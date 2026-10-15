#!/usr/bin/env python3
"""Hole party bench - proves that in a session the host's roll decides
whether a cut gem wakes its spawn hole, and both screens see the same
holes wake through the same stages and the same creatures come out of
them (issues #157, #175).

Starts tests/holeparty/Sandbox.qml twice in Clayground's live loader, as
two processes (a host and a joiner), connects them over Local or Cloud
signaling and starts the game on a fixed seed. The host's enemies stand
still, those the holes send too. Then:

- both screens show the same spawn holes on the same cells, for the same
  veins, at rest
- the knights cut a vein of each hole's room in turn, every strike
  clean, the joiner's first, then the host's: where the host's roll says
  the gem wakes the hole, on both screens it goes through the same stages
  in order - dust, eyes, waves, each wave, closed - the first creature
  shown no sooner than enemy.minTelegraph after the eyes, and both show
  the same creatures (id, kind, tier) at the hole's mouth; where it says
  not, the hole stays at rest on both screens and no creature comes
- the host's roll woke at least one hole

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_holeparty.py [--loader <clayliveloader>] [--mode local|cloud] [--seed 424242]

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
    ap.add_argument("--quiet", type=float, default=0,
                    help="seconds to watch a hole the roll leaves asleep (0: the time a woken one takes)")
    args = ap.parse_args()

    failures = 0

    def check(ok, what):
        nonlocal failures
        print("[HoleParty]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_holeparty_")
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
    print(f"[HoleParty] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "holeparty")
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
        return wake_on_both(H, J, check, args.quiet)
    except TimeoutError as e:
        return abort(str(e))


def stages(events, cell):
    return [e["what"] for e in events if e["cell"] == cell and e["what"] != "creature"]


def first_creature(events, cell):
    """Seconds from the eyes to the first creature shown, None without them"""
    eyes = [e["t"] for e in events if e["cell"] == cell and e["what"] == "eyes"]
    came = [e["t"] for e in events if e["cell"] == cell and e["what"] == "creature"]
    return came[0] - eyes[0] if eyes and came else None


def creatures(rows):
    return sorted((c["id"], c["type"], c["tier"]) for c in rows)


def at_mouth(rows):
    return all(abs(c["x"] - c["mx"]) <= 1.5 and c["my"] - 1.5 <= c["y"] <= c["my"] + 0.2 for c in rows)


def wake_on_both(H, J, check, quiet):
    hh, jh = H.json("holes()"), J.json("holes()")
    lines = lambda hs: sorted((h["cell"], tuple(sorted(h["veins"])), h["stage"]) for h in hs)
    if not check(len(hh) >= 1 and lines(hh) == lines(jh) and all(h["stage"] == "rest" for h in hh),
                 f"both screens show the same {len(hh)} spawn holes on the same cells, for the same veins, "
                 f"at rest ({', '.join(h['cell'] for h in hh)}; joiner {len(jh)})"):
        return 100
    cfg = H.json("holeTable()")
    tele = H.eval1("minTelegraph()")
    want = ["dust", "eyes", "waves"] + ["wave"] * cfg["waves"] + ["closed"]
    count = cfg["waves"] * cfg["perWave"]
    asleep = quiet or cfg["eyesAfter"] + tele + cfg["telegraph"] + cfg["waveGap"]
    knights = H.eval1("knights()")
    woken = 0
    for i, hole in enumerate(hh):
        who, K = ("joiner", J) if i % 2 == 0 else ("host", H)
        vein = hole["veins"][0]
        wakes = H.eval1(f"wakes('{vein}')") is True
        woken += wakes
        check(K.eval1(f"cut('{vein}')") is True,
              f"the {who}'s knight cuts the vein on {vein}, every strike clean; the host's roll for "
              f"{knights} knights says it {'wakes' if wakes else 'leaves asleep'} the hole on {hole['cell']}")
        if not wakes:
            stirred = wait_for(lambda: any(h["stage"] != "rest" for X in (H, J)
                                           for h in X.json("holes()") if h["cell"] == hole["cell"]), asleep)
            hs = [h["stage"] for X in (H, J) for h in X.json("holes()") if h["cell"] == hole["cell"]]
            hc, jc = H.json(f"holeCreatures('{hole['cell']}')"), J.json(f"holeCreatures('{hole['cell']}')")
            check(not stirred and hs == ["rest", "rest"] and not stages(H.json("holeEvents()"), hole["cell"])
                  and not stages(J.json("holeEvents()"), hole["cell"]) and not hc and not jc,
                  f"for {asleep:.1f} s it stays at rest on both screens ({', '.join(hs)}), no creature from it "
                  f"(host {len(hc)}, joiner {len(jc)})")
            continue
        closed = wait_for(lambda: all(h["stage"] == "closed" for X in (H, J)
                                      for h in X.json("holes()") if h["cell"] == hole["cell"]), 30)
        he, je = H.json("holeEvents()"), J.json("holeEvents()")
        hs, js = stages(he, hole["cell"]), stages(je, hole["cell"])
        check(closed and hs == js == want,
              f"both screens see the hole on {hole['cell']} go through the same stages: {', '.join(hs)} "
              f"(joiner {', '.join(js)})")
        hf, jf = first_creature(he, hole["cell"]), first_creature(je, hole["cell"])
        check(hf is not None and jf is not None and hf >= tele - 1e-6 and jf >= tele - 1e-6,
              f"the first creature shows {hf if hf is None else round(hf, 3)} s after the eyes on the host, "
              f"{jf if jf is None else round(jf, 3)} s on the joiner, no sooner than enemy.minTelegraph {tele}")
        hc, jc = H.json(f"holeCreatures('{hole['cell']}')"), J.json(f"holeCreatures('{hole['cell']}')")
        check(len(hc) == count and creatures(hc) == creatures(jc),
              f"both screens show the same {len(hc)} creatures from it: "
              f"{', '.join(f'{c[1]}/{c[2]}' for c in creatures(hc))} (joiner {len(jc)})")
        check(at_mouth(hc) and at_mouth(jc),
              "they stand at the hole's mouth on both screens (host "
              + "; ".join(f"{c['x']:.2f},{c['y']:.2f}" for c in hc) + ", joiner "
              + "; ".join(f"{c['x']:.2f},{c['y']:.2f}" for c in jc)
              + (f", mouth {hc[0]['mx']:.2f},{hc[0]['my']:.2f})" if hc else ")"))
    check(woken >= 1, f"the host's roll woke {woken} of the {len(hh)} holes")
    return 0


if __name__ == "__main__":
    main()
