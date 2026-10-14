import QtQuick

// A vein of gems in a wall (issue #155, Balance.deep): a cluster of small
// faceted gems of its shape half sunk into the face of a wall cell, dim in
// the stone. Where the lantern's light reaches it one facet winks a glint
// above the darkness. While a knight digs it, a ring closes on it in the
// parry ring's language, white while a strike would be clean; each clean
// strike runs a crack through the stone, and once split the cluster is
// gone and a dark hollow stays. A deep gem (selfLit) glows on its own in
// the dark, and while a knight is near a faint shimmer of its colour
// breathes round it. Visual only - the cell stays a wall, and the game
// counts the strikes (Game.strikeVein) or splits it for a knight of
// another screen (cut)
Item {
    id: vein

    property real pixelPerUnit: 1
    // The wall cell's centre in wu, and the cell's size; its face is the
    // lower faceWu of it, towards the floor south of it
    property real cxWu: 0
    property real cyWu: 0
    property real sizeWu: 2
    property real faceWu: 0.7
    // The cell, "gx,gy"
    property string cell: ""
    // The gem it holds (Balance.deep.shapes) and its strikes in all
    property string shape: "tetrahedron"
    property color gemColor: "#F2B33D"
    property int strikes: 4
    // Glows on its own (Balance.deep.shapes)
    property bool selfLit: false
    // 0..1 from its cell, for the cluster's and the cracks' course
    property real seed: 0
    // Where the darkness is drawn over: the ring and the glint go there
    property Item glowParent: null

    // The strikes so far, set by the game
    property int clean: 0
    property int chips: 0
    readonly property int struck: clean + chips
    // Split by a knight of another screen
    property bool cut: false
    readonly property bool split: cut || struck >= strikes
    // The lantern's light on it, 0..1, and whether the knight is near
    // enough for its shimmer
    property real lit: 0
    property bool knightNear: false
    // The ring while a knight digs it: its progress 0..1 to the close,
    // and open while a strike would be clean
    property bool ringShows: false
    property real ringProgress: 0
    property bool ringOpen: false

    // Where a strike lands, the middle of its face, in wu
    readonly property real faceXWu: cxWu
    readonly property real faceYWu: cyWu - sizeWu / 2 + faceWu / 2

    x: (cxWu - sizeWu / 2) * pixelPerUnit
    y: (parent ? parent.height : 0) - (cyWu + sizeWu / 2) * pixelPerUnit
    width: sizeWu * pixelPerUnit
    height: width

    function _r(k) { return Math.abs((Math.sin((k + 1) * 12.9898 + vein.seed * 78.233) * 43758.5453) % 1) }

    // The socket: darker stone round the cluster, and once split the
    // hollow it leaves
    Rectangle {
        x: parent.width * 0.16
        y: parent.height * (1 - vein.faceWu / vein.sizeWu) - parent.height * 0.08
        width: parent.width * 0.68
        height: parent.height * (vein.faceWu / vein.sizeWu) * 0.92
        radius: height * 0.45
        color: vein.split ? "#0C0A0A" : "#22262E"
        opacity: vein.split ? 0.9 : 0.7
    }

    // The cluster: four gems of its shape, tilted, the stone's edge over
    // their feet
    Repeater {
        model: vein.split ? [] : [
            { x: 0.5, y: 0.72, s: 0.34, r: -8 },
            { x: 0.31, y: 0.78, s: 0.22, r: -32 },
            { x: 0.69, y: 0.79, s: 0.24, r: 26 },
            { x: 0.43, y: 0.86, s: 0.15, r: 12 }
        ]
        Gem {
            required property var modelData
            required property int index
            shape: vein.shape
            color: vein.gemColor
            light: 0.55 + 0.45 * vein.lit
            width: vein.width * modelData.s
            height: width
            x: vein.width * modelData.x - width / 2
            y: vein.height * modelData.y - height / 2
            rotation: modelData.r + 30 * vein._r(index)
        }
    }

    // The cracks of the clean strikes: one jagged line through the face
    // for each, from the cluster out, dark with a lit edge
    Canvas {
        id: cracks
        anchors.fill: parent
        readonly property int count: vein.clean
        onCountChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            let ctx = getContext("2d")
            ctx.reset()
            let w = width, h = height
            let top = h * (1 - vein.faceWu / vein.sizeWu)
            for (let c = 0; c < count; c++) {
                let side = c % 2 ? 1 : -1
                let pts = [[w * (0.5 + side * 0.08), h * 0.8]]
                for (let i = 1; i <= 4; i++)
                    pts.push([w * (0.5 + side * (0.08 + 0.09 * i + 0.04 * vein._r(c * 5 + i))),
                              top + (h - top) * (0.55 - 0.5 * vein._r(c * 7 + i) + 0.1 * i)])
                let line = (dx, colour, lw) => {
                    ctx.strokeStyle = colour
                    ctx.lineWidth = lw
                    ctx.beginPath()
                    ctx.moveTo(pts[0][0] + dx, pts[0][1])
                    for (let p of pts) ctx.lineTo(p[0] + dx, p[1])
                    ctx.stroke()
                }
                line(1, "rgba(170, 180, 195, 0.4)", 1)
                line(0, "rgba(6, 5, 4, 0.9)", Math.max(1, w * 0.016))
            }
        }
    }

    // The glow of a selfLit gem, and the shimmer while a knight is near:
    // soft discs of its colour round the cluster, above the darkness
    Rectangle {
        id: glow
        parent: vein.glowParent || vein
        readonly property real sizePx: vein.width * 0.9
        width: sizePx
        height: sizePx
        radius: sizePx / 2
        x: (parent === vein ? 0 : vein.x) + vein.width / 2 - width / 2
        y: (parent === vein ? 0 : vein.y) + vein.height * 0.76 - height / 2
        visible: vein.selfLit && !vein.split
        color: vein.gemColor
        opacity: 0.07
    }
    Rectangle {
        id: glowCore
        parent: vein.glowParent || vein
        readonly property real sizePx: vein.width * 0.5
        width: sizePx
        height: sizePx
        radius: sizePx / 2
        x: (parent === vein ? 0 : vein.x) + vein.width / 2 - width / 2
        y: (parent === vein ? 0 : vein.y) + vein.height * 0.76 - height / 2
        visible: vein.selfLit && !vein.split
        color: vein.gemColor
        opacity: 0.12
    }
    Rectangle {
        id: shimmer
        parent: vein.glowParent || vein
        readonly property real sizePx: vein.width * 0.8
        width: sizePx
        height: sizePx
        radius: sizePx / 2
        x: (parent === vein ? 0 : vein.x) + vein.width / 2 - width / 2
        y: (parent === vein ? 0 : vein.y) + vein.height * 0.76 - height / 2
        visible: vein.knightNear && !vein.split
        color: Qt.lighter(vein.gemColor, 1.4)
        property real breath: 0
        opacity: 0.06 + 0.12 * breath
        SequentialAnimation on breath {
            running: shimmer.visible
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0; duration: 900; easing.type: Easing.InOutSine }
        }
    }

    // The glint: one facet catching the lantern's light, a four-pointed
    // star that winks and fades, above the darkness
    Item {
        id: glint
        parent: vein.glowParent || vein
        readonly property real sizePx: vein.width * 0.34
        width: sizePx
        height: sizePx
        x: (parent === vein ? 0 : vein.x) + vein.width * (0.44 + 0.12 * vein._r(9)) - width / 2
        y: (parent === vein ? 0 : vein.y) + vein.height * 0.64 - height / 2
        visible: !vein.split && vein.lit > 0
        property real wink: 0
        opacity: vein.lit * wink
        Repeater {
            model: [0, 90]
            Rectangle {
                required property real modelData
                anchors.centerIn: parent
                width: glint.width
                height: Math.max(1.5, glint.width * 0.09)
                radius: height / 2
                rotation: modelData + 45 * (1 - glint.wink)
                color: Qt.lighter(vein.gemColor, 1.7)
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: glint.width * 0.26
            height: width
            radius: width / 2
            color: "#FFFFFF"
        }
        SequentialAnimation on wink {
            running: glint.visible
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 180; easing.type: Easing.OutQuad }
            NumberAnimation { from: 1; to: 0; duration: 520; easing.type: Easing.InQuad }
            PauseAnimation { duration: 1300 + 900 * vein._r(3) }
        }
    }

    // The ring: closing on the vein's face from ringFrom times ringSize
    // to ringSize, in the gem's colour, white while a strike is clean
    Rectangle {
        id: ring
        objectName: "veinRing"
        parent: vein.glowParent || vein
        visible: vein.ringShows && !vein.split
        readonly property real base: Balance.deep.ringSize * vein.pixelPerUnit
        readonly property real size: base * (Balance.deep.ringFrom - (Balance.deep.ringFrom - 1) * vein.ringProgress)
        width: size
        height: size
        radius: size / 2
        x: (parent === vein ? 0 : vein.x) + vein.width / 2 - size / 2
        y: (parent === vein ? 0 : vein.y) + vein.height * (1 - vein.faceWu / vein.sizeWu / 2) - size / 2
        color: "transparent"
        border.width: Math.max(1.5, base * Balance.parryRing.thickness)
        border.color: vein.ringOpen ? Balance.parryRing.flashColor : vein.gemColor
        opacity: Balance.parryRing.opacity
    }
}
