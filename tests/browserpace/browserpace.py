#!/usr/bin/env python3
"""Browser pace bench - in Chromium the duel pace chosen in the Esc menu
survives a page reload (issue #362).

    python3 tests/browserpace/browserpace.py <bundle dir> [--out <dir>] [--headed]
                                             [--chromium <executable>] [--timeout 180]

<bundle dir> is the browser game packaging/web-bundle.py wrote (build/web).
The bench serves it with the headers the multithreaded runtime needs and
loads it in a fresh Chromium profile, so nothing of a player's browser is
read or changed. The game, its window's own (src/Main.qml), keeps the pace:
it starts at Standard with nothing stored ("[Game] Duel pace kept:
Standard"). A click on the title's Single Player starts a game, Enter takes the first
special, and after the descent intro Esc opens the menu; W up to Resume
and S three times pick the Duel pace row and D turns it to Deliberate, which the game keeps
("[Game] Duel pace: Deliberate, kept"). Once the browser's store has
written it (window.clayStorage.busy is false) the page reloads, and the
game starts at Deliberate ("[Game] Duel pace kept: Deliberate"). It reads
the game from the console lines it prints, prints one PASS or FAIL line
per check and exits with the number of failures; 100 when the game did not
load. With --out it writes the console and a screenshot after each step
there.

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
        print("[BrowserPace]", "PASS" if ok else "FAIL", what, flush=True)
        if not ok:
            self.failures += 1

    def wait_for(self, text, since, timeout_ms):
        end = time.time() + timeout_ms / 1000
        while time.time() < end:
            if any(text in line for line in self.lines[since:]):
                return True
            self.page.wait_for_timeout(50)
        return False

    def after(self, tag, since):
        return [line.split(tag, 1)[1].strip() for line in self.lines[since:] if tag in line]

    def key(self, name, wait_ms=150):
        self.page.keyboard.press(name)
        self.page.wait_for_timeout(wait_ms)

    def shot(self, name):
        if self.out:
            self.shots += 1
            self.page.screenshot(path=os.path.join(self.out, f"{self.shots:02d}-{name}.png"))

    def loaded(self, since, timeout_s):
        end = time.time() + timeout_s
        while time.time() < end and not any("QML loaded successfully" in line or "QML Error" in line
                                            for line in self.lines[since:]):
            self.page.wait_for_timeout(100)
        errors = [line for line in self.lines[since:] if "QML Error" in line]
        if errors or not any("QML loaded successfully" in line for line in self.lines[since:]):
            print("[BrowserPace] FAIL the game did not load" + (": " + errors[0] if errors else ""), flush=True)
            return False
        return True


def run(bench, timeout_s):
    page = bench.page
    if not bench.loaded(0, timeout_s):
        return 100
    page.wait_for_timeout(3000)
    kept = bench.after("[Game] Duel pace kept:", 0)
    bench.check(kept == ["Standard"], "a fresh browser starts at Standard (" + (" / ".join(kept) or "no line") + ")")
    bench.shot("title")

    # The title's Single Player, at 1280x800; the click gives the page the
    # keys too
    mark = len(bench.lines)
    page.mouse.click(615, 491)
    page.wait_for_timeout(2000)
    bench.check(bench.wait_for("[Game] Starting game", mark, 10000), "a click on Single Player starts a game")
    bench.key("Enter", 500)
    # The descent intro counts two seconds before the menu opens on Esc
    page.wait_for_timeout(4000)
    bench.shot("dungeon")
    # The mouse off the menu, so no row is picked under it
    page.mouse.move(20, 20)
    bench.key("Escape", 500)
    bench.shot("menu")
    mark = len(bench.lines)
    for _ in range(6):
        bench.key("w")
    for _ in range(3):
        bench.key("s")
    bench.key("d", 500)
    set_to = bench.after("[Game] Duel pace:", mark)
    bench.check(set_to == ["Deliberate, kept"],
                "Esc, W up to Resume, S three times and D turn the pace to Deliberate, kept (" + (" / ".join(set_to) or "no line") + ")")
    bench.shot("deliberate")

    # The browser's store writes to IndexedDB after a change
    # (clayground#341); a reload before it is done loses it
    end = time.time() + 10
    busy = True
    while time.time() < end:
        page.wait_for_timeout(200)
        busy = page.evaluate("() => !!(window.clayStorage && window.clayStorage.busy)")
        if not busy:
            break
    page.wait_for_timeout(1000)
    bench.check(not busy, "the browser's store has written the change")

    mark = len(bench.lines)
    page.reload()
    if not bench.loaded(mark, timeout_s):
        return bench.failures + 100
    page.wait_for_timeout(3000)
    kept = bench.after("[Game] Duel pace kept:", mark)
    bench.check(kept == ["Deliberate"], "after a reload the game starts at Deliberate ("
                + (" / ".join(kept) or "no line") + ")")
    bench.shot("reloaded")
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
        print("[BrowserPace] FAIL no Playwright: pip install playwright && python -m playwright install chromium")
        return 100
    bundle = os.path.abspath(args.bundle)
    if not os.path.isfile(os.path.join(bundle, "clayground.wasm")):
        print(f"[BrowserPace] FAIL no clayground.wasm in {bundle} - write the bundle with packaging/web-bundle.py")
        return 100
    if args.out:
        os.makedirs(args.out, exist_ok=True)

    server = Server(("127.0.0.1", 0), functools.partial(Handler, directory=bundle))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    failures = 100
    try:
        with sync_playwright() as pw:
            launch = {"headless": not args.headed}
            if args.chromium:
                launch["executable_path"] = args.chromium
            browser = pw.chromium.launch(**launch)
            page = browser.new_page(viewport={"width": 1280, "height": 800})
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
    print("[BrowserPace] done,", failures, "failed", flush=True)
    return failures


if __name__ == "__main__":
    sys.exit(main())
