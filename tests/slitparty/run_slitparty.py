#!/usr/bin/env python3
"""Slit party bench - proves that in a session every screen fires the same
arrows from the same slits at the same session time, and that each
knight's own game judges the arrows on it (issue #125).

Starts tests/slitparty/Sandbox.qml twice in Clayground's live loader, as
two processes (a host and a joiner), connects them over Local or Cloud
signaling and starts the game on a fixed seed. The host's enemies stand
still, both knights in the start room. Then:

- both screens lay the same slits on the same cells with the same rhythms
- for three seconds both screens log every arrow their slits fire: the
  same arrows, each due at the same session time, each leaving within a
  frame or two of it on both screens
- the joiner's knight stands in a slit's line, its back to it: its own
  game takes the arrow's damage, the host's screen shows the joiner's HP
  as the joiner's game has it and the arrow gone at the knight, the host's
  knight untouched
- the joiner's knight raises its shield just before the next arrow: a
  perfect block on its screen, and the arrow flies back to its slit on
  both screens

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_slitparty.py [--loader <clayliveloader>] [--mode local|cloud] [--seed 424242]

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
        print("[SlitParty]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_slitparty_")
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
    print(f"[SlitParty] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "slitparty")
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
        return slits(H, J, check)
    except TimeoutError as e:
        return abort(str(e))


def slits(H, J, check):
    if not wait_for(lambda: J.eval1("synced") is True, 15):
        check(False, "the joiner's session clock did not sync")
        return 100
    hs, js = H.json("slits()"), J.json("slits()")
    if not check(len(hs) > 0 and sorted(hs, key=lambda s: s["cell"]) == sorted(js, key=lambda s: s["cell"]),
                 f"both screens lay the same {len(hs)} slits on the same cells with the same rhythms "
                 f"(joiner {len(js)}: {', '.join(sorted(set(s['rhythm'] for s in js)))})"):
        return 100

    # Three seconds of arrows on both screens
    starts = [H.eval1("startLog()"), J.eval1("startLog()")]
    time.sleep(3.0)
    hf, jf = H.json("fired"), J.json("fired")
    ends = [H.eval1("now()"), J.eval1("now()")]
    lo, hi = max(starts) + 300, min(ends) - 300
    hd = {a["id"]: a for a in hf if lo <= a["at"] <= hi}
    jd = {a["id"]: a for a in jf if lo <= a["at"] <= hi}
    check(len(hd) > 0 and sorted(hd) == sorted(jd) and all(hd[i]["at"] == jd[i]["at"] for i in hd),
          f"both screens fire the same {len(hd)} arrows due at the same session times in "
          f"{(hi - lo) / 1000:.1f} s (joiner {len(jd)}"
          + (f"; only on the host: {sorted(set(hd) - set(jd))[:3]}, only on the joiner: "
             f"{sorted(set(jd) - set(hd))[:3]}" if sorted(hd) != sorted(jd) else "") + ")")
    late = [a["now"] - a["at"] for a in list(hd.values()) + list(jd.values())]
    apart = [abs(hd[i]["now"] - jd[i]["now"]) for i in hd if i in jd]
    check(late and min(late) >= -1 and max(late) < 50 and max(apart) < 50,
          f"each leaves {min(late):.1f} to {max(late):.1f} ms after it is due on the session clock, "
          f"the two screens at most {max(apart):.1f} ms apart")

    # The joiner's knight in a line, its back to the slit
    full, dmg = J.eval1("maxHp()"), J.eval1("damage()")
    cell = J.eval1("pickSlit()")
    if not check(cell != "", f"a slit with its line's third cell clear: {cell}"):
        return 100
    for i in (H, J):
        i.eval1("startLog()")
    J.eval1(f"standInLine('{cell}')")

    def first(inst, key, pred):
        return next((a for a in inst.json(key) if pred(a)), None)

    hit = None

    def got_hit():
        nonlocal hit
        hit = first(J, "met", lambda a: a["id"].startswith(cell + "#"))
        return hit is not None
    wait_for(got_hit, 5)
    took = wait_for(lambda: J.eval1("hp()") == full - dmg, 3)
    check(hit is not None and hit["result"] == "hit" and took,
          f"the joiner's knight in the line of {cell} is hit by {hit['id'] if hit else '?'} on its own screen: "
          f"{hit['result'] if hit else 'nothing'}, {full - J.eval1('hp()')} taken, {dmg} to take")
    seen = wait_for(lambda: H.eval1("otherHp()") == J.eval1("hp()"), 5)
    gone = hit is not None and wait_for(
        lambda: first(H, "ended", lambda a: a["id"] == hit["id"]) is not None, 5)
    where = first(H, "ended", lambda a: hit is not None and a["id"] == hit["id"])
    check(seen and gone and where["where"] == "knight" and H.eval1("hp()") == H.eval1("maxHp()"),
          f"the host's screen shows the joiner's knight at {H.eval1('otherHp()')} HP as its game has it "
          f"({J.eval1('hp()')}), the arrow gone at it ({where['where'] if where else 'not gone'}), "
          f"the host's knight untouched ({H.eval1('hp()')})")

    # A perfect block on the joiner's screen sends it back on both
    time.sleep(0.7)
    J.eval1("fresh()")
    for i in (H, J):
        i.eval1("startLog()")
    J.eval1("perfectNext()")
    block = None

    def got_block():
        nonlocal block
        block = first(J, "met", lambda a: a["id"].startswith(cell + "#"))
        return block is not None
    wait_for(got_block, 5)
    check(block is not None and block["result"] == "perfect" and J.eval1("hp()") == full,
          f"the joiner's knight raises its shield just before {block['id'] if block else '?'}: "
          f"{block['result'] if block else 'nothing'}, {full - J.eval1('hp()')} taken")
    back = block is not None and wait_for(
        lambda: all(first(i, "ended", lambda a: a["id"] == block["id"]) is not None for i in (H, J)), 5)
    hw = first(H, "ended", lambda a: block is not None and a["id"] == block["id"])
    jw = first(J, "ended", lambda a: block is not None and a["id"] == block["id"])
    check(back and hw["where"] == "slit" and jw["where"] == "slit",
          f"the arrow flies back to its slit on both screens: host {hw['where'] if hw else 'not ended'}, "
          f"joiner {jw['where'] if jw else 'not ended'}")
    J.eval1("moveHome()")
    return 0


if __name__ == "__main__":
    main()
