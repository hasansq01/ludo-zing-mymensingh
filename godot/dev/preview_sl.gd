extends Node3D
## Dev preview of SLBoard: builds the board on a plain table, places pawns, runs a hop / climb / slide and saves
## screenshots (a 62° game view and a top view) to OUT, then quits. Run: godot --path . res://dev/preview_sl.tscn

const OUT := "/private/tmp/claude-501/-Users-shihabshaharia-Coding-ludo-zing-mymensingh/d8feebe6-eee1-4f48-a116-aa2f313481c9/scratchpad/agent_sl/"

var board: SLBoard
var views := []

func _ready() -> void:
	var baker := TexBaker.new()
	add_child(baker)
	if "simple" in OS.get_cmdline_user_args():
		_simple_room()
	else:                                       # the real café: TableWorld's lights, table and room
		var tw := TableWorld.new()
		add_child(tw)
		await tw.build_room(baker, func(_p: float): pass)
		tw.board.visible = false
		for k in tw.cups.size():
			tw.cups[k].visible = false
	board = SLBoard.new()
	add_child(board)
	await board.build(baker)
	board.setup_players([0, 3, 2])
	views.append(_view(Vector2i(900, 1500), deg_to_rad(62.0), 30.0))
	views.append(_view(Vector2i(1400, 1400), deg_to_rad(89.9), 25.0))
	views.append(_view(Vector2i(1200, 900), deg_to_rad(45.0), 9.0, Vector3(1.5, 0, 0.5)))
	board.place([0, 0, 0])
	board.set_current(0)
	await _wait(0.4)
	await _shot("00_start")
	board.place([27, 27, 64])
	board.set_current(1)
	await _wait(0.4)
	await _shot("01_shared")
	# hop 27 -> 28 (ladder foot), climb to 84; hop player 2 64 -> 65 ... and a slide 98 -> 78
	await board.hop_to(0, 28)
	_shot_later(0.4, "02_mid_climb")
	await board.climb(0, 28, 84)
	await _wait(0.2)
	board.place([84, 98, 78])
	await _wait(0.4)
	board.set_current(1)
	_shot_later(0.3, "03_mid_slide")
	await board.slide(1, 98, 78)
	await _wait(0.2)
	board.place([1, 87, 100])
	board.set_current(2)
	await board.slide(1, 87, 24)
	await _wait(0.5)
	await _shot("04_end")
	get_tree().quit()

func _simple_room() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#2b2244")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c8b4d0")
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#fff0dc")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	sun.look_at_from_position(Vector3(4, 30, 12), Vector3.ZERO, Vector3.UP)
	var table := CylinderMesh.new()
	table.top_radius = 14.5; table.bottom_radius = 14.5; table.height = 1.2; table.radial_segments = 72
	MeshKit.put(self, table, MeshKit.mat(Color("#f2c693"), 0.35), Vector3(0, -0.31 - 0.6, 0))

func _view(size: Vector2i, el: float, dist: float, at := Vector3.ZERO) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 48.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	vp.add_child(cam)
	cam.look_at_from_position(at + Vector3(0, sin(el) * dist, cos(el) * dist), at, Vector3.UP if el < 1.5 else Vector3.FORWARD)
	return vp

func _shot_later(s: float, name: String) -> void:
	get_tree().create_timer(s).timeout.connect(func(): await _shot(name))

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	for k in views.size():
		var img: Image = views[k].get_texture().get_image()
		img.save_png(OUT + name + ["_game", "_top", "_close"][k] + ".png")
