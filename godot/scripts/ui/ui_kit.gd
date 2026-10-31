class_name UIKit
extends RefCounted
## Design tokens (type, spacing, radii, borders, lips, shadows, sizes) and the shared widgets of the interface
## (index.html: Lilita One for display text, Nunito for body text; cozy rounded panels; glossy buttons with a 3D
## "lip" that presses down; the .x-btn close button; the .seg segmented control).
##
## Lists use ONE row card: UIKit.list_row(child, state) (states "", "on", "you", "empty"; see its doc). Fixed-height pm
## sheets use UIKit.H_SHEET. Sheet widths: W.form (single column) or W.catalog (grids, long lists).
##
## Colours come from Palette. Every button made here plays the "tap" sound and a light haptic when pressed
## (wire_press), unless the caller's own handler already played a sound in the same moment (like the web's global
## click handler). Styleboxes returned by surface() are SHARED and cached: duplicate() one before changing it.

# =====================================================================================================================
# Tokens
# =====================================================================================================================

## Type scale (px at the 390 px base). Minimum text anywhere is 12 (small/tag); labels 14; the status line 16.
## hero: big amounts and win numbers. title: sheet titles (title_sm on cards narrower than 340). h1: ribbon titles,
## greetings, item names in previews. h2: section headings. h3: list item titles. body_l: dialog text.
## body: notes, bullets, descriptions. label: row labels, names. small: secondary lines, captions. tag: caps tags.
const FS := {
	hero = 34, title = 28, title_sm = 24, h1 = 22, h2 = 20, h3 = 17,
	body_l = 16, status = 16, body = 14, label = 14, small = 12, tag = 12,
}
## Spacing scale for gaps and margins (4-point rhythm; xxs only for hairline gaps).
const SPACE := {xxs = 2, xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32}
## Inner padding of the standard surfaces.
const PAD := {card = 20, pane = 12, row = 12, tile = 8, chip = 6}
## Corner radii. Circles use size / 2. A nested radius = parent radius - padding (min 8).
const R := {xs = 6, sm = 10, md = 14, lg = 18, xl = 28, pill = 999}
## Border widths: hair (glass), line (cards, tiles), rim (selected state, rings), card (sheet frame).
const BW := {hair = 1, line = 2, rim = 3, card = 4}
## Bottom "lip" depths of pressable things. Pressed: the lip shrinks to 2 and the face moves down.
const LIP := {sm = 3, md = 4, lg = 5}
## Shadow tokens [size, offset_y, alpha of Palette.SHADOW] (web --shadow-sm, --shadow, --shadow-lg).
const SHADOWS := {none = [0, 0, 0.0], sm = [4, 2, 0.16], md = [8, 4, 0.20], lg = [16, 10, 0.28]}
## Button size presets: fs = font size, h = visual height, lip, r = radius, pad = side padding, display = Lilita
## (else Nunito 900). Every preset's touch target is at least TAP tall: xs and sm draw a smaller face centred in a
## 48 px tall button. lg: the single forward action of a screen (Start game, Play again). md: dialog actions.
## sm: secondary actions in cards. xs: dense item buttons (Buy, Use, Copy).
const BTN := {
	xs = {fs = 14, h = 36, lip = 3, r = 10, pad = 10, display = false},
	sm = {fs = 17, h = 44, lip = 3, r = 12, pad = 14, display = true},
	md = {fs = 20, h = 50, lip = 4, r = 14, pad = 18, display = true},
	lg = {fs = 24, h = 58, lip = 5, r = 16, pad = 22, display = true},
}
## Common widths of sheets / dialogs and control heights.
const W := {dialog = 330, form = 360, catalog = 400, wide = 440}
const H := {xs = 36, sm = 44, md = 50, lg = 58, xl = 64}
## Minimum touch target (px at the 390 base).
const TAP := 48
## Side gutter of a sheet against the screen edge (replaces every "vp.x - 24").
const GUTTER := 12
## Inset of HUD controls from the screen edges.
const SCREEN_GUTTER := 16

const ICON_DIR := "res://assets/ui/"

## Button kinds: [face, lip, text, text outline, rim (2 px border drawn over the face edge)].
## honey: the primary action. gold: shop item buy. teal: positive secondary / Pass & Play. red: destructive.
## ghost: secondary (Home, No thanks, Cancel). white: small white chip buttons (View, Copy). off: a flat chip for a
## state that can't be pressed (In use, Locked, Need 2.5K).
const KINDS := {
	honey = [Palette.HONEY, Palette.HONEY_LIP, Palette.ON_HONEY, Color(0, 0, 0, 0), Palette.HONEY_RIM],
	gold = [Palette.GOLD, Palette.GOLD_DEEP, Palette.ON_HONEY, Color(0, 0, 0, 0), Color.WHITE],
	teal = [Palette.TEAL, Palette.TEAL_LIP, Color.WHITE, Color(Palette.TEAL_OUTLINE, 0.6), Color.WHITE],
	red = [Palette.RED, Palette.RED_DEEP, Color.WHITE, Color(Palette.RED_OUTLINE, 0.6), Color.WHITE],
	ghost = [Color.WHITE, Palette.LIP_CREAM, Palette.INK, Color(0, 0, 0, 0), Palette.ROW_EDGE],
	white = [Color.WHITE, Palette.LIP_CREAM, Palette.INK, Color(0, 0, 0, 0), Palette.LINE_SOLID],
	off = [Palette.CHIP, Palette.TAB_HOVER, Palette.SUB, Color(0, 0, 0, 0), Color(0, 0, 0, 0)],
}

static var _display: Font
static var _body := {}
static var _caps := {}
static var _bangla := {}
static var _under := []                 # [FontVariation, Bangla weight] pairs: the faces with a Bangla fallback (_bangla_under)
static var _theme: Theme
static var _tex := {}
static var _surf := {}


# =====================================================================================================================
# Fonts
# =====================================================================================================================

## Lilita One: titles, buttons, the logo, big numbers (Bangla in Baloo Da 2, see bangla_font).
static func font_display() -> Font:
	if _display == null:
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/LilitaOne.woff2")
		_bangla_under(fv, 0)
		_display = fv
	return _display

## Nunito at a weight (500, 700, 800, 900; it is a variable font). tnum = tabular figures, so counting numbers and
## clocks don't wobble. Cached.
static func font_body(weight := 700, tnum := false) -> Font:
	var key := weight * 2 + (1 if tnum else 0)
	if not _body.has(key):
		var ts := TextServerManager.get_primary_interface()
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/Nunito.woff2")
		fv.variation_opentype = {ts.name_to_tag("wght"): weight}
		if tnum:
			fv.opentype_features = {ts.name_to_tag("tnum"): 1}
		_bangla_under(fv, weight)
		_body[key] = fv
	return _body[key]

## Letter-spaced Nunito for caps tags and eyebrows (pass upper-cased text; tag/eyebrow/caps_label do it).
## spacing = extra px between glyphs. Cached. Built straight on the Nunito file (not on font_body's FontVariation:
## a nested variation drops the inner wght axis, so caps rendered at the default weight instead of 900).
static func font_caps(weight := 900, spacing := 1) -> Font:
	var key := "%d_%d" % [weight, spacing]
	if not _caps.has(key):
		var ts := TextServerManager.get_primary_interface()
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/Nunito.woff2")
		fv.variation_opentype = {ts.name_to_tag("wght"): weight}
		fv.spacing_glyph = spacing
		_bangla_under(fv, weight)
		_caps[key] = fv
	return _caps[key]

## The Bangla under the Latin faces (neither Lilita One nor Nunito has Bengali glyphs): weight 0 = Baloo Da 2
## ExtraBold under Lilita's titles, else Noto Sans Bengali at the same weight as the Nunito above it, so mixed
## Latin / Bangla text keeps one look. Both are OFL (assets/fonts/OFL-*.txt), cut to the Bengali block with
## pyftsubset (layout features kept: the advanced text server shapes the conjuncts and vowel signs). Their lines
## are a little trimmed (spacing_top / spacing_bottom): Bengali fonts are taller, and a Bangla line would
## otherwise stand ~3 px taller than a Latin one in the same Label. Cached. A FontVariation keeps its own
## fallbacks: one built on another font only hands the base font's fallbacks on, without the weight.
static func bangla_font(weight := 700) -> Font:
	if not _bangla.has(weight):
		var fv := FontVariation.new()
		if weight <= 0:
			fv.base_font = load("res://assets/fonts/BalooDa2.woff2")
		else:
			fv.base_font = load("res://assets/fonts/NotoSansBengali.woff2")
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		fv.spacing_top = -3
		fv.spacing_bottom = -3
		_bangla[weight] = fv
	return _bangla[weight]

## Puts the Bangla face under a Latin one, only while the interface is in Bangla: a line's height is the tallest
## font of its fallback chain, and Baloo Da 2 under Lilita One made every English title ~45 % taller (28 px: 48
## px instead of 33) even with no Bangla in it. sync_bangla() follows a language switch.
static func _bangla_under(fv: FontVariation, weight: int) -> void:
	_under.append([fv, weight])
	fv.fallbacks = [bangla_font(weight)] if L10n.is_bn() else []

## After the interface language changes (L10n.apply): the Bangla fallbacks on, or off for English.
static func sync_bangla() -> void:
	var bn := L10n.is_bn()
	for u: Array in _under:
		(u[0] as FontVariation).fallbacks = [bangla_font(int(u[1]))] if bn else []

## The app-wide theme (cached; don't modify it): Nunito body text in plum, no focus rings over the cozy buttons,
## cream LineEdits with a honey focus ring, slim honey scrollbars.
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font_body(700)
	t.default_font_size = FS.body_l
	t.set_color("font_color", "Label", Palette.INK)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", box(Palette.CARD, 24))
	var line := box(Color.WHITE, R.md, BW.line, Palette.LINE_SOLID)
	line.content_margin_left = 14; line.content_margin_right = 14
	t.set_stylebox("normal", "LineEdit", line)
	var focus := box(Color.WHITE, R.md, BW.rim, Palette.HONEY)
	focus.content_margin_left = 14; focus.content_margin_right = 14
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("font_color", "LineEdit", Palette.INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(Palette.MUTED, 0.8))
	t.set_color("caret_color", "LineEdit", Palette.INK)
	t.set_font_size("font_size", "LineEdit", 18)
	_scroll_styles(t)
	_theme = t
	return t


# =====================================================================================================================
# Styles
# =====================================================================================================================

## A rounded StyleBoxFlat. shadow: a px size (old form; offset = size * 0.45, colour shadow_color) or a SHADOWS
## token name ("sm", "md", "lg"; shadow_color is then ignored). Content margins default to 12 x 10.
static func box(bg: Color, radius := 18, border := 0, border_color := Color.TRANSPARENT, shadow: Variant = 0, shadow_color := Color(0.29, 0.17, 0.24, 0.18)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.corner_detail = 10
	s.anti_aliasing = true
	if border > 0:
		s.set_border_width_all(border)
		s.border_color = border_color
	if shadow is String:
		shade(s, shadow)
	elif int(shadow) > 0:
		s.shadow_size = int(shadow)
		s.shadow_color = shadow_color
		s.shadow_offset = Vector2(0, int(shadow) * 0.45)
	pad(s, 12, 10)
	return s

## Apply a SHADOWS token ("none", "sm", "md", "lg") to a stylebox. Returns it.
static func shade(s: StyleBoxFlat, token := "sm", color := Palette.SHADOW) -> StyleBoxFlat:
	var t: Array = SHADOWS.get(token, SHADOWS.sm)
	s.shadow_size = int(t[0])
	s.shadow_offset = Vector2(0, float(t[1]))
	s.shadow_color = Color(color, float(t[2]))
	return s

## Set a stylebox's content margins: h left/right, v top/bottom (v < 0: same as h). Returns it.
static func pad(s: StyleBox, h: float, v := -1.0) -> StyleBox:
	if v < 0:
		v = h
	s.content_margin_left = h; s.content_margin_right = h
	s.content_margin_top = v; s.content_margin_bottom = v
	return s

## Glass chip over the 3D room (index.html --panel): GLASS, 1 px line, shadow-sm.
static func glass(radius := 16) -> StyleBoxFlat:
	var s := box(Palette.GLASS, radius, BW.hair, Palette.LINE)
	return shade(s, "sm")

## A cached, SHARED surface style (duplicate() before changing it). kinds:
##   "card" sheet card (CARD, r xl, white 2 px, shadow lg, pad 20)
##   "row" cream row card (ROW, ROW_EDGE, lip 4; use list_row())   "tile" white stat tile (ROW_EDGE, lip 4)
##   "pane" .pm-inner pane (PANE, PANE_EDGE 3 px)       "pane_open_top" the same with an open top (under tabs)
##   "item" catalog tile (SURFACE_2, LINE; on: GOLD rim + gold glow)   "bubble" info bubble card
##   "glass" HUD glass   "night" lobby dark glass   "chip" CHIP well   "well" dimmed CHIP_DIM well
##   "toast" the .toast pill
## on: the selected / equipped look (item, tile, row). narrow: tighter padding for cards under 340 px.
static func surface(kind: String, on := false, narrow := false) -> StyleBoxFlat:
	var key := "%s|%s|%s" % [kind, on, narrow]
	if _surf.has(key):
		return _surf[key]
	var s: StyleBoxFlat
	var p: float = PAD.row
	match kind:
		"card":
			s = shade(box(Palette.CARD, R.xl, BW.line, Color.WHITE), "lg", Palette.SHADOW_DEEP)
			p = PAD.card if not narrow else 14
		"row":
			s = box(Palette.ROW, R.lg - 2, BW.line, Palette.GOLD if on else Palette.ROW_EDGE)
			s.border_width_bottom = LIP.md
		"tile":
			s = box(Color.WHITE, R.md, BW.line, Palette.GOLD if on else Palette.ROW_EDGE)
			s.border_width_bottom = LIP.md
			p = PAD.tile
		"pane", "pane_open_top":
			s = box(Palette.PANE, R.lg, BW.rim, Palette.PANE_EDGE)
			p = PAD.pane
			if kind == "pane_open_top":
				s.border_width_top = 0
				s.corner_radius_top_left = 0; s.corner_radius_top_right = 0
		"item":
			s = box(Palette.SURFACE_2, R.lg, BW.line, Palette.LINE)
			if on:
				s.set_border_width_all(BW.rim)
				s.border_color = Palette.GOLD
				s.shadow_size = 8; s.shadow_color = Palette.GLOW_GOLD; s.shadow_offset = Vector2.ZERO
			p = PAD.tile if not narrow else PAD.chip
		"bubble":
			s = shade(box(Palette.CARD, R.lg, BW.rim, Palette.TAN), "md")
		"glass":
			s = glass(16)
			p = PAD.tile
		"night":
			s = box(Palette.NIGHT_GLASS, R.lg, BW.line, Color(1, 1, 1, 0.25))
			p = PAD.tile
		"chip":
			s = box(Palette.CHIP, R.sm)
			p = PAD.chip
		"well":
			s = box(Palette.CHIP_DIM, R.md)
			p = PAD.chip
		"toast":
			s = shade(box(Palette.TOAST, R.pill), "md")
			pad(s, 18, 10)
			_surf[key] = s
			return s
		_:
			push_warning("UIKit.surface: unknown kind %s" % kind)
			s = box(Palette.CARD, R.lg)
	if narrow and kind != "card":
		p = maxf(4.0, p - 4.0)
	pad(s, p)
	if kind == "row" or kind == "tile":
		s.content_margin_bottom += LIP.md - BW.line
	_surf[key] = s
	return s

## A PanelContainer with a surface() style, optionally holding `child`.
static func panel(kind: String, child: Control = null, on := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", surface(kind, on))
	p.set_meta("kit_surface", kind)
	if child:
		p.add_child(child)
	return p

## THE list row (rewards, store, leaderboard, lobby members, quick-match rows, tables, achievements, credits): the cream
## ROW card, 2 px ROW_EDGE border, 4 px lip, radius 16, padding 12 (PAD.row). Put rows 8 px apart (SPACE.sm) in a
## vbox(SPACE.sm). state:
##   ""       the normal row (ROW / ROW_EDGE / lip 4)
##   "on"     gold rim: selected, in use, ready to claim
##   "you"    a player-colour rim, 3 px: you in a list (pass `rim`, default Palette.TEAL)
##   "empty"  an empty seat / slot: CHIP at 55%, LINE_STRONG border, no lip, 12 px content margin all round
## Returns a PanelContainer holding `child` (an HBox, usually: icon 40-44, title h3 + note, trailing sm button or pill).
## Switch the state later with set_row_state(). Don't build a white / SURFACE_2 box of your own for a list row.
##   list.add_child(UIKit.list_row(row_hbox))
##   list.add_child(UIKit.list_row(row_hbox, "you", Palette.CAT.coins[0]))
static func list_row(child: Control = null, state := "", rim := Color.TRANSPARENT) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_meta("kit_surface", "row")
	p.add_theme_stylebox_override("panel", row_style(state, rim))
	if child:
		p.add_child(child)
	return p

## The list_row() look of a state, cached (SHARED: duplicate() before changing it).
static func row_style(state := "", rim := Color.TRANSPARENT) -> StyleBoxFlat:
	match state:
		"on":
			return surface("row", true)
		"you":
			var c := rim if rim.a > 0.0 else Palette.TEAL
			var key := "row_you|%s" % c.to_html()
			if not _surf.has(key):
				var s := surface("row").duplicate() as StyleBoxFlat
				s.border_color = c
				for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT]:
					s.set_border_width(side, BW.rim)
				s.border_width_bottom = LIP.md
				s.content_margin_left += 1; s.content_margin_right += 1; s.content_margin_top += 1
				_surf[key] = s
			return _surf[key]
		"empty":
			if not _surf.has("row_empty"):
				var s := box(Color(Palette.CHIP, 0.55), R.lg - 2, BW.line, Palette.LINE_STRONG)
				pad(s, PAD.row)
				_surf["row_empty"] = s
			return _surf["row_empty"]
		_:
			return surface("row")

## Switch a list_row() to another state.
static func set_row_state(p: PanelContainer, state: String, rim := Color.TRANSPARENT) -> void:
	p.add_theme_stylebox_override("panel", row_style(state, rim))

## Full height of the fixed-height pm sheets (Profile, Shop, Leaderboard, How to play): one token.
const H_SHEET := 680

## Switch a panel() between its normal and on look (cached styleboxes, no allocation).
static func set_on(p: PanelContainer, kind: String, on: bool) -> void:
	p.add_theme_stylebox_override("panel", surface(kind, on))


# =====================================================================================================================
# Text and icons
# =====================================================================================================================

static func label(text: String, size := 16, color := Palette.INK, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font if font else font_body(800))
	l.horizontal_alignment = align
	return l

## A Lilita title, centred.
static func title(text: String, size := 30, color := Palette.INK) -> Label:
	return label(text, size, color, font_display(), HORIZONTAL_ALIGNMENT_CENTER)

## A wrapping body paragraph (Nunito 700).
static func paragraph(t: String, size: int = FS.body, color := Palette.INK, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(t, size, color, font_body(700), align)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## THE section label of the interface: the heading over a group of rows or a grid inside a sheet ("Sound &
## vibration", "Your colour", "Characters", "Ludo vs computer"). Sentence case, Nunito 900, 14 px, RUST. One style
## everywhere (re-audit #12); caps are only for an eyebrow above a title (eyebrow()).
static func caption(t: String, color := Palette.RUST) -> Label:
	return label(t, FS.label, color, font_body(900))

## An overline ABOVE a title or a name ("LUDO ROOM" over "Pastel Dream Room", "SNAKES & LADDERS" over a sheet
## title): small letter-spaced caps in CREMA. Write the text in sentence case; it is upper-cased here.
static func eyebrow(t: String, color := Palette.CREMA) -> Label:
	return caps_label(t, color, FS.small)

## Unboxed caps text (kickers, states such as "Claimed"): upper-cased, letter-spaced Nunito 900.
static func caps_label(t: String, color := Palette.INK, size: int = FS.tag) -> Label:
	return label(t.to_upper(), size, color, font_caps(900, 1))

## Text over the 3D room: white with a soft dark halo so it reads on any background.
static func halo_label(t: String, size := 16) -> Label:
	var l := label(t, size, Color.WHITE, font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Palette.HALO)
	l.add_theme_constant_override("outline_size", 6)
	return l

## A texture from assets/ui: svg("ic_gear") or svg("res://assets/ui/ic_gear.svg"). Mipmapped and cached, so it
## stays crisp at any size (icons are drawn on a 192 px canvas). Null (with a warning) when the file is missing.
static func svg(name: String) -> Texture2D:
	var path := name if name.begins_with("res://") else ICON_DIR + name + ".svg"
	if _tex.has(path):
		return _tex[path]
	var t := load(path) as Texture2D
	if t == null:
		push_warning("UIKit.svg: missing %s" % path)
		return null
	var img := t.get_image()
	if img and not img.is_compressed():
		if not img.has_mipmaps():
			img.generate_mipmaps()
		t = ImageTexture.create_from_image(img)
	_tex[path] = t
	return t

## An icon TextureRect (ignores the mouse). path: a res:// path or an assets/ui name ("ic_star").
static func icon(path: String, size := 24.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = svg(path) if path.ends_with(".svg") or not path.begins_with("res://") else load(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.custom_minimum_size = Vector2(size, size)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

## A tinted icon: for the white glyphs (ic_close, ic_check) any colour works; plum icons can only get darker.
static func glyph(name: String, size := 24.0, color := Palette.INK) -> TextureRect:
	var t := icon(name, size)
	t.self_modulate = color
	return t

## The colour-blind symbol of colour index c (Palette.SYMBOL: circle, square, triangle, diamond).
static func symbol(c: int, size := 16.0) -> TextureRect:
	return icon("sym_" + str(Palette.SYMBOL[posmod(c, 4)]), size)

## A list bullet: a round dot aligned with the first line of FS.body text.
static func bullet(color := Palette.INK, dot := 5.2) -> Control:
	var b := Control.new()
	b.custom_minimum_size = Vector2(dot + 10, dot + 8)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.draw.connect(func(): b.draw_circle(Vector2(dot / 2 + 3, 10.0), dot / 2, color, true, -1.0, true))
	return b

## A bullet + wrapping text row (how-to lists, info bubbles).
static func bullet_row(t: String, size: int = FS.body, color := Palette.INK) -> HBoxContainer:
	var row := hbox(SPACE.xxs)
	row.add_child(bullet(color))
	var l := paragraph(t, size, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


# =====================================================================================================================
# Layout
# =====================================================================================================================

static func margin(child: Control, l := 0, t := 0, r := 0, b := 0) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	m.add_child(child)
	return m

static func vbox(gap := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v

static func hbox(gap := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	return h

## A grid with equal horizontal and vertical gaps.
static func grid(cols: int, gap: int = SPACE.md) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", gap)
	g.add_theme_constant_override("v_separation", gap)
	return g

## An empty control that takes the free space of its box container.
static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## A vertical-only scroll area with a slim honey scrollbar (replaces HowToSheet.make_scroll).
static func scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.scroll_deadzone = 8
	var bar := sc.get_v_scroll_bar()
	var track := pad(box(Color(Palette.MUTED, 0.14), 4), 3, 0)
	var grab := pad(box(Palette.HONEY, 4), 3, 0)
	var grab_hi := pad(box(Palette.HONEY_LIP, 4), 3, 0)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hi)
	bar.add_theme_stylebox_override("grabber_pressed", grab_hi)
	sc.add_theme_constant_override("scrollbar_h_separation", 6)
	sc.add_theme_constant_override("scrollbar_v_separation", 6)
	TouchScroll.attach(sc)          # drags scroll even when they start on a button, toggle or slider
	return sc

## Fade + pop a control in (sheets, cards, toasts). Returns the tween (a sheet stops it when it is covered).
static func pop_in(c: Control, sec := 0.22) -> Tween:
	c.pivot_offset = c.size / 2
	c.modulate.a = 0.0
	c.scale = Vector2(0.92, 0.92)
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, sec * 0.8)
	tw.tween_property(c, "scale", Vector2.ONE, sec)
	return tw


# =====================================================================================================================
# Press feedback
# =====================================================================================================================

## Make a button give the tap feedback once per press: Haptics.tap() and Sound.sfx(sound), the sound skipped when
## any other sound played in the last 120 ms (the caller's handler played its own, e.g. "select"). Connected once
## per button (safe to call again). Runs deferred, after the caller's pressed handlers.
static func wire_press(b: BaseButton, sound := "tap") -> void:
	if b.has_meta("kit_fx"):
		b.set_meta("kit_fx", sound)
		return
	b.set_meta("kit_fx", sound)
	# The feedback still plays deferred (after the press handlers), but only the sound name is deferred: a deferred
	# lambda capturing `b` would outlive a button freed by its own press ("Lambda capture at index 0 was freed").
	b.pressed.connect(func() -> void:
		press_fx.call_deferred(str(b.get_meta("kit_fx", sound))))

## The tap feedback itself (for custom controls that are not Buttons): light haptic + sound (see wire_press).
static func press_fx(sound := "tap") -> void:
	Haptics.tap()
	var tree := Engine.get_main_loop() as SceneTree
	var snd: Node = tree.root.get_node_or_null("Sound") if tree and tree.root else null
	if snd == null or sound == "":
		return
	var last: Variant = snd.get("_last_at")
	if last is Dictionary:
		var newest := -100000
		for v in (last as Dictionary).values():
			newest = maxi(newest, int(v))
		if Time.get_ticks_msec() - newest < 120:
			return
	snd.sfx(sound)

## A tap on something locked, disabled, unaffordable or not ready: the error sound and haptic, a short "bad" toast
## (over the sheet's card when `host` is in a sheet) and a little shake of `shaker`. Nothing changes layout.
static func deny(host: Node, text: String, shaker: Control = null, sec := 1.8) -> void:
	sfx("error")
	Haptics.error()
	shake(shaker)
	if host == null or not host.is_inside_tree():
		return
	var near: Control = null
	var n := host
	while n != null:
		if n is Sheet:
			near = (n as Sheet).card
			break
		n = n.get_parent()
	Toast.show(host, text, near, sec, "bad")

## A short side-to-side shake of a control (none with Reduce motion). Its position comes back to where it was.
static func shake(c: Control) -> void:
	if c == null or not c.is_inside_tree() or Sheet.reduce_motion():
		return
	if c.has_meta("shake_tw"):
		var old: Variant = c.get_meta("shake_tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		c.position.x = float(c.get_meta("shake_x", c.position.x))
	else:
		c.set_meta("shake_x", c.position.x)
	var x0 := c.position.x
	var tw := c.create_tween()
	c.set_meta("shake_tw", tw)
	for dx in [-6.0, 5.0, -4.0, 3.0, -1.5, 0.0]:
		tw.tween_property(c, "position:x", x0 + dx, 0.05).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): c.remove_meta("shake_tw"))

## A disabled button stays quiet when tapped; this makes the tap say why: `reason` returns the text (empty = say
## nothing). The button keeps its disabled look and its `disabled` state.
static func deny_disabled(b: BaseButton, reason: Callable, shaker: Control = null) -> void:
	b.gui_input.connect(func(e: InputEvent) -> void:
		if b.disabled and Sheet._is_tap(e):
			var why := str(reason.call())
			if why != "":
				deny(b, why, shaker if shaker else b))

## Play a sound effect through the Sound autoload when it is there (tests and tools run without it). arg: Sound.sfx's
## optional argument (e.g. the coin amount).
static func sfx(name: String, arg: Variant = null) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var snd: Node = tree.root.get_node_or_null("Sound") if tree and tree.root else null
	if snd:
		snd.sfx(name, arg)


# =====================================================================================================================
# Buttons
# =====================================================================================================================

## The glossy kit button: Button plus a 2 px rim drawn over the face edge (web .pm-btn border), which a StyleBoxFlat
## can't do together with a lip of another colour. Made by button() / btn() / button_with().
class KitButton extends Button:
	var kind := "honey"
	var rim := Color(0, 0, 0, 0)
	var rim_w := 2
	var radius := 14
	var _rim_sb: StyleBoxFlat

	func _draw() -> void:
		if rim.a <= 0.0:
			return
		var st := "normal"
		match get_draw_mode():
			DRAW_PRESSED: st = "pressed"
			DRAW_HOVER: st = "hover"
			DRAW_DISABLED: st = "disabled"
			DRAW_HOVER_PRESSED: st = "hover_pressed"
		var sb := get_theme_stylebox(st) as StyleBoxFlat
		var r := Rect2(Vector2.ZERO, size)
		if sb:
			r = r.grow_individual(sb.expand_margin_left, sb.expand_margin_top, sb.expand_margin_right, sb.expand_margin_bottom)
		if _rim_sb == null:
			_rim_sb = StyleBoxFlat.new()
			_rim_sb.draw_center = false
			_rim_sb.anti_aliasing = true
			_rim_sb.corner_detail = 10
		_rim_sb.set_corner_radius_all(radius)
		_rim_sb.set_border_width_all(rim_w)
		_rim_sb.border_color = Color(rim, rim.a * (0.5 if disabled else 1.0))
		draw_style_box(_rim_sb, r)

## A cozy game button: rounded, with a lip under it that "presses" when tapped, plus tap sound + haptic.
## New form: button(text, kind, "lg" | "md" | "sm" | "xs") (BTN presets). Old form still works:
## button(text, kind, font_size: int, min_h: int = 56) keeps that exact font size and height.
static func button(text_: String, kind := "honey", size: Variant = "lg", min_h := -1) -> Button:
	var b := KitButton.new()
	b.text = text_
	b.focus_mode = Control.FOCUS_NONE
	if size is String:
		style_button(b, kind, size)
	else:
		b.custom_minimum_size = Vector2(0, min_h if min_h >= 0 else 56)
		style_button(b, kind, int(size))
	wire_press(b)
	return b

## Same as button() with a size preset name only: btn("Start game", "honey", "lg").
static func btn(text_: String, kind := "honey", size := "md") -> Button:
	return button(text_, kind, size)

## A button whose content is `child` (an icon, a CoinAmount ...) followed by `text_` (may be ""). The content row
## follows the press.
static func button_with(text_: String, child: Control, kind := "honey", size := "md") -> Button:
	var b := button("", kind, size)
	var p: Dictionary = BTN.get(size, BTN.md)
	var inset := maxf(0.0, (TAP - float(p.h)) / 2.0)
	var row := hbox(SPACE.sm)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.offset_top = inset
	row.offset_bottom = -inset - float(p.lip)
	if child:
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(child)
	if text_ != "":
		var k: Array = KINDS.get(kind, KINDS.honey)
		var l := label(text_, int(p.fs), k[2], font_display() if p.display else font_body(900))
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if (k[3] as Color).a > 0:
			l.add_theme_color_override("font_outline_color", k[3])
			l.add_theme_constant_override("outline_size", 5 if int(p.fs) >= 18 else 3)
		l.name = "Text"
		row.add_child(l)
	row.name = "Content"
	b.add_child(row)
	var shift := float(p.lip) - 2.0
	b.button_down.connect(func(): row.offset_top = inset + shift; row.offset_bottom = -inset - float(p.lip) + shift)
	b.button_up.connect(func(): row.offset_top = inset; row.offset_bottom = -inset - float(p.lip))
	return b

## The big lobby mode button (VS COMPUTER / PASS & PLAY): a 64 px button with a 34 px icon and styled caps text
## (19 px, shrinking to fit half a phone width).
## kind "honey" or "teal"; icon: an assets/ui name or a res:// path.
static func mode_button(text_: String, kind: String, icon_name: String) -> Button:
	var ic := icon(icon_name, 34)
	var b := button_with(text_.to_upper(), ic, kind, "lg")
	b.custom_minimum_size.y = H.xl
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := b.find_child("Text", true, false) as Label
	if l:
		var fit := func() -> void:          # the caps text shrinks (19 -> 12) to fit half a phone width
			var room := b.size.x - 2.0 * SPACE.sm - 34.0 - SPACE.sm
			var fs := 19
			while fs > FS.small and l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
				fs -= 1
			l.add_theme_font_size_override("font_size", fs)
		b.resized.connect(fit)
		fit.call()
	return b

## (Re)style a button as a kit button. size: a BTN preset name, or (old form) a font size int — then radius
## (default 18) and the button's own custom_minimum_size apply. Restyling keeps one press feedback connection.
static func style_button(b: Button, kind := "honey", font_size: Variant = 22, radius := -1) -> void:
	var k: Array = KINDS.get(kind, KINDS.honey)
	var fs: int
	var lip: int
	var r: int
	var inset := 0.0
	var side := 14.0
	var display := true
	if font_size is String:
		var p: Dictionary = BTN.get(font_size, BTN.md)
		fs = int(p.fs); lip = int(p.lip); r = int(p.r) if radius < 0 else radius
		side = float(p.pad); display = bool(p.display)
		b.custom_minimum_size.y = maxf(float(p.h), TAP)
		inset = maxf(0.0, (TAP - float(p.h)) / 2.0)
	else:
		fs = int(font_size); lip = LIP.lg; r = 18 if radius < 0 else radius
	b.set_meta("kit_kind", kind)
	b.set_meta("kit_size", font_size)
	var face: Color = k[0]
	var normal := StyleBoxFlat.new()
	normal.bg_color = face
	normal.set_corner_radius_all(r)
	normal.corner_detail = 10
	normal.anti_aliasing = true
	normal.border_width_bottom = lip
	normal.border_color = k[1]
	normal.shadow_size = 3
	normal.shadow_offset = Vector2(0, 2)
	normal.shadow_color = Color(Palette.INK, 0.2)
	normal.expand_margin_top = -inset
	normal.expand_margin_bottom = -inset
	normal.content_margin_left = side; normal.content_margin_right = side
	normal.content_margin_top = inset + 4
	normal.content_margin_bottom = inset + lip + 4
	var hover := normal.duplicate() as StyleBoxFlat
	if not OS.has_feature("mobile"):           # touch screens keep a stale hover state: no hover look there
		hover.bg_color = face.lightened(0.05)
	var d := float(lip - 2)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.border_width_bottom = 2
	pressed.expand_margin_top = -inset - d
	pressed.content_margin_top = inset + 4 + d
	pressed.content_margin_bottom = inset + lip + 4 - d
	pressed.bg_color = face.darkened(0.04)
	pressed.shadow_size = 1
	pressed.shadow_offset = Vector2(0, 1)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = face.lerp(Palette.DISABLED_FACE, 0.6)
	disabled.border_color = (k[1] as Color).lerp(Palette.DISABLED_LIP, 0.6)
	disabled.shadow_color = Color(Palette.INK, 0.08)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", font_display() if display else font_body(900))
	b.add_theme_font_size_override("font_size", fs)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, k[2])
	b.add_theme_color_override("font_disabled_color", (k[2] as Color).lerp(Palette.DISABLED_TEXT, 0.5))
	if (k[3] as Color).a > 0:
		b.add_theme_color_override("font_outline_color", k[3])
		b.add_theme_constant_override("outline_size", 5 if fs >= 18 else 3)
	else:
		b.add_theme_constant_override("outline_size", 0)
	if b is KitButton:
		var kb := b as KitButton
		kb.kind = kind
		kb.rim = k[4]
		kb.radius = r
		kb.queue_redraw()

## Change a kit button's kind, keeping its size (e.g. Buy -> Use: honey -> teal).
static func set_kind(b: Button, kind: String) -> void:
	style_button(b, kind, b.get_meta("kit_size", "md"))

## Shrink a button's font (down to min_fs) whenever its text doesn't fit its width. Call once after creating it.
static func fit_text(b: Button, min_fs := 12) -> void:
	var full := b.get_theme_font_size("font_size")
	var fit := func():
		var font := b.get_theme_font("font")
		var room := b.size.x - b.get_theme_stylebox("normal").get_margin(SIDE_LEFT) - b.get_theme_stylebox("normal").get_margin(SIDE_RIGHT)
		var fs := full
		while fs > min_fs and font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			fs -= 1
		if fs != b.get_theme_font_size("font_size"):
			b.add_theme_font_size_override("font_size", fs)
	b.clip_text = true
	b.resized.connect(fit)
	b.set_meta("_fit_text", fit)

## Re-run fit_text() after the button's text changed (it only re-fits by itself on a resize).
static func refit_text(b: Button) -> void:
	if b.has_meta("_fit_text"):
		(b.get_meta("_fit_text") as Callable).call()

## A segmented() row on a narrow card: equal widths while every label fits; else every option is as wide as its label
## needs (plus a share of the rest) and all the labels take one size, the largest that fits them all (min_fs at the least, then they clip). Fitting each button on
## its own gave four sizes in one row and still cut "Medium".
static func fit_segmented(seg: HBoxContainer, min_fs := 11) -> void:
	var btns: Array[Button] = []
	for c in seg.get_children():
		if c is Button:
			btns.append(c)
	if btns.is_empty():
		return
	var full := btns[0].get_theme_font_size("font_size")
	var fit := func():
		var font := btns[0].get_theme_font("font")
		var sep := float(seg.get_theme_constant("separation"))
		var pad := func(b: Button) -> float:
			var st := b.get_theme_stylebox("normal")
			return st.get_margin(SIDE_LEFT) + st.get_margin(SIDE_RIGHT)
		var share := (seg.size.x - sep * (btns.size() - 1)) / btns.size()
		var even := true
		for b in btns:
			even = even and font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, full).x + pad.call(b) <= share
		if even:                                          # room for all at full size: equal widths, as everywhere
			for b in btns:
				b.size_flags_stretch_ratio = 1.0
				if b.get_theme_font_size("font_size") != full:
					b.add_theme_font_size_override("font_size", full)
			return
		var fs := full
		while fs > min_fs:
			var need := sep * (btns.size() - 1)
			for b in btns:
				need += font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + pad.call(b)
			if need <= seg.size.x:
				break
			fs -= 1
		for b in btns:
			b.size_flags_stretch_ratio = maxf(1.0, font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + pad.call(b))
			if fs != b.get_theme_font_size("font_size"):
				b.add_theme_font_size_override("font_size", fs)
	for b in btns:
		b.clip_text = true
	seg.resized.connect(fit)

## The square icon button (pause, settings, back, zoom). icon: an assets/ui name ("ic_gear") or a res:// path.
## look "glass" (cream glass over the 3D room, web .icon-btn) or "night" (dark glass on the lobby). Scales to 0.94
## while held. Plays the tap feedback.
static func icon_button(icon_name: String, look := "glass", size := 48, icon_px := -1.0) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(size, size)
	b.size = Vector2(size, size)
	var r := int(round(size * 0.32))
	var st: StyleBoxFlat
	var pr: StyleBoxFlat
	if look == "night":
		st = box(Palette.NIGHT_GLASS, r, BW.line, Color(1, 1, 1, 0.25))
		pr = st.duplicate()
		pr.bg_color = Palette.NIGHT_GLASS.darkened(0.25)
	else:
		st = shade(box(Palette.GLASS, r, BW.hair, Palette.LINE), "sm")
		st.border_width_bottom = LIP.sm
		pr = st.duplicate()
		pr.bg_color = Palette.GLASS_PRESSED
		pr.border_width_bottom = 1
	pad(st, 0); pad(pr, 0)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(icon(icon_name, icon_px if icon_px > 0 else round(size * 0.5)))
	b.add_child(c)
	b.button_down.connect(func(): b.pivot_offset = b.size / 2; b.scale = Vector2(0.94, 0.94))
	b.button_up.connect(func(): b.scale = Vector2.ONE)
	wire_press(b)
	return b


# =====================================================================================================================
# Close button (web .x-btn)
# =====================================================================================================================

## The close control drawn in code. look "red": web .x-btn, a glossy red circle (radial gradient #ff8f80 ->
## #f2453c -> #c41d27) with a 3 px GOLD_HI border, a 2 px GOLD_RING outer ring, a 4 px X_LIP lip, a soft drop
## shadow, a gloss highlight and the white ic_close X. The ring and lip draw just outside the 48 px box (like the
## web box-shadows). look "soft": the info-bubble X, a cream disc with a plum X.
class XButton extends Button:
	var look := "red"
	var _x: Texture2D

	func _init(look_ := "red", px := 48) -> void:
		look = look_
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(px, px)
		size = Vector2(px, px)
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		_x = UIKit.svg("ic_close")
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)

	func _draw() -> void:
		var down := get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
		var k := minf(size.x, size.y) / 48.0
		var c := size / 2.0
		if look == "soft":
			var rs := 15.0 * k
			draw_circle(c, rs, Palette.CHIP.darkened(0.06) if down else Palette.CHIP, true, -1.0, true)
			if _x:
				var g := 13.0 * k
				draw_texture_rect(_x, Rect2(c - Vector2(g, g) / 2, Vector2(g, g)), false, Palette.INK)
			return
		var rad := 24.0 * k
		if down:
			c.y += 2.0 * k
		var lip := (2.0 if down else 4.0) * k
		# soft drop shadow (0 8px 14px rgba(110,30,40,.35)), drawn as a few fading discs
		var sh_y := (4.0 if down else 8.0) * k
		for i in 4:
			draw_circle(c + Vector2(0, sh_y), rad + (i * 1.5 - 1.0) * k, Color(0.43, 0.12, 0.16, 0.09), true, -1.0, true)
		draw_circle(c + Vector2(0, lip), rad, Palette.X_LIP, true, -1.0, true)         # lip
		draw_circle(c, rad + 2.0 * k, Palette.GOLD_RING, true, -1.0, true)            # outer ring
		draw_circle(c, rad, Palette.GOLD_HI, true, -1.0, true)                        # border
		_draw_face(c, rad - 3.0 * k)
		draw_arc(c, rad - 3.0 * k, 0.0, TAU, 64, Color(Palette.X_EDGE, 0.9), 1.0 * k, true)
		_draw_gloss(c, rad - 3.0 * k)
		if _x:
			var g := 20.0 * k
			var rr := Rect2(c - Vector2(g, g) / 2, Vector2(g, g))
			draw_texture_rect(_x, Rect2(rr.position + Vector2(0, 1.5 * k), rr.size), false, Color(0.35, 0.04, 0.08, 0.45))
			draw_texture_rect(_x, rr, false)

	## The radial gradient face: a polar mesh whose vertex colours follow the web gradient from its focal point
	## (36% / 30% of the padding box; radius = distance to the farthest corner).
	func _draw_face(c: Vector2, rf: float) -> void:
		var f := c + Vector2((0.36 - 0.5) * 2.0 * rf, (0.30 - 0.5) * 2.0 * rf)
		var far := (c + Vector2(rf, rf) - f).length()
		var seg := 48
		var rings := 6
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		pts.append(c)
		cols.append(_grad((c - f).length() / far))
		for j in range(1, rings + 1):
			var rr := rf * j / float(rings)
			for i in seg:
				var a := TAU * i / float(seg)
				var p := c + Vector2(cos(a), sin(a)) * rr
				pts.append(p)
				cols.append(_grad((p - f).length() / far))
		var idx := PackedInt32Array()
		for i in seg:
			idx.append_array([0, 1 + i, 1 + (i + 1) % seg])
		for j in range(1, rings):
			var a0 := 1 + (j - 1) * seg
			var a1 := 1 + j * seg
			for i in seg:
				var n := (i + 1) % seg
				idx.append_array([a0 + i, a1 + i, a1 + n, a0 + i, a1 + n, a0 + n])
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)

	static func _grad(t: float) -> Color:
		t = clampf(t, 0.0, 1.0)
		if t < 0.46:
			return Palette.X_HI.lerp(Palette.X_MID, t / 0.46)
		return Palette.X_MID.lerp(Palette.X_EDGE, (t - 0.46) / 0.54)

	## The ::before highlight: an ellipse over the top of the face, white .7 fading to 0.
	func _draw_gloss(c: Vector2, rf: float) -> void:
		var d := rf * 2.0
		var top := c.y - rf + 0.09 * d
		var h := 0.38 * d
		var w := d * (1.0 - 0.36)
		var ctr := Vector2(c.x, top + h / 2.0)
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in 32:
			var a := TAU * i / 32.0
			var p := ctr + Vector2(cos(a) * w / 2.0, sin(a) * h / 2.0)
			pts.append(p)
			cols.append(Color(1, 1, 1, 0.7 * clampf(1.0 - (p.y - top) / h, 0.0, 1.0)))
		draw_polygon(pts, cols)

## The close button: close_button() is the 48 px red web .x-btn; close_button("soft", 44) the info-bubble X.
## Plays the tap feedback. Place it on the card's top-right corner (Sheet does).
static func close_button(look := "red", size := 48) -> Button:
	var b := XButton.new(look, size)
	wire_press(b)
	return b


# =====================================================================================================================
# Segmented control (web .seg)
# =====================================================================================================================

## The segmented row: a CHIP track (r 14, 3 px padding) drawn behind its buttons; the selected segment is a
## white pill with shadow-sm and INK text, the others muted text on the track. Its children are only Buttons.
class Seg extends HBoxContainer:
	var _track: StyleBoxFlat

	func _init() -> void:
		add_theme_constant_override("separation", 0)
		_track = StyleBoxFlat.new()
		_track.bg_color = Palette.CHIP
		_track.set_corner_radius_all(UIKit.R.md)
		_track.corner_detail = 10
		_track.anti_aliasing = true

	func _draw() -> void:
		draw_style_box(_track, Rect2(Vector2.ZERO, size))

## A row of choices where exactly one is selected (Individual / Teams, 2 / 3 / 4 players ...), web .seg.
## options: [[value, text], ...]; on_pick(value) runs when the selection changes. size: "md" (48 px, 15 px text)
## or "sm" (48 px, 14 px text, tighter sides); an int is the old font-size form. Returns the row (an
## HBoxContainer whose children are the Buttons, each with meta "value"). Picking plays the tap feedback.
static func segmented(options: Array, selected, on_pick: Callable, size: Variant = "md") -> HBoxContainer:
	var fs := 15
	var side := 8.0
	if size is String:
		fs = 14 if size == "sm" else 15
		side = 5.0 if size == "sm" else 8.0
	else:
		fs = int(size)
	var row := Seg.new()
	row.custom_minimum_size.y = TAP
	var group := ButtonGroup.new()
	var n := options.size()
	for i in n:
		var o: Array = options[i]
		var b := Button.new()
		b.text = str(o[1])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, TAP)
		var l_in := 3.0 if i == 0 else 1.0
		var r_in := 3.0 if i == n - 1 else 1.0
		var off := StyleBoxFlat.new()
		off.bg_color = Color(1, 1, 1, 0)
		off.set_corner_radius_all(R.sm)
		off.anti_aliasing = true
		var on := off.duplicate() as StyleBoxFlat
		on.bg_color = Color.WHITE
		on.border_width_bottom = LIP.sm                # the same cream lip as the white buttons (a drop shadow got clipped / uneven here)
		on.border_color = Palette.LIP_CREAM
		for sb: StyleBoxFlat in [off, on]:
			sb.expand_margin_left = -l_in; sb.expand_margin_right = -r_in
			sb.expand_margin_top = -3; sb.expand_margin_bottom = -3
			sb.content_margin_left = side + l_in; sb.content_margin_right = side + r_in
			sb.content_margin_top = 9
			sb.content_margin_bottom = 9 + (LIP.sm if sb == on else 0)       # the label centres on the white face, above the lip
		var hov := off.duplicate() as StyleBoxFlat
		if not OS.has_feature("mobile"):
			hov.bg_color = Color(1, 1, 1, 0.35)
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_font_override("font", font_body(800))
		b.add_theme_font_size_override("font_size", fs)
		for st in ["font_color", "font_hover_color"]:
			b.add_theme_color_override(st, Palette.MUTED)
		for st in ["font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(st, Palette.INK)
		b.button_pressed = o[0] == selected
		var value = o[0]
		b.toggled.connect(func(on_: bool):
			if on_:
				on_pick.call(value))
		b.set_meta("value", value)
		wire_press(b)
		row.add_child(b)
	return row


# =====================================================================================================================
# Tags, badges, pills, mounts
# =====================================================================================================================

## A caps tag pill (IN USE, OWNED, FREE, CPU, LOCKED): upper-cases text. looks: "white" (white .88, INK),
## "gold" (GOLD, INK), "teal" (TEAL, white), "ink" (INK, white, 2 px white border), "red" (RED, white),
## "glass" (GLASS, INK), "honey" (HONEY_TINT, ON_HONEY).
static func tag(t: String, look := "white", size: int = FS.tag) -> PanelContainer:
	var bg := Color(1, 1, 1, 0.88)
	var fg := Palette.INK
	var border := 0
	match look:
		"gold": bg = Palette.GOLD
		"teal": bg = Palette.TEAL; fg = Color.WHITE
		"ink": bg = Palette.INK; fg = Color.WHITE; border = BW.line
		"red": bg = Palette.RED; fg = Color.WHITE
		"glass": bg = Palette.GLASS
		"honey": bg = Palette.HONEY_TINT; fg = Palette.ON_HONEY
	var p := PanelContainer.new()
	var st := box(bg, R.pill, border, Color.WHITE)
	if look != "glass":
		st.shadow_size = 1; st.shadow_offset = Vector2(0, 1); st.shadow_color = Color(Palette.INK, 0.15)
	pad(st, 7, 1)
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := caps_label(t, fg, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return p

## The red notification dot ("!" or a count), 22 px, white 2 px border, gently pulsing (pulse = false: still).
## Position it yourself (e.g. over a button's top-right corner).
static func notify_badge(t := "!", pulse := true) -> Label:
	var l := label(t, 13, Color.WHITE, font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var st := box(Palette.RED, R.pill, BW.line, Color.WHITE)
	pad(st, 5, 0)
	st.shadow_size = 2; st.shadow_offset = Vector2(0, 1); st.shadow_color = Color(Palette.INK, 0.25)
	l.add_theme_stylebox_override("normal", st)
	l.custom_minimum_size = Vector2(22, 22)
	l.size = Vector2(22, 22)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if pulse:
		var start := func() -> void:
			l.pivot_offset = l.size / 2
			var tw := l.create_tween().set_loops()
			tw.tween_property(l, "scale", Vector2(1.12, 1.12), 0.6).set_trans(Tween.TRANS_SINE)
			tw.tween_property(l, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)
		l.tree_entered.connect(start, CONNECT_ONE_SHOT)
	return l

## A white rounded mount around an avatar view (profile head, shop cards).
static func avatar_mount(view: Control, pad_px := 6) -> PanelContainer:
	var p := PanelContainer.new()
	var st := shade(box(Color.WHITE, R.lg + 2), "sm")
	pad(st, pad_px)
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(view)
	return p

## A small cream pill around a label (HUD player names, progress).
static func pill(l: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var st := box(Palette.GLASS, R.pill, 0, Color.TRANSPARENT, 3, Palette.shadow(0.14))
	st.content_margin_left = 8; st.content_margin_right = 8; st.content_margin_top = 1; st.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


static func _scroll_styles(t: Theme) -> void:
	var track := pad(box(Color(Palette.MUTED, 0.14), 4), 3, 0)
	var grab := pad(box(Palette.HONEY, 4), 3, 0)
	var grab_hi := pad(box(Palette.HONEY_LIP, 4), 3, 0)
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)
