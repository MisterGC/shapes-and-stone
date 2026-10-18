import QtQuick
import Clayground.Sound

// An ambience bed of the sound factory (sound/ambience/*.sfx.json, a cue
// of sound/cues.json): a recipe of up to 10 s that fades in and out over
// its first and last 1.5 s, played again every `every` seconds while it
// is wanted, so each take crosses into the next. start() and halt() as
// SongMusic's; a halted bed is silenced at once, the volume is set as
// level
SfxPlayer {
    id: bed
    property real level: 1
    property real every: 8.5
    property bool wanted: false
    volume: wanted ? level : 0
    function start() {
        if (wanted) return
        wanted = true
        play()
        _again.restart()
    }
    function halt() {
        wanted = false
        _again.stop()
    }
    property Timer _again: Timer {
        interval: bed.every * 1000
        repeat: true
        onTriggered: bed.play()
    }
}
