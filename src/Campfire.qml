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
    property bool _isHealing: false

    // Warm glow with pulse
    Rectangle {
        anchors.centerIn: parent
        width: healRadius * 2 * campfire.pixelPerUnit
        height: width
        radius: width * 0.5
        color: "#FF8C00"
        opacity: 0.12 + _glowPulse * 0.06

        property real _glowPulse: 0
        SequentialAnimation on _glowPulse {
            loops: Animation.Infinite
            NumberAnimation { to: 1.0; duration: 1500; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.0; duration: 1500; easing.type: Easing.InOutSine }
        }
    }

    // Fire base (brown circle)
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.6
        height: parent.height * 0.6
        radius: width * 0.5
        color: "#5A3A1A"
    }

    // Flames (animated canvas — bigger, 6 tongues)
    Canvas {
        id: flames
        anchors.centerIn: parent
        width: parent.width * 1.5
        height: parent.height * 1.5

        property real flicker: 0

        Timer {
            running: true; repeat: true; interval: 70
            onTriggered: {
                flames.flicker = Math.random()
                flames.requestPaint()
            }
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = width / 2, cy = height / 2
            var r = width * 0.18

            var colors = ["#FF6600", "#FF9933", "#FFCC00", "#FF4400", "#FF7722", "#FFAA00"]
            for (var i = 0; i < 6; i++) {
                var angle = (i / 6) * Math.PI * 2 + flicker * 0.5
                var h = r * (1.4 + flicker * 0.8)
                var fx = cx + Math.cos(angle) * r * 0.35
                var fy = cy - Math.sin(angle) * r * 0.35

                ctx.beginPath()
                ctx.moveTo(fx - r * 0.18, cy + r * 0.1)
                ctx.quadraticCurveTo(fx, fy - h, fx + r * 0.18, cy + r * 0.1)
                ctx.fillStyle = colors[i]
                ctx.globalAlpha = 0.7 + flicker * 0.3
                ctx.fill()
            }
            ctx.globalAlpha = 1.0
        }
    }

    // Rising embers
    Timer {
        running: true; repeat: true; interval: 300
        onTriggered: {
            if (!campfire.parent) return
            let ex = campfire.x + campfire.width * (0.3 + Math.random() * 0.4)
            let ey = campfire.y + campfire.height * 0.3
            emberComp.createObject(campfire.parent, {
                x: ex, y: ey
            })
        }
    }

    Component {
        id: emberComp
        Rectangle {
            id: _ember
            width: 3; height: 3; radius: 1.5
            color: Math.random() > 0.5 ? "#FFAA33" : "#FF6600"
            opacity: 0.8
            SequentialAnimation {
                running: true
                ParallelAnimation {
                    NumberAnimation { target: _ember; property: "y"; from: _ember.y; to: _ember.y - 40; duration: 800; easing.type: Easing.OutQuad }
                    NumberAnimation { target: _ember; property: "x"; from: _ember.x; to: _ember.x + (Math.random() - 0.5) * 20; duration: 800 }
                    NumberAnimation { target: _ember; property: "opacity"; to: 0; duration: 800 }
                }
                ScriptAction { script: _ember.destroy() }
            }
        }
    }

    // Proximity healing + feedback
    Timer {
        running: true; repeat: true; interval: 200
        onTriggered: {
            if (!gameWorld || !gameWorld.player) return
            let p = gameWorld.player
            let dx = p.xWu - campfire.xWu
            let dy = p.yWu - campfire.yWu
            let dist = Math.sqrt(dx * dx + dy * dy)
            let wasHealing = _isHealing
            _isHealing = dist < healRadius && p.hp < p.maxHp
            if (_isHealing) {
                let healed = Math.round(healRate * interval / 1000)
                p.hp = Math.min(p.maxHp, p.hp + healed)
                if (gameWorld.spawnDamageNumber)
                    gameWorld.spawnDamageNumber(p.xWu, p.yWu, "+" + healed, "#44CC44")
            }
            if (p.isHealing !== undefined)
                p.isHealing = _isHealing
        }
    }
}
