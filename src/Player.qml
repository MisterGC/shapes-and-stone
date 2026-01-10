import QtQuick
import Box2D
import Clayground.Physics

PhysicsItem {
    id: player

    // Visual size (the square shape)
    widthWu: 1.0
    heightWu: 1.0

    // Physics config
    bodyType: Body.Kinematic
    fixedRotation: true

    // Collision setup - uses circle fixture smaller than visual
    property alias categories: collider.categories
    property alias collidesWith: collider.collidesWith
    property alias sensor: collider.sensor

    // Movement input (-1 to 1)
    property real moveX: 0
    property real moveY: 0

    // Stats from concept doc
    property real speed: 5.0        // World units per second (70% of base)
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

    // Movement
    linearVelocity: Qt.point(moveX * speed, moveY * speed)

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

    // Circular collider (smaller than visual to avoid corner snagging)
    fixtures: [
        Circle {
            id: collider
            radius: player.width * 0.35  // 70% of half-width
            x: player.width / 2
            y: player.height / 2

            onBeginContact: (other) => player.onCollision(other)
        }
    ]

    // Combat sensor (slightly larger, detects enemies for melee range)
    // TODO: Add separate sensor fixture for attack range

    function onCollision(other) {
        // Handle collision with enemies (sensor collision for combat)
        console.log("Player collision detected")
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
            attackCooldown = 0.6  // 600ms cooldown
            // TODO: Spawn attack hitbox, play animation
        }
    }
}
