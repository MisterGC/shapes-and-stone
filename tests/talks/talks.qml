// Talks bench - lost travellers sit afraid by a vein and miners dig
// beside it; talked to, either leaves with its line (issue #176).
//
// The dungeon on 20 seeds, each at a low, a middle and a high danger,
// built twice: the same travellers on the same spots, of the same kind;
// each in a room but the start room that holds a vein, at most one a
// room, its feet on a room's floor - no figure stands in a wall - in
// front of the rock face beside one of its room's veins, off a vein, a
// hole, a torch, a slit, a secret and a feature's cell; both kinds among
// them; none in the camp nor in the fight room. Then in the dojo's deep
// scenario, paused and single-stepped: a miner, a lost one and a special
// stand on the floor, the lost one trembling; the pickaxe aimed at a
// traveller starts no dig. The miner digs only while a knight is within
// digReach: its strikes, its tink and the room's hole counting them, so
// the chance a gem cut there wakes the hole rises by wakePerDig a strike;
// on a seed whose clean gem alone leaves the hole asleep, the gem cut
// after the miner dug wakes it, and the same gem cut after the miner was
// talked off does not. E beside the lost one, the miner and the special
// talks to each: it says its line - the lost one one of lostLines, the
// miner one of minerLines, the special its own - the chord plays, it
// walks off fading and is gone; the miner stops digging, the hole stays
// asleep, and the special joins the camps for good, kept with the
// record. A miner still there when the hole's first wave comes flees,
// without the chord. A talk the host gets for one gone already changes
// nothing, and a talk the host refuses stops the line and leaves the
// traveller to be talked to again. Prints one PASS or FAIL line per check and exits with the
// number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/talks/talks.qml

import QtQuick
import QtQuick.Window
import QtTest
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
    readonly property var tc: Balance.deep.traveller
    readonly property var hc: Balance.deep.hole
    readonly property int seeds: 20
    readonly property var dangers: [0.3, 1.6, 2.8]
    readonly property real dt: 1 / 60

    function check(ok, what) {
        console.log("[Talks]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function pressE() { keys.keyClick(Qt.Key_E, Qt.NoModifier, -1) }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Talks] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                  recordStoreName: "ShapesAndStoneTalksBench"})
        script.steps = [[() => game.screen === "title", () => {
            // No specials with the camps: the deep room's special is the
            // first of the table
            game.freedCamp.store.set("specials", "[]")
            game.freedCamp.load()
        }]].concat(placementSteps()).concat(talkSteps)
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
    function traveller(kind) { return game.deepTravellers.find(s => s.kind === kind && s.special === "") }
    function special() { return game.deepTravellers.find(s => s.special !== "") }
    function vein() { return game.veins[0] }
    function hole() { return game.holes[0] }
    // A fresh deep room, paused, the knight out of reach of harm
    function freshRoom(seed) {
        Clayground.paused = true
        game.applyScenario("deep", 3, seed)
        game.forceActiveFocus()
        game.player.hp = 100000
        step(1)
    }
    // The value of the deep room's gem cut all clean
    function cleanValue() {
        let v = vein()
        return game.gemValue(v.shape, v.strikes, v.strikes)
    }
    // The first seed from the scenario's whose deep room's vein, cut all
    // clean, wakes its hole by itself (dug false), or one whose clean gem
    // alone leaves it asleep but wakes it after at most most strikes of
    // its miner (dug true); its strikes needed with it, {seed, need}
    function seedWhere(dug, most) {
        for (let k = 0; k < 400; k++) {
            game.applyScenario("deep", 3, game.scenarioSeed + k)
            let c = vein().cell, value = cleanValue()
            if (!dug) {
                if (game.holeWakes(c, value)) return { seed: game.scenarioSeed + k, need: 0 }
                continue
            }
            if (game.holeWakes(c, value)) continue
            for (let n = 1; n <= most; n++)
                if (game.holeWakes(c, value, undefined, n)) return { seed: game.scenarioSeed + k, need: n }
        }
        return null
    }
    // The knight stands in front of the vein, the mouse on it: the next
    // step begins the dig
    function aimAtVein() {
        let p = game.player, v = vein()
        game.endDig()
        p.xWu = v.faceXWu - p.widthWu / 2
        p.yWu = v.cyWu - v.sizeWu / 2 - 0.6 + p.heightWu / 2
        game.aimOverride = { x: v.faceXWu, y: v.faceYWu }
        step(1)
        return game.dig !== null && game.dig.vein === v
    }
    // Every strike of the vein clean, each on its close
    function cutClean() {
        let v = vein(), beat = Math.round(Balance.deep.ringTime / dt), n = 0
        while (!v.split && game.dig && n < 10) {
            let close = Math.floor(game.dig.t / Balance.deep.ringTime + 1e-6) + 1
            stepTo(close * beat)
            game.pressPick()
            n++
        }
        game.aimOverride = null
        return v.split
    }
    // The knight stands just below t, a traveller or a vein, near enough
    // to talk to it or to dig it
    function standBy(t) {
        let p = game.player
        let x = t.midXWu !== undefined ? t.midXWu : t.faceXWu
        let y = t.footYWu !== undefined ? t.footYWu : t.cyWu - t.sizeWu / 2
        game.endDig()
        game.aimOverride = null
        p.xWu = x - p.widthWu / 2
        p.yWu = y - 0.3 + p.heightWu / 2
        step(1)
    }
    // The knight far off, out of every traveller's digReach
    function standAway() {
        let p = game.player
        game.endDig()
        game.aimOverride = null
        p.yWu -= tc.digReach + 3
        step(1)
    }
    function eventsOf(cell) { return game.deepTravellerEvents.filter(e => e.cell === cell).map(e => e.what) }
    function soundsSince(n) {
        let k = game.deepTravellerSoundCount - n
        return k > 0 ? game.deepTravellerSounds.slice(-k) : []
    }
    // Whether the point (x, y) in wu lies on a room's floor cell
    function onFloor(x, y) {
        let gx = Math.floor(x / game.cellSize), gy = Math.floor(y / game.cellSize)
        return game.grid[gy] !== undefined && game.grid[gy][gx] === game.cellRoom
    }

    // ---- placement ----
    property var placed: ({ builds: 0, same: 0, travellers: 0, miners: 0, lost: 0, veinRooms: 0, broken: [] })
    function lines() {
        return game.deepTravellers.map(s => s.cell + ":" + s.kind + ":" + s.special + ":" + s.footXWu.toFixed(3)
                                            + ":" + s.footYWu.toFixed(3) + ":" + s.holeCell).sort()
    }
    function placementBroken() {
        let out = [], g = game.grid
        let off = {}, floor = {}
        for (let f of game.features) {
            if (f.kind === "slit") off[(f.gx - f.dx) + "," + (f.gy - f.dy)] = "a slit"
            if (f.kind === "vein") off[f.wgx + "," + f.wgy] = "a vein"
            floor[f.gx + "," + f.gy] = f.kind
        }
        for (let h of game.holes) off[h.cell] = "a hole"
        let seen = game.deepTravellers.length
        game.rooms.forEach((room, ri) => {
            let veins = game.features.filter(f => f.kind === "vein" && f.gx >= room.x && f.gx < room.x + room.w
                                                  && f.gy >= room.y && f.gy < room.y + room.h)
            let mine = game.deepTravellers.filter(s => s.roomIndex === ri)
            seen -= mine.length
            if (ri === 0 || veins.length === 0) {
                if (mine.length > 0) out.push("room " + ri + " without a vein has a traveller")
                return
            }
            placed.veinRooms++
            if (mine.length > 1) out.push("room " + ri + " has " + mine.length + " travellers")
            for (let s of mine) {
                let c = s.cell.split(",").map(Number)
                if (!onFloor(s.footXWu, s.footYWu) || !onFloor(s.footXWu, s.footYWu + 0.05))
                    out.push(s.cell + ": its feet " + s.footXWu.toFixed(2) + "," + s.footYWu.toFixed(2)
                             + " are not on a room's floor")
                if (Math.floor(s.footXWu / game.cellSize) !== c[0] || Math.floor(s.footYWu / game.cellSize) !== c[1] - 1)
                    out.push(s.cell + " is not in front of its rock face")
                if (g[c[1]][c[0]] !== game.cellWall || g[c[1] - 1][c[0]] !== game.cellRoom)
                    out.push(s.cell + " is no wall face over a room's cell")
                if (!veins.some(v => v.wgy === c[1] && Math.abs(v.wgx - c[0]) >= 1
                                     && Math.abs(v.wgx - c[0]) <= Balance.deep.rockCells))
                    out.push(s.cell + " is not a rock face beside a vein of its room")
                if (off[s.cell]) out.push(s.cell + " is on " + off[s.cell])
                if (floor[c[0] + "," + (c[1] - 1)]) out.push(s.cell + " stands on a " + floor[c[0] + "," + (c[1] - 1)])
                if (game._torchCells[s.cell]) out.push(s.cell + " is on a torch")
                if (game._secretOf(c[0], c[1]) >= 0) out.push(s.cell + " is on a secret")
                if (s.outcome !== "" || s.gone) out.push(s.cell + " is gone already")
                let h = game.holes.find(h => h.veinCells.some(v => veins.some(f => f.wgx + "," + f.wgy === v)))
                if ((h ? h.cell : "") !== s.holeCell) out.push(s.cell + " has the hole " + s.holeCell)
            }
        })
        if (seen !== 0) out.push(seen + " travellers in no room")
        return out
    }
    function placementSteps() {
        let out = []
        for (let i = 0; i < seeds; i++) {
            for (let dg of dangers) {
                out.push([30, () => {
                    let seed = 2000 + i * 7919
                    game.applyScenario("dungeon", dg, seed)
                    let a = lines()
                    for (let why of placementBroken()) placed.broken.push("seed " + seed + " danger " + dg + ": " + why)
                    placed.travellers += a.length
                    placed.miners += game.deepTravellers.filter(s => s.kind === "miner").length
                    placed.lost += game.deepTravellers.filter(s => s.kind === "lost").length
                    game.applyScenario("dungeon", dg, seed)
                    placed.builds++
                    if (JSON.stringify(lines()) === JSON.stringify(a)) placed.same++
                }])
            }
        }
        out.push([30, () => {
            check(placed.builds === seeds * dangers.length && placed.same === placed.builds,
                  "the same seed and danger place the same travellers, kinds and spots on " + placed.same + " of "
                  + placed.builds + " dungeons (" + seeds + " seeds at danger " + dangers.join(", ") + ")")
            check(placed.broken.length === 0 && placed.travellers > 0,
                  placed.travellers + " travellers in " + placed.veinRooms + " rooms with a vein, at most one a room, "
                  + "each with its feet on the room's floor - none in a wall - in front of its vein's rock face, off "
                  + "a vein, a hole, a torch, a slit, a secret and a feature, with its room's hole; none in a room "
                  + "without a vein"
                  + (placed.broken.length ? ": " + placed.broken.length + " not, e.g. " + placed.broken.slice(0, 3).join("; ") : ""))
            check(placed.miners > 0 && placed.lost > 0,
                  "both kinds among them: " + placed.miners + " miners, " + placed.lost + " lost travellers")
            let camps = 0
            for (let i = 0; i < 5; i++) {
                game.applyScenario("village", i * 2, 2000 + i * 7919)
                camps += game.deepTravellers.length
            }
            game.applyScenario("fight")
            check(camps === 0 && game.deepTravellers.length === 0,
                  "no traveller in the camp (5 camps: " + camps + ") nor in the fight room (" + game.deepTravellers.length + ")")
        }])
        return out
    }

    // ---- digging and talking ----
    property var talkSteps: [
        [100, () => {
            freshRoom()
            let m = traveller("miner"), l = traveller("lost"), sp = special()
            check(game.deepTravellers.length === 3 && m && l && sp
                  && game.deepTravellers.every(s => onFloor(s.footXWu, s.footYWu) && s.outcome === "" && !s.gone),
                  "the dojo's deep scenario shows a miner (" + (m ? m.cell : "none") + "), a lost one ("
                  + (l ? l.cell : "none") + ") and a special (" + (sp ? sp.special : "none")
                  + ") on the floor before the vein's rock face, none in a wall")
            check(l.afraid && l.huddled && !m.afraid && !m.huddled,
                  "the lost one sits huddled and trembles with fear (afraid " + l.afraid + "), the miner stands")
            // The pickaxe is the vein's alone
            let p = game.player
            game.endDig()
            p.xWu = m.midXWu - p.widthWu / 2
            p.yWu = m.footYWu - 0.3 + p.heightWu / 2
            game.aimOverride = { x: m.midXWu, y: m.midYWu }
            step(1)
            check(game.dig === null && !p.digging, "the mouse aimed at the miner starts no dig")
            game.aimOverride = null

            // The miner digs only while a knight is near
            standAway()
            let h = hole(), before = game.deepTravellerSoundCount
            seconds(tc.digEvery * 3)
            check(!m.digging && m.digs === 0 && h.dug === 0,
                  "with no knight within " + tc.digReach + " wu the miner does not dig: " + m.digs + " strikes")
            standBy(vein())
            // Its first strike digEvery after the knight came, raise and a
            // tenth of a second to swing it, then one every digEvery
            let span = tc.digEvery * 5 + tc.raise + 0.3, down = 1
            for (let i = 0; i < Math.round(span / dt); i++) {
                step(1)
                down = Math.min(down, m.swing)
            }
            let digs = soundsSince(before).filter(x => x === "dig").length
            check(m.digging && m.digs === 5 && down < 0.1 && digs === 5,
                  "a knight near, it digs beside the vein with its own pick: " + m.digs + " strikes in "
                  + span.toFixed(1) + " s, the pick raised and swung down (" + down.toFixed(2)
                  + "), the tink " + digs + " times")
            let value = cleanValue()
            let base = game.holeWakeChance(value), raised = game.holeWakeChance(value, undefined, h.dug)
            check(h.dug === m.digs && h.stage === "rest"
                  && Math.abs(raised - base - hc.wakePerDig * h.dug) < 1e-9,
                  "its strikes count toward waking the room's hole: " + h.dug + " counted, the chance a clean "
                  + vein().shape + " wakes it " + base.toFixed(3) + " -> " + raised.toFixed(3) + ", the hole at rest")
            Clayground.paused = false
        }],
        [100, () => {
            // The miner's digging wakes a hole the gem alone would not
            let found = seedWhere(true, 12)
            check(found !== null, "a seed whose clean gem alone leaves the hole asleep, its miner's "
                  + (found ? found.need : "?") + " strikes not: " + (found ? found.seed : "none"))
            if (!found) return
            freshRoom(found.seed)
            let m = traveller("miner"), h = hole()
            standBy(vein())
            let k = 0
            while (h.dug < found.need && k++ < 60 * 30) step(1)
            aimAtVein()
            let cut = cutClean()
            check(cut && h.dug >= found.need && h.stage !== "rest",
                  "after the miner dug " + h.dug + " strikes the clean gem wakes the hole: " + h.stage)
            // The same gem with the miner talked off first sleeps on
            freshRoom(found.seed)
            m = traveller("miner")
            h = hole()
            standBy(m)
            pressE()
            step(1)
            aimAtVein()
            cut = cutClean()
            check(cut && m.outcome === "leaving" && h.dug === 0 && h.stage === "rest",
                  "the miner talked off first: the same clean gem leaves the hole asleep (" + h.stage + ", "
                  + h.dug + " strikes counted)")
            Clayground.paused = false
        }],
        [100, () => {
            freshRoom()
            let m = traveller("miner"), l = traveller("lost"), sp = special(), h = hole()
            // The lost one, with E
            standBy(l)
            check(l.talkable && !m.talkable && game.deepTravellerToTalk() === l,
                  "beside the lost one \"[E] Talk\" shows over it alone")
            let sounds = game.deepTravellerSoundCount
            pressE()
            check(l.outcome === "leaving" && tc.lostLines.indexOf(l.saying) >= 0 && !l.talkable
                  && eventsOf(l.cell).join() === "talked,leaving",
                  "E talks to it: it says \"" + l.saying + "\" and leaves (" + eventsOf(l.cell).join(", ") + ")")
            seconds(tc.chordDelay + dt)
            check(soundsSince(sounds).indexOf("chord") >= 0 && !l.huddled && !l.afraid,
                  tc.chordDelay + " s later the chord plays (" + soundsSince(sounds).join() + "), and it stands to go")
            let x0 = l.footXWu, y0 = l.footYWu
            seconds(tc.fadeAfter + tc.fade / 2)
            let moved = Math.hypot(l.footXWu - x0, l.footYWu - y0), mid = l.fade
            seconds(tc.fade)
            check(moved > 0.5 && mid > 0 && mid < 1 && l.gone && eventsOf(l.cell).join() === "talked,leaving,gone",
                  "it walks off (" + moved.toFixed(2) + " wu), fading (" + mid.toFixed(2) + "), and is gone: "
                  + eventsOf(l.cell).join(", "))

            // The miner, with E: it stops digging
            standBy(m)
            seconds(tc.digEvery * 2)
            let dug = m.digs
            pressE()
            check(m.outcome === "leaving" && tc.minerLines.indexOf(m.saying) >= 0 && !m.digging,
                  "E talks the miner into leaving, the deep too dangerous: \"" + m.saying + "\", digging " + m.digging)
            seconds(tc.fadeAfter + tc.fade + 2)
            check(m.gone && m.digs === dug && h.dug === dug && eventsOf(m.cell).join() === "talked,leaving,gone",
                  "it digs no more (" + m.digs + " strikes, the hole counted " + h.dug + ") and is gone: "
                  + eventsOf(m.cell).join(", "))
            check(h.stage === "rest" && game.holeEvents.length === 0,
                  "talking never wakes the room's hole: " + h.stage)

            // The special, with E: it joins the camps for good
            let joinedBefore = game.freedCamp.joined.length
            standBy(sp)
            pressE()
            let kept = JSON.parse(game.freedCamp.store.get("specials", "[]"))
            let who = game.freedCamp.specialOf(sp.special)
            check(sp.outcome === "leaving" && sp.saying === who.line && joinedBefore === 0
                  && game.freedCamp.joined.indexOf(sp.special) >= 0 && kept.indexOf(sp.special) >= 0,
                  "E talks to the special, " + who.name + ": it says its own line and joins the camps for good, "
                  + "kept with the record (" + kept.join(", ") + ")")
            seconds(tc.fadeAfter + tc.fade + 2)
            check(sp.gone, "and walks off, gone")

            // A talk the host gets for one gone already changes nothing
            game._hostTalk(game.knightIdOf(game.player), game.levelIndex, l.cell)
            check(eventsOf(l.cell).join() === "talked,leaving,gone" && l.outcome === "leaving",
                  "a talk that comes for one gone already changes nothing: " + eventsOf(l.cell).join(", "))
            pressE()
            check(game.deepTravellerEvents.filter(e => e.what === "talked").length === 3,
                  "E with none left near talks to no one")
            Clayground.paused = false
        }],
        [100, () => {
            // A talk the host refuses - shown on this screen, as a joiner
            // shows its own at once - stops the line, and the traveller
            // stays to be talked to again
            freshRoom()
            let l = traveller("lost")
            standBy(l)
            game._deepRuns[l.cell].talked = true
            game._deepSay(l, "leaving")
            game._deepEvent(l, "talked")
            let said = l.saying
            game._talkRefused(l.cell)
            step(1)
            check(said !== "" && l.saying === "" && l.outcome === "" && !l.gone && game.talksRefused === 1
                  && game.deepTravellerToTalk() === l && l.talkable && eventsOf(l.cell).join() === "talked,refused",
                  "a talk the host refuses stops its line and it stays, to be talked to again: "
                  + eventsOf(l.cell).join(", ") + ", talkable " + l.talkable)
            pressE()
            check(l.outcome === "leaving" && eventsOf(l.cell).join() === "talked,refused,talked,leaving",
                  "E then talks it into leaving: " + eventsOf(l.cell).join(", "))
            Clayground.paused = false
        }],
        [100, () => {
            // A miner still there flees once the hole's first wave comes
            let found = seedWhere(false, 0)
            freshRoom(found ? found.seed : game.scenarioSeed)
            let m = traveller("miner"), h = hole()
            aimAtVein()
            cutClean()
            let sounds = game.deepTravellerSoundCount
            let k = 0
            while (h.wave < 1 && k++ < 60 * 20) step(1)
            check(found !== null && h.wave >= 1 && m.outcome === "fleeing" && tc.fleeLines.indexOf(m.saying) >= 0,
                  "on a seed whose clean gem wakes the hole the miner flees as its first wave comes: " + m.outcome
                  + ", \"" + m.saying + "\"")
            seconds(tc.fadeAfter + tc.fade + 0.5)
            check(m.gone && eventsOf(m.cell).join() === "fleeing,gone" && soundsSince(sounds).indexOf("chord") < 0,
                  "and is gone, without the chord: " + eventsOf(m.cell).join(", "))
            Clayground.paused = false
            console.log("[Talks] done,", failures, "failed")
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
                    console.log("[Talks] FAIL step", i, "timed out")
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
