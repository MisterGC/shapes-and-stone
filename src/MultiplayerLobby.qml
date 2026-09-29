import QtQuick
import Clayground.Network
import Clayground.Sound

Item {
    id: lobby

    signal startGame()
    signal back()

    property var network: null
    property string playerName: "Knight"

    // Signaling: LAN runs the host's embedded signaling server (no internet,
    // same network only, native builds only); Internet goes through the
    // PeerJS cloud server and also reaches browser instances. Joiners need
    // no switch: the plugin detects LAN codes ("L...-...") by their shape.
    readonly property bool isBrowser: Qt.platform.os === "wasm"
    property bool lanMode: false
    function looksLikeLanCode(code) { return code.startsWith("L") && code.indexOf("-") > 0 }

    Sound {
        id: menuHoverSound
        source: "assets/menu_change.wav"
        volume: 0.5
    }
    Sound {
        id: menuConfirmSound
        source: "assets/menu_confirm.wav"
        volume: 0.6
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
                    border.color: lobby.lanMode === modelData.lan ? "#4A90A4" : "#555555"

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
                width: 150; height: 40; radius: 6
                color: "#44FFFFFF"
                border.color: "#AAAAAA"

                Text {
                    anchors.centerIn: parent
                    text: "Host Game"
                    color: "#FFFFFF"
                    font.pixelSize: 14; font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        menuConfirmSound.play()
                        network.signalingMode = lobby.lanMode
                            ? Network.SignalingMode.Local : Network.SignalingMode.Cloud
                        network.host()
                    }
                }
            }

            Rectangle {
                width: 150; height: 40; radius: 6
                color: "#44FFFFFF"
                border.color: "#AAAAAA"

                Text {
                    anchors.centerIn: parent
                    text: "Join Game"
                    color: "#FFFFFF"
                    font.pixelSize: 14; font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        menuConfirmSound.play()
                        let code = codeInput.text.trim()
                        if (code.length === 0) return
                        if (isBrowser && looksLikeLanCode(code)) {
                            statusText.text = "LAN codes only work in the native game"
                            return
                        }
                        network.join(code)
                    }
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
                    text: "\u2022 " + modelData + (modelData === network.nodeId ? " (you)" : "")
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
            color: "#44CC4444"
            border.color: "#44CC44"
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
            width: 120; height: 32; radius: 4
            color: "#22FFFFFF"
            border.color: "#555555"

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
