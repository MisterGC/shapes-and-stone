import QtQuick

// A spike plate on a dungeon's floor (Balance.dungeon.spike...): a stone
// slab with small holes in it, always the same, the cue a knight learns
// to read. Stepped on it clicks and sinks a little ("clicked"); its
// spikes rise a moment later and stay up, bent, over a stain ("sprung").
// Game._stepPlates runs it; this only draws it.
Item {
    id: plate

    property real pixelPerUnit: 1
    // The feature it stands for: its cell ("gx,gy") and the cell's centre
    property string cell: ""
    property real xWu: 0
    property real yWu: 0
    property real sizeWu: 1.6
    // 0..1 from the feature's cell, for the spikes' bend and the stain
    property real seed: 0
    property int band: 0
    // "armed", "clicked" or "sprung"
    property string phase: "armed"
    // The rise counted down on the physics clock (seconds), or the
    // session time it is due at (ms, -1 when not in a session)
    property real riseIn: 0
    property real riseAt: -1
    // What its spikes did to this node's knight: "", "hit", "dodged",
    // "ignored" or "clear"
    property string result: ""

    z: -1
    x: xWu * pixelPerUnit - width / 2
    y: (parent ? parent.height : 0) - yWu * pixelPerUnit - height / 2
    width: sizeWu * pixelPerUnit
    height: width

    // The slab's stone by the look: sandstone, grey, soot
    readonly property color _stone: ["#6E6250", "#5C5E62", "#3E3433"][band]
    readonly property bool _down: phase !== "armed"

    // The stain the spikes leave, out from under the slab
    Rectangle {
        visible: plate.phase === "sprung"
        anchors.centerIn: parent
        width: parent.width * (1.15 + 0.15 * plate.seed)
        height: parent.height * (0.85 + 0.15 * (1 - plate.seed))
        radius: height / 2
        rotation: plate.seed * 180
        color: "#5A1E1E"
        opacity: 0.55
    }

    // The slab, a little sunk once it clicked
    Rectangle {
        id: slab
        anchors.centerIn: parent
        width: parent.width * (plate._down ? 0.9 : 0.94)
        height: width
        radius: width * 0.06
        color: plate._down ? Qt.darker(plate._stone, 1.2) : plate._stone
        border.color: Qt.darker(plate._stone, 1.7)
        border.width: Math.max(1, width * 0.04)

        // Three by three holes, and the spikes out of them once sprung
        Repeater {
            model: 9
            Item {
                id: hole
                required property int index
                readonly property real hx: (index % 3 + 0.5) / 3
                readonly property real hy: (Math.floor(index / 3) + 0.5) / 3
                // Each spike bent its own way, from the plate's seed
                readonly property real bend: ((plate.seed * 977 + index * 131) % 70) - 35
                x: slab.width * hx
                y: slab.height * hy
                Rectangle {
                    x: -width / 2; y: -height / 2
                    width: slab.width * 0.1
                    height: width
                    radius: width / 2
                    color: Qt.darker(plate._stone, 2.6)
                }
                Rectangle {
                    id: spike
                    visible: plate.phase === "sprung"
                    x: -width / 2
                    y: -height
                    width: Math.max(1, slab.width * 0.06)
                    height: slab.height * 0.24
                    transformOrigin: Item.Bottom
                    rotation: hole.bend
                    scale: plate.phase === "sprung" ? 1 : 0
                    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutBack } }
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#E6E2D6" }
                        GradientStop { position: 1; color: "#7A7468" }
                    }
                }
            }
        }
    }
}
