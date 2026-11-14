#!/usr/bin/env python3
"""Boss party bench - proves that in a two-player session both screens see
the same Hollow Warden, its phase and its adds, and that its room opens for
both when it falls (issue #274).

Starts tests/bossparty/Sandbox.qml twice in Clayground's live loader, as
two processes (a host and a joiner), connects them over Local or Cloud
signaling and starts the game on a fixed seed. The host takes the session
down to the dungeon at depth 2, which ends in the Warden's room, and every
other enemy stands. Then:

- both screens build the boss room on the same cells with the same gates,
  the exit's shut and the ways in open, and show the same Warden asleep,
  its HP the table's for two knights
- the host's knight steps into the room, the joiner's stays outside: the
  room stays open on both screens; the joiner's steps in too: it shuts on
  both, the Warden wakes, and both show its banner and its HP bar
- the host strikes it down to Balance.boss.phaseAt of its HP: both screens
  show its phase 2, the same adds by id and the room's light turned; the
  host's zones under the knights show on the joiner's screen, by id
- the host's knight kills it: both screens open every gate, the exit's too,
  show the victory banner, and each heals its own knight to full HP and
  mana

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_bossparty.py [--loader <clayliveloader>] [--mode local|cloud] [--seed 424242]

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
DEPTH = 2


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
        print("[BossParty]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_bossparty_")
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
    print(f"[BossParty] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places. The
    # game's sounds and music are ../sound of src, read only: a link
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    os.symlink(os.path.join(REPO, "sound"), os.path.join(tmp, "sound"))
    sandbox_dir = os.path.join(tmp, "tests", "bossparty")
    shutil.copytree(os.path.dirname(os.path.abspath(__file__)), sandbox_dir, ignore=skip)
    sbx = os.path.join(sandbox_dir, "Sandbox.qml")

    env = dict(os.environ)
    env.setdefault("QT_QPA_PLATFORM", "offscreen")
    env.setdefault("QML_XHR_ALLOW_FILE_READ", "1")
    env["CLAY_SOUND_MUTE"] = "1"
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
        index = H.eval1(f"goToDepth({DEPTH})")
        if not wait_for(lambda: J.eval1("level()") == index and H.json("boss()")["warden"] is not None
                        and J.json("boss()")["warden"] is not None and J.eval1("inRun()") is True, 30):
            return abort(f"the session did not reach the boss dungeon at depth {DEPTH} (level {index})")
        H.eval1("halt()")
        for i in (H, J):
            i.eval(["standUp()"])
        return fight(H, J, check)
    except TimeoutError as e:
        return abort(str(e))


def gates(b):
    return {g["cell"]: (g["exit"], g["shut"]) for g in b["gates"]}


def fight(H, J, check):
    hb, jb = H.json("boss()"), J.json("boss()")
    hw, jw = hb["warden"], jb["warden"]
    check(hb["room"] == jb["room"] and gates(hb) == gates(jb) and len(hb["gates"]) >= 2
          and all(g["shut"] == g["exit"] for g in hb["gates"]) and hb["stage"] == jb["stage"] == "waiting",
          f"both screens build the boss room {hb['room']} with the same {len(hb['gates'])} gates, "
          f"the exit's shut, the ways in open (joiner {jb['stage']}, {len(jb['gates'])} gates)")
    want = H.eval1("game.wardenHp(game.bossAppearance(game.depth), 2, game.danger)")
    check(hw["id"] != "" and hw["id"] == jw["id"] and hw["hp"] == jw["hp"] == hw["maxHp"] == want
          and hw["dormant"] and jw["dormant"] and jw["remote"] and not hw["remote"],
          f"both show the same Warden {hw['id']} asleep, {hw['hp']} HP (joiner {jw['hp']}; "
          f"{want} by the table for two knights)")

    # One knight in: the room stays open; both in: it shuts
    H.eval1("enterRoom(-1.5)")
    J.eval1("leaveRoom()")
    wait_for(lambda: False, 1.5)
    hb, jb = H.json("boss()"), J.json("boss()")
    check(hb["stage"] == jb["stage"] == "waiting" and not any(s for e, s in gates(jb).values() if not e),
          f"the host's knight in, the joiner's outside: the room stays open on both "
          f"(host {hb['stage']}, joiner {jb['stage']})")
    J.eval1("enterRoom(1.5)")
    shut = wait_for(lambda: H.json("boss()")["stage"] == "fight" and J.json("boss()")["stage"] == "fight", 10)
    wait_for(lambda: J.json("boss()")["banner"] > 0.5, 3)
    hb, jb = H.json("boss()"), J.json("boss()")
    check(shut and all(s for e, s in gates(hb).values()) and all(s for e, s in gates(jb).values())
          and not hb["warden"]["dormant"],
          f"the joiner's knight in too: the room shuts on both, every gate, and the Warden wakes "
          f"(host {hb['stage']}, joiner {jb['stage']})")
    check(jb["bar"] and hb["bar"] and wait_for(lambda: H.json("boss()")["banner"] > 0.2, 3),
          "both show its name banner and its HP bar")

    # Phase 2 with its adds and zones
    H.eval1(f"strikeWarden(Balance.boss.phaseAt)")
    ok = wait_for(lambda: J.json("boss()")["warden"]["phase"] == 2
                  and len(J.json("boss()")["adds"]) == len(H.json("boss()")["adds"]) > 0, 10)
    H.eval1("haltAdds()")
    hb, jb = H.json("boss()"), J.json("boss()")
    check(ok and hb["phase"] == jb["phase"] == 2 and hb["adds"] == jb["adds"] and hb["lit"] and jb["lit"]
          and jb["warden"]["hp"] == hb["warden"]["hp"],
          f"the host strikes it to its phase 2: both show phase {hb['phase']}/{jb['phase']}, the same "
          f"{len(hb['adds'])} adds ({', '.join(hb['adds'])}), HP {hb['warden']['hp']}/{jb['warden']['hp']}, "
          f"the light turned")
    zoned = wait_for(lambda: len(H.json("boss()")["zones"]) > 0, 10)
    seen = zoned and wait_for(lambda: set(H.json("boss()")["zones"]) <= set(J.json("boss()")["zones"])
                              or not H.json("boss()")["zones"], 5)
    hz, jz = H.json("boss()")["zones"], J.json("boss()")["zones"]
    check(zoned and seen, f"the host's zones under the knights show on the joiner's screen "
                          f"(host {hz}, joiner {jz})")

    # It falls
    for i in (H, J):
        i.eval1("hurt()")
    H.eval1("killWarden()")
    won = wait_for(lambda: H.json("boss()")["stage"] == "beaten" and J.json("boss()")["stage"] == "beaten", 10)
    wait_for(lambda: J.json("boss()")["victory"] > 0.5, 3)
    hb, jb = H.json("boss()"), J.json("boss()")
    check(won and hb["warden"] is None and jb["warden"] is None
          and not any(s for e, s in gates(hb).values()) and not any(s for e, s in gates(jb).values()),
          f"the host's knight kills it: every gate opens on both screens, the exit's too "
          f"(host {hb['stage']}, joiner {jb['stage']})")
    check(jb["victory"] > 0.2 and wait_for(lambda: H.json("boss()")["victory"] > 0.2, 3),
          "both show the victory banner")
    check(hb["hp"] == hb["maxHp"] and jb["hp"] == jb["maxHp"] and hb["mana"] == hb["maxMana"]
          and jb["mana"] == jb["maxMana"],
          f"each heals its own knight to full HP and mana (host {hb['hp']}/{hb['maxHp']}, "
          f"joiner {jb['hp']}/{jb['maxHp']})")
    return 0


if __name__ == "__main__":
    main()
