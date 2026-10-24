class_name Meter
extends Control
## A progress bar drawn in code: a rounded track with a rounded fill. Never an empty dark slab: at 0 the fill still
## shows a thin sliver, so the bar reads as "a bar with no progress yet". Looks:
##   "xp"     GOLD_FILL (glossy) on the light TRACK         (XP on cream cards: profile, result screen)
##   "night"  GOLD_FILL (glossy) on a dark INK track, inset (web .pxp / .xpbar: the home top bar)
##   "track"  PEACH on TRACK                                (neutral progress: steps, collection counts)
##   "teal"   TEAL_SOFT on TRACK                            (achievements, collection progress)
## Optional centred numbers ("45 / 150 XP", Nunito 900, 12-14 px with an outline so they read on fill and track);
## numbers need a bar of at least 16 px (the height grows to 16 when they're on).
## inset_left: room at the left end for an overlapping LevelBadge (LevelBadge.row does this); the fill starts there.
##
##   var xp := Meter.new("night", 12)              # home: no numbers
##   var xp2 := Meter.new("xp", 20, true, "XP")    # profile: "45 / 150 XP"
##   xp2.set_value(45, 150, true)

const LOOKS := ["xp", "night", "track", "teal"]
const SEC := 0.5
const MIN_SLIVER := 4.0

var look := "xp"
var value := 0.0                     ## the value (clamped to 0..max_value)
var max_value := 1.0
var numbers := false                 ## draw "value / max unit" in the middle
var unit := ""                       ## after the numbers ("XP"); "" = none
var text_override := ""              ## when set, drawn instead of the numbers
var inset_left := 0.0

var _shown := 0.0                    # the fraction on screen (animates)
var _tw: Tween
var _sb := {}                        # cached styleboxes


func _init(look_ := "xp", height := 14.0, numbers_ := false, unit_ := "") -> void:
	look = look_ if look_ in LOOKS else "xp"
	numbers = numbers_
	unit = unit_
	var h := maxf(height, 16.0) if numbers else maxf(height, 6.0)
	custom_minimum_size = Vector2(40, h)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Set the value and maximum (value is clamped to 0..max; max <= 0 counts as an empty bar). animate: the fill slides
## from where it is over 0.5 s.
func set_value(v: float, max_v: float, animate := false) -> void:
	max_value = maxf(0.0, max_v)
	value = clampf(v, 0.0, max_value)
	var target := fraction()
	if _tw and _tw.is_valid():
		_tw.kill()
	if animate and is_inside_tree() and not is_equal_approx(_shown, target):
		_tw = create_tween()
		_tw.tween_method(func(f: float) -> void:
			_shown = f
			queue_redraw(), _shown, target, SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_shown = target
	queue_redraw()


## value / max_value in 0..1 (0 when max is 0).
func fraction() -> float:
	return clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0


## The fraction on screen right now (differs from fraction() while animating).
func shown_fraction() -> float:
	return _shown


## The centred text ("45 / 150 XP"), "" when numbers are off.
func label_text() -> String:
	if text_override != "":
		return text_override
	if not numbers:
		return ""
	var t := "%s / %s" % [Fmt.coins_full(int(round(value))), Fmt.coins_full(int(round(max_value)))]
	return t + (" " + unit if unit != "" else "")


## The label in the room there is: as is, then without the unit and the spaces ("45/150"), else "" (none).
static func fitted_text(t: String, font: Font, fs: int, room: float) -> String:
	if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= room:
		return t
	var parts := t.split(" ", false)
	var short := t.replace(" ", "")
	if parts.size() >= 3 and parts[1] == "/":
		short = parts[0] + "/" + parts[2]
	if font.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= room:
		return short
	return ""


## Replace the numbers with a text of your own ("" = back to the numbers).
func set_text(t: String) -> void:
	text_override = t
	queue_redraw()


# ---------------------------------------------------------------------------------------------------------------------

func _box(key: String, bg: Color) -> StyleBoxFlat:
	if not _sb.has(key):
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_corner_radius_all(UIKit.R.pill)
		s.corner_detail = 8
		s.anti_aliasing = true
		_sb[key] = s
	return _sb[key]


func _draw() -> void:
	var h := size.y
	var track := Rect2(Vector2.ZERO, size)
	var night := look == "night"
	var pad := clampf(roundf(h * 0.16), 2.0, 3.0) if night else 0.0
	var track_col := Palette.INK if night else Palette.TRACK
	draw_style_box(_box("track", track_col), track)
	# inset shade along the top of the track (web: inset 0 2px 3px)
	var shade := _box("shade", Color(0, 0, 0, 0))
	shade.border_width_top = 2
	shade.border_color = Color(0, 0, 0, 0.32) if night else Color(Palette.SHADOW, 0.12)
	shade.border_blend = true
	draw_style_box(shade, track)
	var inner := Rect2(track.position + Vector2(pad + inset_left, pad), track.size - Vector2(2.0 * pad + inset_left, 2.0 * pad))
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var sliver := maxf(MIN_SLIVER, minf(inner.size.y * 0.5, 8.0))
	var w := clampf(inner.size.x * _shown, sliver, inner.size.x)
	var fill := Rect2(inner.position, Vector2(w, inner.size.y))
	var fill_col: Color
	match look:
		"xp", "night": fill_col = Palette.GOLD_FILL
		"track": fill_col = Palette.PEACH
		_: fill_col = Palette.TEAL_SOFT
	if _shown <= 0.0:
		fill_col = Color(fill_col, 0.75)            # the empty sliver: a quieter tint
	var fb := _box("fill_" + look, fill_col)
	fb.bg_color = fill_col
	if not night:
		# a hairline darker rim so the fill reads on the light track
		fb.border_width_bottom = 1 if inner.size.y >= 8.0 else 0
		fb.border_color = fill_col.darkened(0.18)
	draw_style_box(fb, fill)
	# gloss: a soft white band over the top half (web linear-gradient(gold-hi, gold))
	if fill.size.y >= 6.0 and fill.size.x >= 6.0:
		var g := _box("gloss", Palette.GLOSS)
		var gh := roundf(fill.size.y * 0.42)
		var gr := Rect2(fill.position + Vector2(minf(3.0, fill.size.x * 0.25), 1.0), Vector2(maxf(0.0, fill.size.x - 2.0 * minf(3.0, fill.size.x * 0.25)), gh))
		if gr.size.x > 2.0:
			draw_style_box(g, gr)
	var t := label_text()
	if t == "":
		return
	var fs := clampi(int(h) - 6, UIKit.FS.small, UIKit.FS.label)
	var font := UIKit.font_body(900, true)
	var area := Rect2(Vector2(inset_left, 0), Vector2(size.x - inset_left, h))
	t = fitted_text(t, font, fs, area.size.x - 8.0)
	if t == "":
		return                                       # too narrow for any form of the numbers: the bar alone
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(area.position.x + (area.size.x - tw) / 2.0, (h - font.get_height(fs)) / 2.0 + font.get_ascent(fs))
	var fg := Color.WHITE if night else Palette.INK
	var ol := Color(Palette.INK_STRONG, 0.75) if night else Color(Color.WHITE, 0.85)
	draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, ol)
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)
