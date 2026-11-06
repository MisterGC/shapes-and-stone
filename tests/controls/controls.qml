// Controls bench - every control of the knight comes from one table, the
// game's ControlTable (issue #218), kept per player with the record.
//
// With nothing kept the table is the defaults, and the controls hint names
// every action of it. Bound to K the dash goes on K and not on Space, and
// the hint says so; the right move on L walks the knight right and D no
// longer does; the shield on G is up while G is held. The strike on the
// middle mouse button: the swing's InputAction takes that button, and the
// left one no longer swings. On the pad the potion and the draught trade
// buttons: Y drinks a potion, and the pad's hint names every action; the
// menu on Select opens the menu. The table is kept under "controls" as
// JSON, a new game loads it at its start, and what is missing or not
// valid in it has its default. Prints one PASS or FAIL line per check and
// exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/controls/controls.qml

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.GameController
import Clayground.Storage

Window {
    id: bench
    width: 1000
    height: 600
    visible: true
    color: "#1a1a2e"

    readonly property string storeName: "ShapesAndStoneControlsBench"
    property var game: null
    property int failures: 0

    function check(ok, what) {
        console.log("[Controls]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: input }
    function press(key) { input.keyClick(key, Qt.NoModifier, -1) }
    function hold(key) { input.keyPress(key, Qt.NoModifier, -1) }
    function release(key) { input.keyRelease(key, Qt.NoModifier, -1) }
    function mouseDown(button) { input.mousePress(game, 500, 300, button, Qt.NoModifier, -1) }
    function mouseUp(button) { input.mouseRelease(game, 500, 300, button, Qt.NoModifier, -1) }

    // What the game kept, read back the way the next start reads it
    KeyValueStore { id: kept; name: bench.storeName }

    // The pad, fed the way the dojo inspector's gamepad input feeds it
    QtObject {
        id: agent
        property bool active: false
        property var gamepad: ({})
        signal stateChanged()
        function set(state) {
            gamepad = state
            active = true
            stateChanged()
        }
    }
    SyntheticGamepad {
        gameController: bench.game ? bench.game.gameController : null
        source: agent
    }
    function pad(state) { agent.set(state) }

    function newGame() {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Controls] FAIL", c.errorString())
            Qt.exit(1)
            return null
        }
        return c.createObject(bench.contentItem, {width: 1000, height: 600, muted: true,
                                                  recordStoreName: storeName})
    }

    Component.onCompleted: {
        // Nothing kept from an earlier run
        kept.remove("controls")
        game = newGame()
        if (game) script.start()
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
    function hint() { return find(game, "controlsHint").text.replace(/ /g, " ") }
    function knightPad() { return find(game, "knightPad") }
    // The swing's InputAction in the knight
    function swing() { return game.player.data.find(d => d.holdThresholdMs !== undefined) }
    // Every action's name in the hint, the ones missing listed
    function missing(text) {
        let names = game.controls.actions.map(a => a.name)
        return names.filter((n, i) => names.indexOf(n) === i && text.indexOf(n) === -1)
    }

    property real fromX: 0

    property var steps: [
        [() => game.screen === "title", () => game.applyScenario("village", 0)],
        [() => game.player && game.levelType === "village", () => {
            game.forceActiveFocus()
            check(game.controls.toJson() === JSON.stringify(game.controls.defaults),
                  "with nothing kept the table is the defaults")
            let h = hint()
            check(missing(h).length === 0, "the keyboard's hint names every action (missing: "
                  + missing(h).join(", ") + ")")
            check(h.indexOf("WASD move") !== -1 && h.indexOf("Mouse aim") !== -1
                  && h.indexOf("F/MMB lock on") !== -1 && h.indexOf("V effects") !== -1,
                  "it names the moves, the aim, F and the middle button, and V (" + h + ")")
            game.controls.bind("dash", "key", Qt.Key_K)
            press(Qt.Key_Space)
            check(!game.player.isDashing, "with the dash on K, Space does not dash")
            press(Qt.Key_K)
            check(game.player.isDashing, "K dashes")
            check(hint().indexOf("K dash") !== -1 && hint().indexOf("Space dash") === -1,
                  "the hint says K dash")
        }],
        [1200, () => {
            game.controls.bind("moveRight", "key", Qt.Key_L)
            fromX = game.player.xWu
            hold(Qt.Key_L)
        }],
        [300, () => {
            check(game.player.moveX === 1 && game.player.xWu > fromX + 0.3,
                  "with the right move on L, L held walks the knight right (moveX " + game.player.moveX + ")")
            release(Qt.Key_L)
            hold(Qt.Key_D)
        }],
        [200, () => {
            check(game.player.moveX === 0, "D no longer moves the knight (moveX " + game.player.moveX + ")")
            release(Qt.Key_D)
            check(hint().indexOf("WASL move") !== -1, "the hint says WASL move")
            game.controls.bind("shield", "key", Qt.Key_G)
            hold(Qt.Key_G)
        }],
        [200, () => {
            check(game.player.isBlocking, "with the shield on G, G held raises it")
            release(Qt.Key_G)
        }],
        [200, () => {
            check(!game.player.isBlocking, "G let go lowers it")
            game.controls.bind("lock", "mouse", 0)
            game.controls.bind("strike", "mouse", Qt.MiddleButton)
            check(swing().mouseButton === Qt.MiddleButton, "the swing's InputAction takes the middle button")
            mouseDown(Qt.MiddleButton)
            check(swing().pressed, "the middle button presses the swing")
            mouseUp(Qt.MiddleButton)
            check(!swing().pressed, "and lets it go")
        }],
        [700, () => {
            mouseDown(Qt.LeftButton)
            check(!swing().pressed, "the left button no longer swings")
            mouseUp(Qt.LeftButton)
            game.controls.bind("potion", "pad", "buttonY")
            game.controls.bind("draught", "pad", "buttonX")
            let p = game.player
            p.potions = 2
            p.draughts = 2
            p.hp = p.maxHp - 20
            pad({buttonY: true})
        }],
        [60, () => pad({})],
        [100, () => {
            check(game.player.potions === 1 && game.player.draughts === 2,
                  "with the potion on the pad's Y, Y drinks a potion (potions " + game.player.potions
                  + ", draughts " + game.player.draughts + ")")
            check(knightPad().inUse, "the pad is in use")
            let h = hint()
            check(missing(h).length === 0, "the pad's hint names every action (missing: "
                  + missing(h).join(", ") + ")")
            check(h.indexOf("Y potion") !== -1 && h.indexOf("X draught") !== -1
                  && h.indexOf("L stick move") !== -1 && h.indexOf("M mute") !== -1,
                  "it says Y potion, X draught, the stick, and the mute key the pad lacks (" + h + ")")
            game.controls.bind("knight", "pad", "")
            game.controls.bind("menu", "pad", "buttonSelect")
            pad({buttonSelect: true})
        }],
        [60, () => pad({})],
        [() => game.menuOpen, () => {
            check(!game.knightPanelOpen, "with the menu on the pad's Select, Select opens the menu")
            pad({buttonStart: true})
        }],
        [60, () => pad({})],
        [100, () => {
            check(game.menuOpen, "Start, bound to nothing, leaves it open")
            pad({buttonB: true})
        }],
        [60, () => pad({})],
        [() => !game.menuOpen, () => {
            let k = null
            try { k = JSON.parse(kept.get("controls", "")) } catch (err) { k = null }
            check(!!k && k.dash.key === Qt.Key_K && k.moveRight.key === Qt.Key_L
                  && k.shield.key === Qt.Key_G && k.strike.mouse === Qt.MiddleButton
                  && k.potion.pad === "buttonY" && k.menu.pad === "buttonSelect",
                  "the table is kept under controls as JSON")
            game.destroy()
            game = null
        }],
        [300, () => game = newGame()],
        [() => game && game.screen === "title", () => {
            let c = game.controls
            check(c.key("dash") === Qt.Key_K && c.key("moveRight") === Qt.Key_L
                  && c.mouse("strike") === Qt.MiddleButton && c.pad("potion") === "buttonY",
                  "a new game loads the kept table at its start")
            check(knightPad().keyboardKeys.axisX[1] === Qt.Key_L, "its keyboard walks right on L")
            let t = c.fromJson('{"dash": {"key": 75}, "talk": {"pad": "nope"}, "aim": {"pad": "buttonA"},'
                               + ' "strike": {"mouse": 3}}')
            check(t.dash.key === Qt.Key_K && t.talk.pad === "buttonA" && t.aim.pad === "axisRight"
                  && t.strike.mouse === Qt.LeftButton && t.potion.pad === "buttonX",
                  "what is missing or not valid in the kept table has its default")
            c.reset()
            check(kept.get("controls", "") === JSON.stringify(c.defaults), "reset keeps the defaults")
            kept.remove("controls")
            console.log("[Controls] done,", failures, "failed")
        }],
        // Torn down before quitting, as the other benches do
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ]

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
                    console.log("[Controls] FAIL step", i, "timed out")
                    Qt.exit(failures + 100)
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
