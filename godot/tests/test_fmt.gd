extends "res://tests/test_suite.gd"
## Fmt: the one formatter for coins, gains, shortfalls, clocks, durations and percents (web fmtCoins rule).

func run() -> void:
	# ---- short coins (index.html fmtCoins) ----
	var short := [0, 7, 999, 1000, 1200, 1250, 1999, 2550, 5300, 12000, 12500, 999999, 1000000, 1250000, 12000000]
	var want := ["0", "7", "999", "1K", "1.2K", "1.2K", "1.9K", "2.5K", "5.3K", "12K", "12.5K", "999.9K", "1M", "1.3M", "12M"]
	var got: Array = short.map(func(n: int) -> String: return Fmt.coins(n))
	check("coins: short web form", got == want, got)
	check("coins: negative keeps its sign", Fmt.coins(-2500) == "-2.5K", Fmt.coins(-2500))
	check("coins: thousands are cut, never rounded up", Fmt.coins(2999) == "2.9K", Fmt.coins(2999))

	# ---- full coins ----
	got = [Fmt.coins_full(0), Fmt.coins_full(999), Fmt.coins_full(1000), Fmt.coins_full(5300), Fmt.coins_full(1234567), Fmt.coins_full(-1200)]
	check("coins_full: grouped thousands", got == ["0", "999", "1,000", "5,300", "1,234,567", "-1,200"], got)

	# ---- gains and shortfalls ----
	got = [Fmt.gain(200), Fmt.gain(1200), Fmt.gain(1200, true), Fmt.gain(0), Fmt.gain(-50)]
	check("gain: signed amounts", got == ["+200", "+1,200", "+1.2K", "+0", "-50"], got)
	got = [Fmt.shortfall(2500), Fmt.shortfall(950), Fmt.shortfall(-5)]
	check("shortfall: Need N (short form)", got == ["Need 2.5K", "Need 950", "Need 0"], got)

	# ---- clock ----
	got = [Fmt.clock(3 * 3600 + 53 * 60 + 10), Fmt.clock(3600), Fmt.clock(53 * 60 + 10), Fmt.clock(5), Fmt.clock(0), Fmt.clock(-9), Fmt.clock(25 * 3600)]
	check("clock: h:mm:ss / m:ss", got == ["3:53:10", "1:00:00", "53:10", "0:05", "0:00", "0:00", "25:00:00"], got)

	# ---- until (same rule as Rewards.fmt_dur) ----
	got = [Fmt.until(13 * 3600 + 20 * 60), Fmt.until(5 * 60), Fmt.until(59), Fmt.until(0), Fmt.until(3600), Fmt.until(14399), Fmt.until(61)]
	check("until: rounds up to minutes", got == ["13h 20m", "5m", "1m", "1m", "1h 0m", "4h 0m", "2m"], got)
	var same := [59, 0, 3600, 14399, 47000].all(func(s: int) -> bool: return Fmt.until(s) == Rewards.fmt_dur(s))
	check("until matches Rewards.fmt_dur", same)

	# ---- pct ----
	got = [Fmt.pct(0.0), Fmt.pct(0.426), Fmt.pct(0.5), Fmt.pct(0.996), Fmt.pct(1.0), Fmt.pct(0.001), Fmt.pct(1.7), Fmt.pct(-0.2)]
	check("pct: whole percent, 100% only when done", got == ["0%", "43%", "50%", "99%", "100%", "1%", "100%", "0%"], got)

	check("EMPTY is an en dash", Fmt.EMPTY == "–")
	# the short form agrees with the older formatters it replaces
	var agree := [950, 1000, 1200, 2500, 2550, 2000, 1500000, 1200000].all(func(n: int) -> bool:
		return Fmt.coins(n) == Catalog.short(n) and Fmt.coins(n) == Rewards.fmt_coins(n))
	check("coins agrees with Catalog.short and Rewards.fmt_coins", agree)
