import QtQuick

// A critter of the dungeon (issue #324, Balance.critters): a spider, a
// mouse or a rat on the floor, seen from above. It is drawn only - no
// body, nothing collides with it, it hurts nobody and blocks no way. The
// game moves it (Game._stepCritters): it sets where it is, which way it
// heads and how far its legs have carried it; this draws that. Squashed,
// the game takes it away and leaves a mark on the floor.
Item {
    id: critter
    objectName: "critter"

    // "spider", "mouse" or "rat"
    property string kind: "mouse"
    property real pixelPerUnit: 1
    // Its centre in wu, y up as the world's
    property real xWu: 0
    property real yWu: 0
    property real sizeWu: 0.4
    // The way it heads, radians from east, counter-clockwise as the world's
    property real heading: 0
    // How far it has run in wu: its legs and its tail swing by it
    property real gait: 0
    property color color: "#8C8279"
    // 0..1 from the level's seed
    property real seed: 0

    // What the game keeps of it: "rest", "startled", "flee" or "wander";
    // the seconds left of its startle or its rest, where a scurry goes,
    // the knight it runs from, and whether it is squashed
    property string mood: "rest"
    property real moodLeft: 0
    property real toXWu: 0
    property real toYWu: 0
    property var from: null
    property bool squashed: false

    readonly property real _s: sizeWu * pixelPerUnit
    readonly property real _swing: Math.sin(gait * (kind === "spider" ? 9 : 7))

    x: xWu * pixelPerUnit - _s / 2
    y: (parent ? parent.height : 0) - yWu * pixelPerUnit - _s / 2
    width: _s
    height: _s
    z: -0.5
    rotation: -heading * 180 / Math.PI

    // A mouse or a rat: a tail swaying behind, an oval body, a pointed
    // head with two round ears in front; a rat longer, its tail pink
    Item {
        anchors.fill: parent
        visible: critter.kind !== "spider"
        readonly property bool rat: critter.kind === "rat"
        Rectangle {
            id: tail
            width: critter._s * (parent.rat ? 0.75 : 0.6)
            height: Math.max(1, critter._s * 0.06)
            radius: height / 2
            x: critter._s * 0.22 - width
            y: critter._s / 2 - height / 2
            transformOrigin: Item.Right
            rotation: 18 * critter._swing
            color: parent.rat ? "#B98B84" : Qt.darker(critter.color, 1.2)
        }
        Rectangle {
            width: critter._s * 0.66
            height: critter._s * 0.44
            radius: height / 2
            x: critter._s * 0.14
            y: critter._s / 2 - height / 2
            color: critter.color
        }
        Rectangle {
            width: critter._s * 0.3
            height: critter._s * 0.26
            radius: height / 2
            x: critter._s * 0.66
            y: critter._s / 2 - height / 2
            color: Qt.lighter(critter.color, 1.08)
        }
        Repeater {
            model: [-1, 1]
            Rectangle {
                required property int modelData
                width: critter._s * 0.13
                height: width
                radius: width / 2
                x: critter._s * 0.64
                y: critter._s / 2 + modelData * critter._s * 0.13 - height / 2
                color: Qt.darker(critter.color, 1.35)
            }
        }
    }

    // A spider: eight legs, four a side, stepping in turn, a round
    // abdomen behind and a smaller head in front
    Item {
        anchors.fill: parent
        visible: critter.kind === "spider"
        Repeater {
            model: critter.kind === "spider" ? 8 : 0
            Rectangle {
                required property int index
                readonly property int side: index < 4 ? -1 : 1
                readonly property int pair: index % 4
                width: critter._s * 0.48
                height: Math.max(1, critter._s * 0.05)
                radius: height / 2
                x: critter._s * 0.55
                y: critter._s / 2 - height / 2
                transformOrigin: Item.Left
                rotation: side * (40 + pair * 33) + 14 * critter._swing * (pair % 2 ? 1 : -1) * side
                color: Qt.darker(critter.color, 1.15)
            }
        }
        Rectangle {
            width: critter._s * 0.46
            height: critter._s * 0.4
            radius: height / 2
            x: critter._s * 0.12
            y: critter._s / 2 - height / 2
            color: critter.color
        }
        Rectangle {
            width: critter._s * 0.24
            height: width
            radius: width / 2
            x: critter._s * 0.52
            y: critter._s / 2 - height / 2
            color: Qt.lighter(critter.color, 1.25)
        }
    }
}
