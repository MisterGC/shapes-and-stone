import QtQuick
import Clayground.Canvas

Rectangle {
    id: floor

    // Non-physics floor tile (visual only)
    // Floor doesn't need collision - walls handle boundaries

    // Position in world units (set by parent)
    property real xWu: 0
    property real yWu: 0
    property real widthWu: 1
    property real heightWu: 1

    // Visual: Dark floor color
    color: "#1a1a2e"

    // Subtle grid pattern
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: "#252540"
        border.width: 1
        opacity: 0.3
    }
}
