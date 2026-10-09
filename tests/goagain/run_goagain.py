#!/usr/bin/env python3
"""Go-again bench - proves that when the whole party has fallen, the host
starts the next run for everyone without leaving the session (issue #99).

Starts tests/goagain/Sandbox.qml twice in Clayground's live loader, as two
processes (a host and a joiner), connects them over Local or Cloud signaling
and starts the game on a fixed seed. Then, three times in a row in the same
session:

- the host goes down to depth 1, both knights take gold, a potion and the
  smith's sword
- the joiner's knight falls, then the host's: both screens show "Your party
  has fallen" and stay in the session; the host's says "Enter to go again",
  the joiner's that it waits for the host
- the host fires a shot that stands beside its knight on both screens and
  meets nothing there - no wall, no knight - nor bursts: only the game can
  take it away
- Enter on the joiner's screen does nothing: both stay fallen on the old seed
- Enter on the host's screen starts the next run on both: depth 0 in a
  dungeon, on the same new seed, with the same enemies (by id, type, tier
  and place), each knight at full HP and mana with no gold, potions or
  upgrade, the other knight standing, at full HP, in the colour it had.
  Nothing of the run before is left: no enemy of it, no shot, no downed
  knight, no gold drop

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_goagain.py [--loader <clayliveloader>] [--mode local|cloud]
                 [--seed 424242] [--runs 3]

Prints one PASS or FAIL line per check and exits with the number of failed
checks (100: the bench could not get to its end). The temp dir with both
loaders' logs is kept after a failed run.
"""

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# The knight's full HP and mana, from src/Balance.qml
KNIGHT_HP = 120
KNIGHT_MANA = 40
# How far an enemy on the joiner may be from the host's: the joiner shows
# the host's enemies some 100 ms in the past, and they walk
PLACE_TOLERANCE_WU = 1.5
HOST_HINT = "Enter to go again • Esc to the title"
JOINER_HINT = "Waiting for the host to go again • Esc to leave the session"


class Inspect:
    def __init__(self, sandbox_dir, instance):
        self.dir = os.path.join(sandbox_dir, ".clay", "inspect", "i", instance)
        self.request_path = os.path.join(self.dir, "request.json")
        self.response_path = os.path.join(self.dir, "response.json")

    def state(self):
        try:
            with open(os.path.join(self.dir, "state.json")) as f:
                return json.load(f)
        except (OSError, json.JSONDecodeError):
            return {}

    def wait_phase(self, phase, timeout=60.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.state().get("phase") == phase:
                return True
            time.sleep(0.1)
        return False

    def request(self, payload, timeout=20.0):
        rid = str(uuid.uuid4())[:8]
        payload = dict(payload)
        payload["id"] = rid
        with open(self.request_path, "w") as f:
            json.dump(payload, f)
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                with open(self.response_path) as f:
                    resp = json.load(f)
                if resp.get("requestId") == rid:
                    return resp
            except (OSError, json.JSONDecodeError):
                pass
            time.sleep(0.01)
        raise TimeoutError(f"no response for {payload.get('action')} ({rid})")

    def eval(self, exprs):
        return self.request({"action": "eval", "eval": exprs}).get("eval", {})

    def eval1(self, expr):
        return self.eval([expr]).get(expr)

    def json(self, expr):
        return json.loads(self.eval1(f"JSON.stringify({expr})") or "null")


def wait_for(cond, timeout=15.0, interval=0.1):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if cond():
                return True
        except (TimeoutError, TypeError, KeyError):
            pass
        time.sleep(interval)
    return False


def find_loader(arg):
    for cand in (arg, os.environ.get("CLAYLIVELOADER"),
                 os.path.join(REPO, "build", "bin", "clayliveloader"),
                 shutil.which("clayliveloader")):
        if cand and os.path.isfile(cand) and os.access(cand, os.X_OK):
            return os.path.abspath(cand)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--loader", help="path to clayliveloader")
    ap.add_argument("--mode", choices=("local", "cloud"), default="local",
                    help="signaling: Local (LAN) or Cloud (PeerJS)")
    ap.add_argument("--seed", type=int, default=424242, help="the first run's seed")
    ap.add_argument("--runs", type=int, default=3, help="how often the party goes again")
    args = ap.parse_args()

    failures = 0

    def check(ok, what):
        nonlocal failures
        print("[GoAgain]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_goagain_")
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
    print(f"[GoAgain] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "goagain")
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
        host_id, joiner_id = H.eval1("nodeId"), J.eval1("nodeId")

        H.eval([f"startGame({args.seed})"])
        if not wait_for(lambda: H.eval1("inRun()") is True and J.eval1("inRun()") is True, 30):
            return abort("the session did not reach the dungeon")
        colors = {"host": H.json("run()")["others"][0]["color"],
                  "joiner": J.json("run()")["others"][0]["color"]}

        for n in range(1, args.runs + 1):
            if fall_and_go_again(n, H, J, host_id, joiner_id, colors, check) == 100:
                return 100
    except TimeoutError as e:
        return abort(str(e))
    return 0


def fall_and_go_again(n, H, J, host_id, joiner_id, colors, check):
    tag = f"run {n}:"
    H.eval(["standUp()"])
    J.eval(["standUp()"])
    # Down to depth 1, so the next run's depth 0 is a change
    H.eval(["advance()"])
    if not wait_for(lambda: H.json("run()")["level"] == 1 and J.json("run()")["level"] == 1
                    and H.eval1("game.player !== null") is True
                    and J.eval1("game.player !== null") is True, 15):
        check(False, f"{tag} both screens go down to the village")
        return 100
    H.eval(["advance()"])
    if not wait_for(lambda: H.eval1("inRun()") is True and J.eval1("inRun()") is True
                    and H.json("run()")["level"] == 2 and J.json("run()")["level"] == 2, 15):
        check(False, f"{tag} both screens go down to the dungeon at depth 1")
        return 100
    for i in (H, J):
        i.eval(["standUp()", "enrich()"])
    old_seed = H.json("run()")["seed"]
    old_ids = set(H.json("enemies()"))

    # The joiner's knight falls first, then the host's
    J.eval(["strikeDown()"])
    if not wait_for(lambda: H.json("run()")["others"][0]["hp"] == 0, 5):
        check(False, f"{tag} the host sees the joiner's knight fall")
        return 100
    H.eval(["strikeDown()"])
    fallen = wait_for(lambda: H.json("run()")["partyFallen"] is True
                      and J.json("run()")["partyFallen"] is True, 10)
    if not check(fallen, f"{tag} with both knights down both screens show the party has fallen"):
        return 100
    hr, jr = H.json("run()"), J.json("run()")
    check(hr["connected"] and jr["connected"] and hr["nodes"] >= 2,
          f"{tag} both stay in the session (connected: host {hr['connected']}, "
          f"joiner {jr['connected']})")
    for r, name, hint in ((hr, "host", HOST_HINT), (jr, "joiner", JOINER_HINT)):
        fs = r["fallenScreen"] or {}
        check(fs.get("title") == "Your party has fallen" and fs.get("hint") == hint,
              f"{tag} the {name}'s screen says \"Your party has fallen\" and \"{hint}\" ({fs})")

    # A shot standing on both screens, to be gone with the run
    shot = H.eval1("shoot()")
    wait_for(lambda: J.eval1(f"hold('{shot}')") is True, 3, 0.02)

    # The joiner's Enter does nothing
    J.eval1("enter()")
    time.sleep(0.6)
    hr, jr = H.json("run()"), J.json("run()")
    check(jr["partyFallen"] and jr["fallenScreen"] is not None and jr["seed"] == old_seed
          and hr["partyFallen"] and hr["seed"] == old_seed,
          f"{tag} Enter on the joiner's screen starts nothing: both stay fallen on seed {old_seed} "
          f"(joiner {jr['seed']}, host {hr['seed']})")
    check((jr["fallenScreen"] or {}).get("hint") == JOINER_HINT,
          f"{tag} the joiner's screen still waits for the host")
    hs, js = H.json("shots()"), J.json("shots()")
    check(shot in hs and shot in js,
          f"{tag} the host's shot {shot} stands on both screens before the next run "
          f"(host {hs}, joiner {js})")

    # The host's Enter starts the next run for both
    H.eval1("enter()")
    went = wait_for(lambda: H.eval1("inRun()") is True and J.eval1("inRun()") is True
                    and H.json("run()")["seed"] != old_seed
                    and J.json("run()")["seed"] == H.json("run()")["seed"], 15)
    if not check(went, f"{tag} Enter on the host's screen starts the next run on both"):
        return 100
    # The joiner has every enemy of the host's
    wait_for(lambda: set(J.json("enemies()")) == set(H.json("enemies()")), 3)
    hr, jr = H.json("run()"), J.json("run()")
    he, je = H.json("enemies()"), J.json("enemies()")
    hs, js = H.json("shots()"), J.json("shots()")
    for i in (H, J):
        i.eval(["standUp()"])

    check(hr["connected"] and jr["connected"] and hr["nodes"] >= 2,
          f"{tag} the session is the same: nobody hosted or joined again")
    check(all(r["level"] == 0 and r["depth"] == 0 and r["type"] == "dungeon"
              and r["screen"] == "game" for r in (hr, jr)),
          f"{tag} both are at depth 0 in a dungeon (host level {hr['level']}, joiner {jr['level']})")
    check(hr["seed"] == jr["seed"] != old_seed,
          f"{tag} both play the same new seed {hr['seed']} (joiner {jr['seed']}, before {old_seed})")
    for r, name in ((hr, "host"), (jr, "joiner")):
        k = r["knight"] or {}
        check(k.get("hp") == k.get("maxHp") == KNIGHT_HP and k.get("mana") == k.get("maxMana") == KNIGHT_MANA,
              f"{tag} the {name}'s knight has full HP and mana ({k.get('hp')}/{k.get('maxHp')}, "
              f"{k.get('mana')}/{k.get('maxMana')})")
        check(k.get("gold") == 0 and k.get("potions") == 0 and k.get("upgrade") == "",
              f"{tag} the {name}'s knight has 0 gold, no potion, no upgrade "
              f"({k.get('gold')}, {k.get('potions')}, '{k.get('upgrade')}')")
        check(not r["fallen"] and not r["partyFallen"] and r["fallenScreen"] is None
              and k.get("downed") is False,
              f"{tag} the {name}'s screen shows no fallen screen and its knight stands")
        others = r["others"]
        check(len(others) == 1 and others[0]["hp"] == KNIGHT_HP and others[0]["downed"] is False
              and others[0]["id"] == (joiner_id if name == "host" else host_id),
              f"{tag} the {name}'s screen shows the other knight once, standing, at full HP ({others})")
        check(len(others) == 1 and others[0]["color"] == colors[name],
              f"{tag} the other knight keeps its colour on the {name}'s screen "
              f"({others[0]['color'] if others else None}, was {colors[name]})")
        check(r["goldDrops"] == 0, f"{tag} no gold drop is left on the {name}'s screen")

    check(len(he) > 0 and set(he) == set(je),
          f"{tag} both screens have the same {len(he)} enemies, by object id "
          f"(host {sorted(he)}, joiner {sorted(je)})")
    same = [i for i in he if i in je and he[i][0] == je[i][0] and he[i][1] == je[i][1]
            and math.hypot(he[i][2] - je[i][2], he[i][3] - je[i][3]) <= PLACE_TOLERANCE_WU]
    check(len(same) == len(he),
          f"{tag} each enemy has the same type, tier and place on both screens "
          f"({len(same)} of {len(he)})")
    stale = {name: sorted(i for i in e if i in old_ids or e[i][4]) for name, e in (("host", he), ("joiner", je))}
    check(not stale["host"] and not stale["joiner"],
          f"{tag} no enemy of the run before is left (host {stale['host']}, joiner {stale['joiner']})")
    check(all(not v[5] and not v[6] for v in he.values()) and all(v[6] for v in je.values()),
          f"{tag} the host runs every enemy, none halted; the joiner shows them")
    check(shot not in hs and shot not in js,
          f"{tag} the run before's shot {shot} is gone on both screens (host {hs}, joiner {js})")
    return 0


def stop(procs):
    insts = procs.pop("inspect", ())
    for i in insts:
        try:
            i.eval(["leave()"])
        except (TimeoutError, OSError):
            pass
    for p in procs.values():
        p.terminate()
    for p in procs.values():
        try:
            p.wait(5)
        except subprocess.TimeoutExpired:
            p.kill()


if __name__ == "__main__":
    main()
