// Retreat bench - a room's lead ends each string with a retreat the
// knight can use (issue #363).
//
// Starts the fight room paused (Clayground.paused) and single-steps it
// (Clayground.physicsStep). At each step of the duel pace (Balance.pace)
// - Swift, Standard and Deliberate, set as the game's duelPace - a grunt,
// a guardian, a spitter and a slinger lead each play their first string
// at the knight, which stands 1.5 wu off with its shield up, and then:
// - the lead retreats (aiState "retreat") on the step its string ends,
//   for one beat of its pace (lead.beat times the factor), to the step:
//   it steps back lead.retreat.back wu the way its last blow came, over
//   lead.retreat.step of the beat and stands for the rest of it, winds
//   nothing up, opens no parry window, strikes nobody and fires nothing,
//   and goes for the knight again once the beat is over;
// - a knight that lowers its shield and starts a charge on the step the
//   retreat starts, and holds it, is not struck: the retreat stands its
//   whole beat, the charge is still held and full at its end, the knight
//   whole; outside the retreat the rule holds, and the lead's next
//   string begins with a blow at the charging knight, wound up for
//   enemy.minTelegraph times the factor;
// - a knight that starts a charge on the step the retreat starts and lets
//   go as soon as it is full lands its charged swing inside the retreat,
//   and the lead opens ("heavy").
// A guardian lead in its retreat has its guard down: a blow from the
// front is not blocked by its shield, and no counter follows it, where a
// guardian lead facing the knight outside it blocks the same blow.
// The retreat looks and sounds its own, from the aiState alone, so the
// same on every screen of a session: for each lead type set into every
// state a lead can be in, as a remote screen's lead is set by the host's
// state, only the retreat has its body colour (lead.retreat.color), hides
// the ring round a lead, shuts its eyes, and a guardian's shield hangs low;
// a lead shown from another screen (remote) looks the same; and only the
// retreat logs its sound: the lead's growl at lead.retreat.pitch, a pair
// of sample and pitch no other state of a lead plays.
// Last the Hollow Warden in its boss fight keeps today's fight (issue
// #368): after a string it recovers lead.recovery, no retreat, and a
// knight that starts a charge in reach during one of its rests is struck
// first. Prints one PASS or FAIL line per check and exits with the
// number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/retreat/retreat.qml

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
        console.log("[Retreat]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Retreat] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true})
        script.start()
    }

    function near(a, b, tol) { return Math.abs(a - b) <= (tol === undefined ? 1e-6 : tol) }
    function r3(x) { return Math.round(x * 1000) / 1000 }
    // The physics steps a timer of seconds runs, counted down a step at a
    // time until nothing is left
    function toSteps(seconds) { return Math.ceil(seconds / stepS - 1e-6) }

    // e is the room's lead and the only enemy that thinks, dx wu to the
    // knight's right, with HP that lasts; every other enemy stands
    function leadOf(e, dx) {
        let p = game.player
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
        e._setStance(1)
        e.xWu = p.xWu + dx
        e.yWu = p.yWu
        return e
    }
    // The knight stands where it stood, whole, facing e, its shield up or
    // down
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
    // Every shot and metal ball in flight gone: none reaches the knight or
    // a lead after its string
    function vanishShots() {
        for (let id in game._shotById) {
            let s = game._shotById[id]
            if (s && !s.destroyed) s.vanish()
        }
        for (let id in game._ballById) {
            let b = game._ballById[id]
            if (b && !b.destroyed) b.vanish()
        }
    }
    function shotsInFlight() {
        let n = 0
        for (let id in game._shotById) if (game._shotById[id] && !game._shotById[id].destroyed) n++
        for (let id in game._ballById) if (game._ballById[id] && !game._ballById[id].destroyed) n++
        return n
    }
    // Plays e's first string at the knight behind its shield until the
    // string is over; whether it ended in a retreat
    function playString(e) {
        let p = game.player
        let x = p.xWu, y = p.yWu
        hold(p, e, x, y, true)
        Clayground.physicsStep(2)
        e.beginString(0, false)
        let n = 0
        while (e.stringName !== "" && n < 1200) {
            hold(p, e, x, y, true)
            vanishShots()
            Clayground.physicsStep(1)
            n++
        }
        vanishShots()
        return e.stringName === "" && e.aiState === "retreat"
    }
    function centre(o) { return Qt.point(o.xWu + o.widthWu / 2, o.yWu - o.heightWu / 2) }
    // The knight whole again and e halted, for the next check
    function settle(e) {
        let p = game.player
        if (p.isCharging || p._charge === "spent") p.dropSwing()
        p.lowerShield()
        e.halt()
        vanishShots()
        p.hp = p.maxHp
        Clayground.physicsStep(Math.ceil((Balance.lead.openingTime + Balance.knight.heavyRecovery
                                          + Balance.knight.hurtGrace) / stepS) + 10)
        p.hp = p.maxHp
        p.attackCooldown = 0
    }

    // The retreat after e's string, the knight behind its shield: its
    // length in steps, where it stepped and what it did meanwhile
    function watchRetreat(e) {
        let p = game.player
        let x = p.xWu, y = p.yWu
        let retreated = playString(e)
        let start = centre(e), k = centre(p)
        // Back the way its last blow came
        let away = Qt.point(-e._dirToTargetX, -e._dirToTargetY)
        let al = Math.hypot(away.x, away.y)
        let d0 = Math.hypot(start.x - k.x, start.y - k.y)
        let blows = 0
        let onStruck = () => blows++
        e.struck.connect(onStruck)
        let w0 = e.windUps, n = 0, windows = 0, rings = 0, shots = 0, hurt = 0, moving = 0, lastMove = -1
        let prev = start
        while (e.aiState === "retreat" && n < 600) {
            hold(p, e, x, y, true)
            Clayground.physicsStep(1)
            n++
            if (e.parryWindow) windows++
            if (e.ringShows) rings++
            shots += shotsInFlight()
            hurt += p.maxHp - p.hp
            let c = centre(e)
            if (Math.hypot(c.x - prev.x, c.y - prev.y) > 1e-4 && e.aiState === "retreat") {
                moving++
                lastMove = n
            }
            prev = c
        }
        e.struck.disconnect(onStruck)
        let end = centre(e)
        let moved = Qt.point(end.x - start.x, end.y - start.y)
        let ml = Math.hypot(moved.x, moved.y)
        let out = {retreated: retreated, steps: n, after: e.aiState, back: ml,
                   gained: Math.hypot(end.x - k.x, end.y - k.y) - d0,
                   along: al > 0 && ml > 0 ? (moved.x * away.x + moved.y * away.y) / (al * ml) : 0,
                   lastMove: lastMove, windUps: e.windUps - w0, blows: blows, windows: windows,
                   rings: rings, shots: shots, hurt: hurt, beatLen: e.beatLen}
        settle(e)
        return out
    }

    // The knight lowers its shield and starts a charge on the step e's
    // retreat starts; release: it lets go as soon as the charge is full,
    // else it holds it. What became of the charge and the lead
    function chargeIntoRetreat(e, release) {
        let p = game.player
        let x = p.xWu, y = p.yWu
        let retreated = playString(e)
        hold(p, e, x, y, false)
        p.lowerShield()
        p.attackCooldown = 0
        p.pressSwing()
        let causes = []
        let onOpened = c => causes.push(c)
        e.opened.connect(onOpened)
        let w0 = e.windUps, n = 0, hp0 = p.hp, fullAt = -1, letGo = -1, stateAtLetGo = "", openedAt = -1
        let stateAtOpen = "", left = -1, steps = toSteps(e.beatLen)
        while (n < 600) {
            hold(p, e, x, y, false)
            if (p.chargeFull && fullAt < 0) fullAt = n
            if (release && p.chargeFull && letGo < 0) {
                letGo = n
                stateAtLetGo = e.aiState
                p.releaseSwing()
            }
            let was = e.aiState
            Clayground.physicsStep(1)
            n++
            if (causes.length > 0 && openedAt < 0) {
                openedAt = n
                stateAtOpen = was
                left = steps - n
            }
            if (release ? openedAt >= 0 : e.aiState !== "retreat") break
        }
        e.opened.disconnect(onOpened)
        let out = {retreated: retreated, steps: n, beat: steps, fullAt: fullAt, letGo: letGo,
                   stateAtLetGo: stateAtLetGo, causes: causes, openedAt: openedAt, stateAtOpen: stateAtOpen,
                   left: left, windUps: e.windUps - w0, hurt: hp0 - p.hp,
                   charging: p.isCharging, full: p.chargeFull, after: e.aiState}
        if (!release) {
            // Out of the retreat with the charge still held: the lead strikes
            // first, as anywhere else
            let m = 0
            while (e.stringName === "" && m < 60) {
                hold(p, e, x, y, false)
                Clayground.physicsStep(1)
                m++
            }
            out.punish = e.windUpLength
            out.punishName = e.stringName
            out.punishAfter = m
        }
        settle(e)
        return out
    }

    // A guardian lead's shield against a blow of the knight's from the
    // front, in its retreat and facing the knight outside it
    function guardDown(g) {
        let p = game.player
        let x = p.xWu, y = p.yWu
        let retreated = playString(g)
        g.facingAngle = Math.atan2(p.yWu - g.yWu, p.xWu - g.xWu) * 180 / Math.PI
        let front = g._isShieldFacing(p.xWu, p.yWu)
        let inRetreat = g._blow(p.atk, p.xWu, p.yWu, false, "").blocked
        let w0 = g.windUps
        g.takeDamage(p.atk, p.xWu, p.yWu, false, false)
        Clayground.physicsStep(1)
        let countered = g.windUps !== w0 || g.aiState !== "retreat"
        let state = g.aiState
        settle(g)
        // Outside it: chasing, its shield to the knight
        leadOf(g, 1.5)
        g.aiState = "chase"
        g.facingAngle = Math.atan2(p.yWu - g.yWu, p.xWu - g.xWu) * 180 / Math.PI
        let outside = g._blow(p.atk, p.xWu, p.yWu, false, "").blocked
        settle(g)
        return {retreated: retreated, front: front, inRetreat: inRetreat, countered: countered, state: state,
                outside: outside}
    }

    // Every state a lead can be in
    readonly property var states: ["patrol", "idle", "chase", "circle", "kite", "telegraph", "crush", "lunge",
        "shoot", "bash", "stagger", "recovery", "frozen", "retreat"]
    function childNamed(e, name) {
        for (let c of e.children) if (c.objectName === name) return c
        return null
    }
    // What a lead shows in a state: its body's colour, the ring round it,
    // its eyes and a guardian's shield
    function lookOf(e) {
        let ring = childNamed(e, "toughRing"), eyes = childNamed(e, "enemyEyes")
        let shield = childNamed(e, "guardianShield")
        return {color: String(e.bodyColor), ring: !!ring && ring.visible, eyes: eyes ? eyes.shut : -1,
                eyesDim: eyes ? eyes.opacity : -1, shield: shield ? shield.opacity : -1}
    }
    // Sets e into each state, as the host's replicated state sets a lead on
    // another screen, from chase each time: what it looks like and the
    // sounds it logs there, by state; "spots" is the growl from its patrol
    // into the hunt
    function survey(e) {
        let out = {}
        game.logSounds = true
        let into = (from, to) => {
            e.aiState = from
            let at = game.soundLog.length
            e.aiState = to
            return {look: lookOf(e), sounds: game.soundLog.slice(at).map(x => x.cue + " " + x.pitch),
                    what: game.soundLog.slice(at).map(x => x.what)}
        }
        for (let s of states) out[s] = into("chase", s)
        out.spots = into("patrol", "chase")
        e.aiState = "idle"
        game.logSounds = false
        return out
    }

    function checkLooks(leads) {
        let l = Balance.lead
        for (let type of ["grunt", "guardian", "spitter", "slinger"]) {
            let e = leads[type]
            leadOf(e, 3)
            e.halted = true
            let sv = survey(e)
            let r = sv.retreat.look
            let others = states.filter(s => s !== "retreat")
            let clash = others.filter(s => sv[s].look.color === r.color)
            check(r.color === String(Qt.color(l.retreat.color)) && clash.length === 0,
                  "the " + type + " lead's body in its retreat is " + r.color + " (lead.retreat.color), a colour of "
                  + "no other state of it" + (clash.length ? ": " + clash.join(", ") + " share it" : "")
                  + " (" + others.map(s => s + " " + sv[s].look.color).join(", ") + ")")
            let ringOff = others.filter(s => !sv[s].look.ring)
            let shutOther = others.filter(s => sv[s].look.eyes !== 1 || sv[s].look.eyesDim !== 1)
            check(!r.ring && ringOff.length === 0 && near(r.eyes, l.retreat.eyes)
                  && near(r.eyesDim, l.retreat.eyesOpacity)
                  && shutOther.length === 0,
                  "only in its retreat is the ring round it gone (" + r.ring + ", gone also in: "
                  + (ringOff.join(", ") || "none") + ") and its eyes shut to " + r.eyes + " and dimmed to "
                  + r.eyesDim + " (also in: " + (shutOther.join(", ") || "none") + ")")
            if (type === "guardian") {
                let low = others.filter(s => sv[s].look.shield !== 1)
                check(near(r.shield, l.retreat.shieldOpacity) && low.length === 0,
                      "the guardian lead's shield hangs low only in its retreat, at " + r.shield
                      + " (lead.retreat.shieldOpacity; also in: " + (low.join(", ") || "none") + ")")
            }
            let mine = sv.retreat.sounds
            let heard = others.concat(["spots"])
            let elsewhere = heard.filter(s => sv[s].sounds.some(x => mine.indexOf(x) >= 0))
            let want = "sfx/lead_growl " + l.retreat.pitch
            check(mine.length === 1 && mine[0] === want && sv.retreat.what[0] === "retreat" && elsewhere.length === 0,
                  "the " + type + " lead's retreat sounds " + (mine.join(", ") || "nothing") + " (" + want
                  + "), which no other state of it plays (" + (elsewhere.join(", ") || "none")
                  + "; heard elsewhere: " + [...new Set(heard.reduce((a, s) => a.concat(sv[s].sounds), []))].join(", ") + ")")
            // Shown from another screen: its state the host's
            e.remote = true
            e.aiState = "retreat"
            let shown = lookOf(e)
            e.aiState = "idle"
            e.remote = false
            check(JSON.stringify(shown) === JSON.stringify(r),
                  "the " + type + " lead shown from another screen looks the same in its retreat ("
                  + JSON.stringify(shown) + ")")
            e.halted = false
            e.halt()
        }
    }

    property var leads: ({})

    function checkPace(step) {
        let l = Balance.lead, en = Balance.enemy, k = Balance.knight
        let f = step.factor, name = step.name
        game.duelPace = name
        for (let type of ["grunt", "guardian", "spitter", "slinger"]) {
            let e = leadOf(leads[type], 1.5)
            let tag = name + ", the " + type + " lead"
            let r = watchRetreat(e)
            let beat = toSteps(l.beat * f)
            check(r.retreated && near(r.beatLen, l.beat * f) && Math.abs(r.steps - beat) <= 1
                  && (r.after === "chase" || r.after === "kite"),
                  tag + ": after its string it retreats for " + r.steps + " steps, one beat of its pace (lead.beat "
                  + l.beat + " times " + f + " is " + beat + "), then goes for the knight (" + r.after + ")")
            let stepSteps = toSteps(l.retreat.step * l.beat * f)
            check(near(r.back, l.retreat.back, 0.06) && r.along > 0.99 && r.gained > 0 && r.lastMove > 0
                  && Math.abs(r.lastMove - stepSteps) <= 2,
                  tag + ": it steps back " + r3(r.back) + " wu (lead.retreat.back " + l.retreat.back
                  + ") the way its last blow came (" + r3(r.along) + "), " + r3(r.gained)
                  + " wu further from the knight, moving until step " + r.lastMove
                  + " (" + stepSteps + " by lead.retreat.step), then stands")
            check(r.windUps === 0 && r.blows === 0 && r.windows === 0 && r.rings === 0 && r.shots === 0 && r.hurt === 0,
                  tag + ": in it it strikes nobody: " + r.windUps + " wind-ups, " + r.blows + " blows, "
                  + r.windows + " steps of a parry window, " + r.rings + " of a ring, " + r.shots
                  + " shots in flight, " + r.hurt + " HP off the knight")

            e = leadOf(leads[type], 1.5)
            let held = chargeIntoRetreat(e, false)
            let tele = en.minTelegraph * f
            check(held.retreated && Math.abs(held.steps - held.beat) <= 1 && held.windUps === 0 && held.hurt === 0
                  && held.charging && held.full,
                  tag + ": a knight that starts a charge as the retreat starts and holds it is not struck: the "
                  + "retreat stands " + held.steps + " steps (" + held.beat + "), " + held.windUps
                  + " wind-ups, " + held.hurt + " HP off it, the charge still held (" + held.charging
                  + ") and full (" + held.full + ", from step " + held.fullAt + ")")
            if (type === "grunt" || type === "guardian")
                check(held.punishName !== "" && near(held.punish, tele),
                      tag + ": out of the retreat the lead strikes the charging knight first: \"" + held.punishName
                      + "\" " + held.punishAfter + " steps after, wound up " + r3(held.punish)
                      + " s (enemy.minTelegraph " + en.minTelegraph + " times " + f + ")")

            e = leadOf(leads[type], 1.5)
            let hit = chargeIntoRetreat(e, true)
            check(hit.retreated && hit.stateAtLetGo === "retreat" && hit.causes.join() === "heavy"
                  && hit.stateAtOpen === "retreat" && hit.left >= 0,
                  tag + ": a full charge begun as the retreat starts lands inside it: full at step " + hit.fullAt
                  + ", let go there (" + hit.stateAtLetGo + "), it opens the lead (" + (hit.causes.join() || "nothing")
                  + ") on step " + hit.openedAt + " of " + hit.beat + ", " + hit.left + " to spare")
        }
        let gd = guardDown(leadOf(leads.guardian, 1.5))
        check(gd.retreated && gd.front && !gd.inRetreat && !gd.countered && gd.state === "retreat" && gd.outside,
              name + ": in its retreat the guardian lead's guard is down: a blow from the front (" + gd.front
              + ") is not blocked (" + gd.inRetreat + "), no counter follows (" + gd.state
              + "); facing the knight outside it the same blow is blocked (" + gd.outside + ")")
    }

    // The Warden keeps today's fight (issue #368)
    function checkWarden(w) {
        let p = game.player, l = Balance.lead
        let x = p.xWu, y = p.yWu
        for (let o of game.enemies) if (o !== w && !o.destroyed) o.halt()
        w.dormant = false
        w.halted = false
        w.maxHp = 100000
        w.hp = 100000
        w.target = p
        w.xWu = p.xWu + 1.5 + w.bulk
        w.yWu = p.yWu + w.bulk
        w.beginString(0, false)
        w._endString()
        let state = w.aiState, cooldown = w.attackCooldown
        check(state === "recovery" && near(cooldown, l.recovery),
              "the Warden after a string recovers " + r3(cooldown) + " s (lead.recovery " + l.recovery
              + "), no retreat (" + state + ")")
        // One of its rests, the knight behind its shield, then a charge
        let i = l.strings.warden.findIndex(s => s.beats.indexOf(0) > 0)
        w.attackCooldown = 0
        w.beginString(i, false)
        let n = 0
        while (!(w._beat >= 0 && w._string[w._beat] === 0) && n < 1200) {
            hold(p, w, x, y, true)
            Clayground.physicsStep(1)
            n++
        }
        let inRest = w.aiState === "recovery"
        hold(p, w, x, y, false)
        p.lowerShield()
        p.attackCooldown = 0
        p.pressSwing()
        n = 0
        while (w.aiState === "recovery" && n < 600) {
            hold(p, w, x, y, false)
            Clayground.physicsStep(1)
            n++
        }
        let wound = w.windUpLength
        check(inRest && n < toSteps(w.beatLen) && near(wound, Balance.enemy.minTelegraph),
              "a knight that starts a charge in reach during the Warden's rest of \"" + l.strings.warden[i].name
              + "\" is struck first: the rest is cut short after " + n + " steps (" + toSteps(w.beatLen)
              + " a beat) and it winds up " + r3(wound) + " s (enemy.minTelegraph " + Balance.enemy.minTelegraph + ")")
        p.dropSwing()
        w.halt()
    }

    property var steps: [
        [() => game.screen === "title", () => {
            game.applyScenario("fight")
        }],
        [() => game.player && game.fightRoomActive
              && game.enemies.some(e => e.lead && e.enemyType === "guardian"), () => {
            Clayground.paused = true
            check(game.duelPace === Balance.pace.standard, "the game plays at " + game.duelPace)
            let p = game.player
            let spawn = (type, dx, dy) => {
                game.spawnEnemy(p.xWu + dx, p.yWu + dy, 2, type)
                return game.enemies[game.enemies.length - 1]
            }
            leads = {
                grunt: spawn("grunt", 0, 5),
                guardian: game.enemies.find(e => e.lead && e.enemyType === "guardian"),
                spitter: spawn("spitter", 0, -5),
                slinger: spawn("slinger", 5, 0)
            }
            for (let t in leads) leads[t].halt()
            Clayground.physicsStep(2)
            check(["grunt", "guardian", "spitter", "slinger"].every(t => leads[t] && leads[t].lead && !leads[t].boss),
                  "a grunt, a guardian, a spitter and a slinger lead stand in the fight room")
            checkLooks(leads)
            for (let s of Balance.pace.steps) checkPace(s)
            game.duelPace = Balance.pace.standard
            Clayground.paused = false
            game.applyScenario("boss", 2)
        }],
        [() => game.player && game.fightRoomActive && game.enemies.some(e => e.boss && !e.destroyed), () => {
            Clayground.paused = true
            checkWarden(game.enemies.find(e => e.boss && !e.destroyed))
            Clayground.paused = false
            console.log("[Retreat]", failures === 0 ? "all checks pass" : failures + " checks fail")
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
                    console.log("[Retreat] FAIL step", i, "timed out")
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
