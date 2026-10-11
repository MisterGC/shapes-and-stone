import QtQuick
import Box2D
import Clayground.Physics

// A door's leaf in a doorway (Balance.dungeon): planks with two iron
// bands, between the jambs Game.placeDoors sets as walls. Closed it blocks
// like a wall; open it swings against a jamb, into the room, and blocks
// nothing; bashed it lies in splinters and stays open. Its wood follows
// the dungeon's look (band, as Balance.danger.looks). The game sets
// doorState; prompt shows the E above it for this node's knight in reach
RectBoxBody {
    id: door

    // Its doorway's cell ("gx,gy") and the cell's centre in wu
    property string cell: ""
    property real cxWu: 0
    property real cyWu: 0
    // The corridor runs along x through it: the leaf stands along y
    property bool across: true
    // The side of the room, along the corridor: +1 or -1
    property int roomSide: 1
    property real leafWu: 1.2
    property real thickWu: 0.3
    property int band: 0
    // 0..1 from its cell, for the splinters
    property real seed: 0
    // "closed", "open" or "bashed"
    property string doorState: "closed"
    property bool prompt: false

    readonly property bool shut: doorState === "closed"
    readonly property var _wood: ["#6E4A28", "#5A4A3A", "#45291A"][band]

    bodyType: Body.Static
    friction: 0.0
    restitution: 0.0
    active: shut
    xWu: cxWu - (across ? thickWu : leafWu) / 2
    yWu: cyWu + (across ? leafWu : thickWu) / 2
    widthWu: across ? thickWu : leafWu
    heightWu: across ? leafWu : thickWu
    color: "transparent"
    // Over the jambs, made before it, so the E shows
    z: 0

    // The leaf, hinged at its top (along y) or left (along x) end; open it
    // turns a quarter into the room. On screen y runs down, so a quarter
    // clockwise turns a leaf along y to -x, one along x to -y
    Item {
        id: leaf
        visible: door.doorState !== "bashed"
        anchors.fill: parent
        transformOrigin: door.across ? Item.Top : Item.Left
        rotation: door.shut ? 0 : -90 * door.roomSide
        Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
        Rectangle {
            anchors.fill: parent
            color: door._wood
            border.color: Qt.darker(door._wood, 2)
            border.width: Math.max(1, Math.min(width, height) * 0.12)
        }
        // The planks' seams along the leaf
        Repeater {
            model: [0.33, 0.66]
            Rectangle {
                required property real modelData
                x: door.across ? leaf.width * modelData : 0
                y: door.across ? 0 : leaf.height * modelData
                width: door.across ? 1 : leaf.width
                height: door.across ? leaf.height : 1
                color: Qt.darker(door._wood, 1.6)
            }
        }
        // Two iron bands across it
        Repeater {
            model: [0.2, 0.8]
            Rectangle {
                required property real modelData
                readonly property real band: Math.max(2, (door.across ? leaf.height : leaf.width) * 0.08)
                x: door.across ? -1 : leaf.width * modelData - band / 2
                y: door.across ? leaf.height * modelData - band / 2 : -1
                width: door.across ? leaf.width + 2 : band
                height: door.across ? band : leaf.height + 2
                color: "#3A3836"
            }
        }
    }

    // Bashed: splinters over the doorway and a stub at the hinge
    Repeater {
        model: door.doorState === "bashed" ? 6 : 0
        Rectangle {
            required property int index
            readonly property real r1: (Math.sin((index + 1) * 12.9898 + door.seed * 78.233) * 43758.5453) % 1
            readonly property real r2: (Math.sin((index + 1) * 39.3468 + door.seed * 11.135) * 24634.6345) % 1
            readonly property real len: Math.max(door.width, door.height)
            x: door.width / 2 + r1 * len * 0.6 - width / 2
            y: door.height / 2 + r2 * len * 0.6 - height / 2
            width: len * (0.22 + 0.12 * Math.abs(r2))
            height: Math.max(2, len * 0.07)
            rotation: r1 * 180
            color: index % 2 ? door._wood : Qt.lighter(door._wood, 1.35)
        }
    }
    Rectangle {
        visible: door.doorState === "bashed"
        x: 0
        y: 0
        width: door.across ? door.width : door.width * 0.18
        height: door.across ? door.height * 0.18 : door.height
        color: Qt.darker(door._wood, 1.3)
    }

    // E for this node's knight in reach
    Text {
        visible: door.prompt
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 4
        text: "E"
        color: "#F0E6C8"
        font.pixelSize: 14
        font.bold: true
        style: Text.Outline
        styleColor: "#000000"
    }
}
