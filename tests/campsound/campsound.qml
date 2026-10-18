// Camp sound bench - the camp's sounds sit where they come from, and the
// music steps back while every knight rests (issue #147).
//
// In the camp, the world paused and stepped one physics step at a time:
// the campfire's crackle plays at its source, and the knight hears it
// quieter the further it stands from the fire, from beside it to the
// cave's far edge, where it is silent and plays no more. Standing still by
// the fire the knight sits after Balance.camp.sitAfter; the music keeps
// its level until the knight has stood still Balance.camp.restQuiet
// seconds, is at camp.sounds.restMusic of it fadeDown seconds later, and
// the crackle comes forward to restNear times its gain; one press of D
// brings the music back to its level in fadeUp. The anvil rings only while
// the smith stands at it hammering. Each look - the grotto at depth 0, the
// hall at 4, the ember camp at 7 - has its own near sound on every one of
// 12 seeds, placed at its props, and a knight beside one hears it play. M
// silences the camp's sounds and its music, M again brings them back.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/campsound/campsound.qml

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Common
import "../../src"

Window {
    id: bench
    width: 1000
    height: 600
    visible: true
    color: "#1a1a2e"

    property var game: null
    property var fire: null
    property var cs: null
    property int failures: 0
    readonly property var cfg: Balance.camp.sounds
    readonly property var seeds: Array.from({ length: 12 }, (v, i) => 1000 + 7919 * i)
    readonly property var depths: ({ grotto: 0, hall: 4, ember: 7 })

    function check(ok, what) {
        console.log("[CampSound]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[CampSound] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 1000, height: 600,
                                                  recordStoreName: "ShapesAndStoneCampSoundBench"})
        script.start()
    }

    readonly property real stepS: game ? game.physics.timeStep : 1 / 60
    function steps(seconds) { return Math.round(seconds / stepS) }
    function run(seconds) { Clayground.physicsStep(steps(seconds)) }

    // Every Music, Sound and SfxPlayer in the item tree under root, by file name
    function tracks(root, out) {
        out = out || {}
        let src = root.source !== undefined ? String(root.source) : ""
        if (src.endsWith(".mp3") || src.endsWith(".wav") || src.endsWith(".sfx.json"))
            out[src.substring(src.lastIndexOf("/") + 1)] = root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) tracks(kids[i], out)
        return out
    }
    function put(x, y) {
        let p = game.player
        p.xWu = x
        p.yWu = y
        p.body.linearVelocity = Qt.point(0, 0)
        Clayground.physicsStep(1)
    }
    // The middle of the camp's floor cell furthest from the fire
    function farEdge() {
        let best = null, bestD = -1, s = game.cellSize
        for (let gy = 0; gy < game.grid.length; gy++)
            for (let gx = 0; gx < game.grid[gy].length; gx++) {
                if (game.grid[gy][gx] !== game.cellRoom) continue
                let x = (gx + 0.5) * s, y = (gy + 0.5) * s
                let d = Math.hypot(x - fire.xWu, y - fire.yWu)
                if (d > bestD) { bestD = d; best = Qt.point(x, y) }
            }
        return best
    }
    function music() { return tracks(game)["village_music.mp3"] }
    function campReady() { return game.player && game.levelType === "village" && game.campfire && !game.resetting }
    function looks() { return cs.sources.filter(s => s.name === game.campLook.name) }

    property int seedAt: 0
    property string lookAt: "grotto"
    // Per look, the seeds whose camp has none of its own sound
    property var missing: ({ grotto: [], hall: [], ember: [] })

    property var script_steps: [
        [() => game.width > 0, () => game.applyScenario("village", 0)],
        [() => campReady(), () => {
            fire = game.campfire
            cs = game.campSounds
            game.muted = false
            game.forceActiveFocus()
            Clayground.paused = true
            let names = cs.sources.map(s => s.name)
            check(names.filter(n => n === "crackle").length === 1
                  && cs.sources[0].x === fire.xWu && cs.sources[0].y === fire.yWu,
                  "the crackle sits at the campfire (" + names.join(", ") + ")")
            // The distance: beside the fire, then further, to the far edge
            let p = game.player
            p.sitAfter = 1e9
            let edge = farEdge()
            let at = [1.5, 5, 9, 13].map(d => Qt.point(fire.xWu - d, fire.yWu)).concat([edge])
            let gains = [], counts = [], heard = []
            for (let q of at) {
                put(q.x, q.y)
                let before = cs.played.crackle || 0
                cs.lastGain.crackle = 0
                run(2)
                gains.push(cs.gainOf("crackle"))
                counts.push((cs.played.crackle || 0) - before)
                heard.push(cs.lastGain.crackle)
            }
            let falling = gains.every((g, i) => i === 0 || g < gains[i - 1] || (g === 0 && gains[i - 1] === 0))
            let dist = at.map(q => Math.hypot(q.x - fire.xWu, q.y - fire.yWu).toFixed(1))
            check(gains[0] > 0.4 && falling,
                  "the crackle's gain falls with the knight's distance from the fire ("
                  + dist.map((d, i) => d + " wu: " + gains[i].toFixed(3)).join(", ") + ")")
            check(counts.every((n, i) => gains[i] > 0 ? n > 0 && Math.abs(heard[i] - gains[i]) < 1e-9 : n === 0),
                  "wherever it is heard it plays at that gain (crackles per 2 s: " + counts.join(", ") + ")")
            check(gains[gains.length - 1] === 0 && counts[counts.length - 1] === 0,
                  "at the cave's far edge, " + dist[dist.length - 1] + " wu away, it is silent and plays no more")
            // The rest: standing still by the fire
            p.sitAfter = Balance.camp.sitAfter
            put(fire.xWu - 1.5, fire.yWu)
            let level = music().level
            let nearG = cs.gainOf("crackle")
            run(Balance.camp.sitAfter)
            check(p.seated && cs.restFor >= Balance.camp.sitAfter - 1e-6 && !cs.quiet,
                  "after sitAfter (" + Balance.camp.sitAfter + " s) the knight sits, the camp not yet quiet")
            // restQuiet counts from the knight's first still step, the put()
            run(Balance.camp.restQuiet - Balance.camp.sitAfter - 2 * stepS)
            let early = cs.quiet, earlyLevel = music().level
            Clayground.physicsStep(2)
            check(!early && Math.abs(earlyLevel - level) < 1e-6 && cs.quiet,
                  "the music keeps its level (" + level.toFixed(3) + ") until the knight has stood still "
                  + Balance.camp.restQuiet + " s, then the camp is quiet")
            run(cfg.fadeDown)
            let restLevel = music().level
            check(Math.abs(cs.musicShare - cfg.restMusic) < 1e-6 && Math.abs(restLevel - level * cfg.restMusic) < 1e-3,
                  "fadeDown (" + cfg.fadeDown + " s) later the music plays at restMusic of its level ("
                  + level.toFixed(3) + " -> " + restLevel.toFixed(3) + ")")
            check(Math.abs(cs.gainOf("crackle") - Math.min(1, nearG * cfg.restNear)) < 1e-6,
                  "and the crackle comes forward (" + nearG.toFixed(3) + " -> " + cs.gainOf("crackle").toFixed(3) + ")")
            run(5)
            check(cs.quiet && Math.abs(music().level - restLevel) < 1e-6, "resting on, the music stays down")
            keys.keyPress(Qt.Key_D, Qt.NoModifier, -1)
            Clayground.physicsStep(1)
            check(!p.seated && !cs.quiet && cs.restFor === 0, "D stands the knight up and the camp is no longer quiet")
            keys.keyRelease(Qt.Key_D, Qt.NoModifier, -1)
            run(cfg.fadeUp)
            check(Math.abs(music().level - level) < 1e-6 && cs.musicShare === 1,
                  "fadeUp (" + cfg.fadeUp + " s) after the move the music is back at its level ("
                  + music().level.toFixed(3) + ")")
            // The anvil: only while the smith hammers
            let anvil = cs.sources.find(s => s.name === "anvil")
            let smith = game.dungeonObjects.find(o => o && o.objectName === "npc" && o.npcName === "Blacksmith")
            check(!!anvil && !!smith, "the anvil has its sound and the smith stands by")
            p.sitAfter = 1e9
            put(anvil.x, anvil.y - 1.5)
            // His routine runs on the wall clock, which stands while the
            // bench steps: set him at the anvil hammering, then walking off
            let before = cs.played.anvil || 0
            smith._routineIndex = 0
            smith._atDestination = true
            smith._activityTimer = 1e9
            run(4)
            let rang = (cs.played.anvil || 0) - before
            smith._atDestination = false
            smith._routineIndex = 1
            before = cs.played.anvil || 0
            run(4)
            let quietRang = (cs.played.anvil || 0) - before
            check(smith.routine[0].sound === "anvil" && rang > 0 && quietRang === 0,
                  "the anvil rings while the smith hammers (" + rang + " times in 4 s) and not while he walks ("
                  + quietRang + ")")
            smith._activityTimer = 0
            Clayground.paused = false
        }],
        // The smith's routine runs on the wall clock: by now he walked on
        [100, () => {
            // M silences all of it
            Clayground.paused = true
            put(fire.xWu - 1.5, fire.yWu)
            keys.keyClick(Qt.Key_M, Qt.NoModifier, -1)
            let t = tracks(game)
            let camp = ["camp_crackle.wav", "camp_anvil.sfx.json", "camp_drip.sfx.json", "camp_creak.wav", "camp_hiss.wav"]
            check(game.muted && camp.every(n => t[n] && t[n].volume === 0)
                  && t["village_music.mp3"].volume === 0 && t["village_ambience.mp3"].volume === 0,
                  "M silences the camp's near sounds, its music and its ambience")
            keys.keyClick(Qt.Key_M, Qt.NoModifier, -1)
            check(!game.muted && camp.every(n => t[n].volume > 0) && t["village_music.mp3"].volume > 0,
                  "M again brings them back")
            game.player.sitAfter = 1e9
            Clayground.paused = false
            seedAt = 0
            lookAt = "grotto"
            game.applyScenario("village", depths.grotto, seeds[0])
        }],
        // Each look, on every seed: its own near sound at its props
        [() => {
            if (!campReady()) return false
            if (game.campLook.name !== lookAt) return false
            let own = looks()
            if (own.length === 0) missing[lookAt].push(seeds[seedAt])
            if (seedAt === 0) {
                // Beside the first of them it plays
                Clayground.paused = true
                game.muted = false
                if (own.length > 0) {
                    let s = own[0]
                    let kinds = game.campProps.filter(p => cfg.looks[lookAt].props.indexOf(p.kind) >= 0)
                    check(own.every(o => kinds.some(k => k.x === o.x && k.y === o.y)),
                          lookAt + ": its " + own.length + " near sounds sit at its "
                          + cfg.looks[lookAt].props.join(" and ") + " (" + cfg.looks[lookAt].sample + ")")
                    game.player.sitAfter = 1e9
                    put(s.x, s.y + 2)
                    run(2 * cfg.looks[lookAt].every[1])
                    check((cs.played[lookAt] || 0) > 0 && cs.lastGain[lookAt] > 0,
                          lookAt + ": a knight beside one hears it play (" + (cs.played[lookAt] || 0)
                          + " times in " + 2 * cfg.looks[lookAt].every[1] + " s, gain "
                          + (cs.lastGain[lookAt] || 0).toFixed(3) + ")")
                    let others = cs.sources.filter(o => ["crackle", "anvil", lookAt].indexOf(o.name) < 0)
                    check(others.length === 0, lookAt + ": no other look's sound plays here")
                }
                Clayground.paused = false
            }
            seedAt++
            if (seedAt >= seeds.length) {
                check(missing[lookAt].length === 0, lookAt + " at depth " + depths[lookAt]
                      + ": every one of " + seeds.length + " seeds has its own near sound (missing on "
                      + JSON.stringify(missing[lookAt]) + ")")
                let order = ["grotto", "hall", "ember"]
                let next = order.indexOf(lookAt) + 1
                if (next >= order.length) return true
                lookAt = order[next]
                seedAt = 0
            }
            game.applyScenario("village", depths[lookAt], seeds[seedAt])
            return false
        }, () => {
            // Gone before the window: torn down with it, the camp crashes
            // the exit
            game.destroy()
        }],
        [300, () => {
            console.log("[CampSound] done,", failures, "failed")
            Qt.exit(failures)
        }]
    ]

    Timer {
        id: script
        property int i: 0
        property real waitedMs: 0
        interval: 20
        repeat: true
        onTriggered: {
            let step = bench.script_steps[i]
            waitedMs += interval
            let ready = typeof step[0] === "number" ? waitedMs >= step[0] : step[0]()
            if (!ready) {
                if (waitedMs > 60000) {
                    console.log("[CampSound] FAIL step", i, "timed out")
                    Qt.exit(failures + 100)
                    stop()
                }
                return
            }
            waitedMs = 0
            // Advance first: a key click spins the event loop, and this
            // timer must not run the same step again inside it
            i++
            if (i >= bench.script_steps.length) stop()
            step[1]()
        }
    }
}
