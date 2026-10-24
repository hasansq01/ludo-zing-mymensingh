class_name SnakesLaddersRules
extends RefCounted
## Snakes & Ladders rules, ported from the SL module in index.html (land, replayReaches100, roll, newGame, win).
## Pure game logic like LudoRules: the state is a plain Dictionary, dice values are passed in, and apply_roll
## returns events for the presentation layer to animate.
##
## State: { mode ("cpu" | "local"), turn, phase ("roll" | "over"), sixes, winner, paid, need_one,
##   players [{c, name, you, cpu, pos, rolls, ladders, snakes}] }
## pos 0 is off the board; squares run 1-100. Entering the board: by default any roll v from square 0 moves to
## square v (ladders and snakes apply). The house rule need_one (Settings "Need a 1 to start", pref sl_need_one)
## brings back the web version's rule: off the board only a 1 enters, on square 1.

const LADDERS := {4: 14, 9: 31, 21: 42, 28: 84, 36: 44, 51: 67, 71: 91}   # 1 -> 38 and 80 -> 100 removed (2026-10-21)
const SNAKES := {16: 6, 47: 26, 49: 11, 56: 53, 62: 19, 64: 60, 87: 24, 93: 73, 95: 75, 98: 78}
const REWARD := 100                   # coins for beating the computer
const PLAY_REWARD := 10               # coins for finishing a game you lost against the computer (participation)
const COLOR_NAMES := ["Red", "Green", "Yellow", "Blue"]
const CPU_NAMES := ["Mocha", "Biscotti", "Espresso"]


## The rule in one place: where a roll of v from square `from` ends, and what happened on the way.
## need_one: the "Need a 1 to start" house rule (off the board, only a 1 enters).
static func land(from: int, v: int, need_one := false) -> Dictionary:
	if from == 0 and need_one and v != 1:
		return {to = 0, steps = 0, wait = true}    # off the board: only a 1 brings the pawn on
	var to := from + v
	if to > 100:
		return {to = from, steps = 0, over = true}
	if LADDERS.has(to):
		return {to = LADDERS[to], steps = v, via = to, ladder = true}
	if SNAKES.has(to):
		return {to = SNAKES[to], steps = v, via = to, snake = true}
	return {to = to, steps = v}

## Reward check: replay the human's rolls through the rules from square 0, the way apply_roll played them: the
## third 6 in a row is recorded but ends the turn without moving (a player's rolls only run on past a 6, so a run
## of 6s in the list is one turn's run). Rolls that came through JSON are floats, so whole-number floats count;
## anything outside 1-6 or fractional fails the check. need_one must be the house rule the game was played with.
static func replay_reaches_100(rolls: Array, need_one := false) -> bool:
	var pos := 0
	var sixes := 0
	for v in rolls:
		if not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT and v == floorf(v)):
			return false
		if v < 1 or v > 6:
			return false
		sixes = sixes + 1 if int(v) == 6 else 0
		if sixes == 3:                        # three 6s: the turn is over, the pawn stays
			sixes = 0
			continue
		pos = land(pos, int(v), need_one).to
		if pos == 100:
			return true
	return false

## vs Computer: you play `color`, the computers take the next colours round. Pass & Play: Red, Green, ...
## opts: {need_one: bool} (default false: any roll enters the board).
static func new_game(mode: String, n: int, color := 0, opts := {}) -> Dictionary:
	var players := []
	for k in n:
		var c := (color + k) % 4 if mode == "cpu" else k
		players.append({
			c = c, name = ("You" if k == 0 else CPU_NAMES[k - 1]) if mode == "cpu" else COLOR_NAMES[c],
			you = mode == "cpu" and k == 0, cpu = mode == "cpu" and k > 0,
			pos = 0, rolls = [], ladders = 0, snakes = 0,
		})
	return {mode = mode, turn = 0, phase = "roll", sixes = 0, winner = -1, paid = false, players = players,
		need_one = bool(opts.get("need_one", false))}

## The house rule in force for game g (a state saved before the option existed has no field: any roll enters).
static func needs_one(g: Dictionary) -> bool:
	return bool(g.get("need_one", false))

static func current(g: Dictionary) -> Dictionary:
	return g.players[g.turn]

## The dice show v for the player whose turn it is (phase "roll").
static func apply_roll(g: Dictionary, v: int) -> Array:
	if g.phase != "roll":
		return []
	var p := current(g)
	var ev := [{type = "rolled", turn = g.turn, v = v}]
	p.rolls.append(v)
	g.sixes = g.sixes + 1 if v == 6 else 0
	if g.sixes == 3:
		g.sixes = 0
		ev.append({type = "three_sixes", turn = g.turn})
		_next(g, ev)
		return ev
	var r := land(p.pos, v, needs_one(g))
	if r.has("wait") or r.has("over"):
		ev.append({type = "wait" if r.has("wait") else "over", turn = g.turn, v = v, need = 100 - p.pos})
		if v == 6:
			_again(g, ev)
		else:
			_next(g, ev)
		return ev
	var from: int = p.pos
	p.pos = r.to
	ev.append({type = "move", turn = g.turn, from = from, to = r.to, steps = r.steps, via = r.get("via", 0),
		ladder = r.has("ladder"), snake = r.has("snake")})
	if r.has("ladder"):
		p.ladders += 1
	elif r.has("snake"):
		p.snakes += 1
	if p.pos == 100:
		g.phase = "over"
		g.winner = g.turn
		ev.append({type = "win", turn = g.turn})
		return ev
	if v == 6:
		_again(g, ev)
	else:
		_next(g, ev)
	return ev

## Coins for the finished game, paid once: only you, only against the computer, and only when your recorded
## rolls really reach 100 under the rules.
static func claim_win_reward(g: Dictionary) -> int:
	if g.phase != "over" or g.paid or g.mode != "cpu":
		return 0
	var p: Dictionary = g.players[g.winner]
	if not p.you or not replay_reaches_100(p.rolls, needs_one(g)):
		return 0
	g.paid = true
	return REWARD

## Coins for a finished game vs the computer that you lost (participation), paid once (the same `paid` flag as the
## win reward): 0 for your win, Pass & Play or a game not over.
static func claim_play_reward(g: Dictionary) -> int:
	if g.phase != "over" or g.paid or g.mode != "cpu" or int(g.winner) < 0:
		return 0
	if g.players[g.winner].you or not g.players.any(func(p): return bool(p.you)):
		return 0
	g.paid = true
	return PLAY_REWARD

## Final placings: the winner first, then everyone else by square (ties keep turn order). One entry per player:
## {idx (index into g.players), color, name, place (1-based), finished (reached 100), pos, progress (0-1)}.
static func standings(g: Dictionary) -> Array:
	var order := []
	for k in g.players.size():
		order.append(k)
	var win: int = g.winner
	order.sort_custom(func(a, b):
		if (a == win) != (b == win):
			return a == win
		var pa: int = g.players[a].pos
		var pb: int = g.players[b].pos
		return pa > pb if pa != pb else a < b)
	var out := []
	for n in order.size():
		var p: Dictionary = g.players[order[n]]
		out.append({idx = order[n], color = p.c, name = p.name, place = n + 1, finished = p.pos >= 100,
			pos = p.pos, progress = clampf(p.pos / 100.0, 0.0, 1.0)})
	return out

static func _again(g: Dictionary, ev: Array) -> void:   # a 6: the same player rolls again (the 6s count carries on)
	g.phase = "roll"
	ev.append({type = "turn", turn = g.turn, again = true})

static func _next(g: Dictionary, ev: Array) -> void:
	g.sixes = 0
	g.turn = (g.turn + 1) % g.players.size()
	g.phase = "roll"
	ev.append({type = "turn", turn = g.turn, again = false})
