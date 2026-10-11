import QtQuick
import Clayground.Sound

// A music track that plays on in a loop until it is halted. In the browser
// Clayground's Music ignores loop and ends after one pass (clayground#216),
// so there a track that ends while it is wanted is started again. start()
// and halt() take the place of play() and stop(). The volume is set as
// level: the browser's player takes no volume before its track has loaded
// and plays at full until the next change, so there level is sent again
// once the track plays.
Music {
    id: track
    loop: true

    property real level: 1
    volume: level + _nudge
    property real _nudge: 0
    property Timer _resend: Timer {
        interval: 150
        onTriggered: {
            track._nudge = track.level > 0.5 ? -0.001 : 0.001
            Qt.callLater(() => track._nudge = 0)
        }
    }

    property bool wanted: false
    function start() { wanted = true; play() }
    function halt() { wanted = false; stop() }

    readonly property bool _wasm: Qt.platform.os === "wasm"
    onFinished: if (wanted && _wasm) play()
    // Some players only report that they stopped: try again a moment later,
    // once, if it is still silent then
    onPlayingChanged: {
        if (!_wasm) return
        if (playing) _resend.restart()
        else if (wanted) _again.restart()
    }
    property Timer _again: Timer {
        interval: 300
        onTriggered: if (track.wanted && !track.playing) track.play()
    }
}
