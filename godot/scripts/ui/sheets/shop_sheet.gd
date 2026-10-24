class_name ShopSheet
extends Sheet
## The one Shop (PLAN decision 4: Shop + Inventory + Collection merged). Everything the player can buy, earn or put
## in use lives here, in seven category tabs (TabStrip "gtabs"): Rooms / Scenes / Dice / Avatars (the illustrated
## characters first, then the classic avatars) / Frames / Plates / Badges. An "All | Owned" switch filters the grid
## to what the player owns, for equipping (InventorySheet and CollectionSheet open the Shop that way).
##
## The PM look (the ribbon sheet family): the "Shop" ribbon and the close X; under it one row with All | Owned and the
## balance chip (coin, amount, "+": tap = Get coins), then the tabs. Only the two-column grid scrolls; the card keeps
## one size on every tab.
## A card: the item's art (real 3D thumbnails for rooms and scenes via Thumbnailer, a live Dice3D for dice, the
## portrait / frame / plate / medal from Collection for the rest), its name, and one state row (48 px on every card):
##   for sale     price + Buy (gold), or price + "Need 2.5K" (off: tapping says how many coins are missing)
##   owned        Use (teal)
##   in use       an "In use" pill, and the card wears the gold rim
##   locked       lock + what unlocks it ("Reach level 5", "Win 3 games in a row"), the art faded
## Rooms and scenes: tapping the picture (the "View" chip) opens the live 3D PreviewSheet in place of the Shop.
## Owned filter: a "3 more in the shop · Show all" link row under the grid; a single owned item is centred.
## Buying always asks first (Sheet.confirm), then goes through Catalog / SLScenes / Collection (coins checked, never
## charged twice, rolled back when the save fails), puts the item in use and says "<Item> is yours!".
## Coins come from the Get coins sheet (EarnSheet below): Daily reward, Daily spin and Free coins with their live
## state, each opening its own sheet from Main.
##
##   var s := ShopSheet.new("dice")                 # all items, Dice tab
##   var s := ShopSheet.new("avatars", 400, true)   # owned only (equip)
##   s.room_changed.connect(app.apply_room); s.open(layer)

signal room_changed(id: String)
signal dice_changed(id: String)
signal scene_changed(id: String)         ## a Snakes & Ladders scene was bought / put in use (SLScenes)
signal changed                           ## anything was bought or put in use (rooms, dice, scenes, avatars, frames ...)
signal shop_requested(tab: String)       ## Inventory: "Open shop" (main closes the inventory and opens the Shop there)

const TABS := [
	{key = "rooms", text = "Rooms"},
	{key = "scenes", text = "Scenes"},
	{key = "dice", text = "Dice"},
	{key = "avatars", text = "Avatars"},
	{key = "frames", text = "Frames"},
	{key = "plates", text = "Plates"},
	{key = "badges", text = "Badges"},
]
## Old tab names (Collection, the Coins tab, Inventory) -> the merged tabs.
const TAB_ALIAS := {chars = "avatars", characters = "avatars", nameplates = "plates", coins = "rooms"}
const MAX_H := 680.0                     ## one card height for every tab (web .shop-card min(100%, 680px))
const ART_RATIO := 0.75                  ## card art height / width (the 4:3 thumbnails)
const SIDE_PAD := 14                     ## card side padding (the seven tabs need the width)
const NAME_FS := 16

static var _wells := {}                  # category -> GradientTexture2D (the art well behind dice / avatars ...)

var tab := "rooms"
var owned_only := false
var inventory := false                   ## the nav's Inventory: owned items only, no filter / balance row
var _tabs: TabStrip
var _filter: HBoxContainer
var _balance: CoinAmount
var _earn_btn: Button
var _bleed: MarginContainer
var _updaters: Array[Callable] = []
var _cards: Array[PanelContainer] = []
var _open_earn := false
var _busy := false                       # a purchase confirm is showing


func _init(start_tab := "rooms", width := 400.0, owned_only_ := false, inventory_ := false) -> void:
	super("Inventory" if inventory_ else "Shop", width, true, LOOK_PM)
	inventory = inventory_
	owned_only = owned_only_ or inventory_
	_open_earn = start_tab == "coins"
	tab = _norm_tab(start_tab)
	var st := card.get_theme_stylebox("panel")        # Sheet's own PM frame
	st.content_margin_left = SIDE_PAD
	st.content_margin_right = SIDE_PAD
	# All | Owned, then the balance with its "+" (tap = Get coins), on one row under the ribbon
	var row := UIKit.hbox(UIKit.SPACE.sm)
	_filter = UIKit.segmented([["all", "All"], ["owned", "Owned"]], "owned" if owned_only else "all", _on_filter, "sm")
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_filter)
	_earn_btn = _balance_button()
	row.add_child(_earn_btn)
	row.visible = not inventory               # the inventory lists what you own: nothing to filter or buy
	body.add_child(row)
	# the tabs reach the card's rim (seven icon + label tabs need the width)
	_tabs = TabStrip.new(TABS.duplicate(true), tab, "gtabs")
	_tabs.picked.connect(show_tab)
	_bleed = UIKit.margin(_tabs, -_bleed_px(), 0, -_bleed_px(), 0)
	body.add_child(_bleed)
	add_scroll_body(UIKit.SPACE.md)
	fit(0.9, MAX_H)
	narrow_changed.connect(_on_narrow)


func _ready() -> void:
	Save.changed.connect(refresh)
	show_tab(tab)
	if _open_earn:
		open_earn.call_deferred()


static func _norm_tab(key: String) -> String:
	key = str(TAB_ALIAS.get(key, key))
	for t: Dictionary in TABS:
		if t.key == key:
			return key
	return "rooms"


## Switch to a category and list its cards from the top.
func show_tab(key: String) -> void:
	tab = _norm_tab(key)
	_tabs.select(tab)
	_build()

## Show everything, or only what the player owns.
func set_owned_only(on: bool) -> void:
	owned_only = on
	for b in _filter.get_children():
		if b is Button:
			(b as Button).set_pressed_no_signal(b.get_meta("value", "") == ("owned" if on else "all"))
	_build()

func _on_filter(v: String) -> void:
	owned_only = v == "owned"
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
	var gap: int = UIKit.SPACE.sm if is_narrow else UIKit.SPACE.md
	for sec: Array in sections:
		total += (sec[1] as Array).size()
		var items: Array = sec[1].filter(func(it: Dictionary) -> bool: return not owned_only or _owned(it.kind, it.id))
		if items.is_empty():
			continue
		if sec[0] != "" and sections.size() > 1:
			var cap := UIKit.caption(sec[0])
			cap.name = "Section"
			scroll_body.add_child(UIKit.margin(cap, 4, UIKit.SPACE.sm if shown > 0 else 0, 0, 0))
		if items.size() == 1 and owned_only:
			scroll_body.add_child(HalfRow.new(_card(items[0]), gap))   # one owned item: centred, card-sized
		else:
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

## Re-read the profile: the balance and every card's state.
func refresh() -> void:
	if not is_instance_valid(_balance):
		return
	var c := Catalog.coins()
	if c != _balance.amount:
		_balance.set_amount(c, is_inside_tree())
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

## The balance as a white chip button: coin + amount + a teal "+" (the home top bar's coin chip); tap = Get coins.
func _balance_button() -> Button:
	_balance = CoinAmount.new(Catalog.coins(), "md", "plain")
	_balance.name = "Balance"
	_balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	h.add_child(_balance)
	h.add_child(plus)
	var b := UIKit.button_with("", h, "white", "sm")
	b.name = "GetCoins"
	b.tooltip_text = "Get coins"
	b.custom_minimum_size.x = 120
	_balance.resized.connect(func():
		b.custom_minimum_size.x = maxf(120.0, h.get_combined_minimum_size().x + 2.0 * float(UIKit.BTN.sm.pad)))
	b.pressed.connect(open_earn)
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
				["Characters", chars.map(func(c: Dictionary) -> Dictionary: return {kind = "char", id = c.id, name = c.name})],
				["Classic", classic.map(func(a: Dictionary) -> Dictionary: return {kind = "avatar", id = a.id, name = a.name})],
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
	return Collection.is_unlocked(kind, id)

static func _in_use(kind: String, id: String) -> bool:
	match kind:
		"room": return Catalog.room_in_use() == id
		"scene": return SLScenes.scene_in_use() == id
		"dice": return Catalog.dice_in_use() == id
		"char": return Collection.is_equipped("avatar", id)
	return Collection.is_equipped(kind, id)

static func _price(kind: String, id: String) -> int:
	match kind:
		"room": return int(Catalog.room(id).get("price", 0))
		"scene": return int(SLScenes.info(id).get("price", 0))
		"dice": return int(Catalog.dice(id).get("price", 0))
		"char": return int(Collection.character(id).get("price", 0))
	return 0

## The name in sentences: "Royal Gold dice", "Pastel Dream Room".
static func _title(kind: String, name_: String) -> String:
	return name_ + " dice" if kind == "dice" else name_

## What unlocks a level / achievement item, as the thing to do: "Reach level 5", "Win 3 games in a row".
static func _unlock_note(kind: String, id: String) -> String:
	var ach_id := id if kind == "badge" else ""
	if kind != "badge":
		var u: Dictionary = Collection.item(kind, id).get("unlock", {})
		if u.has("level"):
			return "Reach level %d" % int(u.level)
		ach_id = str(u.get("ach", ""))
	var a := Collection.ach(ach_id)
	return str(a.desc).trim_suffix(".") if not a.is_empty() else Collection.unlock_text(kind, id)


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
	p.add_theme_stylebox_override("panel", UIKit.surface("item", false, is_narrow))
	var v := UIKit.vbox(UIKit.SPACE.sm - 2)
	p.add_child(v)
	# art
	var art := ArtBox.new(ART_RATIO)
	var view := _art(kind, id)
	art.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var price := _price(kind, id)
	var tag := CoinAmount.new(price, "sm", "price")
	tag.name = "Price"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if kind == "room" or kind == "scene":
		art.add_child(_view_button(kind, id))
	art.add_child(tag)
	tag.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 6)
	tag.grow_vertical = Control.GROW_DIRECTION_BEGIN
	v.add_child(art)
	# name: two lines kept for every card, so the state rows line up
	var nl := UIKit.label(it.name, NAME_FS, Palette.INK, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.max_lines_visible = 2
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.add_theme_constant_override("line_spacing", -4)
	nl.custom_minimum_size.y = ceilf(nl.get_theme_font("font").get_height(NAME_FS) * 2.0 - 4.0)
	v.add_child(nl)
	# the state row: one of these shows
	var slot := MarginContainer.new()
	slot.custom_minimum_size.y = UIKit.TAP
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(slot)
	var buy := UIKit.btn("Buy", "gold", "sm")
	buy.name = "Buy"
	UIKit.fit_text(buy, 13)
	buy.pressed.connect(func(): _on_buy(kind, id, it.name))
	slot.add_child(buy)
	var use := UIKit.btn("Use", "teal", "sm")
	use.name = "Use"
	use.pressed.connect(func(): _on_use(kind, id))
	slot.add_child(use)
	var on_pill := in_use_pill()
	slot.add_child(on_pill)
	var lock_row := UIKit.hbox(UIKit.SPACE.xs + 2)
	lock_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var li := UIKit.icon("ic_lock", 20)
	li.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lock_row.add_child(li)
	var ll := UIKit.label(_unlock_note(kind, id), UIKit.FS.small, Palette.MUTED, UIKit.font_body(800))
	ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ll.max_lines_visible = 2                         # the footer keeps the button's height on every card
	ll.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ll.custom_minimum_size.y = 34
	ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ll.add_theme_constant_override("line_spacing", -3)
	lock_row.add_child(ll)
	slot.add_child(lock_row)
	_cards.append(p)
	_updaters.append(func():
		var owned := _owned(kind, id)
		var on := owned and _in_use(kind, id)
		var for_sale := not owned and price > 0
		p.add_theme_stylebox_override("panel", UIKit.surface("item", on, is_narrow))
		buy.visible = for_sale
		tag.visible = for_sale
		use.visible = owned and not on
		on_pill.visible = on
		lock_row.visible = not owned and not for_sale
		(view.get_meta("art", view) as CanvasItem).modulate.a = 0.55 if lock_row.visible else 1.0
		if for_sale:
			var short := price - Catalog.coins()
			buy.text = "Buy" if short <= 0 else Fmt.shortfall(short)
			if buy.get_meta("kit_kind", "") != ("gold" if short <= 0 else "off"):
				UIKit.set_kind(buy, "gold" if short <= 0 else "off"))
	return p

## The art of an item, filling its ArtBox.
func _art(kind: String, id: String) -> Control:
	match kind:
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
		"avatar", "char":
			c.add_child(Collection.make_avatar_of(id, Collection.equipped("frame"), 74))
		"frame":
			c.add_child(Collection.make_avatar_of(Collection.equipped("avatar"), id, 74))
		"plate":
			c.add_child(Collection.make_plate(_player_name(), id, "", 15, true, 112.0))
		"badge":
			if id == "":
				c.add_child(NoBadge.new(68))        # an empty medal outline, not a "None" placeholder word
			else:
				c.add_child(Collection.make_badge(id, 68))
	if not well.has_meta("art") and c.get_child_count() > 0:
		well.set_meta("art", c.get_child(0))
	return well

## A rounded well tinted with the tab's colour (Palette.CAT), behind dice / avatars / frames / plates / badges.
func _well(kind: String) -> Control:
	var cat: String = {dice = "dice", avatar = "avatars", char = "avatars", frame = "frames", plate = "plates", badge = "badges"}.get(kind, "rooms")
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
	b.tooltip_text = "View"
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := UIKit.box(Palette.GLASS, UIKit.R.pill, UIKit.BW.hair, Palette.LINE)
	UIKit.shade(cs, "sm")
	UIKit.pad(cs, 8, 3)
	chip.add_theme_stylebox_override("panel", cs)
	var h := UIKit.hbox(UIKit.SPACE.xs)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(UIKit.icon("ic_eye", 18))
	if not is_narrow:                      # narrow cards: the eye alone, clear of the price tag
		var l := UIKit.label("View", UIKit.FS.small + 1, Palette.INK, UIKit.font_body(900))
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(l)
	chip.add_child(h)
	b.add_child(chip)
	chip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 6)
	chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	UIKit.wire_press(b)
	b.pressed.connect(func(): _on_view(kind, id))
	return b

## The "In use" state (no button: the card's gold rim and this pill say it once).
static func in_use_pill() -> PanelContainer:
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
	var ic := UIKit.glyph("ic_check", 18, Palette.ON_HONEY)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := UIKit.label("In use", UIKit.FS.body_l, Palette.ON_HONEY, UIKit.font_body(900))
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
	var more := UIKit.label("%d more in the shop" % n, UIKit.FS.label, Palette.SUB, UIKit.font_body(800))
	var dot := UIKit.label("·", UIKit.FS.label, Palette.SUB, UIKit.font_body(900))
	var link := UIKit.label("Open shop" if inventory else "Show all", UIKit.FS.label, Palette.TEAL_INK, UIKit.font_body(900))
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
	v.add_child(UIKit.paragraph("You don’t own any of these yet.", UIKit.FS.body_l, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var b := UIKit.btn("Open shop" if inventory else "Show all", "white", "sm")
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

## Buy: enough coins -> confirm -> buy and put in use -> "<Item> is yours!". Short -> "Need 2.5K more coins".
func _on_buy(kind: String, id: String, name_: String) -> void:
	if _busy or _closing:
		return
	var price := _price(kind, id)
	var short := price - Catalog.coins()
	var title := _title(kind, name_)
	if short > 0:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, "Need %s more coins" % Fmt.coins(short), card, 1.8, "bad")
		return
	_busy = true
	var yes: bool = await Sheet.confirm(self, "Buy %s?" % title, "%s coins. You’ll have %s left." % [Fmt.coins(price), Fmt.coins(Catalog.coins() - price)], "Buy")
	_busy = false
	if not yes or not is_instance_valid(self) or _closing:
		return
	var err := ""
	match kind:
		"room": err = Catalog.buy_room(id)
		"dice": err = Catalog.buy_dice(id)
		"scene": err = SLScenes.buy_scene(id)
		"char": err = Collection.buy_char(id, true)
		_: err = "That isn’t for sale."
	if err != "":
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, err, card, 2.2, "bad")
		refresh()
		return
	Sound.sfx("buy")
	Haptics.success()
	Toast.show(self, "%s %s yours!" % [title, "are" if kind == "dice" else "is"], card, 1.8, "good")
	_announce(kind, id)
	refresh()

## Use: put an owned item in use.
func _on_use(kind: String, id: String) -> void:
	if _closing:
		return
	var ok := false
	match kind:
		"room": ok = Catalog.equip_room(id)
		"dice": ok = Catalog.equip_dice(id)
		"scene": ok = SLScenes.equip_scene(id)
		"char": ok = Collection.equip("avatar", id)
		_: ok = Collection.equip(kind, id)
	if not ok:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, Collection.SAVE_FAILED_EQUIP, card, 2.2, "bad")
		return
	Sound.sfx("select")
	_announce(kind, id)
	refresh()

func _announce(kind: String, id: String) -> void:
	match kind:
		"room": room_changed.emit(id)
		"dice": dice_changed.emit(id)
		"scene": scene_changed.emit(id)
	changed.emit()

## View on a room or a scene: its live 3D preview (PreviewSheet) in place of the Shop, back here on close
## (index.html Preview: openSheet hides the Shop, closing returns to it). Use / Buy there = room_changed /
## scene_changed here.
func _on_view(kind: String, id: String) -> void:
	if get_parent() == null or _closing or _busy:
		return
	var pv := PreviewSheet.new(id, kind)
	pv.room_changed.connect(func(rid: String):
		room_changed.emit(rid)
		changed.emit())
	pv.scene_changed.connect(func(sid: String):
		scene_changed.emit(sid)
		changed.emit())
	pv.bought.connect(func(_rid: String): refresh())
	pv.closed.connect(func():
		if is_instance_valid(self) and not _closing:
			visible = true
			refresh()
			UIKit.pop_in(card))
	visible = false
	pv.open(get_parent())

## The Get coins sheet over the Shop.
func open_earn() -> void:
	if get_parent() == null or _closing:
		return
	var e := EarnSheet.new()
	e.closed.connect(func():
		if is_instance_valid(self):
			refresh())
	e.open(get_parent())

## The Get coins sheet on its own (e.g. from the home coin chip): ShopSheet.make_earn().open(layer).
static func make_earn() -> Sheet:
	return EarnSheet.new()


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

## One card alone on a row, centred at the width it has in the two-column grid (an Owned tab with one item).
class HalfRow extends Container:
	var gap := 12

	func _init(child: Control, gap_: int) -> void:
		gap = gap_
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(child)

	func _get_minimum_size() -> Vector2:
		var c := get_child(0) as Control if get_child_count() > 0 else null
		return Vector2(0, c.get_combined_minimum_size().y if c else 0.0)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN and get_child_count() > 0:
			var c := get_child(0) as Control
			var w := floorf((size.x - gap) / 2.0)
			fit_child_in_rect(c, Rect2((size.x - w) / 2.0, 0, w, size.y))


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


## Get coins (web Coins tab -> an Earn hub with live actions): Daily reward, Daily spin and Free coins with their
## state now ("Day 3 reward is ready", "Next spin in 13h 20m", "Next in 3:53:10"), each button opening its own sheet
## through Main._on_tab; plus what a win pays. Updates every second and on Save.changed.
class EarnSheet extends Sheet:
	var _rows := {}                      # key -> {status: Label, button: Button}
	var _tick: Timer

	func _init() -> void:
		super("Get coins", UIKit.W.form, true, LOOK_PM)
		var list := add_scroll_body(UIKit.SPACE.sm)
		_rows.daily = _row(list, "side_gift", "Daily reward", "daily")
		_rows.spin = _row(list, "side_spin", "Daily spin", "spin")
		_rows.free = _row(list, "side_coins", "Free coins", "free")
		var win := UIKit.panel("row")
		var h := UIKit.hbox(UIKit.SPACE.md)
		var ic := UIKit.icon("ic_trophy", 44)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var v := UIKit.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(_title_label("Win vs computer"))
		var note := UIKit.paragraph("%s coins in Ludo, %s in Snakes & Ladders" % [Fmt.gain(LudoRules.WIN_REWARD), Fmt.gain(SnakesLaddersRules.REWARD)], UIKit.FS.body, Palette.SUB)
		v.add_child(note)
		h.add_child(v)
		win.add_child(h)
		list.add_child(win)
		fit()

	func _ready() -> void:
		Save.changed.connect(refresh)
		_tick = Timer.new()
		_tick.wait_time = 1.0
		_tick.timeout.connect(refresh)
		add_child(_tick)
		_tick.start()
		refresh()

	static func _title_label(t: String) -> Label:
		var l := UIKit.label(t, UIKit.FS.h3, Palette.INK, UIKit.font_body(900))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART     # no minimum width: the row fits narrow cards
		l.add_theme_constant_override("line_spacing", -3)
		return l

	func _row(list: VBoxContainer, icon_name: String, title_text: String, key: String) -> Dictionary:
		var p := UIKit.panel("row")
		var h := UIKit.hbox(UIKit.SPACE.md)
		var ic := UIKit.icon(icon_name, 44)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var v := UIKit.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(_title_label(title_text))
		var st := UIKit.paragraph("", UIKit.FS.body, Palette.SUB)
		v.add_child(st)
		h.add_child(v)
		var b := UIKit.btn("Open", "honey", "sm")
		b.name = key.capitalize()
		b.custom_minimum_size.x = 88
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UIKit.fit_text(b, 13)
		b.pressed.connect(func(): _go(key))
		h.add_child(b)
		p.add_child(h)
		list.add_child(p)
		return {status = st, button = b}

	## Live state of the three rows.
	func refresh() -> void:
		var p: Dictionary = Save.profile
		var midnight := Fmt.until(Rewards.sec_to_midnight())
		var d := Rewards.daily_state(p)
		if d.claimable:
			_show_row(_rows.daily, "Day %d reward is ready" % int(d.day), "Claim", "honey")
		else:
			_show_row(_rows.daily, "Next reward in %s" % midnight, "View", "white")
		if Rewards.can_spin(p):
			_show_row(_rows.spin, "Win up to %s coins" % Fmt.coins_full(Rewards.PRIZES.max()), "Spin", "honey")
		else:
			_show_row(_rows.spin, "Next spin in %s" % midnight, "View", "white")
		var left := Rewards.free_left_sec(p)
		if left <= 0:
			_show_row(_rows.free, "%s coins, ready now" % Fmt.gain(Rewards.FREE_AMOUNT), "Claim", "honey")
		else:
			_show_row(_rows.free, "Next %s in %s" % [Fmt.gain(Rewards.FREE_AMOUNT), Fmt.clock(left)], "Claim", "off", true)

	func _show_row(row: Dictionary, status: String, label: String, kind: String, disabled := false) -> void:
		(row.status as Label).text = status
		var b: Button = row.button
		b.text = label
		b.disabled = disabled
		if b.get_meta("kit_kind", "") != kind:
			UIKit.set_kind(b, kind)

	## Open the reward's own sheet (Main._on_tab); without Main (previews) open it here.
	func _go(key: String) -> void:
		if _closing:
			return
		var main := get_tree().root.get_node_or_null("Main")
		if main and main.has_method("_on_tab"):
			main.call("_on_tab", key)
		elif key == "free":
			var n := Rewards.claim_free(Save.profile)
			if n > 0:
				Sound.sfx("coin", n)
				Toast.show(self, "%s coins" % Fmt.gain(n), card, 1.8, "coin")
		else:
			var path := "res://scripts/ui/sheets/%s_sheet.gd" % key
			if ResourceLoader.exists(path) and get_parent():
				var s: Sheet = load(path).new()
				s.open(get_parent())
		refresh.call_deferred()


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
