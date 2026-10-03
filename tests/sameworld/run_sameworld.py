#!/usr/bin/env python3
"""Same-world bench - proves both screens of a session show the same enemies
(issue #14).

Starts tests/sameworld/Sandbox.qml twice in Clayground's live loader, as two
processes (a host and a joiner), connects them over Local or Cloud signaling
and starts the game on a fixed seed. Then it puts each knight beside an
enemy, lets the joiner's knight land a scripted hit and checks the host
takes it, and lets both knights fight for a few seconds. Every frame each
instance records every enemy it shows: object id, position, HP and AI state.

The comparison. The joiner renders the host's enemies a fixed delay in the
past, 50 ms plus the round trip (Enemy.qml, docs/multiplayer-sync.md), and
each of its records carries that delay. An enemy's position on the joiner
has to be within --tolerance Wu of the host's at that delay, give or take
--slack ms (the host's position between its two frames around that
moment). Its id, HP and AI state have to be ones the host had in the --lag
ms before; an enemy on the host has to show up on the joiner within --lag
ms. Both instances run on one machine: they share the wall clock the
records are stamped with.

Usage:
  run_sameworld.py [--loader <clayliveloader>] [--mode local|cloud]
                   [--seed 424242] [--seconds 8] [--lag 300] [--slack 20]
                   [--tolerance 0.25] [--fault stale] [--json out.json]
                   [--dump records.json]
  run_sameworld.py --judge records.json [--late-ms 200]

--fault stale makes the joiner apply none of the host's enemy states: the
run has to fail then. --dump writes both screens' raw records; --judge
judges such a file again, and --late-ms makes its joiner that much later
than it was: a joiner 200 ms late has to fail.

HP is a number, and Clayground blends every number of a replicated object
(clayground#368): between two of the host's states the joiner shows an HP
between the two. Until the clayground pin carries the fix such a value
counts as within tolerance and is counted (hpBlended); right after the
scripted hit and once the fight is over the HPs have to agree exactly.
The scripted hit walks the knight into the enemy instead of swinging from
a standstill: a resting knight on the joiner never registers a host's
enemy (clayground#369).

Whatever ends the run - its end, an exception, Ctrl-C - both loaders are
stopped and the temp dir is removed; it is kept, with the loaders' logs,
only after a run that got to its end with a failed check.

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground commit
the game's clayground/ submodule pins.

Prints one PASS or FAIL line per check and the numbers as JSON, and exits
with the number of failed checks (0: both screens showed the same world).
"""

import argparse
import bisect
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


def wait_for(cond, timeout=15.0, interval=0.15):
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


def clayground_commit():
    try:
        return subprocess.run(
            ["git", "-C", os.path.join(REPO, "clayground"), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def host_at(host, times, eid, t):
    """The host's position of enemy eid at time t, between its two frames
    around t; None where the host had no such enemy then"""
    i = bisect.bisect_left(times, t)
    if i == 0 or i >= len(host):
        return None
    a, b = host[i - 1], host[i]
    if eid not in a["e"] or eid not in b["e"]:
        return None
    f = (t - a["t"]) / max(1, b["t"] - a["t"])
    pa, pb = a["e"][eid], b["e"][eid]
    return (pa[0] + (pb[0] - pa[0]) * f, pa[1] + (pb[1] - pa[1]) * f)


def compare(host, joiner, lag_ms, slack_ms, skew_ms=20):
    """Each joiner record against the host's: the position against the
    host's at the delay the joiner renders with (its record's d), give or
    take slack_ms; id, HP and AI state against the host's of the lag_ms
    before it. Each host enemy against the joiner's records of the lag_ms
    after it."""
    res = {"joinerRecords": len(joiner), "hostRecords": len(host),
           "judged": 0, "posJudged": 0, "maxErrWu": 0.0, "maxErrAt": "", "sumErrWu": 0.0,
           "unknownIds": 0, "missingIds": 0, "hpMiss": 0, "hpBlended": 0, "stateMiss": 0,
           "delayMs": [], "notes": []}
    if not host or not joiner:
        return res
    times = [s["t"] for s in host]
    t_first = max(host[0]["t"], joiner[0]["t"]) + lag_ms
    # The two records stop a few frames apart: judge only what both had
    t_last_joiner = host[-1]["t"]
    t_last_host = joiner[-1]["t"] - lag_ms
    delays = set()

    def note(s):
        if len(res["notes"]) < 8:
            res["notes"].append(s)

    lo = 0
    for js in joiner:
        t = js["t"]
        if t < t_first or t > t_last_joiner:
            continue
        while lo < len(host) and host[lo]["t"] < t - lag_ms:
            lo += 1
        window = []
        i = lo
        while i < len(host) and host[i]["t"] <= t + skew_ms:
            window.append(host[i]["e"])
            i += 1
        if not window:
            continue
        d = js.get("d", 50)
        delays.add(d)
        shifts = range(d - slack_ms, d + slack_ms + 1, 4)
        for eid, je in js["e"].items():
            seen = [w[eid] for w in window if eid in w]
            res["judged"] += 1
            if not seen:
                res["unknownIds"] += 1
                note(f"{t}: joiner shows {eid}, the host had no such enemy")
                continue
            at = [p for p in (host_at(host, times, eid, t - sh) for sh in shifts) if p]
            if at:
                err = min(dist(je, p) for p in at)
                res["posJudged"] += 1
                res["sumErrWu"] += err
                if err > res["maxErrWu"]:
                    res["maxErrWu"] = err
                    res["maxErrAt"] = f"{eid} ({je[3]})"
            # What the host had then: each record's own, and the states and
            # HPs it passed through since the record before
            hps = {he[2] for he in seen} | {h for he in seen for h in (he[6] if len(he) > 6 else [])}
            states = {he[3] for he in seen} | {x for he in seen for x in (he[5] if len(he) > 5 else [])}
            if je[2] not in hps:
                # Clayground blends every number of a replicated object, HP
                # too (clayground#368): a value between two the host had is
                # within tolerance until the pin carries the fix
                if min(hps) < je[2] < max(hps):
                    res["hpBlended"] += 1
                else:
                    res["hpMiss"] += 1
                    note(f"{t}: {eid} HP {je[2]} on the joiner, host had {sorted(hps)}")
            if je[3] not in states:
                res["stateMiss"] += 1
                note(f"{t}: {eid} {je[3]} on the joiner, host had {sorted(states)}")

    jlo = 0
    for hs in host:
        t = hs["t"]
        if t < t_first or t > t_last_host:
            continue
        while jlo < len(joiner) and joiner[jlo]["t"] < t - skew_ms:
            jlo += 1
        ids = set()
        i = jlo
        while i < len(joiner) and joiner[i]["t"] <= t + lag_ms:
            ids.update(joiner[i]["e"].keys())
            i += 1
        for eid in hs["e"]:
            if eid not in ids:
                res["missingIds"] += 1
                note(f"{t}: host has {eid}, the joiner did not show it within {lag_ms} ms")
    for name, rec in (("host", host), ("joiner", joiner)):
        ts = [s["t"] for s in rec]
        res[name + "MaxFrameGapMs"] = max((b - a for a, b in zip(ts, ts[1:])), default=0)
    res["meanErrWu"] = res["sumErrWu"] / max(1, res["posJudged"])
    res["delayMs"] = sorted(delays)
    del res["sumErrWu"]
    return res


def judge(host_rec, join_rec, args, check):
    """The checks on the two records; returns the comparison"""
    cmp = compare(host_rec, join_rec, args.lag, args.slack)
    states = sorted({e[3] for s in host_rec for e in s["e"].values()})
    n, np = cmp["judged"], cmp["posJudged"]
    ds = cmp["delayMs"]
    delay = f"{ds[0]}" if len(ds) == 1 else f"{ds[0]}-{ds[-1]}" if ds else "?"
    check(n > 0, f"{n} enemy records of the joiner judged against the host's "
          f"({cmp['joinerRecords']} joiner frames, {cmp['hostRecords']} host frames)")
    check("chase" in states and any(s in states for s in ("telegraph", "lunge", "shoot")),
          f"the enemies chased and attacked meanwhile (host states: {', '.join(states)})")
    check(cmp["unknownIds"] == 0 and cmp["missingIds"] == 0,
          f"every enemy id agrees within {args.lag} ms ({cmp['unknownIds']} on the joiner "
          f"only, {cmp['missingIds']} on the host only)")
    check(np > 0 and cmp["maxErrWu"] <= args.tolerance,
          f"every enemy's position is within {args.tolerance} Wu of the host's {delay} ms "
          f"(50 + rtt) +-{args.slack} ms before (max {cmp['maxErrWu']:.3f} at "
          f"{cmp['maxErrAt']}, mean {cmp['meanErrWu']:.3f}, {np} judged)")
    check(n > 0 and cmp["hpMiss"] == 0,
          f"every enemy's HP agrees within {args.lag} ms ({cmp['hpMiss']} misses, "
          f"{cmp['hpBlended']} blended between two of the host's, clayground#368)")
    check(n > 0 and cmp["stateMiss"] == 0,
          f"every enemy's AI state agrees within {args.lag} ms ({cmp['stateMiss']} misses)")
    for s in cmp["notes"]:
        print("[SameWorld]   e.g.", s)
    cmp["hostStates"] = states
    return cmp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--loader", help="path to clayliveloader")
    ap.add_argument("--mode", choices=("local", "cloud"), default="local",
                    help="signaling: Local (LAN) or Cloud (PeerJS)")
    ap.add_argument("--seed", type=int, default=424242, help="the game's seed")
    ap.add_argument("--seconds", type=float, default=8.0, help="how long the knights fight")
    ap.add_argument("--lag", type=int, default=300,
                    help="ms the joiner may show an id, HP or AI state after the host")
    ap.add_argument("--slack", type=int, default=20,
                    help="ms the joiner's position may be off the expected delay")
    ap.add_argument("--tolerance", type=float, default=0.25,
                    help="Wu an enemy on the joiner may be from the host's at that delay")
    ap.add_argument("--fault", choices=("stale",),
                    help="stale: the joiner applies none of the host's enemy states")
    ap.add_argument("--json", help="also write the numbers to this file")
    ap.add_argument("--dump", help="write both screens' raw records to this file")
    ap.add_argument("--judge", metavar="DUMP",
                    help="judge the records of an earlier --dump instead of running")
    ap.add_argument("--late-ms", type=int, default=0,
                    help="with --judge: make the joiner this much later than it was")
    args = ap.parse_args()

    failures = 0

    def check(ok, what):
        nonlocal failures
        print("[SameWorld]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            failures += 1
        return ok

    if args.judge:
        with open(args.judge) as f:
            rec = json.load(f)
        joiner = [dict(s, t=s["t"] + args.late_ms) for s in rec["joiner"]]
        print(f"[SameWorld] judging {args.judge}, the joiner {args.late_ms} ms later", flush=True)
        judge(rec["host"], joiner, args, check)
        print(f"[SameWorld] done, {failures} failed")
        sys.exit(min(failures, 100))

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(100)

    tmp = tempfile.mkdtemp(prefix="sas_sameworld_")
    procs = {}
    result = {"mode": args.mode, "seed": args.seed, "fault": args.fault or "",
              "lagMs": args.lag, "slackMs": args.slack, "toleranceWu": args.tolerance,
              "clayground": clayground_commit()}
    # Whatever happens - a failed check, an exception, Ctrl-C - both
    # loaders are stopped and the temp dir goes; it stays only after a run
    # that got to its end with a failed check, for the logs
    aborted, finished = True, False
    try:
        aborted = run(args, loader, tmp, procs, result, check) == 100
        finished = True
    finally:
        stop(procs)
        code = 100 if aborted else failures
        if finished and code != 0:
            print("Logs kept at:", tmp, file=sys.stderr)
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    print(f"[SameWorld] done, {failures} failed")
    sys.exit(min(code, 100))


def run(args, loader, tmp, procs, result, check):
    """The session; returns the number of failed checks, 100 when it could
    not get to the end"""
    # The sandbox imports ../../src: copy both, keeping their places
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "sameworld")
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
        print(json.dumps(result, indent=2))
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
        result["code"] = code
        J.eval([f"joinNet('{code}')"])
        if not wait_for(lambda: J.eval1("connected") is True and H.eval1("nodeCount") >= 2, 40):
            return abort(f"the joiner did not connect to {code}")
        check(True, f"two processes connected over {args.mode} signaling ({code})")

        H.eval([f"startGame({args.seed})"])
        if not wait_for(lambda: H.eval1("inGame()") is True and J.eval1("inGame()") is True
                        and H.eval1("enemyCount") == J.eval1("enemyCount"), 30):
            return abort("the session did not reach the dungeon with the same enemy count")
        if args.fault == "stale":
            print("[SameWorld] fault stale: the joiner applies the state of none of its",
                  J.eval1("stale()"), "enemies from here on", flush=True)
        check(J.eval1("seed") == args.seed,
              f"both play seed {args.seed} (joiner {J.eval1('seed')})")

        he, je = H.json("enemies()"), J.json("enemies()")
        result["enemies"] = len(he)
        check(sorted(he) == sorted(je),
              f"both screens have the same {len(he)} enemies, by object id")
        check(all(not v[4] for v in he.values()) and all(v[4] for v in je.values()),
              "the host runs every enemy, the joiner shows them")

        # The host's knight at one enemy, the joiner's at the one farthest from it
        ids = sorted(he)
        a, b = max(((x, y) for x in ids for y in ids), key=lambda p: dist(he[p[0]], he[p[1]]))
        H.eval([f"placeBeside('{a}')"])
        J.eval([f"placeBeside('{b}')"])
        H.eval(["record(true)"])
        J.eval(["record(true)"])
        host_rec, join_rec = [], []

        def pull():
            host_rec.extend(H.json("take()") or [])
            join_rec.extend(J.json("take()") or [])

        # The scripted hit: the joiner's knight walks into enemy b and
        # strikes it (walks: clayground#369); the host applies the blow,
        # the joiner shows the host's HP
        hp0 = H.eval1(f"hpOf('{b}')")
        landed = False
        deadline = time.time() + 5
        swings = 0
        while time.time() < deadline and not landed:
            J.eval([f"strike('{b}')"])
            swings += 1
            landed = wait_for(lambda: H.eval1(f"hpOf('{b}')") < hp0, 0.8, 0.05)
            pull()
        hp1 = H.eval1(f"hpOf('{b}')")
        knight_at = f"knightAt('{b}')"
        result["hit"] = {"enemy": b, "hpBefore": hp0, "hpAfter": hp1, "swings": swings}
        check(landed, f"the joiner's scripted hit on {b} lands on the host (HP {hp0} -> {hp1})"
              + ("" if landed else f", the joiner's knight: {J.json(knight_at)}"))
        same_hp = wait_for(lambda: J.eval1(f"hpOf('{b}')") == H.eval1(f"hpOf('{b}')"), 2, 0.05)
        hp_h, hp_j = H.eval1(f"hpOf('{b}')"), J.eval1(f"hpOf('{b}')")
        check(same_hp, f"the joiner shows the host's HP of {b} after the hit "
              f"(joiner {hp_j}, host {hp_h})")

        # The fight
        H.eval(["fight(true)"])
        J.eval(["fight(true)"])
        end = time.time() + args.seconds
        while time.time() < end:
            time.sleep(0.5)
            pull()
        H.eval(["fight(false)"])
        J.eval(["fight(false)"])
        time.sleep(args.lag / 1000 + 0.2)
        pull()
        H.eval(["record(false)"])
        J.eval(["record(false)"])
        # At rest from blows, the joiner shows the host's HP exactly
        he, je = H.json("enemies()"), J.json("enemies()")
        off = sorted(i for i in he if i in je and he[i][2] != je[i][2])
        check(sorted(he) == sorted(je) and not off,
              f"after the fight both screens have the same {len(he)} enemies with the same HP"
              + (f" (differ: {', '.join(f'{i} {je[i][2]}/{he[i][2]}' for i in off)})" if off else "")
              + ("" if sorted(he) == sorted(je) else f" (ids: host {sorted(he)}, joiner {sorted(je)})"))

        if args.dump:
            with open(args.dump, "w") as f:
                json.dump({"host": host_rec, "joiner": join_rec}, f)
        result["compare"] = judge(host_rec, join_rec, args, check)
    except TimeoutError as e:
        return abort(str(e))

    print(json.dumps(result, indent=2))
    if args.json:
        with open(args.json, "w") as f:
            json.dump(result, f, indent=2)
            f.write("\n")
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
