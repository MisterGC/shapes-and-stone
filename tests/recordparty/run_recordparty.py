#!/usr/bin/env python3
"""Record party bench - proves that in a session the host's record is the
party's: every screen shows it, and every screen gets the banner when the
party passes it (issue #101).

Starts tests/recordparty/Sandbox.qml twice in Clayground's live loader, as
two processes (a host and a joiner), each with a record store of its own:
the host's knight is "Cy" and its record depth 2 by "Ana", the joiner's
knight is "Dee" and its own record depth 7. Both start in the lobby,
connect over Local or Cloud signaling and the host starts the game on a
fixed seed. Then:

- both lobbies show the host's record, not the joiner's own, and both
  screens know both knights' names
- both HUDs show "record 2"; down to depth 2 no screen raises a banner
- on depth 3 both screens raise the banner, once; the host stores depth 3
  with both names and today, and both HUDs follow to "record 3"; depth 4
  raises no second banner
- both knights fall: both fall screens say "New record" and list the run
  with its depth and time
- the host goes again; the party falls at depth 1 without a banner, and
  both fall screens show the host's record and list both runs, newest
  first, the same on both
- the joiner's own record stays depth 7: the party's record is the host's

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_recordparty.py [--loader <clayliveloader>] [--mode local|cloud]
                     [--seed 424242]

Prints one PASS or FAIL line per check and exits with the number of failed
checks (100: the bench could not get to its end). The temp dir with both
loaders' logs is kept after a failed run.
"""

import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "goagain"))
from run_goagain import Inspect, find_loader, stop, wait_for  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

HOST_RECORD = {"depth": 2, "names": ["Ana"], "date": "2026-10-01"}
JOINER_RECORD = {"depth": 7, "names": ["Dee"], "date": "2026-09-30"}
HOST_LINE = "Record 2  •  Ana  •  2026-10-01"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--loader", help="path to clayliveloader")
    ap.add_argument("--mode", choices=("local", "cloud"), default="local",
                    help="signaling: Local (LAN) or Cloud (PeerJS)")
    ap.add_argument("--seed", type=int, default=424242, help="the first run's seed")
    args = ap.parse_args()

    failures = 0

    def check(ok, what):
        nonlocal failures
        print("[RecordParty]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_recordparty_")
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
    print(f"[RecordParty] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "recordparty")
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
    today = datetime.date.today().isoformat()

    def abort(what):
        check(False, what)
        return 100

    def both(cond, timeout=15):
        return wait_for(lambda: cond(H.json("show()")) and cond(J.json("show()")), timeout)

    def down_to(level):
        H.eval(["advance()"])
        ok = both(lambda s: s["level"] == level and s["screen"] == "game", 15)
        for i in (H, J):
            i.eval(["standUp()"])
        return ok

    try:
        if not (H.wait_phase("ready") and J.wait_phase("ready")):
            return abort("the two instances did not load")
        local = "true" if args.mode == "local" else "false"
        for i, role, rec, name in ((H, "host", HOST_RECORD, "Cy"), (J, "joiner", JOINER_RECORD, "Dee")):
            if i.eval1(f"prepare({local}, '{role}', '{json.dumps(rec)}', '{name}')") is not True:
                return abort("no Network in the game's session")
        H.eval(["hostUp()"])
        if not wait_for(lambda: H.eval1("netId") not in (None, ""), 30):
            return abort("the host got no network code")
        code = H.eval1("netId")
        J.eval([f"joinNet('{code}')"])
        if not wait_for(lambda: J.eval1("connected") is True and H.eval1("nodeCount") >= 2, 40):
            return abort(f"the joiner did not connect to {code}")
        check(True, f"two processes connected over {args.mode} signaling ({code})")

        # The lobby
        both(lambda s: s["lobby"] == HOST_LINE and sorted(s["names"]) == ["Cy", "Dee"], 10)
        hs, js = H.json("show()"), J.json("show()")
        for s, who in ((hs, "host"), (js, "joiner")):
            check(s["lobby"] == HOST_LINE,
                  f"the {who}'s lobby shows the host's record ({s['lobby']})")
            check(s["names"] == ["Cy", "Dee"],
                  f"the {who}'s screen knows both knights' names, the host's first ({s['names']})")

        H.eval([f"startGame({args.seed})"])
        if not wait_for(lambda: H.eval1("inRun()") is True and J.eval1("inRun()") is True, 30):
            return abort("the session did not reach the dungeon")
        for i in (H, J):
            i.eval(["standUp()"])
        hs, js = H.json("show()"), J.json("show()")
        for s, who in ((hs, "host"), (js, "joiner")):
            check(s["hud"] == "record 2", f"the {who}'s HUD shows the host's \"record 2\" ({s['hud']})")

        # Down to the record's depth: no banner
        for level in (1, 2, 3, 4):
            if not down_to(level):
                return abort(f"both screens go down to level {level}")
        time.sleep(0.5)
        hs, js = H.json("show()"), J.json("show()")
        check(hs["depth"] == js["depth"] == 2 and hs["banners"] == [] and js["banners"] == [],
              f"down to depth 2 neither screen raises a banner (host {hs['banners']}, "
              f"joiner {js['banners']})")

        # Past it
        for level in (5, 6):
            if not down_to(level):
                return abort(f"both screens go down to level {level}")
        got = both(lambda s: len(s["banners"]) >= 1, 5)
        hs, js = H.json("show()"), J.json("show()")
        check(got and hs["banners"] == [3] and js["banners"] == [3],
              f"at depth 3 both screens raise the banner (host {hs['banners']}, joiner {js['banners']})")
        check(hs["stored"] == {"depth": 3, "names": ["Cy", "Dee"], "date": today},
              f"the host stores depth 3 with both names and today ({hs['stored']})")
        both(lambda s: s["hud"] == "record 3", 5)
        hs, js = H.json("show()"), J.json("show()")
        for s, who in ((hs, "host"), (js, "joiner")):
            check(s["hud"] == "record 3", f"the {who}'s HUD follows to \"record 3\" ({s['hud']})")
        for level in (7, 8):
            if not down_to(level):
                return abort(f"both screens go down to level {level}")
        time.sleep(0.5)
        hs, js = H.json("show()"), J.json("show()")
        check(hs["banners"] == [3] and js["banners"] == [3],
              f"depth 4 raises no second banner (host {hs['banners']}, joiner {js['banners']})")

        # The party falls
        J.eval(["strikeDown()"])
        time.sleep(0.5)
        H.eval(["strikeDown()"])
        if not both(lambda s: s["partyFallen"] and s["runs"] is not None and len(s["runs"]) == 1, 10):
            return abort("both screens show the party has fallen with its run")
        hs, js = H.json("show()"), J.json("show()")
        for s, who in ((hs, "host"), (js, "joiner")):
            check(s["fallenRecord"] == "New record",
                  f"the {who}'s fall screen says \"New record\" ({s['fallenRecord']})")
            check(len(s["runs"]) == 1 and re.fullmatch(r"Run 1  •  Depth 4  •  \d+:\d\d", s["runs"][0]),
                  f"the {who}'s fall screen lists the run with depth and time ({s['runs']})")

        # Again: the party falls at depth 1, short of the record
        old_seed = hs["seed"]
        H.eval1("enter()")
        if not wait_for(lambda: H.eval1("inRun()") is True and J.eval1("inRun()") is True
                        and H.json("show()")["seed"] != old_seed
                        and J.json("show()")["seed"] == H.json("show()")["seed"], 15):
            return abort("the host's Enter starts the next run on both")
        for i in (H, J):
            i.eval(["standUp()"])
        hs, js = H.json("show()"), J.json("show()")
        for s, who in ((hs, "host"), (js, "joiner")):
            check(s["hud"] == "record 4", f"the next run's HUD on the {who}'s screen shows \"record 4\" "
                  f"({s['hud']})")
        for level in (1, 2):
            if not down_to(level):
                return abort(f"run 2: both screens go down to level {level}")
        J.eval(["strikeDown()"])
        time.sleep(0.5)
        H.eval(["strikeDown()"])
        if not both(lambda s: s["partyFallen"] and s["runs"] is not None and len(s["runs"]) == 2, 10):
            return abort("run 2: both screens show the party has fallen with both runs")
        hs, js = H.json("show()"), J.json("show()")
        line = f"Record 4  •  Cy, Dee  •  {today}"
        for s, who in ((hs, "host"), (js, "joiner")):
            check(s["banners"] == [3], f"run 2 raises no banner on the {who}'s screen ({s['banners']})")
            check(s["fallenRecord"] == line,
                  f"the {who}'s fall screen shows the host's record ({s['fallenRecord']})")
            check(re.fullmatch(r"Run 2  •  Depth 1  •  \d+:\d\d", s["runs"][0]) is not None
                  and re.fullmatch(r"Run 1  •  Depth 4  •  \d+:\d\d", s["runs"][1]) is not None,
                  f"the {who}'s fall screen lists both runs, newest first ({s['runs']})")
        check(hs["runs"] == js["runs"], f"both fall screens list the same runs (host {hs['runs']}, "
              f"joiner {js['runs']})")
        check(js["stored"] == JOINER_RECORD,
              f"the joiner's own record stays depth 7 ({js['stored']})")
    except TimeoutError as e:
        return abort(str(e))
    return 0


if __name__ == "__main__":
    main()
