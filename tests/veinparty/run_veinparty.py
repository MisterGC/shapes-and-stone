#!/usr/bin/env python3
"""Vein party bench - proves that in a session every screen shows the
same veins, and that a gem cut on one screen is gone on both (issue #156).

Starts tests/veinparty/Sandbox.qml twice in Clayground's live loader, as
two processes (a host and a joiner), connects them over Local or Cloud
signaling and starts the game on a fixed seed. The host's enemies stand
still. Then:

- both screens show the same veins on the same cells, with the same gems
  and strikes
- the joiner's knight cuts a vein: it is split on both screens, and its
  gem is in the joiner's pouch, not the host's
- the host's knight cuts another: it is split on the joiner's screen too
- both screens show the same veins split, the rest whole

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_veinparty.py [--loader <clayliveloader>] [--mode local|cloud] [--seed 424242]

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
        print("[VeinParty]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_veinparty_")
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
    print(f"[VeinParty] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "veinparty")
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
        return cut_on_both(H, J, check)
    except TimeoutError as e:
        return abort(str(e))


def whole(veins):
    return sorted((v["cell"], v["shape"], v["strikes"]) for v in veins)


def split(veins):
    return sorted(v["cell"] for v in veins if v["split"])


def cut_on_both(H, J, check):
    hv, jv = H.json("veins()"), J.json("veins()")
    shapes = sorted(set(v["shape"] for v in hv))
    if not check(len(hv) >= 2 and whole(hv) == whole(jv),
                 f"both screens show the same {len(hv)} veins on the same cells, gems and strikes "
                 f"({', '.join(shapes)}; joiner {len(jv)})"):
        return 100

    # The joiner cuts the first vein
    first = jv[0]
    check(J.eval1(f"cut('{first['cell']}')") is True,
          f"the joiner's knight cuts the {first['shape']} vein on {first['cell']}")
    gone = wait_for(lambda: first["cell"] in split(H.json("veins()")), 5)
    check(gone, f"the vein on {first['cell']} is split on the host's screen too")
    got = wait_for(lambda: len(J.json("pouch()")) == 1, 5)
    jp, hp = J.json("pouch()"), H.json("pouch()")
    check(got and jp[0]["shape"] == first["shape"] and len(hp) == 0,
          f"its gem is in the joiner's pouch, not the host's (joiner {jp}, host {hp})")

    # The host cuts another
    second = [v for v in H.json("veins()") if not v["split"]][0]
    check(H.eval1(f"cut('{second['cell']}')") is True,
          f"the host's knight cuts the vein on {second['cell']}")
    gone = wait_for(lambda: second["cell"] in split(J.json("veins()")), 5)
    check(gone, f"the vein on {second['cell']} is split on the joiner's screen too")
    hp = H.json("pouch()")
    check(len(hp) == 1 and hp[0]["shape"] == second["shape"] and len(J.json("pouch()")) == 1,
          f"its gem is in the host's pouch ({hp})")
    hs, js = split(H.json("veins()")), split(J.json("veins()"))
    check(hs == js == sorted([first["cell"], second["cell"]]),
          f"both screens show the same veins split ({hs}; joiner {js}), the other "
          f"{len(hv) - len(hs)} whole")
    return 0


if __name__ == "__main__":
    main()
