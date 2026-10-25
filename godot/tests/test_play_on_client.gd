extends "res://tests/test_suite.gd"
## Play on, client side: the place badges and dimming of finished sides (LudoHUD.done_place, PlayerTile.set_done,
## SLMatch.done_place / SLTile.set_done), the "You finished 1st!" card (FinishCard), the result copy for a 2nd place,
## the claim's placing, the replicas applying the server's {k: "end"} (NetLudo / NetSL), and the fake server's play
## on (over only at the end, {k: "end"} when only bots / ghosts are left unfinished). Nothing here writes the save.

const NEAR := [56, 56, 56, 55]
const MAIN := preload("res://scripts/main.gd")

func run() -> void:
	_badges()
	_card()
	_copy_and_claim()
	_replicas()
	_fake_room()
	_fake_room_all_leave()
	_fake_quick()


# ---------- tiles ----------

func _badges() -> void:
	var t := base()
	t[0] = [56, 56, 56, 56]; t[2] = [56, 56, 56, 56]; t[1][0] = 20
	var s := state(t, [], {finished = [2, 0]})
	check("done_place: places in finish order", LudoHUD.done_place(s, 2) == 1 and LudoHUD.done_place(s, 0) == 2 and LudoHUD.done_place(s, 1) == 0)
	s.phase = "over"; s.finished = [2, 0, 1, 3]
	check("done_place: a side ranked by progress at the end gets no badge", LudoHUD.done_place(s, 1) == 0 and LudoHUD.done_place(s, 3) == 0)
	t = base(); t[0] = [56, 56, 56, 56]
	s = state(t, [], {teams = true, finished = [0]})
	check("done_place in Teams: a colour home alone is still playing (Free Hand)", LudoHUD.done_place(s, 0) == 0)
	s.tok[2] = [56, 56, 56, 56]
	check("done_place in Teams: both home -> the team's place", LudoHUD.done_place(s, 0) == 1 and LudoHUD.done_place(s, 2) == 1)
	var tile := PlayerTile.new(0, "left")
	tile.set_player("Red", "human")
	tile.set_done(2)
	check("PlayerTile.set_done: the place badge, the tile dimmed", tile.place == 2 and tile.done_place == 2 and is_equal_approx(tile.self_modulate.a, PlayerTile.DONE_ALPHA), [tile.place, tile.self_modulate.a])
	var badge_bright := true
	var dimmed := 0
	for ch in tile.get_children():
		if ch is PlayerTile.PlaceBadge:
			badge_bright = is_equal_approx((ch as CanvasItem).modulate.a, 1.0)
		elif ch is CanvasItem and is_equal_approx((ch as CanvasItem).modulate.a, PlayerTile.DONE_ALPHA):
			dimmed += 1
	check("…the badge stays bright, the rest is dimmed", badge_bright and dimmed > 0, dimmed)
	tile.set_done(0)
	check("set_done(0): back to full colour, no badge", tile.place == 0 and is_equal_approx(tile.self_modulate.a, 1.0))
	tile.free()
	var g := SL.new_game("local", 3)
	g.players[1].pos = 100; g.finished = [1]
	check("SLMatch.done_place: the finisher's place, 0 for the others", SLMatch.done_place(g, 1) == 1 and SLMatch.done_place(g, 0) == 0)
	g.erase("finished"); g.winner = 1
	check("SLMatch.done_place: an old state (winner, no finished)", SLMatch.done_place(g, 1) == 1)
	var st := SLMatch.SLTile.new(1, "Green", "human")
	st.set_width(100)
	st.set_done(3)
	check("SLTile.set_done: badge and dimming", st.done_place == 3 and st.find_child("Place", false, false) != null and is_equal_approx(st.self_modulate.a, PlayerTile.DONE_ALPHA))
	st.set_done(0)
	check("SLTile.set_done(0): cleared", st.done_place == 0 and is_equal_approx(st.self_modulate.a, 1.0))
	st.free()

func _card() -> void:
	var c := FinishCard.new()
	var said := []
	c.watch_pressed.connect(func(): said.append("watch"))
	c.home_pressed.connect(func(): said.append("home"))
	check("FinishCard: hidden until presented", not c.visible)
	c.present(1)
	check("FinishCard: You finished 1st! with Keep watching and Home", c.visible and c.title.text == "You finished 1st!" and c.home_button.visible and c.watch_button.text == "Keep watching", c.title.text)
	c.present(2, true, false)
	check("FinishCard: Teams title, Home can be left out", c.title.text == "Your team finished 2nd!" and not c.home_button.visible, c.title.text)
	c.home_button.pressed.emit()
	c.watch_button.pressed.emit()
	check("FinishCard: Keep watching closes it, both buttons signal", said == ["home", "watch"] and not c.visible, said)
	c.free()

func _copy_and_claim() -> void:
	var t := base()
	t[1] = [56, 56, 56, 56]; t[0] = [56, 56, 56, 56]; t[2][0] = 20
	var s := state(t, [], {players = ["human", "cpu", "cpu", "off"], names = ["You", "Mocha", "Biscotti", ""], phase = "over", winner = 1, finished = [1, 0, 2]})
	var copy: Dictionary = LudoMatch.result_copy(s)
	check("result copy: 2nd with all four home", copy.title == "You finished 2nd" and copy.sub == "Mocha won · you got all four home", copy)
	check("claim placing: your place from the standings", MAIN.claim_placing([{kind = "cpu", place = 1}, {kind = "you", place = 2}]) == 2)
	check("claim placing: none without you (Pass & Play)", MAIN.claim_placing([{kind = "human", place = 1}]) == 0 and MAIN.claim_placing(null) == 0)

# ---------- replicas ----------

func _replicas() -> void:
	var t := base()
	t[0] = [56, 56, 56, 56]; t[1][0] = 30; t[2][0] = 10
	var srv := state(t, [], {players = ["human", "human", "human", "off"], finished = [0], turn = 1})
	var ns := NetLudo.new()
	ns.begin({n = 5, seats = [{color = 0, id = 1, name = "Ana"}, {color = 1, id = 2, name = "Bo"}, {color = 2, id = 3, name = "Cy"}],
		state = JSON.parse_string(JSON.stringify(srv))}, "2")
	LudoRules.end_game(srv)
	var ev := ns.apply_rules({k = "end"})
	check("NetLudo: the end act ends the game like the server", ev.size() == 1 and ev[0].type == "game_over" and ns.S.phase == "over" and ns.S.finished == [0, 1, 2] and ns.n == 6, ev)
	check("…and the hashes agree", ns.verify({h = StateHash.of(srv)}))
	var g := SL.new_game("local", 3)
	g.mode = "online"
	g.players[0].pos = 100; g.finished = [0]; g.turn = 1
	var raw: Dictionary = JSON.parse_string(JSON.stringify(g))
	var sl := NetSL.new()
	sl.begin({n = 3, seats = [{color = 0, id = 1}, {color = 1, id = 2}, {color = 2, id = 3}], state = raw}, "3")
	check("NetSL.localize: finished back to ints", sl.S.finished == [0] and typeof(sl.S.finished[0]) == TYPE_INT, sl.S.finished)
	SL.end_game(g)
	ev = sl.apply_rules({k = "end"})
	check("NetSL: the end act (win event, the order)", ev.size() == 1 and ev[0].type == "win" and sl.S.phase == "over" and sl.verify({h = SLStateHash.of(g)}), ev)

# ---------- the fake server ----------

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

## Red finishes in a 3-person room; the others keep playing; when both of them leave, {k: "end"} ends it.
func _fake_room() -> void:
	var room := NetFake.Room.new("PQAYQN", 5)
	var cs := []
	for k in 3:
		var c := client(room, ["Ana", "Bo", "Cy"][k])
		c.join(room.code)
		pump(cs + [c])
		cs.append(c)
	cs[0].send_msg({t = "start"})
	pump(cs)
	room.S.tok[0] = NEAR.duplicate()
	room.dice = [1]
	room._roll()
	room._act({k = "move", c = 0, i = 3})
	pump(cs)
	check("fake room: Red's finish is no game over (play on)", room.playing and room.S.finished == [0] and got(cs[1], "over").is_empty(), room.S.finished)
	var left0 := room.n
	cs[1].leave()
	pump(cs)
	check("fake room: one of the two still playing leaves -> a bot, the game goes on", room.playing and room.S.players[1] == "cpu" and room.n == left0 + 1)
	cs[2].leave()
	pump(cs)
	var last: Dictionary = room.acts[-1]
	check("fake room: the last one leaves -> {k: end}, over to the finished player", not room.playing and last.a == {k = "end"} and got(cs[0], "over").size() == 1, last)
	var over: Dictionary = got(cs[0], "over")[0] if not got(cs[0], "over").is_empty() else {}
	check("…over: Red first, the full order", int(over.get("winner", -1)) == 0 and (over.get("finished", []) as Array).size() == 3, over)
	for c in cs:
		c.free()

## Red finishes and leaves, then the other two leave as well: the match still ends (Red keeps the win).
func _fake_room_all_leave() -> void:
	var room := NetFake.Room.new("QAYQN2", 6)
	var cs := []
	for k in 3:
		var c := client(room, ["Ana", "Bo", "Cy"][k])
		c.join(room.code)
		pump(cs + [c])
		cs.append(c)
	cs[0].send_msg({t = "start"})
	pump(cs)
	room.S.tok[0] = NEAR.duplicate()
	room.dice = [1]
	room._roll()
	room._act({k = "move", c = 0, i = 3})
	cs[0].leave()
	pump(cs)
	check("fake room: the finisher leaves -> no bot for a finished seat, play goes on", room.playing and room.S.players[0] == "human")
	cs[1].leave()
	pump(cs)
	check("…one more leaves: still one person playing", room.playing)
	cs[2].leave()
	pump(cs)
	check("…the last one leaves: {k: end}, Red the winner", not room.playing and room.acts[-1].a == {k = "end"} and int(room.S.winner) == 0, room.acts[-1])
	for c in cs:
		c.free()

## A quick room, one person + three ghosts: the person's finish is followed by {k: end} (no watching ghosts).
func _fake_quick() -> void:
	var hub := NetFake.Hub.new(3)
	var room := hub.add_room("QMABCD")
	var tokens := room.init_quick("ludo", [{account = "acc:me", pid = "pid-me-0000000000", name = "Me"}], 3)
	var c := NetClient.new()
	c.use_save = false
	c.prefs = {}
	c.url_base = "ws://fake"
	c.profile_fn = func() -> Dictionary: return {name = "Me", avatar = "pawn-blue", frame = "classic"}
	c.make_transport = hub.transport_factory()
	c.http_fn = hub.http
	var log := []
	c.set_meta("log", log)
	c.message.connect(func(m: Dictionary): log.append(m))
	c.join(room.code, str(tokens["acc:me"]), true)
	pump([c], 4)
	check("fake quick: the match starts with the person seated", room.playing and not room.is_ghost(0) and room.is_ghost(1))
	for k in 4:
		room.S.tok[k] = NEAR.duplicate()
	room.dice = [1]
	room._roll()
	room._act({k = "move", c = 0, i = 3})
	pump([c])
	var last: Dictionary = room.acts[-1]
	check("fake quick: your finish, then {k: end} (only ghosts unfinished)", not room.playing and last.a == {k = "end"} and room.S.phase == "over", last)
	check("…you win, the ghosts ranked by progress", int(room.S.winner) == 0 and room.S.finished.size() == 4 and LudoRules.standings(room.S)[1].finished == false)
	c.free()
