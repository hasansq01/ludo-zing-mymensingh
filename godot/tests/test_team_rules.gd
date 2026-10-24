extends "res://tests/test_suite.gd"
## Port of tests/team-rules.js (28 checks): Pair Mode (teams) setup, partner captures / blocking, Free Hand and
## team wins. The browser version plays real rolls through the page; here the same rolls go through apply_roll /
## move, and the win-title check reads team_name() (the text the win card shows).

const HOME := [56, 56, 56, 56]

func team(tok: Array, extra: Dictionary = {}) -> Dictionary:
	return state(tok, [], {teams = true}.merged(extra, true))

func run() -> void:
	var s: Dictionary
	var t: Array

	# ---- Setup ----
	s = Ludo.new_game(["human", "cpu", "cpu", "cpu"], true)
	check("Pair Mode on with four seats", s.teams == true and s.free == [false, false, false, false], [s.teams, s.free])
	check("teams are opposite seats: Red+Yellow, Green+Blue", Ludo.mate_of(0) == 2 and Ludo.mate_of(2) == 0 and Ludo.mate_of(1) == 3 and Ludo.mate_of(3) == 1)
	s = Ludo.new_game(["human", "off", "human", "off"], true)
	check("2-player game can never be Pair Mode", s.teams == false)
	s = Ludo.new_game(["human", "human", "human", "off"], true)
	check("3-player game can never be Pair Mode", s.teams == false)
	s = Ludo.new_game(["human", "cpu", "cpu", "cpu"], false)
	check("Individual 4-player game has no teams", s.teams == false)
	s = Ludo.new_game(["human", "cpu", "cpu", "cpu"], true); s.free[0] = true
	s = Ludo.new_game(["human", "cpu", "cpu", "cpu"], true)
	check("a new game never inherits Free Hand state", s.free.all(func(f): return not f))

	# ---- Captures and blocking between partners ----
	t = base(); t[0][0] = 10; t[2][0] = prog(2, 14); s = team(t)
	check("Pair Mode: landing on a partner pawn captures nothing", Ludo.victims_at(s, 0, 14, false).is_empty(), Ludo.victims_at(s, 0, 14, false))
	check("Pair Mode: partner is not a foe, opponents are", not Ludo.foe(s, 0, 2) and Ludo.foe(s, 0, 1) and Ludo.foe(s, 0, 3))
	t = base(); t[0][0] = 10; t[1][0] = prog(1, 14); s = team(t)
	check("Pair Mode: opponents are still captured", Ludo.victims_at(s, 0, 14, false) == [[1, 0]], Ludo.victims_at(s, 0, 14, false))
	t = base(); t[0][0] = 10; t[2][0] = prog(2, 14); s = team(t, {teams = false})
	check("Individual: the same landing still captures Yellow", Ludo.victims_at(s, 0, 14, false) == [[2, 0]])
	t = base(); t[0][0] = 10; t[2][0] = prog(2, 12); t[2][1] = prog(2, 12); s = team(t, {pairs = [{c = 2, a = 0, b = 1}]})
	check("Pair Mode: a partner pair does not block", Ludo.dest(s, 0, 0, 4) == 14)
	check("Pair Mode: a single cannot capture a partner pair either", Ludo.victims_at(s, 0, 12, false).is_empty())
	s = team(t, {teams = false, pairs = [{c = 2, a = 0, b = 1}]})
	check("Individual: that pair still blocks (unchanged)", Ludo.dest(s, 0, 0, 4) == Ludo.NO_MOVE)

	# ---- Free Hand gating (static) ----
	t = base(); t[0] = HOME.duplicate(); t[2][0] = 10; s = team(t, {dice = 4})
	check("finished, no Free Hand yet: nothing to move", Ludo.waiting_six(s, 0) and Ludo.movables(s).is_empty())
	s.free[0] = true
	check("Free Hand on: rolls move the partner", Ludo.mover_of(s, 0) == 2 and Ludo.movables(s) == [0], Ludo.movables(s))
	check("Free Hand never moves opponents or own pawns", Ludo.mover_of(s, 0) != 1 and Ludo.mover_of(s, 0) != 3 and Ludo.mover_of(s, 0) != 0)
	t = base(); t[0][0] = 10; s = team(t)
	check("unfinished player moves its own pawns", Ludo.mover_of(s, 0) == 0 and not Ludo.waiting_six(s, 0))

	# ---- Free Hand flow (real rolls) ----
	# 1. finished Red rolls a 3: no Free Hand, nothing moves, turn passes
	t = base(); t[0] = HOME.duplicate(); t[2][0] = 10; t[2][1] = 20; s = team(t)
	play(s, 3)
	check("non-6 does not start Free Hand and the turn passes", not s.free[0] and s.turn == 1 and s.tok[2][0] == 10, [s.free[0], s.turn, s.tok[2]])
	# 2. finished Red rolls a 6: Free Hand starts and the 6 moves a Yellow pawn
	t = base(); t[0] = HOME.duplicate(); t[2] = [10, 56, 56, 56]; s = team(t)   # one Yellow pawn left, so the 6 has one move
	play(s, 6)
	check("a 6 starts Free Hand and moves the partner pawn", s.free[0] and s.tok[2][0] == 16 and s.turn == 0, [s.free, s.tok[2], s.turn])
	# 3. after activation a normal roll moves the partner (no further 6 needed)
	play(s, 4)
	check("after activation a 4 moves Yellow 4 squares and ends the turn", s.tok[2][0] == 20 and s.turn == 1, [s.tok[2], s.turn])
	# 4. Free Hand stays on and Red's opponents are captured normally by Yellow's pawn
	t = base(); t[0] = HOME.duplicate(); t[2][0] = 12; t[1][0] = prog(1, 41); s = team(t, {free = [true, false, false, false]})   # Yellow 12 = abs 38; +3 = abs 41 (not safe)
	play(s, 3)
	check("Free Hand move captures an opponent and earns another roll", s.tok[2][0] == 15 and s.tok[1][0] == -1 and s.turn == 0, [s.tok[1], s.turn])
	# 5. exact finish still applies to the partner's pawns
	t = base(); t[0] = HOME.duplicate(); t[2] = [56, 56, 56, 54]; s = team(t, {free = [true, false, false, false]})
	play(s, 5)
	check("overshooting the centre is not allowed (exact finish)", s.tok[2][3] == 54 and s.phase != "over", [s.tok[2], s.phase])

	# ---- Wins ----
	# one partner finishing is not a team win
	t = base(); t[0] = [56, 56, 56, 55]; t[2][0] = 10; s = team(t)
	play(s, 1)
	check("Red finishing alone does not win; Red rolls again and needs a 6", s.tok[0][3] == 56 and s.phase == "roll" and s.winner == -1 and s.turn == 0 and Ludo.waiting_six(s, 0), [s.phase, s.winner, s.turn])
	# the team wins when the second partner finishes (through Free Hand)
	t = base(); t[0] = HOME.duplicate(); t[2] = [56, 56, 56, 55]; s = team(t, {free = [true, false, false, false]})
	play(s, 1)
	check("team victory as soon as both partners are home", s.phase == "over" and [0, 2].has(s.winner) and Ludo.team_name(s, s.winner) == "Red + Yellow" and Ludo.winners(s).size() == 2, [s.phase, s.winner, Ludo.team_name(s, maxi(s.winner, 0))])
	# the partner can also finish on its own turn
	t = base(); t[0] = HOME.duplicate(); t[2] = [56, 56, 56, 55]; s = team(t, {turn = 2})
	play(s, 1)
	check("team victory when Yellow finishes on its own turn", s.phase == "over" and [0, 2].has(s.winner), [s.phase, s.winner])
	# Individual Mode: finishing four pawns still wins at once (unchanged)
	t = base(); t[0] = [56, 56, 56, 55]; s = team(t, {teams = false})
	play(s, 1)
	check("Individual: four pawns home wins immediately", s.phase == "over" and s.winner == 0, [s.phase, s.winner])

	# ---- Computer players follow the same rules ----
	var cpus := {players = ["human", "cpu", "human", "cpu"], names = ["Red", "Mocha", "Yellow", "Espresso"], turn = 1}
	t = base(); t[1] = HOME.duplicate(); t[3][0] = 10; s = team(t, cpus)
	play(s, 2)
	check("computer: finished, no 6 yet, cannot move its partner", not s.free[1] and s.tok[3][0] == 10, [s.free, s.tok[3]])
	t = base(); t[1] = HOME.duplicate(); t[3][0] = 10; s = team(t, cpus.merged({free = [false, true, false, false]}, true))
	play(s, 2)
	check("computer with Free Hand moves its partner (Blue)", s.tok[3][0] == 12, s.tok[3])
