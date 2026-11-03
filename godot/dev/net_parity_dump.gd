extends SceneTree
## Dev: records seeded random Ludo games played with the GDScript rules, for the server's TS port parity test
## (server/test/rules_parity.test.ts). Run from the repo root:
##   godot --headless --path godot -s res://dev/net_parity_dump.gd [-- <games> <out.json>]
## Default: 140 games to server/test/fixtures/ludo_traces.json (about 8 MB).
##
## Games mix 2 / 3 / 4 seats (mostly the online layouts, sometimes any layout), all-human tables (so pair_ask
## questions come up) and tables with computers (levels easy / normal / hard), teams on / off, pair_ask on / off,
## some with "Ask before pairing" per colour (opts.pair_ask_by, as quick matches deal it; drawn from a second generator
## so the other games stay as they were), random legal choices (either pawn of a pair; pair answers yes / no), some
## 6-heavy dice, "mode" switches of a seat
## between human and cpu at any moment, and a few refused actions (wrong phase, a pawn that can't move). Play on: games
## run past the first finish (several "finished" events, then game_over), some are ended early by the server's
## {k: "end"} once a side has finished (and a few get a refused "end" after the game is over).
##
## File: {version, games, ev}. ev is a table of event lists (each distinct list stored once). Per game:
##   {seed, args: {players, teams, opts}, levels, s0 (state after new_game), h0, steps, end?}
## and every step is the compact array
##   [k, c, val, ev_index, hash, diff, extra?]
## k / c / val: the protocol action ({k: "roll", c, v: val} | {k: "move", c, i: val} | {k: "pair", c, yes: val} |
## {k: "mode", c, mode: val} | {k: "end"} (stored as ["end", -1, 0])); ev_index: the events the rules returned; hash: StateHash.of() after the action;
## diff: the top-level state keys whose value changed (full values, except tok: only the changed rows, as
## [[colour, row], ...]), so applying the diffs in order to s0 rebuilds the full state after every step exactly; extra: {auto, units} after some of the rolls that reached phase "choose", {pair_default} (default_pair_answer) after every step that reached phase "pair_ask". end (game over):
## {standings, winners, win_reward, play_reward}.

const Ludo := preload("res://scripts/core/ludo_rules.gd")
const SH := preload("res://scripts/net/state_hash.gd")

const MAX_STEPS := 9000

var ev_table := []        # event lists, each distinct JSON stored once
var ev_index := {}
var bad := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 140
	var out: String = args[1] if args.size() > 1 else ProjectSettings.globalize_path("res://").path_join("../server/test/fixtures/ludo_traces.json").simplify_path()
	var recs := []
	var steps := 0
	var over := 0
	for g in games:
		var rec := play_game(1000 + g)
		steps += rec.steps.size()
		over += 1 if rec.has("end") else 0
		recs.append(rec)
	var data := {version = 1, games = recs, ev = ev_table}
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % out)
		quit(1)
		return
	f.store_string(JSON.stringify(data, "", false, true))
	f.close()
	print("wrote %s: %d games (%d finished), %d steps, %d event lists, %d problems" % [out, games, over, steps,
		ev_table.size(), bad])
	quit(1 if bad else 0)

func intern_events(ev: Array) -> int:
	var json := JSON.stringify(ev, "", true, true)
	if ev_index.has(json):
		return ev_index[json]
	ev_index[json] = ev_table.size()
	ev_table.append(ev.duplicate(true))
	return ev_table.size() - 1

func diff(prev: Dictionary, s: Dictionary) -> Dictionary:
	var d := {}
	for k in s:
		if k == "tok" and prev.has("tok"):
			var rows := []                             # tok: only the changed rows, as [[colour, row], ...]
			for c in 4:
				if prev.tok[c] != s.tok[c]:
					rows.append([c, s.tok[c]])
			if not rows.is_empty():
				d.tok = rows
		elif not prev.has(k) or JSON.stringify(prev[k], "", true, true) != JSON.stringify(s[k], "", true, true):
			d[k] = s[k]
	for k in prev:
		if not s.has(k):
			push_error("state key removed: %s" % k)   # the replay format can't express a removal
			bad += 1
	return d.duplicate(true)

func play_game(seed_: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	# seats: mostly the online layouts (2 -> Red + Yellow, 3 -> Red, Green, Yellow, 4 -> all), sometimes any layout
	var seats: Array
	var r := rng.randf()
	if r < 0.3:
		seats = [0, 2]
	elif r < 0.5:
		seats = [0, 1, 2]
	elif r < 0.9:
		seats = [0, 1, 2, 3]
	else:
		seats = []
		while seats.size() < 2:
			seats = []
			for c in 4:
				if rng.randf() < 0.6:
					seats.append(c)
	var all_human := rng.randf() < 0.5
	var players := ["off", "off", "off", "off"]
	for c in seats:
		players[c] = "human" if all_human or rng.randf() < 0.5 else "cpu"
	var teams := rng.randf() < (0.6 if seats.size() == 4 else 0.15)   # (fewer than 4: new_game turns it off)
	var opts := {pair_ask = rng.randf() < 0.6}
	var rng_by := RandomNumberGenerator.new()          # (its own generator: the games without it are unchanged)
	rng_by.seed = seed_ * 31 + 7
	if rng_by.randf() < 0.25:
		var by := []
		for c in 4:
			by.append(rng_by.randf() < 0.5)
		opts.pair_ask_by = by
	var levels := []
	for c in 4:
		levels.append(Ludo.LEVELS[rng.randi_range(0, 2)])
	var six_bias := rng.randf() * 0.15                 # some games roll more 6s (faster, more three-6s)
	var s := Ludo.new_game(players, teams, opts)
	var rec := {seed = seed_, args = {players = players.duplicate(), teams = teams, opts = opts}, levels = levels,
		s0 = s.duplicate(true), h0 = SH.of(s), steps = []}
	var prev := s.duplicate(true)
	var n := 0
	while s.phase != "over" and n < MAX_STEPS:
		n += 1
		var a := []                                    # [k, c, val]
		var ev := []
		var c: int = s.turn
		var x := rng.randf()
		if not s.finished.is_empty() and rng.randf() < 0.0015:
			# the server ends the match early (only ghosts left to finish): the rest ranked by progress
			a = ["end", -1, 0]
			ev = Ludo.end_game(s)
			if ev.is_empty():
				push_error("end refused mid-game")
				bad += 1
		elif x < 0.02:
			# a seat changes hands: a bot takes over / the player is back (any active seat, any phase)
			var act := []
			for k in 4:
				if s.players[k] != "off":
					act.append(k)
			var seat: int = act[rng.randi_range(0, act.size() - 1)]
			var mode := "cpu" if s.players[seat] == "human" else "human"
			a = ["mode", seat, mode]
			s.players[seat] = mode
		elif x < 0.03:
			# a refused action: wrong phase or a pawn that can't move (the rules return [] and change nothing)
			var y := rng.randi_range(0, 2)
			if y == 0 and s.phase != "roll":
				a = ["roll", c, rng.randi_range(1, 6)]
				ev = Ludo.apply_roll(s, a[2])
			elif y == 1 and s.phase != "pair_ask":
				a = ["pair", c, rng.randf() < 0.5]
				ev = Ludo.answer_pair(s, a[2])
			else:
				var cand := []
				for i in 4:
					if s.phase != "choose" or Ludo.unit_for_token(s, i).is_empty():
						cand.append(i)
				if cand.is_empty():
					continue
				a = ["move", c, cand[rng.randi_range(0, cand.size() - 1)]]
				ev = Ludo.move(s, a[2])
			if not ev.is_empty():
				push_error("refused action produced events: %s" % JSON.stringify(a))
				bad += 1
		elif s.phase == "roll":
			var v := 6 if rng.randf() < six_bias else rng.randi_range(1, 6)
			a = ["roll", c, v]
			ev = Ludo.apply_roll(s, v)
		elif s.phase == "choose":
			var i := -1
			if s.players[c] == "cpu":
				i = Ludo.pick_ai(s, Ludo.movables(s), rng, levels[c])
			else:
				var auto := Ludo.auto_move_token(s)
				if auto >= 0 and rng.randf() < 0.5:
					i = auto
				else:
					var us := Ludo.units(s)
					var u: Dictionary = us[rng.randi_range(0, us.size() - 1)]
					i = u.tokens[rng.randi_range(0, u.tokens.size() - 1)]   # either pawn of a pair moves it
			a = ["move", c, i]
			ev = Ludo.move(s, i)
			if ev.is_empty():
				push_error("legal move refused: %s" % JSON.stringify(a))
				bad += 1
		elif s.phase == "pair_ask":
			a = ["pair", c, rng.randf() < 0.6]
			ev = Ludo.answer_pair(s, a[2])
		else:
			break
		var h := SH.of(s)
		if SH.of(JSON.parse_string(JSON.stringify(s))) != h:
			push_error("hash changed through JSON")      # numbers come back as floats
			bad += 1
		var step := [a[0], a[1], a[2], intern_events(ev), h, diff(prev, s)]
		if a[0] == "roll" and s.phase == "choose" and not ev.is_empty() and rng.randf() < 0.15:
			step.append({auto = Ludo.auto_move_token(s), units = Ludo.units(s)})
		elif s.phase == "pair_ask":
			step.append({pair_default = Ludo.default_pair_answer(s)})   # the timeout's / a bot's answer
		rec.steps.append(step)
		prev = s.duplicate(true)
	if s.phase == "over" and rng.randf() < 0.3:
		var ev := Ludo.end_game(s)                     # a refused "end" (already over): no events, no change
		if not ev.is_empty():
			push_error("end after over produced events")
			bad += 1
		rec.steps.append(["end", -1, 0, intern_events(ev), SH.of(s), diff(prev, s)])
	if s.phase == "over":
		rec["end"] = {standings = Ludo.standings(s), winners = Ludo.winners(s), win_reward = Ludo.win_reward(s),
			play_reward = Ludo.play_reward(s)}
	return rec
