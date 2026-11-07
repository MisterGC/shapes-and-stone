// Strings bench - a room's lead strikes in strings (issue #272).
//
// In the fight room each lead type - grunt, guardian, spitter - strikes
// every string of its own (Balance.lead.strings) at the knight, which
// stands with its shield up, the bench stepping the world one physics
// step at a time. Every strike or feint beat gets its blow - a lunge or a
// shot - and its ring: the ring closes once per beat, and a lunge's parry
// window opens on the step the ring closes and stays open for
// enemy.parryFrames steps; one blow lands lead.beat seconds after the
// one before, a rest a beat more, a feint lead.feintHold later, its ring
// held at lead.feintRing for that long; a rest is a recovery a beat long.
// Then a knight within lead.reach holding a full charge is struck first:
// the grunt winds up at once, for enemy.minTelegraph, and its blow
// cancels the charge; a knight with no charge gets the string's count-in,
// enemy.windUp. Prints one PASS or FAIL line per check and exits with the
// number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/strings/strings.qml

import QtQuick
import QtQuick.Window
import Clayground.Common
import "../../src"

Window {
    id: bench
    width: 800
    height: 600
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0

    function check(ok, what) {
        console.log("[Strings]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Strings] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true})
        script.start()
    }

    readonly property real stepS: 1 / 60
    function steps(seconds) { return Math.round(seconds / stepS) }
    function near(a, b, tol) { return Math.abs(a - b) <= tol }

    // The enemy of type is the room's lead and the only one going for the
    // knight, at dx wu to its right; every other enemy stands
    function leadOf(type, dx) {
        let p = game.player
        let e = game.enemies.find(x => x.enemyType === type && !x.destroyed)
        for (let o of game.enemies) if (o !== e && !o.destroyed) o.halt()
        e.halt()
        e.halted = false
        e.lead = true
        e.maxHp = 100000
        e.hp = 100000
        e.crushChance = 0
        e.target = p
        e.attackCooldown = 0
        e._attackTimer = 0
        e.xWu = p.xWu + dx
        e.yWu = p.yWu
        return e
    }
    // The knight stands where it stood, whole, its shield up towards e
    function hold(p, e, x, y, shield) {
        p.xWu = x
        p.yWu = y
        p.hp = p.maxHp
        p.mana = p.maxMana
        p.graceLeft = 0
        p.facingAngle = Math.atan2(e.yWu - e.heightWu / 2 - p.yWu + p.heightWu / 2,
                                   e.xWu + e.widthWu / 2 - p.xWu - p.widthWu / 2) * 180 / Math.PI
        p.isBlocking = shield
    }

    // Strikes string i of e at the knight and steps until it is over.
    // Returns per step what the bench saw after it, and the blows struck
    function play(e, i) {
        let p = game.player
        let x = p.xWu, y = p.yWu
        let rows = [], blows = []
        let n = 0
        let onStruck = (beat, kind) => blows.push({step: n, beat: beat, kind: kind})
        e.struck.connect(onStruck)
        hold(p, e, x, y, true)
        Clayground.physicsStep(2)
        e.beginString(i, false)
        while (e.stringName !== "" && n < 1200) {
            hold(p, e, x, y, true)
            Clayground.physicsStep(1)
            rows.push({state: e.aiState, window: e.parryWindow, ring: e.ringProgress,
                       held: e.feinting, beat: e._beat})
            n++
        }
        e.struck.disconnect(onStruck)
        return {rows: rows, blows: blows, ended: e.stringName === "", state: e.aiState}
    }

    // The runs of steps on which pred holds: [first, last] each
    function runs(rows, pred) {
        let out = [], start = -1
        for (let i = 0; i <= rows.length; i++) {
            let on = i < rows.length && pred(rows[i])
            if (on && start < 0) start = i
            if (!on && start >= 0) { out.push([start, i - 1]); start = -1 }
        }
        return out
    }

    function checkString(type, i) {
        let l = Balance.lead
        let s = l.strings[type][i]
        let melee = type !== "spitter"
        let e = leadOf(type, melee ? 1.5 : 4)
        let r = play(e, i)
        let tag = type + " string \"" + s.name + "\" [" + s.beats.join(", ") + "]"
        let strikes = s.beats.map((b, k) => ({b: b, k: k})).filter(x => x.b !== 0)
        check(r.ended && r.state === "recovery" && r.blows.length === strikes.length
              && r.blows.every((w, j) => w.beat === strikes[j].k
                               && w.kind === (strikes[j].b === 2 ? "feint" : melee ? "strike" : "shot")),
              tag + ": " + r.blows.length + " blows on beats " + r.blows.map(w => w.beat + " " + w.kind).join(", ")
              + " (" + strikes.length + " by the table), then it recovers (" + r.state + ")")

        // The ring closes once per beat: from the step after one blow to
        // the next it starts open and reaches its outline
        let from = 0, rings = []
        for (let w of r.blows) {
            let seg = r.rows.slice(from, w.step + 1).filter(x => x.state !== "recovery")
            rings.push(seg.length ? [Math.min(...seg.map(x => x.ring)), Math.max(...seg.map(x => x.ring))] : [1, 0])
            from = w.step + 1
        }
        // A shot leaves on the step its ring closes: the step before it
        // shows the ring a step short of its outline
        let top = melee ? 0.999 : 1 - 1.5 * stepS / Math.min(l.beat, Balance.enemy.shootWindUp)
        check(rings.length === strikes.length && rings.every(g => g[0] < 0.3 && g[1] >= top),
              tag + ": the ring closes once per beat (" + rings.map(g => g[0].toFixed(2) + "-"
              + g[1].toFixed(2)).join(", ") + ")")

        if (melee) {
            // A parry window on every beat, opening as the ring closes
            let wins = runs(r.rows, x => x.window)
            let good = wins.filter(w => w[1] - w[0] + 1 === Balance.enemy.parryFrames
                                   && r.rows[w[0]].ring === 1 && w[0] > 0 && r.rows[w[0] - 1].ring < 1)
            check(wins.length === strikes.length && good.length === wins.length,
                  tag + ": a parry window on every beat, " + wins.length + " of them ("
                  + strikes.length + " beats), " + good.length + " open "
                  + Balance.enemy.parryFrames + " steps from the step the ring closes ("
                  + wins.map(w => (w[1] - w[0] + 1) + " steps").join(", ") + ")")
            // Each window ends as its blow lands
            check(r.blows.every((w, j) => wins[j] && Math.abs(w.step - wins[j][1]) <= 1),
                  tag + ": each blow lands as its window closes (blows at steps "
                  + r.blows.map(w => w.step).join(", ") + ", windows end at "
                  + wins.map(w => w[1]).join(", ") + ")")
        }

        // One blow a beat after the one before, a rest a beat more, a
        // feint feintHold later
        let gaps = [], want = []
        for (let j = 1; j < r.blows.length; j++) {
            gaps.push(r.blows[j].step - r.blows[j - 1].step)
            want.push(steps((strikes[j].k - strikes[j - 1].k) * l.beat + (strikes[j].b === 2 ? l.feintHold : 0)))
        }
        check(gaps.every((g, j) => Math.abs(g - want[j]) <= 1),
              tag + ": blows " + gaps.join(", ") + " steps apart (" + want.join(", ")
              + " by lead.beat " + l.beat + " s and lead.feintHold " + l.feintHold + " s)")

        // A feint holds its ring at feintRing for feintHold, no window open
        let feints = strikes.filter(x => x.b === 2)
        if (feints.length > 0) {
            let held = runs(r.rows, x => x.held)
            let flat = held.filter(h => r.rows.slice(h[0], h[1] + 1).every(
                x => near(x.ring, l.feintRing, 1e-6) && !x.window))
            check(held.length === feints.length && flat.length === held.length
                  && held.every(h => Math.abs(h[1] - h[0] + 1 - steps(l.feintHold)) <= 1),
                  tag + ": each feint holds " + held.map(h => h[1] - h[0] + 1).join(", ") + " steps ("
                  + steps(l.feintHold) + " by lead.feintHold), its ring at " + l.feintRing
                  + " and no window open (" + flat.length + " of " + held.length + ")")
        }
        // A rest is a recovery a beat long
        let rests = s.beats.filter(b => b === 0).length
        if (rests > 0) {
            let still = runs(r.rows.slice(0, r.blows.length ? r.blows[r.blows.length - 1].step : 0),
                             x => x.state === "recovery")
            let len = still.reduce((a, h) => a + h[1] - h[0] + 1, 0)
            check(Math.abs(len - rests * steps(l.beat)) <= rests,
                  tag + ": its " + rests + " rests stand " + len + " steps (" + rests * steps(l.beat)
                  + " by lead.beat)")
        }
        e.halt()
        e.lead = false
        Clayground.physicsStep(steps(Balance.knight.hurtGrace) + 1)
    }

    // A knight within reach of the grunt with a full charge ("full"), one
    // filling ("filling") or none (""): what the grunt winds up and what
    // its blow does to the charge
    function tryPunish(charge) {
        let p = game.player
        let l = Balance.lead
        let g = leadOf("grunt", charge !== "" ? (l.reach + Balance.enemy.lungeRange) / 2 : 1.5)
        let x = p.xWu, y = p.yWu
        g._committed = true
        hold(p, g, x, y, false)
        if (charge !== "") {
            p.pressSwing()
            let n = 0
            while (!(charge === "full" ? p.chargeFull : p.isCharging) && n < 600) {
                hold(p, g, x, y, false)
                Clayground.physicsStep(1)
                n++
            }
        }
        let full = p.chargeFull, filling = p.isCharging && !p.chargeFull
        g.aiState = "chase"
        let n = 0
        while (g.stringName === "" && n < 60) { hold(p, g, x, y, false); Clayground.physicsStep(1); n++ }
        let wound = g.windUpLength
        let hp0 = p.hp
        let landed = false
        let onStruck = () => landed = true
        g.struck.connect(onStruck)
        n = 0
        while (!landed && n < 300) {
            p.xWu = x
            p.yWu = y
            p.graceLeft = 0
            Clayground.physicsStep(1)
            n++
        }
        g.struck.disconnect(onStruck)
        let out = {full: full, filling: filling, wound: wound, landed: landed, hurt: hp0 - p.hp, charge: p._charge,
                   name: g.stringName}
        if (p.isCharging || p._charge === "spent") p.dropSwing()
        g.halt()
        g.lead = false
        p.hp = p.maxHp
        Clayground.physicsStep(steps(Balance.knight.hurtGrace) + 1)
        return out
    }

    // The grunt strikes its first string at the standing knight; in its
    // first rest the knight presses for a charge. How many steps the rest
    // lasted, and the wind-up that came then
    function tryRestCut() {
        let p = game.player
        let l = Balance.lead
        let i = l.strings.grunt.findIndex(s => s.beats.indexOf(0) > 0)
        let g = leadOf("grunt", 1.5)
        let x = p.xWu, y = p.yWu
        hold(p, g, x, y, true)
        Clayground.physicsStep(2)
        g.beginString(i, false)
        let n = 0
        while (!(g._beat >= 0 && g._string[g._beat] === 0) && n < 600) {
            hold(p, g, x, y, true)
            Clayground.physicsStep(1)
            n++
        }
        let inRest = g.aiState === "recovery"
        let name = g.stringName
        hold(p, g, x, y, false)
        p.isBlocking = false
        p.lowerShield()
        p.pressSwing()
        n = 0
        while (g.aiState === "recovery" && n < 600) {
            p.xWu = x
            p.yWu = y
            Clayground.physicsStep(1)
            n++
        }
        let out = {inRest: inRest, name: name, cutAfter: n, wound: g.windUpLength}
        p.dropSwing()
        g.halt()
        g.lead = false
        Clayground.physicsStep(steps(Balance.knight.hurtGrace) + 1)
        return out
    }

    // In the grunt's first rest the knight, a full charge built outside
    // lead.reach meanwhile, steps in to the edge of its heavy reach and
    // lets go on the same step: what broke the lead's stance
    function tryRestCharge() {
        let p = game.player
        let l = Balance.lead
        let i = l.strings.grunt.findIndex(s => s.beats.indexOf(0) > 0)
        let g = leadOf("grunt", 1.5)
        let x = p.xWu, y = p.yWu
        hold(p, g, x, y, true)
        Clayground.physicsStep(2)
        g.beginString(i, false)
        let n = 0
        while (!(g._beat >= 0 && g._string[g._beat] === 0) && n < 600) {
            hold(p, g, x, y, true)
            Clayground.physicsStep(1)
            n++
        }
        let inRest = g.aiState === "recovery"
        // The lead stands in its rest while the knight charges far off
        g.halted = true
        p.isBlocking = false
        p.lowerShield()
        p.xWu = g.xWu - l.reach - 2
        p.yWu = g.yWu
        p.pressSwing()
        n = 0
        while (!p.chargeFull && n < 600) { Clayground.physicsStep(1); n++ }
        let full = p.chargeFull
        let causes = []
        let onOpened = c => causes.push(c)
        g.opened.connect(onOpened)
        g.halted = false
        p.xWu = g.xWu - Balance.knight.attackRange * Balance.knight.heavyRange * 0.9
        p.yWu = g.yWu
        hold(p, g, p.xWu, p.yWu, false)
        p.releaseSwing()
        Clayground.physicsStep(1)
        g.opened.disconnect(onOpened)
        let out = {inRest: inRest, full: full, causes: causes, opening: g.opening}
        g.halt()
        g.lead = false
        Clayground.physicsStep(Math.ceil((l.openingTime + Balance.knight.heavyRecovery) / stepS) + 10)
        return out
    }

    Timer {
        id: script
        interval: 50
        repeat: true
        property int stage: 0
        onTriggered: {
            if (stage === 0) {
                if (!game || game.screen !== "title") return
                game.applyScenario("fight")
                stage = 1
                return
            }
            if (stage === 1) {
                if (!game.player || !game.fightRoomActive
                        || !["grunt", "guardian", "spitter"].every(t => game.enemies.some(
                            e => e.enemyType === t && !e.destroyed)))
                    return
                stop()
                run()
                game.destroy()
                Qt.exit(failures)
            }
        }
    }

    function run() {
        Clayground.paused = true
        let l = Balance.lead
        let types = ["grunt", "guardian", "spitter"]
        let table = types.every(t => (l.strings[t] || []).length > 0 && l.strings[t].every(
            s => s.beats.length > 0 && s.beats[0] !== 0 && s.beats.every(b => b === 0 || b === 1 || b === 2)))
        check(table && l.beat > Balance.enemy.lungeDuration && l.feintHold > 0
              && l.feintRing > 0 && l.feintRing < 1,
              "every lead type has its strings in Balance.lead: "
              + types.map(t => t + " " + (l.strings[t] || []).map(s => s.name + " ["
                          + s.beats.join(",") + "]").join(" ")).join("; ")
              + "; a beat of " + l.beat + " s, a feint holds " + l.feintHold + " s at " + l.feintRing)
        for (let t of types)
            for (let i = 0; i < (l.strings[t] || []).length; i++) checkString(t, i)

        let punished = tryPunish("full")
        check(punished.full && punished.name !== ""
              && near(punished.wound, Balance.enemy.minTelegraph, 1e-6)
              && punished.landed && punished.hurt > 0 && punished.charge === "spent",
              "a knight " + ((l.reach + Balance.enemy.lungeRange) / 2) + " wu off with a full charge ("
              + punished.full + ") is struck first: the lead winds up " + punished.wound
              + " s (enemy.minTelegraph " + Balance.enemy.minTelegraph + "), its blow takes "
              + punished.hurt + " HP and cancels the charge (" + punished.charge + ")")
        let filling = tryPunish("filling")
        check(filling.filling && near(filling.wound, Balance.enemy.minTelegraph, 1e-6)
              && filling.landed && filling.charge === "spent",
              "so is one whose charge still fills (" + filling.filling + "): wound up "
              + filling.wound + " s, the charge cancelled (" + filling.charge + ")")
        let calm = tryPunish("")
        check(calm.name !== "" && near(calm.wound, Balance.enemy.windUp, 1e-6),
              "a knight with no charge gets the string's count-in: " + calm.wound
              + " s (enemy.windUp " + Balance.enemy.windUp + ")")
        let cut = tryRestCut()
        check(cut.inRest && cut.cutAfter < steps(l.beat) && near(cut.wound, Balance.enemy.minTelegraph, 1e-6),
              "a knight that starts a charge in reach during a rest of \"" + cut.name
              + "\" is struck first: the rest is cut short after " + cut.cutAfter + " steps ("
              + steps(l.beat) + " a beat) and the lead winds up " + cut.wound + " s")
        let let_go = tryRestCharge()
        check(let_go.inRest && let_go.full && let_go.causes.join() === "heavy" && let_go.opening,
              "a full charge built outside lead.reach and let go on arriving in a rest opens the lead "
              + "(in the rest " + let_go.inRest + ", charge full " + let_go.full + ", opened by "
              + (let_go.causes.join() || "nothing") + ")")
        Clayground.paused = false
        console.log("[Strings] done,", failures, "failed")
    }
}
