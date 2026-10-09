// Downed bench - two games in one process, a host and a joiner connected
// over LAN, check that a knight at 0 HP shows as downed on both screens and
// that the run ends for both once every knight is down (issue #19).
//
// Two sessions. In the first the joiner's knight falls first: both screens
// must draw it downed, its own screen must say "You are down" with only Esc
// offered, and the run must go on - the host's knight stands, no screen
// leaves the game, no enemy stops. Then the host's knight falls: the host
// must end the run, both stay in the session and both screens show the
// party's summary - depth, kills, time and best depth - the host's with
// Enter to go again, the joiner's waiting for the host (issue #99), until
// Esc takes each to the title. In the second session the host's knight falls first and the
// joiner's last, so the host learns of the last fall over the network.
// In both, while one knight is down the host goes down two levels, to a
// village and to the next dungeon: on the other screen the downed knight
// must be made downed in each, not drawn standing until its next state
// (issue #20).
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/downed/downed.qml

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

    property var host: null
    property var joiner: null
    property var hostNet: null
    property var joinNet: null
    property int failures: 0

    readonly property int seed: 424242
    // How long both screens may take to show a fall, and to show the
    // party's summary once every knight is down
    readonly property int showMs: 1000
    readonly property int endMs: 3000

    // Sends a key the way a keyboard does, to whatever has the focus
    TestEvent { id: keys }
    function press(screen, key) {
        screen.forceActiveFocus()
        keys.keyClick(key, Qt.NoModifier, -1)
    }

    function check(ok, what) {
        console.log("[Downed]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Downed] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        // A record of its own: the bench keeps no best depth of the player's
        host = c.createObject(bench.contentItem, {width: 500, height: 500, muted: true,
                                                  recordStoreName: "ShapesAndStoneDownedBench"})
        joiner = c.createObject(bench.contentItem, {x: 500, width: 500, height: 500, muted: true,
                                                    recordStoreName: "ShapesAndStoneDownedBench"})
        hostNet = network(host)
        joinNet = network(joiner)
        if (!hostNet || !joinNet) {
            console.log("[Downed] FAIL no Network in the game's session")
            Qt.exit(1)
            return
        }
        hostNet.signalingMode = Network.SignalingMode.Local
        watchMade(host)
        watchMade(joiner)
        script.start()
    }

    // The game's Session and its Network, found by what they offer
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
    function find(root, name) {
        if (root.objectName === name) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = find(kids[i], name)
            if (f) return f
        }
        return null
    }
    function fallenScreen(game) {
        let f = find(game, "fallenScreen")
        return f && f.visible ? f : null
    }
    // The KnightView that draws a knight, local or remote
    function viewOf(knight) {
        if (!knight) return null
        for (let i = 0; i < knight.data.length; i++)
            if (knight.data[i].downed !== undefined && typeof knight.data[i].swing === "function")
                return knight.data[i]
        return null
    }
    // A knight's knight on the other screen
    function remoteOf(game, nodeId) { return session(game).remotePlayers[nodeId] }
    function downedOn(game, nodeId) {
        let k = nodeId === network(game).nodeId ? game.player : remoteOf(game, nodeId)
        let v = viewOf(k)
        return v !== null && v.downed === true
    }
    // A blow no knight survives, from the side, not dashing or blocking
    function strikeDown(game) {
        let p = game.player
        p.isBlocking = false
        p.graceLeft = 0
        p.takeDamage(10 * Math.max(p.hp, p.maxHp), p.xWu + 1, p.yWu)
    }
    function inRun(game) { return game.screen === "game" && game.player !== null }
    function bothInGame() {
        return host.player && joiner.player && host.screen === "game" && joiner.screen === "game"
               && remoteOf(host, joinNet.nodeId) !== undefined
               && remoteOf(joiner, hostNet.nodeId) !== undefined
    }

    // The knights out of the enemies' reach while the bench sets things up:
    // a lunge on the knight still standing must not end the run early
    function standUp(only) {
        for (let g of only ? [only] : [host, joiner]) g.player.hp = 100000
    }

    property real fellAt: 0
    property real endedAt: 0

    // Whether each knight of another node was downed when this screen made
    // it, by node id; filled while a level is built
    property var madeDowned: ({})
    function watchMade(game) {
        session(game).remotePlayerSpawned.connect((nodeId, knight) => {
            let v = viewOf(knight)
            madeDowned[nodeId] = v !== null && v.downed === true
        })
    }
    // The level after the next one: the downed knight goes through a
    // village into a dungeon, where the enemies are
    function goDown(level, f, l, firstName, lastName) {
        return [
            [() => true, () => {
                madeDowned = {}
                host._hostAdvanceLevel()
            }],
            [() => host.levelIndex === level && joiner.levelIndex === level && bothInGame()
                   && madeDowned[network(f()).nodeId] !== undefined, () => {
                check(madeDowned[network(f()).nodeId] === true,
                      "level " + level + ": the " + lastName + "'s screen makes the " + firstName
                      + "'s knight downed, before its first state there")
                check(downedOn(f(), network(f()).nodeId) && f().player.hp === 0,
                      "level " + level + ": the " + firstName + "'s knight is still down on its own screen")
                standUp(l())
            }]
        ]
    }

    function sessionSteps(first, last, firstName, lastName) {
        return [
            [() => !hostNet.connected && !joinNet.connected, () => hostNet.host()],
            [() => hostNet.networkId !== "", () => joinNet.join(hostNet.networkId)],
            [() => hostNet.connected && joinNet.connected && hostNet.nodeCount >= 2, () => {
                host.masterSeed = seed
                host._startMultiplayerGame()
            }],
            [() => bothInGame(), () => {
                console.log("[Downed] both in game,", firstName, "falls first")
                standUp()
            }],
            // The remote knights have had their first state
            [500, () => {
                let f = first(), l = last()
                check(!downedOn(host, network(f).nodeId) && !downedOn(joiner, network(f).nodeId)
                      && !downedOn(host, network(l).nodeId) && !downedOn(joiner, network(l).nodeId),
                      "no knight is drawn downed while it stands, on either screen")
                strikeDown(f)
                fellAt = Date.now()
            }],
            [() => downedOn(host, network(first()).nodeId) && downedOn(joiner, network(first()).nodeId), () => {
                let f = first(), l = last(), id = network(f).nodeId
                let ms = Date.now() - fellAt
                check(ms <= showMs, "the " + firstName + "'s knight at 0 HP is drawn downed on both screens ("
                      + ms + " ms after the fall)")
                check(f.player.hp === 0 && f.fallen, "the " + firstName + "'s game knows its knight is down")
                check(remoteOf(l, id).remoteHp === 0, "the " + lastName + "'s screen has the "
                      + firstName + "'s knight at 0 HP")
                let fs = fallenScreen(f)
                check(fs !== null && find(fs, "fallenTitle").text === "You are down",
                      "the " + firstName + "'s screen says \"You are down\" ("
                      + (fs ? find(fs, "fallenTitle").text : "no fallen screen") + ")")
                check(fs !== null && !fs.canGoAgain && find(fs, "fallenHint").text.indexOf("Esc") >= 0,
                      "it offers only Esc (" + (fs ? find(fs, "fallenHint").text : "") + ")")
                check(fallenScreen(l) === null && !l.fallen && l.player.hp > 0,
                      "the " + lastName + "'s knight stands and its screen shows no fallen screen")
            }],
        ].concat(goDown(1, first, last, firstName, lastName))
         .concat(goDown(2, first, last, firstName, lastName))
         .concat([
            // A second for the run to go on
            [1000, () => {
                let f = first(), l = last()
                check(inRun(host) && inRun(joiner) && hostNet.connected && joinNet.connected,
                      "with one knight standing the run goes on, both screens in the game and the session")
                check(host.enemies.length > 0 && host.enemies.every(e => !e.halted),
                      "no enemy of the host's stops")
                check(downedOn(host, network(f).nodeId) && downedOn(joiner, network(f).nodeId)
                      && f.player.hp === 0,
                      "the " + firstName + "'s knight stays down")
                strikeDown(l)
                fellAt = Date.now()
            }],
            [() => host.partyFallen && joiner.partyFallen, () => {
                let ms = Date.now() - fellAt
                check(ms <= endMs, "with every knight down both screens end the run ("
                      + ms + " ms after the " + lastName + "'s knight fell)")
                check(hostNet.connected && joinNet.connected, "both stay in the session")
                for (let [g, name] of [[host, "host"], [joiner, "joiner"]]) {
                    let fs = fallenScreen(g)
                    let text = n => fs ? find(fs, n).text : "no fallen screen"
                    check(fs !== null && g.screen === "game" && text("fallenTitle") === "Your party has fallen",
                          "the " + name + "'s screen says \"Your party has fallen\" (" + text("fallenTitle") + ")")
                    check(fs !== null && text("fallenDepth") === "Depth " + g.depth
                          && text("fallenStats").indexOf("kill") >= 0 && text("fallenBest").indexOf("est depth") >= 0,
                          "it shows the run's depth, kills, time and best depth (" + text("fallenDepth") + " | "
                          + text("fallenStats") + " | " + text("fallenBest") + ")")
                    let hint = g === host ? "Enter to go again • Esc to the title"
                                          : "Waiting for the host to go again • Esc to leave the session"
                    check(fs !== null && fs.canGoAgain === (g === host) && text("fallenHint") === hint,
                          "it offers " + (g === host ? "to go again" : "to wait for the host")
                          + " (" + text("fallenHint") + ")")
                }
                check(host.enemies.every(e => e.halted), "the host's enemies stop")
                press(fallenScreen(joiner), Qt.Key_Escape)
                press(fallenScreen(host), Qt.Key_Escape)
            }],
            [() => host.screen === "title" && joiner.screen === "title"
                   && !hostNet.connected && !joinNet.connected, () => {
                check(true, "Esc on both summaries goes to the title and out of the session")
                check(host.player === null && joiner.player === null
                      && host.enemies.length === 0 && joiner.enemies.length === 0,
                      "the run is cleared on both")
                check(!host.fallen && !joiner.fallen && !host.partyFallen && !joiner.partyFallen
                      && fallenScreen(host) === null && fallenScreen(joiner) === null,
                      "no fallen screen is left on either")
            }]
        ])
    }

    property var steps: []

    function allSteps() {
        return sessionSteps(() => joiner, () => host, "joiner", "host")
            .concat(sessionSteps(() => host, () => joiner, "host", "joiner"))
            .concat([
                // Torn down before quitting: the game crashes when Qt quits
                // with it still up, and the crash's exit code would hide
                // the result
                [300, () => { host.destroy(); joiner.destroy() }],
                [300, () => {
                    console.log("[Downed] done,", failures, "failed")
                    Qt.exit(failures)
                }]
            ])
    }

    Timer {
        id: script
        property int i: 0
        property real waitedMs: 0
        interval: 20
        repeat: true
        onTriggered: {
            if (bench.steps.length === 0) bench.steps = bench.allSteps()
            let step = bench.steps[i]
            waitedMs += interval
            let ready = typeof step[0] === "number" ? waitedMs >= step[0] : step[0]()
            if (!ready) {
                if (waitedMs > 20000) {
                    console.log("[Downed] FAIL timed out at step", i)
                    Qt.exit(100)
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
