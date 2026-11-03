extends "res://tests/test_suite.gd"
## SLStateHash (the online Snakes & Ladders state hash, server/PROTOCOL.md "S&L state hash"): the PROTOCOL.md
## fresh-game example, which fields are hashed, JSON round trips (numbers come back as floats), and the same strings
## / values as server/test/rules_sl_hash.test.ts (the TS twin). Every step of the recorded S&L parity traces is also
## checked against the TS hash by server/test/rules_sl_parity.test.ts.

const SLH := preload("res://scripts/net/sl_state_hash.gd")

const FRESH_LOCAL_2P := "0|roll|0|-1|0|0.0.0.0.0.,1.0.0.0.0.|"

func run() -> void:
	var s := SL.new_game("local", 2)
	check("fresh 2-player Pass & Play game: the PROTOCOL.md string", SLH.input(s) == FRESH_LOCAL_2P, SLH.input(s))
	check("fresh 2-player Pass & Play game: the TS value", SLH.of(s) == "edd54d53", SLH.of(s))

	s = SL.new_game("cpu", 3, 2, {need_one = true})
	s.players[0].pos = 42; s.players[0].ladders = 2; s.players[0].snakes = 1; s.players[0].rolls = [1, 3, 6, 6, 2]
	s.players[2].cpu = false; s.players[1].pos = 7; s.players[1].rolls = [4, 3]
	s.turn = 1; s.sixes = 2; s.phase = "over"; s.winner = 0
	var want := "1|over|2|0|1|2.42.0.2.1.13662,3.7.1.0.0.43,0.0.0.0.0.|"
	check("every hashed field in the string (same as the TS test)", SLH.input(s) == want, SLH.input(s))
	var h := SLH.of(s)
	check("the TS value", h == "a78c39c4", h)
	var other := s.duplicate(true)
	other.mode = "local"; other.paid = true; other.players[0].name = "Shihab"; other.players[0].you = false
	check("mode, paid, name and you are not hashed", SLH.of(other) == h)
	var no_opt := s.duplicate(true)
	no_opt.erase("need_one")
	check("a state without need_one hashes it as 0", SLH.input(no_opt) == "1|over|2|0|0|2.42.0.2.1.13662,3.7.1.0.0.43,0.0.0.0.0.|", SLH.input(no_opt))
	var fin := s.duplicate(true)
	fin.finished = [0, 2, 1]
	check("finished (play on) is hashed: the TS string", SLH.input(fin) == want + "0,2,1", SLH.input(fin))
	var no_fin := s.duplicate(true)
	no_fin.erase("finished")
	check("a state from before play on (no finished) hashes as none", SLH.of(no_fin) == h)
	var cpu := s.duplicate(true)
	cpu.players[2].cpu = true
	var roll := s.duplicate(true)
	roll.players[1].rolls.append(1)
	check("the cpu flag and the rolls are hashed", SLH.of(cpu) != h and SLH.of(roll) != h)
	check("JSON round trip (floats) keeps the hash", SLH.of(JSON.parse_string(JSON.stringify(s))) == h)

	# a real game: every roll changes the hash, and it survives JSON at every step
	s = SL.new_game("local", 4, 0, {need_one = true})
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ok := true
	var changed := 0
	var steps := 0
	var last := SLH.of(s)
	while s.phase == "roll" and steps < 2000:
		SL.apply_roll(s, rng.randi_range(1, 6))
		var now := SLH.of(s)
		ok = ok and now == SLH.of(JSON.parse_string(JSON.stringify(s))) and now.length() == 8
		changed += 1 if now != last else 0
		last = now
		steps += 1
	check("every step of a game hashes the same after JSON", ok)
	check("every roll changes the hash", changed == steps and steps > 20, [changed, steps])
