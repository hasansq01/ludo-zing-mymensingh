extends "res://tests/test_suite.gd"
## Save._ensure() fills the new preferences without overwriting saved ones, and Save.reset_progress() starts a
## fresh profile but keeps the sound settings. Runs on a detached Save instance (never the real user://save.json).

const SaveScript := preload("res://scripts/core/save.gd")

func fresh_save(profile: Dictionary, prefs: Dictionary) -> Node:
	var sv: Node = SaveScript.new()                # not added to the tree: no _ready, no file load or write
	sv.profile = profile
	sv.prefs = prefs
	sv._ensure()
	return sv

func run() -> void:
	# ---- calmer audio migration, then the master level folded into the channels (no master slider) ----
	var old_sv := fresh_save({}, {vol = {master = 80, music = 50, sfx = 85}})
	check("player on the old default volumes moves to the calm ones (then folded: 70 x 35 / 60)", old_sv.prefs.vol.master == 100 and old_sv.prefs.vol.music == 25 and old_sv.prefs.vol.sfx == 42 and old_sv.prefs.audio_v2, old_sv.prefs.vol)
	var own_sv := fresh_save({}, {vol = {master = 90, music = 20, sfx = 85}})
	check("player with their own volumes keeps their loudness (master folded in)", own_sv.prefs.vol.master == 100 and own_sv.prefs.vol.music == 18 and own_sv.prefs.vol.sfx == 77, own_sv.prefs.vol)
	var done_sv := fresh_save({}, {vol = {master = 80, music = 50, sfx = 85}, audio_v2 = true})
	check("the calm migration runs only once", done_sv.prefs.vol.music == 40 and done_sv.prefs.vol.sfx == 68, done_sv.prefs.vol)
	var gain := func(v: float) -> float: return pow(v / 100.0, 1.5)
	var fold := {master = 64, music = 75, sfx = 50}
	SaveScript.fold_master(fold)
	check("folding keeps each channel's loudness (gain of master x channel)", fold.master == 100 and absf(gain.call(fold.music) - gain.call(64) * gain.call(75)) < 0.01
		and absf(gain.call(fold.sfx) - gain.call(64) * gain.call(50)) < 0.01, fold)
	var again := fold.duplicate()
	SaveScript.fold_master(again)
	check("folding twice changes nothing", again == fold, again)
	var quiet := {master = 5, music = 5, sfx = 0}
	SaveScript.fold_master(quiet)
	check("a quiet channel that was on stays on; a muted one stays muted", quiet.music == 1 and quiet.sfx == 0 and quiet.master == 100, quiet)

	# ---- a brand-new player ----
	var sv := fresh_save({}, {})
	var pr: Dictionary = sv.prefs
	check("new player: vibrate on", pr.vibrate == true)
	check("new player: Relaxed speed (1.0)", is_equal_approx(pr.speed, 1.0), pr.speed)
	check("new player: both house rules on", pr.sl_need_one == true and pr.pair_ask == true)
	check("new player: Top camera for Ludo and Snakes & Ladders", pr.cam == "top" and pr.sl_cam == "top", [pr.cam, pr.sl_cam])
	check("new player: normal bots", pr.bot_level == "normal")
	check("new player: colour-blind symbols and reduced motion off", pr.colorblind == false and pr.reduce_motion == false)
	check("new player: welcome and tutorial not seen", pr.welcome_seen == false and pr.tutorial_done == false)
	check("new player: no last setup", pr.last_setup is Dictionary and pr.last_setup.is_empty())
	check("new player: the old prefs still filled", pr.sound == true)
	check("new player: calm volume defaults (master 100, music 25, effects 42)", pr.vol.master == 100 and pr.vol.music == 25 and pr.vol.sfx == 42, pr.vol)
	check("Sound's defaults match Save's", load("res://scripts/audio/sound.gd").DEFAULT_MASTER == 100 and load("res://scripts/audio/sound.gd").DEFAULT_MUSIC == 25 and load("res://scripts/audio/sound.gd").DEFAULT_EFFECTS == 42)
	check("prefs are JSON-safe", JSON.parse_string(JSON.stringify(pr)).size() == pr.size())
	sv.free()

	# ---- an existing player (has an id), who never saved a speed and has played ----
	var old_profile := {id = "LZM-ABCD-EFGH", name = "You", coins = 300, stats = {played = 3}}
	sv = fresh_save(old_profile, {sound = false})
	pr = sv.prefs
	check("existing player without a saved speed keeps Normal (1.0)", is_equal_approx(pr.speed, 1.0), pr.speed)
	check("existing player who played: welcome and tutorial count as seen", pr.welcome_seen == true and pr.tutorial_done == true)
	check("existing values kept: sound off, coins", pr.sound == false and sv.profile.coins == 300)
	sv.free()
	sv = fresh_save({id = "LZM-ABCD-EFGH", name = "Shihab"}, {speed = 0.55})
	check("existing player with a custom name has seen the welcome, not the tutorial", sv.prefs.welcome_seen == true and sv.prefs.tutorial_done == false)
	check("a save from before the 2026-10-24 defaults gets them once (Relaxed)", is_equal_approx(sv.prefs.speed, 1.0), sv.prefs.speed)
	sv.free()
	sv = fresh_save({id = "LZM-ABCD-EFGH", name = "Shihab"},
		{defaults_v3 = true, speed = 0.55, cam = "3d", sl_cam = "3d", pair_ask = false, sl_need_one = false})
	check("choices made after the new defaults stay (Fast, 3D, house rules off)", is_equal_approx(sv.prefs.speed, 0.55)
		and sv.prefs.cam == "3d" and sv.prefs.sl_cam == "3d" and sv.prefs.pair_ask == false and sv.prefs.sl_need_one == false, sv.prefs)
	sv.free()
	sv = fresh_save({id = "LZM-ABCD-EFGH", name = "You"}, {})
	check("existing player, no games, default name: welcome not seen", sv.prefs.welcome_seen == false and sv.prefs.tutorial_done == false)
	sv.free()
	sv = fresh_save({id = "X"}, {speed = 1.0, vibrate = false, sl_need_one = true, pair_ask = true, bot_level = "hard",
		colorblind = true, reduce_motion = true, welcome_seen = false, tutorial_done = true, last_setup = {ludo = {n = 2}}})
	pr = sv.prefs
	check("saved prefs are never overwritten", pr.speed == 1.0 and pr.vibrate == false and pr.sl_need_one and pr.pair_ask and pr.bot_level == "hard"
		and pr.colorblind and pr.reduce_motion and pr.welcome_seen == false and pr.tutorial_done and pr.last_setup.ludo.n == 2, pr)
	sv.free()
	sv = fresh_save({id = "X"}, {bot_level = "insane", last_setup = "junk", vibrate = 0})
	check("bad values are repaired", sv.prefs.bot_level == "normal" and sv.prefs.last_setup is Dictionary and sv.prefs.vibrate == false, sv.prefs)
	sv.free()

	# ---- reset progress ----
	sv = fresh_save({id = "LZM-ABCD-EFGH", name = "Shihab", coins = 99999, xp = 900, stats = {played = 12, wins = 7}, rooms = ["night", "cafe", "rooftop"]},
		{sound = false, vol = {master = 20, music = 10, sfx = 30}, speed = 1.0, pair_ask = true, bot_level = "hard", welcome_seen = true, tutorial_done = true, info = {pair = 3}})
	var changed := [0]
	sv.changed.connect(func(): changed[0] += 1)
	sv.reset_progress()
	var p: Dictionary = sv.profile
	pr = sv.prefs
	check("reset: fresh profile (coins, XP, stats, name, rooms)", p.coins == 5000 and p.xp == 0 and p.stats.played == 0 and p.stats.wins == 0 and p.name == "You" and p.rooms == ["night", "cafe"], p)
	check("reset: a new player ID", p.id is String and p.id.begins_with("LZM-") and p.id != "LZM-ABCD-EFGH")
	check("reset: sound switch and volumes kept (20 x 10 / 30 folded)", pr.sound == false and pr.vol.master == 100 and pr.vol.music == 2 and pr.vol.sfx == 6, pr.vol)
	check("reset: other prefs back to defaults (Relaxed, house rules on, Top cameras, normal bots, first-run flags off)", is_equal_approx(pr.speed, 1.0) and pr.pair_ask == true and pr.sl_need_one == true and pr.cam == "top"
		and pr.bot_level == "normal" and pr.welcome_seen == false and pr.tutorial_done == false and not pr.has("info"), pr)
	check("reset: changed is emitted", changed[0] == 1)
	sv.free()
