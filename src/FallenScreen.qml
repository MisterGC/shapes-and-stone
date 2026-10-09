import QtQuick

// Shown when the knight falls: how deep the run got, its kills and time,
// the best depth kept between runs, Enter to go again, Esc back to the
// title. In a session whose other knights still fight it says the knight
// is down, keeps the dungeon in sight and offers only Esc, which leaves;
// once every knight is down it shows the party's run, the host's Enter
// starts the next run for everyone and a joiner waits for it. Esc leaves
// the session. Takes the keyboard focus and every click.
Item {
    id: fallenScreen
    objectName: "fallenScreen"

    signal goAgain()
    signal backToTitle()

    property int depth: 0
    property int kills: 0
    // Simulated seconds the run lasted
    property real seconds: 0
    property int bestDepth: 0
    // This run went deeper than any before it
    property bool newBest: false
    // Enter starts the next run: alone, or the host once the party has
    // fallen. A session run ends for everyone or no one
    property bool canGoAgain: true
    // The party has fallen and this joiner waits for the host to go again
    property bool waitsForHost: false
    // Another knight of the session still stands: this one is down, the
    // run goes on, and the dungeon stays in sight
    property bool partyFights: false
    // Every knight of the session is down and the run is over
    property bool partyFallen: false

    // Deferred like the title screen's: the game may still take focus in
    // the same frame
    Component.onCompleted: Qt.callLater(forceActiveFocus)
    onPartyFallenChanged: if (partyFallen) shadeIn.restart()

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
        // Darker once the party has fallen
        NumberAnimation on opacity {
            id: shadeIn
            to: fallenScreen.partyFights ? 0.3 : 0.75
            duration: 900
            easing.type: Easing.OutQuad
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 16
        opacity: 0
        NumberAnimation on opacity { to: 1; duration: 900; easing.type: Easing.InQuad }

        Text {
            objectName: "fallenTitle"
            anchors.horizontalCenter: parent.horizontalCenter
            text: fallenScreen.partyFights ? "You are down"
                  : fallenScreen.partyFallen ? "Your party has fallen" : "You have fallen"
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

        Text {
            objectName: "fallenStats"
            anchors.horizontalCenter: parent.horizontalCenter
            text: fallenScreen.kills + (fallenScreen.kills === 1 ? " kill" : " kills")
                  + "  •  " + Math.floor(fallenScreen.seconds / 60) + ":"
                  + String(Math.floor(fallenScreen.seconds % 60)).padStart(2, "0")
            color: "#AAAAAA"
            font.pixelSize: 14
        }

        Text {
            objectName: "fallenBest"
            anchors.horizontalCenter: parent.horizontalCenter
            text: fallenScreen.newBest ? "New best depth" : "Best depth " + fallenScreen.bestDepth
            color: fallenScreen.newBest ? "#E8C35A" : "#AAAAAA"
            font.pixelSize: 14
            font.bold: fallenScreen.newBest
        }

        Item { width: 1; height: 12 }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            objectName: "fallenHint"
            text: fallenScreen.canGoAgain
                  ? "Enter to go again • Esc to the title"
                  : fallenScreen.waitsForHost
                    ? "Waiting for the host to go again • Esc to leave the session"
                    : fallenScreen.partyFights
                      ? "Your party fights on • Esc to leave the session"
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
