// Same-world bench - one of two game instances, a host or a joiner, that
// run_sameworld.py starts as two processes (clayliveloader --instance),
// connects over Local or Cloud signaling and drives through the inspector
// protocol (issues #14, #17 and #18).
//
// The instance runs the real game. Once the session is in the dungeon the
// driver puts the host's knight beside an enemy and the joiner's in sight of
// another. The joiner's knight stands until that enemy walks into its reach
// and swings, parries it, blocks and dodges its lunges, blocks, dodges and
// takes a spitter's shots, shield-pushes it; then each knight kills an
// enemy, and both fight: each goes for the nearest enemy and swings at it.
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
    // [wall clock, enemy id, result, knight's HP after, HP it lost]
    // (Game.knightStruck)
    property var blows: []
    property int _hpPrev: 0
    property int _hpNow: 0
    // This node's knight's HP over time, as [wall clock, HP]
    property var hpLog: []
    Connections {
        target: game
        function onKnightStruck(enemyId, result) {
            let landed = result === "hit" || result === "blocked"
            bench.blows.push([Date.now(), enemyId, result, bench._hpNow, landed ? bench._hpPrev - bench._hpNow : 0])
        }
    }
    Connections {
        target: game.player
        function onHpChanged() {
            bench._hpPrev = bench._hpNow
            bench._hpNow = game.player.hp
            bench.hpLog.push([Date.now(), game.player.hp])
        }
    }
    // Host: every blow another node's knight sent, as [wall clock, enemy
    // id, kind, what it was on this screen when it arrived]
    // (Session.enemyBlowReceived); a push's carries its direction (dx, dy),
    // the enemy's position and the sender's knight's as this screen shows
    // them
    property var received: []
    Connections {
        target: bench.session
        function onEnemyBlowReceived(fromId, blow) {
            let e = bench._byId()[blow.id], k = bench.session.remotePlayers[fromId]
            let at = blow.kind !== "push" ? null
                   : {dx: bench.r3(blow.dx), dy: bench.r3(blow.dy),
                      enemy: e ? [bench.r3(e.xWu), bench.r3(e.yWu)] : null,
                      knight: k ? [bench.r3(k.xWu), bench.r3(k.yWu)] : null}
            bench.received.push([Date.now(), blow.id, blow.kind, at])
        }
    }
    // Every attack another node's knight met and its node judged, as [wall
    // clock, node id, source, id, result] (Game.struckReported)
    property var reports: []
    // Every shot that met a knight on this screen, as [wall clock, shot id,
    // result, local, knight] (Game.shotEnded); knight is this node's knight
    // then: {blocking, dashing, grace, facing, spitter: the angle to the
    // guarded enemy, shot: the angle to the shot, on this screen's own}
    property var shotEnds: []
    Connections {
        target: game
        function onStruckReported(nodeId, source, id, result) {
            bench.reports.push([Date.now(), nodeId, source, id, result])
        }
        function onShotEnded(shotId, result, local) {
            let p = game.player, e = bench._byId()[bench.guardId], s = game._shotById[shotId]
            let k = p ? {blocking: p.isBlocking, dashing: p.isDashing, grace: bench.r3(p.graceLeft),
                         facing: bench.r3(p.facingAngle),
                         spitter: e ? bench.r3(bench._angleTo(p, e)) : null,
                         shot: local && s ? bench.r3(bench._angleTo(p, s)) : null,
                         at: [bench.r3(p.xWu), bench.r3(p.yWu)], from: e ? [bench.r3(e.xWu), bench.r3(e.yWu)] : null,
                         shotAt: s ? [bench.r3(s.xWu), bench.r3(s.yWu)] : null}
                      : null
            bench.shotEnds.push([Date.now(), shotId, result, local, k])
        }
    }
    // The shots flying on this screen, as {id: [x, y]}
    function shots() {
        let out = {}
        for (let id in game._shotById) {
            let s = game._shotById[id]
            if (s && !s.destroyed) out[id] = [r3(s.xWu), r3(s.yWu)]
        }
        return out
    }
    // Host: the HP this screen shows for the other node's knight, as [wall
    // clock, HP]; HP -1 without
    function remoteHp() {
        for (let id in session.remotePlayers) return [Date.now(), session.remotePlayers[id].remoteHp]
        return [Date.now(), -1]
    }
    // Seconds left of this node's knight's grace after a hit
    function graceLeft() { return game.player ? game.player.graceLeft : 0 }
    // Host: every enemy stops thinking (on) or thinks again (off), so the
    // spitter only spits when spit() says and no other enemy strikes the
    // knight meanwhile
    function hold(on) {
        for (let e of game.enemies) {
            if (!e || e.destroyed) continue
            if (on) {
                e.halt()
            } else if (e.halted) {
                e.halted = false
                e.aiState = "patrol"
            }
        }
    }
    // Host: enemy id spits at the other node's knight, or at its own with
    // own; the shot's id, "" without either
    function spit(id, own) {
        let e = _byId()[id], k = own ? game.player : null
        if (!own) for (let n in session.remotePlayers) k = session.remotePlayers[n]
        if (!e || !k) return ""
        let dx = k.xWu - e.xWu, dy = k.yWu - e.yWu
        let len = Math.max(0.01, Math.hypot(dx, dy))
        e._dirToTargetX = dx / len
        e._dirToTargetY = dy / len
        e.fireProjectile()
        return "shot" + game._shotCount
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
    // Host: enemy id dies as if this node's knight killed it
    function kill(id) {
        let e = _byId()[id]
        if (!e) return false
        e.hp = 0
        e.die("")
        return true
    }
    // This node's knight's reach, by its sensor: [enemy id or "dead", ...]
    // in the order it entered
    function reach() {
        let p = game.player, out = []
        if (!p) return out
        for (let e of p.enemiesInRange) out.push(e && e.destroyed === false ? e.objectId : "dead")
        return out
    }
    // Whether enemy id is in this node's knight's reach, by its sensor
    function inReach(id) {
        let e = _byId()[id], p = game.player
        return !!(e && p && p.enemiesInRange.has(e))
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
    // d Wu and no nearer than near Wu (2 without), facing it; false where it
    // sees no spot
    function standOff(id, d, near) {
        let e = _byId()[id], p = game.player
        if (!e || !p) return false
        for (let r = d; r >= (near || 2); r -= 0.5) {
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
    // and dashes into it once it is in reach; "block": holds the shield up
    // toward it; "dodge": dashes at it from its parry window's late-th
    // frame on this screen, once; "dodgeShot": dashes into shot shotToDodge
    // once it comes within 1.2 Wu, once; "stand": faces it and stands, the
    // shield down. The knight never walks. The log says what it did: when
    // (wall clock), how it stood and what it saw.
    property string guardMode: ""
    property string guardId: ""
    property var guardLog: ({})
    property string shotToDodge: ""
    function guard(id, mode, late) {
        guardId = id
        shotToDodge = ""
        guardMode = mode
        guardLog = {mode: mode, slept: false, done: false, parriesBefore: game.fightRecord.parries,
                    late: late || 1, windowFrames: 0}
        if (game.player) {
            _stand(game.player)
            game.player.isBlocking = mode === "block"
        }
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
            log.reach = reach()
            log.dash = []
            p.mana = p.maxMana
            p.isBlocking = true
            p.dash()
            guardMode = "pushing"
            _shieldDown.restart()
        } else if (guardMode === "block") {
            p.mana = p.maxMana
            p.isBlocking = true
        } else if (guardMode === "dodge" && !e.parryWindow) {
            log.windowFrames = 0
        } else if (guardMode === "dodge" && ++log.windowFrames >= log.late && p.dashCooldown <= 0) {
            log.dodge = what
            p.dash()
            guardMode = ""
        } else if (guardMode === "dodgeShot" && p.dashCooldown <= 0) {
            // Centre to centre: at 40 Wu/s a dash aimed beside the shot
            // passes it between two steps without touching it
            let s = game._shotById[shotToDodge]
            if (s && !s.destroyed && _distTo(p, s) <= 1.2) {
                _face(p, s)
                log.dodge = Object.assign({shot: shotToDodge}, what)
                p.dash()
                guardMode = ""
            }
        } else if (guardMode === "pushing") {
            // What the knight does while the dash lasts
            log.dash.push([what.t, p.isDashing, p.isBlocking, inRange, what.dist])
            if (!p.isDashing) guardMode = ""
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

    // Facing thing e, centre to centre, as the shield measures it
    // (Player.isShieldFacing)
    function _face(p, e) { p.facingAngle = _angleTo(p, e) }
    function _angleTo(p, e) {
        let ex = e.xWu + e.widthWu / 2, ey = e.yWu - e.heightWu / 2
        let px = p.xWu + p.widthWu / 2, py = p.yWu - p.heightWu / 2
        return Math.atan2(ey - py, ex - px) * 180 / Math.PI
    }
    function _distTo(p, e) {
        return Math.hypot(e.xWu + e.widthWu / 2 - p.xWu - p.widthWu / 2,
                          e.yWu - e.heightWu / 2 - p.yWu + p.heightWu / 2)
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
        let dd = renderDelays()
        if (Object.keys(dd).length > 0) s.dd = dd
        _samples.push(s)
    }
    // The samples since the last take, as [{t, e: _recordFrame's}]; a joiner's
    // also carry d, the delay in ms its enemies are rendered with, and dd,
    // each enemy's own by id (autoDelay sizes it per enemy, Enemy.qml)
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
            bench._seeShots()
        }
    }
    // The wall clock of the last frame that showed each shot, by its id
    property var shotSeen: ({})
    function _seeShots() {
        let now = Date.now()
        for (let id in game._shotById)
            if (game._shotById[id] && !game._shotById[id].destroyed) shotSeen[id] = now
    }

    // The delay a joiner's enemies are rendered with, in whole ms; -1
    // without one
    function renderDelayMs() {
        let e = game.enemies.find(e => e && !e.destroyed && e.remote)
        return e ? Math.round(e.renderDelayMs) : -1
    }
    // Each remote enemy's render delay in whole ms, by object id
    function renderDelays() {
        let out = {}
        for (let e of game.enemies)
            if (e && !e.destroyed && e.remote) out[e.objectId] = Math.round(e.renderDelayMs)
        return out
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
