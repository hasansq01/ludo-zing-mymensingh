extends "res://tests/test_suite.gd"
## Emote sounds: all 24 files exist and load, Sound.emote is quiet for unknown ids, and the committed levels
## (tools/make_emote_sfx.py -> assets/audio/emotes/levels.json) stay at the calm tap / step level.

const IDS := ["happy", "laugh", "cool", "angry", "love", "party", "champ", "sleepy", "sob", "gasp", "confused", "hi",
		"cry", "wow", "facepalm", "cheer", "think", "tease", "dice", "crown", "highfive", "flag", "sad", "peek"]
const DIR := "res://assets/audio/emotes/"

func run() -> void:
	var bad: Array = []
	for id: String in IDS:
		var path: String = DIR + id + ".ogg"
		var s: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
		if s == null or s.get_length() < 0.25 or s.get_length() > 1.3:
			bad.append(id)
	check("emote sfx: 24 files exist, load, 0.25-1.3 s", bad.is_empty(), bad)

	var man := EmoteArt.manifest()
	var man_ids: Array = (man.get("emotes", []) as Array).map(func(e: Dictionary) -> String: return e.id)
	man_ids.sort()
	var want := IDS.duplicate()
	want.sort()
	check("emote sfx: ids match the art manifest", man_ids == want)

	var snd := Node.new()
	snd.set_script(load("res://scripts/audio/sound.gd"))
	(Engine.get_main_loop() as SceneTree).root.add_child(snd)   # a node in the tree can play; _ready runs here
	for id: String in ["", "nope", "../audio/tap", "HAPPY", "a/b", ".", "happy.ogg"]:
		snd.call("emote", id)
	check("emote sfx: unknown ids are ignored", (snd.get("_emote_pool") as Array).is_empty())
	snd.call("set_enabled", false)
	snd.call("emote", "happy")
	check("emote sfx: nothing plays with sound off", (snd.get("_emote_pool") as Array).is_empty())
	snd.call("set_enabled", true)
	for i in 6:
		snd.call("emote", "happy")
	var pool: Array = snd.get("_emote_pool")
	check("emote sfx: at most 3 overlapping", pool.size() == 3, pool.size())
	var pitches_ok := true
	for p: AudioStreamPlayer in pool:
		pitches_ok = pitches_ok and absf(p.pitch_scale - 1.0) <= 0.0301 and p.bus == "SFX"
	check("emote sfx: pitch within 3 % on the SFX bus", pitches_ok)
	snd.call("emote", "peek")
	check("emote sfx: a full pool drops the extra one", (snd.get("_emote_pool") as Array).size() == 3)
	snd.queue_free()

	var f := FileAccess.open(DIR + "levels.json", FileAccess.READ)
	check("emote sfx: levels.json present", f != null)
	if f == null:
		return
	var lv: Dictionary = JSON.parse_string(f.get_as_text())
	var em: Dictionary = lv.emotes
	var ref_rms := float(lv.ref_rms_db)
	var ref_peak := float(lv.ref_peak_db)
	var tol := float(lv.rms_tolerance_db)
	var off: Array = []
	var loud: Array = []
	for id: String in IDS:
		if not em.has(id):
			off.append(id)
			continue
		if absf(float(em[id].rms_db) - ref_rms) > tol:
			off.append(id)
		if float(em[id].peak_db) > ref_peak or float(em[id].peak_db) >= -6.0:
			loud.append(id)
	check("emote sfx: RMS within 1.5 dB of the tap / step level", off.is_empty(), off)
	check("emote sfx: no peak above the tap / step peak", loud.is_empty(), loud)
