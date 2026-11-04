class_name Dice3D
extends SubViewportContainer
## The dice button: a real 3D die in its own little world (index.html: the .dice-btn / .cube CSS cube, PIPS, SHOW,
## rollCube() and the dice SKINS).
## Active (the player may roll): a gentle pulse and a glow in the tint colour (set_tint: the player's colour); after
## IDLE_HINT seconds without a roll a hand pointer taps the die (hinting() says when). Landing: a squash, then the face
## pops. While it waits for a roll, show_ready() turns it to a neutral three-quarter pose (a corner towards you, three
## faces showing, none of them "the" result), so the last roll's face never reads as the next one. Whose turn: set_turn(colour, can_tap, caption) tints the die and, with a caption, shows a small name pill under
## it ("Green’s turn"; Pass & Play), the same calls for Ludo and Snakes & Ladders.
## The die is drawn a little larger than the control (so the hop and its shadow are not clipped) and rendered at the
## screen's pixel density, so it stays crisp under the canvas_items stretch. The control's own rect is the tap area.

## Tapped or clicked (touch, or a real mouse button; emulated mouse events from touches are ignored).
signal pressed

const FACE_EULER := {                  # die rotation (YXZ euler) that turns each face to the front (+Z), like SHOW
	1: Vector3.ZERO, 6: Vector3(0, PI, 0), 2: Vector3(0, -PI / 2, 0),
	5: Vector3(0, PI / 2, 0), 3: Vector3(PI / 2, 0, 0), 4: Vector3(-PI / 2, 0, 0),
}
const PITCH := 0.0                     # face-on, like the web's CSS dice: the result is one clear face
const TILT := Vector3.ZERO             # resting pose: square to the camera (no side faces showing)
const PAD := Vector4(0.32, 0.62, 0.32, 0.36) # extra drawing room around the control (left, top, right, bottom) in sizes
const HOP := 0.62                      # jump height in die sizes
const DIE_FILL := 0.74                 # the die's on-screen size as a share of the control's height (default `fill`)
const IDLE_HINT := 4.0                 # s of an active, untouched die before the hand pointer shows
const READY_TURN := 0.785             # the neutral pose: turned 45° about the vertical, then tipped towards the camera
const READY_TIP := 0.6                 # (a corner towards you: the top and two sides show)
const READY_SCALE := 0.8               # the corner view is wider than a face: shrink it to the same footprint

const SHADER := """
shader_type spatial;
render_mode cull_back;

uniform vec4 body : source_color = vec4(0.992, 0.98, 0.949, 1.0);
uniform vec4 edge : source_color = vec4(0.882, 0.843, 0.765, 1.0);
uniform vec4 pip : source_color = vec4(0.133, 0.149, 0.247, 1.0);
uniform vec4 one : source_color = vec4(0.847, 0.196, 0.227, 1.0);
uniform float half_size = 0.5;

varying vec3 p_obj;
varying vec3 n_obj;

void vertex() {
	p_obj = VERTEX;
	n_obj = NORMAL;
}

vec2 closer(vec2 best, vec2 o) {
	return dot(o, o) < dot(best, best) ? o : best;
}

// Offset from the nearest pip centre of face v (pips on a 3x3 grid, as PIPS in index.html).
vec2 nearest_pip(int v, vec2 uv, float g) {
	vec2 b = vec2(9.0);
	if (v == 1 || v == 3 || v == 5) b = closer(b, uv);
	if (v >= 2) { b = closer(b, uv - vec2(-g, g)); b = closer(b, uv - vec2(g, -g)); }
	if (v >= 4) { b = closer(b, uv - vec2(g, g)); b = closer(b, uv - vec2(-g, -g)); }
	if (v == 6) { b = closer(b, uv - vec2(-g, 0.0)); b = closer(b, uv - vec2(g, 0.0)); }
	return b;
}

void fragment() {
	vec3 p = p_obj / half_size;
	vec3 a = abs(p);
	int v; vec2 uv; vec3 tx; vec3 ty;
	if (a.z >= a.x && a.z >= a.y) {
		ty = vec3(0.0, 1.0, 0.0);
		if (p.z > 0.0) { v = 1; tx = vec3(1.0, 0.0, 0.0); } else { v = 6; tx = vec3(-1.0, 0.0, 0.0); }
	} else if (a.x >= a.y) {
		ty = vec3(0.0, 1.0, 0.0);
		if (p.x > 0.0) { v = 2; tx = vec3(0.0, 0.0, -1.0); } else { v = 5; tx = vec3(0.0, 0.0, 1.0); }
	} else {
		tx = vec3(1.0, 0.0, 0.0);
		if (p.y > 0.0) { v = 3; ty = vec3(0.0, 0.0, -1.0); } else { v = 4; ty = vec3(0.0, 0.0, 1.0); }
	}
	uv = vec2(dot(p, tx), dot(p, ty)) * 0.5;
	float r = v == 1 ? 0.155 : 0.1;
	vec2 o = nearest_pip(v, uv, 0.25);
	float d = length(o);
	float w = clamp(fwidth(d), 0.002, 0.025);   // clamped: d jumps where the faces meet
	float inside = 1.0 - smoothstep(r - w, r + w, d);
	float rim = (1.0 - smoothstep(r, r * 1.35, d)) * (1.0 - inside);
	float border = smoothstep(0.4, 0.5, max(abs(uv.x), abs(uv.y)));
	vec3 col = mix(body.rgb, edge.rgb, border * 0.35 + rim * 0.5);
	col = mix(col, v == 1 ? one.rgb : pip.rgb, inside);
	// a shallow dish: the normal leans towards the pip's centre inside it and on its rim
	float slope = d < r ? 0.85 * d / r : 0.85 * (1.0 - smoothstep(r, r * 1.3, d));
	vec3 lean = (tx * o.x + ty * o.y) / max(d, 0.0001);
	vec3 n = normalize(normalize(n_obj) - lean * slope);
	NORMAL = normalize(mat3(VIEW_MATRIX) * (MODEL_NORMAL_MATRIX * n));
	ALBEDO = col;
	ROUGHNESS = mix(0.32, 0.12, inside);
	SPECULAR = mix(0.45, 0.7, inside);
}
"""

var viewport: SubViewport
static var _shader: Shader
var view: TextureRect                  # shows the rendered die, over the padded rect
var glow: TextureRect
var hand: TextureRect                  # the pointer hint (ic_hand) after IDLE_HINT s
var caption: PanelContainer            # the name pill under the die (set_caption); hidden while empty
var _caption_label: Label
var _caption_style: StyleBoxFlat
var fill := DIE_FILL                   # the die's share of the control's height (set before it enters the tree)
var tint := Palette.HONEY              # glow colour while active (set_tint)
var hop: Node3D                        # height, squash and pulse
var die: MeshInstance3D                # tumble rotation (inside the tilted pose)
var shadow: MeshInstance3D
var shadow_core: MeshInstance3D
var camera: Camera3D
var mat: ShaderMaterial
var value := 6
var active := false
var rolling := false
var _roll_tw: Tween
var _t := 0.0
var _height := 0.0
var _squash := 0.0
var _last_press := 0
var _idle := 0.0                       # seconds active and waiting
var _pop := 0.0                        # landing pop (1 -> 0)
var ready_pose := false                ## the die shows the neutral pose (show_ready), not a result
var _ready_tw: Tween
var _ready_k := 0.0                    # 0 = face-on, 1 = the neutral pose (eases the size with the turn)

func _init() -> void:
	custom_minimum_size = Vector2(84, 84)
	mouse_filter = Control.MOUSE_FILTER_STOP
	stretch = false                    # the view is sized by hand at the screen's pixel density (see _layout)

func _ready() -> void:
	glow = TextureRect.new()
	glow.texture = MeshKit.soft_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate = Color(Palette.HONEY, 0.0)
	add_child(glow)
	view = TextureRect.new()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	view.add_child(viewport)           # not a direct child of the container: it is drawn by `view`, scaled down
	_build_world()
	view.texture = viewport.get_texture()
	hand = TextureRect.new()
	hand.texture = UIKit.svg("ic_hand")
	hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hand.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand.visible = false
	add_child(hand)
	_build_caption()
	resized.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	_layout()
	if ready_pose:
		show_ready()
	else:
		show_face(value)
	set_active(false)

func _build_world() -> void:
	var world := Node3D.new()
	viewport.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#fff4e6")
	env.ambient_light_energy = 0.72
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#fff8ee")
	sm.sky_horizon_color = Color("#f3dcc4")
	sm.ground_bottom_color = Color("#6b4a3a")
	sm.ground_horizon_color = Color("#d9b99c")
	sky.sky_material = sm
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	camera = Camera3D.new()
	camera.environment = env
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL   # no perspective: the landed face reads as a flat square
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	world.add_child(camera)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-32), 0)
	key.light_energy = 1.0
	key.light_color = Color("#fffaf0")
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15), deg_to_rad(70), 0)
	fill.light_energy = 0.3
	fill.light_color = Color("#ffe6cf")
	world.add_child(fill)
	var blob := GradientTexture2D.new()
	blob.gradient = Gradient.new()
	blob.gradient.offsets = PackedFloat32Array([0.0, 0.28, 0.58, 0.85])
	blob.gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.15), Color(1, 1, 1, 0)])
	blob.gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	blob.fill = GradientTexture2D.FILL_RADIAL
	blob.fill_from = Vector2(0.5, 0.5)
	blob.fill_to = Vector2(1.0, 0.5)
	var shadow_mat := MeshKit.unlit(Color(0.3, 0.15, 0.2, 0.3), blob)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var stage := Node3D.new()
	stage.rotation.x = PITCH
	world.add_child(stage)
	# a soft drop shadow behind the die (a face-on camera can't see a shadow on the ground)
	shadow = MeshKit.put(stage, MeshKit.plane(1.9, 1.9), shadow_mat, Vector3(0.05, -0.1, -0.7), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	var core_mat := MeshKit.unlit(Color(0.2, 0.09, 0.12, 0.62), blob)
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_core = MeshKit.put(stage, MeshKit.plane(1.35, 1.35), core_mat, Vector3(0.04, -0.08, -0.69), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	hop = Node3D.new()
	stage.add_child(hop)
	var pose := Node3D.new()
	pose.rotation = TILT
	hop.add_child(pose)
	mat = ShaderMaterial.new()
	if _shader == null:                       # one shader for every die (compiling one costs 110-220 ms)
		_shader = Shader.new()
		_shader.code = SHADER
	mat.shader = _shader
	die = MeshKit.put(pose, MeshKit.rbox(1, 1, 1, 0.17, 5), mat, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)

## Lays out the padded view and the hand hint, and sizes the render to the screen pixels it covers.
func _layout() -> void:
	if view == null:
		return
	var s := size
	var rect := Rect2(-s.x * PAD.x, -s.y * PAD.y, s.x * (1.0 + PAD.x + PAD.z), s.y * (1.0 + PAD.y + PAD.w))
	view.position = rect.position
	view.size = rect.size
	var g := s * 1.5
	glow.position = (s - g) / 2.0
	glow.size = g
	var k := clampf((get_viewport().get_final_transform() * get_global_transform_with_canvas()).get_scale().y, 1.0, 4.0)
	viewport.size = Vector2i(maxi(int(rect.size.x * k), 8), maxi(int(rect.size.y * k), 8))
	# camera: the resting die fills DIE_FILL of the control's height and sits on the control's centre
	var unit := s.y * fill                         # pixels per die size
	var world_h := rect.size.y / unit
	camera.size = world_h
	camera.position = Vector3(0, 0, 6.0)
	camera.v_offset = ((s.y * PAD.y + s.y / 2.0) - rect.size.y / 2.0) / unit
	camera.rotation = Vector3.ZERO
	var hs := maxf(s.y * 0.62, 30.0)
	hand.size = Vector2(hs, hs)
	hand.pivot_offset = Vector2(hs * 0.38, hs * 0.1)        # the fingertip
	_layout_caption()

func _process(delta: float) -> void:
	_t += delta
	var pulse := 0.0
	var waiting := active and not rolling
	_idle = _idle + delta if waiting else 0.0
	if waiting:
		pulse = (sin(_t * TAU / 1.1) + 1.0) / 2.0
	_pop = maxf(0.0, _pop - delta / 0.28)
	var sq := _squash
	var pop := sin(_pop * PI) * 0.14 if _pop > 0.0 else 0.0
	var sc := (1.0 + pulse * 0.07 + pop) * lerpf(1.0, READY_SCALE, _ready_k)
	hop.scale = Vector3(sc * (1.0 + sq * 0.6), sc * (1.0 - sq), sc * (1.0 + sq * 0.6))
	hop.position.y = _height * HOP - sq * 0.5
	var lift := clampf(_height, 0.0, 1.0)
	var spread := 1.0 + lift * 0.08
	shadow.scale = Vector3(spread, 1, spread) * (1.0 + sq * 0.2)
	shadow_core.scale = Vector3(1, 1, 1) * (1.0 - lift * 0.3 + sq * 0.15)
	shadow.transparency = lift * 0.55
	shadow_core.transparency = lift * 0.85
	if waiting:
		glow.modulate = Color(tint, 0.3 + pulse * 0.32)
	else:
		glow.modulate = Color(tint, 0.0)
	_hand_hint(waiting and _idle >= IDLE_HINT)

## The hand pointer: slides in over the die's lower right and taps it once every 1.2 s.
func _hand_hint(on: bool) -> void:
	if hand == null:
		return
	if not on:
		hand.visible = false
		return
	var k := fmod(_idle - IDLE_HINT, 1.2) / 1.2
	var press := sin(clampf(k / 0.35, 0.0, 1.0) * PI)      # a tap in the first third of each cycle
	var fade := clampf((_idle - IDLE_HINT) / 0.25, 0.0, 1.0)
	hand.visible = true
	hand.modulate.a = fade
	var s := size
	hand.position = Vector2(s.x * 0.52, s.y * 0.5) + Vector2(-3, -5) * press
	hand.scale = Vector2.ONE * (1.0 - 0.1 * press)


# ---------- public API ----------

## Rolls to face v: a hop with a few full tumbles that settle on v, then a squash and a small bounce.
## Takes ~0.75 s * speed; await it.
func roll(v: int, speed := 1.0) -> void:
	var dur := 0.75 * maxf(speed, 0.05)
	rolling = true
	ready_pose = false
	if _ready_tw:
		_ready_tw.kill()
	_ready_k = 0.0
	_idle = 0.0
	view.modulate = Color.WHITE
	var from := _wrapped(die.rotation)
	var to: Vector3 = FACE_EULER[clampi(v, 1, 6)]
	to += Vector3(TAU * (2 + randi() % 2), TAU * (1 + randi() % 2) * (1 if randf() < 0.5 else -1), TAU * (randi() % 2))
	var tw := create_tween()
	_roll_tw = tw
	tw.tween_method(_roll_step.bind(from, to), 0.0, 1.0, dur)
	await tw.finished
	value = v
	show_face(v)
	_height = 0.0
	_squash = 0.0
	_pop = 1.0
	rolling = false
	set_active(active)

## A tumble still running ends now (a snapshot replaced the state under it): the die lands on its face at once and
## roll()'s caller carries on.
func finish_roll() -> void:
	if rolling and _roll_tw and _roll_tw.is_valid():
		_roll_tw.custom_step(100.0)

## Shows face v at once.
func show_face(v: int) -> void:
	value = clampi(v, 1, 6)
	ready_pose = false
	if _ready_tw:
		_ready_tw.kill()
	_ready_k = 0.0
	if die:
		die.rotation = FACE_EULER[value]

## The neutral waiting pose: a random face turned to a three-quarter view (three faces at an angle), eased in over
## 0.22 s (at once with reduce motion or before the die is built). The next roll() tumbles from it as usual.
func show_ready() -> void:
	ready_pose = true
	if die == null:
		return
	var face := Basis.from_euler(FACE_EULER[randi_range(1, 6)])
	var to := _wrapped((Basis(Vector3.RIGHT, READY_TIP) * Basis(Vector3.UP, READY_TURN) * face).get_euler())
	if _ready_tw:
		_ready_tw.kill()
	if PlayerTile._pref("reduce_motion") or not is_inside_tree():
		die.rotation = to
		_ready_k = 1.0
		return
	_ready_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_parallel(true)
	_ready_tw.tween_property(die, "rotation", to, 0.22).from(_wrapped(die.rotation))
	_ready_tw.tween_property(self, "_ready_k", 1.0, 0.22)

## The human's turn: pulse, glow and (after IDLE_HINT s) the hand pointer. Off: still and a little dimmer.
func set_active(on: bool) -> void:
	if on != active:
		_idle = 0.0
	active = on
	if view == null:
		return
	view.modulate = Color.WHITE if on or rolling else Color(0.9, 0.89, 0.88, 0.95)

## The glow colour while active (the current player's colour).
func set_tint(c: Color) -> void:
	tint = c
	if _caption_style:
		_caption_style.border_color = c

## Whose turn it is, in one call: the glow in the player's colour `c`, active (pulse, glow, hand hint) when they may
## roll now, and an optional caption under the die ("" hides it). text_color: the caption's ink (default INK_STRONG;
## pass the player's name colour, e.g. PlayerTile.name_color(c)).
func set_turn(c: Color, can_tap: bool, caption_text := "", text_color: Variant = null) -> void:
	set_tint(c)
	set_active(can_tap)
	set_caption(caption_text, text_color)

## A small pill under the die (white, rimmed in the tint colour): whose turn it is. "" hides it.
func set_caption(text: String, text_color: Variant = null) -> void:
	if caption == null:
		return
	caption.visible = text != ""
	_caption_label.text = text
	_caption_label.add_theme_color_override("font_color", text_color if text_color is Color else Palette.INK_STRONG)
	_layout_caption()

## The hand pointer is up (active, untouched for IDLE_HINT s): a pad or a frame around the die can pulse with it.
func hinting() -> bool:
	return active and not rolling and _idle >= IDLE_HINT

## Dice skin colours (SKINS in index.html): body, edge shade, pips, and the single pip of the 1.
func set_skin(bg: Color, edge: Color, pip: Color, one: Color) -> void:
	mat.set_shader_parameter("body", bg)
	mat.set_shader_parameter("edge", edge)
	mat.set_shader_parameter("pip", pip)
	mat.set_shader_parameter("one", one)


# ---------- internals ----------

func _build_caption() -> void:
	caption = PanelContainer.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_style = UIKit.box(Palette.CARD, UIKit.R.pill, UIKit.BW.line, tint)
	UIKit.shade(_caption_style, "sm")
	UIKit.pad(_caption_style, UIKit.SPACE.sm + 2, 1)
	caption.add_theme_stylebox_override("panel", _caption_style)
	_caption_label = UIKit.label("", UIKit.FS.label, Palette.INK_STRONG, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_child(_caption_label)
	caption.visible = false
	add_child(caption)

## The caption sits centred just under the control.
func _layout_caption() -> void:
	if caption == null or not caption.visible:
		return
	caption.size = Vector2.ZERO
	var m := caption.get_combined_minimum_size()
	caption.size = m
	caption.position = Vector2(round((size.x - m.x) / 2.0), size.y + UIKit.SPACE.sm)

func _roll_step(t: float, from: Vector3, to: Vector3) -> void:
	# height like the CSS "hop" keyframes: up, land at 60 %, a small second bounce, settle
	if t < 0.6:
		_height = sin(t / 0.6 * PI) * (1.0 - t * 0.25)
	elif t < 0.92:
		_height = sin((t - 0.6) / 0.32 * PI) * 0.22
	else:
		_height = 0.0
	_squash = _impact(t, 0.6, 0.16) + _impact(t, 0.92, 0.07)
	var p := clampf(t / 0.62, 0.0, 1.0)
	p = 1.0 - pow(1.0 - p, 3.0)
	var rot := from.lerp(to, p)
	if t > 0.6:                                    # a little rock as it lands
		var k := (t - 0.6) / 0.4
		rot.z += sin(k * TAU * 1.5) * 0.12 * (1.0 - k)
		rot.x += sin(k * TAU * 1.5 + 1.0) * 0.06 * (1.0 - k)
	die.rotation = rot

## Squash pulse after a landing at t0: quick in, springy out.
func _impact(t: float, t0: float, amount: float) -> float:
	if t < t0:
		return 0.0
	var k := (t - t0) / 0.14
	if k > 1.0:
		return 0.0
	return amount * sin(k * PI) * (1.0 - k * 0.3)

static func _wrapped(r: Vector3) -> Vector3:
	return Vector3(wrapf(r.x, -PI, PI), wrapf(r.y, -PI, PI), wrapf(r.z, -PI, PI))

func _gui_input(event: InputEvent) -> void:
	var hit := false
	if event is InputEventScreenTouch and event.pressed:
		hit = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hit = event.device != InputEvent.DEVICE_ID_EMULATION
	if hit and Time.get_ticks_msec() - _last_press > 200:
		_last_press = Time.get_ticks_msec()
		accept_event()
		pressed.emit()
