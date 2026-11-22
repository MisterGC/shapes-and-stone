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
// calls begin(seed, answer, danger, room, sword, boots, special), steps and
// reads report().

import QtQuick
import Clayground.Common
import "../../src"

Item {
    id: bench
    anchors.fill: parent

    Game {
        id: game
        anchors.fill: parent
        // The descent intro would hold each dungeon's first seconds (issue #316)
        descentIntro: false
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
    property int boots: 0
    // The special the person pilot was given (issue #344), "" for none
    property string personSpecial: ""
    property int steps: 0
    property var _rng: null

    // Pauses the world and enters the fight room; the driver steps from here.
    // answer is how the knight fights: "mix", "block", "parry", "perfect",
    // "heavy" (as mix, but it charges at guardians), "whirlwind" (as mix,
    // but it whirls through every enemy), "stun" (as mix, but it stuns,
    // issue #318), "bolt" (as "masher", but it lets bolts loose for the
    // knight's own mana, issue #319), or one of the pacing pilots
    // "charge", "masher", "skilled" and "person" (Balance.pacing);
    // danger is the danger the fight room is at: its depth and, after the
    // point, the position in the depth's range (Game.applyScenario);
    // room who stands in it: "mixed" (Balance.spawn.fightRoom), "flow",
    // "duel", "guardianduel", "spitterduel", "ballduel" or "boss" (Balance.pacing); sword the knight's sword level, -1 for the
    // one it usually has at that depth (usualSword), 0 when left out;
    // boots the level of its swift boots (Balance.shop.bootsSpeed, issue
    // #325), 0 when left out; special the special the "person" pilot
    // fires (whirlwind, stun or bolt, issue #344), none when left out or
    // for any other pilot
    function begin(s, a, d, r, sw, bo, sp) {
        Clayground.paused = true
        seed = s
        answer = a === undefined ? "mix" : a
        danger = d === undefined ? 0 : d
        room = r === undefined ? "mixed" : r
        personSpecial = answer === "person" && Balance.specials.order.indexOf(sp) >= 0 ? sp : ""
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
        _stunAt = -1000
        _boltAt = -1000
        boltEnds = []
        balls = ({})
        cancelledCharges = 0
        _chargeSeen = ""
        engagedSeconds = 0
        _phase2At = null
        _foes = []
        _attacks = new Map()
        _personPlans = new Map()
        _shotsSeen = new Map()
        _shotPlans = new Map()
        _zonesSeen = new Map()
        personAnswers = { parry: 0, perfect: 0, shot: 0 }
        personMissed = { parry: 0, perfect: 0, shot: 0 }
        personFastest = -1
        _answerCount = 0
        _missPhase = answer === "person" ? missPhaseOf(s, room, danger) : 0
        if (personSpecial !== "") {
            personAnswers.special = 0
            personMissed.special = 0
        }
        _specialPlan = null
        _chanceAt = -1
        _pressAt = -1
        specialUse = { presses: 0, fired: 0, strong: 0, early: 0, late: 0 }
        hurtBy = ({})
        _knightHp = -1
        _knightStartHp = -1
        knightHealed = 0
        _zoneHitsSeen = game.bossFight.zoneHits
        _hurtCause = ""
        manaDry = 0
        _dry = false
        // What would be heard, on the physics steps: muted, logged
        game.logSounds = true
        game.followFightOnSteps = true
        // The dojo's scenarios: "fight" for the mixed room, "flow", "duel",
        // "guardianduel", "spitterduel", "ballduel", "boss"
        game.applyScenario(room === "mixed" ? "fight" : room, danger)
        // The log's clock from 0, in steps of exactly 1/60 s: the same
        // fight logs the same times
        game.clearSoundLog()
        game.physicsSeconds = 0
        sword = sw === undefined ? 0 : sw < 0 ? usualSword(Math.floor(danger)) : sw
        boots = bo === undefined ? 0 : bo
        // The bench tries the moves, not the mana they cost: plenty of it.
        // The bolt's pilot pays its bolts from the knight's own mana: what
        // the mana allows is the question its duel asks (issue #319); so
        // does the person with a special, which pays it as a person does
        // (issue #344)
        if (game.player) {
            game.player.maxMana = answer === "bolt" || personSpecial !== "" ? Balance.knight.mana : 1000
            game.player.mana = game.player.maxMana
            game.player.swordLevel = sword
            game.player.bootsLevel = boots
            // The special's button lets the stun loose for "stun", the bolt
            // for "bolt", the person's own for the person given one, else
            // the whirlwind
            game.player.special = answer === "stun" || answer === "bolt" ? answer
                                : personSpecial !== "" ? personSpecial : "whirlwind"
        }
        if (game.player) game.player.acted.connect(a => {
            if (a === "heavy") bench.heavySwings++
            if (a === "whirlwind" || a === "whirlwind+") bench.whirlsStarted++
            if (a === "hurt" || a === "block") bench._hurtCause = bench.hurtCause(game.player)
        })
        for (let e of game.enemies.filter(alive)) follow(e)
        if (!_boltsFollowed) {
            _boltsFollowed = true
            game.boltEnded.connect(bench.boltEnded)
            game.ballBounced.connect(bench.ballBounced)
            game.ballTurned.connect(bench.ballTurned)
            game.ballFell.connect(bench.ballFell)
        }
        return game.player !== null
    }

    // Every bolt that ended (issue #319): when, how ("enemy", "wall",
    // "reach"), how far it flew, where it ended, how far from the room's
    // centre along either axis, and for an enemy its type, whether a
    // lead, the damage it dealt and the damages the table allows it -
    // bolt.damage times atk less its defense, a chip of that on a lead's
    // stance, that much in an opening, a guardian's shield's share of it
    property var boltEnds: []
    property bool _boltsFollowed: false
    function boltEnded(id, how, enemy, dealt, x, y, travelled, own) {
        if (!own) return
        let b = { t: now(), how: how, travelled: round3(travelled), x: round3(x), y: round3(y),
                  edge: round3(Math.max(Math.abs(x - game._fightRoomCx), Math.abs(y - game._fightRoomCy))) }
        if (how === "enemy" && enemy) {
            let p = game.player
            let base = Math.max(Balance.minDamage, Math.round(p.atk * Balance.bolt.damage) - enemy.def)
            let allowed = enemy.lead && enemy.opening ? [Math.floor(base * Balance.lead.openingDamage)]
                : enemy.lead ? [Math.max(Balance.minDamage, Math.round(base * Balance.lead.chip))] : [base]
            if (enemy.enemyType === "guardian") allowed.push(Math.floor(allowed[0] * Balance.enemy.blockedShare))
            Object.assign(b, { type: enemy.enemyType, lead: enemy.lead, dealt: dealt, allowed: allowed })
        }
        boltEnds.push(b)
    }
    // Every metal ball of a slinger's (issue #322), by its id: when it was
    // slung, its wall bounces - when, where its centre touched the wall
    // and how far from the room's centre along either axis -, the shield
    // that turned it ("blocked" or "perfect") and when, and how it fell,
    // when and after how many bounces
    property var balls: ({})
    function _ball(id) {
        if (!balls[id]) balls[id] = { at: now(), bounces: [], turned: null, turnedAt: null, fell: null }
        return balls[id]
    }
    function ballBounced(id, n, x, y) {
        _ball(id).bounces.push({ t: now(), n: n, x: round3(x), y: round3(y),
                                 edge: round3(Math.max(Math.abs(x - game._fightRoomCx), Math.abs(y - game._fightRoomCy))) })
    }
    function ballTurned(id, by, local, dx, dy) {
        let b = _ball(id)
        b.turned = by
        b.turnedAt = now()
    }
    function ballFell(id, how, bounces, by, x, y) {
        _ball(id).fell = { t: now(), how: how, bounces: bounces, x: round3(x), y: round3(y) }
    }
    // An enemy the bench follows from now on: from the start, or one that
    // came later (the Warden's adds)
    function follow(e) {
        let f = { ref: e, type: e.enemyType, tier: e.tier, lead: e.lead, hp: e.maxHp, lastHp: e.hp,
                  lastState: e.aiState, lastStance: e.stance, engagedAt: null, firstHitAt: null,
                  diedAt: null, hits: 0, openings: 0, opened: {}, openedAt: [],
                  cameAt: steps > 0 ? now() : 0,
                  stuns: [], lastStunAt: null, frozen: null, frozenSpans: [] }
        // A lead's openings by what broke its stance (Enemy.open), and when
        e.opened.connect(cause => {
            f.opened[cause] = (f.opened[cause] || 0) + 1
            f.openedAt.push({ t: now(), cause: cause })
        })
        // What a knight's stun did to it (Enemy.stun, issue #318): the
        // state it was in on the step before and the one after, whether
        // it opened, its stance before and after
        e.stunned.connect(what => {
            f.stuns.push({ t: now(), what: what, before: f.lastState, after: e.aiState,
                           opening: e.opening, stanceBefore: f.lastStance, stance: e.stance })
            if (what === "frozen") f.lastStunAt = now()
        })
        _foes.push(f)
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
        // A death on the last step is seen now, and the blow that felled
        // the knight
        track(0)
        if (game.player) trackHurt(game.player)
        let r = record
        let p = game.player
        let foes = _foes.map(f => ({
            type: f.type, tier: f.tier, lead: f.lead, hp: f.hp,
            engagedAt: f.engagedAt, firstHitAt: f.firstHitAt, diedAt: f.diedAt,
            hits: f.hits, openings: f.openings, opened: f.opened, openedAt: f.openedAt,
            // Its stuns, and each span it stood frozen (issue #318): from
            // the last stun that froze it to its thaw, how far it moved and
            // the state it thawed into; open at the end when it died
            // frozen or the fight stopped
            stuns: f.stuns,
            frozenSpans: f.frozenSpans.concat(f.frozen ? [Object.assign({}, f.frozen, {
                thawAt: null, lasted: null, into: f.diedAt !== null ? "died" : "running" })] : []),
            // The HP it had left, 0 once dead
            hpLeft: f.diedAt !== null ? 0 : f.lastHp,
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
            boots: boots,
            moveSpeed: p ? p.maxSpeed : Balance.knight.moveSpeed,
            outcome: cleared ? "cleared" : fallen ? "fallen" : "running",
            steps: steps,
            seconds: round3(r.seconds),
            damageDealt: r.damageDealt,
            damageTaken: r.damageTaken,
            parries: r.parries,
            blocks: r.blocks,
            perfectBlocks: r.perfectBlocks,
            // Shots a perfect block sent back, and the ones that hit an
            // enemy (Balance.projectile)
            shotsBack: r.shotsBack,
            shotBackHits: r.shotBackHits,
            // The slinger's metal balls (Balance.ball, issue #322): the
            // ones the knight's shield bounced, a perfect block aimed and
            // that hit an enemy, as the record counts them; each ball
            // slung; the wall bounces the table allows and the ball's half
            // size
            ballsBack: r.ballsBack,
            ballsAimed: r.ballsAimed,
            ballBackHits: r.ballBackHits,
            balls: Object.keys(balls).map(id => Object.assign({ id: id }, balls[id])),
            ballBounces: Balance.ball.bounces,
            ballRadius: Balance.ball.size / 2,
            crushBlows: crushBlows,
            crushed: r.crushed,
            heavySwings: heavySwings,
            guardBreaks: guardBreaks,
            whirlwinds: r.whirlwinds,
            whirlHits: r.whirlHits,
            whirlsStarted: whirlsStarted,
            // The stuns (Balance.stun), the enemies they froze and the
            // wind-ups they ended, as the game's record counts them
            stuns: r.stuns,
            stunFrozen: r.stunFrozen,
            stunInterrupted: r.stunInterrupted,
            stunFreeze: Balance.stun.freeze,
            // The bolts (Balance.bolt) let loose and the ones that hit, as
            // the game's record counts them, each one's end, its reach,
            // its speed, the sword's reach and the room's half width
            bolts: r.bolts,
            boltHits: r.boltHits,
            boltEnds: boltEnds,
            boltReach: Balance.bolt.reach,
            boltSpeed: Balance.bolt.speed,
            swordReach: Balance.knight.attackRange,
            roomHalf: 15 * game.cellSize / 2,
            kills: r.kills,
            // Kill chains of two links or more, and the longest's links
            chains: r.chains,
            longestChain: r.longestChain,
            // The blows the chain's bonus made stronger, the points it
            // added and its peak (Balance.chain.bonusShare, issue #321)
            chainBlows: r.chainBlows,
            chainExtra: r.chainExtra,
            chainPeak: round3(r.chainPeak),
            deaths: r.deaths,
            clearSeconds: r.clearSeconds >= 0 ? round3(r.clearSeconds) : null,
            knightHp: p ? p.hp : 0,
            knightMana: p ? round3(p.mana) : 0,
            openings: foes.reduce((n, f) => n + f.openings, 0),
            cancelledCharges: cancelledCharges,
            engagedSeconds: round3(engagedSeconds),
            killGaps: gaps,
            // The Hollow Warden's fight (Balance.boss): when its phase 2
            // began, the adds it called, the zones opened and the ones that
            // hurt the knight
            boss: game.bossFight.stage === "" ? null : {
                stage: game.bossFight.stage, phase2At: _phase2At, adds: game.bossFight.addsCalled,
                zones: game.bossFight.zonesOpened, zoneHits: game.bossFight.zoneHits
            },
            // The person's answers and misses by kind, and the fastest it
            // answered anything, from its start (Balance.pacing.person)
            person: answer !== "person" ? null : {
                reaction: Balance.pacing.person.reaction, miss: Balance.pacing.person.miss,
                answers: personAnswers, missed: personMissed,
                fastest: personFastest < 0 ? null : round3(personFastest),
                // Its special (issue #344): which, its presses, the ones
                // that went off, and its presses one window early or late
                special: personSpecial === "" ? null : Object.assign({ id: personSpecial,
                    mana: game.player ? game.player.specialMana : 0 }, specialUse)
            },
            // What hurt the knight, by cause: hits and HP (issue #344),
            // and how often its mana ran dry
            hurtBy: hurtBy,
            knightStartHp: _knightStartHp,
            knightHealed: knightHealed,
            manaDry: manaDry,
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
    property var _phase2At: null
    readonly property var calm: ["patrol", "idle"]
    function track(dt) {
        let t = now(), engaged = false
        for (let e of game.enemies)
            if (alive(e) && !_foes.some(f => f.ref === e)) follow(e)
        if (_phase2At === null && game.bossFight.phase === 2) _phase2At = t
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
            trackFrozen(f, e, t)
            f.lastState = e.aiState
            f.lastStance = e.stance
        }
        if (engaged) engagedSeconds += dt
    }

    // A frozen span (issue #318): it begins on the step the enemy is seen
    // frozen, reckoned from the stun that froze it last, and ends on the
    // step it is seen thawed. How far its centre moved meanwhile
    function trackFrozen(f, e, t) {
        if (e.aiState === "frozen") {
            if (!f.frozen)
                f.frozen = { stunAt: f.lastStunAt, x: e.xWu, y: e.yWu, moved: 0 }
            f.frozen.stunAt = f.lastStunAt
            f.frozen.moved = round3(Math.max(f.frozen.moved, Math.hypot(e.xWu - f.frozen.x, e.yWu - f.frozen.y)))
        } else if (f.frozen) {
            f.frozenSpans.push(Object.assign({}, f.frozen, {
                thawAt: t, lasted: f.frozen.stunAt === null ? null : round3(t - f.frozen.stunAt),
                into: e.aiState }))
            f.frozen = null
        }
    }

    // A charge ended without its release: a hit, the shield or a dash
    // cancelled it while the button was held (Player._cancelCharge)
    property int cancelledCharges: 0
    property string _chargeSeen: ""
    function trackCharge(p) {
        if ((_chargeSeen === "charging" || _chargeSeen === "full") && p._charge === "spent")
            cancelledCharges++
    }

    // ---- what hurt the knight (issue #344) ----
    // Per cause the hits that cost the knight HP and the HP: a zone of
    // the Warden's, a shot, a metal ball, or the blow of the enemy that
    // struck - its type, "lead" for a room's lead -, as hurtCause names
    // it the moment the knight is hurt or blocks. Mana ran dry each time
    // it fell below a block's cost, the shield then soon down; the HP it
    // got back meanwhile is knightHealed
    property var hurtBy: ({})
    property real _knightHp: -1
    property real _knightStartHp: -1
    property real knightHealed: 0
    property int _zoneHitsSeen: 0
    property string _hurtCause: ""
    property int manaDry: 0
    property bool _dry: false
    function trackHurt(p) {
        let zone = game.bossFight.zoneHits > _zoneHitsSeen
        _zoneHitsSeen = game.bossFight.zoneHits
        let dry = p.mana < p.blockMana
        if (dry && !_dry) manaDry++
        _dry = dry
        if (_knightStartHp < 0) _knightStartHp = p.hp
        let lost = _knightHp < 0 ? 0 : _knightHp - p.hp
        _knightHp = p.hp
        let cause = zone ? "zone" : _hurtCause !== "" ? _hurtCause : "unknown"
        _hurtCause = ""
        if (lost < 0) knightHealed -= lost
        if (lost <= 0) return
        let h = hurtBy[cause] || { hits: 0, hp: 0 }
        h.hits++
        h.hp += lost
        hurtBy[cause] = h
    }
    // What is hurting the knight now: a shot or a ball close by, else the
    // blow of the nearest enemy
    function hurtCause(p) {
        let best = "", bestD = 2.5
        for (let o of game.room.children) {
            if (!(o.objectName === "projectile" || o.objectName === "ball") || o.destroyed !== false || o.back)
                continue
            let d = distTo(p, o.xWu, o.yWu)
            if (d < bestD) { bestD = d; best = o.objectName === "ball" ? "ball" : "shot" }
        }
        if (best !== "") return best
        let near = null, nearD = 1e9
        for (let e of game.enemies.filter(alive)) {
            let d = distTo(p, ex(e), ey(e))
            if (d < nearD) { nearD = d; near = e }
        }
        if (!near) return "unknown"
        return near.enemyType + (near.lead && !near.boss ? " lead" : "") + " blow"
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

    // ---- the Warden's room, tried as in the dojo (run_reload.py) ----
    // The bossroom scenario stands: the knight at the Warden's door, the
    // Warden asleep in its room (issue #274)
    function bossRoomReady() {
        return game.player !== null && game.bossFight.stage === "waiting"
            && game.enemies.some(e => alive(e) && e.boss)
    }
    // Whether item it is on screen: its centre within the game's view
    function onScreen(it) {
        let c = it.mapToItem(game, it.width / 2, it.height / 2)
        return c.x >= 0 && c.x <= game.width && c.y >= 0 && c.y <= game.height
    }
    // What a reload into the Warden's room shows: the room's way in and
    // the Warden on screen, the Warden's HP and tempo against the table
    // (Game.wardenHp, wardenTempo) for its appearance, as JSON
    function tryBossRoom() {
        let f = game.bossFight
        let w = game.enemies.find(e => alive(e) && e.boss)
        let g = f.gates.find(x => !x.exit)
        let n = game.bossAppearance(game.depth)
        return JSON.stringify({depth: game.depth, stage: f.stage, dormant: w.dormant,
                               gateOnScreen: onScreen(g), wardenOnScreen: onScreen(w),
                               hp: w.maxHp, wantHp: game.wardenHp(n, game.partyKnights, game.danger),
                               tempo: w.tempo, wantTempo: game.wardenTempo(n), tableHp: Balance.boss.hp})
    }
    // The sleeping Warden of the bossroom scenario winds up and strikes
    // once - its aiState set, as a remote screen's is - and the sound log
    // says what that played (issue #287): its rows and the table's
    // boss.toll, as JSON. The Warden stands as it stood after
    function tryToll() {
        let w = game.enemies.find(e => alive(e) && e.boss)
        let was = w.aiState, logged = game.logSounds
        game.logSounds = true
        game.clearSoundLog()
        w.aiState = "telegraph"
        w.aiState = "lunge"
        w.aiState = was
        let rows = game.soundLog.map(s => ({cue: s.cue, what: s.what, pitch: s.pitch}))
        game.logSounds = logged
        return JSON.stringify({rows: rows, windUp: Balance.boss.toll.windUp, strike: Balance.boss.toll.strike})
    }

    // ---- a lead's stance, tried as in the dojo (run_reload.py) ----
    // The duel room stands: the knight and a lead
    function duelReady() {
        return game.player !== null && game.fightRoomActive === true
            && game.enemies.some(e => alive(e) && e.lead)
    }
    // The lead's type, its HP, the HP the table gives it and its type's
    // leadHp (issue #288), as JSON
    function tryDuelLead() {
        Clayground.paused = true
        let standing = game.enemies.filter(alive)
        let lead = standing.find(e => e.lead)
        return JSON.stringify({type: lead.enemyType, hp: lead.maxHp, tier: lead.tier,
                               leads: standing.filter(e => e.lead).length, standing: standing.length,
                               want: game.enemyHp(lead.enemyType, lead.tier, game.partyKnights, game.danger),
                               leadHp: Balance.enemy[lead.enemyType].leadHp})
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

    // ---- the bolt, shot by hand (issue #319) ----
    // In the flow room after begin(): the pilot rests, every enemy halted
    // in a corner, the knight at the room's centre, aiming right. Three
    // bolts: at an enemy 5 wu off, its damage and the HP it took; nothing
    // in line, an enemy just past the reach, how far the bolt flew and the
    // HP the enemy lost; from 5 wu before the room's right wall, where it
    // ended. Each as its end (boltEnded) with the numbers to hold it to,
    // as JSON
    function tryBolt() {
        Clayground.paused = true
        _rng = null
        let p = game.player, cx = game._fightRoomCx, cy = game._fightRoomCy
        let half = 15 * game.cellSize / 2
        let foes = game.enemies.filter(alive)
        for (let e of foes) e.halt()
        p.special = "bolt"
        p.maxMana = 1000
        p.maxHp = 100000
        p.hp = 100000
        let put = (o, x, y) => {
            o.xWu = x - o.widthWu / 2
            o.yWu = y + o.heightWu / 2
            if (o.body) o.body.linearVelocity = Qt.point(0, 0)
        }
        let aside = () => foes.forEach((e, i) => put(e, cx - half + 2, cy + half - 2 - i * 1.2))
        let shoot = () => {
            for (let i = 0; i < 2; i++) Clayground.physicsStep(1)
            p.mana = p.maxMana
            p.facingAngle = 0
            let n0 = boltEnds.length
            let went = p.unleash()
            let k = 0
            while (went && boltEnds.length === n0 && k < 200) {
                Clayground.physicsStep(1)
                k++
            }
            return Object.assign({ went: went, steps: k }, boltEnds.length > n0 ? boltEnds[boltEnds.length - 1] : {})
        }
        let a = foes.find(e => !e.lead && e.enemyType !== "guardian")
        aside()
        put(p, cx, cy)
        put(a, cx + 5, cy)
        let hp = a.hp
        let hit = shoot()
        hit.lost = hp - a.hp
        hit.want = Math.max(Balance.minDamage, Math.round(p.atk * Balance.bolt.damage) - a.def)
        hit.gap = 5
        a.hp = a.maxHp
        put(a, cx + Balance.bolt.reach + 1.2, cy)
        hp = a.hp
        let far = shoot()
        far.lost = hp - a.hp
        far.enemyAt = Balance.bolt.reach + 1.2
        aside()
        put(p, cx + half - 5, cy)
        let wall = shoot()
        wall.toWall = 5
        return JSON.stringify({ hit: hit, far: far, wall: wall, reach: Balance.bolt.reach,
                                speed: Balance.bolt.speed, swordReach: Balance.knight.attackRange,
                                roomHalf: half, atk: p.atk })
    }

    // ---- a metal ball, slung by hand (issue #322) ----
    // In the ball duel after begin(): the pilot rests, the slinger halted,
    // the knight at the room's centre in a long grace, so the ball passes
    // it. One ball from 6 wu left of and 3 below the centre, at 0.8, 0.6,
    // fast enough to meet five walls in its time: its bounces and its
    // fall as the bench saw them (balls), with what to hold them to, as
    // JSON
    function tryBall() {
        Clayground.paused = true
        _rng = null
        let p = game.player, cx = game._fightRoomCx, cy = game._fightRoomCy
        let half = 15 * game.cellSize / 2
        for (let e of game.enemies.filter(alive)) e.halt()
        p.maxHp = 100000
        p.hp = 100000
        p.graceLeft = 1e6
        let from = { x: cx - 6, y: cy - 3 }, dir = { x: 0.8, y: 0.6 }
        let b = game.spawnBall(from.x, from.y, dir.x, dir.y, 10)
        let id = b.ballId
        b.speed = 16
        let k = 0
        while (!(balls[id] && balls[id].fell) && k < 1200) {
            Clayground.physicsStep(1)
            k++
        }
        p.graceLeft = 0
        return JSON.stringify({ from: from, dir: dir, speed: 16, centre: { x: cx, y: cy }, roomHalf: half,
                                radius: Balance.ball.size / 2, bounces: Balance.ball.bounces,
                                ball: balls[id] || null, steps: k })
    }

    // ---- the combo, entered by hand (issue #320) ----
    // In the flow room after begin(): the pilot rests, every enemy halted
    // in a corner, the knight at the room's centre. For each special the
    // knight enters the combo with its moves (moveX, moveY) as a pilot
    // walks - away from its aim for comboAway steps, then towards it for
    // comboTowards - and presses the special's button at once, then the
    // same with the button later than Balance.combo.window: the stun at an
    // enemy past the stun's reach and inside the stronger one's, whether
    // it froze; the bolt at an enemy 5 wu off, the damage it took and the
    // bolt's size; the whirlwind with an enemy either side past its reach
    // and inside the stronger one's, the damage they took. As JSON
    readonly property int comboAway: 4
    readonly property int comboTowards: 2
    function tryCombo() {
        Clayground.paused = true
        _rng = null
        let p = game.player, cx = game._fightRoomCx, cy = game._fightRoomCy
        let half = 15 * game.cellSize / 2
        let foes = game.enemies.filter(alive)
        for (let e of foes) e.halt()
        p.maxMana = 1000
        p.maxHp = 100000
        p.hp = 100000
        let put = (o, x, y) => {
            o.xWu = x - o.widthWu / 2
            o.yWu = y + o.heightWu / 2
            if (o.body) o.body.linearVelocity = Qt.point(0, 0)
        }
        let aside = () => foes.forEach((e, i) => { e.halt(); put(e, cx - half + 2, cy + half - 2 - i * 1.2) })
        let small = foes.filter(e => !e.lead && e.enemyType !== "guardian")
        let a = small[0], b = small[1]
        // A step by hand simulates 1/60 s (ClayWorld2d's physicsStep); the
        // world's timeStep before the first one is the running game's last
        // frame, longer on a busy machine, and would wait too few steps
        const step = 1 / 60
        // The knight at the centre facing angle, the combo entered, the
        // button pressed late or not: whether the combo was ready, whether
        // the special was the stronger one and the slowest the knight went
        let fire = (angle, late, before) => {
            aside()
            put(p, cx, cy)
            p.momentum = Balance.momentum.max
            Clayground.physicsStep(2)
            p.facingAngle = angle
            if (before) before()
            let rad = angle * Math.PI / 180
            let fx = Math.cos(rad), fy = -Math.sin(rad)
            let slowest = 1e9
            let walk = (way, n) => {
                p.moveX = fx * way
                p.moveY = fy * way
                for (let i = 0; i < n; i++) {
                    Clayground.physicsStep(1)
                    let v = p.body.linearVelocity
                    slowest = Math.min(slowest, Math.sqrt(v.x * v.x + v.y * v.y))
                }
            }
            walk(-1, comboAway)
            walk(1, comboTowards)
            if (late) walk(1, Math.ceil(Balance.combo.window / step) + 1)
            let ready = p.comboReady()
            p.mana = p.maxMana
            let went = p.unleash()
            return { ready: ready, went: went, strong: went && p.lastStrong, slowest: slowest }
        }
        let wake = e => { e.halted = false; e.target = p }
        let out = { window: Balance.combo.window, away: comboAway, towards: comboTowards,
                    moveSpeed: Balance.knight.moveSpeed, atk: p.atk }
        // The stun, aiming up
        p.special = "stun"
        let gap = (Balance.stun.reach + Balance.combo.stun.reach) / 2
        for (let late of [false, true]) {
            let r = fire(90, late, () => { put(a, p.xWu + p.widthWu / 2 + gap, p.yWu - p.heightWu / 2); wake(a) })
            r.frozen = a.aiState === "frozen"
            r.gap = gap
            out[late ? "stunLate" : "stun"] = r
            a._attackTimer = 0
            Clayground.physicsStep(2)
        }
        // The bolt, aiming right
        p.special = "bolt"
        for (let late of [false, true]) {
            a.hp = 100000
            let r = fire(0, late, () => put(a, p.xWu + p.widthWu / 2 + 5, p.yWu - p.heightWu / 2))
            let bolt = null
            for (let id in game._boltById) if (game._boltById[id].own) bolt = game._boltById[id]
            r.size = bolt ? bolt.widthWu : 0
            let k = 0
            while (bolt && !bolt.destroyed && k < 120) { Clayground.physicsStep(1); k++ }
            r.lost = 100000 - a.hp
            r.want = Math.max(Balance.minDamage, Math.round(p.atk * (late ? Balance.bolt.damage
                                                                         : Balance.combo.bolt.damage)) - a.def)
            out[late ? "boltLate" : "bolt"] = r
        }
        // The whirlwind, aiming up, an enemy either side as it spins
        p.special = "whirlwind"
        let side = (Balance.knight.whirlReach + Balance.combo.whirlwind.reach) / 2
        for (let late of [false, true]) {
            a.hp = 100000; b.hp = 100000
            let beside = () => {
                let c = { x: p.xWu + p.widthWu / 2, y: p.yWu - p.heightWu / 2 }
                put(a, c.x + side, c.y)
                put(b, c.x - side, c.y)
            }
            let r = fire(90, late, null)
            let n = 0
            while (p.isWhirling && n < 120) { beside(); Clayground.physicsStep(1); n++ }
            p.moveX = 0
            p.moveY = 0
            r.seconds = Math.round(n * step * 1000) / 1000
            r.lost = [100000 - a.hp, 100000 - b.hp]
            r.want = Math.max(Balance.minDamage, Math.floor(p.atk * Balance.combo.whirlwind.swing) - a.def)
            r.side = side
            out[late ? "whirlLate" : "whirl"] = r
            Clayground.physicsStep(30)
        }
        aside()
        return JSON.stringify(out)
    }

    // ---- the scripted knight ----
    // Each attack an enemy winds up gets one plan: "parry" waits for the
    // parry window and swings into it, "block" raises the shield towards
    // it, "perfect" keeps the shield down until the lunge is perfectLead
    // steps from landing and raises it then. The answer "mix" rolls the
    // plan from the seed between parry and block; "block", "parry" and
    // "perfect" always pick that one; a crushing blow (aiState "crush") gets
    // the same plans, and a parry finds no window. A shot is always
    // blocked, by "perfect" perfectly, which sends it back. "heavy"
    // meets attacks as "mix" does; it answers a guardian's shield with a
    // charged heavy swing instead of a shield dash: it holds the left
    // button on its way in and lets go once the charge is full and the
    // guardian in the heavy swing's reach. "whirlwind" fights as "mix"
    // does and earns momentum by it; with all of it (Balance.momentum) and
    // an enemy within whirlFrom it whirls at that enemy (Q, unleash).
    // "stun" fights as "mix" does with the stun for its special (issue
    // #318): it stuns (Q, unleash) when a weak or normal enemy not frozen
    // stands within the stun's reach, and when a lead winds up within it
    // stunRest seconds or more after its last stun - the wind-ups between
    // it meets as "mix" does, so the duel goes on. "bolt" plays as
    // "masher" does with the bolt for its special and the knight's own
    // mana (issue #319): with an enemy out of the sword's reach and within
    // boltFrom of the bolt's reach it lets a bolt loose at it (Q,
    // unleash), boltRest seconds or more after its last, whenever the
    // mana is there - a masher who found a way to hurt from afar.
    //
    // The pacing pilots (Balance.pacing): "charge" never raises the shield;
    // it holds a full charge, walks at the nearest enemy and lets go once
    // it is in the heavy swing's reach, then presses again. "masher" never
    // raises the shield either: it walks at the nearest enemy and clicks on
    // every step it can swing. "skilled" parries every lunge and
    // perfect-blocks every crushing blow and every shot, sending it back -
    // walking on at the nearest enemy meanwhile -, breaks a
    // guardian's guard with the shield dash, and swings only into an
    // opening: an enemy within reach that is not winding up or lunging.
    // "person" plays as "skilled" with a person's reaction and misses
    // (below, issue #315); given a special, it fires that one too (issue
    // #344)
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
    // The last stun, on the bench's clock, and the rest before a lead's
    // wind-up is stunned again
    property real _stunAt: -1000
    readonly property real stunRest: 3
    function stunNow(p, foes) {
        if (p.isDashing || p.special !== "stun") return false
        let cx = p.xWu + p.widthWu / 2, cy = p.yWu - p.heightWu / 2
        let near = e => {
            let dx = e.xWu + e.widthWu / 2 - cx, dy = e.yWu - e.heightWu / 2 - cy
            let r = Balance.stun.reach * 0.9 + (e.bulk || 0)
            return dx * dx + dy * dy <= r * r
        }
        let small = foes.some(e => !e.lead && e.aiState !== "frozen" && near(e))
        let lead = now() - _stunAt >= stunRest && foes.some(e => e.lead && near(e)
            && (e.aiState === "telegraph" || e.aiState === "crush" || e.aiState === "shoot"))
        if (!small && !lead) return false
        letGo(p)
        if (!p.unleash()) return false
        _stunAt = now()
        return true
    }

    // The last bolt, on the bench's clock, the rest before the next and
    // the share of the bolt's reach the pilot shoots from
    property real _boltAt: -1000
    readonly property real boltRest: 0.3
    readonly property real boltFrom: 0.9
    function boltNow(p, near) {
        if (p.isDashing || p.special !== "bolt" || now() - _boltAt < boltRest) return false
        if (near.d <= p.attackRange || near.d > Balance.bolt.reach * boltFrom) return false
        if (p.mana < p.specialMana) return false
        face(p, near.e)
        if (!p.unleash()) return false
        _boltAt = now()
        return true
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
                bench.trackHurt(game.player)
            }
            bench.countCrushes()
            bench.perceive()
            if (bench.answer === "charge") bench.pilotCharge()
            else if (bench.answer === "masher" || bench.answer === "bolt") bench.pilotMasher()
            else if (bench.answer === "skilled") bench.pilotSkilled(game.physics.timeStep)
            else if (bench.answer === "person") bench.pilotPerson(game.physics.timeStep)
            else bench.pilot(game.physics.timeStep)
            if (game.player) bench._chargeSeen = game.player._charge
        }
    }

    function alive(e) { return e && e.destroyed === false }
    // Where an enemy is reckoned from: a bigger one (the Warden) from the
    // corner a common one at its centre would have (Enemy.aimXWu)
    function ex(e) { return e.aimXWu !== undefined ? e.aimXWu : e.xWu }
    function ey(e) { return e.aimYWu !== undefined ? e.aimYWu : e.yWu }
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
        let target = foes[0], targetDist = distTo(p, ex(target), ey(target))
        for (let e of foes) {
            let d = distTo(p, ex(e), ey(e))
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
            let d = distTo(p, ex(e), ey(e))
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
    // or, with towards, walking at that enemy behind it. With perfect the
    // shield stays down until the shot is perfectFrom wu off, centre to
    // centre, and comes up then: a perfect block that sends it back
    // (Balance.projectile), the shield down again soon after, ready for the
    // next. A shot sent back is none to answer. Returns whether the knight
    // is answering one
    readonly property real perfectFrom: 0.9
    // A slinger's metal ball (issue #322) is a shot too while it comes at
    // the knight: not fallen, none a shield turned, flying towards it
    function incoming(p, o) {
        if (o.destroyed !== false || o.back) return false
        if (o.objectName === "projectile") return true
        if (o.objectName !== "ball" || o.fallen) return false
        let c = { x: p.xWu + p.widthWu / 2, y: p.yWu - p.heightWu / 2 }
        return o.dirX * (c.x - o.centreX) + o.dirY * (c.y - o.centreY) > 0
    }
    // Facing a ball with the shield so a perfect block sends it at aim
    // (Balance.ball): as near aim's way as the shield's arc still meets
    // the ball, a margin inside it; facing the ball itself without aim
    readonly property real aimMargin: 15
    function faceShot(p, o, aim) {
        face(p, o)
        if (!aim || o.objectName !== "ball") return
        let toBall = p.facingAngle
        let px = p.xWu + p.widthWu / 2, py = p.yWu - p.heightWu / 2
        let toAim = Math.atan2(ey(aim) - aim.heightWu / 2 + (aim.bulk || 0) - py,
                               ex(aim) + aim.widthWu / 2 - (aim.bulk || 0) - px) * 180 / Math.PI
        let d = ((toAim - toBall) % 360 + 540) % 360 - 180
        let most = Balance.knight.shieldArc - aimMargin
        p.facingAngle = toBall + Math.max(-most, Math.min(most, d))
    }
    function answerShot(p, dt, towards, perfect, aim) {
        let shot = null, shotDist = 1e9
        for (let o of game.room.children) {
            if (!(o.objectName === "projectile" || o.objectName === "ball") || !incoming(p, o)) continue
            let d = distTo(p, o.xWu, o.yWu)
            if (d < 3 && d < shotDist) { shot = o; shotDist = d }
        }
        if (shot) {
            letGo(p)
            faceShot(p, shot, perfect === true ? aim : null)
            let cd = Math.hypot(shot.xWu + shot.widthWu / 2 - p.xWu - p.widthWu / 2,
                                shot.yWu - shot.heightWu / 2 - p.yWu + p.heightWu / 2)
            if (perfect === true && !p.isBlocking && cd > perfectFrom) {
                if (towards) moveTowards(p, towards.xWu, towards.yWu, 1)
                else stand(p)
                return true
            }
            _blockLeft = perfect === true ? 0.1 : 0.3
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
    // A zone of the Warden's (BossFight) warning under the knight: it
    // walks straight out of it, away from its centre, the shield and the
    // button let go. Returns whether it is on its way out
    // seen, when given, says which zones the knight has seen: the others
    // it stands in as if they were not there
    function leaveZone(p, seen) {
        let f = game.bossFight, t = f.now(), z = Balance.boss.zone
        let cx = p.xWu + p.widthWu / 2, cy = p.yWu - p.heightWu / 2
        for (let q of f.zones) {
            if (t >= q.at) continue
            if (seen && !seen(q)) continue
            let dx = cx - q.x, dy = cy - q.y, d = Math.sqrt(dx * dx + dy * dy)
            if (d > z.radius + 0.6) continue
            letGo(p)
            p.isBlocking = false
            if (d < 0.01) { dx = 1; dy = 0; d = 1 }
            p.moveX = dx / d
            p.moveY = -dy / d
            return true
        }
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
        if (answer === "stun" && stunNow(p, foes)) return

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

        // 2. A spitter's shot on its way: shield up towards it a moment,
        // "perfect" just before it meets the knight
        if (answerShot(p, dt, null, answer === "perfect", nearest(p, foes).e)) return

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
        // "bolt": a bolt at an enemy out of the sword's reach
        if (answer === "bolt" && boltNow(p, near)) return
        p.attack()
    }

    // "skilled": every attack answered, swings only into openings; it
    // steps out of a floor zone of the Warden's while it warns
    function pilotSkilled(dt) {
        let p = game.player
        let foes = foesOrRest(p)
        if (!foes) return
        if (leaveZone(p)) return
        let threat = answerThreat(p, foes, e => e.aiState === "crush" || e.crushing ? "perfect" : "parry")
        if (threat) {
            threat.answer()
            return
        }
        let near = nearest(p, foes), target = near.e
        if (answerShot(p, dt, near.d > 1.3 ? target : null, true, target)) return
        letGo(p)
        face(p, target)
        if (shieldDash(p, target, near.d)) return
        if (p.isDashing) return
        if (near.d > 1.3) moveTowards(p, target.xWu, target.yWu, 1)
        else stand(p)
        if (near.d <= p.attackRange * 0.9 && !winding(target)) p.attack()
    }

    // ---- "person": a person's reaction and misses (issue #315) ----
    // It plays as "skilled" does, but sees an attack, a shot or a zone
    // only Balance.pacing.person.reaction seconds after it began: an
    // enemy's wind-up begun (or a lunge begun without one), a shot fired,
    // a zone warning. Until then it does what it did, and swings at an
    // enemy that winds up as at any other; once an attack is over it still
    // waits that long before it swings at that enemy. Once it has seen an
    // attack it times its press to the window as "skilled" does - the
    // ring a player reads -, but misses Balance.pacing.person.miss of its
    // parries and perfect blocks, shots' included: one in every five
    // answers for 0.2, in turn, the first miss's place picked by the seed,
    // the room and its danger, so the fights of one run miss on different
    // answers (a roll per answer would leave a short fight to luck). A miss is by
    // one window early (a swing begun before the parry window, the shield
    // up before the perfect block's - the enemy's window, a lead's wider at
    // its duel pace, Balance.pace) or late (no press before the blow
    // lands), as the seed rolls. A shot began with its spitter's wind-up
    // (aiState "shoot"), which the person sees, not with its flight. The
    // times are the physics clock's, the game's own: a slow motion gives
    // it no more.
    readonly property real reaction: Balance.pacing.person.reaction
    readonly property real missShare: Balance.pacing.person.miss
    // Per enemy the attack it is in: {n, at, endedAt, last}, its count,
    // when it began, when the last one ended and the state it was in
    property var _attacks: new Map()
    // Per enemy the plan for its attack: {n, kind, miss, early, pressed}
    property var _personPlans: new Map()
    // When each shot (by its object) and each zone (by its id) was first seen
    property var _shotsSeen: new Map()
    property var _zonesSeen: new Map()
    // Answers planned and missed by kind, and the shortest time from an
    // attack's, a shot's or a zone's start to the person's first answer
    property var personAnswers: ({ parry: 0, perfect: 0, shot: 0 })
    property var personMissed: ({ parry: 0, perfect: 0, shot: 0 })
    property real personFastest: -1
    // Answers so far, and where in the share's turn the first miss lies
    property int _answerCount: 0
    property real _missPhase: 0
    // Where in the share's turn the first miss lies, from 0 to 1: the
    // seed's, the room's and the danger's own, so every fight of a pacing
    // run, all on one seed, has its misses on answers of its own
    function missPhaseOf(s, r, d) {
        let rooms = ["mixed", "flow", "duel", "guardianduel", "spitterduel", "boss", "ballduel"]
        return game.createRng(game.deriveSeed(s, rooms.indexOf(r) * 1000 + Math.round(d * 100)))()
    }
    // Whether the next answer is a miss, and if so whether early
    function rollMiss() {
        let n = _answerCount++
        let miss = Math.floor((n + 1) * missShare + _missPhase) > Math.floor(n * missShare + _missPhase)
        return { miss: miss, early: _rng() < 0.5 }
    }
    readonly property var windUps: ["telegraph", "crush"]

    // What there is to see on this step, with when it began
    function perceive() {
        if (answer !== "person") return
        let t = now()
        for (let e of game.enemies) {
            if (!alive(e)) { _attacks.delete(e); continue }
            let a = _attacks.get(e)
            if (!a) { a = { n: 0, at: -1, endedAt: -1e9, shotAt: -1, last: e.aiState }; _attacks.set(e, a) }
            let s = e.aiState
            let begun = windUps.indexOf(s) >= 0 ? windUps.indexOf(a.last) < 0
                      : s === "lunge" && a.last !== "lunge" && windUps.indexOf(a.last) < 0
            if (begun) { a.n++; a.at = t }
            if (s === "shoot" && a.last !== "shoot") a.shotAt = t
            if (!winding(e) && winding({ aiState: a.last })) a.endedAt = t
            a.last = s
        }
        for (let o of game.room.children)
            if ((o.objectName === "projectile" || o.objectName === "ball") && o.destroyed === false
                    && !o.back && !_shotsSeen.has(o))
                _shotsSeen.set(o, shotBegan(o, t))
        for (let [o] of Array.from(_shotsSeen))
            if (o.destroyed !== false) _shotsSeen.delete(o)
        if (game.bossFight.stage !== "")
            for (let q of game.bossFight.zones)
                if (!_zonesSeen.has(q.id)) _zonesSeen.set(q.id, t)
    }
    // When shot o, first seen at t, began: the wind-up of the spitter (or
    // the slinger, a ball) it left, the nearest one whose wind-up began
    // within a second, else t
    function shotBegan(o, t) {
        let at = t, best = 1e9
        for (let e of game.enemies) {
            if (!alive(e) || !e.ranged) continue
            let a = _attacks.get(e)
            if (!a || a.shotAt < 0 || t - a.shotAt > 1) continue
            let d = Math.hypot(ex(e) - o.xWu, ey(e) - o.yWu)
            if (d < best) { best = d; at = Math.min(t, a.shotAt) }
        }
        return at
    }
    // Whether something that began at at has been seen by now; the first
    // answer to it counts towards the fastest
    function seenSince(at) { return at >= 0 && now() - at >= reaction - 1e-6 }
    function answered(at) {
        let r = now() - at
        if (personFastest < 0 || r < personFastest) personFastest = r
    }
    // Whether the person takes enemy e to be attacking: an attack it has
    // seen, or one that ended less than its reaction ago
    function seemsWinding(e) {
        let a = _attacks.get(e)
        if (!a) return false
        return winding(e) ? seenSince(a.at) : now() - a.endedAt < reaction - 1e-6
    }
    // A plan for enemy e's attack, rolled once as the person sees it
    function personPlan(e) {
        let a = _attacks.get(e), plan = _personPlans.get(e)
        if (plan && plan.n === a.n) return plan
        let kind = e.aiState === "crush" || e.crushing ? "perfect" : "parry"
        let m = rollMiss()
        plan = { n: a.n, kind: kind, miss: m.miss, early: m.early, pressed: false }
        _personPlans.set(e, plan)
        personAnswers[kind]++
        if (m.miss) personMissed[kind]++
        answered(a.at)
        return plan
    }
    // The nearest attack within reach the person has seen, as answerThreat
    function personThreat(p, foes) {
        let threat = null, threatDist = 1e9
        for (let e of foes) {
            if (e.enemyType === "spitter" || !winding(e)) continue
            let a = _attacks.get(e)
            if (!a || !seenSince(a.at)) continue
            let d = distTo(p, ex(e), ey(e))
            if (d < 3.5 && d < threatDist) { threat = e; threatDist = d }
        }
        return threat ? { e: threat, d: threatDist } : null
    }
    // The physics steps until enemy e's parry window opens, -1 when no
    // lunge of its is coming
    function toWindow(e) {
        let pf = e.parryFrames
        if (e.aiState === "lunge") return e._lungeSteps - pf
        if (e.aiState === "telegraph")
            return Math.ceil(e._attackTimer * 60 - 1e-6) + e.lungeStepCount(1 / 60) - pf
        return -1
    }
    // A window is the enemy's own: a room's lead's are wider at a slow
    // duel pace (Balance.pace, issue #361), and one of its windows early
    // is that much early
    function answerPerson(p, threat) {
        let e = threat.e, plan = personPlan(e)
        letGo(p)
        face(p, e)
        stand(p)
        let pf = e.parryFrames
        if (plan.kind === "parry") {
            p.isBlocking = false
            if (!plan.miss) {
                if (e.parryWindow && threat.d <= p.attackRange) p.attack()
            } else if (plan.early && !plan.pressed && toWindow(e) > 0 && toWindow(e) <= pf
                       && threat.d <= p.attackRange) {
                // One window early: the swing is under way before it opens
                p.attack()
                plan.pressed = true
            }
            return
        }
        // A perfect block: perfectLead steps before the blow lands, one
        // window earlier (an ordinary block) or not before it lands
        let lead = !plan.miss ? perfectLead
                 : plan.early ? perfectLead + e.perfectFrames : -1
        p.isBlocking = lead >= 0 && e.aiState === "lunge" && e._lungeSteps <= lead
    }
    // A shot on its way that the person has seen, as answerShot with
    // perfect: a perfect block, one window early (the shield up that much
    // farther off: an ordinary block) or none (it lets the shot hit).
    // Returns whether the knight is answering one
    property var _shotPlans: new Map()
    function personShot(p, dt, towards, aim) {
        let shot = null, shotDist = 1e9
        for (let o of game.room.children) {
            if (!(o.objectName === "projectile" || o.objectName === "ball") || !incoming(p, o)) continue
            let at = _shotsSeen.has(o) ? _shotsSeen.get(o) : -1
            if (!seenSince(at)) continue
            let d = distTo(p, o.xWu, o.yWu)
            if (d < 3 && d < shotDist) { shot = o; shotDist = d }
        }
        if (shot) {
            let plan = _shotPlans.get(shot)
            if (!plan) {
                plan = rollMiss()
                _shotPlans.set(shot, plan)
                personAnswers.shot++
                if (plan.miss) personMissed.shot++
                answered(_shotsSeen.get(shot))
            }
            if (plan.miss && !plan.early) shot = null
            else {
                letGo(p)
                faceShot(p, shot, aim)
                let cd = Math.hypot(shot.xWu + shot.widthWu / 2 - p.xWu - p.widthWu / 2,
                                    shot.yWu - shot.heightWu / 2 - p.yWu + p.heightWu / 2)
                // One of its shooter's windows early (Projectile, MetalBall)
                let frames = shot.perfectFrames > 0 ? shot.perfectFrames : Balance.knight.perfectBlockFrames
                let from = perfectFrom + (plan.miss ? shot.speed * frames / 60 : 0)
                if (!p.isBlocking && cd > from) {
                    if (towards) moveTowards(p, towards.xWu, towards.yWu, 1)
                    else stand(p)
                    return true
                }
                _blockLeft = 0.1
            }
        }
        for (let [o] of Array.from(_shotPlans))
            if (o.destroyed !== false) _shotPlans.delete(o)
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

    // ---- the person's special (issue #344) ----
    // Given one, the person fires it where the pilot of that special does,
    // with its reaction and misses. A chance for it: for the whirlwind,
    // full momentum and an enemy within whirlFrom (as "whirlwind"); for the
    // stun, a weak or normal enemy not frozen within the stun's reach, or
    // a lead winding up within it stunRest seconds after the last stun (as
    // "stun"); for the bolt, an enemy out of the sword's reach and within
    // boltFrom of the bolt's, boltRest seconds after the last bolt (as
    // "bolt") - each with the mana the special costs, which a person
    // reads off the bar. The person presses no sooner than reaction
    // seconds after the chance began, the chance still there. Each press
    // is an answer in the turn of its misses, a fifth of them for 0.2,
    // rolled as it first looks for a chance: a miss is one window
    // (Balance.knight.perfectBlockFrames steps, as its other misses) early
    // - it takes an enemy as near as the knight walks in a window
    // farther off to be in reach, so it may fire at nothing - or late, a
    // window after it would have pressed, whatever stands then. The stun
    // and the shot it is answering come first: the stun before an attack
    // it has seen, the whirlwind and the bolt only when none is coming.
    // Combos are not entered: its own steps can make one (away from a
    // zone, then at the Warden), so it lets any combo lapse before it
    // presses - the plain special only, and the report counts any that
    // went off stronger
    property var _specialPlan: null
    property real _chanceAt: -1
    property real _pressAt: -1
    property var specialUse: ({ presses: 0, fired: 0, strong: 0, early: 0, late: 0 })
    readonly property real specialWindow: Balance.knight.perfectBlockFrames / 60
    function specialChance(p, foes, slack) {
        if (p.isDashing) return null
        let near = nearest(p, foes)
        if (personSpecial === "whirlwind") {
            if (p.momentum < Balance.momentum.max || p.mana < p.whirlMana) return null
            return near.d <= whirlFrom + slack ? near.e : null
        }
        if (p.mana < p.specialMana) return null
        if (personSpecial === "bolt") {
            if (now() - _boltAt < boltRest) return null
            let far = slack > 0 ? Balance.bolt.reach + slack : Balance.bolt.reach * boltFrom
            return near.d > p.attackRange && near.d <= far ? near.e : null
        }
        let cx = p.xWu + p.widthWu / 2, cy = p.yWu - p.heightWu / 2
        let inReach = e => {
            let dx = e.xWu + e.widthWu / 2 - cx, dy = e.yWu - e.heightWu / 2 - cy
            let r = Balance.stun.reach * 0.9 + (e.bulk || 0) + slack
            return dx * dx + dy * dy <= r * r
        }
        let small = foes.find(e => !e.lead && e.aiState !== "frozen" && inReach(e))
        if (small) return small
        if (now() - _stunAt < stunRest) return null
        return foes.find(e => e.lead && inReach(e)
            && (e.aiState === "telegraph" || e.aiState === "crush" || e.aiState === "shoot")) || null
    }
    // Whether the person pressed its special's button on this step
    function personSpecialNow(p, foes) {
        if (!_specialPlan) _specialPlan = rollMiss()
        let plan = _specialPlan
        let early = plan.miss && plan.early, late = plan.miss && !plan.early
        let target = specialChance(p, foes, early ? Balance.knight.moveSpeed * specialWindow : 0)
        if (_pressAt < 0) {
            if (!target) { _chanceAt = -1; return false }
            if (_chanceAt < 0) _chanceAt = now()
            if (!seenSince(_chanceAt)) return false
            if (late) { _pressAt = now() + specialWindow; return false }
        } else if (now() < _pressAt - 1e-6 || p.isDashing) return false
        if (!target) target = nearest(p, foes).e
        letGo(p)
        p.isBlocking = false
        face(p, target)
        if (personSpecial === "whirlwind") moveTowards(p, target.xWu, target.yWu, 1)
        p.comboAt = -1
        let went = p.unleash()
        specialUse.presses++
        if (went) specialUse.fired++
        if (went && p.lastStrong) specialUse.strong++
        if (early) specialUse.early++
        if (late) specialUse.late++
        personAnswers.special++
        if (plan.miss) personMissed.special++
        answered(_chanceAt)
        if (personSpecial === "stun") _stunAt = now()
        if (personSpecial === "bolt") _boltAt = now()
        _specialPlan = null
        _chanceAt = -1
        _pressAt = -1
        return true
    }

    function pilotPerson(dt) {
        let p = game.player
        let foes = foesOrRest(p)
        if (!foes) return
        if (leaveZone(p, q => {
                let at = _zonesSeen.has(q.id) ? _zonesSeen.get(q.id) : -1
                if (!seenSince(at)) return false
                answered(at)
                return true
            })) return
        if (personSpecial === "stun" && personSpecialNow(p, foes)) return
        let threat = personThreat(p, foes)
        if (threat) {
            answerPerson(p, threat)
            return
        }
        let near = nearest(p, foes), target = near.e
        if (personShot(p, dt, near.d > 1.3 ? target : null, target)) return
        if (personSpecial !== "" && personSpecial !== "stun" && personSpecialNow(p, foes)) return
        letGo(p)
        face(p, target)
        if (shieldDash(p, target, near.d)) return
        if (p.isDashing) return
        if (near.d > 1.3) moveTowards(p, target.xWu, target.yWu, 1)
        else stand(p)
        if (near.d <= p.attackRange * 0.9 && !seemsWinding(target)) p.attack()
    }
}
