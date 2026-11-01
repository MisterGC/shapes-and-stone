import QtQuick

// One of the camp's props (issue #146): a pond, stones, a rail track and
// its cart, a heap of coals... of kind, drawn in one pass by
// shaders/prop.frag over its rectangle. Drawn only; a solid kind gets
// a CampSolid (issue #178) the knights bump into, the flat ones they walk
// over. The glowing kinds go over the darkness (Game.glowParent()).
ShaderEffect {
    id: prop

    readonly property var kinds: ["pond", "stones", "mushrooms", "ferns", "rails", "cart", "crates",
                                  "ore", "timber", "basalt", "cracks", "coals", "slag"]
    readonly property var glowing: ["mushrooms", "cracks", "coals"]

    property real pixelPerUnit: parent ? parent.pixelPerUnit : 1
    property real xWu: 0          // west edge
    property real yWu: 0          // north edge, y up as the world's
    property real widthWu: 1
    property real heightWu: 1
    property string propKind: "stones"
    readonly property bool glows: glowing.indexOf(propKind) >= 0

    // Above the floor and the stains, under everything that walks
    z: -1
    x: xWu * pixelPerUnit
    y: parent ? parent.height - yWu * pixelPerUnit : 0
    width: widthWu * pixelPerUnit
    height: heightWu * pixelPerUnit
    blending: true
    fragmentShader: "shaders/prop.frag.qsb"

    property vector2d sizeWu: Qt.vector2d(widthWu, heightWu)
    property real pixelsPerWu: 12
    property real kind: kinds.indexOf(propKind)
    property real seed: 0
    property real time: 0
}
