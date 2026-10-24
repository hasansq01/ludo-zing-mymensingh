class_name CoachMarks
extends Control
## The guided first match's coach marks (Tutorial), over the Ludo HUD:
##   step(): a soft dim scrim with a cut-out over the target (the dice, a glowing pawn) and an optional second
##           cut-out for something to look at (a star square, a rival pawn), a pulsing honey ring, the pointer hand
##           and a one-line caption bubble with a tail. Taps outside the cut-out are blocked (a nudge says so);
##           taps inside go through to the dice or the board as usual.
##   note(): a caption without the scrim (explanations while the computer plays). hold = true: it stays until
##           tapped (anywhere but the top bar; "Tap to continue" under it) or `sec` runs out, and holding() is true
##           meanwhile (the tutorial pauses the game on it). Otherwise input is not blocked.
##   card(): the "You’re ready!" card; returns the button picked.
## A small "Skip tutorial" text button stays in the top-left corner throughout (signal skip).
## Targets are Callables returning a Rect2 in screen (UI) pixels, read every frame, so cut-outs follow the camera
## and the gliding die. pop_host(): a layer just above the scrim (under the caption) for the board's pop texts,
## which are part of the lesson ("+1 roll" after a capture, "Home!").

signal skip
signal card_picked(what: String)

const HOLE_PAD := 10.0                   # cut-out margin around a control target
const PAWN_HOLE := 60.0                  # cut-out diameter around a pawn (the tap target: ≥ 48 px)
const MARK_HOLE := 44.0                  # cut-out diameter around a square or pawn to look at
const RING_W := 3.0
const TAIL := 10.0                       # caption tail height
const BUBBLE_W := 340.0
const GAP := 14.0                        # caption ↔ cut-out gap (plus the tail)
const DIM_A := 0.55                      # scrim opacity (of Palette.VEIL's colour)
const FADE := 0.18
const HOLD_MIN := 0.5                    # s before a tap may close a held note (not the tap that made the move)
const TAP_HINT := "Tap to continue"

const SHADER := """
shader_type canvas_item;
uniform vec2 rect_size = vec2(390.0, 844.0);
uniform vec4 hole_a = vec4(-100.0, -100.0, 0.0, 0.0);   // centre xy, half size zw
uniform float radius_a = 0.0;
uniform vec4 hole_b = vec4(-100.0, -100.0, 0.0, 0.0);
uniform float radius_b = 0.0;
uniform vec4 dim : source_color = vec4(0.0, 0.0, 0.0, 0.5);
uniform float amount = 0.0;
float sd_round(vec2 p, vec2 b, float r) {
	r = min(r, min(b.x, b.y));
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
void fragment() {
	vec2 p = UV * rect_size;
	float d = 1e5;
	if (hole_a.z > 0.0) { d = min(d, sd_round(p - hole_a.xy, hole_a.zw, radius_a)); }
	if (hole_b.z > 0.0) { d = min(d, sd_round(p - hole_b.xy, hole_b.zw, radius_b)); }
	float a = smoothstep(-1.5, 2.5, d);
	COLOR = vec4(dim.rgb, dim.a * a * amount);
}
"""

var safe_top := 0.0                      # where the skip button sits (below the top bar)
var _scrim: ColorRect
var _mat: ShaderMaterial
var _bubble: PanelContainer
var _title: Label
var _sub: Label
var _hint: Label
var _pops: Control
var _tail: Control
var _hand: TextureRect
var _skip: Button
var _card: PanelContainer
var _target := Callable()                # -> Rect2: the cut-out you tap
var _mark := Callable()                  # -> Rect2: a second cut-out to look at (not tappable)
var _near := Callable()                  # -> Rect2: what a note points at
var _block := false
var _amount := 0.0                       # scrim fade 0..1
var _fade_tw: Tween
var _t := 0.0                            # animation clock
var _nudge := 0.0                        # a blocked tap: ring flash + bubble wiggle (1 -> 0)
var _bubble_in := 0.0                    # caption entrance (0 -> 1)
var _hole := Rect2()                     # the current cut-out (local px)
var _mark_rect := Rect2()
var _hand_on := true
var _dice: Control                       # the HUD die: its own hand hint replaces ours after a while
var _note_id := 0
var _holding := false                    # a held note is up (note(..., hold = true))
var _hold_t := 0.0
var _dismissed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = ColorRect.new()
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_mat.set_shader_parameter("dim", Color(Palette.VEIL, DIM_A))
	_scrim.material = _mat
	add_child(_scrim)
	_pops = Control.new()
	_pops.name = "Pops"
	_pops.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pops)
	_build_bubble()
	_hand = UIKit.icon("ic_hand", 52)
	_hand.size = Vector2(52, 52)
	_hand.pivot_offset = Vector2(22, 8)       # the fingertip
	_hand.visible = false
	add_child(_hand)
	_skip = Button.new()
	_skip.text = "Skip tutorial"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.custom_minimum_size = Vector2(UIKit.TAP * 2.4, UIKit.TAP)
	var sb := UIKit.box(Palette.NIGHT_GLASS, UIKit.R.pill)
	UIKit.pad(sb, UIKit.SPACE.lg, UIKit.SPACE.xs)
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.bg_color = Palette.NIGHT_GLASS.darkened(0.3)
	for st in ["normal", "hover", "focus"]:
		_skip.add_theme_stylebox_override(st, sb if st != "focus" else StyleBoxEmpty.new())
	_skip.add_theme_stylebox_override("pressed", sbp)
	_skip.add_theme_stylebox_override("hover_pressed", sbp)
	_skip.add_theme_font_override("font", UIKit.font_body(800))
	_skip.add_theme_font_size_override("font_size", UIKit.FS.label)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		_skip.add_theme_color_override(st, Color.WHITE)
	_skip.pressed.connect(func(): skip.emit())
	UIKit.wire_press(_skip)
	add_child(_skip)
	resized.connect(_place_skip)
	_place_skip()

func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	var st := UIKit.surface("bubble").duplicate() as StyleBoxFlat
	st.border_color = Palette.HONEY
	UIKit.pad(st, UIKit.SPACE.lg, UIKit.SPACE.md)
	_bubble.add_theme_stylebox_override("panel", st)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UIKit.vbox(UIKit.SPACE.xxs)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = UIKit.label("", UIKit.FS.h3, Palette.INK, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub = UIKit.label("", UIKit.FS.body, Palette.SUB, UIKit.font_body(700), HORIZONTAL_ALIGNMENT_CENTER)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = UIKit.label(TAP_HINT, UIKit.FS.small, Palette.SUB, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER)
	_hint.visible = false
	col.add_child(_title)
	col.add_child(_sub)
	col.add_child(UIKit.margin(_hint, 0, UIKit.SPACE.xxs, 0, 0))
	_bubble.add_child(col)
	_bubble.visible = false
	add_child(_bubble)
	_tail = Control.new()
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tail.draw.connect(_draw_tail)
	add_child(_tail)

func _place_skip() -> void:
	if _skip == null:
		return
	_skip.size = _skip.get_combined_minimum_size()
	_skip.position = Vector2(UIKit.SCREEN_GUTTER, safe_top)

func set_safe_top(y: float) -> void:
	safe_top = y
	_place_skip()

func set_dice(d: Control) -> void:
	_dice = d

## Where the board's pop texts go during the lesson: above the scrim, under the caption.
func pop_host() -> Control:
	return _pops


# ---------- public API ----------

## A coach step: dim everything but `target` (and `mark`), point at it, say `text` (and `sub`). Taps outside the
## target are blocked until hide_step().
func step(target: Callable, text: String, sub := "", mark := Callable(), hand := true) -> void:
	_note_id += 1
	_end_hold()
	_close_card()
	_target = target
	_mark = mark
	_near = Callable()
	_hand_on = hand
	_block = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_set_text(text, sub)
	_update_rects()
	_fade_to(1.0)

## Lifts the scrim and the caption (the tap went through; the game animates).
func hide_step() -> void:
	_block = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target = Callable()
	_mark = Callable()
	_hand.visible = false
	if _near.is_null():
		_bubble.visible = false
	_fade_to(0.0)

## An explanation without the scrim, near `near` (or centred), for `sec` seconds (0: until the next step).
## hold: it also closes on a tap (after HOLD_MIN s; "Tap to continue" shows under it) and holding() is true while it
## is up. Coroutine: returns when it hides.
func note(text: String, sub := "", near := Callable(), sec := 2.6, hold := false) -> void:
	hide_step()
	_note_id += 1
	var id := _note_id
	_near = near
	_holding = hold
	_hold_t = 0.0
	_dismissed = false
	_set_text(text, sub)
	_hint.visible = hold
	if hold:
		mouse_filter = Control.MOUSE_FILTER_STOP
	_update_rects()
	if sec <= 0.0 and not hold:
		return
	var left := sec if sec > 0.0 else INF
	while id == _note_id and is_inside_tree() and not _dismissed and left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()
	if id == _note_id and is_inside_tree():
		_near = Callable()
		_bubble.visible = false
		_end_hold()

## A held note is up (the game waits for it).
func holding() -> bool:
	return _holding

## The closing card. Coroutine: returns "play" or "home".
func card(title_: String, text: String, play_text: String, home_text: String) -> String:
	hide_step()
	_note_id += 1
	_near = Callable()
	_bubble.visible = false
	_end_hold()
	_skip.visible = false
	_block = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_target = Callable()
	_hole = Rect2()
	_fade_to(1.0)
	_card = PanelContainer.new()
	var st := UIKit.surface("card").duplicate() as StyleBoxFlat
	UIKit.pad(st, UIKit.PAD.card + 4, UIKit.PAD.card)
	_card.add_theme_stylebox_override("panel", st)
	var col := UIKit.vbox(UIKit.SPACE.md)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var badge := PanelContainer.new()
	var bs := UIKit.box(Palette.HONEY, 36, UIKit.BW.rim, Palette.HONEY_RIM)
	bs.border_width_bottom = UIKit.LIP.md + 1
	bs.border_color = Palette.HONEY_RIM
	UIKit.shade(bs, "sm")
	UIKit.pad(bs, 0)
	badge.add_theme_stylebox_override("panel", bs)
	badge.custom_minimum_size = Vector2(72, 72)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var cc := CenterContainer.new()
	cc.add_child(UIKit.icon("ic_trophy", 40))
	badge.add_child(cc)
	col.add_child(badge)
	var t := UIKit.title(title_, UIKit.FS.title, Palette.INK)
	col.add_child(t)
	var p := UIKit.paragraph(text, UIKit.FS.body_l, Palette.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	p.custom_minimum_size.x = UIKit.W.dialog - 2.0 * (UIKit.PAD.card + 4)
	col.add_child(p)
	col.add_child(UIKit.spacer())
	var play := UIKit.button(play_text, "honey", "lg")
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var home := UIKit.button(home_text, "ghost", "sm")
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(play)
	col.add_child(home)
	_card.add_child(col)
	add_child(_card)
	_card.custom_minimum_size.x = minf(UIKit.W.dialog, size.x - 2.0 * UIKit.SCREEN_GUTTER)
	_card.size = _card.get_combined_minimum_size()
	_card.position = ((size - _card.size) / 2.0).round()
	UIKit.pop_in(_card, 0.28)
	play.pressed.connect(func(): card_picked.emit("play"))
	home.pressed.connect(func(): card_picked.emit("home"))
	var what: String = await card_picked
	return what

## Everything off (the tutorial ended or was left).
func clear() -> void:
	hide_step()
	_end_hold()
	_note_id += 1
	_near = Callable()
	_bubble.visible = false
	_close_card()

## A note is showing.
func noting() -> bool:
	return not _near.is_null()

func blocking() -> bool:
	return _block

## The cut-out you may tap now (local px), or an empty rect.
func hole() -> Rect2:
	return _hole if _block and not _target.is_null() else Rect2()


# ---------- helpers for targets ----------

## A control's rect (screen px) grown by HOLE_PAD.
static func around_control(c: Control) -> Callable:
	return func() -> Rect2:
		if not is_instance_valid(c) or not c.is_visible_in_tree():
			return Rect2()
		return c.get_global_rect().grow(HOLE_PAD)

## A square of `d` px centred on a screen point given by `at` (-> Vector2).
static func around_point(at: Callable, d := PAWN_HOLE) -> Callable:
	return func() -> Rect2:
		var p: Vector2 = at.call()
		return Rect2(p - Vector2(d, d) / 2.0, Vector2(d, d))


# ---------- internals ----------

func _end_hold() -> void:
	_holding = false
	_dismissed = false
	if _hint:
		_hint.visible = false
	if not _block:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

func _set_text(text: String, sub: String) -> void:
	_title.text = text
	_sub.text = sub
	_sub.visible = sub != ""
	_hint.visible = false
	var w := maxf(_text_w(_title, text), _text_w(_sub, sub) if sub != "" else 0.0) + 2.0 * UIKit.SPACE.lg + 8.0
	_bubble.custom_minimum_size.x = minf(clampf(w, 180.0, BUBBLE_W), size.x - 2.0 * UIKit.SCREEN_GUTTER)
	_bubble.size = Vector2.ZERO
	_bubble.visible = text != ""
	_bubble_in = 0.0 if not Sheet.reduce_motion() else 1.0

static func _text_w(l: Label, t: String) -> float:
	var f := l.get_theme_font("font")
	return f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x if f else 0.0

func _close_card() -> void:
	if is_instance_valid(_card):
		_card.queue_free()
	_card = null
	_skip.visible = true

func _fade_to(v: float) -> void:
	if _fade_tw:
		_fade_tw.kill()
	if Sheet.reduce_motion() or not is_inside_tree():
		_amount = v
		return
	_fade_tw = create_tween()
	_fade_tw.tween_property(self, "_amount", v, FADE * (1.0 if v > _amount else 0.8))

func _to_local(r: Rect2) -> Rect2:
	if r.size == Vector2.ZERO:
		return r
	var inv := get_global_transform().affine_inverse()
	return Rect2(inv * r.position, r.size)

func _update_rects() -> void:
	_hole = _to_local(_target.call()) if not _target.is_null() else Rect2()
	_mark_rect = _to_local(_mark.call()) if not _mark.is_null() else Rect2()

func _process(delta: float) -> void:
	_t += delta
	_hold_t += delta
	_nudge = maxf(0.0, _nudge - delta / 0.45)
	_bubble_in = minf(1.0, _bubble_in + delta / 0.24)
	_update_rects()
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("amount", _amount)
	_set_hole("hole_a", "radius_a", _hole)
	_set_hole("hole_b", "radius_b", _mark_rect)
	_scrim.visible = _amount > 0.002
	_place_bubble()
	_place_hand()
	queue_redraw()

func _set_hole(key: String, rkey: String, r: Rect2) -> void:
	if r.size == Vector2.ZERO:
		_mat.set_shader_parameter(key, Vector4(-100, -100, 0, 0))
		return
	var grow := 0.0 if Sheet.reduce_motion() else (1.0 - _ease(_amount)) * 26.0   # the cut-out closes in
	var c := r.get_center()
	var h := r.size / 2.0 + Vector2(grow, grow)
	_mat.set_shader_parameter(key, Vector4(c.x, c.y, h.x, h.y))
	_mat.set_shader_parameter(rkey, minf(h.x, h.y))

static func _ease(k: float) -> float:
	return 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)

## The caption above its target when there is room, else below; centred on it, kept on screen.
func _place_bubble() -> void:
	if not _bubble.visible:
		return
	var ref := _hole
	if ref.size != Vector2.ZERO and _mark_rect.size != Vector2.ZERO:
		ref = ref.merge(_mark_rect)            # never cover what the step points out
	if ref.size == Vector2.ZERO and not _near.is_null():
		ref = _to_local(_near.call())
	var bs := _bubble.get_combined_minimum_size()
	_bubble.size = bs
	var y: float
	var above := true
	if ref.size == Vector2.ZERO:
		y = size.y * 0.42
	else:
		var top_room := ref.position.y - GAP - TAIL - bs.y
		above = top_room > safe_top + UIKit.TAP + UIKit.SPACE.sm
		y = top_room if above else ref.end.y + GAP + TAIL
	var cx := ref.get_center().x if ref.size != Vector2.ZERO else size.x / 2.0
	var x := clampf(cx - bs.x / 2.0, UIKit.SCREEN_GUTTER, size.x - UIKit.SCREEN_GUTTER - bs.x)
	var k := _ease(_bubble_in)
	var wiggle := sin(_nudge * PI * 6.0) * 6.0 * _nudge
	_bubble.position = Vector2(round(x + wiggle), round(y + (1.0 - k) * (8.0 if above else -8.0)))
	_bubble.modulate.a = k
	_bubble.set_meta("above", above)
	_bubble.set_meta("ref", ref)

## The hand taps the cut-out's centre from the lower right (the die shows its own hand after a while instead).
func _place_hand() -> void:
	var on := _block and _hand_on and _hole.size != Vector2.ZERO and _amount > 0.6
	if on and is_instance_valid(_dice) and _dice.has_method("hinting") and _dice.call("hinting"):
		on = false
	_hand.visible = on
	if not on:
		return
	var k := fmod(_t, 1.2) / 1.2
	var press := sin(clampf(k / 0.35, 0.0, 1.0) * PI) if not Sheet.reduce_motion() else 0.0
	var tip := _hole.get_center() + Vector2(_hole.size.x * 0.12, _hole.size.y * 0.18)
	_hand.position = tip - _hand.pivot_offset + Vector2(6, 8) * (1.0 - press)
	_hand.scale = Vector2.ONE * (1.0 - 0.08 * press)

func _draw() -> void:
	if _amount <= 0.01 and not _bubble.visible:
		return
	var a := _ease(_amount)
	if _block and _hole.size != Vector2.ZERO:
		var pulse := 0.0 if Sheet.reduce_motion() else (sin(_t * TAU / 1.1) + 1.0) / 2.0
		var r := minf(_hole.size.x, _hole.size.y) / 2.0
		var w := RING_W + _nudge * 2.0
		_ring(_hole.grow(2.0 + pulse * 3.0), r + 2.0 + pulse * 3.0, Color(Palette.HONEY, a * (0.95 - 0.35 * pulse)), w)
		_ring(_hole.grow(8.0 + pulse * 7.0), r + 8.0 + pulse * 7.0, Color(Palette.HONEY, a * 0.35 * (1.0 - pulse)), 2.0)
		if _nudge > 0.0:
			_ring(_hole.grow(4.0), r + 4.0, Color(Color.WHITE, _nudge * a), 2.0)
	if _mark_rect.size != Vector2.ZERO and _amount > 0.01:
		var rm := minf(_mark_rect.size.x, _mark_rect.size.y) / 2.0
		_dashed(_mark_rect.get_center(), rm + 1.0, Color(Color.WHITE, a * 0.9))
	_tail.queue_redraw()

## A rounded-rect outline matching the cut-out shape (a circle when square).
func _ring(r: Rect2, radius: float, col: Color, w: float) -> void:
	if absf(r.size.x - r.size.y) < 1.0:
		draw_arc(r.get_center(), r.size.x / 2.0, 0.0, TAU, 64, col, w, true)
		return
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(int(round(w)))
	sb.border_color = col
	sb.set_corner_radius_all(int(minf(radius, minf(r.size.x, r.size.y) / 2.0)))
	sb.anti_aliasing = true
	sb.corner_detail = 12
	draw_style_box(sb, r)

## A slowly turning dashed circle: "look here".
func _dashed(c: Vector2, r: float, col: Color) -> void:
	var n := 14
	var spin := 0.0 if Sheet.reduce_motion() else _t * 0.6
	for i in n:
		var a0 := spin + TAU * i / n
		draw_arc(c, r, a0, a0 + TAU / n * 0.55, 6, col, 2.5, true)

## The caption's tail, pointing at its target (drawn over the bubble's edge, so the two read as one shape).
func _draw_tail() -> void:
	if not _bubble.visible or not _bubble.has_meta("ref"):
		return
	var ref: Rect2 = _bubble.get_meta("ref")
	if ref.size == Vector2.ZERO:
		return
	var above: bool = _bubble.get_meta("above")
	var br := Rect2(_bubble.position, _bubble.size)
	var aim := _hole.get_center() if _hole.size != Vector2.ZERO else ref.get_center()
	var tx := clampf(aim.x, br.position.x + 26.0, br.end.x - 26.0)
	var col := Color(Palette.CARD, _bubble.modulate.a)
	var edge := Color(Palette.HONEY, _bubble.modulate.a)
	var pts: PackedVector2Array
	if above:
		var y := br.end.y - 2.0
		pts = PackedVector2Array([Vector2(tx - TAIL, y), Vector2(tx + TAIL, y), Vector2(tx, y + TAIL + 2.0)])
	else:
		var y := br.position.y + 2.0
		pts = PackedVector2Array([Vector2(tx - TAIL, y), Vector2(tx, y - TAIL - 2.0), Vector2(tx + TAIL, y)])
	var edges := PackedVector2Array([pts[0], pts[2], pts[1]]) if above else pts
	var inset := float(UIKit.BW.rim) + 1.0
	var fill := pts.duplicate()
	for k in fill.size():
		if absf(fill[k].x - tx) > 0.5:          # the two base corners: pull them inside the bubble's border
			fill[k].y += -inset if above else inset
	_tail.draw_colored_polygon(fill, col)
	_tail.draw_line(edges[0], edges[1], edge, UIKit.BW.rim, true)
	_tail.draw_line(edges[1], edges[2], edge, UIKit.BW.rim, true)

## Taps reach the game only inside the cut-out (and the skip button, a child, gets its own).
func _has_point(point: Vector2) -> bool:
	if _holding and not _block:
		return point.y >= safe_top - UIKit.SPACE.sm          # the pause and gear above stay tappable
	if not _block:
		return false
	var h := hole()
	return h.size == Vector2.ZERO or not h.has_point(point)

func _gui_input(e: InputEvent) -> void:
	var hit := false
	if e is InputEventScreenTouch and e.pressed:
		hit = true
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		hit = e.device != InputEvent.DEVICE_ID_EMULATION
	if hit and _holding and not _block:
		if _hold_t >= HOLD_MIN:
			_dismissed = true
			Haptics.light()
	elif hit and _block and not is_instance_valid(_card):
		_nudge = 1.0
		Haptics.light()
	if e is InputEventMouseButton or e is InputEventScreenTouch:
		accept_event()
