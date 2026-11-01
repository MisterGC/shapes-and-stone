// Gamepad bench - every menu works with a gamepad (issue #201), driven by
// the synthetic pad alone: no key is pressed and nothing is clicked.
//
// The pad is clayground's SyntheticGamepad on the game's controller, fed
// the way the dojo inspector's gamepad input feeds it. On the title the
// stick moves the focus and A turns the dungeon master on, then A goes to
// a single player game; on the dungeon master's panel the stick picks and
// turns a row, B gives it back, X generates and A goes. In the dungeon
// the stick walks the knight; Start pauses, and under the menu the held
// stick gives the knight no motion. The stick picks Music and sets it, A
// on Resume resumes, Start and B each resume too, and Title with A goes to
// the title. On the title A again turns the dungeon master off and A on
// Multiplayer opens the lobby: the stick goes over Internet/LAN, Host and
// Join, B leaves; A on LAN and on Host hosts, and A on Back leaves the
// session for the title. Then A starts a game; struck down, A on the
// fallen screen goes again and, struck down again, B goes to the title.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/gamepad/gamepad.qml

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
    property int failures: 0

    function check(ok, what) {
        console.log("[Gamepad]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    // The pad: its state by input name, as the inspector's input action
    // sends it (ClayInputCtrl)
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
        gameController: bench.solo ? bench.solo.gameController : null
        source: agent
    }
    function pad(state) { agent.set(state) }
    // A press and its release a moment later, as two steps
    function tap(state) { return [[60, () => pad(state)], [60, () => pad({})]] }
    function up() { return tap({axisY: 1}) }
    function down() { return tap({axisY: -1}) }
    function left() { return tap({axisX: -1}) }
    function right() { return tap({axisX: 1}) }
    function a() { return tap({buttonA: true}) }
    function b() { return tap({buttonB: true}) }
    function x() { return tap({buttonX: true}) }
    function start() { return tap({buttonStart: true}) }

    Component.onCompleted: {
        let comp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (comp.status !== Component.Ready) {
            console.log("[Gamepad] FAIL", comp.errorString())
            Qt.exit(1)
            return
        }
        solo = comp.createObject(bench.contentItem, {width: 1000, height: 500, muted: true,
                                                     recordStoreName: "ShapesAndStoneGamepadBench"})
        solo.setDungeonMaster(false)
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
        let f = find(solo, name)
        return f && f.visible ? f : null
    }
    function titleAt(i) {
        let c = shown("titleChoice" + i)
        return c !== null && c.isCurrent
    }
    function menu() { return shown("pauseMenu") }
    function panel() { return shown("dungeonMasterPanel") }
    function lobby() { return solo.screen === "lobby" ? solo.data.find(d => d.lobby !== undefined).lobby : null }
    function net() { return lobby() ? lobby().network : null }
    function strikeDown() {
        let p = solo.player
        p.isBlocking = false
        p.graceLeft = 0
        p.takeDamage(10 * Math.max(p.hp, p.maxHp), p.xWu + 1, p.yWu)
    }

    property real music: 1

    property var steps: [].concat(
        [[() => titleAt(0), () => {
            check(solo.gameController.layout === "full", "off touch the controller has the full layout ("
                  + solo.gameController.layout + ")")
        }]],
        down(),
        [[0, () => check(titleAt(1), "down on the title moves to Multiplayer")]],
        down(),
        [[0, () => check(titleAt(2), "down again moves to Dungeon Master")]],
        a(),
        [[0, () => check(solo.dungeonMaster && solo.screen === "title",
                         "A on Dungeon Master turns it on and stays on the title")]],
        up(), up(),
        [[0, () => check(titleAt(0), "up twice goes back to Single Player")]],
        a(),
        [[() => panel() !== null, () => {
            check(solo.screen === "game" && solo.masterOpen,
                  "A on Single Player goes to the game, and the dungeon master's panel is up")
        }]],
        down(),
        [[0, () => check(panel().selectedIndex === 1, "down on the panel picks the second row ("
                         + panel().selectedIndex + ")")]],
        right(),
        [[0, () => check(panel().rows[1].set === true, "right turns the row and sets it ("
                         + panel().rows[1].text + ")")]],
        b(),
        [[0, () => check(panel().rows[1].set === false, "B gives the row back to the game")]],
        x(),
        [[() => solo.masterPreview !== null, () => check(true, "X generates the dungeon")]],
        a(),
        [[() => solo.player && solo.enemies.length > 0, () => {
            check(!solo.masterOpen && panel() === null, "A on the panel goes into the dungeon")
            solo.player.hp = 100000
            pad({axisX: 1})
        }],
        [300, () => {
            check(solo.player.moveX === 1, "the stick walks the knight (moveX " + solo.player.moveX + ")")
            pad({axisX: 1, buttonStart: true})
        }],
        [() => menu() !== null, () => {
            check(solo.menuOpen && solo.gamePaused && !solo.physics.running, "Start pauses the game")
            check(solo.player.moveX === 0, "under the menu the held stick gives the knight no motion ("
                  + solo.player.moveX + ")")
            check(menu().selectedIndex === 0, "the menu opens on Resume")
            pad({})
            music = solo.musicVolume
        }]],
        down(),
        [[0, () => check(menu().selectedIndex === 1, "down picks Music")]],
        left(),
        [[0, () => check(Math.abs(solo.musicVolume - (music - 0.1)) < 1e-6,
                         "left turns the music down a tenth (" + music + " -> " + solo.musicVolume + ")")]],
        right(),
        [[0, () => check(solo.musicVolume === music, "right turns it back up (" + solo.musicVolume + ")")]],
        up(),
        [[0, () => check(menu().selectedIndex === 0, "up goes back to Resume")]],
        a(),
        [[() => menu() === null, () => {
            check(!solo.menuOpen && solo.physics.running && solo.screen === "game", "A on Resume resumes")
        }]],
        start(),
        [[() => menu() !== null, () => check(solo.gamePaused, "Start pauses again")]],
        start(),
        [[() => menu() === null, () => check(solo.physics.running, "Start in the menu resumes")]],
        start(),
        [[() => menu() !== null, () => check(solo.gamePaused, "Start pauses once more")]],
        b(),
        [[() => menu() === null, () => {
            check(solo.physics.running && solo.player.isDashing !== true,
                  "B in the menu resumes, and the knight does not dash on it")
        }]],
        start(),
        [[() => menu() !== null, () => {}]],
        down(), down(), down(),
        [[0, () => check(menu().selectedIndex === 3, "down three times picks Title")]],
        a(),
        [[() => solo.screen === "title" && titleAt(0), () => {
            check(solo.player === null && !solo.menuOpen, "A on Title clears the run and goes to the title")
        }]],
        down(), down(), a(),
        [[0, () => check(!solo.dungeonMaster, "A on Dungeon Master turns it off again")]],
        up(), a(),
        [[() => lobby() !== null, () => {
            check(solo.screen === "lobby", "A on Multiplayer opens the lobby")
            check(JSON.stringify(lobby().padChoices) === '["mode","host","join","back"]',
                  "the lobby offers Internet/LAN, Host, Join and Back (" + JSON.stringify(lobby().padChoices) + ")")
        }]],
        down(),
        [[0, () => check(lobby().padChoice === "host" && lobby().padShown("host")
                         && find(lobby(), "lobbyHost").border.width === 2,
                         "down moves the focus to Host Game and shows it")]],
        right(),
        [[0, () => check(lobby().padChoice === "join", "right goes over to Join Game")]],
        down(),
        [[0, () => check(lobby().padChoice === "back", "down from Join goes to Back")]],
        up(), up(),
        [[0, () => check(lobby().padChoice === "mode", "up twice, past Join and Host, to Internet/LAN")]],
        b(),
        [[() => solo.screen === "title", () => check(true, "B in the lobby goes back to the title")]],
        down(), a(),
        [[() => lobby() !== null, () => {}]],
        right(),
        [[0, () => check(lobby().lanMode, "right on Internet/LAN turns LAN on")]],
        down(), a(),
        [[() => net().isHost && net().networkId !== "", () => {
            check(true, "A on Host Game hosts (" + net().networkId + ")")
            check(lobby().padChoice === "back", "hosting alone, the focus is on Back")
        }]],
        a(),
        [[() => solo.screen === "title" && titleAt(0), () => {
            check(true, "A on Back leaves the session for the title")
        }]],
        a(),
        [[() => solo.player && solo.enemies.length > 0, () => {
            check(!solo.masterOpen, "A on Single Player starts a game without the panel")
            strikeDown()
        }],
        [() => shown("fallenScreen") !== null, () => {}]],
        a(),
        [[() => !solo.fallen && solo.player && solo.player.hp > 0, () => {
            check(shown("fallenScreen") === null && solo.screen === "game", "A on the fallen screen goes again")
        }],
        [() => solo.enemies.length > 0, () => strikeDown()],
        [() => shown("fallenScreen") !== null, () => {}]],
        b(),
        [[() => solo.screen === "title", () => {
            check(solo.player === null, "B on the fallen screen goes to the title")
            console.log("[Gamepad] done,", failures, "failed")
        }],
        // Torn down before quitting, as the other benches do
        [300, () => solo.destroy()],
        [300, () => Qt.exit(failures)]]
    )

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
                    console.log("[Gamepad] FAIL step", i, "timed out")
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
