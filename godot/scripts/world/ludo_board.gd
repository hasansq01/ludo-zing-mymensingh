class_name LudoBoard
extends Node3D
## The Ludo board on the table and its 16 pawns (index.html: boardTexture, frame, toks, gridOf, relayout, move()).
## Pure presentation: it shows a LudoRules state and animates the events the rules return.

const TRACK := [[1,6],[2,6],[3,6],[4,6],[5,6],[6,5],[6,4],[6,3],[6,2],[6,1],[6,0],[7,0],[8,0],[8,1],[8,2],[8,3],[8,4],[8,5],[9,6],[10,6],[11,6],[12,6],[13,6],[14,6],[14,7],[14,8],[13,8],[12,8],[11,8],[10,8],[9,8],[8,9],[8,10],[8,11],[8,12],[8,13],[8,14],[7,14],[6,14],[6,13],[6,12],[6,11],[6,10],[6,9],[5,8],[4,8],[3,8],[2,8],[1,8],[0,8],[0,7],[0,6]]
const HOME := [
	[[1,7],[2,7],[3,7],[4,7],[5,7]],
	[[7,1],[7,2],[7,3],[7,4],[7,5]],
	[[13,7],[12,7],[11,7],[10,7],[9,7]],
	[[7,13],[7,12],[7,11],[7,10],[7,9]],
]
const BASE := [[0,0],[9,0],[9,9],[0,9]]
const FIN := [{x = 6.55, y = 7.5, ax = "y"}, {x = 7.5, y = 6.55, ax = "x"}, {x = 8.45, y = 7.5, ax = "y"}, {x = 7.5, y = 8.45, ax = "x"}]
const TOP := 0.3                       # board surface height
const PAIR_SIDE := 0.2                 # pair tokens stand side by side, this far from the square's centre
const PAWN_PROFILE := [[0,0],[.37,0],[.38,.05],[.33,.1],[.23,.16],[.17,.3],[.13,.47],[.24,.51],[.24,.56],[.12,.6],[0,.6]]

var top_mesh: MeshInstance3D
var toks := []                         # toks[c][i] = {node, mat, ring, pair_ring, target, scale, anim, paired, skin ...}
var skins := ["classic", "classic", "classic", "classic"]   ## the pawn skin of each colour (set_skins)
var movable := {}                      # c * 4 + i -> true: glowing pawns the player may tap
var speed := 1.0                       # animation speed factor (Settings: Relaxed 1 / Fast 0.55)
var fx: Node3D
var _gen := 0                          # bumped by cancel_all(): walks of an earlier game stop

func _ready() -> void:
	var frame := MeshKit.put(self, MeshKit.rbox(16.8, 0.6, 16.8, 0.28), MeshKit.mat(Color("#fff6ee"), 0.3), Vector3(0, -0.02, 0))
	frame.name = "Frame"
	MeshKit.put(self, MeshKit.rbox(17.3, 0.32, 17.3, 0.15), MeshKit.mat(Color("#f2b46e"), 0.3), Vector3(0, -0.16, 0))
	MeshKit.contact_shadow(self, 20.4, 20.4, Vector3(-0.1, TableWorld.TT + 0.035, -0.25), Color(0.24, 0.13, 0.07, 0.42), true)
	top_mesh = MeshKit.put(self, MeshKit.plane(15, 15), MeshKit.mat(Color("#fffaf3"), 0.55), Vector3(0, TOP + 0.002, 0), Vector3.ZERO, Vector3.ONE, false)
	fx = Node3D.new()
	add_child(fx)
	PawnSkins.warm_swatch(self, Vector3(0, 0.0, 0))  # inside the frame: never seen, keeps the finish shader compiled
	_build_pawns()
	relayout(null)

func set_texture(tex: Texture2D) -> void:
	top_mesh.material_override = MeshKit.tex_mat(tex, 0.55)


# ---------- board texture ----------

static func paint(c: Control) -> void:
	var S: float = c.size.x
	var u := S / 15.0
	var cream := Color("#fffaf3")
	c.draw_rect(Rect2(0, 0, S, S), cream)
	for col in 4:
		var bx: int = BASE[col][0]
		var by: int = BASE[col][1]
		var cc: Color = Palette.PLAYER[col]
		c.draw_rect(Rect2(bx * u, by * u, 6 * u, 6 * u), cc)
		TexBaker.round_rect(c, Rect2((bx + 1) * u, (by + 1) * u, 4 * u, 4 * u), u * 0.45, cream)
		for i in 4:
			var g := grid_of(col, -1, i)
			TexBaker.circle(c, g * u, u * 0.62, Palette.TINT[col])
			TexBaker.ring(c, g * u, u * 0.62 - u * 0.045, u * 0.09, cc)
		for h in HOME[col]:
			c.draw_rect(Rect2(h[0] * u, h[1] * u, u, u), cc)
		var s: Array = TRACK[LudoRules.OFF[col]]
		c.draw_rect(Rect2(s[0] * u, s[1] * u, u, u), cc)
		c.draw_colored_polygon(TexBaker.star_points(Vector2(s[0] + 0.5, s[1] + 0.5) * u, u * 0.32), cream)
	for k in LudoRules.STARS:
		var t: Array = TRACK[k]
		c.draw_colored_polygon(TexBaker.star_points(Vector2(t[0] + 0.5, t[1] + 0.5) * u, u * 0.34), Color("#d9c3cf"))
	# centre triangles
	var C := Vector2(7.5, 7.5) * u
	var tri := [[[6, 6], [6, 9]], [[6, 6], [9, 6]], [[9, 6], [9, 9]], [[6, 9], [9, 9]]]
	for col in 4:
		var a: Array = tri[col][0]
		var b: Array = tri[col][1]
		c.draw_colored_polygon(PackedVector2Array([Vector2(a[0], a[1]) * u, Vector2(b[0], b[1]) * u, C]), Palette.PLAYER[col])
	# grid lines over the track and home columns
	var line := Color(110 / 255.0, 70 / 255.0, 95 / 255.0, 0.38)
	var cells: Array = TRACK.duplicate()
	for col in 4:
		cells.append_array(HOME[col])
	for cell in cells:
		c.draw_rect(Rect2(cell[0] * u, cell[1] * u, u, u), line, false, 4.0)
	c.draw_rect(Rect2(6 * u, 6 * u, 3 * u, 3 * u), line, false, 4.0)
	for b in BASE:
		c.draw_rect(Rect2(b[0] * u, b[1] * u, 6 * u, 6 * u), line, false, 4.0)
	c.draw_rect(Rect2(4, 4, S - 8, S - 8), line, false, 8.0)


# ---------- grid -> world ----------

static func grid_of(c: int, p: int, i: int) -> Vector2:
	if p < 0:
		var b: Array = BASE[c]
		return Vector2(b[0] + 2 + (i % 2) * 2, b[1] + 2 + (i / 2) * 2)
	if p <= 50:
		var t: Array = TRACK[LudoRules.abs_index(c, p)]
		return Vector2(t[0] + 0.5, t[1] + 0.5)
	if p < LudoRules.GOAL:
		var h: Array = HOME[c][p - 51]
		return Vector2(h[0] + 0.5, h[1] + 0.5)
	var f: Dictionary = FIN[c]
	var o := (i - 1.5) * 0.46
	return Vector2(f.x, f.y + o) if f.ax == "y" else Vector2(f.x + o, f.y)

static func to_world(g: Vector2) -> Vector3:
	return Vector3(g.x - 7.5, TOP, g.y - 7.5)


# ---------- pawns ----------

const PAWN_SCALE := 1.18               # pawns a little bigger than the web's (they still fit a square)
## 3D View: taller, slightly wider pawns (Ludo King-style pins) so they read at phone size; the foot stays inside a
## square (0.74 x 1.18 x 1.1 = 0.96 cells). Top View keeps the plain proportions (eased with the camera).
const TALL_XZ := 1.1
const TALL_Y := 1.42
## Units (a pawn, or a pair's two pawns) sharing a square fan out across the screen (camera-right), the middle one
## of three set behind so every head shows: offsets in cells (right, towards the camera) and the pawn scale for 1..4
## units; 5+ stand on a ring. A pair's pawns stand PAIR_GAP either side of their unit's spot.
const FAN := {
	1: [[Vector2.ZERO], 1.0],
	2: [[Vector2(-0.25, 0.04), Vector2(0.25, -0.04)], 0.86],
	3: [[Vector2(-0.3, 0.14), Vector2(0.0, -0.2), Vector2(0.3, 0.14)], 0.78],
	4: [[Vector2(-0.25, -0.22), Vector2(0.25, -0.22), Vector2(-0.25, 0.22), Vector2(0.25, 0.22)], 0.7],
}
const RING_R := 0.34
const RING_SCALE := 0.56
const PAIR_GAP := 0.17
const PAIR_SCALE := 0.82               # a pair alone on its square
const BOB := 0.22                      # movable pawns bob this high (world units) ...
const BOB_SEC := 0.6                   # ... once per this many seconds
const DIM := 0.4                       # pawns of the mover that can't move: albedo darkened by this (≈ 60 %)
const STEP_SEC := 0.11                 # one square of a walk (× speed)
const LEAVE_SEC := 0.22                # the hop out of the base (× speed)
const FLY_SEC := 0.55                  # a captured pawn's arc back to its base (× speed)

func _build_pawns() -> void:
	var ring_mesh := MeshKit.torus(0.56, 0.12, 48, 10)
	var halo_mesh := MeshKit.plane(HALO_W, HALO_W)     # x pawn scale: about 2.2 squares across in either view
	var pair_mesh := MeshKit.torus(0.4, 0.07, 40, 10)
	var ring_mat := MeshKit.unlit(Palette.GOLD)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.render_priority = 1
	var halo_mat := MeshKit.unlit(Palette.GOLD, MeshKit.soft_texture())
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var arrow_tex := _arrow_texture()
	var badge_tex := _pair_badge_texture()
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Palette.GOLD; gold.metallic = 0.7; gold.roughness = 0.25
	gold.emission_enabled = true; gold.emission = Palette.GOLD; gold.emission_energy_multiplier = 0.15
	for c in 4:
		var row := []
		for i in 4:
			var g := Node3D.new()
			g.name = "Pawn%d_%d" % [c, i]
			add_child(g)
			var look := PawnSkins.dress(g, skins[c], Palette.PLAYER[c])   # its own materials: each glows / dims on its own
			var halo := MeshKit.put(g, halo_mesh, halo_mat.duplicate(), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3.ONE, false)
			halo.visible = false
			var ring := MeshKit.put(g, ring_mesh, ring_mat.duplicate(), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3.ONE, false)
			ring.visible = false
			var pr := MeshKit.put(g, pair_mesh, gold, Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE, false)
			pr.visible = false
			var arrow := Sprite3D.new()          # the "move me" chevron over a movable pawn (on the board, not the
			arrow.texture = arrow_tex             # pawn: the same size whatever the pawn's scale)
			arrow.pixel_size = ARROW_W / 96.0
			arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			arrow.no_depth_test = true
			arrow.render_priority = 3
			arrow.visible = false
			arrow.name = "Arrow%d_%d" % [c, i]
			add_child(arrow)
			var badge := Sprite3D.new()          # "x2" over a pair (shown on the pair's first pawn)
			badge.texture = badge_tex
			badge.pixel_size = BADGE_W / 112.0
			badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			badge.no_depth_test = true
			badge.render_priority = 2
			badge.visible = false
			badge.name = "PairBadge%d_%d" % [c, i]
			add_child(badge)
			var sym := Sprite3D.new()            # colour-blind symbol over the head (pref colorblind)
			sym.texture = UIKit.svg("sym_" + str(Palette.SYMBOL[c]))
			sym.pixel_size = 0.36 / 192.0
			sym.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sym.position = Vector3(0, 1.16, 0)
			sym.visible = false
			g.add_child(sym)
			var sh := MeshKit.contact_shadow(self, 1.0, 1.0, t_shadow_pos(to_world(grid_of(c, -1, i))), PAWN_SHADOW)
			var t := {c = c, i = i, node = g, ring = ring, halo = halo, pair_ring = pr, sym = sym, arrow = arrow, shadow = sh,
				badge = badge, mate = {}, cell = to_world(grid_of(c, -1, i)), fan = Vector2.ZERO,
				target = to_world(grid_of(c, -1, i)), scale = 1.0, anim = false, paired = false,
				pos = Vector3.ZERO, dim = 0.0, squash = 0.0, cur_scale = 1.0}
			_wear(t, skins[c], look)
			t.pos = t.target
			g.position = t.target
			row.append(t)
		toks.append(row)
	# colour-blind symbols in the middle of each base (between its four circles)
	for c in 4:
		var q := MeshKit.put(self, MeshKit.plane(1.5, 1.5), MeshKit.unlit(Color.WHITE, UIKit.svg("sym_" + str(Palette.SYMBOL[c]))),
			to_world(Vector2(BASE[c][0] + 3, BASE[c][1] + 3)) + Vector3(0, 0.006, 0), Vector3.ZERO, Vector3.ONE, false)
		q.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		q.visible = false
		_base_syms.append(q)

## Each colour's pawn skin (Catalog.PAWNS ids; "" or unknown = Classic): ids[c]. Only colours whose skin changed are
## dressed again; their glow, dim, halo, ring, chevron, pair badge and colour-blind symbol carry on as before.
func set_skins(ids: Array) -> void:
	for c in 4:
		var id := str(ids[c]) if c < ids.size() else ""
		if Catalog.pawn(id).is_empty():
			id = Catalog.FREE_PAWN
		if id == skins[c]:
			continue
		skins[c] = id
		for t: Dictionary in toks[c]:
			PawnSkins.undress(t.look)
			_wear(t, id, PawnSkins.dress(t.node, id, Palette.PLAYER[c]))

## Points pawn t at the parts PawnSkins.dress built (its materials, body, head, height).
func _wear(t: Dictionary, id: String, look: Dictionary) -> void:
	t.skin = id
	t.look = look
	t.mat = look.mat
	t.base = look.base
	t.accents = look.accents
	t.body = look.body
	t.head = look.head
	t.over = float(look.top) - PawnSkins.CLASSIC_TOP     # how much taller than Classic (the chevron, the symbol)
	(t.mat as StandardMaterial3D).emission_energy_multiplier = 0.0

const HALO_W := 1.75                   # the glow under a movable pawn, x the pawn's scale (≈ 2.2 squares)
const ARROW_W := 1.36                  # the chevron's width in world units (1.6x the old 0.85)
const BADGE_W := 0.95                  # the pair badge's width in world units

## A bold gold chevron with a white rim, pointing down (96 px wide).
static func _arrow_texture() -> Texture2D:
	var svg := ('<svg xmlns="http://www.w3.org/2000/svg" width="96" height="80" viewBox="0 0 48 40">'
		+ '<path d="M5 7 L24 34 L43 7 L24 15 Z" fill="#%s" stroke="#ffffff" stroke-width="3.2" stroke-linejoin="round"/></svg>') % [
		Palette.GOLD.to_html(false)]
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## The "x2" pair badge: a gold pill with a white rim and a white "x2" drawn as strokes (112 x 64 px).
static func _pair_badge_texture() -> Texture2D:
	var svg := ('<svg xmlns="http://www.w3.org/2000/svg" width="112" height="64" viewBox="0 0 56 32">'
		+ '<rect x="2" y="2" width="52" height="28" rx="14" fill="#%s" stroke="#ffffff" stroke-width="3"/>'
		+ '<path d="M15 10.5 L25 21.5 M25 10.5 L15 21.5" stroke="#ffffff" stroke-width="3.6" stroke-linecap="round"/>'
		+ '<path d="M30.5 12.5 Q31 8.5 35.5 8.5 Q40 8.5 40 12.5 Q40 15.5 35.5 19 L30.5 23.2 L41 23.2" fill="none" stroke="#ffffff"'
		+ ' stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"/></svg>') % [Palette.HONEY_LIP.to_html(false)]
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## The key spot's soft shadow under a pawn: stays on the board while the pawn hops, shrinking and fading with height.
const PAWN_SHADOW := Color(0.2, 0.1, 0.06, 0.5)
const PAWN_SHADOW_SIZE := 1.15          # × the pawn's scale (its foot is 0.74 across)

static func t_shadow_pos(p: Vector3) -> Vector3:
	return Vector3(p.x - 0.04, TOP + 0.012, p.z - 0.1)   # nudged away from the light, which stands at (4, 60, 10)

var _base_syms: Array[MeshInstance3D] = []
var _colorblind := false
var _dim_color := -1                   # the mover whose non-movable pawns are dimmed (-1 none)
var _pulse_at := -10.0                 # pulse_movable(): when the one-off pulse started (seconds)

## Glossy candy-like pawns: a clear coat over the player colour.
static func pawn_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.22
	m.metallic_specular = 0.7
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.12
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.0
	return m

## Place every pawn for state s (null: all at base, all visible). Pawns sharing a square fan out across the screen
## (FAN; a pair's two pawns stay next to each other) so none hides another; a pair also gets its "x2" badge.
func relayout(s) -> void:
	var cells := {}
	for row in toks:
		for t in row:
			var c: int = t.c
			var i: int = t.i
			t.node.visible = s == null or LudoRules.active(s, c)
			t.paired = false
			t.mate = {}
			t.fan = Vector2.ZERO
			if s == null:
				t.cell = to_world(grid_of(c, -1, i)); t.scale = PAWN_SCALE
				continue
			var p: int = s.tok[c][i]
			t.cell = to_world(grid_of(c, p, i))
			t.scale = (0.62 if p >= LudoRules.GOAL else 1.0) * PAWN_SCALE
			if p >= 0 and p < LudoRules.GOAL and t.node.visible:
				var q := LudoRules.pair_of(s, c, i)
				t.paired = not q.is_empty()
				var key := ("t%d" % LudoRules.abs_index(c, p)) if p <= 50 else ("h%d_%d" % [c, p])
				if not cells.has(key):
					cells[key] = []
				if q.is_empty():
					cells[key].append([t])
				elif q.a == i:
					cells[key].append([toks[c][q.a], toks[c][q.b]])
					toks[c][q.a].mate = toks[c][q.b]
	for units in cells.values():
		var n: int = units.size()
		if n == 3:                                        # a pair takes the back spot, its two heads over the singles
			for k in 3:
				if (units[k] as Array).size() == 2 and k != 1:
					var tmp: Array = units[1]
					units[1] = units[k]
					units[k] = tmp
					break
		for k in n:
			var unit: Array = units[k]
			var spot := Vector2.ZERO
			var sc := 1.0
			if FAN.has(n):
				spot = FAN[n][0][k]
				sc = float(FAN[n][1])
			else:
				var a := (float(k) / n) * TAU
				spot = Vector2(cos(a), sin(a)) * RING_R
				sc = RING_SCALE
			if unit.size() == 2 and n == 1:
				sc = PAIR_SCALE
			for m in unit.size():
				var t: Dictionary = unit[m]
				var side := ((PAIR_GAP if m else -PAIR_GAP) * (sc / PAIR_SCALE)) if unit.size() == 2 else 0.0
				t.fan = spot + Vector2(side, 0)
				t.scale = sc * PAWN_SCALE
	_update_targets()

## Screen-right and towards-the-camera on the board (horizontal unit vectors), from the camera drawing it.
func _view_axes() -> Array:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return [Vector3.RIGHT, Vector3.BACK]
	var b := cam.global_transform.basis
	var right := Vector3(b.x.x, 0, b.x.z)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	return [right, Vector3.UP.cross(right).normalized() * -1.0]     # = screen-down on the board

## Each pawn's resting place: its square plus its fan offset turned to the current view.
func _update_targets() -> void:
	var ax := _view_axes()
	for row in toks:
		for t in row:
			var f: Vector2 = t.fan
			t.target = (t.cell as Vector3) + (ax[0] as Vector3) * f.x + (ax[1] as Vector3) * f.y

## A new game (or leaving one): stop every walk in progress and let the pawns settle.
func cancel_all() -> void:
	_gen += 1
	for row in toks:
		for t in row:
			t.anim = false

## The glowing pawns (keys c * 4 + i) the player may tap. dim_color >= 0: that colour's other pawns dim.
func set_movable(keys: Array, dim_color := -1) -> void:
	movable.clear()
	for k in keys:
		movable[k] = true
	_dim_color = dim_color if not keys.is_empty() else -1

## The glowing pawns pulse once (a tap that missed them).
func pulse_movable() -> void:
	_pulse_at = Time.get_ticks_msec() / 1000.0

## Where pawn key (c * 4 + i) stands now, a little above its base (for pops and tap logs).
func pawn_point(key: int) -> Vector3:
	var t: Dictionary = toks[key / 4][key % 4]
	return t.node.global_position + Vector3(0, 0.45, 0)

## Where pawn key is going (its resting place once the board settles), in world space.
func pawn_target(key: int) -> Vector3:
	var t: Dictionary = toks[key / 4][key % 4]
	return to_global(t.target) + Vector3(0, 0.45, 0)

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var pulse := (sin(now * TAU / 1.1) + 1.0) / 2.0
	var kick := clampf(1.0 - (now - _pulse_at) / 0.45, 0.0, 1.0)    # pulse_movable(): a one-off swell
	kick = sin(kick * PI) if kick > 0.0 else 0.0
	var k := 1.0 - pow(0.78, delta * 60.0)        # the web version's lerp(.22) per frame, frame-rate independent
	var ks := 1.0 - pow(0.8, delta * 60.0)
	var kd := 1.0 - pow(0.85, delta * 60.0)
	var cb := _pref("colorblind")
	if cb != _colorblind:
		_colorblind = cb
		for q in _base_syms:
			q.visible = cb
	var still := _pref("reduce_motion")
	var still_skin := not PawnSkins.moving(still)
	# 3D View (tall pawns) .. Top View (plain), following the camera's elevation
	var w := get_parent() as TableWorld
	var top_k := 0.0
	if w:
		top_k = clampf((w.cam_el - TableWorld.GAME_EL) / (TableWorld.TOP_EL - TableWorld.GAME_EL), 0.0, 1.0)
	var txz := lerpf(TALL_XZ, 1.0, top_k)
	var ty := lerpf(TALL_Y, 1.0, top_k) / txz      # extra height of the body, inside the pawn's uniform scale
	_update_targets()
	var cam := get_viewport().get_camera_3d()
	var cam_up := Vector3.FORWARD
	if cam:
		var cu := cam.global_transform.basis.y
		cam_up = Vector3(cu.x, 0, cu.z).normalized() if Vector2(cu.x, cu.z).length() > 0.01 else Vector3.FORWARD
	for row in toks:
		for t in row:
			var g: Node3D = t.node
			var on := movable.has(t.c * 4 + t.i)
			if t.anim:
				t.pos = g.position
			else:
				t.pos = (t.pos as Vector3).lerp(t.target, k)
				var bob := 0.0
				if on and not still:
					bob = (sin(now * TAU / BOB_SEC) * 0.5 + 0.5) * BOB
				g.position = t.pos + Vector3(0, bob, 0)
			t.squash = maxf(0.0, t.squash - delta / 0.14)
			var s: float = t.cur_scale
			s += (t.scale - s) * ks
			t.cur_scale = s
			var sq: float = sin(t.squash * PI) * 0.15 if t.squash > 0.0 else 0.0
			var gs := s * txz
			g.scale = Vector3(gs * (1.0 + sq * 0.7), gs * (1.0 - sq), gs * (1.0 + sq * 0.7))
			(t.body as Node3D).scale = Vector3(1, ty, 1)
			(t.head as Node3D).position.y = 0.74 * ty
			(t.sym as Node3D).position.y = 1.16 * ty + float(t.over)
			PawnSkins.face(g, self, cam)                            # the skin's front towards the camera
			var head_top := g.position.y + (0.93 * ty + float(t.over)) * gs   # world height of the top of the head
			var sh: MeshInstance3D = t.shadow
			sh.visible = g.visible
			if sh.visible:
				var lift := clampf((g.position.y - TOP) / 2.6, 0.0, 1.0)
				sh.position = t_shadow_pos(g.position)
				var ss := gs * PAWN_SHADOW_SIZE * (1.0 + lift * 0.4)
				sh.scale = Vector3(ss, 1, ss)
				sh.material_override.albedo_color.a = PAWN_SHADOW.a * (1.0 - lift * 0.8)
			t.ring.visible = on
			t.halo.visible = on
			var arrow: Sprite3D = t.arrow
			var mate: Dictionary = t.mate
			var second: bool = t.paired and mate.is_empty()           # a pair shows one chevron, over its badge
			arrow.visible = on and g.visible and not second
			if arrow.visible:
				# the chevron floats over the head; in Top View (looking straight down) it moves up the screen
				var hop := (sin(now * TAU / BOB_SEC + 0.6) * 0.5 + 0.5) * (0.0 if still else 0.22)
				var at := g.position
				var over := 0.62
				if t.paired:
					at = (g.position + (mate.node as Node3D).position) / 2.0
					over = 0.7
				arrow.position = Vector3(at.x, head_top + over + hop, at.z) + cam_up * (top_k * (0.95 + hop))
				arrow.modulate.a = 0.9 + pulse * 0.1
				var asz := 1.0 + pulse * 0.08 + kick * 0.35
				arrow.scale = Vector3(asz, asz, asz)
				var rs := 1.0 + pulse * 0.16 + kick * 0.6
				t.ring.scale = Vector3(rs, 1.0, rs)
				t.ring.material_override.albedo_color.a = 0.75 + pulse * 0.25
				var hs := 0.92 + pulse * 0.16 + kick * 0.8
				t.halo.scale = Vector3(hs, 1, hs)
				t.halo.material_override.albedo_color.a = 0.55 + pulse * 0.3 + kick * 0.15
			t.pair_ring.visible = t.paired and not on           # a movable pawn's glowing ring takes its place
			var badge: Sprite3D = t.badge
			badge.visible = t.paired and not mate.is_empty() and g.visible
			if badge.visible:
				var mid: Vector3 = (g.position + (mate.node as Node3D).position) / 2.0
				# beside the pair (screen-right), level with the heads, so the chevron above stays clear
				var side_r: Vector3 = _view_axes()[0]
				badge.position = Vector3(mid.x, head_top - 0.05, mid.z) + side_r * (0.5 * gs / PAWN_SCALE + 0.18)
			t.sym.visible = cb and g.visible
			var want_dim := 1.0 if (_dim_color == t.c and not on) else 0.0
			t.dim += (want_dim - t.dim) * kd
			var m: StandardMaterial3D = t.mat
			m.albedo_color = (t.base as Color).darkened(DIM * t.dim)
			m.emission_energy_multiplier = (0.22 + pulse * 0.38 + kick * 0.4) if on else 0.0
			for a: Dictionary in t.accents:                        # a skin's gold / ears / froth dim with it
				(a.mat as StandardMaterial3D).albedo_color = (a.base as Color).darkened(DIM * t.dim)
			PawnSkins.animate(m, now, still_skin)

static func _pref(key: String) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var save: Node = tree.root.get_node_or_null("Save") if tree and tree.root else null
	if save == null:
		return false
	var pr: Variant = save.get("prefs")
	return pr is Dictionary and bool((pr as Dictionary).get(key, false))

## Screen-space pick: the movable pawn nearest to a tap within `radius` px (or a pawn's on-screen width, if more),
## or -1. The pawns' resting places count, so a bobbing pawn is as easy to hit as a still one.
func pick(cam: Camera3D, screen_pos: Vector2, radius := 44.0) -> int:
	return _nearest(cam, screen_pos, radius, true)

## The nearest visible pawn of colour c to a tap (movable or not), within radius px, or -1.
func pick_any(cam: Camera3D, screen_pos: Vector2, c: int, radius := 30.0) -> int:
	return _nearest(cam, screen_pos, radius, false, c)

func _nearest(cam: Camera3D, screen_pos: Vector2, radius: float, only_movable: bool, color := -1) -> int:
	var best := -1
	var best_d := 1e9
	for row in toks:
		for t in row:
			if not t.node.visible:
				continue
			var key: int = t.c * 4 + t.i
			if only_movable and not movable.has(key):
				continue
			if color >= 0 and t.c != color:
				continue
			var p: Vector3 = to_global(t.pos) + Vector3(0, 0.45, 0)
			if cam.is_position_behind(p):
				continue
			var sp := cam.unproject_position(p)
			var reach := (cam.unproject_position(p + cam.global_transform.basis.x * 0.9) - sp).length()
			var d := sp.distance_to(screen_pos)
			if d < maxf(reach, radius) and d < best_d:
				best_d = d
				best = key
	return best


# ---------- animations (awaitable) ----------

## One arcing hop from a to b; returns the tween (await its `finished` to wait for the landing).
func _hop(t: Dictionary, a: Vector3, b: Vector3, height: float, sec: float) -> Tween:
	var tw := create_tween()
	tw.tween_method(func(k: float):
		var e := k * k * 2.0 if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 2) / 2.0
		var p := a.lerp(b, e)
		p.y = TOP + sin(k * PI) * height
		t.node.position = p, 0.0, 1.0, maxf(0.01, sec * speed))
	return tw

## Walk a unit (one pawn, or both of a pair) square by square from progress `from` to `to`; on_step(q) per square.
## is_paused() holds the walk between squares while the game is paused. Each landing squashes the pawn a little.
func walk(c: int, unit: Array, from: int, to: int, is_pair: bool, on_step: Callable, is_paused := Callable()) -> void:
	var gen := _gen
	var ts := []
	for j in unit:
		ts.append(toks[c][j])
	for t in ts:
		t.anim = true
		t.scale = (0.62 if to >= LudoRules.GOAL else (PAIR_SCALE if is_pair else 1.0)) * PAWN_SCALE
	var q := 0 if from < 0 else from + 1
	while q <= to:
		while is_paused.is_valid() and is_paused.call() and gen == _gen:
			await get_tree().process_frame
		if gen != _gen:
			return
		var b := to_world(grid_of(c, q, unit[0]))
		var hops := []
		for m in ts.size():
			var side := (PAIR_SIDE if m else -PAIR_SIDE) if ts.size() == 2 else 0.0
			hops.append([ts[m], ts[m].node.position, b + Vector3(side, 0, 0)])
		var height := 1.1 if from < 0 else 0.5
		var sec := LEAVE_SEC if from < 0 else STEP_SEC
		for h in hops.slice(1):
			_hop(h[0], h[1], h[2], height, sec)
		await _hop(hops[0][0], hops[0][1], hops[0][2], height, sec).finished
		for t in ts:
			t.squash = 1.0 if q == to else 0.6
		on_step.call(q)
		q += 1
	for t in ts:
		t.pos = t.node.position
		t.anim = false

## Captured pawns: a puff of their colour where they stood, then they fly back to their base in a high arc.
func send_home(victims: Array) -> void:
	for v in victims:
		var t: Dictionary = toks[v[0]][v[1]]
		puff(t.node.position, Palette.PLAYER[v[0]])
		t.anim = true
		t.scale = PAWN_SCALE
		_hop(t, t.node.position, to_world(grid_of(v[0], -1, v[1])), 2.6, FLY_SEC)
	await get_tree().create_timer(maxf(0.01, FLY_SEC * speed) + 0.02).timeout
	for v in victims:
		var t: Dictionary = toks[v[0]][v[1]]
		t.pos = t.node.position
		t.squash = 1.0
		t.anim = false

## A quick burst of `color` (a capture's victim) at `at`.
func puff(at: Vector3, color: Color) -> void:
	var p := _burst(at + Vector3(0, 0.35, 0), color, 30, 0.55, 3.5, 85.0)
	p.gravity = Vector3(0, -2, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	_ring(at, Color.WHITE, 0.35, 1.8, 0.45)

## Two pawns joined into a pair: a gold ring snaps out from the square.
func link_glow(at: Vector3) -> void:
	_ring(at, Palette.GOLD, 0.45, 1.4, 0.5)
	_ring(at, Palette.HONEY, 0.3, 0.9, 0.35)

func _burst(at: Vector3, color: Color, amount: int, life: float, vmax: float, spread: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vmax * 0.45
	p.initial_velocity_max = vmax
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	var m := MeshKit.unlit(Color.WHITE, MeshKit.soft_texture())
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	grad.colors = PackedColorArray([color.lightened(0.5), color, Color(color, 0.0)])
	p.color_ramp = grad
	p.position = at
	fx.add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)
	return p

## A flat ring that grows from r0 to r1 (× its 0.5 base radius) and fades over sec.
func _ring(at: Vector3, color: Color, r0: float, r1: float, sec: float) -> void:
	var ring := MeshKit.put(fx, MeshKit.torus(0.5, 0.06, 48, 8), MeshKit.unlit(color), at + Vector3(0, 0.08, 0), Vector3.ZERO, Vector3.ONE, false)
	ring.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tw := create_tween()
	tw.tween_method(func(k: float):
		var s := r0 + (1.0 - pow(1.0 - k, 3)) * (r1 - r0)
		ring.scale = Vector3(s, 1, s) * 2.0
		ring.material_override.albedo_color.a = (1.0 - k) * 0.9, 0.0, 1.0, sec)
	tw.tween_callback(ring.queue_free)

## Gold + player-colour burst where a pawn reaches the centre (index.html HomeFx).
func home_burst(at: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 46
	p.lifetime = 1.1
	p.explosiveness = 0.92
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.5
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.28, 0.28)
	var m := MeshKit.unlit(Color.WHITE, MeshKit.soft_texture())
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color("#fff3b0"), color, Color(color, 0.0)])
	p.color_ramp = grad
	p.position = at + Vector3(0, 0.4, 0)
	fx.add_child(p)
	p.emitting = true
	# a gold ring that grows and fades
	var ring := MeshKit.put(fx, MeshKit.torus(0.5, 0.06, 48, 8), MeshKit.unlit(Color("#ffd23a")), at + Vector3(0, 0.08, 0), Vector3.ZERO, Vector3.ONE, false)
	ring.material_override = ring.material_override.duplicate()
	ring.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tw := create_tween()
	tw.tween_method(func(k: float):
		var s := 0.4 + (1.0 - pow(1.0 - k, 3)) * 2.4
		ring.scale = Vector3(s, 1, s)
		ring.material_override.albedo_color.a = (1.0 - k) * 0.85, 0.0, 1.0, 1.0)
	tw.tween_callback(ring.queue_free)
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)
