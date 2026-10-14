#!/usr/bin/env python3
"""Makes the vein's sounds (issue #155) as short mono WAVs in src/assets.

Each is synthesised from noise and sines with a fixed seed, so running it
again writes the same files:

  deep_chink.wav    the pickaxe on stone: a heavy thud under an iron click
  deep_tink.wav     a clean strike's bright tink on the gem, a glassy bell
  deep_crumble.wav  the stone's crumble as the vein splits: grit falling off it
  deep_rumble.wav   a spawn hole waking (issue #157): a low rumble in the rock
  deep_groan.wav    a spawn hole's eyes opening: a drawn-out groan from inside
  deep_freed.wav    a traveller of the deep sent up (issue #158, #176): a warm low
                    major chord, the only one in the dungeon's sounds

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


def rumble(rng):
    seconds = 1.1
    buf = silence(seconds)
    # The rock's rumble: low noise swelling and dying away
    n = len(buf)
    low = lowpass(lowpass([rng.uniform(-1, 1) for _ in range(n)], 140), 140)
    for i in range(n):
        t = i / RATE
        buf[i] += 4.0 * low[i] * min(1, t / 0.18) * math.exp(-max(0, t - 0.25) / 0.35)
    # A few stones knocking loose in it
    for at in (0.06, 0.21, 0.38):
        m = int(0.05 * RATE)
        knock = lowpass([rng.uniform(-1, 1) * math.exp(-i / (0.012 * RATE)) for i in range(m)], 380)
        add(buf, at + rng.uniform(0, 0.03), knock, 1.5)
    return fade_out(buf, 0.2)


def groan(rng):
    seconds = 1.4
    n = int(seconds * RATE)
    # A throat: a buzzing tone sliding down from 96 to 68 Hz, wavering
    voice, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = 96 - 28 * (t / seconds) + 2.5 * math.sin(2 * math.pi * 5.5 * t)
        phase += f / RATE
        saw = 2 * (phase % 1) - 1
        voice.append(saw + 0.3 * rng.uniform(-1, 1))
    # Through the mouth of the hole: two dark formants
    shaped = [a + 0.6 * b for a, b in zip(bandpass(voice, 420, 3.0), bandpass(voice, 880, 4.0))]
    for i in range(n):
        t = i / RATE
        shaped[i] *= min(1, t / 0.2) * (1 - 0.4 * t / seconds)
    return fade_out(shaped, 0.35)


def freed(rng):
    seconds = 2.2
    buf = silence(seconds)
    # A warm low major chord, C3 E3 G3 C4, its notes a few milliseconds
    # apart like a soft strum: few soft partials, a slow swell and a long
    # fade, slightly detuned pairs for warmth
    for k, f0 in enumerate([130.81, 164.81, 196.0, 261.63]):
        at = 0.018 * k
        n = len(buf) - int(at * RATE)
        note = []
        for i in range(n):
            t = i / RATE
            env = min(1, t / 0.12) * math.exp(-t / 0.9)
            v = 0.0
            for ratio, gain in [(1.0, 1.0), (2.0, 0.32), (3.0, 0.12)]:
                v += gain * (math.sin(2 * math.pi * f0 * ratio * t)
                             + math.sin(2 * math.pi * f0 * ratio * 1.003 * t + 0.7)) / 2
            note.append(v * env)
        add(buf, at, note, 0.6 if k < 3 else 0.4)
    return fade_out(lowpass(buf, 1800), 0.5)


if __name__ == "__main__":
    for name, make, peak in [("deep_chink.wav", chink, 0.8), ("deep_tink.wav", tink, 0.6),
                             ("deep_crumble.wav", crumble, 0.6), ("deep_rumble.wav", rumble, 0.8),
                             ("deep_groan.wav", groan, 0.6), ("deep_freed.wav", freed, 0.7)]:
        write(name, make(random.Random(name)), peak)
