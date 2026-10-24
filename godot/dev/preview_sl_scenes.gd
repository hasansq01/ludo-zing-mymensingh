extends Node
## Dev preview of SLScenes: builds each S&L scene with the real board, then saves the landing, the 3D match view and
## the top view. godot --path . --resolution 500x1082 res://dev/preview_sl_scenes.tscn -- [out_dir] [scene ...]

const OUT := "/private/tmp/claude-501/-Users-shihabshaharia-Coding-ludo-zing-mymensingh/d8feebe6-eee1-4f48-a116-aa2f313481c9/scratchpad/agent_scenes/godot/"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() and args[0].begins_with("/") else OUT
	var ids := []
	for a in args:
		if SLScenes.SCENES.has(a):
			ids.append(a)
	if ids.is_empty():
		ids = ["jungle", "frost", "candy", "desert", "cloud", "enchanted"]
	var baker := TexBaker.new()
	add_child(baker)
	var scenes := SLScenes.new()
	add_child(scenes)
	var board := SLBoard.new()
	scenes.attach_board(board)
	await board.build(baker)
	var landing: Control = null
	if "ui" in args:
		landing = SLLanding.new()
		var cl := CanvasLayer.new()
		add_child(cl)
		cl.add_child(landing)
	scenes.camera.make_current()
	for id in ids:
		var t0 := Time.get_ticks_msec()
		await scenes.set_scene(baker, id)
		print("[preview] %s built in %d ms, %d nodes" % [id, Time.get_ticks_msec() - t0, _count(scenes)])
		if landing:
			landing.set_scene_name(SLScenes.info(id).name)
			landing.visible = true
		board.setup_players([])
		scenes.play(false)
		scenes.reduced_motion = true
		scenes.t = 10.0
		scenes._table.rotation.y = 0.6
		await _frames(scenes, 3)
		await _shot(out + id + "_landing.png")
		if landing:
			landing.visible = false
		board.setup_players([0, 1])
		board.place([0, 0])
		board.set_current(0)
		scenes.play(true, "3d")
		for k in 40:
			scenes.tick(0.05)
		await _frames(scenes, 3)
		await _shot(out + id + "_match3d.png")
		scenes.set_view("top")
		await _frames(scenes, 3)
		await _shot(out + id + "_matchtop.png")
		scenes.play(false, "3d")
	get_tree().quit()

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c

func _frames(scenes: SLScenes, n: int) -> void:
	for k in n:
		scenes.snap_camera()
		await get_tree().process_frame

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
