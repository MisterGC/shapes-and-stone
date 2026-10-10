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
// right-click then answers with the empty click, knight.noManaWord and the
// mana bar's flash.
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
// past full it goes at normal strength. A tough guardian's crushing blow
// winds up for at least enemy.crushWindUp as aiState "crush", white-hot
// with a doubled ring, and its lunge opens no parry window; on a held
// shield it takes enemy.crushMana mana and enemy.crushShare of the damage
// and drops the shield for enemy.crushLockout, after which a held button
// raises it again; a perfect block takes it whole and staggers the
// guardian for enemy.stagger; a dash makes it miss. A full charge let go
// knight.whirlWindow steps before or after a dash starts whirls, a step
// more does not, nor does a charge that is not full; the whirlwind hits
// each enemy along its path once, knight.whirlSwing times atk, through a
// guardian's shield, and not one the heavy swing it turned hit already;
// the dash swing and the shield dash work as before, and a pause holds
// the window. A dash costs knight.dashMana and a whirlwind knight.whirlMana;
// short of it no dash starts and a full charge swings heavy, each showing
// knight.noManaWord and the mana bar's flash. A lunge or a shot that lands
// throws the knight knight.knockback wu along it, off the grunt; a crushing
// blow through the shield too, a blocked, perfect or dodged blow not; a
// wall stops it, a pause and a hit stop hold it. A blow or a shot the shield
// stops costs knight.blockMana; down knight.manaRegenDelay with nothing
// spent, mana comes back at knight.manaRegen, and a dash starts that over.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
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

    // Only this enemy has the knight as its target, a step from it; it
    // winds up no crushing blow
    function only(type) {
        let p = game.player
        let e = game.enemies.find(x => x.enemyType === type && !x.destroyed)
        for (let o of game.enemies) o.target = o === e ? p : null
        for (let o of game.enemies)
            if (o !== e) { o.aiState = "patrol"; o.parryWindow = false }
        e._knockT = 0
        e.attackCooldown = 0
        e._attackTimer = 0
        e.crushChance = 0
        return e
    }

    // The tough guardian, about to wind up a crushing blow at the knight,
    // 1.5 wu to its right
    function crusher() {
        let p = game.player
        let d = only("guardian")
        d.crushChance = 1
        d.xWu = p.xWu + 1.5
        d.yWu = p.yWu
        d.aiState = "chase"
        return d
    }
    // The knight faces e centre to centre, as the shield measures it
    function faceIt(p, e) {
        p.facingAngle = Math.atan2(e.yWu - e.heightWu / 2 - p.yWu + p.heightWu / 2,
                                   e.xWu + e.widthWu / 2 - p.xWu - p.widthWu / 2) * 180 / Math.PI
    }
    // Every item of this name anywhere under item
    function findAll(item, name, out) {
        out = out || []
        if (!item) return out
        if (item.objectName === name) out.push(item)
        let kids = item.children || []
        for (let i = 0; i < kids.length; i++) findAll(kids[i], name, out)
        return out
    }
    function shows(name) { return findAll(game, name).some(r => r.visible) }

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
                spawnDamageNumber: () => shown.push("damage number"),
                spawnHurtNumber: () => shown.push("damage number")
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
                spawnDamageNumber: () => {},
                spawnHurtNumber: () => {}
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
        // The crushing blow of a tough guardian, step by step
        [() => true, () => {
            Clayground.paused = true
            let p = game.player
            let e = Balance.enemy
            let acts = []
            let record = a => acts.push(a)
            p.acted.connect(record)
            p.hp = p.maxHp
            p.graceLeft = 0
            p.mana = p.maxMana
            p.shieldLock = 0
            p.lowerShield()
            Clayground.physicsStep(Balance.knight.perfectBlockRearm)

            // Its wind-up: aiState "crush" for at least crushWindUp, the
            // guardian white-hot and its ring doubled. The shield is held,
            // raised long before the blow
            let d = crusher()
            faceIt(p, d)
            p.raiseShield()
            let wound = stepUntil(d, "crush")
            let windUp = 0, looks = 0
            while (d.aiState === "crush" && windUp < 600) {
                if (d.crushing && shows("crushGlow") && shows("crushRing")) looks++
                Clayground.physicsStep(1)
                windUp++
            }
            let crushSteps = Math.round(e.crushWindUp / stepS)
            check(wound && d.aiState === "lunge" && windUp >= crushSteps && windUp >= minSteps,
                  "a crushing blow winds up for " + windUp + " steps (aiState \"crush\"), "
                  + crushSteps + " at least")
            check(looks === windUp, "for all " + looks + " of them the guardian glows white-hot and its ring is doubled")
            // Its lunge opens no parry window, its ring never flashes white;
            // on the held shield it lands: crushMana mana, crushShare of
            // the damage, the shield down for crushLockout
            let open = 0, white = 0, lunge = 0, hp = p.hp, mana = p.mana
            let crushed = game.fightRecord.crushed
            while (d.aiState === "lunge" && lunge < 600) {
                faceIt(p, d)
                hp = p.hp
                mana = p.mana
                Clayground.physicsStep(1)
                lunge++
                if (d.parryWindow) open++
                if (d.ringShows && Qt.colorEqual(d.ringColor, Balance.parryRing.flashColor)) white++
            }
            check(open === 0 && white === 0,
                  "its lunge (" + lunge + " steps) is open to a parry for " + open
                  + " steps and its ring white for " + white)
            let want = Math.max(Balance.minDamage,
                                Math.floor(Math.max(Balance.minDamage, d.atk - p.def) * e.crushShare))
            let manaLost = mana - p.mana
            let drain = Balance.knight.blockDrain * stepS
            check(hp - p.hp === want && manaLost >= e.crushMana - 1e-3 && manaLost <= e.crushMana + drain + 1e-3,
                  "on the held shield it takes " + (hp - p.hp) + " HP (" + e.crushShare + " of "
                  + Math.max(1, d.atk - p.def) + " is " + want + ") and " + manaLost.toFixed(3)
                  + " mana (crushMana " + e.crushMana + ", a step's drain " + drain.toFixed(3) + ")")
            check(!p.isBlocking && p.shieldLock > e.crushLockout - stepS - 1e-6
                  && p.shieldLock <= e.crushLockout + 1e-6
                  && acts.indexOf("shieldBreak") >= 0 && acts.indexOf("hurt") >= 0
                  && game.fightRecord.crushed === crushed + 1,
                  "the shield drops for " + p.shieldLock.toFixed(3) + " s (crushLockout " + e.crushLockout
                  + "), breaks and the knight is hurt (acted " + acts.join(", ") + ")")
            // Held, the button raises it again once the lockout is over
            p.raiseShield()
            let locked = 0
            while (!p.isBlocking && locked < 600) {
                Clayground.physicsStep(1)
                locked++
            }
            check(p.isBlocking && Math.abs(locked - e.crushLockout / stepS) <= 1,
                  "with the right button held the shield rises again after " + locked + " steps")
            p.lowerShield()
            d.target = null
            d.aiState = "recovery"
            Clayground.physicsStep(Math.round(Balance.knight.hurtGrace / stepS) + 1)

            // A perfect block takes it whole and staggers the guardian for
            // the full stagger
            p.hp = p.maxHp
            p.mana = p.maxMana - 10
            d = crusher()
            faceIt(p, d)
            let crushedAgain = stepUntil(d, "crush")
            stepUntil(d, "lunge")
            hp = p.hp
            mana = p.mana
            let n = 0
            while (d.aiState === "lunge" && n < 600) {
                faceIt(p, d)
                if (d._lungeSteps <= 4) p.raiseShield()
                Clayground.physicsStep(1)
                n++
            }
            check(crushedAgain && p.hp === hp && d.aiState === "stagger"
                  && Math.abs(d._attackTimer - e.stagger) < 1e-6
                  && p.mana > mana && game.fightRecord.crushed === crushed + 1,
                  "a perfect block takes a crushing blow whole (" + hp + " -> " + p.hp
                  + " HP) and staggers the guardian for " + d._attackTimer.toFixed(3)
                  + " s, the table's stagger is " + e.stagger + " (" + d.aiState + ")")
            p.lowerShield()
            d.target = null
            Clayground.physicsStep(Math.round(e.stagger / stepS) + 1)

            // A dash makes it miss
            p.hp = p.maxHp
            p.mana = p.maxMana
            p.dashCooldown = 0
            d = crusher()
            faceIt(p, d)
            stepUntil(d, "lunge")
            hp = p.hp
            mana = p.mana
            acts = []
            n = 0
            while (d.aiState === "lunge" && n < 600) {
                faceIt(p, d)
                if (d._lungeSteps <= 2 && !p.isDashing && p.dashCooldown <= 0) {
                    p.moveX = 0
                    p.moveY = 0
                    p.dash()
                }
                Clayground.physicsStep(1)
                n++
            }
            check(p.hp === hp && Math.abs(p.mana - (mana - Balance.knight.dashMana)) < 1e-6
                  && acts.indexOf("dash") >= 0
                  && acts.indexOf("hurt") < 0 && d.aiState === "recovery",
                  "in a dash a crushing blow misses (" + hp + " -> " + p.hp + " HP, acted "
                  + acts.join(", ") + ", the guardian " + d.aiState + ")")
            d.target = null
            d.aiState = "patrol"
            d.crushChance = Balance.enemy.crushChance
            p.acted.disconnect(record)
            Clayground.paused = false
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
        // The whirlwind: a full charge let go right around a dash's start
        [() => true, () => {
            Clayground.paused = true
            let p = game.player
            let k = Balance.knight
            let cx = game.width / 2, cy = game.height / 2
            let win = k.whirlWindow
            let fullSteps = Math.round(k.chargeTime / stepS)
            let foes = game.enemies.filter(e => !e.destroyed)
            for (let o of foes) { o.halt(); o.parryWindow = false; o.hp = 100 }
            let gr = foes.filter(e => e.enemyType === "grunt")[0]
            let gd = foes.find(e => e.enemyType === "guardian")
            let sp = foes.find(e => e.enemyType === "spitter")
            let x0 = p.xWu, y0 = p.yWu
            // The enemies stand behind the knight, out of its way, unless a
            // check puts one in it
            let away = () => {
                for (let i = 0; i < foes.length; i++) {
                    foes[i].halt()
                    foes[i].xWu = x0 - 6
                    foes[i].yWu = y0 + 3 - i * 2
                }
            }
            // Any swing, dash or whirlwind over, the knight back where it
            // started, facing right, standing
            let ready = () => {
                p.isBlocking = false
                p.moveX = 0
                p.moveY = 0
                p.facingAngle = 0
                Clayground.physicsStep(Math.ceil((k.whirlDuration + k.swingFade) / stepS) + 2)
                p.graceLeft = 0
                p.attackCooldown = 0
                p.dashCooldown = 0
                p.mana = p.maxMana
                p.xWu = x0
                p.yWu = y0
                away()
                Clayground.physicsStep(1)
            }
            // Held until the charge is full
            let charge = () => {
                ready()
                mouse.mousePress(game, cx, cy, Qt.LeftButton)
                Clayground.physicsStep(fullSteps)
                return p.chargeFull
            }
            let actions = []
            let record = (a) => actions.push(a)
            p.acted.connect(record)
            let whirls0 = game.fightRecord.whirlwinds

            // Let go of n steps before the dash starts
            let before = (n) => {
                let full = charge()
                mouse.mouseRelease(game, cx, cy, Qt.LeftButton)
                if (n > 0) Clayground.physicsStep(n)
                actions = []
                p.dash()
                return {full: full, whirl: p.isWhirling && actions.indexOf("whirlwind") >= 0,
                        acts: actions.join(", ")}
            }
            let b = before(win)
            check(b.full && b.whirl, "a full charge let go " + win + " steps before the dash starts"
                  + " whirls (full " + b.full + ", acted " + b.acts + ")")
            b = before(win + 1)
            check(b.full && !b.whirl && p.isDashing && p.isHeavy,
                  "let go " + (win + 1) + " steps before, it swings heavy and the dash stays a dash"
                  + " (acted " + b.acts + ", heavy " + p.isHeavy + ")")

            // Let go of n steps after the dash started
            let after = (n) => {
                let full = charge()
                p.dash()
                if (n > 0) Clayground.physicsStep(n)
                actions = []
                mouse.mouseRelease(game, cx, cy, Qt.LeftButton)
                return {full: full, whirl: p.isWhirling && actions.indexOf("whirlwind") >= 0,
                        acts: actions.join(", ") || "nothing"}
            }
            let a = after(win)
            check(a.full && a.whirl, "a full charge let go " + win + " steps after the dash started"
                  + " whirls (full " + a.full + ", acted " + a.acts + ")")
            a = after(win + 1)
            check(a.full && !a.whirl && !p.isAttacking && a.acts === "nothing",
                  "let go " + (win + 1) + " steps after, the dash has cancelled the charge: the"
                  + " release swings nothing (acted " + a.acts + ")")

            // A charge that is not full: the dash cancels it, and one let go
            // just before the dash swings normally
            ready()
            mouse.mousePress(game, cx, cy, Qt.LeftButton)
            Clayground.physicsStep(fullSteps - 1)
            let charging = p.isCharging && !p.chargeFull
            p.dash()
            actions = []
            mouse.mouseRelease(game, cx, cy, Qt.LeftButton)
            check(charging && !p.isWhirling && actions.length === 0,
                  "a charge not yet full, dashed with, whirls not and swings nothing (acted "
                  + (actions.join(", ") || "nothing") + ")")
            ready()
            mouse.mousePress(game, cx, cy, Qt.LeftButton)
            Clayground.physicsStep(fullSteps - 1)
            mouse.mouseRelease(game, cx, cy, Qt.LeftButton)
            let normal = p.isAttacking && !p.isHeavy
            actions = []
            p.dash()
            check(normal && !p.isWhirling && actions.indexOf("whirlwind") < 0,
                  "one let go just before a dash swings normally and whirls not (acted "
                  + actions.join(", ") + ")")

            // Along its path: a grunt the heavy swing hit just before, a
            // guardian facing the knight and the other grunt; the spitter
            // stands off the path
            let gr2 = foes.filter(e => e.enemyType === "grunt")[1]
            charge()
            gr.xWu = x0 + 1.5; gr.yWu = y0
            gd.xWu = x0 + 3.5; gd.yWu = y0 + 0.3; gd.facingAngle = 180
            gr2.xWu = x0 + 5.5; gr2.yWu = y0 - 0.3
            sp.xWu = x0 + 3.5; sp.yWu = y0 + 4
            let lost0 = foes.map(e => e.hp)
            let front = gd._isShieldFacing(p.xWu, p.yWu)
            let hits0 = game.fightRecord.whirlHits
            let dealt0 = game.fightRecord.damageDealt
            mouse.mouseRelease(game, cx, cy, Qt.LeftButton)
            Clayground.physicsStep(2)
            let heavyHit = 100 - gr.hp
            actions = []
            p.dash()
            let n = 0
            while (p.isDashing && n < 120) {
                Clayground.physicsStep(1)
                n++
            }
            Clayground.physicsStep(10)
            let lost = foes.map((e, i) => lost0[i] - e.hp)
            let whirlDmg = Math.floor(p.atk * k.whirlSwing)
            let lostOf = (e) => lost[foes.indexOf(e)]
            check(actions.indexOf("whirlwind") >= 0 && heavyHit === Math.floor(p.atk * k.heavySwing) - gr.def
                  && lostOf(gr) === heavyHit,
                  "the grunt the heavy swing hit just before is not hit again by its whirlwind (lost "
                  + lostOf(gr) + ", the heavy hit " + heavyHit + ")")
            check(front && lostOf(gd) === whirlDmg - gd.def && lostOf(gr2) === whirlDmg - gr2.def,
                  "the whirlwind hits the guardian through its shield and the grunt behind it once each, "
                  + whirlDmg + " (" + k.whirlSwing + "x atk " + p.atk + ") less def: they lost "
                  + lostOf(gd) + " and " + lostOf(gr2) + " (shield facing " + front + ")")
            check(lostOf(sp) === 0, "the spitter off its path is not hit (lost " + lostOf(sp) + ")")
            check(game.fightRecord.whirlHits - hits0 === 2
                  && game.fightRecord.whirlwinds - whirls0 === 1,
                  "the fight record counts " + (game.fightRecord.whirlHits - hits0)
                  + " whirlwind hits and " + (game.fightRecord.whirlwinds - whirls0)
                  + " whirlwind that landed; the earlier ones hit nothing")
            check(game.fightRecord.damageDealt - dealt0 === heavyHit + lostOf(gd) + lostOf(gr2),
                  "its hits count " + (game.fightRecord.damageDealt - dealt0) + " dealt")
            check(n <= Math.ceil((k.whirlDuration) / stepS) + 1 && !p.isWhirling,
                  "the whirlwind lasts " + n + " steps (" + k.whirlDuration + " s)")

            // The dash swing and the shield dash work as before
            ready()
            gr.halt(); gr.xWu = x0 + 1.5; gr.yWu = y0
            let ghp = gr.hp
            actions = []
            p.dash()
            mouse.mousePress(game, cx, cy, Qt.LeftButton)
            Clayground.physicsStep(2)
            mouse.mouseRelease(game, cx, cy, Qt.LeftButton)
            check(ghp - gr.hp === Math.floor(p.atk * k.dashingSwing) - gr.def
                  && actions.indexOf("whirlwind") < 0,
                  "a click in a dash swings the dash swing: " + (ghp - gr.hp) + " HP (acted "
                  + actions.join(", ") + ")")
            ready()
            gd.halt(); gd.xWu = x0 + 1.5; gd.yWu = y0; gd.facingAngle = 180
            p.mana = p.maxMana
            p.isBlocking = true
            actions = []
            p.dash()
            Clayground.physicsStep(3)
            check(gd.aiState === "stagger" && actions.indexOf("whirlwind") < 0,
                  "a shield dash still breaks a guardian's guard (" + gd.aiState + ", acted "
                  + actions.join(", ") + ")")
            p.isBlocking = false

            // Mana pays for a dash and a whirlwind; without it a dash does
            // not start and a full charge swings heavy, each refusal with
            // the word over the knight and the mana bar's flash
            ready()
            let m0 = p.mana
            p.dash()
            check(p.isDashing && Math.abs(m0 - p.mana - k.dashMana) < 1e-6,
                  "a dash costs " + (m0 - p.mana).toFixed(2) + " mana, the table says " + k.dashMana)
            let w = before(0)
            check(w.whirl && Math.abs(p.maxMana - p.mana - k.whirlMana) < 1e-6,
                  "a whirlwind costs " + (p.maxMana - p.mana).toFixed(2) + " mana with its dash, the table says "
                  + k.whirlMana)
            ready()
            p.mana = k.dashMana - 1
            let words = spawned("fightWord", k.noManaWord)
            actions = []
            p.dash()
            check(!p.isDashing && actions.indexOf("dash") < 0 && p.mana === k.dashMana - 1
                  && spawned("fightWord", k.noManaWord) === words + 1 && game.manaBarFlashing,
                  "with " + (k.dashMana - 1) + " mana no dash starts, " + k.noManaWord
                  + " shows and the mana bar flashes (acted " + (actions.join(", ") || "nothing") + ")")
            ready()
            charge()
            p.mana = k.whirlMana - 1
            words = spawned("fightWord", k.noManaWord)
            mouse.mouseRelease(game, cx, cy, Qt.LeftButton)
            actions = []
            p.dash()
            check(p.isDashing && !p.isWhirling && p.isHeavy && actions.indexOf("whirlwind") < 0
                  && spawned("fightWord", k.noManaWord) === words + 1,
                  "with " + (k.whirlMana - 1) + " mana a full charge let go into a dash swings heavy and"
                  + " dashes, " + k.noManaWord + " shows (acted " + actions.join(", ") + ")")
            ready()
            charge()
            p.dash()
            p.mana = k.whirlMana - k.dashMana - 1
            words = spawned("fightWord", k.noManaWord)
            actions = []
            mouse.mouseRelease(game, cx, cy, Qt.LeftButton)
            check(!p.isWhirling && actions.indexOf("heavy") >= 0
                  && spawned("fightWord", k.noManaWord) === words + 1,
                  "a full charge held into a dash and let go short of the whirlwind's mana swings heavy, "
                  + k.noManaWord + " shows (acted " + actions.join(", ") + ")")

            // A full charge held into a dash, the game paused: the window
            // counts physics steps, not the wall clock
            charge()
            p.dash()
            kept = p
        }],
        [300, () => {
            let p = kept
            let actions = []
            let record = (a) => actions.push(a)
            p.acted.connect(record)
            mouse.mouseRelease(game, game.width / 2, game.height / 2, Qt.LeftButton)
            check(p.isWhirling && actions.indexOf("whirlwind") >= 0,
                  "paused 300 ms after a dash with a full charge, its release still whirls (acted "
                  + (actions.join(", ") || "nothing") + ")")
            p.acted.disconnect(record)
            for (let o of game.enemies) if (!o.destroyed) { o.halted = false; o.aiState = "patrol" }
            Clayground.physicsStep(Math.ceil(Balance.knight.whirlDuration / stepS) + 2)
            Clayground.paused = false
            console.log("[Answer] whirlwind done,", failures, "failed")
        }],
        [() => true, () => {
            // The knock-back: in the fight room's middle, the others idle
            Clayground.paused = true
            let p = game.player
            let k = Balance.knight
            let kSteps = Math.round(k.knockbackDuration / stepS)
            let ready = () => {
                p.hp = p.maxHp; p.mana = p.maxMana; p.graceLeft = 0
                p.isBlocking = false; p.shieldLock = 0; p._knockT = 0
                p.xWu = game._fightRoomCx; p.yWu = game._fightRoomCy
                Clayground.physicsStep(Balance.knight.perfectBlockRearm)
            }
            let moved = (x, y) => Math.sqrt((p.xWu - x) * (p.xWu - x) + (p.yWu - y) * (p.yWu - y))
            let overlaps = (e) => e.xWu < p.xWu + p.widthWu && p.xWu < e.xWu + e.widthWu
                && e.yWu - e.heightWu < p.yWu && p.yWu - p.heightWu < e.yWu

            // A grunt's lunge that lands throws the knight back along it,
            // knockback wu, and off the grunt that covered it
            ready()
            let g = only("grunt")
            g.xWu = p.xWu + 1.5
            g.yWu = p.yWu
            g.aiState = "chase"
            let lunged = stepUntil(g, "lunge"), n = 0
            while (p.graceLeft === 0 && g.aiState === "lunge" && n < 600) {
                Clayground.physicsStep(1)
                n++
            }
            let hitX = p.xWu, hitY = p.yWu, covered = overlaps(g)
            let lx = g._dirToTargetX, ly = g._dirToTargetY
            g.target = null
            Clayground.physicsStep(kSteps + 2)
            let d = moved(hitX, hitY)
            // Along the lunge: the throw's direction is the lunge's
            let along = d > 0 ? ((p.xWu - hitX) * lx + (p.yWu - hitY) * ly) / d : 0
            check(lunged && p.graceLeft > 0 && p.xWu < hitX && Math.abs(d - k.knockback) < 0.1
                  && along > 0.99,
                  "a lunge that lands from the right throws the knight " + d.toFixed(3)
                  + " wu along it (" + along.toFixed(3) + "), the table says " + k.knockback)
            check(!overlaps(g),
                  "after the knock-back the grunt no longer covers the knight (covered at the hit: "
                  + covered + ", gap " + (g.xWu - p.xWu - p.widthWu).toFixed(3) + " wu)")
            check(p._knockT === 0 && p.body.linearVelocity.x === 0,
                  "the knock-back is over after " + kSteps + " steps and the knight stands")

            // A blow the held shield stops, one it stops perfectly and one
            // a dash dodges throw nothing back
            ready()
            p.facingAngle = 0
            p.isBlocking = true
            Clayground.physicsStep(Balance.knight.perfectBlockFrames + 1)
            let x0 = p.xWu, y0 = p.yWu
            let res = p.takeDamage(20, p.xWu + 1, p.yWu)
            Clayground.physicsStep(kSteps)
            check(res === "blocked" && p._knockT === 0 && moved(x0, y0) < 1e-3,
                  "a blow the held shield stops throws nothing back (" + res + ", moved "
                  + moved(x0, y0).toFixed(3) + " wu)")
            ready()
            p.isBlocking = true
            Clayground.physicsStep(1)
            x0 = p.xWu; y0 = p.yWu
            res = p.takeDamage(20, p.xWu + 1, p.yWu)
            Clayground.physicsStep(kSteps)
            check(res === "perfect" && p._knockT === 0 && moved(x0, y0) < 1e-3,
                  "a blow blocked perfectly throws nothing back (" + res + ", moved "
                  + moved(x0, y0).toFixed(3) + " wu)")
            ready()
            p.dashCooldown = 0
            p.dash()
            res = p.takeDamage(20, p.xWu + 1, p.yWu)
            check(res === "dodged" && p._knockT === 0,
                  "a blow a dash dodges throws nothing back (" + res + ")")
            Clayground.physicsStep(Math.ceil(k.dashDuration / stepS) + 1)

            // A crushing blow through the held shield throws it back
            ready()
            p.isBlocking = true
            Clayground.physicsStep(Balance.knight.perfectBlockFrames + 1)
            x0 = p.xWu; y0 = p.yWu
            res = p.takeDamage(20, p.xWu + 1, p.yWu, undefined, true)
            Clayground.physicsStep(kSteps + 2)
            d = moved(x0, y0)
            check(res === "crushed" && p.xWu < x0 && Math.abs(d - k.knockback) < 0.1,
                  "a crushing blow through the held shield throws the knight " + d.toFixed(3)
                  + " wu back (" + res + ")")

            // A shot that lands throws it along the shot's flight
            ready()
            x0 = p.xWu; y0 = p.yWu
            game.spawnProjectile(p.xWu + 20, p.yWu, -1, 0, 8)
            let shots = game.room.children.filter(o => o.objectName === "projectile" && !o.destroyed)
            shots[shots.length - 1].onHitPlayer({ getBody: () => ({ target: p }) })
            Clayground.physicsStep(kSteps + 2)
            check(p.xWu < x0 && Math.abs(moved(x0, y0) - k.knockback) < 0.1
                  && Math.abs(p.yWu - y0) < 0.05,
                  "a shot flying west that lands throws the knight " + (x0 - p.xWu).toFixed(3)
                  + " wu west")

            // A wall stops it: the knight 0.3 wu left of the room's east
            // wall, hit from the west
            ready()
            let cs = game.cellSize
            let row = Math.floor((p.yWu - p.heightWu / 2) / cs)
            let gx = Math.floor(p.xWu / cs)
            while (gx < game.gridWidth && game.grid[row][gx] !== game.cellWall) gx++
            let wallX = gx * cs
            p.xWu = wallX - p.widthWu - 0.3
            Clayground.physicsStep(1)
            x0 = p.xWu
            res = p.takeDamage(20, p.xWu - 1, p.yWu)
            Clayground.physicsStep(kSteps + 2)
            // The knight's body is a circle of 0.45 of its width
            let edge = p.xWu + p.widthWu * 0.95
            check(res === "hit" && p.xWu > x0 && p.xWu - x0 < k.knockback && edge <= wallX + 0.02,
                  "a hit towards a wall 0.3 wu away throws the knight " + (p.xWu - x0).toFixed(3)
                  + " wu, up to the wall (its body's edge " + edge.toFixed(3)
                  + ", the wall " + wallX + ")")

            // A pause holds it: hit, then the world stands for a while
            ready()
            res = p.takeDamage(20, p.xWu + 1, p.yWu)
            Clayground.physicsStep(2)
            kept = {x: p.xWu, y: p.yWu, t: p._knockT}
        }],
        [500, () => {
            let p = game.player
            check(kept.t > 0 && p._knockT === kept.t && p.xWu === kept.x && p.yWu === kept.y,
                  "paused 500 ms two steps into a knock-back, the knight holds ("
                  + kept.t.toFixed(3) + " -> " + p._knockT.toFixed(3) + " s left)")
            // A full hit stop holds it the same
            Clayground.paused = false
            game.hitStop(1500, 0)
            kept = {x: p.xWu, y: p.yWu, t: p._knockT}
        }],
        [500, () => {
            let p = game.player
            check(game.hitStopActive && p._knockT === kept.t
                  && Math.abs(p.xWu - kept.x) < 1e-3 && Math.abs(p.yWu - kept.y) < 1e-3,
                  "500 ms into a full hit stop the knock-back holds ("
                  + kept.t.toFixed(3) + " -> " + p._knockT.toFixed(3) + " s left)")
        }],
        [() => !game.hitStopActive, () => {}],
        [300, () => {
            let p = game.player
            check(p._knockT === 0 && p.xWu < kept.x,
                  "after the hit stop the knock-back runs on and out (moved "
                  + (kept.x - p.xWu).toFixed(3) + " wu)")
            console.log("[Answer] knock-back done,", failures, "failed")
        }],
        [() => true, () => {
            // Mana: a blow the held shield stops costs blockMana, a shot it
            // deflects too; down manaRegenDelay with nothing spent, mana
            // comes back at manaRegen per second, and spending starts over
            Clayground.paused = true
            let p = game.player
            let k = Balance.knight
            for (let o of game.enemies) if (!o.destroyed) { o.halt(); o.target = null }
            p.xWu = game._fightRoomCx; p.yWu = game._fightRoomCy
            p.hp = p.maxHp; p.graceLeft = 0; p.dashCooldown = 0
            p.facingAngle = 0
            p.mana = p.maxMana
            p.isBlocking = true
            Clayground.physicsStep(k.perfectBlockFrames + 1)
            let m0 = p.mana
            let res = p.takeDamage(20, p.xWu + 1, p.yWu)
            check(res === "blocked" && Math.abs(m0 - p.mana - p.blockMana) < 1e-6,
                  "a blocked blow costs " + (m0 - p.mana).toFixed(2) + " mana, the table says " + k.blockMana)
            m0 = p.mana
            game.spawnProjectile(p.xWu + 20, p.yWu, -1, 0, 8)
            let shots = game.room.children.filter(o => o.objectName === "projectile" && !o.destroyed)
            shots[shots.length - 1].onHitPlayer({ getBody: () => ({ target: p }) })
            check(Math.abs(m0 - p.mana - p.blockMana) < 1e-6,
                  "a shot the shield deflects costs " + (m0 - p.mana).toFixed(2) + " mana")
            p.isBlocking = false
            let delay = Math.round(k.manaRegenDelay / stepS)
            m0 = p.mana
            Clayground.physicsStep(delay - 1)
            let before = p.mana
            Clayground.physicsStep(61)
            check(before === m0 && Math.abs(p.mana - m0 - k.manaRegen) < 0.1,
                  "the lowered shield's mana stays " + delay + " steps, then comes back "
                  + (p.mana - m0).toFixed(2) + " in a second, the table says " + k.manaRegen)
            p.dash()
            m0 = p.mana
            Clayground.physicsStep(delay - 1)
            before = p.mana
            Clayground.physicsStep(2)
            check(before === m0 && p.mana > m0,
                  "a dash starts the rest over: " + (delay - 1) + " steps after it no mana came back ("
                  + m0.toFixed(2) + " -> " + before.toFixed(2) + "), two steps later it does ("
                  + p.mana.toFixed(2) + ")")
            console.log("[Answer] mana done,", failures, "failed")
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
