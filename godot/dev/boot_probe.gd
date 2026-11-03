extends Node
## Dev: times the app's startup (main.gd's splash phases, BootTrace) and the frames right after it, on desktop.
## godot --path godot --resolution 390x844 res://dev/boot_probe.tscn -- [--fresh] [--sl-match] [--quality=low]
##   --fresh     a first launch: an empty profile in memory (the welcome comes up instead of Home)
##   --shot=DIR  saves home.png (and sl.png with --sl-match) there
##   --sl-match  waits 10 s on Home (the background S&L warm-up), then starts a Snakes & Ladders match and reports its worst frame (the first-match shader freeze)
## Prints `[boot] ...` marks, then `[probe] ...` lines: the time to the first Home / welcome frame, the worst frame
## in the 3 s after the splash, and (--sl-match) the worst frame of the match's first 3 s.
## The save is never written: the debounced flush is unhooked and the real file is restored at the end anyway.

var main: Node
var _backup := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)      # dev run: nothing reaches user://save.json
	if args.has("--fresh"):
		Save.profile = {}
		Save.prefs = {}
		Save._ensure()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	while not BootTrace._done:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("[probe] first %s frame at %d ms" % [main.screen, Time.get_ticks_msec()])
	var shot := ""
	for a in args:
		if a.begins_with("--shot="):
			shot = a.trim_prefix("--shot=")
	if shot != "":
		get_viewport().get_texture().get_image().save_png(shot.path_join("home.png"))
	var secs := 10.0 if args.has("--sl-match") else 3.0   # (the background S&L warm-up runs meanwhile)
	print("[probe] worst frame in the %d s after the splash: %d ms" % [secs, await _worst(secs)])
	if args.has("--sl-match"):
		Save.prefs.welcome_seen = true
		main.go_home()
		await get_tree().create_timer(0.5).timeout
		var t0 := Time.get_ticks_msec()
		main.start_sl({game = "sl", mode = "cpu", n = 2, color = 0, bot_level = "normal"})
		var worst := await _worst(3.0)
		if shot != "":
			get_viewport().get_texture().get_image().save_png(shot.path_join("sl.png"))
		print("[probe] S&L match: worst frame in its first 3 s: %d ms (started %d ms after the tap)" % [worst, Time.get_ticks_msec() - t0 - 3000])
	_restore()
	get_tree().quit()

## The longest frame (ms) over the next `sec` seconds.
func _worst(sec: float) -> int:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	var last := Time.get_ticks_msec()
	var worst := 0
	while Time.get_ticks_msec() < end:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_msec()
		worst = maxi(worst, now - last)
		last = now
	return worst

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
