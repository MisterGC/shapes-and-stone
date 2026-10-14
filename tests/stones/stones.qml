// Stones bench - petrified miners and lost travellers stand in a vein's
// rock face, and the same strikes free them (issue #158).
//
// The dungeon on 20 seeds, each at a low, a middle and a high danger,
// built twice: the same travellers on the same cells, of the same kind and
// strikes; each in a room but the start room that holds a vein, at most
// one a room, in the face of its north wall beside one of its veins (its
// rock face) over a room's cell, off a vein, a hole, a torch, a slit and a
// secret; both kinds among them; none in the camp nor in the fight room.
// Then in the dojo's deep scenario, paused and single-stepped, the
// knight's pickaxe on the left button: a miner and a lost one stand
// there, stone; off-beat strikes on the miner never harm it - no strike
// counted or taken back, not freed, the ring started over each time -
// and clean ones free it, with the shell's crumble and then the chord,
// the colour back over colourTime, and the room's spawn hole never woken
// by them; the freed miner says a line, walks to the vein and works there,
// its tink part of the room's sound, and is still there seconds later;
// the freed lost one says a line, walks off and fades out of sight. In a
// fresh room a miner freed after the hole's creatures came flees, and in
// another a miner at work flees once the hole's first wave comes. From
// the #173 review: a freed miner nods before it walks to its work, one
// freed far from the knight crumbles quieter, and a freeing the host
// refuses turns the figure back to stone. Prints
// one PASS or FAIL line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/stones/stones.qml

import QtQuick
import QtQuick.Window
import Clayground.Common
import "../../src"

Window {
    id: bench
    width: 1000
    height: 760
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0
    readonly property var sc: Balance.deep.stone
    readonly property var hc: Balance.deep.hole
    readonly property int seeds: 20
    readonly property var dangers: [0.3, 1.6, 2.8]
    readonly property real dt: 1 / 60

    function check(ok, what) {
        console.log("[Stones]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Stones] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                  recordStoreName: "ShapesAndStoneStonesBench"})
        script.steps = [[() => game.screen === "title", () => {}]].concat(placementSteps()).concat(freeSteps)
        script.start()
    }

    // Halts every enemy the hole sent, so none walks off its spot
    function haltAll() { for (let e of game.enemies) if (e && !e.destroyed && !e.halted) e.halt() }
    function step(n) {
        for (let i = 0; i < n; i++) {
            Clayground.physicsStep(1)
            haltAll()
        }
    }
    function seconds(s) { step(Math.round(s / dt)) }
    // Steps until the dig has run n steps
    function stepTo(n) {
        let k = 0
        while (game.dig && game.dig.t < n * dt - 1e-6 && k++ < 4000) step(1)
    }
    function stone(kind) { return game.stones.find(s => s.kind === kind) }
    function vein() { return game.veins[0] }
    function hole() { return game.holes[0] }
    // A fresh deep room, paused, the knight out of reach of harm
    function freshRoom() {
        Clayground.paused = true
        game.applyScenario("deep", 3)
        game.forceActiveFocus()
        game.player.hp = 100000
        step(1)
    }
    // The knight stands in front of t's face and the mouse aims at it:
    // the next step begins the dig
    function aimAt(t) {
        let p = game.player
        game.endDig()
        p.xWu = t.faceXWu - p.widthWu / 2
        p.yWu = t.cyWu - t.sizeWu / 2 - 0.6 + p.heightWu / 2
        game.aimOverride = { x: t.faceXWu, y: t.faceYWu }
        step(1)
        return game.dig !== null && game.dig.target === t
    }
    // Every strike of t clean, each on its close; the strikes made
    function strikeClean(t, ringTime) {
        let beat = Math.round(ringTime / dt), n = 0
        while (!(t.split || t.freed) && n < 10) {
            let close = Math.floor(game.dig.t / ringTime + 1e-6) + 1
            stepTo(close * beat)
            game.pressPick()
            n++
        }
        return n
    }
    function eventsOf(cell) { return game.stoneEvents.filter(e => e.cell === cell).map(e => e.what) }
    function soundsSince(n) {
        let k = game.stoneSoundCount - n
        return k > 0 ? game.stoneSounds.slice(-k) : []
    }

    // ---- placement ----
    property var placed: ({ builds: 0, same: 0, stones: 0, miners: 0, lost: 0, veinRooms: 0, broken: [] })
    function stoneLines() { return game.stones.map(s => s.cell + ":" + s.kind + ":" + s.strikes + ":" + s.holeCell).sort() }
    function stonesBroken() {
        let out = [], g = game.grid, cs = game.cellSize
        let off = {}
        for (let f of game.features) {
            if (f.kind === "slit") off[(f.gx - f.dx) + "," + (f.gy - f.dy)] = "a slit"
            if (f.kind === "vein") off[f.wgx + "," + f.wgy] = "a vein"
        }
        for (let h of game.holes) off[h.cell] = "a hole"
        let seen = game.stones.length
        game.rooms.forEach((room, ri) => {
            let veins = game.features.filter(f => f.kind === "vein" && f.gx >= room.x && f.gx < room.x + room.w
                                                  && f.gy >= room.y && f.gy < room.y + room.h)
            let mine = game.stones.filter(s => s.roomIndex === ri)
            seen -= mine.length
            if (ri === 0 || veins.length === 0) {
                if (mine.length > 0) out.push("room " + ri + " without a vein has a traveller")
                return
            }
            placed.veinRooms++
            if (mine.length > 1) out.push("room " + ri + " has " + mine.length + " travellers")
            for (let s of mine) {
                let c = s.cell.split(",").map(Number)
                if (g[c[1]][c[0]] !== game.cellWall || g[c[1] - 1][c[0]] !== game.cellRoom)
                    out.push(s.cell + " is no wall face over a room's cell")
                if (!veins.some(v => v.wgy === c[1] && Math.abs(v.wgx - c[0]) >= 1 && Math.abs(v.wgx - c[0]) <= cfgRock()))
                    out.push(s.cell + " is not in a rock face beside a vein of its room")
                if (off[s.cell]) out.push(s.cell + " is on " + off[s.cell])
                if (game._torchCells[s.cell] || game.torches.some(t => Math.floor(t.xWu / cs) === c[0]
                                                                       && Math.floor(t.yWu / cs) === c[1]))
                    out.push(s.cell + " is on a torch")
                if (game._secretOf(c[0], c[1]) >= 0) out.push(s.cell + " is on a secret")
                if (s.freed || s.colour !== 0 || s.strikes < sc.strikes[0] || s.strikes > sc.strikes[1])
                    out.push(s.cell + " is freed or has " + s.strikes + " strikes")
                let h = game.holes.find(h => h.veinCells.some(v => veins.some(f => f.wgx + "," + f.wgy === v)))
                if ((h ? h.cell : "") !== s.holeCell) out.push(s.cell + " has the hole " + s.holeCell)
            }
        })
        if (seen !== 0) out.push(seen + " travellers in no room")
        return out
    }
    function cfgRock() { return Balance.deep.rockCells }
    function placementSteps() {
        let out = []
        for (let i = 0; i < seeds; i++) {
            for (let dg of dangers) {
                out.push([30, () => {
                    let seed = 2000 + i * 7919
                    game.applyScenario("dungeon", dg, seed)
                    let a = stoneLines()
                    for (let why of stonesBroken()) placed.broken.push("seed " + seed + " danger " + dg + ": " + why)
                    placed.stones += a.length
                    placed.miners += game.stones.filter(s => s.kind === "miner").length
                    placed.lost += game.stones.filter(s => s.kind === "lost").length
                    game.applyScenario("dungeon", dg, seed)
                    placed.builds++
                    if (JSON.stringify(stoneLines()) === JSON.stringify(a)) placed.same++
                }])
            }
        }
        out.push([30, () => {
            check(placed.builds === seeds * dangers.length && placed.same === placed.builds,
                  "the same seed and danger place the same travellers, kinds and strikes on " + placed.same + " of "
                  + placed.builds + " dungeons (" + seeds + " seeds at danger " + dangers.join(", ") + ")")
            check(placed.broken.length === 0 && placed.stones > 0,
                  placed.stones + " travellers in " + placed.veinRooms + " rooms with a vein, at most one a room, each "
                  + "in its vein's rock face over a room's cell, off a vein, a hole, a torch, a slit and a secret, "
                  + "stone, with its room's hole; none in a room without a vein"
                  + (placed.broken.length ? ": " + placed.broken.length + " not, e.g. " + placed.broken.slice(0, 3).join("; ") : ""))
            check(placed.miners > 0 && placed.lost > 0,
                  "both kinds among them: " + placed.miners + " miners, " + placed.lost + " lost travellers")
            let camps = 0
            for (let i = 0; i < 5; i++) {
                game.applyScenario("village", i * 2, 2000 + i * 7919)
                camps += game.stones.length
            }
            game.applyScenario("fight")
            check(camps === 0 && game.stones.length === 0,
                  "no traveller in the camp (5 camps: " + camps + ") nor in the fight room (" + game.stones.length + ")")
        }])
        return out
    }

    // ---- freeing ----
    property var freeSteps: [
        [100, () => {
            freshRoom()
            let m = stone("miner"), l = stone("lost")
            check(game.stones.length === 2 && m && l && !m.freed && !l.freed && m.colour === 0 && l.colour === 0,
                  "the dojo's deep scenario shows a petrified miner (" + (m ? m.cell : "none") + ") and a lost one ("
                  + (l ? l.cell : "none") + ") in the vein's rock face, stone")

            // Off-beat strikes never harm it: the ring starts over
            check(aimAt(m) && game.dig.stone === m && !game.dig.vein,
                  "the aim on the miner in reach begins its dig, the pickaxe out")
            let half = Math.round(sc.ringTime / dt / 2), resets = 0, n = 6
            for (let i = 0; i < n; i++) {
                stepTo(half)
                game.pressPick()
                if (game.dig.t === 0 && !game.lastStrike.clean) resets++
            }
            check(m.misses === n && m.clean === 0 && !m.freed && m.outcome === "" && m.colour === 0
                  && resets === n && game.dig && game.dig.target === m,
                  n + " off-beat strikes on the miner: " + m.misses + " off the beat, " + m.clean
                  + " counted, not freed, the ring started over " + resets + " times")
            // A clean strike after them counts, and none is taken back
            stepTo(Math.round(sc.ringTime / dt))
            game.pressPick()
            let one = m.clean
            stepTo(Math.round(sc.ringTime / dt) * 3 / 2)
            game.pressPick()
            check(one === 1 && m.clean === 1 && m.misses === n + 1 && game.dig.t === 0,
                  "a clean strike counts (" + one + "), an off-beat one after it takes none back (" + m.clean + ")")

            // Clean strikes free it
            let sounds = game.stoneSoundCount, veinBefore = game.veinSoundCount
            strikeClean(m, sc.ringTime)
            let crumbled = game.veinSounds.slice(-(game.veinSoundCount - veinBefore)).indexOf("crumble") >= 0
            check(m.freed && m.clean === m.strikes && crumbled,
                  "clean strikes free the miner (" + m.clean + " of " + m.strikes + ") with the shell's crumble")
            seconds(sc.chordDelay + dt)
            check(soundsSince(sounds).join() === "chord" && m.colour > 0 && m.colour < 1,
                  sc.chordDelay + " s later the chord plays (" + soundsSince(sounds).join() + "), the colour coming back ("
                  + m.colour.toFixed(2) + ")")
            seconds(sc.colourTime)
            check(m.colour === 1 && m.outcome === "working" && sc.minerLines.indexOf(m.saying) >= 0,
                  "after colourTime its colour is back (" + m.colour + ") and it goes back to work: " + m.outcome
                  + ", \"" + m.saying + "\"")
            // It nods to the knight where it stood, then walks (#173 review)
            let nodded = 0, stood = true, fx = m.footXWu, fy = m.footYWu
            for (let i = 0; i < Math.round(sc.nod / dt) + 2; i++) {
                step(1)
                nodded = Math.max(nodded, m.nod)
                if (m.nod > 0 && Math.hypot(m.footXWu - fx, m.footYWu - fy) > 1e-6) stood = false
            }
            check(nodded > 0.9 && stood && m.nod === 0,
                  "it nods to the knight (" + nodded.toFixed(2) + ") over " + sc.nod + " s where it stood, then walks")
            seconds(5)
            let w = game._workSpot(m), workSounds = 0
            let before = game.stoneSoundCount
            seconds(sc.workEvery * 3 + 0.1)
            workSounds = soundsSince(before).filter(x => x === "work").length
            check(Math.abs(m.footXWu - w.x) < 1e-6 && Math.abs(m.footYWu - w.y) < 1e-6 && !m.walking && !m.gone,
                  "it works beside the vein, at " + m.footXWu.toFixed(2) + "," + m.footYWu.toFixed(2)
                  + " (the vein at " + vein().cxWu.toFixed(2) + ")")
            check(workSounds >= 3 && workSounds <= 4,
                  "its tink is part of the room's sound: " + workSounds + " in " + (sc.workEvery * 3).toFixed(1) + " s")
            seconds(10)
            check(m.outcome === "working" && !m.gone && m.fade === 1 && eventsOf(m.cell).join() === "freed,working",
                  "10 s later it is still at work in the room: " + eventsOf(m.cell).join(", "))
            check(hole().stage === "rest" && game.holeEvents.length === 0,
                  "the strikes on the miner never woke the room's spawn hole: " + hole().stage)

            // The lost one
            check(aimAt(l), "the aim on the lost one begins its dig")
            strikeClean(l, sc.ringTime)
            check(l.freed && l.clean === l.strikes && l.misses === 0, "clean strikes free the lost one ("
                  + l.clean + " of " + l.strikes + ")")
            game.aimOverride = null
            seconds(sc.colourTime + 0.1)
            check(l.outcome === "leaving" && sc.lostLines.indexOf(l.saying) >= 0,
                  "it thanks the knight and leaves: " + l.outcome + ", \"" + l.saying + "\"")
            let x0 = l.footXWu, y0 = l.footYWu
            seconds(sc.fadeAfter + sc.fade / 2)
            let moved = Math.hypot(l.footXWu - x0, l.footYWu - y0), mid = l.fade
            seconds(sc.fade)
            check(moved > 0.5 && mid > 0 && mid < 1 && l.gone && eventsOf(l.cell).join() === "freed,leaving,gone",
                  "it walks off (" + moved.toFixed(2) + " wu), fading (" + mid.toFixed(2) + "), and is gone: "
                  + eventsOf(l.cell).join(", "))
            check(hole().stage === "rest", "the strikes on the lost one never woke the hole either")
            Clayground.paused = false
        }],
        [100, () => {
            // From the #173 review: one freed far from the knight crumbles
            // quieter, as its chord is; a freeing the host refuses turns
            // the figure back to stone
            freshRoom()
            let l = stone("lost"), p = game.player
            p.yWu -= 12
            step(1)
            let c = game._knightCentre(), d = Math.hypot(l.footXWu - c.x, l.footYWu + 0.6 - c.y)
            let want = Math.max(hc.quietest, 1 - d / hc.hearReach)
            game._freeMoment(l)
            check(l.freed && Math.abs(game.crumbleGain - want) < 1e-6 && want < 0.6,
                  "a traveller freed " + d.toFixed(1) + " wu off crumbles at " + game.crumbleGain.toFixed(2)
                  + " (the chord's gain " + want.toFixed(2) + "), not 1")
            seconds(sc.colourTime)
            game._stoneRefused(l.cell)
            check(!l.freed && l.colour === 0 && l.clean === 0 && l.outcome === "" && game.stonesRefused === 1
                  && eventsOf(l.cell).join() === "freed,refused",
                  "a freeing the host refuses turns it back to stone: freed " + l.freed + ", colour " + l.colour
                  + ", " + eventsOf(l.cell).join(", "))
            seconds(1)
            check(l.colour === 0 && !l.freed && l.outcome === "", "and it stays stone, to be freed again")
            Clayground.paused = false
        }],
        [100, () => {
            // A miner freed after the hole's creatures came flees
            freshRoom()
            let m = stone("miner"), v = vein(), h = hole()
            aimAt(v)
            strikeClean(v, Balance.deep.ringTime)
            let k = 0
            while (h.wave < 1 && k++ < 60 * 20) step(1)
            check(v.split && h.wave >= 1, "the vein cut clean wakes the hole and its first wave comes (wave " + h.wave + ")")
            aimAt(m)
            strikeClean(m, sc.ringTime)
            seconds(sc.colourTime + 0.1)
            check(m.freed && m.outcome === "fleeing" && sc.fleeLines.indexOf(m.saying) >= 0,
                  "a miner freed after the hole's creatures came flees: " + m.outcome + ", \"" + m.saying + "\"")
            seconds(sc.fadeAfter + sc.fade + 0.2)
            check(m.gone && eventsOf(m.cell).join() === "freed,fleeing,gone", "and is gone: " + eventsOf(m.cell).join(", "))
            Clayground.paused = false
        }],
        [100, () => {
            // A miner at work flees once the hole's first wave comes
            freshRoom()
            let m = stone("miner"), v = vein(), h = hole()
            aimAt(m)
            strikeClean(m, sc.ringTime)
            seconds(sc.colourTime + 4)
            let working = m.outcome === "working" && !m.walking
            aimAt(v)
            strikeClean(v, Balance.deep.ringTime)
            let k = 0
            while (h.wave < 1 && k++ < 60 * 20) step(1)
            let atWave = m.outcome
            seconds(sc.say + sc.fadeAfter + sc.fade + 2)
            check(working && atWave === "fleeing" && m.gone && eventsOf(m.cell).join() === "freed,working,fleeing,gone",
                  "a miner at work (" + working + ") flees as the hole's first wave comes (" + atWave + ") and is gone: "
                  + eventsOf(m.cell).join(", "))
            game.aimOverride = null
            Clayground.paused = false
            console.log("[Stones] done,", failures, "failed")
            game.destroy()
        }],
        [300, () => Qt.exit(failures)]
    ]

    Timer {
        id: script
        property var steps: []
        property int i: 0
        property real waitedMs: 0
        interval: 20
        repeat: true
        onTriggered: {
            let step = steps[i]
            waitedMs += interval
            let ready = typeof step[0] === "number" ? waitedMs >= step[0] : step[0]()
            if (!ready) {
                if (waitedMs > 20000) {
                    console.log("[Stones] FAIL step", i, "timed out")
                    Qt.exit(failures + 1)
                    stop()
                }
                return
            }
            waitedMs = 0
            i++
            if (i >= steps.length) stop()
            step[1]()
        }
    }
}
