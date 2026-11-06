// Pad notice bench - the game says when a gamepad connects or leaves, with
// its name (issue #219).
//
// The pads are virtual ones on clayground's GamepadHub, plugged in and
// unplugged the way a player plugs in a real one. On the title a pad
// plugged in gets "Gamepad connected" with its name and, unplugged,
// "Gamepad unplugged". In a game a pad that drives the knight, unplugged,
// says the keyboard and mouse play now, and the keyboard drives again. A
// notice goes after its time. The title's line about pads asks for a press
// in the browser while it lists no pad, says to use Chrome for a pad the
// browser cannot read, and says nothing elsewhere. Prints one PASS or FAIL
// line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/padnotice/padnotice.qml

import QtQuick
import QtQuick.Window
import Clayground.GameController

Window {
    id: bench
    width: 1000
    height: 500
    visible: true
    color: "#1a1a2e"

    property var solo: null
    property var notice: null
    property int failures: 0
    property int padId: -1

    function check(ok, what) {
        console.log("[PadNotice]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let comp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (comp.status !== Component.Ready) {
            console.log("[PadNotice] FAIL", comp.errorString())
            Qt.exit(1)
            return
        }
        solo = comp.createObject(bench.contentItem, {width: 1000, height: 500, muted: true,
                                                     recordStoreName: "ShapesAndStonePadNoticeBench"})
        solo.setDungeonMaster(false)
        notice = find(solo, "padNotice")
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
    function says(line) { return notice.texts().indexOf(line) !== -1 }
    function rowShown() {
        let row = find(notice, "padNoticeRow")
        return row !== null && row.visible
    }
    function said() { return JSON.stringify(notice.texts()) }
    function plug(name) {
        padId = GamepadHub.attachVirtualGamepad(name)
        GamepadHub.poll()
        return padId
    }
    function unplug() {
        GamepadHub.detachVirtualGamepad(padId)
        GamepadHub.poll()
    }

    property var steps: [
        [() => solo.screen === "title" && find(solo, "titleChoice0") !== null, () => {
            check(notice !== null, "the game has the pad notice")
            check(GamepadHub.backend !== "none", "the hub reads pads here (" + GamepadHub.backend + ")")
            // Short, so the bench sees one go
            notice.seconds = 1.5
            check(plug("Bench Pad One") !== -1, "a virtual pad is plugged in (" + padId + ")")
        }],
        [() => says("Gamepad connected - Bench Pad One"), () => {
            check(true, "on the title, plugged in: Gamepad connected - Bench Pad One")
            check(rowShown(), "the notice is on the screen")
        }],
        [300, () => unplug()],
        [() => says("Gamepad unplugged - Bench Pad One"), () => {
            check(true, "unplugged: Gamepad unplugged - Bench Pad One " + said())
        }],
        [() => notice.texts().length === 0, () => {
            check(!rowShown(), "the notices go after their time")
            solo.screen = "game"
        }],
        [() => solo.player !== null && solo.enemies.length > 0, () => {
            plug("Bench Pad Two")
        }],
        [() => says("Gamepad connected - Bench Pad Two"), () => {
            check(true, "in a game, plugged in: Gamepad connected - Bench Pad Two")
            GamepadHub.setVirtualGamepadInput(padId, "south", 1)
            GamepadHub.poll()
        }],
        [() => solo.gameController.gamepadSelected, () => {
            check(solo.gameController.gamepad.name === "Bench Pad Two",
                  "a press on it makes it drive (" + solo.gameController.gamepad.name + ")")
            GamepadHub.setVirtualGamepadInput(padId, "south", 0)
            GamepadHub.poll()
        }],
        [200, () => unplug()],
        [() => says("Gamepad unplugged - Bench Pad Two - keyboard and mouse play now"), () => {
            check(true, "the pad that drove, unplugged: keyboard and mouse play now " + said())
        }],
        [100, () => {
            check(solo.gameController.keyboardSelected && !solo.gameController.gamepadSelected,
                  "the keyboard drives again")
            plug("Bench Pad Three")
        }],
        [() => says("Gamepad connected - Bench Pad Three"), () => unplug()],
        [() => says("Gamepad unplugged - Bench Pad Three"), () => {
            check(true, "a pad that never drove, unplugged: no word of the keyboard " + said())
        }],
        [0, () => {
            let browser = notice.titleLineFor("browser", [])
            check(browser === "Press a button on your gamepad to use it",
                  "the browser listing no pad: the title asks for a press (" + browser + ")")
            check(notice.titleLineFor("browser", [{type: "standard", name: "Pad"}]) === "",
                  "the browser listing a pad: the title says nothing")
            let firefox = notice.titleLineFor("browser", [{type: "unsupported", name: "Pad"}])
            check(firefox.indexOf("Chrome") !== -1, "a pad the browser cannot read: use Chrome (" + firefox + ")")
            check(notice.titleLineFor("sdl", []) === "", "a native build with no pad: the title says nothing")
            solo.backToTitle()
        }],
        [() => solo.screen === "title" && find(solo, "titleChoice0") !== null, () => {
            let line = find(solo, "titlePadLine")
            check(line !== null && line.text === notice.titleLine && line.visible === (notice.titleLine !== ""),
                  "the title shows the pad line (\"" + notice.titleLine + "\")")
            console.log("[PadNotice] done,", failures, "failed")
        }],
        [300, () => solo.destroy()],
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
                    console.log("[PadNotice] FAIL step", i, "timed out", bench.said())
                    Qt.exit(failures + 100)
                    stop()
                }
                return
            }
            waitedMs = 0
            i++
            if (i >= bench.steps.length) stop()
            step[1]()
        }
    }
}
