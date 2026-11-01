// Fight music bench - the dungeon's song follows the fight's intensity
// (issue #191, Balance.music).
//
// One knight in a dungeon, the world paused so the enemies keep the state
// the bench gives them. With no enemy after the knight the dungeon song
// plays at intensity 0. Three enemies chasing it near it raise the
// intensity, eased up at Balance.music.rise, to 1, and the song's
// intensity follows the game's; the song renders louder at 1 than at 0,
// its layers in. Two of them giving up let it fall slowly to a third, an
// enemy chasing beyond reach counts for nothing, and in the camp it is 0.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/fightmusic/fightmusic.qml

import QtQuick
import QtQuick.Window
import Clayground.Common
import "../../src"

Window {
    id: bench
    width: 1000
    height: 600
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0

    function check(ok, what) {
        console.log("[FightMusic]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[FightMusic] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 1000, height: 600, muted: true,
                                                  recordStoreName: "ShapesAndStoneFightMusicBench"})
        script.start()
    }

    function song(root) {
        root = root || game
        if (root.source !== undefined && String(root.source).endsWith("music/dungeon.song.json")) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = song(kids[i])
            if (f) return f
        }
        return null
    }
    function alive() { return game.enemies.filter(e => e && !e.destroyed) }
    // Every enemy patrolling far from the knight, the first n chasing it
    // dist world units away
    function set(n, dist) {
        let p = game.player, es = alive()
        for (let i = 0; i < es.length; i++) {
            let near = i < n
            es[i].xWu = p.xWu + (near ? dist : 40 + i)
            es[i].yWu = p.yWu + (near ? 0.3 * i : 40)
            es[i].aiState = near ? "chase" : "patrol"
        }
    }
    function rms(mono, from, to) {
        let sum = 0
        for (let i = from; i < to; i++) sum += mono[i] * mono[i]
        return Math.sqrt(sum / Math.max(1, to - from))
    }
    property real lastIntensity: 0

    property var steps: [
        [() => game.width > 0 && game.screen === "title", () => {
            game.screen = "game"
            game.forceActiveFocus()
        }],
        [() => game.player && song() && song().playing && alive().length >= 3, () => {
            game.player.hp = 100000
            Clayground.paused = true
            set(0, 0)
        }],
        [800, () => {
            let s = song()
            check(game.fightersNear === 0 && game.fightIntensity === 0 && s.intensity === 0,
                  "no enemy after the knight: the dungeon song plays at intensity 0 (" + s.intensity + ")")
            check(s.loaded && s.version === 2 && s.segment === "explore", "it is the dungeon song, in its "
                  + s.segment + " segment")
            set(3, 2)
        }],
        [300, () => {
            let s = song()
            check(game.fightersNear === 3, "three enemies chase the knight near it (" + game.fightersNear + ")")
            check(game.fightIntensity > 0.15 && game.fightIntensity < 1,
                  "the intensity rises, eased, not at once: " + game.fightIntensity.toFixed(2) + " after 0.3 s")
            check(Math.abs(s.intensity - game.fightIntensity) < 1e-6, "the song's intensity follows the game's")
        }],
        [1000, () => {
            let s = song()
            check(game.fightIntensity === 1 && s.intensity === 1, "within a second it is full: "
                  + s.intensity.toFixed(2))
            check(s.playing && s.segment === "explore", "the song plays on through the change")
            // A render plays at the player's volume: heard for the two renders
            game.muted = false
            let quiet = s.renderOffline(8, [{ at: 0, intensity: 0 }])
            let full = s.renderOffline(8, [{ at: 0, intensity: 1 }])
            game.muted = true
            let from = 4 * 44100, to = Math.min(quiet.length, full.length)
            let q = rms(quiet, from, to), f = rms(full, from, to)
            check(to > from && f > q * 1.15, "at intensity 1 the song renders louder than at 0, its layers in (rms "
                  + f.toFixed(4) + " vs " + q.toFixed(4) + ")")
            set(1, 2)
        }],
        [1000, () => {
            check(game.fightersNear === 1, "two give up: one enemy is after the knight")
            check(game.fightIntensity < 1 && game.fightIntensity > 1 / 3 + 0.05,
                  "the intensity falls slowly towards a third: " + game.fightIntensity.toFixed(2) + " after 1 s")
            lastIntensity = game.fightIntensity
            set(1, Balance.music.reach + 2)
        }],
        [300, () => {
            check(game.fightersNear === 0 && game.fightIntensity < lastIntensity,
                  "an enemy chasing beyond reach counts for nothing (" + game.fightersNear + ", "
                  + game.fightIntensity.toFixed(2) + ")")
            Clayground.paused = false
            game._enterLevel(game.levelIndex + 1)
        }],
        [() => game.levelType === "village" && game.player !== null, () => {
            check(game.fightIntensity === 0 && game.fightersNear === 0 && !song().playing,
                  "in the camp the intensity is 0 and the dungeon song is halted")
            console.log("[FightMusic] done,", failures, "failed")
        }],
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
                    console.log("[FightMusic] FAIL step", i, "timed out")
                    Qt.exit(failures + 1)
                    stop()
                }
                return
            }
            waitedMs = 0
            i++
            if (i >= bench.steps.length) stop()
            step[1]()
        }
    }
}
