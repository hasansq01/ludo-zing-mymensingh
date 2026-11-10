class_name ShopSheet
extends Sheet
## The one Shop (PLAN decision 4: Shop + Inventory + Collection merged). Everything the player can buy, earn or put
## in use lives here, in four tabs (TabStrip "gtabs"), each with its filter under it (SUBS, `tab` is the category):
## Rooms (Ludo | Snakes & Ladders) / Pieces (Pawns | Dice) / Emotes (Stickers | Text) / Look (Avatars | Frames | Plates |
## Badges). The nav's Inventory is the same sheet showing only what the player owns.
##
## The PM look (the ribbon sheet family): the "Shop" ribbon and the close X; under it the coins and gems (tap = Get coins,
## Store), then the tabs and the filter. Only the grid scrolls; the card keeps one size on every tab.
## A compact card: the art, its name and one state line, nothing reserved for what isn't there. Wide art (rooms, scenes,
## emote packs, plates) goes in two columns, square art in three.
##   for sale     the price (coins or gems). Tap the card: its preview, where you buy (PreviewSheet, PawnSheet,
##                EmotePackSheet, ItemSheet), so a stray tap while scrolling never starts a purchase
##   owned        Use (teal); a tap on the card does the same, a tap on previewable art opens the preview
##   in use       a "In use" pill, and the card wears the gold rim
##   locked       lock + what unlocks it ("Reach level 5"), the art faded; a tap says it in full
## Order: what's in use first, then for sale from the cheapest, then owned, then locked (the catalog's order within each).
## Economy v1: every paid item can also be bought with gems (ceil(price / 100), Catalog.gem_price), offered by the
## preview; pawn skins sold for gems only show gems. Too few gems: "Not enough gems", the shortfall, and "Open Store".
## Gems only exist on the server: offline it says "Connect to the internet to buy".
## The preview is the offer (OfferSheet, the Buying mock-up): its price button buys at once (one tap; "Not enough gems"
## still asks whether to open the Store) through Catalog / SLScenes / Collection or the server wallet (coins checked,
## never charged twice, rolled back when the save fails), puts the item in use and shows the RevealSheet.
## Coins come from the Get coins sheet: the Rewards sheet (RewardsSheet.new("Get coins", true)), the same rows as
## Home's gift: Daily spin, Daily reward and Free coins with their live state, each opening its own sheet from Main.
##
##   var s := ShopSheet.new("dice")                 # all items, Dice tab
##   var s := ShopSheet.new("avatars", 400, true)   # owned only (equip)
##   s.room_changed.connect(app.apply_room); s.open(layer)

signal room_changed(id: String)
signal dice_changed(id: String)
signal scene_changed(id: String)         ## a Snakes & Ladders scene was bought / put in use (SLScenes)
signal changed                           ## anything was bought or put in use (rooms, dice, scenes, avatars, frames ...)
signal emotes_changed                    ## an emote pack was bought / put in use
signal store_requested                   ## "Open Store" after "not enough gems": main opens the Store sheet
signal shop_requested(tab: String)       ## Inventory: "Open shop" (main closes the inventory and opens the Shop there)

## l10n-keys: text
const TABS := [
	{key = "boards", text = "Rooms", icon = "cat_rooms", cat = "rooms"},
	{key = "pieces", text = "Pieces", icon = "cat_pawns", cat = "pawns"},
	{key = "emotes", text = "Emotes"},
	{key = "look", text = "Look", icon = "cat_avatars", cat = "avatars"},
]
## What each tab holds: [category, its label in the filter under the tabs].
const SUBS := {
	boards = [["rooms", "Ludo"], ["scenes", "Snakes & Ladders"]],
	pieces = [["pawns", "Pawns"], ["dice", "Dice"]],
	emotes = [["emotes", "Stickers"], ["text", "Text"]],
	look = [["avatars", "Avatars"], ["frames", "Frames"], ["plates", "Plates"], ["badges", "Badges"]],
}
## The filter's labels for the extractor: shown through L10n.t (the pairs above keep the ids).
const _SUB_TEXT := ["Ludo", "Snakes & Ladders", "Pawns", "Dice", "Stickers", "Text", "Avatars", "Frames", "Plates", "Badges", "Pieces"]  # l10n
## Old tab names (Collection, the Coins tab, Inventory) -> the categories.
const TAB_ALIAS := {chars = "avatars", characters = "avatars", nameplates = "plates", coins = "rooms", look = "avatars",
	boards = "rooms", pieces = "pawns"}
const MAX_H := 680.0                     ## one card height for every tab (web .shop-card min(100%, 680px))
const ART_WIDE := 0.62                   ## card art height / width: rooms, scenes, emote packs
const ART_PLATE := 0.4                   ## a nameplate is a strip
const ART_SQUARE := 0.86                 ## dice, pawns, avatars, frames, badges
const WIDE := ["room", "scene", "emotes", "text", "plate"]   ## two columns (the rest three)
const PREVIEWS := ["room", "scene", "pawn", "emotes", "text"]   ## a live preview of their own (dice, characters: ItemSheet)
const STATE_H := 36                      ## the card's state line
const SIDE_PAD := 14                     ## card side padding
const NAME_FS := 14

static var _wells := {}                  # category -> GradientTexture2D (the art well behind dice / avatars ...)
## Rarity colours: [glow, face, deep (edge), rim, label ground]. Free and earned items wear "common".
const RAR := {
	common = [Color("#f6e3c8"), Color("#c08a5a"), Color("#6b3e20"), Color("#f1d6b4"), Color("#3b1f0e")],
	rare = [Color("#d8eeff"), Color("#4f97e8"), Color("#1d4f9a"), Color("#9fd0ff"), Color("#0f2f66")],
	epic = [Color("#e8d4ff"), Color("#9b5ce6"), Color("#4f2196"), Color("#d9b8ff"), Color("#2a0d55")],
	legendary = [Color("#fff3b0"), Color("#ffbf3c"), Color("#c9690a"), Color("#ffe08a"), Color("#3b1a0c")],
}
const RARITY_NAMES := {common = "Common", rare = "Rare", epic = "Epic", legendary = "Legendary"}  # l10n
const OUTLINE := Color("#3b1a0c")
const CARD_H := 196.0
const GAP := 12

var tab := "rooms"
var owned_only := false
var inventory := false                   ## the nav's Inventory: owned items only, no filter / balance row
var _tabs: Tiles
var _sub_box: MarginContainer            # holds the filter of the tab showing (SUBS)
var _sub: HBoxContainer
var _sub_of := ""                        # the tab that filter belongs to
var _last_sub := {}                      # tab -> the category shown last on it
var _balance: CoinAmount
var _gems_amount: CoinAmount
var _earn_btn: Button
var _gem_btn: Button
var _banner_box: MarginContainer       # today's featured item (rebuilt with the tab)
var _banner_clock: Label
var _updaters: Array[Callable] = []
var _cards: Array[PanelContainer] = []
var _open_earn := false
var _busy := false                       # a purchase confirm is showing


func _init(start_tab := "rooms", width := 400.0, owned_only_ := false, inventory_ := false) -> void:
	super("", width, true, LOOK_PM)
	inventory = inventory_
	owned_only = owned_only_ or inventory_
	_open_earn = start_tab == "coins"
	tab = _norm_tab(start_tab)
	make_page(_page_bg())
	body.add_theme_constant_override("separation", GAP)
	# SHOP and the wallet (coins: Get coins; gems: the Store)
	var row := UIKit.hbox(8)
	var title := outlined(L10n.t("Inventory").to_upper() if inventory else L10n.t("Shop").to_upper(), 34, Color("#ffd45e"), 6)
	title.name = "PageTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true                   # the wallet always shows in full; a long title (Bangla) shrinks first
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if inventory:
		title.add_theme_font_size_override("font_size", 26)
	row.add_child(title)
	_earn_btn = _balance_button()
	row.add_child(_earn_btn)
	_gem_btn = _gems_button()
	row.add_child(_gem_btn)
	body.add_child(row)
	_banner_box = UIKit.margin(Control.new(), 0, 0, 0, 0)
	_banner_box.name = "BannerBox"
	body.add_child(_banner_box)
	var tabs := TABS.duplicate(true)
	for t: Dictionary in tabs:
		t.text = L10n.t(t.text)
	_tabs = Tiles.new(tabs, strip_key(tab))
	_tabs.picked.connect(show_tab)
	body.add_child(_tabs)
	_sub_box = UIKit.margin(Control.new(), 0, 0, 0, 0)
	_sub_box.name = "SubFilter"
	body.add_child(_sub_box)
	add_scroll_body(GAP)
	narrow_changed.connect(_on_narrow)


## The page's ground: a warm radial glow at the top fading to deep café brown.
static func _page_bg() -> StyleBox:
	var g := GradientTexture2D.new()
	g.width = 64; g.height = 128
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.0); g.fill_to = Vector2(0.5, 0.75)
	g.gradient = Gradient.new()
	g.gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.gradient.colors = PackedColorArray([Color("#8a4b26"), Color("#5a2c16"), Color("#2b140a")])
	var st := StyleBoxTexture.new()
	st.texture = g
	st.content_margin_left = 14; st.content_margin_right = 14
	st.content_margin_top = 14; st.content_margin_bottom = 8
	return st

## A label in Lilita One with a dark outline (the game look's display type).
static func outlined(text: String, fs: int, col := Color.WHITE, outline := 4, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UIKit.label(text, fs, col, UIKit.font_display(), align)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _ready() -> void:
	Save.changed.connect(refresh)
	show_tab(tab)
	if _open_earn:
		open_earn.call_deferred()


static func _norm_tab(key: String) -> String:
	key = str(TAB_ALIAS.get(key, key))
	return key if strip_key(key) != "" else "rooms"

## The tab a category sits under ("frames" -> "look"), "" when none.
static func strip_key(category: String) -> String:
	for k: String in SUBS:
		for l: Array in SUBS[k]:
			if l[0] == category:
				return k
	return ""


## Switch to a tab (its category shown last) or a category, and list its cards from the top.
func show_tab(key: String) -> void:
	var picked_tab := SUBS.has(key) and key != "emotes"
	if key == "emotes" and _sub_of != "emotes" and _last_sub.has("emotes"):
		picked_tab = true
	tab = str(_last_sub.get(key, SUBS[key][0][0])) if picked_tab else _norm_tab(key)
	var strip := strip_key(tab)
	_last_sub[strip] = tab
	_tabs.select(strip)
	_show_filter(strip)
	_build()

## The filter under the tiles: the category's buttons (the picked one a cream face, the others outlined).
func _show_filter(strip: String) -> void:
	if strip != _sub_of:
		_sub_of = strip
		for c in _sub_box.get_children():
			_sub_box.remove_child(c)
			c.queue_free()
		_sub = UIKit.hbox(8)
		_sub.name = "Filter"
		var group := ButtonGroup.new()
		for l: Array in SUBS[strip]:
			var b := Button.new()
			b.text = L10n.t(l[1])
			b.toggle_mode = true
			b.button_group = group
			b.focus_mode = Control.FOCUS_NONE
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(0, 36)
			b.set_meta("value", l[0])
			var off := UIKit.box(Color(0, 0, 0, 0), 12, 2, Color("#6b3a20"))
			var on := UIKit.box(Color("#fff1dc"), 12, 0)
			on.border_width_bottom = 3
			on.border_color = Color("#d8b48a")
			for k in ["normal", "hover", "disabled", "focus"]:
				b.add_theme_stylebox_override(k, off)
			for k in ["pressed", "hover_pressed"]:
				b.add_theme_stylebox_override(k, on)
			b.add_theme_font_override("font", UIKit.font_display())
			b.add_theme_font_size_override("font_size", 15)
			for k in ["font_color", "font_hover_color"]:
				b.add_theme_color_override(k, Color("#e7c7a6"))
			for k in ["font_pressed_color", "font_hover_pressed_color"]:
				b.add_theme_color_override(k, Color("#4a2212"))
			var v: String = l[0]
			b.toggled.connect(func(x: bool): if x: show_tab(v))
			UIKit.wire_press(b)
			_sub.add_child(b)
		_sub_box.add_child(_sub)
	for b in _sub.get_children():
		if b is Button:
			(b as Button).set_pressed_no_signal(b.get_meta("value", "") == tab)

## Show everything, or only what the player owns.
func set_owned_only(on: bool) -> void:
	owned_only = on
	_build()

func _build() -> void:
	for c in scroll_body.get_children():
		scroll_body.remove_child(c)
		c.queue_free()
	_updaters.clear()
	_cards.clear()
	var sections: Array = _sections(tab)
	var shown := 0
	var total := 0
	_show_banner(sections)
	var gap: int = GAP
	for sec: Array in sections:
		total += (sec[1] as Array).size()
		var items: Array = _ordered(sec[1].filter(func(it: Dictionary) -> bool: return not owned_only or _owned(it.kind, it.id)))
		if items.is_empty():
			continue
		if sec[0] != "" and sections.size() > 1:
			var cap := outlined(sec[0], 15, Color("#ffd45e"), 4)
			cap.name = "Section"
			scroll_body.add_child(UIKit.margin(cap, 4, UIKit.SPACE.sm if shown > 0 else 0, 0, 0))
		var g := UIKit.grid(2, gap)
		g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for it: Dictionary in items:
			g.add_child(_card(it))
		scroll_body.add_child(g)
		shown += items.size()
	if shown == 0:
		scroll_body.add_child(_empty())
	elif owned_only and total > shown:
		scroll_body.add_child(_more_row(total - shown))  # the Owned filter: the rest is one tap away
	scroll_box.scroll_vertical = 0
	refresh()

## In use first, then what's for sale from the cheapest (a gem price counted as its coins), then owned, then locked;
## the catalog's order within each. Read when a tab opens: a purchase doesn't move cards under the player's finger.
static func _ordered(items: Array) -> Array:
	var keyed: Array = []
	for i in items.size():
		var it: Dictionary = items[i]
		var own := _owned(it.kind, it.id)
		var rank := 0 if own and _in_use(it.kind, it.id) else (2 if own else (3 if _price(it.kind, it.id) <= 0 and not _gems_only(it.kind, it.id) else 1))
		var cost := 0
		if rank == 1:
			cost = _gems(it.kind, it.id) * 100 if _gems_only(it.kind, it.id) else _price(it.kind, it.id)
		keyed.append([rank, cost, i, it])
	keyed.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1] != b[1]:
			return a[1] < b[1]
		return a[2] < b[2])
	return keyed.map(func(k: Array) -> Dictionary: return k[3])

## Re-read the profile: the balance and every card's state.
func refresh() -> void:
	if not is_instance_valid(_balance):
		return
	var c := Catalog.coins()
	if c != _balance.amount:
		_balance.set_amount(c, is_inside_tree())
	var g := int(Save.profile.get("gems", 0))
	if g != _gems_amount.amount:
		_gems_amount.set_amount(g, is_inside_tree())
	for u in _updaters:
		u.call()

func _on_narrow(_n: bool) -> void:
	if is_inside_tree():
		_build()

## The coins as a white chip button with a teal "+" (the home top bar's coin chip); tap = Get coins.
func _balance_button() -> Button:
	_balance = CoinAmount.new(Catalog.coins(), "md", "plain")
	_balance.name = "Balance"
	var b := _chip(_balance)
	b.name = "GetCoins"
	b.tooltip_text = tr("Get coins")
	b.pressed.connect(open_earn)
	return b

## The gems, the same chip; tap = the Store.
func _gems_button() -> Button:
	_gems_amount = CoinAmount.gems(int(Save.profile.get("gems", 0)), "md", "plain")
	_gems_amount.name = "GemBalance"
	var b := _chip(_gems_amount)
	b.name = "GetGems"
	b.tooltip_text = tr("Store")
	b.pressed.connect(func(): store_requested.emit())
	return b

## A wallet pill (mock: dark, a gold rim, the amount and a teal "+"); the whole pill is the button.
func _chip(amount: CoinAmount) -> Button:
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount.set_color(Color.WHITE)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var face := UIKit.box(Color("#2a130a"), 17, 2, Color("#c98a3a"))
	face.content_margin_left = 6; face.content_margin_right = 4
	face.content_margin_top = 2; face.content_margin_bottom = 2
	var down := face.duplicate() as StyleBoxFlat
	down.bg_color = Color("#1a0b05")
	for k in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(k, face)
	for k in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(k, down)
	b.custom_minimum_size = Vector2(0, 36)
	var h := UIKit.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(amount)
	var plus := PanelContainer.new()
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := UIKit.box(Palette.TEAL, 12, 0)
	ps.border_width_bottom = 3
	ps.border_color = Color("#1d7f6e")
	UIKit.pad(ps, 0)
	plus.add_theme_stylebox_override("panel", ps)
	plus.custom_minimum_size = Vector2(24, 24)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pl := UIKit.label("+", 18, Color.WHITE, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.add_child(pl)
	h.add_child(plus)
	var m := UIKit.margin(h, 6, 0, 4, 0)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.custom_minimum_size.x = h.get_combined_minimum_size().x + 14
	amount.minimum_size_changed.connect(func(): b.custom_minimum_size.x = h.get_combined_minimum_size().x + 14)
	UIKit.wire_press(b)
	return b


# =====================================================================================================================
# What each tab lists
# =====================================================================================================================

## [[section title, [item, ...]], ...]; item = {kind, id, name}.
static func _sections(key: String) -> Array:
	match key:
		"rooms":
			return [["", Catalog.rooms().map(func(r: Dictionary) -> Dictionary: return {kind = "room", id = r.id, name = r.name})]]
		"scenes":
			return [["", SLScenes.LIST.map(func(s: Dictionary) -> Dictionary: return {kind = "scene", id = s.id, name = s.name})]]
		"dice":
			return [["", Catalog.DICE.map(func(d: Dictionary) -> Dictionary: return {kind = "dice", id = d.id, name = d.name})]]
		"pawns":
			return [["", Catalog.PAWNS.map(func(d: Dictionary) -> Dictionary: return {kind = "pawn", id = d.id, name = d.name})]]
		"emotes":
			return [["", Emotes.packs().map(func(e: Dictionary) -> Dictionary: return {kind = "emotes", id = e.id, name = e.name})]]
		"text":
			return [["", Emotes.text_packs().map(func(e: Dictionary) -> Dictionary: return {kind = "text", id = e.id, name = e.name})]]
		"avatars":
			# the illustrated characters first (the one in use, then the ones owned, then by price), then the
			# classic avatars (pawns, Latte, the earned ones) with the one in use first
			var on := Collection.equipped("avatar")
			var chars := Collection.CHARS.duplicate()
			var rank := func(c: Dictionary) -> int:
				return 0 if c.id == on else (1 if Collection.is_unlocked("char", c.id) else 2)
			chars.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ra: int = rank.call(a)
				var rb: int = rank.call(b)
				if ra != rb:
					return ra < rb
				return int(a.price) < int(b.price) or (int(a.price) == int(b.price) and str(a.name) < str(b.name)))
			var classic := []
			for a: Dictionary in Collection.AVATARS:
				if a.id == on:
					classic.push_front(a)
				else:
					classic.append(a)
			return [
				[L10n.t("Characters"), chars.map(func(c: Dictionary) -> Dictionary: return {kind = "char", id = c.id, name = c.name})],
				[L10n.t("More characters"), Collection.WORLD.map(func(c: Dictionary) -> Dictionary: return {kind = "char", id = c.id, name = c.name})],
				[L10n.t("Classic"), classic.map(func(a: Dictionary) -> Dictionary: return {kind = "avatar", id = a.id, name = a.name})],
			]
		"frames":
			return [["", Collection.FRAMES.map(func(f: Dictionary) -> Dictionary: return {kind = "frame", id = f.id, name = f.name})]]
		"plates":
			return [["", Collection.PLATES.map(func(p: Dictionary) -> Dictionary: return {kind = "plate", id = p.id, name = p.name})]]
		"badges":
			return [["", Collection.BADGES.map(func(b: String) -> Dictionary: return {kind = "badge", id = b, name = Collection.item("badge", b).get("name", b)})]]
	return []

static func _owned(kind: String, id: String) -> bool:
	match kind:
		"room": return Catalog.owns_room(id)
		"scene": return SLScenes.owns_scene(id)
		"dice": return Catalog.owns_dice(id)
		"pawn": return Catalog.owns_pawn(id)
		"emotes": return Catalog.owns_emotes(id)
		"text": return Catalog.owns_text(id)
	return Collection.is_unlocked(kind, id)

static func _in_use(kind: String, id: String) -> bool:
	match kind:
		"room": return Catalog.room_in_use() == id
		"scene": return SLScenes.scene_in_use() == id
		"dice": return Catalog.dice_in_use() == id
		"pawn": return Catalog.pawn_in_use() == id
		"emotes": return Catalog.emotes_in_use() == id
		"text": return Catalog.text_in_use() == id
		"char": return Collection.is_equipped("avatar", id)
	return Collection.is_equipped(kind, id)

static func _price(kind: String, id: String) -> int:
	match kind:
		"room": return int(Catalog.room(id).get("price", 0))
		"scene": return int(SLScenes.info(id).get("price", 0))
		"dice": return int(Catalog.dice(id).get("price", 0))
		"pawn": return int(Catalog.pawn(id).get("price", 0))
		"emotes": return int(Catalog.emote_pack(id).get("price", 0))
		"text": return int(Catalog.text_pack(id).get("price", 0))
		"char": return int(Collection.character(id).get("price", 0))
		"frame", "plate": return Collection.look_price(kind, id)
	return 0

## The gem price: ceil(coins / 100) (Catalog.gem_price), or a gem-only pawn skin's or frame's own; 0 when not sold.
static func _gems(kind: String, id: String) -> int:
	match kind:
		"pawn": return Catalog.pawn_gems(id)
		"frame", "plate": return Collection.look_gems(kind, id)
	return Catalog.gem_price(_price(kind, id))

## Sold for gems only (a premium pawn skin or frame): no coin price, the card's Buy pays gems.
static func _gems_only(kind: String, id: String) -> bool:
	match kind:
		"pawn": return Catalog.pawn_gems_only(id)
		"frame", "plate": return Collection.look_gems_only(kind, id)
	return false

## The name in sentences: "Royal Gold dice", "Marble pawns", "Pastel Dream Room".
static func _title(kind: String, name_: String) -> String:
	if kind == "pawn":
		return L10n.t("%s pawns") % L10n.t(name_)
	return L10n.t("%s dice") % L10n.t(name_) if kind == "dice" else L10n.t(name_)

## What unlocks a level / achievement item, as the thing to do: "Reach level 5", "Win 3 games in a row".
static func _unlock_note(kind: String, id: String) -> String:
	var ach_id := id if kind == "badge" else ""
	if kind != "badge":
		var u: Dictionary = Collection.item(kind, id).get("unlock", {})
		if u.has("level"):
			return L10n.t("Reach level %d") % int(u.level)
		ach_id = str(u.get("ach", ""))
	var a := Collection.ach(ach_id)
	return L10n.t(str(a.desc)).trim_suffix(".").trim_suffix("।") if not a.is_empty() else L10n.t(Collection.unlock_text(kind, id))


# =====================================================================================================================
# Cards
# =====================================================================================================================

func _card(it: Dictionary) -> Control:
	var kind: String = it.kind
	var id: String = it.id
	var rar := rarity(kind, id)
	var c: Array = RAR[rar if rar != "" else "common"]
	var p := GamePanel.radial(c[0], c[1], c[2])
	p.name = "Card"
	p.radius = 18.0
	p.border = 3.0
	p.border_color = c[3]
	p.lip = 5.0
	p.lip_color = c[2].darkened(0.45)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(0, CARD_H)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.set_meta("item", id)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(root)
	# the art over the top two thirds
	var art := Control.new()
	art.name = "Art"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.offset_left = 12; art.offset_right = -12; art.offset_top = 24; art.offset_bottom = -(66 + 2)
	root.add_child(art)
	var view := _art(kind, id, true)
	art.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# the bottom strip: a dark fade that carries the name and the state
	var strip := TextureRect.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := GradientTexture2D.new()
	g.width = 4; g.height = 32
	g.fill_from = Vector2(0.5, 0.0); g.fill_to = Vector2(0.5, 1.0)
	g.gradient = Gradient.new()
	g.gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.gradient.colors = PackedColorArray([Color(c[4], 0.0), Color(c[4], 0.85), Color(c[4], 0.9)])
	strip.texture = g
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -72; strip.offset_bottom = 0; strip.offset_left = 3; strip.offset_right = -3
	root.add_child(strip)
	var col := UIKit.vbox(4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_END
	col.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_top = -64; col.offset_bottom = -8; col.offset_left = 6; col.offset_right = -6
	root.add_child(col)
	var nl := outlined(L10n.t(it.name), 16, Color.WHITE, 4, HORIZONTAL_ALIGNMENT_CENTER)
	nl.name = "ItemName"
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(nl)
	var slot := CenterContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size.y = 30
	col.add_child(slot)
	var gems_only := _gems_only(kind, id)
	var price_row := price_button(_gems(kind, id) if gems_only else _price(kind, id), gems_only)
	price_row.name = "Price"
	slot.add_child(price_row)
	var use := UIKit.btn(tr("Use"), "teal", "xs")
	use.name = "Use"
	use.pressed.connect(func(): _on_use(kind, id))
	slot.add_child(use)
	var on_pill := equipped_pill()
	slot.add_child(on_pill)
	var lock_row := UIKit.hbox(4)
	lock_row.name = "Locked"
	lock_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var li := UIKit.icon("ic_lock", 14)
	li.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lock_row.add_child(li)
	var ll := UIKit.label(_unlock_note(kind, id), 11, Color("#fff1dc"), UIKit.font_body(900))
	ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ll.max_lines_visible = 2
	ll.custom_minimum_size.x = 110
	ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock_row.add_child(ll)
	slot.add_child(lock_row)
	# the rarity chip and the preview eye
	if rar != "":
		var chip := rarity_chip(rar)
		root.add_child(chip)
		chip.position = Vector2(8, 8)
	if PREVIEWS.has(kind):
		var vb := _view_button(kind, id)
		root.add_child(vb)
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vb.offset_bottom = -72
	UIKit.on_tap(p, func() -> void: _on_card(kind, id, ll.text if lock_row.visible else "", p))
	_cards.append(p)
	_updaters.append(func():
		var owned := _owned(kind, id)
		var on := owned and _in_use(kind, id)
		var for_sale := not owned and (_price(kind, id) > 0 or gems_only)
		p.border_color = Color("#ffd45e") if on else c[3]
		p.border = 4.0 if on else 3.0
		price_row.visible = for_sale
		use.visible = owned and not on
		on_pill.visible = on
		lock_row.visible = not owned and not for_sale
		view.modulate.a = 0.55 if lock_row.visible else 1.0)
	return p

## An item's rarity from its price (a gem counted as 100 coins): "" for free and earned items, else "common" (under
## 3K), "rare" (under 6K), "epic" (under 12K) or "legendary".
static func rarity(kind: String, id: String) -> String:
	var v := _gems(kind, id) * 100 if _gems_only(kind, id) else _price(kind, id)
	if v <= 0:
		return ""
	if v < 3000:
		return "common"
	if v < 6000:
		return "rare"
	return "epic" if v < 12000 else "legendary"

## The rarity's name, small, on its dark ground.
static func rarity_chip(rar: String) -> PanelContainer:
	var c: Array = RAR[rar]
	var chip := PanelContainer.new()
	chip.name = "Rarity"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UIKit.box(c[4], 8, 0)
	st.content_margin_left = 8; st.content_margin_right = 8; st.content_margin_top = 1; st.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", st)
	var l := UIKit.label(L10n.t(str(RARITY_NAMES[rar])).to_upper(), 11, c[3], UIKit.font_display())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(l)
	return chip

## A chunky price button face: gold with dark figures (coins) or teal with white figures (gems). xl: the offer's
## big price (66 px, a 7 px inset lip over a 4 px outer one, the amount in full, centred).
static func price_button(amount: int, gems := false, big := false, xl := false) -> Control:
	if xl:
		var f := OfferSheet._face(Color("#6ff0d6") if gems else Color("#ffe27a"), Color("#2fb39c") if gems else Color("#f7a928"),
			Color("#1d7f6e") if gems else Color("#b86a0a"), Color("#0f4f44") if gems else Color("#6b3a06"))
		var amt := CoinAmount.new(amount, "xl", "plain", "", true, "gem" if gems else "coin")
		amt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		amt.set_color(Color.WHITE if gems else Color("#4a2212"))
		if gems:
			amt.text_label.add_theme_constant_override("outline_size", 5)
			amt.text_label.add_theme_color_override("font_outline_color", Color("#1d4f45"))
		var cc := CenterContainer.new()
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(amt)
		f.add_child(cc)
		f.custom_minimum_size.y = 70.0
		return f
	var p := GamePanel.vertical(Color("#5fe0c8") if gems else Color("#ffd45e"), Color("#2fb39c") if gems else Color("#f7a928"))
	p.radius = 14.0 if big else 10.0
	p.lip = 5.0 if big else 4.0
	p.lip_color = Color("#1d7f6e") if gems else Color("#b86a0a")
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := CoinAmount.gems(amount, "md" if big else "sm", "plain") if gems else CoinAmount.new(amount, "md" if big else "sm", "plain")
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.set_color(Color.WHITE if gems else Color("#4a2212"))
	var m := UIKit.margin(a, 16 if big else 12, 3 if big else 2, 16 if big else 12, 1)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(m)
	p.custom_minimum_size.y = 40.0 if big else 30.0
	return p

## "✓ EQUIPPED" on a cream pill (the item in use).
static func equipped_pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "InUse"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UIKit.box(Color("#fff1dc"), 10, 0)
	st.border_width_bottom = 3
	st.border_color = Color("#d8b48a")
	st.content_margin_left = 10; st.content_margin_right = 10; st.content_margin_top = 3; st.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", st)
	var h := UIKit.hbox(4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UIKit.glyph("ic_check", 14, Color("#1d7f6e"))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := UIKit.label(L10n.t("In use").to_upper(), 13, Color("#1d7f6e"), UIKit.font_display())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	p.add_child(h)
	return p


# ---------------------------------------------------------------------------------------------------------------------
# Today's featured item

## One of this tab's three priciest things for sale that the player doesn't own, turning with the (UTC) date.
static func featured(sections: Array) -> Dictionary:
	var pool: Array = []
	for sec: Array in sections:
		for it: Dictionary in sec[1]:
			if _owned(it.kind, it.id) or not (_price(it.kind, it.id) > 0 or _gems_only(it.kind, it.id)):
				continue
			pool.append([_gems(it.kind, it.id) * 100 if _gems_only(it.kind, it.id) else _price(it.kind, it.id), it])
	if pool.is_empty():
		return {}
	pool.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var top := pool.slice(0, 3)
	return top[int(Time.get_unix_time_from_system() / 86400.0) % top.size()][1]

func _show_banner(sections: Array) -> void:
	for ch in _banner_box.get_children():
		_banner_box.remove_child(ch)
		ch.queue_free()
	_banner_clock = null
	var it := {} if owned_only else featured(sections)
	_banner_box.visible = not it.is_empty()
	if it.is_empty():
		return
	_banner_box.add_child(_banner(it))

## The featured banner (mock: a glowing rarity gradient with rays, the art, FEATURED TODAY, the name, when it changes
## and the price). Tap: its preview, like its card.
func _banner(it: Dictionary) -> Control:
	var kind: String = it.kind
	var id: String = it.id
	var rar := rarity(kind, id)
	var c: Array = RAR[rar if rar != "" else "legendary"]
	var p := GamePanel.radial(c[0], c[1], c[2])
	p.name = "Featured"
	p.radius = 20.0
	p.border = 3.0
	p.border_color = c[3]
	p.lip = 6.0
	p.lip_color = c[2].darkened(0.4)
	p.center = Vector2(0.28, 0.55)
	p.reach = Vector2(0.75, 1.1)
	p.rays = 0.24
	p.ray_center = Vector2(0.25, 0.26)
	p.custom_minimum_size = Vector2(0, 156)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := UIKit.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(UIKit.margin(h, 8, 6, 12, 6))
	var art_box := Control.new()
	art_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_box.custom_minimum_size = Vector2(140, 140)
	var art := _art(kind, id, true)
	art_box.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_child(art_box)
	var col := UIKit.vbox(6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(col)
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var cs := UIKit.box(c[4], 10, 0)
	cs.content_margin_left = 10; cs.content_margin_right = 10; cs.content_margin_top = 2; cs.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", cs)
	var tag := L10n.t("Featured today").to_upper()
	if rar != "":
		tag = L10n.t(str(RARITY_NAMES[rar])).to_upper() + " · " + tag
	chip.add_child(UIKit.label(tag, 11, Color("#ffd45e"), UIKit.font_display()))
	col.add_child(chip)
	var nm := outlined(_title(kind, str(it.name)), 26, Color.WHITE, 6)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.max_lines_visible = 2
	col.add_child(nm)
	_banner_clock = UIKit.label("", 13, c[4], UIKit.font_body(900))
	_banner_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_banner_clock)
	_tick_banner()
	var gems_only := _gems_only(kind, id)
	var price := price_button(_gems(kind, id) if gems_only else _price(kind, id), gems_only, true)
	price.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(price)
	UIKit.on_tap(p, func() -> void: _on_card(kind, id, "", p))
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_tick_banner)
	p.add_child(t)
	return p

## "Changes in 05:42:10" (the featured item turns at 00:00 UTC).
func _tick_banner() -> void:
	if not is_instance_valid(_banner_clock):
		return
	var now := int(Time.get_unix_time_from_system())
	var left := 86400 - now % 86400
	_banner_clock.text = L10n.t("Changes in %s") % ("%02d:%02d:%02d" % [left / 3600, (left % 3600) / 60, left % 60])


## A tap on a card: says what unlocks it, opens its preview to buy, or puts it in use.
func _on_card(kind: String, id: String, locked_note: String, from: Control) -> void:
	if _busy or _closing:
		return
	if locked_note != "":
		UIKit.deny(self, locked_note + ("।" if L10n.is_bn() else "."), from, 2.0)
	elif not _owned(kind, id):
		if PREVIEWS.has(kind):
			_on_view(kind, id)
		else:
			_open_item(kind, id)
	elif not _in_use(kind, id):
		_on_use(kind, id)

## The buy screen of a die or a character.
func _open_item(kind: String, id: String) -> void:
	if get_parent() == null:
		return
	var s := ItemSheet.new(kind, id)
	s.changed.connect(func():
		_announce(kind, id)
		refresh())
	s.store_requested.connect(func(): store_requested.emit())
	s.closed.connect(func():
		if is_instance_valid(self) and not _closing:
			refresh())
	s.open(get_parent())

## The "or [gem] 30" line of a card: one flat 34 px button (the whole line is the tap).
static func gem_option(gems: int) -> Button:
	var b := Button.new()
	b.name = "GemBuy"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 34
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("gems", gems)
	for k in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	var h := UIKit.hbox(UIKit.SPACE.xs + 2)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(h)
	var or_l := UIKit.label(L10n.t("or"), UIKit.FS.label, Palette.SUB, UIKit.font_body(800))
	or_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(or_l)
	var amt := CoinAmount.gems(gems, "xs", "plain")
	amt.name = "Amount"
	amt.set_color(Palette.TEAL_INK)
	h.add_child(amt)
	UIKit.wire_press(b)
	return b

## The art of an item, filling its ArtBox.
func _art(kind: String, id: String, bare := false) -> Control:
	match kind:
		"emotes":
			return _emote_art(Emotes.pack(id).get("emotes", []), bool(Emotes.pack(id).get("premium", false)), bare)
		"text":
			return _emote_art((Emotes.text_pack(id).get("emotes", []) as Array).slice(0, 4), false, bare)
		"room":
			return Thumbnailer.view("room", id, UIKit.R.md)
		"scene":
			return Thumbnailer.view("scene", id, UIKit.R.md)
	var well := _well(kind) if not bare else _bare()
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.add_child(c)
	match kind:
		"dice":
			var die := Thumbnailer.dice_art(id, 104 if bare else 84)        # the baked die (a live Dice3D only without a bake)
			c.add_child(die)
			well.set_meta("art", die)
		"pawn":
			var pawn := Thumbnailer.pawn_art(id)           # the baked pair of pawns (a live PawnStage only without a bake)
			well.remove_child(c)
			c.queue_free()
			well.add_child(pawn)
			pawn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			well.set_meta("art", pawn)
			return well
		"avatar", "char":
			c.add_child(Collection.make_avatar_of(id, Collection.equipped("frame"), 92.0 if bare else 62.0))
		"frame":
			c.add_child(Collection.make_avatar_of(Collection.equipped("avatar"), id, 100.0 if bare else 60.0))
		"plate":
			c.add_child(Collection.make_plate(_player_name(), id, "", 17, true, 112.0))
		"badge":
			if id == "":
				c.add_child(NoBadge.new(80 if bare else 56))        # an empty medal outline, not a "None" placeholder word
			else:
				c.add_child(Collection.make_badge(id, 88 if bare else 56))
	if not well.has_meta("art") and c.get_child_count() > 0:
		well.set_meta("art", c.get_child(0))
	return well

## An empty container where a well would go (the game cards draw their own ground).
static func _bare() -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	return p

## A pack's icons on the Emotes tab's well: two columns (three for a Premium pack's eight), with its Premium tag.
func _emote_art(icons: Array, premium: bool, bare := false) -> Control:
	var well := _well("emotes") if not bare else _bare()
	var g := GridContainer.new()
	g.columns = 3 if icons.size() > 6 else 2
	g.name = "Icons"
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_theme_constant_override("h_separation", 2)
	g.add_theme_constant_override("v_separation", 0)
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for eid: String in icons:
		var t := TextureRect.new()
		t.texture = EmoteArt.icon(eid)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.size_flags_vertical = Control.SIZE_EXPAND_FILL
		t.custom_minimum_size = Vector2(10, 10)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.add_child(t)
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 4)
	m.add_child(g)
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.set_meta("art", g)
	if premium:
		var chip := PanelContainer.new()
		chip.name = "Premium"
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var st := UIKit.box(Palette.HONEY_TINT, UIKit.R.sm, 1, Palette.HONEY_TINT_EDGE)
		UIKit.pad(st, 2)
		chip.add_theme_stylebox_override("panel", st)
		var l := UIKit.label(tr("Premium"), UIKit.FS.label, Palette.INK, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(l)
		well.add_child(chip)
	return well

## A rounded well tinted with the tab's colour (Palette.CAT), behind dice / avatars / frames / plates / badges.
func _well(kind: String) -> Control:
	var cat: String = "emotes" if kind == "text" else {dice = "dice", pawn = "pawns", emotes = "emotes", avatar = "avatars", char = "avatars", frame = "frames", plate = "plates", badge = "badges"}.get(kind, "rooms")
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var st := UIKit.box(Palette.SURFACE_2, UIKit.R.md)
	UIKit.pad(st, 0)
	p.add_theme_stylebox_override("panel", st)
	if not _wells.has(cat):
		var face: Color = (Palette.CAT.get(cat, Palette.CAT.coins) as Array)[0]
		var g := GradientTexture2D.new()
		g.width = 8; g.height = 64
		g.fill_from = Vector2(0.5, 0.0); g.fill_to = Vector2(0.5, 1.0)
		g.gradient = Gradient.new()
		g.gradient.set_color(0, face.lerp(Color.WHITE, 0.78))
		g.gradient.set_color(1, face.lerp(Color.WHITE, 0.5))
		_wells[cat] = g
	var tr := TextureRect.new()
	tr.texture = _wells[cat]
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(tr)
	return p

## Over a room's or a scene's picture: the whole picture opens the 3D preview; a small glass "View" chip says so.
func _view_button(kind: String, id: String) -> Button:
	var b := Button.new()
	b.name = "View"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("view", id)
	b.tooltip_text = tr("View")
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := UIKit.box(Palette.GLASS, UIKit.R.pill, UIKit.BW.hair, Palette.LINE)
	UIKit.shade(cs, "sm")
	UIKit.pad(cs, 5, 3)
	chip.add_theme_stylebox_override("panel", cs)
	var h := UIKit.hbox(UIKit.SPACE.xs)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(UIKit.icon("ic_eye", 15))
	chip.add_child(h)
	b.add_child(chip)
	chip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 4)
	chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	UIKit.wire_press(b)
	b.pressed.connect(func(): _on_view(kind, id))
	return b

## The "In use" state (no button: the card's gold rim and this pill say it once).
static func in_use_pill(font_size: int = UIKit.FS.body_l) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "InUse"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.custom_minimum_size.y = UIKit.H.sm
	var st := UIKit.box(Palette.HONEY_TINT, UIKit.BTN.sm.r, UIKit.BW.line, Palette.HONEY_TINT_EDGE)
	UIKit.pad(st, UIKit.SPACE.sm, 0)
	p.add_theme_stylebox_override("panel", st)
	var h := UIKit.hbox(UIKit.SPACE.xs + 2)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UIKit.glyph("ic_check", font_size + 2, Palette.ON_HONEY)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := UIKit.label(L10n.t("In use"), font_size, Palette.ON_HONEY, UIKit.font_body(900))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	p.add_child(h)
	return p

## Under an Owned grid: "3 more in the shop · Show all", one 48 px link row (tap: show everything).
func _more_row(n: int) -> Control:
	var b := Button.new()
	b.name = "More"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = UIKit.TAP
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	var h := UIKit.hbox(UIKit.SPACE.xs + 2)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(h)
	var more := UIKit.label(tr("%d more in the shop") % n, UIKit.FS.label, Palette.SUB, UIKit.font_body(800))
	var dot := UIKit.label("·", UIKit.FS.label, Palette.SUB, UIKit.font_body(900))
	var link := UIKit.label(tr("Open shop") if inventory else tr("Show all"), UIKit.FS.label, Palette.TEAL_INK, UIKit.font_body(900))
	for l: Label in [more, dot, link]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(l)
	b.button_down.connect(func(): link.add_theme_color_override("font_color", Palette.TEAL_LIP))
	b.button_up.connect(func(): link.add_theme_color_override("font_color", Palette.TEAL_INK))
	UIKit.wire_press(b)
	b.pressed.connect(_show_all)
	return UIKit.margin(b, 0, UIKit.SPACE.xs, 0, 0)

## "Show all" in the Shop's Owned filter; "Open shop" (at this tab) in the Inventory.
func _show_all() -> void:
	if inventory:
		shop_requested.emit(tab)
	else:
		set_owned_only(false)

func _empty() -> Control:
	var v := UIKit.vbox(UIKit.SPACE.md)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(UIKit.paragraph(tr("You don’t own any of these yet."), UIKit.FS.body_l, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var b := UIKit.btn(tr("Open shop") if inventory else tr("Show all"), "white", "sm")
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size.x = 140
	b.pressed.connect(_show_all)
	v.add_child(b)
	return UIKit.margin(v, 0, UIKit.SPACE.xl, 0, 0)

func _player_name() -> String:
	return str(Collection.profile().get("name", "You"))


# =====================================================================================================================
# Actions
# =====================================================================================================================

## Buy with coins, from an offer (OfferSheet): short -> "Need 2.5K more coins"; offline -> says so; else buys and puts
## it in use at once (one tap buys: the offer's price button is the deliberate tap, no "Buy X?" question). True when
## bought (the offer then shows the RevealSheet); a failure is said on `host`.
static func buy_with_coins(host: Sheet, kind: String, id: String, _name: String) -> bool:
	var price := _price(kind, id)
	var short := price - Catalog.coins()
	if short > 0:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(host, L10n.t("Need %s more coins") % Fmt.coins(short), host.card, 1.8, "bad")
		return false
	if Account.wallet_active() and is_same(Collection.profile(), Save.profile):
		var online: bool = await Account.instance().ensure_session()      # offline: say so, nothing is tried
		if not is_instance_valid(host) or host._closing:
			return false
		if not online:
			Sound.sfx("error")
			Haptics.error()
			Toast.show(host, Account.error_text("offline", "buy"), host.card, 2.2, "bad")
			return false
	var err: String = await _purchase(kind, id)
	if not is_instance_valid(host) or host._closing:
		return false
	if err != "":
		Sound.sfx("error")
		Haptics.error()
		Toast.show(host, err, host.card, 2.2, "bad")
		return false
	Haptics.success()
	return true

## The purchase itself: "" when bought, else the reason to show. With an Account (the game) the server sells and the
## local profile is replaced by its answer; offline there is no local granting ("Connect to the internet to buy").
## Without one (previews, tests) the local rules apply.
static func _purchase(kind: String, id: String, currency := "coins") -> String:
	if Account.wallet_active() and is_same(Collection.profile(), Save.profile):
		var r: Dictionary = await Account.instance().buy(kind, id, currency)
		if r.get("ok", false):
			return ""
		if r.get("error", "") == "coins" and int(r.get("short", 0)) > 0:
			return Catalog.need_text(int(r.short))
		if r.get("error", "") == "gems" and int(r.get("short", 0)) > 0:
			return gems_need_text(int(r.short))
		return Account.error_text(str(r.get("error", "")), "buy")
	match kind:
		"room": return Catalog.buy_room(id)
		"dice": return Catalog.buy_dice(id)
		"pawn": return Catalog.buy_pawn(id)
		"scene": return SLScenes.buy_scene(id)
		"emotes": return Catalog.buy_emotes(id)
		"text": return Catalog.buy_text(id)
		"char": return Collection.buy_char(id, true)
		"frame", "plate": return Collection.buy_look(kind, id)
	return L10n.t("That isn’t for sale.")

## "<Item> is yours!" ("are" for dice).
static func _yours(kind: String, title: String) -> String:
	return (L10n.t("%s are yours!") if kind == "dice" or kind == "pawn" else L10n.t("%s is yours!")) % title

## "Not enough gems — you need 12 more."
static func gems_need_text(short: int) -> String:
	return L10n.t("Not enough gems — you need %s more.") % Fmt.coins_full(short)

## The gems purchase flow, shared by the offers: checks the wallet (too few gems: a dialog with the shortfall and
## "Open Store"), buys through _purchase at once (one tap buys) and says what went wrong on `host`. Returns ""
## (nothing happened), "store" (not enough gems and "Open Store" was chosen), "bought" or "failed".
static func buy_with_gems(host: Sheet, kind: String, id: String, name_: String) -> String:
	var gems := _gems(kind, id)
	if gems <= 0:
		return ""
	var have := int(Save.profile.get("gems", 0))
	var title := _title(kind, name_)
	if not (Account.wallet_active() and is_same(Collection.profile(), Save.profile)):
		Sound.sfx("error")
		Haptics.error()
		Toast.show(host, Account.error_text("offline", "buy"), host.card, 2.2, "bad")      # gems live on the server
		return ""
	if gems > have:
		Sound.sfx("error")
		Haptics.error()
		var open_store: bool = await Sheet.confirm(host, L10n.t("Not enough gems"), L10n.t("You need %s more gems for %s. You have %s.") % [Fmt.coins_full(gems - have), title, Fmt.coins_full(have)], L10n.t("Open Store"), L10n.t("Not now"))
		return "store" if open_store and is_instance_valid(host) and not host._closing else ""
	var online: bool = await Account.instance().ensure_session()
	if not is_instance_valid(host) or host._closing:
		return ""
	if not online:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(host, Account.error_text("offline", "buy"), host.card, 2.2, "bad")
		return ""
	var err: String = await _purchase(kind, id, "gems")
	if not is_instance_valid(host) or host._closing:
		return ""
	if err != "":
		Sound.sfx("error")
		Haptics.error()
		Toast.show(host, err, host.card, 2.2, "bad")
		return "failed"
	Haptics.success()
	return "bought"

## Put an owned item in use, through the server when there is an Account (the look is part of the profile it keeps;
## offline: "Connect to the internet to change your look"). "" when done, else the reason to show.
static func equip_item(kind: String, id: String) -> String:
	var ok := false
	var why := L10n.t(Collection.SAVE_FAILED_EQUIP)
	if Account.wallet_active() and is_same(Collection.profile(), Save.profile):
		var r: Dictionary = await Account.instance().equip("avatar" if kind == "char" else kind, id)
		ok = bool(r.get("ok", false))
		if not ok:
			why = Account.error_text(str(r.get("error", "")), "equip")
	else:
		match kind:
			"room": ok = Catalog.equip_room(id)
			"dice": ok = Catalog.equip_dice(id)
			"pawn": ok = Catalog.equip_pawn(id)
			"scene": ok = SLScenes.equip_scene(id)
			"emotes": ok = Catalog.equip_emotes(id)
			"text": ok = Catalog.equip_text(id)
			"char": ok = Collection.equip("avatar", id)
			_: ok = Collection.equip(kind, id)
	if ok and kind == "room":
		Save.prefs.room_auto = false              # their pick: the café no longer follows the clock (Rooms.shown)
	return "" if ok else why

## Use on a card.
func _on_use(kind: String, id: String) -> void:
	if _closing or _busy:
		return
	_busy = true
	var why: String = await equip_item(kind, id)
	_busy = false
	if not is_instance_valid(self) or _closing:
		return
	if why != "":
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, why, card, 2.2, "bad")
		return
	Sound.sfx("select")
	_announce(kind, id)
	refresh()

func _announce(kind: String, id: String) -> void:
	match kind:
		"room": room_changed.emit(id)
		"dice": dice_changed.emit(id)
		"scene": scene_changed.emit(id)
		"emotes", "text": emotes_changed.emit()
	changed.emit()

## View on a room or a scene: its live 3D preview (PreviewSheet) in place of the Shop, back here on close
## (index.html Preview: openSheet hides the Shop, closing returns to it). Use / Buy there = room_changed /
## scene_changed here.
func _on_view(kind: String, id: String) -> void:
	if get_parent() == null or _closing or _busy:
		return
	if kind == "emotes" or kind == "text":
		var es := EmotePackSheet.new(id, kind)
		es.changed.connect(func():
			emotes_changed.emit()
			changed.emit()
			refresh())
		es.store_requested.connect(func(): store_requested.emit())
		es.closed.connect(func():
			if is_instance_valid(self) and not _closing:
				refresh())
		es.open(get_parent())
		return
	if kind == "pawn":
		var ps := PawnSheet.new(id)
		ps.changed.connect(func():
			changed.emit()
			refresh())
		ps.store_requested.connect(func(): store_requested.emit())
		ps.closed.connect(func():
			if is_instance_valid(self) and not _closing:
				refresh())
		ps.open(get_parent())
		return
	var pv := PreviewSheet.new(id, kind)
	pv.room_changed.connect(func(rid: String):
		room_changed.emit(rid)
		changed.emit())
	pv.scene_changed.connect(func(sid: String):
		scene_changed.emit(sid)
		changed.emit())
	pv.bought.connect(func(_rid: String): refresh())
	pv.store_requested.connect(func(): store_requested.emit())
	pv.closed.connect(func():
		if is_instance_valid(self) and not _closing:
			refresh())
	pv.open(get_parent())

## The Get coins sheet over the Shop.
func open_earn() -> void:
	if get_parent() == null or _closing:
		return
	var e := make_earn()
	e.closed.connect(func():
		if is_instance_valid(self):
			refresh())
	e.open(get_parent())

## The Get coins sheet on its own (e.g. from the home coin chip): ShopSheet.make_earn().open(layer).
static func make_earn() -> Sheet:
	return RewardsSheet.new(L10n.t("Get coins"), true)       # the Rewards sheet's rows, one experience; taps go to Main


# =====================================================================================================================
# Forwarders for the other sheets (phase 3 removes them)
# =====================================================================================================================

const ON_ACCENT := Palette.ON_HONEY      ## forwarder: use Palette.ON_HONEY
const SUB := Palette.SUB                 ## forwarder: use Palette.SUB

## Forwarder: Toast.show(sheet, text, sheet.card).
static func toast(sheet: Sheet, text: String) -> void:
	Toast.show(sheet, text, sheet.card if sheet else null)

## Forwarder: Sound.sfx(n).
static func sfx(_from: Node, n: String) -> void:
	Sound.sfx(n)

## Forwarder: a gold "sm" kit button (UIKit.btn(text, "gold", "sm")).
static func item_button() -> Button:
	return UIKit.btn("", "gold", "sm")

## Forwarder: UIKit.set_kind(b, "gold" | "off").
static func style_item_button(b: Button, gold: bool) -> void:
	UIKit.style_button(b, "gold" if gold else "off", "sm")

## Forwarder: CoinAmount.new(n, "sm").
static func price_tag(n: int) -> Control:
	return CoinAmount.new(n, "sm", "plain")

## Forwarder: a CoinAmount chip on the sheet's header (left). Returns its label.
static func add_balance_chip(sheet: Sheet) -> Label:
	var chip := CoinAmount.new(Catalog.coins(), "md", "chip")
	sheet.header.add_child(chip)
	chip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE)
	chip.grow_vertical = Control.GROW_DIRECTION_BOTH
	return chip.text_label

## Forwarder: Sheet.fit(0.9, MAX_H) for sheets that fit themselves.
static func fit_fixed(c: Control, sc: ScrollContainer, width: float, vp: Vector2) -> void:
	c.custom_minimum_size.x = minf(width, vp.x - 2.0 * UIKit.GUTTER)
	var other := c.get_combined_minimum_size().y - sc.get_combined_minimum_size().y
	var h := maxf(180.0, minf(MAX_H, vp.y * 0.9) - other)
	if absf(sc.custom_minimum_size.y - h) > 0.5:
		sc.custom_minimum_size.y = h

## Forwarder: UIKit.grid(2) added to pane.
static func grid_box(pane: Control) -> GridContainer:
	var g := UIKit.grid(2, UIKit.SPACE.md)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.add_child(g)
	return g


# =====================================================================================================================
# Widgets
# =====================================================================================================================

## Keeps its height at width x ratio; its children fill it (anchors).
class ArtBox extends Control:
	var ratio := 0.75

	func _init(r: float) -> void:
		ratio = r
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 100)
		resized.connect(_shape)

	func _shape() -> void:
		var want := roundf(size.x * ratio)
		if size.x > 0.0 and absf(custom_minimum_size.y - want) > 0.5:
			custom_minimum_size.y = want


## The four sections as chunky tiles (mock): the picked one orange, raised and rimmed; the others wood. Each shows a
## picture of what's inside over its name.
class Tiles extends HBoxContainer:
	signal picked(key: String)
	var selected := ""
	var _tiles := {}          # key -> {panel, label}

	func _init(items: Array, sel: String) -> void:
		selected = sel
		name = "Sections"
		add_theme_constant_override("separation", 8)
		custom_minimum_size.y = 72
		for it: Dictionary in items:
			var key: String = it.key
			var p := GamePanel.vertical(Color("#6b3a20"), Color("#4a2414"))
			p.name = "Tile_" + key
			p.radius = 16.0
			p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			p.size_flags_vertical = Control.SIZE_SHRINK_END
			var col := UIKit.vbox(1)
			col.alignment = BoxContainer.ALIGNMENT_CENTER
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.add_child(col)
			var t := TextureRect.new()
			t.texture = _icon(key)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.custom_minimum_size = Vector2(38, 30)
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			col.add_child(t)
			var l := UIKit.label(str(it.text), 13, Color("#f3d9bf"), UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.add_theme_color_override("font_outline_color", OUTLINE)
			col.add_child(l)
			var b := Button.new()
			b.flat = true
			b.focus_mode = Control.FOCUS_NONE
			for k in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
				b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
			b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			b.pressed.connect(func():
				if key != selected:
					select(key)
					picked.emit(key))
			UIKit.wire_press(b)
			p.add_child(b)
			add_child(p)
			_tiles[key] = {panel = p, label = l}
		select(sel)

	func select(key: String) -> void:
		selected = key
		for k: String in _tiles:
			var on := k == key
			var p: GamePanel = _tiles[k].panel
			var l: Label = _tiles[k].label
			p.c0 = Color("#ff9a5c") if on else Color("#6b3a20")
			p.c1 = Color("#f8804a") if on else Color("#5a2f1a")
			p.c2 = Color("#f2622e") if on else Color("#4a2414")
			p.border = 3.0 if on else 0.0
			p.border_color = Color("#fff1b8")
			p.lip = 5.0 if on else 4.0
			p.lip_color = Color("#b8401a") if on else Color("#2a120a")
			p.custom_minimum_size.y = 72.0 if on else 64.0
			l.add_theme_color_override("font_color", Color.WHITE if on else Color("#f3d9bf"))
			l.add_theme_constant_override("outline_size", 4 if on else 0)
			l.add_theme_font_size_override("font_size", 14 if on else 13)

	static func _icon(key: String) -> Texture2D:
		match key:
			"boards": return Thumbnailer.baked("room", Rooms.DEFAULT)
			"pieces": return Thumbnailer.baked("pawn", "kitty")
			"emotes": return EmoteArt.icon("happy")
			"look": return Collection.medal_texture("first")
		return null


## "No badge": a dashed medal outline the size of a medal (the Badges tab's first card).
class NoBadge extends Control:
	func _init(px: float) -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0 + Vector2(0, size.y * 0.08)
		var r := minf(size.x, size.y) * 0.34
		var col := Color(Palette.MUTED, 0.55)
		var n := 16
		for i in n:
			var a0 := TAU * i / n
			draw_arc(c, r, a0, a0 + TAU / n * 0.55, 6, col, 3.0, true)
		# the ribbon stubs above the disc, as on the medals
		var w := r * 0.42
		for sx in [-1.0, 1.0]:
			var x: float = c.x + sx * w * 0.6
			draw_line(Vector2(x, c.y - r - 4.0), Vector2(x - sx * 2.0, c.y - r - r * 0.55), col, 3.0, true)
