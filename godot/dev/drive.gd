extends Node
## Dev driver: runs the real app (scenes/main.tscn), plays through the main flows and saves screenshots.
## godot --path . res://dev/drive.tscn -- <out_dir> [steps]

var out := "/tmp"
var main: Node
var n := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen in ["home", "welcome"], 30)
	if main.screen == "welcome":
		await _sleep(1.5)
		await shot("welcome")
		for c in main.screens.get_children():
			if c is Welcome:
				c.continued.emit()
		await _until(func(): return main.screen == "home", 10)
	await _sleep(2.5)
	var top: Sheet = main._top_sheet()
	if top:
		top.close()
		await _sleep(0.5)
	await shot("home")
	main._open_setup("ludo", "cpu")
	await _sleep(0.8)
	await shot("setup_cpu")
	main._top_sheet().close()
	await _sleep(0.4)
	main.speed = 0.4
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false})
	await _sleep(2.0)
	await shot("ludo_start")
	main.ludo.roll(6)
	await _sleep(2.2)
	await shot("ludo_after_six")
	await autoplay(40.0, "ludo_play")
	main.open_pause()
	await _sleep(0.6)
	await shot("pause")
	main._top_sheet().close()
	await _sleep(0.4)
	main.open_sl_landing()
	await _sleep(3.0)
	await shot("sl_landing")
	main.start_sl({game = "sl", mode = "cpu", n = 3, color = 0})
	await _sleep(2.0)
	await shot("sl_start")
	await autoplay_sl(30.0)
	await shot("sl_play")
	main.go_home()
	await _sleep(1.0)
	main._on_tab("settings")
	await _sleep(0.8)
	await shot("settings")
	main._top_sheet().close()
	await _sleep(0.4)
	main._on_tab("profile")
	await _sleep(0.8)
	await shot("profile")
	main._top_sheet().close()
	await _sleep(0.4)
	var cs = load("res://scripts/ui/sheets/collection_sheet.gd").new()
	cs.open(main.sheet_layer)
	await _sleep(0.8)
	await shot("collection")
	cs.close()
	await _sleep(0.4)
	var sh = load("res://scripts/ui/sheets/shop_sheet.gd").new("scenes")
	sh.open(main.sheet_layer)
	await _sleep(0.8)
	await shot("shop_scenes")
	get_tree().quit()

func autoplay(sec: float, tag: String) -> void:
	var t0 := Time.get_ticks_msec()
	var k := 0
	while (Time.get_ticks_msec() - t0) / 1000.0 < sec:
		await _sleep(0.25)
		var S: Dictionary = main.ludo.S
		if S.is_empty() or S.phase == "over":
			break
		var top: Sheet = main._top_sheet()
		if top and top.title_label and top.title_label.text == "Make a pair?":
			for b in top.find_children("*", "Button", true, false):
				if b.text == "Pair up":
					b.pressed.emit()
			continue
		if LudoRules.is_human(S, S.turn):
			if S.phase == "roll":
				main.ludo.roll()
			elif S.phase == "pick":
				main.ludo.choose_pick("single")
			elif S.phase == "choose" and not main.ludo._busy:
				var mv := LudoRules.picked(S, S.pick) if S.pick != "" else LudoRules.movables(S)
				if mv.size():
					main.ludo.move(mv[0])
		if (Time.get_ticks_msec() - t0) / 1000.0 > (k + 1) * 12.0:
			k += 1
			await shot("%s_%d" % [tag, k])

func autoplay_sl(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < sec:
		await _sleep(0.3)
		var G: Dictionary = main.sl.G
		if G.is_empty() or G.phase == "over":
			break
		if G.players[G.turn].you and G.phase == "roll":
			main.sl.roll()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name])
	print("shot ", name)

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
