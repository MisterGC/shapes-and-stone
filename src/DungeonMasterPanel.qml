import QtQuick

// The dungeon master's panel (issue #142), up before each dungeon for the
// host or a solo player with Dungeon Master ticked on the title. Its rows
// are Balance.dungeonMaster's settings at the values the game would use,
// a set one marked; the map is the dungeon Go enters, with its enemies,
// breakables and traps. W/S or the arrows pick a row, A/D or the arrows
// turn it a step (and set it), Backspace gives it back to the game, G
// generates (again: a new dungeon), Enter or Space goes, C copies the
// settings set as JSON and V pastes them. A gamepad picks and turns with
// its stick or D-pad, gives back with B, generates with X and goes with A
// or Start. Takes the keyboard focus and every click; M still reaches the
// game and mutes.
Item {
    id: panel
    objectName: "dungeonMasterPanel"

    signal turned(string key, int steps)
    signal unset(string key)
    signal generate()
    signal go()
    signal copied()
    signal pasted(string text)

    // A pad in use (Game.padInUse): the hint names its buttons, as printed
    // on it (Game.padLabels)
    property bool pad: false
    property var padLabels: ({ A: "A", B: "B", X: "X", Y: "Y" })
    // The depth of the dungeon the panel is up for
    property int depth: 0
    // [{key, label, value, set, text}] (Game.masterRows)
    property var rows: []
    // What Generate showed (Game.planDungeon), null before it
    property var preview: null
    property string note: ""
    // The settings set, as Copy settings puts them on the clipboard
    property string settingsJson: "{}"
    property int cellWall: 0
    property real cellSize: 2
    property int selectedIndex: 0

    Component.onCompleted: Qt.callLater(forceActiveFocus)

    function turn(by) {
        let r = rows[selectedIndex]
        if (r) turned(r.key, by)
    }
    function copySettings() {
        clip.text = settingsJson
        clip.selectAll()
        clip.copy()
        clip.text = ""
        copied()
    }
    function pasteSettings() {
        clip.text = ""
        clip.paste()
        let t = clip.text
        clip.text = ""
        pasted(t)
    }

    // The gamepad (MenuPad): up and down pick a row, left and right turn
    // it, B gives it back to the game, X generates, A or Start goes
    function padMove(dx, dy) {
        if (dy !== 0) selectedIndex = Math.max(0, Math.min(rows.length - 1, selectedIndex - dy))
        else turn(dx)
    }
    function padConfirm() { go() }
    function padBack() {
        let r = rows[selectedIndex]
        if (r) unset(r.key)
    }
    function padExtra() { generate() }

    // What Generate showed, counted
    readonly property var counts: {
        let c = { rooms: 0, enemies: 0, breakables: 0, spike: 0, slit: 0, doors: 0, secrets: 0 }
        if (!preview) return c
        c.rooms = preview.rooms.length
        c.enemies = preview.enemies.length
        for (let f of preview.features) {
            if (f.kind === "spike" || f.kind === "slit") c[f.kind]++
            else c.breakables++
        }
        c.doors = preview.doors.length
        c.secrets = preview.secrets.length
        return c
    }

    // The clipboard's way in and out: QML has no clipboard of its own
    TextEdit { id: clip; visible: false }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: panel.forceActiveFocus()
    }

    Rectangle {
        anchors.fill: parent
        color: "#08070C"
        opacity: 0.9
    }

    Column {
        anchors.centerIn: parent
        spacing: 14

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Dungeon Master"
            color: "#DDDDDD"
            font.pixelSize: 32
            font.bold: true
            font.letterSpacing: 2
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Depth " + panel.depth + " waits below"
            color: "#E0B060"
            font.pixelSize: 14
            font.italic: true
        }

        Row {
            spacing: 24

            Column {
                id: settingsColumn
                spacing: 8
                width: 340

                Repeater {
                    model: panel.rows
                    delegate: Rectangle {
                        id: rowItem
                        objectName: "masterRow_" + modelData.key
                        width: settingsColumn.width; height: 38; radius: 6
                        readonly property bool isCurrent: panel.selectedIndex === index
                        readonly property int row: index
                        color: isCurrent ? "#4A4A52" : "#2A2A30"
                        border.color: isCurrent ? "#AAAAAA" : "#555555"
                        border.width: isCurrent ? 2 : 1

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: panel.selectedIndex = rowItem.row
                            // A double click gives the row back to the game
                            onDoubleClicked: panel.unset(modelData.key)
                        }
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            Text {
                                width: parent.width - 150; height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: modelData.label
                                color: rowItem.isCurrent ? "#FFFFFF" : "#999999"
                                font.pixelSize: 14
                                font.bold: rowItem.isCurrent
                            }
                            Repeater {
                                model: ["◀", "", "▶"]
                                delegate: Text {
                                    objectName: modelData === "" ? "masterValue_" + panel.rows[rowItem.row].key : ""
                                    width: modelData === "" ? 78 : 32; height: rowItem.height
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    // A value set by the master is gold, the game's grey
                                    text: modelData !== "" ? modelData : panel.rows[rowItem.row].text
                                    color: modelData === "" && panel.rows[rowItem.row].set ? "#E8C35A"
                                           : rowItem.isCurrent ? "#FFFFFF" : "#999999"
                                    font.pixelSize: modelData === "" ? 14 : 12
                                    font.bold: modelData === "" && panel.rows[rowItem.row].set
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: modelData !== ""
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: panel.selectedIndex = rowItem.row
                                        onClicked: panel.turned(panel.rows[rowItem.row].key, index === 0 ? -1 : 1)
                                    }
                                }
                            }
                        }
                    }
                }

                Item { width: 1; height: 4 }

                Grid {
                    columns: 2
                    spacing: 8
                    Repeater {
                        // The pad copies and pastes nothing: those name no button
                        model: [{ label: "Generate  (" + (panel.pad ? panel.padLabels.X : "G") + ")", act: "generate" },
                                { label: "Go  (" + (panel.pad ? panel.padLabels.A : "Enter") + ")", act: "go" },
                                { label: "Copy settings" + (panel.pad ? "" : "  (C)"), act: "copy" },
                                { label: "Paste settings" + (panel.pad ? "" : "  (V)"), act: "paste" }]
                        delegate: Rectangle {
                            objectName: "masterButton_" + modelData.act
                            width: 166; height: 38; radius: 6
                            color: modelData.act === "go" ? "#3E5A44" : "#2A2A30"
                            border.color: "#777777"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: "#EEEEEE"
                                font.pixelSize: 13
                                font.bold: modelData.act === "go"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    panel.forceActiveFocus()
                                    if (modelData.act === "generate") panel.generate()
                                    else if (modelData.act === "go") panel.go()
                                    else if (modelData.act === "copy") panel.copySettings()
                                    else panel.pasteSettings()
                                }
                            }
                        }
                    }
                }

                Text {
                    objectName: "masterNote"
                    visible: panel.note !== ""
                    text: panel.note
                    color: "#E0B060"
                    font.pixelSize: 12
                    font.italic: true
                }
            }

            Column {
                spacing: 6

                Rectangle {
                    width: map.width + 8; height: map.height + 8
                    color: "#15131A"
                    border.color: "#555555"
                    border.width: 1

                    Canvas {
                        id: map
                        objectName: "masterMap"
                        x: 4; y: 4
                        width: Math.max(160, Math.min(panel.height - 220, panel.width - 440, 520))
                        height: width
                        property var shown: panel.preview
                        onShownChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onPaint: panel.paintMap(getContext("2d"), width, height)
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !panel.preview
                        text: "G shows the dungeon Go enters"
                        color: "#888888"
                        font.pixelSize: 13
                        font.italic: true
                    }
                }
                Text {
                    objectName: "masterCounts"
                    visible: panel.preview !== null
                    width: map.width + 8
                    wrapMode: Text.WordWrap
                    text: panel.preview
                          ? "Seed " + panel.preview.seed + " • " + panel.counts.rooms + " rooms • "
                            + panel.counts.enemies + " enemies • " + panel.counts.breakables
                            + " breakables • " + panel.counts.spike + " spike plates • "
                            + panel.counts.slit + " arrow slits • " + panel.counts.doors + " doors"
                            + (panel.counts.secrets > 0 ? " • " + panel.counts.secrets + " secret rooms" : "")
                          : ""
                    color: "#BBBBBB"
                    font.pixelSize: 12
                }
                Row {
                    spacing: 10
                    Repeater {
                        model: [{ c: "#7FBF7F", t: "weak" }, { c: "#E0C060", t: "normal" },
                                { c: "#E05050", t: "tough" }, { c: "#C77B4A", t: "breakable" },
                                { c: "#D8D8D8", t: "spikes" }, { c: "#FF6A3A", t: "slit" },
                                { c: "#B08040", t: "door" }, { c: "#A070E0", t: "secret" }]
                        delegate: Row {
                            spacing: 3
                            Rectangle { width: 8; height: 8; radius: 4; color: modelData.c; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.t; color: "#888888"; font.pixelSize: 12 }
                        }
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: panel.pad
                  ? "Up/down to pick • left/right to set • " + panel.padLabels.B + " for the game's value • "
                    + panel.padLabels.X + " to generate • " + panel.padLabels.A + " or Start to go"
                  : "W/S to pick • A/D to set • Backspace for the game's value • G to generate • Enter to go"
            color: "#888888"
            font.pixelSize: 12
            font.italic: true
        }
    }

    // The preview, north up as on the minimap: rock, the floor with the
    // start room, the entrance and the exit, then the doors, the secret
    // rooms, the features and the enemies (by tier; a guardian square, a
    // spitter a diamond, a grunt round)
    function paintMap(ctx, w, h) {
        ctx.clearRect(0, 0, w, h)
        let p = preview
        if (!p) return
        let gh = p.grid.length, gw = gh > 0 ? p.grid[0].length : 0
        if (gw === 0) return
        let s = Math.min(w / gw, h / gh)
        let X = gx => gx * s
        let Y = gy => (gh - 1 - gy) * s
        let start = p.rooms[0]
        for (let gy = 0; gy < gh; gy++)
            for (let gx = 0; gx < gw; gx++) {
                if (p.grid[gy][gx] === cellWall) continue
                let inStart = start && gx >= start.x && gx < start.x + start.w
                              && gy >= start.y && gy < start.y + start.h
                ctx.fillStyle = inStart ? "#3E5A44" : "#4A4238"
                ctx.fillRect(X(gx), Y(gy), s, s)
            }
        ctx.fillStyle = "#5A8AD0"
        ctx.fillRect(X(p.entranceGridX), Y(0), s, s)
        ctx.fillStyle = "#E8C35A"
        ctx.fillRect(X(p.exitGridX), Y(gh - 1), s, s)
        ctx.fillStyle = "#B08040"
        for (let d of p.doors) ctx.fillRect(X(d.gx) + s * 0.2, Y(d.gy) + s * 0.2, s * 0.6, s * 0.6)
        ctx.strokeStyle = "#A070E0"
        ctx.lineWidth = 1
        for (let r of p.secrets) {
            if (r.room) ctx.strokeRect(X(r.room.x), Y(r.room.y + r.room.h - 1), r.room.w * s, r.room.h * s)
            ctx.fillStyle = "#A070E0"
            ctx.fillRect(X(r.gx), Y(r.gy), s, s)
        }
        for (let f of p.features) {
            let x = X(f.gx), y = Y(f.gy)
            if (f.kind === "spike") {
                ctx.strokeStyle = "#D8D8D8"
                ctx.lineWidth = Math.max(1, s * 0.18)
                ctx.beginPath()
                ctx.moveTo(x + s * 0.2, y + s * 0.2); ctx.lineTo(x + s * 0.8, y + s * 0.8)
                ctx.moveTo(x + s * 0.8, y + s * 0.2); ctx.lineTo(x + s * 0.2, y + s * 0.8)
                ctx.stroke()
            } else if (f.kind === "slit") {
                ctx.fillStyle = "#FF6A3A"
                ctx.fillRect(x + s * 0.3, y + s * 0.3, s * 0.4, s * 0.4)
            } else {
                ctx.fillStyle = f.kind === "crystal" ? "#6FE0E8" : f.kind === "crate" ? "#9A6B3A" : "#C77B4A"
                ctx.fillRect(x + s * 0.15, y + s * 0.15, s * 0.7, s * 0.7)
            }
        }
        for (let e of p.enemies) {
            let cx = e.x / cellSize * s, cy = (gh - e.y / cellSize) * s, r = Math.max(2, s * 0.45)
            ctx.fillStyle = ["#7FBF7F", "#E0C060", "#E05050"][e.tier]
            ctx.beginPath()
            if (e.type === "guardian") ctx.rect(cx - r, cy - r, 2 * r, 2 * r)
            else if (e.type === "spitter") {
                ctx.moveTo(cx, cy - r * 1.2); ctx.lineTo(cx + r * 1.2, cy)
                ctx.lineTo(cx, cy + r * 1.2); ctx.lineTo(cx - r * 1.2, cy); ctx.closePath()
            } else ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.fill()
        }
    }

    Keys.onPressed: (event) => {
        // M goes on to the game and mutes; no other key reaches the knight
        if (event.key === Qt.Key_M) return
        event.accepted = true
        if (event.key === Qt.Key_W || event.key === Qt.Key_Up) {
            selectedIndex = Math.max(0, selectedIndex - 1)
        } else if (event.key === Qt.Key_S || event.key === Qt.Key_Down) {
            selectedIndex = Math.min(rows.length - 1, selectedIndex + 1)
        } else if (event.key === Qt.Key_A || event.key === Qt.Key_Left) {
            turn(-1)
        } else if (event.key === Qt.Key_D || event.key === Qt.Key_Right) {
            turn(1)
        } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
            let r = rows[selectedIndex]
            if (r) unset(r.key)
        } else if (event.key === Qt.Key_G) {
            generate()
        } else if (event.key === Qt.Key_C) {
            copySettings()
        } else if (event.key === Qt.Key_V) {
            pasteSettings()
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                   || event.key === Qt.Key_Space) {
            go()
        }
    }
    // Releases stay here too: the game's controller must not see half a key
    Keys.onReleased: (event) => { if (event.key !== Qt.Key_M) event.accepted = true }
}
