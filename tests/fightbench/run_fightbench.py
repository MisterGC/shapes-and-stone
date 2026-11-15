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
                    [--answer mix|block|parry|perfect|heavy|whirlwind|stun|bolt|charge|masher|skilled|person]
                    [--room mixed|flow|duel|guardianduel|spitterduel|ballduel|boss] [--sword N] [--boots N]
                    [--depth 0 | --danger 0.0] [--max-seconds 180] [--json out.json]
  run_fightbench.py --pacing [--check] [--rooms flow duel guardianduel spitterduel ballduel boss]
                    [--depths 0 2 4] [--answers charge masher skilled person] [--boots N] [--jobs N]
                    [--json out.json]

One fight prints its report as JSON. --answer is how the scripted knight
meets a grunt's or a guardian's attack: "mix" parries or blocks as the
seed rolls, "block" always blocks, "parry" always parries, "perfect"
raises the shield 4 physics steps before each lunge lands, a perfect
block, and just before each shot meets the knight, which sends it back
(Balance.projectile), "heavy" meets attacks as "mix" does but charges a
heavy swing at a guardian instead of shield-dashing it, "whirlwind"
fights as "mix" does
and, once its momentum is full, whirls (Q) at the nearest enemy within
reach. The report counts the whirlwinds that landed (hit an enemy), their
hits and the ones begun. "stun" fights as "mix" does with the stun for its
special (issue #318): it stuns when a weak or normal enemy not frozen
stands in the stun's reach, and when a lead winds up in it 3 s or more
after its last stun; the report has each enemy's stuns and frozen spans.
"bolt" plays as "masher" does with the bolt for its special and the
knight's own mana (issue #319): at an enemy out of the sword's reach and
within 0.9 of the bolt's reach it lets a bolt loose whenever the mana is
there; the report has each bolt's end.
The pacing pilots: "charge" holds a full charge
and lets go at the nearest enemy, "masher" clicks, "skilled" parries,
perfect-blocks - crushing blows and shots, which it sends back - and
strikes in openings, "person" plays as "skilled" with a person's reaction
time and misses (Balance.pacing.person, issue #315). --room is who stands in the fight room: "mixed" its usual lineup (Balance.spawn.fightRoom), "flow" fodder
only, "duel" a room's lead alone, a grunt, "guardianduel" a guardian lead
alone (issue #288), "spitterduel" a spitter lead alone (issue #315),
"ballduel" a slinger lead alone, the lead whose metal balls bounce off the
walls and the shields (issue #322), and "boss" the Hollow Warden alone, its
adds coming in its phase 2 (Balance.pacing, Balance.boss). --sword is the
knight's sword level: by default 0 in the mixed room and in flow and duel
the one a knight usually has at that depth. --boots is the level of the
knight's swift boots, the smith's upgrade that makes it walk faster
(Balance.shop.bootsSpeed, issue #325): 0 by default, in a single fight and
in every fight of --pacing; a report says it and the knight's walking
speed. --danger is the danger the
fight room is at, its depth plus a position in the depth's range (2.5:
half way through depth 2's): the lineup stays, the enemies hit as hard as
at that danger. --depth d is --danger d, the bottom of the depth's range.
The same seed and danger give the same numbers.

--pacing plays every room of --rooms at every depth of --depths with every
pilot of --answers (by default flow, duel, guardianduel, spitterduel,
ballduel and boss, Balance.pacing.depths, and
charge, masher, skilled and person), --jobs loaders at a time, prints a report of
each fight - per enemy its time to kill and hits to kill, the gaps between
kills, the kill chains and the longest one's links (Balance.chain), the
death sound's pitch kill by kill, the time engaged, the damage taken,
openings, cancelled charges, the shots sent back and the ones of them that
hit an enemy, what was heard - and, with --check, one PASS
or FAIL line per band of Balance.pacing, and the chain's lines: in the
flow fights' sound logs the death sound climbs over a 4-kill chain and
falls back after a break, and each flow fight's counted chains are the
ones its death sounds tell; the boss room plays at
Balance.pacing.bossDepths instead (2, 5 and 8, the Warden's first three
appearances) unless --depths is given, and at each of them "skilled"
kills the Warden within bossSkilled seconds of its engagement and does
not fall, "masher" and "charge" fall or take at least bossSlow times as
long. The skilled pilot steps out of a floor zone of the Warden's while
it warns. In every boss fight the Warden's wind-ups and strikes play its
toll and nothing screams before its adds come; in no flow or duel fight
is its toll heard (issue #287). No band checks the spitter duel or the
ball duel; --check tests the slinger's balls there instead (issue #322):
in each ball duel every ball that fell at a wall bounced
Balance.ball.bounces times first and none bounced more, each bounce at
the room's walls, and at each depth a ball the skilled pilot's shield
bounced hit the lead and opened it (its record's hits, the lead's
openings by "ball"); and one ball slung by hand across the ball duel's
room (Sandbox.tryBall) bounces off its walls Balance.ball.bounces times,
each where the mirror path off the walls puts it, and falls at the next
wall. The
person's fights get no band either: a section of their own says of each
whether the person won - cleared the room without falling - and in how
many seconds, or how it lost, with its answers and misses (issue #315);
--check tests its own rule instead: its misses over all its fights lie
within Balance.pacing.person.missSlack of its share. Unless --answers is
given, the run also plays "stun" in the flow and the duel room at its
first depth, banded by no table; --check tests the stun on them (issue
#318): in the flow fight it froze enemies, each frozen span lasted
Balance.stun.freeze from the stun that froze it last, within two steps,
the enemy did not move in it and thawed into the chase, never into a
blow; in the duel it ended the lead's wind-ups, each time from a wind-up
into the chase, the lead not opened, its stance as it was, and never
froze it. It also plays "bolt" in the flow room at its first depth and in
the spitter duel at each depth, banded by no table but the duel's, and
shoots three bolts by hand in the flow room (Sandbox.tryBolt); --check
tests the bolt (issue #319): by hand, one at an enemy 5 wu off, out of
the sword's reach, deals Balance.bolt.damage times atk less its defense,
one with nothing in line flies Balance.bolt.reach and ends, an enemy just
past it unhurt, and one shot at the room's wall 5 wu off stops there; in
the fights it hit enemies, each hit dealt the damage the table allows - a
chip of it on a lead's stance, a guardian's shield's share from its front
-, some from out of the sword's reach, no bolt flew past its reach, every
bolt that ended at a wall ended at the room's wall and none outside the
room; and in the spitter duel the masher with the bolt takes at least
Balance.pacing.duelSlow seconds to kill the lead, or falls, as the masher
must in a duel. It also enters the combo by hand in the flow room
(Sandbox.tryCombo, issue #320): for each special the knight's moves away
from its aim, then towards it, as a pilot walks, and the special's button
at once, then the same with the button later than Balance.combo.window;
--check tests that the combo fires each stronger version - the stun
freezes an enemy past the stun's reach, the bolt deals
Balance.combo.bolt.damage times atk, the whirlwind hits enemies past its
reach for Balance.combo.whirlwind.swing times atk and spins longer - the
late button the normal one, and that the knight walks on through it.
--json writes every report in full, sound log
and music trace included. Exits 1 when a band fails under --check, 2 when
a fight could not be played.

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
ANSWERS = ("mix", "block", "parry", "perfect", "heavy", "whirlwind", "stun", "bolt", "charge",
           "masher", "skilled", "person")
PILOTS = ("charge", "masher", "skilled", "person")
# The pilot that plays like a person (issue #315): reported, not banded
PERSON = "person"
# The stun's pilot (issue #318): its fights are judged by check_stun, never
# banded, in these rooms at the first depth of a pacing run
STUN = "stun"
STUN_ROOMS = ("flow", "duel")
# The bolt's pilot (issue #319): judged by check_bolt and the duel's band
# alone, in the flow room at the first depth of a pacing run and in the
# spitter duel at each
BOLT = "bolt"


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


def shoot_bolts(loader, seed):
    """The three bolts shot by hand in the flow room (Sandbox.tryBolt,
    issue #319), or raises FightError"""
    tmp, bench, proc, log = start_loader(loader)
    try:
        if not bench.wait_phase("ready"):
            raise FightError("the sandbox did not load", tmp)
        if bench.eval1(f"begin({seed}, '{BOLT}', 0, 'flow', 0)") is not True:
            raise FightError("the fight room did not start", tmp)
        time.sleep(1.0)
        shots = json.loads(bench.eval1("tryBolt()") or "null")
    except (TimeoutError, json.JSONDecodeError, TypeError) as e:
        raise FightError(f"the bolts could not be shot: {e}", tmp)
    finally:
        stop_loader(proc, log)
    if not isinstance(shots, dict):
        raise FightError(f"the bolts shot nothing: {shots!r}", tmp)
    shutil.rmtree(tmp, ignore_errors=True)
    return shots


def check_bolt_shots(s, step=1 / 60):
    """(ok, line) for the bolts shot by hand: the damage of one at an
    enemy out of the sword's reach, the reach of one with nothing in line,
    the wall that ends one"""
    hit, far, wall = s["hit"], s["far"], s["wall"]
    one = s["speed"] * step
    return [
        (hit.get("how") == "enemy" and hit.get("dealt") == hit["want"] == hit["lost"]
         and hit["gap"] > s["swordReach"],
         f"bolt by hand: at an enemy {hit['gap']} wu off, out of the sword's {s['swordReach']} wu, it deals "
         f"bolt.damage times atk {s['atk']} less its defense, {hit['want']} ({hit.get('how')}, dealt "
         f"{hit.get('dealt')}, the enemy lost {hit['lost']})"),
        (far.get("how") == "reach" and abs(far.get("travelled", 0) - s["reach"]) <= one + 1e-3
         and far["lost"] == 0,
         f"bolt by hand: nothing in line it flies its reach of {s['reach']} wu and ends ({far.get('how')} after "
         f"{far.get('travelled')} wu), the enemy {far['enemyAt']} wu off unhurt (lost {far['lost']})"),
        (wall.get("how") == "wall" and wall["toWall"] - 1 <= wall.get("travelled", -1) <= wall["toWall"]
         and abs(wall.get("edge", 0) - s["roomHalf"]) <= 0.6,
         f"bolt by hand: shot at the room's wall {wall['toWall']} wu off it stops there ({wall.get('how')} after "
         f"{wall.get('travelled')} wu, {wall.get('edge')} wu from the centre, the wall at {s['roomHalf']})"),
    ]


def sling_ball(loader, seed):
    """The metal ball slung by hand in the ball duel (Sandbox.tryBall,
    issue #322), or raises FightError"""
    tmp, bench, proc, log = start_loader(loader)
    try:
        if not bench.wait_phase("ready"):
            raise FightError("the sandbox did not load", tmp)
        if bench.eval1(f"begin({seed}, 'skilled', 1, 'ballduel', 0)") is not True:
            raise FightError("the ball duel did not start", tmp)
        time.sleep(1.0)
        ball = json.loads(bench.eval1("tryBall()") or "null")
    except (TimeoutError, json.JSONDecodeError, TypeError) as e:
        raise FightError(f"the ball could not be slung: {e}", tmp)
    finally:
        stop_loader(proc, log)
    if not isinstance(ball, dict) or not ball.get("ball"):
        raise FightError(f"the ball slung nothing: {ball!r}", tmp)
    shutil.rmtree(tmp, ignore_errors=True)
    return ball


def mirror_path(x, y, dx, dy, lo, hi, n):
    """Where a ball from (x, y) along (dx, dy) touches the walls of a box
    [lo, hi] on both axes, its centre: its first n contacts, each with
    the axis it meets"""
    out = []
    for _ in range(n):
        tx = (hi[0] - x) / dx if dx > 0 else (x - lo[0]) / -dx if dx < 0 else float("inf")
        ty = (hi[1] - y) / dy if dy > 0 else (y - lo[1]) / -dy if dy < 0 else float("inf")
        t = min(tx, ty)
        x, y = x + dx * t, y + dy * t
        axis = "x" if tx <= ty else "y"
        if axis == "x":
            dx = -dx
        else:
            dy = -dy
        out.append((x, y, axis))
    return out


def check_ball_by_hand(s, step=1 / 60):
    """(ok, line) for the ball slung by hand: it bounces off the room's
    walls ballBounces times, each where the mirror path off the walls puts
    it, and falls at the next wall"""
    c, half, rad, most = s["centre"], s["roomHalf"], s["radius"], s["bounces"]
    lo = (c["x"] - half + rad, c["y"] - half + rad)
    hi = (c["x"] + half - rad, c["y"] + half - rad)
    path = mirror_path(s["from"]["x"], s["from"]["y"], s["dir"]["x"], s["dir"]["y"], lo, hi, most + 1)
    ball = s["ball"]
    got = ball["bounces"]
    across = s["speed"] * step + 2e-3
    off = []
    for i, h in enumerate(got):
        if i >= len(path):
            off.append(i + 1)
            continue
        x, y, axis = path[i]
        on, other = (abs(h["x"] - x), abs(h["y"] - y)) if axis == "x" else (abs(h["y"] - y), abs(h["x"] - x))
        if on > 2e-3 or other > across:
            off.append(i + 1)
    fell = ball.get("fell") or {}
    x, y, axis = path[most]
    fell_off = abs(fell.get("x", 1e9) - x) if axis == "x" else abs(fell.get("y", 1e9) - y)
    return [
        (len(got) == most and not off,
         f"ball by hand: slung across the ball duel's room it bounces {len(got)} times off its walls ({most} by "
         f"the table), each where the mirror path puts it (" + ", ".join(f"({h['x']:.2f}, {h['y']:.2f})" for h in got)
         + (f"; off at {off}" if off else "") + ")"),
        (fell.get("how") == "wall" and fell.get("bounces") == most and fell_off <= 2e-3,
         f"ball by hand: after them it falls at the next wall ({fell.get('how')} after {fell.get('bounces')} bounces "
         f"at ({fell.get('x', 0):.2f}, {fell.get('y', 0):.2f}), the wall at ({x:.2f}, {y:.2f}))"),
    ]


def enter_combos(loader, seed):
    """The combo entered by hand in the flow room for each special, and
    late (Sandbox.tryCombo, issue #320), or raises FightError"""
    tmp, bench, proc, log = start_loader(loader)
    try:
        if not bench.wait_phase("ready"):
            raise FightError("the sandbox did not load", tmp)
        if bench.eval1(f"begin({seed}, 'mix', 0, 'flow', 0)") is not True:
            raise FightError("the fight room did not start", tmp)
        time.sleep(1.0)
        combos = json.loads(bench.eval1("tryCombo()") or "null")
    except (TimeoutError, json.JSONDecodeError, TypeError) as e:
        raise FightError(f"the combos could not be entered: {e}", tmp)
    finally:
        stop_loader(proc, log)
    if not isinstance(combos, dict):
        raise FightError(f"the combos gave nothing: {combos!r}", tmp)
    shutil.rmtree(tmp, ignore_errors=True)
    return combos


def check_combos(c):
    """(ok, line) for the combos entered by hand: each special's stronger
    version right after the combo, the knight walking on through it, and
    the normal one with the button late"""
    lines = []
    when = f"away {c['away']} steps, towards {c['towards']}"
    late = f"later than the window of {c['window']} s"
    s, sl = c["stun"], c["stunLate"]
    lines.append((s["ready"] and s["strong"] and s["frozen"],
                  f"combo by hand: {when}, then the button, fires the stronger stun: an enemy {s['gap']} wu off, "
                  f"past the stun's reach, freezes (combo {'entered' if s['ready'] else 'not entered'}, "
                  f"{'stronger' if s['strong'] else 'normal'}, {'frozen' if s['frozen'] else 'not frozen'})"))
    lines.append((sl["went"] and not sl["strong"] and not sl["frozen"],
                  f"combo by hand: the button {late} fires the normal stun, the enemy {sl['gap']} wu off not "
                  f"frozen ({'stronger' if sl['strong'] else 'normal'}, {'frozen' if sl['frozen'] else 'not frozen'})"))
    b, bl = c["bolt"], c["boltLate"]
    lines.append((b["strong"] and b["lost"] == b["want"] and bl["went"] and not bl["strong"] and bl["lost"] == bl["want"]
                  and bl["size"] < b["size"],
                  f"combo by hand: the stronger bolt deals {b['want']} (lost {b['lost']}, {b['size']} wu across), "
                  f"the late one the normal {bl['want']} (lost {bl['lost']}, {bl['size']} wu across)"))
    w, wl = c["whirl"], c["whirlLate"]
    lines.append((w["strong"] and all(x == w["want"] for x in w["lost"]) and wl["went"] and not wl["strong"]
                  and wl["lost"] == [0, 0] and w["seconds"] > wl["seconds"],
                  f"combo by hand: the stronger whirlwind hits both enemies {round(w['side'], 2)} wu either side for "
                  f"{w['want']} (lost {w['lost']}) over {w['seconds']} s, the late one neither (lost {wl['lost']}) "
                  f"over {wl['seconds']} s"))
    slowest = min(x["slowest"] for x in (s, b, w))
    lines.append((slowest >= c["moveSpeed"] * 0.5,
                  f"combo by hand: the knight walks on through every combo (slowest {slowest:.2f} wu/s, "
                  f"its speed {c['moveSpeed']})"))
    return lines


def play_fight(loader, seed, answer, danger, room, sword, max_seconds, batch, boots=0):
    """Plays one fight in a loader of its own; returns its report, or raises
    FightError with the directory the logs are kept in"""
    tmp, bench, proc, log = start_loader(loader)
    try:
        if not bench.wait_phase("ready"):
            raise FightError("the sandbox did not load", tmp)
        if bench.eval1(f"begin({seed}, '{answer}', {danger}, '{room}', {sword}, {boots})") is not True:
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
# The pacing rooms, and among them the duel rooms with bands: a grunt lead
# alone and a guardian lead alone (Balance.pacing.duel, .guardianDuel); the
# spitter lead's duel (.spitterDuel, issue #315) has none
# the slinger's (.ballDuel, issue #322) has none either: check_ball tests it
ROOMS = ("flow", "duel", "guardianduel", "spitterduel", "ballduel", "boss")
DUELS = ("duel", "guardianduel")


def fmt_s(v):
    return "-" if v is None else f"{v:.2f} s"


def boots_tag(r):
    """" boots 3 (9.0 wu/s)" for a fight with swift boots, else nothing"""
    return f" boots {r['boots']} ({r['moveSpeed']} wu/s)" if r.get("boots") else ""


def describe(r):
    """The report of one fight as lines of text"""
    stun = ""
    if r["answer"] == STUN:
        stun = (f", stuns {r.get('stuns', 0)}, froze {r.get('stunFrozen', 0)}, "
                f"ended {r.get('stunInterrupted', 0)} wind-ups")
    if r["answer"] == BOLT:
        how = Counter(b["how"] for b in r.get("boltEnds", []))
        stun = (f", bolts {r.get('bolts', 0)}, hits {r.get('boltHits', 0)} ("
                + ", ".join(f"{k} {n}" for k, n in sorted(how.items())) + ")")
    lines = [f"{r['room']} depth {r['depth']} sword {r['sword']}{boots_tag(r)} {r['answer']}: "
             f"{r['outcome']} after {r['seconds']:.2f} s, damage taken {r['damageTaken']}, "
             f"openings {r['openings']}, cancelled charges {r['cancelledCharges']}, "
             f"engaged {r['engagedSeconds']:.2f} s, shots sent back {r.get('shotsBack', 0)} "
             f"({r.get('shotBackHits', 0)} hit){stun}"]
    balls = r.get("balls") or []
    if balls:
        fell = Counter(b["fell"]["how"] for b in balls if b.get("fell"))
        lines.append(f"  balls: {len(balls)} slung, {sum(len(b['bounces']) for b in balls)} wall bounces, "
                     f"{r.get('ballsBack', 0)} bounced by the shield ({r.get('ballsAimed', 0)} aimed by a perfect "
                     f"block), {r.get('ballBackHits', 0)} hit an enemy; fell "
                     + (", ".join(f"{k} {n}" for k, n in sorted(fell.items())) or "none"))
    for e in r["enemies"]:
        # A lead's openings by what broke its stance (Balance.lead)
        opened = e.get("opened") or {}
        by = (" (" + ", ".join(f"{c} {n}" for c, n in sorted(opened.items())) + ")") if opened else ""
        lead = ", lead" if e.get("lead") else ""
        lines.append(f"  {e['type']} ({TIERS[e['tier']]}{lead}, {e['hp']} HP): hits {e['hits']}, "
                     f"ttk {fmt_s(e['ttk'])} from its first hit, {fmt_s(e['ttkEngaged'])} "
                     f"from engaging, died at {fmt_s(e['diedAt'])}, openings {e['openings']}{by}")
    person = r.get("person")
    if person:
        lines.append(f"  the person: {answers_line(person)}")
    boss = r.get("boss")
    if boss:
        lines.append(f"  the Warden: {boss['stage']}, phase 2 from {fmt_s(boss['phase2At'])}, "
                     f"{boss['adds']} adds, {boss['zones']} zones opened, {boss['zoneHits']} hurt the knight")
    if r["killGaps"]:
        lines.append("  gaps between kills: " + ", ".join(f"{g:.2f}" for g in r["killGaps"]) + " s")
    pitches = death_pitches(r)
    if pitches:
        lines.append(f"  chains {r['chains']}, longest {r['longestChain']}; the death sound at "
                     + ", ".join(f"{p:+d}" for p in pitches) + " semitones")
    if r.get("chainBlows"):
        lines.append(f"  chain bonus: {r['chainBlows']} blows stronger, +{r['chainExtra']} points, "
                     f"peak +{round(r['chainPeak'] * 100)}%")
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
        spans = duel_spans(music, "state")
        played = duel_spans(music, "segment")
        lines.append("  duel part: " + (", ".join(fmt_span(a, b) for a, b in spans) if spans else "none")
                     + "; played " + (", ".join(fmt_span(a, b) for a, b in played) if played else "never")
                     + f"; growls {sum(1 for x in r['sounds'] if x['what'] == 'growl' and x['cue'] == GROWL)}"
                     + f", stings {sum(1 for x in r['sounds'] if x['what'] == 'sting')}")
    return lines


def answers_line(person):
    """The person's answers and misses (issue #315) as text"""
    a, m = person["answers"], person["missed"]
    fastest = person.get("fastest")
    return (f"missed {sum(m.values())} of {sum(a.values())} answers ("
            + ", ".join(f"{k} {m[k]}/{a[k]}" for k in ("parry", "perfect", "shot"))
            + "), fastest answer " + ("-" if fastest is None else f"{fastest:.3f} s")
            + f" after it began (reaction {person['reaction']} s, miss {person['miss']})")


def person_lines(results):
    """(won, line) per fight of the person (issue #315): won is the room
    cleared without falling; the line says in how many seconds, or how it
    lost - fell, or still at it when the fight was stopped - and what
    stood then"""
    out = []
    for r in results:
        if r["answer"] != PERSON:
            continue
        tag = f"{r['room']} depth {r['depth']} sword {r['sword']}{boots_tag(r)}"
        leads = [e for e in r["enemies"] if e.get("lead") or e["type"] == "warden"]
        lead = leads[0] if leads else None
        won = r["outcome"] == "cleared"
        if won:
            what = f"cleared in {r['seconds']:.2f} s"
            if lead and lead["ttkEngaged"] is not None:
                what += f", the {lead['type']} lead killed {lead['ttkEngaged']:.2f} s after it engaged"
        else:
            what = ("fell" if r["outcome"] == "fallen" else "still fighting") + f" after {r['seconds']:.2f} s"
            standing = [e for e in r["enemies"] if e["diedAt"] is None]
            if standing:
                what += ", standing: " + ", ".join(
                    f"{e['type']} {e.get('hpLeft', '?')} of {e['hp']} HP" for e in standing)
        what += f"; knight HP {r['knightHp']}, damage taken {r['damageTaken']}"
        out.append((won, f"{tag}: {what}; {answers_line(r['person'])}"))
    return out


def check_person_misses(results, person):
    """(ok, line) for the person's misses (issue #315), when it played: over
    all its fights they lie within missSlack of its share miss - the pilot's
    own rule, not a band on its wins"""
    rs = [r for r in results if r["answer"] == PERSON and r.get("person")]
    answers = sum(sum(r["person"]["answers"].values()) for r in rs)
    if not rs or not answers:
        return []
    missed = sum(sum(r["person"]["missed"].values()) for r in rs)
    share, slack = person["miss"], person["missSlack"]
    return [(abs(missed / answers - share) <= slack + 1e-9,
             f"the person misses {share} of its answers, give or take {slack} "
             f"({missed} of {answers}, {missed / answers:.2f}, in {len(rs)} fights)")]


def check_stun(results, step=1 / 60):
    """(ok, line) for the stun's fights (issue #318): in a flow fight the
    knight stunned and froze enemies, every frozen span ended lasted
    Balance.stun.freeze from the stun that froze it last, within two
    steps, its enemy did not move and thawed into the chase; no weak or
    normal enemy was anything but frozen by a stun. In a duel the stun
    ended the lead's wind-ups: each from a wind-up into the chase, not
    opened, its stance as it was; the lead never froze and no opening
    came on a stun's step"""
    out = []
    for r in results:
        if r["answer"] != STUN:
            continue
        tag = f"stun {r['room']} depth {r['depth']}"
        freeze = r.get("stunFreeze")
        small = [e for e in r["enemies"] if not e.get("lead") and e["type"] != "warden"]
        leads = [e for e in r["enemies"] if e.get("lead") or e["type"] == "warden"]
        if r["room"] == "flow":
            out.append((r.get("stuns", 0) > 0 and r.get("stunFrozen", 0) > 0,
                        f"{tag}: the knight stuns and freezes small enemies ({r.get('stuns', 0)} stuns, "
                        f"{r.get('stunFrozen', 0)} frozen)"))
            spans = [sp for e in small for sp in e.get("frozenSpans", []) if sp["thawAt"] is not None]
            lasted = [sp["lasted"] for sp in spans if sp["lasted"] is not None]
            off = [x for x in lasted if abs(x - freeze) > 2 * step + 1e-6]
            out.append((bool(lasted) and not off and len(lasted) == len(spans),
                        f"{tag}: each frozen span lasts {freeze} s from its stun, within two steps "
                        f"({len(lasted)} spans, " + (f"{min(lasted):.3f}-{max(lasted):.3f} s" if lasted else "none")
                        + (f", off: {off}" if off else "") + ")"))
            moved = max([sp["moved"] for e in small for sp in e.get("frozenSpans", [])], default=0)
            out.append((moved <= 0.01, f"{tag}: a frozen enemy does not move (at most {moved:.3f} wu)"))
            into = Counter(sp["into"] for sp in spans)
            out.append((bool(spans) and set(into) == {"chase"},
                        f"{tag}: a frozen enemy thaws into the chase, never into a blow ("
                        + ", ".join(f"{k} {n}" for k, n in sorted(into.items())) + ")"))
            whats = Counter(s["what"] for e in small for s in e.get("stuns", []))
            cut = sum(1 for e in small for s in e.get("stuns", []) if s["before"] in ("telegraph", "crush", "lunge"))
            out.append((set(whats) <= {"frozen"},
                        f"{tag}: a stun freezes a weak or normal enemy, nothing else ("
                        + ", ".join(f"{k} {n}" for k, n in sorted(whats.items())) + f"; {cut} of them "
                        "cut an attack short)"))
        else:
            stuns = [s for e in leads for s in e.get("stuns", [])]
            ended = [s for s in stuns if s["what"] == "interrupted"]
            out.append((len(ended) > 0 and r.get("stunInterrupted", 0) == len(ended),
                        f"{tag}: the stun ends the lead's wind-ups ({len(ended)} ended, "
                        f"the record {r.get('stunInterrupted', 0)})"))
            bad = [s for s in stuns if s["what"] != "interrupted"
                   or s["before"] not in ("telegraph", "crush", "shoot") or s["after"] != "chase"]
            out.append((not bad, f"{tag}: each from a wind-up into the chase ("
                                 + ", ".join(sorted({f"{s['before']}->{s['after']}" for s in stuns})) + ")"))
            opened = [s for s in stuns if s["opening"] or abs(s["stance"] - s["stanceBefore"]) > 1e-6]
            on_stun = [o for e in leads for o in e.get("openedAt", [])
                       if any(abs(o["t"] - s["t"]) <= step + 1e-6 for s in stuns)]
            out.append((not opened and not on_stun,
                        f"{tag}: the lead is not opened and keeps its stance ({len(opened)} stuns opened it "
                        f"or wore its stance, {len(on_stun)} openings on a stun's step; its openings "
                        + (", ".join(f"{c} {n}" for e in leads for c, n in sorted((e.get('opened') or {}).items()))
                           or "none") + ")"))
            froze = sum(len(e.get("frozenSpans", [])) for e in leads)
            out.append((froze == 0, f"{tag}: the lead never freezes ({froze} frozen spans)"))
    return out


def check_bolt(results, step=1 / 60):
    """(ok, line) for the bolt's fights (issue #319): in the flow fight it
    hit enemies; in every bolt fight each hit dealt a damage the table
    allows, some hit from out of the sword's reach, no bolt flew past its
    reach and one that ended there flew all of it, every bolt that ended
    at a wall ended at the room's wall and none outside the room; in the
    spitter duel the masher with the bolt takes at least duelSlow seconds
    to kill the lead, or falls, and the masher's own time beside it"""
    out = []
    rs = [r for r in results if r["answer"] == BOLT]
    for r in rs:
        tag = f"bolt {r['room']} depth {r['depth']}"
        ends = r.get("boltEnds", [])
        hits = [b for b in ends if b["how"] == "enemy"]
        reach, speed, half = r["boltReach"], r["boltSpeed"], r["roomHalf"]
        if r["room"] == "flow":
            out.append((r.get("bolts", 0) > 0 and len(hits) > 0 and r.get("boltHits", 0) == len(hits),
                        f"{tag}: the knight lets bolts loose and hits enemies ({r.get('bolts', 0)} bolts, "
                        f"{len(hits)} hits, the record {r.get('boltHits', 0)})"))
        off = [b for b in hits if b["dealt"] not in b["allowed"]]
        dealt = Counter(f"{b['type']}{' lead' if b['lead'] else ''} {b['dealt']}" for b in hits)
        out.append((bool(hits) and not off,
                    f"{tag}: each hit deals the damage the table allows ("
                    + ", ".join(f"{k} x{n}" for k, n in sorted(dealt.items()))
                    + (f"; off: {[(b['dealt'], b['allowed']) for b in off]}" if off else "") + ")"))
        far = [b for b in hits if b["travelled"] > r["swordReach"]]
        out.append((bool(far), f"{tag}: it hurts from out of the sword's reach ({len(far)} of {len(hits)} hits "
                               f"flew more than {r['swordReach']} wu, the farthest "
                               f"{max((b['travelled'] for b in hits), default=0):.2f} wu)"))
        longest = max((b["travelled"] for b in ends), default=0)
        at_reach = [b for b in ends if b["how"] == "reach"]
        short = [b for b in at_reach if b["travelled"] < reach - 1e-3]
        out.append((longest <= reach + speed * step + 1e-3 and not short,
                    f"{tag}: no bolt flies past its reach of {reach} wu (the longest {longest:.2f} wu; "
                    f"{len(at_reach)} ended at it)"))
        wall = [b for b in ends if b["how"] == "wall"]
        astray = [b for b in wall if not half - 0.6 <= b["edge"] <= half + 0.1]
        outside = [b for b in ends if b["edge"] > half + 0.1]
        out.append((not astray and not outside,
                    f"{tag}: a bolt that ends at a wall ends at the room's wall, none outside the room "
                    f"({len(wall)} at a wall, {half - 0.6:.1f}-{half + 0.1:.1f} wu from the centre"
                    + (f"; astray {[b['edge'] for b in astray]}" if astray else "")
                    + (f"; outside {[b['edge'] for b in outside]}" if outside else "") + ")"))
        if r["room"] == "spitterduel":
            bands = r["pacing"]
            leads = [e for e in r["enemies"] if e["tier"] == 2] or r["enemies"]
            t = leads[0]["ttkEngaged"]
            masher = next((m for m in results if m["answer"] == "masher" and m["room"] == "spitterduel"
                           and m["depth"] == r["depth"]), None)
            mt = None
            if masher:
                ml = [e for e in masher["enemies"] if e["tier"] == 2] or masher["enemies"]
                mt = "fell" if masher["outcome"] == "fallen" else "alive" if ml[0]["ttkEngaged"] is None \
                    else f"{ml[0]['ttkEngaged']:.2f} s"
            ok = r["outcome"] == "fallen" or t is None or t >= bands["duelSlow"]
            what = "fell" if r["outcome"] == "fallen" else "alive" if t is None else f"{t:.2f} s"
            out.append((ok, f"{tag}: the masher with the bolt takes at least {bands['duelSlow']} s to kill "
                            f"the spitter lead, or falls ({what}, {len(hits)} bolt hits; the masher without "
                            f"it {mt or 'not played'})"))
    return out


def check_ball(results):
    """(ok, line) for the slinger's balls in the ball duels (issue #322):
    in each fight every ball that fell at a wall bounced ballBounces times
    first, none bounced more, and each bounce touched the room's walls;
    over the ball duels balls bounced off the walls; at each depth a ball
    the skilled pilot's shield bounced hit the lead and opened it"""
    out = []
    rs = [r for r in results if r["room"] == "ballduel"]
    for r in rs:
        tag = f"ballduel depth {r['depth']} {r['answer']}"
        balls, most = r.get("balls") or [], r["ballBounces"]
        wall = [b for b in balls if b.get("fell") and b["fell"]["how"] == "wall"]
        short = [b["id"] for b in wall if len(b["bounces"]) != most]
        over = [b["id"] for b in balls if len(b["bounces"]) > most]
        half, rad = r["roomHalf"], r["ballRadius"]
        astray = [h["edge"] for b in balls for h in b["bounces"] if abs(h["edge"] - (half - rad)) > 1e-3]
        out.append((not short and not over and not astray,
                    f"{tag}: every ball that fell at a wall bounced {most} times first, none more, each bounce "
                    f"at the room's walls ({len(balls)} balls, {len(wall)} fell at a wall, "
                    f"{sum(len(b['bounces']) for b in balls)} bounces"
                    + (f"; short {short}" if short else "") + (f"; over {over}" if over else "")
                    + (f"; astray {astray[:5]}" if astray else "") + ")"))
    for r in rs:
        if r["answer"] != "skilled":
            continue
        leads = [e for e in r["enemies"] if e.get("lead")]
        opened = sum((e.get("opened") or {}).get("ball", 0) for e in leads)
        out.append((r.get("ballBackHits", 0) > 0 and opened > 0,
                    f"ballduel depth {r['depth']} skilled: a ball its shield bounced hits the lead and opens it "
                    f"({r.get('ballsBack', 0)} bounced, {r.get('ballsAimed', 0)} aimed, {r.get('ballBackHits', 0)} hit, "
                    f"the lead opened by a ball {opened} times)"))
    return out


def death_pitches(r):
    """The pitch of every death sound the fight played, in order"""
    return [s["pitch"] for s in r["sounds"] if s["what"] == "death"]


def climbs(pitches, links):
    """Where pitches has a chain of links deaths climbing from the burst's
    own pitch, each a step above the one before: its start, else None"""
    for i in range(len(pitches) - links + 1):
        run = pitches[i:i + links]
        if run[0] == 0 and all(b > a for a, b in zip(run, run[1:])):
            return i
    return None


def falls_back(pitches):
    """Where a death sound plays at the burst's own pitch right after one
    above it, a chain broken: its index, else None"""
    for i in range(1, len(pitches)):
        if pitches[i] == 0 and pitches[i - 1] > 0:
            return i
    return None


def check_chain(results, links=4):
    """The kill chain's lines (issue #270): in the flow fights' sound logs
    the death sound climbs over a links-kill chain somewhere and falls back
    after a break somewhere; and no fight's chains run past its kills"""
    flows = [r for r in results if r["room"] == "flow"]
    if not flows:
        return []
    def tag(r):
        return f"flow depth {r['depth']} {r['answer']}"
    climb = next((r for r in flows if climbs(death_pitches(r), links) is not None), None)
    fall = next((r for r in flows if falls_back(death_pitches(r)) is not None), None)
    out = [(climb is not None,
            f"chain: the death sound climbs over a {links}-kill chain ("
            + (f"{tag(climb)}: " + ", ".join(f"{p:+d}" for p in death_pitches(climb)) if climb
               else "in no flow fight") + ")"),
           (fall is not None,
            "chain: the death sound falls back after a break ("
            + (f"{tag(fall)}: " + ", ".join(f"{p:+d}" for p in death_pitches(fall)) if fall
               else "in no flow fight") + ")")]
    for r in flows:
        heard = heard_chains(death_pitches(r))
        ok = (r["chains"], r["longestChain"]) == (len(heard), max(heard, default=0))
        out.append((ok, f"{tag(r)}: the counted chains are the ones heard (counted {r['chains']}, "
                        f"longest {r['longestChain']}; heard {len(heard)}, longest "
                        f"{max(heard, default=0)})"))
    return out


def heard_chains(pitches):
    """The chains of two links or more the death sounds tell: a death at a
    pitch above the one before is the next link, at the top of the scale
    the top again too; their lengths"""
    out, links = [], 0
    for i, p in enumerate(pitches):
        links = links + 1 if i > 0 and links > 0 and (p > pitches[i - 1] or p == pitches[i - 1] > 0) else 1
        if links == 2:
            out.append(2)
        elif links > 2:
            out[-1] = links
    return out


# The duel's sounds (issue #273): the lead's growl and the song's sting
GROWL = "sfx/lead_growl"


def duel_spans(music, key):
    """The spans of the physics clock in which the music trace's key
    ("state", what the game asks for, or "segment", what the song plays) is
    the duel part: [(from, to)], to None while it lasts to the end"""
    spans, at = [], None
    for m in music:
        if m[key] == "duel" and at is None:
            at = m["t"]
        elif m[key] != "duel" and at is not None:
            spans.append((at, m["t"]))
            at = None
    if at is not None:
        spans.append((at, None))
    return spans


def fmt_span(a, b):
    return f"{a:.2f}-{'end' if b is None else f'{b:.2f}'} s"


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
        spans = duel_spans(r["music"], "state")
        out.append((not spans, f"{tag}: the song stays in its flow part "
                               f"({'duel ' + ', '.join(fmt_span(a, b) for a, b in spans) if spans else 'flow only'})"))
    # Each lead's duel room (issue #288) by depth
    duels = {}
    for r in results:
        if r["room"] in DUELS:
            duels.setdefault((DUELS.index(r["room"]), r["depth"]), {})[r["answer"]] = r
    for (i, depth), by in sorted(duels.items()):
        duel = DUELS[i]
        for pilot, r in sorted(by.items()):
            out.extend(check_duel_sound(r, f"{duel} depth {depth} {pilot}"))
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
            out.append((ok, f"{duel} depth {depth} {pilot}: takes at least {bands['duelSlow']} s "
                            f"or falls ({what})"))
            # The lead strikes a knight charging in its reach first (#272)
            if pilot == "charge":
                least = bands["duelCancelled"]
                out.append((r["cancelledCharges"] >= least,
                            f"{duel} depth {depth} charge: hits cancel at least {least} "
                            f"{'charge' if least == 1 else 'charges'} ({r['cancelledCharges']})"))
        r = by.get("skilled")
        if r:
            t = lead_time(r)
            lo, hi = bands["duelSkilled"]
            ok = r["outcome"] == "cleared" and t is not None and lo <= t <= hi
            what = r["outcome"] if t is None else f"{t:.2f} s, {r['outcome']}"
            out.append((ok, f"{duel} depth {depth} skilled: kills the lead in {lo}-{hi} s ({what})"))
            others = [by[p] for p in ("masher", "charge") if p in by]
            if others:
                took = ", ".join(f"{o['answer']} {o['damageTaken']}" for o in others)
                out.append((all(r["damageTaken"] < o["damageTaken"] for o in others),
                            f"{duel} depth {depth} skilled: takes less damage than the others "
                            f"({r['damageTaken']}; {took})"))
    return out + check_chain(results) + check_boss(results, bands) + check_warden_sound(results)


def check_boss(results, bands):
    """The boss room's bands (issues #274, #289): at each of bossDepths
    played "skilled" kills the Warden within bossSkilled seconds of its
    engagement and does not fall; "masher" and "charge" fall, or take at
    least bossSlow times as long - or are still at it when the fight was
    stopped that late"""
    def warden(r):
        return next((e for e in r["enemies"] if e["type"] == "warden"), None)
    out = []
    for depth in bands["bossDepths"]:
        by = {r["answer"]: r for r in results if r["room"] == "boss" and r["depth"] == depth}
        skilled_t = None
        r = by.get("skilled")
        if r:
            w = warden(r)
            t = w["ttkEngaged"] if w else None
            lo, hi = bands["bossSkilled"]
            skilled_t = t
            ok = r["outcome"] != "fallen" and t is not None and lo <= t <= hi
            what = "never died" if t is None else f"{t:.2f} s"
            out.append((ok, f"boss depth {depth} sword {r['sword']} skilled: kills the Warden in {lo}-{hi} s "
                            f"and does not fall ({what}, {r['outcome']})"))
        for pilot in ("masher", "charge"):
            r = by.get(pilot)
            if not r:
                continue
            w = warden(r)
            t = w["ttkEngaged"] if w else None
            least = bands["bossSlow"] * (skilled_t if skilled_t is not None else bands["bossSkilled"][0])
            ok = r["outcome"] == "fallen" or (t is not None and t >= least) or (t is None and r["seconds"] >= least)
            what = "fell" if r["outcome"] == "fallen" else f"alive after {r['seconds']:.2f} s" if t is None \
                else f"{t:.2f} s"
            out.append((ok, f"boss depth {depth} sword {r['sword']} {pilot}: falls or takes at least "
                            f"{bands['bossSlow']} times as long as skilled, {least:.2f} s ({what})"))
    return out


# The Warden's own toll (issue #287) and the goblin's scream
TOLL = "sfx/warden_toll"
SCREAM = "sfx/goblin_scream"


def check_warden_sound(results):
    """(ok, line) per fight for the Warden's toll (issue #287): in every
    boss fight its wind-ups and its strikes toll, and nothing screams
    before its adds come in its phase 2 - until then it stands alone, so a
    scream would be its own -; in every flow and duel fight the toll is
    never heard"""
    out = []
    for r in results:
        tag = f"{r['room']} depth {r['depth']} {r['answer']}"
        tolls = [s for s in r["sounds"] if s["cue"] == TOLL]
        if r["room"] != "boss":
            out.append((not tolls, f"{tag}: the Warden's toll is never heard ({len(tolls)})"))
            continue
        winds = [s for s in tolls if s["what"] == "windUp"]
        strikes = [s for s in tolls if s["what"] == "strike"]
        adds_at = (r.get("boss") or {}).get("phase2At")
        early = [s for s in r["sounds"] if s["cue"] == SCREAM and (adds_at is None or s["t"] < adds_at)]
        pitches = sorted({f"{s['pitch']:+d}" for s in tolls})
        out.append((bool(winds) and bool(strikes) and not early,
                    f"{tag}: the Warden's wind-ups and strikes toll ({len(winds)} wind-ups, "
                    f"{len(strikes)} strikes, at {', '.join(pitches) or '-'}), nothing screams before its "
                    f"adds ({len(early)} screams before {fmt_s(adds_at) if adds_at is not None else 'the end'})"))
    return out


def check_duel_sound(r, tag):
    """(ok, line) for how a duel sounds (issue #273): the song's state is its
    duel part from the lead's engagement to its fall and its flow part
    after, the lead growls once as it engages, and every opening stings"""
    out = []
    leads = [e for e in r["enemies"] if e.get("lead")]
    if not leads or leads[0]["engagedAt"] is None:
        return [(False, f"{tag}: the lead engaged (no lead, or it never engaged)")]
    lead, step = leads[0], 0.05
    spans = duel_spans(r["music"], "state")
    start, end = spans[0] if spans else (None, None)
    died = lead["diedAt"]
    # The state follows on the step after the fall: a lead that fell on
    # the fight's last step, after which the bench steps no more, leaves
    # the duel part to the end
    last = died is not None and died >= r["seconds"] - step
    ok = (len(spans) == 1 and abs(start - lead["engagedAt"]) <= step
          and (died is None or (end is None and last) or (end is not None and abs(end - died) <= step)))
    out.append((ok, f"{tag}: the song's state is its duel part from the lead's engagement at "
                    f"{lead['engagedAt']:.2f} s {'to its fall at ' + format(died, '.2f') + ' s' if died is not None else 'on'}"
                    f" ({', '.join(fmt_span(a, b) for a, b in spans) if spans else 'never'}"
                    f"{', the fight ends on its fall' if last and end is None else ''})"))
    growls = [x for x in r["sounds"] if x["cue"] == GROWL]
    out.append((len(growls) == 1 and growls[0]["t"] <= lead["engagedAt"] + step,
                f"{tag}: the lead growls once as it engages "
                f"({', '.join(format(x['t'], '.2f') + ' s' for x in growls) or 'never'})"))
    stings = [x for x in r["sounds"] if x["what"] == "sting"]
    out.append((len(stings) >= lead["openings"],
                f"{tag}: a sting for every opening ({len(stings)} stings, {lead['openings']} openings)"))
    return out


def pacing(args, loader):
    rooms = args.rooms or list(ROOMS)
    answers = args.answers or list(PILOTS)
    fights = []
    # The depths are the game's own (Balance.pacing.depths), read as the
    # bands are, unless given; the boss room plays at its own,
    # Balance.pacing.bossDepths (issue #289)
    depths = boss_depths = args.depths
    if not depths:
        try:
            p = read_pacing(loader)
        except FightError as e:
            print(f"FAIL {e}; logs in {e.logs}", file=sys.stderr)
            sys.exit(2)
        depths, boss_depths = p["depths"], p.get("bossDepths") or p["depths"]
    for room in rooms:
        for depth in (boss_depths if room == "boss" else depths):
            for answer in answers:
                fights.append((room, depth, answer))
    # The stun's fights (issue #318), at the first depth; the bolt's (issue
    # #319) in the flow room at the first depth and the spitter duel at each
    if not args.answers:
        fights += [(room, depths[0], STUN) for room in STUN_ROOMS if room in rooms]
        if "flow" in rooms:
            fights.append(("flow", depths[0], BOLT))
        if "spitterduel" in rooms:
            fights += [("spitterduel", d, BOLT) for d in depths]
    results, errors = {}, []
    shots = None
    combos = None
    slung = None
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(play_fight, loader, args.seed, a, d, room, -1, args.max_seconds,
                               args.batch, args.boots): (room, d, a) for room, d, a in fights}
        # The bolts shot by hand (issue #319)
        shooting = pool.submit(shoot_bolts, loader, args.seed) \
            if not args.answers and "flow" in rooms else None
        # The combos entered by hand (issue #320)
        entering = pool.submit(enter_combos, loader, args.seed) \
            if not args.answers and "flow" in rooms else None
        # The metal ball slung by hand (issue #322)
        slinging = pool.submit(sling_ball, loader, args.seed) \
            if not args.answers and "ballduel" in rooms else None
        if shooting:
            try:
                shots = shooting.result()
            except FightError as e:
                errors.append(f"FAIL the bolts by hand: {e}; logs in {e.logs}")
        if slinging:
            try:
                slung = slinging.result()
            except FightError as e:
                errors.append(f"FAIL the ball by hand: {e}; logs in {e.logs}")
        if entering:
            try:
                combos = entering.result()
            except FightError as e:
                errors.append(f"FAIL the combos by hand: {e}; logs in {e.logs}")
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
    # The person's fights are reported, never banded (issue #315), nor are
    # the stun's (check_stun, issue #318) and the bolt's (check_bolt, issue
    # #319)
    banded = [r for r in ordered if r["answer"] not in (PERSON, STUN, BOLT)]
    person = person_lines(ordered)
    if person:
        p = ordered[0]["pacing"].get("person", {})
        print(f"\nthe person (reaction {p.get('reaction')} s, misses {p.get('miss')}), not banded: "
              f"a WIN is a fight a person can do")
        for won, line in person:
            print(("WIN  " if won else "LOSE ") + line)
        print(f"the person wins {sum(1 for won, _ in person if won)} of {len(person)} fights")
    lines = []
    if args.check and banded:
        lines = check(banded, banded[0]["pacing"])
    if args.check and person:
        lines += check_person_misses(ordered, ordered[0]["pacing"]["person"])
    if args.check:
        lines += check_stun(ordered) + check_bolt(ordered) + check_ball(ordered)
        if shots:
            lines += check_bolt_shots(shots)
        if combos:
            lines += check_combos(combos)
        if slung:
            lines += check_ball_by_hand(slung)
    if lines:
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
    ap.add_argument("--room", choices=("mixed",) + ROOMS, default="mixed",
                    help="who stands in the fight room")
    ap.add_argument("--sword", type=int,
                    help="the knight's sword level; default 0 in the mixed room, else the usual one")
    ap.add_argument("--boots", type=int, default=0,
                    help="the level of the knight's swift boots (Balance.shop.bootsSpeed); default 0")
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
    ap.add_argument("--rooms", nargs="+", choices=ROOMS, help="--pacing: these rooms")
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
                            args.max_seconds, args.batch, args.boots)
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
