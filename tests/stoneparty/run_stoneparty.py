#!/usr/bin/env python3
"""Stone party bench - proves that in a session both screens show the same
petrified travellers, the same freeing and the same outcome (issue #158).

Starts tests/stoneparty/Sandbox.qml twice in Clayground's live loader, as
two processes (a host and a joiner), connects them over Local or Cloud
signaling and starts the game on a fixed seed. The host's enemies stand
still. Then:

- both screens show the same petrified travellers on the same cells, of
  the same kind and strikes, still stone
- the joiner's knight frees one, every strike clean: both screens show it
  freed, with its colour back, and go on as the host decided - a miner
  whose room's hole sent no creature works at the same spot beside its
  vein on both, a lost one walks off and is gone on both - each screen
  plays the chord, and both saw the same events
- the host's knight frees another, when the dungeon has one, and both
  screens show the same again
- then the party goes on to the camp (issue #159): each machine's record
  has a special of its own, and both screens seat the host's special and
  the travellers that left by the fire, both fires give its comfort alone,
  and the joiner's own record keeps its own special
- before the freeings (#173 review): a freeing of the joiner's the host refuses -
  reported for another level - shows freed on the joiner's screen, then
  turns back to stone there, and the host's stays stone

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_stoneparty.py [--loader <clayliveloader>] [--mode local|cloud] [--seed 424244]

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
    ap.add_argument("--seed", type=int, default=424244,
                    help="the run's seed (424244: a lost traveller and a miner at depth 0)")
    args = ap.parse_args()

    failures = 0

    def check(ok, what):
        nonlocal failures
        print("[StoneParty]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_stoneparty_")
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
    print(f"[StoneParty] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "stoneparty")
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
        # Each machine's record with a special of its own (issue #159)
        H.eval(["setSpecials(['healer'])"])
        J.eval(["setSpecials(['cook'])"])
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
        if free_on_both(H, J, check) == 100:
            return 100
        return camp_on_both(H, J, check)
    except TimeoutError as e:
        return abort(str(e))


def lines(stones):
    return sorted((s["cell"], s["kind"], s["strikes"], s["hole"]) for s in stones)


def one(K, cell):
    return next((s for s in K.json("stones()") if s["cell"] == cell), None)


def whats(events, cell):
    return [e["what"] for e in events if e["cell"] == cell]


def free_on_both(H, J, check):
    hs, js = H.json("stones()"), J.json("stones()")
    if not check(len(hs) >= 1 and lines(hs) == lines(js) and not any(s["freed"] for s in hs + js),
                 f"both screens show the same {len(hs)} petrified travellers on the same cells, of the same "
                 f"kind and strikes, stone ({', '.join(s['cell'] + ' ' + s['kind'] for s in hs)}; joiner {len(js)})"):
        return 100
    # From the #173 review: a freeing the host refuses turns back to stone
    cell = hs[0]["cell"]
    shown = J.eval1(f"freeStale('{cell}')") is True
    back = wait_for(lambda: J.eval1("refused()") == 1, 15)
    jf, hf = one(J, cell), one(H, cell)
    check(shown and back and not jf["freed"] and jf["colour"] == 0 and jf["outcome"] == ""
          and not hf["freed"] and whats(J.json("stoneEvents()"), cell) == ["freed", "refused"],
          f"a freeing the host refuses (another level) shows freed on the joiner, then turns back to stone: "
          f"joiner freed {jf['freed']}, colour {jf['colour']}, "
          f"{', '.join(whats(J.json('stoneEvents()'), cell))}; host freed {hf['freed']}")
    for who, K in (("joiner", J), ("host", H)):
        if who == "host" and len(hs) < 2:
            check(True, "the dungeon has one traveller: the host's knight frees none of its own")
            break
        stone = hs[0] if who == "joiner" else hs[1]
        cell, kind = stone["cell"], stone["kind"]
        holes = {h["cell"]: h for h in H.json("holes()")}
        hole = holes.get(stone["hole"])
        want = "leaving" if kind == "lost" else ("fleeing" if hole and hole["wave"] > 0 else "working")
        if not check(K.eval1(f"free('{cell}')") is True,
                     f"the {who}'s knight frees the {kind} on {cell}, every strike clean"):
            return 100
        decided = wait_for(lambda: all((one(X, cell) or {}).get("outcome") == want for X in (H, J)), 20)
        hf, jf = one(H, cell), one(J, cell)
        check(decided and hf["freed"] and jf["freed"],
              f"both screens show it freed and going on as the host decided: {hf['outcome']} "
              f"(joiner {jf['outcome']}, wanted {want})")
        coloured = wait_for(lambda: all((one(X, cell) or {}).get("colour") == 1 for X in (H, J)), 10)
        sounds = (H.json("stoneSounds()"), J.json("stoneSounds()"))
        check(coloured and all("chord" in s for s in sounds),
              f"its colour comes back on both screens and each plays the chord "
              f"(host {', '.join(sounds[0])}; joiner {', '.join(sounds[1])})")
        if want == "working":
            w = H.json(f"workSpot('{cell}')")
            at = lambda X: (lambda s: s and not s["gone"] and abs(s["x"] - w["x"]) < 0.01
                            and abs(s["y"] - w["y"]) < 0.01)(one(X, cell))
            settled = wait_for(lambda: at(H) and at(J), 15)
            hf, jf = one(H, cell), one(J, cell)
            check(settled, f"the miner works beside its vein at the same spot on both screens: host "
                           f"{hf['x']:.2f},{hf['y']:.2f}, joiner {jf['x']:.2f},{jf['y']:.2f} "
                           f"(the spot {w['x']:.2f},{w['y']:.2f})")
            time.sleep(3)
            check(all(not one(X, cell)["gone"] and one(X, cell)["outcome"] == "working" for X in (H, J)),
                  "3 s later it still works there on both screens")
        else:
            gone = wait_for(lambda: all((one(X, cell) or {}).get("gone") is True for X in (H, J)), 15)
            check(gone, f"the {kind} walks off and is gone on both screens")
        he, je = whats(H.json("stoneEvents()"), cell), whats(J.json("stoneEvents()"), cell)
        # The joiner's screen saw the refused freeing first
        if who == "joiner" and je[:2] == ["freed", "refused"]:
            je = je[2:]
        check(he == je and he[:2] == ["freed", want],
              f"both screens saw the same: {', '.join(he)} (joiner {', '.join(je)})")
    return 0


def camp_on_both(H, J, check):
    """The camp after the dungeon: the host's record decides which specials
    sit by the fire, on both screens, with the travellers that left"""
    left = sorted(s["kind"] for s in H.json("stones()") if s["outcome"] in ("leaving", "fleeing"))
    H.eval(["onward()"])
    if not check(wait_for(lambda: H.json("camp()")["inCamp"] and J.json("camp()")["inCamp"], 30),
                 "the party goes on to the camp on both screens"):
        return 100
    hc, jc = H.json("camp()"), J.json("camp()")
    want = sorted(["lost:healer"] + left)
    check(hc["sitting"] == want and jc["sitting"] == want,
          f"the host's special and the travellers that left sit by the fire on both screens: host "
          f"{', '.join(hc['sitting'])}; joiner {', '.join(jc['sitting'])} (wanted {', '.join(want)})")
    check(hc["shown"] == ["healer"] and jc["shown"] == ["healer"] and jc["own"] == ["cook"],
          f"the host's record decides the specials on every screen: host shows {hc['shown']}, joiner "
          f"{jc['shown']}; the joiner's own record keeps {jc['own']}")
    check(hc["heal"] == jc["heal"] == 10 and hc["mana"] == jc["mana"] == 5 and hc["light"] == jc["light"],
          f"both fires give the host's special's comfort alone: heal {hc['heal']}/{jc['heal']} HP/s, "
          f"mana {hc['mana']}/{jc['mana']}, light {hc['light']}/{jc['light']} wu")
    return 0


if __name__ == "__main__":
    main()
