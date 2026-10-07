import QtQuick

// Opened with Esc during a run: Resume or Title. Alone the game is paused
// under it; in a session the world goes on, since a pause would stop every
// other player's enemies, and only this knight stops taking input. W/S or
// the arrows pick, Enter or Space confirms, Esc resumes. Takes the keyboard
// focus and every click; M still reaches the game and mutes.
Item {
    id: pauseMenu
    objectName: "pauseMenu"

    signal resume()
    signal toTitle()

    // In a session: the world runs on under the menu
    property bool inSession: false
    property int selectedIndex: 0
    readonly property var choices: ["Resume", "Title"]

    // Deferred like the fallen screen's: the game may still take focus in
    // the same frame
    Component.onCompleted: Qt.callLater(forceActiveFocus)

    function choose(index) {
        if (index === 0) resume()
        else toTitle()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: pauseMenu.forceActiveFocus()
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: pauseMenu.inSession ? 0.35 : 0.6
    }

    Column {
        anchors.centerIn: parent
        spacing: 12

        Text {
            objectName: "pauseTitle"
            anchors.horizontalCenter: parent.horizontalCenter
            text: pauseMenu.inSession ? "Menu" : "Paused"
            color: "#DDDDDD"
            font.pixelSize: 36
            font.bold: true
            font.letterSpacing: 2
        }

        Text {
            objectName: "pauseNote"
            anchors.horizontalCenter: parent.horizontalCenter
            visible: pauseMenu.inSession
            text: "The party fights on - your knight stands still"
            color: "#E0B060"
            font.pixelSize: 13
            font.italic: true
        }

        Item { width: 1; height: 8 }

        Repeater {
            model: pauseMenu.choices
            delegate: Rectangle {
                id: btn
                objectName: "pauseChoice" + modelData
                anchors.horizontalCenter: parent.horizontalCenter
                width: 220; height: 44; radius: 6
                readonly property bool isCurrent: pauseMenu.selectedIndex === index
                // Opaque: the knight is right under the menu's middle
                color: isCurrent ? "#4A4A52" : "#2A2A30"
                border.color: isCurrent ? "#AAAAAA" : "#555555"
                border.width: isCurrent ? 2 : 1

                Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: btn.isCurrent ? "#FFFFFF" : "#999999"
                    font.pixelSize: 16
                    font.bold: btn.isCurrent
                    font.letterSpacing: 1
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: pauseMenu.selectedIndex = index
                    onClicked: pauseMenu.choose(index)
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "W/S to pick • Enter to select • Esc to resume"
            color: "#888888"
            font.pixelSize: 12
            font.italic: true
        }
    }

    Keys.onPressed: (event) => {
        // M goes on to the game and mutes; no other key reaches the knight
        if (event.key === Qt.Key_M) return
        event.accepted = true
        if (event.key === Qt.Key_W || event.key === Qt.Key_Up) {
            selectedIndex = 0
        } else if (event.key === Qt.Key_S || event.key === Qt.Key_Down) {
            selectedIndex = choices.length - 1
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                   || event.key === Qt.Key_Space) {
            choose(selectedIndex)
        } else if (event.key === Qt.Key_Escape) {
            resume()
        }
    }
    // Releases stay here too: the game's controller must not see half a key
    Keys.onReleased: (event) => { if (event.key !== Qt.Key_M) event.accepted = true }
}
