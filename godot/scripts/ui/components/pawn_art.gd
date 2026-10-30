class_name PawnArt
## The board's pawn (LudoBoard.PAWN_PROFILE lathe + the 0.19 head sphere at y 0.74: the same pawn Ludo and Snakes &
## Ladders use) drawn flat into any CanvasItem in a player colour, for the setup sheets' seat rows and colour choices.
## Pure 2D draw calls (two polygons, a circle, two highlights): no texture, no SubViewport, no GPU work beyond the
## draw, nothing to cache. Use PawnArt.draw(self, rect, colour_index) from a _draw().

const HEAD_Y := 0.74
const HEAD_R := 0.19
const TOP := HEAD_Y + HEAD_R          ## the pawn's height in board units
const HALF_W := 0.38                  ## its widest half-width (the base)

static var _poly := PackedVector2Array()    # the body outline, y up, built once

static func _outline() -> PackedVector2Array:
	if _poly.is_empty():
		var right := []
		for p in LudoBoard.PAWN_PROFILE:
			right.append(Vector2(p[0], p[1]))
		for p in right:
			_poly.append(p)
		for k in range(right.size() - 2, 0, -1):
			_poly.append(Vector2(-right[k].x, right[k].y))
	return _poly

## Draw the pawn of player colour c, standing on the bottom edge of `rect` and as tall as it allows (aspect kept).
static func draw(ci: CanvasItem, rect: Rect2, c: int, rim := Color.TRANSPARENT) -> void:
	c = clampi(c, 0, 3)
	var s := minf(rect.size.y / TOP, rect.size.x / (HALF_W * 2.0))
	var o := Vector2(rect.position.x + rect.size.x / 2.0, rect.end.y)
	var face: Color = Palette.PLAYER[c]
	var deep: Color = Palette.PLAYER_DARK[c]
	var map := func(p: Vector2) -> Vector2: return o + Vector2(p.x, -p.y) * s
	# contact shadow
	var sh := PackedVector2Array()
	for k in 20:
		var a := TAU * float(k) / 20.0
		sh.append(o + Vector2(cos(a) * HALF_W * 0.95, -0.02 + sin(a) * 0.07) * s + Vector2(0, 0.01 * s))
	ci.draw_colored_polygon(sh, Color(deep, 0.35))
	var body := PackedVector2Array()
	for p in _outline():
		body.append(map.call(p))
	ci.draw_colored_polygon(body, face)
	body.append(body[0])
	if rim.a > 0.0:                      # a pawn on its own colour needs a rim to stand out
		ci.draw_polyline(body, rim, maxf(1.5, s * 0.07), true)
		ci.draw_circle(map.call(Vector2(0.0, HEAD_Y)), HEAD_R * s + maxf(0.75, s * 0.035), rim, false, maxf(1.5, s * 0.07), true)
	ci.draw_polyline(body, Color(deep, 0.9), maxf(1.0, s * 0.03), true)
	# the right half in shade (the profile itself closes the polygon on the axis)
	var side := PackedVector2Array()
	for p in LudoBoard.PAWN_PROFILE:
		side.append(map.call(Vector2(p[0] * 0.999, p[1])))
	ci.draw_colored_polygon(side, Color(deep, 0.38))
	var hc: Vector2 = map.call(Vector2(0.0, HEAD_Y))
	ci.draw_circle(hc, HEAD_R * s, face, true, -1.0, true)
	ci.draw_circle(hc + Vector2(HEAD_R * s * 0.3, HEAD_R * s * 0.15), HEAD_R * s * 0.7, Color(deep, 0.30), true, -1.0, true)
	ci.draw_circle(hc + Vector2(-0.07, -0.07) * s, 0.055 * s, Color(1, 1, 1, 0.75), true, -1.0, true)
	# a gloss streak down the lit side of the body
	var g := PackedVector2Array([map.call(Vector2(-0.2, 0.17)), map.call(Vector2(-0.12, 0.3)), map.call(Vector2(-0.08, 0.45)), map.call(Vector2(-0.14, 0.44)), map.call(Vector2(-0.17, 0.3))])
	ci.draw_colored_polygon(g, Color(1, 1, 1, 0.4))
