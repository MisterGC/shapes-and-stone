#!/usr/bin/env python3
"""Steam Deck bench - the HUD and the menus at the Deck's 1280x800 (issue #202).

Renders src/Game.qml with Clayground's clayrender at 1280x800, one PNG per
screen: the title, the lobby, the dungeon master's panel, the dungeon's
HUD with its controls hint, the knight panel, the pause menu, the fallen
screen and a seller's dialogue in the village - each with the keyboard and
with a pad in use, whose buttons the hints then name. On each screen
tests/deck/scan.js looks at every visible text on the last frame and the
bench checks that none is smaller than 12 px (the size Valve recommends
for the Deck, 9 px its least), none is elided or cut by a line limit and
none of the HUD's or a menu's reaches past the window's edge. With a pad
in use no text names a key, as the Deck has none.

Prints one PASS or FAIL line per check and exits with the number of
failures. The PNGs are for a person to look at: they go to --out, else to
a temporary directory the last line names.

Usage:
  run_deck.py [--renderer <clayrender>] [--out <dir>] [--only <screen>]

The renderer is --renderer, else build/bin/clayrender of this repository
(configure with -DCLAYGROUND_WITH_TOOLS=ON). It renders through the GPU
into a window never shown, so it needs a graphics session.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIZE = "1280x800"

DUNGEON = ["--eval", 'applyScenario("dungeon", 0, 7)',
           "--wait-for", 'levelType === "dungeon" && player !== null']
VILLAGE = ["--eval", 'applyScenario("village", 0, 7)',
           "--wait-for", 'levelType === "village" && player !== null']
# Beside the innkeeper, who sells more than one ware, with gold to buy
SELLER = ('for (let n of room.children) { if (n.objectName === "npc" && n.wares && n.wares.length >= 2) {'
          ' player.gold = 999; player.xWu = n.xWu + n.widthWu + 0.2; player.yWu = n.yWu;'
          ' n.interact(); break } }')
MASTER = ('openMaster({ index: 0, pos: dangerPosition, knights: knightsNow(), seed: 7,'
          ' go: (m, pos) => {} }); masterLoader.item.generate()')

# A key named in a hint: what a pad's hints must not say
KEYS = re.compile(r"W/S|A/D|WASD|\bEnter to\b|\(Enter\)|\bEsc\b|Backspace|\[[12E]\]|\([GCV]\)|\bC or\b")

SCREENS = [
    ("title", []),
    ("lobby", ["--set", 'screen="lobby"']),
    ("master", ["--eval", MASTER]),
    ("hud", DUNGEON),
    ("knight", DUNGEON + ["--set", "knightPanelOpen=true"]),
    ("pause", DUNGEON + ["--eval", "openMenu()"]),
    ("fallen", DUNGEON + ["--eval", "_fall()"]),
    ("dialogue", VILLAGE + ["--eval", SELLER]),
]


def render(renderer, scan, out, name, setup, pad):
    png = os.path.join(out, name + ".png")
    trace = os.path.join(out, name + ".jsonl")
    cmd = [renderer, os.path.join(REPO, "src", "Game.qml"), "--size", SIZE, "--out", png,
           "--set", "muted=true"]
    if pad:
        cmd += ["--set", "knightPad.inUse=true"]
    cmd += setup + ["--frames", "90", "--trace", scan, "--trace-out", trace]
    env = dict(os.environ)
    env["QT_DISABLE_SHADER_DISK_CACHE"] = "1"
    with open(os.path.join(out, name + ".log"), "w") as log:
        code = subprocess.call(cmd, cwd=REPO, env=env, stdout=log, stderr=subprocess.STDOUT)
    last = None
    try:
        with open(trace) as f:
            for line in f:
                row = json.loads(line)
                if "values" in row:
                    last = row["values"].get(scan)
    except (OSError, json.JSONDecodeError):
        pass
    return code, png, last


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--renderer", help="path to clayrender")
    ap.add_argument("--out", help="directory for the PNGs")
    ap.add_argument("--only", help="one screen by name, e.g. pause")
    args = ap.parse_args()

    renderer = args.renderer or os.path.join(REPO, "build", "bin", "clayrender")
    if not os.access(renderer, os.X_OK):
        print("FAIL no clayrender: pass --renderer or configure the build with "
              "-DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(1)
    out = os.path.abspath(args.out) if args.out else tempfile.mkdtemp(prefix="sas_deck_")
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "scan.js")) as f:
        scan = "\n".join(l for l in f.read().splitlines() if not l.startswith("//"))

    failures = 0

    def check(ok, what):
        nonlocal failures
        print(("PASS " if ok else "FAIL ") + what, flush=True)
        if not ok:
            failures += 1

    for name, setup in SCREENS:
        if args.only and args.only != name:
            continue
        for pad in (False, True):
            shot = name + ("-pad" if pad else "-keys")
            # clayrender exits 2 for QML warnings while it renders; the
            # game has known ones, the bench at hand is the picture
            code, png, seen = render(renderer, scan, out, shot, setup, pad)
            if code not in (0, 2) or not os.path.exists(png) or not isinstance(seen, dict):
                check(False, f"{shot}: renders at {SIZE} (clayrender exit {code})")
                continue
            check(True, f"{shot}: renders at {SIZE}, {len(seen['texts'])} texts on screen")
            check(not seen["small"], f"{shot}: no text under 12 px" +
                  ("" if not seen["small"] else ": " + "; ".join(seen["small"])))
            check(not seen["cut"], f"{shot}: no text elided" +
                  ("" if not seen["cut"] else ": " + "; ".join(seen["cut"])))
            check(not seen["outside"], f"{shot}: the HUD's and the menus' texts inside the window" +
                  ("" if not seen["outside"] else ": " + "; ".join(seen["outside"])))
            if pad:
                keys = [t for t in seen["texts"] if KEYS.search(t)]
                check(not keys, f"{shot}: no text names a key" + ("" if not keys else ": " + "; ".join(keys)))

    print(f"[Deck] {failures} failed; shots in {out}", flush=True)
    sys.exit(failures)


if __name__ == "__main__":
    main()
