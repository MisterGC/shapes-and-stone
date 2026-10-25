import QtQuick
import QtQml
import Clayground.GameController

// The knight on a gamepad (issue #200): the game's controller in its full
// layout - the left stick moves (Game.knightMoveX), the right stick aims, R1
// strikes as the left mouse button does, L1 raises the shield, B dashes
// (Game.qml) and the other buttons do what the keys do. The pad is in use
// from its first input to the next key press, and its aim from its first
// input to the next move of the mouse; the hints name its buttons
// meanwhile. A physical pad is taken as the controller's source when one
// of its buttons or sticks moves, the keyboard again when a key goes down.
Item {
    id: knightPad

    property var controller: null
    property var game: null
    // The game's dialogue panel: A goes on, the stick picks a ware, X buys it
    property var dialogue: null

    // The keyboard's part of the controller: WASD and Space for B
    readonly property var keyboardKeys: ({ axisX: [Qt.Key_A, Qt.Key_D], axisY: [Qt.Key_S, Qt.Key_W],
                                           buttonB: Qt.Key_Space })

    // A pad drives the knight: the hints name its buttons
    property bool inUse: false
    // The pad aims, at aimAngle degrees up from the right, until the mouse
    // moves
    property bool aiming: false
    property real aimAngle: 0
    // A stick past this far counts, a trigger past triggerOn is pressed
    property real deadZone: 0.3
    property real triggerOn: 0.5

    // What a button is printed with on the selected pad (a PlayStation pad's
    // Cross), else its position's name in the full layout
    function label(button) {
        const pad = controller ? controller.gamepad : null
        const at = { buttonA: "south", buttonB: "east", buttonX: "west", buttonY: "north" }
        if (pad && pad.labels && at[button] && pad.labels[at[button]])
            return pad.labels[at[button]]
        return button.replace("button", "")
    }

    function keyboardUsed() {
        inUse = false
        aiming = false
        if (controller && !controller.keyboardSelected) _select(-1)
    }
    function mouseUsed() { aiming = false }

    function _padUsed() {
        if (!enabled) return
        if (!aiming) {
            aiming = true
            aimAngle = game && game.player ? game.player.facingAngle : 0
        }
        inUse = true
        _aimLater()
    }

    // The pad at index of the hub, or the keyboard for -1
    property bool _selecting: false
    function _select(index) {
        _selecting = true
        if (index >= 0) controller.selectGamepad(index)
        else controller.selectKeyboard(keyboardKeys)
        _selecting = false
    }

    // Input that is not neutral, from a key press when _inKey
    property bool _inKey: false
    function _moved(value) {
        if (!_inKey && (value === true || (typeof value === "number" && Math.abs(value) > deadZone)))
            _padUsed()
    }

    // The right stick aims; at rest the left one does while the knight
    // walks. Once after a change, not per axis: a source writes x and y
    // one after the other, and a diagonal let go would aim along the axis
    // written last
    function _aimLater() { Qt.callLater(_aim) }
    function _aim() {
        if (!aiming || !controller || (game && game.talking)) return
        let c = controller
        if (Math.hypot(c.axisRightX, c.axisRightY) > deadZone)
            aimAngle = Math.atan2(c.axisRightY, c.axisRightX) * 180 / Math.PI
        else if (Math.hypot(c.axisX, c.axisY) > deadZone)
            aimAngle = Math.atan2(c.axisY, c.axisX) * 180 / Math.PI
    }

    // In the game, with no menu over it
    function _playing() {
        return !!game && !!game.player && game.screen === "game" && !game.menuOpen && !game.masterOpen
    }
    function _free() { return _playing() && !game.fallen && !game.talking }

    // The press of R1 or L1 that began a strike or a raised shield, ended
    // by its release wherever the game is by then
    property bool _striking: false
    property bool _shielding: false
    property bool _l2: false
    property bool _r2: false
    property int _wareStep: 0

    function _button(name, down) {
        if (!enabled) return
        if (name === "buttonR1") {
            if (down && _playing() && !game.talking) {
                game.strikePress()
                _striking = true
            } else if (!down && _striking) {
                _striking = false
                game.strikeRelease()
            }
            return
        }
        if (name === "buttonL1") {
            if (down && _playing() && !game.talking) {
                game.player.raiseShield()
                _shielding = true
            } else if (!down && _shielding) {
                _shielding = false
                if (game.player) game.player.lowerShield()
            }
            return
        }
        // Fallen, the face buttons are the fallen screen's
        if (!down || !_playing() || game.fallen) return
        let panel = dialogue
        if (name === "buttonA") {
            if (game.talking) panel.advance()
            else game.interact()
        } else if (name === "buttonX") {
            if (game.talking && panel.wares.length > 0) game.buyWare(panel.wares[panel.selected])
            else if (!game.talking) game.drinkPotion()
        } else if (name === "buttonY") {
            if (!game.talking) game.drinkDraught()
        } else if (name === "buttonSelect") {
            game.knightPanelOpen = !game.knightPanelOpen
        }
    }

    // The triggers press past triggerOn: R2 whirls, L2 locks on
    function _trigger(name, value) {
        let down = value > triggerOn
        if (name === "triggerR2") {
            if (down === _r2) return
            _r2 = down
            if (down && enabled && _free()) game.player.unleash()
        } else {
            if (down === _l2) return
            _l2 = down
            if (down && enabled && _playing()) game.toggleLock()
        }
    }

    // In a dialogue with wares the stick picks one, a push at a time
    function _pickWare() {
        if (!enabled || !game || !game.talking) return
        let panel = dialogue
        let step = controller.axisY > 0.5 ? -1 : controller.axisY < -0.5 ? 1 : 0
        if (step === _wareStep) return
        _wareStep = step
        if (step !== 0 && panel.wares.length > 0)
            panel.selected = Math.max(0, Math.min(panel.wares.length - 1, panel.selected + step))
    }

    Connections {
        target: knightPad.controller
        function onAxisXChanged() { knightPad._moved(knightPad.controller.axisX); knightPad._aimLater() }
        function onAxisYChanged() {
            knightPad._moved(knightPad.controller.axisY)
            knightPad._aimLater()
            knightPad._pickWare()
        }
        function onAxisRightXChanged() { knightPad._moved(knightPad.controller.axisRightX); knightPad._aimLater() }
        function onAxisRightYChanged() { knightPad._moved(knightPad.controller.axisRightY); knightPad._aimLater() }
        function onTriggerL2Changed() {
            knightPad._moved(knightPad.controller.triggerL2)
            knightPad._trigger("triggerL2", knightPad.controller.triggerL2)
        }
        function onTriggerR2Changed() {
            knightPad._moved(knightPad.controller.triggerR2)
            knightPad._trigger("triggerR2", knightPad.controller.triggerR2)
        }
        function onButtonAPressedChanged() { knightPad._pressed("buttonA") }
        function onButtonBPressedChanged() { knightPad._moved(knightPad.controller.buttonBPressed) }
        function onButtonXPressedChanged() { knightPad._pressed("buttonX") }
        function onButtonYPressedChanged() { knightPad._pressed("buttonY") }
        function onButtonL1PressedChanged() { knightPad._pressed("buttonL1") }
        function onButtonR1PressedChanged() { knightPad._pressed("buttonR1") }
        function onButtonSelectPressedChanged() { knightPad._pressed("buttonSelect") }
        // The selected pad was unplugged: the keyboard again
        function onGamepadSelectedChanged() {
            let c = knightPad.controller
            if (!knightPad._selecting && knightPad.enabled && !c.gamepadSelected
                    && !c.keyboardSelected && !c.vGamepadSelected) {
                knightPad.inUse = false
                knightPad.aiming = false
                knightPad._select(-1)
            }
        }
    }
    function _pressed(name) {
        let down = controller.inputValue(name)
        _moved(down)
        _button(name, down)
    }

    // A physical pad whose button or stick moves becomes the source
    Instantiator {
        model: GamepadHub.gamepads
        delegate: Connections {
            target: modelData
            function onValuesChanged() { knightPad._touched(index, modelData) }
        }
    }
    function _touched(index, pad) {
        if (!enabled || !controller || controller.gamepad === pad) return
        let v = pad.values
        for (let k in v) {
            let x = v[k]
            if (x === true || (typeof x === "number" && Math.abs(x) > triggerOn)) {
                _select(index)
                _padUsed()
                return
            }
        }
    }

    // First in the game's Keys.forwardTo: a key goes down, the keyboard is
    // the source again before the controller sees the key
    Keys.onPressed: (event) => {
        event.accepted = false
        if (event.isAutoRepeat) return
        keyboardUsed()
        _inKey = true
        Qt.callLater(() => knightPad._inKey = false)
    }
    Keys.onReleased: (event) => {
        event.accepted = false
        _inKey = true
        Qt.callLater(() => knightPad._inKey = false)
    }
}
