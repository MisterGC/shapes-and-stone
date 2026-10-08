#!/usr/bin/env python3
"""Reload bench - the charged heavy swing is tried in the dojo's fight
scenario and its table values take effect after a reload (issue #79).

Starts tests/fightbench/Sandbox.qml in Clayground's live loader, enters the
fight room and holds the left button until the charge is full, then lets
go at the guardian (Sandbox.tryCharge): the charge must be full after
knight.chargeTime and the guardian must stagger. Then it changes
knight.chargeTime in the loaded copy of src/Balance.qml, reloads the
sandbox through the inspector, as the dojo reloads on a save, and tries
again: the charge must now be full after the new time. Prints one PASS or
FAIL line per check and exits with the number of failures.

Usage:
  run_reload.py [--loader <clayliveloader>]

The loader is found as run_fightbench.py finds it.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

from run_fightbench import REPO, Inspect, find_loader

STEP = 1 / 60
NEW_CHARGE_TIME = 0.45


def wait(predicate, timeout=30.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.1)
    return False


def try_charge(bench):
    bench.eval1("applyScenario('fight', 0)")
    if not wait(lambda: bench.eval1("fightReady()") is True):
        return None
    return json.loads(bench.eval1("tryCharge()") or "{}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--loader", help="path to clayliveloader")
    args = ap.parse_args()

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(1)

    tmp = tempfile.mkdtemp(prefix="sas_reload_")
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "fightbench")
    shutil.copytree(os.path.dirname(os.path.abspath(__file__)), sandbox_dir, ignore=skip)

    env = dict(os.environ)
    env.setdefault("QT_QPA_PLATFORM", "offscreen")
    log = open(os.path.join(tmp, "loader.log"), "w")
    proc = subprocess.Popen(
        [loader, "--sbx", os.path.join(sandbox_dir, "Sandbox.qml"), "--instance", "reload"],
        cwd=os.path.dirname(loader), env=env, stdout=log, stderr=subprocess.STDOUT)

    failures = 0

    def check(ok, what):
        nonlocal failures
        print("[Reload]", "PASS" if ok else "FAIL", what)
        if not ok:
            failures += 1

    try:
        bench = Inspect(sandbox_dir, "reload")
        if not bench.wait_phase("ready"):
            print("FAIL the sandbox did not load; logs in", tmp, file=sys.stderr)
            failures += 1
            return finish(proc, tmp, failures)

        first = try_charge(bench)
        steps = round(first["chargeTime"] / STEP) if first else -1
        check(first is not None and first["fullSteps"] == steps and first["staggered"],
              f"in the fight room the charge is full after {first and first['fullSteps']} steps "
              f"(chargeTime {first and first['chargeTime']} s, {steps} steps) and the guardian "
              f"staggers ({first and first['staggered']}, lost {first and first['lost']} HP)")

        balance = os.path.join(tmp, "src", "Balance.qml")
        with open(balance) as f:
            text = f.read()
        text, n = re.subn(r"chargeTime: [0-9.]+,", f"chargeTime: {NEW_CHARGE_TIME},", text)
        with open(balance, "w") as f:
            f.write(text)
        reloads = bench.state().get("reloadCount", 0)
        bench.request({"action": "reload"})
        reloaded = wait(lambda: bench.state().get("reloadCount", 0) > reloads
                        and bench.state().get("phase") == "ready")
        check(n == 1 and reloaded, f"knight.chargeTime set to {NEW_CHARGE_TIME} and the sandbox reloaded")

        second = try_charge(bench) if reloaded else None
        steps = round(NEW_CHARGE_TIME / STEP)
        check(second is not None and second["fullSteps"] == steps and second["staggered"],
              f"after the reload the charge is full after {second and second['fullSteps']} steps "
              f"({steps} expected) and the guardian staggers ({second and second['staggered']})")
    except TimeoutError as e:
        print("FAIL", e, "; logs in", tmp, file=sys.stderr)
        failures += 1
    return finish(proc, tmp, failures)


def finish(proc, tmp, failures):
    proc.terminate()
    try:
        proc.wait(5)
    except subprocess.TimeoutExpired:
        proc.kill()
    if failures == 0:
        shutil.rmtree(tmp, ignore_errors=True)
    else:
        print("Logs kept at:", tmp, file=sys.stderr)
    sys.exit(failures)


if __name__ == "__main__":
    main()
