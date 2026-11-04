extends "res://tests/test_suite.gd"
## NotifPlan: the local reminder policy (quiet hours with a stable jitter, one reward reminder a day, close + 2 h,
## two days of horizon, come-back 1 / 3 / 7 days, 3 h between two, the toggles) and the offline reward times.

const H := 3600
const DAY := 86400

## Unix time of a local date and time in a zone `tz` seconds east of UTC.
func at(tz: int, d: int, h: int, m := 0) -> int:
	return int(Time.get_unix_time_from_datetime_dict({year = 2026, month = 10, day = d, hour = h, minute = m, second = 0})) - tz

func hm(unix: int, tz: int) -> int:
	return posmod(unix + tz, DAY) / 60

func ids(plan: Array) -> Array:
	return plan.map(func(n: Dictionary) -> String: return n.id)

func find(plan: Array, id: String) -> Dictionary:
	for n: Dictionary in plan:
		if n.id == id:
			return n
	return {}

func run() -> void:
	_quiet()
	_rewards()
	_comeback()
	_spacing()
	_sweep()
	_offline()
	_text()

func _quiet() -> void:
	for tz in [0, 6 * H, -5 * H, int(5.5 * H)]:
		var noon := at(tz, 26, 12)
		check("quiet %d: midday stays" % tz, NotifPlan.quiet(noon, tz) == noon)
		check("quiet %d: 21:59 is allowed, 22:00 is not" % tz, not NotifPlan.in_quiet(at(tz, 26, 21, 59), tz) and NotifPlan.in_quiet(at(tz, 26, 22), tz))
		check("quiet %d: 08:59 is quiet, 09:00 is not" % tz, NotifPlan.in_quiet(at(tz, 26, 8, 59), tz) and not NotifPlan.in_quiet(at(tz, 26, 9), tz))
		var late := NotifPlan.quiet(at(tz, 26, 23, 30), tz)
		var j := NotifPlan.jitter_min(NotifPlan.day_num(at(tz, 27, 12), tz))
		check("quiet %d: 23:30 moves to 09:00 + the day's jitter the next morning" % tz, late == at(tz, 27, 9, j), [late, at(tz, 27, 9, j)])
		var early := NotifPlan.quiet(at(tz, 26, 3), tz)
		check("quiet %d: 03:00 moves to 09:00 the same day" % tz, early == at(tz, 26, 9, NotifPlan.jitter_min(NotifPlan.day_num(at(tz, 26, 12), tz))))
	var ok := true
	var seen := {}
	for d in 800:
		var jm := NotifPlan.jitter_min(20000 + d)
		ok = ok and jm >= 0 and jm <= 40 and jm == NotifPlan.jitter_min(20000 + d)
		seen[jm] = true
	check("jitter: 0-40 minutes, stable per day, and it varies", ok and seen.size() > 20, seen.size())

func _rewards() -> void:
	var tz := 6 * H
	var close := at(tz, 26, 14)                       # Monday afternoon
	var s1 := at(tz, 27, 0)
	var ready := {daily = s1, spin = s1, free = close + 4 * H}
	var p := NotifPlan.plan(close, tz, {rewards = true, reminders = false, ready = ready})
	check("rewards: today's free coins, then tomorrow morning's everything", ids(p) == ["rw0", "rw1"], ids(p))
	var r0 := find(p, "rw0")
	check("rewards: day 0 at the free coins' time, naming only them", r0.at == close + 4 * H and r0.body == "Free coins are waiting" and r0.link == "free" and r0.channel == "rewards", r0)
	var r1 := find(p, "rw1")
	var j := NotifPlan.jitter_min(NotifPlan.day_num(s1, tz))
	check("rewards: day 1 is ready at midnight, so it goes at 09:00 + jitter", r1.at == at(tz, 27, 9, j), [r1.at, at(tz, 27, 9, j)])
	check("rewards: it names everything ready and links to the first", r1.body == "Your daily reward, a free spin and free coins are waiting" and r1.link == "daily" and r1.title == "Ludo Zing", r1)
	# close + 2 h: ready now, closing at 20:00
	var late := at(tz, 26, 20)
	var p2 := NotifPlan.plan(late, tz, {reminders = false, ready = {daily = late, spin = late, free = late}})
	check("rewards: ready now at 20:00 -> 22:00 is quiet, so the morning; day 1 would be the same morning: one reminder", ids(p2) == ["rw0"] and p2[0].at == at(tz, 27, 9, NotifPlan.jitter_min(NotifPlan.day_num(s1, tz))), p2)
	check("rewards: all three named, the daily first", p2[0].body == "Your daily reward, a free spin and free coins are waiting" and p2[0].link == "daily")
	var p3 := NotifPlan.plan(close, tz, {reminders = false, ready = {spin = close}})
	check("rewards: ready now at 14:00 -> close + 2 h (16:00), then tomorrow's", ids(p3) == ["rw0", "rw1"] and p3[0].at == close + 2 * H and p3[0].link == "spin" and p3[0].body == "A free spin is waiting", p3)
	# the horizon: today and tomorrow only
	var p4 := NotifPlan.plan(close, tz, {reminders = false, ready = {free = close + 5 * DAY}})
	check("rewards: nothing ready in the next two days: nothing scheduled", p4.is_empty(), p4)
	var p5 := NotifPlan.plan(close, tz, {reminders = false, ready = {free = at(tz, 27, 14)}})
	check("rewards: a reward ready tomorrow afternoon gives one reminder, tomorrow at that time", ids(p5) == ["rw1"] and p5[0].at == at(tz, 27, 14), p5)
	var p6 := NotifPlan.plan(at(tz, 26, 23, 30), tz, {reminders = false, ready = {daily = at(tz, 26, 23, 30)}})
	check("rewards: closing near midnight never reaches the third day", p6.all(func(n): return n.at < at(tz, 28, 0)), p6)
	# unknown rewards
	check("rewards: no times known: nothing", NotifPlan.plan(close, tz, {reminders = false, ready = {}}).is_empty())
	check("rewards: the toggle off: no reward reminders", NotifPlan.plan(close, tz, {rewards = false, reminders = false, ready = ready}).is_empty())
	check("master off: nothing at all", NotifPlan.plan(close, tz, {enabled = false, ready = ready}).is_empty())
	# one per day, in a negative zone too (the local day, not the UTC one)
	var west := -8 * H
	var wclose := at(west, 26, 19)
	var pw := NotifPlan.plan(wclose, west, {reminders = false, ready = {daily = wclose, free = wclose}})
	var days := {}
	for n: Dictionary in pw:
		days[NotifPlan.day_num(n.at, west)] = true
	check("rewards: one per local day (UTC-8)", days.size() == pw.size() and not pw.is_empty(), pw)
	# the default: everything on
	var d := NotifPlan.plan(close, tz, {ready = ready})
	check("defaults: both kinds on", d.size() > 2 and find(d, "cb3").has("at"), ids(d))

func _comeback() -> void:
	var tz := 6 * H
	var close := at(tz, 26, 14)
	var p := NotifPlan.plan(close, tz, {rewards = false, ready = {}})
	check("come-back: 1, 3 and 7 days after the close", ids(p) == ["cb1", "cb3", "cb7"], ids(p))
	check("come-back: at the same time of day", p[0].at == close + DAY and p[1].at == close + 3 * DAY and p[2].at == close + 7 * DAY, p.map(func(n): return n.at))
	check("come-back: reminders channel, home link, own copy", p.all(func(n): return n.channel == "reminders" and n.link == "home" and n.title != "" and n.body != ""))
	check("come-back: the three days read differently", p[0].body != p[1].body and p[1].body != p[2].body)
	check("come-back: the same close gives the same plan", NotifPlan.plan(close, tz, {rewards = false, ready = {}}) == p)
	var titles := {}
	for k in 6:
		titles[NotifPlan.plan(close + k * DAY, tz, {rewards = false, ready = {}})[0].title] = true
	check("come-back: the copy varies by day", titles.size() >= 3, titles)
	var no_ludo_king := true
	for key in NotifPlan.COMEBACK:
		for c: Array in NotifPlan.COMEBACK[key]:
			no_ludo_king = no_ludo_king and not (c[0] + c[1]).contains("King")
	check("come-back: copy never says Ludo King", no_ludo_king)
	check("come-back: the toggle off: none", NotifPlan.plan(close, tz, {reminders = false, rewards = false, ready = {}}).is_empty())
	# a come-back on a day with a reward reminder is dropped
	var s1 := at(tz, 27, 0)
	var both := NotifPlan.plan(close, tz, {ready = {daily = s1, spin = s1, free = close + 4 * H}})
	check("come-back: day 1 has the reward reminder, so cb1 is dropped (3 and 7 stay)", ids(both) == ["rw0", "rw1", "cb3", "cb7"], ids(both))
	# a night-time close: the come-back moves out of the quiet hours
	var night := at(tz, 26, 23, 15)
	var pn := NotifPlan.plan(night, tz, {rewards = false, ready = {}})
	check("come-back: 23:15 + 1 day is quiet: 09:00 + jitter the day after", not NotifPlan.in_quiet(pn[0].at, tz) and hm(pn[0].at, tz) >= 540 and hm(pn[0].at, tz) <= 580 and pn[0].at > night + DAY)

func _spacing() -> void:
	var tz := 0
	var mk := func(id: String, t: int) -> Dictionary:
		return {id = id, at = t, channel = "rewards", title = "t", body = "b", link = "home"}
	var out := NotifPlan.space([mk.call("b", at(tz, 26, 13)), mk.call("a", at(tz, 26, 12))], tz)
	check("space: sorted by time, 3 h apart (the later moves on)", ids(out) == ["a", "b"] and out[0].at == at(tz, 26, 12) and out[1].at == at(tz, 26, 15), out)
	var out2 := NotifPlan.space([mk.call("a", at(tz, 26, 20)), mk.call("b", at(tz, 26, 21))], tz)
	check("space: a push-back into the quiet hours goes on to the morning", out2[1].at > at(tz, 27, 9) - 1 and not NotifPlan.in_quiet(out2[1].at, tz), out2)
	var out3 := NotifPlan.space([mk.call("a", at(tz, 26, 12)), mk.call("b", at(tz, 26, 15))], tz)
	check("space: exactly 3 h apart is fine", out3[1].at == at(tz, 26, 15))
	check("space: nothing in, nothing out", NotifPlan.space([], tz).is_empty())

## Whatever the close time, zone and reward times: sorted, never in the quiet hours, 3 h apart, unique ids.
func _sweep() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bad := []
	for k in 400:
		var tz: int = [0, 6 * H, -5 * H, int(5.5 * H), 13 * H, -11 * H][k % 6]
		var close := at(0, 26, 0) + rng.randi_range(0, 3 * DAY)
		var ready := {}
		for key in ["daily", "spin", "free"]:
			if rng.randf() < 0.8:
				ready[key] = close + rng.randi_range(-2 * H, 40 * H)
		var p := NotifPlan.plan(close, tz, {ready = ready, last_play = close})
		var good := true
		var seen := {}
		for i in p.size():
			var n: Dictionary = p[i]
			good = good and not seen.has(n.id) and not NotifPlan.in_quiet(n.at, tz) and n.at > close
			seen[n.id] = true
			if i > 0:
				good = good and n.at - p[i - 1].at >= 3 * H
		if not good:
			bad.append([k, tz, close, ready])
	check("sweep: sorted, outside the quiet hours, 3 h apart, unique, after the close (400 random cases)", bad.is_empty(), bad.slice(0, 2))

func _offline() -> void:
	var tz := 6 * H
	var now := at(tz, 26, 15)
	var key := "2026-10-26"
	check("day key follows the zone", NotifPlan.day_key(at(0, 26, 20), tz) == "2026-10-27" and NotifPlan.day_key(at(tz, 26, 3), tz) == key)
	var fresh := {daily = {}, last_spin = "", last_free = 0}
	var t := NotifPlan.ready_times(fresh, now, tz)
	check("offline: a fresh profile has all three ready now", t.daily == now and t.spin == now and t.free == now, t)
	var used := {daily = {cycle = 0, streak = 1, last = key, last_at = now - H}, last_spin = key, last_free = now - H}
	var u := NotifPlan.ready_times(used, now, tz)
	check("offline: claimed today: daily and spin at the next local midnight, free coins 3 h from now", u.daily == at(tz, 27, 0) and u.spin == at(tz, 27, 0) and u.free == now + 3 * H, u)
	var old := {daily = {cycle = 0, streak = 3, last = "2026-10-24", last_at = 1}, last_spin = "2026-10-25", last_free = now - 5 * H}
	var o := NotifPlan.ready_times(old, now, tz)
	check("offline: an earlier day claimed: ready now (the free wait is over)", o.daily == now and o.spin == now and o.free == now, o)
	check("offline: the profile is not touched", used.daily.streak == 1 and used.daily.last == key and not used.daily.has("history"))

func _text() -> void:
	check("text: one reward", NotifPlan.rewards_text(["daily"]) == "Your daily reward is waiting" and NotifPlan.rewards_text(["spin"]) == "A free spin is waiting" and NotifPlan.rewards_text(["free"]) == "Free coins are waiting")
	check("text: two", NotifPlan.rewards_text(["daily", "spin"]) == "Your daily reward and a free spin are waiting" and NotifPlan.rewards_text(["spin", "free"]) == "A free spin and free coins are waiting")
	check("text: three", NotifPlan.rewards_text(["daily", "spin", "free"]) == "Your daily reward, a free spin and free coins are waiting")
