extends Node
## Dev: every Ludo room in a match (3D View and Top View) plus the Shop preview of chosen rooms, for lighting checks.
## godot --path . --resolution 390x844 res://dev/room_shots.tscn -- <out_dir> [tag] [rooms,comma,separated] [preview,rooms|none] [cues]
## "cues": a board with a pair and a mixed stack on one star, two singles sharing a square, a finished pawn, and
## your pawns glowing as movable (the rest of your colour dimmed).
## Never writes the real save: Save's debounced flush is unhooked, and the file is restored at the end anyway.

var out := "/tmp"
var tag := "shot"
var main: Node
var _backup := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		tag = args[1]
	var ids: Array = Rooms.LIST.map(func(r): return r.id)
	if args.size() > 2 and args[2] != "all":
		ids = Array(args[2].split(","))
	var previews: Array = ["studio"]
	if args.size() > 3:
		previews = Array(args[3].split(",")) if args[3] != "none" else []
	var cues := args.size() > 4 and args[4] == "cues"
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	Save.prefs.cam = "3d"
	var owned: Array = Save.profile.get("rooms", []) if Save.profile.get("rooms") is Array else []
	for id in ids + previews:
		if not owned.has(id):
			owned.append(id)
	Save.profile.rooms = owned
	Save.profile.room = ids[0]
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "home", 60)
	await _sleep(1.0)
	for id in ids:
		Save.profile.room = id
		await main.apply_room(id)
		Save.prefs.cam = "3d"
		main._on_prefs_changed()
		main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false})
		await _sleep(0.6)
		main.ludo._id += 1                    # freeze the match: no turns, the board stays as laid out
		var S: Dictionary = main.ludo.S
		S.tok = [[12, 12, 30, -1], [5, 40, -1, -1], [20, 51, -1, -1], [8, 25, 44, -1]]
		if cues:
			S.tok = [[8, 8, 20, 56], [7, 40, -1, -1], [34, 51, -1, -1], [21, 25, 44, -1]]
			S.pairs = [{c = 0, a = 0, b = 1}]
		main.world.board.relayout(S)
		if cues:
			main.world.board.set_movable([0, 1, 2], 0)
		await _sleep(2.6)
		await shot("%s_%s_3d" % [tag, id])
		Save.prefs.cam = "top"
		main._on_prefs_changed()
		await _sleep(2.8)
		await shot("%s_%s_top" % [tag, id])
		Save.prefs.cam = "3d"
		main._on_prefs_changed()
		main.go_home()
		await _sleep(0.8)
	for id in previews:
		PreviewSheet.new(id).open(main.sheet_layer)
		await _sleep(4.0)
		await shot("%s_%s_preview" % [tag, id])
		main.close_all_sheets()
		await _sleep(1.5)
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
