// Holes bench - a vein's room has a spawn hole, and a gem cut from its
// vein wakes it by chance (issues #157, #175).
//
// The dungeon on 20 seeds, each at a low, a middle and a high danger,
// built twice: the same holes on the same cells; each room but the start
// room that holds a vein has one hole and no other room has one, in the
// face of its north wall over a room's cell, off its veins, a torch, a
// slit and a secret, most gap cells or more from each vein and only a
// few in a small room on a vein's rock face; none in the camp nor in
// the fight room. The dojo's
// deep scenario shows a hole at rest. Then in the deep scenario, paused
// and single-stepped, on a seed whose roll leaves the hole asleep and on
// one whose roll wakes it: the strikes wake nothing before the gem is
// cut; on the first the cut gem leaves it at rest; on the second the cut
// wakes it through its stages in order - dust with the rumble at the
// cut, eyes with the groan eyesAfter later - the first creature crawls
// out no sooner than enemy.minTelegraph (and telegraph) after the eyes;
// waves waves of perWave creatures come from the hole's cell, and then
// it closes with the crumble, and a gem cut after that wakes nothing.
// Then the share (issue #175): the dungeon on 40 seeds at a shallow and a
// deep danger, the game's roll for 1 to 4 knights of the first vein of
// each hole cut all chipped and all clean - the share of woken holes
// rises with the gem's worth and with the knights (unless every chance
// stands at wakeMost already) and lies near the mean of holeWakeChance;
// on 10 of the seeds the game's own cut for 2 knights, built twice,
// wakes the holes its roll says, the same both times.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/holes/holes.qml

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
    readonly property var cfg: Balance.deep
    readonly property var hc: Balance.deep.hole
    readonly property int seeds: 20
    readonly property var dangers: [0.3, 1.6, 2.8]
    readonly property real dt: 1 / 60
    readonly property int beat: Math.round(cfg.ringTime / dt)

    function check(ok, what) {
        console.log("[Holes]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function veinPoint() {
        let v = vein()
        return v.mapToItem(game, v.width / 2, v.height * (1 - v.faceWu / v.sizeWu / 2))
    }
    function aimVein() {
        let p = veinPoint()
        keys.mouseMove(game, p.x, p.y, -1, Qt.NoButton, Qt.NoModifier)
    }
    function strike() {
        let p = veinPoint()
        keys.mouseClick(game, p.x, p.y, Qt.LeftButton, Qt.NoModifier, -1)
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Holes] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                  recordStoreName: "ShapesAndStoneHolesBench"})
        script.steps = [[() => game.screen === "title", () => {}]].concat(placementSteps()).concat(wakeSteps)
            .concat(shareSteps()).concat(endSteps)
        script.start()
    }

    function vein() { return game.veins[0] }
    function hole() { return game.holes[0] }
    // Halts every enemy the holes sent, so none walks off its spot
    function haltAll() { for (let e of game.enemies) if (e && !e.destroyed && !e.halted) e.halt() }
    function step(n) {
        for (let i = 0; i < n; i++) {
            Clayground.physicsStep(1)
            haltAll()
        }
    }
    // Steps until the dig has run n steps
    function stepTo(n) {
        let k = 0
        while (game.dig && game.dig.t < n * dt - 1e-6 && k++ < 4000) step(1)
    }
    function freshDig(depth, seed) {
        Clayground.paused = true
        game.applyScenario("deep", depth, seed)
        game.forceActiveFocus()
        aimVein()
        step(1)
    }
    function eventsOf(cell) { return game.holeEvents.filter(e => e.cell === cell) }
    function whats(list) { return list.map(e => e.what) }
    function soundsSince(n) {
        let k = game.holeSoundCount - n
        return k > 0 ? game.holeSounds.slice(-k) : []
    }
    function creatures(cell) { return game.enemies.filter(e => e && !e.destroyed && e.fromHole === cell) }

    // ---- placement ----
    property var placed: ({ builds: 0, same: 0, holes: 0, veinRooms: 0, far: 0, onRock: 0, broken: [], empty: 0 })
    // "gx,gy" of each hole of the game, sorted
    function holeLines() { return game.holes.map(h => h.cell + ":" + h.veinCells.join(" ")).sort() }
    // What rule the holes of the game break, ["..."]
    function holesBroken() {
        let out = [], g = game.grid, cs = game.cellSize
        let slitCells = {}
        for (let f of game.features)
            if (f.kind === "slit") slitCells[(f.gx - f.dx) + "," + (f.gy - f.dy)] = true
        game.rooms.forEach((room, ri) => {
            let veins = game.features.filter(f => f.kind === "vein" && f.gx >= room.x && f.gx < room.x + room.w
                                                  && f.gy >= room.y && f.gy < room.y + room.h)
            let mine = game.holes.filter(h => {
                let c = h.cell.split(",").map(Number)
                return c[1] === room.y + room.h && c[0] >= room.x && c[0] < room.x + room.w
            })
            if (ri === 0 || veins.length === 0) {
                if (mine.length > 0) out.push("room " + ri + " without a vein has a hole")
                return
            }
            placed.veinRooms++
            if (mine.length !== 1) {
                out.push("room " + ri + " with " + veins.length + " vein(s) has " + mine.length + " holes")
                return
            }
            let h = mine[0], c = h.cell.split(",").map(Number)
            if (g[c[1]][c[0]] !== game.cellWall || g[c[1] - 1][c[0]] !== game.cellRoom)
                out.push(h.cell + " is no wall face over a room's cell")
            if (game._torchCells[h.cell] || game.torches.some(t => Math.floor(t.xWu / cs) === c[0]
                                                                   && Math.floor(t.yWu / cs) === c[1]))
                out.push(h.cell + " is on a torch")
            if (slitCells[h.cell]) out.push(h.cell + " is on a slit")
            if (game._secretOf(c[0], c[1]) >= 0) out.push(h.cell + " is on a secret")
            if (h.stage !== "rest") out.push(h.cell + " is not at rest")
            let d = Math.min(...veins.map(v => Math.abs(v.wgx - c[0]) + Math.abs(v.wgy - c[1])))
            if (d === 0) out.push(h.cell + " is on a vein")
            if (d <= cfg.rockCells) placed.onRock++
            if (d >= hc.gap) placed.far++
            let wanted = veins.map(v => v.wgx + "," + v.wgy).sort().join()
            if (h.veinCells.slice().sort().join() !== wanted) out.push(h.cell + " is woken by " + h.veinCells.join(" "))
        })
        return out
    }
    function placementSteps() {
        let out = []
        for (let i = 0; i < seeds; i++) {
            for (let dg of dangers) {
                out.push([30, () => {
                    let seed = 2000 + i * 7919
                    game.applyScenario("dungeon", dg, seed)
                    let a = holeLines()
                    for (let why of holesBroken()) placed.broken.push("seed " + seed + " danger " + dg + ": " + why)
                    placed.holes += a.length
                    if (a.length === 0) placed.empty++
                    game.applyScenario("dungeon", dg, seed)
                    placed.builds++
                    if (JSON.stringify(holeLines()) === JSON.stringify(a)) placed.same++
                }])
            }
        }
        out.push([30, () => {
            check(placed.builds === seeds * dangers.length && placed.same === placed.builds,
                  "the same seed and danger place the same holes on " + placed.same + " of " + placed.builds
                  + " dungeons (" + seeds + " seeds at danger " + dangers.join(", ") + ")")
            check(placed.broken.length === 0 && placed.holes === placed.veinRooms && placed.holes > 0,
                  "each of the " + placed.veinRooms + " rooms with a vein has one hole at rest (" + placed.holes
                  + "), in the face of its north wall over a room's cell, off its veins, a torch, a slit "
                  + "and a secret, woken by its room's veins; no other room has one"
                  + (placed.broken.length ? ": " + placed.broken.length + " not, e.g. " + placed.broken.slice(0, 3).join("; ") : ""))
            check(placed.far >= placed.holes * 0.8 && placed.onRock <= placed.holes * 0.05,
                  placed.far + " of the " + placed.holes + " holes stand " + hc.gap + " cells or more from each vein of "
                  + "their room; " + placed.onRock + " in a small room stand on its vein's rock face")
            let camps = 0
            for (let i = 0; i < 5; i++) {
                game.applyScenario("village", i * 2, 2000 + i * 7919)
                camps += game.holes.length
            }
            game.applyScenario("fight")
            check(camps === 0 && game.holes.length === 0,
                  "no hole in the camp (5 camps: " + camps + ") nor in the fight room (" + game.holes.length + ")")
        }])
        return out
    }

    // ---- waking ----
    readonly property int depth: 3
    // The first seed from scenarioSeed whose deep room's vein, cut all
    // clean, wakes its hole (wakes) or leaves it asleep (!wakes)
    function deepSeed(wakes) {
        for (let k = 0; k < 200; k++) {
            let seed = game.scenarioSeed + k
            game.applyScenario("deep", depth, seed)
            let v = vein()
            if (game.holeWakes(v.cell, game.gemValue(v.shape, v.strikes, v.strikes)) === wakes) return seed
        }
        return -1
    }
    // Cuts the vein dug, every strike clean; the hole's stage before the
    // last strike
    function cutClean() {
        let v = vein(), before = ""
        for (let i = 1; i <= v.strikes; i++) {
            stepTo(i * beat)
            if (i === v.strikes) before = hole().stage
            strike()
        }
        return before
    }
    property int sleepSeed: -1
    property int wakeSeed: -1
    property var wakeSteps: [
        [100, () => {
            game.applyScenario("deep")
            let h = hole()
            check(game.holes.length === 1 && h.stage === "rest" && h.visible && h.veinCells.join() === vein().cell,
                  "the dojo's deep scenario shows a hole at rest, at " + (h ? h.cell : "none")
                  + ", woken by the vein at " + vein().cell)
            sleepSeed = deepSeed(false)
            wakeSeed = deepSeed(true)
            check(sleepSeed >= 0 && wakeSeed >= 0, "at depth " + depth + " seed " + sleepSeed
                  + " rolls the deep room's hole asleep and seed " + wakeSeed + " awake for a gem cut all clean")

            // A cut whose roll fails leaves the hole at rest
            freshDig(depth, sleepSeed)
            let v = vein()
            let before = cutClean()
            step(Math.round((hc.eyesAfter + hc.telegraph + hc.waveGap) / dt))
            check(v.split && v.clean === v.strikes && before === "rest" && hole().stage === "rest"
                  && game.holeEvents.length === 0 && game.enemies.length === 0,
                  "on seed " + sleepSeed + " the gem cut all clean (" + v.clean + " of " + v.strikes
                  + ") leaves the hole at rest: " + hole().stage + ", " + game.holeEvents.length + " events, "
                  + game.enemies.length + " creatures")
            Clayground.paused = false
        }],
        [100, () => {
            freshDig(depth, wakeSeed)
            let v = vein(), h = hole(), n = game.holeSoundCount
            let before = cutClean()
            let atCut = h.stage + " (" + soundsSince(n).join() + ")"
            n = game.holeSoundCount
            check(v.split && before === "rest" && atCut === "dust (rumble)",
                  "the strikes wake nothing before the cut (" + before + "); the cut gem wakes the hole: " + atCut)
            let k = 0
            while (h.stage === "dust" && k++ < 60 * 10) step(1)
            check(h.stage === "eyes" && soundsSince(n).join() === "groan" && h.eyesOpen
                  && bench.findEyes(h).objectName === "holeEyes",
                  "eyesAfter " + hc.eyesAfter + " s later its two eyes open in the dark with the groan ("
                  + (k * dt).toFixed(3) + " s, " + soundsSince(n).join() + ")")

            // The waves, until it closes
            k = 0
            while (h.stage !== "closed" && k++ < 60 * 30) step(1)
            let ev = eventsOf(h.cell)
            let order = []
            for (let w = 1; w <= hc.waves; w++) {
                if (w === 1) order.push("waves")
                order.push("wave")
                for (let i = 0; i < hc.perWave; i++) order.push("creature")
            }
            order = ["dust", "eyes"].concat(order).concat(["closed"])
            check(whats(ev).join() === order.join(),
                  "the hole goes through " + whats(ev).join(", "))
            let at = what => (ev.find(e => e.what === what) || { t: NaN }).t
            let first = at("creature") - at("eyes"), fromDust = at("creature") - at("dust")
            check(first >= Balance.enemy.minTelegraph - 1e-6 && first >= hc.telegraph - dt - 1e-6
                  && Math.abs(at("eyes") - at("dust") - hc.eyesAfter) <= dt + 1e-6,
                  "the first creature comes " + first.toFixed(3) + " s after the eyes opened ("
                  + fromDust.toFixed(3) + " s after the dust), no sooner than enemy.minTelegraph "
                  + Balance.enemy.minTelegraph + " and telegraph " + hc.telegraph)
            let cs = creatures(h.cell)
            let off = cs.filter(e => Math.abs(e.xWu + e.widthWu / 2 - h.mouthXWu) > h.sizeWu / 2
                                     || e.yWu > h.mouthYWu + 1e-6 || e.yWu < h.mouthYWu - 1)
            check(cs.length === hc.waves * hc.perWave && off.length === 0,
                  cs.length + " creatures came from the hole's cell " + h.cell + " in " + hc.waves + " waves of "
                  + hc.perWave + ": " + cs.map(e => e.enemyType + "/" + e.tier + " at "
                  + (e.xWu + e.widthWu / 2).toFixed(2) + "," + e.yWu.toFixed(2)).join("; ")
                  + " (mouth " + h.mouthXWu.toFixed(2) + "," + h.mouthYWu.toFixed(2) + ")")
            let last = ev.filter(e => e.what === "creature").pop()
            check(h.closed && game.holeSounds.indexOf("crumble") >= 0
                  && Math.abs(at("closed") - last.t - hc.closeAfter) <= dt + 1e-6,
                  "closeAfter " + hc.closeAfter + " s after the last creature it closes with the crumble ("
                  + (at("closed") - last.t).toFixed(3) + " s)")

            // A gem cut after that wakes nothing
            let events = game.holeEvents.length, sounds = game.holeSoundCount, count = cs.length
            game._gemCut(v.cell, 1000)
            step(Math.round((hc.eyesAfter + hc.telegraph + hc.waveGap) / dt))
            check(h.closed && game.holeEvents.length === events && game.holeSoundCount === sounds
                  && creatures(h.cell).length === count,
                  "a gem cut after it closed wakes nothing: " + h.stage + ", " + (game.holeEvents.length - events)
                  + " events, " + (creatures(h.cell).length - count) + " creatures more")
            Clayground.paused = false
        }]
    ]

    // ---- the share (issue #175) ----
    readonly property int shareSeeds: 40
    readonly property int cutSeeds: 10
    readonly property var shareDangers: [0.5, 8.5]
    readonly property var parties: [1, 2, 3, 4]
    // By "danger/knights/chipped|clean": {holes, woken, chance (summed)}
    property var share: ({})
    property var cutRuns: ({ runs: 0, woken: 0, notSame: [], notRolled: [] })
    // The first vein of each hole of the dungeon built, its gem's worth
    // cut every strike chipped or clean: [{cell, hole, value}]
    function holeVeins(clean) {
        return game.holes.map(h => {
            let v = game.veinAt(h.veinCells[0])
            return { cell: v.cell, hole: h.cell, value: game.gemValue(v.shape, clean ? v.strikes : 0, v.strikes) }
        })
    }
    // Builds the dungeon on seed at danger dg for knights and cuts the
    // first vein of each hole, every strike clean, through the game's own
    // cut; the cells of the holes woken, sorted
    function cutAll(seed, dg, knights) {
        game.knightsOverride = knights
        game.applyScenario("dungeon", dg, seed)
        let out = []
        for (let h of game.holes) {
            let v = game.veinAt(h.veinCells[0])
            v.clean = v.strikes
            v.chips = 0
            game._veinCut(v)
            if (h.stage !== "rest") out.push(h.cell)
        }
        return out.sort()
    }
    function shareSteps() {
        let out = []
        for (let i = 0; i < shareSeeds; i++) {
            for (let dg of shareDangers) {
                out.push([30, () => {
                    Clayground.paused = true
                    let seed = 7000 + i * 104729
                    // The holes stand where they stand for any party: one
                    // build, the game's roll for each party and worth
                    game.knightsOverride = 1
                    game.applyScenario("dungeon", dg, seed)
                    for (let n of parties)
                        for (let clean of [false, true]) {
                            let key = dg + "/" + n + "/" + (clean ? "clean" : "chipped")
                            let row = share[key] = share[key] || { holes: 0, woken: 0, chance: 0 }
                            for (let hv of holeVeins(clean)) {
                                row.holes++
                                row.chance += game.holeWakeChance(hv.value, n)
                                if (game.holeWakes(hv.cell, hv.value, n)) row.woken++
                            }
                        }
                    if (i >= cutSeeds) return
                    // The game's own cut, for 2 knights, built twice: it
                    // wakes the holes the roll says, the same both times
                    let a = cutAll(seed, dg, 2)
                    game.applyScenario("dungeon", dg, seed)
                    let rolled = holeVeins(true).filter(hv => game.holeWakes(hv.cell, hv.value)).map(hv => hv.hole).sort()
                    let b = cutAll(seed, dg, 2)
                    cutRuns.runs++
                    cutRuns.woken += a.length
                    if (a.join() !== b.join()) cutRuns.notSame.push(seed + "@" + dg + ": " + a.join(" ") + " / " + b.join(" "))
                    if (a.join() !== rolled.join()) cutRuns.notRolled.push(seed + "@" + dg + ": " + a.join(" ") + " / " + rolled.join(" "))
                }])
            }
        }
        out.push([30, () => {
            game.knightsOverride = 0
            Clayground.paused = false
            let s = (dg, n, c) => share[dg + "/" + n + "/" + c]
            let pct = r => (100 * r.woken / Math.max(1, r.holes)).toFixed(0) + "%"
            let line = dg => parties.map(n => n + ": " + pct(s(dg, n, "chipped")) + " -> " + pct(s(dg, n, "clean"))).join(", ")
            let rate = r => r.woken / Math.max(1, r.holes)
            // Every gem's chance at wakeMost: the share can rise no more
            let capped = r => r.chance >= r.holes * hc.wakeMost - 1e-6
            let rises = (hi, lo) => rate(hi) > rate(lo) || (capped(hi) && capped(lo))
            let byValue = [], byParty = [], near = []
            for (let dg of shareDangers)
                for (let n of parties) {
                    let lo = s(dg, n, "chipped"), hi = s(dg, n, "clean")
                    if (!rises(hi, lo)) byValue.push(dg + "/" + n)
                    if (n > 1 && !(rises(s(dg, n, "chipped"), s(dg, n - 1, "chipped"))
                                   && rises(s(dg, n, "clean"), s(dg, n - 1, "clean")))) byParty.push(dg + "/" + n)
                    for (let r of [lo, hi])
                        if (Math.abs(rate(r) - r.chance / Math.max(1, r.holes)) > 0.12) near.push(dg + "/" + n)
                }
            for (let dg of shareDangers) console.log("[Holes] danger", dg, "woken by knights, chipped -> clean:", line(dg))
            let deeper = parties.every(n => rises(s(shareDangers[1], n, "clean"), s(shareDangers[0], n, "clean")))
            check(byValue.length === 0 && deeper,
                  "the share of woken holes rises with the gem's worth: all clean over all chipped at each danger and "
                  + "party, and the deep gems' over the shallow ones'" + (byValue.length ? " - not at " + byValue.join(", ") : ""))
            check(byParty.length === 0,
                  "it rises with the knights at each danger, chipped and clean, or every gem's chance stands at "
                  + "wakeMost " + hc.wakeMost + (byParty.length ? " - not at " + byParty.join(", ") : ""))
            check(near.length === 0 && s(shareDangers[0], 1, "chipped").holes > 50,
                  "each share lies within 12 points of the mean holeWakeChance over " + s(shareDangers[0], 1, "chipped").holes
                  + " holes at danger " + shareDangers[0] + " and " + s(shareDangers[1], 1, "chipped").holes + " at "
                  + shareDangers[1] + (near.length ? " - not at " + near.join(", ") : ""))
            check(cutRuns.runs === cutSeeds * shareDangers.length && cutRuns.notRolled.length === 0 && cutRuns.woken > 0,
                  "the game's cut wakes the holes its roll says on " + (cutRuns.runs - cutRuns.notRolled.length) + " of "
                  + cutRuns.runs + " dungeons for 2 knights (" + cutRuns.woken + " woken)"
                  + (cutRuns.notRolled.length ? ": " + cutRuns.notRolled.slice(0, 3).join("; ") : ""))
            check(cutRuns.notSame.length === 0 && cutRuns.runs > 0,
                  "the same seed and party wake the same holes on " + (cutRuns.runs - cutRuns.notSame.length) + " of "
                  + cutRuns.runs + " dungeons built and cut twice"
                  + (cutRuns.notSame.length ? ": " + cutRuns.notSame.slice(0, 3).join("; ") : ""))
            console.log("[Holes] done,", failures, "failed")
            game.destroy()
        }])
        return out
    }
    property var endSteps: [[300, () => Qt.exit(failures)]]
    function findEyes(h) {
        let kids = h.glowParent ? h.glowParent.children : []
        for (let i = 0; i < kids.length; i++)
            if (kids[i].objectName === "holeEyes" && Math.abs(kids[i].x + kids[i].width / 2 - h.x - h.width / 2) < 1)
                return kids[i]
        return { objectName: "" }
    }

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
                    console.log("[Holes] FAIL step", i, "timed out")
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
