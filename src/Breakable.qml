import QtQuick
import Box2D
import Clayground.Physics

// A thing on a dungeon's floor that a blow breaks (Balance.dungeon.loot):
// a clay "urn", a wooden "crate" (a barrel on some cells) or a "crystal"
// cluster. It blocks the knights and the enemies like a small wall, not
// the shots, and casts no shadow. Its colours follow the dungeon's look
// (band, as Balance.danger.looks). Game.breakThing takes it off the floor.
RectBoxBody {
    id: thing

    // The feature it stands for: its kind and its cell ("gx,gy")
    property string kind: "urn"
    property string cell: ""
    // Its centre in wu, the cell's
    property real cxWu: 0
    property real cyWu: 0
    property real sizeWu: 1.2
    // 0..1 from the feature's cell, for a crate's barrel and a tilt
    property real seed: 0
    property int band: 0
    // The crystal's glow, made beside it above the darkness
    property var glow: null

    readonly property bool barrel: kind === "crate" && seed < 0.4

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

    // Urn: a round belly, a narrower neck and a rim, lit from the top
    Item {
        visible: thing.kind === "urn"
        anchors.fill: parent
        rotation: (thing.seed - 0.5) * 30
        Rectangle {
            x: parent.width * 0.12; y: parent.height * 0.22
            width: parent.width * 0.76; height: width
            radius: width / 2
            color: thing._clay
            border.color: Qt.darker(thing._clay, 1.8)
            border.width: Math.max(1, width * 0.06)
            Rectangle {
                x: parent.width * 0.2; y: parent.height * 0.15
                width: parent.width * 0.3; height: width * 0.6
                radius: height / 2
                color: Qt.lighter(thing._clay, 1.4)
                opacity: 0.6
            }
        }
        Rectangle {
            x: parent.width * 0.3; y: parent.height * 0.06
            width: parent.width * 0.4; height: parent.height * 0.24
            radius: width * 0.2
            color: Qt.darker(thing._clay, 1.15)
            border.color: Qt.darker(thing._clay, 1.8)
            border.width: 1
        }
    }

    // Crate: a square of planks with a cross brace; barrel: a round top
    // with two hoops
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
    Rectangle {
        visible: thing.barrel
        anchors.fill: parent
        anchors.margins: parent.width * 0.04
        radius: width / 2
        color: thing._wood
        border.color: Qt.darker(thing._wood, 1.9)
        border.width: Math.max(1, width * 0.07)
        Repeater {
            model: [0.62, 0.86]
            Rectangle {
                required property real modelData
                anchors.centerIn: parent
                width: parent.width * modelData; height: width
                radius: width / 2
                color: "transparent"
                border.color: "#3A3530"
                border.width: Math.max(1, parent.width * 0.05)
            }
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
