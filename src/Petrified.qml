import QtQuick

// A petrified traveller in a vein's rock face (issue #158, Balance.deep
// .stone): a stone-grey figure half in the wall, in a dark niche of the
// face, faintly cracked, its edge shimmering pale blue where a lantern's
// light reaches it. A miner was caught mid-swing, a small pick raised and
// a lamp on its cap; a lost traveller huddled, arms round its knees, a
// pack on its back. While a knight frees it a ring closes on it in the
// parry ring's language, white while a strike would be clean; each clean
// strike runs one more crack through the shell. Freed, colour flows back
// into it from its middle out (colour 0..1), and then the game walks it:
// to work at a vein, swinging its pick (swing), or off toward the exit,
// fading out (fade). Visual only - the cell stays a wall
Item {
    id: stone
    objectName: "petrified"

    property real pixelPerUnit: 1
    // The wall cell's centre in wu, and the cell's size; its face is the
    // lower faceWu of it, towards the floor south of it
    property real cxWu: 0
    property real cyWu: 0
    property real sizeWu: 2
    property real faceWu: 0.7
    // The cell, "gx,gy"
    property string cell: ""
    // "miner" or "lost"
    property string kind: "miner"
    // The veins of its room, "gx,gy", its room's spawn hole ("" none) and
    // the room's index in the dungeon (-1 none)
    property var veinCells: []
    property string holeCell: ""
    property int roomIndex: -1
    property int strikes: 3
    // 0..1 from its cell, for the cracks and the niche
    property real seed: 0
    // Where the darkness is drawn over: the ring and the shimmer go there
    property Item glowParent: null

    // The clean strikes so far and the off-beat ones, set by the game
    property int clean: 0
    property int misses: 0
    // Freed: the shell cracked; outcome, set by the game once known:
    // "" not yet, "working", "leaving" or "fleeing"; gone once it walked
    // out of sight
    property bool freed: false
    property string outcome: ""
    property bool gone: false
    // The colour come back, 0..1, and the figure's fade, 1..0
    property real colour: 0
    property real fade: 1
    // Where its feet stand, in wu: in the niche until it walks, and
    // whether it walks now, which way it faces (-1 left, 1 right) and
    // the pick's swing 0..1 while it works
    property real footXWu: cxWu
    property real footYWu: cyWu - sizeWu / 2 + 0.05
    property bool walking: false
    property int facing: 1
    property real swing: 0
    // The lantern's light on it, 0..1, and whether a knight is near
    property real lit: 0
    property bool knightNear: false
    // The ring while a knight frees it: its progress 0..1 to the close,
    // and open while a strike would be clean
    property bool ringShows: false
    property real ringProgress: 0
    property bool ringOpen: false
    // What it says, in a bubble over its head
    property string saying: ""

    // Where a strike lands, the middle of the figure, in wu
    readonly property real faceXWu: cxWu
    readonly property real faceYWu: cyWu - sizeWu / 2 + faceWu / 2 + 0.1

    readonly property color shimmerColor: Balance.deep.stone.shimmer

    x: (cxWu - sizeWu / 2) * pixelPerUnit
    y: (parent ? parent.height : 0) - (cyWu + sizeWu / 2) * pixelPerUnit
    width: sizeWu * pixelPerUnit
    height: width

    function _r(k) { return Math.abs((Math.sin((k + 1) * 12.9898 + stone.seed * 78.233) * 43758.5453) % 1) }

    // The niche: a dark recess in the face where it stood, rock round it
    Canvas {
        id: niche
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onPaint: {
            let ctx = getContext("2d")
            ctx.reset()
            let w = width, h = height
            let top = h * (1 - stone.faceWu / stone.sizeWu)
            ctx.fillStyle = "#16130F"
            ctx.beginPath()
            ctx.moveTo(w * 0.22, h)
            for (let i = 0; i <= 8; i++) {
                let a = Math.PI * i / 8
                let j = 1 + 0.18 * (stone._r(i + 20) - 0.5)
                ctx.lineTo(w * 0.5 - Math.cos(a) * w * 0.28 * j, h - Math.sin(a) * (h - top) * 1.08 * j)
            }
            ctx.lineTo(w * 0.78, h)
            ctx.closePath()
            ctx.fill()
        }
    }

    // The figure: its feet at footXWu, footYWu
    Item {
        id: figure
        // The figure's box, its feet at the bottom middle, and room round
        // it for the raised pick
        readonly property real wWu: 1.0
        readonly property real hWu: 1.3
        readonly property real padWu: 0.25
        readonly property real topWu: 0.45
        width: wWu * stone.pixelPerUnit
        height: hWu * stone.pixelPerUnit
        x: (stone.footXWu - (stone.cxWu - stone.sizeWu / 2)) * stone.pixelPerUnit - width / 2
        y: (stone.cyWu + stone.sizeWu / 2 - stone.footYWu) * stone.pixelPerUnit - height
        opacity: stone.fade
        visible: !stone.gone

        // A bob while it walks
        property real bob: 0
        transform: Translate { y: -figure.bob * figure.height * 0.04 }
        SequentialAnimation on bob {
            running: stone.walking
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 160; easing.type: Easing.OutQuad }
            NumberAnimation { from: 1; to: 0; duration: 160; easing.type: Easing.InQuad }
        }

        Canvas {
            id: body
            x: -figure.padWu * stone.pixelPerUnit
            y: -figure.topWu * stone.pixelPerUnit
            width: parent.width + 2 * figure.padWu * stone.pixelPerUnit
            height: parent.height + figure.topWu * stone.pixelPerUnit
            readonly property real colour: stone.colour
            readonly property int cracks: stone.clean
            readonly property real lit: stone.lit
            readonly property real swing: stone.swing
            readonly property int facing: stone.facing
            readonly property bool upright: stone.outcome !== ""
            onColourChanged: requestPaint()
            onCracksChanged: requestPaint()
            onLitChanged: requestPaint()
            onSwingChanged: requestPaint()
            onFacingChanged: requestPaint()
            onUprightChanged: requestPaint()
            onWidthChanged: requestPaint()

            readonly property var grey: ({ skin: "#94928D", cloth: "#77756F", dark: "#5C5A56", cap: "#6C6A65",
                                           tool: "#4A4844", handle: "#56544F", lamp: "#C4C2BC", pack: "#66645F" })
            readonly property var miner: ({ skin: "#E2B48C", cloth: "#9A6A34", dark: "#4A3424", cap: "#D8A630",
                                            tool: "#A9B0B8", handle: "#7A5230", lamp: "#FFE08A", pack: "#7A5A38" })
            readonly property var lost: ({ skin: "#E2B48C", cloth: "#5C7398", dark: "#3A4256", cap: "#5C7398",
                                           tool: "#A9B0B8", handle: "#7A5230", lamp: "#FFE08A", pack: "#8A6A44" })

            // The figure's shapes in pal; edge strokes the outline first
            function drawFigure(ctx, pal, edge) {
                let w = figure.width, h = figure.height
                let disc = (x, y, r) => { ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill() }
                let oval = (x, y, rx, ry) => {
                    ctx.beginPath()
                    ctx.ellipse(x - rx, y - ry, rx * 2, ry * 2)
                    ctx.fill()
                }
                if (edge) {
                    ctx.fillStyle = edge
                    if (stone.kind === "miner" || upright) {
                        oval(w * 0.5, h * 0.62, w * 0.3, h * 0.27)
                        disc(w * 0.5, h * 0.27, w * 0.21)
                    } else {
                        oval(w * 0.5, h * 0.72, w * 0.38, h * 0.24)
                        disc(w * 0.5, h * 0.47, w * 0.21)
                    }
                }
                if (stone.kind === "miner") {
                    let f = facing
                    // Legs and boots, the body, the head with its cap and lamp
                    ctx.fillStyle = pal.dark
                    oval(w * 0.4, h * 0.88, w * 0.1, h * 0.09)
                    oval(w * 0.6, h * 0.88, w * 0.1, h * 0.09)
                    ctx.fillStyle = pal.cloth
                    oval(w * 0.5, h * 0.62, w * 0.25, h * 0.22)
                    ctx.fillStyle = pal.skin
                    disc(w * 0.5, h * 0.29, w * 0.17)
                    ctx.fillStyle = pal.cap
                    ctx.beginPath()
                    ctx.arc(w * 0.5, h * 0.26, w * 0.18, Math.PI, Math.PI * 2)
                    ctx.fill()
                    ctx.fillStyle = pal.lamp
                    disc(w * 0.5, h * 0.17, w * 0.06)
                    // The arm and the pick: raised high over its head
                    // petrified, swung down onto the stone by swing while
                    // it works
                    let a = (-62 + 80 * swing) * Math.PI / 180
                    let sx = w * (0.5 + f * 0.17), sy = h * 0.5
                    let ux = f * Math.cos(a), uy = Math.sin(a)
                    let ex = sx + ux * w * 0.3, ey = sy + uy * w * 0.3
                    ctx.lineCap = "round"
                    ctx.strokeStyle = pal.skin
                    ctx.lineWidth = w * 0.1
                    ctx.beginPath(); ctx.moveTo(sx, sy); ctx.lineTo(ex, ey); ctx.stroke()
                    // The handle on from the fist, the head across its end,
                    // curved, a point to each side
                    let hx = ex + ux * w * 0.3, hy = ey + uy * w * 0.3
                    ctx.strokeStyle = pal.handle
                    ctx.lineWidth = w * 0.06
                    ctx.beginPath(); ctx.moveTo(ex - ux * w * 0.04, ey - uy * w * 0.04); ctx.lineTo(hx, hy); ctx.stroke()
                    let px = -uy, py = ux
                    ctx.strokeStyle = pal.tool
                    ctx.lineWidth = w * 0.075
                    ctx.beginPath()
                    ctx.moveTo(hx - px * w * 0.2 - ux * w * 0.06, hy - py * w * 0.2 - uy * w * 0.06)
                    ctx.quadraticCurveTo(hx + ux * w * 0.05, hy + uy * w * 0.05,
                                         hx + px * w * 0.2 - ux * w * 0.06, hy + py * w * 0.2 - uy * w * 0.06)
                    ctx.stroke()
                } else if (upright) {
                    // Freed, standing: a cloak, the pack on its back
                    ctx.fillStyle = pal.pack
                    oval(w * 0.5, h * 0.55, w * 0.22, h * 0.17)
                    ctx.fillStyle = pal.dark
                    oval(w * 0.4, h * 0.88, w * 0.1, h * 0.09)
                    oval(w * 0.6, h * 0.88, w * 0.1, h * 0.09)
                    ctx.fillStyle = pal.cloth
                    oval(w * 0.5, h * 0.63, w * 0.25, h * 0.23)
                    ctx.fillStyle = pal.skin
                    disc(w * 0.5, h * 0.29, w * 0.17)
                    ctx.fillStyle = pal.cloth
                    ctx.beginPath()
                    ctx.arc(w * 0.5, h * 0.27, w * 0.19, Math.PI * 1.05, Math.PI * 1.95)
                    ctx.fill()
                } else {
                    // Huddled: crouched low, knees drawn up, arms round
                    // them, head bowed over them, the pack behind
                    ctx.fillStyle = pal.pack
                    oval(w * 0.5, h * 0.6, w * 0.26, h * 0.15)
                    ctx.fillStyle = pal.cloth
                    oval(w * 0.5, h * 0.74, w * 0.33, h * 0.2)
                    ctx.fillStyle = pal.dark
                    disc(w * 0.38, h * 0.8, w * 0.12)
                    disc(w * 0.62, h * 0.8, w * 0.12)
                    ctx.fillStyle = pal.skin
                    disc(w * 0.5, h * 0.5, w * 0.16)
                    ctx.fillStyle = pal.cloth
                    ctx.beginPath()
                    ctx.arc(w * 0.5, h * 0.48, w * 0.18, Math.PI * 1.05, Math.PI * 1.95)
                    ctx.fill()
                    ctx.strokeStyle = pal.skin
                    ctx.lineWidth = w * 0.08
                    ctx.lineCap = "round"
                    ctx.beginPath()
                    ctx.moveTo(w * 0.24, h * 0.7)
                    ctx.quadraticCurveTo(w * 0.5, h * 0.92, w * 0.76, h * 0.7)
                    ctx.stroke()
                }
            }

            onPaint: {
                let ctx = getContext("2d")
                ctx.reset()
                ctx.translate(figure.padWu * stone.pixelPerUnit, figure.topWu * stone.pixelPerUnit)
                let w = figure.width, h = figure.height
                let pal = stone.kind === "miner" ? miner : lost
                let e = Qt.rgba(stone.shimmerColor.r, stone.shimmerColor.g, stone.shimmerColor.b,
                                colour < 1 ? 0.25 + 0.6 * lit : 0)
                // Grey stone, the edge shimmering in the lantern's light
                if (colour < 1) drawFigure(ctx, grey, e)
                // The colour back, from the middle out
                if (colour > 0) {
                    ctx.save()
                    ctx.beginPath()
                    ctx.arc(w * 0.5, h * 0.6, Math.hypot(w, h) * 0.6 * colour, 0, Math.PI * 2)
                    ctx.clip()
                    ctx.clearRect(-w, -h, 3 * w, 3 * h)
                    drawFigure(ctx, pal, null)
                    ctx.restore()
                }
                if (colour >= 1) return
                // The shell's cracks: two faint ones, one more for each
                // clean strike, fading as the colour comes back
                ctx.globalAlpha = 1 - colour
                for (let c = 0; c < 2 + cracks; c++) {
                    let x = w * (0.3 + 0.4 * stone._r(c * 3)), y = h * (0.3 + 0.2 * stone._r(c * 3 + 1))
                    ctx.strokeStyle = c < 2 ? "rgba(40, 38, 36, 0.45)" : "rgba(20, 18, 16, 0.85)"
                    ctx.lineWidth = Math.max(1, w * (c < 2 ? 0.012 : 0.02))
                    ctx.beginPath()
                    ctx.moveTo(x, y)
                    for (let i = 1; i <= 4; i++) {
                        x += w * 0.08 * (stone._r(c * 9 + i) - 0.5) * 2
                        y += h * 0.09
                        ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                }
                ctx.globalAlpha = 1
            }
        }

        // What it says, in a bubble over its head
        Rectangle {
            id: bubble
            objectName: "stoneBubble"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.top
            anchors.bottomMargin: 2
            width: Math.min(bubbleText.implicitWidth, 170) + 12
            height: bubbleText.height + 8
            radius: 6
            color: "#E8E2D0"
            border.color: "#6A6458"
            border.width: 1
            opacity: stone.saying !== "" ? 0.95 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            Text {
                id: bubbleText
                x: 6
                y: 4
                width: Math.min(implicitWidth, 170)
                text: stone.saying
                wrapMode: Text.WordWrap
                color: "#2A2420"
                font.pixelSize: 10
            }
            Rectangle {
                width: 7
                height: 7
                rotation: 45
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - 4
                color: parent.color
            }
        }
    }

    // The miner's lamp, lit again once the colour is back, above the
    // darkness
    Rectangle {
        id: lamp
        parent: stone.glowParent || stone
        readonly property real sizePx: stone.pixelPerUnit * 0.7
        width: sizePx
        height: sizePx
        radius: sizePx / 2
        x: (parent === stone ? 0 : stone.x) + figure.x + figure.width / 2 - width / 2
        y: (parent === stone ? 0 : stone.y) + figure.y + figure.height * 0.17 - height / 2
        visible: stone.kind === "miner" && stone.colour >= 1 && !stone.gone
        color: "#FFD877"
        opacity: 0.14 * stone.fade
    }

    // The shimmer while a knight is near and it is stone still: a soft
    // pale disc round it, above the darkness
    Rectangle {
        id: shimmer
        parent: stone.glowParent || stone
        readonly property real sizePx: stone.width * 0.6
        width: sizePx
        height: sizePx
        radius: sizePx / 2
        x: (parent === stone ? 0 : stone.x) + stone.width / 2 - width / 2
        y: (parent === stone ? 0 : stone.y) + figure.y + figure.height * 0.55 - height / 2
        visible: !stone.freed && (stone.knightNear || stone.lit > 0)
        color: stone.shimmerColor
        property real breath: 0
        opacity: (0.02 + 0.05 * breath) * Math.max(stone.lit, stone.knightNear ? 0.6 : 0)
        SequentialAnimation on breath {
            running: shimmer.visible
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 1300; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0; duration: 1300; easing.type: Easing.InOutSine }
        }
    }

    // The ring: closing on the figure from ringFrom times ringSize to
    // ringSize, pale, white while a strike is clean
    Rectangle {
        id: ring
        objectName: "stoneRing"
        parent: stone.glowParent || stone
        visible: stone.ringShows && !stone.freed
        readonly property real base: Balance.deep.ringSize * stone.pixelPerUnit
        readonly property real size: base * (Balance.deep.ringFrom - (Balance.deep.ringFrom - 1) * stone.ringProgress)
        width: size
        height: size
        radius: size / 2
        x: (parent === stone ? 0 : stone.x) + stone.width / 2 - size / 2
        y: (parent === stone ? 0 : stone.y) + (stone.cyWu + stone.sizeWu / 2 - stone.faceYWu) * stone.pixelPerUnit - size / 2
        color: "transparent"
        border.width: Math.max(1.5, base * Balance.parryRing.thickness)
        border.color: stone.ringOpen ? Balance.parryRing.flashColor : stone.shimmerColor
        opacity: Balance.parryRing.opacity
    }
}
