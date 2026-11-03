extends SceneTree
## Dev: records seeded random Snakes & Ladders games played with the GDScript rules, for the server's TS port parity
## test (server/test/rules_sl_parity.test.ts). Run from the repo root:
##   godot --headless --path godot -s res://dev/net_parity_dump_sl.gd [-- <games> <out.json>]
## Default: 300 games to server/test/fixtures/sl_traces.json (keep it under 4 MB).
##
## Games mix 2 / 3 / 4 players, vs Computer (any colour for you) and Pass & Play, need_one on / off, some 6-heavy
## dice (more three-6s and 6-overshoots), "mode" switches of a player between human and cpu at any moment (also for
## a colour that has no player: no change), and a few refused rolls after the game is over. Play on: games run past
## the first player home (several "finished" events, then "win"); some are ended early by the server's {k: "end"} once
## a player has finished (stored as ["end", -1, 0]); a refused "end" after the game is over now and then.
##
## File: {version, games, ev}. ev is a table of event lists (each distinct list stored once). Per game:
##   {seed, args: {mode, n, color, opts: {need_one}}, s0 (state after new_game), h0, steps, end?}
## and every step is the compact array
##   [k, c, val, ev_index, hash, diff]
## k / c / val: the protocol action ({k: "roll", c, v: val} | {k: "mode", c, mode: val}); ev_index: the events the
## rules returned; hash: SLStateHash.of() after the action; diff: the top-level state keys whose value changed (full
## values, except players: only the changed players, as [[index, fields, added_rolls?], ...] where fields holds the
## changed keys with their new values and added_rolls the rolls appended to that player's rolls), so applying the
## diffs in order to s0 rebuilds the full state after every step exactly. end (game over):
##   {standings, win_reward, play_reward, replay} (rewards claimed on copies of the final state; replay: for every
##   player, replay_reaches_100(rolls, need_one)).
##
## The "mode" action as clients apply it: for p in s.players: if p.c == c: p.cpu = mode == "cpu".

const SL := preload("res://scripts/core/snakes_ladders_rules.gd")
const SLH := preload("res://scripts/net/sl_state_hash.gd")

const MAX_STEPS := 3000

var ev_table := []        # event lists, each distinct JSON stored once
var ev_index := {}
var bad := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 300
	var out: String = args[1] if args.size() > 1 else ProjectSettings.globalize_path("res://").path_join("../server/test/fixtures/sl_traces.json").simplify_path()
	var recs := []
	var steps := 0
	var over := 0
	for g in games:
		var rec := play_game(5000 + g)
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

func same(a: Variant, b: Variant) -> bool:
	return JSON.stringify(a, "", true, true) == JSON.stringify(b, "", true, true)

## One player's changes: [fields, added_rolls or null].
func player_diff(a: Dictionary, b: Dictionary) -> Array:
	var fields := {}
	var added = null
	for k in b:
		if k == "rolls" and a.has("rolls"):
			var ra: Array = a.rolls
			var rb: Array = b.rolls
			if same(ra, rb):
				continue
			if rb.size() > ra.size() and same(rb.slice(0, ra.size()), ra):
				added = rb.slice(ra.size())
			else:
				fields.rolls = rb
		elif not a.has(k) or not same(a[k], b[k]):
			fields[k] = b[k]
	for k in a:
		if not b.has(k):
			push_error("player key removed: %s" % k)
			bad += 1
	return [fields, added]

func diff(prev: Dictionary, s: Dictionary) -> Dictionary:
	var d := {}
	for k in s:
		if k == "players" and prev.has("players") and prev.players.size() == s.players.size():
			var rows := []                             # only the changed players, as [[index, fields, added?], ...]
			for i in s.players.size():
				var pd := player_diff(prev.players[i], s.players[i])
				if pd[0].is_empty() and pd[1] == null:
					continue
				var row := [i, pd[0]]
				if pd[1] != null:
					row.append(pd[1])
				rows.append(row)
			if not rows.is_empty():
				d.players = rows
		elif not prev.has(k) or not same(prev[k], s[k]):
			d[k] = s[k]
	for k in prev:
		if not s.has(k):
			push_error("state key removed: %s" % k)   # the replay format can't express a removal
			bad += 1
	return d.duplicate(true)

## The protocol "mode" action, as a client applies it.
static func apply_mode(s: Dictionary, c: int, mode: String) -> void:
	for p in s.players:
		if int(p.c) == c:
			p.cpu = mode == "cpu"

func play_game(seed_: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var n := rng.randi_range(2, 4)
	var mode := "cpu" if rng.randf() < 0.5 else "local"
	var color := rng.randi_range(0, 3)
	var opts := {need_one = rng.randf() < 0.5}
	var six_bias := rng.randf() * 0.2                  # some games roll more 6s (more three-6s, 6-overshoots)
	var s := SL.new_game(mode, n, color, opts)
	var rec := {seed = seed_, args = {mode = mode, n = n, color = color, opts = opts.duplicate()},
		s0 = s.duplicate(true), h0 = SLH.of(s), steps = []}
	var prev := s.duplicate(true)
	var k := 0
	var refused := 0
	while k < MAX_STEPS:
		k += 1
		var a := []                                    # [k, c, val]
		var ev := []
		var x := rng.randf()
		if s.phase == "over":
			# a refused roll (or "end") after the end (the rules return [] and change nothing), sometimes twice
			if refused >= 2 or rng.randf() < 0.6:
				break
			refused += 1
			if rng.randf() < 0.3:
				a = ["end", -1, 0]
				ev = SL.end_game(s)
			else:
				a = ["roll", int(SL.current(s).c), rng.randi_range(1, 6)]
				ev = SL.apply_roll(s, a[2])
			if not ev.is_empty():
				push_error("refused action produced events: %s" % JSON.stringify(a))
				bad += 1
		elif not s.finished.is_empty() and rng.randf() < 0.01:
			# the server ends the match early (only ghosts left to finish): the rest ranked by square
			a = ["end", -1, 0]
			ev = SL.end_game(s)
		elif x < 0.03:
			# a player changes hands: a bot takes over / the player is back (any player, any moment)
			var p: Dictionary = s.players[rng.randi_range(0, s.players.size() - 1)]
			a = ["mode", int(p.c), "human" if p.cpu else "cpu"]
			apply_mode(s, a[1], a[2])
		elif x < 0.035:
			# a mode for a colour nobody plays (no change), or a repeat of the current mode
			var c := rng.randi_range(0, 3)
			var p = null
			for q in s.players:
				if int(q.c) == c:
					p = q
			a = ["mode", c, ("cpu" if p.cpu else "human") if p != null else ("cpu" if rng.randf() < 0.5 else "human")]
			apply_mode(s, a[1], a[2])
		else:
			var v := 6 if rng.randf() < six_bias else rng.randi_range(1, 6)
			a = ["roll", int(SL.current(s).c), v]
			ev = SL.apply_roll(s, v)
			if ev.is_empty():
				push_error("legal roll refused: %s" % JSON.stringify(a))
				bad += 1
		var h := SLH.of(s)
		if SLH.of(JSON.parse_string(JSON.stringify(s))) != h:
			push_error("hash changed through JSON")      # numbers come back as floats
			bad += 1
		rec.steps.append([a[0], a[1], a[2], intern_events(ev), h, diff(prev, s)])
		prev = s.duplicate(true)
	if s.phase == "over":
		var w := s.duplicate(true)
		var pl := s.duplicate(true)
		var replay := []
		for p in s.players:
			replay.append(SL.replay_reaches_100(p.rolls, SL.needs_one(s)))
		rec["end"] = {standings = SL.standings(s), win_reward = SL.claim_win_reward(w),
			play_reward = SL.claim_play_reward(pl), replay = replay}
	return rec
