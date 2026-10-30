class_name Sheet
extends Control
## A modal sheet: a dimmed backdrop (Palette.SCRIM) and a centred card with a title and (optionally) the 48 px red
## close button on the card's top-right corner, which is then the ONLY dismiss control of the sheet (no Done / Close /
## Got it buttons; a sheet may still have one primary action). Sheets stack; Android's Back and Escape call
## on_back() on the top one (default: close it when dismissable); a tap on the backdrop closes a dismissable sheet.
## Stacking: open() covers the layer's top sheet and close() (or a sheet leaving without it) uncovers the new top. A
## pm sheet shows alone: the one under it fades and shrinks to COVER_SCALE, then hides, and comes back as it was
## (scroll, tab, state). A card dialog (a confirm) sits over the sheet, whose card stays under the dialog's scrim.
## Only the top sheet dims the game (the backdrops crossfade: one SCRIM at every frame) and shows its close button;
## the ones under it are inert.
##
## Looks (index.html):
##   "card"  .card: the cream CARD face, 2 px white border, shadow-lg, the title in Lilita inside the card.
##   "pm"    .pm: cream PM face, 4 px white rim, 3 px orange ring, deep drop shadow, the title in a RibbonTitle on
##           the card's top edge. THE look of every full sheet (Shop, Get coins, Profile, Settings, Daily, Spin,
##           Preview, Credits, Setup); "card" is for the small confirm dialogs.
## set_kicker("Snakes & Ladders") adds an eyebrow (under the ribbon, or above a card title); add_caption() a section
## label (UIKit.caption).
## Usage:
##   var s := Sheet.new("Settings", UIKit.W.form, true, "pm")
##   var list := s.add_scroll_body()        # long content scrolls inside the card
##   list.add_child(...)
##   s.fit()                                # width min(width, screen - 2 x GUTTER), height <= 88% of the screen
##   s.open(layer); await s.closed
##   if await Sheet.confirm(self, "Leave this game?", "This game won't be saved.", "Leave", "Keep playing", true): ...
## Motion: 220 ms back-out pop in, 140 ms fade out; with the Reduce motion setting a short fade only.

signal closed
signal answered(yes: bool)               ## confirm dialogs: emitted once, after the dialog has closed
signal narrow_changed(narrow: bool)      ## the card crossed 340 px (tighter layouts)

const LOOK_CARD := "card"
const LOOK_PM := "pm"
const NARROW_W := 340.0
## Centre of the close button, inset from the card's top-right corner (web .card .x-btn top/right -10 with a 2 px
## border; .pm .x-btn -16 with a 4 px rim: both put it over the corner, about 8 px outside the card).
const CLOSE_INSET := 16.0
## The PM ribbon's top edge above the card (web .pm-title top -24 px inside a 4 px rim).
const RIBBON_TOP := -20.0
## PM: where the content starts below the card's top edge (web .pm padding-top 38 + rim 4).
const PM_CONTENT_TOP := 42.0
## Height of the eyebrow line set_kicker() adds to the header.
const KICKER_H := 18.0
const IN_SEC := 0.22
const OUT_SEC := 0.14
const COVER_SEC := 0.18
const COVER_SCALE := 0.94
## z_index step between stacked sheets: a child's own z (a raised badge) stays under the sheet above.
const Z_STEP := 10

var card: PanelContainer
var body: VBoxContainer
var title_label: Label                   ## CARD: the title label; PM: the ribbon's label (null without a title)
var header: Control                      ## body's first child: holds the title (CARD), the ribbon and the close button
var close_btn: Button                    ## the red X (null when not closable)
var _chrome: Control                     ## the card's top layer holding close_btn
var ribbon: RibbonTitle                  ## PM look with a title
var kicker: Label                        ## set_kicker()'s eyebrow (null until set)
var sheet_look := LOOK_CARD
var dismissable := true                  ## Back, Escape and a backdrop tap close the sheet
var back_action := Callable()            ## when valid, Back calls this instead (e.g. result card -> Home)
var is_narrow := false
var scroll_box: ScrollContainer          ## add_scroll_body()'s scroll area
var scroll_body: VBoxContainer           ## add_scroll_body()'s content
var scroll_hint := false                 ## add_scroll_body(): a round "more below" chevron on the fade while the content
                                         ## goes on below (tap: scroll down). For sheets whose cut can fall between rows
var _clampbox: ClampBox                     # holds body: the card is never wider than fit() says (SH-04)
var backdrop: ColorRect

var _closing := false
var _cover := ""                         # "" on top; "dim" under a card dialog; "hide" under a pm sheet
var _card_tw: Tween                      # the card's pop in, cover or uncover
var _scrim_tw: Tween                     # the backdrop's fade in
var _scrim_by: Sheet                     # the sheet whose fade sets this backdrop now (null: at rest)
var _sheet_w: float = UIKit.W.form
var _fit_on := false                     # fit() was called
var _fit_max := 0.88
var _fit_fixed := 0.0
var _fit_wired := false
var _scroll_wrap: Control
var _fade: TextureRect
var _more_hint: MoreHint
var _center: CenterContainer
var _kb := 0.0                           # logical px of the on-screen keyboard the card is lifted over (0: none)
var _edit: LineEdit                      # the focused LineEdit inside this sheet (null: none)
var _kb_wired := false

## Dev / tests: pretend the on-screen keyboard is this tall (PHYSICAL px, like DisplayServer's); < 0 uses the real one.
static var kb_debug_px := -1.0
const KB_MARGIN := 12.0                  # air kept between the card and the keyboard


func _init(title_text := "", width: float = UIKit.W.form, closable := true, look := LOOK_CARD) -> void:
	sheet_look = LOOK_PM if look == LOOK_PM else LOOK_CARD
	_sheet_w = width
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Palette.SCRIM
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(func(e: InputEvent):
		if dismissable and _is_tap(e):
			close())
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center = center
	add_child(center)
	card = PanelContainer.new()
	card.name = "Card"
	card.add_theme_stylebox_override("panel", _pm_style() if sheet_look == LOOK_PM else _card_style())
	card.custom_minimum_size = Vector2(width, 0)
	center.add_child(card)
	_clampbox = ClampBox.new()
	_clampbox.name = "Clamp"
	card.add_child(_clampbox)
	body = UIKit.vbox(UIKit.SPACE.md)
	_clampbox.add_child(body)
	header = Control.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(header)
	if sheet_look == LOOK_PM:
		# the content starts under the ribbon (PM_CONTENT_TOP from the card's top edge)
		var top := (card.get_theme_stylebox("panel") as StyleBox).content_margin_top
		header.custom_minimum_size.y = maxf(0.0, PM_CONTENT_TOP - top - UIKit.SPACE.md)
		if title_text != "":
			ribbon = RibbonTitle.new(title_text)
			ribbon.name = "Ribbon"
			header.add_child(ribbon)
			title_label = ribbon.label
	else:
		header.custom_minimum_size.y = 40.0 if title_text != "" or closable else 0.0
		if title_text != "":
			title_label = UIKit.title(title_text, UIKit.FS.title)
			title_label.name = "Title"
			title_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			if closable:                      # centred, clear of the close button on both sides
				title_label.offset_left = 30.0
				title_label.offset_right = -30.0
			title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			header.add_child(title_label)
	if closable:
		close_btn = UIKit.close_button()
		close_btn.name = "Close"
		close_btn.tooltip_text = "Close"
		# on its own layer over the card's content, so nothing the sheet adds later (a 3D preview, a grid) draws over
		# the X or takes its taps
		_chrome = Control.new()
		_chrome.name = "Chrome"
		_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(_chrome)
		_chrome.add_child(close_btn)
		close_btn.pressed.connect(close)
	else:
		dismissable = false
	card.sort_children.connect(_place_chrome)
	card.resized.connect(_place_chrome)

static func _is_tap(e: InputEvent) -> bool:
	return (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed)


# =====================================================================================================================
# Card looks
# =====================================================================================================================

## web .card: CARD face, 2 px white border, r 28, shadow-lg, padding 20 (own copy: callers may change it).
static func _card_style() -> StyleBoxFlat:
	return UIKit.surface("card").duplicate() as StyleBoxFlat

## web .pm: PM face, 4 px PM_RIM rim, r 28, a 3 px PM_RING ring outside it, 0 12px 28px rgba(50,25,40,.4).
static func _pm_style() -> StyleBox:
	var s := PMStyle.new()
	s.content_margin_left = UIKit.PAD.pane + 4
	s.content_margin_right = UIKit.PAD.pane + 4
	s.content_margin_top = UIKit.PAD.pane + 4
	s.content_margin_bottom = UIKit.PAD.pane + 4
	return s

## The .pm frame as one StyleBox: the face with its rim and drop shadow, then the orange ring just outside the box.
class PMStyle extends StyleBox:
	var face: StyleBoxFlat
	var ring: StyleBoxFlat

	func _init() -> void:
		face = StyleBoxFlat.new()
		face.bg_color = Palette.PM
		face.set_corner_radius_all(UIKit.R.xl)
		face.set_border_width_all(UIKit.BW.card)
		face.border_color = Palette.PM_RIM
		face.corner_detail = 12
		face.anti_aliasing = true
		face.shadow_color = Color(Palette.SHADOW_DEEP, 0.4)
		face.shadow_size = 14
		face.shadow_offset = Vector2(0, 12)
		ring = StyleBoxFlat.new()
		ring.draw_center = false
		ring.set_border_width_all(UIKit.BW.rim)
		ring.border_color = Palette.PM_RING
		ring.set_corner_radius_all(UIKit.R.xl + UIKit.BW.rim)
		ring.corner_detail = 12
		ring.anti_aliasing = true

	func _draw(to_canvas_item: RID, rect: Rect2) -> void:
		face.draw(to_canvas_item, rect)
		ring.draw(to_canvas_item, rect.grow(UIKit.BW.rim))


# =====================================================================================================================
# Open / close / back
# =====================================================================================================================

## Show the sheet on top of `layer` (the app's sheet layer), covering the sheet that was on top. Coroutine (callers
## may ignore it).
func open(layer: Control) -> Sheet:
	var below := top_sheet(layer)
	card.modulate.a = 0.0                     # nothing shows until the pop starts (no full-size first frame)
	backdrop.modulate.a = 0.0
	_scrim_by = self
	if below:
		below._scrim_by = self                # its backdrop fades out as this one's fades in
	layer.add_child(self)
	tree_exited.connect(_restack.bind(layer), CONNECT_ONE_SHOT)
	_restack(layer)
	if not is_inside_tree():
		card.modulate.a = 1.0
		return self
	await get_tree().process_frame
	if not is_instance_valid(card) or _closing:
		return self
	_place_chrome()
	var reduced := reduce_motion()
	_scrim_tw = create_tween()
	_scrim_tw.tween_method(_scrim_step.bind(below), 0.0, 1.0, 0.12 if reduced else 0.18)
	_scrim_tw.finished.connect(_release.bind(layer))
	if _cover == "hide":
		return self                           # a pm sheet opened over this one in the same frame
	if reduced:
		card.scale = Vector2.ONE
		_card_tw = card.create_tween()
		_card_tw.tween_property(card, "modulate:a", 1.0, 0.12)
	else:
		_card_tw = UIKit.pop_in(card, IN_SEC)
	return self

## Fade the sheet out (140 ms), then emit `closed` and free it. The sheet under it is uncovered at once. Safe to call
## twice.
func close() -> void:
	if _closing:
		return
	var layer := get_parent()
	var was_top := layer != null and top_sheet(layer) == self
	_closing = true
	if close_btn:
		close_btn.visible = false                # the uncovered sheet's X shows at once; two X's never overlap
	var next: Sheet = top_sheet(layer) if was_top else null   # its backdrop takes the scrim over as this one fades
	if next:
		next._scrim_by = self
	for tw: Tween in [_card_tw, _scrim_tw]:
		if tw:
			tw.kill()
	var shield := Control.new()              # swallow taps while fading out (no double "Start game")
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shield)
	if layer:
		_restack(layer)
	if is_inside_tree():
		var tw := create_tween().set_parallel(true)
		tw.tween_method(_out_step.bind(next), 1.0, 0.0, OUT_SEC)
		if not reduce_motion() and is_instance_valid(card):
			card.pivot_offset = card.size / 2
			tw.tween_property(card, "scale", Vector2(0.96, 0.96), OUT_SEC).set_ease(Tween.EASE_IN)
		await tw.finished
	_release(layer)
	closed.emit()
	queue_free()

## Lay `layer` out after a sheet opened, closed or left: the top sheet is uncovered and shows its close button (web
## .pm[inert] > .x-btn: the ones under it hide theirs); each sheet below is covered, "hide" under a pm sheet, else
## "dim". A backdrop no fade is setting rests at full (the top sheet) or at none (the others).
static func _restack(layer: Node) -> void:
	if not is_instance_valid(layer):
		return
	var live := layer.is_inside_tree()
	var stack: Array[Sheet] = []
	for c in layer.get_children():          # (a sheet leaving the tree is still a child while tree_exited runs)
		if c is Sheet and not c.is_queued_for_deletion() and not (c as Sheet)._closing and (c.is_inside_tree() or not live):
			stack.append(c)
	var under_pm := false
	for k in range(stack.size() - 1, -1, -1):
		var s := stack[k]
		var top := k == stack.size() - 1
		s.z_index = k * Z_STEP                   # a stray child z_index can't climb over the sheet above (SH-01)
		s._set_cover("" if top else ("hide" if under_pm else "dim"))
		under_pm = under_pm or s.sheet_look == LOOK_PM
		if s.close_btn:
			s.close_btn.visible = top
		var d := s._scrim_by
		if not (is_instance_valid(d) and d.is_inside_tree() and not d.is_queued_for_deletion()):
			s._scrim_by = null
			s.backdrop.modulate.a = 1.0 if top else 0.0

## Cover ("dim" / "hide") or uncover (""): inert while covered; "hide" fades and shrinks the card, then hides it
## (the backdrop is the scrim handover's), and uncovering brings it back (with Reduce motion a quick fade only).
func _set_cover(mode: String) -> void:
	if mode == _cover:
		return
	var was := _cover
	_cover = mode
	mouse_behavior_recursive = MOUSE_BEHAVIOR_INHERITED if mode == "" else MOUSE_BEHAVIOR_DISABLED
	focus_behavior_recursive = FOCUS_BEHAVIOR_INHERITED if mode == "" else FOCUS_BEHAVIOR_DISABLED
	if mode != "hide" and was != "hide":
		return                                # "" <-> "dim": the card stays as it is
	var hiding := mode == "hide"
	var reduced := reduce_motion()
	if _card_tw:
		_card_tw.kill()
	card.visible = true
	card.pivot_offset = card.size / 2
	var to := Vector2.ONE * (COVER_SCALE if hiding and not reduced else 1.0)
	if not is_inside_tree():
		card.modulate.a = 0.0 if hiding else 1.0
		card.scale = to
		card.visible = not hiding
		return
	if reduced:
		card.scale = Vector2.ONE
	_card_tw = card.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_card_tw.tween_property(card, "modulate:a", 0.0 if hiding else 1.0, 0.1 if reduced else COVER_SEC)
	if not reduced:
		_card_tw.tween_property(card, "scale", to, COVER_SEC)
	if hiding:
		_card_tw.chain().tween_callback(card.hide)

## The open fade's step (x: this backdrop 0 -> 1); the sheet below fades the other way.
func _scrim_step(x: float, below: Sheet) -> void:
	if _scrim_by == self:
		backdrop.modulate.a = x
	if is_instance_valid(below) and below._scrim_by == self:
		below.backdrop.modulate.a = minf(below.backdrop.modulate.a, _partner(x))

## The close fade's step (k: this sheet 1 -> 0); the uncovered sheet's backdrop comes up as this one goes.
func _out_step(k: float, next: Sheet) -> void:
	modulate.a = k
	if is_instance_valid(next) and next._scrim_by == self:
		next.backdrop.modulate.a = maxf(next.backdrop.modulate.a, _partner(k * backdrop.modulate.a))

## The backdrop alpha that, with another one at x over the same game, keeps the dim at one SCRIM:
## 1 - (1 - s a)(1 - s x) = s.
static func _partner(x: float) -> float:
	var s := Palette.SCRIM.a
	return clampf((1.0 - (1.0 - s) / (1.0 - s * x)) / s, 0.0, 1.0)

## This sheet's fade is done: the backdrops it was setting rest (_restack).
func _release(layer: Node) -> void:
	if not is_instance_valid(layer):
		return
	for c in layer.get_children():
		if c is Sheet and (c as Sheet)._scrim_by == self:
			(c as Sheet)._scrim_by = null
	_restack(layer)

## Back / Escape on the top sheet. Default: back_action when set, else close when dismissable. Override for a custom
## Back (call super.on_back() for the default). Returns nothing; the caller has handled Back either way.
func on_back() -> void:
	if _closing:
		return
	if back_action.is_valid():
		back_action.call()
	elif dismissable:
		close()

## The app's Back: on_back() on the top open sheet of `layer`. True when there was one (Back is handled).
static func back(layer: Node) -> bool:
	var top := top_sheet(layer)
	if top == null:
		return false
	top.on_back()
	return true

## The top open (not closing) sheet in `layer`, or null.
static func top_sheet(layer: Node) -> Sheet:
	if layer == null:
		return null
	for k in range(layer.get_child_count() - 1, -1, -1):
		var c := layer.get_child(k)
		if c is Sheet and not c.is_queued_for_deletion() and not (c as Sheet)._closing:
			return c
	return null

## The Reduce motion setting (Save.prefs.reduce_motion; false without the Save autoload).
static func reduce_motion() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var save: Node = tree.root.get_node_or_null("Save") if tree and tree.root else null
	if save == null:
		return false
	var prefs: Variant = save.get("prefs")
	return prefs is Dictionary and bool((prefs as Dictionary).get("reduce_motion", false))


# =====================================================================================================================
# Body helpers
# =====================================================================================================================

## A full-width action button in the sheet body. size: a UIKit.BTN preset ("lg", "md", ...) or (old form) a font
## size int.
func add_button(text: String, kind: String, on_press: Callable, font_size: Variant = 22) -> Button:
	var b := UIKit.button(text, kind, font_size)
	b.pressed.connect(on_press)
	body.add_child(b)
	return b

## A row of buttons sharing the width, [secondary left] [primary right], 12 px apart.
func add_row(buttons: Array) -> HBoxContainer:
	var row := UIKit.hbox(UIKit.SPACE.md)
	for b: Control in buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	body.add_child(row)
	return row

## A section label in the body (UIKit.caption: the one section-label style).
func add_caption(text: String) -> Label:
	var l := UIKit.caption(text)
	body.add_child(l)
	return l

## An eyebrow naming the game or the kind of thing ("SNAKES & LADDERS", "LUDO ROOM"; UIKit.eyebrow, centred).
## PM look: just under the ribbon. Card look: above the title. Call once, after _init; returns the label.
func set_kicker(text: String) -> Label:
	if kicker == null:
		kicker = UIKit.eyebrow(text)
		kicker.name = "Kicker"
		kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kicker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(kicker)
		kicker.set_anchors_preset(Control.PRESET_TOP_WIDE)
		kicker.offset_left = 30.0
		kicker.offset_right = -30.0
		if sheet_look == LOOK_PM:
			# a fixed gap under the ribbon's bottom edge (SPACE.sm), whatever the card's centring
			var top_m := (card.get_theme_stylebox("panel") as StyleBox).content_margin_top
			kicker.offset_top = RIBBON_TOP + RibbonTitle.H + UIKit.SPACE.sm - top_m
			kicker.offset_bottom = kicker.offset_top + KICKER_H
			header.custom_minimum_size.y = maxf(header.custom_minimum_size.y, kicker.offset_bottom)
		else:
			kicker.offset_top = 0.0
			kicker.offset_bottom = KICKER_H
			header.custom_minimum_size.y = maxf(header.custom_minimum_size.y, 40.0) + KICKER_H
			if title_label:
				title_label.offset_top = KICKER_H
	kicker.text = text.to_upper()
	return kicker

## A centred, wrapping line of text.
func add_text(text: String, size := 16) -> Label:
	var l := UIKit.label(text, size, Palette.INK, UIKit.font_body(700), HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(l)
	return l

## A scroll area in the body for long content; returns its VBoxContainer (add the content there). The scrollbar is
## hidden (drag / wheel to scroll); a soft fade at the bottom shows there is more. Turns fit() on: the card grows with
## the content up to max_h of the screen, then the content scrolls. Call once.
func add_scroll_body(gap: int = UIKit.SPACE.md) -> VBoxContainer:
	if scroll_body:
		return scroll_body
	var wrap := MarginContainer.new()
	wrap.name = "ScrollWrap"
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_box = UIKit.scroll()
	scroll_box.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	wrap.add_child(scroll_box)
	scroll_body = UIKit.vbox(gap)
	scroll_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_box.add_child(scroll_body)
	_fade = TextureRect.new()
	_fade.name = "Fade"
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.custom_minimum_size = Vector2(0, 22)
	_fade.size_flags_vertical = Control.SIZE_SHRINK_END
	_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade.stretch_mode = TextureRect.STRETCH_SCALE
	var face := Palette.PM if sheet_look == LOOK_PM else Palette.CARD
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(face, 0.0), face])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 4
	gt.height = 32
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	_fade.texture = gt
	_fade.visible = false
	wrap.add_child(_fade)
	_more_hint = MoreHint.new()
	_more_hint.visible = false
	_more_hint.pressed.connect(func():
		var bar := scroll_box.get_v_scroll_bar()
		var to := minf(bar.max_value - bar.page, bar.value + bar.page * 0.75)
		create_tween().tween_property(scroll_box, "scroll_vertical", int(to), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))
	wrap.add_child(_more_hint)
	_scroll_wrap = wrap
	body.add_child(wrap)
	scroll_box.get_v_scroll_bar().value_changed.connect(func(_v: float): _update_fade())
	scroll_box.get_v_scroll_bar().changed.connect(_update_fade)
	if not _fit_on:
		fit()
	return scroll_body

func _update_fade() -> void:
	if _fade == null or scroll_box == null:
		return
	var bar := scroll_box.get_v_scroll_bar()
	_fade.visible = bar.max_value - bar.page > 1.0 and bar.value < bar.max_value - bar.page - 2.0
	if _more_hint:
		_more_hint.visible = scroll_hint and _fade.visible


## scroll_hint's chip: a small white disc with a down chevron, centred on the scroll area's bottom edge (half of it
## hangs into the gap below, so it covers as little of the content as it can).
class MoreHint extends Button:
	const D := 26.0

	func _init() -> void:
		name = "MoreHint"
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(D + 22.0, D)       # a wider touch area than the disc
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_END
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())

	func _draw() -> void:
		var c := Vector2(size.x / 2.0, size.y)
		draw_circle(c + Vector2(0, 2), D / 2.0, Palette.shadow(0.18), true, -1.0, true)
		draw_circle(c, D / 2.0, Color.WHITE, true, -1.0, true)
		draw_arc(c, D / 2.0 - 1.0, 0.0, TAU, 40, Palette.ROW_EDGE, 2.0, true)
		var k := 4.5
		draw_polyline(PackedVector2Array([c + Vector2(-k, -k * 0.4), c + Vector2(0, k * 0.6), c + Vector2(k, -k * 0.4)]), Palette.SUB, 2.5, true)


## Holds the sheet's body inside the card. Its minimum width is 0 and the body is laid out in the width fit() allows,
## so content with a wide minimum can't stretch the card past the screen gutter (it overflows the card instead, and
## fit_now() warns in debug builds). Height still follows the body.
class ClampBox extends Container:
	var avail_w := 0.0                       ## 0: no clamp yet (the body's own width wins)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func body_min_w() -> float:
		var m := 0.0
		for c in get_children():
			if c is Control and (c as Control).visible:
				m = maxf(m, (c as Control).get_combined_minimum_size().x)
		return m

	func _get_minimum_size() -> Vector2:
		var m := Vector2.ZERO
		for c in get_children():
			if c is Control and (c as Control).visible:
				var cm := (c as Control).get_combined_minimum_size()
				m.y = maxf(m.y, cm.y)
				if avail_w <= 0.0:
					m.x = maxf(m.x, cm.x)
		return m

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			for c in get_children():
				if c is Control and (c as Control).visible:
					fit_child_in_rect(c, Rect2(Vector2.ZERO, size))


# =====================================================================================================================
# Fitting to the screen (replaces the per-sheet _fit copies)
# =====================================================================================================================

## Keep the card on screen, now and on every resize: width min(width, screen - 2 x GUTTER) (narrow below 340 px);
## with add_scroll_body(), the scroll area shows all its content unless the card would pass max_h of the screen
## height, then the content scrolls. fixed_px > 0: the card is always min(fixed_px, max_h of the screen) tall
## whatever the content (Shop: one size for every tab). Sheets without fit() still get the width rule unless they
## have their own _fit().
func fit(max_h := 0.88, fixed_px := 0.0) -> void:
	_fit_on = true
	_fit_max = max_h
	_fit_fixed = fixed_px
	if is_inside_tree():
		_wire_fit()
		fit_now()

## Re-fit now (after the content changed in a way the signals don't see).
func fit_now() -> void:
	if not is_inside_tree() or card == null:
		return
	var vp := get_viewport_rect().size
	var w := minf(_sheet_w, vp.x - 2.0 * UIKit.GUTTER)
	if absf(card.custom_minimum_size.x - w) > 0.5:
		card.custom_minimum_size.x = w
	if absf(_clampbox.avail_w - (w - _card_pad_x())) > 0.5:
		_clampbox.avail_w = w - _card_pad_x()
		_clampbox.update_minimum_size()
	# flip is_narrow first: the narrow_changed layouts are what the width check below must measure
	var nar := w < NARROW_W
	if nar != is_narrow:
		is_narrow = nar
		if sheet_look == LOOK_CARD and title_label and title_label.get_parent() == header:
			title_label.add_theme_font_size_override("font_size", UIKit.FS.title_sm if nar else UIKit.FS.title)
		narrow_changed.emit(nar)
	if OS.is_debug_build() and not has_meta("_warned_wide"):
		_check_wide.call_deferred()          # after the frame's rebuilds settle: only real overflow warns
	if _fit_on and scroll_box:
		var cap := vp.y * _fit_max
		if _kb > 0.0:                           # the keyboard is up: what is left above it (the buttons stay in view)
			cap = minf(cap, vp.y - _kb - _safe_top() - KB_MARGIN * 2.0)
		if sheet_look == LOOK_PM and ribbon:
			cap += RIBBON_TOP                   # the ribbon stands above the card
		var other := card.get_combined_minimum_size().y - _scroll_wrap.get_combined_minimum_size().y
		var h: float
		if _fit_fixed > 0.0:
			h = minf(_fit_fixed, cap) - other
		else:
			h = minf(scroll_body.get_combined_minimum_size().y, cap - other)
		h = maxf(h, 120.0)
		if absf(scroll_box.custom_minimum_size.y - h) > 0.5:
			scroll_box.custom_minimum_size.y = h
		_update_fade.call_deferred()

## Debug: warn once when the body's minimum width is wider than the card allows (it overflows the card).
func _check_wide() -> void:
	if not is_inside_tree() or card == null or has_meta("_warned_wide"):
		return
	var w := minf(_sheet_w, get_viewport_rect().size.x - 2.0 * UIKit.GUTTER)
	var want := _clampbox.body_min_w() + _card_pad_x()
	if want > w + 0.5:
		set_meta("_warned_wide", true)
		push_warning("Sheet %s: content wants %d px but the card is held to %d px" % [get_script().resource_path.get_file(), int(want), int(w)])

## The card's left + right content margins.
func _card_pad_x() -> float:
	var st := card.get_theme_stylebox("panel")
	return st.content_margin_left + st.content_margin_right

func _wire_fit() -> void:
	if _fit_wired:
		return
	_fit_wired = true
	get_viewport().size_changed.connect(fit_now)
	if scroll_body:
		scroll_body.minimum_size_changed.connect(fit_now)
	card.minimum_size_changed.connect(fit_now)

func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		_wire_keyboard()
		if _fit_on or not has_method("_fit"):
			_wire_fit()
			fit_now()

## HowToSheet.fit_card with the GUTTER rule (forwarder for the sheets that still fit themselves): width min(width,
## screen - 2 x GUTTER); the scroll area shows all of `inner` unless the card would pass 88% of the screen height.
static func fit_card(c: Control, sc: ScrollContainer, inner: Control, width: float, vp: Vector2) -> void:
	c.custom_minimum_size.x = minf(width, vp.x - 2.0 * UIKit.GUTTER)
	var want := inner.get_combined_minimum_size().y
	var other := c.get_combined_minimum_size().y - sc.get_combined_minimum_size().y
	var h := minf(want, maxf(160.0, vp.y * 0.88 - other))
	if absf(sc.custom_minimum_size.y - h) > 0.5:
		sc.custom_minimum_size.y = h


# =====================================================================================================================
# On-screen keyboard (one approach for every sheet with a LineEdit; Welcome uses keyboard_inset() too)
# =====================================================================================================================

## The keyboard's height in the viewport's logical px (the window's physical px scaled by viewport / window height); 0
## when it is not showing. kb_debug_px stands in for it in dev runs and tests.
static func keyboard_inset(view_h: float) -> float:
	var px := kb_debug_px
	if px < 0.0:
		if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
			return 0.0
		px = float(DisplayServer.virtual_keyboard_get_height())
	var win := DisplayServer.window_get_size()
	if px <= 0.0 or win.y <= 0:
		return 0.0
	return px * view_h / float(win.y)

func _wire_keyboard() -> void:
	if _kb_wired or not is_inside_tree():
		return
	_kb_wired = true
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	tree_exiting.connect(func():
		if _edit and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
			DisplayServer.virtual_keyboard_hide())
	_on_focus_changed(get_viewport().gui_get_focus_owner())

func _on_focus_changed(n: Control) -> void:
	var e := n as LineEdit
	if e != null and not is_ancestor_of(e):
		e = null
	if e == _edit:
		return
	_edit = e
	var tick := get_tree().process_frame
	if e:
		if not e.has_meta("_kb_next"):          # Enter / Done: on to the next field, from the last one close the keyboard
			e.set_meta("_kb_next", true)
			e.keep_editing_on_text_submit = true
			e.text_submitted.connect(func(_t: String): _next_field(e))
		if not tick.is_connected(_kb_tick):
			tick.connect(_kb_tick)
		_kb_scroll_to(e)
	elif tick.is_connected(_kb_tick):
		tick.disconnect(_kb_tick)
		_kb_apply(0.0)

## The next visible LineEdit after e in the sheet (tree order), or release focus and hide the keyboard.
func _next_field(e: LineEdit) -> void:
	var all: Array[LineEdit] = []
	_collect_edits(card, all)
	var i := all.find(e)
	if i >= 0 and i + 1 < all.size():
		all[i + 1].grab_focus()
		return
	e.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()

func _collect_edits(n: Node, out: Array[LineEdit]) -> void:
	for c in n.get_children():
		if c is LineEdit and (c as LineEdit).is_visible_in_tree() and (c as LineEdit).editable:
			out.append(c)
		else:
			_collect_edits(c, out)

func _kb_tick() -> void:
	_kb_apply(keyboard_inset(get_viewport_rect().size.y) if _edit else 0.0)

## Lift the card over the keyboard kb px tall: the card area ends above it, fit_now() shrinks the scroll body to what
## is left (the primary buttons under it stay on screen) and the focused field is scrolled into view.
func _kb_apply(kb: float) -> void:
	if absf(kb - _kb) <= 1.0:
		return
	_kb = kb
	_center.offset_bottom = -kb
	_center.offset_top = _safe_top() if kb > 0.0 else 0.0     # the card stays under the status bar
	fit_now()
	if _edit:
		_kb_scroll_to(_edit)

## The top safe-area inset (Main.safe_top), found up the tree; 0 when there is none.
func _safe_top() -> float:
	var n := get_parent()
	while n:
		if "safe_top" in n:
			return float(n.get("safe_top"))
		n = n.get_parent()
	return 0.0

func _kb_scroll_to(e: Control) -> void:
	if scroll_box == null or not scroll_box.is_ancestor_of(e):
		return
	for k in 2:                                 # after the card has been resized
		await get_tree().process_frame
		if not is_instance_valid(e) or not e.has_focus() or not is_inside_tree():
			return
		scroll_box.ensure_control_visible(e)


# =====================================================================================================================
# The close button and the ribbon, placed against the card's corner / top edge
# =====================================================================================================================

func _place_chrome() -> void:
	if card == null or header == null:
		return
	var origin := _clampbox.position + body.position + header.position      # the header's top-left in card space
	if close_btn:
		var s := close_btn.size
		close_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
		close_btn.position = Vector2(card.size.x - CLOSE_INSET, CLOSE_INSET) - s / 2.0 - close_btn.get_parent().position
		if _chrome and _chrome.get_index() != card.get_child_count() - 1:
			card.move_child(_chrome, -1)          # stays the card's last child
	if ribbon:
		ribbon.fit_to(card.size.x)
		ribbon.position = Vector2((card.size.x - ribbon.size.x) / 2.0, RIBBON_TOP) - origin


# =====================================================================================================================
# Confirm dialog (replaces "Tap again to ..." and the quit sheet)
# =====================================================================================================================

## A small decision dialog (CARD look, UIKit.W.dialog wide, no close button): title, text, [no] [yes]. no is the
## ghost button, yes honey (red when danger). Back, Escape and a backdrop tap answer no. Coroutine: returns the
## choice once the dialog has closed.
##   if await Sheet.confirm(self, "Restart this game?", "Everyone goes back to the start.", "Restart", "Keep playing"):
## host: any node of the app; the dialog opens on the app's sheet layer (Main.sheet_layer), else on host (a
## Control) or the root's first Control.
static func confirm(host: Node, title_text: String, text: String, yes: String, no := "Cancel", danger := false) -> bool:
	var s := make_confirm(title_text, text, yes, no, danger)
	var layer := _layer_for(host)
	if layer == null:
		s.free()
		return false
	s.open(layer)
	var v: bool = await s.answered
	return v

## The confirm dialog itself, not opened yet (previews; Sheet.confirm opens it and waits).
static func make_confirm(title_text: String, text: String, yes: String, no := "Cancel", danger := false) -> Sheet:
	var s := Sheet.new(title_text, UIKit.W.dialog, false)
	s.dismissable = true
	s.set_meta("confirm", true)
	s.body.add_theme_constant_override("separation", UIKit.SPACE.lg)
	if title_text != "":
		s.header.custom_minimum_size.y = 36.0
	if text != "":
		var l := UIKit.paragraph(text, UIKit.FS.body_l, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		s.body.add_child(l)
	var state := {value = false, done = false}
	var nb := UIKit.btn(no, "ghost", "md")
	nb.name = "No"
	var yb := UIKit.btn(yes, "red" if danger else "honey", "md")
	yb.name = "Yes"
	for b: Button in [nb, yb]:
		UIKit.fit_text(b, 14)
	nb.pressed.connect(func():
		state.value = false
		s.close())
	yb.pressed.connect(func():
		state.value = true
		s.close())
	s.add_row([nb, yb])
	var finish := func() -> void:
		if not state.done:
			state.done = true
			s.answered.emit(bool(state.value))
	s.closed.connect(finish)
	s.tree_exiting.connect(func():               # removed without closing (close_all_sheets): answer no
		if not state.done:
			state.value = state.value if s._closing else false
			finish.call())
	return s

static func _layer_for(host: Node) -> Control:
	var tree := (host.get_tree() if host and host.is_inside_tree() else Engine.get_main_loop()) as SceneTree
	if tree == null:
		return null
	var app := tree.root.get_node_or_null("Main")
	if app == null:
		app = tree.root.find_child("Main", true, false)
	if app and "sheet_layer" in app and app.sheet_layer is Control:
		return app.sheet_layer
	if host is Control:
		return host
	for c in tree.root.get_children():
		if c is Control:
			return c
	return null
