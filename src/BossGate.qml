import QtQuick
import Box2D
import Clayground.Physics

// An iron gate of the boss room (Balance.boss, issue #274): a frame of
// bars across a way into the room, on the edge of the corridor's cell
// that meets the room, or across the exit stairs' shaft. Shut it blocks
// like a wall - the knights, the enemies, their shots; open its bars have
// sunk into the floor and it blocks nothing. Game's BossFight sets shut
RectBoxBody {
    id: gate

    // The corridor's cell ("gx,gy") and the edge's centre in wu
    property string cell: ""
    property real cxWu: 0
    property real cyWu: 0
    // The edge runs along y: the way runs along x through it
    property bool across: true
    property real lengthWu: 2
    property real thickWu: 0.35
    // The gate of the exit stairs' shaft
    property bool exit: false
    property bool shut: false

    bodyType: Body.Static
    friction: 0.0
    restitution: 0.0
    active: shut
    xWu: cxWu - (across ? thickWu : lengthWu) / 2
    yWu: cyWu + (across ? lengthWu : thickWu) / 2
    widthWu: across ? thickWu : lengthWu
    heightWu: across ? lengthWu : thickWu
    color: "transparent"
    z: 0

    // Rising out of the floor as it shuts, sinking as it opens
    property real raised: shut ? 1 : 0
    Behavior on raised { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }

    readonly property color _iron: Balance.boss.gateColor
    // The slot in the floor it sinks into
    Rectangle {
        anchors.fill: parent
        color: Qt.darker(gate._iron, 2.4)
        opacity: 0.8
    }
    Item {
        anchors.fill: parent
        opacity: gate.raised
        visible: opacity > 0.01
        // The frame
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Qt.lighter(gate._iron, 1.4)
            border.width: Math.max(1, Math.min(width, height) * 0.25)
        }
        // The bars across the way, and a cross bar along it
        Repeater {
            model: 6
            Rectangle {
                required property int index
                readonly property real at: (index + 0.5) / 6
                readonly property real bar: Math.max(2, (gate.across ? gate.height : gate.width) * 0.05)
                x: gate.across ? 0 : gate.width * at - bar / 2
                y: gate.across ? gate.height * at - bar / 2 : 0
                width: gate.across ? gate.width : bar
                height: gate.across ? bar : gate.height
                color: gate._iron
                border.color: Qt.lighter(gate._iron, 1.6)
                border.width: 1
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: gate.across ? Math.max(2, gate.width * 0.3) : gate.width
            height: gate.across ? gate.height : Math.max(2, gate.height * 0.3)
            color: Qt.darker(gate._iron, 1.3)
        }
    }
}
