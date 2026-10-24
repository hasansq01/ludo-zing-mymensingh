class_name Splash
extends Control
## The studio splash (index.html #splash): deep plum night, the Flipfold brandmark | rule | Flipfold Studio logo
## centred, and a real-progress bar near the bottom. Sizes come from a unit u (the icon's side) like the web --u:
## u = min(90, 14% of the width, 17% of the height); the logo is .88u tall, the rule .5u, the gaps .5u.
##
##   var splash := Splash.new(); add_child(splash)
##   splash.set_progress(0.4) ... await splash.finish()

## Emitted when the splash starts fading out (show the next screen under it now).
signal fading

const MARK := preload("res://assets/ui/brandmark.svg")    # the Flipfold brandmark, exactly as supplied (index.html .studio-mark)
const LOGO := preload("res://assets/ui/flipfold_logo.svg")
const LOGO_ASPECT := 2071.0 / 449.0

const BAR_SHADER := """
shader_type canvas_item;
uniform vec2 bar_size = vec2(240.0, 10.0);
uniform float margin = 24.0;
uniform float progress = 0.0;
uniform float sheen = 0.0;      // 0..1 phase of the slow sheen inside the fill
uniform float sweep = -1.0;     // 0..1 while the completion sweep runs, < 0 otherwise
uniform float done_glow = 0.0;  // 0..1 lavender ring + outer glow once complete

float box(vec2 p, vec2 lo, vec2 hi, float r) {
	vec2 c = (lo + hi) * 0.5, b = (hi - lo) * 0.5;
	vec2 q = abs(p - c) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
vec4 over(vec4 d, vec4 s) {
	float a = s.a + d.a * (1.0 - s.a);
	if (a <= 0.0) return vec4(0.0);
	return vec4((s.rgb * s.a + d.rgb * d.a * (1.0 - s.a)) / a, a);
}
float band(float x, float lo, float w) {   // 0 -> 1 -> 0 across [lo, lo + w]
	float t = clamp((x - lo) / w, 0.0, 1.0);
	return 1.0 - abs(t * 2.0 - 1.0);
}
void fragment() {
	vec2 p = UV * (bar_size + 2.0 * margin) - margin;
	float W = bar_size.x, H = bar_size.y;
	float d = box(p, vec2(0.0), bar_size, H * 0.5);
	float inside = clamp(0.5 - d, 0.0, 1.0);
	vec4 col = vec4(0.0);
	// outer glow + 1px ring (brighter once complete)
	float glow = 1.0 - smoothstep(0.0, 18.0, d);
	col = over(col, vec4(0.663, 0.545, 1.0, 0.45 * done_glow * glow * glow * step(0.0, d)));
	float ring = clamp(1.0 - abs(d - 0.5) * 1.4, 0.0, 1.0) * step(-0.2, d);
	col = over(col, vec4(mix(vec3(0.769, 0.667, 1.0), vec3(0.839, 0.769, 1.0), done_glow), mix(0.16, 0.35, done_glow) * ring));
	// track with a soft inner shadow from the top
	vec4 track = vec4(0.071, 0.039, 0.110, 0.75 * inside);
	float ds = box(p - vec2(0.0, 1.0), vec2(0.0), bar_size, H * 0.5);
	float inner = smoothstep(-3.0, 0.5, ds);
	col = over(col, track);
	col = over(col, vec4(0.0, 0.0, 0.0, 0.55 * inner * inside));
	// fill: lavender gradient, soft glow, glossy top half, moving sheen
	float fw = max(0.0, (W - 4.0) * progress);
	if (fw > 0.0) {
		float r = (H - 4.0) * 0.5;
		float df = box(p, vec2(2.0), vec2(2.0 + fw, H - 2.0), min(r, fw * 0.5));
		float fill = clamp(0.5 - df, 0.0, 1.0);
		col = over(col, vec4(0.663, 0.545, 1.0, 0.35 * inside * (1.0 - smoothstep(0.0, 3.5, df)) * step(0.0, df)));
		float t = clamp((p.x - 2.0) / fw, 0.0, 1.0);
		vec3 g = t < 0.6 ? mix(vec3(0.482, 0.361, 0.769), vec3(0.663, 0.545, 1.0), t / 0.6)
			: mix(vec3(0.663, 0.545, 1.0), vec3(0.851, 0.8, 1.0), (t - 0.6) / 0.4);
		col = over(col, vec4(g, fill));
		float hi = clamp((p.y - 2.0) / (H * 0.5 - 2.0), 0.0, 1.0);
		col = over(col, vec4(1.0, 1.0, 1.0, 0.4 * (1.0 - hi) * step(p.y, H * 0.5) * fill));
		float e = sheen < 0.5 ? 2.0 * sheen * sheen : 1.0 - pow(-2.0 * sheen + 2.0, 2.0) * 0.5;
		float sl = 2.0 + fw * (-0.4 + 1.5 * e);
		col = over(col, vec4(1.0, 1.0, 1.0, 0.35 * band(p.x, sl, fw * 0.4) * fill));
	}
	// completion sweep, clipped to the track
	if (sweep >= 0.0) {
		float e = 1.0 - pow(1.0 - sweep, 3.0);
		float sl = W * (-0.35 + 1.35 * e);
		col = over(col, vec4(1.0, 1.0, 1.0, 0.85 * mix(1.0, 0.2, e) * band(p.x, sl, W * 0.35) * inside));
	}
	COLOR = col;
}
"""

const GLOW_PAD := 160.0   # source pixels of room around the artwork for its glow
const BAR_MARGIN := 24.0
const BAR_H := 10.0

var _real := 0.0
var _shown := 0.0
var _finished := false
var _sheen_t := 0.0

var _bg: TextureRect
var _studio: Control
var _glow: Control
var _mark: TextureRect
var _rule: Panel
var _logo: TextureRect
var _bar: ColorRect
var _bar_mat: ShaderMaterial
var _text: Label
var _glow_amt := 0.0
var _mark_glow: Texture2D
var _logo_glow: Texture2D


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_bg = TextureRect.new()
	_bg.texture = _background()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_studio = Control.new()
	_studio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_studio.modulate.a = 0.0
	add_child(_studio)
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.draw.connect(_draw_glow)
	_studio.add_child(_glow)
	_mark = _image(MARK)
	_logo = _image(LOGO)
	_rule = Panel.new()
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(1, 1, 1, 0.85)
	rs.set_corner_radius_all(1)
	_rule.add_theme_stylebox_override("panel", rs)
	_studio.add_child(_mark)
	_studio.add_child(_rule)
	_studio.add_child(_logo)

	_bar = ColorRect.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BAR_SHADER
	_bar_mat.shader = sh
	_bar_mat.set_shader_parameter("margin", BAR_MARGIN)
	_bar.material = _bar_mat
	add_child(_bar)

	_text = Label.new()
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.add_theme_font_override("font", UIKit.font_caps(800, 2))
	_text.add_theme_font_size_override("font_size", 11)
	_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	_text.text = "LOADING"

	resized.connect(_layout)


func _ready() -> void:
	_layout()
	_studio.scale = Vector2(0.97, 0.97)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_studio, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_studio, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


## Real loading progress, 0..1. The bar eases toward it and never goes backwards; it shows 99% at most until finish().
func set_progress(f: float) -> void:
	if not _finished:
		_real = maxf(_real, clampf(f, 0.0, 0.999))


## Completes the bar (100%), plays the glow sweep across the bar and the logo highlight (~0.45 s), then fades the
## whole splash out (~0.4 s) and frees it. Await it; `fading` fires as the fade starts.
func finish() -> void:
	if _finished:
		return
	_finished = true
	_real = 1.0
	if _mark_glow == null:
		_mark_glow = _blurred(MARK)
		_logo_glow = _blurred(LOGO)
	while _shown < 1.0 and is_inside_tree():
		await get_tree().process_frame
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float): _bar_mat.set_shader_parameter("sweep", v), 0.0, 1.0, 0.45)
	tw.tween_method(func(v: float): _bar_mat.set_shader_parameter("done_glow", v), 0.0, 1.0, 0.3)
	tw.tween_method(_set_glow, 0.0, 1.0, 0.45)
	await tw.finished
	_bar_mat.set_shader_parameter("sweep", -1.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fading.emit()
	var out := create_tween()
	out.tween_property(self, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await out.finished
	queue_free()


func _process(delta: float) -> void:
	_sheen_t = fmod(_sheen_t + delta / 1.8, 1.0)
	_bar_mat.set_shader_parameter("sheen", _sheen_t)
	if _shown >= 1.0:
		return
	_shown += (_real - _shown) * (1.0 - pow(0.88, delta * 60.0))
	if _real - _shown < 0.004:
		_shown = _real
	_bar_mat.set_shader_parameter("progress", _shown)


func _set_glow(v: float) -> void:
	# studioGlow: peaks half way (drop-shadow + brightness 1.12), back to normal at the end
	_glow_amt = sin(v * PI)
	var b := 1.0 + 0.12 * _glow_amt
	_mark.self_modulate = Color(b, b, b)
	_logo.self_modulate = Color(b, b, b)
	_glow.queue_redraw()


func _draw_glow() -> void:
	if _glow_amt <= 0.01:
		return
	# drop-shadow(0 0 14px rgba(214,196,255,.55)): pre-blurred copies of the artwork, drawn under it
	if _mark_glow == null:
		return
	var c := Color(0.839, 0.769, 1.0, 0.95 * _glow_amt)
	for pair in [[_mark, _mark_glow, float(MARK.get_width())], [_logo, _logo_glow, float(LOGO.get_width())]]:
		var r: TextureRect = pair[0]
		var pad: float = GLOW_PAD * r.size.x / maxf(1.0, float(pair[2]))
		_glow.draw_texture_rect(pair[1], Rect2(r.position - Vector2(pad, pad), r.size + Vector2(pad, pad) * 2.0), false, c)


func _layout() -> void:
	var s := size
	if s.x <= 0.0:
		return
	var inner := s - Vector2(32, 32)
	var u := minf(90.0, minf(inner.x * 0.14, inner.y * 0.17))
	var logo_h := u * 0.88
	var logo_w := logo_h * LOGO_ASPECT
	var gap := u * 0.5
	var row_w := u + gap + 2.0 + gap + logo_w
	_studio.size = Vector2(row_w, u)
	_studio.position = (s - _studio.size) * 0.5
	_studio.pivot_offset = _studio.size * 0.5
	_glow.size = _studio.size
	_mark.position = Vector2.ZERO
	_mark.size = Vector2(u, u)
	_rule.position = Vector2(u + gap, u * 0.25)
	_rule.size = Vector2(2, u * 0.5)
	_logo.position = Vector2(u + gap + 2.0 + gap, (u - logo_h) * 0.5)
	_logo.size = Vector2(logo_w, logo_h)

	var bottom := 56.0 + _safe_bottom()
	var w := minf(240.0, s.x * 0.62)
	_bar_mat.set_shader_parameter("bar_size", Vector2(w, BAR_H))
	var text_h := _text.get_minimum_size().y
	var top := s.y - bottom - text_h - 11.0 - BAR_H
	_bar.position = Vector2((s.x - w) * 0.5 - BAR_MARGIN, top - BAR_MARGIN)
	_bar.size = Vector2(w + BAR_MARGIN * 2.0, BAR_H + BAR_MARGIN * 2.0)
	_text.position = Vector2((s.x - w) * 0.5 - 20.0, top + BAR_H + 11.0 - 2.0)
	_text.size = Vector2(w + 40.0, text_h)



## Bottom safe-area inset (gesture bar / notch) in UI units; 0 on desktop.
func _safe_bottom() -> float:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return 0.0
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.y <= 0 or safe.size.y <= 0:
		return 0.0
	return maxf(0.0, float(win.y - safe.end.y)) * size.y / float(win.y)



func _image(tex: Texture2D) -> TextureRect:
	var t := TextureRect.new()
	t.texture = _mipmapped(tex)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## The SVGs are imported at their native size (511 / 2071 px wide) and shown far smaller: mipmaps keep them smooth.
static func _mipmapped(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A soft, blurred copy of an artwork's shape (padded by GLOW_PAD source pixels on every side), white.
static func _blurred(tex: Texture2D) -> Texture2D:
	var src := tex.get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var p := int(GLOW_PAD)
	var img := Image.create(src.get_width() + p * 2, src.get_height() + p * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	img.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i(p, p))
	for i in 5:   # repeated halving: a cheap wide box blur
		img.resize(maxi(1, img.get_width() / 2), maxi(1, img.get_height() / 2), Image.INTERPOLATE_BILINEAR)
	var w := img.get_width()
	var h := img.get_height()
	for pass_i in 2:
		var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var a := 0.0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						a += img.get_pixel(clampi(x + dx, 0, w - 1), clampi(y + dy, 0, h - 1)).a
				out.set_pixel(x, y, Color(1, 1, 1, a / 9.0))
		img = out
	return ImageTexture.create_from_image(img)


## radial-gradient(ellipse at 50% 46%, #2c1f3f 0%, #170f22 62%, #0f0a17 100%), farthest-corner.
static func _background() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([Color("#2c1f3f"), Color("#170f22"), Color("#0f0a17")])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.46)
	t.fill_to = Vector2(0.5 + 0.7637, 0.46)
	t.width = 256
	t.height = 512
	return t

