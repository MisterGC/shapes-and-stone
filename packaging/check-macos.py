#!/usr/bin/env python3
"""Fails when the packaged app would load anything from outside itself.

check-macos.py <app>

Every Mach-O file in the app may link only to the app itself (@rpath,
@executable_path, @loader_path) and to the system (/System, /usr/lib), and
may carry no rpath outside the app. Prints each offender and exits with
their number.
"""

import os
import subprocess
import sys

app = os.path.abspath(sys.argv[1])
system = ("@", "/System/", "/usr/lib/")
offenders = []
count = 0
for root, _, files in os.walk(app):
    for name in files:
        path = os.path.join(root, name)
        if os.path.islink(path):
            continue
        with open(path, "rb") as f:
            if f.read(4) not in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe"):
                continue
        count += 1
        rel = os.path.relpath(path, app)
        links = subprocess.run(["otool", "-L", path], capture_output=True,
                               text=True, check=True).stdout.splitlines()[1:]
        for line in links:
            dep = line.strip().rsplit(" (", 1)[0]
            if not dep.startswith(system) and not dep.startswith(app):
                offenders.append(f"{rel} links to {dep}")
        commands = subprocess.run(["otool", "-l", path], capture_output=True,
                                  text=True, check=True).stdout.splitlines()
        for i, line in enumerate(commands):
            if "LC_RPATH" in line:
                rpath = commands[i + 2].split()[1]
                if not rpath.startswith("@"):
                    offenders.append(f"{rel} has rpath {rpath}")

for o in offenders:
    print("FAIL", o)
print(f"{count} binaries, {len(offenders)} reach outside the app")
sys.exit(len(offenders))
