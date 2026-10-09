#!/usr/bin/env python3
"""Danger party bench - proves that in a session the host sets the next
dungeon's danger from every knight's record and every screen builds and
shows the same dungeon at it (issue #96), built for the party's two
knights (issue #102).

Starts tests/dangerparty/Sandbox.qml twice in Clayground's live loader, as
two processes (a host and a joiner), connects them over Local or Cloud
signaling and starts the game on a fixed seed. Both screens start at depth
0 at the host's position. Then four times the bench makes up both knights'
records of the dungeon and the host leads the party down:

- the host holds both records, its own and the joiner's from its state
- in the village both screens have the next dungeon's position the host
  settled from both records: the HP lost averaged, a fall of either knight
  a fall - not the one the host's record alone would give
- in the next dungeon both screens have the same depth and danger and the
  same look: band, light, every torch, the floor, what lies on it, the air
- each dungeon, the first too, is built for two knights on both screens:
  the same enemies, as many as Balance.party adds to the spawn table for
  a second knight, each with the HP it adds

The records take the party to a middle, a low, a middle and a high
dungeon. With --shots <dir> each screen of the first three dungeons after
depth 0 is saved as <dir>/<host|joiner>-depth<N>.png, the knight in the
room after the first; that needs a window, so --shots leaves
QT_QPA_PLATFORM alone unless it is set.

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Usage:
  run_dangerparty.py [--loader <clayliveloader>] [--mode local|cloud]
                     [--seed 424242] [--shots <dir>]

Prints one PASS or FAIL line per check and exits with the number of failed
checks (100: the bench could not get to its end). The temp dir with both
loaders' logs is kept after a failed run.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Balance.danger in src/Balance.qml
START = 0.5
PULL = 0.5
TOP = 0.999
LOW, HIGH = 0.33, 0.67
BANDS = ("low", "middle", "high")

# Each dungeon's made-up records: (share lost, fell) of the host's knight
# and of the joiner's
ROUNDS = [
    ((0.0, False), (0.9, False)),
    ((0.05, False), (0.1, True)),
    ((0.0, False), (0.2, False)),
    ((0.0, False), (0.1, False)),
]


def settle(position, records):
    """Game.settleDanger"""
    fell = any(f for _, f in records)
    lost = sum(min(1, max(0, l)) for l, _ in records) / len(records)
    earned = 0 if fell else 1 - lost
    return max(0, min(TOP, position + (earned - position) * PULL))


def band(position):
    return 0 if position < LOW else 1 if position < HIGH else 2


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

    def shot(self, path):
        resp = self.request({"action": "snapshot", "screenshot": {"path": path}}, 30)
        return resp.get("screenshot"), resp.get("screenshotError")


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
    ap.add_argument("--seed", type=int, default=424242, help="the run's seed")
    ap.add_argument("--shots", help="save each screen of the dungeons here (needs a window)")
    args = ap.parse_args()

    failures = 0

    def check(ok, what):
        nonlocal failures
        print("[DangerParty]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_dangerparty_")
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
    print(f"[DangerParty] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, check):
    """The session; returns 100 when it could not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "dangerparty")
    shutil.copytree(os.path.dirname(os.path.abspath(__file__)), sandbox_dir, ignore=skip)
    sbx = os.path.join(sandbox_dir, "Sandbox.qml")

    env = dict(os.environ)
    if not args.shots:
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
        hd, jd = H.json("danger()"), J.json("danger()")
        check(hd["danger"] == jd["danger"] == START and hd["depth"] == jd["depth"] == 0,
              f"both screens start at depth 0 at the host's danger {START} "
              f"(host {hd['danger']}, joiner {jd['danger']})")
        wait_for(lambda: H.json("look()") == J.json("look()"), 5)
        hl, jl = H.json("look()"), J.json("look()")
        check(hl == jl, "both screens build the first dungeon with the same look"
              + ("" if hl == jl else f" (host {hl}, joiner {jl})"))
        check_foes("depth 0:", H, J, check)

        position = START
        for n, (host_rec, joiner_rec) in enumerate(ROUNDS, 1):
            position = descend(n, position, host_rec, joiner_rec, H, J, args, check)
            if position is None:
                return 100
    except TimeoutError as e:
        return abort(str(e))
    return 0


def descend(n, position, host_rec, joiner_rec, H, J, args, check):
    """One dungeon's records and the way down to the next; returns the
    next dungeon's position, None when it could not get there"""
    tag = f"depth {n - 1} to {n}:"
    H.eval1("calm()")
    H.eval1(f"setRecord({host_rec[0]}, {str(host_rec[1]).lower()})")
    J.eval1(f"setRecord({joiner_rec[0]}, {str(joiner_rec[1]).lower()})")
    # The joiner's record reaches the host with its state
    joiner_seen = wait_for(lambda: (lambda r: len(r) == 2 and abs(r[1]["lost"] - joiner_rec[0]) < 0.002
                                    and r[1]["fell"] == joiner_rec[1])(H.json("records()")), 5)
    records = H.json("records()")
    check(joiner_seen, f"{tag} the host holds both records ({records})")
    want = settle(position, [host_rec, joiner_rec])
    alone = settle(position, [host_rec])
    level = 2 * n

    H.eval(["advance()"])
    if not wait_for(lambda: H.json("danger()")["level"] == level - 1 and J.json("danger()")["level"] == level - 1
                    and H.json("danger()")["standing"] and J.json("danger()")["standing"], 15):
        check(False, f"{tag} both screens go down to the village")
        return None
    hd, jd = H.json("danger()"), J.json("danger()")
    lost = ", ".join(f"{name} {int(round(l * 100))}% lost{' and fell' if f else ''}"
                     for name, (l, f) in (("host", host_rec), ("joiner", joiner_rec)))
    check(abs(hd["next"] - want) < 0.002 and abs(jd["next"] - want) < 0.002,
          f"{tag} in the village both screens have the next position {want:.3f} ({BANDS[band(want)]}) "
          f"settled from both records ({lost}; host {hd['next']}, joiner {jd['next']})")
    check(abs(want - alone) > 0.01,
          f"{tag} the host's record alone would have given {alone:.3f} ({BANDS[band(alone)]})")

    H.eval(["advance()"])
    if not wait_for(lambda: H.eval1("inRun()") is True and J.eval1("inRun()") is True
                    and H.json("danger()")["level"] == level and J.json("danger()")["level"] == level, 15):
        check(False, f"{tag} both screens go down to the dungeon at depth {n}")
        return None
    H.eval1("calm()")
    hd, jd = H.json("danger()"), J.json("danger()")
    check(hd["depth"] == jd["depth"] == n and abs(hd["danger"] - (n + want)) < 0.002
          and hd["danger"] == jd["danger"],
          f"{tag} both screens are at depth {n} at danger {n + want:.3f} "
          f"(host {hd['danger']}, joiner {jd['danger']})")
    # The stairs show each screen's forecast from the records it holds,
    # the other knight's with its next state
    wait_for(lambda: H.json("look()") == J.json("look()"), 5)
    hl, jl = H.json("look()"), J.json("look()")
    check(hl["band"] == jl["band"] == band(want),
          f"{tag} both show a {BANDS[band(want)]} danger dungeon")
    check(hl == jl,
          f"{tag} both build it with the same look: {len(hl['torches'])} torches in "
          f"{hl['torches'][0][2] if hl['torches'] else None}, floor {hl['floor']}, "
          f"{len(hl['onFloor'])} things on it, air {hl['air']}, stairs {hl['stairs']}"
          + ("" if hl == jl else f" (host {hl}, joiner {jl}; host {H.json('records()')} "
                                  f"{H.json('danger()')}, joiner {J.json('records()')} {J.json('danger()')})"))
    check_foes(tag, H, J, check)
    if args.shots and n <= 3:
        os.makedirs(args.shots, exist_ok=True)
        for i in (H, J):
            i.eval1("showRoom()")
        time.sleep(2.0)
        for name, i in (("host", H), ("joiner", J)):
            path = os.path.join(os.path.abspath(args.shots), f"{name}-depth{n}.png")
            saved, err = i.shot(path)
            check(saved is not None, f"{tag} saved {name}-depth{n}.png ({err or saved})")
    return want


def check_foes(tag, H, J, check):
    """Both screens show the same enemies, the dungeon built for two
    knights: as many as the table gives two, each with two knights' HP"""
    wait_for(lambda: H.json("foes()") == J.json("foes()"), 5)
    hf, jf = H.json("foes()"), J.json("foes()")
    n = len(hf["enemies"])
    hp = sorted({f"{e[1]}{e[2]} {e[3]}" for e in hf["enemies"]})
    check(hf == jf and hf["knights"] == 2 and hf["min"] <= n <= hf["max"]
          and all(e[3] == e[4] for e in hf["enemies"]),
          f"{tag} both screens build it for {hf['knights']} knights: the same {n} enemies, "
          f"the table's {hf['min']} to {hf['max']} (one knight's {hf['soloMin']} to {hf['soloMax']}), "
          f"their HP the table's ({', '.join(hp)})"
          + ("" if hf == jf else f" (host {hf}, joiner {jf})"))


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
