extends "res://tests/test_suite.gd"
## Online v2, client side: the Snakes & Ladders replica (NetSL: localize, the S&L hash, roll / mode acts, gaps,
## mismatch -> sync), S&L friend rooms (the host's game setting, colours, roll only) and whole S&L games through the
## fake room with every hash checked; quick match (NetQuick against the fake matchmaker: hello with the session,
## queued, cancel, the error codes, a fresh session once, no connection), quick rooms (the token seat, no lobby, no
## host, ghost seats exactly like people, a whole game, a reconnect), the Online flow (search -> matched -> the
## players revealed -> the match, messages held meanwhile, cancel, Play again queues again, the app going to the
## background), the session in every hello, the online rewards table, Home's QUICK MATCH and the copy rules.
## Nothing here writes the save or opens a socket.

func run() -> void:
	_sl_replica()
	_sl_friend_room()
	_sl_full_game(2, 31)
	_sl_full_game(3, 7)
	_sl_full_game(4, 12)
	_quick_client()
	_quick_errors()
	_quick_room()
	_online_flow()
	_online_sl_and_cancel()
	_rewards()
	_raw_ws()
	_home()
	_copy()


# ---------- harness ----------

func client(hub: Variant, name: String, session := "s-" ) -> NetClient:
	var c := NetClient.new()
	c.use_save = false
	c.prefs = {}
	c.url_base = "ws://fake"
	var sess := session + name if session != "" else ""
	c.session_fn = func() -> String: return sess
	c.profile_fn = func() -> Dictionary: return {name = name, avatar = "pawn-blue", frame = "classic"}
	c.make_transport = hub.transport_factory()
	c.http_fn = hub.http
	var log := []
	c.set_meta("log", log)
	c.message.connect(func(m: Dictionary): log.append(m))
	return c

func quick(c: NetClient) -> NetQuick:
	var q := NetQuick.new(c)
	var log := []
	q.set_meta("log", log)
	q.queued.connect(func(p: int, e: int): log.append({t = "queued", position = p, eta_s = e}))
	q.matched.connect(func(code: String, tok: String): log.append({t = "matched", code = code, token = tok}))
	q.failed.connect(func(code: String, msg: String): log.append({t = "failed", code = code, msg = msg}))
	q.cancelled.connect(func(): log.append({t = "cancelled"}))
	return q

func pump(cs: Array, times := 3) -> void:
	for k in times:
		for c in cs:
			c._process(0.0)

func got(c: Object, t: String) -> Array:
	return (c.get_meta("log") as Array).filter(func(m): return m.get("t") == t)

func last(c: Object, t: String) -> Dictionary:
	var a := got(c, t)
	return a[-1] if not a.is_empty() else {}

func free_all(cs: Array) -> void:
	for c in cs:
		if is_instance_valid(c):
			c.free()


# ---------- the S&L replica ----------

func _sl_replica() -> void:
	var fresh := SnakesLaddersRules.new_game("local", 2)
	check("sl hash: the PROTOCOL.md example", SLStateHash.of(fresh) == "edd54d53", SLStateHash.of(fresh))
	var wire: Dictionary = JSON.parse_string(JSON.stringify(fresh))
	wire.mode = "online"
	var seats := [{color = 0, id = 1, name = "Ana", avatar = "pawn-red", frame = "classic", level = 4, bot = false, online = true},
		{color = 1, id = 2, name = "Bo", avatar = "pawn-green", frame = "classic", level = 7, bot = false, online = true}]
	var loc := NetSL.localize(wire, seats, "2")
	check("sl replica: you are Green, your player is you and \"You\", the other is named by its seat",
		int(loc.me) == 1 and bool(loc.players[1].you) and loc.players[1].name == "You" and not bool(loc.players[0].you) and loc.players[0].name == "Ana")
	check("sl replica: JSON floats back to ints", typeof(loc.turn) == TYPE_INT and typeof(loc.players[0].pos) == TYPE_INT and loc.mode == "online")
	check("sl replica: you / names / mode are not hashed", SLStateHash.of(loc) == "edd54d53", SLStateHash.of(loc))
	var r := NetReplica.for_game("sl")
	check("replica factory: sl -> NetSL, else NetLudo", r is NetSL and NetReplica.for_game("ludo") is NetLudo and NetReplica.for_game(null) is NetLudo)
	var ns := NetSL.new()
	ns.begin({n = 0, game = "sl", seats = seats, state = wire}, "1")
	check("sl replica: my turn first (Red)", ns.me == 0 and ns.my_turn() and ns.turn_color() == 0)
	check("sl replica: the only request is roll", ns.auto_request() == {t = "roll", n = 0})
	# play an act computed by the rules themselves
	var srv := SnakesLaddersRules.new_game("local", 2)
	SnakesLaddersRules.apply_roll(srv, 4)               # a ladder: 4 -> 14
	ns.push({t = "act", n = 0, a = {k = "roll", c = 0, v = 4}, h = SLStateHash.of(srv)})
	var m := ns.next()
	var ev := ns.apply_rules(m.a)
	check("sl replica: roll applies apply_roll (events for the animation)", ev.any(func(e): return e.type == "move" and e.ladder) and int(ns.S.players[0].pos) == 14)
	check("sl replica: hash matches", ns.verify(m) and ns.n == 1)
	check("sl replica: Bo's turn now", not ns.my_turn() and ns.turn_color() == 1)
	ns.push({t = "act", n = 1, a = {k = "mode", c = 1, mode = "cpu"}, h = ""})
	ns.play(ns.next())
	check("sl replica: mode act: that colour's player is a bot, the seat says so", bool(ns.S.players[1].cpu) and bool(ns.seat(1).bot) and ns.index_of(1) == 1)
	ns.push({t = "act", n = 1, a = {k = "roll", c = 1, v = 2}, h = ""})
	check("sl replica: a duplicate n is dropped", ns.next().is_empty())
	ns.push({t = "act", n = 5, a = {k = "roll", c = 1, v = 2}, h = ""})
	check("sl replica: a gap asks for a sync", ns.next().get("t") == "need_sync" and ns.awaiting_sync and ns.gaps == 1)
	ns.push({t = "act", n = 2, a = {k = "roll", c = 1, v = 2}, h = ""})
	check("sl replica: acts wait for the snapshot", ns.next().is_empty())
	ns.push({t = "sync", n = 7, game = "sl", seats = seats, state = wire})
	var sy := ns.next()
	ns.begin(sy, "1")
	check("sl replica: the sync replaces everything", ns.n == 7 and not ns.awaiting_sync and int(ns.S.players[0].pos) == 0 and bool(ns.S.players[0].you))
	ns.push({t = "act", n = 7, a = {k = "roll", c = 0, v = 3}, h = "00000000"})
	check("sl replica: a wrong hash is a mismatch", not ns.play(ns.next()) and ns.mismatches == 1 and ns.awaiting_sync)

func _sl_friend_room() -> void:
	var room := NetFake.Room.new("SNRM22", 9)
	var a := client(room, "Ana")
	var b := client(room, "Bo")
	var c := client(room, "Cy")
	for x in [a, b, c]:
		x.join(room.code)
		pump([a, b, c])
	var hello: Dictionary = a.log_sent[0]
	check("hello: carries the account session", hello.get("session") == "s-Ana" and hello.has("pid"), hello)
	a.send_msg({t = "settings", game = "sl"})
	pump([a, b, c])
	var lob := last(b, "lobby")
	check("sl room: the host's game reaches everyone", lob.settings.game == "sl", lob.settings)
	check("sl room: colours Red, Green, Yellow in join order", (lob.members as Array).map(func(m): return int(m.color)) == [0, 1, 2], lob.members)
	b.send_msg({t = "settings", game = "ludo"})
	pump([a, b])
	check("sl room: a guest can't change the game", last(b, "error").get("code") == "not_host")
	a.send_msg({t = "start"})
	pump([a, b, c])
	var st := last(c, "start")
	check("sl start: game sl, an S&L state, the S&L hash", st.get("game") == "sl" and (st.state as Dictionary).has("players")
		and str(st.h) == SLStateHash.of(NetSL.localize(st.state, st.seats, "")), st.get("game"))
	var ns := NetSL.new()
	ns.begin(st, a.member_id)
	a.send_msg(ns.request("move", {i = 0}))
	pump([a])
	check("sl match: move is refused (bad_action)", last(a, "error").get("code") == "bad_action")
	free_all([a, b, c])

## Members join, the host picks S&L and starts; every client rolls on its turn from its own replica (bots and timeouts
## roll for the others). Every act's hash is checked on every client.
func _sl_full_game(count: int, seed_: int) -> void:
	var room := NetFake.Room.new("SLG%dZZ" % count, seed_)
	room.code = NetClient.clean_code("SLG%dZZ" % count).rpad(6, "Z").substr(0, 6)
	var cs := []
	for k in count:
		var c := client(room, ["Ana", "Bo", "Cy", "Di"][k])
		c.join(room.code)
		pump(cs + [c])
		cs.append(c)
	cs[0].send_msg({t = "settings", game = "sl"})
	cs[0].send_msg({t = "start"})
	pump(cs)
	var res := _play_out(room, cs, 6000)
	check("sl game (%d players): over on every client" % count, res.over == count, res)
	check("sl game (%d players): no mismatch, no gap, every replica on the server's state" % count,
		res.mismatches == 0 and res.gaps == 0 and res.same == count and res.acts > 10, res)
	check("sl game (%d players): over says the winner's colour and standings" % count, res.winner == int(room.S.players[int(room.S.winner)].c)
		and res.standings == count, res)
	free_all(cs)

## Plays until every client got `over`. Returns counts (and the replicas, by client).
func _play_out(room: NetFake.Room, cs: Array, limit: int) -> Dictionary:
	var reps := {}
	var read := {}
	for c in cs:
		read[c] = 0
		reps[c] = null
	var res := {over = 0, mismatches = 0, gaps = 0, same = 0, acts = 0, winner = -1, standings = 0, ghost_acts = 0}
	var done := {}
	var guard := 0
	while guard < limit:
		guard += 1
		pump(cs, 1)
		for c in cs:
			var log: Array = c.get_meta("log")
			for k in range(read[c], log.size()):
				var m: Dictionary = log[k]
				match str(m.get("t", "")):
					"start":
						reps[c] = NetReplica.for_game(m.get("game"))
						(reps[c] as NetReplica).begin(m, c.member_id)
					"act", "sync", "over":
						if reps[c] != null:
							(reps[c] as NetReplica).push(m)
			read[c] = log.size()
			var x: NetReplica = reps[c]
			while x != null:
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
						res.standings = (m2.get("standings", []) as Array).size()
		if done.size() == cs.size():
			break
		if not room.playing:
			if room.finished_once:
				continue
			break
		var turn := room.turn_color()
		if room.is_cpu(turn) or room.is_ghost(turn):
			room.step()
			if room.is_ghost(turn):
				res.ghost_acts += 1
			continue
		var actor: NetClient = null
		for c in cs:
			if reps[c] != null and (reps[c] as NetReplica).me == turn:
				actor = c
		if actor == null:
			room.timeout()
			continue
		var me: NetReplica = reps[actor]
		if me.n != room.n:
			continue                                  # still catching up
		var req := me.auto_request(guard)
		if not req.is_empty():
			actor.send_msg(req)
	pump(cs, 2)
	for c in cs:
		var x: NetReplica = reps[c]
		if x == null:
			continue
		res.mismatches += x.mismatches
		res.gaps += x.gaps
		if done.has(c):
			res.over += 1
		if x.state_hash() == room.state_hash() and x.n == room.n:
			res.same += 1
	res.acts = room.n
	res.reps = reps
	return res


# ---------- quick match: the queue client ----------

func _quick_client() -> void:
	var hub := NetFake.Hub.new(3)
	var c := client(hub, "Ana")
	var q := quick(c)
	check("quick url: game and table size", NetQuick.queue_url("wss://x.dev/", "sl", 4) == "wss://x.dev/v1/quick/ws?game=sl&players=4")
	check("quick: only ludo / sl and 2 / 4", NetQuick.valid("ludo", 2) and NetQuick.valid("sl", 4) and not NetQuick.valid("sl", 3) and not NetQuick.valid("chess", 2))
	q.search("sl", 2)
	check("quick: connecting at once", q.status == "connecting" and q.searching())
	pump([q])
	var hello: Dictionary = hub.mm.hellos[-1] if not hub.mm.hellos.is_empty() else {}
	check("quick hello: v 1, session, pid, name, avatar, frame", hello.get("t") == "hello" and int(hello.get("v", 0)) == 1
		and hello.get("session") == "s-Ana" and str(hello.get("pid", "")).length() >= 16 and hello.get("name") == "Ana"
		and hello.get("avatar") == "pawn-blue" and hello.get("frame") == "classic", hello)
	check("quick: queued, position 1, an eta", q.status == "queued" and last(q, "queued").get("position") == 1 and int(last(q, "queued").get("eta_s", 0)) > 0)
	check("quick: the queue is per game and size", hub.mm.queue("sl", 2).size() == 1 and hub.mm.queue("ludo", 2).is_empty())
	var c2 := client(hub, "Bo")
	var q2 := quick(c2)
	q2.search("sl", 2)
	pump([q, q2])
	check("quick: a full table of people is matched at once", last(q, "matched").get("code", "") != "" and last(q2, "matched").get("code") == last(q, "matched").get("code"))
	check("quick: matched: done, the socket closed", q.status == "matched" and q.transport == null and not q.searching())
	check("quick: each person has their own seat token", str(last(q, "matched").token) != str(last(q2, "matched").token))
	# cancel
	var c3 := client(hub, "Cy")
	var q3 := quick(c3)
	q3.search("ludo", 4)
	pump([q3])
	q3.cancel()
	check("quick cancel: sent, the queue is empty, cancelled", q3.log_sent.any(func(m): return m.t == "cancel") and hub.mm.queue("ludo", 4).is_empty()
		and not got(q3, "cancelled").is_empty() and q3.status == "idle")
	check("quick cancel: the server saw it", hub.mm.cancels == 1)
	# the oldest waiting person gets a table with ghosts after the wait (the fake: fill())
	q3.search("ludo", 4)
	pump([q3])
	var room := hub.mm.fill("ludo", 4)
	pump([q3])
	check("quick fill: matched into a 4-seat room with 3 ghosts", room != null and room.members.size() == 4
		and room.members.filter(func(m): return bool(m.ghost)).size() == 3 and last(q3, "matched").get("code") == room.code)
	# replaced: the same account queues on a second connection
	var d1 := client(hub, "Di")
	var d2 := client(hub, "Di")
	var qa := quick(d1)
	var qb := quick(d2)
	qa.search("sl", 4)
	pump([qa])
	qb.search("sl", 4)
	pump([qa, qb])
	check("quick: queueing again elsewhere replaces the older connection", last(qa, "failed").get("code") == "replaced" and qb.status == "queued"
		and hub.mm.queue("sl", 4).size() == 1)
	free_all([q, q2, q3, qa, qb, c, c2, c3, d1, d2])

func _quick_errors() -> void:
	var hub := NetFake.Hub.new(4)
	var c := client(hub, "Ana")
	var q := quick(c)
	hub.mm.maintenance = "Back at 6 pm."
	q.search("ludo", 2)
	pump([q])
	check("quick: maintenance -> failed with the message", last(q, "failed").get("code") == "maintenance" and last(q, "failed").get("msg") == "Back at 6 pm."
		and q.status == "failed")
	hub.mm.maintenance = ""
	hub.mm.banned = ["s-Ana"]
	q.search("ludo", 2)
	pump([q])
	check("quick: banned -> failed (no retries)", last(q, "failed").get("code") == "banned" and q.transport == null)
	hub.mm.banned = []
	# an expired session: one fresh sign-in, then queued
	hub.mm.bad_sessions = ["s-Ana"]
	var renewed := []
	q.renew_fn = func() -> String:
		renewed.append(1)
		return "fresh-1"
	q.search("ludo", 2)
	pump([q], 4)
	check("quick: an expired session is renewed once, then queued", renewed.size() == 1 and q.status == "queued"
		and hub.mm.hellos[-1].get("session") == "fresh-1", [renewed, q.status])
	q.cancel()
	hub.mm.bad_sessions = ["s-Ana", "fresh-1"]
	q.renew_fn = func() -> String: return "fresh-1"
	q.search("ludo", 2)
	pump([q], 4)
	check("quick: a session that stays bad fails with session", last(q, "failed").get("code") == "session")
	check("quick copy: session / replaced / busy have friendly words", NetClient.error_text("session").begins_with("We couldn’t")
		and NetClient.error_text("replaced") != NetClient.error_text("nope") and NetClient.error_text("busy") != NetClient.error_text("nope"))
	# no session at all and no account: session
	var nos := client(hub, "Nos", "")
	var qn := quick(nos)
	qn.search("ludo", 2)
	check("quick: no session and no account -> failed session", last(qn, "failed").get("code") == "session" and hub.mm.hellos.size() > 0)
	# no network: no_connection after a few tries
	var lost := client(hub, "Lost")
	lost.make_transport = func() -> NetTransport:
		var p := hub.make_pipe()
		p.reachable = false
		return p
	var ql := quick(lost)
	ql.search("sl", 2)
	for k in 30:
		ql._process(1.0)
	check("quick: no network -> no_connection", last(ql, "failed").get("code") == "no_connection" and ql.status == "failed")
	free_all([q, qn, ql, c, nos, lost])


# ---------- quick rooms ----------

func _quick_room() -> void:
	var hub := NetFake.Hub.new(8)
	var a := client(hub, "Ana")
	var qa := quick(a)
	qa.search("ludo", 2)
	pump([qa])
	var room := hub.mm.fill("ludo", 2)
	pump([qa])
	var mt := last(qa, "matched")
	a.join(str(mt.code), str(mt.token), true)
	pump([a])
	var w := last(a, "welcome")
	check("quick room: welcomed into the reserved seat, host -1", not w.is_empty() and int(w.host) == -1 and not a.is_host() and a.quick)
	check("quick room: the kept room says quick (a restart takes it back)", bool(NetClient.saved_room(a.prefs).get("quick", false)))
	check("quick room: the match starts once every person is here (no lobby)", got(a, "lobby").is_empty() and not last(a, "start").is_empty())
	var st := last(a, "start")
	var seats: Array = st.seats
	var mine := seats.filter(func(s): return NetClient.id_str(s.id) == a.member_id)
	var other := seats.filter(func(s): return NetClient.id_str(s.id) != a.member_id)
	check("quick room: two seats, Red and Yellow", seats.size() == 2 and seats.map(func(s): return int(s.color)) == [0, 2])
	check("ghost seat: the same keys as a person's", other.size() == 1 and mine.size() == 1 and (other[0] as Dictionary).keys() == (mine[0] as Dictionary).keys(), [other, mine])
	check("ghost seat: a person (human, not a bot, online, a name, a level)", st.state.players[int(other[0].color)] == "human" and not bool(other[0].bot)
		and bool(other[0].online) and str(other[0].name) != "" and int(other[0].level) >= 1)
	a.send_msg({t = "settings", game = "sl"})
	a.send_msg({t = "start"})
	pump([a])
	check("quick room: settings / start -> bad_action", got(a, "error").filter(func(e): return e.code == "bad_action").size() == 2)
	var stranger := client(hub, "Eve")
	stranger.join(room.code)
	pump([stranger])
	check("quick room: no seat for anyone else (full)", last(stranger, "error").get("code") == "full" and stranger.status == "idle")
	# a few turns, then the network drops: back into the same seat with the token
	var res := _play_out(room, [a], 30)
	var id := a.member_id
	a.transport.drop()
	a._process(0.0)
	room.step()
	room.step()
	for k in 10:
		a._process(0.3)
	var hello: Dictionary = a.log_sent.filter(func(m): return m.t == "hello")[-1]
	check("quick reconnect: hello with the token and the session", hello.get("token") == str(mt.token) and hello.get("session") == "s-Ana")
	check("quick reconnect: same seat, a sync", a.member_id == id and a.status == "open" and not last(a, "sync").is_empty())
	var res2 := _play_out(room, [a], 8000)
	check("quick game: played to over, every hash matched", res2.over == 1 and res2.mismatches == 0 and res2.same == 1, res2)
	check("quick game: the ghost played like a person (acts, no mode acts)", res2.ghost_acts > 0 and room.acts.all(func(x): return x.a.k != "mode"))
	# after over: a reconnect gets sync + over, never a lobby
	a.close_socket()
	a.join(room.code)
	pump([a])
	check("quick room after over: sync + over, no lobby", not last(a, "over").is_empty() and got(a, "lobby").is_empty())
	free_all([a, qa, stranger])
	var _r := res


# ---------- Online: quick flow ----------

class FakeMatch extends Node:
	var online := false
	var got: Array = []
	var started: Array = []

	func start_online(m: Dictionary, _net: Object) -> void:
		online = true
		started.append(m)

	func net_push(m: Dictionary) -> void:
		got.append(["push", str(m.get("t", ""))])

	func net_turn(_m: Dictionary) -> void:
		got.append(["turn", ""])

	func net_presence(_m: Dictionary) -> void:
		got.append(["presence", ""])

	func net_error(_m: Dictionary) -> void:
		pass

	func net_status(_s: String) -> void:
		pass

class FakeApp extends Node:
	var sheet_layer := Control.new()
	var ui_root := Control.new()
	var ludo := FakeMatch.new()
	var sl := FakeMatch.new()
	var screen := "home"
	var homes := 0
	var host_calls: Array = []
	var entered_sl := 0

	func _init() -> void:
		sheet_layer.size = Vector2(390, 844)
		add_child(sheet_layer)
		add_child(ui_root)
		add_child(ludo)
		add_child(sl)

	func start_online(m: Dictionary, n: Object) -> void:
		screen = "ludo"
		ludo.start_online(m, n)

	func _enter_sl() -> void:
		entered_sl += 1
		screen = "sl"

	func go_home() -> void:
		homes += 1
		screen = "home"
		ludo.online = false
		sl.online = false

	func online_host_changed(on: bool) -> void:
		host_calls.append(on)

	func online_closed() -> void:
		pass

func _online(hub: NetFake.Hub, name := "Ana") -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	var app := FakeApp.new()
	tree.root.add_child(app)
	var c := client(hub, name)
	var o := Online.new(app, c)
	o.reveal_fast = true
	app.add_child(o)
	return [app, o]

func opump(o: Online, times := 4) -> void:
	for k in times:
		o.net._process(0.0)
		o.quick_q._process(0.0)

func _online_flow() -> void:
	var hub := NetFake.Hub.new(11)
	var pair := _online(hub)
	var app: FakeApp = pair[0]
	var o: Online = pair[1]
	o.open_quick("ludo")
	var s := o.quick_sheet
	check("online quick: the picker opens with the remembered table (2 by default)", s != null and s.stage == "pick" and s.players == 2 and s.game == "ludo")
	check("quick sheet: 48 px targets (picker, Find players)", s.find_button.get_combined_minimum_size().y >= UIKit.TAP
		and (s.picker.get_child(0) as Control).get_combined_minimum_size().y >= UIKit.TAP)
	s.find.emit(4)
	opump(o)
	check("online quick: searching, the table size remembered", o.state == "searching" and s.stage == "searching" and int(o.net.prefs.quick_players) == 4
		and o.quick_cfg == {game = "ludo", players = 4} and hub.mm.queue("ludo", 4).size() == 1)
	check("quick sheet: your seat and three searching seats, Cancel", s.slots.size() == 4 and (s.slots[0] as QuickSheet.Slot).filled
		and not (s.slots[1] as QuickSheet.Slot).filled and s.cancel_button.visible and s.cancel_button.get_combined_minimum_size().y >= UIKit.TAP)
	check("quick sheet: the time waited", s.sub_label.text.begins_with("0:0"), s.sub_label.text)
	var room := hub.mm.fill("ludo", 4)
	opump(o, 6)
	check("online quick: matched -> the room joined with the token -> start -> the match (no lobby)", o.state == "match" and app.ludo.online
		and app.ludo.started.size() == 1 and o.net.quick and o.net.code == room.code)
	check("online quick: the players were revealed in the sheet (every seat filled the same way)", s.stage == "found" and s.slots.all(func(x): return (x as QuickSheet.Slot).filled))
	check("online quick: a turn sent with the start reached the match after it", app.ludo.got.size() >= 1 and app.ludo.got[0][0] == "turn", app.ludo.got)
	# the server plays a ghost's step: it reaches the match in order
	var before := app.ludo.got.size()
	if room.S.players[room.turn_color()] == "human" and room.is_ghost(room.turn_color()):
		room.step()
	else:
		o.net.send_msg({t = "roll", n = 0})
	opump(o)
	check("online quick: acts go to the match", app.ludo.got.size() > before and app.ludo.got.slice(before).any(func(g): return g[0] == "push"))
	check("online quick: is_host() offers Play again in a quick room", o.is_host())
	# play to the end on the server and check Play again queues again
	room.S.phase = "over"
	room.S.winner = room.turn_color()
	room.playing = false
	room.finished_once = true
	room._broadcast(room._over_msg())
	opump(o)
	check("online quick: over -> state over", o.state == "over")
	var hellos := hub.mm.hellos.size()
	o.rematch()
	opump(o)
	check("online quick: Play again leaves the room, goes home and queues the same table", o.state == "searching" and app.homes == 1
		and hub.mm.hellos.size() == hellos + 1 and hub.mm.queue("ludo", 4).size() == 1 and not o.net.in_room()
		and is_instance_valid(o.quick_sheet) and o.quick_sheet.stage == "searching")
	# the app goes to the background during the search: it stops
	o._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	opump(o)
	check("online quick: backgrounding stops the search", o.state == "idle" and hub.mm.queue("ludo", 4).is_empty()
		and o.quick_sheet.stage == "error" and o.quick_sheet.note_label.text.contains("background"))
	_end(app)

func _online_sl_and_cancel() -> void:
	var hub := NetFake.Hub.new(12)
	var pair := _online(hub)
	var app: FakeApp = pair[0]
	var o: Online = pair[1]
	o.open_quick("sl")
	var s := o.quick_sheet
	check("online quick sl: the sheet names the game", s.game == "sl" and s.kicker.text == "SNAKES & LADDERS ONLINE")
	s.find.emit(2)
	opump(o)
	s.cancel_pressed.emit()
	s.close()
	opump(o)
	check("online quick: Cancel leaves the queue", o.state == "idle" and hub.mm.queue("sl", 2).is_empty() and hub.mm.cancels == 1)
	o.open_quick("sl")
	o.quick_sheet.find.emit(2)
	opump(o)
	hub.mm.fill("sl", 2)
	o.quick_q._process(0.0)                       # matched -> joining (the room socket not open yet)
	check("online quick: joining after matched", o.state == "joining" and o.quick_sheet.stage == "matched")
	o.cancel_quick()
	opump(o)
	check("online quick: Cancel after matched leaves the room", o.state == "idle" and not o.net.in_room())
	# an S&L match opens the S&L screen
	o.open_quick("sl")
	o.quick_sheet.find.emit(2)
	opump(o)
	var room := hub.mm.fill("sl", 2)
	opump(o, 6)
	check("online quick sl: the S&L screen opens and the match starts", app.entered_sl == 1 and app.sl.online and app.sl.started.size() == 1
		and str(app.sl.started[0].get("game")) == "sl" and room.game == "sl")
	# maintenance: the sheet says so
	o.leave()
	hub.mm.maintenance = "Back soon."
	o.open_quick("ludo")
	o.quick_sheet.find.emit(2)
	opump(o)
	check("online quick: maintenance shows the admin's message in the sheet", o.state == "idle" and o.quick_sheet.stage == "error"
		and o.quick_sheet.note_label.text == "Back soon." and o.quick_sheet.find_button.visible)
	# friend room for S&L: the creator's game is set on the new room
	hub.mm.maintenance = ""
	o.quick_sheet.close()
	o.open_friends("sl")
	check("online friends: the sheet for S&L", o.friends.game == "sl" and o.friends.kicker.text == "SNAKES & LADDERS ONLINE")
	o._create()
	opump(o, 6)
	var r2: NetFake.Room = hub.rooms.get(o.net.code)
	check("online friends: the new room is S&L (the host's settings)", r2 != null and r2.settings.game == "sl" and o.state == "lobby"
		and is_instance_valid(o.lobby_sheet) and o.lobby_sheet.game == "sl")
	o.lobby_sheet.game_changed.emit("ludo")
	opump(o)
	check("online friends: the lobby's game picker sends settings {game}", r2.settings.game == "ludo" and o.lobby_sheet.game == "ludo")
	o.leave()
	_end(app)

func _end(app: Node) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.remove_child(app)
	app.free()


# ---------- the app's WebSocket client (NetTransport.Raw) ----------

static func _server_frame(op: int, payload: PackedByteArray, fin := true) -> PackedByteArray:
	var f := PackedByteArray([(0x80 if fin else 0) | op])
	var n := payload.size()
	if n < 126:
		f.append(n)
	else:
		f.append(126)
		f.append((n >> 8) & 0xFF)
		f.append(n & 0xFF)
	f.append_array(payload)
	return f

func _raw_ws() -> void:
	check("raw ws: the RFC 6455 accept key", NetTransport.Raw._accept_for("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
	check("raw ws: the app uses it", NetTransport.make() is NetTransport.Raw)
	var r := NetTransport.Raw.new()
	var out := StreamPeerBuffer.new()
	r._peer = out
	r._phase = "open"
	# matched + close 1000 "matched" in one read: both frames are delivered, then closed
	var bytes := _server_frame(0x1, "{\"t\":\"matched\",\"code\":\"K7QX2M\"}".to_utf8_buffer())
	var close := PackedByteArray([0x03, 0xE8])
	close.append_array("matched".to_utf8_buffer())
	bytes.append_array(_server_frame(0x8, close))
	r._buf = bytes
	r._frames()
	var got_ := r.receive()
	check("raw ws: the frame sent right before the close is kept", got_.size() == 1 and str(got_[0]).contains("matched"), got_)
	check("raw ws: then closed with the server's code and reason", r.state() == WebSocketPeer.STATE_CLOSED and r.close_code == 1000 and r.close_reason == "matched")
	# a long text frame split over reads, a fragmented message, a ping
	var r2 := NetTransport.Raw.new()
	var out2 := StreamPeerBuffer.new()
	r2._peer = out2
	r2._phase = "open"
	var big := "x".repeat(3000)
	var fb := _server_frame(0x1, big.to_utf8_buffer())
	r2._buf = fb.slice(0, 1000)
	r2._frames()
	check("raw ws: half a frame waits", r2.receive().is_empty() and r2.state() == WebSocketPeer.STATE_OPEN)
	r2._buf.append_array(fb.slice(1000))
	r2._frames()
	check("raw ws: the rest completes it (126 length)", r2.receive() == [big])
	var frag := _server_frame(0x1, "he".to_utf8_buffer(), false)
	frag.append_array(_server_frame(0x9, "p".to_utf8_buffer()))
	frag.append_array(_server_frame(0x0, "llo".to_utf8_buffer()))
	r2._buf = frag
	r2._frames()
	check("raw ws: fragments join (a ping between them)", r2.receive() == ["hello"])
	var sent := out2.data_array
	check("raw ws: a ping is answered with a masked pong", sent.size() >= 7 and sent[0] == 0x8A and (sent[1] & 0x80) != 0
		and (sent[6] ^ sent[2]) == "p".unicode_at(0))
	# what we send is masked
	var r3 := NetTransport.Raw.new()
	var out3 := StreamPeerBuffer.new()
	r3._peer = out3
	r3._phase = "open"
	r3.send("{\"t\":\"ping\"}")
	var d := out3.data_array
	var n := d[1] & 0x7F
	var body := PackedByteArray()
	for k in n:
		body.append(d[6 + k] ^ d[2 + (k % 4)])
	check("raw ws: our text frame: FIN text, masked, the payload back", d[0] == 0x81 and (d[1] & 0x80) != 0 and body.get_string_from_utf8() == "{\"t\":\"ping\"}")
	check("raw ws: urls: ws / wss / bad", NetTransport.Raw.new().open("http://x") == ERR_INVALID_PARAMETER)


# ---------- rewards, Home, copy ----------

func _rewards() -> void:
	check("rewards: Ludo win 150 + 100 XP, finish 20 + 40", NetReplica.online_reward("ludo", "win") == {coins = 150, xp = 100}
		and NetReplica.online_reward("ludo", "finish") == {coins = 20, xp = 40})
	check("rewards: S&L win 100 + 60 XP, finish 10 + 25", NetReplica.online_reward("sl", "win") == {coins = 100, xp = 60}
		and NetReplica.online_reward("sl", "finish") == {coins = 10, xp = 25})
	check("rewards: left (or watching) pays nothing", NetReplica.online_reward("ludo", "left") == {coins = 0, xp = 0}
		and NetReplica.online_reward("sl", "") == {coins = 0, xp = 0})

func _home() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for sz in [Vector2(390, 844), Vector2(320, 640)]:
		var frame := Control.new()
		frame.size = sz
		tree.root.add_child(frame)
		var h := HomeScreen.new()
		frame.add_child(h)
		h._layout()
		h._modes.notification(Container.NOTIFICATION_SORT_CHILDREN)
		var asked := []
		h.quick_match.connect(func(g: String): asked.append(g))
		h.play_friends.connect(func(g: String): asked.append("friends:" + g))
		h.quick_button.pressed.emit()
		h.select_game("sl")
		h.quick_button.pressed.emit()
		h.friends_button.pressed.emit()
		check("home %dx%d: QUICK MATCH and Friends ask for the picked game (S&L too)" % [sz.x, sz.y],
			asked == ["ludo", "sl", "friends:sl"], asked)
		var rows: Array[Control] = [h.quick_button, h._modes]
		var ok := true
		for r: Control in rows:
			ok = ok and r.position.x >= 15.0 and r.position.x + r.size.x <= sz.x - 15.0 and r.size.y >= UIKit.TAP
		var gap := h._modes.position.y - (h.quick_button.position.y + h.quick_button.size.y)
		check("home %dx%d: QUICK MATCH and the modes inside the gutters, >= 48 px, apart" % [sz.x, sz.y], ok and gap >= 6.0, [h.quick_button.position, h.quick_button.size, h._modes.position, gap])
		check("home %dx%d: QUICK MATCH is the wider one" % [sz.x, sz.y], h.quick_button.size.x > h.friends_button.size.x, [h.quick_button.size, h.friends_button.size])
		if sz.y >= 844.0:                    # (the UI is never shorter than the 844 px base on a phone)
			check("home %dx%d: the free band for the table stays" % [sz.x, sz.y], h.free_band().y - h.free_band().x > 40.0, h.free_band())
		h.select_game("ludo")
		tree.root.remove_child(frame)
		frame.free()

func _copy() -> void:
	var files := ["res://scripts/ui/sheets/quick_sheet.gd", "res://scripts/game/sl_match.gd", "res://scripts/net/net_quick.gd",
		"res://scripts/net/online.gd", "res://scripts/net/net_sl.gd", "res://scripts/ui/home_screen.gd",
		"res://scripts/ui/sheets/lobby_sheet.gd", "res://scripts/ui/sheets/friends_sheet.gd"]
	var bad := []
	var re := RegEx.create_from_string("\"[^\"]*[A-Za-z]'[A-Za-z][^\"]*\"")
	var color := RegEx.create_from_string("Color\\(\"#")
	for p in files:
		for line in FileAccess.get_file_as_string(p).split("\n"):
			var code := line.split("#")[0] if not line.strip_edges().begins_with("##") else ""
			if re.search(code) and not code.contains("get(") and not code.contains("\\\""):
				bad.append([p.get_file(), line.strip_edges()])
			if color.search(line):
				bad.append([p.get_file(), "colour literal"])
	check("online v2 copy: typographic apostrophes, no colour literals", bad.is_empty(), bad)
	var ui := FileAccess.get_file_as_string("res://scripts/ui/sheets/quick_sheet.gd") + FileAccess.get_file_as_string("res://scripts/game/sl_match.gd")
	var seat_words := []
	for line in FileAccess.get_file_as_string("res://scripts/ui/sheets/quick_sheet.gd").split("\n"):
		var code := line.split("##")[0].replace("\"ghost\"", "")
		if RegEx.create_from_string("\"[^\"]*\\b([Bb]ots?|[Gg]hosts?|CPU|[Cc]omputer)\\b[^\"]*\"").search(code):
			seat_words.append(line.strip_edges())
	check("online v2 copy: the quick-match sheet never says bot / ghost / computer", seat_words.is_empty(), seat_words)
	check("online v2 copy: sentence case", ui.contains("\"Quick match\"") and ui.contains("\"Finding players…\"") and ui.contains("\"Find players\"") and ui.contains("\"I’m back\""))
