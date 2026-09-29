import QtQuick

// One short-lived particle in world units: a shard, a spark or a mote.
// It flies out with (velX, velY) wu/s, slows down, spins and fades, all
// driven by a single animated progress value, then destroys itself.
Rectangle {
    id: p

    property real pixelPerUnit: 1
    property real xWu: 0
    property real yWu: 0
    property real velX: 0
    property real velY: 0
    property real sizeWu: 0.2
    property real lifetime: 500        // ms
    property real spin: 0              // degrees over the lifetime
    property real shrinkTo: 0.25       // size factor at the end of life
    property real stretch: 1           // >1 draws a streak along the velocity
    property bool round: false

    property real t: 0
    // Covered distance: decelerating, as if dragged along the floor.
    readonly property real _travel: (1 - Math.pow(1 - t, 3)) * lifetime / 1000 / 1.8
    readonly property real _x: xWu + velX * _travel
    readonly property real _y: yWu + velY * _travel

    width: sizeWu * pixelPerUnit * stretch * (1 - (1 - shrinkTo) * t)
    height: sizeWu * pixelPerUnit * (1 - (1 - shrinkTo) * t)
    x: _x * pixelPerUnit - width / 2
    y: (parent ? parent.height : 0) - _y * pixelPerUnit - height / 2
    radius: round ? height / 2 : 0
    rotation: stretch > 1 ? -Math.atan2(velY, velX) * 180 / Math.PI
                          : _rot0 + spin * t
    readonly property real _rot0: Math.random() * 360
    opacity: t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4
    antialiasing: true

    NumberAnimation on t {
        from: 0; to: 1
        duration: p.lifetime
        onFinished: p.destroy()
    }
}
