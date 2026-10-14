import QtQuick

// A spawn hole in a wall (issue #157, Balance.deep.hole): a small dark
// burrow with a ragged rim low in the face of a wall cell of a vein's
// room. Its stage, set by the game: "rest" a detail of the wall; "dust"
// woken, the rim trembling (the game puffs dust from it); "eyes" two eyes
// open in its dark, above the darkness, and blink; "waves" they stay
// open while creatures crawl out; "closed" the rim has crumbled shut, a
// heap of rubble in the burrow. Visual only - the cell stays a wall
Item {
    id: hole
    objectName: "spawnHole"

    property real pixelPerUnit: 1
    // The wall cell's centre in wu, and the cell's size; its face is the
    // lower faceWu of it, towards the floor south of it
    property real cxWu: 0
    property real cyWu: 0
    property real sizeWu: 2
    property real faceWu: 0.7
    // The cell, "gx,gy"
    property string cell: ""
    // 0..1 from its cell, for the rim's and the rubble's shapes
    property real seed: 0
    // Where the darkness is drawn over: the eyes go there
    property Item glowParent: null

    // The veins of its room, "gx,gy", whose cut gems may wake it, and the
    // waves sent
    property var veinCells: []
    property int wave: 0

    property string stage: "rest"
    readonly property bool awake: stage === "dust" || stage === "eyes" || stage === "waves"
    readonly property bool eyesOpen: stage === "eyes" || stage === "waves"
    readonly property bool closed: stage === "closed"

    // Its mouth, the bottom middle of the face, where creatures come out,
    // in wu
    readonly property real mouthXWu: cxWu
    readonly property real mouthYWu: cyWu - sizeWu / 2

    x: (cxWu - sizeWu / 2) * pixelPerUnit
    y: (parent ? parent.height : 0) - (cyWu + sizeWu / 2) * pixelPerUnit
    width: sizeWu * pixelPerUnit
    height: width

    function _r(k) { return Math.abs((Math.sin((k + 1) * 12.9898 + hole.seed * 78.233) * 43758.5453) % 1) }

    // The burrow: an arch from the floor up into the face, its rim of
    // ragged stones lighter than the dark inside; closed, rubble fills it
    Canvas {
        id: burrow
        anchors.fill: parent
        readonly property bool shut: hole.closed
        onShutChanged: requestPaint()
        onWidthChanged: requestPaint()
        // The rim trembles while the hole is awake
        property real shake: 0
        transform: Translate { x: burrow.shake * hole.width * 0.012 }
        SequentialAnimation on shake {
            running: hole.awake
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 60 }
            NumberAnimation { from: 1; to: -1; duration: 120 }
            NumberAnimation { from: -1; to: 0; duration: 60 }
            PauseAnimation { duration: 260 }
        }
        onPaint: {
            let ctx = getContext("2d")
            ctx.reset()
            let w = width, h = height
            let face = h * hole.faceWu / hole.sizeWu
            let cx = w * 0.5, bottom = h
            let rx = w * 0.27, ry = face * 0.78
            // The arch's outline, ragged: points round the top half of an
            // ellipse standing on the floor
            let arch = (sx, sy, jag) => {
                let pts = []
                for (let i = 0; i <= 10; i++) {
                    let a = Math.PI * i / 10
                    let j = 1 + jag * (hole._r(i + 3) - 0.5)
                    pts.push([cx - Math.cos(a) * sx * j, bottom - Math.sin(a) * sy * j])
                }
                return pts
            }
            let fill = (pts, colour) => {
                ctx.fillStyle = colour
                ctx.beginPath()
                ctx.moveTo(pts[0][0], bottom)
                for (let p of pts) ctx.lineTo(p[0], p[1])
                ctx.lineTo(pts[pts.length - 1][0], bottom)
                ctx.closePath()
                ctx.fill()
            }
            // The rim: broken stones round the mouth, a shade lighter
            fill(arch(rx * 1.32, ry * 1.25, 0.32), "rgba(92, 84, 74, 0.85)")
            fill(arch(rx * 1.14, ry * 1.1, 0.22), "#1E1A17")
            // The dark inside, darkest at the back
            fill(arch(rx, ry, 0.16), "#070605")
            fill(arch(rx * 0.6, ry * 0.62, 0.1), "#000000")
            if (!shut) return
            // Rubble fills it: a heap of grey chunks up to the rim
            for (let k = 0; k < 9; k++) {
                let u = (k % 3 - 1) * 0.62 + 0.24 * (hole._r(k * 4) - 0.5)
                let v = Math.floor(k / 3)
                let px = cx + u * rx, py = bottom - (0.2 + 0.3 * v) * ry
                let s = rx * (0.42 - 0.07 * v) * (0.8 + 0.4 * hole._r(k * 4 + 1))
                ctx.fillStyle = ["#5E574E", "#4C463F", "#6B645A"][k % 3]
                ctx.beginPath()
                for (let c = 0; c < 6; c++) {
                    let a = Math.PI * 2 * c / 6 + hole._r(k * 4 + 2)
                    let rr = s * (0.7 + 0.3 * hole._r(k * 9 + c))
                    let qx = px + Math.cos(a) * rr, qy = py + Math.sin(a) * rr * 0.7
                    if (c === 0) ctx.moveTo(qx, qy)
                    else ctx.lineTo(qx, qy)
                }
                ctx.closePath()
                ctx.fill()
            }
        }
    }

    // The eyes: two small lit slits in the dark that open, above the
    // darkness, and blink now and then
    Item {
        id: eyes
        objectName: "holeEyes"
        parent: hole.glowParent || hole
        readonly property real sizePx: hole.width * 0.07
        width: hole.width * 0.36
        height: sizePx
        x: (parent === hole ? 0 : hole.x) + hole.width / 2 - width / 2
        y: (parent === hole ? 0 : hole.y) + hole.height * (1 - 0.45 * hole.faceWu / hole.sizeWu) - height / 2
        visible: open > 0.01
        property real open: hole.eyesOpen ? 1 : 0
        Behavior on open { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
        property real blink: 1
        SequentialAnimation on blink {
            running: hole.eyesOpen
            loops: Animation.Infinite
            PauseAnimation { duration: 1500 + 1100 * hole._r(5) }
            NumberAnimation { to: 0.1; duration: 70 }
            NumberAnimation { to: 1; duration: 110 }
        }
        Repeater {
            model: [-1, 1]
            Rectangle {
                required property real modelData
                width: eyes.sizePx * 1.3
                height: eyes.sizePx * eyes.open * eyes.blink
                radius: width / 2
                x: eyes.width / 2 + modelData * eyes.width * 0.25 - width / 2
                y: eyes.height / 2 - height / 2
                color: "#FFD04A"
                // The glow round each eye, under it
                Rectangle {
                    z: -1
                    anchors.centerIn: parent
                    width: eyes.sizePx * 2.2
                    height: width
                    radius: width / 2
                    color: "#FF9A2A"
                    opacity: 0.2 * eyes.open
                }
            }
        }
    }
}
