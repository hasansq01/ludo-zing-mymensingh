extends "res://tests/test_suite.gd"
## StateHash (the online state hash, server/PROTOCOL.md "State hash"): FNV-1a reference values, the PROTOCOL.md
## fresh-game example, which fields are hashed, JSON round trips (numbers come back as floats), and the same
## strings / values as server/test/rules_hash.test.ts (the TS twin). Every step of the recorded parity traces is also
## checked against the TS hash by server/test/rules_parity.test.ts.

const SH := preload("res://scripts/net/state_hash.gd")

const FRESH_2P := "-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1||0|0|0|roll|-1|0000||human,off,human,off|"

func run() -> void:
	check("fnv1a32 of \"\"", SH.fnv1a32("") == "811c9dc5", SH.fnv1a32(""))
	check("fnv1a32 of \"a\"", SH.fnv1a32("a") == "e40c292c", SH.fnv1a32("a"))
	check("fnv1a32 of \"foobar\" (32-bit masking)", SH.fnv1a32("foobar") == "bf9cf968", SH.fnv1a32("foobar"))
	check("fnv1a32 hashes UTF-8 bytes", SH.fnv1a32("é") != SH.fnv1a32("e") and SH.fnv1a32("é").length() == 8)

	var s := Ludo.new_game(["human", "off", "human", "off"])
	check("fresh 2-player game: the PROTOCOL.md string", SH.input(s) == FRESH_2P, SH.input(s))
	check("fresh 2-player game: the TS value", SH.of(s) == "86cf2abe", SH.of(s))

	var t := base(); t[0][0] = 10; t[0][1] = 10; t[2] = [56, 56, 56, 56]
	s = state(t, [{c = 0, a = 0, b = 1}], {players = ["human", "cpu", "human", "off"], free = [false, false, true, false],
		finished = [2], phase = "pair_ask", pending = {c = 0, i = 2, to = 12, extra = true, partner = 3}, dice = 4, sixes = 1})
	var want := "10,10,-1,-1,-1,-1,-1,-1,56,56,56,56,-1,-1,-1,-1|0.0.1|0|4|1|pair_ask|-1|0010|2|human,cpu,human,off|0.2.12.1.3"
	check("pairs, free, finished and pending in the string (same as the TS test)", SH.input(s) == want, SH.input(s))
	var h := SH.of(s)
	var other := s.duplicate(true)
	other.names = ["A", "B", "C", "D"]; other.view = 2; other.teams = true; other.pair_ask = true; other.pick = "pair"
	check("names, view, teams, pair_ask and pick are not hashed", SH.of(other) == h)
	var no_partner := s.duplicate(true)
	no_partner.pending = {c = 0, i = 2, to = 12, extra = false}
	check("pending without a partner ends .0.-1", SH.input(no_partner).ends_with("|0.2.12.0.-1"), SH.input(no_partner))
	var cleared := s.duplicate(true)
	cleared.pending = {}
	check("an empty pending hashes differently", SH.of(cleared) != h and SH.input(cleared).ends_with("|"))
	var no_fin := s.duplicate(true)
	no_fin.erase("finished")
	check("a state without finished hashes it as empty", SH.input(no_fin).contains("|0010||human"), SH.input(no_fin))
	check("JSON round trip (floats) keeps the hash", SH.of(JSON.parse_string(JSON.stringify(s))) == h)

	# a real game: the hash changes with the play and survives JSON at every step
	s = Ludo.new_game(["human", "human", "human", "human"], true, {pair_ask = true})
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ok := true
	var changed := 0
	var last := SH.of(s)
	for n in 300:
		if s.phase == "roll":
			Ludo.apply_roll(s, rng.randi_range(1, 6))
		elif s.phase == "choose":
			var mv := Ludo.movables(s)
			Ludo.move(s, mv[rng.randi_range(0, mv.size() - 1)])
		elif s.phase == "pair_ask":
			Ludo.answer_pair(s, rng.randf() < 0.5)
		else:
			break
		var now := SH.of(s)
		ok = ok and now == SH.of(JSON.parse_string(JSON.stringify(s))) and now.length() == 8
		changed += 1 if now != last else 0
		last = now
	check("every step of a game hashes the same after JSON", ok)
	check("the hash follows the play", changed > 250, changed)
