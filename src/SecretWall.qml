import QtQuick

// The clue of a secret door (Balance.dungeon.secrets): over its wall cell,
// a hairline crack from the top of the stone to its foot and a faint dust
// breathing out of it onto the floor in front, where a dash into the
// crack bursts it open. Visual only - the cell is a wall like any other
// until the game opens it (Game._showSecret), and then this shows nothing
Item {
    id: clue

    property real pixelPerUnit: 1
    // The wall cell's centre in wu, and the cell's size
    property real cxWu: 0
    property real cyWu: 0
    property real sizeWu: 2
    // A unit step from the wall cell to the floor cell in front of it
    property int nx: 0
    property int ny: -1
    // 0..1 from its cell, for the crack's course
    property real seed: 0
    property bool open: false

    x: (cxWu - sizeWu / 2) * pixelPerUnit
    y: (parent ? parent.height : 0) - (cyWu + sizeWu / 2) * pixelPerUnit
    width: sizeWu * pixelPerUnit
    height: width
    visible: !open
    z: 0

    // The crack: a jagged hairline from the top of the cell to its foot,
    // with a short branch, a lit edge beside the dark one so it reads on
    // the dark stone
    Canvas {
        id: crack
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onPaint: {
            let ctx = getContext("2d")
            ctx.reset()
            let w = width, h = height
            let r = k => Math.abs((Math.sin((k + 1) * 12.9898 + clue.seed * 78.233) * 43758.5453) % 1)
            let pts = []
            for (let i = 0; i <= 6; i++)
                pts.push([w * (0.42 + 0.16 * r(i) + (i % 2 ? 0.06 : -0.06)), h * i / 6])
            let line = (dx, colour, lw) => {
                ctx.strokeStyle = colour
                ctx.lineWidth = lw
                ctx.beginPath()
                ctx.moveTo(pts[0][0] + dx, pts[0][1])
                for (let p of pts) ctx.lineTo(p[0] + dx, p[1])
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(pts[3][0] + dx, pts[3][1])
                ctx.lineTo(pts[3][0] + dx + w * 0.16, pts[3][1] + h * 0.1)
                ctx.lineTo(pts[3][0] + dx + w * 0.24, pts[3][1] + h * 0.08)
                ctx.stroke()
            }
            line(1, "rgba(150, 160, 175, 0.35)", 1)
            line(0, "rgba(8, 6, 5, 0.8)", Math.max(1, w * 0.014))
        }
    }

    // Dust breathing out of the crack's foot onto the floor in front
    Repeater {
        model: 5
        Rectangle {
            id: speck
            required property int index
            readonly property real side: (index % 2 ? 1 : -1) * (0.1 + 0.08 * index)
            property real t: 0
            width: Math.max(1.5, clue.width * 0.06)
            height: width
            radius: width / 2
            color: "#D8CDB6"
            // From the cell's edge towards the floor (screen y runs down)
            x: clue.width / 2 * (1 + clue.nx) - width / 2
               + (clue.nx * 0.45 * t + (clue.nx === 0 ? side * t : 0)) * clue.width
            y: clue.height / 2 * (1 - clue.ny) - height / 2
               + (-clue.ny * 0.45 * t + (clue.ny === 0 ? side * t : 0)) * clue.height
            opacity: 0.5 * (1 - t) * Math.min(1, t * 6)
            SequentialAnimation on t {
                running: clue.visible
                loops: Animation.Infinite
                PauseAnimation { duration: speck.index * 380 }
                NumberAnimation { from: 0; to: 1; duration: 2200; easing.type: Easing.OutQuad }
                PauseAnimation { duration: (4 - speck.index) * 380 + 600 }
            }
        }
    }
}
