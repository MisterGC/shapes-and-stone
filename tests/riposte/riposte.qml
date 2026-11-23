// Riposte bench - a swing right after a block is a riposte (issue #365).
//
// Starts the fight room paused (Clayground.paused) and single-steps it
// (Clayground.physicsStep), at the game's duel pace. A grunt lead, its
// lunge stopped by the knight's held shield, and the knight 1.2 wu off,
// facing it:
// - the riposte's window is Balance.lead.riposte.frames physics steps
//   times the duel pace, rounded, at each of Swift, Standard and
//   Deliberate: 30 steps, half a second, at Standard;
// - a swing begun on the window's last step lands whole on the lead into
//   its guard, its stance full and worn low alike, the number shown is
//   what it lost, and it gives back the mana the block cost: the knight's
//   mana is what it was when the shield rose; it shows the word
//   lead.riposte.word, plays the shield's clang lead.riposte.pitch
//   semitones up, the record counts one riposte;
// - one begun a step after the window, a second swing after a riposte and
//   a charged swing are no riposte: the guard's share, no mana back;
// - a guardian lead takes a riposte whole through its shield;
// - a perfect block still opens the lead, and pays more than a held block
//   with its riposte: no HP lost against some, mana gained against none,
//   the swing after it lands lead.openingDamage times against whole;
// - at every pace, against each string of a grunt and a guardian lead, a
//   knight that holds its shield from the string's start and ripostes
//   every blow stops every strike, ripostes each one, and ends the string
//   - its last riposte landed - with at least the mana it began with;
// - a lead shown on another screen gives the riposte's whole number, and
//   the host's lead takes it whole;
// - a host's lead's blow stopped by a joiner's held shield, landed as the
//   joiner's screen lands it (Game._landKnightBlow), opens the window on
//   that lead, and so do a spitter lead's shot and a slinger lead's ball
//   stopped by the held shield (Game.shotLanded, ballLanded): a swing in
//   it lands whole;
// - against a normal grunt nothing changes: a swing right after its
//   blocked lunge lands as any swing, no riposte, no mana back; the Hollow
//   Warden gives no riposte either (issue #368): a swing right after a
//   block takes lead.warden.chip.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/riposte/riposte.qml

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
        console.log("[Riposte]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Riposte] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true})
        script.start()
    }

    function near(a, b, tol) { return Math.abs(a - b) <= (tol === undefined ? 1e-6 : tol) }
    function r3(x) { return Math.round(x * 1000) / 1000 }

    // Where the knight stands for every check, set once the room is up
    property point home: Qt.point(0, 0)
    // e stands 1.2 wu to the right of the knight, back at home, its AI
    // halted in state, with HP that lasts and its stance full; every other
    // enemy halted and out of the way
    function setUp(e, state, lead) {
        let p = game.player
        p.xWu = home.x
        p.yWu = home.y
        let k = 0
        for (let o of game.enemies) {
            if (o === e || o.destroyed) continue
            o.halt()
            if (Math.hypot(o.xWu - home.x, o.yWu - home.y) < 4) {
                o.xWu = home.x - 5 + 2 * (k++)
                o.yWu = home.y + 5
            }
        }
        e.halt()
        e.lead = lead !== false
        e.maxHp = 100000
        e.hp = 100000
        e.crushChance = 0
        e.target = p
        e._setStance(1)
        e._stanceRest = 0
        e.xWu = p.xWu + 1.2
        e.yWu = p.yWu + e.bulk
        e.aiState = state
        e.halted = true
        knightReady(e)
        return e
    }
    // The knight faces e centre to centre, as the shield measures it
    // (Player.isShieldFacing)
    function face(e) {
        let p = game.player
        p.facingAngle = Math.atan2(e.yWu - e.heightWu / 2 - p.yWu + p.heightWu / 2,
                                   e.xWu + e.widthWu / 2 - p.xWu - p.widthWu / 2) * 180 / Math.PI
    }
    // and corner to corner, as its swing's arc reads it (Player.
    // isInAttackArc): a lead's lunge ends on the knight, and that close
    // the two differ by more than the arc
    function faceSwing(e) {
        let p = game.player
        p.facingAngle = Math.atan2(e.yWu - p.yWu, e.xWu - p.xWu) * 180 / Math.PI
    }
    // The knight whole and ready to swing, its shield down, facing e
    function knightReady(e) {
        let p = game.player
        if (p.isCharging || p._charge === "spent") p.dropSwing()
        p.lowerShield()
        p.isBlocking = false
        p.hp = p.maxHp
        p.mana = p.maxMana
        p.graceLeft = 0
        // No riposte left open from the check before
        p._riposteLead = null
        face(e)
        let n = 0
        while ((p.isAttacking || p.attackCooldown > 0) && n < 600) {
            Clayground.physicsStep(1)
            n++
        }
    }
    // The numbers and words over things now, by the item
    function shown(name) {
        let out = []
        let parents = [game.glowParent(), game.room]
        for (let par of parents)
            for (let i = 0; i < par.children.length; i++) {
                let c = par.children[i]
                if (c.objectName === name && out.indexOf(c) < 0) out.push(c)
            }
        return out
    }
    // The knight's swing's damage on e before any share, a charged one's
    // when heavy, one behind the shield when blocking
    function base(e, heavy, blocking) {
        let p = game.player
        let amount = heavy ? Math.floor(p.atk * Balance.knight.heavySwing)
                   : blocking ? Math.floor(p.atk * Balance.knight.blockingSwing) : p.atk
        return Math.max(Balance.minDamage, amount - e.def)
    }
    function guard(e, heavy) { return Math.max(Balance.minDamage, Math.round(base(e, heavy) * Balance.lead.guard)) }

    // e lunges at the knight, which holds its shield up from well before
    // the blow (a held block) or raises it just before it lands (perfect),
    // standing where it stands, at mana; the lunge played out, e stands
    // halted 1.2 wu off in state, its stance at stance. Then, delay steps
    // after the blow, the knight swings - a charged swing when heavy, a
    // second swing after the first when twice -, its shield lowered first
    // unless keep. Returns what became of the blow and the swing
    function blockThenSwing(e, o) {
        let p = game.player
        setUp(e, "chase", o.lead)
        let x = p.xWu, y = p.yWu, gx = e.xWu, gy = e.yWu
        let perfect = o.perfect === true
        let hold = up => {
            p.xWu = x
            p.yWu = y
            face(e)
            p.isBlocking = up
        }
        // Down long enough for a perfect block to count, or up long before
        // the blow for a held one
        if (o.mana !== undefined) p.mana = o.mana
        let raisedMana = p.mana
        for (let i = 0; i < 60; i++) {
            hold(!perfect)
            e.xWu = gx
            e.yWu = gy
            Clayground.physicsStep(1)
        }
        let rec = game.fightRecord
        let blocks0 = rec.blocks, perfect0 = rec.perfectBlocks, ripostes0 = rec.ripostes
        let hp0 = p.hp
        let causes = []
        let onOpened = c => causes.push(c)
        e.opened.connect(onOpened)
        e.halted = false
        e.windUp(0.2)
        let n = 0
        while ((e.aiState === "telegraph" || e.aiState === "lunge") && n < 300) {
            hold(perfect ? e.aiState === "lunge" && e._lungeSteps <= 4 : true)
            Clayground.physicsStep(1)
            n++
        }
        e.opened.disconnect(onOpened)
        let opened = e.opening
        let afterBlock = p.mana
        // e halted where the check wants it: in its guard, or open
        if (!opened) {
            e.halted = true
            e.aiState = o.state || "telegraph"
            e._setStance(o.stance === undefined ? 1 : o.stance)
        } else {
            e.halted = true
        }
        e.xWu = gx
        e.yWu = gy
        if (o.keep !== true) {
            p.lowerShield()
            p.isBlocking = false
        }
        let manaPreSwing = p.mana
        let hpE = e.hp
        let numbers0 = shown("damageNumber"), words0 = shown("fightWord")
        game.logSounds = true
        let log0 = game.soundLog.length
        // The swing begins delay physics steps after the step the shield
        // stopped the blow on (Player._riposteFrom); a perfect block opens
        // no riposte, so its swing counts from the blow
        let from = perfect ? p._steps : p._riposteFrom
        while (p._steps - from < o.delay) {
            hold(o.keep === true)
            Clayground.physicsStep(1)
        }
        let stanceBefore = e._stanceLeft
        if (o.heavy) {
            p.pressSwing()
            let k = 0
            while (!p.chargeFull && k < 600) { p.xWu = x; p.yWu = y; face(e); Clayground.physicsStep(1); k++ }
            p.releaseSwing()
        } else {
            p.attack()
        }
        let first = -1
        n = 0
        while (e.hp === hpE && n < 60) { hold(o.keep === true); Clayground.physicsStep(1); n++ }
        first = hpE - e.hp
        let manaFirst = p.mana
        let second = -1
        if (o.twice) {
            let k = 0
            while ((p.isAttacking || p.attackCooldown > 0) && k < 120) { hold(false); Clayground.physicsStep(1); k++ }
            let h2 = e.hp
            p.attack()
            k = 0
            while (e.hp === h2 && k < 60) { hold(false); Clayground.physicsStep(1); k++ }
            second = h2 - e.hp
        }
        let out = {
            blocked: rec.blocks - blocks0, perfect: rec.perfectBlocks - perfect0, ripostes: rec.ripostes - ripostes0,
            hurt: hp0 - p.hp, opened: opened, causes: causes,
            raisedMana: raisedMana, afterBlock: afterBlock, preSwing: manaPreSwing, afterSwing: manaFirst,
            lost: first, second: second, stanceBefore: stanceBefore, stance: e._stanceLeft,
            numbers: shown("damageNumber").filter(x => numbers0.indexOf(x) < 0).map(x => x.text),
            words: shown("fightWord").filter(x => words0.indexOf(x) < 0).map(x => x.text),
            sounds: game.soundLog.slice(log0).filter(s => s.what === "riposte")
        }
        game.logSounds = false
        e.halt()
        knightReady(e)
        return out
    }
    function word() { return Balance.lead.riposte.word }

    function checkWindow(g) {
        let rp = Balance.lead.riposte
        for (let s of Balance.pace.steps) {
            game.duelPace = s.name
            let want = Math.round(rp.frames * s.factor)
            check(g.riposteable && g.riposteFrames === want,
                  s.name + ": the riposte's window is " + g.riposteFrames + " physics steps (lead.riposte.frames "
                  + rp.frames + " times " + s.factor + ", rounded, is " + want + ")")
        }
        game.duelPace = Balance.pace.standard
        check(g.riposteFrames === 30, "at Standard that is " + g.riposteFrames + " steps, "
              + r3(g.riposteFrames / 60) + " s")
    }

    function checkRiposte(g) {
        let l = Balance.lead, rp = l.riposte
        let p = game.player
        for (let stance of [1, 0.3]) {
            let r = blockThenSwing(g, {delay: g.riposteFrames, mana: 30, stance: stance})
            check(r.blocked === 1 && r.perfect === 0 && r.hurt > 0 && r.lost === base(g)
                  && r.numbers.length === 1 && Number(r.numbers[0]) === r.lost,
                  "a swing begun on the window's last step (" + g.riposteFrames + ") after a held block, the lead "
                  + "in its guard, its stance at " + stance + ", lands whole: " + r.lost + " HP (" + base(g)
                  + ", the guard's share is " + guard(g) + "), the number shows " + r.numbers.join())
            check(near(r.afterSwing, r.raisedMana, 1e-6) && r.afterBlock < r.raisedMana - p.blockMana + 1e-6,
                  "and gives back the mana that block cost: " + r3(r.raisedMana) + " as the shield rose, "
                  + r3(r.afterBlock) + " after the blow (" + p.blockMana + " and the upkeep), " + r3(r.afterSwing)
                  + " after the riposte")
            check(r.ripostes === 1 && r.words.join() === rp.word && r.sounds.length === 1
                  && r.sounds[0].cue === "sfx/shield_clang" && r.sounds[0].pitch === rp.pitch
                  && near(r.stance, Math.max(0, r.stanceBefore - l.wear)),
                  "it shows " + (r.words.join() || "no word") + ", plays " + r.sounds.map(s => s.cue + " "
                  + s.pitch).join() + " (lead.riposte.pitch " + rp.pitch + "), the record counts " + r.ripostes
                  + " riposte, and the stance wears as by any blow, " + r3(r.stanceBefore) + " to " + r3(r.stance))
        }
        // The shield kept up through the swing: the swing behind the
        // shield's damage, whole
        let k = blockThenSwing(g, {delay: 10, mana: 30, keep: true})
        check(k.lost === base(g, false, true) && k.ripostes === 1 && near(k.afterSwing, k.raisedMana, 1e-6),
              "a riposte behind the held shield lands whole too: " + k.lost + " HP (" + base(g, false, true)
              + "), its mana back to " + r3(k.afterSwing) + " (" + r3(k.raisedMana) + ")")
        let late = blockThenSwing(g, {delay: g.riposteFrames + 1, mana: 30})
        check(late.lost === guard(g) && late.ripostes === 0 && near(late.afterSwing, late.preSwing, 1e-6)
              && late.words.length === 0 && late.sounds.length === 0,
              "one begun a step after the window is no riposte: " + late.lost + " HP (the guard's " + guard(g)
              + "), mana " + r3(late.afterSwing) + " as before it (" + r3(late.preSwing) + "), no word, no ring")
        let twice = blockThenSwing(g, {delay: 2, mana: 30, twice: true})
        check(twice.lost === base(g) && twice.second === guard(g) && twice.ripostes === 1,
              "one block, one riposte: the first swing lands whole (" + twice.lost + "), a second swing after it "
              + "takes the guard's share (" + twice.second + " of " + guard(g) + ")")
        let heavy = blockThenSwing(g, {delay: 1, mana: 30, heavy: true})
        check(heavy.lost === guard(g, true) && heavy.ripostes === 0,
              "a charged swing right after the block is no riposte: " + heavy.lost + " HP (the guard's share of "
              + base(g, true) + " is " + guard(g, true) + ")")
    }

    function checkGuardian(gu) {
        let r = blockThenSwing(gu, {delay: 10, mana: 30})
        check(r.blocked === 1 && r.lost === base(gu) && r.ripostes === 1,
              "a guardian lead, its shield towards the knight, takes a riposte whole: " + r.lost + " HP ("
              + base(gu) + ")")
    }

    function checkPerfect(g) {
        let l = Balance.lead
        let held = blockThenSwing(g, {delay: 10, mana: 30})
        let pb = blockThenSwing(g, {delay: 10, mana: 30, perfect: true})
        check(pb.perfect === 1 && pb.opened && pb.causes.join() === "perfect",
              "a perfect block still opens the lead (" + (pb.causes.join() || "nothing") + ")")
        let heldNet = held.afterSwing - held.raisedMana, pbNet = pb.afterSwing - pb.raisedMana
        check(pb.hurt === 0 && held.hurt > 0 && pbNet > heldNet + 1e-6
              && pb.lost === Math.floor(base(g) * l.openingDamage) && pb.lost > held.lost && pb.ripostes === 0,
              "and pays more than a held block with its riposte: " + pb.hurt + " HP lost against " + held.hurt
              + ", mana " + (pbNet >= 0 ? "+" : "") + r3(pbNet) + " against " + (heldNet >= 0 ? "+" : "")
              + r3(heldNet) + ", the swing after it " + pb.lost + " HP against " + held.lost)
    }

    // Lead e plays string i of its kind at the knight, which holds its
    // shield up from the string's start, standing, and swings delay steps
    // after each blow its shield stopped. What the knight's mana was then
    // and as its last riposte landed, the strikes, blocks and ripostes
    function playString(e, i, delay) {
        let p = game.player
        setUp(e, "chase")
        let x = p.xWu, y = p.yWu
        p.mana = 30
        // Up well before the first blow: no perfect block
        p.isBlocking = true
        let rec = game.fightRecord
        let blocks0 = rec.blocks, perfect0 = rec.perfectBlocks, ripostes0 = rec.ripostes, hp0 = p.hp
        e.halted = false
        e.target = p
        let begun = p.mana
        e.beginString(i)
        let strikes = 0, last = e.aiState, due = -1, seen = null, n = 0
        let swung = 0, end = p.mana, ripostes = rec.ripostes
        while (n < 900) {
            p.xWu = x
            p.yWu = y
            if (p.isAttacking) faceSwing(e)
            else face(e)
            p.isBlocking = true
            if (due >= 0 && n >= due) {
                faceSwing(e)
                p.attack()
                swung++
                due = -1
            }
            Clayground.physicsStep(1)
            if (p._riposteLead === e && p._riposteFrom !== seen) {
                seen = p._riposteFrom
                due = n + delay
            }
            // The mana as each riposte lands: the last one ends the string
            if (rec.ripostes !== ripostes) {
                ripostes = rec.ripostes
                end = p.mana
            }
            if (e.aiState === "lunge" && last !== "lunge") strikes++
            last = e.aiState
            n++
            if (e.aiState !== "telegraph" && e.aiState !== "lunge" && e.aiState !== "recovery" && due < 0
                    && !p.isAttacking && e._string.length === 0)
                break
        }
        let out = {begun: begun, end: end, strikes: strikes, blocks: rec.blocks - blocks0, swung: swung,
                   perfect: rec.perfectBlocks - perfect0, ripostes: rec.ripostes - ripostes0, hurt: hp0 - p.hp,
                   state: e.aiState}
        e.halt()
        knightReady(e)
        return out
    }
    function checkStrings(g, gu) {
        for (let s of Balance.pace.steps) {
            game.duelPace = s.name
            for (let [e, kind] of [[g, "grunt"], [gu, "guardian"]]) {
                let list = Balance.lead.strings[kind]
                for (let i = 0; i < list.length; i++) {
                    let r = playString(e, i, 12)
                    check(r.strikes > 0 && r.blocks === r.strikes && r.ripostes === r.strikes && r.perfect === 0
                          && r.end >= r.begun - 1e-6,
                          s.name + ", a " + kind + " lead's \"" + list[i].name + "\": the knight holds its shield "
                          + "through it, stops " + r.blocks + " of " + r.strikes + " strikes, ripostes " + r.ripostes
                          + " and ends it with " + r3(r.end) + " mana (began with " + r3(r.begun) + ")")
                }
            }
        }
        game.duelPace = Balance.pace.standard
    }

    // A lead shown from another screen: the riposte's number is whole,
    // and the host's lead takes it whole
    function checkRemote(g) {
        let p = game.player
        setUp(g, "telegraph")
        g.remote = true
        let hp0 = g.hp
        let n = g.takeDamage(p.atk, p.xWu, p.yWu, false, false, true)
        let hpRemote = hp0 - g.hp
        g.remote = false
        setUp(g, "telegraph")
        hp0 = g.hp
        g.takeRemoteBlow(p.atk, p.xWu, p.yWu, "other", false, "", false, true)
        let whole = hp0 - g.hp
        hp0 = g.hp
        g.takeRemoteBlow(p.atk, p.xWu, p.yWu, "other", false, "", false, false)
        let plain = hp0 - g.hp
        check(n === base(g) && hpRemote === 0 && whole === base(g) && plain === guard(g),
              "a lead shown from another screen gives the riposte's number whole (" + n + " of " + base(g)
              + "), its HP left to the host (" + hpRemote + "); the host's lead takes it whole (" + whole
              + "), a plain blow at the guard's share (" + plain + ")")
    }

    // The knight's shield stopped a strike of e's a moment ago, its window
    // open or not: e stands halted 1.2 wu off in its guard, and the
    // knight, its shield lowered, swings 10 steps after the block. Whether
    // the window was open on e, the HP e lost and the ripostes counted
    function swingAfterBlock(e) {
        let p = game.player
        let open = p._riposteLead === e
        let from = p._riposteFrom
        let ripostes0 = game.fightRecord.ripostes
        e.halted = true
        e.aiState = "telegraph"
        e._setStance(1)
        e.xWu = p.xWu + 1.2
        e.yWu = p.yWu + e.bulk
        p.lowerShield()
        p.isBlocking = false
        face(e)
        let n = 0
        while (p._steps - from < 10 && n < 60) { face(e); Clayground.physicsStep(1); n++ }
        let hp0 = e.hp
        p.attack()
        n = 0
        while (e.hp === hp0 && n < 60) { face(e); Clayground.physicsStep(1); n++ }
        let out = {open: open, lost: hp0 - e.hp, ripostes: game.fightRecord.ripostes - ripostes0}
        e.halt()
        knightReady(e)
        return out
    }
    // A host's lead's blow on a joiner's knight lands through the game's
    // own path for it (Game._landKnightBlow), on the held shield
    function checkJoinerBlow(g) {
        let p = game.player
        setUp(g, "chase")
        g.xWu = p.xWu + 1.0
        p.mana = 30
        p.isBlocking = true
        for (let i = 0; i < 30; i++) { face(g); Clayground.physicsStep(1) }
        let id = "riposteBenchLead"
        game._enemyById[id] = g
        let blocks0 = game.fightRecord.blocks
        game._landKnightBlow({id: id, atk: g.atk, x: g.xWu, y: g.yWu, size: g.widthWu, crush: false,
                              dx: -1, dy: 0, ax: g.aimXWu, ay: g.aimYWu,
                              reach: Balance.enemy.lungeHitRange + g.bulk, pf: g.perfectFrames,
                              pw: g.parryFrames, arrived: game._physicsSteps})
        delete game._enemyById[id]
        let blocked = game.fightRecord.blocks - blocks0
        let r = swingAfterBlock(g)
        check(blocked === 1 && r.open && r.lost === base(g) && r.ripostes === 1,
              "a host's lead's blow stopped by a joiner's held shield (Game._landKnightBlow, " + blocked
              + " blocked) opens the riposte's window on that lead (" + r.open + "), and a swing in it lands "
              + "whole: " + r.lost + " HP (" + base(g) + "), " + r.ripostes + " riposte")
    }
    // A spitter lead's shot and a slinger lead's metal ball, flying at the
    // knight behind its shield, met there (Game.shotLanded, ballLanded)
    function checkShotBlocks(sp, sl) {
        let p = game.player
        for (let [e, ball, what] of [[sp, false, "a spitter lead's shot"], [sl, true, "a slinger lead's ball"]]) {
            setUp(e, "chase")
            e.xWu = p.xWu + 4
            knightReady(e)
            p.mana = 30
            p.isBlocking = true
            for (let i = 0; i < 30; i++) { face(e); Clayground.physicsStep(1) }
            let blocks0 = game.fightRecord.blocks, from0 = p._riposteFrom
            let cx = p.xWu + p.widthWu / 2, cy = p.yWu - p.heightWu / 2
            if (ball) game.spawnBall(cx + 3, cy, -1, 0, e.atk, 0, e)
            else game.spawnProjectile(cx + 3 - Balance.projectile.size / 2, cy + Balance.projectile.size / 2,
                                      -1, 0, e.atk, 0, e)
            let n = 0
            while (n < 120 && p._riposteFrom === from0 && game.fightRecord.blocks === blocks0) {
                p.isBlocking = true
                face(e)
                Clayground.physicsStep(1)
                n++
            }
            let blocked = game.fightRecord.blocks - blocks0
            // The ball the shield glanced away falls here: it would hit the
            // slinger brought close for the swing
            for (let i = 0; i < game.room.children.length; i++) {
                let o = game.room.children[i]
                if (o.objectName === "ball" && o.destroyed === false) o.fallAt(o.xWu, o.yWu, "bench")
            }
            let r = swingAfterBlock(e)
            check(blocked === 1 && r.open && r.lost === base(e) && r.ripostes === 1,
                  what + " stopped by the held shield (" + blocked + " blocked) opens the riposte's window on "
                  + "the shooter (" + r.open + "), and a swing in it, the shooter come close, lands whole: "
                  + r.lost + " HP (" + base(e) + "), " + r.ripostes + " riposte")
        }
    }

    // Weak and normal enemies keep their fight
    function checkNormal(e) {
        e.tier = 1
        let r = blockThenSwing(e, {delay: 10, mana: 30, lead: false})
        check(!e.lead && !e.riposteable && r.blocked === 1 && r.lost === base(e) && r.ripostes === 0
              && near(r.afterSwing, r.preSwing, 1e-6) && r.words.length === 0 && r.sounds.length === 0,
              "a normal grunt: a swing right after its blocked lunge lands as any swing (" + r.lost + " of "
              + base(e) + "), no riposte, mana " + r3(r.afterSwing) + " as before it (" + r3(r.preSwing)
              + "), no word, no ring")
    }

    // The Warden gives no riposte (issue #368)
    function checkWarden(w) {
        let lw = Balance.lead.warden
        let p = game.player
        w.dormant = false
        setUp(w, "chase")
        w.xWu = p.xWu + 1.0
        w.yWu = p.yWu + w.bulk
        knightReady(w)
        let ripostes0 = game.fightRecord.ripostes
        p.mana = 30
        p.isBlocking = true
        p.payBlock()
        p.riposteOpen(w)
        p.lowerShield()
        let mana = p.mana
        let hp0 = w.hp
        Clayground.physicsStep(2)
        p.attack()
        let n = 0
        while (w.hp === hp0 && n < 60) { Clayground.physicsStep(1); n++ }
        let want = Math.max(Balance.minDamage, Math.round(base(w) * lw.chip))
        check(!w.riposteable && hp0 - w.hp === want && game.fightRecord.ripostes === ripostes0
              && near(p.mana, mana, 1e-6),
              "the Warden gives no riposte: a swing right after a block takes its chip, " + (hp0 - w.hp)
              + " HP (" + want + "), no mana back (" + r3(p.mana) + ")")
        w.halt()
    }

    property var steps: [
        [() => game.screen === "title", () => {
            game.applyScenario("fight")
        }],
        [() => game.player && game.fightRoomActive
              && game.enemies.some(e => e.lead && e.enemyType === "guardian"), () => {
            Clayground.paused = true
            let p = game.player
            // A bench that times its answers on a knight standing still
            p.knockback = 0
            let spawn = (type, tier, dx, dy) => {
                game.spawnEnemy(p.xWu + dx, p.yWu + dy, tier, type)
                return game.enemies[game.enemies.length - 1]
            }
            home = Qt.point(p.xWu, p.yWu)
            let g = spawn("grunt", 2, 0, 5)
            let gu = spawn("guardian", 2, 0, -5)
            let normal = spawn("grunt", 1, -6, 0)
            let sp = spawn("spitter", 2, 6, 0)
            let sl = spawn("slinger", 2, 6, 5)
            for (let e of [g, gu, normal, sp, sl]) e.halt()
            Clayground.physicsStep(2)
            check(g.lead && gu.lead && sp.lead && sl.lead && !g.boss && !normal.lead
                  && game.duelPace === Balance.pace.standard,
                  "a grunt, a guardian, a spitter and a slinger lead and a normal grunt stand in the fight room ("
                  + game.duelPace + " pace)")
            checkWindow(g)
            checkRiposte(g)
            checkGuardian(gu)
            checkPerfect(g)
            checkStrings(g, gu)
            checkRemote(g)
            checkJoinerBlow(g)
            checkShotBlocks(sp, sl)
            checkNormal(normal)
            Clayground.paused = false
            game.applyScenario("boss", 2)
        }],
        [() => game.player && game.fightRoomActive && game.enemies.some(e => e.boss && !e.destroyed), () => {
            Clayground.paused = true
            game.player.knockback = 0
            checkWarden(game.enemies.find(e => e.boss && !e.destroyed))
            Clayground.paused = false
            console.log("[Riposte]", failures === 0 ? "all checks pass" : failures + " checks fail")
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
                    console.log("[Riposte] FAIL step", i, "timed out")
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
