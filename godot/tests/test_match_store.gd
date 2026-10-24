extends "res://tests/test_suite.gd"
## MatchStore: the saved match round-trips through JSON with ints intact, peek/clear by game, and a Ludo state
## saved mid-game is still a valid rules state after load (W2a); an S&L {game, cfg, G} save round-trips and main
## rebuilds both games' setups from what was kept (P3-B).

func run() -> void:
	var was := MatchStore.path
	MatchStore.path = "user://test_match_store.json"
	MatchStore.enabled = true
	MatchStore.clear()
	check("empty: nothing saved", not MatchStore.has_saved() and MatchStore.peek().is_empty() and MatchStore.load().is_empty())

	var s := LudoRules.new_game(["human", "cpu", "cpu", "cpu"], false, {pair_ask = true})
	s.tok = [[10, 14, -1, 56], [3, -1, -1, 20], [-1, 9, 33, 44], [-1, -1, 8, -1]]
	s.pairs = [{c = 2, a = 1, b = 2}]
	s.turn = 2
	MatchStore.save("ludo", {S = s, players = s.players, teams = false, opts = {bot_level = "hard"}}, "Ludo vs Computer · 11%")
	check("saved", MatchStore.has_saved())
	var p := MatchStore.peek()
	check("peek: game + summary", p.get("game") == "ludo" and p.get("summary") == "Ludo vs Computer · 11%", p)
	var st := MatchStore.load()
	var t: Dictionary = st.get("S", {})
	check("load: tok ints", typeof(t.tok[0][0]) == TYPE_INT and t.tok == s.tok, t.get("tok"))
	check("load: turn int, pairs ints", typeof(t.turn) == TYPE_INT and typeof(t.pairs[0].a) == TYPE_INT, [t.turn, t.pairs])
	check("load: opts kept", st.opts.bot_level == "hard" and t.pair_ask == true, st.get("opts"))
	t.phase = "roll"
	var ev := LudoRules.apply_roll(t, 4)
	check("load: the state still plays", ev.size() > 0 and t.phase in ["choose", "roll"], ev)

	MatchStore.clear("sl")
	check("clear(other game) keeps it", MatchStore.has_saved())
	var main_gd: Script = load("res://scripts/main.gd")
	var lc: Dictionary = main_gd._ludo_cfg_of(st)
	check("main: a resumed Ludo match keeps its bot level for Restart", lc.bot_level == "hard" and lc.players == s.players and lc.teams == false, lc)
	MatchStore.clear("ludo")
	check("clear(ludo) removes it", not MatchStore.has_saved())

	# ---- Snakes & Ladders: {game, cfg, G} as SLMatch.save_match() keeps it ----
	var g := SL.new_game("cpu", 3, 1)
	var cfg := {game = "sl", mode = "cpu", n = 3, color = 1, bot_level = "easy"}
	for v in [6, 6, 6, 4, 2]:                     # three 6s (the third doesn't move), then on
		SL.apply_roll(g, v)
	MatchStore.save("sl", {game = "sl", cfg = cfg, G = g.duplicate(true)}, "Snakes & Ladders vs Computer · Square 12")
	check("sl: saved as the S&L game", MatchStore.game() == "sl" and MatchStore.peek().summary.ends_with("Square 12"))
	var sst := MatchStore.load()
	var sg: Dictionary = sst.get("G", {})
	check("sl: rolls and squares come back as ints", typeof(sg.players[0].rolls[0]) == TYPE_INT and sg.players[0].rolls == g.players[0].rolls and typeof(sg.turn) == TYPE_INT, sg.get("players"))
	check("sl: main rebuilds the setup from cfg (Restart / Play again)", main_gd._sl_cfg_of(sst) == cfg, main_gd._sl_cfg_of(sst))
	check("sl: a bare rules state still gives a setup", main_gd._sl_cfg_of(sg).n == 3 and main_gd._sl_cfg_of(sg).color == 1, main_gd._sl_cfg_of(sg))
	sg.players[0].pos = 97                        # finish it: the resumed game's rolls still pass the reward replay
	sg.players[0].rolls = [6, 6, 6, 2, 1, 5, 1, 6, 3, 4, 6]
	sg.turn = 0
	SL.apply_roll(sg, 3)
	check("sl: a resumed game won after three 6s pays", sg.phase == "over" and SL.claim_win_reward(sg) == 100, sg.players[0].rolls)
	MatchStore.clear("ludo")
	check("sl: clear(ludo) keeps the S&L match", MatchStore.has_saved())
	MatchStore.clear("sl")
	check("sl: clear(sl) removes it", not MatchStore.has_saved())

	check("ints: floats back to ints, real floats kept", MatchStore.ints({a = 1.0, b = [2.0, 0.5], c = {d = -1.0}}) == {a = 1, b = [2, 0.5], c = {d = -1}})
	MatchStore.enabled = false
	MatchStore.save("ludo", {S = s})
	check("disabled: no write", not MatchStore.has_saved())
	MatchStore.enabled = true
	MatchStore.clear()
	MatchStore.path = was
