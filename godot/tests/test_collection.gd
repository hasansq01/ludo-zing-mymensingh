extends "res://tests/test_suite.gd"
## Collection logic: free / locked / level / achievement unlocks, buying characters with and without coins, no double
## charge, rollback when the save fails, equip rules, achievement progress and the one-time claim, plus the SVG art.
## Every check runs on its own profile Dictionary (Collection.profile_source): the real save is never read or written.

var writes := 0

func fresh(coins := 5000, stats := {}) -> Dictionary:
	var st := {played = 0, wins = 0, losses = 0, streak = 0, bestStreak = 0, coinsEarned = 0, pairsFormed = 0, ppGames = 0, slPlayed = 0, slWins = 0}
	st.merge(stats, true)
	return {coins = coins, xp = 0, stats = st, avatar = "pawn-red", av_owned = [], frame = "classic", plate = "plain", badge = "", claimed = []}

func use(p: Dictionary, fail := false) -> Dictionary:
	Collection.profile_source = p
	writes = 0
	Collection.writer = func(_prof: Dictionary) -> bool:
		writes += 1
		return not fail
	return p

func run() -> void:
	var keep_src: Variant = Collection.profile_source
	var keep_writer: Callable = Collection.writer
	_run()
	Collection.profile_source = keep_src
	Collection.writer = keep_writer

func _ids(list: Array) -> Array:
	return list.map(func(x): return x.id)

func _run() -> void:
	var p: Dictionary
	var err: String

	# ---- catalogue (index.html CHARS / AVATARS / FRAMES / PLATES / ACH) ----
	check("20 characters", Collection.CHARS.size() == 20)
	check("10 male and 10 female", Collection.CHARS.filter(func(c): return c.g == "m").size() == 10 and Collection.CHARS.filter(func(c): return c.g == "f").size() == 10)
	check("Arif and Nadia are the free characters", _ids(Collection.CHARS.filter(func(c): return c.price == 0)) == ["ch-arif", "ch-nadia"])
	check("paid characters cost 10,000-12,000", Collection.CHARS.all(func(c): return c.price == 0 or (c.price >= 10000 and c.price <= 12000)))
	check("character ids are unique", _unique(_ids(Collection.CHARS) + _ids(Collection.AVATARS)))
	check("avatars match the web", _ids(Collection.AVATARS) == ["pawn-red", "pawn-green", "pawn-yellow", "pawn-blue", "latte", "dice", "robot", "crown"])
	check("frames match the web", _ids(Collection.FRAMES) == ["classic", "gold", "mint", "royal"] and Collection.FRAMES.map(func(f): return f.name) == ["Wood", "Gold", "Mint", "Royal"])
	check("plates match the web", _ids(Collection.PLATES) == ["plain", "espresso", "ruby"])
	check("achievements match the web", _ids(Collection.ACH) == ["first", "streak", "veteran", "pairs", "party", "coins"]
		and Collection.ACH.map(func(a): return a.reward) == [200, 300, 500, 300, 300, 500]
		and Collection.ACH.map(func(a): return a.goal) == [1, 3, 25, 10, 5, 10000])
	check("badges: none + every achievement", Collection.BADGES == [""] + _ids(Collection.ACH))
	check("avatar(id) finds originals and characters", Collection.avatar("robot").name == "Robot" and Collection.avatar("ch-mim").name == "Mim" and Collection.avatar("nope").is_empty())
	check("level info like the web", [Collection.level_info(0).level, Collection.level_info(99).level, Collection.level_info(100).level, Collection.level_info(250).level, Collection.level_info(450).level, Collection.level_info(700).level] == [1, 1, 2, 3, 4, 5])

	# ---- unlocks ----
	p = use(fresh(0))
	check("free avatars unlocked", Collection.is_unlocked("avatar", "pawn-red") and Collection.is_unlocked("avatar", "latte"))
	check("free characters unlocked with no coins", Collection.is_unlocked("char", "ch-arif") and Collection.is_unlocked("char", "ch-nadia"))
	check("paid character locked until bought", not Collection.is_unlocked("char", "ch-rafi") and not Collection.is_unlocked("avatar", "ch-rafi"))
	check("achievement avatar locked before the achievement", not Collection.is_unlocked("avatar", "dice") and not Collection.is_unlocked("avatar", "robot"))
	check("level avatar / frame locked at level 1", not Collection.is_unlocked("avatar", "crown") and not Collection.is_unlocked("frame", "gold"))
	check("Wood frame and Plain plate always unlocked", Collection.is_unlocked("frame", "classic") and Collection.is_unlocked("plate", "plain"))
	check("no badge is always allowed", Collection.is_unlocked("badge", ""))
	check("a badge needs its achievement", not Collection.is_unlocked("badge", "first"))
	check("unknown ids are locked", not Collection.is_unlocked("avatar", "unicorn") and not Collection.is_unlocked("frame", "neon") and not Collection.is_unlocked("badge", "nope") and not Collection.is_unlocked("shoes", "x"))
	p.xp = 699
	check("level 4 (699 XP) still locks Crown", not Collection.is_unlocked("avatar", "crown"))
	p.xp = 700
	check("level 5 unlocks Crown and the Gold frame", Collection.level() == 5 and Collection.is_unlocked("avatar", "crown") and Collection.is_unlocked("frame", "gold"))
	p.stats.wins = 1
	check("First Victory unlocks Lucky Dice and its badge", Collection.is_unlocked("avatar", "dice") and Collection.is_unlocked("badge", "first"))
	p.stats.bestStreak = 3
	check("Winning Streak unlocks Robot and the Ruby plate", Collection.is_unlocked("avatar", "robot") and Collection.is_unlocked("plate", "ruby"))
	p.stats.pairsFormed = 9
	check("9 pairs: Mint still locked", not Collection.is_unlocked("frame", "mint"))
	p.stats.pairsFormed = 10
	check("10 pairs unlock Mint", Collection.is_unlocked("frame", "mint"))
	p.stats.played = 25; p.stats.coinsEarned = 10000
	check("Espresso plate and Royal frame from their achievements", Collection.is_unlocked("plate", "espresso") and Collection.is_unlocked("frame", "royal"))
	check("unlock texts", [Collection.unlock_text("avatar", "crown"), Collection.unlock_text("frame", "royal"), Collection.unlock_text("char", "ch-rafi"), Collection.unlock_text("avatar", "latte"), Collection.unlock_text("badge", "pairs")]
		== ["Reach level 5", "Earn “Coin Collector”", "10K coins", "", "Earn “Master of Pairs”"],
		[Collection.unlock_text("avatar", "crown"), Collection.unlock_text("frame", "royal"), Collection.unlock_text("char", "ch-rafi"), Collection.unlock_text("avatar", "latte"), Collection.unlock_text("badge", "pairs")])
	check("stats as JSON floats still count", Collection.ach_done("first", {stats = {wins = 1.0}}))

	# ---- buying characters ----
	p = use(fresh(12000))
	err = Collection.buy_char("ch-rafi")
	check("buy a character: success", err == "", err)
	check("buy a character: price taken once", p.coins == 2000, p.coins)
	check("buy a character: owned", p.av_owned == ["ch-rafi"] and Collection.is_unlocked("char", "ch-rafi"), p.av_owned)
	check("buy a character: not equipped (the card then offers Use)", p.avatar == "pawn-red")
	check("buy a character: saved once", writes == 1, writes)
	check("buying does not count as coins earned", p.stats.coinsEarned == 0)
	err = Collection.buy_char("ch-rafi")
	check("buying twice is refused", err == "You already own Rafi.", err)
	check("buying twice charges nothing", p.coins == 2000 and p.av_owned == ["ch-rafi"] and writes == 1, [p.coins, p.av_owned, writes])
	p = use(fresh(10249))
	err = Collection.buy_char("ch-imran")
	check("not enough coins is refused", err == "Not enough coins — you need 1 more.", err)
	check("not enough coins spends nothing", p.coins == 10249 and p.av_owned.is_empty() and writes == 0, p)
	p = use(fresh(10250))
	check("exactly enough coins buys", Collection.buy_char("ch-imran") == "" and p.coins == 0 and p.av_owned == ["ch-imran"])
	p = use(fresh(50000))
	err = Collection.buy_char("ch-arif")
	check("free characters aren't sold", err != "" and p.coins == 50000 and p.av_owned.is_empty() and writes == 0, err)
	err = Collection.buy_char("ch-bogus")
	check("unknown characters aren't sold", err != "" and p.coins == 50000 and writes == 0, err)
	err = Collection.buy_char("robot")
	check("original avatars aren't sold", err != "" and p.coins == 50000 and writes == 0, err)
	check("buy and equip in one go", Collection.buy_char("ch-mim", true) == "" and p.avatar == "ch-mim" and p.coins == 39000)
	p = use(fresh(11000))
	p.erase("av_owned")
	check("buying works when av_owned is missing", Collection.buy_char("ch-nayeem") == "" and p.av_owned == ["ch-nayeem"])

	# ---- rollback when the save fails ----
	p = use(fresh(12000), true)
	var before := p.duplicate(true)
	err = Collection.buy_char("ch-rakib")
	check("failed save: buy reports it", err == Collection.SAVE_FAILED, err)
	check("failed save: no coins spent, nothing owned", p.coins == 12000 and p.av_owned.is_empty(), p)
	check("failed save: profile exactly as before", p == before)
	check("failed save: the same Dictionary is kept", is_same(Collection.profile(), p))
	check("failed save: equip refused and rolled back", not Collection.equip("frame", "classic") or p.frame == "classic")
	p.stats.wins = 1
	before = p.duplicate(true)
	check("failed save: equip of an unlocked item returns false", not Collection.equip("avatar", "dice") and p.avatar == "pawn-red")
	check("failed save: claim pays nothing", Collection.claim_ach("first") == 0 and p == before, p)

	# ---- equipping ----
	p = use(fresh(0))
	check("equip a free avatar", Collection.equip("avatar", "latte") and p.avatar == "latte" and writes == 1)
	check("equip the one in use again: no save", Collection.equip("avatar", "latte") and writes == 1)
	check("equip a free character", Collection.equip("char", "ch-nadia") and p.avatar == "ch-nadia")
	check("never equip a paid character not bought", not Collection.equip("char", "ch-rafi") and p.avatar == "ch-nadia")
	check("never equip a locked avatar", not Collection.equip("avatar", "crown") and p.avatar == "ch-nadia")
	check("never equip a locked frame", not Collection.equip("frame", "royal") and p.frame == "classic")
	check("never equip a locked plate", not Collection.equip("plate", "ruby") and p.plate == "plain")
	check("never equip an unearned badge", not Collection.equip("badge", "veteran") and p.badge == "")
	check("never equip unknown things", not Collection.equip("avatar", "zzz") and not Collection.equip("hat", "classic"))
	p.stats.bestStreak = 3; p.stats.pairsFormed = 10
	check("equip an unlocked frame / plate / badge", Collection.equip("frame", "mint") and Collection.equip("plate", "ruby") and Collection.equip("badge", "streak")
		and p.frame == "mint" and p.plate == "ruby" and p.badge == "streak")
	check("take the badge off", Collection.equip("badge", "") and p.badge == "")
	check("equipped() reads what is in use", Collection.equipped("avatar") == "ch-nadia" and Collection.equipped("frame") == "mint" and Collection.equipped("plate") == "ruby")
	p = use(fresh(0))
	p.avatar = "ch-rafi"; p.frame = "royal"; p.plate = "unknown"; p.badge = "coins"
	check("equipped() falls back from locked / unknown saved values", Collection.equipped("avatar") == "pawn-red" and Collection.equipped("frame") == "classic"
		and Collection.equipped("plate") == "plain" and Collection.equipped("badge") == "")
	p = use({})
	check("equipped() on an empty profile gives the defaults", Collection.equipped("avatar") == "pawn-red" and Collection.equipped("frame") == "classic" and Collection.equipped("badge") == "")
	check("is_equipped", Collection.is_equipped("avatar", "pawn-red") and not Collection.is_equipped("avatar", "latte"))

	# ---- achievements: progress and the one-time claim ----
	p = use(fresh(100, {played = 12, wins = 1, bestStreak = 2, coinsEarned = 6400}))
	var pr := Collection.ach_progress("veteran")
	check("progress: value / goal / pct", pr.value == 12 and pr.goal == 25 and not pr.done and not pr.claimed and is_equal_approx(pr.pct, 0.48), pr)
	pr = Collection.ach_progress("coins")
	check("progress: coins", pr.value == 6400 and pr.goal == 10000 and not pr.done, pr)
	p.stats.wins = 7
	pr = Collection.ach_progress("first")
	check("progress is capped at the goal", pr.value == 1 and pr.done and is_equal_approx(pr.pct, 1.0), pr)
	check("progress of an unknown achievement is empty", Collection.ach_progress("bogus").is_empty())
	check("one claimable achievement", Collection.claimable_count() == 1, Collection.claimable_count())
	check("unfinished achievement can't be claimed", Collection.claim_ach("veteran") == 0 and p.coins == 100 and writes == 0)
	check("claim pays the reward", Collection.claim_ach("first") == 200 and p.coins == 300, p.coins)
	check("claim counts as coins earned (addCoins)", p.stats.coinsEarned == 6600, p.stats.coinsEarned)
	check("claim is remembered and saved", p.claimed == ["first"] and writes == 1 and Collection.ach_progress("first").claimed)
	check("claiming again pays nothing", Collection.claim_ach("first") == 0 and p.coins == 300 and writes == 1)
	check("nothing claimable after the claim", Collection.claimable_count() == 0)
	check("unknown achievements pay nothing", Collection.claim_ach("bogus") == 0 and p.coins == 300)
	p.stats.bestStreak = 3; p.stats.pairsFormed = 10
	check("two claimable now", Collection.claimable_count() == 2)
	check("claim both", Collection.claim_ach("streak") == 300 and Collection.claim_ach("pairs") == 300 and p.coins == 900 and p.claimed == ["first", "streak", "pairs"])
	p = use(fresh(0, {wins = 1}))
	p.claimed = ["first"]
	check("an already-claimed saved id pays nothing", Collection.claim_ach("first") == 0 and p.coins == 0)
	p.erase("claimed")
	p.stats.bestStreak = 3
	check("claim works when claimed[] is missing", Collection.claim_ach("streak") == 300 and p.claimed == ["streak"])

	# ---- art ----
	var bad := []
	for c: Dictionary in Collection.CHARS:
		var img := Image.new()
		if img.load_svg_from_string(Collection.tile_svg(c.id), 1.0) != OK or img.get_width() != 40:
			bad.append(c.id)
	for a: Dictionary in Collection.AVATARS:
		var img := Image.new()
		if img.load_svg_from_string(Collection.tile_svg(a.id), 1.0) != OK:
			bad.append(a.id)
	check("every avatar tile is valid SVG", bad.is_empty(), bad)
	var t := Collection.avatar_texture("ch-sumaiya", 64)
	check("avatar_texture gives a texture of the asked size", t != null and t.get_width() == 64 and t.get_height() == 64)
	check("avatar_texture is cached", is_same(t, Collection.avatar_texture("ch-sumaiya", 64)))
	var img2 := t.get_image()
	check("portrait tile: transparent corner, coloured middle", img2.get_pixel(0, 0).a < 0.1 and img2.get_pixel(32, 32).a > 0.9)
	check("unknown avatar draws the Red Pawn", Collection.tile_svg("nope") == Collection.tile_svg("pawn-red"))
	check("avatar colours", Collection.avatar_colors("ch-arif") == [Color("#bfe6ff"), Color("#6fb3e8")])

	# ---- medals: drawn art (assets/ui/medal_<id>.svg), not letters ----
	var no_art := Collection.ACH.filter(func(a): return Collection.medal_texture(a.id) == null).map(func(a): return a.id)
	check("every achievement has its medal art", no_art.is_empty(), no_art)
	check("no medal art for unknown ids", Collection.medal_texture("nope") == null)

	# ---- the Shop's Avatars tab: illustrated characters first, the one in use first ----
	p = use(fresh(0))
	p.avatar = "ch-nadia"
	var secs: Array = ShopSheet._sections("avatars")
	check("avatars tab: Characters then Classic", secs.map(func(x): return x[0]) == ["Characters", "Classic"], secs.map(func(x): return x[0]))
	check("avatars tab: the character in use leads, then the owned ones", secs[0][1][0].id == "ch-nadia" and secs[0][1][1].id == "ch-arif", secs[0][1].slice(0, 3))
	p.avatar = "pawn-blue"
	secs = ShopSheet._sections("avatars")
	check("avatars tab: a classic avatar in use leads its section", secs[1][1][0].id == "pawn-blue" and secs[1][1].size() == Collection.AVATARS.size())
	p.avatar = "ch-nadia"
	check("welcome: only the free characters, the one in use first", Welcome.free_avatars() == ["ch-nadia", "ch-arif"], Welcome.free_avatars())
	check("copy: typographic apostrophes", not Collection.SAVE_FAILED.contains("'") and not Catalog.SAVE_FAILED.contains("'"))

func _unique(a: Array) -> bool:
	var seen := {}
	for x in a:
		if seen.has(x):
			return false
		seen[x] = true
	return true
