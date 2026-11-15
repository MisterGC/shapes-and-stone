// Stun bench - the stun special: a shield bash that freezes weak and
// normal enemies and ends the wind-up of a lead or the Warden without
// opening it (issue #318).
//
// Alone, stepped on the physics clock: in the flow scenario the knight,
// with the stun chosen, stands between two small enemies within
// Balance.stun.reach, one of them winding up, and a third out of it. The
// special's button bashes for the stun's mana: the two freeze, the wind-up
// is over, the third goes on; they show it - the frost rim, held breath -
// and stand frozen for stun.freeze seconds to the step, unmoved, through a
// blow too, never striking, then thaw into the chase. Short of the mana the
// button bashes nothing. In the duel scenario the lead, its stance worn,
// winds up: the stun ends its wind-up and its string, it goes for the
// knight again at once, not frozen, not opened, its stance as it was, and
// a charged swing right after finds no opening; out of a wind-up a stun
// does nothing to it. In the boss scenario the same for the Warden.
// In a session, a host and a joiner joined over LAN in one process: the
// joiner's knight stuns next to a small enemy the host runs - it freezes
// on the host and shows frozen on the joiner's screen, and thaws on both
// after about stun.freeze - and next to an enemy the host makes a lead
// and winds up: the host ends its wind-up, neither screen freezes or opens
// it. Muted. Prints one PASS or FAIL line per check and exits with the
// number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/stun/stun.qml

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
        console.log("[Stun]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        gameComp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComp.status !== Component.Ready) {
            console.log("[Stun] FAIL", gameComp.errorString())
            Qt.exit(1)
            return
        }
        solo = gameComp.createObject(bench.contentItem, {width: 1000, height: 500, muted: true,
                                                         recordStoreName: "ShapesAndStoneStunBench"})
        script.start()
    }

    // ---- helpers ----
    function alive(e) { return e && e.destroyed === false }
    function centreDist(a, b) {
        return Math.hypot(a.xWu + a.widthWu / 2 - b.xWu - b.widthWu / 2,
                          a.yWu - a.heightWu / 2 - b.yWu + b.heightWu / 2)
    }
    // Every item of this name anywhere under item is visible
    function shows(item, name) {
        if (!item) return false
        if (item.objectName === name && item.visible) return true
        let kids = item.children || []
        for (let i = 0; i < kids.length; i++)
            if (shows(kids[i], name)) return true
        return false
    }
    function steps(n) {
        for (let i = 0; i < n; i++) Clayground.physicsStep(1)
    }
    // An enemy put at (dx, dy) wu from the knight's corner, at rest
    function place(e, p, dx, dy) {
        e.xWu = p.xWu + dx
        e.yWu = p.yWu + dy
        e.body.linearVelocity = Qt.point(0, 0)
    }
    // The knight ready to stun: the stun chosen, full mana, unhurt for good
    function readyStun(p) {
        p.special = "stun"
        p.maxHp = 100000
        p.hp = 100000
        p.mana = p.maxMana
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

    property var a: null
    property var b: null
    property var far: null
    property var lead: null
    property real farX: 0
    property real farY: 0
    property real stepS: 1 / 60

    // The flow scenario: two small enemies in reach, one winding up, a
    // third out of it
    function soloFlow() {
        let g = solo, p = g.player
        Clayground.paused = true
        readyStun(p)
        let small = g.enemies.filter(e => alive(e) && !e.lead)
        check(small.length >= 3, "the flow room stands three small enemies or more (" + small.length + ")")
        a = small[0]; b = small[1]; far = small[2]
        for (let e of small.slice(3)) place(e, p, 12, 0)
        place(a, p, 1.5, 0)
        place(b, p, -1.5, 0)
        place(far, p, 0, Balance.stun.reach + 1.5)
        steps(1)
        a.target = p
        a.windUp(1.0)
        steps(1)
        check(a.aiState === "telegraph", "the first enemy winds up a blow (" + a.aiState + ")")
        farX = far.xWu; farY = far.yWu
        let mana = p.mana, rec = g.fightRecord.stuns
        let went = p.unleash()
        check(went && Math.abs(mana - p.mana - p.specialMana) < 1e-6 && p.specialMana === Balance.stun.mana,
              "with the stun chosen the special's button bashes for its " + p.specialMana + " mana ("
              + (mana - p.mana) + " spent)")
        check(a.aiState === "frozen" && b.aiState === "frozen" && far.aiState !== "frozen",
              "the two in reach freeze, the one out of it does not (" + [a.aiState, b.aiState, far.aiState].join(", ") + ")")
        check(!a.parryWindow && a.windUps >= 1, "the wind-up under way is over: no blow comes of it")
        check(g.fightRecord.stuns === rec + 1 && g.fightRecord.stunFrozen === 2 && g.fightRecord.stunInterrupted === 0,
              "the record counts the stun and the two it froze (" + g.fightRecord.stuns + ", "
              + g.fightRecord.stunFrozen + ", " + g.fightRecord.stunInterrupted + ")")
        check(shows(a, "frostRim") && shows(b, "frostRim") && !shows(far, "frostRim") && a._breath === 0,
              "a frozen enemy shows it: its frost rim, its breath held")
        // Frozen to the step: freeze seconds, unmoved and through a blow
        let ax = a.xWu, ay = a.yWu, bx = b.xWu, by = b.yWu, hp = a.hp
        let n = Math.round(Balance.stun.freeze / stepS), frozenFor = -1, moved = 0, struck = false, into = []
        let hp0 = p.hp
        for (let i = 1; i <= n + 3; i++) {
            if (i === 10) a.takeDamage(1, p.xWu, p.yWu, false)
            if (i === 12) b.takeDamage(1, p.xWu, p.yWu, true)
            steps(1)
            if (a.aiState === "frozen" || b.aiState === "frozen") {
                moved = Math.max(moved, Math.hypot(a.xWu - ax, a.yWu - ay), Math.hypot(b.xWu - bx, b.yWu - by))
                if (a.aiState === "lunge" || b.aiState === "lunge" || a.parryWindow || b.parryWindow) struck = true
            } else if (frozenFor < 0) {
                frozenFor = i
                into = [a.aiState, b.aiState]
            }
        }
        check(Math.abs(frozenFor - n) <= 1, "they stand frozen for " + Balance.stun.freeze + " s, "
              + n + " steps, to the step (" + frozenFor + " steps)")
        check(moved < 1e-3 && a.hp < hp, "frozen they do not move, a blow and a charged one included ("
              + moved.toFixed(4) + " wu, HP " + hp + " -> " + a.hp + ")")
        check(!struck && p.hp === hp0, "frozen they never strike (the knight's HP " + hp0 + " -> " + p.hp + ")")
        check(into.join() === "chase,chase", "then they thaw into the chase (" + into.join(", ")
              + "), their AI going on (" + a.aiState + ", " + b.aiState + " 3 steps later)")
        // Short of the mana: nothing
        p.mana = Balance.stun.mana - 1
        rec = g.fightRecord.stuns
        let refused = !p.unleash()
        check(refused && p.mana === Balance.stun.mana - 1 && g.fightRecord.stuns === rec && a.aiState !== "frozen",
              "short of the mana the button bashes nothing and spends nothing")
        Clayground.paused = false
    }

    // A lead, or the Warden, winding up: the stun ends the wind-up
    function soloLead(what) {
        let g = solo, p = g.player
        Clayground.paused = true
        readyStun(p)
        let foes = g.enemies.filter(alive)
        lead = foes.find(e => what === "the Warden" ? e.boss : e.lead)
        check(!!lead, what + " stands in the room")
        if (!lead) { Clayground.paused = false; return }
        lead.dormant = false
        for (let e of foes) if (e !== lead) place(e, p, 14, 0)
        place(lead, p, 1.5 + lead.bulk, 0)
        steps(1)
        lead.target = p
        lead._setStance(0.6)
        lead.beginString(-1, false)
        steps(1)
        let state = lead.aiState, inString = lead.stringName !== ""
        let rec = g.fightRecord.stunInterrupted
        p.unleash()
        check((state === "telegraph" || state === "crush") && lead.aiState === "chase" && lead.stringName === "" && !lead.parryWindow,
              "the stun ends " + what + "'s wind-up and its string: it goes for the knight again at once ("
              + state + (inString ? " of a string" : "") + " -> " + lead.aiState + ")")
        check(!lead.opening && lead.aiState !== "frozen" && Math.abs(lead.stance - 0.6) < 1e-6,
              what + " is neither frozen nor opened, its stance as it was (" + lead.stance + ")")
        check(g.fightRecord.stunInterrupted === rec + 1, "the record counts the wind-up it ended")
        let hp = lead.hp
        lead.takeDamage(p.atk, p.xWu, p.yWu, true)
        check(!lead.opening, "a charged swing right after the stun finds no opening ("
              + (hp - lead.hp) + " damage)")
        steps(30)
        check(lead.aiState !== "frozen" && lead.aiState !== "stagger" && !lead.opening,
              "nor does it freeze or stagger after (" + lead.aiState + ")")
        // Out of a wind-up a stun does nothing to it
        lead._clearString()
        lead.aiState = "chase"
        p.mana = p.maxMana
        rec = g.fightRecord.stunInterrupted
        p.unleash()
        check(lead.aiState === "chase" && g.fightRecord.stunInterrupted === rec && !lead.opening,
              "out of a wind-up a stun does nothing to " + what + " (" + lead.aiState + ")")
        Clayground.paused = false
    }

    // ---- the session ----
    property string idS: ""
    property string idL: ""
    property real stunnedAt: 0
    // What the joiner's stun did to the host's lead, on the host
    property var leadStunned: []
    property var seen: null
    Timer {
        id: sampler
        interval: 16
        repeat: true
        onTriggered: {
            let s = bench.seen, h = bench.byId(bench.host)[bench.idS], j = bench.byId(bench.joiner)[bench.idS]
            let t = Date.now() - bench.stunnedAt
            if (h && h.aiState === "frozen") { s.hostFrozen++; s.hostLast = t; if (s.hostFirst < 0) s.hostFirst = t }
            if (j && j.aiState === "frozen") {
                s.joinFrozen++; s.joinLast = t
                if (s.joinFirst < 0) s.joinFirst = t
                if (bench.shows(j, "frostRim")) s.joinRim++
            }
        }
    }
    function startSession() {
        host = gameComp.createObject(bench.contentItem, {width: 500, height: 500, muted: true,
                                                         recordStoreName: "ShapesAndStoneStunBench"})
        joiner = gameComp.createObject(bench.contentItem, {x: 500, width: 500, height: 500, muted: true,
                                                           recordStoreName: "ShapesAndStoneStunBench"})
        hostNet = network(host)
        joinNet = network(joiner)
        hostNet.signalingMode = Network.SignalingMode.Local
        hostNet.host()
    }

    property var soloSteps: [
        [() => solo.screen === "title", () => solo.applyScenario("flow", 0)],
        [() => solo.player && solo.fightRoomActive && solo.enemies.filter(alive).length >= 3, () => soloFlow()],
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
            let ids = Object.keys(h).filter(id => !h[id].lead && h[id].enemyType !== "spitter")
            idS = ids[0] || ""
            idL = ids[1] || ""
            check(idS !== "" && idL !== "", "the host runs two small melee enemies or more")
            readyStun(joiner.player)
            readyStun(host.player)
            // The host's knight out of the way
            host.player.xWu = h[idS].xWu + 20
        }],
        [500, () => {
            let je = byId(joiner)[idS], jp = joiner.player
            jp.xWu = je.xWu + 1.4
            jp.yWu = je.yWu
            seen = {hostFrozen: 0, joinFrozen: 0, joinRim: 0, hostFirst: -1, joinFirst: -1, hostLast: -1, joinLast: -1}
            stunnedAt = Date.now()
            let went = jp.unleash()
            check(went && joiner.fightRecord.stunFrozen >= 1,
                  "the joiner's knight stuns next to a small enemy the host runs")
            sampler.start()
        }],
        [Balance.stun.freeze * 1000 + 1200, () => {
            sampler.stop()
            let s = seen, f = Balance.stun.freeze * 1000
            check(s.hostFirst >= 0 && s.hostFirst < 300 && s.hostLast > f - 300 && s.hostLast < f + 400,
                  "it freezes on the host and thaws after about " + Balance.stun.freeze + " s (frozen from "
                  + s.hostFirst + " to " + s.hostLast + " ms)")
            check(s.joinFirst >= 0 && s.joinFirst < 400 && s.joinLast > f - 300 && s.joinLast < f + 500
                  && s.joinRim === s.joinFrozen,
                  "the joiner's screen shows it frozen, with its frost rim, and thawed after it (frozen from "
                  + s.joinFirst + " to " + s.joinLast + " ms, the rim in " + s.joinRim + " of " + s.joinFrozen + " frames)")
            let h = byId(host)[idS], j = byId(joiner)[idS]
            check(h && j && h.aiState !== "frozen" && j.aiState !== "frozen", "thawed on both screens ("
                  + (h ? h.aiState : "gone") + " / " + (j ? j.aiState : "gone") + ")")
            // The host makes another enemy a lead and winds it up at the
            // joiner's knight
            let hl = byId(host)[idL], jl = byId(joiner)[idL], jp = joiner.player
            jp.xWu = jl.xWu + 1.4
            jp.yWu = jl.yWu
            jp.mana = jp.maxMana
            hl.lead = true
            hl.stunned.connect(w => bench.leadStunned.push(w))
            hl.windUp(2.0)
        }],
        [() => { let jl = byId(joiner)[idL]; return jl && jl.lead && jl.aiState === "telegraph" }, () => {
            let jl = byId(joiner)[idL], jp = joiner.player
            jp.xWu = jl.xWu + 1.4
            jp.yWu = jl.yWu
            check(jp.unleash() && joiner.fightRecord.stunInterrupted >= 1,
                  "the joiner's knight stuns next to the host's lead winding up")
        }],
        [400, () => {
            let hl = byId(host)[idL], jl = byId(joiner)[idL]
            check(leadStunned.join() === "interrupted" && hl && hl.aiState !== "frozen" && !hl.opening,
                  "the host ends the lead's wind-up, neither frozen nor opened (" + leadStunned.join(", ")
                  + ", now " + (hl ? hl.aiState : "gone") + ")")
            check(jl && jl.aiState !== "frozen" && !jl.opening, "and the joiner's screen shows it so ("
                  + (jl ? jl.aiState : "gone") + ")")
            hostNet.leave()
            joinNet.leave()
        }],
        // Torn down before quitting: the game crashes when Qt quits with it
        // still up, and the crash's exit code would hide the result
        [300, () => { host.destroy(); joiner.destroy() }],
        [300, () => {
            console.log("[Stun] done,", failures, "failed")
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
                    console.log("[Stun] FAIL step", i, "timed out")
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
