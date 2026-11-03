extends Node
## Dev: the S&L landing and a Pass & Play match inside the real app (main.tscn): the landing, its "Change scene"
## shortcut (Shop, Scenes tab) and a 3-player Pass & Play start. Backs up / restores the save like tour.gd.
##   godot --path . --resolution 390x844 res://dev/preview_sl_app.tscn -- <out_dir>

var out := "/tmp"
var main: Node
var _backup := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	MatchStore.enabled = false
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen in ["home", "welcome"], 40)
	for c in main.screens.get_children():
		if c is Welcome:
			c.continued.emit()
	await _sleep(1.5)
	for c in main.sheet_layer.get_children():
		c.queue_free()
	main.open_sl_landing()
	await _sleep(2.5)
	await shot("app_landing")
	main.landing._scene_btn.pressed.emit()
	await _sleep(1.2)
	await shot("app_change_scene")
	for c in main.sheet_layer.get_children():
		c.queue_free()
	await _sleep(0.3)
	main.start_sl({game = "sl", mode = "local", n = 3, color = 0})
	await _sleep(2.5)
	await shot("app_local_start")
	main.sl.roll(6)
	await _sleep(0.9)
	await shot("app_local_six")
	await _sleep(1.6)
	await shot("app_local_after")
	_restore()
	get_tree().quit()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)

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
