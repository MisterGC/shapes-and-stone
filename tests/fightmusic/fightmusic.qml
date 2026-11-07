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
// What a bench hears (issue #267): muted, with logSounds on, a sound played
// is a row of soundLog with its cue, what, pitch, distance, gain and the
// physicsSeconds it played at; with followFightOnSteps on the intensity
// stands while no physics step runs and moves with the steps, and
// musicTrace gets a row once it has moved musicTraceStep.
// A duel (issue #273, Balance.duel): a room's lead patrolling near the
// knight is none; as it spots the knight it growls and the song's state is
// its duel part, which the song moves to on the next bar where an audio
// output runs it (with none its playhead stands, clayground#507, and the
// segment is skipped); a parry in the duel and the lead's opening each
// sting once, the opening plays the slow motion - the physics at
// slowScale for slowTime of the physics clock, the same steps every run -
// a lock on the lead closes the view in to duel.zoom round the knight, which
// stays where it is on screen, a lock on an enemy that is no lead does not,
// with hitStopMode "view" (a session's) the opening's slow motion is a hit
// stop of the picture with the physics at full speed, and the lead's fall
// brings the flow part back.
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
    property var duelLead: null
    property real segmentWait: 0
    property real positionBefore: 0
    // The close-in (Balance.duel.zoom): the knight's centre in the game's
    // own coordinates, through the canvas' scale, and how long to wait for
    // the zoom to run its zoomTime
    property point knightAt: Qt.point(0, 0)
    property var other: null
    readonly property int zoomWait: Balance.duel.zoomTime * 1000 + 400
    property point leadAt: Qt.point(0, 0)
    function onScreen(item) {
        return item.parent.mapToItem(game, item.x + item.width * 0.5, item.y + item.height * 0.5)
    }
    function knightOnScreen() { return onScreen(game.player) }
    function r3(v) { return Math.round(v * 1000) / 1000 }
    function lastSound() { return game.soundLog[game.soundLog.length - 1] }

    property var steps: [
        [() => game.width > 0 && game.screen === "title", () => {
            game.screen = "game"
            game.forceActiveFocus()
        }],
        [() => game.player && song() && song().playing && alive().length >= 3, () => {
            game.player.hp = 100000
            Clayground.paused = true
            // The plain fight first: no room's lead among them
            for (let e of alive()) e.lead = false
            set(0, 0)
        }],
        [800, () => {
            let s = song()
            check(game.fightersNear === 0 && game.fightIntensity === 0 && s.intensity === 0,
                  "no enemy after the knight: the dungeon song plays at intensity 0 (" + s.intensity + ")")
            check(s.loaded && s.version === 2 && s.segment === "flow" && s.state === "flow",
                  "it is the dungeon song, in its " + s.segment + " part")
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
            check(s.playing && s.segment === "flow", "the song plays on through the change")
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
            // The sound log, muted: one row per sound played
            game.logSounds = true
            game.clearSoundLog()
            game.physicsSeconds = 0
            Clayground.physicsStep(3)
            game.playImpact()
            let row = lastSound()
            check(game.soundLog.length === 1 && row.cue === "sfx/punch_hitting" && row.what === "hit"
                  && row.pitch === 0 && row.dist === 0 && row.gain === 1 && row.t === r3(game.physicsSeconds)
                  && row.t > 0,
                  "muted, a blow's sound is a row of the sound log at physicsSeconds: " + JSON.stringify(row))
            game.playBlock(undefined, true)
            row = lastSound()
            check(row.cue === "sfx/shield_clang" && row.what === "perfectBlock"
                  && row.pitch === Balance.perfectBlock.pitch, "a perfect block's clang logs its pitch: "
                  + JSON.stringify(row))
            let p = game.player
            game.playScream(p.xWu + 3, p.yWu, 2)
            row = lastSound()
            check(row.cue === "sfx/goblin_scream" && row.pitch === Balance.scream.tierPitch[2]
                  && Math.abs(row.dist - 3) < 0.01 && Math.abs(row.gain - (1 - 3 / game.remoteHearingWu)) < 0.01,
                  "a tough enemy's scream 3 wu off logs its pitch, distance and gain: " + JSON.stringify(row))
            // The intensity on the physics steps: three enemies chase, and
            // without a step it stands
            game.followFightOnSteps = true
            set(3, 2)
            lastIntensity = game.fightIntensity
        }],
        [400, () => {
            check(game.fightIntensity === lastIntensity, "with followFightOnSteps the intensity stands "
                  + "while no physics step runs (" + game.fightIntensity.toFixed(3) + ")")
            // Stepped one at a time, the three held chasing: their AI
            // runs on the steps too
            let from = game.musicTrace.length
            for (let n = 0; n < 10; n++) {
                set(3, 2)
                Clayground.physicsStep(1)
            }
            let eased = Math.min(1, lastIntensity + 10 / 60 * Balance.music.rise)
            check(Math.abs(game.fightIntensity - eased) < 0.01,
                  "and rises with the steps, at Balance.music.rise: " + lastIntensity.toFixed(3) + " to "
                  + game.fightIntensity.toFixed(3) + " in 10 steps (" + eased.toFixed(3) + ")")
            let rows = game.musicTrace.slice(from)
            let moved = rows.find(m => Math.abs(m.intensity - lastIntensity) >= game.musicTraceStep)
            check(moved !== undefined && moved.song === "music/dungeon" && moved.segment === "flow"
                  && moved.playing === true && moved.t > 0 && moved.t <= r3(game.physicsSeconds),
                  "the music trace gets a row once the intensity has moved musicTraceStep: "
                  + JSON.stringify(moved) + ", " + rows.length + " rows")
            // A room's lead, patrolling 3 wu off the knight, the others away
            set(0, 0)
            duelLead = alive()[0]
            duelLead.lead = true
            duelLead.xWu = game.player.xWu + 3
            duelLead.yWu = game.player.yWu
            duelLead.aiState = "patrol"
            game.clearSoundLog()
            game.physicsSeconds = 0
            // Followed without a step, on which its AI would spot the knight
            game._followFight(0)
            check(!game.duelEngaged && song().state === "flow",
                  "a room's lead patrolling near the knight is no duel: the song's state is " + song().state)
            duelLead.aiState = "chase"
            let growl = game.soundLog.find(r => r.what === "growl")
            check(growl !== undefined && growl.cue === "sfx/lead_growl" && Math.abs(growl.dist - 3) < 0.01
                  && game.soundLog.filter(r => r.cue === "sfx/lead_growl").length === 1,
                  "as it spots the knight the lead growls once, 3 wu off: " + JSON.stringify(growl))
            Clayground.physicsStep(1)
            let trace = game.musicTrace.find(m => m.state === "duel")
            check(game.duelEngaged && game.duelLead === duelLead && song().state === "duel" && trace !== undefined
                  && trace.t === r3(game.physicsSeconds),
                  "on the next physics step the song's state is its duel part, in the music trace at "
                  + (trace ? trace.t : "-") + " s: " + JSON.stringify(trace))
            segmentWait = Date.now()
            positionBefore = song().position
        }],
        // The song moves on its next bar, on the audio output's clock
        [() => song().segment === "duel" || Date.now() - segmentWait > 4000, () => {
            let s = song()
            if (s.segment === "duel")
                check(true, "the song moves to its duel part on the next bar (" + (Date.now() - segmentWait)
                      + " ms)")
            else if (s.position === positionBefore)
                console.log("[FightMusic] SKIP no audio output runs the song (its playhead stands at "
                            + s.position + "), so its segment stays " + s.segment + " (clayground#507)")
            else
                check(false, "the song moves to its duel part on the next bar: still " + s.segment
                      + " after 4 s, its playhead moving")
            // A parry in the duel stings, and one more at once does not
            let from = game.soundLog.length
            game.countFight("parry")
            game.countFight("parry")
            let stings = game.soundLog.slice(from).filter(r => r.what === "sting")
            check(stings.length === 1 && stings[0].cue === "music/dungeon",
                  "a parry in the duel plays the song's sting, two in a moment one: " + JSON.stringify(stings))
            Clayground.physicsStep(30)
            from = game.soundLog.length
            duelLead.open("parry")
            stings = game.soundLog.slice(from).filter(r => r.what === "sting")
            check(duelLead.opening && stings.length === 1, "the lead's opening stings: " + JSON.stringify(stings))
            let d = Balance.duel
            check(game.slowing && Math.abs(game.slowLeft - d.slowTime) < 1e-9
                  && Math.abs(game.physics.timeScale - Clayground.timeScale * d.slowScale) < 1e-6,
                  "the opening plays the slow motion: the physics at " + game.physics.timeScale.toFixed(2)
                  + " for " + game.slowLeft.toFixed(3) + " s of the physics clock")
            let steps = Math.round(d.slowTime * 60)
            Clayground.physicsStep(steps - 1)
            let still = game.slowing
            Clayground.physicsStep(1)
            check(still && !game.slowing && game.physics.timeScale === Clayground.timeScale,
                  "it ends on the " + steps + "th physics step (slowTime " + d.slowTime + " s), the time scale "
                  + game.physics.timeScale + " again")
            // A lock on the lead closes the view in round the knight
            knightAt = knightOnScreen()
            leadAt = onScreen(duelLead)
            game.player.lockTarget = duelLead
        }],
        [zoomWait, () => {
            let d = Balance.duel, at = knightOnScreen(), lead = onScreen(duelLead)
            check(game.player.lockedOn && Math.abs(game.viewZoom - d.zoom) < 1e-3,
                  "a lock on the lead closes the view in to " + game.viewZoom.toFixed(3) + " within zoomTime "
                  + d.zoomTime + " s (duel.zoom " + d.zoom + ")")
            check(Math.hypot(at.x - knightAt.x, at.y - knightAt.y) <= 1,
                  "the knight stays where it is on screen: (" + knightAt.x.toFixed(1) + ", " + knightAt.y.toFixed(1)
                  + ") before, (" + at.x.toFixed(1) + ", " + at.y.toFixed(1) + ") zoomed")
            let apart = Math.hypot(leadAt.x - knightAt.x, leadAt.y - knightAt.y)
            let zoomed = Math.hypot(lead.x - at.x, lead.y - at.y)
            check(apart > 50 && Math.abs(zoomed / apart - d.zoom) < 0.01,
                  "and the lead 3 wu off is drawn " + (zoomed / apart).toFixed(3) + " times as far from it ("
                  + apart.toFixed(1) + " px, " + zoomed.toFixed(1) + " px)")
            game.player.lockTarget = null
        }],
        [zoomWait, () => {
            check(Math.abs(game.viewZoom - 1) < 1e-3, "letting go of the lock opens the view out to "
                  + game.viewZoom.toFixed(3))
            // A lock on an enemy that is no lead, 4 wu off, does not
            other = alive().find(e => e !== duelLead)
            other.lead = false
            other.xWu = game.player.xWu
            other.yWu = game.player.yWu + 4
            game.player.lockTarget = other
        }],
        [zoomWait, () => {
            check(game.player.lockedOn && game.player.lockTarget === other && Math.abs(game.viewZoom - 1) < 1e-3,
                  "a lock on an enemy that is no lead leaves the view at " + game.viewZoom.toFixed(3))
            game.player.lockTarget = null
            other.xWu = game.player.xWu + 40
            other.yWu = game.player.yWu + 40
            // In a session the opening's slow motion is the picture's: a
            // view hit stop, the simulation at full speed. The lead's
            // opening runs out first, so it opens again
            Clayground.physicsStep(Math.ceil(Balance.lead.openingTime * 60) + 6)
            let wasOpen = duelLead.opening
            game.hitStopMode = "view"
            duelLead.xWu = game.player.xWu + 3
            duelLead.yWu = game.player.yWu
            duelLead.open("parry")
            check(!wasOpen && duelLead.opening && game.hitStopActive && !game.slowing
                  && game.physics.timeScale === Clayground.timeScale,
                  "with hitStopMode view the opening's slow motion is a hit stop of the picture ("
                  + game.hitStopActive + "), not of the physics: slowing " + game.slowing + ", time scale "
                  + game.physics.timeScale)
            game.hitStopMode = "physics"
            // The lead falls: the flow part again
            duelLead.die()
            Clayground.physicsStep(1)
            check(!game.duelEngaged && song().state === "flow"
                  && game.musicTrace[game.musicTrace.length - 1].state === "flow",
                  "the lead falls: the song's state is its flow part again, in the trace at "
                  + game.musicTrace[game.musicTrace.length - 1].t + " s")
            game.followFightOnSteps = false
            game.logSounds = false
            set(0, 0)
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
