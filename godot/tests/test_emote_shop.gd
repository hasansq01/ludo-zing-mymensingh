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
	check("emotes: four packs in the contract's order", Catalog.EMOTE_PACKS.map(func(e): return e.id) == ["starter", "pawns", "friends", "game"])
	check("emotes: pack prices", Catalog.EMOTE_PACKS.map(func(e): return e.price) == [0, 2500, 4000, 3500])
	check("emotes: six per pack, 24 unique", Catalog.EMOTE_PACKS.all(func(e): return e.emotes.size() == 6) and Catalog.EMOTE_PACKS.reduce(func(a, e): return a + e.emotes.size(), 0) == 24)
	var m: Array = EmoteArt.manifest().get("sets", [])
	check("emotes: the catalogue matches the art manifest", m.size() == 4 and m.all(func(s): return Catalog.emote_pack(s.id).emotes == s.emotes and int(Catalog.emote_pack(s.id).price) == int(s.price)))
	var p := use({coins = 0})
	check("emotes: Starter owned and in use even without the keys", Catalog.owns_emotes("starter") and Catalog.emotes_in_use() == "starter")
	check("emotes: paid packs not owned; unknown never", not Catalog.owns_emotes("pawns") and not Catalog.owns_emotes("nope"))
	p = use(fresh(5000))
	var err := Catalog.buy_emotes("pawns")
	check("emotes: buy pays once, owns and equips", err == "" and p.coins == 2500 and p.emote_sets == ["starter", "pawns"] and p.emote_set == "pawns" and writes == 1, [err, p])
	err = Catalog.buy_emotes("pawns")
	check("emotes: no second charge", err.begins_with("You already own") and p.coins == 2500 and writes == 1, err)
	err = Catalog.buy_emotes("friends")
	check("emotes: too poor: the need-more line, nothing changes", err.begins_with("Not enough coins") and p.coins == 2500 and not (p.emote_sets as Array).has("friends"), err)
	check("emotes: Starter is free (already owned)", Catalog.buy_emotes("starter").begins_with("You already own"))
	check("emotes: unknown id refused", Catalog.buy_emotes("nope").contains("n’t in the"))
	check("emotes: equip an owned pack, and an unowned one is refused", Catalog.equip_emotes("starter") and p.emote_set == "starter" and not Catalog.equip_emotes("game") and p.emote_set == "starter")
	check("emotes: owned_emote_packs lists Starter then Pawns", Catalog.owned_emote_packs().map(func(e): return e.id) == ["starter", "pawns"])
	p = use(fresh(9000), true)
	err = Catalog.buy_emotes("friends")
	check("emotes: a failed save rolls everything back", err == Catalog.SAVE_FAILED and p.coins == 9000 and p.emote_sets == ["starter"] and p.emote_set == "starter", p)

func _save_repair() -> void:
	var s: Node = preload("res://scripts/core/save.gd").new()
	s.profile = {}
	s.prefs = {}
	s._ensure()
	check("emotes: a new profile owns and uses Starter", s.profile.emote_sets == ["starter"] and s.profile.emote_set == "starter")
	s.profile = {emote_sets = "x", emote_set = 4}
	s._ensure()
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
	check("Emotes.packs: manifest order and names", Emotes.packs().map(func(e): return e.id) == ["starter", "pawns", "friends", "game"] and Emotes.packs()[1].name == "Pawn Pals")
	check("Emotes.pack / pack_of", Emotes.pack("friends").emotes[0] == "cry" and Emotes.pack_of("dice") == "game" and Emotes.pack_of("zzz") == "" and Emotes.pack("zzz").is_empty())
	check("Emotes: starter equipped by default", Emotes.equipped_pack() == "starter" and ",".join(Emotes.equipped_ids()) == "happy,laugh,cool,angry,love,party")
	check("Emotes.owns_emote: starter yes, paid no", Emotes.owns_emote("happy") and not Emotes.owns_emote("champ") and not Emotes.owns_emote("nope"))
	p.emote_sets = ["starter", "pawns"]
	p.emote_set = "pawns"
	check("Emotes: owned packs and the equipped six follow the profile", Emotes.owned_packs() == ["starter", "pawns"] and Emotes.equipped_ids()[0] == "champ" and Emotes.owns_emote("champ") and not Emotes.owns_emote("cry"))
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
	check("shop: an Emotes tab, between Pawns and Look", ShopSheet.TABS.map(func(t): return t.key).slice(2, 6) == ["dice", "pawns", "emotes", "look"])
	shop.show_tab("frames")
	check("shop: Frames sit under the Look tab (its Avatars | Frames | Plates | Badges filter shows)", shop.tab == "frames" and shop._look.get_parent().visible and ShopSheet.strip_key("badges") == "look")
	shop.show_tab("emotes")
	check("shop: the Look filter hides on the other tabs", not shop._look.get_parent().visible)
	check("shop: Emotes lists the four packs", shop._cards.size() == 4 and _card(shop, "pawns") != null)
	check("shop: a card previews six icons", _card(shop, "pawns").find_child("Icons", true, false).get_child_count() == 6)
	var st := _card(shop, "starter")
	check("shop: Starter shows In use (free, equipped)", _vis(st, "InUse") and not _vis(st, "Buy") and not _vis(st, "Use"))
	var pw := _card(shop, "pawns")
	check("shop: Pawn Pals for sale: Buy, with its price chip on the art", _vis(pw, "Buy") and (pw.find_child("Buy", true, false) as Button).text == "Buy" and (pw.find_child("Price", true, false) as Control).visible, (pw.find_child("Buy", true, false) as Button).text)
	var fr := _card(shop, "friends")
	check("shop: Friends Set too dear: the Need line", _vis(fr, "Buy") and (fr.find_child("Buy", true, false) as Button).text.begins_with("Need"), (fr.find_child("Buy", true, false) as Button).text)
	check("shop: every emote card has a View chip", _vis(pw, "View"))
	# owned, not in use -> Use ; owned and in use -> In use
	Save.profile.emote_sets = ["starter", "pawns"]
	shop.refresh()
	check("shop: an owned pack shows Use", _vis(pw, "Use") and not _vis(pw, "Buy") and not _vis(pw, "InUse"))
	var ok: bool = Catalog.equip_emotes("pawns")
	shop.refresh()
	check("shop: once equipped it shows In use and Starter shows Use", ok and _vis(pw, "InUse") and _vis(st, "Use") and not _vis(st, "InUse"))
	shop.set_owned_only(true)
	check("shop: Owned filter lists Starter and Pawn Pals only", shop._cards.size() == 2)
	shop.free()
	var inv := ShopSheet.new("emotes", 400.0, true, true)
	_root.add_child(inv)
	check("inventory: Emotes tab lists the owned packs", inv._cards.size() == 2)
	inv.free()
	# View sheet
	Save.profile.emote_sets = ["starter"]
	Save.profile.emote_set = "starter"
	var v := EmotePackSheet.new("friends")
	_root.add_child(v)
	check("view: six emotes", v._cells.size() == 6 and v._cells[0].emote_id == "cry")
	check("view: too dear: Need, no Buy", v._need.visible and not v._buy.visible and not v._use.visible and v._need.text.begins_with("Need"))
	Save.profile.coins = 9000
	v.refresh()
	check("view: affordable: Buy", v._buy.visible and not v._need.visible)
	Save.profile.emote_sets = ["starter", "friends"]
	v.refresh()
	check("view: owned: Use", v._use.visible and not v._buy.visible)
	Save.profile.emote_set = "friends"
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
	check("wallet: an emote pack is bought through the server", err == "" and Save.profile.coins == 2500 and Save.profile.emote_sets.has("pawns") and Save.profile.emote_set == "pawns" and f.count("/v1/shop/buy") == 1, [err, Save.profile])
	check("wallet: the body says kind emotes", f.last("/v1/shop/buy").body == {kind = "emotes", id = "pawns", currency = "coins"}, f.last("/v1/shop/buy"))
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
