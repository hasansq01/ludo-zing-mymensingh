class_name NetLudo
extends NetReplica
## The online Ludo replica (NetReplica holds the queue, n, the hash check), without any animation (LudoMatch
## animates; tests drive this directly): the local LudoRules state S built from the server's `start` / `sync` (your
## seat, "You", the board turned to you) and one action at a time through LudoRules (apply_roll / move /
## answer_pair / the `mode` act). S.me is your colour (-1 watching); NetLudo.you(s, c) is the "is this you" test for
## online and offline states alike (offline: LudoRules.is_you).

const REQUESTS := ["roll", "move", "pair"]


func _init() -> void:
	game = "ludo"
	hash_fn = Callable(StateHash, "of")

## Colour c is you: online, your seat (S.me); offline, the only human at the table.
static func you(s: Dictionary, c: int) -> bool:
	if s.has("me"):
		return c >= 0 and c == int(s.me)
	return LudoRules.is_you(s, c)

## The local state from a server snapshot: ints restored (JSON gives floats), defaults filled, S.me / S.view = your
## colour, your display name "You" (presentation only, never hashed).
static func localize(state: Dictionary, seats_: Array, me_id: String) -> Dictionary:
	var s: Dictionary = MatchStore.ints(state)
	for k in [["pairs", []], ["finished", []], ["pending", {}], ["pick", ""], ["free", [false, false, false, false]],
			["teams", false], ["pair_ask", false], ["winner", -1], ["dice", 0], ["sixes", 0]]:
		if not s.has(k[0]) or s[k[0]] == null:
			var d: Variant = k[1]
			s[k[0]] = d.duplicate() if d is Array or d is Dictionary else d
	if not s.get("names") is Array or (s.names as Array).size() != 4:
		s.names = ["", "", "", ""]
	var c := NetReplica.color_of(seats_, me_id)
	s.me = c
	if c >= 0:
		s.view = c
		s.names[c] = "You"
	else:
		var first := 0
		for k in 4:
			if s.players[k] != "off":
				first = k
				break
		s.view = first
	for st in seats_:                         # the seats' names are the ones to show (names are never hashed)
		var sc := int(st.get("color", -1))
		if sc >= 0 and sc < 4 and sc != c and str(st.get("name", "")) != "":
			s.names[sc] = str(st.name)
	return s

func _localize(state: Dictionary, seats_: Array, me_id: String) -> Dictionary:
	return localize(state, seats_, me_id)

## Apply one action to S with the same rules functions offline play uses; returns the rules' events.
## (LudoMatch calls this at the moment the animation needs the state: a roll after the dice have tumbled.)
func apply_rules(a: Dictionary) -> Array:
	n += 1
	var c := int(a.get("c", S.get("turn", 0)))
	match str(a.get("k", "")):
		"roll":
			return LudoRules.apply_roll(S, int(a.get("v", 0)))
		"move":
			return LudoRules.move(S, int(a.get("i", -1)))
		"pair":
			return LudoRules.answer_pair(S, bool(a.get("yes", false)))
		"end":                                # the server ends the match early (play on: only bots / ghosts left)
			return LudoRules.end_game(S)
		"mode":
			if c >= 0 and c < 4 and S.players[c] != "off":
				S.players[c] = "cpu" if str(a.get("mode", "")) == "cpu" else "human"
			for st in seats:
				if int(st.get("color", -1)) == c:
					st.bot = S.players[c] == "cpu"
	return []

## Is it your move now (your colour's turn, played by you, not a bot)?
func my_turn() -> bool:
	return me >= 0 and not S.is_empty() and int(S.turn) == me and S.players[me] == "human" and S.phase != "over"

func turn_color() -> int:
	return int(S.get("turn", -1)) if not S.is_empty() else -1

## The request an automatic player sends now (auto-move, else a unit picked by `salt`; pair prompts yes).
func auto_request(salt := 0) -> Dictionary:
	if not my_turn():
		return {}
	match str(S.phase):
		"roll":
			return request("roll")
		"choose":
			var i := LudoRules.auto_move_token(S)
			if i < 0:
				var us := LudoRules.units(S)
				if us.is_empty():
					return {}
				i = int(us[(n * 7 + 3 + salt) % us.size()].token)
			return request("move", {i = i})
		"pair_ask":
			return request("pair", {yes = true})
	return {}

## The step the server's timer counts for the current phase (s): roll 15, choose 20, pair_ask 10.
static func phase_sec(phase: String) -> float:
	match phase:
		"choose":
			return 20.0
		"pair_ask":
			return 10.0
	return 15.0
