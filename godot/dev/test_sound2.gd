extends Node
## Dev check for the Sound autoload and the recorded / mixed sound set: every effect loads (with its variation
## takes), lengths are sane, the music loops, then every effect is played once in turn and the dice / step logic is
## exercised (scheduled landing, no double landing, a new roll replaces the old one, steps stay level, soft / repeat / calm limits, takes never
## repeat back to back). Exit code 1 when anything fails.
## Run: godot --headless --path godot res://dev/test_sound2.tscn      (add --audio-driver CoreAudio to listen)

const MIN_TAKES := {roll = 4, land = 4, step = 4, capture = 2, coin = 2}

var fails := 0


func check(what: String, ok: bool, info: Variant = "") -> void:
	if not ok:
		fails += 1
		print("FAIL ", what, " ", info)


func playing(name: String) -> int:
	return Sound._count_playing([name])


func stop_all() -> void:
	for p: AudioStreamPlayer in Sound._pool:
		p.stop()


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _ready() -> void:
	var keep := [Sound.enabled, Sound.master_volume, Sound.music_volume, Sound.effects_volume]
	check("calm default volumes", Sound.DEFAULT_MASTER == 70 and Sound.DEFAULT_MUSIC == 35 and Sound.DEFAULT_EFFECTS == 60)
	check("at most 4 effect voices", Sound._pool.size() == 4, Sound._pool.size())
	var has_lp := false
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectLowPassFilter:
			has_lp = true
	check("master low-pass", has_lp)
	Sound.set_enabled(true)
	Sound.set_volumes(70, 35, 60)
	# ---- files ----
	for n: String in Sound.EFFECTS:
		var takes: Array = Sound._takes.get(n, [])
		check("loads " + n, takes.size() >= int(MIN_TAKES.get(n, 1)), takes.size())
		for s: AudioStream in takes:
			var l := s.get_length()
			check("length %s %s" % [n, s.resource_path], l > 0.01 and l < 2.5, l)
		print("%-9s %d take(s)  %s" % [n, takes.size(), ", ".join(takes.map(func(s): return "%.2fs" % s.get_length()))])
	var m: AudioStream = Sound._music.stream
	check("music loads", m != null)
	if m is AudioStreamOggVorbis:
		check("music loops", (m as AudioStreamOggVorbis).loop)
	check("music length >= 90 s", m != null and m.get_length() >= 90.0, m.get_length() if m else 0)
	print("music %.1f s %s" % [m.get_length() if m else 0.0, m.get_class() if m else ""])
	# ---- non-repeating takes ----
	var last := -1
	var repeats := 0
	var seen := {}
	for i in 200:
		var k: int = Sound._pick("land", 5)
		if k == last:
			repeats += 1
		last = k
		seen[k] = true
	check("takes never repeat back to back", repeats == 0, repeats)
	check("every take gets played", seen.size() == 5, seen.keys())
	# ---- every effect, one after the other ----
	for n: String in Sound.EFFECTS:
		stop_all()
		var before := Time.get_ticks_msec()
		Sound.sfx(n, 750 if n == "coin_big" else null)
		check("plays " + n, int(Sound._last_at.get(n, -1)) >= before)
		await wait(0.15)
	Sound.sfx("coin", 900)
	await wait(0.02)
	check("coin 900 plays the big coin", playing("coin_big") >= 1)
	Sound.sfx("nope")   # unknown names are ignored
	await wait(1.0)
	# ---- dice: scheduled landing ----
	Sound.sfx("roll", 0.75)
	await wait(0.03)
	check("roll plays", playing("roll") == 1)
	check("no landing yet", playing("land") == 0)
	await wait(0.6)    # impact at 0.6 x 0.75 = 0.45 s
	check("landing played on the impact", playing("land") == 1)
	check("rattle cut by the landing", playing("roll") == 0)
	var at: int = Sound._last_at.get("land", 0)
	Sound.sfx("land")  # the caller's own landing at the end of the roll: skipped
	await wait(0.02)
	check("no double landing", int(Sound._last_at.get("land", 0)) == at)
	await wait(0.6)
	# old behaviour: no duration -> "land" plays when called
	Sound.sfx("roll")
	await wait(0.3)
	check("no scheduled landing without a duration", playing("land") == 0)
	Sound.sfx("land")
	await wait(0.02)
	check("land on call", playing("land") == 1)
	await wait(0.6)
	# caller lands before the schedule: plays once, now
	Sound.sfx("roll", 2.0)
	await wait(0.2)
	Sound.sfx("land")
	await wait(0.02)
	at = Sound._last_at.get("land", 0)
	check("early land plays", playing("land") == 1)
	await wait(1.3)
	check("schedule cancelled by the early land", int(Sound._last_at.get("land", 0)) == at)
	# a new roll replaces the old one
	Sound.sfx("roll")
	await wait(0.15)
	Sound.sfx("roll")
	await wait(0.02)
	check("one rattle at a time", playing("roll") == 1)
	# disabling cancels a pending landing
	Sound.sfx("roll", 0.5)
	Sound.set_enabled(false)
	Sound.set_enabled(true)
	await wait(0.5)
	check("disable cancels the landing", playing("land") == 0)
	await wait(0.5)
	# ---- steps: level (no rising pitch), at most 2 at once ----
	var pitches := []
	for i in 6:
		Sound.sfx("step", i + 3)
		var newest: AudioStreamPlayer = null
		for p: AudioStreamPlayer in Sound._pool:
			if p.playing and Sound._voice_name.get(p, "") == "step":
				if newest == null or int(Sound._voice_started[p]) >= int(Sound._voice_started[newest]):
					newest = p
		pitches.append(newest.pitch_scale if newest else 0.0)
		await wait(0.11)
	check("every step plays at 0.11 s", not 0.0 in pitches, pitches)
	check("steps stay level", pitches.all(func(x): return absf(x - 1.0) <= 0.021), pitches)
	check("at most 2 step voices", playing("step") <= 2)
	# ---- calm limits ----
	stop_all()
	await wait(0.2)
	var t0: int = Sound._last_at.get("capture", 0)
	Sound.sfx("capture")
	var t1: int = Sound._last_at.get("capture", 0)
	Sound.sfx("capture")   # within 120 ms: skipped
	check("same sound within 120 ms skipped", int(Sound._last_at.get("capture", 0)) == t1 and t1 != t0)
	await wait(0.4)
	stop_all()
	await wait(0.2)
	Sound.sfx("win", {soft = true})
	var loud := 0.0
	for p: AudioStreamPlayer in Sound._pool:
		if p.playing and Sound._voice_name.get(p, "") == "win":
			loud = p.volume_db
	check("soft plays 6 dB down", loud <= -5.9 and loud >= -6.1, loud)
	stop_all()
	await wait(0.2)
	Sound.sfx("six")
	await wait(0.3)
	stop_all()
	Sound.sfx("six")       # again within 12 s: a little softer
	var six_db := 0.0
	for p: AudioStreamPlayer in Sound._pool:
		if p.playing and Sound._voice_name.get(p, "") == "six":
			six_db = p.volume_db
	check("repeated six is softer", six_db <= -3.9, six_db)
	stop_all()
	for n in ["capture", "win", "home", "lose", "buy", "pair", "snake"]:
		Sound.sfx(n)
	check("never more than 4 effects", Sound._pool.filter(func(p): return p.playing).size() <= 4)
	await wait(0.3)
	# ---- api ----
	Sound.play_music(true)
	await wait(0.1)
	Sound.set_app_paused(true)
	Sound.set_app_paused(false)
	Sound.play_music(false)
	Sound.set_volumes(150, -5, 85)
	check("clamp", Sound.master_volume == 100 and Sound.music_volume == 0)
	print("peak ", Sound.peak())
	Sound.set_enabled(false)   # stop every voice and let the audio server drop the playbacks before quitting
	await wait(0.3)
	Sound.set_enabled(keep[0])
	Sound.set_volumes(keep[1], keep[2], keep[3])
	print("test_sound2: ", "OK" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit(1 if fails else 0)
