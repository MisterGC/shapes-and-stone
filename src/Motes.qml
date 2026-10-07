import QtQuick

// Dust in the dungeon air or fireflies over the village, across the whole
// level in world units (see shaders/motes.frag). Visual only.
ShaderEffect {
    id: motes

    property real pixelPerUnit: parent ? parent.pixelPerUnit : 1
    property real widthWu: 100
    property real heightWu: 100
    property bool fireflies: false

    z: 4
    x: 0
    y: parent ? parent.height - heightWu * pixelPerUnit : 0
    width: widthWu * pixelPerUnit
    height: heightWu * pixelPerUnit
    blending: true
    fragmentShader: "shaders/motes.frag.qsb"

    property vector2d sizeWu: Qt.vector2d(widthWu, heightWu)
    property real time: 0
    property real pixelsPerWu: 12
    property real density: fireflies ? 0.05 : 0.35
    property real moteSize: fireflies ? 0.06 : 0.045
    property real blink: fireflies ? 1 : 0
    property real drift: fireflies ? 0.9 : 0.35
    property color color: fireflies ? Qt.rgba(0.75, 1.0, 0.45, 0.9) : Qt.rgba(1.0, 0.85, 0.6, 0.35)

    NumberAnimation on time {
        from: 0; to: 3600; duration: 3600000
        loops: Animation.Infinite
    }
}
