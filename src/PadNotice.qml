import QtQuick
import Clayground.GameController

// Says when a gamepad connects or leaves (issue #219): a short notice with
// the pad's name at the top of the screen, on the title, in the lobby and
// in a game, in the pause menu's look. A pad that was driving the knight
// and is unplugged says the keyboard and mouse play again. A pad the
// browser lists but cannot read (Firefox, clayground's "unsupported" type)
// says to use Chrome. titleLine is the title's standing line about pads:
// in the browser, where a pad is only listed after a press on it, "press a
// button on your gamepad" until one is.
Item {
    id: padNotice
    objectName: "padNotice"

    // The game's controller: which pad drives
    property var controller: null
    // How long a notice stays, in seconds, its fade in and out included
    property real seconds: 4
    property real fade: 0.25

    // The notices up now, oldest first, as {title, detail}; at most three
    readonly property alias notices: shown
    // The text of the notices up now, one "title - detail" each, for the
    // benches
    function texts() {
        let out = []
        for (let i = 0; i < shown.count; i++) {
            let n = shown.get(i)
            out.push(n.detail !== "" ? n.title + " - " + n.detail : n.title)
        }
        return out
    }

    readonly property string titleLine: titleLineFor(GamepadHub.backend, GamepadHub.gamepads)
    // What the title says about pads for a backend and its listed pads
    function titleLineFor(backend, pads) {
        for (let i = 0; i < pads.length; i++)
            if (pads[i].type === "unsupported")
                return "This browser does not read gamepads - play with one in Chrome"
        if (backend === "browser" && pads.length === 0)
            return "Press a button on your gamepad to use it"
        return ""
    }

    // The pads seen so far, deviceId -> name, and the one that drove last
    property var _known: ({})
    property int _lastDriving: -1
    Connections {
        target: padNotice.controller
        function onGamepadDeviceIdChanged() {
            let id = padNotice.controller.gamepadDeviceId
            if (id !== -1) padNotice._lastDriving = id
        }
        function onKeyboardSelectedChanged() {
            if (padNotice.controller.keyboardSelected && padNotice.controller.gamepadDeviceId === -1)
                Qt.callLater(() => { if (padNotice.controller.gamepadDeviceId === -1) padNotice._lastDriving = -1 })
        }
    }

    Connections {
        target: GamepadHub
        function onGamepadsChanged() { padNotice._sync() }
    }
    // Pads already there when the game starts are named too: the player
    // sees which one the game found
    Component.onCompleted: _sync()

    function _sync() {
        let pads = GamepadHub.gamepads
        let now = {}
        for (let i = 0; i < pads.length; i++) {
            let p = pads[i]
            now[p.deviceId] = p.name
            if (_known[p.deviceId] === undefined) {
                if (p.type === "unsupported")
                    show(p.name, "found, but this browser does not read gamepads - use Chrome")
                else
                    show("Gamepad connected", p.name)
            }
        }
        for (let id in _known) {
            if (now[id] !== undefined) continue
            let drove = Number(id) === _lastDriving
            if (drove) _lastDriving = -1
            show("Gamepad unplugged", _known[id] + (drove ? " - keyboard and mouse play now" : ""))
        }
        _known = now
    }

    function show(title, detail) {
        while (shown.count >= 3) shown.remove(0)
        shown.append({ title: title, detail: detail, until: Date.now() + seconds * 1000 })
        expiry.restart()
    }

    ListModel { id: shown }
    // Takes a notice down once its time is up
    Timer {
        id: expiry
        interval: 100
        repeat: true
        onTriggered: {
            let t = Date.now()
            while (shown.count > 0 && shown.get(0).until <= t) shown.remove(0)
            if (shown.count === 0) stop()
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 24
        spacing: 8

        Repeater {
            model: shown
            delegate: Rectangle {
                id: note
                objectName: "padNoticeRow"
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(220, row.implicitWidth + 32)
                height: 44
                radius: 6
                color: "#2A2A30"
                border.color: "#4A4A52"
                border.width: 1
                opacity: 0
                Component.onCompleted: fadeIn.start()
                NumberAnimation on opacity {
                    id: fadeIn
                    running: false
                    to: 1
                    duration: padNotice.fade * 1000
                }
                // Fades out before the timer takes it down
                Timer {
                    interval: Math.max(0, (model.until - Date.now()) - padNotice.fade * 1000)
                    running: true
                    onTriggered: fadeOut.start()
                }
                NumberAnimation on opacity {
                    id: fadeOut
                    running: false
                    to: 0
                    duration: padNotice.fade * 1000
                }

                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.title
                        color: "#FFFFFF"
                        font.pixelSize: 16
                        font.bold: true
                        font.letterSpacing: 1
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== ""
                        text: model.detail
                        color: "#AAAAAA"
                        font.pixelSize: 14
                    }
                }
            }
        }
    }
}
