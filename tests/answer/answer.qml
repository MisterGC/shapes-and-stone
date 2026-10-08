// Answer bench - every enemy attack can be read and answered (issue #35).
//
// Starts the fight room paused (Clayground.paused) and single-steps it
// (Clayground.physicsStep), one enemy at a time, the others without a
// target. Counted in physics steps of 1/60 s: a grunt's telegraph, a
// guardian's counter and a spitter's shot each last at least the table's
// minTelegraph, and a lunge is open to a parry for exactly parryFrames
// steps. The parry ring reaches the grunt on the step the window opens,
// is white for the window, and closes on a spitter as its shot leaves. A
// hit the shield does not stop gives the knight hurtGrace seconds
// in which no damage lands, and its view flickers for as long; a blocked
// hit gives none. A shield raised at most knight.perfectBlockFrames steps
// before a blow, after it was down knight.perfectBlockRearm steps, takes
// it whole, gives knight.perfectBlockMana back and staggers a lunging
// grunt for knight.perfectBlockStagger seconds; raised a step earlier or
// re-armed a step short, it blocks with the chip.
// A lunge that lands plays the knight's hurt sound, not the sword's punch;
// a lunge or a shot that lands in the grace plays no hit.
// A lunge the shield stops plays the shield's block once and no hit,
// flashes the shield and throws the grunt block.recoil wu back.
// A raised shield drains knight.blockDrain mana per second and drops at
// 0, where it breaks once - the view's shards, acted("shieldBreak") and
// the mana bar's flash; it cannot be raised again without mana, and a
// right-click then answers with the empty click and the mana bar's flash.
// A parry gives knight.parryMana back. With debugMechanics off a parry
// and a perfect block show their word, PARRY and PERFECT, and a hit no
// damage number. The hurt flash, the HP chunk, the shards, the mana bar's
// flash and the low shield's blink hold while the game is paused, however
// long, and run on with its physics steps. The left button, clicked
// through the game's mouse area, swings on release before
// knight.chargeStart; held, it charges at knight.chargeSpeed and is full on
// the step knight.chargeTime reaches; a full charge let go of at a guardian
// facing the knight deals knight.heavySwing times atk through its shield
// and staggers it; a hit while charging cancels it; held knight.chargeHold
// past full it goes at normal strength. Prints one PASS or FAIL line per
// check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/answer/answer.qml

import QtQuick
import QtQuick.Window
import QtTest
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
    // What a paused check saw, for the step after the wait
    property var kept: null

    // Sends real mouse clicks to the game; runs no tests of its own
    TestCase { id: mouse; when: false }

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

            // From the start of its telegraph the parry ring closes on the
            // grunt and reaches it on the step the parry window opens; it
            // is white for the window and gone after the lunge
            g.attackCooldown = 0
            g.aiState = "chase"
            entered = stepUntil(g, "telegraph")
            let first = g.ringProgress, last = first, rising = true
            let full = -1, window = -1, white = 0, i = 0
            while (entered && (g.aiState === "telegraph" || g.aiState === "lunge") && i < 600) {
                Clayground.physicsStep(1)
                i++
                if (g.ringShows && g.ringProgress < last) rising = false
                last = g.ringProgress
                if (full < 0 && g.ringProgress >= 1) full = i
                if (window < 0 && g.parryWindow) window = i
                if (g.parryWindow && g.ringShows && Qt.colorEqual(g.ringColor, Balance.parryRing.flashColor))
                    white++
            }
            check(entered && first < 0.1 && rising && full > 0 && full === window,
                  "the parry ring rises from " + first.toFixed(3) + " to 1 on step " + full
                  + " of the telegraph and lunge, the parry window opens on step " + window)
            check(white === Balance.enemy.parryFrames && !g.ringShows && g.ringProgress === 0,
                  "the ring is white for " + white + " steps of the window and gone after the lunge ("
                  + g.aiState + ")")

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
            // Its ring closes on the shorter counter as exactly
            let cFull = -1, cWindow = -1, c = 0
            while (d.aiState === "lunge" && c < 600) {
                Clayground.physicsStep(1)
                c++
                if (cFull < 0 && d.ringProgress >= 1) cFull = c
                if (cWindow < 0 && d.parryWindow) cWindow = c
            }
            check(cFull > 0 && cFull === cWindow,
                  "on a guardian's counter the ring reaches 1 on lunge step " + cFull
                  + ", the parry window opens on step " + cWindow)

            // A spitter's shot winds up for at least the minimum
            let s = only("spitter")
            s.xWu = p.xWu + 4
            s.yWu = p.yWu
            s._shootTimer = 0
            s.aiState = "kite"
            entered = stepUntil(s, "shoot")
            let shot = 0, sLast = 0, sRising = true, sWhite = false
            while (s.aiState === "shoot" && shot < 600) {
                if (s.ringProgress < sLast) sRising = false
                sLast = s.ringProgress
                if (!s.ringShows || Qt.colorEqual(s.ringColor, Balance.parryRing.flashColor)) sWhite = true
                Clayground.physicsStep(1)
                shot++
            }
            check(entered && s.aiState === "kite" && shot >= minSteps,
                  "a spitter's shot winds up for " + shot + " steps, the minimum is " + minSteps)
            check(sRising && sLast >= 1 - 1.5 * stepS / s.windUpLength && !sWhite,
                  "a spitter's shot gets the ring, closing to " + sLast.toFixed(3)
                  + " on its last wind-up step, never white")
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

            // A hit from behind lands and starts the grace; outside debug
            // mode it shows no damage number
            game.debugMechanics = false
            let numbers = spawned("damageNumber")
            p.takeDamage(20, p.xWu - 1, p.yWu)
            let afterHit = p.hp
            let v = view(p)
            check(afterHit < p.maxHp && p.graceLeft > 0 && v && v.graceLeft > 0,
                  "a hit lands (" + p.maxHp + " -> " + afterHit + " HP), starts "
                  + p.graceLeft.toFixed(3) + " s of grace and the knight flickers")
            check(spawned("damageNumber") === numbers,
                  "with debugMechanics off a hit shows no damage number ("
                  + (spawned("damageNumber") - numbers) + " shown)")
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
            let perfectWords = spawned("fightWord", "PERFECT")
            let res = p.takeDamage(20, p.xWu + 1, p.yWu)
            check(res === "perfect" && p.hp === before && p.graceLeft === 0
                  && Math.abs(p.mana - (manaBefore + Balance.knight.perfectBlockMana)) < 1e-3,
                  "a shield raised " + pf + " steps before a blow blocks it perfectly ("
                  + res + ", " + before + " -> " + p.hp + " HP, mana "
                  + manaBefore.toFixed(2) + " -> " + p.mana.toFixed(2) + ")")
            check(spawned("fightWord", "PERFECT") === perfectWords + 1,
                  "with debugMechanics off a perfect block shows PERFECT ("
                  + (spawned("fightWord", "PERFECT") - perfectWords) + " shown)")
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

            // A lunge that lands plays the knight's hurt, not the sword's
            // punch; in the grace a lunge and a shot play no hit. A
            // stand-in for the game of the grunt and of the knight records
            // what they would show and play.
            let shown = []
            let fake = {
                fx: false,
                playImpact: () => shown.push("impact sound"),
                playHurt: () => shown.push("hurt sound"),
                impact: (kind) => shown.push(kind),
                countFight: () => {},
                spawnDamageNumber: () => shown.push("damage number")
            }
            let g = game.enemies.find(x => x.enemyType === "grunt" && !x.destroyed)
            let realWorld = g.gameWorld
            let ownWorld = p.gameWorld
            g.xWu = p.xWu + 0.5
            g.yWu = p.yWu
            g.target = p
            g.gameWorld = fake
            p.gameWorld = fake
            g.performAttack()
            check(shown.filter(x => x === "hurt sound").length === 1
                  && shown.indexOf("impact sound") < 0 && p.graceLeft > 0,
                  "a lunge that lands plays the knight's hurt and no punch (" + shown.join(", ") + ")")
            shown = []
            let hp = p.hp
            g.performAttack()
            g.gameWorld = realWorld
            p.gameWorld = ownWorld
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
            let breaks = 0
            let countBreak = (action) => { if (action === "shieldBreak") breaks++ }
            p.acted.connect(countBreak)
            while (p.isBlocking && held < 6000) {
                Clayground.physicsStep(1)
                held++
            }
            let dry = Math.round(p.maxMana / drain / stepS)
            check(!p.isBlocking && p.mana === 0 && held === dry,
                  "the shield drops at 0 mana after " + held + " steps, " + dry + " expected")
            let shards = v.children.find(c => c.objectName === "shieldShards")
            let broke = !!shards && shards.visible
            let barFlashed = game.manaBarFlashing === true
            Clayground.physicsStep(10)
            p.acted.disconnect(countBreak)
            check(breaks === 1 && broke && barFlashed,
                  "a shield drained to 0 breaks once (acted " + breaks + "x, shards "
                  + broke + ", mana bar flash " + barFlashed + ")")
            p.isBlocking = true
            check(!p.isBlocking, "without mana the shield cannot be raised")
            // A right-click with no mana is no dead input: the empty click
            // and the mana bar's flash, the shield stays down
            let empty = []
            let emptyWorld = {
                playShieldEmpty: () => empty.push("playShieldEmpty"),
                flashManaBar: () => empty.push("flashManaBar")
            }
            p.gameWorld = emptyWorld
            mouse.mousePress(game, game.width / 2, game.height / 2, Qt.RightButton)
            let raised = p.isBlocking
            mouse.mouseRelease(game, game.width / 2, game.height / 2, Qt.RightButton)
            p.gameWorld = ownWorld
            check(!raised && empty.indexOf("playShieldEmpty") >= 0
                  && empty.indexOf("flashManaBar") >= 0,
                  "a right-click at 0 mana gives the empty feedback (" + (empty.join(", ") || "nothing")
                  + ") and leaves the shield down (" + raised + ")")
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
            let parryWords = spawned("fightWord", "PARRY")
            p.facingAngle = Math.atan2(pr.yWu - p.yWu, pr.xWu - p.xWu) * 180 / Math.PI
            p.attackCooldown = 0
            p.attack()
            Clayground.physicsStep(1)
            check(game.fightRecord.parries === parries + 1 && p.mana === Balance.knight.parryMana,
                  "a parry gives " + p.mana + " mana back, the table says " + Balance.knight.parryMana)
            check(spawned("fightWord", "PARRY") === parryWords + 1,
                  "with debugMechanics off a parry shows PARRY ("
                  + (spawned("fightWord", "PARRY") - parryWords) + " shown)")
            p.isBlocking = true
            check(p.isBlocking, "with mana back the shield rises again")
            p.isBlocking = false
            for (let o of game.enemies) o.target = null

            // Paused: a hit, the shield run dry and a right-click without
            // mana, each on its own feedback
            let hv = view(p)
            p.hp = p.maxHp
            p.graceLeft = 0
            p.facingAngle = 0
            p.takeDamage(20, p.xWu - 1, p.yWu)
            p.mana = 0.001
            p.isBlocking = true
            Clayground.physicsStep(1)
            p.raiseShield()
            kept = {
                chunk: find(game, "hpChunk").hp,
                hurt: find(hv, "hurtFlash").opacity,
                shards: find(hv, "shieldShards").visible,
                shardsT: find(hv, "shieldShards").t,
                mana: game.manaBarFlashing
            }
        }],
        // Wall clock passes, the world does not
        [600, () => {
            let p = game.player
            let hv = view(p)
            let now = {
                chunk: find(game, "hpChunk").hp,
                hurt: find(hv, "hurtFlash").opacity,
                shards: find(hv, "shieldShards").visible,
                shardsT: find(hv, "shieldShards").t,
                mana: game.manaBarFlashing
            }
            check(kept.chunk > p.hp && now.chunk === kept.chunk,
                  "paused, the HP chunk holds (" + kept.chunk.toFixed(2) + " -> "
                  + now.chunk.toFixed(2) + " HP over 600 ms, the knight at " + p.hp + ")")
            check(kept.hurt > 0.5 && now.hurt === kept.hurt,
                  "paused, the hurt flash holds (" + kept.hurt + " -> " + now.hurt + ")")
            check(kept.shards && now.shards && now.shardsT === kept.shardsT,
                  "paused, the shards hold (t " + kept.shardsT.toFixed(3) + " -> " + now.shardsT.toFixed(3) + ")")
            check(kept.mana && now.mana, "paused, the mana bar's flash holds (" + kept.mana + " -> " + now.mana + ")")
            // and they run on with the steps: each is over after its time
            Clayground.physicsStep(Math.ceil(Balance.hurt.chunkDrain / stepS) + 1)
            check(find(game, "hpChunk").hp === p.hp && find(hv, "hurtFlash").opacity === 0
                  && !find(hv, "shieldShards").visible && !game.manaBarFlashing,
                  "stepped on " + (Math.ceil(Balance.hurt.chunkDrain / stepS) + 1)
                  + " steps, the chunk has drained (" + find(game, "hpChunk").hp + " HP) and the flashes and shards are over")
            // The low shield's blink: off after half a blink, kept while
            // paused, on again after the next half
            p.mana = 5
            p.raiseShield()
            let arc = hv.children.find(c => c.thickness !== undefined)
            Clayground.physicsStep(Math.round(0.5 / Balance.shieldBreak.blink / stepS))
            kept = { blink: arc.opacity }
        }],
        [400, () => {
            let p = game.player
            let arc = view(p).children.find(c => c.thickness !== undefined)
            let paused = arc.opacity
            Clayground.physicsStep(Math.round(0.5 / Balance.shieldBreak.blink / stepS))
            check(kept.blink < 1 && paused === kept.blink && arc.opacity === 1,
                  "the low shield blinks on the steps: off " + kept.blink + ", still "
                  + paused + " after 400 ms paused, on " + arc.opacity + " half a blink later")
            p.isBlocking = false
            Clayground.paused = false
            console.log("[Answer] done,", failures, "failed")
        }],
        // The left button: a click swings, a hold charges a heavy swing
        [() => true, () => {
            Clayground.paused = true
            let p = game.player
            let k = Balance.knight
            let cx = game.width / 2, cy = game.height / 2
            for (let o of game.enemies) { o.target = null; o.parryWindow = false }
            p.isBlocking = false
            p.moveX = 0
            p.moveY = 0
            let ready = () => {
                p.facingAngle = 0
                p.graceLeft = 0
                p.attackCooldown = 0
                Clayground.physicsStep(Math.ceil((k.swingDuration + k.swingFade) / stepS) + 1)
            }
            let startSteps = Math.round(k.chargeStart / stepS)
            let fullSteps = Math.round(k.chargeTime / stepS)
            let letGoSteps = Math.round((k.chargeTime + k.chargeHold) / stepS)
            let actions = []
            let record = (a) => actions.push(a)
            p.acted.connect(record)

            // A click: released before chargeStart it swings at once, a
            // normal swing
            ready()
            mouse.mousePress(game, cx, cy, Qt.LeftButton)
            let onPress = p.isAttacking
            Clayground.physicsStep(startSteps - 1)
            let charging = p.isCharging
            mouse.mouseRelease(game, cx, cy, Qt.LeftButton)
            check(!onPress && !charging && p.isAttacking && !p.isHeavy,
                  "a click released after " + (startSteps - 1) + " steps swings normally on release"
                  + " (on press " + onPress + ", charging " + charging + ", swing "
                  + p.isAttacking + ", heavy " + p.isHeavy + ")")

            // Held, it charges from chargeStart, moving at chargeSpeed, and
            // is full at chargeTime
            ready()
            mouse.mousePress(game, cx, cy, Qt.LeftButton)
            Clayground.physicsStep(startSteps - 1)
            let before = p.isCharging
            Clayground.physicsStep(1)
            let began = p.isCharging
            p.moveX = 1
            Clayground.physicsStep(1)
            let vx = p.body.linearVelocity.x
            p.moveX = 0
            check(!before && began && Math.abs(vx - p.maxSpeed * k.chargeSpeed) < 1e-3,
                  "the charge begins on step " + startSteps + " and moves the knight at "
                  + vx.toFixed(3) + " wu/s, the table says " + (p.maxSpeed * k.chargeSpeed).toFixed(3))
            Clayground.physicsStep(fullSteps - startSteps - 2)
            let notYet = p.chargeFull
            Clayground.physicsStep(1)
            check(!notYet && p.chargeFull && p.chargeProgress === 1,
                  "the charge is full on step " + fullSteps + " (full a step before: " + notYet + ")")

            // Released full in front of a guardian that faces the knight:
            // 2.5x atk through its shield, and it staggers
            let gd = game.enemies.find(x => x.enemyType === "guardian" && !x.destroyed)
            gd.halt()
            gd.xWu = p.xWu + 1.5
            gd.yWu = p.yWu
            gd.facingAngle = 180
            Clayground.physicsStep(1)
            let front = gd._isShieldFacing(p.xWu, p.yWu)
            let hp0 = gd.hp
            let dealt0 = game.fightRecord.damageDealt
            actions = []
            mouse.mouseRelease(game, cx, cy, Qt.LeftButton)
            Clayground.physicsStep(1)
            let heavyDmg = Math.floor(p.atk * k.heavySwing)
            let lost = hp0 - gd.hp
            check(front && p.isHeavy && lost === heavyDmg - gd.def && gd.aiState === "stagger"
                  && actions.indexOf("heavy") >= 0,
                  "a full charge released at a guardian's shield deals " + heavyDmg + " ("
                  + k.heavySwing + "x atk " + p.atk + ") less its def " + gd.def + ": it lost "
                  + lost + " HP, is " + gd.aiState + " (from the front " + front + ", acted "
                  + actions.join(", ") + ")")
            check(game.fightRecord.damageDealt - dealt0 === lost,
                  "the heavy hit counts " + (game.fightRecord.damageDealt - dealt0) + " dealt")
            gd.halted = false
            gd.aiState = "patrol"
            gd.target = null
            gd.xWu = p.xWu - 6
            Clayground.physicsStep(1)

            // A hit taken while charging cancels the charge: its release
            // swings nothing
            ready()
            mouse.mousePress(game, cx, cy, Qt.LeftButton)
            Clayground.physicsStep(startSteps + 4)
            let wasCharging = p.isCharging
            p.takeDamage(20, p.xWu + 1, p.yWu)
            let cancelled = !p.isCharging
            Clayground.physicsStep(fullSteps)
            mouse.mouseRelease(game, cx, cy, Qt.LeftButton)
            check(wasCharging && cancelled && !p.chargeFull && !p.isAttacking,
                  "a hit while charging cancels it (charging " + wasCharging + ", after the hit "
                  + p.isCharging + ", release swings " + p.isAttacking + ")")
            Clayground.physicsStep(Math.ceil(k.hurtGrace / stepS) + 1)

            // Held chargeHold past full, the knight lets it go at normal
            // strength, and the release swings nothing more
            ready()
            let gr = game.enemies.find(x => x.enemyType === "grunt" && !x.destroyed)
            gr.halt()
            gr.hp = 100
            gr.xWu = p.xWu + 1.5
            gr.yWu = p.yWu
            mouse.mousePress(game, cx, cy, Qt.LeftButton)
            Clayground.physicsStep(letGoSteps - 1)
            let held = p.chargeFull && !p.isAttacking
            let ghp = gr.hp
            Clayground.physicsStep(1)
            let letGo = p.isAttacking && !p.isHeavy && !p.isCharging
            Clayground.physicsStep(1)
            let normalLost = ghp - gr.hp
            actions = []
            mouse.mouseRelease(game, cx, cy, Qt.LeftButton)
            let afterRelease = actions.slice()
            check(held && letGo && normalLost === p.atk - gr.def,
                  "held " + letGoSteps + " steps (" + (k.chargeTime + k.chargeHold).toFixed(1)
                  + " s), the charge goes at normal strength: " + normalLost + " HP, atk "
                  + p.atk + " less def " + gr.def + " (full until then " + held + ")")
            check(afterRelease.length === 0,
                  "its release later swings no second time (acted "
                  + (afterRelease.join(", ") || "nothing") + ")")
            gr.halted = false
            gr.aiState = "patrol"
            p.acted.disconnect(record)
            Clayground.paused = false
            console.log("[Answer] charge done,", failures, "failed")
        }],
        // Torn down before quitting, as the other benches do
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ]

    // Found by objectName anywhere under item
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

    // The floating texts of this kind (and this text) in the room
    function spawned(name, text) {
        return game.room.children.filter(o => o.objectName === name
                                         && (text === undefined || o.text === text)).length
    }

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
