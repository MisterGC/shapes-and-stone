import QtQuick
import Box2D
import Clayground.Physics

RectBoxBody {
    id: wall

    // Physics config - static, immovable
    bodyType: Body.Static
    friction: 0.0      // No friction so players slide along walls
    restitution: 0.0   // No bounce

    // Visual: Dark stone color (no border)
    color: "#2C3E50"

    // Procedural rock top (see shaders/wall.frag). Round props (tree) and
    // invisible blockers keep their plain look.
    property bool fx: true

    ShaderEffect {
        anchors.fill: parent
        visible: wall.fx && wall.radius === 0 && wall.opacity > 0
        fragmentShader: "shaders/wall.frag.qsb"
        property vector2d originWu: Qt.vector2d(wall.xWu, wall.yWu)
        property vector2d sizeWu: Qt.vector2d(wall.widthWu, wall.heightWu)
        property real pixelsPerWu: 12
        property real face: 0
        property color baseColor: wall.color
    }
}
