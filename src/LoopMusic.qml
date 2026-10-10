import QtQuick
import Clayground.Sound

// A music track that plays on in a loop until it is halted. In the browser
// Clayground's Music ignores loop and ends after one pass (clayground#216),
// so there a track that ends while it is wanted is started again. start()
// and halt() take the place of play() and stop().
Music {
    id: track
    loop: true

    property bool wanted: false
    function start() { wanted = true; play() }
    function halt() { wanted = false; stop() }

    readonly property bool _wasm: Qt.platform.os === "wasm"
    onFinished: if (wanted && _wasm) play()
    // Some players only report that they stopped: try again a moment later,
    // once, if it is still silent then
    onPlayingChanged: if (wanted && _wasm && !playing) _again.restart()
    property Timer _again: Timer {
        interval: 300
        onTriggered: if (track.wanted && !track.playing) track.play()
    }
}
