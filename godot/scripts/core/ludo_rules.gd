class_name LudoRules
extends RefCounted
## Ludo rules, ported from index.html (dest, movables, victimsAt, pairPartner, stuckReason, roll, move, pickAI).
## Pure game logic: no nodes, no animation, no timers. Dice values are passed in (rolled by the client offline,
## by the server online), and the computer player's jitter uses an optional RandomNumberGenerator so tests and
## replays are repeatable.
##
## The state is a plain Dictionary of ints, bools, strings and arrays, so it saves as JSON and goes over the
## network unchanged. apply_roll / choose_pick / move / answer_pair change the state and return a list of events;
## the presentation layer animates those events and writes the status messages.
##
## State: { players[4] ("human" | "cpu" | "off"), names[4], view, tok[4][4], pairs [{c, a, b}], turn, dice, sixes,
##   phase, pick ("" | "single" | "pair"), winner, teams, free[4], pending, pair_ask, finished [colours] }
## Phases: "roll" -> "choose" (every legal unit may be tapped: see units()) -> "pair_ask" (only with the house rule
## pair_ask, for a human: make a pair?) -> ... "over". apply_roll no longer produces "pick" (the old Single / Pair
## step); choose_pick / picked still work for old callers. s.finished lists the colours in the order they got all
## four pawns home (standings()); at the end it holds every playing colour in final order.
##
## Play on after the first finish (real Ludo): a side that finishes (a colour with all four pawns home; in Teams both
## partners, the team finishing together) gets its place (event {type "finished", c, place, team?}) and is skipped
## from then on (next_active), while the others play on for the next places. The game is over ("over", one
## game_over event {winner, team, order}) when fewer than two sides are left unfinished, or when no unfinished side
## has a "human" seat (vs Computer: once you are done you don't watch the computers finish). Then the unfinished
## sides are ranked by progress (standings()) and s.finished becomes the full order; s.winner is the first finisher
## (in Teams: the colour that brought its team home). end_game(s) ends a game early the same way (the server's
## {k: "end"}). Rule (b) is checked only when a side finishes (a seat switching between human and cpu never ends a
## game by itself). Captures, pairs, splits, three 6s and Free Hand are unchanged: a finished colour has no pawn on
## the track, so it can't block or be captured.
## Progress per token: -1 base, 0-50 track, 51-55 home column, 56 (GOAL) finished.
## Colours: 0 red, 1 green, 2 yellow, 3 blue.

const OFF := [0, 13, 26, 39]          # each colour's start square (its Home Base cell) on the 52-cell track
const STARS := [8, 21, 34, 47]
const SAFE := [0, 13, 26, 39, 8, 21, 34, 47]
const GOAL := 56
const NO_MOVE := -1                   # dest() result for an illegal move (a legal destination is always >= 0)
const COLOR_NAMES := ["Red", "Green", "Yellow", "Blue"]
const CPU_NAMES := ["Mocha", "Biscotti", "Espresso"]
const WIN_REWARD := 200               # coins for beating the computer
const PLAY_REWARD := 20               # coins for finishing a game you lost against the computer (participation)


# ---------- setup ----------

## opts: {pair_ask: bool} - the "Ask before pairing" house rule (default false: a single landing on a loose pawn of
## its own colour off a safe square pairs up by itself, for humans and computers alike).
static func new_game(players: Array, teams := false, opts := {}) -> Dictionary:
	teams = teams and players.all(func(p): return p != "off")   # Pair Mode needs all four seats
	var humans := players.count("human")
	var names := []
	var cpu_no := 0
	for c in 4:
		if players[c] == "off":
			names.append("")
		elif players[c] == "cpu":
			names.append(CPU_NAMES[cpu_no] if cpu_no < CPU_NAMES.size() else COLOR_NAMES[c])   # (4 computers: sims)
			cpu_no += 1
		else:
			names.append("You" if humans == 1 else COLOR_NAMES[c])
	var h := players.find("human")
	return {
		players = players.duplicate(), names = names, view = h if h >= 0 else 0,
		tok = [[-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]], pairs = [],
		turn = players.find_custom(func(p): return p != "off"), dice = 0, sixes = 0, phase = "roll", pick = "",
		winner = -1, teams = teams, free = [false, false, false, false], pending = {},
		pair_ask = bool(opts.get("pair_ask", false)), finished = [],
	}


# ---------- board helpers ----------

static func abs_index(c: int, p: int) -> int:
	return (OFF[c] + p) % 52

static func active(s: Dictionary, c: int) -> bool:
	return s.players[c] != "off"

static func is_human(s: Dictionary, c: int) -> bool:
	return s.players[c] == "human"

static func pname(s: Dictionary, c: int) -> String:
	return s.names[c] if s.names[c] != "" else COLOR_NAMES[c]

## Colour c is "you": the only human at the table (vs Computer). Never true in Pass & Play. Use this, never the
## display name, to decide anything.
static func is_you(s: Dictionary, c: int) -> bool:
	return c >= 0 and c < 4 and s.players[c] == "human" and s.players.count("human") == 1

## Grammar-safe pieces for status messages: subject "You" / "Mocha", object "you" / "Mocha", possessive
## "Your" / "Mocha's" (cap false: "your"), and verb(s, c, "roll", "rolls") -> "roll" for you, "rolls" for others.
static func subject(s: Dictionary, c: int) -> String:
	return "You" if is_you(s, c) else pname(s, c)

static func object(s: Dictionary, c: int) -> String:
	return "you" if is_you(s, c) else pname(s, c)

static func poss(s: Dictionary, c: int, cap := true) -> String:
	if is_you(s, c):
		return "Your" if cap else "your"
	return pname(s, c) + "'s"

static func verb(s: Dictionary, c: int, base: String, third: String) -> String:
	return base if is_you(s, c) else third

## The next colour that plays after c: active and its side not finished yet (play on: finished sides sit out).
static func next_active(s: Dictionary, c: int) -> int:
	for k in range(1, 5):
		var n := (c + k) % 4
		if active(s, n) and not side_done(s, n):
			return n
	return c

## Colour c's side has finished (has its place): individual games, c is in s.finished; Teams, c and its partner
## both have all four pawns home (a colour home alone still rolls: it helps its partner, Free Hand).
static func side_done(s: Dictionary, c: int) -> bool:
	if team_on(s):
		return all_home(s, c) and all_home(s, mate_of(c))
	return _finished(s).has(c)


# ---------- Team (Pair Mode) games: 4 players, opposite seats are partners (Red + Yellow, Green + Blue) ----------
# s.teams is true only in a Pair Mode game; s.free[c] records that colour c, having finished its own four pawns,
# rolled the 6 that starts its Free Hand: from then on c's rolls move its partner's pawns. A team wins when both
# partners have all four pawns home. Partners never capture or block each other. Individual games: s.teams is false
# and every helper below falls back to the classic rules. (Not to be confused with s.pairs: two same-colour pawns
# joined on one square.)

static func team_on(s: Dictionary) -> bool:
	return s.teams

static func mate_of(c: int) -> int:
	return (c + 2) % 4

static func all_home(s: Dictionary, c: int) -> bool:
	return s.tok[c].all(func(p): return p >= GOAL)

## Whose pawns c can capture / is blocked by.
static func foe(s: Dictionary, c: int, o: int) -> bool:
	return o != c and active(s, o) and not (team_on(s) and o == mate_of(c))

## Finished, Free Hand not started yet.
static func waiting_six(s: Dictionary, c: int) -> bool:
	return team_on(s) and all_home(s, c) and not s.free[c]

## Whose pawns c's roll moves.
static func mover_of(s: Dictionary, c: int) -> int:
	return mate_of(c) if team_on(s) and all_home(s, c) else c

## The team's name for messages: "Your team" when you play in it, else its players ("Mocha + Espresso",
## "Red + Yellow" in Pass & Play).
static func team_name(s: Dictionary, c: int) -> String:
	var m := mate_of(c)
	if is_you(s, c) or is_you(s, m):
		return "Your team"
	return "%s + %s" % [pname(s, mini(c, m)), pname(s, maxi(c, m))]

## The team by its colours, always: "Red + Yellow" / "Green + Blue".
static func team_label(_s: Dictionary, c: int) -> String:
	var m := mate_of(c)
	return "%s + %s" % [COLOR_NAMES[mini(c, m)], COLOR_NAMES[maxi(c, m)]]


# ---------- Pairs: two same-colour tokens joined on one main-track square ----------
# s.pairs = [{c, a, b}]: token indices a < b of colour c. Both tokens always share one progress value.
# A pair moves half the roll on even rolls only, blocks opponent single tokens, captures and can be captured
# only by an opposing pair, and splits by itself when it lands on any player's start square (the coloured square
# where tokens enter the track, i.e. that player's Home Base cell) or enters its home column (progress 51-55).
# Pairs never form on a start square or in a home column.

## The pair token i of colour c belongs to, or {} when it is a single.
static func pair_of(s: Dictionary, c: int, i: int) -> Dictionary:
	for q in s.pairs:
		if q.c == c and (q.a == i or q.b == i):
			return q
	return {}

static func unit_of(s: Dictionary, c: int, i: int) -> Array:
	var q := pair_of(s, c, i)
	return [i] if q.is_empty() else [q.a, q.b]

## An opponent pair standing on main-track square `abs`, or {}.
static func opp_pair_at(s: Dictionary, c: int, abs_sq: int) -> Dictionary:
	for q in s.pairs:
		if not foe(s, c, q.c):
			continue
		var p: int = s.tok[q.c][q.a]
		if p >= 0 and p <= 50 and abs_index(q.c, p) == abs_sq:
			return q
	return {}

## Any colour's Home Base cell.
static func on_start_square(c: int, p: int) -> bool:
	return p >= 0 and p <= 50 and OFF.has(abs_index(c, p))

static func _remove_pair(s: Dictionary, c: int, i: int) -> void:
	s.pairs = s.pairs.filter(func(q): return not (q.c == c and (q.a == i or q.b == i)))


# ---------- moves ----------

## Where token i (or the pair it belongs to) lands with roll d, or NO_MOVE when the move is illegal.
static func dest(s: Dictionary, c: int, i: int, d: int) -> int:
	var p: int = s.tok[c][i]
	var pair := not pair_of(s, c, i).is_empty()
	if p >= GOAL:
		return NO_MOVE
	if p < 0:
		return 0 if d == 6 else NO_MOVE
	if pair and d % 2:
		return NO_MOVE                             # pairs use even rolls only…
	var to := p + (d / 2 if pair else d)          # …and move half the roll
	if to > GOAL:
		return NO_MOVE
	# blockades stop single tokens only: a single can't jump an opponent pair and needs exactly a 1 to leave
	# its square. A moving pair passes opposing pairs freely (its own even-roll rule still applies).
	if not pair and not _blocker(s, c, i, d).is_empty():
		return NO_MOVE
	return to

## The opponent pair that stops single token i (on the board) moving d squares, or {}.
static func _blocker(s: Dictionary, c: int, i: int, d: int) -> Dictionary:
	var p: int = s.tok[c][i]
	if p < 0:
		return {}
	if p <= 50 and d != 1:
		var here := opp_pair_at(s, c, abs_index(c, p))
		if not here.is_empty():
			return here
	for q in range(p + 1, p + d):
		if q > 50:
			break
		var on := opp_pair_at(s, c, abs_index(c, q))
		if not on.is_empty():
			return on
	return {}

static func can_move(s: Dictionary, c: int, i: int, d: int) -> bool:
	return dest(s, c, i, d) != NO_MOVE

## One entry per movable unit of the player whose turn it is; a pair is listed once, by its first token.
## (Uses s.dice, so it means something only in phase "choose".)
static func movables(s: Dictionary) -> Array:
	if waiting_six(s, s.turn):
		return []                                  # a finished partner moves nothing until its Free Hand starts
	var c := mover_of(s, s.turn)
	var out := []
	for i in 4:
		var q := pair_of(s, c, i)
		if (q.is_empty() or q.a == i) and can_move(s, c, i, s.dice):
			out.append(i)
	return out

## Tokens sent home by a landing on progress `to`, as [[colour, token], ...]: a pair takes only an opposing pair
## (never a single token); a single token takes one loose token and never a pair. Safe squares protect everyone.
## A pair that lands on a lone opposing token simply shares the square with it.
static func victims_at(s: Dictionary, c: int, to: int, is_pair: bool) -> Array:
	if to > 50:
		return []
	var a := abs_index(c, to)
	if SAFE.has(a):
		return []
	if is_pair:
		var q := opp_pair_at(s, c, a)
		return [] if q.is_empty() else [[q.c, q.a], [q.c, q.b]]
	for o in 4:
		if not foe(s, c, o):
			continue                               # never your own colour or your partner's
		for j in 4:
			var p: int = s.tok[o][j]
			if p >= 0 and p <= 50 and abs_index(o, p) == a and pair_of(s, o, j).is_empty():
				return [[o, j]]
	return []

## A loose token of the same colour already on the main-track square token i just landed on (-1 if none).
## Start squares (every colour's Home Base cell) never offer a pair.
static func pair_partner(s: Dictionary, c: int, i: int) -> int:
	var p: int = s.tok[c][i]
	if p < 0 or p > 50 or on_start_square(c, p) or not pair_of(s, c, i).is_empty():
		return -1
	for k in 4:
		if k != i and s.tok[c][k] == p and pair_of(s, c, k).is_empty():
			return k
	return -1

## Why a roll left nothing to move (colour c's pawns, roll d), for the status line after "Mocha rolled 4.":
## "Blocked by Blue's pair." / "Blocked by your pair.", "A pair needs an even roll.", else "No move this time.".
## On a 6 (the player keeps the turn) the text says so: "No move. Roll again." / "Blocked by ... Roll again."
static func stuck_reason(s: Dictionary, c: int, d: int) -> String:
	var again := " Roll again." if d == 6 else ""
	var pair_odd := false
	for i in 4:
		var p: int = s.tok[c][i]
		if p < 0 or p >= GOAL:
			continue
		if not pair_of(s, c, i).is_empty():
			pair_odd = pair_odd or d % 2 == 1
			continue
		if p + d > GOAL:
			continue
		var q := _blocker(s, c, i, d)
		if not q.is_empty():
			return "Blocked by %s pair.%s" % [poss(s, q.c, false), again]
	if pair_odd:
		return "A pair needs an even roll."
	return "No move. Roll again." if d == 6 else "No move this time."


# ---------- turn flow ----------

## The dice show v for the player whose turn it is (phase "roll").
static func apply_roll(s: Dictionary, v: int) -> Array:
	if s.phase != "roll":
		return []
	var c: int = s.turn
	var ev := [{type = "rolled", c = c, v = v}]
	s.dice = v
	s.sixes = s.sixes + 1 if v == 6 else 0
	if s.sixes == 3:
		s.sixes = 0
		ev.append({type = "three_sixes", c = c})
		_next_turn(s, ev)
		return ev
	if waiting_six(s, c):
		if v != 6:                                 # a finished partner needs a 6 before it may help
			ev.append({type = "need_six", c = c, v = v})
			_next_turn(s, ev)
			return ev
		s.free[c] = true                           # remembered for the rest of the game
		ev.append({type = "free_hand", c = c, mate = mate_of(c)})
	var mc := mover_of(s, c)
	var mv := movables(s)
	if mv.is_empty():
		ev.append({type = "stuck", c = c, mover = mc, reason = stuck_reason(s, mc, v)})
		if v == 6:
			_begin_turn(s, ev)
		else:
			_next_turn(s, ev)
		return ev
	# every legal unit (singles and pairs alike) may be tapped: the tap decides, there is no Single / Pair step
	s.phase = "choose"
	ev.append({type = "choose", c = c, mover = mc, movable = mv})
	return ev

## Legacy (the old Single / Pair step; apply_roll no longer asks): a human narrows this turn's choice to one kind of
## unit. False if none of that kind can move. Works in phase "choose" (and "pick" from old saved games).
static func choose_pick(s: Dictionary, kind: String) -> bool:
	if not is_human(s, s.turn) or not (kind == "single" or kind == "pair"):
		return false
	if s.phase != "pick" and s.phase != "choose":
		return false
	if picked(s, kind).is_empty():
		return false
	s.pick = kind
	s.phase = "choose"
	return true

## The movable units of one kind ("single" or "pair").
static func picked(s: Dictionary, kind: String) -> Array:
	var c := mover_of(s, s.turn)
	return movables(s).filter(func(i): return (not pair_of(s, c, i).is_empty()) == (kind == "pair"))

## Every legal unit for this roll, so the board can light them all and map a tapped pawn to its unit. One entry
## per unit: {mover (whose pawns), tokens ([i] or [a, b]), token (lead index, what move() takes), pair, from, to}.
## A paired pawn never moves alone: both pawns of a pair map to the pair's entry.
static func units(s: Dictionary) -> Array:
	var c := mover_of(s, s.turn)
	var d: int = s.dice
	var out := []
	for i in _legal(s):
		var q := pair_of(s, c, i)
		out.append({mover = c, tokens = unit_of(s, c, i), token = i, pair = not q.is_empty(), from = s.tok[c][i],
			to = dest(s, c, i, d)})
	return out

## The legal unit pawn i (of the colour the roll moves) belongs to, or {} when that pawn can't move.
static func unit_for_token(s: Dictionary, i: int) -> Dictionary:
	for u in units(s):
		if u.tokens.has(i):
			return u
	return {}

## The movable units this turn (the legacy Single / Pair choice narrows them).
static func _legal(s: Dictionary) -> Array:
	return picked(s, s.pick) if s.pick != "" else movables(s)

## The token a human's move goes to without a tap: the only movable unit, the first when all are at base, or the
## first when every option is the same move (same kind of unit from the same square). -1 when the player has to
## choose.
static func auto_move_token(s: Dictionary) -> int:
	if s.phase != "choose":
		return -1
	var c := mover_of(s, s.turn)
	var mv := _legal(s)
	if mv.is_empty():
		return -1
	if mv.size() == 1 or mv.all(func(i): return s.tok[c][i] < 0):
		return mv[0]
	var first_pair := not pair_of(s, c, mv[0]).is_empty()
	var first_from: int = s.tok[c][mv[0]]
	if mv.all(func(i): return s.tok[c][i] == first_from and (not pair_of(s, c, i).is_empty()) == first_pair):
		return mv[0]
	return -1

## Move token i (or its whole pair) by the dice (phase "choose"). Returns no events when the move isn't allowed.
static func move(s: Dictionary, i: int) -> Array:
	if s.phase != "choose":
		return []
	var roller: int = s.turn
	var c := mover_of(s, roller)                   # whose pawns move (the partner's under Free Hand)
	var d: int = s.dice
	if waiting_six(s, roller):
		return []
	var pair := pair_of(s, c, i)
	var is_pair := not pair.is_empty()
	if is_pair:
		i = pair.a                                 # either token of a pair moves the whole pair
	if s.pick != "" and (s.pick == "pair") != is_pair:
		return []                                  # honour the Single / Pair choice
	var to := dest(s, c, i, d)
	if to == NO_MOVE:
		return []
	s.pick = ""
	var unit := unit_of(s, c, i)
	var from: int = s.tok[c][i]
	for j in unit:
		s.tok[c][j] = to
	var ev := [{type = "move", c = c, roller = roller, tokens = unit, from = from, to = to, pair = is_pair}]
	if is_pair and to >= GOAL:
		_remove_pair(s, c, i)                      # both reached the centre

	var extra := d == 6
	var victims := victims_at(s, c, to, is_pair)
	if not victims.is_empty():
		extra = true
		for v in victims:
			_remove_pair(s, v[0], v[1])
			s.tok[v[0]][v[1]] = -1
		ev.append({type = "capture", c = c, victims = victims})

	# a pair landing on any colour's start square, or entering its home column (progress 51-55, the coloured lane
	# to the centre), splits by itself, once, right after it arrives; both tokens stay on that cell as singles
	if is_pair and (to > 50 and to < GOAL or to <= 50 and on_start_square(c, to)):
		_remove_pair(s, c, i)
		ev.append({type = "split", c = c, tokens = unit, where = "lane" if to > 50 else "start"})

	# a single token landing on a loose token of its own colour pairs up by itself off safe squares (computers
	# always; humans too unless the "Ask before pairing" house rule is on, then the human is asked, anywhere)
	var pend := {c = c, i = i, to = to, extra = extra}
	var partner := pair_partner(s, c, i)
	if partner >= 0:
		if is_human(s, roller) and bool(s.get("pair_ask", false)):
			pend["partner"] = partner
			s.pending = pend
			s.phase = "pair_ask"
			ev.append({type = "pair_offer", c = c, a = i, b = partner})
			return ev
		if not SAFE.has(abs_index(c, to)):
			_form_pair(s, c, i, partner, ev)
	_finish_move(s, pend, ev)
	return ev

## Human only: the answer to "make a pair?" (phase "pair_ask").
static func answer_pair(s: Dictionary, yes: bool) -> Array:
	if s.phase != "pair_ask":
		return []
	var pend: Dictionary = s.pending
	s.pending = {}
	var ev := []
	if yes:
		_form_pair(s, pend.c, pend.i, pend.partner, ev)
	_finish_move(s, pend, ev)
	return ev

static func _form_pair(s: Dictionary, c: int, i: int, partner: int, ev: Array) -> void:
	if not pair_of(s, c, i).is_empty() or not pair_of(s, c, partner).is_empty():
		return
	s.pairs.append({c = c, a = mini(i, partner), b = maxi(i, partner)})
	ev.append({type = "pair_formed", c = c, a = mini(i, partner), b = maxi(i, partner), human = is_human(s, s.turn)})

static func _finish_move(s: Dictionary, pend: Dictionary, ev: Array) -> void:
	var c: int = pend.c
	var to: int = pend.to
	var extra: bool = pend.extra
	if to == GOAL:
		extra = true
		ev.append({type = "home", c = c})
		if all_home(s, c):
			_mark_finished(s, c)                   # (Teams: each colour's own order; standings() lists partners by it)
			if not team_on(s) or all_home(s, mate_of(c)):
				_side_finished(s, c, ev)           # a colour (Teams: both partners, the team together) has its place
				if s.phase == "over":
					return
			else:
				ev.append({type = "all_home", c = c})   # Teams: four home, the partner still playing (Free Hand next)
	if extra and not side_done(s, s.turn):
		_begin_turn(s, ev)
	else:
		_next_turn(s, ev)                          # (a side that just finished hands the turn on, extra or not)

static func _begin_turn(s: Dictionary, ev: Array) -> void:   # the same player again; the 6s count carries on
	s.phase = "roll"
	s.pick = ""
	ev.append({type = "turn", c = s.turn, again = true})

static func _next_turn(s: Dictionary, ev: Array) -> void:
	s.sixes = 0
	s.turn = next_active(s, s.turn)
	s.phase = "roll"
	s.pick = ""
	ev.append({type = "turn", c = s.turn, again = false})

## Colour c's side just finished (c: the colour whose pawn came home last): its place, then is the game over?
static func _side_finished(s: Dictionary, c: int, ev: Array) -> void:
	var place := 0
	for side in _sides(s):
		if side_done(s, side[0]):
			place += 1
	var e := {type = "finished", c = c, place = place}
	if team_on(s):
		e["team"] = [mini(c, mate_of(c)), maxi(c, mate_of(c))]
	ev.append(e)
	var left := 0
	var human := false
	for side in _sides(s):
		if side_done(s, side[0]):
			continue
		left += 1
		for k in side:
			human = human or is_human(s, k)
	if left < 2 or not human:
		_game_over(s, c if place == 1 else -1, ev)

## The sides of the game, each a list of colours: [[c], ...] for the active colours; Teams [[0, 2], [1, 3]].
static func _sides(s: Dictionary) -> Array:
	if team_on(s):
		return [[0, 2], [1, 3]]
	var out := []
	for c in 4:
		if active(s, c):
			out.append([c])
	return out

## The end: the unfinished sides are ranked by progress after the finished ones (standings()), s.finished becomes
## that full order and s.winner the first finisher (w; -1: the first in that order).
static func _game_over(s: Dictionary, w: int, ev: Array) -> void:
	if w < 0 and not team_on(s) and not _finished(s).is_empty():
		w = s.finished[0]
	s.winner = w                               # (Teams: standings() puts the winning team first)
	var order := standings(s).map(func(e): return int(e.color))
	if w < 0:
		w = order[0]
		s.winner = w
	s.finished = order
	s.phase = "over"
	s.pick = ""
	s.pending = {}
	ev.append({type = "game_over", winner = w, team = winners(s), order = order.duplicate()})

## Ends the game now (the server's {k: "end"}: only ghosts are left to finish, say): the unfinished sides are ranked
## by progress, exactly as at a natural end. [] when the game is already over.
static func end_game(s: Dictionary) -> Array:
	if s.phase == "over":
		return []
	var ev := []
	_game_over(s, -1, ev)
	return ev

static func _finished(s: Dictionary) -> Array:
	if not s.get("finished") is Array:
		s.finished = []                            # states saved before finish order was recorded
	elif s.finished.any(func(x): return typeof(x) != TYPE_INT):
		s.finished = s.finished.map(func(x): return int(x))   # came through JSON as floats
	return s.finished

static func _mark_finished(s: Dictionary, c: int) -> void:
	if not _finished(s).has(c):
		s.finished.append(c)


# ---------- results ----------

## The winning colours: the winner, plus the partner in Pair Mode.
static func winners(s: Dictionary) -> Array:
	if s.winner < 0:
		return []
	return [s.winner, mate_of(s.winner)] if team_on(s) else [s.winner]

## Coins for the finished game: beating the computer pays out (when you, the only human, are a winner).
static func win_reward(s: Dictionary) -> int:
	if s.phase != "over" or not s.players.has("cpu"):
		return 0
	return WIN_REWARD if winners(s).any(func(k): return is_you(s, k)) else 0

## Coins for playing a game vs the computer to the end and losing it (a small participation reward, so a loss still
## pays something). 0 for a win (win_reward pays), Pass & Play, a game with no "you", or a game not over.
static func play_reward(s: Dictionary) -> int:
	if s.phase != "over" or not s.players.has("cpu") or win_reward(s) > 0:
		return 0
	for k in 4:
		if active(s, k) and is_you(s, k):
			return PLAY_REWARD
	return 0

## How far colour c has come, 0 (all at base) to 1 (all four home).
static func progress(s: Dictionary, c: int) -> float:
	var n := 0
	for p in s.tok[c]:
		n += maxi(0, mini(int(p), GOAL) + 1)
	return n / (4.0 * (GOAL + 1))

## Placings for every active colour: {color, place (1-based), finished (all four home), progress (0-1)}.
## Individual: colours that finished come first in finish order, then the rest by progress (ties: seat order).
## Teams: both partners share their team's place; the winning team (or, mid-game, the team further on) is 1st,
## partners listed finished first, then by progress.
static func standings(s: Dictionary) -> Array:
	var fin := _finished(s)
	var cols := []
	for c in 4:
		if active(s, c):
			cols.append(c)
	var by_finish := func(a: int, b: int) -> bool:
		var fa := fin.find(a)
		var fb := fin.find(b)
		if (fa >= 0) != (fb >= 0):
			return fa >= 0
		if fa >= 0:
			return fa < fb
		var pa := progress(s, a)
		var pb := progress(s, b)
		return pa > pb if pa != pb else a < b
	cols.sort_custom(by_finish)
	var out := []
	if not team_on(s):
		for n in cols.size():
			out.append({color = cols[n], place = n + 1, finished = all_home(s, cols[n]), progress = progress(s, cols[n])})
		return out
	var teams_ := [[0, 2], [1, 3]]
	var score := func(t: Array) -> float:   # winners first, then a team with more of its pawns home / further on
		if s.winner >= 0 and t.has(s.winner):
			return 1000.0
		return progress(s, t[0]) + progress(s, t[1])
	teams_.sort_custom(func(a, b): return score.call(a) > score.call(b) if score.call(a) != score.call(b) else a[0] < b[0])
	for n in teams_.size():
		var members: Array = teams_[n].duplicate()
		members.sort_custom(by_finish)
		for c in members:
			out.append({color = c, place = n + 1, finished = all_home(s, c), progress = progress(s, c)})
	return out


# ---------- computer player: score each legal move ----------
# Levels differ only in how a move is chosen; the dice are the same uniform rolls for everyone.
#   "easy":   a random legal move (half the time it takes a move that finishes a pawn; it never dodges danger).
#   "normal": scores every move (finish, leave base, capture, safety, running from a threat) plus a little jitter.
#   "hard":   the same move values plus a one-turn risk lookahead: it plays the move on a copy of the state and
#             compares the expected loss of its pawns before and after (every enemy unit that could hit one of
#             them next roll, weighted by how far that pawn has come). So it lands out of reach, runs from threats,
#             pairs up on threatened squares (only a pair can take a pair) and captures the pawns that threaten it.

const LEVELS := ["easy", "normal", "hard"]
const RISK_W := 4.0                   # hard: weight of the expected-loss change

static func threat_at(s: Dictionary, c: int, abs_sq: int) -> bool:
	return threats_at(s, c, abs_sq) > 0

## How many opponent single pawns stand 1-6 squares behind main-track square abs_sq (0 on safe squares): the
## pawns that could capture a single of colour c there with one roll.
static func threats_at(s: Dictionary, c: int, abs_sq: int) -> int:
	if SAFE.has(abs_sq):
		return 0
	var n := 0
	for o in 4:
		if not foe(s, c, o):
			continue
		for j in 4:
			var p: int = s.tok[o][j]
			if p < 0 or p > 50 or not pair_of(s, o, j).is_empty():
				continue                           # pairs can't capture single tokens
			var d := (abs_sq - abs_index(o, p) + 52) % 52
			if d >= 1 and d <= 6:
				n += 1
	return n

## The computer's move: one of mv (from movables()), by level "easy" / "normal" / "hard" (anything else: normal).
static func pick_ai(s: Dictionary, mv: Array, rng: RandomNumberGenerator = null, level := "normal") -> int:
	if mv.is_empty():
		return -1
	if level == "easy":
		return _pick_easy(s, mv, rng)
	var hard := level == "hard"
	var c := mover_of(s, s.turn)                   # under Free Hand the computer plays its partner's pawns
	var best: int = mv[0]
	var best_score := -INF
	for i in mv:
		var sc := (_score_hard(s, c, i) if hard and mv.size() > 1 else _score(s, c, i, s.dice)) + _rand(rng) * 4
		if sc > best_score:
			best_score = sc
			best = i
	return best

static func _rand(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng else randf()

static func _pick_easy(s: Dictionary, mv: Array, rng: RandomNumberGenerator) -> int:
	var c := mover_of(s, s.turn)
	var d: int = s.dice
	var fin := mv.filter(func(i): return dest(s, c, i, d) == GOAL)
	if not fin.is_empty() and _rand(rng) < 0.5:
		return fin[0]
	return mv[mini(int(_rand(rng) * mv.size()), mv.size() - 1)]

## Normal: the web version's move scores.
static func _score(s: Dictionary, c: int, i: int, d: int) -> float:
	var p: int = s.tok[c][i]
	var to := dest(s, c, i, d)
	var pair := not pair_of(s, c, i).is_empty()
	var sc := to * 0.4
	if to == GOAL:
		sc += 160 if pair else 100
	if p < 0:
		sc += 60
	if p <= 50 and to > 50:
		sc += 45
	if to <= 50:
		var a := abs_index(c, to)
		var hits := victims_at(s, c, to, pair).size()
		if hits:
			sc += 120 if hits == 2 else 80
		elif SAFE.has(a):
			sc += 18
		if not pair and threat_at(s, c, a):
			sc -= 30                               # single tokens can't touch a pair
	if not pair and p >= 0 and p <= 50 and threat_at(s, c, abs_index(c, p)):
		sc += 25
	return sc

## Hard: the move values without the one-square threat checks, plus the change in expected loss over the move.
static func _score_hard(s: Dictionary, c: int, i: int) -> float:
	var d: int = s.dice
	var p: int = s.tok[c][i]
	var to := dest(s, c, i, d)
	var pair := not pair_of(s, c, i).is_empty()
	var sc := to * 0.4
	if to == GOAL:
		sc += 160 if pair else 100
	if p < 0:
		sc += 60
	if p <= 50 and to > 50:
		sc += 45
	if to <= 50:
		var victims := victims_at(s, c, to, pair)
		if victims.size():
			sc += (120 if victims.size() == 2 else 80) + int(s.tok[victims[0][0]][victims[0][1]]) * 0.5
		elif SAFE.has(abs_index(c, to)):
			sc += 10
	var after := s.duplicate(true)
	move(after, i)
	return sc + (risk(s, c) - risk(after, c)) * RISK_W

## Chance that a pawn k squares ahead of an enemy single is hit with its next roll (k itself, or a 6 then k - 6).
static func _hit_p(k: int) -> float:
	if k >= 1 and k <= 6:
		return 1.0 / 6.0
	if k >= 7 and k <= 12:
		return 1.0 / 36.0
	return 0.0

## Expected loss for colour c next turn: for each of its units on the main track off safe squares, the chance that
## an enemy unit able to capture it (singles take singles, pairs take pairs) lands on it, times what it would
## lose (its progress plus the 6 it needs to come back; double for a pair).
static func risk(s: Dictionary, c: int) -> float:
	var total := 0.0
	for i in 4:
		var p: int = s.tok[c][i]
		if p < 0 or p > 50:
			continue
		var a := abs_index(c, p)
		if SAFE.has(a):
			continue
		var q := pair_of(s, c, i)
		if not q.is_empty() and q.a != i:
			continue                               # count a pair once
		var safe_p := 1.0
		for o in 4:
			if not foe(s, c, o):
				continue
			for j in 4:
				var op: int = s.tok[o][j]
				if op < 0 or op > 50:
					continue
				var oq := pair_of(s, o, j)
				if q.is_empty() != oq.is_empty() or (not oq.is_empty() and oq.a != j):
					continue
				var k := (a - abs_index(o, op) + 52) % 52
				if op + k > 50:
					continue                       # that pawn turns into its home column first
				var hp := _hit_p(k) if oq.is_empty() else (1.0 / 6.0 if k >= 1 and k <= 3 else 0.0)
				safe_p *= 1.0 - hp
		total += (1.0 - safe_p) * (p + 12) * (1 if q.is_empty() else 2)
	return total
