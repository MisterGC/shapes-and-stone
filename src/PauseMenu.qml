import QtQuick

// Opened with Esc during a run: Resume, the Music and Sound volumes, the
// Duel pace (issue #362), the Control Input page (issue #220) and Title.
// Alone the game is paused under it; in a session the world goes
// on, since a pause would stop every other player's enemies, and only this
// knight stops taking input. W/S or the arrows pick, A/D or the arrows turn
// a volume down or up a tenth and the duel pace a step slower or quicker
// (Balance.pace), Enter or Space confirms, Esc resumes; a gamepad does the
// same with its stick or D-pad, A, and B or Start, and a click on a row's
// arrows turns it. On a joiner the duel pace row shows the host's and does
// not turn. Takes the keyboard focus and every click; the mute key (M)
// still reaches the game and mutes.
Item {
    id: pauseMenu
    objectName: "pauseMenu"

    signal resume()
    signal toTitle()
    // The Control Input page is to open over the menu
    signal controlInput()
    // which: "music" or "sound", value 0..1
    signal volumeSet(string which, real value)
    // name: one of Balance.pace's steps
    signal duelPaceSet(string name)

    // In a session: the world runs on under the menu
    property bool inSession: false
    // A pad in use (Game.padInUse): the hint names its buttons, as printed
    // on it (Game.padLabels)
    property bool pad: false
    property var padLabels: ({ A: "A", B: "B", X: "X", Y: "Y" })
    // The key that mutes, in the game's control table (Game.controls)
    property int muteKey: Qt.Key_M
    property int selectedIndex: 0
    readonly property var choices: ["Resume", "Music", "Sound", "Duel pace", "Control Input", "Title"]
    readonly property int paceRow: 3
    property real musicVolume: 1
    property real soundVolume: 1
    // The duel pace the leads play at (Game.playedDuelPace), and whether it
    // is the host's, which this menu shows and does not turn
    property string duelPace: Balance.pace.standard
    property bool paceByHost: false
    readonly property var paceSteps: Balance.pace.steps.map(p => p.name)

    // Deferred like the fallen screen's: the game may still take focus in
    // the same frame
    Component.onCompleted: Qt.callLater(forceActiveFocus)

    function choose(index) {
        if (index === 0) resume()
        else if (index === 4) controlInput()
        else if (index === 5) toTitle()
    }
    // The row's volume, or -1 for a row that has none
    function volumeOf(index) {
        return index === 1 ? musicVolume : index === 2 ? soundVolume : -1
    }
    // What a row that turns shows between its arrows, "" for one that does
    // not turn
    function valueOf(index) {
        if (index === paceRow) return duelPace
        let v = volumeOf(index)
        return v < 0 ? "" : Math.round(v * 100) + "%"
    }
    // Turns a volume by a share, the duel pace a step the way by points:
    // down to Swift, up to Deliberate, no further than either
    function turn(index, by) {
        if (index === paceRow) {
            if (paceByHost || by === 0) return
            let i = paceSteps.indexOf(duelPace)
            let next = Math.max(0, Math.min(paceSteps.length - 1, (i < 0 ? paceSteps.indexOf(Balance.pace.standard) : i)
                                                                      + (by > 0 ? 1 : -1)))
            if (paceSteps[next] !== duelPace) duelPaceSet(paceSteps[next])
            return
        }
        let v = volumeOf(index)
        if (v < 0) return
        let next = Math.round(Math.max(0, Math.min(1, v + by)) * 10) / 10
        if (next !== v) volumeSet(index === 1 ? "music" : "sound", next)
    }
    // The gamepad (MenuPad): up and down pick, left and right set a
    // volume or the duel pace, A selects, B and Start resume
    function padMove(dx, dy) {
        if (dy !== 0) selectedIndex = Math.max(0, Math.min(choices.length - 1, selectedIndex - dy))
        else turn(selectedIndex, dx * 0.1)
    }
    function padConfirm() { choose(selectedIndex) }
    function padBack() { resume() }

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

        Text {
            objectName: "pausePaceNote"
            anchors.horizontalCenter: parent.horizontalCenter
            visible: pauseMenu.paceByHost
            text: "The host sets the duel pace"
            color: "#E0B060"
            font.pixelSize: 13
            font.italic: true
        }

        Item { width: 1; height: 8 }

        Repeater {
            model: pauseMenu.choices
            delegate: Rectangle {
                id: btn
                objectName: "pauseChoice" + modelData.replace(" ", "")
                anchors.horizontalCenter: parent.horizontalCenter
                width: 280; height: 44; radius: 6
                readonly property bool isCurrent: pauseMenu.selectedIndex === index
                // What the row shows between its arrows, "" for a row
                // that does not turn
                readonly property string value: pauseMenu.valueOf(index)
                readonly property bool turns: value !== ""
                readonly property bool locked: index === pauseMenu.paceRow && pauseMenu.paceByHost
                readonly property int row: index
                readonly property string text: modelData
                // Opaque: the knight is right under the menu's middle
                color: isCurrent ? "#4A4A52" : "#2A2A30"
                border.color: isCurrent ? "#AAAAAA" : "#555555"
                border.width: isCurrent ? 2 : 1

                Text {
                    anchors.centerIn: parent
                    visible: !btn.turns
                    text: modelData
                    color: btn.isCurrent ? "#FFFFFF" : "#999999"
                    font.pixelSize: 16
                    font.bold: btn.isCurrent
                    font.letterSpacing: 1
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: !btn.turns ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onEntered: pauseMenu.selectedIndex = index
                    onClicked: pauseMenu.choose(index)
                }

                // A row that turns: its name, then its value - a volume's
                // share, the duel pace's step - between arrows that turn
                // it down and up; on a joiner the duel pace has none
                Row {
                    visible: btn.turns
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    readonly property int valueWidth: btn.row === pauseMenu.paceRow ? 96 : 52
                    Text {
                        width: parent.width - 80 - parent.valueWidth; height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: modelData
                        color: btn.isCurrent ? "#FFFFFF" : "#999999"
                        font.pixelSize: 16
                        font.bold: btn.isCurrent
                        font.letterSpacing: 1
                    }
                    Repeater {
                        model: ["\u25C0", "", "\u25B6"]
                        delegate: Text {
                            objectName: modelData === "" ? "pauseValue" + btn.text.replace(" ", "")
                                        : modelData === "\u25C0" ? "pauseDown" + btn.text.replace(" ", "")
                                        : "pauseUp" + btn.text.replace(" ", "")
                            width: modelData === "" ? parent.valueWidth : 40; height: btn.height
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData !== "" ? (btn.locked ? "" : modelData) : btn.value
                            color: btn.isCurrent ? "#FFFFFF" : "#999999"
                            font.pixelSize: modelData === "" ? 15 : 13
                            font.bold: btn.isCurrent
                            MouseArea {
                                anchors.fill: parent
                                enabled: modelData !== "" && !btn.locked
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: pauseMenu.selectedIndex = btn.row
                                onClicked: pauseMenu.turn(btn.row, index === 0 ? -0.1 : 0.1)
                            }
                        }
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: pauseMenu.pad
                  ? "Up/down to pick • left/right to set • " + pauseMenu.padLabels.A + " to select • "
                    + pauseMenu.padLabels.B + " or Start to resume"
                  : "W/S to pick • A/D to set • Enter to select • Esc to resume"
            color: "#888888"
            font.pixelSize: 12
            font.italic: true
        }
    }

    Keys.onPressed: (event) => {
        // The mute key goes on to the game and mutes; no other key reaches
        // the knight
        if (event.key === muteKey) return
        event.accepted = true
        if (event.key === Qt.Key_W || event.key === Qt.Key_Up) {
            selectedIndex = Math.max(0, selectedIndex - 1)
        } else if (event.key === Qt.Key_S || event.key === Qt.Key_Down) {
            selectedIndex = Math.min(choices.length - 1, selectedIndex + 1)
        } else if (event.key === Qt.Key_A || event.key === Qt.Key_Left) {
            turn(selectedIndex, -0.1)
        } else if (event.key === Qt.Key_D || event.key === Qt.Key_Right) {
            turn(selectedIndex, 0.1)
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                   || event.key === Qt.Key_Space) {
            choose(selectedIndex)
        } else if (event.key === Qt.Key_Escape) {
            resume()
        }
    }
    // Releases stay here too: the game's controller must not see half a key
    Keys.onReleased: (event) => { if (event.key !== muteKey) event.accepted = true }
}
