import QtQuick
import Box2D
import Clayground.Physics

PhysicsItem {
    id: enemy

    // Visual size
    widthWu: 0.5
    heightWu: 0.5

    // Physics config
    bodyType: Body.Kinematic
    fixedRotation: true

    // Collision setup
    property alias categories: collider.categories
    property alias collidesWith: collider.collidesWith
    property alias sensor: collider.sensor

    // AI target
    property var target: null

    // Stats (Grunt from concept doc)
    property real speed: 4.0        // 80% of base speed
    property int hp: 20
    property int maxHp: 20
    property int atk: 10
    property int def: 2

    // Combat state
    property bool isAttacking: false
    property real attackCooldown: 0
    property real telegraphTimer: 0

    // AI state
    property string state: "idle"  // idle, chase, telegraph, attack, recovery

    // Visual: Dull Red square (Grunt)
    Rectangle {
        id: visual
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        color: "#8B3A3A"  // Dull Red

        // Telegraph flash (orange when about to attack)
        opacity: state === "telegraph" ? 0.7 : 1.0

        Behavior on opacity { NumberAnimation { duration: 100 } }
    }

    // Circular collider
    fixtures: [
        Circle {
            id: collider
            radius: enemy.width * 0.35
            x: enemy.width / 2
            y: enemy.height / 2

            onBeginContact: (other) => enemy.onCollision(other)
        }
    ]

    // Simple AI behavior
    Timer {
        id: aiTimer
        interval: 16  // ~60fps
        running: true
        repeat: true
        onTriggered: updateAI(interval / 1000.0)
    }

    function updateAI(dt) {
        if (!target) {
            linearVelocity = Qt.point(0, 0)
            return
        }

        // Update cooldowns
        if (attackCooldown > 0) attackCooldown -= dt
        if (telegraphTimer > 0) telegraphTimer -= dt

        let dx = target.xWu - xWu
        let dy = target.yWu - yWu
        let dist = Math.sqrt(dx * dx + dy * dy)

        switch (state) {
            case "idle":
            case "chase":
                if (dist < 1.5) {
                    // In melee range, start telegraph
                    state = "telegraph"
                    telegraphTimer = 0.3
                    linearVelocity = Qt.point(0, 0)
                    visual.color = "#FF8C00"  // Orange telegraph
                } else {
                    // Chase player
                    state = "chase"
                    let dirX = dx / dist
                    let dirY = dy / dist
                    linearVelocity = Qt.point(dirX * speed, dirY * speed)
                }
                break

            case "telegraph":
                if (telegraphTimer <= 0) {
                    state = "attack"
                    performAttack()
                }
                break

            case "attack":
                // Attack animation/lunge would happen here
                state = "recovery"
                attackCooldown = 0.8
                visual.color = "#8B3A3A"  // Back to normal color
                break

            case "recovery":
                if (attackCooldown <= 0) {
                    state = "chase"
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
            }
        }
    }

    function onCollision(other) {
        console.log("Enemy collision detected")
    }

    function takeDamage(amount) {
        let finalDamage = Math.max(1, amount - def)
        hp = Math.max(0, hp - finalDamage)
        if (hp <= 0) {
            die()
        }
        // TODO: Trigger hit flash animation
    }

    function die() {
        // TODO: Death particles, gold drop
        destroy()
    }
}
