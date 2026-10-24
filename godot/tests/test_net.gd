extends "res://tests/test_suite.gd"
## Online rooms, client side (server/PROTOCOL.md v1): NetClient's pure helpers, the protocol flow against an
## in-process fake room (NetFake: hello / welcome / lobby / start / act / sync / over, errors, reconnect with the
## token, ping / pong), and NetLudo's replica bookkeeping (act queue order, duplicates, gaps, hash mismatch ->
## sync_req -> sync). Whole games are played through two clients with every hash checked. Nothing here touches
## the Save autoload or the network.

var _pairs := 0

func run() -> void:
	_helpers()
	_flow()
	_errors()
	_replica()
	_full_game(2, false, false, 11)
	_full_game(3, false, true, 23)
	_full_game(4, true, true, 5)
	check("full games: \"Ask before pairing\" prompts were asked and answered online", _pairs > 0, _pairs)
	_leaver_game()
	_reconnect()


# ---------- harness ----------

func client(room: NetFake.Room, name: String) -> NetClient:
	var c := NetClient.new()
	c.use_save = false
	c.prefs = {}
	c.url_base = "ws://fake"
	c.profile_fn = func() -> Dictionary: return {name = name, avatar = "pawn-blue", frame = "classic"}
	c.make_transport = room.transport_factory()
	c.http_fn = room.http
	var log := []
	c.set_meta("log", log)
	c.message.connect(func(m: Dictionary): log.append(m))
	return c

func pump(cs: Array, times := 3) -> void:
	for k in times:
		for c: NetClient in cs:
			c._process(0.0)

func got(c: NetClient, t: String) -> Array:
	return (c.get_meta("log") as Array).filter(func(m): return m.get("t") == t)

func last(c: NetClient, t: String) -> Dictionary:
	var a := got(c, t)
	return a[-1] if not a.is_empty() else {}

func free_all(cs: Array) -> void:
	for c: NetClient in cs:
		c.free()


# ---------- pure helpers ----------

func _helpers() -> void:
	check("code: upper case, alphabet only", NetClient.clean_code(" k7q-x2m ") == "K7QX2M", NetClient.clean_code(" k7q-x2m "))
	check("code: 0 O 1 I L are not code letters", NetClient.clean_code("O0I1L5") == "5")
	check("code: capped at 6", NetClient.clean_code("ABCDEFGH") == "ABCDEF")
	check("code: valid needs 6", NetClient.valid_code("K7QX2M") and not NetClient.valid_code("K7QX2") and not NetClient.valid_code("k7qx2m"))
	check("url: --net= wins", NetClient.resolve_url({net_url = "ws://a:1"}, PackedStringArray(["--net=ws://localhost:8787/"])) == "ws://localhost:8787")
	check("url: then prefs.net_url", NetClient.resolve_url({net_url = "ws://10.0.2.2:8787"}) == "ws://10.0.2.2:8787")
	check("url: else production", NetClient.resolve_url({}) == NetClient.PROD_URL and NetClient.PROD_URL.begins_with("wss://"))
	check("http base from ws", NetClient.http_base("wss://x.workers.dev") == "https://x.workers.dev" and NetClient.http_base("ws://localhost:8787/") == "http://localhost:8787")
	var p := {}
	var pid := NetClient.ensure_pid(p)
	check("ids: numbers and text are the same id", NetClient.id_str(3.0) == "3" and NetClient.id_str(3) == "3" and NetClient.id_str("m3") == "m3" and NetClient.id_str(null) == "")
	check("pid: 16+ chars, kept", pid.length() >= 16 and NetClient.ensure_pid(p) == pid and p.net_pid == pid)
	check("saved room: needs a code and a token", NetClient.saved_room({net_room = {code = "K7QX2M", token = "t"}}).code == "K7QX2M"
		and NetClient.saved_room({net_room = {code = "K7QX2M", token = ""}}).is_empty() and NetClient.saved_room({}).is_empty())
	check("wire name: trimmed, 16 max, never \"You\"", NetClient.wire_name("  Rafi   Khan ") == "Rafi Khan" and NetClient.wire_name("You") == "Player"
		and NetClient.wire_name("ABCDEFGHIJKLMNOPQRS").length() == 16 and NetClient.wire_name("") == "Player")
	var texts := ["not_found", "full", "started", "no_connection", "version", "too_few", "teams_need_4", "nope"].map(func(c): return NetClient.error_text(c))
	check("error copy: friendly, typographic apostrophes, no \"token\"", texts.all(func(t): return t != "" and not t.contains("'") and not t.to_lower().contains("token") and t[0] == t[0].to_upper()), texts)
	check("phase seconds", NetLudo.phase_sec("roll") == 15.0 and NetLudo.phase_sec("choose") == 20.0 and NetLudo.phase_sec("pair_ask") == 10.0)
	var fresh := LudoRules.new_game(["human", "off", "human", "off"])
	check("hash: the PROTOCOL.md example string", StateHash.input(fresh) == "-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1||0|0|0|roll|-1|0000||human,off,human,off|", StateHash.input(fresh))
	check("hash: the shared example hashes to 86cf2abe", StateHash.of(fresh) == "86cf2abe", StateHash.of(fresh))
	var loc := NetLudo.localize(JSON.parse_string(JSON.stringify(fresh)), [{color = 0, id = "a", name = "Ana"}, {color = 2, id = "b", name = "Bo"}], "b")
	check("hash: a localized replica (JSON floats, S.me, \"You\", seat names) hashes the same", StateHash.of(loc) == "86cf2abe" and loc.names == ["Ana", "", "You", ""], [StateHash.of(loc), loc.names])
	check("fake colours: 2 opposite, 3, 4", NetFake.Room.colors_for(2) == [0, 2] and NetFake.Room.colors_for(3) == [0, 1, 2] and NetFake.Room.colors_for(4) == [0, 1, 2, 3])


# ---------- hello, lobby, start ----------

func _flow() -> void:
	var room := NetFake.Room.new()
	var a := client(room, "Ana")
	var b := client(room, "Bo")
	var cr: Dictionary = await a.create_room()
	check("create room: the code", cr.ok and cr.code == room.code, cr)
	var ck: Dictionary = await a.check_room("k7qx2m")
	check("check room: open, no members yet", ck.ok and ck.open and ck.members == 0 and not ck.started, ck)
	var nf: Dictionary = await a.check_room("ZZZZZZ")
	check("check room: unknown code -> not_found", not nf.ok and nf.error == "not_found", nf)
	a.join(cr.code)
	check("joining: connecting", a.status == "connecting")
	pump([a])
	var hello: Dictionary = a.log_sent[0]
	check("hello first: v 1, pid, name, avatar, frame, no token", hello.t == "hello" and hello.v == 1 and str(hello.pid).length() >= 16
		and hello.name == "Ana" and hello.avatar == "pawn-blue" and hello.frame == "classic" and not hello.has("token"), hello)
	check("welcomed: open, member id, host = you", a.status == "open" and a.member_id != "" and a.is_host(), [a.status, a.member_id, a.host_id])
	check("the room token is kept for a restart", NetClient.saved_room(a.prefs).get("token", "") == a.token and a.token != "")
	b.join(room.code)
	pump([a, b])
	var lob := last(a, "lobby")
	check("lobby: two members in join order, colours Red / Yellow", lob.members.size() == 2 and lob.members[0].name == "Ana"
		and lob.members[1].name == "Bo" and int(lob.members[0].color) == 0 and int(lob.members[1].color) == 2, lob)
	check("B is not host", not b.is_host() and b.host_id == a.member_id)
	b.send_msg({t = "start"})
	pump([a, b])
	check("start by a guest: not_host", last(b, "error").get("code") == "not_host")
	a.send_msg({t = "settings", pair_ask = true})
	pump([a, b])
	check("settings reach everyone", bool(last(b, "lobby").settings.pair_ask))
	a.send_msg({t = "settings", teams = true})
	a.send_msg({t = "start"})
	pump([a, b])
	check("teams with 2: teams_need_4", last(a, "error").get("code") == "teams_need_4")
	a.send_msg({t = "settings", teams = false})
	a.send_msg({t = "start"})
	pump([a, b])
	var st := last(b, "start")
	check("start reaches both: n 0, seats, state, hash", not st.is_empty() and int(st.n) == 0 and st.seats.size() == 2 and st.state is Dictionary
		and str(st.h) == StateHash.of(MatchStore.ints(st.state)), st.keys())
	check("a turn follows the start", not last(a, "turn").is_empty() and int(last(a, "turn").c) == 0)
	var ns := NetLudo.new()
	ns.begin(st, b.member_id)
	check("replica: you are Yellow, the board turns to you, \"You\" locally", ns.me == 2 and int(ns.S.view) == 2 and ns.S.names[2] == "You" and ns.S.names[0] == "Ana")
	check("replica: S.me marks you; hash ignores it", NetLudo.you(ns.S, 2) and not NetLudo.you(ns.S, 0) and StateHash.of(ns.S) == str(st.h))
	check("offline states: you() is LudoRules.is_you", NetLudo.you({players = ["human", "cpu", "off", "off"]}, 0) and not NetLudo.you({players = ["human", "human", "off", "off"]}, 0))
	a.send_msg({t = "roll", n = 5})
	pump([a, b])
	check("a stale n: error stale", last(a, "error").get("code") == "stale")
	b.send_msg({t = "roll", n = 0})
	pump([a, b])
	check("not your turn: error", last(b, "error").get("code") == "not_your_turn")
	a.ping()
	pump([a])
	check("pong: round trip and server clock", a.rtt_ms >= 0 and absf(a.server_now() - Time.get_unix_time_from_system() * 1000.0) < 5000.0)
	a.leave()
	check("leave: idle, room forgotten", a.status == "idle" and NetClient.saved_room(a.prefs).is_empty() and a.log_sent.any(func(m): return m.t == "leave"))
	free_all([a, b])


# ---------- errors ----------

func _errors() -> void:
	var room := NetFake.Room.new()
	var cs := []
	for k in 4:
		var c := client(room, "P%d" % k)
		c.join(room.code)
		pump([c])
		cs.append(c)
	var e := client(room, "Late")
	e.join(room.code)
	pump([e])
	check("a fifth member: full, then idle (no retries)", last(e, "error").get("code") == "full" and e.status == "idle" and not e.in_room())
	cs[0].send_msg({t = "start"})
	pump(cs)
	var late := client(room, "Later")
	room.members.pop_back()                    # (make room so only "started" can refuse)
	late.join(room.code)
	pump([late])
	check("joining a started match without a seat: started", last(late, "error").get("code") == "started")
	var lost := client(room, "Lost")
	lost.make_transport = func() -> NetTransport:
		var p := room.make_pipe()
		p.reachable = false
		return p
	lost.join(room.code)
	for k in 40:
		lost._process(0.5)
	check("a first join that never connects gives up: no_connection", last(lost, "error").get("code") == "no_connection" and lost.status == "idle")
	free_all(cs + [e, late, lost])


# ---------- the replica: queue, duplicates, gaps, hash, sync ----------

func _replica() -> void:
	var room := NetFake.Room.new("ABCDEF", 3)
	var a := client(room, "Ana")
	var b := client(room, "Bo")
	for c in [a, b]:
		c.join(room.code)
		pump([a, b])
	a.send_msg({t = "start"})
	pump([a, b])
	var ns := NetLudo.new()
	ns.begin(last(a, "start"), a.member_id)
	room.dice = [3]
	a.send_msg(ns.request("roll"))
	pump([a, b])
	var act := last(a, "act")
	check("roll act: n 0, k roll, colour, value, hash", int(act.n) == 0 and act.a.k == "roll" and int(act.a.c) == 0 and int(act.a.v) == 3 and str(act.h).length() == 8, act)
	ns.push(act)
	ns.push(act)                                # a duplicate (a resend)
	var m := ns.next()
	check("next(): the act", m.get("n") == act.n)
	check("…applied with the rules, hash matches", ns.play(m) and ns.n == 1 and int(ns.S.turn) == 2, [ns.n, ns.S.turn])
	check("…the duplicate is dropped", ns.next().is_empty())
	room.dice = [6]
	b.send_msg({t = "roll", n = 1})
	pump([a, b])
	var r6 := last(a, "act")
	room.dice = []
	ns.push({t = "act", n = 5, a = {k = "roll", c = 0, v = 1}, h = "x"})   # a gap: 1..4 missing
	check("a gap in n: need_sync, later acts dropped", ns.next().get("t") == "need_sync" and ns.awaiting_sync)
	ns.push(r6)
	check("…until the sync", ns.next().is_empty())
	a.send_msg({t = "sync_req"})
	pump([a])
	ns.push(last(a, "sync"))
	var sy := ns.next()
	check("sync arrives in order", sy.get("t") == "sync")
	ns.begin(sy, a.member_id)
	check("…and replaces the state (n, hash, you)", ns.n == room.n and StateHash.of(ns.S) == StateHash.of(room.S) and not ns.awaiting_sync and ns.S.names[0] == "You")
	room.corrupt_next = true
	var nb := NetLudo.new()
	nb.begin(last(b, "start"), b.member_id)
	nb.push(got(b, "act")[0])
	nb.push(got(b, "act")[1])
	while true:
		var x := nb.next()
		if x.is_empty():
			break
		nb.play(x)
	check("B caught up by acts: same hash as the server", StateHash.of(nb.S) == StateHash.of(room.S) and nb.n == 2)
	# B (Yellow) rolled a 6: the move
	var mv := LudoRules.auto_move_token(nb.S)
	b.send_msg(nb.request("move", {i = mv}))
	pump([a, b])
	var bad := last(b, "act")
	check("a wrong server hash…", str(bad.h) == "00000000")
	nb.push(bad)
	check("…is a mismatch: awaiting sync", not nb.play(nb.next()) and nb.awaiting_sync and nb.mismatches == 1)
	var ex := nb.S.duplicate(true)
	nb.push({t = "act", n = nb.n, a = {k = "roll", c = 0, v = 2}, h = ""})
	check("…acts wait for the snapshot", nb.next().is_empty() and nb.S.tok == ex.tok)
	nb.push({t = "over", winner = 0, finished = [0]})
	check("over is always played", nb.next().get("t") == "over")
	var mode := {t = "act", n = nb.n, a = {k = "mode", c = 0, mode = "cpu"}, h = ""}
	var nm := NetLudo.new()
	nm.begin({n = 0, seats = [{color = 0, id = "x", bot = false, online = true}, {color = 2, id = "y"}], state = LudoRules.new_game(["human", "off", "human", "off"])}, "y")
	nm.push({t = "act", n = 0, a = {k = "mode", c = 0, mode = "cpu"}, h = ""})
	nm.play(nm.next())
	check("mode act: the colour becomes a bot, the seat says so", nm.S.players[0] == "cpu" and bool(nm.seat(0).bot) and nm.n == 1)
	check("presence: by member id", nm.set_online("x", false) == 0 and not bool(nm.seat(0).online) and nm.set_online("zz", true) == -1)
	check("my_turn: not on someone else's turn", not nm.my_turn() and mode.a.k == "mode")
	free_all([a, b])


# ---------- whole games ----------

## Members join and the host starts; every client plays its own turns from its replica (auto-move, else the first
## unit; pair prompts answered yes), the server's bots and timeouts act for leavers. Every act's hash is checked.
func _full_game(count: int, teams: bool, pair_ask: bool, seed_: int) -> void:
	var room := NetFake.Room.new("GAME%02d" % count, seed_)
	room.code = NetClient.clean_code("GM%dXYZ" % count).rpad(6, "Z").substr(0, 6)
	var cs := []
	for k in count:
		var c := client(room, ["Ana", "Bo", "Cy", "Di"][k])
		c.join(room.code)
		pump(cs + [c])
		cs.append(c)
	cs[0].send_msg({t = "settings", teams = teams, pair_ask = pair_ask})
	cs[0].send_msg({t = "start"})
	pump(cs)
	var res := _play_out(room, cs, [], 4000)
	var tag := "%d players%s%s" % [count, " teams" if teams else "", " ask" if pair_ask else ""]
	check("full game (%s): reached over on every client" % tag, res.over == count, res)
	check("…no hash mismatch, no gap", res.mismatches == 0 and res.gaps == 0, res)
	check("…every replica ends on the server's state", res.same == count and res.acts > 20, res)
	check("…the winner agrees", res.winner == int(room.S.winner) and int(room.S.winner) >= 0, res)
	_pairs += res.pairs
	free_all(cs)

func _leaver_game() -> void:
	var room := NetFake.Room.new("QEAVR2", 99)
	var cs := []
	for k in 3:
		var c := client(room, ["Ana", "Bo", "Cy"][k])
		c.join(room.code)
		pump(cs + [c])
		cs.append(c)
	cs[0].send_msg({t = "start"})
	pump(cs)
	var res := _play_out(room, cs, [], 40)        # a few turns
	cs[1].leave()
	pump(cs)
	var res2 := _play_out(room, [cs[0], cs[2]], [], 4000, res.ns)
	check("a member leaves mid-match: a bot plays their colour", room.S.players[1] == "cpu" and res2.bot_acts > 0, [room.S.players, res2])
	check("…the others finish with matching hashes", res2.over == 2 and res2.mismatches == 0 and res2.same == 2, res2)
	free_all(cs)

## Plays until every client got `over` (or `limit` server acts). Returns counts.
func _play_out(room: NetFake.Room, cs: Array, _skip: Array, limit: int, prev := {}) -> Dictionary:
	var ns := prev.duplicate() if not prev.is_empty() else {}
	var read := {}
	for c: NetClient in cs:
		read[c] = 0
		if not ns.has(c):
			var x := NetLudo.new()
			ns[c] = x
	var res := {over = 0, mismatches = 0, gaps = 0, same = 0, acts = 0, winner = -1, pairs = 0, bot_acts = 0, ns = ns}
	var done := {}
	var start_n := room.n
	var guard := 0
	while room.n - start_n < limit and guard < limit * 4:
		guard += 1
		pump(cs, 1)
		for c: NetClient in cs:
			var x: NetLudo = ns[c]
			var log: Array = c.get_meta("log")
			for k in range(read[c], log.size()):
				var m: Dictionary = log[k]
				match str(m.get("t", "")):
					"start":
						if x.S.is_empty():
							x.begin(m, c.member_id)
					"act", "sync", "over":
						x.push(m)
			read[c] = log.size()
			while true:
				var m2 := x.next()
				if m2.is_empty():
					break
				match str(m2.t):
					"act":
						if not x.play(m2):
							c.send_msg({t = "sync_req"})
					"need_sync":
						c.send_msg({t = "sync_req"})
					"sync":
						x.begin(m2, c.member_id)
					"over":
						done[c] = true
						res.winner = int(m2.winner)
		if done.size() == cs.size() or not room.playing and room.finished_once and done.size() == cs.size():
			break
		if not room.playing:
			if room.finished_once:
				continue
			break
		var turn := int(room.S.turn)
		if room.S.players[turn] == "cpu":
			room.step()
			res.bot_acts += 1
			continue
		var actor: NetClient = null
		for c: NetClient in cs:
			if (ns[c] as NetLudo).me == turn:
				actor = c
		if actor == null:
			room.timeout()
			continue
		var me: NetLudo = ns[actor]
		if me.n != room.n:
			continue                                  # still catching up (frames in flight)
		match str(me.S.phase):
			"roll":
				actor.send_msg(me.request("roll"))
			"choose":
				var i := LudoRules.auto_move_token(me.S)
				if i < 0:                                 # vary the choice so pawns meet (pairs, captures)
					var us := LudoRules.units(me.S)
					i = int(us[(room.n * 7 + 3) % us.size()].token)
				actor.send_msg(me.request("move", {i = i}))
			"pair_ask":
				res.pairs += 1
				actor.send_msg(me.request("pair", {yes = true}))
	pump(cs, 2)
	for c: NetClient in cs:
		var x: NetLudo = ns[c]
		res.mismatches += x.mismatches
		res.gaps += x.gaps
		if done.has(c):
			res.over += 1
		if not x.S.is_empty() and StateHash.of(x.S) == StateHash.of(room.S) and x.n == room.n:
			res.same += 1
	res.acts = room.n
	return res


# ---------- reconnect ----------

func _reconnect() -> void:
	var room := NetFake.Room.new("RECNN2", 4)
	var a := client(room, "Ana")
	var b := client(room, "Bo")
	for c in [a, b]:
		c.join(room.code)
		pump([a, b])
	a.send_msg({t = "start"})
	pump([a, b])
	var id := b.member_id
	var tok := b.token
	b.transport.drop()                          # the network drops B's socket
	b._process(0.0)
	check("a dropped socket: reconnecting (the room is kept)", b.status == "reconnecting" and b.in_room(), b.status)
	pump([a])
	check("the others see B offline", last(a, "presence").get("online") == false and NetClient.id_str(last(a, "presence").get("id")) == id)
	room.dice = [5]
	a.send_msg({t = "roll", n = 0})               # play goes on meanwhile
	pump([a])
	for k in 10:
		b._process(0.3)
	var hello: Dictionary = b.log_sent.filter(func(m): return m.t == "hello")[-1]
	check("reconnect: hello with the token", hello.get("token") == tok, hello)
	check("…same seat (member id), open again", b.member_id == id and b.status == "open")
	var sy := last(b, "sync")
	check("…a sync with the actions missed", not sy.is_empty() and int(sy.n) == 1, sy.keys())
	var nb := NetLudo.new()
	nb.begin(sy, b.member_id)
	check("…the replica matches the server again", StateHash.of(nb.S) == StateHash.of(room.S) and nb.me == 2)
	var c2 := client(room, "Bo")                   # the app restarted: a new client with the kept room
	c2.prefs = b.prefs.duplicate(true)
	b.close_socket()
	b.set_process(false)
	check("resume(): uses Save.prefs.net_room", c2.resume() and c2.code == room.code and c2.token == tok)
	pump([c2])
	check("…takes back the seat after a restart", c2.member_id == id and not last(c2, "sync").is_empty())
	free_all([a, b, c2])
