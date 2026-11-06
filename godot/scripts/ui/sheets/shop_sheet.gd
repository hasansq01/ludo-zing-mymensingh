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
## Buying always asks first (Sheet.confirm), then goes through Catalog / SLScenes / Collection (coins checked, never
## charged twice, rolled back when the save fails), puts the item in use and says "<Item> is yours!".
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

var tab := "rooms"
var owned_only := false
var inventory := false                   ## the nav's Inventory: owned items only, no filter / balance row
var _tabs: TabStrip
var _sub_box: MarginContainer            # holds the filter of the tab showing (SUBS)
var _sub: HBoxContainer
var _sub_of := ""                        # the tab that filter belongs to
var _last_sub := {}                      # tab -> the category shown last on it
var _balance: CoinAmount
var _gems_amount: CoinAmount
var _earn_btn: Button
var _gem_btn: Button
var _bleed: MarginContainer
var _updaters: Array[Callable] = []
var _cards: Array[PanelContainer] = []
var _open_earn := false
var _busy := false                       # a purchase confirm is showing


func _init(start_tab := "rooms", width := 400.0, owned_only_ := false, inventory_ := false) -> void:
	super(L10n.t("Inventory") if inventory_ else L10n.t("Shop"), width, true, LOOK_PM)
	inventory = inventory_
	owned_only = owned_only_ or inventory_
	_open_earn = start_tab == "coins"
	tab = _norm_tab(start_tab)
	var st := card.get_theme_stylebox("panel")        # Sheet's own PM frame
	st.content_margin_left = SIDE_PAD
	st.content_margin_right = SIDE_PAD
	# the coins and the gems, each with its "+" (coins: Get coins; gems: the Store)
	var row := UIKit.hbox(UIKit.SPACE.sm)
	_earn_btn = _balance_button()
	_earn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_earn_btn)
	_gem_btn = _gems_button()
	_gem_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_gem_btn)
	row.visible = not inventory               # the inventory lists what you own: nothing to buy
	body.add_child(row)
	# the tabs reach the card's rim
	var tabs := TABS.duplicate(true)
	for t: Dictionary in tabs:
		t.text = L10n.t(t.text)
	_tabs = TabStrip.new(tabs, strip_key(tab), "gtabs")
	_tabs.picked.connect(show_tab)
	_bleed = UIKit.margin(_tabs, -_bleed_px(), 0, -_bleed_px(), 0)
	body.add_child(_bleed)
	_sub_box = UIKit.margin(Control.new(), 0, UIKit.SPACE.xs, 0, 0)
	_sub_box.name = "SubFilter"
	body.add_child(_sub_box)
	add_scroll_body(UIKit.SPACE.sm)
	fit(0.9, MAX_H)
	narrow_changed.connect(_on_narrow)


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

## The filter under the tabs: built when the tab changes, the category marked.
func _show_filter(strip: String) -> void:
	if strip != _sub_of:
		_sub_of = strip
		for c in _sub_box.get_children():
			_sub_box.remove_child(c)
			c.queue_free()
		_sub = UIKit.segmented((SUBS[strip] as Array).map(func(l: Array) -> Array: return [l[0], L10n.t(l[1])]), tab, show_tab, "sm")
		_sub.name = "Filter"
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
	var gap: int = UIKit.SPACE.xs if is_narrow else UIKit.SPACE.sm
	for sec: Array in sections:
		total += (sec[1] as Array).size()
		var items: Array = _ordered(sec[1].filter(func(it: Dictionary) -> bool: return not owned_only or _owned(it.kind, it.id)))
		if items.is_empty():
			continue
		if sec[0] != "" and sections.size() > 1:
			var cap := UIKit.caption(sec[0])
			cap.name = "Section"
			scroll_body.add_child(UIKit.margin(cap, 4, UIKit.SPACE.sm if shown > 0 else 0, 0, 0))
		var g := UIKit.grid(2 if WIDE.has(items[0].kind) else 3, gap)
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
	var st := card.get_theme_stylebox("panel")
	st.content_margin_left = SIDE_PAD - 2 if is_narrow else SIDE_PAD
	st.content_margin_right = st.content_margin_left
	for side in ["margin_left", "margin_right"]:
		_bleed.add_theme_constant_override(side, -_bleed_px())
	if is_inside_tree():
		_build()

## How far the tabs reach past the content: to the inside of the PM frame's white rim.
func _bleed_px() -> int:
	var st := card.get_theme_stylebox("panel")
	return maxi(0, int(st.content_margin_left) - UIKit.BW.card)

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

func _chip(amount: CoinAmount) -> Button:
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plus := PanelContainer.new()
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := UIKit.box(Palette.TEAL, UIKit.R.pill, UIKit.BW.line, Color.WHITE)
	UIKit.pad(ps, 0)
	plus.add_theme_stylebox_override("panel", ps)
	plus.custom_minimum_size = Vector2(24, 24)
	var pl := UIKit.label("+", 19, Color.WHITE, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.add_child(pl)
	var h := UIKit.hbox(UIKit.SPACE.sm)
	h.add_child(amount)
	h.add_child(plus)
	return UIKit.button_with("", h, "white", "sm")


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
	return 0

## The gem price: ceil(coins / 100) (Catalog.gem_price), or a gem-only pawn skin's own; 0 when not sold.
static func _gems(kind: String, id: String) -> int:
	return Catalog.pawn_gems(id) if kind == "pawn" else Catalog.gem_price(_price(kind, id))

## Sold for gems only (a premium pawn skin): no coin price, the card's Buy pays gems.
static func _gems_only(kind: String, id: String) -> bool:
	return kind == "pawn" and Catalog.pawn_gems_only(id)

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

func _card(it: Dictionary) -> PanelContainer:
	var kind: String = it.kind
	var id: String = it.id
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.set_meta("item", id)
	p.add_theme_stylebox_override("panel", _card_face(false))
	var v := UIKit.vbox(UIKit.SPACE.xs)
	p.add_child(v)
	# art
	var art := ArtBox.new(ART_PLATE if kind == "plate" else (ART_WIDE if WIDE.has(kind) else ART_SQUARE))
	var view := _art(kind, id)
	art.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if PREVIEWS.has(kind):
		art.add_child(_view_button(kind, id))
	v.add_child(art)
	# name: one line on every card
	var nl := UIKit.label(L10n.t(it.name), NAME_FS, Palette.INK, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	nl.name = "ItemName"
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if kind == "badge":                      # the long names ("Experienced Player"): two lines, on every badge
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.max_lines_visible = 2
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nl.add_theme_constant_override("line_spacing", -3)
		nl.custom_minimum_size.y = ceilf(nl.get_theme_font("font").get_height(NAME_FS) * 2.0 - 3.0)
	else:
		nl.clip_text = true
	v.add_child(nl)
	# the state line: one of these shows
	var slot := MarginContainer.new()
	slot.custom_minimum_size.y = STATE_H
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(slot)
	var gems_only := _gems_only(kind, id)
	var price_row := CenterContainer.new()
	price_row.name = "Price"
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := CoinAmount.gems(_gems(kind, id), "sm", "plain") if gems_only else CoinAmount.new(_price(kind, id), "sm", "plain")
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_child(tag)
	slot.add_child(price_row)
	var use := UIKit.btn(tr("Use"), "teal", "xs")
	use.name = "Use"
	use.pressed.connect(func(): _on_use(kind, id))
	slot.add_child(use)
	var on_pill := in_use_pill(UIKit.FS.body)
	on_pill.custom_minimum_size.y = STATE_H
	slot.add_child(on_pill)
	var lock_row := UIKit.hbox(UIKit.SPACE.xs)
	lock_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var li := UIKit.icon("ic_lock", 15)
	li.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lock_row.add_child(li)
	var ll := UIKit.label(_unlock_note(kind, id), 11, Palette.MUTED, UIKit.font_body(800))
	ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ll.max_lines_visible = 2
	ll.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ll.custom_minimum_size.y = STATE_H
	ll.add_theme_constant_override("line_spacing", -3)
	lock_row.add_child(ll)
	slot.add_child(lock_row)
	UIKit.on_tap(p, func() -> void: _on_card(kind, id, ll.text if lock_row.visible else "", p))
	_cards.append(p)
	_updaters.append(func():
		var owned := _owned(kind, id)
		var on := owned and _in_use(kind, id)
		var for_sale := not owned and (_price(kind, id) > 0 or gems_only)
		p.add_theme_stylebox_override("panel", _card_face(on))
		price_row.visible = for_sale
		use.visible = owned and not on
		on_pill.visible = on
		lock_row.visible = not owned and not for_sale
		(view.get_meta("art", view) as CanvasItem).modulate.a = 0.55 if lock_row.visible else 1.0)
	return p

## The catalog tile with tighter padding: the art takes the room.
func _card_face(on: bool) -> StyleBoxFlat:
	var st := UIKit.surface("item", on, is_narrow).duplicate() as StyleBoxFlat
	UIKit.pad(st, 5 if is_narrow else 6)
	return st

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
func _art(kind: String, id: String) -> Control:
	match kind:
		"emotes":
			return _emote_art(Emotes.pack(id).get("emotes", []), bool(Emotes.pack(id).get("premium", false)))
		"text":
			return _emote_art((Emotes.text_pack(id).get("emotes", []) as Array).slice(0, 4), false)
		"room":
			return Thumbnailer.view("room", id, UIKit.R.md)
		"scene":
			return Thumbnailer.view("scene", id, UIKit.R.md)
	var well := _well(kind)
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.add_child(c)
	match kind:
		"dice":
			var die := Thumbnailer.dice_art(id, 84)        # the baked die (a live Dice3D only without a bake)
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
			c.add_child(Collection.make_avatar_of(id, Collection.equipped("frame"), 62))
		"frame":
			c.add_child(Collection.make_avatar_of(Collection.equipped("avatar"), id, 62))
		"plate":
			c.add_child(Collection.make_plate(_player_name(), id, "", 15, true, 112.0))
		"badge":
			if id == "":
				c.add_child(NoBadge.new(56))        # an empty medal outline, not a "None" placeholder word
			else:
				c.add_child(Collection.make_badge(id, 56))
	if not well.has_meta("art") and c.get_child_count() > 0:
		well.set_meta("art", c.get_child(0))
	return well

## A pack's icons on the Emotes tab's well: two columns (three for a Premium pack's eight), with its Premium tag.
func _emote_art(icons: Array, premium: bool) -> Control:
	var well := _well("emotes")
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

## Buy with coins, from a preview: short -> "Need 2.5K more coins"; offline -> says so; else confirm -> buy and put in
## use -> "<Item> is yours!" on `host`. True when bought.
static func buy_with_coins(host: Sheet, kind: String, id: String, name_: String) -> bool:
	var price := _price(kind, id)
	var short := price - Catalog.coins()
	var title := _title(kind, name_)
	if short > 0:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(host, L10n.t("Need %s more coins") % Fmt.coins(short), host.card, 1.8, "bad")
		return false
	if Account.wallet_active() and is_same(Collection.profile(), Save.profile):
		var online: bool = await Account.instance().ensure_session()      # offline: say so before asking to confirm
		if not is_instance_valid(host) or host._closing:
			return false
		if not online:
			Sound.sfx("error")
			Haptics.error()
			Toast.show(host, Account.error_text("offline", "buy"), host.card, 2.2, "bad")
			return false
	var yes: bool = await Sheet.confirm(host, L10n.t("Buy %s?") % title, L10n.t("%s coins. You’ll have %s left.") % [Fmt.coins(price), Fmt.coins(Catalog.coins() - price)], L10n.t("Buy"))
	if not yes or not is_instance_valid(host) or host._closing:
		return false
	var err: String = await _purchase(kind, id)
	if not is_instance_valid(host) or host._closing:
		return false
	if err != "":
		Sound.sfx("error")
		Haptics.error()
		Toast.show(host, err, host.card, 2.2, "bad")
		return false
	Sound.sfx("buy")
	Haptics.success()
	Toast.show(host, _yours(kind, title), host.card, 1.8, "good")
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
	return L10n.t("That isn’t for sale.")

## "<Item> is yours!" ("are" for dice).
static func _yours(kind: String, title: String) -> String:
	return (L10n.t("%s are yours!") if kind == "dice" or kind == "pawn" else L10n.t("%s is yours!")) % title

## "Not enough gems — you need 12 more."
static func gems_need_text(short: int) -> String:
	return L10n.t("Not enough gems — you need %s more.") % Fmt.coins_full(short)

## The gems purchase flow, shared with the Preview: checks the wallet, asks first, buys through _purchase and says so
## on `host` (its toasts and confirms). Returns "" (nothing happened), "store" (not enough gems and "Open Store" was
## chosen), "bought" or "failed".
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
	var yes: bool = await Sheet.confirm(host, L10n.t("Buy %s?") % title, L10n.t("%s gems. You’ll have %s left.") % [Fmt.coins_full(gems), Fmt.coins_full(have - gems)], L10n.t("Buy"))
	if not yes or not is_instance_valid(host) or host._closing:
		return ""
	var err: String = await _purchase(kind, id, "gems")
	if not is_instance_valid(host) or host._closing:
		return ""
	if err != "":
		Sound.sfx("error")
		Haptics.error()
		Toast.show(host, err, host.card, 2.2, "bad")
		return "failed"
	Sound.sfx("buy")
	Haptics.success()
	Toast.show(host, _yours(kind, title), host.card, 1.8, "good")
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
