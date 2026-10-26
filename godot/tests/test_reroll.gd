extends "res://tests/test_suite.gd"
## Re-rolls in online matches (server/ECONOMY_V1.md section 4): RerollFlow's times, the HUD's "Roll again" button and the
## hold note, the replica staying consistent through rerolled + sync + act (Ludo and Snakes & Ladders: the hash matches
## the fake server's), and the live matches (LudoMatch / SLMatch through Online against the fake hub): the offer shows
## the button with its price, a tap sends {t: "reroll", n}, a hold keeps the next player's dice asleep until it ends, an
## `error hold` is answered by rolling at `until`, the errors hide the button, and a `sync` that arrives while the bad
## roll's dice are still tumbling is taken at once. Also the coin table's `over` (match_id, payouts by colour, the
## entry paid out once) and what the live match's result carries from it. Nothing here writes the save or opens a socket.

## A clock the test moves.
class Clock extends RefCounted:
	var ms := 1000.0
	func now() -> float:
		return ms

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func run() -> void:
	_flow()
	_button_and_hud()
	_replicas()
	_table_over()
	await _live_ludo()
	await _live_sl()
	await _live_table_result()


# ---------- RerollFlow ----------

func _flow() -> void:
	var ck := Clock.new()
	var rr := RerollFlow.new()
	rr.clock = ck.now
	rr.on_offer({n = 5, until = 5000, now = 2000, free = 0, gems = 12, cost = 5})
	check("flow: the offer's length is until - now (the server's own clock pair)", is_equal_approx(rr.offer_left_ms(), 3000.0) and rr.offer.total == 3000.0)
	check("flow: open for the state at n only", rr.offer_open(5) and not rr.offer_open(4) and not rr.offer_open(6))
	check("flow: price: gems when no free re-roll is held", not rr.is_free() and rr.offer.cost == 5 and rr.offer.gems == 12)
	ck.ms += 1200.0
	check("flow: the window runs down in our own time", is_equal_approx(rr.offer_left_ms(), 1800.0) and rr.offer_open(5))
	rr.mark_sent()
	check("flow: once sent it is not open again", not rr.offer_open(5))
	rr.on_offer({n = 5, until = 9_000_000, now = 100, free = 1, gems = 0, cost = 5})
	check("flow: a wrong clock can't hold the offer longer than the cap", rr.offer_left_ms() <= RerollFlow.MAX_MS and rr.is_free())
	ck.ms += 5000.0
	check("flow: expired", not rr.offer_open(5) and rr.offer_left_ms() == 0.0)
	rr.on_hold({c = 2, until = 10_000}, 8_500.0)
	check("flow: a hold ends at until by the server clock (1.5 s left)", is_equal_approx(rr.hold_left_ms(), 1500.0))
	check("flow: it holds everyone but the colour that may roll again", rr.holds(0) and rr.holds(1) and not rr.holds(2))
	ck.ms += 1600.0
	check("flow: …until it ends", not rr.holds(0) and rr.hold_left_ms() == 0.0)
	rr.on_hold({c = 2, until = 10_000})
	check("flow: no server clock yet: the whole 3 s window is assumed", is_equal_approx(rr.hold_left_ms(), RerollFlow.WINDOW_MS))
	rr.on_hold({c = 1, until = 1}, 90_000.0)
	check("flow: an `until` in the past holds nothing", not rr.holds(0))
	rr.clear()
	check("flow: clear", rr.offer.is_empty() and rr.hold.is_empty())
	check("flow: error copy", RerollFlow.error_text("reroll_used") != "" and RerollFlow.error_text("reroll_closed") != "" and RerollFlow.error_text("gems").contains("gems")
		and RerollFlow.error_text("hold") == "" and RerollFlow.is_error("hold") and not RerollFlow.is_error("stale"))


# ---------- the button and the HUD ----------

func _button_and_hud() -> void:
	var b := RerollButton.new()
	_tree().root.add_child(b)
	var taps := []
	b.pressed.connect(func(): taps.append(1))
	check("button: hidden until an offer", not b.visible)
	b.tap()
	check("button: a tap while hidden does nothing", taps.is_empty())
	b.show_offer(3000.0, 3000.0, true, 5)
	check("button: free re-roll: 'Free'", b.visible and b.price_text() == "Free")
	b.show_offer(3000.0, 3000.0, false, 5)
	check("button: no free re-roll: the gem price '5'", b.price_text() == "5")
	check("button: 56 px tall, at least a thumb wide", b.size.y >= 56.0 and b.size.x >= UIKit.TAP)
	b.tap()
	check("button: a tap emits once", taps.size() == 1)
	b.set_busy(true)
	b.tap()
	check("button: busy (a spinner) takes no second tap", taps.size() == 1 and b.busy)
	b.hide_offer()
	check("button: hidden", not b.visible and not b.busy)
	b.show_offer(1500.0, 3000.0, true, 5)
	b._process(0.0)
	check("button: the ring is half full at 1.5 s of 3", is_equal_approx(b.left_ms / b.total_ms, 0.5) or b.left_ms <= 1500.0)
	b.free()

	var hud := LudoHUD.new()
	hud.size = Vector2(390, 844)
	_tree().root.add_child(hud)
	var seats := [{color = 0, id = "m1", name = "Ana", avatar = "pawn-green", frame = "classic", bot = false, online = true},
		{color = 2, id = "m2", name = "Rahim", avatar = "pawn-blue", frame = "classic", bot = false, online = true}]
	var ns := NetLudo.new()
	ns.begin({n = 0, seats = seats, state = LudoRules.new_game(["human", "off", "human", "off"])}, "m1")
	hud.set_online(true, ns.me, ns.seats)
	hud.setup(ns.S)
	hud.update(ns.S, 0)
	check("hud: your turn: the dice are awake", hud.dice.active)
	hud.roll_locked = true
	hud.refresh_roll()
	check("hud: a hold on another player's re-roll: the dice sleep", not hud.dice.active)
	hud.roll_locked = false
	hud.refresh_roll()
	check("hud: …and wake when it ends", hud.dice.active)
	var pressed := []
	hud.reroll_pressed.connect(func(): pressed.append(1))
	hud.show_reroll(3000.0, 3000.0, false, 5)
	var br := Rect2(hud.reroll_button.position, hud.reroll_button.size)
	var clear := true
	for r in hud.tile_rects():
		clear = clear and not br.intersects(r)
	check("hud: 'Roll again' shows level with the tile row, inside the screen, clear of the tiles", hud.reroll_button.visible
		and Rect2(Vector2.ZERO, hud.size).encloses(br) and clear, [br, hud.tile_rects()])
	hud.reroll_button.tap()
	check("hud: its tap is reroll_pressed", pressed.size() == 1)
	hud.hide_reroll()
	check("hud: hide", not hud.reroll_button.visible)
	hud.set_hold("Rahim")
	check("hud: 'Rahim may roll again…'", hud.hold_note.visible and hud.hold_note.label.text == "Rahim may roll again…"
		and hud.hold_note.position.y > hud.top.bottom() and Rect2(Vector2.ZERO, hud.size).encloses(Rect2(hud.hold_note.position, hud.hold_note.size)))
	hud.set_hold("")
	check("hud: no note", not hud.hold_note.visible)
	hud.show_reroll(3000.0, 3000.0, true, 5)
	hud.hide_for_result()
	check("hud: the result hides both", not hud.reroll_button.visible and not hud.hold_note.visible)
	hud.show_reroll(3000.0, 3000.0, true, 5)
	check("hud: no button after the game", not hud.reroll_button.visible)
	hud.free()


# ---------- the replica through rerolled + sync + act (no animation) ----------

func _client(hub: Variant, name: String) -> NetClient:
	var c := NetClient.new()
	c.use_save = false
	c.prefs = {}
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

func _got(c: Object, t: String) -> Array:
	return (c.get_meta("log") as Array).filter(func(m): return m.get("t") == t)

## A quick room with one person (+ a ghost) and the person's replica; returns {hub, room, c, q, ns}.
func _quick(game: String, n_free := 1, n_gems := 0, table := "practice") -> Dictionary:
	var hub := NetFake.Hub.new(21)
	var c := _client(hub, "Ana")
	var q := NetQuick.new(c)
	_tree().root.add_child(c)
	_tree().root.add_child(q)
	var tok := [""]
	var code := [""]
	q.matched.connect(func(cd, t): code[0] = cd; tok[0] = t)
	q.search(game, 2, table)
	_pump([c, q])
	var room := hub.mm.fill(game, 2, table)
	room.rr_default = {free = n_free, gems = n_gems}
	_pump([c, q])
	var ns := NetReplica.for_game(game)
	c.start.connect(func(m: Dictionary): ns.begin(m, c.member_id))
	c.join(code[0], tok[0], true)
	_pump([c, q], 8)
	return {hub = hub, room = room, c = c, q = q, ns = ns}

func _drain(d: Dictionary) -> void:
	var c: NetClient = d.c
	var ns: NetReplica = d.ns
	for m: Dictionary in _got(c, "act") + _got(c, "sync"):
		pass

## Plays everything the client got after index `from` into the replica, in order; returns the messages.
func _feed(d: Dictionary, from: int) -> Array:
	var ns: NetReplica = d.ns
	var log: Array = (d.c as NetClient).get_meta("log")
	var seen := []
	for k in range(from, log.size()):
		var m: Dictionary = log[k]
		if str(m.t) in ["act", "sync", "over"]:
			ns.push(m)
			seen.append(m)
	var out := []
	while true:
		var m := ns.next()
		if m.is_empty():
			break
		match str(m.t):
			"sync":
				ns.begin(m, (d.c as NetClient).member_id)
			"act":
				ns.play(m)
		out.append(m.t)
	return out

func _replicas() -> void:
	for game in ["ludo", "sl"]:
		var d := _quick(game)
		var room: NetFake.Room = d.room
		var c: NetClient = d.c
		var ns: NetReplica = d.ns
		var tag := "[%s] " % game
		check(tag + "replica: a quick match started, your turn, a free re-roll in your pocket", room.playing and ns.my_turn() and int(room.members[0].rr.free) == 1, [room.playing, ns.my_turn()])
		var log: Array = c.get_meta("log")
		var from := log.size()
		room.force_bad_roll(ns.me)
		_pump([c], 3)
		check(tag + "a forced bad roll: the sync restores it (replica in step)", _feed(d, from) == ["sync"] and ns.my_turn() and ns.state_hash() == room.state_hash())
		from = log.size()
		c.send_msg(ns.request("roll"))
		_pump([c], 3)
		var offers := _got(c, "reroll_offer")
		var holds := _got(c, "hold")
		check(tag + "a bad roll: reroll_offer to you with n, free, gems and the cost; hold for everyone", offers.size() == 1 and int(offers[0].n) == room.n and int(offers[0].free) == 1
			and int(offers[0].cost) == 5 and offers[0].has("until") and offers[0].has("now") and holds.size() == 1 and int(holds[0].c) == ns.me, [offers, holds])
		check(tag + "the bad roll's act plays and the hashes match", _feed(d, from) == ["act"] and ns.verify({h = room.acts.back().h}) and ns.n == room.n)
		var bad_n := ns.n
		from = log.size()
		c.send_msg({t = "reroll", n = ns.n})
		_pump([c], 3)
		check(tag + "rerolled {c, paid free} to everyone", _got(c, "rerolled").size() == 1 and int(_got(c, "rerolled")[0].c) == ns.me and _got(c, "rerolled")[0].paid == "free")
		check(tag + "then sync, then the new roll's act, in order", _feed(d, from) == ["sync", "act"], _feed(d, from))
		check(tag + "the replica is in step with the server (hash, n)", ns.state_hash() == room.state_hash() and ns.n == room.n and ns.mismatches == 0 and ns.n == bad_n,
			[ns.state_hash(), room.state_hash(), ns.n, room.n, bad_n])
		check(tag + "the server paid the free re-roll", int(room.members[0].rr.free) == 0 and room.rr_log.size() == 1)
		# once per match: no second offer
		check(tag + "used: the colour can't be offered again", room.rr_used.has(ns.me))
		from = log.size()
		c.send_msg({t = "reroll", n = ns.n})
		_pump([c], 3)
		var errs := _got(c, "error")
		check(tag + "a second re-roll is refused (reroll_closed: no offer open)", errs.size() >= 1 and str(errs.back().code) in ["reroll_closed", "reroll_used"], errs)
		# the queue: a sync drops the acts waiting before it
		var q := NetReplica.for_game(game)
		q.push({t = "act", n = 3, a = {k = "roll", c = 0, v = 2}})
		q.push({t = "sync", n = 2})
		q.push({t = "act", n = 2, a = {k = "roll", c = 0, v = 4}})
		check(tag + "the acts queued before a sync are dropped, the ones after stay", q.pending() == 2 and q.next().t == "sync" and q.pending() == 1)
		d.q.free()
		d.c.free()
	# gems: no free re-roll, 5 gems
	var g := _quick("ludo", 0, 12)
	var ns2: NetReplica = g.ns
	var c2: NetClient = g.c
	var room2: NetFake.Room = g.room
	room2.dice = [3]
	c2.send_msg(ns2.request("roll"))
	_pump([c2], 3)
	var offer := _got(c2, "reroll_offer")
	check("gems: the offer has no free re-roll and 12 gems", offer.size() == 1 and int(offer[0].free) == 0 and int(offer[0].gems) == 12)
	c2.send_msg({t = "reroll", n = int(offer[0].n)})
	_pump([c2], 3)
	check("gems: paid in gems (5)", _got(c2, "rerolled")[0].paid == "gems" and int(room2.members[0].rr.gems) == 7)
	g.q.free()
	g.c.free()
	# nothing to pay with: no offer at all
	var z := _quick("ludo", 0, 4)
	(z.room as NetFake.Room).dice = [3]
	(z.c as NetClient).send_msg((z.ns as NetReplica).request("roll"))
	_pump([z.c], 3)
	check("no free re-roll and under 5 gems: no offer, no hold", _got(z.c, "reroll_offer").is_empty() and _got(z.c, "hold").is_empty())
	# errors
	var e := _quick("ludo", 1, 0)
	var er: NetFake.Room = e.room
	var ec: NetClient = e.c
	er.dice = [3]
	ec.send_msg((e.ns as NetReplica).request("roll"))
	_pump([ec], 3)
	ec.send_msg({t = "reroll", n = 99})
	_pump([ec], 3)
	check("errors: a wrong n is reroll_closed", str(_got(ec, "error").back().code) == "reroll_closed")
	(er.members[0] as Dictionary).rr = {free = 0, gems = 1}
	ec.send_msg({t = "reroll", n = er.n})
	_pump([ec], 3)
	check("errors: nothing left to pay with is `gems`, and the hold ends", str(_got(ec, "error").back().code) == "gems" and er.rr_offer.is_empty())
	e.q.free()
	e.c.free()


# ---------- live matches through Online ----------

class LiveApp extends Node:
	var sheet_layer := Control.new()
	var ui_root := Control.new()
	var screen := "home"
	var speed := 0.05
	var paused := false
	var safe_top := 0.0
	var safe_bottom := 0.0
	var ludo: LudoMatch
	var sl: SLMatch
	var world: TableWorld
	var hud: LudoHUD
	var sl_board: SLBoard
	var homes := 0

	func _init() -> void:
		sheet_layer.size = Vector2(390, 844)
		ui_root.size = Vector2(390, 844)
		add_child(ui_root)
		add_child(sheet_layer)

	func build() -> void:
		world = TableWorld.new()
		add_child(world)
		hud = LudoHUD.new()
		hud.size = Vector2(390, 844)
		ui_root.add_child(hud)
		ludo = LudoMatch.new(self, world, hud)
		ludo.save_matches = false
		add_child(ludo)
		sl_board = SLBoard.new()
		add_child(sl_board)
		sl = SLMatch.new(self, world, sl_board)
		add_child(sl)
		sl.build_hud(ui_root)
		sl.hud.visible = false

	func start_online(m: Dictionary, n: Object) -> void:
		screen = "ludo"
		ludo.start_online(m, n)

	func start_online_sl(m: Dictionary, n: Object) -> void:
		screen = "sl"
		sl.hud.visible = true
		sl.start_online(m, n)

	func _top_sheet() -> Control:
		return Sheet.top_sheet(sheet_layer)

	func go_home() -> void:
		homes += 1
		screen = "home"

	func online_host_changed(_on: bool) -> void:
		pass

	func online_closed() -> void:
		pass

func _frames(n: int) -> void:
	for k in n:
		await _tree().process_frame

## Waits until f() (up to `secs` of real time: holds and windows run on the clock).
func _until(f: Callable, secs := 8.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		if f.call():
			return true
		await _tree().process_frame
	return bool(f.call())

## A live game of `game` in a quick room with one person: {app, hub, room, o, c}. The person has `free` re-rolls.
func _live(game: String, n_free := 1, n_gems := 0, table := "practice") -> Dictionary:
	var hub := NetFake.Hub.new(31)
	var app := LiveApp.new()
	_tree().root.add_child(app)
	app.build()
	var c := _client(hub, "Ana")
	var o := Online.new(app, c)
	o.reveal_fast = true
	o.coins_fn = func() -> int: return 5000
	o.level_fn = func() -> int: return 3
	app.add_child(o)
	o.open_quick(game)
	o.quick_sheet.select_table(table)
	o.quick_sheet.find.emit(2)
	await _frames(4)
	var room := hub.mm.fill(game, 2, table)
	room.rr_default = {free = n_free, gems = n_gems}
	room.window_ms = 1500
	return {app = app, hub = hub, room = room, o = o, c = c}

func _live_end(d: Dictionary) -> void:
	(d.o as Online).leave()
	(d.app as Node).queue_free()
	await _frames(2)

func _find_toast(text: String) -> bool:
	for n in _tree().root.find_children("Toast", "PanelContainer", true, false):
		for l in (n as Node).find_children("Text", "Label", true, false):
			if (l as Label).text.contains(text):
				return true
	return false

func _sent(c: NetClient, t: String) -> Array:
	return c.log_sent.filter(func(m): return m.get("t") == t)

func _acts(c: NetClient) -> int:
	return _got(c, "act").size()

## The match has taken in everything the server sent and is at rest.
func _rest_ludo(L: LudoMatch, room: NetFake.Room) -> bool:
	return L.ns.n == room.n and L.ns.state_hash() == room.state_hash() and not L._net_pumping and L.ns.pending() == 0 and not L._busy

func _rest_sl(S: SLMatch, room: NetFake.Room) -> bool:
	return S.ns.n == room.n and S.ns.state_hash() == room.state_hash() and not S._net_pumping and S.ns.pending() == 0 and not S._busy

func _up_ludo(d: Dictionary) -> bool:
	var L: LudoMatch = d.app.ludo
	return await _until(func(): return L.online and L._net_ready and not L._busy and L.ns != null and L.ns.my_turn())

func _live_ludo() -> void:
	# --- the offer, the tap, the new roll
	var d := await _live("ludo")
	var app: LiveApp = d.app
	var room: NetFake.Room = d.room
	var c: NetClient = d.c
	var o: Online = d.o
	var L: LudoMatch = app.ludo
	var ok := await _up_ludo(d)
	check("live ludo: the quick match is up and it is your turn", ok and o.state == "match")
	if not ok:
		await _live_end(d)
		return
	room.dice = [3]
	L._on_dice()
	var shown := await _until(func(): return L.hud.reroll_button.visible)
	check("live ludo: after your bad roll 'Roll again' shows, 'Free', with the ring running", shown and L.hud.reroll_button.price_text() == "Free" and L.hud.reroll_button.left_ms > 0.0)
	check("live ludo: the hold is yours: no note, nothing locks your dice", not L.hud.hold_note.visible and not L.rr.holds(L.ns.me))
	var n_at := L.ns.n
	var acts_before := _acts(c)
	L.hud.reroll_button.tap()
	var sent := _sent(c, "reroll")
	check("live ludo: a tap sends {t: reroll, n} with the current n", sent.size() == 1 and int(sent[0].n) == n_at and L.hud.reroll_button.busy, [sent, n_at])
	L.hud.reroll_button.tap()
	check("live ludo: …only once (a spinner meanwhile)", _sent(c, "reroll").size() == 1)
	var done := await _until(func(): return _got(c, "rerolled").size() == 1 and _acts(c) > acts_before and _rest_ludo(L, room))
	check("live ludo: rerolled + sync + the new roll played: the replica matches the server", done and L.ns.mismatches == 0 and _sent(c, "sync_req").is_empty(),
		[L.ns.n, room.n, L.ns.mismatches])
	check("live ludo: the button is gone and everyone saw 'You rolled again'", not L.hud.reroll_button.visible and _find_toast("rolled again"),
		[L.hud.reroll_button.visible, _find_toast("rolled again")])
	check("live ludo: the dice are not stuck", not L.hud.dice.rolling and not L._rr_wait)
	# once per match: another bad roll has no offer
	room.force_bad_roll(L.ns.me, 3)
	await _until(func(): return L.ns.state_hash() == room.state_hash() and L.ns.my_turn() and not L._busy)
	var acts2 := _acts(c)
	L._on_dice()
	await _until(func(): return _acts(c) > acts2 and _rest_ludo(L, room))
	await _frames(10)
	check("live ludo: used once: no second offer or button", not L.hud.reroll_button.visible and _got(c, "reroll_offer").size() == 1 and _sent(c, "reroll").size() == 1)
	await _live_end(d)

	# --- the next player's hold: a ghost's bad roll, the person is next
	var h := await _live("ludo")
	app = h.app
	room = h.room
	c = h.c
	L = app.ludo
	await _until(func(): return L.online and L._net_ready and not L._busy and L.ns != null)
	room.ghost_reroll = 1.0
	room.window_ms = 1400
	room.force_bad_roll(2, 3)                        # the ghost's turn with a bad roll coming
	await _until(func(): return L.ns.state_hash() == room.state_hash() and L.ns.turn_color() == 2)
	room.step()                                      # the ghost rolls badly: its own hold
	var held := await _until(func(): return L.rr.holds(L.ns.me) and L.ns.turn_color() == L.ns.me and not L._busy)
	check("live ludo: a hold on the ghost's re-roll: it is your turn but the dice sleep", held and L.hud.roll_locked and not L.hud.dice.active)
	check("live ludo: …with 'name may roll again…' under the tiles", L.hud.hold_note.visible and L.hud.hold_note.label.text.ends_with(" may roll again…")
		and L.hud.hold_note.label.text.begins_with(str(room.seats[1].name)), L.hud.hold_note.label.text)
	var rolls_before := _sent(c, "roll").size()
	L._on_dice()
	check("live ludo: a tap on the sleeping dice sends nothing", _sent(c, "roll").size() == rolls_before)
	var woke := await _until(func(): return not L.rr.holds(L.ns.me) and L.hud.dice.active, 5.0)
	check("live ludo: when the hold ends the dice wake and the note goes", woke and not L.hud.roll_locked and not L.hud.hold_note.visible,
		[woke, L.hud.roll_locked, L.hud.hold_note.visible, L.rr.hold, L.hud.dice.active])
	await _live_end(h)

	# --- error hold: our roll goes out early; the server says wait; the match rolls at `until`
	var e := await _live("ludo")
	app = e.app
	room = e.room
	c = e.c
	L = app.ludo
	await _up_ludo(e)
	room.rr_offer = {c = 2, bn = 0, n = room.n, before = {}, until = NetFake.Room._now() + 900.0, ghost = true}   # a hold the match hasn't heard of
	var r0 := _sent(c, "roll").size()
	var acts0 := _acts(c)
	L.roll()
	var errd := await _until(func(): return not _find_error(c, "hold").is_empty(), 3.0)
	check("live ludo: the server's `error hold` comes back (and is not an alert: the dice are held)", errd and L.rr.holds(L.ns.me) and not L.hud.dice.active)
	check("live ludo: …the roll isn't resent while the hold runs", _sent(c, "roll").size() == r0 + 1 and _acts(c) == acts0)
	var rolled := await _until(func(): return _sent(c, "roll").size() == r0 + 2 and _acts(c) > acts0, 5.0)
	check("live ludo: …and it goes out again once the hold ends (the server rolls)", rolled, [_sent(c, "roll").size(), r0, _acts(c), acts0])
	await _live_end(e)

	# --- the errors hide the button
	var f := await _live("ludo")
	app = f.app
	room = f.room
	L = app.ludo
	await _up_ludo(f)
	L.net_reroll_offer({n = L.ns.n, until = 4000, now = 1000, free = 1, gems = 0, cost = 5})
	await _until(func(): return L.hud.reroll_button.visible, 2.0)
	L.net_error({code = "reroll_used"})
	await _frames(3)
	check("live ludo: reroll_used: a short toast, the button goes", not L.hud.reroll_button.visible and _find_toast("already rolled again"))
	L.net_reroll_offer({n = L.ns.n, until = 4000, now = 1000, free = 0, gems = 9, cost = 5})
	await _until(func(): return L.hud.reroll_button.visible, 2.0)
	check("live ludo: a gems offer shows its price", L.hud.reroll_button.price_text() == "5")
	L.net_error({code = "gems"})
	await _frames(3)
	check("live ludo: gems: not enough gems, the button goes", not L.hud.reroll_button.visible and _find_toast("gems"))
	L.net_reroll_offer({n = L.ns.n, until = 4000, now = 1000, free = 0, gems = 9, cost = 5})
	await _until(func(): return L.hud.reroll_button.visible, 2.0)
	L.net_error({code = "reroll_closed"})
	await _frames(3)
	check("live ludo: reroll_closed: too late, the button goes", not L.hud.reroll_button.visible and _find_toast("Too late"))
	L.net_reroll_offer({n = L.ns.n + 3, until = 4000, now = 1000, free = 0, gems = 9, cost = 5})
	await _frames(3)
	check("live ludo: an offer for another state shows no button", not L.hud.reroll_button.visible)
	await _live_end(f)

	# --- a sync in the middle of the bad roll's animation (a ghost re-rolls at once)
	var m := await _live("ludo")
	app = m.app
	room = m.room
	c = m.c
	L = app.ludo
	await _until(func(): return L.online and L._net_ready and not L._busy and L.ns != null)
	room.ghost_reroll = 1.0
	room.ghost_take = true
	room.force_bad_roll(2, 3)
	await _until(func(): return L.ns.state_hash() == room.state_hash() and L.ns.turn_color() == 2)
	var aborts0 := L.aborts
	room.hold = true                                 # everything the ghost does arrives in one go
	room.dice = [3, 6]
	room.step()                                      # bad roll + hold
	room.step()                                      # the ghost takes it: rerolled, sync, the new roll (a 6)
	room.hold = false
	room.release()
	var settled := await _until(func(): return _got(c, "rerolled").size() == 1 and _rest_ludo(L, room))
	check("live ludo: the sync arrived while the bad roll's dice tumbled: that animation was ended", L.aborts == aborts0 + 1, [L.aborts, aborts0])
	check("live ludo: the board settled on the synced state, then the new roll played: the hash matches", settled and L.ns.mismatches == 0 and _sent(c, "sync_req").is_empty()
		and not L.hud.dice.rolling, [L.ns.n, room.n, L.ns.mismatches, _sent(c, "sync_req").size()])
	check("live ludo: the board shows the synced state (pawn out of the base after the 6)", int(L.S.tok[2][0]) == int(room.S.tok[2][0]) and L.S.tok == room.S.tok)
	check("live ludo: everyone saw '<name> rolled again'", _find_toast("rolled again"))
	check("live ludo: nobody is held any more", not L.rr.holds(L.ns.me) and not L.hud.hold_note.visible and not L.hud.roll_locked)
	await _live_end(m)

func _find_error(c: NetClient, code: String) -> Array:
	return (c.get_meta("log") as Array).filter(func(x): return x.get("t") == "error" and x.get("code") == code)

func _live_sl() -> void:
	var d := await _live("sl")
	var app: LiveApp = d.app
	var room: NetFake.Room = d.room
	var c: NetClient = d.c
	var S: SLMatch = app.sl
	var ok := await _until(func(): return S.online and S._net_ready and not S._busy and S.ns != null and S.ns.my_turn())
	check("live sl: the quick match is up and it is your turn", ok)
	if not ok:
		await _live_end(d)
		return
	room.force_bad_roll(S.ns.me, 3)                  # one square before the snake at 47
	await _until(func(): return S.ns.state_hash() == room.state_hash() and S.ns.my_turn() and not S._busy)
	S._on_dice()
	var shown := await _until(func(): return S.reroll_button.visible)
	check("live sl: after your snake 'Roll again' shows, 'Free'", shown and S.reroll_button.price_text() == "Free")
	check("live sl: it sits above the dice, inside the screen", Rect2(Vector2.ZERO, S.hud.size).encloses(Rect2(S.reroll_button.position, S.reroll_button.size))
		and S.reroll_button.position.y + S.reroll_button.size.y <= S.dice.position.y, [S.reroll_button.position, S.dice.position])
	var n_at := S.ns.n
	var acts_before := _acts(c)
	S.reroll_button.tap()
	var sent := _sent(c, "reroll")
	check("live sl: a tap sends {t: reroll, n}", sent.size() == 1 and int(sent[0].n) == n_at and S.reroll_button.busy, [sent, n_at])
	var done := await _until(func(): return _got(c, "rerolled").size() == 1 and _acts(c) > acts_before and _rest_sl(S, room))
	check("live sl: rerolled + sync + the new roll: the replica matches the server", done and S.ns.mismatches == 0 and _sent(c, "sync_req").is_empty(), [S.ns.n, room.n, S.ns.mismatches])
	check("live sl: button gone, 'You rolled again' toast", not S.reroll_button.visible and _find_toast("rolled again"), [S.reroll_button.visible, _find_toast("rolled again")])
	await _live_end(d)

	# --- hold on a ghost's snake, then a mid-turn sync
	var h := await _live("sl")
	app = h.app
	room = h.room
	c = h.c
	S = app.sl
	await _until(func(): return S.online and S._net_ready and not S._busy and S.ns != null)
	room.ghost_reroll = 1.0
	room.window_ms = 1400
	var gc: int = int(room.seats[1].color)
	room.force_bad_roll(gc, 3)
	await _until(func(): return S.ns.state_hash() == room.state_hash() and S.ns.turn_color() == gc)
	room.step()
	var held := await _until(func(): return S.rr.holds(S.ns.me) and S.ns.my_turn() and not S._busy)
	check("live sl: a hold on the ghost's re-roll: the dice sleep and the note names it", held and S.hold_note.visible and S.hold_note.label.text.ends_with(" may roll again…") and not S.dice.active,
		[held, S.hold_note.label.text])
	var woke := await _until(func(): return not S.rr.holds(S.ns.me) and S.dice.active and not S.hold_note.visible, 5.0)
	check("live sl: the hold ends: the dice wake, the note goes", woke)
	room.end_hold()
	room.ghost_take = true
	room.force_bad_roll(gc, 3)
	await _until(func(): return S.ns.state_hash() == room.state_hash() and S.ns.turn_color() == gc)
	var aborts0 := S.aborts
	room.hold = true
	room.dice = [3, 2]
	room.step()
	room.step()
	room.hold = false
	room.release()
	var settled := await _until(func(): return _got(c, "rerolled").size() == 1 and _rest_sl(S, room))
	check("live sl: a sync while the pawn is still sliding ends that animation", S.aborts == aborts0 + 1, [S.aborts, aborts0])
	check("live sl: …the board is the synced state, then the new roll plays: the hash matches", settled and S.ns.mismatches == 0 and _sent(c, "sync_req").is_empty()
		and not S.dice.rolling, [S.ns.n, room.n, S.ns.mismatches])
	await _live_end(h)


# ---------- the coin table's result ----------

func _table_over() -> void:
	for game in ["ludo", "sl"]:
		var d := _quick(game, 0, 0, "t100")
		var room: NetFake.Room = d.room
		var ns: NetReplica = d.ns
		var hub: NetFake.Hub = d.hub
		var tag := "[%s] " % game
		check(tag + "table: the entry was taken at the queue (5000 - 100) and the room carries the table", hub.mm.coins == 4900 and room.table == {tier = "t100", entry = 100} and room.quick)
		# the person finishes first
		if game == "sl":
			for p in room.S.players:
				p.pos = 100 if int(p.c) == ns.me else 40
			room.S.turn = 0
			room.S.phase = "roll"
			room._act({k = "end"})
		else:
			for c in 4:
				if room.S.players[c] != "off":
					room.S.tok[c] = [56, 56, 56, 56] if c == ns.me else [10, -1, -1, -1]
			room._act({k = "end"})
		var over := room._over_msg()
		var other: int = int(room.seats[1].color)
		check(tag + "table: over carries match_id and table {tier, entry, payouts by colour}", str(over.match_id) == "QM%s-1" % room.code.substr(2) and over.table.tier == "t100" and over.table.entry == 100
			and over.table.payouts[str(ns.me)] == 180 and over.table.payouts[str(other)] == 0, over)
		check(tag + "table: the winner's payout reaches their coins once (5000 - 100 + 180)", hub.mm.coins == 5080)
		room._over_msg()
		check(tag + "table: asking for `over` again pays nothing more", hub.mm.coins == 5080)
		var tr := NetReplica.table_result(JSON.parse_string(JSON.stringify(over)), ns.me)
		check(tag + "table_result: your payout, the entry, the match id (JSON round trip)", tr.payout == 180 and tr.entry == 100 and tr.tier == "t100" and tr.match_id == over.match_id)
		check(tag + "table_result: the loser's is 0", NetReplica.table_result(over, other).payout == 0)
		check(tag + "table_result: a friends' room has none; watching gets 0", NetReplica.table_result({t = "over"}, 0).is_empty() and NetReplica.table_result(over, -1).payout == 0)
		d.q.free()
		d.c.free()
	check("coins: Practice grants win 50 / finish 10 (XP as before); a paid table none here; friends' rooms as before",
		NetReplica.online_coins("ludo", "win", {tier = "practice", entry = 0}) == 50 and NetReplica.online_coins("sl", "finish", {tier = "practice", entry = 0}) == 10
		and NetReplica.online_coins("ludo", "win", {tier = "t100", entry = 100}) == 0 and NetReplica.online_coins("ludo", "win", {}) == 150
		and NetReplica.online_coins("ludo", "left", {tier = "practice", entry = 0}) == 0)
	# a 4-player table pays 1st and 2nd
	var room := NetFake.Room.new("QMTEST", 3)
	room.quick = true
	room.table = {tier = "t500", entry = 500}
	room.game = "ludo"
	room.S = LudoRules.new_game(["human", "human", "human", "human"], false)
	room.seats = [{color = 0, id = 1, left = false}, {color = 1, id = 2, left = false}, {color = 2, id = 3, left = true}, {color = 3, id = 4, left = false}]
	room.S.tok = [[56, 56, 56, 56], [56, 56, 20, 20], [56, 56, 56, 30], [1, 1, 1, 1]]
	room.S.phase = "over"
	room.S.winner = 0
	room.S.finished = [0]
	var pays := room.payouts()
	check("table: 4 players: 1st 1,350, 2nd 450, the seat that left gets none even ahead", pays["0"] == 1350 and pays["1"] == 450 and pays["2"] == 0 and pays["3"] == 0, pays)

func _live_table_result() -> void:
	Account.set_instance(Account.new())
	var acc := Account.instance()
	acc.enabled = true
	var d := await _live("ludo", 0, 0, "t100")
	var app: LiveApp = d.app
	var room: NetFake.Room = d.room
	var L: LudoMatch = app.ludo
	var ok := await _up_ludo(d)
	var got := []
	L.finished.connect(func(r: Dictionary): got.append(r))
	if ok:
		var me: int = L.ns.me
		for c in 4:
			if room.S.players[c] != "off":
				room.S.tok[c] = [56, 56, 56, 52] if c == me else [56, 56, 40, 30]
		room.S.pairs = []
		room.S.phase = "roll"
		room.S.pending = {}
		room.S.sixes = 0
		room.S.turn = me
		room.dice = [4]
		room._broadcast(room._sync_msg())
		await _until(func(): return L.ns.state_hash() == room.state_hash() and not L._busy)
		L._on_dice()
		var t0 := Time.get_ticks_msec()
		while got.is_empty() and Time.get_ticks_msec() - t0 < 15000:     # (animations run on the clock, not on frames)
			if L.S.phase == "choose" and not L._busy and L.ns.my_turn() and not L.board.movable.is_empty():
				L.move(int(LudoRules.units(L.S)[0].token))
			await _frames(1)
	check("live table: the match ended with a result", ok and got.size() == 1, got.size())
	if not got.is_empty():
		var r: Dictionary = got[0]
		check("live table: the result carries the table {tier, entry, payout 180, match_id} and the prize as the coins reward", r.table.tier == "t100" and r.table.entry == 100
			and r.table.payout == 180 and r.reward == 180 and str(r.table.match_id) == room.match_id() and r.online, [r.get("table"), r.get("reward")])
		var screen := ResultScreen.new(r.merged({ads = true, host = true}))
		check("live table: …as a result card with the prize and the double button", screen.is_coin_table() and screen.table_payout() == 180 and screen.double_button != null)
		screen.free()
	await _live_end(d)
	Account.set_instance(null)
	acc.free()
