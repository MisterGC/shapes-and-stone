import QtQuick
import Clayground.World

// How a knight looks: body, helmet, lantern and its light, shield, swing,
// dash afterimages and the flashes. It draws only - the local Player and
// the RemotePlayer drive it with the same state properties and the same
// action calls, so a visual added here shows on both knights.
Item {
    id: view
    anchors.fill: parent

    // The knight's body (a PhysicsItem); the swing, the afterimages and the
    // lantern light are placed relative to it in the room
    required property var host
    property var gameWorld: null

    // Colours: body, helmet trim and the light accent of shield and trails
    property color bodyColor: "#4A90A4"
    property color trimColor: "#2A6A84"
    property color accentColor: "#7AB8D4"
    property color bladeColor: "#5A9AB4"
    property color ridgeColor: "#3A8A9A"

    // State, bound by the driver
    property real facingAngle: 0
    property real moveX: 0          // -1..1, for the lean
    property real moveAmount: 0     // 0..1, for the step bob and the lantern swing
    property bool blocking: false
    property bool dashing: false
    property bool healing: false
    property real dashCooldownProgress: 1   // 0 just dashed, 1 ready
    // Seconds left of the grace after a hit: the knight flickers white
    property real graceLeft: 0

    // Seconds, from the balance table: wind up plus follow through, and
    // the fade of the arc after it
    property real swingDuration: Balance.knight.swingDuration
    readonly property real swingFade: Balance.knight.swingFade
    readonly property bool swinging: attackAnimation.running

    // The swing animation ended (fade included)
    signal swingFinished()

    readonly property bool _fx: gameWorld ? gameWorld.fx === true : false

    function swing() {
        attackArc.swingProgress = 0
        attackArc.swingOpacity = 0.9
        attackArc.requestPaint()
        attackAnimation.restart()
    }

    // durationMs keeps the afterimages coming when the driver's dashing
    // state is too coarse to show the whole dash
    function dash(durationMs) {
        dashFlash.restart()
        _dashTrail.interval = durationMs
        _dashTrail.restart()
    }

    function parry() { parryGlow.restart() }
    function hurt() { hurtFlash.restart() }

    function _rgba(c, a) {
        return "rgba(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", "
                + Math.round(c.b * 255) + ", " + a + ")"
    }

    // The knight's own lantern: small, steady, just enough to fight by
    Light2d {
        target: view.host
        // xWu/yWu of a body are its top-left corner
        offsetXWu: 0.5
        offsetYWu: -0.5
        enabled: view._fx
        radius: view.gameWorld && view.gameWorld.levelType === "village" ? 5.5 : 7.5
        color: view.gameWorld && view.gameWorld.levelType === "village" ? "#FFC98A" : "#FFE2B8"
        intensity: 1.0
        flicker: 0.08
        castsShadows: true
    }

    // Contact shadow: grounds the shape on the floor
    Rectangle {
        z: -1
        visible: view._fx
        width: parent.width * 0.92
        // Kept inside the body's bounds: a child reaching outside inflates
        // childrenRect and skews the physics debug draw
        height: parent.height * 0.32
        radius: height / 2
        x: (parent.width - width) / 2
        y: parent.height * 0.68
        color: "#000000"
        opacity: 0.38
    }

    // Life: breathing at rest, a step bob and a lean while walking.
    // Visual only - the body and its collider do not move.
    property real _lifeT: 0
    NumberAnimation on _lifeT {
        running: view._fx
        from: 0; to: 1000; duration: 1000000
        loops: Animation.Infinite
    }
    readonly property real _breath: Math.sin(_lifeT * 2.4) * (1 - moveAmount)
    readonly property real _step: Math.abs(Math.sin(_lifeT * 11)) * moveAmount

    Rectangle {
        id: visual
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        transform: [
            Scale {
                origin.x: visual.width / 2; origin.y: visual.height
                xScale: view._fx ? 1 - 0.02 * view._breath + 0.03 * view._step : 1
                yScale: view._fx ? 1 + 0.03 * view._breath - 0.05 * view._step : 1
            },
            Translate {
                x: view._fx ? view.moveX * visual.width * 0.04 : 0
                y: view._fx ? -view._step * visual.height * 0.07 : 0
            }
        ]
        color: view.bodyColor
        radius: width * .5

        BodyShade {
            visible: view._fx
            baseColor: visual.color
        }

        // Healing shimmer
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "#44CC44"
            opacity: 0
            SequentialAnimation on opacity {
                running: view.healing
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 400; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: 400; easing.type: Easing.InOutSine }
            }
        }

        // Helmet
        Canvas {
            anchors.centerIn: parent
            width: parent.width * 0.6
            height: parent.height * 0.6
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width, h = height
                ctx.fillStyle = view.trimColor
                ctx.strokeStyle = view.trimColor
                ctx.lineWidth = w * 0.06

                // Dome
                ctx.beginPath()
                ctx.moveTo(w * 0.15, h * 0.55)
                ctx.quadraticCurveTo(w * 0.15, h * 0.1, w * 0.5, h * 0.08)
                ctx.quadraticCurveTo(w * 0.85, h * 0.1, w * 0.85, h * 0.55)
                ctx.closePath()
                ctx.fill()

                // Visor slit
                ctx.fillStyle = view.bodyColor
                ctx.fillRect(w * 0.2, h * 0.42, w * 0.6, h * 0.1)

                // Cheek guards
                ctx.fillStyle = view.trimColor
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

        SequentialAnimation {
            id: dashFlash
            PropertyAnimation { target: visual; property: "opacity"; from: 0.4; to: 1.0; duration: 150 }
        }

        // Hurt flash: white for a few frames, then back
        Rectangle {
            id: hurtFlashRect
            anchors.fill: parent
            radius: parent.radius
            color: "white"
            opacity: 0
        }
        SequentialAnimation {
            id: hurtFlash
            PropertyAction { target: hurtFlashRect; property: "opacity"; value: 0.95 }
            PauseAnimation { duration: 50 }
            NumberAnimation { target: hurtFlashRect; property: "opacity"; to: 0; duration: 140 }
        }

        // Grace after a hit: flickers white until no hit can land again
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "white"
            opacity: view.graceLeft <= 0 ? 0
                : Math.floor(view.graceLeft / 0.05) % 2 === 0 ? 0.6 : 0.1
        }

        // Parry glow
        Rectangle {
            id: parryGlowRect
            anchors.fill: parent
            radius: parent.radius
            color: "#FFD700"
            opacity: 0
        }

        SequentialAnimation {
            id: parryGlow
            PropertyAnimation { target: parryGlowRect; property: "opacity"; from: 0.6; to: 0; duration: 200 }
        }
    }

    // The lantern: carried in the off hand, a quarter turn from the facing
    // direction, swinging a little with each step. The light around the
    // knight has a source you can see.
    Item {
        id: lantern
        visible: view._fx
        readonly property real angleRad: (view.facingAngle + 100) * Math.PI / 180
        readonly property real orbit: view.width * 0.62
        readonly property real swing: Math.sin(view._lifeT * 5.5) * view.moveAmount * view.width * 0.05
        width: view.width * 0.26
        height: width * 1.25
        x: view.width / 2 - width / 2 + Math.cos(angleRad) * orbit + swing
        y: view.height / 2 - height / 2 - Math.sin(angleRad) * orbit
        z: view.facingAngle > 0 && view.facingAngle < 180 ? -0.5 : 1
        // Halo
        Rectangle {
            anchors.centerIn: glass
            width: lantern.width * 2.2
            height: width
            radius: width / 2
            color: "#FFD27A"
            opacity: 0.18 + 0.05 * Math.sin(view._lifeT * 13)
        }
        // Handle, cage and the flame behind the glass
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.5; height: parent.height * 0.18
            radius: height / 2
            color: "transparent"
            border.color: "#2A2420"; border.width: Math.max(1, width * 0.18)
        }
        Rectangle {
            id: glass
            y: parent.height * 0.14
            width: parent.width; height: parent.height * 0.86
            radius: width * 0.2
            color: "#FFE8A8"
            border.color: "#3A302A"; border.width: Math.max(1, width * 0.14)
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.34; height: parent.height * 0.42
                radius: width / 2
                color: "#FFFFFF"
            }
        }
    }

    // Shield arc visual (orbits on facing side when blocking)
    Canvas {
        id: shieldArc
        visible: view.blocking
        readonly property real shieldSize: view.width * 0.8
        readonly property real orbitRadius: view.width * 0.5
        readonly property real angleRad: view.facingAngle * Math.PI / 180
        width: shieldSize
        height: shieldSize
        x: view.width / 2 - width / 2 + Math.cos(angleRad) * orbitRadius
        y: view.height / 2 - height / 2 - Math.sin(angleRad) * orbitRadius
        rotation: -view.facingAngle
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height
            ctx.beginPath()
            ctx.arc(w / 2, h / 2, w * 0.4, -Math.PI * 0.4, Math.PI * 0.4)
            ctx.strokeStyle = view.accentColor
            ctx.lineWidth = w * 0.25
            ctx.stroke()
        }

        onVisibleChanged: if (visible) requestPaint()
    }

    // Dash cooldown ring
    Canvas {
        id: dashCooldownRing
        anchors.centerIn: parent
        width: parent.width * 1.3
        height: parent.height * 1.3
        visible: view.dashCooldownProgress < 1
        opacity: 0.4

        property real progress: view.dashCooldownProgress

        onProgressChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = width / 2, cy = height / 2
            var r = width * 0.45
            var startAngle = -Math.PI / 2
            var endAngle = startAngle + progress * Math.PI * 2
            ctx.beginPath()
            ctx.arc(cx, cy, r, startAngle, endAngle)
            ctx.strokeStyle = "#AAAAAA"
            ctx.lineWidth = 2
            ctx.stroke()
        }
    }

    // Dash afterimages: one every other physics step while dashing
    Timer {
        id: _dashTrail
    }
    Timer {
        interval: 33
        repeat: true
        triggeredOnStart: true
        running: (view.dashing || _dashTrail.running) && !!view.host && !!view.host.parent
        onTriggered: afterimageComp.createObject(view.host.parent, {
            x: view.host.x, y: view.host.y,
            width: view.host.width, height: view.host.height,
            color: view.accentColor
        })
    }

    Component {
        id: afterimageComp
        Rectangle {
            id: _ghost
            radius: width * 0.5
            opacity: 0.5
            SequentialAnimation {
                running: true
                ParallelAnimation {
                    NumberAnimation { target: _ghost; property: "opacity"; to: 0; duration: 200 }
                    NumberAnimation { target: _ghost; property: "scale"; to: 0.5; duration: 200 }
                }
                ScriptAction { script: _ghost.destroy() }
            }
        }
    }

    // Direction indicator arrowhead (orbits around the knight)
    Canvas {
        id: aimArrow
        opacity: 0.5
        readonly property real arrowSize: view.width * 0.3
        readonly property real orbitRadius: view.width * 0.7
        readonly property real angleRad: view.facingAngle * Math.PI / 180
        width: arrowSize
        height: arrowSize
        x: view.width / 2 - width / 2 + Math.cos(angleRad) * orbitRadius
        y: view.height / 2 - height / 2 - Math.sin(angleRad) * orbitRadius
        rotation: -view.facingAngle
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height
            ctx.beginPath()
            ctx.moveTo(w, h * 0.5)
            ctx.lineTo(0, 0)
            ctx.lineTo(w * 0.3, h * 0.5)
            ctx.lineTo(0, h)
            ctx.closePath()
            ctx.fillStyle = view.accentColor
            ctx.fill()
        }
    }

    // Attack swing visualization
    // Reparented to avoid inflating the body's childrenRect.
    Canvas {
        id: attackArc
        parent: view.host.parent
        x: view.host.x + view.host.width/2 - width/2
        y: view.host.y + view.host.height/2 - height/2
        width: view.host.width * 4
        height: view.host.height * 4
        visible: attackAnimation.running
        rotation: -view.facingAngle

        // Swing progress: 0 = start, 1 = end
        property real swingProgress: 0
        property real swingOpacity: 0.9

        onSwingProgressChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var centerX = width / 2
            var centerY = height / 2
            var radius = width * 0.4
            var innerRadius = width * 0.15

            // Swing range 120 degrees
            var swingRange = Math.PI * 0.67
            var startAngle = -swingRange / 2
            var currentAngle = startAngle + (swingProgress * swingRange)

            // Smear: a crescent over the path the blade has covered, brightest
            // just behind the blade, fading towards where the swing began.
            if (view._fx) {
                var segs = 10
                var covered = currentAngle - startAngle
                for (var sI = 0; sI < segs; sI++) {
                    var a0 = startAngle + covered * sI / segs
                    var a1 = startAngle + covered * (sI + 1) / segs + 0.01
                    var k = (sI + 1) / segs
                    var inner = innerRadius * 1.3 + (radius - innerRadius) * 0.35 * (1 - k)
                    ctx.beginPath()
                    ctx.arc(centerX, centerY, radius * (0.96 + 0.04 * k), a0, a1)
                    ctx.arc(centerX, centerY, inner, a1, a0, true)
                    ctx.closePath()
                    ctx.fillStyle = "rgba(210, 236, 255, " + (swingOpacity * 0.55 * k * k) + ")"
                    ctx.fill()
                }
            }

            // Draw motion trails (3 curved arcs = "cut air" effect)
            var arcSpan = 0.18  // ~10 degrees per arc
            for (var i = 3; i >= 1; i--) {
                var trailOffset = currentAngle - (i * 0.25)  // Offset behind blade
                var trailRadius = innerRadius + (radius - innerRadius) * (i / 4)  // Varying radii
                var trailOpacity = swingOpacity * (1.0 - i * 0.25)
                ctx.beginPath()
                ctx.arc(centerX, centerY, trailRadius, trailOffset - arcSpan/2, trailOffset + arcSpan/2)
                ctx.strokeStyle = view._rgba(view.accentColor, trailOpacity)
                ctx.lineWidth = 2
                ctx.stroke()
            }

            // Draw sword blade at leading edge
            var bladeLen = radius - innerRadius
            var bladeW = bladeLen * 0.15
            var bx = centerX + innerRadius * Math.cos(currentAngle)
            var by = centerY + innerRadius * Math.sin(currentAngle)
            var tx = centerX + radius * Math.cos(currentAngle)
            var ty = centerY + radius * Math.sin(currentAngle)
            var perpX = -Math.sin(currentAngle)
            var perpY = Math.cos(currentAngle)

            ctx.beginPath()
            // Tip
            ctx.moveTo(tx, ty)
            // Right shoulder
            ctx.lineTo(centerX + (innerRadius + bladeLen * 0.7) * Math.cos(currentAngle) + perpX * bladeW,
                       centerY + (innerRadius + bladeLen * 0.7) * Math.sin(currentAngle) + perpY * bladeW)
            // Right base
            ctx.lineTo(bx + perpX * bladeW * 0.6, by + perpY * bladeW * 0.6)
            // Cross-guard right
            ctx.lineTo(bx + perpX * bladeW * 0.9, by + perpY * bladeW * 0.9)
            // Cross-guard left
            ctx.lineTo(bx - perpX * bladeW * 0.9, by - perpY * bladeW * 0.9)
            // Left base
            ctx.lineTo(bx - perpX * bladeW * 0.6, by - perpY * bladeW * 0.6)
            // Left shoulder
            ctx.lineTo(centerX + (innerRadius + bladeLen * 0.7) * Math.cos(currentAngle) - perpX * bladeW,
                       centerY + (innerRadius + bladeLen * 0.7) * Math.sin(currentAngle) - perpY * bladeW)
            ctx.closePath()
            ctx.fillStyle = view._rgba(view.bladeColor, swingOpacity)
            ctx.fill()
            ctx.strokeStyle = view._rgba(view.accentColor, swingOpacity)
            ctx.lineWidth = 1.5
            ctx.stroke()

            // Center ridge
            ctx.beginPath()
            ctx.moveTo(bx, by)
            ctx.lineTo(tx, ty)
            ctx.strokeStyle = view._rgba(view.ridgeColor, swingOpacity * 0.8)
            ctx.lineWidth = 1
            ctx.stroke()
        }

        // Swing animation
        SequentialAnimation {
            id: attackAnimation

            // First half of swing (wind up)
            PropertyAnimation {
                target: attackArc
                property: "swingProgress"
                from: 0
                to: 0.5
                duration: view.swingDuration * 500
                easing.type: Easing.OutQuad
            }

            // Second half of swing (follow through)
            PropertyAnimation {
                target: attackArc
                property: "swingProgress"
                from: 0.5
                to: 1
                duration: view.swingDuration * 500
                easing.type: Easing.OutQuad
            }

            // Fade out
            PropertyAnimation {
                target: attackArc
                property: "swingOpacity"
                from: 0.9
                to: 0
                duration: view.swingFade * 1000
            }

            ScriptAction {
                script: {
                    attackArc.swingProgress = 0
                    attackArc.swingOpacity = 0.9
                    view.swingFinished()
                }
            }
        }
    }
}
