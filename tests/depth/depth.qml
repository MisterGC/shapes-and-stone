// Depth bench - the HUD shows how deep the knight is, the fallen screen
// shows the run's depth, kills and time, and the record of the deepest
// descent is kept between runs (issues #37, #101).
//
// Runs twice, as two processes, to cross a restart. The first run clears
// the bench's record, checks the HUD at depth 0 and 2, kills an enemy and
// falls at depth 2: a new best. The second run must load best depth 2 from
// the store, show its record on the fallen screen after a fall at depth 0, and keep
// depth 3 as soon as a new run gets there. Prints one PASS or FAIL line per
// check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/depth/depth.qml -- first
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/depth/depth.qml -- second

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Storage

Window {
    id: bench
    width: 800
    height: 600
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0
    readonly property string phase: Qt.application.arguments.includes("second") ? "second" : "first"

    // The same store the game keeps its record in, under the bench's name,
    // so the player's own best depth is not touched
    readonly property string storeName: "ShapesAndStoneDepthBench"
    KeyValueStore { id: record; name: bench.storeName }

    function check(ok, what) {
        console.log("[Depth]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    Component.onCompleted: {
        console.log("[Depth] phase", phase)
        if (phase === "first") {
            record.remove("bestDepth")
            record.remove("record")
        } else
            check(record.get("bestDepth", "none") === "2",
                  "the store holds best depth 2 from the first run (" + record.get("bestDepth", "none") + ")")
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Depth] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true,
                                                  recordStoreName: storeName})
        script.start()
    }

    function find(root, name) {
        if (root.objectName === name) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = find(kids[i], name)
            if (f) return f
        }
        return null
    }
    function fallenScreen() {
        let f = find(game, "fallenScreen")
        return f && f.visible ? f : null
    }
    function fallenText(name) { return find(fallenScreen(), name).text }
    function hud() { return find(game, "gaugeLabel") }

    function strikeDown() {
        let p = game.player
        p.isBlocking = false
        p.takeDamage(10 * p.maxHp, p.xWu + 1, p.yWu)
    }

    property var firstSteps: [
        [() => game.screen === "title", () => {
            check(game.bestDepth === -1, "with a cleared record there is no best depth (" + game.bestDepth + ")")
            game.screen = "game"
            game.forceActiveFocus()
        }],
        [() => game.player && game.enemies.length > 0, () => {
            check(hud() && hud().visible && hud().text === "Depth 0",
                  "the HUD shows \"Depth 0\" in the first dungeon (" + (hud() ? hud().text : "none") + ")")
            game.levelIndex = game.levelIndexOf(2, "dungeon")
            check(hud().text === "Depth 2", "the HUD shows \"Depth 2\" two dungeons down (" + hud().text + ")")
            game.levelIndex = game.levelIndexOf(2, "village")
            check(hud().text === "Depth 2", "the village after it is still \"Depth 2\" (" + hud().text + ")")
            check(record.get("bestDepth", "none") === "2",
                  "depth 2 is kept as soon as the run gets there (" + record.get("bestDepth", "none") + ")")
            game.levelIndex = game.levelIndexOf(2, "dungeon")
            game.enemies[0].takeDamage(100000)
        }],
        // Let the run's clock tick a little
        [500, () => strikeDown()],
        [() => fallenScreen() !== null, () => {
            check(fallenText("fallenDepth") === "Depth 2", "the fallen screen shows depth 2 (" + fallenText("fallenDepth") + ")")
            let stats = fallenText("fallenStats")
            check(/^1 kill  •  0:\d\d$/.test(stats), "the fallen screen shows 1 kill and the time (" + stats + ")")
            check(game.runSeconds > 0, "the run's time ran (" + game.runSeconds.toFixed(2) + " s)")
            check(fallenText("fallenRecord") === "New record",
                  "a first fall at depth 2 is a new record (" + fallenText("fallenRecord") + ")")
            check(game.bestDepth === 2, "the game's best depth is 2")
        }]
    ]

    property var secondSteps: [
        [() => game.screen === "title", () => {
            check(game.bestDepth === 2, "after the restart the game loads best depth 2 (" + game.bestDepth + ")")
            game.screen = "game"
            game.forceActiveFocus()
        }],
        [() => game.player && game.enemies.length > 0, () => {
            check(hud().text === "Depth 0", "the HUD shows \"Depth 0\" (" + hud().text + ")")
            strikeDown()
        }],
        [() => fallenScreen() !== null, () => {
            check(fallenText("fallenDepth") === "Depth 0", "the fall is at depth 0 (" + fallenText("fallenDepth") + ")")
            check(/^0 kills  •  0:\d\d$/.test(fallenText("fallenStats")),
                  "no kills this run (" + fallenText("fallenStats") + ")")
            check(fallenText("fallenRecord").startsWith("Record 2  •  "),
                  "the fallen screen shows the previous record, depth 2 (" + fallenText("fallenRecord") + ")")
            press(Qt.Key_Return)
        }],
        [() => game.player && !game.fallen, () => {
            check(game.runKills === 0 && game.runSeconds < 1, "Enter starts a fresh run record")
            check(hud().text === "Depth 0", "the new run's HUD is back at \"Depth 0\" (" + hud().text + ")")
            game.levelIndex = game.levelIndexOf(3, "dungeon")
            check(record.get("bestDepth", "none") === "3",
                  "reaching depth 3 keeps it at once (" + record.get("bestDepth", "none") + ")")
            strikeDown()
        }],
        [() => fallenScreen() !== null, () => {
            check(fallenText("fallenRecord") === "New record",
                  "a fall below the old record is a new record (" + fallenText("fallenRecord") + ")")
            press(Qt.Key_Escape)
        }],
        [() => game.screen === "title", () => {
            check(game.bestDepth === 3, "the title keeps best depth 3")
        }]
    ]

    property var steps: (phase === "first" ? firstSteps : secondSteps).concat([
        [() => true, () => console.log("[Depth] done,", failures, "failed")],
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
                    console.log("[Depth] FAIL step", i, "timed out")
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
            step[1]()
        }
    }
}
