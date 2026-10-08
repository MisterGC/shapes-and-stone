#!/usr/bin/env python3
"""Reload bench - the charged heavy swing and the crushing blow are tried
in the dojo's fight scenario and their table values take effect after a
reload (issues #79 and #80).

Starts tests/fightbench/Sandbox.qml in Clayground's live loader, enters the
fight room and holds the left button until the charge is full, then lets
go at the guardian (Sandbox.tryCharge): the charge must be full after
knight.chargeTime and the guardian must stagger. Then it changes
knight.chargeTime in the loaded copy of src/Balance.qml, reloads the
sandbox through the inspector, as the dojo reloads on a save, and tries
again: the charge must now be full after the new time. Then the fight
room's tough guardian goes for the knight (Sandbox.tryCrush): at the
table's enemy.crushChance it must wind up a crushing blow among its
attacks; with enemy.crushChance set to 1 in the loaded copy and the
sandbox reloaded, every one of its attacks must be a crushing one. Prints
one PASS or FAIL line per check and exits with the number of failures.

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
CRUSH_ATTACKS = 12
CRUSH_MAX_STEPS = 60 * 60


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


def try_crush(bench):
    bench.eval1("applyScenario('fight', 0)")
    if not wait(lambda: bench.eval1("fightReady()") is True):
        return None
    return json.loads(bench.eval1(f"tryCrush({CRUSH_ATTACKS}, {CRUSH_MAX_STEPS})") or "{}")


def reload(bench, balance, pattern, repl):
    """Edits the loaded copy of the table and reloads the sandbox"""
    with open(balance) as f:
        text = f.read()
    text, n = re.subn(pattern, repl, text)
    with open(balance, "w") as f:
        f.write(text)
    reloads = bench.state().get("reloadCount", 0)
    bench.request({"action": "reload"})
    reloaded = wait(lambda: bench.state().get("reloadCount", 0) > reloads
                    and bench.state().get("phase") == "ready")
    return n == 1 and reloaded


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

        crush = try_crush(bench)
        check(crush is not None and crush["tier"] == 2 and crush["attacks"] == CRUSH_ATTACKS
              and 0 < crush["crushes"] < crush["attacks"],
              f"in the fight room the tough guardian winds up {crush and crush['crushes']} crushing "
              f"blows in {crush and crush['attacks']} attacks (crushChance "
              f"{crush and crush['guardianChance']})")

        balance = os.path.join(tmp, "src", "Balance.qml")
        reloaded = reload(bench, balance, r"chargeTime: [0-9.]+,", f"chargeTime: {NEW_CHARGE_TIME},")
        check(reloaded, f"knight.chargeTime set to {NEW_CHARGE_TIME} and the sandbox reloaded")

        second = try_charge(bench) if reloaded else None
        steps = round(NEW_CHARGE_TIME / STEP)
        check(second is not None and second["fullSteps"] == steps and second["staggered"],
              f"after the reload the charge is full after {second and second['fullSteps']} steps "
              f"({steps} expected) and the guardian staggers ({second and second['staggered']})")

        reloaded = reload(bench, balance, r"crushChance: [0-9.]+,", "crushChance: 1,")
        check(reloaded, "enemy.crushChance set to 1 and the sandbox reloaded")
        crush = try_crush(bench) if reloaded else None
        check(crush is not None and crush["attacks"] == CRUSH_ATTACKS
              and crush["crushes"] == crush["attacks"] and crush["crushChance"] == 1,
              f"after the reload every attack of the tough guardian is a crushing one "
              f"({crush and crush['crushes']} of {crush and crush['attacks']})")
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
