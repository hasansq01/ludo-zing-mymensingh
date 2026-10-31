class_name PawnArt
## The board's pawn (LudoBoard.PAWN_PROFILE lathe + the 0.19 head sphere at y 0.74: the same pawn Ludo and Snakes &
## Ladders use) drawn flat into any CanvasItem in a player colour, for the setup sheets' seat rows and colour choices
## and the lobby. With a pawn skin (Catalog.PAWNS) it is that skin's silhouette in the same colour: the knight's
## base and horse head, the teacup, the crown / ears / gold bands on the classic pawn, and a few veins (marble) or
## sparkles (glitter) over it, as PawnSkins builds them in 3D.
## Pure 2D draw calls (a few polygons, circles, lines): no texture, no SubViewport, no GPU work beyond the draw,
## nothing to cache but the outlines. Use PawnArt.draw(self, rect, colour_index, rim, skin) from a _draw().

const HEAD_Y := 0.74
const HEAD_R := 0.19
const TOP := HEAD_Y + HEAD_R          ## the classic pawn's height in board units
const HALF_W := 0.38                  ## its widest half-width (the base)
const GOLD := Color("#f4c542")
const GOLD_DEEP := Color("#b8860b")

static var _polys := {}               # skin -> the body outline, y up, built once

## The lathe profile of a skin's body (radius, height), closed on the axis.
static func _profile(skin: String) -> Array:
	match skin:
		"knight":
			return PawnSkins.KNIGHT_BASE
		"teacup":
			var cup: Array = PawnSkins.CUP.slice(0, 13)      # the outside, up to the rim
			cup.append([.29, .645])
			cup.append([0, .645])
			return cup
	return LudoBoard.PAWN_PROFILE

## The body outline (both halves) of a skin.
static func _outline(skin: String) -> PackedVector2Array:
	if not _polys.has(skin):
		var poly := PackedVector2Array()
		var right := []
		for p in _profile(skin):
			right.append(Vector2(p[0], p[1]))
		for p in right:
			poly.append(p)
		for k in range(right.size() - 2, 0, -1):
			poly.append(Vector2(-right[k].x, right[k].y))
		_polys[skin] = poly
	return _polys[skin]

## A skin's height in board units (the drawing fits it to the rect).
static func height(skin: String) -> float:
	match skin:
		"knight": return 1.08
		"crown": return HEAD_Y + 0.29
		"kitty": return HEAD_Y + 0.29
		"teacup": return 0.66
		"trim": return TOP + 0.07
	return TOP

## Draw the pawn of player colour c, standing on the bottom edge of `rect` and as tall as it allows (aspect kept),
## in pawn skin `skin` ("" = Classic).
static func draw(ci: CanvasItem, rect: Rect2, c: int, rim := Color.TRANSPARENT, skin := "") -> void:
	c = clampi(c, 0, 3)
	if Catalog.pawn(skin).is_empty():
		skin = Catalog.FREE_PAWN
	var tall := maxf(height(skin), TOP)
	var s := minf(rect.size.y / tall, rect.size.x / (HALF_W * 2.0 + (0.12 if skin == "teacup" else 0.0)))
	var o := Vector2(rect.position.x + rect.size.x / 2.0, rect.end.y)
	var face: Color = Palette.PLAYER[c]
	var deep: Color = Palette.PLAYER_DARK[c]
	var map := func(p: Vector2) -> Vector2: return o + Vector2(p.x, -p.y) * s
	var line := maxf(1.0, s * 0.03)
	# contact shadow
	var sh := PackedVector2Array()
	for k in 20:
		var a := TAU * float(k) / 20.0
		sh.append(o + Vector2(cos(a) * HALF_W * 0.95, -0.02 + sin(a) * 0.07) * s + Vector2(0, 0.01 * s))
	ci.draw_colored_polygon(sh, Color(deep, 0.35))
	if skin == "teacup":                 # the handle behind the cup's right side
		ci.draw_arc(map.call(Vector2(0.31, 0.37)), 0.09 * s, -PI * 0.55, PI * 0.55, 16, face, maxf(2.0, s * 0.06), true)
		ci.draw_arc(map.call(Vector2(0.31, 0.37)), 0.09 * s, -PI * 0.55, PI * 0.55, 16, Color(deep, 0.5), maxf(1.0, s * 0.02), true)
	var body := PackedVector2Array()
	for p in _outline(skin):
		body.append(map.call(p))
	ci.draw_colored_polygon(body, face)
	body.append(body[0])
	var heads := skin != "knight" and skin != "teacup"
	if rim.a > 0.0:                      # a pawn on its own colour needs a rim to stand out
		ci.draw_polyline(body, rim, maxf(1.5, s * 0.07), true)
		if heads:
			ci.draw_circle(map.call(Vector2(0.0, HEAD_Y)), HEAD_R * s + maxf(0.75, s * 0.035), rim, false, maxf(1.5, s * 0.07), true)
	ci.draw_polyline(body, Color(deep, 0.9), line, true)
	# the right half in shade (the profile itself closes the polygon on the axis)
	var side := PackedVector2Array()
	for p in _profile(skin):
		side.append(map.call(Vector2(p[0] * 0.999, p[1])))
	ci.draw_colored_polygon(side, Color(deep, 0.38))
	match skin:
		"knight":
			_knight(ci, map, s, face, deep, rim)
		"teacup":
			var top: Vector2 = map.call(Vector2(0.0, 0.632))
			_ellipse(ci, top, Vector2(0.29, 0.04) * s, PawnSkins.froth(face))
			_ellipse(ci, top + Vector2(-0.06, -0.004) * s, Vector2(0.12, 0.018) * s, Color(1, 1, 1, 0.55))
		_:
			if skin == "kitty":
				_ears(ci, map, s, face, deep)
			var hc: Vector2 = map.call(Vector2(0.0, HEAD_Y))
			ci.draw_circle(hc, HEAD_R * s, face, true, -1.0, true)
			ci.draw_circle(hc + Vector2(HEAD_R * s * 0.3, HEAD_R * s * 0.15), HEAD_R * s * 0.7, Color(deep, 0.30), true, -1.0, true)
			ci.draw_circle(hc + Vector2(-0.07, -0.07) * s, 0.055 * s, Color(1, 1, 1, 0.75), true, -1.0, true)
			if skin == "crown":
				_crown(ci, map, s, face)
	# a gloss streak down the lit side of the body
	if skin != "teacup":
		var g := PackedVector2Array([map.call(Vector2(-0.2, 0.17)), map.call(Vector2(-0.12, 0.3)), map.call(Vector2(-0.08, 0.45)), map.call(Vector2(-0.14, 0.44)), map.call(Vector2(-0.17, 0.3))])
		ci.draw_colored_polygon(g, Color(1, 1, 1, 0.4))
	match skin:
		"trim":
			for b: Array in [[0.035, 0.37], [0.3, 0.17], [0.535, 0.25]]:
				ci.draw_line(map.call(Vector2(-b[1], b[0])), map.call(Vector2(b[1], b[0])), GOLD, maxf(1.5, s * 0.05), true)
			ci.draw_circle(map.call(Vector2(0.0, HEAD_Y + HEAD_R + 0.01)), 0.05 * s, GOLD, true, -1.0, true)
		"marble":
			var vein := Color(1, 1, 1, 0.7)
			var w := maxf(1.0, s * 0.025)
			ci.draw_polyline(_pts(map, [[-0.22, 0.12], [-0.06, 0.2], [0.04, 0.33], [0.12, 0.45]]), vein, w, true)
			ci.draw_polyline(_pts(map, [[0.18, 0.1], [0.08, 0.16], [0.1, 0.26]]), vein, w * 0.8, true)
			ci.draw_polyline(_pts(map, [[-0.1, 0.66], [0.0, 0.74], [0.08, 0.84]]), vein, w, true)
		"glitter":
			for d: Array in [[-0.2, 0.08, 1.0], [0.05, 0.13, 0.7], [0.22, 0.06, 0.8], [-0.06, 0.26, 0.9], [0.09, 0.38, 0.7],
					[-0.1, 0.43, 0.6], [0.12, 0.53, 0.8], [-0.07, 0.68, 0.9], [0.08, 0.8, 1.0], [0.0, 0.6, 0.6]]:
				var at: Vector2 = map.call(Vector2(d[0], d[1]))
				var r := maxf(0.8, s * 0.022 * float(d[2]))
				ci.draw_circle(at, r, Color(1, 1, 1, 0.9), true, -1.0, true)
				ci.draw_line(at - Vector2(r * 2.2, 0), at + Vector2(r * 2.2, 0), Color(1, 1, 1, 0.5), maxf(0.6, r * 0.5), true)

static func _pts(map: Callable, a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(map.call(Vector2(p[0], p[1])))
	return out

static func _ellipse(ci: CanvasItem, at: Vector2, r: Vector2, col: Color) -> void:
	var e := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		e.append(at + Vector2(cos(a) * r.x, sin(a) * r.y))
	ci.draw_colored_polygon(e, col)

## The knight's horse head (PawnSkins.KNIGHT, facing right) and its eye.
static func _knight(ci: CanvasItem, map: Callable, s: float, face: Color, deep: Color, rim: Color) -> void:
	var horse := _pts(map, PawnSkins.KNIGHT)
	ci.draw_colored_polygon(horse, face)
	horse.append(horse[0])
	if rim.a > 0.0:
		ci.draw_polyline(horse, rim, maxf(1.5, s * 0.07), true)
	ci.draw_polyline(horse, Color(deep, 0.9), maxf(1.0, s * 0.03), true)
	ci.draw_colored_polygon(_pts(map, [[-0.03, 0.995], [-0.075, 0.955], [-0.125, 0.885], [-0.185, 0.77], [-0.205, 0.63], [-0.12, 0.7], [-0.07, 0.85]]), Color(deep, 0.38))
	ci.draw_circle(map.call(Vector2(0.105, 0.86)), 0.03 * s, PawnSkins.INK, true, -1.0, true)

## Two cat ears on the head, pink inside.
static func _ears(ci: CanvasItem, map: Callable, s: float, face: Color, deep: Color) -> void:
	for sx in [-1.0, 1.0]:
		var outer := _pts(map, [[sx * 0.05, HEAD_Y + 0.15], [sx * 0.22, HEAD_Y + 0.29], [sx * 0.19, HEAD_Y + 0.05]])
		ci.draw_colored_polygon(outer, face)
		var ol := outer.duplicate()
		ol.append(ol[0])
		ci.draw_polyline(ol, Color(deep, 0.9), maxf(1.0, s * 0.03), true)
		ci.draw_colored_polygon(_pts(map, [[sx * 0.095, HEAD_Y + 0.145], [sx * 0.205, HEAD_Y + 0.25], [sx * 0.18, HEAD_Y + 0.085]]), PawnSkins.EAR)

## The gold crown on the head, a gem of the seat colour on its band.
static func _crown(ci: CanvasItem, map: Callable, s: float, face: Color) -> void:
	var y0 := HEAD_Y + 0.11
	var y1 := HEAD_Y + 0.19
	var crown := _pts(map, [[-0.155, y0], [-0.16, y1 + 0.07], [-0.08, y1], [0.0, y1 + 0.09], [0.08, y1], [0.16, y1 + 0.07], [0.155, y0]])
	ci.draw_colored_polygon(crown, GOLD)
	crown.append(crown[0])
	ci.draw_polyline(crown, GOLD_DEEP, maxf(1.0, s * 0.025), true)
	for x in [-0.16, 0.0, 0.16]:
		ci.draw_circle(map.call(Vector2(x, y1 + (0.09 if x == 0.0 else 0.07))), 0.022 * s, GOLD, true, -1.0, true)
	ci.draw_circle(map.call(Vector2(0.0, (y0 + y1) / 2.0)), 0.032 * s, face, true, -1.0, true)
