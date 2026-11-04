class_name StateHash
extends RefCounted
## The online state hash (server/PROTOCOL.md "State hash"): FNV-1a 32-bit over the UTF-8 bytes of a canonical
## string, as 8 lowercase hex digits. Twin of server/src/rules/hash.ts; both are tested on the same recorded traces.
##   tok(16 ints, colour-major) | pairs ("c.a.b") | turn | dice | sixes | phase | winner | free ("0"/"1" x4) |
##   finished | players | pending ("" or "c.i.to.extra(0/1).partner", partner -1 if absent)
## names, view, teams, pair_ask and pick are not hashed. Every number goes through int(), so a state that came
## through JSON (numbers as floats) hashes the same as the live one.

const FNV_OFFSET := 0x811c9dc5
const FNV_PRIME := 0x01000193
const MASK := 0xFFFFFFFF

static func of(s: Dictionary) -> String:
	return fnv1a32(input(s))

## The canonical string that of() hashes.
static func input(s: Dictionary) -> String:
	var tok := PackedStringArray()
	for c in 4:
		for i in 4:
			tok.append(str(int(s.tok[c][i])))
	var pairs := PackedStringArray()
	for q in s.get("pairs", []):
		pairs.append("%d.%d.%d" % [int(q.c), int(q.a), int(q.b)])
	var free_s := ""
	var fr: Array = s.get("free", [false, false, false, false])
	for c in 4:
		free_s += "1" if c < fr.size() and bool(fr[c]) else "0"
	var fin := PackedStringArray()
	var finished = s.get("finished", [])
	if finished is Array:
		for x in finished:
			fin.append(str(int(x)))
	var players := PackedStringArray()
	for seat in s.players:
		players.append(str(seat))
	var pending := ""
	var pend = s.get("pending", {})
	if pend is Dictionary and not pend.is_empty():
		pending = "%d.%d.%d.%s.%d" % [int(pend.c), int(pend.i), int(pend.to), "1" if bool(pend.extra) else "0",
			int(pend.get("partner", -1))]
	return "|".join(PackedStringArray([",".join(tok), ",".join(pairs), str(int(s.turn)), str(int(s.dice)),
		str(int(s.sixes)), str(s.phase), str(int(s.winner)), free_s, ",".join(fin), ",".join(players), pending]))

## FNV-1a 32 of the text's UTF-8 bytes. GDScript ints are 64-bit, so the product is masked back to 32 bits.
static func fnv1a32(text: String) -> String:
	var h := FNV_OFFSET
	for b in text.to_utf8_buffer():
		h = h ^ b
		h = (h * FNV_PRIME) & MASK
	return "%08x" % h
