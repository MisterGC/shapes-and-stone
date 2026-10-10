// Join and leave bench - three games in one process, a host, a joiner and a
// late joiner connected over LAN, check that joining a run under way,
// leaving it and losing the host each end somewhere sensible (issue #20).
//
// The host starts a run with the joiner, whose knight goes down, and goes
// down two levels; at the village's camp the joiner's knight rises and is
// struck down again (issue #100). Then the late joiner joins: it must start in the host's
// level on the host's seed, with the host's live enemies, draw the downed
// knight downed from the start, and its knight must show on the host's and
// the joiner's screens. Its knight then stands at one of the host's enemies
// until the enemy goes for it, and it leaves: no enemy of the host's may go
// for it after. Last the host leaves: the joiner must be back on the title,
// saying that the host left. Prints one PASS or FAIL line per check and
// exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/joinleave/joinleave.qml

import QtQuick
import QtQuick.Window
import Clayground.Network

Window {
    id: bench
    width: 1500
    height: 500
    visible: true
    color: "#1a1a2e"

    property var host: null
    property var joiner: null
    property var late: null
    property var hostNet: null
    property var joinNet: null
    property var lateNet: null
    property int failures: 0

    readonly property int seed: 424242
    // The level the late joiner joins at: the dungeon after the first village
    readonly property int joinLevel: 2
    // How far a knight or an enemy may be from where its own screen has it:
    // another screen shows it a few frames in the past
    readonly property real maxErrorWu: 1.0
    // How long the host may take to let go of a knight whose player left,
    // and a joiner to be back on the title once the host left
    readonly property int dropMs: 1500
    readonly property int titleMs: 2000

    function check(ok, what) {
        console.log("[JoinLeave]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[JoinLeave] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        // A record of its own: the bench keeps no best depth of the player's
        let make = x => c.createObject(bench.contentItem, {x: x, width: 500, height: 500, muted: true,
                                                          recordStoreName: "ShapesAndStoneJoinLeaveBench"})
        host = make(0)
        joiner = make(500)
        late = make(1000)
        hostNet = network(host)
        joinNet = network(joiner)
        lateNet = network(late)
        if (!hostNet || !joinNet || !lateNet) {
            console.log("[JoinLeave] FAIL no Network in the game's session")
            Qt.exit(1)
            return
        }
        hostNet.signalingMode = Network.SignalingMode.Local
        // Drawn standing when the late joiner made it: shown, and not down
        session(late).remotePlayerSpawned.connect((nodeId, knight) => {
            let v = viewOf(knight)
            lateMadeStanding[nodeId] = knight.visible && v !== null && v.downed !== true
        })
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
    // The KnightView that draws a knight, local or remote
    function viewOf(knight) {
        if (!knight) return null
        for (let i = 0; i < knight.data.length; i++)
            if (knight.data[i].downed !== undefined && typeof knight.data[i].swing === "function")
                return knight.data[i]
        return null
    }
    function remoteOf(game, nodeId) { return session(game).remotePlayers[nodeId] }
    function downedOn(game, nodeId) {
        let k = nodeId === network(game).nodeId ? game.player : remoteOf(game, nodeId)
        let v = viewOf(k)
        return v !== null && v.downed === true
    }
    function strikeDown(game) {
        let p = game.player
        p.isBlocking = false
        p.graceLeft = 0
        p.takeDamage(10 * Math.max(p.hp, p.maxHp), p.xWu + 1, p.yWu)
    }
    function liveEnemies(game) { return game.enemies.filter(e => e && !e.destroyed) }
    function liveIds(game) { return liveEnemies(game).map(e => e.objectId).sort() }
    function dist(a, b) { return Math.sqrt((a.xWu - b.xWu) ** 2 + (a.yWu - b.yWu) ** 2) }
    function inLevel(game, level) { return game.screen === "game" && game.player !== null && game.levelIndex === level }
    // The host's enemies that go for the late joiner's knight
    function goingForLate() { return liveEnemies(host).filter(e => e.targetId === lateId) }

    property var lateMadeStanding: ({})
    property string lateId: ""
    property var bait: null
    property real joinedAt: 0
    property real leftAt: 0
    property real hostLeftAt: 0

    property var steps: []
    function allSteps() { return [
        [() => !hostNet.connected && !joinNet.connected, () => hostNet.host()],
        [() => hostNet.networkId !== "", () => joinNet.join(hostNet.networkId)],
        [() => hostNet.connected && joinNet.connected && hostNet.nodeCount >= 2, () => {
            host.masterSeed = seed
            host._startMultiplayerGame()
        }],
        [() => inLevel(host, 0) && inLevel(joiner, 0) && remoteOf(host, joinNet.nodeId) !== undefined, () => {
            // Out of the enemies' reach: the run must not end before the
            // late joiner is in
            host.player.hp = 100000
            strikeDown(joiner)
        }],
        [() => downedOn(host, joinNet.nodeId), () => host._hostAdvanceLevel()],
        // At the camp the joiner's knight rises: down again for the next level
        [() => inLevel(host, 1) && inLevel(joiner, 1) && joiner.player.hp > 0, () => strikeDown(joiner)],
        [() => downedOn(host, joinNet.nodeId) && joiner.player.hp === 0, () => host._hostAdvanceLevel()],
        [() => inLevel(host, joinLevel) && inLevel(joiner, joinLevel) && liveEnemies(host).length > 0, () => {
            console.log("[JoinLeave] host and joiner at level", joinLevel, "- the late joiner joins")
            joinedAt = Date.now()
            lateNet.join(hostNet.networkId)
        }],
        [() => inLevel(late, joinLevel) && remoteOf(host, lateNet.nodeId) !== undefined
               && remoteOf(joiner, lateNet.nodeId) !== undefined, () => {
            lateId = lateNet.nodeId
            check(true, "the late joiner is in the run " + (Date.now() - joinedAt) + " ms after it joined")
            check(late.masterSeed === host.masterSeed && late.levelIndex === host.levelIndex
                  && late.levelType === host.levelType,
                  "it plays the host's seed and level (seed " + late.masterSeed + ", level "
                  + late.levelIndex + " " + late.levelType + ")")
            check(JSON.stringify(late.rooms) === JSON.stringify(host.rooms) && late.rooms.length > 0,
                  "its dungeon is the host's (" + late.rooms.length + " rooms)")
            check(remoteOf(late, hostNet.nodeId) !== undefined && remoteOf(late, joinNet.nodeId) !== undefined,
                  "it shows the host's and the joiner's knights")
            check(lateMadeStanding[joinNet.nodeId] === false,
                  "it never draws the joiner's downed knight standing, not even before its first state")
            late.player.hp = 100000
        }],
        // The enemies' and the late knight's states have arrived
        [1000, () => {
            let h = liveIds(host), l = liveIds(late)
            check(h.length > 0 && JSON.stringify(h) === JSON.stringify(l),
                  "it shows the host's live enemies (host " + h.length + ", late joiner " + l.length + ")")
            let worst = 0
            for (let e of liveEnemies(late)) {
                let he = host._enemyById[e.objectId]
                if (he) worst = Math.max(worst, dist(e, he))
            }
            check(worst <= maxErrorWu, "each where the host has it (worst " + worst.toFixed(2) + " Wu)")
            check(downedOn(late, joinNet.nodeId) && remoteOf(late, joinNet.nodeId).visible
                  && !downedOn(late, hostNet.nodeId) && remoteOf(late, hostNet.nodeId).visible,
                  "it draws the joiner's knight down and the host's standing")
            let k = remoteOf(host, lateId), j = remoteOf(joiner, lateId)
            check(k && dist(k, late.player) <= maxErrorWu && j && dist(j, late.player) <= maxErrorWu,
                  "its knight shows where it stands on the host's and the joiner's screens ("
                  + (k ? dist(k, late.player).toFixed(2) : "none") + " and "
                  + (j ? dist(j, late.player).toFixed(2) : "none") + " Wu)")
            // At the host's enemy farthest from the host's knight
            bait = liveEnemies(host).sort((a, b) => dist(b, host.player) - dist(a, host.player))[0]
            late.player.xWu = bait.xWu + 1
            late.player.yWu = bait.yWu
        }],
        // An enemy in the middle of going for it, not only aiming to
        [() => goingForLate().some(e => ["chase", "telegraph", "lunge"].indexOf(e.aiState) >= 0), () => {
            console.log("[JoinLeave]", goingForLate().length, "enemies go for the late joiner's knight,",
                        goingForLate().map(e => e.aiState).join(" "), "- it leaves")
            leftAt = Date.now()
            late.backToTitle()
        }],
        [() => goingForLate().length === 0 && remoteOf(host, lateId) === undefined, () => {
            let ms = Date.now() - leftAt
            check(ms <= dropMs, "the host's enemies drop the knight of the player who left ("
                  + ms + " ms after it left)")
        }],
        [() => remoteOf(joiner, lateId) === undefined, () => {
            let ms = Date.now() - leftAt
            check(ms <= dropMs, "the joiner's screen no longer shows it (" + ms + " ms after it left)")
            check(late.screen === "title" && late.titleMessage === "",
                  "the late joiner is on the title, with no message: it left on its own")
        }],
        [1000, () => {
            check(goingForLate().length === 0,
                  "a second later still no enemy goes for it ("
                  + liveEnemies(host).map(e => e.targetId || "-").join(" ") + ")")
            check(inLevel(host, joinLevel) && inLevel(joiner, joinLevel) && hostNet.connected && joinNet.connected,
                  "the host and the joiner play on")
            hostLeftAt = Date.now()
            host.backToTitle()
        }],
        [() => joiner.screen === "title", () => {
            let ms = Date.now() - hostLeftAt
            check(ms <= titleMs, "with the host gone the joiner is back on the title (" + ms + " ms after)")
            let m = find(joiner, "titleMessage")
            check(m !== null && m.visible && m.text === "The host left the game",
                  "its title says why (" + (m ? m.text : "no message") + ")")
            check(joiner.player === null && liveEnemies(joiner).length === 0 && !joinNet.connected,
                  "its run is cleared and it is out of the session")
            check(host.titleMessage === "", "the host's title has no message: it left on its own")
        }],
        // Torn down before quitting: the game crashes when Qt quits with it
        // still up, and the crash's exit code would hide the result
        [300, () => { host.destroy(); joiner.destroy(); late.destroy() }],
        [300, () => {
            console.log("[JoinLeave] done,", failures, "failed")
            Qt.exit(failures)
        }]
    ] }

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
                    console.log("[JoinLeave] FAIL timed out at step", i)
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
