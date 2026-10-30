import QtQuick

Item {
    id: panel
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: 20
    width: parent.width * 0.6
    height: 100 + wares.length * 18
    z: 2000
    visible: false

    property string speakerName: ""
    // Who speaks, the Npc that opened it (null for none)
    property var speaker: null
    property color speakerColor: "#C9A227"
    property var lines: []
    property int _lineIndex: 0
    // What the speaker sells, picked with keys 1 to 5: [{label, price}];
    // one with sell is what the speaker buys from the knight, for price
    property var wares: []
    // The knight's gold, to grey out what it cannot pay
    property int gold: 0
    // The speaker's answer to a purchase, shown instead of the line
    property string note: ""
    // On a pad (Game.padInUse) the stick picks a ware, selected, and
    // buyKey buys it; talkKey goes on
    property bool pad: false
    property int selected: 0
    property string talkKey: "E"
    property string buyKey: "X"

    function open(name, color, dialogueLines, offered, who) {
        speakerName = name
        speaker = who || null
        speakerColor = color
        lines = dialogueLines
        wares = offered || []
        note = ""
        selected = 0
        _lineIndex = 0
        visible = true
    }

    function advance() {
        note = ""
        _lineIndex++
        if (_lineIndex >= lines.length)
            close()
    }

    function close() {
        visible = false
        speaker = null
        lines = []
        wares = []
        note = ""
        _lineIndex = 0
    }

    // Background
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: "#CC111111"
        border.color: "#444444"
        border.width: 1
    }

    // Speaker name with colored dot
    Row {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 12
        spacing: 6

        Rectangle {
            width: 10; height: 10; radius: 5
            color: speakerColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: speakerName
            color: speakerColor
            font.pixelSize: 13
            font.bold: true
        }
    }

    // Dialogue text
    Text {
        objectName: "dialogueText"
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        anchors.topMargin: 6
        text: note !== "" ? note
              : lines.length > 0 && _lineIndex < lines.length ? lines[_lineIndex] : ""
        color: "#DDDDDD"
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }

    // The wares, one per number key, or picked on a pad
    Column {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 12
        anchors.bottomMargin: 10
        Repeater {
            model: panel.wares
            Text {
                required property var modelData
                required property int index
                text: (!panel.pad ? "[" + (index + 1) + "] " : index === panel.selected ? "▶ " : "   ")
                      + modelData.label + (modelData.sell ? " + " : " - ") + modelData.price + " gold"
                color: modelData.sell || panel.gold >= modelData.price ? "#E8B83A" : "#776644"
                font.pixelSize: 12
                font.bold: true
            }
        }
    }

    // Continue hint
    Text {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 10
        text: (pad && wares.length > 0 ? "[" + buyKey + "] buy  " : "")
              + "[" + talkKey + "] " + (_lineIndex < lines.length - 1 ? "continue" : "close")
        color: "#888888"
        font.pixelSize: 12
        font.italic: true
    }

    // Click to advance
    MouseArea {
        anchors.fill: parent
        onClicked: panel.advance()
    }
}
