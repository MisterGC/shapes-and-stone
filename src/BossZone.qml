import QtQuick

// A floor zone of the Warden's phase 2 (Balance.boss.zone, issue #274): a
// crack opens in the floor and a ring in the arrow slits' glow closes on
// it, as a slit's ring closes before its shot, then the floor bursts in
// the Warden's core colour and fades. Game's BossFight runs it on its
// clock; this only draws it: warn runs from 0 to 1 while it warns, burst
// from 1 down to 0 after it hurt
Item {
    id: zone

    property real pixelPerUnit: 1
    property string zoneId: ""
    property real xWu: 0
    property real yWu: 0
    property real radiusWu: 1.3
    property real warn: 0
    property real burst: 0
    // Where the ring is drawn: above the darkness, as an enemy's
    property Item ringParent: null

    z: -1
    x: xWu * pixelPerUnit - width / 2
    y: (parent ? parent.height : 0) - yWu * pixelPerUnit - height / 2
    width: 2 * radiusWu * pixelPerUnit
    height: width

    // The crack in the floor, darker as the ring closes
    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: width
        radius: width / 2
        color: "#000000"
        opacity: 0.18 + 0.32 * zone.warn
        border.color: Balance.dungeon.slitGlowColor
        border.width: Math.max(1, zone.width * 0.02)
    }
    Canvas {
        anchors.fill: parent
        onPaint: {
            let ctx = getContext("2d")
            ctx.reset()
            let w = width, c = w / 2
            ctx.strokeStyle = "#0A0807"
            ctx.lineWidth = Math.max(1, w * 0.025)
            ctx.beginPath()
            for (let i = 0; i < 5; i++) {
                let a = i * 1.257 + 0.4
                ctx.moveTo(c, c)
                ctx.lineTo(c + Math.cos(a) * w * 0.22, c + Math.sin(a) * w * 0.22)
                ctx.lineTo(c + Math.cos(a + 0.3) * w * 0.42, c + Math.sin(a + 0.3) * w * 0.42)
            }
            ctx.stroke()
        }
        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
    }
    // The burst, fading
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * (0.7 + 0.3 * (1 - zone.burst))
        height: width
        radius: width / 2
        color: Balance.boss.coreColor
        opacity: 0.7 * zone.burst
        visible: zone.burst > 0
    }
    // The ring closing on the zone's outline, white as it hurts
    Rectangle {
        objectName: "zoneRing"
        parent: zone.ringParent ? zone.ringParent : zone
        visible: zone.warn > 0 && zone.burst <= 0
        readonly property real size: zone.width * (Balance.parryRing.from - (Balance.parryRing.from - 1) * zone.warn)
        width: size
        height: size
        radius: size / 2
        x: (parent === zone ? 0 : zone.x) + (zone.width - size) / 2
        y: (parent === zone ? 0 : zone.y) + (zone.height - size) / 2
        color: "transparent"
        border.width: Math.max(1.5, zone.width * Balance.parryRing.thickness * 0.5)
        border.color: zone.warn >= 1 ? Balance.parryRing.flashColor : Balance.dungeon.slitGlowColor
        opacity: Balance.parryRing.opacity
    }
}
