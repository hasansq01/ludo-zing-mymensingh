class_name NetReplica
extends RefCounted
## The game-agnostic part of an online replica (server/PROTOCOL.md): the local rules state S built from the
## server's `start` / `sync`, your seat and colour (me), the count of actions applied (n), the queue of server
## messages still to play, and the hash check after each action. NetLudo (Ludo) and NetSL (Snakes & Ladders) add
## the game's own pieces: localize() (S from a snapshot), apply_rules() (one action through the rules functions the
## game plays offline), my_turn() and the hash function.
##
##   var ns := NetReplica.for_game(start_msg.game)  # NetLudo / NetSL
##   ns.begin(start_msg, my_member_id)               # S, seats, me, n
##   ns.push(act_msg)                                 # act / sync / over, in arrival order
##   var m := ns.next()                               # the next message to play ({} when none):
##                                                    #   {t = "act"...} play it: ev = ns.apply_rules(m.a); ns.verify(m)
##                                                    #   {t = "sync"...} replace the state: ns.begin(m, id)
##                                                    #   {t = "over"...} the end
##                                                    #   {t = "need_sync"} send sync_req (a gap in n)
## A duplicate act (n already applied) is dropped; a gap or a hash mismatch sets awaiting_sync, and every act until
## the next sync is dropped (the snapshot contains them).

var game := "ludo"
var S := {}
var me := -1                              ## your colour (-1: watching)
var seats: Array = []                     ## [{color, id, name, avatar, frame, level, bot, online}]
var n := 0                                ## actions applied
var awaiting_sync := false
var q: Array = []
var hash_fn := Callable()
var mismatches := 0                       ## hash mismatches seen (tests, debugging)
var gaps := 0

## What an online match pays (ONLINE_V2.md "Economy decisions", the server's econ ONLINE_REWARDS): by game and
## outcome, [coins, xp]. "left" (you left, or a bot was playing your seat at the end) pays nothing.
const ONLINE_REWARDS := {
	ludo = {win = [300, 100], finish = [50, 40]},
	sl = {win = [200, 60], finish = [25, 25]},
}
## Quick match at the Practice table pays coins win 50 / finish 10 (ECONOMY_V1.md 3; XP as above).
const PRACTICE_COINS := {win = 50, finish = 10}


## The replica for a game ("ludo" | "sl"; anything else is Ludo, the protocol's default).
static func for_game(g: Variant) -> NetReplica:
	if str(g) == "sl":
		return NetSL.new()
	return NetLudo.new()

## {coins, xp} an online match of game `g` grants for outcome "win" | "finish" | "left" ("" = no seat: nothing).
static func online_reward(g: String, outcome: String) -> Dictionary:
	var t: Dictionary = ONLINE_REWARDS.get(g, ONLINE_REWARDS.ludo)
	var v: Array = t.get(outcome, [0, 0])
	return {coins = int(v[0]), xp = int(v[1])}

## The coin table of a quick match's `over` for your colour: {} for a friend room, else {tier, entry, payout (coins the
## server paid you; 0 when you lost or watched), bonus (the 1st place's house bonus, on top of payout), refund (the entry
## given back instead of a prize), ended ("away" when the server ended a match nobody was connected to; else ""), match_id}. A Practice table has entry 0.
static func table_result(over: Dictionary, me: int) -> Dictionary:
	var t: Variant = over.get("table")
	if not t is Dictionary:
		return {}
	var pays: Variant = (t as Dictionary).get("payouts", {})
	var pay := 0
	if me >= 0 and pays is Dictionary:
		pay = int(pays.get(str(me), pays.get(me, 0)))
	return {tier = str(t.get("tier", "")), entry = int(t.get("entry", 0)), payout = maxi(0, pay),
		bonus = _mine(t.get("bonus"), me), refund = _mine(t.get("refunds"), me), ended = str(over.get("ended", "")),
		match_id = str(over.get("match_id", ""))}

## Colour `me`'s coins in a {"<colour>": coins} dictionary (0 when missing, malformed or watching).
static func _mine(d: Variant, me: int) -> int:
	if me < 0 or not d is Dictionary:
		return 0
	return maxi(0, int(d.get(str(me), d.get(me, 0))))

## Coins an online match grants outside a paid table: friends' rooms ONLINE_REWARDS, Practice PRACTICE_COINS. A coin
## table pays its payout instead (table_result), never this.
static func online_coins(g: String, outcome: String, table: Dictionary) -> int:
	if not table.is_empty():
		if int(table.get("entry", 0)) > 0:
			return 0
		return int(PRACTICE_COINS.get(outcome, 0))
	return int(online_reward(g, outcome).coins)

## True when the server grants online rewards into this player's account (an Account runs): the result shows
## them and the profile is refreshed from the server; false: the XP is kept locally (no account), no coins.
static func server_rewards() -> bool:
	return Account.wallet_active()

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
	S = _localize(msg.get("state", {}), seats, me_id)
	me = int(S.get("me", -1))
	n = int(msg.get("n", 0))
	awaiting_sync = false

## Game hook: the local state from a snapshot (ints restored, defaults filled, S.me = your colour, presentation).
func _localize(state: Dictionary, _seats: Array, _me_id: String) -> Dictionary:
	var s: Dictionary = MatchStore.ints(state)
	s.me = -1
	return s

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

## A message from the server. A snapshot replaces the state, so the acts still waiting before it are dropped (a
## re-roll's sync restores the state before the bad roll: its act must not play after it).
func push(msg: Dictionary) -> void:
	if str(msg.get("t", "")) == "sync":
		q = q.filter(func(m): return str(m.get("t", "")) != "act")
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

## Game hook: apply one action to S with the rules functions offline play uses; returns the rules' events. Counts n.
func apply_rules(_a: Dictionary) -> Array:
	n += 1
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

## Our state's hash now ("" without a hash function).
func state_hash() -> String:
	return str(hash_fn.call(S)) if hash_fn.is_valid() and not S.is_empty() else ""

## Apply one act message straight through (no animation): rules + hash. Used by tests and headless clients.
func play(msg: Dictionary) -> bool:
	apply_rules(msg.get("a", {}))
	return verify(msg)

## A request to the server for the current step ({t, n, ...fields}).
func request(t: String, fields := {}) -> Dictionary:
	var m := {t = t, n = n}
	m.merge(fields)
	return m

## Game hook: is it your move now (your colour's turn, played by you, not a bot)?
func my_turn() -> bool:
	return false

## Game hook: the colour whose turn it is (-1: none).
func turn_color() -> int:
	return -1

## Game hook: the request this client would send now for an automatic player (headless clients, tests):
## {} when it isn't your turn.
func auto_request(_salt := 0) -> Dictionary:
	return {}

## The game's own name for the colour's player ("" when unknown): the seat's name.
func seat_name(c: int) -> String:
	return str(seat(c).get("name", ""))
