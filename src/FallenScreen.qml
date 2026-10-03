import QtQuick

// Shown when the knight falls: how deep the run got, Enter to go again,
// Esc back to the title. Takes the keyboard focus and every click.
Item {
    id: fallenScreen
    objectName: "fallenScreen"

    signal goAgain()
    signal backToTitle()

    property int depth: 0
    // A session run ends for everyone or no one (co-op death is #19):
    // until then a fallen co-op player only leaves
    property bool canGoAgain: true

    // Deferred like the title screen's: the game may still take focus in
    // the same frame
    Component.onCompleted: Qt.callLater(forceActiveFocus)

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: fallenScreen.forceActiveFocus()
    }

    Rectangle {
        id: shade
        anchors.fill: parent
        color: "#000000"
        opacity: 0
        NumberAnimation on opacity { to: 0.75; duration: 900; easing.type: Easing.OutQuad }
    }

    Column {
        anchors.centerIn: parent
        spacing: 16
        opacity: 0
        NumberAnimation on opacity { to: 1; duration: 900; easing.type: Easing.InQuad }

        Text {
            objectName: "fallenTitle"
            anchors.horizontalCenter: parent.horizontalCenter
            text: "You have fallen"
            color: "#CC4444"
            font.pixelSize: 42
            font.bold: true
            font.letterSpacing: 2
        }

        Text {
            objectName: "fallenDepth"
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Depth " + fallenScreen.depth
            color: "#DDDDDD"
            font.pixelSize: 20
            font.letterSpacing: 1
        }

        Item { width: 1; height: 12 }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: fallenScreen.canGoAgain
                  ? "Enter to go again • Esc to the title"
                  : "Esc to leave the session"
            color: "#888888"
            font.pixelSize: 12
            font.italic: true
        }
    }

    Keys.onPressed: (event) => {
        // Other keys go on to the game: M still mutes, and the fallen
        // knight ignores the rest
        if (canGoAgain && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            goAgain()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            backToTitle()
            event.accepted = true
        }
    }
}
