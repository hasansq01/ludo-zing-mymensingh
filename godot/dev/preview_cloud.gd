extends Node
## Dev preview for one room: five fixed wide views (back, left, right, front wall, up at the ceiling), matching the
## web capture script. godot --path . --resolution 640x480 res://dev/preview_cloud.tscn -- <out_dir> [room]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() else "/tmp"
	var room: String = args[1] if args.size() > 1 else "cloud"
	var baker := TexBaker.new()
	add_child(baker)
	var world := TableWorld.new()
	add_child(world)
	await world.build_room(baker, func(_f): pass, room)
	world.view_home()
	for k in 30:
		world._process(0.1)
	world.set_process(false)
	var cam := world.camera
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = 70
	var views := [[Vector3(0, 5, 55), Vector3(0, 10, -60)], [Vector3(50, 5, 0), Vector3(-60, 10, 0)], [Vector3(-50, 5, 0), Vector3(60, 10, 0)], [Vector3(0, 5, -55), Vector3(0, 10, 60)], [Vector3(0, -20, 0), Vector3(0, 40, -60)]]
	for k in views.size():
		cam.look_at_from_position(views[k][0], views[k][1], Vector3.UP)
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/gd_view%d.png" % k)
	get_tree().quit()
