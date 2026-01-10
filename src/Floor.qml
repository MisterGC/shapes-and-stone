import QtQuick
import Clayground.Canvas

Rectangle {
    id: floor

    // Non-physics floor tile (visual only)
    // Floor doesn't need collision - walls handle boundaries

    // World unit properties
    property real pixelPerUnit: parent ? parent.pixelPerUnit : 1
    property real xWu: 0
    property real yWu: 0
    property real widthWu: 1
    property real heightWu: 1

    // Convert world units to pixels (match PhysicsItem convention)
    x: xWu * pixelPerUnit
    y: parent ? parent.height - yWu * pixelPerUnit : 0
    width: widthWu * pixelPerUnit
    height: heightWu * pixelPerUnit

    // Visual: Dark floor color
    color: "#252538"

    // Subtle grid pattern
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: "#303050"
        border.width: 1
        opacity: 0.5
    }
}
