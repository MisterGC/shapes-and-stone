import QtQuick
import Box2D
import Clayground.Physics

PhysicsItem {
    id: rp

    property string nodeId: ""
    property color playerColor: "#A44A90"
    property real targetX: 0
    property real targetY: 0
    property real facingAngle: 0
    property int actionState: 0   // 0=idle, 1=atk, 2=block, 3=dash
    property int remoteHp: 120

    widthWu: 1.0
    heightWu: 1.0

    bodyType: Body.Kinematic
    fixedRotation: true
    gravityScale: 0

    fixtures: Circle {
        radius: rp.width * 0.35
        x: rp.width / 2
        y: rp.height / 2
        sensor: true
    }

    // Smooth position interpolation
    onTargetXChanged: xWu = targetX
    onTargetYChanged: yWu = targetY
    Behavior on xWu { NumberAnimation { duration: 60 } }
    Behavior on yWu { NumberAnimation { duration: 60 } }

    // Visual circle
    Rectangle {
        id: visual
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        color: playerColor
        radius: width * 0.5
        opacity: actionState === 3 ? 0.5 : 1.0

        // Helmet icon (simplified, tinted)
        Canvas {
            anchors.centerIn: parent
            width: parent.width * 0.6
            height: parent.height * 0.6
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width, h = height
                var darker = Qt.darker(playerColor, 1.4)
                ctx.fillStyle = darker
                ctx.strokeStyle = darker
                ctx.lineWidth = w * 0.06

                // Dome
                ctx.beginPath()
                ctx.moveTo(w * 0.15, h * 0.55)
                ctx.quadraticCurveTo(w * 0.15, h * 0.1, w * 0.5, h * 0.08)
                ctx.quadraticCurveTo(w * 0.85, h * 0.1, w * 0.85, h * 0.55)
                ctx.closePath()
                ctx.fill()

                // Visor slit
                ctx.fillStyle = playerColor
                ctx.fillRect(w * 0.2, h * 0.42, w * 0.6, h * 0.1)

                // Cheek guards
                ctx.fillStyle = darker
                ctx.beginPath()
                ctx.moveTo(w * 0.15, h * 0.55)
                ctx.lineTo(w * 0.15, h * 0.78)
                ctx.lineTo(w * 0.3, h * 0.88)
                ctx.lineTo(w * 0.3, h * 0.55)
                ctx.closePath()
                ctx.fill()

                ctx.beginPath()
                ctx.moveTo(w * 0.85, h * 0.55)
                ctx.lineTo(w * 0.85, h * 0.78)
                ctx.lineTo(w * 0.7, h * 0.88)
                ctx.lineTo(w * 0.7, h * 0.55)
                ctx.closePath()
                ctx.fill()

                // Nose guard
                ctx.fillRect(w * 0.46, h * 0.35, w * 0.08, h * 0.25)
            }
        }
    }

    // Shield arc (visible when blocking)
    Canvas {
        id: shieldArc
        visible: actionState === 2
        readonly property real shieldSize: rp.width * 0.8
        readonly property real orbitRadius: rp.width * 0.5
        readonly property real angleRad: facingAngle * Math.PI / 180
        width: shieldSize
        height: shieldSize
        x: rp.width / 2 - width / 2 + Math.cos(angleRad) * orbitRadius
        y: rp.height / 2 - height / 2 - Math.sin(angleRad) * orbitRadius
        rotation: -facingAngle
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height
            ctx.beginPath()
            ctx.arc(w / 2, h / 2, w * 0.4, -Math.PI * 0.4, Math.PI * 0.4)
            ctx.strokeStyle = Qt.lighter(playerColor, 1.3)
            ctx.lineWidth = w * 0.25
            ctx.stroke()
        }
        onVisibleChanged: if (visible) requestPaint()
    }

    // Attack arc flash (visible briefly when attacking)
    Canvas {
        id: attackArc
        visible: actionState === 1
        readonly property real arcSize: rp.width * 2.5
        readonly property real angleRad: facingAngle * Math.PI / 180
        width: arcSize
        height: arcSize
        x: rp.width / 2 - width / 2 + Math.cos(angleRad) * rp.width * 0.6
        y: rp.height / 2 - height / 2 - Math.sin(angleRad) * rp.width * 0.6
        rotation: -facingAngle
        opacity: 0.6
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height
            ctx.beginPath()
            ctx.arc(w / 2, h / 2, w * 0.35, -Math.PI * 0.25, Math.PI * 0.25)
            ctx.strokeStyle = "#DDDDDD"
            ctx.lineWidth = w * 0.08
            ctx.stroke()
        }
        onVisibleChanged: if (visible) requestPaint()
    }
}
