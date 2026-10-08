import QtQuick
import Box2D
import Clayground.Physics

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
    property int maxHp: Balance.knight.hp + (upgrade === "hp" ? Balance.shop.hpUpgrade : 0)
    property int atk: Balance.knight.atk + (upgrade === "atk" ? Balance.shop.atkUpgrade : 0)
    property int def: Balance.knight.def
    // A raised shield drains mana, a parry gives some back
    property real mana: Balance.knight.mana
    property int maxMana: Balance.knight.mana
    // Gold picked up this run, for the village's wares
    property int gold: 0
    // Health potions bought from the innkeeper, drunk with key 1
    property int potions: 0
    // The smith's one upgrade of the run: "atk", "hp" or "" before it
    property string upgrade: ""

    // At 0 HP the knight has fallen: it stands still, takes no more hits
    // and can neither swing nor dash
    readonly property bool fallen: hp <= 0

    // Combat state
    property bool isAttacking: false
    property real _swingTimer: 0
    property bool isBlocking: false
    // No mana, no shield: it cannot be raised, and drops when it runs dry
    onIsBlockingChanged: {
        if (isBlocking && mana <= 0) {
            isBlocking = false
            return
        }
        // When the shield rose and fell, in physics steps: the perfect block
        if (isBlocking) {
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
    // The shield was down long enough before it rose
    property bool _rearmed: true
    // A blow the shield meets now is blocked perfectly
    readonly property bool perfectGuard: isBlocking && _rearmed
        && _steps - _raisedAt <= Balance.knight.perfectBlockFrames
    property real attackCooldown: 0
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

    // Seconds left of the grace after a hit, in which no damage is taken
    property real graceLeft: 0

    // Movement - set velocity every physics step so collision response
    // doesn't permanently zero a component while the key is held.
    // Dash, swing and cooldowns count the time the step simulated: a pause, a
    // single step or a hit stop holds them with the world (issue #33).
    Connections {
        target: player.world
        function onStepped() {
            let dt = player.world.timeStep
            _steps++
            attackCooldown = Math.max(0, attackCooldown - dt)
            dashCooldown = Math.max(0, dashCooldown - dt)
            if (graceLeft > 0) graceLeft = graceLeft - dt < 1e-6 ? 0 : graceLeft - dt
            if (isBlocking && !fallen) {
                let left = mana - Balance.knight.blockDrain * dt
                mana = left < 1e-6 ? 0 : left
                if (mana <= 0) isBlocking = false
            }
            // A swing hits until its arc has faded, as long as the view
            // draws it, but counted in steps
            if (isAttacking) {
                _swingTimer -= dt
                if (_swingTimer <= 0) isAttacking = false
            }

            if (fallen) {
                player.body.linearVelocity = Qt.point(0, 0)
            } else if (isDashing) {
                let spd = isBlocking ? dashSpeed * blockSpeedMultiplier : dashSpeed
                player.body.linearVelocity = Qt.point(_dashDirX * spd, _dashDirY * spd)
                _dashTimer -= dt
                // Dash-push: knockback enemies instead of damage
                if (isBlocking) pushEnemiesInRange()
                if (_dashTimer <= 0) isDashing = false
            } else if (isBlocking) {
                let spd = maxSpeed * blockSpeedMultiplier
                player.body.linearVelocity = Qt.point(moveX * spd, moveY * spd)
            } else {
                player.body.linearVelocity = Qt.point(moveX * maxSpeed, moveY * maxSpeed)
            }
            if (isAttacking) hitEnemiesInArc()
        }
    }

    // A moment others should see: "attack", "dash", "parry", "block",
    // "perfectBlock" or "hurt".
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
        downed: player.fallen
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

    // Check if an enemy is within the attack arc
    function isInAttackArc(enemy) {
        let dx = enemy.xWu - xWu
        let dy = enemy.yWu - yWu
        let angleToEnemy = Math.atan2(dy, dx) * 180 / Math.PI

        // Normalize angle difference to -180 to 180
        let angleDiff = angleToEnemy - facingAngle
        while (angleDiff > 180) angleDiff -= 360
        while (angleDiff < -180) angleDiff += 360

        return Math.abs(angleDiff) <= attackArcAngle
    }

    // Deal damage to enemies in attack arc (skips already-hit enemies this swing)
    function hitEnemiesInArc() {
        let hitCount = 0
        for (let enemy of _inRange()) {
            if (!_hitThisSwing.has(enemy) && isInAttackArc(enemy)) {
                let parried = enemy.parryWindow
                let dmg = isBlocking ? Math.floor(atk * Balance.knight.blockingSwing)
                        : isDashing ? Math.floor(atk * Balance.knight.dashingSwing) : atk
                if (parried) dmg = atk * Balance.knight.parrySwing
                enemy.takeDamage(dmg, xWu, yWu)
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
                        gameWorld.spawnDamageNumber(enemy.xWu, enemy.yWu + 0.5, "PARRY", "#FFD700")
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
    // "dodged" by a dash, or "ignored" - fallen or in the grace after a hit.
    // Only a blow that was hit or blocked should look and sound like one;
    // a perfect block looks and sounds like its own.
    // The attacker is the corner (attackerX, attackerY) of a thing
    // attackerSize Wu in size (isShieldFacing).
    function takeDamage(amount, attackerX, attackerY, attackerSize) {
        if (fallen) return "ignored"
        if (isDashing) return "dodged"  // Invulnerable during dash
        if (graceLeft > 0) return "ignored"  // and for a moment after a hit
        let finalDamage = Math.max(Balance.minDamage, amount - def)
        let blocked = isBlocking && isShieldFacing(attackerX, attackerY, attackerSize)
        if (blocked && perfectGuard) return _perfectBlock(attackerX, attackerY, attackerSize)
        if (blocked) {
            finalDamage = Math.floor(finalDamage * Balance.knight.blockedShare)
            // The shield's own sound, the only one a blocked blow plays
            if (gameWorld) gameWorld.playBlock()
            view.block()
            acted("block")
        }
        hp = Math.max(0, hp - finalDamage)
        if (gameWorld) {
            gameWorld.countFight("taken", finalDamage)
            if (blocked) gameWorld.countFight("block")
        }
        if (!blocked) {
            graceLeft = Balance.knight.hurtGrace
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
            gameWorld.spawnDamageNumber(xWu, yWu, finalDamage, blocked ? "#4A90A4" : "#FF4444")
        }
        return blocked ? "blocked" : "hit"
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

    // A potion heals up to max HP; none is wasted on a knight that is
    // unhurt or has fallen. Returns the HP it healed, 0 when none was drunk
    function drinkPotion() {
        if (potions <= 0 || fallen || hp >= maxHp) return 0
        let healed = Math.min(Balance.shop.potionHeal, maxHp - hp)
        potions--
        hp += healed
        return healed
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
        isDashing = true
        _hitThisSwing = new Set()
        _dashTimer = dashDuration
        dashCooldown = dashCooldownTime
        view.dash(dashDuration * 1000)
        acted("dash")
        if (gameWorld) gameWorld.playDash()
    }

    function attack() {
        if (!fallen && attackCooldown <= 0 && !isAttacking) {
            isAttacking = true
            _swingTimer = attackDuration + Balance.knight.swingFade
            _hitThisSwing = new Set()
            attackCooldown = attackCooldownTime
            view.swing()
            acted("attack")
            if (!isDashing && gameWorld) gameWorld.playSwordSwing()
            console.log("[Player] Attack! Facing:", facingAngle.toFixed(0), "degrees")
        }
    }
}
