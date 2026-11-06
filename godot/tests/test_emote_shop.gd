extends "res://tests/test_suite.gd"
## Emote packs in the economy and the Shop: the catalogue, the profile keys and their repair, Catalog buy / equip,
## the Emotes helper, the Emotes tab's card states and the View sheet, and buying through a fake server.
## Save is swapped for a throwaway profile (and its write cut): user://save.json is never touched.

const Fake := preload("res://tests/fake_accounts.gd")

var _sp: Dictionary
var _spf: Dictionary
var _root: Node
var writes := 0

func run() -> void:
	_root = (Engine.get_main_loop() as SceneTree).root
	var keep_src: Variant = Catalog.profile_source
	var keep_writer: Callable = Catalog.writer
	_catalog()
	_save_repair()
	_helper()
	_sandbox()
	_shop_ui()
	_wallet()
	_restore()
	Catalog.profile_source = keep_src
	Catalog.writer = keep_writer

func fresh(coins := 5000) -> Dictionary:
	return {coins = coins, rooms = ["night", "cafe"], room = "night", dice_owned = ["classic"], dice = "classic",
		emote_sets = ["starter"], emote_set = "starter", stats = {coinsEarned = 0}}

func use(p: Dictionary, fail := false) -> Dictionary:
	Catalog.profile_source = p
	writes = 0
	Catalog.writer = func(_prof: Dictionary) -> bool:
		writes += 1
		return not fail
	return p

func _catalog() -> void:
	check("emotes: five packs in the contract's order", Catalog.EMOTE_PACKS.map(func(e): return e.id) == ["starter", "friends", "boys", "pawns", "game"])
	check("emotes: pack prices", Catalog.EMOTE_PACKS.map(func(e): return e.price) == [0, 2500, 2500, 5000, 5000])
	check("emotes: 6 per set, 8 per Premium pack, 34 in all", Catalog.EMOTE_PACKS.all(func(e): return e.emotes.size() == (8 if e.get("premium", false) else 6)) and Catalog.EMOTE_PACKS.reduce(func(a, e): return a + e.emotes.size(), 0) == 34)
	var m: Array = EmoteArt.manifest().get("sets", [])
	check("emotes: the catalogue matches the art manifest", m.size() == 5 and m.all(func(s): return Catalog.emote_pack(s.id).emotes == s.emotes and int(Catalog.emote_pack(s.id).price) == int(s.price)))
	var p := use({coins = 0})
	check("emotes: Starter owned and in use even without the keys", Catalog.owns_emotes("starter") and Catalog.emotes_in_use() == "starter")
	check("emotes: paid packs not owned; unknown never", not Catalog.owns_emotes("pawns") and not Catalog.owns_emotes("nope"))
	p = use(fresh(5000))
	var err := Catalog.buy_emotes("pawns")
	check("emotes: buy pays once, owns and equips", err == "" and p.coins == 0 and p.emote_sets == ["starter", "pawns"] and p.emote_set == "pawns" and writes == 1, [err, p])
	err = Catalog.buy_emotes("pawns")
	check("emotes: no second charge", err.begins_with("You already own") and p.coins == 0 and writes == 1, err)
	err = Catalog.buy_emotes("friends")
	check("emotes: too poor: the need-more line, nothing changes", err.begins_with("Not enough coins") and p.coins == 0 and not (p.emote_sets as Array).has("friends"), err)
	check("emotes: Starter is free (already owned)", Catalog.buy_emotes("starter").begins_with("You already own"))
	check("emotes: unknown id refused", Catalog.buy_emotes("nope").contains("n’t in the"))
	check("emotes: equip an owned pack, and an unowned one is refused", Catalog.equip_emotes("starter") and p.emote_set == "starter" and not Catalog.equip_emotes("game") and p.emote_set == "starter")
	check("emotes: owned_emote_packs lists Starter then Pawns", Catalog.owned_emote_packs().map(func(e): return e.id) == ["starter", "pawns"])
	p = use(fresh(9000), true)
	err = Catalog.buy_emotes("friends")
	check("emotes: a failed save rolls everything back", err == Catalog.SAVE_FAILED and p.coins == 9000 and p.emote_sets == ["starter"] and p.emote_set == "starter", p)

	_text_catalog()

func _text_catalog() -> void:
	check("text: four packs, Good Manners free", Catalog.TEXT_PACKS.map(func(e): return e.id) == ["basic", "ludo", "react", "bangla"] and Catalog.TEXT_PACKS.map(func(e): return e.price) == [0, 3000, 3000, 3000])
	var m: Array = EmoteArt.manifest().get("text_packs", [])
	check("text: the catalogue matches the art manifest", m.size() == 4 and m.all(func(s): return Catalog.text_pack(s.id).emotes == s.emotes and int(Catalog.text_pack(s.id).price) == int(s.price)))
	check("text: the team phrases match the art manifest", EmoteArt.manifest().team == Catalog.TEAM_PHRASES)
	var p := use({coins = 0})
	check("text: Good Manners owned and in use even without the keys", Catalog.owns_text("basic") and Catalog.text_in_use() == "basic")
	check("text: paid packs not owned; unknown never", not Catalog.owns_text("ludo") and not Catalog.owns_text("nope"))
	p = use(fresh(4000))
	var err := Catalog.buy_text("bangla")
	check("text: buy pays once, owns and equips, the sticker packs untouched", err == "" and p.coins == 1000 and p.text_packs == ["basic", "bangla"] and p.text_pack == "bangla" and p.emote_sets == ["starter"] and writes == 1, [err, p])
	check("text: no second charge", Catalog.buy_text("bangla").begins_with("You already own") and p.coins == 1000)
	check("text: too poor: nothing changes", Catalog.buy_text("ludo").begins_with("Not enough coins") and p.coins == 1000)
	check("text: unknown refused", Catalog.buy_text("nope").contains("n’t in the"))
	check("text: equip an owned pack, an unowned one is refused", Catalog.equip_text("basic") and p.text_pack == "basic" and not Catalog.equip_text("ludo") and p.text_pack == "basic")
	check("text: the Text tab holds the equipped pack", Emotes.equipped_text_ids()[0] == "t-hi" and Emotes.equipped_text_ids().size() == 8)
	check("text: Pair Mode adds the team phrases", Emotes.equipped_text_ids(true).size() == 12 and Emotes.equipped_text_ids(true).back() == "t-partner")

func _save_repair() -> void:
	var s: Node = preload("res://scripts/core/save.gd").new()
	s.profile = {}
	s.prefs = {}
	s._ensure()
	check("emotes: a new profile owns and uses Starter", s.profile.emote_sets == ["starter"] and s.profile.emote_set == "starter")
	check("text: a new profile owns and uses Good Manners", s.profile.text_packs == ["basic"] and s.profile.text_pack == "basic")
	s.profile = {emote_sets = "x", emote_set = 4, text_packs = "x", text_pack = 4}
	s._ensure()
	check("text: damaged keys are repaired", s.profile.text_packs == ["basic"] and s.profile.text_pack == "basic", s.profile)
	check("emotes: damaged keys are repaired", s.profile.emote_sets == ["starter"] and s.profile.emote_set == "starter", s.profile)
	s.profile = {emote_sets = ["game", "pawns"], emote_set = "friends"}
	s._ensure()
	check("emotes: Starter is added first; an unowned equipped pack falls back", s.profile.emote_sets == ["starter", "game", "pawns"] and s.profile.emote_set == "starter", s.profile)
	s.profile = {emote_sets = ["starter", "game"], emote_set = "game"}
	s._ensure()
	check("emotes: owned choices are kept", s.profile.emote_set == "game" and s.profile.emote_sets == ["starter", "game"])
	s.free()

func _helper() -> void:
	var p := use(fresh())
	check("Emotes.packs: manifest order and names", Emotes.packs().map(func(e): return e.id) == ["starter", "friends", "boys", "pawns", "game"] and Emotes.packs()[1].name == "Girl Set" and Emotes.packs()[3].premium and not Emotes.packs()[1].premium)
	check("Emotes.pack / pack_of", Emotes.pack("friends").emotes[0] == "cheer" and Emotes.pack_of("t-six") == "ludo" and Emotes.pack_of("t-go") == "team" and Emotes.pack_of("dice") == "game" and Emotes.pack_of("zzz") == "" and Emotes.pack("zzz").is_empty())
	check("Emotes: starter equipped by default", Emotes.equipped_pack() == "starter" and ",".join(Emotes.equipped_ids()) == "happy,laugh,sob,angry,gasp,love")
	check("Emotes.owns_emote: starter yes, paid no", Emotes.owns_emote("happy") and not Emotes.owns_emote("champ") and not Emotes.owns_emote("nope") and Emotes.owns_emote("t-hi") and Emotes.owns_emote("t-go") and not Emotes.owns_emote("t-six"))
	p.emote_sets = ["starter", "pawns"]
	p.emote_set = "pawns"
	check("Emotes: owned packs and the equipped six follow the profile", Emotes.owned_packs() == ["starter", "pawns"] and Emotes.equipped_ids()[0] == "party" and Emotes.owns_emote("cool") and not Emotes.owns_emote("cry"))
	p.emote_set = "game"
	check("Emotes: an unowned saved pack reads as Starter", Emotes.equipped_pack() == "starter")

func _sandbox() -> void:
	_sp = Save.profile
	_spf = Save.prefs
	Save.profile = Fake.base_profile()
	Save.profile.emote_sets = ["starter"]
	Save.profile.emote_set = "starter"
	Save.prefs = {}
	Save.normalize()
	Catalog.profile_source = null
	Catalog.writer = func(_p: Dictionary) -> bool: return true
	if Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)

func _restore() -> void:
	Save._dirty = false
	Save.profile = _sp
	Save.prefs = _spf
	if not Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.connect(Save.flush)

func _card(shop: ShopSheet, id: String) -> Control:
	for c in shop._cards:
		if c.get_meta("item", "") == id:
			return c
	return null

func _vis(n: Node, name_: String) -> bool:
	var x := n.find_child(name_, true, false) as CanvasItem
	return x != null and x.visible

func _shop_ui() -> void:
	Save.profile.coins = 3000
	var shop := ShopSheet.new("emotes")
	_root.add_child(shop)
	check("shop: four tabs, each with its filter", ShopSheet.TABS.map(func(t): return t.key) == ["boards", "pieces", "emotes", "look"] and ShopSheet.SUBS.boards.size() == 2 and ShopSheet.SUBS.look.size() == 4)
	check("shop: each category sits under its tab", ShopSheet.strip_key("scenes") == "boards" and ShopSheet.strip_key("dice") == "pieces" and ShopSheet.strip_key("text") == "emotes" and ShopSheet.strip_key("badges") == "look")
	check("shop: old names still open the right place", ShopSheet._norm_tab("characters") == "avatars" and ShopSheet._norm_tab("coins") == "rooms" and ShopSheet._norm_tab("nope") == "rooms")
	shop.show_tab("frames")
	check("shop: Frames open under the Look tab with its filter", shop.tab == "frames" and shop._sub_of == "look" and shop._sub.get_child_count() >= 4)
	shop.show_tab("pieces")
	check("shop: picking a tab opens its first category", shop.tab == "pawns" and shop._sub_of == "pieces")
	shop.show_tab("dice")
	shop.show_tab("look")
	shop.show_tab("pieces")
	check("shop: a tab comes back to the category shown last", shop.tab == "dice")
	shop.show_tab("emotes")
	shop.show_tab("emotes")
	check("shop: Stickers list the five packs", shop.tab == "emotes" and shop._cards.size() == 5 and _card(shop, "pawns") != null)
	check("shop: a card previews its icons, Premium tagged", _card(shop, "friends").find_child("Icons", true, false).get_child_count() == 6 and _card(shop, "pawns").find_child("Icons", true, false).get_child_count() == 8)
	var st := _card(shop, "starter")
	check("shop: Starter shows In use (free, equipped)", _vis(st, "InUse") and not _vis(st, "Price") and not _vis(st, "Use"))
	var pw := _card(shop, "friends")
	check("shop: Girl Set for sale: its price, no Buy button on the card", _vis(pw, "Price") and pw.find_child("Buy", true, false) == null and pw.find_child("GemBuy", true, false) == null)
	check("shop: every emote card opens a preview", _vis(pw, "View"))
	check("shop: what's in use comes first, then for sale from the cheapest", shop._cards[0].get_meta("item") == "starter" and shop._cards[1].get_meta("item") == "friends" and shop._cards[3].get_meta("item") == "pawns", shop._cards.map(func(c): return c.get_meta("item")))
	shop.show_tab("text")
	check("shop: Text lists the four text packs", shop._cards.size() == 4 and _card(shop, "bangla") != null)
	shop.show_tab("dice")
	check("shop: square art in three columns, wide art in two", shop.scroll_body.get_child(0).columns == 3)
	shop.show_tab("rooms")
	check("shop: ...rooms in two", shop.scroll_body.get_child(0).columns == 2)
	shop.show_tab("emotes")
	shop.show_tab("emotes")
	st = _card(shop, "starter")
	pw = _card(shop, "friends")
	# owned, not in use -> Use ; owned and in use -> In use
	Save.profile.emote_sets = ["starter", "friends"]
	shop.refresh()
	check("shop: an owned pack shows Use", _vis(pw, "Use") and not _vis(pw, "Price") and not _vis(pw, "InUse"))
	var ok: bool = Catalog.equip_emotes("friends")
	shop.refresh()
	check("shop: once equipped it shows In use and Starter shows Use", ok and _vis(pw, "InUse") and _vis(st, "Use") and not _vis(st, "InUse"))
	shop.set_owned_only(true)
	check("shop: owned only lists the Pawn Set and the Girl Set among the stickers", shop._cards.size() == 2)
	shop.free()
	var inv := ShopSheet.new("emotes", 400.0, true, true)
	_root.add_child(inv)
	check("inventory: Emotes lists the owned packs, Text its own", inv._cards.size() == 2)
	inv.show_tab("text")
	check("inventory: Text lists Good Manners", inv._cards.size() == 1)
	inv.free()
	# the buy screen of what has no live preview
	var item := ItemSheet.new("dice", "gold")
	_root.add_child(item)
	check("item sheet: a die for sale offers coins or gems; too dear says what's missing", item._gem != null and (item._buy.visible or item._need.visible) and not item._use.visible)
	item.free()
	Save.profile.dice_owned = ["classic", "crema"]
	Save.profile.dice = "classic"
	var mine := ItemSheet.new("dice", "crema")
	_root.add_child(mine)
	check("item sheet: an owned die offers Use", mine._use.visible and not mine._buy.visible and not mine._gem.visible)
	await mine._on_act()
	check("item sheet: Use puts it in use", Save.profile.dice == "crema" and mine._on_pill.visible)
	mine.free()
	Save.profile.dice = "classic"
	Save.profile.dice_owned = ["classic"]
	# View sheet
	Save.profile.emote_sets = ["starter"]
	Save.profile.emote_set = "starter"
	var v := EmotePackSheet.new("pawns")
	_root.add_child(v)
	check("view: its eight emotes", v._cells.size() == 8 and v._cells[0].emote_id == "party")
	check("view: too dear: Need, no Buy", v._need.visible and not v._buy.visible and not v._use.visible and v._need.text.begins_with("Need"))
	Save.profile.coins = 9000
	v.refresh()
	check("view: affordable: Buy", v._buy.visible and not v._need.visible)
	Save.profile.emote_sets = ["starter", "pawns"]
	v.refresh()
	check("view: owned: Use", v._use.visible and not v._buy.visible)
	Save.profile.emote_set = "pawns"
	v.refresh()
	check("view: equipped: In use pill", v._on_pill.visible and not v._use.visible)
	var seam: EmotePackSheet.EmoteCell = null
	var plain: EmotePackSheet.EmoteCell = null
	var v2 := EmotePackSheet.new("starter")
	_root.add_child(v2)
	for c in v2._cells:
		if c.emote_id == "happy":
			seam = c
		if c.emote_id == "laugh":
			plain = c
	var d := plain.play_sec()
	var vt := EmotePackSheet.new("bangla", "text")
	_root.add_child(vt)
	check("view: a text pack shows its 8 phrases, no name under them, Buy", vt._cells.size() == 8 and vt._cells[0].emote_id == "t-bgg" and not vt._cells[0].find_child("Name", true, false).visible and vt._buy.visible and not vt._use.visible)
	Save.profile.text_packs = ["basic", "bangla"]
	vt.refresh()
	check("view: an owned text pack: Use", vt._use.visible and not vt._buy.visible)
	Save.profile.text_pack = "bangla"
	vt.refresh()
	check("view: the equipped text pack: In use", vt._on_pill.visible and not vt._use.visible)
	Save.profile.text_packs = ["basic"]
	Save.profile.text_pack = "basic"
	vt.free()
	check("view: a non-seamless emote plays through, holds on the last frame, then replays", d > 2.0 and plain.frame_at(0.0) == 0 and plain.frame_at(d + 0.3) == 35 and plain.frame_at(d + EmotePackSheet.PAUSE_SEC + 0.05) < 3, [d, plain.frame_at(d + 0.3)])
	check("view: a seamless emote just loops", seam.frame_at(seam.play_sec() + 0.01) < 2)
	v.free()
	v2.free()

func _wallet() -> void:
	var f := Fake.new()
	f.profile.coins = 5000
	Save.profile.coins = 5000                 # (a guest sign-in imports the local profile's coins)
	var a := Account.new()
	a.url_base = "ws://fake"
	a.http_fn = f.http
	_root.add_child(a)
	a.persist = Callable()
	await a.sign_in_guest()
	var shop := ShopSheet.new("emotes")
	_root.add_child(shop)
	var err: String = await shop._purchase("emotes", "pawns")
	check("wallet: an emote pack is bought through the server", err == "" and Save.profile.coins == 0 and Save.profile.emote_sets.has("pawns") and Save.profile.emote_set == "pawns" and f.count("/v1/shop/buy") == 1, [err, Save.profile])
	check("wallet: the body says kind emotes", f.last("/v1/shop/buy").body == {kind = "emotes", id = "pawns", currency = "coins", catalog = 2}, f.last("/v1/shop/buy"))
	f.profile.coins = 3000
	await a.refresh_me()
	var terr: String = await shop._purchase("text", "ludo")
	check("wallet: a text pack is bought through the server", terr == "" and Save.profile.text_packs.has("ludo") and Save.profile.text_pack == "ludo" and f.last("/v1/shop/buy").body == {kind = "text", id = "ludo", currency = "coins", catalog = 2}, [terr, f.last("/v1/shop/buy")])
	await shop._on_use("text", "basic")
	check("wallet: Use equips a text pack through the server", Save.profile.text_pack == "basic" and f.last("/v1/shop/equip").body == {kind = "text", id = "basic"}, Save.profile)
	await shop._on_use("emotes", "starter")
	check("wallet: Use equips through the server", Save.profile.emote_set == "starter" and f.last("/v1/shop/equip").body == {kind = "emotes", id = "starter"}, Save.profile)
	f.profile.coins = 100
	err = await shop._purchase("emotes", "friends")
	check("wallet: too poor: need-more-coins line", err.begins_with("Not enough coins"), err)
	f.online = false
	a._session = ""
	err = await shop._purchase("emotes", "game")
	check("wallet: offline: Connect to the internet to buy", err == "Connect to the internet to buy.", err)
	check("wallet: offline: nothing granted", not Save.profile.emote_sets.has("game"))
	shop.free()
	_root.remove_child(a)
	Account.set_instance(null)
	a.free()
