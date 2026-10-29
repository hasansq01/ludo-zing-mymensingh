class_name SLScenes
extends Node3D
## The Snakes & Ladders worlds (index.html: the Jungle module, SCENES, SL_SCENES, buyScene / useScene).
## S&L is played in its own 3D world, not the café: a sky, fog, its own lights, a ground with a clearing, scenery,
## screen-anchored framing pieces (corner trees, vines, the tree with a coiled snake), a hanging title sign, floating
## motes and falling leaves around a round table that turns slowly with the real board (SLBoard) on it.
## play(true) turns the landing into the game table: the table squares to the camera and stops, the sign, the coiled
## snake's tree and the decor pawns go, and the camera glides to the '3d' (50°) or 'top' view fitted to the board box.
##
## Everything is built in the web version's units under `_w` (scaled by K, table top at TableWorld.TT), so its numbers
## port one to one; the SLBoard (Godot units, 15-unit face) sits on the table in its own holder. SLScenes has its own
## Camera3D (46° vertical lens with a lens shift, as three.js setViewOffset) whose `environment` overrides the café's,
## so the café's WorldEnvironment needs no change: the app hides TableWorld, shows this and makes `camera` current.
## Scenes are built on first use; switching frees the previous one (the web disposes it too).

signal scene_built(id: String)

## The shop list (SL_SCENES): Jungle is free and always owned.
const LIST := [
	{id = "jungle", name = "Jungle Clearing", price = 0, desc = "The classic sunny jungle.", g = [Color("#c8ee9c"), Color("#6aa84a")]},
	{id = "frost", name = "Frosty Wonderland", price = 20000, desc = "Snowy pines, a frozen pond, lanterns, falling snow.", g = [Color("#eef8ff"), Color("#9fc4e6")]},
	{id = "candy", name = "Candy Kingdom", price = 22000, desc = "Lollipops, gumdrops and candy-cane ladders.", g = [Color("#ffe3f1"), Color("#f59ccb")]},
	{id = "desert", name = "Desert Temple", price = 25000, desc = "Sandstone ruins, palms, an oasis, golden trim.", g = [Color("#ffe4ad"), Color("#e9a35a")]},
	{id = "cloud", name = "Cloud Kingdom", price = 25000, desc = "Floating islands, rainbows, a pearl-white table.", g = [Color("#e3f3ff"), Color("#9fcfff")]},
	{id = "enchanted", name = "Enchanted Jungle", price = 25000, desc = "Glowing mushrooms, fireflies, golden snakes.", g = [Color("#8f6bb8"), Color("#2b4a5c")]},
]
const DEFAULT := "jungle"

const K := 15.0 / 4.8                    # web units -> Godot units (the board face is 4.8 there, 15 here)
const TT := -0.31                        # table top in Godot units (TableWorld.TT)
const GROUND := -3.75                    # web units, below the table top
const TABLE_R := 4.0
const SIGN_K := 0.5
const SURF := 0.366                      # web board surface height above the table top
const BOARD_HALF := 8.65 / K             # SLBoard's lip half-size, in web units
const FOV := 46.0
const LANDING_EL := 31.0
const PLAY_EL := 58.0                    # the match's 3D View: steep, so the far rows stay readable
const PLAY_FILL := 0.94                  # the board's share of the screen width in a match
const PAD_NEAR := (SLBoard.PAD_Z + SLBoard.PAD_D / 2.0 + 0.15) / K   # the start pad's near edge, in web units

const WOOD := {plank = "#a9693a", grain = Color(90 / 255.0, 45 / 255.0, 20 / 255.0), edge = "#7a4422", stroke = "#3a1a12", rope = "#c9a46a"}

## Per scene (index.html SCENES): sky gradient (top .. bottom), fog [colour, near, far], light [hemi sky, hemi ground,
## hemi intensity, sun colour, sun intensity, ambient], ground, clearing rgb, table [top, trim, roughness, metalness],
## board style (SLBoard.apply_style), sign style, the snake coiled on the table, motes [kind, colour, count, size],
## falling leaves / sprinkles, light beams.
const SCENES := {
	jungle = {
		sky = ["#9bd572", "#e8f6c0", "#b3e08a", "#6aa84a"], fog = ["#d6edb0", 20, 72], light = ["#fff6dc", "#4a8a36", 0.66, "#fff0c8", 0.8, 0.12],
		ground = "#76c150", clearing = [230, 200, 140], table = ["#b87a45", "#8a552c", 0.55, 0.0],
		board = {bands = ["#ffd2b0", "#ffc8c4", "#cfe9c2", "#ffe39a", "#cfe4f2"], cream = "#fff4e2", grout = "#e9c7a0", goal = "#ffd45c", star = "#f4a92a", num = "#7d4f61", num100 = "#b06d00", frame = "#fff4e6", frameR = 0.38, lip = "#f2b25c", rail = "#c47a3c", rung = "#f2b366"},
		sign = {plank = "#a9693a", grain = Color(90 / 255.0, 45 / 255.0, 20 / 255.0), edge = "#7a4422", stroke = "#3a1a12", rope = "#c9a46a", c1 = "#e5484d", c2 = "#f4c430", top = "vine", snake = ["#5cc84f", "#2f8f3a", "#fff0b8"]},
		table_snake = ["#ffb02e", "#e07a16", "#fff3c4"], motes = ["fly", "#fff3a0", 40, 0.45], fall = ["#7cc95a"], beams = Color(1.0, 250 / 255.0, 210 / 255.0, 0.55),
	},
	candy = {
		sky = ["#ff9fcf", "#ffe4f3", "#ffd0ea", "#f08cc0"], fog = ["#ffd9ee", 30, 95], light = ["#fff4fb", "#d86aa6", 0.72, "#fff2e6", 0.78, 0.14],
		ground = "#ffb6d8", clearing = [255, 240, 228], table = ["#ff9cc6", "#e0609e", 0.25, 0.05],
		board = {bands = ["#ffd1e8", "#d6efff", "#fff1a8", "#d8f5d0", "#e8dcff"], tiles = ["#ffc9df", "#ffd6ba", "#fff4e2", "#c2eed8"], marks = ["sprinkles", ["#ff6fae", "#5fd0b0", "#b58cff", "#3fc6c9", "#e5484d"]], cream = "#fffaf6", grout = "#f7c3da", goal = "#ffe066", star = "#ff7ab6", num = "#8a3f68", num100 = "#b0306f", frame = "#ffe6f2", frameR = 0.3, lip = "#ff8fc1",
			trim = {lip = ["stripes", "#e5484d", "#fff8fb"], corner = ["mint", "#e5484d", "#fff8fb"], mid = ["gumdrop", ["#5fd0b0", "#b58cff", "#3fc6c9", "#ff8fbf"]]},
			rail = "#e5484d", rung = "#7fdcbf", stripe = ["#e5484d", "#ffffff"], snakePattern = "stripes", snakes = ["#ff6fae", "#a77bf0", "#3fcf9f", "#ff7f6e", "#38c6c9", "#e5484d", "#c99bff", "#ff8fbf", "#2fbf8f", "#ff9a7a"]},
		sign = {plank = "#ff9ec7", grain = Color(200 / 255.0, 60 / 255.0, 120 / 255.0), edge = "#d9628f", stroke = "#8f2a5c", rope = "#ffffff", c1 = "#ffffff", c2 = "#ffe066", top = "cloud", snake = ["#7ad3ff", "#3f9fd8", "#fff6fb"]},
		table_snake = ["#b58cff", "#7c4ddb", "#fff3ff"], motes = ["fly", "#ffffff", 40, 0.35], fall = ["#ff6fae", "#7ad3ff", "#ffe066", "#9be38a"], beams = null,
	},
	desert = {
		sky = ["#ffb46b", "#ffe4ad", "#ffd38f", "#e9a35a"], fog = ["#f4d29c", 40, 130], light = ["#fff1d6", "#b8803e", 0.66, "#ffe0a8", 0.95, 0.12],
		ground = "#ddb173", clearing = [240, 214, 160], table = ["#7a4a2a", "#e3b04b", 0.5, 0.65],
		board = {bands = ["#f6d9a8", "#f2c6a0", "#e9dcb0", "#f7e3b9", "#efc9a0"], tiles = ["#fff5e2", "#f1d9ae", "#e7cd9f"], marks = ["glyphs", "#c4643a"], cream = "#fff3dc", grout = "#cf9f62", goal = "#ffd45c", star = "#c4643a", num = "#5e3b22", num100 = "#9a5a00", frame = "#e8cd9c", frameR = 0.6, lip = "#e0a83a", lipM = 0.6,
			trim = {lip = ["diamonds", "#d9a441", "#1f6f6a"], corner = ["sun", "#e0ad4a", "#1f6f6a"], mid = ["tile", ["#c4643a"]]},
			rail = "#a8693a", rung = "#e6bf83", snakePattern = "diamonds", snakes = ["#2fb3a6", "#2f9e5f", "#c9643c", "#c9a03f", "#1f7a78", "#3fc6b8", "#4aa36a", "#d4774a", "#b8913a", "#2a8f8a"]},
		sign = {plank = "#d9b27c", grain = Color(130 / 255.0, 80 / 255.0, 30 / 255.0), edge = "#a07a48", stroke = "#5a2e14", rope = "#c9a46a", c1 = "#c9532e", c2 = "#ffd56a", top = "none", snake = ["#d4a64a", "#8a5a2a", "#fff0c8"]},
		table_snake = ["#5fb3a0", "#2f7d6e", "#f6f0d8"], motes = ["fly", "#fff1c8", 34, 0.3], fall = null, beams = Color(1.0, 240 / 255.0, 200 / 255.0, 0.45),
	},
	frost = {
		sky = ["#a9d6ff", "#eef8ff", "#d4ecfc", "#9fc4e6"], fog = ["#e6f3fb", 32, 115], light = ["#eaf6ff", "#8fb6d2", 0.72, "#ffe4b8", 0.7, 0.16],
		ground = "#f4f9ff", clearing = [226, 240, 250], table = ["#dcebf5", "#9cc7e0", 0.3, 0.05],
		board = {bands = ["#d7ecff", "#dff5ee", "#e8e6ff", "#d9f2ff", "#eef3ff"], cream = "#ffffff", grout = "#bcd7ea", goal = "#ffd45c", star = "#59a8e0", num = "#2f4f73", num100 = "#9a5a00", frame = "#f3fbff", frameR = 0.25, lip = "#8cc8ea", rail = "#7fb0d0", rung = "#e3f4ff"},
		sign = {plank = "#b5835a", grain = Color(90 / 255.0, 50 / 255.0, 20 / 255.0), edge = "#7a5232", stroke = "#173a6b", rope = "#e6f0f7", c1 = "#3b7be0", c2 = "#ffffff", top = "snow", snake = ["#e5484d", "#ffffff", "#fff3f3"]},
		table_snake = ["#3fa7d6", "#ffffff", "#eaf8ff"], motes = ["snow", "#ffffff", 110, 0.32], fall = null, beams = null,
	},
	cloud = {
		sky = ["#78c4ff", "#cfeaff", "#ffe3f2", "#b6dcff"], fog = ["#e4f2ff", 40, 140], light = ["#ffffff", "#b8c9ff", 0.8, "#fff4e0", 0.7, 0.18],
		ground = null, clearing = null, table = ["#f6f1ea", "#e2d7f3", 0.22, 0.12],
		board = {bands = ["#ffe3ef", "#e1efff", "#fff3c9", "#e3f8e6", "#efe4ff"], cream = "#ffffff", grout = "#e6dcf5", goal = "#ffe07a", star = "#b48cff", num = "#5b4b8a", num100 = "#9a5a00", frame = "#ffffff", frameR = 0.22, frameM = 0.1, lip = "#c9b3ff", rail = "#f2a7cf", rung = "#ffffff"},
		sign = {plank = "#fbf7ff", grain = Color(160 / 255.0, 140 / 255.0, 220 / 255.0), edge = "#c9b3ff", stroke = "#4b3a8a", rope = "#ffffff", c1 = "#8a5cf0", c2 = "#ff8fc1", top = "cloud", snake = ["#ff9ad0", "#ffffff", "#fff2fa"]},
		table_snake = ["#7fd6ff", "#ffffff", "#f2fbff"], motes = ["fly", "#fff6c8", 40, 0.4], fall = null, beams = Color(1, 1, 1, 0.5),
	},
	enchanted = {
		sky = ["#3d2f7a", "#6a4fa8", "#8f6bb8", "#2b4a5c"], fog = ["#4a4a82", 18, 62], light = ["#c9b8ff", "#1f4a3a", 0.72, "#ffd9a0", 0.7, 0.12],
		ground = "#2f6b4f", clearing = [86, 150, 120], table = ["#5a3524", "#e3b04b", 0.35, 0.7],
		board = {bands = ["#cdeee4", "#e3d7fb", "#d6f0c8", "#fbe6b8", "#cfe3f7"], cream = "#fbf7ee", grout = "#b9a6d6", goal = "#ffd45c", star = "#7ef0c8", num = "#3d2f5c", num100 = "#9a5a00", frame = "#f7ecd6", frameR = 0.3, lip = "#e3b04b", lipM = 0.7, rail = "#c99a3a", railM = 0.5, rung = "#f4d58a"},
		sign = {plank = "#7a4a2e", grain = Color(40 / 255.0, 20 / 255.0, 10 / 255.0), edge = "#4e2c18", stroke = "#1d1240", rope = "#e3c47a", c1 = "#7ef0c8", c2 = "#ffd56a", top = "vine", vine = ["#2e7d5a", "#4fbf8a", "#2f9a6a"], snake = ["#f2c14e", "#b8862a", "#fff4d0"]},
		table_snake = ["#3fd0c0", "#1f8a80", "#e8fff8"], motes = ["fly", "#c8ff9a", 80, 0.6], fall = ["#7ef0c8"], beams = Color(200 / 255.0, 180 / 255.0, 1.0, 0.4),
	},
}

var camera: Camera3D
var env: Environment
var board: SLBoard
var current := ""                        # the scene on show
var mode := "landing"                    # landing | play
var view := "3d"                         # 3d | top (in a match)
var reduced_motion := false
var board_box := Rect2()                 # the match board box in UI pixels (empty: a default under the HUD)
var t := 0.0

var _w: Node3D                           # the current world, in web units (scaled by K)
var _table: Node3D
var _holder: Node3D                      # the SLBoard's place on the table (Godot units)
var _sign: Node3D
var _coil_tree: Node3D
var _decor := []
var _sway := []
var _heads := []
var _tongues := []
var _leaves := []
var _beams := []
var _bobs := []
var _anchors := []
var _motes: MultiMeshInstance3D
var _mote_seeds := []
var _mote_kind := "fly"
var _sky: MeshInstance3D
var _sky_tex: GradientTexture2D
var _lights := []
var _sway_on := true
var _building := false
var _vp := Vector2.ZERO
var _landing := {}                       # camera goals: {pos, look, up, ox, oy} in web units / UI pixels
var _play_cache := {}
var _cam := {}                           # the eased camera
var _hf := 0.2
var _vf := 0.4
var _baker: TexBaker
var rng := RandomNumberGenerator.new()

static var _mats := {}
static var _skins := {}
static var _meshes := {}


func _init() -> void:
	name = "SLScenes"

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "SLCamera"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.projection = Camera3D.PROJECTION_FRUSTUM
	add_child(camera)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.0
	env.glow_enabled = false
	camera.environment = env
	# the sky: three.js draws scene.background as a screen-filling gradient; here an unlit quad on the far plane
	_sky_tex = GradientTexture2D.new()
	_sky_tex.width = 4
	_sky_tex.height = 256
	_sky_tex.fill_from = Vector2(0.5, 0.0)
	_sky_tex.fill_to = Vector2(0.5, 1.0)
	_sky_tex.gradient = Gradient.new()
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = _sky_tex
	sm.disable_fog = true
	sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_sky = MeshInstance3D.new()
	_sky.mesh = QuadMesh.new()
	_sky.material_override = sm
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky.extra_cull_margin = 16384
	camera.add_child(_sky)
	_table = Node3D.new()
	_table.name = "Table"
	_table.set_meta("dyn", true)            # it turns: never merged into the static world
	_holder = Node3D.new()
	_holder.name = "BoardHolder"
	_holder.position = Vector3(0, -TT / K, 0)
	_holder.scale = Vector3.ONE / K
	_holder.set_meta("dyn", true)
	_table.add_child(_holder)
	get_viewport().size_changed.connect(func(): _vp = Vector2.ZERO)


# =====================================================================================================================
# Public API
# =====================================================================================================================

static func info(id: String) -> Dictionary:
	for s: Dictionary in LIST:
		if s.id == id:
			return s
	return {}

## Put the S&L board on this world's table (the board keeps its own pawns and animations).
func attach_board(b: SLBoard) -> void:
	board = b
	if b.get_parent():
		b.get_parent().remove_child(b)
	_holder.add_child(b)
	b.position = Vector3.ZERO
	b.rotation = Vector3.ZERO
	b.scale = Vector3.ONE

## Build scene `id` (first use) and show it, with the board in its style. Coroutine.
func build(baker: TexBaker, id: String) -> void:
	await set_scene(baker, id)

## Show scene `id`, building it when it isn't the one on show. Coroutine; safe to call again while it builds.
func set_scene(baker: TexBaker, id: String) -> void:
	if not SCENES.has(id):
		id = DEFAULT
	_baker = baker
	while _building:
		await get_tree().process_frame
	if id == current and _w:
		return
	_building = true
	await _build_world(id)
	_building = false
	scene_built.emit(id)

## Landing (false) or the match (true), in the given camera view ("3d" / "top"; "" keeps the current one).
func play(on: bool, v := "") -> void:
	mode = "play" if on else "landing"
	if v != "":
		view = "top" if v == "top" else "3d"
	_play_cache = {}
	if not on and board:
		board.set_current(-1)

func set_view(v: String) -> void:
	view = "top" if v == "top" else "3d"
	_play_cache = {}

## The match board box (index.html #slBoard), in UI pixels: the board is fitted into it.
func set_board_box(r: Rect2) -> void:
	board_box = r
	_play_cache = {}

## Animation step (the node also animates itself in _process while visible).
func tick(dt: float) -> void:
	_animate(dt)

## Jump the camera to its goal (previews, screenshots).
func snap_camera() -> void:
	_fit_if_needed()
	_apply_cam(_goal(), 1.0)


# ---------- purchases (index.html buyScene / useScene) over Save.profile.scenes / .scene ----------

static func owned_ids() -> Array:
	var p := Catalog.profile()
	var v = p.get("scenes", [])
	var out := [DEFAULT]
	if v is Array:
		for id in v:
			if not info(str(id)).is_empty() and not out.has(str(id)):
				out.append(str(id))
	return out

static func owns_scene(id: String) -> bool:
	if info(id).is_empty():
		return false
	return id == DEFAULT or owned_ids().has(id)

## The equipped scene (only an owned one counts; Jungle otherwise).
static func scene_in_use() -> String:
	var s := str(Catalog.profile().get("scene", DEFAULT))
	return s if owns_scene(s) else DEFAULT

## Owned scenes in catalogue order.
static func owned_scenes() -> Array:
	return LIST.filter(func(s: Dictionary) -> bool: return owns_scene(s.id))

## Buys a scene (and puts it in use unless equip is false). "" when bought, else the reason (nothing changed then).
static func buy_scene(id: String, equip := true) -> String:
	var s := info(id)
	if s.is_empty():
		return "That scene isn’t in the shop."
	if owns_scene(id):
		return "You already own %s." % s.name
	var price := int(s.price)
	if Catalog.coins() < price:
		return Catalog.need_text(price - Catalog.coins())
	var ok := Catalog._commit(func(p: Dictionary) -> void:
		p.coins = int(p.get("coins", 0)) - price
		var owned := owned_ids()
		owned.append(id)
		p.scenes = owned
		if equip:
			p.scene = id)
	return "" if ok else Catalog.SAVE_FAILED

## Puts an owned scene in use. False when it isn't owned (or the save failed).
static func equip_scene(id: String) -> bool:
	if not owns_scene(id):
		return false
	var p := Catalog.profile()
	if str(p.get("scene", "")) == id and p.get("scenes") is Array:
		return true
	return Catalog._commit(func(q: Dictionary) -> void:
		q.scenes = owned_ids()
		q.scene = id)


# =====================================================================================================================
# World building
# =====================================================================================================================

func _build_world(id: String) -> void:
	var T: Dictionary = SCENES[id]
	rng.seed = hash(id) & 0x7fffffff
	if _w:
		if _table.get_parent():
			_table.get_parent().remove_child(_table)
		for c in _table.get_children():
			if c != _holder:
				_table.remove_child(c)
				c.queue_free()
		remove_child(_w)
		_w.queue_free()
	for l in _lights:
		l.queue_free()
	_lights.clear()
	for a in [_sway, _heads, _tongues, _leaves, _beams, _bobs, _anchors, _decor]:
		a.clear()
	_sign = null
	_coil_tree = null
	_motes = null
	_play_cache = {}
	_cam = {}
	_vp = Vector2.ZERO
	_w = Node3D.new()
	_w.name = "World_" + id
	_w.position = Vector3(0, TT, 0)
	_w.scale = Vector3.ONE * K
	add_child(_w)
	current = id
	_apply_env(T)
	# ground, a soft-edged clearing and a soft shadow under the table
	if T.ground != null:
		_add(_circle(90, 48), _lam(T.ground), 0, GROUND, 0, null, {rx = -PI / 2})
	if T.clearing != null:
		var cl: Array = T.clearing
		var c0 := Color8(cl[0], cl[1], cl[2])
		var c1 := Color8(cl[0] - 8, cl[1] - 8, cl[2] - 8)
		var gt := _radial([0.0, 0.62, 1.0], [c0, c1, Color(c1, 0.0)])
		var m := _lam_tex(gt)
		m.render_priority = 0
		_add(QuadMesh.new(), m, 0, GROUND + 0.02, 0, null, {rx = -PI / 2, s = 18.0})
	var blob := _radial([0.03, 1.0], [Color(40 / 255.0, 30 / 255.0, 10 / 255.0, 0.45), Color(40 / 255.0, 30 / 255.0, 10 / 255.0, 0.0)])
	var bm := _basic_tex(blob)
	bm.render_priority = 1
	_add(QuadMesh.new(), bm, 0, GROUND + 0.04, 0, null, {rx = -PI / 2, s = 10.0})

	# the table: round top in the scene's finish, trim, one leg, a base, the board and two pawns; it turns slowly
	_w.add_child(_table)
	_table.rotation = Vector3.ZERO
	var tb: Array = T.table
	var top_m := _std(tb[0], tb[2])
	var metal: float = tb[3]
	var trim_m := _std(tb[1], 0.35 if metal > 0 else 0.6, metal)
	_add(MeshKit.cylinder(TABLE_R, TABLE_R, 0.36, 64), top_m, 0, -0.18, 0, _table)
	_add(_torus(TABLE_R, 0.14, 10, 64), trim_m, 0, -0.18, 0, _table, {rx = PI / 2})
	_add(MeshKit.cylinder(0.45, 0.6, 3.1, 20), top_m if metal > 0 else trim_m, 0, -1.9, 0, _table)
	_add(MeshKit.cylinder(1.7, 1.9, 0.26, 32), trim_m, 0, GROUND + 0.14, 0, _table)
	if board:
		await board.apply_style(_baker, T.board)
	for d in [[-3.2, -1.1, "#e5484d"], [-2.95, -1.95, "#3b7be0"]]:
		var pw := _pawn(_table, d[0], d[1], d[2])
		_dyn(pw)
		_decor.append(pw)
	# a little friendly snake coiled on the table behind the board's top-right corner: never over a square
	var tcoil := []
	for k in 17:
		var a := k * 0.62
		var r := 0.55 - k * 0.018
		tcoil.append(Vector3(cos(a) * r, 0.1 + k * 0.008, sin(a) * r))
	tcoil.append(Vector3(0.12, 0.42, 0.1))
	tcoil.append(Vector3(0.05, 0.8, 0.3))
	var tsn := Node3D.new()
	tsn.position = Vector3(3.12, 0, -1.8)
	_table.add_child(tsn)
	_dyn(tsn)
	_decor.append(tsn)                     # landing only: in a match it would sit at the board's corner
	var ts: Array = T.table_snake
	await _snake(tcoil, 0.11, ts[0], ts[1], ts[2], Vector3(-0.4, -0.15, 1), tsn)
	_merge(_table)

	match id:
		"jungle": await _jungle_world()
		"candy": await _candy_world()
		"desert": await _desert_world()
		"frost": await _frost_world()
		"cloud": await _cloud_world()
		"enchanted": await _enchanted_world()
	_sign = await _make_sign(T.sign)
	_w.add_child(_sign)
	_anchor(_sign, 0, 0.62, SIGN_K, false)

	# light beams, floating motes (fireflies / sparkles / snow), a few falling leaves or sprinkles
	if T.beams != null:
		var bc: Color = T.beams
		var beam_tex := GradientTexture2D.new()
		beam_tex.width = 8
		beam_tex.height = 128
		beam_tex.fill_from = Vector2(0.5, 0)
		beam_tex.fill_to = Vector2(0.5, 1)
		beam_tex.gradient = Gradient.new()
		beam_tex.gradient.set_color(0, bc)
		beam_tex.gradient.set_color(1, Color(1, 1, 1, 0))
		var bi := 0
		for b in [[-5, -8, -0.35], [3, -10, -0.25], [8, -6, -0.4]]:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.albedo_texture = beam_tex
			m.albedo_color = Color(1, 1, 1, 0.5)
			var q := QuadMesh.new()
			q.size = Vector2(3, 26)
			var mi := _add(q, m, b[0], 6, b[1], null, {rz = b[2]})
			_beams.append({m = m, ph = bi * 2.0})
			bi += 1
	_build_motes(T.motes)
	if T.fall != null:
		var fc: Array = T.fall
		for i in 10:
			var lm := _add(_leaf_geo(0.42, 0.12, 0.15), _leaf_mat(fc[i % fc.size()]), (rng.randf() - 0.5) * 14, rng.randf() * 12, -2 - rng.randf() * 6)
			_dyn(lm)
			_leaves.append({m = lm, sp = 0.4 + rng.randf() * 0.5, ph = rng.randf() * 6})
	_merge(_w)
	_fit_if_needed()
	_apply_cam(_goal(), 1.0)

## The scene's sky, fog and lights. three.js hemisphere light = flat ambient (sky / ground mean) plus a light from
## above in (sky - ground) / 2 and a negative one from below in the same colour: exactly sky up, ground down.
func _apply_env(T: Dictionary) -> void:
	var sky: Array = T.sky
	var g := _sky_tex.gradient
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.75, 1.0])
	g.colors = PackedColorArray([Color(sky[0]), Color(sky[1]), Color(sky[2]), Color(sky[3])])
	var fog: Array = T.fog
	env.background_color = Color(fog[0])
	env.fog_light_color = Color(fog[0])
	env.fog_depth_begin = float(fog[1]) * K
	env.fog_depth_end = float(fog[2]) * K
	var L: Array = T.light
	var hs := Color(L[0]).srgb_to_linear()
	var hg := Color(L[1]).srgb_to_linear()
	var hi: float = L[2]
	var mean := (hs + hg) * 0.5 * hi
	var amb := Color(mean.r + L[5], mean.g + L[5], mean.b + L[5])
	var mx := maxf(amb.r, maxf(amb.g, amb.b))
	var e := maxf(1.0, mx)
	env.ambient_light_color = Color(amb.r / e, amb.g / e, amb.b / e).linear_to_srgb()
	env.ambient_light_energy = e
	var d := (hs - hg) * 0.5 * hi
	var dm := maxf(0.0001, maxf(d.r, maxf(d.g, d.b)))
	var dcol := Color(maxf(d.r, 0) / dm, maxf(d.g, 0) / dm, maxf(d.b, 0) / dm).linear_to_srgb()
	for down in [false, true]:
		var hl := DirectionalLight3D.new()
		hl.light_color = dcol
		hl.light_energy = dm
		hl.light_negative = down
		hl.light_specular = 0.0
		hl.shadow_enabled = false
		hl.rotation = Vector3(PI / 2 if down else -PI / 2, 0, 0)
		add_child(hl)
		_lights.append(hl)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(L[3])
	sun.light_energy = L[4]
	sun.shadow_enabled = false
	add_child(sun)
	sun.basis = Basis.looking_at(-Vector3(7, 16, 10).normalized(), Vector3.UP)
	_lights.append(sun)


# ---------- materials (cached by colour) ----------

static func _col(c) -> Color:
	return c if c is Color else Color(str(c))

## three.js MeshLambertMaterial: matte, no highlight.
static func _lam(c, cull := true) -> StandardMaterial3D:
	var key := "lam|%s|%s" % [_col(c).to_html(), cull]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = _col(c)
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if not cull:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m

## three.js MeshStandardMaterial: the glossy toy look (snakes, pawns, table, candy).
static func _std(c, r := 0.45, metal := 0.0) -> StandardMaterial3D:
	var key := "std|%s|%s|%s" % [_col(c).to_html(), r, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = _col(c)
	m.roughness = r
	m.metallic = metal
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	_mats[key] = m
	return m

## Lanterns, mushrooms, berries: a standard material glowing in its own colour.
static func _glow(c, i := 1.0) -> StandardMaterial3D:
	var key := "glow|%s|%s" % [_col(c).to_html(), i]
	if _mats.has(key):
		return _mats[key]
	var m := _std(c, 0.5).duplicate() as StandardMaterial3D
	m.emission_enabled = true
	m.emission = _col(c)
	m.emission_energy_multiplier = i
	_mats[key] = m
	return m

static func _leaf_mat(c) -> StandardMaterial3D:
	return _lam(c, false)

static func _lam_tex(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m

static func _basic_tex(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m

static func _radial(offsets: Array, colors: Array, px := 128) -> GradientTexture2D:
	var gt := GradientTexture2D.new()
	gt.width = px
	gt.height = px
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	gt.gradient = g
	return gt


# ---------- node helpers (three.js add(): position, uniform or xyz scale, XYZ Euler rotation) ----------

func _add(mesh: Mesh, m: Material, x: float, y: float, z: float, parent: Node3D = null, o := {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(x, y, z)
	mi.rotation_order = EULER_ORDER_XYZ
	if o.has("s"):
		var s = o.s
		mi.scale = Vector3(s[0], s[1], s[2]) if s is Array else Vector3.ONE * float(s)
	mi.rotation = Vector3(o.get("rx", 0.0), o.get("ry", 0.0), o.get("rz", 0.0))
	(parent if parent else _w).add_child(mi)
	return mi

func _group(parent: Node3D, x: float, y: float, z: float) -> Node3D:
	var g := Node3D.new()
	g.rotation_order = EULER_ORDER_XYZ
	g.position = Vector3(x, y, z)
	(parent if parent else _w).add_child(g)
	return g

static func _dyn(n: Node3D) -> Node3D:
	n.set_meta("dyn", true)
	return n

## A cylinder from a to b of radius r.
func _rod(a: Vector3, b: Vector3, r: float, m: Material, parent: Node3D) -> MeshInstance3D:
	var d := b - a
	var mi := _add(_cyl(), m, (a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2, parent)
	var dir := d.normalized()
	var q := Quaternion(Vector3.UP, dir) if dir.dot(Vector3.UP) > -0.9999 else Quaternion(Vector3.RIGHT, PI)
	mi.basis = Basis(q).scaled_local(Vector3(r, d.length(), r))
	return mi

## A rail of short alternating pieces (candy-cane ladders).
func _striped_rod(a: Vector3, b: Vector3, r: float, cols: Array, parent: Node3D) -> void:
	var L := a.distance_to(b)
	var n := maxi(2, roundi(L / 0.09))
	for i in n:
		_rod(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), r, _std(cols[i % cols.size()], 0.3), parent)

static func _sph() -> SphereMesh:
	return MeshKit.sphere(1.0, 24, 16)

static func _cyl() -> CylinderMesh:
	return MeshKit.cylinder(1.0, 1.0, 1.0, 14)

static func _cone(r: float, h: float, segs: int) -> CylinderMesh:
	return MeshKit.cylinder(0.0, r, h, segs)


# ---------- procedural meshes (three.js geometry conventions: circles / tori in the XY plane) ----------

## Triangles from index triples, each wound so its front (Godot: clockwise) faces along the vertex normals.
static func _mesh(pos: PackedVector3Array, nor: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var out := PackedInt32Array()
	out.resize(idx.size())
	for i in range(0, idx.size(), 3):
		var a := idx[i]
		var b := idx[i + 1]
		var c := idx[i + 2]
		var n := nor[a] + nor[b] + nor[c]
		if (pos[c] - pos[a]).cross(pos[b] - pos[a]).dot(n) < 0:
			var tmp := b; b = c; c = tmp
		out[i] = a; out[i + 1] = b; out[i + 2] = c
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	if uv.size() == pos.size():
		arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = out
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

static func _circle(r: float, segs: int) -> ArrayMesh:
	return _ring(0.0, r, segs)

static func _ring(r0: float, r1: float, segs: int) -> ArrayMesh:
	var key := "ring|%s|%s|%d" % [r0, r1, segs]
	if _meshes.has(key):
		return _meshes[key]
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in segs + 1:
		var a := TAU * k / segs
		for r in [r0, r1]:
			pos.append(Vector3(cos(a) * r, sin(a) * r, 0))
			nor.append(Vector3.BACK)
			uv.append(Vector2(0.5 + cos(a) * r / r1 * 0.5, 0.5 - sin(a) * r / r1 * 0.5))
	for k in segs:
		var i := k * 2
		idx.append_array([i, i + 1, i + 3, i, i + 3, i + 2])
	var m := _mesh(pos, nor, uv, idx)
	_meshes[key] = m
	return m

## three.js TorusGeometry(radius, tube, radialSegments, tubularSegments, arc): in the XY plane round the z axis.
static func _torus(R: float, r: float, radial: int, tubular: int, arc := TAU) -> ArrayMesh:
	var key := "torus|%s|%s|%d|%d|%s" % [R, r, radial, tubular, arc]
	if _meshes.has(key):
		return _meshes[key]
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in radial + 1:
		for i in tubular + 1:
			var u := float(i) / tubular * arc
			var v := float(j) / radial * TAU
			var p := Vector3((R + r * cos(v)) * cos(u), (R + r * cos(v)) * sin(u), r * sin(v))
			pos.append(p)
			nor.append((p - Vector3(R * cos(u), R * sin(u), 0)).normalized())
	for j in range(1, radial + 1):
		for i in range(1, tubular + 1):
			var a := (tubular + 1) * j + i - 1
			var b := (tubular + 1) * (j - 1) + i - 1
			var c := (tubular + 1) * (j - 1) + i
			var d := (tubular + 1) * j + i
			idx.append_array([a, b, d, b, c, d])
	var m := _mesh(pos, nor, PackedVector2Array(), idx)
	_meshes[key] = m
	return m

## A leaf lying along +x: pointed tip, widest at 40%, folded along the midrib, drooping towards the tip.
static func _leaf_geo(len: float, wid: float, droop: float) -> ArrayMesh:
	var key := "leaf|%s|%s|%s" % [len, wid, droop]
	if _meshes.has(key):
		return _meshes[key]
	var n := 10
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for i in n + 1:
		var f := float(i) / n
		var l := f * len
		var hw := wid * sin(PI * pow(f, 0.75))
		var y := -droop * f * f * len
		pts.append([Vector3(l, y + hw * 0.35, -hw), Vector3(l, y, 0), Vector3(l, y + hw * 0.35, hw)])
	for p in pts:
		for q in p:
			st.add_vertex(q)
	for i in n:
		var a := i * 3
		var b := a + 3
		for tri in [[a, b, a + 1], [a + 1, b, b + 1], [a + 1, b + 1, a + 2], [a + 2, b + 1, b + 2]]:
			st.add_index(tri[0]); st.add_index(tri[2]); st.add_index(tri[1])
	st.generate_normals()
	var m := st.commit()
	_meshes[key] = m
	return m

## A tube whose radius follows rf(u) (u: 0 at the tail .. 1 at the neck). The seam runs along the back and the
## texture's v = .5 along the belly, so a painted belly stays underneath.
static func _taper(curve: CRCurve, n: int, radial: int, rf: Callable) -> ArrayMesh:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var prev := Vector3.ZERO
	for i in n + 1:
		var u := float(i) / n
		var P := curve.point_at(u)
		var T := curve.tangent_at(u)
		var U := Vector3.UP - T * T.dot(Vector3.UP)
		var N: Vector3
		if i > 0:
			N = (prev - T * T.dot(prev)).normalized()
			if U.length_squared() > 0.04:
				N = N.lerp(U.normalized(), 0.25).normalized()
		else:
			N = U.normalized() if U.length_squared() > 0.001 else Vector3(0, 0, 1)
		prev = N
		var B := T.cross(N)
		var r: float = rf.call(u)
		for j in radial + 1:
			var a := float(j) / radial * TAU
			var d := N * cos(a) + B * sin(a)
			pos.append(P + d * r)
			nor.append(d)
			uv.append(Vector2(u, float(j) / radial))
	for i in n:
		for j in radial:
			var a := i * (radial + 1) + j
			var b := a + radial + 1
			idx.append_array([a, a + 1, b, b, a + 1, b + 1])
	return _mesh(pos, nor, uv, idx)

## three.js CatmullRomCurve3 (centripetal), with getPointAt's arc-length parameter.
class CRCurve extends RefCounted:
	var pts: Array
	var lens := PackedFloat32Array()
	const DIV := 200

	func _init(points: Array) -> void:
		pts = points
		var last := point(0.0)
		lens.append(0.0)
		for i in range(1, DIV + 1):
			var p := point(float(i) / DIV)
			lens.append(lens[i - 1] + p.distance_to(last))
			last = p

	func length() -> float:
		return lens[DIV]

	func point(tt: float) -> Vector3:
		var l := pts.size()
		var p := (l - 1) * tt
		var ip := int(floor(p))
		var w := p - ip
		if w == 0.0 and ip == l - 1:
			ip = l - 2
			w = 1.0
		var p0: Vector3 = pts[ip - 1] if ip > 0 else (pts[0] as Vector3) * 2.0 - pts[1]
		var p1: Vector3 = pts[ip % l]
		var p2: Vector3 = pts[(ip + 1) % l]
		var p3: Vector3 = pts[ip + 2] if ip + 2 < l else (pts[l - 1] as Vector3) * 2.0 - pts[l - 2]
		var dt0 := pow(p0.distance_squared_to(p1), 0.25)
		var dt1 := pow(p1.distance_squared_to(p2), 0.25)
		var dt2 := pow(p2.distance_squared_to(p3), 0.25)
		if dt1 < 1e-4: dt1 = 1.0
		if dt0 < 1e-4: dt0 = dt1
		if dt2 < 1e-4: dt2 = dt1
		var t1 := ((p1 - p0) / dt0 - (p2 - p0) / (dt0 + dt1) + (p2 - p1) / dt1) * dt1
		var t2 := ((p2 - p1) / dt1 - (p3 - p1) / (dt1 + dt2) + (p3 - p2) / dt2) * dt1
		var c2 := -3.0 * p1 + 3.0 * p2 - 2.0 * t1 - t2
		var c3 := 2.0 * p1 - 2.0 * p2 + t1 + t2
		return p1 + t1 * w + c2 * w * w + c3 * w * w * w

	func u_to_t(u: float) -> float:
		var target := u * lens[DIV]
		var lo := 0
		var hi := DIV
		while lo < hi - 1:
			var mid := (lo + hi) / 2
			if lens[mid] < target:
				lo = mid
			else:
				hi = mid
		var seg := lens[hi] - lens[lo]
		var f := (target - lens[lo]) / seg if seg > 0 else 0.0
		return (lo + f) / DIV

	func point_at(u: float) -> Vector3:
		return point(u_to_t(u))

	func tangent_at(u: float) -> Vector3:
		var tt := u_to_t(u)
		var a := clampf(tt - 0.0001, 0.0, 1.0)
		var b := clampf(tt + 0.0001, 0.0, 1.0)
		return (point(b) - point(a)).normalized()


# =====================================================================================================================
# Props (index.html: canopy, tree, palm, bush, fern, vine, snake, ladderProp, lollipop, ...)
# =====================================================================================================================

func _canopy(parent: Node3D, x: float, y: float, z: float, r: float, cols: Array) -> Node3D:
	var g := _group(parent, x, y, z)
	var a = cols[0]
	var b = cols[1] if cols.size() > 1 else a
	var top = cols[2] if cols.size() > 2 else a
	_add(_sph(), _lam(a), 0, 0, 0, g, {s = [r, r * 0.82, r]})
	_add(_sph(), _lam(b), r * 0.78, -r * 0.28, r * 0.12, g, {s = r * 0.66})
	_add(_sph(), _lam(b), -r * 0.8, -r * 0.25, -r * 0.05, g, {s = r * 0.7})
	_add(_sph(), _lam(top), r * 0.1, r * 0.42, r * 0.22, g, {s = r * 0.55})
	if _sway_on:
		_sway.append({g = _dyn(g), ph = rng.randf() * 6, amp = 0.02 + rng.randf() * 0.015})
	return g

func _tree(x: float, z: float, h: float, r: float, cols: Array, bark = "#7a4a2a") -> Node3D:
	var g := _group(_w, x, GROUND, z)
	_add(MeshKit.cylinder(r * 0.6, r, h, 16), _lam(bark), 0, h / 2, 0, g)
	_add(MeshKit.cylinder(r, r * 1.45, r * 0.8, 16), _lam(bark), 0, r * 0.4, 0, g)
	_canopy(g, 0, h + r * 0.9, 0, r * 3.1, cols)
	return g

func _palm(x: float, z: float, h: float, lean: float, parent: Node3D = null) -> Node3D:
	var g := _group(parent if parent else _w, x, GROUND, z)
	g.rotation.z = lean
	var seg := 8
	var bend := func(k: float) -> float: return sin(k / seg * 1.3) * 0.6
	for k in seg:
		_add(MeshKit.cylinder(0.3 - k * 0.018, 0.34 - k * 0.018, h / seg * 1.02, 12), _lam("#8f6038" if k % 2 else "#a56f42"), bend.call(k + 0.5), h / seg * (k + 0.5), 0, g)
	var top := _group(g, bend.call(float(seg)), h, 0)
	for k in 8:
		var f := _group(top, 0, 0, 0)
		f.rotation.y = k / 8.0 * TAU + 0.2
		_add(_leaf_geo(3.4, 0.62, 0.5), _leaf_mat("#3f9a3a" if k % 2 else "#5cb84a"), 0, 0, 0, f, {rz = 0.32})
	for c in [[0.25, 0], [-0.15, 0.22], [-0.12, -0.22]]:
		_add(_sph(), _lam("#7a4a2a"), c[0], -0.25, c[1], top, {s = 0.2})
	if _sway_on:
		_sway.append({g = _dyn(top), ph = rng.randf() * 6, amp = 0.04})
	return g

func _bush(parent: Node3D, x: float, z: float, s: float, cols: Array, flowers = null) -> Node3D:
	var g := _group(parent, x, GROUND, z)
	var a = cols[0]
	var b = cols[1] if cols.size() > 1 else a
	_add(_sph(), _lam(a), 0, s * 0.5, 0, g, {s = [s, s * 0.78, s * 0.9]})
	_add(_sph(), _lam(b), s * 0.82, s * 0.32, s * 0.15, g, {s = s * 0.62})
	_add(_sph(), _lam(b), -s * 0.85, s * 0.3, s * 0.05, g, {s = s * 0.66})
	if flowers != null:
		var i := 0
		for f in [[-0.35, 0.95, 0.55], [0.4, 0.85, 0.6], [0.95, 0.55, 0.45]]:
			_add(_sph(), _lam(flowers[i % flowers.size()]), f[0] * s, f[1] * s, f[2] * s, g, {s = s * 0.13})
			i += 1
	return g

func _fern(parent: Node3D, x: float, z: float, s: float, col) -> Node3D:
	var g := _group(parent, x, GROUND, z)
	for k in 7:
		var f := _group(g, 0, 0, 0)
		f.rotation.y = k / 7.0 * TAU
		_add(_leaf_geo(s * 1.3, s * 0.26, 0.55), _leaf_mat(col if k % 2 else "#3f9a3a"), 0, s * 0.05, 0, f, {rz = 0.75})
	if _sway_on:
		_sway.append({g = _dyn(g), ph = rng.randf() * 6, amp = 0.03})
	return g

func _vine(from: Vector3, to: Vector3, sag: float, parent: Node3D, cols := ["#3f8f3a", "#5cb84a", "#3f9a3a"], berry = null) -> void:
	var mid := from.lerp(to, 0.5)
	mid.y -= sag
	var q := from.lerp(mid, 0.5)
	q.y = from.y - sag * 0.6
	var curve := CRCurve.new([from, q, mid, to])
	_add(_taper(curve, 40, 8, func(_u: float) -> float: return 0.06), _lam(cols[0]), 0, 0, 0, parent)
	for k in range(1, 10):
		var p := curve.point(k / 10.0)
		var f := _group(parent, p.x, p.y, p.z)
		f.rotation = Vector3(0, k * 2.1, 0)
		_add(_leaf_geo(0.55, 0.16, 0.4), _leaf_mat(cols[1] if k % 2 else cols[2]), 0, 0, 0, f, {rz = -0.9})
		if berry != null and k % 2:
			_add(_sph(), _glow(berry, 0.9), 0, -0.18, 0.12, f, {s = 0.09})

## The snake's skin (index.html snakeSkin): body colour, spots along the back and the sides, a pale scaled belly.
func _skin(col, spot, belly) -> Texture2D:
	var key := "%s|%s|%s" % [col, spot, belly]
	if _skins.has(key):
		return _skins[key]
	var tex: Texture2D = await _baker.bake(Vector2i(256, 128), func(c: Control):
		var w := c.size.x
		var h := c.size.y
		c.draw_rect(Rect2(0, 0, w, h), _col(col))
		for i in 4:
			var x := 32.0 + i * 64
			for y in [0.0, h]:
				c.draw_colored_polygon(_ellipse(Vector2(x, y), 17, 20), _col(spot))
			for y in [h * 0.22, h * 0.78]:
				c.draw_colored_polygon(_ellipse(Vector2(x + 32, y), 6, 7), _col(spot))
		c.draw_rect(Rect2(0, h * 0.37, w, h * 0.26), _col(belly))
		var x2 := 8.0
		while x2 < w:
			c.draw_rect(Rect2(x2, h * 0.37, 2, h * 0.26), Color(120 / 255.0, 80 / 255.0, 40 / 255.0, 0.12))
			x2 += 16)
	_skins[key] = tex
	return tex

static func _ellipse(c: Vector2, rx: float, ry: float, n := 28) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k in n:
		var a := TAU * k / n
		p.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return p

func _snake_head(head: Node3D, R: float, col, belly) -> void:
	_add(_sph(), _std(col, 0.4), 0, R * 0.25, R * 0.75, head, {s = [R * 1.3, R * 0.95, R * 1.6]})
	_add(_sph(), _std(belly, 0.5), 0, -R * 0.24, R * 0.95, head, {s = [R * 0.95, R * 0.42, R * 1.1]})
	for s in [-1.0, 1.0]:
		_add(_sph(), _std("#ffffff", 0.25), s * R * 0.56, R * 0.92, R * 1.15, head, {s = R * 0.5})
		_add(_sph(), _std("#2a1d24", 0.2), s * R * 0.58, R * 0.97, R * 1.55, head, {s = [R * 0.28, R * 0.3, R * 0.16]})
		_add(_sph(), _std("#ffffff", 0.2), s * R * 0.5, R * 1.1, R * 1.68, head, {s = R * 0.08})
		_add(_sph(), _lam("#ff9fb0"), s * R * 0.78, R * 0.08, R * 1.95, head, {s = [R * 0.22, R * 0.13, R * 0.08], ry = s * 0.6})
		_add(_sph(), _std("#3a2230", 0.4), s * R * 0.18, R * 0.48, R * 2.22, head, {s = R * 0.05})
	_add(_torus(R * 0.38, R * 0.05, 6, 18, 2.0), _std("#6a2a32", 0.4), 0, R * 0.2, R * 2.18, head, {rz = -PI / 2 - 1})

## The friendly cartoon snake: a tapered glossy body with a painted back pattern and pale belly, and a rounded head
## with big eyes, a smile, rosy cheeks and a flicking tongue; head at the end of the path, looking along `look`.
func _snake(points: Array, R: float, col, spot, belly, look: Vector3, parent: Node3D = null) -> Node3D:
	var g := _group(parent if parent else _w, 0, 0, 0)
	var curve := CRCurve.new(points)
	var L := curve.length()
	var m := StandardMaterial3D.new()
	m.albedo_texture = await _skin(col, spot, belly)
	m.roughness = 0.42
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.uv1_scale = Vector3(maxf(1, roundf(L / (R * 8))), 1, 1)
	var rf := func(u: float) -> float:
		if u < 0.35:
			return R * (0.14 + 0.86 * sin(u / 0.35 * PI / 2))
		if u > 0.9:
			return R * (1.0 - (u - 0.9) * 1.6)
		return R
	_add(_taper(curve, maxi(60, roundi(L * 12)), 16, rf), m, 0, 0, 0, g)
	var p0: Vector3 = points[0]
	_add(_sph(), _std(col, 0.42), p0.x, p0.y, p0.z, g, {s = R * 0.14})
	var end := curve.point_at(1.0)
	var aim := _group(g, end.x, end.y, end.z)
	aim.basis = Basis.looking_at(-look.normalized(), Vector3.UP)
	var head := _group(aim, 0, 0, 0)
	_snake_head(head, R * 0.95, col, belly)
	var tongue := _group(head, 0, -R * 0.05, R * 2.15)
	var red := _lam("#e5484d")
	var bx := BoxMesh.new()
	bx.size = Vector3(R * 0.14, R * 0.05, R * 0.9)
	_add(bx, red, 0, 0, R * 0.4, tongue)
	var fork := BoxMesh.new()
	fork.size = Vector3(R * 0.1, R * 0.05, R * 0.4)
	for s in [-1.0, 1.0]:
		_add(fork, red, s * R * 0.1, 0, R * 0.95, tongue, {ry = s * 0.5})
	_dyn(head)
	_heads.append({head = head, base = head.position, ph = rng.randf() * 6, amp = R * 0.25})
	_tongues.append({g = tongue, ph = rng.randf() * 6})
	return g

func _ladder_prop(x: float, z: float, h: float, lean: float, ry: float) -> Node3D:
	var g := _group(_w, x, GROUND, z)
	g.rotation = Vector3(0, ry, lean)
	for s in [-0.55, 0.55]:
		_add(_cyl(), _lam("#b8692e"), s, h / 2, 0, g, {s = [0.1, h, 0.1]})
	var k := 1
	while k < h / 0.7:
		_add(_cyl(), _lam("#e8a05a"), 0, k * 0.7, 0, g, {s = [0.06, 1.1, 0.06], rz = PI / 2})
		k += 1
	return g

func _pawn(parent: Node3D, x: float, z: float, col) -> Node3D:
	var m := _std(col, 0.3)
	var g := _group(parent, x, 0, z)
	_add(MeshKit.cylinder(0.26, 0.3, 0.1, 20), m, 0, 0.05, 0, g)
	_add(MeshKit.cylinder(0.09, 0.23, 0.42, 20), m, 0, 0.3, 0, g)
	_add(MeshKit.cylinder(0.15, 0.15, 0.05, 20), m, 0, 0.52, 0, g)
	_add(_sph(), m, 0, 0.66, 0, g, {s = 0.16})
	return g

func _lollipop(x: float, z: float, h: float, r: float, c1, c2) -> Node3D:
	var g := _group(_w, x, GROUND, z)
	_add(_cyl(), _std("#ffffff", 0.3), 0, h / 2, 0, g, {s = [r * 0.12, h, r * 0.12]})
	_add(_sph(), _std(c1, 0.25), 0, h + r * 0.8, 0, g, {s = [r, r, r * 0.35]})
	var i := 0
	for k in [0.75, 0.5, 0.25]:
		_add(_torus(r * k, r * 0.09, 8, 28), _std(c1 if i % 2 else c2, 0.25), 0, h + r * 0.8, r * 0.3, g)
		i += 1
	return g

func _cotton_tree(x: float, z: float, h: float, r: float, cols: Array) -> Node3D:
	var g := _group(_w, x, GROUND, z)
	for k in 6:
		_add(_cyl(), _std("#ffffff" if k % 2 else "#ff8fc1", 0.3), 0, h / 6 * (k + 0.5), 0, g, {s = [r * 0.3, h / 6 * 1.02, r * 0.3]})
	_canopy(g, 0, h + r * 0.9, 0, r * 2.2, cols)
	return g

func _gumdrop(parent: Node3D, x: float, z: float, s: float, col) -> Node3D:
	var g := _group(parent, x, GROUND, z)
	_add(MeshKit.cylinder(s * 0.55, s, s * 0.9, 20), _std(col, 0.2), 0, s * 0.45, 0, g)
	_add(_sph(), _std(col, 0.2), 0, s * 0.9, 0, g, {s = [s * 0.55, s * 0.35, s * 0.55]})
	return g

func _cane(parent: Node3D, x: float, z: float, h: float, ry: float) -> Node3D:
	var g := _group(parent, x, GROUND, z)
	g.rotation.y = ry
	_striped_rod(Vector3.ZERO, Vector3(0, h, 0), 0.18, ["#e5484d", "#ffffff"], g)
	for k in 8:
		var a0 := k / 8.0 * PI
		var a1 := (k + 1) / 8.0 * PI
		_rod(Vector3(0.55 - cos(a0) * 0.55, h + sin(a0) * 0.55, 0), Vector3(0.55 - cos(a1) * 0.55, h + sin(a1) * 0.55, 0), 0.18, _std("#ffffff" if k % 2 else "#e5484d", 0.3), g)
	return g

func _column(x: float, z: float, h: float, r: float, col, tilt := 0.0) -> Node3D:
	var g := _group(_w, x, GROUND, z)
	g.rotation.z = tilt
	_add(MeshKit.rbox(r * 3, r * 0.8, r * 3, r * 0.2), _lam(col), 0, r * 0.4, 0, g)
	_add(MeshKit.cylinder(r, r * 1.08, h, 16), _lam(col), 0, h / 2 + r * 0.8, 0, g)
	if tilt == 0.0:
		_add(MeshKit.rbox(r * 2.8, r * 0.7, r * 2.8, r * 0.2), _lam(col), 0, h + r * 1.15, 0, g)
	return g

func _pine(x: float, z: float, h: float, s: float, col = "#3f7f6a", snow := true) -> Node3D:
	var g := _group(_w, x, GROUND, z)
	_add(_cyl(), _lam("#6b4a32"), 0, h * 0.15, 0, g, {s = [s * 0.25, h * 0.3, s * 0.25]})
	for t2 in [[0.25, 1.6], [0.5, 1.25], [0.75, 0.9]]:
		_add(_cone(s * t2[1], h * 0.38, 12), _lam(col), 0, h * t2[0] + h * 0.1, 0, g)
		if snow:
			_add(_cone(s * t2[1] * 0.62, h * 0.17, 12), _lam("#ffffff"), 0, h * t2[0] + h * 0.21, 0, g)
	return g

func _lantern(parent: Node3D, x: float, z: float, h: float) -> Node3D:
	var g := _group(parent, x, GROUND, z)
	_add(_cyl(), _lam("#4a3a32"), 0, h / 2, 0, g, {s = [0.08, h, 0.08]})
	_add(MeshKit.rbox(0.5, 0.62, 0.5, 0.08), _lam("#3a2e2a"), 0, h + 0.3, 0, g)
	_add(MeshKit.rbox(0.38, 0.46, 0.38, 0.06), _glow("#ffcf7a", 1.4), 0, h + 0.3, 0, g)
	_add(_cone(0.42, 0.3, 4), _lam("#3a2e2a"), 0, h + 0.76, 0, g, {ry = PI / 4})
	return g

func _puff(parent: Node3D, x: float, y: float, z: float, s: float, col = "#ffffff") -> Node3D:
	var g := _group(parent, x, y, z)
	for p in [[0, 0, 0, 1], [0.9, -0.15, 0.1, 0.75], [-0.9, -0.12, 0, 0.8], [0.35, 0.35, -0.2, 0.7], [-0.4, 0.3, 0.2, 0.62]]:
		_add(_sph(), _lam(col), p[0] * s, p[1] * s, p[2] * s, g, {s = p[3] * s})
	return g

func _island(x: float, y: float, z: float, s: float, bob := true, parent: Node3D = null) -> Node3D:
	var g := _group(parent if parent else _w, x, y, z)
	_add(_cone(s, s * 1.6, 9), _lam("#b49478"), 0, -s * 0.8, 0, g, {rx = PI})
	_add(MeshKit.cylinder(s * 1.02, s * 0.98, s * 0.25, 18), _lam("#8fd16a"), 0, 0, 0, g)
	_add(_cyl(), _lam("#8a5a32"), 0, s * 0.5, 0, g, {s = [s * 0.1, s * 0.9, s * 0.1]})
	_add(_sph(), _lam("#6cc457"), 0, s * 1.1, 0, g, {s = s * 0.5})
	_puff(g, -s * 0.9, -s * 0.5, s * 0.2, s * 0.35)
	if bob:
		_dyn(g)
		_bobs.append({g = g, y = y, ph = rng.randf() * 6, amp = 0.25 + rng.randf() * 0.2})
	return g

func _rainbow(x: float, y: float, z: float, R: float, ry := 0.0) -> Node3D:
	var g := _group(_w, x, y, z)
	g.rotation.y = ry
	var k := 0
	for c in ["#ff6b6b", "#ffa94d", "#ffe066", "#69db7c", "#4dabf7", "#9775fa"]:
		_add(_torus(R - k * 0.55, 0.3, 8, 48, PI), _lam(c), 0, 0, 0, g)
		k += 1
	return g

func _mushroom(parent: Node3D, x: float, z: float, s: float, col) -> Node3D:
	var g := _group(parent, x, GROUND, z)
	_add(_cyl(), _lam("#f3ead8"), 0, s * 0.45, 0, g, {s = [s * 0.18, s * 0.9, s * 0.18]})
	_add(_sph(), _glow(col, 0.85), 0, s * 0.95, 0, g, {s = [s * 0.55, s * 0.32, s * 0.55]})
	for d in [[0.25, 0.2], [-0.2, 0.28], [0.05, -0.3]]:
		_add(_sph(), _lam("#ffffff"), d[0] * s, s * 1.12, d[1] * s, g, {s = s * 0.07})
	return g

func _snowman(parent: Node3D, x: float, z: float, s: float) -> Node3D:
	var g := _group(parent, x, GROUND, z)
	var w := _lam("#ffffff")
	_add(_sph(), w, 0, s * 0.7, 0, g, {s = s * 0.75})
	_add(_sph(), w, 0, s * 1.65, 0, g, {s = s * 0.5})
	_add(_sph(), w, 0, s * 2.3, 0, g, {s = s * 0.35})
	_add(_cone(s * 0.07, s * 0.4, 10), _lam("#ff8a2a"), 0, s * 2.3, s * 0.45, g, {rx = PI / 2})
	for k in [-1.0, 1.0]:
		_add(_sph(), _lam("#2a1d24"), k * s * 0.12, s * 2.42, s * 0.3, g, {s = s * 0.05})
	_add(_torus(s * 0.42, s * 0.09, 8, 20), _lam("#e5484d"), 0, s * 1.98, 0, g, {rx = PI / 2})
	return g

## The framing piece on the left with a snake coiled up it, head turned toward you (hidden during a match).
func _coil_on(pillar: Node3D, R: float, cols: Array) -> void:
	var coil := []
	for k in 15:
		var a := k * 0.5
		coil.append(Vector3(cos(a) * R, 1 + k * 0.19, sin(a) * R))
	coil.append(Vector3(R + 0.33, 4.0, 1.05))
	coil.append(Vector3(R + 0.58, 4.5, 1.6))
	await _snake(coil, 0.3, cols[0], cols[1], cols[2], Vector3(0.6, -0.3, 1), pillar)

## The sign: two planks in the scene's colours, the title painted on, hanging on ropes.
func _make_sign(S: Dictionary) -> Node3D:
	var g := Node3D.new()
	g.name = "Sign"
	var grng := RandomNumberGenerator.new()
	grng.seed = 4242
	var grain: Color = S.grain
	var plank: Texture2D = await _baker.bake(Vector2i(512, 128), func(c: Control):
		var w := c.size.x
		var h := c.size.y
		c.draw_rect(Rect2(0, 0, w, h), _col(S.plank))
		for i in 26:
			var col := Color(grain, 0.12 + grng.randf() * 0.15)
			var lw := 1.0 + grng.randf() * 2
			var y := grng.randf() * h
			var pts := PackedVector2Array()
			for k in 25:
				var u := k / 24.0
				var a := Vector2(0, y); var b := Vector2(w * 0.3, y + 8); var cc := Vector2(w * 0.6, y - 8); var d := Vector2(w, y + 4)
				pts.append(a * pow(1 - u, 3) + b * 3 * u * pow(1 - u, 2) + cc * 3 * u * u * (1 - u) + d * u * u * u)
			c.draw_polyline(pts, col, lw, true)
		for x in [24.0, w - 24]:
			c.draw_circle(Vector2(x, h / 2), 6, Color(70 / 255.0, 35 / 255.0, 15 / 255.0, 0.4), true, -1, true))
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = plank
	wood.roughness = 1.0
	wood.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	wood.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var edge := _lam(S.edge)
	for y in [0.55, -0.55]:
		_add(MeshKit.rbox(6.2, 1.12, 0.28, 0.02), edge, 0, y, 0, g)
		var q := QuadMesh.new()
		q.size = Vector2(6.2, 1.12)
		_add(q, wood, 0, y, 0.141, g)
	var title: Texture2D = await _baker.bake(Vector2i(1024, 400), func(c: Control):
		var w := c.size.x
		var h := c.size.y
		var font := UIKit.font_display()
		for wd in [["SNAKES", h * 0.3, 150, S.c1], ["& LADDERS", h * 0.72, 132, S.c2]]:
			var px: int = wd[2]
			var asc := font.get_ascent(px)
			var desc := font.get_descent(px)
			var base := Vector2(0, wd[1] + (asc - desc) / 2.0)
			c.draw_string_outline(font, base, wd[0], HORIZONTAL_ALIGNMENT_CENTER, w, px, int(px * 0.22), _col(S.stroke))
			c.draw_string_outline(font, base, wd[0], HORIZONTAL_ALIGNMENT_CENTER, w, px, int(px * 0.12), Color("#fff6e6"))
			c.draw_string(font, base, wd[0], HORIZONTAL_ALIGNMENT_CENTER, w, px, _col(wd[3])), true)
	var tq := QuadMesh.new()
	tq.size = Vector2(6, 2.34)
	var tm := _basic_tex(title)
	tm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	tm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_add(tq, tm, 0, 0, 0.15, g)
	var rope := _lam(S.rope)
	for x in [-2.4, 2.4]:
		_add(_cyl(), rope, x, 5.2, 0, g, {s = [0.06, 9, 0.06]})
	match str(S.top):
		"vine":
			_vine(Vector3(-3.3, 1.3, -0.05), Vector3(3.3, 1.32, -0.05), 0.28, g, S.get("vine", ["#3f8f3a", "#5cb84a", "#3f9a3a"]))
		"snow":
			var k := 0
			for x in [-2.2, -0.7, 0.8, 2.3]:
				_add(_sph(), _lam("#ffffff"), x, 1.14, 0, g, {s = [0.95 + (k % 2) * 0.2, 0.2, 0.22]})
				k += 1
		"cloud":
			var k := 0
			for x in [-2.6, -1.2, 0.2, 1.5, 2.7]:
				_add(_sph(), _lam("#ffffff"), x, 1.2, -0.05, g, {s = 0.38 + (k % 2) * 0.14})
				k += 1
	# a little snake curled over the top-right corner, peeking at you
	var sn: Array = S.snake
	await _snake([Vector3(1.4, 1.2, -0.25), Vector3(2.1, 1.35, -0.2), Vector3(2.8, 1.25, 0), Vector3(3.1, 1.6, 0.25), Vector3(2.9, 2.1, 0.45)], 0.17, sn[0], sn[1], sn[2], Vector3(-0.4, -0.15, 1), g)
	return g

func _build_motes(cfg: Array) -> void:
	_mote_kind = cfg[0]
	var n: int = cfg[2]
	var size: float = cfg[3] * tan(deg_to_rad(FOV / 2))       # three.js points: size * scale / depth px ≈ this in world units
	_mote_seeds.clear()
	for i in n:
		if _mote_kind == "snow":
			_mote_seeds.append([(rng.randf() - 0.5) * 30, rng.randf() * 16, -2 - rng.randf() * 18, rng.randf() * 6, 0.6 + rng.randf() * 0.7])
		else:
			_mote_seeds.append([(rng.randf() - 0.5) * 22, GROUND + 0.5 + rng.randf() * 7, -4 - rng.randf() * 14, rng.randf() * 6])
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if _mote_kind == "snow" else BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_color = _col(cfg[1])
	m.albedo_texture = _radial([0.0, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0)], 32)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = n
	_motes = MultiMeshInstance3D.new()
	_motes.multimesh = mm
	_motes.material_override = m
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.extra_cull_margin = 64
	_dyn(_motes)
	_w.add_child(_motes)
	_update_motes()


# =====================================================================================================================
# The scenery of each scene (index.html jungleWorld, candyWorld, ...)
# =====================================================================================================================

func _ring_pos(i: int, n_minus: float, a0: float, span: float, r: float) -> Vector2:
	var a := PI * (a0 + i / n_minus * span)
	return Vector2(cos(a) * r, sin(a) * r)

func _jungle_world() -> void:
	var greens := [["#4caf50", "#43a047", "#7cc95a"], ["#3f9a3a", "#4caf50", "#72c055"], ["#57b847", "#4caf50", "#8fd16a"]]
	_sway_on = false
	var i := 0
	for tr in [[-15, -17, 4, 1], [-6, -26, 5, 1.1], [6, -25, 4.5, 1], [16, -16, 4, 0.95], [-24, -8, 4, 0.9], [24, -7, 4.5, 1], [0, -36, 6, 1.3]]:
		_tree(tr[0], tr[1], tr[2], tr[3], greens[i % 3]); i += 1
	for p in [[-19, -22, 8, 0.06], [19, -23, 7.5, -0.08]]:
		_palm(p[0], p[1], p[2], p[3])
	for k in 9:
		var q := _ring_pos(k, 8.0, 1.08, 0.84, 10 + (k % 2) * 1.5)
		_bush(_w, q.x, q.y, 1.6 + (k % 3) * 0.3, greens[k % 3], ["#ff8fb3", "#ffd34d", "#ff7a5a"] if k % 3 == 1 else null)
	for k in 4:
		var q := _ring_pos(k, 3.0, 1.2, 0.6, 8)
		_fern(_w, q.x, q.y, 1.3, "#66bb4a")
	_sway_on = true
	var left := _tree(0, 0, 16, 1.1, ["#3f9a3a", "#4caf50", "#66bb4a"], "#6b3f22")
	_anchor(left, -1.04, 0, 1.02, true, 0.9)
	_coil_tree = left
	await _coil_on(left, 1.42, ["#5cc84f", "#2f8f3a", "#fff0b8"])
	var right := _tree(0, 0, 17, 1.2, ["#4caf50", "#43a047", "#72c055"], "#6b3f22")
	right.rotation.y = PI
	_anchor(right, 1.07, 0, 1.12, true, 0.9)
	await _hanging_snake("#9a5ee8", "#6436b8", "#ffe9c8", "#6b3f22", ["#3f9a3a", "#4caf50", "#72c055"])
	var lad := _ladder_prop(0, 0, 6, -0.28, 0.4)
	_anchor(lad, -0.86, -0.2, 1.06, true, 0.6)
	var fl := _group(_w, 0, 0, 0)
	_anchor(fl, -0.92, -0.66, 0.72, true, 0.8)
	_bush(fl, 0, 0, 1.3, ["#4caf50", "#66bb4a"], ["#ff8fb3", "#ffd34d"])
	_fern(fl, 1.6, 0.8, 1.2, "#57b847")
	var fr := _group(_w, 0, 0, 0)
	_anchor(fr, 0.96, -0.42, 0.9, true, 0.9)
	_fern(fr, 0, 0, 1.5, "#4caf50")
	var vines := _group(_w, 0, 0, 0)
	_anchor(vines, 0, 0.99, 1.0, false, 0.9)
	_vine(Vector3(-9, 1, 0), Vector3(9, 1.2, 0), 2.2, vines)
	_vine(Vector3(-8, 2, -1), Vector3(4, 2.4, -1), 1.4, vines)

func _hanging_snake(c0, c1, c2, bark, leaves: Array) -> void:
	var hang := _group(_w, 0, 0, 0)
	_anchor(hang, 0.84, 0.2, 0.92, false, 0.7)
	await _snake([Vector3(2.2, 2.6, 0), Vector3(1.1, 2.55, 0), Vector3(0.1, 2.2, 0.05), Vector3(-0.25, 1.35, 0.2), Vector3(0.1, 0.55, 0.3), Vector3(-0.25, -0.05, 0.5)], 0.26, c0, c1, c2, Vector3(-0.5, -0.3, 1), hang)
	_add(_cyl(), _lam(bark), 1.3, 2.85, 0, hang, {s = [0.18, 4, 0.18], rz = PI / 2})
	_canopy(hang, 3.4, 3.4, -0.4, 1.5, leaves)

func _candy_world() -> void:
	var pinks := [["#ffb3d9", "#ff9cc9", "#ffe0f0"], ["#b9e4ff", "#9fd6ff", "#e6f6ff"], ["#e5d4ff", "#d3bcff", "#f6efff"]]
	_sway_on = false
	var i := 0
	for tr in [[-15, -17, 4.5, 1], [-6, -26, 5.5, 1.1], [6, -25, 5, 1], [16, -16, 4.5, 0.95], [-24, -8, 4.5, 0.9], [24, -7, 5, 1], [0, -36, 6.5, 1.3]]:
		_cotton_tree(tr[0], tr[1], tr[2], tr[3], pinks[i % 3]); i += 1
	for a in [[-4.6, -9, 3.6, 1.2, "#ff6fae", "#ffffff"], [4.9, -11, 4.2, 1.35, "#7ad3ff", "#ffffff"], [-2, -18, 6, 1.8, "#ffe066", "#ff8fc1"], [3.2, -23, 6.5, 1.9, "#9be38a", "#ffffff"], [-12, -14, 5, 1.5, "#c49bff", "#ffffff"]]:
		_lollipop(a[0], a[1], a[2], a[3], a[4], a[5])
	var cols := ["#ff6fae", "#7ad3ff", "#ffe066", "#9be38a", "#c49bff", "#ff9f6b"]
	for k in 12:
		var q := _ring_pos(k, 11.0, 1.06, 0.88, 9.5 + (k % 2) * 1.6)
		_gumdrop(_w, q.x, q.y, 0.9 + (k % 3) * 0.25, cols[k % cols.size()])
	for c in [[-2.6, -7.2, 0.3], [2.4, -7.4, -0.4], [-7, -5, 0.9], [7, -5.5, -0.8]]:
		_cane(_w, c[0], c[1], 2.4, c[2])
	_sway_on = true
	var left := _cotton_tree(0, 0, 15, 1.1, pinks[0])
	_anchor(left, -1.04, 0, 1.02, true, 0.9)
	_coil_tree = left
	await _coil_on(left, 0.72, ["#7ad3ff", "#3f9fd8", "#fff6fb"])
	var right := _lollipop(0, 0, 13, 3.2, "#ff6fae", "#ffffff")
	_anchor(right, 1.07, 0, 1.12, true, 0.9)
	var fl := _group(_w, 0, 0, 0)
	_anchor(fl, -0.92, -0.66, 0.72, true, 0.8)
	_gumdrop(fl, 0, 0, 1.2, "#ffe066")
	_gumdrop(fl, 1.5, 0.6, 0.9, "#ff6fae")
	var fr := _group(_w, 0, 0, 0)
	_anchor(fr, 0.96, -0.42, 0.9, true, 0.9)
	_cane(fr, 0, 0, 3, -0.3)
	_gumdrop(fr, -1.2, 0.8, 1, "#7ad3ff")

func _desert_world() -> void:
	var sand := "#e2c08a"
	var stone := "#d9b27c"
	_sway_on = false
	for d in [[-30, -30, 14], [28, -34, 16], [0, -46, 20], [-40, -10, 12], [40, -12, 12]]:
		_add(_sph(), _lam(sand), d[0], GROUND, d[1], null, {s = [d[2], d[2] * 0.28, d[2] * 0.8]})
	for k in 5:
		_add(MeshKit.rbox(12 - k * 2.2, 1.5, 12 - k * 2.2, 0.2), _lam("#cf9f62"), -3, GROUND + 0.75 + k * 1.5, -30, null)
	for c in [[-5, -11, 6], [-2.2, -16, 8], [2.2, -16, 8], [5.5, -12, 6.5]]:
		_column(c[0], c[1], c[2], 0.55, stone)
	_column(-16, -6, 3.5, 0.55, stone)
	_column(16, -6, 2.5, 0.55, stone)
	_add(MeshKit.rbox(5.6, 0.9, 1.2, 0.1), _lam(stone), 0, GROUND + 9.4, -16, null)
	for b in [[-9, -9, 0.4], [9.5, -10, -0.3], [-3, -14, 0.8]]:
		_add(MeshKit.rbox(1.6, 1, 1.1, 0.15), _lam("#cfa56c"), b[0], GROUND + 0.5, b[1], null, {ry = b[2]})
	_add(_circle(2.6, 40), _std("#45b7d1", 0.08, 0.1), 3.4, GROUND + 0.03, -8.6, null, {rx = -PI / 2})
	_add(_ring(2.6, 3.2, 40), _lam("#8fc46a"), 3.4, GROUND + 0.025, -8.6, null, {rx = -PI / 2})
	for k in 9:
		var a := k / 9.0 * TAU
		_add(_cyl(), _lam("#6fa84a"), 3.4 + cos(a) * 3, GROUND + 0.6, -8.6 + sin(a) * 3, null, {s = [0.06, 1.2, 0.06], rz = sin(a) * 0.2})
	for p in [[5.6, -10.5, 6.5, -0.12], [1.4, -12, 7, 0.08], [-4.8, -8.5, 6, 0.14], [-8, -15, 7.5, 0.06], [9, -16, 7, -0.1]]:
		_palm(p[0], p[1], p[2], p[3])
	_sway_on = true
	var left := _column(0, 0, 15, 1.1, stone)
	_anchor(left, -1.04, 0, 1.02, true, 0.9)
	_coil_tree = left
	await _coil_on(left, 1.45, ["#d4a64a", "#8a5a2a", "#fff0c8"])
	var right := _group(_w, 0, 0, 0)
	_anchor(right, 1.07, 0, 1.12, true, 0.9)
	var palm := _palm(0, 0, 15, -0.08, right)
	palm.position.y = 0
	var fl := _group(_w, 0, 0, 0)
	_anchor(fl, -0.92, -0.66, 0.72, true, 0.8)
	_add(MeshKit.rbox(1.8, 1.1, 1.3, 0.15), _lam(stone), 0, GROUND + 0.55, 0, fl, {ry = 0.4})
	_add(_sph(), _lam("#d8b278"), 1.6, GROUND, 0.6, fl, {s = [1.2, 0.5, 1]})
	var fr := _group(_w, 0, 0, 0)
	_anchor(fr, 0.96, -0.42, 0.9, true, 0.9)
	_add(MeshKit.rbox(1.2, 2.2, 1.2, 0.15), _lam(stone), 0, GROUND + 1.1, 0, fr, {rz = 0.15})

func _frost_world() -> void:
	_sway_on = false
	for p in [[-5.5, -14, 7, 1.1], [5, -15, 7.5, 1.15], [-1.5, -20, 9, 1.4], [3.5, -24, 10, 1.5], [-8, -22, 9, 1.4], [9, -21, 9, 1.4], [0, -32, 12, 1.8], [-12, -12, 7, 1.1], [12, -11, 7.5, 1.15]]:
		_pine(p[0], p[1], p[2], p[3])
	_add(_circle(2.8, 40), _std("#bfe6f5", 0.06, 0.1), -3.2, GROUND + 0.03, -9.5, null, {rx = -PI / 2})
	_add(_ring(2.8, 3.4, 40), _lam("#ffffff"), -3.2, GROUND + 0.025, -9.5, null, {rx = -PI / 2})
	for k in 10:
		var q := _ring_pos(k, 9.0, 1.08, 0.84, 10 + (k % 2) * 1.5)
		_add(_sph(), _lam("#ffffff"), q.x, GROUND, q.y, null, {s = [1.6 + (k % 3) * 0.4, 0.7, 1.4]})
	_snowman(_w, 3.6, -8.6, 1.05)
	for l in [[-5.6, -6.6], [5.8, -6.4], [-0.6, -11.5]]:
		_lantern(_w, l[0], l[1], 2.4)
	_sway_on = true
	var left := _tree(0, 0, 16, 1.1, ["#3f7f6a", "#4f8f7a", "#ffffff"], "#6b4a32")
	_anchor(left, -1.04, 0, 1.02, true, 0.9)
	_coil_tree = left
	await _coil_on(left, 1.4, ["#e5484d", "#ffffff", "#fff3f3"])
	var right := _pine(0, 0, 17, 1.25)
	_anchor(right, 1.1, 0, 1.12, true, 0.9)
	var fl := _group(_w, 0, 0, 0)
	_anchor(fl, -0.92, -0.66, 0.72, true, 0.8)
	_lantern(fl, 0, 0, 2.2)
	_add(_sph(), _lam("#ffffff"), 1.4, GROUND, 0.5, fl, {s = [1.4, 0.6, 1.1]})
	var fr := _group(_w, 0, 0, 0)
	_anchor(fr, 0.96, -0.42, 0.9, true, 0.9)
	_snowman(fr, 0, 0, 0.9)

func _cloud_world() -> void:
	_sway_on = false
	for k in 26:
		var a := rng.randf() * TAU
		var r := 6 + rng.randf() * 30
		_puff(_w, cos(a) * r, GROUND - 1.2 + rng.randf() * 0.8, sin(a) * r - 4, 1.6 + rng.randf() * 1.8, "#ffffff" if k % 4 else "#f3ecff")
	_puff(_w, 0, GROUND - 0.4, 0, 2.3)
	_rainbow(0, GROUND - 2, -28, 11)
	_rainbow(-6, GROUND + 1, -16, 5, 0.5)
	for p in [[-4.6, 2.2, -12, 1.2], [5.2, 3.6, -15, 1.5], [-1.5, 6.5, -22, 1.7], [8, 1.2, -9, 1], [-9, 4, -20, 1.6]]:
		_island(p[0], p[1], p[2], p[3])
	_sway_on = true
	var left := _group(_w, 0, 0, 0)
	_anchor(left, -1.04, 0, 1.02, true, 0.9)
	for k in 7:
		_puff(left, 0, k * 2.2 + 0.5, 0, 1.25 - k * 0.04)
	_add(_cyl(), _lam("#f3ecff"), 0, 7, 0, left, {s = [1.05, 14, 1.05]})
	_coil_tree = left
	await _coil_on(left, 1.9, ["#ff9ad0", "#ffffff", "#fff2fa"])
	var right := _group(_w, 0, 0, 0)
	_anchor(right, 1.02, 0.42, 1.2, false, 0.9)
	_island(0, 0, 0, 1.1, false, right)
	var fl := _group(_w, 0, 0, 0)
	_anchor(fl, -0.92, -0.66, 0.72, true, 0.8)
	_puff(fl, 0, 0.6, 0, 1.3)
	var fr := _group(_w, 0, 0, 0)
	_anchor(fr, 0.96, -0.42, 0.9, true, 0.9)
	_puff(fr, 0, 0.8, 0, 1.4, "#f3ecff")

func _enchanted_world() -> void:
	var teal := [["#2e8b6e", "#3aa17e", "#7fe0c0"], ["#2f7d5a", "#43a06e", "#9ef0c8"], ["#3a6f8f", "#4a8fb0", "#a8e6ff"]]
	_sway_on = false
	var i := 0
	for tr in [[-15, -17, 6, 1], [-6, -26, 7, 1.1], [6, -25, 6.5, 1], [16, -16, 6, 0.95], [-24, -8, 5.5, 0.9], [24, -7, 6, 1], [0, -36, 8, 1.3]]:
		_tree(tr[0], tr[1], tr[2], tr[3] * 0.9, teal[i % 3], "#4a3326"); i += 1
	for k in 9:
		var q := _ring_pos(k, 8.0, 1.08, 0.84, 10 + (k % 2) * 1.5)
		_bush(_w, q.x, q.y, 1.5 + (k % 3) * 0.3, teal[k % 3], ["#ff9be0", "#9be8ff", "#fff59b"] if k % 2 else null)
	var glows := ["#7ef0c8", "#ff8fe0", "#9bd8ff", "#ffe27a"]
	for k in 14:
		var q := _ring_pos(k, 13.0, 1.05, 0.9, 7.5 + (k % 3) * 1.2)
		_mushroom(_w, q.x, q.y, 0.6 + (k % 3) * 0.25, glows[k % glows.size()])
	for k in 4:
		var q := _ring_pos(k, 3.0, 1.2, 0.6, 8.6)
		_fern(_w, q.x, q.y, 1.3, "#3aa17e")
	_sway_on = true
	var left := _tree(0, 0, 16, 1.1, teal[0], "#4a3326")
	_anchor(left, -1.04, 0, 1.02, true, 0.9)
	_coil_tree = left
	await _coil_on(left, 1.42, ["#f2c14e", "#b8862a", "#fff4d0"])
	var right := _tree(0, 0, 17, 1.2, teal[1], "#4a3326")
	right.rotation.y = PI
	_anchor(right, 1.07, 0, 1.12, true, 0.9)
	await _hanging_snake("#3fd0c0", "#1f8a80", "#e8fff8", "#4a3326", teal[2])
	var fl := _group(_w, 0, 0, 0)
	_anchor(fl, -0.92, -0.66, 0.72, true, 0.8)
	_mushroom(fl, 0, 0, 1.2, "#ff8fe0")
	_mushroom(fl, 1.3, 0.7, 0.8, "#7ef0c8")
	var fr := _group(_w, 0, 0, 0)
	_anchor(fr, 0.96, -0.42, 0.9, true, 0.9)
	_mushroom(fr, 0, 0, 1.1, "#9bd8ff")
	_fern(fr, 0.8, 0.6, 1.3, "#3aa17e")
	var vines := _group(_w, 0, 0, 0)
	_anchor(vines, 0, 0.99, 1.0, false, 0.9)
	var vc := ["#2e7d5a", "#4fbf8a", "#2f9a6a"]
	_vine(Vector3(-9, 1, 0), Vector3(9, 1.2, 0), 2.2, vines, vc, "#ffe27a")
	_vine(Vector3(-8, 2, -1), Vector3(4, 2.4, -1), 1.4, vines, vc, "#7ef0c8")


# ---------- static merge (index.html mergeStatic): one mesh per material for everything that never moves ----------

func _merge(root: Node3D) -> void:
	var buckets := {}                     # material -> [vertices, normals, indices]
	var kill := []
	var inv := root.global_transform.affine_inverse()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var mat := m.material_override as StandardMaterial3D
		if mat == null or mat.albedo_texture != null or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var p: Node = m
		var moving := false
		while p and p != root:
			if p.has_meta("dyn"):
				moving = true
				break
			p = p.get_parent()
		if moving or m.mesh == null:
			continue
		var xf := inv * m.global_transform
		var nb := xf.basis.inverse().transposed()
		if not buckets.has(mat):
			buckets[mat] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
		var bk: Array = buckets[mat]
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var ix = arr[Mesh.ARRAY_INDEX]
			var base: int = (bk[0] as PackedVector3Array).size()
			for k in v.size():
				bk[0].append(xf * v[k])
				bk[1].append((nb * n[k]).normalized())
			if ix is PackedInt32Array and (ix as PackedInt32Array).size() > 0:
				for q in ix:
					bk[2].append(base + q)
			else:
				for q in v.size():
					bk[2].append(base + q)
		kill.append(m)
	for m in kill:
		m.get_parent().remove_child(m)
		m.free()
	for mat in buckets:
		var bk: Array = buckets[mat]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = bk[0]
		arr[Mesh.ARRAY_NORMAL] = bk[1]
		arr[Mesh.ARRAY_INDEX] = bk[2]
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


# =====================================================================================================================
# Camera: landing framing, screen-anchored pieces, the match views (index.html fitView, anchor, playView, applyCam)
# =====================================================================================================================

## Pieces hung in front of the landing camera: k = distance as a share of the camera-to-table distance, s = size.
func _anchor(obj: Node3D, sx: float, sy: float, k: float, on_ground: bool, s := 1.0) -> void:
	_dyn(obj)
	_anchors.append({obj = obj, sx = sx, sy = sy, k = k, ground = on_ground, s = s})

func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(390, 844)

func _fit_if_needed() -> void:
	var vp := _viewport_size()
	if vp != _vp:
		_fit(vp)

func _fit(vp: Vector2) -> void:
	_vp = vp
	var aspect := vp.x / maxf(vp.y, 1.0)
	_vf = deg_to_rad(FOV) / 2.0
	_hf = atan(tan(_vf) * aspect)
	var dist := maxf(14.0, (TABLE_R / 0.84) / tan(_hf) * 1.06)
	var el := deg_to_rad(LANDING_EL)
	var pos := Vector3(0, sin(el) * dist + 0.4, cos(el) * dist)
	var look := Vector3(0, 0.2, 0)
	_landing = {pos = pos, look = look, up = Vector3.UP, ox = 0.0, oy = -vp.y * 0.07}
	_play_cache = {}
	var bs := Basis.looking_at(look - pos, Vector3.UP)
	var to_table := pos.length()
	for a in _anchors:
		var depth: float = a.k * to_table
		var p := _world_at(pos, bs, a.sx, a.sy, depth, _landing.oy)
		var obj: Node3D = a.obj
		obj.position = Vector3(p.x, GROUND if a.ground else p.y, p.z)
		if obj != _sign:
			obj.scale = Vector3.ONE * (a.s * depth / 14.0)
	if _sign:                               # facing the camera, 82% of the screen wide
		_sign.basis = bs.scaled_local(Vector3.ONE * (2 * tan(_hf) * SIGN_K * to_table * 0.82 / 6.4))

## The point `depth` in front of the camera (along its forward axis) at screen position (sx, sy) in -1..1.
func _world_at(pos: Vector3, bs: Basis, sx: float, sy: float, depth: float, oy: float) -> Vector3:
	var syf := sy - 2.0 * oy / _vp.y
	var dir := Vector3(sx * tan(_hf), syf * tan(_vf), -1.0)
	return pos + bs * (dir * depth)

func _goal() -> Dictionary:
	return _play_view(view) if mode == "play" else _landing

func _box() -> Rect2:
	if board_box.size.x > 0:
		return board_box
	var top := 12.0 + 48 + 96
	var bottom := _vp.y - 130.0
	var side := minf(_vp.x * PLAY_FILL, 560.0)
	return Rect2((_vp.x - side) / 2, top, side, maxf(bottom - top, side * 0.6))

## Camera that fits the whole board (plus pawn height) into the board box: '3d' 50° or 'top' straight down.
func _play_view(v: String) -> Dictionary:
	var R := _box()
	var key := "%s|%s|%s" % [v, _vp, R]
	if _play_cache.get("key", "") == key:
		return _play_cache
	var look := Vector3(0, SURF, 0)
	var top := v == "top"
	var el := deg_to_rad(PLAY_EL)
	var dir := Vector3(0, 1, 0) if top else Vector3(0, sin(el), cos(el))
	var up := Vector3(0, 0, -1) if top else Vector3.UP
	var H := BOARD_HALF
	var pts := []
	for x in [-H, H]:
		for z in [-H, H]:
			for y in [0.0, SURF]:
				pts.append(Vector3(x, y, z))
		pts.append(Vector3(x * 0.9, SURF + 0.45, -H))   # pawns standing on the far row
	# the start pad's near edge (pawns waiting in front of square 1): only its depth counts, the width is the board's
	for x in [-H * 0.5, 0.0]:
		pts.append(Vector3(x, 0.0, PAD_NEAR))
		pts.append(Vector3(x, 0.45, PAD_NEAR))
	var bs := Basis.looking_at(-dir, up)
	var box := func(d: float) -> Rect2:
		var cp := look + dir * d
		var r := Rect2()
		var first := true
		for p in pts:
			var q: Vector3 = bs.inverse() * (p - cp)
			var sx := (q.x / (-q.z * tan(_hf)) + 1) / 2 * _vp.x
			var sy := (1 - q.y / (-q.z * tan(_vf))) / 2 * _vp.y
			if first:
				r = Rect2(sx, sy, 0, 0)
				first = false
			else:
				r = r.expand(Vector2(sx, sy))
		return r
	var lo := 2.0
	var hi := 60.0
	for k in 30:
		var mid := (lo + hi) / 2
		var b: Rect2 = box.call(mid)
		if b.size.x > R.size.x or b.size.y > R.size.y:
			lo = mid
		else:
			hi = mid
	var b: Rect2 = box.call(hi)
	_play_cache = {key = key, pos = look + dir * hi, look = look, up = up,
		ox = b.get_center().x - R.get_center().x, oy = b.get_center().y - R.get_center().y}
	return _play_cache

## Ease the camera toward goal (k = share of the way; 1 = jump) and set the Godot camera from it.
func _apply_cam(goal: Dictionary, k: float) -> void:
	if goal.is_empty():
		return
	if _cam.is_empty():
		_cam = goal.duplicate()
	_cam.pos = (_cam.pos as Vector3).lerp(goal.pos, k)
	_cam.look = (_cam.look as Vector3).lerp(goal.look, k)
	_cam.up = (_cam.up as Vector3).lerp(goal.up, k).normalized()
	_cam.ox += (goal.ox - _cam.ox) * k
	_cam.oy += (goal.oy - _cam.oy) * k
	var pos := _to_godot(_cam.pos)
	var look := _to_godot(_cam.look)
	var fwd := (look - pos).normalized()
	var up: Vector3 = _cam.up
	if absf(fwd.dot(up)) > 0.999:
		up = Vector3(0, 0, -1)
	camera.look_at_from_position(pos, look, up)
	# three.js setViewOffset = a lens shift: Godot's frustum projection with the same vertical lens
	var near := 0.5 * K
	var far := 200.0 * K
	var h := 2.0 * near * tan(_vf)
	var aspect := _vp.x / maxf(_vp.y, 1.0)
	var off := Vector2(_cam.ox / _vp.x * h * aspect, -_cam.oy / _vp.y * h)
	camera.set_frustum(h, off, near, far)
	# the sky on the far plane, exactly the visible window
	var d := far * 0.95
	_sky.position = Vector3(off.x * d / near, off.y * d / near, -d)
	_sky.scale = Vector3(h * aspect * d / near, h * d / near, 1)

func _to_godot(p: Vector3) -> Vector3:
	return Vector3(p.x * K, p.y * K + TT, p.z * K)


# =====================================================================================================================
# Animation (index.html animate / render)
# =====================================================================================================================

func _process(delta: float) -> void:
	if not visible or _w == null or _building:
		return
	_animate(minf(delta, 0.05))
	_apply_cam(_goal(), 1.0 if reduced_motion else 1.0 - exp(-minf(delta, 1.0) * 3.5))

func _animate(dt: float) -> void:
	if _w == null:
		return
	_fit_if_needed()
	t += dt
	if mode == "play":                     # turn the table square to the camera (shortest way), then hold it
		var a := fposmod(_table.rotation.y + PI, TAU) - PI
		_table.rotation.y = a * maxf(0.0, 1.0 - dt * 4)
		# framing pieces hung from the landing view: kept in 3D View, gone in Top View (they would sit over the board)
		for an in _anchors:
			an.obj.visible = an.obj != _sign and an.obj != _coil_tree and view != "top"
		for p in _decor:
			p.visible = false
	else:
		_table.rotation.y += dt * (0.08 if reduced_motion else 0.22)
		for an in _anchors:
			an.obj.visible = true
		for p in _decor:
			p.visible = true
	for s in _sway:
		s.g.rotation.z = sin(t * 0.7 + s.ph) * s.amp
		s.g.rotation.x = cos(t * 0.5 + s.ph) * s.amp * 0.5
	for h in _heads:
		h.head.position.y = h.base.y + sin(t * 1.6 + h.ph) * h.amp
		h.head.rotation.z = sin(t * 0.9 + h.ph) * 0.12
	for o in _tongues:
		var c := fmod(t * 0.8 + o.ph, 3.0)
		o.g.scale = Vector3(1, 1, 0.4 + sin(c / 0.35 * PI) * 0.9 if c < 0.35 else 0.05)
		o.g.visible = c < 0.35
	for b in _beams:
		b.m.albedo_color.a = 0.32 + sin(t * 0.6 + b.ph) * 0.14
	_update_motes()
	for b in _bobs:
		b.g.position.y = b.y + sin(t * 0.7 + b.ph) * b.amp
	for l in _leaves:
		var m: Node3D = l.m
		m.position.y -= dt * l.sp
		m.position.x += sin(t + l.ph) * dt * 0.4
		m.rotation = Vector3(t * l.sp * 2 + l.ph, t + l.ph, t * 0.7)
		if m.position.y < GROUND:
			m.position.y = 12
			m.position.x = (rng.randf() - 0.5) * 14

func _update_motes() -> void:
	if _motes == null:
		return
	var mm := _motes.multimesh
	for i in _mote_seeds.size():
		var s: Array = _mote_seeds[i]
		var p: Vector3
		if _mote_kind == "snow":
			p = Vector3(s[0] + sin(t * 0.6 + s[3]) * 0.7, GROUND + fposmod(s[1] - t * s[4], 16.0), s[2] + cos(t * 0.4 + s[3]) * 0.4)
		else:
			p = Vector3(s[0] + sin(t * 0.5 + s[3]) * 0.8, s[1] + sin(t * 0.8 + s[3] * 2) * 0.5, s[2] + cos(t * 0.4 + s[3]) * 0.6)
		mm.set_instance_transform(i, Transform3D(Basis(), p))
