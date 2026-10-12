import QtQuick

// An arrow from a slit (Balance.dungeon.arrow...): a shaft with a pale
// head at (xWu, yWu) and fletching at its tail, lengthWu behind the head
// along (dirX, dirY), y up. Its flight is a function of the clock, worked
// out by Game._stepSlits, which sets its head each step; this only draws
// it. Drawn above the darkness, so a knight sees it coming.
Item {
    id: arrow

    property real pixelPerUnit: 1
    // The slit's cell and the beat it left on: the same on every screen
    property string arrowId: ""
    // The slit it left
    property var slit: null
    property real xWu: 0
    property real yWu: 0
    property real dirX: 1
    property real dirY: 0
    property real lengthWu: 0.8
    // Where its flight starts - the muzzle, or where a perfect block sent
    // it back from - the clock's moment it starts at (s), how far it flies
    // from there (wu), and whether it flies back to its slit
    property real fromX: 0
    property real fromY: 0
    property real fromT: 0
    property real flightWu: 0
    property bool back: false
    // This node's knight met it already: it is judged once
    property bool judged: false
    // The head's place on the step before, for the knight it passes
    property real lastX: 0
    property real lastY: 0

    z: 5
    x: xWu * pixelPerUnit
    y: (parent ? parent.height : 0) - yWu * pixelPerUnit
    width: 0
    height: 0
    // Screen y runs down
    rotation: Math.atan2(-dirY, dirX) * 180 / Math.PI

    readonly property real _len: lengthWu * pixelPerUnit
    readonly property real _thick: Math.max(1.5, 0.07 * pixelPerUnit)

    Rectangle {
        x: -arrow._len
        y: -arrow._thick / 2
        width: arrow._len
        height: arrow._thick
        color: "#9A7650"
    }
    // The head
    Rectangle {
        x: -width * 0.6
        y: -height / 2
        width: arrow._thick * 3.2
        height: arrow._thick * 2.4
        radius: height * 0.2
        color: arrow.back ? "#FFFFFF" : "#DCD8CC"
    }
    // The fletching
    Rectangle {
        x: -arrow._len
        y: -height / 2
        width: arrow._len * 0.25
        height: arrow._thick * 2.6
        color: "#C8C0B0"
        opacity: 0.85
    }
}
