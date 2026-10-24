#!/usr/bin/env python3
"""Builds every sound file in godot/assets/audio/ from recorded CC0 foley and the synth stems.

Run from anywhere, after `godot --headless --path godot -s res://tools/gen_audio.gd` (which writes the stems):
    python3 godot/tools/mix_audio.py
Needs numpy, scipy and soundfile (libsndfile with Vorbis, for reading the Kenney .ogg files and writing .ogg).

Sources (all CC0, see godot/assets/audio/CREDITS.md):
    tools/audio_src/kenney/<pack>/*.ogg   recordings from Kenney's Casino Audio, Impact Sounds, Interface Sounds and
                                          RPG Audio packs (only the files used are kept)
    tools/audio_src/synth/*.wav           the synth stems from gen_audio.gd (warm stings, coin bell, whoosh, music)

The mix is voiced for listening comfort over long sessions:
  * Warm: every file is low-passed (6-7 kHz for the bright ones, 2.5-4 kHz for clicks and steps); the dice and
    wood recordings also get a -6 dB dip around 4 kHz (where a click gets sharp) and their first-millisecond
    spike rounded by a gentle soft-knee saturator, followed by the low-pass so it adds no edge.
  * Quiet and unpumped: NO limiter and no makeup gain. Each effect gets a plain gain so that its peak lands on
    its PEAK value (all at or below -6 dBFS; UI taps / steps -16 to -18 dBFS) or its integrated loudness on its
    LUFS cap, whichever is lower. Loudness is ITU-R BS.1770 integrated LUFS (K-weighting, 400 ms gated blocks;
    a sound shorter than one block is measured padded to 400 ms). Music: -22 LUFS.
  * Small rooms: a short, dark reverb glues the sounds; the music sits in a long, dark circular one.
Effects under ~1 s are 16-bit mono 44.1 kHz WAV (Godot imports them QOA-compressed); longer ones and the music are
Ogg Vorbis (music at 22.05 kHz).

Variations: an effect with several takes is written as name_1, name_2, ... and Sound (scripts/audio/sound.gd) picks
one at random, never the same twice in a row.
"""
import os
import sys
from math import gcd

import numpy as np
import soundfile as sf
from scipy.signal import lfilter, butter, fftconvolve, resample_poly

HERE = os.path.dirname(os.path.abspath(__file__))
KENNEY = os.path.join(HERE, "audio_src", "kenney")
SYNTH = os.path.join(HERE, "audio_src", "synth")
OUT = os.path.join(HERE, "..", "assets", "audio")
SR = 44100
MSR = 22050             # music rate
OGG_OVER = 0.8          # seconds: longer effects are written as .ogg


# ---------- io ----------

def load(rel, sr=SR):
    path = os.path.join(KENNEY, rel) if rel.endswith(".ogg") else os.path.join(SYNTH, rel)
    x, fs = sf.read(path, dtype="float32", always_2d=True)
    x = x.mean(axis=1)
    if fs != sr:                            # a few Kenney files are 48 kHz
        g = gcd(fs, sr)
        x = resample_poly(x, sr // g, fs // g)
    return x.astype(np.float64)


def write(name, x, sr=SR, loop=False):
    secs = len(x) / sr
    ogg = loop or secs > OGG_OVER
    for ext in (".wav", ".ogg"):            # drop a stale file of the other format
        old = os.path.join(OUT, name + ext)
        if os.path.exists(old) and ext != (".ogg" if ogg else ".wav"):
            os.remove(old)
            if os.path.exists(old + ".import"):
                os.remove(old + ".import")
    path = os.path.join(OUT, name + (".ogg" if ogg else ".wav"))
    if ogg:
        sf.write(path, x.astype(np.float32), sr, format="OGG", subtype="VORBIS", compression_level=0.55)
    else:
        sf.write(path, x, sr, format="WAV", subtype="PCM_16")
    return path


# ---------- editing ----------

def db(g):
    return 10 ** (g / 20.0)


def first_hit(x, thr_db=-24.0, win=0.002):
    """Index a little before the first transient (window RMS within thr_db of the loudest)."""
    n = int(win * SR)
    m = len(x) // n
    e = np.sqrt((x[: m * n].reshape(m, n) ** 2).mean(1)) + 1e-12
    d = 20 * np.log10(e / e.max())
    for i in range(1, m):
        if d[i] > thr_db:
            return max(0, (i - 1) * n - int(0.002 * SR))
    return 0


def hits(x, thr_db=-30.0, win=0.002, rise=9.0, hold=0.04):
    n = int(win * SR)
    m = len(x) // n
    e = np.sqrt((x[: m * n].reshape(m, n) ** 2).mean(1)) + 1e-12
    d = 20 * np.log10(e / e.max())
    out, i = [], 1
    while i < m:
        if d[i] > thr_db and d[i] - d[max(0, i - 3)] > rise:
            out.append((i * n, float(d[i : i + 5].max())))
            i += int(hold / win)
        else:
            i += 1
    return out


def fade(x, fin=0.002, fout=0.01, out_from=None):
    """Cosine fade in over fin seconds; fade out over fout seconds at the end (or from out_from to the end)."""
    x = x.copy()
    a = max(1, int(fin * SR))
    x[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
    if out_from is not None:
        s = int(out_from * SR)
        b = len(x) - s
    else:
        b = max(1, int(fout * SR))
        s = len(x) - b
    if b > 0:
        x[s:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, b))
    return x


def env_db(x, points):
    """Piecewise-linear gain in dB over time: points = [(t, dB), ...]; holds the ends."""
    t = np.arange(len(x)) / SR
    ts, gs = zip(*points)
    return x * db(np.interp(t, ts, gs))


def mix(length, *layers):
    """layers: (signal, at seconds, gain dB)."""
    n = int(length * SR)
    for x, at, _ in layers:
        n = max(n, int(at * SR) + len(x))
    out = np.zeros(n)
    for x, at, g in layers:
        s = int(at * SR)
        out[s : s + len(x)] += x * db(g)
    return out


def norm(x):
    return x / (np.abs(x).max() + 1e-12)


def highpass(x, f, order=2, sr=SR):
    b, a = butter(order, f / (sr / 2), "high")
    return lfilter(b, a, x)


def lowpass(x, f, order=2, sr=SR):
    b, a = butter(order, f / (sr / 2), "low")
    return lfilter(b, a, x)


def peaking(x, f, gain_db, q=1.0, sr=SR):
    """RBJ peaking EQ (a dip for negative gain)."""
    A = db(gain_db / 2)
    w = 2 * np.pi * f / sr
    alpha = np.sin(w) / (2 * q)
    b = [1 + alpha * A, -2 * np.cos(w), 1 - alpha * A]
    a = [1 + alpha / A, -2 * np.cos(w), 1 - alpha / A]
    return lfilter(np.array(b) / a[0], np.array(a) / a[0], x)


def soften(x, knee=0.5):
    """Rounds the sharpest transient peaks: unity below knee x peak, a tanh curve above it (no time constants, so
    nothing pumps). Follow with a low-pass to remove the little edge it adds."""
    p = np.abs(x).max() + 1e-12
    y = x / p
    k = knee
    a = np.abs(y)
    over = a > k
    y[over] = np.sign(y[over]) * (k + (1 - k) * np.tanh((a[over] - k) / (1 - k)))
    return y * p


def warm_wood(x, lp=6000.0):
    """The dice / wood treatment: dip the 4 kHz click, round the spike, roll off the top."""
    x = peaking(x, 4000.0, -6.0, 0.9)
    x = soften(x, 0.45)
    return lowpass(x, lp, 2)


def trim_tail(x, thr_db=-60.0, pad=0.01):
    a = np.abs(x)
    keep = np.where(a > a.max() * db(thr_db))[0]
    end = min(len(x), (keep[-1] if len(keep) else 0) + int(pad * SR))
    return fade(x[:end], fin=0.0005, fout=min(0.03, end / SR / 4))


# ---------- reverb ----------

def impulse(rt60, sr=SR, damp=6000.0, pre=0.01, seed=7):
    """A small synthetic room: a few early reflections and an exponentially decaying, darkening noise tail."""
    rng = np.random.default_rng(seed)
    n = int(rt60 * 1.3 * sr)
    t = np.arange(n) / sr
    tail = rng.standard_normal(n) * np.exp(-6.91 * t / rt60)
    lo = lowpass(tail, damp, 1, sr)
    lo2 = lowpass(lo, damp * 0.5, 1, sr)
    k = np.clip(t / rt60, 0, 1)
    tail = lo * (1 - k) + lo2 * k                         # dark from the start, darker as it fades
    ir = np.zeros(n + int(pre * sr))
    ir[int(pre * sr):] = tail * 0.5
    for d, g in [(0.013, 0.4), (0.019, -0.3), (0.027, 0.25), (0.037, -0.18)]:
        ir[int(d * sr)] += g
    ir = lowpass(ir, damp, 1, sr)
    return ir / np.sqrt((ir ** 2).sum())


def reverb(x, rt60=1.0, wet=0.2, sr=SR, damp=4500.0, loop=False):
    ir = impulse(rt60, sr, damp)
    if loop:                                              # circular: the tail of the end wraps into the start
        n = len(x)
        if len(ir) > n:
            raise SystemExit("loop shorter than the reverb")
        y = np.real(np.fft.ifft(np.fft.fft(x) * np.fft.fft(ir, n)))
    else:
        y = fftconvolve(x, ir)
        x = np.concatenate([x, np.zeros(len(y) - len(x))])
    return x * (1 - wet) + y * wet * 1.6


# ---------- metering ----------

def _biquad_k(kind, fc, q, gain_db, sr):
    A = 10 ** (gain_db / 40.0)
    w0 = 2 * np.pi * fc / sr
    alpha = np.sin(w0) / (2 * q)
    c = np.cos(w0)
    if kind == "shelf":
        b = [A * ((A + 1) + (A - 1) * c + 2 * np.sqrt(A) * alpha), -2 * A * ((A - 1) + (A + 1) * c),
             A * ((A + 1) + (A - 1) * c - 2 * np.sqrt(A) * alpha)]
        a = [(A + 1) - (A - 1) * c + 2 * np.sqrt(A) * alpha, 2 * ((A - 1) - (A + 1) * c),
             (A + 1) - (A - 1) * c - 2 * np.sqrt(A) * alpha]
    else:
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
        a = [1 + alpha, -2 * c, 1 - alpha]
    return np.array(b) / a[0], np.array(a) / a[0]


def lufs(x, sr=SR):
    """ITU-R BS.1770-4 integrated loudness (mono). Sounds shorter than a 400 ms block are padded with silence."""
    b1, a1 = _biquad_k("shelf", 1681.974450955533, 0.7071752369554196, 3.999843853973347, sr)
    b2, a2 = _biquad_k("hp", 38.13547087602444, 0.5003270373238773, 0.0, sr)
    y = lfilter(b2, a2, lfilter(b1, a1, x))
    blk, hop = int(0.4 * sr), int(0.1 * sr)
    if len(y) < blk:
        y = np.concatenate([y, np.zeros(blk - len(y))])
    z = np.array([np.mean(y[i : i + blk] ** 2) for i in range(0, len(y) - blk + 1, hop)])
    l = -0.691 + 10 * np.log10(z + 1e-20)
    z1 = z[l > -70.0]
    if len(z1) == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(z1.mean()) - 10.0
    z2 = z[(l > -70.0) & (l > rel)]
    return -0.691 + 10 * np.log10(z2.mean())


def peak_db(x):
    return 20 * np.log10(np.abs(x).max() + 1e-12)


def centroid(x, sr=SR):
    X = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1 / sr)
    return float((X * f).sum() / (X.sum() + 1e-12))


def finish_set(takes, peak, cap, sr=SR):
    """One plain gain per take: its peak on `peak` dBFS or its loudness on `cap` LUFS, whichever is quieter; then
    the takes of a set are evened out to within 1.5 LU of the quietest. No limiter, no compression."""
    xs = [x - x.mean() if len(x) > sr else x for x in takes]
    ys = [x * db(min(peak - peak_db(x), cap - lufs(x, sr))) for x in xs]
    floor = min(lufs(y, sr) for y in ys)
    return [y * db(min(0.0, floor + 1.5 - lufs(y, sr))) for y in ys]


# ---------- the effects ----------

DICE = "casino-audio/"
IMP = "impact-sounds/"
UI = "interface-sounds/"
RPG = "rpg-audio/"


def clack(rel, at, length=0.075):
    """One single die clack cut out of a throw recording at `at` seconds."""
    x = load(rel)
    s = max(0, int(at * SR) - int(0.002 * SR))
    return fade(x[s : s + int(length * SR)], fin=0.0015, fout=0.03)


def make_roll():
    """roll_1..4: the die rattling in the hand, 0.40 s, starting on a rattle hit and fading out from 0.26 s so it
    has gone quiet by the time the die lands (0.6 x the 0.75 s roll = 0.45 s at normal speed)."""
    picks = []
    for f in ["dice-shake-1.ogg", "dice-shake-2.ogg", "dice-shake-3.ogg"]:
        x = load(DICE + f)
        hs = hits(x, thr_db=-26.0, rise=8.0)
        for s, lvl in hs:
            if s / SR + 0.40 > len(x) / SR - 0.05:
                continue
            inside = [h for h, l in hs if s <= h < s + int(0.30 * SR) and l > -22.0]
            picks.append((len(inside), lvl, f, s))
    picks.sort(key=lambda p: (-p[0], -p[1]))
    chosen = []
    for n, lvl, f, s in picks:
        if all(not (f == g and abs(s - t) < int(0.45 * SR)) for _, _, g, t in chosen):
            if sum(1 for c in chosen if c[2] == f) < 2:
                chosen.append((n, lvl, f, s))
        if len(chosen) == 4:
            break
    out = []
    for n, lvl, f, s in chosen:
        x = load(DICE + f)[max(0, s - int(0.003 * SR)) :][: int(0.40 * SR)]
        x = fade(x, fin=0.005, out_from=0.26)
        x = warm_wood(highpass(x, 150.0), 3000.0)
        out.append((x, f"{f} @ {s / SR:.2f}s, {n} hits"))
    return out


def make_land():
    """land_1..5: one die hitting the wooden table and tumbling to rest. Starts on the first impact; later bounces
    are tapered (-6 dB at 0.13 s down to -12 dB at 0.35 s) so the first clack reads as THE landing; 0.5 s max."""
    out = []
    for f in ["die-throw-1.ogg", "die-throw-2.ogg", "die-throw-3.ogg", "die-throw-4.ogg", "dice-throw-3.ogg"]:
        x = load(DICE + f)
        x = x[first_hit(x) :]
        x = x[: int(0.5 * SR)]
        x = env_db(x, [(0.0, 0.0), (0.08, 0.0), (0.13, -6.0), (0.35, -12.0)])
        x = fade(x, fin=0.0015, out_from=min(0.4, len(x) / SR - 0.02))
        x = warm_wood(highpass(x, 80.0), 6000.0)
        x = reverb(x, rt60=0.35, wet=0.08, damp=4000.0)
        out.append((trim_tail(x), f))
    return out


STEP_CLACKS = [("die-throw-2.ogg", 0.220), ("die-throw-2.ogg", 0.351), ("die-throw-3.ogg", 0.307),
               ("dice-throw-3.ogg", 0.176), ("dice-throw-1.ogg", 0.220)]


def make_step():
    """step_1..5: a soft wooden "tok" for a pawn on a square: one die clack, heavily softened (2.8 kHz low-pass)
    over a light wood knock for body. Quiet: these play on every square."""
    out = []
    for k, (f, at) in enumerate(STEP_CLACKS):
        c = norm(warm_wood(clack(DICE + f, at, 0.07), 2800.0))
        w = load(IMP + f"impactWood_light_00{k}.ogg")
        w = norm(fade(w[first_hit(w) :][: int(0.08 * SR)], fin=0.002, fout=0.03))
        x = mix(0.09, (c, 0.0, 0.0), (w, 0.001, -4.0))
        out.append((trim_tail(lowpass(highpass(x, 110.0), 3000.0)), f"{f} @ {at:.3f}s + impactWood_light_00{k}.ogg"))
    return out


def make_capture():
    """capture_1..3: a rounded wooden knock (die clack + soft punch thump) and a low swoosh as the pawn flies home."""
    whoosh = norm(load("whoosh.wav"))
    combos = [("die-throw-3.ogg", 0.076, "impactPunch_medium_000.ogg", "cloth2.ogg"),
              ("dice-throw-3.ogg", 0.056, "impactPunch_medium_001.ogg", "cloth1.ogg"),
              ("die-throw-2.ogg", 0.078, "impactPunch_medium_003.ogg", "cloth3.ogg")]
    out = []
    for f, at, punch, cloth in combos:
        c = norm(warm_wood(clack(DICE + f, at, 0.12), 4500.0))
        p = load(IMP + punch)
        p = norm(lowpass(fade(p[first_hit(p) :][: int(0.3 * SR)], fin=0.003, fout=0.12), 2500.0))
        cl = load(RPG + cloth)
        cl = norm(lowpass(fade(cl[first_hit(cl, -20.0) :][: int(0.3 * SR)], fin=0.01, fout=0.15), 4000.0))
        x = mix(0.6, (c, 0.0, -2.0), (p, 0.0, -4.0), (whoosh, 0.05, -8.0), (cl, 0.07, -18.0))
        x = reverb(lowpass(highpass(x, 70.0), 3500.0), rt60=0.45, wet=0.12, damp=3500.0)
        out.append((trim_tail(x), f"{f} @ {at:.3f}s + {punch} + {cloth} + synth whoosh"))
    return out


def cap_len(x, sec):
    """Keep stings short: fade the ringing tail out over the last 40 % of `sec`."""
    if len(x) / SR <= sec:
        return x
    return fade(x[: int(sec * SR)], fin=0.0005, out_from=sec * 0.6)


def sting(stem, rt60=1.0, wet=0.2, lp=6500.0, max_len=1.2):
    x = load(stem + ".wav")
    x = lowpass(highpass(x, 90.0), lp, 2)
    return cap_len(trim_tail(reverb(x, rt60=rt60, wet=wet, damp=3500.0), thr_db=-58.0), max_len)


def chip(f, lp=3500.0, length=0.12):
    c = load(DICE + f)
    c = fade(c[first_hit(c) :][: int(length * SR)], fin=0.002, fout=0.05)
    return norm(lowpass(peaking(c, 4500.0, -6.0, 0.9), lp, 2))


def make_coin():
    """coin_1..3: the soft coin bell (synth) with a real chip clink, rounded and low-passed, under it."""
    bell = norm(load("coin.wav"))
    out = []
    for f in ["chips-collide-1.ogg", "chips-collide-2.ogg", "chips-stack-5.ogg"]:
        x = mix(0.7, (chip(f), 0.0, -12.0), (bell, 0.004, 0.0))
        out.append((trim_tail(reverb(lowpass(x, 6500.0), rt60=0.8, wet=0.15, damp=3500.0)), f"synth bell + {f}"))
    return out


def make_coin_big():
    bell = norm(load("coin_big.wav"))
    h = load(RPG + "handleCoins2.ogg")
    h = norm(lowpass(fade(h[first_hit(h, -30.0) :], fin=0.004, fout=0.08), 3500.0))
    x = mix(1.0, (chip("chips-stack-1.ogg"), 0.0, -12.0), (bell, 0.004, 0.0), (h, 0.03, -14.0))
    x = lowpass(x, 6500.0)
    return trim_tail(reverb(x, rt60=0.9, wet=0.16, damp=3500.0)), "synth bell + handleCoins2.ogg + chips-stack-1.ogg"


def make_buy():
    s = norm(load("buy.wav"))
    h = load(DICE + "chips-handle-3.ogg")
    h = norm(lowpass(fade(h[first_hit(h) :], fin=0.004, fout=0.06), 3500.0))
    x = lowpass(mix(1.0, (h, 0.0, -10.0), (s, 0.02, 0.0)), 6500.0)
    return cap_len(trim_tail(reverb(x, rt60=0.9, wet=0.18, damp=3500.0)), 1.2), \
        "synth bell + electric piano + chips-handle-3.ogg"


def make_pair(stem, click, gain):
    s = norm(load(stem + ".wav"))
    x = mix(1.2, (chip(click, 3000.0, 0.1), 0.0, gain), (s, 0.01, 0.0))
    x = lowpass(highpass(x, 90.0), 6000.0)
    return cap_len(trim_tail(reverb(x, rt60=0.9, wet=0.2, damp=3500.0)), 0.9), f"synth nylon pluck + {click}"


def make_click(f, lp, label):
    x = load(UI + f)
    x = fade(x[first_hit(x) :], fin=0.002, fout=0.012)
    return trim_tail(lowpass(highpass(x, 200.0), lp, 2)), label


# Peak (dBFS) and loudness cap (LUFS) per effect: the gain is whichever is quieter. Everything peaks at -6 dBFS or
# lower; UI and steps sit far below the board events; dice and captures are the loudest, stings sit under them.
LEVEL = {
    #           peak    LUFS cap
    "tap":     (-18.0, -38.0),
    "tick":    (-20.0, -40.0),
    "step":    (-17.0, -36.0),
    "select":  (-16.0, -34.0),
    "error":   (-15.0, -32.0),
    "roll":    (-12.0, -31.0),
    "land":    (-7.0, -26.0),
    "capture": (-6.0, -25.0),
    "six":     (-14.0, -31.0),
    "pair":    (-14.0, -31.0),
    "split":   (-15.0, -32.0),
    "ladder":  (-13.0, -30.0),
    "snake":   (-13.0, -30.0),
    "home":    (-11.0, -28.0),
    "coin":    (-13.0, -30.0),
    "coin_big": (-11.0, -28.0),
    "buy":     (-12.0, -29.0),
    "win":     (-9.0, -26.0),
    "lose":    (-11.0, -28.0),
}
MUSIC_LUFS = -22.0
MUSIC_PEAK = -6.0


def build_music():
    m = load("music.wav", sr=MSR)
    n = len(m)
    # filters are causal: run them twice round the loop and keep the second lap, so the seam has no step
    m = highpass(np.concatenate([m, m]), 45.0, 2, MSR)[n:]
    m = reverb(m, rt60=2.6, wet=0.32, sr=MSR, damp=2500.0, loop=True)
    m = lowpass(np.concatenate([m, m]), 4500.0, 2, MSR)[n:]
    m = m - m.mean()
    m = m * db(min(MUSIC_LUFS - lufs(m, MSR), MUSIC_PEAK - peak_db(m)))
    return m


def main():
    os.makedirs(OUT, exist_ok=True)
    sets = {
        "roll": make_roll(), "land": make_land(), "step": make_step(), "capture": make_capture(),
        "coin": make_coin(),
        "six": [(sting("six_1", 1.0, 0.22, max_len=1.0), "synth felt marimba + electric piano"),
                (sting("six_2", 1.0, 0.22, max_len=1.0), "synth felt marimba + electric piano")],
    }
    singles = {
        "tap": make_click("select_002.ogg", 2500.0, "select_002.ogg"),
        "tick": make_click("tick_002.ogg", 2500.0, "tick_002.ogg"),
        "select": (sting("select", 0.8, 0.16, 5000.0, 0.5), "synth felt marimba"),
        "pair": make_pair("pair", "chips-collide-3.ogg", -12.0),
        "split": make_pair("split", "chip-lay-1.ogg", -14.0),
        "home": (sting("home", 1.3, 0.24, max_len=1.6), "synth electric piano chord"),
        "ladder": (sting("ladder", 0.9, 0.18, max_len=1.0), "synth felt marimba run"),
        "snake": (sting("snake", 0.8, 0.16, 4000.0), "synth soft slide"),
        "win": (sting("win", 1.4, 0.26, max_len=2.2), "synth electric piano chord"),
        "lose": (sting("lose", 1.3, 0.24, max_len=2.0), "synth nylon pluck + electric piano"),
        "error": (sting("error", 0.6, 0.12, 4000.0), "synth low felt marimba"),
        "coin_big": make_coin_big(), "buy": make_buy(),
    }
    for name in sets:                     # stale single files replaced by variation sets
        for ext in (".wav", ".ogg"):
            p = os.path.join(OUT, name + ext)
            if os.path.exists(p):
                os.remove(p)
                if os.path.exists(p + ".import"):
                    os.remove(p + ".import")
    rows = []
    for name, takes in sets.items():
        done = finish_set([x for x, _ in takes], *LEVEL[name])
        for i, (y, (_, src)) in enumerate(zip(done, takes), 1):
            rows.append((f"{name}_{i}", y, src, write(f"{name}_{i}", y)))
    for name, (x, src) in singles.items():
        y = finish_set([x], *LEVEL[name])[0]
        rows.append((name, y, src, write(name, y)))
    m = build_music()
    write("music", m, sr=MSR, loop=True)
    total = 0
    print(f"{'file':14s} {'sec':>5s} {'peak':>6s} {'LUFS':>6s} {'cent':>6s} {'bytes':>7s}  source")
    for name, y, src, path in rows:
        size = os.path.getsize(path)
        total += size
        print(f"{os.path.basename(path):14s} {len(y) / SR:5.2f} {peak_db(y):6.1f} {lufs(y):6.1f} {centroid(y):6.0f} "
              f"{size:7d}  {src}")
    size = os.path.getsize(os.path.join(OUT, "music.ogg"))
    total += size
    print(f"{'music.ogg':14s} {len(m) / MSR:5.1f} {peak_db(m):6.1f} {lufs(m, MSR):6.1f} {centroid(m, MSR):6.0f} "
          f"{size:7d}  synth loop (gen_audio.gd)")
    print(f"total {total / 1024:.0f} KB in {len(rows) + 1} files")


if __name__ == "__main__":
    sys.exit(main())
