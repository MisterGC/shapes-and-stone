import QtQuick
import Clayground.Sound

// A song of the sound factory (sound/music/*.song.json, a cue of
// sound/cues.json) as the game's music: clay_sound plays it live, and
// its segment goes on into itself until it is halted, in the browser as
// on the desktop. start() and halt() take the place of play() and
// stop(); the volume is set as level
SongPlayer {
    id: song
    property real level: 1
    volume: level
    property bool wanted: false
    function start() {
        wanted = true
        if (!playing) play()
    }
    function halt() {
        wanted = false
        stop()
    }
}
