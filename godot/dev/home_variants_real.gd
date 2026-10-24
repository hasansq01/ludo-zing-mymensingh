extends Node
## Dev (W1): the real HomeScreen inside main.tscn in its states (plain / continue / again / snakes), with signal
## checks. godot --path . --resolution 390x844 res://dev/home_variants_real.tscn -- <out_dir> <tag> [safe_top] [safe_bottom]
## Throwaway state: the real save and user://match.json are backed up first and restored at the end.

const MATCH := "user://match.json"

var out := "/tmp"
var tag := "390"
var main: Node
var _backup := ""
var _match_backup := ""
var _log: Array = []

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	if a.size() > 1: tag = a[1]
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	if FileAccess.file_exists(MATCH):
		_match_backup = FileAccess.get_file_as_string(MATCH)
	_remove_match()
	MatchStore.enabled = false                 # games started by the signal checks don't write user://match.json
	Save.profile.room = Rooms.DEFAULT
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen in ["home", "welcome"], 40)
	await _sleep(0.8)
	for c in main.screens.get_children():
		if c is Welcome:
			c.continued.emit()
	await _until(func(): return main.screen == "home", 10)
	await _sleep(1.0)
	main.close_all_sheets()
	if a.size() > 2:
		main.safe_top = float(a[2])
		main.safe_bottom = float(a[3]) if a.size() > 3 else 0.0
		main.home.safe_top = main.safe_top
		main.home.safe_bottom = main.safe_bottom
	var home: HomeScreen = main.home
	Save.profile.name = "Shihab"
	Save.profile.coins = 5300
	Save.profile.xp = 260
	var R: Script = load("res://scripts/core/rewards.gd")
	Save.profile.last_spin = R.day_key()
	Save.profile.last_free = int(Time.get_unix_time_from_system()) - (int(R.FREE_EVERY_SEC) - 13990)
	Save.prefs.erase("last_played")
	Save.prefs.home_game = "ludo"
	home.game = "ludo"
	for sig in ["play", "play_game", "continue_match", "play_again", "game_switched", "open_tab"]:
		home.connect(sig, func(x = null, y = null): _log.append([sig, x, y]))
	await _state("plain")
	# Continue match: a saved match file
	var f := FileAccess.open(MATCH, FileAccess.WRITE)
	f.store_string(JSON.stringify({v = 1, game = "ludo", summary = "Ludo vs Computer · 35%", saved_at = int(Time.get_unix_time_from_system()) - 720, state = {x = 1}}))
	f.close()
	await _state("continue")
	_remove_match()
	Save.prefs.last_played = {game = "ludo", mode = "cpu"}
	if not Save.prefs.get("last_setup") is Dictionary:
		Save.prefs.last_setup = {}
	Save.prefs.last_setup["ludo"] = {cpu = {count = 3, color = 0, teams = false, bot_level = "normal"}}
	await _state("again")
	(home._switch_buttons["sl"] as Button).button_pressed = true
	await _state("snakes")
	# signal checks
	_log.clear()
	(home._modes.get_child(0) as Button).pressed.emit()
	(home._modes.get_child(1) as Button).pressed.emit()
	home._quick.pressed.emit()
	(home._tabs.get_child(1) as Button).pressed.emit()
	(home._tabs.get_child(2) as Button).pressed.emit()
	home.sides.spin.button.pressed.emit()
	print("signals: ", _log)
	print("band ", home.free_band(), " factor ", home.table_width_factor, " coin_amount ", home.coin_amount, " side ", home.side_button("free"))
	main.close_all_sheets()
	_restore()
	get_tree().quit()

func _state(name: String) -> void:
	if name != "continue":
		_remove_match()                        # (other dev runs share user://)
	main.close_all_sheets()
	main.go_home()
	main.home.refresh()
	main._fit_home()
	await _sleep(0.2)
	var w = main.world
	w.orbit = false
	w.cam_target_az = TableWorld.seat_az(0) + 0.35
	w.cam_az = w.cam_target_az
	w.cam_zoom = w.cam_target_zoom
	w.cam_el = w.cam_target_el
	w.view_y = w.view_target_y
	await _sleep(1.4)
	main.close_all_sheets()
	await RenderingServer.frame_post_draw
	var path := "%s/real_C_%s_%s.png" % [out, name, tag]
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)

func _remove_match() -> void:
	if FileAccess.file_exists(MATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MATCH))

func _restore() -> void:
	Save._dirty = false
	if _backup != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
		Save.load_data()
	if _match_backup != "" and not FileAccess.file_exists(MATCH):
		var m := FileAccess.open(MATCH, FileAccess.WRITE)
		m.store_string(_match_backup)
		m.close()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_restore()

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
