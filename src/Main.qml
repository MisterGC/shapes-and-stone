import QtQuick
import QtQuick.Window

Window {
    visible: true
    visibility: Window.Maximized
    flags: Qt.platform.os === "wasm" ? Qt.FramelessWindowHint : Qt.Window
    title: qsTr("Shapes & Stone")
    color: "#1a1a2e"

    Component.onCompleted: {
        console.log("[Main] Window created - width:", width, "height:", height)
        console.log("[Main] Platform:", Qt.platform.os, "Plugin:", Qt.platform.pluginName)
        if (Qt.platform.pluginName === "minimal") Qt.quit()
    }

    Game {
        anchors.fill: parent
        Component.onCompleted: console.log("[Main] Game component loaded")
    }
}
