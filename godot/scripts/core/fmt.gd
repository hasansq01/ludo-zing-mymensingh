class_name Fmt
extends RefCounted
## The one place numbers, coins and times become text. Pure static functions, no state.
## Rule: chips, balances, prices and buttons use coins(); sentences use coins_full(); gains use gain();
## "Next ... in" notes use until(); a ticking caption uses clock().

## Shown for a value that does not exist yet (win rate with no games, an empty slot).
const EMPTY := "–"

## Short coin amount, the web rule (index.html fmtCoins): 999, 1K, 1.2K, 12K, 999.9K, 1.2M.
## Thousands are cut (2550 -> 2.5K, never rounded up to a value the player does not have); millions round to
## one decimal. A trailing ".0" is dropped. Negative amounts keep their sign.
static func coins(n: int) -> String:
	if n < 0:
		return "-" + coins(-n)
	if n < 1000:
		return str(n)
	if n < 1000000:
		return _trim("%.1f" % (floorf(n / 100.0) / 10.0)) + "K"
	return _trim("%.1f" % (floorf(n / 100000.0 + 0.5) / 10.0)) + "M"   # half up, like JS toFixed

## Full amount with thousands separators: 5300 -> "5,300", -1200 -> "-1,200".
static func coins_full(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## A gain: "+200", "+1,200" (short = true: "+1.2K"). Negative values show "-": gain(-50) -> "-50".
static func gain(n: int, short := false) -> String:
	var t := coins(absi(n)) if short else coins_full(absi(n))
	return ("-" if n < 0 else "+") + t

## A button / note for a price the player can't afford yet: shortfall(2500) -> "Need 2.5K".
static func shortfall(n: int) -> String:
	return L10n.t("Need %s") % coins(maxi(0, n))

## A ticking countdown: "3:53:10" (an hour or more), "53:10", "0:05". Negative counts as 0.
static func clock(sec: int) -> String:
	sec = maxi(0, sec)
	if sec >= 3600:
		return "%d:%02d:%02d" % [sec / 3600, (sec / 60) % 60, sec % 60]
	return "%d:%02d" % [sec / 60, sec % 60]

## Time left in words, rounded up to whole minutes: "13h 20m", "1h 0m", "5m"; anything under a minute (and 0) is
## "1m". Same rule as Rewards.fmt_dur.
static func until(sec: int) -> String:
	var m := maxi(1, ceili(sec / 60.0))
	return L10n.t("%dh %dm") % [m / 60, m % 60] if m >= 60 else L10n.t("%dm") % m

## A fraction (0..1) as a whole percent: 0.426 -> "43%". Never shows "100%" before it is done (0.996 -> "99%") or
## "0%" once something happened (0.001 -> "1%"). Clamped to 0..100.
static func pct(f: float) -> String:
	f = clampf(f, 0.0, 1.0)
	var v := roundi(f * 100.0)
	if f < 1.0:
		v = mini(v, 99)
	if f > 0.0:
		v = maxi(v, 1)
	return "%d%%" % v


static func _trim(s: String) -> String:
	return s.trim_suffix(".0")
