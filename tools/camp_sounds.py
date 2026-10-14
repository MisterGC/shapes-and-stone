#!/usr/bin/env python3
"""Makes the camp's near sounds (issue #147) as short mono WAVs in src/assets.

Each is synthesised from noise and sines with a fixed seed, so running it
again writes the same files:

  camp_crackle.wav  the campfire: a few dry pops over a soft breath
  camp_anvil.wav    the smith's hammer on the anvil: a short metal ring
  camp_drip.wav     water dripping in the grotto: a plink rising in pitch
  camp_creak.wav    a cart's wheel in the miners' hall: wood on wood
  camp_hiss.wav     embers in the ember camp: a swell of hiss with sparks

The game plays them at their source, pitched a little each time
(Balance.camp.sounds), so a few files make a camp that never repeats.

  python3 tools/camp_sounds.py
"""

import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "assets")


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def add(buf, at, samples, gain=1.0):
    i0 = int(at * RATE)
    for i, s in enumerate(samples):
        if i0 + i < len(buf):
            buf[i0 + i] += s * gain


def highpass(samples, cutoff):
    a = 1.0 / (1.0 + 2 * math.pi * cutoff / RATE)
    out, prev_x, prev_y = [], 0.0, 0.0
    for x in samples:
        prev_y = a * (prev_y + x - prev_x)
        prev_x = x
        out.append(prev_y)
    return out


def lowpass(samples, cutoff):
    k = 1.0 - math.exp(-2 * math.pi * cutoff / RATE)
    out, y = [], 0.0
    for x in samples:
        y += k * (x - y)
        out.append(y)
    return out


def bandpass(samples, centre, q):
    # A two-pole resonator (RBJ band-pass, constant peak gain)
    w = 2 * math.pi * centre / RATE
    alpha = math.sin(w) / (2 * q)
    b0, b2 = alpha, -alpha
    a0, a1, a2 = 1 + alpha, -2 * math.cos(w), 1 - alpha
    out, x1, x2, y1, y2 = [], 0.0, 0.0, 0.0, 0.0
    for x in samples:
        y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, x, y1, y
        out.append(y)
    return out


def fade_out(samples, seconds):
    n = min(len(samples), int(seconds * RATE))
    for i in range(n):
        samples[len(samples) - n + i] *= 1 - i / n
    return samples


def write(name, samples, peak):
    top = max(abs(s) for s in samples) or 1.0
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / top * peak * 32767)) for s in samples))
    print("wrote", os.path.relpath(path), "%.2f s" % (len(samples) / RATE))


def crackle(rng):
    buf = silence(0.45)
    # A soft breath of the flame under the pops
    breath = lowpass([rng.uniform(-1, 1) for _ in buf], 400)
    for i in range(len(buf)):
        t = i / len(buf)
        buf[i] += breath[i] * 0.25 * math.sin(math.pi * t)
    for _ in range(5):
        n = int(rng.uniform(0.002, 0.007) * RATE)
        pop = [rng.uniform(-1, 1) * math.exp(-i / (n / 5)) for i in range(n)]
        add(buf, rng.uniform(0.0, 0.38), highpass(pop, 1500), rng.uniform(0.4, 1.0))
    return fade_out(buf, 0.03)


def anvil(rng):
    buf = silence(1.4)
    f0 = 830.0
    # A struck bar's partials, inharmonic, the high ones dying first
    for ratio, gain, decay in [(1.0, 1.0, 0.45), (2.76, 0.55, 0.25), (5.40, 0.35, 0.12), (8.93, 0.2, 0.06)]:
        for i in range(len(buf)):
            t = i / RATE
            buf[i] += gain * math.sin(2 * math.pi * f0 * ratio * t + ratio) * math.exp(-t / decay)
    n = int(0.006 * RATE)
    add(buf, 0.0, highpass([rng.uniform(-1, 1) * (1 - i / n) for i in range(n)], 2000), 1.2)
    return fade_out(buf, 0.1)


def drip(rng):
    buf = silence(0.35)
    phase = 0.0
    for i in range(len(buf)):
        t = i / RATE
        f = 700 + 900 * (1 - math.exp(-t / 0.02))
        phase += 2 * math.pi * f / RATE
        buf[i] = math.sin(phase) * math.exp(-t / 0.035) * min(1, t / 0.002)
    # The cave answers once, softer
    echo = [s * 0.25 for s in buf]
    add(buf, 0.11, echo)
    return fade_out(buf, 0.05)


def creak(rng):
    seconds = 0.9
    buf = silence(seconds)
    # Stick and slip: a train of clicks whose rate wanders
    t, rate = 0.0, 45.0
    while t < seconds:
        env = math.sin(math.pi * t / seconds) ** 0.7
        add(buf, t, [1.0, -0.6, 0.3], env * rng.uniform(0.7, 1.0))
        rate = max(25, min(70, rate + rng.uniform(-6, 6)))
        t += 1 / rate
    body = bandpass(buf, 750, 6)
    wood = bandpass(buf, 1900, 8)
    return fade_out([b + 0.4 * w for b, w in zip(body, wood)], 0.08)


def hiss(rng):
    seconds = 1.6
    buf = highpass([rng.uniform(-1, 1) for _ in range(int(seconds * RATE))], 2500)
    for i in range(len(buf)):
        t = i / RATE
        swell = min(1, t / 0.4) * math.exp(-max(0, t - 0.4) / 0.45)
        buf[i] *= 0.35 * swell
    for _ in range(4):
        n = int(rng.uniform(0.002, 0.004) * RATE)
        add(buf, rng.uniform(0.1, 1.0), highpass([rng.uniform(-1, 1) * (1 - i / n) for i in range(n)], 3000),
            rng.uniform(0.3, 0.6))
    return fade_out(buf, 0.1)


if __name__ == "__main__":
    for name, make, peak in [("camp_crackle.wav", crackle, 0.8), ("camp_anvil.wav", anvil, 0.7),
                             ("camp_drip.wav", drip, 0.7), ("camp_creak.wav", creak, 0.7),
                             ("camp_hiss.wav", hiss, 0.6)]:
        write(name, make(random.Random(name)), peak)
