extends Node
## Dev preview for the dream room port: overview shots of each wall from fixed cameras.
## godot --path . --resolution 1000x700 res://dev/preview_dream.tscn -- <out_dir> [room]

const VIEWS := [
	["back", Vector3(0, 20, 50), Vector3(0, 0, -60)],
	["left", Vector3(45, 20, 0), Vector3(-60, 0, 0)],
	["right", Vector3(-45, 20, 0), Vector3(60, 0, 0)],
	["front", Vector3(0, 20, -50), Vector3(0, 0, 60)],
]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() else "/tmp"
	var room: String = args[1] if args.size() > 1 else "dream"
	var baker := TexBaker.new()
	add_child(baker)
	var world := TableWorld.new()
	add_child(world)
	await world.build_room(baker, func(_f): pass, room)
	world.reduced_motion = true
	var cam := Camera3D.new()
	cam.fov = 60
	cam.near = 0.5
	cam.far = 500
	add_child(cam)
	cam.current = true
	world.set_process(false)
	for v in VIEWS:
		cam.look_at_from_position(v[1], v[2])
		for k in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/ov_%s_%s.png" % [room, v[0]])
	get_tree().quit()
