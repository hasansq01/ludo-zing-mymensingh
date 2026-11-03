extends "res://tests/test_suite.gd"
## Snakes & Ladders win reward vs the three-sixes rule: the third 6 in a row is recorded in the player's rolls but
## never moves the pawn, so the reward replay must skip it too. Before the fix the replay moved on it and a win
## after any three-sixes turn could go unpaid (about 6 % of wins).

## Plays a vs-Computer game to the end with seeded dice; returns the final state.
func _play(seed_: int, n: int, need_one := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var g := SL.new_game("cpu", n, 0, {need_one = need_one})
	for k in 5000:
		if g.phase == "over":
			break
		SL.apply_roll(g, rng.randi_range(1, 6))
	return g

func run() -> void:
	# ---- the replay mirrors the rule ----
	check("replay: the third 6 of a turn does not move (6, 6, 6 -> 12, then 88 more from 12 is not 100)",
		not SL.replay_reaches_100([6, 6, 6]) and SL.land(SL.land(0, 6).to, 6).to == 12)
	# 6, 6, (6: no move) -> 12; 2 -> 14; 1 -> 15; 5 -> 20; 1 -> 21 > 42; 6 -> 48; 3 -> 51 > 67; 4 -> 71 > 91; 6 -> 97; 3 -> 100
	var path := [6, 6, 6, 2, 1, 5, 1, 6, 3, 4, 6, 3]
	check("replay: a real win with three 6s at the start reaches 100", SL.replay_reaches_100(path), path)
	check("replay: the same rolls replayed as plain moves would not explain it",
		_naive(path) != 100, _naive(path))
	check("replay: a 6, 6 then a 5 is an ordinary turn (all three move)", SL.replay_reaches_100([6, 6, 5, 1, 6, 3, 4, 6, 3, 3]) == (_naive([6, 6, 5, 1, 6, 3, 4, 6, 3, 3]) == 100))

	# ---- the same win played through apply_roll pays ----
	var g := SL.new_game("cpu", 2)
	var me: Dictionary = g.players[0]
	var cpu_roll := 1
	for v in path:
		while g.turn != 0 and g.phase == "roll":
			SL.apply_roll(g, cpu_roll)            # the computer creeps along by 1s
		SL.apply_roll(g, v)
	check("three 6s then a real path: you win on 100", g.phase == "over" and g.winner == 0 and me.pos == 100, [g.phase, me.pos])
	check("three 6s then a real path: the win pays 100 coins", SL.claim_win_reward(g) == 100, me.rolls)
	var rt: Dictionary = MatchStore.ints(JSON.parse_string(JSON.stringify({rolls = me.rolls})))
	check("the rolls through JSON (a resumed game) still pay", SL.replay_reaches_100(rt.rolls), rt)

	# ---- many seeded games: every win you really made is paid ----
	for need_one in [false, true]:
		var wins := 0
		var unpaid := 0
		var with_three := 0
		for s in 400:
			var gg := _play(1000 + s, 2 + s % 3, need_one)
			if gg.phase != "over" or not gg.players[gg.winner].you:
				continue
			wins += 1
			if _has_three_sixes(gg.players[0].rolls):
				with_three += 1
			if SL.claim_win_reward(gg) != 100:
				unpaid += 1
		check("[need_one %s] seeded games: some of your wins had three 6s (the case is covered)" % need_one, with_three > 0, [wins, with_three])
		check("[need_one %s] seeded games: every one of your %d wins is paid" % [need_one, wins], wins > 0 and unpaid == 0, [wins, unpaid])

## Every roll replayed as a move (the old, wrong replay).
func _naive(rolls: Array) -> int:
	var pos := 0
	for v in rolls:
		pos = SL.land(pos, int(v)).to
		if pos == 100:
			return 100
	return pos

func _has_three_sixes(rolls: Array) -> bool:
	var run := 0
	for v in rolls:
		run = run + 1 if v == 6 else 0
		if run == 3:
			return true
	return false
