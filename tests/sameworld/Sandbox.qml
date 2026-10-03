// Same-world bench - one of two game instances, a host or a joiner, that
// run_sameworld.py starts as two processes (clayliveloader --instance),
// connects over Local or Cloud signaling and drives through the inspector
// protocol (issues #14 and #17).
//
// The instance runs the real game. Once the session is in the dungeon the
// driver puts the host's knight beside an enemy and the joiner's in sight of
// another. The joiner's knight stands until that enemy walks into its reach
// and swings, parries it, shield-pushes it; then each knight kills an enemy,
// and both fight: each goes for the nearest enemy and swings at it.
// Meanwhile every frame records every enemy this screen shows - its object
// id, position, HP and AI state - stamped with the wall clock, and the
// driver takes the records and compares the two screens.
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

    // Every stain on this screen, as [x, y]
    function stains() {
        return game.stains.filter(s => s).map(s => [r3(s.xWu), r3(s.yWu)])
    }
    // Every host's blow on this node's knight and what became of it, as
    // [wall clock, enemy id, result] (Game.knightStruck)
    property var blows: []
    Connections {
        target: game
        function onKnightStruck(enemyId, result) { bench.blows.push([Date.now(), enemyId, result]) }
    }
    // How often each enemy entered "stagger" since record(true)
    property var staggers: ({})

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
    // The type of enemy id: grunt, guardian or spitter; "" without it
    function typeOf(id) { let e = _byId()[id]; return e ? e.enemyType : "" }
    // This node's knight as {x, y, hp, awake} plus its fight record's damage
    // dealt, parries and kills
    function knight() {
        let p = game.player, r = game.fightRecord
        if (!p) return {}
        return {x: r3(p.xWu), y: r3(p.yWu), hp: p.hp, awake: p.awake,
                dealt: r.damageDealt, parries: r.parries, kills: r.kills}
    }
    // The knight standing as far from enemy id as the enemy sees, up to
    // d Wu and no nearer than 2 Wu, facing it; false where it sees no spot
    function standOff(id, d) {
        let e = _byId()[id], p = game.player
        if (!e || !p) return false
        for (let r = d; r >= 2; r -= 0.5) {
            for (let k = 0; k < 8; k++) {
                let a = k * Math.PI / 4
                let x = e.xWu + Math.cos(a) * r, y = e.yWu + Math.sin(a) * r
                if (!game.hasLineOfSight(e.xWu, e.yWu, x, y)) continue
                p.hp = 100000
                p.xWu = x
                p.yWu = y
                _stand(p)
                _face(p, e)
                return true
            }
        }
        return false
    }

    // ---- the knight stands and answers one enemy (issue #17) ----
    // mode "swing": one swing once the enemy is in reach; "parry": swings
    // only into its parry window, from the window's late-th frame on this
    // screen, until one parry; "push": raises the shield
    // and dashes into it once it is in reach. The knight never walks. The
    // log says what it did: when (wall clock), how it stood and what it saw.
    property string guardMode: ""
    property string guardId: ""
    property var guardLog: ({})
    function guard(id, mode, late) {
        guardId = id
        guardMode = mode
        guardLog = {mode: mode, slept: false, done: false, parriesBefore: game.fightRecord.parries,
                    late: late || 1, windowFrames: 0}
        if (game.player) _stand(game.player)
        return _byId()[id] !== undefined
    }
    function _guard() {
        let p = game.player, e = _byId()[guardId]
        if (!p || !e) { guardMode = ""; return }
        let log = guardLog
        if (!p.awake) log.slept = true
        _face(p, e)
        let d = Math.hypot(e.xWu - p.xWu, e.yWu - p.yWu)
        let ready = p.attackCooldown <= 0 && !p.isAttacking
        let inRange = p.enemiesInRange.has(e)
        let what = {t: Date.now(), dist: r3(d), awake: p.awake, inRange: inRange,
                    knightHp: p.hp, enemyHp: e.hp, x: r3(p.xWu), y: r3(p.yWu),
                    ex: r3(e.xWu), ey: r3(e.yWu), state: e.aiState}
        if (guardMode === "swing" && ready && d <= p.attackRange * 0.8) {
            log.swing = what
            p.attack()
            guardMode = ""
        } else if (guardMode === "parry" && game.fightRecord.parries > log.parriesBefore) {
            // The knight's step judged the swing a parry
            log.parry = log.lastSwing
            log.parry.after = what
            guardMode = ""
        } else if (guardMode === "parry" && !e.parryWindow) {
            log.windowFrames = 0
        } else if (guardMode === "parry" && ++log.windowFrames < log.late) {
            // Late in the window as this screen shows it: the host's lunge
            // has landed by then, and its blow is on its way
        } else if (guardMode === "parry" && ready && d <= p.attackRange * 0.9) {
            log.lastSwing = what
            log.swings = (log.swings || 0) + 1
            p.attack()
        } else if (guardMode === "push" && p.dashCooldown <= 0 && inRange && d <= 1.6
                   && e.aiState !== "lunge" && e.aiState !== "telegraph") {
            log.push = what
            p.mana = p.maxMana
            p.isBlocking = true
            p.dash()
            guardMode = ""
            _shieldDown.restart()
        }
        log.done = guardMode === ""
        guardLog = log
    }
    Timer { id: _shieldDown; interval: 400; onTriggered: if (game.player) game.player.isBlocking = false }

    // ---- one knight goes for one enemy until it is gone ----
    property string huntId: ""
    function hunt(id) { huntId = id; return _byId()[id] !== undefined }

    // ---- the fight: each knight goes for the nearest enemy ----
    property bool fighting: false
    function fight(on) { fighting = on; if (!on && game.player) _stand(game.player) }

    function _face(p, e) {
        p.facingAngle = Math.atan2(e.yWu - p.yWu, e.xWu - p.xWu) * 180 / Math.PI
    }
    function _stand(p) { p.moveX = 0; p.moveY = 0 }
    // Each frame: toward the nearest enemy, or the hunted one, and swing
    // once it is in reach
    function _pilot(only) {
        let p = game.player
        if (!p || p.fallen) return
        let best = null, bestD = Infinity
        for (let e of game.enemies) {
            if (!e || e.destroyed || (only && e.objectId !== only)) continue
            let dx = e.xWu - p.xWu, dy = e.yWu - p.yWu
            let d = Math.sqrt(dx * dx + dy * dy)
            if (d < bestD) { bestD = d; best = e }
        }
        if (!best) {
            _stand(p)
            if (only) huntId = ""
            return
        }
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
    function record(on) { recording = on; _samples = []; _passed = {}; if (on) staggers = {} }
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
            en.aiStateChanged.connect(() => {
                bench._note(id, "s", en.aiState)
                if (en.aiState === "stagger") bench.staggers[id] = (bench.staggers[id] || 0) + 1
            })
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
        running: bench.fighting || bench.recording || bench.guardMode !== "" || bench.huntId !== ""
        onTriggered: {
            if (bench.guardMode !== "") bench._guard()
            else if (bench.huntId !== "") bench._pilot(bench.huntId)
            else if (bench.fighting) bench._pilot("")
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
