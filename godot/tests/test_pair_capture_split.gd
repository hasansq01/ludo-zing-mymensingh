extends "res://tests/test_suite.gd"
## Port of tests/pair-capture-split.js (151 checks): pair capture rules (static and real moves) and the automatic
## pair split on every home-lane cell, for all four colours.

const NAMES := ["Red", "Green", "Yellow", "Blue"]

func run() -> void:
	const R := 0
	const B := 3
	var b_at := func(a): return prog(B, a)
	var s: Dictionary
	var t: Array

	# ---- 1. Capture rules (static) ----
	t = base(); t[R][0] = 10; t[R][1] = 10; t[B][0] = b_at.call(12); s = state(t, [{c = R, a = 0, b = 1}])
	check("static: a pair landing on a single captures nothing", Ludo.victims_at(s, R, 12, true).is_empty(), Ludo.victims_at(s, R, 12, true))
	t = base(); t[R][0] = 10; t[B][0] = b_at.call(12); t[B][1] = b_at.call(12); s = state(t, [{c = B, a = 0, b = 1}])
	check("static: a single landing on a pair captures nothing", Ludo.victims_at(s, R, 12, false).is_empty())
	t = base(); t[R][0] = 10; t[R][1] = 10; t[B][0] = b_at.call(12); t[B][1] = b_at.call(12); t[B][2] = b_at.call(12)
	s = state(t, [{c = R, a = 0, b = 1}, {c = B, a = 0, b = 1}])
	check("static: on a square with a pair and a single, a pair takes only the pair", Ludo.victims_at(s, R, 12, true) == [[3, 0], [3, 1]], Ludo.victims_at(s, R, 12, true))
	check("static: …and a single takes only the single", Ludo.victims_at(s, R, 12, false) == [[3, 2]], Ludo.victims_at(s, R, 12, false))

	# ---- 1. Capture rules (real moves) ----
	t = base(); t[R][0] = 10; t[R][1] = 10; t[B][0] = b_at.call(12); s = state(t, [{c = R, a = 0, b = 1}])
	play(s, 4)
	check("real: a pair moving onto a single does not capture it; both share the square", s.tok[R][0] == 12 and s.tok[R][1] == 12 and s.tok[B][0] == b_at.call(12) and s.pairs.size() == 1, s.tok)
	check("real: …no capture means no extra roll (turn passes on a 4)", s.turn != R, s.turn)

	t = base(); t[R][0] = 10; t[B][0] = b_at.call(12); t[B][1] = b_at.call(12); s = state(t, [{c = B, a = 0, b = 1}])
	play(s, 2)
	check("real: a single moving onto a pair does not capture it", s.tok[R][0] == 12 and s.tok[B][0] == b_at.call(12) and s.tok[B][1] == b_at.call(12) and s.pairs.any(func(q): return q.c == B), [s.tok, s.pairs])

	t = base(); t[R][0] = 10; t[R][1] = 10; t[B][0] = b_at.call(12); t[B][1] = b_at.call(12); s = state(t, [{c = R, a = 0, b = 1}, {c = B, a = 0, b = 1}])
	play(s, 4)
	check("real: a pair moving onto a pair captures both pawns and rolls again", s.tok[B][0] == -1 and s.tok[B][1] == -1 and not s.pairs.any(func(q): return q.c == B) and s.turn == R, [s.tok[B], s.turn])

	t = base(); t[R][0] = 10; t[B][0] = b_at.call(12); s = state(t)
	play(s, 2)
	check("real: a single still captures a single (unchanged)", s.tok[B][0] == -1 and s.turn == R, [s.tok[B], s.turn])

	t = base(); t[R][0] = 6; t[R][1] = 6; t[B][0] = b_at.call(8); s = state(t, [{c = R, a = 0, b = 1}])
	play(s, 4)
	check("real: safe squares still protect (pair on a star with a single)", s.tok[B][0] == b_at.call(8) and s.tok[R][0] == 8, s.tok)

	# ---- 2. Automatic split on every home-lane cell (progress 51-55), all four colours ----
	# 51-53 are reached straight from the track (a pair moves half the roll); 54-55 can only be reached by a pair that
	# was already in the lane (e.g. a game saved before this rule), so those start from 52 / 53.
	var cases := [[50, 2, 51], [50, 4, 52], [50, 6, 53], [52, 4, 54], [53, 4, 55], [49, 4, 51], [48, 6, 51]]
	for c in 4:
		for cs in cases:
			var from: int = cs[0]
			var d: int = cs[1]
			var to: int = cs[2]
			t = base(); t[c][0] = from; t[c][1] = from; t[c][2] = 56; t[c][3] = 56   # spare pawns home, so a 6 has only the pair to move
			var other := (c + 1) % 4
			t[other][0] = 20                                                         # a bystander that must not change
			s = state(t, [{c = c, a = 0, b = 1}], {turn = c})
			check("%d: pair at %d can move %d to %d" % [c, from, d, to], Ludo.dest(s, c, 0, d) == to, Ludo.dest(s, c, 0, d))
			play(s, d)
			var count := 0
			for row in s.tok:
				count += row.size()
			var ok: bool = s.tok[c][0] == to and s.tok[c][1] == to and s.tok[c][2] == 56 and s.tok[c][3] == 56 \
				and s.pairs.is_empty() and s.tok[other][0] == 20 and count == 16
			check("%s: pair %d +%d lands on lane cell %d and splits once into two singles there" % [NAMES[c], from, d, to], ok, [s.tok[c], s.pairs])
			check("%s %d: the split leaves no pairing offer and the turn follows the roll" % [NAMES[c], to], s.turn == (c if d == 6 else (c + 1) % 4), s.turn)
			# afterwards the two pawns move independently under the normal rules
			s.turn = c; s.phase = "roll"; s.sixes = 0
			var before := JSON.stringify([s.tok, s.pairs])
			play(s, 1, 0)
			check("%s %d: a 1 then moves one pawn alone (odd rolls are fine: no longer a pair)" % [NAMES[c], to], s.tok[c][0] == to + 1 and s.tok[c][1] == to and s.pairs.is_empty(), [before, s.tok[c]])
			if to + 2 <= 56:
				s.turn = c; s.phase = "roll"; s.sixes = 0
				play(s, 1, 1)
				check("%s %d: the other pawn moves on its own too" % [NAMES[c], to], s.tok[c][1] == to + 1 and s.tok[c][0] == to + 1 and s.pairs.is_empty(), s.tok[c])

	# ---- Unchanged pair behaviour elsewhere ----
	t = base(); t[R][0] = 10; t[R][1] = 10; s = state(t, [{c = R, a = 0, b = 1}])
	play(s, 4)
	check("a pair on a plain track square stays a pair", s.tok[R][0] == 12 and s.pairs.size() == 1, [s.tok[R], s.pairs])
	t = base(); t[R][0] = 11; t[R][1] = 11; s = state(t, [{c = R, a = 0, b = 1}])
	play(s, 4)
	check("a pair still splits on a start square (Green 13)", s.tok[R][0] == 13 and s.tok[R][1] == 13 and s.pairs.is_empty(), [s.tok[R], s.pairs])
	t = base(); t[R][0] = 48; t[R][1] = 48; t[R][2] = 50; s = state(t, [{c = R, a = 0, b = 1}])
	check("a pair one cell before the lane cannot reach the centre in one move", Ludo.dest(s, R, 0, 6) == 51)
	t = base(); t[R][0] = 54; t[R][1] = 54; s = state(t, [{c = R, a = 0, b = 1}])
	play(s, 4)
	check("a legacy pair in the lane that reaches the centre finishes both pawns", s.tok[R][0] == 56 and s.tok[R][1] == 56 and s.pairs.is_empty(), s.tok[R])

	# Pair Mode: a team-mate pawn is never captured, by a pair or a single
	t = base(); t[0][0] = 10; t[0][1] = 10; t[2][0] = prog(2, 12); s = state(t, [{c = 0, a = 0, b = 1}], {teams = true})
	check("Pair Mode: a pair landing on a partner single captures nothing", Ludo.victims_at(s, 0, 12, true).is_empty())
