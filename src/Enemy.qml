import QtQuick
import Box2D
import Clayground.Physics
import Clayground.Behavior

PhysicsItem {
    id: enemy
    objectName: "enemy"

    property var gameWorld: null

    Component.onCompleted: {
        console.log("[Enemy] Created - xWu:", xWu, "yWu:", yWu)
        _spawnXWu = xWu
        _spawnYWu = yWu
    }

    property bool destroyed: false

    widthWu: 0.8
    heightWu: 0.8

    bodyType: Body.Dynamic
    fixedRotation: true
    gravityScale: 0

    property alias categories: collider.categories
    property alias collidesWith: collider.collidesWith
    property alias sensor: collider.sensor

    // AI target
    property var target: null

    // Tier: 0=weak, 1=normal, 2=tough
    property int tier: 1
    property string enemyType: "grunt"  // "grunt", "guardian", or "spitter"
    property real facingAngle: 0          // Guardian tracks player direction
    readonly property real shieldArc: 60  // ±60 degrees frontal shield
    readonly property real shieldRotSpeed: 120  // Degrees per second

    // Stats
    readonly property real chaseSpeed: enemyType === "spitter" ? 2.4 : 4.0
    readonly property real patrolSpeed: enemyType === "spitter" ? 0.9 : 1.5
    property real _lungeSpeed: 0  // Calculated per attack
    readonly property real windUpSpeed: 4.0
    readonly property real windUpDuration: 0.3
    readonly property real lungeDuration: 0.35
    readonly property real lungeRange: 2.0
    property int hp: 30
    property int maxHp: 30
    property int atk: 10
    property int def: 2

    // Spitter-specific
    readonly property real preferredDist: 5.0   // Distance to maintain from player
    readonly property real shootRange: 8.0      // Max range to start shooting
    readonly property real kiteSpeed: 3.0       // Retreat speed
    readonly property real shootCooldown: 1.2
    property real _shootTimer: 0

    // Combat state
    property real attackCooldown: 0
    property real _attackTimer: 0
    property real _dirToTargetX: 0
    property real _dirToTargetY: 0
    property bool parryWindow: false

    // AI state: patrol, chase, telegraph, lunge, stagger, recovery, kite, shoot
    property string aiState: "patrol"

    // Internal state
    property real _spawnXWu: 0
    property real _spawnYWu: 0
    property var _lastKnownTargetPos: null
    property real _pathRecalcTimer: 0

    // Tough enemy glow ring
    Rectangle {
        visible: tier === 2
        anchors.centerIn: parent
        width: parent.width * 1.4
        height: parent.height * 1.4
        radius: width * 0.5
        color: "transparent"
        border.color: "#CC6644"
        border.width: 2
        opacity: 0.6
    }

    // Visual
    Rectangle {
        id: visual
        anchors.centerIn: parent
        anchors.fill: parent
        radius: width * .5
        opacity: tier === 0 ? 0.6 : 1.0
        color: {
            let isSpitter = enemyType === "spitter"
            let base
            switch (enemy.aiState) {
            case "patrol": base = isSpitter ? "#6B8E4A" : "#8B3A3A"; break
            case "chase": base = isSpitter ? "#7BA854" : "#CC4444"; break
            case "kite": base = "#8EBB5A"; break
            case "shoot": base = "#AADD66"; break
            case "telegraph": base = "#FF8C00"; break
            case "lunge": base = "#FF4444"; break
            case "stagger": base = "#666666"; break
            default: base = isSpitter ? "#6B8E4A" : "#8B3A3A"
            }
            return tier === 0 ? Qt.darker(base, 1.4) : tier === 2 ? Qt.lighter(base, 1.2) : base
        }
        Behavior on color { ColorAnimation { duration: 100 } }

        Canvas {
            id: goblinIcon
            anchors.centerIn: parent
            width: parent.width * 0.7
            height: parent.height * 0.7
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width, h = height
                var dark = Qt.darker(visual.color, 1.8)
                ctx.fillStyle = dark
                ctx.strokeStyle = dark
                ctx.lineWidth = w * 0.06

                if (enemyType === "spitter") {
                    // Big central eye
                    ctx.beginPath()
                    ctx.arc(w * 0.5, h * 0.4, w * 0.22, 0, Math.PI * 2)
                    ctx.fill()
                    // Pupil (lighter)
                    ctx.fillStyle = visual.color
                    ctx.beginPath()
                    ctx.arc(w * 0.5, h * 0.4, w * 0.1, 0, Math.PI * 2)
                    ctx.fill()
                    // Open mouth (spitting)
                    ctx.fillStyle = dark
                    ctx.beginPath()
                    ctx.arc(w * 0.5, h * 0.72, w * 0.14, 0, Math.PI * 2)
                    ctx.fill()
                } else {
                    // Pointy ears
                    ctx.beginPath()
                    ctx.moveTo(w * 0.05, h * 0.45)
                    ctx.lineTo(w * -0.05, h * 0.05)
                    ctx.lineTo(w * 0.25, h * 0.35)
                    ctx.closePath()
                    ctx.fill()

                    ctx.beginPath()
                    ctx.moveTo(w * 0.95, h * 0.45)
                    ctx.lineTo(w * 1.05, h * 0.05)
                    ctx.lineTo(w * 0.75, h * 0.35)
                    ctx.closePath()
                    ctx.fill()

                    // Eyes
                    ctx.beginPath()
                    ctx.arc(w * 0.33, h * 0.42, w * 0.09, 0, Math.PI * 2)
                    ctx.fill()
                    ctx.beginPath()
                    ctx.arc(w * 0.67, h * 0.42, w * 0.09, 0, Math.PI * 2)
                    ctx.fill()

                    // Jagged mouth
                    ctx.beginPath()
                    ctx.moveTo(w * 0.25, h * 0.7)
                    ctx.lineTo(w * 0.35, h * 0.62)
                    ctx.lineTo(w * 0.45, h * 0.72)
                    ctx.lineTo(w * 0.55, h * 0.62)
                    ctx.lineTo(w * 0.65, h * 0.72)
                    ctx.lineTo(w * 0.75, h * 0.62)
                    ctx.stroke()
                }
            }

            Connections {
                target: visual
                function onColorChanged() { goblinIcon.requestPaint() }
            }
        }
    }

    Rectangle {
        id: hitFlash
        anchors.fill: visual
        color: "white"
        opacity: 0
        SequentialAnimation {
            id: hitFlashAnimation
            PropertyAnimation {
                target: hitFlash; property: "opacity"
                from: 0.8; to: 0; duration: 150
                easing.type: Easing.OutQuad
            }
        }
    }

    // Parry window flash
    Rectangle {
        id: parryFlash
        anchors.fill: visual
        radius: visual.radius
        color: "white"
        opacity: parryWindow ? 0.4 : 0
        Behavior on opacity { NumberAnimation { duration: 50 } }
    }

    // Stagger wobble animation
    SequentialAnimation {
        id: staggerWobble
        loops: Animation.Infinite
        PropertyAnimation { target: enemy; property: "rotation"; to: 10; duration: 80 }
        PropertyAnimation { target: enemy; property: "rotation"; to: -10; duration: 80 }
    }

    // Health bar
    Rectangle {
        id: healthBarBg
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 4
        width: parent.width * 1.2
        height: 4
        color: "#333333"
        visible: hp < maxHp

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * (hp / maxHp)
            color: hp > maxHp * 0.5 ? "#22CC22" : (hp > maxHp * 0.25 ? "#CCCC22" : "#CC2222")
            Behavior on width { NumberAnimation { duration: 100 } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    // Guardian shield arc
    Canvas {
        id: guardianShield
        visible: enemyType === "guardian" && aiState !== "stagger"
        readonly property real shieldSize: enemy.width * 0.8
        readonly property real orbitRadius: enemy.width * 0.5
        readonly property real angleRad: facingAngle * Math.PI / 180
        width: shieldSize
        height: shieldSize
        x: enemy.width / 2 - width / 2 + Math.cos(angleRad) * orbitRadius
        y: enemy.height / 2 - height / 2 - Math.sin(angleRad) * orbitRadius
        rotation: -facingAngle
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height
            ctx.beginPath()
            ctx.arc(w / 2, h / 2, w * 0.4, -Math.PI * 0.4, Math.PI * 0.4)
            ctx.strokeStyle = "#CC6644"
            ctx.lineWidth = w * 0.25
            ctx.stroke()
        }

        Connections {
            target: enemy
            function onFacingAngleChanged() { guardianShield.requestPaint() }
        }
        Component.onCompleted: requestPaint()
    }

    // Mechanics debug hint
    Text {
        visible: gameWorld ? gameWorld.debugMechanics : false
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: hp < maxHp ? 14 : 6
        text: enemyType === "guardian" ? "Flank/Push" : (enemyType === "spitter" ? "Close/Shield" : "Block/Counter")
        color: enemyType === "guardian" ? "#CC6644" : (enemyType === "spitter" ? "#6B8E4A" : "#AAAAAA")
        font.pixelSize: 9
        font.bold: true
        style: Text.Outline
        styleColor: "#000000"
    }

    fixtures: [
        Circle {
            id: collider
            radius: enemy.width * 0.35
            x: enemy.width / 2
            y: enemy.height / 2
            density: 1.0
            friction: 0.0
            restitution: 0.0
            onBeginContact: (other) => enemy.onCollision(other)
        }
    ]

    // FollowPath for both patrol and chase navigation
    // Manage FollowPath.running imperatively — a declarative binding gets
    // broken by FollowPath's internal "running = false" on path completion.
    onAiStateChanged: followPath.running = (aiState === "patrol" || aiState === "chase")
    onEnemyTypeChanged: goblinIcon.requestPaint()

    FollowPath {
        id: followPath
        world: enemy.gameWorld
        actor: enemy
        debug: gameWorld ? gameWorld.debugBehavior : false
        desiredSpeed: enemy.aiState === "chase" ? enemy.chaseSpeed : enemy.patrolSpeed
        repeat: enemy.aiState === "patrol"
        onArrived: {
            if (enemy.aiState === "chase") {
                if (target && gameWorld && gameWorld.hasLineOfSight(xWu, yWu, target.xWu, target.yWu)) {
                    _recalcChasePath()
                    followPath.running = true
                } else {
                    console.log("[Enemy] Lost target, returning to patrol")
                    aiState = "patrol"
                    _setupPatrol()
                }
            }
        }
    }

    Timer {
        id: aiTimer
        interval: 100
        running: true
        repeat: true
        onTriggered: updateAI(interval / 1000.0)
    }

    function updateAI(dt) {
        if (!target || !gameWorld) {
            aiState = "patrol"
            return
        }

        if (attackCooldown > 0) attackCooldown -= dt
        if (_attackTimer > 0) _attackTimer -= dt
        if (_shootTimer > 0) _shootTimer -= dt
        _pathRecalcTimer -= dt

        let dx = target.xWu - xWu
        let dy = target.yWu - yWu
        let dist = Math.sqrt(dx * dx + dy * dy)
        let canSee = gameWorld.hasLineOfSight(xWu, yWu, target.xWu, target.yWu)

        switch (aiState) {
        case "patrol":
            if (canSee) {
                console.log("[Enemy] Spotted player!")
                aiState = "chase"
                _recalcChasePath()
            } else if (followPath.wpsWu.length === 0) {
                _setupPatrol()
            } else if (!followPath.running) {
                followPath.running = true
            }
            break

        case "chase":
            if (enemyType === "spitter") {
                // Spitter transitions to kite when in range with LOS
                if (canSee && dist < shootRange) {
                    aiState = "kite"
                } else if (_pathRecalcTimer <= 0) {
                    _recalcChasePath()
                    _pathRecalcTimer = 1.0
                }
            } else {
                if (enemyType === "guardian") _lerpFacing(dy, dx, dt)
                if (dist < lungeRange && canSee) {
                    // Capture direction to target for wind-up/lunge
                    let len = Math.max(0.01, dist)
                    _dirToTargetX = dx / len
                    _dirToTargetY = dy / len
                    _attackTimer = windUpDuration
                    aiState = "telegraph"
                } else if (_pathRecalcTimer <= 0) {
                    _lastKnownTargetPos = Qt.point(target.xWu, target.yWu)
                    _recalcChasePath()
                    _pathRecalcTimer = 1.0
                }
            }
            break

        case "kite":
            // Spitter: maintain distance, retreat if too close, advance if too far
            if (!canSee) {
                aiState = "chase"
                _recalcChasePath()
                break
            }
            {
                let len = Math.max(0.01, dist)
                let ndx = dx / len
                let ndy = dy / len
                if (dist < preferredDist * 0.7) {
                    // Too close — retreat
                    body.linearVelocity = Qt.point(
                        -ndx * kiteSpeed, ndy * kiteSpeed)
                } else if (dist > preferredDist * 1.3) {
                    // Too far — approach
                    body.linearVelocity = Qt.point(
                        ndx * chaseSpeed, -ndy * chaseSpeed)
                } else {
                    // Good range — strafe slightly
                    body.linearVelocity = Qt.point(
                        -ndy * patrolSpeed, -ndx * patrolSpeed)
                }
            }
            // Shoot when cooldown ready
            if (_shootTimer <= 0 && dist <= shootRange) {
                _shootTimer = shootCooldown
                _attackTimer = 0.3  // Brief telegraph
                let len = Math.max(0.01, dist)
                _dirToTargetX = dx / len
                _dirToTargetY = dy / len
                aiState = "shoot"
            }
            break

        case "shoot":
            // Brief telegraph then fire
            body.linearVelocity = Qt.point(0, 0)
            if (_attackTimer <= 0) {
                fireProjectile()
                aiState = "kite"
            }
            break

        case "telegraph":
            // Pull backward (wind-up) — negate Y for world-to-screen
            body.linearVelocity = Qt.point(
                -_dirToTargetX * windUpSpeed,
                _dirToTargetY * windUpSpeed)
            if (_attackTimer <= 0) {
                // Calculate lunge speed to reach the player
                let lungeDx = target.xWu - xWu
                let lungeDy = target.yWu - yWu
                let lungeDist = Math.sqrt(lungeDx * lungeDx + lungeDy * lungeDy)
                let len = Math.max(0.01, lungeDist)
                _dirToTargetX = lungeDx / len
                _dirToTargetY = lungeDy / len
                _lungeSpeed = lungeDist / lungeDuration
                _attackTimer = lungeDuration
                aiState = "lunge"
            }
            break

        case "lunge":
            // Dash forward — negate Y for world-to-screen
            body.linearVelocity = Qt.point(
                _dirToTargetX * _lungeSpeed,
                -_dirToTargetY * _lungeSpeed)
            parryWindow = _attackTimer < 0.15
            if (_attackTimer <= 0) {
                parryWindow = false
                body.linearVelocity = Qt.point(0, 0)
                performAttack()
                aiState = "recovery"
                attackCooldown = 0.8
            }
            break

        case "stagger":
            body.linearVelocity = Qt.point(0, 0)
            if (_attackTimer <= 0) {
                staggerWobble.stop()
                enemy.rotation = 0
                aiState = "chase"
            }
            break

        case "recovery":
            body.linearVelocity = Qt.point(0, 0)
            if (enemyType === "guardian") _lerpFacing(dy, dx, dt)
            if (attackCooldown <= 0)
                aiState = "chase"
            break
        }
    }

    function _lerpFacing(dy, dx, dt) {
        let targetAngle = Math.atan2(dy, dx) * 180 / Math.PI
        let diff = targetAngle - facingAngle
        while (diff > 180) diff -= 360
        while (diff < -180) diff += 360
        let maxRot = shieldRotSpeed * dt
        facingAngle += Math.max(-maxRot, Math.min(maxRot, diff))
    }

    function _recalcChasePath() {
        if (!target || !gameWorld) return
        let path = gameWorld.findPath(xWu, yWu, target.xWu, target.yWu)
        if (path.length > 1) {
            // Skip first waypoint (our current cell)
            followPath.wpsWu = path.slice(1)
        } else if (path.length === 1) {
            followPath.wpsWu = path
        }
        // If no path found, keep current path (or stop)
    }

    function _setupPatrol() {
        // Patrol near spawn point: 2-3 waypoints in a small area
        let offsets = [
            Qt.point(_spawnXWu - 2, _spawnYWu),
            Qt.point(_spawnXWu + 2, _spawnYWu),
            Qt.point(_spawnXWu, _spawnYWu + 2),
            Qt.point(_spawnXWu, _spawnYWu - 2)
        ]
        // Pick 2 random reachable offsets
        let wps = []
        for (let p of offsets) {
            if (gameWorld) {
                let gx = Math.floor(p.x / gameWorld.cellSize)
                let gy = Math.floor(p.y / gameWorld.cellSize)
                if (gx >= 0 && gx < gameWorld.gridWidth &&
                    gy >= 0 && gy < gameWorld.gridHeight &&
                    gameWorld.grid[gy][gx] !== gameWorld.cellWall) {
                    wps.push(p)
                }
            }
            if (wps.length >= 2) break
        }
        if (wps.length >= 2)
            followPath.wpsWu = wps
    }

    function performAttack() {
        if (target && target.takeDamage) {
            let dx = target.xWu - xWu
            let dy = target.yWu - yWu
            let dist = Math.sqrt(dx * dx + dy * dy)
            if (dist < 1.2) {
                target.takeDamage(atk, xWu, yWu)
                if (gameWorld) gameWorld.playImpact()
                console.log("[Enemy] Lunge hit! Dealt", atk, "damage")
            }
        }
    }

    function fireProjectile() {
        if (gameWorld && gameWorld.spawnProjectile) {
            gameWorld.spawnProjectile(xWu, yWu, _dirToTargetX, _dirToTargetY, atk)
            if (gameWorld.playSpitShot) gameWorld.playSpitShot()
            console.log("[Enemy] Spitter fired projectile!")
        }
    }

    function stagger() {
        parryWindow = false
        _attackTimer = 1.0
        aiState = "stagger"
        staggerWobble.restart()
    }

    function onCollision(other) {}

    function _isShieldFacing(attackerX, attackerY) {
        let dx = attackerX - xWu
        let dy = attackerY - yWu
        let angleToAttacker = Math.atan2(dy, dx) * 180 / Math.PI
        let angleDiff = angleToAttacker - facingAngle
        while (angleDiff > 180) angleDiff -= 360
        while (angleDiff < -180) angleDiff += 360
        return Math.abs(angleDiff) <= shieldArc
    }

    function takeDamage(amount, attackerX, attackerY) {
        let finalDamage = Math.max(1, amount - def)

        // Guardian frontal shield
        let blocked = false
        if (enemyType === "guardian" && aiState !== "stagger"
            && attackerX !== undefined && _isShieldFacing(attackerX, attackerY)) {
            finalDamage = Math.floor(finalDamage * 0.3)
            blocked = true
        }

        hp = Math.max(0, hp - finalDamage)
        console.log("[Enemy] Took", finalDamage, "damage, HP:", hp, blocked ? "(blocked)" : "")
        hitFlashAnimation.restart()
        if (gameWorld) gameWorld.shake(blocked ? 0.5 : 1.5)

        // Guardian counter-attacks after blocking
        if (blocked && aiState !== "telegraph" && aiState !== "lunge") {
            if (target) {
                let dx = target.xWu - xWu
                let dy = target.yWu - yWu
                let len = Math.max(0.01, Math.sqrt(dx * dx + dy * dy))
                _dirToTargetX = dx / len
                _dirToTargetY = dy / len
                _attackTimer = windUpDuration * 0.5  // Faster counter
                aiState = "telegraph"
            }
        }

        // Getting hit while patrolling triggers chase
        if (aiState === "patrol" && target) {
            console.log("[Enemy] Hit while patrolling — chasing attacker!")
            aiState = "chase"
            _recalcChasePath()
        }

        if (hp <= 0) die()
    }

    function die() {
        console.log("[Enemy] Died!")
        if (gameWorld) {
            gameWorld.spawnDeathParticles(xWu, yWu)
            gameWorld.playDeathBurst()
        }
        destroyed = true
        destroy()
    }
}
