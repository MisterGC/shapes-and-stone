// Fight bench - plays the "fight" scenario with a scripted knight and
// reports how the fight went (issue #34).
//
// The game runs paused: run_fightbench.py steps it through the inspector,
// a few physics steps of exactly 1/60 s at a time, so the fight does not
// depend on how fast the machine renders. The pilot below plays the knight
// on every step; what it does depends only on the fight and on its seed.
// The numbers are the game's own fight record (Game.qml).
//
// Driven by run_fightbench.py (clayliveloader --sbx Sandbox.qml), which
// calls begin(seed, answer, depth), steps and reads report().

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
    function applyScenario(name, depth) { game.applyScenario(name, depth) }

    // ---- driver API ----
    property int seed: 0
    property string answer: "mix"
    property int depth: 0
    property int steps: 0
    property var _rng: null

    // Pauses the world and enters the fight room; the driver steps from here.
    // answer is how the knight meets an attack: "mix", "block", "parry",
    // "perfect" or "heavy" (as mix, but it charges at guardians);
    // depth is the depth the fight room is at.
    function begin(s, a, d) {
        Clayground.paused = true
        seed = s
        answer = a === undefined ? "mix" : a
        depth = d === undefined ? 0 : d
        steps = 0
        _rng = game.createRng(s)
        _plans = new Map()
        _blockLeft = 0
        _held = false
        heavySwings = 0
        guardBreaks = 0
        _staggered = new Set()
        game.applyScenario("fight", depth)
        if (game.player) game.player.acted.connect(a => { if (a === "heavy") bench.heavySwings++ })
        return game.player !== null
    }

    readonly property var record: game.fightRecord
    readonly property bool cleared: record.clearSeconds >= 0
    readonly property bool fallen: game.fallen
    readonly property bool done: cleared || fallen

    function report() {
        let r = record
        let p = game.player
        return {
            seed: seed,
            answer: answer,
            depth: game.depth,
            outcome: cleared ? "cleared" : fallen ? "fallen" : "running",
            steps: steps,
            seconds: round3(r.seconds),
            damageDealt: r.damageDealt,
            damageTaken: r.damageTaken,
            parries: r.parries,
            blocks: r.blocks,
            perfectBlocks: r.perfectBlocks,
            heavySwings: heavySwings,
            guardBreaks: guardBreaks,
            kills: r.kills,
            deaths: r.deaths,
            clearSeconds: r.clearSeconds >= 0 ? round3(r.clearSeconds) : null,
            knightHp: p ? p.hp : 0,
            knightMana: p ? round3(p.mana) : 0
        }
    }
    function round3(v) { return Math.round(v * 1000) / 1000 }

    // ---- the charge, tried as in the dojo (run_reload.py) ----
    // The fight room stands: the knight and its grunt, guardian and spitter
    function fightReady() {
        return game.player !== null && game.fightRoomActive === true
            && ["grunt", "guardian", "spitter"].every(t => game.enemies.some(
                e => e.enemyType === t && alive(e)))
    }
    // Holds the left button until the charge is full, counting the physics
    // steps, then lets go at the guardian, which stands in front of the
    // knight and faces it. The enemies stand still meanwhile. Returns the
    // steps, whether the guardian staggered and the HP it lost, as JSON
    function tryCharge() {
        Clayground.paused = true
        let p = game.player
        let foes = game.enemies.filter(alive)
        for (let e of foes) e.halt()
        let gd = foes.find(e => e.enemyType === "guardian")
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

    // ---- the scripted knight ----
    // Each attack an enemy winds up gets one plan: "parry" waits for the
    // parry window and swings into it, "block" raises the shield towards
    // it, "perfect" keeps the shield down until the lunge is perfectLead
    // steps from landing and raises it then. The answer "mix" rolls the
    // plan from the seed between parry and block; "block", "parry" and
    // "perfect" always pick that one. A shot is always blocked. "heavy"
    // meets attacks as "mix" does; it answers a guardian's shield with a
    // charged heavy swing instead of a shield dash: it holds the left
    // button on its way in and lets go once the charge is full and the
    // guardian in the heavy swing's reach.
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
    function countGuardBreaks(p) {
        for (let e of game.enemies.filter(alive)) {
            if (e.enemyType !== "guardian") continue
            let now = e.aiState === "stagger"
            if (now && !_staggered.has(e) && p.isHeavy) guardBreaks++
            if (now) _staggered.add(e); else _staggered.delete(e)
        }
    }
    function heavyReach(p) { return p.attackRange * Balance.knight.heavyRange * 0.9 }
    function letGo(p) {
        if (_held) p.dropSwing()
        _held = false
    }

    Connections {
        target: game.physics
        enabled: game.player !== null && bench._rng !== null
        function onStepped() {
            bench.steps++
            if (game.player) bench.countGuardBreaks(game.player)
            bench.pilot(game.physics.timeStep)
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

    function pilot(dt) {
        let p = game.player
        if (!p || p.fallen || done) {
            if (p) { stand(p); letGo(p); p.isBlocking = false }
            return
        }
        let foes = game.enemies.filter(alive)
        if (foes.length === 0) { stand(p); letGo(p); p.isBlocking = false; return }

        // Forget plans of attacks that are over
        for (let e of Array.from(_plans.keys()))
            if (!alive(e) || (e.aiState !== "telegraph" && e.aiState !== "lunge"))
                _plans.delete(e)

        // 1. An attack coming at the knight: parry or block it
        let threat = null, threatDist = 1e9
        for (let e of foes) {
            if (e.enemyType === "spitter") continue
            if (e.aiState !== "telegraph" && e.aiState !== "lunge") continue
            let d = distTo(p, e.xWu, e.yWu)
            if (d < 3.5 && d < threatDist) { threat = e; threatDist = d }
        }
        if (threat) {
            // A guardian winding up within reach of a full charge: the
            // heavy swing staggers it before its blow
            if (answer === "heavy" && threat.enemyType === "guardian" && p.chargeFull
                    && threatDist <= heavyReach(p)) {
                face(p, threat)
                stand(p)
                p.releaseSwing()
                _held = false
                return
            }
            letGo(p)
            if (!_plans.has(threat))
                _plans.set(threat, answer === "perfect" ? "perfect"
                                   : _rng() < parryChance ? "parry" : "block")
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
            return
        }

        // 2. A spitter's shot on its way: shield up towards it a moment
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
            stand(p)
            return
        }
        p.isBlocking = false

        // 3. Go for the nearest enemy
        let target = foes[0], targetDist = distTo(p, target.xWu, target.yWu)
        for (let e of foes) {
            let d = distTo(p, e.xWu, e.yWu)
            if (d < targetDist) { target = e; targetDist = d }
        }
        face(p, target)

        // A guardian's shield turns swings: a charged heavy swing breaks
        // its guard
        if (answer === "heavy" && target.enemyType === "guardian" && target.aiState !== "stagger") {
            // Held past the charge's hold, the knight let it go: press anew
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
        letGo(p)
        // A guardian's shield turns swings: a shield dash breaks its guard
        if (target.enemyType === "guardian" && target.aiState !== "stagger") {
            if (targetDist < 2.5 && p.dashCooldown <= 0 && !p.isDashing) {
                p.isBlocking = true
                moveTowards(p, target.xWu, target.yWu, 1)
                p.dash()
                return
            }
        }
        if (p.isDashing) return

        if (targetDist > 1.3) moveTowards(p, target.xWu, target.yWu, 1)
        else stand(p)
        if (targetDist <= p.attackRange * 0.9) p.attack()
    }
}
