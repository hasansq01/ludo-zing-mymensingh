class_name MatchLook
extends RefCounted
## The game look (GameUI) for the in-match HUD of Ludo and Snakes & Ladders: the pieces drawn over the 3D board share
## one dark café vocabulary with Home's top bar: dark chips with a gold rim (the pause / gear buttons, the event line,
## pills, the progress pill), wood seat cards framed in the player's colour, light player-colour names, outlined
## display type for names and numbers, and a small game card (GameUI.card_style) for the prompts over the board.
## Colours come from Palette (GL_* and the player colours).

const CHIP_A := 0.9                      ## the dark chips' opacity (the board shows a hair through, like Home's chips)


## A dark café chip: GL_CHIP_BG with a 2 px gold rim and a soft shadow (Home's top-bar chips).
static func chip_box(r := 14, rim := Palette.GL_CHIP_RIM, border := 2, a := CHIP_A) -> StyleBoxFlat:
	var s := UIKit.box(Color(Palette.GL_CHIP_BG, a), r, border, rim)
	s.corner_detail = 10
	s.anti_aliasing = true
	s.shadow_color = Color(0, 0, 0, 0.28)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s

## A player's colour for a name on the dark ground (the seat colour, lifted until it reads).
static func name_color(c: int) -> Color:
	c = posmod(c, 4)
	var col: Color = Palette.PLAYER[c]
	return col.lerp(Color.WHITE, [0.3, 0.32, 0.08, 0.36][c])

## The ink name colour PlayerTile.name_color(c) (for cream) -> the light one, inside BBCode written for cream.
static func relight(bb: String) -> String:
	for c in 4:
		bb = bb.replace("#" + PlayerTile.name_color(c).to_html(false), "#" + name_color(c).to_html(false))
	return bb

## Outlined display type (Lilita One, the dark outline).
static func outlined(t: String, fs: int, col := Color.WHITE, outline := 2, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	return GameUI.outlined(t, fs, col, outline, align)

## A square HUD button (pause, back, gear) as a dark chip with a gold-rimmed game icon; presses in a little.
static func icon_button(kind: String, px := 48) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(px, px)
	b.size = Vector2(px, px)
	var st := chip_box(16)
	UIKit.pad(st, 0)
	var pr := chip_box(16)
	pr.bg_color = Color(Palette.GL_CHIP_BG.darkened(0.35), CHIP_A)
	pr.shadow_size = 2
	UIKit.pad(pr, 0)
	for k in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	for k in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(k, pr)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := TextureRect.new()
	ic.texture = icon(kind)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2.ONE * round(px * (0.66 if kind == "gear" else 0.6))
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(ic)
	b.add_child(c)
	b.button_down.connect(func(): b.pivot_offset = b.size / 2; b.scale = Vector2(0.94, 0.94))
	b.button_up.connect(func(): b.scale = Vector2.ONE)
	UIKit.wire_press(b)
	return b

static var _icons := {}

## The HUD icons in the Home icon style (a gold gradient with the dark outline): "pause", "back"; "gear" is Home's.
static func icon(kind: String) -> Texture2D:
	if kind == "gear":
		return UIKit.svg("res://assets/ui/home/hi_gear.svg")
	if _icons.has(kind):
		return _icons[kind]
	var hi := Palette.GL_GOLD_GLOW.to_html(false)
	var mid := Palette.GL_GOLD.to_html(false)
	var lo := Palette.GL_BTN_GOLD_LO.to_html(false)
	var ink := Palette.GL_INK.to_html(false)
	var grad := ('<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#%s"/>' % hi
		+ '<stop offset="0.5" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></linearGradient></defs>' % [mid, lo])
	var shape := ""
	if kind == "pause":
		shape = ('<rect x="11" y="8" width="10" height="32" rx="3.6" fill="url(#g)" stroke="#%s" stroke-width="2.6"/>' % ink
			+ '<rect x="27" y="8" width="10" height="32" rx="3.6" fill="url(#g)" stroke="#%s" stroke-width="2.6"/>' % ink
			+ '<rect x="13.6" y="11" width="2.6" height="11" rx="1.3" fill="#ffffff" opacity="0.55"/>'
			+ '<rect x="29.6" y="11" width="2.6" height="11" rx="1.3" fill="#ffffff" opacity="0.55"/>')
	else:                                    # back: a chunky chevron
		shape = ('<path d="M30 9L15 24l15 15" fill="none" stroke="#%s" stroke-width="11" stroke-linecap="round" stroke-linejoin="round"/>' % ink
			+ '<path d="M30 9L15 24l15 15" fill="none" stroke="url(#g)" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>')
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">%s%s</svg>' % [grad, shape]
	var img := Image.new()
	img.load_svg_from_string(svg, 3.0)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_icons[kind] = t
	return t

## The small game card for prompts over the board (pair up, I'm back, you finished): GameUI's popup card, tighter.
static func card(pad_h := 16.0, pad_v := 12.0) -> StyleBox:
	var s := GameUI.card_style()
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v + GameUI.CardStyle.LIP
	return s

## Two prompt buttons (GameUI buttons, side by side) wide enough for their upper-cased labels, the same width
## (at least `min_w`, at most `max_w`; a label longer than that steps its type down to 13 px): the face clips a label
## that doesn't fit, so the row grows or the type shrinks instead.
static func fit_buttons(a: Button, b: Button, min_w := 128.0, max_w := 172.0) -> void:
	var f := UIKit.font_display()
	var w := min_w
	for x: Button in [a, b]:
		if not x is GameUI.GameButton:
			continue
		var gb := x as GameUI.GameButton
		var fs: int = GameUI.SIZES[gb.size_name][1]
		var t := x.text.to_upper()
		while fs > 13 and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 30.0 > max_w:
			fs -= 1
		gb.label.add_theme_font_size_override("font_size", fs)
		w = maxf(w, minf(max_w, f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 30.0))
	a.custom_minimum_size.x = w
	b.custom_minimum_size.x = w

## A dark pill for one-line notes on the board ("Reconnecting…", "Mitu may roll again…"): a gold rim, cream text.
static func note_pill() -> StyleBoxFlat:
	var s := chip_box(UIKit.R.pill)
	UIKit.pad(s, UIKit.SPACE.md + 2, UIKit.SPACE.xs + 1)
	return s

## A label for a note pill: Nunito 900 in cream.
static func note_label(t := "") -> Label:
	var l := UIKit.label(t, UIKit.FS.body, Palette.GL_CREAM_RIM, UIKit.font_body(900))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A countdown disc (the server's turn timer on a seat): a dark disc with a gold rim, a ring in the seat colour that
## empties (red near the end) and the seconds in outlined display type. Drawn on `item` at m, radius r.
static func draw_timer(item: CanvasItem, m: Vector2, r: float, k: float, secs: int, c: int, late: bool) -> void:
	item.draw_circle(m + Vector2(0, 2), r + 1.5, Color(0, 0, 0, 0.35), true, -1.0, true)
	item.draw_circle(m, r + 1.5, Palette.GL_CHIP_RIM, true, -1.0, true)
	item.draw_circle(m, r, Palette.GL_CHIP_BG, true, -1.0, true)
	item.draw_arc(m, r - 3.0, 0.0, TAU, 40, Color(1, 1, 1, 0.14), 3.5, true)
	if k > 0.0:
		var col := Palette.GL_BTN_RED_HI if late else name_color(c)
		item.draw_arc(m, r - 3.0, -PI / 2.0, -PI / 2.0 + TAU * k, 40, col, 3.5, true)
	var f := UIKit.font_display()
	var t := str(secs)
	var fs := int(round(r * 1.05))
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := m + Vector2(-w / 2.0, fs * 0.36)
	item.draw_string_outline(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Palette.GL_INK)
	item.draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.GL_BTN_RED_HI if late else Color.WHITE)

## A rounded rect with a vertical gradient (top -> bottom), drawn on `item` as one convex polygon with vertex colours
## (for faces drawn in _draw, where a GamePanel can't go).
static func draw_grad_round(item: CanvasItem, rect: Rect2, r: float, top: Color, bottom: Color) -> void:
	r = minf(r, minf(rect.size.x, rect.size.y) / 2.0)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var corners := [[rect.position + Vector2(rect.size.x - r, r), -PI / 2.0], [rect.end - Vector2(r, r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI / 2.0], [rect.position + Vector2(r, r), PI]]
	for cr: Array in corners:
		for i in 9:
			var a: float = cr[1] + PI / 2.0 * i / 8.0
			var p: Vector2 = (cr[0] as Vector2) + Vector2(cos(a), sin(a)) * r
			pts.append(p)
			cols.append(top.lerp(bottom, clampf((p.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)))
	item.draw_polygon(pts, cols)

## The chunky gold game button drawn on `item` (GameUI's gold look: two lips, a gradient face); `down` presses it in.
## Returns the face rect (draw the content on it).
static func draw_gold_button(item: CanvasItem, rect: Rect2, r: float, down: bool, dim := false) -> Rect2:
	var lip := 4.0
	var lip2 := 3.0
	var sh := StyleBoxFlat.new()
	sh.bg_color = Palette.GL_GOLD_LIP2
	sh.set_corner_radius_all(int(r))
	sh.corner_detail = 10
	sh.anti_aliasing = true
	sh.shadow_color = Color(0, 0, 0, 0.3)
	sh.shadow_size = 6
	sh.shadow_offset = Vector2(0, 3)
	item.draw_style_box(sh, Rect2(rect.position + Vector2(0, lip + lip2), Vector2(rect.size.x, rect.size.y - lip - lip2)))
	var lp := sh.duplicate() as StyleBoxFlat
	lp.bg_color = Palette.GL_GOLD_LIP
	lp.shadow_size = 0
	var face_h := rect.size.y - lip - lip2
	var dy := (lip + lip2 - 2.0) if down else 0.0
	item.draw_style_box(lp, Rect2(rect.position + Vector2(0, dy + lip), Vector2(rect.size.x, face_h)))
	var face := Rect2(rect.position + Vector2(0, dy), Vector2(rect.size.x, face_h))
	var k := 0.7 if dim else 1.0
	draw_grad_round(item, face, r, Palette.GL_BTN_GOLD_HI * Color(k, k, k), Palette.GL_BTN_GOLD_LO * Color(k, k, k))
	return face

## A small dark tag ("CPU", "Bot", "Offline"): caps in cream on the ink colour.
static func tag(t: String, fs := 11) -> PanelContainer:
	var p := PanelContainer.new()
	var st := UIKit.box(Palette.GL_INK, UIKit.R.pill, 0, Color.TRANSPARENT)
	UIKit.pad(st, 5, 0)
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := UIKit.label(t, fs, Palette.GL_CREAM_RIM, UIKit.font_caps(900, 1), HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_constant_override("line_spacing", -2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p
