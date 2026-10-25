import QtQuick
import Clayground.Network
import Clayground.Sound

Item {
    id: lobby

    signal startGame()
    signal back()

    property var network: null
    property string playerName: "Knight"
    property bool muted: false
    // The player's Sound setting (Game.soundVolume)
    property real soundVolume: 1
    // Every knight's name by its node (Session.names)
    property var names: ({})
    // The record: this machine's, once connected the host's (Game.recordLine)
    property string recordLine: ""

    // Signaling: LAN runs the host's embedded signaling server (no internet,
    // same network only, native builds only); Internet goes through the
    // PeerJS cloud server and also reaches browser instances. Joiners need
    // no switch: the plugin detects LAN codes ("L...-...") by their shape.
    readonly property bool isBrowser: Qt.platform.os === "wasm"
    property bool lanMode: false
    function looksLikeLanCode(code) { return code.startsWith("L") && code.indexOf("-") > 0 }

    function hostGame() {
        menuConfirmSound.play()
        network.signalingMode = lobby.lanMode
            ? Network.SignalingMode.Local : Network.SignalingMode.Cloud
        network.host()
    }
    function joinGame() {
        menuConfirmSound.play()
        let code = codeInput.text.trim()
        if (code.length === 0) return
        if (isBrowser && looksLikeLanCode(code)) {
            statusText.text = "LAN codes only work in the native game"
            return
        }
        network.join(code)
    }

    // The gamepad (MenuPad, issue #201): up and down move the focus over
    // what the lobby offers now, left and right turn Internet/LAN over and
    // go between Host and Join, A presses, B goes back. Join takes the
    // code typed or pasted; the pad cannot type one. The focus shows once
    // the pad moved it.
    readonly property bool _picking: !network.connected && network.status !== 1
    readonly property var padChoices: {
        let c = []
        if (_picking) {
            if (!isBrowser) c.push("mode")
            c.push("host", "join")
        }
        if (network.isHost && network.nodeCount >= 2) c.push("start")
        c.push("back")
        return c
    }
    property int padIndex: 0
    property bool padUsed: false
    readonly property string padChoice: padChoices[Math.min(padIndex, padChoices.length - 1)]
    function padShown(choice) { return padUsed && padChoice === choice }
    function padMove(dx, dy) {
        padUsed = true
        let i = Math.min(padIndex, padChoices.length - 1)
        if (dy !== 0) {
            // Host and Join share a row
            let next = i - dy
            if (dy < 0 && padChoices[i] === "host") next++
            if (dy > 0 && padChoices[i] === "join" && padChoices[i - 1] === "host") next--
            next = Math.max(0, Math.min(padChoices.length - 1, next))
            if (next !== i) menuHoverSound.play()
            padIndex = next
        } else if (padChoice === "mode") {
            if (lanMode !== (dx > 0)) menuHoverSound.play()
            lanMode = dx > 0
        } else if (padChoice === "host" && dx > 0 || padChoice === "join" && dx < 0) {
            menuHoverSound.play()
            padIndex = i + dx
        }
    }
    function padConfirm() {
        padUsed = true
        let c = padChoice
        if (c === "mode") {
            menuHoverSound.play()
            lanMode = !lanMode
        }
        else if (c === "host") hostGame()
        else if (c === "join") joinGame()
        else if (c === "start") {
            menuConfirmSound.play()
            startGame()
        }
        else back()
    }
    function padBack() { back() }

    Sound {
        id: menuHoverSound
        source: "assets/menu_change.wav"
        volume: muted ? 0 : 0.5 * soundVolume
    }
    Sound {
        id: menuConfirmSound
        source: "assets/menu_confirm.wav"
        volume: muted ? 0 : 0.6 * soundVolume
    }

    Connections {
        target: network
        function onErrorOccurred(message) {
            console.log("[Lobby] Error:", message)
            statusText.text = "Error: " + message
        }
    }

    // Background
    Rectangle {
        anchors.fill: parent
        color: "#1a1a2e"
    }

    // Main panel
    Column {
        anchors.centerIn: parent
        spacing: 16
        width: 320

        // Title
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Multiplayer"
            color: "#CCCCCC"
            font.pixelSize: 24
            font.bold: true
            font.letterSpacing: 2
        }

        Text {
            objectName: "lobbyRecord"
            visible: lobby.recordLine !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: lobby.recordLine
            color: "#E8C35A"
            font.pixelSize: 13
        }

        // Player name
        Rectangle {
            width: parent.width; height: 36; radius: 4
            color: "#22FFFFFF"
            border.color: "#555555"

            TextInput {
                anchors.fill: parent
                anchors.margins: 8
                text: lobby.playerName
                color: "#FFFFFF"
                font.pixelSize: 14
                onTextChanged: lobby.playerName = text
                maximumLength: 16
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "Name"
                color: "#555555"
                font.pixelSize: 10
            }
        }

        // Signaling mode (host side; hidden in the browser, which is Internet only)
        Row {
            visible: !isBrowser && !network.connected && network.status !== 1
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Repeater {
                model: [{label: "Internet", lan: false}, {label: "LAN", lan: true}]
                delegate: Rectangle {
                    width: 100; height: 28; radius: 4
                    color: lobby.lanMode === modelData.lan ? "#444A90A4" : "#22FFFFFF"
                    border.color: lobby.padShown("mode") && lobby.lanMode === modelData.lan ? "#FFFFFF"
                                  : lobby.lanMode === modelData.lan ? "#4A90A4" : "#555555"
                    border.width: lobby.padShown("mode") && lobby.lanMode === modelData.lan ? 2 : 1

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: lobby.lanMode === modelData.lan ? "#FFFFFF" : "#999999"
                        font.pixelSize: 12
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (lobby.lanMode !== modelData.lan) menuHoverSound.play()
                            lobby.lanMode = modelData.lan
                        }
                    }
                }
            }
        }

        Text {
            visible: !isBrowser && !network.connected && network.status !== 1
            anchors.horizontalCenter: parent.horizontalCenter
            text: lobby.lanMode ? "Same network, no internet needed, native players only"
                                : "Works across the internet and with browser players"
            color: "#777777"
            font.pixelSize: 10
        }

        // Host / Join buttons (pre-connection)
        Row {
            visible: !network.connected && network.status !== 1 // Not connecting
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Rectangle {
                objectName: "lobbyHost"
                width: 150; height: 40; radius: 6
                color: "#44FFFFFF"
                border.color: lobby.padShown("host") ? "#FFFFFF" : "#AAAAAA"
                border.width: lobby.padShown("host") ? 2 : 1

                Text {
                    anchors.centerIn: parent
                    text: "Host Game"
                    color: "#FFFFFF"
                    font.pixelSize: 14; font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: lobby.hostGame()
                }
            }

            Rectangle {
                objectName: "lobbyJoin"
                width: 150; height: 40; radius: 6
                color: "#44FFFFFF"
                border.color: lobby.padShown("join") ? "#FFFFFF" : "#AAAAAA"
                border.width: lobby.padShown("join") ? 2 : 1

                Text {
                    anchors.centerIn: parent
                    text: "Join Game"
                    color: "#FFFFFF"
                    font.pixelSize: 14; font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: lobby.joinGame()
                }
            }
        }

        // Network code input (for joining)
        Rectangle {
            visible: !network.connected && network.status !== 1
            width: parent.width; height: 36; radius: 4
            color: "#22FFFFFF"
            border.color: "#555555"

            TextInput {
                id: codeInput
                anchors.fill: parent
                anchors.margins: 8
                color: "#FFFFFF"
                font.pixelSize: 14
                font.family: "monospace"
                maximumLength: 20

                Text {
                    anchors.fill: parent
                    text: "Enter network code to join..."
                    color: "#555555"
                    font.pixelSize: 14
                    visible: codeInput.text.length === 0 && !codeInput.activeFocus
                }
            }
        }

        // Status
        Text {
            id: statusText
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                if (network.connected)
                    return "Connected \u2022 " + network.nodeCount + " player(s)"
                if (network.status === 1)
                    return "Connecting..."
                return "Not connected"
            }
            color: network.connected ? "#44CC44" : "#999999"
            font.pixelSize: 12
        }

        // Network code display (when hosting)
        Rectangle {
            visible: network.isHost && network.networkId !== ""
            width: parent.width; height: 40; radius: 4
            color: "#22FFFFFF"
            border.color: "#4A90A4"

            Text {
                anchors.centerIn: parent
                text: (network.signalingMode === Network.SignalingMode.Local ? "LAN code: " : "Code: ")
                      + network.networkId
                color: "#4A90A4"
                font.pixelSize: 16
                font.bold: true
                font.family: "monospace"
                font.letterSpacing: 2
            }
        }

        // Player list
        Column {
            visible: network.connected
            width: parent.width
            spacing: 4

            Text {
                text: "Players:"
                color: "#888888"
                font.pixelSize: 11
            }

            Repeater {
                model: network.nodes
                delegate: Text {
                    text: "\u2022 " + (lobby.names[modelData] || modelData)
                          + (modelData === network.nodeId ? " (you)" : "")
                    color: "#CCCCCC"
                    font.pixelSize: 12
                    font.family: "monospace"
                }
            }
        }

        // Start Game button (host only, 2+ players)
        Rectangle {
            visible: network.isHost && network.nodeCount >= 2
            anchors.horizontalCenter: parent.horizontalCenter
            width: 200; height: 44; radius: 6
            objectName: "lobbyStart"
            color: "#44CC4444"
            border.color: lobby.padShown("start") ? "#FFFFFF" : "#44CC44"
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: "Start Game"
                color: "#44CC44"
                font.pixelSize: 16; font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    menuConfirmSound.play()
                    lobby.startGame()
                }
            }
        }

        // Back button
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            objectName: "lobbyBack"
            width: 120; height: 32; radius: 4
            color: "#22FFFFFF"
            border.color: lobby.padShown("back") ? "#FFFFFF" : "#555555"
            border.width: lobby.padShown("back") ? 2 : 1

            Text {
                anchors.centerIn: parent
                text: "Back"
                color: "#999999"
                font.pixelSize: 12
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: lobby.back()
            }
        }
    }

    Component.onCompleted: forceActiveFocus()

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            back()
            event.accepted = true
        }
    }
}
