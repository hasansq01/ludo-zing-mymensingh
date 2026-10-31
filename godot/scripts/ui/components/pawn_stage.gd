class_name PawnStage
extends SubViewportContainer
## Pawns in a pawn skin (PawnSkins) in their own little 3D world, for the Shop: a SubViewport with its OWN World3D
## (transparent background, its own lights, nothing shared with the café), stretched over the control.
##   CARD   a red pawn in front and a blue one behind it, still: the Shop card's picture (dev/bake_thumbs bakes it
##          into assets/thumbs/pawn_<id>.webp; this is the live fallback for a skin without a bake)
##   FOUR   the four seat colours side by side, turning slowly on the spot (PawnSheet), so every colour can be seen
##          in the skin from every side
## Draws only while visible (UPDATE_WHEN_VISIBLE); a still CARD stops drawing after a few frames.
##   var st := PawnStage.new("crown", PawnStage.FOUR); st.custom_minimum_size = Vector2(320, 200); add_child(st)

const CARD := "card"
const FOUR := "four"
const SPIN := 0.55                       ## FOUR: radians a second each pawn turns
## Where the pawns stand per layout: [colour index, position, scale]; the camera's eye and target.
const LAYOUTS := {
	card = {pawns = [[3, Vector3(0.42, 0, -0.42), 0.92], [0, Vector3(-0.3, 0, 0.18), 1.0]],
		eye = Vector3(0.0, 1.7, 4.7), look = Vector3(0.06, 0.3, -0.1), fov = 27.0},
	four = {pawns = [[0, Vector3(-1.38, 0, 0), 1.0], [1, Vector3(-0.46, 0, 0), 1.0], [2, Vector3(0.46, 0, 0), 1.0], [3, Vector3(1.38, 0, 0), 1.0]],
		eye = Vector3(0.0, 1.3, 5.5), look = Vector3(0.0, 0.48, 0.0), fov = 26.0},
}

var skin := "classic"
var layout := CARD
var keep_drawing := false                ## a still CARD keeps drawing (the bake tool reads it back)
var viewport: SubViewport
var camera: Camera3D
var _root: Node3D
var _looks: Array = []                   # [{node, look}] per pawn
var _still_frames := 0


func _init(skin_ := "classic", layout_ := CARD) -> void:
	skin = skin_
	layout = layout_ if LAYOUTS.has(layout_) else CARD
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	_root = Node3D.new()
	viewport.add_child(_root)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#fff4e6")
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var L: Dictionary = LAYOUTS[layout]
	camera = Camera3D.new()
	camera.environment = env
	camera.fov = float(L.fov)
	_root.add_child(camera)
	camera.transform = Transform3D(Basis.looking_at(L.look - L.eye, Vector3.UP), L.eye)   # (not in the tree yet)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.05
	key.light_color = Color("#fffaf0")
	key.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-28.0), 0)
	_root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.32
	fill.light_color = Color("#ffe6cf")
	fill.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(150.0), 0)
	_root.add_child(fill)
	set_skin(skin)


## Dress the pawns in another skin.
func set_skin(id: String) -> void:
	skin = id
	for l: Dictionary in _looks:
		(l.node as Node).queue_free()
	_looks.clear()
	for p: Array in (LAYOUTS[layout] as Dictionary).pawns:
		var g := Node3D.new()
		g.position = p[1]
		g.scale = Vector3.ONE * float(p[2])
		_root.add_child(g)
		var look := PawnSkins.dress(g, id, Palette.PLAYER[int(p[0])])
		MeshKit.contact_shadow(g, 1.1, 1.1, Vector3(0, 0.004, 0), Color(0.24, 0.13, 0.07, 0.38))
		var to_cam := camera.position - g.position              # the skin's front towards the camera (PawnSkins.face)
		g.rotation.y = atan2(to_cam.x, to_cam.z)
		if layout == FOUR:
			g.rotation.y += float(_looks.size()) * 0.7     # each a little turned from the next
		_looks.append({node = g, look = look})
	_still_frames = 0
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE

func _process(delta: float) -> void:
	if layout == FOUR:
		var now := Time.get_ticks_msec() / 1000.0
		var still := not PawnSkins.moving(false)
		for l: Dictionary in _looks:
			(l.node as Node3D).rotation.y += SPIN * delta
			PawnSkins.animate(l.look.mat, now, still)
	elif _still_frames < 4 and not keep_drawing and is_visible_in_tree():
		_still_frames += 1                  # a still card: a few drawn frames (textures, MSAA settle), then no more draws
		if _still_frames == 4:
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
