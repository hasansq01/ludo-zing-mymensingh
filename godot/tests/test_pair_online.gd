extends "res://tests/test_suite.gd"
## "Ask before pairing" online (server/PROTOCOL.md "Ask before pairing"): the per-colour rule (LudoRules.asks_pair,
## new_game's pair_ask_by, default_pair_answer), the hello carrying your own Settings choice, the fake server dealing
## it to every person's colour in friend and quick rooms alike (an old client's settings.pair_ask is ignored; ghosts
## are asked and answer), and the live match through Online against the fake hub: with the setting on, your move onto
## your own pawn opens the inline prompt and the answer goes to the server; off, the pair forms by itself; the
## server's timer closes an open prompt; a ghost's question shows you no prompt and its answer plays out. Nothing here opens a socket or writes user://save.json: Save
## plays on a copy of the profile and prefs with its debounced write cut, then gets the originals back.

const Live := preload("res://tests/test_reroll.gd")   # (its LiveApp: the parts of main a live match needs)

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

var _sp := {}
var _spf := {}

func run() -> void:
	_sandbox()
	_rules()
	_hello()
	_fake_rooms()
	_defaults()
	await _live(true)
	await _live(false)
	await _live_timeout()
	await _live_ghost(1.0)
	await _live_ghost(0.0)
	_restore()

## A pair you form online counts in your stats (Save.save()): keep that off the real save.
func _sandbox() -> void:
	_sp = Save.profile
	_spf = Save.prefs
	Save.profile = _sp.duplicate(true)
	Save.prefs = _spf.duplicate(true)
	if Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)

func _restore() -> void:
	Save._dirty = false
	Save.profile = _sp
	Save.prefs = _spf
	if not Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.connect(Save.flush)


# ---------- the rules ----------

func _rules() -> void:
	var s := Ludo.new_game(["human", "off", "human", "off"], false, {pair_ask = false, pair_ask_by = [true, false, false, false]})
	check("rules: pair_ask_by is kept per colour", s.pair_ask_by == [true, false, false, false] and s.pair_ask == false)
	check("rules: asks_pair: Red yes, Yellow no", Ludo.asks_pair(s, 0) and not Ludo.asks_pair(s, 2))
	s.players[0] = "cpu"
	check("rules: asks_pair: a bot is never asked", not Ludo.asks_pair(s, 0))
	var t := Ludo.new_game(["human", "off", "human", "off"], false, {pair_ask = true})
	check("rules: without pair_ask_by the table's pair_ask decides (and the state has no pair_ask_by)",
		Ludo.asks_pair(t, 0) and Ludo.asks_pair(t, 2) and not t.has("pair_ask_by"))
	var bad := Ludo.new_game(["human", "off", "human", "off"], false, {pair_ask = true, pair_ask_by = [false]})
	check("rules: a pair_ask_by that isn't 4 long is ignored", not bad.has("pair_ask_by") and Ludo.asks_pair(bad, 0))
	# the move: Red's pawn on 7 rolls 3 onto its pawn on 10 (off the safe squares)
	for ask: bool in [true, false]:
		var g := Ludo.new_game(["human", "off", "human", "off"], false, {pair_ask = not ask, pair_ask_by = [ask, false, not ask, false]})
		g.tok[0] = [10, 7, -1, -1]
		Ludo.apply_roll(g, 3)
		var ev := Ludo.move(g, 1)
		var types: Array = ev.map(func(e): return e.type)
		if ask:
			check("rules: Red's own entry on: asked (pair_offer, phase pair_ask)", types.has("pair_offer") and g.phase == "pair_ask", types)
		else:
			check("rules: Red's own entry off (the table's on): pairs by itself", not types.has("pair_offer") and types.has("pair_formed") and g.pairs.size() == 1, types)


# ---------- the hello ----------

func _client(hub: Variant, name: String, prefs: Dictionary) -> NetClient:
	var c := NetClient.new()
	c.use_save = false
	c.prefs = prefs
	c.url_base = "ws://fake"
	var sess := "s-" + name
	c.session_fn = func() -> String: return sess
	c.profile_fn = func() -> Dictionary: return {name = name, avatar = "pawn-blue", frame = "classic"}
	c.make_transport = hub.transport_factory()
	c.http_fn = hub.http
	var log := []
	c.set_meta("log", log)
	c.message.connect(func(m: Dictionary): log.append(m))
	return c

func _pump(cs: Array, times := 4) -> void:
	for k in times:
		for c in cs:
			c._process(0.0)

func _hellos(c: NetClient) -> Array:
	return c.log_sent.filter(func(m): return m.get("t") == "hello")

func _hello() -> void:
	for want: bool in [true, false]:
		var room := NetFake.Room.new("PAQK22", 3)
		var c := _client(room, "Ana", {pair_ask = want})
		c.join(room.code)
		_pump([c])
		var h := _hellos(c)
		check("hello: carries your Ask before pairing (%s)" % want, h.size() == 1 and h[0].get("pair_ask") == want, h)
		c.free()
	var room := NetFake.Room.new("PAQK23", 3)
	var d := _client(room, "Bo", {})
	d.join(room.code)
	_pump([d])
	check("hello: no saved choice yet: on (the Settings default)", _hellos(d)[0].get("pair_ask") == true)
	d.free()


# ---------- the fake server ----------

func _fake_rooms() -> void:
	# a friend room: each person's own (the host's old room rule is ignored)
	var room := NetFake.Room.new("PAQF24", 5)
	var a := _client(room, "Ana", {pair_ask = false})
	var b := _client(room, "Bo", {pair_ask = true})
	for x in [a, b]:
		x.join(room.code)
		_pump([a, b])
	a.send_msg({t = "settings", pair_ask = true})      # (an old client's host toggle)
	a.send_msg({t = "start"})
	_pump([a, b])
	check("friend room: each person's own, Ana (host) off, Bo on", room.S.pair_ask == false and room.S.get("pair_ask_by") == [false, false, true, false], room.S.get("pair_ask_by"))
	a.free()
	b.free()
	# a quick room: each person's own
	var hub := NetFake.Hub.new(9)
	var cs := []
	for k in 2:
		var c := _client(hub, "P%d" % k, {pair_ask = k == 0})
		var q := NetQuick.new(c)
		q.matched.connect(func(code, tok): c.join(code, tok, true))
		_tree().root.add_child(c)
		_tree().root.add_child(q)
		q.search("ludo", 2)
		cs.append([c, q])
	var nodes := [cs[0][0], cs[0][1], cs[1][0], cs[1][1]]
	_pump(nodes)
	_pump(nodes, 6)                                      # (two people for a 2-table: matched at once)
	var qr: NetFake.Room = hub.rooms.values()[0] if hub.rooms.size() == 1 else null
	var ok := qr != null and qr.playing and qr.S.has("pair_ask_by")
	check("quick room: started with per-colour entries", ok, qr.S if qr else null)
	if ok:
		var by: Array = qr.S.pair_ask_by
		var c0 := -1
		for st in qr.seats:
			if st.name == "P0":
				c0 = int(st.color)
		check("quick room: P0 (on) is asked, P1 (off) is not", c0 >= 0 and by[c0] == true and by[2 - c0] == false and by[1] == false and by[3] == false, by)
	for x in cs:
		x[1].queue_free()
		x[0].queue_free()


# ---------- the live match ----------

func _frames(n: int) -> void:
	for k in n:
		await _tree().process_frame

func _until(f: Callable, secs := 8.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		if f.call():
			return true
		await _tree().process_frame
	return bool(f.call())

## A quick match against one ghost, you (Red) with `ask` as your setting; your pawns on 10 and 7, a 3 to roll.
## Returns {app, room, o, c, L} with the match at rest on your roll (or {} when it never got there).
func _setup(ask: bool) -> Dictionary:
	var hub := NetFake.Hub.new(17)
	var app = Live.LiveApp.new()
	_tree().root.add_child(app)
	app.build()
	var c := _client(hub, "Ana", {pair_ask = ask})
	var o := Online.new(app, c)
	o.reveal_fast = true
	o.coins_fn = func() -> int: return 5000
	o.level_fn = func() -> int: return 3
	app.add_child(o)
	o.open_quick("ludo")
	o.quick_sheet.select_table("practice")
	o.quick_sheet.find.emit(2)
	await _frames(4)
	var room: NetFake.Room = hub.mm.fill("ludo", 2, "practice")
	var L: LudoMatch = app.ludo
	var d := {app = app, room = room, o = o, c = c, L = L}
	var up := await _until(func(): return L.online and L._net_ready and not L._busy and L.ns != null and L.ns.my_turn())
	if not up:
		return d
	room.S.tok[L.ns.me] = [10, 7, -1, -1]
	room._broadcast(room._sync_msg())                   # (the board laid out for the test, as a snapshot)
	await _until(func(): return L.ns.state_hash() == room.state_hash() and L.ns.my_turn() and not L._busy and not L._net_pumping)
	room.dice = [3]
	L._on_dice()
	var chose := await _until(func(): return L.ns.S.phase == "choose" and L.ns.my_turn() and not L._busy and not L._net_pumping)
	d.ready = chose
	return d

func _end(d: Dictionary) -> void:
	(d.o as Online).leave()
	(d.app as Node).queue_free()
	await _frames(2)

func _pair_sent(c: NetClient) -> Array:
	return c.log_sent.filter(func(m): return m.get("t") == "pair")

func _live(ask: bool) -> void:
	var d := await _setup(ask)
	var L: LudoMatch = d.L
	var room: NetFake.Room = d.room
	var tag := "live (setting %s)" % ("on" if ask else "off")
	check("%s: your roll of 3, two pawns to choose from" % tag, bool(d.get("ready", false)))
	if not d.get("ready", false):
		await _end(d)
		return
	check("%s: the server dealt your setting to your colour" % tag, room.S.get("pair_ask_by", [])[L.ns.me] == ask, room.S.get("pair_ask_by"))
	L.move(1)                                            # the pawn on 7 onto the one on 10
	if ask:
		var shown := await _until(func(): return L.hud.pair_box.visible)
		check("%s: the 'Create a Pair?' prompt shows on your move" % tag, shown and room.S.phase == "pair_ask")
		check("%s: nothing is sent before you answer" % tag, _pair_sent(d.c).is_empty())
		L.hud._answer(false)                             # Keep single
		var sent := _pair_sent(d.c)
		check("%s: Keep single sends {t: pair, yes: false}" % tag, sent.size() == 1 and sent[0].get("yes") == false and int(sent[0].n) == L.ns.n, sent)
		var played := await _until(func(): return L.ns.n == room.n and room.S.phase != "pair_ask" and not L._busy and not L._net_pumping)
		check("%s: the server's pair act: the pawns stay single, the prompt is gone" % tag, played and room.S.pairs.is_empty()
			and L.ns.S.pairs.is_empty() and not L.hud.pair_box.visible and L.ns.mismatches == 0)
	else:
		var done := await _until(func(): return L.ns.n == room.n and not L._busy and not L._net_pumping and room.S.phase != "choose")
		await _frames(5)
		check("%s: no prompt, the pair formed by itself" % tag, done and not L.hud.pair_box.visible and room.S.pairs.size() == 1
			and L.ns.S.pairs.size() == 1 and _pair_sent(d.c).is_empty() and L.ns.mismatches == 0)
	await _end(d)

func _live_timeout() -> void:
	var d := await _setup(true)
	var L: LudoMatch = d.L
	var room: NetFake.Room = d.room
	if not d.get("ready", false):
		check("live timeout: set up", false)
		await _end(d)
		return
	L.move(1)
	var shown := await _until(func(): return L.hud.pair_box.visible)
	room.timeout()                                       # the pair step's deadline: the server answers for you
	var closed := await _until(func(): return L.ns.n == room.n and not L.hud.pair_box.visible and not L._busy and not L._net_pumping)
	await _frames(3)
	check("live timeout: the server's answer closes the open prompt; nothing is sent after it", shown and closed
		and _pair_sent(d.c).is_empty() and L.ns.mismatches == 0 and room.S.pairs.size() == 1)
	await _end(d)


# ---------- the rules' default answer, ghosts ----------

## A ghost (Yellow) lands on its own pawn: it is asked (no prompt for you), step() answers with Room.ghost_pair's
## odds (1: yes, 0: no), and your replica plays it out.
func _live_ghost(odds: float) -> void:
	var tag := "live ghost (%s)" % ("yes" if odds > 0.5 else "no")
	var hub := NetFake.Hub.new(23)
	var app = Live.LiveApp.new()
	_tree().root.add_child(app)
	app.build()
	var c := _client(hub, "Ana", {pair_ask = true})
	var o := Online.new(app, c)
	o.reveal_fast = true
	o.coins_fn = func() -> int: return 5000
	o.level_fn = func() -> int: return 3
	app.add_child(o)
	o.open_quick("ludo")
	o.quick_sheet.select_table("practice")
	o.quick_sheet.find.emit(2)
	await _frames(4)
	var room: NetFake.Room = hub.mm.fill("ludo", 2, "practice")
	var L: LudoMatch = app.ludo
	var d := {app = app, o = o}
	var up := await _until(func(): return L.online and L._net_ready and not L._busy and L.ns != null and L.ns.my_turn())
	var ghost := 2 - L.ns.me if up else -1
	check("%s: the ghost's colour is asked" % tag, up and room.S.pair_ask_by[ghost] == true, room.S.get("pair_ask_by"))
	if not up:
		await _end(d)
		return
	room.ghost_pair = odds
	room.S.tok[ghost] = [10, 7, -1, -1]
	room.S.turn = ghost
	room._broadcast(room._sync_msg())
	await _until(func(): return L.ns.state_hash() == room.state_hash() and not L._busy and not L._net_pumping)
	room.dice = [3]
	room.step()                                           # the ghost rolls 3
	await _until(func(): return L.ns.n == room.n and not L._busy and not L._net_pumping)
	room._act({k = "move", c = ghost, i = 1})            # (its pick, made here: 7 onto 10)
	var asked := await _until(func(): return L.ns.n == room.n and L.ns.S.phase == "pair_ask" and not L._net_pumping)
	await _frames(5)
	check("%s: the ghost is asked; you see no prompt and send nothing" % tag, asked and not L.hud.pair_box.visible and _pair_sent(c).is_empty())
	room.step()                                           # the ghost answers
	var played := await _until(func(): return L.ns.n == room.n and room.S.phase != "pair_ask" and not L._busy and not L._net_pumping)
	var want := 1 if odds > 0.5 else 0
	check("%s: its answer plays out on your board" % tag, played and room.S.pairs.size() == want and L.ns.S.pairs.size() == want
		and L.ns.mismatches == 0 and not L.hud.pair_box.visible, [room.S.pairs, L.ns.S.pairs])
	await _end(d)

func _defaults() -> void:
	var s := Ludo.new_game(["human", "off", "human", "off"], false, {pair_ask_by = [true, false, true, false]})
	check("default answer: false outside the question", Ludo.default_pair_answer(s) == false)
	s.tok[0] = [10, 7, -1, -1]
	Ludo.apply_roll(s, 3)
	Ludo.move(s, 1)
	check("default answer: off the safe squares, yes (as unasked)", s.phase == "pair_ask" and Ludo.default_pair_answer(s) == true)
	var t := Ludo.new_game(["human", "off", "human", "off"], false, {pair_ask_by = [true, false, true, false]})
	t.tok[0] = [8, 5, -1, -1]
	Ludo.apply_roll(t, 3)
	Ludo.move(t, 1)
	check("default answer: on a star square, no (unasked they wouldn't pair there)", t.phase == "pair_ask" and Ludo.default_pair_answer(t) == false)
	# the fake server's timeout uses it
	var room := NetFake.Room.new("PAQD25", 3)
	room.S = t
	room.playing = true
	room.seats = [{color = 0, id = 1}, {color = 2, id = 2}]
	room.timeout()
	check("fake timeout: the default answer (kept single on the star)", t.phase != "pair_ask" and t.pairs.is_empty())
	var g := Ludo.new_game(["human", "off", "human", "off"], false, {pair_ask_by = [true, false, true, false]})
	g.phase = "pair_ask"
	g.pending = {c = 0, i = 1, to = 10, extra = false, partner = 0}
	var calm := NetFake.Room.ghost_pair_odds(g)
	g.tok[2] = [32, -1, -1, -1]                           # Yellow's single 4 squares behind Red's 10
	var threat := NetFake.Room.ghost_pair_odds(g)
	g.pending.to = 8
	var safe := NetFake.Room.ghost_pair_odds(g)
	check("ghost odds (the server's GHOST_PAIR): threat > calm > safe", threat == 0.95 and calm == 0.7 and safe == 0.3, [threat, calm, safe])
