import QtQuick
import Box2D
import Clayground.Physics

PhysicsItem {
    id: npc
    objectName: "npc"

    property var gameWorld: null
    property string npcName: ""
    property color npcColor: "#C9A227"
    property string iconType: ""  // "mug", "hammer", "crystal"
    property var dialogueLines: []
    property string greetingSound: ""

    // Routine: [{x, y, duration, text}, ...]
    property var routine: []
    property int _routineIndex: 0
    property string _activityText: ""
    property bool _atDestination: false
    property real _activityTimer: 0
    property real walkSpeed: 1.5

    // Interaction
    property var nearbyPlayer: null
    property alias interactionCategories: interactionSensor.categories
    property alias interactionCollidesWith: interactionSensor.collidesWith

    widthWu: 0.8
    heightWu: 0.8
    bodyType: Body.Kinematic
    fixedRotation: true
    gravityScale: 0

    // Visual: colored circle with icon
    Rectangle {
        id: visual
        anchors.fill: parent
        radius: width * 0.5
        color: npcColor

        Canvas {
            id: icon
            anchors.centerIn: parent
            width: parent.width * 0.6
            height: parent.height * 0.6
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width, h = height
                var dark = Qt.darker(npcColor, 1.8)
                ctx.fillStyle = dark
                ctx.strokeStyle = dark
                ctx.lineWidth = w * 0.06

                if (iconType === "hammer") {
                    // Handle
                    ctx.fillRect(w * 0.45, h * 0.25, w * 0.1, h * 0.55)
                    // Head
                    ctx.fillRect(w * 0.25, h * 0.15, w * 0.5, h * 0.2)
                } else if (iconType === "mug") {
                    // Mug body
                    ctx.fillRect(w * 0.25, h * 0.3, w * 0.4, h * 0.45)
                    // Handle
                    ctx.beginPath()
                    ctx.arc(w * 0.65, h * 0.52, w * 0.12, -Math.PI * 0.5, Math.PI * 0.5)
                    ctx.stroke()
                    // Foam top
                    ctx.fillRect(w * 0.2, h * 0.25, w * 0.5, h * 0.1)
                } else if (iconType === "crystal") {
                    // Crystal ball
                    ctx.beginPath()
                    ctx.arc(w * 0.5, h * 0.4, w * 0.22, 0, Math.PI * 2)
                    ctx.stroke()
                    // Sparkle
                    ctx.fillStyle = Qt.lighter(npcColor, 1.6)
                    ctx.beginPath()
                    ctx.arc(w * 0.42, h * 0.33, w * 0.06, 0, Math.PI * 2)
                    ctx.fill()
                    // Base
                    ctx.fillStyle = dark
                    ctx.fillRect(w * 0.35, h * 0.62, w * 0.3, h * 0.08)
                }
            }
        }
    }

    // Idle bobbing
    SequentialAnimation {
        running: _atDestination
        loops: Animation.Infinite
        NumberAnimation { target: npc; property: "scale"; to: 1.03; duration: 600; easing.type: Easing.InOutSine }
        NumberAnimation { target: npc; property: "scale"; to: 0.97; duration: 600; easing.type: Easing.InOutSine }
    }

    // Floating activity text
    Text {
        id: activityLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 8
        text: _activityText
        color: "#CCCCAA"
        font.pixelSize: 9
        font.italic: true
        style: Text.Outline
        styleColor: "#000000"
        opacity: _atDestination && _activityText !== "" ? 1.0 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    // Interaction prompt
    Text {
        id: promptLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: activityLabel.top
        anchors.bottomMargin: 2
        text: "[E] Talk"
        color: "#FFFFFF"
        font.pixelSize: 10
        font.bold: true
        style: Text.Outline
        styleColor: "#000000"
        opacity: nearbyPlayer ? 1.0 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    fixtures: [
        Circle {
            radius: npc.width * 0.35
            x: npc.width / 2
            y: npc.height / 2
            density: 1.0
            friction: 0.0
            restitution: 0.0
        },
        Circle {
            id: interactionSensor
            radius: npc.width * 2.0
            x: npc.width / 2
            y: npc.height / 2
            sensor: true
            onBeginContact: (other) => {
                let entity = other.getBody().target
                if (entity && entity.objectName === "player")
                    nearbyPlayer = entity
            }
            onEndContact: (other) => {
                let entity = other.getBody().target
                if (entity && entity.objectName === "player")
                    nearbyPlayer = null
            }
        }
    ]

    // Routine AI
    Timer {
        id: routineTimer
        running: routine.length > 0
        repeat: true
        interval: 100
        onTriggered: _updateRoutine(interval / 1000.0)
    }

    function _updateRoutine(dt) {
        if (routine.length === 0) return
        let act = routine[_routineIndex]

        if (_atDestination) {
            _activityTimer -= dt
            if (_activityTimer <= 0) {
                _atDestination = false
                _activityText = ""
                _routineIndex = (_routineIndex + 1) % routine.length
            }
            body.linearVelocity = Qt.point(0, 0)
            return
        }

        // Walk toward destination
        let dx = act.x - xWu
        let dy = act.y - yWu
        let dist = Math.sqrt(dx * dx + dy * dy)

        if (dist < 0.3) {
            // Arrived
            body.linearVelocity = Qt.point(0, 0)
            _atDestination = true
            _activityTimer = act.duration || 3
            _activityText = act.text || ""
        } else {
            let ndx = dx / dist
            let ndy = dy / dist
            body.linearVelocity = Qt.point(
                ndx * walkSpeed, -ndy * walkSpeed)
        }
    }

    function interact() {
        if (gameWorld && dialogueLines.length > 0) {
            if (greetingSound !== "" && gameWorld.playNpcGreeting)
                gameWorld.playNpcGreeting(greetingSound)
            gameWorld.openDialogue(npcName, npcColor, dialogueLines)
        }
    }
}
