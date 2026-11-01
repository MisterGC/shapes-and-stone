import QtQuick

// A gamepad in the menus (issue #201): the stick or the D-pad of the
// game's controller moves the focus a row or a step, held it moves on
// after a moment, A confirms, B goes back, X is the menu's own extra and
// startInput, the menu's binding in the game's ControlTable (Start by
// default, issue #218), pauses. Only the press counts, so a button held
// into a menu does nothing there; the game decides which menu each one
// reaches.
Item {
    id: menuPad

    property var controller: null
    // A stick past this far is pushed in its direction
    property real deadZone: 0.5
    // Held, the direction moves again after delayMs and then every repeatMs
    property int delayMs: 400
    property int repeatMs: 150
    // The pad input that pauses and resumes, as GameController.inputs names
    // it; a trigger counts pressed past deadZone
    property string startInput: "buttonStart"

    // dx, dy: -1, 0 or 1, up and right positive
    signal moved(int dx, int dy)
    signal confirmed()
    signal backed()
    signal extra()
    signal started()

    function _dir(v) { return v > deadZone ? 1 : v < -deadZone ? -1 : 0 }
    readonly property int _dx: controller ? _dir(controller.axisX) : 0
    readonly property int _dy: controller ? _dir(controller.axisY) : 0
    property int _heldX: 0
    property int _heldY: 0

    function _push() {
        // One direction at a time: a diagonal moves the way it leans most
        let dx = _dx, dy = _dy
        if (dx !== 0 && dy !== 0) {
            if (Math.abs(controller.axisX) >= Math.abs(controller.axisY)) dy = 0
            else dx = 0
        }
        if (dx === _heldX && dy === _heldY) return
        _heldX = dx
        _heldY = dy
        if (dx === 0 && dy === 0) {
            repeat.stop()
            return
        }
        moved(dx, dy)
        repeat.interval = delayMs
        repeat.restart()
    }
    on_DxChanged: _push()
    on_DyChanged: _push()

    function _pressed(v) { return typeof v === "number" ? v > deadZone : !!v }
    readonly property bool _start: !!controller && startInput !== ""
                                   && _pressed(controller.inputValue(startInput))
    on_StartChanged: if (_start) started()

    Timer {
        id: repeat
        onTriggered: {
            menuPad.moved(menuPad._heldX, menuPad._heldY)
            interval = menuPad.repeatMs
            start()
        }
    }

    Connections {
        target: menuPad.controller
        function onButtonAPressedChanged() { if (menuPad.controller.buttonAPressed) menuPad.confirmed() }
        function onButtonBPressedChanged() { if (menuPad.controller.buttonBPressed) menuPad.backed() }
        function onButtonXPressedChanged() { if (menuPad.controller.buttonXPressed) menuPad.extra() }
    }
}
