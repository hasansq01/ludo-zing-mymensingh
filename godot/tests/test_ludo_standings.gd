extends "res://tests/test_suite.gd"
## "You" helpers (is_you, subject / object / poss / verb), team labels, the recorded finish order (s.finished) and
## standings() for Individual and Teams games, plus the JSON round trip of the new state fields.

const HOME := [56, 56, 56, 56]

func run() -> void:
	var s: Dictionary
	var t: Array
	var vs := {players = ["human", "cpu", "cpu", "cpu"], names = ["You", "Mocha", "Biscotti", "Espresso"]}

	# ---- is_you and grammar helpers ----
	s = Ludo.new_game(["human", "cpu", "cpu", "cpu"])
	check("is_you: the only human vs the computer", Ludo.is_you(s, 0) and not Ludo.is_you(s, 1) and not Ludo.is_you(s, 3))
	s = Ludo.new_game(["cpu", "off", "human", "cpu"])
	check("is_you follows the seat, not seat 0", Ludo.is_you(s, 2) and not Ludo.is_you(s, 0) and not Ludo.is_you(s, 1))
	s = Ludo.new_game(["human", "human", "off", "off"])
	check("is_you: never in Pass & Play", not Ludo.is_you(s, 0) and not Ludo.is_you(s, 1))
	s = Ludo.new_game(["human", "cpu", "off", "off"])
	s.names[0] = "Shihab"                          # a custom display name changes nothing
	check("is_you does not depend on the display name", Ludo.is_you(s, 0))
	check("is_you out of range is false", not Ludo.is_you(s, -1) and not Ludo.is_you(s, 4))
	s = Ludo.new_game(["human", "cpu", "cpu", "off"])
	check("subject: You / Mocha", Ludo.subject(s, 0) == "You" and Ludo.subject(s, 1) == "Mocha")
	check("object: you / Mocha", Ludo.object(s, 0) == "you" and Ludo.object(s, 2) == "Biscotti")
	check("poss: Your / your / Mocha's", Ludo.poss(s, 0) == "Your" and Ludo.poss(s, 0, false) == "your" and Ludo.poss(s, 1) == "Mocha's" and Ludo.poss(s, 1, false) == "Mocha's")
	check("verb: You roll, Mocha rolls", Ludo.verb(s, 0, "roll", "rolls") == "roll" and Ludo.verb(s, 1, "roll", "rolls") == "rolls")
	var line := "%s %s a 6. %s again!" % [Ludo.subject(s, 0), Ludo.verb(s, 0, "roll", "rolls"), Ludo.verb(s, 0, "Roll", "Rolls")]
	check("a whole line reads right for you", line == "You roll a 6. Roll again!", line)
	s = Ludo.new_game(["human", "human", "off", "off"])
	check("Pass & Play: colours are third person", Ludo.subject(s, 1) == "Green" and Ludo.verb(s, 1, "go", "goes") == "goes" and Ludo.poss(s, 0) == "Red's")

	# ---- team names ----
	s = Ludo.new_game(["human", "cpu", "cpu", "cpu"], true)
	check("team_label: colours joined with +", Ludo.team_label(s, 0) == "Red + Yellow" and Ludo.team_label(s, 2) == "Red + Yellow" and Ludo.team_label(s, 3) == "Green + Blue")
	check("team_name: Your team / Mocha + Espresso", Ludo.team_name(s, 2) == "Your team" and Ludo.team_name(s, 1) == "Mocha + Espresso", [Ludo.team_name(s, 2), Ludo.team_name(s, 1)])
	s = Ludo.new_game(["human", "human", "human", "human"], true)
	check("team_name in Pass & Play: Green + Blue", Ludo.team_name(s, 3) == "Green + Blue")

	# ---- win reward uses is_you ----
	t = base(); t[0] = [56, 56, 56, 55]; s = state(t, [], {players = ["human", "cpu", "off", "off"], names = ["Shihab", "Mocha", "", ""]})
	play(s, 1)
	check("beating the computer pays even with a custom name", s.phase == "over" and Ludo.win_reward(s) == Ludo.WIN_REWARD)

	# ---- progress ----
	t = base(); s = state(t)
	check("progress: all at base is 0", Ludo.progress(s, 0) == 0.0)
	t = base(); t[0] = HOME.duplicate(); s = state(t)
	check("progress: all home is 1", is_equal_approx(Ludo.progress(s, 0), 1.0))
	t = base(); t[0] = [56, 56, -1, -1]; s = state(t)
	check("progress: two home is a half", is_equal_approx(Ludo.progress(s, 0), 0.5))

	# ---- finish order (Individual) ----
	s = Ludo.new_game(["human", "cpu", "cpu", "cpu"])
	check("a new game has an empty finish order", s.finished == [])
	t = base(); t[1] = [56, 56, 56, 55]; t[0][0] = 30; t[2][0] = 10; t[3][0] = 40
	s = state(t, [], vs.merged({turn = 1, finished = []}))
	play(s, 1)
	check("Individual: the first home is recorded, you play on", s.phase == "roll" and s.finished == [1] and s.turn == 2, [s.phase, s.finished])
	var st := Ludo.standings(s)
	check("Individual standings: winner first, then by progress", st.map(func(e): return e.color) == [1, 3, 0, 2], st)
	Ludo.end_game(s)
	check("…end_game: the full order recorded, Green wins", s.phase == "over" and s.winner == 1 and s.finished == [1, 3, 0, 2], s.finished)
	check("…places 1-4, only the winner finished", st.map(func(e): return e.place) == [1, 2, 3, 4] and st[0].finished and not st[1].finished, st)
	check("…progress is 0-1", st.all(func(e): return e.progress >= 0.0 and e.progress <= 1.0) and is_equal_approx(st[0].progress, 1.0))
	t = base(); t[0][0] = 20; t[1][0] = 20; s = state(t, [], {players = ["human", "off", "human", "off"]})
	st = Ludo.standings(s)
	check("standings list only active colours; ties keep seat order", st.map(func(e): return e.color) == [0, 2], st)
	t = base(); s = state(t)
	s.erase("finished")                            # a state saved before finish order existed
	check("standings work without s.finished", Ludo.standings(s).size() == 4)
	t = base(); t[0] = [56, 56, 56, 55]; s = state(t)
	s.erase("finished")
	play(s, 1)
	check("…and a game that ends then records it", s.finished == [0], s.get("finished"))

	# ---- finish order (Teams) ----
	t = base(); t[0] = [56, 56, 56, 55]; t[2][0] = 10; t[1][0] = 5; t[3][0] = 30
	s = state(t, [], {teams = true, finished = []})
	play(s, 1)
	check("Teams: Red's fourth pawn home is recorded, no win yet", s.finished == [0] and s.phase == "roll" and s.winner == -1, [s.finished, s.phase])
	st = Ludo.standings(s)
	check("Teams mid-game: partners share a place, the team further on first", st.map(func(e): return e.color) == [0, 2, 3, 1] and st.map(func(e): return e.place) == [1, 1, 2, 2], st)
	s.tok[2] = [56, 56, 56, 55]; s.turn = 2; s.phase = "roll"; s.sixes = 0
	play(s, 1)
	check("Teams: the team win records both partners in finish order, then the other team", s.phase == "over" and s.finished == [0, 2, 3, 1], s.finished)
	st = Ludo.standings(s)
	check("Teams final standings: winners place 1, both finished", st[0].place == 1 and st[1].place == 1 and st[0].finished and st[1].finished and st[2].place == 2, st)
	t = base(); t[0] = HOME.duplicate(); t[2] = [56, 56, 56, 55]
	s = state(t, [], {teams = true, finished = [], free = [true, false, false, false]})
	play(s, 1)
	check("Teams: a partner already home (old state) is listed with its team", s.phase == "over" and s.finished == [2, 0, 1, 3], s.finished)
	t = base(); t[1][0] = 50; t[3][0] = 2; s = state(t, [], {teams = true, finished = []})
	st = Ludo.standings(s)
	check("Teams: Green + Blue ahead on progress lead mid-game", st[0].color == 1 and st[0].place == 1 and st[2].place == 2, st)

	# ---- JSON round trip with the new fields ----
	s = Ludo.new_game(["human", "cpu", "cpu", "cpu"], false, {pair_ask = true})
	s.finished = [2]
	var rt: Dictionary = JSON.parse_string(JSON.stringify(s))
	check("pair_ask and finished survive JSON", rt.pair_ask == true and rt.finished.size() == 1 and int(rt.finished[0]) == 2)
	check("standings of a JSON round-tripped state", Ludo.standings(rt).size() == 4 and int(Ludo.standings(rt)[0].color) == 2)
