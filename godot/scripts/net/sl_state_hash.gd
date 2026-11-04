class_name SLStateHash
extends RefCounted
## The online Snakes & Ladders state hash (server/PROTOCOL.md "S&L state hash"): FNV-1a 32-bit over the UTF-8
## bytes of a canonical string, as 8 lowercase hex digits (the FNV of StateHash). Twin of
## server/src/rules/sl_hash.ts; both are tested on the same recorded traces.
##   turn | phase | sixes | winner | need_one ("0"/"1") | players | finished
## players: one "c.pos.cpu.ladders.snakes.rolls" per player in array (turn) order, comma-joined (cpu "0"/"1", rolls
## every recorded roll as one digit, concatenated); finished: the player indices in finish order, comma-joined ("" when
## none or missing). mode, paid, name and you are not hashed. Every number goes
## through int(), so a state that came through JSON (numbers as floats) hashes the same as the live one.

const SH := preload("res://scripts/net/state_hash.gd")

static func of(s: Dictionary) -> String:
	return SH.fnv1a32(input(s))

## The canonical string that of() hashes.
static func input(s: Dictionary) -> String:
	var players := PackedStringArray()
	for p in s.players:
		var rolls := ""
		for v in p.get("rolls", []):
			rolls += str(int(v))
		players.append("%d.%d.%s.%d.%d.%s" % [int(p.c), int(p.pos), "1" if bool(p.cpu) else "0", int(p.ladders),
			int(p.snakes), rolls])
	var fin := PackedStringArray()
	var f: Variant = s.get("finished", [])
	if f is Array:
		for x in f:
			fin.append(str(int(x)))
	return "|".join(PackedStringArray([str(int(s.turn)), str(s.phase), str(int(s.sixes)), str(int(s.winner)),
		"1" if bool(s.get("need_one", false)) else "0", ",".join(players), ",".join(fin)]))
