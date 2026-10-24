extends "res://tests/test_suite.gd"
## Port of tests/pair-rules.js (25 checks): pair forming, movement, blocking, capture, start squares, regressions.

func run() -> void:
	var cpu := {players = ["human", "cpu", "cpu", "cpu"], names = ["You", "Mocha", "Biscotti", "Espresso"]}
	var b_at := func(a): return prog(3, a)
	var s: Dictionary
	var t: Array

	# ---- Formation ----
	t = base(); t[0][0] = 10; t[0][1] = 10; s = state(t, [], cpu)
	check("2. same-colour pawns on a plain track square can pair", Ludo.pair_partner(s, 0, 1) == 0, Ludo.pair_partner(s, 0, 1))
	t = base(); t[0][0] = 0; t[0][1] = 0; s = state(t, [], cpu)
	check("1. no pair offered on own start square (Home Base cell)", Ludo.pair_partner(s, 0, 1) == -1)
	t = base(); t[0][0] = 13; t[0][1] = 13; s = state(t, [], cpu)
	check("1. no pair offered on an opponent start square", Ludo.pair_partner(s, 0, 1) == -1)
	t = base(); t[0][0] = 10; t[0][1] = 12; s = state(t, [], cpu)
	check("passing over a pawn does not offer a pair", Ludo.pair_partner(s, 0, 1) == -1)
	t = base(); t[0][0] = 10; t[0][1] = 10; t[0][2] = 10; s = state(t, [{c = 0, a = 0, b = 1}], cpu)
	check("no pairing with pawns already in a pair", Ludo.pair_partner(s, 0, 2) == -1)
	t = base(); t[0][0] = 53; t[0][1] = 53; s = state(t, [], cpu)
	check("no pairing inside the home column", Ludo.pair_partner(s, 0, 1) == -1)

	# ---- Pair movement ----
	t = base(); t[0][0] = 10; t[0][1] = 10; s = state(t, [{c = 0, a = 0, b = 1}], cpu)
	check("10. pair: 2 → 1 cell, 4 → 2, 6 → 3", Ludo.dest(s, 0, 0, 2) == 11 and Ludo.dest(s, 0, 0, 4) == 12 and Ludo.dest(s, 0, 0, 6) == 13)
	check("11. pair cannot use 1, 3 or 5", [1, 3, 5].all(func(d): return Ludo.dest(s, 0, 0, d) == Ludo.NO_MOVE))
	check("either pawn of a pair gives the same move", Ludo.dest(s, 0, 1, 4) == Ludo.dest(s, 0, 0, 4))
	t = base(); t[0][0] = 10; t[0][1] = 10; t[0][2] = 5; s = state(t, [{c = 0, a = 0, b = 1}], cpu.merged({dice = 3}))
	check("11. odd roll still moves a normal pawn", Ludo.movables(s) == [2], Ludo.movables(s))

	# ---- Blocking ----
	t = base(); t[0][0] = 10; t[0][1] = 10; t[3][0] = b_at.call(7); s = state(t, [{c = 0, a = 0, b = 1}], cpu.merged({turn = 3}))
	check("6. single cannot jump an opponent pair", Ludo.dest(s, 3, 0, 5) == Ludo.NO_MOVE)
	check("6. single may land on the pair square", Ludo.dest(s, 3, 0, 3) == b_at.call(10))
	t[3][0] = b_at.call(10)
	check("6. single on the pair square passes only with a 1", Ludo.dest(s, 3, 0, 1) == b_at.call(11) and [2, 3, 4, 5, 6].all(func(d): return Ludo.dest(s, 3, 0, d) == Ludo.NO_MOVE))
	t = base(); t[0][0] = 10; t[0][1] = 10; t[3][0] = b_at.call(9); t[3][1] = b_at.call(9)
	s = state(t, [{c = 0, a = 0, b = 1}, {c = 3, a = 0, b = 1}], cpu.merged({turn = 3}))
	check("7. a pair passes an opponent pair on an even roll (no 1 needed)", Ludo.dest(s, 3, 0, 4) == b_at.call(11) and Ludo.dest(s, 3, 0, 6) == b_at.call(12), [Ludo.dest(s, 3, 0, 4), Ludo.dest(s, 3, 0, 6)])
	t[3][0] = b_at.call(10); t[3][1] = b_at.call(10)
	check("7. a pair sharing a square with an opponent pair can leave on an even roll", Ludo.dest(s, 3, 0, 2) == b_at.call(11))
	check("7. … but still never on an odd roll", Ludo.dest(s, 3, 0, 1) == Ludo.NO_MOVE)

	# ---- Capture ----
	t = base(); t[0][0] = 10; t[0][1] = 10; t[3][0] = b_at.call(7); s = state(t, [{c = 0, a = 0, b = 1}], cpu.merged({turn = 3}))
	check("a single pawn cannot capture a pair", Ludo.victims_at(s, 3, b_at.call(10), false).is_empty())
	t = base(); t[0][0] = 10; t[0][1] = 10; t[3][0] = b_at.call(9); t[3][1] = b_at.call(9)
	s = state(t, [{c = 0, a = 0, b = 1}, {c = 3, a = 0, b = 1}], cpu.merged({turn = 3}))
	check("a pair captures a pair (both pawns)", Ludo.victims_at(s, 3, b_at.call(10), true) == [[0, 0], [0, 1]])
	t = base(); t[0][0] = 8; t[0][1] = 8; t[3][0] = b_at.call(6); t[3][1] = b_at.call(6)
	s = state(t, [{c = 0, a = 0, b = 1}, {c = 3, a = 0, b = 1}], cpu.merged({turn = 3}))
	check("no pair capture on a safe square", Ludo.victims_at(s, 3, b_at.call(8), true).is_empty())
	t = base(); t[0][2] = 10; t[0][3] = 10; t[3][0] = b_at.call(7); s = state(t, [], cpu.merged({turn = 3}))
	check("a single still captures only one of a loose stack", Ludo.victims_at(s, 3, b_at.call(10), false).size() == 1)

	# ---- Start squares (Home Base cells) ----
	check("3/4. start squares of every colour count", [0, 13, 26, 39].all(func(p): return Ludo.on_start_square(0, p)))
	check("5. plain and star squares do not", [10, 8, 21].all(func(p): return not Ludo.on_start_square(0, p)))

	# ---- Regression for normal pawns ----
	t = base(); t[0][3] = 50; s = state(t, [], cpu)
	check("15. leave base only on a 6", Ludo.dest(s, 0, 0, 6) == 0 and Ludo.dest(s, 0, 0, 5) == Ludo.NO_MOVE)
	var finish_ok := Ludo.dest(s, 0, 3, 6) == 56
	s.tok[0][3] = 53
	check("15. exact roll to finish", finish_ok and Ludo.dest(s, 0, 3, 4) == Ludo.NO_MOVE)
	t = base(); t[0][0] = 20; t[0][1] = 20; s = state(t, [{c = 0, a = 0, b = 1}], cpu)
	check("13. stuck message for a pair on an odd roll", Ludo.stuck_reason(s, 0, 3) == "A pair needs an even roll.")
