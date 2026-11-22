// Shares bench - every good answer to a room's lead does damage (issue
// #364).
//
// Starts the fight room paused (Clayground.paused) and single-steps it
// (Clayground.physicsStep), at the game's duel pace. A grunt lead, its AI
// halted in the state the check sets, and the knight 1.2 wu off, facing
// it:
// - a swing into its guard - while it chases, and while it winds up -
//   takes Balance.lead.guard of the swing's damage and wears lead.wear
//   off its stance; a swing in a rest of its string (its recovery) or in
//   its retreat takes all of it; a swing in an opening takes
//   lead.openingDamage times it, more than in any other moment; the
//   number shown over the lead is the HP it lost, each time;
// - a charged swing into its guard takes the guard's share of the charged
//   swing and wears lead.heavyWear; one in its retreat or a rest lands
//   whole and opens nothing; one in an opening more again;
// - 1 / lead.wear swings into its guard, rounded up, open it ("worn"), the
//   one before does not; 1 / lead.blockWear strikes stopped by a held
//   shield do the same;
// - a strike of its stopped by the knight's held shield, its lunge played
//   out, wears lead.blockWear off its stance; one that hits the knight
//   steadies it by lead.steady; a perfect block opens it ("perfect");
// - the bolt takes the same shares - guard, whole in its retreat, more in
//   an opening - and wears the stance without breaking it; a shot sent
//   back opens it, landing whole, and in an opening takes the opening's
//   share;
// - a spitter lead's shot and a slinger lead's metal ball, fired at the
//   knight behind its shield, wear the shooter's stance by
//   lead.blockWear; let through to the knight, they steady it;
// - a lead shown on another screen (remote) gives the same number for the
//   same blow, guard and whole, and its HP stays the host's.
// Weak and normal enemies keep their fight: a swing on a normal grunt
// takes all of its damage, and its blocked and landed strikes do nothing
// to it. Last the Hollow Warden keeps today's stance (issue #368): a swing
// takes lead.warden.chip of it and wears lead.warden.wear, a charged swing
// in its recovery opens it ("heavy"), a blocked strike wears nothing, and
// in an opening a swing takes lead.warden.openingDamage times it. Prints
// one PASS or FAIL line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/shares/shares.qml

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
        console.log("[Shares]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Shares] FAIL", c.errorString())
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
    // enemy stands
    function setUp(e, state, lead) {
        let p = game.player
        p.xWu = home.x
        p.yWu = home.y
        // Every other enemy halted and out of the sword's reach
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
        e.yWu = p.yWu
        e.aiState = state
        e.halted = true
        knightReady(e)
        return e
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
        p.facingAngle = Math.atan2(e.yWu - e.heightWu / 2 - p.yWu + p.heightWu / 2,
                                   e.xWu + e.widthWu / 2 - p.xWu - p.widthWu / 2) * 180 / Math.PI
        let n = 0
        while ((p.isAttacking || p.attackCooldown > 0) && n < 600) {
            Clayground.physicsStep(1)
            n++
        }
    }
    // The numbers over things now, by the item
    function numbers() {
        let out = []
        let parents = [game.glowParent(), game.room]
        for (let par of parents)
            for (let i = 0; i < par.children.length; i++) {
                let c = par.children[i]
                if (c.objectName === "damageNumber" && out.indexOf(c) < 0) out.push(c)
            }
        return out
    }
    // A swing of the knight's at e, charged when heavy: the HP e lost, the
    // number shown for it, e's stance after it and whether it opened e
    function swing(e, heavy) {
        let p = game.player
        knightReady(e)
        let before = numbers()
        let hp0 = e.hp, causes = []
        let onOpened = c => causes.push(c)
        e.opened.connect(onOpened)
        let n = 0
        if (heavy) {
            p.pressSwing()
            while (!p.chargeFull && n < 600) { Clayground.physicsStep(1); n++ }
            p.releaseSwing()
        } else {
            p.attack()
        }
        n = 0
        while (e.hp === hp0 && n < 120) { Clayground.physicsStep(1); n++ }
        e.opened.disconnect(onOpened)
        let shown = numbers().filter(x => before.indexOf(x) < 0).map(x => x.text)
        return {lost: hp0 - e.hp, shown: shown, stance: e._stanceLeft, opening: e.opening, causes: causes}
    }
    // The knight's swing's damage on e, a charged one's when heavy, before
    // any share
    function base(e, heavy) {
        let p = game.player
        let amount = heavy ? Math.floor(p.atk * Balance.knight.heavySwing) : p.atk
        return Math.max(Balance.minDamage, amount - e.def)
    }
    function share(e, heavy, c) { return Math.max(Balance.minDamage, Math.round(base(e, heavy) * c)) }
    function shownIs(r) { return r.shown.length === 1 && Number(r.shown[0]) === r.lost }

    function checkSwings(g) {
        let l = Balance.lead
        // Into its guard: chasing, then winding up
        for (let state of ["chase", "telegraph"]) {
            setUp(g, state)
            let r = swing(g, false)
            let want = share(g, false, l.guard)
            check(r.lost === want && shownIs(r) && near(r.stance, 1 - l.wear) && !r.opening,
                  "a swing into the lead's guard (" + state + ") takes " + r.lost + " HP (lead.guard " + l.guard
                  + " of " + base(g, false) + " is " + want + "), the number shows " + r.shown.join() + ", and its "
                  + "stance wears to " + r3(r.stance) + " (lead.wear " + l.wear + ")")
        }
        let guard = share(g, false, l.guard)
        // In a rest and in its retreat: whole
        let whole = {}
        for (let state of ["recovery", "retreat"]) {
            setUp(g, state)
            let r = swing(g, false)
            whole[state] = r.lost
            check(r.lost === base(g, false) && shownIs(r) && !r.opening && near(r.stance, 1 - l.wear),
                  "a swing in the lead's " + (state === "recovery" ? "rest" : "retreat") + " lands whole: "
                  + r.lost + " HP (" + base(g, false) + "), the number shows " + r.shown.join()
                  + ", its stance worn to " + r3(r.stance))
        }
        // In an opening: the most of all
        setUp(g, "chase")
        g.halted = false
        g.open("parry")
        g.halted = true
        let o = swing(g, false)
        let opened = Math.floor(base(g, false) * l.openingDamage)
        check(o.lost === opened && shownIs(o) && o.lost > whole.recovery && o.lost > whole.retreat && o.lost > guard,
              "a swing in an opening takes " + o.lost + " HP (lead.openingDamage " + l.openingDamage + " times "
              + base(g, false) + " is " + opened + "), the number shows " + o.shown.join() + ": more than in a rest ("
              + whole.recovery + "), the retreat (" + whole.retreat + ") or into the guard (" + guard + ")")

        // Charged swings
        setUp(g, "chase")
        let hg = swing(g, true)
        let hwant = share(g, true, l.guard)
        check(hg.lost === hwant && shownIs(hg) && near(hg.stance, 1 - l.heavyWear) && !hg.opening,
              "a charged swing into the guard takes " + hg.lost + " HP (" + l.guard + " of " + base(g, true) + " is "
              + hwant + "), the number shows " + hg.shown.join() + ", its stance worn to " + r3(hg.stance)
              + " (lead.heavyWear " + l.heavyWear + ")")
        let heavyWhole = {}
        for (let state of ["recovery", "retreat"]) {
            setUp(g, state)
            let r = swing(g, true)
            heavyWhole[state] = r.lost
            check(r.lost === base(g, true) && shownIs(r) && !r.opening && r.causes.length === 0,
                  "a charged swing in the lead's " + (state === "recovery" ? "rest" : "retreat") + " lands whole, "
                  + r.lost + " HP (" + base(g, true) + "), the number shows " + r.shown.join() + ", and opens nothing ("
                  + (r.causes.join() || "nothing") + ")")
        }
        setUp(g, "chase")
        g.halted = false
        g.open("parry")
        g.halted = true
        let ho = swing(g, true)
        check(ho.lost === Math.floor(base(g, true) * l.openingDamage) && shownIs(ho)
              && ho.lost > heavyWhole.retreat && ho.lost > hwant,
              "a charged swing in an opening takes " + ho.lost + " HP, more than in the retreat ("
              + heavyWhole.retreat + ") or into the guard (" + hwant + "); the number shows " + ho.shown.join())
    }

    // Blows into the guard straight on the lead, as a swing strikes it, n
    // of them or until it opens: how many it took and what opened it
    function wearOut(g, each) {
        setUp(g, "chase")
        let causes = []
        let onOpened = c => causes.push(c)
        g.opened.connect(onOpened)
        let n = 0
        while (!g.opening && n < 50) {
            each(g)
            n++
        }
        g.opened.disconnect(onOpened)
        return {n: n, causes: causes}
    }
    function checkWear(g) {
        let l = Balance.lead
        let p = game.player
        let blows = wearOut(g, e => e.takeDamage(p.atk, p.xWu, p.yWu, false, false))
        let want = Math.ceil(1 / l.wear - 1e-9)
        check(blows.n === want && blows.causes.join() === "worn",
              "the lead's guard breaks into an opening on swing " + blows.n + " (1 / lead.wear " + l.wear
              + " rounded up is " + want + "), opened by " + (blows.causes.join() || "nothing"))
        let blocks = wearOut(g, e => e.strikeMet("blocked"))
        let wantB = Math.ceil(1 / l.blockWear - 1e-9)
        check(blocks.n === wantB && blocks.causes.join() === "worn",
              "so it does on blocked strike " + blocks.n + " (1 / lead.blockWear " + l.blockWear + " rounded up is "
              + wantB + "), opened by " + (blocks.causes.join() || "nothing"))
        // Blows and blocked strikes in turn: they add up
        let i = 0
        let mixed = wearOut(g, e => {
            if (i++ % 2 === 0) e.takeDamage(p.atk, p.xWu, p.yWu, false, false)
            else e.strikeMet("blocked")
        })
        let left = 1, wantM = 0
        while (left > 1e-6) left -= wantM++ % 2 === 0 ? l.wear : l.blockWear
        check(mixed.n === wantM && mixed.causes.join() === "worn",
              "swings and blocked strikes in turn break it together after " + mixed.n + " of them (" + wantM + ")")
    }

    // Its own lunge at the knight, the knight's shield held up (block) or
    // down: the result as the knight took it, and the lead's stance before
    // and after
    function lungeAt(g, block, stance) {
        let p = game.player
        setUp(g, "chase")
        g._setStance(stance)
        let x = p.xWu, y = p.yWu, gx = g.xWu, gy = g.yWu
        // The knight stands where it stood, facing the lead, its shield up
        // or down
        let hold = () => {
            p.xWu = x
            p.yWu = y
            p.facingAngle = Math.atan2(g.yWu - g.heightWu / 2 - p.yWu + p.heightWu / 2,
                                       g.xWu + g.widthWu / 2 - p.xWu - p.widthWu / 2) * 180 / Math.PI
            p.isBlocking = block
        }
        // The shield up well before the blow: a held block, no perfect one
        for (let i = 0; i < 60; i++) {
            hold()
            g.xWu = gx
            g.yWu = gy
            Clayground.physicsStep(1)
        }
        g.halted = false
        let blocks0 = game.fightRecord.blocks
        let hp0 = p.hp
        g.windUp(0.2)
        let before = g._stanceLeft
        let n = 0
        while (g.aiState !== "lunge" && n < 300) {
            hold()
            Clayground.physicsStep(1)
            n++
        }
        // Just before it lands the stance is what it was
        before = g._stanceLeft
        while (g.aiState === "lunge" && n < 600) {
            hold()
            Clayground.physicsStep(1)
            n++
        }
        let out = {blocked: game.fightRecord.blocks - blocks0, hurt: hp0 - p.hp, before: before, after: g._stanceLeft,
                   opening: g.opening, state: g.aiState}
        g.halt()
        knightReady(g)
        return out
    }
    function checkStrikes(g) {
        let l = Balance.lead
        let b = lungeAt(g, true, 1)
        check(b.blocked === 1 && near(b.before - b.after, l.blockWear) && !b.opening,
              "the lead's lunge stopped by a held shield wears its stance from " + r3(b.before) + " to "
              + r3(b.after) + " (lead.blockWear " + l.blockWear + "; " + b.blocked + " blocked)")
        let h = lungeAt(g, false, 0.3)
        check(h.blocked === 0 && h.hurt > 0 && near(h.after, Math.min(1, 0.3 + l.steady)) && !h.opening,
              "its lunge that hits the knight (" + h.hurt + " HP) steadies its stance from " + r3(h.before)
              + " to " + r3(h.after) + " (lead.steady " + l.steady + ")")
        setUp(g, "chase")
        g.halted = false
        let causes = []
        let onOpened = c => causes.push(c)
        g.opened.connect(onOpened)
        g.perfectBlocked()
        g.opened.disconnect(onOpened)
        check(causes.join() === "perfect" && g.opening, "a perfect block opens it (" + (causes.join() || "nothing") + ")")
        g.halt()
    }

    // The bolt and a shot sent back
    function checkBoltAndShot(g) {
        let l = Balance.lead
        let p = game.player
        let amount = Math.round(p.atk * Balance.bolt.damage)
        let bd = Math.max(Balance.minDamage, amount - g.def)
        let bolt = state => {
            setUp(g, state)
            if (state === "open") {
                g.halted = false
                g.open("parry")
                g.halted = true
            }
            let hp0 = g.hp
            let shown = g.takeBolt(amount, p.xWu, p.yWu)
            return {lost: hp0 - g.hp, shown: shown, stance: g._stanceLeft, opening: g.opening}
        }
        let bg = bolt("chase"), br = bolt("retreat"), bo = bolt("open")
        check(bg.lost === Math.max(Balance.minDamage, Math.round(bd * l.guard)) && bg.shown === bg.lost
              && br.lost === bd && br.shown === bd && bo.lost === Math.floor(bd * l.openingDamage)
              && bo.lost > br.lost && br.lost > bg.lost && near(bg.stance, 1 - l.wear) && !bg.opening && !br.opening,
              "the bolt takes the same shares: " + bg.lost + " into the guard, " + br.lost + " in the retreat, "
              + bo.lost + " in an opening (of " + bd + "), the number as dealt, and wears the stance to "
              + r3(bg.stance))
        setUp(g, "chase")
        g._setStance(l.wear * 0.5)
        g.takeBolt(amount, p.xWu, p.yWu)
        check(!g.opening && g._stanceLeft > 0, "a bolt never breaks the stance (left " + r3(g._stanceLeft) + ")")
        // A shot sent back
        setUp(g, "chase")
        let hp0 = g.hp, causes = []
        let onOpened = c => causes.push(c)
        g.opened.connect(onOpened)
        let shown = g.takeShot(20, p.xWu, p.yWu, "shot")
        let whole = Math.max(Balance.minDamage, 20 - g.def)
        let first = hp0 - g.hp
        hp0 = g.hp
        let again = g.takeShot(20, p.xWu, p.yWu, "shot")
        g.opened.disconnect(onOpened)
        check(first === whole && shown === whole && causes.join() === "shot"
              && hp0 - g.hp === Math.floor(whole * l.openingDamage) && again === hp0 - g.hp,
              "a shot sent back opens the lead (" + (causes.join() || "nothing") + "), landing whole (" + first
              + " of " + whole + "), and one in the opening takes " + (hp0 - g.hp) + " (" + l.openingDamage
              + " times)")
    }

    // A spitter's shot and a slinger's ball at the knight, its shield up or
    // down: the shooter's stance before and after
    function shotAt(e, ball, block) {
        let p = game.player
        setUp(e, "chase")
        e.xWu = p.xWu + 4
        e.yWu = p.yWu
        e._setStance(block ? 1 : 0.3)
        knightReady(e)
        p.isBlocking = block
        let before = e._stanceLeft
        let hp0 = p.hp
        let cx = p.xWu + p.widthWu / 2, cy = p.yWu - p.heightWu / 2
        if (ball) game.spawnBall(cx + 3, cy, -1, 0, e.atk, 0, e)
        else game.spawnProjectile(cx + 3 - Balance.projectile.size / 2, cy + Balance.projectile.size / 2, -1, 0,
                                  e.atk, 0, e)
        let n = 0
        while (n < 120 && Math.abs(e._stanceLeft - before) < 1e-9) {
            p.isBlocking = block
            Clayground.physicsStep(1)
            n++
        }
        return {before: before, after: e._stanceLeft, hurt: hp0 - p.hp}
    }
    function checkShots(sp, sl) {
        let l = Balance.lead
        for (let [e, ball, what] of [[sp, false, "the spitter lead's shot"], [sl, true, "the slinger lead's ball"]]) {
            let b = shotAt(e, ball, true)
            check(near(b.before - b.after, l.blockWear) && b.hurt === 0,
                  what + " stopped by the knight's held shield wears its stance from " + r3(b.before) + " to "
                  + r3(b.after) + " (lead.blockWear " + l.blockWear + ")")
            let h = shotAt(e, ball, false)
            check(h.hurt > 0 && near(h.after, Math.min(1, h.before + l.steady)),
                  what + " that hits the knight (" + h.hurt + " HP) steadies its stance from " + r3(h.before)
                  + " to " + r3(h.after))
            e.halt()
            e.xWu = game.player.xWu + 8
        }
    }

    // A lead shown from another screen: the number for a blow is the one
    // the host's lead takes
    function checkRemote(g) {
        let l = Balance.lead
        let p = game.player
        let out = {}
        for (let state of ["chase", "retreat"]) {
            setUp(g, state)
            g.remote = true
            let hp0 = g.hp
            out[state] = g.takeDamage(p.atk, p.xWu, p.yWu, false, false)
            out[state + "Hp"] = hp0 - g.hp
            g.remote = false
        }
        check(out.chase === share(g, false, l.guard) && out.retreat === base(g, false) && out.chaseHp === 0
              && out.retreatHp === 0,
              "a lead shown from another screen gives the same number: " + out.chase + " into its guard, "
              + out.retreat + " in its retreat, its HP left to the host (" + out.chaseHp + ", " + out.retreatHp + ")")
    }

    // A normal grunt keeps its fight
    function checkNormal(e) {
        setUp(e, "chase", false)
        e.tier = 1
        let r = swing(e, false)
        let st = e._stanceLeft
        e.strikeMet("blocked")
        let afterBlock = e._stanceLeft
        e.strikeMet("hit")
        check(!e.lead && r.lost === base(e, false) && shownIs(r) && afterBlock === st && e._stanceLeft === st,
              "a normal grunt takes a swing whole (" + r.lost + " of " + base(e, false) + ", shown "
              + r.shown.join() + "), and its blocked and landed strikes leave it as it was (" + r3(st) + ", "
              + r3(afterBlock) + ", " + r3(e._stanceLeft) + ")")
        e.halt()
    }

    // The Warden keeps today's stance (issue #368)
    function checkWarden(w) {
        let l = Balance.lead, lw = l.warden
        let p = game.player
        w.dormant = false
        w.halted = false
        let place = state => {
            setUp(w, state)
            w.xWu = p.xWu + 1.0
            w.yWu = p.yWu + w.bulk
            knightReady(w)
        }
        place("chase")
        let r = swing(w, false)
        let want = share(w, false, lw.chip)
        check(r.lost === want && shownIs(r) && near(r.stance, 1 - lw.wear),
              "the Warden takes a swing's chip: " + r.lost + " HP (lead.warden.chip " + lw.chip + " of " + base(w, false)
              + " is " + want + "), the number shows " + r.shown.join() + ", its stance worn to " + r3(r.stance)
              + " (lead.warden.wear " + lw.wear + ")")
        place("chase")
        w._setStance(0.5)
        w.strikeMet("blocked")
        let blocked = w._stanceLeft
        w.strikeMet("hit")
        check(near(blocked, 0.5) && near(w._stanceLeft, 0.5),
              "its blocked and landed strikes leave its stance as it was (" + r3(blocked) + ", " + r3(w._stanceLeft) + ")")
        place("recovery")
        let h = swing(w, true)
        check(h.causes.join() === "heavy" && h.opening && h.lost === base(w, true),
              "a charged swing in its recovery opens it (" + (h.causes.join() || "nothing") + "), landing whole ("
              + h.lost + " of " + base(w, true) + ")")
        let o = swing(w, false)
        check(o.lost === Math.floor(base(w, false) * lw.openingDamage) && shownIs(o),
              "in its opening a swing takes " + o.lost + " HP (lead.warden.openingDamage " + lw.openingDamage
              + " times " + base(w, false) + ")")
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
            let spawn = (type, tier, dx, dy) => {
                game.spawnEnemy(p.xWu + dx, p.yWu + dy, tier, type)
                return game.enemies[game.enemies.length - 1]
            }
            home = Qt.point(p.xWu, p.yWu)
            let g = spawn("grunt", 2, 0, 5)
            let sp = spawn("spitter", 2, 0, -5)
            let sl = spawn("slinger", 2, 6, 0)
            let normal = spawn("grunt", 1, -6, 0)
            for (let e of [g, sp, sl, normal]) e.halt()
            Clayground.physicsStep(2)
            check(g.lead && sp.lead && sl.lead && !g.boss && !normal.lead,
                  "a grunt, a spitter and a slinger lead and a normal grunt stand in the fight room ("
                  + game.duelPace + " pace)")
            checkSwings(g)
            checkWear(g)
            checkStrikes(g)
            checkBoltAndShot(g)
            checkRemote(g)
            checkShots(sp, sl)
            checkNormal(normal)
            Clayground.paused = false
            game.applyScenario("boss", 2)
        }],
        [() => game.player && game.fightRoomActive && game.enemies.some(e => e.boss && !e.destroyed), () => {
            Clayground.paused = true
            checkWarden(game.enemies.find(e => e.boss && !e.destroyed))
            Clayground.paused = false
            console.log("[Shares]", failures === 0 ? "all checks pass" : failures + " checks fail")
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
                    console.log("[Shares] FAIL step", i, "timed out")
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
