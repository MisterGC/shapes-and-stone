#!/usr/bin/env python3
"""Builds the browser game: the files a static host (GitHub Pages) serves.

    python3 packaging/web-bundle.py --runtime <starter dir or zip> [--out build/web] [--check]

The bundle is Clayground's Web Runtime starter (clayground-starter.zip of a
Clayground release, or <wasm build>/clayground-starter) with the game's src/
in place of the starter's Main.qml: the QML, the qmldir, assets/ and the
shaders baked to .qsb by Qt's qsb, for the same targets as the native build
(CMakeLists.txt). assets-manifest.json lists the .qsb only: the runtime reads
a shader from its in-memory file system, but fetches images and sounds by
their URL, so preloading assets/ would download them twice.

--check runs Clayground's run_in_browser.py on the written files in headless
Chromium and exits with its code: 0 = the game loaded to the title without a
QML, shader or WebGL error. It needs Playwright with Chromium.
"""
import argparse
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "src")
WEBDOJO = os.path.join(ROOT, "clayground", "tools", "webdojo")
# The starter's own sample game and its notes for a new game are not ours.
STARTER_SKIP = {"Main.qml", "README.md", "make-assets-manifest.py"}
# As qt_add_shaders() in CMakeLists.txt; WebGL2 needs GLSL 300 es.
QSB_ARGS = ["--glsl", "100 es,120,150,300 es", "--hlsl", "50", "--msl", "12"]


def find_qsb(given):
    candidates = [given, shutil.which("qsb")]
    for env in ("QT_HOST_PATH", "QT_ROOT_DIR"):
        if os.environ.get(env):
            candidates.append(os.path.join(os.environ[env], "bin", "qsb"))
    for c in candidates:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return None


def copy_runtime(runtime, out):
    if os.path.isdir(runtime):
        for name in os.listdir(runtime):
            if name in STARTER_SKIP:
                continue
            src = os.path.join(runtime, name)
            dst = os.path.join(out, name)
            if os.path.isdir(src):
                shutil.copytree(src, dst)
            else:
                shutil.copy2(src, dst)
    else:
        with zipfile.ZipFile(runtime) as z:
            for info in z.infolist():
                top = info.filename.split("/", 1)[0]
                if top not in STARTER_SKIP:
                    z.extract(info, out)
    if not os.path.isfile(os.path.join(out, "clayground.wasm")):
        raise SystemExit(f"no clayground.wasm in {runtime} - not a starter bundle")


def name_page(out):
    # The starter's page is titled for a sample game; the tab says ours.
    path = os.path.join(out, "index.html")
    with open(path, encoding="utf-8") as f:
        html = f.read()
    html = re.sub(r"<title>.*?</title>", "<title>Shapes &amp; Stone</title>", html, count=1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)


def copy_game(out):
    for name in os.listdir(SRC):
        src = os.path.join(SRC, name)
        if name.startswith("."):
            continue
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(out, name),
                            ignore=shutil.ignore_patterns(".*", "*.qsb"))
        else:
            shutil.copy2(src, os.path.join(out, name))


def bake_shaders(qsb, out):
    baked = []
    shaders = os.path.join(out, "shaders")
    for name in sorted(os.listdir(shaders)):
        if not name.endswith((".frag", ".vert")):
            continue
        src = os.path.join(shaders, name)
        rc = subprocess.call([qsb, *QSB_ARGS, "-o", src + ".qsb", src])
        if rc != 0:
            raise SystemExit(f"qsb failed on {name} (exit {rc})")
        baked.append(f"shaders/{name}.qsb")
    return baked


def load_manifest_module():
    path = os.path.join(WEBDOJO, "appshell", "make-assets-manifest.py")
    spec = importlib.util.spec_from_file_location("make_assets_manifest", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def check(out, steps):
    # run_in_browser.py serves the runtime from <build-dir>/clayground-starter
    # and the game from its game dir; here both are the bundle.
    with tempfile.TemporaryDirectory() as build_dir:
        os.symlink(out, os.path.join(build_dir, "clayground-starter"))
        cmd = [sys.executable, os.path.join(WEBDOJO, "run_in_browser.py"), out,
               "--build-dir", build_dir, "--out", out + "-check"]
        for s in steps:
            cmd += ["--do", s]
        print(" ".join(cmd), flush=True)
        return subprocess.call(cmd)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0],
                                 epilog="Details: see the module docstring.")
    ap.add_argument("--runtime", required=True,
                    help="Web Runtime starter: clayground-starter.zip or its unpacked folder")
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "web"),
                    help="output folder, emptied first (default: build/web)")
    ap.add_argument("--qsb", default="", help="Qt's qsb (default: PATH, $QT_HOST_PATH/bin, $QT_ROOT_DIR/bin)")
    ap.add_argument("--check", action="store_true",
                    help="load the written files in headless Chromium (run_in_browser.py)")
    ap.add_argument("--do", action="append", default=[], metavar="STEP",
                    help="run_in_browser.py step for --check, repeatable")
    args = ap.parse_args()

    qsb = find_qsb(args.qsb)
    if not qsb:
        print("qsb not found - pass --qsb <Qt>/macos/bin/qsb or set QT_HOST_PATH")
        return 2
    out = os.path.abspath(args.out)
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)

    copy_runtime(os.path.abspath(args.runtime), out)
    name_page(out)
    copy_game(out)
    baked = bake_shaders(qsb, out)
    files = load_manifest_module().collect(out, [])
    with open(os.path.join(out, "assets-manifest.json"), "w", encoding="utf-8") as f:
        json.dump(files, f, indent=0)
        f.write("\n")
    with open(os.path.join(out, "RUNTIME-MANIFEST.json")) as f:
        runtime = json.load(f)
    print(f"{out}: runtime {runtime.get('version', '?')}, {len(baked)} shader(s) baked, "
          f"assets-manifest.json lists {len(files)} file(s)")
    if args.check:
        return check(out, args.do or ["wait:6000", "shot:title"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
