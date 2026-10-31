#!/usr/bin/env python3
"""Quick benches - every bench that finishes in about 30 s offscreen, one
after the other, as CI runs them on every push (issue #211).

Each bench is a QML file under tests/ that prints one PASS or FAIL line per
check and exits with the number of failures. This starts each with qml,
offscreen, and fails a bench that exits non-zero or runs past --timeout.
The benches left out - networked, windowed or slow - are listed in the
README with how to run them.

Usage:
  run_quick.py [--qml <qml>] [--import <dir>] [--timeout 120] [--only <name>...]

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
    ("impacts", "impacts/impacts.qml", []),
    ("enemies", "enemies/enemies.qml", []),
    ("wallpush", "wallpush/wallpush.qml", []),
    ("sound", "sound/sound.qml", []),
    ("pause", "pause/pause.qml", []),
    ("fallen", "fallen/fallen.qml", []),
    ("focus", "focus/focus.qml", []),
    ("gamepad", "gamepad/gamepad.qml", []),
    ("downed", "downed/downed.qml", []),
    ("joinleave", "joinleave/joinleave.qml", []),
    ("gold", "gold/gold.qml", []),
    ("dialogue", "dialogue/dialogue.qml", []),
    ("camp", "camp/camp.qml", []),
    ("camps", "camps/camps.qml", []),
    ("sit", "sit/sit.qml", []),
    ("campsound", "campsound/campsound.qml", []),
    ("moths", "moths/moths.qml", []),
    ("cat", "cat/cat.qml", []),
    ("fishing", "fishing/fishing.qml", []),
    ("depth first", "depth/depth.qml", ["first"]),
    ("depth second", "depth/depth.qml", ["second"]),
    ("record", "record/record.qml", []),
    ("balance", "balance/balance.qml", []),
    ("partysize", "partysize/partysize.qml", []),
    ("danger", "danger/danger.qml", []),
    ("loops", "loops/loops.qml", []),
    ("spikes", "spikes/spikes.qml", []),
    ("deep", "deep/deep.qml", []),
    ("dungeonmaster", "dungeonmaster/dungeonmaster.qml", []),
    ("clock", "clock/clock.qml", []),
    ("hitstop", "hitstop/hitstop.qml", []),
    ("answer", "answer/answer.qml", []),
    ("settings", "settings/settings.qml", []),
    ("cues", "cues/cues.qml", []),
    ("lipsync", "lipsync/lipsync.qml", []),
    ("fightmusic", "fightmusic/fightmusic.qml", []),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--qml", help="path to Qt's qml tool")
    ap.add_argument("--import", dest="imports", default=os.path.join(REPO, "build", "bin", "qml"),
                    help="the build's QML import dir")
    ap.add_argument("--timeout", type=float, default=120, help="seconds a bench may take")
    ap.add_argument("--only", nargs="+", metavar="NAME", help="run these benches alone")
    args = ap.parse_args()

    qml = args.qml or shutil.which("qml")
    if not qml:
        print("FAIL no qml: pass --qml or put Qt's bin dir on PATH", file=sys.stderr)
        sys.exit(100)
    benches = [b for b in QUICK if not args.only or b[0] in args.only]
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
