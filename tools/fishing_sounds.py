#!/usr/bin/env python3
"""Makes the camp pond's fishing sounds as short mono WAVs in src/assets.

Each is synthesised from noise and sines with a fixed seed, so running it
again writes the same files:

  fish_cast.wav    the rod swung and the line whipping out
  fish_plop.wav    the bobber landing on the water
  fish_plip.wav    a nibble: a tiny tug at the bobber
  fish_bite.wav    the bite: the bobber pulled under, a deep plop
  fish_click.wav   one tick of the reel's ratchet
  fish_splash.wav  the fish thrashing at the surface
  fish_land.wav    the fish lifted out: a splash and a wet flop
  fish_snap.wav    the line snapping
  cat_purr.wav     the cave cat purring over its fish

  python3 tools/fishing_sounds.py
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


def noise(rng, seconds, decay, attack=0.002):
    n = int(seconds * RATE)
    return [rng.uniform(-1, 1) * min(1, i / (attack * RATE)) * math.exp(-i / (decay * RATE)) for i in range(n)]


def droplet(f0, seconds, decay, rise):
    n = int(seconds * RATE)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * f0 * (1 + rise * min(1, t / seconds)) / RATE
        out.append(math.sin(phase) * math.exp(-t / decay) * min(1, t / 0.002))
    return out


def cast(rng):
    buf = silence(0.45)
    # The swish: band noise sweeping up and away
    n = int(0.32 * RATE)
    sw = [rng.uniform(-1, 1) * math.sin(math.pi * i / n) ** 2 for i in range(n)]
    add(buf, 0.0, bandpass(sw, 1500, 1.2), 0.6)
    # The reel letting line run: fast faint ticks
    for k in range(9):
        add(buf, 0.05 + k * 0.032, highpass(noise(rng, 0.008, 0.002), 3000), 0.18 * (1 - k / 10))
    return fade_out(buf, 0.06)


def plop(rng):
    buf = silence(0.35)
    add(buf, 0.0, droplet(420, 0.12, 0.03, 1.2), 0.8)
    add(buf, 0.0, bandpass(noise(rng, 0.2, 0.05), 900, 1.0), 0.3)
    return fade_out(lowpass(buf, 3500), 0.05)


def plip(rng):
    buf = silence(0.15)
    add(buf, 0.0, droplet(900, 0.06, 0.015, 0.8), 0.6)
    return fade_out(buf, 0.03)


def bite(rng):
    buf = silence(0.5)
    add(buf, 0.0, droplet(230, 0.2, 0.06, 1.6), 1.0)
    add(buf, 0.01, bandpass(noise(rng, 0.35, 0.09), 700, 0.9), 0.45)
    for k in range(4):
        add(buf, 0.06 + rng.uniform(0, 0.15), droplet(rng.uniform(900, 1600), 0.05, 0.012, 0.5), 0.25)
    return fade_out(lowpass(buf, 4000), 0.08)


def click(rng):
    buf = silence(0.03)
    add(buf, 0.0, bandpass(noise(rng, 0.02, 0.003), 2600, 2.5), 0.9)
    return buf


def splash(rng):
    buf = silence(0.55)
    add(buf, 0.0, bandpass(noise(rng, 0.5, 0.12, 0.01), 1100, 0.7), 0.8)
    for k in range(7):
        add(buf, rng.uniform(0, 0.3), droplet(rng.uniform(600, 1500), 0.06, 0.015, 0.6), 0.3)
    return fade_out(lowpass(buf, 5000), 0.1)


def land(rng):
    buf = silence(0.8)
    add(buf, 0.0, bandpass(noise(rng, 0.45, 0.1, 0.005), 1000, 0.8), 0.7)
    for k in range(5):
        add(buf, rng.uniform(0.02, 0.25), droplet(rng.uniform(700, 1400), 0.05, 0.014, 0.6), 0.3)
    # The flop on the bank: a soft wet thud
    add(buf, 0.42, lowpass(noise(rng, 0.12, 0.025), 500), 1.0)
    add(buf, 0.42, droplet(140, 0.1, 0.03, -0.3), 0.6)
    return fade_out(buf, 0.1)


def snap(rng):
    buf = silence(0.45)
    add(buf, 0.0, highpass(noise(rng, 0.02, 0.004), 2000), 0.8)
    # The slack line's twang, falling
    n = int(0.4 * RATE)
    tw, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * (520 - 300 * t) / RATE
        tw.append((math.sin(phase) + 0.3 * math.sin(2.01 * phase)) * math.exp(-t / 0.09))
    add(buf, 0.005, tw, 0.5)
    return fade_out(buf, 0.06)


def purr(rng):
    seconds = 1.6
    buf = silence(seconds)
    n = int(seconds * RATE)
    base = lowpass(noise(rng, seconds, 10.0, 0.05), 300)
    for i in range(n):
        t = i / RATE
        # Twenty-five pulses a second, in on the breath and out on it
        pulse = 0.5 + 0.5 * math.sin(2 * math.pi * 25 * t)
        breath = 0.6 + 0.4 * math.sin(2 * math.pi * t / 0.8)
        env = min(1, t / 0.15) * min(1, (seconds - t) / 0.3)
        buf[i] += base[i] * pulse * breath * env
    return fade_out(buf, 0.2)


if __name__ == "__main__":
    for name, make, peak in [("fish_cast.wav", cast, 0.5), ("fish_plop.wav", plop, 0.6),
                             ("fish_plip.wav", plip, 0.4), ("fish_bite.wav", bite, 0.75),
                             ("fish_click.wav", click, 0.35), ("fish_splash.wav", splash, 0.6),
                             ("fish_land.wav", land, 0.7), ("fish_snap.wav", snap, 0.55),
                             ("cat_purr.wav", purr, 0.6)]:
        write(name, make(random.Random(name)), peak)
