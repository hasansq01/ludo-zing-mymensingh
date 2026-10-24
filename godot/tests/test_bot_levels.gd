extends "res://tests/test_suite.gd"
## Computer skill levels (pick_ai level "easy" / "normal" / "hard"): every pick is a legal move, the levels choose
## differently in telling positions, and in seeded self-play hard clearly beats easy. Dice are uniform throughout:
## the rules never touch rolls, so skill is only in the choice of move.

const GAMES := 200

## One all-computer 4-player game; levels[c] plays colour c. Counts illegal or refused picks into bad[0].
func game(levels: Array, rng: RandomNumberGenerator, bad: Array) -> int:
	var s := Ludo.new_game(["cpu", "cpu", "cpu", "cpu"])
	var rolls := 0
	while s.phase != "over" and rolls < 20000:
		rolls += 1
		Ludo.apply_roll(s, rng.randi_range(1, 6))
		if s.phase == "choose":
			var mv := Ludo.movables(s)
			var i := Ludo.pick_ai(s, mv, rng, levels[s.turn])
			if not mv.has(i) or Ludo.move(s, i).is_empty():
				bad[0] += 1
				return -1
	return s.winner

func run() -> void:
	var s: Dictionary
	var t: Array
	var rng := RandomNumberGenerator.new()
	var cpu := {players = ["cpu", "cpu", "cpu", "cpu"], names = ["A", "B", "C", "D"]}

	check("levels list", Ludo.LEVELS == ["easy", "normal", "hard"])
	s = state(base(), [], cpu.merged({dice = 4}))
	check("no legal move: -1 for every level", ["easy", "normal", "hard"].all(func(l): return Ludo.pick_ai(s, [], rng, l) == -1))
	check("default level is normal (same pick as level normal with the same seed)", _same_seed(s))

	# capture vs plain move: normal and hard take the capture
	t = base(); t[0][0] = 10; t[0][1] = 30; t[1][0] = prog(1, 14)
	s = state(t, [], cpu.merged({dice = 4, phase = "choose"}))
	var mv := Ludo.movables(s)
	check("normal takes the capture", Ludo.pick_ai(s, mv, rng, "normal") == 0)
	check("hard takes the capture", Ludo.pick_ai(s, mv, rng, "hard") == 0)
	# finishing move: easy takes it about half the time
	t = base(); t[0][0] = 52; t[0][1] = 10; t[0][2] = 20; t[0][3] = 30
	s = state(t, [], cpu.merged({dice = 4, phase = "choose"}))
	mv = Ludo.movables(s)
	var fin := 0
	rng.seed = 3
	for k in 400:
		if Ludo.pick_ai(s, mv, rng, "easy") == 0:
			fin += 1
	check("easy takes a finishing move about 50% + (random share)", fin > 200 and fin < 340, fin)   # 0.5 + 0.5 * 1/4
	check("normal and hard always finish", Ludo.pick_ai(s, mv, rng, "normal") == 0 and Ludo.pick_ai(s, mv, rng, "hard") == 0)
	# easy is random among the rest: every option gets picked
	t = base(); t[0][0] = 10; t[0][1] = 20; t[0][2] = 30; t[0][3] = 40
	s = state(t, [], cpu.merged({dice = 3, phase = "choose"}))
	mv = Ludo.movables(s)
	var seen := {}
	for k in 200:
		seen[Ludo.pick_ai(s, mv, rng, "easy")] = true
	check("easy spreads its picks over every legal move", seen.size() == 4, seen.keys())
	# hard avoids walking into a threat that normal ignores less strongly: two quiet options, one lands 1 ahead of
	# two enemy singles, the other stays out of reach
	t = base(); t[0][0] = 20; t[0][1] = 5; t[1][0] = prog(1, 23); t[1][1] = prog(1, 23)
	s = state(t, [], cpu.merged({dice = 4, phase = "choose", pairs = []}))
	mv = Ludo.movables(s)
	check("hard does not land right in front of two enemy pawns", Ludo.pick_ai(s, mv, rng, "hard") == 1, [mv, Ludo.risk(s, 0)])
	# hard runs from a threat: pawn 0 sits 2 ahead of an enemy single, pawn 1 is safe on a star
	t = base(); t[0][0] = 30; t[0][1] = 8; t[1][0] = prog(1, 28)
	s = state(t, [], cpu.merged({dice = 5, phase = "choose"}))
	mv = Ludo.movables(s)
	check("hard runs the threatened pawn out of range", Ludo.pick_ai(s, mv, rng, "hard") == 0)
	var t2 := base(); t2[0][1] = 8; t2[1][0] = prog(1, 6)
	check("risk(): a threatened pawn counts, one on a star does not", Ludo.risk(s, 0) > 0.0 and Ludo.risk(state(t2, [], cpu), 0) == 0.0)
	# hard pairs up on a threatened square: pawn 1 at 24 is threatened by two singles; a 4 brings pawn 0 onto it
	t = base(); t[0][0] = 20; t[0][1] = 24; t[0][2] = 40; t[1][0] = prog(1, 21); t[1][1] = prog(1, 22)
	s = state(t, [], cpu.merged({dice = 4, phase = "choose"}))
	mv = Ludo.movables(s)
	check("hard pairs up to protect a threatened pawn", Ludo.pick_ai(s, mv, rng, "hard") == 0, mv)
	var after := s.duplicate(true)
	Ludo.move(after, 0)
	check("…and the pair is out of reach of single pawns (risk drops)", after.pairs.size() == 1 and Ludo.risk(after, 0) < Ludo.risk(s, 0), [after.pairs, Ludo.risk(after, 0), Ludo.risk(s, 0)])
	# the state is never changed by thinking
	var before := JSON.stringify(s)
	Ludo.pick_ai(s, mv, rng, "hard")
	check("pick_ai never changes the state", JSON.stringify(s) == before)

	# ---- seeded self-play: hard (2 seats) vs easy (2 seats), seats swap every game ----
	rng.seed = 20261024
	var bad := [0]
	var hard_wins := 0
	var finished := 0
	for g in GAMES:
		var lv := ["hard", "easy", "hard", "easy"] if g % 2 == 0 else ["easy", "hard", "easy", "hard"]
		var w := game(lv, rng, bad)
		if w >= 0:
			finished += 1
			if lv[w] == "hard":
				hard_wins += 1
	check("self-play: every pick was a legal move", bad[0] == 0, bad[0])
	check("self-play: every game finished", finished == GAMES, finished)
	check("self-play: hard beats easy in at least 60%% of %d 4-player games" % GAMES, hard_wins >= GAMES * 0.6, hard_wins)
	# normal vs easy, a shorter run (normal is the current skill; it must stay well above easy)
	var normal_wins := 0
	for g in 60:
		var lv := ["normal", "easy", "normal", "easy"] if g % 2 == 0 else ["easy", "normal", "easy", "normal"]
		var w := game(lv, rng, bad)
		if w >= 0 and lv[w] == "normal":
			normal_wins += 1
	check("self-play: normal beats easy most of the time", normal_wins >= 36 and bad[0] == 0, normal_wins)

func _same_seed(s: Dictionary) -> bool:
	var t := base(); t[0][0] = 10; t[0][1] = 20; t[0][2] = 30
	var st: Dictionary = s.duplicate(true)
	st.tok = t; st.dice = 3; st.phase = "choose"
	var mv := Ludo.movables(st)
	var a := RandomNumberGenerator.new(); a.seed = 9
	var b := RandomNumberGenerator.new(); b.seed = 9
	var ok := true
	for k in 20:
		ok = ok and Ludo.pick_ai(st, mv, a) == Ludo.pick_ai(st, mv, b, "normal")
	return ok
