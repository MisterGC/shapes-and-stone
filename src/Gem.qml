import QtQuick

// A gem as the deep keeps it (issue #155, Balance.deep.shapes): one of the
// five Platonic solids drawn flat, as the knight is, its faces in light,
// middle and dark tones of its colour with lit edges. Drawing only - a
// vein's cluster and the gem popping out of it are made of these.
Canvas {
    id: gem

    // "tetrahedron", "cube", "octahedron", "dodecahedron" or "icosahedron"
    property string shape: "tetrahedron"
    property color color: "#F2B33D"
    // Below 1 the faces are darkened by it, for a gem still in the stone
    property real light: 1

    onShapeChanged: requestPaint()
    onColorChanged: requestPaint()
    onLightChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    // The points of a ring of n round the centre at radius r, the first at
    // the angle a0 in degrees, screen y down
    function _ring(n, r, a0) {
        let out = []
        for (let i = 0; i < n; i++) {
            let a = (a0 + 360 * i / n) * Math.PI / 180
            out.push([r * Math.cos(a), r * Math.sin(a)])
        }
        return out
    }
    // The shape's faces in [-1, 1], screen y down: [[x, y], ...] each
    function faces(shape) {
        if (shape === "cube") {
            let h = _ring(6, 1, -90), c = [0, 0]
            return [[h[0], h[1], c, h[5]], [h[5], c, h[3], h[4]], [c, h[1], h[2], h[3]]]
        }
        if (shape === "octahedron") {
            let t = [0, -1], r = [0.72, 0], b = [0, 1], l = [-0.72, 0], c = [-0.12, -0.08]
            return [[t, l, c], [t, c, r], [l, b, c], [c, b, r]]
        }
        if (shape === "dodecahedron") {
            let o = _ring(10, 1, -90), n = _ring(5, 0.52, -90), out = [n]
            for (let i = 0; i < 5; i++)
                out.push([n[i], o[2 * i], o[2 * i + 1], o[(2 * i + 2) % 10], n[(i + 1) % 5]])
            return out
        }
        if (shape === "icosahedron") {
            let o = _ring(6, 1, -90), n = _ring(3, 0.5, -90), out = [n]
            for (let i = 0; i < 3; i++) {
                let a = n[i], b = n[(i + 1) % 3]
                out.push([a, o[2 * i], o[2 * i + 1]], [a, o[2 * i + 1], b], [b, o[2 * i + 1], o[(2 * i + 2) % 6]])
            }
            return out
        }
        let p = _ring(3, 1, -90), c = [0, 0.08]
        return [[c, p[2], p[0]], [c, p[0], p[1]], [c, p[1], p[2]]]
    }

    onPaint: {
        let ctx = getContext("2d")
        ctx.reset()
        let s = Math.min(width, height) / 2 * 0.92
        let cx = width / 2, cy = height / 2
        // Lit from the upper left, as the knight's lantern side of things
        let lx = -0.6, ly = -0.8
        for (let f of faces(shape)) {
            let mx = 0, my = 0
            for (let p of f) { mx += p[0] / f.length; my += p[1] / f.length }
            let len = Math.hypot(mx, my)
            let k = len < 0.05 ? 0.25 : (mx * lx + my * ly) / len
            let tone = k > 0.3 ? Qt.lighter(color, 1.35) : k > -0.3 ? color : Qt.darker(color, 1.6)
            if (light < 1) tone = Qt.darker(tone, 1 / Math.max(0.2, light))
            ctx.beginPath()
            ctx.moveTo(cx + f[0][0] * s, cy + f[0][1] * s)
            for (let p of f) ctx.lineTo(cx + p[0] * s, cy + p[1] * s)
            ctx.closePath()
            ctx.fillStyle = tone
            ctx.fill()
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.55 * light)
            ctx.lineWidth = Math.max(1, s * 0.05)
            ctx.lineJoin = "round"
            ctx.stroke()
        }
    }
}
