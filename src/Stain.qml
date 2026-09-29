import QtQuick

// What stays on the floor where something died: a flat blot in the fallen
// one's colour with a few drops around it. Settles in, then stays for the
// rest of the level - the "shape that didn't make it" the dungeon remembers.
Item {
    id: stain

    property real pixelPerUnit: 1
    property real xWu: 0
    property real yWu: 0
    property real sizeWu: 0.9
    property color color: "#5A1E1E"
    property real seed: Math.random()

    z: -1
    x: xWu * pixelPerUnit - width / 2
    y: (parent ? parent.height : 0) - yWu * pixelPerUnit - height / 2
    width: sizeWu * pixelPerUnit
    height: width
    opacity: 0
    scale: 0.4

    ParallelAnimation {
        running: true
        NumberAnimation { target: stain; property: "opacity"; to: 0.75; duration: 260 }
        NumberAnimation { target: stain; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack }
    }

    // The blot: two overlapping discs so it is never a perfect circle
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * (0.7 + 0.2 * stain.seed)
        height: parent.height * (0.55 + 0.2 * (1 - stain.seed))
        radius: height / 2
        rotation: stain.seed * 180
        color: stain.color
    }
    Rectangle {
        x: parent.width * (0.35 + 0.2 * stain.seed)
        y: parent.height * (0.3 + 0.15 * stain.seed)
        width: parent.width * 0.4
        height: width
        radius: width / 2
        color: stain.color
    }
    Repeater {
        model: 4
        Rectangle {
            required property int index
            readonly property real a: (index / 4 + stain.seed) * Math.PI * 2
            readonly property real d: stain.width * (0.45 + 0.12 * ((index * 7 + stain.seed * 10) % 3))
            width: stain.width * (0.08 + 0.04 * (index % 2))
            height: width
            radius: width / 2
            x: stain.width / 2 + Math.cos(a) * d - width / 2
            y: stain.height / 2 + Math.sin(a) * d - height / 2
            color: stain.color
        }
    }
}
