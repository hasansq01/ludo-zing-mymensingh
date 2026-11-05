class_name Emotes
extends RefCounted
## Emote packs for the picker, the HUD and the relay (server/EMOTES.md). Pack order and names come from
## assets/emotes/emotes.json (EmoteArt.manifest()) when it is there, else from Catalog.EMOTE_PACKS. What the player
## owns is read through Catalog (Save.profile, or Catalog.profile_source in tests).

## Packs in order: [{id, name, price, emotes: Array[String]}].
static func packs() -> Array:
	var out := []
	var sets: Array = EmoteArt.manifest().get("sets", [])
	for s in sets:
		if s is Dictionary and str(s.get("id", "")) != "":
			var base := Catalog.emote_pack(str(s.id))
			out.append({
				id = str(s.id),
				name = str(s.get("name", base.get("name", s.id))),
				price = int(base.get("price", s.get("price", 0))),
				emotes = _strs(s.get("emotes", base.get("emotes", []))),
				premium = bool(s.get("premium", false)),
			})
	if out.is_empty():
		for e: Dictionary in Catalog.EMOTE_PACKS:
			out.append({id = e.id, name = e.name, price = int(e.price), emotes = _strs(e.emotes), premium = bool(e.get("premium", false))})
	return out

## The text packs in order: [{id, name, price, emotes: Array[String]}].
static func text_packs() -> Array:
	var out := []
	for e: Dictionary in Catalog.TEXT_PACKS:
		out.append({id = e.id, name = e.name, price = int(e.price), emotes = _strs(e.emotes)})
	return out

static func text_pack(id: String) -> Dictionary:
	for p: Dictionary in text_packs():
		if p.id == id:
			return p
	return {}

## The Text tab's phrases: the equipped text pack, plus the team phrases in Pair Mode.
static func equipped_text_ids(teams := false) -> Array[String]:
	var out: Array[String] = []
	out.assign(text_pack(Catalog.text_in_use()).get("emotes", []))
	if teams:
		out.append_array(_strs(Catalog.TEAM_PHRASES))
	return out

## One pack ({} when unknown).
static func pack(id: String) -> Dictionary:
	for p: Dictionary in packs():
		if p.id == id:
			return p
	return {}

## The pack an emote belongs to ("" when unknown).
static func pack_of(emote_id: String) -> String:
	for p: Dictionary in packs() + text_packs():
		if p.emotes.has(emote_id):
			return p.id
	return "team" if Catalog.TEAM_PHRASES.has(emote_id) else ""

## Owned pack ids in pack order (Starter always).
static func owned_packs() -> Array:
	var out := []
	for p: Dictionary in packs():
		if Catalog.owns_emotes(p.id):
			out.append(p.id)
	return out

## The equipped pack id (Starter when the saved one isn't owned).
static func equipped_pack() -> String:
	return Catalog.emotes_in_use()

## The six emote ids of the equipped pack, in order.
static func equipped_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(pack(equipped_pack()).get("emotes", []))
	return out

## True when the player's account owns the pack of that emote (Starter always).
static func owns_emote(emote_id: String) -> bool:
	var pid := pack_of(emote_id)
	return pid == "team" or Catalog.owns_emotes(pid) or Catalog.owns_text(pid)

static func _strs(a: Variant) -> Array[String]:
	var out: Array[String] = []
	if a is Array:
		for x in a:
			out.append(str(x))
	return out
