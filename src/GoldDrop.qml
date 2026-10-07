import QtQuick

// Gold on the floor where an enemy died, until a knight picks it up. In a
// session the host spawns it as a replicated object (type "gold") and gives
// it to the first knight whose node claims it.
Item {
    id: drop

    property real pixelPerUnit: 1
    property real xWu: 0
    property real yWu: 0
    property int amount: 0
    // The replicated object in a session, "" alone
    property string objectId: ""
    // This node asked the host for it and waits for the answer
    property bool claimed: false

    x: xWu * pixelPerUnit - width / 2
    y: (parent ? parent.height : 0) - yWu * pixelPerUnit - height / 2
    width: 0.4 * pixelPerUnit
    height: width
    scale: 0

    // Pops out of the death, then bobs while it waits
    NumberAnimation on scale { to: 1; duration: 260; easing.type: Easing.OutBack }
    property real _bob: 0
    SequentialAnimation on _bob {
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 700; easing.type: Easing.InOutSine }
    }

    Rectangle {
        width: parent.width
        height: width
        y: -drop._bob * drop.height * 0.15
        radius: width / 2
        color: "#E8B83A"
        border.color: "#8A6A14"
        border.width: Math.max(1, width * 0.12)
    }
}
