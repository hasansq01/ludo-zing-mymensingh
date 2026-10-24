extends "res://tests/test_suite.gd"
## Snakes & Ladders scene purchases (SLScenes.buy_scene / equip_scene, index.html buyScene / useScene): Jungle free and
## always owned (even on an old save without `scenes` / `scene`), buying with and without enough coins, no double
## charge, buy without equipping, equipping owned / not owned / unknown scenes, and the rollback when the save fails.
## Every check runs on its own profile Dictionary (Catalog.profile_source): the real save is never read or written.

var writes := 0

func fresh(coins := 30000) -> Dictionary:
	return {coins = coins, rooms = ["night", "cafe"], room = "night", stats = {coinsEarned = 0}}

func use(p: Dictionary, fail := false) -> Dictionary:
	Catalog.profile_source = p
	writes = 0
	Catalog.writer = func(_prof: Dictionary) -> bool:
		writes += 1
		return not fail
	return p

func run() -> void:
	var keep_src: Variant = Catalog.profile_source
	var keep_writer: Callable = Catalog.writer
	_run()
	Catalog.profile_source = keep_src
	Catalog.writer = keep_writer

func _run() -> void:
	var p: Dictionary
	var err: String

	# ---- catalogue ----
	check("the six web scenes in shop order", SLScenes.LIST.map(func(s): return s.id) == ["jungle", "frost", "candy", "desert", "cloud", "enchanted"])
	check("scene prices match the web", SLScenes.LIST.map(func(s): return s.price) == [0, 20000, 22000, 25000, 25000, 25000])
	check("every scene has a world config", SLScenes.LIST.all(func(s): return SLScenes.SCENES.has(s.id)))
	check("every scene has a card gradient", SLScenes.LIST.all(func(s): return (s.g as Array).size() == 2))
	check("info(unknown) is empty", SLScenes.info("volcano").is_empty())

	# ---- an old save without the fields ----
	p = use(fresh(0))
	check("Jungle owned without a scenes list", SLScenes.owns_scene("jungle") and SLScenes.owned_ids() == ["jungle"])
	check("scene in use falls back to Jungle", SLScenes.scene_in_use() == "jungle")
	check("paid scenes not owned by default", not SLScenes.owns_scene("frost") and not SLScenes.owns_scene("enchanted"))
	check("owned scenes lists Jungle", SLScenes.owned_scenes().map(func(s): return s.id) == ["jungle"])
	err = SLScenes.buy_scene("jungle")
	check("Jungle can't be bought (already owned)", err != "" and p.coins == 0 and writes == 0, err)
	check("equipping Jungle works with no coins and adds the fields", SLScenes.equip_scene("jungle") and p.scene == "jungle" and p.scenes == ["jungle"] and writes == 1, p)

	# ---- buy with enough coins ----
	p = use(fresh(30000))
	err = SLScenes.buy_scene("frost")
	check("buy a scene: success", err == "", err)
	check("buy a scene: price taken once", p.coins == 10000, p.coins)
	check("buy a scene: owned (Jungle kept) and in use", p.scenes == ["jungle", "frost"] and p.scene == "frost" and SLScenes.scene_in_use() == "frost", p)
	check("buy a scene: saved once", writes == 1, writes)
	check("buying does not count as coins earned", p.stats.coinsEarned == 0)
	p = use(fresh(25000))
	err = SLScenes.buy_scene("desert", false)
	check("buy without equipping keeps Jungle in use", err == "" and p.coins == 0 and (p.scenes as Array).has("desert") and SLScenes.scene_in_use() == "jungle", p)

	# ---- not enough coins ----
	p = use(fresh(21999))
	err = SLScenes.buy_scene("candy")
	check("not enough coins names the shortfall", err == "Not enough coins — you need 1 more.", err)
	check("not enough coins spends nothing", p.coins == 21999 and not p.has("scenes") and writes == 0, p)

	# ---- double buy ----
	p = use(fresh(60000))
	SLScenes.buy_scene("cloud")
	err = SLScenes.buy_scene("cloud")
	check("scene bought twice: second refused, charged once", err != "" and p.coins == 35000 and (p.scenes as Array).count("cloud") == 1 and writes == 1, [err, p])

	# ---- equip ----
	p = use(fresh(0))
	p.scenes = ["jungle", "enchanted"]
	p.scene = "jungle"
	check("equip an owned scene", SLScenes.equip_scene("enchanted") and p.scene == "enchanted" and writes == 1)
	check("equip the scene in use: true, no write", SLScenes.equip_scene("enchanted") and writes == 1)
	check("equip a scene not owned is refused", not SLScenes.equip_scene("candy") and p.scene == "enchanted")
	check("equip an unknown scene is refused", not SLScenes.equip_scene("volcano") and not SLScenes.equip_scene(""))
	check("unknown scene can't be bought", SLScenes.buy_scene("volcano") != "" and writes == 1)
	p.scenes.append("volcano")
	check("a stray unknown id in the save isn't owned", not SLScenes.owns_scene("volcano") and not SLScenes.owned_ids().has("volcano"))
	p.scene = "candy"
	check("an equipped scene that isn't owned falls back to Jungle", SLScenes.scene_in_use() == "jungle")

	# ---- the save fails: everything rolls back ----
	p = use(fresh(30000), true)
	err = SLScenes.buy_scene("frost")
	check("failed save: buy reports it", err == Catalog.SAVE_FAILED, err)
	check("failed save: no coins spent, nothing owned or equipped", p.coins == 30000 and not p.has("scenes") and not p.has("scene"), p)
	p.scenes = ["jungle", "frost"]
	check("failed save: equip returns false and keeps the old scene", not SLScenes.equip_scene("frost") and not p.has("scene"))
