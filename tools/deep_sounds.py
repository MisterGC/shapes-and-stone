#!/usr/bin/env python3
"""Makes the vein's sounds (issue #155) as short mono WAVs in src/assets.

Each is synthesised from noise and sines with a fixed seed, so running it
again writes the same files:

  deep_chink.wav    the pickaxe on stone: a heavy thud under an iron click
  deep_tink.wav     a clean strike's bright tink on the gem, a glassy bell
  deep_crumble.wav  an off-beat strike's crumble: grit falling off the stone

The game plays the tink a pentatonic step higher with each clean strike,
and three times, a fifth and an octave apart, as the gem's chime
(Balance.deep), so one file plays the whole phrase.

  python3 tools/deep_sounds.py
"""

import math
import random

from camp_sounds import RATE, add, bandpass, fade_out, highpass, lowpass, silence, write


def chink(rng):
    buf = silence(0.4)
    # The stone's thud: low noise, gone in a few tens of milliseconds
    n = int(0.08 * RATE)
    thud = lowpass([rng.uniform(-1, 1) * math.exp(-i / (0.018 * RATE)) for i in range(n)], 260)
    add(buf, 0.0, thud, 6.0)
    # The pick's iron: a short click of inharmonic partials
    for ratio, gain, decay in [(1.0, 0.5, 0.05), (2.41, 0.3, 0.03), (3.93, 0.2, 0.018)]:
        for i in range(len(buf)):
            t = i / RATE
            buf[i] += gain * math.sin(2 * math.pi * 1250 * ratio * t + ratio) * math.exp(-t / decay)
    # Grit off the point of contact
    n = int(0.03 * RATE)
    add(buf, 0.002, highpass([rng.uniform(-1, 1) * (1 - i / n) for i in range(n)], 1800), 0.5)
    return fade_out(buf, 0.05)


def tink(rng):
    buf = silence(0.75)
    f0 = 1046.5
    # A small glass bell: few partials, the high ones dying first, a soft
    # click of an attack
    for ratio, gain, decay in [(1.0, 1.0, 0.28), (2.32, 0.35, 0.12), (4.25, 0.15, 0.05)]:
        for i in range(len(buf)):
            t = i / RATE
            buf[i] += gain * math.sin(2 * math.pi * f0 * ratio * t) * math.exp(-t / decay) * min(1, t / 0.0015)
    return fade_out(buf, 0.08)


def crumble(rng):
    seconds = 0.45
    buf = silence(seconds)
    # Grains of grit, many at first, fewer as the stone settles
    t = 0.0
    while t < seconds - 0.01:
        n = int(rng.uniform(0.001, 0.004) * RATE)
        grain = [rng.uniform(-1, 1) * (1 - i / n) for i in range(n)]
        add(buf, t, grain, rng.uniform(0.3, 1.0) * math.exp(-t / 0.15))
        t += rng.uniform(0.004, 0.02) * (1 + 4 * t)
    return fade_out(bandpass(buf, 1400, 1.2), 0.06)


if __name__ == "__main__":
    for name, make, peak in [("deep_chink.wav", chink, 0.8), ("deep_tink.wav", tink, 0.6),
                             ("deep_crumble.wav", crumble, 0.6)]:
        write(name, make(random.Random(name)), peak)
