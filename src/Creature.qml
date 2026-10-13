import QtQuick

// A small creature of the camp (issue #150), the template the cave cat is
// made from and later creatures reuse: it idles in a loop, looks up when a
// knight comes near, and settles back when the knight leaves. It is drawn
// only - no body, nothing collides with it, nobody talks to it, nothing
// depends on it. A creature fills it with its shapes, which read:
//   lift       0 idle .. 1 alert, eased over rise and fall seconds
//   lookX/Y    the way to the knight it watches, a unit vector, y up
//   breathing  -1 .. 1, one breath every numbers.breath seconds
//   act        0 .. 1 .. 0 while its idle act plays (the cat's stretch)
// Each screen watches its own knights (gameWorld.knightsHere()), so in a
// session it looks up at whichever knight comes near on every screen.
Item {
    id: creature

    // What it is, for the benches; its numbers, a Balance.camp group
    property string creature: ""
    property var numbers: ({})
    property var gameWorld: null
    property real pixelPerUnit: parent && parent.pixelPerUnit !== undefined ? parent.pixelPerUnit : 1
    // Where it lies, its centre in wu, y up as the world's
    property real xWu: 0
    property real yWu: 0
    property real sizeWu: numbers.size || 1
    // Its own stream's draw, 0..1: when its acts come, which way it lies
    property real seed: 0

    x: (xWu - sizeWu / 2) * pixelPerUnit
    y: parent ? parent.height - (yWu + sizeWu / 2) * pixelPerUnit : 0
    width: sizeWu * pixelPerUnit
    height: width

    // "idle" or "alert": alert while a standing knight is within notice
    // wu, idle again settle seconds after none is within forget wu. A
    // knight that sits down is no news: it lets the creature settle
    readonly property string mood: _alert ? "alert" : "idle"
    property bool _alert: false
    // The knight it watches, or null
    property var watching: null
    property real lookX: 0
    property real lookY: -1
    property real _awayFor: 0

    property real lift: _alert ? 1 : 0
    Behavior on lift {
        NumberAnimation {
            duration: (creature._alert ? creature.numbers.rise : creature.numbers.fall) * 1000
            easing.type: Easing.InOutSine
        }
    }

    // One tick of the watch: who is near, and how long since anyone was
    function watch(dt) {
        let n = numbers
        let knights = gameWorld && gameWorld.knightsHere ? gameWorld.knightsHere() : []
        let best = null, bestD = Infinity
        for (let k of knights) {
            if (k.seated) continue
            let d = Math.hypot(k.x - xWu, k.y - yWu)
            if (d < bestD) { bestD = d; best = k }
        }
        if (best && bestD < (_alert ? n.forget : n.notice)) {
            _alert = true
            _awayFor = 0
            watching = best.knight
            if (bestD > 0.01) {
                lookX = (best.x - xWu) / bestD
                lookY = (best.y - yWu) / bestD
            }
        } else if (_alert) {
            _awayFor += dt
            if (_awayFor >= n.settle) {
                _alert = false
                watching = null
            }
        }
        _actIn -= dt
        if (_actIn <= 0 && !_alert && lift === 0 && !actAnim.running) actAnim.start()
    }
    Timer {
        interval: creature.numbers.tick * 1000
        running: !!creature.gameWorld
        repeat: true
        onTriggered: creature.watch(interval / 1000)
    }

    // Its breath, one every numbers.breath seconds
    property real _t: 0
    NumberAnimation on _t {
        from: 0; to: 1000; duration: 1000000
        loops: Animation.Infinite
    }
    readonly property real breathing: Math.sin(2 * Math.PI * (_t / numbers.breath + seed))

    // The idle act: now and then, every act.every[0] to [1] seconds of
    // its own stream, while idle, for act.seconds
    property real act: 0
    property real _actIn: _nextAct()
    property int _acts: 0
    function _nextAct() {
        let a = numbers.act
        if (!a) return Infinity
        // A hash of its seed and how many acts it has done, not
        // Math.random: the same creature acts on the same beat everywhere
        let h = Math.abs(Math.sin((seed * 1000 + _acts * 7.31) * 12.9898) * 43758.5453) % 1
        return a.every[0] + h * (a.every[1] - a.every[0])
    }
    SequentialAnimation {
        id: actAnim
        NumberAnimation {
            target: creature; property: "act"; to: 1
            duration: creature.numbers.act ? creature.numbers.act.seconds * 400 : 0
            easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: creature.numbers.act ? creature.numbers.act.seconds * 200 : 0 }
        NumberAnimation {
            target: creature; property: "act"; to: 0
            duration: creature.numbers.act ? creature.numbers.act.seconds * 400 : 0
            easing.type: Easing.InOutSine
        }
        ScriptAction { script: { creature._acts++; creature._actIn = creature._nextAct() } }
    }
    // Woken, it leaves its act
    on_AlertChanged: if (_alert && actAnim.running) { actAnim.stop(); act = 0; _acts++; _actIn = _nextAct() }
}
