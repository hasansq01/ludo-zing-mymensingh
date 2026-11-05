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
	check("the web scenes in shop order", SLScenes.LIST.map(func(s): return s.id) == ["jungle", "trail", "frost", "candy", "desert", "cloud", "enchanted"])
	check("scene prices (Enchanted Jungle free since 2026-10-30, Snake Trail free)", SLScenes.LIST.map(func(s): return s.price) == [0, 0, 20000, 22000, 25000, 25000, 0])
	_check_trail()
	check("every scene has a world config", SLScenes.LIST.all(func(s): return SLScenes.SCENES.has(s.id)))
	check("every scene has a card gradient", SLScenes.LIST.all(func(s): return (s.g as Array).size() == 2))
	check("info(unknown) is empty", SLScenes.info("volcano").is_empty())

	# ---- an old save without the fields ----
	p = use(fresh(0))
	check("Jungle owned without a scenes list", SLScenes.owns_scene("jungle") and SLScenes.owned_ids() == ["jungle"])
	check("scene in use falls back to Jungle", SLScenes.scene_in_use() == "jungle")
	check("paid scenes not owned by default", not SLScenes.owns_scene("frost") and not SLScenes.owns_scene("cloud"))
	check("free scenes owned by everyone", SLScenes.owns_scene("jungle") and SLScenes.owns_scene("trail") and SLScenes.owns_scene("enchanted"))
	check("owned scenes lists the free ones", SLScenes.owned_scenes().map(func(s): return s.id) == ["jungle", "trail", "enchanted"])
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

## Snake Trail: one winding road of 100 tiles on the board's face, its own snakes and ladders between neighbouring loops.
func _check_trail() -> void:
	check("only Snake Trail has its own squares", SLScenes.LIST.all(func(s): return SLScenes.layout_of(s.id) == ("trail" if s.id == "trail" else "")))
	check("an unknown scene is on the grid", SLScenes.layout_of("nope") == "")
	var cells := []
	var inside := true
	var even := true
	for n in range(1, 101):
		var c := SLBoard.grid_of(n, "trail")
		cells.append(c)
		inside = inside and c.x > 0.5 and c.x < 9.5 and c.y > 0.5 and c.y < 9.7
		if n > 1:
			even = even and absf(c.distance_to(cells[n - 2]) - SLTrail.pitch()) < 0.08
	check("100 squares, all on the face", cells.size() == 100 and inside)
	check("each square a tile's length from the last", even)
	var apart := true
	for i in 100:
		for j in range(i + 1, 100):
			apart = apart and (cells[i] as Vector2).distance_to(cells[j]) > 0.6
	check("no two squares overlap (a pawn stands on one)", apart)
	check("square 1 is at the bottom left, 100 at the top", cells[0].x < 2.5 and cells[0].y > 8.5 and cells[99].y < 1.5)
	check("the grid is unchanged by the default", SLBoard.grid_of(1) == Vector2(0.5, 9.5) and SLBoard.grid_of(100) == Vector2(0.5, 0.5))
	var ladders := SnakesLaddersRules.TRAIL_LADDERS
	var snakes := SnakesLaddersRules.TRAIL_SNAKES
	var near := true
	for f in ladders:
		near = near and SLBoard.grid_of(f, "trail").distance_to(SLBoard.grid_of(ladders[f], "trail")) < 2.0
	check("each ladder joins neighbouring loops", near)
	var lengths := true
	for h in snakes:
		var body := SLBoard.snake_body(h, 32, "trail")
		lengths = lengths and body[0].is_equal_approx(SLBoard.grid_of(h, "trail")) and body[32].is_equal_approx(SLBoard.grid_of(snakes[h], "trail"))
	check("a snake's body runs from its head's square to its tail's", lengths)
	check("the classic bodies are still there beside them", SLBoard.snake_body(16, 32).size() == 33 and SLBoard.snake_body(16, 32)[0].is_equal_approx(SLBoard.grid_of(16) + SLBoard.HEAD_NUDGE))
	var b := SLBoard.new()
	check("a new board is on the grid", b.layout == "" and b.cell_world(1) == SLBoard.grid_to_world(SLBoard.grid_of(1)))
	b.layout = "trail"
	check("on the trail, pawns stand on its tiles", b.cell_world(1) == SLBoard.grid_to_world(SLBoard.grid_of(1, "trail")))
	b.use_layout("")
	check("use_layout: a match can put the board back on the grid", b.layout == "" and b.cell_world(50) == SLBoard.grid_to_world(SLBoard.grid_of(50)))
	b.free()

