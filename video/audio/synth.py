#!/usr/bin/env python3
"""Score for the 30-second AgentSweep film, synthesised in code (no samples).

Method after huashu-art-motion's references/05: a strict 120 BPM grid (one bar = 2 s, every cut on a bar line),
one short motif carried through, hard entrances at cuts, and sound effects pinned to picture events.

    uv run --with numpy --with soundfile python audio/synth.py   ->  audio/music.wav (48 kHz stereo, 30.0 s)
"""
from pathlib import Path

import numpy as np
import soundfile as sf

SR = 48000
DUR = 30.0
N = int(SR * DUR)
BEAT = 0.5
rng = np.random.default_rng(7)
L = np.zeros(N)
R = np.zeros(N)


def tvec(d):
    return np.arange(int(d * SR)) / SR


def env(d, a=0.005, r=None, curve=6.0):
    """Attack then exponential decay over d seconds."""
    t = tvec(d)
    e = np.exp(-curve * t / d)
    na = max(1, int(a * SR))
    e[:na] *= np.linspace(0, 1, na)
    return e


def add(sig, t, gain=1.0, pan=0.0):
    s = int(round(t * SR))
    if s >= N or len(sig) == 0:
        return
    sig = sig[: N - s] * gain
    a = (pan + 1) * np.pi / 4
    L[s:s + len(sig)] += sig * np.cos(a)
    R[s:s + len(sig)] += sig * np.sin(a)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def pluck(midi, d=0.6, bright=3):
    t = tvec(d)
    f = hz(midi)
    s = sum(np.sin(2 * np.pi * f * k * t) / k ** 1.6 for k in range(1, bright + 1))
    return s * env(d, 0.003, curve=7)


def pad(midis, d, a=0.4):
    t = tvec(d)
    s = np.zeros_like(t)
    for m in midis:
        for det in (-0.12, 0.0, 0.12):
            f = hz(m + det)
            s += np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2 * f * t)
    e = np.minimum(1, t / a) * np.minimum(1, (d - t) / 0.6)
    return s / (len(midis) * 3) * np.clip(e, 0, 1)


def kick(d=0.35):
    t = tvec(d)
    f = 45 + 110 * np.exp(-t * 28)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(d, 0.001, curve=7)


def hat(d=0.06):
    return rng.standard_normal(int(d * SR)) * env(d, 0.0005, curve=9) * 0.35


def click(d=0.03, f=2600):
    t = tvec(d)
    return np.sin(2 * np.pi * f * t) * env(d, 0.0005, curve=10)


def blip(midi, d=0.12):
    t = tvec(d)
    f = hz(midi) * (1 + 0.5 * np.exp(-t * 60))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(d, 0.002, curve=8)


def boom(d=1.4):
    t = tvec(d)
    f = 30 + 60 * np.exp(-t * 6)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(d, 0.002, curve=4)
    n = rng.standard_normal(len(t)) * env(d, 0.001, curve=30) * 0.5
    return s + n


def riser(d):
    t = tvec(d)
    n = rng.standard_normal(len(t))
    # crude rising band: difference of moving averages narrows as it rises
    k = np.linspace(40, 4, len(t)).astype(int)
    c = np.cumsum(np.insert(n, 0, 0))
    idx = np.arange(len(t))
    lo = (c[idx + 1] - c[np.maximum(0, idx + 1 - k)]) / k
    tone = np.sin(2 * np.pi * np.cumsum(200 + 900 * (t / d) ** 2) / SR) * 0.25
    return (lo * 0.8 + tone) * (t / d) ** 2


def sweep_down(d):
    t = tvec(d)
    f = 120 * np.exp(-t * 0.7) + 28
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.minimum(1, t / 0.05) * np.exp(-t * 0.5)


def chime(midi, d=1.6):
    t = tvec(d)
    f = hz(midi)
    s = np.sin(2 * np.pi * f * t) + 0.45 * np.sin(2 * np.pi * 2.76 * f * t) * np.exp(-t * 4)
    return s * env(d, 0.002, curve=5)


def crumple(d=0.45):
    n = rng.standard_normal(int(d * SR))
    g = (rng.random(int(d * SR)) > 0.985).astype(float)
    g = np.convolve(g, np.hanning(240), 'same')
    return n * g * env(d, 0.002, curve=3) * 0.8


# ---------------------------------------------------------------- 0–4 s: the disk fills, the alert lands
add(pad([45, 52], 3.0, a=1.5), 0.0, 0.35)
for i in range(24):                                   # ticking that tightens toward the alert
    tt = 0.25 * i * (1 - 0.012 * i)
    if tt < 2.95:
        add(click(f=1800 + 40 * i), tt, 0.08 + 0.006 * i, pan=0.3 if i % 2 else -0.3)
for i in range(7):                                    # each block landing in the bar
    add(blip(57 + [0, 3, 5, 7, 10, 12, 15][i], 0.14), 0.3 + i * 0.32 + 0.28, 0.2)
add(riser(1.2), 1.8, 0.18)
add(boom(), 3.0, 0.9)
add(chime(81, 0.9), 3.0, 0.22, -0.2)                  # alert two-tone
add(chime(76, 0.9), 3.12, 0.18, 0.2)

# ---------------------------------------------------------------- 4–8 s: folders and question marks
motif = [69, 72, 76]                                  # A C E: the three-note motif
for b in range(4):
    for j, m in enumerate(motif):
        add(pluck(m - 12 + (5 if b == 2 else 0), 0.7), 4 + b * 1.0 + j * 0.25, 0.2, pan=-0.2 + 0.2 * j)
add(pad([45, 48, 52], 4.0), 4.0, 0.28)
enter = [0.05 + i * 0.16 for i in range(4)] + [1.45 + i * 0.16 for i in range(2)] + [2.85 + i * 0.16 for i in range(2)]
for i, e in enumerate(enter):
    add(blip(84 + (i % 3) * 2, 0.1), 4 + e + 0.4, 0.14, pan=-0.5 + i / 7)

# ---------------------------------------------------------------- 8–18 s: scan and results groove
roots = [45, 41, 48, 43, 45]                          # Am F C G Am, one per bar
for bar in range(5):
    t0 = 8 + bar * 2
    add(pad([roots[bar] + 12, roots[bar] + 19, roots[bar] + 24], 2.0, a=0.1), t0, 0.16)
    for beat in range(4):
        add(kick(), t0 + beat * BEAT, 0.55)
        add(hat(), t0 + beat * BEAT + 0.25, 0.5, pan=0.25)
        add(pluck(roots[bar] - 12, 0.4, bright=2), t0 + beat * BEAT, 0.22)
    for k in range(8):                                # sixteenth arpeggio from the motif
        m = motif[k % 3] + (roots[bar] - 45)
        add(pluck(m, 0.25), t0 + k * 0.25, 0.07, pan=0.4 if k % 2 else -0.4)
for i in range(14):                                   # scan ticks while planets light up
    add(click(f=3200, d=0.025), 8.2 + i * 0.36, 0.06, pan=-0.6 + i / 12)
for k, tt in enumerate((15.3, 15.8, 16.3)):           # callouts
    add(blip(88 + k * 3, 0.16), tt, 0.16)

# ---------------------------------------------------------------- 18–22 s: the black hole
add(riser(1.25), 17.0, 0.35)
add(boom(1.8), 18.25, 0.85)
add(sweep_down(3.3), 18.3, 0.55)
add(pad([33, 40], 3.6, a=0.3), 18.25, 0.3)
for k in range(10):                                   # debris falling in
    add(blip(96 - k * 2, 0.08), 18.6 + k * 0.28, 0.05, pan=np.sin(k) * 0.6)
add(chime(93, 2.0), 21.55, 0.28)                      # flash
add(chime(100, 2.0), 21.55, 0.12, 0.3)

# ---------------------------------------------------------------- 22–26 s: empty the Trash, space comes back
add(pad([48, 55, 60, 64], 4.0, a=0.2), 22.0, 0.3)
add(click(f=1500, d=0.04), 22.27, 0.25)
add(click(f=1500, d=0.04), 22.72, 0.25)
add(crumple(), 22.8, 0.6)
for k, m in enumerate([72, 76, 79, 84]):              # space freed: rising chime
    add(chime(m, 1.2), 23.35 + k * 0.125, 0.2, pan=-0.3 + 0.2 * k)
for beat in range(8):
    add(kick(), 22 + beat * BEAT, 0.35 if beat % 2 == 0 else 0.2)

# ---------------------------------------------------------------- 26–30 s: drag into Applications
add(pad([48, 52, 55, 60], 4.0, a=0.3), 26.0, 0.32)
for j, m in enumerate([72, 76, 79]):
    add(pluck(m, 0.9), 26.5 + j * 0.25, 0.18)
add(click(f=1200, d=0.04), 26.75, 0.2)
add(kick(0.5), 28.0, 0.7)
add(chime(84, 2.0), 28.0, 0.3)
add(chime(91, 2.0), 28.25, 0.16)
add(pluck(60 - 12, 1.8, bright=2), 28.0, 0.35)

# ---------------------------------------------------------------- master
mix = np.stack([L, R], axis=1)
mix = np.tanh(mix * 1.4) / np.tanh(1.4)               # gentle saturation glues the bus
fade = np.ones(N)
fade[-int(0.8 * SR):] = np.linspace(1, 0, int(0.8 * SR)) ** 2
mix *= fade[:, None]
rms = np.sqrt(np.mean(mix ** 2))
mix *= 10 ** (-16 / 20) / max(rms, 1e-9)              # about -16 dBFS RMS
peak = np.max(np.abs(mix))
if peak > 0.89:
    mix *= 0.89 / peak                                # keep true peak under about -1 dBFS
out = Path(__file__).with_name('music.wav')
sf.write(out, mix.astype(np.float32), SR, subtype='PCM_24')
print(f'wrote {out}  {len(mix) / SR:.2f}s  rms {20 * np.log10(np.sqrt(np.mean(mix ** 2))):.1f} dBFS  peak {20 * np.log10(np.max(np.abs(mix))):.1f} dBFS')
