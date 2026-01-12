import QtQuick
import Box2D
import Clayground.Physics

PhysicsItem {
    id: player

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
    readonly property real attackDuration: 0.25  // Visual swing duration
    readonly property real attackCooldownTime: 0.5
    readonly property real attackRange: 2.0  // World units
    readonly property real attackArcAngle: 60  // Degrees from facing direction

    // Movement - direct velocity binding (like topdown demo)
    linearVelocity.x: moveX * maxSpeed
    linearVelocity.y: moveY * maxSpeed

    // Attack cooldown timer
    Timer {
        id: cooldownTimer
        interval: 50
        repeat: true
        running: attackCooldown > 0
        onTriggered: {
            attackCooldown = Math.max(0, attackCooldown - interval / 1000)
        }
    }

    // Visual: Steel Blue square (Knight)
    Rectangle {
        id: visual
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        color: "#4A90A4"  // Steel Blue

        // Inner glow effect
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.7
            height: parent.height * 0.7
            color: "#5BA0B4"
            opacity: 0.5
        }
    }

    // Direction indicator line
    Rectangle {
        id: aimLine
        width: parent.width * 0.8
        height: 2
        color: "#7AB8D4"
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.horizontalCenter
        rotation: -facingAngle
        transformOrigin: Item.Left
    }

    // Attack swing visualization
    Canvas {
        id: attackArc
        anchors.centerIn: parent
        width: parent.width * 4
        height: parent.height * 4
        visible: isAttacking
        rotation: -facingAngle  // Canvas 0 = right, rotate to match facing

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

            // Draw sword blade (thick line at leading edge)
            ctx.beginPath()
            ctx.moveTo(centerX + innerRadius * Math.cos(currentAngle),
                       centerY + innerRadius * Math.sin(currentAngle))
            ctx.lineTo(centerX + radius * Math.cos(currentAngle),
                       centerY + radius * Math.sin(currentAngle))
            ctx.strokeStyle = "rgba(122, 184, 212, " + swingOpacity + ")"
            ctx.lineWidth = 4
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

            // Hit detection at mid-swing
            ScriptAction {
                script: hitEnemiesInArc()
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

    // Circular collider (smaller than visual to avoid corner snagging)
    fixtures: [
        Circle {
            id: collider
            radius: player.width * 0.35  // 70% of half-width
            x: player.width / 2
            y: player.height / 2
            density: 1.0
            friction: 0.0
            restitution: 0.0

            onBeginContact: (other) => player.onCollision(other)
        },
        // Attack range sensor - detects enemies in melee range
        Circle {
            id: attackSensor
            radius: attackRange * pixelPerUnit
            x: player.width / 2
            y: player.height / 2
            sensor: true  // Non-physical, detection only

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

    function onCollision(other) {
        // Handle collision with enemies
    }

    // Check if an enemy is within the attack arc
    function isInAttackArc(enemy) {
        let dx = enemy.xWu - xWu
        let dy = enemy.yWu - yWu
        let angleToEnemy = Math.atan2(-dy, dx) * 180 / Math.PI

        // Normalize angle difference to -180 to 180
        let angleDiff = angleToEnemy - facingAngle
        while (angleDiff > 180) angleDiff -= 360
        while (angleDiff < -180) angleDiff += 360

        return Math.abs(angleDiff) <= attackArcAngle
    }

    // Deal damage to enemies in attack arc
    function hitEnemiesInArc() {
        let hitCount = 0
        for (let enemy of enemiesInRange) {
            if (enemy && !enemy.destroyed && isInAttackArc(enemy)) {
                enemy.takeDamage(atk)
                hitCount++
                console.log("[Player] Hit enemy for", atk, "damage!")
            }
        }
        return hitCount
    }

    function takeDamage(amount) {
        let finalDamage = Math.max(1, amount - def)
        if (isBlocking) {
            finalDamage = Math.floor(finalDamage * 0.3)
        }
        hp = Math.max(0, hp - finalDamage)
        // TODO: Trigger hit flash animation
    }

    function attack() {
        if (attackCooldown <= 0 && !isAttacking) {
            isAttacking = true
            attackCooldown = attackCooldownTime
            attackArc.requestPaint()
            attackAnimation.restart()
            console.log("[Player] Attack! Facing:", facingAngle.toFixed(0), "degrees")
        }
    }
}
