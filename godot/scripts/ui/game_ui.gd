class_name GameUI
extends RefCounted
## The game look's kit (Design canvas "Ludo Zing Game UI": Shop, Buying, Ranks, Profile, Home): one place for the
## pieces every restyled screen and popup uses, so they read as one game.
##   Popups: Sheet LOOK_GAME (super(title, width, closable, Sheet.LOOK_GAME)) wears card_style(): a dark café card
##     with a warm radial glow, a gold rim, a deep 3D lip and a drop shadow; the title is big outlined gold type (no
##     ribbon) and the X is the round red game X inside the corner.
##   Type: outlined() (Lilita One with a dark outline). Text on the dark ground: TEXT (white), SUB (cream), GOLD.
##   Buttons: button(text, look, size): a chunky gradient face with a lip (looks: gold, teal, red, cream, blue,
##     green, purple, wood); the Button's text shows on the face, upper-cased (set .text as usual).
##   Surfaces: tile() a wood tile (rows, stat boxes), chip() a dark pill with a gold rim, ShopSheet.filter_button()
##     for two-way / segmented choices.
## Colours come from Palette (GL_*); no colour literals in screens that the lint checks.

const TEXT := Color.WHITE
const SUB := Palette.GL_CREAM_TEXT             ## secondary text on the dark ground (#e7c7a6)
const GOLD := Palette.GL_TITLE                 ## titles, section heads (#ffd45e)
const INK := Palette.GL_INK                    ## outlines (#3b1a0c)
const BROWN := Palette.GL_BROWN_TEXT           ## text on gold / cream faces (#4a2212)

## look -> [face top, face bottom, lip, outer lip, text colour, text outline (transparent: none)]
const LOOKS := {
	gold = [Palette.GL_BTN_GOLD_HI, Palette.GL_BTN_GOLD_LO, Palette.GL_GOLD_LIP, Palette.GL_GOLD_LIP2, Palette.GL_BROWN_TEXT, Color(0, 0, 0, 0)],
	teal = [Palette.GL_BTN_TEAL_HI, Palette.GL_BTN_TEAL_LO, Palette.GL_TEAL_LIP, Palette.GL_TEAL_LIP2, Color.WHITE, Palette.GL_TEAL_LIP2],
	red = [Palette.GL_BTN_RED_HI, Palette.GL_BTN_RED_LO, Palette.GL_RED_LIP, Palette.GL_RED_LIP2, Color.WHITE, Palette.GL_RED_LIP2],
	cream = [Palette.GL_CREAM_HI, Palette.GL_CREAM_LO, Palette.GL_CREAM_LIP, Palette.GL_WOOD, Palette.GL_BROWN_TEXT, Color(0, 0, 0, 0)],
	blue = [Palette.GL_BLUE_HI, Palette.GL_BLUE_LO, Palette.GL_BLUE_LIP, Palette.GL_BLUE_LIP2, Color.WHITE, Palette.GL_BLUE_LIP2],
	green = [Palette.GL_GREEN_HI, Palette.GL_GREEN_LO, Palette.GL_GREEN_LIP, Palette.GL_GREEN_LIP2, Color.WHITE, Palette.GL_GREEN_LIP2],
	purple = [Palette.GL_PURPLE_HI, Palette.GL_PURPLE_LO, Palette.GL_PURPLE_LIP, Palette.GL_PURPLE_LIP2, Color.WHITE, Palette.GL_PURPLE_LIP2],
	wood = [Palette.GL_TILE_HI, Palette.GL_TILE_LO, Palette.GL_DOCK, Palette.GL_DOCK, Palette.GL_CREAM_TEXT, Color(0, 0, 0, 0)],
}
## size -> [height, font size, radius, lip, outer lip]
const SIZES := {
	xs = [32.0, 15, 11.0, 4.0, 0.0],   # on a card, beside a price button or the In use pill
	sm = [42.0, 17, 14.0, 4.0, 2.0],
	md = [54.0, 21, 16.0, 5.0, 3.0],
	lg = [66.0, 28, 20.0, 7.0, 4.0],
}


## A label in the display face (Lilita One) with the dark outline (`outline` px each side; 0: none).
static func outlined(text: String, fs: int, col := TEXT, outline := 3, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UIKit.label(text, fs, col, UIKit.font_display(), align)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline * 2)
		l.add_theme_color_override("font_outline_color", INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Body text on the dark ground (Nunito 800, cream by default).
static func text(t: String, fs: int = UIKit.FS.body, col := SUB, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UIKit.label(t, fs, col, UIKit.font_body(800), align)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A chunky game button: `look` (LOOKS) and `size` ("xs" | "sm" | "md" | "lg"); optional icon (a res:// path) left of the
## text. It fills its width (SIZE_EXPAND_FILL) unless the caller says otherwise.
static func button(t: String, look := "gold", size := "md", icon_path := "") -> GameButton:
	return GameButton.new(t, look, size, icon_path)

## The game look for an old UIKit button kind ("honey", "teal", "red", "white", "ghost", ...).
static func look_for(kind: String) -> String:
	match kind:
		"honey", "gold", "primary", "yellow", "orange":
			return "gold"
		"teal", "mint", "success":
			return "teal"
		"red", "danger", "coral":
			return "red"
		"blue", "info":
			return "blue"
		"green":
			return "green"
		"purple", "plum":
			return "purple"
	return "cream"

## A wood tile (rows, stat boxes, list items): a vertical brown gradient, a 2 px warm rim, radius r.
static func tile(r := 16.0, pad := 12.0) -> GamePanel:
	var p := GamePanel.vertical(Palette.GL_TILE_HI, Palette.GL_TILE_LO)
	p.radius = r
	p.border = 2.0
	p.border_color = Palette.GL_TILE_RIM
	p.pad = pad
	return p

## A dark pill with a gold rim and cream text ("New week in 2d 6h", tags).
static func chip(t: String, fs := 12) -> PanelContainer:
	var c := PanelContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UIKit.box(Palette.GL_CHIP_BG, 12, 2, Palette.GL_CHIP_RIM)
	st.content_margin_left = 10; st.content_margin_right = 10; st.content_margin_top = 3; st.content_margin_bottom = 4
	c.add_theme_stylebox_override("panel", st)
	var l := UIKit.label(t, fs, Palette.GL_CREAM_RIM, UIKit.font_body(900))
	l.name = "Text"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(l)
	return c

## The popup card (Sheet LOOK_GAME).
static func card_style() -> CardStyle:
	var s := CardStyle.new()
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 18
	s.content_margin_bottom = 20 + CardStyle.LIP
	return s


## A chunky gradient button (see GameUI.button). The face is a GamePanel; the Button's own text is invisible and a
## label on the face shows it upper-cased (kept in step on every redraw, so `b.text = ...` just works). Disabled:
## the face greys.
class GameButton extends Button:
	var look := "gold"
	var size_name := "md"
	var face: GamePanel
	var label: Label
	var icon_rect: TextureRect
	var _row: HBoxContainer
	var _shown := ""

	func _init(t: String, look_ := "gold", size_ := "md", icon_path := "") -> void:
		look = look_
		size_name = size_
		text = t
		focus_mode = Control.FOCUS_NONE
		flat = true
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for k in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(k, StyleBoxEmpty.new())
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
			add_theme_color_override(k, Color(0, 0, 0, 0))
		var c: Array = GameUI.LOOKS[look]
		var z: Array = GameUI.SIZES[size_name]
		if size_name == "xs":                    # the hidden Button text sets the width: measure it at the face's size
			add_theme_font_size_override("font_size", int(z[1]))
		face = GamePanel.vertical(c[0], c[1])
		face.name = "Face"
		face.radius = z[2]
		face.lip = z[3]
		face.lip_color = c[2]
		face.lip2 = z[4]
		face.lip2_color = c[3]
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(face)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_row = HBoxContainer.new()
		_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_row.add_theme_constant_override("separation", 8)
		_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.clip_contents = true                # a label too long for the face is cut at its edges, never spills
		add_child(_row)
		_place_row(false)
		if icon_path != "":
			icon_rect = UIKit.icon(icon_path, int(z[1]) + 8)
			icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_row.add_child(icon_rect)
		label = UIKit.label("", int(z[1]), c[4], UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
		label.name = "Text"
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if (c[5] as Color).a > 0.0:
			label.add_theme_constant_override("outline_size", 6 if size_name == "lg" else 4)
			label.add_theme_color_override("font_outline_color", c[5])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_child(label)
		custom_minimum_size.y = z[0]
		button_down.connect(func(): _place_row(true))
		button_up.connect(func(): _place_row(false))
		UIKit.wire_press(self)
		_sync()

	## The content rides on the face: pressed, it drops by the lip.
	func _place_row(down: bool) -> void:
		var z: Array = GameUI.SIZES[size_name]
		var lips: float = z[3] + z[4]
		_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_row.offset_left = 10.0
		_row.offset_right = -10.0
		_row.offset_top = (lips - 2.0) if down else 0.0
		_row.offset_bottom = -2.0 if down else -lips

	func _sync() -> void:
		var t := text.to_upper()
		if t != _shown:
			_shown = t
			label.text = t
			label.visible = t != ""
		face.modulate = Color(0.62, 0.6, 0.6) if disabled else Color.WHITE

	func _draw() -> void:
		_sync()


## The popup card: a drop shadow, the deep lip under it, the gold rim, and the face, a warm radial glow near the top
## fading to deep café brown (a polar mesh with vertex colours: no shader, so the sheet's pop / fade animations and
## modulate work as with any StyleBox).
class CardStyle extends StyleBox:
	const RADIUS := 26.0
	const RIM := 3.0
	const LIP := 7.0
	var _shadow: StyleBoxFlat
	var _lip: StyleBoxFlat
	var _rim: StyleBoxFlat

	func _init() -> void:
		_shadow = StyleBoxFlat.new()
		_shadow.bg_color = Color(0, 0, 0, 0)
		_shadow.set_corner_radius_all(int(RADIUS))
		_shadow.shadow_color = Color(0, 0, 0, 0.5)
		_shadow.shadow_size = 18
		_shadow.shadow_offset = Vector2(0, 10)
		_lip = StyleBoxFlat.new()
		_lip.bg_color = Palette.GL_CARD_LIP
		_lip.set_corner_radius_all(int(RADIUS))
		_lip.corner_detail = 12
		_lip.anti_aliasing = true
		_rim = StyleBoxFlat.new()
		_rim.bg_color = Palette.GL_CHIP_RIM
		_rim.set_corner_radius_all(int(RADIUS))
		_rim.corner_detail = 12
		_rim.anti_aliasing = true

	func _draw(ci: RID, rect: Rect2) -> void:
		_shadow.draw(ci, rect)
		_lip.draw(ci, rect)
		var top := Rect2(rect.position, Vector2(rect.size.x, maxf(1.0, rect.size.y - LIP)))
		_rim.draw(ci, top)
		var f := top.grow(-RIM)
		_face(ci, f, RADIUS - RIM)

	## The face: rounded rect outline points, rings toward a focal point near the top centre, colours by distance.
	static func _face(ci: RID, f: Rect2, r: float) -> void:
		if f.size.x < 2.0 or f.size.y < 2.0:
			return
		r = minf(r, minf(f.size.x, f.size.y) / 2.0)
		var outline := PackedVector2Array()
		var per := 10
		var corners := [[f.position + Vector2(f.size.x - r, r), -PI / 2.0], [f.end - Vector2(r, r), 0.0],
			[Vector2(f.position.x + r, f.end.y - r), PI / 2.0], [f.position + Vector2(r, r), PI]]
		for cr: Array in corners:
			for i in per + 1:
				var a: float = cr[1] + PI / 2.0 * i / float(per)
				outline.append((cr[0] as Vector2) + Vector2(cos(a), sin(a)) * r)
		var focal := Vector2(f.position.x + f.size.x * 0.5, f.position.y + minf(f.size.y * 0.22, 120.0))
		var reach := Vector2(f.size.x * 0.75, maxf(f.size.y * 0.7, 260.0))
		var rings := 7
		var pts := PackedVector2Array([focal])
		var cols := PackedColorArray([_grad(0.0)])
		for j in range(1, rings + 1):
			var k := j / float(rings)
			for p in outline:
				var q := focal + (p - focal) * k
				pts.append(q)
				cols.append(_grad(((q - focal) / reach).length()))
		var n := outline.size()
		var idx := PackedInt32Array()
		for i in n:
			idx.append_array([0, 1 + i, 1 + (i + 1) % n])
		for j in range(1, rings):
			var a0 := 1 + (j - 1) * n
			var a1 := 1 + j * n
			for i in n:
				var m := (i + 1) % n
				idx.append_array([a0 + i, a1 + i, a1 + m, a0 + i, a1 + m, a0 + m])
		RenderingServer.canvas_item_add_triangle_array(ci, idx, pts, cols)

	static func _grad(t: float) -> Color:
		t = clampf(t, 0.0, 1.0)
		if t < 0.45:
			return Palette.GL_CARD_GLOW.lerp(Palette.GL_CARD_FACE, t / 0.45)
		return Palette.GL_CARD_FACE.lerp(Palette.GL_CARD_DEEP, (t - 0.45) / 0.55)


# --- settings ---

## Keeps a GameButton's label on its face: the label's font shrinks (down to min_fs) while the upper-cased text is
## wider than the face, on every resize and redraw (long labels, Bangla). Below min_fs it is cut at the face's edge.
static func fit_button_text(b: GameButton, min_fs := 13) -> void:
	var full := int(SIZES[b.size_name][1])
	var fit := func() -> void:
		var avail := b.size.x - 22.0
		if b.icon_rect:
			avail -= b.icon_rect.size.x + 8.0
		if avail <= 0.0:
			return
		var font := b.label.get_theme_font("font")
		var t := b.text.to_upper()
		var edge := float(b.label.get_theme_constant("outline_size"))
		var fs := full
		while fs > min_fs and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + edge > avail:
			fs -= 1
		if b.label.get_theme_font_size("font_size") != fs:
			b.label.add_theme_font_size_override("font_size", fs)
	b.resized.connect(fit)
	b.draw.connect(fit)
