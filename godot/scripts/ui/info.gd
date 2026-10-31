class_name Info
extends RefCounted
## Feature info (index.html INFO / Info / .info-i / .info-tip): a small round plum ⓘ beside each feature with special
## rules. Tapping it opens one cream bubble with the explanation next to the icon: on a sheet above it (the control
## it explains sits below), kept inside that sheet when it fits; elsewhere below it (or above when there is no
## room); always on the screen. The bubble floats over everything (its own CanvasLayer on the tree root) and closes on a tap
## anywhere else (that tap still does its own job), its X, Escape, a second tap on the icon, the icon leaving the
## screen (its sheet closed) or a window resize. A tap on the icon never also presses the button under it.
##
## Pulse: an icon pulses when its feature is selected or becomes relevant (nudge(), or `auto` icons when they appear),
## only until the player has opened that explanation once ("open") and at most 3 showings in all, so returning
## players aren't nagged. Both are kept in Save.prefs.info ({key: "open" | showings}).
##
##   caption_row.add_child(Info.icon("team"))         # beside a caption or title (the way to use it)
##   Info.attach(button, "team")                       # (old) inside a button after its text: avoid (AX-04)
##   Info.nudge("team", teams_selected)                # pulse (or stop) the visible "team" icons
##
## The texts restate the rules in ludo_rules.gd (foe, dest, victims_at, pair_partner, move, waiting_six),
## snakes_ladders_rules.gd (land), rewards.gd (daily_state) and catalog.gd (scenes): change them together
## (tests/test_info.gd checks the main facts). [b]…[/b] is bold; ⓘ is drawn as the icon. The Snakes & Ladders keys
## follow the "Need a 1 to start" house rule (INFO_NEED_ONE, Save.prefs.sl_need_one): entry(key) picks the text.
## Copy: "Teams (2 v 2)" is the team mode and "Help your teammate" its finishing rule; "pairs" are two of your own
## pawns joined (PLAN Decision 1).

# l10n:begin
const INFO := {
	ind = {t = "Individual mode", b = [
		"Everyone plays for themselves. There are no teams.",
		"Capture any other colour’s loose pawns, and they can capture yours.",
		"The first player to get all four pawns home wins."]},
	team = {t = "Teams (2 v 2)", b = [
		"Teammates sit opposite each other: [b]Red + Yellow[/b] play against [b]Green + Blue[/b]. Four players only.",
		"Teammates never capture or block each other. Only the other team’s pawns can be captured.",
		"All four of your pawns home? Roll a 6 to [b]help your teammate[/b]: your rolls then move their pawns.",
		"Your team wins when both teammates have all four pawns home."]},
	pair = {t = "Pairs", b = [
		"Land a pawn on another of your own and they join into a [b]pair[/b]. Pairs can’t form on a start square or in the home lane, and never form by themselves on a star.",
		"A pair moves on even rolls only, and half the roll: a 4 moves it 2 squares.",
		"Single pawns can’t jump a pair. They must land on it, then roll exactly a 1 to move on. Only a pair can capture a pair.",
		"A pair splits by itself on any coloured start square or when it enters its home lane."]},
	free = {t = "Help your teammate", b = [
		"Teams (2 v 2) only. Once all four of your pawns are home, you keep your turns to help your teammate.",
		"First you need a 6: until you roll one, your turn passes.",
		"That 6 already moves your teammate’s pawns, and so does every roll after it.",
		"Your team wins when both teammates have all four pawns home."]},
	capture = {t = "Captures in Teams (2 v 2)", b = [
		"Land a single pawn on a loose pawn of the other team to send it back to its base, and roll again.",
		"Only a pair can capture a pair. A pair never captures a single pawn; they just share the square.",
		"Your teammate’s pawns are safe from you, and yours are safe from them.",
		"Star squares and coloured start squares are safe for everyone."]},
	slEntry = {t = "Entering the board", b = [
		"Everyone starts off the board. Any first roll moves your pawn on: a 3 takes it to square 3.",
		"Ladders and snakes count from your very first move.",
		"First to reach square 100 wins."]},
	sl = {t = "Snakes & Ladders rules", b = [
		"Any roll moves your pawn onto the board and up the squares.",
		"Land on the foot of a ladder to climb it. Land on a snake’s head to slide down to its tail.",
		"A 6 gives you another roll. Three 6s in a row end your turn.",
		"You need the exact roll to land on 100. A bigger roll leaves you where you are."]},
	cam = {t = "Camera view (Ludo)", b = [
		"[b]3D[/b]: the tilted look across the table in your room.",
		"[b]Top[/b]: the camera looks straight down, so every square is easy to see.",
		"Only the camera changes. You can switch at any time, even during a game."]},
	slcam = {t = "Camera view (Snakes & Ladders)", b = [
		"[b]3D[/b]: an angled look at the board in your scene.",
		"[b]Top[/b]: the camera looks straight down, so every square is easy to see.",
		"Only the camera changes. You can switch at any time, even during a game."]},
	daily = {t = "Daily reward", b = [
		"Claim one reward a day, from Day 1 to Day 7. Day 7 has the biggest prize.",
		"Claim again the next day to keep your run going. Miss a day and the calendar starts again at Day 1.",
		"After Day 7, a new week of rewards begins.",
		"A dice or character you already own is swapped for the coins shown.",
		"A new day starts at midnight on this device."]},
	scenes = {t = "Scenes", b = [
		"A scene is the 3D world around the Snakes & Ladders board. The board, snakes, ladders and rules are the same in every scene.",
		"Jungle Clearing and Enchanted Jungle are free. The others cost the coins shown, paid once, and are yours to keep.",
		"A scene you buy is put to use straight away. Switch between your scenes with [b]Use[/b].",
		"Not enough coins? Nothing is spent; the shop tells you how many more you need."]},
}
# l10n:end

## The Snakes & Ladders texts while the "Need a 1 to start" house rule is on (Settings, pref sl_need_one).
# l10n:begin
const INFO_NEED_ONE := {
	slEntry = {t = "Entering the board", b = [
		"Everyone starts off the board. You need to roll a [b]1[/b] to step onto square 1.",
		"A 2 to 6 leaves your pawn waiting off the board, but a 6 still gives you another roll.",
		"First to reach square 100 wins."]},
	sl = {t = "Snakes & Ladders rules", b = [
		"Roll a [b]1[/b] to enter the board. Until then your pawn waits off the board.",
		"Land on the foot of a ladder to climb it. Land on a snake’s head to slide down to its tail.",
		"A 6 gives you another roll. Three 6s in a row end your turn.",
		"You need the exact roll to land on 100. A bigger roll leaves you where you are."]},
}
# l10n:end

const MAX_SHOWINGS := 3                 # an unread icon pulses on at most this many showings
const BEATS := 4                        # one showing pulses 4 beats of 1.5 s (infoPulse 1.5s × 4)
const BEAT_SEC := 1.5
const GROUP := "info_icons"
const HIT := 48.0                       # tap target (UIKit.TAP; the dot is smaller)

const PLUM := Palette.INFO              # the (i) disc
const PLUM_DEEP := Palette.INFO_DEEP    # its lip
const TIP_BG := Palette.CARD            # the bubble face
const TIP_RING := Palette.TAN           # the bubble's outer ring and caret edge
const X_BG := Palette.CHIP              # (old) the bubble X disc: UIKit.close_button("soft") draws it now
const LIGHT_GLYPH := Palette.RIBBON     # the "i" of the white icon on an orange title ribbon (.pm-title .info-i)
const LIGHT_LIP := Color(Palette.RIBBON_SHADOW, 0.45)

## Tests / previews: their own state Dictionary instead of Save.prefs.info, and their own save function
## (called with that Dictionary after each change). Unset = Save.prefs.info + Save.save().
static var state_source: Variant = null
static var writer: Callable

static var _mem := {}                   # no Save autoload (headless tools): kept in memory only
static var _bubble: Bubble
static var _glyph_tex: Texture2D


# ---------- the texts ----------

## The explanation shown for `key` ({t, b}): INFO[key], or INFO_NEED_ONE[key] for the Snakes & Ladders keys while
## the "Need a 1 to start" house rule is on. {} for an unknown key.
static func entry(key: String) -> Dictionary:
	if INFO_NEED_ONE.has(key) and _pref("sl_need_one"):
		return INFO_NEED_ONE[key]
	return INFO.get(key, {})

static func _pref(name: String) -> bool:
	var s := _save_node()
	if s == null:
		return false
	var prefs: Variant = s.get("prefs")
	return prefs is Dictionary and bool((prefs as Dictionary).get(name, false))


# ---------- the icon ----------

## The tappable ⓘ for INFO[key]: a `size` px dot (22 default; 18 small) with a 48 px round tap area that reaches
## past its box. Put it beside a caption or a title, never inside an action button (the old attach() does that). `auto`: it pulses by itself whenever it appears (a sheet opening).
## look: "plum" (default) or "light" (white with an orange glyph, on the orange title ribbons).
static func icon(key: String, auto := false, size := 22.0, look := "plum") -> Control:
	return InfoIcon.new(key, auto, size, look)

## Puts an icon inside `b` right after its text (the text and icon stay centred together; tapping the icon
## does not press the button). Returns the icon.
static func attach(b: Button, key: String, auto := false, size := 20.0, gap := 5.0) -> Control:
	var ic := InfoIcon.new(key, auto, size, "plum")
	var extra := size + gap
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		if not b.has_theme_stylebox_override(st):
			continue
		var sb := b.get_theme_stylebox(st).duplicate() as StyleBox
		sb.content_margin_right = maxf(sb.content_margin_right, 0.0) + extra
		b.add_theme_stylebox_override(st, sb)
	b.add_child(ic)
	var place := func() -> void:
		if not is_instance_valid(b) or not is_instance_valid(ic):
			return                           # (deferred: the button may be gone already)
		var f := b.get_theme_font("font")
		var fs := b.get_theme_font_size("font_size")
		var tw := f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var sb := b.get_theme_stylebox("normal")
		var l := sb.get_margin(SIDE_LEFT)
		var r := b.size.x - sb.get_margin(SIDE_RIGHT)
		var cx := (l + r) / 2.0
		var top := sb.get_margin(SIDE_TOP)
		var bottom := b.size.y - sb.get_margin(SIDE_BOTTOM)
		ic.position = Vector2(roundf(cx + tw / 2.0 + gap), roundf((top + bottom - size) / 2.0))
	b.resized.connect(place)
	place.call_deferred()
	return ic


# ---------- pulse ----------

## Pulse the visible icons of `key` (under `root` when given), or stop them (on = false). Counts one showing when
## at least one icon starts; never once the key was read or after MAX_SHOWINGS showings.
static func nudge(key: String, on := true, root: Node = null) -> void:
	var icons := _icons(key, root)
	if not on or not may(key):
		for ic: InfoIcon in icons:
			ic.stop_pulse()
		return
	var fresh := icons.filter(func(ic: InfoIcon) -> bool: return not ic.pulsing and ic.is_visible_in_tree())
	if fresh.is_empty():
		return
	for ic: InfoIcon in fresh:
		ic.start_pulse()
	count_showing(key)

## True while `key` may still pulse: not read yet and fewer than MAX_SHOWINGS showings.
static func may(key: String) -> bool:
	var v: Variant = _state().get(key)
	return not is_read(key) and _num(v) < MAX_SHOWINGS

static func is_read(key: String) -> bool:
	var v: Variant = _state().get(key)
	return typeof(v) == TYPE_STRING and v == "open"

## How many times `key` pulsed (0 once read).
static func showings(key: String) -> int:
	return 0 if is_read(key) else _num(_state().get(key))

## Book one showing of `key` (when it may still pulse). Returns true when counted.
static func count_showing(key: String) -> bool:
	if not INFO.has(key) or not may(key):
		return false
	_state()[key] = showings(key) + 1
	_write()
	return true

## Remember that the player read `key`: it never pulses again.
static func mark_read(key: String) -> void:
	if not INFO.has(key) or is_read(key):
		return
	_state()[key] = "open"
	_write()


# ---------- the bubble ----------

## Open the explanation of `ic` (an icon from icon() / attach()); a second open of the same icon closes it.
static func open(ic: Control) -> void:
	var key := str(ic.get("key")) if ic else ""
	if not INFO.has(key):
		return
	if is_open() and _bubble.anchor == ic:
		close()
		return
	close()
	if not ic.is_inside_tree():
		return
	var tree := ic.get_tree()
	_bubble = Bubble.new(key, ic)
	tree.root.add_child(_bubble)
	for o: InfoIcon in _icons(key, null):
		o.stop_pulse()
	mark_read(key)
	var snd := tree.root.get_node_or_null("Sound")
	if snd:
		snd.sfx("select")

## Open INFO[key] beside the first visible icon of that key (previews, tests). False when none is on screen.
static func open_key(key: String) -> bool:
	for ic: InfoIcon in _icons(key, null):
		if ic.is_visible_in_tree():
			open(ic)
			return true
	return false

## Close the bubble (a sheet change, a new screen). Returns true when one was open.
static func close() -> bool:
	if not is_open():
		_bubble = null
		return false
	var b := _bubble
	_bubble = null
	b.dismiss()
	return true

static func is_open() -> bool:
	return _bubble != null and is_instance_valid(_bubble) and not _bubble.is_queued_for_deletion() and not _bubble.closing

## The key whose bubble is open, or "".
static func open_key_now() -> String:
	return _bubble.key if is_open() else ""


# ---------- state ----------

static func _state() -> Dictionary:
	if state_source is Dictionary:
		return state_source
	var s := _save_node()
	if s == null:
		return _mem
	var prefs: Dictionary = s.prefs
	if not prefs.get("info") is Dictionary:
		prefs.info = {}
	return prefs.info

static func _write() -> void:
	if writer.is_valid():
		writer.call(_state())
		return
	if state_source is Dictionary:
		return                           # a test state without a writer: nothing to write
	var s := _save_node()
	if s:
		s.save()

static func _save_node() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Save")
	return null

static func _num(v: Variant) -> int:      # JSON brings counts back as floats
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return maxi(0, int(v))
	return 0

static func _icons(key: String, root: Node) -> Array:
	var ml := Engine.get_main_loop()
	if not ml is SceneTree:
		return []
	return (ml as SceneTree).get_nodes_in_group(GROUP).filter(func(n: Node) -> bool:
		return n is InfoIcon and (n as InfoIcon).key == key and not n.is_queued_for_deletion() and (root == null or root == n or root.is_ancestor_of(n)))

## The ⓘ glyph as a small texture (assets/ui/ic_info.svg), for an inline ⓘ inside the bubble text.
static func glyph_texture() -> Texture2D:
	if _glyph_tex == null:
		_glyph_tex = UIKit.svg("ic_info")
	return _glyph_tex


# ---------- widgets ----------

## The round ⓘ. Its box is the dot; the tap area is a 48 px circle around its centre. With Reduce motion the
## pulse is a still ring for the same time.
class InfoIcon extends Control:
	var key := ""
	var auto := false
	var dot := 22.0
	var look := "plum"
	var pulsing := false
	var _p := 0.0                         # 0..1..0 over each beat
	var _tw: Tween
	var _down := false
	var _still := false                   # Reduce motion: a still ring instead of the pulse

	func _init(k: String, a := false, d := 22.0, l := "plum") -> void:
		key = k
		auto = a
		dot = d
		look = l
		custom_minimum_size = Vector2(d, d)
		size = Vector2(d, d)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		focus_mode = Control.FOCUS_NONE
		add_to_group(Info.GROUP)
		visibility_changed.connect(_on_visibility)

	func _ready() -> void:
		if auto:
			_auto_nudge.call_deferred()

	func _on_visibility() -> void:
		if not is_visible_in_tree():
			stop_pulse()                     # a later showing pulses (and is counted) afresh
		elif auto:
			_auto_nudge.call_deferred()

	func _auto_nudge() -> void:
		if is_inside_tree() and is_visible_in_tree():
			Info.nudge(key, true, self)

	func _has_point(p: Vector2) -> bool:
		return p.distance_to(size / 2.0) <= Info.HIT / 2.0

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			accept_event()
			if e.button_index != MOUSE_BUTTON_LEFT:
				return
			if e.pressed:
				_down = true
			elif _down:
				_down = false
				if _has_point(e.position):
					Info.open(self)
		elif e is InputEventScreenTouch or e is InputEventScreenDrag or e is InputEventMouseMotion:
			accept_event()

	func start_pulse() -> void:
		stop_pulse()
		pulsing = true
		_tw = create_tween()
		if Sheet.reduce_motion():
			_still = true
			queue_redraw()
			_tw.tween_interval(Info.BEATS * Info.BEAT_SEC)
			_tw.finished.connect(func() -> void:
				pulsing = false
				_still = false
				queue_redraw())
			return
		for k in Info.BEATS:
			_tw.tween_method(_set_p, 0.0, 1.0, Info.BEAT_SEC / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_tw.tween_method(_set_p, 1.0, 0.0, Info.BEAT_SEC / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tw.finished.connect(func() -> void:
			pulsing = false
			_set_p(0.0))

	func stop_pulse() -> void:
		if _tw:
			_tw.kill()
			_tw = null
		pulsing = false
		_still = false
		_set_p(0.0)

	func _set_p(v: float) -> void:
		_p = v
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := dot / 2.0
		var light := look == "light"
		if pulsing and _still:
			draw_arc(c, r + 5.0, 0.0, TAU, 40, Color(Info.PLUM, 0.55), 3.0, true)
		elif pulsing:          # the soft ring that grows and fades (box-shadow 0 0 0 2px → 10px)
			var spread := 2.0 + 8.0 * _p
			draw_circle(c, r * (1.0 + 0.18 * _p) + spread, Color(Info.PLUM, 0.6 * (1.0 - _p)), true, -1.0, true)
		var s := 1.0 + 0.18 * _p
		draw_set_transform(c, 0.0, Vector2(s, s))
		if light:
			draw_circle(Vector2(0, 2), r, Info.LIGHT_LIP, true, -1.0, true)
			draw_circle(Vector2.ZERO, r, Color.WHITE, true, -1.0, true)
		else:
			draw_circle(Vector2.ZERO, r + 2.0, Color.WHITE, true, -1.0, true)   # 0 0 0 2px #fff
			draw_circle(Vector2(0, 2), r, Info.PLUM_DEEP, true, -1.0, true)     # 0 2px 0 #5a3f99
			draw_circle(Vector2.ZERO, r, Info.PLUM, true, -1.0, true)
		# the "i" (INFO_SVG: a 20-unit box drawn at 14/22 of the dot)
		var g := dot * 14.0 / 22.0 / 20.0
		var ink := Info.LIGHT_GLYPH if light else Color.WHITE
		var o := Vector2(-10.0, -10.0) * g
		draw_circle(o + Vector2(10.0, 5.2) * g, 1.9 * g, ink, true, -1.0, true)
		var stem := StyleBoxFlat.new()
		stem.bg_color = ink
		stem.set_corner_radius_all(int(ceilf(1.8 * g)))
		stem.corner_detail = 6
		stem.anti_aliasing = true
		stem.anti_aliasing_size = 0.6
		draw_style_box(stem, Rect2(o + Vector2(8.2, 8.3) * g, Vector2(3.6, 8.4) * g))
		draw_set_transform(Vector2.ZERO)


## The explanation bubble: its own top CanvasLayer, a cream card (TAN ring, white border) with the INK title, the
## bullets, a soft X, and a small caret pointing at the icon.
class Bubble extends CanvasLayer:
	const MARGIN := 10.0
	const GAP := 12.0                     # icon edge to card edge (the caret spans it)
	const MAX_W := 330.0
	const FS := 15                        # bullet text (INFO-01)
	const TITLE_FS := 19
	const CARET_W := 22.0
	const CARET_H := 10.0

	var key := ""
	var anchor: Control
	var closing := false
	var root: Control
	var holder: Control                   # the bubble: the card plus its X and caret, placed and popped as one
	var panel: PanelContainer
	var x_btn: Button
	var caret: Control
	var _caret_up := true                 # the caret points up (bubble below the icon)
	var _caret_x := 0.0
	var _frames := 0
	var _shown := false
	var _natural_w := 0.0

	func _init(k: String, ic: Control) -> void:
		key = k
		anchor = ic
		layer = 120
		name = "InfoBubble"
		root = Control.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.theme = UIKit.theme()
		add_child(root)
		_build()
		ic.tree_exiting.connect(_lost)
		ic.visibility_changed.connect(_on_anchor_visibility)

	func _ready() -> void:
		get_viewport().size_changed.connect(_lost)

	func _on_anchor_visibility() -> void:
		if is_instance_valid(anchor) and not anchor.is_visible_in_tree():
			_lost()

	func _lost() -> void:
		if Info._bubble == self:
			Info.close()
		else:
			dismiss()

	func _build() -> void:
		var d: Dictionary = Info.entry(key)
		holder = Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_STOP    # taps on the bubble stay on the bubble
		holder.modulate.a = 0.0
		root.add_child(holder)
		panel = PanelContainer.new()       # the tan ring and the drop shadow around the cream card
		var ring := UIKit.box(Info.TIP_RING, UIKit.R.lg + 2, 0, Color.TRANSPARENT, 14, Color(Palette.SHADOW_DEEP, 0.32))
		ring.shadow_offset = Vector2(0, 10)
		UIKit.pad(ring, 2)
		panel.add_theme_stylebox_override("panel", ring)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(panel)
		var card := PanelContainer.new()
		var st := UIKit.box(Info.TIP_BG, UIKit.R.lg, UIKit.BW.rim, Color.WHITE)
		st.content_margin_left = UIKit.SPACE.lg; st.content_margin_right = UIKit.SPACE.lg
		st.content_margin_top = 14; st.content_margin_bottom = 15
		card.add_theme_stylebox_override("panel", st)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(card)
		var col := UIKit.vbox(UIKit.SPACE.sm)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(col)
		var title := UIKit.label(tr(str(d.get("t", ""))), TITLE_FS, Palette.INK, UIKit.font_display())
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_constant_override("line_spacing", -2)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(UIKit.margin(title, 0, 1, 38, 0))
		var f_body := UIKit.font_body(700)
		var f_bold := UIKit.font_body(900)
		_natural_w = UIKit.font_display().get_string_size(tr(str(d.get("t", ""))), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FS).x + 38.0
		for src_line: String in d.get("b", []):
			var line := tr(src_line)
			var row := UIKit.hbox(0)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(UIKit.bullet(Info.PLUM))
			var rt := RichTextLabel.new()
			rt.bbcode_enabled = true
			rt.fit_content = true
			rt.scroll_active = false
			rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rt.add_theme_font_override("normal_font", f_body)
			rt.add_theme_font_override("bold_font", f_bold)
			rt.add_theme_font_size_override("normal_font_size", FS)
			rt.add_theme_font_size_override("bold_font_size", FS)
			rt.add_theme_color_override("default_color", Palette.INK)
			rt.add_theme_constant_override("line_separation", 1)
			var parts := line.split("ⓘ")
			for k in parts.size():
				if k > 0 and Info.glyph_texture():
					rt.add_image(Info.glyph_texture(), 16, 16, Color.WHITE, INLINE_ALIGNMENT_CENTER)
				rt.append_text(parts[k])
			row.add_child(rt)
			col.add_child(row)
			var plain := line.replace("[b]", "").replace("[/b]", "")
			_natural_w = maxf(_natural_w, f_body.get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x + 16.0)
		_natural_w += 2.0 * UIKit.SPACE.lg + 6.0 + 4.0      # card padding, border, ring
		x_btn = UIKit.close_button("soft")
		x_btn.name = "Close"
		x_btn.tooltip_text = tr("Close")
		x_btn.pressed.connect(func() -> void: Info.close())
		holder.add_child(x_btn)
		caret = Control.new()
		caret.name = "Caret"
		caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caret.size = Vector2(CARET_W, CARET_H + 4.0)
		caret.draw.connect(_draw_caret)
		holder.add_child(caret)

	## The caret: a TAN triangle with the white-bordered face inside it, overlapping the card edge so the seam hides.
	func _draw_caret() -> void:
		var w := CARET_W
		var h := CARET_H
		var outer: PackedVector2Array
		var inner: PackedVector2Array
		var fill: PackedVector2Array
		if _caret_up:              # tip at the top, base on the card's top edge (y = h + 4)
			outer = PackedVector2Array([Vector2(w / 2.0, 0), Vector2(w, h + 4.0), Vector2(0, h + 4.0)])
			inner = PackedVector2Array([Vector2(w / 2.0, 2.6), Vector2(w - 2.8, h + 4.0), Vector2(2.8, h + 4.0)])
			fill = PackedVector2Array([Vector2(w / 2.0, 6.0), Vector2(w - 6.4, h + 4.0), Vector2(6.4, h + 4.0)])
		else:                      # tip at the bottom, base on the card's bottom edge (y = 0)
			outer = PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w / 2.0, h + 4.0)])
			inner = PackedVector2Array([Vector2(2.8, 0), Vector2(w - 2.8, 0), Vector2(w / 2.0, h + 1.4)])
			fill = PackedVector2Array([Vector2(6.4, 0), Vector2(w - 6.4, 0), Vector2(w / 2.0, h - 2.0)])
		caret.draw_colored_polygon(outer, Info.TIP_RING)
		caret.draw_colored_polygon(inner, Color.WHITE)
		caret.draw_colored_polygon(fill, Info.TIP_BG)

	func _process(_dt: float) -> void:
		if closing:
			return
		if not is_instance_valid(anchor) or not anchor.is_inside_tree():
			_lost()
			return
		_place()
		_frames += 1
		if _frames >= 2 and not _shown:      # the wrapped text has its height after a layout pass
			_shown = true
			if Sheet.reduce_motion():
				var tf := holder.create_tween()
				tf.tween_property(holder, "modulate:a", 1.0, 0.12)
				return
			holder.scale = Vector2(0.7, 0.7)       # pop in from the icon's side (the .info-tip pop)
			var tw := holder.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(holder, "modulate:a", 1.0, 0.14)
			tw.tween_property(holder, "scale", Vector2.ONE, 0.2)

	## The card of the sheet the icon sits on, in this layer's coordinates (empty when it isn't on a sheet).
	func _sheet_rect() -> Rect2:
		var n: Node = anchor
		while n and not (n is Sheet):
			n = n.get_parent()
		if n == null or (n as Sheet).card == null:
			return Rect2()
		var cd: Control = (n as Sheet).card
		var xf := cd.get_global_transform_with_canvas()
		return Rect2(xf * Vector2.ZERO, cd.size * xf.get_scale())

	## Centred on the icon. On a sheet (re-audit #37: it never spills off the sheet onto the screen under it, nor
	## covers the control it explains, which sits under its caption's ⓘ): above the icon inside the sheet, else below
	## it inside the sheet, else above it on the screen, else below. Off sheets: below, else above. Else as low as
	## fits. Always kept on the screen, and no wider than the sheet.
	func _place() -> void:
		var vr := root.get_viewport_rect()
		var xf := anchor.get_global_transform_with_canvas()
		var c := xf * (anchor.size / 2.0)
		var half := float(anchor.get("dot")) / 2.0 * xf.get_scale().y
		var L0 := vr.position.x + MARGIN
		var R0 := vr.end.x - MARGIN
		var T0 := vr.position.y + MARGIN
		var B0 := vr.end.y - MARGIN
		var sr := _sheet_rect().intersection(Rect2(L0, T0, R0 - L0, B0 - T0))
		if sr.size.x >= 200.0:                   # the bubble stays over the sheet's card sideways too
			L0 = sr.position.x
			R0 = sr.end.x
		var w := minf(minf(MAX_W, R0 - L0), _natural_w)
		if panel.size.x != w:
			panel.size = Vector2(w, panel.get_combined_minimum_size().y)
		var h := panel.get_combined_minimum_size().y
		var x := clampf(c.x - w / 2.0, L0, maxf(L0, R0 - w))
		var below := c.y + half + GAP
		var above := c.y - half - GAP - h
		var fits_below := below + h <= B0
		var fits_above := above >= T0
		var y := maxf(T0, B0 - h)
		if sr.size.y > 0.0 and above >= sr.position.y:
			y = above                            # on a sheet the explained control sits under its caption's ⓘ
		elif sr.size.y > 0.0 and below + h <= sr.end.y:
			y = below
		elif sr.size.y > 0.0 and fits_above:
			y = above
		elif fits_below:
			y = below
		elif fits_above:
			y = above
		panel.size = Vector2(w, h)
		holder.size = Vector2(w, h)
		holder.position = Vector2(roundf(x), roundf(y))
		x_btn.size = Vector2(UIKit.TAP, UIKit.TAP)
		x_btn.position = Vector2(w - 2.0 - 3.0 - UIKit.TAP, 2.0 + 1.0)   # inside the card's white border
		var up := y >= c.y
		var show_caret := is_equal_approx(y, below) or is_equal_approx(y, above)
		var cx := clampf(c.x - x, UIKit.R.lg + CARET_W / 2.0, w - UIKit.R.lg - CARET_W / 2.0)
		caret.visible = show_caret and absf(cx - (c.x - x)) < 1.0      # only when it really points at the icon
		if up != _caret_up or absf(cx - _caret_x) > 0.25:
			_caret_up = up
			_caret_x = cx
			caret.queue_redraw()
		caret.position = Vector2(cx - CARET_W / 2.0, -CARET_H - 2.0) if up else Vector2(cx - CARET_W / 2.0, h - 2.0)
		if not _shown:
			holder.pivot_offset = Vector2(clampf(c.x - x, 0.0, w), 0.0 if up else h)

	## Taps elsewhere close the bubble and still do their own job; Escape closes only the bubble.
	func _input(e: InputEvent) -> void:
		if closing:
			return
		if e.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			Info.close()
			return
		var pos := Vector2.INF
		if e is InputEventMouseButton and e.pressed:
			pos = e.position
		elif e is InputEventScreenTouch and e.pressed:
			pos = e.position
		if pos == Vector2.INF:
			return
		pos = root.get_global_transform_with_canvas().affine_inverse() * pos
		if holder.get_global_rect().has_point(pos):
			return
		if is_instance_valid(anchor):
			var xf := anchor.get_global_transform_with_canvas()
			if pos.distance_to(xf * (anchor.size / 2.0)) <= Info.HIT / 2.0 * xf.get_scale().x:
				return                       # the icon itself toggles the bubble
		Info.close()

	func dismiss() -> void:
		if closing:
			return
		closing = true
		set_process_input(false)
		if is_instance_valid(anchor):
			if anchor.tree_exiting.is_connected(_lost):
				anchor.tree_exiting.disconnect(_lost)
			if anchor.visibility_changed.is_connected(_on_anchor_visibility):
				anchor.visibility_changed.disconnect(_on_anchor_visibility)
		if not is_inside_tree():
			queue_free()
			return
		var tw := create_tween()
		tw.tween_property(holder, "modulate:a", 0.0, 0.1)
		tw.finished.connect(queue_free)
