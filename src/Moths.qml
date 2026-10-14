import QtQuick

// The moths circling the camp's campfire and lanterns (issue #149): every
// moth of every light drawn in one pass of shaders/moths.frag over the
// rectangle their loops lie in, no item per moth. Visual only.
ShaderEffect {
    id: moths

    readonly property var numbers: Balance.camp.moths
    // The lights the moths circle, at most maxLights: { x, y, orbit,
    // count }, x and y the light's centre in wu, at most maxPerLight
    // moths each
    property var mothLights: []
    readonly property int maxLights: 6
    readonly property int maxPerLight: 8
    readonly property var _lights: mothLights.slice(0, maxLights)
    readonly property int mothCount: _lights.reduce((n, l) => n + Math.min(l.count, maxPerLight), 0)

    // The rectangle every loop lies in, in wu: west, south, east, north
    readonly property real _reach: Math.max(numbers.fire.orbit, numbers.lantern.orbit) * (1 + numbers.swell / 2)
                                   + numbers.dart + numbers.size + 0.5
    readonly property real westWu: _lights.length ? Math.min(..._lights.map(l => l.x)) - _reach : 0
    readonly property real eastWu: _lights.length ? Math.max(..._lights.map(l => l.x)) + _reach : 0
    readonly property real southWu: _lights.length ? Math.min(..._lights.map(l => l.y)) - _reach : 0
    readonly property real northWu: _lights.length ? Math.max(..._lights.map(l => l.y)) + _reach : 0

    property real pixelPerUnit: parent ? parent.pixelPerUnit : 1
    z: 5
    x: westWu * pixelPerUnit
    y: parent ? parent.height - northWu * pixelPerUnit : 0
    width: (eastWu - westWu) * pixelPerUnit
    height: (northWu - southWu) * pixelPerUnit
    blending: true
    fragmentShader: "shaders/moths.frag.qsb"

    function _slot(i) {
        let l = _lights[i]
        return l ? Qt.vector4d(l.x - westWu, l.y - southWu, l.orbit, Math.min(l.count, maxPerLight))
                 : Qt.vector4d(0, 0, 0, 0)
    }
    property vector2d sizeWu: Qt.vector2d(eastWu - westWu, northWu - southWu)
    property real time: 0
    property real pixelsPerWu: 12
    property real seed: 0
    property real squash: numbers.squash
    property real swell: numbers.swell
    property vector2d speed: Qt.vector2d(numbers.speed[0], numbers.speed[1])
    property real waver: numbers.waver
    property real dart: numbers.dart
    property real mothSize: numbers.size
    property real flutter: numbers.flutter
    property vector4d l0: _slot(0)
    property vector4d l1: _slot(1)
    property vector4d l2: _slot(2)
    property vector4d l3: _slot(3)
    property vector4d l4: _slot(4)
    property vector4d l5: _slot(5)
    property color color: "white"

    // false holds the moths at time, for a capture that steps it itself
    property alias flying: flight.running
    NumberAnimation on time {
        id: flight
        from: 0; to: 3600; duration: 3600000
        loops: Animation.Infinite
    }
}
