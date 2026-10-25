#!/usr/bin/env python3
"""Builds the 24 emote sounds: godot/assets/audio/emotes/<id>.ogg (+ levels.json with the measured levels).

    python3 godot/tools/make_emote_sfx.py
Needs numpy, scipy, soundfile (same as mix_audio.py, whose helpers it reuses). Deterministic.

Same calm voicing as the rest of the game's sfx: soft attacks, everything low-passed (5-6 kHz at most), a little dark
room, no limiter. Each sound is a plain gain so its active RMS lands on the reference (the mean of the tap and step
sounds) and its peak stays at or below the loudest of those (-17 dBFS). Sources: synthesized tones (felt-marimba /
bell style partials, glides, filtered noise) plus CC0 Kenney recordings for dice, thud, clap, cloth and the click
(see assets/audio/CREDITS.md). 44.1 kHz mono Ogg Vorbis.
"""
import json
import os
import sys

import numpy as np
import soundfile as sf
from scipy.signal import butter, lfilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import mix_audio as M  # noqa: E402

SR = M.SR
AUDIO = os.path.normpath(os.path.join(HERE, "..", "assets", "audio"))
OUT = os.path.join(AUDIO, "emotes")
RNG = np.random.default_rng(2610)
NOTE = {"C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.0, "A4": 440.0, "B4": 493.88,
        "C5": 523.25, "D5": 587.33, "E5": 659.25, "F5": 698.46, "G5": 783.99, "A5": 880.0, "B5": 987.77,
        "C6": 1046.5, "D6": 1174.7, "E6": 1318.5, "G6": 1568.0, "C7": 2093.0, "Eb4": 311.13, "Bb4": 466.16,
        "Ab4": 415.3, "Db5": 554.37, "Eb5": 622.25, "Gb4": 369.99}
REF_PEAK_DB = -17.0     # the loudest tap / step peak
ACTIVE_THR = 0.03       # "active" = samples above 3 % of the peak


def t_(d):
    return np.arange(int(d * SR)) / SR


def tone(f, dur=0.5, att=0.008, tau=0.18, parts=((1, 1.0), (2, 0.18), (3, 0.05)), vib=0.0, glide=None):
    """Felt-marimba / soft bell: a few partials, soft attack, exponential decay. glide=(f_end) slides the pitch."""
    t = t_(dur)
    fr = f * np.ones_like(t) if glide is None else f * (glide / f) ** (t / dur)
    if vib:
        fr = fr * (1 + vib * np.sin(2 * np.pi * 5.5 * t))
    ph = 2 * np.pi * np.cumsum(fr) / SR
    y = sum(a * np.sin(ph * k) for k, a in parts)
    env = np.exp(-t / tau) * np.minimum(1, t / att)
    return M.fade(y * env, fin=0.001, fout=min(0.04, dur / 4))


def bell(f, dur=0.6, tau=0.25):
    return tone(f, dur, 0.004, tau, ((1, 1.0), (2.76, 0.12), (4.1, 0.04)))


def blip(f0, f1, dur=0.09):
    """A bouncy rounded blip: sine glide with a quick hump envelope."""
    t = t_(dur)
    fr = f0 * (f1 / f0) ** (t / dur)
    y = np.sin(2 * np.pi * np.cumsum(fr) / SR) + 0.15 * np.sin(4 * np.pi * np.cumsum(fr) / SR)
    return y * np.sin(np.pi * t / dur) ** 1.5


def noise(dur):
    return RNG.standard_normal(int(dur * SR))


def sweep_noise(dur, f0, f1, q=2.5, shape=None):
    """Band-passed noise whose centre glides f0 -> f1 (a soft whoosh), block-wise."""
    x = noise(dur)
    out = np.zeros_like(x)
    n = len(x)
    blk = 441
    z = None
    for i in range(0, n, blk):
        fc = f0 * (f1 / f0) ** (i / n)
        bw = fc / q
        lo, hi = max(40, fc - bw / 2), min(SR / 2 - 100, fc + bw / 2)
        b, a = butter(2, [lo / (SR / 2), hi / (SR / 2)], "band")
        seg = x[i : i + blk]
        y, z = lfilter(b, a, seg, zi=(z if z is not None else np.zeros(max(len(a), len(b)) - 1)))
        out[i : i + blk] = y
    t = np.arange(n) / n
    env = np.sin(np.pi * t) ** 2 if shape is None else shape(t)
    return M.norm(out) * env


def seq(notes, step, mk, tail=0.5):
    """Notes (name or Hz) one after another every `step` s, each built by mk(freq)."""
    n = len(notes)
    layers = [(mk(NOTE.get(f, f)), i * step, -i * 0.4) for i, f in enumerate(notes)]
    return M.mix(step * (n - 1) + tail, *layers)


def clip(rel, at, length, lp=3500, hp=0):
    x = M.load(rel)
    s = max(0, int(at * SR))
    y = x[s : s + int(length * SR)]
    y = M.fade(y, fin=0.002, fout=min(0.05, len(y) / SR / 3))
    return M.lowpass(M.highpass(y, hp) if hp else y, lp)


# ---------- the 24 ----------

def squash(x, k=3.0):
    """Evens out a spiky recording (tanh of the normalised signal), so it can sit at the calm level without a peak."""
    return np.tanh(k * M.norm(x)) / np.tanh(k)


def e_happy():   # bright soft chime arpeggio
    return seq(["C5", "E5", "G5", "C6"], 0.11, lambda f: bell(f, 0.7, 0.28), 0.6)


def e_laugh():   # playful bouncy blips, rising and falling
    return M.mix(0.8, *[(blip(f0, f1, 0.1), 0.13 * i, -1.2 * (i % 2)) for i, (f0, f1) in
                        enumerate([(500, 750), (560, 820), (500, 750), (580, 880), (520, 700)])])


def e_cool():    # smooth whoosh then a soft click
    w = sweep_noise(0.45, 500, 1800, 1.5, lambda t: np.sin(np.pi * t ** 0.8) ** 2)
    w = M.lowpass(w, 2500)
    k = clip(M.UI + "tick_002.ogg", 0, 0.08, 3000)
    return M.mix(0.7, (w, 0.0, -2), (k, 0.4, 6), (tone(NOTE["G4"], 0.25, 0.01, 0.1), 0.42, -14))


def e_angry():   # low soft bonk plus a grumble
    t = t_(0.7)
    bonk = np.sin(2 * np.pi * np.cumsum(120 * (70 / 120) ** (np.minimum(t, 0.3) / 0.3)) / SR) * np.exp(-t / 0.16)
    gr = np.tanh(2.2 * np.sin(2 * np.pi * 85 * t + 3 * np.sin(2 * np.pi * 11 * t))) * np.exp(-((t - 0.3) / 0.22) ** 2)
    return M.fade(M.lowpass(bonk + 0.35 * gr, 700), 0.004, 0.08)


def e_love():    # warm two-note "aww"
    a = tone(NOTE["E5"], 0.7, 0.03, 0.3, ((1, 1), (2, 0.3), (3, 0.08)), vib=0.004)
    b = tone(NOTE["G5"], 0.9, 0.03, 0.4, ((1, 1), (2, 0.3), (3, 0.08)), vib=0.004)
    return M.mix(1.1, (a, 0.0, 0), (b, 0.26, 1))


def e_party():   # sparkle fanfare with a little confetti hiss
    f = seq(["C5", "G5", "C6", "E6", "G6"], 0.09, lambda f: bell(f, 0.55, 0.22), 0.55)
    s = M.lowpass(M.highpass(noise(0.5), 2500), 5500) * np.sin(np.pi * t_(0.5) / 0.5) ** 2 * 0.05
    return M.mix(0.9, (f, 0, 0), (s, 0.25, 0))


def e_champ():   # small regal triad swell
    ch = [tone(NOTE[n], 0.9, 0.06, 0.55, ((1, 1), (2, 0.4), (3, 0.15), (4, 0.06))) for n in ["G4", "C5", "E5"]]
    top = tone(NOTE["G5"], 0.8, 0.02, 0.45, ((1, 1), (2, 0.3), (3, 0.1)))
    return M.mix(1.1, (ch[0], 0, 0), (ch[1], 0.12, -1), (ch[2], 0.24, -1), (top, 0.4, 0))


def e_sleepy(): # slow descending tones and a snore puff
    n = seq(["G4", "E4", "C4"], 0.3, lambda f: tone(f, 0.6, 0.05, 0.3, vib=0.003), 0.4)
    b = M.lowpass(noise(0.4), 500) * np.sin(np.pi * t_(0.4) / 0.4) ** 2
    return M.mix(1.2, (n, 0, 0), (b, 0.75, 4))


def e_sob():     # gentle descending minor with hiccup shakes
    return seq(["A4", "G4", "E4", "E4"], 0.22, lambda f: tone(f, 0.45, 0.02, 0.2, vib=0.012), 0.5)


def e_gasp():    # quick rising whoosh and a pop
    w = sweep_noise(0.3, 400, 2400, 1.2, lambda t: np.sin(np.pi * t * 0.5) ** 2)
    return M.mix(0.55, (M.lowpass(w, 3000), 0, -1), (blip(500, 900, 0.1), 0.28, 3))


def e_confused():  # curious questioning two notes (second slides up, unresolved)
    a = tone(NOTE["E4"], 0.3, 0.02, 0.2)
    b = tone(NOTE["E4"] * 1.0, 0.5, 0.03, 0.3, glide=NOTE["B4"] * 1.03, vib=0.0)
    return M.mix(0.9, (a, 0, 0), (b, 0.28, 1))


def e_hi():      # friendly pop pair
    return M.mix(0.45, (blip(380, 760, 0.08), 0.0, 0), (blip(450, 900, 0.09), 0.13, 1),
                 (clip(M.UI + "tick_002.ogg", 0, 0.05, 2800), 0.15, -6))


def e_cry():     # long gentle descending minor, wobbling
    return seq(["A4", "F4", "D4"], 0.33, lambda f: tone(f, 0.6, 0.03, 0.28, vib=0.014), 0.5)


def e_wow():     # rising whoosh into a shimmering bell
    w = M.lowpass(sweep_noise(0.35, 600, 2600, 1.2, lambda t: np.sin(np.pi * t * 0.5) ** 2), 3500)
    return M.mix(0.9, (w, 0, -2), (bell(NOTE["E6"], 0.6, 0.3), 0.3, -2), (bell(NOTE["B5"], 0.55, 0.3), 0.36, -5))


def e_facepalm():  # soft thud and cloth rub
    th = M.lowpass(M.load(M.IMP + "impactPunch_medium_001.ogg")[: int(0.4 * SR)], 450)
    cl = clip(M.RPG + "cloth1.ogg", 0.0, 0.3, 1800)
    return M.mix(0.55, (M.fade(th, 0.002, 0.1), 0, 0), (cl, 0.05, -10))


def e_cheer():   # soft cheer sparkle: pentatonic twinkles over a soft crowd swell
    notes = ["G5", "A5", "C6", "D6", "E6", "G6", "E6", "C6"]
    tw = M.mix(1.2, *[(bell(NOTE[n], 0.4, 0.15), 0.1 * i, -3) for i, n in enumerate(notes)])
    cr = M.lowpass(M.highpass(noise(1.0), 500), 2200) * np.sin(np.pi * t_(1.0)) ** 2 * 0.08
    return M.mix(1.2, (tw, 0.05, 0), (cr, 0, 0))


def e_think():   # curious "hmm" two plucks
    return M.mix(0.8, (tone(NOTE["G4"], 0.35, 0.02, 0.15), 0, 0), (tone(NOTE["A4"], 0.45, 0.02, 0.2, vib=0.005), 0.32, 0),
                 (bell(NOTE["E6"], 0.25, 0.08), 0.5, -16))


def e_tease():   # playful nyah-nyah
    return M.mix(0.75, *[(blip(f, f * 0.93, 0.11), 0.135 * i, 0) for i, f in
                         enumerate([NOTE["G5"], NOTE["E5"], NOTE["G5"], NOTE["E5"], NOTE["G5"]])])


def e_dice():    # the game's dice rattle and landing, softened
    r = M.load(M.DICE + "dice-shake-2.ogg")[int(0.27 * SR) : int(0.27 * SR) + int(0.45 * SR)]
    r = M.warm_wood(M.fade(r, 0.003, 0.15), 5500)
    l = M.warm_wood(M.fade(M.load(M.DICE + "die-throw-2.ogg")[: int(0.4 * SR)], 0.002, 0.2), 5000)
    return squash(M.mix(0.95, (M.norm(r), 0, 0), (M.norm(l), 0.5, -4)), 7.0)


def e_crown():   # tiny regal harp-like sparkle run
    return seq(["C5", "E5", "G5", "C6", "E6", "G6", "C7"], 0.065, lambda f: bell(f, 0.6, 0.3), 0.6)


def e_highfive():  # friendly clap-tap
    cl = M.lowpass(M.highpass(noise(0.12), 900), 3200) * np.exp(-t_(0.12) / 0.018)
    th = tone(150, 0.12, 0.003, 0.04, ((1, 1),))
    return M.mix(0.4, (M.fade(cl + 0.8 * th, 0.002, 0.04), 0, 0), (clip(M.DICE + "die-throw-1.ogg", 0.0, 0.1, 2500), 0.0, -8))


def e_flag():    # soft flutter
    c = M.load(M.RPG + "cloth3.ogg")
    c = M.fade(c[: int(0.7 * SR)], 0.08, 0.2)
    t = t_(len(c) / SR)
    am = 0.55 + 0.45 * np.sin(2 * np.pi * 17 * t)
    return squash(M.lowpass(c * am, 1800), 3.0)


def e_sad():     # two slow falling notes
    return M.mix(1.0, (tone(NOTE["E4"], 0.5, 0.04, 0.3, vib=0.004), 0, 0),
                 (tone(NOTE["E4"], 0.7, 0.04, 0.4, glide=NOTE["C4"], vib=0.004), 0.38, 0))


def e_peek():    # cute peek-a-boo: low pop, then higher pop and a twinkle
    return M.mix(0.75, (blip(300, 650, 0.1), 0, 0), (blip(520, 1100, 0.1), 0.32, 1), (bell(NOTE["C6"], 0.3, 0.1), 0.45, -8))


MAKERS = {k[2:]: v for k, v in globals().items() if k.startswith("e_")}


MAX_S = 1.2


def finish(x, lp=5500, knee=0.6):
    x = x - x.mean()
    x = M.lowpass(x, lp, 2)
    x = M.reverb(x, 0.35, 0.12, damp=3500)
    x = M.trim_tail(x, -55)
    if len(x) > int(MAX_S * SR):
        x = x[: int(MAX_S * SR)]
    x = M.fade(x, 0.003, 0.12 if len(x) > 0.9 * SR else 0.05)
    return M.lowpass(M.soften(x, knee), 5500, 1)


def active_rms_db(x):
    a = np.abs(x)
    m = a > a.max() * ACTIVE_THR
    return float(20 * np.log10(np.sqrt((x[m] ** 2).mean()) + 1e-12))


def load_out(p):
    x, fs = sf.read(p, dtype="float64", always_2d=True)
    return x.mean(axis=1), fs


def reference():
    names = ["tap.wav", "step_1.wav", "step_2.wav", "step_3.wav", "step_4.wav", "step_5.wav"]
    rows = {}
    for n in names + ["tick.wav", "select.wav", "ladder.ogg", "coin_1.ogg", "six_1.ogg", "land_1.wav"]:
        x, _ = load_out(os.path.join(AUDIO, n))
        rows[n] = {"peak_db": round(M.peak_db(x), 1), "rms_db": round(active_rms_db(x), 1)}
    ref_rms = float(np.mean([rows[n]["rms_db"] for n in names]))
    ref_peak = max(rows[n]["peak_db"] for n in names)
    return rows, ref_rms, ref_peak


def main():
    os.makedirs(OUT, exist_ok=True)
    refs, ref_rms, ref_peak = reference()
    levels = {}
    for eid in sorted(MAKERS):
        raw = MAKERS[eid]()
        for knee in (0.6, 0.45, 0.35, 0.28, 0.22, 0.17):   # round spiky transients until the peak cap leaves the RMS in range
            x = finish(raw, knee=knee)
            g = ref_rms - active_rms_db(x)
            if M.peak_db(x) + g <= ref_peak - 0.4:
                break
        g = min(g, ref_peak - 0.4 - M.peak_db(x))   # margin for the Vorbis round trip
        x = x * M.db(g)
        path = os.path.join(OUT, eid + ".ogg")
        for _ in range(8):
            sf.write(path, x.astype(np.float32), SR, format="OGG", subtype="VORBIS", compression_level=0.55)
            y, fs = load_out(path)            # measure what the game will load
            if M.peak_db(y) <= ref_peak:
                break
            x = x * M.db(-0.3)                # the Vorbis round trip overshot the cap
        levels[eid] = {"dur_s": round(len(y) / fs, 2), "peak_db": round(M.peak_db(y), 1),
                       "rms_db": round(active_rms_db(y), 1), "lufs": round(M.lufs(y, fs), 1),
                       "centroid_hz": round(M.centroid(y, fs))}
        print(eid, levels[eid])
    data = {"ref_rms_db": round(ref_rms, 1), "ref_peak_db": ref_peak, "rms_tolerance_db": 1.5, "reference": refs,
            "emotes": levels}
    with open(os.path.join(OUT, "levels.json"), "w") as f:
        json.dump(data, f, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
