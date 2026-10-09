// Impact bench - two games in one process, a host and a joiner connected
// over LAN, check that a hit shakes only the screen of the player it
// concerns (issue #16).
//
// Each side lands every kind of hit through Game.impact(), the way Player,
// Enemy and Projectile report them. The other side must draw the hit's
// sparks and shards, and must neither shake, kick, flash nor hit-stop; the
// side that landed it must. The host keeps its simulation at full speed for
// its own hit stops too, and so does the joiner: in a session others see
// what each node simulates. A blow the shield stops (playerBlocked),
// landed alone, freezes the screen that landed it and only that one; a
// perfect block (perfectBlock), landed alone, freezes and flashes the
// screen that landed it and only that one, and the other draws its sparks.
// A real hit on the joiner's knight flashes the joiner's screen and leaves
// the lost HP as a chunk on its HP bar, neither on the host's; the
// joiner's shield run dry flashes the joiner's mana bar, not the host's,
// and the host draws its shards on the joiner's knight.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
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

    readonly property var kinds: ["enemyHit", "heavyHit", "enemyBlocked", "enemyDeath",
        "playerHit", "playerBlocked", "perfectBlock", "parry", "whirlwind", "projectileHit",
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

    // Found by objectName anywhere under item
    function find(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        let kids = item.children || []
        for (let i = 0; i < kids.length; i++) {
            let f = find(kids[i], name)
            if (f) return f
        }
        return null
    }
    // The KnightView of a knight
    function view(knight) {
        for (let i = 0; i < knight.children.length; i++)
            if (typeof knight.children[i].parry === "function") return knight.children[i]
        return null
    }

    // What a screen's HUD and the other screen's knight did: sampled every
    // frame while a knight's own moment goes on
    property var huds: []
    function hud(game, otherKnight) {
        return {game: game, flashed: false, chunk: false, manaFlash: false, shards: false,
                other: otherKnight}
    }
    Timer {
        interval: 5
        repeat: true
        running: bench.huds.length > 0
        onTriggered: {
            for (let h of bench.huds) {
                let fx = screenFx(h.game)
                if (fx && fx._flash > 0.001) h.flashed = true
                let c = find(h.game, "hpChunk")
                if (c && h.game.player && c.hp > h.game.player.hp + 0.5) h.chunk = true
                if (h.game.manaBarFlashing) h.manaFlash = true
                let v = h.other ? view(h.other) : null
                let sh = v ? find(v, "shieldShards") : null
                if (sh && sh.visible) h.shards = true
            }
        }
    }

    // A hit of every kind (or of these kinds), landed on `from`, watched on
    // both screens
    property var sender: null
    property var receiver: null
    property var sent: null
    property var seen: null
    function landHits(from, to, only) {
        from.camera.resetShake()
        to.camera.resetShake()
        sender = from
        receiver = to
        sent = probe(from)
        seen = probe(to)
        probes = [sent, seen]
        let p = from.player
        for (let k of only || kinds)
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
        [() => hostNet.networkId !== "", () => {
            // Not in a session yet: solo play keeps the physics hit stop
            check(joiner.hitStopMode === "physics", "a game outside a session keeps the physics hit stop (" + joiner.hitStopMode + ")")
            joinNet.join(hostNet.networkId)
        }],
        [() => hostNet.connected && joinNet.connected && hostNet.nodeCount >= 2,
         () => host._startMultiplayerGame()],
        [() => host.player && joiner.player && host.screen === "game" && joiner.screen === "game"
               && Object.keys(session(host).remotePlayers).length > 0
               && Object.keys(session(joiner).remotePlayers).length > 0,
         () => {
            console.log("[Impacts] both in game, host", hostNet.nodeId, "joiner", joinNet.nodeId)
            check(host.hitStopMode === "view", "the host's hit stop holds the picture, not the simulation (" + host.hitStopMode + ")")
            check(joiner.hitStopMode === "view", "the joiner's hit stop holds the picture, not the simulation (" + joiner.hitStopMode + ")")
        }],
        // Let the level's start settle, then the joiner hits
        [1500, () => landHits(joiner, host)],
        [600, () => {
            report("the joiner", "the host")
            // The joiner's own hit stop held the picture only
            check(!sent.slowed, "the joiner keeps its simulation at full speed for its own hits")
        }],
        [300, () => landHits(host, joiner)],
        [600, () => {
            report("the host", "the joiner")
            // The host's own hit stop held the picture only
            check(!sent.slowed, "the host keeps its simulation at full speed for its own hits")
        }],
        // A block alone: it freezes the screen that landed it, only that one.
        // The host's enemies stand from here on: a lunge that hit a knight
        // meanwhile froze and flashed that knight's screen for its own hit
        [300, () => {
            for (let e of host.enemies) if (e && !e.destroyed) e.halt()
            landHits(joiner, host, ["playerBlocked"])
        }],
        [300, () => {
            probes = []
            check(sent.froze && sent.shook,
                  "the joiner hit-stops and kicks for its own block (froze "
                  + sent.froze + ", shook " + sent.shook + ")")
            check(!seen.froze && !seen.shook,
                  "the host neither hit-stops nor kicks for the joiner's block (froze "
                  + seen.froze + ", shook " + seen.shook + ")")
        }],
        // A perfect block alone: it freezes and flashes the screen that
        // landed it, only that one; the other draws its sparks
        [300, () => landHits(joiner, host, ["perfectBlock"])],
        [300, () => {
            seen.particles1 = particles(host)
            probes = []
            check(sent.froze && sent.flashed,
                  "the joiner hit-stops and flashes for its own perfect block (froze "
                  + sent.froze + ", flashed " + sent.flashed + ")")
            check(!seen.froze && !seen.flashed && !seen.shook,
                  "the host neither hit-stops, flashes nor shakes for the joiner's perfect block (froze "
                  + seen.froze + ", flashed " + seen.flashed + ", shook " + seen.shook + ")")
            check(seen.particles1 > seen.particles0,
                  "the host draws the joiner's perfect block (" + seen.particles0 + " -> "
                  + seen.particles1 + " particles)")
        }],
        // A real hit on the joiner's knight, from behind: the screen flash
        // and the HP chunk are the joiner's alone
        [300, () => {
            let jp = joiner.player
            jp.isBlocking = false
            jp.graceLeft = 0
            huds = [hud(joiner, null), hud(host, null)]
            jp.takeDamage(20, jp.xWu - 1, jp.yWu)
        }],
        [300, () => {
            let j = huds[0], h = huds[1]
            huds = []
            check(j.flashed && j.chunk,
                  "the joiner's screen flashes and its HP bar shows the lost chunk for its knight's hurt (flashed "
                  + j.flashed + ", chunk " + j.chunk + ")")
            check(!h.flashed && !h.chunk,
                  "the host's screen neither flashes nor shows an HP chunk for the joiner's hurt (flashed "
                  + h.flashed + ", chunk " + h.chunk + ")")
        }],
        // The joiner's shield runs dry on its next step: its mana bar
        // flashes, the host's does not, and the host draws the shards
        [600, () => {
            let jp = joiner.player
            let rp = session(host).remotePlayers[joinNet.nodeId]
            huds = [hud(joiner, null), hud(host, rp)]
            jp.mana = 0.01
            jp.isBlocking = true
        }],
        [300, () => {
            let j = huds[0], h = huds[1]
            huds = []
            check(j.manaFlash && !joiner.player.isBlocking,
                  "the joiner's mana bar flashes when its shield runs dry (" + j.manaFlash + ")")
            check(!h.manaFlash, "the host's mana bar does not flash for the joiner's shield (" + h.manaFlash + ")")
            check(h.shards, "the host draws the joiner's shield breaking into shards (" + h.shards + ")")
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
