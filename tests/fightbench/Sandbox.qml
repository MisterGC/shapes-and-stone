// Fight bench - plays the "fight" scenario with a scripted knight and
// reports how the fight went (issues #34, #267).
//
// The game runs paused: run_fightbench.py steps it through the inspector,
// a few physics steps of exactly 1/60 s at a time, so the fight does not
// depend on how fast the machine renders. The pilot below plays the knight
// on every step; what it does depends only on the fight and on its seed.
// The totals are the game's own fight record (Game.qml); the bench adds
// what it sees of each enemy on every step, and what the game would have
// let the player hear: its sound log and music trace (Game.logSounds),
// muted.
//
// Driven by run_fightbench.py (clayliveloader --sbx Sandbox.qml), which
// calls begin(seed, answer, danger, room, sword), steps and reads report().

import QtQuick
import Clayground.Common
import "../../src"

Item {
    id: bench
    anchors.fill: parent

    Game {
        id: game
        anchors.fill: parent
        muted: true
    }

    // The dojo's scenario menu reaches the game through the bench
    function scenarios() { return game.scenarios() }
    function applyScenario(name, danger) { game.applyScenario(name, danger) }

    // ---- driver API ----
    property int seed: 0
    property string answer: "mix"
    property real danger: 0
    property string room: "mixed"
    property int sword: 0
    property int steps: 0
    property var _rng: null

    // Pauses the world and enters the fight room; the driver steps from here.
    // answer is how the knight fights: "mix", "block", "parry", "perfect",
    // "heavy" (as mix, but it charges at guardians), "whirlwind" (as mix,
    // but it whirls through every enemy), or one of the pacing pilots
    // "charge", "masher" and "skilled" (Balance.pacing);
    // danger is the danger the fight room is at: its depth and, after the
    // point, the position in the depth's range (Game.applyScenario);
    // room who stands in it: "mixed" (Balance.spawn.fightRoom), "flow" or
    // "duel" (Balance.pacing); sword the knight's sword level, -1 for the
    // one it usually has at that depth (usualSword), 0 when left out
    function begin(s, a, d, r, sw) {
        Clayground.paused = true
        seed = s
        answer = a === undefined ? "mix" : a
        danger = d === undefined ? 0 : d
        room = r === undefined ? "mixed" : r
        steps = 0
        _rng = game.createRng(s)
        _plans = new Map()
        _blockLeft = 0
        _held = false
        heavySwings = 0
        guardBreaks = 0
        _staggered = new Set()
        crushBlows = 0
        _crushing = new Set()
        whirlsStarted = 0
        cancelledCharges = 0
        _chargeSeen = ""
        engagedSeconds = 0
        _foes = []
        // What would be heard, on the physics steps: muted, logged
        game.logSounds = true
        game.followFightOnSteps = true
        // The dojo's scenarios: "fight" for the mixed room, "flow", "duel"
        game.applyScenario(room === "mixed" ? "fight" : room, danger)
        // The log's clock from 0, in steps of exactly 1/60 s: the same
        // fight logs the same times
        game.clearSoundLog()
        game.physicsSeconds = 0
        sword = sw === undefined ? 0 : sw < 0 ? usualSword(Math.floor(danger)) : sw
        // The bench tries the moves, not the mana they cost: plenty of it
        if (game.player) {
            game.player.maxMana = 1000
            game.player.mana = 1000
            game.player.swordLevel = sword
        }
        if (game.player) game.player.acted.connect(a => {
            if (a === "heavy") bench.heavySwings++
            if (a === "whirlwind") bench.whirlsStarted++
        })
        for (let e of game.enemies.filter(alive)) {
            let f = { ref: e, type: e.enemyType, tier: e.tier, lead: e.lead, hp: e.maxHp, lastHp: e.hp,
                      lastState: e.aiState, engagedAt: null, firstHitAt: null, diedAt: null,
                      hits: 0, openings: 0, opened: {} }
            // A lead's openings by what broke its stance (Enemy.open)
            e.opened.connect(cause => f.opened[cause] = (f.opened[cause] || 0) + 1)
            _foes.push(f)
        }
        return game.player !== null
    }
    // The sword level a knight usually has at depth d: the highest the
    // smith of a camp before it sold (the camp after depth c sells level L
    // once c reaches shop.levelDepth[L - 1]), one level a camp
    function usualSword(d) {
        return Balance.shop.levelDepth.filter(c => c < d).length
    }

    readonly property var record: game.fightRecord
    readonly property bool cleared: record.clearSeconds >= 0
    readonly property bool fallen: game.fallen
    readonly property bool done: cleared || fallen

    // Seconds since begin() on the physics clock
    function now() { return round3(game.physicsSeconds) }

    function report() {
        // A death on the last step is seen now
        track(0)
        let r = record
        let p = game.player
        let foes = _foes.map(f => ({
            type: f.type, tier: f.tier, lead: f.lead, hp: f.hp,
            engagedAt: f.engagedAt, firstHitAt: f.firstHitAt, diedAt: f.diedAt,
            hits: f.hits, openings: f.openings, opened: f.opened,
            // From the first blow that landed to its death
            ttk: f.diedAt !== null && f.firstHitAt !== null ? round3(f.diedAt - f.firstHitAt) : null,
            // From the moment it went for the knight to its death
            ttkEngaged: f.diedAt !== null && f.engagedAt !== null ? round3(f.diedAt - f.engagedAt) : null
        }))
        let kills = foes.filter(f => f.diedAt !== null).map(f => f.diedAt).sort((a, b) => a - b)
        let gaps = []
        for (let i = 1; i < kills.length; i++) gaps.push(round3(kills[i] - kills[i - 1]))
        return {
            seed: seed,
            answer: answer,
            room: room,
            depth: game.depth,
            danger: round3(game.danger),
            sword: sword,
            outcome: cleared ? "cleared" : fallen ? "fallen" : "running",
            steps: steps,
            seconds: round3(r.seconds),
            damageDealt: r.damageDealt,
            damageTaken: r.damageTaken,
            parries: r.parries,
            blocks: r.blocks,
            perfectBlocks: r.perfectBlocks,
            crushBlows: crushBlows,
            crushed: r.crushed,
            heavySwings: heavySwings,
            guardBreaks: guardBreaks,
            whirlwinds: r.whirlwinds,
            whirlHits: r.whirlHits,
            whirlsStarted: whirlsStarted,
            kills: r.kills,
            // Kill chains of two links or more, and the longest's links
            chains: r.chains,
            longestChain: r.longestChain,
            deaths: r.deaths,
            clearSeconds: r.clearSeconds >= 0 ? round3(r.clearSeconds) : null,
            knightHp: p ? p.hp : 0,
            knightMana: p ? round3(p.mana) : 0,
            openings: foes.reduce((n, f) => n + f.openings, 0),
            cancelledCharges: cancelledCharges,
            engagedSeconds: round3(engagedSeconds),
            killGaps: gaps,
            enemies: foes,
            sounds: game.soundLog,
            music: game.musicTrace
        }
    }
    function round3(v) { return Math.round(v * 1000) / 1000 }

    // ---- what the bench sees of each enemy, every step ----
    // A blow that landed is HP lost; an opening is a stagger it went into
    // (a parry, a perfect block, a broken guard), and a lead's are counted
    // by what broke its stance too (opened); it engaged on the first
    // step it was neither patrolling nor idle - chasing, circling, winding
    // up, striking, recovering, staggered; it died on the step it was
    // gone, the blow that killed it one more hit. Time engaged is the
    // seconds in which any enemy was engaged
    property var _foes: []
    property real engagedSeconds: 0
    readonly property var calm: ["patrol", "idle"]
    function track(dt) {
        let t = now(), engaged = false
        for (let f of _foes) {
            if (f.diedAt !== null) continue
            let e = f.ref
            if (!alive(e)) {
                f.diedAt = t
                if (f.lastHp > 0) {
                    f.hits++
                    if (f.firstHitAt === null) f.firstHitAt = t
                }
                continue
            }
            if (e.hp < f.lastHp) {
                f.hits++
                if (f.firstHitAt === null) f.firstHitAt = t
            }
            f.lastHp = e.hp
            let into = calm.indexOf(e.aiState) < 0
            if (into) engaged = true
            if (into && f.engagedAt === null) f.engagedAt = t
            if (e.aiState === "stagger" && f.lastState !== "stagger") f.openings++
            f.lastState = e.aiState
        }
        if (engaged) engagedSeconds += dt
    }

    // A charge ended without its release: a hit, the shield or a dash
    // cancelled it while the button was held (Player._cancelCharge)
    property int cancelledCharges: 0
    property string _chargeSeen: ""
    function trackCharge(p) {
        if ((_chargeSeen === "charging" || _chargeSeen === "full") && p._charge === "spent")
            cancelledCharges++
    }

    // ---- the charge, tried as in the dojo (run_reload.py) ----
    // The fight room stands: the knight and its grunt, guardian and spitter
    function fightReady() {
        return game.player !== null && game.fightRoomActive === true
            && ["grunt", "guardian", "spitter"].every(t => game.enemies.some(
                e => e.enemyType === t && alive(e)))
    }
    // Holds the left button until the charge is full, counting the physics
    // steps, then lets go at the guardian, which stands in front of the
    // knight and faces it. The enemies stand still meanwhile. The fight
    // room's tough guardian is its lead (Balance.lead), which a charge
    // does not stagger: here it is none. Returns the steps, whether the
    // guardian staggered and the HP it lost, as JSON
    function tryCharge() {
        Clayground.paused = true
        let p = game.player
        let foes = game.enemies.filter(alive)
        for (let e of foes) e.halt()
        let gd = foes.find(e => e.enemyType === "guardian")
        gd.lead = false
        p.isBlocking = false
        p.moveX = 0
        p.moveY = 0
        p.facingAngle = 0
        p.attackCooldown = 0
        p.pressSwing()
        let n = 0
        while (!p.chargeFull && n < 600) {
            Clayground.physicsStep(1)
            n++
        }
        gd.xWu = p.xWu + 1.5
        gd.yWu = p.yWu
        gd.facingAngle = 180
        Clayground.physicsStep(1)
        let hp0 = gd.hp
        p.releaseSwing()
        Clayground.physicsStep(1)
        return JSON.stringify({fullSteps: n, staggered: gd.aiState === "stagger",
                               lost: hp0 - gd.hp, chargeTime: Balance.knight.chargeTime})
    }

    // ---- the kill chain, tried as in the dojo (run_reload.py) ----
    // Every enemy stands still; the knight strikes one down, then gapSteps
    // physics steps later another. The links the second kill made, the
    // death sound's pitches and Balance.chain.window
    function tryChain(gapSteps) {
        Clayground.paused = true
        let p = game.player
        let foes = game.enemies.filter(alive)
        for (let e of foes) e.halt()
        game.breakChain()
        game.logSounds = true
        game.clearSoundLog()
        foes[0].takeDamage(100000, p.xWu, p.yWu)
        Clayground.physicsStep(gapSteps)
        foes[1].takeDamage(100000, p.xWu, p.yWu)
        Clayground.physicsStep(1)
        return JSON.stringify({links: game.chainLinks, window: Balance.chain.window,
                               pitches: game.soundLog.filter(l => l.what === "death").map(l => l.pitch)})
    }

    // ---- the crushing blow, tried as in the dojo (run_reload.py) ----
    // Only the tough guardian goes for the knight, which stands; the others
    // stand still. Steps until the guardian has wound up attacks attacks or
    // maxSteps have passed. Returns the attacks, the crushing ones among
    // them and the chances, as JSON
    function tryCrush(attacks, maxSteps) {
        Clayground.paused = true
        let p = game.player
        let foes = game.enemies.filter(alive)
        let gd = foes.find(e => e.enemyType === "guardian")
        for (let e of foes) if (e !== gd) e.halt()
        p.isBlocking = false
        p.moveX = 0
        p.moveY = 0
        p.hp = 100000
        let n = 0, wound = 0, crushes = 0, last = gd.aiState
        while (wound < attacks && n < maxSteps) {
            Clayground.physicsStep(1)
            n++
            if (gd.aiState !== last && (gd.aiState === "telegraph" || gd.aiState === "crush")) {
                wound++
                if (gd.aiState === "crush") crushes++
            }
            last = gd.aiState
        }
        return JSON.stringify({attacks: wound, crushes: crushes, steps: n, tier: gd.tier,
                               guardianChance: gd.crushChance, crushChance: Balance.enemy.crushChance})
    }

    // ---- a lead's stance, tried as in the dojo (run_reload.py) ----
    // The duel room stands: the knight and a lead
    function duelReady() {
        return game.player !== null && game.fightRoomActive === true
            && game.enemies.some(e => alive(e) && e.lead)
    }
    // Opens the lead as a parry would and strikes it with a swing of the
    // knight's atk in the opening. Returns whether its stance bar showed,
    // whether it opened, the seconds the opening lasts, the HP the swing
    // took and the HP the table says it takes, as JSON
    function tryOpening() {
        Clayground.paused = true
        let p = game.player
        let lead = game.enemies.find(e => alive(e) && e.lead)
        for (let e of game.enemies.filter(alive)) e.halt()
        let bar = false
        for (let i = 0; i < lead.children.length; i++)
            if (lead.children[i].objectName === "stanceBar") bar = lead.children[i].visible
        lead.halted = false
        lead.open("parry")
        let opened = lead.opening && lead.aiState === "stagger"
        let seconds = round3(lead._attackTimer)
        let hp0 = lead.hp
        lead.takeDamage(p.atk, p.xWu, p.yWu, false)
        return JSON.stringify({bar: bar, opened: opened, seconds: seconds, lost: hp0 - lead.hp,
                               want: Math.floor(Math.max(Balance.minDamage, p.atk - lead.def)
                                                * Balance.lead.openingDamage),
                               openingTime: Balance.lead.openingTime})
    }

    // ---- the scripted knight ----
    // Each attack an enemy winds up gets one plan: "parry" waits for the
    // parry window and swings into it, "block" raises the shield towards
    // it, "perfect" keeps the shield down until the lunge is perfectLead
    // steps from landing and raises it then. The answer "mix" rolls the
    // plan from the seed between parry and block; "block", "parry" and
    // "perfect" always pick that one; a crushing blow (aiState "crush") gets
    // the same plans, and a parry finds no window. A shot is always blocked. "heavy"
    // meets attacks as "mix" does; it answers a guardian's shield with a
    // charged heavy swing instead of a shield dash: it holds the left
    // button on its way in and lets go once the charge is full and the
    // guardian in the heavy swing's reach. "whirlwind" fights as "mix"
    // does and earns momentum by it; with all of it (Balance.momentum) and
    // an enemy within whirlFrom it whirls at that enemy (Q, unleash).
    //
    // The pacing pilots (Balance.pacing): "charge" never raises the shield;
    // it holds a full charge, walks at the nearest enemy and lets go once
    // it is in the heavy swing's reach, then presses again. "masher" never
    // raises the shield either: it walks at the nearest enemy and clicks on
    // every step it can swing. "skilled" parries every lunge and
    // perfect-blocks every crushing blow, blocks a shot - walking on at
    // the nearest enemy behind the shield -, breaks a
    // guardian's guard with the shield dash, and swings only into an
    // opening: an enemy within reach that is not winding up or lunging
    property var _plans: new Map()
    property real _blockLeft: 0     // seconds the shield stays up for a shot
    // Steps before a lunge lands that the "perfect" plan raises the shield
    readonly property int perfectLead: 4
    readonly property real parryChance: answer === "block" || answer === "perfect" ? 0
                                      : answer === "parry" ? 1 : 0.6
    // The scripted left button is held, and heavy swings so far
    property bool _held: false
    property int heavySwings: 0
    // Guardians a heavy swing staggered
    property int guardBreaks: 0
    property var _staggered: new Set()
    // Crushing blows wound up at the knight
    property int crushBlows: 0
    property var _crushing: new Set()
    function countCrushes() {
        for (let e of game.enemies.filter(alive)) {
            let now = e.aiState === "crush"
            if (now && !_crushing.has(e)) crushBlows++
            if (now) _crushing.add(e); else _crushing.delete(e)
        }
    }
    function countGuardBreaks(p) {
        for (let e of game.enemies.filter(alive)) {
            if (e.enemyType !== "guardian") continue
            let now = e.aiState === "stagger"
            if (now && !_staggered.has(e) && p.isHeavy) guardBreaks++
            if (now) _staggered.add(e); else _staggered.delete(e)
        }
    }
    function heavyReach(p) { return p.attackRange * Balance.knight.heavyRange * 0.9 }
    // Whirlwinds begun, and how close the knight whirls at an enemy
    property int whirlsStarted: 0
    readonly property real whirlFrom: 3.5
    function letGo(p) {
        if (_held) p.dropSwing()
        _held = false
    }

    Connections {
        target: game.physics
        enabled: game.player !== null && bench._rng !== null
        function onStepped() {
            bench.steps++
            bench.track(game.physics.timeStep)
            if (game.player) {
                bench.countGuardBreaks(game.player)
                bench.trackCharge(game.player)
            }
            bench.countCrushes()
            if (bench.answer === "charge") bench.pilotCharge()
            else if (bench.answer === "masher") bench.pilotMasher()
            else if (bench.answer === "skilled") bench.pilotSkilled(game.physics.timeStep)
            else bench.pilot(game.physics.timeStep)
            if (game.player) bench._chargeSeen = game.player._charge
        }
    }

    function alive(e) { return e && e.destroyed === false }
    function distTo(p, x, y) {
        let dx = x - p.xWu, dy = y - p.yWu
        return Math.sqrt(dx * dx + dy * dy)
    }
    // Facing thing o, centre to centre, as the shield measures it
    // (Player.isShieldFacing)
    function face(p, o) {
        let ox = o.xWu + o.widthWu / 2, oy = o.yWu - o.heightWu / 2
        let px = p.xWu + p.widthWu / 2, py = p.yWu - p.heightWu / 2
        p.facingAngle = Math.atan2(oy - py, ox - px) * 180 / Math.PI
    }
    // moveY is screen down, world y is up
    function moveTowards(p, x, y, speed) {
        let dx = x - p.xWu, dy = y - p.yWu
        let len = Math.sqrt(dx * dx + dy * dy)
        if (len < 0.01) { p.moveX = 0; p.moveY = 0; return }
        p.moveX = dx / len * speed
        p.moveY = -dy / len * speed
    }
    function stand(p) { p.moveX = 0; p.moveY = 0 }
    function winding(e) { return e.aiState === "telegraph" || e.aiState === "crush" || e.aiState === "lunge" }
    function nearest(p, foes) {
        let target = foes[0], targetDist = distTo(p, target.xWu, target.yWu)
        for (let e of foes) {
            let d = distTo(p, e.xWu, e.yWu)
            if (d < targetDist) { target = e; targetDist = d }
        }
        return { e: target, d: targetDist }
    }
    // The standing enemies, or null once there is nothing to fight: the
    // knight stands then, the button and the shield let go
    function foesOrRest(p) {
        let foes = p && !p.fallen && !done ? game.enemies.filter(alive) : []
        if (foes.length > 0) return foes
        if (p) { stand(p); letGo(p); p.isBlocking = false }
        return null
    }

    // An attack coming at the knight within reach: answered by its plan,
    // the first time it is seen rolled by planOf(threat). Returns whether
    // there was one
    function answerThreat(p, foes, planOf) {
        // Forget plans of attacks that are over
        for (let e of Array.from(_plans.keys()))
            if (!alive(e) || !winding(e))
                _plans.delete(e)
        let threat = null, threatDist = 1e9
        for (let e of foes) {
            if (e.enemyType === "spitter") continue
            if (!winding(e)) continue
            let d = distTo(p, e.xWu, e.yWu)
            if (d < 3.5 && d < threatDist) { threat = e; threatDist = d }
        }
        if (!threat) return null
        return { e: threat, d: threatDist, answer: () => {
            letGo(p)
            if (!_plans.has(threat)) _plans.set(threat, planOf(threat))
            face(p, threat)
            stand(p)
            if (_plans.get(threat) === "parry") {
                p.isBlocking = false
                if (threat.parryWindow && threatDist <= p.attackRange) p.attack()
            } else if (_plans.get(threat) === "perfect") {
                p.isBlocking = threat.aiState === "lunge" && threat._lungeSteps <= perfectLead
            } else {
                p.isBlocking = true
            }
        } }
    }
    // A spitter's shot on its way: shield up towards it a moment, standing
    // or, with towards, walking at that enemy behind it. Returns whether
    // the shield is up for one
    function answerShot(p, dt, towards) {
        let shot = null, shotDist = 1e9
        for (let o of game.room.children) {
            if (o.objectName !== "projectile" || o.destroyed !== false) continue
            let d = distTo(p, o.xWu, o.yWu)
            if (d < 3 && d < shotDist) { shot = o; shotDist = d }
        }
        if (shot) {
            letGo(p)
            _blockLeft = 0.3
            face(p, shot)
        }
        if (_blockLeft > 0) {
            _blockLeft -= dt
            p.isBlocking = true
            if (towards) moveTowards(p, towards.xWu, towards.yWu, 1)
            else stand(p)
            return true
        }
        p.isBlocking = false
        return false
    }
    // A guardian's shield turns swings: a shield dash breaks its guard.
    // Returns whether the knight dashed
    function shieldDash(p, target, targetDist) {
        if (target.enemyType === "guardian" && target.aiState !== "stagger"
                && targetDist < 2.5 && p.dashCooldown <= 0 && !p.isDashing) {
            p.isBlocking = true
            moveTowards(p, target.xWu, target.yWu, 1)
            p.dash()
            return true
        }
        return false
    }

    function pilot(dt) {
        let p = game.player
        let foes = foesOrRest(p)
        if (!foes) return

        // 1. An attack coming at the knight: parry or block it
        let threat = answerThreat(p, foes, () => answer === "perfect" ? "perfect"
                                                 : _rng() < parryChance ? "parry" : "block")
        if (threat) {
            // A guardian winding up within reach of a full charge: the
            // heavy swing staggers it before its blow
            if (answer === "heavy" && threat.e.enemyType === "guardian" && p.chargeFull
                    && threat.d <= heavyReach(p)) {
                face(p, threat.e)
                stand(p)
                p.releaseSwing()
                _held = false
                return
            }
            threat.answer()
            return
        }

        // 2. A spitter's shot on its way: shield up towards it a moment
        if (answerShot(p, dt)) return

        // 3. Go for the nearest enemy
        let near = nearest(p, foes), target = near.e, targetDist = near.d
        face(p, target)

        // A guardian's shield turns swings: a charged heavy swing breaks
        // its guard
        if (answer === "heavy" && target.enemyType === "guardian" && target.aiState !== "stagger") {
            // The charge was cancelled (a hit): press anew
            if (_held && !p.isCharging && p.chargeHeld > Balance.knight.chargeStart) letGo(p)
            if (!_held) _held = p.pressSwing()
            if (p.chargeFull && targetDist <= heavyReach(p)) {
                p.releaseSwing()
                _held = false
            }
            // Charging, it lets the guardian come; full, it goes in
            if (p.chargeFull && targetDist > 1.3) moveTowards(p, target.xWu, target.yWu, 1)
            else stand(p)
            return
        }
        // With all the momentum and an enemy close, a whirlwind at it;
        // otherwise it fights as "mix" does
        if (answer === "whirlwind" && !p.isDashing && p.momentum >= Balance.momentum.max
                && targetDist <= whirlFrom) {
            letGo(p)
            moveTowards(p, target.xWu, target.yWu, 1)
            p.unleash()
            return
        }
        letGo(p)
        if (shieldDash(p, target, targetDist)) return
        if (p.isDashing) return

        if (targetDist > 1.3) moveTowards(p, target.xWu, target.yWu, 1)
        else stand(p)
        if (targetDist <= p.attackRange * 0.9) p.attack()
    }

    // "charge": a full charge, let go at the nearest enemy in reach
    function pilotCharge() {
        let p = game.player
        let foes = foesOrRest(p)
        if (!foes) return
        p.isBlocking = false
        let near = nearest(p, foes), target = near.e
        face(p, target)
        // A hit cancelled the charge: let go and press anew
        if (_held && p._charge === "spent") letGo(p)
        if (!_held) _held = p.pressSwing()
        if (p.chargeFull && near.d <= heavyReach(p)) {
            stand(p)
            p.releaseSwing()
            _held = false
            return
        }
        if (near.d > heavyReach(p) * 0.8) moveTowards(p, target.xWu, target.yWu, 1)
        else stand(p)
    }

    // "masher": at the nearest enemy, a click on every step it can swing
    function pilotMasher() {
        let p = game.player
        let foes = foesOrRest(p)
        if (!foes) return
        p.isBlocking = false
        letGo(p)
        let near = nearest(p, foes), target = near.e
        face(p, target)
        if (near.d > 1.3) moveTowards(p, target.xWu, target.yWu, 1)
        else stand(p)
        p.attack()
    }

    // "skilled": every attack answered, swings only into openings
    function pilotSkilled(dt) {
        let p = game.player
        let foes = foesOrRest(p)
        if (!foes) return
        let threat = answerThreat(p, foes, e => e.aiState === "crush" || e.crushing ? "perfect" : "parry")
        if (threat) {
            threat.answer()
            return
        }
        let near = nearest(p, foes), target = near.e
        if (answerShot(p, dt, near.d > 1.3 ? target : null)) return
        letGo(p)
        face(p, target)
        if (shieldDash(p, target, near.d)) return
        if (p.isDashing) return
        if (near.d > 1.3) moveTowards(p, target.xWu, target.yWu, 1)
        else stand(p)
        if (near.d <= p.attackRange * 0.9 && !winding(target)) p.attack()
    }
}
