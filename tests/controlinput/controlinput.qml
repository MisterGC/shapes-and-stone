// Control Input bench - the Control Input page (issue #220) opens and
// closes from the title and the pause menu by keyboard and mouse, and
// lists every action with both its bindings and the devices with the one
// in use marked. The gamepad bench walks it with the pad.
//
// On the title S three times and Enter open the page over it, with the
// focus; every action of the control table has its row with its key or
// mouse button and its pad input, as the table names them; Keyboard and
// Mouse are listed and in use. A virtual pad plugged in (where the build
// reads pads) is listed by its name, a press on it marks it in use and the
// hint names its buttons, a key marks the keyboard again, and unplugged it
// is gone. Esc goes back to the title, on Control Input; a click on the
// row opens the page and a click on Back closes it. In the game Esc opens
// the pause menu, S three times and Enter open the page over it, the menu
// hidden and the world still paused, M mutes, Esc goes back to the menu on
// Control Input and the menu's click and Back's click do the same.
// Prints one PASS or FAIL line per check and exits with the number of
// failures. With an out dir after --, it saves the page over the title and
// over the pause menu at 1280x800 as PNGs.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/controlinput/controlinput.qml [-- <out dir>]

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.GameController

Window {
    id: bench
    width: 1280
    height: 800
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0
    // The virtual pad's deviceId, -1 for none
    property int padId: -1
    readonly property string outDir: {
        const args = Qt.application.arguments
        const i = args.indexOf("--")
        return i >= 0 && i + 1 < args.length ? args[i + 1] : ""
    }

    function check(ok, what) {
        console.log("[ControlInput]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    // Keys and clicks the way a keyboard and a mouse send them
    TestEvent { id: input }
    function press(key) { input.keyClick(key, Qt.NoModifier, -1) }
    function click(item) {
        input.mouseMove(item, item.width / 2, item.height / 2, -1, Qt.NoButton, Qt.NoModifier)
        input.mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, -1)
    }

    Component.onCompleted: {
        let comp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (comp.status !== Component.Ready) {
            console.log("[ControlInput] FAIL", comp.errorString())
            Qt.exit(1)
            return
        }
        game = comp.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                     recordStoreName: "ShapesAndStoneControlInputBench"})
        game.setDungeonMaster(false)
        game.controls.reset()
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
    // The title screen, its menu shown or not
    function title() {
        let c = game.screen === "title" ? find(game, "titleChoice0") : null
        return c ? c.parent.parent : null
    }
    function titleAt(i) {
        let c = shown("titleChoice" + i)
        return c !== null && c.isCurrent
    }
    function page() { return shown("controlInputPage") }
    function menu() { return shown("pauseMenu") }
    // The device chips: [{ name, inUse }]
    function devices() {
        let list = []
        for (let i = 0; ; i++) {
            let c = find(game, "controlDevice" + i)
            if (!c) return list
            list.push({ name: c.deviceName, inUse: c.inUse })
        }
    }
    function deviceNames() { return devices().map(d => d.name + (d.inUse ? "*" : "")).join(", ") }

    // Every action has its row, with its title and both bindings as the
    // table names them
    function checkRows() {
        let t = game.controls
        let missing = [], wrong = []
        for (const a of t.actions) {
            let row = find(game, "controlRow" + a.id)
            if (!row) { missing.push(a.id); continue }
            let keys = t.keysBindingName(a.id) || "-"
            if (row.title !== a.title || row.title === "" || row.keysText !== keys)
                wrong.push(a.id + " " + row.title + " | " + row.keysText + " | " + row.padText)
        }
        check(missing.length === 0, "every action of the table has its row (missing: " + missing.join(", ") + ")")
        check(wrong.length === 0, "each row shows its action's title and its key or mouse binding ("
              + wrong.join("; ") + ")")
        let rows = { moveUp: ["Move up", "W", "L stick / D-pad up"], aim: ["Aim", "Mouse", "R stick"],
                     strike: ["Strike", "LMB", "R1"], shield: ["Shield", "RMB", "L1"],
                     dash: ["Dash", "Space", "B"], whirlwind: ["Whirlwind", "Q", "R2"],
                     lock: ["Lock on an enemy", "F / MMB", "L2"], knight: ["Knight panel", "C", "Select"],
                     mute: ["Mute", "M", "-"], menu: ["Menu", "Esc", "Start"] }
        let off = []
        for (const id in rows) {
            let row = find(game, "controlRow" + id)
            let got = row ? [row.title, row.keysText, row.padText] : []
            if (JSON.stringify(got) !== JSON.stringify(rows[id])) off.push(id + ": " + got.join(" | "))
        }
        check(off.length === 0, "the defaults read side by side, e.g. Strike | LMB | R1, Mute | M | - (" + off.join("; ") + ")")
    }

    function capture(name, then) {
        if (outDir === "") { then(); return }
        bench.contentItem.grabToImage(r => {
            let ok = r.saveToFile(outDir + "/" + name + ".png")
            console.log("[ControlInput] capture", name, ok ? "saved" : "FAILED")
            then()
        }, Qt.size(bench.width, bench.height))
    }
    property bool captured: false

    property var steps: [
        [() => title() !== null && title().activeFocus, () => {
            press(Qt.Key_S)
            press(Qt.Key_S)
            press(Qt.Key_S)
            check(titleAt(3), "S three times on the title picks Control Input")
            press(Qt.Key_Return)
        }],
        [() => page() !== null && page().activeFocus, () => {
            check(game.controlInputOpen && find(game, "controlInputTitle").text === "Control Input",
                  "Enter opens the Control Input page over the title, with the focus")
            check(title().covered && !find(title(), "titleChoice0").parent.visible, "the title's menu is hidden under the page")
            checkRows()
            let d = devices()
            check(d.length >= 2 && d[0].name === "Keyboard" && d[1].name === "Mouse" && d[0].inUse && d[1].inUse,
                  "Keyboard and Mouse are listed, in use (" + deviceNames() + ")")
            check(d.length - 2 === GamepadHub.count && (GamepadHub.count > 0) === (shown("controlNoPad") === null),
                  "each connected pad is listed, and with none the page says how to get one listed ("
                  + GamepadHub.count + " connected)")
            press(Qt.Key_S)
            press(Qt.Key_S)
            check(page().selectedIndex === 2, "S picks a row down the table (" + page().selectedIndex + ")")
            padId = GamepadHub.backend === "sdl" ? GamepadHub.attachVirtualGamepad("Bench Pad") : -1
            if (padId < 0) console.log("[ControlInput] SKIP the pad's part: this build reads no pads ("
                                       + GamepadHub.backend + ")")
        }],
        [() => padId < 0 || devices().some(d => d.name === "Bench Pad"), () => {
            if (padId < 0) return
            check(!devices().find(d => d.name === "Bench Pad").inUse, "a pad plugged in is listed by its name, not yet in use ("
                  + deviceNames() + ")")
            GamepadHub.setVirtualGamepadInput(padId, "north", 1)
        }],
        [() => padId < 0 || game.padInUse, () => {
            if (padId < 0) return
            GamepadHub.setVirtualGamepadInput(padId, "north", 0)
            let d = devices()
            check(d.find(x => x.name === "Bench Pad").inUse && !d[0].inUse && !d[1].inUse,
                  "a press on it marks the pad in use, the keyboard and mouse no longer (" + deviceNames() + ")")
            check(find(game, "controlHint").text.indexOf("or Start to go back") !== -1,
                  "the hint names the pad's buttons (" + find(game, "controlHint").text + ")")
            check(page() !== null, "a press of Y on the page leaves it open")
        }],
        [100, () => {
            bench.captured = false
            capture("controlinput-title", () => bench.captured = true)
        }],
        [() => outDir === "" || captured, () => {
            if (padId < 0) return
            press(Qt.Key_W)
            check(devices()[0].inUse && !devices().find(x => x.name === "Bench Pad").inUse,
                  "a key marks the keyboard in use again (" + deviceNames() + ")")
            GamepadHub.detachVirtualGamepad(padId)
            padId = -1
        }],
        [() => !devices().some(d => d.name === "Bench Pad"), () => {
            check(true, "unplugged, the pad is no longer listed (" + deviceNames() + ")")
            press(Qt.Key_Escape)
        }],
        [() => page() === null && title().activeFocus, () => {
            check(!game.controlInputOpen && game.screen === "title" && titleAt(3),
                  "Esc goes back to the title, on Control Input, with the focus")
            click(find(game, "titleChoice3"))
        }],
        [() => page() !== null, () => {
            check(true, "a click on Control Input opens the page")
            click(find(game, "controlBack"))
        }],
        [() => page() === null, () => {
            check(game.screen === "title" && title().activeFocus, "a click on Back closes it, the title has the focus")
            press(Qt.Key_W)
            press(Qt.Key_W)
            press(Qt.Key_W)
            press(Qt.Key_Return)
        }],
        [() => game.screen === "game" && game.player && game.enemies.length > 0, () => {
            game.forceActiveFocus()
            press(Qt.Key_Escape)
        }],
        [() => menu() !== null && menu().activeFocus, () => {
            press(Qt.Key_S)
            press(Qt.Key_S)
            press(Qt.Key_S)
            check(find(menu(), "pauseChoiceControlInput").isCurrent, "S three times in the pause menu picks Control Input")
            press(Qt.Key_Return)
        }],
        [() => page() !== null && page().activeFocus, () => {
            check(menu() === null && game.menuOpen && game.gamePaused && !game.physics.running,
                  "Enter opens the page over the pause menu: the menu hidden, the world still paused")
            checkRows()
            press(Qt.Key_M)
        }],
        [100, () => {
            check(!game.muted && page() !== null, "M on the page unmutes the game, the page stays open")
            press(Qt.Key_M)
        }],
        [100, () => {
            check(game.muted && page() !== null, "M again mutes it")
            bench.captured = false
            capture("controlinput-pause", () => bench.captured = true)
        }],
        [() => outDir === "" || captured, () => press(Qt.Key_Escape)],
        [() => page() === null && menu() !== null && menu().activeFocus, () => {
            check(game.menuOpen && game.gamePaused && menu().selectedIndex === 3,
                  "Esc goes back to the pause menu, on Control Input, the game still paused")
            click(find(game, "pauseChoiceControlInput"))
        }],
        [() => page() !== null, () => {
            check(game.menuOpen, "a click on Control Input in the pause menu opens the page")
            click(find(game, "controlBack"))
        }],
        [() => page() === null && menu() !== null && menu().activeFocus, () => {
            check(game.menuOpen, "a click on Back goes back to the pause menu, with the focus")
            press(Qt.Key_Escape)
        }],
        [() => menu() === null && game.physics.running, () => {
            check(!game.controlInputOpen, "Esc in the pause menu resumes, the page closed")
            console.log("[ControlInput] done,", failures, "failed")
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
                    console.log("[ControlInput] FAIL step", i, "timed out")
                    if (bench.padId >= 0) GamepadHub.detachVirtualGamepad(bench.padId)
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
