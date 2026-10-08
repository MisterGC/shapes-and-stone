// Answer bench - every enemy attack can be read and answered (issue #35).
//
// Starts the fight room paused (Clayground.paused) and single-steps it
// (Clayground.physicsStep), one enemy at a time, the others without a
// target. Counted in physics steps of 1/60 s: a grunt's telegraph, a
// guardian's counter and a spitter's shot each last at least the table's
// minTelegraph, and a lunge is open to a parry for exactly parryFrames
// steps. A hit the shield does not stop gives the knight hurtGrace seconds
// in which no damage lands, and its view flickers for as long; a blocked
// hit gives none. A shield raised at most knight.perfectBlockFrames steps
// before a blow, after it was down knight.perfectBlockRearm steps, takes
// it whole, gives knight.perfectBlockMana back and staggers a lunging
// grunt for knight.perfectBlockStagger seconds; raised a step earlier or
// re-armed a step short, it blocks with the chip.
// A lunge or a shot that lands in the grace plays no hit.
// A lunge the shield stops plays the shield's block once and no hit,
// flashes the shield and throws the grunt block.recoil wu back.
// A raised shield drains knight.blockDrain mana per second and drops at
// 0, cannot be raised again without mana, and a parry gives
// knight.parryMana back. Prints one PASS or FAIL line per check and exits
// with the number of failures.
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

            // A hit the held shield stops gives no grace
            Clayground.physicsStep(graceSteps)
            p.isBlocking = true
            Clayground.physicsStep(Balance.knight.perfectBlockFrames + 1)
            p.takeDamage(20, p.xWu + 1, p.yWu)
            check(p.graceLeft === 0, "a blocked hit gives no grace")
            p.isBlocking = false

            // A shield raised at most perfectBlockFrames steps before a blow
            // blocks it perfectly: no damage, mana back. Raised a step
            // earlier, it blocks with the chip; down for less than
            // perfectBlockRearm steps before it rose, it is no perfect block
            let pf = Balance.knight.perfectBlockFrames
            let rearm = Balance.knight.perfectBlockRearm
            Clayground.physicsStep(rearm)
            p.mana = p.maxMana - 10
            p.isBlocking = true
            Clayground.physicsStep(pf)
            let before = p.hp, manaBefore = p.mana
            let res = p.takeDamage(20, p.xWu + 1, p.yWu)
            check(res === "perfect" && p.hp === before && p.graceLeft === 0
                  && Math.abs(p.mana - (manaBefore + Balance.knight.perfectBlockMana)) < 1e-3,
                  "a shield raised " + pf + " steps before a blow blocks it perfectly ("
                  + res + ", " + before + " -> " + p.hp + " HP, mana "
                  + manaBefore.toFixed(2) + " -> " + p.mana.toFixed(2) + ")")
            p.isBlocking = false
            Clayground.physicsStep(rearm)
            p.isBlocking = true
            Clayground.physicsStep(pf)
            let open = p.perfectGuard
            Clayground.physicsStep(1)
            before = p.hp
            res = p.takeDamage(20, p.xWu + 1, p.yWu)
            check(open === true && res === "blocked" && p.hp < before,
                  "raised " + (pf + 1) + " steps before a blow, a step after its perfect window ("
                  + open + "), it blocks with the chip (" + res + ", " + before + " -> " + p.hp + " HP)")
            p.isBlocking = false
            Clayground.physicsStep(rearm - 1)
            p.isBlocking = true
            let armed = p.perfectGuard
            before = p.hp
            res = p.takeDamage(20, p.xWu + 1, p.yWu)
            check(armed === false && res === "blocked" && p.hp < before,
                  "a shield down for only " + (rearm - 1) + " steps before it rose has no perfect window ("
                  + armed + ") and blocks with the chip (" + res + ", " + before + " -> " + p.hp + " HP)")
            p.isBlocking = false
            // A lunge blocked perfectly staggers the grunt: a real one, run
            // step by step to its landing, the shield raised 4 steps before
            // it lands and down since the wind-up began, the knight facing
            // the grunt centre to centre as the shield measures it
            let pg = only("grunt")
            p.mana = p.maxMana
            pg.xWu = p.xWu + 1.5
            pg.yWu = p.yWu
            pg.target = p
            pg.aiState = "chase"
            let lunged = stepUntil(pg, "lunge")
            let lungeSteps = 0
            while (pg.aiState === "lunge" && lungeSteps < 600) {
                p.facingAngle = Math.atan2(pg.yWu - pg.heightWu / 2 - p.yWu + p.heightWu / 2,
                                           pg.xWu + pg.widthWu / 2 - p.xWu - p.widthWu / 2) * 180 / Math.PI
                if (pg._lungeSteps <= 4) p.isBlocking = true
                Clayground.physicsStep(1)
                lungeSteps++
            }
            check(lunged && pg.aiState === "stagger"
                  && Math.abs(pg._attackTimer - Balance.knight.perfectBlockStagger) < 1e-6,
                  "a lunge blocked perfectly staggers the grunt for "
                  + pg._attackTimer.toFixed(3) + " s, the table says "
                  + Balance.knight.perfectBlockStagger + " (" + pg.aiState + " after the lunge landed)")
            p.isBlocking = false
            pg.target = null
            Clayground.physicsStep(Math.round(Balance.knight.perfectBlockStagger / stepS) + 1)

            // In the grace a lunge and a shot play no hit. A stand-in for the
            // game records what the attacker would show and play.
            let shown = []
            let fake = {
                fx: false,
                playImpact: () => shown.push("impact sound"),
                impact: (kind) => shown.push(kind),
                spawnDamageNumber: () => shown.push("damage number")
            }
            let g = game.enemies.find(x => x.enemyType === "grunt" && !x.destroyed)
            let realWorld = g.gameWorld
            g.xWu = p.xWu + 0.5
            g.yWu = p.yWu
            g.target = p
            g.gameWorld = fake
            g.performAttack()
            check(shown.length === 1 && shown[0] === "impact sound" && p.graceLeft > 0,
                  "a lunge that lands plays its hit (" + shown.join(", ") + ")")
            shown = []
            let hp = p.hp
            g.performAttack()
            g.gameWorld = realWorld
            g.target = null
            check(p.hp === hp && shown.length === 0,
                  "a lunge in the grace plays no hit (" + (shown.join(", ") || "nothing") + ")")
            game.spawnProjectile(p.xWu + 20, p.yWu, -1, 0, 8)
            let shots = game.room.children.filter(o => o.objectName === "projectile" && !o.destroyed)
            let shot = shots[shots.length - 1]
            shot.gameWorld = fake
            shot.onHitPlayer({ getBody: () => ({ target: p }) })
            check(p.hp === hp && shown.length === 1 && shown[0] === "projectileBurst",
                  "a shot in the grace bursts and plays no hit (" + shown.join(", ") + ")")
            Clayground.physicsStep(graceSteps)

            // A lunge the shield stops plays the shield's block once, no
            // hit, flashes the shield and throws the grunt back off it. The
            // stand-in stands for the game of the grunt and of the knight.
            let played = []
            let blockWorld = {
                fx: false,
                playImpact: () => played.push("playImpact"),
                playBlock: () => played.push("playBlock"),
                impact: () => {},
                countFight: () => {},
                spawnDamageNumber: () => {}
            }
            // The shield is held: raised longer ago than a perfect block's
            // window
            let bg = only("grunt")
            bg.target = null
            p.facingAngle = 0
            p.mana = p.maxMana
            p.isBlocking = true
            Clayground.physicsStep(Balance.knight.perfectBlockFrames + 1)
            bg.aiState = "recovery"
            bg._attackTimer = 10
            bg.xWu = p.xWu + 0.5
            bg.yWu = p.yWu
            Clayground.physicsStep(1)
            let bv = view(p)
            let knightWorld = p.gameWorld
            bg.target = p
            bg.gameWorld = blockWorld
            p.gameWorld = blockWorld
            let x0 = bg.xWu
            let graceFree = p.graceLeft === 0
            bg.performAttack()
            p.gameWorld = knightWorld
            bg.gameWorld = realWorld
            bg.target = null
            let flashed = bv.children.some(c => c.flash !== undefined && c.flash > 0.5)
            let blocks = played.filter(x => x === "playBlock").length
            let impacts = played.filter(x => x === "playImpact").length
            check(graceFree && blocks === 1 && impacts === 0,
                  "a blocked lunge plays " + blocks + " playBlock and " + impacts
                  + " playImpact (" + (played.join(", ") || "nothing") + ")")
            check(flashed, "a blocked lunge flashes the knight's shield")
            Clayground.physicsStep(Math.ceil(bg.knockDuration / stepS) + 1)
            let recoiled = bg.xWu - x0
            check(Math.abs(recoiled - Balance.block.recoil) < 0.02,
                  "a blocked lunge throws the grunt " + recoiled.toFixed(3)
                  + " wu back, the table says " + Balance.block.recoil)
            p.isBlocking = false
            bg.aiState = "patrol"
            bg._attackTimer = 0

            // A raised shield drains mana and drops when it runs dry
            let drain = Balance.knight.blockDrain
            p.mana = p.maxMana
            p.isBlocking = true
            Clayground.physicsStep(60)
            check(Math.abs(p.mana - (p.maxMana - drain)) < 1e-3 && p.isBlocking,
                  "a second of shield drains " + (p.maxMana - p.mana).toFixed(3)
                  + " mana, the table says " + drain)
            let held = 60
            while (p.isBlocking && held < 6000) {
                Clayground.physicsStep(1)
                held++
            }
            let dry = Math.round(p.maxMana / drain / stepS)
            check(!p.isBlocking && p.mana === 0 && held === dry,
                  "the shield drops at 0 mana after " + held + " steps, " + dry + " expected")
            p.isBlocking = true
            check(!p.isBlocking, "without mana the shield cannot be raised")
            p.facingAngle = 180
            p.takeDamage(20, p.xWu - 1, p.yWu)
            check(p.graceLeft > 0, "with the shield dropped a hit from the front lands")
            Clayground.physicsStep(graceSteps)

            // A parry gives mana back, and the shield can be raised again
            let pr = only("grunt")
            pr.xWu = p.xWu + 1.5
            pr.yWu = p.yWu
            pr.aiState = "chase"
            let parried = stepUntil(pr, "telegraph")
            while (parried && !pr.parryWindow && pr.aiState !== "recovery") {
                p.facingAngle = Math.atan2(pr.yWu - p.yWu, pr.xWu - p.xWu) * 180 / Math.PI
                Clayground.physicsStep(1)
            }
            let parries = game.fightRecord.parries
            p.facingAngle = Math.atan2(pr.yWu - p.yWu, pr.xWu - p.xWu) * 180 / Math.PI
            p.attackCooldown = 0
            p.attack()
            Clayground.physicsStep(1)
            check(game.fightRecord.parries === parries + 1 && p.mana === Balance.knight.parryMana,
                  "a parry gives " + p.mana + " mana back, the table says " + Balance.knight.parryMana)
            p.isBlocking = true
            check(p.isBlocking, "with mana back the shield rises again")
            p.isBlocking = false
            for (let o of game.enemies) o.target = null
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
