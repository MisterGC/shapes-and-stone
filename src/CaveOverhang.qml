import QtQuick

// The camp's rock overhanging one run of a north-facing cave edge (issue
// #145): a ragged lip over the top of the wall face, stalactites hanging
// from it and their shadows on the floor below the face. One pass for the
// whole run (see shaders/overhang.frag), as the motes are drawn. Visual
// only - the wall behind it is what the knights collide with.
ShaderEffect {
    id: oh

    property real pixelPerUnit: parent ? parent.pixelPerUnit : 1
    property real xWu: 0
    property real yWu: 0          // top edge of the face below it (world units)
    property real widthWu: 1
    property real faceWu: 0.7
    property real lipWu: 0.3
    property real stalactiteWu: 0.55
    property real toothWu: 0.7
    property real shadowWu: 1.6
    property real seed: 0
    property color baseColor: "#2C3E50"

    x: xWu * pixelPerUnit
    y: parent ? parent.height - yWu * pixelPerUnit : 0
    width: widthWu * pixelPerUnit
    height: (faceWu + shadowWu) * pixelPerUnit
    blending: true
    fragmentShader: "shaders/overhang.frag.qsb"

    property vector2d originWu: Qt.vector2d(xWu, yWu)
    property vector2d sizeWu: Qt.vector2d(widthWu, faceWu + shadowWu)
    property real pixelsPerWu: 12
}
