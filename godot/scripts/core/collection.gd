class_name Collection
extends RefCounted
## The player's Collection (index.html: AV_ART, personSVG, CHARS, AVATARS, FRAMES, PLATES, ACH, isUnlocked,
## unlockText, levelInfo, avatarHTML, badgeSVG, buyAvatar, the Collection equip handler and the Achievements claim).
##   Characters: 20 drawn portraits (10 male, 10 female). Arif and Nadia are free, the rest cost 10,000-12,000 coins
##     and, once bought, are listed in profile.av_owned.
##   More characters: 12 free portraits with a wide range of looks (WORLD; they are characters too, kind "char").
##   Avatars: the four pawns and Latte are free; Lucky Dice / Robot unlock with an achievement, Crown at level 5.
##   Frames (3D-rendered art round the avatar, assets/frames) are free, sold for coins or gems, or earned; Nameplates
##     (behind the name) and Badges (an earned achievement's medal beside the name) unlock by level or achievement.
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
## Display text (name, desc, unlock texts) is translated where it is shown: L10n.t(x.name), L10n.t(x.desc); the l10n-keys line
## below collects the table values. Character names stay English (their entries say so in bn.po).
const SAVE_FAILED := "Couldn’t save on this device. No coins were spent."  # l10n
const SAVE_FAILED_EQUIP := "Couldn’t save on this device."  # l10n

## l10n-keys: name, desc
## Character portraits: skin, hair (colour), hs (hairstyle), top (outfit colour), od (outfit detail), acc (accessory),
## ac (accessory colour), g ("m" | "f"); a1 / a2 the tile gradient. The first of each gender is free.
const CHARS := [
	{id = "ch-arif", name = "Arif", g = "m", price = 0, a1 = "#bfe6ff", a2 = "#6fb3e8", skin = "#eebf9c", hair = "#3b2a24", hs = "crop", top = "#3b7be0", od = "v", mouth = "smile"},
	{id = "ch-rafi", name = "Rafi", g = "m", price = 10000, a1 = "#ffe2b3", a2 = "#f3a64b", skin = "#d9a07a", hair = "#1f1a1c", hs = "quiff", top = "#2fa86b", od = "collar", mouth = "grin"},
	{id = "ch-tanvir", name = "Tanvir", g = "m", price = 10500, a1 = "#d9f3e4", a2 = "#6cc79a", skin = "#8d5a3b", hair = "#1b1416", hs = "afro", top = "#f4a340", od = "hoodie", mouth = "laugh", look = "happy"},
	{id = "ch-nayeem", name = "Nayeem", g = "m", price = 11000, a1 = "#e9e0ff", a2 = "#a58bf0", skin = "#f3c6a5", hair = "#5b3a22", hs = "side", top = "#5b4bb7", od = "tie", acc = "glasses", ac = "#3a2230", mouth = "smile"},
	{id = "ch-sabbir", name = "Sabbir", g = "m", price = 11750, a1 = "#ffd6cf", a2 = "#ef7e6f", skin = "#b97a52", hair = "#2a1d18", hs = "buzz", top = "#4a4f63", od = "stripe", mouth = "grin"},
	{id = "ch-imran", name = "Imran", g = "m", price = 10250, a1 = "#fff1c2", a2 = "#e9c14c", skin = "#eebf9c", hair = "#6b4426", hs = "manbun", top = "#c0483f", od = "scarf", ac = "#f3d36b", mouth = "smirk"},
	{id = "ch-rakib", name = "Rakib", g = "m", price = 12000, a1 = "#cdeff5", a2 = "#4fb6c9", skin = "#d9a07a", hair = "#e2a23a", hs = "spiky", top = "#2b2f45", od = "v", mouth = "grin", look = "wink"},
	{id = "ch-fahim", name = "Fahim", g = "m", price = 11250, a1 = "#ffe0ec", a2 = "#f28bb0", skin = "#f6d2b8", hair = "#3b2a24", hs = "cap", top = "#ffffff", od = "stripe", ac = "#e5484d", mouth = "laugh"},
	{id = "ch-shuvo", name = "Shuvo", g = "m", price = 10750, a1 = "#e3f4c8", a2 = "#9ccc5a", skin = "#b97a52", hair = "#1f1a1c", hs = "curls", top = "#8a5a3c", od = "collar", mouth = "smile", look = "happy"},
	{id = "ch-jamil", name = "Jamil", g = "m", price = 11500, a1 = "#dfe7ff", a2 = "#7d97e8", skin = "#f3c6a5", hair = "#4a2e20", hs = "beanie", top = "#2fb39c", od = "hoodie", acc = "glasses", ac = "#e0a100", mouth = "smirk"},
	{id = "ch-nadia", name = "Nadia", g = "f", price = 0, a1 = "#ffd9e6", a2 = "#f590b4", skin = "#eebf9c", hair = "#2a1d18", hs = "long", top = "#e5484d", od = "necklace", ac = "#f4c430", mouth = "lips"},
	{id = "ch-riya", name = "Riya", g = "f", price = 10000, a1 = "#d8f1ff", a2 = "#68b8ea", skin = "#f6d2b8", hair = "#1f1a1c", hs = "bob", top = "#f4c430", od = "collar", mouth = "laugh", look = "happy"},
	{id = "ch-tania", name = "Tania", g = "f", price = 10500, a1 = "#fff0c9", a2 = "#f0b84a", skin = "#d9a07a", hair = "#7a4a28", hs = "pony", top = "#7c4dff", od = "v", ac = "#ff7a9c", mouth = "lips", look = "wink"},
	{id = "ch-mim", name = "Mim", g = "f", price = 11000, a1 = "#e7dcff", a2 = "#a98cf0", skin = "#8d5a3b", hair = "#1b1416", hs = "curlylong", top = "#2fa86b", od = "necklace", acc = "earrings", ac = "#f4c430", mouth = "grin"},
	{id = "ch-sumaiya", name = "Sumaiya", g = "f", price = 11750, a1 = "#d6f4ea", a2 = "#5fc4a3", skin = "#f3c6a5", hair = "#6b3a7a", hs = "hijab", top = "#6b3a7a", od = "v", mouth = "smile"},
	{id = "ch-priya", name = "Priya", g = "f", price = 10250, a1 = "#ffe1d1", a2 = "#f39a6b", skin = "#b97a52", hair = "#2a1d18", hs = "buns", top = "#3b7be0", od = "stripe", mouth = "laugh"},
	{id = "ch-lamia", name = "Lamia", g = "f", price = 12000, a1 = "#fce4ff", a2 = "#d58be8", skin = "#eebf9c", hair = "#c4572a", hs = "pixie", top = "#2b2f45", od = "necklace", acc = "earrings", ac = "#e9e3ff", mouth = "smirk"},
	{id = "ch-fariha", name = "Fariha", g = "f", price = 11250, a1 = "#fff6c8", a2 = "#e6cf52", skin = "#d9a07a", hair = "#1f1a1c", hs = "braids", top = "#e5484d", od = "dupatta", ac = "#f4c430", mouth = "lips"},
	{id = "ch-nusrat", name = "Nusrat", g = "f", price = 10750, a1 = "#d9ecff", a2 = "#8fb3ef", skin = "#f6d2b8", hair = "#5b3a22", hs = "wavy", top = "#ff9ec7", od = "collar", ac = "#2fb39c", mouth = "grin"},
	{id = "ch-ayesha", name = "Ayesha", g = "f", price = 11500, a1 = "#ffdcd6", a2 = "#ee8a7c", skin = "#8d5a3b", hair = "#1b1416", hs = "bangs", top = "#2fb39c", od = "scarf", ac = "#ffd45e", mouth = "smile", look = "happy"},
]
## More characters: free for everyone, with a wide range of looks; shown together, never labelled by origin. Common desi names (owner 2026-11-06);
## the ids keep the old names because saves and the server hold them. On top of
## the fields above: eye ("round" | "almond" | "narrow" | "big"), eyeCol, lash, brow ("none" | "thin" | "soft" | "thick"),
## nose ("small" | "wide"), mouth ("lips" | "smile" | "grin" | "neutral"), fh (facial hair: "stubble" | "moustache" |
## "goatee" | "beard"). None of them set: the default face for that gender. Every character also has its own expression:
## mouth ("lips" | "smile" | "grin" | "laugh" | "smirk" | "neutral") and look ("" | "happy" | "wink").
const WORLD := [
	{id = "w-hana", name = "Sadia", g = "f", price = 0, a1 = "#ffe0ec", a2 = "#f28bb0", skin = "#f6d9c2", hair = "#ee5f9b", hs = "hijab", eye = "big", nose = "small", top = "#b23a78", mouth = "laugh"},
	{id = "w-kenji", name = "Sakib", g = "m", price = 0, a1 = "#dfe7ff", a2 = "#7d97e8", skin = "#f3d3b5", hair = "#1b1416", hs = "side", eye = "narrow", nose = "small", top = "#2b2f45", od = "v", mouth = "smirk"},
	{id = "w-mei", name = "Mitu", g = "f", price = 0, a1 = "#d6f4ea", a2 = "#5fc4a3", skin = "#f6d9c2", hair = "#2a1d18", hs = "buns", eye = "almond", nose = "small", top = "#e5484d", od = "necklace", ac = "#f4c430", mouth = "grin"},
	{id = "w-linh", name = "Sharmin", g = "f", price = 0, a1 = "#fff0c9", a2 = "#f0b84a", skin = "#e3b18a", hair = "#2fa86b", hs = "hijab", eye = "almond", nose = "small", top = "#1f7a4d", mouth = "smile", look = "happy"},
	{id = "w-emma", name = "Farzana", g = "f", price = 0, a1 = "#d8f1ff", a2 = "#68b8ea", skin = "#eebf9c", hair = "#2a1d18", hs = "wavy", nose = "small", top = "#9b6be0", od = "collar", ac = "#ff7fae", mouth = "laugh"},
	{id = "w-lukas", name = "Hasan", g = "m", price = 0, a1 = "#e3f4c8", a2 = "#9ccc5a", skin = "#d9a07a", hair = "#2a1d18", hs = "crop", nose = "small", fh = "stubble", top = "#3b7be0", od = "hoodie", mouth = "smile"},
	{id = "w-sofia", name = "Jannat", g = "f", price = 0, a1 = "#ffe1d1", a2 = "#f39a6b", skin = "#f3c6a5", hair = "#c8434f", hs = "hijab", nose = "small", top = "#8f2a3a", mouth = "lips", look = "wink"},
	{id = "w-oliver", name = "Rahim", g = "m", price = 0, a1 = "#fff1c2", a2 = "#e9c14c", skin = "#b97a52", hair = "#1f1a1c", hs = "curls", nose = "small", top = "#e5484d", od = "stripe", mouth = "grin"},
	{id = "w-jayden", name = "Sohel", g = "m", price = 0, a1 = "#cdeff5", a2 = "#4fb6c9", skin = "#6b4128", hair = "#1b1416", hs = "fade", nose = "wide", top = "#f4a340", od = "hoodie", mouth = "grin"},
	{id = "w-maya", name = "Rupa", g = "f", price = 0, a1 = "#fce4ff", a2 = "#d58be8", skin = "#8d5a3b", hair = "#1b1416", hs = "locs", nose = "wide", top = "#f4c430", od = "necklace", acc = "earrings", ac = "#f4c430", mouth = "lips"},
	{id = "w-carlos", name = "Kamal", g = "m", price = 0, a1 = "#ffd6cf", a2 = "#ef7e6f", skin = "#c68a5e", hair = "#2a1d18", hs = "quiff", nose = "small", fh = "moustache", top = "#2fa86b", od = "collar", mouth = "laugh"},
	{id = "w-ava", name = "Tasnim", g = "f", price = 0, a1 = "#e7dcff", a2 = "#a98cf0", skin = "#c68a5e", hair = "#3b7be0", hs = "hijab", nose = "small", top = "#2452a8", mouth = "grin"},
]
## The original avatars (the Avatars tab). Red Pawn is the fallback. Characters are avatars too (avatar(id) finds both).
const AVATARS := [
	{id = "pawn-red", name = "Red Pawn", art = "hero", a1 = "#ffe3da", a2 = "#f7a596", body = "#ff6f62", deep = "#c9353c"},
	{id = "pawn-green", name = "Green Pawn", art = "sprout", a1 = "#e2f7e4", a2 = "#93dcae", body = "#46c988", deep = "#1f8f5c"},
	{id = "pawn-yellow", name = "Yellow Pawn", art = "beats", a1 = "#fff5cf", a2 = "#fbd670", body = "#ffc83a", deep = "#d99600"},
	{id = "pawn-blue", name = "Blue Pawn", art = "cool", a1 = "#dfeaff", a2 = "#9cbdf7", body = "#5c9bf6", deep = "#2c62c4"},
	{id = "latte", name = "Latte", art = "latte", a1 = "#fbeeda", a2 = "#e6bd8d"},
	{id = "dice", name = "Lucky Dice", art = "dice", a1 = "#ffc2bd", a2 = "#e0434b", unlock = {ach = "first"}},
	{id = "robot", name = "Robot", art = "robot", a1 = "#d6f1ff", a2 = "#74bdec", unlock = {ach = "streak"}},
	{id = "crown", name = "Crown", art = "royal", a1 = "#ebdfff", a2 = "#ac8df2", body = "#8a5cf0", deep = "#5a30b8", unlock = {level = 5}},
]

## Frames: 3D-rendered art around the avatar tile (tools/frames/frames.blend.py -> assets/frames/<id>.webp). The art is
## a FRAME_CANVAS-times-wider square centred on the tile, so crests, wings and tassels break out of it.
## For sale: `price` (coins; also ceil(price / 100) gems) or `gems` alone (gems only, like the premium pawn skins);
## `unlock` = earned by level or achievement; neither = free. Once bought a frame is listed in profile.av_owned.
## The look in motion (AvatarView's shader): `shine` = how bright the light sweep over the metal is (0 = none);
## `sparks` = where stones twinkle, in the render's units (the tile is -1..1, y up).
## l10n-keys: name
const FRAMES := [
	{id = "classic", name = "Wood", shine = 0.0, sparks = []},
	{id = "silver", name = "Silver", price = 1500, shine = 0.45, sparks = [[0.93, 0.93], [-0.93, -0.93], [0.0, 1.24]]},
	{id = "gold", name = "Gold", unlock = {level = 5}, shine = 0.55, sparks = [[0.93, 0.93], [-0.93, 0.93], [0.93, -0.93], [-0.93, -0.93], [0.0, 1.26]]},
	{id = "mint", name = "Emerald", unlock = {ach = "pairs"}, shine = 0.5, sparks = [[0.93, 0.93], [-0.93, -0.93], [0.0, 1.34], [-0.93, 0.93]]},
	{id = "royal", name = "Royal Crown", unlock = {ach = "coins"}, shine = 0.5, sparks = [[0.0, 1.19], [0.93, 0.93], [-0.93, -0.93], [0.93, -0.93]]},
	{id = "rose", name = "Rose Hearts", price = 4000, shine = 0.45, sparks = [[0.0, 1.31], [0.95, 0.95], [-0.95, -0.95]]},
	{id = "ludo", name = "Ludo Champ", price = 6000, shine = 0.35, sparks = [[0.0, 1.24]]},
	{id = "ice", name = "Frost", gems = 80, shine = 0.5, sparks = [[0.95, 0.95], [-0.95, 0.95], [0.95, -0.95], [-0.95, -0.95], [0.0, 1.5]]},
	{id = "rickshaw", name = "Rickshaw Art", gems = 100, shine = 0.4, sparks = [[0.0, 1.22], [0.93, 0.93], [-0.93, -0.93]]},
	{id = "wings", name = "Angel Wings", gems = 120, shine = 0.6, sparks = [[0.0, 1.28], [0.93, 0.93], [-0.93, 0.93], [0.93, -0.93], [-0.93, -0.93]]},
	{id = "diamond", name = "Diamond", gems = 150, shine = 0.6, sparks = [[0.0, 1.46], [0.3, 1.36], [-0.3, 1.36], [0.0, -1.24], [1.1, 0.0], [-1.1, 0.0], [0.6, -1.1], [-0.6, 1.1]]},
]
## The frame art spans FRAME_CANVAS tile half-widths each way (the render's canvas, tools/frames/frames.blend.py).
const FRAME_CANVAS := 1.75
## The tile's share of an AvatarView's square: the frame's band then just reaches the edge; crests spill past it.
const FRAME_TILE := 0.8
## Nameplates: 3D-rendered plates behind the name (assets/ui3d/plate_<id>.webp, tools/frames/ui_art.blend.py), drawn
## in three slices so they stretch to any name. Plain has no plate. Sold, earned or free like the frames (price / gems /
## unlock; bought ones listed in profile.av_owned, so plate ids never repeat a frame's or a character's). `text` is the
## name's colour on the plate.
## l10n-keys: name
const PLATES := [
	{id = "plain", name = "Plain", text = "#4a2b3d"},
	{id = "espresso", name = "Espresso", unlock = {ach = "veteran"}, text = "#ffd27a"},
	{id = "ruby", name = "Ruby", unlock = {ach = "streak"}, text = "#ffffff"},
	{id = "scroll", name = "Gold Scroll", price = 3000, text = "#4a2212"},
	{id = "velvet", name = "Royal Velvet", price = 5000, text = "#ffffff"},
	{id = "paint", name = "Rickshaw Paint", gems = 60, text = "#ffffff"},
	{id = "neon", name = "Neon", gems = 80, text = "#c9fdff"},
	{id = "crystal", name = "Diamond Plate", gems = 120, text = "#ffffff"},
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
static var _medals := {}
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
	return _find(WORLD, id)

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
			return {id = "", name = L10n.t("No badge")} if id == "" else ach(id)
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
	if int(it.get("price", 0)) > 0 or int(it.get("gems", 0)) > 0:
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
		return "" if id == "" else L10n.t("Earn “%s”") % L10n.t(str(ach(id).get("name", id)))
	var it := item(kind, id)
	if int(it.get("price", 0)) > 0:
		return L10n.t("%s coins") % Fmt.coins(int(it.price))
	if int(it.get("gems", 0)) > 0:
		return L10n.t("%s gems") % Fmt.coins_full(int(it.gems))
	var u: Dictionary = it.get("unlock", {})
	if u.is_empty():
		return ""
	if u.has("level"):
		return L10n.t("Reach level %d") % int(u.level)
	return L10n.t("Earn “%s”") % L10n.t(str(ach(str(u.ach)).get("name", u.ach)))

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
		return L10n.t("That character isn’t in the collection.")
	var price := int(c.price)
	if price <= 0:
		return L10n.t("%s is free to use.") % c.name
	if is_unlocked("char", id):
		return L10n.t("You already own %s.") % c.name
	if coins() < price:
		return Catalog.need_text(price - coins())
	var ok := _commit(func(p: Dictionary) -> void:
		p.coins = int(p.get("coins", 0)) - price
		var owned := _list(p, "av_owned")
		owned.append(id)
		p.av_owned = owned
		if equip_it:
			p.avatar = id)
	return "" if ok else L10n.t(SAVE_FAILED)

## Buys a frame or nameplate for coins and puts it in use (the local rules; with an Account the server sells,
## ShopSheet._purchase). Gem-only ones can't be bought here (gems live on the server). "" when bought, else the reason.
static func buy_look(kind: String, id: String) -> String:
	var f := item(kind, id) if kind in ["frame", "plate"] else {}
	if f.is_empty():
		return L10n.t("That frame isn’t in the collection.") if kind == "frame" else L10n.t("That nameplate isn’t in the collection.")
	if is_unlocked(kind, id):
		return L10n.t("You already own %s.") % L10n.t(str(f.name))
	var price := int(f.get("price", 0))
	if price <= 0:
		# sold for gems only, or earned (level / achievement): say how
		return L10n.t("%s is sold for gems only.") % L10n.t(str(f.name)) if int(f.get("gems", 0)) > 0 else unlock_text(kind, id)
	if coins() < price:
		return Catalog.need_text(price - coins())
	var ok := _commit(func(p: Dictionary) -> void:
		p.coins = int(p.get("coins", 0)) - price
		var owned := _list(p, "av_owned")
		owned.append(id)
		p.av_owned = owned
		p[kind] = id)
	return "" if ok else L10n.t(SAVE_FAILED)

static func buy_frame(id: String) -> String:
	return buy_look("frame", id)

static func buy_plate(id: String) -> String:
	return buy_look("plate", id)

## A frame's or nameplate's coin price (0 = not sold for coins) and gem price (its own when sold for gems only, else
## ceil(price / 100)).
static func look_price(kind: String, id: String) -> int:
	return int(item(kind, id).get("price", 0))

static func look_gems(kind: String, id: String) -> int:
	var f := item(kind, id)
	return int(f.gems) if f.has("gems") else Catalog.gem_price(int(f.get("price", 0)))

static func look_gems_only(kind: String, id: String) -> bool:
	var f := item(kind, id)
	return int(f.get("gems", 0)) > 0 and int(f.get("price", 0)) <= 0

## A frame's coin price (0 = not sold for coins) and gem price (its own for a gems-only frame, else ceil(price / 100)).
static func frame_price(id: String) -> int:
	return look_price("frame", id)

static func frame_gems(id: String) -> int:
	return look_gems("frame", id)

static func frame_gems_only(id: String) -> bool:
	return look_gems_only("frame", id)

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

## The square avatar tile: the gradient (160deg), corners rounded at 28 %, the art filling it (a character's bust or a
## classic avatar's mascot). px = texture size (drawn smaller it stays crisp, mipmapped).
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
	return person_svg(a) if a.has("hs") else mascot_svg(a)

const INK := "#3a2230"
const CREAM := "#fff8ec"
const GOLD := "#ffcf4a"

## A classic avatar's mascot on the 40 x 40 grid: they have faces, like the characters and the computer players.
static func mascot_svg(a: Dictionary) -> String:
	var out := ""
	match str(a.art):
		"hero":
			out = _mascot_hero(a)
		"sprout":
			out = _mascot_sprout(a)
		"beats":
			out = _mascot_beats(a)
		"cool":
			out = _mascot_cool(a)
		"royal":
			out = _mascot_royal(a)
		"latte":
			out = _mascot_latte()
		"dice":
			out = _mascot_dice()
		"robot":
			out = _mascot_robot()
	return _soft_shade(out)

## The soft shade rgba(70,30,40,.16) as colour + opacity (plain hex keeps every SVG reader happy).
static func _soft_shade(svg: String) -> String:
	return svg.replace('fill="SH"', 'fill="#461e28" fill-opacity="0.16"').replace('stroke="SH"', 'stroke="#461e28" stroke-opacity="0.16"')

## The pawn with a big round head: body, collar, head, its shade and shine (the face goes on top).
static func _pawn(body: String, deep: String) -> String:
	return (_path("M6.5 40C6.5 33.8 11.4 30.8 15 28.6H25C28.6 30.8 33.5 33.8 33.5 40Z", body)
		+ _path("M6.5 40C6.5 33.8 11.4 30.8 15 28.6H17.6C14.2 31 12.6 35 12.8 40Z", "SH")
		+ '<rect x="12" y="25.2" width="16" height="4.4" rx="2.2" fill="%s"/>' % deep
		+ _circle(20, 15.4, 10.8, body)
		+ _path("M13 7.2C8 11.4 8 20 12.8 23.6C16.2 26.4 21.2 26.8 24.6 25.2C17.4 25.2 11 17.6 13 7.2Z", "SH")
		+ '<ellipse cx="15.6" cy="8.8" rx="3" ry="1.6" transform="rotate(-28 15.6 8.8)" fill="#fff" opacity=".5"/>')

static func _open_eye(x: float, y: float) -> String:
	return '<ellipse cx="%s" cy="%s" rx="1.6" ry="2" fill="%s"/>' % [x, y, INK] + _circle(x + 0.5, y - 0.7, 0.6, "#fff")

static func _happy_eye(x: float, y: float) -> String:
	return '<path d="M%s %sQ%s %s %s %s" fill="none" stroke="%s" stroke-width="1.4" stroke-linecap="round"/>' % [x - 2, y + 0.9, x, y - 1.7, x + 2, y + 0.9, INK]

static func _cheeks(y: float, col := "#ff5f7e", op := 0.38) -> String:
	return '<circle cx="13.4" cy="%s" r="1.9" fill="%s" opacity="%s"/><circle cx="26.6" cy="%s" r="1.9" fill="%s" opacity="%s"/>' % [y, col, op, y, col, op]

## An open, laughing mouth with its tongue.
static func _laugh(y: float) -> String:
	return (_path("M16.6 %sQ20 %s 23.4 %sQ20 %s 16.6 %sZ" % [y, y + 5.4, y, y + 0.8, y], INK)
		+ _path("M18 %sQ20 %s 22 %sQ20 %s 18 %sZ" % [y + 2.2, y + 4.2, y + 2.2, y + 1.2, y + 2.2], "#ff7f8f"))

## Red: the plucky hero, a headband and a toothy grin.
static func _mascot_hero(a: Dictionary) -> String:
	return (_path("M28.8 11.2L36.4 7.6L35 11.6L37 15.4L29.4 14.6Z", a.deep)
		+ _pawn(a.body, a.deep)
		+ _path("M9.5 13.2Q20 7.8 30.5 13.2L30.8 16.2Q20 10.8 9.2 16.2Z", CREAM)
		+ _path("M9.4 15.2Q20 9.8 30.6 15.2L30.8 16.2Q20 10.8 9.2 16.2Z", a.deep)
		+ '<path d="M13.8 15.9L18 16.9M26.2 15.9L22 16.9" fill="none" stroke="%s" stroke-width="1.3" stroke-linecap="round"/>' % INK
		+ _open_eye(16.3, 18.9) + _open_eye(23.7, 18.9) + _cheeks(21.8)
		+ '<path d="M16.8 21.8H23.2Q22.8 24.8 20 24.8Q17.2 24.8 16.8 21.8Z" fill="#fff" stroke="%s" stroke-width=".9" stroke-linejoin="round"/>' % INK)

## Green: the gentle one, a sprout on the head and smiling eyes.
static func _mascot_sprout(a: Dictionary) -> String:
	return ('<g transform="translate(0 3.2)">' + _pawn(a.body, a.deep)
		+ '<path d="M20 5.2V1.4" fill="none" stroke="%s" stroke-width="1.5" stroke-linecap="round"/>' % a.deep
		+ _path("M20 2C17 2.8 13.6 1.8 12.2 -1.6C16 -2.4 19.4 -1.2 20 2Z", "#a9ee9a")
		+ _path("M20 2C23 2.8 26.4 1.8 27.8 -1.6C24 -2.4 20.6 -1.2 20 2Z", "#7ee08a")
		+ _happy_eye(15.9, 14.8) + _happy_eye(24.1, 14.8) + _cheeks(18.2, "#ffb08a", 0.75) + _laugh(18.4) + "</g>")

## Yellow: the music lover, headphones and a wink.
static func _mascot_beats(a: Dictionary) -> String:
	var phones := "#7a4bd6"
	return (_pawn(a.body, a.deep)
		+ '<path d="M8.6 16C8.4 7.6 13.4 2.8 20 2.8C26.6 2.8 31.6 7.6 31.4 16" fill="none" stroke="%s" stroke-width="2.4" stroke-linecap="round"/>' % phones
		+ '<rect x="5.8" y="12.6" width="6" height="9.4" rx="3" fill="%s"/><rect x="28.2" y="12.6" width="6" height="9.4" rx="3" fill="%s"/>' % [phones, phones]
		+ '<rect x="7.2" y="14.4" width="2" height="5.8" rx="1" fill="#ff8fc0"/><rect x="30.8" y="14.4" width="2" height="5.8" rx="1" fill="#ff8fc0"/>'
		+ _open_eye(16.2, 15.6) + _happy_eye(24, 15.8) + _cheeks(19.2)
		+ '<path d="M16.4 19.8Q20 23.8 23.6 19.8" fill="none" stroke="%s" stroke-width="1.3" stroke-linecap="round"/>' % INK
		+ _path("M20.4 21.8Q22 21.4 22.8 20.6Q23.2 23.2 21.6 23.4Q20.4 23.4 20.4 21.8Z", "#ff7f8f"))

## Blue: the cool one, shades and a crooked smile.
static func _mascot_cool(a: Dictionary) -> String:
	return (_path("M13.6 6.2C14.2 2.4 18.4 1.2 20.4 3.4C21.6 1 26 1.6 26.6 6.4C22.6 4 17.6 4 13.6 6.2Z", a.deep)
		+ _pawn(a.body, a.deep)
		+ '<path d="M9.6 13.6H30.4" fill="none" stroke="#1d1922" stroke-width="1.5" stroke-linecap="round"/>'
		+ _path("M11 13.2H19C19.4 17.8 17.6 19.4 14.8 19.4C12 19.4 10.8 17.6 11 13.2Z", "#1d1922")
		+ _path("M21 13.2H29C29.2 17.6 28 19.4 25.2 19.4C22.4 19.4 20.6 17.8 21 13.2Z", "#1d1922")
		+ '<path d="M13 14.6L15.6 17.6M23 14.6L25.6 17.6" stroke="#8fd8ff" stroke-width="1.1" stroke-linecap="round"/>'
		+ '<path d="M16.8 22.8Q20.8 24.4 24 21" fill="none" stroke="%s" stroke-width="1.3" stroke-linecap="round"/>' % INK)

## Crown (level 5): the king of the board, a big gold crown and a proud smile.
static func _mascot_royal(a: Dictionary) -> String:
	return ('<g transform="translate(0 2.8)">' + _pawn(a.body, a.deep)
		+ _path("M9.6 11.4L7.4 1.4L14.2 5.8L20 -0.4L25.8 5.8L32.6 1.4L30.4 11.4C24 9.4 16 9.4 9.6 11.4Z", GOLD)
		+ _path("M9.6 11.4L7.4 1.4L14.2 5.8L13.4 10.4C12 10.6 10.8 11 9.6 11.4Z", "#f2b02c")
		+ _path("M9.5 11.4C16 9.4 24 9.4 30.5 11.4L30.1 13.2C24 11.4 16 11.4 9.9 13.2Z", "#f09a1c")
		+ _circle(20, 6.4, 1.7, "#ff4d6a") + _circle(14.6, 8, 1.1, "#4dd6e8") + _circle(25.4, 8, 1.1, "#4dd6e8")
		+ _circle(7.4, 1.4, 1.1, CREAM) + _circle(20, -0.4, 1.1, CREAM) + _circle(32.6, 1.4, 1.1, CREAM)
		+ _happy_eye(16, 16.6) + _happy_eye(24, 16.6) + _cheeks(19.4, "#ff8fb0", 0.6)
		+ '<path d="M16.8 20.2Q20 23.4 23.2 20.2" fill="none" stroke="%s" stroke-width="1.3" stroke-linecap="round"/>' % INK
		+ '<path d="M6.5 40C6.5 35 9 32.6 12.4 30.8C14 33 26 33 27.6 30.8C31 32.6 33.5 35 33.5 40Z" fill="%s"/>' % CREAM
		+ _circle(13, 35.2, 0.9, INK) + _circle(20, 34.8, 0.9, INK) + "</g>")

## Latte: a tall glass with foam, a straw and a sleepy, happy face.
static func _mascot_latte() -> String:
	return ('<path d="M25.6 8L28.8 0.6" fill="none" stroke="#ff7a8f" stroke-width="2.4" stroke-linecap="round"/>'
		+ _path("M10.4 12H29.6L27.4 37C27.2 39 26 40 24 40H16C14 40 12.8 39 12.6 37Z", "#c98b57")
		+ _path("M12 30H28L27.4 37C27.2 39 26 40 24 40H16C14 40 12.8 39 12.6 37Z", "#f6e4c8")
		+ _path("M11.6 25.6C15 27.4 17.4 24.8 20 26.2C22.6 27.6 25.4 25 28.4 26.4L28 31C25 29.6 22.6 32 20 30.6C17.4 29.2 15 32 12 30.2Z", "#e3b78a")
		+ _path("M10.4 12H14L15.4 40H16C14 40 12.8 39 12.6 37Z", "SH")
		+ _circle(14, 9.6, 4.4, CREAM) + _circle(20, 7.6, 5.4, CREAM) + _circle(26, 9.6, 4.4, CREAM)
		+ '<rect x="9.2" y="9.8" width="21.6" height="4.4" rx="2.2" fill="%s"/>' % CREAM
		+ _path("M20 11.4C17.6 9.8 17.2 8.2 18.4 7.4C19.2 6.9 19.8 7.4 20 7.9C20.2 7.4 20.8 6.9 21.6 7.4C22.8 8.2 22.4 9.8 20 11.4Z", "#c98b57")
		+ _happy_eye(16, 19) + _happy_eye(24, 19) + _cheeks(22)
		+ '<path d="M17.6 22.2Q20 24.6 22.4 22.2" fill="none" stroke="%s" stroke-width="1.3" stroke-linecap="round"/>' % INK)

## Lucky Dice: a tipsy die whose two middle pips are its eyes, with a four-leaf clover.
static func _mascot_dice() -> String:
	var clover := ""
	for r: int in [0, 90, 180, 270]:
		clover += '<ellipse cx="33" cy="4.2" rx="1.9" ry="2.5" transform="rotate(%d 33 7)" fill="#3fce7c"/>' % r
	return ('<g transform="rotate(-7 20 21)">'
		+ '<rect x="7" y="9.6" width="28" height="28" rx="7.5" fill="#c9202a"/>'
		+ '<rect x="5" y="6.6" width="28" height="28" rx="7.5" fill="%s"/>' % CREAM
		+ _path("M5 28.4C5.6 31.8 8.6 34.6 12.5 34.6H25.5C29.4 34.6 32.4 31.8 33 28.4C30 32.4 8 32.4 5 28.4Z", "SH")
		+ _circle(10.8, 12.2, 2, "#e5484d") + _circle(27.2, 12.2, 2, "#e5484d") + _circle(10.8, 29, 2, "#e5484d") + _circle(27.2, 29, 2, "#e5484d")
		+ _open_eye(15.2, 18.6) + _open_eye(22.8, 18.6)
		+ '<circle cx="12.6" cy="22.2" r="1.7" fill="#ff5f7e" opacity=".38"/><circle cx="25.4" cy="22.2" r="1.7" fill="#ff5f7e" opacity=".38"/>'
		+ '<g transform="translate(-1 0)">' + _laugh(21.6) + "</g></g>"
		+ clover + _circle(33, 7, 0.9, "#1f9a58"))

## Robot: a friendly little one, smiling eyes on a screen and a heart on its chest.
static func _mascot_robot() -> String:
	return ('<rect x="9" y="30" width="22" height="12" rx="4.5" fill="#8fa8c8"/>'
		+ '<rect x="9" y="30" width="6" height="12" rx="3" fill="#461e28" fill-opacity="0.16"/>'
		+ _path("M20 39.4C17.6 37.8 16.8 36.2 17.8 35.2C18.6 34.4 19.6 34.8 20 35.6C20.4 34.8 21.4 34.4 22.2 35.2C23.2 36.2 22.4 37.8 20 39.4Z", "#ff5f7e")
		+ '<rect x="17" y="26.6" width="6" height="4.4" fill="#6f88a8"/>'
		+ '<path d="M20 7V3.6" fill="none" stroke="#6f88a8" stroke-width="1.7" stroke-linecap="round"/>' + _circle(20, 2.8, 2.2, "#ff7a5c") + _circle(19.4, 2.2, 0.7, "#fff")
		+ '<rect x="4.6" y="14.2" width="4.4" height="8.4" rx="2.2" fill="#ff7a5c"/><rect x="31" y="14.2" width="4.4" height="8.4" rx="2.2" fill="#ff7a5c"/>'
		+ '<rect x="7" y="6.4" width="26" height="22.4" rx="9" fill="#f2f8ff"/>'
		+ _path("M7 15.4C7 10 11 6.4 16 6.4H17C13 7.6 11.2 11 11.4 15.4C11.4 21 13 25.8 17.6 28.8H16C11 28.8 7 25 7 19.8Z", "SH")
		+ '<rect x="10.6" y="10.4" width="18.8" height="14" rx="6" fill="#1d2748"/>'
		+ '<g fill="none" stroke="#5ff2ff" stroke-width="1.7" stroke-linecap="round"><path d="M13.6 17.2Q15.6 14.2 17.6 17.2"/><path d="M22.4 17.2Q24.4 14.2 26.4 17.2"/><path d="M17.4 19.6Q20 22.6 22.6 19.6"/></g>'
		+ '<circle cx="13.2" cy="20.6" r="1.3" fill="#ff5f9e" opacity=".75"/><circle cx="26.8" cy="20.6" r="1.3" fill="#ff5f9e" opacity=".75"/>')

const JAW := "M12.6 18.4C12.8 25.2 16 27.2 20 27.2C24 27.2 27.2 25.2 27.4 18.4C26.4 22 24 23.4 20 23.4C16 23.4 13.6 22 12.6 18.4Z"

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
			if not p.has("fh"):                  # the buzz cut's own beard (Sabbir)
				face = _path(JAW, H)
		"manbun":
			front = _circle(20, 5.4, 3.1, H) + _path(crop, H)
		"spiky":
			front = _path("M12 16C11 12.6 11.6 10.8 13 10.4C12.4 8.2 14 6.8 15.6 7.6C15.6 5.2 18 4.4 19.2 6.2C19.8 4 22.4 4.2 23 6.4C24.6 5.2 26.4 6.4 26 8.2C27.8 8.2 28.6 10 27.6 11.2C28.8 12 28.8 14 28 16C25 13 15 13 12 16Z", H)
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
		"hijab":                                 # as the Girl Set emotes: the hood, a dark under-scarf at the brow, the drape
			ears_on = false
			back = _path("M9 20C8.6 8.8 13.8 4.6 20 4.6C26.2 4.6 31.4 8.8 31 20C31 27 26.8 30.8 20 31.2C13.2 30.8 9 27 9 20Z", H)
			front = (_path("M12.7 16C13 10.8 16.2 8.7 20 8.7C23.8 8.7 27 10.8 27.3 16C25.2 12.8 14.8 12.8 12.7 16Z", "#3b2a24")
				+ '<path d="M12.2 16.4C12.2 10.4 15.8 8 20 8C24.2 8 27.8 10.4 27.8 16.4" fill="none" stroke="%s" stroke-width="1"/>' % H
				+ '<path d="M13.6 6.8Q16.4 5.4 19.2 5.3" fill="none" stroke="#fff" stroke-opacity=".3" stroke-width="1.2" stroke-linecap="round"/>')
		"wavy":
			back = _path("M10.6 17C10 8.5 14.5 5.6 20 5.6C25.5 5.6 30 8.5 29.4 17C31.4 20 29 22.4 30.8 25.4C32.4 28.2 29.6 31 30.4 33.6C26.4 35 13.6 35 9.6 33.6C10.4 31 7.6 28.2 9.2 25.4C11 22.4 8.6 20 10.6 17Z", H)
			front = (_path("M12 16.6C11.6 9 15.2 7 20 7C24.8 7 28.4 9 28 16.6C25 12.6 15 12.6 12 16.6Z", H)
				+ '<path d="M12.4 12.4C15 9.4 25 9.4 27.6 12.4" fill="none" stroke="%s" stroke-width="2.2" stroke-linecap="round"/>' % AC)
		"bangs":
			back = _path(long_back, H)
			front = (_path("M12 16.2C11.8 9.2 15.4 7 20 7C24.6 7 28.2 9.2 28 16.2C27.6 14.6 27.2 14 26.4 14H13.6C12.8 14 12.4 14.6 12 16.2Z", H)
				+ _path("M25.4 8.2L29.4 6.2L29 10ZM25.4 8.2L28.8 11.6L25.2 11Z", AC) + _circle(25.6, 9.2, 1.3, AC))
		"bald":
			front = '<ellipse cx="16.6" cy="11.6" rx="2.6" ry="1.3" transform="rotate(-20 16.6 11.6)" fill="#fff" opacity=".28"/>'
		"fade":
			front = (_path("M12.3 15C12.2 8.4 14.8 5.4 20 5.4C25.2 5.4 27.8 8.4 27.7 15C26 13 14 13 12.3 15Z", H)
				+ '<path d="M12.3 15C12.4 13 13 12.4 14 12.2V15.6Z M27.7 15C27.6 13 27 12.4 26 12.2V15.6Z" fill="%s" opacity=".55"/>' % H)
		"straight":
			back = _path("M10.8 17C10.4 8.5 14.6 5.6 20 5.6C25.4 5.6 29.6 8.5 29.2 17L29.8 34.2H10.2Z", H)
			front = _path("M12 17.6C11.6 9.4 15 7 20 7.2C18.6 9.2 16.6 12.6 12 17.6ZM28 17.6C28.4 9.4 25 7 20 7.2C21.4 9.2 23.4 12.6 28 17.6Z", H)
		"locs":
			for r: Array in [["9.7", "21"], ["12.3", "19"], ["25.1", "19"], ["27.7", "21"]]:
				back += '<rect x="%s" y="12" width="2.6" height="%s" rx="1.3" fill="%s"/>' % [r[0], r[1], H]
			front = _path("M12 16.2C11.6 9 15.2 6.8 20 6.8C24.8 6.8 28.4 9 28 16.2C25 12.8 15 12.8 12 16.2Z", H)
			for x: String in ["15.4", "18.4", "21.6", "24.6"]:
				front += '<path d="M%s 8.6V13.4" stroke="#000" stroke-opacity=".18" stroke-width=".7" stroke-linecap="round"/>' % x
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
	var neck := _path("M17 20H23V28.8C21.4 30 18.6 30 17 28.8Z", S) + _path("M17 23.2C18.8 25 21.2 25 23 23.2V20H17Z", "SH")
	if p.hs == "hijab":
		neck = (_path("M9.6 22C8.4 28.6 7.8 33 8.8 36C13 38.8 27 38.8 31.2 36C32.2 33 31.6 28.6 30.4 22Z", H)
			+ _path("M9.6 22C8.4 28.6 7.8 33 8.8 36C10 36.8 11.6 37.4 13.4 37.8C12.4 32 12.6 27 14 22Z", "SH")
			+ '<path d="M13.4 26.6C15.8 30 24.2 30 26.6 26.6M16 33.4Q20 35 24 33.4" fill="none" stroke="SH" stroke-width="1" stroke-linecap="round"/>')
	var ears := (_circle(12.2, 18.6, 1.7, S) + _circle(27.8, 18.6, 1.7, S)) if ears_on else ""
	var hijab: bool = p.hs == "hijab"
	var head := ears + '<ellipse cx="20" cy="17.4" rx="%s" ry="%s" fill="%s"/>' % [7.4 if hijab else 8, 8.4 if hijab else 9, S]
	head += '<path d="M12 17.4C12 22.4 15.6 26.4 20 26.4C16.8 25.4 14.5 21.8 14.3 17.4C14.2 13.6 15.2 11 17 9C14 9.8 12 13 12 17.4Z" fill="#461e28" fill-opacity="0.09"/>'
	var f: bool = p.g == "f"
	var eyes := _eyes(str(p.get("eye", "round")), str(p.get("eyeCol", "")), ink, str(p.get("look", "")), bool(p.get("lash", f)))
	var brow: String = {thin = ".8", soft = "1.1", thick = "1.7"}.get(str(p.get("brow", "thin" if f else "soft")), "")
	if brow != "":
		eyes += '<path d="M14.6 15.5Q16.5 14.3 18.4 15.3M21.6 15.3Q23.5 14.3 25.4 15.5" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round"/>' % [ink if hijab or p.hs == "bald" else H, brow]
	var mouth: String = {
		"lips": _path("M17.2 21.9Q18.8 21 20 21.6Q21.2 21 22.8 21.9Q20 25.2 17.2 21.9Z", "#d9536a") + '<path d="M19 23.4Q20 23.8 21 23.4" fill="none" stroke="#fff" stroke-opacity=".5" stroke-width=".5" stroke-linecap="round"/>',
		"smile": '<path d="M17.3 22Q20 24.7 22.7 22" fill="none" stroke="%s" stroke-width="1" stroke-linecap="round"/>' % ink,
		"grin": '<path d="M17.5 21.8H22.5Q22.3 24.5 20 24.5Q17.7 24.5 17.5 21.8Z" fill="#fff" stroke="%s" stroke-width=".7" stroke-linejoin="round"/>' % ink,
		"laugh": _path("M17.4 21.7H22.6Q22.4 25 20 25Q17.6 25 17.4 21.7Z", "#6e2233") + _path("M18.4 24Q20 23 21.6 24Q21.1 25 20 25Q18.9 25 18.4 24Z", "#ff7f8f") + _path("M17.8 21.7H22.2L22 22.4H18Z", "#fff"),
		"smirk": '<path d="M17.6 23Q20.8 24.2 22.8 21.5" fill="none" stroke="%s" stroke-width="1" stroke-linecap="round"/>' % ink,
		"neutral": '<path d="M18 22.5Q20 23.2 22 22.5" fill="none" stroke="%s" stroke-width="1" stroke-linecap="round"/>' % ink,
	}.get(str(p.get("mouth", "")), "")
	if mouth == "":
		mouth = '<path d="M17.3 22Q20 24.7 22.7 22" fill="none" stroke="%s" stroke-width="1" stroke-linecap="round"/>' % ink
	var nose_d: String = {"wide": "M18.5 20Q18.8 21.2 20 21Q21.2 21.2 21.5 20"}.get(str(p.get("nose", "")), "M19.2 20.2Q20 21 20.8 20.2")
	mouth = '<path d="%s" fill="none" stroke="SH" stroke-width="1" stroke-linecap="round"/>' % nose_d + mouth
	var stache := _path("M17 21.2Q18.6 19.8 20 20.8Q21.4 19.8 23 21.2Q21.6 21.6 20 21.3Q18.4 21.6 17 21.2Z", H)
	match str(p.get("fh", "")):
		"stubble":
			face += '<path d="%s" fill="%s" opacity=".3"/>' % [JAW, H]
		"moustache":
			face += stache
		"goatee":
			face += stache + '<ellipse cx="20" cy="25.6" rx="1.9" ry="1.3" fill="%s"/>' % H
		"beard":
			face += _path(JAW, H) + stache
	var cheeks := '<circle cx="14.6" cy="21.4" r="1.7" fill="#ff6f83" opacity=".32"/><circle cx="25.4" cy="21.4" r="1.7" fill="#ff6f83" opacity=".32"/>'
	match str(p.get("acc", "")):
		"glasses":
			acc = '<g fill="#fff" fill-opacity=".14" stroke="%s" stroke-width="1"><circle cx="16.5" cy="18.5" r="3"/><circle cx="23.5" cy="18.5" r="3"/></g><path d="M19.5 18.2H20.5" fill="none" stroke="%s" stroke-width="1"/>' % [AC, AC]
		"earrings":
			acc = _circle(12.2, 21.4, 1.1, AC) + _circle(27.8, 21.4, 1.1, AC)
		"shades":
			acc = ('<g fill="#1d1922" stroke="%s" stroke-width=".7"><path d="M14 16.8H19.4Q19.6 20.4 16.7 20.4Q14 20.4 14 16.8Z"/><path d="M20.6 16.8H26Q26 20.4 23.3 20.4Q20.4 20.4 20.6 16.8Z"/></g>' % AC
				+ '<path d="M19.4 17.2H20.6" fill="none" stroke="%s" stroke-width=".7"/><path d="M15 17.6L16.2 19" fill="none" stroke="#fff" stroke-opacity=".45" stroke-width=".6" stroke-linecap="round"/>' % AC)
	var shine := ""
	if not ["cap", "beanie", "hijab", "bald", "buzz", "curls", "curlylong", "wavy"].has(str(p.hs)):
		shine = '<path d="M15 10.4Q16.8 8.6 19.2 8.1" fill="none" stroke="#fff" stroke-opacity=".3" stroke-width="1.2" stroke-linecap="round"/>'
	# the big head: the whole of it grows around its middle and sits a little higher, the body a little lower
	var head_y: float = {afro = 18.8, manbun = 18.4, beanie = 18.4, curlylong = 17.6, buns = 17.2}.get(str(p.hs), 16.6)
	var big := 'transform="translate(20 %s) scale(1.16) translate(-20 -17.4)"' % head_y
	var out := ('<g %s>%s</g>' % [big, back]
		+ '<g transform="translate(0 1.8)">%s</g>' % (outfit + neck)
		+ '<g %s>%s</g>' % [big, head + face + eyes + mouth + cheeks + front + shine + acc])
	return _soft_shade(out)

## Both eyes: the white, the iris (dark or eyeCol) with its shine, the upper lid (and lashes). look: "happy" = both
## smiling arcs, "wink" = the right one. shape: "round" | "big" | "almond" | "narrow".
static func _eyes(shape: String, col: String, ink: String, look := "", lash := false) -> String:
	var out := ""
	var i := 0
	for x: float in [16.5, 23.5]:
		var side := -1.0 if x < 20.0 else 1.0
		if look == "happy" or (look == "wink" and i == 1):
			out += '<path d="M%s 19.2Q%s 16.8 %s 19.2" fill="none" stroke="%s" stroke-width="1.2" stroke-linecap="round"/>' % [x - 2, x, x + 2, ink]
			if lash:
				out += '<path d="M%s 18.6L%s 17.8" fill="none" stroke="%s" stroke-width=".8" stroke-linecap="round"/>' % [x + side * 1.8, x + side * 2.6, ink]
			i += 1
			continue
		var iris: String = col if col != "" else ink
		match shape:
			"narrow":
				out += '<path d="M%s 18.9Q%s 16.9 %s 18.9Q%s 20.1 %s 18.9Z" fill="#fff"/>' % [x - 2, x, x + 2, x, x - 2]
				out += _circle(x, 18.6, 1.15, iris) + _circle(x + 0.4, 18.2, 0.35, "#fff")
				out += '<path d="M%s 18.9Q%s 16.9 %s 18.9" fill="none" stroke="%s" stroke-width=".8" stroke-linecap="round"/>' % [x - 2.1, x, x + 2.1, ink]
			"almond":
				out += '<path d="M%s 18.8Q%s 16.2 %s 18.5Q%s 20.6 %s 18.8Z" fill="#fff"/>' % [x - side * 2.1, x, x + side * 2.2, x, x - side * 2.1]
				out += _circle(x, 18.5, 1.4, iris) + _circle(x + 0.45, 18, 0.45, "#fff")
				out += '<path d="M%s 18.8Q%s 16.2 %s 18.5" fill="none" stroke="%s" stroke-width=".85" stroke-linecap="round"/>' % [x - side * 2.2, x, x + side * 2.4, ink]
			_:
				var k := 1.15 if shape == "big" else 1.0
				out += '<ellipse cx="%s" cy="18.6" rx="%s" ry="%s" fill="#fff"/>' % [x, 1.75 * k, 2.1 * k]
				out += '<ellipse cx="%s" cy="18.75" rx="%s" ry="%s" fill="%s"/>' % [x, 1.45 * k, 1.85 * k, iris]
				if col != "":
					out += _circle(x, 18.85, 0.85, ink)
				out += _circle(x + 0.5, 18, 0.6, "#fff")
				if lash:
					out += '<path d="M%s 17.9Q%s %s %s 17.9" fill="none" stroke="%s" stroke-width=".7" stroke-linecap="round"/>' % [x - 1.75 * k, x, 16.2 - (k - 1.0) * 2.0, x + 1.75 * k, ink]
		if lash:
			out += '<path d="M%s 17.7L%s 16.9" fill="none" stroke="%s" stroke-width=".8" stroke-linecap="round"/>' % [x + side * 1.8, x + side * 2.6, ink]
		i += 1
	return out

static func _path(d: String, fill: String) -> String:
	return '<path d="%s" fill="%s"/>' % [d, fill]

static func _circle(x: float, y: float, r: float, fill: String) -> String:
	return '<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % [x, y, r, fill]

## An achievement's medal: assets/ui/medal_<id>.svg (the icon family: plum outlines, a white gloss), mipmapped.
## Without that file: the plain ribbons + disc of badgeSVG (BadgeView then draws the mark on it).
static func medal_texture(id: String) -> Texture2D:
	if ach(id).is_empty():
		return null
	var art := "res://assets/ui3d/medal_%s.webp" % id          # the 3D-rendered medal (tools/frames/ui_art.blend.py)
	if ResourceLoader.exists(art):
		if not _medals.has(id):            # kept: a texture loaded only inside _draw is freed before it is drawn (white)
			_medals[id] = load(art)
		return _medals[id]
	var path := "%smedal_%s.svg" % [UIKit.ICON_DIR, id]
	if not ResourceLoader.exists(path):
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


## The avatar tile in its frame: the tile (FRAME_TILE of the square, centred), then the frame's art over it (a child
## with the shine / twinkle shader, so the metal moves on the GPU with no redraws). Crests and wings spill outside.
class AvatarView extends Control:
	var avatar_id := Collection.DEFAULT_AVATAR
	var frame_id := Collection.DEFAULT_FRAME
	var _src := {}           # {} = the live profile
	var _art: FrameArt

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(_fit)
		_art = FrameArt.new()
		add_child(_art)

	func set_look(id: String, f: String) -> void:
		avatar_id = id if not Collection.avatar(id).is_empty() else Collection.DEFAULT_AVATAR
		frame_id = f if not Collection.frame(f).is_empty() else Collection.DEFAULT_FRAME
		_art.set_frame(frame_id)
		_fit()
		queue_redraw()

	func use_profile(p: Dictionary) -> void:
		_src = p
		refresh()

	## Re-reads the equipped avatar and frame.
	func refresh() -> void:
		set_look(Collection.equipped("avatar", _src), Collection.equipped("frame", _src))

	## The avatar tile's rect (the frame's art is FRAME_CANVAS times as wide, on the same centre).
	func tile_rect() -> Rect2:
		var side := minf(size.x, size.y) * Collection.FRAME_TILE
		return Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side))

	func _fit() -> void:
		var t := tile_rect()
		var w := t.size.x * Collection.FRAME_CANVAS
		_art.position = t.get_center() - Vector2(w, w) / 2.0
		_art.size = Vector2(w, w)

	func _draw() -> void:
		var t := tile_rect()
		if t.size.x <= 0:
			return
		draw_texture_rect(Collection.avatar_texture(avatar_id), t, false)


## A frame's rendered art with its motion: a light sweep over the metal every few seconds and twinkles on its stones
## (FRAMES.shine / .sparks). The tile under it belongs to AvatarView.
class FrameArt extends Control:
	static var _shader: Shader
	static var _tex := {}
	var _mat: ShaderMaterial

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		resized.connect(queue_redraw)

	static func texture(id: String) -> Texture2D:
		if not _tex.has(id):
			var path := "res://assets/frames/%s.webp" % id
			_tex[id] = load(path) if ResourceLoader.exists(path) else null
		return _tex[id]

	## The shine material: a light sweep of strength `shine` and twinkles at `uv_pts` (texture UVs, at most 8). `key`
	## staggers the sweep, so pieces on one screen don't flash in step. Also used by medals and nameplates.
	static func shine_material(shine: float, uv_pts: Array, key: String) -> ShaderMaterial:
		if _shader == null:
			_shader = Shader.new()
			_shader.code = SHADER
		var m := ShaderMaterial.new()
		m.shader = _shader
		var pts := PackedVector2Array()
		for p: Vector2 in uv_pts.slice(0, 8):
			pts.append(p)
		while pts.size() < 8:
			pts.append(Vector2(-9, -9))
		m.set_shader_parameter("shine", shine)
		m.set_shader_parameter("pts", pts)
		m.set_shader_parameter("n_pts", mini(uv_pts.size(), 8))
		m.set_shader_parameter("phase", float(hash(key) % 1000) / 1000.0)
		return m

	func set_frame(id: String) -> void:
		var f := Collection.frame(id)
		var shine := float(f.get("shine", 0.0))
		var sparks: Array = f.get("sparks", [])
		if shine <= 0.0 and sparks.is_empty():
			_mat = null
			material = null
		else:
			var c := Collection.FRAME_CANVAS
			var uv := []
			for sp: Array in sparks:
				uv.append(Vector2((float(sp[0]) + c) / (2.0 * c), (c - float(sp[1])) / (2.0 * c)))
			_mat = shine_material(shine, uv, id)
			material = _mat
		set_meta("frame", id)
		queue_redraw()

	func _draw() -> void:
		var t := texture(str(get_meta("frame", Collection.DEFAULT_FRAME)))
		if t:
			draw_texture_rect(t, Rect2(Vector2.ZERO, size), false)

	const SHADER := """shader_type canvas_item;
uniform float shine = 0.5;
uniform float phase = 0.0;
uniform int n_pts = 0;
uniform vec2 pts[8];
// A diagonal band of light crosses the frame in 0.9 s every 4.5 s; each stone flashes a four-point star in turn.
void fragment() {
	vec4 c = COLOR;
	float t = fract(TIME / 4.5 + phase) * 5.0;
	float d = (UV.x + UV.y) * 0.5 - (t * 1.6 - 0.3);
	float band = exp(-d * d * 900.0) * step(t, 1.0);
	c.rgb += band * shine * c.a * vec3(1.0, 0.96, 0.85);
	float s = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= n_pts) { break; }
		vec2 p = UV - pts[i];
		float tw = pow(max(0.0, sin(TIME * 1.7 + float(i) * 2.39 + phase * 6.28)), 12.0);
		float r = length(p);
		float star = 0.0022 / (abs(p.x * p.y) * 40.0 + 0.0022) * exp(-r * r * 2200.0);
		s += (star * 0.8 + exp(-r * r * 9000.0)) * tw;
	}
	c.rgb += vec3(s);
	c.a = max(c.a, clamp(s, 0.0, 1.0));
	COLOR = c;
}"""


## A medal: the medal_<id>.svg art (or, without it, the plain disc with its mark in Lilita One).
class BadgeView extends Control:
	var ach_id := ""
	## The glint on the medal's rim (texture UV): the sweep crosses the metal, the rim catches a star.
	const MEDAL_SPARK := Vector2(0.68, 0.42)

	## A 3D medal shines (light sweep + a twinkle on its rim), unless something else (the grey "not earned" look) has
	## the material.
	func _shine() -> void:
		if material == null and ach_id != "":
			material = Collection.FrameArt.shine_material(0.55, [MEDAL_SPARK], "medal:" + ach_id)

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
			if material == null and art is CompressedTexture2D:
				_shine.call_deferred()
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


## The name on its plate, the badge after the name. A plate is 3D art in three slices (assets/ui3d/plate_<id>.webp:
## 512 x 128, square caps at both ends, a centre that stretches); Plain is no plate.
class PlateView extends PanelContainer:
	## Where a plate's stones twinkle (texture UV of the 512 x 128 art: caps are the outer quarters).
	const PLATE_SPARKS := {
		scroll = [Vector2(0.06, 0.5), Vector2(0.94, 0.5)],
		crystal = [Vector2(0.11, 0.5), Vector2(0.89, 0.5), Vector2(0.15, 0.18), Vector2(0.85, 0.82)],
		neon = [Vector2(0.08, 0.2), Vector2(0.92, 0.8)],
		paint = [Vector2(0.11, 0.5), Vector2(0.89, 0.5)],
		velvet = [Vector2(0.11, 0.42), Vector2(0.89, 0.42)],
	}
	var plate_id := Collection.DEFAULT_PLATE
	var label: Label
	var badge: BadgeView
	var max_text_w := 220.0
	var _padded := true
	var _fs := 20
	static var _tex := {}

	static func art(id: String) -> Texture2D:
		if not _tex.has(id):
			var path := "res://assets/ui3d/plate_%s.webp" % id
			_tex[id] = load(path) if ResourceLoader.exists(path) else null
		return _tex[id]

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
		var col := Color(pl.text)
		label.add_theme_color_override("font_color", col)
		var plain := plate_id == Collection.DEFAULT_PLATE or art(plate_id) == null
		# a dark outline under light names on the plates (the art is busy); none on Plain or the gold plate
		var light := col.get_luminance() > 0.6
		label.add_theme_constant_override("outline_size", 0 if plain or not light else maxi(3, int(_fs / 6.0)))
		label.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.06, 0.6))
		var st := StyleBoxEmpty.new()
		if plain:
			var padx := 0.0 if not _padded else roundf(_fs * 0.6)
			st.content_margin_left = padx
			st.content_margin_right = padx if not badge.visible else roundf(padx * 0.6)
			st.content_margin_top = 0.0 if not _padded else roundf(_fs * 0.12)
			st.content_margin_bottom = st.content_margin_top
		else:
			var hh := plate_height()
			st.content_margin_left = roundf(hh * 0.62)          # inside the caps' ornaments
			st.content_margin_right = roundf(hh * (0.62 if not badge.visible else 0.5))
			st.content_margin_top = roundf((hh - _fs * 1.25) / 2.0)
			st.content_margin_bottom = st.content_margin_top
		add_theme_stylebox_override("panel", st)
		var sparks: Array = PLATE_SPARKS.get(plate_id, [])
		material = null if plain else Collection.FrameArt.shine_material(0.45, sparks, "plate:" + plate_id)
		queue_redraw()

	## A plate's height for this font size (the band holds the name, the caps stand taller). height_k: the plate's
	## height in font sizes (the Profile's big plate sets a taller one, so the band holds the name with room around it).
	var height_k := 2.1:
		set(v):
			height_k = v
			if label:
				set_look(label.text, plate_id, badge.ach_id)

	func plate_height() -> float:
		return roundf(_fs * height_k)

	func _draw() -> void:
		var t := art(plate_id)
		if plate_id == Collection.DEFAULT_PLATE or t == null or size.x < 2 or size.y < 2:
			return
		var h := size.y
		var tw := float(t.get_width())
		var th := float(t.get_height())
		var cap := th                          # square caps
		var cw := minf(h, size.x / 2.0)        # caps drawn h wide (narrower on a very short plate)
		var src_cw := cap * cw / h
		draw_texture_rect_region(t, Rect2(0, 0, cw, h), Rect2(0, 0, src_cw, th))
		draw_texture_rect_region(t, Rect2(size.x - cw, 0, cw, h), Rect2(tw - src_cw, 0, src_cw, th))
		if size.x > 2.0 * cw:
			draw_texture_rect_region(t, Rect2(cw, 0, size.x - 2.0 * cw, h), Rect2(cap, 0, tw - 2.0 * cap, th))


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
