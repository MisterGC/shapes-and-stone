import QtQuick
import Box2D
import Clayground.Physics
import Clayground.GameController

PhysicsItem {
    id: player
    objectName: "player"

    property var gameWorld: null

    // Visual size (the square shape)
    widthWu: 1.0
    heightWu: 1.0

    // Physics config - Dynamic for collision response
    bodyType: Body.Dynamic
    fixedRotation: true
    gravityScale: 0     // No gravity effect (top-down)

    // Collision setup - uses circle fixture smaller than visual
    property alias categories: collider.categories
    property alias collidesWith: collider.collidesWith
    property alias sensor: collider.sensor

    // Attack sensor collision setup
    property alias attackSensorCategories: attackSensor.categories
    property alias attackSensorCollidesWith: attackSensor.collidesWith

    // Movement input (-1 to 1)
    property real moveX: 0
    property real moveY: 0

    // Screen coordinates for aiming (set by Game.qml)
    property real mouseScreenX: 0
    property real mouseScreenY: 0
    property real playerScreenX: 0
    property real playerScreenY: 0

    // Facing direction (calculated in screen space)
    // Screen Y is flipped (down = positive), so we use (playerScreenY - mouseScreenY)
    property real facingAngle: Math.atan2(playerScreenY - mouseScreenY, mouseScreenX - playerScreenX) * 180 / Math.PI

    // Stats, from the balance table
    readonly property real maxSpeed: Balance.knight.moveSpeed
    property int hp: Balance.knight.hp
    property int maxHp: Balance.knight.hp
    property int atk: Balance.knight.atk + _level(Balance.shop.swordAtk, swordLevel, 0)
    property int def: Balance.knight.def
    // A raised shield drains mana, a parry gives some back
    property real mana: Balance.knight.mana
    property int maxMana: Balance.knight.mana
    // Gold picked up this run, for the village's wares
    property int gold: 0
    // Health potions bought from the innkeeper, drunk with key 1
    property int potions: 0
    // Mana draughts bought from the innkeeper, drunk with key 2
    property int draughts: 0
    // The smith's upgrades of the run, each a level from 0 (none) to the
    // table's last (Balance.shop): the sharpened sword, the reinforced
    // shield, the lighter harness and the balanced blade. Every effect
    // reads them live, so setting one applies it at once
    property int swordLevel: 0
    property int shieldLevel: 0
    property int harnessLevel: 0
    property int bladeLevel: 0
    // A level bought from the smith at this camp: he sells one per camp,
    // and the knight of the next level starts without it
    property bool smithDone: false
    // An upgrade's effect at level: its table's entry, base at level 0
    function _level(table, level, base) {
        return level > 0 ? table[Math.min(level, table.length) - 1] : base
    }
    // The share of a blow a held block lets through, and the mana a blow
    // the shield stops costs: a reinforced shield's are lower
    readonly property real blockedShare: _level(Balance.shop.shieldBlockedShare, shieldLevel,
                                                Balance.knight.blockedShare)
    readonly property real blockMana: _level(Balance.shop.shieldBlockMana, shieldLevel,
                                             Balance.knight.blockMana)
    // The mana a dash costs, and a whirlwind with its dash: a lighter
    // harness's and a balanced blade's are lower
    readonly property real dashMana: _level(Balance.shop.harnessDashMana, harnessLevel,
                                            Balance.knight.dashMana)
    readonly property real whirlMana: _level(Balance.shop.bladeWhirlMana, bladeLevel,
                                             Balance.knight.whirlMana)
    readonly property real blockDrain: Balance.knight.blockDrain

    // At 0 HP the knight has fallen: it stands still, takes no more hits
    // and can neither swing nor dash
    readonly property bool fallen: hp <= 0

    // In a session: the fallen ally this knight lifts up (its node's id,
    // "" for none) and how far, 0..1 (Game._stepRevive); a hit starts it
    // over. Every screen draws the ring from it
    property string reviveTarget: ""
    property real reviveProgress: 0
    // How far an ally has lifted this knight up while it is down, 0..1
    property real reviveRing: 0

    // Combat state
    property bool isAttacking: false
    property real _swingTimer: 0
    property bool isBlocking: false
    // Seconds the shield stays down after a crushing blow broke it, on the
    // physics clock: it cannot be raised until then
    property real shieldLock: 0
    // The right button is held: the shield rises again once a crushing
    // blow's lockout is over
    property bool _shieldWanted: false
    // No mana, no shield: it cannot be raised, and drops when it runs dry
    onIsBlockingChanged: {
        if (isBlocking && (mana <= 0 || shieldLock > 0)) {
            isBlocking = false
            return
        }
        // When the shield rose and fell, in physics steps: the perfect block
        if (isBlocking) {
            _cancelCharge()
            _rearmed = _steps - _loweredAt >= Balance.knight.perfectBlockRearm
            _raisedAt = _steps
        } else {
            _loweredAt = _steps
        }
    }
    // Physics steps since the knight came up, the perfect block's clock
    property int _steps: 0
    property int _raisedAt: -1000
    property int _loweredAt: -1000
    // The physics step mana was last spent on: the rest starts over
    property int _spentAt: -1000
    // The shield was down long enough before it rose
    property bool _rearmed: true
    // A blow the shield meets now is blocked perfectly
    readonly property bool perfectGuard: isBlocking && _rearmed
        && _steps - _raisedAt <= Balance.knight.perfectBlockFrames
    property real attackCooldown: 0
    // The swing under way is a charged heavy one
    property bool isHeavy: false
    readonly property real blockSpeedMultiplier: Balance.knight.blockSpeed
    readonly property real pushForce: Balance.knight.pushSpeed  // Knockback velocity for dash-push
    readonly property real attackDuration: Balance.knight.swingDuration
    readonly property real attackCooldownTime: Balance.knight.attackCooldown
    readonly property real attackRange: Balance.knight.attackRange
    readonly property real attackArcAngle: Balance.knight.attackArc

    // Dash state
    property bool isDashing: false
    property real dashCooldown: 0
    readonly property real dashSpeed: Balance.knight.dashSpeed
    readonly property real dashDuration: Balance.knight.dashDuration
    readonly property real dashCooldownTime: Balance.knight.dashCooldown
    property real _dashTimer: 0
    property real _dashDirX: 0
    property real _dashDirY: 0
    // The dash under way is a whirlwind (Balance.knight.whirl...): a full
    // charge let go within whirlWindow steps of the dash's start
    property bool isWhirling: false
    // The physics step a full charge swung heavy, and the one a dash
    // started with a full charge held: the whirlwind's window
    property int _fullLetGoAt: -1000
    property int _dashedFullAt: -1000
    // The enemies this whirlwind hit, and whether it hit any
    property var _hitThisWhirl: new Set()
    property bool _whirlLanded: false

    // Seconds left of the grace after a hit, in which no damage is taken
    property real graceLeft: 0

    // How far a hit throws the knight back, in wu (Balance.knight.knockback);
    // a bench that times its answers on a knight standing still sets 0
    property real knockback: Balance.knight.knockback
    // Thrown back by a hit: seconds left of it and its velocity at the
    // start, in wu per second, y up
    property real _knockT: 0
    property real _knockVx: 0
    property real _knockVy: 0

    // Footsteps: the way really walked since the last one, wu; a dash, a
    // knockback or a fall makes none and starts the count again
    property real _walked: 0
    property real _lastX: NaN
    property real _lastY: NaN
    function _countSteps() {
        let dx = xWu - _lastX, dy = yWu - _lastY
        _lastX = xWu
        _lastY = yWu
        if (isNaN(dx) || fallen || isDashing || _knockT > 0) {
            _walked = 0
            return
        }
        _walked += Math.sqrt(dx * dx + dy * dy)
        if (_walked >= Balance.steps.length) {
            _walked = 0
            if (gameWorld && gameWorld.playStep) gameWorld.playStep()
        }
    }

    // Movement - set velocity every physics step so collision response
    // doesn't permanently zero a component while the key is held.
    // Dash, swing and cooldowns count the time the step simulated: a pause, a
    // single step or a hit stop holds them with the world (issue #33).
    Connections {
        target: player.world
        function onStepped() {
            let dt = player.world.timeStep
            _steps++
            _countSteps()
            attackCooldown = Math.max(0, attackCooldown - dt)
            dashCooldown = Math.max(0, dashCooldown - dt)
            if (graceLeft > 0) graceLeft = graceLeft - dt < 1e-6 ? 0 : graceLeft - dt
            if (shieldLock > 0) {
                shieldLock = shieldLock - dt < 1e-6 ? 0 : shieldLock - dt
                if (shieldLock === 0 && _shieldWanted && !fallen && mana > 0) isBlocking = true
            }
            if (isBlocking && !fallen) {
                let left = mana - blockDrain * dt
                mana = left < 1e-6 ? 0 : left
                if (mana <= 0) {
                    isBlocking = false
                    _shieldBreak()
                }
            } else if (!fallen && mana < maxMana
                       && (_steps - Math.max(_loweredAt, _spentAt)) * dt >= Balance.knight.manaRegenDelay) {
                // Down long enough, the shield's mana comes back
                mana = Math.min(maxMana, mana + Balance.knight.manaRegen * dt)
            }
            // A swing hits until its arc has faded, as long as the view
            // draws it, but counted in steps
            if (isAttacking) {
                _swingTimer -= dt
                if (_swingTimer <= 0) {
                    isAttacking = false
                    isHeavy = false
                }
            }

            if (fallen) {
                player.body.linearVelocity = Qt.point(0, 0)
            } else if (isDashing) {
                let spd = isWhirling ? Balance.knight.whirlSpeed
                        : isBlocking ? dashSpeed * blockSpeedMultiplier : dashSpeed
                player.body.linearVelocity = Qt.point(_dashDirX * spd, _dashDirY * spd)
                _dashTimer -= dt
                // Dash-push: knockback enemies instead of damage
                if (isBlocking) pushEnemiesInRange()
                if (isWhirling) whirlEnemies()
                if (_dashTimer <= 0) {
                    isDashing = false
                    isWhirling = false
                }
            } else if (_knockT > 0) {
                // Fades out step by step, like an enemy's knockback
                let k = _knockT / Balance.knight.knockbackDuration
                player.body.linearVelocity = Qt.point(_knockVx * k, -_knockVy * k)
                _knockT = _knockT - dt < 1e-6 ? 0 : _knockT - dt
            } else if (isBlocking) {
                let spd = maxSpeed * blockSpeedMultiplier
                player.body.linearVelocity = Qt.point(moveX * spd, moveY * spd)
            } else if (isCharging) {
                let spd = maxSpeed * Balance.knight.chargeSpeed
                player.body.linearVelocity = Qt.point(moveX * spd, moveY * spd)
            } else {
                player.body.linearVelocity = Qt.point(moveX * maxSpeed, moveY * maxSpeed)
            }
            if (isAttacking) hitEnemiesInArc()
            // A full charge held into a dash is spent once the whirlwind's
            // window after the dash's start has passed
            if (_charge === "full" && _dashedFullAt >= 0
                    && _steps - _dashedFullAt > Balance.knight.whirlWindow)
                _charge = "spent"
        }
    }

    // A moment others should see: "attack", "heavy", "whirlwind", "dash",
    // "parry", "block", "perfectBlock", "hurt" or "shieldBreak".
    // Game.qml sends it to the other players, whose RemotePlayer shows it.
    signal acted(string action)

    // Healing state (set by Campfire)
    property bool isHealing: false

    // How the knight looks: shared with the RemotePlayer
    KnightView {
        id: view
        host: player
        gameWorld: player.gameWorld
        facingAngle: player.facingAngle
        moveX: player.moveX
        moveAmount: Math.min(1, Math.sqrt(player.moveX * player.moveX + player.moveY * player.moveY))
        blocking: player.isBlocking
        dashing: player.isDashing
        healing: player.isHealing
        dashCooldownProgress: 1.0 - (player.dashCooldown / player.dashCooldownTime)
        swingDuration: player.attackDuration
        graceLeft: player.graceLeft
        lowShield: player.mana < player.maxMana * Balance.shieldBreak.lowShare
        potions: player.potions
        draughts: player.draughts
        charging: player.isCharging
        charge: player.chargeProgress
        chargeFull: player.chargeFull
        downed: player.fallen
        reviveProgress: player.reviveRing
        swordLevel: player.swordLevel
        shieldLevel: player.shieldLevel
    }

    // DEBUG: Attack damage area visualization (wedge showing hit zone)
    // Positioned manually to avoid inflating parent's childrenRect
    // which would distort Box2D debug draw.
    Canvas {
        id: attackZoneDebug
        visible: gameWorld ? gameWorld.debugMechanics : false
        parent: player.parent
        x: player.x + player.width/2 - width/2
        y: player.y + player.height/2 - height/2
        width: attackRange * pixelPerUnit * 2.2
        height: attackRange * pixelPerUnit * 2.2
        rotation: -facingAngle
        opacity: 0.3

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var centerX = width / 2
            var centerY = height / 2
            var radius = attackRange * pixelPerUnit

            // Draw wedge for attack arc (±attackArcAngle degrees)
            var arcRad = attackArcAngle * Math.PI / 180
            ctx.beginPath()
            ctx.moveTo(centerX, centerY)
            ctx.arc(centerX, centerY, radius, -arcRad, arcRad)
            ctx.closePath()
            ctx.fillStyle = "#FF6600"
            ctx.fill()
        }

        // Repaint when facing changes
        Connections {
            target: player
            function onFacingAngleChanged() { attackZoneDebug.requestPaint() }
        }
    }

    // Circular collider — matches visual size closely
    fixtures: [
        Circle {
            id: collider
            radius: player.width * 0.45
            x: player.width / 2
            y: player.height / 2
            density: 1.0
            friction: 0.0
            restitution: 0.0

            onBeginContact: (other) => player.onCollision(other)
        },
        // Attack range sensor — proximity detector for melee candidates.
        // Actual hit detection uses hitEnemiesInArc() with distance + angle checks,
        // so this just needs to be a rough proximity envelope.
        Circle {
            id: attackSensor
            radius: player.width * Balance.knight.attackSensor
            x: player.width / 2
            y: player.height / 2
            sensor: true

            onBeginContact: (other) => {
                let entity = other.getBody().target
                if (entity && entity.objectName === "enemy") {
                    enemiesInRange.add(entity)
                }
            }
            onEndContact: (other) => {
                let entity = other.getBody().target
                if (entity) {
                    enemiesInRange.delete(entity)
                }
            }
        }
    ]

    // Track enemies currently in attack range. An enemy that dies in range
    // ends its contacts with its item since MisterGC/clayground#371;
    // _inRange() stays as a guard that drops one that is gone or dead.
    property var enemiesInRange: new Set()
    // The enemies in range that still stand
    function _inRange() {
        for (let enemy of enemiesInRange)
            if (!enemy || enemy.destroyed !== false) enemiesInRange.delete(enemy)
        return enemiesInRange
    }
    property var _hitThisSwing: new Set()

    function onCollision(other) {
        // Handle collision with enemies
    }

    // Check if an enemy is within the attack arc: a heavy swing's when one
    // is under way
    function isInAttackArc(enemy) {
        let dx = enemy.xWu - xWu
        let dy = enemy.yWu - yWu
        let angleToEnemy = Math.atan2(dy, dx) * 180 / Math.PI

        // Normalize angle difference to -180 to 180
        let angleDiff = angleToEnemy - facingAngle
        while (angleDiff > 180) angleDiff -= 360
        while (angleDiff < -180) angleDiff += 360

        return Math.abs(angleDiff) <= (isHeavy ? Balance.knight.heavyArc : attackArcAngle)
    }

    // The enemies a swing can reach: those the attack sensor holds, and for
    // a heavy swing every standing enemy within heavyRange of the attack
    // range, centre to centre - it reaches past the sensor
    function _swingCandidates() {
        let inRange = _inRange()
        if (!isHeavy || !gameWorld || !gameWorld.enemies) return inRange
        let reach = attackRange * Balance.knight.heavyRange
        let all = new Set(inRange)
        for (let e of gameWorld.enemies) {
            if (!e || e.destroyed !== false) continue
            let dx = e.xWu + e.widthWu / 2 - (xWu + widthWu / 2)
            let dy = e.yWu - e.heightWu / 2 - (yWu - heightWu / 2)
            if (dx * dx + dy * dy <= reach * reach) all.add(e)
        }
        return all
    }

    // Deal damage to enemies in attack arc (skips already-hit enemies this swing)
    function hitEnemiesInArc() {
        let hitCount = 0
        for (let enemy of _swingCandidates()) {
            if (!_hitThisSwing.has(enemy) && isInAttackArc(enemy)) {
                let parried = enemy.parryWindow
                let dmg = isBlocking ? Math.floor(atk * Balance.knight.blockingSwing)
                        : isDashing ? Math.floor(atk * Balance.knight.dashingSwing) : atk
                if (parried) dmg = atk * Balance.knight.parrySwing
                if (isHeavy) {
                    dmg = Math.max(dmg, Math.floor(atk * Balance.knight.heavySwing))
                    // It breaks a guardian's guard: staggered, its shield
                    // takes nothing off and it does not counter
                    if (enemy.enemyType === "guardian" && !parried) enemy.stagger()
                }
                enemy.takeDamage(dmg, xWu, yWu, isHeavy)
                _hitThisSwing.add(enemy)
                hitCount++
                if (parried) {
                    if (gameWorld) gameWorld.countFight("parry")
                    if (gameWorld && gameWorld.parried) gameWorld.parried(enemy)
                    enemy.stagger()
                    attackCooldown = 0
                    mana = Math.min(maxMana, mana + Balance.knight.parryMana)
                    view.parry()
                    acted("parry")
                    if (gameWorld) {
                        gameWorld.playImpact()
                        if (gameWorld.impact)
                            gameWorld.impact("parry", enemy.xWu, enemy.yWu, enemy.xWu - xWu, enemy.yWu - yWu)
                        else
                            gameWorld.spawnParryEffect(enemy.xWu, enemy.yWu)
                        gameWorld.spawnDamageNumber(enemy.xWu, enemy.yWu, dmg, "#FFD700")
                        gameWorld.spawnWord(enemy.xWu, enemy.yWu + 0.5, "PARRY", "#FFD700")
                    }
                    console.log("[Player] PARRY! Dealt", dmg, "damage!")
                } else {
                    if (gameWorld) {
                        gameWorld.playImpact()
                        gameWorld.spawnDamageNumber(enemy.xWu, enemy.yWu, dmg, "#FFCC44")
                    }
                    console.log("[Player] Hit enemy for", dmg, "damage!")
                }
            }
        }
        return hitCount
    }

    // Push enemies away during dash-push (skips already-pushed this dash)
    function pushEnemiesInRange() {
        for (let enemy of _inRange()) {
            if (!_hitThisSwing.has(enemy)) {
                let dx = enemy.xWu - xWu
                let dy = enemy.yWu - yWu
                let len = Math.sqrt(dx * dx + dy * dy)
                if (len < 0.01) continue
                enemy.shove(dx, dy, pushForce)
                _hitThisSwing.add(enemy)
                // Shield-push breaks guardian guard
                if (enemy.enemyType === "guardian") enemy.stagger()
                if (gameWorld) gameWorld.playImpact()
                console.log("[Player] Pushed enemy!" + (enemy.enemyType === "guardian" ? " (guard broken!)" : ""))
            }
        }
    }

    // The whirlwind hits every standing enemy within whirlReach of the
    // knight, centre to centre, once: a heavy blow, through a guardian's
    // shield. Returns how many it hit this step
    function whirlEnemies() {
        if (!gameWorld || !gameWorld.enemies) return 0
        let k = Balance.knight
        let hitCount = 0
        for (let e of gameWorld.enemies) {
            if (!e || e.destroyed !== false || _hitThisWhirl.has(e)) continue
            let dx = e.xWu + e.widthWu / 2 - (xWu + widthWu / 2)
            let dy = e.yWu - e.heightWu / 2 - (yWu - heightWu / 2)
            if (dx * dx + dy * dy > k.whirlReach * k.whirlReach) continue
            let dmg = Math.floor(atk * k.whirlSwing)
            _hitThisWhirl.add(e)
            e.takeDamage(dmg, xWu, yWu, true)
            hitCount++
            gameWorld.countFight("whirlHit")
            if (!_whirlLanded) {
                _whirlLanded = true
                gameWorld.countFight("whirlwind")
            }
            gameWorld.playImpact()
            gameWorld.spawnDamageNumber(e.xWu, e.yWu, dmg, Balance.whirl.glow)
            console.log("[Player] Whirlwind hit enemy for", dmg, "damage!")
        }
        return hitCount
    }

    readonly property real shieldArcAngle: Balance.knight.shieldArc

    // Whether the shield faces an attacker whose corner is (attackerX,
    // attackerY) and whose size is attackerSize Wu (the knight's own without
    // it), measured from the knight's centre to the attacker's: the one
    // place a blow's direction is judged. Corner to corner, a small shot
    // from the left or from above came in at the arc's edge or beyond.
    function isShieldFacing(attackerX, attackerY, attackerSize) {
        let a = _centreOf(attackerX, attackerY, attackerSize)
        let dx = a.x - (xWu + widthWu / 2)
        let dy = a.y - (yWu - heightWu / 2)
        let angleToAttacker = Math.atan2(dy, dx) * 180 / Math.PI
        let angleDiff = angleToAttacker - facingAngle
        while (angleDiff > 180) angleDiff -= 360
        while (angleDiff < -180) angleDiff += 360
        return Math.abs(angleDiff) <= shieldArcAngle
    }

    // The centre of a square thing at corner (x, y) of size Wu, the
    // knight's own size without one
    function _centreOf(x, y, size) {
        let s = size === undefined ? widthWu : size
        return { x: x + s / 2, y: y - s / 2 }
    }

    function getShieldWorldPos() {
        let rad = facingAngle * Math.PI / 180
        return { x: xWu + Math.cos(rad) * 0.5, y: yWu + Math.sin(rad) * 0.5 }
    }

    // Returns what became of the blow: "hit", "blocked" by the shield,
    // "perfect" - blocked by a shield raised just before it (perfectGuard),
    // "crushed" - a crushing blow that broke the held shield, "dodged" by
    // a dash, or "ignored" - fallen or in the grace after a hit.
    // Only a blow that was hit or blocked should look and sound like one;
    // a perfect block and a crushing blow look and sound like their own.
    // The attacker is the corner (attackerX, attackerY) of a thing
    // attackerSize Wu in size (isShieldFacing); crush is true for a
    // crushing blow (Balance.enemy.crush...). (alongX, alongY) is the way
    // the blow travelled, y up - a lunge's or a shot's - which a hit
    // throws the knight back along; without it, from the attacker's centre
    // through the knight's.
    function takeDamage(amount, attackerX, attackerY, attackerSize, crush, alongX, alongY) {
        if (fallen) return "ignored"
        if (isDashing) return "dodged"  // Invulnerable during dash
        if (graceLeft > 0) return "ignored"  // and for a moment after a hit
        let finalDamage = Math.max(Balance.minDamage, amount - def)
        let blocked = isBlocking && isShieldFacing(attackerX, attackerY, attackerSize)
        if (blocked && perfectGuard) return _perfectBlock(attackerX, attackerY, attackerSize)
        if (blocked && crush === true)
            return _crushed(finalDamage, attackerX, attackerY, attackerSize, alongX, alongY)
        if (blocked) {
            finalDamage = Math.floor(finalDamage * blockedShare)
            // The shield's own sound, the only one a blocked blow plays
            if (gameWorld) gameWorld.playBlock()
            view.block()
            acted("block")
            payBlock()
        }
        hp = Math.max(0, hp - finalDamage)
        if (gameWorld) {
            gameWorld.countFight("taken", finalDamage)
            if (blocked) gameWorld.countFight("block")
        }
        if (!blocked) {
            _cancelCharge()
            graceLeft = Balance.knight.hurtGrace
            _knockBack(attackerX, attackerY, attackerSize, alongX, alongY)
            view.hurt()
            acted("hurt")
            // The knight's own hurt sound, the only one a hit plays
            if (gameWorld) gameWorld.playHurt()
        }
        if (gameWorld) {
            let a = _centreOf(attackerX, attackerY, attackerSize)
            if (gameWorld.impact)
                gameWorld.impact(blocked ? "playerBlocked" : "playerHit", xWu, yWu,
                                 xWu + widthWu / 2 - a.x, yWu - heightWu / 2 - a.y)
            else
                gameWorld.shake(blocked ? 1 : 3)
            gameWorld.spawnHurtNumber(xWu, yWu, finalDamage, blocked ? "#4A90A4" : "#FF4444")
        }
        return blocked ? "blocked" : "hit"
    }

    // Thrown back along the blow (takeDamage), knockback wu: a knockback
    // fades out step by step, so it covers its start speed
    // times the sum of its steps' shares of it
    function _knockBack(attackerX, attackerY, attackerSize, alongX, alongY) {
        let k = Balance.knight
        if (knockback <= 0 || fallen) return
        let dx = alongX, dy = alongY
        if (dx === undefined || dy === undefined || dx * dx + dy * dy < 1e-6) {
            let a = _centreOf(attackerX, attackerY, attackerSize)
            dx = xWu + widthWu / 2 - a.x
            dy = yWu - heightWu / 2 - a.y
        }
        let len = Math.sqrt(dx * dx + dy * dy)
        if (len < 0.001) return
        let dt = player.world.timeStep, per = 0
        for (let t = k.knockbackDuration; t > 1e-9; t -= dt) per += t / k.knockbackDuration * dt
        let speed = knockback / per
        _knockVx = dx / len * speed
        _knockVy = dy / len * speed
        _knockT = k.knockbackDuration
    }

    // The shield rose just before the blow: it takes all of it and gives
    // some mana back; the attacker staggers on "perfect"
    function _perfectBlock(attackerX, attackerY, attackerSize) {
        mana = Math.min(maxMana, mana + Balance.knight.perfectBlockMana)
        view.perfectBlock()
        acted("perfectBlock")
        if (gameWorld) {
            gameWorld.playBlock(1, true)
            gameWorld.countFight("block")
            gameWorld.countFight("perfectBlock")
            gameWorld.spawnWord(attackerX, attackerY + 0.5, "PERFECT", Balance.perfectBlock.flashColor)
            let a = _centreOf(attackerX, attackerY, attackerSize)
            let s = getShieldWorldPos()
            if (gameWorld.impact)
                gameWorld.impact("perfectBlock", s.x, s.y,
                                 xWu + widthWu / 2 - a.x, yWu - heightWu / 2 - a.y)
            else
                gameWorld.shake(1)
        }
        return "perfect"
    }

    // A crushing blow met the held shield: it breaks - crushMana mana gone,
    // down for crushLockout seconds - and crushShare of the damage lands,
    // a hurt with its grace
    function _crushed(damage, attackerX, attackerY, attackerSize, alongX, alongY) {
        let e = Balance.enemy
        let finalDamage = Math.max(Balance.minDamage, Math.floor(damage * e.crushShare))
        _spend(e.crushMana)
        shieldLock = e.crushLockout
        isBlocking = false
        hp = Math.max(0, hp - finalDamage)
        _cancelCharge()
        graceLeft = Balance.knight.hurtGrace
        _knockBack(attackerX, attackerY, attackerSize, alongX, alongY)
        _shieldBreak()
        view.hurt()
        acted("hurt")
        if (gameWorld) {
            gameWorld.playHurt()
            gameWorld.countFight("taken", finalDamage)
            gameWorld.countFight("crushed")
            let a = _centreOf(attackerX, attackerY, attackerSize)
            if (gameWorld.impact)
                gameWorld.impact("crushBlow", xWu, yWu,
                                 xWu + widthWu / 2 - a.x, yWu - heightWu / 2 - a.y)
            else
                gameWorld.shake(3)
            gameWorld.spawnHurtNumber(xWu, yWu, finalDamage, "#FF4444")
        }
        return "crushed"
    }

    // Mana spent: the rest before it comes back starts over
    function _spend(amount) {
        mana = Math.max(0, mana - amount)
        _spentAt = _steps
    }
    // Whether the knight has amount mana; without it, it says so - the
    // word over it, the empty click and the mana bar's flash - so a
    // refused move is never a dead input
    function _afford(amount) {
        if (mana >= amount) return true
        _noMana()
        return false
    }
    function _noMana() {
        if (!gameWorld) return
        gameWorld.playShieldEmpty()
        gameWorld.flashManaBar()
        if (gameWorld.spawnWord)
            gameWorld.spawnWord(xWu, yWu + 0.4, Balance.knight.noManaWord, Balance.knight.noManaColor)
    }
    // A blow the raised shield stopped, a lunge or a shot: it costs
    // blockMana, and the shield breaks if that empties it
    function payBlock() {
        _spend(blockMana)
        if (mana <= 0 && isBlocking) {
            isBlocking = false
            _shieldBreak()
        }
    }

    // The shield ran dry while raised: it breaks, with a crack, and the
    // mana bar flashes
    function _shieldBreak() {
        view.shieldBreak()
        acted("shieldBreak")
        if (gameWorld) {
            gameWorld.playShieldBreak()
            gameWorld.flashManaBar()
        }
    }

    // The right button: raises the shield, or, with no mana, answers with
    // a dull click and the mana bar's flash so it is no dead input
    function raiseShield() {
        if (fallen) return
        _shieldWanted = true
        // Broken by a crushing blow: it rises when the lockout is over
        if (shieldLock > 0) return
        if (mana <= 0) {
            _noMana()
            return
        }
        isBlocking = true
    }
    // The right button is let go of
    function lowerShield() {
        _shieldWanted = false
        isBlocking = false
    }

    // A potion heals up to max HP; none is wasted on a knight that is
    // unhurt or has fallen. Returns the HP it healed, 0 when none was drunk
    function drinkPotion() {
        if (potions <= 0 || fallen || hp >= maxHp) return 0
        let healed = Math.min(Balance.shop.potionHeal, maxHp - hp)
        potions--
        hp += healed
        return healed
    }

    // A draught gives mana back up to max mana; none is wasted on a knight
    // whose mana is full or that has fallen. Returns the mana it gave,
    // 0 when none was drunk
    function drinkDraught() {
        if (draughts <= 0 || fallen || mana >= maxMana) return 0
        let gained = Math.min(Balance.shop.draughtMana, maxMana - mana)
        draughts--
        mana += gained
        return gained
    }

    function dash() {
        if (fallen || dashCooldown > 0 || isDashing) return
        // Use movement direction, or facing direction if stationary
        let dirX = moveX
        let dirY = moveY
        if (dirX === 0 && dirY === 0) {
            let rad = facingAngle * Math.PI / 180
            dirX = Math.cos(rad)
            dirY = -Math.sin(rad)  // Screen Y is flipped
        }
        let len = Math.sqrt(dirX * dirX + dirY * dirY)
        if (len < 0.01) return
        _dashDirX = dirX / len
        _dashDirY = dirY / len
        // A heavy swing just let go of turns into a whirlwind; a full
        // charge still held waits whirlWindow steps for its release
        let whirl = isAttacking && isHeavy && _steps - _fullLetGoAt <= Balance.knight.whirlWindow
        // A dash costs dashMana, a whirlwind whirlMana with its dash;
        // without the whirlwind's, the dash goes on as one
        if (!_afford(dashMana)) return
        if (whirl && mana < whirlMana) {
            whirl = false
            _noMana()
        }
        _spend(whirl ? whirlMana : dashMana)
        let kept = whirl ? new Set(_hitThisSwing) : null
        if (_charge === "full" && !whirl) _dashedFullAt = _steps
        else _cancelCharge()
        isDashing = true
        _knockT = 0
        _hitThisSwing = new Set()
        _dashTimer = dashDuration
        dashCooldown = dashCooldownTime
        view.dash(dashDuration * 1000)
        acted("dash")
        if (gameWorld) gameWorld.playDash()
        if (whirl) _whirl(kept)
    }

    // The whirlwind: the dash under way goes on as one, whirlDuration
    // seconds at whirlSpeed from now. hit holds the enemies the heavy
    // swing it turns has hit already: those it does not hit again
    function _whirl(hit) {
        let k = Balance.knight
        isAttacking = false
        isHeavy = false
        isWhirling = true
        _hitThisWhirl = hit || new Set()
        _whirlLanded = false
        _dashTimer = k.whirlDuration
        dashCooldown = k.whirlDuration + dashCooldownTime
        attackCooldown = k.whirlDuration
        view.whirl(k.whirlDuration * 1000)
        acted("whirlwind")
        if (gameWorld) {
            gameWorld.playWhirlwind()
            if (gameWorld.impact)
                gameWorld.impact("whirlwind", xWu, yWu, _dashDirX, -_dashDirY)
        }
        console.log("[Player] Whirlwind!")
    }

    function attack() {
        if (!fallen && attackCooldown <= 0 && !isAttacking) {
            isAttacking = true
            isHeavy = false
            _swingTimer = attackDuration + Balance.knight.swingFade
            _hitThisSwing = new Set()
            attackCooldown = attackCooldownTime
            view.swing()
            acted("attack")
            if (!isDashing && gameWorld) gameWorld.playSwordSwing()
            console.log("[Player] Attack! Facing:", facingAngle.toFixed(0), "degrees")
        }
    }

    // The charged swing: a wide heavy blow (Balance.knight.heavy...).
    // Returns whether it swung
    function heavyAttack() {
        if (fallen || attackCooldown > 0 || isAttacking) return false
        isAttacking = true
        isHeavy = true
        _fullLetGoAt = _steps
        _swingTimer = attackDuration + Balance.knight.swingFade
        _hitThisSwing = new Set()
        attackCooldown = attackCooldownTime
        view.swing(true)
        acted("heavy")
        if (gameWorld) gameWorld.playHeavySwing()
        console.log("[Player] Heavy swing! Facing:", facingAngle.toFixed(0), "degrees")
        return true
    }

    // The left button. A press is a swing on its release before
    // knight.chargeStart, and a charge when held longer: charging from
    // chargeStart, full at chargeTime, let go at normal strength
    // chargeHold after that. Its clock is the physics steps (swingInput), so
    // a pause or a hit stop holds the charge. Game.qml hands the mouse
    // button's events to pressSwing() and releaseSwing(); a bench can call
    // them without one.
    function pressSwing(mouse) { return swingInput.press(mouse) }
    function releaseSwing(mouse) { return swingInput.release(mouse) }
    // The button is let go of without a swing: a menu took the input
    function dropSwing() {
        _cancelCharge()
        _charge = "spent"
        swingInput.release()
    }

    // Where the press is: "" before chargeStart, "charging", "full",
    // "normal" (held past chargeStart while it could not charge: a normal
    // swing on release) or "spent" (swung already, or cancelled: nothing
    // on release)
    property string _charge: ""
    readonly property bool isCharging: _charge === "charging" || _charge === "full"
    readonly property bool chargeFull: _charge === "full"
    // Seconds the left button has been held, on the physics clock
    readonly property real chargeHeld: swingInput.heldMs / 1000
    // 0 when the charge begins, 1 when it is full
    readonly property real chargeProgress: !isCharging ? 0
        : Math.min(1, Math.max(0, (chargeHeld - Balance.knight.chargeStart)
                               / (Balance.knight.chargeTime - Balance.knight.chargeStart)))

    // A hit, a raised shield or a dash ends a charge: its release swings
    // nothing. A full charge outlives a dash by the whirlwind's window
    function _cancelCharge() {
        if (isCharging) _charge = "spent"
    }

    function _onSwingPressed() {
        _charge = ""
        _dashedFullAt = -1000
        if (fallen) {
            _charge = "spent"
        } else if (isBlocking || isDashing) {
            // No charge behind the shield or in a dash: the press swings at
            // once, as the swing while blocking and the dash swing always did
            attack()
            _charge = "spent"
        }
    }

    function _onSwingHeld(heldMs) {
        // timeStep is a float: 36 steps of 1/60 s sum to just under 600 ms
        let held = heldMs + 1e-3
        let k = Balance.knight
        if (_charge === "" && held >= k.chargeStart * 1000)
            _charge = isBlocking || isDashing || fallen ? "normal" : "charging"
        if (_charge === "charging" && held >= k.chargeTime * 1000) {
            _charge = "full"
            if (gameWorld) gameWorld.playChargeFull()
        }
        if (_charge === "full" && held >= (k.chargeTime + k.chargeHold) * 1000) {
            // Held too long: it goes at normal strength, no charge is carried
            _charge = "spent"
            attack()
        }
    }

    function _onSwingReleased() {
        // Let go of within the window after the dash started: a whirlwind
        // its dash paid dashMana already, the whirlwind the rest of
        // whirlMana; without it, the charge swings heavy
        let whirlRest = Math.max(0, whirlMana - dashMana)
        let inWindow = _charge === "full" && isDashing && !isWhirling
            && _steps - _dashedFullAt <= Balance.knight.whirlWindow
        if (inWindow && _afford(whirlRest)) {
            _spend(whirlRest)
            _whirl()
        } else if (_charge === "full") heavyAttack()
        else if (_charge === "" || _charge === "charging" || _charge === "normal") attack()
        _charge = ""
    }

    onFallenChanged: if (fallen) _cancelCharge()

    InputAction {
        id: swingInput
        world: player.world
        mouseButton: Qt.LeftButton
        holdThresholdMs: Balance.knight.chargeStart * 1000
        onPressedChanged: if (pressed) player._onSwingPressed()
        onHeldMsChanged: if (pressed) player._onSwingHeld(heldMs)
        onReleased: player._onSwingReleased()
    }
}
