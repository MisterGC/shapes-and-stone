// Sound bench - starts the game the way a native build does, outside the
// dojo, and checks that you hear it and that M mutes it (issue #31).
//
// The game is created without setting `muted`, the way Main.qml creates it.
// It must start audible, play the title music, and play the dungeon music
// once single player starts. M must mute every track and show the mute
// icon; M again must bring the sound and the icon back. Prints one PASS or
// FAIL line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/sound/sound.qml

import QtQuick
import QtQuick.Window
import QtTest

Window {
    id: bench
    width: 800
    height: 600
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0

    function check(ok, what) {
        console.log("[Sound]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    // Sends M the way a keyboard does, to whatever has the focus
    TestEvent { id: keys }
    function pressM() { keys.keyClick(Qt.Key_M, Qt.NoModifier, -1) }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Sound] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600})
        script.start()
    }

    // Every Music and Sound in the item tree under `root`, by file name
    function tracks(root, out) {
        out = out || {}
        let src = root.source !== undefined ? String(root.source) : ""
        if (src.endsWith(".mp3") || src.endsWith(".wav"))
            out[src.substring(src.lastIndexOf("/") + 1)] = root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) tracks(kids[i], out)
        return out
    }
    function find(root, name) {
        if (root.objectName === name) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = find(kids[i], name)
            if (f) return f
        }
        return null
    }
    function heard(t) { return t.volume > 0 }
    function silent(all) {
        for (let n in all) if (all[n].volume > 0) return false
        return true
    }

    property var steps: [
        [() => game.screen === "title", () => {
            let t = tracks(game)
            check(!game.muted, "a start outside the dojo is not muted")
            check(t["title_music.mp3"] && t["title_music.mp3"].playing && heard(t["title_music.mp3"]),
                  "the title music plays and is heard")
            game.screen = "game"
            game.forceActiveFocus()
        }],
        [() => game.player && tracks(game)["dungeon_music.mp3"].playing, () => {
            let t = tracks(game)
            check(heard(t["dungeon_music.mp3"]), "the dungeon music plays and is heard (volume "
                  + t["dungeon_music.mp3"].volume + ")")
            check(t["dungeon_ambience.mp3"].playing && heard(t["dungeon_ambience.mp3"]),
                  "the dungeon ambience plays and is heard")
            check(!find(game, "muteIcon").visible, "no mute icon while the sound is on")
            pressM()
        }],
        [100, () => {
            check(game.muted, "M mutes the game")
            check(silent(tracks(game)), "M silences every track and sound")
            check(find(game, "muteIcon").visible, "the mute icon shows while muted")
            pressM()
        }],
        [100, () => {
            let t = tracks(game)
            check(!game.muted, "M again unmutes the game")
            check(heard(t["dungeon_music.mp3"]), "the dungeon music is heard again")
            check(!find(game, "muteIcon").visible, "the mute icon goes away again")
            console.log("[Sound] done,", failures, "failed")
        }],
        // Torn down before quitting, as the impact bench does
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ]

    Timer {
        id: script
        property int i: 0
        property real waitedMs: 0
        interval: 20
        repeat: true
        onTriggered: {
            let step = bench.steps[i]
            waitedMs += interval
            let ready = typeof step[0] === "number" ? waitedMs >= step[0] : step[0]()
            if (!ready) {
                if (waitedMs > 20000) {
                    console.log("[Sound] FAIL step", i, "timed out")
                    Qt.exit(failures + 1)
                    stop()
                }
                return
            }
            waitedMs = 0
            // Advance first: a key click spins the event loop, and this
            // timer must not run the same step again inside it
            i++
            if (i >= bench.steps.length) stop()
            step[1]()
        }
    }
}
