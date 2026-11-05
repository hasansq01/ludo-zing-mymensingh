extends Node
## Every pawn skin in one picture, as the Shop draws it, with its triangle count (designing skins without baking):
##   godot --path . res://dev/pawn_preview.tscn -- <out.png> [four] [ids ...]   (needs a GPU: not --headless)
## four: all four colours of each skin (PawnStage.FOUR) instead of the Shop's pair.
## board: the skins named (up to four, one per colour) on a real board, in 3D View and Top View, at play size.
## Never saves the player's game.

const W := 300
const H := 225
const COLS := 5
const GAP := 8

func _ready() -> void:
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	var args := OS.get_cmdline_user_args()
	if args.size() > 1 and args[1] == "board":
		await _boards(args[0], args.slice(2))
		get_tree().quit()
		return
	var four := args.size() > 1 and args[1] == "four"
	var rest := args.slice(2 if four else 1)
	var ids: Array = rest if not rest.is_empty() else Thumbnailer.ids("pawn")
	var rows := ceili(ids.size() / float(mini(COLS, ids.size())))
	var cols := mini(COLS, ids.size())
	var sheet := Image.create(cols * (W + GAP) + GAP, rows * (H + GAP) + GAP, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#fff3e6"))
	for i in ids.size():
		var sk := PawnSkins.meshes(ids[i], Palette.PLAYER[0])
		var tris := _tris(sk.body) + _tris(sk.head)
		for a: Dictionary in sk.accents:
			tris += _tris(a.mesh)
		print("%-10s %5d triangles  top %.2f" % [ids[i], tris, float(sk.top)])
		var st := PawnStage.new(ids[i], PawnStage.FOUR if four else PawnStage.CARD)
		st.keep_drawing = true
		st.size = Vector2(W * 2, H * 2)
		st.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(st)
		st.size = Vector2(W * 2, H * 2)
		for f in 5:
			await RenderingServer.frame_post_draw
		var img := st.viewport.get_texture().get_image()
		st.queue_free()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(W, H, Image.INTERPOLATE_LANCZOS)
		var at := Vector2i(GAP + (i % cols) * (W + GAP), GAP + (i / cols) * (H + GAP))
		sheet.fill_rect(Rect2i(at, Vector2i(W, H)), Color("#f7dfe0"))
		sheet.blend_rect(img, Rect2i(0, 0, W, H), at)
	sheet.save_png(args[0])
	get_tree().quit()

## The skins on the board at both game camera angles, side by side (a phone's width each).
func _boards(out: String, ids: Array) -> void:
	var sheet := Image.create(1460, 720, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	var view := 0
	for el: float in [TableWorld.GAME_EL, TableWorld.TOP_EL]:
		var vp := SubViewport.new()
		vp.size = Vector2i(720, 720)
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var board := LudoBoard.new()
		vp.add_child(board)
		board.set_skins(ids)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("#d9b48a")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("#fff4e6")
		env.ambient_light_energy = 0.7
		var cam := Camera3D.new()
		cam.environment = env
		cam.fov = 30.0
		vp.add_child(cam)
		var dist := 21.0
		cam.look_at_from_position(Vector3(0, sin(el) * dist, cos(el) * dist), Vector3.ZERO, Vector3.FORWARD if el > 1.5 else Vector3.UP)
		var sun := DirectionalLight3D.new()
		sun.light_energy = 1.0
		sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-25.0), 0)
		vp.add_child(sun)
		var k := clampf((el - TableWorld.GAME_EL) / (TableWorld.TOP_EL - TableWorld.GAME_EL), 0.0, 1.0)
		for f in 8:
			for row in board.toks:
				for t in row:
					PawnSkins.face(t.node, board, cam)
					PawnSkins.pose(t.look, k, 1.0 if k > 0.5 else 1.29)
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, 720, 720), Vector2i(view * 740, 0))
		vp.queue_free()
		view += 1
	sheet.save_png(out)

static func _tris(m: Mesh) -> int:
	if m == null:
		return 0
	var a := m.surface_get_arrays(0)
	return (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
