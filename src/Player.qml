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

    // Stats from concept doc
    readonly property real maxSpeed: 7.5  // World units per second
    property int hp: 120
    property int maxHp: 120
    property int atk: 15
    property int def: 5
    property int mana: 40
    property int maxMana: 40

    // Combat state
    property bool isAttacking: false
    property bool isBlocking: false
    property real attackCooldown: 0
    readonly property real blockSpeedMultiplier: 0.4
    readonly property real pushForce: 20.0          // Knockback velocity for dash-push
    readonly property real attackDuration: 0.25  // Visual swing duration
    readonly property real attackCooldownTime: 0.5
    readonly property real attackRange: 2.0  // World units
    readonly property real attackArcAngle: 60  // Degrees from facing direction

    // Dash state
    property bool isDashing: false
    property real dashCooldown: 0
    readonly property real dashSpeed: 40.0
    readonly property real dashDuration: 0.15
    readonly property real dashCooldownTime: 0.8
    property real _dashTimer: 0
    property real _dashDirX: 0
    property real _dashDirY: 0

    // Movement - set velocity every physics step so collision response
    // doesn't permanently zero a component while the key is held
    Connections {
        target: player.world
        function onStepped() {
            let dt = 1/60.0

            if (isDashing) {
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

    // Cooldown timer (attack + dash)
    Timer {
        id: cooldownTimer
        interval: 50
        repeat: true
        running: attackCooldown > 0 || dashCooldown > 0
        onTriggered: {
            let dt = interval / 1000
            attackCooldown = Math.max(0, attackCooldown - dt)
            dashCooldown = Math.max(0, dashCooldown - dt)
        }
    }

    // A moment others should see: "attack", "dash", "parry" or "hurt".
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
        onSwingFinished: player.isAttacking = false
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
            radius: player.width * 1.5
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

    // Track enemies currently in attack range
    property var enemiesInRange: new Set()
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
        for (let enemy of enemiesInRange) {
            if (enemy && !enemy.destroyed && !_hitThisSwing.has(enemy) && isInAttackArc(enemy)) {
                let parried = enemy.parryWindow
                let dmg = isBlocking ? Math.floor(atk * 0.85)
                        : isDashing ? Math.floor(atk * 1.5) : atk
                if (parried) dmg = atk * 2
                enemy.takeDamage(dmg, xWu, yWu)
                _hitThisSwing.add(enemy)
                hitCount++
                if (parried) {
                    enemy.stagger()
                    attackCooldown = 0
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
        for (let enemy of enemiesInRange) {
            if (enemy && !enemy.destroyed && !_hitThisSwing.has(enemy)) {
                let dx = enemy.xWu - xWu
                let dy = enemy.yWu - yWu
                let len = Math.sqrt(dx * dx + dy * dy)
                if (len < 0.01) continue
                enemy.body.linearVelocity = Qt.point(
                    (dx / len) * pushForce,
                    -(dy / len) * pushForce)  // Negate Y for screen coords
                _hitThisSwing.add(enemy)
                // Shield-push breaks guardian guard
                if (enemy.enemyType === "guardian") enemy.stagger()
                if (gameWorld) gameWorld.playImpact()
                console.log("[Player] Pushed enemy!" + (enemy.enemyType === "guardian" ? " (guard broken!)" : ""))
            }
        }
    }

    readonly property real shieldArcAngle: 60  // ±60 degrees from facing

    function isShieldFacing(attackerX, attackerY) {
        let dx = attackerX - xWu
        let dy = attackerY - yWu
        let angleToAttacker = Math.atan2(dy, dx) * 180 / Math.PI
        let angleDiff = angleToAttacker - facingAngle
        while (angleDiff > 180) angleDiff -= 360
        while (angleDiff < -180) angleDiff += 360
        return Math.abs(angleDiff) <= shieldArcAngle
    }

    function getShieldWorldPos() {
        let rad = facingAngle * Math.PI / 180
        return { x: xWu + Math.cos(rad) * 0.5, y: yWu + Math.sin(rad) * 0.5 }
    }

    function takeDamage(amount, attackerX, attackerY) {
        if (isDashing) return  // Invulnerable during dash
        let finalDamage = Math.max(1, amount - def)
        let blocked = isBlocking && isShieldFacing(attackerX, attackerY)
        if (blocked) {
            finalDamage = Math.floor(finalDamage * 0.3)
            if (gameWorld) gameWorld.playImpact()
        }
        hp = Math.max(0, hp - finalDamage)
        if (!blocked) {
            view.hurt()
            acted("hurt")
        }
        if (gameWorld) {
            if (gameWorld.impact)
                gameWorld.impact(blocked ? "playerBlocked" : "playerHit", xWu, yWu,
                                 xWu - attackerX, yWu - attackerY)
            else
                gameWorld.shake(blocked ? 1 : 3)
            gameWorld.spawnDamageNumber(xWu, yWu, finalDamage, blocked ? "#4A90A4" : "#FF4444")
        }
    }

    function dash() {
        if (dashCooldown > 0 || isDashing) return
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
        if (attackCooldown <= 0 && !isAttacking) {
            isAttacking = true
            _hitThisSwing = new Set()
            attackCooldown = attackCooldownTime
            view.swing()
            acted("attack")
            if (!isDashing && gameWorld) gameWorld.playSwordSwing()
            console.log("[Player] Attack! Facing:", facingAngle.toFixed(0), "degrees")
        }
    }
}
