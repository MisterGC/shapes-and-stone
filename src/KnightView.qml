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
    // Mana is low: the raised shield thins and blinks
    property bool lowShield: false
    // At 0 HP: the knight slumps to the floor, dark, its lantern low and
    // no aim shown - the same on every screen that draws it
    property bool downed: false
    // How far an ally has lifted the downed knight up, 0..1: the ring
    // around it (Balance.party)
    property real reviveProgress: 0
    readonly property color _ringColor: Balance.party.ringColor
    // The left button is held for a heavy swing: the blade, drawn back,
    // glows brighter with charge (0..1); when chargeFull a ring flashes out
    property bool charging: false
    property real charge: 0
    property bool chargeFull: false
    readonly property color _glow: Balance.heavy.glow
    onChargeFullChanged: if (chargeFull) chargeRingFlash.restart()
    // The smith's sword and shield levels of the run, 0 for none: a
    // sharpened sword's blade has a brighter, wider edge, a reinforced
    // shield a lighter rim along its outside
    property int swordLevel: 0
    property int shieldLevel: 0
    // The potions and mana draughts the knight carries: a vial of each kind
    // it has at its belt, with the count beside it. Only the local Player
    // knows them; a remote knight carries none to show
    property int potions: 0
    property int draughts: 0
    readonly property color _edgeColor: Qt.lighter(accentColor, 1.6)
    readonly property color _rimColor: Qt.lighter(accentColor, 1.8)
    onSwordLevelChanged: chargeBlade.requestPaint()
    onShieldLevelChanged: shieldArc.requestPaint()

    // Seconds, from the balance table: wind up plus follow through, and
    // the fade of the arc after it
    property real swingDuration: Balance.knight.swingDuration
    readonly property real swingFade: Balance.knight.swingFade
    readonly property bool swinging: attackAnimation.running || whirlAnimation.running
    readonly property bool whirling: whirlAnimation.running

    // The swing animation ended (fade included)
    signal swingFinished()

    readonly property bool _fx: gameWorld ? gameWorld.fx === true : false

    // heavy: the charged swing, wider, longer and glowing
    function swing(heavy) {
        whirlAnimation.stop()
        attackArc.whirl = false
        attackArc.heavy = heavy === true
        attackArc.swingProgress = 0
        attackArc.swingOpacity = 0.9
        attackArc.requestPaint()
        attackAnimation.restart()
    }

    // The whirlwind: the blade spins Balance.whirl.turns times round the
    // knight in durationMs, glowing, with the dash's afterimages
    function whirl(durationMs) {
        attackAnimation.stop()
        attackArc.heavy = true
        attackArc.whirl = true
        attackArc.swingProgress = 0
        attackArc.swingOpacity = 0.9
        whirlSpin.duration = durationMs
        whirlAnimation.restart()
        dash(durationMs)
    }

    // durationMs keeps the afterimages coming when the driver's dashing
    // state is too coarse to show the whole dash
    function dash(durationMs) {
        dashFlash.restart()
        _dashTrail.interval = durationMs
        _dashTrail.restart()
    }

    function parry() { parryGlow.restart() }
    // The shield took a blow: it flashes white and bumps out; a perfect
    // block flashes longer, swells further and lights the knight pale blue
    function block() {
        shieldArc.perfect = false
        shieldFlash.restart()
    }
    function perfectBlock() {
        shieldArc.perfect = true
        shieldFlash.restart()
        perfectGlow.restart()
    }
    function hurt() { hurtLeft = Balance.hurt.flash }
    // The shield ran dry: its arc splits into grey shards that fly apart
    function shieldBreak() {
        shieldShards.angle = view.facingAngle
        shardAge = 0
    }

    // The hurt flash, the low shield's blink and the shards count the time
    // the physics steps simulate, as the grace does: a pause or the hit
    // stop of the blow that caused them holds them with the world, and a
    // single step in the dojo advances them by a step
    property real hurtLeft: 0
    property real blinkT: 0
    // Seconds since the shield broke; at shardTime the shards are gone
    property real shardAge: Balance.shieldBreak.shardTime
    Connections {
        target: view.host && view.host.world ? view.host.world : null
        function onStepped() {
            let dt = view.host.world.timeStep
            if (view.hurtLeft > 0) view.hurtLeft = view.hurtLeft - dt < 1e-6 ? 0 : view.hurtLeft - dt
            view.blinkT = view.blocking && view.lowShield ? view.blinkT + dt : 0
            if (view.shardAge < Balance.shieldBreak.shardTime)
                view.shardAge = Math.min(Balance.shieldBreak.shardTime, view.shardAge + dt)
        }
    }

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
        intensity: view.downed ? 0.35 : 1.0
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
                xScale: view.downed ? 1.2 : view._fx ? 1 - 0.02 * view._breath + 0.03 * view._step : 1
                yScale: view.downed ? 0.5 : view._fx ? 1 + 0.03 * view._breath - 0.05 * view._step : 1
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

        // Hurt flash: red for a moment, then the white grace flicker takes
        // over - a hurt never looks like the grace that follows it
        Rectangle {
            id: hurtFlashRect
            objectName: "hurtFlash"
            anchors.fill: parent
            radius: parent.radius
            color: Balance.hurt.color
            opacity: view.hurtLeft > 0 ? 0.95 : 0
            // Above the grace flicker while it shows
            z: 1
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

        // Perfect block glow
        Rectangle {
            id: perfectGlowRect
            anchors.fill: parent
            radius: parent.radius
            color: Balance.perfectBlock.flashColor
            opacity: 0
        }

        PropertyAnimation {
            id: perfectGlow
            target: perfectGlowRect; property: "opacity"; from: 0.7; to: 0
            duration: Balance.perfectBlock.glow * 1000
        }

        // Downed: the body darkens
        Rectangle {
            objectName: "downedShade"
            anchors.fill: parent
            radius: parent.radius
            color: "#000000"
            opacity: view.downed ? 0.55 : 0
        }
    }

    // The vials: at the belt, on the side away from the lantern, so the
    // knight shows how well it is stocked. Upright like the lantern
    Row {
        id: belt
        objectName: "knightBelt"
        visible: view.potions > 0 || view.draughts > 0
        opacity: view.downed ? 0.5 : 1
        readonly property real angleRad: (view.facingAngle - 100) * Math.PI / 180
        readonly property real orbit: view.width * 0.6
        spacing: view.width * 0.08
        x: view.width / 2 - width / 2 + Math.cos(angleRad) * orbit
        y: view.height / 2 - height / 2 - Math.sin(angleRad) * orbit
        z: view.facingAngle < 0 && view.facingAngle > -180 ? -0.5 : 1
        Repeater {
            model: [{n: view.potions, fill: "#5FD05F", name: "potion"},
                    {n: view.draughts, fill: "#B080E0", name: "draught"}]
            delegate: Item {
                objectName: "beltVial_" + modelData.name
                visible: modelData.n > 0
                width: vial.width + count.width
                height: vial.height
                // Neck, cork and the round body
                Item {
                    id: vial
                    width: view.width * 0.2
                    height: width * 1.5
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.4; height: parent.height * 0.36
                        color: "#C8D8E0"
                        border.color: "#2A2420"; border.width: Math.max(1, parent.width * 0.08)
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width; height: width
                        radius: width / 2
                        color: modelData.fill
                        border.color: "#2A2420"; border.width: Math.max(1, parent.width * 0.1)
                    }
                }
                Text {
                    id: count
                    objectName: "beltCount"
                    anchors.bottom: parent.bottom
                    leftPadding: 1
                    text: modelData.n
                    color: "#FFFFFF"
                    style: Text.Outline
                    styleColor: "#000000"
                    font.pixelSize: Math.max(9, view.width * 0.28)
                    font.bold: true
                }
            }
        }
    }

    // The lantern: carried in the off hand, a quarter turn from the facing
    // direction, swinging a little with each step. The light around the
    // knight has a source you can see.
    Item {
        id: lantern
        visible: view._fx
        opacity: view.downed ? 0.5 : 1
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
        scale: 1 + ((perfect ? Balance.perfectBlock.bump : Balance.block.bump) - 1) * flash
        // Low on mana it blinks; a blow's flash shows through the blink
        opacity: view.lowShield && !_blinkOn && flash <= 0 ? 0.25 : 1
        // 1 the moment a blow lands on it, back to 0 as its flash fades
        property real flash: 0
        // The blow it flashes for was blocked perfectly
        property bool perfect: false
        // Thinner when mana runs low
        readonly property real thickness: view.lowShield ? 0.12 : 0.25
        // On for the first half of each blink, counted from when it began
        readonly property bool _blinkOn: Math.floor(view.blinkT * Balance.shieldBreak.blink * 2) % 2 === 0
        onThicknessChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height
            var cx = w / 2, cy = h / 2, r = w * 0.4, half = w * thickness / 2
            var a0 = -Math.PI * 0.4, a1 = Math.PI * 0.4
            var band = function() {
                ctx.beginPath()
                ctx.arc(cx, cy, r + half, a0, a1)
                ctx.arc(cx, cy, r - half, a1, a0, true)
                ctx.closePath()
            }
            // Steel: bevelled across the band, darker at both edges
            var steel = ctx.createRadialGradient(cx, cy, r - half, cx, cy, r + half)
            steel.addColorStop(0, "#5E6870")
            steel.addColorStop(0.35, "#C9D2D9")
            steel.addColorStop(0.55, "#9AA6AF")
            steel.addColorStop(1, "#4A535A")
            band()
            ctx.fillStyle = steel
            ctx.fill()
            // A sheen from the top, fading down the arc
            var sheen = ctx.createLinearGradient(0, cy - r - half, 0, cy + r + half)
            sheen.addColorStop(0, "rgba(255,255,255,0.45)")
            sheen.addColorStop(0.45, "rgba(255,255,255,0)")
            sheen.addColorStop(1, "rgba(0,0,0,0.25)")
            band()
            ctx.fillStyle = sheen
            ctx.fill()
            // Its edge in the knight's own colour, so knights stay apart
            band()
            ctx.strokeStyle = Qt.darker(view.accentColor, 1.6)
            ctx.lineWidth = Math.max(1, w * 0.025)
            ctx.stroke()
            // Rivets along the middle of the band
            for (var i = -1; i <= 1; i++) {
                var ra = i * Math.PI * 0.26
                var rx = cx + Math.cos(ra) * r, ry = cy + Math.sin(ra) * r
                var rr = Math.max(1, w * thickness * 0.14)
                ctx.beginPath()
                ctx.arc(rx, ry, rr, 0, Math.PI * 2)
                ctx.fillStyle = "#3A4248"
                ctx.fill()
                ctx.beginPath()
                ctx.arc(rx - rr * 0.3, ry - rr * 0.3, rr * 0.45, 0, Math.PI * 2)
                ctx.fillStyle = "#E8EEF2"
                ctx.fill()
            }
            if (view.shieldLevel > 0) {
                ctx.beginPath()
                ctx.arc(w / 2, h / 2, w * (0.4 + thickness / 2), -Math.PI * 0.4, Math.PI * 0.4)
                ctx.strokeStyle = view._rimColor
                ctx.lineWidth = w * 0.09
                ctx.stroke()
            }
        }

        onVisibleChanged: if (visible) requestPaint()

        // The flash: the same arc in white over it
        Canvas {
            anchors.fill: parent
            opacity: shieldArc.flash
            visible: opacity > 0
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width, h = height
                ctx.beginPath()
                ctx.arc(w / 2, h / 2, w * 0.4, -Math.PI * 0.4, Math.PI * 0.4)
                ctx.strokeStyle = "#FFFFFF"
                ctx.lineWidth = w * 0.25
                ctx.stroke()
            }
            Component.onCompleted: requestPaint()
        }

        NumberAnimation {
            id: shieldFlash
            target: shieldArc; property: "flash"
            from: 1; to: 0
            duration: (shieldArc.perfect ? Balance.perfectBlock.flash : Balance.block.flash) * 1000
            easing.type: Easing.OutCubic
        }
    }

    // The broken shield: the arc in shards grey pieces, flying apart from
    // where it was and fading out
    Item {
        id: shieldShards
        objectName: "shieldShards"
        readonly property real shieldSize: view.width * 0.8
        readonly property real orbitRadius: view.width * 0.5
        // The facing when it broke: the shards keep it while the knight turns
        property real angle: 0
        readonly property real angleRad: angle * Math.PI / 180
        // 0 the moment it breaks, 1 when the shards are gone, eased out
        readonly property real age: view.shardAge / Balance.shieldBreak.shardTime
        readonly property real t: 1 - (1 - age) * (1 - age)
        visible: age < 1
        width: shieldSize
        height: shieldSize
        x: view.width / 2 - width / 2 + Math.cos(angleRad) * orbitRadius
        y: view.height / 2 - height / 2 - Math.sin(angleRad) * orbitRadius
        rotation: -angle
        opacity: 1 - t

        Repeater {
            model: Balance.shieldBreak.shards
            Canvas {
                id: shard
                required property int index
                readonly property int count: Balance.shieldBreak.shards
                // This shard's part of the arc and the direction it flies
                readonly property real a0: -Math.PI * 0.4 + Math.PI * 0.8 * index / count
                readonly property real a1: -Math.PI * 0.4 + Math.PI * 0.8 * (index + 1) / count
                readonly property real mid: (a0 + a1) / 2
                anchors.fill: parent
                transform: [
                    Rotation {
                        origin.x: shard.width / 2 + Math.cos(shard.mid) * shard.width * 0.4
                        origin.y: shard.height / 2 + Math.sin(shard.mid) * shard.height * 0.4
                        angle: (shard.index - (shard.count - 1) / 2) * 45 * shieldShards.t
                    },
                    Translate {
                        x: Math.cos(shard.mid) * shard.width * 0.6 * shieldShards.t
                        y: Math.sin(shard.mid) * shard.height * 0.6 * shieldShards.t
                    }
                ]
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var w = width, h = height
                    ctx.beginPath()
                    // A gap between the pieces: the cracks
                    ctx.arc(w / 2, h / 2, w * 0.4, a0 + 0.06, a1 - 0.06)
                    ctx.strokeStyle = "#8A8E94"
                    ctx.lineWidth = w * 0.2
                    ctx.stroke()
                }
                Component.onCompleted: requestPaint()
            }
        }
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
        visible: !view.downed
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

    // The charge: the blade drawn back at the far edge of the heavy arc,
    // its colour going from the blade's to Balance.heavy.glow, with a halo
    // that grows with the charge. Reparented like the swing.
    Canvas {
        id: chargeBlade
        objectName: "chargeBlade"
        parent: view.host.parent
        x: view.host.x + view.host.width/2 - width/2
        y: view.host.y + view.host.height/2 - height/2
        width: view.host.width * 4
        height: view.host.height * 4
        visible: view.charging && !view.downed && !attackAnimation.running
        rotation: -view.facingAngle
        readonly property real charge: view.charge
        onChargeChanged: requestPaint()
        onVisibleChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var c = view.charge
            var glow = view._glow
            var cx = width / 2, cy = height / 2
            var a = -Balance.knight.heavyArc * Math.PI / 180
            var inner = view.host.width * 0.55, outer = view.host.width * 1.4
            var bx = cx + inner * Math.cos(a), by = cy + inner * Math.sin(a)
            var tx = cx + outer * Math.cos(a), ty = cy + outer * Math.sin(a)
            var px = -Math.sin(a), py = Math.cos(a)
            var w = (outer - inner) * 0.1
            // Halo
            ctx.beginPath()
            ctx.moveTo(tx, ty)
            ctx.lineTo(bx, by)
            ctx.strokeStyle = view._rgba(glow, 0.15 + 0.45 * c)
            ctx.lineWidth = w * (2 + 3 * c)
            ctx.lineCap = "round"
            ctx.stroke()
            // Blade
            ctx.beginPath()
            ctx.moveTo(tx, ty)
            ctx.lineTo(bx + px * w, by + py * w)
            ctx.lineTo(bx - px * w, by - py * w)
            ctx.closePath()
            var r = view.bladeColor.r + (glow.r - view.bladeColor.r) * c
            var g = view.bladeColor.g + (glow.g - view.bladeColor.g) * c
            var b = view.bladeColor.b + (glow.b - view.bladeColor.b) * c
            ctx.fillStyle = "rgba(" + Math.round(r * 255) + ", " + Math.round(g * 255) + ", "
                    + Math.round(b * 255) + ", 1)"
            ctx.fill()
            var sharp = view.swordLevel > 0
            ctx.strokeStyle = view.chargeFull ? "#FFFFFF"
                                              : view._rgba(sharp ? view._edgeColor : view.accentColor, 0.9)
            ctx.lineWidth = view.chargeFull || sharp ? 2 : 1
            ctx.stroke()
        }
    }

    // The charge is full: a ring flashes out from the knight
    Rectangle {
        id: chargeRing
        objectName: "chargeRing"
        parent: view.host.parent
        width: view.host.width
        height: view.host.height
        x: view.host.x
        y: view.host.y
        radius: width / 2
        color: "transparent"
        border.color: Balance.heavy.ringColor
        border.width: Math.max(1, view.host.width * 0.06)
        opacity: 0
        visible: opacity > 0
        ParallelAnimation {
            id: chargeRingFlash
            NumberAnimation {
                target: chargeRing; property: "scale"
                from: 1; to: Balance.heavy.ringScale
                duration: Balance.heavy.ring * 1000; easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: chargeRing; property: "opacity"
                from: 0.9; to: 0
                duration: Balance.heavy.ring * 1000
            }
        }
    }

    // A downed knight an ally lifts up: a ring fills clockwise around it
    // from the top, full when the knight rises. Reparented like the swing
    Canvas {
        id: reviveRing
        objectName: "reviveRing"
        parent: view.host.parent
        width: view.host.width * Balance.party.ringRadius * 2 + Balance.party.ringWidth * 2
        height: width
        x: view.host.x + view.host.width / 2 - width / 2
        y: view.host.y + view.host.height / 2 - height / 2
        visible: view.downed && view.reviveProgress > 0
        readonly property real progress: view.reviveProgress
        onProgressChanged: requestPaint()
        onVisibleChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var r = view.host.width * Balance.party.ringRadius
            var start = -Math.PI / 2
            ctx.lineWidth = Balance.party.ringWidth
            ctx.strokeStyle = view._rgba(view._ringColor, 0.2)
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, r, 0, 2 * Math.PI)
            ctx.stroke()
            ctx.strokeStyle = view._rgba(view._ringColor, 1)
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, r, start, start + 2 * Math.PI * Math.min(1, progress))
            ctx.stroke()
        }
    }

    // Attack swing visualization
    // Reparented to avoid inflating the body's childrenRect.
    Canvas {
        id: attackArc
        parent: view.host.parent
        x: view.host.x + view.host.width/2 - width/2
        y: view.host.y + view.host.height/2 - height/2
        width: view.host.width * 5
        height: view.host.height * 5
        visible: attackAnimation.running || whirlAnimation.running
        rotation: -view.facingAngle

        // Swing progress: 0 = start, 1 = end
        property real swingProgress: 0
        property real swingOpacity: 0.9
        // The charged swing: its arc and reach (Balance.knight.heavy...)
        property bool heavy: false
        // The whirlwind: full turns (Balance.whirl), the smear behind the
        // blade no longer than Balance.whirl.smear
        property bool whirl: false

        onSwingProgressChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var centerX = width / 2
            var centerY = height / 2
            var reach = heavy ? Balance.knight.heavyRange : 1
            var radius = view.host.width * 1.6 * reach
            var innerRadius = view.host.width * 0.6

            // Swing range 120 degrees, a heavy one twice its arc
            var swingRange = whirl ? Balance.whirl.turns * 2 * Math.PI
                           : heavy ? Balance.knight.heavyArc * Math.PI / 90 : Math.PI * 0.67
            var startAngle = -swingRange / 2
            var currentAngle = startAngle + (swingProgress * swingRange)
            if (whirl) startAngle = Math.max(startAngle, currentAngle - Balance.whirl.smear * Math.PI / 180)

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
                    ctx.fillStyle = heavy ? view._rgba(view._glow, swingOpacity * 0.75 * k * k)
                                          : "rgba(210, 236, 255, " + (swingOpacity * 0.55 * k * k) + ")"
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
                ctx.strokeStyle = view._rgba(heavy ? view._glow : view.accentColor, trailOpacity)
                ctx.lineWidth = heavy ? 3 : 2
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
            ctx.fillStyle = view._rgba(heavy ? view._glow : view.bladeColor, swingOpacity)
            ctx.fill()
            var sharp = view.swordLevel > 0
            ctx.strokeStyle = view._rgba(sharp ? view._edgeColor : view.accentColor, swingOpacity)
            ctx.lineWidth = sharp ? 2.5 : 1.5
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

        // Whirlwind animation: one even spin, then the fade
        SequentialAnimation {
            id: whirlAnimation
            PropertyAnimation {
                id: whirlSpin
                target: attackArc
                property: "swingProgress"
                from: 0
                to: 1
                duration: Balance.knight.whirlDuration * 1000
            }
            PropertyAnimation {
                target: attackArc
                property: "swingOpacity"
                from: 0.9
                to: 0
                duration: view.swingFade * 1000
            }
            ScriptAction {
                script: {
                    attackArc.whirl = false
                    attackArc.swingProgress = 0
                    attackArc.swingOpacity = 0.9
                    view.swingFinished()
                }
            }
        }
    }
}
