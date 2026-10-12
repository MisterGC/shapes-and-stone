#!/usr/bin/env python3
"""Master party bench - proves that in a session the joiner enters the
dungeon the host's dungeon master generated (issue #142).

Starts tests/masterparty/Sandbox.qml twice in Clayground's live loader, as
two processes (a host and a joiner), connects them over Local or Cloud
signaling. The host ticks Dungeon Master and sets 6 rooms and 2 enemies
per room, the joiner ticks it too (a joiner never has the panel). Then:

- the host starts the game: the panel is up on the host, the joiner
  waits outside the dungeon
- the host generates twice (a new seed) and goes: both screens build the
  dungeon the panel showed, the same grid, rooms and features on the
  rolled seed, the host's enemies where the preview had them and as many
  on the joiner's screen
- out to the village, no panel; out of it the panel is up on the host and
  the joiner waits in the village; the host sets 7 rooms, generates and
  goes: both screens build that dungeon

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_masterparty.py [--loader <clayliveloader>] [--mode local|cloud] [--seed 424242]

Prints one PASS or FAIL line per check and exits with the number of failed
checks (100: the bench could not get to its end). The temp dir with both
loaders' logs is kept after a failed run.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                "goagain"))
from run_goagain import Inspect, find_loader, stop, wait_for  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SETTINGS = {"rooms": 6, "enemies": 2}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--loader", help="path to clayliveloader")
    ap.add_argument("--mode", choices=("local", "cloud"), default="local",
                    help="signaling: Local (LAN) or Cloud (PeerJS)")
    ap.add_argument("--seed", type=int, default=424242, help="the run's seed")
    args = ap.parse_args()

    failures = 0

    def check(ok, what):
        nonlocal failures
        print("[MasterParty]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_masterparty_")
    procs = {}
    aborted = True
    try:
        aborted = run(args, loader, tmp, procs, check) == 100
    finally:
        stop(procs)
        code = 100 if aborted else failures
        if code != 0:
            print("Logs kept at:", tmp, file=sys.stderr)
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    print(f"[MasterParty] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "masterparty")
    shutil.copytree(os.path.dirname(os.path.abspath(__file__)), sandbox_dir, ignore=skip)
    sbx = os.path.join(sandbox_dir, "Sandbox.qml")

    env = dict(os.environ)
    env.setdefault("QT_QPA_PLATFORM", "offscreen")
    for n in ("host", "joiner"):
        log = open(os.path.join(tmp, f"{n}.log"), "w")
        procs[n] = subprocess.Popen([loader, "--sbx", sbx, "--instance", n],
                                    cwd=os.path.dirname(loader), env=env,
                                    stdout=log, stderr=subprocess.STDOUT)
    H, J = Inspect(sandbox_dir, "host"), Inspect(sandbox_dir, "joiner")
    procs["inspect"] = (H, J)

    def abort(what):
        check(False, what)
        return 100

    try:
        if not (H.wait_phase("ready") and J.wait_phase("ready")):
            return abort("the two instances did not load")
        local = "true" if args.mode == "local" else "false"
        for i in (H, J):
            if i.eval1(f"configure({local})") is not True:
                return abort("no Network in the game's session")
        H.eval(["hostUp()"])
        if not wait_for(lambda: H.eval1("netId") not in (None, ""), 30):
            return abort("the host got no network code")
        code = H.eval1("netId")
        J.eval([f"joinNet('{code}')"])
        if not wait_for(lambda: J.eval1("connected") is True and H.eval1("nodeCount") >= 2, 40):
            return abort(f"the joiner did not connect to {code}")
        check(True, f"two processes connected over {args.mode} signaling ({code})")

        settings = json.dumps(SETTINGS)
        check(H.eval1(f"master(true, '{settings}')") is True, f"the host ticks Dungeon Master, sets {settings}")
        J.eval1("master(true, '')")
        return first_dungeon(args, H, J, check)
    except TimeoutError as e:
        return abort(str(e))


def same_layout(a, b):
    return a["grid"] == b["grid"] and a["rooms"] == b["rooms"] and a["features"] == b["features"]


def enter(H, J, check, what):
    """The host generates twice and goes; both screens build what it showed"""
    first = H.eval1("generate()")
    second = H.eval1("generate()")
    check(first is not None and second is not None and first != second,
          f"{what}: the host's G shows a dungeon, G again a new seed ({first} -> {second})")
    shown = H.json("shown()")
    H.eval1("go()")
    if not wait_for(lambda: H.eval1("inRun()") is True and J.eval1("inRun()") is True, 30):
        check(False, f"{what}: both knights in the dungeon after Go "
              f"(host {H.json('where()')}, joiner {J.json('where()')})")
        return None
    H.eval1("halt()")
    for i in (H, J):
        i.eval(["standUp()"])
    hb, jb = H.json("built()"), J.json("built()")
    check(hb["master"] is not None and hb["master"] == jb["master"] and hb["seed"] == shown["seed"] == jb["seed"],
          f"{what}: both screens build with the host's overrides on the shown seed "
          f"({json.dumps(jb['master'])}, seed {jb['seed']})")
    check(same_layout(hb, shown), f"{what}: the host's dungeon is the one its panel showed "
          f"({len(hb['rooms'])} rooms, {len(hb['features'])} features)")
    check(same_layout(jb, shown), f"{what}: the joiner enters the dungeon the host generated "
          f"({len(jb['rooms'])} rooms, {len(jb['features'])} features)")
    check(hb["enemies"] == shown["enemies"],
          f"{what}: the host's enemies stand where the preview had them ({len(hb['enemies'])})")
    joiner_foes = wait_for(lambda: J.eval1("game.enemies.filter(e => e && !e.destroyed).length")
                           == len(shown["enemies"]), 10)
    check(joiner_foes, f"{what}: the joiner's screen shows the host's {len(shown['enemies'])} enemies")
    check(abs(hb["danger"] - shown["danger"]) < 1e-9 and abs(jb["danger"] - shown["danger"]) < 1e-9,
          f"{what}: both at the shown danger {shown['danger']:.3f}")
    return shown


def first_dungeon(args, H, J, check):
    if not check(H.eval1(f"startGame({args.seed})") is True,
                 "the host starts the game: its panel is up"):
        return 100
    time.sleep(1.0)
    jw = J.json("where()")
    check(J.eval1("panelUp()") is False and not (jw["screen"] == "game" and jw["knight"]),
          f"the joiner waits outside the dungeon, without a panel ({jw})")
    if enter(H, J, check, "first dungeon") is None:
        return 100

    # Out to the village: no panel there
    check(H.eval1("advance()") is False, "out of the dungeon into the village the host has no panel")
    if not wait_for(lambda: H.json("where()")["type"] == "village" and J.json("where()")["type"] == "village"
                    and H.json("where()")["knight"] and J.json("where()")["knight"], 30):
        check(False, "both knights reach the village")
        return 100
    check(True, "both knights reach the village")

    # Out of the village: the panel on the host, the joiner waits
    check(H.eval1("advance()") is True, "out of the village the host's panel is up")
    time.sleep(1.0)
    jw = J.json("where()")
    check(jw["type"] == "village" and jw["level"] == 1, f"the joiner waits in the village ({jw})")
    turned = json.loads(H.eval1("turn('rooms', 1)") or "null")
    check(turned == dict(SETTINGS, rooms=SETTINGS["rooms"] + 1), f"the host turns the rooms up to 7 ({turned})")
    shown = enter(H, J, check, "second dungeon")
    if shown is None:
        return 100
    check(len(shown["rooms"]) == SETTINGS["rooms"] + 1, f"the second dungeon has the 7 rooms set ({len(shown['rooms'])})")
    return 0


if __name__ == "__main__":
    main()
