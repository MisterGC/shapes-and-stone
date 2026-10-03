// Same-world bench - one of two game instances, a host or a joiner, that
// run_sameworld.py starts as two processes (clayliveloader --instance),
// connects over Local or Cloud signaling and drives through the inspector
// protocol (issue #14).
//
// The instance runs the real game. Once the session is in the dungeon the
// driver puts each knight beside an enemy, lets the joiner's knight land a
// scripted hit and then lets both knights fight: each goes for the nearest
// enemy and swings at it. Meanwhile every frame records every enemy this
// screen shows - its object id, position, HP and AI state - stamped with
// the wall clock, and the driver takes the records and compares the two
// screens.
//
// stale() makes this screen apply none of the host's enemy states (only on
// a joiner): the check that the bench can fail.

import QtQuick
import Clayground.Network
import "../../src"

Item {
    id: bench
    anchors.fill: parent

    Game {
        id: game
        anchors.fill: parent
        muted: true
        // A record of its own: the bench keeps no best depth of the player's
        recordStoreName: "ShapesAndStoneSameWorldBench"
    }

    // ---- the game's Session and its Network, found by what they offer ----
    readonly property var session: {
        for (let i = 0; i < game.data.length; i++)
            if (typeof game.data[i].sendImpact === "function") return game.data[i]
        return null
    }
    readonly property var net: session ? session.network : null

    // ---- driver API ----
    property bool useLocalSignaling: true
    readonly property string netId: net ? net.networkId : ""
    readonly property string nodeId: net ? net.nodeId : ""
    readonly property bool connected: net ? net.connected : false
    readonly property int nodeCount: net ? net.nodeCount : 0
    readonly property bool isHost: net ? net.isHost : false
    readonly property string screen: game.screen
    readonly property int enemyCount: game.enemies.length
    readonly property int seed: game.masterSeed
    // In the dungeon, with the other player's knight and the host's enemies
    // (a function: remotePlayers changes in place, a binding misses it)
    function inGame() {
        return game.screen === "game" && game.player !== null && session !== null
               && Object.keys(session.remotePlayers).length > 0 && game.enemies.length > 0
    }

    function configure(local) {
        useLocalSignaling = local
        return net !== null
    }
    function _mode() {
        return useLocalSignaling ? Network.SignalingMode.Local : Network.SignalingMode.Cloud
    }
    function hostUp() { net.signalingMode = _mode(); net.host() }
    function joinNet(code) { net.signalingMode = _mode(); net.join(code) }
    // Host: start the session's game on this seed
    function startGame(s) {
        game.masterSeed = s
        game._startMultiplayerGame()
    }
    function leave() { if (net) net.leave() }

    function _byId() {
        let m = {}
        for (let e of game.enemies)
            if (e && !e.destroyed) m[e.objectId] = e
        return m
    }
    // Every enemy as {id: [x, y, hp, aiState, remote]}
    function enemies() {
        let m = _byId(), out = {}
        for (let id in m) {
            let e = m[id]
            out[id] = [r3(e.xWu), r3(e.yWu), e.hp, e.aiState, e.remote]
        }
        return out
    }
    function hpOf(id) { let e = _byId()[id]; return e ? e.hp : -1 }
    function r3(v) { return Math.round(v * 1000) / 1000 }

    // The knight a step beside enemy id, facing it; the knights cannot fall
    function placeBeside(id) {
        let e = _byId()[id], p = game.player
        if (!e || !p) return false
        p.hp = 100000
        p.xWu = e.xWu + 1
        p.yWu = e.yWu
        _face(p, e)
        return true
    }
    // This node's knight against enemy id, for a hit that did not land
    function knightAt(id) {
        let e = _byId()[id], p = game.player
        if (!p) return {}
        return {x: r3(p.xWu), y: r3(p.yWu), facing: r3(p.facingAngle), attacking: p.isAttacking,
                cooldown: r3(p.attackCooldown), inRange: e ? p.enemiesInRange.has(e) : false,
                dist: e ? r3(Math.hypot(e.xWu - p.xWu, e.yWu - p.yWu)) : -1,
                enemyState: e ? e.aiState : ""}
    }
    // The scripted hit: a step beside enemy id, walking into it, one swing.
    // Walking, not standing: a knight at rest sleeps in Box2D, and a
    // joiner's enemy, moved by its position only, does not wake it, so the
    // swing sensor would not see it (clayground#369)
    function strike(id) {
        if (!placeBeside(id)) return false
        let p = game.player, e = _byId()[id]
        // moveY is screen down, world y is up
        p.moveX = (e.xWu - p.xWu) > 0 ? 1 : -1
        p.moveY = 0
        p.attack()
        _strikeStop.restart()
        return true
    }
    Timer { id: _strikeStop; interval: 300; onTriggered: if (game.player && !bench.fighting) bench._stand(game.player) }

    // ---- the fight: each knight goes for the nearest enemy ----
    property bool fighting: false
    function fight(on) { fighting = on; if (!on && game.player) _stand(game.player) }

    function _face(p, e) {
        p.facingAngle = Math.atan2(e.yWu - p.yWu, e.xWu - p.xWu) * 180 / Math.PI
    }
    function _stand(p) { p.moveX = 0; p.moveY = 0 }
    function _pilot() {
        let p = game.player
        if (!p || p.fallen) return
        let best = null, bestD = Infinity
        for (let e of game.enemies) {
            if (!e || e.destroyed) continue
            let dx = e.xWu - p.xWu, dy = e.yWu - p.yWu
            let d = Math.sqrt(dx * dx + dy * dy)
            if (d < bestD) { bestD = d; best = e }
        }
        if (!best) { _stand(p); return }
        _face(p, best)
        if (bestD > 1.2) {
            // moveY is screen down, world y is up
            p.moveX = (best.xWu - p.xWu) / bestD
            p.moveY = -(best.yWu - p.yWu) / bestD
        } else {
            _stand(p)
        }
        if (bestD <= p.attackRange * 0.9) p.attack()
    }

    // ---- the record: every enemy on this screen, every frame ----
    property bool recording: false
    property var _samples: []
    function record(on) { recording = on; _samples = []; _passed = {} }
    // The AI states and HPs each enemy took since the last frame: one can
    // last less than a frame (a lunge lands and a blow staggers it at once)
    // and still be sent, and so be shown by the other screen
    property var _hooked: ({})
    property var _passed: ({})
    function _note(id, key, v) {
        let p = _passed[id] || (_passed[id] = {s: [], h: []})
        p[key].push(v)
    }
    function _hook() {
        for (let e of game.enemies) {
            if (!e || e.destroyed || e.objectId === "" || _hooked[e.objectId]) continue
            let id = e.objectId, en = e
            _hooked[id] = true
            en.aiStateChanged.connect(() => bench._note(id, "s", en.aiState))
            en.hpChanged.connect(() => bench._note(id, "h", en.hp))
        }
    }
    // One record: enemies() plus, per enemy, the states and HPs it took
    // since the last record
    function _recordFrame() {
        let e = enemies()
        for (let id in e) {
            let p = _passed[id]
            e[id].push(p ? p.s : [], p ? p.h : [])
        }
        _passed = {}
        _hook()
        let s = {t: Date.now(), e: e}
        let d = renderDelayMs()
        if (d >= 0) s.d = d
        _samples.push(s)
    }
    // The samples since the last take, as [{t, e: _recordFrame's}]; a joiner's
    // also carry d, the delay in ms its enemies are rendered with (50 ms
    // plus the round trip, Enemy.qml)
    function take() {
        let s = _samples
        _samples = []
        return s
    }

    FrameAnimation {
        running: bench.fighting || bench.recording
        onTriggered: {
            if (bench.fighting) bench._pilot()
            if (bench.recording) bench._recordFrame()
        }
    }

    // The delay a joiner's enemies are rendered with; -1 without one
    function renderDelayMs() {
        let r = _replicaOf(game.enemies.find(e => e && !e.destroyed && e.remote))
        return r ? r.interpolator.delayMs : -1
    }
    function _replicaOf(e) {
        if (!e) return null
        for (let i = 0; i < e.data.length; i++)
            if (typeof e.data[i]._receive === "function") return e.data[i]
        return null
    }

    // ---- fault "stale": the joiner applies none of the host's enemy states ----
    function stale() {
        let n = 0
        for (let e of game.enemies) {
            if (!e || !e.remote) continue
            let r = _replicaOf(e)
            if (r) { r.properties = []; n++ }
        }
        return n
    }
}
