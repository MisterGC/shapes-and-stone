// Duel pace bench - the Esc menu's "Duel pace" row sets how slow a room's
// lead fights, the choice is kept, and in a session the host's holds
// (issue #362).
//
// In a record store of its own, with the pace kept (Game.keepsDuelPace, as
// the game's window keeps it), in the duel room (Balance.pacing.duel):
// - nothing stored, the game plays at Balance.pace.standard; the menu has
//   the row between Sound and Control Input and it shows Standard;
// - S three times picks it, D turns it a step slower to Deliberate and A
//   back and on to Swift, no further than either end: each step is kept
//   with the record (key "duelPace") at once, and the lead's beat
//   (lead.beat) is its factor times the table's;
// - a click on the row's right arrow turns it a step slower, on its left
//   arrow a step quicker; the pad's stick right and left do the same;
// - a new game on the same store, the next start, plays the pace kept;
// - a game on the same store that does not keep the pace - a bench, the
//   dojo - plays at Standard whatever is stored, and its menu's row turns
//   the pace and stores nothing.
// In a session, a host and a joiner joined over LAN in one process, the
// joiner set to Swift on its own: the host keeps Deliberate, every screen
// plays it - the joiner's leads at its factor -, and the joiner's menu
// shows the row as the host's: Deliberate, without arrows, with a note,
// and D, A and a click leave it as it is. The host turns its row to
// Swift and the joiner plays Swift; the joiner's own choice stays its own,
// and back alone it plays it again. The pace the machine keeps for the
// game (store "ShapesAndStone") is the same after the bench as before it.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/duelpace/duelpace.qml

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Storage
import Clayground.Network
import Clayground.GameController
import "../../src"

Window {
    id: bench
    width: 1000
    height: 600
    visible: true
    color: "#1a1a2e"

    readonly property string storeName: "ShapesAndStoneDuelPaceBench"
    readonly property int seed: 424242
    property var gameComp: null
    property var game: null
    property var host: null
    property var joiner: null
    property var hostNet: null
    property var joinNet: null
    property string machinePace: ""
    property int failures: 0

    function check(ok, what) {
        console.log("[DuelPace]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }
    function near(a, b) { return Math.abs(a - b) < 1e-6 }
    function factorOf(name) {
        let s = Balance.pace.steps.find(p => p.name === name)
        return s ? s.factor : -1
    }

    TestEvent { id: input }
    function press(item, key) {
        if (item) item.forceActiveFocus()
        input.keyClick(key, Qt.NoModifier, -1)
    }
    function click(item) {
        input.mouseMove(item, item.width / 2, item.height / 2, -1, Qt.NoButton, Qt.NoModifier)
        input.mouseClick(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, -1)
    }

    // What the bench's games kept, and what the machine keeps for the game
    KeyValueStore { id: kept; name: bench.storeName }
    KeyValueStore { id: machine; name: "ShapesAndStone" }

    // The pad, as the gamepad bench drives it (ClayInputCtrl's shape)
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
        machinePace = machine.get("duelPace", "<none>")
        kept.remove("duelPace")
        gameComp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComp.status !== Component.Ready) {
            console.log("[DuelPace] FAIL", gameComp.errorString())
            Qt.exit(1)
            return
        }
        game = newGame(true)
        script.start()
    }
    function newGame(keeps, props) {
        return gameComp.createObject(bench.contentItem, Object.assign(
            {width: 1000, height: 600, muted: true, recordStoreName: storeName, keepsDuelPace: keeps}, props || {}))
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
    function shown(g, name) {
        let f = find(g, name)
        return f && f.visible ? f : null
    }
    function menu(g) { return shown(g, "pauseMenu") }
    function row(g) { return menu(g) ? find(menu(g), "pauseValueDuelpace").text : "" }
    function lead(g) { return g.enemies.find(e => !e.destroyed && e.lead && !e.boss) || null }
    // The lead's beat at the game's pace, against the table's at factor
    function beatAt(g, f) {
        let e = lead(g)
        return e !== null && near(e.pace, f) && near(e.beatLen, Balance.lead.beat * f / e.speedUp)
    }
    function beatLine(g) {
        let e = lead(g)
        return e ? "the lead's beat " + e.beatLen.toFixed(3) + " s, pace " + e.pace : "no lead"
    }
    // The pace g plays and its leads with it
    function plays(g, name, what) {
        let f = factorOf(name)
        check(g.playedDuelPace === name && near(g.duelPaceFactor, f) && beatAt(g, f),
              what + ": plays " + g.playedDuelPace + ", factor " + g.duelPaceFactor + ", " + beatLine(g))
    }
    // Up to Resume, whatever row the mouse rests on, then S three times
    // down to the row
    function toPaceRow(m) {
        for (let i = 0; i < m.choices.length; i++) press(m, Qt.Key_W)
        press(m, Qt.Key_S)
        press(m, Qt.Key_S)
        press(m, Qt.Key_S)
    }
    function standUp(g) { if (g.player) g.player.hp = 100000 }
    function session(g) {
        for (let i = 0; i < g.data.length; i++)
            if (typeof g.data[i].sendImpact === "function") return g.data[i]
        return null
    }
    function network(g) {
        let s = session(g)
        if (!s) return null
        for (let i = 0; i < s.data.length; i++)
            if (typeof s.data[i].join === "function" && s.data[i].signalingMode !== undefined)
                return s.data[i]
        return null
    }
    function inDuel(g) { return g.player && g.fightRoomActive && lead(g) !== null }

    property var soloSteps: [
        [() => game.screen === "title", () => {
            check(game.duelPace === Balance.pace.standard, "nothing stored, the game plays at "
                  + game.duelPace + " (" + Balance.pace.standard + " wanted)")
            game.applyScenario("duel")
        }],
        [() => inDuel(game), () => {
            standUp(game)
            plays(game, "Standard", "in the duel room")
            press(game, Qt.Key_Escape)
        }],
        [() => menu(game) !== null && menu(game).activeFocus, () => {
            let m = menu(game)
            check(m.choices.join(",") === "Resume,Music,Sound,Duel pace,Control Input,Title",
                  "the menu has Duel pace between Sound and Control Input (" + m.choices.join(",") + ")")
            check(row(game) === "Standard", "the row shows Standard (" + row(game) + ")")
            toPaceRow(m)
            check(find(m, "pauseChoiceDuelpace").isCurrent, "W up to Resume and S three times pick the row")
            press(m, Qt.Key_D)
            check(row(game) === "Deliberate" && kept.get("duelPace", "") === "Deliberate",
                  "D turns it to Deliberate (" + row(game) + "), kept at once (" + kept.get("duelPace", "") + ")")
            plays(game, "Deliberate", "D")
            press(m, Qt.Key_D)
            check(row(game) === "Deliberate", "D again goes no further than Deliberate (" + row(game) + ")")
            press(m, Qt.Key_A)
            press(m, Qt.Key_A)
            check(row(game) === "Swift" && kept.get("duelPace", "") === "Swift",
                  "A twice turns it to Swift (" + row(game) + "), kept (" + kept.get("duelPace", "") + ")")
            plays(game, "Swift", "A twice")
            press(m, Qt.Key_A)
            check(row(game) === "Swift", "A again goes no further than Swift (" + row(game) + ")")
            click(find(m, "pauseUpDuelpace"))
            check(row(game) === "Standard" && kept.get("duelPace", "") === "Standard",
                  "a click on the right arrow turns it to Standard (" + row(game) + "), kept")
            click(find(m, "pauseUpDuelpace"))
            plays(game, "Deliberate", "a second click on the right arrow")
            click(find(m, "pauseDownDuelpace"))
            check(row(game) === "Standard" && game.duelPace === "Standard",
                  "a click on the left arrow turns it back to Standard (" + row(game) + ")")
            check(menu(game).selectedIndex === 3, "the row stays picked under the mouse")
            pad({axisX: 1})
        }],
        [60, () => pad({})],
        [60, () => {
            check(row(game) === "Deliberate" && kept.get("duelPace", "") === "Deliberate",
                  "the pad's stick right turns it to Deliberate (" + row(game) + "), kept")
            plays(game, "Deliberate", "the stick right")
            pad({axisX: -1})
        }],
        [60, () => pad({})],
        [60, () => {
            check(row(game) === "Standard", "the stick left turns it back to Standard (" + row(game) + ")")
            pad({axisX: 1})
        }],
        [60, () => pad({})],
        [60, () => {
            check(kept.get("duelPace", "") === "Deliberate", "the stick right again: Deliberate, kept")
            press(menu(game), Qt.Key_Escape)
        }],
        [() => menu(game) === null, () => {
            game.destroy()
            game = null
        }],
        // The next start
        [300, () => {
            game = newGame(true)
            check(game.duelPace === "Deliberate", "a new game on the same store plays the pace kept ("
                  + game.duelPace + ")")
            game.applyScenario("duel")
        }],
        [() => inDuel(game), () => {
            standUp(game)
            plays(game, "Deliberate", "after the restart, in the duel room")
            game.destroy()
            game = null
        }],
        // A game that does not keep the pace, as a bench or the dojo builds it
        [300, () => {
            game = newGame(false)
            check(game.duelPace === Balance.pace.standard && kept.get("duelPace", "") === "Deliberate",
                  "a game that does not keep the pace plays at " + game.duelPace
                  + " with Deliberate stored")
            game.applyScenario("duel")
        }],
        [() => inDuel(game), () => {
            standUp(game)
            plays(game, "Standard", "not kept, in the duel room")
            press(game, Qt.Key_Escape)
        }],
        [() => menu(game) !== null && menu(game).activeFocus, () => {
            let m = menu(game)
            toPaceRow(m)
            press(m, Qt.Key_A)
            check(row(game) === "Swift" && kept.get("duelPace", "") === "Deliberate",
                  "its row turns the pace to " + row(game) + " and stores nothing ("
                  + kept.get("duelPace", "") + " stays)")
            plays(game, "Swift", "not kept, A")
            game.destroy()
            game = null
        }],
        [300, () => startSession()]
    ]

    // Host and joiner on the bench's store: the host keeps Deliberate, the
    // joiner keeps nothing and is set to Swift on its own
    function startSession() {
        kept.set("duelPace", "Deliberate")
        host = newGame(true, {width: 500})
        joiner = newGame(false, {x: 500, width: 500})
        joiner.setDuelPace("Swift")
        hostNet = network(host)
        joinNet = network(joiner)
        if (!hostNet || !joinNet) {
            console.log("[DuelPace] FAIL no Network in the game's session")
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
    // Every lead on g's screen plays at name's factor
    function leadsAt(g, name) {
        let ls = g.enemies.filter(e => !e.destroyed && e.lead && !e.boss)
        return ls.length > 0 && ls.every(e => near(e.pace, factorOf(name)))
    }
    function leadsLine(g) {
        let ls = g.enemies.filter(e => !e.destroyed && e.lead && !e.boss)
        return ls.length + " leads at " + ls.map(e => e.pace).join(", ")
    }

    property var sessionSteps: [
        [() => hostNet && !hostNet.connected && !joinNet.connected, () => {
            check(host.duelPace === "Deliberate" && joiner.duelPace === "Swift",
                  "alone, the host plays " + host.duelPace + ", the joiner " + joiner.duelPace)
            hostNet.host()
        }],
        [() => hostNet.networkId !== "", () => joinNet.join(hostNet.networkId)],
        [() => hostNet.connected && joinNet.connected && hostNet.nodeCount >= 2, () => {
            host.masterSeed = seed
            // Deep enough for rooms with a lead (Balance.spawn's leadShare)
            host.levelIndex = 4
            host._startMultiplayerGame()
        }],
        [() => bothInGame() && joiner.playedDuelPace === "Deliberate", () => {
            standUp(host)
            standUp(joiner)
        }],
        // The host's enemies have reached the joiner
        [500, () => {
            check(host.playedDuelPace === "Deliberate" && joiner.playedDuelPace === "Deliberate"
                  && near(joiner.duelPaceFactor, factorOf("Deliberate")),
                  "in the session both screens play the host's Deliberate (host " + host.playedDuelPace
                  + ", joiner " + joiner.playedDuelPace + ", factor " + joiner.duelPaceFactor + ")")
            check(leadsAt(host, "Deliberate") && leadsAt(joiner, "Deliberate"),
                  "the leads play it on both screens (host " + leadsLine(host) + "; joiner "
                  + leadsLine(joiner) + ")")
            check(joiner.duelPace === "Swift", "the joiner's own choice stays " + joiner.duelPace)
            press(joiner, Qt.Key_Escape)
        }],
        [() => menu(joiner) !== null && menu(joiner).activeFocus, () => {
            let m = menu(joiner)
            check(row(joiner) === "Deliberate" && shown(m, "pausePaceNote") !== null,
                  "the joiner's menu shows the host's Deliberate (" + row(joiner) + ") and says the host sets it")
            check(find(m, "pauseUpDuelpace").text === "" && find(m, "pauseDownDuelpace").text === "",
                  "the joiner's row has no arrows")
            toPaceRow(m)
            press(m, Qt.Key_A)
            press(m, Qt.Key_D)
            click(find(m, "pauseDownDuelpace"))
            check(row(joiner) === "Deliberate" && joiner.playedDuelPace === "Deliberate"
                  && joiner.duelPace === "Swift" && host.duelPace === "Deliberate",
                  "A, D and a click on the joiner's row change nothing (" + row(joiner) + ", own "
                  + joiner.duelPace + ", host " + host.duelPace + ")")
            press(m, Qt.Key_Escape)
            press(host, Qt.Key_Escape)
        }],
        [() => menu(host) !== null && menu(host).activeFocus, () => {
            let m = menu(host)
            check(shown(m, "pausePaceNote") === null && row(host) === "Deliberate",
                  "the host's row shows Deliberate, its own, with arrows")
            toPaceRow(m)
            press(m, Qt.Key_A)
            press(m, Qt.Key_A)
            check(row(host) === "Swift" && kept.get("duelPace", "") === "Swift",
                  "the host turns its row to Swift (" + row(host) + "), kept")
            press(m, Qt.Key_Escape)
        }],
        [() => joiner.playedDuelPace === "Swift", () => {
            check(near(joiner.duelPaceFactor, factorOf("Swift")) && leadsAt(joiner, "Swift")
                  && leadsAt(host, "Swift"),
                  "the joiner follows the host to Swift (" + leadsLine(joiner) + ")")
            joiner.setDuelPace("Deliberate")
            check(joiner.duelPace === "Swift", "a joiner sets no pace of its own in a session ("
                  + joiner.duelPace + ")")
            joinNet.leave()
        }],
        [() => !joinNet.connected, () => {
            check(joiner.playedDuelPace === "Swift" && joiner.duelPace === "Swift",
                  "back alone, the joiner plays its own pace (" + joiner.playedDuelPace + ")")
            joiner.setDuelPace("Standard")
            check(joiner.playedDuelPace === "Standard", "and sets it again alone (" + joiner.playedDuelPace + ")")
            hostNet.leave()
        }],
        [300, () => {
            host.destroy()
            joiner.destroy()
            host = null
            joiner = null
            kept.remove("duelPace")
        }],
        [300, () => {
            let now = machine.get("duelPace", "<none>")
            check(now === machinePace, "the pace the machine keeps for the game is as it was ("
                  + machinePace + " -> " + now + ")")
            console.log("[DuelPace] done,", failures, "failed")
            Qt.exit(failures)
        }]
    ]
    readonly property var steps: soloSteps.concat(sessionSteps)

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
                    console.log("[DuelPace] FAIL step", i, "timed out")
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
