extends SceneTree
## Dev: exports the coin economy's tables from the GDScript sources into JSON for the server (server/src/econ/).
## Run from the repo root:
##   godot --headless --path godot -s res://dev/export_catalog.gd [-- <out.json>]
## Default out: ../server/src/econ/catalog.json. A relative <out.json> is relative to the project folder (godot/).
##
## Everything is read from the game's own constants and functions, never retyped here:
##   items        Catalog.DICE, Rooms.LIST, SLScenes.LIST, Collection.CHARS / AVATARS / FRAMES / PLATES / BADGES
##   achievements Collection.ACH
##   defaults     what Save._ensure() gives a brand-new profile (starting coins, free rooms / dice, equipped items)
##   rewards      Rewards.DAILY_CYCLES / PRIZES / FREE_* / HISTORY_MAX
##   match        LudoRules / SnakesLaddersRules rewards, the XP Save.record_ludo gives, LudoMatch.NET_XP_*
##   level        the two numbers of Save.level_info (need = base + step * (level - 1))
## Item fields: {kind, id, name, price, buy (sold for coins), free (owned / usable by everyone from the start),
## default (the fallback of its kind), unlock ({level} | {ach} | null)}.
## econ_parity_dump.gd embeds build() in its fixture, so the server test notices a stale catalog.json.

const SaveScript := preload("res://scripts/core/save.gd")

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)   # on the first frame: the root is in the tree (Save's timer)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://").path_join("../server/src/econ/catalog.json").simplify_path()
	if out.is_relative_path():
		out = ProjectSettings.globalize_path("res://").path_join(out).simplify_path()   # relative to the project (godot/)
	var data := build()
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % out)
		quit(1)
		return
	f.store_string(JSON.stringify(data, "  ", false) + "\n")
	f.close()
	print("wrote %s: %d items, %d achievements" % [out, data.items.size(), data.achievements.size()])
	quit(0)


## The whole export as a Dictionary (also used by econ_parity_dump.gd).
static func build() -> Dictionary:
	var items := []
	for d: Dictionary in Catalog.DICE:
		items.append(_item("dice", d, int(d.price) > 0, d.id == Catalog.FREE_DICE, d.id == Catalog.FREE_DICE))
	for e: Dictionary in Catalog.EMOTE_PACKS:
		items.append(_item("emotes", e, int(e.price) > 0, e.id == Catalog.FREE_EMOTES, e.id == Catalog.FREE_EMOTES))
	for r: Dictionary in Rooms.LIST:
		items.append(_item("room", r, int(r.price) > 0, Catalog.FREE_ROOMS.has(r.id), r.id == Rooms.DEFAULT))
	for s: Dictionary in SLScenes.LIST:
		items.append(_item("scene", s, int(s.price) > 0, s.id == SLScenes.DEFAULT, s.id == SLScenes.DEFAULT))
	for c: Dictionary in Collection.CHARS:
		items.append(_item("char", c, int(c.price) > 0, int(c.price) <= 0, false))
	for a: Dictionary in Collection.AVATARS:
		items.append(_item("avatar", a, false, not a.has("unlock"), a.id == Collection.DEFAULT_AVATAR))
	for fr: Dictionary in Collection.FRAMES:
		items.append(_item("frame", fr, false, not fr.has("unlock"), fr.id == Collection.DEFAULT_FRAME))
	for pl: Dictionary in Collection.PLATES:
		items.append(_item("plate", pl, false, not pl.has("unlock"), pl.id == Collection.DEFAULT_PLATE))
	for b: String in Collection.BADGES:
		var it := Collection.item("badge", b)
		items.append({kind = "badge", id = b, name = str(it.get("name", b)), price = 0, buy = false, free = b == "",
			default = b == "", unlock = null if b == "" else {ach = b}})
	var achs := []
	for a: Dictionary in Collection.ACH:
		achs.append({id = a.id, name = a.name, stat = a.stat, goal = int(a.goal), reward = int(a.reward)})
	return {
		version = 1,
		source = "godot/dev/export_catalog.gd",
		items = items,
		achievements = achs,
		defaults = _defaults(),
		level = _level(),
		rewards = {
			daily_cycles = Rewards.DAILY_CYCLES.duplicate(true),
			history_max = Rewards.HISTORY_MAX,
			prizes = Rewards.PRIZES.duplicate(),
			free_every_sec = Rewards.FREE_EVERY_SEC,
			free_amount = Rewards.FREE_AMOUNT,
		},
		match = _match(),
	}

static func _item(kind: String, d: Dictionary, buy: bool, free: bool, is_default: bool) -> Dictionary:
	var u = d.get("unlock")
	var unlock = null
	if u is Dictionary:
		unlock = {level = int(u.level)} if u.has("level") else {ach = str(u.ach)}
	return {kind = kind, id = str(d.id), name = str(d.name), price = int(d.get("price", 0)), buy = buy, free = free,
		default = is_default, unlock = unlock}

## A fresh profile from Save._ensure (on a detached Save instance: nothing is read or written).
static func _fresh() -> Dictionary:
	var s: Node = SaveScript.new()
	s.profile = {}
	s.prefs = {}
	s._ensure()
	var p: Dictionary = s.profile.duplicate(true)
	s.free()
	return p

static func _defaults() -> Dictionary:
	var p := _fresh()
	var stats: Array = p.stats.keys()
	return {
		name = p.name, coins = int(p.coins), xp = int(p.xp), stats = stats,
		rooms = p.rooms, room = p.room, emote_sets = p.emote_sets, emote_set = p.emote_set, dice_owned = p.dice_owned, dice = p.dice,
		scenes = [SLScenes.DEFAULT], scene = SLScenes.DEFAULT,
		avatar = p.avatar, frame = p.frame, plate = p.plate, badge = p.badge,
		bot_levels = SaveScript.BOT_LEVELS,
	}

static func _level() -> Dictionary:
	var base := int(SaveScript.level_info(0).need)
	var step := int(SaveScript.level_info(base).need) - base
	return {base = base, step = step}

## The XP Save.record_ludo gives (run on detached Saves with a timer that never fires, so nothing is written).
static func _record_xp(players: Array, won: bool) -> int:
	var s: Node = SaveScript.new()
	s.profile = {}
	s.prefs = {}
	s._ensure()
	var holder := Node.new()
	var t := Timer.new()
	holder.add_child(t)
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	s._timer = t
	var before := int(s.profile.xp)
	s.record_ludo(players, won)
	var xp := int(s.profile.xp) - before
	s._dirty = false
	t.stop()
	holder.queue_free()
	s.free()
	return xp

static func _match() -> Dictionary:
	# loaded at run time: ludo_match.gd names the Save autoload, which a -s script can't see when it is compiled
	var net: Dictionary = (load("res://scripts/game/ludo_match.gd") as Script).get_script_constant_map()
	return {
		ludo = {
			win = LudoRules.WIN_REWARD, play = LudoRules.PLAY_REWARD,
			xp_win = _record_xp(["human", "cpu", "off", "off"], true),
			xp_loss = _record_xp(["human", "cpu", "off", "off"], false),
			xp_pp = _record_xp(["human", "human", "off", "off"], true),
		},
		sl = {win = SnakesLaddersRules.REWARD, play = SnakesLaddersRules.PLAY_REWARD, xp_win = 0, xp_loss = 0, xp_pp = 0},
		online_today = {coins_win = 0, coins_finish = 0, xp_win = int(net.NET_XP_WIN), xp_finish = int(net.NET_XP_PLAY)},
	}
