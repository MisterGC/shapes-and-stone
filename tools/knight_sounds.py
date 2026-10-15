#!/usr/bin/env python3
"""Makes the knight's own sounds as short mono WAVs in src/assets.

Each is synthesised from noise and sines with a fixed seed, so running it
again writes the same files:

  potion_drink.wav  a health potion drunk: the cork pulled, three gulps and
                    a breath let out
  heartbeat.wav     the knight low on health: one beat of its heart, a deep
                    lub and a softer dub

  python3 tools/knight_sounds.py
"""

import math
import random

from camp_sounds import RATE, add, bandpass, fade_out, lowpass, silence, write


def drink(rng):
    buf = silence(1.35)
    # The cork: a short hollow pop, a falling tone over a click of noise
    n = int(0.05 * RATE)
    pop = []
    for i in range(n):
        t = i / RATE
        f = 900 - 5000 * t
        pop.append(math.sin(2 * math.pi * f * t) * math.exp(-t / 0.012))
    add(buf, 0.0, pop, 0.5)
    add(buf, 0.0, bandpass([rng.uniform(-1, 1) * math.exp(-i / (0.004 * RATE)) for i in range(n)],
                           1400, 2.0), 0.4)
    # Three gulps: a throat's low bloop rising in pitch, under a wet slosh
    for k, at in enumerate([0.22, 0.48, 0.74]):
        n = int(0.16 * RATE)
        f0 = 150 + 12 * k + rng.uniform(-6, 6)
        gulp = []
        phase = 0.0
        for i in range(n):
            t = i / RATE
            f = f0 * (1 + 1.4 * min(1, t / 0.07))
            phase += 2 * math.pi * f / RATE
            env = min(1, t / 0.008) * math.exp(-t / 0.045)
            gulp.append(math.sin(phase) * env)
        add(buf, at, gulp, 0.9)
        slosh = bandpass([rng.uniform(-1, 1) * min(1, i / (0.01 * RATE)) * math.exp(-i / (0.035 * RATE))
                          for i in range(n)], 700, 1.5)
        add(buf, at + 0.01, slosh, 0.35)
    # The breath let out after: soft, airy, falling away
    n = int(0.42 * RATE)
    breath = [rng.uniform(-1, 1) * min(1, i / (0.06 * RATE)) * math.exp(-i / (0.16 * RATE)) for i in range(n)]
    add(buf, 0.92, lowpass(bandpass(breath, 900, 0.7), 2200), 0.5)
    return fade_out(buf, 0.1)


def heartbeat(rng):
    buf = silence(0.6)
    for at, f0, gain in [(0.0, 58, 1.0), (0.17, 72, 0.6)]:
        n = int(0.16 * RATE)
        thump = []
        for i in range(n):
            t = i / RATE
            f = f0 * (1 + 0.6 * math.exp(-t / 0.02))
            env = min(1, t / 0.006) * math.exp(-t / 0.05)
            thump.append(math.sin(2 * math.pi * f * t) * env)
        add(buf, at, thump, gain)
        add(buf, at, lowpass([rng.uniform(-1, 1) * math.exp(-i / (0.01 * RATE)) for i in range(n)], 180),
            0.5 * gain)
    return fade_out(lowpass(buf, 400), 0.1)


if __name__ == "__main__":
    for name, make, peak in [("potion_drink.wav", drink, 0.7), ("heartbeat.wav", heartbeat, 0.8)]:
        write(name, make(random.Random(name)), peak)
