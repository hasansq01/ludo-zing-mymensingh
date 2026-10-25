class_name EmotePicker
extends Control
## The emote button and its picker panel in a game (index.html `Emotes`: #emoteBtn / #emotePanel).
##
## The button: a bare cream chat bubble with a thin warm-brown outline and three dots (no background), placed by
## the owner (place_button(centre), usually just above your avatar). It opens the panel: a slim cream panel along
## the left edge of the board, vertically centred in the band the owner gives (place_panel(top, bottom); one column
## when the band is tall enough, else two, three or six), holding the equipped pack's six stickers. It pops out from
## the left (slide + scale + fade, the stickers a moment after each other) and closes with a quick fade.
## A pick sends (picked(id)), closes the panel and cools the picker down for COOL s (the stickers greyed, taps
## ignored). It closes on a pick, a tap outside it (that tap is used up: it doesn't reach the board), Escape, Back
## (close_open(), for main's Back handler; the GO_BACK notification as a fallback) and whenever guard() says so (a
## sheet opened). Nothing here blocks game input except the button itself and the open panel.
## Time is driven by tick(dt) (from _process; tests call it). Reduce motion: no slide or pop.

signal picked(id: String)

const SZ := 44.0                         ## the button's hit area
const ICON := 34.0                       ## the drawn chat bubble
const CW := 72.0                         ## one picker cell: a wide sticker
const CH := 50.0
const GAP := 5.0
const PAD := 6.0
const LEFT := 8.0
const COOL := 2.0
const OPEN_SEC := 0.24
const CLOSE_SEC := 0.16
const CELL_SEC := 0.26
const STAGGER := 0.035
const STARTER := ["happy", "laugh", "cool", "angry", "love", "party"]

var ids: Array[String] = []
var is_open := false
var cool_left := 0.0
var guard := Callable()                  ## () -> bool: true closes the panel (a sheet is open, the game paused)
var still := -1                          ## reduce motion: -1 = the Settings pref, 0 / 1 = forced (tests)
var button: EmoteButton
var panel: PickPanel
var cells: Array = []
var cols := 1
var band := Vector2(120, 600)            ## the free band (top, bottom) the panel is centred in
var _anim := 0.0                         ## s since the panel opened / started closing
var _closing := false
var _grey := 0.0
var _kbd := false                        ## the last input was a key (focus rings show only then)
var _swallow_until := 0                  ## ms: the touch's emulated mouse click after an outside tap is used up too
static var _open_ones: Array = []
static var _grey_shader: Shader


func _init() -> void:
	name = "EmotePicker"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button = EmoteButton.new()
	button.pressed.connect(toggle)
	add_child(button)
	panel = PickPanel.new()
	panel.visible = false
	add_child(panel)
	refresh()

func _exit_tree() -> void:
	_open_ones.erase(self)

func _process(delta: float) -> void:
	tick(delta)

## The equipped pack's six emotes (core/emotes.gd when it's there; else the Starter set).
static func equipped() -> Array[String]:
	var out: Array[String] = []
	var path := "res://scripts/core/emotes.gd"
	if ResourceLoader.exists(path):
		var s: Variant = load(path)
		if s is Script and (s as Script).has_method("equipped_ids"):
			var got: Variant = (s as Script).call("equipped_ids")
			if got is Array:
				for x in got:
					if not EmoteArt.info(str(x)).is_empty():
						out.append(str(x))
	if out.is_empty():
		out.assign(STARTER)
	return out

## Rebuilds the cells from the equipped pack (each game start: the pack may have changed).
func refresh() -> void:
	ids = equipped()
	for c in cells:
		c.queue_free()
	cells.clear()
	for k in ids.size():
		var cell := Cell.new(ids[k], k)
		cell.pressed.connect(pick.bind(ids[k]))
		panel.add_child(cell)
		cells.append(cell)
	_layout_panel()

## The button's centre (the owner's layout); show = false hides it (and closes the panel).
func place_button(center: Vector2, show_it := true) -> void:
	button.size = Vector2(SZ, SZ)
	button.position = (center - button.size / 2.0).round()
	button.visible = show_it
	if not show_it and is_open:
		close()

## The button's rect (Rect2() while hidden).
func button_rect() -> Rect2:
	return Rect2(button.position, button.size) if button.visible else Rect2()

## The band the panel is centred in (top and bottom y).
func place_panel(top: float, bottom: float) -> void:
	band = Vector2(top, bottom)
	_layout_panel()

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	if is_open or not button.visible:
		return
	is_open = true
	_closing = false
	_anim = 0.0 if not _still() else OPEN_SEC + CELL_SEC + STAGGER * 6.0
	panel.visible = true
	_layout_panel()
	button.open = true
	if not _open_ones.has(self):
		_open_ones.append(self)
	UIKit.sfx("tap")
	if _kbd and not cells.is_empty():
		(cells[0] as Control).grab_focus()
	tick(0.0)

func close() -> void:
	if not is_open:
		return
	is_open = false
	_closing = true
	_anim = 0.0
	button.open = false
	_open_ones.erase(self)
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f and panel.is_ancestor_of(f):
		if _kbd:
			button.grab_focus()
		else:
			f.release_focus()
	if _still():
		_finish_close()
	tick(0.0)

## Back for main: closes any open picker; true when one was open (the Back is used up).
static func close_open() -> bool:
	var any := false
	for p in _open_ones.duplicate():
		if is_instance_valid(p) and p.is_open:
			p.close()
			any = true
	_open_ones.clear()
	return any

## A pick from the panel: sends unless cooling down, then closes and cools down.
func pick(id: String) -> bool:
	if cool_left > 0.0 or not ids.has(id):
		return false
	cool_left = COOL
	close()
	picked.emit(id)
	return true

func cooling() -> bool:
	return cool_left > 0.0

## Time passes: the panel's in / out animation, the cooldown and its grey fading in and out.
func tick(dt: float) -> void:
	if is_open and guard.is_valid() and bool(guard.call()):
		close()
	if cool_left > 0.0:
		cool_left = maxf(0.0, cool_left - dt)
	var want := 1.0 if cool_left > 0.0 else 0.0
	_grey = move_toward(_grey, want, dt / 0.3)   # the colour goes and comes back smoothly
	for c in cells:
		(c as Cell).set_grey(_grey)
	if not panel.visible:
		return
	_anim += dt
	var still_ := _still()
	if _closing:
		var u := clampf(_anim / CLOSE_SEC, 0.0, 1.0)
		var e := u * u
		panel.modulate.a = 1.0 - e
		panel.scale = Vector2.ONE * lerpf(1.0, 0.94, e)
		panel.position.x = LEFT - 16.0 * e
		if u >= 1.0:
			_finish_close()
		return
	if still_:
		panel.modulate.a = 1.0
		panel.scale = Vector2.ONE
		panel.position.x = LEFT
		for c in cells:
			(c as Cell).pose(1.0)
		return
	var p := clampf(_anim / OPEN_SEC, 0.0, 1.0)
	var ep := _back_out(p, 0.6)
	panel.modulate.a = clampf(p * 1.6, 0.0, 1.0)
	panel.scale = Vector2.ONE * lerpf(0.88, 1.0, ep)
	panel.position.x = LEFT - 26.0 * (1.0 - ep)
	for k in cells.size():
		var q := clampf((_anim - 0.06 - STAGGER * k) / CELL_SEC, 0.0, 1.0)
		(cells[k] as Cell).pose(q)

func _finish_close() -> void:
	_closing = false
	panel.visible = false
	panel.modulate.a = 1.0
	panel.scale = Vector2.ONE
	panel.position.x = LEFT

## The panel's grid: the fewest columns whose height fits the band (1, 2, 3, else 6), vertically centred in it.
func _layout_panel() -> void:
	var n := maxi(cells.size(), 1)
	var avail := band.y - band.x
	cols = 6
	for k in [1, 2, 3, 6]:
		if _grid_size(k, n).y <= avail:
			cols = k
			break
	var sz := _grid_size(cols, n)
	panel.size = sz
	panel.pivot_offset = Vector2(0, sz.y / 2.0)
	var y := maxf(band.x - 4.0, (band.x + band.y) / 2.0 - sz.y / 2.0)
	if not _closing:
		panel.position = Vector2(LEFT, round(y))
	else:
		panel.position.y = round(y)
	for k in cells.size():
		var cell: Cell = cells[k]
		cell.home = Vector2(PAD + (k % cols) * (CW + GAP), PAD + (k / cols) * (CH + GAP))
		cell.size = Vector2(CW, CH)
		cell.pivot_offset = cell.size / 2.0
		cell.pose(cell.k)

static func _grid_size(c: int, n: int) -> Vector2:
	var rows := ceili(float(n) / c)
	return Vector2(c * CW + (c - 1) * GAP + PAD * 2.0, rows * CH + (rows - 1) * GAP + PAD * 2.0)

## The panel's rect on screen (Rect2() while closed).
func panel_rect() -> Rect2:
	return Rect2(panel.position, panel.size) if panel.visible else Rect2()

func _input(e: InputEvent) -> void:
	if e is InputEventKey:
		if e.pressed:
			_kbd = true
	elif e is InputEventMouseButton or e is InputEventScreenTouch:
		_kbd = false
	if not is_visible_in_tree():
		return
	var press: bool = (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed)
	var pointer: bool = e is InputEventScreenTouch or e is InputEventMouseButton
	if pointer and Time.get_ticks_msec() < _swallow_until and not _inside(e.position):
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	if e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if press and not _inside(e.position):
		close()
		_swallow_until = Time.get_ticks_msec() + 300
		get_viewport().set_input_as_handled()

func _inside(p: Vector2) -> bool:
	var local := get_global_transform_with_canvas().affine_inverse() * p
	return Rect2(panel.position, panel.size).has_point(local) or (button.visible and Rect2(button.position, button.size).has_point(local))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_open:
		close()

func _still() -> bool:
	return still == 1 if still >= 0 else PlayerTile._pref("reduce_motion")

## Ease out with a small overshoot (the web's cubic-bezier(.2,.9,.3,1.15)).
static func _back_out(u: float, s: float) -> float:
	var v := u - 1.0
	return 1.0 + (s + 1.0) * v * v * v + s * v * v

## The sticker without most of its transparent margin (the art leaves room round the speech bubble), so it reads
## bigger in a 72 x 50 cell.
static func cropped(t: Texture2D) -> Texture2D:
	if t == null:
		return null
	var a := AtlasTexture.new()
	a.atlas = t
	var k := t.get_width() / 344.0
	a.region = Rect2(12.0 * k, 0.0, 300.0 * k, 208.0 * k)
	return a

static func grey_material() -> ShaderMaterial:
	if _grey_shader == null:
		_grey_shader = Shader.new()
		_grey_shader.code = """
shader_type canvas_item;
uniform float grey = 0.0;
void fragment() {
	float l = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));   // COLOR: the texture times the draw's colour
	COLOR.rgb = mix(COLOR.rgb, vec3(l), grey);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _grey_shader
	return m


## The button: a cream chat bubble with three dots, a thin warm-brown outline and a soft lip (no background).
class EmoteButton extends Button:
	var open := false:
		set(v):
			open = v
			queue_redraw()
	var _down := false
	static var _tex: Texture2D

	func _init() -> void:
		name = "EmoteButton"
		flat = true
		focus_mode = Control.FOCUS_ALL
		tooltip_text = "Emotes"
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(SZ, SZ)
		size = Vector2(SZ, SZ)
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(s, empty)
		button_down.connect(func(): _down = true; queue_redraw())
		button_up.connect(func(): _down = false; queue_redraw())
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	static func texture() -> Texture2D:
		if _tex == null:
			var fill_hi := Palette.CARD.lerp(Color.WHITE, 0.4).to_html(false)
			var fill_lo := Palette.HONEY_TINT.lerp(Palette.PEACH, 0.2).lerp(Color.WHITE, 0.35).to_html(false)
			var ink := Palette.RUST.lerp(Palette.SUB, 0.15).to_html(false)
			var lip := Palette.TAN.lerp(Palette.BRONZE, 0.4).to_html(false)
			var shade := Palette.SHADOW.to_html(false)
			var bubble := "M9 5.5h14a6 6 0 0 1 6 6v5.5a6 6 0 0 1-6 6h-8.6l-5 4.1c-.6.5-1.5.1-1.4-.7l.3-3.6A6 6 0 0 1 3 17V11.5a6 6 0 0 1 6-6z"
			var svg := ('<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="-2 -1 36 36"><defs>'
				+ '<linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></linearGradient></defs>' % [fill_hi, fill_lo]
				+ '<path d="%s" transform="translate(0 3.2)" fill="#%s" fill-opacity="0.22"/>' % [bubble, shade]
				+ '<path d="%s" transform="translate(0 1.5)" fill="#%s" fill-opacity="0.95" stroke="#%s" stroke-opacity="0.9" stroke-width="1.5" stroke-linejoin="round"/>' % [bubble, lip, lip]
				+ '<path d="%s" fill="url(#g)" stroke="#%s" stroke-width="1.5" stroke-linejoin="round"/>' % [bubble, ink]
				+ '<path d="M8 8.6h7" stroke="#ffffff" stroke-width="1.6" stroke-linecap="round" opacity=".9"/>'
				+ '<circle cx="10.8" cy="14.3" r="1.75" fill="#%s"/><circle cx="16" cy="14.3" r="1.75" fill="#%s"/><circle cx="21.2" cy="14.3" r="1.75" fill="#%s"/></svg>' % [ink, ink, ink])
			var img := Image.new()
			img.load_svg_from_string(svg, 4.0)
			_tex = ImageTexture.create_from_image(img)
		return _tex

	func _draw() -> void:
		var k := 0.92 if _down else (1.1 if open else 1.0)
		var s := ICON * 36.0 / 32.0 * k
		var r := Rect2(size / 2.0 - Vector2(s, s) / 2.0, Vector2(s, s))
		if open:                              # a warm glow while the panel is open
			draw_circle(size / 2.0 + Vector2(0, 1), s * 0.5, Color(Palette.PEACH, 0.35), true, -1.0, true)
		draw_texture_rect(texture(), r, false)
		var p := get_parent() as EmotePicker
		if has_focus() and p and p._kbd:
			var st := UIKit.box(Color.TRANSPARENT, UIKit.R.sm, 2, Palette.PEACH)
			st.draw_center = false
			draw_style_box(st, Rect2(Vector2.ZERO, size).grow(2))


## The slim cream panel (a white rim and a warm ring, a soft shadow).
class PickPanel extends Control:
	var _ring: StyleBoxFlat
	var _face: StyleBoxFlat

	func _init() -> void:
		name = "EmotePanel"
		mouse_filter = Control.MOUSE_FILTER_STOP
		_ring = UIKit.box(Palette.HONEY_TINT_EDGE.lerp(Palette.TAN, 0.3), UIKit.R.lg + 2, 0)
		_ring.shadow_color = Color(Palette.SHADOW_DEEP, 0.3)
		_ring.shadow_size = 12
		_ring.shadow_offset = Vector2(0, 8)
		_face = UIKit.box(Palette.CARD, UIKit.R.lg, 3, Color.WHITE)
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_style_box(_ring, Rect2(Vector2.ZERO, size).grow(2))
		draw_style_box(_face, Rect2(Vector2.ZERO, size))


## One sticker in the panel (72 x 50): a soft cream well holding the sticker; greyed while the picker cools down.
class Cell extends Button:
	var id := ""
	var index := 0
	var home := Vector2.ZERO
	var k := 1.0                          # its pop-in progress (0..1)
	var _icon: TextureRect
	var _bg: StyleBoxFlat
	var _bg_on: StyleBoxFlat
	var _down := false
	var _grey := -1.0

	func _init(id_: String, index_: int) -> void:
		id = id_
		index = index_
		name = "Emote_" + id_
		flat = true
		focus_mode = Control.FOCUS_ALL
		var info := EmoteArt.info(id_)
		tooltip_text = str(info.get("name", id_))
		mouse_filter = Control.MOUSE_FILTER_STOP
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(s, empty)
		_bg = UIKit.box(Palette.SURFACE_2, UIKit.R.md, 2, Palette.ROW_EDGE.lerp(Palette.TAN, 0.25))
		_bg_on = UIKit.box(Palette.HONEY_TINT.lerp(Color.WHITE, 0.35), UIKit.R.md, 2, Palette.HONEY_TINT_EDGE)
		_icon = TextureRect.new()
		_icon.texture = EmotePicker.cropped(EmoteArt.icon(id_))
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon.material = EmotePicker.grey_material()
		add_child(_icon)
		button_down.connect(func(): _down = true; pose(k))
		button_up.connect(func(): _down = false; pose(k))
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		resized.connect(_fit)

	func _fit() -> void:
		_icon.position = Vector2(3, 4)
		_icon.size = size - Vector2(6, 8)

	## Its pop-in pose: from the left, small and clear, to its place (u 0..1, a small overshoot).
	func pose(u: float) -> void:
		k = u
		var e := EmotePicker._back_out(u, 1.2)
		var press := 0.9 if _down else 1.0
		scale = Vector2.ONE * lerpf(0.6, 1.0, e) * press
		position = home + Vector2(-10.0 * (1.0 - e), 0)
		modulate.a = clampf(u * 1.8, 0.0, 1.0) * (1.0 - 0.25 * maxf(_grey, 0.0))

	func set_grey(g: float) -> void:
		if g == _grey:
			return
		_grey = g
		(_icon.material as ShaderMaterial).set_shader_parameter("grey", g)
		pose(k)

	func _draw() -> void:
		var hot := (is_hovered() or (has_focus() and _kbd())) and _grey <= 0.0
		draw_style_box(_bg_on if hot else _bg, Rect2(Vector2.ZERO, size))
		if has_focus() and _kbd():
			var st := UIKit.box(Color.TRANSPARENT, UIKit.R.md + 2, 2, Palette.PEACH.darkened(0.1))
			st.draw_center = false
			draw_style_box(st, Rect2(Vector2.ZERO, size).grow(2))

	func _kbd() -> bool:
		var p := get_parent().get_parent() as EmotePicker if get_parent() else null
		return p != null and p._kbd
