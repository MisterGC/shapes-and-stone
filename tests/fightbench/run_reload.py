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
sandbox reloaded, every one of its attacks must be a crushing one. Then
the duel room's lead (issue #271) shows its stance bar, and opened as a
parry opens it (Sandbox.tryOpening) it staggers for lead.openingTime and
a swing in the opening does lead.openingDamage times its damage; with
lead.openingTime changed in the loaded copy and the sandbox reloaded, the
opening lasts the new time. The guardianduel scenario (issue #288) stands
a guardian lead with the table's HP, its type's leadHp share of the tough
tier's; with guardian.leadHp changed in the loaded copy and the sandbox
reloaded, the lead has the new HP. Then in the flow scenario the knight strikes
two enemies down CHAIN_GAP seconds apart (Sandbox.tryChain): within
Balance.chain.window they chain, the second death sound a step higher;
with chain.window set below the gap in the loaded copy and the sandbox
reloaded, they no longer do. Then the bossroom scenario (issue #274) puts
the knight at the Hollow Warden's door: the room's way in and the Warden
are on screen, the Warden asleep, its HP and tempo the table's; with
boss.hp changed in the loaded copy and the sandbox reloaded, the Warden
has the new HP. Woken there to wind up and strike once (Sandbox.tryToll),
it plays its own toll, sfx/warden_toll, at boss.toll's pitches and no
scream (issue #287); with boss.toll.windUp changed in the loaded copy and
the sandbox reloaded, its wind-up tolls at the new pitch. Prints one PASS or FAIL line per check and exits with the
number of failures.

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
NEW_OPENING_TIME = 2.5
NEW_GUARDIAN_LEAD_HP = 0.5
CHAIN_GAP = 2.0
NEW_CHAIN_WINDOW = 1.5
BOSS_DEPTH = 2
NEW_BOSS_HP = 4000
NEW_TOLL_WIND_UP = 3


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


def try_opening(bench):
    bench.eval1("applyScenario('duel', 0)")
    if not wait(lambda: bench.eval1("duelReady()") is True):
        return None
    return json.loads(bench.eval1("tryOpening()") or "{}")


def try_duel_lead(bench):
    bench.eval1("applyScenario('guardianduel', 0)")
    if not wait(lambda: bench.eval1("duelReady()") is True):
        return None
    return json.loads(bench.eval1("tryDuelLead()") or "{}")


def try_chain(bench):
    bench.eval1("applyScenario('flow', 0)")
    if not wait(lambda: bench.eval1("fightReady()") is True):
        return None
    return json.loads(bench.eval1(f"tryChain({round(CHAIN_GAP / STEP)})") or "{}")


def try_boss_room(bench):
    bench.eval1(f"applyScenario('bossroom', {BOSS_DEPTH})")
    if not wait(lambda: bench.eval1("bossRoomReady()") is True):
        return None
    return json.loads(bench.eval1("tryBossRoom()") or "{}")


def try_toll(bench):
    bench.eval1(f"applyScenario('bossroom', {BOSS_DEPTH})")
    if not wait(lambda: bench.eval1("bossRoomReady()") is True):
        return None
    return json.loads(bench.eval1("tryToll()") or "{}")


def tolled(toll, wind_up):
    """Whether the Warden's tryToll rows are its toll at wind_up for the
    wind-up and the table's strike pitch, and no scream"""
    rows = [(r["cue"], r["what"], r["pitch"]) for r in toll["rows"]]
    return (rows.count(("sfx/warden_toll", "windUp", wind_up)) == 1
            and rows.count(("sfx/warden_toll", "strike", toll["strike"])) == 1
            and not any(r[0] == "sfx/goblin_scream" for r in rows))


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

        opening = try_opening(bench)
        check(opening is not None and opening["bar"] and opening["opened"]
              and abs(opening["seconds"] - opening["openingTime"]) < 1e-6
              and opening["lost"] == opening["want"],
              f"in the duel room the lead shows its stance bar ({opening and opening['bar']}), "
              f"a parry opens it for {opening and opening['seconds']} s (openingTime "
              f"{opening and opening['openingTime']}) and a swing in the opening takes "
              f"{opening and opening['lost']} HP ({opening and opening['want']} by the table)")
        reloaded = reload(bench, balance, r"openingTime: [0-9.]+,", f"openingTime: {NEW_OPENING_TIME},")
        check(reloaded, f"lead.openingTime set to {NEW_OPENING_TIME} and the sandbox reloaded")
        opening = try_opening(bench) if reloaded else None
        check(opening is not None and opening["opened"]
              and abs(opening["seconds"] - NEW_OPENING_TIME) < 1e-6,
              f"after the reload the lead's opening lasts {opening and opening['seconds']} s "
              f"({NEW_OPENING_TIME} expected)")
        lead = try_duel_lead(bench)
        check(lead is not None and lead["type"] == "guardian" and lead["hp"] == lead["want"],
              f"the guardianduel scenario stands a {lead and lead['type']} lead of "
              f"{lead and lead['hp']} HP ({lead and lead['want']} by the table, leadHp "
              f"{lead and lead['leadHp']})")
        reloaded = reload(bench, balance, r"(guardian: \{ hpBonus: -?[0-9]+, leadHp: )[0-9.]+,",
                          rf"\g<1>{NEW_GUARDIAN_LEAD_HP},")
        check(reloaded, f"guardian.leadHp set to {NEW_GUARDIAN_LEAD_HP} and the sandbox reloaded")
        after = try_duel_lead(bench) if reloaded else None
        check(after is not None and after["leadHp"] == NEW_GUARDIAN_LEAD_HP
              and after["hp"] == after["want"] and lead is not None and after["hp"] < lead["hp"],
              f"after the reload the guardian lead has {after and after['hp']} HP "
              f"({after and after['want']} by the table at leadHp {after and after['leadHp']})")
        chain = try_chain(bench)
        check(chain is not None and chain["window"] > CHAIN_GAP and chain["links"] == 2
              and len(chain["pitches"]) == 2 and chain["pitches"][1] > chain["pitches"][0] == 0,
              f"in the flow room two kills {CHAIN_GAP} s apart chain (chain.window "
              f"{chain and chain['window']} s, links {chain and chain['links']}, death sound at "
              f"{chain and chain['pitches']})")
        reloaded = reload(bench, balance, r"(chain: \(\{\s*window: )[0-9.]+,",
                          rf"\g<1>{NEW_CHAIN_WINDOW},")
        check(reloaded, f"chain.window set to {NEW_CHAIN_WINDOW} and the sandbox reloaded")
        chain = try_chain(bench) if reloaded else None
        check(chain is not None and chain["window"] == NEW_CHAIN_WINDOW and chain["links"] == 1
              and chain["pitches"] == [0, 0],
              f"after the reload the same two kills do not chain (chain.window "
              f"{chain and chain['window']} s, links {chain and chain['links']}, death sound at "
              f"{chain and chain['pitches']})")
        boss = try_boss_room(bench)
        check(boss is not None and boss["stage"] == "waiting" and boss["dormant"]
              and boss["gateOnScreen"] and boss["wardenOnScreen"]
              and boss["hp"] == boss["wantHp"] and abs(boss["tempo"] - boss["wantTempo"]) < 1e-9,
              f"the bossroom scenario lands at the Warden's door at depth {boss and boss['depth']}: its "
              f"way in on screen ({boss and boss['gateOnScreen']}), the Warden on screen "
              f"({boss and boss['wardenOnScreen']}) and asleep, {boss and boss['hp']} HP "
              f"({boss and boss['wantHp']} by the table, boss.hp {boss and boss['tableHp']}), tempo "
              f"{boss and boss['tempo']} ({boss and boss['wantTempo']} by the table)")
        reloaded = reload(bench, balance, r"(boss: \(\{\s*every: [0-9]+,\s*name: \"[^\"]*\",\s*hp: )[0-9]+,",
                          rf"\g<1>{NEW_BOSS_HP},")
        check(reloaded, f"boss.hp set to {NEW_BOSS_HP} and the sandbox reloaded")
        boss = try_boss_room(bench) if reloaded else None
        check(boss is not None and boss["tableHp"] == NEW_BOSS_HP and boss["hp"] == boss["wantHp"]
              and boss["gateOnScreen"],
              f"after the reload the Warden has {boss and boss['hp']} HP ({boss and boss['wantHp']} by "
              f"the table at boss.hp {boss and boss['tableHp']}), its way in on screen")

        # The Warden's own toll (issue #287), at the table's pitches
        toll = try_toll(bench) if boss else None
        check(toll is not None and tolled(toll, toll["windUp"]),
              f"the Warden's wind-up and strike toll at boss.toll's +{toll and toll['windUp']} and "
              f"+{toll and toll['strike']}, no scream ({toll and toll['rows']})")
        reloaded = reload(bench, balance, r"toll: \{ windUp: -?[0-9]+,", f"toll: {{ windUp: {NEW_TOLL_WIND_UP},")
        check(reloaded, f"boss.toll.windUp set to {NEW_TOLL_WIND_UP} and the sandbox reloaded")
        toll = try_toll(bench) if reloaded else None
        check(toll is not None and toll["windUp"] == NEW_TOLL_WIND_UP and tolled(toll, NEW_TOLL_WIND_UP),
              f"after the reload the Warden's wind-up tolls at +{NEW_TOLL_WIND_UP} ({toll and toll['rows']})")
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
