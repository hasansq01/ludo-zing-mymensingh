extends Node
## Dev preview: builds the café + table + board and saves screenshots (home view, game view, top view).
## godot --path . res://dev/preview_world.tscn -- <out_dir>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() else "/tmp"
	var tag: String = args[1] if args.size() > 1 else ""
	if args.size() > 4:
		TableWorld.SHADOWS = args[2] == "1"
		TableWorld.SHADOW_BIAS = float(args[3])
		TableWorld.SHADOW_NBIAS = float(args[4])
	var baker := TexBaker.new()
	add_child(baker)
	var world := TableWorld.new()
	add_child(world)
	await world.build_room(baker, func(_f): pass, args[5] if args.size() > 5 else Rooms.DEFAULT)
	var s := LudoRules.new_game(["human", "cpu", "cpu", "cpu"])
	s.tok[0][0] = 5; s.tok[1][0] = 20; s.tok[2][1] = 30; s.tok[3][2] = 52; s.tok[0][1] = 56
	world.board.relayout(s)
	world.board.set_movable([0, 2])
	world.reduced_motion = true
	world.view_home()
	await _settle(world)
	_shot(out + "/world_home%s.png" % tag)
	world.view_game(0, false)
	await _settle(world)
	_shot(out + "/world_game%s.png" % tag)
	world.view_game(0, true)
	await _settle(world)
	_shot(out + "/world_top%s.png" % tag)
	get_tree().quit()

func _settle(world: TableWorld) -> void:
	for k in 200:
		world._process(0.1)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
