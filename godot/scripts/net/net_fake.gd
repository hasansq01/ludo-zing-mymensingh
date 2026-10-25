class_name NetFake
extends RefCounted
## An in-process stand-in for the Cloudflare server (server/PROTOCOL.md v1), for tests, dev scenes and a headless
## self-check: the same messages, the same rules (LudoRules / SnakesLaddersRules) and the same hashes (StateHash /
## SLStateHash). It is not the server: no timers (call room.timeout() / room.step() / mm.fill() yourself), no rate
## limits, no grace period before a bot.
##
## One friend room (as before):
##   var room := NetFake.Room.new()
##   var a := NetClient.new(); a.make_transport = room.transport_factory(); a.http_fn = room.http
##   a.join(room.code) ...
##   room.step()                                # one bot (or ghost) action, when one is on turn
##   room.timeout()                             # the current player's step times out (auto-act)
## Rooms + quick match (a Hub routes each socket by its URL: /v1/rooms/<code>/ws or /v1/quick/ws?game=&players=):
##   var hub := NetFake.Hub.new()
##   net.make_transport = hub.transport_factory(); net.http_fn = hub.http
##   hub.mm.fill("ludo", 2)                     # the oldest waiting people get a table now, ghosts fill the rest
##   var room := hub.rooms[code]
## Quick rooms (Room.quick): no lobby, no host (welcome.host -1), settings / start -> bad_action, seats reserved by
## token, the match starts when every matched person has said hello (or start_quick(): the server's 10 s), ghost
## seats look exactly like people (players[c] = "human", bot false, online true) and are played by step().
## Play on (PROTOCOL.md "Play on after the first finish"): `over` only at the end of the game; after an act (and a
## leave) the room sends {k: "end"} when no real person (not a ghost, not left) is left unfinished while one is still
## seated, like the server.
## Emotes (server/EMOTES.md): {t: "emote", id} is relayed to the others as {t: "emote", c, id} (lobby: c = -1 and
## member), after the server's checks: the member owns the emote's pack (Starter always; a member's packs are
## mem.emote_sets, set them in a test) and at most 1 per EMOTE_GAP ms and EMOTE_MAX per EMOTE_WINDOW ms (clock_ms()
## is the clock: set `clock` to fake it); refusals are {t: "error", code: "emote_locked" | "emote_rate"}.
## ghost_emote(c, id) sends a ghost's (or any seat's) emote to everyone, exactly like a person's.
## Pipe is the client end of a socket; pipe.drop() cuts it from the server side.

const GHOST_NAMES := ["Rafi", "Mitu", "Tanvir", "Nusrat", "Sakib", "Ayesha", "Shuvo", "Tania"]
const GHOST_AVATARS := ["ch-rafi", "ch-mim", "ch-tanvir", "pawn-green", "pawn-blue", "ch-nusrat"]


## The client end of one socket.
class Pipe extends NetTransport:
	var room: Room
	var hub: Hub
	var mm: Matchmaker
	var url := ""
	var inbox: Array = []
	var reachable := true                 ## false: the socket never opens (no network, unknown room)
	var _state := WebSocketPeer.STATE_CLOSED

	func open(url_: String) -> int:
		url = url_
		if hub != null:
			room = null
			mm = null
			if url.contains("/v1/quick/ws"):
				mm = hub.mm
			else:
				var at := url.find("/v1/rooms/")
				if at >= 0:
					var c := url.substr(at + 10, 6)
					room = hub.rooms.get(c)
		if not reachable or (room == null and mm == null) or (room != null and not url.contains("/v1/rooms/%s/ws" % room.code)):
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
		if mm != null:
			mm.receive(self, text)
		else:
			room.receive(self, text)
		return OK

	func receive() -> Array:
		var out := inbox
		inbox = []
		return out

	func close() -> void:
		if _state == WebSocketPeer.STATE_OPEN:
			if mm != null:
				mm.dropped(self)
			elif room != null:
				room.dropped(self)
		_state = WebSocketPeer.STATE_CLOSED

	## The server (or the network) drops this socket.
	func drop() -> void:
		close()

	## The server closes this socket after its last message (the frames already sent stay readable).
	func server_close() -> void:
		_state = WebSocketPeer.STATE_CLOSED

	func is_open() -> bool:
		return _state == WebSocketPeer.STATE_OPEN


class Room extends RefCounted:
	var code := "K7QX2M"
	var members: Array = []               ## {id, pid, token, name, avatar, frame, level, online, pipe, ghost}
	var host: Variant = -1                ## member ids are numbers, like the real server's
	var settings := {teams = false, pair_ask = false, game = "ludo"}
	var game := "ludo"                    ## the match's game (settings.game at the start)
	var quick := false                    ## a quick-match room (see the class notes)
	var S := {}
	var seats: Array = []
	var playing := false
	var finished_once := false
	var n := 0
	var acts: Array = []                  ## every act sent ({n, a, h})
	var aways: Array = []                 ## every {t: "away"} seen: {id, on} (the app went to the background / came back)
	var rng := RandomNumberGenerator.new()
	var dice: Array = []                  ## scripted rolls, front first (else random)
	var corrupt_next := false             ## tests: the next act carries a wrong hash
	var hold := false                     ## tests: queue outgoing frames instead of delivering them
	var held: Array = []
	var _ids := 0
	var pipes: Array = []
	var clock := Callable()               ## () -> ms for the emote rate limit (Time.get_ticks_msec by default)
	const EMOTE_GAP := 2000
	const EMOTE_WINDOW := 30000
	const EMOTE_MAX := 6

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
			return {status = 200, data = info()}
		return {status = 404, data = null}

	## GET /v1/rooms/<code>'s answer.
	func info() -> Dictionary:
		return {code = code, open = not quick and not playing and members.size() < 4, members = members.size(), started = playing}

	## A quick room: these people (seat order: humans then ghosts, as given) get reserved seats; returns their
	## tokens by account. humans: [{account, pid, name, avatar, frame, level}]; ghosts: how many seats to fill.
	func init_quick(g: String, humans: Array, ghosts: int) -> Dictionary:
		quick = true
		host = -1
		settings.game = g
		var tokens := {}
		var taken := {}
		for h: Dictionary in humans:
			taken[str(h.get("name", "")).to_lower()] = true
		for h: Dictionary in humans:
			_ids += 1
			var tok := "q%d_%d" % [_ids, rng.randi() % 100000]
			members.append({id = _ids, pid = str(h.get("pid", "")), token = tok, name = str(h.get("name", "Player")),
				avatar = str(h.get("avatar", "")), frame = str(h.get("frame", "")), level = int(h.get("level", 1)),
				online = false, pipe = null, ghost = false, account = str(h.get("account", ""))})
			tokens[str(h.get("account", ""))] = tok
		for k in ghosts:
			_ids += 1
			var nm: String = GHOST_NAMES[(k + rng.randi() % GHOST_NAMES.size()) % GHOST_NAMES.size()]
			while taken.has(nm.to_lower()):
				nm = GHOST_NAMES[(GHOST_NAMES.find(nm) + 1) % GHOST_NAMES.size()]
			taken[nm.to_lower()] = true
			members.append({id = _ids, pid = "", token = "", name = nm, avatar = GHOST_AVATARS[rng.randi() % GHOST_AVATARS.size()],
				frame = "classic", level = 1 + rng.randi() % 12, online = true, pipe = null, ghost = true})
		return tokens

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
				if quick or playing:
					_send(pipe, {t = "error", code = "bad_action", msg = "no settings now"})
				elif me.id != host:
					_send(pipe, {t = "error", code = "not_host", msg = ""})
				else:
					if m.has("teams"):
						settings.teams = bool(m.teams)
					if m.has("pair_ask"):
						settings.pair_ask = bool(m.pair_ask)
					if m.has("game"):
						if not str(m.game) in ["ludo", "sl"]:
							_send(pipe, {t = "error", code = "bad_message", msg = "game"})
							return
						settings.game = str(m.game)
					_lobby()
			"start":
				if quick:
					_send(pipe, {t = "error", code = "bad_action", msg = "quick matches have no rematch: queue again"})
				else:
					_start(pipe, me)
			"roll", "move", "pair":
				_request(pipe, me, t, m)
			"back":
				var c := _color(me.id)
				if playing and c >= 0 and is_cpu(c):
					_act({k = "mode", c = c, mode = "human"})
			"sync_req":
				if playing or finished_once:
					_send(pipe, _sync_msg())
			"emote":
				_emote(pipe, me, str(m.get("id", "")))
			"away":
				aways.append({id = me.id, on = bool(m.get("on", false))})
			"leave":
				_leave(me)
			_:
				_send(pipe, {t = "error", code = "bad_message", msg = t})

	## A member's emote: the pack check, the rate limit, then to everyone else.
	func _emote(pipe: Pipe, me: Dictionary, id: String) -> void:
		var pack := str(EmoteArt.info(id).get("set", ""))
		if pack == "":
			_send(pipe, {t = "error", code = "bad_message", msg = "emote"})
			return
		var owned: Array = me.get("emote_sets", ["starter"])
		if pack != "starter" and not owned.has(pack):
			_send(pipe, {t = "error", code = "emote_locked", msg = ""})
			return
		var now := clock_ms()
		var times: Array = (me.get("emote_times", []) as Array).filter(func(x): return now - int(x) < EMOTE_WINDOW)
		if (not times.is_empty() and now - int(times.back()) < EMOTE_GAP) or times.size() >= EMOTE_MAX:
			me.emote_times = times
			_send(pipe, {t = "error", code = "emote_rate", msg = ""})
			return
		times.append(now)
		me.emote_times = times
		var c := _color(me.id) if playing or finished_once else -1
		var msg := {t = "emote", c = c, id = id}
		if c < 0:
			msg.member = me.id
		for mem in members:
			if mem.pipe != null and mem.pipe != pipe:
				_send(mem.pipe, msg)

	## Colour c's emote to every connected member (a ghost reacting, like the server's ghosts).
	func ghost_emote(c: int, id: String) -> void:
		_broadcast({t = "emote", c = c, id = id})

	func clock_ms() -> int:
		return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()

	func _hello(pipe: Pipe, m: Dictionary) -> void:
		if int(m.get("v", 0)) != 1:
			_send(pipe, {t = "error", code = "version", msg = ""})
			return
		var tok := str(m.get("token", ""))
		for mem in members:
			if tok != "" and mem.token == tok and not bool(mem.get("ghost", false)):
				if mem.pipe != null and mem.pipe != pipe:
					(mem.pipe as Pipe).server_close()   # the member's older socket (4001)
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
					if c >= 0 and is_cpu(c):
						_act({k = "mode", c = c, mode = "human"})
					else:
						_send(pipe, _turn_msg())
				elif quick:
					if finished_once:
						_send(pipe, _sync_msg())
						_send(pipe, _over_msg())
					elif members.all(func(x): return bool(x.get("ghost", false)) or x.online):
						start_quick()
				else:
					if finished_once:
						_send(pipe, _sync_msg())
						_send(pipe, _over_msg())
					_lobby()
				return
		if quick:
			_send(pipe, {t = "error", code = "full", msg = "the room is full"})
			pipe.server_close()
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
			frame = str(m.get("frame", "")), level = 1, online = true, pipe = pipe, ghost = false,
			session = str(m.get("session", ""))}
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
		if str(settings.get("game", "ludo")) == "ludo" and settings.teams and count != 4:
			_send(pipe, {t = "error", code = "teams_need_4", msg = ""})
			return
		_deal()

	## The quick room's start (every matched person connected, or the server's 10 s).
	func start_quick() -> void:
		if quick and not playing and not finished_once:
			_deal()

	## Seats the members in join order and broadcasts `start`.
	func _deal() -> void:
		game = str(settings.get("game", "ludo"))
		var count := members.size()
		var cols := seat_colors(game, count)
		seats = []
		for k in count:
			var mem: Dictionary = members[k]
			var st := {color = cols[k], id = mem.id, name = mem.name, avatar = mem.avatar, frame = mem.frame,
				level = int(mem.get("level", 1)), bot = false, online = bool(mem.online)}
			seats.append(st)
		if game == "sl":
			S = SnakesLaddersRules.new_game("local", count, 0, {need_one = false})
			S.mode = "online"
			for k in count:
				var p: Dictionary = S.players[k]
				p.c = cols[k]
				p.name = members[k].name
				p.you = false
				p.cpu = false
		else:
			var players := ["off", "off", "off", "off"]
			for k in count:
				players[cols[k]] = "human"
			S = LudoRules.new_game(players, bool(settings.teams), {pair_ask = bool(settings.pair_ask)})
			for st in seats:
				S.names[st.color] = st.name
		n = 0
		acts = []
		playing = true
		finished_once = false
		_broadcast({t = "start", n = 0, game = game, seats = seats.duplicate(true), state = S.duplicate(true), h = state_hash()})
		_broadcast(_turn_msg())

	func _request(pipe: Pipe, me: Dictionary, t: String, m: Dictionary) -> void:
		if not playing:
			_send(pipe, {t = "error", code = "bad_action", msg = "no match"})
			return
		if int(m.get("n", -1)) != n:
			_send(pipe, {t = "error", code = "stale", msg = ""})
			return
		var c := _color(me.id)
		if c != turn_color() or c < 0:
			_send(pipe, {t = "error", code = "not_your_turn", msg = ""})
			return
		if game == "sl" and t != "roll":
			_send(pipe, {t = "error", code = "bad_action", msg = "snakes & ladders only has roll"})
			return
		if is_cpu(c):
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
			for st in seats:
				if st.id == me.id:
					st.online = false
			for st in seats:
				if st.id == me.id:
					st.left = true
			if not is_cpu(c) and not ranked().has(c):
				_act({k = "mode", c = c, mode = "cpu"})
			_broadcast({t = "presence", id = me.id, online = false})
			if only_bots_left():
				_act({k = "end"})
			return
		members.erase(me)
		if host == me.id:
			host = members[0].id if not members.is_empty() and not quick else -1
		if not quick:
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
				elif not quick:
					_lobby()

	# ---------- the rules, by game ----------

	static func seat_colors(g: String, count: int) -> Array:
		if g == "sl":
			return [0, 1, 2, 3].slice(0, maxi(1, count))
		return colors_for(count)

	## The colour whose turn it is.
	func turn_color() -> int:
		if S.is_empty():
			return -1
		if game == "sl":
			return int(S.players[int(S.turn)].c)
		return int(S.turn)

	func is_cpu(c: int) -> bool:
		if game == "sl":
			for p in S.players:
				if int(p.c) == c:
					return bool(p.cpu)
			return false
		return c >= 0 and c < 4 and S.players[c] == "cpu"

	## Colour c is a ghost seat (quick rooms): the server plays it like a person.
	func is_ghost(c: int) -> bool:
		for st in seats:
			if int(st.color) == c:
				for mem in members:
					if mem.id == st.id:
						return bool(mem.get("ghost", false))
		return false

	func state_hash() -> String:
		return SLStateHash.of(S) if game == "sl" else StateHash.of(S)

	func _apply(a: Dictionary) -> void:
		match str(a.k):
			"roll":
				if game == "sl":
					SnakesLaddersRules.apply_roll(S, int(a.v))
				else:
					LudoRules.apply_roll(S, int(a.v))
			"move":
				LudoRules.move(S, int(a.i))
			"pair":
				LudoRules.answer_pair(S, bool(a.yes))
			"end":
				if game == "sl":
					SnakesLaddersRules.end_game(S)
				else:
					LudoRules.end_game(S)
			"mode":
				var cpu: bool = a.mode == "cpu"
				if game == "sl":
					for p in S.players:
						if int(p.c) == int(a.c):
							p.cpu = cpu
				else:
					S.players[int(a.c)] = str(a.mode)
				for st in seats:
					if int(st.color) == int(a.c):
						st.bot = cpu

	# ---------- the match ----------

	func _roll() -> void:
		var v: int = int(dice.pop_front()) if not dice.is_empty() else rng.randi_range(1, 6)
		_act({k = "roll", c = turn_color(), v = v})

	func _act(a: Dictionary) -> void:
		_apply(a)
		var h := state_hash()
		if corrupt_next:
			corrupt_next = false
			h = "00000000"
		var msg := {t = "act", n = n, a = a, h = h}
		n += 1
		acts.append(msg)
		_broadcast(msg)
		if S.phase != "over" and str(a.k) != "mode" and only_bots_left():
			_act({k = "end"})                  # (that act sends `over`)
			return
		if S.phase == "over":
			playing = false
			finished_once = true
			_broadcast(_over_msg())
			if not quick:
				_lobby()
		elif str(a.k) != "mode":
			_broadcast(_turn_msg())

	## Colours whose side has its place now (S&L: the players who reached 100; Ludo Teams: only at the end).
	func ranked() -> Array:
		if S.is_empty():
			return []
		if game == "sl":
			return (S.get("finished", []) as Array).map(func(k): return int(S.players[int(k)].c))
		if S.phase == "over" or not bool(S.teams):
			return (S.get("finished", []) as Array).map(func(x): return int(x))
		return []

	## Play on: no real person (not a ghost, not left) is unfinished, while the result is for someone (a person still
	## seated, or one who finished and left since).
	func only_bots_left() -> bool:
		if not playing or S.is_empty() or S.phase == "over":
			return false
		var open := []
		if game == "sl":
			for k in S.players.size():
				if not (S.get("finished", []) as Array).has(k):
					open.append(int(S.players[k].c))
		else:
			for c in 4:
				if S.players[c] != "off" and not LudoRules.side_done(S, c):
					open.append(c)
		var done := ranked()
		var someone := false                   # the result is for someone: seated, or finished (and left since)
		for st in seats:
			if is_ghost(int(st.color)):
				continue
			var gone := bool(st.get("left", false))
			if not gone and open.has(int(st.color)):
				return false
			someone = someone or not gone or done.has(int(st.color))
		return someone

	## One bot or ghost action when one is on turn (true if it acted).
	func step() -> bool:
		if not playing:
			return false
		var c := turn_color()
		if not is_cpu(c) and not is_ghost(c):
			return false
		_auto(not is_cpu(c))
		return true

	## The current player's step times out: the server acts for them (roll; auto move or the AI's; pair = yes).
	func timeout() -> void:
		if playing:
			_auto()

	func _auto(ghost := false) -> void:
		var c := turn_color()
		match str(S.phase):
			"roll":
				_roll()
			"choose":
				var i := LudoRules.auto_move_token(S)
				if i < 0:
					i = LudoRules.pick_ai(S, LudoRules.units(S).map(func(u): return u.token), rng, "normal" if ghost else "easy")
				_act({k = "move", c = c, i = i})
			"pair_ask":
				_act({k = "pair", c = c, yes = true})

	# ---------- out ----------

	func _sync_msg() -> Dictionary:
		return {t = "sync", n = n, game = game, seats = seats.duplicate(true), state = S.duplicate(true), h = state_hash()}

	func _turn_msg() -> Dictionary:
		var now := _now()
		return {t = "turn", c = turn_color(), deadline = now + NetLudo.phase_sec(str(S.phase)) * 1000.0, now = now}

	func _over_msg() -> Dictionary:
		if game == "sl":
			var w := int(S.winner)
			var wc := int(S.players[w].c) if w >= 0 else -1
			return {t = "over", finished = ranked(), winner = wc, standings = SnakesLaddersRules.standings(S)}
		return {t = "over", finished = S.finished.duplicate(), winner = int(S.winner), standings = LudoRules.standings(S)}

	func _lobby() -> void:
		if quick:
			return
		var cols := seat_colors(str(settings.get("game", "ludo")), members.size())
		var list := []
		for k in members.size():
			var mem: Dictionary = members[k]
			list.append({id = mem.id, name = mem.name, avatar = mem.avatar, frame = mem.frame, level = int(mem.get("level", 1)),
				online = mem.online, color = cols[k] if k < cols.size() else -1})
		_broadcast({t = "lobby", code = code, host = host, members = list, settings = settings.duplicate(), max = 4,
			status = "playing" if playing else ("over" if finished_once else "lobby")})

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

	## The playing colours for a member count in Ludo (PROTOCOL.md "Colours").
	static func colors_for(count: int) -> Array:
		if count <= 2:
			return [0, 2]
		if count == 3:
			return [0, 1, 2]
		return [0, 1, 2, 3]


## The quick-match queues (one per game + size, like the server's Matchmaker objects, here in one place).
class Matchmaker extends RefCounted:
	var hub: Hub
	var waiting: Array = []               ## {pipe, account, pid, name, avatar, frame, level, game, size, since}
	var maintenance := ""                 ## non-empty: every hello gets `error maintenance` with this text
	var banned: Array = []                ## sessions / pids refused with `error banned`
	var bad_sessions: Array = []          ## sessions refused with `error session` (expired)
	var eta := 6
	var hellos: Array = []                ## every hello received (tests)
	var cancels := 0
	var _seq := 0

	func receive(pipe: Pipe, text: String) -> void:
		var m: Variant = JSON.parse_string(text)
		if not m is Dictionary:
			_send(pipe, {t = "error", code = "bad_message", msg = "not JSON"})
			return
		var t := str(m.get("t", ""))
		if t == "ping":
			_send(pipe, {t = "pong", now = Room._now()})
			return
		var e := _entry(pipe)
		if t == "hello":
			if not e.is_empty():
				_send(pipe, {t = "error", code = "bad_message", msg = "already said hello"})
				return
			_hello(pipe, m)
			return
		if e.is_empty():
			_send(pipe, {t = "error", code = "bad_message", msg = "say hello first"})
			return
		if t == "cancel":
			cancels += 1
			waiting.erase(e)
			_send(pipe, {t = "cancelled"})
			pipe.server_close()
			_positions(str(e.game), int(e.size))
			return
		_send(pipe, {t = "error", code = "bad_message", msg = t})

	func _hello(pipe: Pipe, m: Dictionary) -> void:
		hellos.append(m)
		if int(m.get("v", 0)) != 1:
			_fatal(pipe, "version", "unsupported protocol version")
			return
		var pid := str(m.get("pid", ""))
		if pid.length() < 16:
			_fatal(pipe, "bad_message", "pid")
			return
		var sess := str(m.get("session", ""))
		if sess == "":
			_fatal(pipe, "session", "quick match needs a session (POST /v1/auth/guest)")
			return
		if maintenance != "":
			_fatal(pipe, "maintenance", maintenance)
			return
		if sess in bad_sessions:
			_fatal(pipe, "session", "your session is not valid: sign in again")
			return
		if sess in banned or pid in banned:
			_fatal(pipe, "banned", "You are banned from online play.")
			return
		var g := _query(pipe.url, "game", "ludo")
		var size := int(_query(pipe.url, "players", "2"))
		var acc := "acc:" + sess
		var since := Time.get_ticks_msec()
		for o: Dictionary in waiting.duplicate():
			if o.account == acc:
				since = int(o.since)                # a newer connection takes the older one's place
				waiting.erase(o)
				_send(o.pipe, {t = "error", code = "replaced", msg = "you queued again on another connection"})
				(o.pipe as Pipe).server_close()
		_seq += 1
		waiting.append({pipe = pipe, account = acc, pid = pid, name = str(m.get("name", "Player")), avatar = str(m.get("avatar", "")),
			frame = str(m.get("frame", "")), level = 3, game = g, size = size, since = since, seq = _seq})
		waiting.sort_custom(func(a, b): return a.since < b.since or (a.since == b.since and a.seq < b.seq))
		var q := queue(g, size)
		if q.size() >= size:
			_group(q.slice(0, size), 0)
		_positions(g, size)

	## The people waiting for one game + size, first come first served.
	func queue(g: String, size: int) -> Array:
		return waiting.filter(func(e): return e.game == g and int(e.size) == size)

	## The oldest waiting people of that queue get a table now; ghosts take the empty seats (the server's 4-9 s).
	## Returns the room ({} when nobody waits).
	func fill(g: String, size: int) -> Room:
		var q := queue(g, size)
		if q.is_empty():
			return null
		var take := q.slice(0, mini(size, q.size()))
		var r := _group(take, size - take.size())
		_positions(g, size)
		return r

	func _group(entries: Array, ghosts: int) -> Room:
		var code := hub.next_code()
		var room := hub.add_room(code)
		var humans := []
		for e: Dictionary in entries:
			humans.append({account = e.account, pid = e.pid, name = e.name, avatar = e.avatar, frame = e.frame, level = e.level})
		var tokens := room.init_quick(str(entries[0].game), humans, ghosts)
		for e: Dictionary in entries:
			waiting.erase(e)
			_send(e.pipe, {t = "matched", code = code, token = tokens[e.account]})
			(e.pipe as Pipe).server_close()
		return room

	func _positions(g: String, size: int) -> void:
		var q := queue(g, size)
		for k in q.size():
			var e: Dictionary = q[k]
			if int(e.get("pos", 0)) != k + 1:
				e.pos = k + 1
				_send(e.pipe, {t = "queued", position = k + 1, eta_s = eta})

	func dropped(pipe: Pipe) -> void:
		var e := _entry(pipe)
		if not e.is_empty():
			waiting.erase(e)
			_positions(str(e.game), int(e.size))

	func _entry(pipe: Pipe) -> Dictionary:
		for e: Dictionary in waiting:
			if e.pipe == pipe:
				return e
		return {}

	func _fatal(pipe: Pipe, code: String, msg: String) -> void:
		_send(pipe, {t = "error", code = code, msg = msg})
		pipe.server_close()

	func _send(pipe: Pipe, msg: Dictionary) -> void:
		pipe.inbox.append(JSON.stringify(msg))

	static func _query(url: String, key: String, def: String) -> String:
		var at := url.find("?")
		if at < 0:
			return def
		for part in url.substr(at + 1).split("&"):
			var kv := part.split("=")
			if kv.size() == 2 and kv[0] == key:
				return kv[1]
		return def


## Rooms by code plus the matchmaker, one transport for both (NetClient and NetQuick share it).
class Hub extends RefCounted:
	var rooms := {}
	var mm := Matchmaker.new()
	var pipes: Array = []
	var seed_base := 7
	var _codes := 0

	func _init(seed_ := 7) -> void:
		seed_base = seed_
		mm.hub = self

	## A fresh room code (QM + four code letters, distinct for the hub's first million rooms).
	func next_code() -> String:
		_codes += 1
		var a := NetClient.ALPHABET
		var k := _codes * 7919
		var out := "QM"
		for i in 4:
			out += a[k % a.length()]
			k /= a.length()
		return out

	func add_room(code: String) -> Room:
		var r := Room.new(code, seed_base + _codes)
		rooms[code] = r
		return r

	func make_pipe() -> Pipe:
		var p := Pipe.new()
		p.hub = self
		pipes.append(p)
		return p

	func transport_factory() -> Callable:
		return func() -> NetTransport: return make_pipe()

	## NetClient.http_fn: POST /v1/rooms (a new room), GET /v1/rooms/<code>.
	func http(method: int, path: String) -> Dictionary:
		if method == HTTPClient.METHOD_POST and path == "/v1/rooms":
			var c := next_code()
			add_room(c)
			return {status = 200, data = {code = c}}
		if path.begins_with("/v1/rooms/"):
			var r: Room = rooms.get(path.substr(10, 6))
			if r:
				return {status = 200, data = r.info()}
		return {status = 404, data = null}
