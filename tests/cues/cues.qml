// Cue bench - checks that the game plays every cue of its cue sheet,
// sound/cues.json, the way the sheet says (issue #190).
//
// For each cue the game must have a player of the cue's file: a Sound of
// the render for a rendered cue, an SfxPlayer of the recipe or a
// SongPlayer of the song for a live one (issue #191), loaded and without
// an error. A live recipe's play() must play a variation and its
// renderOffline() must hold samples, as a song's must. The game's own
// calls must reach them, M must silence them all and M again bring them
// back. Prints one PASS or FAIL line per check and exits with the number
// of failures. Reading the sheet needs QML_XHR_ALLOW_FILE_READ=1.
//
//   QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/cues/cues.qml

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
    property var sheet: null

    function check(ok, what) {
        console.log("[Cues]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function pressM() { keys.keyClick(Qt.Key_M, Qt.NoModifier, -1) }

    // A JSON file under sound/, null when it does not read
    function readSound(path) {
        let xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../sound/" + path), false)
        xhr.send()
        try { return JSON.parse(xhr.responseText) } catch (e) { return null }
    }

    Component.onCompleted: {
        sheet = readSound("cues.json")
        if (!sheet) {
            console.log("[Cues] FAIL sound/cues.json does not read (QML_XHR_ALLOW_FILE_READ=1?)")
            Qt.exit(1)
            return
        }
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Cues] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600})
        script.start()
    }

    // Every player in the item tree under `root` whose source is in the
    // sound folder, by its path there ("sfx/deep_chink.wav")
    function players(root, out) {
        out = out || {}
        let src = root.source !== undefined ? String(root.source) : ""
        let at = src.indexOf("/sound/")
        if (at >= 0) out[src.substring(at + 7)] = root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) players(kids[i], out)
        return out
    }
    // A live cue is a recipe's SfxPlayer or a song's SongPlayer
    function live(p) { return p.layers !== undefined || song(p) }
    function song(p) { return p.segment !== undefined }
    function ready(p) { return live(p) ? p.loaded : p.status === 2 }
    function cues() { return Object.keys(sheet.cues).sort() }
    function file(cue) { let c = sheet.cues[cue]; return c.mode === "live" ? c.source : c.render }
    function allReady() {
        let p = players(game)
        return cues().every(c => p[file(c)] && (ready(p[file(c)]) || p[file(c)].error))
    }

    property var steps: [
        [() => game.screen === "title" && allReady(), () => {
            let p = players(game)
            check(cues().length > 0, "the cue sheet lists " + cues().length + " cues")
            for (let c of cues()) {
                let cue = sheet.cues[c], pl = p[file(c)]
                check(pl && live(pl) === (cue.mode === "live"),
                      c + " (" + cue.mode + ") is played by " + (cue.mode === "live" ? "an SfxPlayer of " : "a Sound of ")
                      + file(c))
                if (!pl) continue
                check(ready(pl) && !(live(pl) && pl.error), c + " is loaded" + (pl.error ? ": " + pl.error : ""))
                if (song(pl)) {
                    let mono = pl.renderOffline(1)
                    check(pl.version === 2 && mono.length > 0,
                          c + " is a version 2 song and renders " + mono.length + " samples")
                } else if (live(pl)) {
                    let seed = pl.play()
                    let mono = pl.renderOffline(seed)
                    check(pl.lastSeed === seed && mono.length > 0,
                          c + " plays seed " + seed + " of its " + pl.pool + " and renders " + mono.length + " samples")
                }
            }
            // A designed cue (issue #195): its design file, the template
            // its provenance names, sits beside the recipe it compiles to
            let designed = cues().filter(c => sheet.cues[c].provenance && sheet.cues[c].provenance.template)
            check(designed.length > 0, designed.length + " cues come from design files: " + designed.join(", "))
            for (let c of designed) {
                let t = sheet.cues[c].provenance.template, d = readSound(t.design)
                check(d && d.template.id === t.id && d.template.version === t.version
                      && t.design.replace(/\.sfx\.design\.json$/, ".sfx.json") === sheet.cues[c].source,
                      c + "'s design " + t.design + " is on the template " + t.id + " " + t.version
                      + ", beside its recipe " + sheet.cues[c].source)
            }
            game.screen = "game"
            game.forceActiveFocus()
        }],
        [() => game.player, () => {
            let p = players(game)
            let crumble = p["sfx/deep_crumble.sfx.json"], rumble = p["sfx/deep_rumble.sfx.json"]
            let groan = p["sfx/deep_groan.sfx.json"]
            let before = [crumble.lastSeed, rumble.lastSeed, groan.lastSeed]
            game.playCrumble(0.5)
            game.playHoleSound("rumble", null)
            game.playHoleSound("groan", null)
            check(crumble.lastSeed !== before[0] && rumble.lastSeed !== before[1] && groan.lastSeed !== before[2],
                  "the game's own calls play the crumble, the rumble and the groan from their recipes")
            let n = game.veinSoundCount
            game.playChink(-1)
            game.playTink(4)
            check(game.veinSoundCount === n + 2, "the game plays the chink and the tink from their recipes, transposed")
            let tink = p["sfx/deep_tink.sfx.json"], seed = tink.variationSeed(0)
            let up = tink.renderOffline(seed, 1, 4), plain = tink.renderOffline(seed)
            check(up.length > 0 && up.length === plain.length && up[200] !== plain[200],
                  "a tink played 4 semitones up is the same length and other samples")
            pressM()
        }],
        [100, () => {
            let p = players(game)
            // The title's song goes with the title screen
            let gone = cues().filter(c => !p[file(c)])
            check(gone.join(",") === "music/title", "in the game every cue's player is there but the title's ("
                  + gone.join(", ") + ")")
            check(game.muted && cues().every(c => !p[file(c)] || p[file(c)].volume === 0), "M silences every cue")
            pressM()
        }],
        [100, () => {
            let p = players(game)
            // The heartbeat is heard only while the knight is low on
            // health, the camp's ambience only in the camp
            let quiet = ["sfx/heartbeat", "ambience/village", "music/title"]
            let still = cues().filter(c => quiet.indexOf(c) < 0 && !(p[file(c)] && p[file(c)].volume > 0))
            check(!game.muted && still.length === 0,
                  "M again brings them back" + (still.length > 0 ? ", but not " + still.join(", ") : ""))
            console.log("[Cues] done,", failures, "failed")
        }],
        // Torn down before quitting, as the sound bench does
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
                    console.log("[Cues] FAIL step", i, "timed out")
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
