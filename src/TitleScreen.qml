import QtQuick
import Clayground.Sound

Item {
    id: titleScreen

    signal singlePlayerSelected()
    signal multiplayerSelected()

    property int _selectedIndex: 0

    // Menu sounds
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

    // Title music
    Music {
        id: titleMusic
        source: "assets/title_music.mp3"
        volume: 0.4
        loop: true
    }
    Component.onCompleted: { titleMusic.play(); forceActiveFocus() }
    Component.onDestruction: titleMusic.stop()

    // Background (fills area not covered by image)
    Rectangle { anchors.fill: parent; color: "#0a0a14" }

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

        Repeater {
            model: ["Single Player", "Multiplayer"]
            delegate: Rectangle {
                id: btn
                width: 220; height: 44; radius: 6
                property bool isCurrent: titleScreen._selectedIndex === index
                color: isCurrent ? "#44FFFFFF" : "#22FFFFFF"
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
                    onClicked: titleScreen._confirm()
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
        if (event.key === Qt.Key_W || event.key === Qt.Key_Up) {
            if (_selectedIndex > 0) { _selectedIndex--; menuHoverSound.play() }
            event.accepted = true
        } else if (event.key === Qt.Key_S || event.key === Qt.Key_Down) {
            if (_selectedIndex < 1) { _selectedIndex++; menuHoverSound.play() }
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
