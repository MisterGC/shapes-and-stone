import QtQuick
import Box2D
import Clayground.Physics
import Clayground.World

PhysicsItem {
    id: projectile
    objectName: "projectile"

    property var gameWorld: null
    // The host's id for this shot, the same on every node
    property string shotId: ""
    property real dirX: 0
    property real dirY: 0
    property real speed: Balance.projectile.speed
    property int damage: Balance.enemy.spitter.atk
    property bool destroyed: false
    // It went, on this screen
    signal gone()

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

    // It lights its own way through the dark
    Light2d {
        offsetXWu: projectile.widthWu / 2
        offsetYWu: -projectile.heightWu / 2
        radius: 2.5
        color: "#9ADD55"
        intensity: 0.9
        castsShadows: false
    }

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

    // Burst when its lifetime of simulated time is over
    PhysicsTimer {
        world: projectile.world
        running: true
        interval: Balance.projectile.lifetime * 1000
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
        if (entity.isBlocking && entity.isShieldFacing(xWu, yWu, widthWu)) {
            let sp = entity.getShieldWorldPos()
            if (gameWorld) {
                gameWorld.playImpact()
                gameWorld.impact("projectileDeflected", sp.x, sp.y, dirX, dirY)
                gameWorld.countFight("block")
                if (gameWorld.shotLanded) gameWorld.shotLanded(shotId, "blocked")
            }
            vanish()
            return
        }
        // A shot the knight dodges or ignores bursts without a hit
        let result = entity.takeDamage(damage, xWu, yWu, widthWu, false, dirX, dirY)
        if (gameWorld) {
            if (result === "hit" || result === "blocked") {
                gameWorld.impact("projectileHit", entity.xWu, entity.yWu, dirX, dirY)
                gameWorld.spawnDamageNumber(entity.xWu, entity.yWu, damage, "#6B8E4A")
            }
            if (gameWorld.shotLanded) gameWorld.shotLanded(shotId, result)
        }
        die()
    }

    function die() {
        if (destroyed) return
        if (gameWorld) gameWorld.impact("projectileBurst", xWu, yWu, -dirX, -dirY)
        vanish()
    }

    // Gone without an impact of its own
    function vanish() {
        if (destroyed) return
        destroyed = true
        gone()
        destroy()
    }
}
