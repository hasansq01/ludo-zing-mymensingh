class_name ProfileSheet
extends Sheet
## Profile: a full screen in the game look (the mock-up's Profile), opened from Home's avatar chip. It covers Home's
## bottom bar; the round red X in the corner and Back close it. The café shows through the top (blurred, fading into
## the brown page ground: Room), then, from the top:
##   the equipped avatar big in its equipped frame; the name on the equipped nameplate (3D art, 3-slice) with the
##     equipped badge and a pencil: the pencil (or a tap on the plate) shows the name field under it (1-14
##     characters, trimmed, inner spaces collapsed, not "You"; Save shows once it changed);
##   the level pill and the XP bar ("1,488 / 2,400 XP");
##   four wood stat tiles (Ludo vs computer: Played, Wins, Win rate, Best streak);
##   My table: what is in use, on rarity tiles (Frame, Pawns, Dice); a tap opens the Inventory there;
##   Ranks (the Leaderboard) and Customise (the Inventory's Look tab);
##   below: Achievements (earned count, rewards to claim, the coins they fly to, every medal with its progress and
##     Claim), Account (Google Play Games), and the other stats (Snakes & Ladders, pairs, Pass & Play, coins earned).
## Anything that changes the profile (a new name, a claim, an equip) writes Save.profile, emits Save.changed (the HUD
## re-renders) and profile_changed.

signal profile_changed
signal inventory_requested(tab: String)  ## main: close this screen and open the Inventory on this category

const MAX_NAME := 14
const MEDAL_PX := 52.0
## Economy v1: every achievement also pays this many gems (the server decides; shown only with an account).
const ACH_GEMS := 10
## Loaded at run time (not by class name), so the Profile still compiles while the Shop is being changed.
const SHOP_SCRIPT := "res://scripts/ui/sheets/shop_sheet.gd"
const COLLECTION_SCRIPT := "res://scripts/ui/sheets/collection_sheet.gd"

## The game look's colours (mock-up Profile.dc.html).
const GROUND := Color("#2b140a")         ## the page's brown ground
const WOOD_TOP := Color("#5a2c16")
const WOOD_BOTTOM := Color("#3b1a0c")
const WOOD_RIM := Color("#8a4b26")
const SAND := Color("#e7c7a6")           ## small text on wood
const GOLD_TEXT := Color("#ffd45e")      ## section titles
const INK := Color("#4a2212")            ## text on cream / gold buttons
const OUTLINE := Color("#3b1a0c")
const MINT := Color("#5fe0c8")           ## Synced / Claimed on wood
const AVATAR_PX := 150.0                 ## the avatar's box: a 120 px tile, the frame art 210 px (mock-up)
const SIDE := 14                         ## the page's side inset
## The stat tiles: [stat key, label, icon, icon ground].
const STATS := [
	["played", "Played", "play", Color("#3b7be0")],
	["wins", "Wins", "trophy", Color("#f7a928")],
	["winRate", "Win rate", "%", Color("#2fa86b")],
	["bestStreak", "Best streak", "flame", Color("#e5484d")],
]
## The stat icons (24 px viewBox paths of the mock-up), drawn white.
const ICONS := {
	play = '<path d="M8 5l12 7-12 7z" fill="#fff"/>',
	trophy = '<path d="M6 3h12v3a6 6 0 0 1-12 0zM10 13h4v4h3v3H7v-3h3z" fill="#fff"/>',
	flame = '<path d="M13 2c1 4-3 5-3 9a3 3 0 0 0 6 0c0-1-.4-2-1-3 3 1 5 4 5 7a8 8 0 0 1-16 0c0-6 6-8 9-13z" fill="#fff"/>',
	pencil = '<path d="M4 20h4L19 9l-4-4L4 16z" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>',
}
## My table: [category in the Inventory, label, kind for the rarity].
const TABLE := [["frames", "Frame", "frame"], ["pawns", "Pawns", "pawn"], ["dice", "Dice", "dice"]]
## The labels of STATS and TABLE for the extractor (shown through tr()).
const _LABEL_TEXT := ["Played", "Wins", "Win rate", "Best streak", "Frame", "Pawns", "Dice"]  # l10n

static var _icons := {}                  # icon key -> Texture2D (kept: textures loaded in _draw must outlive it)

var pane := "profile"
var _room: ColorRect
var _ava: Collection.AvatarView
var _plate: Collection.PlateView
var _plate_back: GamePanel
var _pencil: Button
var _edit_box: VBoxContainer
var _editing := false
var _level: LevelBadge
var _xp: Meter
var _coins: CoinAmount
var _name_edit: LineEdit
var _save_btn: Button
var _err: Label
var _stats_note: Label
var _stat_vals := {}                  # stat key -> value Label (or CoinAmount for coinsEarned)
var _table_tiles := {}                # category -> {panel, slot, id}
var _profile_pane: VBoxContainer
var _ach_pane: VBoxContainer
var _ach_count: PanelContainer        # the red count of rewards waiting, by the Achievements title
var _ach_earned: Label
var _ach_coins: CoinAmount            # coins waiting to be claimed
var _ach_claim: Control
var _ach_updaters: Array[Callable] = []
var _claim_btns := {}                 # achievement id -> its Claim button
var _flying := 0                      # coin flights still landing (the counter counts up on its own meanwhile)
var _desat: Shader
var _acct_box: Control                 # the whole Account section (heading + card)
var _acct_title: Label
var _acct_note: Label
var _acct_synced: Control
var _acct_button: Button
var _acct_signing := false


func _init(width := 360.0) -> void:
	super("", width, true, Sheet.LOOK_PM)
	var bg := StyleBoxEmpty.new()
	bg.content_margin_left = SIDE
	bg.content_margin_right = SIDE
	make_page(bg, false)
	_room = _make_room()
	add_child(_room)
	move_child(_room, backdrop.get_index() + 1)       # over the (clear) backdrop, under the card
	body.add_theme_constant_override("separation", 0)
	var list := add_scroll_body(0)
	_tint_fade(scroll_box.get_parent())

	_profile_pane = UIKit.vbox(0)
	_profile_pane.name = "Me"
	_build_hero(_profile_pane)
	_build_stats(_profile_pane)
	_build_table(_profile_pane)
	_build_buttons(_profile_pane)
	list.add_child(_profile_pane)
	_ach_pane = UIKit.vbox(10)
	_ach_pane.name = "Achievements"
	_build_ach()
	list.add_child(UIKit.margin(_ach_pane, 0, 30, 0, 0))
	_acct_box = _section(tr("Account"), _build_account())
	_acct_box.name = "AccountBox"
	list.add_child(UIKit.margin(_acct_box, 0, 26, 0, 0))
	list.add_child(UIKit.margin(_build_more_stats(), 0, 26, 0, 28))
	_refresh()


func _ready() -> void:
	Save.changed.connect(_refresh)
	var acc := Account.instance()
	if acc != null:
		acc.account_changed.connect(_refresh_account)
		acc.signed_in_changed.connect(_refresh_account)
	resized.connect(_fit_room)
	scroll_box.get_v_scroll_bar().value_changed.connect(func(v: float):
		(_room.material as ShaderMaterial).set_shader_parameter("scroll", v))
	_fit_room()

## "profile" (the top) | "ach" (scrolled to the Achievements).
func show_pane(key: String) -> void:
	pane = key if key == "ach" else "profile"
	if scroll_box == null:
		return
	if pane == "ach":
		_scroll_to_ach.call_deferred()
	else:
		scroll_box.scroll_vertical = 0

func _scroll_to_ach() -> void:
	if is_instance_valid(_ach_pane) and is_inside_tree():
		scroll_box.scroll_vertical = int(_ach_pane.get_parent().position.y)

## The scroll fade blends into the page's brown ground.
func _tint_fade(wrap: Node) -> void:
	var fade := wrap.get_node_or_null("Fade") as TextureRect
	if fade == null:
		return
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(GROUND, 0.0), GROUND])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 4
	gt.height = 32
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	fade.texture = gt


# =====================================================================================================================
# The room behind: the café (what is drawn under this screen), softly blurred, fading into the brown ground,
# scrolling away with the content
# =====================================================================================================================

const ROOM_SHADER := """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float height = 844.0;      // this rect's height (px)
uniform float top = 0.0;           // where the content starts (the status bar's height)
uniform float scroll = 0.0;        // how far the page is scrolled: the room goes up with the content
uniform vec2 px = vec2(0.0025, 0.0014);   // one px in screen UV
uniform vec4 ground : source_color = vec4(0.169, 0.078, 0.039, 1.0);
// mock-up: linear-gradient(rgba(43,20,10,.2) 0%, rgba(43,20,10,.55) 30%, #2b140a 42%) of an 844 px screen, over the
// room blurred 2 px and saturated 1.1
void fragment() {
	float y = UV.y * height - top + scroll;
	if (y >= 354.0) {
		COLOR = ground;
	} else {
		vec3 c = vec3(0.0);
		for (int i = -2; i <= 2; i++) {
			for (int j = -2; j <= 2; j++) {
				c += texture(screen_tex, SCREEN_UV + vec2(float(i), float(j)) * px).rgb;
			}
		}
		c /= 25.0;
		float g = dot(c, vec3(0.2126, 0.7152, 0.0722));
		c = mix(vec3(g), c, 1.1);
		float a = y < 253.0 ? mix(0.2, 0.55, max(y, 0.0) / 253.0) : mix(0.55, 1.0, (y - 253.0) / 101.0);
		COLOR = vec4(mix(c, ground.rgb, a), 1.0);
	}
}"""

static var _room_shader: Shader

func _make_room() -> ColorRect:
	var r := ColorRect.new()
	r.name = "Room"
	r.color = Color.WHITE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _room_shader == null:
		_room_shader = Shader.new()
		_room_shader.code = ROOM_SHADER
	var m := ShaderMaterial.new()
	m.shader = _room_shader
	m.set_shader_parameter("ground", GROUND)
	r.material = m
	return r

func _fit_room() -> void:
	if _room == null or not is_inside_tree():
		return
	var m := _room.material as ShaderMaterial
	var vp := get_viewport_rect().size
	m.set_shader_parameter("height", maxf(1.0, size.y))
	m.set_shader_parameter("top", _safe_top())
	m.set_shader_parameter("px", Vector2(1.0 / maxf(1.0, vp.x), 1.0 / maxf(1.0, vp.y)))


# =====================================================================================================================
# Small pieces of the game look
# =====================================================================================================================

## A wood tile: the dark brown top-to-bottom gradient with a 2 px rim (the stat tiles, the cards below).
static func wood(radius := 16.0) -> GamePanel:
	var p := GamePanel.vertical(WOOD_TOP, WOOD_BOTTOM)
	p.radius = radius
	p.border = 2.0
	p.border_color = WOOD_RIM
	return p

## A section title: gold Lilita One with a dark edge ("My table").
static func section_title(text: String) -> Label:
	var l := ShopSheet.outlined(text, 20, GOLD_TEXT, 4)
	l.name = "Section"
	return l

## A white icon from a 24 px path of the mock-up, rasterised once.
static func icon_tex(key: String, px := 48) -> Texture2D:
	var k := "%s:%d" % [key, px]
	if not _icons.has(k):
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">%s</svg>' % str(ICONS[key])
		var img := Image.new()
		if img.load_svg_from_string(svg, px / 24.0) != OK:
			img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		_icons[k] = ImageTexture.create_from_image(img)
	return _icons[k]

static func _tex_rect(t: Texture2D, px: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## A chunky button: a cream (Ranks) or gold (Customise) gradient face with a darker lip inside its bottom edge, an
## icon and Lilita One text in dark brown. The Button itself is the tap target (54 px).
static func chunky_button(text: String, icon: Texture2D, gold: bool) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, 54)
	var face := GamePanel.vertical(Color("#ffd866") if gold else Color("#fff6e6"), Color("#f7a928") if gold else Color("#ffe2bd"))
	face.name = "Face"
	face.radius = 16.0
	face.lip = 5.0
	face.lip_color = Color("#b86a0a") if gold else Color("#d9a86a")
	b.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(cc)
	var h := UIKit.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon:
		h.add_child(_tex_rect(icon, 28))
	var l := UIKit.label(text, 18, INK, UIKit.font_display())
	l.name = "Text"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	cc.add_child(h)
	b.button_down.connect(func():                 # pressed: the face sinks onto its lip
		face.lip = 2.0
		face.offset_top = 3.0)
	b.button_up.connect(func():
		face.lip = 5.0
		face.offset_top = 0.0)
	UIKit.wire_press(b)
	return b


# =====================================================================================================================
# The top: avatar, nameplate (+ the name field), level and XP
# =====================================================================================================================

func _build_hero(v: VBoxContainer) -> void:
	_ava = Collection.make_avatar(AVATAR_PX) as Collection.AvatarView
	_ava.name = "Avatar"
	var ac := CenterContainer.new()
	ac.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ac.add_child(_ava)
	v.add_child(UIKit.margin(ac, 0, 64, 0, 0))         # the frame's art (210 px) starts 34 px down, like the mock-up

	# the nameplate: the equipped plate's art with the name, the badge and the pencil (Plain: a wood capsule)
	_plate = Collection.make_plate("", Collection.DEFAULT_PLATE, "", 26, true, 190.0)
	_plate.height_k = 2.5
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pencil = Button.new()
	_pencil.name = "EditName"
	_pencil.focus_mode = Control.FOCUS_NONE
	_pencil.tooltip_text = tr("Change name")
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		_pencil.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_pencil.custom_minimum_size = Vector2(30, 30)
	_pencil.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pen := icon_tex("pencil", 42)
	_pencil.draw.connect(func():
		var c := _pencil.size / 2.0
		_pencil.draw_circle(c, 15.0, Color(1, 1, 1, 0.28 if _editing else 0.15), true, -1.0, true)
		_pencil.draw_texture_rect(pen, Rect2(c - Vector2(7, 7), Vector2(14, 14)), false))
	_pencil.pressed.connect(_toggle_edit)
	UIKit.wire_press(_pencil)
	_plate.get_child(0).add_child(_pencil)
	_plate_back = GamePanel.new()
	_plate_back.name = "Nameplate"
	_plate_back.mouse_filter = Control.MOUSE_FILTER_STOP
	_plate_back.add_child(_plate)
	UIKit.on_tap(_plate_back, _toggle_edit)
	var pc := CenterContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(_plate_back)
	v.add_child(UIKit.margin(pc, 0, 12, 0, 0))

	_edit_box = _build_name()
	_edit_box.name = "NameEdit"
	_edit_box.custom_minimum_size.x = 300
	var ec := CenterContainer.new()
	ec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ec.add_child(_edit_box)
	v.add_child(ec)
	_edit_box.visible = false

	# the level pill over the start of the XP bar
	_level = LevelBadge.new(1, 28.0)
	_level.set_even(true)
	_xp = Meter.new("game", 22, true, "XP")
	_xp.inset_left = 10.0
	_xp.show_behind_parent = true            # the pill stays over the bar by draw order
	var row := HBoxContainer.new()
	row.name = "Level"
	row.add_theme_constant_override("separation", -10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.x = 300
	row.add_child(_level)
	row.add_child(_xp)
	var lc := CenterContainer.new()
	lc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lc.add_child(row)
	v.add_child(UIKit.margin(lc, 0, 6, 0, 0))

## The name field (under the plate while editing); Save appears once the name differs from the saved one; the inline
## error line.
func _build_name() -> VBoxContainer:
	var v := UIKit.vbox(UIKit.SPACE.sm)
	var row := UIKit.hbox(UIKit.SPACE.sm)
	_name_edit = LineEdit.new()
	_name_edit.max_length = MAX_NAME
	_name_edit.text = str(Save.profile.get("name", "You"))
	_name_edit.placeholder_text = tr("Your name")
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_edit.custom_minimum_size = Vector2(0, UIKit.TAP)
	_name_edit.select_all_on_focus = true
	_name_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_name_edit.add_theme_font_override("font", UIKit.font_body(800))
	_name_edit.text_changed.connect(func(_t: String): _validate(true))
	_name_edit.text_submitted.connect(func(_t: String): _save_name())
	row.add_child(_name_edit)
	_save_btn = UIKit.button(tr("Save"), "honey", "sm")
	_save_btn.custom_minimum_size.x = 84
	_save_btn.pressed.connect(_save_name)
	row.add_child(_save_btn)
	v.add_child(UIKit.margin(row, 0, 10, 0, 0))
	_err = UIKit.label("", UIKit.FS.small, Color("#ff9b8f"), UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER)
	_err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_err)
	_validate(false)
	return v

## The pencil (or a tap on the plate): show / hide the name field. Hiding it puts the saved name back.
func _toggle_edit() -> void:
	_set_editing(not _editing)

func _set_editing(on: bool) -> void:
	_editing = on
	_edit_box.visible = on
	_pencil.queue_redraw()
	if on:
		_name_edit.text = str(Save.profile.get("name", "You"))
		_validate(false)
		if is_inside_tree():
			_name_edit.grab_focus()
	else:
		_name_edit.release_focus()
		_name_edit.text = str(Save.profile.get("name", "You"))
		_validate(false)

## Plain (no plate art): the name on a wood capsule in white; a plate: its own art carries the name.
func _style_plate(plain: bool) -> void:
	if plain:
		_plate_back.mode = 1
		_plate_back.c0 = WOOD_TOP
		_plate_back.c1 = WOOD_TOP.lerp(WOOD_BOTTOM, 0.5)
		_plate_back.c2 = WOOD_BOTTOM
		_plate_back.mid = 0.5
		_plate_back.radius = 14.0
		_plate_back.border = 2.0
		_plate_back.border_color = WOOD_RIM
		_plate_back.pad = 4.0
		_plate.label.add_theme_color_override("font_color", Color.WHITE)
	else:
		for k in ["c0", "c1", "c2", "border_color"]:
			_plate_back.set(k, Color(0, 0, 0, 0))
		_plate_back.border = 0.0
		_plate_back.pad = 0.0
	if plain or _plate.label.get_theme_constant("outline_size") > 0:   # the mock-up's dark edge on a light name
		_plate.label.add_theme_constant_override("outline_size", 6)
		_plate.label.add_theme_color_override("font_outline_color", OUTLINE)


# =====================================================================================================================
# Stats, My table, the buttons
# =====================================================================================================================

## Four wood tiles in a row: a coloured round icon, the number big, the label small.
func _build_stats(v: VBoxContainer) -> void:
	var g := UIKit.grid(4, 8)
	g.name = "Stats"
	for it: Array in STATS:
		g.add_child(_stat_tile(it[0], tr(it[1]), it[2], it[3]))
	v.add_child(UIKit.margin(g, 0, 20, 0, 0))
	_stats_note = UIKit.paragraph(tr("Finish a game to start your stats."), 13, SAND, HORIZONTAL_ALIGNMENT_CENTER)
	_stats_note.add_theme_font_override("font", UIKit.font_body(800))
	var nm := UIKit.margin(_stats_note, 0, 8, 0, 0)
	nm.name = "StatsNote"
	v.add_child(nm)

func _stat_tile(key: String, caption: String, icon: String, col: Color) -> GamePanel:
	var p := wood(16.0)
	p.name = "Stat_" + key
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tv := UIKit.vbox(4)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon != "":
		var dot := GamePanel.vertical(col.lightened(0.08), col.darkened(0.06))
		dot.radius = 17.0
		dot.custom_minimum_size = Vector2(34, 34)
		dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if icon == "%":
			var pl := UIKit.label("%", 13, Color.WHITE, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
			pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			dot.add_child(pl)
		else:
			var cc := CenterContainer.new()
			cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cc.add_child(_tex_rect(icon_tex(icon), 18))
			dot.add_child(cc)
		tv.add_child(dot)
	var val := ShopSheet.outlined("0", 22, Color.WHITE, 4, HORIZONTAL_ALIGNMENT_CENTER)
	val.name = "Value"
	_stat_vals[key] = val
	tv.add_child(val)
	var lab := UIKit.label(caption, 11, SAND, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(lab)
	p.add_child(UIKit.margin(tv, 2, 10, 2, 8))
	return p

## "My table": what is in use, each on its rarity's tile (Frame, Pawns, Dice). A tap opens the Inventory there.
func _build_table(v: VBoxContainer) -> void:
	v.add_child(UIKit.margin(section_title(tr("My table")), 2, 16, 0, 8))
	var g := UIKit.grid(3, 10)
	g.name = "MyTable"
	for t: Array in TABLE:
		g.add_child(_table_tile(t[0], tr(t[1])))
	v.add_child(g)

func _table_tile(cat: String, caption: String) -> GamePanel:
	var p := GamePanel.radial(Color.WHITE, Color.WHITE, Color.WHITE)
	p.name = "Table_" + cat
	p.radius = 18.0
	p.border = 3.0
	p.lip = 4.0
	p.mid = 0.45
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(0, 134)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(root)
	var slot := Control.new()                    # the art (rebuilt when what is in use changes)
	slot.name = "Art"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(slot)
	var l := ShopSheet.outlined(caption, 13, Color.WHITE, 4, HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	l.offset_top = -26
	l.offset_bottom = -6
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(l)
	UIKit.on_tap(p, func() -> void:
		UIKit.press_fx()
		_open_inventory(cat))
	_table_tiles[cat] = {panel = p, slot = slot, id = ""}
	return p

## The equipped item's id for a My table category.
static func _table_id(cat: String) -> String:
	match cat:
		"frames": return Collection.equipped("frame")
		"pawns": return Catalog.pawn_in_use()
		"dice": return Catalog.dice_in_use()
	return ""

func _refresh_table() -> void:
	for t: Array in TABLE:
		var cat: String = t[0]
		var e: Dictionary = _table_tiles[cat]
		var id := _table_id(cat)
		var rar := ShopSheet.rarity(t[2], id)
		var c: Array = ShopSheet.RAR[rar if rar != "" else "common"]
		var p: GamePanel = e.panel
		p.c0 = c[0]; p.c1 = c[1]; p.c2 = c[2]
		p.border_color = c[3]
		p.lip_color = (c[2] as Color).darkened(0.45)
		if e.id == id:
			continue
		e.id = id
		var slot: Control = e.slot
		for ch in slot.get_children():
			slot.remove_child(ch)
			ch.queue_free()
		var art: Control
		var box := Rect2(0, 4, 92, 92)            # the mock-up's places: frame 92 x 92 at 4, pawns 92 x 76 at 10, dice 70 x 74 at 12
		match cat:
			"frames":
				var fa := Collection.FrameArt.new()
				fa.set_frame(id)
				art = fa
			"pawns":
				art = Thumbnailer.pawn_art(id)
				if art is TextureRect:
					(art as TextureRect).stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				box = Rect2(0, 2, 140, 105)       # the baked pair has room around it: its pawns come out ~84 x 75
			"dice":
				art = Thumbnailer.dice_art(id, 62)
				box = Rect2(0, 18, 62, 62)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(art)
		art.set_anchors_preset(Control.PRESET_CENTER_TOP)
		art.offset_left = -box.size.x / 2.0
		art.offset_right = box.size.x / 2.0
		art.offset_top = box.position.y
		art.offset_bottom = box.position.y + box.size.y

## Ranks (cream: the Leaderboard) and Customise (gold: the Inventory's Look tab).
func _build_buttons(v: VBoxContainer) -> void:
	var g := UIKit.grid(2, 10)
	g.name = "Buttons"
	var ranks := chunky_button(tr("Ranks"), load("res://assets/ui3d/place_1.webp") as Texture2D, false)
	ranks.name = "Leaderboard"
	ranks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ranks.pressed.connect(_open_leaderboard)
	g.add_child(ranks)
	var look := chunky_button(tr("Customise"), UIKit.svg("res://assets/ui/home/hi_shop.svg"), true)
	look.name = "Inventory"
	look.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	look.pressed.connect(_customise)
	g.add_child(look)
	v.add_child(UIKit.margin(g, 0, 24, 0, 0))

## The other stats, smaller tiles: Snakes & Ladders (played, wins), then pairs, Pass & Play games and coins earned.
func _build_more_stats() -> VBoxContainer:
	var v := UIKit.vbox(10)
	v.name = "MoreStats"
	v.add_child(section_title(tr("Snakes & Ladders")))
	var g := UIKit.grid(2, 8)
	g.add_child(_stat_tile("slPlayed", tr("Played"), "", Color.WHITE))
	g.add_child(_stat_tile("slWins", tr("Wins"), "", Color.WHITE))
	v.add_child(g)
	v.add_child(UIKit.margin(section_title(tr("Overall")), 0, 16, 0, 0))
	var g2 := UIKit.grid(3, 8)
	g2.add_child(_stat_tile("pairsFormed", tr("Pairs formed"), "", Color.WHITE))
	g2.add_child(_stat_tile("ppGames", tr("Pass & Play games"), "", Color.WHITE))
	var coins := _stat_tile("coinsEarned", tr("Coins earned"), "", Color.WHITE)
	var old: Label = _stat_vals.coinsEarned
	var amt := CoinAmount.new(0, "md", "plain")
	amt.set_color(Color.WHITE)
	amt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	old.get_parent().add_child(amt)
	old.get_parent().move_child(amt, old.get_index())
	old.queue_free()
	_stat_vals.coinsEarned = amt
	g2.add_child(coins)
	v.add_child(g2)
	return v


# =====================================================================================================================
# Inventory, Leaderboard
# =====================================================================================================================

## Customise: the Inventory on its Look tab (Avatars).
func _customise() -> void:
	_open_inventory("avatars")

## Forwarder (dev previews): the old name of _customise.
func _open_collection() -> void:
	_customise()

## The Inventory on a category: main swaps this screen for the Inventory screen (Home's bar shows again); without
## main (previews) the Inventory opens over this sheet.
func _open_inventory(cat: String) -> void:
	if _closing:
		return
	if not inventory_requested.get_connections().is_empty():
		inventory_requested.emit(cat)
		return
	var s := _make_shop(cat)
	if s == null:
		return
	var app := _app()
	if app and s.has_signal("room_changed"):           # rooms / dice / scenes put in use there apply at once
		if app.has_method("apply_shop_changes"):
			app.call("apply_shop_changes", s)
		elif app.has_method("_wire_shop"):
			app.call("_wire_shop", s)
	if s.has_signal("changed"):
		s.connect("changed", _on_look_changed)
	s.closed.connect(_on_look_changed)
	s.open(get_parent() if get_parent() else self)

func _on_look_changed() -> void:
	if not is_instance_valid(self) or _closing:
		return
	_refresh()
	profile_changed.emit()

## The Inventory (the Shop showing owned items) on a category; the old Collection when the Shop can't open.
static func _make_shop(cat := "avatars") -> Sheet:
	var sc := load(SHOP_SCRIPT) as GDScript
	if sc and sc.can_instantiate() and _init_arity(sc) >= 3:
		if _init_arity(sc) >= 4:                         # the Inventory variant: no All | Owned row
			return sc.new(cat, float(UIKit.W.catalog), true, true) as Sheet
		return sc.new(cat, float(UIKit.W.catalog), true) as Sheet
	var col := load(COLLECTION_SCRIPT) as GDScript
	if col and col.can_instantiate():
		return col.new("chars") as Sheet
	push_warning("ProfileSheet: neither the Shop nor the Collection can open")
	return null

static func _init_arity(sc: GDScript) -> int:
	for m: Dictionary in sc.get_script_method_list():
		if m.get("name", "") == "_init":
			return (m.get("args", []) as Array).size()
	return 0

func _app() -> Node:
	if not is_inside_tree():
		return null
	var app := get_tree().root.get_node_or_null("Main")
	return app if app else get_tree().root.find_child("Main", true, false)

## The Leaderboard over the Profile.
func _open_leaderboard() -> void:
	var layer := get_parent() as Control
	if layer == null or _closing:
		return
	LeaderboardSheet.new().open(layer)


# =====================================================================================================================
# Account
# =====================================================================================================================

## A section: its gold title above the wood card that holds `content`.
func _section(title: String, content: Control) -> VBoxContainer:
	var v := UIKit.vbox(10)
	v.add_child(section_title(title))
	var p := wood(16.0)
	p.pad = 14.0
	p.add_child(content)
	v.add_child(p)
	return v

## The Account section: "Guest" with the Google Play Games button, or the signed-in Google name with "Synced".
## Only shown where an Account exists (the game; not previews).
func _build_account() -> VBoxContainer:
	var v := UIKit.vbox(UIKit.SPACE.sm)
	var head := UIKit.hbox(UIKit.SPACE.sm)
	_acct_title = ShopSheet.outlined(tr("Guest"), 18, Color.WHITE, 4)
	_acct_title.name = "AccountTitle"
	_acct_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_acct_title.clip_text = true
	_acct_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_acct_title)
	_acct_synced = UIKit.hbox(UIKit.SPACE.xs)
	_acct_synced.name = "Synced"
	_acct_synced.add_child(UIKit.glyph("ic_check", 16, MINT))
	var sl := UIKit.caps_label(tr("Synced"), MINT)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_acct_synced.add_child(sl)
	_acct_synced.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_acct_synced)
	v.add_child(head)
	_acct_note = UIKit.paragraph("", 13, SAND)
	_acct_note.add_theme_font_override("font", UIKit.font_body(800))
	_acct_note.name = "AccountNote"
	v.add_child(_acct_note)
	_acct_button = UIKit.btn(tr("Sign in with Google Play Games"), "honey", "sm")
	_acct_button.name = "GoogleSignIn"
	UIKit.fit_text(_acct_button, 13)
	_acct_button.pressed.connect(_sign_in_google)
	UIKit.deny_disabled(_acct_button, func() -> String:
		return tr("You’re offline. Connect to sign in.") if account_state() == "offline" else "")
	v.add_child(_acct_button)
	return v

## What the Account section shows now (Account.instance() absent: hidden).
func account_state() -> String:
	var acc := Account.instance()
	if acc == null or not acc.enabled:
		return "none"
	if acc.banned:
		return "banned"
	if not acc.is_guest():
		return "linked"
	if not acc.has_session():
		return "offline"
	return "guest" if acc.google_available() else "guest_local"

func _refresh_account() -> void:
	if _acct_box == null or not is_instance_valid(_acct_box):
		return
	var st := account_state()
	_acct_box.visible = st != "none"
	if st == "none":
		return
	var acc := Account.instance()
	_acct_synced.visible = st == "linked"
	_acct_button.visible = st in ["guest", "offline"] and acc.google_available()
	_acct_button.disabled = _acct_signing or st == "offline"
	_acct_button.text = tr("Signing in…") if _acct_signing else tr("Sign in with Google Play Games")
	match st:
		"linked":
			var g := acc.google_name()
			_acct_title.text = g if g != "" else "Google Play Games"
			_acct_note.text = tr("Signed in with Google Play Games. Your progress is saved to your account.")
		"guest":
			_acct_title.text = tr("Guest")
			_acct_note.text = tr("Sign in to keep your progress if you change phones.")
		"guest_local":
			_acct_title.text = tr("Guest")
			_acct_note.text = tr("Your progress is saved on our server. Sign-in with Google Play Games is available on Android.")
		"offline":
			_acct_title.text = tr("Guest · offline")
			_acct_note.text = tr("You’re offline. Your progress will sync when you’re back online.")
		"banned":
			_acct_title.text = tr("Account unavailable")
			_acct_note.text = tr("This account can’t play online right now.")
			_acct_button.visible = false

func _sign_in_google() -> void:
	var acc := Account.instance()
	if acc == null or _acct_signing:
		return
	_acct_signing = true
	_refresh_account()
	var r: Dictionary = await acc.link_google()
	_acct_signing = false
	if not is_instance_valid(self) or _closing:
		return
	_refresh_account()
	if r.get("ok", false):
		Haptics.success()
		Toast.show(self, tr("Signed in as %s") % (acc.google_name() if acc.google_name() != "" else tr("your Google account")), card, 2.0, "good")
		profile_changed.emit()
		return
	var why := Account.google_error_text(str(r.get("error", "")))
	if why != "":
		Haptics.error()
		Toast.show(self, why, card, 2.4, "bad")


# =====================================================================================================================
# Achievements
# =====================================================================================================================

## The title (with the red count of rewards waiting) and the coins the rewards fly to; the earned count and what is
## still to claim; then every achievement on its wood card.
func _build_ach() -> void:
	var head := UIKit.hbox(8)
	var t := section_title(tr("Achievements"))
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	_ach_count = PanelContainer.new()
	_ach_count.name = "Count"
	_ach_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ach_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cs := UIKit.box(Color("#e5484d"), 11, 2, Color.WHITE)
	cs.content_margin_left = 7; cs.content_margin_right = 7; cs.content_margin_top = 0; cs.content_margin_bottom = 1
	_ach_count.add_theme_stylebox_override("panel", cs)
	_ach_count.add_child(UIKit.label("0", 13, Color.WHITE, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER))
	head.add_child(_ach_count)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	_coins = CoinAmount.new(0, "md", "plain")
	_coins.name = "Coins"
	_coins.set_color(Color.WHITE)
	_coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_coins)
	_ach_pane.add_child(head)
	var sum := UIKit.hbox(UIKit.SPACE.sm)
	_ach_earned = UIKit.label("", 13, SAND, UIKit.font_body(900, true))
	_ach_earned.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ach_earned.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sum.add_child(_ach_earned)
	_ach_claim = UIKit.hbox(UIKit.SPACE.sm)               # the rewards still to claim (not the wallet)
	_ach_claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ach_claim.add_child(UIKit.label(tr("To claim"), 13, SAND, UIKit.font_body(900)))
	_ach_coins = CoinAmount.new(0, "sm", "plain")
	_ach_coins.set_color(GOLD_TEXT)
	_ach_coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ach_claim.add_child(_ach_coins)
	sum.add_child(_ach_claim)
	_ach_pane.add_child(UIKit.margin(sum, 2, 0, 0, 0))
	for a: Dictionary in Collection.ACH:
		_ach_pane.add_child(_ach_card(a))

## Medal | name, description, then the teal progress bar with the reward (in progress) or Claimed at its right;
## a finished, unclaimed one shows a full-width Claim button there instead (and wears a gold rim).
func _ach_card(a: Dictionary) -> GamePanel:
	var id: String = a.id
	var goal := int(a.goal)
	var top := UIKit.hbox(12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var well := PanelContainer.new()
	well.custom_minimum_size = Vector2(MEDAL_PX, MEDAL_PX)
	well.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := Collection.make_badge(id, MEDAL_PX - 4.0)
	well.add_child(badge)
	top.add_child(well)

	var txt := UIKit.vbox(2)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := ShopSheet.outlined(tr(a.name), 17, Color.WHITE, 4)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.add_child(t)
	var d := UIKit.paragraph(tr(a.desc), 13, SAND)
	d.add_theme_font_override("font", UIKit.font_body(800))
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.add_child(d)
	var foot := UIKit.hbox(UIKit.SPACE.sm)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := Meter.new("game_teal", 20, true)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(bar)
	var reward := HBoxContainer.new()                      # the coins (and, with an account, the gems) it pays
	reward.add_theme_constant_override("separation", UIKit.SPACE.sm)
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reward.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rc := CoinAmount.new(int(a.reward), "sm", "plain")
	rc.set_color(Color.WHITE)
	reward.add_child(rc)
	if Account.wallet_active():
		var rg := CoinAmount.gems(ACH_GEMS, "sm", "plain", "+")
		rg.set_color(Color.WHITE)
		reward.add_child(rg)
	foot.add_child(reward)
	var claimed := UIKit.hbox(UIKit.SPACE.xs)
	claimed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claimed.add_child(UIKit.glyph("ic_check", 16, MINT))
	var cl := UIKit.caps_label(tr("Claimed"), MINT)
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claimed.add_child(cl)
	foot.add_child(claimed)
	var amt := HBoxContainer.new()
	amt.add_theme_constant_override("separation", UIKit.SPACE.sm)
	var amt_coins := CoinAmount.new(int(a.reward), "xs", "plain")
	amt_coins.set_color(Palette.ON_HONEY)
	amt.add_child(amt_coins)
	if Account.wallet_active():
		var amt_gems := CoinAmount.gems(ACH_GEMS, "xs", "plain", "+")
		amt_gems.name = "Gems"
		amt_gems.set_color(Palette.ON_HONEY)
		amt.add_child(amt_gems)
	var claim := UIKit.button_with(tr("Claim"), amt, "honey", "sm")
	claim.name = "Claim"
	claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reorder_claim(claim)
	claim.custom_minimum_size.x = _claim_width(amt)
	claim.pressed.connect(func(): _claim(id))
	_claim_btns[id] = claim
	foot.add_child(claim)
	txt.add_child(UIKit.margin(foot, 0, 6, 0, 0))
	top.add_child(txt)
	var p := wood(16.0)
	p.name = "Ach_" + id
	p.pad = 12.0
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(top)
	UIKit.on_tap(p, func() -> void:                         # a tap on one not earned yet says what it asks for
		if not bool(Collection.ach_progress(id, Save.profile).get("done", false)):
			UIKit.deny(self, "%s: %s" % [tr(a.name), tr(str(a.desc)).trim_suffix(".").trim_suffix("।")], p, 2.2))

	_ach_updaters.append(func():
		var pr := Collection.ach_progress(id, Save.profile)
		var done := bool(pr.get("done", false))
		var got := bool(pr.get("claimed", false))
		var v := int(pr.get("value", 0))
		bar.set_value(v, goal)
		bar.set_text(("%s / %s" % [Fmt.coins(v), Fmt.coins(goal)]) if goal >= 1000 else "%d / %d" % [v, goal])
		_medal_look(well, badge, done)
		claim.visible = done and not got
		claim.disabled = false
		bar.visible = not claim.visible           # a ready reward: the Claim button takes the row
		reward.visible = not done
		claimed.visible = got
		p.border = 3.0 if claim.visible else 2.0
		p.border_color = GOLD_TEXT if claim.visible else WOOD_RIM)
	return p

## "Claim" first, then the coin amount (button_with puts its child before the text).
static func _reorder_claim(b: Button) -> void:
	var row := b.get_node_or_null("Content")
	var text := row.get_node_or_null("Text") if row else null
	if text:
		row.move_child(text, 0)

## The Claim button's width: its padding, "Claim", the gap and the coin amount (button_with's content row is
## anchored inside the button, so the button doesn't grow with it by itself).
static func _claim_width(amt: Control) -> float:
	var p: Dictionary = UIKit.BTN.sm
	var tw := UIKit.font_display().get_string_size(L10n.t("Claim"), HORIZONTAL_ALIGNMENT_LEFT, -1, int(p.fs)).x
	return ceilf(2.0 * float(p.pad) + tw + UIKit.SPACE.sm + amt.get_combined_minimum_size().x)

## Earned: full colour on a warm well with a gold ring. Not yet: a faded, desaturated medal on a dark well.
func _medal_look(well: PanelContainer, badge: Control, done: bool) -> void:
	var st := UIKit.box(Color("#7a3e08") if done else Color(0, 0, 0, 0.28), UIKit.R.pill, 2 if done else 0, GOLD_TEXT)
	UIKit.pad(st, 5)
	well.add_theme_stylebox_override("panel", st)
	if done:
		badge.material = null
		badge.modulate = Color.WHITE
		return
	if _desat == null:
		_desat = Shader.new()
		_desat.code = """shader_type canvas_item;
void fragment() {
	float g = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR.rgb = mix(vec3(g), COLOR.rgb, 0.4);
}"""
	if not (badge.material is ShaderMaterial and (badge.material as ShaderMaterial).shader == _desat):
		var m := ShaderMaterial.new()
		m.shader = _desat
		badge.material = m
	badge.modulate = Color(1, 1, 1, 0.6)

## Pays the achievement once; the coins fly from its Claim button to the coin counter, which counts up.
func _claim(id: String) -> void:
	var btn: Button = _claim_btns.get(id, null)
	var from := btn.get_global_rect().get_center() if btn and btn.is_inside_tree() else Vector2.INF
	var target := _coin_target()
	var fly := from != Vector2.INF and target != null and is_inside_tree()
	if fly:
		_flying += 1                                     # before the grant: its Save.changed must not jump the counter
	var n := 0
	var gems := 0
	if Account.wallet_active() and is_same(Collection.profile(), Save.profile):
		if btn:
			btn.disabled = true
		var r: Dictionary = await Account.instance().claim_ach(id)
		if not is_instance_valid(self) or _closing:
			return
		n = int(r.get("coins", 0)) if r.get("ok", false) else 0
		gems = int(r.get("gems", 0)) if r.get("ok", false) else 0
		if n <= 0:
			if fly:
				_flying -= 1
			if btn:
				btn.disabled = false
			Haptics.error()
			Toast.show(self, Account.error_text(str(r.get("error", "")), "claim"), card, 2.2, "bad")
			_refresh()
			return
	else:
		n = Collection.claim_ach(id)
	if n <= 0:
		if fly:
			_flying -= 1
		return
	Haptics.success()
	if fly:
		var landed := func() -> void:
			_flying = maxi(0, _flying - 1)
			if _flying == 0 and is_instance_valid(_ava):
				_refresh()
		CoinFly.run(self, from, target, n, landed, Collection.coins())
		if gems > 0:
			Toast.show(self, tr("+%d gems") % gems, card, 1.8, "gem")
	else:
		Toast.show(self, tr("%s: %s coins") % [tr(Collection.ach(id).name), Fmt.gain(n)] + ((" " + tr("+%d gems") % gems) if gems > 0 else ""), card, 1.8, "coin")
	_refresh()
	profile_changed.emit()

## The counter the coins fly to: the one by the Achievements title (a toast instead when it is out of sight).
func _coin_target() -> Control:
	return _coins if _coins and _coins.is_visible_in_tree() else null


# =====================================================================================================================
# Data
# =====================================================================================================================

func _refresh() -> void:
	if not is_instance_valid(_ava):
		return
	var p: Dictionary = Save.profile
	_ava.refresh()
	var plate := Collection.equipped("plate", p)
	_plate.set_look(L10n.seat_name(str(p.get("name", "You"))), plate, Collection.equipped("badge", p))
	_style_plate(plate == Collection.DEFAULT_PLATE or Collection.PlateView.art(plate) == null)
	var info: Dictionary = Save.level_info(int(p.get("xp", 0)))
	_level.set_level(int(info.level))
	_xp.set_value(float(info.into), float(info.need))
	if _flying == 0:
		_coins.set_amount(int(p.get("coins", 0)))
	var st: Dictionary = p.get("stats", {}) if p.get("stats") is Dictionary else {}
	var played := int(st.get("played", 0))
	var sl_played := int(st.get("slPlayed", 0))
	for k: String in _stat_vals:
		var c: Control = _stat_vals[k]
		if c is CoinAmount:
			(c as CoinAmount).set_amount(int(st.get(k, 0)))
			continue
		var lab := c as Label
		var text := str(int(st.get(k, 0)))
		match k:
			"winRate":
				text = Fmt.pct(float(st.get("wins", 0)) / played) if played > 0 else Fmt.EMPTY
			"wins", "bestStreak":
				if played == 0: text = Fmt.EMPTY
			"slWins":
				if sl_played == 0: text = Fmt.EMPTY
		lab.text = text
		lab.add_theme_color_override("font_color", SAND if text == Fmt.EMPTY else Color.WHITE)
	_stats_note.get_parent().visible = played == 0 and sl_played == 0 and int(st.get("ppGames", 0)) == 0
	_refresh_table()
	var earned := 0
	var waiting := 0
	for a: Dictionary in Collection.ACH:
		if Collection.ach_done(a.id, p):
			earned += 1
			if not bool(Collection.ach_progress(a.id, p).get("claimed", false)):
				waiting += int(a.reward)
	_ach_coins.set_amount(waiting)
	_ach_claim.visible = waiting > 0
	_ach_earned.text = tr("%d of %d earned") % [earned, Collection.ACH.size()]
	for u in _ach_updaters:
		u.call()
	var n := Collection.claimable_count(p)
	_ach_count.visible = n > 0
	(_ach_count.get_child(0) as Label).text = str(n)
	if _name_edit and not _name_edit.has_focus():
		_validate(false)
	_refresh_account()

## Trimmed, inner runs of spaces collapsed to one.
static func clean_name(s: String) -> String:
	var parts := s.strip_edges().split(" ", false)
	return " ".join(parts)

## True when the typed name is valid. Save shows only when the name changed, disabled while it's invalid.
func _validate(show_err: bool) -> bool:
	var n := clean_name(_name_edit.text)
	var reserved := n.to_lower() == "you"           # (the game calls every player's own row "You")
	var ok := n.length() >= 1 and n.length() <= MAX_NAME and not reserved
	var changed := n != str(Save.profile.get("name", ""))
	_save_btn.visible = changed
	_save_btn.disabled = not ok or not changed
	_err.text = "" if not show_err or ok else tr("Pick another name: “You” is how the game shows you to yourself.") if reserved \
		else tr("Enter a name of 1 to %d characters.") % MAX_NAME
	_err.visible = _err.text != ""
	return ok

func _save_name() -> void:
	if not _validate(true) or _save_btn.disabled:
		return
	var n := clean_name(_name_edit.text)
	if Account.wallet_active():
		_save_btn.disabled = true
		var r: Dictionary = await Account.instance().push_identity({name = NetClient.wire_name(n)})
		if not is_instance_valid(self) or _closing:
			return
		if not r.get("ok", false):
			Haptics.error()
			Toast.show(self, Account.error_text(str(r.get("error", "")), "name"), card, 2.2, "bad")
			_validate(false)
			return
		n = str(Save.profile.get("name", n))
	else:
		Save.profile.name = n
		Save.save()
	_name_edit.text = n
	_name_edit.release_focus()
	Haptics.success()
	Save.changed.emit()      # also refreshes this sheet
	_validate(false)
	if _editing:
		_set_editing(false)
	Toast.show(self, tr("Name saved"), card, 1.4, "good")
	profile_changed.emit()
