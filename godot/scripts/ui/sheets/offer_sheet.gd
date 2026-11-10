class_name OfferSheet
extends Sheet
## The Shop's offer (the Buying mock-up), shared by every item's preview (ItemSheet, PawnSheet, PreviewSheet,
## EmotePackSheet): the Shop dimmed, one card in the item's rarity colours (ShopSheet.RAR; free and earned items wear
## "common"): a radial glow with light rays, a light rim and a dark 3D lip, rounded 28. On it, top to bottom: a chip
## with the rarity and the kind ("EPIC PAWN SKIN"), the name in outlined display type, the art large over a soft
## shadow (the subclass's _make_art), one or two chips with what the item is (its real description, _facts), and the
## action: the chunky gold price (a gem-only item's in teal), "or [gem] N gems" when it also sells for gems, "Need
## 2.5K" when the coins are short (tap: says how many), Use (teal) when owned, the "In use" pill, or a lock and what
## unlocks it. The round red X in the corner; under the card "You have 130.1K coins. One tap buys it."
## One tap buys (no "Buy X?" question: the price button is the deliberate second tap after opening the offer); the
## economy is ShopSheet's (buy_with_coins / buy_with_gems: server wallet, offline, not enough gems -> Store). After a
## purchase the RevealSheet shows the item; its USE NOW (puts it in use) and Keep shopping both go back to the Shop.
##   var s := ItemSheet.new("dice", "gold"); s.changed.connect(refresh_shop); s.open(layer)

signal changed                           ## bought or put in use
signal store_requested                   ## "Open Store" after "not enough gems" (the Shop passes it on to Main)

const W := 346.0                         ## the card (mock: 390 px screen, 22 px each side)
const FACE_H := 608.0                    ## the card's face, rim included (mock: 600 + 2 x 4)
const MIN_FACE_H := 470.0
const LIP := 8.0
const RADIUS := 28.0
const RIM := 4.0
const CHIP_TOP := 30.0
const ART_TOP := 132.0
const ART_W := 270.0
const WIDE_W := 298.0                    ## rooms, scenes, emote packs, plates: the card's width less 24 a side
const SIDE := 28.0                       ## the chips and buttons: 24 from the rim
const BOTTOM := 28.0
const ART_GAP := 34.0                    ## art bottom -> info chips (the shadow sits in it)
const STACK_GAP := 22.0                  ## info chips -> price
const LINE_GAP := 43.0                   ## card -> "You have ..."
const SCRIM := Color(0.07, 0.024, 0.008, 0.72)      ## rgba(18,6,2,.72)
## The kind on the chip ("EPIC PAWN SKIN").
# l10n:begin
const KIND_NAMES := {pawn = "Pawn skin", dice = "Dice", room = "Ludo room", scene = "S&L scene", emotes = "Emote pack",
	text = "Text emotes", char = "Character", avatar = "Avatar", frame = "Frame", plate = "Nameplate", badge = "Badge"}
# l10n:end

static var _spaced: Dictionary = {}      # spacing -> letter-spaced Lilita One
static var _trims: Dictionary = {}       # texture path -> the texture without its transparent margins

var kind := ""
var item_id := ""
var item_name := ""                      ## the catalogue name (untranslated)
var rar := ""                            ## ShopSheet.rarity: "" for free / earned items
var colors: Array                        ## ShopSheet.RAR[rar or "common"]: [glow, face, deep, rim, label ground]
var panel: GamePanel
var root: Control                        ## the card's face: everything on it is placed by _layout
var art: Control                         ## the art's box
var wide_art := false
var _chip: PanelContainer
var _chip_l: Label
var _name_l: Label
var _x: Button
var _shadow: TextureRect
var _facts: Control
var _fact_boxes: Array[Panel] = []
var _fact_labels: Array[Label] = []
var _stack: VBoxContainer
var _slot: Control
var _buy: Button
var _need: Button
var _use: Button
var _on_pill: Control
var _lock: Control
var _lock_l: Label
var _gem: Button
var _line: Label
var _gems_only := false
var _acting := false
var _face_h := FACE_H
var _wrap: Control


func _init(kind_ := "dice", id := "classic", name_ := "") -> void:
	super("", W, false, LOOK_CARD)
	dismissable = true                   # Back, Escape and a tap on the dim close it (and the X)
	kind = kind_
	item_id = id
	item_name = name_
	rar = ShopSheet.rarity(kind, id)
	colors = ShopSheet.RAR[rar if rar != "" else "common"]
	_gems_only = ShopSheet._gems_only(kind, id)
	wide_art = kind in ["room", "scene", "emotes", "text", "plate"]
	backdrop.color = SCRIM
	var empty := StyleBoxEmpty.new()
	card.add_theme_stylebox_override("panel", empty)
	header.visible = false
	body.add_theme_constant_override("separation", 0)
	var lift := Control.new()                # the mock sits the card a little low (96 px over it, 70 under the line)
	lift.custom_minimum_size.y = 26
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(lift)
	_build_card()
	var gap := Control.new()
	gap.custom_minimum_size.y = LINE_GAP
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(gap)
	_line = UIKit.label("", 14, Color("#e7c7a6"), UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER)
	_line.name = "Wallet"
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_line)


func _ready() -> void:
	Save.changed.connect(refresh)
	get_viewport().size_changed.connect(_fit_height)
	_fit_height()
	refresh()


# =====================================================================================================================
# The card
# =====================================================================================================================

func _build_card() -> void:
	var c := colors
	# the soft drop shadow (0 20px 50px rgba(0,0,0,.6)) behind the card
	_wrap = PanelContainer.new()
	_wrap.name = "Offer"
	_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0)
	sh.set_corner_radius_all(int(RADIUS))
	sh.shadow_color = Color(0, 0, 0, 0.45)
	sh.shadow_size = 26
	sh.shadow_offset = Vector2(0, 18)
	_wrap.add_theme_stylebox_override("panel", sh)
	body.add_child(_wrap)
	panel = GamePanel.radial(c[0].lerp(Color.WHITE, 0.35), c[1].lerp(Color.WHITE, 0.08), c[2])
	panel.name = "Panel"
	panel.c3 = c[4]
	panel.mid = 0.38
	panel.mid2 = 0.78
	panel.center = Vector2(0.5, 0.38)
	panel.reach = Vector2(0.8, 0.55)
	panel.radius = RADIUS
	panel.border = RIM
	panel.border_color = c[3]
	panel.lip = LIP
	panel.lip_color = c[4].darkened(0.4)
	panel.rays = 0.22
	panel.ray_count = 18.0
	panel.ray_width = 0.4
	panel.ray_center = Vector2(0.5, 234.0 / FACE_H)
	panel.ray_reach = 280.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP      # a tap on the card doesn't reach the dim (which closes)
	panel.custom_minimum_size = Vector2(0, FACE_H + LIP)
	_wrap.add_child(panel)
	root = Control.new()
	root.name = "Face"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(root)
	root.resized.connect(_layout)
	# the rarity + kind chip
	_chip = PanelContainer.new()
	_chip.name = "Kind"
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := UIKit.box(c[4], 12, 2, c[3])
	cs.content_margin_left = 16; cs.content_margin_right = 16
	cs.content_margin_top = 4; cs.content_margin_bottom = 4
	_chip.add_theme_stylebox_override("panel", cs)
	var kind_text := L10n.t(str(KIND_NAMES.get(kind, "")))
	if rar != "":
		kind_text = L10n.t("%s %s") % [L10n.t(str(ShopSheet.RARITY_NAMES[rar])), kind_text]
	_chip_l = UIKit.label(kind_text.to_upper(), 14, c[0], spaced_display(2))
	_chip_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.add_child(_chip_l)
	root.add_child(_chip)
	# the name
	_name_l = UIKit.label(L10n.t(item_name), 46, Color.WHITE, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	_name_l.name = "ItemName"
	_name_l.add_theme_constant_override("outline_size", 8)
	_name_l.add_theme_color_override("font_outline_color", c[4])
	_name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_name_l)
	# the soft shadow under the art, then the art
	_shadow = TextureRect.new()
	_shadow.name = "Shadow"
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	var g := GradientTexture2D.new()
	g.width = 64; g.height = 64
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5); g.fill_to = Vector2(1.0, 0.5)
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color(c[4], 0.75))
	g.gradient.set_color(1, Color(c[4], 0.0))
	_shadow.texture = g
	_shadow.visible = not wide_art
	root.add_child(_shadow)
	art = Control.new()
	art.name = "Art"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(art)
	var a := _make_art()
	if a:
		art.add_child(a)
		a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# what it is
	_facts = Control.new()
	_facts.name = "Facts"
	_facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_facts)
	var first := true
	for f: String in _fact_list():
		_add_fact(f, first)
		first = false
	# the action
	_stack = UIKit.vbox(10)
	_stack.name = "Actions"
	root.add_child(_stack)
	_slot = Control.new()
	_slot.name = "Slot"
	_slot.custom_minimum_size.y = 70
	_stack.add_child(_slot)
	var gems_price := ShopSheet._gems(kind, item_id)
	var price := ShopSheet._price(kind, item_id)
	_buy = chunky(ShopSheet.price_button(gems_price if _gems_only else price, _gems_only, true, true))
	_buy.name = "Buy"
	_buy.pressed.connect(_on_buy)
	_need = chunky(_face(Color("#8f7d9e").lerp(c[1], 0.25), Color("#5d4c6c").lerp(c[2], 0.25), Color("#3d2f4a").lerp(c[4], 0.3), Color("#22182c")))
	_need.name = "Need"
	_need.pressed.connect(_on_buy)
	_use = chunky(_face(Color("#6ff0d6"), Color("#2fb39c"), Color("#1d7f6e"), Color("#0f4f44")))
	_use.name = "Use"
	_use.text = tr("Use")
	_use.pressed.connect(_on_use)
	_on_pill = _in_use_face()
	_lock = _lock_face()
	for b: Control in [_buy, _need, _use, _on_pill, _lock]:
		_slot.add_child(b)
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sync_label(_use, "#1d4f45")
	if price > 0 and gems_price > 0 and not _gems_only:
		_gem = _gem_button(gems_price)
		_gem.pressed.connect(_on_gems)
		_stack.add_child(_gem)
	# the X
	_x = UIKit.close_button("game", 44)
	_x.name = "Close"
	_x.tooltip_text = tr("Close")
	_x.pressed.connect(close)
	root.add_child(_x)


## The art in its box (filled by anchors). Subclasses draw their own; this is the dice / character / frame / plate one.
func _make_art() -> Control:
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match kind:
		"dice": c.add_child(Thumbnailer.dice_art(item_id, 170))
		"frame": c.add_child(Collection.make_avatar_of(Collection.equipped("avatar"), item_id, 170))
		"plate": c.add_child(Collection.make_plate(str(Collection.profile().get("name", "You")), item_id, "", 30, true, 220.0))
		"badge": c.add_child(Collection.make_badge(item_id, 170))
		_: c.add_child(Collection.make_avatar_of(item_id, Collection.equipped("frame"), 170))
	return c

## The info chips (already translated): what the item is, from its catalogue data. Subclasses add their own.
func _fact_list() -> Array:
	var out: Array = []
	if _locked():
		return [ShopSheet._unlock_note(kind, item_id)]
	match kind:
		"dice": out.append(tr("Ludo and Snakes & Ladders"))
		"frame": out.append(tr("Rounds your picture in every game"))
		"plate": out.append(tr("Under your name in every game"))
		"char", "avatar": out.append(tr("Your picture in every game"))
	return out

func _locked() -> bool:
	return not ShopSheet._owned(kind, item_id) and ShopSheet._price(kind, item_id) <= 0 and not _gems_only

func _add_fact(text: String, star: bool) -> void:
	var p := Panel.new()                     # placed by _layout_facts (no containers: a wrapping label's height
	p.name = "Fact"                          # follows its width, which only the layout knows)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UIKit.box(Color(colors[4], 0.6), 12))
	if star:
		var icon: Control = UIKit.glyph("ic_lock", 16, colors[0]) if _locked() else StarOutline.new(colors[0])
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(icon)
	var l := UIKit.label(text.trim_suffix(".").trim_suffix("।"), 13, Color.WHITE, UIKit.font_body(900))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("line_spacing", -5)      # the mock's tight 1.35 lines
	p.add_child(l)
	_facts.add_child(p)
	_fact_boxes.append(p)
	_fact_labels.append(l)

## A picture without its transparent margins (the baked pawn pairs are framed for the Shop cards; the offer and the
## reveal show the pawns themselves large, as the mock-up does). Cached per texture.
static func trimmed(t: Texture2D) -> Texture2D:
	if t == null:
		return null
	var key := t.resource_path if t.resource_path != "" else str(t.get_instance_id())
	if _trims.has(key):
		return _trims[key]
	var out := t
	var img := t.get_image()
	if img and not img.is_compressed():
		var r := img.get_used_rect()
		if r.size.x > 0 and r.size.y > 0 and r.size != img.get_size():
			var at := AtlasTexture.new()
			at.atlas = t
			at.region = Rect2(r.grow(2)).intersection(Rect2(Vector2.ZERO, img.get_size()))
			out = at
	_trims[key] = out
	return out

## The pawn pair, trimmed, kept to its aspect inside whatever box holds it.
static func pawn_pair(id: String) -> Control:
	var p := Thumbnailer.pawn_art(id)
	if p is TextureRect:
		var tr := p as TextureRect
		tr.texture = trimmed(tr.texture)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return p

## Lilita One with extra space between the letters (the mock's letter-spaced chips). Cached.
static func spaced_display(spacing: int) -> Font:
	if not _spaced.has(spacing):
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/LilitaOne.woff2")
		fv.spacing_glyph = spacing
		UIKit._bangla_under(fv, 0)
		_spaced[spacing] = fv
	return _spaced[spacing]

## A chunky vertical-gradient face with an inset lip and an outer lip (the mock's big buttons).
static func _face(top: Color, bottom: Color, lip: Color, lip2: Color) -> GamePanel:
	var p := GamePanel.vertical(top, bottom)
	p.radius = 20.0
	p.lip = 7.0
	p.lip_color = lip
	p.lip2 = 4.0
	p.lip2_color = lip2
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## A Button wearing a GamePanel face (and whatever is in it). The Button's own text stays invisible (tests and
## accessibility read it); a "Text" label in the face shows it (set_text: _sync_label).
static func chunky(face: Control) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	for k in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(k, Color(0, 0, 0, 0))
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.custom_minimum_size.y = 70
	b.button_down.connect(func(): face.modulate = Color(0.92, 0.92, 0.92))
	b.button_up.connect(func(): face.modulate = Color.WHITE)
	UIKit.wire_press(b)
	return b

## The big outlined label on a chunky face, showing the Button's text.
func _sync_label(b: Button, outline: String) -> void:
	var face := b.get_node("Face") as Control
	var l := face.get_node_or_null("Text") as Label
	if l == null:
		l = UIKit.label("", 30, Color.WHITE, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
		l.name = "Text"
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(outline))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(l)
	l.text = b.text.to_upper()

## "✓ IN USE" as a cream chunky face (not a button).
func _in_use_face() -> Control:
	var p := _face(Color("#fff7ea"), Color("#f6e3c8"), Color("#d8b48a"), Color(colors[4], 0.85))
	p.name = "InUse"
	var h := UIKit.hbox(8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UIKit.glyph("ic_check", 28, Color("#1d7f6e"))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := UIKit.label(L10n.t("In use").to_upper(), 28, Color("#1d7f6e"), UIKit.font_display())
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	p.add_child(h)
	return p

## A dark face with the lock and what unlocks it ("Reach level 5").
func _lock_face() -> Control:
	var p := PanelContainer.new()
	p.name = "Locked"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UIKit.box(Color(colors[4], 0.55), 20, 2, Color(colors[0], 0.5))
	p.add_theme_stylebox_override("panel", st)
	var h := UIKit.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UIKit.glyph("ic_lock", 24, colors[0])
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	_lock_l = UIKit.label(ShopSheet._unlock_note(kind, item_id), 20, colors[0], UIKit.font_display())
	_lock_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_lock_l)
	p.add_child(h)
	return p

## "or [gem] 60 gems": the secondary button (the item also sells for gems).
func _gem_button(gems: int) -> Button:
	var b := Button.new()
	b.name = "GemBuy"
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("gems", gems)
	b.custom_minimum_size.y = 50
	var st := UIKit.box(Color(colors[4], 0.55), 16, 2, Color(colors[0], 0.5))
	var dn := st.duplicate() as StyleBoxFlat
	dn.bg_color = Color(colors[4], 0.8)
	for k in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	for k in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(k, dn)
	var h := UIKit.hbox(8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var or_l := UIKit.label(L10n.t("or"), 19, colors[0], UIKit.font_display())
	or_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(or_l)
	var amt := CoinAmount.gems(gems, "md", "plain")
	amt.name = "Amount"
	amt.coin.custom_minimum_size = Vector2(22, 22)
	amt.text_label.add_theme_font_override("font", UIKit.font_display())
	amt.text_label.add_theme_font_size_override("font_size", 19)
	amt.set_color(colors[0])
	var num := UIKit.hbox(5)                 # "[gem] 60 gems": the number and the word a space apart
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_child(amt)
	var gl := UIKit.label(L10n.t("gems"), 19, colors[0], UIKit.font_display())
	gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.add_child(gl)
	h.add_child(num)
	UIKit.wire_press(b)
	return b


# =====================================================================================================================
# Layout
# =====================================================================================================================

## The card's height: the mock's 608 px face on a 844 px screen; shorter screens shrink the art.
func _fit_height() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var h := clampf(vp.y - 236.0 - _safe_top(), MIN_FACE_H, FACE_H)
	if absf(h - _face_h) > 0.5:
		_face_h = h
		panel.custom_minimum_size.y = h + LIP
		panel.ray_center = Vector2(0.5, 234.0 / h)

## Everything on the face, top to bottom (mock positions, measured from the card's outer edge).
func _layout() -> void:
	var w := root.size.x
	var hh := root.size.y
	if w < 10.0 or hh < 10.0:
		return
	_x.size = Vector2(44, 44)
	_x.position = Vector2(w - 16.0 - 44.0, 16.0)
	var cm := _chip.get_combined_minimum_size()
	_chip.size = cm
	_chip.position = Vector2(roundf((w - cm.x) / 2.0), CHIP_TOP)
	# the name: one line, smaller until it fits
	var fs := 46
	var room_w := w - 40.0
	var font := UIKit.font_display()
	while fs > 26 and font.get_string_size(_name_l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0 > room_w:
		fs -= 2
	_name_l.add_theme_font_size_override("font_size", fs)
	var nm := _name_l.get_combined_minimum_size()
	_name_l.size = Vector2(room_w, nm.y)
	_name_l.position = Vector2(20.0, CHIP_TOP + cm.y + 6.0 - (nm.y - fs) * 0.5)
	# bottom up: the actions, the info chips, then the art takes what is left
	var sm := _stack.get_combined_minimum_size()
	_stack.size = Vector2(w - 2.0 * SIDE, sm.y)
	_stack.position = Vector2(SIDE, hh - BOTTOM - sm.y + 4.0)          # the outer lip hangs into the bottom padding
	var facts_h := _layout_facts(w - 2.0 * SIDE)
	var facts_top := _stack.position.y - STACK_GAP - facts_h
	_facts.position = Vector2(SIDE, facts_top)
	_facts.size = Vector2(w - 2.0 * SIDE, facts_h)
	var top := ART_TOP - (4.0 if wide_art else 0.0)
	var art_h := maxf(80.0, facts_top - (ART_GAP if facts_h > 0.0 else 16.0) - top)
	if wide_art:
		art_h = maxf(80.0, facts_top - 18.0 - top)
	var aw := WIDE_W if wide_art else ART_W
	art.position = Vector2(roundf((w - aw) / 2.0), top)
	art.size = Vector2(aw, art_h)
	_shadow.size = Vector2(230, 46)
	_shadow.position = Vector2(roundf((w - 230.0) / 2.0), top + art_h - 18.0)
	_layout_more()

## Subclasses place their own overlays (the 3D view's chips) once the art box has its size.
func _layout_more() -> void:
	pass

## The info chips side by side, centred, 10 apart: each its one-line width when they fit, else the row's width shared
## by their lengths (the text wraps). Returns the row's height.
func _layout_facts(avail: float) -> float:
	var n := _fact_boxes.size()
	if n == 0:
		return 0.0
	var gap := 10.0
	var nat: Array[float] = []
	var extra: Array[float] = []                 # padding 12 a side, plus the icon and its 6 px gap
	var total := 0.0
	for i in n:
		var l := _fact_labels[i]
		var tw := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
		extra.append(24.0 + (22.0 if _fact_boxes[i].has_node("Icon") else 0.0))
		nat.append(ceilf(tw) + 2.0 + extra[i])
		total += nat[i]
	var room := avail - gap * (n - 1)
	var widths: Array[float] = []
	var sum := 0.0
	for i in n:
		widths.append(nat[i] if total <= room else floorf(maxf(80.0, room * nat[i] / total)))
		sum += widths[i]
	var h := 0.0
	var th: Array[float] = []
	for i in n:
		var l := _fact_labels[i]
		var f := l.get_theme_font("font")
		var fs := l.get_theme_font_size("font_size")
		var t := f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, widths[i] - extra[i], fs, -1,
			TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y
		var lines := maxf(1.0, roundf(t / f.get_height(fs)))
		t = lines * f.get_height(fs) + (lines - 1.0) * l.get_theme_constant("line_spacing")
		th.append(ceilf(t))
		h = maxf(h, ceilf(t) + 12.0)
	var x0 := roundf((avail - sum - gap * (n - 1)) / 2.0)
	for i in n:
		var p := _fact_boxes[i]
		p.position = Vector2(x0, 0)
		p.size = Vector2(widths[i], h)
		var l := _fact_labels[i]
		# drawn from the top, placed at the text's own height: the label's height may lag behind its new width
		l.position = Vector2(extra[i] - 12.0, roundf((h - th[i]) / 2.0))
		l.size = Vector2(widths[i] - extra[i], th[i])
		if p.has_node("Icon"):
			var ic := p.get_node("Icon") as Control
			ic.size = Vector2(16, 16)
			ic.position = Vector2(12, roundf((h - 16.0) / 2.0))
		x0 += widths[i] + gap
	return h


# =====================================================================================================================
# State and actions
# =====================================================================================================================

## Re-read the profile: which action shows, and the line under the card.
func refresh() -> void:
	if not is_instance_valid(_buy):
		return
	var own := ShopSheet._owned(kind, item_id)
	var on := own and ShopSheet._in_use(kind, item_id)
	var price := ShopSheet._price(kind, item_id)
	var for_sale := not own and (price > 0 or _gems_only)
	var short := 0 if _gems_only else price - Catalog.coins()
	_buy.visible = for_sale and short <= 0
	_need.visible = for_sale and short > 0
	_need.text = Fmt.shortfall(short)
	_sync_label(_need, "#22182c")
	_use.visible = own and not on
	_on_pill.visible = on
	_lock.visible = not own and not for_sale
	if _gem:
		_gem.visible = not own
	if for_sale:
		if _gems_only:
			_line.text = L10n.t("You have %s gems. One tap buys it.") % Fmt.coins_full(int(Save.profile.get("gems", 0)))
		elif short > 0:
			_line.text = L10n.t("You have %s coins.") % Fmt.coins(Catalog.coins())
		else:
			_line.text = L10n.t("You have %s coins. One tap buys it.") % Fmt.coins(Catalog.coins())
	_line.modulate.a = 1.0 if for_sale else 0.0
	if root.is_inside_tree():
		_layout()

## The price button (coins; a gem-only item pays gems) and "Need 2.5K" (says how many coins are missing).
func _on_buy() -> void:
	if _gems_only:
		await _on_gems()
		return
	if _acting or _closing or ShopSheet._owned(kind, item_id) or not _can_act():
		return
	_acting = true
	var before := Catalog.coins()
	var ok: bool = await ShopSheet.buy_with_coins(self, kind, item_id, item_name)
	_acting = false
	if not is_instance_valid(self) or _closing:
		return
	if ok:
		_bought(_spent(before, Catalog.coins(), ShopSheet._price(kind, item_id)), false)
	refresh()

## "or [gem] N gems" (and a gem-only item's price): the Shop's gems flow.
func _on_gems() -> void:
	if _acting or _closing or ShopSheet._owned(kind, item_id) or not _can_act():
		return
	_acting = true
	var before := int(Save.profile.get("gems", 0))
	var res: String = await ShopSheet.buy_with_gems(self, kind, item_id, item_name)
	_acting = false
	if not is_instance_valid(self) or _closing:
		return
	if res == "store":
		store_requested.emit()
	elif res == "bought":
		_bought(_spent(before, int(Save.profile.get("gems", 0)), ShopSheet._gems(kind, item_id)), true)
	refresh()

## Use: put the owned item in use (through the server when there is an Account).
func _on_use() -> void:
	if _acting or _closing or not ShopSheet._owned(kind, item_id) or ShopSheet._in_use(kind, item_id) or not _can_act():
		return
	_acting = true
	var why: String = await ShopSheet.equip_item(kind, item_id)
	_acting = false
	if not is_instance_valid(self) or _closing:
		return
	if why != "":
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, why, panel, 2.2, "bad")
	else:
		Sound.sfx("select")
		var t := L10n.t(item_name)
		Toast.show(self, (tr("%s pawns are in use") if kind == "pawn" else tr("%s is in use")) % t, panel, 1.6, "good")
		_announce()
	refresh()

## The old previews' entry point (Buy / Need / Use, whichever shows).
func _on_act() -> void:
	if ShopSheet._owned(kind, item_id):
		await _on_use()
	else:
		await _on_buy()

## False while the subclass can't take an action yet (a room preview still switching the café).
func _can_act() -> bool:
	return true

## Bought or put in use: tell the Shop (subclasses add their own signals).
func _announce() -> void:
	changed.emit()

## What a purchase really cost: the balance before less the balance after (the server's answer), else the price.
static func _spent(before: int, after: int, price: int) -> int:
	return before - after if before > after else price

## Bought: the reveal over everything; its USE NOW and Keep shopping both come back to the Shop.
func _bought(paid: int, gems: bool) -> void:
	_announce()
	var layer := get_parent() as Control
	if layer == null:
		return
	var rv := RevealSheet.new(kind, item_id, item_name, paid, gems)
	rv.used.connect(func():
		if is_instance_valid(self):
			_announce()
			close())
	rv.kept.connect(func():
		if is_instance_valid(self):
			close())
	rv.open(layer)


## The mock's outlined star (24-unit path, 2.5 stroke) at 16 px.
class StarOutline extends Control:
	const PTS := [Vector2(12, 3), Vector2(14.6, 8.6), Vector2(20.7, 9.3), Vector2(16.2, 13.5), Vector2(17.4, 19.5),
		Vector2(12, 16.6), Vector2(6.6, 19.5), Vector2(7.8, 13.5), Vector2(3.3, 9.3), Vector2(9.4, 8.6), Vector2(12, 3)]
	var col: Color

	func _init(c: Color) -> void:
		col = c
		custom_minimum_size = Vector2(16, 16)

	func _draw() -> void:
		var k := minf(size.x, size.y) / 24.0
		var pts := PackedVector2Array()
		for p: Vector2 in PTS:
			pts.append(p * k)
		draw_polyline(pts, col, 2.5 * k, true)
