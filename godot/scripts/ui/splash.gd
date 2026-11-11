class_name Splash
extends Control
## The loading screen, in two parts:
##   1. The studio intro (index.html #splash), unchanged (the engine's boot image, assets/ui/boot_splash.png, is this
##      same row on the same plum, so it is on screen from the moment the app opens): deep plum night, the Flipfold brandmark | rule | Flipfold
##      Studio logo centred (sizes from a unit u, the icon's side: u = min(90, 14% of the width, 17% of the height);
##      the logo is .88u tall, the rule .5u, the gaps .5u).
##   2. After STUDIO_HOLD, a cross-fade to the game's own loading screen in the game look: the warm café ground with
##      slowly turning gold rays, the Ludo Zing logo (as supplied) bobbing gently, a chunky gold progress bar with the
##      percentage on it, a game tip under it (they turn every TIP_EVERY s) and the studio's name small at the bottom.
## The bar shows real progress the whole time (it may already be part full when it appears).
##
##   var splash := Splash.new(); add_child(splash)
##   splash.set_progress(0.4) ... await splash.finish()

## Emitted when the splash starts fading out (show the next screen under it now).
signal fading

const MARK := preload("res://assets/ui/brandmark.svg")    # the Flipfold brandmark, exactly as supplied (index.html .studio-mark)
const LOGO := preload("res://assets/ui/flipfold_logo.svg")
const LOGO_ASPECT := 2071.0 / 449.0
const GAME_LOGO := preload("res://assets/ui/ludo_zing_logo.png")   # as supplied

const STUDIO_HOLD := 1.5          ## s from the start before the game screen takes over
const SWAP := 0.45                ## s of cross-fade
const TIP_EVERY := 3.6            ## s per tip
const BAR_H := 30.0
const BAR_INSET := 5.0

## The game rules' own sentences (How to play), so the Bangla is the same as there.
const TIPS := [
	"Roll a [b]6[/b] to bring a pawn out of your base.",  # l10n
	"[b]Star squares[/b] and [b]coloured start squares[/b] are safe: nobody can be captured there.",  # l10n
	"You need the [b]exact number[/b] to reach the centre. A bigger roll can’t move that pawn.",  # l10n
	"Land on the foot of a ladder to climb it. Land on a snake’s head to slide down to its tail.",  # l10n
]

const GROUND_SHADER := """shader_type canvas_item;
uniform vec2 size = vec2(400.0, 800.0);
uniform vec2 center = vec2(0.5, 0.34);
uniform float turn = 0.0;
void fragment() {
	vec2 p = UV * size;
	vec2 o = center * size;
	float d = length(p - o) / (max(size.x, size.y) * 0.72);
	vec3 a = vec3(0.541, 0.294, 0.149);
	vec3 b = vec3(0.353, 0.173, 0.086);
	vec3 k = vec3(0.169, 0.078, 0.039);
	vec3 col = d < 0.45 ? mix(a, b, d / 0.45) : mix(b, k, clamp((d - 0.45) / 0.55, 0.0, 1.0));
	float ang = (atan(p.y - o.y, p.x - o.x) + turn) / 6.2831853 * 18.0;
	float f = fract(ang);
	float aa = clamp(fwidth(ang), 0.0, 0.2) * 0.75;
	float ray = smoothstep(-aa, aa, f) * (1.0 - smoothstep(0.42 - aa, 0.42 + aa, f));
	col = mix(col, vec3(1.0, 0.84, 0.37), ray * 0.11 * (1.0 - smoothstep(0.05, 0.85, d)));
	COLOR = vec4(col, 1.0);
}"""

var _real := 0.0
var _shown := 0.0
var _finished := false
var _game_on := false               # the game screen has taken over
var _t := 0.0
var _tip_i := 0
var _tip_t := 0.0

var _bg: TextureRect
var _studio: Control
var _mark: TextureRect
var _rule: Panel
var _logo: TextureRect

var _game: Control
var _ground: ColorRect
var _ground_mat: ShaderMaterial
var _game_logo: TextureRect
var _track: GamePanel
var _fill: GamePanel
var _pct: Label
var _tip: RichTextLabel
var _credit: TextureRect


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
	_build_game()
	resized.connect(_layout)


func _build_game() -> void:
	_game = Control.new()
	_game.name = "Game"
	_game.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game.modulate.a = 0.0
	_game.visible = false
	add_child(_game)
	_ground = ColorRect.new()
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ground_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	_ground_mat.shader = sh
	_ground.material = _ground_mat
	_game.add_child(_ground)
	_game_logo = _image(GAME_LOGO)
	_game_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_game.add_child(_game_logo)
	# the bar: a dark track with a warm rim, a gold fill with a lip, the percentage outlined on top
	_track = GamePanel.vertical(Palette.GL_CHIP_BG, Palette.GL_INK)
	_track.radius = BAR_H / 2.0
	_track.border = 3.0
	_track.border_color = Palette.GL_CHIP_RIM
	_game.add_child(_track)
	_fill = GamePanel.vertical(Palette.GL_BTN_GOLD_HI, Palette.GL_BTN_GOLD_LO)
	_fill.radius = (BAR_H - BAR_INSET * 2.0) / 2.0
	_fill.lip = 3.0
	_fill.lip_color = Palette.GL_GOLD_LIP
	_game.add_child(_fill)
	_pct = GameUI.outlined("0%", 17, Color.WHITE, 3, HORIZONTAL_ALIGNMENT_CENTER)
	_pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_game.add_child(_pct)
	_tip = RichTextLabel.new()
	_tip.bbcode_enabled = true
	_tip.fit_content = true
	_tip.scroll_active = false
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_theme_font_override("normal_font", UIKit.font_body(800))
	_tip.add_theme_font_override("bold_font", UIKit.font_body(900))
	_tip.add_theme_font_size_override("normal_font_size", 15)
	_tip.add_theme_font_size_override("bold_font_size", 15)
	_tip.add_theme_color_override("default_color", Palette.GL_CREAM_TEXT)
	_game.add_child(_tip)
	_credit = _image(LOGO)
	_credit.modulate.a = 0.5
	_game.add_child(_credit)
	_tip_i = randi() % TIPS.size()
	_show_tip()


func _ready() -> void:
	_layout()
	if bool(ProjectSettings.get_setting("application/boot_splash/show_image", false)):
		_studio.modulate.a = 1.0                 # the engine's boot image (assets/ui/boot_splash.png) already shows this row
	else:
		_studio.scale = Vector2(0.97, 0.97)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_studio, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_studio, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(STUDIO_HOLD).timeout.connect(_swap)


## The studio intro gives way to the game's loading screen.
func _swap() -> void:
	if _game_on or not is_inside_tree():
		return
	_game_on = true
	_game.visible = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_game, "modulate:a", 1.0, SWAP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_studio, "modulate:a", 0.0, SWAP * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_game_logo.scale = Vector2(0.9, 0.9)
	tw.tween_property(_game_logo, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Real loading progress, 0..1. The bar eases toward it and never goes backwards; it shows 99% at most until finish().
func set_progress(f: float) -> void:
	if not _finished:
		_real = maxf(_real, clampf(f, 0.0, 0.999))

## Completes the bar (100%) once the game screen is up, gives it a little pop, then fades the whole splash out
## (~0.4 s) and frees it. Await it; `fading` fires as the fade starts.
func finish() -> void:
	if _finished:
		return
	_finished = true
	_real = 1.0
	while (_shown < 1.0 or not _game_on or _game.modulate.a < 1.0) and is_inside_tree():
		await get_tree().process_frame
	if not is_inside_tree():
		return
	_fill.pivot_offset = _fill.size / 2.0
	var pop := create_tween()
	pop.tween_property(_fill, "scale", Vector2(1.0, 1.25), 0.1).set_trans(Tween.TRANS_SINE)
	pop.tween_property(_fill, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await pop.finished
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fading.emit()
	var out := create_tween()
	out.tween_property(self, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await out.finished
	queue_free()


func _process(delta: float) -> void:
	_t += delta
	if _shown < 1.0:
		_shown += (_real - _shown) * (1.0 - pow(0.9, delta * 60.0))
		if _real - _shown < 0.004:
			_shown = _real
	if not _game.visible:
		return
	_ground_mat.set_shader_parameter("turn", _t * 0.12)
	if _t > STUDIO_HOLD + 0.65:                 # after the logo's pop in: a gentle breathing
		var b := 1.0 + 0.018 * sin(_t * 2.2)
		_game_logo.scale = Vector2(b, b)
	_place_fill()
	_pct.text = "%d%%" % int(round(_shown * 100.0))
	_tip_t += delta
	if _tip_t >= TIP_EVERY:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		var tw := create_tween()
		tw.tween_property(_tip, "modulate:a", 0.0, 0.25)
		tw.tween_callback(_show_tip)
		tw.tween_property(_tip, "modulate:a", 1.0, 0.3)


func _show_tip() -> void:
	_tip.text = "[center]%s[/center]" % L10n.t(TIPS[_tip_i])


func _place_fill() -> void:
	var inner := _track.size.x - BAR_INSET * 2.0
	var h := BAR_H - BAR_INSET * 2.0
	_fill.position = _track.position + Vector2(BAR_INSET, BAR_INSET)
	_fill.size = Vector2(maxf(h, inner * _shown), h)
	_fill.visible = _shown > 0.005


func _layout() -> void:
	var s := size
	if s.x <= 0.0:
		return
	# the studio row
	var inner := s - Vector2(32, 32)
	var u := minf(90.0, minf(inner.x * 0.14, inner.y * 0.17))
	var logo_h := u * 0.88
	var logo_w := logo_h * LOGO_ASPECT
	var gap := u * 0.5
	var row_w := u + gap + 2.0 + gap + logo_w
	_studio.size = Vector2(row_w, u)
	_studio.position = (s - _studio.size) * 0.5
	_studio.pivot_offset = _studio.size * 0.5
	_mark.position = Vector2.ZERO
	_mark.size = Vector2(u, u)
	_rule.position = Vector2(u + gap, u * 0.25)
	_rule.size = Vector2(2, u * 0.5)
	_logo.position = Vector2(u + gap + 2.0 + gap, (u - logo_h) * 0.5)
	_logo.size = Vector2(logo_w, logo_h)
	# the game screen
	_ground_mat.set_shader_parameter("size", s)
	var lw := minf(s.x * 0.8, 440.0)
	var lh := lw * float(GAME_LOGO.get_height()) / float(GAME_LOGO.get_width())
	_game_logo.size = Vector2(lw, lh)
	_game_logo.position = Vector2((s.x - lw) * 0.5, s.y * 0.34 - lh * 0.5)
	_game_logo.pivot_offset = _game_logo.size * 0.5
	var safe := _safe_bottom()
	var credit_h := 14.0
	_credit.size = Vector2(credit_h * LOGO_ASPECT, credit_h)
	_credit.position = Vector2((s.x - _credit.size.x) * 0.5, s.y - safe - 28.0 - credit_h)
	var bw := minf(s.x - 64.0, 340.0)
	var bar_y := s.y * 0.7
	_track.position = Vector2((s.x - bw) * 0.5, bar_y)
	_track.size = Vector2(bw, BAR_H)
	_pct.position = _track.position
	_pct.size = _track.size
	_tip.position = Vector2((s.x - bw) * 0.5 - 8.0, bar_y + BAR_H + 18.0)
	_tip.size = Vector2(bw + 16.0, 0.0)
	_tip.custom_minimum_size.x = bw + 16.0
	_place_fill()


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

## The artwork is imported at its native size and shown far smaller: mipmaps keep it smooth.
static func _mipmapped(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
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
