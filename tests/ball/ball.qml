// Ball bench - the slinger, a lead that slings metal balls which bounce
// (issue #322).
//
// Alone, stepped on the physics clock: in the spitter duel and in the ball
// duel at spawn.slingerDepth the slinger looks unlike the spitter - a body
// with rounded corners, iron, a visor's slit for its one eye - and is a
// room's lead with its stance bar. In the ball duel, the slinger halted: a
// ball slung across the room bounces off its walls Balance.ball.bounces
// times, each bounce where the mirror path off the walls puts it, and
// falls at the next wall, plays its shot, a bounce per wall and its fall,
// and is gone restTime later. A ball no shield has touched passes an
// enemy unhurt and hurts the knight for the slinger's atk less its
// defense, and falls there; a knight in a dash lets it through, unhurt,
// and it flies on. A plain raised shield bounces it at least ball.glance
// degrees off the line it came along, at its speed, for the shield's
// mana, the knight unhurt; a perfect block sends it along the way the
// knight faces at ball.backSpeed, and into the slinger standing that way:
// it hurts it for ball.backDamage times the knight's swing less its
// defense, the blow whole, and opens it (cause "ball"); the fight record
// counts both bounces, the aimed one and the hit.
// In a session, a host and a joiner joined over LAN in one process: a
// ball the host slings bounces off the same walls at the same places on
// both screens and falls at the same place; one the joiner's knight's
// raised shield bounces is turned on the host's screen too, from the same
// place the same way, and the host's lead it meets loses the blow once,
// opens on the host's screen, and the ball falls on both; no knight is
// hurt. Then the host's lead slings at the joiner's knight (issue #364):
// a ball its raised shield bounces wears the host's lead's stance by
// Balance.lead.blockWear, and one that hits the knight steadies it by
// Balance.lead.steady, the joiner's screen telling the host. Muted. Prints one PASS or FAIL line per check and exits with the
// number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/ball/ball.qml

import QtQuick
import QtQuick.Window
import Clayground.Common
import Clayground.Network
import "../../src"

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
    property int failures: 0
    property var gameComp: null

    function check(ok, what) {
        console.log("[Ball]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        gameComp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComp.status !== Component.Ready) {
            console.log("[Ball] FAIL", gameComp.errorString())
            Qt.exit(1)
            return
        }
        solo = gameComp.createObject(bench.contentItem, {width: 1000, height: 500, muted: true,
                                                         recordStoreName: "ShapesAndStoneBallBench"})
        follow(solo, soloSeen)
        script.start()
    }

    // ---- helpers ----
    readonly property real stepS: 1 / 60
    readonly property real r: Balance.ball.size / 2
    function alive(e) { return e && e.destroyed === false }
    function steps(n) {
        for (let i = 0; i < n; i++) Clayground.physicsStep(1)
    }
    function centreOf(o) { return {x: o.xWu + o.widthWu / 2, y: o.yWu - o.heightWu / 2} }
    // o put with its centre at (x, y), at rest
    function put(o, x, y) {
        o.xWu = x - o.widthWu / 2
        o.yWu = y + o.heightWu / 2
        if (o.body) o.body.linearVelocity = Qt.point(0, 0)
    }
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
    function deg(dx, dy) { return Math.atan2(dy, dx) * 180 / Math.PI }
    // The angle between two ways, in degrees
    function between(ax, ay, bx, by) {
        return Math.abs(Math.atan2(ax * by - ay * bx, ax * bx + ay * by)) * 180 / Math.PI
    }
    function ballOf(g, id) { return g._ballById[id] || null }

    // What a game said of its balls: bounces, turns and falls by ball id
    property var soloSeen: ({bounces: {}, turned: {}, fell: {}})
    property var hostSeen: ({bounces: {}, turned: {}, fell: {}})
    property var joinSeen: ({bounces: {}, turned: {}, fell: {}})
    function follow(g, seen) {
        g.ballBounced.connect((id, n, x, y) => {
            if (!seen.bounces[id]) seen.bounces[id] = []
            seen.bounces[id].push({n: n, x: x, y: y})
        })
        g.ballTurned.connect((id, by, local, dx, dy) => seen.turned[id] = {by: by, local: local, dx: dx, dy: dy})
        g.ballFell.connect((id, how, bounces, by, x, y) =>
            seen.fell[id] = {how: how, bounces: bounces, by: by, x: x, y: y})
    }

    // Where a ball from (x, y) along (dx, dy) touches the walls of a box
    // of [lo, hi] on both axes, its centre: its first n contacts, each
    // with the axis it meets ("x" or "y"), and the way flown to it
    function mirrorPath(x, y, dx, dy, lo, hi, n) {
        let out = [], flown = 0
        for (let i = 0; i < n; i++) {
            let tx = dx > 0 ? (hi.x - x) / dx : dx < 0 ? (x - lo.x) / -dx : Infinity
            let ty = dy > 0 ? (hi.y - y) / dy : dy < 0 ? (y - lo.y) / -dy : Infinity
            let t = Math.min(tx, ty)
            x += dx * t
            y += dy * t
            flown += t
            let axis = tx <= ty ? "x" : "y"
            if (axis === "x") dx = -dx; else dy = -dy
            out.push({x: x, y: y, axis: axis, flown: flown})
        }
        return out
    }

    // ---- alone ----
    property var spitterLook: null
    function lookOf(e) {
        let body = find(e, "enemyBody"), eyes = find(e, "enemyEyes")
        e.halt()
        e.aiState = "patrol"
        let look = {round: body ? body.radius / body.width : -1, color: body ? String(body.color) : "",
                    slit: eyes ? eyes.slit === true : false}
        // Patrolling it would walk off: it stands again
        e.halt()
        return look
    }
    function soloSpitter() {
        Clayground.paused = true
        let e = solo.enemies.find(x => alive(x) && x.enemyType === "spitter")
        spitterLook = e ? lookOf(e) : null
        Clayground.paused = false
    }

    function soloBall() {
        let g = solo, p = g.player
        Clayground.paused = true
        let e = g.enemies.find(x => alive(x) && x.enemyType === "slinger")
        check(!!e, "the ball duel stands a slinger")
        if (!e) { Clayground.paused = false; return }
        // Its look, beside the spitter's
        let look = lookOf(e)
        let bar = find(e, "stanceBar")
        check(!!spitterLook && look.round < 0.3 && spitterLook.round === 0.5 && look.color !== spitterLook.color
              && look.slit && !spitterLook.slit,
              "the slinger looks unlike a spitter: corners " + look.round.toFixed(2) + " of its width round (the spitter "
              + (spitterLook ? spitterLook.round : "-") + "), " + look.color + " where the spitter is "
              + (spitterLook ? spitterLook.color : "-") + ", one slit for an eye (" + look.slit + ")")
        check(e.lead && e.tier === 2 && e.ranged && !!bar && bar.visible && e.crushChance === 0,
              "it is a room's lead, its stance bar shown, a shooter that winds up no crushing blow")

        let cx = g._fightRoomCx, cy = g._fightRoomCy, half = 15 * g.cellSize / 2
        p.maxHp = 100000
        p.hp = 100000
        p.maxMana = 1000
        p.mana = 1000
        put(e, cx - half + 2, cy + half - 2)
        put(p, cx, cy)
        steps(2)

        // 1. Across the room: its bounces where the mirror path puts them,
        // then it falls at the next wall. The knight lets it pass (its
        // grace after a hit)
        g.logSounds = true
        g.clearSoundLog()
        p.graceLeft = 1e6
        // Where it hears the shot and the first bounce
        put(p, cx + 4, cy + 5)
        let from = {x: cx - 6, y: cy - 3}, len = Math.hypot(0.8, 0.6)
        let dir = {x: 0.8 / len, y: 0.6 / len}
        let lo = {x: cx - half + r, y: cy - half + r}, hi = {x: cx + half - r, y: cy + half - r}
        let path = mirrorPath(from.x, from.y, dir.x, dir.y, lo, hi, Balance.ball.bounces + 1)
        let b = g.spawnBall(from.x, from.y, dir.x, dir.y, e.atk)
        let id = b.ballId
        // Fast enough to reach its last wall in its time
        b.speed = Math.max(Balance.ball.speed, path[path.length - 1].flown / (Balance.ball.lifetime * 0.8))
        let tol = b.speed * stepS + 1e-3
        let k = 0
        while (!soloSeen.fell[id] && k < 1200) { steps(1); k++ }
        let got = soloSeen.bounces[id] || []
        let off = []
        got.forEach((h, i) => {
            let w = path[i]
            let onAxis = w.axis === "x" ? Math.abs(h.x - w.x) : Math.abs(h.y - w.y)
            let across = w.axis === "x" ? Math.abs(h.y - w.y) : Math.abs(h.x - w.x)
            if (onAxis > 1e-3 || across > tol) off.push(i + 1)
        })
        check(got.length === Balance.ball.bounces && off.length === 0,
              "a ball across the room bounces " + got.length + " times off its walls ("
              + Balance.ball.bounces + " by the table), each where the mirror path puts it ("
              + got.map(h => "(" + h.x.toFixed(2) + ", " + h.y.toFixed(2) + ")").join(", ")
              + (off.length ? "; off at " + off.join(", ") : "") + ")")
        let f = soloSeen.fell[id], last = path[path.length - 1]
        let fellOff = f ? (last.axis === "x" ? Math.abs(f.x - last.x) : Math.abs(f.y - last.y)) : 1e9
        check(!!f && f.how === "wall" && f.bounces === Balance.ball.bounces && fellOff <= 1e-3,
              "after them it falls at the next wall it meets (" + (f ? f.how + " after " + f.bounces
              + " bounces at (" + f.x.toFixed(2) + ", " + f.y.toFixed(2) + ")" : "it never fell") + ", the wall at ("
              + last.x.toFixed(2) + ", " + last.y.toFixed(2) + "))")
        steps(Math.ceil(Balance.ball.restTime / stepS) + 2)
        check(!ballOf(g, id),
              "fallen, it lies " + Balance.ball.restTime + " s and is gone")
        // Heard where the knight hears it: within the game's hearing
        let hears = (x, y) => Math.hypot(x - p.xWu, y - p.yWu) < g.remoteHearingWu
        let wantBounces = got.filter(h => hears(h.x, h.y)).length
        let wantFall = f && hears(f.x, f.y) ? 1 : 0
        let wantShot = hears(from.x, from.y) ? 1 : 0
        let heard = g.soundLog.filter(x => x.cue.indexOf("sfx/ball_") === 0)
        let shots = heard.filter(x => x.what === "ballShot").length
        let bounced = heard.filter(x => x.what === "bounce" && x.pitch === 0).length
        let fell = heard.filter(x => x.what === "fall" && x.pitch === Balance.ball.fallPitch).length
        check(shots === wantShot && wantShot === 1 && bounced === wantBounces && wantBounces > 0 && fell === wantFall,
              "it plays its shot once, a bounce for every wall within the knight's hearing and its fall "
              + Balance.ball.fallPitch + " semitones down (shot " + shots + " of " + wantShot + ", bounce " + bounced + " of "
              + wantBounces + ", fall " + fell + " of " + wantFall + ")")
        g.logSounds = false
        p.graceLeft = 0
        put(p, cx, cy)

        // 2. A ball no shield has touched: through an enemy unhurt, into
        // the knight, which it hurts, and it falls there
        g.spawnEnemy(cx + 2.5, cy + 0.4, 1, "grunt")
        let grunt = g.enemies.find(x => alive(x) && x.enemyType === "grunt")
        if (grunt) { grunt.halt(); put(grunt, cx + 2.5, cy) }
        steps(2)
        p.isBlocking = false
        p.graceLeft = 0
        let hp = p.hp, ghp = grunt ? grunt.hp : -1
        b = g.spawnBall(cx + 5, cy, -1, 0, e.atk)
        id = b.ballId
        k = 0
        while (!soloSeen.fell[id] && k < 120) { steps(1); k++ }
        f = soloSeen.fell[id]
        let want = Math.max(Balance.minDamage, e.atk - p.def)
        check(!!grunt && grunt.hp === ghp && hp - p.hp === want && !!f && f.how === "knight",
              "a ball no shield has touched passes an enemy unhurt (HP " + ghp + " -> " + (grunt ? grunt.hp : "-")
              + ") and hurts the knight for the slinger's atk " + e.atk + " less its defense, " + want
              + " (lost " + (hp - p.hp) + "), and falls there (" + (f ? f.how : "flies on") + ")")
        if (grunt) put(grunt, cx - half + 2, cy - half + 2)
        steps(Math.ceil(Balance.knight.hurtGrace / stepS) + 2)

        // 3. A knight in a dash lets it through, and it flies on
        hp = p.hp
        b = g.spawnBall(cx + 3, cy, -1, 0, e.atk)
        id = b.ballId
        // A dash on the spot, long enough for the ball to pass
        p._dashDirX = 0
        p._dashDirY = 0
        p._dashTimer = 100
        p.isDashing = true
        steps(Math.ceil(4 / Balance.ball.speed / stepS))
        p.isDashing = false
        p._dashTimer = 0
        check(hp === p.hp && !soloSeen.fell[id] && alive(b) && b.centreX < cx - 0.5,
              "a knight in a dash lets it through unhurt (HP " + hp + " -> " + p.hp + "), and it flies on ("
              + (soloSeen.fell[id] ? "fell" : "at " + b.centreX.toFixed(2)) + ")")
        if (alive(b)) b.vanish()

        // 4. A plain raised shield: off at least glance degrees from the line
        // it came along, at its speed, for the shield's mana
        put(p, cx, cy)
        p.facingAngle = 0
        p.isBlocking = true
        steps(Balance.knight.perfectBlockFrames + 4)
        p.mana = 1000
        hp = p.hp
        let rec = {back: g.fightRecord.ballsBack, aimed: g.fightRecord.ballsAimed, hits: g.fightRecord.ballBackHits}
        b = g.spawnBall(cx + 4, cy, -1, 0, e.atk)
        id = b.ballId
        k = 0
        let manaBefore = p.mana
        while (!soloSeen.turned[id] && k < 120) { p.isBlocking = true; manaBefore = p.mana; steps(1); k++ }
        let spent = manaBefore - p.mana
        let t = soloSeen.turned[id]
        let off1 = t ? between(t.dx, t.dy, 1, 0) : 0
        check(!!t && t.by === "blocked" && t.local && off1 >= Balance.ball.glance - 1e-6
              && Math.abs(b.speed - Balance.ball.speed) < 1e-6 && b.back,
              "a plain raised shield bounces it " + off1.toFixed(1) + " degrees off the line it came along (at least "
              + Balance.ball.glance + "), at its speed " + b.speed + " (" + (t ? t.by : "not turned") + ")")
        let drain = Balance.knight.blockDrain * stepS
        check(hp === p.hp && spent >= Balance.knight.blockMana - 1e-6 && spent <= Balance.knight.blockMana + drain + 1e-6,
              "the knight is unhurt (HP " + hp + " -> " + p.hp + ") and pays the shield's "
              + Balance.knight.blockMana + " mana on the step it bounces (" + spent.toFixed(2) + ")")
        if (alive(b)) b.vanish()

        // 5. A perfect block: along the way the knight faces, at backSpeed,
        // into the slinger standing that way, which opens
        p.isBlocking = false
        steps(Balance.knight.perfectBlockRearm + 4)
        let aim = 20, rad = aim * Math.PI / 180
        put(e, cx + 6 * Math.cos(rad), cy + 6 * Math.sin(rad))
        e._setStance(1)
        let causes = []
        e.opened.connect(c => causes.push(c))
        p.facingAngle = aim
        p.mana = 500
        let manaAt = 500
        hp = p.hp
        let ehp = e.hp
        b = g.spawnBall(cx + 4, cy, -1, 0, e.atk)
        id = b.ballId
        k = 0
        while (!soloSeen.turned[id] && k < 120) {
            let c = centreOf(p)
            if (Math.hypot(b.centreX - c.x, b.centreY - c.y) < 0.9) p.isBlocking = true
            manaAt = p.mana
            steps(1)
            k++
        }
        t = soloSeen.turned[id]
        let off2 = t ? between(t.dx, t.dy, Math.cos(rad), Math.sin(rad)) : 180
        check(!!t && t.by === "perfect" && off2 < 1e-6 && Math.abs(b.speed - Balance.ball.backSpeed) < 1e-6,
              "a perfect block sends it along the way the knight faces, " + aim + " degrees (" + (t ? deg(t.dx, t.dy).toFixed(2)
              : "-") + "), at backSpeed " + Balance.ball.backSpeed + " (" + b.speed + ", " + (t ? t.by : "not turned") + ")")
        let gained = p.mana - manaAt
        check(hp === p.hp && gained >= Balance.knight.perfectBlockMana - drain - 1e-6,
              "the knight is unhurt and gains the perfect block's mana (HP " + hp + " -> " + p.hp + ", +"
              + gained.toFixed(2) + " on the step it bounces, " + Balance.knight.perfectBlockMana + " by the table)")
        p.isBlocking = false
        k = 0
        while (!soloSeen.fell[id] && k < 120) { steps(1); k++ }
        f = soloSeen.fell[id]
        want = Math.max(Balance.minDamage, Math.round(p.atk * Balance.ball.backDamage) - e.def)
        check(!!f && f.how === "enemy" && ehp - e.hp === want && causes.join() === "ball" && e.opening,
              "it hurts the slinger it meets for backDamage times the swing " + p.atk + " less its defense, " + want
              + ", the blow whole (lost " + (ehp - e.hp) + "), and opens it (" + (causes.join() || "not opened") + "; "
              + (f ? f.how : "it never fell") + ", the slinger at (" + e.centreXWu.toFixed(2) + ", " + e.centreYWu.toFixed(2) + "))")
        // 6. Fallen here, then turned by another screen's report (it came
        // late, as over a network): it gets up and flies on that way, not
        // faded and not gone after its rest
        b = g.spawnBall(cx - 4, cy - 4, 0, -1, e.atk)
        id = b.ballId
        steps(2)
        b.fallAt(b.centreX, b.centreY, "report")
        steps(10)
        g._ballReported({source: "ball", id: id, result: "blocked", x: cx - 4, y: cy - 4, dx: 0, dy: 1})
        steps(Math.ceil(Balance.ball.restTime / stepS) + 6)
        let look2 = alive(b) ? find(b, "ballLook") : null
        check(alive(b) && ballOf(g, id) === b && !b.fallen && b.back && b.dirY > 0.999 && b.centreY > cy - 4 + 1
              && !!look2 && look2.opacity === 1,
              "a ball that fell here and is then reported turned by another screen gets up: "
              + Balance.ball.restTime + " s later it is " + (alive(b) ? (b.fallen ? "fallen" : "flying")
              + " the reported way (" + b.dirX.toFixed(2) + ", " + b.dirY.toFixed(2) + "), at opacity "
              + (look2 ? look2.opacity : "-") : "gone"))
        if (alive(b)) b.vanish()
        let r2 = g.fightRecord
        check(r2.ballsBack === rec.back + 2 && r2.ballsAimed === rec.aimed + 1 && r2.ballBackHits === rec.hits + 1,
              "the fight record counts the two bounces, the aimed one and its hit (" + (r2.ballsBack - rec.back) + ", "
              + (r2.ballsAimed - rec.aimed) + ", " + (r2.ballBackHits - rec.hits) + ")")
        Clayground.paused = false
    }

    // ---- the session's Network, found by what it offers ----
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
    function byId(game) {
        let m = {}
        for (let e of game.enemies)
            if (alive(e)) m[e.objectId] = e
        return m
    }
    function startSession() {
        host = gameComp.createObject(bench.contentItem, {width: 500, height: 500, muted: true,
                                                         recordStoreName: "ShapesAndStoneBallBench"})
        joiner = gameComp.createObject(bench.contentItem, {x: 500, width: 500, height: 500, muted: true,
                                                           recordStoreName: "ShapesAndStoneBallBench"})
        follow(host, hostSeen)
        follow(joiner, joinSeen)
        hostNet = network(host)
        joinNet = network(joiner)
        hostNet.signalingMode = Network.SignalingMode.Local
        hostNet.host()
    }
    // The host's knight's centre when the run began, in the start room
    property var base: null
    property string sessionBall: ""
    property string leadId: ""
    property int leadHp: 0
    property var leadCauses: []
    property var hp0: null
    // The host's lead's stance before a ball it slung met the joiner's
    // knight, and the joiner's HP then (issue #364)
    property real leadStance: 0
    property int joinerHp: 0
    // The joiner's knight at base, its shield raised facing right; the
    // host's knight below it; the lead standing where the shield sends a
    // ball coming from the right; both knights in a long grace, so a ball
    // that misses the shield passes
    function lineUp() {
        let jp = joiner.player, hp = host.player
        put(jp, base.x, base.y)
        put(hp, base.x, base.y - 3)
        jp.facingAngle = 0
        jp.isBlocking = true
        jp.mana = jp.maxMana
        let lead = byId(host)[leadId]
        if (lead) {
            let a = Balance.ball.glance * Math.PI / 180, touch = 0.5 + r
            put(lead, base.x + touch + 3 * Math.cos(a), base.y + 3 * Math.sin(a))
        }
    }

    property var soloSteps: [
        [() => solo.screen === "title", () => solo.applyScenario("spitterduel", Balance.spawn.slingerDepth)],
        [() => solo.player && solo.fightRoomActive && solo.enemies.some(e => alive(e) && e.enemyType === "spitter"),
         () => soloSpitter()],
        [100, () => solo.applyScenario("ballduel", Balance.spawn.slingerDepth)],
        [() => solo.player && solo.fightRoomActive && solo.enemies.some(e => alive(e) && e.enemyType === "slinger"),
         () => soloBall()],
        [100, () => { solo.destroy(); solo = null }],
        [300, () => startSession()]
    ]
    property var sessionSteps: [
        [() => hostNet.networkId !== "", () => joinNet.join(hostNet.networkId)],
        [() => hostNet.connected && joinNet.connected && hostNet.nodeCount >= 2, () => {
            host.masterSeed = 424242
            host._startMultiplayerGame()
        }],
        [() => host.player && joiner.player && host.screen === "game" && joiner.screen === "game"
               && host.enemies.length >= 1 && joiner.enemies.length === host.enemies.length, () => {
            let h = byId(host)
            for (let id in h) h[id].halt()
            let ids = Object.keys(h).filter(id => !h[id].boss)
            leadId = ids[0] || ""
            check(leadId !== "", "the host runs an enemy to make a lead of")
            if (leadId) {
                h[leadId].lead = true
                h[leadId].maxHp = 10000
                h[leadId].hp = 10000
                h[leadId]._setStance(1)
                h[leadId].opened.connect(c => bench.leadCauses.push(c))
            }
            host.player.maxHp = 100000; host.player.hp = 100000
            joiner.player.maxHp = 100000; joiner.player.hp = 100000
            host.player.graceLeft = 1e6
            joiner.player.graceLeft = 1e6
            base = centreOf(host.player)
            // The knights out of the way, the lead aside: a ball from the
            // start room's middle bounces about
            put(host.player, base.x, base.y - 3)
            put(joiner.player, base.x, base.y + 3)
        }],
        [600, () => {
            hp0 = {host: host.player.hp, joiner: joiner.player.hp}
            let b = host.spawnBall(base.x + 0.3, base.y + 0.2, 0.8, 0.6, 10)
            sessionBall = b.ballId
        }],
        [() => hostSeen.fell[sessionBall] && joinSeen.fell[sessionBall], () => {
            let a = hostSeen.bounces[sessionBall] || [], b = joinSeen.bounces[sessionBall] || []
            let far = a.map((h, i) => b[i] ? Math.max(Math.abs(h.x - b[i].x), Math.abs(h.y - b[i].y)) : 1e9)
            let most = far.length ? Math.max.apply(null, far) : 0
            check(a.length === Balance.ball.bounces && b.length === a.length && most <= 0.3,
                  "a ball the host slings bounces " + a.length + " times on the host's screen and " + b.length
                  + " on the joiner's, at the same places (" + a.map(h => "(" + h.x.toFixed(2) + ", " + h.y.toFixed(2)
                  + ")").join(", ") + "; at most " + most.toFixed(3) + " wu apart)")
            let fh = hostSeen.fell[sessionBall], fj = joinSeen.fell[sessionBall]
            check(fh.how === "wall" && fj.how === "wall" && Math.hypot(fh.x - fj.x, fh.y - fj.y) <= 0.3,
                  "and falls at the same wall on both (" + fh.how + " at (" + fh.x.toFixed(2) + ", " + fh.y.toFixed(2)
                  + "), " + fj.how + " at (" + fj.x.toFixed(2) + ", " + fj.y.toFixed(2) + "))")
            host.player.graceLeft = 1e6
            joiner.player.graceLeft = 1e6
            lineUp()
        }],
        // The lead where the joiner's screen shows it too
        [600, () => lineUp()],
        [500, () => {
            lineUp()
            leadHp = byId(host)[leadId] ? byId(host)[leadId].hp : 0
            leadCauses = []
            joiner.player.graceLeft = 0
            let b = host.spawnBall(base.x + 4, base.y, -1, 0, 10)
            sessionBall = b.ballId
        }],
        [() => (joinSeen.fell[sessionBall] && hostSeen.fell[sessionBall]) || false, () => {}],
        // The joiner's blow on its way to the host
        [400, () => {
            let tj = joinSeen.turned[sessionBall], th = hostSeen.turned[sessionBall]
            check(!!tj && tj.local && tj.by === "blocked" && !!th && !th.local && th.by === "blocked"
                  && Math.abs(tj.dx - th.dx) < 1e-6 && Math.abs(tj.dy - th.dy) < 1e-6,
                  "a ball the joiner's knight's raised shield bounces turns on the host's screen too, the same way ("
                  + (tj ? deg(tj.dx, tj.dy).toFixed(2) : "-") + " / " + (th ? deg(th.dx, th.dy).toFixed(2) : "-") + " degrees)")
            let lead = byId(host)[leadId]
            let want = Math.max(Balance.minDamage, Math.round(joiner.player.atk * Balance.ball.backDamage)
                                - (lead ? lead.def : 0))
            check(!!lead && leadHp - lead.hp === want && leadCauses.join() === "ball",
                  "the host's lead it meets loses the blow once, " + want + " (lost " + (lead ? leadHp - lead.hp : "-")
                  + "), and opens (" + (leadCauses.join() || "not opened") + ")")
            let fj = joinSeen.fell[sessionBall], fh = hostSeen.fell[sessionBall]
            check(fj.how === "enemy" && (fh.how === "report" || fh.how === "enemy"),
                  "the ball falls there on both screens (" + fj.how + " / " + fh.how + ")")
            check(host.player.hp === hp0.host && joiner.player.hp === hp0.joiner,
                  "no knight is hurt (HP " + host.player.hp + ", " + joiner.player.hp + ")")
            // The lead stood again, its stance full, behind the joiner's
            // knight: a ball the shield bounces flies away from it
            let l = byId(host)[leadId]
            if (l) {
                l.halt()
                l._setStance(1)
            }
            lineUp()
            if (l) put(l, base.x - 4, base.y + 2)
        }],
        // A ball the host's lead slings, bounced by the joiner's shield
        [500, () => {
            lineUp()
            let l = byId(host)[leadId]
            if (l) put(l, base.x - 4, base.y + 2)
            joiner.player.graceLeft = 0
            leadStance = l ? l._stanceLeft : -1
            let b = host.spawnBall(base.x + 4, base.y, -1, 0, 10, 0, l)
            sessionBall = b.ballId
        }],
        [() => !!hostSeen.turned[sessionBall], () => {}],
        [300, () => {
            let l = byId(host)[leadId]
            let after = l ? l._stanceLeft : -1
            check(!!l && Math.abs(leadStance - after - Balance.lead.blockWear) < 1e-6 && !l.opening,
                  "a ball the host's lead slings and the joiner's raised shield bounces wears the lead's stance on "
                  + "the host from " + leadStance.toFixed(3) + " to " + after.toFixed(3) + " (lead.blockWear "
                  + Balance.lead.blockWear + ")")
            // Next its ball hits the joiner's knight, the stance worn first
            if (l) l._setStance(0.3)
            joiner.player.isBlocking = false
            joiner.player.graceLeft = 0
        }],
        [300, () => {
            let l = byId(host)[leadId]
            if (l) put(l, base.x - 4, base.y + 2)
            put(joiner.player, base.x, base.y)
            joiner.player.isBlocking = false
            joiner.player.graceLeft = 0
            leadStance = l ? l._stanceLeft : -1
            joinerHp = joiner.player.hp
            let b = host.spawnBall(base.x + 4, base.y, -1, 0, 10, 0, l)
            sessionBall = b.ballId
        }],
        [() => !!joinSeen.fell[sessionBall], () => {}],
        [300, () => {
            let l = byId(host)[leadId]
            let after = l ? l._stanceLeft : -1
            let want = Math.min(1, leadStance + Balance.lead.steady)
            check(!!l && joiner.player.hp < joinerHp && Math.abs(after - want) < 1e-6,
                  "one that hits the joiner's knight (" + (joinerHp - joiner.player.hp) + " HP) steadies the lead's "
                  + "stance on the host from " + leadStance.toFixed(3) + " to " + after.toFixed(3) + " (lead.steady "
                  + Balance.lead.steady + ")")
            hostNet.leave()
            joinNet.leave()
        }],
        // Torn down before quitting: the game crashes when Qt quits with it
        // still up, and the crash's exit code would hide the result
        [300, () => { host.destroy(); joiner.destroy() }],
        [300, () => {
            console.log("[Ball] done,", failures, "failed")
            Qt.exit(failures)
        }]
    ]
    readonly property var allSteps: soloSteps.concat(sessionSteps)

    Timer {
        id: script
        property int i: 0
        property real waitedMs: 0
        interval: 20
        repeat: true
        onTriggered: {
            let step = bench.allSteps[i]
            waitedMs += interval
            let ready = typeof step[0] === "number" ? waitedMs >= step[0] : step[0]()
            if (!ready) {
                if (waitedMs > 20000) {
                    console.log("[Ball] FAIL step", i, "timed out")
                    Qt.exit(failures + 100)
                    stop()
                }
                return
            }
            waitedMs = 0
            i++
            if (i >= bench.allSteps.length) stop()
            step[1]()
        }
    }
}
