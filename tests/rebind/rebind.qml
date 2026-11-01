// Rebind bench - every binding on the Control Input page (issue #221) is
// rebound by pressing the new key, mouse button or pad button, and the game
// follows it.
//
// On the page over the title: the dash's key cell, chosen with Enter, takes
// K, and the table is kept at once. The strike's cell, chosen with a click,
// takes the right button: the shield had it, so the two trade cells and the
// shield is on the left button. The potion's pad cell takes Y, the
// draught's, which gets X; A, which chose the talk's pad cell, is not taken
// itself, and B cancels it, the page still open. Esc cancels the talk's key
// cell; the menu's cells stay fixed; a move takes no mouse button. In the
// village K dashes and Space no longer does, the right button swings, the
// left one raises the shield and the pad's Y drinks a potion. In the pause
// menu's page a click on the mouse and keyboard's Reset puts that column's
// defaults back, the pad's kept, and Enter on the gamepad's Reset puts its
// own back. Prints one PASS or FAIL line per check and exits with the
// number of failures. With an out dir after --, it saves the page while a
// cell waits at 1280x800 as a PNG.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/rebind/rebind.qml [-- <out dir>]

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.GameController
import Clayground.Storage

Window {
    id: bench
    width: 1280
    height: 800
    visible: true
    color: "#1a1a2e"

    readonly property string storeName: "ShapesAndStoneRebindBench"
    property var game: null
    property int failures: 0
    readonly property string outDir: {
        const args = Qt.application.arguments
        const i = args.indexOf("--")
        return i >= 0 && i + 1 < args.length ? args[i + 1] : ""
    }

    function check(ok, what) {
        console.log("[Rebind]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    // Keys and clicks the way a keyboard and a mouse send them
    TestEvent { id: input }
    function press(key) { input.keyClick(key, Qt.NoModifier, -1) }
    function click(item) {
        input.mouseMove(item, item.width / 2, item.height / 2, -1, Qt.NoButton, Qt.NoModifier)
        input.mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, -1)
    }
    // A mouse button pressed and let go on the page, away from its rows
    function mouseOnPage(button) {
        input.mousePress(page(), 40, 40, button, Qt.NoModifier, -1)
        input.mouseRelease(page(), 40, 40, button, Qt.NoModifier, -1)
    }
    function mouseDown(button) { input.mousePress(game, 500, 300, button, Qt.NoModifier, -1) }
    function mouseUp(button) { input.mouseRelease(game, 500, 300, button, Qt.NoModifier, -1) }

    // What the game kept, read back the way the next start reads it
    KeyValueStore { id: kept; name: bench.storeName }
    function keptTable() {
        try { return JSON.parse(kept.get("controls", "")) } catch (err) { return null }
    }

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

    Component.onCompleted: {
        // Nothing kept from an earlier run
        kept.remove("controls")
        let comp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (comp.status !== Component.Ready) {
            console.log("[Rebind] FAIL", comp.errorString())
            Qt.exit(1)
            return
        }
        game = comp.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                     recordStoreName: storeName})
        game.setDungeonMaster(false)
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
    function shown(name) {
        let f = find(game, name)
        return f && f.visible ? f : null
    }
    function title() {
        let c = game.screen === "title" ? find(game, "titleChoice0") : null
        return c ? c.parent.parent : null
    }
    function page() { return shown("controlInputPage") }
    function menu() { return shown("pauseMenu") }
    function prompt() { return find(page(), "controlPrompt").text }
    function rowOf(action) { return game.controls.actions.findIndex(a => a.id === action) }
    // The page's row index and column (0 the mouse and keyboard, 1 the
    // gamepad) picked by the keyboard, as a player picks them
    function go(index, column) {
        let p = page()
        for (let n = 0; p.selectedIndex < index && n < 40; n++) press(Qt.Key_S)
        for (let n = 0; p.selectedIndex > index && n < 40; n++) press(Qt.Key_W)
        if (p.column < column) press(Qt.Key_D)
        if (p.column > column) press(Qt.Key_A)
        return p.selectedIndex === index && p.column === column
    }
    // The swing's InputAction in the knight
    function swing() { return game.player.data.find(d => d.holdThresholdMs !== undefined) }

    function capture(name, then) {
        if (outDir === "") { then(); return }
        bench.contentItem.grabToImage(r => {
            let ok = r.saveToFile(outDir + "/" + name + ".png")
            console.log("[Rebind] capture", name, ok ? "saved" : "FAILED")
            then()
        }, Qt.size(bench.width, bench.height))
    }
    property bool captured: false

    property var steps: [
        [() => title() !== null && title().activeFocus, () => {
            check(game.controls.toJson() === JSON.stringify(game.controls.defaults), "with nothing kept the table is the defaults")
            press(Qt.Key_S)
            press(Qt.Key_S)
            press(Qt.Key_S)
            press(Qt.Key_Return)
        }],
        // A key: the dash's key cell, chosen with Enter
        [() => page() !== null && page().activeFocus, () => {
            check(go(rowOf("dash"), 0), "W/S and A/D pick the dash's mouse and keyboard cell")
            press(Qt.Key_Return)
            check(page().capturing === "keys" && page().captureAction === "dash"
                  && find(game, "controlCelldashkeys").waiting,
                  "Enter makes the cell wait for a key (" + prompt() + ")")
            check(game.controls.key("dash") === Qt.Key_Space, "the Enter that chose it is not taken")
            bench.captured = false
            capture("rebind-waiting", () => bench.captured = true)
        }],
        [() => outDir === "" || captured, () => {
            press(Qt.Key_K)
            check(game.controls.key("dash") === Qt.Key_K && page().capturing === ""
                  && find(game, "controlRowdash").keysText === "K",
                  "K pressed, the dash is on K and its row says so (" + find(game, "controlRowdash").keysText + ")")
            let k = keptTable()
            check(!!k && k.dash.key === Qt.Key_K, "the table is kept at once")
            // A mouse button: the strike's cell, chosen with a click
            click(find(game, "controlCellstrikekeys"))
        }],
        [60, () => {
            check(page().capturing === "keys" && page().captureAction === "strike",
                  "a click on the strike's cell makes it wait (" + prompt() + ")")
            mouseOnPage(Qt.RightButton)
        }],
        [60, () => {
            let c = game.controls
            check(c.mouse("strike") === Qt.RightButton && c.key("strike") === 0,
                  "the right button pressed, the strike is on it")
            check(c.mouse("shield") === Qt.LeftButton && find(game, "controlRowshield").keysText === "LMB",
                  "the shield had it: the two trade, the shield on the left button ("
                  + find(game, "controlRowshield").keysText + ")")
            check(prompt().indexOf("swapped with Shield") !== -1, "the page says they swapped (" + prompt() + ")")
            // A pad button: the potion's pad cell
            check(go(rowOf("potion"), 1), "the potion's gamepad cell is picked")
            press(Qt.Key_Return)
        }],
        [60, () => {
            check(page().capturing === "pad", "Enter makes it wait for a pad button (" + prompt() + ")")
            pad({buttonY: true})
        }],
        [60, () => {
            pad({})
            let c = game.controls
            check(c.pad("potion") === "buttonY" && c.pad("draught") === "buttonX",
                  "Y pressed, the potion is on Y and the draught, which had it, on X")
            check(page() !== null && page().capturing === "", "the page stays open")
            // The pad's A chooses the talk's pad cell and is not taken
            check(go(rowOf("talk"), 1), "the talk's gamepad cell is picked")
            pad({buttonA: true})
        }],
        [60, () => {
            pad({})
            check(page().capturing === "pad" && page().captureAction === "talk" && game.controls.pad("talk") === "buttonA",
                  "the pad's A makes the talk's cell wait, and is not taken itself")
            pad({buttonB: true})
        }],
        [60, () => {
            pad({})
        }],
        [100, () => {
            check(page() !== null && page().capturing === "" && game.controls.pad("talk") === "buttonA"
                  && game.controls.pad("dash") === "buttonB"
                  && prompt() === "Talk, open a door kept as it was",
                  "B cancels: the talk keeps A, the dash B, the page stays open and says so (" + prompt() + ")")
            // Esc cancels a key cell
            go(rowOf("talk"), 0)
            press(Qt.Key_Return)
        }],
        [60, () => {
            check(page().capturing === "keys", "the talk's key cell waits")
            press(Qt.Key_Escape)
            check(page() !== null && page().capturing === "" && game.controls.key("talk") === Qt.Key_E
                  && game.controls.key("menu") === Qt.Key_Escape,
                  "Esc cancels: the talk keeps E, the menu Esc, and the page stays open")
            // The menu stays fixed
            go(rowOf("menu"), 0)
            press(Qt.Key_Return)
            check(page().capturing === "" && prompt().indexOf("menu stays on Esc and Start") !== -1,
                  "the menu's key cell stays fixed (" + prompt() + ")")
            check(go(rowOf("menu"), 1), "the menu's gamepad cell is picked (row " + page().selectedIndex
                  + ", column " + page().column + ")")
            press(Qt.Key_Return)
            check(page().capturing === "" && game.controls.pad("menu") === "buttonStart",
                  "and its pad cell too (waiting: '" + page().capturing + "' " + page().captureAction
                  + ", menu on " + game.controls.pad("menu") + ", " + prompt() + ")")
            // A move takes no mouse button
            go(rowOf("moveUp"), 0)
            press(Qt.Key_Return)
        }],
        [60, () => {
            check(prompt() === "Press a key for Move up", "a move asks for a key (" + prompt() + ")")
            mouseOnPage(Qt.MiddleButton)
        }],
        [60, () => {
            check(page().capturing === "" && game.controls.key("moveUp") === Qt.Key_W
                  && game.controls.mouse("lock") === Qt.MiddleButton && prompt() === "Move up takes a key, not a mouse button",
                  "the middle button is not taken by the move and stays with the lock (" + prompt() + ")")
            press(Qt.Key_Escape)
        }],
        // The game follows each
        [() => page() === null && title().activeFocus, () => game.applyScenario("village", 0)],
        [() => game.player && game.levelType === "village", () => {
            game.forceActiveFocus()
            press(Qt.Key_Space)
            check(!game.player.isDashing, "in the village Space no longer dashes")
            press(Qt.Key_K)
            check(game.player.isDashing, "K dashes")
        }],
        [1200, () => {
            check(swing().mouseButton === Qt.RightButton, "the swing's InputAction takes the right button")
            mouseDown(Qt.RightButton)
            check(swing().pressed && !game.player.isBlocking, "the right button swings")
            mouseUp(Qt.RightButton)
        }],
        [700, () => {
            mouseDown(Qt.LeftButton)
            check(game.player.isBlocking && !swing().pressed, "the left button raises the shield")
            mouseUp(Qt.LeftButton)
            let p = game.player
            p.potions = 2
            p.draughts = 2
            p.hp = p.maxHp - 20
            pad({buttonY: true})
        }],
        [60, () => pad({})],
        [100, () => {
            check(game.player.potions === 1 && game.player.draughts === 2,
                  "the pad's Y drinks a potion (potions " + game.player.potions + ", draughts "
                  + game.player.draughts + ")")
            game.forceActiveFocus()
            press(Qt.Key_Escape)
        }],
        // Reset, from the pause menu's page
        [() => menu() !== null && menu().activeFocus, () => {
            press(Qt.Key_S)
            press(Qt.Key_S)
            press(Qt.Key_S)
            press(Qt.Key_Return)
        }],
        [() => page() !== null && page().activeFocus, () => {
            click(find(game, "controlResetKeys"))
            let c = game.controls, d = c.defaults
            check(c.key("dash") === Qt.Key_Space && c.mouse("strike") === Qt.LeftButton
                  && c.mouse("shield") === Qt.RightButton && c.key("strike") === 0,
                  "a click on the mouse and keyboard's Reset puts its defaults back")
            check(c.pad("potion") === "buttonY" && c.pad("draught") === "buttonX", "the gamepad's are kept")
            check(go(page().resetIndex, 1), "the gamepad's Reset is picked")
            press(Qt.Key_Return)
            check(c.toJson() === JSON.stringify(d), "Enter on it puts the gamepad's back too: the table is the defaults")
            let k = keptTable()
            check(!!k && JSON.stringify(k) === JSON.stringify(d), "and is kept")
            press(Qt.Key_Escape)
        }],
        [() => page() === null && menu() !== null, () => {
            check(game.menuOpen, "Esc goes back to the pause menu")
            kept.remove("controls")
            console.log("[Rebind] done,", failures, "failed")
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
                    console.log("[Rebind] FAIL step", i, "timed out")
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
