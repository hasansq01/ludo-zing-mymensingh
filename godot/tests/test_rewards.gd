extends "res://tests/test_suite.gd"
## Port of tests/daily-rewards.js (the logic checks; the ones that read the popup's HTML are checked on the state
## the sheet draws from, the home badge and the restart text are left out) plus the Daily Spin and Free Coins rules.
## Pure: every check uses its own profile dictionary and fixed day keys / timestamps.

const R := preload("res://scripts/core/rewards.gd")
const DAY0 := "2026-03-10"
const T0 := 1800000000   # a fixed "now" (unix seconds)

## A fresh player: no daily data, plain dice only.
func fresh(coins := 1000) -> Dictionary:
	return {coins = coins, stats = {coinsEarned = 0}, dice_owned = ["classic"], dice = "classic", daily = {}, last_spin = "", last_free = 0}

func day(n: int) -> String:
	return R.add_days(DAY0, n)

func run() -> void:
	var C: Array = R.DAILY_CYCLES
	var p := fresh()
	var st: Dictionary
	var r: Dictionary

	# ---- helpers ----
	check("day keys are local YYYY-MM-DD", R.is_day_key(R.day_key()) and R.day_key().length() == 10, R.day_key())
	check("day keys step across months and years", R.add_days("2026-01-31", 1) == "2026-02-01" and R.add_days("2026-12-31", 1) == "2027-01-01"
		and R.add_days("2028-02-28", 1) == "2028-02-29", [R.add_days("2026-01-31", 1), R.add_days("2026-12-31", 1)])
	check("coin amounts are shortened like the web game", R.fmt_coins(950) == "950" and R.fmt_coins(1200) == "1.2K" and R.fmt_coins(2000) == "2K"
		and R.fmt_coins(1500000) == "1.5M", [R.fmt_coins(1200), R.fmt_coins(2000)])
	check("durations round up to minutes", R.fmt_dur(59) == "1m" and R.fmt_dur(3600) == "1h 0m" and R.fmt_dur(14399) == "4h 0m" and R.fmt_dur(0) == "1m",
		[R.fmt_dur(59), R.fmt_dur(3600), R.fmt_dur(14399)])

	# ---- a new player ----
	st = R.daily_state(p, day(0))
	check("a new player can claim Day 1 of cycle 1", st.claimable and st.today == 0 and st.cycle == 0, st)
	check("the calendar lists 7 days, Day 1 marked today", st.rewards.size() == 7 and st.rewards[0].status == "today"
		and st.rewards.slice(1).all(func(t): return t.status == "locked"), st.rewards.map(func(t): return t.status))

	# ---- Day 1, then duplicate claims ----
	var c0: int = p.coins
	R.claim_daily(p, day(0)); R.claim_daily(p, day(0)); R.claim_daily(p, day(0))   # rapid taps
	check("Day 1 pays its coins exactly once", p.coins == c0 + C[0][0].coins and p.daily.history.size() == 1, [p.coins - c0, p.daily.history.size()])
	check("Day 1 is saved as claimed today", p.daily.streak == 1 and p.daily.last == day(0) and p.daily.last_at > 0, p.daily)
	check("coins earned counts the reward", p.stats.coinsEarned == C[0][0].coins, p.stats)
	c0 = p.coins
	r = R.claim_daily(p, day(0))
	check("claiming again today does nothing", not r.ok and r.coins == 0 and p.coins == c0 and p.daily.history.size() == 1, r)
	st = R.daily_state(p, day(0))
	check("the calendar shows Day 1 claimed and nothing to claim", st.rewards[0].status == "claimed" and not st.claimable and st.today == -1
		and st.rewards[1].status == "locked", st)

	# ---- Days 2-7 on consecutive days ----
	for k in range(1, 7):
		st = R.daily_state(p, day(k))
		var rw: Dictionary = C[0][k]
		var before := {coins = p.coins, owned = (p.dice_owned as Array).duplicate()}
		check("Day %d is claimable the next day" % (k + 1), st.claimable and st.today == k and st.cycle == 0, st)
		r = R.claim_daily(p, day(k))
		var want := int(rw.get("coins", 0))   # a character not owned yet is given itself, not its coins
		var have: Array = p.get("av_owned", [])
		var ok: bool = r.ok and p.coins == before.coins + want and r.coins == want and p.daily.streak == k + 1 and p.daily.last == day(k) \
			and (not rw.has("dice") or (p.dice_owned.has(rw.dice) and not before.owned.has(rw.dice) and r.dice == rw.dice)) \
			and (not rw.has("char") or have.has(rw.char))
		check("Day %d grants %s" % [k + 1, JSON.stringify(rw)], ok, {coins = p.coins - before.coins, streak = p.daily.streak, owned = p.dice_owned, r = r})
	st = R.daily_state(p, day(6))
	check("after Day 7 all seven tiles show claimed", st.rewards.all(func(t): return t.status == "claimed") and not st.claimable, st.rewards.map(func(t): return t.status))

	# ---- the next cycle ----
	st = R.daily_state(p, day(7))
	check("the day after Day 7 starts cycle 2 at Day 1", st.claimable and st.cycle == 1 and st.today == 0, st)
	var cc: int = p.coins
	R.claim_daily(p, day(7))
	check("cycle 2 Day 1 pays the cycle-2 amount", p.coins == cc + C[1][0].coins and p.daily.cycle == 1 and p.daily.streak == 1, [p.coins - cc, p.daily])

	# ---- missed days ----
	p.daily.streak = 3; p.daily.last = day(7)
	st = R.daily_state(p, day(10))
	check("missing a day restarts at Day 1 (same cycle)", st.claimable and st.today == 0 and st.cycle == 1 and st.missed, st)
	cc = p.coins
	R.claim_daily(p, day(10))
	check("the restart pays Day 1", p.coins == cc + C[1][0].coins and p.daily.streak == 1, [p.coins - cc])
	p.daily.streak = 7; p.daily.cycle = 1; p.daily.last = day(10)
	st = R.daily_state(p, day(15))
	check("a finished cycle followed by a break starts the next cycle at Day 1", st.claimable and st.cycle == 2 and st.today == 0 and not st.missed, st)
	p.daily.streak = 7; p.daily.cycle = 2; p.daily.last = day(10)
	st = R.daily_state(p, day(11))
	check("after the last cycle the list starts over", st.claimable and st.cycle == 3 and st.rewards[0].reward == C[0][0], st)
	cc = p.coins
	R.claim_daily(p, day(11))
	check("cycle 4 pays cycle 1's amounts", p.coins == cc + C[0][0].coins, [p.coins - cc])

	# ---- items never given twice ----
	p = fresh()
	p.daily = {cycle = 0, streak = 3, last = day(-1), last_at = 1, history = []}
	p.dice_owned.append("crema")
	cc = p.coins
	var n0: int = p.dice_owned.size()
	st = R.daily_state(p, day(0))
	check("an owned dice skin shows as its coins", st.rewards[3].label == "400 coins" and st.rewards[3].grant.dice == "", st.rewards[3])
	r = R.claim_daily(p, day(0))
	check("an already-owned dice skin pays its coins instead", p.coins == cc + C[0][3]["or"] and p.dice_owned.size() == n0 and r.dice == "", [p.coins - cc, p.dice_owned])
	p = fresh()
	p.daily = {cycle = 0, streak = 3, last = day(-1), last_at = 1, history = []}
	st = R.daily_state(p, day(0))
	r = R.claim_daily(p, day(0))
	check("a new dice skin is added, with no coins", r.dice == "crema" and r.coins == 0 and p.dice_owned == ["classic", "crema"]
		and st.rewards[3].label == "Crema dice" and r.text == "Day 4: Crema dice unlocked", [r, p.dice_owned])
	st = R.daily_state(p, day(0))
	check("the claimed dice tile still shows the dice it gave", st.rewards[3].status == "claimed" and st.rewards[3].label == "Crema dice", st.rewards[3])
	st = R.daily_state(p, day(1))
	check("claimed tiles without history show their reward", st.rewards[0].label == "100 coins" and st.rewards[3].label == "Crema dice", st.rewards.map(func(t): return t.label))
	p.daily = {cycle = 0, streak = 6, last = day(-1), last_at = 1, history = []}
	p.av_owned = [C[0][6].char]
	cc = p.coins
	r = R.claim_daily(p, day(0))
	check("a character already owned pays its coins instead (Day 7)", p.coins == cc + C[0][6].coins + C[0][6]["or"] and r.text == "Day 7: +2K coins", [p.coins - cc, r])

	# ---- clock moved back, damaged data ----
	p = fresh()
	p.daily = {cycle = 0, streak = 2, last = day(1), last_at = 1, history = []}
	check("a claim dated in the future (clock moved back) cannot be repeated", not R.daily_state(p, day(0)).claimable and not R.claim_daily(p, day(0)).ok)
	p.daily = {cycle = -3, streak = 99, last = "garbage", history = "x"}
	st = R.daily_state(p, day(0))
	check("damaged saved data is repaired, not trusted", st.claimable and st.today == 0 and p.daily.streak == 0 and p.daily.cycle == 0 and p.daily.history is Array, p.daily)
	p.daily = {cycle = 1.0, streak = 4.0, last = day(-1), last_at = 5.0, history = []}   # numbers read back from JSON are floats
	st = R.daily_state(p, day(0))
	check("saved numbers read back from JSON keep the run", st.claimable and st.cycle == 1 and st.today == 4, st)
	p.erase("daily")
	check("a profile without daily data starts at Day 1", R.daily_state(p, day(0)).today == 0)
	p = fresh()
	for k in 70:
		R.claim_daily(p, day(k))
	check("the claim history keeps the last 60 claims", p.daily.history.size() == 60 and p.daily.history[-1].on == day(69), p.daily.history.size())

	# ---- separate profiles ----
	var a := fresh()
	var b := fresh()
	R.claim_daily(a, day(0)); R.claim_daily(a, day(1))
	check("another profile has its own calendar (Day 1 open)", R.daily_state(b, day(1)).claimable and R.daily_state(b, day(1)).today == 0, b.daily)
	R.claim_daily(b, day(1))
	check("claiming on one profile keeps the other's claim", not R.daily_state(a, day(1)).claimable and a.daily.streak == 2 and b.daily.streak == 1, [a.daily, b.daily])

	# ---- the first home visit of a day opens the calendar once ----
	p = fresh()
	check("a waiting reward opens the calendar by itself", R.should_auto_open(p, day(0)))
	R.mark_auto_open(p, day(0))
	check("only once that day", not R.should_auto_open(p, day(0)) and R.should_auto_open(p, day(1)))
	R.claim_daily(p, day(1))
	check("not once the day is claimed", not R.should_auto_open(p, day(1)))

	# ---- Daily Spin ----
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	p = fresh()
	check("the wheel has 8 prizes", R.PRIZES.size() == 8 and R.PRIZES == [100, 250, 150, 500, 100, 1000, 200, 300])
	check("a new player can spin", R.can_spin(p, day(0)))
	cc = p.coins
	r = R.spin(p, rng, day(0))
	check("a spin lands on a segment and pays its prize", r.ok and r.index >= 0 and r.index < 8 and r.prize == R.PRIZES[r.index] and p.coins == cc + r.prize
		and p.stats.coinsEarned == r.prize, [r, p.coins - cc])
	check("the spin is recorded for today", p.last_spin == day(0) and not R.can_spin(p, day(0)), p.last_spin)
	cc = p.coins
	r = R.spin(p, rng, day(0))
	check("a second spin the same day does nothing", not r.ok and r.index == -1 and p.coins == cc, r)
	check("the next day the wheel is ready again", R.can_spin(p, day(1)) and R.spin(p, rng, day(1)).ok)
	var seen := {}
	var total_ok := true
	for k in 400:
		var q := fresh(0)
		var s: Dictionary = R.spin(q, rng, day(0))
		seen[s.index] = true
		total_ok = total_ok and q.coins == R.PRIZES[s.index]
	check("every segment can come up, each paying its own prize", seen.size() == 8 and total_ok, seen.keys())
	var r1 := RandomNumberGenerator.new(); r1.seed = 99
	var r2 := RandomNumberGenerator.new(); r2.seed = 99
	check("the same random seed picks the same segment", R.spin(fresh(), r1, day(0)).index == R.spin(fresh(), r2, day(0)).index)

	# ---- Free Coins ----
	p = fresh()
	check("free coins are ready for a new player", R.free_ready(p, T0) and R.free_left_sec(p, T0) == 0)
	cc = p.coins
	var got: int = R.claim_free(p, T0)
	check("claiming pays 300 coins", got == 300 and R.FREE_AMOUNT == 300 and p.coins == cc + 300 and p.stats.coinsEarned == 300 and p.last_free == T0, [got, p.coins - cc])
	check("right after a claim it waits 4 hours", not R.free_ready(p, T0) and R.free_left_sec(p, T0) == 14400 and R.FREE_EVERY_SEC == 14400, R.free_left_sec(p, T0))
	cc = p.coins
	check("claiming early pays nothing", R.claim_free(p, T0 + 60) == 0 and p.coins == cc and p.last_free == T0)
	check("the countdown runs down", R.free_left_sec(p, T0 + 3600) == 10800 and R.free_left_sec(p, T0 + 14399) == 1 and not R.free_ready(p, T0 + 14399),
		[R.free_left_sec(p, T0 + 3600), R.free_left_sec(p, T0 + 14399)])
	check("4 hours later it is ready again", R.free_ready(p, T0 + 14400) and R.claim_free(p, T0 + 14400) == 300 and p.last_free == T0 + 14400)
	p.last_free = T0
	check("the Free Coins caption shows the time left, then Free Coins", R.free_caption(p, T0 + 60) == "3h 59m" and R.free_caption(p, T0 + 14400) == "Free Coins",
		[R.free_caption(p, T0 + 60), R.free_caption(p, T0 + 14400)])
	p.last_free = T0 + 999999
	check("a clock moved back never waits more than 4 hours", R.free_left_sec(p, T0) == 14400, R.free_left_sec(p, T0))

	# ---- reward coins reach the home counter (HomeScreen._fly_to: sheets host their own CoinFly) ----
	var root := Control.new()
	var layer := Control.new()
	var sheet := Control.new()
	root.add_child(layer)
	layer.add_child(sheet)
	var counter := Control.new()
	var other := Control.new()
	var fly := CoinFly.new()
	fly._target = counter
	sheet.add_child(fly)
	check("a CoinFly nested in a sheet is found for its counter", HomeScreen._fly_to(root, counter) == fly)
	check("a CoinFly aimed elsewhere doesn't hold the counter", HomeScreen._fly_to(root, other) == null)
	sheet.remove_child(fly)
	fly.free()
	check("no fly: nothing holds the counter", HomeScreen._fly_to(root, counter) == null)
	for n in [root, counter, other]:
		n.free()
	check("the daily sheet closes itself soon after a claim", DailySheet.AUTO_CLOSE_SEC > 0.0 and DailySheet.AUTO_CLOSE_SEC <= 1.2)
