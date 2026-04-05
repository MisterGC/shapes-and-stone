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
    readonly property real maxSpeed: 15.0  // World units per second
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
    readonly property real blockSpeedMultiplier: 0.5
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
    property int _dashStepCount: 0
    Connections {
        target: player.world
        function onStepped() {
            let dt = 1/60.0

            if (isDashing) {
                let spd = isBlocking ? dashSpeed * blockSpeedMultiplier : dashSpeed
                player.body.linearVelocity = Qt.point(_dashDirX * spd, _dashDirY * spd)
                _dashTimer -= dt
                _dashStepCount++
                if (_dashStepCount % 2 === 0 && player.parent) {
                    afterimageComp.createObject(player.parent, {
                        x: player.x, y: player.y,
                        width: player.width, height: player.height
                    })
                }
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

    // Visual: Steel Blue circle (Knight)
    Rectangle {
        id: visual
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        color: "#4A90A4"  // Steel Blue
        radius: width * .5

        Canvas {
            anchors.centerIn: parent
            width: parent.width * 0.6
            height: parent.height * 0.6
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width, h = height
                ctx.fillStyle = "#2A6A84"
                ctx.strokeStyle = "#2A6A84"
                ctx.lineWidth = w * 0.06

                // Dome
                ctx.beginPath()
                ctx.moveTo(w * 0.15, h * 0.55)
                ctx.quadraticCurveTo(w * 0.15, h * 0.1, w * 0.5, h * 0.08)
                ctx.quadraticCurveTo(w * 0.85, h * 0.1, w * 0.85, h * 0.55)
                ctx.closePath()
                ctx.fill()

                // Visor slit
                ctx.fillStyle = "#4A90A4"
                ctx.fillRect(w * 0.2, h * 0.42, w * 0.6, h * 0.1)

                // Cheek guards
                ctx.fillStyle = "#2A6A84"
                ctx.beginPath()
                ctx.moveTo(w * 0.15, h * 0.55)
                ctx.lineTo(w * 0.15, h * 0.78)
                ctx.lineTo(w * 0.3, h * 0.88)
                ctx.lineTo(w * 0.3, h * 0.55)
                ctx.closePath()
                ctx.fill()

                ctx.beginPath()
                ctx.moveTo(w * 0.85, h * 0.55)
                ctx.lineTo(w * 0.85, h * 0.78)
                ctx.lineTo(w * 0.7, h * 0.88)
                ctx.lineTo(w * 0.7, h * 0.55)
                ctx.closePath()
                ctx.fill()

                // Nose guard
                ctx.fillRect(w * 0.46, h * 0.35, w * 0.08, h * 0.25)
            }
        }

        SequentialAnimation {
            id: dashFlash
            PropertyAnimation { target: visual; property: "opacity"; from: 0.4; to: 1.0; duration: dashDuration * 1000 }
        }

        // Parry glow
        Rectangle {
            id: parryGlowRect
            anchors.fill: parent
            radius: parent.radius
            color: "#FFD700"
            opacity: 0
        }

        SequentialAnimation {
            id: parryGlow
            PropertyAnimation { target: parryGlowRect; property: "opacity"; from: 0.6; to: 0; duration: 200 }
        }
    }

    // Shield arc visual (orbits on facing side when blocking)
    Canvas {
        id: shieldArc
        visible: isBlocking
        readonly property real shieldSize: player.width * 0.8
        readonly property real orbitRadius: player.width * 0.5
        readonly property real angleRad: facingAngle * Math.PI / 180
        width: shieldSize
        height: shieldSize
        x: player.width / 2 - width / 2 + Math.cos(angleRad) * orbitRadius
        y: player.height / 2 - height / 2 - Math.sin(angleRad) * orbitRadius
        rotation: -facingAngle
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height
            ctx.beginPath()
            ctx.arc(w / 2, h / 2, w * 0.4, -Math.PI * 0.4, Math.PI * 0.4)
            ctx.strokeStyle = "#7AB8D4"
            ctx.lineWidth = w * 0.25
            ctx.stroke()
        }

        onVisibleChanged: if (visible) requestPaint()
    }

    // Dash cooldown ring
    Canvas {
        id: dashCooldownRing
        anchors.centerIn: parent
        width: parent.width * 1.3
        height: parent.height * 1.3
        visible: dashCooldown > 0
        opacity: 0.4

        property real progress: 1.0 - (dashCooldown / dashCooldownTime)

        onProgressChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = width / 2, cy = height / 2
            var r = width * 0.45
            var startAngle = -Math.PI / 2
            var endAngle = startAngle + progress * Math.PI * 2
            ctx.beginPath()
            ctx.arc(cx, cy, r, startAngle, endAngle)
            ctx.strokeStyle = "#AAAAAA"
            ctx.lineWidth = 2
            ctx.stroke()
        }
    }

    // Dash afterimage component

    Component {
        id: afterimageComp
        Rectangle {
            id: _ghost
            radius: width * 0.5
            color: "#7AB8D4"
            opacity: 0.5
            SequentialAnimation {
                running: true
                ParallelAnimation {
                    NumberAnimation { target: _ghost; property: "opacity"; to: 0; duration: 200 }
                    NumberAnimation { target: _ghost; property: "scale"; to: 0.5; duration: 200 }
                }
                ScriptAction { script: _ghost.destroy() }
            }
        }
    }

    // Direction indicator arrowhead (orbits around player)
    Canvas {
        id: aimArrow
        opacity: 0.5
        readonly property real arrowSize: player.width * 0.3
        readonly property real orbitRadius: player.width * 0.7
        readonly property real angleRad: facingAngle * Math.PI / 180
        width: arrowSize
        height: arrowSize
        x: player.width / 2 - width / 2 + Math.cos(angleRad) * orbitRadius
        y: player.height / 2 - height / 2 - Math.sin(angleRad) * orbitRadius
        rotation: -facingAngle
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height
            ctx.beginPath()
            ctx.moveTo(w, h * 0.5)
            ctx.lineTo(0, 0)
            ctx.lineTo(w * 0.3, h * 0.5)
            ctx.lineTo(0, h)
            ctx.closePath()
            ctx.fillStyle = "#7AB8D4"
            ctx.fill()
        }
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

    // Attack swing visualization
    // Reparented to avoid inflating PhysicsItem's childrenRect.
    Canvas {
        id: attackArc
        parent: player.parent
        x: player.x + player.width/2 - width/2
        y: player.y + player.height/2 - height/2
        width: player.width * 4
        height: player.height * 4
        visible: isAttacking
        rotation: -facingAngle

        // Swing progress: 0 = start, 1 = end
        property real swingProgress: 0
        property real swingOpacity: 0.9

        onSwingProgressChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var centerX = width / 2
            var centerY = height / 2
            var radius = width * 0.4
            var innerRadius = width * 0.15

            // Swing range 120 degrees
            var swingRange = Math.PI * 0.67
            var startAngle = -swingRange / 2
            var currentAngle = startAngle + (swingProgress * swingRange)

            // Draw motion trails (3 curved arcs = "cut air" effect)
            var arcSpan = 0.18  // ~10 degrees per arc
            for (var i = 3; i >= 1; i--) {
                var trailOffset = currentAngle - (i * 0.25)  // Offset behind blade
                var trailRadius = innerRadius + (radius - innerRadius) * (i / 4)  // Varying radii
                var trailOpacity = swingOpacity * (1.0 - i * 0.25)
                ctx.beginPath()
                ctx.arc(centerX, centerY, trailRadius, trailOffset - arcSpan/2, trailOffset + arcSpan/2)
                ctx.strokeStyle = "rgba(122, 184, 212, " + trailOpacity + ")"
                ctx.lineWidth = 2
                ctx.stroke()
            }

            // Draw sword blade at leading edge
            var bladeLen = radius - innerRadius
            var bladeW = bladeLen * 0.15
            var bx = centerX + innerRadius * Math.cos(currentAngle)
            var by = centerY + innerRadius * Math.sin(currentAngle)
            var tx = centerX + radius * Math.cos(currentAngle)
            var ty = centerY + radius * Math.sin(currentAngle)
            var perpX = -Math.sin(currentAngle)
            var perpY = Math.cos(currentAngle)

            ctx.beginPath()
            // Tip
            ctx.moveTo(tx, ty)
            // Right shoulder
            ctx.lineTo(centerX + (innerRadius + bladeLen * 0.7) * Math.cos(currentAngle) + perpX * bladeW,
                       centerY + (innerRadius + bladeLen * 0.7) * Math.sin(currentAngle) + perpY * bladeW)
            // Right base
            ctx.lineTo(bx + perpX * bladeW * 0.6, by + perpY * bladeW * 0.6)
            // Cross-guard right
            ctx.lineTo(bx + perpX * bladeW * 0.9, by + perpY * bladeW * 0.9)
            // Cross-guard left
            ctx.lineTo(bx - perpX * bladeW * 0.9, by - perpY * bladeW * 0.9)
            // Left base
            ctx.lineTo(bx - perpX * bladeW * 0.6, by - perpY * bladeW * 0.6)
            // Left shoulder
            ctx.lineTo(centerX + (innerRadius + bladeLen * 0.7) * Math.cos(currentAngle) - perpX * bladeW,
                       centerY + (innerRadius + bladeLen * 0.7) * Math.sin(currentAngle) - perpY * bladeW)
            ctx.closePath()
            ctx.fillStyle = "rgba(90, 154, 180, " + swingOpacity + ")"
            ctx.fill()
            ctx.strokeStyle = "rgba(122, 184, 212, " + swingOpacity + ")"
            ctx.lineWidth = 1.5
            ctx.stroke()

            // Center ridge
            ctx.beginPath()
            ctx.moveTo(bx, by)
            ctx.lineTo(tx, ty)
            ctx.strokeStyle = "rgba(58, 138, 154, " + swingOpacity * 0.8 + ")"
            ctx.lineWidth = 1
            ctx.stroke()
        }

        // Swing animation
        SequentialAnimation {
            id: attackAnimation

            // First half of swing (wind up)
            PropertyAnimation {
                target: attackArc
                property: "swingProgress"
                from: 0
                to: 0.5
                duration: attackDuration * 500
                easing.type: Easing.OutQuad
            }

            // Second half of swing (follow through)
            PropertyAnimation {
                target: attackArc
                property: "swingProgress"
                from: 0.5
                to: 1
                duration: attackDuration * 500
                easing.type: Easing.OutQuad
            }

            // Fade out
            PropertyAnimation {
                target: attackArc
                property: "swingOpacity"
                from: 0.9
                to: 0
                duration: 100
            }

            ScriptAction {
                script: {
                    isAttacking = false
                    attackArc.swingProgress = 0
                    attackArc.swingOpacity = 0.9
                }
            }
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
                    parryGlow.restart()
                    if (gameWorld) {
                        gameWorld.playImpact()
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
        if (gameWorld) {
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
        _dashStepCount = 0
        dashCooldown = dashCooldownTime
        dashFlash.restart()
        if (gameWorld) gameWorld.playDash()
    }

    function attack() {
        if (attackCooldown <= 0 && !isAttacking) {
            isAttacking = true
            _hitThisSwing = new Set()
            attackCooldown = attackCooldownTime
            attackArc.requestPaint()
            attackAnimation.restart()
            if (!isDashing && gameWorld) gameWorld.playSwordSwing()
            console.log("[Player] Attack! Facing:", facingAngle.toFixed(0), "degrees")
        }
    }
}
