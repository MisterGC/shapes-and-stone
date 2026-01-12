import QtQuick
import Box2D
import Clayground.Physics
import Clayground.Behavior

PhysicsItem {
    id: enemy
    objectName: "enemy"  // For detection by player attack sensor

    // Reference to game world (set when spawned)
    property var gameWorld: null

    Component.onCompleted: {
        console.log("[Enemy] Created - xWu:", xWu, "yWu:", yWu)
    }

    // Track if destroyed (for cleanup)
    property bool destroyed: false

    // Visual size
    widthWu: 0.8
    heightWu: 0.8

    // Physics config - Dynamic for collision response
    bodyType: Body.Dynamic
    fixedRotation: true
    gravityScale: 0     // No gravity effect (top-down)

    // Collision setup
    property alias categories: collider.categories
    property alias collidesWith: collider.collidesWith
    property alias sensor: collider.sensor

    // AI target
    property var target: null

    // Stats (Grunt from concept doc)
    readonly property real chaseSpeed: 8.0
    property int hp: 20
    property int maxHp: 20
    property int atk: 10
    property int def: 2

    // Combat state
    property real attackCooldown: 0
    property real telegraphTimer: 0

    // AI state
    property string aiState: "idle"  // idle, chase, telegraph, attack, recovery

    // Visual: Dull Red square (Grunt)
    Rectangle {
        id: visual
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        color: aiState === "telegraph" ? "#FF8C00" : "#8B3A3A"

        Behavior on color { ColorAnimation { duration: 100 } }
    }

    // Hit flash overlay
    Rectangle {
        id: hitFlash
        anchors.fill: visual
        color: "white"
        opacity: 0

        SequentialAnimation {
            id: hitFlashAnimation
            PropertyAnimation {
                target: hitFlash
                property: "opacity"
                from: 0.8
                to: 0
                duration: 150
                easing.type: Easing.OutQuad
            }
        }
    }

    // Floating health bar (Warcraft 3 style)
    Rectangle {
        id: healthBarBg
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 4
        width: parent.width * 1.2
        height: 4
        color: "#333333"
        visible: hp < maxHp  // Only show when damaged

        Rectangle {
            id: healthBarFill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * (hp / maxHp)
            color: hp > maxHp * 0.5 ? "#22CC22" : (hp > maxHp * 0.25 ? "#CCCC22" : "#CC2222")

            Behavior on width { NumberAnimation { duration: 100 } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    // Circular collider
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

    // MoveTo behavior for chasing player
    MoveTo {
        id: moveTo
        world: enemy.gameWorld
        actor: enemy
        desiredSpeed: enemy.chaseSpeed
        running: enemy.aiState === "chase"
        destXWu: enemy.target ? enemy.target.xWu : enemy.xWu
        destYWu: enemy.target ? enemy.target.yWu : enemy.yWu
    }

    // AI state machine
    Timer {
        id: aiTimer
        interval: 100  // 10fps for AI decisions
        running: true
        repeat: true
        onTriggered: updateAI(interval / 1000.0)
    }

    function updateAI(dt) {
        if (!target || !gameWorld) {
            aiState = "idle"
            return
        }

        // Update cooldowns
        if (attackCooldown > 0) attackCooldown -= dt
        if (telegraphTimer > 0) telegraphTimer -= dt

        let dx = target.xWu - xWu
        let dy = target.yWu - yWu
        let dist = Math.sqrt(dx * dx + dy * dy)

        switch (aiState) {
            case "idle":
                aiState = "chase"
                break

            case "chase":
                if (dist < 1.5) {
                    // In melee range, start telegraph
                    aiState = "telegraph"
                    telegraphTimer = 0.3
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
                if (attackCooldown <= 0) {
                    aiState = "chase"
                }
                break
        }
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

    function onCollision(other) {
        // Handle collision events if needed
    }

    function takeDamage(amount) {
        let finalDamage = Math.max(1, amount - def)
        hp = Math.max(0, hp - finalDamage)
        console.log("[Enemy] Took", finalDamage, "damage, HP:", hp)

        // Trigger hit flash
        hitFlashAnimation.restart()

        if (hp <= 0) {
            die()
        }
    }

    function die() {
        console.log("[Enemy] Died!")
        destroyed = true
        destroy()
    }
}
