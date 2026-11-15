// Kill chain bench - a kill chain makes the knight's blows stronger while
// it holds, the HUD shows it, and a kill bursts more the longer the chain
// (issue #321).
//
// Starts the fight room paused and single-steps it, every enemy halted. A
// grunt with no stance stands in front of the knight as a dummy; a swing
// landed on it measures the damage. Kills are the game's own: a victim
// struck down, then Game.killLanded for the links past the room's enemies.
// Without a chain, and with fewer than chain.pipEvery links, a swing deals
// atk less the grunt's defense; each pipEvery-th link adds
// chain.bonusShare of the swing and of a whirlwind's hit, up to
// chain.bonusCap, and still adds its momentum pip. The HUD's chain label
// shows the bonus while it holds and hides without one. A hit the knight
// takes ends it, and so does the chain's window running out with no kill;
// a step before the window it still holds. The momentum the chain added
// stays after it ends. A kill's burst has 12 shards, 10 sparks and a ring
// of 1.6 wu; each link past the first up to chain.burstLinks adds
// burstShards, burstSparks and burstRing, past it the burst stays; another
// player's chained kill, received through the session, bursts as large on
// this screen. Prints one PASS or FAIL line per check and exits with the
// number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/killchain/killchain.qml

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
        console.log("[KillChain]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[KillChain] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true})
        script.start()
    }

    readonly property real stepS: 1 / 60
    property var dummy: null

    // Every item of this name anywhere under item
    function findAll(item, name, out) {
        out = out || []
        if (!item) return out
        if (item.objectName === name) out.push(item)
        let kids = item.children || []
        for (let i = 0; i < kids.length; i++) findAll(kids[i], name, out)
        return out
    }
    function hud() { return findAll(game, "chainBonusHud")[0] }
    function hudShows() { let h = hud(); return !!h && h.visible }
    function session() {
        for (let i = 0; i < game.data.length; i++)
            if (typeof game.data[i].sendImpact === "function") return game.data[i]
        return null
    }

    // The dummy 1.2 wu right of the knight, which faces it; full HP
    function standDummy() {
        let p = game.player
        dummy.xWu = p.xWu + 1.2
        dummy.yWu = p.yWu
        dummy._knockT = 0
        dummy.hp = 100000
        p.facingAngle = Math.atan2(dummy.yWu - dummy.heightWu / 2 - p.yWu + p.heightWu / 2,
                                   dummy.xWu + dummy.widthWu / 2 - p.xWu - p.widthWu / 2) * 180 / Math.PI
    }
    // A normal swing at the dummy, stepped until it is over: the damage it
    // dealt, -1 when it swung not. Holds the chain's clock: the steps are
    // taken off the chain's last kill
    function swing() {
        let p = game.player
        standDummy()
        p.attackCooldown = 0
        p.isBlocking = false
        let before = dummy.hp
        let at = game._chainAt
        let t0 = game.physicsSeconds
        p.attack()
        if (!p.isAttacking) return -1
        let n = 0
        while (p.isAttacking && n < 120) {
            Clayground.physicsStep(1)
            n++
        }
        game._chainAt = at + (game.physicsSeconds - t0)
        return before - dummy.hp
    }
    // A whirlwind's hit on the dummy, the normal version: its damage
    function whirlHit() {
        let p = game.player
        standDummy()
        p.whirlStrong = false
        p._hitThisWhirl = new Set()
        let before = dummy.hp
        p.whirlEnemies()
        return before - dummy.hp
    }
    // n kills of this knight's, at the dummy's left, as an enemy's death
    // reports them
    function kills(n) {
        let p = game.player
        for (let i = 0; i < n; i++) game.killLanded(p.xWu - 1, p.yWu, -1, 0, "#C04040")
    }
    // The damage of a blow of dmg with a bonus, less the dummy's defense
    function withBonus(dmg, bonus) {
        return Math.floor(dmg * (1 + bonus) + 1e-6) - dummy.def
    }
    function near(a, b) { return Math.abs(a - b) < 1e-9 }

    property var steps: [
        [() => game.screen === "title", () => {
            game.applyScenario("fight")
        }],
        [() => game.player && game.fightRoomActive && game.enemies.filter(e => !e.destroyed).length >= 3, () => {
            Clayground.paused = true
            let c = Balance.chain
            let p = game.player
            let foes = game.enemies.filter(e => !e.destroyed)
            for (let e of foes) {
                e.lead = false
                e.halt()
            }
            dummy = foes.find(e => e.enemyType === "grunt") || foes[0]
            let victims = foes.filter(e => e !== dummy && e.enemyType !== "guardian")
            p.special = "whirlwind"
            p.momentum = 0
            p.graceLeft = 0
            game.breakChain()

            // No chain: a swing deals atk less the defense
            let base = p.atk - dummy.def
            let d0 = swing()
            check(d0 === base && game.chainBonus === 0 && !hudShows(),
                  "without a chain a swing deals " + d0 + " (atk " + p.atk + " less defense " + dummy.def
                  + ", bonus " + game.chainBonus + ") and the chain label hides")
            let w0 = whirlHit()
            let wBase = Math.floor(p.atk * Balance.knight.whirlSwing) - dummy.def
            check(w0 === wBase, "without a chain a whirlwind's hit deals " + w0 + " (" + wBase + ")")

            // A real kill starts it; below pipEvery links there is no pip
            // and no bonus
            p.momentum = 0
            let v = victims[0]
            v.takeDamage(100000, p.xWu, p.yWu)
            kills(c.pipEvery - 2)
            let d1 = swing()
            check(game.chainLinks === c.pipEvery - 1 && game.chainBonus === 0 && d1 === base && !hudShows(),
                  "a chain of " + game.chainLinks + " links, one short of a pip, adds nothing: the swing deals "
                  + d1 + ", the label hides")

            // The pipEvery-th link: one pip, bonusShare more, its momentum pip
            p.momentum = 0
            kills(1)
            let pipMomentum = p.momentum
            let d2 = swing()
            let want1 = withBonus(p.atk, c.bonusShare)
            check(game.chainPips === 1 && near(game.chainBonus, c.bonusShare) && d2 === want1,
                  "the chain's first pip (" + game.chainLinks + " links) makes the swing deal " + d2
                  + " (" + want1 + ", +" + Math.round(c.bonusShare * 100) + "%)")
            check(pipMomentum === 1, "the pip still adds its momentum pip (momentum 0 -> " + pipMomentum + ")")
            let h = hud()
            let label = "CHAIN +" + Math.round(c.bonusShare * 100) + "%"
            check(hudShows() && h.text === label,
                  "the HUD shows the bonus while it holds (" + (h ? h.text : "no label") + ", want " + label + ")")
            let w1 = whirlHit()
            let wWant = withBonus(Math.floor(p.atk * Balance.knight.whirlSwing), c.bonusShare)
            check(w1 === wWant, "a whirlwind's hit deals " + w1 + " with the pip (" + wWant + ")")

            // Each pip adds bonusShare, up to bonusCap
            let capPips = Math.ceil(c.bonusCap / c.bonusShare - 1e-9)
            let seen = []
            for (let pip = 2; pip <= capPips + 2; pip++) {
                kills(c.pipEvery)
                let d = swing()
                let bonus = Math.min(c.bonusCap, pip * c.bonusShare)
                let want = withBonus(p.atk, bonus)
                seen.push(game.chainLinks + " links: " + d)
                check(game.chainPips === pip && near(game.chainBonus, Math.round(bonus * 1000) / 1000) && d === want
                      && h.text === "CHAIN +" + Math.round(bonus * 100) + "%",
                      "pip " + pip + (pip > capPips ? ", past the cap," : "") + " makes the swing deal " + d
                      + " (" + want + ", +" + Math.round(bonus * 100) + "%), the HUD " + h.text)
            }
            check(withBonus(p.atk, c.bonusCap) > base,
                  "the cap's swing deals more than one without a chain (" + seen.join(", ") + ")")

            // A hit the knight takes breaks it: no bonus, the label hides,
            // the momentum stays
            let mo = p.momentum
            p.graceLeft = 0
            p.isBlocking = false
            p.takeDamage(10, p.xWu - 1, p.yWu)
            p.hp = p.maxHp
            let d3 = swing()
            check(game.chainLinks === 0 && game.chainBonus === 0 && d3 === base && !hudShows(),
                  "a hit taken breaks the chain: the swing deals " + d3 + ", the label hides")
            check(p.momentum === mo, "the momentum the chain added stays (" + p.momentum + ")")

            // Its window running out ends it too; a step before, it holds
            p.graceLeft = 0
            kills(c.pipEvery)
            let windowSteps = Math.floor(c.window / stepS + 1e-6)
            Clayground.physicsStep(windowSteps - 1)
            check(game.chainLinks === c.pipEvery && game.chainBonus > 0 && hudShows(),
                  "a step before the window runs out the chain holds (" + game.chainLinks + " links, +"
                  + Math.round(game.chainBonus * 100) + "%)")
            Clayground.physicsStep(3)
            let d4 = swing()
            check(game.chainLinks === 0 && game.chainBonus === 0 && d4 === base && !hudShows(),
                  "once the window ran out with no kill the chain is over: the swing deals " + d4
                  + ", the label hides")
        }],
        [() => true, () => {
            // The burst grows with the chain, up to burstLinks
            let c = Balance.chain
            let p = game.player
            game.breakChain()
            let sizes = []
            let ok = true
            for (let link = 1; link <= c.burstLinks + 2; link++) {
                kills(1)
                let b = game.lastDeathBurst
                let past = Math.min(link, c.burstLinks) - 1
                let want = {shards: 12 + past * c.burstShards, sparks: 10 + past * c.burstSparks,
                            ring: 1.6 + past * c.burstRing}
                sizes.push(link + ": " + (b ? b.shards + "/" + b.sparks + "/" + b.ring.toFixed(1) : "none"))
                if (!b || b.shards !== want.shards || b.sparks !== want.sparks || !near(b.ring, want.ring))
                    ok = false
            }
            check(ok, "a kill bursts more the longer the chain, the same past " + c.burstLinks
                  + " links (link: shards/sparks/ring " + sizes.join(", ") + ")")

            // A real kill in a chain: its burst is the chain's
            game.breakChain()
            let foes = game.enemies.filter(e => !e.destroyed && e !== dummy)
            kills(3)
            if (foes.length > 0) foes[0].takeDamage(100000, p.xWu, p.yWu)
            let b = game.lastDeathBurst
            check(foes.length > 0 && game.chainLinks === 4 && b && b.shards === 12 + 3 * c.burstShards,
                  "an enemy struck down as a chain's 4th link bursts with " + (b ? b.shards : "no")
                  + " shards (" + (12 + 3 * c.burstShards) + ")")

            // Another player's chained kill, through the session
            let s = session()
            game.lastDeathBurst = null
            if (s) s.impactReceived("chainKill", p.xWu + 2, p.yWu, 1, 0, "#C04040", 5)
            b = game.lastDeathBurst
            check(s && b && b.shards === 12 + 4 * c.burstShards && b.sparks === 10 + 4 * c.burstSparks,
                  "another player's 5th chained kill bursts as large here (" + (b ? b.shards + " shards, "
                  + b.sparks + " sparks" : "no burst") + ")")
            console.log("[KillChain] done,", failures, "failed")
        }],
        // Torn down before quitting, as the impact bench does
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
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
                    console.log("[KillChain] FAIL step", i, "timed out")
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
