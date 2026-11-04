class_name GameTopBar
extends Control
## The game screen's top row (Ludo, Snakes & Ladders, the S&L landing): a left icon button (pause, or back),
## the event line in the middle (a cream glass bar, 16 px Nunito, plum ink; bold names tinted with the player's
## colour) and the gear on the right. Full width, sits under the safe area (set safe_top).
##
## The event line has two layers:
##   set_idle(bb)  the persistent state ("Your turn — tap the dice", "Mocha is thinking…"), shown quietly
##   say(bb, sec, kind)  a transient message. kind "event" (a capture, a 6, home) pops in and stays readable at
##                 least MIN_EVENT s; kind "info" just shows for `sec`. A new message replaces the current one,
##                 except that an "info" arriving while an "event" is younger than MIN_EVENT waits for it (only
##                 the latest waiting message is kept). When the message expires the bar goes back to the idle
##                 text; with no idle text the bar fades out (never stale text).
## [b]Name[/b] is bold in the current turn's colour (set_turn); GameTopBar.who(name, c) tints one name explicitly.
## The line is one line, always the same height: 16 px, shrinking to 14 px for a long message (two lines of 14 px
## only when even that can't fit, still inside the 48 px bar), so the bar never jumps between turns.
## info_slot: (old) an ⓘ inside the bar's right end. Avoid it: a help icon inside a transient message reads as "about
## this message" and narrows the line; the games put their ⓘ on the player's own tile instead.
## hide_for_result() hides the whole row (result screens); show_bar() brings it back.

signal left_pressed
signal gear_pressed

const MIN_EVENT := 1.6
const ROW_H := 48.0
const TOP_GAP := 12.0
const FS_MIN := 14                       # a long line shrinks to this before it wraps

var safe_top := 0.0:
	set(v):
		safe_top = v
		_layout()
## "pause" or "back".
var mode := "pause"
var info_slot: HBoxContainer
var bar: PanelContainer
var text: RichTextLabel
var left_button: Button
var gear_button: Button

var _idle := ""
var _msg := ""
var _msg_kind := ""
var _msg_left := 0.0
var _msg_age := 0.0
var _pending: Array = []                 # [bb, sec, kind] waiting for an event to be read
var _turn := -1
var _shown := ""
var _mirror: Control                     # left spacer matching info_slot, so the text stays centred
var _sb: StyleBoxFlat
var _sb_event: StyleBoxFlat
var _flash := 0.0
var _hidden := false
var _bar_tw: Tween
var _fit_queued := false


func _init(mode_ := "pause") -> void:
	mode = mode_
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	_sb = UIKit.glass(UIKit.R.md + 2)
	_sb.border_width_bottom = UIKit.LIP.sm
	_sb.border_color = Palette.LINE
	UIKit.pad(_sb, UIKit.SPACE.md, 6)
	_sb.content_margin_bottom = 6 + UIKit.LIP.sm - 1
	_sb_event = _sb.duplicate()
	bar = PanelContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("panel", _sb)
	add_child(bar)
	var row := UIKit.hbox(UIKit.SPACE.xs)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)
	_mirror = Control.new()
	_mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_mirror)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_OFF
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_override("normal_font", UIKit.font_body(800))
	text.add_theme_font_override("bold_font", UIKit.font_body(900))
	text.add_theme_font_size_override("normal_font_size", UIKit.FS.status)
	text.add_theme_font_size_override("bold_font_size", UIKit.FS.status)
	text.add_theme_color_override("default_color", Palette.INK)
	text.add_theme_constant_override("line_separation", -2)
	row.add_child(text)
	info_slot = UIKit.hbox(0)
	info_slot.mouse_filter = Control.MOUSE_FILTER_PASS
	info_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info_slot)
	info_slot.resized.connect(_sync_mirror)
	info_slot.child_entered_tree.connect(func(n: Node):
		if n is CanvasItem:
			(n as CanvasItem).visibility_changed.connect(_sync_mirror.call_deferred)
		_sync_mirror.call_deferred())
	info_slot.child_exiting_tree.connect(func(_n): _sync_mirror.call_deferred())
	bar.modulate.a = 0.0
	# A PanelContainer only ever grows to its minimum size. The RichTextLabel's first measure can happen before the
	# row has its width (set_idle before layout wraps every word onto its own line), so shrink the bar back to its
	# content whenever the minimum changes.
	bar.minimum_size_changed.connect(_fit_later)
	set_mode(mode)
	gear_button = UIKit.icon_button("ic_gear")
	gear_button.pressed.connect(func(): gear_pressed.emit())
	add_child(gear_button)
	resized.connect(_layout)
	set_process(false)


## "pause" (in a game) or "back" (the S&L landing).
func set_mode(m: String) -> void:
	mode = m
	if left_button:
		left_button.queue_free()
	left_button = UIKit.icon_button("ic_back" if m == "back" else "ic_pause")
	left_button.pressed.connect(func(): left_pressed.emit())
	add_child(left_button)
	_layout()

## The colour plain [b]names[/b] take: the player whose turn it is (-1 = ink).
func set_turn(c: int) -> void:
	_turn = c

## A transient message (see the class notes). sec <= 0: stays until replaced or cleared.
func say(bb: String, sec := 1.6, kind := "info") -> void:
	if bb == "":
		return
	if kind != "event" and _msg_kind == "event" and _msg != "" and _msg_age < MIN_EVENT:
		_pending = [bb, sec, kind]
		return
	_pending = []
	_msg = bb
	_msg_kind = kind
	_msg_age = 0.0
	_msg_left = maxf(sec, MIN_EVENT) if kind == "event" else (sec if sec > 0 else INF)
	_show(_tint(bb), kind == "event")
	set_process(true)

## The persistent state line, shown whenever no message is up. "" = nothing (the bar hides when idle).
func set_idle(bb: String) -> void:
	_idle = bb
	if _msg == "":
		_show(_tint(bb), false)

## Drops the message on show (and any waiting one) and goes back to the idle text: a prompt aimed at the player
## replaces whatever event was still being read.
func cancel_message() -> void:
	_msg = ""
	_msg_kind = ""
	_pending = []
	_show(_tint(_idle), false)

## No message, nothing waiting, no idle text: the bar fades out.
func clear() -> void:
	_msg = ""
	_msg_kind = ""
	_pending = []
	_idle = ""
	_show("", false)
	set_process(false)

## The text the bar is showing (or fading out from), as BBCode before tinting; for tests and tools.
func current() -> String:
	return _msg if _msg != "" else _idle

## Hides the whole row (buttons too) behind a result screen.
func hide_for_result() -> void:
	_hidden = true
	clear()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func(): visible = false)

## Brings the row back after hide_for_result() (a new game).
func show_bar() -> void:
	_hidden = false
	visible = true
	modulate.a = 1.0

## [b]name[/b] in player c's name colour, for messages that mention someone other than the current player.
static func who(name: String, c: int) -> String:
	return "[b][color=#%s]%s[/color][/b]" % [PlayerTile.name_color(c).to_html(false), L10n.seat_name(name)]

## Height of the row including the safe area (for laying out things under it).
func bottom() -> float:
	return safe_top + TOP_GAP + ROW_H


# ---------------------------------------------------------------------------------------------------------------

func _tint(bb: String) -> String:
	if bb == "":
		return ""
	var col: Color = PlayerTile.name_color(_turn) if _turn >= 0 else Palette.INK_STRONG
	return bb.replace("[b]", "[b][color=#%s]" % col.to_html(false)).replace("[/b]", "[/color][/b]")

func _show(bb: String, pop: bool) -> void:
	if bb == _shown and not pop:
		return
	_shown = bb
	if _bar_tw:
		_bar_tw.kill()
	if not is_inside_tree():                 # built before it joined the tree: no animation
		text.text = "[center]" + bb + "[/center]"
		_fit_font()
		bar.modulate.a = 1.0 if bb != "" else 0.0
		_fit_later()
		return
	if bb == "":
		_bar_tw = create_tween()
		_bar_tw.tween_property(bar, "modulate:a", 0.0, 0.2)
		return
	text.text = "[center]" + bb + "[/center]"
	_fit_font()
	_fit_later()
	_bar_tw = create_tween().set_parallel(true)
	_bar_tw.tween_property(bar, "modulate:a", 1.0, 0.12)
	text.modulate.a = 0.0
	_bar_tw.tween_property(text, "modulate:a", 1.0, 0.14)
	if pop and not PlayerTile._pref("reduce_motion"):
		bar.pivot_offset = bar.size / 2.0
		bar.scale = Vector2(1.07, 1.07)
		_bar_tw.tween_property(bar, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if pop:
		_flash = 1.0
		bar.add_theme_stylebox_override("panel", _sb_event)
		_paint_flash()
	else:
		_flash = 0.0
		bar.add_theme_stylebox_override("panel", _sb)

func _paint_flash() -> void:
	_sb_event.bg_color = Palette.GLASS.lerp(Palette.HONEY_TINT, 0.85 * _flash)
	_sb_event.set_border_width_all(1 + int(round(_flash)))
	_sb_event.border_width_bottom = UIKit.LIP.sm
	_sb_event.border_color = Palette.LINE.lerp(Palette.HONEY_LIP, _flash)

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta / 0.9)
		_paint_flash()
	if _msg == "":
		if _flash <= 0.0:
			set_process(false)
		return
	_msg_age += delta
	_msg_left -= delta
	if _msg_left > 0.0:
		return
	_msg = ""
	_msg_kind = ""
	if _pending.size() == 3:
		var p := _pending
		_pending = []
		say(str(p[0]), float(p[1]), str(p[2]))
		return
	_show(_tint(_idle), false)

func _sync_mirror() -> void:
	if not is_instance_valid(info_slot):
		return
	var any := false
	for ch in info_slot.get_children():
		if ch is CanvasItem and (ch as CanvasItem).visible:
			any = true
	info_slot.visible = any
	_mirror.custom_minimum_size.x = info_slot.get_combined_minimum_size().x if any else 0.0
	_mirror.visible = any

func _fit() -> void:
	_fit_queued = false
	_fit_font()
	bar.size = Vector2(bar.size.x, 0)       # shrink back to the text after a longer message
	bar.pivot_offset = bar.size / 2.0

## One line: 16 px, else the largest size down to FS_MIN that fits the bar's width; only a line too long even at
## FS_MIN wraps (two lines of FS_MIN, tight, so the bar keeps ROW_H).
func _fit_font() -> void:
	var plain := text.get_parsed_text().strip_edges()
	var avail := bar.custom_minimum_size.x - _sb.get_margin(SIDE_LEFT) - _sb.get_margin(SIDE_RIGHT) - 4.0
	if is_instance_valid(info_slot) and info_slot.visible:
		avail -= 2.0 * (info_slot.get_combined_minimum_size().x + UIKit.SPACE.xs)
	var f := UIKit.font_body(900)              # the bold weight: names are bold, so measure on the safe side
	var fs: int = UIKit.FS.status
	while fs > FS_MIN and f.get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
		fs -= 1
	var wrap := f.get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail
	text.add_theme_font_size_override("normal_font_size", fs)
	text.add_theme_font_size_override("bold_font_size", fs)
	text.add_theme_constant_override("line_separation", -5 if wrap else -2)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	var pad := 2 if wrap else 6
	if int(_sb.content_margin_top) != pad:
		for sb: StyleBoxFlat in [_sb, _sb_event]:
			sb.content_margin_top = pad
			sb.content_margin_bottom = pad + UIKit.LIP.sm - 1

## The font size the line uses now (tests).
func line_size() -> int:
	return text.get_theme_font_size("normal_font_size")

## True when the line had to wrap (tests).
func wrapped() -> bool:
	return text.autowrap_mode != TextServer.AUTOWRAP_OFF

func _fit_later() -> void:
	if not _fit_queued:
		_fit_queued = true
		_fit.call_deferred()

func _layout() -> void:
	var w := size.x if size.x > 0 else get_viewport_rect().size.x if is_inside_tree() else 390.0
	var g: float = UIKit.SCREEN_GUTTER
	var y := safe_top + TOP_GAP
	custom_minimum_size.y = y + ROW_H
	offset_bottom = offset_top + y + ROW_H     # anchored top-wide: height through the offset
	if left_button:
		left_button.position = Vector2(g, y)
	if gear_button:
		gear_button.position = Vector2(w - g - ROW_H, y)
	var bx := g + ROW_H + UIKit.SPACE.sm
	bar.position = Vector2(bx, y)
	bar.custom_minimum_size = Vector2(maxf(w - 2.0 * bx, 120.0), ROW_H)
	bar.size = Vector2(bar.custom_minimum_size.x, 0)
	bar.pivot_offset = bar.size / 2.0
	_fit_later()                            # the text reflows at the new width a frame later
