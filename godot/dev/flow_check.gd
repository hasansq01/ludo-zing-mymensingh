extends Node
## Dev: checks the app flow end to end in a window (W7): launch straight to Home (welcome already seen), Back
## (Escape) on every screen, the frame cap, pause confirms, an autoplayed match to the ResultScreen, Back on the
## result = Home, and Play again. Screenshots to <out_dir>.
## godot --path . --resolution 390x844 res://dev/flow_check.tscn -- <out_dir> [--safe=0,34]
## Runs on the real save backed up first and restored at the end (like tour.gd).

var out := "/tmp"
var main: Node
var n := 0
var fails := 0
var _backup := ""
var _match_backup := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() and not args[0].begins_with("--"):
		out = args[0]
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	if FileAccess.file_exists(MatchStore.PATH):
		_match_backup = FileAccess.get_file_as_string(MatchStore.PATH)
	Save.prefs.welcome_seen = true
	Rewards.daily_data(Save.profile).auto_on = Rewards.day_key()   # keep the daily reward from popping up here
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "home", 40)
	await _sleep(1.0)
	check("later launches go splash -> home", main.screen == "home" and main.screens.get_children().all(func(c): return not c is Welcome))
	check("30 fps on Home", Engine.max_fps == 30, Engine.max_fps)
	check("safe bottom >= 0", main.safe_bottom >= 0.0, main.safe_bottom)
	await shot("home")
	# Back on Home: the quit confirm; Back again answers Stay
	await esc()
	check("Back on Home asks before quitting", _top_title() == "Leave the café?", _top_title())
	await shot("quit_confirm")
	await esc()
	check("Back on the quit confirm = Stay", main._top_sheet() == null and main.screen == "home")
	# Back closes sheets
	for tab in ["settings", "profile", "shop", "daily", "spin"]:
		main._on_tab(tab)
		await _sleep(0.7)
		var had: bool = main._top_sheet() != null
		await esc()
		check("Back closes %s" % tab, had and main._top_sheet() == null and main.screen == "home")
	# free coins: claim or the countdown toast
	main._on_tab("free")
	await _sleep(0.4)
	await shot("free_coins")
	await _sleep(1.6)
	# S&L landing: Back = Home
	main.open_sl_landing()
	await _sleep(2.5)
	await shot("sl_landing")
	await esc()
	await _sleep(0.6)
	check("Back on the S&L landing = Home", main.screen == "home")
	# a Ludo game: Back pauses, Back resumes; Exit asks
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false})
	await _sleep(1.5)
	check("60 fps in a match", Engine.max_fps == 60, Engine.max_fps)
	await esc()
	check("Back in a game pauses", main._pause_sheet != null and main.paused)
	await shot("pause")
	await esc()
	check("Back on pause resumes", main._pause_sheet == null and not main.paused)
	main.open_pause()
	await _sleep(0.5)
	main._ask_exit()
	await _sleep(0.6)
	check("Exit asks first", _top_title() == "Leave this game?", _top_title())
	await esc()
	check("Back on the exit confirm keeps playing", main.screen == "ludo" and main._pause_sheet != null)
	await esc()
	# Exit keeps the match: Continue resumes it
	main.ludo.roll(6)
	await _sleep(3.0)
	main.open_pause()
	await _sleep(0.4)
	main._ask_exit()
	await _sleep(0.6)
	(main._top_sheet().find_child("Yes", true, false) as Button).pressed.emit()
	await _sleep(1.0)
	check("Leave goes home and keeps the match", main.screen == "home" and MatchStore.has_saved(), MatchStore.peek())
	await shot("home_continue")
	main.continue_match()
	await _sleep(2.0)
	check("Continue resumes the Ludo match", main.screen == "ludo" and not main.ludo.S.is_empty())
	await shot("continued")
	main.go_home()
	await _sleep(0.5)
	# an autoplayed match to the result
	main.ludo.autoplay = true
	main.speed = 0.2
	main.world.board.speed = 0.2
	main.start_ludo({game = "ludo", players = ["human", "off", "cpu", "off"], teams = false})
	await _until(func(): return is_instance_valid(main._result), 300)
	check("the match ends on the ResultScreen", is_instance_valid(main._result))
	await _sleep(3.0)
	await shot("result")
	await esc()
	await _sleep(0.6)
	check("Back on the result = Home", main.screen == "home" and not is_instance_valid(main._result), main.screen)
	await shot("home_after_result")
	main.start_ludo({game = "ludo", players = ["human", "off", "cpu", "off"], teams = false})
	await _until(func(): return is_instance_valid(main._result), 300)
	await _sleep(2.5)
	var r: ResultScreen = main._result
	if r:
		r.again_button.pressed.emit()
	await _sleep(1.5)
	check("Play again starts the same game", main.screen == "ludo" and not is_instance_valid(main._result) and not main.ludo.S.is_empty() and main.ludo.S.players == ["human", "off", "cpu", "off"])
	await shot("play_again")
	main.ludo.autoplay = false
	main.go_home()
	await _sleep(0.8)
	check("30 fps back on Home", Engine.max_fps == 30, Engine.max_fps)
	print("FLOW: %d failed" % fails)
	_restore()
	get_tree().quit()

func _top_title() -> String:
	var t: Sheet = main._top_sheet()
	return t.title_label.text if t and t.title_label else ""

func esc() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var u := e.duplicate()
	u.pressed = false
	Input.parse_input_event(u)
	await _sleep(0.45)

func check(what: String, ok: bool, got: Variant = null) -> void:
	if not ok:
		fails += 1
	print("  %s %s%s" % ["ok  " if ok else "FAIL", what, "" if ok or got == null else "  got %s" % str(got)])

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name])

func _restore() -> void:
	if _match_backup != "":
		var m := FileAccess.open(MatchStore.PATH, FileAccess.WRITE)
		m.store_string(_match_backup)
		m.close()
	else:
		MatchStore.clear()
	Save._dirty = false
	if _backup != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
		Save.load_data()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_restore()

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
