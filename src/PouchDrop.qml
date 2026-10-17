import QtQuick

// A fallen knight's pouch of gems where it fell (issue #156,
// Balance.deep), until a knight takes it: a small leather bag tied at the
// neck, a facet of its finest gem winking out of it. In a session the
// host spawns it as a replicated object (type "pouch") and gives it to
// the first knight whose node claims it.
Item {
    id: drop

    property real pixelPerUnit: 1
    property real xWu: 0
    property real yWu: 0
    // The gems in it, "shape:value,shape:value" (Game.pouchText)
    property string gems: ""
    // The node of the knight that dropped it, "" alone
    property string owner: ""
    // The replicated object in a session, "" alone
    property string objectId: ""
    // This node asked the host for it and waits for the answer
    property bool claimed: false
    // The colour of its finest gem, for the wink
    property color gemColor: "#F2B33D"

    x: xWu * pixelPerUnit - width / 2
    y: (parent ? parent.height : 0) - yWu * pixelPerUnit - height / 2
    width: 0.6 * pixelPerUnit
    height: width
    scale: 0

    NumberAnimation on scale { to: 1; duration: 260; easing.type: Easing.OutBack }

    // The bag
    Rectangle {
        x: parent.width * 0.1
        y: parent.height * 0.3
        width: parent.width * 0.8
        height: parent.height * 0.66
        radius: width * 0.42
        color: "#7A5230"
        border.color: "#3E2814"
        border.width: Math.max(1, width * 0.08)
    }
    // Its neck, tied
    Rectangle {
        x: parent.width * 0.32
        y: parent.height * 0.14
        width: parent.width * 0.36
        height: parent.height * 0.22
        radius: height * 0.3
        color: "#8E6440"
        border.color: "#3E2814"
        border.width: Math.max(1, width * 0.1)
    }
    Rectangle {
        x: parent.width * 0.28
        y: parent.height * 0.3
        width: parent.width * 0.44
        height: Math.max(1, parent.height * 0.06)
        color: "#C9A227"
    }
    // A facet of its finest gem winking out of it
    Rectangle {
        id: wink
        x: parent.width * 0.56
        y: parent.height * 0.4
        width: parent.width * 0.16
        height: width
        rotation: 45
        color: drop.gemColor
        property real k: 0
        opacity: 0.5 + 0.5 * k
        SequentialAnimation on k {
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 900; easing.type: Easing.InOutSine }
        }
    }
}
