extends "res://tests/test_suite.gd"
## Play on after the first finish (Ludo and Snakes & Ladders): places in finish order ("finished" events), finished
## sides skipped by the turn order, the two end conditions (fewer than two sides left; no person left unfinished),
## the ranking of the rest by progress, end_game() (the server's {k: "end"}), Teams (the team finishes together,
## Free Hand until then) and states saved before play on. The TS twin is server/test/rules_playon.test.ts.

const HOME := [56, 56, 56, 56]
const NEAR := [56, 56, 56, 55]                # one pawn a 1 away from home

func types(ev: Array) -> Array:
	return ev.map(func(e): return str(e.type))

func of_type(ev: Array, t: String) -> Dictionary:
	for e in ev:
		if e.type == t:
			return e
	return {}

func run() -> void:
	_ludo()
	_ludo_rule_b()
	_ludo_teams()
	_ludo_end_and_compat()
	_sl()

func _ludo() -> void:
	var t := base()
	t[0] = NEAR.duplicate(); t[1] = NEAR.duplicate(); t[2] = NEAR.duplicate(); t[3][0] = 12
	var s := state(t, [], {finished = []})                     # four people (Pass & Play)
	Ludo.apply_roll(s, 1)
	var ev := Ludo.move(s, 3)
	check("4 players: Red home -> finished, place 1", types(ev) == ["move", "home", "finished", "turn"] and of_type(ev, "finished") == {type = "finished", c = 0, place = 1}, ev)
	check("…the game goes on with Green's turn", s.phase == "roll" and s.turn == 1 and s.winner == -1 and s.finished == [0], [s.phase, s.turn, s.finished])
	check("…Red's side is done, the others not", Ludo.side_done(s, 0) and not Ludo.side_done(s, 1) and not Ludo.side_done(s, 3))
	Ludo.apply_roll(s, 1)
	ev = Ludo.move(s, 3)
	check("Green home: place 2, Yellow's turn", of_type(ev, "finished").get("place") == 2 and s.turn == 2 and s.phase == "roll", [ev, s.turn])
	Ludo.apply_roll(s, 1)
	ev = Ludo.move(s, 3)
	check("Yellow home: place 3, one side left -> game over", types(ev) == ["move", "home", "finished", "game_over"] and s.phase == "over", types(ev))
	check("…the full order, Red the winner", s.finished == [0, 1, 2, 3] and s.winner == 0 and of_type(ev, "game_over") == {type = "game_over", winner = 0, team = [0], order = [0, 1, 2, 3]}, [s.finished, of_type(ev, "game_over")])
	var st := Ludo.standings(s)
	check("…standings 1-4, Blue ranked by progress (not finished)", st.map(func(e): return e.place) == [1, 2, 3, 4] and st[2].finished and not st[3].finished and st[3].color == 3, st)
	check("…no more rolls", Ludo.apply_roll(s, 6).is_empty())

	# the turn order skips finished sides
	t = base(); t[0] = HOME.duplicate(); t[1][0] = 3
	s = state(t, [], {finished = [0], turn = 3})
	ev = Ludo.apply_roll(s, 2)                                  # Blue: nothing to move
	check("after Blue comes Green: Red (finished) sits out", s.turn == 1 and ev[-1] == {type = "turn", c = 1, again = false}, ev)
	check("next_active skips finished sides", Ludo.next_active(s, 3) == 1 and Ludo.next_active(s, 2) == 3)
	s.turn = 3; s.sixes = 2
	ev = Ludo.apply_roll(s, 6)
	check("three 6s still end the turn, past Red", types(ev) == ["rolled", "three_sixes", "turn"] and s.turn == 1, ev)
	s.turn = 3; s.sixes = 0
	ev = Ludo.apply_roll(s, 6)                                  # a 6 out of base: Blue's own extra turn as before
	Ludo.move(s, Ludo.auto_move_token(s))
	check("a 6 still gives the roller another turn", s.turn == 3 and s.phase == "roll", [s.turn, s.phase])

	# finishing with a 6 (or after a capture) hands the turn on: a finished side never rolls again
	t = base(); t[0] = [56, 56, 56, 50]; t[1][0] = 2
	s = state(t, [], {finished = []})
	Ludo.apply_roll(s, 6)
	ev = Ludo.move(s, 3)
	check("finished with a 6: no extra roll, Green next", of_type(ev, "finished").get("place") == 1 and s.turn == 1 and s.sixes == 0 and ev[-1] == {type = "turn", c = 1, again = false}, ev)
	check("…and Green's pawn (and everyone's) unchanged", s.tok[1][0] == 2)

	# three players: the second finisher ends it (Blue off)
	t = base(); t[0] = NEAR.duplicate(); t[2] = NEAR.duplicate(); t[1][0] = 20
	s = state(t, [], {players = ["human", "human", "human", "off"], finished = []})
	play(s, 1)
	check("3 players: Red 1st, the game goes on", s.phase == "roll" and s.turn == 1)
	s.turn = 2
	play(s, 1)
	check("…Yellow 2nd ends it: Green ranked 3rd by progress", s.phase == "over" and s.finished == [0, 2, 1] and s.winner == 0, s.finished)

func _ludo_rule_b() -> void:
	var vs := {players = ["human", "cpu", "cpu", "cpu"], names = ["You", "Mocha", "Biscotti", "Espresso"], finished = []}
	# vs Computer: a computer finishes first, you play on for 2nd
	var t := base()
	t[1] = NEAR.duplicate(); t[0] = NEAR.duplicate(); t[2][0] = 30; t[3][0] = 40
	var s := state(t, [], vs.merged({turn = 1}).duplicate(true))
	play(s, 1)
	check("vs Computer: Mocha 1st, you are still playing (the game goes on)", s.phase == "roll" and s.finished == [1] and s.turn == 2, [s.phase, s.finished, s.turn])
	s.players[0] = "cpu"                                        # a seat switching to cpu never ends a game by itself
	check("a mode switch alone does not end the game", s.phase == "roll")
	s.players[0] = "human"
	s.turn = 0
	Ludo.apply_roll(s, 1)
	var ev := Ludo.move(s, 3)
	check("you finish 2nd: no person left unfinished -> game over", s.phase == "over" and types(ev).slice(-2) == ["finished", "game_over"], types(ev))
	check("…the computers ranked by progress, Mocha the winner", s.finished == [1, 0, 3, 2] and s.winner == 1, s.finished)
	check("…a loss: no win reward, the participation reward", Ludo.win_reward(s) == 0 and Ludo.play_reward(s) == Ludo.PLAY_REWARD)
	var copy: Dictionary = LudoMatch.result_copy(s)
	check("…headline: You finished 2nd", copy.title == "You finished 2nd", copy)
	var st := Ludo.standings(s)
	check("…standings: you 2nd and finished", st[1].color == 0 and st[1].place == 2 and st[1].finished, st)

	# you finish first: the game is over at once (as before)
	t = base(); t[0] = NEAR.duplicate(); t[1][0] = 10
	s = state(t, [], vs.duplicate(true))
	play(s, 1)
	check("vs Computer: you 1st ends the game at once", s.phase == "over" and s.winner == 0 and s.finished.size() == 4 and Ludo.win_reward(s) == Ludo.WIN_REWARD, [s.phase, s.finished])

	# two people and two computers: both people finish, then the computers aren't watched
	t = base(); t[0] = NEAR.duplicate(); t[2] = NEAR.duplicate(); t[1][0] = 5; t[3][0] = 9
	s = state(t, [], {players = ["human", "cpu", "human", "cpu"], finished = []})
	play(s, 1)
	check("2 people + 2 computers: Red 1st, Yellow still playing", s.phase == "roll" and s.finished == [0])
	s.turn = 2
	play(s, 1)
	check("…Yellow 2nd: only computers left -> over, Blue 3rd by progress", s.phase == "over" and s.finished == [0, 2, 3, 1], s.finished)

	# 4 computers (sims): the first finish ends it (no person ever)
	t = base(); t[0] = NEAR.duplicate()
	s = state(t, [], {players = ["cpu", "cpu", "cpu", "cpu"], finished = []})
	play(s, 1)
	check("4 computers: over at the first finish", s.phase == "over" and s.winner == 0)

func _ludo_teams() -> void:
	# Red home first (Free Hand), then Red's 6 helps Yellow home: the team finishes together, the game is over
	var t := base()
	t[0] = NEAR.duplicate(); t[2] = [56, 56, 56, 50]; t[1][0] = 5; t[3][0] = 30
	var s := state(t, [], {teams = true, finished = []})
	Ludo.apply_roll(s, 1)
	var ev := Ludo.move(s, 3)
	check("Teams: Red's four home -> all_home (no place yet), the game goes on", types(ev) == ["move", "home", "all_home", "turn"] and s.phase == "roll" and s.finished == [0], ev)
	check("…Red's side is not done until Yellow is home", not Ludo.side_done(s, 0) and Ludo.next_active(s, 3) == 0)
	s.turn = 0
	ev = Ludo.apply_roll(s, 6)
	check("…Red's 6 starts the Free Hand (help your teammate)", types(ev).has("free_hand") and s.phase == "choose" and Ludo.mover_of(s, 0) == 2, ev)
	ev = Ludo.move(s, 3)
	var f := of_type(ev, "finished")
	check("…Yellow home by Red's roll: the team finishes together", f == {type = "finished", c = 2, place = 1, team = [0, 2]}, f)
	check("…two teams: the other one is 2nd, game over", s.phase == "over" and types(ev)[-1] == "game_over" and s.finished == [0, 2, 3, 1] and Ludo.winners(s) == [2, 0], [s.finished, Ludo.winners(s)])
	var st := Ludo.standings(s)
	check("…Teams standings: places 1, 1, 2, 2", st.map(func(e): return e.place) == [1, 1, 2, 2], st)

func _ludo_end_and_compat() -> void:
	var t := base()
	t[0] = HOME.duplicate(); t[1][0] = 40; t[2][0] = 12; t[3] = [56, 56, -1, -1]
	var s := state(t, [], {finished = [0], turn = 1, phase = "choose", dice = 3, pick = "single"})
	var ev := Ludo.end_game(s)
	check("end_game: one game_over, the rest ranked by progress", types(ev) == ["game_over"] and s.finished == [0, 3, 1, 2] and s.winner == 0, [ev, s.finished])
	check("…phase over, pick and pending cleared", s.phase == "over" and s.pick == "" and s.pending == {})
	check("…refused once over", Ludo.end_game(s).is_empty())
	t = base(); t[1][0] = 50; t[3][0] = 2
	s = state(t, [], {teams = true, finished = []})
	Ludo.end_game(s)
	check("end_game in Teams before any finish: the team further on wins", s.winner == 1 and Ludo.winners(s) == [1, 3] and s.finished.size() == 4, [s.winner, s.finished])
	s = state(base())
	s.erase("finished")                                        # a game saved before finish order existed
	Ludo.apply_roll(s, 2)
	check("an old saved state (no finished) plays on", s.has("finished") and s.finished == [] and s.turn == 1 and s.phase == "roll", s)
	s = state(base(), [], {finished = [1.0], turn = 0})        # finished through JSON (floats)
	Ludo.apply_roll(s, 2)
	check("finished as floats (JSON): Green still skipped", s.turn == 2 and s.finished == [1], [s.turn, s.finished])
	t = base(); t[0] = NEAR.duplicate(); t[1] = NEAR.duplicate()
	s = state(t, [], {players = ["human", "human", "off", "off"], finished = []})
	play(s, 1)
	check("2 players: the first finish ends it, as before", s.phase == "over" and s.finished == [0, 1] and s.winner == 0)

func _sl() -> void:
	var g := SL.new_game("local", 3)
	check("S&L new game: an empty finish order", g.finished == [])
	g.players[0].pos = 97; g.players[1].pos = 99; g.players[2].pos = 50
	var ev := SL.apply_roll(g, 3)
	check("S&L: Red reaches 100 -> finished, place 1, Green's turn", types(ev) == ["rolled", "move", "finished", "turn"] and of_type(ev, "finished") == {type = "finished", turn = 0, c = 0, place = 1} and g.turn == 1 and g.phase == "roll", ev)
	ev = SL.apply_roll(g, 1)
	check("…Green 2nd: one left -> over (a win event with the order)", types(ev).slice(-2) == ["finished", "win"] and g.phase == "over" and g.winner == 0 and g.finished == [0, 1, 2], [types(ev), g.finished])
	check("…win event: the winner and the order", ev[-1] == {type = "win", turn = 0, order = [0, 1, 2]}, ev[-1])
	var st := SL.standings(g)
	check("…standings in finish order, the last by square", st.map(func(e): return e.idx) == [0, 1, 2] and st[1].finished and not st[2].finished, st)

	g = SL.new_game("local", 4)
	g.finished = [0]; g.players[0].pos = 100; g.turn = 3
	SL.apply_roll(g, 2)
	check("S&L: finished players are skipped (Blue -> Green)", g.turn == 1, g.turn)
	g.turn = 3; g.players[3].pos = 94
	ev = SL.apply_roll(g, 6)
	check("S&L: a 6 onto 100 hands the turn on", of_type(ev, "finished").get("place") == 2 and g.turn == 1 and g.sixes == 0 and ev[-1] == {type = "turn", turn = 1, again = false}, ev)

	g = SL.new_game("cpu", 3)                                  # You, Mocha, Biscotti
	g.players[1].pos = 97; g.players[0].pos = 98; g.players[2].pos = 40; g.turn = 1
	SL.apply_roll(g, 3)
	check("S&L vs Computer: Mocha 1st, you play on", g.phase == "roll" and g.finished == [1] and g.turn == 2, [g.phase, g.turn])
	g.turn = 0
	ev = SL.apply_roll(g, 2)
	check("…you 2nd: no person left -> over, Mocha the winner", g.phase == "over" and g.winner == 1 and g.finished == [1, 0, 2], g.finished)
	check("…no win reward, the participation reward", SL.claim_win_reward(g.duplicate(true)) == 0 and SL.claim_play_reward(g.duplicate(true)) == SL.PLAY_REWARD)
	g = SL.new_game("cpu", 3)
	g.players[0].pos = 98; g.players[0].rolls = [2, 6, 4, 6, 1, 6, 2, 3]
	SL.apply_roll(g, 2)
	check("S&L vs Computer: you 1st ends it at once", g.phase == "over" and g.winner == 0 and g.finished.size() == 3)

	g = SL.new_game("local", 3)
	g.players[1].pos = 60; g.players[2].pos = 60
	check("S&L end_game: ranked by square, ties in turn order", SL.end_game(g).size() == 1 and g.finished == [1, 2, 0] and g.winner == 1 and g.phase == "over", g.finished)
	check("…refused once over", SL.end_game(g).is_empty())
	g = SL.new_game("local", 2)
	g.erase("finished")
	g.phase = "over"; g.winner = 1; g.players[1].pos = 100
	check("S&L: a game saved before play on (winner, no finished) ranks the winner first", SL.standings(g)[0].idx == 1)
	g = SL.new_game("local", 3)
	g.finished = [0.0]                                         # through JSON
	SL.apply_roll(g, 2)                                        # (turn 0 is a finished player only in this test)
	check("S&L: finished as floats is read as ints", g.finished == [0] and g.turn == 1, [g.finished, g.turn])
