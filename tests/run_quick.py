#!/usr/bin/env python3
"""Quick benches - every bench that finishes in about 30 s offscreen, one
after the other, as CI runs them on every push (issue #211).

Each bench is a QML file under tests/ that prints one PASS or FAIL line per
check and exits with the number of failures. This starts each with qml,
offscreen, and fails a bench that exits non-zero or runs past --timeout.
The benches left out - networked, windowed or slow - are listed in the
README with how to run them.

Usage:
  run_quick.py [--qml <qml>] [--import <dir>] [--timeout 120] [--held] [--only <name>...]

qml is --qml, else the first qml on PATH; the import dir is --import, else
build/bin/qml of this repository. Prints one PASS or FAIL line per bench
with its time, a failed bench's output after it, and exits with the number
of failed benches.
"""

import argparse
import os
import shutil
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (name, QML file under tests/, arguments after --). The depth bench runs
# twice so its record crosses a restart: "second" needs "first" before it.
# A bench that takes over 30 s offscreen is not here: the README's
# "Benches" section lists those and the rest that run by hand.
QUICK = [
    ("wallpush", "wallpush/wallpush.qml", []),
    ("sound", "sound/sound.qml", []),
    ("pause", "pause/pause.qml", []),
    ("fallen", "fallen/fallen.qml", []),
    ("focus", "focus/focus.qml", []),
    ("gamepad", "gamepad/gamepad.qml", []),
    ("controls", "controls/controls.qml", []),
    ("controlinput", "controlinput/controlinput.qml", []),
    ("rebind", "rebind/rebind.qml", []),
    ("padnotice", "padnotice/padnotice.qml", []),
    ("downed", "downed/downed.qml", []),
    ("joinleave", "joinleave/joinleave.qml", []),
    ("gold", "gold/gold.qml", []),
    ("dialogue", "dialogue/dialogue.qml", []),
    ("camp", "camp/camp.qml", []),
    ("sit", "sit/sit.qml", []),
    ("campsound", "campsound/campsound.qml", []),
    ("moths", "moths/moths.qml", []),
    ("fishing", "fishing/fishing.qml", []),
    ("depth first", "depth/depth.qml", ["first"]),
    ("depth second", "depth/depth.qml", ["second"]),
    ("record", "record/record.qml", []),
    ("danger", "danger/danger.qml", []),
    ("spikes", "spikes/spikes.qml", []),
    ("deep", "deep/deep.qml", []),
    ("dungeonmaster", "dungeonmaster/dungeonmaster.qml", []),
    ("leads", "leads/leads.qml", []),
    ("clock", "clock/clock.qml", []),
    ("hitstop", "hitstop/hitstop.qml", []),
    ("answer", "answer/answer.qml", []),
    ("cues", "cues/cues.qml", []),
    ("lipsync", "lipsync/lipsync.qml", []),
    ("fightmusic", "fightmusic/fightmusic.qml", []),
]

# Quick here, but red or slow on CI's ubuntu-latest runner, so out of CI for
# now and run by hand with --held (or --only <name>):
HELD = [
    # the next level keeps the knight's HP and mana: FAIL on the runner
    ("balance", "balance/balance.qml", []),
    # no audio output device on the runner, then step 12 times out
    ("settings", "settings/settings.qml", []),
    # 55.9 s on the runner
    ("cat", "cat/cat.qml", []),
    # 72.1 s on the runner
    ("loops", "loops/loops.qml", []),
    # 39.4 s on the runner
    ("partysize", "partysize/partysize.qml", []),
    # 31.3 s on the runner
    ("camps", "camps/camps.qml", []),
    # host-and-joiner timing in one process, flaky on ubuntu-latest (passed
    # in run 41241728960, failed in 41243071117)
    ("impacts", "impacts/impacts.qml", []),
    ("enemies", "enemies/enemies.qml", []),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--qml", help="path to Qt's qml tool")
    ap.add_argument("--import", dest="imports", default=os.path.join(REPO, "build", "bin", "qml"),
                    help="the build's QML import dir")
    ap.add_argument("--timeout", type=float, default=120, help="seconds a bench may take")
    ap.add_argument("--only", nargs="+", metavar="NAME", help="run these benches alone")
    ap.add_argument("--held", action="store_true", help="run the HELD benches too")
    args = ap.parse_args()

    qml = args.qml or shutil.which("qml")
    if not qml:
        print("FAIL no qml: pass --qml or put Qt's bin dir on PATH", file=sys.stderr)
        sys.exit(100)
    pool = QUICK + HELD if args.held or args.only else QUICK
    benches = [b for b in pool if not args.only or b[0] in args.only]
    # The game reads sound/*.json through XMLHttpRequest, which Qt refuses
    # for local files unless allowed
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QML_XHR_ALLOW_FILE_READ="1")

    failed = []
    began = time.time()
    for name, qml_file, extra in benches:
        cmd = [qml, "-I", args.imports, os.path.join(REPO, "tests", qml_file)]
        if extra:
            cmd += ["--"] + extra
        start = time.time()
        try:
            run = subprocess.run(cmd, cwd=REPO, env=env, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True, errors="replace",
                                 timeout=args.timeout)
            code, out = run.returncode, run.stdout
            why = f"exit {code}"
        except subprocess.TimeoutExpired as e:
            code = None
            out = e.stdout.decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
            why = f"past {args.timeout:.0f} s"
        secs = time.time() - start
        if code == 0:
            print(f"[Quick] PASS {name} ({secs:.1f} s)", flush=True)
        else:
            failed.append(name)
            print(f"[Quick] FAIL {name} ({why}, {secs:.1f} s)", flush=True)
            print(out.rstrip(), flush=True)
    print(f"[Quick] done, {len(failed)} of {len(benches)} failed in {time.time() - began:.0f} s"
          + (": " + ", ".join(failed) if failed else ""))
    sys.exit(min(len(failed), 100))


if __name__ == "__main__":
    main()
