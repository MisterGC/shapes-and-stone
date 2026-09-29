import QtQuick

// The visible face of a wall towards the floor south of it, plus the shadow
// it drops onto that floor. Visual only - the physics wall above it is what
// the player collides with. Gives the flat walls a height without leaving
// the top-down view.
Item {
    id: wf

    property real pixelPerUnit: parent ? parent.pixelPerUnit : 1
    property real xWu: 0
    property real yWu: 0          // top edge of the face (world units)
    property real widthWu: 1
    property real heightWu: 0.7
    property real shadowWu: 0.9
    property color color: "#3A4658"

    x: xWu * pixelPerUnit
    y: parent ? parent.height - yWu * pixelPerUnit : 0
    width: widthWu * pixelPerUnit
    height: (heightWu + shadowWu) * pixelPerUnit

    ShaderEffect {
        id: bricks
        width: parent.width
        height: wf.heightWu * wf.pixelPerUnit
        fragmentShader: "shaders/wall.frag.qsb"
        property vector2d originWu: Qt.vector2d(wf.xWu, wf.yWu)
        property vector2d sizeWu: Qt.vector2d(wf.widthWu, wf.heightWu)
        property real pixelsPerWu: 12
        property real face: 1
        property color baseColor: wf.color
    }

    // Soft contact shadow on the floor at the foot of the face
    Rectangle {
        anchors.top: bricks.bottom
        width: parent.width
        height: wf.shadowWu * wf.pixelPerUnit
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#99000000" }
            GradientStop { position: 0.35; color: "#40000000" }
            GradientStop { position: 1.0; color: "#00000000" }
        }
    }
}
