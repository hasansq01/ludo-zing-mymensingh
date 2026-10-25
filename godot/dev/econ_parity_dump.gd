extends SceneTree
## Dev: runs the GDScript economy (Save, Catalog, SLScenes, Collection, Rewards, LudoRules, SnakesLaddersRules) on
## many seeded inputs and writes what it returned, for the server's TS port parity test (server/test/econ_parity.test.ts).
## Run from the repo root:
##   godot --headless --path godot -s res://dev/econ_parity_dump.gd [-- <out.json> [<seed>]]
## Default out: ../server/test/fixtures/econ_cases.json (relative to the project folder, godot/).
##
## Nothing touches the real save file: Catalog / Collection work on `profile_source` dictionaries, Save's functions
## run on detached Save instances whose debounce timer never fires (and _dirty is cleared before they are freed).
## Godot prints 8 "Invalid month / day value" errors for the impossible day keys in `days`: expected.
## Profiles go through JSON first, as on a real load (every number a float), then Save._ensure().
##
## Sections (each a list of cases; `p` the profile before, `out` the profile after):
##   catalog    export_catalog.gd build() (the test compares it with server/src/econ/catalog.json)
##   level      [xp, level, into, need] (Save.level_info; Collection.level_info is checked to agree)
##   days       {key, num, plus: [[days, key]...]} (Rewards.day_num / add_days, damaged and impossible keys too)
##   normalize  {in, out} (Save._ensure on raw, damaged profiles; out.id is "" when _ensure made a random one)
##   unlocked   {p, kind, id, unlocked, equipped} (Collection.is_unlocked / equipped)
##   buy        {p, kind, id, err (the game's message), code, out}
##   equip      {p, kind, id, ok, out}
##   ach        {p, id, progress, claimable_count, paid, out}
##   daily      {p, steps: [{today, claim, state, res?, out}]} (a run of days; `at` / `last_at` are wall-clock in
##              the game: the test masks them)
##   spin       {p, today, seed, roll, res, out} (roll: the segment the seeded RNG gives, read from a twin RNG)
##   free       {p, now, left, paid, out}
##   ludo       {p, players, teams, winner, won, win_reward, play_reward, out} (LudoMatch._game_over's bookkeeping:
##              reward = win_reward or play_reward, Save.record_ludo(players, human_won), Save.add_coins(reward))
##   sl         {p, mode, n, won, reward, out} (SLMatch._win's: claim_win_reward or claim_play_reward,
##              Save.record_sl(won_paid), Save.add_coins(reward)), from real games played with random dice

const SaveScript := preload("res://scripts/core/save.gd")
const ExportCatalog := preload("res://dev/export_catalog.gd")
const SL := preload("res://scripts/core/snakes_ladders_rules.gd")
const BASE_DAY := "2026-10-24"

var rng := RandomNumberGenerator.new()
var bad := 0
var _timer_holder: Node

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)   # on the first frame: the root is in the tree (Save's timer)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "../server/test/fixtures/econ_cases.json"
	if out.is_relative_path():
		out = ProjectSettings.globalize_path("res://").path_join(out).simplify_path()
	rng.seed = int(args[1]) if args.size() > 1 else 20261024
	seed(rng.seed)
	_timer_holder = Node.new()
	root.add_child(_timer_holder)
	var data := {
		version = 1, seed = rng.seed, base_day = BASE_DAY,
		catalog = ExportCatalog.build(),
		level = level_cases(), days = day_cases(), normalize = normalize_cases(), unlocked = unlocked_cases(),
		buy = buy_cases(), equip = equip_cases(), ach = ach_cases(), daily = daily_cases(), spin = spin_cases(),
		free = free_cases(), ludo = ludo_cases(), sl = sl_cases(),
	}
	Catalog.profile_source = null
	Collection.profile_source = null
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % out)
		quit(1)
		return
	f.store_string(JSON.stringify(data, "", false, true))
	f.close()
	var counts := []
	for k in data:
		if data[k] is Array:
			counts.append("%s %d" % [k, data[k].size()])
	print("wrote %s: %s; %d problems" % [out, ", ".join(counts), bad])
	quit(1 if bad else 0)

func check(ok: bool, what: String) -> void:
	if not ok:
		bad += 1
		push_error("parity dump: " + what)


# ---------- helpers ----------

func pick(a: Array) -> Variant:
	return a[rng.randi_range(0, a.size() - 1)]

func chance(p: float) -> bool:
	return rng.randf() < p

func subset(a: Array, p := 0.4) -> Array:
	var out := []
	for x in a:
		if chance(p):
			out.append(x)
	return out

func ids(list: Array) -> Array:
	return list.map(func(d): return d.id)

func json_trip(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v))

func copy(p: Dictionary) -> Dictionary:
	return p.duplicate(true)

## A detached Save whose timer is in the tree but never connected (save() only marks it dirty).
func make_save(p: Dictionary) -> Node:
	var s: Node = SaveScript.new()
	s.profile = p
	s.prefs = {}
	var t := Timer.new()
	_timer_holder.add_child(t)
	s._timer = t
	return s

func drop_save(s: Node) -> void:
	s._dirty = false
	s._timer.stop()
	s._timer.queue_free()
	s.free()

func ensure(raw: Dictionary) -> Dictionary:
	var s := make_save(raw)
	s._ensure()
	var p: Dictionary = s.profile
	drop_save(s)
	return p

func day(offset: int) -> String:
	return Rewards.add_days(BASE_DAY, offset)

func room_ids() -> Array: return ids(Rooms.LIST)
func dice_ids() -> Array: return ids(Catalog.DICE)
func scene_ids() -> Array: return ids(SLScenes.LIST)
func emote_ids() -> Array: return ids(Catalog.EMOTE_PACKS)
func char_ids() -> Array: return ids(Collection.CHARS)
func avatar_ids() -> Array: return ids(Collection.AVATARS)
func frame_ids() -> Array: return ids(Collection.FRAMES)
func plate_ids() -> Array: return ids(Collection.PLATES)
func ach_ids() -> Array: return ids(Collection.ACH)

## A random daily calendar state (sometimes damaged).
func rand_daily() -> Variant:
	if chance(0.15):
		return pick([null, [], "x", {}, {cycle = -1, streak = 9, last = "2026-1-1"}, {cycle = 1.5, streak = 3.0}])
	var d := {cycle = rng.randi_range(0, 5), streak = rng.randi_range(0, 7)}
	if chance(0.85):
		d.last = day(rng.randi_range(-4, 0))
		d.last_at = 1761264000 + rng.randi_range(0, 100000)
	if chance(0.3):
		d.auto_on = day(rng.randi_range(-2, 0))
	var hist := []
	for k in rng.randi_range(0, 4):
		hist.append({on = day(-k), at = 1761264000, cycle = rng.randi_range(0, 3), day = rng.randi_range(1, 7),
			coins = pick([0, 100, 400, 1200]), item = pick([null, "crema", "espresso", "ch-rafi", "ch-mim"])})
	d.history = hist
	return d

## A raw profile as the save file could hold it (JSON numbers become floats on the trip).
func rand_raw() -> Dictionary:
	var raw := {id = "LZM-T%03d-%04d" % [rng.randi_range(0, 999), rng.randi_range(0, 9999)]}
	raw.name = pick(["You", "Shihab", "Mim", "Rafi"])
	var prices := [0, 1000, 2500, 3000, 6000, 10000, 10500, 12000, 20000, 25000]
	raw.coins = pick([rng.randi_range(0, 60000), rng.randi_range(0, 3000), pick(prices) + rng.randi_range(-1, 1), 5000])
	raw.xp = pick([0, rng.randi_range(0, 400), rng.randi_range(0, 3000), rng.randi_range(0, 30000), 99, 100, 249, 250, 1000])
	raw.stats = {
		played = rng.randi_range(0, 30), wins = rng.randi_range(0, 3), losses = rng.randi_range(0, 10),
		streak = rng.randi_range(0, 3), bestStreak = rng.randi_range(0, 4), coinsEarned = rng.randi_range(0, 12000),
		pairsFormed = rng.randi_range(0, 12), ppGames = rng.randi_range(0, 6), slPlayed = rng.randi_range(0, 9),
		slWins = rng.randi_range(0, 4),
	}
	raw.rooms = subset(room_ids(), 0.35)
	raw.room = pick(room_ids() + ["bogus"])
	raw.dice_owned = subset(dice_ids(), 0.35)
	raw.dice = pick(dice_ids())
	if chance(0.6):
		raw.scenes = subset(scene_ids(), 0.3)
	if chance(0.6):
		raw.scene = pick(scene_ids())
	if chance(0.6):
		raw.emote_sets = subset(emote_ids(), 0.35)
	if chance(0.6):
		raw.emote_set = pick(emote_ids() + ["bogus"])
	raw.av_owned = subset(char_ids(), 0.2)
	raw.avatar = pick(avatar_ids() + char_ids())
	raw.frame = pick(frame_ids())
	raw.plate = pick(plate_ids())
	raw.badge = pick(Collection.BADGES)
	raw.claimed = subset(ach_ids(), 0.3)
	raw.daily = rand_daily()
	raw.last_spin = pick(["", day(0), day(-1), day(-3)])
	raw.last_free = pick([0, 1761264000, 1761264000 + rng.randi_range(0, 30000)])
	return raw

func rand_profile() -> Dictionary:
	return ensure(json_trip(rand_raw()))


# ---------- sections ----------

func level_cases() -> Array:
	var out := []
	var xs := [0, 1, 99, 100, 101, 249, 250, 251, 449, 450, 1000, 5000, 12345, 50000, 199999, 200000, 1000000, -5]
	for k in 160:
		xs.append(rng.randi_range(0, 250000))
	for x in xs:
		var li := SaveScript.level_info(x)
		check(li == Collection.level_info(x), "level_info differs for %d" % x)
		out.append([x, li.level, li.into, li.need])
	return out

func day_cases() -> Array:
	var keys := [BASE_DAY, "1970-01-01", "2000-02-29", "2024-02-29", "2100-03-01", "2026-12-31", "2027-01-01",
		"2026-13-01", "2026-02-30", "2026-00-10", "2026-10-00", "2026-1-1", "", "abcd-ef-gh", "2026/10/24", "+202-10-24"]
	for k in 40:
		keys.append(day(rng.randi_range(-3000, 3000)))
	var out := []
	for key in keys:
		var plus := []
		if Rewards.day_num(key) > 0:
			for d in [-1, 1, 7, 31, 366]:
				plus.append([d, Rewards.add_days(key, d)])
		out.append({key = key, num = Rewards.day_num(key), valid = Rewards.is_day_key(key), plus = plus})
	return out

func normalize_cases() -> Array:
	var out := []
	var raws := []
	raws.append({})
	raws.append({name = "   ", coins = 12.9, xp = -40})
	raws.append({coins = "1234", xp = "12.7", last_free = "99"})
	raws.append({coins = true, rooms = "night", room = 5, dice_owned = {}, dice = 3, daily = [], last_spin = 7,
		avatar = "", av_owned = "x", frame = null, plate = "", badge = 0, claimed = {}})
	raws.append({rooms = ["dream", 3, "cafe"], room = "dream", dice_owned = ["gold"], dice = "gold", stats = {wins = 2.0, extra = 5}})
	raws.append({rooms = ["dream"], room = "studio", dice_owned = ["classic", "classic"], dice = "crema", stats = []})
	raws.append({emote_sets = ["game", 3, "pawns"], emote_set = "friends"})
	raws.append({emote_sets = "x", emote_set = 4})
	raws.append({emote_sets = ["friends"], emote_set = "friends"})
	raws.append({name = "\tAna\n", id = "LZM-AAAA-BBBB", extra_field = {a = 1}})
	for k in 60:
		var raw := rand_raw()
		for key in raw.keys():
			if chance(0.1):
				raw.erase(key)
		raws.append(raw)
	for raw in raws:
		var input = json_trip(raw)
		var had_id: bool = input.has("id")
		var p := ensure(copy(input))
		var o := copy(p)
		if not had_id:
			check(str(o.id).length() == 13 and str(o.id).begins_with("LZM-"), "fresh id %s" % o.id)
			o.id = ""
		out.append({"in": input, "out": o})
	return out

func unlocked_cases() -> Array:
	var out := []
	var kinds := {avatar = avatar_ids() + char_ids() + ["nope"], char = char_ids(), frame = frame_ids() + ["nope"],
		plate = plate_ids(), badge = Collection.BADGES + ["nope"]}
	for k in 60:
		var p := rand_profile()
		for kind in kinds:
			var id: String = pick(kinds[kind])
			out.append({p = p, kind = kind, id = id, unlocked = Collection.is_unlocked(kind, id, p),
				equipped = Collection.equipped(kind, p)})
	return out

func buy_code(err: String) -> String:
	if err == "":
		return ""
	if err.contains("n’t in the"):
		return "unknown"
	if err.begins_with("You already own") or err.ends_with("is free to use."):
		return "owned"
	if err.begins_with("Not enough coins"):
		return "coins"
	return "?"

func buy_cases() -> Array:
	var out := []
	var kinds := {room = room_ids() + ["nope"], emotes = emote_ids() + ["nope"], dice = dice_ids() + ["nope"], scene = scene_ids() + ["nope"],
		char = char_ids() + ["pawn-red", "nope"]}
	for k in 420:
		var p := rand_profile()
		var kind: String = pick(kinds.keys())
		var id: String = pick(kinds[kind])
		if chance(0.3):
			p.coins = pick([60000, 25000, 12000])   # more cases that get as far as paying
		var before := copy(p)
		Catalog.profile_source = p
		Collection.profile_source = p
		var err := ""
		match kind:
			"room": err = Catalog.buy_room(id)
			"dice": err = Catalog.buy_dice(id)
			"emotes": err = Catalog.buy_emotes(id)
			"scene": err = SLScenes.buy_scene(id)
			"char": err = Collection.buy_char(id, true)
		var code := buy_code(err)
		check(code != "?", "unmapped buy message %s" % err)
		out.append({p = before, kind = kind, id = id, err = err, code = code, out = copy(p)})
	return out

func equip_cases() -> Array:
	var out := []
	var kinds := {room = room_ids() + ["nope"], emotes = emote_ids() + ["nope"], dice = dice_ids(), scene = scene_ids(), avatar = avatar_ids() + char_ids(),
		char = char_ids(), frame = frame_ids(), plate = plate_ids(), badge = Collection.BADGES}
	for k in 340:
		var p := rand_profile()
		var kind: String = pick(kinds.keys())
		var id: String = pick(kinds[kind])
		var before := copy(p)
		Catalog.profile_source = p
		Collection.profile_source = p
		var ok := false
		match kind:
			"room": ok = Catalog.equip_room(id)
			"dice": ok = Catalog.equip_dice(id)
			"emotes": ok = Catalog.equip_emotes(id)
			"scene": ok = SLScenes.equip_scene(id)
			_: ok = Collection.equip(kind, id)
		out.append({p = before, kind = kind, id = id, ok = ok, out = copy(p)})
	return out

func ach_cases() -> Array:
	var out := []
	for k in 160:
		var p := rand_profile()
		var id: String = pick(ach_ids() + ["nope"])
		var before := copy(p)
		Collection.profile_source = p
		var progress := Collection.ach_progress(id, p)
		var count := Collection.claimable_count(p)
		var paid := Collection.claim_ach(id)
		out.append({p = before, id = id, progress = progress, claimable_count = count, paid = paid, out = copy(p)})
	return out

func state_summary(st: Dictionary) -> Dictionary:
	var tiles := []
	for t: Dictionary in st.rewards:
		tiles.append({day = t.day, grant = t.grant, status = t.status})
	return {key = st.key, claimable = st.claimable, cycle = st.cycle, claimed = st.claimed, today = st.today,
		day = st.day, streak = st.streak, missed = st.missed, tiles = tiles}

func daily_cases() -> Array:
	var out := []
	for k in 70:
		var p := rand_profile()
		var start := copy(p)
		var today := day(rng.randi_range(-1, 2))
		var steps := []
		for n in rng.randi_range(4, 24):
			var claim := chance(0.85)
			var st := state_summary(Rewards.daily_state(p, today))
			var step := {today = today, claim = claim, state = st}
			if claim:
				step.res = Rewards.claim_daily(p, today)
				step.res.erase("text")
			step.out = copy(p)
			steps.append(step)
			today = Rewards.add_days(today, pick([0, 1, 1, 1, 1, 1, 1, 2, 3, -1, 9]))
		out.append({p = start, steps = steps})
	return out

func spin_cases() -> Array:
	var out := []
	for k in 200:
		var p := rand_profile()
		var today: String = pick([day(0), day(-1), day(1), str(p.last_spin)])
		if today == "":
			today = day(0)                        # (Rewards reads "" as the device's today)
		var s := rng.randi()
		var r := RandomNumberGenerator.new()
		r.seed = s
		var twin := RandomNumberGenerator.new()
		twin.seed = s
		var roll := twin.randi_range(0, Rewards.PRIZES.size() - 1)
		var before := copy(p)
		var res := Rewards.spin(p, r, today)
		if res.ok:
			check(res.index == roll, "spin roll %d vs %d" % [res.index, roll])
		out.append({p = before, today = today, seed = s, roll = roll, res = res, out = copy(p)})
	return out

func free_cases() -> Array:
	var out := []
	for k in 160:
		var p := rand_profile()
		var last := int(p.last_free)
		var now: int = pick([last + rng.randi_range(0, 30000), last + 14400, last + 14399, last - 500, 1761300000, last])
		if now < 0:
			now = 1761300000                      # (Rewards reads a negative `now` as the device's clock)
		var before := copy(p)
		var left := Rewards.free_left_sec(p, now)
		var paid := Rewards.claim_free(p, now)
		out.append({p = before, now = now, left = left, paid = paid, out = copy(p)})
	return out

func ludo_cases() -> Array:
	var out := []
	var layouts := [
		["human", "cpu", "off", "off"], ["human", "off", "cpu", "off"], ["human", "cpu", "cpu", "cpu"],
		["cpu", "human", "cpu", "off"], ["human", "human", "off", "off"], ["human", "human", "cpu", "cpu"],
		["human", "human", "human", "human"], ["human", "off", "off", "off"], ["cpu", "cpu", "off", "off"],
		["off", "cpu", "human", "cpu"],
	]
	for k in 220:
		var p := rand_profile()
		var players: Array = (pick(layouts) as Array).duplicate()
		var teams := chance(0.3) and not players.has("off")
		var s := LudoRules.new_game(players, teams)
		var active := []
		for c in 4:
			if players[c] != "off":
				active.append(c)
		s.phase = "over"
		s.winner = pick(active)
		var winners := LudoRules.winners(s)
		var human_won := winners.any(func(c): return LudoRules.is_human(s, c))
		var win_reward := LudoRules.win_reward(s)
		var play_reward := LudoRules.play_reward(s)
		var reward := win_reward if win_reward > 0 else play_reward
		var before := copy(p)
		var sv := make_save(p)
		sv.record_ludo(players, human_won)
		if reward > 0:
			sv.add_coins(reward)
		drop_save(sv)
		out.append({p = before, players = players, teams = s.teams, winner = s.winner, won = human_won,
			win_reward = win_reward, play_reward = play_reward, out = copy(p)})
	return out

func sl_cases() -> Array:
	var out := []
	for k in 160:
		var p := rand_profile()
		var mode: String = pick(["cpu", "cpu", "local"])
		var n := rng.randi_range(2, 4)
		var g := SL.new_game(mode, n, 0, {need_one = chance(0.3)})
		var guard := 0
		while g.phase != "over" and guard < 20000:
			SL.apply_roll(g, rng.randi_range(1, 6))
			guard += 1
		if g.phase != "over":
			continue
		var reward := SL.claim_win_reward(g)
		var won_paid := reward > 0
		if not won_paid:
			reward = SL.claim_play_reward(g)
		var before := copy(p)
		var sv := make_save(p)
		sv.record_sl(won_paid)
		if reward > 0:
			sv.add_coins(reward)
		drop_save(sv)
		out.append({p = before, mode = mode, n = n, won = bool(g.players[g.winner].you), reward = reward, out = copy(p)})
	return out
