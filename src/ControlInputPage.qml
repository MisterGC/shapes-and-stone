import QtQuick

// The Control Input page (issue #220), opened from the pause menu and the
// title, in the pause menu's look: at the top the devices there are -
// Keyboard, Mouse and each connected gamepad by name - the one in use
// marked; below every action of the game's ControlTable with its key or
// mouse button and its pad input side by side. W/S or the arrows pick a
// row, Enter or Space on Back and Esc go back; a gamepad does the same
// with its stick or D-pad, A, and B or Start (MenuPad); the mouse picks by
// hovering and goes back with a click on Back. Takes the keyboard focus
// and every click; the mute key (M) still reaches the game and mutes.
//
// A browser lists a gamepad only once one of its buttons was pressed on
// the page, and Firefox lists a pad with no input at all (clayground#474):
// the device row says so.
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
    // The rows: every action, then Back
    readonly property int backIndex: actions.length
    property int selectedIndex: 0

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

    function close() { closed() }
    function pick(index) {
        selectedIndex = Math.max(0, Math.min(backIndex, index))
        if (selectedIndex < backIndex) rows.positionViewAtIndex(selectedIndex, ListView.Contain)
    }
    function choose(index) { if (index === backIndex) close() }
    // The gamepad (MenuPad): up and down pick, A on Back, B and Start go
    // back
    function padMove(dx, dy) { if (dy !== 0) pick(selectedIndex - dy) }
    function padConfirm() { choose(selectedIndex) }
    function padBack() { close() }

    // Deferred like the pause menu's: the menu under it may still hold the
    // focus in the same frame
    Component.onCompleted: Qt.callLater(forceActiveFocus)

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
        id: column
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
                        text: chip.deviceName + (chip.inUse ? "  \u2022  in use" : "")
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
            height: Math.max(58, Math.min(contentHeight, page.height - 250))
            spacing: 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: page.actions
            delegate: Rectangle {
                id: row
                objectName: "controlRow" + modelData.id
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
                        model: [[row.title, 220], [row.keysText, 190], [row.padText, 210]]
                        delegate: Text {
                            width: modelData[1]; height: row.height
                            leftPadding: 14
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: modelData[0]
                            color: modelData[0] === "-" ? "#666666" : row.isCurrent ? "#FFFFFF" : index === 0 ? "#BBBBBB" : "#999999"
                            font.pixelSize: 14
                            font.bold: row.isCurrent && index === 0
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: page.selectedIndex = index
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
                onEntered: page.selectedIndex = page.backIndex
                onClicked: page.close()
            }
        }

        Text {
            objectName: "controlHint"
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.pad
                  ? "Up/down to pick • " + page.padLabels.B + " or Start to go back"
                  : "W/S to pick • Esc to go back"
            color: "#888888"
            font.pixelSize: 12
            font.italic: true
        }
    }

    Keys.onPressed: (event) => {
        if (!event.isAutoRepeat) keyUsed()
        // The mute key goes on to the game and mutes; no other key reaches
        // the knight
        if (event.key === muteKey) return
        event.accepted = true
        if (event.key === Qt.Key_W || event.key === Qt.Key_Up) {
            pick(selectedIndex - 1)
        } else if (event.key === Qt.Key_S || event.key === Qt.Key_Down) {
            pick(selectedIndex + 1)
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                   || event.key === Qt.Key_Space) {
            choose(selectedIndex)
        } else if (event.key === Qt.Key_Escape) {
            close()
        }
    }
    // Releases stay here too: the game's controller must not see half a key
    Keys.onReleased: (event) => { if (event.key !== muteKey) event.accepted = true }
}
