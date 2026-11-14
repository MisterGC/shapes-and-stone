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
    // A perfect block sent it back (Balance.projectile, issue #283): it
    // flies back along its line, hurts no knight and bursts on the first
    // enemy it meets. Only the screen whose knight sent it back (own)
    // deals that enemy backDamage; on the others it bursts there alone
    property bool back: false
    property bool ownBack: false
    property int backDamage: 0
    // It went, on this screen
    signal gone()

    widthWu: Balance.projectile.size
    heightWu: Balance.projectile.size

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
        color: projectile.back ? "#E8FFD0" : "#9ADD55"
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
        color: projectile.back ? "#E8FFD0" : "#8EBB5A"
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
        id: life
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

    // The sensor met a knight or an enemy: a shot on its way judges this
    // screen's knight, one sent back the first enemy
    function onHitPlayer(other) {
        if (destroyed) return
        let entity = other.getBody().target
        if (!entity) return
        if (back) {
            if (entity.objectName === "enemy") hitEnemy(entity)
            return
        }
        if (!entity.takeDamage || entity.objectName === "enemy") return

        // The shield stops it whole; raised just before, it sends it back
        let shield = entity.shieldShot ? entity.shieldShot(xWu, yWu, widthWu, dirX, dirY) : ""
        if (shield === "perfect") {
            sendBack(true, Math.round(entity.atk * Balance.projectile.backDamage))
            if (gameWorld && gameWorld.shotLanded) gameWorld.shotLanded(shotId, "perfect", xWu, yWu)
            return
        }
        if (shield === "blocked") {
            if (gameWorld && gameWorld.shotLanded) gameWorld.shotLanded(shotId, "blocked")
            vanish()
            return
        }
        // A shot the knight dodges or ignores bursts without a hit
        let result = entity.takeDamage(damage, xWu, yWu, widthWu, false, dirX, dirY)
        if (gameWorld) {
            if (result === "hit" || result === "blocked") {
                gameWorld.impact("projectileHit", entity.xWu, entity.yWu, dirX, dirY)
                gameWorld.spawnHurtNumber(entity.xWu, entity.yWu, damage, "#6B8E4A")
            }
            if (gameWorld.shotLanded) gameWorld.shotLanded(shotId, result)
        }
        die()
    }

    // A perfect block sends it back along its line (Balance.projectile):
    // own when this screen's knight did, dealing damage to the enemy it
    // meets. Its lifetime starts again
    function sendBack(own, damage) {
        if (destroyed || back) return
        back = true
        ownBack = own
        backDamage = damage
        dirX = -dirX
        dirY = -dirY
        speed = Balance.projectile.backSpeed
        life.restart()
    }

    // Sent back, it met enemy: it bursts there, and the screen whose
    // knight sent it back deals the blow - a lead's stance breaks under
    // it (Enemy.takeShot) - and tells the others it is gone
    function hitEnemy(enemy) {
        if (destroyed || !enemy || enemy.destroyed) return
        if (ownBack && enemy.takeShot) {
            let dealt = enemy.takeShot(backDamage, xWu - dirX, yWu - dirY)
            if (gameWorld) {
                // The knight's own hit sound: its blow came back
                if (gameWorld.playImpact) gameWorld.playImpact()
                gameWorld.spawnDamageNumber(enemy.xWu, enemy.yWu, dealt, "#E8FFD0")
                if (gameWorld.countFight) gameWorld.countFight("shotBackHit")
                if (gameWorld.shotLanded) gameWorld.shotLanded(shotId, "enemy")
            }
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
