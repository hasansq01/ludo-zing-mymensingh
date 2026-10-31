class_name Catalog
extends RefCounted
## What the Shop sells and what the player owns (index.html: SKINS, ROOM_LIST, buyRoom, useRoom, the dice buy / equip
## handlers, commitProfile; the pawn skins are new). Pure logic over the profile, no UI.
## Buying checks the id, ownership and coins first (never spends coins the player doesn't have, never sells twice),
## takes the price once, adds the item, equips it (the Shop does that for rooms and dice alike) and writes the save.
## If the write fails, every profile field goes back to what it was, so nothing is spent.
##
## The profile is Save.profile at runtime. Tests (and tools) can set `profile_source` to their own Dictionary and
## `writer` to their own save function, so the real save file is never touched.

## Names that are plain words, shown through L10n.t (the rest, Crema / Espresso / Pawn Pals ..., stay English). A new
## item table only needs its plain names added here (or `## l10n-keys: name` when all its names are translated).
const _NAMES := ["Classic", "Royal Gold", "Starter Set", "Friends Set", "Game Set", "Gold Trim", "Marble", "Kitty Ears",  # l10n
	"Teacup", "Glitter", "Royal Crown", "Chess Knight"]  # l10n
## l10n-keys: desc

## Dice skins (SKINS): body, edge shade, pips, the single pip of the 1. Classic is free and always owned.
const DICE := [
	{id = "classic", name = "Classic", price = 0, bg = Color("#fdfaf2"), edge = Color("#e1d7c3"), pip = Color("#22263f"), one = Color("#d8323a")},
	{id = "crema", name = "Crema", price = 1000, bg = Color("#f1d9b5"), edge = Color("#d2b183"), pip = Color("#5a3418"), one = Color("#5a3418")},
	{id = "espresso", name = "Espresso", price = 2500, bg = Color("#4a2c1a"), edge = Color("#2a170c"), pip = Color("#f3e3cc"), one = Color("#f2b632")},
	{id = "gold", name = "Royal Gold", price = 6000, bg = Color("#f6c945"), edge = Color("#c99a1c"), pip = Color("#3a2400"), one = Color("#b3261e")},
]
## Emote packs (server/EMOTES.md): six animated stickers each. Starter is free and always owned. The art and the
## emotes' display names come from assets/emotes/emotes.json (EmoteArt); these rows are the economy's source.
const EMOTE_PACKS := [
	{id = "starter", name = "Starter Set", price = 0, emotes = ["happy", "laugh", "cool", "angry", "love", "party"]},
	{id = "pawns", name = "Pawn Pals", price = 2500, emotes = ["champ", "sleepy", "sob", "gasp", "confused", "hi"]},
	{id = "friends", name = "Friends Set", price = 4000, emotes = ["cry", "wow", "facepalm", "cheer", "think", "tease"]},
	{id = "game", name = "Game Set", price = 3500, emotes = ["dice", "crown", "highfive", "flag", "sad", "peek"]},
]
## Pawn skins (owner 2026-10-31, "shapes + finishes"): a new shape (a crown, cat ears, a chess knight, a teacup) or a
## new finish (gold trim, marble, glitter) for every one of a player's pawns, in Ludo and Snakes & Ladders alike, and
## seen by everyone at an online table. The seat colour (Palette.PLAYER) stays each pawn's main colour, so players
## always tell pawns apart; PawnSkins builds the 3D look, PawnArt the flat one. Classic is free and always owned.
## `price` is in coins (and then also ceil(price / 100) gems, as every Shop item); a row with `gems` and no price is
## sold for gems only (the premium shapes). Dice run 1,000-6,000 coins: the coin skins sit beside them, the gem
## ones at one to two of the smallest gem packs (80 gems). `desc`: the PawnSheet's line under the turning pawns.
const PAWNS := [
	{id = "classic", name = "Classic", price = 0, desc = "The glossy pawn every game starts with."},
	{id = "trim", name = "Gold Trim", price = 2000, desc = "Gold bands at the foot, the waist and the collar."},
	{id = "marble", name = "Marble", price = 3500, desc = "Polished stone with soft white veins."},
	{id = "kitty", name = "Kitty Ears", price = 5000, desc = "Two pointy cat ears, pink inside."},
	{id = "teacup", name = "Teacup", price = 6000, desc = "A cup on its saucer, frothy on top."},
	{id = "glitter", name = "Glitter", price = 0, gems = 80, desc = "Sparkles all over that catch the light."},
	{id = "crown", name = "Royal Crown", price = 0, gems = 120, desc = "A small gold crown with a jewel in your colour."},
	{id = "knight", name = "Chess Knight", price = 0, gems = 150, desc = "A horse's head on a turned base, like the chess piece."},
]
const FREE_EMOTES := "starter"
const FREE_DICE := "classic"
const FREE_PAWN := "classic"
const FREE_ROOMS := ["night", "cafe"]
## Each room's card swatch (ROOM_LIST `g`: linear-gradient(160deg, from, to)).
const ROOM_GRADIENT := {
	night = [Color("#3d2f70"), Color("#c98a6a")],
	cafe = [Color("#ffe6cc"), Color("#ffc28f")],
	dream = [Color("#ffdced"), Color("#c9b3ff")],
	studio = [Color("#fff1a8"), Color("#ffb98a")],
	cloud = [Color("#c4e8ff"), Color("#9ee8dc")],
}
const SAVE_FAILED := "Couldn’t save on this device. No coins were spent."  # l10n

## Set to a Dictionary to work on it instead of Save.profile (tests). null = Save.profile.
static var profile_source: Variant = null
## Called with the profile after every change; returns true when it was saved. Invalid = Save.save() (+ Save.changed).
static var writer: Callable


# ---------- catalogue ----------

static func dice(id: String) -> Dictionary:
	for d: Dictionary in DICE:
		if d.id == id:
			return d
	return {}

static func room(id: String) -> Dictionary:
	for r: Dictionary in Rooms.LIST:
		if r.id == id:
			return r
	return {}

static func rooms() -> Array:
	return Rooms.LIST

static func pawn(id: String) -> Dictionary:
	for d: Dictionary in PAWNS:
		if d.id == id:
			return d
	return {}

## A pawn skin's gem price: its own `gems` (sold for gems only), else ceil(price / 100); 0 for Classic / unknown ids.
static func pawn_gems(id: String) -> int:
	var d := pawn(id)
	return int(d.gems) if d.has("gems") else gem_price(int(d.get("price", 0)))

## Sold for gems only (no coin price).
static func pawn_gems_only(id: String) -> bool:
	var d := pawn(id)
	return d.has("gems") and int(d.get("price", 0)) <= 0

static func emote_pack(id: String) -> Dictionary:
	for e: Dictionary in EMOTE_PACKS:
		if e.id == id:
			return e
	return {}


# ---------- the player's things ----------

static func profile() -> Dictionary:
	if profile_source is Dictionary:
		return profile_source
	var s := _save_node()
	return s.profile if s else {}

static func coins() -> int:
	return int(profile().get("coins", 0))

static func owns_room(id: String) -> bool:
	if room(id).is_empty():
		return false
	return FREE_ROOMS.has(id) or _list(profile(), "rooms").has(id)

static func owns_dice(id: String) -> bool:
	if dice(id).is_empty():
		return false
	return id == FREE_DICE or _list(profile(), "dice_owned").has(id)

static func owns_pawn(id: String) -> bool:
	if pawn(id).is_empty():
		return false
	return id == FREE_PAWN or _list(profile(), "pawns_owned").has(id)

## The pawn skin in use: the saved one when it is owned, else Classic.
static func pawn_in_use() -> String:
	var d := str(profile().get("pawn", ""))
	return d if owns_pawn(d) else FREE_PAWN

## Owned pawn skins in the order they were bought (Classic first).
static func owned_pawns() -> Array:
	var out := [pawn(FREE_PAWN)]
	for id in _list(profile(), "pawns_owned"):
		var d := pawn(str(id))
		if not d.is_empty() and not out.has(d):
			out.append(d)
	return out

static func owns_emotes(id: String) -> bool:
	if emote_pack(id).is_empty():
		return false
	return id == FREE_EMOTES or _list(profile(), "emote_sets").has(id)

static func emotes_in_use() -> String:
	var e := str(profile().get("emote_set", ""))
	return e if owns_emotes(e) else FREE_EMOTES

## Owned emote packs in catalogue order (Starter first).
static func owned_emote_packs() -> Array:
	return EMOTE_PACKS.filter(func(e: Dictionary) -> bool: return owns_emotes(e.id))

static func room_in_use() -> String:
	var r := str(profile().get("room", ""))
	return r if owns_room(r) else Rooms.DEFAULT

static func dice_in_use() -> String:
	var d := str(profile().get("dice", ""))
	return d if owns_dice(d) else FREE_DICE

## Owned rooms in catalogue order (free ones always).
static func owned_rooms() -> Array:
	return Rooms.LIST.filter(func(r: Dictionary) -> bool: return owns_room(r.id))

## Owned dice in the order they were bought (Classic first), like P.owned.
static func owned_dice() -> Array:
	var out := [dice(FREE_DICE)]
	for id in _list(profile(), "dice_owned"):
		var d := dice(str(id))
		if not d.is_empty() and not out.has(d):
			out.append(d)
	return out


# ---------- buying and equipping ----------

## Buys a room and puts it in use. "" when bought, else the reason (nothing changed then).
static func buy_room(id: String, equip := true) -> String:
	var r := room(id)
	if r.is_empty():
		return L10n.t("That room isn’t in the shop.")
	if owns_room(id):
		return L10n.t("You already own %s.") % L10n.t(r.name)
	var price := int(r.price)
	if coins() < price:
		return need_text(price - coins())
	var ok := _commit(func(p: Dictionary) -> void:
		p.coins = int(p.get("coins", 0)) - price
		var owned := _list(p, "rooms")
		owned.append(id)
		p.rooms = owned
		if equip:
			p.room = id)
	return "" if ok else L10n.t(SAVE_FAILED)

## Buys a dice skin and equips it. "" when bought, else the reason (nothing changed then).
static func buy_dice(id: String, equip := true) -> String:
	var d := dice(id)
	if d.is_empty():
		return L10n.t("Those dice aren’t in the shop.")
	if owns_dice(id):
		return L10n.t("You already own %s.") % L10n.t(d.name)
	var price := int(d.price)
	if coins() < price:
		return need_text(price - coins())
	var ok := _commit(func(p: Dictionary) -> void:
		p.coins = int(p.get("coins", 0)) - price
		var owned := _list(p, "dice_owned")
		if not owned.has(FREE_DICE):
			owned.insert(0, FREE_DICE)
		owned.append(id)
		p.dice_owned = owned
		if equip:
			p.dice = id)
	return "" if ok else L10n.t(SAVE_FAILED)

## Buys a pawn skin for coins and equips it. "" when bought, else the reason (nothing changed then). The gem-only
## skins (pawn_gems_only) are sold by the server's wallet alone (ShopSheet.buy_with_gems).
static func buy_pawn(id: String, equip := true) -> String:
	var d := pawn(id)
	if d.is_empty():
		return "Those pawns aren’t in the shop."
	if owns_pawn(id):
		return "You already own %s." % d.name
	if pawn_gems_only(id):
		return "%s is sold for gems only." % d.name
	var price := int(d.price)
	if coins() < price:
		return need_text(price - coins())
	var ok := _commit(func(p: Dictionary) -> void:
		p.coins = int(p.get("coins", 0)) - price
		var owned := _list(p, "pawns_owned")
		if not owned.has(FREE_PAWN):
			owned.insert(0, FREE_PAWN)
		owned.append(id)
		p.pawns_owned = owned
		if equip:
			p.pawn = id)
	return "" if ok else SAVE_FAILED

## Equips an owned pawn skin. False when it isn't owned (or the save failed); true when it is in use now.
static func equip_pawn(id: String) -> bool:
	if not owns_pawn(id):
		return false
	if str(profile().get("pawn", "")) == id:
		return true
	return _commit(func(p: Dictionary) -> void: p.pawn = id)

## Buys an emote pack and equips it. "" when bought, else the reason (nothing changed then).
static func buy_emotes(id: String, equip := true) -> String:
	var e := emote_pack(id)
	if e.is_empty():
		return L10n.t("That emote pack isn’t in the shop.")
	if owns_emotes(id):
		return L10n.t("You already own %s.") % L10n.t(e.name)
	var price := int(e.price)
	if coins() < price:
		return need_text(price - coins())
	var ok := _commit(func(p: Dictionary) -> void:
		p.coins = int(p.get("coins", 0)) - price
		var owned := _list(p, "emote_sets")
		if not owned.has(FREE_EMOTES):
			owned.insert(0, FREE_EMOTES)
		owned.append(id)
		p.emote_sets = owned
		if equip:
			p.emote_set = id)
	return "" if ok else L10n.t(SAVE_FAILED)

## Equips an owned emote pack. False when it isn't owned (or the save failed); true when it is in use now.
static func equip_emotes(id: String) -> bool:
	if not owns_emotes(id):
		return false
	if str(profile().get("emote_set", "")) == id:
		return true
	return _commit(func(p: Dictionary) -> void: p.emote_set = id)

## Puts an owned room in use. False when it isn't owned (or the save failed); true when it is in use now.
static func equip_room(id: String) -> bool:
	if not owns_room(id):
		return false
	if str(profile().get("room", "")) == id:
		return true
	return _commit(func(p: Dictionary) -> void: p.room = id)

## Equips owned dice. False when they aren't owned (or the save failed); true when they are in use now.
static func equip_dice(id: String) -> bool:
	if not owns_dice(id):
		return false
	if str(profile().get("dice", "")) == id:
		return true
	return _commit(func(p: Dictionary) -> void: p.dice = id)


# ---------- text ----------

## Economy v1: every paid item can also be bought with gems, ceil(coins / 100). Free items (0 coins) have no gem price.
static func gem_price(coins: int) -> int:
	return 0 if coins <= 0 else (coins + 99) / 100

static func need_text(short: int) -> String:
	return L10n.t("Not enough coins — you need %s more.") % group(short)

## 1234567 -> "1,234,567". Forwards to Fmt.coins_full.
static func group(n: int) -> String:
	return Fmt.coins_full(n)

## Short coin amounts like the web (fmtCoins): 950, 1K, 2.5K, 1.2M. Forwards to Fmt.coins.
static func short(n: int) -> String:
	return Fmt.coins(n)


# ---------- internals ----------

static func _list(p: Dictionary, key: String) -> Array:
	var v = p.get(key, [])
	return (v as Array).duplicate() if v is Array else []

static func _save_node() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Save")
	return null

## Applies `mutate` to the profile and saves; on a failed save every field is put back (commitProfile).
static func _commit(mutate: Callable) -> bool:
	var p := profile()
	var before := p.duplicate(true)
	mutate.call(p)
	if _write(p):
		return true
	p.clear()
	p.merge(before)
	return false

static func _write(p: Dictionary) -> bool:
	if writer.is_valid():
		return bool(writer.call(p))
	if profile_source is Dictionary:
		return true                        # a test profile without a writer: nothing to write
	var s := _save_node()
	if s == null:
		return false
	s.save()
	s.changed.emit()
	return true
