// Focus bench - after an overlay closes, the keys move the knight again
// without a click (issue #73).
//
// Every key goes where a keyboard sends it, to whatever has the focus; the
// bench never hands the focus to an item itself and never clicks the game.
// From the title Enter starts a run, D held moves the knight. Esc opens the
// pause menu and Esc closes it, the menu opens again and Enter on Resume
// closes it: after each, the game has the focus and D held moves the
// knight. A fall shows the fallen
// screen, Enter goes again, and D held moves the knight of the new run.
// Title in the menu goes to the title, Multiplayer opens the lobby, its
// start begins the run, and D held moves the knight. Holding D while the
// menu opens leaves the knight still under it and after it, until D is
// pressed again. Prints one PASS or FAIL line per check and exits with the
// number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/focus/focus.qml

import QtQuick
import QtQuick.Window
import QtTest

Window {
    id: bench
    width: 800
    height: 600
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0

    function check(ok, what) {
        console.log("[Focus]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    // Keys the way a keyboard sends them, to whatever has the focus
    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }
    function hold(key) { keys.keyPress(key, Qt.NoModifier, -1) }
    function release(key) { keys.keyRelease(key, Qt.NoModifier, -1) }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Focus] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true,
                                                  recordStoreName: "ShapesAndStoneFocusBench"})
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
    // The item under root that has the function, shown
    function having(root, fn) {
        if (typeof root[fn] === "function" && root.visible) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = having(kids[i], fn)
            if (f) return f
        }
        return null
    }
    function title() { return having(game, "singlePlayerSelected") }
    function lobby() { return having(game, "startGame") }
    function focused() {
        let f = bench.activeFocusItem
        return f ? (f.objectName || String(f)) : "nothing"
    }
    function standUp() { game.player.hp = 100000 }
    function strikeDown() {
        let p = game.player
        p.isBlocking = false
        p.graceLeft = 0
        p.takeDamage(10 * Math.max(p.hp, p.maxHp), p.xWu + 1, p.yWu)
    }

    // The game holds the focus itself, then D held is checked a moment
    // later and let go. Without the focus on the game the keys still reach
    // it from the closed screen's Loader, so the knight alone would not tell
    function holdD(after) {
        return [
            [100, () => {
                check(bench.activeFocusItem === game, "after " + after + " the game has the focus (focus on "
                      + focused() + ")")
                hold(Qt.Key_D)
            }],
            [100, () => {
                check(game.player.moveX === 1, "after " + after + " D held moves the knight (moveX "
                      + game.player.moveX + ", focus on " + focused() + ")")
                release(Qt.Key_D)
            }],
            [100, () => check(game.player.moveX === 0, "after " + after + " D let go stops the knight")]
        ]
    }

    property var steps: [
        [() => title() !== null && title().activeFocus, () => press(Qt.Key_Return)],
        [() => game.player && game.enemies.length > 0 && title() === null, () => standUp()],
    ].concat(holdD("the title")).concat([
        [0, () => press(Qt.Key_Escape)],
        [() => shown("pauseMenu") !== null && shown("pauseMenu").activeFocus, () => press(Qt.Key_Escape)],
        [() => shown("pauseMenu") === null, () => {}],
    ]).concat(holdD("Esc closes the pause menu")).concat([
        [0, () => press(Qt.Key_Escape)],
        [() => shown("pauseMenu") !== null && shown("pauseMenu").activeFocus, () => press(Qt.Key_Return)],
        [() => shown("pauseMenu") === null, () => {}],
    ]).concat(holdD("Resume closes the pause menu")).concat([
        // D held while the menu opens: the knight lets go under the menu
        // and does not walk off after it until D is pressed again
        [0, () => hold(Qt.Key_D)],
        [100, () => {
            check(game.player.moveX === 1, "D held before the menu moves the knight")
            press(Qt.Key_Escape)
        }],
        [() => shown("pauseMenu") !== null && shown("pauseMenu").activeFocus, () => {
            check(game.player.moveX === 0, "the knight lets go of D under the menu")
            release(Qt.Key_D)
            press(Qt.Key_Escape)
        }],
        [() => shown("pauseMenu") === null, () => {}],
        [100, () => check(game.player.moveX === 0, "after the menu the knight stands until D is pressed")],
        [0, () => strikeDown()],
        [() => shown("fallenScreen") !== null && shown("fallenScreen").activeFocus, () => press(Qt.Key_Return)],
        [() => game.player && !game.fallen && shown("fallenScreen") === null, () => standUp()],
    ]).concat(holdD("the fallen screen goes again")).concat([
        [0, () => press(Qt.Key_Escape)],
        [() => shown("pauseMenu") !== null && shown("pauseMenu").activeFocus, () => {
            // Down past Music and Sound to Title
            press(Qt.Key_S)
            press(Qt.Key_S)
            press(Qt.Key_S)
            press(Qt.Key_Return)
        }],
        [() => title() !== null && title().activeFocus, () => {
            press(Qt.Key_S)
            press(Qt.Key_Return)
        }],
        // The lobby's start is a click on its own button, only shown with
        // a second player; the bench raises its signal instead
        [() => lobby() !== null && game.screen === "lobby", () => lobby().startGame()],
        [() => game.screen === "game" && game.player && game.enemies.length > 0 && lobby() === null,
         () => standUp()],
    ]).concat(holdD("the lobby starts the run")).concat([
        [0, () => console.log("[Focus] done,", failures, "failed")],
        // Torn down before quitting, as the other benches do
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
                    console.log("[Focus] FAIL step", i, "timed out (focus on " + focused() + ")")
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
