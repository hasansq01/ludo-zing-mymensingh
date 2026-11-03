extends Node
## Dev (home rethink): screenshots of the lighter home layout candidates D / E / F (+ F2, F's mode sheet) from
## dev/home_layouts_lobby.gd over the real café, plus the CURRENT HomeScreen for comparison.
##   godot --path . --resolution 390x844 res://dev/home_layouts.tscn -- <out_dir> <tag> [safe_top] [safe_bottom] [variants] [states]
##   variants: "current,D,E,F,F2"; states: "plain,continue". Files: <out>/<variant>_<state>_<tag>.png
##   ("current" is written as 00_current_<state>_<tag>.png).
## Never writes user://save.json or user://match.json: Save's debounced flush is unhooked and Save._dirty is kept
## false (like dev/back_check.gd); the Continue match slot of the current home is filled in memory only.

const Lobby := preload("res://dev/home_layouts_lobby.gd")

var out := "/tmp"
var tag := "390"
var st := 0.0
var sb := 0.0
var variants := ["current", "D", "E", "F", "F2"]
var states := ["plain", "continue"]
var main: Node


func _ready() -> void:
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)        # dev run: nothing reaches user://save.json
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	if a.size() > 1: tag = a[1]
	if a.size() > 2: st = float(a[2])
	if a.size() > 3: sb = float(a[3])
	if a.size() > 4: variants = Array(a[4].split(","))
	if a.size() > 5: states = Array(a[5].split(","))
	DirAccess.make_dir_recursive_absolute(out)
	MatchStore.enabled = false
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	Save.prefs.erase("last_played")
	Save.prefs.home_game = "ludo"
	Save.profile.room = Rooms.DEFAULT
	Rewards.daily_data(Save.profile).auto_on = Time.get_date_string_from_system()   # no daily sheet popping up
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
	main.safe_top = st
	main.safe_bottom = sb
	main.home.safe_top = st
	main.home.safe_bottom = sb
	# a believable mid-progress profile (in memory only)
	Save.profile.name = "Shihab"
	Save.profile.coins = 5300
	Save.profile.xp = 260
	var R: Script = load("res://scripts/core/rewards.gd")
	Save.profile.last_spin = R.day_key()                         # today's spin used
	Save.profile.last_free = int(Time.get_unix_time_from_system()) - (int(R.FREE_EVERY_SEC) - 13990)   # 3:53:10 left
	for v in variants:
		for s in states:
			if v == "current":
				await _shot_current(s)
			else:
				await _shot_variant(v, s)
	Save._dirty = false
	get_tree().quit()


func _process(_d: float) -> void:
	Save._dirty = false


func _frame_cam() -> void:
	var w = main.world
	w.orbit = false
	w.cam_target_az = TableWorld.seat_az(0) + 0.35
	w.cam_az = w.cam_target_az
	w.cam_zoom = w.cam_target_zoom
	w.cam_el = w.cam_target_el
	w.view_y = w.view_target_y


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)


func _shot_current(s: String) -> void:
	var home: HomeScreen = main.home
	home.visible = true
	main.close_all_sheets()
	home.refresh()
	if s == "continue":                       # the Continue match pill, in memory only (no user://match.json)
		home._show_continue("Ludo vs Computer · 35%")
	main._fit_home()
	await _sleep(0.2)
	_frame_cam()
	await _sleep(1.4)
	main.close_all_sheets()
	await _save_shot("%s/00_current_%s_%s.png" % [out, s, tag])
	if s == "continue":
		home._show_continue("")


func _shot_variant(v: String, s: String) -> void:
	main.home.visible = false
	main.close_all_sheets()
	var q := {}
	if s == "continue":
		q = {kind = "continue", game = "ludo", title = "Continue match", sub = "Ludo vs Computer · 35%"}
	var lobby: Control = Lobby.new(v, q)
	lobby.safe_top = st
	lobby.safe_bottom = sb
	main.screens.add_child(lobby)
	await get_tree().process_frame
	lobby._layout()
	await get_tree().process_frame
	lobby._layout()
	var band: Vector2 = lobby.free_band()
	var w = main.world
	w.fit_home(band.x, band.y, main.ui_root.size * Vector2(lobby.table_width_factor, 1.0))
	w.view_home()
	_frame_cam()
	await _sleep(1.2)
	await _save_shot("%s/%s_%s_%s.png" % [out, v, s, tag])
	print("band ", band)
	lobby.queue_free()
	await get_tree().process_frame


func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
