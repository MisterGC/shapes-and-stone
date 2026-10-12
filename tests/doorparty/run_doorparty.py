#!/usr/bin/env python3
"""Door party bench - proves that in a session a door opened on one screen
is open on every screen, and that the host owns the doors (issue #127).

Starts tests/doorparty/Sandbox.qml twice in Clayground's live loader, as
two processes (a host and a joiner), connects them over Local or Cloud
signaling and starts the game on a fixed seed. The host's enemies stand
still. Then:

- both screens lay the same doors on the same cells, every one closed
- the joiner's knight presses E beside a door: it is open on both screens
- the host's knight presses E beside it: it is closed on both screens
- the joiner's knight presses E standing in the doorway of a door the
  host opened: it stays open on both screens
- the host's enemy bursts a closed door open: it is bashed on both
  screens, and the joiner's E beside it leaves it so

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_doorparty.py [--loader <clayliveloader>] [--mode local|cloud] [--seed 424242]

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
        print("[DoorParty]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_doorparty_")
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
    print(f"[DoorParty] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "doorparty")
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
        return open_and_close(H, J, check)
    except TimeoutError as e:
        return abort(str(e))


def states(doors):
    return {d["cell"]: d["state"] for d in doors}


def both(H, J, cell, state, timeout=5):
    """Whether both screens show the door on cell so within timeout s"""
    return wait_for(lambda: H.eval1(f"stateOf('{cell}')") == state
                    and J.eval1(f"stateOf('{cell}')") == state, timeout)


def open_and_close(H, J, check):
    hd, jd = H.json("doors()"), J.json("doors()")
    if not check(len(hd) > 0 and states(hd) == states(jd)
                 and all(d["state"] == "closed" for d in hd),
                 f"both screens lay the same {len(hd)} doors on the same cells, all closed "
                 f"(joiner {len(jd)})"):
        return 100
    a, b = hd[0]["cell"], hd[1]["cell"] if len(hd) > 1 else None

    # The joiner opens a door, the host closes it
    J.eval1(f"standBy('{a}', -1.2)")
    check(J.eval1("pressE()") is True, f"the joiner's knight presses E beside the door on {a}")
    opened = both(H, J, a, "open")
    shown = (H.eval1(f"stateOf('{a}')"), J.eval1(f"stateOf('{a}')"))
    check(opened, f"the door on {a} is open on both screens (host {shown[0]}, joiner {shown[1]})")
    J.eval1(f"standBy('{a}', -4)")
    H.eval1(f"standBy('{a}', 1.2)")
    check(H.eval1("pressE()") is True, f"the host's knight presses E beside it")
    check(both(H, J, a, "closed"), f"it is closed on both screens")

    # The host opens it, the joiner in the doorway cannot close it
    H.eval1("pressE()")
    check(both(H, J, a, "open"), "the host opens it again, open on both screens")
    H.eval1(f"standBy('{a}', 4)")
    J.eval1(f"standBy('{a}', 0)")
    J.eval1("pressE()")
    time.sleep(1.0)
    check(H.eval1(f"stateOf('{a}')") == "open" and J.eval1(f"stateOf('{a}')") == "open",
          "the joiner's E in the doorway leaves it open on both screens")

    # The host's enemy bashes a closed door: bashed on both, for good
    c = b or a
    if c == a:
        J.eval1(f"standBy('{a}', -4)")
        H.eval1(f"standBy('{a}', 1.2)")
        H.eval1("pressE()")
        both(H, J, a, "closed")
    check(H.eval1(f"bash('{c}')") == "bashed", f"the host's enemy bursts the door on {c} open")
    check(both(H, J, c, "bashed"), "it is bashed on both screens")
    J.eval1(f"standBy('{c}', -1.2)")
    J.eval1("pressE()")
    time.sleep(1.0)
    check(H.eval1(f"stateOf('{c}')") == "bashed" and J.eval1(f"stateOf('{c}')") == "bashed",
          "the joiner's E beside it leaves it bashed on both screens")
    check(states(H.json("doors()")) == states(J.json("doors()")),
          "both screens show every door the same")
    return 0


if __name__ == "__main__":
    main()
