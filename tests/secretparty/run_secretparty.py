#!/usr/bin/env python3
"""Secret party bench - proves that in a session a secret door opened on
one screen is open on every screen, its room and cache with it, and that
the host owns the secrets (issue #128).

Starts tests/secretparty/Sandbox.qml twice in Clayground's live loader, as
two processes (a host and a joiner), connects them over Local or Cloud
signaling and starts the game on the first seed from --seed whose first
dungeon hides a secret room. The host's enemies stand still. Then:

- both screens hide the same secret rooms on the same cells, every one
  closed and rock
- the joiner's knight dashes into the wall one tile off along it: it
  stays closed on both screens
- the joiner's knight dashes into the cracked face: it is open on both
  screens, its door and room floor and its cache standing on both
- both screens count one secret found this run

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_secretparty.py [--loader <clayliveloader>] [--mode local|cloud] [--seed 424242]

Prints one PASS or FAIL line per check and exits with the number of failed
checks (100: the bench could not get to its end). The temp dir with both
loaders' logs is kept after a failed run.
"""

import argparse
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
        print("[SecretParty]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_secretparty_")
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
    print(f"[SecretParty] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "secretparty")
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

        seed = H.eval1(f"seedWithSecret({args.seed})")
        if not isinstance(seed, (int, float)) or seed < 0:
            return abort(f"no seed from {args.seed} hides a secret room in its first dungeon")
        seed = int(seed)
        check(True, f"seed {seed} hides a secret room in its first dungeon")
        H.eval([f"startGame({seed})"])
        if not wait_for(lambda: H.eval1("inRun()") is True and J.eval1("inRun()") is True, 30):
            return abort("the session did not reach the dungeon")
        H.eval1("halt()")
        for i in (H, J):
            i.eval(["standUp()"])
        return open_secret(H, J, check)
    except TimeoutError as e:
        return abort(str(e))


def both(H, J, cell, key, value, timeout=5):
    """Whether both screens show the secret on cell with key at value
    within timeout s"""
    def shows(i):
        s = i.json(f"secretOf('{cell}')")
        return s is not None and s.get(key) == value
    return wait_for(lambda: shows(H) and shows(J), timeout)


def open_secret(H, J, check):
    hs, js = H.json("secrets()"), J.json("secrets()")
    cells = [s["cell"] for s in hs]
    if not check(len(hs) > 0 and cells == [s["cell"] for s in js]
                 and all(not s["open"] and s["rock"] for s in hs + js),
                 f"both screens hide the same {len(hs)} secret room(s) on {', '.join(cells)}, "
                 f"closed and rock (joiner {len(js)})"):
        return 100
    a = cells[0]

    # One tile off along the wall: nothing
    J.eval1(f"standBefore('{a}', 1)")
    J.eval1(f"dashInto('{a}')")
    time.sleep(1.0)
    h, j = H.json(f"secretOf('{a}')"), J.json(f"secretOf('{a}')")
    check(not h["open"] and not j["open"] and h["rock"] and j["rock"],
          f"the joiner's dash into the wall one tile off leaves the secret on {a} closed on both screens")

    # Into the cracked face: open on both, its room and cache with it
    J.eval1(f"standBefore('{a}', 0)")
    check(J.eval1(f"dashInto('{a}')") is True, f"the joiner's knight dashes into the cracked face on {a}")
    opened = both(H, J, a, "open", True)
    h, j = H.json(f"secretOf('{a}')"), J.json(f"secretOf('{a}')")
    check(opened, f"it is open on both screens (host {h['open']}, joiner {j['open']})")
    check(h["floor"] and j["floor"], "its door and room are floor on both screens")
    check(h["cache"] > 0 and h["cache"] == j["cache"],
          f"its cache stands on both screens (host {h['cache']}, joiner {j['cache']})")
    check(H.eval1("found()") == 1 and J.eval1("found()") == 1,
          f"both screens count one secret found (host {H.eval1('found()')}, joiner {J.eval1('found()')})")
    return 0


if __name__ == "__main__":
    main()
