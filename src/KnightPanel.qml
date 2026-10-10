import QtQuick

// The knight panel, opened and closed with C: the knight's stats, what it
// carries and the smith's upgrades it has bought this run, each with what
// its level gives. It only shows: the game runs on under it and the knight
// keeps moving, alone as in a session.
Item {
    id: panel
    objectName: "knightPanel"
    width: 300
    height: body.height + 24

    // The knight shown (Player), and the game for its depth and the smith's
    // wording
    property var knight: null
    property var game: null

    readonly property var _upgrades: {
        if (!knight || !game) return []
        return game.smithLines.map(line => {
            let level = knight[line + "Level"]
            return level > 0 ? {line: line, name: game.smithName(line, level), gives: game.smithGives(line, level)}
                             : {line: line, name: game.smithName(line, 0), gives: ""}
        })
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: "#CC111111"
        border.color: "#444444"
        border.width: 1
    }

    Column {
        id: body
        x: 12; y: 12
        width: parent.width - 24
        spacing: 4

        component Stat: Row {
            property alias label: l.text
            property alias value: v.text
            property color valueColor: "#DDDDDD"
            width: body.width
            Text { id: l; width: 90; color: "#999999"; font.pixelSize: 13 }
            Text { id: v; color: valueColor; font.pixelSize: 13; font.bold: true }
        }
        component Heading: Text {
            color: "#C9A227"
            font.pixelSize: 13
            font.bold: true
            font.letterSpacing: 1
            topPadding: 6
        }

        Heading { text: "Knight"; topPadding: 0 }
        Stat {
            objectName: "knightHp"
            label: "HP"
            value: panel.knight ? panel.knight.hp + " / " + panel.knight.maxHp : ""
            valueColor: "#66CC66"
        }
        Stat {
            label: "Mana"
            value: panel.knight ? Math.floor(panel.knight.mana) + " / " + panel.knight.maxMana : ""
            valueColor: "#6FA8DC"
        }
        Stat {
            objectName: "knightDamage"
            label: "Damage"
            value: panel.knight ? String(panel.knight.atk) : ""
        }
        Stat {
            label: "Depth"
            value: panel.game ? (panel.game.levelType === "village" ? "Camp" : String(panel.game.depth)) : ""
        }

        Heading { text: "Pack" }
        Stat {
            label: "Gold"
            value: panel.knight ? String(panel.knight.gold) : ""
            valueColor: "#E8B83A"
        }
        Stat {
            objectName: "knightPotions"
            label: "Potions"
            value: panel.knight ? panel.knight.potions + "   [1] drinks one" : ""
            valueColor: "#66CC66"
        }
        Stat {
            label: "Draughts"
            value: panel.knight ? panel.knight.draughts + "   [2] drinks one" : ""
            valueColor: "#B080E0"
        }

        Heading { text: "From the smith" }
        Repeater {
            model: panel._upgrades
            delegate: Column {
                objectName: "knightUpgrade_" + modelData.line
                width: body.width
                Text {
                    width: parent.width
                    text: modelData.name + (modelData.gives === "" ? " - none yet" : "")
                    color: modelData.gives === "" ? "#777777" : "#DDDDDD"
                    font.pixelSize: 13
                    font.bold: modelData.gives !== ""
                }
                Text {
                    visible: modelData.gives !== ""
                    width: parent.width
                    leftPadding: 12
                    text: modelData.gives
                    color: "#AAAAAA"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
        }

        Text {
            topPadding: 6
            text: "C or Esc closes"
            color: "#777777"
            font.pixelSize: 11
            font.italic: true
        }
    }
}
