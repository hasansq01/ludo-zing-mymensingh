class_name LevelBadge
extends Control
## The player level as a gold star (assets/ui/ic_star.svg) with the number on it (web .lvstar). Replaces the
## "star 2" text chips and the profile's honey disc. Sizes: "xs" 24, "sm" 28, "md" 36, "lg" 48, "xl" 64 (or a px number).
## The number is Nunito 900 with tabular figures in INK, at least 12 px; it shrinks to fit 3 digits. From level 10 the
## star is never smaller than "sm" (28 px): two digits don't fit the 24 px star's body. A light rim keeps the digits
## readable on the star at every size.
##
##   var lvl := LevelBadge.new(Save.level, "sm")
##   lvl.set_level(3, true)                     # pop when the player levels up
##   var row := LevelBadge.row(lvl, Meter.new("night", 12))   # the star overlapping the start of an XP bar

const SIZES := {xs = 24.0, sm = 28.0, md = 36.0, lg = 48.0, xl = 64.0}

var level := 1
var px := 28.0
var _base_px := 28.0
var _star: Texture2D
var _tw: Tween


func _init(level_ := 1, size_: Variant = "sm") -> void:
	level = level_
	_base_px = float(SIZES.get(size_, 28.0)) if size_ is String else float(size_)
	_apply_size()
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_star = UIKit.svg("ic_star")


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
	rotation = deg_to_rad(-18.0)
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(self, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "rotation", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The star's px for a requested size: at least MIN_TWO_DIGITS from level 10.
static func size_for(level_: int, base: float) -> float:
	return maxf(base, SIZES.sm) if level_ >= 10 else base


func _apply_size() -> void:
	px = size_for(level, _base_px)
	custom_minimum_size = Vector2(px, px)


## The number's font size at this badge size (>= 12).
func number_size() -> int:
	var digits := str(level).length()
	var k := 0.43 if digits <= 1 else (0.38 if digits == 2 else 0.31)
	return maxi(UIKit.FS.small, int(round(px * k)))


## A row with `badge` overlapping the left end of `meter` (web .lvl: the star sits over the bar's start). The meter
## gets inset_left = the covered length: its fill starts behind the star and comes out past it. Returns an
## HBoxContainer (meter expands).
static func row(badge: LevelBadge, meter: Meter) -> HBoxContainer:
	var r := HBoxContainer.new()
	var overlap := roundf(badge.px * 0.45)
	r.add_theme_constant_override("separation", -int(overlap))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.inset_left = overlap
	meter.show_behind_parent = true            # the star is drawn over the bar's start by draw order (no z_index)
	r.add_child(badge)
	r.add_child(meter)
	return r


func _draw() -> void:
	var s := minf(size.x, size.y)
	var r := Rect2((size - Vector2(s, s)) / 2.0, Vector2(s, s))
	if _star:
		# web drop-shadow(0 1px 0 rgba(74,43,61,.35))
		draw_texture_rect(_star, Rect2(r.position + Vector2(0, maxf(1.0, s / 28.0)), r.size), false, Color(Palette.INK, 0.35))
		draw_texture_rect(_star, r, false)
	var t := str(level)
	var fs := number_size()
	var font := UIKit.font_body(900, true)
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# the star's body sits a little below the box centre (its points reach the top)
	var cy := r.position.y + s * 0.56
	var pos := Vector2(r.position.x + (s - tw) / 2.0, cy - font.get_height(fs) / 2.0 + font.get_ascent(fs))
	# a soft light rim keeps the digits off the star's dark outline (1 px on the small stars)
	draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(s / 12.0)) if s >= 36.0 else 1, Color(Palette.HONEY_RIM, 0.9))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.INK)
