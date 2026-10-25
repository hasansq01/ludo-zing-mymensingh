extends Node
## Autoload "Save": the player's profile and preferences, kept in user://save.json (index.html: P, prefs, Store,
## ensureProfile, recordResult, levelInfo). Writes are debounced; the file is replaced atomically so a crash
## mid-write never loses progress.

signal changed                          # coins, XP or stats changed (the HUD re-renders)

const PATH := "user://save.json"
const VERSION := 1

var profile := {}
var prefs := {}
var _dirty := false
var _timer: Timer

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.4
	_timer.timeout.connect(flush)
	add_child(_timer)
	load_data()

func load_data() -> void:
	var data := {}
	if FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			data = parsed
	profile = data.get("profile", {}) if data.get("profile") is Dictionary else {}
	prefs = data.get("prefs", {}) if data.get("prefs") is Dictionary else {}
	_ensure()

const BOT_LEVELS := ["easy", "normal", "hard"]
const NOTIF_KEYS := ["notif", "notif_rewards", "notif_reminders", "notif_game", "notif_offers"]

## Fill only missing fields, never overwrite saved ones.
func _ensure() -> void:
	var p := profile
	var fresh := not p.has("id")              # a profile created now (first launch, or after reset_progress)
	if not p.get("name") is String or (p.name as String).strip_edges() == "":
		p.name = "You"
	if not p.has("id"):
		var abc := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
		var s := ""
		for k in 8:
			s += abc[randi() % abc.length()]
		p.id = "LZM-%s-%s" % [s.substr(0, 4), s.substr(4, 4)]
	p.coins = maxi(0, as_int(p.get("coins"), 5000))      # null / text / negative in a damaged save: never a crash
	p.xp = maxi(0, as_int(p.get("xp"), 0))
	var st: Dictionary = p.get("stats", {}) if p.get("stats") is Dictionary else {}
	for k in ["played", "wins", "losses", "streak", "bestStreak", "coinsEarned", "pairsFormed", "ppGames", "slPlayed", "slWins"]:
		st[k] = maxi(0, as_int(st.get(k), 0))
	p.stats = st
	# owned rooms (free ones always), the equipped room; owned dice skins, the equipped skin
	var rooms: Array = p.get("rooms", []) if p.get("rooms") is Array else []
	for free in ["night", "cafe"]:
		if not rooms.has(free):
			rooms.append(free)
	p.rooms = rooms
	if not p.get("room") is String or not rooms.has(p.room):
		p.room = "night"
	var dice: Array = p.get("dice_owned", []) if p.get("dice_owned") is Array else []
	if not dice.has("classic"):
		dice.insert(0, "classic")
	p.dice_owned = dice
	if not p.get("dice") is String or not dice.has(p.dice):
		p.dice = "classic"
	# emote packs (Catalog.EMOTE_PACKS): owned ids (Starter always, first), the equipped pack
	var emo: Array = p.get("emote_sets", []) if p.get("emote_sets") is Array else []
	if not emo.has("starter"):
		emo.insert(0, "starter")
	p.emote_sets = emo
	if not p.get("emote_set") is String or not emo.has(p.emote_set):
		p.emote_set = "starter"
	# rewards: daily calendar state, last spin day, last free-coins claim (unix seconds)
	if not p.get("daily") is Dictionary:
		p.daily = {}
	if not p.get("last_spin") is String:
		p.last_spin = ""
	p.last_free = maxi(0, as_int(p.get("last_free"), 0))
	# collection (Collection): equipped avatar / frame / nameplate / badge, bought characters, claimed achievements.
	# Only missing or wrongly typed fields are filled; Collection.equipped() falls back when a saved one is locked.
	if not p.get("avatar") is String or p.avatar == "":
		p.avatar = "pawn-red"
	if not p.get("av_owned") is Array:
		p.av_owned = []
	if not p.get("frame") is String or p.frame == "":
		p.frame = "classic"
	if not p.get("plate") is String or p.plate == "":
		p.plate = "plain"
	if not p.get("badge") is String:
		p.badge = ""
	if not p.get("claimed") is Array:
		p.claimed = []
	var pr := prefs
	pr.sound = bool(pr.get("sound", true))
	var vol: Dictionary = pr.get("vol", {}) if pr.get("vol") is Dictionary else {}
	vol.master = clampi(as_int(vol.get("master"), 70), 0, 100)
	vol.music = clampi(as_int(vol.get("music"), 35), 0, 100)
	vol.sfx = clampi(as_int(vol.get("sfx"), 60), 0, 100)
	# calmer audio (2026-10-24): players still on the old defaults (80 / 50 / 85, sliders never moved) get the new
	# quieter ones once; anyone who set their own levels keeps them
	if not pr.get("audio_v2", false):
		if vol.master == 80 and vol.music == 50 and vol.sfx == 85:
			vol.master = 70; vol.music = 35; vol.sfx = 60
		pr.audio_v2 = true
	fold_master(vol)
	pr.vol = vol
	# defaults (user's call, 2026-10-24): Relaxed speed, Top camera for both games, both house rules on. Saves from
	# before then get them once (nothing has shipped yet); later changes in Settings are kept.
	if not pr.get("defaults_v3", false):
		for k in ["speed", "cam", "sl_cam", "sl_need_one", "pair_ask"]:
			pr.erase(k)
		pr.defaults_v3 = true
	pr.speed = 0.55 if (pr.get("speed") is float or pr.get("speed") is int) and float(pr.get("speed")) < 0.8 else 1.0   # 1.0 Relaxed, 0.55 Fast
	pr.cam = "3d" if pr.get("cam", "top") == "3d" else "top"
	pr.sl_cam = "3d" if pr.get("sl_cam", "top") == "3d" else "top"
	pr.last_players = pr.get("last_players", ["human", "cpu", "cpu", "cpu"])
	pr.vibrate = bool(pr.get("vibrate", true))
	pr.sl_need_one = bool(pr.get("sl_need_one", true))       # Snakes & Ladders house rule "Need a 1 to start"
	pr.pair_ask = bool(pr.get("pair_ask", true))             # Ludo house rule "Ask before pairing"
	pr.bot_level = str(pr.get("bot_level")) if BOT_LEVELS.has(pr.get("bot_level")) else "normal"   # computer skill
	pr.colorblind = bool(pr.get("colorblind", false))
	pr.reduce_motion = bool(pr.get("reduce_motion", false))
	for k in NOTIF_KEYS:                       # Notifications: the master switch and the four kinds, all on until changed
		pr[k] = pr[k] if pr.get(k) is bool else true
	pr.notif_asked = maxi(0, as_int(pr.get("notif_asked"), 0))         # how often the soft permission prompt was shown
	pr.notif_asked_at = maxi(0, as_int(pr.get("notif_asked_at"), 0))   # ... and when last (unix seconds)
	if not pr.get("last_setup") is Dictionary:
		pr.last_setup = {}                     # the last game setup per game ({ludo: {...}, sl: {...}})
	# first-run flags: a player who has already played (or named themselves) has seen the welcome / basics
	var played: bool = st.played + st.ppGames + st.slPlayed > 0
	if not pr.has("welcome_seen"):
		pr.welcome_seen = not fresh and (played or p.name != "You")
	pr.welcome_seen = bool(pr.welcome_seen)
	if not pr.has("tutorial_done"):
		pr.tutorial_done = played
	pr.tutorial_done = bool(pr.tutorial_done)

## A number from a save (JSON gives floats; a damaged file can hold null, text, a list): an int, else `dflt`.
static func as_int(v: Variant, dflt := 0) -> int:
	if v is int:
		return v
	if v is float:
		return dflt if is_nan(v) or is_inf(v) else int(v)
	if v is String and (v as String).strip_edges().is_valid_int():
		return int((v as String).strip_edges())
	return dflt

## Re-checks the profile and preferences (fills what is missing, repairs what is damaged). Account calls it after
## it wrote a server profile into Save.profile.
func normalize() -> void:
	_ensure()

## Settings has no master Volume slider any more (re-audit #40): the master level is folded into the two channels
## once, so nothing sounds louder or quieter. Each slider maps to gain (v / 100) ^ 1.5 (Sound._curve), so
## master x channel / 100 keeps the product of the two gains exactly; master becomes 100. A channel that was on
## never folds to 0 (muted). Safe to call again: with master at 100 it changes nothing.
static func fold_master(vol: Dictionary) -> void:
	var m := as_int(vol.get("master"), 100)
	if m >= 100:
		vol.master = 100
		return
	for k in ["music", "sfx"]:
		var c := as_int(vol.get(k), 0)
		vol[k] = 0 if c <= 0 else clampi(roundi(c * m / 100.0), 1, 100)
	vol.master = 100

## Settings "Reset progress": a brand-new profile (coins, XP, stats, items, rewards, a new player ID) and default
## preferences, except the sound switch, volumes and notification choices, which are kept. Saved at once.
func reset_progress() -> void:
	var keep := {}
	for k in ["sound", "vol", "notif_asked", "notif_asked_at"] + NOTIF_KEYS:
		if prefs.has(k):
			keep[k] = prefs[k]
	profile = {}
	prefs = keep
	_ensure()
	if _timer != null:
		save()
	changed.emit()

func save() -> void:
	_dirty = true
	_timer.start()

func flush() -> void:
	if not _dirty:
		return
	_dirty = false
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Save: can't write %s (%d)" % [tmp, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify({v = VERSION, profile = profile, prefs = prefs}))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PATH))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		flush()


# ---------- progress ----------

func add_coins(n: int) -> void:
	profile.coins = maxi(0, int(profile.coins) + n)
	if n > 0:
		profile.stats.coinsEarned += n
	save()
	changed.emit()

## Level n needs 100 + 50·(n−1) XP to reach n+1.
static func level_info(xp: int) -> Dictionary:
	var level := 1
	var need := 100
	while xp >= need:
		xp -= need
		level += 1
		need = 100 + (level - 1) * 50
	return {level = level, into = xp, need = need}

## A finished Ludo game (index.html recordResult): vs Computer with one human counts wins / losses / streaks;
## Pass & Play counts games together.
func record_ludo(players: Array, human_won: bool) -> void:
	var st: Dictionary = profile.stats
	var humans := players.count("human")
	if humans == 1 and players.has("cpu"):
		st.played += 1
		if human_won:
			st.wins += 1; st.streak += 1; st.bestStreak = maxi(st.bestStreak, st.streak); profile.xp += 100
		else:
			st.losses += 1; st.streak = 0; profile.xp += 40
	elif humans > 1:
		st.ppGames += 1; profile.xp += 30
	save()
	changed.emit()

func record_sl(won_vs_cpu: bool) -> void:
	var st: Dictionary = profile.stats
	st.slPlayed += 1
	if won_vs_cpu:
		st.slWins += 1
	save()
	changed.emit()
