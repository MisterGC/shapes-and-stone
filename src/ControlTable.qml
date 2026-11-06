import QtQuick

// Every control of the knight in one table (issue #218): per action the key
// and the mouse button of the mouse and keyboard, and the input of the
// gamepad, as GameController.inputs names it. The game's key handler and
// MouseArea, KnightPad, MenuPad's Start, the swing's InputAction and every
// controls hint read it; nothing else binds a control of the knight.
//
// The defaults are the game's controls before the table. The player's own
// table is kept in store under "controls", as JSON with every action: an
// action or a field missing there, or not valid, has its default.
//
// The moves and the aim are the controller's sticks on a gamepad: their pad
// inputs name them for the hints and are not rebound here, as the pad's
// sticks reach the game through GameController's axes only.
QtObject {
    id: table

    // Where the player's table is kept: a KeyValueStore
    property var store: null
    readonly property string storeKey: "controls"

    // The actions in the order the hints name them. name: what the hint
    // says; hold: pressed and released, not only pressed; move: one of the
    // four the keyboard walks with; pointer: aimed with the mouse pointer
    readonly property var actions: [
        { id: "moveUp", name: "move", move: true },
        { id: "moveLeft", name: "move", move: true },
        { id: "moveDown", name: "move", move: true },
        { id: "moveRight", name: "move", move: true },
        { id: "aim", name: "aim", pointer: true },
        { id: "strike", name: "strike, hold to charge, at a vein dig", hold: true },
        { id: "shield", name: "shield", hold: true },
        { id: "dash", name: "dash" },
        { id: "whirlwind", name: "whirlwind" },
        { id: "talk", name: "talk" },
        { id: "potion", name: "potion" },
        { id: "draught", name: "draught" },
        { id: "lock", name: "lock on" },
        { id: "knight", name: "knight" },
        { id: "mute", name: "mute" },
        { id: "effects", name: "effects" },
        { id: "menu", name: "menu" }
    ]

    // key: a Qt.Key, 0 for none; mouse: a Qt mouse button, 0 for none;
    // pad: a GameController input, "" for none. The moves' pad inputs are
    // an axis and its direction, the aim's the right stick
    readonly property var defaults: ({
        moveUp: { key: Qt.Key_W, mouse: 0, pad: "axisY+" },
        moveLeft: { key: Qt.Key_A, mouse: 0, pad: "axisX-" },
        moveDown: { key: Qt.Key_S, mouse: 0, pad: "axisY-" },
        moveRight: { key: Qt.Key_D, mouse: 0, pad: "axisX+" },
        aim: { key: 0, mouse: 0, pad: "axisRight" },
        strike: { key: 0, mouse: Qt.LeftButton, pad: "buttonR1" },
        shield: { key: 0, mouse: Qt.RightButton, pad: "buttonL1" },
        dash: { key: Qt.Key_Space, mouse: 0, pad: "buttonB" },
        whirlwind: { key: Qt.Key_Q, mouse: 0, pad: "triggerR2" },
        talk: { key: Qt.Key_E, mouse: 0, pad: "buttonA" },
        potion: { key: Qt.Key_1, mouse: 0, pad: "buttonX" },
        draught: { key: Qt.Key_2, mouse: 0, pad: "buttonY" },
        lock: { key: Qt.Key_F, mouse: Qt.MiddleButton, pad: "triggerL2" },
        knight: { key: Qt.Key_C, mouse: 0, pad: "buttonSelect" },
        mute: { key: Qt.Key_M, mouse: 0, pad: "" },
        effects: { key: Qt.Key_V, mouse: 0, pad: "" },
        menu: { key: Qt.Key_Escape, mouse: 0, pad: "buttonStart" }
    })

    // The table in use, action id -> { key, mouse, pad }. Replaced as a
    // whole on every change, so a binding that reads it follows
    property var bindings: defaults

    // The mouse buttons the game's MouseArea takes for an action
    readonly property int bindableMouseButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                                | Qt.BackButton | Qt.ForwardButton
    // The pad inputs a button-like action takes: the buttons and triggers
    // of the full layout
    readonly property var bindablePadInputs: ["buttonA", "buttonB", "buttonX", "buttonY",
                                              "buttonL1", "buttonR1", "triggerL2", "triggerR2",
                                              "buttonStart", "buttonSelect"]

    function key(action) { return bindings[action] ? bindings[action].key : 0 }
    function mouse(action) { return bindings[action] ? bindings[action].mouse : 0 }
    function pad(action) { return bindings[action] ? bindings[action].pad : "" }

    // The action a key, a mouse button or a pad input is bound to, "" for
    // none
    function actionOfKey(k) { return _find(b => k !== 0 && b.key === k) }
    function actionOfMouse(button) { return _find(b => button !== 0 && b.mouse === button) }
    function actionOfPad(input) { return _find(b => input !== "" && b.pad === input) }
    function _find(match) {
        for (const a of actions)
            if (bindings[a.id] && match(bindings[a.id])) return a.id
        return ""
    }

    // Binds action's key, mouse or pad (which) to value, keeps the table
    // and returns whether it took it
    function bind(action, which, value) {
        if (!defaults[action] || !_valid(action, which, value)) return false
        let next = JSON.parse(JSON.stringify(bindings))
        next[action][which] = value
        bindings = next
        save()
        return true
    }
    // Every action back to its default, kept
    function reset() {
        bindings = defaults
        save()
    }

    function _valid(action, which, value) {
        if (which === "key") return typeof value === "number" && value >= 0 && Math.floor(value) === value
        if (which === "mouse")
            return typeof value === "number" && (value === 0 || (value & bindableMouseButtons) === value
                                                 && (value & (value - 1)) === 0)
        if (which === "pad") {
            if (typeof value !== "string") return false
            // The sticks are the controller's: a move or the aim keeps its own
            if (table._fixedPad(action)) return value === defaults[action].pad
            return value === "" || bindablePadInputs.indexOf(value) !== -1
        }
        return false
    }
    function _fixedPad(action) {
        const a = actions.find(x => x.id === action)
        return !!a && (!!a.move || !!a.pointer)
    }

    // The table from text kept by save(): what is missing or not valid has
    // its default
    function fromJson(text) {
        let kept = null
        try { kept = JSON.parse(text) } catch (err) { kept = null }
        let next = JSON.parse(JSON.stringify(defaults))
        if (kept && typeof kept === "object") {
            for (const a in next) {
                const row = kept[a]
                if (!row || typeof row !== "object") continue
                for (const which of ["key", "mouse", "pad"])
                    if (row[which] !== undefined && _valid(a, which, row[which])) next[a][which] = row[which]
            }
        }
        return next
    }
    function toJson() { return JSON.stringify(bindings) }

    // The player's table from the store, or the defaults with nothing kept
    function load() {
        bindings = store ? fromJson(store.get(storeKey, "")) : defaults
    }
    function save() {
        if (store) store.set(storeKey, toJson())
    }

    // What a key or mouse button is called in the hints
    function keyName(k) {
        if (k === 0) return ""
        const named = {}
        named[Qt.Key_Space] = "Space"
        named[Qt.Key_Escape] = "Esc"
        named[Qt.Key_Tab] = "Tab"
        named[Qt.Key_Backspace] = "Backspace"
        named[Qt.Key_Return] = "Enter"
        named[Qt.Key_Enter] = "Enter"
        named[Qt.Key_Insert] = "Ins"
        named[Qt.Key_Delete] = "Del"
        named[Qt.Key_Home] = "Home"
        named[Qt.Key_End] = "End"
        named[Qt.Key_PageUp] = "PgUp"
        named[Qt.Key_PageDown] = "PgDn"
        named[Qt.Key_Left] = "Left"
        named[Qt.Key_Up] = "Up"
        named[Qt.Key_Right] = "Right"
        named[Qt.Key_Down] = "Down"
        named[Qt.Key_Shift] = "Shift"
        named[Qt.Key_Control] = "Ctrl"
        named[Qt.Key_Meta] = "Meta"
        named[Qt.Key_Alt] = "Alt"
        named[Qt.Key_CapsLock] = "Caps"
        if (named[k]) return named[k]
        if (k >= Qt.Key_F1 && k <= Qt.Key_F35) return "F" + (k - Qt.Key_F1 + 1)
        if (k > 0x20 && k < 0x7f) return String.fromCharCode(k)
        return "Key " + k.toString(16)
    }
    function mouseName(button) {
        if (button === Qt.LeftButton) return "LMB"
        if (button === Qt.RightButton) return "RMB"
        if (button === Qt.MiddleButton) return "MMB"
        if (button === Qt.BackButton) return "Mouse 4"
        if (button === Qt.ForwardButton) return "Mouse 5"
        return ""
    }
    // A pad input as the hints call it; padLabel names a button as printed
    // on the pad (KnightPad.label)
    function padName(input, padLabel) {
        if (input === "") return ""
        if (input === "axisRight") return "R stick"
        if (input.startsWith("axis")) return "L stick"
        return padLabel ? padLabel(input) : input.replace(/^(button|trigger)/, "")
    }

    // What action is bound to on the mouse and keyboard: its key and mouse
    // button, "F/MMB"; the four moves as one, "WASD"
    function keysName(action) {
        if (action === "move") {
            const names = ["moveUp", "moveLeft", "moveDown", "moveRight"].map(a => keyName(key(a)))
            return names.every(n => n.length === 1) ? names.join("") : names.join("/")
        }
        const a = actions.find(x => x.id === action)
        if (a && a.pointer) return "Mouse"
        return [keyName(key(action)), mouseName(mouse(action))].filter(n => n !== "").join("/")
    }
    // What action is bound to on the pad, else on the keyboard
    function padOrKeysName(action, padLabel) {
        const p = padName(pad(action === "move" ? "moveUp" : action), padLabel)
        return p !== "" ? p : keysName(action)
    }
    // What action is bound to on the device in use: the pad's while one is
    // in use (onPad)
    function name(action, onPad, padLabel) {
        return onPad ? padOrKeysName(action, padLabel) : keysName(action)
    }

    // The controls hint: every action with what it is bound to on the
    // device in use, the four moves as one, each item whole on its line
    function hint(onPad, padLabel) {
        let items = []
        for (const a of actions) {
            if (a.move && a.id !== "moveUp") continue
            const id = a.move ? "move" : a.id
            const bound = name(id, onPad, padLabel)
            if (bound !== "") items.push(bound + " " + a.name)
        }
        return items.map(t => t.replace(/ /g, " ")).join("  •  ")
    }
}
