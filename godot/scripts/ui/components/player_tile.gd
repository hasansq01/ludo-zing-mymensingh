class_name PlayerTile
extends Control
## A player's corner tile in a game (Ludo, and S&L as "tile lite"): a cream card holding the avatar and a SOLID
## dice slot (on the side towards the screen centre), a nameplate overlapping the card's foot (name + CPU tag),
## a progress pill (4 home pips + whole percent, or a note such as "Square 47"), an optional chip ("Help your
## teammate") and the colour-blind symbol (pref colorblind).
##
## The card is framed in the player's colour (3 px; a lighter shade while waiting) and the nameplate is tinted with
## it, so each tile reads as the base of that colour on the board. Active turn: 1.1x, the full-colour 4 px frame and a
## soft breathing glow. Inactive: full opacity, slightly smaller (0.95). The chip can lead with colour dots
## (set_chip_colors: the two teammates' colours in Teams). Avatars: "you" = the equipped avatar + frame (Collection.make_avatar); "cpu" = the
## café mascots (Mocha, Biscotti, Espresso; assets/avatars/cpu_*.svg) on a tile in the player's colour;
## "human" (Pass & Play) = the pawn tile of that colour.
##
##   var t := PlayerTile.new(0, "left")             # side: which screen edge it sits on; the slot faces inwards
##   t.set_player("Mocha", "cpu", "mocha")
##   t.set_state(true, false, 1, 0.43, "")
##   dice.global_position = t.dice_slot_rect().position
##
## The tile's own size is its unscaled layout (size / custom_minimum_size); scale changes with the turn, around
## pivot_offset (outer edge, card middle). PlayerTile.make_avatar() builds the same avatar for other screens.

const AVA := 64.0
const SLOT := 64.0
const PAD := 5.0
const GAP := 6.0
const CARD_W := PAD * 2.0 + AVA + GAP + SLOT    # 144
const CARD_H := PAD * 2.0 + AVA                 # 74
const NAME_OVERLAP := 9.0
const ACTIVE_SCALE := 1.1
const IDLE_SCALE := 0.95
const CPU_IDS := ["mocha", "biscotti", "espresso"]
const PAWN_AVATARS := ["pawn-red", "pawn-green", "pawn-yellow", "pawn-blue"]

var color_index := 0
var side := "left"
var player_name := ""
var kind := "cpu"
var cpu_id := ""
var active := false
var mover := false
var place := 0
var done_place := 0                      ## play on: this side finished in this place (badge, tile dimmed); 0 = playing

var _ava: Control
var _name_pill: PanelContainer
var _name: Label
var _cpu_tag: Control
var _prog_pill: PanelContainer
var _pips: Array[Control] = []
var _pct: Label
var _chip_pill: PanelContainer
var _chip: Label
var _chip_dots: HBoxContainer
var _chip_cols: Array = []
var show_progress := true                ## false hides the progress pill (the staged tutorial board)
var _sym: Control
var _place_badge: Control
var _note := ""
var _home := 0
var _glow := 0.0
var _t := 0.0
var _scale_tw: Tween
var _sb_card: StyleBoxFlat
var _sb_card_on: StyleBoxFlat
var _sb_slot: StyleBoxFlat
var _sb_glow: StyleBoxFlat
var _sb_mover: StyleBoxFlat
var _sb_you: StyleBoxFlat


func _init(color_index_ := 0, side_ := "left") -> void:
	color_index = posmod(color_index_, 4)
	side = side_
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_styles()
	_name = UIKit.label("", UIKit.FS.label, Palette.INK, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cpu_tag = _small_tag(tr("CPU"), Palette.INK, Color.WHITE)
	var nrow := UIKit.hbox(UIKit.SPACE.xs)
	nrow.alignment = BoxContainer.ALIGNMENT_CENTER
	nrow.add_child(_name)
	nrow.add_child(_cpu_tag)
	_name_pill = _pill(nrow, (Palette.TINT[color_index] as Color).lerp(Color.WHITE, 0.3), 26)
	add_child(_name_pill)
	var prow := UIKit.hbox(UIKit.SPACE.xs)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	var pips := UIKit.hbox(3)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for k in 4:
		var pip := Pip.new()
		pip.color = Palette.PLAYER[color_index]
		pips.add_child(pip)
		_pips.append(pip)
	prow.add_child(pips)
	_pct = UIKit.label("0%", UIKit.FS.small, Palette.INK, UIKit.font_body(900, true))
	_pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prow.add_child(_pct)
	_prog_pill = _pill(prow, Palette.GLASS, 22)
	add_child(_prog_pill)
	_chip = UIKit.label("", UIKit.FS.small, Palette.TEAL_OUTLINE, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	_chip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_chip_dots = UIKit.hbox(2)
	_chip_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_dots.visible = false
	var crow := UIKit.hbox(UIKit.SPACE.xs)
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_child(_chip_dots)
	crow.add_child(_chip)
	_chip_pill = _pill(crow, Palette.TEAL_GLOW.lerp(Color.WHITE, 0.45), 22)
	_chip_pill.visible = false
	add_child(_chip_pill)
	set_player(Palette.NAMES[color_index], "human")
	resized.connect(_layout)


## Name, kind ("you" | "cpu" | "human") and the mascot for computers ("mocha" | "biscotti" | "espresso";
## "" = guessed from the name, then by colour).
func set_player(name_: String, kind_: String, cpu_id_ := "") -> void:
	player_name = name_
	kind = kind_
	cpu_id = cpu_id_
	if _ava:
		_ava.queue_free()
	_ava = make_avatar(color_index, kind, AVA, cpu_id if cpu_id != "" else name_)
	add_child(_ava)
	move_child(_ava, 0)
	_name.text = L10n.seat_name(name_)
	_cpu_tag.visible = kind == "cpu"
	_refresh_symbol()
	_layout()

## active: it is this player's turn. mover: a teammate's roll moves these pawns (Help your teammate).
## home: pawns home (0..4; < 0 hides the pips). pct: progress 0..1 (Fmt.pct). chip: "" hides the chip.
func set_state(active_: bool, mover_: bool, home: int, pct: float, chip := "") -> void:
	var was := active
	active = active_
	mover = mover_
	_home = home
	for k in 4:
		(_pips[k] as Pip).filled = k < home
		_pips[k].visible = home >= 0
		_pips[k].queue_redraw()
	_pct.text = _note if _note != "" else Fmt.pct(pct)
	_prog_pill.visible = show_progress
	_chip.text = chip
	_chip_pill.visible = chip != ""
	_refresh_symbol()
	if was != active or _scale_tw == null:
		_animate_scale()
	set_process(active and not _reduce_motion())
	if not active:
		_glow = 0.0
	queue_redraw()
	_layout()

## The chip leads with a dot per colour (Teams: the two teammates' colours, so the team reads at a glance) on a
## white pill with ink text; [] = the plain teal chip ("Help your teammate").
func set_chip_colors(cols: Array) -> void:
	if cols == _chip_cols:
		return
	_chip_cols = cols.duplicate()
	for ch in _chip_dots.get_children():
		_chip_dots.remove_child(ch)
		ch.queue_free()
	for c in cols:
		var d := Pip.new()
		d.color = Palette.PLAYER[posmod(int(c), 4)]
		d.filled = true
		_chip_dots.add_child(d)
	_chip_dots.visible = not cols.is_empty()
	var st := _chip_pill.get_theme_stylebox("panel") as StyleBoxFlat
	st.bg_color = Color.WHITE if not cols.is_empty() else Palette.TEAL_GLOW.lerp(Color.WHITE, 0.45)
	UIKit.pad(st, 7 if not cols.is_empty() else 9, 0)
	_chip.add_theme_color_override("font_color", Palette.INK if not cols.is_empty() else Palette.TEAL_OUTLINE)
	_layout()

## Shows or hides the progress pill (pips + percent).
func set_progress_visible(on: bool) -> void:
	show_progress = on
	_prog_pill.visible = on
	_layout()

## Replaces the percent with a short note (S&L: "Square 47"); "" = back to the percent.
func set_note(t: String) -> void:
	_note = t
	if t != "":
		_pct.text = t

## The rank ribbon for result screens (1..4); 0 hides it.
func set_place(n: int) -> void:
	place = n
	if _place_badge:
		_place_badge.queue_free()
		_place_badge = null
	if n > 0:
		_place_badge = PlaceBadge.make(n, 26)
		add_child(_place_badge)
	_layout()

## Play on: this side has finished in place n while the game goes on: its place badge on the avatar and the tile
## dimmed (the card and everything on it but the badge); 0 = still playing (full colour, no badge).
func set_done(n: int) -> void:
	if n == done_place:
		return
	done_place = n
	set_place(n)
	_apply_done()

## The dimming of a finished side (also for children added later, e.g. the online badge).
func _apply_done() -> void:
	var k := DONE_ALPHA if done_place > 0 else 1.0
	self_modulate.a = k
	for ch in get_children():
		if ch is CanvasItem and ch != _place_badge:
			(ch as CanvasItem).modulate.a = k

const DONE_ALPHA := 0.5

## The dice slot in global (canvas) coordinates, including the tile's scale: put the dice there.
func dice_slot_rect() -> Rect2:
	var r := Rect2(_slot_pos(), Vector2(SLOT, SLOT))
	var xf := get_global_transform()
	return Rect2(xf * r.position, r.size * xf.get_scale())

## The slot in the tile's own coordinates (unscaled).
func dice_slot_local() -> Rect2:
	return Rect2(_slot_pos(), Vector2(SLOT, SLOT))

## The avatar's rect in global coordinates (coin flights, pops).
func avatar_rect() -> Rect2:
	var xf := get_global_transform()
	return Rect2(xf * _ava_pos(), Vector2(AVA, AVA) * xf.get_scale())

## Height of the laid-out tile (card + pills), unscaled.
func tile_height() -> float:
	return custom_minimum_size.y


# ---------------------------------------------------------------------------------------------------------------
# Avatars (shared with ResultScreen and anything that shows a player)
# ---------------------------------------------------------------------------------------------------------------

## A player's avatar of `px` size: "you" = equipped avatar and frame; "cpu" = the café mascot (cpu_hint: id or
## name; unknown names fall back by colour); "human" = the pawn tile of that colour.
static func make_avatar(c: int, kind_: String, px: float, cpu_hint := "") -> Control:
	if kind_ == "you":
		return Collection.make_avatar(px)
	var t := AvatarTile.new()
	t.color_index = posmod(c, 4)
	t.art = mascot_texture(cpu_hint, c) if kind_ == "cpu" else null
	t.pawn = kind_ != "cpu"
	t.custom_minimum_size = Vector2(px, px)
	t.size = Vector2(px, px)
	return t

## The mascot art (transparent square) for a computer player: id or name ("Mocha", "biscotti").
static func mascot_texture(hint: String, c := 0) -> Texture2D:
	var id := hint.to_lower().strip_edges()
	if not CPU_IDS.has(id):
		id = CPU_IDS[posmod(c - 1, 3)]
	return UIKit.svg("res://assets/avatars/cpu_%s.svg" % id)

## The tile frame for player c: the full colour on its turn, a lighter shade (half way to white) while waiting.
static func frame_color(c: int, on: bool) -> Color:
	var col: Color = Palette.PLAYER[posmod(c, 4)]
	return col if on else col.lerp(Color.WHITE, 0.5)

## The text colour for player c's name on cream (PLAYER_DARK pulled towards ink until it reads; yellow needs most).
static func name_color(c: int) -> Color:
	c = posmod(c, 4)
	return (Palette.PLAYER_DARK[c] as Color).lerp(Palette.INK_STRONG, 0.45 if c == 2 else 0.18)


## A rounded tile in the player's colour (top light, bottom full) with a white rim, and art over it:
## a mascot (art) or the white pawn (pawn = true).
class AvatarTile extends Control:
	var color_index := 0
	var art: Texture2D
	var pawn := false
	var desaturate := false
	static var _grad := {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var s := minf(size.x, size.y)
		if s <= 0:
			return
		var o := (size - Vector2(s, s)) / 2.0
		var rim := maxf(2.0, round(s * 0.045))
		var r := s * 0.28
		var outer := StyleBoxFlat.new()
		outer.bg_color = Color.WHITE
		outer.set_corner_radius_all(int(r))
		outer.corner_detail = 10
		outer.anti_aliasing = true
		outer.shadow_size = int(maxf(2.0, s * 0.05))
		outer.shadow_offset = Vector2(0, s * 0.03)
		outer.shadow_color = Palette.shadow(0.25)
		draw_style_box(outer, Rect2(o, Vector2(s, s)))
		var tile := Rect2(o + Vector2(rim, rim), Vector2.ONE * (s - 2.0 * rim))
		draw_texture_rect(_tile_tex(color_index, int(tile.size.x)), tile, false)
		if pawn or art == null:
			var p := UIKit.svg("pawn_icon")
			if p:
				var ps := tile.size.x * 0.56
				draw_texture_rect(p, Rect2(tile.get_center() - Vector2(ps, ps) / 2.0 - Vector2(0, tile.size.x * 0.02), Vector2(ps, ps)), false)
		else:
			var a := tile.grow(-tile.size.x * 0.03)
			draw_texture_rect(art, a, false)

	## Rounded-corner gradient tile as a cached texture (SVG from palette colours; no literals).
	static func _tile_tex(c: int, px: int) -> Texture2D:
		px = clampi(px, 16, 512)
		var key := "%d:%d" % [c, px]
		if _grad.has(key):
			return _grad[key]
		var top: Color = (Palette.TINT[c] as Color).lerp(Color.WHITE, 0.25)
		var mid: Color = (Palette.PLAYER[c] as Color).lerp(Palette.TINT[c], 0.35)
		var bot: Color = Palette.PLAYER[c]
		var svg := ('<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40"><defs>'
			+ '<linearGradient id="g" x1="0" y1="0" x2="0.25" y2="1"><stop offset="0" stop-color="#%s"/>' % top.to_html(false)
			+ '<stop offset="0.55" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></linearGradient>' % [mid.to_html(false), bot.to_html(false)]
			+ '</defs><rect width="40" height="40" rx="10" fill="url(#g)"/>'
			+ '<ellipse cx="20" cy="9" rx="17" ry="8" fill="#ffffff" fill-opacity="0.18"/></svg>')
		var img := Image.new()
		img.load_svg_from_string(svg, px / 40.0)
		img.generate_mipmaps()
		var t := ImageTexture.create_from_image(img)
		_grad[key] = t
		return t


## One of the 4 home pips: a player-colour dot when that pawn is home, else a white dot with a colour ring.
class Pip extends Control:
	var color := Color.WHITE
	var filled := false

	func _init() -> void:
		custom_minimum_size = Vector2(10, 10)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c, r, color, true, -1.0, true)
		if not filled:
			draw_circle(c, r - 2.0, Color.WHITE, true, -1.0, true)


## A round place badge: 1st gold (crown above), 2nd silver, 3rd bronze, 4th plain.
class PlaceBadge extends Control:
	var n := 1

	static func make(n_: int, px := 26.0) -> PlaceBadge:
		var b := PlaceBadge.new()
		b.n = n_
		b.custom_minimum_size = Vector2(px, px)
		b.size = Vector2(px, px)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return b

	static func face_color(n_: int) -> Color:
		match n_:
			1: return Palette.GOLD
			2: return Palette.SILVER
			3: return Palette.BRONZE
		return Palette.CHIP

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size / 2.0
		var face := face_color(n)
		draw_circle(c + Vector2(0, 1.5), s / 2.0, Palette.shadow(0.3), true, -1.0, true)
		draw_circle(c, s / 2.0, Color.WHITE, true, -1.0, true)
		draw_circle(c, s / 2.0 - 2.0, face, true, -1.0, true)
		draw_circle(c - Vector2(0, s * 0.12), s * 0.26, Color(1, 1, 1, 0.22), true, -1.0, true)
		var f := UIKit.font_display()
		var fs := int(s * 0.52)
		var t := str(n)
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col := Palette.ON_HONEY if n == 1 else Palette.INK
		draw_string(f, Vector2(c.x - w / 2.0, c.y + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# ---------------------------------------------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------------------------------------------

func _build_styles() -> void:
	var col: Color = Palette.PLAYER[color_index]
	_sb_card = UIKit.box(Palette.GLASS, UIKit.R.lg + 2, UIKit.BW.rim, frame_color(color_index, false))
	_sb_card.border_width_bottom = UIKit.LIP.md + 1
	UIKit.shade(_sb_card, "md")
	_sb_card_on = _sb_card.duplicate()
	_sb_card_on.set_border_width_all(UIKit.BW.card)
	_sb_card_on.border_width_bottom = UIKit.LIP.md + 2
	_sb_card_on.border_color = col
	_sb_card_on.bg_color = Palette.CARD
	_sb_slot = UIKit.box(Palette.CHIP.lerp(Palette.TINT[color_index], 0.45), UIKit.R.md, 0)
	_sb_slot.border_width_top = 3
	_sb_slot.border_color = Palette.TAB_HOVER.lerp(Palette.TINT[color_index], 0.3).darkened(0.06)
	_sb_glow = StyleBoxFlat.new()
	_sb_glow.bg_color = Color(col, 0.0)
	_sb_glow.set_corner_radius_all(UIKit.R.lg + 6)
	_sb_glow.corner_detail = 10
	_sb_glow.shadow_color = Color(col.lightened(0.1), 0.7)
	_sb_glow.shadow_size = 14
	_sb_you = StyleBoxFlat.new()
	_sb_you.bg_color = col
	_sb_you.set_corner_radius_all(int(AVA * 0.3) + 2)
	_sb_you.corner_detail = 10
	_sb_you.anti_aliasing = true
	_sb_mover = StyleBoxFlat.new()
	_sb_mover.draw_center = false
	_sb_mover.set_border_width_all(UIKit.BW.rim)
	_sb_mover.border_color = Palette.TEAL_SOFT
	_sb_mover.set_corner_radius_all(int(AVA * 0.3) + 3)
	_sb_mover.corner_detail = 10
	_sb_mover.anti_aliasing = true
	_sb_mover.shadow_color = Color(Palette.TEAL_GLOW, 0.8)
	_sb_mover.shadow_size = 8

func _pill(child: Control, bg: Color, h: float) -> PanelContainer:
	var p := PanelContainer.new()
	var st := UIKit.box(bg, UIKit.R.pill, 0, Color.TRANSPARENT)
	UIKit.shade(st, "sm")
	UIKit.pad(st, 9, 0)
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(0, h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(child)
	return p

func _small_tag(t: String, bg: Color, fg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var st := UIKit.box(bg, UIKit.R.pill, 0, Color.TRANSPARENT)
	UIKit.pad(st, 5, 0)
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := UIKit.label(t, UIKit.FS.tag, fg, UIKit.font_caps(900, 1), HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_constant_override("line_spacing", -2)
	p.add_child(l)
	return p

func _ava_pos() -> Vector2:
	return Vector2(PAD if side != "right" else PAD + SLOT + GAP, PAD)

func _slot_pos() -> Vector2:
	return Vector2(PAD + AVA + GAP if side != "right" else PAD, PAD)

func _layout() -> void:
	if _ava:
		_ava.position = _ava_pos()
		_ava.size = Vector2(AVA, AVA)
	var y := CARD_H - NAME_OVERLAP
	var maxw := CARD_W - 6.0
	var nw := UIKit.font_body(900).get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.FS.label).x + 2.0
	var tagw := _cpu_tag.get_combined_minimum_size().x + UIKit.SPACE.xs if _cpu_tag.visible else 0.0
	_name.custom_minimum_size.x = minf(nw, maxw - 18.0 - tagw)      # an ellipsis-trimmed Label reports no width
	for p: Control in [_name_pill, _prog_pill, _chip_pill]:
		if not p.visible:
			continue
		p.size = Vector2.ZERO
		var m := p.get_combined_minimum_size()
		p.size = Vector2(minf(m.x, maxw), m.y)
		p.position = Vector2(round((CARD_W - p.size.x) / 2.0), y)
		y += p.size.y + 3.0
	if _chip_pill.visible:
		var dots := _chip_dots.get_combined_minimum_size().x + UIKit.SPACE.xs if _chip_dots.visible else 0.0
		_chip.custom_minimum_size.x = minf(UIKit.font_body(900).get_string_size(_chip.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.FS.small).x + 2.0, maxw - 18.0 - dots)
	var h := y - 3.0
	custom_minimum_size = Vector2(CARD_W, h)
	if size != custom_minimum_size:
		size = custom_minimum_size
	pivot_offset = Vector2(0.0 if side != "right" else CARD_W, CARD_H / 2.0)
	if _sym:
		var ap := _ava_pos()
		_sym.position = ap + Vector2(AVA - _sym.size.x + 5, -5)
	if _place_badge:
		var ap2 := _ava_pos()
		_place_badge.position = ap2 + Vector2(-8, -8)
	queue_redraw()

func _refresh_symbol() -> void:
	var on := _colorblind()
	if on and _sym == null:
		_sym = PanelContainer.new()
		var st := UIKit.box(Color.WHITE, UIKit.R.pill, 0, Color.TRANSPARENT)
		UIKit.shade(st, "sm")
		UIKit.pad(st, 3)
		_sym.add_theme_stylebox_override("panel", st)
		_sym.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sym.add_child(UIKit.symbol(color_index, 14))
		add_child(_sym)
		_sym.size = _sym.get_combined_minimum_size()
	if _sym:
		_sym.visible = on

func _colorblind() -> bool:
	return _pref("colorblind")

func _reduce_motion() -> bool:
	return _pref("reduce_motion")

## A boolean preference from the Save autoload (false when there is none, e.g. in tools).
static func _pref(key: String) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var save: Node = tree.root.get_node_or_null("Save") if tree and tree.root else null
	if save == null:
		return false
	var pr: Variant = save.get("prefs")
	return pr is Dictionary and bool((pr as Dictionary).get(key, false))

func _animate_scale() -> void:
	var k := ACTIVE_SCALE if active else IDLE_SCALE
	if _scale_tw:
		_scale_tw.kill()
	if not is_inside_tree() or _reduce_motion():
		scale = Vector2(k, k)
		_scale_tw = create_tween() if is_inside_tree() else null
		return
	_scale_tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_scale_tw.tween_property(self, "scale", Vector2(k, k), 0.28 if active else 0.2)

func _enter_tree() -> void:
	_refresh_symbol()
	scale = Vector2.ONE * (ACTIVE_SCALE if active else IDLE_SCALE)
	_layout()

func _process(delta: float) -> void:
	_t += delta
	_glow = 0.5 + 0.5 * sin(_t * TAU / 1.4)
	queue_redraw()

func _draw() -> void:
	var card := Rect2(Vector2.ZERO, Vector2(CARD_W, CARD_H))
	if active:
		var a := 0.75 if _reduce_motion() else 0.45 + 0.45 * _glow
		_sb_glow.shadow_color.a = a
		_sb_glow.shadow_size = int(10 + 8 * _glow)
		draw_style_box(_sb_glow, card.grow(-4))
	draw_style_box(_sb_card_on if active else _sb_card, card)
	draw_style_box(_sb_slot, Rect2(_slot_pos(), Vector2(SLOT, SLOT)))
	if kind == "you":                       # the equipped avatar has its own colours: a ring in the seat colour
		draw_style_box(_sb_you, Rect2(_ava_pos(), Vector2(AVA, AVA)).grow(2))
	if mover:
		draw_style_box(_sb_mover, Rect2(_ava_pos(), Vector2(AVA, AVA)).grow(3))
