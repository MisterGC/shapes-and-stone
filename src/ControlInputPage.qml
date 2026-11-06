import QtQuick

// The Control Input page (issue #220), opened from the pause menu and the
// title, in the pause menu's look: at the top the devices there are -
// Keyboard, Mouse and each connected gamepad by name - the one in use
// marked; below every action of the game's ControlTable with its key or
// mouse button and its pad input side by side, then a Reset under each
// column and Back. W/S or the arrows pick a row, A/D or the arrows a
// column, Enter or Space chooses, Esc goes back; a gamepad does the same
// with its stick or D-pad, A, and B or Start (MenuPad); the mouse picks by
// hovering and chooses with a click. Takes the keyboard focus and every
// click; the mute key (M) still reaches the game and mutes.
//
// Rebinding (issue #221): chosen, an action's cell waits for the next
// input - in the mouse and keyboard column a key or a mouse button, in the
// gamepad column a pad button - and is rebound to it (ControlTable.rebind):
// one another action has trades cells with it. Esc or the pad's B cancels,
// and so does an input of the other column's device. The pad coming into
// use - its first press on the page - and a pad press that cancels put the
// pick on the gamepad's column; that first press chooses nothing. The
// menu, the aim and the pad's moves stay fixed, so nobody locks themselves
// out of the menu. A Reset puts its column's defaults back. Every change
// is kept at once.
//
// A browser lists a gamepad only once one of its buttons was pressed on
// the page, and Firefox lists a Switch pad it misreads, on macOS and
// Windows, with no input at all (clayground#474): the device row says so.
Item {
    id: page
    objectName: "controlInputPage"

    signal closed()
    // A key went down on the page: the keyboard is in use again, as a key
    // makes it in the game (KnightPad.keyboardUsed), which under a menu
    // sees no key
    signal keyUsed()

    // The game's ControlTable
    property var controls: null
    // In a session: the world runs on under the page
    property bool inSession: false
    // A pad in use (Game.padInUse): the hint names its buttons, as printed
    // on it (Game.padLabels), and the pad drives instead of the mouse and
    // keyboard
    property bool pad: false
    property var padLabels: ({ A: "A", B: "B", X: "X", Y: "Y" })
    // What a pad input is printed with on the selected pad (KnightPad.label)
    property var padLabel: null
    // The connected pads (GameController.gamepads) and the selected one
    // (GameController.gamepad), null for none
    property var gamepads: []
    property var gamepad: null
    // The key that mutes, in the game's control table
    property int muteKey: Qt.Key_M

    readonly property var actions: controls ? controls.actions : []
    // The rows: every action, the Resets, then Back
    readonly property int resetIndex: actions.length
    readonly property int backIndex: actions.length + 1
    property int selectedIndex: 0
    // The column picked, 0 the mouse and keyboard, 1 the gamepad: at first
    // the one of the device in use
    property int column: 0
    readonly property var columns: ["keys", "pad"]

    // Waiting for the input that rebinds captureAction's cell in the
    // column capturing ("keys" or "pad"), "" while not
    property string capturing: ""
    property string captureAction: ""
    // Only an input pressed after the one that chose counts
    property bool _armed: false
    // The press that ended a wait is not the menu's as well (MenuPad)
    property bool _settling: false
    // What the last choice did, until the next one: a pick by hovering
    // follows the mouse resting where a wait ended, and must not hide it
    property string note: ""

    // Keyboard, Mouse and each pad: name, what it is, whether it is in use
    readonly property var devices: {
        let list = [{ name: "Keyboard", kind: "keyboard", inUse: !pad },
                    { name: "Mouse", kind: "mouse", inUse: !pad }]
        for (let i = 0; i < gamepads.length; i++) {
            const p = gamepads[i]
            list.push({ name: p.type === "unsupported" ? p.name + " - no input in this browser" : p.name,
                        kind: "gamepad", inUse: pad && p === gamepad })
        }
        return list
    }

    // What action is bound to, as the rows show it; "-" for nothing
    function keysText(action) {
        const t = controls ? controls.keysBindingName(action) : ""
        return t !== "" ? t : "-"
    }
    function padText(action) {
        const t = controls ? controls.padBindingName(action, padLabel) : ""
        return t !== "" ? t : "-"
    }
    function titleOf(action) {
        const a = actions.find(x => x.id === action)
        return a ? a.title : action
    }
    // Whether the cell in row index and column col stays as it is
    function isFixed(index, col) {
        return index < actions.length && !!controls && controls.fixed(actions[index].id, columns[col])
    }
    // Whether action is one of the moves, which take a key alone
    function isMove(action) { return !!controls && controls.isMove(action) }
    // What the page says of a cell that stays as it is
    // (ControlTable.fixedReason)
    function _fixedNote(action, col) {
        const why = controls.fixedReason(action, columns[col])
        if (why === "menu")
            return "The menu stays on " + keysText("menu") + " and " + padText("menu") + ", so it always opens"
        if (why === "pointer") return "The aim stays on the mouse and the right stick"
        if (why === "stick") return "The moves stay on the left stick and the D-pad"
        return titleOf(action) + " stays as it is"
    }
    // What an input is called: a key, a mouse button, a pad input
    function inputName(input) {
        if (typeof input === "string") return controls.padName(input, padLabel)
        return input.key ? controls.keyName(input.key) : controls.mouseName(input.mouse)
    }

    function close() { closed() }
    function pick(index) {
        selectedIndex = Math.max(0, Math.min(backIndex, index))
        if (selectedIndex < actions.length) rows.positionViewAtIndex(selectedIndex, ListView.Contain)
    }
    function pickColumn(col) {
        column = Math.max(0, Math.min(1, col))
    }
    function choose(index) {
        if (index === backIndex) {
            close()
        } else if (index === resetIndex) {
            controls.resetColumn(columns[column])
            note = column === 1 ? "The gamepad's defaults are back" : "The mouse and keyboard's defaults are back"
        } else if (isFixed(index, column)) {
            note = _fixedNote(actions[index].id, column)
        } else {
            _capture(actions[index].id, columns[column])
        }
    }

    // The cell waits for the next input
    function _capture(action, which) {
        note = ""
        captureAction = action
        capturing = which
        _armed = false
        Qt.callLater(() => page._armed = page.capturing !== "")
    }
    function _endCapture(text) {
        capturing = ""
        captureAction = ""
        _armed = false
        note = text
        _settling = true
        Qt.callLater(() => page._settling = false)
    }
    function cancelCapture() {
        if (capturing !== "") _endCapture(titleOf(captureAction) + " kept as it was")
    }
    // input: { key }, { mouse } or a pad input
    function _take(input) {
        const action = captureAction
        const r = controls.rebind(action, capturing, input)
        if (r.taken) {
            _endCapture(r.swapped !== "" ? titleOf(action) + " swapped with " + titleOf(r.swapped) : "")
            return
        }
        // Why not, as ControlTable.rebind says it
        const name = inputName(input)
        if (r.reason === "keyOnly")
            _endCapture(titleOf(action) + " takes a key, not a mouse button")
        else if (r.reason === "held")
            _endCapture(name + " stays with " + titleOf(r.holder))
        else if (r.reason === "fixed")
            _endCapture(_fixedNote(action, columns.indexOf(capturing)))
        else
            _endCapture(titleOf(action) + " cannot take " + (name !== "" ? name : "that"))
    }
    // A pad input pressed (KnightPad.inputPressed): while a cell waits, the
    // gamepad's binding; B, the menu's input or any while the mouse and
    // keyboard's cell waits cancel
    // A pad press that cancels the mouse and keyboard's cell puts the pick
    // on the gamepad's column, so its next A waits on a pad cell
    function padInput(name) {
        if (capturing === "" || !_armed) return
        const keysCell = capturing === "keys"
        if (name === "buttonB" || name === controls.pad("menu") || keysCell) {
            cancelCapture()
            if (keysCell) pickColumn(1)
        } else {
            _take(name)
        }
    }

    // The pad comes into use on the page: the pick goes to its column. On
    // the title that is the pad's first press - in the browser the one that
    // lists it (issue #236). A pick on a Reset or Back, where a click left
    // the resting mouse, goes up to the first action whose pad cell can be
    // rebound, so the pad's next A picks a cell and resets nothing
    onPadChanged: {
        if (!pad || capturing !== "") return
        pickColumn(1)
        if (selectedIndex >= actions.length) {
            const first = actions.findIndex((a, i) => !isFixed(i, 1))
            pick(first >= 0 ? first : 0)
        }
    }
    // A press on a pad is making it the controller's source
    // (KnightPad.takingPad): that press only takes the pad. It does not
    // choose the cell or the Reset of the mouse and keyboard column picked
    // before, by the keys or by the resting mouse
    property bool padTaking: false

    // The gamepad (MenuPad): the stick picks a row and a column, A
    // chooses, B and Start go back. While a cell waits its presses are
    // padInput's
    function padMove(dx, dy) {
        if (capturing !== "" || _settling || padTaking) return
        note = ""
        if (dy !== 0) pick(selectedIndex - dy)
        else if (dx !== 0) pickColumn(column + dx)
    }
    function padConfirm() { if (capturing === "" && !_settling && !padTaking) choose(selectedIndex) }
    function padBack() { if (capturing === "" && !_settling && !padTaking) close() }

    // The console says what the page shows: the devices with the ones in
    // use, and the prompt and the hint under the table. The browser build has nothing
    // else to tell a bench (tests/browserpad) what the page did
    function _logDevices() {
        console.info("[ControlInputPage] devices:", devices.map(d => d.name + (d.inUse ? " (in use)" : "")).join(", "))
    }
    onDevicesChanged: _logDevices()

    // Deferred like the pause menu's: the menu under it may still hold the
    // focus in the same frame
    Component.onCompleted: {
        column = pad ? 1 : 0
        _logDevices()
        Qt.callLater(forceActiveFocus)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: page.forceActiveFocus()
        onWheel: (wheel) => { wheel.accepted = true }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: page.inSession ? 0.35 : 0.6
    }

    Column {
        id: body
        anchors.centerIn: parent
        spacing: 10

        Text {
            objectName: "controlInputTitle"
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Control Input"
            color: "#DDDDDD"
            font.pixelSize: 36
            font.bold: true
            font.letterSpacing: 2
        }

        // The devices, the ones in use marked; with no pad the way to get
        // one listed
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Repeater {
                model: page.devices
                delegate: Rectangle {
                    id: chip
                    objectName: "controlDevice" + index
                    readonly property string deviceName: modelData.name
                    readonly property string kind: modelData.kind
                    readonly property bool inUse: modelData.inUse
                    width: Math.min(chipText.implicitWidth, 272) + 28; height: 32; radius: 6
                    color: inUse ? "#4A4A52" : "#2A2A30"
                    border.color: inUse ? "#E0B060" : "#555555"
                    border.width: inUse ? 2 : 1
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, 272)
                        elide: Text.ElideRight
                        text: chip.deviceName + (chip.inUse ? "  •  in use" : "")
                        color: chip.inUse ? "#FFFFFF" : "#999999"
                        font.pixelSize: 14
                        font.bold: chip.inUse
                    }
                }
            }
            Text {
                objectName: "controlNoPad"
                visible: page.gamepads.length === 0
                height: 32
                leftPadding: 6
                verticalAlignment: Text.AlignVCenter
                text: "No gamepad - connect one and press any of its buttons"
                color: "#888888"
                font.pixelSize: 13
                font.italic: true
            }
        }

        // The table: what each column binds
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            Repeater {
                model: [["Action", 220], ["Mouse and keyboard", 190], ["Gamepad", 210]]
                delegate: Text {
                    width: modelData[1]; height: 18
                    leftPadding: 14
                    text: modelData[0]
                    color: "#888888"
                    font.pixelSize: 12
                    font.bold: true
                    font.letterSpacing: 1
                }
            }
        }

        ListView {
            id: rows
            objectName: "controlRows"
            anchors.horizontalCenter: parent.horizontalCenter
            width: 620
            height: Math.max(58, Math.min(contentHeight, page.height - 290))
            spacing: 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: page.actions
            delegate: Rectangle {
                id: row
                objectName: "controlRow" + modelData.id
                readonly property int rowIndex: index
                readonly property string action: modelData.id
                readonly property string title: modelData.title
                readonly property string keysText: page.keysText(modelData.id)
                readonly property string padText: page.padText(modelData.id)
                readonly property bool isCurrent: page.selectedIndex === index
                width: rows.width; height: 28; radius: 6
                color: isCurrent ? "#4A4A52" : "#2A2A30"
                border.color: isCurrent ? "#AAAAAA" : "#555555"
                border.width: isCurrent ? 2 : 1
                Row {
                    anchors.fill: parent
                    Repeater {
                        // The title, then a cell per column
                        model: [[row.title, 220, -1], [row.keysText, 190, 0], [row.padText, 210, 1]]
                        delegate: Item {
                            id: cell
                            objectName: modelData[2] < 0 ? "" : "controlCell" + row.action + page.columns[modelData[2]]
                            readonly property int col: modelData[2]
                            readonly property bool picked: row.isCurrent && col === page.column
                            readonly property bool waiting: col >= 0 && page.capturing === page.columns[col]
                                                            && page.captureAction === row.action
                            readonly property bool fixed: col >= 0 && page.isFixed(row.rowIndex, col)
                            width: modelData[1]; height: row.height
                            // The cell picked, and the one waiting
                            Rectangle {
                                visible: cell.col >= 0 && (cell.picked || cell.waiting)
                                anchors.fill: parent
                                anchors.margins: 3
                                radius: 4
                                color: cell.waiting ? "#3A3428" : "#5A5A64"
                                border.color: cell.waiting ? "#E0B060" : "#CCCCCC"
                                border.width: 1
                            }
                            Text {
                                anchors.fill: parent
                                leftPadding: 14
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                text: cell.waiting ? "Press…" : modelData[0]
                                color: cell.waiting ? "#E0B060"
                                     : modelData[0] === "-" ? "#666666"
                                     : cell.fixed ? "#777777"
                                     : row.isCurrent ? "#FFFFFF" : cell.col < 0 ? "#BBBBBB" : "#999999"
                                font.pixelSize: 14
                                font.bold: (row.isCurrent && cell.col < 0) || cell.waiting
                                font.italic: cell.fixed
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: cell.col >= 0 && !cell.fixed ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onEntered: {
                                    if (page.capturing !== "") return
                                    if (page.selectedIndex !== row.rowIndex) page.pick(row.rowIndex)
                                    if (cell.col >= 0 && page.column !== cell.col) page.pickColumn(cell.col)
                                }
                                onClicked: if (cell.col >= 0) page.choose(row.rowIndex)
                            }
                        }
                    }
                }
            }
        }

        // A Reset under each column
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            Item { width: 220; height: 32 }
            Repeater {
                model: [["controlResetKeys", 190], ["controlResetPad", 210]]
                delegate: Item {
                    width: modelData[1]; height: 32
                    Rectangle {
                        id: reset
                        objectName: modelData[0]
                        readonly property bool isCurrent: page.selectedIndex === page.resetIndex && page.column === index
                        anchors.fill: parent
                        anchors.leftMargin: 3
                        anchors.rightMargin: 3
                        radius: 6
                        color: isCurrent ? "#4A4A52" : "#2A2A30"
                        border.color: isCurrent ? "#AAAAAA" : "#555555"
                        border.width: isCurrent ? 2 : 1
                        Text {
                            anchors.centerIn: parent
                            text: "Reset to defaults"
                            color: reset.isCurrent ? "#FFFFFF" : "#999999"
                            font.pixelSize: 13
                            font.bold: reset.isCurrent
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: {
                                page.pick(page.resetIndex)
                                page.pickColumn(index)
                            }
                            onClicked: page.choose(page.resetIndex)
                        }
                    }
                }
            }
        }

        Rectangle {
            id: back
            objectName: "controlBack"
            anchors.horizontalCenter: parent.horizontalCenter
            width: 220; height: 44; radius: 6
            readonly property bool isCurrent: page.selectedIndex === page.backIndex
            color: isCurrent ? "#4A4A52" : "#2A2A30"
            border.color: isCurrent ? "#AAAAAA" : "#555555"
            border.width: isCurrent ? 2 : 1
            Text {
                anchors.centerIn: parent
                text: "Back"
                color: back.isCurrent ? "#FFFFFF" : "#999999"
                font.pixelSize: 16
                font.bold: back.isCurrent
                font.letterSpacing: 1
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: page.pick(page.backIndex)
                onClicked: page.close()
            }
        }

        // While a cell waits what it takes, else what the last choice did
        Text {
            objectName: "controlPrompt"
            anchors.horizontalCenter: parent.horizontalCenter
            height: 18
            text: page.capturing === "keys"
                  ? (page.isMove(page.captureAction) ? "Press a key for " : "Press a key or mouse button for ")
                    + page.titleOf(page.captureAction)
                  : page.capturing === "pad" ? "Press a gamepad button for " + page.titleOf(page.captureAction)
                  : page.note
            color: "#E0B060"
            font.pixelSize: 14
            onTextChanged: if (text !== "") console.info("[ControlInputPage] prompt:", text)
        }

        Text {
            objectName: "controlHint"
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.capturing !== ""
                  ? (page.pad ? page.padLabels.B + " or Esc to cancel" : "Esc or the gamepad's " + page.padLabels.B + " to cancel")
                  : page.pad
                  ? "Stick to pick • " + page.padLabels.A + " to rebind • " + page.padLabels.B + " or Start to go back"
                  : "W/S and A/D to pick • Enter or a click to rebind • Esc to go back"
            color: "#888888"
            font.pixelSize: 12
            font.italic: true
            onTextChanged: console.info("[ControlInputPage] hint:", text)
        }
    }

    // While a cell waits, a mouse button pressed anywhere is its input.
    // It takes no hover: the cell under a resting mouse stays hovered, and
    // is not entered again, picking itself, once the wait ends
    MouseArea {
        objectName: "controlCapture"
        anchors.fill: parent
        enabled: page.capturing !== ""
        acceptedButtons: Qt.AllButtons
        onPressed: (mouse) => {
            page.forceActiveFocus()
            if (!page._armed) return
            if (page.capturing === "pad") page.cancelCapture()
            else page._take({ mouse: mouse.button })
        }
        onWheel: (wheel) => { wheel.accepted = true }
    }

    Keys.onPressed: (event) => {
        if (!event.isAutoRepeat) keyUsed()
        // While a cell waits every key is its: Esc, the menu's key or any
        // while the gamepad's cell waits cancel, others are the binding
        if (capturing !== "") {
            event.accepted = true
            if (event.isAutoRepeat || !_armed) return
            if (event.key === Qt.Key_Escape || event.key === controls.key("menu") || capturing === "pad")
                cancelCapture()
            else if (event.key !== 0 && event.key !== Qt.Key_unknown)
                _take({ key: event.key })
            return
        }
        // The mute key goes on to the game and mutes; no other key reaches
        // the knight
        if (event.key === muteKey) return
        event.accepted = true
        if (!event.isAutoRepeat) note = ""
        if (event.key === Qt.Key_W || event.key === Qt.Key_Up) {
            pick(selectedIndex - 1)
        } else if (event.key === Qt.Key_S || event.key === Qt.Key_Down) {
            pick(selectedIndex + 1)
        } else if (event.key === Qt.Key_A || event.key === Qt.Key_Left) {
            pickColumn(column - 1)
        } else if (event.key === Qt.Key_D || event.key === Qt.Key_Right) {
            pickColumn(column + 1)
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                   || event.key === Qt.Key_Space) {
            if (!event.isAutoRepeat) choose(selectedIndex)
        } else if (event.key === Qt.Key_Escape) {
            close()
        }
    }
    // Releases stay here too: the game's controller must not see half a key
    Keys.onReleased: (event) => { if (event.key !== muteKey || capturing !== "") event.accepted = true }
}
