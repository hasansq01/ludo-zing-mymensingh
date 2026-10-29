class_name SLBoard
extends Node3D
## The Snakes & Ladders board on the café table and its pawns (index.html: SL cellRC / centre / snakePts / makeBoard,
## and the Jungle module's buildBoard: rounded pastel tiles, flat cartoon ladders and snakes painted on the face).
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
var _built := false
var style := {}                         # SLScenes board style (apply_style); empty = the Jungle defaults above
var _lip: MeshInstance3D
var _pad: MeshInstance3D
var _pad_lip: MeshInstance3D
static var _phases := {}                # head square -> wave phase chosen for that snake


func _ready() -> void:
	_make()

## Paint the tile face with the ladders and snakes on it. Coroutine.
## A board on an SLScenes table skips it: its scene paints it in its own style (apply_style, from set_scene), and a
## default face painted first would only be thrown away (a 2048 texture with every ladder and snake, twice).
func build(baker: TexBaker) -> void:
	_make()
	if _on_scene():
		return
	var tex := await baker.bake(Vector2i(2048, 2048), paint)
	top_mesh.material_override = MeshKit.tex_mat(tex, 0.5)

func _on_scene() -> bool:
	var n := get_parent()
	while n:
		if n is SLScenes:
			return true
		n = n.get_parent()
	return false

## A scene's board look (SLScenes.SCENES[id].board, index.html B): tile bands, cream, grout, goal, star, number ink,
## frame / lip (+ roughness / metalness), ladder rails / rungs or a candy stripe, snake colours. Repaints the face
## (ladders and snakes are painted on it); pawns stay. Coroutine.
func apply_style(baker: TexBaker, st: Dictionary) -> void:
	_make()
	style = st
	(get_node("Frame") as MeshInstance3D).material_override = MeshKit.mat(_sc("frame", "#fff6ee"), float(st.get("frameR", 0.3)), float(st.get("frameM", 0.0)))
	_lip.material_override = MeshKit.mat(_sc("lip", "#f2b46e"), 0.35 if st.has("lip") else 0.3, float(st.get("lipM", 0.0)))
	_pad.material_override = (get_node("Frame") as MeshInstance3D).material_override
	_pad_lip.material_override = _lip.material_override
	var old := get_node_or_null("Trim")
	if old:
		remove_child(old)
		old.queue_free()
	if st.has("trim"):
		await _add_trim(baker, st.trim)
	var tex := await baker.bake(Vector2i(2048, 2048), func(c: Control): paint_styled(c, st))
	top_mesh.material_override = MeshKit.tex_mat(tex, 0.5)

# ---------- board trim (the style's trim: lip, corner, mid), all on the rim and off the tiles ----------
#   lip: ["stripes" | "diamonds", a, b]  a patterned ring raised round the face
#   corner: ["mint" | "sun", a, b]       a flat round piece on each corner of the frame (peppermint / sun medallion)
#   mid: ["gumdrop" | "tile", colours]   a small piece in the middle of each side (round gumdrop / flat diamond tile)

const LIP_IN := 7.5                     # the patterned lip runs from the face edge out to LIP_OUT
const LIP_OUT := 7.8
const FRAME_TOP := 0.28
const TRIM_EDGE := 8.1                  # corner and mid pieces sit on the frame at this distance from the centre
static var _trim_mats := {}
static var _medals := {}

func _add_trim(baker: TexBaker, T: Dictionary) -> void:
	var trim := Node3D.new()
	trim.name = "Trim"
	add_child(trim)
	var lip := _lip_mat(T.lip)
	var mid := (LIP_IN + LIP_OUT) / 2.0
	var span := LIP_OUT * 2.0
	var strip := MeshKit.rbox(span, 0.11, LIP_OUT - LIP_IN, 0.05)
	var side := MeshKit.rbox(LIP_OUT - LIP_IN, 0.11, LIP_IN * 2.0, 0.05)
	MeshKit.put(trim, strip, lip, Vector3(0, 0.315, -mid), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.put(trim, strip, lip, Vector3(0, 0.315, mid), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.put(trim, side, lip, Vector3(-mid, 0.315, 0), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.put(trim, side, lip, Vector3(mid, 0.315, 0), Vector3.ZERO, Vector3.ONE, false)
	var ck: String = T.corner[0]
	var ca := Color(str(T.corner[1]))
	var cb := Color(str(T.corner[2]))
	var medal: Texture2D = await _medal(baker, ck, ca, cb)
	var rim := MeshKit.mat(cb if ck == "mint" else ca, 0.3)
	var face := MeshKit.tex_mat(medal, 0.3)
	var disc := MeshKit.cylinder(0.34, 0.34, 0.05, 28)
	var cap := MeshKit.cylinder(0.34, 0.34, 0.002, 28)     # its round cap carries the picture (the texture is the disc inscribed in the square)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var at := Vector3(sx * TRIM_EDGE, FRAME_TOP, sz * TRIM_EDGE)
			MeshKit.put(trim, disc, rim, at + Vector3(0, 0.025, 0), Vector3.ZERO, Vector3.ONE, false)
			MeshKit.put(trim, cap, face, at + Vector3(0, 0.051, 0), Vector3.ZERO, Vector3.ONE, false)
	var mk: String = T.mid[0]
	var mcols: Array = T.mid[1]
	var i := 0
	for p in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		var col := MeshKit.mat(Color(str(mcols[i % mcols.size()])), 0.3 if mk == "gumdrop" else 0.45)
		var at := Vector3(p.x * TRIM_EDGE, FRAME_TOP, p.y * TRIM_EDGE)
		if mk == "gumdrop":
			MeshKit.put(trim, MeshKit.sphere(1.0, 16, 10), col, at + Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(0.3, 0.22, 0.3), false)
		else:
			MeshKit.put(trim, MeshKit.cylinder(0.34, 0.34, 0.07, 4), col, at + Vector3(0, 0.035, 0), Vector3.ZERO, Vector3.ONE, false)
		i += 1

## The patterned lip's material: the pattern is a texture mapped from the world position (triplanar), so it runs on
## round the four strips.
static func _lip_mat(spec: Array) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [spec[0], spec[1], spec[2]]
	if _trim_mats.has(key):
		return _trim_mats[key]
	var a := Color(str(spec[1]))
	var b := Color(str(spec[2]))
	var diamonds: bool = spec[0] == "diamonds"
	var w := 128
	var img := Image.create(w, w, true, Image.FORMAT_RGBA8)
	for y in w:
		for x in w:
			var on: bool
			if diamonds:
				on = absf(fposmod(x / float(w) * 8.0, 1.0) - 0.5) + absf(fposmod(y / float(w) * 8.0, 1.0) - 0.5) < 0.3
			else:
				on = fposmod((x + y) / float(w) * 7.0, 1.0) < 0.5
			img.set_pixel(x, y, a if on else b)
	img.generate_mipmaps()
	var m := MeshKit.tex_mat(ImageTexture.create_from_image(img), 0.35)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var span := 4.0 if diamonds else 3.0       # board units per texture repeat
	m.uv1_scale = Vector3.ONE / span
	if diamonds:                               # a row of diamonds centred on the strip
		m.uv1_offset = Vector3.ONE * ((0.5 - fposmod(((LIP_IN + LIP_OUT) / 2.0) / span * 8.0, 1.0)) / 8.0)
	_trim_mats[key] = m
	return m

## The corner medallion (painted on a square, shown as a disc): a peppermint swirl or a sun in a ring.
static func _medal(baker: TexBaker, kind: String, a: Color, b: Color) -> Texture2D:
	var key := "%s|%s|%s" % [kind, a.to_html(), b.to_html()]
	if not _medals.has(key):
		_medals[key] = await baker.bake(Vector2i(128, 128), func(c: Control): _paint_medal(c, kind, a, b))
	return _medals[key]

static func _paint_medal(c: CanvasItem, kind: String, a: Color, b: Color) -> void:
	var m := 64.0
	var ctr := Vector2(m, m)
	c.draw_rect(Rect2(0, 0, m * 2, m * 2), b)
	if kind == "mint":                          # eight swirled wedges, a centre dot
		for k in 8:
			var a0 := k * PI / 4.0
			var pts := PackedVector2Array()
			for q in 9:
				var t := q / 8.0
				pts.append(ctr + Vector2.from_angle(a0 + t * 0.6) * m * 0.96 * t)
			for q in range(8, -1, -1):
				var t := q / 8.0
				pts.append(ctr + Vector2.from_angle(a0 + PI / 4.0 * 0.5 + t * 0.6) * m * 0.96 * t)
			c.draw_colored_polygon(pts, a)
		c.draw_circle(ctr, m * 0.16, b, true, -1.0, true)
	else:                                       # a sun: twelve pointed rays round a face, inside a thin ring
		var ray := PackedVector2Array()
		for k in 24:
			ray.append(ctr + Vector2.from_angle(k * PI / 12.0) * m * (0.42 if k % 2 else 0.72))
		c.draw_colored_polygon(ray, a)
		c.draw_circle(ctr, m * 0.3, b, true, -1.0, true)
		c.draw_circle(ctr, m * 0.2, a, true, -1.0, true)
		c.draw_arc(ctr, m * 0.86, 0, TAU, 48, a, m * 0.07, true)

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

# ---------- board texture ----------

static func paint(c: Control) -> void:
	paint_styled(c, {})

static func paint_styled(c: Control, st: Dictionary) -> void:
	var col_of := func(key: String, def: String) -> Color:
		var v = st.get(key, def)
		return v if v is Color else Color(str(v))
	var bands: Array = st.get("bands", BANDS)
	var tiles: Array = st.get("tiles", [])
	var marks: Array = st.get("marks", [])
	var S: float = c.size.x
	var u := S / 10.0
	c.draw_rect(Rect2(0, 0, S, S), col_of.call("grout", GROUT))
	for n in range(1, 101):
		var rc := cell_rc(n)
		var r := rc.x
		var k := rc.y
		var col: Color
		if n == 100:
			col = col_of.call("goal", GOAL)
		elif not tiles.is_empty():           # premium boards: a 3- or 4-colour pattern that shifts every row
			col = Color(str(tiles[(k + 2 * (r % 2)) % tiles.size()]))
		else:
			col = Color(str(bands[r >> 1])) if (r + k) % 2 else col_of.call("cream", TILE_CREAM)
		var x := k * u + u * 0.045
		var y := (9 - r) * u + u * 0.045
		var s := u * 0.91
		# a soft bevel: darker base, the tile face lifted off it, a light sheen on the upper half
		TexBaker.round_rect(c, Rect2(x, y, s, s), u * 0.16, col.darkened(0.1))
		TexBaker.round_rect(c, Rect2(x, y, s, s - u * 0.045), u * 0.16, col)
		TexBaker.round_rect(c, Rect2(x + u * 0.06, y + u * 0.05, s - u * 0.12, s * 0.42), u * 0.12, Color(1, 1, 1, 0.22))
		if not marks.is_empty() and n != 100:
			_tile_mark(c, marks, n, Vector2(x + s * 0.79, y + s * 0.77), u)     # bottom-right corner, clear of the number
	# 100: a star on the goal
	var g100 := grid_of(100) * u
	c.draw_colored_polygon(TexBaker.star_points(g100 + Vector2(0, u * 0.1), u * 0.3, 0.46), col_of.call("star", STAR))
	_paint_ladders(c, u, st)
	_paint_snakes(c, u, st)
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


# ---------- ladders and snakes (flat art painted on the face, index.html paintLadders / paintSnakes) ----------

## A small, faint decoration in a tile's corner (the style's marks): ["sprinkles", colours] two candy sprinkles on every
## tile; ["glyphs", colour] a sun, a pyramid or an eye-like diamond on every third tile.
static func _tile_mark(c: CanvasItem, marks: Array, n: int, at: Vector2, u: float) -> void:
	if marks[0] == "sprinkles":
		var cols: Array = marks[1]
		var spec := [[-0.05, -0.05, 0.5], [0.05, 0.05, -0.6]]
		for j in 2:
			var p := at + Vector2(spec[j][0], spec[j][1]) * u
			var a: float = spec[j][2] + n
			var d := Vector2(cos(a), sin(a)) * u * 0.045
			_seg(c, p - d, p + d, Color(str(cols[(n * 3 + j) % cols.size()])), u * 0.035)
		return
	if n % 3 != 0:
		return
	var col := Color(str(marks[1]))
	col.a = 0.6
	var d := u * 0.08
	var w := u * 0.022
	if n % 9 == 0:                          # a sun: a dot and eight rays
		c.draw_circle(at, d * 0.45, col, true, -1.0, true)
		for k in 8:
			var q := Vector2(cos(k * PI / 4), sin(k * PI / 4))
			c.draw_line(at + q * d * 0.7, at + q * d, col, w, true)
	elif n % 9 == 3:                        # a pyramid
		c.draw_polyline(PackedVector2Array([at + Vector2(-d, d * 0.7), at + Vector2(0, -d * 0.8), at + Vector2(d, d * 0.7), at + Vector2(-d, d * 0.7)]), col, w, true)
		c.draw_line(at + Vector2(-d * 0.45, d * 0.05), at + Vector2(d * 0.45, d * 0.05), col, w, true)
	else:                                   # an eye-like diamond
		c.draw_polyline(PackedVector2Array([at + Vector2(-d, 0), at + Vector2(0, -d * 0.6), at + Vector2(d, 0), at + Vector2(0, d * 0.6), at + Vector2(-d, 0)]), col, w, true)
		c.draw_circle(at, d * 0.22, col, true, -1.0, true)

## A line with round ends (draw_line has square ones).
static func _seg(c: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	c.draw_line(a, b, col, w, true)
	c.draw_circle(a, w * 0.5, col, true, -1.0, true)
	c.draw_circle(b, w * 0.5, col, true, -1.0, true)

static func _ellipse(center: Vector2, rx: float, ry: float, ang: float, n := 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cs := cos(ang)
	var sn := sin(ang)
	for i in n:
		var a := float(i) / n * TAU
		var p := Vector2(cos(a) * rx, sin(a) * ry)
		pts.append(center + Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs))
	return pts

## A filled shape with an ink outline (the outline's inner half is covered by the fill).
static func _blob(c: CanvasItem, pts: PackedVector2Array, fill: Color, ink: Color, w: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	c.draw_polyline(closed, ink, w, true)
	c.draw_colored_polygon(pts, fill)

static func _style_col(st: Dictionary, key: String, def: String) -> Color:
	var v = st.get(key, def)
	return v if v is Color else Color(str(v))

## Two rails and even rungs (the style's rail / rung, or a candy stripe): a soft shadow, an outline pass, the colours,
## a thin shine. u: one square in texture pixels.
static func _paint_ladders(c: CanvasItem, u: float, st: Dictionary) -> void:
	var rail := _style_col(st, "rail", RAIL)
	var rung := _style_col(st, "rung", RUNG)
	var stripe: Array = st.get("stripe", [])
	rail = rail.darkened(clampf((rail.get_luminance() - 0.58) * 3.0, 0.0, 0.5))   # a pale rail would vanish on the tiles
	var ink := rail.darkened(0.55)
	var shadow := Color(0.29, 0.17, 0.24, 0.16)
	var rw := u * 0.1
	var gw := u * 0.075
	var ow := u * 0.045
	var drop := Vector2(u * 0.025, u * 0.035)
	for f in SnakesLaddersRules.LADDERS:
		var a := (grid_of(f) + END_NUDGE) * u
		var b := (grid_of(SnakesLaddersRules.LADDERS[f]) + END_NUDGE) * u
		var d := b - a
		var dir := d.normalized()
		var nrm := Vector2(-dir.y, dir.x) * u * LADDER_HALF
		var ext := dir * u * 0.12
		var rails := []                       # [start, end] of each rail
		for s in [1.0, -1.0]:
			rails.append([a + nrm * s - ext, b + nrm * s + ext])
		var rungs := []
		var n := maxi(2, roundi(d.length() / (u * 0.42)))
		for i in range(1, n):
			var m := a + d * (float(i) / n)
			rungs.append([m - nrm, m + nrm])
		for r in rails:
			_seg(c, r[0] + drop, r[1] + drop, shadow, rw + ow * 1.6)
		for r in rungs:
			_seg(c, r[0] + drop, r[1] + drop, shadow, gw + ow * 1.6)
		for r in rungs:
			_seg(c, r[0], r[1], ink, gw + ow)
		for r in rails:
			_seg(c, r[0], r[1], ink, rw + ow)
		for r in rungs:
			_seg(c, r[0], r[1], rung, gw)
		for r in rails:
			var p0: Vector2 = r[0]
			var p1: Vector2 = r[1]
			_seg(c, p0, p1, Color(str(stripe[1])) if stripe.size() > 1 else rail, rw)
			if stripe.size() > 1:             # candy-cane rails
				var k := maxi(2, roundi(p0.distance_to(p1) / (u * 0.2)))
				for i in range(0, k, 2):
					c.draw_line(p0.lerp(p1, float(i) / k), p0.lerp(p1, float(i + 1) / k), Color(str(stripe[0])), rw, true)
			var side := nrm * 0.14
			c.draw_line(p0 - side + dir * u * 0.04, p1 - side - dir * u * 0.04, Color(1, 1, 1, 0.4), u * 0.022, true)

## A tapered wavy body along the path the pawns ride (snake_body, head first), soft spots, a round head with big eyes
## and a forked tongue; the tail comes to a point.
static func _paint_snakes(c: CanvasItem, u: float, st: Dictionary) -> void:
	var cols: Array = st.get("snakes", SNAKE_COL)
	var i := 0
	for h in SnakesLaddersRules.SNAKES:
		var col := Color(str(cols[i % cols.size()]))
		var ink := col.darkened(0.5)
		var n := 40
		var P := PackedVector2Array()
		for q in snake_body(h, n):
			P.append(q * u)
		var half := func(j: int) -> float:      # half the body's width at point j (the head end is the widest)
			return u * (0.15 - 0.115 * pow(float(j) / n, 1.15))
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for j in n + 1:
			var t := (P[mini(j + 1, n)] - P[maxi(j - 1, 0)]).normalized()
			var w: float = half.call(j)
			left.append(P[j] + Vector2(t.y, -t.x) * w)
			right.append(P[j] + Vector2(-t.y, t.x) * w)
		var poly := PackedVector2Array(left)
		poly.append(P[n] + (P[n] - P[n - 1]).normalized() * u * 0.1)       # the tail tip
		for j in range(n, -1, -1):
			poly.append(right[j])
		var shadow := PackedVector2Array()       # a soft shadow under the body
		for q in poly:
			shadow.append(q + Vector2(u * 0.02, u * 0.035))
		c.draw_colored_polygon(shadow, Color(0.29, 0.17, 0.24, 0.16))
		_blob(c, poly, col, ink, u * 0.05)
		var pattern: String = st.get("snakePattern", "")
		if pattern == "stripes":                 # slanted candy bands across the body
			for j in range(4, n - 3, 3):
				c.draw_colored_polygon(PackedVector2Array([left[j], left[j + 1], right[j + 2], right[j + 1]]), Color(1, 1, 1, 0.55))
		elif pattern == "diamonds":              # a row of pale diamonds down the back
			for j in range(4, n - 3, 3):
				var t := (P[j + 1] - P[j - 1]).normalized()
				var l: float = half.call(j) * 1.05
				var w: float = half.call(j) * 0.55
				var nr := Vector2(-t.y, t.x)
				c.draw_colored_polygon(PackedVector2Array([P[j] - t * l, P[j] + nr * w, P[j] + t * l, P[j] - nr * w]), Color(1, 0.957, 0.84, 0.62))
		else:
			var spot := col.darkened(0.18)       # back spots
			for j in range(5, n - 3, 4):
				var w: float = half.call(j)
				c.draw_colored_polygon(_ellipse(P[j], w * 0.62, w * 0.4, (P[j + 1] - P[j - 1]).angle(), 16), spot)
		var shine := PackedVector2Array()        # a soft shine along one side
		for j in range(3, n - 6):
			shine.append((P[j] * 2.0 + left[j]) / 3.0)
		c.draw_polyline(shine, Color(1, 1, 1, 0.38), u * 0.028, true)
		# the head, pointing away from the body, on the head square
		var ang := (P[0] - P[3]).angle()
		var fw := Vector2(cos(ang), sin(ang))
		var sd := Vector2(-fw.y, fw.x)
		var at := func(f: float, s: float) -> Vector2:
			return P[0] + (fw * f + sd * s) * u
		_blob(c, _ellipse(at.call(0.05, 0.0), u * 0.27, u * 0.22, ang, 36), col, ink, u * 0.05)
		var t0: Vector2 = at.call(0.28, 0.0)     # forked tongue
		var t1: Vector2 = at.call(0.4, 0.0)
		var red := Color("#e5484d")
		_seg(c, t0, t1, red, u * 0.03)
		_seg(c, t1, at.call(0.46, -0.05), red, u * 0.03)
		_seg(c, t1, at.call(0.46, 0.05), red, u * 0.03)
		for s in [-1.0, 1.0]:
			c.draw_colored_polygon(_ellipse(at.call(0.1, s * 0.15), u * 0.045, u * 0.03, ang, 12), Color(1, 0.55, 0.63, 0.55))   # cheeks
			var e: Vector2 = at.call(-0.02, s * 0.11)
			c.draw_circle(e, u * 0.096, ink, true, -1.0, true)
			c.draw_circle(e, u * 0.085, Color.WHITE, true, -1.0, true)
			var pp: Vector2 = at.call(0.0, s * 0.11) + fw * u * 0.02
			c.draw_circle(pp, u * 0.042, Color("#2a1d24"), true, -1.0, true)
			c.draw_circle(pp + fw * u * 0.01 + sd * u * 0.015, u * 0.014, Color.WHITE, true, -1.0, true)
		c.draw_arc(at.call(0.08, 0.0), u * 0.1, ang - 0.7, ang + 0.7, 16, ink, u * 0.02, true)   # a little smile
		i += 1


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

## Glide up the painted ladder from its foot to its top, stepping over the rungs.
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
		p.x += END_NUDGE.x * C * lift                            # along the painted ladder's centre line
		p.z += END_NUDGE.y * C * lift
		p.y = TOP + lift * (0.04 + absf(sin(e * rungs * PI)) * 0.1)      # a step per rung on the flat ladder
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
	var path := PackedVector3Array([t.node.position])      # then along the painted body, head to tail
	for q in snake_body(head):
		path.append(grid_to_world(q))
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
