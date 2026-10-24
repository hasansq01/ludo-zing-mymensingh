class_name TableWorld
extends Node3D
## The 3D café: environment and lights, the round table with its cups, the Moonlit Café room around it, and the
## camera rig (index.html: Rooms + BUILD.cafe(true), placeCups, frameLoop's camera easing).
## Units as in the web version: 1 unit ≈ 2.5 cm, the board is 15 units, the table top is at y = TT.

const Y0 := -30.0                       # floor height
const TT := -0.31                       # table-top height
const W := 60.0                         # half room size
const H := 95.0                         # wall height
const GAME_EL := deg_to_rad(62.0)
const HOME_EL := deg_to_rad(33.0)
const TOP_EL := deg_to_rad(89.5)
const TOP_ROLL := PI / 4

var camera: Camera3D
var env: Environment
var board: LudoBoard
var sl_board: Node3D                    # Snakes & Ladders board (built by SLBoard)
var cups := []                          # four cups; in a game only two show, on the far side
var steam := []
var rooms: Rooms
var rng := RandomNumberGenerator.new()

# camera state, eased towards the targets every frame
var cam_az := -PI / 2
var cam_target_az := -PI / 2
var cam_el := HOME_EL
var cam_target_el := HOME_EL
var cam_zoom := 1.0
var cam_target_zoom := 1.0
var cam_roll := 0.0
var cam_target_roll := 0.0
var cam_dist := 30.0
var view_y := 0.0                       # vertical shift of the framing (camera v_offset), eased
var view_target_y := 0.0
var orbit := false                      # home screen: the camera drifts slowly round the café
var reduced_motion := false

func _ready() -> void:
	rng.seed = 20261023
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 48.0                   # horizontal: the web version's portrait lens (2·atan(tan 24°))
	camera.near = 0.5
	camera.far = 500.0
	add_child(camera)
	_build_environment()
	_build_table()
	board = LudoBoard.new()
	board.name = "LudoBoard"
	add_child(board)
	_update_camera(true)

## Textures are painted on the GPU, so the room is built in a second, awaitable step (the splash shows progress).
func build_room(baker: TexBaker, progress: Callable, room_id := Rooms.DEFAULT) -> void:
	board.set_texture(await baker.bake(Vector2i(2048, 2048), LudoBoard.paint))
	progress.call(0.35)
	var rings := await baker.bake(Vector2i(1024, 1024), _paint_rings)
	_table_top.material_override = MeshKit.tex_mat(rings, 0.32)
	_table_top.material_override.albedo_color = Color("#fff0dc")   # MOOD.night table tint
	_latte_mat.albedo_texture = await baker.bake(Vector2i(256, 256), _paint_latte)
	progress.call(0.5)
	rooms = Rooms.new(self)
	add_child(rooms)
	progress.call(0.6)
	await rooms.set_room(baker, room_id)
	progress.call(1.0)


# ---------- environment + shared lights ----------

func _build_environment() -> void:
	# index.html MOOD.night: background + fog #2b2244, hemisphere light (#8a6aa8 sky / #8a5038 ground, 0.32),
	# key spot (#ffd6a0, 0.85), no tone mapping, no post-processing (the "bloom" is additive sprites)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#2b2244")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8a5e80")      # the hemisphere light's sky / ground mean (in linear light)
	env.ambient_light_energy = 0.32
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("#2b2244")
	env.fog_depth_begin = 110.0
	env.fog_depth_end = 260.0
	env.fog_density = 1.0
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# the hemisphere light's up / down half (Rooms.apply_mood): the flat ambient is the sky / ground mean, these two
	# add (sky - ground) / 2 · cos(normal, up) on top, so faces looking up get the sky colour, faces looking down the
	# ground colour, exactly as three.js HemisphereLight (no specular, no shadow)
	for down in [false, true]:
		var hl := DirectionalLight3D.new()
		hl.name = "HemiDown" if down else "HemiUp"
		hl.light_negative = down
		hl.light_specular = 0.0
		hl.shadow_enabled = false
		hl.rotation = Vector3(PI / 2 if down else -PI / 2, 0, 0)
		hl.light_energy = 0.0
		add_child(hl)
		hemi.append(hl)
	# the key light: a warm spot from high above (three.js SpotLight angle .45, penumbra .6, no distance decay)
	key = SpotLight3D.new()
	key.light_color = Color("#ffd6a0")
	key.light_energy = 0.85                # three.js .85 (Rooms.apply_mood sets each room's own)
	key.spot_range = 220.0                # well past the floor: Godot fades a light out near the end of its range
	key.spot_attenuation = 0.0
	key.spot_angle = rad_to_deg(0.45)
	# three.js penumbra .6: full light inside 0.18 rad, a smoothstep to nothing at 0.45. Godot's cone falloff is
	# 1 - rim^(1 / spot_angle_attenuation) (rim = (1 - cos a) / (1 - cos angle), measured), so 0.71 (exponent 1.4)
	# fits it within 0.12 everywhere; the old 2.0 (exponent 0.5) already took 25 % off at the board's corners.
	key.spot_angle_attenuation = 0.71
	key.shadow_enabled = SHADOWS
	key.shadow_blur = 1.6
	key.shadow_bias = SHADOW_BIAS
	key.shadow_normal_bias = SHADOW_NBIAS
	key.position = Vector3(4, 60, 10)
	add_child(key)
	key.look_at(Vector3.ZERO, Vector3.FORWARD)

var key: SpotLight3D
var hemi: Array[DirectionalLight3D] = []    # [up, down]: see _build_environment
## No real shadows: in the GL Compatibility renderer a shadow-casting light is added in its own pass in sRGB space,
## which washed every daytime room out (see MeshKit.contact_shadow); soft contact shadows stand in for them.
static var SHADOWS := false
static var SHADOW_BIAS := 0.05
static var SHADOW_NBIAS := 0.6


# ---------- table + cups ----------

var _table_top: MeshInstance3D
var _latte_mat: StandardMaterial3D

func _build_table() -> void:
	var edge := MeshKit.mat(Color("#e6a462"), 0.32)
	var enamel := MeshKit.mat(Color("#fff8f0"), 0.28)
	var top := CylinderMesh.new()
	top.top_radius = 14.5; top.bottom_radius = 14.5; top.height = 1.2; top.radial_segments = 72; top.rings = 1
	MeshKit.put(self, top, edge, Vector3(0, TT - 0.6, 0))
	# the ring-grain top is its own disc so the texture maps straight down
	_table_top = MeshKit.put(self, _disc(14.5, 72), MeshKit.mat(Color("#f2c693"), 0.32), Vector3(0, TT + 0.02, 0), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.put(self, MeshKit.torus(14.5, 0.4, 72, 12), edge, Vector3(0, TT - 0.6, 0))
	MeshKit.put(self, MeshKit.cylinder(1.4, 1.9, 28, 24), enamel, Vector3(0, Y0 + 14.6, 0))
	MeshKit.put(self, MeshKit.cylinder(6.4, 7.4, 1.4, 40), enamel, Vector3(0, Y0 + 0.7, 0))
	# the key spot's shadow of the table top on the floor (light at (4, 60, 10): centred a little towards -x / -z)
	# and a darker contact shadow round the foot
	MeshKit.contact_shadow(self, 50, 50, Vector3(-2, Y0 + 0.16, -5), Color(0.2, 0.1, 0.05, 0.52), false, 0.72)
	MeshKit.contact_shadow(self, 19, 19, Vector3(0, Y0 + 0.18, 0), Color(0.22, 0.12, 0.06, 0.3))
	_latte_mat = StandardMaterial3D.new()
	_latte_mat.albedo_color = Color.WHITE
	_latte_mat.roughness = 0.35
	var glazes := [Color("#fffaf2"), Color("#ffc6a5"), Color("#d8caff"), Color("#bfe3ff")]
	for k in 4:
		var g := cup(self, Vector3.ZERO, k * 1.7 + 0.6, glazes[k])
		cups.append(g)
		for s in 4:
			var sp := MeshKit.glow(Color.WHITE, 1.0, 0.0)
			sp.material_override.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			g.add_child(sp)
			steam.append({sp = sp, base = 3.1, phase = s / 4.0 + k * 0.13, drift = rng.randf_range(-1, 1)})
	home_cups()

func set_table_tint(c: Color) -> void:
	if _table_top and _table_top.material_override:
		_table_top.material_override.albedo_color = c

static func _disc(r: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		for p in [Vector2.ZERO, Vector2(cos(a0), sin(a0)), Vector2(cos(a1), sin(a1))]:   # clockwise seen from above = front
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.5 + p.x * 0.5, 0.5 + p.y * 0.5))
			st.add_vertex(Vector3(p.x * r, 0, p.y * r))
	return st.commit()

## A cup of latte on its saucer (index.html cup()).
func cup(parent: Node3D, pos: Vector3, ry: float, glaze: Color) -> Node3D:
	var g := Node3D.new()
	g.position = pos + Vector3(0, TT, 0)
	g.rotation.y = ry
	g.scale = Vector3.ONE * 0.78
	parent.add_child(g)
	var gm := MeshKit.mat(glaze, 0.18)
	MeshKit.put(g, MeshKit.lathe(PackedVector2Array([Vector2(0, 0), Vector2(1.6, 0), Vector2(2.7, 0.25), Vector2(3, 0.42), Vector2(2.85, 0.45), Vector2(1.7, 0.22), Vector2(0, 0.22)]), 48), gm, Vector3.ZERO)
	MeshKit.put(g, MeshKit.lathe(PackedVector2Array([Vector2(0, 0), Vector2(1.05, 0), Vector2(1.2, 0.15), Vector2(1.45, 1.4), Vector2(1.62, 2.9), Vector2(1.55, 3), Vector2(1.45, 1.5), Vector2(1.12, 0.32), Vector2(0, 0.32)]), 40), gm, Vector3(0, 0.22, 0))
	var handle := TorusMesh.new()
	handle.inner_radius = 0.45; handle.outer_radius = 0.79; handle.rings = 24; handle.ring_segments = 10
	MeshKit.put(g, handle, gm, Vector3(1.45, 1.75, 0), Vector3(PI / 2, 0, 0))
	MeshKit.put(g, _disc(1.5, 40), _latte_mat, Vector3(0, 2.75, 0), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.put(g, BoxMesh.new(), MeshKit.mat(Color("#e9ecf2"), 0.18, 0.85), Vector3(2.05, 0.5, 0.4), Vector3(0, 0.3, 0), Vector3(0.25, 0.08, 2.6))
	MeshKit.contact_shadow(g, 7.6, 7.6, Vector3(-0.15, 0.015, -0.35), Color(0.24, 0.13, 0.07, 0.38))
	return g

## In a game: two cups sit 35° either side of the far board corner, behind the board as seen from the seat.
func place_cups(az: float) -> void:
	for k in cups.size():
		var g: Node3D = cups[k]
		g.visible = k < 2
		var a := az + PI + (0.62 if k else -0.62)
		g.position.x = sin(a) * 12.2
		g.position.z = cos(a) * 12.2

## Home screen: one cup beside each side of the board.
func home_cups() -> void:
	for k in cups.size():
		var g: Node3D = cups[k]
		var a := k * PI / 2
		g.visible = true
		g.position.x = sin(a) * 11.6
		g.position.z = cos(a) * 11.6


# ---------- painted textures ----------

func _paint_rings(c: Control) -> void:
	var w := c.size.x
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("#f2c693"))
	var r := 8.0
	var rr := RandomNumberGenerator.new(); rr.seed = 7
	while r < w * 0.72:
		var col := Color(190 / 255.0, 120 / 255.0, 60 / 255.0) if rr.randf() < 0.5 else Color(1.0, 236 / 255.0, 205 / 255.0)
		col.a = rr.randf_range(0.12, 0.3)
		c.draw_arc(c.size / 2 + Vector2(rr.randf_range(-6, 6), rr.randf_range(-6, 6)), r, 0, TAU, 128, col, rr.randf_range(1, 4), true)
		r += rr.randf_range(5, 14)

func _paint_latte(c: Control) -> void:
	var w := c.size.x
	var ctr := c.size / 2
	for k in 40:                                  # radial gradient by rings, outside in
		var t := 1.0 - k / 40.0
		var col := Color("#7a4a2a").lerp(Color("#b07848"), clampf((1.0 - t) / 0.25, 0, 1)) if t > 0.75 else Color("#b07848").lerp(Color("#d9a774"), 1.0 - t / 0.75)
		TexBaker.circle(c, ctr, w / 2 * t, col)
	var heart := PackedVector2Array()
	for k in 64:                                  # the latte-art heart
		var a := TAU * k / 64.0
		var x := 16 * pow(sin(a), 3)
		var y := 13 * cos(a) - 5 * cos(2 * a) - 2 * cos(3 * a) - cos(4 * a)
		heart.append(ctr + Vector2(x, -y) * 4.2 + Vector2(0, 6))
	c.draw_colored_polygon(heart, Color("#fff3e2"))

# ---------- camera ----------

## Framing for a seat (Ludo game): behind colour c's corner, the shortest way round.
static func seat_az(c: int) -> float:
	return -PI / 2 * (c + 1) - PI / 4

## Top View zoom (index.html topFit): the board with its frame (half side 8.4) at 97% of the screen width,
## and no taller than the band between the top and bottom card rows (`band_px` UI pixels of `vp_h`).
func top_zoom(band_px := 0.0, vp_h := 844.0) -> float:
	var hf := deg_to_rad(camera.fov) / 2.0
	var d := 8.4 / 0.97 / tan(hf)
	if band_px > 0:
		var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(390, 844)
		var vf := atan(tan(hf) * vp.y / vp.x)
		d = maxf(d, 8.4 / (tan(vf) * band_px / vp_h))
	return d / maxf(cam_dist, 0.001)

var top_band := 0.0                     # set by the app: free height between the card rows, in UI pixels

func view_game(c: int, top_view: bool) -> void:
	orbit = false
	var seat := seat_az(c)
	cam_target_az = seat + round((cam_az - seat) / TAU) * TAU
	cam_target_el = TOP_EL if top_view else GAME_EL
	cam_target_roll = TOP_ROLL if top_view else 0.0
	cam_target_zoom = top_zoom(top_band) if top_view else 1.0
	view_target_y = 0.0
	place_cups(seat)
	for k in cups.size():
		cups[k].visible = k < 2 and not top_view    # Top View: a clean board, no cups under the top cards

func set_top_view(top_view: bool) -> void:
	cam_target_el = TOP_EL if top_view else GAME_EL
	cam_target_roll = TOP_ROLL if top_view else 0.0
	cam_target_zoom = top_zoom(top_band) if top_view else 1.0
	for k in cups.size():
		cups[k].visible = k < 2 and not top_view

func view_home() -> void:
	orbit = true
	cam_target_el = HOME_EL
	cam_target_roll = 0.0
	cam_target_zoom = home_zoom
	view_target_y = home_view_y
	home_cups()

## Snakes & Ladders: square 1 at the bottom-left, seen from +Z (3D View 58°, or straight down).
func view_sl(top_view: bool) -> void:
	orbit = false
	cam_target_az = round(cam_az / TAU) * TAU
	cam_target_el = TOP_EL if top_view else deg_to_rad(58.0)
	cam_target_roll = 0.0
	cam_target_zoom = top_zoom() if top_view else 1.0
	view_target_y = 0.0
	place_cups(0.0)
	for k in cups.size():
		cups[k].visible = k < 2 and not top_view

func set_sl_top_view(top_view: bool) -> void:
	cam_target_el = TOP_EL if top_view else deg_to_rad(58.0)
	cam_target_zoom = top_zoom() if top_view else 1.0
	for k in cups.size():
		cups[k].visible = k < 2 and not top_view

## Home framing, measured by the home screen (table fits the band between the logo and the buttons).
var home_zoom := 1.15
var home_view_y := 0.0

## Home screen framing (index.html homeFit): the smallest zoom at which the whole table top is at most 99% of the
## screen width and fits the free band, then its far rim 7% of the screen height below the band's top.
func fit_home(band_top: float, band_bottom: float, vp: Vector2) -> void:
	var saved := [cam_el, cam_zoom, view_y]
	cam_el = HOME_EL
	view_y = 0.0
	var lo := 0.5
	var hi := 3.5
	for it in 26:
		var mid := (lo + hi) / 2.0
		cam_zoom = mid
		_update_camera(true)
		var bb := _rim_box()
		if bb.size.x <= vp.x * 0.99 and bb.size.y <= band_bottom - band_top:
			hi = mid
		else:
			lo = mid
	cam_zoom = hi
	_update_camera(true)
	var bb := _rim_box()
	var drop := vp.y * (0.025 if vp.y < 640 else 0.07)
	var want := minf(band_top + drop, band_bottom - bb.size.y)
	var c := Vector3(0, TT, 0)
	var ppu := (camera.unproject_position(c) - camera.unproject_position(c + camera.global_transform.basis.y)).length()
	home_zoom = hi
	home_view_y = (want - bb.position.y) / maxf(ppu, 0.001)
	cam_el = saved[0]; cam_zoom = saved[1]; view_y = saved[2]
	_update_camera(true)

## Screen-space bounding box of the table's rim.
func _rim_box() -> Rect2:
	var r := Rect2()
	for k in 32:
		var a := TAU * k / 32.0
		var p := camera.unproject_position(Vector3(cos(a) * 14.9, TT, sin(a) * 14.9))
		r = Rect2(p, Vector2.ZERO) if k == 0 else r.expand(p)
	return r

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if orbit and not reduced_motion:
		cam_target_az += 0.0016 * 60.0 * delta
	var k := 1.0 - pow(0.96, delta * 60.0)        # the web version's 0.04 easing per frame
	cam_az += (cam_target_az - cam_az) * k
	cam_el += (cam_target_el - cam_el) * k
	cam_zoom += (cam_target_zoom - cam_zoom) * k
	cam_roll += (cam_target_roll - cam_roll) * k
	view_y += (view_target_y - view_y) * k
	_update_camera(false)
	if not Quality.extras():                  # low tier: no steam, no room animation
		for s in steam:
			(s.sp as Sprite3D).visible = false
		return
	for s in steam:
		var p := fmod(t * 0.22 + s.phase, 1.0)
		var sp: Sprite3D = s.sp
		sp.position = Vector3(sin(t * 0.9 + s.phase * 9) * 0.5 * p + s.drift * p, s.base + p * 5.5, cos(t * 0.7 + s.phase * 7) * 0.4 * p)
		sp.pixel_size = (1.2 + p * 3.0) / 128.0
		sp.modulate.a = sin(p * PI) * 0.22
	if rooms:
		rooms.tick(t)

func _update_camera(_snap: bool) -> void:
	var vp_size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(390, 844)
	var aspect := vp_size.x / maxf(vp_size.y, 1.0)
	# fit the diamond (half-width 11.5) across the screen; the lens is fixed horizontally (48°)
	var hf := deg_to_rad(camera.fov) / 2.0
	var vf := atan(tan(hf) / aspect)
	var free := maxf(0.45, (vp_size.y - 330.0) / vp_size.y) if aspect < 0.9 else 0.9
	var need_v := 11.5 * sin(GAME_EL) + 1.2
	cam_dist = maxf(11.4 / tan(hf), need_v / (tan(vf) * free))
	var dist := cam_dist * cam_zoom
	var h := cos(cam_el) * dist
	camera.position = Vector3(sin(cam_az) * h, sin(cam_el) * dist, cos(cam_az) * h)
	# screen-up = the horizontal forward direction turned by the roll (well defined straight down, for Top View)
	var fwd := Vector3(-sin(cam_az), 0, -cos(cam_az))
	var cr := cos(cam_roll)
	var sr := sin(cam_roll)
	var up := Vector3(fwd.x * cr + fwd.z * sr, 0, -fwd.x * sr + fwd.z * cr)
	if cam_el < deg_to_rad(75) and cam_roll < 0.01:
		up = Vector3.UP
	camera.look_at_from_position(camera.position, Vector3.ZERO, up)
	camera.v_offset = view_y
