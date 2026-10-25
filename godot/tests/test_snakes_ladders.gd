extends "res://tests/test_suite.gd"
## Port of the rule and turn checks in tests/snakes-ladders.js (board data, the landing rule, reward replay, setup,
## real turns with forced dice, rewards). The page checks there (landing / popups / pause / quit / win card) test
## the HTML interface and come back when the Godot screens exist. Both entry rules are covered: the default (any
## roll enters, moving from square 0) and the "Need a 1 to start" house rule (need_one).

func roll_until(g: Dictionary, done: Callable, rng: RandomNumberGenerator) -> void:   # computers roll until done
	for k in 200:
		if done.call():
			return
		SL.apply_roll(g, rng.randi_range(1, 6))

func run() -> void:
	var LA: Dictionary = SL.LADDERS
	var SN: Dictionary = SL.SNAKES

	# ---- board data and the landing rule ----
	check("every ladder goes up, every snake goes down", LA.keys().all(func(a): return LA[a] > a) and SN.keys().all(func(a): return SN[a] < a))
	check("no square is both a ladder foot and a snake head; 100 is never a snake head", LA.keys().all(func(k): return not SN.has(k)) and not SN.has(100))
	check("plain move", SL.land(10, 2) == {to = 12, steps = 2})
	for n1 in [false, true]:
		check("[need_one %s] off the board, a 1 enters on square 1 (no ladder there any more)" % n1, SL.land(0, 1, n1).to == 1 and SL.land(0, 1, n1).steps == 1 and not SL.land(0, 1, n1).has("ladder"))
	check("removed ladders: no 1 -> 38 and no 80 -> 100 in the board data", not LA.has(1) and not LA.has(80) and not LA.values().has(38) and not LA.values().has(100) and LA.size() == 7, LA)
	check("landing on 80 stays on 80; landing on 1 from the board stays on 1", SL.land(77, 3).to == 80 and not SL.land(77, 3).has("ladder") and SL.land(0, 1).to == 1)
	check("every remaining ladder still climbs", [[4, 14], [9, 31], [21, 42], [28, 84], [36, 44], [51, 67], [71, 91]].all(func(ft): return SL.land(ft[0] - 1, 1).to == ft[1] and SL.land(ft[0] - 1, 1).has("ladder")))
	check("every snake still slides", SN.keys().all(func(h): return SL.land(h - 2, 2).to == SN[h] and SL.land(h - 2, 2).has("snake")))
	check("need a 1: off the board, 2-6 never enter", [2, 3, 4, 5, 6].all(func(v): return SL.land(0, v, true).to == 0 and SL.land(0, v, true).has("wait")))
	check("default: off the board, every roll v moves to square v", [1, 2, 3, 5, 6].all(func(v): return SL.land(0, v).to == v and SL.land(0, v).steps == v and not SL.land(0, v).has("wait")))
	check("default: entering on a ladder foot climbs it (0 + 4 -> 4 -> 14)", SL.land(0, 4).to == 14 and SL.land(0, 4).has("ladder") and SL.land(0, 4).via == 4 and SL.land(0, 4).steps == 4)
	check("default: land() without the flag is the any-roll rule", SL.land(0, 3) == SL.land(0, 3, false) and SL.land(0, 3).to == 3)
	check("on the board every roll moves (no entry rule after entering)", [1, 2, 3, 5, 6].all(func(v): return SL.land(10, v).to != 10))
	check("landing on a ladder foot climbs it (4 -> 14)", SL.land(3, 1).to == 14 and SL.land(3, 1).has("ladder"))
	check("landing on a snake head slides down (16 -> 6)", SL.land(13, 3).to == 6 and SL.land(13, 3).has("snake"))
	check("overshooting 100 does not move", SL.land(97, 5).to == 97 and SL.land(97, 5).has("over"))
	check("exact roll reaches 100", SL.land(97, 3).to == 100)
	check("reward replay: a real path reaches 100", SL.replay_reaches_100([1, 3, 6, 1, 6, 3, 4, 6, 3]))   # 1, 4>14, 20, 21>42, 48, 51>67, 71>91, 97, 100
	check("reward replay: the old shortcut via 1 -> 38 no longer reaches 100", not SL.replay_reaches_100([1, 6, 6, 1, 4, 6, 3]))
	check("reward replay: invented rolls do not", not SL.replay_reaches_100([3]) and not SL.replay_reaches_100([7, 7]) and not SL.replay_reaches_100([2.5]))
	check("reward replay (need a 1): the same path without the entering 1 does not reach 100", not SL.replay_reaches_100([6, 6, 1, 4, 6, 3], true))
	check("reward replay (need a 1): the real path still reaches 100", SL.replay_reaches_100([1, 3, 6, 1, 6, 3, 4, 6, 3], true))
	check("reward replay (need a 1): waiting rolls before the 1 are replayed too", SL.replay_reaches_100([4, 2, 1, 3, 6, 1, 6, 3, 4, 6, 3], true) and not SL.replay_reaches_100([4, 2, 1, 3, 6, 1, 6, 3, 4, 6, 3]))
	check("reward replay (any roll): 4 > 14, 20, 21 > 42, 48, 51 > 67, 71 > 91, 97, 100", SL.replay_reaches_100([4, 6, 1, 6, 3, 4, 6, 3]) and not SL.replay_reaches_100([4, 6, 1, 6, 3, 4, 6, 3], true))
	check("reward replay: rolls that came through JSON (floats) still count", SL.replay_reaches_100(JSON.parse_string("[1, 3, 6, 1, 6, 3, 4, 6, 3]")) and SL.replay_reaches_100(JSON.parse_string("[1, 3, 6, 1, 6, 3, 4, 6, 3]"), true))

	# ---- setup ----
	var g := SL.new_game("cpu", 3, 2)
	check("vs Computer as Yellow with 2 computers", g.mode == "cpu" and g.players.size() == 3 and g.players[0].you and g.players[0].c == 2, g.players.map(func(p): return p.c))
	g = SL.new_game("local", 4)
	check("Pass & Play with 4 players", g.mode == "local" and g.players.size() == 4)
	check("new games default to any roll entering", g.need_one == false and SL.needs_one(g) == false and SL.new_game("cpu", 2).need_one == false)
	g = SL.new_game("cpu", 2, 1, {need_one = true})
	check("opts.need_one turns the house rule on", g.need_one == true and SL.needs_one(g) and g.players[0].c == 1)
	check("a state saved before the option reads as the default", not SL.needs_one({mode = "cpu"}))
	var rt: Dictionary = JSON.parse_string(JSON.stringify(g))
	check("state with need_one survives a JSON round trip", rt.need_one == true and rt.players.size() == 2)

	# ---- Pass & Play turns, default entry rule (any roll enters) ----
	g = SL.new_game("local", 2)
	var Q0: Dictionary = g.players[0]
	var Q1: Dictionary = g.players[1]
	var ev := SL.apply_roll(g, 3)
	check("any roll: a 3 off the board moves to square 3 and the turn passes", Q0.pos == 3 and g.turn == 1 and ev.any(func(e): return e.type == "move" and e.from == 0 and e.to == 3 and e.steps == 3), [Q0.pos, ev])
	check("any roll: no wait event", not ev.any(func(e): return e.type == "wait"))
	SL.apply_roll(g, 4)
	check("any roll: a 4 off the board climbs the ladder at 4 to 14", Q1.pos == 14 and Q1.ladders == 1 and g.turn == 0, Q1.pos)
	g = SL.new_game("local", 2)
	SL.apply_roll(g, 6)
	check("any roll: a 6 off the board moves to 6 and earns another roll", g.players[0].pos == 6 and g.turn == 0, [g.players[0].pos, g.turn])
	g = SL.new_game("local", 2)
	SL.apply_roll(g, 1)
	check("any roll: a 1 still enters on square 1", g.players[0].pos == 1 and g.turn == 1)

	# ---- Pass & Play turns, house rule "Need a 1 to start" ----
	g = SL.new_game("local", 2, 0, {need_one = true})
	var P0: Dictionary = g.players[0]
	var P1: Dictionary = g.players[1]
	check("Pass & Play with 2 players", g.players.size() == 2 and g.players.all(func(p): return not p.cpu and p.pos == 0))
	for v in [2, 3, 4, 5]:
		var wev := SL.apply_roll(g, v)
		check("need a 1: off the board, a %d does not enter and the turn passes" % v, P0.pos == 0 and g.turn == 1 and wev.any(func(e): return e.type == "wait"), [P0.pos, g.turn])
		g.turn = 0; g.phase = "roll"
	SL.apply_roll(g, 6)
	check("need a 1: off the board, a 6 does not enter but still earns another roll", P0.pos == 0 and g.turn == 0, [P0.pos, g.turn])
	g.sixes = 0
	SL.apply_roll(g, 1)
	check("need a 1: a 1 enters on square 1 (no climb) and the turn passes", P0.pos == 1 and P0.ladders == 0 and g.turn == 1, P0.pos)
	P0.pos = 3; P1.pos = 0; g.turn = 0
	SL.apply_roll(g, 1)
	check("after entering, a 1 is an ordinary move (3 -> 4 climbs to 14)", P0.pos == 14, P0.pos)
	P1.pos = 2                                     # already entered
	SL.apply_roll(g, 4)
	check("after entering, a 4 moves normally (2 -> 6)", P1.pos == 6 and g.turn == 0, P1.pos)
	g.turn = 1
	SL.apply_roll(g, 6)
	check("a 6 moves and the same player rolls again", P1.pos == 12 and g.turn == 1, g.turn)
	SL.apply_roll(g, 2)
	check("after the extra roll the turn passes", P1.pos == 14 and g.turn == 0, P1.pos)
	P0.pos = 13
	SL.apply_roll(g, 3)
	check("landing on 16 slides down the snake to 6", P0.pos == 6 and P0.snakes == 1, P0.pos)
	P1.pos = 97
	SL.apply_roll(g, 5)
	check("a roll past 100 leaves the player on 97", P1.pos == 97 and g.turn == 0, P1.pos)
	P0.pos = 40
	SL.apply_roll(g, 6); SL.apply_roll(g, 6); SL.apply_roll(g, 6)
	check("three 6s in a row: the third does not move and the turn ends", P0.pos == 52 and g.sixes == 0 and g.turn == 1, [P0.pos, g.turn])
	SL.apply_roll(g, 3)
	check("exactly 100 wins (Pass & Play: no coins)", g.phase == "over" and g.winner == 1 and SL.claim_win_reward(g) == 0, [g.winner])

	# ---- vs Computer: rewards and the computer's turn ----
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	g = SL.new_game("cpu", 2)
	check("vs Computer: you + 1 computer", g.players[0].you and g.players[1].cpu)
	SL.apply_roll(g, 2)
	roll_until(g, func(): return g.turn == 0, rng)
	check("the computer takes its own turn and hands back", g.players[1].rolls.size() >= 1 and g.turn == 0 and g.phase == "roll", g.players[1].rolls)
	var me: Dictionary = g.players[0]
	me.pos = 97; me.rolls = [1, 3, 6, 1, 6, 3, 4, 6]   # a real path that reaches 97
	SL.apply_roll(g, 3)
	var paid := SL.claim_win_reward(g)
	check("beating the computer pays 100 coins once", g.phase == "over" and paid == 100 and g.paid and SL.claim_win_reward(g) == 0, [paid, g.paid])
	check("a win pays no participation reward", SL.claim_play_reward(g) == 0)
	var gl := SL.new_game("cpu", 2)
	gl.players[1].pos = 97
	gl.turn = 1
	SL.apply_roll(gl, 3)
	var pr := SL.claim_play_reward(gl)
	check("losing to the computer pays the participation reward once", gl.phase == "over" and gl.winner == 1 and SL.claim_win_reward(gl) == 0 and pr == SL.PLAY_REWARD and SL.claim_play_reward(gl) == 0, [gl.phase, pr])
	var gp := SL.new_game("local", 2)
	gp.players[1].pos = 97
	gp.turn = 1
	SL.apply_roll(gp, 3)
	check("Pass & Play: no participation reward", gp.phase == "over" and SL.claim_play_reward(gp) == 0)
	check("tile squares: one format, Off board before the first move", SLMatch.SLTile.square_text(0) == "Off board" and SLMatch.SLTile.square_text(47) == "Square 47" and SLMatch.SLTile.square_text(47, true) == "Sq 47")
	check("tile squares: a 4-up row at 320 / 390 px uses the short form, a 2-up row the long one", not SLMatch.SLTile.fits_long(70) and not SLMatch.SLTile.fits_long(83) and SLMatch.SLTile.fits_long(112))
	g = SL.new_game("cpu", 2)
	g.players[0].pos = 97; g.players[0].rolls = []   # a position the recorded rolls cannot explain
	SL.apply_roll(g, 3)
	check("a win the rolls cannot explain pays nothing", g.phase == "over" and SL.claim_win_reward(g) == 0 and not g.paid)
	g = SL.new_game("cpu", 2)
	g.players[0].pos = 97; g.players[0].rolls = [4, 6, 1, 6, 3, 4, 6]   # any-roll path to 97 (4 > 14 at the start)
	SL.apply_roll(g, 3)
	check("any roll: the reward replay uses the game's rule (pays)", SL.claim_win_reward(g) == 100)
	g = SL.new_game("cpu", 2, 0, {need_one = true})
	g.players[0].pos = 97; g.players[0].rolls = [4, 6, 1, 6, 3, 4, 6]   # under need-a-1 these rolls never enter
	SL.apply_roll(g, 3)
	check("need a 1: the same rolls cannot explain the win (pays nothing)", g.phase == "over" and SL.claim_win_reward(g) == 0)

	# ---- standings ----
	g = SL.new_game("cpu", 4)
	g.players[0].pos = 40; g.players[1].pos = 72; g.players[2].pos = 0; g.players[3].pos = 40
	var st := SL.standings(g)
	check("standings mid-game: by square, ties in turn order", st.map(func(e): return e.idx) == [1, 0, 3, 2] and st.map(func(e): return e.place) == [1, 2, 3, 4], st)
	check("standings entries carry colour, name, progress", st[0].color == g.players[1].c and st[0].name == "Mocha" and is_equal_approx(st[0].progress, 0.72) and not st[0].finished)
	g.turn = 2; g.players[2].pos = 97
	SL.apply_roll(g, 3)
	st = SL.standings(g)
	check("standings after a computer's finish: it is first, you play on", g.phase == "roll" and g.finished == [2] and g.turn == 3 and st[0].idx == 2 and st[0].finished and st[0].place == 1 and st[1].idx == 1, [g.phase, g.finished, st])
	SL.end_game(g)
	check("end_game: the rest ranked by square (ties in turn order)", g.phase == "over" and g.winner == 2 and g.finished == [2, 1, 0, 3], g.finished)

	# ---- 3 and 4 players ----
	g = SL.new_game("cpu", 4)
	check("vs Computer with 4 players: 3 computers", g.players.size() == 4 and g.players.filter(func(p): return p.cpu).size() == 3)
	g = SL.new_game("local", 3)
	check("Pass & Play with 3 players", g.players.size() == 3 and g.players.all(func(p): return not p.cpu))
