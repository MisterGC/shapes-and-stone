// Features bench - a dungeon places its features from its own seeded
// stream, as many as its danger asks, and the dojo can show them
// (issue #122).
//
// Lands in the dojo's features scenario and checks that it is a dungeon
// showing the test kind; builds the same seed at the same danger twice
// and checks the same features on the same cells, and the scenario seed's
// against the fingerprint recorded below, so they are the same on every
// run; builds the dungeon played at low, middle and high danger and
// checks it holds as many of each kind as the table asks there (the test
// kind none); then builds the features scenario on 50 seeds and walks
// each grid itself: every feature on a room's cell, not in the start
// room, not beside a corridor, the table's distance clear of the entrance
// and the exit, one to a cell, and each room holding its showcase count
// or every cell it has free. The next level is built without the
// showcase. With an out dir and a window it saves features.png. Prints
// one PASS or FAIL line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/features/features.qml
//   qml -I <build>/bin/qml tests/features/features.qml -- <out dir>

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
        console.log("[Features]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Features] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                  recordStoreName: "ShapesAndStoneFeaturesBench"})
        script.start()
    }

    // The features scenario on the scenario seed at danger 0: the
    // fingerprint of its features, recorded from this build
    readonly property string recorded: "87b91999"
    readonly property int seeds: 50

    function kinds() { return Object.keys(Balance.dungeon.kinds) }
    function lines() { return game.features.map(f => [f.kind, f.gx, f.gy].join(":")) }
    function hash(ls) {
        let s = ls.join("\n"), h = 5381
        for (let i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0
        return h.toString(16)
    }
    function shown(kind) {
        return game.dungeonObjects.filter(o => o && o.kind === kind && o.xWu !== undefined
                                          && o.visible && game.features.some(f => f.kind === kind
                                              && f.xWu === o.xWu && f.yWu === o.yWu))
    }

    // The rules, read off the grid here and not from the game's own check:
    // the cells of room r a feature may stand on
    function freeCells(r) {
        let room = game.rooms[r], out = []
        for (let gy = room.y; gy < room.y + room.h; gy++)
            for (let gx = room.x; gx < room.x + room.w; gx++)
                if (ruleBroken(gx, gy) === "") out.push(gx + "," + gy)
        return out
    }
    // What rule a feature on (gx, gy) breaks, "" for none
    function ruleBroken(gx, gy) {
        let g = game.grid, cs = game.cellSize, start = game.rooms[0]
        if (g[gy][gx] === game.cellHallway) return "on a corridor"
        if (g[gy][gx] !== game.cellRoom) return "not on a room's floor"
        if (gx >= start.x && gx < start.x + start.w && gy >= start.y && gy < start.y + start.h)
            return "in the start room"
        if ([[1, 0], [-1, 0], [0, 1], [0, -1]].some(n => {
                let row = g[gy + n[1]]
                return row !== undefined && row[gx + n[0]] === game.cellHallway }))
            return "on a doorway"
        let dist = (ex, ey) => Math.hypot((gx - ex) * cs, (gy - ey) * cs)
        if (dist(game.entranceGridX, 0) < Balance.dungeon.clearOfEntrance) return "near the entrance"
        if (dist(game.exitGridX, game.gridHeight - 1) < Balance.dungeon.clearOfExit) return "near the exit"
        return ""
    }
    function roomOf(gx, gy) {
        return game.rooms.findIndex(r => gx >= r.x && gx < r.x + r.w && gy >= r.y && gy < r.y + r.h)
    }

    // One seed's dungeon against the rules: [broken, short, features]
    function walk(seed) {
        let broken = [], short = [], cells = {}
        for (let f of game.features) {
            let why = ruleBroken(f.gx, f.gy)
            if (cells[f.gx + "," + f.gy]) why = "on a cell taken"
            cells[f.gx + "," + f.gy] = true
            if (f.xWu !== (f.gx + 0.5) * game.cellSize || f.yWu !== (f.gy + 0.5) * game.cellSize)
                why = "off its cell's centre"
            if (why !== "") broken.push("seed " + seed + " " + f.kind + " at " + f.gx + "," + f.gy + " " + why)
        }
        // Each room asks showcase of each kind (whole numbers), or every
        // cell it has free if fewer
        let asked = 0
        for (let k of kinds()) asked += Balance.dungeon.kinds[k].showcase
        for (let r = 1; r < game.rooms.length; r++) {
            let want = Math.min(asked, freeCells(r).length)
            let got = game.features.filter(f => roomOf(f.gx, f.gy) === r).length
            if (got !== want) short.push("seed " + seed + " room " + r + " holds " + got + ", asked " + want)
        }
        return [broken, short, game.features.length]
    }

    property var steps: [
        [() => game.screen === "title", () => {
            check(Balance.dungeon && Balance.dungeon.clearOfEntrance > 0 && Balance.dungeon.clearOfExit > 0
                  && kinds().indexOf("test") >= 0,
                  "Balance.dungeon has clearOfEntrance " + Balance.dungeon.clearOfEntrance + ", clearOfExit "
                  + Balance.dungeon.clearOfExit + " and the kinds " + kinds().join(", "))
            check(game.scenarios().indexOf("features") >= 0,
                  "the dojo offers the features scenario: " + game.scenarios().join(", "))
            game.applyScenario("features")
        }],
        // The dojo's features scenario: a dungeon, the test kind shown
        [500, () => {
            let t = shown("test").length, n = game.features.filter(f => f.kind === "test").length
            check(game.screen === "game" && game.levelType === "dungeon" && !game.fightRoomActive && game.player,
                  "applyScenario(\"features\") lands in a dungeon (depth " + game.depth + ", "
                  + game.rooms.length + " rooms)")
            check(n > 0 && t === n,
                  "it shows the test kind: " + n + " placed, " + t + " drawn and visible")
            let h = hash(lines())
            console.log("[Features] scenario fingerprint:", h, game.features.length, "features")
            check(h === recorded, "seed " + game.scenarioSeed + " places the features recorded ("
                  + h + ", recorded " + recorded + ")")
            // Beside the first feature, the enemies still, the camera
            // snapped to the knight as the looks bench does
            if (outDir !== "") {
                game.fx = true
                for (let e of game.enemies) if (e && e.halt) e.halt()
                game.player.xWu = game.features[0].xWu
                game.player.yWu = game.features[0].yWu - 1.5
                game.camera.target = null
                game.camera.target = game.player
            }
        }],
        [500, () => {
            if (outDir === "") return
            bench.contentItem.grabToImage(r => {
                let ok = r.saveToFile(outDir + "/features.png")
                console.log("[Features]", ok ? "saved" : "could not save", outDir + "/features.png")
            })
        }],
        [300, () => {
            // The same seed and danger, twice: the same features
            for (let dg of [0.5, 2.5, 4.8]) {
                game.applyScenario("features", dg)
                let a = lines()
                game.applyScenario("features", dg)
                let b = lines()
                check(a.length > 0 && JSON.stringify(a) === JSON.stringify(b),
                      "seed " + game.scenarioSeed + " at danger " + dg + " places the same "
                      + a.length + " features twice")
            }
            // The dungeon played: as many as the table asks at its danger
            for (let dg of [0.2, 1.5, 2.9]) {
                game.applyScenario("dungeon", dg)
                let band = game.dangerBand(game.dangerPosition)
                for (let k of kinds()) {
                    let per = Balance.dungeon.kinds[k].perRoom[band]
                    let n = game.features.filter(f => f.kind === k).length
                    let rooms = game.rooms.length - 1
                    // Each room its whole number and a chance of one more
                    let ok = per === 0 ? n === 0 : n > 0 && n <= Math.ceil(per) * rooms
                    check(ok, "danger " + dg + " (band " + band + "): " + n + " " + k
                          + ", the table asks " + per + " a room in " + rooms + " rooms")
                }
            }
        }],
    ].concat(seedSteps()).concat([
        [100, () => {
            check(walked.least > 0, seeds + " seeds place " + walked.total + " features, at least "
                  + walked.least + " a dungeon")
            check(walked.broken.length === 0, "no feature breaks a rule on " + seeds + " seeds (start room, "
                  + "doorway, corridor, entrance and exit distance, one a cell)"
                  + (walked.broken.length ? ": " + walked.broken.length + ", e.g. "
                     + walked.broken.slice(0, 3).join("; ") : ""))
            check(walked.short.length === 0, "every room on " + seeds + " seeds holds its showcase count or "
                  + "all it has free" + (walked.short.length ? ": " + walked.short.length + " do not, e.g. "
                                         + walked.short.slice(0, 3).join("; ") : ""))
            // The next level is built without the showcase
            game.applyScenario("features")
            game.resetDungeon()
        }],
        [() => game.player && game.levelType === "village", () => game.resetDungeon()],
        [() => game.player && game.levelType === "dungeon", () => {
            let n = game.features.filter(f => f.kind === "test").length
            check(!game.featureShowcase && n === 0,
                  "the next dungeon, depth " + game.depth + ", is built without the showcase: " + n + " test features")
            console.log("[Features] done,", failures, "failed")
        }],
        // Torn down before quitting, as the other benches do
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ])

    // The rules on 50 seeds, at dangers across the bands: one dungeon a
    // step, so the last one's objects are gone before the next is built
    property var walked: ({ broken: [], short: [], total: 0, least: 1e9 })
    function seedSteps() {
        let out = []
        for (let i = 0; i < seeds; i++) {
            out.push([60, () => {
                let seed = 1000 + i * 7919
                game.applyScenario("features", (i % 10) * 0.55, seed)
                let w = walk(seed)
                walked.broken = walked.broken.concat(w[0])
                walked.short = walked.short.concat(w[1])
                walked.total += w[2]
                walked.least = Math.min(walked.least, w[2])
            }])
        }
        return out
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
                    console.log("[Features] FAIL step", i, "timed out")
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
                console.log("[Features] FAIL step", i - 1, "threw:", err)
                Qt.exit(failures + 1)
                stop()
            }
        }
    }
}
