class_name NetSL
extends NetReplica
## The online Snakes & Ladders replica (server/PROTOCOL.md "Game types", "S&L state hash"): the local
## SnakesLaddersRules state S from the server's `start` / `sync` (mode "online"; every player `you: false` on the
## wire: your own player gets `you: true` and the name "You" here, presentation only, never hashed), and one action
## at a time: `roll {c, v}` -> SnakesLaddersRules.apply_roll(S, v); `mode {c, mode}` -> that colour's player
## `cpu = mode == "cpu"`; `end {}` -> SnakesLaddersRules.end_game(S) (play on: the server ends the match early). The hash is SLStateHash. The only request is `roll`. S.me is your colour (-1: watching).


func _init() -> void:
	game = "sl"
	hash_fn = Callable(SLStateHash, "of")

## The local state from a server snapshot: the rules' types back (JSON gives floats), S.me = your colour, your
## player `you` and named "You", the others named as their seats.
static func localize(state: Dictionary, seats_: Array, me_id: String) -> Dictionary:
	var g := state.duplicate(true)
	for k in ["turn", "sixes"]:
		g[k] = int(g.get(k, 0))
	g.winner = int(g.get("winner", -1))
	g.mode = str(g.get("mode", "online"))
	g.phase = str(g.get("phase", "roll"))
	g.paid = bool(g.get("paid", false))
	g.need_one = bool(g.get("need_one", false))
	var fin := []
	for x in g.get("finished", []) if g.get("finished") is Array else []:
		fin.append(int(x))
	g.finished = fin
	var c := NetReplica.color_of(seats_, me_id)
	var players := []
	for p in g.get("players", []):
		var q: Dictionary = (p as Dictionary).duplicate(true) if p is Dictionary else {}
		q.c = int(q.get("c", 0))
		q.pos = int(q.get("pos", 0))
		q.cpu = bool(q.get("cpu", false))
		q.ladders = int(q.get("ladders", 0))
		q.snakes = int(q.get("snakes", 0))
		var rolls := []
		for r in q.get("rolls", []):
			rolls.append(int(r))
		q.rolls = rolls
		q.you = c >= 0 and q.c == c
		var seat_name := ""
		for st in seats_:
			if st is Dictionary and int(st.get("color", -1)) == q.c:
				seat_name = str(st.get("name", ""))
		q.name = "You" if q.you else (seat_name if seat_name != "" else str(q.get("name", "Player")))
		players.append(q)
	g.players = players
	g.me = c
	return g

func _localize(state: Dictionary, seats_: Array, me_id: String) -> Dictionary:
	return localize(state, seats_, me_id)

## The player (index into S.players) of colour c, or -1.
func index_of(c: int) -> int:
	for k in (S.get("players", []) as Array).size():
		if int(S.players[k].c) == c:
			return k
	return -1

## Apply one action with the offline rules; returns the rules' events (apply_roll's; none for `mode`).
func apply_rules(a: Dictionary) -> Array:
	n += 1
	match str(a.get("k", "")):
		"roll":
			return SnakesLaddersRules.apply_roll(S, int(a.get("v", 0)))
		"end":
			return SnakesLaddersRules.end_game(S)
		"mode":
			var c := int(a.get("c", -1))
			var cpu := str(a.get("mode", "")) == "cpu"
			for p in S.players:
				if int(p.c) == c:
					p.cpu = cpu
			for st in seats:
				if int(st.get("color", -1)) == c:
					st.bot = cpu
	return []

func turn_color() -> int:
	if S.is_empty() or (S.players as Array).is_empty():
		return -1
	return int(S.players[clampi(int(S.turn), 0, S.players.size() - 1)].c)

## Your roll now: your colour's turn, not played by a bot, the game not over.
func my_turn() -> bool:
	if me < 0 or S.is_empty() or S.phase != "roll":
		return false
	var p: Dictionary = S.players[int(S.turn)]
	return int(p.c) == me and not bool(p.cpu)

func auto_request(_salt := 0) -> Dictionary:
	return request("roll") if my_turn() else {}

## Your player ({} when watching).
func mine() -> Dictionary:
	var k := index_of(me)
	return S.players[k] if k >= 0 else {}

## The roll timer (s): S&L only has the roll step.
static func phase_sec(_phase := "roll") -> float:
	return 15.0
