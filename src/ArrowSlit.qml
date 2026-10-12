import QtQuick

// An arrow slit in a dungeon's wall (Balance.dungeon.slit...): a narrow
// dark opening in a stone frame, set into the wall beside its feature's
// cell, that fires across the room along (dirX, dirY), y up. Before each
// shot a ring in the telegraph colour closes on it, as an enemy's parry
// ring closes on the enemy, and the opening glows; the ring flashes white
// as the arrow leaves. Game._stepSlits runs it; this only draws it.
Item {
    id: slit

    property real pixelPerUnit: 1
    // The feature it stands for: its cell ("gx,gy"), the muzzle on the
    // wall's face, where its arrows leave, and the way they fly
    property string cell: ""
    property real xWu: 0
    property real yWu: 0
    property int dirX: 0
    property int dirY: 0
    // How far its arrows fly, muzzle to the wall facing it, wu
    property real lineWu: 0
    // Its rhythm: its name, the beats (1 a shot, 0 a rest) and the beat
    // the rhythm starts on, counted from the clock's 0
    property string rhythm: ""
    property var beats: [1]
    property int offset: 0
    property int band: 0
    // The next shot's wind-up, 0..1 (0 none under way), and whether one
    // just left
    property real warn: 0
    property bool flash: false
    // The clock's moment its last arrow left, s
    property real shotAt: -1000
    // Where the ring is drawn: above the darkness, as an enemy's
    property Item ringParent: null

    readonly property bool _across: dirX !== 0
    readonly property real _sizeWu: 1.0

    // Over the wall it is set in
    z: 1
    // Set a little into the wall, so the opening sits on its face
    x: (xWu - dirX * 0.3) * pixelPerUnit - width / 2
    y: (parent ? parent.height : 0) - (yWu - dirY * 0.3) * pixelPerUnit - height / 2
    width: _sizeWu * pixelPerUnit
    height: width

    // The frame's stone by the look: sandstone, grey, soot
    readonly property color _stone: ["#7A6C58", "#62656B", "#463A38"][band]
    readonly property color _glow: Balance.dungeon.slitGlowColor

    Rectangle {
        id: frame
        anchors.centerIn: parent
        width: parent.width * (slit._across ? 0.42 : 0.9)
        height: parent.height * (slit._across ? 0.9 : 0.42)
        radius: Math.min(width, height) * 0.2
        color: slit._stone
        border.color: Qt.darker(slit._stone, 1.8)
        border.width: Math.max(1, slit.width * 0.04)

        // The opening, dark, glowing from inside while it winds up
        Rectangle {
            anchors.centerIn: parent
            width: slit._across ? parent.width * 0.3 : parent.width * 0.78
            height: slit._across ? parent.height * 0.78 : parent.height * 0.3
            radius: Math.min(width, height) / 2
            color: slit.flash ? "#FFFFFF"
                 : Qt.rgba(0.06 + (slit._glow.r - 0.06) * slit.warn,
                           0.05 + (slit._glow.g - 0.05) * slit.warn,
                           0.05 + (slit._glow.b - 0.05) * slit.warn, 1)
        }
    }

    // The wind-up ring: from Balance.parryRing.from times the slit's size
    // onto it, white for the moment the arrow leaves
    Rectangle {
        id: ring
        objectName: "slitRing"
        parent: slit.ringParent ? slit.ringParent : slit
        visible: slit.warn > 0 || slit.flash
        readonly property real size: slit.width
            * (Balance.parryRing.from - (Balance.parryRing.from - 1) * (slit.flash ? 1 : slit.warn))
        width: size
        height: size
        radius: size / 2
        x: (parent === slit ? 0 : slit.x) + (slit.width - size) / 2
        y: (parent === slit ? 0 : slit.y) + (slit.height - size) / 2
        color: "transparent"
        border.width: Math.max(1.5, slit.width * Balance.parryRing.thickness)
        border.color: slit.flash ? Balance.parryRing.flashColor : slit._glow
        opacity: Balance.parryRing.opacity
    }
}
