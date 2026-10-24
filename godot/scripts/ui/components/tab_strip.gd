class_name TabStrip
extends Control
## The one tab row of the interface, drawn in code. Two looks:
##   "gtabs"  web .gtabs: flat category tabs with rounded tops on a 2 px TAB baseline. Inactive tabs are TAB beige;
##            the active one takes its Palette.CAT colour, stands taller and has a 3 px darker bar at its foot.
##            Up to 4 tabs show the icon beside the label; when the labels don't fit (5-7 tabs on a phone) the icon
##            goes above a smaller label (14 -> 12 px); if even that doesn't fit, the strip scrolls sideways (drag).
##   "folder" web .ftabs: folder tabs with a 3 px PANE_EDGE outline joined to the pane below (pane_style("folder")).
##            The active tab is PANE cream and opens into the pane, the others are tan and stop above its top line.
## Every tab shows an icon AND a label (no icon-only tabs). A red count badge can sit on any tab (set_count).
## The whole strip height is the touch target (>= 48 px); taps give UIKit.press_fx feedback.
##
##   var tabs := TabStrip.new([{key = "rooms", text = "Rooms", cat = "rooms"}, ...], "rooms")
##   tabs.picked.connect(show_tab)
##   pane.add_theme_stylebox_override("panel", TabStrip.pane_style("folder"))
##
## items: [{key: String, text: String, icon: String (assets/ui name or res:// path) or Texture2D (optional,
## default "cat_<cat>" / "cat_<key>"), cat: String (a Palette.CAT key; gtabs colour, default = key)}].

## Emitted when the player taps a tab that is not the selected one (after it became selected).
signal picked(key: String)

const GAP := 6.0                     ## gtabs gap between tabs
const MAX_W := 132.0                 ## gtabs maximum tab width (web max-width)
const H_ON := 52.0                   ## gtabs active tab height (= strip height)
const H_OFF := 42.0                  ## gtabs inactive tab height (stops above the baseline)
const BASE := 2.0                    ## gtabs baseline
const BAR := 3.0                     ## gtabs active colour bar
const RADIUS := 14
const F_GAP := 8.0                   ## folder gap between tabs
const F_H := 48.0                    ## folder strip height (active tab height)
const F_OFF_TOP := 8.0               ## folder inactive tabs start this far down
const F_EDGE := 3.0                  ## folder outline width (= the pane's border)
const DRAG := 8.0                    ## px a press must move before it scrolls instead of tapping

var look := "gtabs"
var items: Array = []
var selected := ""
var sound := "select"                ## the press_fx sound when a tab is picked ("" = haptic only)
var fade_color := Palette.CARD       ## gtabs: the surface behind the strip (the scroll-edge fade blends into it)

var _tex: Array = []                 # Texture2D per item (or null)
var _counts := {}
var _press := -1
var _press_x := 0.0
var _scroll := 0.0
var _scroll0 := 0.0
var _dragging := false
# layout cache (rebuilt when the size or the items change)
var _lay_w := -1.0
var _rects: Array = []               # Rect2 per tab, in content space (before the scroll offset)
var _column := false                 # gtabs: icon above the label
var _fs := 15
var _ic := 22.0
var _content_w := 0.0
var _shown_once := false


func _init(items_: Array = [], selected_ := "", look_ := "gtabs") -> void:
	look = look_ if look_ in ["gtabs", "folder"] else "gtabs"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = look == "gtabs"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	custom_minimum_size = Vector2(0, H_ON if look == "gtabs" else F_H)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_items(items_, selected_)


## Replace the tabs (keeps the counts of keys that remain). selected_ "" keeps the current selection if it exists.
func set_items(items_: Array, selected_ := "") -> void:
	items = items_
	_tex.clear()
	for it in items:
		_tex.append(_icon_for(it))
	var keys := keys()
	if selected_ != "":
		selected = selected_
	if not keys.has(selected):
		selected = str(keys[0]) if keys.size() else ""
	_lay_w = -1.0
	queue_redraw()


## Select a tab without emitting picked (e.g. when a sheet opens on a tab). Scrolls it into view.
func select(key: String) -> void:
	if not keys().has(key):
		return
	selected = key
	_layout()
	_scroll_into_view(_index(key))
	queue_redraw()


## Show a red count badge on a tab (n <= 0 hides it). 99+ for big counts.
func set_count(key: String, n: int) -> void:
	_counts[key] = n
	queue_redraw()


func get_count(key: String) -> int:
	return int(_counts.get(key, 0))


## The tab keys in order.
func keys() -> Array:
	return items.map(func(it: Dictionary) -> String: return str(it.get("key", "")))


## True when the gtabs labels don't fit and the strip scrolls sideways.
func scrolls() -> bool:
	_layout()
	return _content_w > size.x + 0.5


## The style of the pane under the tabs: "folder" -> the .pm-inner pane with an open top (PANE, 3 px PANE_EDGE,
## rounded bottom; the strip draws its top line); "gtabs" -> web .gtray, no frame, 12 px above / 14 px below.
## A fresh copy: change its margins freely.
static func pane_style(look_ := "gtabs") -> StyleBox:
	if look_ == "folder":
		return UIKit.surface("pane_open_top").duplicate()
	var e := StyleBoxEmpty.new()
	e.content_margin_top = UIKit.SPACE.md
	e.content_margin_bottom = 14
	return e


## The colour pair [face, bar] of an item (Palette.CAT, honey for unknown categories).
static func cat_colors(it: Dictionary) -> Array:
	var cat := str(it.get("cat", it.get("key", "")))
	return Palette.CAT.get(cat, Palette.CAT.coins)


# ---------------------------------------------------------------------------------------------------------------------

func _icon_for(it: Dictionary) -> Texture2D:
	var ic: Variant = it.get("icon", null)
	if ic is Texture2D:
		return ic
	var names: Array = []
	if ic is String and ic != "":
		names.append(ic)
	names.append("cat_" + str(it.get("cat", "")))
	names.append("cat_" + str(it.get("key", "")))
	for n: String in names:
		var path := n if n.begins_with("res://") else UIKit.ICON_DIR + n + ".svg"
		if ResourceLoader.exists(path):
			return UIKit.svg(path)
	push_warning("TabStrip: no icon for tab %s" % it.get("key", "?"))
	return null


func _index(key: String) -> int:
	return keys().find(key)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_lay_w = -1.0
		_layout()
		if not _shown_once and size.x > 0.0:
			_shown_once = true
			_scroll_into_view(_index(selected))       # a sheet opening on a later tab shows it
		_clamp_scroll()
		queue_redraw()


func _label_w(t: String, fs: int) -> float:
	return UIKit.font_display().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _layout() -> void:
	if is_equal_approx(_lay_w, size.x) and _rects.size() == items.size():
		return
	_lay_w = size.x
	_rects.clear()
	var n := items.size()
	if n == 0:
		_content_w = 0.0
		return
	if look == "folder":
		var fw := (size.x - F_GAP * (n - 1)) / n
		_fs = 17 if size.x >= 300.0 else 15
		_ic = 20.0
		# labels shrink (to 13) before they would overflow a narrow tab
		var widest := 0.0
		for it in items:
			widest = maxf(widest, _label_w(str(it.get("text", "")), _fs))
		while _fs > 13 and _ic + 6.0 + widest + 20.0 > fw:
			_fs -= 1
			widest = 0.0
			for it in items:
				widest = maxf(widest, _label_w(str(it.get("text", "")), _fs))
		for i in n:
			var on: bool = str(items[i].get("key", "")) == selected
			_rects.append(Rect2(i * (fw + F_GAP), 0.0 if on else F_OFF_TOP, fw, F_H if on else F_H - F_OFF_TOP - F_EDGE))
		_content_w = size.x
		return
	var w := minf(MAX_W, (size.x - GAP * (n - 1)) / n)
	# 1) icon beside a 15 px label (web .gtabs)
	_column = false
	_fs = 15
	_ic = 22.0 if w >= 80.0 else 20.0
	var fits := true
	for it in items:
		if _ic + 5.0 + _label_w(str(it.get("text", "")), _fs) + 10.0 > w:
			fits = false
			break
	# 2) icon above a 14..12 px label (web .gtabs.four on phones)
	if not fits:
		_column = true
		_ic = 20.0
		for fs in [14, 13, 12]:
			_fs = fs
			fits = true
			for it in items:
				if _label_w(str(it.get("text", "")), fs) + 6.0 > w:
					fits = false
					break
			if fits:
				break
	# 3) still too long: every tab gets the width of the longest label and the strip scrolls
	if not fits:
		var need := 0.0
		for it in items:
			need = maxf(need, _label_w(str(it.get("text", "")), _fs) + 12.0)
		w = need
	for i in n:
		_rects.append(Rect2(i * (w + GAP), 0.0, w, H_ON))
	_content_w = n * w + GAP * (n - 1)
	_clamp_scroll()


func _clamp_scroll() -> void:
	_scroll = clampf(_scroll, 0.0, maxf(0.0, _content_w - size.x))


func _scroll_into_view(i: int) -> void:
	if i < 0 or i >= _rects.size() or _content_w <= size.x:
		return
	var r: Rect2 = _rects[i]
	if r.position.x - _scroll < 0.0:
		_scroll = r.position.x - GAP
	elif r.end.x - _scroll > size.x:
		_scroll = r.end.x - size.x + GAP
	_clamp_scroll()


func _draw() -> void:
	_layout()
	if look == "folder":
		_draw_folder()
	else:
		_draw_gtabs()


func _draw_gtabs() -> void:
	draw_rect(Rect2(0, size.y - BASE, size.x, BASE), Palette.TAB)
	var font := UIKit.font_display()
	for i in items.size():
		var it: Dictionary = items[i]
		var on: bool = str(it.get("key", "")) == selected
		var full: Rect2 = _rects[i]
		var h := H_ON if on else H_OFF
		var r := Rect2(full.position.x - _scroll, size.y - (h if on else h + BASE), full.size.x, h)
		if r.end.x < 0.0 or r.position.x > size.x:
			continue
		var pressed := _press == i and not _dragging
		if pressed and not on:
			r.position.y += 1.0
		var cc := cat_colors(it)
		var face: Color = cc[0] if on else (Palette.TAB_HOVER if pressed else Palette.TAB)
		var st := _top_box(face, RADIUS)
		draw_style_box(st, r)
		if on:
			draw_rect(Rect2(r.position.x, r.end.y - BAR, r.size.x, BAR), cc[1])
		var text := str(it.get("text", ""))
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
		var tex: Texture2D = _tex[i]
		var inner := Rect2(r.position, Vector2(r.size.x, r.size.y - (BAR if on else 0.0)))
		if _column:
			var block := _ic + 2.0 + _fs * 0.9
			var top := inner.position.y + (inner.size.y - block) / 2.0
			if tex:
				draw_texture_rect(tex, Rect2(inner.get_center().x - _ic / 2.0, top, _ic, _ic), false)
			var tx := inner.position.x + (inner.size.x - minf(tw, inner.size.x - 4.0)) / 2.0
			draw_string(font, Vector2(tx, top + _ic + 2.0 + _fs * 0.8), text, HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 4.0, _fs, Palette.INK_DEEP, TextServer.JUSTIFICATION_NONE)
		else:
			var total := _ic + 5.0 + tw
			var cx := inner.position.x + (inner.size.x - total) / 2.0
			var cy := inner.get_center().y
			if tex:
				draw_texture_rect(tex, Rect2(cx, cy - _ic / 2.0, _ic, _ic), false)
			draw_string(font, Vector2(cx + _ic + 5.0, cy + _fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, Palette.INK_DEEP)
		_draw_count(str(it.get("key", "")), Vector2(r.end.x - 10.0, maxf(r.position.y + 1.0, 10.0)))
	# scroll hints: a soft fade at an edge with more tabs behind it
	if _content_w > size.x + 0.5:
		var fw := 22.0
		if _scroll < _content_w - size.x - 0.5:
			_fade(Rect2(size.x - fw, 0, fw, size.y - BASE), false)
		if _scroll > 0.5:
			_fade(Rect2(0, 0, fw, size.y - BASE), true)


func _fade(r: Rect2, left: bool) -> void:
	var c0 := Color(fade_color, 0.0)
	var c1 := Color(fade_color, 0.95)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var a := c1 if left else c0
	var b := c0 if left else c1
	draw_polygon(pts, PackedColorArray([a, b, b, a]))


func _draw_folder() -> void:
	draw_rect(Rect2(0, size.y - F_EDGE, size.x, F_EDGE), Palette.PANE_EDGE)       # the pane's top line
	var font := UIKit.font_display()
	for i in items.size():
		var it: Dictionary = items[i]
		var on: bool = str(it.get("key", "")) == selected
		var r: Rect2 = _rects[i]
		r = Rect2(r.position.x, size.y - F_H + (0.0 if on else F_OFF_TOP), r.size.x, F_H if on else F_H - F_OFF_TOP - F_EDGE)
		var pressed := _press == i and not on
		if pressed:
			r.position.y += 1.0
			r.size.y -= 1.0
		var st := _top_box(Palette.PANE if on else (Palette.TAB_HOVER if pressed else Palette.LINE_SOLID), 16)
		st.border_color = Palette.PANE_EDGE
		st.border_width_left = int(F_EDGE); st.border_width_right = int(F_EDGE); st.border_width_top = int(F_EDGE)
		draw_style_box(st, r)
		var text := str(it.get("text", ""))
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
		var tex: Texture2D = _tex[i]
		var total := (_ic + 6.0 if tex else 0.0) + tw
		var cx := r.position.x + (r.size.x - total) / 2.0
		var cy := r.position.y + F_EDGE + (r.size.y - F_EDGE) / 2.0
		var col := Palette.INK if on else Palette.SUB
		if tex:
			draw_texture_rect(tex, Rect2(cx, cy - _ic / 2.0, _ic, _ic), false, Color(1, 1, 1, 1.0 if on else 0.75))
			cx += _ic + 6.0
		draw_string(font, Vector2(cx, cy + _fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, col)
		_draw_count(str(it.get("key", "")), Vector2(r.end.x - 14.0, r.position.y + 2.0))


func _top_box(face: Color, radius: int) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = face
	st.corner_radius_top_left = radius
	st.corner_radius_top_right = radius
	st.corner_detail = 10
	st.anti_aliasing = true
	return st


func _draw_count(key: String, c: Vector2) -> void:
	var n := int(_counts.get(key, 0))
	if n <= 0:
		return
	var t := "99+" if n > 99 else str(n)
	var nf := UIKit.font_body(900, true)
	var tw := nf.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.FS.small).x
	var w := maxf(18.0, tw + 8.0)
	var r := Rect2(c.x - w / 2.0, c.y - 9.0, w, 18.0)
	var st := UIKit.box(Palette.RED, UIKit.R.pill, UIKit.BW.line, Color.WHITE)
	st.shadow_size = 2; st.shadow_offset = Vector2(0, 1); st.shadow_color = Color(Palette.INK, 0.25)
	draw_style_box(st, r.grow(1.0))
	draw_string(nf, Vector2(c.x - tw / 2.0, c.y + 4.3), t, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.FS.small, Color.WHITE)


func _hit(p: Vector2) -> int:
	_layout()
	for i in _rects.size():
		var r: Rect2 = _rects[i]
		var x0 := r.position.x - (_scroll if look == "gtabs" else 0.0)
		var half_gap := (GAP if look == "gtabs" else F_GAP) / 2.0
		if p.x >= x0 - half_gap and p.x < x0 + r.size.x + half_gap and p.y >= 0.0 and p.y <= size.y:
			return i
	return -1


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouse and (e as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return                                   # touches arrive as ScreenTouch / ScreenDrag; skip the mouse copies
	var down := false
	var up := false
	var pos := Vector2.ZERO
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		down = e.pressed; up = not e.pressed; pos = e.position
	elif e is InputEventScreenTouch:
		down = e.pressed; up = not e.pressed; pos = e.position
	elif (e is InputEventScreenDrag or (e is InputEventMouseMotion and (e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT)) and _press >= 0:
		var dx: float = e.position.x - _press_x
		if not _dragging and absf(dx) > DRAG and scrolls():
			_dragging = true
		if _dragging:
			_scroll = _scroll0 - dx
			_clamp_scroll()
			queue_redraw()
		accept_event()
		return
	if down:
		_press = _hit(pos)
		_press_x = pos.x
		_scroll0 = _scroll
		_dragging = false
		queue_redraw()
		accept_event()
	elif up:
		var i := _hit(pos)
		if not _dragging and i >= 0 and i == _press:
			var key := str(items[i].get("key", ""))
			if key != selected:
				UIKit.press_fx(sound)
				selected = key
				_lay_w = -1.0
				_layout()
				_scroll_into_view(i)
				picked.emit(key)
		_press = -1
		_dragging = false
		queue_redraw()
		accept_event()


## Test / automation hook: act as if the player tapped tab `key` (emits picked when it changes the selection).
func tap(key: String) -> void:
	var i := _index(key)
	if i < 0 or key == selected:
		return
	selected = key
	_lay_w = -1.0
	_layout()
	_scroll_into_view(i)
	queue_redraw()
	picked.emit(key)
