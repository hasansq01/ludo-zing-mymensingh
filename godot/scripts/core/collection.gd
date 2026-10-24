class_name Collection
extends RefCounted
## The player's Collection (index.html: AV_ART, personSVG, CHARS, AVATARS, FRAMES, PLATES, ACH, isUnlocked,
## unlockText, levelInfo, avatarHTML, badgeSVG, buyAvatar, the Collection equip handler and the Achievements claim).
##   Characters: 20 drawn portraits (10 male, 10 female). Arif and Nadia are free, the rest cost 10,000-12,000 coins
##     and, once bought, are listed in profile.av_owned.
##   Avatars: the four pawns and Latte are free; Lucky Dice / Robot unlock with an achievement, Crown at level 5.
##   Frames (the ring around the avatar), Nameplates (behind the name) and Badges (an earned achievement's medal
##     beside the name) unlock by level or achievement.
##   Achievements: a stat reaching a goal; each pays its coins once (profile.claimed).
## Pure logic over a profile Dictionary plus the drawing helpers the rest of the app uses for the player's look:
##   avatar_texture(id)   the square avatar tile (gradient + art, rounded corners) as a texture
##   make_avatar(size)    the equipped avatar inside its equipped frame, as a Control (home chip, profile, game card)
##   make_plate(...)      the name on its nameplate with the badge, make_badge(id, size) a medal.
## The profile is Save.profile at runtime. Tests set `profile_source` to their own Dictionary and `writer` to their own
## save function, so the real save file is never touched. A failed save puts every profile field back (commitProfile).

const DEFAULT_AVATAR := "pawn-red"
const DEFAULT_FRAME := "classic"
const DEFAULT_PLATE := "plain"
const SAVE_FAILED := "Couldn’t save on this device. No coins were spent."
const SAVE_FAILED_EQUIP := "Couldn’t save on this device."

## Character portraits: skin, hair (colour), hs (hairstyle), top (outfit colour), od (outfit detail), acc (accessory),
## ac (accessory colour), g ("m" | "f"); a1 / a2 the tile gradient. The first of each gender is free.
const CHARS := [
	{id = "ch-arif", name = "Arif", g = "m", price = 0, a1 = "#bfe6ff", a2 = "#6fb3e8", skin = "#eebf9c", hair = "#3b2a24", hs = "crop", top = "#3b7be0", od = "v"},
	{id = "ch-rafi", name = "Rafi", g = "m", price = 10000, a1 = "#ffe2b3", a2 = "#f3a64b", skin = "#d9a07a", hair = "#1f1a1c", hs = "quiff", top = "#2fa86b", od = "collar"},
	{id = "ch-tanvir", name = "Tanvir", g = "m", price = 10500, a1 = "#d9f3e4", a2 = "#6cc79a", skin = "#8d5a3b", hair = "#1b1416", hs = "afro", top = "#f4a340", od = "hoodie"},
	{id = "ch-nayeem", name = "Nayeem", g = "m", price = 11000, a1 = "#e9e0ff", a2 = "#a58bf0", skin = "#f3c6a5", hair = "#5b3a22", hs = "side", top = "#5b4bb7", od = "tie", acc = "glasses", ac = "#3a2230"},
	{id = "ch-sabbir", name = "Sabbir", g = "m", price = 11750, a1 = "#ffd6cf", a2 = "#ef7e6f", skin = "#b97a52", hair = "#2a1d18", hs = "buzz", top = "#4a4f63", od = "stripe"},
	{id = "ch-imran", name = "Imran", g = "m", price = 10250, a1 = "#fff1c2", a2 = "#e9c14c", skin = "#eebf9c", hair = "#6b4426", hs = "manbun", top = "#c0483f", od = "scarf", ac = "#f3d36b"},
	{id = "ch-rakib", name = "Rakib", g = "m", price = 12000, a1 = "#cdeff5", a2 = "#4fb6c9", skin = "#d9a07a", hair = "#e2a23a", hs = "spiky", top = "#2b2f45", od = "v"},
	{id = "ch-fahim", name = "Fahim", g = "m", price = 11250, a1 = "#ffe0ec", a2 = "#f28bb0", skin = "#f6d2b8", hair = "#3b2a24", hs = "cap", top = "#ffffff", od = "stripe", ac = "#e5484d"},
	{id = "ch-shuvo", name = "Shuvo", g = "m", price = 10750, a1 = "#e3f4c8", a2 = "#9ccc5a", skin = "#b97a52", hair = "#1f1a1c", hs = "curls", top = "#8a5a3c", od = "collar"},
	{id = "ch-jamil", name = "Jamil", g = "m", price = 11500, a1 = "#dfe7ff", a2 = "#7d97e8", skin = "#f3c6a5", hair = "#4a2e20", hs = "beanie", top = "#2fb39c", od = "hoodie", acc = "glasses", ac = "#e0a100"},
	{id = "ch-nadia", name = "Nadia", g = "f", price = 0, a1 = "#ffd9e6", a2 = "#f590b4", skin = "#eebf9c", hair = "#2a1d18", hs = "long", top = "#e5484d", od = "necklace", ac = "#f4c430"},
	{id = "ch-riya", name = "Riya", g = "f", price = 10000, a1 = "#d8f1ff", a2 = "#68b8ea", skin = "#f6d2b8", hair = "#1f1a1c", hs = "bob", top = "#f4c430", od = "collar"},
	{id = "ch-tania", name = "Tania", g = "f", price = 10500, a1 = "#fff0c9", a2 = "#f0b84a", skin = "#d9a07a", hair = "#7a4a28", hs = "pony", top = "#7c4dff", od = "v", ac = "#ff7a9c"},
	{id = "ch-mim", name = "Mim", g = "f", price = 11000, a1 = "#e7dcff", a2 = "#a98cf0", skin = "#8d5a3b", hair = "#1b1416", hs = "curlylong", top = "#2fa86b", od = "necklace", acc = "earrings", ac = "#f4c430"},
	{id = "ch-sumaiya", name = "Sumaiya", g = "f", price = 11750, a1 = "#d6f4ea", a2 = "#5fc4a3", skin = "#f3c6a5", hair = "#6b3a7a", hs = "hijab", top = "#6b3a7a", od = "v"},
	{id = "ch-priya", name = "Priya", g = "f", price = 10250, a1 = "#ffe1d1", a2 = "#f39a6b", skin = "#b97a52", hair = "#2a1d18", hs = "buns", top = "#3b7be0", od = "stripe"},
	{id = "ch-lamia", name = "Lamia", g = "f", price = 12000, a1 = "#fce4ff", a2 = "#d58be8", skin = "#eebf9c", hair = "#c4572a", hs = "pixie", top = "#2b2f45", od = "necklace", acc = "earrings", ac = "#e9e3ff"},
	{id = "ch-fariha", name = "Fariha", g = "f", price = 11250, a1 = "#fff6c8", a2 = "#e6cf52", skin = "#d9a07a", hair = "#1f1a1c", hs = "braids", top = "#e5484d", od = "dupatta", ac = "#f4c430"},
	{id = "ch-nusrat", name = "Nusrat", g = "f", price = 10750, a1 = "#d9ecff", a2 = "#8fb3ef", skin = "#f6d2b8", hair = "#5b3a22", hs = "wavy", top = "#ff9ec7", od = "collar", ac = "#2fb39c"},
	{id = "ch-ayesha", name = "Ayesha", g = "f", price = 11500, a1 = "#ffdcd6", a2 = "#ee8a7c", skin = "#8d5a3b", hair = "#1b1416", hs = "bangs", top = "#2fb39c", od = "scarf", ac = "#ffd45e"},
]
## The original avatars (the Avatars tab). Red Pawn is the fallback. Characters are avatars too (avatar(id) finds both).
const AVATARS := [
	{id = "pawn-red", name = "Red Pawn", art = "pawn", a1 = "#ff8a80", a2 = "#e5484d"},
	{id = "pawn-green", name = "Green Pawn", art = "pawn", a1 = "#8be3b0", a2 = "#2fa86b"},
	{id = "pawn-yellow", name = "Yellow Pawn", art = "pawn", a1 = "#ffe27a", a2 = "#e0a100"},
	{id = "pawn-blue", name = "Blue Pawn", art = "pawn", a1 = "#8fb7ff", a2 = "#3b7be0"},
	{id = "latte", name = "Latte", art = "cup", a1 = "#f1d9b5", a2 = "#a8693c"},
	{id = "dice", name = "Lucky Dice", art = "dice", a1 = "#ff9a9d", a2 = "#c3141b", unlock = {ach = "first"}},
	{id = "robot", name = "Robot", art = "robot", a1 = "#b8e7ff", a2 = "#3a8fd0", unlock = {ach = "streak"}},
	{id = "crown", name = "Crown", art = "crown", a1 = "#c99bff", a2 = "#6a35c0", unlock = {level = 5}},
]
## Frames: the rings around the avatar tile (index.html .avatar.f-*: box-shadow rings + glow).
## inner / outer ring colours and widths (px at a 60 px avatar), glow colour and blur.
const FRAMES := [
	{id = "classic", name = "Wood", inner = "#ffffff", outer = "#e0a868", iw = 2.0, ow = 2.0, glow = "", blur = 0.0},
	{id = "gold", name = "Gold", unlock = {level = 5}, inner = "#fff3a0", outer = "#e0a100", iw = 2.0, ow = 3.0, glow = "#f2b632", ga = 0.6, blur = 16.0},
	{id = "mint", name = "Mint", unlock = {ach = "pairs"}, inner = "#e9fff1", outer = "#2fa86b", iw = 2.0, ow = 3.0, glow = "#2fa86b", ga = 0.5, blur = 14.0},
	{id = "royal", name = "Royal", unlock = {ach = "coins"}, inner = "#ffffff", outer = "#7c4dff", iw = 2.0, ow = 3.0, glow = "#7c4dff", ga = 0.55, blur = 16.0},
]
## Nameplates (index.html .n-*): vertical gradient, 1 px inner rim, text colour. Plain has no plate.
const PLATES := [
	{id = "plain", name = "Plain", text = "#4a2b3d"},
	{id = "espresso", name = "Espresso", unlock = {ach = "veteran"}, top = "#4a2c1a", bottom = "#2a170c", rim = "#8a5530", rim_a = 1.0, text = "#f7a928"},
	{id = "ruby", name = "Ruby", unlock = {ach = "streak"}, top = "#ff6b6b", bottom = "#b51d22", rim = "#ffffff", rim_a = 0.5, text = "#ffffff"},
]
## Achievements: a stat reaching a goal pays `reward` coins once. Its medal (badge) is assets/ui/medal_<id>.svg: the
## ribbons, a gold-rimmed disc in `color` and an emblem (trophy, flame, star, a pawn pair, two pawns, coins); `mark`
## is only the fallback text drawn on the plain disc when that file is missing.
const ACH := [
	{id = "first", name = "First Victory", desc = "Win a game against the computer.", goal = 1, stat = "wins", reward = 200, color = "#e0a100", mark = "1"},
	{id = "streak", name = "Winning Streak", desc = "Win 3 games in a row.", goal = 3, stat = "bestStreak", reward = 300, color = "#e5484d", mark = "x3"},
	{id = "veteran", name = "Experienced Player", desc = "Finish 25 games.", goal = 25, stat = "played", reward = 500, color = "#3b7be0", mark = "25"},
	{id = "pairs", name = "Master of Pairs", desc = "Form 10 pairs.", goal = 10, stat = "pairsFormed", reward = 300, color = "#2fa86b", mark = "P"},
	{id = "party", name = "Multiplayer Champion", desc = "Finish 5 Pass & Play games.", goal = 5, stat = "ppGames", reward = 300, color = "#7c4dff", mark = "5"},
	{id = "coins", name = "Coin Collector", desc = "Earn 10,000 coins in total.", goal = 10000, stat = "coinsEarned", reward = 500, color = "#d98a0b", mark = "$"},
]
## Badges: "" (no badge) and every achievement's medal, worn once that achievement is done.
const BADGES := ["", "first", "streak", "veteran", "pairs", "party", "coins"]

## Set to a Dictionary to work on it instead of Save.profile (tests). null = Save.profile.
static var profile_source: Variant = null
## Called with the profile after every change; returns true when it was saved. Invalid = Save.save() (+ Save.changed).
static var writer: Callable

static var _tex := {}
static var _gray: Shader


# =====================================================================================================================
# Catalogue
# =====================================================================================================================

## Any avatar (original or character) by id; {} when unknown.
static func avatar(id: String) -> Dictionary:
	for a: Dictionary in AVATARS:
		if a.id == id:
			return a
	return character(id)

static func character(id: String) -> Dictionary:
	for c: Dictionary in CHARS:
		if c.id == id:
			return c
	return {}

static func frame(id: String) -> Dictionary:
	return _find(FRAMES, id)

static func plate(id: String) -> Dictionary:
	return _find(PLATES, id)

static func ach(id: String) -> Dictionary:
	return _find(ACH, id)

static func is_character(id: String) -> bool:
	return not character(id).is_empty()

## The catalogue entry for a kind ("avatar" | "char" | "frame" | "plate" | "badge"); a badge is its achievement,
## the "" badge is {id = "", name = "No badge"}.
static func item(kind: String, id: String) -> Dictionary:
	match kind:
		"avatar", "char":
			return avatar(id)
		"frame":
			return frame(id)
		"plate":
			return plate(id)
		"badge":
			return {id = "", name = "No badge"} if id == "" else ach(id)
	return {}

## The tile gradient of an avatar: [a1, a2].
static func avatar_colors(id: String) -> Array:
	var a := avatar(id)
	if a.is_empty():
		a = AVATARS[0]
	return [Color(a.a1), Color(a.a2)]


# =====================================================================================================================
# The player's things
# =====================================================================================================================

static func profile() -> Dictionary:
	if profile_source is Dictionary:
		return profile_source
	var s := _save_node()
	return s.profile if s else {}

static func coins(p: Dictionary = {}) -> int:
	return int(_p(p).get("coins", 0))

## Level n needs 100 + 50·(n−1) XP to reach n+1 (levelInfo).
static func level_info(xp: int) -> Dictionary:
	var level := 1
	var need := 100
	while xp >= need:
		xp -= need
		level += 1
		need = 100 + (level - 1) * 50
	return {level = level, into = xp, need = need}

static func level(p: Dictionary = {}) -> int:
	return int(level_info(maxi(0, int(_p(p).get("xp", 0)))).level)

static func stat(name: String, p: Dictionary = {}) -> int:
	var st = _p(p).get("stats", {})
	return int((st as Dictionary).get(name, 0)) if st is Dictionary else 0

static func ach_done(id: String, p: Dictionary = {}) -> bool:
	var a := ach(id)
	return not a.is_empty() and stat(a.stat, p) >= int(a.goal)

## isUnlocked: a paid character once bought; otherwise free, or its level / achievement reached. Unknown ids: false.
static func is_unlocked(kind: String, id: String, p: Dictionary = {}) -> bool:
	if kind == "badge":
		return id == "" or ach_done(id, p)
	var it := item(kind, id)
	if it.is_empty():
		return false
	if int(it.get("price", 0)) > 0:
		return _list(_p(p), "av_owned").has(id)
	var u: Dictionary = it.get("unlock", {})
	if u.is_empty():
		return true
	if u.has("level"):
		return level(p) >= int(u.level)
	return ach_done(str(u.ach), p)

## Why an item is locked: "12K coins", "Reach level 5", "Earn “Coin Collector”" ("" when it is free).
static func unlock_text(kind: String, id: String) -> String:
	if kind == "badge":
		return "" if id == "" else "Earn “%s”" % ach(id).get("name", id)
	var it := item(kind, id)
	if int(it.get("price", 0)) > 0:
		return "%s coins" % Fmt.coins(int(it.price))
	var u: Dictionary = it.get("unlock", {})
	if u.is_empty():
		return ""
	if u.has("level"):
		return "Reach level %d" % int(u.level)
	return "Earn “%s”" % ach(str(u.ach)).get("name", u.ach)

## What is in use for a kind ("avatar" | "frame" | "plate" | "badge"), falling back to the default when the saved
## value is unknown or no longer unlocked (ensureProfile).
static func equipped(kind: String, p: Dictionary = {}) -> String:
	var pp := _p(p)
	match kind:
		"avatar", "char":
			var id := str(pp.get("avatar", DEFAULT_AVATAR))
			return id if is_unlocked("avatar", id, pp) else DEFAULT_AVATAR
		"frame":
			var id := str(pp.get("frame", DEFAULT_FRAME))
			return id if is_unlocked("frame", id, pp) else DEFAULT_FRAME
		"plate":
			var id := str(pp.get("plate", DEFAULT_PLATE))
			return id if is_unlocked("plate", id, pp) else DEFAULT_PLATE
		"badge":
			var id := str(pp.get("badge", ""))
			return id if is_unlocked("badge", id, pp) else ""
	return ""

static func is_equipped(kind: String, id: String, p: Dictionary = {}) -> bool:
	return equipped(kind, p) == id


# =====================================================================================================================
# Buying, equipping, claiming
# =====================================================================================================================

## Buys a paid character (buyAvatar): only with enough coins, never twice. "" when bought, else the reason (nothing
## changed then). Buying doesn't equip it (the card then offers Use), unless `equip_it`.
static func buy_char(id: String, equip_it := false) -> String:
	var c := character(id)
	if c.is_empty():
		return "That character isn’t in the collection."
	var price := int(c.price)
	if price <= 0:
		return "%s is free to use." % c.name
	if is_unlocked("char", id):
		return "You already own %s." % c.name
	if coins() < price:
		return Catalog.need_text(price - coins())
	var ok := _commit(func(p: Dictionary) -> void:
		p.coins = int(p.get("coins", 0)) - price
		var owned := _list(p, "av_owned")
		owned.append(id)
		p.av_owned = owned
		if equip_it:
			p.avatar = id)
	return "" if ok else SAVE_FAILED

## Puts an unlocked item in use (kind "avatar" | "char" | "frame" | "plate" | "badge"; badge "" = no badge).
## False when it is locked or unknown (or the save failed); true when it is in use now.
static func equip(kind: String, id: String) -> bool:
	if not is_unlocked(kind, id):
		return false
	var field: String = {avatar = "avatar", char = "avatar", frame = "frame", plate = "plate", badge = "badge"}.get(kind, "")
	if field == "":
		return false
	if str(profile().get(field, "")) == id and profile().has(field):
		return true
	return _commit(func(p: Dictionary) -> void: p[field] = id)

## {value (capped at the goal), goal, done, claimed, pct 0..1} for an achievement ({} when unknown).
static func ach_progress(id: String, p: Dictionary = {}) -> Dictionary:
	var a := ach(id)
	if a.is_empty():
		return {}
	var goal := int(a.goal)
	var v := mini(goal, stat(a.stat, p))
	return {value = v, goal = goal, done = v >= goal, claimed = _list(_p(p), "claimed").has(id), pct = float(v) / goal}

## Pays a finished, unclaimed achievement's coins once (they count as coins earned, like addCoins).
## Returns the coins paid, 0 when it isn't claimable (or the save failed: then nothing changed).
static func claim_ach(id: String) -> int:
	var pr := ach_progress(id)
	if pr.is_empty() or not pr.done or pr.claimed:
		return 0
	var reward := int(ach(id).reward)
	var ok := _commit(func(p: Dictionary) -> void:
		var cl := _list(p, "claimed")
		cl.append(id)
		p.claimed = cl
		p.coins = int(p.get("coins", 0)) + reward
		var st: Dictionary = p.get("stats") if p.get("stats") is Dictionary else {}
		st.coinsEarned = int(st.get("coinsEarned", 0)) + reward
		p.stats = st)
	return reward if ok else 0

## Achievements done but not yet claimed (the dot on the Achievements tab).
static func claimable_count(p: Dictionary = {}) -> int:
	var n := 0
	for a: Dictionary in ACH:
		var pr := ach_progress(a.id, p)
		if pr.done and not pr.claimed:
			n += 1
	return n


# =====================================================================================================================
# Drawing: avatar art as SVG (rasterised once per id and size)
# =====================================================================================================================

## The square avatar tile: the gradient (160deg), corners rounded at 28 %, the art (portraits fill it; the other
## art sits at 62 % with a soft shadow). px = texture size (drawn smaller it stays crisp, mipmapped).
static func avatar_texture(id: String, px := 256) -> Texture2D:
	var a := avatar(id)
	if a.is_empty():
		a = AVATARS[0]
	return _svg_texture("tile:%s:%d" % [a.id, px], tile_svg(a.id), px / 40.0)

## Only the art on a transparent square (for a tile drawn some other way, e.g. a game card's own gradient box).
static func art_texture(id: String, px := 256) -> Texture2D:
	var a := avatar(id)
	if a.is_empty():
		a = AVATARS[0]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">%s</svg>' % _art_layer(a)
	return _svg_texture("art:%s:%d" % [a.id, px], svg, px / 40.0)

## The tile as an SVG document (40 x 40).
static func tile_svg(id: String) -> String:
	var a := avatar(id)
	if a.is_empty():
		a = AVATARS[0]
	# CSS linear-gradient(160deg) over a 40 x 40 box: the gradient line runs through the centre, 25.64 either side
	return ('<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40"><defs>'
		+ '<linearGradient id="g" gradientUnits="userSpaceOnUse" x1="11.23" y1="-4.09" x2="28.77" y2="44.09">'
		+ '<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>' % [a.a1, a.a2]
		+ '<clipPath id="c"><rect width="40" height="40" rx="11.2"/></clipPath></defs>'
		+ '<rect width="40" height="40" rx="11.2" fill="url(#g)"/><g clip-path="url(#c)">%s</g></svg>' % _art_layer(a))

static func _art_layer(a: Dictionary) -> String:
	if a.has("hs"):
		return person_svg(a)
	var art: String = ART[a.art]
	var k := 24.8 / (24.0 if a.art == "pawn" else 40.0)        # 62 % of the tile
	# drop-shadow(0 2px 2px rgba(110,60,90,.25)): the same shapes in the shadow colour, a little lower
	var shadow := RegEx.create_from_string('(fill|stroke)="#[0-9a-fA-F]+"').sub(art, '$1="#6e3c5a"', true)
	return ('<g transform="translate(7.6 9) scale(%s)" opacity="0.25">%s</g>' % [k, shadow]
		+ '<g transform="translate(7.6 7.6) scale(%s)">%s</g>' % [k, art])

## The non-portrait avatar art (AV_ART; the pawn is #pawnIco on a 24 grid, the rest 40).
const ART := {
	pawn = '<circle cx="12" cy="6.5" r="3.6" fill="#fff8ec"/><path d="M8.6 11.2h6.8l-1.1 2.3 2.4 5.2c.3.7-.2 1.3-.9 1.3H8.2c-.7 0-1.2-.6-.9-1.3l2.4-5.2z" fill="#fff8ec"/><rect x="6" y="19.2" width="12" height="2.6" rx="1.3" fill="#fff8ec"/>',
	cup = '<circle cx="18" cy="21" r="13" fill="#fff8ec"/><rect x="29" y="17" width="8" height="7" rx="3.5" fill="#fff8ec"/><circle cx="18" cy="21" r="9.5" fill="#6b3a1e"/><path d="M18 26.5c-5-3.2-6-6.2-3.6-7.8 1.5-1 3 0 3.6 1 .6-1 2.1-2 3.6-1 2.4 1.6 1.4 4.6-3.6 7.8z" fill="#f3e3cc"/>',
	dice = '<rect x="6" y="6" width="28" height="28" rx="7" fill="#fff8ec"/><g fill="#22263f"><circle cx="13" cy="13" r="2.8"/><circle cx="27" cy="13" r="2.8"/><circle cx="20" cy="20" r="2.8"/><circle cx="13" cy="27" r="2.8"/><circle cx="27" cy="27" r="2.8"/></g>',
	crown = '<path d="M6 29l-2-17 9 7 7-11 7 11 9-7-2 17z" fill="#ffe27a" stroke="#fff8ec" stroke-width="2" stroke-linejoin="round"/><rect x="6" y="30" width="28" height="4" rx="2" fill="#fff8ec"/><circle cx="20" cy="22" r="2.6" fill="#e5484d"/>',
	robot = '<line x1="20" y1="4" x2="20" y2="10" stroke="#fff8ec" stroke-width="2.5"/><circle cx="20" cy="4.5" r="2.5" fill="#ff5a5a"/><rect x="7" y="10" width="26" height="22" rx="9" fill="#fff8ec"/><rect x="11" y="15" width="18" height="11" rx="5.5" fill="#1d2240"/><circle cx="16" cy="20.5" r="2.4" fill="#4df0ff"/><circle cx="24" cy="20.5" r="2.4" fill="#4df0ff"/>',
}

## A character's bust on the 40 x 40 grid (personSVG): back hair, outfit, neck, head, face, front hair, accessory.
static func person_svg(p: Dictionary) -> String:
	var S: String = p.skin
	var H: String = p.hair
	var AC: String = p.get("ac", "#fff8ec")
	var ink := "#3a2230"
	var back := ""
	var front := ""
	var acc := ""
	var face := ""
	var ears_on := true
	var crop := "M12 16C12 9 16 7 20 7C25 7 28 9.5 28 16C26 13 23 12 20 12.5C16 12 13.5 13.5 12 16Z"
	var long_back := "M10.6 17C10 8.5 14.5 5.6 20 5.6C25.5 5.6 30 8.5 29.4 17L30.6 33.5C26.5 35 13.5 35 9.4 33.5Z"
	match str(p.hs):
		"crop":
			front = _path(crop, H)
		"quiff":
			front = _path("M12 15.5C11 8 15 5 21 4.6C26.5 4.6 29.2 8.2 28 15.5C27 12.2 25 11.5 22.5 11.2C25.3 9.3 22.5 7.5 19 9.6C16 11.2 13.5 12.4 12 15.5Z", H)
		"afro":
			back = _circle(20, 13.5, 11.2, H)
			front = _path("M12.2 15.5C12.5 10 16 8.6 20 8.6C24 8.6 27.5 10 27.8 15.5C25 12.8 15 12.8 12.2 15.5Z", H)
		"side":
			front = _path("M12 17C11 9 15 6.5 20 6.5C26 6.5 29 9 28.5 17L27.2 13C23 13 18 12.2 15 9.8C14 12 13 14 12 17Z", H)
		"buzz":
			front = _path("M12.3 15C12.5 9.5 16 7.8 20 7.8C24 7.8 27.5 9.5 27.7 15C25 12.6 15 12.6 12.3 15Z", H)
			face = _path("M12.6 18.4C12.8 25.2 16 27.2 20 27.2C24 27.2 27.2 25.2 27.4 18.4C26.4 22 24 23.4 20 23.4C16 23.4 13.6 22 12.6 18.4Z", H)
		"manbun":
			front = _circle(20, 5.4, 3.1, H) + _path(crop, H)
		"spiky":
			front = _path("M12 16L11.4 9.8L14.6 11L15 6.4L18 9L20 4.8L22 9L25 6.4L25.4 11L28.6 9.8L28 16C25 13 15 13 12 16Z", H)
		"cap":
			front = (_path("M12.2 17L12.6 13H27.4L27.8 17C26 15.4 14 15.4 12.2 17Z", H)
				+ _path("M11.6 14.2C11.6 7.6 15.6 6 20 6C24.4 6 28.4 7.6 28.4 14.2Z", AC)
				+ _path("M19 12.8L33.2 13.4C33.4 15 31.4 15.6 28 15.4L19 15Z", AC)
				+ _path("M11.6 14.2C11.6 7.6 15.6 6 20 6C17 8 16.2 10.6 16.6 14.2Z", "SH"))
		"curls":
			for c: Array in [[13.6, 13.2, 2.6], [15, 10.2, 3], [18.3, 8.2, 3.2], [22, 8, 3.2], [25.3, 9.8, 3], [26.8, 13, 2.6]]:
				front += _circle(c[0], c[1], c[2], H)
		"beanie":
			front = (_path("M11.5 15.2C11.5 7.2 15.5 5.4 20 5.4C24.5 5.4 28.5 7.2 28.5 15.2Z", AC)
				+ '<rect x="11" y="12.6" width="18" height="3.6" rx="1.8" fill="%s"/>' % AC
				+ '<rect x="11" y="12.6" width="18" height="3.6" rx="1.8" fill="SH"/>'
				+ _circle(20, 4.6, 2.4, "#fff8ec"))
		"long":
			back = _path(long_back, H)
			front = _path("M12 17C11.5 9 15 7 20 7C25 7 28.5 9 28 17C26 12.5 22 11 17 11.6C15 12 13 14 12 17Z", H)
		"bob":
			back = _path("M10.4 23.5C9.4 10 14 6 20 6C26 6 30.6 10 29.6 23.5C27.2 24.6 26 24 27.4 21.4H12.6C14 24 12.8 24.6 10.4 23.5Z", H)
			front = _path("M12 16.2C12 9.6 15.5 7.4 20 7.4C24.5 7.4 28 9.6 28 16.2V14C24 13 16 13 12 14Z", H)
		"pony":
			back = _path("M26.6 9.6C33.4 10.6 34.6 20.4 31 27.2C30.2 21.6 29 16.4 25.6 13Z", H)
			front = _path(crop, H) + _circle(27.4, 10.4, 1.7, AC)
		"curlylong":
			for c: Array in [[11.6, 14, 4], [12, 21, 4.2], [13, 27.6, 3.8], [28.4, 14, 4], [28, 21, 4.2], [27, 27.6, 3.8], [20, 8.4, 6.4], [14.6, 9.6, 4], [25.4, 9.6, 4]]:
				back += _circle(c[0], c[1], c[2], H)
			for c: Array in [[14.4, 12.6, 2.6], [17.6, 10.6, 2.8], [21.6, 10.4, 2.8], [25, 12.2, 2.6]]:
				front += _circle(c[0], c[1], c[2], H)
		"buns":
			back = _circle(12.4, 7.6, 3.8, H) + _circle(27.6, 7.6, 3.8, H)
			front = _path("M12 16.5C12 9.6 15.6 7.6 20 7.6C24.4 7.6 28 9.6 28 16.5C25.6 13.2 22.4 12.4 20 13.4C17.6 12.4 14.4 13.2 12 16.5Z", H)
		"pixie":
			front = _path("M12 18C10.8 10 14.6 6.6 20.4 6.6C26 6.6 29.2 9.6 28.2 15.6C25.8 11.8 21 13.6 16.6 11.4C15.2 13.8 13.6 15.4 12 18Z", H)
		"braids":
			for x: float in [10.8, 29.2]:
				for y: float in [17, 21, 25, 29]:
					back += '<ellipse cx="%s" cy="%s" rx="2.4" ry="2.3" fill="%s"/>' % [x, y, H]
				back += _circle(x, 32.4, 1.4, AC)
			front = _path("M12 17C11.6 9 15.2 7 20 7C24.8 7 28.4 9 28 17C27 13 24 11.6 20.4 11.2V9.6L19.6 11.2C16 11.6 13 13 12 17Z", H)
		"hijab":
			ears_on = false
			back = _path("M9.4 20.6C9 9.2 14 5 20 5C26 5 31 9.2 30.6 20.6C30.6 27 26.6 30.4 20 30.8C13.4 30.4 9.4 27 9.4 20.6Z", H)
			front = (_path("M12.6 15.6C13 10.6 16.2 8.8 20 8.8C23.8 8.8 27 10.6 27.4 15.6C25 12.6 15 12.6 12.6 15.6Z", H)
				+ _path("M9.6 21C11 27.6 15 30 20 30.4C17 31.6 13.4 32.6 11.2 34.6C10 31 9.4 26 9.6 21Z", "SH"))
		"wavy":
			back = _path("M10.6 17C10 8.5 14.5 5.6 20 5.6C25.5 5.6 30 8.5 29.4 17C31.4 20 29 22.4 30.8 25.4C32.4 28.2 29.6 31 30.4 33.6C26.4 35 13.6 35 9.6 33.6C10.4 31 7.6 28.2 9.2 25.4C11 22.4 8.6 20 10.6 17Z", H)
			front = (_path("M12 16.6C11.6 9 15.2 7 20 7C24.8 7 28.4 9 28 16.6C25 12.6 15 12.6 12 16.6Z", H)
				+ '<path d="M12.4 12.4C15 9.4 25 9.4 27.6 12.4" fill="none" stroke="%s" stroke-width="2.2" stroke-linecap="round"/>' % AC)
		"bangs":
			back = _path(long_back, H)
			front = (_path("M12 16.2C11.8 9.2 15.4 7 20 7C24.6 7 28.2 9.2 28 16.2C27.6 14.6 27.2 14 26.4 14H13.6C12.8 14 12.4 14.6 12 16.2Z", H)
				+ _path("M25.4 8.2L29.4 6.2L29 10ZM25.4 8.2L28.8 11.6L25.2 11Z", AC) + _circle(25.6, 9.2, 1.3, AC))
	# outfit and its detail
	var T: String = p.top
	var od := ""
	match str(p.get("od", "")):
		"v":
			od = _path("M17 28.6L20 33.4L23 28.6Z", S)
		"collar":
			od = _path("M16 28.2L20 31.4L17.6 33.6ZM24 28.2L20 31.4L22.4 33.6Z", "#fff8ec")
		"hoodie":
			od = ('<path d="M13 29.6C15 32 25 32 27 29.6" fill="none" stroke="SH" stroke-width="2.4"/>'
				+ '<path d="M18 31.4V36.4M22 31.4V36.4" stroke="#fff8ec" stroke-width="1.1" stroke-linecap="round"/>')
		"stripe":
			od = ('<path d="M7.2 35.6H32.8V37.4H7.2Z" fill="#fff8ec" opacity=".85"/>'
				+ '<path d="M17.4 28.4C18.6 30 21.4 30 22.6 28.4" fill="none" stroke="SH" stroke-width="1.6"/>')
		"tie":
			od = (_path("M17 28.2L20 31.4L23 28.2", "#fff8ec") + _path("M17 30.2L20 31.6L17 33ZM23 30.2L20 31.6L23 33Z", AC)
				+ _circle(20, 31.6, 0.9, AC))
		"necklace":
			od = ('<path d="M16.4 28.6C17.4 31.4 22.6 31.4 23.6 28.6" fill="none" stroke="%s" stroke-width="1"/>' % AC
				+ _circle(20, 31, 1.2, AC))
		"scarf":
			od = _path("M14.6 27.4C16.6 30 23.4 30 25.4 27.4L26.4 29.2C24 32 16 32 13.6 29.2Z", AC) + _path("M23 30.2L24.8 36.4L22 36Z", AC)
		"dupatta":
			od = '<path d="M8.4 33.8C12 30.2 16 29 18.6 29.2L22.6 40H15.6Z" fill="%s" opacity=".9"/>' % AC
	var outfit := _path("M6 40C6 31.4 12 28 20 28C28 28 34 31.4 34 40Z", T) + _path("M6 40C6 31.4 12 28 20 28C14.6 30 12.4 34 12.6 40Z", "SH") + od
	var neck := _path("M17 22.6H23V28.8C21.4 30 18.6 30 17 28.8Z", S) + _path("M17 24.6C18.8 26 21.2 26 23 24.6V22.6H17Z", "SH")
	var ears := (_circle(12.1, 18.4, 1.9, S) + _circle(27.9, 18.4, 1.9, S)) if ears_on else ""
	var hijab: bool = p.hs == "hijab"
	var head := ears + '<ellipse cx="20" cy="17.4" rx="%s" ry="%s" fill="%s"/>' % [7.2 if hijab else 8, 8.2 if hijab else 9, S]
	var f: bool = p.g == "f"
	var eyes := ('<ellipse cx="16.8" cy="18.2" rx="1.15" ry="1.35" fill="%s"/><ellipse cx="23.2" cy="18.2" rx="1.15" ry="1.35" fill="%s"/>' % [ink, ink]
		+ _circle(17.2, 17.7, 0.4, "#fff") + _circle(23.6, 17.7, 0.4, "#fff"))
	if f:
		eyes += '<path d="M15.2 17.3L14.6 16.6M24.8 17.3L25.4 16.6" stroke="%s" stroke-width=".7" stroke-linecap="round"/>' % ink
	else:
		eyes += '<path d="M15.2 15.6Q16.8 14.8 18.4 15.5M21.6 15.5Q23.2 14.8 24.8 15.6" fill="none" stroke="%s" stroke-width="1" stroke-linecap="round"/>' % (ink if hijab else H)
	var mouth := (_path("M18 21.8Q20 23.8 22 21.8Q20 22.6 18 21.8Z", "#d9536a") if f
		else '<path d="M17.8 21.6Q20 23.6 22.2 21.6" fill="none" stroke="%s" stroke-width=".9" stroke-linecap="round"/>' % ink)
	var cheeks := '<circle cx="15.2" cy="21" r="1.5" fill="#ff8f9b" opacity=".35"/><circle cx="24.8" cy="21" r="1.5" fill="#ff8f9b" opacity=".35"/>'
	match str(p.get("acc", "")):
		"glasses":
			acc = '<g fill="none" stroke="%s" stroke-width=".9"><circle cx="16.8" cy="18.2" r="2.5"/><circle cx="23.2" cy="18.2" r="2.5"/><path d="M19.3 18H20.7"/></g>' % AC
		"earrings":
			acc = _circle(12.1, 21.2, 1, AC) + _circle(27.9, 21.2, 1, AC)
	var out := back + outfit + neck + head + face + eyes + mouth + cheeks + front + acc
	# the soft shade rgba(70,30,40,.16) as colour + opacity (plain hex keeps every SVG reader happy)
	return out.replace('fill="SH"', 'fill="#461e28" fill-opacity="0.16"').replace('stroke="SH"', 'stroke="#461e28" stroke-opacity="0.16"')

static func _path(d: String, fill: String) -> String:
	return '<path d="%s" fill="%s"/>' % [d, fill]

static func _circle(x: float, y: float, r: float, fill: String) -> String:
	return '<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % [x, y, r, fill]

## An achievement's medal: assets/ui/medal_<id>.svg (the icon family: plum outlines, a white gloss), mipmapped.
## Without that file: the plain ribbons + disc of badgeSVG (BadgeView then draws the mark on it).
static func medal_texture(id: String) -> Texture2D:
	var path := "%smedal_%s.svg" % [UIKit.ICON_DIR, id]
	if ach(id).is_empty() or not ResourceLoader.exists(path):
		return null
	return UIKit.svg(path)

## The plain medal (badgeSVG) without its mark: two ribbons and the coloured disc (fallback of medal_texture).
static func badge_texture(id: String, px := 128) -> Texture2D:
	var a := ach(id)
	var col: String = a.get("color", "#c7a98a")
	var svg := ('<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">'
		+ '<path d="M12 1h6l-2 13h-6zM22 1h6l-2 13h-6z" fill="#c3141b"/>'
		+ '<circle cx="20" cy="25" r="13" fill="%s" stroke="#fff3a0" stroke-width="2.5"/></svg>' % col)
	return _svg_texture("badge:%s:%d" % [id, px], svg, px / 40.0)

## Rasterises an SVG once (mipmapped, so small draws stay smooth).
static func _svg_texture(key: String, svg: String, scale: float) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var img := Image.new()
	var err := img.load_svg_from_string(svg, scale)
	if err != OK:
		push_warning("Collection: bad SVG for %s" % key)
		img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


# =====================================================================================================================
# Drawing: Controls
# =====================================================================================================================

## The avatar inside its frame, fitting a size x size square (the frame rings are inside it; the glow spills out).
## profile {} = the live profile's equipped avatar and frame. Call .refresh() on it after the profile changes.
static func make_avatar(size: float, p := {}) -> Control:
	var v := AvatarView.new()
	v.custom_minimum_size = Vector2(size, size)
	v.size = Vector2(size, size)
	v.use_profile(p)
	return v

## The same for a given avatar and frame (collection cards, previews).
static func make_avatar_of(id: String, frame_id: String, size: float) -> AvatarView:
	var v := AvatarView.new()
	v.custom_minimum_size = Vector2(size, size)
	v.size = Vector2(size, size)
	v.set_look(id, frame_id)
	return v

## The name on a nameplate with a badge after it (index.html .plate). badge "" = none.
## The name keeps its natural width up to max_text_w, then ends in an ellipsis.
static func make_plate(text: String, plate_id: String, badge_id := "", font_size := 20, padded := true, max_text_w := 220.0) -> PlateView:
	var v := PlateView.new()
	v.max_text_w = max_text_w
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.setup(text, plate_id, badge_id, font_size, padded)
	return v

## An achievement's medal; dim = the grey "not earned yet" look.
static func make_badge(id: String, size: float, dim := false) -> BadgeView:
	var b := BadgeView.new()
	b.ach_id = id
	b.custom_minimum_size = Vector2(size, size)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if dim:
		set_dim(b, true, 1.0, 0.42)
	return b

## The "locked" look (index.html .locked .avatar: grayscale(1) brightness(.6)), or the "not earned" medal look
## (grayscale + opacity). Off restores full colour. Children follow the parent's material.
static func set_dim(c: CanvasItem, on: bool, brightness := 0.6, alpha := 1.0) -> void:
	if not on:
		c.material = null
		return
	if _gray == null:
		_gray = Shader.new()
		_gray.code = """shader_type canvas_item;
uniform float bright = 0.6;
uniform float alpha = 1.0;
void fragment() {
	float g = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)) * bright;
	COLOR = vec4(vec3(g), COLOR.a * alpha);
}"""
	var m := ShaderMaterial.new()
	m.shader = _gray
	m.set_shader_parameter("bright", brightness)
	m.set_shader_parameter("alpha", alpha)
	c.material = m
	for ch in c.find_children("*", "CanvasItem", true, false):
		(ch as CanvasItem).use_parent_material = true


## The avatar tile in its frame. Draws: glow, outer ring, inner ring, the tile texture.
class AvatarView extends Control:
	var avatar_id := Collection.DEFAULT_AVATAR
	var frame_id := Collection.DEFAULT_FRAME
	var _src := {}           # {} = the live profile

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func set_look(id: String, f: String) -> void:
		avatar_id = id if not Collection.avatar(id).is_empty() else Collection.DEFAULT_AVATAR
		frame_id = f if not Collection.frame(f).is_empty() else Collection.DEFAULT_FRAME
		queue_redraw()

	func use_profile(p: Dictionary) -> void:
		_src = p
		refresh()

	## Re-reads the equipped avatar and frame.
	func refresh() -> void:
		set_look(Collection.equipped("avatar", _src), Collection.equipped("frame", _src))

	## Ring widths scale with the avatar a little (the web uses fixed px; tiny chips get thinner rings).
	func ring_k() -> float:
		return clampf(minf(size.x, size.y) / 60.0, 0.6, 1.4)

	func _draw() -> void:
		var side := minf(size.x, size.y)
		if side <= 0:
			return
		var f := Collection.frame(frame_id)
		var k := ring_k()
		var iw: float = f.iw * k
		var ow: float = f.ow * k
		var origin := (size - Vector2(side, side)) / 2.0
		var tile := Rect2(origin + Vector2(iw + ow, iw + ow), Vector2.ONE * (side - 2.0 * (iw + ow)))
		var r := tile.size.x * 0.28
		var outer := StyleBoxFlat.new()
		outer.bg_color = Color(f.outer)
		outer.set_corner_radius_all(int(round(r + iw + ow)))
		outer.corner_detail = 12
		outer.anti_aliasing = true
		if float(f.blur) > 0.0:
			outer.shadow_color = Color(Color(f.glow), float(f.ga) * 0.55)
			outer.shadow_size = int(round(float(f.blur) * 0.4 * k))
		draw_style_box(outer, tile.grow(iw + ow))
		var inner := StyleBoxFlat.new()
		inner.bg_color = Color(f.inner)
		inner.set_corner_radius_all(int(round(r + iw)))
		inner.corner_detail = 12
		inner.anti_aliasing = true
		draw_style_box(inner, tile.grow(iw))
		draw_texture_rect(Collection.avatar_texture(avatar_id), tile, false)


## A medal: the medal_<id>.svg art (or, without it, the plain disc with its mark in Lilita One).
class BadgeView extends Control:
	var ach_id := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		resized.connect(queue_redraw)

	func _draw() -> void:
		var side := minf(size.x, size.y)
		if side <= 0 or ach_id == "":
			return
		var o := (size - Vector2(side, side)) / 2.0
		var art := Collection.medal_texture(ach_id)
		if art:
			draw_texture_rect(art, Rect2(o, Vector2(side, side)), false)
			return
		draw_texture_rect(Collection.badge_texture(ach_id), Rect2(o, Vector2(side, side)), false)
		var a := Collection.ach(ach_id)
		var font := UIKit.font_display()
		var fs := int(round(side * 13.0 / 40.0))
		var mark: String = a.get("mark", "")
		var w := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var asc := font.get_ascent(fs)
		var desc := font.get_descent(fs)
		var cy := o.y + side * 25.0 / 40.0
		draw_string(font, Vector2(o.x + (side - w) / 2.0, cy + (asc - desc) / 2.0 - side * 0.01), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## The name on its plate (pill with a vertical gradient and a thin rim), the badge after the name.
class PlateView extends PanelContainer:
	var plate_id := Collection.DEFAULT_PLATE
	var label: Label
	var badge: BadgeView
	var max_text_w := 220.0
	var _padded := true
	var _fs := 20

	func setup(text: String, pid: String, bid: String, fs: int, padded: bool) -> void:
		_fs = fs
		_padded = padded
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", int(round(fs * 0.32)))
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(h)
		label = UIKit.label(text, fs, Palette.INK, UIKit.font_display())
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(label)
		badge = Collection.make_badge(bid, roundf(fs * 1.3))
		h.add_child(badge)
		set_look(text, pid, bid)
		resized.connect(queue_redraw)

	func set_look(text: String, pid: String, bid: String) -> void:
		plate_id = pid if not Collection.plate(pid).is_empty() else Collection.DEFAULT_PLATE
		label.text = text
		var tw := UIKit.font_display().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
		label.custom_minimum_size.x = ceilf(minf(tw + 1.0, max_text_w))
		badge.ach_id = bid
		badge.visible = bid != ""
		badge.queue_redraw()
		var pl := Collection.plate(plate_id)
		label.add_theme_color_override("font_color", Color(pl.text))
		var plain := plate_id == Collection.DEFAULT_PLATE
		var st := StyleBoxEmpty.new()
		var padx := 0.0 if plain and not _padded else roundf(_fs * 0.6)
		st.content_margin_left = padx
		st.content_margin_right = padx if not badge.visible else roundf(padx * 0.6)
		st.content_margin_top = 0.0 if plain and not _padded else roundf(_fs * 0.12)
		st.content_margin_bottom = st.content_margin_top
		add_theme_stylebox_override("panel", st)
		queue_redraw()

	func _draw() -> void:
		var pl := Collection.plate(plate_id)
		if not pl.has("top") or size.x < 2 or size.y < 2:
			return
		var w := int(roundf(size.x))
		var h := int(roundf(size.y))
		var key := "plate:%s:%dx%d" % [plate_id, w, h]
		var rim_a: float = pl.rim_a
		var svg := ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><defs>' % [w, h, w, h]
			+ '<linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>' % [pl.top, pl.bottom]
			+ '<rect width="%d" height="%d" rx="%s" fill="url(#g)"/>' % [w, h, h / 2.0]
			+ '<rect x="0.5" y="0.5" width="%s" height="%s" rx="%s" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="1"/></svg>' % [w - 1.0, h - 1.0, (h - 1.0) / 2.0, pl.rim, rim_a])
		draw_texture_rect(Collection._svg_texture(key, svg, 3.0), Rect2(Vector2.ZERO, Vector2(w, h)), false)


# =====================================================================================================================
# Internals
# =====================================================================================================================

static func _p(p: Dictionary) -> Dictionary:
	return p if not p.is_empty() else profile()

static func _find(list: Array, id: String) -> Dictionary:
	for it: Dictionary in list:
		if it.id == id:
			return it
	return {}

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
