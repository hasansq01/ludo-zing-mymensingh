class_name SideButton
extends Control
## A lobby side button (web .side-btn): a glossy square colour tile with a white rim, a lip that presses, an icon,
## a halo caption under it (12 px caps over the 3D room), an optional countdown pill under the caption and the
## red notify badge on the top-right corner. Colours: a Palette.LOBBY pair [face, lip].
##
##   var b := SideButton.new("spin", "Spin", "side_spin", Palette.LOBBY.spin)
##   b.pressed.connect(func(id): ...)
##   b.set_badge("!")          # "" hides it; "3" for a count; "•" for a plain dot
##   b.set_countdown("13h 20m") # "" hides it
##   b.set_ready(false)         # cooling down: the tile greys out (still pressable)
##   b.shake()                  # a tap while not ready
##
## The control's size is the whole column (tile + caption + countdown); its width is WIDTH so captions never
## leave it: place it at least UIKit.SCREEN_GUTTER - (WIDTH - tile) / 2 from the screen edge.

signal pressed(id: String)

const WIDTH := 80.0

var id := ""
var tile := 60.0
var button: Button
var caption: Label
var countdown: PanelContainer
var badge: Label
var _cd_label: Label
var _icon: TextureRect
var _art: Control
var _caption_text := ""
var _shake_tw: Tween


func _init(id_: String, caption_text: String, icon_name: String, colors: Array = Palette.LOBBY.spin, tile_px := 60.0) -> void:
	id = id_
	tile = tile_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face: Color = colors[0]
	var lip: Color = colors[1]
	button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.size = Vector2(tile, tile)
	button.custom_minimum_size = Vector2(tile, tile)
	for k in ["normal", "hover", "disabled", "pressed", "hover_pressed", "focus"]:
		button.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	var art := TileArt.new()
	art.lip = lip
	art.face = face
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(art)
	_art = art
	_icon = UIKit.icon(icon_name, tile * 0.72)
	_icon.size = Vector2.ONE * tile * 0.72
	button.add_child(_icon)
	button.pressed.connect(func(): pressed.emit(id))
	button.button_down.connect(func(): _icon.position.y = _icon_y() + float(UIKit.LIP.lg - 1); art.down = true; art.queue_redraw())
	button.button_up.connect(func(): _icon.position.y = _icon_y(); art.down = false; art.queue_redraw())
	UIKit.wire_press(button)
	add_child(button)
	caption = UIKit.halo_label("", UIKit.FS.small)
	caption.add_theme_font_override("font", UIKit.font_caps(900, 1))
	caption.clip_text = true
	add_child(caption)
	_cd_label = UIKit.label("", UIKit.FS.small, Color.WHITE, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_CENTER)
	countdown = PanelContainer.new()
	var cst := UIKit.box(Palette.TOAST, UIKit.R.pill, 0, Color.TRANSPARENT)
	UIKit.pad(cst, 7, 0)
	countdown.add_theme_stylebox_override("panel", cst)
	countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	countdown.add_child(_cd_label)
	countdown.visible = false
	add_child(countdown)
	badge = UIKit.notify_badge("!")
	badge.visible = false
	add_child(badge)
	set_caption(caption_text)
	_layout()

## The caption under the tile (shown in caps). Shrinks to fit WIDTH, never below 12 px... the copy must be short.
func set_caption(t: String) -> void:
	_caption_text = t
	caption.text = t.to_upper()
	_layout()

## A countdown pill under the caption ("13h 20m", "3:53"); "" hides it.
func set_countdown(t: String) -> void:
	_cd_label.text = t
	countdown.visible = t != ""
	_layout()

## The notify badge: "" hides it, "!" / a count / "•".
func set_badge(t: String) -> void:
	badge.visible = t != ""
	if t != "":
		badge.text = t
		badge.size = badge.get_combined_minimum_size()
	_layout()

## Dims the tile (the thing is not ready) while keeping it pressable (it can explain why).
func set_ready(on: bool) -> void:
	_art.modulate = Color.WHITE if on else Color.WHITE.lerp(Palette.DISABLED_FACE, 0.45)
	_icon.modulate = Color.WHITE if on else Color(1, 1, 1, 0.75)

## A short side-to-side shake (a tap on something not ready yet: "not now"). Honours Reduce motion (no shake).
func shake() -> void:
	if not is_inside_tree() or Sheet.reduce_motion():
		return
	if _shake_tw and _shake_tw.is_valid():
		_shake_tw.kill()
	button.position.x = (WIDTH - tile) / 2.0
	var x0 := button.position.x
	_shake_tw = create_tween()
	for dx in [-6.0, 5.0, -4.0, 3.0, -1.5, 0.0]:
		_shake_tw.tween_property(button, "position:x", x0 + dx, 0.05).set_trans(Tween.TRANS_SINE)

func _icon_y() -> float:
	return (tile - UIKit.LIP.lg - _icon.size.y) / 2.0 + 1.0

func _layout() -> void:
	var bx := (WIDTH - tile) / 2.0
	button.position = Vector2(bx, 0)
	_icon.position = Vector2((tile - _icon.size.x) / 2.0, _icon_y())
	var y := tile + 3.0
	var fs: int = UIKit.FS.small
	caption.add_theme_font_size_override("font_size", fs)
	caption.position = Vector2(0, y)
	caption.size = Vector2(WIDTH, 18)
	y += 18.0
	if countdown.visible:
		countdown.size = countdown.get_combined_minimum_size()
		countdown.position = Vector2(round((WIDTH - countdown.size.x) / 2.0), y)
		y += countdown.size.y
	if badge.visible:
		badge.position = Vector2(bx + tile - badge.size.x + 7.0, -7.0)
	custom_minimum_size = Vector2(WIDTH, y)
	size = custom_minimum_size


## The tile itself, drawn in code (a StyleBoxFlat can't do a white rim over a lip of another colour): drop shadow,
## the lip under the face, the face with a 3 px white rim, and a gloss band over its top half. Pressed: the face
## moves down onto the lip.
class TileArt extends Control:
	var face := Color.WHITE
	var lip := Color.BLACK
	var down := false
	var _sb := {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _box(key: String, bg: Color, border := 0, border_color := Color.WHITE, r: int = UIKit.R.lg) -> StyleBoxFlat:
		if not _sb.has(key):
			var sb := StyleBoxFlat.new()
			sb.bg_color = bg
			sb.set_corner_radius_all(r)
			sb.corner_detail = 10
			sb.anti_aliasing = true
			if border > 0:
				sb.set_border_width_all(border)
				sb.border_color = border_color
			_sb[key] = sb
		return _sb[key]

	func _draw() -> void:
		var L: float = UIKit.LIP.lg + 1
		var d := L - 2.0 if down else 0.0
		var face_r := Rect2(Vector2(0, d), Vector2(size.x, size.y - L))
		var sh := _box("shadow", Palette.shadow(0.28))
		draw_style_box(sh, Rect2(Vector2(1, 4), size - Vector2(2, 0)))
		draw_style_box(_box("lip", lip, UIKit.BW.rim, Color.WHITE), Rect2(Vector2(0, L), Vector2(size.x, size.y - L)))
		draw_style_box(_box("face", face, UIKit.BW.rim, Color.WHITE), face_r)
		var g := _box("gloss", Palette.GLOSS, 0, Color.WHITE, UIKit.R.md - 2)
		draw_style_box(g, Rect2(face_r.position + Vector2(6, 5), Vector2(face_r.size.x - 12, face_r.size.y * 0.36)))
