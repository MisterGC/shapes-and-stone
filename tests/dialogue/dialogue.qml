// Dialogue bench - while a villager's dialogue is open the knight stands,
// and Esc closes the dialogue instead of opening the menu (issue #90).
//
// One knight in the village talks to the innkeeper with E. With the panel
// up, D held moves the knight nowhere and Space does not dash; E through
// the lines closes the panel and the D still held walks the knight on,
// and outside the panel Space dashes. Talking again, Esc closes the panel
// and opens no menu; Esc once more, with no dialogue, opens the menu.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/dialogue/dialogue.qml

import QtQuick
import QtQuick.Window
import QtTest

Window {
    id: bench
    width: 1000
    height: 500
    visible: true
    color: "#1a1a2e"

    property var solo: null
    property int failures: 0

    function check(ok, what) {
        console.log("[Dialogue]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    Component.onCompleted: {
        let comp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (comp.status !== Component.Ready) {
            console.log("[Dialogue] FAIL", comp.errorString())
            Qt.exit(1)
            return
        }
        solo = comp.createObject(bench.contentItem, {width: 1000, height: 500, muted: true,
                                                     recordStoreName: "ShapesAndStoneDialogueBench"})
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
    function menu() {
        let m = find(solo, "pauseMenu")
        return m && m.visible ? m : null
    }
    function panel() {
        for (let i = 0; i < solo.data.length; i++)
            if (solo.data[i] && typeof solo.data[i].advance === "function"
                && solo.data[i].wares !== undefined) return solo.data[i]
        return null
    }
    function innkeeper() {
        let kids = solo.room.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i].objectName === "npc" && kids[i].npcName === "Innkeeper") return kids[i]
        return null
    }
    function standByInnkeeper() {
        let inn = innkeeper()
        solo.player.xWu = inn.xWu
        solo.player.yWu = inn.yWu - 1
    }

    property point knightPos: Qt.point(0, 0)
    function takePos() { knightPos = Qt.point(solo.player.xWu, solo.player.yWu) }
    function walked() {
        return Math.abs(solo.player.xWu - knightPos.x) + Math.abs(solo.player.yWu - knightPos.y)
    }

    property var steps: [
        [() => solo.width > 0, () => solo.applyScenario("dungeon", 0)],
        [() => solo.player !== null, () => solo._enterLevel(solo.levelIndex + 1)],
        [() => solo.player && solo.levelType === "village" && innkeeper() !== null, () => {
            solo.player.hp = 100000
            standByInnkeeper()
        }],
        [() => innkeeper().nearbyPlayer !== null, () => {
            solo.forceActiveFocus()
            press(Qt.Key_E)
        }],
        [() => panel().visible, () => {
            check(panel().speakerName === "Innkeeper", "E at the innkeeper opens the dialogue")
            takePos()
            keys.keyPress(Qt.Key_D, Qt.NoModifier, -1)
        }],
        [300, () => {
            check(solo.player.moveX === 0 && solo.player.moveY === 0,
                  "with the dialogue open D held gives the knight no motion (moveX "
                  + solo.player.moveX + ")")
            check(walked() < 0.01, "with the dialogue open the knight stays where it was ("
                  + walked().toFixed(3) + " wu in 300 ms)")
            press(Qt.Key_Space)
            check(!solo.player.isDashing, "with the dialogue open Space does not dash")
        }],
        [300, () => {
            check(walked() < 0.01, "after Space the knight still stands (" + walked().toFixed(3) + " wu)")
            check(panel().visible, "the dialogue is still open")
            for (let i = 0; i < 6 && panel().visible; i++) press(Qt.Key_E)
            check(!panel().visible, "E through the lines closes the dialogue")
            check(solo.player.moveX === 1, "once it closes the D still held moves the knight (moveX "
                  + solo.player.moveX + ")")
            takePos()
        }],
        [300, () => {
            check(walked() > 0.3, "the knight walks on after the dialogue ("
                  + walked().toFixed(2) + " wu in 300 ms)")
            keys.keyRelease(Qt.Key_D, Qt.NoModifier, -1)
            press(Qt.Key_Space)
            check(solo.player.isDashing, "outside the dialogue Space dashes")
        }],
        // The dash and its cooldown over, back to the innkeeper
        [1500, () => standByInnkeeper()],
        [() => innkeeper().nearbyPlayer !== null && !solo.player.isDashing, () => {
            press(Qt.Key_E)
        }],
        [() => panel().visible, () => {
            press(Qt.Key_Escape)
            check(!panel().visible, "Esc closes the open dialogue")
            check(!solo.menuOpen, "Esc on a dialogue opens no menu")
        }],
        [200, () => {
            check(menu() === null && !solo.menuOpen && solo.physics.running,
                  "after Esc on the dialogue no menu is up and the world runs")
            press(Qt.Key_Escape)
        }],
        [() => menu() !== null, () => {
            check(solo.menuOpen, "Esc without a dialogue opens the menu")
            press(Qt.Key_Escape)
        }],
        [() => menu() === null, () => {
            check(!solo.menuOpen, "Esc in the menu closes it")
            console.log("[Dialogue] done,", failures, "failed")
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
                    console.log("[Dialogue] FAIL step", i, "timed out")
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
