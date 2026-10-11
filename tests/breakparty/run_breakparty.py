#!/usr/bin/env python3
"""Break party bench - proves that in a session a thing broken on one
screen is broken on every screen, and that its gold is picked up once
(issue #123).

Starts tests/breakparty/Sandbox.qml twice in Clayground's live loader, as
two processes (a host and a joiner), connects them over Local or Cloud
signaling and starts the game on a fixed seed. The host's enemies stand
still. Then:

- both screens stand the same breakables on the same cells
- the joiner's knight swings at an urn or a crate that holds gold: it is
  gone on both screens, and both show the host's gold drop where it stood,
  the amount the table gives it
- both knights step onto the drop at once: one of them gets the gold, the
  other none, and the drop is gone on both screens
- the host's knight breaks a crystal with a charged swing (another thing
  with a swing when the dungeon holds no crystal): it is gone on the
  joiner's screen too, and its gold lies on both

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_breakparty.py [--loader <clayliveloader>] [--mode local|cloud] [--seed 424242]

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
        print("[BreakParty]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_breakparty_")
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
    print(f"[BreakParty] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "breakparty")
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
            i.eval(["standUp()"])
        return break_and_pick(H, J, check)
    except TimeoutError as e:
        return abort(str(e))


def cells(things):
    return sorted(t["cell"] for t in things)


def at(drops, thing):
    return [d for d in drops if abs(d["x"] - thing["x"]) < 1e-6 and abs(d["y"] - thing["y"]) < 1e-6]


def break_and_pick(H, J, check):
    ht, jt = H.json("things()"), J.json("things()")
    kinds = sorted(set(t["kind"] for t in ht))
    if not check(len(ht) > 0 and cells(ht) == cells(jt),
                 f"both screens stand the same {len(ht)} breakables on the same cells "
                 f"({', '.join(kinds)}; joiner {len(jt)})"):
        return 100

    # The joiner breaks an urn or a crate that holds gold
    rich = [t for t in ht if t["kind"] in ("urn", "crate") and t["gold"] > 0]
    if not check(len(rich) > 0, f"the dungeon holds an urn or a crate with gold ({len(rich)})"):
        return 100
    thing = rich[0]
    gold_before = (H.eval1("gold()"), J.eval1("gold()"))
    check(J.eval1(f"swingAt('{thing['cell']}', false)") is True,
          f"the joiner's knight swings at the {thing['kind']} on {thing['cell']}")
    gone = wait_for(lambda: thing["cell"] not in cells(H.json("things()"))
                    and thing["cell"] not in cells(J.json("things()")), 5)
    check(gone, f"the {thing['kind']} is broken on both screens")
    dropped = wait_for(lambda: len(at(H.json("drops()"), thing)) == 1
                       and len(at(J.json("drops()"), thing)) == 1, 5)
    hd, jd = at(H.json("drops()"), thing), at(J.json("drops()"), thing)
    check(dropped and hd[0]["amount"] == thing["gold"] and jd[0]["amount"] == thing["gold"]
          and hd[0]["id"] != "" and hd[0]["id"] == jd[0]["id"],
          f"both screens show one gold drop where it stood, {thing['gold']} as the table gives it "
          f"(host {[d['amount'] for d in hd]}, joiner {[d['amount'] for d in jd]})")
    if not dropped:
        return 100

    # Both knights step onto it at once: it is picked up once
    H.eval1(f"moveTo({thing['x']}, {thing['y']})")
    J.eval1(f"moveTo({thing['x']}, {thing['y']})")
    picked = wait_for(lambda: len(at(H.json("drops()"), thing)) == 0
                      and len(at(J.json("drops()"), thing)) == 0, 5)
    time.sleep(0.5)
    gained = (H.eval1("gold()") - gold_before[0], J.eval1("gold()") - gold_before[1])
    check(picked, "with both knights on it the drop is gone on both screens")
    check(sorted(gained) == [0, thing["gold"]],
          f"one knight got its {thing['gold']} gold, the other none (host +{gained[0]}, joiner +{gained[1]})")

    # The host breaks a crystal with a charged swing, else another thing
    left = H.json("things()")
    crystal = ([t for t in left if t["kind"] == "crystal"] + left)[0]
    heavy = crystal["kind"] == "crystal"
    check(H.eval1(f"swingAt('{crystal['cell']}', {'true' if heavy else 'false'})") is True,
          f"the host's knight swings {'a charged swing ' if heavy else ''}at the {crystal['kind']} "
          f"on {crystal['cell']}")
    gone = wait_for(lambda: crystal["cell"] not in cells(J.json("things()"))
                    and crystal["cell"] not in cells(H.json("things()")), 5)
    check(gone, f"the {crystal['kind']} is broken on the joiner's screen too")
    want = 1 if crystal["gold"] > 0 else 0
    dropped = wait_for(lambda: len(at(H.json("drops()"), crystal)) == want
                       and len(at(J.json("drops()"), crystal)) == want, 5)
    check(dropped, f"its gold lies on both screens as the table gives it ({crystal['gold']})")
    left = len(H.json("things()"))
    check(left == len(ht) - 2 and cells(H.json("things()")) == cells(J.json("things()")),
          f"both screens stand the same {left} breakables left")
    return 0


if __name__ == "__main__":
    main()
