import QtQuick

Item {
    id: panel
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: 20
    width: parent.width * 0.6
    height: 100
    z: 2000
    visible: false

    property string speakerName: ""
    property color speakerColor: "#C9A227"
    property var lines: []
    property int _lineIndex: 0

    function open(name, color, dialogueLines) {
        speakerName = name
        speakerColor = color
        lines = dialogueLines
        _lineIndex = 0
        visible = true
    }

    function advance() {
        _lineIndex++
        if (_lineIndex >= lines.length)
            close()
    }

    function close() {
        visible = false
        lines = []
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
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        anchors.topMargin: 6
        text: lines.length > 0 && _lineIndex < lines.length ? lines[_lineIndex] : ""
        color: "#DDDDDD"
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }

    // Continue hint
    Text {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 10
        text: _lineIndex < lines.length - 1 ? "[E] continue" : "[E] close"
        color: "#888888"
        font.pixelSize: 10
        font.italic: true
    }

    // Click to advance
    MouseArea {
        anchors.fill: parent
        onClicked: panel.advance()
    }
}
