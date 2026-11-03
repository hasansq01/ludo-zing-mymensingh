extends SceneTree
## Offline synth stems for the sound effects and the music loop. The finished effects are built by
## tools/mix_audio.py, which layers these stems with recorded CC0 foley (Kenney packs, tools/audio_src/kenney/),
## adds a small room reverb, normalises the loudness and writes res://assets/audio/ (see assets/audio/CREDITS.md).
##
## Pipeline (run both from the repo root, in this order):
##   godot --headless --path godot -s res://tools/gen_audio.gd     # -> godot/tools/audio_src/synth/*.wav
##   python3 godot/tools/mix_audio.py                              # -> godot/assets/audio/*.wav / *.ogg
##
## The physical sounds (dice, pawn steps, captures, chip clinks, UI taps) are recordings; what is synthesised here
## are the musical stings, the coin bell, a soft whoosh and the music loop. The whole set is voiced for long,
## comfortable sessions: warm instruments in a low register (felt marimba, FM electric piano, nylon pluck), soft
## 5-15 ms attacks, no glockenspiel, no high sparkles. Stems are raw: peak-normalised to 0.7, no reverb, no EQ and
## no limiting (mix_audio.py filters, adds the room and sets the levels). A fixed seed makes the output repeatable.
## `-- music` (or any stem names) after the command renders just those.

const OUT_DIR := "res://tools/audio_src/synth/"
const SFX_RATE := 44100
const MUSIC_RATE := 22050
const SEED := 20261020

var rng := RandomNumberGenerator.new()


## One mono mix buffer. With `wrap` on, sound running past the end continues at the start (seamless loops).
class Mix:
	var sr: int
	var buf: PackedFloat32Array
	var wrap := false

	func _init(rate: int, seconds: float, wrap_around := false) -> void:
		sr = rate
		wrap = wrap_around
		buf.resize(int(ceil(seconds * rate)))
		buf.fill(0.0)

	func add(idx: int, x: float) -> void:
		var n := buf.size()
		if wrap:
			buf[posmod(idx, n)] += x
		elif idx >= 0 and idx < n:
			buf[idx] += x


static func note(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


static func poly_blep(t: float, dt: float) -> float:
	if t < dt:
		t /= dt
		return t + t - t * t - 1.0
	if t > 1.0 - dt:
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	return 0.0


## RBJ biquad coefficients [b0, b1, b2, a1, a2] (normalised by a0).
static func biquad(kind: String, f: float, q: float, sr: int) -> PackedFloat32Array:
	f = clampf(f, 10.0, sr * 0.49)
	var w := TAU * f / sr
	var cw := cos(w)
	var alpha := sin(w) / (2.0 * q)
	var b0: float
	var b1: float
	var b2: float
	match kind:
		"lowpass":
			b0 = (1.0 - cw) / 2.0
			b1 = 1.0 - cw
			b2 = b0
		"highpass":
			b0 = (1.0 + cw) / 2.0
			b1 = -(1.0 + cw)
			b2 = b0
		_:   # bandpass, 0 dB peak gain (Web Audio's bandpass)
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
	var a0 := 1.0 + alpha
	return PackedFloat32Array([b0 / a0, b1 / a0, b2 / a0, -2.0 * cw / a0, (1.0 - alpha) / a0])


## Envelope sample counts and decay factor: linear 0 -> v over `attack`, then exponential v -> 0.0001 at `dur`.
static func env_setup(v: float, attack: float, dur: float, sr: int) -> Vector3:
	var att_n := maxi(1, int(attack * sr))
	var dec_n := maxi(1, int((dur - attack) * sr))
	return Vector3(att_n, dec_n, pow(0.0001 / maxf(v, 0.0002), 1.0 / dec_n))


# Web Audio's lowpass / highpass Q is a resonance in dB; its default (1 dB) is about this linear Q.
const LP_Q := 1.12


## One oscillator (sine / triangle / square / sawtooth): linear attack, exponential decay to 0.0001 at `dur`,
## optional exponential pitch glide to f2, optional lowpass, optional vibrato (vib = depth in semitones, vib_hz).
func tone(m: Mix, f: float, at: float, dur: float, o: Dictionary = {}) -> void:
	var type: String = o.get("type", "sine")
	var v: float = o.get("v", 0.3)
	var attack: float = o.get("attack", 0.006)
	var f2: float = o.get("f2", 0.0)
	var lp: float = o.get("lp", 0.0)
	var vib: float = o.get("vib", 0.0)
	var vib_hz: float = o.get("vib_hz", 6.0)
	var sr := m.sr
	var start := int(at * sr)
	var n := int(dur * sr)
	var e := env_setup(v, attack, dur, sr)
	var att_n := int(e.x)
	var gmul := e.z
	var freq := f
	var fmul := pow(f2 / f, 1.0 / n) if f2 > 0.0 else 1.0
	var c := biquad("lowpass", lp, LP_Q, sr) if lp > 0.0 else PackedFloat32Array()
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var phase := 0.0
	var g := 0.0
	for i in n:
		if i < att_n:
			g = v * float(i) / att_n
		else:
			g *= gmul
		var fi := freq
		if vib > 0.0:
			fi *= pow(2.0, vib / 12.0 * sin(TAU * vib_hz * i / sr))
		var dt := fi / sr
		var s: float
		match type:
			"triangle":
				s = 1.0 - 4.0 * absf(phase - 0.5)
			"square":
				s = (1.0 if phase < 0.5 else -1.0) + poly_blep(phase, dt) - poly_blep(fmod(phase + 0.5, 1.0), dt)
			"sawtooth":
				s = 2.0 * phase - 1.0 - poly_blep(phase, dt)
			_:
				s = sin(TAU * phase)
		phase += dt
		if phase >= 1.0:
			phase -= 1.0
		freq *= fmul
		if lp > 0.0:
			var y := c[0] * s + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
			x2 = x1
			x1 = s
			y2 = y1
			y1 = y
			s = y
		m.add(start + i, s * g)


## Filtered white noise with the same envelope; f -> f2 sweeps the filter.
func noise(m: Mix, at: float, dur: float, o: Dictionary = {}) -> void:
	var v: float = o.get("v", 0.2)
	var kind: String = o.get("type", "bandpass")
	var f: float = o.get("f", 2000.0)
	var f2: float = o.get("f2", 0.0)
	var q: float = o.get("q", 1.0)
	var attack: float = o.get("attack", 0.003)
	if kind != "bandpass":
		q = LP_Q
	var sr := m.sr
	var start := int(at * sr)
	var n := int(dur * sr)
	var e := env_setup(v, attack, dur, sr)
	var att_n := int(e.x)
	var gmul := e.z
	var fc := f
	var fmul := pow(f2 / f, 1.0 / n) if f2 > 0.0 else 1.0
	var c := biquad(kind, fc, q, sr)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var g := 0.0
	for i in n:
		if i < att_n:
			g = v * float(i) / att_n
		else:
			g *= gmul
		if fmul != 1.0:
			fc *= fmul
			if i % 16 == 0:
				c = biquad(kind, fc, q, sr)
		var s := rng.randf_range(-1.0, 1.0)
		var y := c[0] * s + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
		x2 = x1
		x1 = s
		y2 = y1
		y1 = y
		m.add(start + i, y * g)


# ---------- warm instruments ----------
# Everything is voiced low (fundamentals mostly 170-700 Hz), with soft 5-15 ms attacks and few, quickly fading
# upper partials, so nothing is bright or piercing: a felt-mallet marimba, an FM electric piano (Rhodes-like),
# a plucked nylon string (Karplus-Strong) and a soft bell for coins.

## Felt marimba: the fundamental and a faint 4th partial (1 : 3.93), a 6 ms attack, a soft low "thump".
func felt(m: Mix, n: float, at: float, v: float, ring := 1.0) -> void:
	var f := note(n)
	var d := 0.6 * ring * clampf(pow(440.0 / f, 0.35), 0.5, 1.6)
	tone(m, f, at, d, {v = v, attack = 0.006})
	tone(m, f * 3.93, at, d * 0.22, {v = v * 0.05, attack = 0.006})
	noise(m, at, 0.03, {v = v * 0.08, type = "lowpass", f = 700.0, attack = 0.004})


## FM electric piano: carrier and modulator at the same frequency; the modulation index starts low (warm) and
## falls over ~0.3 s, so a note opens a touch rounder than it rings. 8 ms attack, slow exponential decay.
func ep(m: Mix, n: float, at: float, v: float, dur := 2.5, index := 0.8) -> void:
	var f := note(n)
	var sr := m.sr
	var start := int(at * sr)
	var count := int(dur * sr)
	var att := maxi(1, int(0.008 * sr))
	var tau := 1.4 * clampf(pow(440.0 / f, 0.3), 0.6, 1.5)
	var w := TAU * f / sr
	for i in count:
		var t := float(i) / sr
		var g := v * (float(i) / att if i < att else exp(-(t - 0.008) / tau))
		g *= clampf((dur - t) / 0.08, 0.0, 1.0)   # 80 ms release at the end
		var ix := index * exp(-t / 0.3) + 0.12
		m.add(start + i, g * sin(w * i + ix * sin(w * i)))


## Plucked nylon string (Karplus-Strong): a soft, lowpassed noise burst circulating in a damped delay line.
## `bright` 0..1 sets the pluck's tone (low = thumb, high = nail); decay time `t60` seconds.
func pluck(m: Mix, n: float, at: float, v: float, t60 := 1.2, bright := 0.35) -> void:
	var f := note(n)
	var sr := m.sr
	var period := float(sr) / f
	var size := int(ceil(period)) + 2
	var line := PackedFloat32Array()
	line.resize(size)
	var lp := 0.0
	for i in size:
		lp += (rng.randf_range(-1.0, 1.0) - lp) * bright
		line[i] = lp
	var decay := pow(0.001, 1.0 / (t60 * f))      # per trip round the loop
	var start := int(at * sr)
	var count := int(t60 * 1.1 * sr)
	var pos := 0.0
	var prev := 0.0
	var att := int(0.005 * sr)
	var buf := PackedFloat32Array()                # the string, sample by sample, read one period back
	buf.resize(count + size)
	for i in size:
		buf[i] = line[i]
	for i in range(size, count + size):
		var back := float(i) - period
		var k := int(back)
		var fr := back - k
		var a := buf[k] * (1.0 - fr) + buf[k + 1] * fr
		var y := decay * (0.5 * a + 0.5 * prev)
		prev = a
		buf[i] = y
	for i in count:
		var g := v * (float(i) / att if i < att else 1.0)
		m.add(start + i, buf[i + size] * g)


## A soft struck bell for the coins: a low-ish fundamental, two faint inharmonic partials, a 4 ms attack.
func bell(m: Mix, f: float, at: float, v: float, ring: float) -> void:
	tone(m, f, at, ring, {v = v, attack = 0.004})
	tone(m, f * 2.76, at, ring * 0.45, {v = v * 0.22, attack = 0.004})
	tone(m, f * 5.40, at, ring * 0.2, {v = v * 0.05, attack = 0.004})


# ---------- stems ----------

## Every stem mix_audio.py uses. All in F major (the music's key).
const STEMS := ["select", "six_1", "six_2", "pair", "split", "home", "ladder", "snake", "win", "lose", "error",
		"coin", "coin_big", "buy", "whoosh"]


func make_stem(name: String) -> Mix:
	var m := Mix.new(SFX_RATE, 3.5)
	match name:
		"select":   # one soft felt "tup"
			felt(m, 72, 0.0, 0.5, 0.8)
		"six_1":    # extra roll: a gentle rising fourth, felt marimba doubled by the electric piano
			felt(m, 72, 0.0, 0.42)
			felt(m, 77, 0.11, 0.42)
			ep(m, 77, 0.11, 0.18, 1.2)
		"six_2":
			felt(m, 69, 0.0, 0.42)
			felt(m, 74, 0.11, 0.42)
			ep(m, 74, 0.11, 0.18, 1.2)
		"pair":     # two nylon plucks up a fifth
			pluck(m, 65, 0.0, 0.5, 0.9)
			pluck(m, 72, 0.07, 0.45, 1.0)
		"split":    # and down
			pluck(m, 72, 0.0, 0.45, 0.9)
			pluck(m, 65, 0.08, 0.5, 1.0)
		"home":     # a short warm chime: electric piano F A C, rolled
			for k in 3:
				ep(m, [65, 69, 72][k], k * 0.08, 0.3, 1.6)
			felt(m, 53, 0.0, 0.25, 1.4)
		"ladder":   # soft felt run up the scale
			var up := [65, 67, 69, 72, 74]
			for k in up.size():
				felt(m, up[k], k * 0.065, 0.36)
		"snake":    # a soft slide down with a breath of air, no hiss
			tone(m, 520.0, 0.02, 0.62, {type = "triangle", v = 0.3, f2 = 170.0, attack = 0.04, lp = 1400.0,
					vib = 0.25, vib_hz = 5.0})
			noise(m, 0.0, 0.4, {v = 0.06, type = "lowpass", f = 1600.0, attack = 0.06})
		"win":      # warm, low-key: electric piano rising F A C, then a soft open F chord
			for k in 3:
				ep(m, [65, 69, 72][k], k * 0.13, 0.28, 1.4)
			for n in [53, 57, 60, 65]:
				ep(m, n, 0.42, 0.17, 2.2, 0.6)
			felt(m, 77, 0.42, 0.18, 1.2)
			felt(m, 41, 0.42, 0.22, 1.6)
		"lose":     # gentle: nylon A G F, settling on a soft Bb chord ("never mind")
			for k in 3:
				pluck(m, [69, 67, 65][k], k * 0.22, 0.42, 1.3)
			for n in [58, 62, 65]:
				ep(m, n, 0.68, 0.14, 1.8, 0.5)
		"error":    # two low felt notes a semitone apart, soft
			felt(m, 57, 0.0, 0.42, 0.6)
			felt(m, 56, 0.14, 0.38, 0.7)
		"coin":     # soft coin: two low bell strikes a fourth apart, no clink, no sparkle
			bell(m, 784.0, 0.0, 0.3, 0.4)
			bell(m, 1047.0, 0.07, 0.34, 0.6)
		"coin_big":
			bell(m, 784.0, 0.0, 0.3, 0.4)
			bell(m, 1047.0, 0.07, 0.34, 0.6)
			bell(m, 1319.0, 0.14, 0.3, 0.8)
			felt(m, 53, 0.14, 0.2, 1.2)
		"buy":      # the coin and a soft electric piano "thank you"
			bell(m, 784.0, 0.0, 0.28, 0.4)
			bell(m, 1047.0, 0.07, 0.3, 0.5)
			ep(m, 72, 0.16, 0.2, 1.0)
			ep(m, 77, 0.26, 0.2, 1.2)
		"whoosh":   # a low, soft swoosh: band-passed noise sweeping 300 -> 1400 Hz
			noise(m, 0.0, 0.42, {v = 0.5, f = 300.0, f2 = 1400.0, q = 0.9, attack = 0.15})
	return m


# ---------- music ----------

## A calm lo-fi café loop at 66 BPM, 32 bars (~116 s): soft electric-piano chords with lots of space, a warm
## filtered pad, a round sine bass and a very sparse melody kept under ~600 Hz. Four sections so it doesn't feel
## repetitive: A (pad + piano), A2 (+ bass + a few melody notes), B (new chords), A3 (thinning out, ending on C
## so it leads back into the F at the top). Rendered with wrap-around: the loop has no seam. No drums, no high
## instruments; mix_audio.py adds a long, dark, circular reverb.
func make_music() -> Mix:
	const A := [[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60], [48, 52, 55, 57]]   # Fmaj7 Em7 Dm7 C6
	const A_BASS := [41, 40, 38, 36]
	const B := [[50, 53, 57, 58], [48, 52, 55, 57], [46, 50, 53, 55], [48, 53, 55, 58]]   # Bbmaj7/D Am7 Gm7 C7sus
	const B_BASS := [34, 33, 31, 36]
	const MEL := [65, 67, 69, 72, 74]   # F G A C D (pentatonic, F4-D5)
	const BARS := 32
	var beat := 60.0 / 66.0
	var bar := beat * 4.0
	var m := Mix.new(MUSIC_RATE, BARS * bar, true)
	var mi := 2
	for b in BARS:
		var t := b * bar
		var sec := b / 8          # 0 A, 1 A2, 2 B, 3 A3
		var chord: Array = (B if sec == 2 else A)[b % 4]
		var root: int = (B_BASS if sec == 2 else A_BASS)[b % 4]
		# pad: two slightly detuned, heavily filtered saws per chord tone (the top tone left out)
		for i in 3:
			for det in [-0.06, 0.06]:
				tone(m, note(chord[i] + det), t, bar * 1.35, {type = "sawtooth", v = 0.011, attack = 1.4, lp = 650.0})
		# electric piano: a soft rolled chord on beat 1, sometimes a lighter touch of the top two on the "and" of 3
		var vel := 0.075 if sec != 3 or b < 28 else 0.06
		for i in chord.size():
			ep(m, chord[i], t + i * 0.035 + rng.randf() * 0.01, vel * (0.85 + rng.randf() * 0.3), bar * 0.95, 0.7)
		if rng.randf() < 0.45:
			for i in [2, 3]:
				ep(m, chord[i], t + beat * 2.5 + (i - 2) * 0.03, vel * 0.55, beat * 1.4, 0.6)
		# bass from A2 on (and fading out of A3)
		if sec == 1 or sec == 2 or (sec == 3 and b < 28):
			tone(m, note(root), t, beat * 2.6, {v = 0.13, attack = 0.015, lp = 300.0})
			tone(m, note(root) * 2.0, t, beat * 1.2, {v = 0.02, attack = 0.015})
			if rng.randf() < 0.5:
				tone(m, note(root + 7), t + beat * 2.0, beat * 1.6, {v = 0.08, attack = 0.015, lp = 300.0})
		# melody: A2 and B only, 0-2 notes a bar on the off beats, low velocity
		if sec == 1 or sec == 2:
			var count: int = [0, 1, 1, 2][rng.randi_range(0, 3)]
			var slots := [1.0, 1.5, 2.5, 3.0]
			slots.shuffle()
			for k in count:
				mi = clampi(mi + [-1, 1, -2, 2][rng.randi_range(0, 3)], 0, MEL.size() - 1)
				ep(m, MEL[mi], t + slots[k] * beat, 0.055, beat * 2.6, 0.55)
	return m


# ---------- output ----------

## Peak-normalise to 0.7, trim the silent tail (not for loops), 16-bit PCM WAV.
func write_stem(name: String, m: Mix, loop: bool) -> float:
	var buf := m.buf
	var n := buf.size()
	var peak := 0.0
	for x in buf:
		peak = maxf(peak, absf(x))
	var k := 0.7 / peak if peak > 0.0 else 1.0
	if not loop:
		var last := n - 1
		while last > 0 and absf(buf[last]) * k < 0.0002:
			last -= 1
		n = mini(n, last + int(0.01 * m.sr))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, clampi(roundi(buf[i] * k * 32767.0), -32767, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = m.sr
	w.stereo = false
	w.data = bytes
	var err := w.save_to_wav(OUT_DIR + name + ".wav")
	if err != OK:
		push_error("gen_audio: could not save %s (%d)" % [name, err])
	return float(n) / m.sr


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	rng.seed = SEED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var only := OS.get_cmdline_user_args()   # e.g. -- music   (just that one)
	for name: String in STEMS:
		if only.is_empty() or name in only:
			print("%-9s %.2f s" % [name, write_stem(name, make_stem(name), false)])
	if only.is_empty() or "music" in only:
		print("%-9s %.2f s (loop)" % ["music", write_stem("music", make_music(), true)])
	print("gen_audio: done in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()
