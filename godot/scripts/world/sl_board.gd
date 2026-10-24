class_name SLBoard
extends Node3D
## The Snakes & Ladders board on the café table and its pawns (index.html: SL cellRC / centre / snakePts / makeBoard,
## and the Jungle module's buildBoard: rounded pastel tiles, 3D ladders with rails and rungs, tapered tube snakes).
## Same footprint as LudoBoard: a 15 x 15 playing face (1.5 units per square) at y = TOP in a rounded cream frame.
## Square 1 is bottom-left seen from +Z; rows zig-zag upwards. Pure presentation: it shows positions and animates moves.

const TOP := LudoBoard.TOP              # board surface height
const C := 1.5                          # one square, in world units
const TABLE_Y := -0.31                  # the table top (TableWorld.TT): where waiting pawns stand
const PAWN_SCALE := 1.35                # squares are 1.5x the Ludo ones, so the pawns are bigger too
const SHARED_SCALE := 0.82
const SHARE_OFF := [[-0.22, -0.14], [0.22, -0.14], [-0.22, 0.2], [0.22, 0.2]]   # in squares, like tokenXY
const SNAKE_COL := ["#2fa86b", "#8a4fe0", "#e5484d", "#f08c00", "#3b7be0", "#2fb39c", "#d9536a", "#6b8e23", "#c0483f", "#7c4dff"]
const BANDS := ["#ffc7a0", "#ffbcba", "#c2e4b2", "#ffda80", "#bcd8f0"]   # tile colour per pair of rows (Jungle board)
const TILE_CREAM := "#fff4e2"
const GROUT := "#efd2b2"
const GOAL := "#ffd45c"
const STAR := "#f4a92a"
const NUM := "#7d4f61"
const NUM_100 := "#b06d00"
const RAIL := "#c47a3c"                 # honey wood ladders
const RUNG := "#f2b366"
const SNAKE_R := 0.165 * C              # snake body radius (full thickness)
const SNAKE_SAMPLES := 64
const END_NUDGE := Vector2(0.07, 0.09)  # ladder ends and snake heads / tails sit a little below-right of a square's
                                        # centre, clear of its number in the top-left corner
const HEAD_NUDGE := Vector2(0.1, 0.2)  # snake heads sit lower still: they face up the board, towards the number
const LADDER_HALF := 0.18               # half the ladder's width, in squares
const NUM_FS := 0.43                    # square numbers: font size as a share of a square (11-13 px at 390 wide)
const HOP_SEC := 0.16                   # one square's hop (times speed)
const WAIT_SCALE := 0.88                # waiting pawns on the start pad are a little smaller
const WAIT_GAP := 1.12                  # their spacing along the pad
## The start pad in front of square 1 (board units): waiting pawns stand on it in a row.
const PAD_X0 := -7.6
const PAD_X1 := -2.55
const PAD_Z := 9.55
const PAD_D := 1.3
const PAD_H := 0.16

var top_mesh: MeshInstance3D
var fx: Node3D
var pawns := []                         # pawns[pi] = {node, mat, ring, target, scale, anim, pos}
var current := -1
var pace := 1.0                         # app-wide animation factor (Settings: Relaxed 1 / Fast 0.55), times each call's speed
var snake_rides := {}                   # head square -> PackedVector3Array: where a pawn rides along the body, head to tail
var _built := false
var style := {}                         # SLScenes board style (apply_style); empty = the Jungle defaults above
var _lip: MeshInstance3D
var _pad: MeshInstance3D
var _pad_lip: MeshInstance3D
var _obstacles := []                    # [centre, radius] along the ladder rails and laid snakes, for draping
static var _phases := {}                # head square -> wave phase chosen for that snake


func _ready() -> void:
	_make()

## Paint the tile face and make sure the frame, ladders and snakes exist (they need no texture). Coroutine.
func build(baker: TexBaker) -> void:
	_make()
	var tex := await baker.bake(Vector2i(2048, 2048), paint)
	top_mesh.material_override = MeshKit.tex_mat(tex, 0.5)

## A scene's board look (SLScenes.SCENES[id].board, index.html B): tile bands, cream, grout, goal, star, number ink,
## frame / lip (+ roughness / metalness), ladder rails / rungs or a candy stripe, snake colours. Repaints the face and
## rebuilds the ladders and snakes; pawns stay. Coroutine.
func apply_style(baker: TexBaker, st: Dictionary) -> void:
	_make()
	style = st
	(get_node("Frame") as MeshInstance3D).material_override = MeshKit.mat(_sc("frame", "#fff6ee"), float(st.get("frameR", 0.3)), float(st.get("frameM", 0.0)))
	_lip.material_override = MeshKit.mat(_sc("lip", "#f2b46e"), 0.35 if st.has("lip") else 0.3, float(st.get("lipM", 0.0)))
	_pad.material_override = (get_node("Frame") as MeshInstance3D).material_override
	_pad_lip.material_override = _lip.material_override
	var old := get_node("LaddersSnakes")
	remove_child(old)
	old.queue_free()
	_obstacles.clear()
	snake_rides.clear()
	var pieces := Node3D.new()
	pieces.name = "LaddersSnakes"
	add_child(pieces)
	_build_ladders(pieces)
	_build_snakes(pieces)
	var tex := await baker.bake(Vector2i(2048, 2048), func(c: Control): paint_styled(c, st))
	top_mesh.material_override = MeshKit.tex_mat(tex, 0.5)

## A style colour (a "#rrggbb" string or a Color), or the default.
func _sc(key: String, def) -> Color:
	var v = style.get(key, def)
	return v if v is Color else Color(str(v))

func _make() -> void:
	if _built:
		return
	_built = true
	var frame := MeshKit.put(self, MeshKit.rbox(16.8, 0.6, 16.8, 0.28), MeshKit.mat(Color("#fff6ee"), 0.3), Vector3(0, -0.02, 0))
	frame.name = "Frame"
	_lip = MeshKit.put(self, MeshKit.rbox(17.3, 0.32, 17.3, 0.15), MeshKit.mat(Color("#f2b46e"), 0.3), Vector3(0, -0.16, 0))
	top_mesh = MeshKit.put(self, MeshKit.plane(15, 15), MeshKit.mat(Color(TILE_CREAM), 0.5), Vector3(0, TOP + 0.002, 0), Vector3.ZERO, Vector3.ONE, false)
	top_mesh.name = "Face"
	# the start pad: a small slab of the frame on the table in front of square 1 (shown while pawns are waiting)
	var pw := PAD_X1 - PAD_X0
	var pc := Vector3((PAD_X0 + PAD_X1) / 2.0, 0, PAD_Z)
	_pad_lip = MeshKit.put(self, MeshKit.rbox(pw + 0.3, PAD_H * 0.6, PAD_D + 0.3, 0.2), MeshKit.mat(Color("#f2b46e"), 0.3), pc + Vector3(0, TABLE_Y + PAD_H * 0.3, 0))
	_pad = MeshKit.put(self, MeshKit.rbox(pw, PAD_H, PAD_D, 0.42), MeshKit.mat(Color("#fff6ee"), 0.3), pc + Vector3(0, TABLE_Y + PAD_H / 2.0 + 0.02, 0))
	_pad.name = "StartPad"
	_pad.visible = false
	_pad_lip.visible = false
	var pieces := Node3D.new()
	pieces.name = "LaddersSnakes"
	add_child(pieces)
	_build_ladders(pieces)
	_build_snakes(pieces)
	fx = Node3D.new()
	add_child(fx)


# ---------- squares -> board ----------

## Row from the bottom (0..9) and column from the left (0..9) of square n (index.html cellRC).
static func cell_rc(n: int) -> Vector2i:
	var r := (n - 1) / 10
	var k := (n - 1) % 10
	return Vector2i(r, 9 - k if r % 2 else k)

## Centre of square n in squares from the top-left corner of the face (texture space / C).
static func grid_of(n: int) -> Vector2:
	var rc := cell_rc(n)
	return Vector2(rc.y + 0.5, 9 - rc.x + 0.5)

static func grid_to_world(g: Vector2, y := TOP) -> Vector3:
	return Vector3(g.x * C - 7.5, y, g.y * C - 7.5)

## Centre of square n on the board surface; 0 is the first waiting spot off the board.
func cell_world(n: int) -> Vector3:
	if n <= 0:
		return wait_spot(0)
	return grid_to_world(grid_of(n))

## Off-board waiting spot of player pi: in a row on the start pad in front of square 1.
func wait_spot(pi: int) -> Vector3:
	return Vector3(PAD_X0 + 0.72 + pi * WAIT_GAP, TABLE_Y + PAD_H + 0.02, PAD_Z)

## A wavy body from the head to the tail in squares (index.html snakePts), with its wave phase.
static func snake_path(head: int, tail: int, phase: float, samples := SNAKE_SAMPLES) -> PackedVector2Array:
	var a := grid_of(head) + HEAD_NUDGE
	var b := grid_of(tail) + END_NUDGE
	var d := b - a
	var L := d.length()
	var nrm := Vector2(-d.y, d.x) / L
	var waves := maxf(1.5, L / 2.2)
	var amp := 0.3
	var pts := PackedVector2Array()
	for s in samples + 1:
		var t := float(s) / samples
		var w := sin(t * PI * waves + phase) * amp * sin(t * PI)
		pts.append(a + d * t + nrm * w)
	return pts

## The body of the snake with this head: the web version's phase (its index) unless another phase keeps the body
## clearly further from the other snakes' heads and tails, the ladder ends and the snakes laid before it.
static func snake_body(head: int, samples := SNAKE_SAMPLES) -> PackedVector2Array:
	if _phases.is_empty():
		_choose_phases()
	return snake_path(head, SnakesLaddersRules.SNAKES[head], _phases[head], samples)

static func _choose_phases() -> void:
	var spots := []                         # every special square's anchor
	for f in SnakesLaddersRules.LADDERS:
		spots.append([f, grid_of(f) + END_NUDGE])
		spots.append([SnakesLaddersRules.LADDERS[f], grid_of(SnakesLaddersRules.LADDERS[f]) + END_NUDGE])
	for h in SnakesLaddersRules.SNAKES:
		spots.append([h, grid_of(h) + HEAD_NUDGE])
		spots.append([SnakesLaddersRules.SNAKES[h], grid_of(SnakesLaddersRules.SNAKES[h]) + END_NUDGE])
	var laid := []
	var i := 0
	for h in SnakesLaddersRules.SNAKES:
		var t: int = SnakesLaddersRules.SNAKES[h]
		var best := float(i)
		var best_score := -1e9
		for m in 12:
			var ph := i + m * TAU / 12.0
			var pts := snake_path(h, t, ph, 32)
			var near := 9.0
			for j in range(3, pts.size() - 3):
				for sp in spots:
					if sp[0] != h and sp[0] != t:
						near = minf(near, pts[j].distance_to(sp[1]))
				for q in laid:
					near = minf(near, pts[j].distance_to(q) + 0.25)
			var score := minf(near, 0.62) - (0.0 if m == 0 else 0.03)
			if score > best_score:
				best_score = score
				best = ph
		_phases[h] = best
		laid.append_array(snake_path(h, t, best, 32))
		i += 1

## Snake body radius at u (0 = tail tip, 1 = head): thin tail, full from three quarters on (Jungle boardSnake rf).
static func snake_radius(u: float) -> float:
	return SNAKE_R * (0.22 + 0.78 * sin(minf(1.0, u * 1.3) * PI / 2))


# ---------- board texture ----------

static func paint(c: Control) -> void:
	paint_styled(c, {})

static func paint_styled(c: Control, st: Dictionary) -> void:
	var col_of := func(key: String, def: String) -> Color:
		var v = st.get(key, def)
		return v if v is Color else Color(str(v))
	var bands: Array = st.get("bands", BANDS)
	var S: float = c.size.x
	var u := S / 10.0
	c.draw_rect(Rect2(0, 0, S, S), col_of.call("grout", GROUT))
	for n in range(1, 101):
		var rc := cell_rc(n)
		var r := rc.x
		var k := rc.y
		var col: Color = col_of.call("goal", GOAL) if n == 100 else (Color(str(bands[r >> 1])) if (r + k) % 2 else col_of.call("cream", TILE_CREAM))
		var x := k * u + u * 0.045
		var y := (9 - r) * u + u * 0.045
		var s := u * 0.91
		# a soft bevel: darker base, the tile face lifted off it, a light sheen on the upper half
		TexBaker.round_rect(c, Rect2(x, y, s, s), u * 0.16, col.darkened(0.1))
		TexBaker.round_rect(c, Rect2(x, y, s, s - u * 0.045), u * 0.16, col)
		TexBaker.round_rect(c, Rect2(x + u * 0.06, y + u * 0.05, s - u * 0.12, s * 0.42), u * 0.12, Color(1, 1, 1, 0.22))
	# contact shadows under the 3D ladders and snakes, so they sit on the board
	for f in SnakesLaddersRules.LADDERS:
		var a := (grid_of(f) + END_NUDGE) * u
		var b := (grid_of(SnakesLaddersRules.LADDERS[f]) + END_NUDGE) * u
		var dir := (b - a).normalized()
		var nrm := Vector2(-dir.y, dir.x) * u * LADDER_HALF
		for side in [1.0, -1.0]:
			for pass_w in [0.2, 0.13]:
				c.draw_line(a + nrm * side - dir * u * 0.12, b + nrm * side + dir * u * 0.12, Color(0.29, 0.17, 0.24, 0.08), u * pass_w, true)
	for h in SnakesLaddersRules.SNAKES:
		var pts := snake_body(h, 48)
		for j in pts.size() - 1:
			var w := snake_radius(1.0 - float(j) / (pts.size() - 1)) / C * u
			for pass_k in [2.3, 1.6]:
				c.draw_line(pts[j] * u, pts[j + 1] * u, Color(0.29, 0.17, 0.24, 0.07), w * pass_k, true)
	# 100: a star on the goal
	var g100 := grid_of(100) * u
	c.draw_colored_polygon(TexBaker.star_points(g100 + Vector2(0, u * 0.1), u * 0.3, 0.46), col_of.call("star", STAR))
	# numbers on every tile, with a soft halo
	var font := UIKit.font_body(900)
	var fs := int(u * NUM_FS)
	var asc := font.get_ascent(fs) * 0.86
	for n in range(1, 101):
		var rc := cell_rc(n)
		var p := Vector2(rc.y * u + u * 0.1, (9 - rc.x) * u + u * 0.075 + asc)
		var txt := str(n)
		c.draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(u * 0.1), Color(1, 0.98, 0.94, 0.95))
		c.draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_of.call("num100", NUM_100) if n == 100 else col_of.call("num", NUM))


# ---------- ladders ----------

func _build_ladders(parent: Node3D) -> void:
	var rail := MeshKit.mat(_sc("rail", RAIL), 0.5, float(style.get("railM", 0.0)))
	var rung := MeshKit.mat(_sc("rung", RUNG), 0.5)
	var stripe: Array = style.get("stripe", [])
	var rr := 0.085
	var cap := MeshKit.sphere(rr, 12, 8)
	for f in SnakesLaddersRules.LADDERS:
		var a := grid_to_world(grid_of(f) + END_NUDGE)
		var b := grid_to_world(grid_of(SnakesLaddersRules.LADDERS[f]) + END_NUDGE)
		var d := b - a
		var L := d.length()
		var dir := d / L
		var nrm := Vector3(-dir.z, 0, dir.x) * C * LADDER_HALF
		var ext := dir * C * 0.12
		var lift := Vector3(0, rr + 0.01, 0)
		for s in [1.0, -1.0]:
			var p0: Vector3 = a + nrm * s - ext + lift
			var p1: Vector3 = b + nrm * s + ext + lift
			if stripe.is_empty():
				_rod(parent, p0, p1, rr, rail)
			else:                                # candy-cane rails: short alternating pieces
				var pieces := maxi(2, roundi(p0.distance_to(p1) / (0.09 * 15.0 / 4.8)))
				for q in pieces:
					_rod(parent, p0.lerp(p1, float(q) / pieces), p0.lerp(p1, float(q + 1) / pieces), rr * 1.07, MeshKit.mat(Color(str(stripe[q % stripe.size()])), 0.3))
			MeshKit.put(parent, cap, rail if stripe.is_empty() else MeshKit.mat(Color(str(stripe[0])), 0.3), p0)
			MeshKit.put(parent, cap, rail if stripe.is_empty() else MeshKit.mat(Color(str(stripe[0])), 0.3), p1)
			var steps := ceili(p0.distance_to(p1) / 0.2)
			for q in steps + 1:
				_obstacles.append([p0.lerp(p1, float(q) / steps), rr])
		var k := maxi(2, roundi(L / (C * 0.42)))
		for i in range(1, k):
			var m := a + d * (float(i) / k) + Vector3(0, 0.07, 0)
			_rod(parent, m - nrm * 1.08, m + nrm * 1.08, 0.055, rung)

## A cylinder of radius r from a to b.
static func _rod(parent: Node3D, a: Vector3, b: Vector3, r: float, m: Material) -> MeshInstance3D:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.UP)
	if x.length() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y)
	var mi := MeshKit.put(parent, MeshKit.cylinder(r, r, 1.0, 14), m, (a + b) / 2)
	mi.basis = Basis(x, y * d.length(), z)
	return mi


# ---------- snakes ----------

func _build_snakes(parent: Node3D) -> void:
	var i := 0
	for h in SnakesLaddersRules.SNAKES:
		var cols: Array = style.get("snakes", SNAKE_COL)
		var col := Color(str(cols[i % cols.size()]))
		var g2 := snake_body(h)
		var pts := PackedVector3Array()           # tail first; y = the body's centre line
		var rads := PackedFloat32Array()
		var n := g2.size()
		for j in n:
			var uu := float(j) / (n - 1)
			var r := snake_radius(uu)
			var p := grid_to_world(g2[n - 1 - j], TOP + r * 0.72)
			pts.append(p)
			rads.append(r)
		_drape(pts, rads)
		_snake(parent, pts, rads, col)
		for j in n:
			_obstacles.append([pts[j], rads[j]])
		# the ride: on top of the body, head to tail
		var ride := PackedVector3Array()
		for j in range(n - 1, -1, -1):
			ride.append(pts[j] + Vector3(0, rads[j] * 0.8, 0))
		snake_rides[h] = ride
		i += 1

## Lift the body where it crosses a ladder or a snake laid before it, so it drapes over them instead of cutting through.
func _drape(pts: PackedVector3Array, rads: PackedFloat32Array) -> void:
	var n := pts.size()
	var lift := PackedFloat32Array()
	lift.resize(n)
	for j in n:
		var p := pts[j]
		var r := rads[j]
		var need := 0.0
		for o in _obstacles:
			var q: Vector3 = o[0]
			var qr: float = o[1]
			var d := Vector2(p.x - q.x, p.z - q.z).length()
			var touch := qr + r
			if d > touch + 0.5:
				continue
			var over := q.y + qr + r * 0.92 - p.y
			if over > 0.0:
				need = maxf(need, over * (1.0 - smoothstep(touch * 0.7, touch + 0.5, d)))
		lift[j] = need
	for pass_k in 4:                             # smooth it into a gentle arch
		var sm := lift.duplicate()
		for j in range(1, n - 1):
			sm[j] = maxf(lift[j] * 0.85, (lift[j - 1] + lift[j] * 2.0 + lift[j + 1]) / 4.0)
		lift = sm
	for j in n:
		pts[j].y += lift[j]

## A tapered tube along pts (tail first, radius rads) with soft stripes, and a head with eyes and a tongue.
func _snake(parent: Node3D, pts: PackedVector3Array, rads: PackedFloat32Array, col: Color) -> void:
	var n := pts.size()
	var radial := 16
	var light := col.lerp(Color("#fff6dc"), 0.42)
	var dark := col.darkened(0.18)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts := []
	var nrms := []
	var cols := []
	var arc := 0.0
	for j in n:
		var p := pts[j]
		var r := rads[j]
		var tng := (pts[mini(j + 1, n - 1)] - pts[maxi(j - 1, 0)]).normalized()
		var side := tng.cross(Vector3.UP).normalized()
		var up := side.cross(tng).normalized()
		if j > 0:
			arc += pts[j].distance_to(pts[j - 1])
		var band := smoothstep(0.62, 0.9, 0.5 + 0.5 * sin(arc / 0.5 * TAU))
		for q in radial + 1:
			var ang := float(q) / radial * TAU
			var dn := up * cos(ang) + side * sin(ang)
			verts.append(p + dn * r)
			nrms.append(dn)
			var top := clampf(cos(ang), 0.0, 1.0)
			var cc := col.lerp(light, band * 0.85)                                  # light bands round the body
			cc = cc.lerp(dark, smoothstep(0.75, 1.0, top) * 0.35 * (1.0 - band))   # a darker spine
			if cos(ang) < -0.2:
				cc = cc.lerp(light, 0.5)                                          # pale belly
			cols.append(cc)
	for j in n - 1:
		for q in radial:
			var a := j * (radial + 1) + q
			var b := a + radial + 1
			_tri(st, verts, nrms, cols, a, b, a + 1)
			_tri(st, verts, nrms, cols, a + 1, b, b + 1)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.32
	m.clearcoat_enabled = true
	m.clearcoat = 0.6
	m.clearcoat_roughness = 0.25
	var body := MeshInstance3D.new()
	body.mesh = st.commit()
	body.material_override = m
	parent.add_child(body)
	MeshKit.put(parent, MeshKit.sphere(rads[0], 10, 6), MeshKit.mat(col, 0.32), pts[0])   # tail tip
	# head, facing on along the body
	var R := SNAKE_R
	var f := pts[n - 1] - pts[n - 3]
	f.y = 0
	f = f.normalized()
	var head := Node3D.new()
	head.position = pts[n - 1]
	head.rotation.y = atan2(f.x, f.z)
	parent.add_child(head)
	var hm := MeshKit.mat(col, 0.32)
	var unit := MeshKit.sphere(1.0, 24, 14)
	MeshKit.put(head, unit, hm, Vector3(0, R * 0.12, R * 0.5), Vector3.ZERO, Vector3(R * 1.4, R * 1.0, R * 1.65))
	MeshKit.put(head, unit, MeshKit.mat(light, 0.4), Vector3(0, -R * 0.12, R * 0.62), Vector3.ZERO, Vector3(R * 1.15, R * 0.62, R * 1.35), false)
	var white := MeshKit.mat(Color.WHITE, 0.25)
	var pupil := MeshKit.mat(Color("#2a1d24"), 0.15)
	var blush := MeshKit.mat(Color("#ff9fb0"), 0.6)
	for s in [-1.0, 1.0]:
		MeshKit.put(head, unit, white, Vector3(s * R * 0.64, R * 0.78, R * 0.9), Vector3.ZERO, Vector3.ONE * R * 0.46, false)
		MeshKit.put(head, unit, pupil, Vector3(s * R * 0.72, R * 0.98, R * 1.16), Vector3.ZERO, Vector3.ONE * R * 0.25, false)
		MeshKit.put(head, unit, white, Vector3(s * R * 0.64, R * 1.14, R * 1.24), Vector3.ZERO, Vector3.ONE * R * 0.08, false)
		MeshKit.put(head, unit, blush, Vector3(s * R * 1.0, R * 0.22, R * 1.38), Vector3.ZERO, Vector3(R * 0.24, R * 0.13, R * 0.17), false)
	# a little forked tongue
	var tongue := MeshKit.mat(Color("#e5484d"), 0.4)
	var t0 := Vector3(0, -R * 0.05, R * 2.05)
	_rod(head, t0, t0 + Vector3(0, 0, R * 0.55), R * 0.075, tongue)
	for s in [-1.0, 1.0]:
		_rod(head, t0 + Vector3(0, 0, R * 0.5), t0 + Vector3(s * R * 0.24, 0, R * 0.88), R * 0.065, tongue)

## One triangle, wound so its front faces along the normals (as MeshKit._tri), with a vertex colour.
static func _tri(st: SurfaceTool, pts: Array, nrms: Array, cols: Array, a: int, b: int, c: int) -> void:
	var n: Vector3 = nrms[a] + nrms[b] + nrms[c]
	var pa: Vector3 = pts[a]
	if (pts[c] - pa).cross(pts[b] - pa).dot(n) < 0:
		var t := b; b = c; c = t
	for q in [a, b, c]:
		st.set_normal(nrms[q])
		st.set_color(cols[q])
		st.add_vertex(pts[q])


# ---------- pawns ----------

## One pawn per player; colors are LudoRules colour indices (0..3). Everyone starts at their waiting spot.
func setup_players(colors: Array) -> void:
	_make()
	for p in pawns:
		_stop(p)
		p.node.queue_free()
	pawns.clear()
	current = -1
	var prof := PackedVector2Array()
	for q in LudoBoard.PAWN_PROFILE:
		prof.append(Vector2(q[0], q[1]))
	var body_mesh := MeshKit.lathe(prof, 36)
	var head_mesh := MeshKit.sphere(0.19, 28, 18)
	var ring_mesh := MeshKit.torus(0.5, 0.045, 48, 8)
	for pi in colors.size():
		var ci: int = colors[pi]
		var m := LudoBoard.pawn_material(Palette.PLAYER[ci])
		var g := Node3D.new()
		g.name = "SLPawn%d" % pi
		add_child(g)
		MeshKit.put(g, body_mesh, m, Vector3.ZERO)
		MeshKit.put(g, head_mesh, m, Vector3(0, 0.74, 0))
		var rm := MeshKit.unlit(Color(1, 1, 1, 0.9))
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var ring := MeshKit.put(g, ring_mesh, rm, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE, false)
		ring.visible = false
		var t := {node = g, mat = m, ring = ring, target = wait_spot(pi), scale = PAWN_SCALE * WAIT_SCALE, anim = false, pos = 0}
		g.position = t.target
		g.scale = Vector3.ONE * float(t.scale)
		pawns.append(t)
	_refresh_pad()

## Show everyone at positions[pi] (0 = off the board) without animation.
func place(positions: Array) -> void:
	for pi in mini(positions.size(), pawns.size()):
		pawns[pi].pos = int(positions[pi])
		pawns[pi].anim = false
		_stop(pawns[pi])
	_relayout()
	for t in pawns:
		t.node.position = t.target
		t.node.scale = Vector3.ONE * float(t.scale)

## The pulsing ring under the current player's pawn (-1: none).
func set_current(pi: int) -> void:
	current = pi

## Where each pawn stands: square centres, spread out when players share a square; the waiting ones in a row on the
## start pad from square 1's side.
func _relayout() -> void:
	var waiting := 0
	for pi in pawns.size():
		var t: Dictionary = pawns[pi]
		var n: int = t.pos
		if n <= 0:
			t.target = wait_spot(waiting)
			waiting += 1
			t.scale = PAWN_SCALE * WAIT_SCALE
			continue
		var mates := []
		for qi in pawns.size():
			if pawns[qi].pos == n:
				mates.append(qi)
		var p := cell_world(n)
		if mates.size() > 1:
			var o: Array = SHARE_OFF[mates.find(pi) % 4]
			p += Vector3(o[0] * C, 0, o[1] * C)
			t.scale = PAWN_SCALE * SHARED_SCALE
		else:
			t.scale = PAWN_SCALE
		t.target = p
	_refresh_pad()

## The start pad shows while a pawn is waiting on it.
func _refresh_pad() -> void:
	if _pad:
		_pad.visible = pawns.any(func(t): return int(t.pos) <= 0)
		_pad_lip.visible = _pad.visible

## Where pawn pi's head is now, in global coordinates (for pops over it).
func pawn_top(pi: int) -> Vector3:
	if pi < 0 or pi >= pawns.size():
		return global_position
	var g: Node3D = pawns[pi].node
	return g.global_position + Vector3(0, 1.1 * g.scale.y, 0)

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var pulse := (sin(now * 1000.0 / 180.0) + 1.0) / 2.0
	var k := 1.0 - pow(0.78, delta * 60.0)
	var ks := 1.0 - pow(0.8, delta * 60.0)
	for pi in pawns.size():
		var t: Dictionary = pawns[pi]
		var g: Node3D = t.node
		if not t.anim:
			g.position = g.position.lerp(t.target, k)
		var s: float = g.scale.x + (float(t.scale) - g.scale.x) * ks
		g.scale = Vector3(s, s, s)
		var on := pi == current
		t.ring.visible = on
		t.mat.emission_energy_multiplier = (0.08 + pulse * 0.16) if on else 0.0
		if on:
			var rs := 1.0 + pulse * 0.18
			t.ring.scale = Vector3(rs, rs, rs)
			t.ring.material_override.albedo_color.a = 0.5 + pulse * 0.5


# ---------- animations (awaitable) ----------

## A fresh tween for pawn t; any move still running on it stops (place() and setup_players() stop them too).
func _tween(t: Dictionary) -> Tween:
	_stop(t)
	t.tw = create_tween()
	return t.tw

func _stop(t: Dictionary) -> void:
	var old: Tween = t.get("tw")
	if old and old.is_valid():
		old.kill()
	t.tw = null
	if t.has("node") and is_instance_valid(t.node):
		(t.node as Node3D).rotation = Vector3.ZERO

func _dur(sec: float, speed: float) -> float:
	return maxf(0.01, sec * speed * pace)

static func _ease(k: float) -> float:
	return k * k * 2.0 if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 2) / 2.0

## Move pawn pi's square to n and return where it now stands (the others shuffle aside on their own).
func _move_to(pi: int, n: int) -> Vector3:
	pawns[pi].pos = n
	_relayout()
	return pawns[pi].target

## One arcing hop to square n (0: back to the waiting spot).
func hop_to(pi: int, n: int, speed := 1.0) -> void:
	var t: Dictionary = pawns[pi]
	var a: Vector3 = t.node.position
	var b := _move_to(pi, n)
	var height := 0.7 if a.y < TOP - 0.1 or n <= 0 else 0.55
	t.anim = true
	var tw := _tween(t)
	tw.tween_method(func(k: float):
		var p := a.lerp(b, _ease(k))
		p.y = lerpf(a.y, b.y, _ease(k)) + sin(k * PI) * height
		t.node.position = p, 0.0, 1.0, _dur(HOP_SEC, speed))
	await tw.finished
	t.node.position = b
	t.anim = false

## Glide up the ladder from its foot to its top, bobbing over the rungs.
func climb(pi: int, from_sq: int, to_sq: int, speed := 1.0) -> void:
	var t: Dictionary = pawns[pi]
	var a: Vector3 = t.node.position
	var foot := cell_world(from_sq)
	var b := _move_to(pi, to_sq)
	var cells := foot.distance_to(cell_world(to_sq)) / C
	var rungs := maxf(2.0, roundf(cells * C / (C * 0.42)))
	t.anim = true
	var tw := _tween(t)
	var last := [-1.0]
	var dur := _dur(0.4 + 0.075 * cells, speed)
	tw.tween_method(func(k: float):
		var e := _ease(k)
		var p := a.lerp(b, e)
		var lift := clampf(minf(k, 1.0 - k) * 8.0, 0.0, 1.0)     # up onto the rungs, along, and down at the top
		p.y = TOP + lift * (0.16 + absf(sin(e * rungs * PI)) * 0.07)
		t.node.position = p
		_trail(p, k, last, dur), 0.0, 1.0, dur)
	await tw.finished
	t.node.position = b
	t.anim = false
	for q in 6:                                              # and a little burst at the top
		var ang := q * TAU / 6.0
		_sparkle(b + Vector3(cos(ang) * 0.5, 0.6 + randf() * 0.4, sin(ang) * 0.5), dur * 0.8)

## A sparkle behind the climber every few percent of the climb (last[0]: when the previous one was dropped).
func _trail(p: Vector3, k: float, last: Array, dur: float) -> void:
	if k - float(last[0]) > 0.06 and k < 0.95:
		last[0] = k
		_sparkle(p + Vector3(randf_range(-0.25, 0.25), 0.35 + randf() * 0.5, randf_range(-0.25, 0.25)), dur)

static var _spark_mesh: Mesh
static var _spark_mats := []

## One sparkle: a tiny glowing star that pops up, drifts upward and fades.
func _sparkle(at: Vector3, life: float) -> void:
	if _spark_mesh == null:
		_spark_mesh = MeshKit.sphere(0.11, 8, 6)
		for col in [Palette.GOLD_HI, Palette.HONEY, Color.WHITE]:
			var m := MeshKit.unlit(col)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_spark_mats.append(m)
	var mi := MeshInstance3D.new()
	mi.mesh = _spark_mesh
	mi.material_override = _spark_mats[randi() % _spark_mats.size()]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.scale = Vector3.ONE * 0.2
	fx.add_child(mi)
	var tl := clampf(life * 0.9, 0.3, 0.9)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * (0.8 + randf() * 0.6), tl * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "position:y", at.y + 0.7, tl).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(mi, "scale", Vector3.ZERO, tl * 0.7).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)

## Ride down the snake from its head along the body to the tail.
func slide(pi: int, head: int, tail: int, speed := 1.0) -> void:
	var t: Dictionary = pawns[pi]
	var ride: PackedVector3Array = snake_rides.get(head, PackedVector3Array([cell_world(head), cell_world(tail)]))
	var path := PackedVector3Array([t.node.position])
	path.append_array(ride)
	var b := _move_to(pi, tail)
	path.append(b)
	var lens := PackedFloat32Array([0.0])
	for j in range(1, path.size()):
		lens.append(lens[j - 1] + path[j].distance_to(path[j - 1]))
	var total: float = lens[lens.size() - 1]
	t.anim = true
	var tw := _tween(t)
	var g: Node3D = t.node
	tw.tween_method(func(k: float):
		var e := k * k * (3.0 - 2.0 * k)                # ease in and out: a whoosh down the body
		var d := e * total
		var j := 1
		while j < path.size() - 1 and lens[j] < d:
			j += 1
		var seg := maxf(0.0001, lens[j] - lens[j - 1])
		g.position = path[j - 1].lerp(path[j], clampf((d - lens[j - 1]) / seg, 0.0, 1.0))
		var wob := sin(k * PI) * 0.32                   # a dizzy wobble on the way down
		g.rotation = Vector3(sin(k * TAU * 2.5) * wob * 0.6, k * TAU * 1.0, sin(k * TAU * 3.0) * wob), 0.0, 1.0, _dur(0.6 + 0.05 * total / C, speed))
	await tw.finished
	g.position = b
	g.rotation = Vector3.ZERO
	t.anim = false
