class_name Toast
extends RefCounted
## The one toast of the interface (web .toast): a plum pill (Palette.TOAST, radius pill, shadow) with white
## Nunito 900 16 px text, centred, wrapping to at most the screen width - 32. Optional icon by kind:
##   "info" no icon   "good" a teal disc with a white check   "bad" a red disc with "!"   "coin" the coin   "gem" the gem
## Placement: above the bottom safe area (safe bottom + 104 px, like the web), or - with `near` - just under that
## control (a sheet card), or over its bottom edge when there's no room below.
## One at a time: a new toast replaces the one showing. It pops in (150 ms), holds `sec`, fades out (250 ms) and
## frees itself. Taps go through it.
## It floats over every sheet: the pill lives in its own CanvasLayer ("ToastLayer", layer 110) in the host's viewport,
## above the UI root's CanvasLayer (the info bubble, 120, stays above it).
##
##   Toast.show(self, "Pastel Dream Room is yours!", card, 1.8, "good")
##   Toast.show_above(self, "Free coins in 3h 3m", free_button)     # over a control (never over the buttons under it)

const LAYER := 110
const BOTTOM := 104.0                ## gap between the toast's bottom edge and the bottom safe area (web)
const EDGE := 16.0                   ## minimum gap to the screen sides
const MAX_W := 360.0
const FS := 16
const ICON := 22.0
const GESTURE_DP := 20.0             ## minimum bottom inset on mobile (the Android gesture swipe zone), in dp


## Show a toast. host: any node in the tree (its viewport hosts the toast). Returns the pill (a PanelContainer),
## or null when host isn't in a tree. The pill is placed (and sized) one frame later, so it's safe to call from
## _ready().
static func show(host: Node, text: String, near: Control = null, sec := 1.8, kind := "info") -> Control:
	if host == null or not host.is_inside_tree():
		return null
	var vp := host.get_viewport()
	var root := _layer_root(vp)
	var pill := PanelContainer.new()
	pill.name = "Toast"
	pill.set_meta("toast", true)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", UIKit.surface("toast"))
	pill.modulate.a = 0.0
	var row := UIKit.hbox(UIKit.SPACE.sm)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := _icon(kind)
	if ic:
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var l := UIKit.label("", FS, Color.WHITE, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Text"
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var size := vp.get_visible_rect().size
	var max_w := minf(MAX_W, size.x - 2.0 * EDGE)
	var room := max_w - 36.0 - ((ICON + UIKit.SPACE.sm) if ic else 0.0)
	l.text = wrap_text(text, l.get_theme_font("font"), FS, room)
	row.add_child(l)
	pill.add_child(row)
	root.set_meta("latest", pill)
	_attach.call_deferred(root, pill, near, sec)
	return pill


## Show a toast just ABOVE `above` (centred on it), e.g. over the lobby's feature tiles so it never covers the play
## buttons below them. Falls back to the default bottom placement when `above` isn't on screen.
static func show_above(host: Node, text: String, above: Control, sec := 1.8, kind := "info") -> Control:
	var pill := show(host, text, null, sec, kind)
	if pill and is_instance_valid(above):
		pill.set_meta("above", above)
	return pill


## Remove the toast showing in host's viewport (e.g. when the screen changes).
static func clear(host: Node) -> void:
	if host == null or not host.is_inside_tree():
		return
	var layer := _layer(host)
	if layer == null:
		return
	for c in layer.get_child(0).get_children():
		if c.has_meta("toast"):
			c.queue_free()


## The pill showing in host's viewport, or null.
static func current(host: Node) -> Control:
	if host == null or not host.is_inside_tree():
		return null
	var layer := _layer(host)
	if layer == null:
		return null
	for c in layer.get_child(0).get_children():
		if c.has_meta("toast") and not c.is_queued_for_deletion():
			return c
	return null


## The top / bottom safe insets in UI px [top = notch / cutout, bottom = gesture bar]; 0 off mobile. The game runs
## in immersive mode, so Android reports no bottom inset although the bottom edge is still a swipe zone: the bottom
## keeps at least GESTURE_DP (in dp, converted through the screen dpi). Same rule as main.gd insets(); debug builds
## honour the same `-- --safe=TOP,BOTTOM` override (UI px).
static func safe_insets(vp: Viewport) -> Vector2:
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--safe="):
				var p := a.trim_prefix("--safe=").split(",")
				return Vector2(float(p[0]), float(p[1]) if p.size() > 1 else 0.0)
	if not OS.has_feature("mobile"):
		return Vector2.ZERO
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return Vector2.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var k := vp.get_visible_rect().size.y / float(win.y)
	var top := maxf(0.0, float(safe.position.y)) * k if safe.size.y > 0 else 0.0
	var bottom := maxf(0.0, float(win.y - safe.end.y)) * k if safe.size.y > 0 else 0.0
	var px_per_dp := maxf(1.0, DisplayServer.screen_get_dpi() / 160.0)
	return Vector2(top, maxf(bottom, GESTURE_DP * px_per_dp * k))


## Greedy word wrap with explicit line breaks (an autowrap Label has no reliable size before its first layout).
static func wrap_text(text: String, font: Font, fs: int, max_w: float) -> String:
	var out: PackedStringArray = []
	for para in text.split("\n"):
		var cur := ""
		for word in para.split(" "):
			var t := word if cur == "" else cur + " " + word
			if cur != "" and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
				out.append(cur)
				cur = word
			else:
				cur = t
		out.append(cur)
	return "\n".join(out)


# ---------------------------------------------------------------------------------------------------------------------

static func _layer(host: Node) -> CanvasLayer:
	var vp := host.get_viewport()
	var layer: Variant = vp.get_meta("toast_layer") if vp.has_meta("toast_layer") else null
	return layer if is_instance_valid(layer) and layer is CanvasLayer else null


static func _layer_root(vp: Viewport) -> Control:
	var found: Variant = vp.get_meta("toast_layer") if vp.has_meta("toast_layer") else null
	var layer: CanvasLayer = found if is_instance_valid(found) and found is CanvasLayer else null
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "ToastLayer"
		layer.layer = LAYER
		var root := Control.new()
		root.name = "Root"
		root.theme = UIKit.theme()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(root)
		vp.add_child.call_deferred(layer)
		vp.set_meta("toast_layer", layer)
	return layer.get_child(0) as Control


## Deferred: add the newest pill (one at a time: it replaces the toast showing; an older pill that never showed is
## dropped), then place and animate it. The node arguments are untyped: `near` (a sheet's card) or the root may be
## freed before this runs, and a freed object can't be passed to a typed parameter ("Cannot convert argument").
static func _attach(root_: Variant, pill_: Variant, near_: Variant, sec: float) -> void:
	if not is_instance_valid(pill_):
		return
	var pill := pill_ as PanelContainer
	var root: Control = root_ as Control if is_instance_valid(root_) else null
	if root == null or not root.is_inside_tree() or root.get_meta("latest", null) != pill:
		pill.free()
		return
	for old in root.get_children():
		if old.has_meta("toast"):
			root.remove_child(old)
			old.queue_free()
	root.add_child(pill)
	_place(pill, near_ as Control if is_instance_valid(near_) else null, sec)


static func _place(pill: PanelContainer, near: Control, sec: float) -> void:
	var vp := pill.get_viewport()
	var scr := vp.get_visible_rect().size
	var safe := safe_insets(vp)
	pill.size = Vector2.ZERO
	var sz := pill.get_combined_minimum_size()
	pill.size = sz
	var x := (scr.x - sz.x) / 2.0
	var y := scr.y - safe.y - BOTTOM - sz.y
	var above: Variant = pill.get_meta("above") if pill.has_meta("above") else null
	if is_instance_valid(above) and (above as Control).is_inside_tree() and (above as Control).is_visible_in_tree():
		var ax := (above as Control).get_global_transform_with_canvas()
		var ar := Rect2(ax.origin, (above as Control).size * ax.get_scale())
		x = ar.get_center().x - sz.x / 2.0
		y = ar.position.y - sz.y - 14.0
	elif is_instance_valid(near) and near.is_inside_tree() and near.is_visible_in_tree():
		var xf := near.get_global_transform_with_canvas()
		var r := Rect2(xf.origin, near.size * xf.get_scale())
		x = r.get_center().x - sz.x / 2.0
		y = r.end.y + 14.0                                       # under the card, clear of its buttons
		if y + sz.y > scr.y - safe.y - 12.0:
			y = r.end.y - sz.y - 22.0                            # no room below: over the card's bottom edge
	x = clampf(x, EDGE, maxf(EDGE, scr.x - EDGE - sz.x))
	y = clampf(y, safe.x + 12.0, maxf(safe.x + 12.0, scr.y - safe.y - 12.0 - sz.y))
	pill.position = Vector2(roundf(x), roundf(y))
	pill.pivot_offset = sz / 2.0
	var calm := _reduce_motion(pill)
	pill.scale = Vector2.ONE if calm else Vector2(0.94, 0.94)
	var tw := pill.create_tween()
	tw.tween_property(pill, "modulate:a", 1.0, 0.15)
	if not calm:
		tw.parallel().tween_property(pill, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(0.3, sec))
	tw.tween_property(pill, "modulate:a", 0.0, 0.25)
	tw.tween_callback(pill.queue_free)


static func _reduce_motion(n: Node) -> bool:
	var save := n.get_tree().root.get_node_or_null("Save")
	if save == null:
		return false
	var prefs: Variant = save.get("prefs")
	return prefs is Dictionary and bool((prefs as Dictionary).get("reduce_motion", false))


static func _icon(kind: String) -> Control:
	match kind:
		"coin":
			return UIKit.icon("coin", ICON)
		"gem":
			return UIKit.icon("gem", ICON)
		"good", "bad":
			var c := Control.new()
			c.custom_minimum_size = Vector2(ICON, ICON)
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			var good := kind == "good"
			var check := UIKit.svg("ic_check") if good else null
			c.draw.connect(func() -> void:
				var m := c.size / 2.0
				var rad := ICON / 2.0
				c.draw_circle(m, rad, Palette.TEAL if good else Palette.RED, true, -1.0, true)
				c.draw_arc(m, rad - 0.75, 0.0, TAU, 40, Color(1, 1, 1, 0.9), 1.5, true)
				if good:
					if check:
						c.draw_texture_rect(check, Rect2(m - Vector2(8, 8), Vector2(16, 16)), false)
				else:
					c.draw_line(m + Vector2(0, -5.5), m + Vector2(0, 1.5), Color.WHITE, 3.0, true)
					c.draw_circle(m + Vector2(0, 5.5), 1.7, Color.WHITE, true, -1.0, true))
			return c
	return null
