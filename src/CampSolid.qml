import QtQuick
import Box2D
import Clayground.Physics

// What the knights cannot walk on in the camp (issue #178): the pond, the
// bushes, the stones and the other props that stand up from the floor,
// and the campfire's core. An invisible static body over the prop's
// rectangle (xWu, yWu its north-west corner, y up), shape "oval" the
// ellipse inside it or "box" the rectangle, both fill of it about its
// middle. The ellipse is an octagon, the most corners a Box2D polygon
// takes
PhysicsItem {
    id: solid
    objectName: "campSolid"

    property string shape: "oval"
    property real fill: 1
    // What it stands for: a prop's kind, or "fire"
    property string kind: ""
    property alias categories: outline.categories
    property alias collidesWith: outline.collidesWith

    bodyType: Body.Static

    // Its corners in wu from its middle, y up
    readonly property var cornersWu: {
        let a = widthWu / 2 * fill, b = heightWu / 2 * fill
        if (shape === "box")
            return [Qt.point(-a, b), Qt.point(a, b), Qt.point(a, -b), Qt.point(-a, -b)]
        let pts = []
        for (let i = 0; i < 8; i++) {
            let t = (i + 0.5) * Math.PI / 4
            pts.push(Qt.point(a * Math.cos(t), b * Math.sin(t)))
        }
        return pts
    }
    // Whether the point (x, y) wu lies inside it
    function holds(x, y) {
        let px = x - (xWu + widthWu / 2), py = y - (yWu - heightWu / 2)
        let c = cornersWu, n = c.length, side = 0
        for (let i = 0; i < n; i++) {
            let p = c[i], q = c[(i + 1) % n]
            let cross = (q.x - p.x) * (py - p.y) - (q.y - p.y) * (px - p.x)
            if (cross !== 0) {
                if (side === 0) side = Math.sign(cross)
                else if (Math.sign(cross) !== side) return false
            }
        }
        return true
    }

    fixtures: [
        Polygon {
            id: outline
            friction: 0.0
            restitution: 0.0
            vertices: solid.cornersWu.map(p => Qt.point((p.x + solid.widthWu / 2) * solid.pixelPerUnit,
                                                         (solid.heightWu / 2 - p.y) * solid.pixelPerUnit))
        }
    ]
}
