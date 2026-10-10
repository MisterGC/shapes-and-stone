#!/usr/bin/env python3
"""Revive bench - proves that in a session an ally lifts a fallen knight up,
and that a knight still down at the camp rises there (issue #100).

Starts tests/revive/Sandbox.qml twice in Clayground's live loader, as two
processes (a host and a joiner), connects them over Local or Cloud signaling
and starts the game on a fixed seed. The host's enemies stand still, so only
the bench hits a knight. Then:

- the joiner's knight falls with the host's knight out of reach
  (Balance.party.reviveRange): no ring fills on either screen
- the host's knight stands beside it: a ring fills around the fallen knight
  on both screens
- half way the host's knight takes a hit that throws it nowhere: the ring
  starts over on both screens
- reviveTime after the hit, not sooner, the joiner's knight rises with
  reviveHp of its max HP on both screens; its fallen screen is gone and no
  ring is left. The host's fight record counts one lift, the joiner's one
  time it was lifted
- the joiner's knight falls again, the host's out of reach, and the host
  goes down to the village: at its camp the joiner's knight rises with
  reviveHp on both screens

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_revive.py [--loader <clayliveloader>] [--mode local|cloud] [--seed 424242]

Prints one PASS or FAIL line per check and exits with the number of failed
checks (100: the bench could not get to its end). The temp dir with both
loaders' logs is kept after a failed run.
"""

import argparse
import math
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

# The knight's full HP, from src/Balance.qml
KNIGHT_HP = 120
# The party's numbers when the game has none (before issue #100): the bench
# still runs, and fails where nothing is lifted
DEFAULT_PARTY = {"reviveRange": 1.5, "reviveTime": 3.0, "reviveHp": 0.3}
# Where the host's knight stands: beside the fallen knight, and out of its
# reach in the same room
BESIDE_WU = 0.8
AWAY_WU = 2.5


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
        print("[Revive]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_revive_")
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
    print(f"[Revive] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "revive")
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
        joiner_id = J.eval1("nodeId")

        H.eval([f"startGame({args.seed})"])
        if not wait_for(lambda: H.eval1("inRun()") is True and J.eval1("inRun()") is True, 30):
            return abort("the session did not reach the dungeon")
        party = dict(DEFAULT_PARTY)
        party.update(H.json("party()") or {})
        risen = round(party["reviveHp"] * KNIGHT_HP)
        print(f"[Revive] party: {party}, a knight rises with {risen} HP", flush=True)
        check(party["reviveRange"] > BESIDE_WU and party["reviveRange"] < AWAY_WU,
              f"the bench stands {BESIDE_WU} wu beside the fallen knight, inside reviveRange "
              f"{party['reviveRange']}, and {AWAY_WU} wu away, outside it")
        H.eval1("halt()")
        for i in (H, J):
            i.eval(["standUp()"])
        return lift_and_camp(H, J, joiner_id, party, risen, check)
    except TimeoutError as e:
        return abort(str(e))


def other(r):
    return r["others"][0] if r["others"] else {}


def lift_and_camp(H, J, joiner_id, party, risen, check):
    # The joiner's knight falls, the host's out of reach
    H.eval1(f"moveBeside('{joiner_id}', {AWAY_WU})")
    J.eval1("strikeDown()")
    if not wait_for(lambda: other(H.json("run()")).get("hp") == 0, 5):
        check(False, "the host sees the joiner's knight fall")
        return 100
    time.sleep(0.5)
    hr, jr = H.json("run()"), J.json("run()")
    dist = math.hypot(hr["knight"]["x"] - other(hr)["x"], hr["knight"]["y"] - other(hr)["y"])
    check(jr["fallen"] and jr["fallenScreen"] == "You are down" and jr["knight"]["hp"] == 0,
          f"the joiner's knight is down, its screen says \"You are down\" ({jr['fallenScreen']})")
    check(dist > party["reviveRange"] and other(hr)["ring"] == 0 and jr["knight"]["ring"] == 0
          and hr["knight"]["progress"] == 0,
          f"with the host's knight {dist:.2f} wu away no ring fills (host {other(hr)['ring']}, "
          f"joiner {jr['knight']['ring']})")

    # The host's knight stands beside it: the ring fills on both screens
    H.eval1(f"moveBeside('{joiner_id}', {BESIDE_WU})")
    began = time.time()
    if not check(wait_for(lambda: H.json("run()")["knight"]["progress"] >= 0.5, party["reviveTime"] + 2, 0.02),
                 f"beside the fallen knight the host's knight lifts it up: half way within "
                 f"{party['reviveTime'] / 2 + 2:.1f} s"):
        return 100
    half = time.time() - began
    hr, jr = H.json("run()"), J.json("run()")
    check(other(hr)["ring"] >= 0.45 and hr["knight"]["lifting"] == joiner_id,
          f"the host's screen draws the ring around the joiner's knight ({other(hr)['ring']:.2f}, "
          f"{half:.2f} s in)")
    check(jr["knight"]["ring"] >= 0.3 and jr["knight"]["downed"] is True,
          f"the joiner's screen draws it around its own fallen knight ({jr['knight']['ring']:.2f})")

    # Half way, a hit on the host's knight starts the lift over
    result = H.eval1("hurt()")
    hit = time.time()
    after = H.json("run()")
    check(result == "hit" and after["knight"]["progress"] < 0.1,
          f"a hit lands on the host's knight ({result}) and its lift starts over "
          f"({after['knight']['progress']:.2f})")
    check(wait_for(lambda: J.json("run()")["knight"]["ring"] < 0.2, 1.5, 0.02),
          "the joiner's screen shows the ring start over")

    # reviveTime after the hit, not sooner, the joiner's knight rises
    rose = wait_for(lambda: J.json("run()")["knight"]["hp"] > 0, party["reviveTime"] + 3, 0.02)
    took = time.time() - hit
    if not check(rose, f"the joiner's knight rises ({took:.2f} s after the hit)"):
        return 100
    check(took >= party["reviveTime"] * 0.9,
          f"it rises reviveTime ({party['reviveTime']} s) after the hit, not sooner ({took:.2f} s)")
    wait_for(lambda: other(H.json("run()")).get("hp", 0) > 0, 2)
    hr, jr = H.json("run()"), J.json("run()")
    check(jr["knight"]["hp"] == risen and not jr["fallen"] and jr["fallenScreen"] is None
          and jr["knight"]["downed"] is False,
          f"on its own screen with {jr['knight']['hp']} HP (reviveHp: {risen}), standing, no fallen screen")
    check(other(hr)["hp"] == risen and other(hr)["downed"] is False,
          f"on the host's screen standing with {other(hr)['hp']} HP")
    check(other(hr)["ring"] == 0 and jr["knight"]["ring"] == 0 and hr["knight"]["lifting"] == "",
          "no ring is left on either screen")
    check(hr["record"]["lifts"] == 1 and jr["record"]["lifted"] == 1,
          f"the fight record counts the lift: host lifts {hr['record']['lifts']}, "
          f"joiner lifted {jr['record']['lifted']}")

    # Down again, the host's knight out of reach: it rises at the camp
    J.eval(["standUp()"])
    H.eval1(f"moveBeside('{joiner_id}', {AWAY_WU})")
    J.eval1("strikeDown()")
    if not wait_for(lambda: other(H.json("run()")).get("hp") == 0, 5):
        check(False, "the host sees the joiner's knight fall again")
        return 100
    H.eval1("advance()")
    camp = wait_for(lambda: H.json("run()")["type"] == "village" and J.json("run()")["type"] == "village"
                    and J.json("run()")["knight"] is not None
                    and J.json("run()")["knight"]["hp"] > 0
                    and other(H.json("run()")).get("hp", 0) > 0, 10)
    hr, jr = H.json("run()"), J.json("run()")
    check(camp and jr["knight"]["hp"] == risen and not jr["fallen"] and jr["fallenScreen"] is None,
          f"down when the party reaches the camp, the joiner's knight rises there with "
          f"{(jr['knight'] or {}).get('hp')} HP on its own screen ({jr['type']})")
    check(camp and other(hr).get("hp") == risen and other(hr).get("downed") is False,
          f"and on the host's screen ({other(hr).get('hp')} HP)")
    return 0


if __name__ == "__main__":
    main()
