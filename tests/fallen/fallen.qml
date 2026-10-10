// Fall bench - the knight falls, the run ends with how deep it got, and the
// player can go again or go back to the title (issue #6).
//
// Starts single player, puts the run at depth 2 and brings the knight to
// 0 HP. The enemies must stop and the "You have fallen" screen must show
// the depth. Enter must start a new run from depth 0 on a new seed; a
// second fall and Esc must return to the title, from where a start builds
// a fresh run again. Prints one PASS or FAIL line per check and exits with
// the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/fallen/fallen.qml

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
        console.log("[Fallen]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    // Sends a key the way a keyboard does, to whatever has the focus
    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Fallen] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true})
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
    function music(name) {
        let kids = game.data
        for (let i = 0; i < kids.length; i++)
            if (kids[i].source !== undefined && String(kids[i].source).endsWith(name))
                return kids[i]
        return null
    }

    // A blow no knight survives, from the side, not dashing or blocking
    function strikeDown() {
        let p = game.player
        p.isBlocking = false
        p.takeDamage(10 * p.maxHp, p.xWu + 1, p.yWu)
    }

    property int firstSeed: 0
    property int secondSeed: 0
    property var enemyPos: []
    function positions() {
        return game.enemies.map(e => Qt.point(e.xWu, e.yWu))
    }

    property var steps: [
        [() => game.screen === "title", () => {
            game.screen = "game"
            game.forceActiveFocus()
        }],
        [() => game.player && game.enemies.length > 0, () => {
            firstSeed = game.masterSeed
            check(game.depth === 0 && !game.fallen, "a run starts at depth 0, not fallen")
            // Two dungeons and their villages behind the knight
            game.levelIndex = 4
            strikeDown()
        }],
        [() => fallenScreen() !== null, () => {
            let f = fallenScreen()
            check(game.player.hp === 0, "the knight is at 0 HP")
            check(game.fallen, "the game knows the knight has fallen")
            check(find(f, "fallenTitle").text === "You have fallen", "the screen says \"You have fallen\"")
            check(find(f, "fallenDepth").text === "Depth 2", "the screen shows how deep the run got ("
                  + find(f, "fallenDepth").text + ")")
            check(find(f, "fallenHint").text === "Enter to go again • Esc to the title",
                  "the screen offers Enter to go again (" + find(f, "fallenHint").text + ")")
            let halted = game.enemies.every(e => e.halted && e.target === null && e.aiState === "idle")
            check(halted, "every enemy has stopped (" + game.enemies.length + " enemies)")
            strikeDown()
            check(game.player.hp === 0, "a fallen knight takes no more damage")
        }],
        // Knockbacks and lunges in flight have died down
        [300, () => { enemyPos = positions() }],
        [1000, () => {
            let now = positions()
            let still = now.every((p, i) => Math.abs(p.x - enemyPos[i].x) < 0.01
                                            && Math.abs(p.y - enemyPos[i].y) < 0.01)
            check(still, "no enemy moves for a second after the fall")
            check(game.player.hp === 0 && game.fallen, "the knight stays fallen")
            press(Qt.Key_Return)
        }],
        [() => game.player && !game.fallen, () => {
            secondSeed = game.masterSeed
            check(fallenScreen() === null, "Enter closes the fallen screen")
            check(game.screen === "game", "Enter keeps the game screen")
            check(game.levelIndex === 0 && game.depth === 0 && game.levelType === "dungeon",
                  "Enter starts the new run at depth 0 in a dungeon")
            check(secondSeed !== firstSeed && secondSeed >= 0,
                  "the new run has a new seed (" + firstSeed + " -> " + secondSeed + ")")
            check(game.player.hp === game.player.maxHp, "the knight starts the new run at full HP")
            check(game.enemies.length > 0 && game.enemies.every(e => !e.halted && e.target === game.player),
                  "the new run's enemies hunt the knight")
            strikeDown()
        }],
        [() => fallenScreen() !== null, () => {
            check(find(fallenScreen(), "fallenDepth").text === "Depth 0", "a fall in the first dungeon shows depth 0")
            press(Qt.Key_Escape)
        }],
        [() => game.screen === "title", () => {
            check(!game.fallen && fallenScreen() === null, "Esc closes the fallen screen")
            check(game.player === null && game.enemies.length === 0, "Esc clears the run")
            check(!music("dungeon_music.mp3").playing, "the dungeon music stops on the title")
            game.screen = "game"
            game.forceActiveFocus()
        }],
        [() => game.player && game.enemies.length > 0, () => {
            check(game.masterSeed !== secondSeed && game.masterSeed >= 0,
                  "a start from the title rolls a new seed")
            check(game.depth === 0 && game.player.hp === game.player.maxHp && !game.fallen,
                  "a start from the title is a fresh run")
            console.log("[Fallen] done,", failures, "failed")
        }],
        // Torn down before quitting, as the impact bench does
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
                    console.log("[Fallen] FAIL step", i, "timed out")
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
