class_name NetFake
extends RefCounted
## An in-process stand-in for one room of the Cloudflare server (server/PROTOCOL.md v1), for tests, dev scenes and
## a headless self-check: the same messages, the same rules (LudoRules) and the same hash (StateHash). It is not the
## server: no timers (call room.timeout() / room.step() yourself), no rate limits, no grace period before a bot.
##
##   var room := NetFake.Room.new()
##   var a := NetClient.new(); a.make_transport = room.transport_factory(); a.http_fn = room.http
##   a.join(room.code) ...
##   room.step()                                # one bot action, when a bot is on turn
##   room.timeout()                             # the current player's step times out (auto-act)
## Pipe is the client end of a socket into the room; pipe.drop() cuts it from the server side.

## The client end of one socket.
class Pipe extends NetTransport:
	var room: Room
	var inbox: Array = []
	var reachable := true                 ## false: the socket never opens (no network, unknown room)
	var _state := WebSocketPeer.STATE_CLOSED

	func open(url: String) -> int:
		if room == null or not reachable or not url.contains("/v1/rooms/%s/ws" % room.code):
			_state = WebSocketPeer.STATE_CLOSED
			return OK
		_state = WebSocketPeer.STATE_CONNECTING
		return OK

	func poll() -> void:
		if _state == WebSocketPeer.STATE_CONNECTING:
			_state = WebSocketPeer.STATE_OPEN

	func state() -> int:
		return _state

	func send(text: String) -> int:
		if _state != WebSocketPeer.STATE_OPEN:
			return ERR_UNAVAILABLE
		room.receive(self, text)
		return OK

	func receive() -> Array:
		var out := inbox
		inbox = []
		return out

	func close() -> void:
		if _state == WebSocketPeer.STATE_OPEN:
			room.dropped(self)
		_state = WebSocketPeer.STATE_CLOSED

	## The server (or the network) drops this socket.
	func drop() -> void:
		close()


class Room extends RefCounted:
	var code := "K7QX2M"
	var members: Array = []               ## {id, pid, token, name, avatar, frame, online, pipe}
	var host: Variant = -1                ## member ids are numbers, like the real server's
	var settings := {teams = false, pair_ask = false}
	var S := {}
	var seats: Array = []
	var playing := false
	var finished_once := false
	var n := 0
	var acts: Array = []                  ## every act sent ({n, a, h})
	var rng := RandomNumberGenerator.new()
	var dice: Array = []                  ## scripted rolls, front first (else random)
	var corrupt_next := false             ## tests: the next act carries a wrong hash
	var hold := false                     ## tests: queue outgoing frames instead of delivering them
	var held: Array = []
	var _ids := 0
	var pipes: Array = []

	func _init(code_ := "K7QX2M", seed_ := 7) -> void:
		code = code_
		rng.seed = seed_

	func make_pipe() -> Pipe:
		var p := Pipe.new()
		p.room = self
		pipes.append(p)
		return p

	func transport_factory() -> Callable:
		return func() -> NetTransport: return make_pipe()

	## NetClient.http_fn: POST /v1/rooms, GET /v1/rooms/<code>.
	func http(method: int, path: String) -> Dictionary:
		if method == HTTPClient.METHOD_POST and path == "/v1/rooms":
			return {status = 200, data = {code = code}}
		if path == "/v1/rooms/" + code:
			return {status = 200, data = {code = code, open = not playing and members.size() < 4,
				members = members.size(), started = playing}}
		return {status = 404, data = null}

	# ---------- messages ----------

	func receive(pipe: Pipe, text: String) -> void:
		var m: Variant = JSON.parse_string(text)
		if not m is Dictionary:
			_send(pipe, {t = "error", code = "bad_message", msg = "not json"})
			return
		var t := str(m.get("t", ""))
		if t == "hello":
			_hello(pipe, m)
			return
		var me := _member_of(pipe)
		if me.is_empty():
			_send(pipe, {t = "error", code = "bad_message", msg = "hello first"})
			return
		match t:
			"ping":
				_send(pipe, {t = "pong", now = _now()})
			"settings":
				if me.id != host:
					_send(pipe, {t = "error", code = "not_host", msg = ""})
				elif not playing:
					if m.has("teams"):
						settings.teams = bool(m.teams)
					if m.has("pair_ask"):
						settings.pair_ask = bool(m.pair_ask)
					_lobby()
			"start":
				_start(pipe, me)
			"roll", "move", "pair":
				_request(pipe, me, t, m)
			"back":
				var c := _color(me.id)
				if playing and c >= 0 and S.players[c] == "cpu":
					_act({k = "mode", c = c, mode = "human"})
			"sync_req":
				if playing or finished_once:
					_send(pipe, _sync_msg())
			"leave":
				_leave(me)
			_:
				_send(pipe, {t = "error", code = "bad_message", msg = t})

	func _hello(pipe: Pipe, m: Dictionary) -> void:
		if int(m.get("v", 0)) != 1:
			_send(pipe, {t = "error", code = "version", msg = ""})
			return
		var tok := str(m.get("token", ""))
		for mem in members:
			if tok != "" and mem.token == tok:
				mem.pipe = pipe
				mem.online = true
				for st in seats:
					if st.id == mem.id:
						st.online = true
				_send(pipe, {t = "welcome", token = mem.token, id = mem.id, code = code, host = host})
				if playing:
					_send(pipe, _sync_msg())
					_broadcast({t = "presence", id = mem.id, online = true})
					var c := _color(mem.id)
					if c >= 0 and S.players[c] == "cpu":
						_act({k = "mode", c = c, mode = "human"})
					else:
						_send(pipe, _turn_msg())
				else:
					_lobby()
				return
		if playing:
			_send(pipe, {t = "error", code = "started", msg = ""})
			return
		if members.size() >= 4:
			_send(pipe, {t = "error", code = "full", msg = ""})
			return
		_ids += 1
		var mem := {id = _ids, pid = str(m.get("pid", "")), token = "tok%d_%d" % [_ids, rng.randi() % 100000],
			name = str(m.get("name", "Player")).substr(0, 16), avatar = str(m.get("avatar", "")),
			frame = str(m.get("frame", "")), online = true, pipe = pipe}
		members.append(mem)
		if int(host) < 0:
			host = mem.id
		_send(pipe, {t = "welcome", token = mem.token, id = mem.id, code = code, host = host})
		_lobby()

	func _start(pipe: Pipe, me: Dictionary) -> void:
		if me.id != host:
			_send(pipe, {t = "error", code = "not_host", msg = ""})
			return
		if playing:
			return
		var count := members.size()
		if count < 2:
			_send(pipe, {t = "error", code = "too_few", msg = ""})
			return
		if settings.teams and count != 4:
			_send(pipe, {t = "error", code = "teams_need_4", msg = ""})
			return
		var cols := colors_for(count)
		var players := ["off", "off", "off", "off"]
		seats = []
		for k in count:
			var mem: Dictionary = members[k]
			players[cols[k]] = "human"
			seats.append({color = cols[k], id = mem.id, name = mem.name, avatar = mem.avatar, frame = mem.frame,
				bot = false, online = bool(mem.online)})
		S = LudoRules.new_game(players, bool(settings.teams), {pair_ask = bool(settings.pair_ask)})
		for st in seats:
			S.names[st.color] = st.name
		n = 0
		acts = []
		playing = true
		finished_once = false
		_broadcast({t = "start", n = 0, seats = seats.duplicate(true), state = S.duplicate(true), h = StateHash.of(S)})
		_broadcast(_turn_msg())

	func _request(pipe: Pipe, me: Dictionary, t: String, m: Dictionary) -> void:
		if not playing:
			_send(pipe, {t = "error", code = "bad_action", msg = "no match"})
			return
		var c := _color(me.id)
		if c != int(S.turn) or c < 0:
			_send(pipe, {t = "error", code = "not_your_turn", msg = ""})
			return
		if int(m.get("n", -1)) != n:
			_send(pipe, {t = "error", code = "stale", msg = ""})
			return
		if S.players[c] == "cpu":
			_act({k = "mode", c = c, mode = "human"})   # any request counts as "back"
		match t:
			"roll":
				if S.phase != "roll":
					_send(pipe, {t = "error", code = "bad_action", msg = ""})
					return
				_roll()
			"move":
				var probe: Dictionary = S.duplicate(true)
				if S.phase != "choose" or LudoRules.move(probe, int(m.get("i", -1))).is_empty():
					_send(pipe, {t = "error", code = "bad_action", msg = ""})
					return
				_act({k = "move", c = c, i = int(m.i)})
			"pair":
				if S.phase != "pair_ask":
					_send(pipe, {t = "error", code = "bad_action", msg = ""})
					return
				_act({k = "pair", c = c, yes = bool(m.get("yes", false))})

	func _leave(me: Dictionary) -> void:
		var c := _color(me.id)
		if playing and c >= 0:
			me.online = false
			me.pipe = null
			me.token = ""                     # gone for good
			if S.players[c] == "human":
				_act({k = "mode", c = c, mode = "cpu"})
			_broadcast({t = "presence", id = me.id, online = false})
			return
		members.erase(me)
		if host == me.id:
			host = members[0].id if not members.is_empty() else -1
		_lobby()

	## A socket closed (client or network).
	func dropped(pipe: Pipe) -> void:
		for mem in members:
			if mem.pipe == pipe:
				mem.pipe = null
				mem.online = false
				if playing:
					for st in seats:
						if st.id == mem.id:
							st.online = false
					_broadcast({t = "presence", id = mem.id, online = false})
				else:
					_lobby()

	# ---------- the match ----------

	func _roll() -> void:
		var v: int = int(dice.pop_front()) if not dice.is_empty() else rng.randi_range(1, 6)
		_act({k = "roll", c = int(S.turn), v = v})

	func _act(a: Dictionary) -> void:
		match str(a.k):
			"roll":
				LudoRules.apply_roll(S, int(a.v))
			"move":
				LudoRules.move(S, int(a.i))
			"pair":
				LudoRules.answer_pair(S, bool(a.yes))
			"mode":
				S.players[int(a.c)] = str(a.mode)
				for st in seats:
					if int(st.color) == int(a.c):
						st.bot = a.mode == "cpu"
		var h := StateHash.of(S)
		if corrupt_next:
			corrupt_next = false
			h = "00000000"
		var msg := {t = "act", n = n, a = a, h = h}
		n += 1
		acts.append(msg)
		_broadcast(msg)
		if S.phase == "over":
			playing = false
			finished_once = true
			_broadcast({t = "over", finished = S.finished.duplicate(), winner = int(S.winner)})
		elif str(a.k) != "mode":
			_broadcast(_turn_msg())

	## One bot action when a bot is on turn (true if it acted).
	func step() -> bool:
		if not playing or S.players[int(S.turn)] != "cpu":
			return false
		_auto()
		return true

	## The current player's step times out: the server acts for them (roll; auto move or the AI's; pair = yes).
	func timeout() -> void:
		if playing:
			_auto()

	func _auto() -> void:
		var c := int(S.turn)
		match str(S.phase):
			"roll":
				_roll()
			"choose":
				var i := LudoRules.auto_move_token(S)
				if i < 0:
					i = LudoRules.pick_ai(S, LudoRules.units(S).map(func(u): return u.token), rng, "easy")
				_act({k = "move", c = c, i = i})
			"pair_ask":
				_act({k = "pair", c = c, yes = true})

	# ---------- out ----------

	func _sync_msg() -> Dictionary:
		return {t = "sync", n = n, seats = seats.duplicate(true), state = S.duplicate(true), h = StateHash.of(S)}

	func _turn_msg() -> Dictionary:
		var now := _now()
		return {t = "turn", c = int(S.turn), deadline = now + NetLudo.phase_sec(str(S.phase)) * 1000.0, now = now}

	func _lobby() -> void:
		var cols := colors_for(members.size())
		var list := []
		for k in members.size():
			var mem: Dictionary = members[k]
			list.append({id = mem.id, name = mem.name, avatar = mem.avatar, frame = mem.frame, online = mem.online,
				color = cols[k] if k < cols.size() else -1})
		_broadcast({t = "lobby", code = code, host = host, members = list, settings = settings.duplicate(), max = 4})

	func _broadcast(msg: Dictionary) -> void:
		for mem in members:
			if mem.pipe != null:
				_send(mem.pipe, msg)

	func _send(pipe: Pipe, msg: Dictionary) -> void:
		var text := JSON.stringify(msg)
		if hold:
			held.append([pipe, text])
		else:
			pipe.inbox.append(text)

	## Deliver the frames held back while `hold` was on.
	func release() -> void:
		for h in held:
			(h[0] as Pipe).inbox.append(h[1])
		held = []

	func _member_of(pipe: Pipe) -> Dictionary:
		for mem in members:
			if mem.pipe == pipe:
				return mem
		return {}

	func _color(id: Variant) -> int:
		for st in seats:
			if st.id == id:
				return int(st.color)
		return -1

	static func _now() -> float:
		return floorf(Time.get_unix_time_from_system() * 1000.0)

	## The playing colours for a member count (PROTOCOL.md "Colours").
	static func colors_for(count: int) -> Array:
		if count <= 2:
			return [0, 2]
		if count == 3:
			return [0, 1, 2]
		return [0, 1, 2, 3]
