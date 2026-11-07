#!/usr/bin/env python3
"""Fight bench - plays the "fight" scenario with a scripted knight and
reports how the fight went (issues #34, #267).

Starts tests/fightbench/Sandbox.qml in Clayground's live loader, pauses the
game and enters the fight room, then steps the world through the inspector
protocol, a few physics steps at a time, until the room is cleared or the
knight has fallen. The scripted knight lives in the sandbox and acts on
every step, so the same seed gives the same report on every run. The game
is muted and the loader is started with CLAY_SOUND_MUTE=1, so nothing is
heard; what a player would have heard is in the report: the game's sound
log (cue, time, pitch, distance) and its music trace (state, segment,
intensity).

Usage:
  run_fightbench.py [--loader <clayliveloader>] [--seed 424242]
                    [--answer mix|block|parry|perfect|heavy|whirlwind|charge|masher|skilled]
                    [--room mixed|flow|duel] [--sword N]
                    [--depth 0 | --danger 0.0] [--max-seconds 180] [--json out.json]
  run_fightbench.py --pacing [--check] [--rooms flow duel] [--depths 0 2 4]
                    [--answers charge masher skilled] [--jobs N] [--json out.json]

One fight prints its report as JSON. --answer is how the scripted knight
meets a grunt's or a guardian's attack: "mix" parries or blocks as the
seed rolls, "block" always blocks, "parry" always parries, "perfect"
raises the shield 4 physics steps before each lunge lands, a perfect
block, "heavy" meets attacks as "mix" does but charges a heavy swing at a
guardian instead of shield-dashing it, "whirlwind" fights as "mix" does
and, once its momentum is full, whirls (Q) at the nearest enemy within
reach. The report counts the whirlwinds that landed (hit an enemy), their
hits and the ones begun. The pacing pilots: "charge" holds a full charge
and lets go at the nearest enemy, "masher" clicks, "skilled" parries,
perfect-blocks and strikes in openings. --room is who stands in the fight
room: "mixed" its usual lineup (Balance.spawn.fightRoom), "flow" fodder
only and "duel" a room's lead alone (Balance.pacing). --sword is the
knight's sword level: by default 0 in the mixed room and in flow and duel
the one a knight usually has at that depth. --danger is the danger the
fight room is at, its depth plus a position in the depth's range (2.5:
half way through depth 2's): the lineup stays, the enemies hit as hard as
at that danger. --depth d is --danger d, the bottom of the depth's range.
The same seed and danger give the same numbers.

--pacing plays every room of --rooms at every depth of --depths with every
pilot of --answers (by default flow and duel, Balance.pacing.depths, and
charge, masher and skilled), --jobs loaders at a time, prints a report of
each fight - per enemy its time to kill and hits to kill, the gaps between
kills, the time engaged, the damage taken, openings, cancelled charges,
what was heard - and, with --check, one PASS or FAIL line per band of
Balance.pacing. --json writes every report in full, sound log and music
trace included. Exits 1 when a band fails under --check, 2 when a fight
could not be played.

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground
commit the game's clayground/ submodule pins.
"""

import argparse
import concurrent.futures
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from collections import Counter

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ANSWERS = ("mix", "block", "parry", "perfect", "heavy", "whirlwind", "charge", "masher", "skilled")
PILOTS = ("charge", "masher", "skilled")


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


class FightError(Exception):
    def __init__(self, message, logs):
        super().__init__(message)
        self.logs = logs


def start_loader(loader):
    """The sandbox in a loader of its own: (its temp dir, its inspector, the
    loader's process, its log)"""
    # The sandbox imports ../../src: copy both, keeping their places. The
    # game's sounds and music are ../sound of src, read only: a link
    tmp = tempfile.mkdtemp(prefix="sas_fightbench_")
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    os.symlink(os.path.join(REPO, "sound"), os.path.join(tmp, "sound"))
    sandbox_dir = os.path.join(tmp, "tests", "fightbench")
    shutil.copytree(os.path.dirname(os.path.abspath(__file__)), sandbox_dir, ignore=skip)

    env = dict(os.environ)
    env.setdefault("QT_QPA_PLATFORM", "offscreen")
    # The game reads sound/*.json through XMLHttpRequest, which Qt refuses
    # for local files unless allowed; and nothing is to be heard
    env.setdefault("QML_XHR_ALLOW_FILE_READ", "1")
    env["CLAY_SOUND_MUTE"] = "1"
    log = open(os.path.join(tmp, "loader.log"), "w")
    proc = subprocess.Popen(
        [loader, "--sbx", os.path.join(sandbox_dir, "Sandbox.qml"), "--instance", "fight"],
        cwd=os.path.dirname(loader), env=env, stdout=log, stderr=subprocess.STDOUT)
    return tmp, Inspect(sandbox_dir, "fight"), proc, log


def stop_loader(proc, log):
    proc.terminate()
    try:
        proc.wait(5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    log.close()


def read_pacing(loader):
    """Balance.pacing as the game has it, read from a loaded sandbox, or
    raises FightError"""
    tmp, bench, proc, log = start_loader(loader)
    try:
        if not bench.wait_phase("ready"):
            raise FightError("the sandbox did not load", tmp)
        pacing = json.loads(bench.eval1("JSON.stringify(Balance.pacing)") or "null")
    except (TimeoutError, json.JSONDecodeError, TypeError) as e:
        raise FightError(f"Balance.pacing could not be read: {e}", tmp)
    finally:
        stop_loader(proc, log)
    if not isinstance(pacing, dict) or not isinstance(pacing.get("depths"), list) or not pacing["depths"]:
        raise FightError(f"Balance.pacing has no depths: {pacing!r}", tmp)
    shutil.rmtree(tmp, ignore_errors=True)
    return pacing


def play_fight(loader, seed, answer, danger, room, sword, max_seconds, batch):
    """Plays one fight in a loader of its own; returns its report, or raises
    FightError with the directory the logs are kept in"""
    tmp, bench, proc, log = start_loader(loader)
    try:
        if not bench.wait_phase("ready"):
            raise FightError("the sandbox did not load", tmp)
        if bench.eval1(f"begin({seed}, '{answer}', {danger}, '{room}', {sword})") is not True:
            raise FightError("the fight room did not start", tmp)
        # Let what the scene sets up on its first frames settle before step 1
        time.sleep(1.0)

        # Clayground's MoveTo re-aims on simulated time (clayground#340), so
        # a batch of steps run in one go re-aims as often as a running game
        # does, and the batches follow each other without a pause.
        max_steps = int(max_seconds * 60)
        while True:
            resp = bench.request({"action": "batch", "steps": [
                {"action": "time", "step": batch},
                {"action": "eval", "eval": ["done", "steps"]}]})
            if resp.get("error"):
                raise FightError(resp["error"], tmp)
            state = resp["steps"][1].get("eval", {})
            if state.get("done") is True or state.get("steps", 0) >= max_steps:
                break

        result = json.loads(bench.eval1("JSON.stringify(report())") or "{}")
        result["pacing"] = json.loads(bench.eval1("JSON.stringify(Balance.pacing)") or "{}")
        result["clayground"] = clayground_commit()
    except TimeoutError as e:
        raise FightError(str(e), tmp)
    finally:
        stop_loader(proc, log)
    # What the sound engine said of the audio output: on a machine with
    # none, that it found none
    with open(os.path.join(tmp, "loader.log"), errors="replace") as f:
        said = sorted({line.split("AudioOutput:", 1)[1].strip() for line in f
                       if "clay::sound::AudioOutput:" in line})
    result["audioOutput"] = said
    shutil.rmtree(tmp, ignore_errors=True)
    return result


# ---- the pacing report ----

TIERS = ("weak", "normal", "tough")


def fmt_s(v):
    return "-" if v is None else f"{v:.2f} s"


def describe(r):
    """The report of one fight as lines of text"""
    lines = [f"{r['room']} depth {r['depth']} sword {r['sword']} {r['answer']}: "
             f"{r['outcome']} after {r['seconds']:.2f} s, damage taken {r['damageTaken']}, "
             f"openings {r['openings']}, cancelled charges {r['cancelledCharges']}, "
             f"engaged {r['engagedSeconds']:.2f} s"]
    for e in r["enemies"]:
        # A lead's openings by what broke its stance (Balance.lead)
        opened = e.get("opened") or {}
        by = (" (" + ", ".join(f"{c} {n}" for c, n in sorted(opened.items())) + ")") if opened else ""
        lead = ", lead" if e.get("lead") else ""
        lines.append(f"  {e['type']} ({TIERS[e['tier']]}{lead}, {e['hp']} HP): hits {e['hits']}, "
                     f"ttk {fmt_s(e['ttk'])} from its first hit, {fmt_s(e['ttkEngaged'])} "
                     f"from engaging, died at {fmt_s(e['diedAt'])}, openings {e['openings']}{by}")
    if r["killGaps"]:
        lines.append("  gaps between kills: " + ", ".join(f"{g:.2f}" for g in r["killGaps"]) + " s")
    cues = Counter(s["cue"] + ("" if not s["pitch"] else f"{s['pitch']:+d}") for s in r["sounds"])
    lines.append(f"  heard: {len(r['sounds'])} sounds - "
                 + ", ".join(f"{c} {n}" for c, n in sorted(cues.items(), key=lambda kv: -kv[1])))
    music = r["music"]
    if music:
        peak = max(m["intensity"] for m in music)
        states = sorted({f"{m['song']} {m['state']}/{m['segment'] or '-'}" for m in music})
        lines.append(f"  music: {', '.join(states)}; intensity {music[0]['intensity']:.2f} "
                     f"at the start, peak {peak:.2f}, {music[-1]['intensity']:.2f} at the end "
                     f"({len(music)} trace rows)")
    return lines


def check(results, bands):
    """One (ok, line) per band of Balance.pacing for the fights played"""
    out = []
    for r in results:
        if r["room"] != "flow":
            continue
        tag = f"flow depth {r['depth']} {r['answer']}"
        lo, hi = bands["flowHits"].get(r["answer"], [1, 3])
        out.append((r["outcome"] != "fallen", f"{tag}: the knight does not fall ({r['outcome']})"))
        for e in r["enemies"]:
            ok = e["diedAt"] is not None and lo <= e["hits"] <= hi
            hits = f"{lo}" if lo == hi else f"{lo}-{hi}"
            out.append((ok, f"{tag}: {e['type']} ({TIERS[e['tier']]}) dies to {hits} {'hit' if hi == 1 else 'hits'} "
                            f"({e['hits']}{'' if e['diedAt'] is not None else ', alive'})"))
        gap = max(r["killGaps"]) if r["killGaps"] else 0
        cleared = r["outcome"] == "cleared"
        out.append((cleared and gap <= bands["flowGap"],
                    f"{tag}: no gap between kills over {bands['flowGap']} s "
                    f"(longest {gap:.2f} s{'' if cleared else ', not cleared'})"))
    duels = {}
    for r in results:
        if r["room"] == "duel":
            duels.setdefault(r["depth"], {})[r["answer"]] = r
    for depth, by in sorted(duels.items()):
        def lead_time(r):
            leads = [e for e in r["enemies"] if e["tier"] == 2] or r["enemies"]
            return leads[0]["ttkEngaged"]
        for pilot in ("masher", "charge"):
            r = by.get(pilot)
            if not r:
                continue
            t = lead_time(r)
            ok = r["outcome"] == "fallen" or t is None or t >= bands["duelSlow"]
            what = "fell" if r["outcome"] == "fallen" else "alive" if t is None else f"{t:.2f} s"
            out.append((ok, f"duel depth {depth} {pilot}: takes at least {bands['duelSlow']} s "
                            f"or falls ({what})"))
        r = by.get("skilled")
        if r:
            t = lead_time(r)
            lo, hi = bands["duelSkilled"]
            ok = r["outcome"] == "cleared" and t is not None and lo <= t <= hi
            what = r["outcome"] if t is None else f"{t:.2f} s, {r['outcome']}"
            out.append((ok, f"duel depth {depth} skilled: kills the lead in {lo}-{hi} s ({what})"))
            others = [by[p] for p in ("masher", "charge") if p in by]
            if others:
                took = ", ".join(f"{o['answer']} {o['damageTaken']}" for o in others)
                out.append((all(r["damageTaken"] < o["damageTaken"] for o in others),
                            f"duel depth {depth} skilled: takes less damage than the others "
                            f"({r['damageTaken']}; {took})"))
    return out


def pacing(args, loader):
    rooms = args.rooms or ["flow", "duel"]
    answers = args.answers or list(PILOTS)
    fights = []
    # The depths are the game's own (Balance.pacing.depths), read as the
    # bands are, unless given
    depths = args.depths
    if not depths:
        try:
            depths = read_pacing(loader)["depths"]
        except FightError as e:
            print(f"FAIL {e}; logs in {e.logs}", file=sys.stderr)
            sys.exit(2)
    for room in rooms:
        for depth in depths:
            for answer in answers:
                fights.append((room, depth, answer))
    results, errors = {}, []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(play_fight, loader, args.seed, a, d, room, -1, args.max_seconds,
                               args.batch): (room, d, a) for room, d, a in fights}
        for fut in concurrent.futures.as_completed(futures):
            key = futures[fut]
            try:
                results[key] = fut.result()
            except FightError as e:
                errors.append(f"FAIL {key[0]} depth {key[1]} {key[2]}: {e}; logs in {e.logs}")
    ordered = [results[k] for k in fights if k in results]
    for r in ordered:
        print("\n".join(describe(r)))
    if ordered:
        said = sorted({s for r in ordered for s in r["audioOutput"]})
        print(f"clayground {ordered[0]['clayground']}, seed {args.seed}; the audio output "
              + ("said: " + "; ".join(said) if said
                 else "said nothing; CLAY_SOUND_MUTE=1 holds any output at volume 0"))
    if args.json:
        with open(args.json, "w") as f:
            json.dump(ordered, f, indent=2)
            f.write("\n")
    failed = 0
    if args.check and ordered:
        lines = check(ordered, ordered[0]["pacing"])
        print()
        for ok, line in lines:
            print(("PASS " if ok else "FAIL ") + line)
        failed = sum(1 for ok, _ in lines if not ok)
        print(f"{len(lines) - failed} of {len(lines)} bands pass")
    for e in errors:
        print(e, file=sys.stderr)
    if errors:
        sys.exit(2)
    sys.exit(1 if failed else 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--loader", help="path to clayliveloader")
    ap.add_argument("--seed", type=int, default=424242,
                    help="seed of the scripted knight's choices")
    ap.add_argument("--answer", choices=ANSWERS, default="mix",
                    help="how the scripted knight fights")
    ap.add_argument("--room", choices=("mixed", "flow", "duel"), default="mixed",
                    help="who stands in the fight room")
    ap.add_argument("--sword", type=int,
                    help="the knight's sword level; default 0 in the mixed room, else the usual one")
    ap.add_argument("--depth", type=int, default=0,
                    help="depth the fight room is at, at the bottom of its range")
    ap.add_argument("--danger", type=float,
                    help="danger the fight room is at: depth plus position, e.g. 2.5")
    ap.add_argument("--max-seconds", type=float, default=180.0,
                    help="simulated seconds before the fight counts as not finished")
    ap.add_argument("--batch", type=int, default=6,
                    help="physics steps per inspector request")
    ap.add_argument("--json", help="also write the report(s) to this file")
    ap.add_argument("--pacing", action="store_true",
                    help="play the pacing rooms at their depths with the pacing pilots")
    ap.add_argument("--check", action="store_true",
                    help="with --pacing: fail a fight outside the bands of Balance.pacing")
    ap.add_argument("--rooms", nargs="+", choices=("flow", "duel"), help="--pacing: these rooms")
    ap.add_argument("--depths", nargs="+", type=int, help="--pacing: these depths")
    ap.add_argument("--answers", nargs="+", choices=ANSWERS, help="--pacing: these pilots")
    ap.add_argument("--jobs", type=int, default=max(1, min(4, (os.cpu_count() or 2) // 2)),
                    help="--pacing: loaders at a time")
    args = ap.parse_args()

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(2 if args.pacing else 1)
    if args.check and not args.pacing:
        ap.error("--check needs --pacing")
    if args.pacing:
        pacing(args, loader)
        return

    danger = args.danger if args.danger is not None else args.depth
    sword = args.sword if args.sword is not None else (0 if args.room == "mixed" else -1)
    try:
        result = play_fight(loader, args.seed, args.answer, danger, args.room, sword,
                            args.max_seconds, args.batch)
    except FightError as e:
        print("FAIL", e, "; logs kept at", e.logs, file=sys.stderr)
        sys.exit(1)
    print(json.dumps(result, indent=2))
    if args.json:
        with open(args.json, "w") as f:
            json.dump(result, f, indent=2)
            f.write("\n")
    if result.get("outcome") not in ("cleared", "fallen"):
        print(f"FAIL the fight did not end within {args.max_seconds} s", file=sys.stderr)
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
