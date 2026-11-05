class_name SLTrail
extends RefCounted
## The Snake Trail board (index.html: SL_LAYOUTS.trail, paintTrail): one winding road of 8 wavy bands joined by round
## bends, so the path itself looks like a long snake. Square 1 is by its head, 100 at its tail with a trophy. The tiles
## are its body segments: snake heads red, ladder feet yellow. Pure geometry and painting; the rules are
## SnakesLaddersRules (board "trail"), the board is SLBoard (style layout "trail").
##
## The path is in board units (0..10, y up); cell() gives square n in squares from the face's top-left corner (y down),
## as SLBoard.grid_of does for the grid.

const BANDS := 8
const Y0 := 0.75
const S := 8.5 / 7.0                    # one band to the next
const XL := 1.25
const XR := 8.75
const AMP := 0.2                        # the bands' wave
const HW := 0.4                         # half the road's width
const NUM_FS := 0.32                    # square numbers: font size as a share of a square (a tile is ~0.74 long)
## Fallback colours (a style's `trail`): clouds, ink, the two body colours, snake heads, ladder feet, the trophy.
const COLORS := {cloud = "#ffffff", outline = "#2c5a17", tiles = ["#7cc84a", "#c5ea6a"], red = "#ff5a4f", yellow = "#ffd84d", trophy = "#f4b82a"}

static var _pts := PackedVector2Array()
static var _cum := PackedFloat32Array()
static var _cells := PackedVector2Array()

static func _build() -> void:
	if not _pts.is_empty():
		return
	var R := S / 2.0
	for b in BANDS:
		var y := Y0 + b * S
		var right := b % 2 == 0
		for i in 61:
			var f := i / 60.0
			var x := XL + (XR - XL) * f if right else XR - (XR - XL) * f
			_pts.append(Vector2(x, y + AMP * sin((x - XL) / (XR - XL) * TAU)))
		if b < BANDS - 1:
			for i in range(1, 24):
				var a := -PI / 2.0 + (1.0 if right else -1.0) * PI * i / 24.0
				_pts.append(Vector2((XR if right else XL) + R * cos(a), y + R + R * sin(a)))
	_cum.append(0.0)
	for i in range(1, _pts.size()):
		_cum.append(_cum[i - 1] + _pts[i].distance_to(_pts[i - 1]))
	_cells.append(Vector2.ZERO)                 # (squares run from 1)
	for n in range(1, 101):
		var p: Vector2 = at((n - 0.5) * pitch()).p
		_cells.append(Vector2(p.x, 10.0 - p.y))

## The road's length, in board units.
static func total() -> float:
	_build()
	return _cum[_cum.size() - 1]

## One tile's length along the road.
static func pitch() -> float:
	return total() / 100.0

## The point and direction at distance s along the road (clamped to it): {p, d}, board units, y up.
static func at(s: float) -> Dictionary:
	_build()
	s = clampf(s, 0.0, _cum[_cum.size() - 1])
	var i := clampi(_cum.bsearch(s), 1, _cum.size() - 1)
	var a := _pts[i - 1]
	var b := _pts[i]
	var seg := maxf(_cum[i] - _cum[i - 1], 0.000001)
	return {p = a.lerp(b, (s - _cum[i - 1]) / seg), d = (b - a).normalized()}

## Centre of square n in squares from the top-left corner of the face.
static func cell(n: int) -> Vector2:
	_build()
	return _cells[clampi(n, 1, 100)]

## In texture space (y down): the point at distance s, its direction.
static func _pt(s: float, u: float) -> Array:
	var q := at(s)
	return [Vector2(q.p.x * u, (10.0 - q.p.y) * u), Vector2(q.d.x, -q.d.y)]

## The road between distances s0 and s1 as one closed outline.
static func _band(s0: float, s1: float, u: float) -> PackedVector2Array:
	var k := maxi(2, ceili((s1 - s0) / 0.08))
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in k + 1:
		var q := _pt(s0 + (s1 - s0) * i / k, u)
		var nrm := Vector2(-q[1].y, q[1].x) * HW * u
		left.append(q[0] + nrm)
		right.append(q[0] - nrm)
	right.reverse()
	left.append_array(right)
	return left

## Everything under the snakes and ladders: the clouds on the sky, the body with its outline, tail and head, a tile per
## square and the trophy at the tail's tip. u: one square in texture pixels. st: the board style.
static func paint(c: CanvasItem, u: float, st: Dictionary) -> void:
	var T: Dictionary = st.get("trail", COLORS)
	var ink := Color(str(T.outline))
	var body: Array = T.tiles
	_clouds(c, u, Color(str(T.cloud), 0.9))
	var line := PackedVector2Array()              # the outline under the whole body: one fat stroke along the road
	var s := 0.0
	while s <= total():
		line.append(_pt(s, u)[0])
		s += 0.05
	c.draw_polyline(line, ink, (HW * 2.0 + 0.1) * u, true)
	var tip := _tail(c, u, ink, Color(str(body[0])))
	_head(c, u, ink, Color(str(body[0])))
	var goal := Color(str(st.get("goal", "#ffd45c")))
	for n in range(1, 101):
		var col := goal if n == 100 else Color(str(T.red)) if SnakesLaddersRules.TRAIL_SNAKES.has(n) else Color(str(T.yellow)) if SnakesLaddersRules.TRAIL_LADDERS.has(n) else Color(str(body[n % body.size()]))
		var tile := _band((n - 1) * pitch(), n * pitch(), u)
		var k := tile.size() / 2                  # filled as a strip: a tile on a bend can cross itself on the inside
		for i in k - 1:                           # (as one polygon it wouldn't triangulate, and wouldn't be filled at all)
			c.draw_primitive(PackedVector2Array([tile[i], tile[i + 1], tile[2 * k - 2 - i], tile[2 * k - 1 - i]]), PackedColorArray([col]), PackedVector2Array())
		var ring := tile.duplicate()
		ring.append(tile[0])
		c.draw_polyline(ring, ink, u * 0.04, true)
	_trophy(c, u, tip, Color(str(T.trophy)))

static func _clouds(c: CanvasItem, u: float, col: Color) -> void:
	for q in [[1.6, 9.7, 0.5], [5.2, 9.75, 0.6], [8.6, 9.7, 0.45], [3.4, 0.25, 0.5], [7.2, 0.2, 0.55], [9.7, 5.0, 0.35], [0.3, 4.6, 0.35]]:
		for p in [[0.0, 0.0, 1.0], [0.8, 0.1, 0.7], [-0.8, 0.12, 0.75], [0.3, -0.35, 0.65]]:
			var at_ := Vector2((q[0] + p[0] * q[2]) * u, (10.0 - q[1]) * u + p[1] * q[2] * u)
			c.draw_circle(at_, p[2] * q[2] * u, col, true, -1.0, true)

## The tail: tapering on past 100, with a little upward flick. Returns its tip.
static func _tail(c: CanvasItem, u: float, ink: Color, col: Color) -> Vector2:
	var e := _pt(total(), u)
	var mid := PackedVector2Array()
	var half := PackedFloat32Array()
	for i in 13:
		var f := i / 12.0
		mid.append(e[0] + e[1] * f * 0.95 * u - Vector2(0, f * f * 0.35 * u))
		half.append((1.0 - f) * HW * u)
	for pass_ in 2:
		var grow := u * 0.05 if pass_ == 0 else 0.0
		var poly := PackedVector2Array()
		for i in 13:
			poly.append(mid[i] - Vector2(0, half[i] + grow))
		for i in range(12 if pass_ == 0 else 11, -1, -1):   # (with no margin, the two sides meet at the tip)
			poly.append(mid[i] + Vector2(0, half[i] + grow))
		c.draw_colored_polygon(poly, ink if pass_ == 0 else col)
	return mid[12]

## The head before square 1, looking back along the road: big eyes on top, a forked tongue, a wide smile.
static func _head(c: CanvasItem, u0: float, ink: Color, col: Color) -> void:
	var st := _pt(0.0, u0)
	var h: Vector2 = st[0] - st[1] * 0.52 * u0
	var u := u0 * 0.8
	var red := Color("#e5484d")
	_ellipse(c, h, u * 0.62, u * 0.5, col, ink, u * 0.05)
	c.draw_line(h + Vector2(-0.5, 0.2) * u, h + Vector2(-0.66, 0.42) * u, red, u * 0.045, true)
	c.draw_line(h + Vector2(-0.66, 0.42) * u, h + Vector2(-0.78, 0.42) * u, red, u * 0.045, true)
	c.draw_line(h + Vector2(-0.66, 0.42) * u, h + Vector2(-0.66, 0.55) * u, red, u * 0.045, true)
	for e in [Vector2(-0.2, -0.42), Vector2(0.2, -0.46)]:
		_ellipse(c, h + e * u, u * 0.2, u * 0.24, Color.WHITE, ink, u * 0.04)
		c.draw_circle(h + (e + Vector2(0.06, 0.04)) * u, u * 0.1, Color("#1d2a14"), true, -1.0, true)
		c.draw_circle(h + (e + Vector2(0.09, 0.0)) * u, u * 0.035, Color.WHITE, true, -1.0, true)
	for n in [Vector2(-0.42, -0.02), Vector2(-0.3, 0.05)]:      # nostrils
		c.draw_circle(h + n * u, u * 0.04, col.darkened(0.35), true, -1.0, true)
	c.draw_arc(h + Vector2(0.05, -0.02) * u, u * 0.32, 0.45, 1.9, 16, ink, u * 0.045, true)
	var cheek := PackedVector2Array()
	for k in 16:
		var a := k / 16.0 * TAU
		cheek.append(h + Vector2(0.3 + cos(a) * 0.09, 0.12 + sin(a) * 0.06) * u)
	c.draw_colored_polygon(cheek, Color(1, 0.55, 0.63, 0.5))

static func _ellipse(c: CanvasItem, at_: Vector2, rx: float, ry: float, fill: Color, ink: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for k in 36:
		var a := k / 36.0 * TAU
		pts.append(at_ + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	c.draw_polyline(pts, ink, w, true)

static func _trophy(c: CanvasItem, u: float, tip: Vector2, col: Color) -> void:
	var s := u * 0.2
	var at_ := tip + Vector2(0.1, -0.32) * u      # (a little to the right of the web's: its handle would leave the face)
	var ink := col.darkened(0.45)
	var w := u * 0.03
	for k in [-1.0, 1.0]:                         # the handles, under the cup
		c.draw_arc(at_ + Vector2(k * s * 1.05, -s * 0.1), s * 0.32, 0.0, TAU, 20, ink, w, true)
	var cup := PackedVector2Array([at_ + Vector2(-s, -s * 0.5), at_ + Vector2(s, -s * 0.5)])
	for i in range(1, 9):                         # the bowl: two soft curves down to the stem
		var f := i / 8.0
		cup.append(at_ + Vector2(s * (1.0 - f * f), lerpf(-s * 0.5, s * 0.7, sqrt(f))))
	for i in range(7, 0, -1):
		var f := i / 8.0
		cup.append(at_ + Vector2(-s * (1.0 - f * f), lerpf(-s * 0.5, s * 0.7, sqrt(f))))
	c.draw_colored_polygon(cup, col)
	var ring := cup.duplicate()
	ring.append(cup[0])
	c.draw_polyline(ring, ink, w, true)
	c.draw_rect(Rect2(at_ + Vector2(-s * 0.15, s * 0.7), Vector2(s * 0.3, s * 0.35)), col)
	c.draw_rect(Rect2(at_ + Vector2(-s * 0.55, s * 1.05), Vector2(s * 1.1, s * 0.25)), col)
