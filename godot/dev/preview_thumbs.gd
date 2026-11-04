extends Node
## Dev: renders every room and S&L scene thumbnail with Thumbnailer inside the real app (fresh, cache cleared) and
## shoots a contact sheet of Thumbnailer.View cards over the home screen. The real save is backed up and restored.
##   godot --path . --resolution 390x844 res://dev/preview_thumbs.tscn -- <out_dir>

var out := "/tmp"
var main: Node
var _backup := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	var room_before := ""
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen in ["home", "welcome"], 60)
	room_before = str(Save.profile.room)
	var cafe_before: String = main.world.rooms.current
	Thumbnailer.clear(true)
	# a contact sheet opening first: its views show the shimmer, then fade in as the worker renders
	var layer: Control = main.sheet_layer
	var s := Sheet.new("Thumbnails", UIKit.W.wide)
	var list := s.add_scroll_body()
	var views := []
	for kind in Thumbnailer.KINDS:
		list.add_child(UIKit.caption("Rooms" if kind == "room" else "Scenes"))
		var g := UIKit.grid(2, UIKit.SPACE.sm)
		list.add_child(g)
		for id in Thumbnailer.ids(kind):
			var v := UIKit.vbox(2)
			var t := Thumbnailer.view(kind, id)
			t.custom_minimum_size = Vector2(0, 120)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_child(t)
			v.add_child(UIKit.label(id, UIKit.FS.small, Palette.MUTED))
			g.add_child(v)
			views.append(t)
	s.open(layer)
	await _sleep(0.6)
	await _shot("thumbs_loading")
	var t0 := Time.get_ticks_msec()
	for kind in Thumbnailer.KINDS:
		for id in Thumbnailer.ids(kind):
			var tex: Texture2D = await Thumbnailer.get_async(kind, id)
			print("%s %s ready at %d ms: %s" % [kind, id, Time.get_ticks_msec() - t0, tex.get_size() if tex else "null"])
			if tex:
				tex.get_image().save_png("%s/thumb_%s_%s.png" % [out, kind, id])
	await _sleep(0.8)
	await _shot("thumbs_contact")
	s.scroll_box.scroll_vertical = 10000
	await _sleep(0.4)
	await _shot("thumbs_contact_2")
	print("profile room unchanged: ", str(Save.profile.room) == room_before, "; cafe room unchanged: ", main.world.rooms.current == cafe_before)
	print("worker freed: ", get_tree().root.get_node_or_null("Thumbnailer") == null)
	# second pass: everything comes from the disk cache
	Thumbnailer.clear(false)
	var t1 := Time.get_ticks_msec()
	for id in Thumbnailer.ids("room"):
		Thumbnailer.room(id)
	print("5 rooms from disk in %d ms" % (Time.get_ticks_msec() - t1))
	_restore()
	get_tree().quit()

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out, n]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _until(f: Callable, sec: float) -> void:
	var t := 0.0
	while not f.call() and t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()

func _sleep(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _restore() -> void:
	Save._dirty = false
	if _backup != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(_backup)
		f.close()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_restore()
