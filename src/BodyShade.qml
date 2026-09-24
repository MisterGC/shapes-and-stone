import QtQuick

// Cel shading for a round body, lit from the top-left like the floor and the
// walls (see shaders/body.frag): light and shadow crescents and a thin dark
// outline that keeps the shape apart from the textured floor. Place it as
// the first child of the body's visual so icons stay on top.
ShaderEffect {
    // The body colour; the outline is a darker shade of it
    property color baseColor: "#808080"

    anchors.fill: parent
    fragmentShader: "shaders/body.frag.qsb"
    property color outlineColor: Qt.darker(baseColor, 2.4)
    property real outline: 0.09
}
