// Answer bench - every enemy attack can be read and answered (issue #35).
//
// Starts the fight room paused (Clayground.paused) and single-steps it
// (Clayground.physicsStep), one enemy at a time, the others without a
// target. Counted in physics steps of 1/60 s: a grunt's telegraph, a
// guardian's counter and a spitter's shot each last at least the table's
// minTelegraph, and a lunge is open to a parry for exactly parryFrames
// steps. A hit the shield does not stop gives the knight hurtGrace seconds
// in which no damage lands, and its view flickers for as long; a blocked
// hit gives none. Prints one PASS or FAIL line per check and exits with
// the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/answer/answer.qml

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
        console.log("[Answer]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Answer] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true})
        script.start()
    }

    readonly property real stepS: 1 / 60
    readonly property int minSteps: Math.round(Balance.enemy.minTelegraph / stepS)

    // Only this enemy has the knight as its target, a step from it
    function only(type) {
        let p = game.player
        let e = game.enemies.find(x => x.enemyType === type && !x.destroyed)
        for (let o of game.enemies) o.target = o === e ? p : null
        for (let o of game.enemies)
            if (o !== e) { o.aiState = "patrol"; o.parryWindow = false }
        e._knockT = 0
        e.attackCooldown = 0
        e._attackTimer = 0
        return e
    }

    // Steps while the enemy is in the state, at most a few seconds' worth
    function stepsIn(e, state) {
        let n = 0
        while (e.aiState === state && n < 600) {
            Clayground.physicsStep(1)
            n++
        }
        return n
    }
    // Steps until the enemy reaches the state
    function stepUntil(e, state) {
        let n = 0
        while (e.aiState !== state && n < 600) {
            Clayground.physicsStep(1)
            n++
        }
        return e.aiState === state
    }

    property var steps: [
        [() => game.screen === "title", () => {
            game.applyScenario("fight")
        }],
        [() => game.player && game.fightRoomActive
              && ["grunt", "guardian", "spitter"].every(t => game.enemies.some(e => e.enemyType === t)), () => {
            Clayground.paused = true
            let p = game.player

            // A grunt winds up its lunge for at least the minimum
            let g = only("grunt")
            g.xWu = p.xWu + 1.5
            g.yWu = p.yWu
            g.aiState = "chase"
            let entered = stepUntil(g, "telegraph")
            let n = stepsIn(g, "telegraph")
            check(entered && g.aiState === "lunge" && n >= minSteps,
                  "a grunt's telegraph lasts " + n + " steps, the minimum is " + minSteps)

            // Its lunge is open to a parry for exactly parryFrames steps
            let open = 0, lunge = 0
            while (g.aiState === "lunge" && lunge < 600) {
                Clayground.physicsStep(1)
                lunge++
                if (g.parryWindow) open++
            }
            check(open === Balance.enemy.parryFrames && !g.parryWindow,
                  "the lunge (" + lunge + " steps) is open to a parry for " + open
                  + " steps, the table says " + Balance.enemy.parryFrames)

            // A guardian's counter after a blocked hit: the table's share of
            // a wind-up is below the minimum, the counter is not
            let d = only("guardian")
            d.xWu = p.xWu + 1.5
            d.yWu = p.yWu
            d.facingAngle = 180
            d.aiState = "recovery"
            d.attackCooldown = 10
            let hp = d.hp
            d.takeDamage(p.atk, p.xWu, p.yWu)
            let counter = stepsIn(d, "telegraph")
            let share = Balance.enemy.windUp * Balance.enemy.counterWindUp
            check(d.hp > hp - p.atk + d.def && d.aiState === "lunge" && counter >= minSteps,
                  "a guardian's counter lasts " + counter + " steps, the minimum is "
                  + minSteps + " (the share of a wind-up alone is "
                  + Math.round(share / stepS) + ")")
            d.attackCooldown = 10
            stepsIn(d, "lunge")

            // A spitter's shot winds up for at least the minimum
            let s = only("spitter")
            s.xWu = p.xWu + 4
            s.yWu = p.yWu
            s._shootTimer = 0
            s.aiState = "kite"
            entered = stepUntil(s, "shoot")
            let shot = stepsIn(s, "shoot")
            check(entered && s.aiState === "kite" && shot >= minSteps,
                  "a spitter's shot winds up for " + shot + " steps, the minimum is " + minSteps)
            for (let o of game.enemies) o.target = null
        }],
        [() => true, () => {
            let p = game.player
            let graceSteps = Math.round(Balance.knight.hurtGrace / stepS)
            // Wait for the shot of the last check to be gone
            Clayground.physicsStep(300)
            p.hp = p.maxHp
            p.graceLeft = 0
            p.isBlocking = false
            p.facingAngle = 0

            // A hit from behind lands and starts the grace
            p.takeDamage(20, p.xWu - 1, p.yWu)
            let afterHit = p.hp
            let v = view(p)
            check(afterHit < p.maxHp && p.graceLeft > 0 && v && v.graceLeft > 0,
                  "a hit lands (" + p.maxHp + " -> " + afterHit + " HP), starts "
                  + p.graceLeft.toFixed(3) + " s of grace and the knight flickers")
            p.takeDamage(20, p.xWu - 1, p.yWu)
            check(p.hp === afterHit, "a second hit right after it does not land (" + p.hp + " HP)")
            Clayground.physicsStep(graceSteps - 1)
            p.takeDamage(20, p.xWu - 1, p.yWu)
            check(p.hp === afterHit && v.graceLeft > 0,
                  "a hit on the last step of the grace does not land and the flicker still shows")
            Clayground.physicsStep(1)
            check(p.graceLeft === 0 && v.graceLeft === 0,
                  "the grace and the flicker are over after " + graceSteps + " steps")
            p.takeDamage(20, p.xWu - 1, p.yWu)
            check(p.hp < afterHit, "after the grace a hit lands again (" + afterHit + " -> " + p.hp + " HP)")

            // A hit the shield stops gives no grace
            Clayground.physicsStep(graceSteps)
            p.isBlocking = true
            p.takeDamage(20, p.xWu + 1, p.yWu)
            check(p.graceLeft === 0, "a blocked hit gives no grace")
            p.isBlocking = false
            Clayground.paused = false
            console.log("[Answer] done,", failures, "failed")
        }],
        // Torn down before quitting, as the other benches do
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ]

    // The knight's KnightView
    function view(knight) {
        for (let i = 0; i < knight.children.length; i++)
            if (typeof knight.children[i].parry === "function") return knight.children[i]
        return null
    }

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
                    console.log("[Answer] FAIL step", i, "timed out")
                    Qt.exit(failures + 1)
                    stop()
                }
                return
            }
            waitedMs = 0
            i++
            if (i >= bench.steps.length) stop()
            step[1]()
        }
    }
}
