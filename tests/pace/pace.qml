// Pace bench - a room's lead fights at the duel pace, nobody else does
// (issue #361).
//
// Starts the fight room paused (Clayground.paused) and single-steps it
// (Clayground.physicsStep). The game plays at Balance.pace.standard,
// Standard, unless told otherwise. Then, at each step of Balance.pace -
// Swift, Standard and Deliberate - set as the game's duelPace:
// - a grunt, a guardian and a spitter lead carry the step's factor: their
//   beat (lead.beat), count-in, wind-ups (enemy.windUp, enemy.crushWindUp,
//   enemy.shootWindUp) and recovery (lead.recovery) are factor times as
//   long, their walking, kiting and wind-up speeds factor times slower, a
//   guardian lead turns its shield at enemy.shieldTurnSpeed over factor,
//   and against them the parry window (enemy.parryFrames,
//   lead.parryStart) and the perfect-block window
//   (knight.perfectBlockFrames) are factor times as many steps, rounded;
// - the grunt lead plays it: its string's count-in, a feint's hold, a
//   blow it strikes a charging knight with, a crushing blow's wind-up and
//   the recovery after a string last as long as that, its lunge is open
//   to a parry for its parryFrames steps, a swing begun its parryStart
//   steps before parries it and one a step earlier does not, a shield
//   raised its perfectFrames steps before its blow blocks it perfectly
//   and one a step earlier does not; the spitter lead's shot winds up for
//   its shootWindUp; chasing the knight it walks no faster than its
//   chaseSpeed, and at Standard and Deliberate slower than the knight
//   with its shield up (knight.moveSpeed times knight.blockSpeed);
// - a weak and a normal grunt, a normal guardian and a normal spitter
//   keep the table's timings and speeds, a normal grunt winds up for
//   enemy.windUp, recovers enemy.recovery, is open to a parry for
//   enemy.parryFrames steps and a shield raised knight.perfectBlockFrames
//   steps before its blow is perfect, a step earlier not;
// - the knight keeps its own timings: its walk, its shield's slowing,
//   swing, cooldown, charge, dash and perfect-block window are the
//   table's.
// Last the Hollow Warden in its boss room keeps today's fight: factor 1,
// its own beat and count-in, the table's speeds and windows (issue #368).
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/pace/pace.qml

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
    readonly property real stepS: 1 / 60

    function check(ok, what) {
        console.log("[Pace]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Pace] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true})
        script.start()
    }

    function near(a, b) { return Math.abs(a - b) < 1e-6 }
    function r3(x) { return Math.round(x * 1000) / 1000 }
    // The physics steps a timer of seconds runs, counted down a step at a
    // time until nothing is left
    function toSteps(seconds) { return Math.ceil(seconds / stepS - 1e-6) }

    // A new enemy of the type and tier, at (dx, dy) wu off the knight, no
    // target and nothing to do until a check gives it one
    function spawn(type, tier, dx, dy) {
        let p = game.player
        game.spawnEnemy(p.xWu + dx, p.yWu + dy, tier, type)
        let e = game.enemies[game.enemies.length - 1]
        calm(e)
        return e
    }
    function calm(e) {
        e.target = null
        e.aiState = "patrol"
        e.parryWindow = false
        e._clearString()
        e.attackCooldown = 0
        e._attackTimer = 0
        e._knockT = 0
        e.crushChance = 0
        e.body.linearVelocity = Qt.point(0, 0)
    }
    // Only e has the knight for its target, dx wu to the knight's right
    function only(e, dx) {
        let p = game.player
        for (let o of game.enemies) if (o !== e) calm(o)
        calm(e)
        e.xWu = p.xWu + dx
        e.yWu = p.yWu
        e.target = p
        p.hp = p.maxHp
        p.mana = p.maxMana
        p.graceLeft = 0
        p.isBlocking = false
        p.facingAngle = 0
    }
    // Steps while e stays in the state, at most ten seconds' worth
    function stepsIn(e, state) {
        let n = 0
        while (e.aiState === state && n < 600) {
            Clayground.physicsStep(1)
            n++
        }
        return n
    }

    // What a lead at factor f carries, against the table: [ok, line]
    function carries(e, f) {
        let t = Balance.enemy[e.enemyType], en = Balance.enemy
        let got = {
            pace: e.pace, beat: e.beatLen, countIn: e.countIn, windUp: e.windUpDuration,
            crushWindUp: e.crushWindUp, shootWindUp: e.shootWindUp,
            chase: e.chaseSpeed, patrol: e.patrolSpeed, kite: e.kiteSpeed, windUpSpeed: e.windUpSpeed,
            shieldTurn: e.shieldRotSpeed,
            parryFrames: e.parryFrames, parryStart: e.parryStart, perfectFrames: e.perfectFrames
        }
        let want = {
            pace: f, beat: Balance.lead.beat * f, countIn: en.windUp * f, windUp: en.windUp * f,
            crushWindUp: en.crushWindUp * f, shootWindUp: en.shootWindUp * f,
            chase: t.chaseSpeed / f, patrol: t.patrolSpeed / f, kite: en.kiteSpeed / f,
            windUpSpeed: en.windUpSpeed / f, shieldTurn: en.shieldTurnSpeed / f,
            parryFrames: Math.round(en.parryFrames * f), parryStart: Math.round(Balance.lead.parryStart * f),
            perfectFrames: Math.round(Balance.knight.perfectBlockFrames * f)
        }
        let off = Object.keys(want).filter(k => !near(got[k], want[k]))
        return [off.length === 0, Object.keys(want).map(k => k + " " + r3(got[k])
                + (near(got[k], want[k]) ? "" : " (want " + r3(want[k]) + ")")).join(", ")]
    }

    // A shield raised k steps before e's blow lands: what became of it
    function blockAfter(e, k) {
        let p = game.player
        only(e, 1.0)
        p.isBlocking = true
        p._rearmed = true
        p._raisedAt = p._steps - k
        e.opening = false
        e._dirToTargetX = -1
        e._dirToTargetY = 0
        let res = p.takeDamage(e.atk, e.xWu, e.yWu, e.widthWu, false, -1, 0, e.perfectFrames)
        p.isBlocking = false
        return res
    }
    // The steps e's lunge, begun now at the knight 1.5 wu off, is open to
    // a parry; cooldown is the recovery it set as it landed
    property real cooldown: 0
    function parryOpen(e) {
        let p = game.player
        only(e, 1.5)
        p.isDashing = false
        e._startLunge()
        let open = e.parryWindow ? 1 : 0, n = 0
        cooldown = 0
        while (e.aiState === "lunge" && n < 600) {
            Clayground.physicsStep(1)
            n++
            if (e.parryWindow) open++
        }
        p.hp = p.maxHp
        return open
    }
    Connections {
        target: bench.recovering
        function onAttackCooldownChanged() {
            bench.cooldown = Math.max(bench.cooldown, bench.recovering.attackCooldown)
        }
    }
    property var recovering: null
    // Whether a swing begun k steps before now parries lead e in its window
    function parriesAfter(e, k) {
        let p = game.player
        p.isHeavy = false
        p._prevSwingStep = p._steps - k - 1000
        p._swingStep = p._steps - k
        return p._parriesLead(e)
    }
    // The fastest e walks, wu/s, chasing the knight 7 wu off over a second
    function chaseTop(e) {
        let p = game.player
        only(e, 7)
        e.aiState = "chase"
        e._recalcChasePath()
        let top = 0
        for (let i = 0; i < 60; i++) {
            Clayground.physicsStep(1)
            if (e.aiState !== "chase") break
            let v = e.body.linearVelocity
            top = Math.max(top, Math.sqrt(v.x * v.x + v.y * v.y))
        }
        return top
    }
    // The physics steps e's string i winds up its first blow for, a
    // punishing one with punish: until it lunges or its shot leaves
    function firstWindUp(e, i, punish) {
        only(e, 1.8)
        e.beginString(i, punish)
        let state = e.aiState, w = e.windUps, n = 0
        if (state !== "telegraph" && state !== "shoot") return -1
        while (e.aiState === state && e.windUps === w && n < 600) {
            Clayground.physicsStep(1)
            n++
        }
        return n
    }

    property var leads: ({})
    property var others: []

    function checkPace(step) {
        let p = game.player, k = Balance.knight, en = Balance.enemy, l = Balance.lead
        let f = step.factor, name = step.name
        game.duelPace = name
        check(near(game.duelPaceFactor, f), name + ": the game's duel pace factor is " + game.duelPaceFactor
              + " (table " + f + ")")
        for (let type of ["grunt", "guardian", "spitter"]) {
            let c = carries(leads[type], f)
            check(c[0], name + ": the " + type + " lead carries factor " + f + ": " + c[1])
        }

        let g = leads.grunt
        // Its string's count-in, a feint's hold, a punishing blow, a
        // crushing blow and the recovery after a string
        let w = firstWindUp(g, 0, false)
        check(w === toSteps(en.windUp * f), name + ": the grunt lead's string winds up its first blow for "
              + w + " steps, enemy.windUp times " + f + " is " + toSteps(en.windUp * f))
        only(g, 1.8)
        g.beginString(1, false)
        check(near(g.feintHold, l.feintHold * f), name + ": its feint holds " + r3(g.feintHold)
              + " s, lead.feintHold times " + f + " is " + r3(l.feintHold * f))
        w = firstWindUp(g, 0, true)
        check(w === toSteps(en.minTelegraph * f), name + ": a blow it strikes a charging knight with winds up for "
              + w + " steps, enemy.minTelegraph times " + f + " is " + toSteps(en.minTelegraph * f))
        only(g, 1.8)
        g.crushChance = 1
        g.windUp(g.windUpDuration)
        w = g.aiState === "crush" ? stepsIn(g, "crush") : -1
        check(w === toSteps(en.crushWindUp * f), name + ": its crushing blow winds up for " + w
              + " steps, enemy.crushWindUp times " + f + " is " + toSteps(en.crushWindUp * f))
        only(g, 1.8)
        g.beginString(0, false)
        g._endString()
        check(g.aiState === "recovery" && near(g.attackCooldown, l.recovery * f),
              name + ": after a string it recovers " + r3(g.attackCooldown) + " s, lead.recovery times "
              + f + " is " + r3(l.recovery * f))
        // Its windows
        let open = parryOpen(g)
        check(open === g.parryFrames && open === Math.round(en.parryFrames * f),
              name + ": its lunge is open to a parry for " + open + " steps, enemy.parryFrames times "
              + f + " is " + Math.round(en.parryFrames * f))
        let ps = g.parryStart
        check(parriesAfter(g, ps) && !parriesAfter(g, ps + 1),
              name + ": a swing begun " + ps + " steps before it lands parries it, one begun "
              + (ps + 1) + " does not")
        let pf = g.perfectFrames
        let atPf = blockAfter(g, pf), pastPf = blockAfter(g, pf + 1)
        check(atPf === "perfect" && pastPf === "blocked" && pf === Math.round(k.perfectBlockFrames * f),
              name + ": a shield raised " + pf + " steps before its blow blocks it " + atPf + ", "
              + (pf + 1) + " steps before " + pastPf + " (knight.perfectBlockFrames times " + f + ")")
        let s = leads.spitter
        w = firstWindUp(s, 0, false)
        check(w === toSteps(en.shootWindUp * f), name + ": the spitter lead's shot winds up for " + w
              + " steps, enemy.shootWindUp times " + f + " is " + toSteps(en.shootWindUp * f))
        // Its walk
        let top = chaseTop(g), shielded = p.maxSpeed * p.blockSpeedMultiplier
        check(top > 0 && top <= g.chaseSpeed * 1.02, name + ": chasing, the grunt lead walks at most "
              + r3(top) + " wu/s, its chaseSpeed " + r3(g.chaseSpeed))
        if (name !== "Swift")
            check(top < shielded, name + ": it walks slower than the knight with its shield up ("
                  + r3(top) + " < " + r3(shielded) + " wu/s)")

        // Weak and normal enemies keep the table's timings
        for (let e of others) {
            let t = Balance.enemy[e.enemyType]
            let ok = e.pace === 1 && near(e.windUpDuration, en.windUp) && near(e.crushWindUp, en.crushWindUp)
                && near(e.shootWindUp, en.shootWindUp) && near(e.chaseSpeed, t.chaseSpeed)
                && near(e.patrolSpeed, t.patrolSpeed) && near(e.kiteSpeed, en.kiteSpeed)
                && near(e.windUpSpeed, en.windUpSpeed) && near(e.shieldRotSpeed, en.shieldTurnSpeed)
                && e.parryFrames === en.parryFrames && e.perfectFrames === k.perfectBlockFrames
            check(ok, name + ": a " + ["weak", "normal"][e.tier] + " " + e.enemyType + " keeps the table's "
                  + "timings (pace " + e.pace + ", wind-up " + r3(e.windUpDuration) + " s, chase "
                  + r3(e.chaseSpeed) + " wu/s, shield turn " + r3(e.shieldRotSpeed) + ", parry "
                  + e.parryFrames + " and perfect " + e.perfectFrames + " steps)")
        }
        let n = others.find(e => e.enemyType === "grunt" && e.tier === 1)
        only(n, 1.8)
        n.aiState = "chase"
        n._attack()
        w = n.aiState === "telegraph" ? stepsIn(n, "telegraph") : -1
        let want = toSteps(Math.max(en.minTelegraph, en.windUp))
        check(w === want, name + ": a normal grunt winds up for " + w + " steps, the table's " + want)
        recovering = n
        open = parryOpen(n)
        recovering = null
        check(open === en.parryFrames && n.aiState === "recovery" && near(cooldown, en.recovery),
              name + ": its lunge is open to a parry for " + open + " steps (table " + en.parryFrames
              + "), then it recovers " + r3(cooldown) + " s (table " + en.recovery + ")")
        pf = k.perfectBlockFrames
        atPf = blockAfter(n, pf)
        pastPf = blockAfter(n, pf + 1)
        check(atPf === "perfect" && pastPf === "blocked", name + ": a shield raised " + pf
              + " steps before its blow blocks it " + atPf + ", " + (pf + 1) + " steps before " + pastPf)

        // The knight keeps its own
        let ok = near(p.maxSpeed, k.moveSpeed) && near(p.blockSpeedMultiplier, k.blockSpeed)
            && near(p.attackDuration, k.swingDuration) && near(p.attackCooldownTime, k.attackCooldown)
            && near(p.dashSpeed, k.dashSpeed) && near(p.dashDuration, k.dashDuration)
            && near(p.dashCooldownTime, k.dashCooldown)
        check(ok, name + ": the knight walks " + r3(p.maxSpeed) + " wu/s, " + p.blockSpeedMultiplier
              + " of it behind its shield, swings " + p.attackDuration + " s every " + p.attackCooldownTime
              + " s, dashes at " + p.dashSpeed + " for " + p.dashDuration
              + " s every " + p.dashCooldownTime + " s, as the table says")
        p.isBlocking = true
        p._rearmed = true
        p._raisedAt = p._steps - k.perfectBlockFrames
        let guard = p.perfectGuard
        p._raisedAt = p._steps - k.perfectBlockFrames - 1
        guard = guard && !p.perfectGuard
        p.isBlocking = false
        check(guard, name + ": the knight's own perfect-block window stays " + k.perfectBlockFrames + " steps")
    }

    property var steps: [
        [() => game.screen === "title", () => {
            game.applyScenario("fight")
        }],
        [() => game.player && game.fightRoomActive
              && game.enemies.some(e => e.lead && e.enemyType === "guardian"), () => {
            Clayground.paused = true
            let std = Balance.pace.steps.find(s => s.name === Balance.pace.standard)
            let names = Balance.pace.steps.map(s => s.name + " " + s.factor).join(", ")
            check(Balance.pace.steps.length === 3 && ["Swift", "Standard", "Deliberate"].every(
                      n => Balance.pace.steps.some(s => s.name === n)),
                  "the pace has three steps: " + names)
            let g = game.enemies.find(e => e.lead && e.enemyType === "guardian")
            check(game.duelPace === "Standard" && std && near(game.duelPaceFactor, std.factor)
                  && near(g.pace, std.factor),
                  "the game plays at " + game.duelPace + ", factor " + game.duelPaceFactor
                  + ", and the fight room's lead at " + g.pace)
            check(game.player.maxSpeed === Balance.knight.moveSpeed,
                  "the knight has no boots (" + game.player.maxSpeed + " wu/s)")
            leads = {
                grunt: spawn("grunt", 2, 0, 5),
                guardian: g,
                spitter: spawn("spitter", 2, 0, -5)
            }
            others = [spawn("grunt", 0, 5, 5), spawn("grunt", 1, -5, 5), spawn("guardian", 1, 5, -5),
                      spawn("spitter", 1, -5, -5)]
            for (let s of Balance.pace.steps) checkPace(s)
            game.duelPace = Balance.pace.standard
            Clayground.paused = false
            game.applyScenario("bossroom", 2, 1)
        }],
        [() => game.enemies.some(e => e.boss), () => {
            let w = game.enemies.find(e => e.boss), en = Balance.enemy, t = Balance.enemy.warden
            let ok = w.lead && w.pace === 1 && near(w.beatLen, Balance.boss.beat / w.speedUp)
                && near(w.countIn, Balance.boss.countIn) && near(w.windUpDuration, en.windUp)
                && near(w.chaseSpeed, t.chaseSpeed) && w.parryFrames === en.parryFrames
                && w.perfectFrames === Balance.knight.perfectBlockFrames && w.parryStart === Balance.lead.parryStart
            check(ok, "at " + game.duelPace + " the Warden keeps today's fight: pace " + w.pace + ", a beat of "
                  + r3(w.beatLen) + " s (boss.beat " + Balance.boss.beat + " over tempo " + r3(w.speedUp)
                  + "), count-in " + w.countIn + " s, chase " + r3(w.chaseSpeed) + " wu/s, parry "
                  + w.parryFrames + " and perfect " + w.perfectFrames + " steps")
            console.log("[Pace]", failures === 0 ? "all checks pass" : failures + " checks fail")
        }],
        [300, () => { game.destroy(); Qt.exit(failures) }]
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
                    console.log("[Pace] FAIL step", i, "timed out")
                    Qt.exit(failures + 1)
                    stop()
                }
                return
            }
            waitedMs = 0
            i++
            if (i >= bench.steps.length) stop()
            // A step that throws stops there, its checks after the throw
            // never run: that is a failure
            try {
                step[1]()
            } catch (err) {
                bench.check(false, "step " + (i - 1) + " threw: " + err)
                Qt.exit(failures)
            }
        }
    }
}
