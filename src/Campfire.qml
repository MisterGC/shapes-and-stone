import QtQuick
import Box2D
import Clayground.Physics

RectBoxBody {
    id: campfire

    widthWu: 1.5
    heightWu: 1.5
    bodyType: Body.Static
    sensor: true
    categories: Box.Category1
    collidesWith: Box.Category2
    color: "transparent"

    // Healing config
    property var gameWorld: null
    property real healRate: 5.0  // HP per second
    property real healRadius: 3.0

    // Warm glow
    Rectangle {
        anchors.centerIn: parent
        width: healRadius * 2 * campfire.pixelPerUnit
        height: width
        radius: width * 0.5
        color: "#FF8C00"
        opacity: 0.08
    }

    // Fire base (brown circle)
    Rectangle {
        id: base
        anchors.centerIn: parent
        width: parent.width * 0.6
        height: parent.height * 0.6
        radius: width * 0.5
        color: "#5A3A1A"
    }

    // Flames (animated canvas)
    Canvas {
        id: flames
        anchors.centerIn: parent
        width: parent.width
        height: parent.height

        property real flicker: 0

        Timer {
            running: true; repeat: true; interval: 80
            onTriggered: {
                flames.flicker = Math.random()
                flames.requestPaint()
            }
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = width / 2, cy = height / 2
            var r = width * 0.2

            // Draw 3-4 flame tongues
            var colors = ["#FF6600", "#FF9933", "#FFCC00", "#FF4400"]
            for (var i = 0; i < 4; i++) {
                var angle = (i / 4) * Math.PI * 2 + flicker * 0.5
                var h = r * (1.2 + flicker * 0.6)
                var fx = cx + Math.cos(angle) * r * 0.3
                var fy = cy - Math.sin(angle) * r * 0.3

                ctx.beginPath()
                ctx.moveTo(fx - r * 0.15, cy + r * 0.1)
                ctx.quadraticCurveTo(fx, fy - h, fx + r * 0.15, cy + r * 0.1)
                ctx.fillStyle = colors[i]
                ctx.globalAlpha = 0.7 + flicker * 0.3
                ctx.fill()
            }
            ctx.globalAlpha = 1.0
        }
    }

    // Proximity healing via timer (checks distance to player)
    Timer {
        running: true; repeat: true; interval: 200
        onTriggered: {
            if (!gameWorld || !gameWorld.player) return
            let p = gameWorld.player
            let dx = p.xWu - campfire.xWu
            let dy = p.yWu - campfire.yWu
            let dist = Math.sqrt(dx * dx + dy * dy)
            if (dist < healRadius && p.hp < p.maxHp) {
                p.hp = Math.min(p.maxHp, p.hp + Math.round(healRate * interval / 1000))
            }
        }
    }
}
