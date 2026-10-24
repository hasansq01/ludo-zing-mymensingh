extends Node
## Sound (autoload "Sound"): the game's effects and music, voiced to stay comfortable over long sessions.
##
## Files: res://assets/audio/<name>.wav|.ogg, or a variation set <name>_1, <name>_2, ... (built by
## tools/mix_audio.py from recorded CC0 foley and the synth stems of tools/gen_audio.gd; see assets/audio/CREDITS.md).
## The files are already quiet and warm (peaks at or below -6 dBFS, UI and steps far lower, everything low-passed).
## A set plays a random take, never the same one twice in a row, with a little pitch / gain jitter so repeats don't
## sound copied. Musical stings (six, home, win, ...) are tuned to the music and play without pitch jitter.
##
## sfx(name, arg): `arg` is a number (old callers) or a Dictionary of options:
##   soft = true   a quieter take (SOFT_DB): use it for the computer's turns, so only the player's own actions are
##                 at full level. Example: Sound.sfx("roll", {dur = 0.41, soft = true}).
##   dur = sec     "roll" only: the roll's duration. The landing clack is then scheduled at IMPACT_AT of it, which is
##                 when the die first hits the table in dice_3d.gd, and the caller's own sfx("land") right after is
##                 skipped. Without it, "land" plays when it is called. A landing cuts a still-ringing rattle short.
##   amount = n    "coin" only: 500+ plays the big coin.
## A plain number still means dur for "roll", amount for "coin" and is ignored for "step" (old square number).
##
## Calm safety: at most MAX_VOICES effects at once (win / lose / home / capture / land may take the oldest of the
## others), the same sound at most once per GAP (120 ms; steps 100 ms), and a cue repeated within REPEAT_MS plays a
## few dB softer (REPEAT_SOFT), so the extra-roll / coin chimes don't hammer the same note every turn.
##
## Buses (made in code): "SFX" and "Music" both send to "Master", which carries a gentle low-pass (MASTER_LP_HZ) so
## nothing is piercing, and a safety hard limiter at -1 dBFS that the quiet levels never reach in practice. Music
## fades in over MUSIC_FADE_IN and ducks DUCK_DB under board / reward effects. Each slider (0-100) maps to gain as
## (v / 100) ^ 1.5, so the low end stays useful. The app going to the background (set_app_paused, or the OS
## notification) silences everything.

const EFFECTS := ["tap", "select", "roll", "land", "step", "six", "capture", "pair", "split", "coin", "coin_big",
		"buy", "home", "ladder", "snake", "win", "lose", "error", "tick"]
const AUDIO_DIR := "res://assets/audio/"
const MAX_TAKES := 9
## Default slider values for a new player (Save's `vol` defaults fold to these: master 70 x music 35 / effects 60,
## the calm 2026-10 levels, became music 25 / effects 42 with the master at 100; Settings has no master slider).
const DEFAULT_MASTER := 100
const DEFAULT_MUSIC := 25
const DEFAULT_EFFECTS := 42
const GAP := {step = 100, error = 250}   # ms between two plays of the same sound
const DEFAULT_GAP := 120
const MAX_VOICES := 4
## Voices one effect may hold at once. RESTART effects stop their own oldest voice to play again (a new roll
## replaces the old one); the others are skipped when full.
const VOICES := {step = 2, coin = 1, coin_big = 1}
const DEFAULT_VOICES := 1
const RESTART := ["roll", "land", "step", "tap", "tick", "select"]
const BIG_COIN := 500
const PRIORITY := ["win", "lose", "home", "capture", "land"]   # may take the oldest voice of another sound
const SOFT_DB := -6.0
const REPEAT_MS := 12000
const REPEAT_SOFT := {six = 4.0, coin = 2.0, coin_big = 2.0, select = 2.0, pair = 2.0, split = 2.0, ladder = 2.0,
		snake = 2.0, home = 2.0}
## Random pitch spread (fraction) and gain spread (dB, downwards) per take. Tuned stings have none.
const PITCH_JITTER := {roll = 0.03, land = 0.03, capture = 0.03, step = 0.02, tap = 0.02, tick = 0.02}
const GAIN_JITTER := {roll = 1.0, land = 1.0, step = 2.0, capture = 0.8, tap = 0.8}
const IMPACT_AT := 0.6       # dice_3d._roll_step: the die first lands at 60 % of the roll
const AUTO_LAND_HOLD := 900  # ms after a scheduled landing during which the caller's own "land" is skipped
const ROLL_CUT := 0.06       # s: fade of a rattle that is still ringing when the die lands
const MUSIC_FADE_IN := 2.0   # s
const MUSIC_FADE_OUT := 0.8  # s
const DUCK_DB := -3.0
const DUCK_ATTACK := 0.15    # s to go fully down
const DUCK_RELEASE := 0.8    # s to come back up
const NO_DUCK := ["tap", "tick", "step", "select"]
const MASTER_LP_HZ := 7000.0
const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"

var enabled := true
var master_volume := DEFAULT_MASTER
var music_volume := DEFAULT_MUSIC
var effects_volume := DEFAULT_EFFECTS

var _takes: Dictionary = {}            # effect name -> Array of AudioStream (one or more takes)
var _last_take: Dictionary = {}        # effect name -> index played last
var _pool: Array[AudioStreamPlayer] = []
var _voice_name: Dictionary = {}       # player -> effect name it is playing
var _voice_started: Dictionary = {}    # player -> ticks msec when it started
var _voice_tween: Dictionary = {}      # player -> Tween fading it out
var _last_at: Dictionary = {}          # effect name -> ticks msec of its last play
var _land_token := 0                   # bumps to cancel a scheduled landing
var _land_pending := false             # a scheduled landing is still waiting
var _land_soft := false                # ... and whether it is a soft one
var _auto_land_at := -100000           # ticks msec of the last scheduled landing that played
var _music: AudioStreamPlayer
var _music_wanted := false
var _music_on := false
var _music_gain := 0.0
var _music_pos := 0.0
var _music_tween: Tween
var _duck := 0.0                       # current music duck, dB (0 or down to DUCK_DB)
var _app_paused := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps playing (and fading) while the game tree is paused
	_rng.randomize()
	_setup_buses()
	for n: String in EFFECTS:
		var takes := _load_takes(n)
		if takes.is_empty():
			push_warning("Sound: missing %s" % n)
		else:
			_takes[n] = takes
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	_music.volume_db = linear_to_db(0.0001)
	_music.stream = _load_music()
	if _music.stream == null:
		push_warning("Sound: missing music")
	add_child(_music)
	_apply_levels()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		set_app_paused(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		set_app_paused(false)


func _process(delta: float) -> void:
	if not _music.playing:
		_duck = 0.0
		return
	var busy := false
	for p in _pool:
		if p.playing and not _voice_name.get(p, "") in NO_DUCK:
			busy = true
			break
	var target := DUCK_DB if busy else 0.0
	var rate := absf(DUCK_DB) / (DUCK_ATTACK if target < _duck else DUCK_RELEASE)
	var d := move_toward(_duck, target, rate * delta)
	if d != _duck:
		_duck = d
		_set_music_gain(_music_gain)


# ---------- public API ----------

## Plays a named effect (see EFFECTS); `arg` as described in the header (a number, or {soft, dur, amount}).
func sfx(name: String, arg: Variant = null) -> void:
	if not enabled or _app_paused or effects_volume <= 0 or master_volume <= 0:
		return
	var o := _opts(name, arg)
	var soft := bool(o.get("soft", false))
	var now := Time.get_ticks_msec()
	if name == "land":
		if _land_pending:
			_cancel_land()     # the caller landed before the schedule did: play it now, once
		elif now - _auto_land_at < AUTO_LAND_HOLD:
			return             # already played on the impact
	elif name == "roll":
		_cancel_land()
		_auto_land_at = -100000
		if float(o.get("dur", 0.0)) > 0.0:
			_schedule_land(float(o.dur) * IMPACT_AT, soft)
	_play(name, o, soft, now)


## Sound on / off (the Settings switch). Off silences effects and music at once; music comes back if it was wanted.
func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		_cancel_land()
		for p in _pool:
			p.stop()
	_apply_levels()


## Slider values 0-100 (defaults DEFAULT_MASTER / DEFAULT_MUSIC / DEFAULT_EFFECTS = 100 / 25 / 42).
func set_volumes(master: int, music: int, effects: int) -> void:
	master_volume = clampi(master, 0, 100)
	music_volume = clampi(music, 0, 100)
	effects_volume = clampi(effects, 0, 100)
	_apply_levels()


## Starts / stops the music loop (fades in over MUSIC_FADE_IN, out over MUSIC_FADE_OUT). Plays only while sound is
## enabled, the app is in the foreground and the music and master sliders are above 0.
func play_music(on: bool) -> void:
	_music_wanted = on
	_sync_music()


## The app went to the background (true) or came back (false): silence everything at once / restore it.
func set_app_paused(paused: bool) -> void:
	if paused == _app_paused:
		return
	_app_paused = paused
	if paused:
		_cancel_land()
	if paused and _music_on:
		if _music_tween:
			_music_tween.kill()
		_music_on = false
		_music.stream_paused = true
		_set_music_gain(0.0)   # fades back in on resume
	_apply_levels()


## Loudest level leaving the Master bus right now (0..1), for tests and meters.
func peak() -> float:
	var l := AudioServer.get_bus_peak_volume_left_db(0, 0)
	var r := AudioServer.get_bus_peak_volume_right_db(0, 0)
	return db_to_linear(maxf(l, r))


## Number of takes loaded for an effect (0 when missing), for tests.
func takes(name: String) -> int:
	return (_takes.get(name, []) as Array).size()


# ---------- internals ----------

static func _num(v: Variant) -> float:
	return float(v) if v is int or v is float else 0.0


## The options Dictionary for any `arg`: Dictionaries pass through; an old plain number becomes dur / amount.
static func _opts(name: String, arg: Variant) -> Dictionary:
	if arg is Dictionary:
		return arg
	if arg is int or arg is float:
		if name == "roll":
			return {dur = float(arg)}
		if name == "coin":
			return {amount = float(arg)}
	return {}


static func _curve(v: int) -> float:
	return pow(v / 100.0, 1.5)


static func _find(base: String) -> AudioStream:
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(AUDIO_DIR + base + ext):
			return load(AUDIO_DIR + base + ext) as AudioStream
	return null


static func _load_takes(n: String) -> Array:
	var out := []
	var one := _find(n)
	if one:
		out.append(one)
	for i in range(1, MAX_TAKES + 1):
		var s := _find("%s_%d" % [n, i])
		if s == null:
			break
		out.append(s)
	return out


static func _load_music() -> AudioStream:
	var m := _find("music")
	if m is AudioStreamOggVorbis:
		(m as AudioStreamOggVorbis).loop = true
	elif m is AudioStreamWAV:
		# save_to_wav writes no loop chunk, so the loop is set here: the whole file, seamless by construction
		var w := m as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(round(w.get_length() * w.mix_rate))
	return m


func _play(name: String, o: Dictionary, soft: bool, now: int) -> void:
	var file := name
	if name == "coin" and _num(o.get("amount", 0)) >= BIG_COIN:
		file = "coin_big"
	var takes: Array = _takes.get(file, [])
	if takes.is_empty():
		return
	var last := int(_last_at.get(file, -100000))
	if now - last < int(GAP.get(file, DEFAULT_GAP)):
		return   # the same sound too soon: skip it
	if file == "coin" or file == "coin_big":
		if _count_playing(["coin", "coin_big"]) >= 1:
			return   # several pickups at once: one coin sound at a time
	if _count_playing([file]) >= int(VOICES.get(file, DEFAULT_VOICES)):
		if not file in RESTART:
			return
		_stop_oldest(file)
	var p := _free_voice(file in PRIORITY)
	if p == null:
		return
	if file == "land":
		for q in _pool:
			if q.playing and _voice_name.get(q, "") == "roll":
				_fade_out(q, ROLL_CUT)
	var j: float = PITCH_JITTER.get(file, 0.0)
	var pitch := 1.0 + _rng.randf_range(-j, j)
	var g: float = GAIN_JITTER.get(file, 0.0)
	var gain := _rng.randf_range(-g, 0.0)
	if soft:
		gain += SOFT_DB
	if now - last < REPEAT_MS:
		gain -= float(REPEAT_SOFT.get(file, 0.0))
	_last_at[file] = now
	_start(p, file, takes[_pick(file, takes.size())], pitch, gain, now)


## A random take, never the one played last.
func _pick(file: String, n: int) -> int:
	if n <= 1:
		return 0
	var last := int(_last_take.get(file, -1))
	var i := _rng.randi_range(0, n - 2)
	if i >= last and last >= 0:
		i += 1
	_last_take[file] = i
	return i


func _start(p: AudioStreamPlayer, file: String, stream: AudioStream, pitch: float, gain_db: float, now: int) -> void:
	var tw: Tween = _voice_tween.get(p)
	if tw:
		tw.kill()
		_voice_tween.erase(p)
	_voice_name[p] = file
	_voice_started[p] = now
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = gain_db
	p.play()


func _fade_out(p: AudioStreamPlayer, sec: float) -> void:
	var old: Tween = _voice_tween.get(p)
	if old:
		old.kill()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -40.0, sec)
	tw.tween_callback(p.stop)
	_voice_tween[p] = tw


func _stop_oldest(file: String) -> void:
	var oldest: AudioStreamPlayer = null
	for p in _pool:
		if p.playing and _voice_name.get(p, "") == file:
			if oldest == null or int(_voice_started[p]) < int(_voice_started[oldest]):
				oldest = p
	if oldest:
		oldest.stop()


func _schedule_land(sec: float, soft: bool) -> void:
	var tok := _land_token
	_land_pending = true
	_land_soft = soft
	# not process_always: a paused game tree freezes the dice tween, and the clack waits with it
	get_tree().create_timer(maxf(sec, 0.0), false, false, true).timeout.connect(func() -> void:
		if tok != _land_token:
			return
		_land_pending = false
		if not enabled or _app_paused:
			return
		var now := Time.get_ticks_msec()
		_auto_land_at = now
		_play("land", {}, _land_soft, now))


func _cancel_land() -> void:
	_land_token += 1
	_land_pending = false


func _setup_buses() -> void:
	for bus_name: String in [SFX_BUS, MUSIC_BUS]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	var has_lp := false
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		var e := AudioServer.get_bus_effect(0, i)
		if e is AudioEffectLowPassFilter:
			has_lp = true
		elif e is AudioEffectHardLimiter:
			has_limiter = true
	if not has_lp:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = MASTER_LP_HZ
		lp.db = AudioEffectFilter.FILTER_12DB
		AudioServer.add_bus_effect(0, lp, 0)
	if not has_limiter:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(0, lim)


func _set_bus(bus_name: String, v: int, mute: bool) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, mute or v <= 0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(_curve(v), 0.0001)))


func _apply_levels() -> void:
	_set_bus("Master", master_volume, not enabled or _app_paused)
	_set_bus(SFX_BUS, effects_volume, false)
	_set_bus(MUSIC_BUS, music_volume, false)
	_sync_music()


func _sync_music() -> void:
	if _music == null or _music.stream == null:
		return
	var want := _music_wanted and enabled and not _app_paused and music_volume > 0 and master_volume > 0
	if want == _music_on:
		return
	_music_on = want
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	if want:
		if _music.stream_paused:
			_music.stream_paused = false
		elif not _music.playing:
			_music.play(_music_pos)
		_music_tween.tween_method(_set_music_gain, _music_gain, 1.0, MUSIC_FADE_IN * (1.0 - _music_gain))
	else:
		_music_tween.tween_method(_set_music_gain, _music_gain, 0.0, MUSIC_FADE_OUT * _music_gain)
		_music_tween.tween_callback(_stop_music)


func _set_music_gain(g: float) -> void:
	_music_gain = g
	_music.volume_db = linear_to_db(maxf(g * g, 0.0001)) + _duck   # g^2: a gentler, more even-sounding fade


func _stop_music() -> void:
	_music_pos = _music.get_playback_position()
	_music.stop()


func _count_playing(names: Array) -> int:
	var n := 0
	for p in _pool:
		if p.playing and _voice_name.get(p, "") in names:
			n += 1
	return n


## A free voice; when all are busy, a PRIORITY sound takes the oldest voice that isn't itself a priority sound.
func _free_voice(may_steal: bool) -> AudioStreamPlayer:
	var oldest: AudioStreamPlayer = null
	for p in _pool:
		if not p.playing:
			return p
		if _voice_name.get(p, "") in PRIORITY:
			continue
		if oldest == null or int(_voice_started[p]) < int(_voice_started[oldest]):
			oldest = p
	if may_steal and oldest:
		oldest.stop()
		return oldest
	return null
