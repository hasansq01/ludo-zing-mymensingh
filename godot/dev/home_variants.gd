extends Node
## Dev (W1): screenshots of the candidate home layouts (dev/home_variants_lobby.gd) over the real café.
## godot --path . --resolution 390x844 res://dev/home_variants.tscn -- <out_dir> <tag> [safe_top] [safe_bottom] [variants] [states]
##   variants: "A,B,C"; states: "plain,continue,again" (the quick-resume slot). Runs on a throwaway profile state:
##   the real save is backed up first and restored at the end (like dev/tour.gd).

const Lobby := preload("res://dev/home_variants_lobby.gd")

var out := "/tmp"
var tag := "390"
var st := 0.0
var sb := 0.0
var variants := ["A", "B", "C"]
var states := ["plain", "continue"]
var widen := 1.0                         # the table may be this many screen widths wide (bigger board)
var main: Node
var _backup := ""

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: out = a[0]
	if a.size() > 1: tag = a[1]
	if a.size() > 2: st = float(a[2])
	if a.size() > 3: sb = float(a[3])
	if a.size() > 4: variants = Array(a[4].split(","))
	if a.size() > 5: states = Array(a[5].split(","))
	if a.size() > 6: widen = float(a[6])
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	Save.profile.room = Rooms.DEFAULT          # the default café, as in the user's screenshots (in memory only)
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
	# a believable mid-progress profile (in memory only)
	Save.profile.name = "Shihab"
	Save.profile.coins = 5300
	Save.profile.xp = 260
	var R: Script = load("res://scripts/core/rewards.gd")
	Save.profile.last_spin = R.day_key()                         # today's spin used: "13h 20m"
	Save.profile.last_free = int(Time.get_unix_time_from_system()) - (int(R.FREE_EVERY_SEC) - 13990)   # 3:53:10 left
	main.home.visible = false
	for v in variants:
		for s in states:
			var q := {}
			if s == "continue":
				q = {kind = "continue", game = "ludo", title = "Continue match", sub = "Ludo · vs 3 computers · Turn 34"}
			elif s == "again":
				q = {kind = "again", game = "ludo", title = "Play again", sub = "Ludo · 4 players · Normal"}
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
			w.fit_home(band.x, band.y, main.ui_root.size * Vector2(widen, 1.0))
			w.view_home()
			w.orbit = false
			w.cam_target_az = TableWorld.seat_az(0) + 0.35
			w.cam_az = w.cam_target_az
			w.cam_zoom = w.cam_target_zoom
			w.cam_el = w.cam_target_el
			w.view_y = w.view_target_y
			await _sleep(1.2)
			await RenderingServer.frame_post_draw
			var path := "%s/home_%s_%s_%s.png" % [out, v, s, tag]
			get_viewport().get_texture().get_image().save_png(path)
			print("shot ", path, " band ", band)
			lobby.queue_free()
			await get_tree().process_frame
	_restore()
	get_tree().quit()

func _restore() -> void:
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
