class_name Rewards
extends RefCounted
## The reward rules (index.html: DAILY_CYCLES / dailyState / claimDaily, the daily spin PRIZES, the Free Coins timer),
## as pure functions over a profile Dictionary. The sheets pass Save.profile; the tests pass their own dictionaries
## and fixed day keys / timestamps.
##
## Daily Reward: one claim per local calendar day. Claiming the day after the last claim continues the run; missing a
## day (or more) restarts at Day 1 of the current cycle; after Day 7 the next cycle starts (after the last cycle the
## list starts over); a clock moved back never re-opens a claimed day. A dice skin already owned pays its `or` coins;
## a `char` reward gives that character (Collection.CHARS) unless it is owned already, then its `or` coins.
## State: p.daily = {cycle, streak (days claimed in this cycle, 0-7), last (YYYY-MM-DD), last_at (unix s), auto_on,
## history (<= 60 entries)}; damaged data is repaired, never trusted.
## Daily Spin: one spin per local day (p.last_spin = that day's key). Free Coins: FREE_AMOUNT every FREE_EVERY_SEC
## (p.last_free = unix seconds of the last claim).
## Coins go into p.coins and p.stats.coinsEarned; when p is the Save autoload's profile, changes are saved and
## Save.changed is emitted.

const DAILY_CYCLES := [
	[{"coins": 100}, {"coins": 150}, {"coins": 200}, {"dice": "crema", "or": 400}, {"coins": 300}, {"coins": 400},
		{"coins": 800, "char": "ch-rafi", "or": 1200}],
	[{"coins": 150}, {"coins": 200}, {"coins": 250}, {"dice": "espresso", "or": 600}, {"coins": 350}, {"coins": 450},
		{"coins": 1000, "char": "ch-mim", "or": 1500}],
	[{"coins": 200}, {"coins": 250}, {"coins": 300}, {"coins": 400}, {"dice": "gold", "or": 900}, {"coins": 500},
		{"coins": 1500, "char": "ch-tanvir", "or": 2000}],
]
## Dice skins a daily reward can give (index.html SKINS names).
## Shown through L10n.t(name) (the display sites translate).
const DICE_NAMES := {classic = "Classic", crema = "Crema", espresso = "Espresso", gold = "Royal Gold"}  # l10n
## The 8 wheel segments, clockwise from the top (index.html PRIZES).
const PRIZES := [100, 250, 150, 500, 100, 1000, 200, 300]
const FREE_EVERY_SEC := 14400
const FREE_AMOUNT := 300
const HISTORY_MAX := 60


# ---------- days ----------

## The local calendar day "YYYY-MM-DD": now (unix < 0) or of a unix time, in the device's time zone.
static func day_key(unix := -1) -> String:
	var d: Dictionary
	if unix < 0:
		d = Time.get_date_dict_from_system()
	else:
		d = Time.get_date_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]

## Days since 1970 for a day key (-1 for a damaged key).
static func day_num(key: String) -> int:
	if not is_day_key(key):
		return -1
	var y := int(key.substr(0, 4)); var m := int(key.substr(5, 2)); var dd := int(key.substr(8, 2))
	return int(Time.get_unix_time_from_datetime_dict({year = y, month = m, day = dd, hour = 0, minute = 0, second = 0}) / 86400)

## The key `days` days after `key` (tests and previews).
static func add_days(key: String, days: int) -> String:
	var d := Time.get_date_dict_from_unix_time((day_num(key) + days) * 86400)
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]

static func is_day_key(v: Variant) -> bool:
	if not v is String or (v as String).length() != 10:
		return false
	var s := v as String
	return s[4] == "-" and s[7] == "-" and s.substr(0, 4).is_valid_int() and s.substr(5, 2).is_valid_int() and s.substr(8, 2).is_valid_int()

static func _today(today: String) -> String:
	return today if today != "" else day_key()

static func _now(now: int) -> int:
	return now if now >= 0 else int(Time.get_unix_time_from_system())

## Seconds until the next local midnight (when the calendar and the wheel open again).
static func sec_to_midnight() -> int:
	var t := Time.get_time_dict_from_system()
	return maxi(1, 86400 - (int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second)))

## "4h 12m" / "35m" (index.html fmtDur: rounds up to whole minutes, at least 1m). Forwards to Fmt.until.
static func fmt_dur(sec: int) -> String:
	return Fmt.until(sec)

## 950 / 1.2K / 2K / 1.5M (index.html fmtCoins). Forwards to Fmt.coins.
static func fmt_coins(n: int) -> String:
	return Fmt.coins(n)


# ---------- daily reward ----------

static func cycle_rewards(cycle: int) -> Array:
	return DAILY_CYCLES[posmod(cycle, DAILY_CYCLES.size())]

## The saved calendar state, repaired if missing or damaged (written back into p.daily).
static func daily_data(p: Dictionary) -> Dictionary:
	var d: Dictionary = p.get("daily") if p.get("daily") is Dictionary else {}
	var cycle = d.get("cycle")
	var streak = d.get("streak")
	var hist: Array = d.get("history") if d.get("history") is Array else []
	var fixed := {
		cycle = int(cycle) if _is_int(cycle) and int(cycle) >= 0 else 0,
		streak = int(streak) if _is_int(streak) and int(streak) >= 0 and int(streak) <= 7 else 0,
		last = d.get("last") if is_day_key(d.get("last")) else "",
		last_at = int(d.get("last_at")) if _is_int(d.get("last_at")) and int(d.get("last_at")) > 0 else 0,
		auto_on = d.get("auto_on") if d.get("auto_on") is String else "",
		history = hist.slice(-HISTORY_MAX),
	}
	p.daily = fixed
	return fixed

static func _is_int(v: Variant) -> bool:
	return v is int or (v is float and is_equal_approx(v, roundf(v)))   # JSON numbers load as floats

## A reward as it would be given to p now: {coins, dice ("" when none)}; owned dice and every character turn into
## their `or` coins.
static func grant_of(p: Dictionary, r: Dictionary) -> Dictionary:
	var g := {coins = int(r.get("coins", 0)), dice = "", char = ""}
	if r.has("dice"):
		var owned: Array = p.get("dice_owned") if p.get("dice_owned") is Array else []
		if DICE_NAMES.has(r.dice) and not owned.has(r.dice):
			g.dice = r.dice
		else:
			g.coins += int(r.get("or", 0))
	if r.has("char"):
		var have: Array = p.get("av_owned") if p.get("av_owned") is Array else []
		if not have.has(r.char) and not char_name(r.char).is_empty():
			g.char = r.char
		else:
			g.coins += int(r.get("or", 0))
	return g

## A character's display name ("" when unknown), from Collection.CHARS.
static func char_name(id: String) -> String:
	for c in Collection.CHARS:
		if c.id == id:
			return str(c.name)
	return ""

## "400 coins", "Crema dice", "800 coins + Crema dice".
static func grant_label(g: Dictionary) -> String:
	var parts := []
	if int(g.coins) > 0:
		parts.append(L10n.t("%s coins") % fmt_coins(int(g.coins)))
	if str(g.dice) != "":
		parts.append(L10n.t("%s dice") % L10n.t(str(DICE_NAMES.get(g.dice, g.dice))))
	if str(g.get("char", "")) != "":
		parts.append(char_name(str(g.char)))
	return " + ".join(parts)

## What today looks like: {key, claimable, cycle, claimed (tiles already claimed), today (index of today's tile,
## -1 when nothing is claimable), day (1-7: the day claimable now, or the last one claimed), streak (saved days
## claimed), missed (a run was broken), rewards: 7 × {day, reward, grant, label, status "claimed"|"today"|"locked"}}.
static func daily_state(p: Dictionary, today := "") -> Dictionary:
	var d := daily_data(p)
	var key := _today(today)
	var gap := day_num(key) - day_num(d.last) if d.last != "" else 1 << 30
	var st := {key = key, streak = d.streak, missed = false}
	if gap <= 0:   # claimed today (or the clock went back)
		st.merge({claimable = false, cycle = d.cycle, claimed = d.streak, today = -1, day = maxi(1, d.streak)}, true)
	else:
		var cycle: int = d.cycle
		var start: int = d.streak
		if gap == 1 and d.streak == 7:   # the run continues into the next cycle
			cycle += 1; start = 0
		elif gap > 1:                    # a missed day: back to Day 1
			start = 0
		if gap > 1 and d.streak == 7:    # a finished cycle, then a break: the next cycle's Day 1
			cycle += 1
		st.merge({claimable = true, cycle = cycle, claimed = start, today = start, day = start + 1,
			missed = gap > 1 and d.last != "" and d.streak > 0 and d.streak < 7}, true)
	var list := []
	var rewards := cycle_rewards(st.cycle)
	for k in 7:
		var g := grant_of(p, rewards[k]) if k >= st.claimed else _granted(d, st.cycle, k, rewards[k])
		list.append({day = k + 1, reward = rewards[k], grant = g, label = grant_label(g),
			status = "claimed" if k < st.claimed else ("today" if k == st.today else "locked")})
	st.rewards = list
	return st

## What a claimed day gave (its history entry; the reward itself when the history doesn't have it), so a claimed
## dice tile keeps showing the dice rather than the coins it would pay now.
static func _granted(d: Dictionary, cycle: int, k: int, r: Dictionary) -> Dictionary:
	var hist: Array = d.history
	for i in range(hist.size() - 1, -1, -1):
		var e = hist[i]
		if e is Dictionary and int(e.get("day", 0)) == k + 1 and int(e.get("cycle", -1)) == cycle:
			var item: String = e.item if e.get("item") is String else ""
			var is_char := item.begins_with("ch-")
			return {coins = int(e.get("coins", 0)), dice = "" if is_char else item, char = item if is_char else ""}
	var g := {coins = int(r.get("coins", 0)), dice = str(r.get("dice", "")), char = ""}
	if r.has("char"):
		g.coins += int(r.get("or", 0))
	return g

## Claims today's reward: adds the coins / dice, records the day. Never twice a day.
## Returns {ok, coins, dice, text, day, cycle} (ok false and zeros when nothing was claimable).
static func claim_daily(p: Dictionary, today := "") -> Dictionary:
	var st := daily_state(p, today)
	if not st.claimable:
		return {ok = false, coins = 0, dice = "", text = L10n.t("Already claimed today"), day = st.day, cycle = st.cycle}
	var g: Dictionary = st.rewards[st.today].grant
	var d: Dictionary = p.daily
	var now := int(Time.get_unix_time_from_system())
	var hist: Array = d.history
	var item = g.dice if g.dice != "" else (g.char if str(g.get("char", "")) != "" else null)
	hist.append({on = st.key, at = now, cycle = st.cycle, day = st.today + 1, coins = g.coins, item = item})
	d.history = hist.slice(-HISTORY_MAX)
	d.cycle = st.cycle
	d.streak = st.today + 1
	d.last = st.key
	d.last_at = now
	_add_coins(p, g.coins)
	if g.dice != "":
		var owned: Array = p.get("dice_owned") if p.get("dice_owned") is Array else ["classic"]
		owned.append(g.dice)
		p.dice_owned = owned
	if str(g.get("char", "")) != "":
		var have: Array = p.get("av_owned") if p.get("av_owned") is Array else []
		have.append(g.char)
		p.av_owned = have
	var bits := []
	if g.coins > 0:
		bits.append(L10n.t("+%s coins") % fmt_coins(g.coins))
	if g.dice != "":
		bits.append(L10n.t("%s dice unlocked") % L10n.t(str(DICE_NAMES.get(g.dice, g.dice))))
	if str(g.get("char", "")) != "":
		bits.append(L10n.t("%s joined your collection") % char_name(str(g.char)))
	commit(p)
	return {ok = true, coins = g.coins, dice = g.dice, text = L10n.t("Day %d: %s") % [st.today + 1, ", ".join(bits)],
		day = st.today + 1, cycle = st.cycle}

## The calendar opens by itself on the first home visit of a day with a reward waiting; once a day.
static func should_auto_open(p: Dictionary, today := "") -> bool:
	return daily_state(p, today).claimable and daily_data(p).auto_on != _today(today)

static func mark_auto_open(p: Dictionary, today := "") -> void:
	daily_data(p).auto_on = _today(today)
	commit(p, false)


# ---------- daily spin ----------

static func can_spin(p: Dictionary, today := "") -> bool:
	return str(p.get("last_spin", "")) != _today(today)

## Spins the wheel: picks a segment, adds its coins and records the day.
## Returns {ok, index (segment 0-7), prize (coins)}; ok false (index -1) when today's spin is used.
## notify false: saved at once, but Save.changed waits for commit(p) (the wheel calls it when it stops, so the
## balance on the HUD doesn't jump before the prize shows).
static func spin(p: Dictionary, rng: RandomNumberGenerator, today := "", notify := true) -> Dictionary:
	if not can_spin(p, today):
		return {ok = false, index = -1, prize = 0}
	var k := rng.randi_range(0, PRIZES.size() - 1)
	p.last_spin = _today(today)
	_add_coins(p, PRIZES[k])
	commit(p, notify)
	return {ok = true, index = k, prize = PRIZES[k]}


# ---------- free coins ----------

## Seconds until Free Coins can be claimed again (0 = ready). A clock moved back never waits longer than one period.
static func free_left_sec(p: Dictionary, now := -1) -> int:
	var last := int(p.get("last_free", 0))
	if last <= 0:
		return 0
	return clampi(FREE_EVERY_SEC - (_now(now) - last), 0, FREE_EVERY_SEC)

static func free_ready(p: Dictionary, now := -1) -> bool:
	return free_left_sec(p, now) <= 0

## Claims the free coins when ready; returns the coins given (0 when not ready).
static func claim_free(p: Dictionary, now := -1) -> int:
	if not free_ready(p, now):
		return 0
	p.last_free = _now(now)
	_add_coins(p, FREE_AMOUNT)
	commit(p)
	return FREE_AMOUNT


## The Free Coins button caption: "Free Coins" when ready, else the time left ("3h 59m").
static func free_caption(p: Dictionary, now := -1) -> String:
	var left := free_left_sec(p, now)
	return L10n.t("Free Coins") if left <= 0 else fmt_dur(left)


# ---------- internals ----------

static func _add_coins(p: Dictionary, n: int) -> void:
	p.coins = int(p.get("coins", 0)) + n
	var st: Dictionary = p.get("stats") if p.get("stats") is Dictionary else {}
	st.coinsEarned = int(st.get("coinsEarned", 0)) + n
	p.stats = st

## Saves and (notify) emits Save.changed when p is the live profile (the Save autoload; absent in the headless tests).
static func commit(p: Dictionary, notify := true) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var save: Node = tree.root.get_node_or_null("Save") if tree else null
	if save == null or not is_same(save.get("profile"), p):
		return
	save.call("save")
	if notify:
		save.emit_signal("changed")
