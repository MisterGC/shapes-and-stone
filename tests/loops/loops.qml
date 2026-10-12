// Loops bench - some rooms get a second entrance, so a dungeon has loops
// to flank and to escape (issue #126).
//
// Checks that the table asks more corridors off the chain at a higher
// danger; builds the same seed at the same danger twice, at low, middle
// and high danger, and checks the same corridors on the same cells; then
// builds 50 seeds at dangers across the bands and walks each grid itself:
// every room, the exit and the cell above the entrance's block reachable
// from the start room, as many corridors off the chain as the table asks
// at the dungeon's band, each joining two rooms not neighbours in the
// chain, each cell it carved a corridor's, in no third room nor beside
// one, beside each of its own rooms at one doorway and not along its
// wall, nor on or beside the entrance's or the exit's shaft, and closing a
// loop: its two rooms still joined with its cells walled up. With an out
// dir and a window it saves minimap.png, the game's minimap of a dungeon
// with loops, all of it explored, and loops.png, the same grid with the
// corridors off the chain in amber. Prints one PASS or FAIL line per
// check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/loops/loops.qml
//   qml -I <build>/bin/qml tests/loops/loops.qml -- <out dir>

import QtQuick
import QtQuick.Window
import "../../src"

Window {
    id: bench
    width: 1280
    height: 800
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0
    property string outDir: {
        let args = Qt.application.arguments
        let i = args.indexOf("--")
        return i >= 0 && i + 1 < args.length ? args[i + 1] : ""
    }

    function check(ok, what) {
        console.log("[Loops]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Loops] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                  recordStoreName: "ShapesAndStoneLoopsBench"})
        script.start()
    }

    readonly property int seeds: 50
    // The dungeon captured: the scenario seed high in depth 2's range
    readonly property real shotDanger: 2.9

    function find(root, name) {
        if (root.objectName === name) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = find(kids[i], name)
            if (f) return f
        }
        return null
    }
    function table() { return Balance.dungeon.extraCorridors }
    function asked() { return table()[game.dangerBand(game.dangerPosition)] }
    function corridors() { return JSON.stringify(game.loopCorridors) }
    function rows() { return JSON.stringify(game.grid) }

    // The cells reachable from (gx, gy) over anything but rock, those in
    // walled ("gx,gy" keys) taken for rock too
    function reach(gx, gy, walled) {
        let g = game.grid, seen = {}, todo = [[gx, gy]]
        seen[gx + "," + gy] = true
        while (todo.length > 0) {
            let c = todo.pop()
            for (let n of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
                let x = c[0] + n[0], y = c[1] + n[1], k = x + "," + y
                if (seen[k] || !g[y] || g[y][x] === undefined || g[y][x] === game.cellWall || walled[k]) continue
                seen[k] = true
                todo.push([x, y])
            }
        }
        return seen
    }
    function centre(r) { return [Math.floor(r.x + r.w / 2), Math.floor(r.y + r.h / 2)] }
    function inRoom(r, gx, gy) { return gx >= r.x && gx < r.x + r.w && gy >= r.y && gy < r.y + r.h }

    // One seed's dungeon: [problems, corridors]
    function walk(seed) {
        let out = [], g = game.grid, rooms = game.rooms, say = s => out.push("seed " + seed + " " + s)
        let start = centre(rooms[0]), from = reach(start[0], start[1], {})
        let cut = rooms.filter(r => !from[centre(r).join(",")]).length
        if (cut > 0) say(cut + " rooms cut off")
        if (!from[game.exitGridX + "," + (game.gridHeight - 1)]) say("the exit cut off")
        if (!from[game.entranceGridX + ",1"]) say("the entrance's shaft cut off")
        let lc = game.loopCorridors
        if (lc.length !== asked())
            say(lc.length + " corridors off the chain, the table asks " + asked())
        let last = rooms[rooms.length - 1]
        for (let c of lc) {
            let what = "corridor " + c.a + "-" + c.b
            if (Math.abs(c.a - c.b) < 2) say(what + " joins neighbours in the chain")
            if (c.cells.length === 0) say(what + " carved nothing")
            // Into each of its two rooms through one doorway, not along
            // their walls
            for (let k of [c.a, c.b]) {
                let side = c.cells.filter(p => [[1, 0], [-1, 0], [0, 1], [0, -1]].some(
                                              n => inRoom(rooms[k], p[0] + n[0], p[1] + n[1])))
                if (side.length > 1) say(what + " runs along room " + k + "'s wall, " + side.length + " cells")
            }
            let walled = {}
            for (let p of c.cells) {
                let x = p[0], y = p[1]
                walled[x + "," + y] = true
                if (g[y][x] !== game.cellHallway) say(what + " at " + x + "," + y + " is no corridor's cell")
                rooms.forEach((r, k) => {
                    if (k === c.a || k === c.b) return
                    if (inRoom(r, x, y)) say(what + " cuts through room " + k + " at " + x + "," + y)
                    else if ([[1, 0], [-1, 0], [0, 1], [0, -1]].some(n => inRoom(r, x + n[0], y + n[1])))
                        say(what + " opens into room " + k + " at " + x + "," + y)
                })
                if ((Math.abs(x - game.entranceGridX) <= 1 && y < rooms[0].y)
                        || (Math.abs(x - game.exitGridX) <= 1 && y >= last.y + last.h))
                    say(what + " runs into a shaft at " + x + "," + y)
            }
            let a = centre(rooms[c.a]), b = centre(rooms[c.b])
            if (!reach(a[0], a[1], walled)[b.join(",")]) say(what + " closes no loop")
        }
        return [out, lc.length]
    }

    property var walked: ({ problems: [], total: 0, least: 1e9, bands: [0, 0, 0] })
    function seedSteps() {
        let out = []
        for (let i = 0; i < seeds; i++) {
            out.push([60, () => {
                let seed = 1000 + i * 7919
                game.applyScenario("dungeon", (i % 10) * 0.55, seed)
                let w = walk(seed)
                walked.problems = walked.problems.concat(w[0])
                walked.total += w[1]
                walked.least = Math.min(walked.least, w[1])
                walked.bands[game.dangerBand(game.dangerPosition)]++
            }])
        }
        return out
    }

    property var steps: [
        [() => game.screen === "title", () => {
            let t = table()
            check(t && t.length === 3 && t[0] >= 1 && t[0] <= t[1] && t[1] <= t[2] && t[0] < t[2],
                  "Balance.dungeon.extraCorridors asks more at a higher danger: " + JSON.stringify(t))
            if (outDir === "") return
            // The captured dungeon, all of it explored, the minimap
            // enlarged so its cells read, beside the plan. Taken before
            // the dungeons below are built, as the features bench does
            game.applyScenario("dungeon", shotDanger)
            game.fx = true
            for (let e of game.enemies) if (e && e.halt) e.halt()
            for (let row of game.exploredCells) row.fill(true)
            let m = find(game, "minimap")
            m.width = 600
            m.height = 600
            m.requestPaint()
            plan.requestPaint()
            plan.visible = true
        }],
        [500, () => {
            if (outDir === "") return
            bench.contentItem.grabToImage(r => {
                let ok = r.saveToFile(outDir + "/loops.png")
                console.log("[Loops]", ok ? "saved" : "could not save", outDir + "/loops.png")
            })
        }],
        [500, () => {
            plan.visible = false
            let m = find(game, "minimap")
            m.width = 150
            m.height = 150
            // The same seed and danger, twice: the same corridors, the
            // same grid
            for (let dg of [0.2, 1.5, 2.9]) {
                game.applyScenario("dungeon", dg)
                let a = corridors(), ga = rows(), n = game.loopCorridors.length
                game.applyScenario("dungeon", dg)
                check(n > 0 && a === corridors() && ga === rows(),
                      "seed " + game.scenarioSeed + " at danger " + dg + " carves the same " + n
                      + " corridors off the chain twice: " + game.loopCorridors.map(c => c.a + "-" + c.b
                                                                                   + " (" + c.cells.length + " cells)").join(", "))
            }
        }],
    ].concat(seedSteps()).concat([
        [100, () => {
            check(walked.least > 0, seeds + " seeds (bands low " + walked.bands[0] + ", middle "
                  + walked.bands[1] + ", high " + walked.bands[2] + ") carve " + walked.total
                  + " corridors off the chain, at least " + walked.least + " a dungeon")
            check(walked.problems.length === 0, "every dungeon on " + seeds + " seeds is connected, its corridors "
                  + "off the chain as many as the table asks, none through or into a third room, along its rooms' walls or into a shaft, "
                  + "each closing a loop" + (walked.problems.length ? ": " + walked.problems.length
                                             + ", e.g. " + walked.problems.slice(0, 4).join("; ") : ""))
            console.log("[Loops] done,", failures, "failed")
        }],
        // Torn down before quitting, as the other benches do
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ])

    // The grid of the captured dungeon: rooms, the chain's corridors and
    // the shafts in grey, the corridors off the chain in amber
    Canvas {
        id: plan
        visible: false
        z: 2000
        x: 20
        y: 20
        width: 600
        height: 600
        onPaint: {
            let ctx = getContext("2d")
            ctx.fillStyle = "#111"
            ctx.fillRect(0, 0, width, height)
            if (!game || game.grid.length === 0) return
            let gw = game.gridWidth, gh = game.gridHeight, s = width / gw, loop = {}
            for (let c of game.loopCorridors)
                for (let p of c.cells) loop[p[0] + "," + p[1]] = true
            for (let gy = 0; gy < gh; gy++)
                for (let gx = 0; gx < gw; gx++) {
                    let t = game.grid[gy][gx]
                    ctx.fillStyle = loop[gx + "," + gy] ? "#E0A030"
                        : t === game.cellWall ? "#333" : t === game.cellRoom ? "#777" : "#555"
                    ctx.fillRect(gx * s, (gh - 1 - gy) * s, s, s)
                }
        }
    }

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
                if (waitedMs > 60000) {
                    console.log("[Loops] FAIL step", i, "timed out")
                    Qt.exit(failures + 1)
                    stop()
                }
                return
            }
            waitedMs = 0
            i++
            if (i >= bench.steps.length) stop()
            try {
                step[1]()
            } catch (err) {
                console.log("[Loops] FAIL step", i - 1, "threw:", err)
                Qt.exit(failures + 1)
                stop()
            }
        }
    }
}
