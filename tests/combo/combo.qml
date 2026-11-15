// Combo bench - a direction combo before the special's button fires the
// special's stronger version for the same mana (issue #320).
//
// Alone, stepped on the physics clock, the enemies' AI halted, in the flow
// scenario. First the pad's left stick alone, the right stick at rest and
// the aim the game's own, so the left stick aims as the knight walks, one
// physics step a turn of the event loop: right a while, then left (away),
// then right (towards) and R2 fire the stronger bolt, the aim held right
// through the push away; held left past Balance.combo.aimHold the knight
// turns round, and right then and R2 fire the normal bolt. Then, the
// knight aiming up: with the stun, the move keys away from
// the aim (S) for a few steps, then towards it (W), and Q fires the
// stronger stun (Balance.combo.stun) for the stun's mana - an enemy past
// the stun's reach and inside the stronger one's freezes, for the stronger
// freeze - the knight walking on every step of it, its name over the
// knight and the swell heard over the bash. The same combo with Q later
// than Balance.combo.window, the combo the other way round, and the combo
// with the moves away again after it fire the normal stun. With the bolt
// and the knight aiming right, the synthetic pad's stick away and towards
// and R2 fire the stronger bolt (Balance.combo.bolt): bigger, faster,
// combo.bolt.damage times atk; late, the normal bolt. The moves rebound to
// K and I: K then I and Q fire the stronger whirlwind (Balance.combo.
// whirlwind), longer and wider, hitting harder; S then W, no longer the
// moves, fire the normal one; the choice of specials names each stronger
// version and the combo with K and I. In a session, a host and a joiner
// joined over LAN in one process: the joiner's stronger stun freezes the
// host's enemy for the stronger freeze and the host hears the swell; the
// joiner's stronger bolt flies big on the host's screen. Muted. Prints one
// PASS or FAIL line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/combo/combo.qml

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Common
import Clayground.GameController
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
    readonly property real stepS: 1 / 60
    readonly property string store: "ShapesAndStoneComboBench"

    function check(ok, what) {
        console.log("[Combo]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(k) {
        solo.forceActiveFocus()
        keys.keyPress(k, Qt.NoModifier, -1)
    }
    function release(k) {
        solo.forceActiveFocus()
        keys.keyRelease(k, Qt.NoModifier, -1)
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

    Component.onCompleted: {
        gameComp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComp.status !== Component.Ready) {
            console.log("[Combo] FAIL", gameComp.errorString())
            Qt.exit(1)
            return
        }
        solo = gameComp.createObject(bench.contentItem, {width: 1000, height: 500, muted: true,
                                                         recordStoreName: store})
        solo.controls.reset()
        solo.boltEnded.connect((id, how, enemy, dealt, x, y, travelled, own) =>
            bench.ends.push({id: id, how: how, enemy: enemy, dealt: dealt, own: own}))
        script.start()
    }

    // ---- helpers ----
    function alive(e) { return e && e.destroyed === false }
    function steps(n) {
        for (let i = 0; i < n; i++) Clayground.physicsStep(1)
    }
    function centreOf(o) { return {x: o.xWu + o.widthWu / 2, y: o.yWu - o.heightWu / 2} }
    function place(e, p, dx, dy) {
        let c = centreOf(p)
        e.xWu = c.x + dx - e.widthWu / 2
        e.yWu = c.y + dy + e.heightWu / 2
        e.body.linearVelocity = Qt.point(0, 0)
        if (!e.halted) e.halt()
    }
    // A halted enemy let go again, the knight its target as a playing one's
    function wake(e, p) {
        e.halted = false
        e.target = p
    }
    function aim(p, angle) {
        p.padAim = true
        p.padAimAngle = angle
    }
    // The knight's speed now, wu a second
    function speed(p) {
        let v = p.body.linearVelocity
        return Math.sqrt(v.x * v.x + v.y * v.y)
    }
    // Holds input away for n steps, then towards for m steps, each by
    // calling hold(way) - way -1 away, 1 towards, 0 let go - and returns
    // the slowest the knight went on any of those steps
    function enter(hold, n, m) {
        let slowest = 1e9
        hold(-1)
        for (let i = 0; i < n; i++) { steps(1); slowest = Math.min(slowest, speed(solo.player)) }
        hold(1)
        for (let i = 0; i < m; i++) { steps(1); slowest = Math.min(slowest, speed(solo.player)) }
        return slowest
    }
    // The keys of moves away (down) and towards (up) while aiming up
    function keysHold(down, up) {
        return way => {
            if (way === -1) { release(up); press(down) }
            else if (way === 1) { release(down); press(up) }
            else { release(down); release(up) }
        }
    }
    function padHold(axis) {
        return way => {
            let s = {}
            if (way !== 0) s[axis] = way
            pad(s)
        }
    }
    function surges(g) { return g.soundLog.filter(x => x.cue === "sfx/special_surge").length }
    // A floating word over the knight in the room, by its text
    function wordShown(g, text) {
        let kids = g.room ? g.room.children : []
        for (let i = 0; i < kids.length; i++)
            if (kids[i].text === text && kids[i].visible) return true
        return false
    }
    function ready(p, special) {
        p.special = special
        p.maxHp = 100000
        p.hp = 100000
        p.maxMana = 1000
        p.mana = p.maxMana
    }

    property var ends: []
    property var small: []

    // ---- the pad's left stick alone, the aim the game's (issue #320) ----
    // One physics step a turn of the event loop, so KnightPad's aim, a
    // Qt.callLater, follows the stick between steps as in play
    property var stick: ({})
    function stickSteps(state, n) {
        let out = [[20, () => { pad(state); bench.stick = state }]]
        for (let i = 0; i < n; i++) out.push([20, () => {
            if (bench.stick.triggerR2 !== 1) Clayground.physicsStep(1)
        }])
        return out
    }
    property var stickWent: null
    function stickStart() {
        let g = solo, p = g.player
        Clayground.paused = true
        p.special = "bolt"
        p.maxHp = 100000
        p.hp = 100000
        p.maxMana = 1000
        p.mana = p.maxMana
        for (let e of g.enemies.filter(alive)) place(e, p, -10, 10)
        p.xWu = g._fightRoomCx - p.widthWu / 2
        p.yWu = g._fightRoomCy + p.heightWu / 2
    }
    // R2 pressed: whether the special was the stronger one, the bolt in
    // flight's size, the facing
    function stickFire() {
        let g = solo, p = g.player, bolt = null
        p.mana = p.maxMana
        pad({axisX: 1, triggerR2: 1})
        for (let id in g._boltById) if (g._boltById[id].own) bolt = g._boltById[id]
        stickWent = {strong: p.lastStrong, size: bolt ? bolt.widthWu : 0,
                     facing: p.facingAngle, padAim: p.padAim}
    }
    function stickCheckStrong() {
        let r = stickWent
        check(r.padAim && r.strong && Math.abs(r.size - Balance.combo.bolt.size) < 1e-6,
              "the pad's left stick alone, right then left then right, the right stick at rest and the aim the "
              + "game's, and R2 fire the stronger bolt (" + (r.strong ? "stronger" : "normal") + ", "
              + r.size + " wu across, facing " + r.facing.toFixed(0) + ")")
        check(Math.abs(r.facing) < 1, "the push away left the aim right, where the bolt flies (facing "
              + r.facing.toFixed(1) + ")")
    }
    function stickCheckTurn() {
        let r = stickWent
        check(!r.strong && Math.abs(r.size - Balance.bolt.size) < 1e-6,
              "held left past the aim's hold, " + Balance.combo.aimHold + " s, the knight turns round: right "
              + "then and R2 fire the normal bolt (" + (r.strong ? "stronger" : "normal") + ", " + r.size + " wu across)")
    }
    function stickTurned() {
        let p = solo.player
        check(Math.abs(Math.abs(p.facingAngle) - 180) < 1, "held left that long the knight faces left (facing "
              + p.facingAngle.toFixed(1) + ")")
    }
    readonly property int holdSteps: Math.ceil(Balance.combo.aimHold * 60) + 6
    readonly property var stickCases: [].concat(
        [[20, () => stickStart()]],
        stickSteps({axisX: 1}, 10),
        stickSteps({axisX: -1}, 4),
        stickSteps({axisX: 1}, 2),
        [[20, () => stickFire()], [20, () => { pad({}); bench.stick = {} }], [20, () => stickCheckStrong()]],
        stickSteps({}, 40),
        stickSteps({axisX: 1}, 10),
        stickSteps({axisX: -1}, holdSteps),
        [[20, () => stickTurned()]],
        stickSteps({axisX: 1}, 2),
        [[20, () => stickFire()], [20, () => { pad({}); bench.stick = {} }], [20, () => stickCheckTurn()]],
        stickSteps({}, 40),
        [[20, () => { Clayground.paused = false }]]
    )

    // The stun by the keys: the stronger one, then late, the wrong way
    // round and away again after the combo
    function soloStun() {
        let g = solo, p = g.player
        Clayground.paused = true
        g.logSounds = true
        g.clearSoundLog()
        ready(p, "stun")
        aim(p, 90)
        small = g.enemies.filter(e => alive(e) && !e.lead && e.enemyType !== "guardian")
        check(small.length >= 2, "the flow room stands two small enemies or more (" + small.length + ")")
        let s = Balance.stun, c = Balance.combo.stun
        let gap = (s.reach + c.reach) / 2
        let a = small[0]
        let put = () => {
            for (let e of g.enemies.filter(alive)) place(e, p, -10, 10)
            p.xWu = g._fightRoomCx - p.widthWu / 2
            p.yWu = g._fightRoomCy + p.heightWu / 2
            steps(1)
            place(a, p, gap, 0)
            if (a.aiState === "frozen") a._attackTimer = 0
            steps(2)
        }
        put()
        let mana = p.mana, rec = g.fightRecord.strongSpecials, heard = surges(g)
        let slowest = enter(keysHold(Qt.Key_S, Qt.Key_W), 4, 2)
        check(p.comboReady(), "the move keys away from the aim (S, aiming up) and then towards it (W) enter the combo")
        wake(a, p)
        keys.keyClick(Qt.Key_Q, Qt.NoModifier, -1)
        let spent = mana - p.mana
        check(p.lastStrong && g.fightRecord.strongSpecials === rec + 1 && !p.comboReady(),
              "Q then fires the stronger stun and spends the combo (record " + g.fightRecord.strongSpecials + ")")
        check(Math.abs(spent - p.specialMana) < 1e-6, "for the stun's own mana (" + spent + " of " + p.specialMana + ")")
        check(slowest > Balance.knight.moveSpeed * 0.5, "the knight walks on through the combo (slowest "
              + slowest.toFixed(2) + " wu/s)")
        check(a.aiState === "frozen", "an enemy " + gap + " wu off, past the stun's reach " + s.reach
              + " and inside the stronger one's " + c.reach + ", freezes (" + a.aiState + ")")
        check(surges(g) === heard + 1 && g.soundLog.some(x => x.cue === "sfx/stun_bash"),
              "the swell is heard over the bash")
        check(wordShown(g, c.name.toUpperCase()), "the stronger stun's name, " + c.name.toUpperCase() + ", shows over the knight")
        release(Qt.Key_W)
        let n = 0
        while (a.aiState === "frozen" && n < 400) { steps(1); n++ }
        check(Math.abs(n * stepS - c.freeze) <= 3 * stepS, "it stays frozen the stronger freeze, " + c.freeze
              + " s (" + (n * stepS).toFixed(3) + " s)")

        // Late: Q after the combo's window
        put()
        enter(keysHold(Qt.Key_S, Qt.Key_W), 4, 2)
        steps(Math.ceil(Balance.combo.window / stepS) + 1)
        p.mana = p.maxMana
        wake(a, p)
        keys.keyClick(Qt.Key_Q, Qt.NoModifier, -1)
        check(!p.lastStrong && a.aiState !== "frozen", "Q later than the combo's window, " + Balance.combo.window
              + " s, fires the normal stun: the enemy " + gap + " wu off stays unfrozen (" + a.aiState + ")")
        release(Qt.Key_W)

        // The wrong way round: towards, then away
        put()
        let hold = keysHold(Qt.Key_S, Qt.Key_W)
        hold(1); steps(4); hold(-1); steps(2)
        p.mana = p.maxMana
        wake(a, p)
        keys.keyClick(Qt.Key_Q, Qt.NoModifier, -1)
        check(!p.lastStrong && a.aiState !== "frozen", "towards, then away, and Q fire the normal stun")
        hold(0)

        // Away again after the combo
        put()
        enter(hold, 4, 2)
        hold(-1); steps(2)
        p.mana = p.maxMana
        keys.keyClick(Qt.Key_Q, Qt.NoModifier, -1)
        check(!p.lastStrong, "away again after the combo, Q fires the normal stun")
        hold(0)
        steps(2)
        // A normal enemy in the normal reach freezes for the normal freeze
        // with the combo late: the normal stun is as it was
        put()
        place(a, p, s.reach * 0.6, 0)
        enter(hold, 4, 2)
        hold(0)
        steps(Math.ceil(Balance.combo.window / stepS) + 1)
        p.mana = p.maxMana
        wake(a, p)
        keys.keyClick(Qt.Key_Q, Qt.NoModifier, -1)
        n = 0
        while (a.aiState === "frozen" && n < 400) { steps(1); n++ }
        check(!p.lastStrong && Math.abs(n * stepS - s.freeze) <= 3 * stepS, "the normal stun freezes for "
              + s.freeze + " s as before (" + (n * stepS).toFixed(3) + " s)")
        Clayground.paused = false
    }

    // The bolt by the pad's stick and R2, the knight aiming right
    function soloBolt() {
        let g = solo, p = g.player
        Clayground.paused = true
        ready(p, "bolt")
        aim(p, 0)
        let a = small[0]
        for (let e of g.enemies.filter(alive)) place(e, p, -10, 10)
        place(a, p, 5, 0)
        steps(2)
        let shoot = (strong) => {
            a.hp = 100000
            let hp = a.hp, n0 = ends.length, bolt = null
            p.mana = p.maxMana
            let mana = p.mana
            enter(padHold("axisX"), 4, 2)
            if (!strong) steps(Math.ceil(Balance.combo.window / stepS) + 1)
            pad({axisX: 1, triggerR2: 1})
            for (let id in g._boltById) if (g._boltById[id].own) bolt = g._boltById[id]
            let size = bolt ? bolt.widthWu : 0, fly = bolt ? bolt.speed : 0
            let k = 0
            while (ends.length === n0 && k < 120) { steps(1); k++ }
            pad({})
            steps(1)
            let e = ends.length > n0 ? ends[ends.length - 1] : null
            return {strong: p.lastStrong, size: size, speed: fly, lost: hp - a.hp, end: e, spent: mana - p.mana}
        }
        let r = shoot(true)
        let want = Math.max(Balance.minDamage, Math.round(p.atk * Balance.combo.bolt.damage) - a.def)
        check(r.strong && Math.abs(r.size - Balance.combo.bolt.size) < 1e-6
              && Math.abs(r.speed - Balance.combo.bolt.speed) < 1e-6,
              "the pad's stick away from the aim and towards it, then R2, fire the stronger bolt: "
              + r.size + " wu across at " + r.speed + " wu/s")
        check(!!r.end && r.end.how === "enemy" && r.lost === want && Math.abs(r.spent - p.specialMana) < 1e-6,
              "it hurts for " + Balance.combo.bolt.damage + " times atk " + p.atk + " less defense " + a.def
              + ", " + want + " (lost " + r.lost + "), for the bolt's own mana (" + r.spent + ")")
        r = shoot(false)
        want = Math.max(Balance.minDamage, Math.round(p.atk * Balance.bolt.damage) - a.def)
        check(!r.strong && Math.abs(r.size - Balance.bolt.size) < 1e-6 && r.lost === want,
              "late, R2 fires the normal bolt: " + r.size + " wu across, " + r.lost + " damage (" + want + ")")
        Clayground.paused = false
    }

    // The moves rebound to K and I: the whirlwind by them, and not by S
    // and W; the choice names the combo with them
    function soloRebound() {
        let g = solo, p = g.player
        Clayground.paused = true
        ready(p, "whirlwind")
        aim(p, 90)
        let c = g.controls
        let up = c.rebind("moveUp", "keys", {key: Qt.Key_I}), down = c.rebind("moveDown", "keys", {key: Qt.Key_K})
        check(up.taken && down.taken && c.key("moveUp") === Qt.Key_I && c.key("moveDown") === Qt.Key_K,
              "the moves up and down rebound to I and K")
        let a = small[0], b = small[1]
        let k = Balance.knight, cw = Balance.combo.whirlwind
        let whirl = (down, up, strong) => {
            for (let e of g.enemies.filter(alive)) place(e, p, -10, 10)
            p.xWu = g._fightRoomCx - p.widthWu / 2
            p.yWu = g._fightRoomCy + p.heightWu / 2
            steps(1)
            enter(keysHold(down, up), 4, 2)
            if (!strong) steps(Math.ceil(Balance.combo.window / stepS) + 1)
            // Beside the knight, past the whirlwind's reach and inside the
            // stronger one's
            let side = (k.whirlReach + cw.reach) / 2
            place(a, p, side, 0)
            place(b, p, -side, 0)
            a.hp = 100000; b.hp = 100000
            p.momentum = Balance.momentum.max
            p.mana = p.maxMana
            keys.keyClick(Qt.Key_Q, Qt.NoModifier, -1)
            let n = 0, went = p.isWhirling
            while (p.isWhirling && n < 120) {
                // They stay beside it as it spins forward
                place(a, p, side, 0)
                place(b, p, -side, 0)
                steps(1)
                n++
            }
            keysHold(down, up)(0)
            steps(1)
            return {went: went, strong: p.lastStrong, steps: n, lost: [100000 - a.hp, 100000 - b.hp]}
        }
        let r = whirl(Qt.Key_K, Qt.Key_I, true)
        let want = Math.max(Balance.minDamage, Math.floor(p.atk * cw.swing) - a.def)
        check(r.went && r.strong, "K then I, the moves as rebound, and Q fire the stronger whirlwind")
        check(Math.abs(r.steps * stepS - cw.duration) <= 2 * stepS, "it spins " + cw.duration + " s ("
              + (r.steps * stepS).toFixed(3) + " s)")
        check(r.lost[0] === want && r.lost[1] > 0, "it hits both enemies beside it, out of the whirlwind's reach "
              + k.whirlReach + " and inside its own " + cw.reach + ", for " + cw.swing + " times atk less defense ("
              + r.lost.join(", ") + ", want " + want + ")")
        r = whirl(Qt.Key_S, Qt.Key_W, true)
        check(r.went && !r.strong && r.lost[0] === 0, "S then W, no longer the moves, and Q fire the normal whirlwind ("
              + r.lost.join(", ") + " damage)")
        // The choice of specials: each card's stronger version, and the
        // combo in the keys as bound
        let comp = Qt.createComponent(Qt.resolvedUrl("../../src/SpecialChoice.qml"))
        let cards = Balance.specials.order.map(id => ({id: id, name: Balance.specials[id].name,
            line: Balance.specials[id].line, mana: Balance.specials[id].mana,
            strongName: Balance.combo[id].name, strongLine: Balance.combo[id].line}))
        let choice = comp.createObject(bench.contentItem, {width: 1000, height: 500, cards: cards, combo: g.comboHint})
        let texts = []
        let walk = it => {
            if (it.objectName === "specialStrong" && it.visible) texts.push(it.text)
            for (let i = 0; i < it.children.length; i++) walk(it.children[i])
        }
        walk(choice)
        let names = Balance.specials.order.map(id => Balance.combo[id].name)
        check(texts.length === 3 && names.every((n, i) => texts[i].indexOf(n) >= 0 && texts[i].indexOf(Balance.combo[Balance.specials.order[i]].line) >= 0),
              "the choice's cards each name the stronger version and what is stronger (" + texts.join(" | ") + ")")
        check(g.comboHint.indexOf("K I Q") >= 0 && g.comboHint.indexOf("away from your aim, then towards it") >= 0,
              "the choice shows the combo with the moves as rebound (" + g.comboHint + ")")
        choice.destroy()
        c.reset()
        check(g.comboHint.indexOf("S W Q") >= 0, "with the defaults back it shows S W Q (" + g.comboHint + ")")
        Clayground.paused = false
    }

    // ---- the session ----
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
                                                         recordStoreName: store})
        joiner = gameComp.createObject(bench.contentItem, {x: 500, width: 500, height: 500, muted: true,
                                                           recordStoreName: store})
        hostNet = network(host)
        joinNet = network(joiner)
        hostNet.signalingMode = Network.SignalingMode.Local
        hostNet.host()
    }
    property var base: null
    property string idT: ""
    property int frozenFrames: 0
    property real bigSeen: 0
    // The joiner's knight enters the combo by its moves: away (down, the
    // aim up) for a few frames, then towards, with Q a frame later
    function joinerCombo(way) {
        let jp = joiner.player
        jp.moveX = 0
        jp.moveY = way === -1 ? 1 : way === 1 ? -1 : 0
    }
    Timer {
        id: sampler
        interval: 16
        repeat: true
        onTriggered: {
            let e = byId(bench.host)[bench.idT]
            if (e && e.aiState === "frozen") bench.frozenFrames++
            for (let id in bench.host._boltById) {
                let b = bench.host._boltById[id]
                if (!b.own && b.strong) bench.bigSeen = Math.max(bench.bigSeen, b.widthWu)
            }
        }
    }
    property real frozenAt: 0

    property var soloSteps: [].concat([
        [() => solo.screen === "title", () => solo.applyScenario("flow", 0)],
        [() => solo.player && solo.fightRoomActive && solo.enemies.filter(alive).length >= 4, () => {}]],
        stickCases, [
        [100, () => soloStun()],
        [100, () => soloBolt()],
        [100, () => soloRebound()],
        [100, () => { solo.logSounds = false; solo.destroy(); solo = null }],
        [300, () => startSession()]
    ])
    property var sessionSteps: [
        [() => hostNet.networkId !== "", () => joinNet.join(hostNet.networkId)],
        [() => hostNet.connected && joinNet.connected && hostNet.nodeCount >= 2, () => {
            host.masterSeed = 424242
            host._startMultiplayerGame()
        }],
        [() => host.player && joiner.player && host.screen === "game" && joiner.screen === "game"
               && host.enemies.length >= 2 && joiner.enemies.length === host.enemies.length, () => {
            let h = byId(host)
            let ids = Object.keys(h).filter(id => !h[id].lead && !h[id].boss)
            idT = ids[0] || ""
            for (let id in h) if (id !== idT) h[id].halt()
            check(idT !== "", "the host runs a small enemy")
            ready(joiner.player, "stun")
            aim(joiner.player, 90)
            base = centreOf(host.player)
        }],
        // The host's enemy beside the joiner's knight, where both screens
        // show it; it goes for the knight, in the stun's reach
        [100, () => {
            let jp = joiner.player
            jp.xWu = base.x - 3 - jp.widthWu / 2
            jp.yWu = base.y + jp.heightWu / 2
            let e = byId(host)[idT]
            if (e) {
                e.xWu = base.x - 3 + 1.5 - e.widthWu / 2
                e.yWu = base.y + e.heightWu / 2
                e.body.linearVelocity = Qt.point(0, 0)
            }
        }],
        [600, () => {
            host.logSounds = true
            host.clearSoundLog()
            frozenFrames = 0
            sampler.start()
            joinerCombo(-1)
        }],
        [120, () => joinerCombo(1)],
        [50, () => {
            let jp = joiner.player
            check(jp.comboReady(), "the joiner's knight enters the combo")
            let went = jp.unleash()
            joinerCombo(0)
            check(went && jp.lastStrong, "and lets the stronger stun loose at the host's enemy")
            frozenAt = Date.now()
        }],
        [1000, () => {
            let e = byId(host)[idT]
            check(e && e.aiState === "frozen", "the host's enemy freezes (" + (e ? e.aiState : "gone") + ")")
            check(host.soundLog.some(x => x.cue === "sfx/special_surge") && host.soundLog.some(x => x.cue === "sfx/stun_bash"),
                  "the host hears the swell over the joiner's bash")
        }],
        // Past the normal freeze it is frozen still
        [Balance.stun.freeze * 1000 - 600, () => {
            let e = byId(host)[idT]
            check(e && e.aiState === "frozen", "past the normal freeze, " + Balance.stun.freeze
                  + " s, it is frozen still: the stronger freeze reached the host (" + (e ? e.aiState : "gone") + ")")
        }],
        [(Balance.combo.stun.freeze - Balance.stun.freeze) * 1000 + 600, () => {
            let e = byId(host)[idT]
            check(e && e.aiState !== "frozen", "after the stronger freeze it thaws (" + (e ? e.aiState : "gone") + ")")
            // The joiner's stronger bolt, aimed away from everyone
            let jp = joiner.player
            jp.special = "bolt"
            jp.mana = jp.maxMana
            aim(jp, 90)
            bigSeen = 0
            joinerCombo(-1)
        }],
        [120, () => joinerCombo(1)],
        [50, () => {
            let jp = joiner.player
            let went = jp.unleash()
            joinerCombo(0)
            for (let id in joiner._boltById) if (joiner._boltById[id].own) joiner._boltById[id].reach = 2
            check(went && jp.lastStrong, "the joiner's knight lets the stronger bolt loose")
        }],
        [700, () => {
            sampler.stop()
            check(Math.abs(bigSeen - Balance.combo.bolt.size) < 1e-6, "it flies big on the host's screen too ("
                  + bigSeen + " wu across)")
            host.logSounds = false
            hostNet.leave()
            joinNet.leave()
        }],
        [300, () => { host.destroy(); joiner.destroy() }],
        [300, () => {
            console.log("[Combo] done,", failures, "failed")
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
                    console.log("[Combo] FAIL step", i, "timed out")
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
