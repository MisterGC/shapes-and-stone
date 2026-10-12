import QtQuick
import Box2D
import Clayground.Physics

// A thing on a dungeon's floor that a blow breaks (Balance.dungeon.loot):
// a clay "urn", a wooden "crate" (a barrel on some cells) or a "crystal"
// cluster. It blocks the knights and the enemies like a small wall, not
// the shots, and casts no shadow. An urn and a barrel stand upright, seen
// from the side, on a smaller foot (Balance.dungeon.standing). Its colours
// follow the dungeon's look (band, as Balance.danger.looks).
// Game.breakThing takes it off the floor.
RectBoxBody {
    id: thing

    // The feature it stands for: its kind and its cell ("gx,gy")
    property string kind: "urn"
    property string cell: ""
    // 0..1 from the feature's cell, for a crate's barrel
    property real seed: 0
    readonly property bool barrel: kind === "crate" && seed < 0.4
    readonly property var _standing: kind === "urn" ? Balance.dungeon.standing.urn
                                   : barrel ? Balance.dungeon.standing.barrel : null
    // Its centre in wu, the cell's; the square it blocks, sizeWu, and how
    // tall it is drawn, tallWu
    property real cxWu: 0
    property real cyWu: 0
    property real sizeWu: _standing ? _standing.foot : Balance.dungeon.breakableSize
    readonly property real tallWu: _standing ? _standing.tall : sizeWu
    property int band: 0
    // The crystal's glow, made beside it above the darkness
    property var glow: null

    bodyType: Body.Static
    friction: 0.0
    restitution: 0.0
    xWu: cxWu - sizeWu / 2
    yWu: cyWu + sizeWu / 2
    widthWu: sizeWu
    heightWu: sizeWu
    color: "transparent"
    z: -1

    // The urn's clay by the look: red earth, grey stone, soot black
    readonly property var _clay: ["#A55A36", "#7C7A70", "#4A2A22"][band]
    readonly property var _wood: ["#7A5530", "#5E5446", "#4A3020"][band]

    // Urn and barrel stand upright on the floor, seen from the side: what
    // blocks is their foot (sizeWu square), what is drawn rises from its
    // lower edge to tallWu, on a shadow of its own
    Item {
        id: standing
        visible: thing.kind === "urn" || thing.barrel
        x: 0
        y: parent.height - height
        width: parent.width
        height: thing.tallWu * thing.pixelPerUnit
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - height * 0.7
            width: parent.width * 1.05; height: parent.width * 0.32
            radius: height / 2
            color: "#000000"
            opacity: 0.35
        }

        // Urn: a foot, a belly wider than tall, a narrow neck and a
        // flared lip, lit from the left
        Item {
            visible: thing.kind === "urn"
            anchors.fill: parent
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.88
                width: parent.width * 0.46; height: parent.height * 0.1
                radius: height * 0.3
                color: Qt.darker(thing._clay, 1.3)
                border.color: Qt.darker(thing._clay, 1.9)
                border.width: 1
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.13
                width: parent.width * 0.4; height: parent.height * 0.3
                color: Qt.darker(thing._clay, 1.1)
                border.color: Qt.darker(thing._clay, 1.9)
                border.width: 1
            }
            Rectangle {
                id: belly
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.3
                width: parent.width; height: parent.height * 0.62
                radius: Math.min(width, height) / 2
                color: thing._clay
                border.color: Qt.darker(thing._clay, 1.9)
                border.width: Math.max(1, width * 0.05)
                // The shaded right side and a light band on the left
                Rectangle {
                    x: parent.width * 0.55; y: parent.height * 0.12
                    width: parent.width * 0.38; height: parent.height * 0.76
                    radius: width / 2
                    color: Qt.darker(thing._clay, 1.35)
                    opacity: 0.6
                }
                Rectangle {
                    x: parent.width * 0.18; y: parent.height * 0.18
                    width: parent.width * 0.14; height: parent.height * 0.5
                    radius: width / 2
                    color: Qt.lighter(thing._clay, 1.45)
                    opacity: 0.65
                }
                // A painted band round the shoulder
                Rectangle {
                    x: parent.width * 0.08; y: parent.height * 0.3
                    width: parent.width * 0.84; height: Math.max(1, parent.height * 0.06)
                    color: Qt.darker(thing._clay, 1.6)
                    opacity: 0.8
                }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.06
                width: parent.width * 0.62; height: parent.height * 0.1
                radius: height / 2
                color: Qt.lighter(thing._clay, 1.1)
                border.color: Qt.darker(thing._clay, 1.9)
                border.width: 1
                // The dark mouth seen over the lip
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.6; height: parent.height * 0.45
                    radius: height / 2
                    color: Qt.darker(thing._clay, 2.6)
                }
            }
        }

        // Barrel: staves bulging at the middle, two hoops, its round lid
        // seen from just above
        Item {
            visible: thing.barrel
            anchors.fill: parent
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.1
                width: parent.width * 0.86; height: parent.height * 0.86
                radius: width * 0.16
                color: thing._wood
                border.color: Qt.darker(thing._wood, 1.9)
                border.width: Math.max(1, width * 0.05)
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.26
                width: parent.width; height: parent.height * 0.54
                radius: width * 0.22
                color: thing._wood
                border.color: Qt.darker(thing._wood, 1.9)
                border.width: Math.max(1, width * 0.05)
                Rectangle {
                    x: parent.width * 0.6; y: 0
                    width: parent.width * 0.32; height: parent.height
                    color: Qt.darker(thing._wood, 1.3)
                    opacity: 0.55
                }
            }
            // The staves' seams
            Repeater {
                model: [0.3, 0.5, 0.7]
                Rectangle {
                    required property real modelData
                    x: parent.width * modelData; y: parent.height * 0.18
                    width: 1; height: parent.height * 0.74
                    color: Qt.darker(thing._wood, 1.6)
                }
            }
            // The hoops
            Repeater {
                model: [0.28, 0.72]
                Rectangle {
                    required property real modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * modelData
                    width: parent.width * 0.98; height: Math.max(2, parent.height * 0.07)
                    radius: height / 3
                    color: "#3A3530"
                }
            }
            // The lid: an ellipse a shade lighter, its ring of iron
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.02
                width: parent.width * 0.86; height: parent.height * 0.18
                radius: height / 2
                color: Qt.lighter(thing._wood, 1.2)
                border.color: "#3A3530"
                border.width: Math.max(1, height * 0.15)
            }
        }
    }

    // Crate: a square of planks with a cross brace
    Rectangle {
        visible: thing.kind === "crate" && !thing.barrel
        anchors.fill: parent
        anchors.margins: parent.width * 0.06
        color: thing._wood
        border.color: Qt.darker(thing._wood, 1.9)
        border.width: Math.max(1, width * 0.07)
        Repeater {
            model: [0.33, 0.66]
            Rectangle {
                required property real modelData
                x: 0; y: parent.height * modelData
                width: parent.width; height: 1
                color: Qt.darker(thing._wood, 1.5)
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 1.3; height: parent.height * 0.12
            rotation: 45
            color: Qt.lighter(thing._wood, 1.2)
        }
    }
    // Crystal: three long diamonds from one root, pale at their edges
    Repeater {
        model: thing.kind === "crystal" ? [
            { x: 0.5, w: 0.36, h: 0.9, r: 0 },
            { x: 0.32, w: 0.26, h: 0.6, r: -30 },
            { x: 0.68, w: 0.24, h: 0.55, r: 28 }
        ] : []
        Item {
            id: shard
            required property var modelData
            x: thing.width * modelData.x - width / 2
            y: thing.height * 0.9 - height
            width: thing.width * modelData.w
            height: thing.height * modelData.h
            rotation: modelData.r
            transformOrigin: Item.Bottom
            // A square turned on its corner, stretched up to the shard
            Item {
                width: parent.width
                height: width
                y: parent.height - height
                transform: Scale {
                    origin.x: shard.width / 2
                    origin.y: shard.width
                    yScale: shard.height / shard.width
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width / Math.SQRT2
                    height: width
                    rotation: 45
                    color: "#7FE6FF"
                    border.color: "#E8FBFF"
                    border.width: 1
                    opacity: 0.9
                }
            }
        }
    }
}
