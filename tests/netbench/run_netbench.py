#!/usr/bin/env python3
"""Net bench - measures the game's player-sync path between two instances.

Launches a host and a joiner of tests/netbench/Sandbox.qml through the
Clayground live loader, connects them (Local or Cloud signaling), lets the
host move on a clock-driven path and reads the joiner's error statistics
back through the inspector protocol.

Usage:
  run_netbench.py --loader <clayliveloader> [--mode local|cloud]
                  [--interval 50] [--delay 120] [--seconds 10] [--json out]

Both instances must run on the same machine (the truth is derived from the
shared wall clock). For a real LAN or WAN check run the game itself.
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

    def wait_phase(self, phase, timeout=30.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.state().get("phase") == phase:
                return True
            time.sleep(0.1)
        return False

    def request(self, payload, timeout=10.0):
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
            time.sleep(0.03)
        raise TimeoutError(f"no response for {payload.get('action')} ({rid})")

    def eval(self, exprs, timeout=10.0):
        return self.request({"action": "eval", "eval": exprs}, timeout).get("eval", {})

    def eval1(self, expr):
        return self.eval([expr]).get(expr)


def wait_for(cond, timeout=15.0, interval=0.15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if cond():
                return True
        except Exception:
            pass
        time.sleep(interval)
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--loader", required=True, help="path to clayliveloader")
    ap.add_argument("--mode", choices=["local", "cloud"], default="local")
    ap.add_argument("--interval", type=int, default=0,
                    help="broadcast period ms; 0 = every frame (the game's setting)")
    ap.add_argument("--delay", type=int, default=50, help="interpolator delayMs")
    ap.add_argument("--auto", action="store_true",
                    help="use StateInterpolator.autoDelay (clayground #291) instead of --delay")
    ap.add_argument("--seconds", type=float, default=10.0, help="measurement window")
    ap.add_argument("--json", help="append the result as one JSON line to this file")
    args = ap.parse_args()

    loader = os.path.abspath(args.loader)
    loader_dir = os.path.dirname(loader)
    src = os.path.dirname(os.path.abspath(__file__))
    tmp = tempfile.mkdtemp(prefix="sas_netbench_")
    sandbox_dir = os.path.join(tmp, "bench")
    shutil.copytree(src, sandbox_dir,
                    ignore=shutil.ignore_patterns(".clay", "__pycache__", "*.py"))
    sbx = os.path.join(sandbox_dir, "Sandbox.qml")

    env = dict(os.environ)
    env.setdefault("QT_QPA_PLATFORM", "offscreen")

    procs = {}
    result = {"mode": args.mode, "intervalMs": args.interval,
              "delayMs": args.delay, "auto": args.auto}
    ok = False
    try:
        for n in ("host", "joiner"):
            logf = open(os.path.join(tmp, f"{n}.log"), "w")
            procs[n] = subprocess.Popen(
                [loader, "--sbx", sbx, "--instance", n],
                cwd=loader_dir, env=env, stdout=logf, stderr=subprocess.STDOUT)
        H, J = Inspect(sandbox_dir, "host"), Inspect(sandbox_dir, "joiner")

        if not (H.wait_phase("ready") and J.wait_phase("ready")):
            print("FAIL instances did not reach ready; logs in", tmp)
            return finish(procs, tmp, False)

        local = "true" if args.mode == "local" else "false"
        for i in (H, J):
            auto = "true" if args.auto else "false"
            i.eval([f"configure({local}, {args.interval}, {args.delay}, {auto})"])

        H.eval(["hostUp()"])
        if not wait_for(lambda: H.eval1("netId") not in (None, ""), 30):
            print("FAIL host got no network code; logs in", tmp)
            return finish(procs, tmp, False)
        code = H.eval1("netId")
        J.eval([f"joinNet('{code}')"])
        if not wait_for(lambda: J.eval1("connected") is True, 40):
            print("FAIL joiner did not connect; logs in", tmp)
            return finish(procs, tmp, False)
        # wait for the lossy state channel (or accept the fallback after 5 s)
        wait_for(lambda: "unreliable" in (J.eval1("JSON.stringify(netRef.peerStats)") or ""), 5)

        host_id = J.eval1("nodeList[0]")
        J.eval([f"trackSender('{host_id}')"])
        H.eval(["startPath()"])
        time.sleep(1.0)                       # let the buffer fill
        J.eval(["trackSender(trackedSender)"])  # restart statistics
        time.sleep(args.seconds)
        rep = json.loads(J.eval1("JSON.stringify(report())") or "{}")
        result.update(rep)
        result["code"] = code
        result["phaseTimingJoiner"] = json.loads(
            J.eval1("JSON.stringify(netRef.phaseTiming)") or "{}")
        ok = rep.get("n", 0) >= 10
    finally:
        print(json.dumps(result, indent=2))
        if args.json:
            with open(args.json, "a") as f:
                f.write(json.dumps(result) + "\n")
        return finish(procs, tmp, ok)


def finish(procs, tmp, ok):
    for p in procs.values():
        try:
            p.terminate()
        except Exception:
            pass
    time.sleep(1)
    for p in procs.values():
        try:
            p.kill()
        except Exception:
            pass
    if ok:
        shutil.rmtree(tmp, ignore_errors=True)
        sys.exit(0)
    print("Logs kept at:", tmp)
    sys.exit(1)


if __name__ == "__main__":
    main()
