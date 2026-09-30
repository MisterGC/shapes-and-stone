// Impact bench - two games in one process, a host and a joiner connected
// over LAN, check that a hit shakes only the screen of the player it
// concerns (issue #16).
//
// Each side lands every kind of hit through Game.impact(), the way Player,
// Enemy and Projectile report them. The other side must draw the hit's
// sparks and shards, and must neither shake, kick, flash nor hit-stop; the
// side that landed it must. The host keeps its simulation at full speed for
// its own hit stops too, since others see what it simulates. Prints one
// PASS or FAIL line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/impacts/impacts.qml

import QtQuick
import QtQuick.Window
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

    readonly property var kinds: ["enemyHit", "enemyBlocked", "enemyDeath",
        "playerHit", "playerBlocked", "parry", "projectileHit",
        "projectileDeflected", "projectileBurst"]

    function check(ok, what) {
        console.log("[Impacts]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Impacts] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        host = c.createObject(bench.contentItem, {width: 500, height: 500, muted: true})
        joiner = c.createObject(bench.contentItem, {x: 500, width: 500, height: 500, muted: true})
        hostNet = network(host)
        joinNet = network(joiner)
        if (!hostNet || !joinNet) {
            console.log("[Impacts] FAIL no Network in the game's session")
            Qt.exit(1)
            return
        }
        hostNet.signalingMode = Network.SignalingMode.Local
        hostNet.host()
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
    function screenFx(game) {
        for (let i = 0; i < game.data.length; i++)
            if (typeof game.data[i].flash === "function" && game.data[i]._flash !== undefined)
                return game.data[i]
        return null
    }

    // Live impact particles (sparks, shards, rings) and stains
    function particles(game) {
        let n = 0
        for (let parent of [game.room, game.glowParent()])
            for (let i = 0; i < parent.children.length; i++) {
                let o = parent.children[i]
                if (o.lifetime !== undefined || o.objectName === "stain" || o.toString().indexOf("Stain") >= 0) n++
            }
        return n
    }

    // What a screen did while a hit went out: sampled every frame
    property var probes: []
    function probe(game) {
        return {game: game, shook: false, froze: false, flashed: false,
                slowed: false, particles0: particles(game)}
    }
    Timer {
        interval: 5
        repeat: true
        running: bench.probes.length > 0
        onTriggered: {
            for (let p of bench.probes) {
                let cam = p.game.camera
                if (cam.trauma > 0.001 || Math.abs(cam.kickXWu) > 0.001 || Math.abs(cam.kickYWu) > 0.001)
                    p.shook = true
                if (p.game.hitStopActive) p.froze = true
                if (p.game.physics.timeScale < 0.999) p.slowed = true
                let fx = screenFx(p.game)
                if (fx && fx._flash > 0.001) p.flashed = true
            }
        }
    }

    // A hit of every kind, landed on `from`, watched on both screens
    property var sender: null
    property var receiver: null
    property var sent: null
    property var seen: null
    function landHits(from, to) {
        from.camera.resetShake()
        to.camera.resetShake()
        sender = from
        receiver = to
        sent = probe(from)
        seen = probe(to)
        probes = [sent, seen]
        let p = from.player
        for (let k of kinds)
            from.impact(k, p.xWu + 1, p.yWu, 1, 0, "#C04040")
    }
    function report(fromName, toName) {
        probes = []
        seen.particles1 = particles(receiver)
        check(seen.particles1 > seen.particles0,
              toName + " draws " + fromName + "'s hits (" + seen.particles0 + " -> " + seen.particles1 + " particles)")
        check(!seen.shook, toName + " does not shake or kick for " + fromName + "'s hits")
        check(!seen.froze, toName + " does not hit-stop for " + fromName + "'s hits")
        check(!seen.slowed, toName + " keeps its simulation at full speed for " + fromName + "'s hits")
        check(!seen.flashed, toName + " does not flash for " + fromName + "'s hits")
        check(sent.shook && sent.froze && sent.flashed,
              fromName + " shakes, hit-stops and flashes for its own hits (shook "
              + sent.shook + ", froze " + sent.froze + ", flashed " + sent.flashed + ")")
    }

    // Steps: [condition to wait for (or null), action]
    property var steps: [
        [() => hostNet.networkId !== "", () => joinNet.join(hostNet.networkId)],
        [() => hostNet.connected && joinNet.connected && hostNet.nodeCount >= 2,
         () => host._startMultiplayerGame()],
        [() => host.player && joiner.player && host.screen === "game" && joiner.screen === "game"
               && Object.keys(session(host).remotePlayers).length > 0
               && Object.keys(session(joiner).remotePlayers).length > 0,
         () => {
            console.log("[Impacts] both in game, host", hostNet.nodeId, "joiner", joinNet.nodeId)
            check(host.hitStopMode === "view", "the host's hit stop holds the picture, not the simulation (" + host.hitStopMode + ")")
            check(joiner.hitStopMode === "physics", "the joiner's hit stop stays as it was (" + joiner.hitStopMode + ")")
        }],
        // Let the level's start settle, then the joiner hits
        [1500, () => landHits(joiner, host)],
        [600, () => report("the joiner", "the host")],
        [300, () => landHits(host, joiner)],
        [600, () => {
            report("the host", "the joiner")
            // The host's own hit stop held the picture only
            check(!sent.slowed, "the host keeps its simulation at full speed for its own hits")
        }],
        [100, () => {
            console.log("[Impacts] done,", failures, "failed")
            hostNet.leave()
            joinNet.leave()
        }],
        // Torn down before quitting: the game crashes when Qt quits with it
        // still up, and the crash's exit code would hide the result
        [300, () => { host.destroy(); joiner.destroy() }],
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
                    console.log("[Impacts] FAIL timed out at step", i)
                    Qt.exit(100)
                }
                return
            }
            waitedMs = 0
            step[1]()
            i++
            if (i >= bench.steps.length) stop()
        }
    }
}
