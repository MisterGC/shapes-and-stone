#!/usr/bin/env python3
"""Spike party bench - proves that in a session a spike plate set off on one
screen is sprung on every screen, and that each knight's own game judges
the spikes on it (issue #124).

Starts tests/spikeparty/Sandbox.qml twice in Clayground's live loader, as
two processes (a host and a joiner), connects them over Local or Cloud
signaling and starts the game on a fixed seed. The host's enemies stand
still. Then:

- both screens lay the same spike plates on the same cells, all armed
- the joiner's knight stands on a plate: its own game takes the spikes'
  damage, the host's screen shows the plate sprung and the joiner's HP
  as the joiner's game has it, the host's knight untouched
- the host's knight stands on another: the same the other way round
- the joiner's knight steps on a third and dashes off at the click: it
  takes nothing, the plate sprung on both screens
- both knights stand on a fourth at once: each game takes the damage from
  its own knight once
- the joiner's knight steps back onto its first plate: nothing more

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_spikeparty.py [--loader <clayliveloader>] [--mode local|cloud] [--seed 424242]

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
        print("[SpikeParty]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_spikeparty_")
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
    print(f"[SpikeParty] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "spikeparty")
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

        H.eval([f"startGame({args.seed})"])
        if not wait_for(lambda: H.eval1("inRun()") is True and J.eval1("inRun()") is True, 30):
            return abort("the session did not reach the dungeon")
        H.eval1("halt()")
        for i in (H, J):
            i.eval(["fresh()"])
        return spikes(H, J, check)
    except TimeoutError as e:
        return abort(str(e))


def phase(inst, cell):
    return next((q["phase"] for q in inst.json("plates()") if q["cell"] == cell), None)


def sprung_on_both(H, J, cell):
    return wait_for(lambda: phase(H, cell) == "sprung" and phase(J, cell) == "sprung", 5)


def spikes(H, J, check):
    hp_, jp = H.json("plates()"), J.json("plates()")
    if not check(len(hp_) >= 4 and sorted(q["cell"] for q in hp_) == sorted(q["cell"] for q in jp)
                 and all(q["phase"] == "armed" for q in hp_ + jp),
                 f"both screens lay the same {len(hp_)} spike plates on the same cells, all armed "
                 f"(joiner {len(jp)})"):
        return 100
    dmg = H.eval1("damage()")
    if not check(dmg > 0 and dmg == J.eval1("damage()"),
                 f"a plate's spikes take {dmg} on both screens (joiner {J.eval1('damage()')})"):
        return 100
    full = H.eval1("maxHp()")
    with_out = [q for q in hp_ if q["out"]]
    dash = with_out[0] if with_out else hp_[2]
    rest = [q for q in hp_ if q["cell"] != dash["cell"]]
    first, second, both = rest[0], rest[1], rest[2]

    # The joiner's knight on a plate: its own game takes the damage
    J.eval1(f"moveTo({first['x']}, {first['y']})")
    check(sprung_on_both(H, J, first["cell"]),
          f"the joiner's knight stands on the plate on {first['cell']}: sprung on both screens")
    took = wait_for(lambda: J.eval1("hp()") == full - dmg, 3)
    check(took and next(q for q in J.json("plates()") if q["cell"] == first["cell"])["result"] == "hit",
          f"the joiner's game takes {full - J.eval1('hp()')} from its knight, {dmg} to take")
    seen = wait_for(lambda: H.eval1("otherHp()") == J.eval1("hp()"), 5)
    check(seen and H.eval1("hp()") == full,
          f"the host's screen shows the joiner's knight at {H.eval1('otherHp()')} HP as the joiner's "
          f"game has it ({J.eval1('hp()')}), the host's knight untouched ({H.eval1('hp()')})")
    J.eval1("moveHome()")

    # The host's knight on another
    H.eval1(f"moveTo({second['x']}, {second['y']})")
    check(sprung_on_both(H, J, second["cell"]),
          f"the host's knight stands on the plate on {second['cell']}: sprung on both screens")
    took = wait_for(lambda: H.eval1("hp()") == full - dmg, 3)
    seen = wait_for(lambda: J.eval1("otherHp()") == H.eval1("hp()"), 5)
    check(took and seen and J.eval1("hp()") == full - dmg,
          f"the host's game takes {full - H.eval1('hp()')} from its knight, the joiner's screen shows it "
          f"at {J.eval1('otherHp()')}, the joiner's knight no more than before ({J.eval1('hp()')})")
    H.eval1("moveHome()")

    # The joiner's knight dashes off a third at its click
    for i in (H, J):
        i.eval1("fresh()")
    check(J.eval1(f"dashOff('{dash['cell']}')") is True and dash["out"],
          f"the joiner's knight will dash off the plate on {dash['cell']} at its click")
    J.eval1(f"moveTo({dash['x']}, {dash['y']})")
    check(sprung_on_both(H, J, dash["cell"]), "it clicks and rises, sprung on both screens")
    time.sleep(0.5)
    check(J.eval1("hp()") == full and H.eval1("otherHp()") == full,
          f"the knight that dashed takes nothing: {J.eval1('hp()')} HP on its screen, "
          f"{H.eval1('otherHp()')} on the host's")
    J.eval1("moveHome()")

    # Both knights on a fourth at once
    for i in (H, J):
        i.eval1("fresh()")
    time.sleep(0.3)
    H.eval1(f"moveTo({both['x']}, {both['y']})")
    J.eval1(f"moveTo({both['x']}, {both['y']})")
    check(sprung_on_both(H, J, both["cell"]),
          f"both knights stand on the plate on {both['cell']}: sprung on both screens")
    time.sleep(1.0)
    check(H.eval1("hp()") == full - dmg and J.eval1("hp()") == full - dmg,
          f"each game takes the damage from its own knight once: host {full - H.eval1('hp()')}, "
          f"joiner {full - J.eval1('hp()')}, {dmg} to take")
    for i in (H, J):
        i.eval1("moveHome()")

    # Back onto the first plate: it fired once
    before = J.eval1("hp()")
    J.eval1(f"moveTo({first['x']}, {first['y']})")
    time.sleep(1.0)
    check(J.eval1("hp()") == before and phase(J, first["cell"]) == "sprung",
          f"the joiner's knight back on {first['cell']} takes {before - J.eval1('hp()')}, the plate still sprung")
    left = [q["cell"] for q in H.json("plates()") if q["phase"] == "armed"]
    check(left == [q["cell"] for q in J.json("plates()") if q["phase"] == "armed"]
          and len(left) == len(hp_) - 4,
          f"both screens show the same {len(left)} plates still armed")
    return 0


if __name__ == "__main__":
    main()
