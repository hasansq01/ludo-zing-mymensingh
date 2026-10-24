class_name Welcome
extends Control
## The first-run welcome over the café (index.html #welcome), shown once (Save.prefs.welcome_seen): the game logo
## with four bobbing pawns, then one warm card: a greeting, an optional name ("Your name"; empty keeps "You"), a
## pick of the free illustrated characters (Collection: Arif and Nadia, one row, the one in use first; the pawn and
## cup avatars are not mixed in: one art style) and "Let’s play". Both can be changed later in Profile / Shop.
## Later launches go splash -> home.

signal continued

const MAX_NAME := 14
const TILE := 76.0                       ## the biggest avatar tile (one row of free characters)

var safe_top := 0.0
var safe_bottom := 0.0
var name_edit: LineEdit
var play_button: Button
var picked := ""                         # the avatar id chosen here
var _logo: BrandLogo
var _pawns := []
var _col: VBoxContainer
var _card: PanelContainer
var _tiles := {}                         # avatar id -> AvatarPick
var _t := 0.0
var _kb := 0.0                           # virtual keyboard lift (UI px)

## The avatars offered on the welcome: the free illustrated characters, the one in use first.
static func free_avatars() -> Array:
	var out := []
	var on := Collection.equipped("avatar")
	for c: Dictionary in Collection.CHARS:
		if int(c.get("price", 0)) == 0:
			if c.id == on:
				out.push_front(str(c.id))
			else:
				out.append(str(c.id))
	return out

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_veil()
	_col = UIKit.vbox(UIKit.SPACE.md)
	_col.alignment = BoxContainer.ALIGNMENT_END
	add_child(_col)
	# logo with its pawns
	var logo_box := Control.new()
	logo_box.custom_minimum_size = Vector2(250, 208)
	logo_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_child(logo_box)
	_logo = BrandLogo.new()
	_logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_box.add_child(_logo)
	# index.html .w-pawn.p1..p4: left/top as fractions of the logo box, colours red, green, yellow, blue
	var spots := [[-0.10, 0.12, 0], [0.98, 0.04, 1], [-0.04, 0.78, 2], [0.94, 0.68, 3]]
	for k in 4:
		var p := UIKit.icon("res://assets/ui/w_pawn_mono.svg", 30)
		p.modulate = Palette.PLAYER[spots[k][2]]
		p.size = Vector2(30, 30)
		p.set_meta("spot", Vector2(spots[k][0], spots[k][1]))
		p.set_meta("delay", [0.0, -0.7, -1.3, -2.0][k])
		logo_box.add_child(p)
		_pawns.append(p)
	_col.add_child(UIKit.spacer())
	_card = _build_card()
	_col.add_child(_card)
	resized.connect(_layout)
	_layout()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.5)

## Soft cream-to-blush veil over the 3D room (index.html .welcome background) and a glow behind the logo.
func _veil() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(Palette.CARD, 0.5), Color(Palette.CARD, 0.2), Color(Palette.PEACH, 0.78)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0)
	gt.fill_to = Vector2(0.5, 1)
	var veil := TextureRect.new()
	veil.texture = gt
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var gg := Gradient.new()
	gg.colors = PackedColorArray([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var ggt := GradientTexture2D.new()
	ggt.gradient = gg
	ggt.fill = GradientTexture2D.FILL_RADIAL
	ggt.fill_from = Vector2(0.5, 0.22)
	ggt.fill_to = Vector2(0.5, 0.7)
	var glow := TextureRect.new()
	glow.texture = ggt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

func _build_card() -> PanelContainer:
	var card := PanelContainer.new()
	var st := (UIKit.surface("card") as StyleBoxFlat).duplicate() as StyleBoxFlat
	UIKit.pad(st, UIKit.PAD.card, UIKit.SPACE.lg)
	st.content_margin_top = UIKit.SPACE.lg + 2
	card.add_theme_stylebox_override("panel", st)
	card.custom_minimum_size = Vector2(UIKit.W.form, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var v := UIKit.vbox(UIKit.SPACE.md)
	card.add_child(v)
	var hello := UIKit.title("Welcome to the café!", UIKit.FS.h1)
	hello.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hello.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hello)
	var sub := UIKit.paragraph("Pick a name and a look. You can change both later in your profile.", UIKit.FS.body, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(sub)
	# name
	name_edit = LineEdit.new()
	name_edit.name = "Name"
	name_edit.max_length = MAX_NAME
	var cur := str(Save.profile.get("name", "You"))
	name_edit.text = "" if cur == "You" else cur
	name_edit.placeholder_text = "Your name"
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.custom_minimum_size = Vector2(0, UIKit.TAP + 4)
	name_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	name_edit.add_theme_font_override("font", UIKit.font_body(800))
	name_edit.add_theme_font_size_override("font_size", UIKit.FS.h3)
	name_edit.text_submitted.connect(func(_t: String): name_edit.release_focus())
	v.add_child(name_edit)
	# avatars: one centred row of the free characters
	var cap := UIKit.caption("Choose your avatar")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(UIKit.margin(cap, 0, UIKit.SPACE.xs, 0, 0))
	var ids := free_avatars()
	var eq := Collection.equipped("avatar")
	picked = eq if ids.has(eq) else str(ids[0])
	var per_row := maxi(1, mini(ids.size(), 4))
	var rows := UIKit.vbox(UIKit.SPACE.sm)
	v.add_child(rows)
	var row: HBoxContainer
	for k in ids.size():
		if k % per_row == 0:
			row = UIKit.hbox(UIKit.SPACE.lg)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			rows.add_child(row)
		var t := AvatarPick.new(str(ids[k]), TILE)
		t.pressed.connect(_pick.bind(str(ids[k])))
		row.add_child(t)
		_tiles[str(ids[k])] = t
	_pick(picked, false)
	v.add_child(UIKit.spacer())
	play_button = UIKit.btn("Let’s play", "honey", "lg")
	play_button.name = "Play"
	play_button.pressed.connect(_continue)
	v.add_child(play_button)
	var note := UIKit.label("No sign-up needed. Your progress saves automatically.", UIKit.FS.small, Palette.MUTED, UIKit.font_body(700), HORIZONTAL_ALIGNMENT_CENTER)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	return card

func _pick(id: String, fx := true) -> void:
	picked = id
	for k in _tiles:
		(_tiles[k] as AvatarPick).set_on(k == id)
	if fx:
		UIKit.pop_in(_tiles[id], 0.18)

## Saves the name (empty keeps "You") and the avatar, marks the welcome as seen and moves on.
func _continue() -> void:
	play_button.disabled = true
	name_edit.release_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
	var n := " ".join(name_edit.text.strip_edges().split(" ", false)).substr(0, MAX_NAME)
	Save.profile.name = n if n != "" else "You"
	Collection.equip("avatar", picked)
	Save.prefs.welcome_seen = true
	Save.save()
	continued.emit()

func _layout() -> void:
	var w := size.x
	var h := size.y
	var gut := float(UIKit.SCREEN_GUTTER)
	_col.set_anchors_preset(Control.PRESET_FULL_RECT)
	_col.offset_left = gut
	_col.offset_right = -gut
	_col.offset_top = safe_top + clampf(h * 0.04, 10, 40)
	_col.offset_bottom = -(safe_bottom + clampf(h * 0.03, 12, 32) + _kb)
	_card.custom_minimum_size.x = minf(UIKit.W.form, w - gut * 2)
	# avatar tiles shrink on narrow phones: up to 4 per row inside the card padding
	var inner := _card.custom_minimum_size.x - UIKit.PAD.card * 2
	var per := float(clampi(_tiles.size(), 1, 4))
	var px := clampf((inner - (per - 1.0) * UIKit.SPACE.lg) / per - 8.0, 40.0, TILE)
	for t in _tiles.values():
		(t as AvatarPick).set_px(px)
	var lw := clampf(minf(w * 0.72, (h - 560.0) * 1.15), 150.0, 280.0)
	(_logo.get_parent() as Control).custom_minimum_size = Vector2(lw, lw * 266.0 / 320.0)

## The pawns bob around the logo (index.html @keyframes bob, 2.6 s, staggered); the card rises over the keyboard.
func _process(delta: float) -> void:
	_t += delta
	for p in _pawns:
		var box: Control = p.get_parent()
		var s: Vector2 = p.get_meta("spot")
		var ph: float = (_t + float(p.get_meta("delay"))) / 2.6 * TAU
		p.position = Vector2(s.x * box.size.x, s.y * box.size.y + sin(ph) * 6.0)
	var kb := 0.0
	if name_edit and name_edit.has_focus() and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		var win := DisplayServer.window_get_size()
		if win.y > 0:
			kb = maxf(0.0, DisplayServer.virtual_keyboard_get_height() * size.y / float(win.y) - safe_bottom)
	if absf(kb - _kb) > 1.0:
		_kb = kb
		_layout()

## Fade out and free (the home screen is shown underneath).
func leave() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	await tw.finished
	queue_free()


## One avatar choice: the tile in a white mount; the chosen one gets the honey ring and a check.
class AvatarPick extends Button:
	var id := ""
	var on := false
	var _px := 56.0
	var _view: Control
	var _check: TextureRect

	func _init(id_: String, px: float) -> void:
		id = id_
		_px = px
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(px, px) + Vector2(8, 8)
		tooltip_text = str(Collection.avatar(id).get("name", ""))
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			add_theme_stylebox_override(s, empty)
		_view = Collection.make_avatar_of(id, Collection.DEFAULT_FRAME, px)
		_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_view.position = Vector2(4, 4)
		add_child(_view)
		_check = UIKit.icon("ic_check", 20)
		_check.size = Vector2(20, 20)
		_check.position = Vector2(px - 12, -2)
		_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_check.visible = false
		var bg := Panel.new()
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_theme_stylebox_override("panel", UIKit.box(Palette.TEAL, 999, 2, Color.WHITE))
		bg.size = Vector2(22, 22)
		bg.position = Vector2(-1, -1)
		bg.show_behind_parent = true
		_check.add_child(bg)
		add_child(_check)
		UIKit.wire_press(self, "select")
		pivot_offset = custom_minimum_size / 2.0

	func set_px(px: float) -> void:
		if absf(px - _px) < 0.5:
			return
		_px = px
		custom_minimum_size = Vector2(px, px) + Vector2(8, 8)
		_view.custom_minimum_size = Vector2(px, px)
		_view.size = Vector2(px, px)
		_check.position = Vector2(px - 12, -2)
		pivot_offset = custom_minimum_size / 2.0

	func set_on(v: bool) -> void:
		on = v
		_check.visible = v
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(1, 1), size - Vector2(2, 2))
		var st := UIKit.box(Palette.HONEY_TINT if on else Color(Palette.CARD, 0.0), int(UIKit.R.md + 4), UIKit.BW.rim if on else 0, Palette.HONEY)
		if on:
			draw_style_box(st, r)
