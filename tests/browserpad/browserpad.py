#!/usr/bin/env python3
"""Browser pad bench - in Chromium the title's Control Input page takes a pad
on its first press, without a game started first (issue #236).

    python3 tests/browserpad/browserpad.py <bundle dir> [--out <dir>] [--headed]
                                           [--chromium <executable>] [--timeout 180]

<bundle dir> is the browser game packaging/web-bundle.py wrote (build/web).
The bench serves it with the headers the multithreaded runtime needs and
loads it in Chromium with a stand-in for navigator.getGamepads() shaped
like Chrome's real one: four empty slots, a fresh snapshot on every call,
and no pad at all until a button is pressed on it - the pad then appears
in its slot with that press already down, as the press that let the
browser show it. The pad is a Pro Controller in the standard mapping.

On the title a click opens Control Input, the mouse left resting where it
clicked, over the mouse and keyboard column's Reset. The pad's A, its
first press, lists it by name and marks it in use, and chooses nothing on
the page: not that Reset, nor a cell of that column. The D-pad goes up to
the first row and down to Strike, A makes its
gamepad cell wait, Y rebinds it (the draught had Y, so the two trade) - and
no game has started. It reads the page from the console lines it prints
("[ControlInputPage] devices: ...", "[ControlInputPage] prompt: ..."),
prints one PASS or FAIL line per check and exits with the number of
failures; 100 when the game did not load. With --out it writes the
console and a screenshot after each step there.

Needs Playwright with Chromium (pip install playwright && python -m
playwright install chromium); --chromium names another Chromium or Chrome.
"""
import argparse
import functools
import http.server
import os
import sys
import threading
import time

PAD_NAME = "Pro Controller"
PAD_ID = PAD_NAME + " (STANDARD GAMEPAD Vendor: 057e Product: 2009)"
# The standard gamepad's buttons (https://w3c.github.io/gamepad/#remapping)
A, B, X, Y, DPAD_UP, DPAD_DOWN = 0, 1, 2, 3, 12, 13
# The page's rows: 17 actions, the Resets and Back
ROWS = 19

# Chrome's navigator.getGamepads(), driven by window.__padStep(step). A
# step presses or lets go of a button; the first press plugs the pad in.
PAD_JS = r"""
(() => {
  const slots = [null, null, null, null];
  const snapshot = p => p && {
    id: p.id, index: p.index, connected: true, mapping: "standard", timestamp: p.timestamp,
    axes: p.axes.slice(),
    buttons: p.buttons.map(b => ({pressed: b.pressed, touched: b.touched, value: b.value})),
  };
  navigator.getGamepads = () => slots.map(snapshot);
  window.__padStep = (step) => {
    const i = step.slot || 0;
    if (!slots[i]) {
      if (!step.value) return;
      slots[i] = {id: step.id, index: i, timestamp: 0, axes: [0, 0, 0, 0],
                  buttons: Array.from({length: 17}, () => ({pressed: false, touched: false, value: 0}))};
    }
    const v = step.value;
    slots[i].buttons[step.button] = {pressed: v > 0, touched: v > 0, value: v};
    slots[i].timestamp = performance.now();
  };
})();
"""


class Handler(http.server.SimpleHTTPRequestHandler):
    """Static files with the COOP/COEP headers multithreaded WASM needs."""

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, *args):
        pass


class Server(http.server.ThreadingHTTPServer):
    # The runtime fetches every QML file of the game at once; the default
    # backlog of 5 resets some of them, and the game does not load
    request_queue_size = 128


class Bench:
    def __init__(self, page, out):
        self.page = page
        self.out = out
        self.lines = []
        self.failures = 0
        self.shots = 0
        page.on("console", lambda m: self.lines.append(m.text))

    def check(self, ok, what):
        print("[BrowserPad]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            self.failures += 1

    def wait_for(self, text, since, timeout_ms):
        end = time.time() + timeout_ms / 1000
        while time.time() < end:
            if any(text in line for line in self.lines[since:]):
                return True
            self.page.wait_for_timeout(50)
        return False

    def page_lines(self, kind, since):
        tag = "[ControlInputPage] " + kind + ":"
        return [line.split(tag, 1)[1].strip() for line in self.lines[since:] if tag in line]

    def press(self, button):
        self.page.evaluate("s => window.__padStep(s)", {"id": PAD_ID, "button": button, "value": 1})
        self.page.wait_for_timeout(100)
        self.page.evaluate("s => window.__padStep(s)", {"id": PAD_ID, "button": button, "value": 0})
        self.page.wait_for_timeout(250)

    def shot(self, name):
        if self.out:
            self.shots += 1
            self.page.screenshot(path=os.path.join(self.out, f"{self.shots:02d}-{name}.png"))


def run(bench, timeout_s):
    page = bench.page
    end = time.time() + timeout_s
    while time.time() < end and not any("QML loaded successfully" in line or "QML Error" in line
                                        for line in bench.lines):
        page.wait_for_timeout(100)
    errors = [line for line in bench.lines if "QML Error" in line]
    if errors or not any("QML loaded successfully" in line for line in bench.lines):
        print("[BrowserPad] FAIL the game did not load" + (": " + errors[0] if errors else ""), flush=True)
        return 100
    page.wait_for_timeout(3000)
    bench.shot("title")

    # The title's Control Input row, at 1280x800
    mark = len(bench.lines)
    page.mouse.click(640, 687)
    bench.check(bench.wait_for("[ControlInputPage] devices:", mark, 5000),
                "a click on Control Input opens the page over the title")
    page.wait_for_timeout(500)
    devices = bench.page_lines("devices", mark)
    bench.check(bool(devices) and PAD_NAME not in devices[-1],
                "before a press the browser lists no pad (" + (devices[-1] if devices else "no line") + ")")
    bench.shot("page")

    # The pad's first press: it appears with A down
    mark = len(bench.lines)
    bench.press(A)
    page.wait_for_timeout(300)
    devices = bench.page_lines("devices", mark)
    bench.check(bool(devices) and PAD_NAME + " (in use)" in devices[-1],
                "the first press lists the pad by name, in use (" + (devices[-1] if devices else "no line") + ")")
    prompts = bench.page_lines("prompt", mark)
    bench.check(not prompts,
                "that press only takes the pad: it chooses nothing on the page, not the cell or Reset"
                " of the mouse and keyboard column under the resting mouse (" + (" / ".join(prompts) or "no prompt") + ")")
    bench.shot("first-press")

    # The D-pad up to the first row, down to Strike, A, then Y
    mark = len(bench.lines)
    for _ in range(ROWS):
        bench.press(DPAD_UP)
    for _ in range(5):
        bench.press(DPAD_DOWN)
    bench.press(A)
    prompts = bench.page_lines("prompt", mark)
    bench.check(bool(prompts) and prompts[-1] == "Press a gamepad button for Strike",
                "the D-pad up to the top, down to Strike, and A make its gamepad cell wait (" + (" / ".join(prompts) or "no prompt") + ")")
    bench.shot("waiting")
    mark = len(bench.lines)
    bench.press(Y)
    prompts = bench.page_lines("prompt", mark)
    bench.check(bool(prompts) and prompts[-1] == "Strike swapped with Draught",
                "Y rebinds it; the draught had Y and gets R1 (" + (" / ".join(prompts) or "no prompt") + ")")
    bench.shot("rebound")

    started = [line for line in bench.lines if "[Game] New run" in line or "Spawning player" in line]
    bench.check(not started, "no game was started" + (" (" + started[0] + ")" if started else ""))
    return bench.failures


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    ap.add_argument("bundle", help="the browser game packaging/web-bundle.py wrote")
    ap.add_argument("--out", default="", help="write the console and screenshots here")
    ap.add_argument("--headed", action="store_true", help="show the browser window")
    ap.add_argument("--chromium", default="", help="the Chromium or Chrome to run")
    ap.add_argument("--timeout", type=float, default=180, help="seconds the game may take to load")
    args = ap.parse_args()
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("[BrowserPad] FAIL no Playwright: pip install playwright && python -m playwright install chromium")
        return 100
    bundle = os.path.abspath(args.bundle)
    if not os.path.isfile(os.path.join(bundle, "clayground.wasm")):
        print(f"[BrowserPad] FAIL no clayground.wasm in {bundle} - write the bundle with packaging/web-bundle.py")
        return 100
    if args.out:
        os.makedirs(args.out, exist_ok=True)

    server = Server(("127.0.0.1", 0), functools.partial(Handler, directory=bundle))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with sync_playwright() as pw:
            launch = {"headless": not args.headed}
            if args.chromium:
                launch["executable_path"] = args.chromium
            browser = pw.chromium.launch(**launch)
            page = browser.new_page(viewport={"width": 1280, "height": 800})
            page.add_init_script(PAD_JS)
            bench = Bench(page, args.out)
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
    print("[BrowserPad] done,", failures, "failed", flush=True)
    return failures


if __name__ == "__main__":
    sys.exit(main())
