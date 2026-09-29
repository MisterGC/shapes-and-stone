import QtQuick

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

    // Procedural ground (see shaders/floor.frag); false shows the flat floor
    property bool fx: true
    // "stone" (dungeon flagstones) or "earth" (village ground)
    property string style: "stone"
    property real seed: 0

    // Beneath stains, walls and everything that moves
    z: -2

    // Convert world units to pixels (match PhysicsItem convention)
    x: xWu * pixelPerUnit
    y: parent ? parent.height - yWu * pixelPerUnit : 0
    width: widthWu * pixelPerUnit
    height: heightWu * pixelPerUnit

    // Visual: dark floor colour. With fx on the stone is a neutral grey -
    // the bluish tone turned salmon under warm torchlight.
    color: fx ? "#2B2A2C" : "#252538"

    // Subtle grid pattern
    Rectangle {
        anchors.fill: parent
        visible: !floor.fx
        color: "transparent"
        border.color: "#303050"
        border.width: 1
        opacity: 0.5
    }

    ShaderEffect {
        anchors.fill: parent
        visible: floor.fx
        fragmentShader: "shaders/floor.frag.qsb"
        property vector2d sizeWu: Qt.vector2d(floor.widthWu, floor.heightWu)
        property real pixelsPerWu: 16
        // Half a character across: at a whole unit a stone was as big as the
        // knight and the floor read like a giant's hall
        property real stoneWu: 0.5
        // Half a chunky pixel: a full one made the gaps as loud as the stones
        property real seamPx: 0.5
        property real style: floor.style === "earth" ? 1 : 0
        property real seed: floor.seed
        property color baseColor: floor.color
        property color seamColor: Qt.darker(floor.color, 1.45)
    }
}
