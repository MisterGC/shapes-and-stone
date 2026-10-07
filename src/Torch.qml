import QtQuick
import Clayground.World

// A wall torch: an iron bracket, a flame drawn from three flickering layered
// shapes, and the light it throws. Visual only - no physics.
Item {
    id: torch

    property real pixelPerUnit: parent ? parent.pixelPerUnit : 1
    property real xWu: 0
    property real yWu: 0          // centre of the flame (world units)
    property color flameColor: "#FF9A3C"
    property real sizeWu: 0.55

    // Every torch burns on its own rhythm
    property real phase: Math.random() * 10

    x: xWu * pixelPerUnit - width / 2
    y: parent ? parent.height - yWu * pixelPerUnit - height / 2 : 0
    width: sizeWu * pixelPerUnit
    height: width

    // The light it throws, a little in front of the wall so the wall's own
    // cell does not swallow it
    Light2d {
        offsetYWu: -0.5
        radius: torch.lightRadius
        color: torch.flameColor
        intensity: 1.0
        flicker: 0.45
    }
    property real lightRadius: 8

    // Bracket
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.62
        width: parent.width * 0.18
        height: parent.height * 0.42
        color: "#2A2420"
    }
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.55
        width: parent.width * 0.42
        height: parent.height * 0.12
        color: "#3A302A"
    }

    property real _t: 0
    NumberAnimation on _t {
        from: 0; to: 1000; duration: 1000000
        loops: Animation.Infinite
    }
    readonly property real flicker: 0.5 + 0.3 * Math.sin((_t + phase) * 17.0)
                                    + 0.2 * Math.sin((_t + phase) * 41.0)

    // Flame: outer, mid and core tongues, each swaying on its own
    Repeater {
        model: [
            { w: 0.62, h: 0.78, c: Qt.darker(torch.flameColor, 1.25), a: 0.9, s: 1.0 },
            { w: 0.44, h: 0.6, c: torch.flameColor, a: 1.0, s: 1.4 },
            { w: 0.24, h: 0.38, c: "#FFE9A8", a: 1.0, s: 2.0 }
        ]
        Rectangle {
            required property var modelData
            readonly property real sway: Math.sin((torch._t + torch.phase) * 9.0 * modelData.s) * 0.06
            width: torch.width * modelData.w
            height: torch.height * modelData.h * (0.85 + 0.25 * torch.flicker)
            x: torch.width * (0.5 + sway) - width / 2
            y: torch.height * 0.62 - height
            radius: width / 2
            color: modelData.c
            opacity: modelData.a
            antialiasing: true
        }
    }
}
