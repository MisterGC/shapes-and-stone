import QtQuick
import Box2D
import Clayground.Physics

PhysicsItem {
    id: projectile
    objectName: "projectile"

    property var gameWorld: null
    property real dirX: 0
    property real dirY: 0
    property real speed: 5.0
    property int damage: 8
    property bool destroyed: false

    widthWu: 0.3
    heightWu: 0.3

    bodyType: Body.Dynamic
    fixedRotation: true
    gravityScale: 0

    // Wall collider (solid — stops at wall boundary)
    property alias categories: wallCollider.categories
    property alias collidesWith: wallCollider.collidesWith
    // Player sensor (detects hit without pushing)
    property alias sensorCategories: playerSensor.categories
    property alias sensorCollidesWith: playerSensor.collidesWith

    // Visual: sickly green glowing orb
    Rectangle {
        id: glow
        anchors.centerIn: parent
        width: parent.width * 1.6
        height: parent.height * 1.6
        radius: width * 0.5
        color: "#6B8E4A"
        opacity: 0.3
    }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        radius: width * 0.5
        color: "#8EBB5A"
    }

    fixtures: [
        Circle {
            id: wallCollider
            radius: projectile.width * 0.4
            x: projectile.width / 2
            y: projectile.height / 2
            density: 0.1
            restitution: 0
            friction: 0
            onBeginContact: (other) => projectile.onHitWall(other)
        },
        Circle {
            id: playerSensor
            radius: projectile.width * 0.4
            x: projectile.width / 2
            y: projectile.height / 2
            sensor: true
            onBeginContact: (other) => projectile.onHitPlayer(other)
        }
    ]

    // Move in straight line
    Connections {
        target: projectile.world
        function onStepped() {
            if (destroyed) return
            projectile.body.linearVelocity = Qt.point(
                dirX * speed, -dirY * speed)
        }
    }

    // Auto-destroy after 3 seconds
    Timer {
        running: true
        interval: 3000
        onTriggered: projectile.die()
    }

    function onHitWall(other) {
        if (destroyed) return
        let entity = other.getBody().target
        if (entity && (entity.objectName === "wall" || !entity.objectName))
            die()
    }

    function onHitPlayer(other) {
        if (destroyed) return
        let entity = other.getBody().target
        if (!entity || !entity.takeDamage || entity.objectName === "enemy") return

        // Shield blocks projectile completely
        if (entity.isBlocking && entity.isShieldFacing(xWu, yWu)) {
            let sp = entity.getShieldWorldPos()
            if (gameWorld) {
                gameWorld.playImpact()
                gameWorld.shake(0.5)
                gameWorld.spawnDeflectParticles(sp.x, sp.y)
            }
            destroyed = true
            destroy()
            return
        }
        entity.takeDamage(damage, xWu, yWu)
        if (gameWorld) {
            gameWorld.shake(1)
            gameWorld.spawnDamageNumber(entity.xWu, entity.yWu, damage, "#6B8E4A")
        }
        die()
    }

    function die() {
        if (destroyed) return
        destroyed = true
        if (gameWorld) gameWorld.spawnSpitParticles(xWu, yWu)
        destroy()
    }
}
