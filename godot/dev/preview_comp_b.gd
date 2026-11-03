extends Node
## Dev preview of the phase 1 C-B components over the real 3D café: GameTopBar states, PlayerTile states (a full
## game HUD mock), SideButtons on the lobby, CoinFly frames and the ResultScreen (win / lose / teams / S&L).
## Never writes the save (prefs are changed in memory only and restored).
##   godot --path . --resolution 390x844 res://dev/preview_comp_b.tscn -- <out_dir> [page ...]
## pages: game bars tiles side coin result_win result_lose result_team result_sl (default: all)

var out := "/tmp"
var world: TableWorld
var ui: Control
var layer: CanvasLayer
var S := {}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	var pages: Array = Array(args.slice(1)) if args.size() > 1 else ["game", "bars", "tiles", "side", "coin", "result_win", "result_lose", "result_team", "result_sl"]
	var baker := TexBaker.new()
	add_child(baker)
	world = TableWorld.new()
	add_child(world)
	await world.build_room(baker, func(_f): pass, str(Save.profile.room))
	world.reduced_motion = true
	layer = CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.theme = UIKit.theme()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	S = LudoRules.new_game(["human", "cpu", "cpu", "cpu"])
	S.tok = [[-1, 5, 12, 57], [3, -1, -1, 20], [57, 57, 30, 44], [-1, -1, 8, -1]]
	world.board.relayout(S)
	world.top_band = 844.0 - 2 * (68.0 + 118.0) + 40.0
	world.view_game(0, false)
	await _settle(1.6)
	for p in pages:
		_clear()
		match str(p):
			"avatars": await _page_avatars()
			"game": await _page_game()
			"bars": await _page_bars()
			"tiles": await _page_tiles()
			"side": await _page_side()
			"coin": await _page_coin()
			"result_win": await _page_result("win")
			"result_lose": await _page_result("lose")
			"result_team": await _page_result("team")
			"result_sl": await _page_result("sl")
	get_tree().quit()

func _clear() -> void:
	for c in ui.get_children():
		c.queue_free()

func _settle(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _tiles(turn: int, teams := false) -> Array:
	var corner := ["bl", "tl", "tr", "br"]
	var names := ["You", "Mocha", "Biscotti", "Espresso"]
	var kinds := ["you", "cpu", "cpu", "cpu"]
	var out_ := []
	var w := 390.0
	var h := 844.0
	for c in 4:
		var side := "left" if corner[c] in ["bl", "tl"] else "right"
		var t := PlayerTile.new(c, side)
		ui.add_child(t)
		t.set_player(names[c], kinds[c], names[c].to_lower() if kinds[c] == "cpu" else "")
		var home := 0
		for p in S.tok[c]:
			if p >= LudoRules.GOAL:
				home += 1
		var chip := ""
		if teams:
			chip = "Team " + LudoRules.team_label(S, c)
		t.set_state(c == turn, false, home, LudoRules.progress(S, c), chip)
		var top: bool = corner[c] in ["tl", "tr"]
		var x := 16.0 if side == "left" else w - 16.0 - PlayerTile.CARD_W
		var y := 68.0 + 4.0 if top else h - 16.0 - t.tile_height()
		t.position = Vector2(x, y)
		out_.append(t)
	return out_

func _page_avatars() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.CARD
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var ids := ["mocha", "biscotti", "espresso"]
	for i in 3:
		for c in 4:
			var a := PlayerTile.make_avatar(c, "cpu", 84, ids[i])
			a.position = Vector2(12 + c * 94, 20 + i * 100)
			ui.add_child(a)
	for c in 4:
		var h := PlayerTile.make_avatar(c, "human", 84)
		h.position = Vector2(12 + c * 94, 320)
		ui.add_child(h)
	var big := PlayerTile.make_avatar(1, "cpu", 180, "mocha")
	big.position = Vector2(10, 430)
	ui.add_child(big)
	var big2 := PlayerTile.make_avatar(2, "cpu", 180, "biscotti")
	big2.position = Vector2(200, 430)
	ui.add_child(big2)
	var big3 := PlayerTile.make_avatar(3, "cpu", 180, "espresso")
	big3.position = Vector2(10, 630)
	ui.add_child(big3)
	var me := PlayerTile.make_avatar(0, "you", 180)
	me.position = Vector2(200, 630)
	ui.add_child(me)
	await _settle(0.4)
	await _shot("avatars")

func _page_game() -> void:
	var bar := GameTopBar.new()
	ui.add_child(bar)
	bar.set_turn(0)
	bar.set_idle("Your turn — tap the dice")
	var tiles := _tiles(0)
	var dice := Dice3D.new()
	dice.custom_minimum_size = Vector2(64, 64)
	dice.size = Vector2(64, 64)
	ui.add_child(dice)
	await _settle(0.6)
	var r: Rect2 = tiles[0].dice_slot_rect()
	dice.position = r.position + (r.size - dice.size) / 2.0
	dice.set_active(true)
	await _settle(0.8)
	await _shot("game_idle")
	bar.set_turn(1)
	for c in 4:
		tiles[c].set_state(c == 1, false, 0 if c != 2 else 2, LudoRules.progress(S, c), "")
	r = tiles[1].dice_slot_rect()
	dice.position = r.position + (r.size - dice.size) / 2.0
	dice.set_active(false)
	bar.say("[b]Mocha[/b] captured your pawn! +1 roll", 1.6, "event")
	await _settle(0.12)
	await _shot("game_event_pop")
	await _settle(0.6)
	await _shot("game_event")
	bar.set_idle("[b]Mocha[/b] is thinking…")
	await _settle(1.6)
	await _shot("game_after_event_idle")

func _page_bars() -> void:
	var specs := [
		["pause", 0, "idle", "Your turn — tap the dice", false],
		["pause", 1, "event", "[b]Mocha[/b] rolled a 6. Roll again!", false],
		["pause", 2, "info", "[b]Biscotti[/b] is thinking…", false],
		["pause", 0, "info", "Teams: Red + Yellow vs Green + Blue", true],
		["pause", 3, "event", "[b]Espresso[/b] captured %s's pawn and rolls again!" % GameTopBar.who("Mocha", 1), false],
		["back", -1, "idle", "Snakes & Ladders", false],
		["pause", 0, "info", "You rolled three 6s in a row. Turn lost.", true],
	]
	var y := 0.0
	var bars := []
	for sp in specs:
		var bar := GameTopBar.new(sp[0])
		bar.safe_top = y
		ui.add_child(bar)
		bar.set_turn(int(sp[1]))
		if sp[4]:
			bar.info_slot.add_child(Info.icon("team", false, 22))
		if sp[2] == "idle":
			bar.set_idle(sp[3])
		else:
			bar.say(sp[3], 5.0, sp[2])
		bars.append(bar)
		y += 84.0
	await _settle(0.12)
	await _shot("bars_pop")
	await _settle(1.0)
	await _shot("bars")
	# readability rule: an info message during a fresh event waits for it
	var b: GameTopBar = bars[1]
	b.set_idle("Your turn — tap the dice")
	b.say("[b]Biscotti[/b] rolled 2.", 1.0, "info")
	print("[preview] queued while event fresh: ", b.current())

func _page_tiles() -> void:
	var prefs: Dictionary = Save.prefs
	var cb_was := bool(prefs.get("colorblind", false))
	var bg := ColorRect.new()
	bg.color = Color(Palette.SHADOW_DEEP, 0.25)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var rows := [
		[0, "left", "You", "you", "", true, false, 1, 0.43, ""],
		[1, "right", "Mocha", "cpu", "mocha", false, false, 0, 0.12, ""],
		[2, "left", "Biscotti", "cpu", "biscotti", false, false, 3, 0.86, "Team Red + Yellow"],
		[3, "right", "Espresso", "cpu", "espresso", true, false, 0, 0.0, "Team Green + Blue"],
		[0, "left", "Red", "human", "", false, true, 4, 1.0, "Help your teammate"],
		[2, "right", "Yellow", "human", "", true, false, 2, 0.61, ""],
	]
	var y := 24.0
	for i in rows.size():
		var r: Array = rows[i]
		if i == 4:
			prefs.colorblind = true
		var t := PlayerTile.new(r[0], r[1])
		ui.add_child(t)
		t.set_player(r[2], r[3], r[4])
		t.set_state(r[5], r[6], r[7], r[8], r[9])
		var x := 24.0 if i % 2 == 0 else 390.0 - 24.0 - PlayerTile.CARD_W
		t.position = Vector2(x, y + (0 if i % 2 == 0 else 0))
		if i % 2 == 1:
			y += 180.0
	var p := PlayerTile.new(1, "left")
	ui.add_child(p)
	p.set_player("Mocha", "cpu", "mocha")
	p.set_state(false, false, -1, 0.47, "")
	p.set_note("Square 47")
	p.set_place(1)
	p.position = Vector2(24, y)
	var q := PlayerTile.new(3, "right")
	ui.add_child(q)
	q.set_player("You", "you")
	q.set_state(false, false, 2, 0.55, "")
	q.set_place(2)
	q.position = Vector2(390 - 24 - PlayerTile.CARD_W, y)
	await _settle(0.9)
	await _shot("tiles")
	prefs.colorblind = cb_was

func _page_side() -> void:
	world.view_home()
	await _settle(1.4)
	var specs := [
		["spin", "Spin", "side_spin", Palette.LOBBY.spin, "!", ""],
		["daily", "Rewards", "side_gift", Palette.LOBBY.gift, "1", ""],
		["free", "Free", "side_coins", Palette.LOBBY.coins, "", "3:53:10"],
		["spin2", "Spin", "side_spin", Palette.LOBBY.spin, "", "13h 20m"],
	]
	var pos := [Vector2(4, 90), Vector2(4, 196), Vector2(390 - 4 - SideButton.WIDTH, 90), Vector2(390 - 4 - SideButton.WIDTH, 196)]
	var btns := []
	for i in specs.size():
		var sp: Array = specs[i]
		var b := SideButton.new(sp[0], sp[1], sp[2], sp[3])
		ui.add_child(b)
		b.set_badge(sp[4])
		b.set_countdown(sp[5])
		if i == 3:
			b.set_ready(false)
		b.position = pos[i]
		btns.append(b)
	await _settle(0.5)
	await _shot("side")
	(btns[0] as SideButton).button.button_pressed = true
	(btns[0] as SideButton).button.button_down.emit()
	(btns[0] as SideButton).button.queue_redraw()
	await _settle(0.1)
	await _shot("side_pressed")
	world.view_game(0, false)
	await _settle(1.2)

func _page_coin() -> void:
	var bg := ColorRect.new()
	bg.color = Color(Palette.SHADOW_DEEP, 0.35)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var bal := CoinAmount.new(5300, "md", "chip")
	ui.add_child(bal)
	bal.position = Vector2(250, 20)
	var src := UIKit.btn("Claim", "honey", "lg")
	ui.add_child(src)
	src.size = Vector2(200, 58)
	src.position = Vector2(95, 620)
	await _settle(0.3)
	CoinFly.run(ui, src.get_global_rect().get_center(), bal, 200)
	var marks := [0.1, 0.3, 0.55, 0.8, 1.3]
	var last := 0.0
	for m: float in marks:
		await _settle(m - last)
		last = m
		await _shot("coin_%03d" % int(m * 100))

func _page_result(kind: String) -> void:
	var bar := GameTopBar.new()
	ui.add_child(bar)
	bar.set_idle("Your turn — tap the dice")
	var tiles := _tiles(0, kind == "team")
	await _settle(0.3)
	bar.hide_for_result()
	var d := {}
	match kind:
		"win":
			d = {game = "ludo", human_won = true, reward = 200, xp_before = 60, xp_after = 160, standings = [
				{color = 0, name = "You", kind = "you", place = 1, finished = true, progress = 1.0},
				{color = 2, name = "Biscotti", kind = "cpu", cpu_id = "biscotti", place = 2, finished = false, progress = 0.72},
				{color = 1, name = "Mocha", kind = "cpu", cpu_id = "mocha", place = 3, finished = false, progress = 0.41},
				{color = 3, name = "Espresso", kind = "cpu", cpu_id = "espresso", place = 4, finished = false, progress = 0.18}]}
		"lose":
			d = {game = "ludo", human_won = false, reward = 0, xp_before = 30, xp_after = 70, standings = [
				{color = 1, name = "Mocha", kind = "cpu", cpu_id = "mocha", place = 1, finished = true, progress = 1.0},
				{color = 0, name = "You", kind = "you", place = 2, finished = false, progress = 0.81},
				{color = 3, name = "Espresso", kind = "cpu", cpu_id = "espresso", place = 3, finished = false, progress = 0.5},
				{color = 2, name = "Biscotti", kind = "cpu", cpu_id = "biscotti", place = 4, finished = false, progress = 0.33}]}
		"team":
			d = {game = "ludo", human_won = true, reward = 200, xp_before = 210, xp_after = 310, standings = [
				{color = 0, name = "You", kind = "you", place = 1, finished = true, progress = 1.0},
				{color = 2, name = "Biscotti", kind = "cpu", cpu_id = "biscotti", place = 1, finished = true, progress = 1.0},
				{color = 1, name = "Mocha", kind = "cpu", cpu_id = "mocha", place = 2, finished = false, progress = 0.66},
				{color = 3, name = "Espresso", kind = "cpu", cpu_id = "espresso", place = 2, finished = false, progress = 0.4}]}
		"sl":
			d = {game = "sl", human_won = false, reward = 0, xp_before = 0, xp_after = 0, standings = [
				{color = 0, name = "Red", kind = "human", place = 1, finished = true, progress = 1.0, pos = 100},
				{color = 1, name = "Green", kind = "human", place = 2, finished = false, progress = 0.87, pos = 87},
				{color = 2, name = "Yellow", kind = "human", place = 3, finished = false, progress = 0.62, pos = 62}]}
	var bal: CoinAmount = null
	if int(d.reward) > 0:
		bal = CoinAmount.new(5300, "md", "chip")
		d.coin_target = bal
		d.coin_total = 5500
	var r := ResultScreen.new(d)
	r.open(ui)
	if bal:
		ui.add_child(bal)
		bal.position = Vector2(270, 16)
		bal.z_index = 60
	await _settle(0.9)
	await _shot("result_%s_reveal" % kind)
	await _settle(2.6)
	await _shot("result_%s" % kind)
	r.on_back()
	await _settle(0.4)
