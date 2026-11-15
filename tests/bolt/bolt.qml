// Bolt bench - the bolt special: a blast along the knight's aim that hurts
// the first enemy it meets (issue #319).
//
// Alone, stepped on the physics clock, the enemies' AI halted: in the flow
// scenario the knight, with the bolt chosen, aims at two small enemies in
// a row, the first out of the sword's reach. The special's button lets a
// bolt loose for the bolt's mana; it flies at Balance.bolt.speed along the
// aim and hurts the first enemy for bolt.damage times atk less its defense,
// the second not at all; aimed up, it hurts the enemy above and not the two
// to the right. Nothing in line, it flies its reach, bolt.reach, and ends,
// an enemy just past the reach unhurt; aimed at a wall it ends there. A
// guardian's shield takes it from the front as any blow. Short of the mana
// the button lets nothing loose. In the duel scenario the lead takes it as
// a blow on its stance - a chip of it, its stance worn, not opened - and a
// bolt into a stance worn to the last wear leaves it unbroken, which the
// sword's next blow breaks. In the boss scenario the same for the Warden.
// In a session, a host and a joiner joined over LAN in one process: the
// joiner's bolt flies through the host's knight to an enemy the host runs
// - it flies on the host's screen too, the host's enemy loses the bolt's
// damage once, and neither knight is hurt - and the host's bolt through
// the joiner's knight the same way. Muted. Prints one PASS or FAIL line per
// check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/bolt/bolt.qml

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
        console.log("[Bolt]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        gameComp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComp.status !== Component.Ready) {
            console.log("[Bolt] FAIL", gameComp.errorString())
            Qt.exit(1)
            return
        }
        solo = gameComp.createObject(bench.contentItem, {width: 1000, height: 500, muted: true,
                                                         recordStoreName: "ShapesAndStoneBoltBench"})
        solo.boltEnded.connect((id, how, enemy, dealt, x, y, travelled, own) =>
            bench.ends.push({id: id, how: how, enemy: enemy, dealt: dealt, x: x, y: y,
                             travelled: travelled, own: own}))
        script.start()
    }

    // ---- helpers ----
    function alive(e) { return e && e.destroyed === false }
    function steps(n) {
        for (let i = 0; i < n; i++) Clayground.physicsStep(1)
    }
    function centreOf(o) { return {x: o.xWu + o.widthWu / 2, y: o.yWu - o.heightWu / 2} }
    // An enemy put with its centre at (dx, dy) wu from the knight's, at
    // rest, its AI halted
    function place(e, p, dx, dy) {
        let c = centreOf(p)
        e.xWu = c.x + dx - e.widthWu / 2
        e.yWu = c.y + dy + e.heightWu / 2
        e.body.linearVelocity = Qt.point(0, 0)
        if (!e.halted) e.halt()
    }
    // The knight ready: the bolt chosen, full mana, unhurt for good, aiming
    // at angle degrees up from the right
    function readyBolt(p, angle) {
        p.special = "bolt"
        p.maxHp = 100000
        p.hp = 100000
        p.mana = p.maxMana
        aim(p, angle)
    }
    function aim(p, angle) {
        p.padAim = true
        p.padAimAngle = angle
    }
    // What a bolt does to enemy e: the knight's bolt.damage times atk less
    // its defense, a chip of that on a lead's stance (Enemy._blow)
    function boltDamage(p, e) {
        let amount = Math.round(p.atk * Balance.bolt.damage)
        let d = Math.max(Balance.minDamage, amount - e.def)
        if (e.lead && !e.opening) d = Math.max(Balance.minDamage, Math.round(d * Balance.lead.chip))
        return d
    }

    // The bolts that ended on the solo screen, in order
    property var ends: []
    // Lets a bolt loose and steps until it ends, at most limit steps:
    // {went, end, steps, spent}
    function shoot(p, limit) {
        let n0 = ends.length, mana = p.mana
        let went = p.unleash()
        let spent = mana - p.mana
        let k = 0
        while (went && ends.length === n0 && k < (limit || 120)) {
            steps(1)
            k++
        }
        return {went: went, end: ends.length > n0 ? ends[ends.length - 1] : null, steps: k, spent: spent}
    }
    readonly property real stepS: 1 / 60

    // The flow scenario: the bolt's damage, its aim, its reach, the wall
    function soloFlow() {
        let g = solo, p = g.player
        Clayground.paused = true
        readyBolt(p, 0)
        let small = g.enemies.filter(e => alive(e) && !e.lead)
        check(small.length >= 4, "the flow room stands four small enemies or more (" + small.length + ")")
        let melee = small.filter(e => e.enemyType !== "guardian")
        let a = melee[0], b = melee[1], c = melee[2]
        for (let e of small) place(e, p, -10, 10)
        // Two in a row to the right, the first out of the sword's reach
        place(a, p, 5, 0)
        place(b, p, 8, 0)
        steps(1)
        let ha = a.hp, hb = b.hp, rec = g.fightRecord.bolts, hits = g.fightRecord.boltHits
        let ac = centreOf(a), pc = centreOf(p)
        let gap = Math.hypot(ac.x - pc.x, ac.y - pc.y)
        let r = shoot(p)
        check(r.went && Math.abs(r.spent - p.specialMana) < 1e-6 && p.specialMana === Balance.bolt.mana,
              "with the bolt chosen the special's button lets a bolt loose for its " + p.specialMana
              + " mana (" + r.spent + " spent)")
        check(g.fightRecord.bolts === rec + 1, "the record counts the bolt (" + g.fightRecord.bolts + ")")
        let e = r.end
        check(!!e && e.how === "enemy" && e.enemy === a && e.own,
              "it ends at the first enemy in its line (" + (e ? e.how : "no end") + ", "
              + (e && e.enemy === a ? "the first" : e && e.enemy === b ? "the second" : "another") + ")")
        let want = boltDamage(p, a)
        check(!!e && e.dealt === want && ha - a.hp === want && b.hp === hb,
              "it hurts it for " + Balance.bolt.damage + " times atk " + p.atk + " less its defense " + a.def
              + ", " + want + " (dealt " + (e ? e.dealt : "-") + ", HP " + ha + " -> " + a.hp
              + "), and not the one behind it (HP " + hb + " -> " + b.hp + ")")
        check(gap > Balance.knight.attackRange, "it hurts an enemy out of the sword's reach ("
              + gap.toFixed(2) + " wu off, the sword reaches " + Balance.knight.attackRange + ")")
        let speed = e ? e.travelled / (r.steps * stepS) : 0
        check(!!e && Math.abs(speed - Balance.bolt.speed) <= Balance.bolt.speed * 0.1,
              "it flies at " + Balance.bolt.speed + " wu/s (" + speed.toFixed(2) + " wu/s, "
              + (e ? e.travelled.toFixed(2) : "-") + " wu in " + r.steps + " steps)")
        check(g.fightRecord.boltHits === hits + 1, "the record counts its hit (" + g.fightRecord.boltHits + ")")

        // Along the aim: up at the third, not right at the two
        place(c, p, 0, 4)
        steps(1)
        p.mana = p.maxMana
        aim(p, 90)
        ha = a.hp; hb = b.hp
        let hc = c.hp
        r = shoot(p)
        e = r.end
        check(!!e && e.how === "enemy" && e.enemy === c && hc - c.hp === boltDamage(p, c)
              && a.hp === ha && b.hp === hb,
              "aimed up it hurts the enemy above and not the two to the right (" + (e ? e.how : "no end")
              + ", HP " + hc + " -> " + c.hp + ")")

        // Its reach: nothing in line, it ends at bolt.reach; an enemy just
        // past it is unhurt
        p.mana = p.maxMana
        aim(p, 0)
        place(a, p, Balance.bolt.reach + 1.2, 0)
        place(b, p, -10, 10)
        place(c, p, -10, 10)
        steps(1)
        ha = a.hp
        r = shoot(p, 200)
        e = r.end
        let step = Balance.bolt.speed * stepS
        check(!!e && e.how === "reach" && Math.abs(e.travelled - Balance.bolt.reach) <= step + 1e-6 && a.hp === ha,
              "nothing in line it flies its reach, " + Balance.bolt.reach + " wu, and ends ("
              + (e ? e.how + " after " + e.travelled.toFixed(2) + " wu" : "no end") + "); an enemy "
              + (Balance.bolt.reach + 1.2) + " wu off is unhurt (HP " + ha + " -> " + a.hp + ")")

        // A wall ends it: the knight 5 wu from the room's right wall
        place(a, p, -10, 10)
        p.xWu = g._fightRoomCx + 15 - 5 - p.widthWu / 2
        steps(2)
        p.mana = p.maxMana
        pc = centreOf(p)
        let toWall = g._fightRoomCx + 15 - pc.x
        r = shoot(p)
        e = r.end
        check(!!e && e.how === "wall" && e.travelled <= toWall && e.travelled >= toWall - 1,
              "aimed at a wall " + toWall.toFixed(2) + " wu off it ends there (" + (e ? e.how + " after "
              + e.travelled.toFixed(2) + " wu" : "no end") + ")")
        p.xWu = g._fightRoomCx - p.widthWu / 2
        steps(2)

        // A guardian's shield takes it from the front, as any blow
        let gd = small.find(x => x.enemyType === "guardian")
        if (gd) {
            place(gd, p, 4, 0)
            steps(1)
            gd.hp = 1000
            gd.facingAngle = 180
            p.mana = p.maxMana
            let full = boltDamage(p, gd)
            let hg = gd.hp
            r = shoot(p)
            check(!!r.end && r.end.enemy === gd && hg - gd.hp === Math.floor(full * Balance.enemy.blockedShare),
                  "a guardian's shield takes it from the front as any blow (" + (hg - gd.hp) + " of " + full + ")")
        } else {
            check(false, "the flow room stands a guardian")
        }

        // Short of the mana: nothing
        p.mana = Balance.bolt.mana - 1
        rec = g.fightRecord.bolts
        let n0 = ends.length
        let refused = !p.unleash()
        steps(30)
        check(refused && p.mana >= Balance.bolt.mana - 1 && g.fightRecord.bolts === rec && ends.length === n0,
              "short of the mana the button lets nothing loose and spends nothing")
        Clayground.paused = false
    }

    // A lead, or the Warden: the bolt is a blow on its stance and never
    // opens it
    function soloLead(what) {
        let g = solo, p = g.player
        Clayground.paused = true
        readyBolt(p, 0)
        let foes = g.enemies.filter(alive)
        let lead = foes.find(e => what === "the Warden" ? e.boss : e.lead)
        check(!!lead, what + " stands in the room")
        if (!lead) { Clayground.paused = false; return }
        lead.dormant = false
        for (let e of foes) if (e !== lead) place(e, p, -10, 10)
        place(lead, p, 5 + lead.bulk, 0)
        steps(1)
        lead.hp = lead.maxHp
        lead._setStance(0.6)
        let hp = lead.hp, want = boltDamage(p, lead), opened = 0
        lead.opened.connect(() => opened++)
        let r = shoot(p)
        check(!!r.end && r.end.enemy === lead && hp - lead.hp === want,
              what + " takes it on its stance: a chip of it, " + want + " (HP " + hp + " -> " + lead.hp + ")")
        let worn = Math.round((0.6 - Balance.lead.wear) * 20) / 20
        check(!lead.opening && opened === 0 && Math.abs(lead.stance - worn) < 1e-6 && lead.aiState !== "stagger",
              "it wears the stance as a blow does and does not open it (stance 0.6 -> " + lead.stance
              + ", " + lead.aiState + ")")
        // Worn to the last wear: a bolt leaves it unbroken, the sword's next
        // blow breaks it
        lead._setStance(Balance.lead.wear * 0.7)
        p.mana = p.maxMana
        r = shoot(p)
        check(!!r.end && r.end.enemy === lead && !lead.opening && opened === 0 && lead._stanceLeft > 0,
              "a bolt into a stance worn to its last wear does not break it (left "
              + lead._stanceLeft.toFixed(3) + ")")
        lead.takeDamage(p.atk, p.xWu, p.yWu, false)
        check(lead.opening && opened === 1, "the sword's next blow breaks it (" + (lead.opening ? "open" : "not open") + ")")
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

    property string idT: ""
    property string idU: ""
    // The bolts that ended on each screen, and the frames another node's
    // bolt flew on each
    property var hostEnds: []
    property var joinEnds: []
    property var seen: ({host: 0, joiner: 0})
    property var hp0: null
    Timer {
        id: sampler
        interval: 16
        repeat: true
        onTriggered: {
            for (let id in bench.host._boltById) if (!bench.host._boltById[id].own) bench.seen.host++
            for (let id in bench.joiner._boltById) if (!bench.joiner._boltById[id].own) bench.seen.joiner++
        }
    }
    function startSession() {
        host = gameComp.createObject(bench.contentItem, {width: 500, height: 500, muted: true,
                                                         recordStoreName: "ShapesAndStoneBoltBench"})
        joiner = gameComp.createObject(bench.contentItem, {x: 500, width: 500, height: 500, muted: true,
                                                           recordStoreName: "ShapesAndStoneBoltBench"})
        host.boltEnded.connect((id, how, enemy, dealt, x, y, travelled, own) =>
            bench.hostEnds.push({id: id, how: how, enemy: enemy, dealt: dealt, own: own}))
        joiner.boltEnded.connect((id, how, enemy, dealt, x, y, travelled, own) =>
            bench.joinEnds.push({id: id, how: how, enemy: enemy, dealt: dealt, own: own}))
        hostNet = network(host)
        joinNet = network(joiner)
        hostNet.signalingMode = Network.SignalingMode.Local
        hostNet.host()
    }
    // Where the host's knight stood when the run began: the line-ups are
    // round it, in the start room
    property var base: null
    // The shooter 2.5 wu left of base, the other knight at base, enemy id
    // 3 wu right of it and enemy away 2.5 wu below base, the shooter aiming
    // right; the host's enemies go to the joiner's screen as they move
    function lineUp(shooter, other, id, away) {
        let put = (o, dx, dy) => {
            o.xWu = base.x + dx - o.widthWu / 2
            o.yWu = base.y + dy + o.heightWu / 2
            if (o.body) o.body.linearVelocity = Qt.point(0, 0)
        }
        let h = byId(host)
        put(shooter, -2.5, 0)
        put(other, 0, 0)
        if (h[id]) put(h[id], 3, 0)
        if (h[away]) put(h[away], 0, -2.5)
        aim(shooter, 0)
    }
    // The checks after a bolt of the shooter's node: its own screen ended
    // it at the enemy, the other flew it and ended it too, the host's enemy
    // lost the bolt's damage once and neither knight was hurt
    function checkShot(who, ownEnds, otherEnds, otherSeen, id, want, hpBefore) {
        let o = ownEnds.filter(x => x.own)
        let t = otherEnds.filter(x => !x.own)
        check(o.length === 1 && o[0].how === "enemy" && o[0].enemy && o[0].enemy.objectId === id && o[0].dealt === want,
              "the " + who + "'s bolt hurts the enemy behind the other knight for " + want + " on its screen ("
              + o.map(x => x.how + " " + x.dealt).join(", ") + ")")
        check(otherSeen > 0 && t.length === 1 && t[0].dealt === 0,
              "it flies on the other screen too (" + otherSeen + " frames) and ends there, dealing nothing there ("
              + t.map(x => x.how + " " + x.dealt).join(", ") + ")")
        let h = byId(host)[id]
        check(h && hpBefore - h.hp === want, "the host's enemy loses the bolt's damage once (HP " + hpBefore + " -> "
              + (h ? h.hp : "gone") + ")")
        check(host.player.hp === hp0.host && joiner.player.hp === hp0.joiner,
              "it hurts no knight, the one in its line included (HP " + host.player.hp + ", " + joiner.player.hp + ")")
    }
    property int hpT: 0

    property var soloSteps: [
        [() => solo.screen === "title", () => solo.applyScenario("flow", 0)],
        [() => solo.player && solo.fightRoomActive && solo.enemies.filter(alive).length >= 4, () => soloFlow()],
        [100, () => solo.applyScenario("duel", 0)],
        [() => solo.player && solo.fightRoomActive && solo.enemies.some(e => alive(e) && e.lead), () => soloLead("the lead")],
        [100, () => solo.applyScenario("boss", 2)],
        [() => solo.player && solo.fightRoomActive && solo.enemies.some(e => alive(e) && e.boss), () => soloLead("the Warden")],
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
               && host.enemies.length >= 2 && joiner.enemies.length === host.enemies.length, () => {
            let h = byId(host)
            for (let id in h) h[id].halt()
            let ids = Object.keys(h).filter(id => !h[id].lead && !h[id].boss)
            idT = ids[0] || ""
            idU = ids[1] || ""
            check(idT !== "" && idU !== "", "the host runs two small enemies or more")
            readyBolt(joiner.player, 0)
            readyBolt(host.player, 0)
            base = centreOf(host.player)
            lineUp(joiner.player, host.player, idT, idU)
        }],
        // The knights and the enemies where the other screen shows them too
        [600, () => lineUp(joiner.player, host.player, idT, idU)],
        [400, () => {
            hostEnds = []; joinEnds = []
            seen = {host: 0, joiner: 0}
            hpT = byId(host)[idT].hp
            hp0 = {host: host.player.hp, joiner: joiner.player.hp}
            sampler.start()
            check(joiner.player.unleash(), "the joiner's knight lets a bolt loose at the host's enemy")
        }],
        [1200, () => {
            checkShot("joiner", joinEnds, hostEnds, seen.host, idT, boltDamage(joiner.player, byId(host)[idT] || {def: 0}), hpT)
            lineUp(host.player, joiner.player, idU, idT)
        }],
        [600, () => lineUp(host.player, joiner.player, idU, idT)],
        [400, () => {
            hostEnds = []; joinEnds = []
            seen = {host: 0, joiner: 0}
            hpT = byId(host)[idU].hp
            hp0 = {host: host.player.hp, joiner: joiner.player.hp}
            host.player.mana = host.player.maxMana
            check(host.player.unleash(), "the host's knight lets a bolt loose at its own enemy")
        }],
        [1200, () => {
            sampler.stop()
            checkShot("host", hostEnds, joinEnds, seen.joiner, idU, boltDamage(host.player, byId(host)[idU] || {def: 0}), hpT)
            hostNet.leave()
            joinNet.leave()
        }],
        // Torn down before quitting: the game crashes when Qt quits with it
        // still up, and the crash's exit code would hide the result
        [300, () => { host.destroy(); joiner.destroy() }],
        [300, () => {
            console.log("[Bolt] done,", failures, "failed")
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
                    console.log("[Bolt] FAIL step", i, "timed out")
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
