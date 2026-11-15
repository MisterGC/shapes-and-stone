import QtQuick
import Box2D
import Clayground.Physics
import Clayground.World

// The bolt (Balance.bolt, issue #319): a blast a knight lets loose along
// its aim. It flies from (fromX, fromY), its centre, along (dirX, dirY) and
// ends at the first enemy it meets, at a wall or past its reach. Only the
// bolt of this screen's knight (own) deals the enemy its blow; another
// knight's flies here to be seen and bursts on the enemy it meets alone.
// It hurts no knight: its sensor does not meet one
PhysicsItem {
    id: bolt
    objectName: "bolt"

    property var gameWorld: null
    // The firing node's id for this bolt, the same on every node
    property string boltId: ""
    property real dirX: 1
    property real dirY: 0
    property real fromX: 0
    property real fromY: 0
    property real speed: Balance.bolt.speed
    property real reach: Balance.bolt.reach
    property int damage: 0
    property bool own: false
    property bool destroyed: false
    // How far its centre is from where it began
    property real travelled: 0
    // It ended on this screen: how - "enemy", "wall" or "reach", or as the
    // firing node said when its report came first (Game._boltEndReported)
    // - the enemy it met, null for none, and the damage it dealt there
    signal ended(string how, var enemy, int dealt)

    widthWu: Balance.bolt.size
    heightWu: Balance.bolt.size
    bodyType: Body.Dynamic
    bullet: true
    fixedRotation: true
    gravityScale: 0

    property alias categories: wallCollider.categories
    property alias collidesWith: wallCollider.collidesWith
    property alias sensorCategories: enemySensor.categories
    property alias sensorCollidesWith: enemySensor.collidesWith

    readonly property real centreX: xWu + widthWu / 2
    readonly property real centreY: yWu - heightWu / 2

    Light2d {
        offsetXWu: bolt.widthWu / 2
        offsetYWu: -bolt.heightWu / 2
        radius: Balance.bolt.light
        color: Balance.bolt.color
        intensity: 1.0
        castsShadows: false
    }

    // A streak behind it along its line, and the blast round its core
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.horizontalCenter
        width: parent.width * 2.2
        height: parent.height * 0.6
        radius: height / 2
        color: Balance.bolt.color
        opacity: 0.45
        transformOrigin: Item.Right
        rotation: -Math.atan2(bolt.dirY, bolt.dirX) * 180 / Math.PI
    }
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 1.7
        height: width
        radius: width / 2
        color: Balance.bolt.color
        opacity: 0.4
    }
    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: width
        radius: width / 2
        color: Balance.bolt.coreColor
    }

    fixtures: [
        Circle {
            id: wallCollider
            radius: bolt.width * 0.4
            x: bolt.width / 2
            y: bolt.height / 2
            density: 0.1
            restitution: 0
            friction: 0
            onBeginContact: (other) => bolt._metWall(other)
        },
        Circle {
            id: enemySensor
            radius: bolt.width * 0.5
            x: bolt.width / 2
            y: bolt.height / 2
            sensor: true
            onBeginContact: (other) => bolt._metEnemy(other)
        }
    ]

    // It flies straight on; past its reach it fades out
    Connections {
        target: bolt.world
        function onStepped() {
            if (bolt.destroyed) return
            bolt.travelled = Math.hypot(bolt.centreX - bolt.fromX, bolt.centreY - bolt.fromY)
            if (bolt.travelled >= bolt.reach) {
                bolt.end("reach", null)
                return
            }
            bolt.body.linearVelocity = Qt.point(bolt.dirX * bolt.speed, -bolt.dirY * bolt.speed)
        }
    }

    // Another node's knight is in the walls' category too (RemotePlayer):
    // it flies through it
    function _metWall(other) {
        if (destroyed) return
        let entity = other.getBody().target
        if (!entity || entity.nodeId !== undefined) return
        if (entity.objectName === "wall" || !entity.objectName) end("wall", null)
    }

    // The first enemy it meets that still stands: the own bolt deals the
    // blow (Enemy.takeBolt) from a step back along its line
    function _metEnemy(other) {
        if (destroyed) return
        let enemy = other.getBody().target
        if (!enemy || enemy.objectName !== "enemy" || enemy.destroyed !== false) return
        let dealt = 0
        if (own && enemy.takeBolt) dealt = enemy.takeBolt(damage, centreX - dirX, centreY - dirY)
        end("enemy", enemy, dealt)
    }

    // It ends here on this screen: how, the enemy it met and what it dealt
    function end(how, enemy, dealt) {
        if (destroyed) return
        destroyed = true
        travelled = Math.hypot(centreX - fromX, centreY - fromY)
        ended(how, enemy || null, dealt || 0)
        destroy()
    }
}
