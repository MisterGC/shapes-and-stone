import QtQuick
import QtQuick.Window

Window {
    visible: true
    visibility: Window.Maximized
    flags: Qt.platform.os === "wasm" ? Qt.FramelessWindowHint : Qt.Window
    title: qsTr("Shapes & Stone")
    color: "#1a1a2e"

    Game { anchors.fill: parent }

    Component.onCompleted: if (Qt.platform.pluginName === "minimal") Qt.quit()
}
