#!/usr/bin/env python3
"""Fight bench - plays the "fight" scenario with a scripted knight and
prints how the fight went as JSON (issue #34).

Starts tests/fightbench/Sandbox.qml in Clayground's live loader, pauses the
game and enters the fight room, then steps the world through the inspector
protocol, a few physics steps at a time, until the room is cleared or the
knight has fallen. The scripted knight lives in the sandbox and acts on
every step, so the same seed gives the same numbers on every run.

Usage:
  run_fightbench.py [--loader <clayliveloader>] [--seed 424242]
                    [--max-seconds 180] [--json out.json]

The loader is --loader, else $CLAYLIVELOADER, else build/bin/clayliveloader
of this repository (configure with -DCLAYGROUND_WITH_TOOLS=ON), else the
first clayliveloader on PATH. It should be built from the Clayground
commit the game's clayground/ submodule pins.
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--loader", help="path to clayliveloader")
    ap.add_argument("--seed", type=int, default=424242,
                    help="seed of the scripted knight's choices")
    ap.add_argument("--max-seconds", type=float, default=180.0,
                    help="simulated seconds before the fight counts as not finished")
    ap.add_argument("--batch", type=int, default=6,
                    help="physics steps per inspector request")
    ap.add_argument("--json", help="also write the metrics to this file")
    args = ap.parse_args()

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(1)

    # The sandbox imports ../../src: copy both, keeping their places
    tmp = tempfile.mkdtemp(prefix="sas_fightbench_")
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "fightbench")
    shutil.copytree(os.path.dirname(os.path.abspath(__file__)), sandbox_dir, ignore=skip)

    env = dict(os.environ)
    env.setdefault("QT_QPA_PLATFORM", "offscreen")
    log = open(os.path.join(tmp, "loader.log"), "w")
    proc = subprocess.Popen(
        [loader, "--sbx", os.path.join(sandbox_dir, "Sandbox.qml"), "--instance", "fight"],
        cwd=os.path.dirname(loader), env=env, stdout=log, stderr=subprocess.STDOUT)

    ok = False
    try:
        bench = Inspect(sandbox_dir, "fight")
        if not bench.wait_phase("ready"):
            print("FAIL the sandbox did not load; logs in", tmp, file=sys.stderr)
            return finish(proc, tmp, False)
        if bench.eval1(f"begin({args.seed})") is not True:
            print("FAIL the fight room did not start; logs in", tmp, file=sys.stderr)
            return finish(proc, tmp, False)
        # Let what the scene sets up on its first frames settle before step 1
        time.sleep(1.0)

        # Clayground's MoveTo (enemy path following) re-aims on a 100 ms
        # wall-clock Timer, not on the physics steps. A batch runs its steps
        # in one go; the pause after it gives that Timer the time to fire
        # once more, so the enemies re-aim after every batch, as often as a
        # running game at 60 steps per second does. Workaround until MoveTo
        # counts steps.
        max_steps = int(args.max_seconds * 60)
        steps = 0
        while True:
            resp = bench.request({"action": "batch", "steps": [
                {"action": "time", "step": args.batch},
                {"action": "eval", "eval": ["done", "steps"]}]})
            if resp.get("error"):
                print("FAIL", resp["error"], "; logs in", tmp, file=sys.stderr)
                return finish(proc, tmp, False)
            state = resp["steps"][1].get("eval", {})
            steps = state.get("steps", 0)
            if state.get("done") is True or steps >= max_steps:
                break
            time.sleep(0.15)

        result = json.loads(bench.eval1("JSON.stringify(report())") or "{}")
        result["clayground"] = clayground_commit()
        print(json.dumps(result, indent=2))
        if args.json:
            with open(args.json, "w") as f:
                json.dump(result, f, indent=2)
                f.write("\n")
        ok = result.get("outcome") in ("cleared", "fallen")
        if not ok:
            print(f"FAIL the fight did not end within {args.max_seconds} s",
                  file=sys.stderr)
    except TimeoutError as e:
        print("FAIL", e, "; logs in", tmp, file=sys.stderr)
    return finish(proc, tmp, ok)


def finish(proc, tmp, ok):
    proc.terminate()
    try:
        proc.wait(5)
    except subprocess.TimeoutExpired:
        proc.kill()
    if ok:
        shutil.rmtree(tmp, ignore_errors=True)
        sys.exit(0)
    print("Logs kept at:", tmp, file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
