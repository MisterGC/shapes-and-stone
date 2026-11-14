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
                    [--answer mix|block|parry|perfect|heavy|whirlwind|charge|masher|skilled|person]
                    [--room mixed|flow|duel|guardianduel|spitterduel|boss] [--sword N]
                    [--depth 0 | --danger 0.0] [--max-seconds 180] [--json out.json]
  run_fightbench.py --pacing [--check] [--rooms flow duel guardianduel spitterduel boss]
                    [--depths 0 2 4] [--answers charge masher skilled person] [--jobs N]
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
hits and the ones begun. The pacing pilots: "charge" holds a full charge
and lets go at the nearest enemy, "masher" clicks, "skilled" parries,
perfect-blocks - crushing blows and shots, which it sends back - and
strikes in openings, "person" plays as "skilled" with a person's reaction
time and misses (Balance.pacing.person, issue #315). --room is who stands in the fight room: "mixed" its usual lineup (Balance.spawn.fightRoom), "flow" fodder
only, "duel" a room's lead alone, a grunt, "guardianduel" a guardian lead
alone (issue #288), "spitterduel" a spitter lead alone (issue #315) and
"boss" the Hollow Warden alone, its
adds coming in its phase 2 (Balance.pacing, Balance.boss). --sword is the
knight's sword level: by default 0 in the mixed room and in flow and duel
the one a knight usually has at that depth. --danger is the danger the
fight room is at, its depth plus a position in the depth's range (2.5:
half way through depth 2's): the lineup stays, the enemies hit as hard as
at that danger. --depth d is --danger d, the bottom of the depth's range.
The same seed and danger give the same numbers.

--pacing plays every room of --rooms at every depth of --depths with every
pilot of --answers (by default flow, duel, guardianduel, spitterduel and
boss, Balance.pacing.depths, and
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
is its toll heard (issue #287). No band checks the spitter duel. The
person's fights get no band either: a section of their own says of each
whether the person won - cleared the room without falling - and in how
many seconds, or how it lost, with its answers and misses (issue #315).
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
ANSWERS = ("mix", "block", "parry", "perfect", "heavy", "whirlwind", "charge", "masher", "skilled",
           "person")
PILOTS = ("charge", "masher", "skilled", "person")
# The pilot that plays like a person (issue #315): reported, not banded
PERSON = "person"


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
# The pacing rooms, and among them the duel rooms with bands: a grunt lead
# alone and a guardian lead alone (Balance.pacing.duel, .guardianDuel); the
# spitter lead's duel (.spitterDuel, issue #315) has none
ROOMS = ("flow", "duel", "guardianduel", "spitterduel", "boss")
DUELS = ("duel", "guardianduel")


def fmt_s(v):
    return "-" if v is None else f"{v:.2f} s"


def describe(r):
    """The report of one fight as lines of text"""
    lines = [f"{r['room']} depth {r['depth']} sword {r['sword']} {r['answer']}: "
             f"{r['outcome']} after {r['seconds']:.2f} s, damage taken {r['damageTaken']}, "
             f"openings {r['openings']}, cancelled charges {r['cancelledCharges']}, "
             f"engaged {r['engagedSeconds']:.2f} s, shots sent back {r.get('shotsBack', 0)} "
             f"({r.get('shotBackHits', 0)} hit)"]
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
        tag = f"{r['room']} depth {r['depth']} sword {r['sword']}"
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
    # The person's fights are reported, never banded (issue #315)
    banded = [r for r in ordered if r["answer"] != PERSON]
    person = person_lines(ordered)
    if person:
        p = ordered[0]["pacing"].get("person", {})
        print(f"\nthe person (reaction {p.get('reaction')} s, misses {p.get('miss')}), not banded: "
              f"a WIN is a fight a person can do")
        for won, line in person:
            print(("WIN  " if won else "LOSE ") + line)
        print(f"the person wins {sum(1 for won, _ in person if won)} of {len(person)} fights")
    if args.check and banded:
        lines = check(banded, banded[0]["pacing"])
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
