class_name NetLudo
extends RefCounted
## The online Ludo replica's bookkeeping, without any animation (LudoMatch animates; tests drive this directly):
## the local rules state S built from the server's `start` / `sync` (your seat, "You", the board turned to you),
## the count of actions applied (n), the queue of server messages still to play, and the hash check after each
## action.
##
##   var ns := NetLudo.new()
##   ns.begin(start_msg, my_member_id)          # S, seats, me, n
##   ns.push(act_msg)                            # act / sync / over, in arrival order
##   var m := ns.next()                          # the next message to play ({} when none):
##                                               #   {t = "act"...} play it: ev = ns.apply_rules(m.a); ns.verify(m)
##                                               #   {t = "sync"...} replace the state: ns.begin(m, id)
##                                               #   {t = "over"...} the end
##                                               #   {t = "need_sync"} send sync_req (a gap in n)
## A duplicate act (n already applied) is dropped; a gap or a hash mismatch sets awaiting_sync, and every act until
## the next sync is dropped (the snapshot contains them). S.me is your colour (-1 watching); NetLudo.you(s, c)
## is the "is this you" test for online and offline states alike (offline: LudoRules.is_you).

const REQUESTS := ["roll", "move", "pair"]

var S := {}
var me := -1
var seats: Array = []                     ## [{color, id, name, avatar, frame, bot, online}]
var n := 0                                ## actions applied
var awaiting_sync := false
var q: Array = []
var hash_fn := Callable(StateHash, "of")
var mismatches := 0                       ## hash mismatches seen (tests, debugging)
var gaps := 0


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
	var c := color_of(seats_, me_id)
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

## The colour of member `id` in `seats_`, or -1.
static func color_of(seats_: Array, id: String) -> int:
	if id == "":
		return -1
	for st in seats_:
		if st is Dictionary and NetClient.id_str(st.get("id", "")) == id:
			return int(st.get("color", -1))
	return -1

## A new match or a full snapshot (start / sync): replaces everything; the queue keeps only what comes after it.
func begin(msg: Dictionary, me_id: String) -> void:
	seats = MatchStore.ints(msg.get("seats", [])) if msg.get("seats") is Array else seats
	S = localize(msg.get("state", {}), seats, me_id)
	me = int(S.me)
	n = int(msg.get("n", 0))
	awaiting_sync = false

## The seat of colour c ({} when none).
func seat(c: int) -> Dictionary:
	for st in seats:
		if int(st.get("color", -1)) == c:
			return st
	return {}

## presence {id, online}: the seat's online flag. Returns the colour (-1 when not seated).
func set_online(id: String, on: bool) -> int:
	for st in seats:
		if NetClient.id_str(st.get("id", "")) == id:
			st.online = on
			return int(st.get("color", -1))
	return -1

func push(msg: Dictionary) -> void:
	q.append(msg)

func pending() -> int:
	return q.size()

## The next message to play, in order ({} when the queue is empty). See the class notes.
func next() -> Dictionary:
	while not q.is_empty():
		var m: Dictionary = q.pop_front()
		match str(m.get("t", "")):
			"sync", "over":
				return m
			"act":
				if awaiting_sync:
					continue
				var k := int(m.get("n", -1))
				if k < n:
					continue                      # already applied (a resend after a reconnect)
				if k > n:
					awaiting_sync = true          # we missed one: a snapshot is needed
					gaps += 1
					return {t = "need_sync"}
				return m
	return {}

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
		"mode":
			if c >= 0 and c < 4 and S.players[c] != "off":
				S.players[c] = "cpu" if str(a.get("mode", "")) == "cpu" else "human"
			for st in seats:
				if int(st.get("color", -1)) == c:
					st.bot = S.players[c] == "cpu"
	return []

## After apply_rules: does our state hash match the server's (msg.h)? A mismatch sets awaiting_sync (send
## sync_req). An act without h is trusted.
func verify(msg: Dictionary) -> bool:
	var h := str(msg.get("h", ""))
	if h == "" or not hash_fn.is_valid():
		return true
	if str(hash_fn.call(S)) == h:
		return true
	mismatches += 1
	awaiting_sync = true
	return false

## Apply one act message straight through (no animation): rules + hash. Used by tests and headless clients.
func play(msg: Dictionary) -> bool:
	apply_rules(msg.get("a", {}))
	return verify(msg)

## A request to the server for the current step ({t, n, ...fields}).
func request(t: String, fields := {}) -> Dictionary:
	var m := {t = t, n = n}
	m.merge(fields)
	return m

## Is it your move now (your colour's turn, played by you, not a bot)?
func my_turn() -> bool:
	return me >= 0 and not S.is_empty() and int(S.turn) == me and S.players[me] == "human" and S.phase != "over"

## The step the server's timer counts for the current phase (s): roll 15, choose 20, pair_ask 10.
static func phase_sec(phase: String) -> float:
	match phase:
		"choose":
			return 20.0
		"pair_ask":
			return 10.0
	return 15.0
