import QtQuick
import Clayground.World

// Stairs leading down at the level exit: steps that darken as they descend
// and a slow cold pulse, so the way on reads from across the room.
Item {
    id: stairs

    property real pixelPerUnit: parent ? parent.pixelPerUnit : 1
    property real xWu: 0          // left edge
    property real yWu: 0          // top edge
    property real widthWu: 2
    property real heightWu: 2
    property color glow: "#6FA8FF"

    z: -1
    x: xWu * pixelPerUnit
    y: parent ? parent.height - yWu * pixelPerUnit : 0
    width: widthWu * pixelPerUnit
    height: heightWu * pixelPerUnit

    // A cold light rising from below
    Light2d {
        // Follows its parent's top-left corner; offset to the steps' middle
        offsetXWu: stairs.widthWu / 2
        offsetYWu: -stairs.heightWu * 0.6
        radius: 6
        color: stairs.glow
        intensity: 0.8
        flicker: 0.1
    }

    Rectangle { anchors.fill: parent; color: "#07070C" }

    Repeater {
        model: 6
        Rectangle {
            required property int index
            // Step 0 is the lowest on screen and the nearest to the player
            readonly property real k: index / 6
            x: stairs.width * 0.06 * (1 + k * 1.5)
            width: stairs.width - 2 * x
            y: stairs.height * (1 - (index + 1) / 6)
            height: stairs.height / 6 * 0.72
            color: Qt.darker("#5A6478", 1 + k * 2.2)
            Rectangle {
                width: parent.width
                height: Math.max(1, parent.height * 0.18)
                color: Qt.lighter(parent.color, 1.35)
            }
        }
    }

    Rectangle {
        id: pulse
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(stairs.glow.r, stairs.glow.g, stairs.glow.b, 0.55) }
            GradientStop { position: 1.0; color: "transparent" }
        }
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { from: 0.35; to: 0.8; duration: 1600; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.8; to: 0.35; duration: 1600; easing.type: Easing.InOutSine }
        }
    }
}
