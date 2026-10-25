extends "res://tests/test_suite.gd"
## In-game emotes (server/EMOTES.md "In-game"): the picker (open / close by Escape, an outside tap, guard and
## close_open; a pick sends, closes and cools down 2 s; the panel's columns follow the band), the reaction layer
## (the queue of 2 per player, timing, reduce motion, delayed computer reactions), placement inside the screen and
## clear of the tiles, the dice and the button for every seat layout at 390 x 844 and 320 x 693 (3D and Top view),
## the button clear of the prompts, Snakes & Ladders (the button by the dice, reactions under the tiles), the
## computer throttles (9 s each, 4 s overall, never the same twice running) and the react rules, the sender (vs
## computer, Pass & Play, online), and online: the fake server relays {t: "emote"} with its pack and rate checks,
## NetClient's emote signal, Online's routing (quiet emote errors) and EmoteLayer.incoming. No save is written.

const SIZES := [Vector2(390, 844), Vector2(320, 693)]

func run() -> void:
	_picker()
	_layer()
	_cpu_rules()
	_ludo_layout()
	_sl_layout()
	_senders()
	_relay()
	_routing()


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e

func _click(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	e.global_position = at
	return e


# ---------- the picker ----------

func _picker() -> void:
	var host := Control.new()
	host.size = Vector2(390, 844)
	_tree().root.add_child(host)
	var p := EmotePicker.new()
	host.add_child(p)
	p.size = host.size
	p.still = 0
	check("picker: six emotes of the equipped pack, each with its art", p.ids.size() == 6 and p.cells.size() == 6
		and p.ids.all(func(id): return EmoteArt.icon(id) != null), p.ids)
	check("picker: the pack's ids come from Emotes (Starter by default)", p.ids == EmotePicker.equipped(), p.ids)
	p.place_button(Vector2(53, 660), false)
	p.open()
	check("picker: no panel while the button is hidden", not p.is_open and not p.panel.visible)
	p.place_button(Vector2(53, 660))
	check("picker: the button is the 44 px hit area centred where asked", p.button.visible and p.button_rect() == Rect2(31, 638, 44, 44), p.button_rect())
	p.place_panel(180, 610)
	p.button.pressed.emit()
	check("picker: the button opens the panel", p.is_open and p.panel.visible)
	p.tick(0.02)
	check("picker: it pops out from the left (sliding, small, fading in)", p.panel.position.x < EmotePicker.LEFT and p.panel.scale.x < 1.0 and p.panel.modulate.a < 1.0)
	check("picker: the stickers come a moment after each other", (p.cells[0] as EmotePicker.Cell).k >= (p.cells[5] as EmotePicker.Cell).k and (p.cells[5] as EmotePicker.Cell).k == 0.0)
	p.tick(1.0)
	check("picker: then rests at the left edge, every sticker in place", p.panel.position.x == EmotePicker.LEFT and is_equal_approx(p.panel.scale.x, 1.0)
		and p.cells.all(func(c): return is_equal_approx((c as EmotePicker.Cell).k, 1.0)))
	check("picker: one column in a tall band, centred in it", p.cols == 1 and p.panel_rect().position.y >= 176 and p.panel_rect().end.y <= 610, [p.cols, p.panel_rect()])
	p._input(_click(p.panel_rect().get_center()))
	check("picker: a tap inside the panel keeps it open", p.is_open)
	p._input(_key(KEY_ESCAPE))
	check("picker: Escape closes it", not p.is_open)
	p.tick(0.5)
	check("picker: closing fades it out, then it's gone", not p.panel.visible)
	p.open()
	p._input(_click(Vector2(300, 300)))
	check("picker: a tap outside closes it (and is used up)", not p.is_open and Time.get_ticks_msec() < p._swallow_until)
	p._swallow_until = 0
	p.tick(1.0)
	var sent := []
	p.picked.connect(func(id: String): sent.append(id))
	p.open()
	p.tick(1.0)
	(p.cells[1] as Button).pressed.emit()
	check("picker: a pick sends that emote and closes", sent == ["laugh"] or sent == [p.ids[1]] and not p.is_open, sent)
	check("picker: then cools down for 2 s", p.cooling() and is_equal_approx(p.cool_left, EmotePicker.COOL))
	p.open()
	p.tick(0.4)
	check("picker: cooling, the stickers are greyed and a tap does nothing", (p.cells[0] as EmotePicker.Cell)._grey > 0.9 and not p.pick(p.ids[0]) and sent.size() == 1 and p.is_open)
	p.tick(1.7)
	check("picker: after 2 s it works again", not p.cooling() and p.pick(p.ids[2]) and sent.size() == 2)
	p.tick(2.5)
	check("picker: an emote outside the pack is refused", not p.pick("not_an_emote"))
	p.open()
	check("picker: Back (main's close_open) closes it and says so", EmotePicker.close_open() and not p.is_open and not EmotePicker.close_open())
	var blocked := [false]
	p.guard = func() -> bool: return blocked[0]
	p.open()
	blocked[0] = true
	p.tick(0.0)
	check("picker: a sheet opening (guard) closes it", not p.is_open)
	blocked[0] = false
	p.place_panel(180, 380)
	check("picker: two columns in a short band", p.cols == 2 and p.panel.size.y <= 200, [p.cols, p.panel.size])
	p.place_panel(180, 290)
	check("picker: six in a row when even three columns can't fit", p.cols == 6, p.cols)
	p.still = 1
	p.place_panel(180, 610)
	p.open()
	check("picker: reduce motion: in place at once", p.panel.position.x == EmotePicker.LEFT and p.panel.scale == Vector2.ONE and p.panel.modulate.a == 1.0)
	p.close()
	check("picker: reduce motion: gone at once", not p.panel.visible)
	host.queue_free()
	_tree().root.remove_child(host)


# ---------- the reaction layer ----------

func _layer() -> void:
	var l := EmoteLayer.new()
	l.mute = true
	l.still = 0
	l.size = Vector2(390, 844)
	l.seat_fn = func(c: int) -> Dictionary:
		if c == 3:
			return {}
		return {card = Rect2(16 + c * 100, 700, 144, 116), slot = Rect2(90 + c * 100, 705, 64, 64), inner = "right", low = true}
	_tree().root.add_child(l)
	check("layer: 116 px wide on a normal phone, 96 on a 320 px one", l.bubble_width() == 116.0 and _width_at(Vector2(320, 693)) == 96.0)
	check("layer: an unknown emote or a seat that isn't there shows nothing", not l.show_emote(0, "nope") and not l.show_emote(3, "happy") and l.showing.is_empty())
	var seen := []
	l.shown.connect(func(c: int, id: String): seen.append([c, id]))
	check("layer: a reaction shows", l.show_emote(0, "happy") and l.showing.has(0) and seen == [[0, "happy"]])
	check("layer: the next two wait, a third is dropped", l.show_emote(0, "laugh") and l.show_emote(0, "cool") and not l.show_emote(0, "love")
		and (l.queue[0] as Array) == ["laugh", "cool"], l.queue)
	check("layer: another player's shows at the same time", l.show_emote(1, "angry") and l.showing.size() == 2)
	var b: EmoteLayer.Bubble = l.showing[0]
	l.tick(0.05)
	check("layer: it pops in (small, rising, fading in)", b.scale.x < 1.0 and b.modulate.a < 1.0)
	l.tick(0.6)
	check("layer: then holds, full size, while its frames play", is_equal_approx(b.scale.x, 1.0) and b.modulate.a == 1.0 and b.frame > 0)
	l.tick(1.6)
	check("layer: near the end it shrinks away", b.scale.x < 1.0 and b.modulate.a < 1.0)
	l.tick(0.2)
	check("layer: after 2.4 s the next in the queue follows", l.showing.has(0) and (l.showing[0] as EmoteLayer.Bubble).id == "laugh" and (l.queue[0] as Array) == ["cool"])
	l.tick(2.5)
	l.tick(2.5)
	check("layer: and the queue drains", not l.showing.has(0) and (l.queue.get(0, []) as Array).is_empty())
	l.show_later(1, "party", 0.5)
	l.tick(0.3)
	check("layer: a delayed reaction waits", not l.showing.has(1))
	l.tick(0.3)
	check("layer: then shows", l.showing.has(1) and (l.showing[1] as EmoteLayer.Bubble).id == "party")
	l.clear()
	check("layer: clear() takes everything away", l.showing.is_empty() and l.queue.is_empty() and l._later.is_empty())
	l.still = 1
	l.show_emote(0, "love")
	var sb: EmoteLayer.Bubble = l.showing[0]
	l.tick(0.1)
	var fade_in := sb.modulate.a
	l.tick(1.0)
	check("layer: reduce motion: a fade only (no pop, no frames)", sb.scale == Vector2.ONE and fade_in > 0.0 and fade_in < 1.0 and sb.modulate.a == 1.0 and sb.frame == 0)
	l.queue_free()
	_tree().root.remove_child(l)

func _width_at(s: Vector2) -> float:
	var l := EmoteLayer.new()
	l.size = s
	var w := l.bubble_width()
	l.free()
	return w


# ---------- computer reactions ----------

func _cpu_rules() -> void:
	var l := EmoteLayer.new()
	l.mute = true
	l.always = true
	l.size = Vector2(390, 844)
	l.rng.seed = 5
	var now := [100000]
	l.now_fn = func() -> int: return now[0]
	l.is_cpu_fn = func(c: int) -> bool: return c > 0
	l.is_human_fn = func(c: int) -> bool: return c == 0
	l.seat_fn = func(c: int) -> Dictionary: return {card = Rect2(16, 100 + c * 150, 144, 116), slot = Rect2(90, 105 + c * 150, 64, 64), inner = "right", low = false}
	_tree().root.add_child(l)
	check("cpu: a person never 'reacts' by itself", not l.cpu_say(0, ["happy"], 1.0))
	check("cpu: a computer reacts", l.cpu_say(1, ["happy", "laugh"], 1.0))
	check("cpu: not on the same frame (a short delay)", l.showing.is_empty())
	l.tick(EmoteLayer.CPU_DELAY[1] + 0.05)
	check("cpu: then it shows on its seat", l.showing.has(1))
	check("cpu: another computer waits 4 s after any reaction", not l.cpu_say(2, ["happy"], 1.0))
	now[0] += EmoteLayer.ANY_GAP + 1
	check("cpu: after 4 s another may", l.cpu_say(2, ["happy"], 1.0))
	now[0] += EmoteLayer.ANY_GAP + 1
	check("cpu: the same one waits 9 s", not l.cpu_say(1, ["happy"], 1.0))
	now[0] += EmoteLayer.CPU_GAP
	check("cpu: after 9 s it may again", l.cpu_say(1, ["happy", "laugh"], 1.0))
	var ids := []
	for k in 6:
		now[0] += EmoteLayer.CPU_GAP + 1
		l.cpu_say(3, ["laugh", "cool", "tease"], 1.0)
		ids.append(l._last_cpu[3])
	var repeats := 0
	for k in range(1, ids.size()):
		if ids[k] == ids[k - 1]:
			repeats += 1
	check("cpu: never the same emote twice running", repeats == 0, ids)
	l.always = false
	now[0] += EmoteLayer.CPU_GAP + 1
	check("cpu: chance 0 never reacts", not l.cpu_say(1, ["happy"], 0.0))
	l.always = true
	l.clear()
	now[0] += EmoteLayer.CPU_GAP + 1
	check("react: a computer captured by you sulks", l.react_capture(0, [1]) and ["cry", "angry", "wow", "facepalm", "sad"].has(l._last_cpu[1]))
	now[0] += EmoteLayer.CPU_GAP + 1
	check("react: a computer capturing you gloats", l.react_capture(2, [0]) and ["laugh", "cool", "tease"].has(l._last_cpu[2]))
	now[0] += EmoteLayer.CPU_GAP + 1
	check("react: computers capturing each other say nothing", not l.react_capture(1, [3]))
	now[0] += EmoteLayer.CPU_GAP + 1
	check("react: a winning computer celebrates", l.react_win([3], [0, 1, 2, 3]) and ["party", "crown", "happy"].has(l._last_cpu[3]))
	now[0] += EmoteLayer.CPU_GAP + 1
	check("react: you win: a computer congratulates (or sulks)", l.react_win([0], [0, 1, 2, 3]) and ["cheer", "sad", "cry"].has(l._last_cpu[1]))
	now[0] += EmoteLayer.CPU_GAP + 1
	check("react: a computer finishing (play on) is pleased", l.react_finish(2) and ["party", "happy", "champ"].has(l._last_cpu[2]))
	now[0] += EmoteLayer.CPU_GAP + 1
	check("react: S&L snake and ladder", l.react_snake(1) and l._last_cpu[1] in ["cry", "sad", "facepalm", "angry"])
	l.queue_free()
	_tree().root.remove_child(l)


# ---------- Ludo: placement for every seat layout ----------

func _ludo_layout() -> void:
	var host := Control.new()
	_tree().root.add_child(host)
	var bad := []
	var cam0: String = Save.prefs.get("cam", "3d") if _save() else "3d"
	for sz: Vector2 in SIZES:
		for cam in ["3d", "top"]:
			if _save():
				Save.prefs.cam = cam                  # (the HUD's placement doesn't depend on the camera: checked)
			for layout in [["human", "cpu", "cpu", "cpu"], ["human", "off", "cpu", "off"], ["human", "cpu", "off", "cpu"], ["human", "human", "human", "human"]]:
				for view in 4:
					var hud := LudoHUD.new()
					hud.size = sz
					host.add_child(hud)
					hud.size = sz
					hud.emotes.mute = true
					var s := LudoRules.new_game(layout)
					s.view = view
					hud.setup(s)
					hud.set_emotes(true)
					var tag := "%dx%d %s %s view %d" % [sz.x, sz.y, cam, layout, view]
					_check_ludo(hud, s, sz, tag, bad)
					host.remove_child(hud)
					hud.free()
	if _save():
		Save.prefs.cam = cam0
	check("ludo layout: reactions inside the screen, on their own half, clear of every tile and the button; the button above your avatar clear of every tile and dice slot; the panel between the tile rows (every seat, 390x844 and 320x693, 3D and Top view)", bad.is_empty(), bad.slice(0, 6))
	# the prompts over the tile row
	var hud2 := LudoHUD.new()
	host.add_child(hud2)
	hud2.size = Vector2(320, 693)
	hud2.emotes.mute = true
	var s2 := LudoRules.new_game(["human", "cpu", "cpu", "cpu"])
	hud2.setup(s2)
	hud2.set_emotes(true)
	var free_at := hud2.emote_picker.button_rect()
	hud2.pair_box.visible = true
	hud2._place_pair_box()
	hud2._place_emotes()
	var pr := Rect2(hud2.pair_box.position, hud2.pair_box.size)
	check("ludo prompts: the button moves up clear of the pair prompt", not hud2.emote_picker.button_rect().intersects(pr) and hud2.emote_picker.button_rect().position.y < free_at.position.y,
		[hud2.emote_picker.button_rect(), pr])
	hud2.pair_box.visible = false
	hud2.show_finish(1, false, true)
	var fr := Rect2(hud2.finish_card.position, hud2.finish_card.size)
	hud2.emotes.show_emote(0, "party")
	check("ludo prompts: the button and your reaction stay clear of the finish card", not hud2.emote_picker.button_rect().intersects(fr) and not hud2.emotes.spot(0).intersects(fr),
		[hud2.emote_picker.button_rect(), hud2.emotes.spot(0), fr])
	hud2.hide_finish()
	check("ludo prompts: back over your avatar when it's gone", hud2.emote_picker.button_rect() == free_at)
	hud2.tutorial = true
	check("ludo: no button during the tutorial", not hud2.emote_picker.button.visible)
	hud2.tutorial = false
	hud2.hide_for_result()
	check("ludo: no button after the game", not hud2.emote_picker.button.visible)
	host.queue_free()
	_tree().root.remove_child(host)

func _save() -> bool:
	return _tree().root.get_node_or_null("Save") != null

func _check_ludo(hud: LudoHUD, s: Dictionary, sz: Vector2, tag: String, bad: Array) -> void:
	var screen := Rect2(Vector2.ZERO, sz).grow(-4)
	var btn := hud.emote_picker.button_rect()
	var cards := {}
	for c in 4:
		var st := hud.emote_seat(c)
		if not st.is_empty():
			cards[c] = st
	if btn.size.x <= 0.0 or not screen.encloses(btn):
		bad.append([tag, "button", btn])
	for c in cards:
		var st: Dictionary = cards[c]
		if btn.intersects(st.card) or btn.intersects(st.slot):
			bad.append([tag, "button over tile", c])
	var mine: Dictionary = cards.get(hud._emote_tile(), {})
	if not mine.is_empty() and btn.end.y > (mine.card as Rect2).position.y:
		bad.append([tag, "button not above your tile"])
	for c in cards:
		var r := hud.emotes.spot(c)
		if r.size.x < 70.0 or not Rect2(Vector2.ZERO, sz).grow(-EmoteLayer.EDGE + 0.5).encloses(r):
			bad.append([tag, "bubble outside", c, r])
		var st: Dictionary = cards[c]
		var half_ok: bool = (r.end.x <= sz.x / 2.0 + 0.5) if st.inner == "right" else (r.position.x >= sz.x / 2.0 - 0.5)
		if not half_ok:
			bad.append([tag, "bubble off its half", c, r])
		if r.intersects(btn):
			bad.append([tag, "bubble over the button", c])
		for k in cards:
			if r.intersects(cards[k].card):
				bad.append([tag, "bubble over a tile", c, k])
	hud.emote_picker.still = 1
	hud.emote_picker.open()
	var pr := hud.emote_picker.panel_rect()
	for c in cards:
		if pr.intersects(cards[c].card):
			bad.append([tag, "panel over a tile", c, pr])
	if pr.intersects(btn) or not screen.encloses(pr):
		bad.append([tag, "panel", pr])
	hud.emote_picker.close()


# ---------- Snakes & Ladders ----------

func _sl_layout() -> void:
	var app := _fake_app()
	_tree().root.add_child(app)
	for sz: Vector2 in SIZES:
		for n in [2, 3, 4]:
			var parent := Control.new()
			parent.size = sz
			app.add_child(parent)
			var m := SLMatch.new(app, null, null)
			app.add_child(m)
			m.build_hud(parent)
			m.hud.size = sz
			m.emotes.mute = true
			m.G = SnakesLaddersRules.new_game("cpu", n, 0)
			m._build_tiles()
			m._refresh_tiles()
			m._emote_sync()
			m._layout()
			var tag := "%dx%d n=%d" % [sz.x, sz.y, n]
			var btn := m.emote_picker.button_rect()
			var dice := Rect2(m.dice_pad.position, m.dice_pad.size)
			var ok := btn.size.x > 0.0 and Rect2(Vector2.ZERO, sz).grow(-4).encloses(btn) and not btn.intersects(dice)
			check("sl %s: the button by the dice (inside the screen, clear of the dice)" % tag, ok, [btn, dice])
			var rows := []
			var inside := true
			for p in m.G.players:
				var st := m.emote_seat(int(p.c))
				var r := m.emotes.spot(int(p.c))
				rows.append(r)
				inside = inside and Rect2(Vector2.ZERO, sz).grow(-EmoteLayer.EDGE + 0.5).encloses(r) and r.position.y >= (st.card as Rect2).end.y and not r.intersects(dice) and not r.intersects(btn)
			check("sl %s: every reaction just under its tile, inside the screen" % tag, inside, rows)
			m.emote_picker.still = 1
			m.emote_picker.open()
			var pr := m.emote_picker.panel_rect()
			check("sl %s: the panel between the tiles and the button" % tag, pr.position.y >= m.chips.position.y + SLMatch.SLTile.H and pr.end.y <= btn.position.y and not pr.intersects(dice), [pr, btn])
			m.emote_picker.close()
			m.emotes.is_cpu_fn = m.emotes.is_cpu_fn   # (wired by build_hud)
			check("sl %s: computers react, you don't" % tag, m.emotes._is_cpu(int(m.G.players[1].c)) and not m.emotes._is_cpu(int(m.G.players[0].c)))
			m.G.phase = "over"
			m._emote_sync()
			check("sl %s: no button after the game" % tag, not m.emote_picker.button.visible)
			m.free()
			parent.free()
	app.queue_free()
	_tree().root.remove_child(app)

func _fake_app() -> Node:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar safe_top := 0.0\nvar safe_bottom := 0.0\nvar paused := false\nvar speed := 1.0\nvar ludo: Variant = null\nvar sl: Variant = null\nvar screen := \"ludo\"\n"
	s.reload()
	var n: Node = s.new()
	return n


# ---------- who sends ----------

func _senders() -> void:
	var s := LudoRules.new_game(["human", "cpu", "cpu", "cpu"])
	s.turn = 2
	check("sender: vs the computer it's you, whoever's turn", LudoMatch.emote_sender_of(s) == 0)
	var pp := LudoRules.new_game(["human", "human", "off", "human"])
	pp.turn = 3
	check("sender: Pass & Play, the player to move", LudoMatch.emote_sender_of(pp) == 3)
	check("sender: online, your seat (watching: nobody)", LudoMatch.emote_sender_of(pp, 1) == 1 and LudoMatch.emote_sender_of(pp, -1) == -1 and LudoMatch.emote_sender_of(pp, 2) == -1)
	var mixed := LudoRules.new_game(["human", "cpu", "human", "cpu"])
	mixed.turn = 1
	check("sender: Pass & Play with computers: on a computer's turn the first person", LudoMatch.emote_sender_of(mixed) == 0)
	pp.phase = "over"
	check("sender: nobody after the game", LudoMatch.emote_sender_of(pp) == -1 and LudoMatch.emote_sender_of({}) == -1)
	var g := SnakesLaddersRules.new_game("cpu", 3, 0)
	g.turn = 2
	check("sl sender: vs the computer, you", SLMatch.emote_sender_of(g) == int(g.players[0].c))
	var lg := SnakesLaddersRules.new_game("local", 3, 0)
	lg.turn = 1
	check("sl sender: Pass & Play, the player to move", SLMatch.emote_sender_of(lg) == int(lg.players[1].c))
	check("sl sender: online, your colour if seated", SLMatch.emote_sender_of(lg, int(lg.players[2].c)) == int(lg.players[2].c) and SLMatch.emote_sender_of(lg, -1) == -1)


# ---------- online: the fake server relays emotes ----------

func _client(room: NetFake.Room, name: String) -> NetClient:
	var c := NetClient.new()
	c.use_save = false
	c.prefs = {}
	c.url_base = "ws://fake"
	var sess := "s-" + name
	c.session_fn = func() -> String: return sess
	c.profile_fn = func() -> Dictionary: return {name = name, avatar = "pawn-blue", frame = "classic"}
	c.make_transport = room.transport_factory()
	c.http_fn = room.http
	var log := []
	c.set_meta("log", log)
	c.message.connect(func(m: Dictionary): log.append(m))
	var em := []
	c.set_meta("emotes", em)
	c.emote.connect(func(m: Dictionary): em.append(m))
	return c

func _pump(cs: Array, times := 3) -> void:
	for k in times:
		for c in cs:
			c._process(0.0)

func _got(c: NetClient, t: String) -> Array:
	return (c.get_meta("log") as Array).filter(func(m): return m.get("t") == t)

func _relay() -> void:
	var room := NetFake.Room.new("EMKT22", 3)
	var now := [500000]
	room.clock = func() -> int: return now[0]
	var a := _client(room, "Ana")
	var b := _client(room, "Bo")
	var c := _client(room, "Cy")
	var cs := [a, b, c]
	for x in cs:
		x.join(room.code)
		_pump(cs)
	_pump(cs, 4)
	a.send_emote("happy")
	_pump(cs)
	var lb: Array = b.get_meta("emotes")
	check("relay lobby: c = -1 and the member", lb.size() == 1 and int(lb[0].c) == -1 and NetClient.id_str(lb[0].get("member", "")) == a.member_id, lb)
	a.send_msg({t = "start"})
	_pump(cs, 4)
	var col_a := room._color(int(a.member_id))
	now[0] += 2100
	a.send_emote("laugh")
	_pump(cs)
	var eb: Array = (b.get_meta("emotes") as Array).slice(1)
	var ec: Array = (c.get_meta("emotes") as Array).slice(1)
	check("relay: in a match the others get {t: emote, c: the sender's colour, id}", eb.size() == 1 and ec.size() == 1 and int(eb[0].c) == col_a and eb[0].id == "laugh" and col_a >= 0, [eb, col_a])
	check("relay: never back to the sender (it shows its own at once)", (a.get_meta("emotes") as Array).is_empty())
	now[0] += 500
	a.send_emote("cool")
	_pump(cs)
	check("relay: a second within 2 s is refused (emote_rate)", _got(a, "error").any(func(m): return m.code == "emote_rate") and (b.get_meta("emotes") as Array).size() == 2)
	now[0] += 2100
	a.send_emote("champ")
	_pump(cs)
	check("relay: a pack the account doesn't own is refused (emote_locked)", _got(a, "error").any(func(m): return m.code == "emote_locked") and (b.get_meta("emotes") as Array).size() == 2)
	for mem in room.members:
		if str(mem.id) == a.member_id:
			mem.emote_sets = ["starter", "pawns"]
	now[0] += 2100
	a.send_emote("champ")
	_pump(cs)
	check("relay: owned, it goes through", (b.get_meta("emotes") as Array).back().id == "champ")
	var before := _got(a, "error").filter(func(m): return m.code == "emote_rate").size()
	var refused := 0
	for k in 6:
		now[0] += 2100
		a.send_emote("love")
		_pump(cs)
	refused = _got(a, "error").filter(func(m): return m.code == "emote_rate").size() - before
	check("relay: at most 6 in 30 s (3 sent before these 6: the last 3 are refused)", refused == 3, refused)
	room.ghost_emote(2, "party")
	_pump(cs)
	check("relay: a ghost's (any seat's) emote reaches everyone like a person's", (a.get_meta("emotes") as Array).back() == {t = "emote", c = 2, id = "party"})
	b.send_emote("nope")
	_pump(cs)
	check("relay: an unknown emote is a bad message", _got(b, "error").any(func(m): return m.code == "bad_message"))
	for x in cs:
		x.free()


# ---------- online: routing ----------

func _routing() -> void:
	var ms := GDScript.new()
	ms.source_code = "extends Node\nvar online := true\nvar got := []\nvar errs := []\nfunc net_emote(m): got.append(m)\nfunc net_error(m): errs.append(m)\n"
	ms.reload()
	var match_: Node = ms.new()
	var app := _fake_app()
	app.ludo = match_
	var net := NetClient.new()
	net.use_save = false
	net.prefs = {}
	var on := Online.new(app, net)
	on.state = "match"
	on._on_emote({t = "emote", c = 1, id = "happy"})
	check("routing: another seat's emote reaches the match on screen", match_.got.size() == 1 and int(match_.got[0].c) == 1)
	on._on_emote({t = "emote", c = -1, id = "happy", member = 4})
	check("routing: lobby emotes (c = -1) are not shown in a match", match_.got.size() == 1)
	on._holding = true
	on._on_emote({t = "emote", c = 2, id = "happy"})
	check("routing: while the match opens they are dropped (not replayed late)", match_.got.size() == 1 and on._held.is_empty())
	on._holding = false
	on._on_error({t = "error", code = "emote_rate"})
	on._on_error({t = "error", code = "emote_locked"})
	check("routing: emote_rate / emote_locked are ignored quietly (no toast, not a refused move)", match_.errs.is_empty() and on.state == "match")
	var sig := []
	net.emote.connect(func(m: Dictionary): sig.append(m))
	net.handle({t = "emote", c = 3, id = "cool"})
	check("net client: {t: emote} is its own signal", sig.size() == 1 and sig[0].id == "cool")
	check("incoming: a seat's emote is shown", EmoteLayer.incoming({c = 2, id = "love"}, 0, func(_c): return true) == [2, "love"])
	check("incoming: never your own, the lobby's or an empty seat's", EmoteLayer.incoming({c = 0, id = "love"}, 0, Callable()).is_empty()
		and EmoteLayer.incoming({c = -1, id = "love"}, 0, Callable()).is_empty()
		and EmoteLayer.incoming({c = 3, id = "love"}, 0, func(c): return c != 3).is_empty())
	check("incoming: an unknown emote is left out", EmoteLayer.incoming({c = 2, id = "zzz"}, 0, Callable()).is_empty())
	net.free()
	on.free()
	match_.free()
	app.free()
