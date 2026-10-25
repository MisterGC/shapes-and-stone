#!/usr/bin/env python3
"""Pad knight bench - the knight plays with a gamepad (issue #200).

Starts tests/padknight/Sandbox.qml in Clayground's live loader, enters the
dojo's "dungeon" scenario at depth 0 and pauses it, then plays the knight
with the dojo's synthetic pad alone - the inspector's gamepad input, no
key and no click: the left stick walks it right and up, the right stick
aims it left, up and down-right, R1 swings and, held, charges a heavy
swing, L1 raises the shield, B dashes, X drinks a potion and Select opens
the knight panel. The controls hint names the pad's buttons from its first
input on. Then a right click aims with the mouse again, and a key press
gives the hint back to the keyboard and walks the knight. L2 locks on a
grunt and off again, R2 whirls and Y drinks a draught.

A virtual SDL pad stands in for a physical one: a button on it makes it
the controller's source and the hint the pad's again, its right stick
aims, a key press takes the keyboard back, and unplugging it leaves the
keyboard. Skipped where the build reads no physical pads.

In the village scenario A talks to a seller, the stick picks a ware, X
buys it and B closes the dialogue.

Prints one PASS or FAIL line per check and exits with the number of
failures.

Usage:
  run_padknight.py [--loader <clayliveloader>]

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
                    if resp.get("error"):
                        raise RuntimeError(f"{payload.get('action')}: {resp['error']}")
                    return resp
            except (OSError, json.JSONDecodeError):
                pass
            time.sleep(0.01)
        raise TimeoutError(f"no response for {payload.get('action')} ({rid})")

    def eval1(self, expr):
        return self.request({"action": "eval", "eval": [expr]}).get("eval", {}).get(expr)


def find_loader(arg):
    for cand in (arg, os.environ.get("CLAYLIVELOADER"),
                 os.path.join(REPO, "build", "bin", "clayliveloader"),
                 shutil.which("clayliveloader")):
        if cand and os.path.isfile(cand) and os.access(cand, os.X_OK):
            return os.path.abspath(cand)
    return None


class Bench:
    def __init__(self, inspect):
        self.i = inspect
        self.failures = 0

    def check(self, ok, what):
        print("[PadKnight]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            self.failures += 1

    def knight(self):
        return json.loads(self.i.eval1("state()"))

    # The synthetic pad holds this state until the next one; inputs not
    # named are neutral
    def pad(self, **state):
        self.i.request({"action": "input", "gamepad": state})

    def step(self, n):
        self.i.request({"action": "time", "step": n})

    def key(self, name, press=True, release=True):
        self.i.request({"action": "input", "key": {"key": name, "press": press, "release": release}})


def angle_near(a, b, tol=3.0):
    d = (a - b + 180) % 360 - 180
    return abs(d) <= tol


def play(b):
    i = b.i
    k = b.knight()
    b.check(not k["padInUse"] and "WASD" in k["hint"],
            "before any pad input the hint is the keyboard's: " + k["hint"][:40])

    # The left stick walks the knight
    x0, y0 = k["x"], k["y"]
    b.pad(axisX=1)
    b.step(20)
    k = b.knight()
    # A pad's button and what it does are joined by a no-break space
    k["hint"] = k["hint"].replace("\u00a0", " ")
    b.check(k["x"] - x0 > 0.5, f"the left stick right walks the knight right ({k['x'] - x0:+.2f} wu)")
    b.check(k["padInUse"], "the pad is in use from its first input")
    b.check("L stick move" in k["hint"] and "R1 strike" in k["hint"] and "L1 shield" in k["hint"]
            and "B dash" in k["hint"] and "WASD" not in k["hint"],
            "the controls hint names the pad's buttons: " + k["hint"])
    b.check(angle_near(k["facing"], 0, 1), f"walking right without the right stick it faces right ({k['facing']:.0f})")
    y1 = k["y"]
    b.pad(axisY=1)
    b.step(20)
    k = b.knight()
    b.check(k["y"] - y1 > 0.5, f"the left stick up walks the knight up ({k['y'] - y1:+.2f} wu)")
    b.pad()
    b.step(10)

    # The right stick aims
    for state, want, what in (({"axisRightX": -1}, 180, "left"), ({"axisRightY": 1}, 90, "up"),
                              ({"axisRightX": 0.7, "axisRightY": -0.7}, -45, "down-right")):
        b.pad(**state)
        b.step(2)
        k = b.knight()
        b.check(k["padAim"] and angle_near(k["facing"], want),
                f"the right stick {what} aims the knight at {want} degrees ({k['facing']:.0f})")
    b.pad()
    b.step(2)
    k = b.knight()
    b.check(angle_near(k["facing"], -45), f"let go, the aim stays where it was ({k['facing']:.0f})")

    # R1 swings; held, it charges a heavy swing
    b.pad(buttonR1=True)
    b.step(2)
    b.pad()
    swung = False
    for _ in range(6):
        b.step(1)
        swung = swung or b.knight()["attacking"]
    b.check(swung, "a tap of R1 swings the sword")
    b.step(90)
    b.pad(buttonR1=True)
    b.step(int(k["chargeTime"] * 60) + 6)
    k = b.knight()
    b.check(k["chargeFull"], "R1 held for the charge time charges a full heavy swing")
    b.pad()
    swung = False
    for _ in range(6):
        b.step(1)
        swung = swung or b.knight()["attacking"]
    b.check(swung, "let go, the heavy swing comes out")
    b.step(120)

    # L1 raises the shield while held
    b.pad(buttonL1=True)
    b.step(12)
    k = b.knight()
    b.check(k["blocking"], "L1 held raises the shield")
    b.pad()
    b.step(12)
    k = b.knight()
    b.check(not k["blocking"], "let go of L1, the shield goes down")

    # B dashes
    x0 = k["x"]
    b.pad(axisX=-1, buttonB=True)
    dashed = False
    for _ in range(4):
        b.step(1)
        dashed = dashed or b.knight()["dashing"]
    b.pad()
    b.step(30)
    k = b.knight()
    b.check(dashed, f"B dashes ({k['x'] - x0:+.2f} wu)")

    # X drinks a potion, Select opens the knight panel and closes it
    i.eval1("hurtWithPotion()")
    hp0 = b.knight()["hp"]
    b.pad(buttonX=True)
    b.step(2)
    b.pad()
    b.step(2)
    k = b.knight()
    b.check(k["potions"] == 0 and k["hp"] > hp0, f"X drinks a potion (hp {hp0} -> {k['hp']})")
    b.pad(buttonSelect=True)
    b.step(1)
    b.pad()
    b.step(1)
    b.check(b.knight()["panel"], "Select opens the knight panel")
    b.pad(buttonSelect=True)
    b.step(1)
    b.pad()
    b.step(1)
    b.check(not b.knight()["panel"], "Select again closes it")

    # The mouse aims again as soon as it is used
    k = b.knight()
    i.request({"action": "input", "click": {"x": round(k["screenX"] - 150), "y": round(k["screenY"]),
                                            "button": "right"}})
    b.step(2)
    k = b.knight()
    b.check(not k["padAim"] and angle_near(k["facing"], 180, 10),
            f"a click left of the knight aims it with the mouse again ({k['facing']:.0f})")

    # A key press is the keyboard's again
    x0 = k["x"]
    b.key("D", release=False)
    b.step(20)
    k = b.knight()
    b.key("D", press=False)
    b.step(2)
    b.check(not k["padInUse"] and "WASD" in k["hint"], "a key press gives the hint back to the keyboard")
    b.check(k["keyboard"] and k["x"] - x0 > 0.5, f"and D walks the knight ({k['x'] - x0:+.2f} wu)")

    # L2 locks on and off, R2 whirls, Y drinks a draught
    i.eval1("gruntNear()")
    b.step(2)
    b.pad(triggerL2=1)
    b.step(1)
    b.pad()
    b.step(1)
    b.check(b.knight()["lockedOn"], "L2 locks on the grunt beside the knight")
    i.eval1("readyToWhirl()")
    b.pad(triggerR2=1)
    b.step(1)
    b.pad()
    b.step(1)
    k = b.knight()
    b.check(k["momentum"] == 0 and k["dashing"], "R2 with full momentum whirls")
    b.step(60)
    b.pad(triggerL2=1)
    b.step(1)
    b.pad()
    b.step(1)
    b.check(not b.knight()["lockedOn"], "L2 again lets go")
    i.eval1("lowWithDraught()")
    b.pad(buttonY=True)
    b.step(1)
    b.pad()
    b.step(1)
    k = b.knight()
    b.check(k["draughts"] == 0 and k["mana"] > 1, f"Y drinks a draught (mana {k['mana']:.0f})")


def village(b):
    i = b.i
    if i.eval1("toVillage()") is not True:
        b.check(False, "the village scenario starts")
        return
    time.sleep(1.0)
    b.step(5)
    name = i.eval1("besideSeller()")
    b.step(10)
    b.pad(buttonA=True)
    b.step(1)
    b.pad()
    b.step(1)
    k = b.knight()
    b.check(k["talking"] and k["wares"] > 1, f"A beside {name} talks to them, {k['wares']} wares offered")
    b.check("[A] continue" in k["dialogueHint"] or "[A] close" in k["dialogueHint"],
            "the dialogue names A to go on: " + k["dialogueHint"][-40:])
    b.pad(axisY=-1)
    b.step(1)
    b.pad()
    b.step(1)
    k = b.knight()
    b.check(k["ware"] == 1, f"the stick down picks the second ware ({k['ware']})")
    gold = k["gold"]
    b.pad(buttonX=True)
    b.step(1)
    b.pad()
    b.step(1)
    k = b.knight()
    b.check(k["gold"] != gold, f"X buys it (gold {gold} -> {k['gold']})")
    b.pad(buttonB=True)
    b.step(1)
    b.pad()
    b.step(1)
    k = b.knight()
    b.check(not k["talking"] and not k["dashing"], "B closes the dialogue and dashes nowhere")


def physical(b):
    i = b.i
    backend = i.eval1("backend()")
    if backend != "sdl":
        print(f"[PadKnight] SKIP physical pad: this build reads none ({backend})", flush=True)
        return
    pid = i.eval1("plugPad('Bench Pad')")
    b.check(isinstance(pid, int) and pid > 0, f"a virtual pad plugs in ({pid})")
    k = b.knight()
    b.check(k["keyboard"] and not k["gamepad"], "plugged in, the keyboard stays the source until the pad is used")
    i.eval1(f"padInput({pid}, 'rightShoulder', true)")
    b.step(2)
    k = b.knight()
    b.check(k["gamepad"] and k["gamepadName"] == "Bench Pad" and k["padInUse"],
            f"a button on it makes it the source ({k['gamepadName']}) and the hint the pad's")
    i.eval1(f"padInput({pid}, 'rightShoulder', false)")
    i.eval1(f"padInput({pid}, 'rightX', 1)")
    b.step(2)
    k = b.knight()
    b.check(k["padAim"] and angle_near(k["facing"], 0), f"its right stick aims ({k['facing']:.0f})")
    i.eval1(f"padInput({pid}, 'rightX', 0)")
    b.key("W")
    b.step(2)
    k = b.knight()
    b.check(k["keyboard"] and not k["gamepad"] and not k["padInUse"], "a key press takes the keyboard back")
    i.eval1(f"padInput({pid}, 'south', true)")
    i.eval1(f"padInput({pid}, 'south', false)")
    b.step(2)
    b.check(b.knight()["gamepad"], "the pad's A makes it the source again")
    i.eval1(f"unplugPad({pid})")
    b.step(2)
    k = b.knight()
    b.check(k["keyboard"] and not k["gamepad"] and not k["padInUse"], "unplugged, the keyboard is the source")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--loader", help="path to clayliveloader")
    args = ap.parse_args()

    loader = find_loader(args.loader)
    if not loader:
        print("FAIL no clayliveloader: pass --loader, set CLAYLIVELOADER or "
              "configure the build with -DCLAYGROUND_WITH_TOOLS=ON", file=sys.stderr)
        sys.exit(1)

    # The sandbox imports ../../src: copy both, keeping their places
    tmp = tempfile.mkdtemp(prefix="sas_padknight_")
    skip = shutil.ignore_patterns(".clay", "__pycache__", "*.py")
    shutil.copytree(os.path.join(REPO, "src"), os.path.join(tmp, "src"), ignore=skip)
    sandbox_dir = os.path.join(tmp, "tests", "padknight")
    shutil.copytree(os.path.dirname(os.path.abspath(__file__)), sandbox_dir, ignore=skip)

    env = dict(os.environ)
    env.setdefault("QT_QPA_PLATFORM", "offscreen")
    log = open(os.path.join(tmp, "loader.log"), "w")
    proc = subprocess.Popen(
        [loader, "--sbx", os.path.join(sandbox_dir, "Sandbox.qml"), "--instance", "pad"],
        cwd=os.path.dirname(loader), env=env, stdout=log, stderr=subprocess.STDOUT)

    bench = Bench(Inspect(sandbox_dir, "pad"))
    failures = 1
    try:
        if not bench.i.wait_phase("ready"):
            print("FAIL the sandbox did not load; logs in", tmp, file=sys.stderr)
        elif bench.i.eval1("begin()") is not True:
            print("FAIL the dungeon did not start; logs in", tmp, file=sys.stderr)
        else:
            # Let what the scene sets up on its first frames settle
            time.sleep(1.0)
            bench.i.request({"action": "time", "paused": True})
            play(bench)
            physical(bench)
            village(bench)
            failures = bench.failures
            print(f"[PadKnight] {failures} failed; logs in {tmp}", flush=True)
    except (TimeoutError, RuntimeError) as e:
        print("FAIL", e, "; logs in", tmp, file=sys.stderr)
    proc.terminate()
    try:
        proc.wait(5)
    except subprocess.TimeoutExpired:
        proc.kill()
    sys.exit(failures)


if __name__ == "__main__":
    main()
