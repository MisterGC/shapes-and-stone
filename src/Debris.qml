import QtQuick

// What lies on the floor of a dangerous dungeon (Balance.danger.looks):
// "bones", a skull and a few long bones, pale where light falls on them;
// or "embers", a heap of coals glowing on their own. Visual only, laid out
// from the level's seed.
Item {
    id: debris

    property real pixelPerUnit: 1
    property real xWu: 0
    property real yWu: 0
    property real sizeWu: 0.8
    property string kind: "bones"
    property real seed: 0

    z: -1
    x: xWu * pixelPerUnit - width / 2
    y: (parent ? parent.height : 0) - yWu * pixelPerUnit - height / 2
    width: sizeWu * pixelPerUnit
    height: width
    rotation: seed * 360

    // Bones: two crossed and one apart, each a shaft with knobbed ends
    Repeater {
        model: debris.kind === "bones" ? [
            { x: 0.15, y: 0.42, w: 0.7, r: 25 },
            { x: 0.2, y: 0.5, w: 0.6, r: -40 },
            { x: 0.5, y: 0.78, w: 0.4, r: 80 * debris.seed }
        ] : []
        Item {
            required property var modelData
            x: debris.width * modelData.x
            y: debris.height * modelData.y
            width: debris.width * modelData.w
            height: debris.height * 0.08
            rotation: modelData.r
            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                radius: height / 2
                color: "#2A2520"
            }
            Rectangle { anchors.fill: parent; radius: height / 2; color: "#CFC6B2" }
            Repeater {
                model: [0, 1]
                Rectangle {
                    required property int modelData
                    width: parent.height * 1.8
                    height: width
                    radius: width / 2
                    x: modelData === 0 ? -width / 3 : parent.width - width * 2 / 3
                    y: (parent.height - height) / 2
                    color: "#D8D0BC"
                }
            }
        }
    }
    // The skull
    Rectangle {
        visible: debris.kind === "bones"
        x: debris.width * 0.55
        y: debris.height * 0.12
        width: debris.width * 0.3
        height: width * 0.9
        radius: width * 0.45
        color: "#DDD5C2"
        border.color: "#2A2520"
        border.width: 1
        Repeater {
            model: [0.22, 0.58]
            Rectangle {
                required property real modelData
                x: parent.width * modelData
                y: parent.height * 0.35
                width: parent.width * 0.22
                height: width
                radius: width / 2
                color: "#1A1612"
            }
        }
    }

    // Embers: a dark heap of coals, each glowing and fading on its own
    Rectangle {
        visible: debris.kind === "embers"
        anchors.centerIn: parent
        width: parent.width * 0.8
        height: parent.height * 0.6
        radius: height / 2
        color: "#1C0C08"
        opacity: 0.85
    }
    Repeater {
        model: debris.kind === "embers" ? 7 : 0
        Rectangle {
            required property int index
            readonly property real a: (index / 7 + debris.seed) * Math.PI * 2
            readonly property real d: debris.width * (0.08 + 0.22 * ((index * 5 + debris.seed * 10) % 3) / 2)
            width: debris.width * (0.1 + 0.05 * (index % 3))
            height: width
            radius: width / 2
            x: debris.width / 2 + Math.cos(a) * d - width / 2
            y: debris.height / 2 + Math.sin(a) * d * 0.7 - height / 2
            color: index % 3 === 0 ? "#FFB040" : "#FF4A18"
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { from: 0.35; to: 1; duration: 700 + index * 130; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1; to: 0.35; duration: 900 + index * 110; easing.type: Easing.InOutSine }
            }
        }
    }
}
