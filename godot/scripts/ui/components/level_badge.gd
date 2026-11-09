class_name LevelBadge
extends Control
## The player level as a gold pill: a small "Lv" and the number (Lilita One), on a glossy gold capsule with a dark
## rim. It grows sideways with the digits, so "Lv 7", "Lv 47" and "Lv 128" all read at every size (the old star's
## body only held one digit). Heights: "xs" 18, "sm" 22, "md" 26, "lg" 32, "xl" 40 (or a px number). `px` is the
## height, `bsize` the whole badge (callers place it from bsize: it is wider than tall).
##
##   var lvl := LevelBadge.new(Save.level, "sm")
##   lvl.set_level(3, true)                     # pop when the player levels up
##   var row := LevelBadge.row(lvl, Meter.new("night", 12))   # the pill overlapping the start of an XP bar

const SIZES := {xs = 18.0, sm = 22.0, md = 26.0, lg = 32.0, xl = 40.0}
const RIM := Color("#7a3a18")
const FACE := Color("#f2b632")
const GLOSS := Color("#ffd866")
const INK := Color("#4a2212")
const PREFIX := "Lv"                           ## a symbol like "XP" (not translated)

var level := 1
var px := 22.0                                 ## the pill's height
var bsize := Vector2(44, 22)                   ## the whole pill
var _tw: Tween


func _init(level_ := 1, size_: Variant = "sm") -> void:
	level = level_
	px = float(SIZES.get(size_, 22.0)) if size_ is String else float(size_)
	_apply_size()
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Show a level. animate: a springy pop (level up).
func set_level(n: int, animate := false) -> void:
	level = n
	_apply_size()
	queue_redraw()
	if not animate or not is_inside_tree():
		return
	if _tw and _tw.is_valid():
		_tw.kill()
	pivot_offset = size / 2.0
	scale = Vector2(0.6, 0.6)
	rotation = deg_to_rad(-10.0)
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(self, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "rotation", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The number's and the prefix's font sizes at this height.
func number_size() -> int:
	return maxi(10, int(round(px * 0.66)))

func prefix_size() -> int:
	return maxi(8, int(round(px * 0.44)))

## The pill's size for a level at a height (the width follows the digits).
static func pill_size(level_: int, h: float) -> Vector2:
	var font := UIKit.font_display()
	var nw := font.get_string_size(str(level_), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, int(round(h * 0.66)))).x
	var pw := font.get_string_size(PREFIX, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, int(round(h * 0.44)))).x
	return Vector2(ceilf(h * 0.78 + pw + h * 0.12 + nw), h)


func _apply_size() -> void:
	bsize = pill_size(level, px)
	custom_minimum_size = bsize
	size = bsize


## Place the pill centred on the bottom edge of a square avatar box of side `side` (it overhangs by `drop` px).
func place_under(side: float, drop := 4.0) -> void:
	position = Vector2(roundf((side - bsize.x) / 2.0), side - bsize.y + drop)
	size = bsize


## A row with `badge` overlapping the left end of `meter`: the fill starts behind the pill and comes out past it.
## Returns an HBoxContainer (meter expands).
static func row(badge: LevelBadge, meter: Meter) -> HBoxContainer:
	var r := HBoxContainer.new()
	var overlap := roundf(badge.bsize.x * 0.5)
	r.add_theme_constant_override("separation", -int(overlap))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.inset_left = overlap
	meter.show_behind_parent = true            # the pill is drawn over the bar's start by draw order (no z_index)
	r.add_child(badge)
	r.add_child(meter)
	return r


func _box(bg: Color, r: float, border := 0.0, border_col := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(int(ceilf(r)))
	s.corner_detail = 10
	s.anti_aliasing = true
	if border > 0.0:
		s.set_border_width_all(int(round(border)))
		s.border_color = border_col
	return s


func _draw() -> void:
	var h := bsize.y
	var r := Rect2((size - bsize) / 2.0, bsize)
	var rim := maxf(1.0, roundf(h / 12.0))
	draw_style_box(_box(Color(INK, 0.35), h / 2.0), Rect2(r.position + Vector2(0, maxf(1.0, h / 16.0)), r.size))   # drop
	draw_style_box(_box(FACE, h / 2.0, rim, RIM), r)
	# gloss: the top half a lighter gold, inset from the rim
	var g := Rect2(r.position + Vector2(rim + h * 0.12, rim + 0.5), Vector2(r.size.x - 2.0 * (rim + h * 0.12), h * 0.42))
	if g.size.x > 2.0:
		draw_style_box(_box(Color(GLOSS, 0.9), g.size.y / 2.0), g)
	var font := UIKit.font_display()
	var fs := number_size()
	var ps := prefix_size()
	var nw := font.get_string_size(str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pw := font.get_string_size(PREFIX, HORIZONTAL_ALIGNMENT_LEFT, -1, ps).x
	var x := r.position.x + (r.size.x - (pw + h * 0.12 + nw)) / 2.0
	var base := r.position.y + (h - font.get_height(fs)) / 2.0 + font.get_ascent(fs) + h * 0.02
	var ol := 1 if h < 26.0 else 2
	draw_string_outline(font, Vector2(x, base), PREFIX, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, ol, Color(1, 0.96, 0.82, 0.8))
	draw_string(font, Vector2(x, base), PREFIX, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, INK)
	var nx := x + pw + h * 0.12
	draw_string_outline(font, Vector2(nx, base), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ol, Color(1, 0.96, 0.82, 0.8))
	draw_string(font, Vector2(nx, base), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
