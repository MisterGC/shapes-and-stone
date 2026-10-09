import QtQuick

// How deep the knight is: a shaft of rock layers, one per depth, darker
// and hotter the deeper, and the knight's marker in its layer. At the camp
// it shows large and the marker sinks into the next layer, the next
// dungeon's. It shows the depth only, never where the danger stands in
// the depth's range (Balance.gauge)
Item {
    id: gauge

    property int depth: 0
    // At the camp between two dungeons
    property bool camp: false

    // The depth the marker is at; at the camp it goes from depth to depth + 1
    property real shown: depth
    readonly property int layers: Balance.gauge.layers
    readonly property real layerHeight: camp ? Balance.gauge.large.layer : Balance.gauge.small.layer
    readonly property real shaftWidth: camp ? Balance.gauge.large.width : Balance.gauge.small.width
    // The depth at the shaft's top: the marker in the middle layer, the
    // surface at the top while the knight is shallow
    readonly property real topDepth: Math.max(0, shown - Math.floor(layers / 2))

    readonly property color topColor: Balance.gauge.top
    readonly property color deepColor: Balance.gauge.deep
    readonly property color seamColor: Balance.gauge.seam

    // 0 at the surface, 1 from Balance.gauge.hotDepth on
    function heat(d) { return Math.min(1, Math.max(0, d) / Balance.gauge.hotDepth) }
    // The rock of layer d: darker the deeper and drawn toward the seams'
    // glow, every other layer a shade darker so the layers tell apart
    function layerColor(d) {
        let t = heat(d), g = Balance.gauge.glow * t, s = d % 2 === 1 ? Balance.gauge.alternate : 1
        return Qt.rgba(s * ((1 - g) * (topColor.r + (deepColor.r - topColor.r) * t) + g * seamColor.r),
                       s * ((1 - g) * (topColor.g + (deepColor.g - topColor.g) * t) + g * seamColor.g),
                       s * ((1 - g) * (topColor.b + (deepColor.b - topColor.b) * t) + g * seamColor.b), 1)
    }
    // The marker's centre, from the shaft's top
    readonly property real markerY: (shown - topDepth + 0.5) * layerHeight

    implicitWidth: shaft.width + label.width + 6
    implicitHeight: shaft.height
    width: implicitWidth
    height: implicitHeight

    function _settle() {
        sink.stop()
        shown = depth
        if (camp) sink.start()
    }
    onDepthChanged: _settle()
    onCampChanged: _settle()
    Component.onCompleted: _settle()

    SequentialAnimation {
        id: sink
        PauseAnimation { duration: Balance.gauge.sinkDelay * 1000 }
        NumberAnimation {
            target: gauge
            property: "shown"
            to: gauge.depth + 1
            duration: Balance.gauge.sink * 1000
            easing.type: Easing.InOutQuad
        }
    }
    // Sunk into the next layer: the camp's gauge has shown the way down
    readonly property bool sunk: camp && !sink.running && shown === depth + 1

    Rectangle {
        id: shaft
        anchors.right: parent.right
        width: gauge.shaftWidth
        height: gauge.layers * gauge.layerHeight
        color: "#000000"
        border.color: "#000000"
        border.width: 2
        radius: 3
        clip: true

        Repeater {
            model: gauge.layers + 1
            Rectangle {
                readonly property int d: Math.floor(gauge.topDepth) + index
                x: 2
                width: shaft.width - 4
                y: (d - gauge.topDepth) * gauge.layerHeight
                height: gauge.layerHeight
                color: gauge.layerColor(d)

                // The seam under the layer glows the hotter, the deeper
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: gauge.camp ? 3 : 1
                    color: gauge.seamColor
                    opacity: gauge.heat(parent.d)
                }
                // Each layer's depth, on the large gauge
                Text {
                    visible: gauge.camp
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.d
                    color: "#DDDDDD"
                    opacity: 0.6
                    font.pixelSize: 11
                    font.bold: true
                }
            }
        }

        // The surface over depth 0
        Rectangle {
            visible: gauge.topDepth < 0.5
            y: -gauge.topDepth * gauge.layerHeight
            width: parent.width
            height: gauge.camp ? 4 : 2
            color: "#6A9A4A"
        }

        // The knight
        Rectangle {
            id: marker
            objectName: "gaugeMarker"
            readonly property real size: gauge.camp ? 18 : 9
            width: size
            height: size
            rotation: 45
            x: (shaft.width - size) / 2
            y: gauge.markerY - size / 2
            color: Balance.gauge.marker
            border.color: "#000000"
            border.width: 1
        }

        Behavior on width { NumberAnimation { duration: 250 } }
        Behavior on height { NumberAnimation { duration: 250 } }
    }

    // The depth in words, beside the marker
    Text {
        id: label
        objectName: "gaugeLabel"
        anchors.right: shaft.left
        anchors.rightMargin: 6
        y: Math.max(0, Math.min(shaft.height - height, gauge.markerY - height / 2))
        text: "Depth " + gauge.depth
        color: "#DDDDDD"
        style: Text.Outline
        styleColor: "#000000"
        font.pixelSize: gauge.camp ? 18 : 14
        font.bold: true
        font.letterSpacing: 1
    }
}
