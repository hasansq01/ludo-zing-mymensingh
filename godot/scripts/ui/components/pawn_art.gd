class_name PawnArt
## The board's pawn (LudoBoard.PAWN_PROFILE lathe + the 0.19 head sphere at y 0.74: the same pawn Ludo and Snakes &
## Ladders use) drawn flat into any CanvasItem in a player colour, for the setup sheets' seat rows and colour choices
## and the lobby. With a pawn skin (Catalog.PAWNS) it is that skin's silhouette in the same colour: the knight's
## base and horse head, the teacup, the crown / ears / gold bands on the classic pawn, and a few veins (marble) or
## sparkles (glitter) over it, as PawnSkins builds them in 3D. The themed skins draw their own body and a simple
## picture of their head (the cupcake, the fruit, the flower, the tricorn, the visor, the hat, the horns).
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
		"candy", "fruity", "blossom", "pirate", "dragon":
			return PawnSkins.BELL
		"wizard":
			return PawnSkins.ROBE
		"ice":
			return PawnSkins.COLUMN
		"robo", "space":
			return PawnSkins.FOOT.slice(0, 5) + PawnSkins.SUIT.slice(1)
	return LudoBoard.PAWN_PROFILE

## A skin's round head: its centre's height and radius (the themed skins' own; r 0: no plain head).
static func _head_of(skin: String, c: int) -> Vector2:
	match skin:
		"knight", "teacup", "blossom": return Vector2.ZERO
		"candy", "pirate", "dragon": return Vector2(PawnSkins.BELL_HEAD_Y, 0.2)
		"fruity": return Vector2(0.8, 0.2) if PawnSkins.FRUIT[c] != "melon" else Vector2.ZERO
		"robo": return Vector2(0.82, 0.2)
		"space": return Vector2(0.82, 0.24)
		"wizard": return Vector2(0.76, 0.165)
		"ice": return Vector2(0.78, 0.19)
	return Vector2(HEAD_Y, HEAD_R)

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
		"candy": return 1.02
		"fruity": return 1.05
		"blossom": return 1.08
		"ice": return 1.15
		"pirate", "robo", "wizard", "dragon": return 1.15
		"space": return 1.06
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
	if skin == "dragon":                 # the wings behind the body
		for sx in [-1.0, 1.0]:
			ci.draw_colored_polygon(_pts(map, [[sx * 0.15, 0.36], [sx * 0.15, 0.5], [sx * 0.38, 0.54], [sx * 0.36, 0.42], [sx * 0.28, 0.42]]), face.lerp(Color.WHITE, 0.28))
	if skin == "teacup":                 # the handle behind the cup's right side
		ci.draw_arc(map.call(Vector2(0.31, 0.37)), 0.09 * s, -PI * 0.55, PI * 0.55, 16, face, maxf(2.0, s * 0.06), true)
		ci.draw_arc(map.call(Vector2(0.31, 0.37)), 0.09 * s, -PI * 0.55, PI * 0.55, 16, Color(deep, 0.5), maxf(1.0, s * 0.02), true)
	var body := PackedVector2Array()
	for p in _outline(skin):
		body.append(map.call(p))
	ci.draw_colored_polygon(body, face)
	body.append(body[0])
	var round_head := _head_of(skin, c)
	if rim.a > 0.0:                      # a pawn on its own colour needs a rim to stand out
		ci.draw_polyline(body, rim, maxf(1.5, s * 0.07), true)
		if round_head.y > 0.0:
			ci.draw_circle(map.call(Vector2(0.0, round_head.x)), round_head.y * s + maxf(0.75, s * 0.035), rim, false, maxf(1.5, s * 0.07), true)
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
			if round_head.y > 0.0:
				var hr := round_head.y
				var hc: Vector2 = map.call(Vector2(0.0, round_head.x))
				var skull: Color = Color(str(PawnSkins.INKS.white)) if skin == "robo" or skin == "space" else Color(str(PawnSkins.INKS.orange)) if skin == "fruity" and PawnSkins.FRUIT[c] == "orange" else face
				ci.draw_circle(hc, hr * s, skull, true, -1.0, true)
				ci.draw_circle(hc + Vector2(hr * s * 0.3, hr * s * 0.15), hr * s * 0.7, Color(deep if skull == face else Color("#8a7f70"), 0.30), true, -1.0, true)
				ci.draw_circle(hc + Vector2(-0.07, -0.07) * s, 0.055 * s, Color(1, 1, 1, 0.75), true, -1.0, true)
			if skin == "crown":
				_crown(ci, map, s, face)
			_themed(ci, map, s, skin, c, face, deep)
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

## The themed skins' heads and details over the body, in a few shapes (these pawns are small on screen).
static func _themed(ci: CanvasItem, map: Callable, s: float, skin: String, c: int, face: Color, deep: Color) -> void:
	var ink := func(key: String) -> Color: return Color(str(PawnSkins.INKS[key]))
	var line := maxf(1.0, s * 0.03)
	match skin:
		"candy":
			for y: float in [0.1, 0.27, 0.44]:             # the stripes, leaning
				var a := PawnSkins._r_at(PawnSkins.BELL, y)
				var b := PawnSkins._r_at(PawnSkins.BELL, y + 0.09)
				ci.draw_colored_polygon(_pts(map, [[-a, y], [-b, y + 0.09], [b, y + 0.17], [a, y + 0.08]]), ink.call("cream"))
			var y0 := PawnSkins.BELL_HEAD_Y
			ci.draw_colored_polygon(_arc(map, Vector2(0, y0), 0.212, -0.05, PI + 0.05), ink.call("cream"))
			for d: Array in [[-0.09, 0.09, "pink"], [0.04, 0.14, "sky"], [0.11, 0.05, "lemon"], [-0.02, 0.05, "lime"]]:
				ci.draw_circle(map.call(Vector2(d[0], y0 + d[1])), 0.018 * s, ink.call(d[2]), true, -1.0, true)
		"fruity":
			ci.draw_colored_polygon(_pts(map, [[-0.15, 0.6], [-0.13, 0.5], [-0.08, 0.56], [-0.02, 0.48], [0.05, 0.56], [0.11, 0.5], [0.15, 0.6], [0.11, 0.67], [-0.11, 0.67]]), face.lerp(Color.BLACK, 0.18))
			match PawnSkins.FRUIT[c]:
				"strawberry":
					for d: Array in [[-0.09, 0.82], [0.05, 0.86], [0.1, 0.76], [-0.03, 0.72]]:
						ci.draw_circle(map.call(Vector2(d[0], d[1])), 0.016 * s, ink.call("dot"), true, -1.0, true)
					ci.draw_colored_polygon(_pts(map, [[-0.11, 0.96], [0.0, 1.05], [0.11, 0.96], [0.0, 0.99]]), ink.call("leaf"))
				"melon":
					ci.draw_colored_polygon(_pts(map, [[0.0, 0.95], [-0.2, 0.68], [-0.1, 0.65], [0.1, 0.65], [0.2, 0.68]]), ink.call("flesh"))
					ci.draw_polyline(_pts(map, [[-0.2, 0.67], [-0.1, 0.64], [0.1, 0.64], [0.2, 0.67]]), ink.call("rind"), maxf(1.5, s * 0.04), true)
					for d: Array in [[-0.05, 0.76], [0.05, 0.76], [0.0, 0.85]]:
						ci.draw_circle(map.call(Vector2(d[0], d[1])), 0.014 * s, ink.call("seed"), true, -1.0, true)
				"orange":
					ci.draw_line(map.call(Vector2(0.0, 1.0)), map.call(Vector2(0.0, 1.04)), ink.call("stem"), line, true)
					ci.draw_colored_polygon(_pts(map, [[0.0, 1.0], [0.08, 1.04], [0.14, 1.0], [0.06, 0.98]]), ink.call("leaf"))
				_:
					ci.draw_colored_polygon(_pts(map, [[-0.07, 0.98], [-0.09, 1.03], [-0.03, 1.0], [0.0, 1.04], [0.03, 1.0], [0.09, 1.03], [0.07, 0.98]]), ink.call("navy"))
		"blossom":
			ci.draw_polyline(_pts(map, [[-0.26, 0.2], [-0.05, 0.33], [0.11, 0.26], [0.2, 0.4]]), face.lerp(Color.WHITE, 0.62), maxf(1.5, s * 0.05), true)
			for sx in [-1.0, 1.0]:
				ci.draw_colored_polygon(_pts(map, [[0.0, 0.62], [sx * 0.15, 0.68], [sx * 0.28, 0.6], [sx * 0.14, 0.58]]), ink.call("leaf"))
			var petal := Color(["#ff86b0", "#8be07a", "#ffd84a", "#5fb0ff"][c])
			var mid := Vector2(0.0, 0.84)
			for k in 5:
				var a := TAU * k / 5.0
				ci.draw_circle(map.call(mid + Vector2(sin(a), cos(a)) * 0.14), 0.095 * s, petal, true, -1.0, true)
			ci.draw_circle(map.call(mid), 0.075 * s, Color("#e5484d" if c == 2 else "#ffd23f"), true, -1.0, true)
		"ice":
			var pale := face.lerp(Color.WHITE, 0.5)
			ci.draw_colored_polygon(_pts(map, [[-0.06, 0.9], [0.0, 1.15], [0.06, 0.9]]), pale)
			ci.draw_colored_polygon(_pts(map, [[-0.13, 0.86], [-0.14, 1.05], [-0.05, 0.92]]), pale)
			ci.draw_colored_polygon(_pts(map, [[0.13, 0.86], [0.14, 1.05], [0.05, 0.92]]), pale)
			for x: float in [-0.27, -0.13, 0.0, 0.13, 0.27]:
				ci.draw_colored_polygon(_pts(map, [[x - 0.05, 0.08], [x, 0.26], [x + 0.05, 0.08]]), pale)
		"pirate":
			var y0 := PawnSkins.BELL_HEAD_Y
			ci.draw_line(map.call(Vector2(-PawnSkins._r_at(PawnSkins.BELL, 0.21), 0.21)), map.call(Vector2(PawnSkins._r_at(PawnSkins.BELL, 0.21), 0.21)), ink.call("belt"), maxf(1.5, s * 0.06), true)
			ci.draw_circle(map.call(Vector2(0.0, 0.21)), 0.03 * s, ink.call("gold"), true, -1.0, true)
			ci.draw_line(map.call(Vector2(-0.2, y0 - 0.02)), map.call(Vector2(0.2, y0 + 0.05)), ink.call("felt"), maxf(1.0, s * 0.02), true)
			ci.draw_circle(map.call(Vector2(-0.07, y0 - 0.01)), 0.055 * s, ink.call("felt"), true, -1.0, true)
			var hat := _pts(map, [[-0.34, y0 + 0.06], [-0.2, y0 + 0.28], [0.0, y0 + 0.36], [0.2, y0 + 0.28], [0.34, y0 + 0.06], [0.0, y0 + 0.14]])
			ci.draw_colored_polygon(hat, ink.call("felt"))
			hat.append(hat[0])
			ci.draw_polyline(hat, ink.call("gold"), line, true)
			ci.draw_circle(map.call(Vector2(0.0, y0 + 0.23)), 0.04 * s, ink.call("white"), true, -1.0, true)
		"robo", "space":
			var y0 := 0.82
			var big := skin == "space"
			var off := 0.245 if big else 0.212
			for sx in [-1.0, 1.0]:
				ci.draw_rect(Rect2(map.call(Vector2(sx * off - 0.03, y0 + 0.06)), Vector2(0.06, 0.12) * s), face, true)
			ci.draw_circle(map.call(Vector2(0.0, 0.32)), 0.065 * s, ink.call("white"), true, -1.0, true)
			if big:
				_ellipse(ci, map.call(Vector2(0.0, y0 + 0.02)), Vector2(0.18, 0.14) * s, face.lerp(Color.BLACK, 0.38))
				ci.draw_circle(map.call(Vector2(0.0, 0.32)), 0.035 * s, ink.call("gold"), true, -1.0, true)
			else:
				_ellipse(ci, map.call(Vector2(0.0, y0)), Vector2(0.17, 0.085) * s, ink.call("dark"))
				var eye := face.lerp(Color.WHITE, 0.3)
				for sx in [-1.0, 1.0]:
					ci.draw_circle(map.call(Vector2(sx * 0.07, y0)), 0.04 * s, eye, true, -1.0, true)
				ci.draw_circle(map.call(Vector2(0.0, 0.32)), 0.03 * s, eye, true, -1.0, true)
				ci.draw_line(map.call(Vector2(0.0, y0 + 0.2)), map.call(Vector2(0.0, y0 + 0.26)), ink.call("white"), line, true)
				ci.draw_circle(map.call(Vector2(0.0, y0 + 0.27)), 0.035 * s, eye, true, -1.0, true)
		"wizard":
			var star := Color("#ff8a3d" if c == 2 else "#ffd84a")
			ci.draw_colored_polygon(_pts(map, [[-0.2, 0.86], [-0.08, 1.05], [0.12, 1.15], [0.07, 1.03], [0.2, 0.86]]), face)
			ci.draw_polyline(_pts(map, [[-0.2, 0.86], [-0.08, 1.05], [0.12, 1.15], [0.07, 1.03], [0.2, 0.86]]), Color(deep, 0.9), line, true)
			_ellipse(ci, map.call(Vector2(0.0, 0.85)), Vector2(0.31, 0.045) * s, face.lerp(Color.BLACK, 0.12))
			ci.draw_line(map.call(Vector2(-0.14, 0.63)), map.call(Vector2(0.14, 0.63)), face.lerp(Color.WHITE, 0.3), maxf(1.5, s * 0.07), true)
			ci.draw_circle(map.call(Vector2(0.0, 0.3)), 0.05 * s, star, true, -1.0, true)
			ci.draw_circle(map.call(Vector2(0.0, 0.95)), 0.04 * s, star, true, -1.0, true)
		"dragon":
			var y0 := PawnSkins.BELL_HEAD_Y
			var scale := face.lerp(Color.BLACK, 0.32)
			for y: float in [0.1, 0.22, 0.34]:
				var r := PawnSkins._r_at(PawnSkins.BELL, y)
				ci.draw_polyline(_pts(map, [[-r * 0.9, y], [-r * 0.45, y + 0.05], [0.0, y], [r * 0.45, y + 0.05], [r * 0.9, y]]), scale, line, true)
			for sx in [-1.0, 1.0]:
				ci.draw_colored_polygon(_pts(map, [[sx * 0.08, y0 + 0.14], [sx * 0.2, y0 + 0.36], [sx * 0.18, y0 + 0.13]]), ink.call("gold"))
			ci.draw_circle(map.call(Vector2(0.0, 0.36)), 0.04 * s, ink.call("gold"), true, -1.0, true)

## A filled piece of a disc, in board units (angles anticlockwise from +x, y up).
static func _arc(map: Callable, at: Vector2, r: float, a0: float, a1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 15:
		var a := lerpf(a0, a1, k / 14.0)
		out.append(map.call(at + Vector2(cos(a), sin(a)) * r))
	return out

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
