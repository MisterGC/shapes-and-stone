import QtQuick

// A traveller of the deep (issue #176, Balance.deep.traveller): someone
// the deep drew down, on the floor of a vein's room in front of its rock
// face. A lost one sits huddled there, arms round its knees, a pack on
// its back, trembling with fear. A miner came for the treasure: it stands
// beside the vein, a lamp on its cap, and swings its own pick at the rock
// (swing, set by the game) while a knight is near. Talked to, it says its
// line in a bubble over its head and the game walks it off toward the
// exit, fading (fade). While this node's knight can talk to it, "[E] Talk"
// shows over it. A rare one is special (issue #159): a faint gold edge
// round it. Seated, it is one by a camp's fire, huddled in either kind,
// calm
Item {
    id: traveller
    objectName: "deepTraveller"

    property real pixelPerUnit: 1
    // Its box: centred on cxWu, cyWu, sizeWu across, its feet near its
    // bottom (footXWu, footYWu)
    property real cxWu: 0
    property real cyWu: 0
    property real sizeWu: 2
    // The wall cell of the rock face it is in front of, "gx,gy"; at a
    // camp a name of the spot
    property string cell: ""
    // "miner" or "lost"
    property string kind: "miner"
    // The veins of its room, "gx,gy", its room's spawn hole ("" none) and
    // the room's index in the dungeon (-1 none)
    property var veinCells: []
    property string holeCell: ""
    property int roomIndex: -1
    // The id of Balance.deep.specials it is, "" none
    property string special: ""
    // Sitting by a camp's fire: huddled in either kind, not afraid
    property bool seated: false
    // 0..1 from its cell
    property real seed: 0
    // Where the darkness is drawn over: the lamp and the gold glow go there
    property Item glowParent: null

    // How it goes on, set by the game: "" still here, "leaving" (talked
    // to) or "fleeing" (a miner once its hole's creatures came); gone once
    // it walked out of sight
    property string outcome: ""
    property bool gone: false
    // The figure's fade, 1..0
    property real fade: 1
    // Where its feet stand, in wu; whether it walks now, which way it
    // faces (-1 left, 1 right), and the pick's swing 0..1 (raised ..
    // down on the rock)
    property real footXWu: cxWu
    property real footYWu: cyWu - sizeWu / 2 + 0.05
    property bool walking: false
    property int facing: 1
    property real swing: 1
    // A miner digging now, and its strikes so far
    property bool digging: false
    property int digs: 0
    // This node's knight is near enough to talk to it
    property bool talkable: false
    // What it says, in a bubble over its head
    property string saying: ""

    // Afraid: a lost one still waiting in the deep
    readonly property bool afraid: kind === "lost" && !seated && outcome === ""
    // Huddled: a lost one before it stands up to go, or anyone seated
    readonly property bool huddled: seated || (kind === "lost" && outcome === "")
    // Its middle, in wu, where a knight talks to
    readonly property real midXWu: footXWu
    readonly property real midYWu: footYWu + 0.55
    // Where its pick strikes the rock, in wu
    readonly property real pickXWu: footXWu + facing * 0.55
    readonly property real pickYWu: footYWu + 0.5

    readonly property color edgeColor: Balance.deep.specialEdge

    x: (cxWu - sizeWu / 2) * pixelPerUnit
    y: (parent ? parent.height : 0) - (cyWu + sizeWu / 2) * pixelPerUnit
    width: sizeWu * pixelPerUnit
    height: width

    // The figure: its feet at footXWu, footYWu
    Item {
        id: figure
        // The figure's box, its feet at the bottom middle, and room round
        // it for the raised pick
        readonly property real wWu: 1.0
        readonly property real hWu: 1.3
        readonly property real padWu: 0.25
        readonly property real topWu: 0.45
        width: wWu * traveller.pixelPerUnit
        height: hWu * traveller.pixelPerUnit
        x: (traveller.footXWu - (traveller.cxWu - traveller.sizeWu / 2)) * traveller.pixelPerUnit - width / 2
        y: (traveller.cyWu + traveller.sizeWu / 2 - traveller.footYWu) * traveller.pixelPerUnit - height
        opacity: traveller.fade
        visible: !traveller.gone

        // A bob while it walks, a shiver while it is afraid
        property real bob: 0
        property real shiver: 0
        transform: Translate {
            x: figure.shiver * figure.width * Balance.deep.traveller.tremble
            y: -figure.bob * figure.height * 0.04
        }
        SequentialAnimation on bob {
            running: traveller.walking
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 160; easing.type: Easing.OutQuad }
            NumberAnimation { from: 1; to: 0; duration: 160; easing.type: Easing.InQuad }
        }
        SequentialAnimation on shiver {
            running: traveller.afraid
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 45 }
            NumberAnimation { from: 1; to: -1; duration: 90 }
            NumberAnimation { from: -1; to: 0; duration: 45 }
            PauseAnimation { duration: 140 + 220 * traveller.seed }
        }

        Canvas {
            id: body
            x: -figure.padWu * traveller.pixelPerUnit
            y: -figure.topWu * traveller.pixelPerUnit
            width: parent.width + 2 * figure.padWu * traveller.pixelPerUnit
            height: parent.height + figure.topWu * traveller.pixelPerUnit
            readonly property real swing: traveller.swing
            readonly property int facing: traveller.facing
            readonly property bool huddled: traveller.huddled
            onSwingChanged: requestPaint()
            onFacingChanged: requestPaint()
            onHuddledChanged: requestPaint()
            onWidthChanged: requestPaint()

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
                    if (!huddled) {
                        oval(w * 0.5, h * 0.62, w * 0.3, h * 0.27)
                        disc(w * 0.5, h * 0.27, w * 0.21)
                    } else {
                        oval(w * 0.5, h * 0.72, w * 0.38, h * 0.24)
                        disc(w * 0.5, h * 0.47, w * 0.21)
                    }
                }
                if (traveller.kind === "miner" && !traveller.seated) {
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
                    // The arm and the pick: raised high over its head at
                    // swing 0, down on the rock at 1
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
                } else if (!huddled) {
                    // Standing to go: a cloak, the pack on its back
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
                    // A miner sitting keeps its cap and lamp on
                    if (traveller.kind === "miner") {
                        ctx.fillStyle = pal.cap
                        ctx.beginPath()
                        ctx.arc(w * 0.5, h * 0.47, w * 0.18, Math.PI, Math.PI * 2)
                        ctx.fill()
                        ctx.fillStyle = pal.lamp
                        disc(w * 0.5, h * 0.38, w * 0.06)
                    }
                }
            }

            onPaint: {
                let ctx = getContext("2d")
                ctx.reset()
                ctx.translate(figure.padWu * traveller.pixelPerUnit, figure.topWu * traveller.pixelPerUnit)
                // A special keeps a faint gold edge
                drawFigure(ctx, traveller.kind === "miner" ? miner : lost, traveller.special !== ""
                           ? Qt.rgba(traveller.edgeColor.r, traveller.edgeColor.g, traveller.edgeColor.b, 0.55) : null)
            }
        }

        // What it says, in a bubble over its head
        Rectangle {
            id: bubble
            objectName: "travellerBubble"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.top
            anchors.bottomMargin: 2
            width: Math.min(bubbleText.implicitWidth, 170) + 12
            height: bubbleText.height + 8
            radius: 6
            color: "#E8E2D0"
            border.color: "#6A6458"
            border.width: 1
            opacity: traveller.saying !== "" ? 0.95 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            Text {
                id: bubbleText
                x: 6
                y: 4
                width: Math.min(implicitWidth, 170)
                text: traveller.saying
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

        // The prompt while this node's knight can talk to it
        Text {
            objectName: "travellerPrompt"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.top
            anchors.bottomMargin: 2
            text: "[E] Talk"
            color: "#FFFFFF"
            font.pixelSize: 10
            font.bold: true
            style: Text.Outline
            styleColor: "#000000"
            opacity: traveller.talkable && traveller.saying === "" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
    }

    // The miner's lamp, above the darkness
    Rectangle {
        id: lamp
        parent: traveller.glowParent || traveller
        readonly property real sizePx: traveller.pixelPerUnit * 0.7
        width: sizePx
        height: sizePx
        radius: sizePx / 2
        x: (parent === traveller ? 0 : traveller.x) + figure.x + figure.width / 2 - width / 2
        y: (parent === traveller ? 0 : traveller.y) + figure.y + figure.height * (traveller.seated ? 0.38 : 0.17) - height / 2
        visible: traveller.kind === "miner" && !traveller.gone
        color: "#FFD877"
        opacity: 0.14 * traveller.fade
    }

    // A special's faint gold glow, breathing, above the darkness
    Rectangle {
        id: glow
        parent: traveller.glowParent || traveller
        readonly property real sizePx: traveller.pixelPerUnit * 1.3
        width: sizePx
        height: sizePx
        radius: sizePx / 2
        x: (parent === traveller ? 0 : traveller.x) + figure.x + figure.width / 2 - width / 2
        y: (parent === traveller ? 0 : traveller.y) + figure.y + figure.height * 0.55 - height / 2
        visible: traveller.special !== "" && !traveller.gone
        color: traveller.edgeColor
        property real breath: 0
        opacity: (0.03 + 0.04 * breath) * traveller.fade
        SequentialAnimation on breath {
            running: glow.visible
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 1300; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0; duration: 1300; easing.type: Easing.InOutSine }
        }
    }
}
