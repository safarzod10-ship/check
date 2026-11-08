#!/usr/bin/env python3
"""Synthesised sound effects and ambience loops for DUSHANBE-X (16-bit mono WAV, 22050 Hz).

Run from the project root:  python3 tools/audiogen/audiogen.py
Writes audio/sfx/*.wav. Files named *_loop.wav are seamless loops (cross-faded ends).
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "audio", "sfx")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(42)


def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def lowpass(x, hz, order=2):
    b, a = signal.butter(order, hz / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def highpass(x, hz, order=2):
    b, a = signal.butter(order, hz / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def noise(sec):
    return rng.normal(0, 1, int(sec * SR))


def brown(sec):
    x = np.cumsum(noise(sec))
    x = highpass(x, 15)
    return x / (np.abs(x).max() + 1e-9)


def env_ad(n, attack, decay):
    a = int(attack * SR)
    e = np.exp(-np.arange(n) / (decay * SR))
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    return e


def norm(x, peak=0.85):
    return x / (np.abs(x).max() + 1e-9) * peak


def make_loop(fn, sec, fade=0.5):
    """Generate sec+fade seconds and crossfade the tail into the head -> seamless loop."""
    x = fn(sec + fade)
    n = int(sec * SR)
    f = int(fade * SR)
    out = x[:n].copy()
    w = np.linspace(0, 1, f)
    out[:f] = x[:f] * w + x[n:n + f] * (1 - w)
    return out


def write(name, x, peak=0.85):
    x = norm(np.asarray(x, np.float64), peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, f"{len(x) / SR:.2f}s")


# ---------------------------------------------------------------- loops
def engine(sec):
    # 4-cylinder idle ~ 900 rpm -> firing 30 Hz; integer cycles over 2 s keep it loopable
    t = t_axis(sec)
    f0 = 30.0
    x = signal.sawtooth(2 * np.pi * f0 * t) * 0.6
    x += np.sin(2 * np.pi * f0 * 2 * t) * 0.35 + np.sin(2 * np.pi * f0 * 0.5 * t) * 0.3
    pulses = (np.sin(2 * np.pi * f0 * t) > 0.6).astype(float)
    x += lowpass(pulses, 400) * 0.6
    x += lowpass(noise(sec), 700) * 0.15
    return lowpass(x, 1100, 3)


def wind(sec):
    n = noise(sec)
    x = bandpass(n, 150, 900)
    t = t_axis(sec)
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / 4.0 + 1.0) * np.sin(2 * np.pi * t / 2.7)
    whistle = bandpass(n, 900, 1300, 2) * (0.2 + 0.2 * np.sin(2 * np.pi * t / 3.3))
    return x * gust + whistle * 0.3


def rain(sec):
    x = highpass(noise(sec), 1500) * 0.5 + bandpass(noise(sec), 400, 3000) * 0.4
    drops = np.zeros(int(sec * SR))
    for _ in range(int(sec * 60)):
        p = rng.integers(0, len(drops) - 400)
        drops[p:p + 400] += np.sin(2 * np.pi * rng.uniform(1800, 4000) * np.arange(400) / SR) * \
            np.exp(-np.arange(400) / 60) * rng.uniform(0.2, 0.8)
    return x + drops * 0.6


def river(sec):
    t = t_axis(sec)
    x = bandpass(noise(sec), 200, 2500) * 0.7 + lowpass(noise(sec), 300) * 0.5
    bub = np.zeros(len(t))
    for _ in range(int(sec * 25)):
        p = rng.integers(0, len(t) - 800)
        f = rng.uniform(300, 900)
        k = np.arange(800)
        bub[p:p + 800] += np.sin(2 * np.pi * (f + k * 0.8) * k / SR) * np.exp(-k / 150) * rng.uniform(0.2, 0.6)
    return x * (0.85 + 0.15 * np.sin(2 * np.pi * t / 3.0)) + bub * 0.5


def chirp_bird(n_samples, f_lo, f_hi):
    k = np.arange(n_samples)
    sweep = f_lo + (f_hi - f_lo) * (0.5 + 0.5 * np.sin(np.linspace(0, rng.uniform(4, 12), n_samples)))
    phase = 2 * np.pi * np.cumsum(sweep) / SR
    return np.sin(phase) * np.sin(np.pi * k / n_samples) ** 2


def birds(sec, density=1.0):
    out = np.zeros(int(sec * SR))
    for _ in range(int(sec * 1.4 * density)):
        p = rng.integers(0, len(out) - 9000)
        notes = rng.integers(2, 6)
        base = rng.uniform(2200, 4200)
        for q in range(notes):
            ln = int(rng.uniform(0.05, 0.14) * SR)
            s = p + q * int(ln * 1.3)
            if s + ln < len(out):
                out[s:s + ln] += chirp_bird(ln, base * 0.85, base * 1.2) * rng.uniform(0.3, 1.0)
    return out + lowpass(noise(sec), 500) * 0.04


def city(sec):
    hum = lowpass(brown(sec), 220) * 1.0 + bandpass(noise(sec), 300, 1200) * 0.12
    t = t_axis(sec)
    hum *= 0.8 + 0.2 * np.sin(2 * np.pi * t / 5.0)
    # distant passing cars (doppler swells)
    for _ in range(int(sec / 2.5)):
        p = rng.integers(0, len(t) - SR * 3)
        n = SR * 3
        sw = np.sin(np.pi * np.arange(n) / n) ** 2
        hum[p:p + n] += lowpass(noise(3), 600)[:n] * sw * 0.5
    return hum + birds(sec, 0.25) * 0.25


def siren(sec):
    t = t_axis(sec)
    f = 650 + 350 * (0.5 + 0.5 * np.sin(2 * np.pi * t / sec))   # one wail per loop
    ph = 2 * np.pi * np.cumsum(f) / SR
    return signal.square(ph) * 0.3 + np.sin(ph) * 0.7


write("engine_loop", make_loop(engine, 2.0, 0.2), 0.8)
write("wind_loop", make_loop(wind, 8.0, 1.0), 0.7)
write("rain_loop", make_loop(rain, 6.0, 0.8), 0.7)
write("river_loop", make_loop(river, 6.0, 0.8), 0.7)
write("city_ambience_loop", make_loop(city, 10.0, 1.0), 0.7)
write("birds_loop", make_loop(birds, 10.0, 1.0), 0.6)
write("siren_loop", siren(2.0), 0.6)

# ---------------------------------------------------------------- one-shots
for i in range(4):
    n = int(0.16 * SR)
    x = lowpass(noise(0.16), rng.uniform(600, 1100)) * env_ad(n, 0.003, 0.03)
    x += np.sin(2 * np.pi * rng.uniform(70, 110) * np.arange(n) / SR) * env_ad(n, 0.002, 0.025) * 0.6
    write(f"footstep_{i + 1}", x, 0.6)

n = int(0.35 * SR)
k = np.arange(n)
punch = np.sin(2 * np.pi * (120 - 60 * k / n) * k / SR) * env_ad(n, 0.002, 0.07)
punch += lowpass(noise(0.35), 2500) * env_ad(n, 0.001, 0.025) * 0.8
write("punch_hit", punch, 0.9)

t = t_axis(0.7)
horn = signal.square(2 * np.pi * 415 * t) * 0.5 + signal.square(2 * np.pi * 520 * t) * 0.5
horn = lowpass(horn, 2500) * np.clip(np.minimum(t / 0.02, (0.7 - t) / 0.05), 0, 1)
write("horn", horn, 0.8)

n = int(0.4 * SR)
door = np.sin(2 * np.pi * 80 * np.arange(n) / SR) * env_ad(n, 0.002, 0.06)
door += highpass(noise(0.4), 2000) * env_ad(n, 0.001, 0.01) * 0.5
write("door", door, 0.8)

n = int(0.06 * SR)
click = np.sin(2 * np.pi * 1800 * np.arange(n) / SR) * env_ad(n, 0.001, 0.012)
write("ui_click", click, 0.5)

n = int(4.0 * SR)
thunder = lowpass(brown(4.0), 400)[:n] * env_ad(n, 0.02, 1.2)
crack = highpass(noise(4.0), 800)[:n] * env_ad(n, 0.001, 0.08) * 0.7
write("thunder", thunder + crack, 0.95)
