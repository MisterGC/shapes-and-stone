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

    // Stats
    readonly property real chaseSpeed: 8.0
    readonly property real patrolSpeed: 3.0
    property int hp: 20
    property int maxHp: 20
    property int atk: 10
    property int def: 2

    // Combat state
    property real attackCooldown: 0
    property real telegraphTimer: 0

    // AI state: patrol, chase, telegraph, attack, recovery
    property string aiState: "patrol"

    // Internal state
    property real _spawnXWu: 0
    property real _spawnYWu: 0
    property var _lastKnownTargetPos: null
    property real _pathRecalcTimer: 0

    // Visual
    Rectangle {
        id: visual
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        color: {
            switch (enemy.aiState) {
            case "patrol": return "#8B3A3A"
            case "chase": return "#CC4444"
            case "telegraph": return "#FF8C00"
            default: return "#8B3A3A"
            }
        }
        Behavior on color { ColorAnimation { duration: 100 } }
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
        if (telegraphTimer > 0) telegraphTimer -= dt
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
            if (dist < 1.5) {
                aiState = "telegraph"
                telegraphTimer = 0.3
            } else if (_pathRecalcTimer <= 0) {
                _lastKnownTargetPos = Qt.point(target.xWu, target.yWu)
                _recalcChasePath()
                _pathRecalcTimer = 1.0
            }
            break

        case "telegraph":
            if (telegraphTimer <= 0) {
                aiState = "attack"
                performAttack()
            }
            break

        case "attack":
            aiState = "recovery"
            attackCooldown = 0.8
            break

        case "recovery":
            if (attackCooldown <= 0)
                aiState = "chase"
            break
        }
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
            if (dist < 1.5) {
                target.takeDamage(atk)
                console.log("[Enemy] Attack hit! Dealt", atk, "damage")
            }
        }
    }

    function onCollision(other) {}

    function takeDamage(amount) {
        let finalDamage = Math.max(1, amount - def)
        hp = Math.max(0, hp - finalDamage)
        console.log("[Enemy] Took", finalDamage, "damage, HP:", hp)
        hitFlashAnimation.restart()

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
        destroyed = true
        destroy()
    }
}
