// Pause bench - a first-time player sees the controls at depth 0, and Esc
// opens a menu with Resume, Music, Sound and Title (issue #39).
//
// Alone: at depth 0 the controls hint names LMB and its hold to charge,
// RMB, Space for the dash (not Shift), E, M and Esc, and deeper it is gone. With D held, Esc opens
// the "Paused" menu: the
// world stops - no enemy moves, the run's time stands still, the knight
// lets go of D - and M still mutes. Esc and Enter on Resume both go back
// to the game, which runs on without catching up the pause in its first
// steps; S down to Title and Enter go to the title. Esc on the fallen screen
// still goes to the title, never to the menu.
// In a session, a host and a joiner joined over LAN in one process: the
// joiner's menu says the party fights on and pauses nothing - its knight
// with D held is given no motion and 1 drinks no potion, and the host's
// enemies go on on its screen. Under the host's menu the host's world runs
// on and its enemies go on on the joiner's screen. Esc on the joiner's
// "You are down" screen still leaves the session, and Title in the host's
// menu leaves it for the title.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/pause/pause.qml

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Network

Window {
    id: bench
    width: 1000
    height: 500
    visible: true
    color: "#1a1a2e"

    property var solo: null
    property var host: null
    property var joiner: null
    property var hostNet: null
    property var joinNet: null
    property var gameComp: null
    property int failures: 0

    readonly property int seed: 424242

    function check(ok, what) {
        console.log("[Pause]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    // Sends a key the way a keyboard does, to an item given the focus first,
    // or to whatever has it
    TestEvent { id: keys }
    function press(item, key) {
        if (item) item.forceActiveFocus()
        keys.keyClick(key, Qt.NoModifier, -1)
    }
    function hold(item, key) {
        item.forceActiveFocus()
        keys.keyPress(key, Qt.NoModifier, -1)
    }

    Component.onCompleted: {
        gameComp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComp.status !== Component.Ready) {
            console.log("[Pause] FAIL", gameComp.errorString())
            Qt.exit(1)
            return
        }
        solo = gameComp.createObject(bench.contentItem, {width: 1000, height: 500, muted: true,
                                                         recordStoreName: "ShapesAndStonePauseBench"})
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
    function shown(game, name) {
        let f = find(game, name)
        return f && f.visible ? f : null
    }
    function menu(game) { return shown(game, "pauseMenu") }
    function session(game) {
        for (let i = 0; i < game.data.length; i++)
            if (typeof game.data[i].sendImpact === "function") return game.data[i]
        return null
    }
    function network(game) {
        let s = session(game)
        if (!s) return null
        for (let i = 0; i < s.data.length; i++)
            if (typeof s.data[i].join === "function" && s.data[i].signalingMode !== undefined)
                return s.data[i]
        return null
    }
    function positions(game) { return game.enemies.map(e => Qt.point(e.xWu, e.yWu)) }
    // How far the enemies went in all since the positions were taken
    function moved(game, before) {
        let now = positions(game)
        let sum = 0
        for (let i = 0; i < Math.min(now.length, before.length); i++)
            sum += Math.abs(now[i].x - before[i].x) + Math.abs(now[i].y - before[i].y)
        return sum
    }
    // How far the knight went since its position was taken
    function walked(knight) {
        return Math.abs(knight.xWu - knightPos.x) + Math.abs(knight.yWu - knightPos.y)
    }
    // The knights out of reach of harm while the bench looks
    function standUp(game) { game.player.hp = 100000 }
    function strikeDown(game) {
        let p = game.player
        p.isBlocking = false
        p.graceLeft = 0
        p.takeDamage(10 * Math.max(p.hp, p.maxHp), p.xWu + 1, p.yWu)
    }

    property var enemyPos: []
    property real seconds: 0
    property point knightPos: Qt.point(0, 0)
    property int potions: 0

    property var soloSteps: [
        [() => solo.screen === "title", () => {
            solo.screen = "game"
            solo.forceActiveFocus()
        }],
        [() => solo.player && solo.enemies.length > 0, () => {
            standUp(solo)
            let hint = shown(solo, "controlsHint")
            let text = hint ? hint.text : ""
            check(hint !== null && solo.depth === 0, "at depth 0 the controls hint is shown")
            for (let k of ["LMB", "hold to charge", "RMB", "Space dash", "E talk", "M mute", "Esc"])
                check(text.indexOf(k) >= 0, "the hint names " + k + " (" + text + ")")
            // Space dashes (KeyboardGamepad sets buttonB from the A key), Shift does nothing
            check(text.indexOf("Shift") < 0, "the hint does not name Shift (" + text + ")")
            check(menu(solo) === null && !solo.menuOpen, "no menu before Esc")
            hold(solo, Qt.Key_D)
        }],
        [300, () => {
            check(solo.player.moveX === 1, "D held moves the knight (moveX " + solo.player.moveX + ")")
            press(solo, Qt.Key_Escape)
        }],
        [() => menu(solo) !== null && menu(solo).activeFocus, () => {
            let m = menu(solo)
            check(find(m, "pauseTitle").text === "Paused", "Esc opens the \"Paused\" menu ("
                  + find(m, "pauseTitle").text + ")")
            check(find(m, "pauseChoiceResume") !== null && find(m, "pauseChoiceTitle") !== null,
                  "the menu offers Resume and Title")
            check(solo.gamePaused && !solo.physics.running, "alone, the menu pauses the world")
            check(solo.player.moveX === 0, "the knight lets go of D under the menu")
            check(shown(solo, "controlsHint") === null, "the menu hides the controls hint")
            keys.keyRelease(Qt.Key_D, Qt.NoModifier, -1)
            enemyPos = positions(solo)
            seconds = solo.runSeconds
            knightPos = Qt.point(solo.player.xWu, solo.player.yWu)
        }],
        [1000, () => {
            check(moved(solo, enemyPos) < 1e-6, "paused for a second, no enemy moves ("
                  + moved(solo, enemyPos).toFixed(4) + " wu)")
            check(solo.runSeconds === seconds, "the run's time stands still ("
                  + seconds.toFixed(3) + " -> " + solo.runSeconds.toFixed(3) + " s)")
            check(solo.player.xWu === knightPos.x && solo.player.yWu === knightPos.y,
                  "the knight stays where it was")
            press(menu(solo), Qt.Key_M)
            check(solo.muted === false, "M under the menu still reaches the game and unmutes")
            press(menu(solo), Qt.Key_M)
            check(solo.muted === true && menu(solo) !== null, "M again mutes, and the menu stays")
            press(menu(solo), Qt.Key_Escape)
        }],
        [() => menu(solo) === null, () => {
            check(!solo.menuOpen && !solo.gamePaused && solo.physics.running,
                  "Esc in the menu resumes, and the world runs again")
            check(solo.activeFocus, "the game has the keys back")
        }],
        // The second of pause is not caught up on the first step after it
        // (clayground#338): the run's time counts from where the pause
        // held it
        [100, () => {
            check(solo.runSeconds - seconds < 0.3, "the first moments after the menu do not catch up the pause ("
                  + (solo.runSeconds - seconds).toFixed(3) + " s run in the first 100 ms)")
            seconds = solo.runSeconds
        }],
        [300, () => {
            check(solo.runSeconds > seconds, "the run's time goes on after the menu ("
                  + seconds.toFixed(3) + " -> " + solo.runSeconds.toFixed(3) + " s)")
            press(solo, Qt.Key_Escape)
        }],
        [() => menu(solo) !== null && menu(solo).activeFocus, () => {
            check(menu(solo).selectedIndex === 0, "the menu opens on Resume")
            press(menu(solo), Qt.Key_Return)
        }],
        [() => menu(solo) === null, () => {
            check(solo.physics.running && solo.screen === "game", "Enter on Resume goes back to the game")
            press(solo, Qt.Key_Escape)
        }],
        [() => menu(solo) !== null && menu(solo).activeFocus, () => {
            press(menu(solo), Qt.Key_S)
            press(menu(solo), Qt.Key_S)
            press(menu(solo), Qt.Key_S)
            check(menu(solo).selectedIndex === 3, "S three times picks Title, past Music and Sound")
            press(menu(solo), Qt.Key_Return)
        }],
        [() => solo.screen === "title", () => {
            check(solo.player === null && solo.enemies.length === 0 && !solo.menuOpen
                  && menu(solo) === null, "Enter on Title clears the run and goes to the title")
            check(solo.physics.running, "the world is not left paused")
            solo.screen = "game"
            solo.forceActiveFocus()
        }],
        [() => solo.player && solo.enemies.length > 0, () => {
            check(shown(solo, "controlsHint") !== null, "a new run shows the hint again")
            solo.levelIndex = 2
            check(shown(solo, "controlsHint") === null, "at depth 1 the hint is gone")
            strikeDown(solo)
        }],
        [() => shown(solo, "fallenScreen") !== null, () => {
            press(shown(solo, "fallenScreen"), Qt.Key_Escape)
        }],
        [() => solo.screen === "title", () => {
            check(!solo.menuOpen, "Esc on the fallen screen goes to the title, not to the menu")
            solo.destroy()
            solo = null
            startSession()
        }]
    ]

    function startSession() {
        host = gameComp.createObject(bench.contentItem, {width: 500, height: 500, muted: true,
                                                         recordStoreName: "ShapesAndStonePauseBench"})
        joiner = gameComp.createObject(bench.contentItem, {x: 500, width: 500, height: 500, muted: true,
                                                           recordStoreName: "ShapesAndStonePauseBench"})
        hostNet = network(host)
        joinNet = network(joiner)
        if (!hostNet || !joinNet) {
            console.log("[Pause] FAIL no Network in the game's session")
            Qt.exit(1)
            return
        }
        hostNet.signalingMode = Network.SignalingMode.Local
    }
    function bothInGame() {
        return host && joiner && host.player && joiner.player
               && host.screen === "game" && joiner.screen === "game"
               && session(host).remotePlayers[joinNet.nodeId] !== undefined
               && session(joiner).remotePlayers[hostNet.nodeId] !== undefined
    }

    property var sessionSteps: [
        [() => hostNet && !hostNet.connected && !joinNet.connected, () => hostNet.host()],
        [() => hostNet.networkId !== "", () => joinNet.join(hostNet.networkId)],
        [() => hostNet.connected && joinNet.connected && hostNet.nodeCount >= 2, () => {
            host.masterSeed = seed
            host._startMultiplayerGame()
        }],
        [() => bothInGame(), () => {
            standUp(host)
            standUp(joiner)
        }],
        // The enemies have had their first states and go for the knights
        [500, () => {
            joiner.player.potions = 1
            joiner.player.hp = joiner.player.maxHp - 10
            hold(joiner, Qt.Key_D)
            knightPos = Qt.point(joiner.player.xWu, joiner.player.yWu)
        }],
        [300, () => {
            check(joiner.player.moveX === 1 && walked(joiner.player) > 0.3,
                  "in a session D held moves the joiner's knight ("
                  + walked(joiner.player).toFixed(2) + " wu in 300 ms)")
            press(joiner, Qt.Key_Escape)
        }],
        [() => menu(joiner) !== null && menu(joiner).activeFocus, () => {
            let m = menu(joiner)
            check(find(m, "pauseTitle").text === "Menu" && shown(m, "pauseNote") !== null,
                  "the joiner's menu says the party fights on ("
                  + find(m, "pauseTitle").text + ": " + find(m, "pauseNote").text + ")")
            check(!joiner.gamePaused && joiner.physics.running && host.physics.running,
                  "in a session the menu pauses nothing, on either screen")
            check(joiner.player.moveX === 0, "the joiner's knight lets go of D under the menu")
            keys.keyRelease(Qt.Key_D, Qt.NoModifier, -1)
            press(m, Qt.Key_1)
            check(joiner.player.potions === 1, "1 under the menu drinks no potion")
            standUp(joiner)
            enemyPos = positions(joiner)
            knightPos = Qt.point(joiner.player.xWu, joiner.player.yWu)
        }],
        [1000, () => {
            check(moved(joiner, enemyPos) > 0.1, "the host's enemies go on on the joiner's screen ("
                  + moved(joiner, enemyPos).toFixed(2) + " wu in a second)")
            check(joiner.player.moveX === 0 && walked(joiner.player) < 0.1,
                  "the joiner's knight is given no motion (" + walked(joiner.player).toFixed(2) + " wu in a second)")
            press(menu(joiner), Qt.Key_Escape)
        }],
        [() => menu(joiner) === null, () => {
            check(joiner.activeFocus && !joiner.menuOpen, "Esc gives the joiner its game back")
            press(host, Qt.Key_Escape)
        }],
        [() => menu(host) !== null && menu(host).activeFocus, () => {
            check(!host.gamePaused && host.physics.running, "the host's menu does not pause the host")
            enemyPos = positions(joiner)
            seconds = host.runSeconds
        }],
        [1000, () => {
            check(moved(joiner, enemyPos) > 0.1, "under the host's menu its enemies go on on the joiner's screen ("
                  + moved(joiner, enemyPos).toFixed(2) + " wu in a second)")
            check(host.runSeconds > seconds + 0.5, "the host's run time goes on under its menu ("
                  + seconds.toFixed(2) + " -> " + host.runSeconds.toFixed(2) + " s)")
            press(menu(host), Qt.Key_Return)
        }],
        [() => menu(host) === null, () => {
            check(host.screen === "game" && hostNet.connected, "Enter on Resume keeps the host in the session")
            strikeDown(joiner)
        }],
        [() => shown(joiner, "fallenScreen") !== null, () => {
            press(joiner, Qt.Key_Escape)
            check(menu(joiner) === null, "Esc on the game under \"You are down\" opens no menu")
            press(shown(joiner, "fallenScreen"), Qt.Key_Escape)
        }],
        [() => joiner.screen === "title" && !joinNet.connected, () => {
            check(true, "Esc on \"You are down\" still leaves the session for the title")
        }],
        [() => session(host).remotePlayers[joinNet.nodeId] === undefined, () => {
            check(host.screen === "game" && host.player !== null, "the host plays on alone")
            press(host, Qt.Key_Escape)
        }],
        [() => menu(host) !== null && menu(host).activeFocus, () => {
            press(menu(host), Qt.Key_S)
            press(menu(host), Qt.Key_S)
            press(menu(host), Qt.Key_S)
            press(menu(host), Qt.Key_Return)
        }],
        [() => host.screen === "title", () => {
            check(!hostNet.connected && host.player === null && !host.menuOpen,
                  "Title in the host's menu leaves the session for the title")
            console.log("[Pause] done,", failures, "failed")
        }],
        // Torn down before quitting, as the other benches do
        [300, () => { host.destroy(); joiner.destroy() }],
        [300, () => Qt.exit(failures)]
    ]

    property var steps: soloSteps.concat(sessionSteps)

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
                    console.log("[Pause] FAIL step", i, "timed out")
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
