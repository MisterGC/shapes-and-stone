import QtQuick

// The choice of a special (issue #317): before a dungeon's descent intro
// counts, a card per special the knight may pick (Balance.specials) with
// its name, a line of what it does and its mana cost. It shows the game's
// choice and tells it what was done: the arrows, 1 to 3, Enter, Space and
// the talk key reach the game's key handler; the move keys left and
// right, as the keyboard's stick, and a gamepad's stick or D-pad and A
// come through MenuPad (padMove, padConfirm); the mouse picks a card by a
// click. The card under the keys or the stick is drawn in
// Balance.specials.pickColor. Each card names the special's stronger
// version and what is stronger about it, and a line under the cards the
// combo that fires it (Balance.combo, issue #320)
Item {
    id: choice
    objectName: "specialChoice"

    // The cards, [{id, name, line, mana, strongName, strongLine}], in
    // Balance.specials.order
    property var cards: []
    // The card under the keys or the stick (Game.specialSelected)
    property int selected: 0
    // A pad in use (Game.padInUse): the hint names its stick and its A, as
    // printed on it (Game.padLabels)
    property bool pad: false
    property var padLabels: ({ A: "A" })
    // What the keys that move and take are bound to, for the hint
    property string keysMove: "A/D"
    // The combo for the stronger version, in the controls as bound
    // (Game.comboHint)
    property string combo: ""

    // A move along the cards, a card under the mouse, a card taken
    signal moved(int by)
    signal pointed(int index)
    signal taken(int index)

    function padMove(dx, dy) { if (dx !== 0) moved(dx) }
    function padConfirm() { taken(selected) }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.36
        spacing: 10

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Choose your special"
            color: "#DDDDDD"
            style: Text.Outline
            styleColor: "#000000"
            font.pixelSize: 18
            font.bold: true
            font.letterSpacing: 2
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            Repeater {
                model: choice.cards
                Rectangle {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property bool chosen: index === choice.selected
                    objectName: "specialCard_" + modelData.id
                    width: Math.min(Balance.specials.cardWidth,
                                    (choice.width - 32 - 12 * (choice.cards.length - 1)) / choice.cards.length)
                    height: cardText.implicitHeight + 24
                    radius: 6
                    color: "#E0101018"
                    border.color: chosen ? Balance.specials.pickColor : "#555555"
                    border.width: chosen ? 3 : 1
                    Column {
                        id: cardText
                        x: 12
                        y: 12
                        width: parent.width - 24
                        spacing: 6
                        Text {
                            objectName: "specialName"
                            width: parent.width
                            text: (choice.cards.length > 1 ? (card.index + 1) + "  " : "") + card.modelData.name
                            color: card.chosen ? Balance.specials.pickColor : "#FFFFFF"
                            font.pixelSize: 18
                            font.bold: true
                        }
                        Text {
                            objectName: "specialLine"
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: card.modelData.line
                            color: "#CCCCCC"
                            font.pixelSize: 13
                        }
                        Text {
                            objectName: "specialStrong"
                            width: parent.width
                            wrapMode: Text.WordWrap
                            visible: card.modelData.strongName !== ""
                            text: "Combo: " + card.modelData.strongName + ", " + card.modelData.strongLine
                            color: Balance.combo.color
                            font.pixelSize: 12
                        }
                        Text {
                            objectName: "specialMana"
                            width: parent.width
                            text: card.modelData.mana + " mana"
                            color: "#C080FF"
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                        hoverEnabled: true
                        onEntered: choice.pointed(card.index)
                        onClicked: choice.taken(card.index)
                    }
                }
            }
        }
        Text {
            objectName: "specialCombo"
            anchors.horizontalCenter: parent.horizontalCenter
            visible: choice.combo !== ""
            text: choice.combo
            color: Balance.combo.color
            style: Text.Outline
            styleColor: "#000000"
            font.pixelSize: 13
        }
        Text {
            objectName: "specialHint"
            anchors.horizontalCenter: parent.horizontalCenter
            text: choice.pad ? "Stick choose  •  " + choice.padLabels.A + " take"
                             : choice.keysMove + " or 1-" + choice.cards.length + " choose  •  Enter take  •  or click"
            color: "#AAAAAA"
            style: Text.Outline
            styleColor: "#000000"
            font.pixelSize: 13
        }
    }
}
