class_name RibbonTitle
extends Control
## The orange title ribbon across the top edge of a .pm sheet (index.html .pm-title): a rounded RIBBON face with a
## 2.5 px RIBBON_RIM border, a RIBBON_LIP inner lip along the bottom, a white gloss line along the top and a soft drop,
## the title in white Lilita with a warm shadow. Optionally an (i) bubble after the title (Info.icon(info_key)).
##   var r := RibbonTitle.new("Settings")          # natural width (text + padding), 48 px tall
##   var r := RibbonTitle.new("Daily Reward", 240, "daily")
## Sheet (look "pm") makes one, centres it on the card's top edge and calls fit_to(card width) on every resize:
## at least 58% of the card, at most the card minus 84 px (room for the close button); a long title shrinks its font
## (22 down to 15) and then ends in an ellipsis.

const H := 48.0                          ## ribbon height (web: 8 + 11 padding, 1.1 line, 2 x 2.5 border)
const PAD_X := 22.0                      ## side padding of the text
const RIM := 2.5                         ## RIBBON_RIM border
const LIP_H := 4.0                       ## inset 0 -4px 0 RIBBON_LIP
const RADIUS := 15
const INFO_GAP := 8.0
const FS_MAX := 22                       ## UIKit.FS.h1 (web 1.4rem)
const FS_MIN := 15

var label: Label                         ## the title text (Sheet exposes it as title_label)
var info: Control                        ## the (i) bubble, or null
var fixed_width := 0.0                   ## > 0: always this wide (still capped by fit_to)

var _row: HBoxContainer
var _sb_drop: StyleBoxFlat
var _sb_rim: StyleBoxFlat
var _sb_lip: StyleBoxFlat
var _sb_face: StyleBoxFlat
var _sb_gloss: StyleBoxFlat
var _avail := 0.0                        # the width fit_to allows (0 = no limit)


func _init(text := "", width := 0.0, info_key := "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fixed_width = width
	_sb_drop = _flat(Color(Palette.INK, 0.25), RADIUS)
	_sb_rim = _flat(Palette.RIBBON_RIM, RADIUS)
	_sb_lip = _flat(Palette.RIBBON_LIP, RADIUS - 2)
	_sb_face = _flat(Palette.RIBBON, RADIUS - 2)
	_sb_gloss = _flat(Palette.GLOSS, RADIUS - 2)
	_sb_gloss.draw_center = false
	_sb_gloss.border_width_top = 2
	_sb_gloss.border_color = Palette.GLOSS
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = PAD_X
	center.offset_right = -PAD_X
	center.offset_top = RIM
	center.offset_bottom = -(RIM + LIP_H)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_row = UIKit.hbox(int(INFO_GAP))
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_row)
	label = UIKit.label(text, FS_MAX, Color.WHITE, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_shadow_color", Palette.RIBBON_SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("shadow_outline_size", 0)
	label.add_theme_color_override("font_outline_color", Color(Palette.RIBBON_LIP, 0.55))
	label.add_theme_constant_override("outline_size", 3)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(label)
	if info_key != "":
		info = Info.icon(info_key, true, 22, "light")
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(info)
	custom_minimum_size = Vector2(0, H)
	size = Vector2(natural_width(), H)

static func _flat(c: Color, r: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.corner_detail = 10
	s.anti_aliasing = true
	return s


## Change the title (keeps the width rules).
func set_text(t: String) -> void:
	label.text = t
	fit_to(_avail)

## The width the ribbon wants: the title at full size plus padding (and the (i) bubble).
func natural_width() -> float:
	if fixed_width > 0.0:
		return fixed_width
	return _content_w(FS_MAX) + 2.0 * PAD_X

func _content_w(fs: int) -> float:
	var w := UIKit.font_display().get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2.0
	if info:
		w += INFO_GAP + info.get_combined_minimum_size().x
	return ceilf(w)

## Size the ribbon for a card `card_w` wide (web: min-width 58%, max-width card - 84 px). Shrinks the font when the
## title doesn't fit, then trims it with an ellipsis. card_w 0: natural width. Sets size (and offsets around the
## current centre when the ribbon is anchored to a centre point).
func fit_to(card_w: float) -> void:
	_avail = card_w
	var w := natural_width()
	var max_w := INF
	if card_w > 0.0:
		max_w = maxf(120.0, card_w - 84.0)
		w = clampf(w, minf(card_w * 0.58, max_w), max_w)
	var room := w - 2.0 * PAD_X
	var fs := FS_MAX
	while fs > FS_MIN and _content_w(fs) > room:
		fs -= 1
	label.add_theme_font_size_override("font_size", fs)
	var text_room := room - (INFO_GAP + info.get_combined_minimum_size().x if info else 0.0)
	var text_w := _content_w(fs) - (INFO_GAP + info.get_combined_minimum_size().x if info else 0.0)
	label.custom_minimum_size.x = minf(text_w, text_room)   # an ellipsis label reports no width of its own
	size = Vector2(w, H)
	custom_minimum_size.x = w
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(_sb_drop, Rect2(r.position + Vector2(0, 3), r.size))     # 0 3px 0 rgba(74,43,61,.25)
	draw_style_box(_sb_rim, r)
	var inner := r.grow(-RIM)
	draw_style_box(_sb_lip, inner)
	draw_style_box(_sb_face, Rect2(inner.position, inner.size - Vector2(0, LIP_H)))
	draw_style_box(_sb_gloss, Rect2(inner.position, inner.size - Vector2(0, LIP_H)))   # inset 0 2px 0 white .35
