extends "res://tests/test_suite.gd"
## Shop and Inventory logic (Catalog): buying with and without enough coins, no double charge, equipping owned and
## not-owned items, free rooms / Classic dice always owned, unknown ids, and the rollback when the save fails.
## Every check runs on its own profile Dictionary (Catalog.profile_source): the real save is never read or written.

var writes := 0

func fresh(coins := 5000) -> Dictionary:
	return {coins = coins, rooms = ["night", "cafe"], room = "night", dice_owned = ["classic"], dice = "classic", stats = {coinsEarned = 0}}

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
	check("every web dice skin is in the catalogue", Catalog.DICE.map(func(d): return d.id) == ["classic", "crema", "espresso", "gold"])
	check("skin prices match the web", Catalog.DICE.map(func(d): return d.price) == [0, 1000, 2500, 6000])
	check("dice(id) finds a skin", Catalog.dice("espresso").name == "Espresso" and Catalog.dice("espresso").bg == Color("#4a2c1a"))
	check("dice(unknown) is empty", Catalog.dice("rainbow").is_empty())
	check("every room has a card gradient", Rooms.LIST.all(func(r): return Catalog.ROOM_GRADIENT.has(r.id)))
	check("short coin amounts like the web", [Catalog.short(950), Catalog.short(1000), Catalog.short(2500), Catalog.short(2550), Catalog.short(1200000)] == ["950", "1K", "2.5K", "2.5K", "1.2M"],
		[Catalog.short(950), Catalog.short(1000), Catalog.short(2500), Catalog.short(2550), Catalog.short(1200000)])
	check("need text", Catalog.need_text(2500) == "Not enough coins — you need 2,500 more.", Catalog.need_text(2500))

	# ---- free things are always owned ----
	p = use({coins = 0})
	check("free rooms owned even when the list is missing", Catalog.owns_room("night") and Catalog.owns_room("cafe"))
	check("Classic dice owned even when the list is missing", Catalog.owns_dice("classic"))
	check("paid rooms are not owned by default", not Catalog.owns_room("dream") and not Catalog.owns_dice("gold"))
	check("owned rooms lists the free ones", Catalog.owned_rooms().map(func(r): return r.id) == ["night", "cafe"])
	check("owned dice lists Classic", Catalog.owned_dice().map(func(d): return d.id) == ["classic"])
	check("room / dice in use fall back to the defaults", Catalog.room_in_use() == "night" and Catalog.dice_in_use() == "classic")
	p = use(fresh(0))
	err = Catalog.buy_room("cafe")
	check("buying a free room is refused (already owned)", err != "" and p.coins == 0 and (p.rooms as Array).count("cafe") == 1 and writes == 0, err)
	check("equipping a free room works with no coins", Catalog.equip_room("cafe") and p.room == "cafe" and writes == 1)

	# ---- buy with enough coins ----
	p = use(fresh(5000))
	err = Catalog.buy_room("dream")
	check("buy a room: success", err == "", err)
	check("buy a room: price taken once", p.coins == 2000, p.coins)
	check("buy a room: owned and in use (Shop buyRoom equips)", (p.rooms as Array).has("dream") and p.room == "dream", p)
	check("buy a room: saved once", writes == 1, writes)
	check("buying does not count as coins earned", p.stats.coinsEarned == 0)
	p = use(fresh(5000))
	err = Catalog.buy_room("studio", false)
	check("buy a room without equipping keeps the room in use", err == "" and p.room == "night" and (p.rooms as Array).has("studio") and p.coins == 1000, p)
	p = use(fresh(2500))
	err = Catalog.buy_dice("espresso")
	check("buy dice with exactly enough coins", err == "" and p.coins == 0 and (p.dice_owned as Array).has("espresso") and p.dice == "espresso", [err, p])
	check("owned dice list keeps the buy order", Catalog.owned_dice().map(func(d): return d.id) == ["classic", "espresso"])

	# ---- not enough coins: nothing spent ----
	p = use(fresh(2999))
	err = Catalog.buy_room("dream")
	check("room: not enough coins is refused", err == "Not enough coins — you need 1 more.", err)
	check("room: not enough coins spends nothing", p.coins == 2999 and not (p.rooms as Array).has("dream") and p.room == "night" and writes == 0, p)
	p = use(fresh(100))
	err = Catalog.buy_dice("gold")
	check("dice: not enough coins names the shortfall", err == "Not enough coins — you need 5,900 more.", err)
	check("dice: not enough coins spends nothing", p.coins == 100 and p.dice_owned == ["classic"] and p.dice == "classic" and writes == 0, p)

	# ---- double buy: no double charge ----
	p = use(fresh(10000))
	Catalog.buy_room("cloud")
	err = Catalog.buy_room("cloud")
	check("room bought twice: second is refused", err != "", err)
	check("room bought twice: charged once", p.coins == 5000 and (p.rooms as Array).count("cloud") == 1 and writes == 1, p)
	p = use(fresh(10000))
	Catalog.buy_dice("crema")
	err = Catalog.buy_dice("crema")
	check("dice bought twice: charged once", err != "" and p.coins == 9000 and (p.dice_owned as Array).count("crema") == 1 and writes == 1, p)
	err = Catalog.buy_dice("classic")
	check("Classic can't be bought", err != "" and p.coins == 9000)

	# ---- equip ----
	p = use(fresh(0))
	p.rooms.append("studio")
	p.dice_owned.append("gold")
	check("equip an owned room", Catalog.equip_room("studio") and p.room == "studio" and writes == 1)
	check("equip the room already in use: true, no write", Catalog.equip_room("studio") and writes == 1)
	check("equip a room not owned is refused", not Catalog.equip_room("cloud") and p.room == "studio")
	check("equip owned dice", Catalog.equip_dice("gold") and p.dice == "gold")
	check("equip dice not owned is refused", not Catalog.equip_dice("espresso") and p.dice == "gold")
	check("equip Classic always works", Catalog.equip_dice("classic") and p.dice == "classic")

	# ---- unknown ids ----
	p = use(fresh(99999))
	check("unknown room can't be bought", Catalog.buy_room("castle") != "" and p.coins == 99999 and writes == 0)
	check("unknown dice can't be bought", Catalog.buy_dice("rainbow") != "" and p.coins == 99999 and writes == 0)
	check("unknown room can't be equipped", not Catalog.equip_room("castle") and p.room == "night")
	check("unknown dice can't be equipped", not Catalog.equip_dice("rainbow") and p.dice == "classic")
	check("empty id is unknown", Catalog.buy_room("") != "" and not Catalog.equip_dice(""))
	p.rooms.append("castle")
	check("a stray unknown id in the save isn't treated as owned", not Catalog.owns_room("castle"))

	# ---- the save fails: everything rolls back ----
	p = use(fresh(5000), true)
	err = Catalog.buy_room("dream")
	check("failed save: buy reports it", err == Catalog.SAVE_FAILED, err)
	check("failed save: no coins spent, room not owned, room unchanged", p.coins == 5000 and p.rooms == ["night", "cafe"] and p.room == "night", p)
	err = Catalog.buy_dice("crema")
	check("failed save: dice rolled back", err == Catalog.SAVE_FAILED and p.coins == 5000 and p.dice_owned == ["classic"] and p.dice == "classic", p)
	p.rooms.append("studio")
	check("failed save: equip returns false and keeps the old room", not Catalog.equip_room("studio") and p.room == "night")
	var same := p
	Catalog.buy_room("cloud")
	check("rollback keeps the same profile Dictionary", is_same(same, Catalog.profile()))
