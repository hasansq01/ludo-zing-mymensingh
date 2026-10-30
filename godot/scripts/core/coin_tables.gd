class_name CoinTables
extends RefCounted
## The coin tables of quick match (server/ECONOMY_V1.md section 3), pure and static: the ids the queue takes
## (`table=`), the entries and levels, the prize maths (fee 5 % of the pot; 2 players: the winner takes the pool;
## 4 players: 1st 60 %, 2nd 30 %, 3rd 10 % of the pool, rounded down, the remainder stays with the house; at a paid
## table the 1st place also gets a house bonus of 20 % of the pool on top) and the picker's rows. The server decides
## everything real (entries, payouts, who may sit); this only shows it and picks the table.
##
##   CoinTables.prize(100, 2)                      # 190 (pool); CoinTables.bonus(100, 2) # 38; first_total # 228
##   CoinTables.rows(2, level, coins)              # [{id, entry, level, locked, affordable, prize, bonus, total, ok}]
##   CoinTables.rows(2, level, coins, tables_msg)  # the server's unlocked / affordable win when it answered

const PRACTICE := "practice"
const FEE_PCT := 5
const SHARES_4P := [60, 30, 10]          ## percent of the pool for places 1-3 at a 4-player table (4th gets 0)
const BONUS_PCT := 20                    ## house bonus for 1st at a paid table: percent of the pool, new coins on top
const BROKE_BELOW := 100                 ## fewer coins than the cheapest paid table: the broke popup
const TABLES := [
	{id = "practice", entry = 0, level = 1},
	{id = "t100", entry = 100, level = 1},
	{id = "t500", entry = 500, level = 1},
	{id = "t2k", entry = 2000, level = 6},
	{id = "t10k", entry = 10000, level = 10},
	{id = "t50k", entry = 50000, level = 15},
]


static func valid(id: String) -> bool:
	return not info(id).is_empty()

## The table {id, entry, level} ({} for an unknown id).
static func info(id: String) -> Dictionary:
	for t: Dictionary in TABLES:
		if t.id == id:
			return t
	return {}

## The pot left after the fee, for `size` players who each put in `entry`.
static func pool(entry: int, size: int) -> int:
	return entry * size * (100 - FEE_PCT) / 100

## What place `place` (1-based) is paid at a table of `size` players: 2 players pay 1st only (the pool); 4 players pay
## three places (SHARES_4P of the pool, each rounded down; the remainder stays with the house). The server's tablePayouts.
static func prize(entry: int, size: int, place := 1) -> int:
	var p := pool(entry, size)
	if size <= 2:
		return p if place == 1 else 0
	if place < 1 or place > SHARES_4P.size():
		return 0
	return p * int(SHARES_4P[place - 1]) / 100

## The house bonus for 1st place (new coins on top of the prize); 0 at Practice.
static func bonus(entry: int, size: int) -> int:
	return pool(entry, size) * BONUS_PCT / 100 if entry > 0 else 0

## What 1st place receives in all: the prize and the bonus.
static func first_total(entry: int, size: int) -> int:
	return prize(entry, size, 1) + bonus(entry, size)

static func is_broke(coins: int) -> bool:
	return coins < BROKE_BELOW

## The picker's rows for a table size, from the local numbers (level, coins); `server` is a GET /v1/tables answer
## ({tables: [{id, unlocked, affordable}]}): its flags replace ours for the tables it lists.
## row: {id, entry, level, locked, affordable, prize (1st place's pot payout), bonus, total (1st's prize + bonus), ok (can be picked: not locked, affordable)}.
static func rows(size: int, level: int, coins: int, server := {}) -> Array:
	var flags := {}
	if server.get("tables") is Array:
		for t in server.tables:
			if t is Dictionary:
				flags[str(t.get("id", ""))] = t
	var out := []
	for t: Dictionary in TABLES:
		var locked := level < int(t.level)
		var affordable := coins >= int(t.entry)
		if flags.has(t.id):
			locked = not bool(flags[t.id].get("unlocked", not locked))
			affordable = bool(flags[t.id].get("affordable", affordable))
		out.append({id = t.id, entry = int(t.entry), level = int(t.level), locked = locked, affordable = affordable,
			prize = prize(int(t.entry), size) if int(t.entry) > 0 else 0, bonus = bonus(int(t.entry), size),
				total = first_total(int(t.entry), size) if int(t.entry) > 0 else 0, ok = not locked and affordable})
	return out

## The id to preselect: the remembered table when it can be played now, else Practice.
static func pick(want: String, list: Array) -> String:
	for r: Dictionary in list:
		if r.id == want and r.ok:
			return want
	return PRACTICE

## "Entry 100 lost" for a coin-table match you didn't win a prize in; "" for Practice.
static func lost_text(entry: int) -> String:
	return "Entry %s lost" % Fmt.coins_full(entry) if entry > 0 else ""

## "Entry 100 refunded" for a match whose entry the server gave back; "" for Practice.
static func refund_text(entry: int) -> String:
	return "Entry %s refunded" % Fmt.coins_full(entry) if entry > 0 else ""

## "Includes +38 house bonus".
static func bonus_text(bonus_: int) -> String:
	return "Includes +%s house bonus" % Fmt.coins_full(bonus_) if bonus_ > 0 else ""

## The note for a match the server ended because nobody was connected.
const AWAY_TEXT := "The match ended while everyone was away: places by progress."

## Short names for a table in a sentence ("the 500 table").
static func label(id: String) -> String:
	var t := info(id)
	return "Practice" if int(t.get("entry", 0)) <= 0 else Fmt.coins_full(int(t.entry))
