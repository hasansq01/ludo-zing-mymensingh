class_name NotifPlan
extends RefCounted
## The local notification policy (server/NOTIFICATIONS.md "N-GAME"), as pure functions: what to schedule when the
## app goes to the background. Notifications (scripts/net/notifications.gd) feeds it the clock and the reward times
## and hands the answer to the plugin.
##
##   NotifPlan.plan(now_unix, tz_offset_s, state) -> [{id, at, channel, title, body, link}], by time
##   state = {enabled (master, default true), rewards, reminders (the toggles, default true),
##            ready {daily, spin, free: unix time each becomes claimable (<= now: ready now; missing: unknown)},
##            last_play (unix, the close time; default now)}
##
## Rewards: one reminder per local calendar day at most, today and tomorrow only: the earliest ready reward, fired at
## max(ready, close + 2 h), naming everything ready by then, linking to the first. Daily and spin open again at local
## midnight and stay open until claimed; Free Coins stays ready once its wait is over.
## Come-back: 1, 3 and 7 days after the close, the copy chosen by the day from a small pool, linking home. A come-back
## on a day that already has a reward reminder is dropped.
## Quiet hours 22:00-09:00 (local): a time inside them moves to 09:00 plus a jitter of 0-40 minutes that depends only
## on the day, so a plan made twice gives the same times. Two notifications are never closer than 3 hours (the later
## one moves on).

const QUIET_FROM := 22 * 3600
const QUIET_TO := 9 * 3600
const JITTER_MIN := 41                  # 0..40 minutes
const SPACING := 3 * 3600
const CLOSE_GAP := 2 * 3600
const DAY := 86400
const COMEBACK_DAYS := [1, 3, 7]
const KEYS := ["daily", "spin", "free"]

const TITLE := "Ludo Zing"
## What each reward is called inside "Your daily reward and a free spin are waiting".
const NAMES := {daily = "your daily reward", spin = "a free spin", free = "free coins"}
const LINKS := {daily = "daily", spin = "spin", free = "free"}
## Come-back copy per day, [title, body]; the day number picks one.
const COMEBACK := {
	1: [["Your table is waiting", "Come back for a quick game of Ludo Zing."],
		["Ready for a game?", "Your pawns are lined up. Roll the dice!"],
		["Ludo Zing misses you", "One quick game before bed?"]],
	3: [["It's been a few days", "Your friends and the café are waiting. Fancy a game?"],
		["Time for a rematch?", "Jump back into Ludo Zing and roll a six."],
		["Free coins are stacking up", "Come back and spend them on something nice."]],
	7: [["We saved your seat", "It's been a week. Come back and play a round of Ludo Zing."],
		["A week without Ludo Zing?", "Your café is open. Come and roll the dice."],
		["Still your favourite game?", "Come back for a game and a daily reward."]],
}


# ---------- the plan ----------

static func plan(now: int, tz: int, state: Dictionary) -> Array:
	if not bool(state.get("enabled", true)):
		return []
	var close := int(state.get("last_play", now))
	var found := []
	var reward_days := {}
	if bool(state.get("rewards", true)):
		for c: Dictionary in _rewards(now, tz, close, state.get("ready", {}) if state.get("ready") is Dictionary else {}):
			found.append(c)
			reward_days[day_num(int(c.at), tz)] = true
	if bool(state.get("reminders", true)):
		for c: Dictionary in _comebacks(tz, close):
			if not reward_days.has(day_num(int(c.at), tz)):
				found.append(c)
	return space(found, tz)

## Candidates {id, at, channel, title, body, link} in time order with 3 h between any two (the later one moves on,
## out of the quiet hours again if it lands in them).
static func space(found: Array, tz: int) -> Array:
	var sorted := found.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at < b.at)
	var out := []
	var last := -(1 << 40)
	for c: Dictionary in sorted:
		var at := quiet(maxi(int(c.at), last + SPACING), tz)
		last = at
		out.append({id = c.id, at = at, channel = c.channel, title = c.title, body = c.body, link = c.link})
	return out

static func _rewards(now: int, tz: int, close: int, ready: Dictionary) -> Array:
	var items := []                      # {key, at}, in the fixed order (ties keep it)
	for key: String in KEYS:
		var at: Variant = ready.get(key)
		if (at is int or at is float) and int(at) > 0:
			items.append({key = key, at = int(at)})
	var out := []
	if items.is_empty():
		return out
	var today := day_start(now, tz)
	var days := {}
	for k in 2:
		var from := today + k * DAY
		var first := -1
		for it: Dictionary in items:
			if it.at < from + DAY:       # ready during or before this day: ready from the day's start at the latest
				var t := maxi(int(it.at), from)
				first = t if first < 0 else mini(first, t)
		if first < 0:
			continue
		var at := quiet(maxi(first, close + CLOSE_GAP), tz)
		if at >= today + 2 * DAY or days.has(day_num(at, tz)):
			continue
		days[day_num(at, tz)] = true
		var due := items.filter(func(it: Dictionary) -> bool: return it.at <= at)
		var lead: Dictionary = due[0]
		for it: Dictionary in due:
			if maxi(int(it.at), from) < maxi(int(lead.at), from):   # (a reward waiting since before the day starts with it)
				lead = it
		out.append({id = "rw%d" % k, at = at, channel = "rewards", title = TITLE, body = rewards_text(due.map(func(it: Dictionary) -> String: return it.key)),
			link = LINKS[lead.key]})
	return out

static func _comebacks(tz: int, close: int) -> Array:
	var out := []
	for n: int in COMEBACK_DAYS:
		var at := quiet(close + n * DAY, tz)
		var pool: Array = COMEBACK[n]
		var copy: Array = pool[posmod(day_num(close, tz) + n, pool.size())]
		out.append({id = "cb%d" % n, at = at, channel = "reminders", title = copy[0], body = copy[1], link = "home"})
	return out

## "Your daily reward and a free spin are waiting" for the keys that are ready (in the order given).
static func rewards_text(keys: Array) -> String:
	var names := keys.map(func(k: String) -> String: return NAMES[k])
	var list := ""
	if names.size() == 1:
		list = names[0]
	else:
		list = ", ".join(names.slice(0, -1)) + " and " + names[-1]
	list = list.substr(0, 1).to_upper() + list.substr(1)
	return list + (" is waiting" if keys.size() == 1 and keys[0] != "free" else " are waiting")


# ---------- offline reward times ----------

## When each reward becomes claimable from a profile and the rules of Rewards (the offline game): `now` when it is
## claimable now, else the next local midnight (daily, spin) or the end of the Free Coins wait.
static func ready_times(p: Dictionary, now: int, tz: int) -> Dictionary:
	var key := day_key(now, tz)
	var midnight := day_start(now, tz) + DAY
	var copy := p.duplicate()            # (daily_state repairs p.daily in place)
	return {
		daily = now if Rewards.daily_state(copy, key).claimable else midnight,
		spin = now if Rewards.can_spin(copy, key) else midnight,
		free = now + Rewards.free_left_sec(copy, now),
	}


# ---------- local time ----------

## Days since 1970 of the local day `unix` falls in.
static func day_num(unix: int, tz: int) -> int:
	return floori((unix + tz) / float(DAY))

## The unix time of that local day's midnight.
static func day_start(unix: int, tz: int) -> int:
	return day_num(unix, tz) * DAY - tz

static func day_key(unix: int, tz: int) -> String:
	var d := Time.get_date_dict_from_unix_time(unix + tz)
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]

static func in_quiet(unix: int, tz: int) -> bool:
	var s := posmod(unix + tz, DAY)
	return s >= QUIET_FROM or s < QUIET_TO

## A time outside the quiet hours: itself, or 09:00 (plus the day's jitter) of the morning it falls before.
static func quiet(unix: int, tz: int) -> int:
	if not in_quiet(unix, tz):
		return unix
	var day := day_num(unix, tz)
	if posmod(unix + tz, DAY) >= QUIET_FROM:
		day += 1
	return day * DAY - tz + QUIET_TO + jitter_min(day) * 60

## 0..40, the same for the same day.
static func jitter_min(day: int) -> int:
	return ((day * 2654435761) >> 8) % JITTER_MIN
