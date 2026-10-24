class_name BrandLogo
extends Control
## The game logo "LUDO ZING MYMENSINGH" (index.html: <symbol id="brandLogo" viewBox="0 0 320 266">).
## The shapes come from assets/ui/brand_logo_art.svg (Godot's SVG importer drops <text>); the lettering is drawn
## here with Lilita One at the control's real pixel size, so it stays sharp. Keeps the 320:266 aspect, centred.

const VIEW := Vector2(320, 266)
const ART := preload("res://assets/ui/brand_logo_art.svg")
const BUBBLES := [                     # centre, ring colour, letter colour
	[Vector2(85, 74), "L", Color("#d32f2f")], [Vector2(135, 70), "U", Color("#1f8a52")],
	[Vector2(185, 70), "D", Color("#e08a00")], [Vector2(235, 74), "O", Color("#2a63bf")],
]
const RIBBON := [Vector2(58, 172), Vector2(262, 172), Vector2(256, 187), Vector2(262, 202), Vector2(58, 202), Vector2(64, 187)]
const MARK := Color(1, 0, 1)           # vertex colour the gold shader paints over

const GOLD_SHADER := """
shader_type canvas_item;
uniform float top = 0.0;
uniform float height = 1.0;
varying float gold;                    // > 0: a MARK-coloured vertex (its value keeps any modulate dimming)
varying float y;

void vertex() {
	gold = (COLOR.g < 0.02 && COLOR.r > 0.1 && abs(COLOR.r - COLOR.b) < 0.02) ? COLOR.r : 0.0;
	y = VERTEX.y;
}

void fragment() {
	if (gold > 0.0) {
		float t = clamp((y - top) / height, 0.0, 1.0);
		vec3 a = vec3(1.0, 0.965, 0.69);    // #fff6b0
		vec3 b = vec3(1.0, 0.824, 0.227);   // #ffd23a
		vec3 c = vec3(0.941, 0.549, 0.0);   // #f08c00
		COLOR.rgb = t < 0.45 ? mix(a, b, t / 0.45) : mix(b, c, (t - 0.45) / 0.55);
		COLOR.rgb *= gold;
	}
}
"""

## Gentle float, like the web's .brand-logo animation (3.2 s, 6 px).
var bob := false:
	set(v):
		bob = v
		set_process(v and is_visible_in_tree())
		queue_redraw()
		if _zing:
			_zing.queue_redraw()

var _t := 0.0
var _zing: Control                     # draws ZING's face and everything above it, through the gold shader

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(160, 133)

func _ready() -> void:
	_zing = Control.new()
	_zing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = GOLD_SHADER
	_zing.material = m
	_zing.draw.connect(_draw_top)
	add_child(_zing)
	resized.connect(_zing.queue_redraw)
	set_process(bob and is_visible_in_tree())

## The float stops while the logo is hidden (the home screen under a game) and resumes when it shows (PF-03).
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree():
		set_process(bob and is_visible_in_tree())

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	_zing.queue_redraw()

func _scale() -> float:
	return minf(size.x / VIEW.x, size.y / VIEW.y)

func _origin() -> Vector2:
	var s := _scale()
	var o := (size - VIEW * s) / 2.0
	if bob:
		o.y -= (1.0 - cos(_t * TAU / 3.2)) / 2.0 * 6.4 * s
	return o

func _p(o: Vector2, s: float, x: float, y: float) -> Vector2:
	return o + Vector2(x, y) * s

## Art, the LUDO bubble letters and ZING's dark extrusion (everything under ZING's face).
func _draw() -> void:
	var s := _scale()
	var o := _origin()
	draw_texture_rect(ART, Rect2(o, VIEW * s), false)
	for b in BUBBLES:
		var c: Vector2 = b[0]
		_text(self, b[1], _p(o, s, c.x, c.y + 12), 34 * s, b[2])
	_text(self, "ZING", _p(o, s, 160, 170), 80 * s, Color("#7a3a00"), 2 * s, 14 * s, Color("#7a3a00"))

## ZING's outlined gold face and highlight, then the ribbon over it and MYMENSINGH (drawn by the shader child).
func _draw_top() -> void:
	var s := _scale()
	var o := _origin()
	var f := UIKit.font_display()
	var base := _p(o, s, 160, 163)
	var fs := int(round(80 * s))
	var m := _zing.material as ShaderMaterial
	var asc := f.get_ascent(fs)
	m.set_shader_parameter("top", base.y - asc * 0.78)
	m.set_shader_parameter("height", asc * 0.78 + f.get_descent(fs) * 0.2)
	_text(_zing, "ZING", base, 80 * s, MARK, 2 * s, 7 * s, Color("#5a2a00"))
	_text(_zing, "ZING", base, 80 * s, Color(1, 1, 1, 0.55), 2 * s, 1.5 * s, Color(1, 1, 1, 0.55), true)
	# ribbon (the art has it too, but it must cover ZING's extrusion as in the SVG)
	var tail := Color("#9c0f14")
	_poly(o, s, [Vector2(48, 176), Vector2(32, 189), Vector2(48, 202), Vector2(64, 202), Vector2(64, 176)], tail)
	_poly(o, s, [Vector2(272, 176), Vector2(288, 189), Vector2(272, 202), Vector2(256, 202), Vector2(256, 176)], tail)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for q: Vector2 in RIBBON:
		pts.append(_p(o, s, q.x, q.y))
		cols.append(Color("#ff5a5a").lerp(Color("#c3141b"), (q.y - 172.0) / 30.0))
	_zing.draw_polygon(pts, cols)
	pts.append(pts[0])
	_zing.draw_polyline(pts, Color.WHITE, 2.5 * s, true)
	_text(_zing, "MYMENSINGH", _p(o, s, 160, 195), 20 * s, Color.WHITE, 3 * s, 3 * s, Color("#7a0f12"))

func _poly(o: Vector2, s: float, src: Array, col: Color) -> void:
	var pts := PackedVector2Array()
	for q: Vector2 in src:
		pts.append(_p(o, s, q.x, q.y))
	_zing.draw_colored_polygon(pts, col)

## Lilita One with extra space after each glyph (SVG letter-spacing), cached per whole-pixel spacing.
static var _spaced := {}

static func _font(spacing: int) -> Font:
	if spacing <= 0:
		return UIKit.font_display()
	if not _spaced.has(spacing):
		var fv := FontVariation.new()
		fv.base_font = UIKit.font_display()
		fv.spacing_glyph = spacing
		_spaced[spacing] = fv
	return _spaced[spacing]

## Centred text at a baseline with letter spacing and an optional stroke under the fill
## (paint-order: stroke; `outline_only` draws just the stroke, like a fill="none" layer).
static func _text(ci: CanvasItem, text: String, base: Vector2, size: float, fill: Color,
		spacing := 0.0, stroke := 0.0, stroke_col := Color.BLACK, outline_only := false) -> void:
	var fs := maxi(int(round(size)), 1)
	var sp := int(round(spacing))
	var f := _font(sp)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x - sp   # no trailing space
	var at := Vector2(base.x - w / 2.0, base.y)
	if stroke > 0.0:
		ci.draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(int(round(stroke)), 1), stroke_col)
	if not outline_only:
		ci.draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fill)
