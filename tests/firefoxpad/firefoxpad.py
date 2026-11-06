#!/usr/bin/env python3
"""Firefox pad bench - in Firefox the Control Input page lists a pad
Firefox reads cleanly by name and the pad drives the page; a Switch pad
Firefox misreads stays listed with no input (issue #240).

    python3 tests/firefoxpad/firefoxpad.py <bundle dir> [--out <dir>] [--headed]
                                           [--firefox <executable>] [--timeout 180]

<bundle dir> is the browser game packaging/web-bundle.py wrote (build/web),
on a Clayground runtime from v2026.11.1 on: before it, Firefox listed every
pad with no input (clayground#474). The bench serves it as
tests/browserpad does and loads it in Playwright's Firefox with the same
stand-in for navigator.getGamepads(), the pads named as Firefox names them,
"<vendor>-<product>-<name>".

On the title a click opens Control Input. An Xbox Wireless Controller's
first press lists it by name, in use, without "no input in this browser";
its next A makes Strike's gamepad cell wait, and its B cancels that - the
pad drives the page. Then a Pro Controller's press lists it beside: on
macOS and Windows Firefox misreads that Switch pad, so the runtime lists
it with no input and the row says so; on Linux the kernel reads it first,
and it is listed clean. The bench reads the page from the console lines it
prints ("[ControlInputPage] devices: ...", "[ControlInputPage] prompt: ..."),
prints one PASS or FAIL line per check and exits with the number of
failures; 100 when the game did not load. With --out it writes the console
and a screenshot after each step there.

Needs Playwright with Firefox (pip install playwright && python -m
playwright install firefox); --firefox names another Firefox.
"""
import argparse
import functools
import os
import sys
import threading
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "browserpad"))
from browserpad import PAD_JS, Bench, Handler, Server  # noqa: E402

XBOX_NAME = "Xbox Wireless Controller"
XBOX_ID = "045e-02ea-" + XBOX_NAME
PRO_NAME = "Pro Controller"
PRO_ID = "057e-2009-" + PRO_NAME
NO_INPUT = " - no input in this browser"
# The standard gamepad's buttons (https://w3c.github.io/gamepad/#remapping),
# by position as an Xbox pad names them
A, B = 0, 1


class FirefoxBench(Bench):
    def check(self, ok, what):
        print("[FirefoxPad]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            self.failures += 1


def press(bench, pad_id, slot, button):
    page = bench.page
    page.evaluate("s => window.__padStep(s)", {"id": pad_id, "slot": slot, "button": button, "value": 1})
    page.wait_for_timeout(100)
    page.evaluate("s => window.__padStep(s)", {"id": pad_id, "slot": slot, "button": button, "value": 0})
    page.wait_for_timeout(250)


def run(bench, timeout_s):
    page = bench.page
    end = time.time() + timeout_s
    while time.time() < end and not any("QML loaded successfully" in line or "QML Error" in line
                                        for line in bench.lines):
        page.wait_for_timeout(100)
    errors = [line for line in bench.lines if "QML Error" in line]
    if errors or not any("QML loaded successfully" in line for line in bench.lines):
        print("[FirefoxPad] FAIL the game did not load" + (": " + errors[0] if errors else ""), flush=True)
        return 100
    page.wait_for_timeout(3000)
    bench.shot("title")
    agent = page.evaluate("navigator.userAgent")
    print("[FirefoxPad] user agent:", agent, flush=True)

    # The title's Control Input row, at 1280x800, where the page's mouse and
    # keyboard Reset will be under the resting mouse
    mark = len(bench.lines)
    page.mouse.click(640, 675)
    bench.check(bench.wait_for("[ControlInputPage] devices:", mark, 5000),
                "a click on Control Input opens the page over the title")
    page.wait_for_timeout(500)
    bench.shot("page")

    # The Xbox pad's first press lists it, clean, in use
    mark = len(bench.lines)
    press(bench, XBOX_ID, 0, A)
    page.wait_for_timeout(300)
    devices = bench.page_lines("devices", mark)
    row = devices[-1] if devices else "no line"
    bench.check(bool(devices) and XBOX_NAME + " (in use)" in row and NO_INPUT not in row,
                "the Xbox pad's first press lists it by name, in use, with its input read (" + row + ")")
    bench.shot("xbox")

    # It drives the page: A makes Strike's gamepad cell wait, B cancels
    mark = len(bench.lines)
    press(bench, XBOX_ID, 0, A)
    prompts = bench.page_lines("prompt", mark)
    bench.check(bool(prompts) and prompts[-1] == "Press a gamepad button for Strike",
                "its next A makes Strike's gamepad cell wait (" + (" / ".join(prompts) or "no prompt") + ")")
    mark = len(bench.lines)
    press(bench, XBOX_ID, 0, B)
    prompts = bench.page_lines("prompt", mark)
    bench.check(bool(prompts) and prompts[-1] == "Strike kept as it was",
                "its B cancels the waiting cell (" + (" / ".join(prompts) or "no prompt") + ")")
    bench.shot("xbox-drives")

    # A Pro Controller beside it: misread by Firefox on macOS and Windows
    misread = "Macintosh" in agent or "Windows" in agent
    mark = len(bench.lines)
    press(bench, PRO_ID, 1, A)
    page.wait_for_timeout(300)
    devices = bench.page_lines("devices", mark)
    row = devices[-1] if devices else "no line"
    if misread:
        bench.check(PRO_NAME + NO_INPUT in row,
                    "a Pro Controller, which Firefox misreads here, is listed with no input (" + row + ")")
    else:
        bench.check(PRO_NAME in row and NO_INPUT not in row,
                    "a Pro Controller, which the kernel reads here, is listed clean (" + row + ")")
    bench.check(XBOX_NAME in row and XBOX_NAME + NO_INPUT not in row,
                "the Xbox pad stays listed with its input read (" + row + ")")
    bench.shot("pro")
    return bench.failures


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    ap.add_argument("bundle", help="the browser game packaging/web-bundle.py wrote")
    ap.add_argument("--out", default="", help="write the console and screenshots here")
    ap.add_argument("--headed", action="store_true", help="show the browser window")
    ap.add_argument("--firefox", default="", help="the Firefox to run")
    ap.add_argument("--timeout", type=float, default=180, help="seconds the game may take to load")
    args = ap.parse_args()
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("[FirefoxPad] FAIL no Playwright: pip install playwright && python -m playwright install firefox")
        return 100
    bundle = os.path.abspath(args.bundle)
    if not os.path.isfile(os.path.join(bundle, "clayground.wasm")):
        print(f"[FirefoxPad] FAIL no clayground.wasm in {bundle} - write the bundle with packaging/web-bundle.py")
        return 100
    if args.out:
        os.makedirs(args.out, exist_ok=True)

    server = Server(("127.0.0.1", 0), functools.partial(Handler, directory=bundle))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with sync_playwright() as pw:
            launch = {"headless": not args.headed}
            if args.firefox:
                launch["executable_path"] = args.firefox
            browser = pw.firefox.launch(**launch)
            page = browser.new_page(viewport={"width": 1280, "height": 800})
            page.add_init_script(PAD_JS)
            bench = FirefoxBench(page, args.out)
            page.goto(f"http://127.0.0.1:{server.server_address[1]}/index.html")
            try:
                failures = run(bench, args.timeout)
            finally:
                if args.out:
                    with open(os.path.join(args.out, "console.log"), "w", encoding="utf-8") as f:
                        f.write("\n".join(bench.lines) + "\n")
                browser.close()
    finally:
        server.shutdown()
    print("[FirefoxPad] done,", failures, "failed", flush=True)
    return failures


if __name__ == "__main__":
    sys.exit(main())
