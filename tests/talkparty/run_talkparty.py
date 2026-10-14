#!/usr/bin/env python3
"""Talk party bench - proves that in a session both screens show the same
travellers of the deep, the same talk and the same leaving (issue #176).

Starts tests/talkparty/Sandbox.qml twice in Clayground's live loader, as
two processes (a host and a joiner), connects them over Local or Cloud
signaling and starts the game on a fixed seed. The host's enemies stand
still. Then:

- both screens show the same travellers on the same spots, of the same
  kind and special, all still there
- a talk of the joiner's the host gets for another level changes nothing
  on either screen
- with the joiner's knight by a miner, the miner digs on both screens,
  and the host counts its strikes toward waking the room's hole
- the joiner's knight talks to a traveller: its line shows on the
  joiner's screen at once and on the host's, the same; both screens show
  it leave as the host decided, play the chord, show it gone, and saw the
  same events
- the host's knight talks to another, when the dungeon has one, and both
  screens show the same again
- then the party goes on to the camp (issue #159): each machine's record
  has a special of its own, and both screens seat the host's special and
  the travellers that left by the fire, both fires give its comfort alone,
  and the joiner's own record keeps its own special

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_talkparty.py [--loader <clayliveloader>] [--mode local|cloud] [--seed 424244]

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
                    help="the run's seed")
    args = ap.parse_args()

    failures = 0

    def check(ok, what):
        nonlocal failures
        print("[TalkParty]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_talkparty_")
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
    print(f"[TalkParty] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "talkparty")
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
        if talk_on_both(H, J, check) == 100:
            return 100
        return camp_on_both(H, J, check)
    except TimeoutError as e:
        return abort(str(e))


def lines(travellers):
    return sorted((t["cell"], t["kind"], t["special"], round(t["x"], 3), round(t["y"], 3), t["hole"])
                  for t in travellers)


def one(K, cell):
    return next((t for t in K.json("travellers()") if t["cell"] == cell), None)


def whats(events, cell):
    return [e["what"] for e in events if e["cell"] == cell]


def talk_on_both(H, J, check):
    hs, js = H.json("travellers()"), J.json("travellers()")
    if not check(len(hs) >= 1 and lines(hs) == lines(js)
                 and all(t["outcome"] == "" and not t["gone"] for t in hs + js),
                 f"both screens show the same {len(hs)} travellers of the deep on the same spots, of the same "
                 f"kind and special, all there ({', '.join(t['cell'] + ' ' + t['kind'] for t in hs)}; "
                 f"joiner {len(js)})"):
        return 100
    for K in (H, J):
        K.eval1("noteStart()")
    # A talk for another level than the host's changes nothing
    cell = hs[0]["cell"]
    J.eval1(f"talkStale('{cell}')")
    time.sleep(2)
    check(all(one(K, cell)["outcome"] == "" and not one(K, cell)["gone"] for K in (H, J)),
          "a talk of the joiner's the host gets for another level changes nothing on either screen")
    # The joiner's knight by a miner: it digs on both screens, the host
    # counts its strikes
    miner = next((t for t in hs if t["kind"] == "miner"), None)
    if miner:
        mc = miner["cell"]
        J.eval1(f"standBy('{mc}')")
        digs = wait_for(lambda: all(one(K, mc)["digging"] and one(K, mc)["digs"] >= 2 for K in (H, J)), 15)
        hole = next((h for h in H.json("holes()") if h["cell"] == miner["hole"]), None)
        hm, jm = one(H, mc), one(J, mc)
        check(digs and hole is not None and hole["dug"] >= 2 and hole["stage"] == "rest",
              f"with the joiner's knight by the miner on {mc} it digs on both screens (host {hm['digs']} strikes, "
              f"joiner {jm['digs']}), and the host counts them toward waking its hole "
              f"({hole['dug'] if hole else '-'} at {miner['hole']})")
        J.eval1("standAway()")
    else:
        check(True, "the dungeon has no miner: no digging to show")
    # The miner first, if there is one, else the first
    order = sorted(hs, key=lambda t: t["kind"] != "miner")
    for who, K in (("joiner", J), ("host", H)):
        if who == "host" and len(order) < 2:
            check(True, "the dungeon has one traveller: the host's knight talks to none of its own")
            break
        t = order[0] if who == "joiner" else order[1]
        cell, kind = t["cell"], t["kind"]
        heard = {X: X.eval1("soundCount()") for X in (H, J)}
        said = K.eval1(f"talk('{cell}')")
        if not check(isinstance(said, str) and said != "",
                     f"the {who}'s knight talks to the {kind} on {cell}: it says \"{said}\" at once"):
            return 100
        K.eval1("standAway()")
        decided = wait_for(lambda: all((one(X, cell) or {}).get("outcome") == "leaving" for X in (H, J)), 20)
        hf, jf = one(H, cell), one(J, cell)
        check(decided and hf["saying"] == said and jf["saying"] == said,
              f"both screens show its line and it leaving as the host decided: host \"{hf['saying']}\" "
              f"{hf['outcome']}, joiner \"{jf['saying']}\" {jf['outcome']}")
        chord = wait_for(lambda: all(X.eval1(f"chordsSince({heard[X]})") == 1 for X in (H, J)), 10)
        gone = wait_for(lambda: all((one(X, cell) or {}).get("gone") is True for X in (H, J)), 15)
        check(chord and gone, f"each screen plays the chord and shows the {kind} walk off and gone")
        he, je = whats(H.json("events()"), cell), whats(J.json("events()"), cell)
        talker, other = (je, he) if who == "joiner" else (he, je)
        check(talker == ["talked", "leaving", "gone"] and other == ["leaving", "gone"],
              f"both screens saw the same: the {who}'s {', '.join(talker)}, the other's {', '.join(other)}")
    return 0


def camp_on_both(H, J, check):
    """The camp after the dungeon: the host's record decides which specials
    sit by the fire, on both screens, with the travellers that left"""
    left = sorted(t["kind"] for t in H.json("travellers()")
                  if t["outcome"] in ("leaving", "fleeing") and t["special"] == "")
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
