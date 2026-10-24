extends Node
## Dev: per-light contributions in a room, measured on white Lambert probe squares on the board and the table
## (compare with the same probes in the web build). Prints linear values per light group.
## godot --path . --resolution 390x844 res://dev/light_split.tscn -- <room> [out_png_dir]
## Never writes the real save (Save's flush is unhooked; the file is restored at the end).

var main: Node
var _backup := ""
const PROBES := [Vector3(0, 0.9, 0), Vector3(5, 0.9, 5), Vector3(-5, 0.9, -5)]
## bare board points (no probe): the four base corners (coloured) and two white home pads
const SAMPLES := [Vector3(7, 0.3, 7), Vector3(-7, 0.3, 7), Vector3(7, 0.3, -7), Vector3(-7, 0.3, -7), Vector3(4.5, 0.3, 3.6), Vector3(-4.5, 0.3, -3.6), Vector3(0, -0.3, 10.5), Vector3(0, -0.3, -10.5)]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var room: String = args[0] if args.size() > 0 else "studio"
	var outdir: String = args[1] if args.size() > 1 else ""
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	Save.prefs.cam = args[2] if args.size() > 2 else "top"
	Save.profile.room = room
	var owned: Array = Save.profile.get("rooms", []) if Save.profile.get("rooms") is Array else []
	owned.append(room)
	Save.profile.rooms = owned
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "home", 60)
	await main.apply_room(room)
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false})
	await _sleep(0.5)
	main.ludo._id += 1
	main._on_prefs_changed()
	await _sleep(3.0)
	if main.hud is CanvasItem:
		main.hud.visible = false
	var w: TableWorld = main.world
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color.WHITE
	pm.roughness = 1.0
	pm.metallic_specular = 0.0
	pm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	var probes := []
	for p in PROBES:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.plane(1.6, 1.6)
		mi.material_override = pm
		mi.position = p
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(mi)
		probes.append(mi)
	var omnis: Array = w.rooms._built[room].find_children("*", "OmniLight3D", true, false)
	var amb := w.env.ambient_light_energy
	var key_e := w.key.light_energy
	var cfgs := {all = [true, true, true], ambient = [true, false, false], key = [false, true, false], omni = [false, false, true], amb_key = [true, true, false], amb_omni = [true, false, true], key_omni = [false, true, true], none = [false, false, false], all2 = [true, true, true]}
	for name in cfgs:
		var c: Array = cfgs[name]
		w.env.ambient_light_energy = amb if c[0] else 0.0
		w.key.visible = c[1]
		for o in omnis:
			o.visible = c[2]
		for k in 4:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if outdir != "":
			img.save_png("%s/split_%s_%s.png" % [outdir, room, name])
		var vals := []
		for p in PROBES + SAMPLES:
			var s := w.camera.unproject_position(p) * Vector2(img.get_size()) / get_viewport().get_visible_rect().size
			var col := img.get_pixelv(Vector2i(s))
			var li := col.srgb_to_linear()
			vals.append("(%d %d %d|%.2f %.2f %.2f)" % [col.r8, col.g8, col.b8, li.r, li.g, li.b])
		print("SPLIT %s %s: %s" % [room, name, " ".join(vals)])
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
