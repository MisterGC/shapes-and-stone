import QtQuick
import QtQml
import Clayground.GameController

// The knight on a gamepad (issue #200): the game's controller in its full
// layout - the left stick moves (Game.knightMoveX), the right stick aims and
// each button or trigger does the action it is bound to in the game's
// ControlTable (issue #218): R1 strikes as the left mouse button does, L1
// raises the shield, B dashes and so on by default. The pad is in use from
// its first input to the next key press, and its aim from its first input
// to the next move of the mouse; the hints name its buttons meanwhile. A
// physical pad is taken as the controller's source when one of its buttons
// or sticks moves, the keyboard again when a key goes down.
Item {
    id: knightPad

    property var controller: null
    property var game: null
    // The game's dialogue panel: A goes on, the stick picks a ware, X buys it
    property var dialogue: null
    // The game's ControlTable: which action each pad input does, and the
    // keys the keyboard walks with
    property var controls: null

    // The keyboard's part of the controller: the four keys of the moves.
    // Every other key is the game's key handler's
    readonly property var keyboardKeys: controls
        ? ({ axisX: [controls.key("moveLeft"), controls.key("moveRight")],
             axisY: [controls.key("moveDown"), controls.key("moveUp")] })
        : ({ axisX: [Qt.Key_A, Qt.Key_D], axisY: [Qt.Key_S, Qt.Key_W] })

    // A pad drives the knight: the hints name its buttons
    property bool inUse: false
    // The pad aims, at aimAngle degrees up from the right, until the mouse
    // moves
    property bool aiming: false
    property real aimAngle: 0
    // A stick past this far counts, a trigger past triggerOn is pressed
    property real deadZone: 0.3
    property real triggerOn: 0.5

    // What a button or trigger is printed with on the selected pad (a
    // PlayStation pad's Cross), else its position's name in the full
    // layout: "A", "R1", "R2", "Select"
    function label(button) {
        const pad = controller ? controller.gamepad : null
        const at = { buttonA: "south", buttonB: "east", buttonX: "west", buttonY: "north" }
        if (pad && pad.labels && at[button] && pad.labels[at[button]])
            return pad.labels[at[button]]
        return button.replace(/^(button|trigger)/, "")
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

    // In the game, with no menu, title or fallen screen over it: those own
    // the pad then (MenuPad, issue #201)
    function _playing() {
        return !!game && !!game.player && !game.overlayUp && !game.masterOpen
    }
    function _free() { return _playing() && !game.talking }

    // The press that began a strike or a raised shield, ended by its
    // release wherever the game is by then
    property bool _striking: false
    property bool _shielding: false
    property int _wareStep: 0

    // Each pad input as last seen pressed: a trigger is pressed past
    // triggerOn
    property var _down: ({})

    // A button or trigger was pressed, as GameController.inputs names it:
    // the Control Input page rebinds a pad cell to it (issue #221)
    signal inputPressed(string name)

    // A button or trigger changed: on its press or release, the action it
    // is bound to. Not for a change a key made (the keyboard's moves). A
    // press while the Control Input page waits for one (Game.rebinding) is
    // the page's alone
    function _input(name) {
        let value = controller.inputValue(name)
        _moved(value)
        let down = typeof value === "number" ? value > triggerOn : !!value
        if (!!_down[name] === down) return
        _down[name] = down
        if (_inKey || !controls) return
        const rebinding = !!game && !!game.rebinding
        if (down && enabled) inputPressed(name)
        if (down && rebinding) return
        let action = controls.actionOfPad(name)
        if (action !== "") _act(action, down)
    }

    // A press that closed a menu, the title or the fallen screen (MenuPad's
    // A, B or Start) is theirs: the game, playing again from that moment,
    // does not act on it too
    readonly property bool _overlay: !!game && (game.overlayUp || game.masterOpen)
    property bool _overlayLeft: false
    on_OverlayChanged: if (!_overlay) {
        _overlayLeft = true
        Qt.callLater(() => knightPad._overlayLeft = false)
    }

    function _act(action, down) {
        if (!enabled || (down && _overlayLeft)) return
        if (action === "strike") {
            if (down && _free()) {
                game.strikePress()
                _striking = true
            } else if (!down && _striking) {
                _striking = false
                game.strikeRelease()
            }
            return
        }
        if (action === "shield") {
            if (down && _free()) {
                game.player.raiseShield()
                _shielding = true
            } else if (!down && _shielding) {
                _shielding = false
                if (game.player) game.player.lowerShield()
            }
            return
        }
        if (!down) return
        // Mute and the effects anywhere; the menu is MenuPad's Start
        if (action === "mute") { game.muted = !game.muted; return }
        if (action === "effects") { game.fx = !game.fx; return }
        if (!_playing()) return
        let panel = dialogue
        if (action === "dash") {
            // In a dialogue it closes it, as Esc does
            if (!game.talking) game.player.dash()
            else if (inUse) panel.close()
        } else if (action === "talk") {
            if (game.talking) panel.advance()
            else game.interact()
        } else if (action === "potion") {
            // In a dialogue with wares it buys the one the stick picked
            if (game.talking && panel.wares.length > 0) game.buyWare(panel.wares[panel.selected])
            else if (!game.talking) game.drinkPotion()
        } else if (action === "draught") {
            if (!game.talking) game.drinkDraught()
        } else if (action === "whirlwind") {
            if (!game.talking) game.player.unleash()
        } else if (action === "lock") {
            game.toggleLock()
        } else if (action === "knight") {
            game.knightPanelOpen = !game.knightPanelOpen
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
        function onTriggerL2Changed() { knightPad._input("triggerL2") }
        function onTriggerR2Changed() { knightPad._input("triggerR2") }
        function onButtonAPressedChanged() { knightPad._input("buttonA") }
        function onButtonBPressedChanged() { knightPad._input("buttonB") }
        function onButtonXPressedChanged() { knightPad._input("buttonX") }
        function onButtonYPressedChanged() { knightPad._input("buttonY") }
        function onButtonL1PressedChanged() { knightPad._input("buttonL1") }
        function onButtonR1PressedChanged() { knightPad._input("buttonR1") }
        function onButtonStartPressedChanged() { knightPad._input("buttonStart") }
        function onButtonSelectPressedChanged() { knightPad._input("buttonSelect") }
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
