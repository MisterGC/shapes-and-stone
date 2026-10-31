import QtQuick
import Clayground.Sound

Item {
    id: titleScreen

    signal singlePlayerSelected()
    signal multiplayerSelected()
    // The third row: the dungeon master's panel before each dungeon, on
    // or off (Game.dungeonMaster); Enter or a click turns it over
    signal dungeonMasterToggled()
    property bool dungeonMaster: false

    property bool muted: false
    // The player's Music and Sound settings (Game.musicVolume, soundVolume)
    property real musicVolume: 1
    property real soundVolume: 1
    property int _selectedIndex: 0
    // Why the game came back here, e.g. the host was lost; "" for none
    property string message: ""
    // The deepest descent kept on this machine (Game.recordLine); "" for none
    property string recordLine: ""
    // Who was freed tonight and the specials with the camps (CampFreed);
    // "" for none (issue #159)
    property string freedLine: ""
    property string joinedLine: ""

    // Menu sounds
    SfxPlayer {
        id: menuHoverSound
        source: "../sound/sfx/menu_change.sfx.json"
        volume: muted ? 0 : 0.5 * soundVolume
    }
    SfxPlayer {
        id: menuConfirmSound
        source: "../sound/sfx/menu_confirm.sfx.json"
        volume: muted ? 0 : 0.6 * soundVolume
    }

    // Title music, the sound factory's song (sound/cues.json)
    SongMusic {
        id: titleMusic
        source: "../sound/music/title.song.json"
        level: muted ? 0 : 0.4 * musicVolume
    }
    // A browser refuses to play before the first key press or click, and the
    // refused play() is not tried again: there the first gesture starts it.
    property bool _musicStarted: false
    function _startMusic() {
        if (_musicStarted) return
        _musicStarted = true
        titleMusic.start()
    }
    // Deferred: Game and the canvas both take focus while they are created;
    // grabbing it now would lose it to them and Enter would do nothing.
    Component.onCompleted: {
        if (Qt.platform.os !== "wasm") _startMusic()
        Qt.callLater(forceActiveFocus)
    }
    Component.onDestruction: titleMusic.halt()

    // Background (fills area not covered by image)
    Rectangle { anchors.fill: parent; color: "#0a0a14" }

    // A click anywhere counts as the browser's first gesture
    MouseArea {
        anchors.fill: parent
        onPressed: (mouse) => { titleScreen._startMusic(); mouse.accepted = false }
    }

    // Cover art — full height, centered
    Image {
        anchors.centerIn: parent
        height: parent.height
        width: implicitWidth * (height / implicitHeight)
        source: "assets/box_cover.png"
        fillMode: Image.PreserveAspectFit
    }

    // Dark gradient at bottom
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: parent.height * 0.35
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.6; color: "#CC000000" }
            GradientStop { position: 1.0; color: "#EE000000" }
        }
    }

    // Menu buttons
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.08
        spacing: 12

        Text {
            objectName: "titleRecord"
            visible: titleScreen.recordLine !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: titleScreen.recordLine
            color: "#E8C35A"
            style: Text.Outline
            styleColor: "#000000"
            font.pixelSize: 15
            font.bold: true
            font.letterSpacing: 1
        }

        Text {
            objectName: "titleFreed"
            visible: titleScreen.freedLine !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: titleScreen.freedLine
            color: "#A8D4FF"
            style: Text.Outline
            styleColor: "#000000"
            font.pixelSize: 13
        }

        Text {
            objectName: "titleJoined"
            visible: titleScreen.joinedLine !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: titleScreen.joinedLine
            color: "#E8C35A"
            style: Text.Outline
            styleColor: "#000000"
            font.pixelSize: 13
        }

        Text {
            objectName: "titleMessage"
            visible: titleScreen.message !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            text: titleScreen.message
            color: "#E0B060"
            font.pixelSize: 14
            font.bold: true
        }

        Repeater {
            model: ["Single Player", "Multiplayer", "Dungeon Master"]
            delegate: Rectangle {
                id: btn
                objectName: "titleChoice" + index
                width: 220; height: 44; radius: 6
                property bool isCurrent: titleScreen._selectedIndex === index
                color: isCurrent ? "#44FFFFFF" : "#22FFFFFF"
                border.color: isCurrent ? "#AAAAAA" : "#555555"
                border.width: isCurrent ? 2 : 1

                Text {
                    anchors.centerIn: parent
                    text: index === 2 ? modelData + ": " + (titleScreen.dungeonMaster ? "On" : "Off") : modelData
                    color: btn.isCurrent ? "#FFFFFF" : "#999999"
                    font.pixelSize: 16
                    font.bold: btn.isCurrent
                    font.letterSpacing: 1
                }

                SequentialAnimation on scale {
                    running: btn.isCurrent
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.02; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.98; duration: 800; easing.type: Easing.InOutSine }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        if (titleScreen._selectedIndex !== index) {
                            titleScreen._selectedIndex = index
                            menuHoverSound.play()
                        }
                    }
                    onClicked: { titleScreen._startMusic(); titleScreen._confirm() }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "W/S to navigate \u2022 Enter to select"
            color: "#555555"
            font.pixelSize: 10
            font.italic: true
        }
    }

    // Keyboard navigation
    Keys.onPressed: (event) => {
        _startMusic()
        if (event.key === Qt.Key_W || event.key === Qt.Key_Up) {
            if (_selectedIndex > 0) { _selectedIndex--; menuHoverSound.play() }
            event.accepted = true
        } else if (event.key === Qt.Key_S || event.key === Qt.Key_Down) {
            if (_selectedIndex < 2) { _selectedIndex++; menuHoverSound.play() }
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                   || event.key === Qt.Key_Space) {
            _confirm()
            event.accepted = true
        }
    }

    // Fade-out overlay
    Rectangle {
        id: fadeOut
        anchors.fill: parent
        color: "#000000"
        opacity: 0
        z: 100
    }

    SequentialAnimation {
        id: fadeOutAnim
        NumberAnimation { target: fadeOut; property: "opacity"; to: 1.0; duration: 1200; easing.type: Easing.InQuad }
        ScriptAction { script: _emitSelection() }
    }

    property int _pendingSelection: -1

    function _confirm() {
        if (_pendingSelection >= 0) return  // Already transitioning
        if (_selectedIndex === 2) {
            menuHoverSound.play()
            dungeonMasterToggled()
            return
        }
        _pendingSelection = _selectedIndex
        menuConfirmSound.play()
        fadeOutAnim.start()
    }

    function _emitSelection() {
        if (_pendingSelection === 0)
            singlePlayerSelected()
        else
            multiplayerSelected()
    }
}
