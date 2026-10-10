// Record bench - the deepest descent is the record everyone sees, and
// passing it is a moment (issue #101).
//
// Puts a record of depth 2 by "Ana" into the bench's store and names this
// machine's knight "Bo". The title and the HUD show the record. A first run
// goes down to depth 2, the record's depth, and falls there: no banner,
// the record stays Ana's. A second run goes down to depth 4: on the step
// depth 3 passes the record the banner goes up, once, the record becomes
// Bo's depth 3 at once and depth 4 as the run gets there, and the fall
// says "New record". A third run that falls short raises none. Each fall
// lists the runs so far with depth and time, newest first. With an out
// dir it saves the title, the HUD with the banner up and the last fall
// screen as title.png, hud.png and fallen.png; offscreen the dungeon
// behind the HUD is not drawn. Prints one PASS or FAIL line per check and
// exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/record/record.qml
//   qml -I <build>/bin/qml tests/record/record.qml -- <out dir>

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Storage

Window {
    id: bench
    width: 1000
    height: 700
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0
    readonly property var args: Qt.application.arguments
    readonly property string outDir: args.indexOf("--") >= 0 && args.indexOf("--") < args.length - 1
                                     ? args[args.length - 1] : ""

    // The same store the game keeps its record in, under the bench's name,
    // so the player's own record is not touched
    readonly property string storeName: "ShapesAndStoneRecordBench"
    KeyValueStore { id: store; name: bench.storeName }
    readonly property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")

    function check(ok, what) {
        console.log("[Record]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    // Every banner the game raised, with the depth it was at and the run
    property var banners: []
    property int run: 0

    Component.onCompleted: {
        store.remove("bestDepth")
        store.set("record", JSON.stringify({depth: 2, names: ["Ana"], date: "2026-10-01"}))
        store.set("playerName", "Bo")
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Record] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                  recordStoreName: storeName})
        if (game.recordBanner === undefined) {
            check(false, "the game raises a banner for a new record (no recordBanner signal)")
            script.i = runSteps.length
        } else {
            game.recordBanner.connect(d => banners.push({depth: d, run: run}))
        }
        script.start()
    }

    function find(root, name) {
        if (!root) return null
        if (root.objectName === name) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = find(kids[i], name)
            if (f) return f
        }
        return null
    }
    function findAll(root, name, out) {
        out = out || []
        if (!root) return out
        if (root.objectName === name) out.push(root)
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) findAll(kids[i], name, out)
        return out
    }
    function fallenScreen() {
        let f = find(game, "fallenScreen")
        return f && f.visible ? f : null
    }
    function text(root, name) {
        let t = find(root, name)
        return t ? t.text : "none"
    }
    // The runs the fallen screen lists, top to bottom
    function runLines() {
        return findAll(fallenScreen(), "fallenRun").filter(t => t.visible).map(t => t.text)
    }
    function stored() {
        try { return JSON.parse(store.get("record", "null")) } catch (err) { return null }
    }
    function bannerUp() { return find(game, "recordBanner").opacity > 0 }
    function hudRecord() { return text(game, "gaugeRecord") }
    // Down to a dungeon at depth d, through the village before it
    function descend(d) {
        game.levelIndex = game.levelIndexOf(d - 1, "village")
        game.levelIndex = game.levelIndexOf(d, "dungeon")
    }
    function strikeDown() {
        let p = game.player
        p.isBlocking = false
        p.takeDamage(10 * p.maxHp, p.xWu + 1, p.yWu)
    }

    property bool saved: false
    function capture(name) {
        saved = outDir === ""
        if (saved) return
        bench.contentItem.grabToImage(r => {
            check(r.saveToFile(outDir + "/" + name + ".png"), "saved " + name + ".png")
            saved = true
        })
    }

    property var runSteps: [
        [() => game.screen === "title" && find(game, "titleRecord") !== null, () => {
            check(text(game, "titleRecord") === "Record 2  •  Ana  •  2026-10-01",
                  "the title shows the stored record (" + text(game, "titleRecord") + ")")
            capture("title")
        }],
        [() => saved, () => {
            run = 1
            game.screen = "game"
            game.forceActiveFocus()
        }],
        // Run 1: down to the record's depth, not past it
        [() => game.player && game.enemies.length > 0, () => {
            check(hudRecord() === "record 2", "the HUD shows \"record 2\" beside the depth (" + hudRecord() + ")")
            descend(1)
            descend(2)
            check(banners.length === 0, "reaching the record's depth 2 raises no banner (" + banners.length + ")")
        }],
        [500, () => {
            check(!bannerUp(), "no banner over the dungeon at the record's depth")
            strikeDown()
        }],
        [() => fallenScreen() !== null, () => {
            let s = stored()
            check(s && s.depth === 2 && s.names.join() === "Ana" && s.date === "2026-10-01",
                  "a run that does not pass the record leaves it as it was (" + JSON.stringify(s) + ")")
            check(text(fallenScreen(), "fallenRecord") === "Record 2  •  Ana  •  2026-10-01",
                  "the fall screen shows the record (" + text(fallenScreen(), "fallenRecord") + ")")
            let lines = runLines()
            check(lines.length === 1 && /^Run 1  •  Depth 2  •  0:\d\d$/.test(lines[0]),
                  "the fall screen lists the one run of the session (" + lines.join(" | ") + ")")
            run = 2
            press(Qt.Key_Return)
        }],
        // Run 2: past the record
        [() => game.player && !game.fallen && game.enemies.length > 0, () => {
            descend(1)
            descend(2)
            check(banners.length === 0, "run 2: no banner down to depth 2 (" + banners.length + ")")
            game.levelIndex = game.levelIndexOf(2, "village")
            game.levelIndex = game.levelIndexOf(3, "dungeon")
            // Checked in the same step, before any frame
            check(banners.length === 1 && banners[0].depth === 3,
                  "the banner goes up on the step depth 3 passes the record (" + JSON.stringify(banners) + ")")
            let s = stored()
            check(s && s.depth === 3 && s.names.join() === "Bo" && s.date === today,
                  "depth 3 is stored at once with the knight's name and today (" + JSON.stringify(s) + ")")
            check(store.get("bestDepth", "none") === "3", "the best depth alone is 3 too")
        }],
        // Captured once it has faded in
        [() => find(game, "recordBanner").opacity >= 1, () => {
            check(text(find(game, "recordBanner"), "recordBanner") === "New record", "the banner says \"New record\"")
            check(hudRecord() === "record 3", "the HUD's record follows to 3 (" + hudRecord() + ")")
            capture("hud")
        }],
        [() => saved, () => {
            descend(4)
            check(banners.length === 1, "going deeper still raises no second banner (" + banners.length + ")")
            let s = stored()
            check(s && s.depth === 4 && s.names.join() === "Bo", "depth 4 is stored as the run gets there ("
                  + JSON.stringify(s) + ")")
        }],
        [() => !bannerUp(), () => {
            check(true, "the banner is gone again")
            strikeDown()
        }],
        [() => fallenScreen() !== null, () => {
            check(text(fallenScreen(), "fallenRecord") === "New record",
                  "the fall screen says \"New record\" (" + text(fallenScreen(), "fallenRecord") + ")")
            let lines = runLines()
            check(lines.length === 2 && /^Run 2  •  Depth 4  •  0:\d\d$/.test(lines[0])
                  && /^Run 1  •  Depth 2  •  0:\d\d$/.test(lines[1]),
                  "the fall screen lists both runs, newest first (" + lines.join(" | ") + ")")
            run = 3
            press(Qt.Key_Return)
        }],
        // Run 3: short of the new record
        [() => game.player && !game.fallen && game.enemies.length > 0, () => {
            check(hudRecord() === "record 4", "the next run's HUD shows \"record 4\" (" + hudRecord() + ")")
            descend(1)
            descend(2)
            descend(3)
            check(banners.length === 1, "a run that stays above depth 4 raises none ("
                  + banners.filter(b => b.run === 3).length + " in run 3)")
            strikeDown()
        }],
        [() => fallenScreen() !== null, () => {
            let lines = runLines()
            check(lines.length === 3 && /^Run 3  •  Depth 3  •  0:\d\d$/.test(lines[0])
                  && /^Run 2  •  Depth 4/.test(lines[1]) && /^Run 1  •  Depth 2/.test(lines[2]),
                  "the fall screen lists every run, newest first (" + lines.join(" | ") + ")")
            check(text(fallenScreen(), "fallenRecord") === "Record 4  •  Bo  •  " + today,
                  "and the record is Bo's depth 4 (" + text(fallenScreen(), "fallenRecord") + ")")
        }],
        [1000, () => capture("fallen")],
        [() => saved, () => press(Qt.Key_Escape)],
        [() => game.screen === "title" && find(game, "titleRecord") !== null, () => {
            check(text(game, "titleRecord") === "Record 4  •  Bo  •  " + today,
                  "the title shows the new record (" + text(game, "titleRecord") + ")")
        }]
    ]
    property var steps: runSteps.concat([
        [() => true, () => console.log("[Record] done,", failures, "failed")],
        // Torn down before quitting, as the impact bench does
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ])

    Timer {
        id: script
        property int i: 0
        property real waitedMs: 0
        interval: 20
        repeat: true
        onTriggered: {
            let step = bench.steps[i]
            waitedMs += interval
            let ready = typeof step[0] === "number" ? waitedMs >= step[0] : step[0]()
            if (!ready) {
                if (waitedMs > 20000) {
                    console.log("[Record] FAIL step", i, "timed out")
                    Qt.exit(failures + 1)
                    stop()
                }
                return
            }
            waitedMs = 0
            // Advance first: a key click spins the event loop, and this
            // timer must not run the same step again inside it
            i++
            if (i >= bench.steps.length) stop()
            try {
                step[1]()
            } catch (err) {
                check(false, "step " + (i - 1) + " threw: " + err)
            }
        }
    }
}
