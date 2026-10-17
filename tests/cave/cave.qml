// Cave bench - the camp's edge is a cave, not a box, and the camp grows to
// make room (issue #145).
//
// On 20 seeds it builds the camp and checks that its floor is no box and
// about 1.5 times the old 20 x 20 cells, that the walk from where the
// knights come in to the stairs takes at most Balance.camp.maxWalk seconds
// at the knight's move speed - and walks the knight there, along the
// pathfinder's way, until the next dungeon starts - and that the campfire,
// the innkeeper in the tavern, the smith at his anvil, the witch at her
// tree and both tunnels are where the knights find them. A second game,
// another screen, builds the first seeds' camps again: the same outline;
// the 20 seeds build 20 outlines. The tavern and the smithy block the
// light, and the campfire's light casts shadows and reaches them.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/cave/cave.qml
//
// With a window and an output directory it also saves, for three seeds,
// the outline (outline-<seed>.png, one 8 px square per cell) and the camp
// (camp-<seed>.png, zoomed out to show it whole), and the buildings'
// shadows (shadows.png, and shadows-fire-only.png with the lanterns out):
//
//   qml -I <build>/bin/qml tests/cave/cave.qml -- <out dir>

import QtQuick
import QtQuick.Window
import "../../src"

Window {
    id: bench
    width: 1100
    height: 950
    visible: true
    color: "#1a1a2e"

    property var game: null
    property var other: null
    property int failures: 0
    readonly property string storeName: "ShapesAndStoneCaveBench"

    readonly property var args: Qt.application.arguments
    readonly property string outDir: args.length > 1 && !String(args[args.length - 1]).endsWith(".qml")
                                     ? args[args.length - 1] : ""
    readonly property var seeds: Array.from({ length: 20 }, (v, i) => 1000 + 7919 * i)
    readonly property var shotSeeds: seeds.slice(0, 3)

    function check(ok, what) {
        console.log("[Cave]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    property var gameComponent: null
    Component.onCompleted: {
        gameComponent = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComponent.status !== Component.Ready) {
            console.log("[Cave] FAIL", gameComponent.errorString())
            Qt.exit(1)
            return
        }
        game = gameComponent.createObject(bench.contentItem, {width: bench.width, height: bench.height,
                                                              muted: true, recordStoreName: storeName})
        script.start()
    }

    function inCamp(g) { return g && g.player && g.levelType === "village" && !g.resetting }
    function signature(g) { return g.grid.map(r => r.join("")).join("/") }
    function npc(g, name) {
        let kids = g.room.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i].objectName === "npc" && kids[i].npcName === name) return kids[i]
        return null
    }
    function campfire(g) { return g.dungeonObjects.find(o => o && o.healRadius !== undefined) }
    function lightLayer(root) {
        if (root && typeof root.setOccluderGrid === "function" && typeof root.isOccluded === "function")
            return root
        let kids = (root && (root.data || root.children)) || []
        for (let i = 0; i < kids.length; i++) {
            let f = lightLayer(kids[i])
            if (f) return f
        }
        return null
    }
    function cellOf(g, x, y) { return [Math.floor(x / g.cellSize), Math.floor(y / g.cellSize)] }
    function floorAt(g, x, y) {
        let c = cellOf(g, x, y)
        return g.grid[c[1]] && g.grid[c[1]][c[0]] !== g.cellWall
    }
    function building(g, gx, gy) { return g._buildingCells[gy * g.gridWidth + gx] === true }
    // The knight's centre: a body's xWu/yWu are its top-left corner
    function centre(k) { return Qt.point(k.xWu + k.widthWu / 2, k.yWu - k.heightWu / 2) }
    function pathLength(from, path) {
        let len = 0, at = from
        for (let p of path) { len += Math.hypot(p.x - at.x, p.y - at.y); at = p }
        return len
    }
    // From where the knights come in to the stairs' sensor
    function stairsPoint(g) { return Qt.point((g.exitGridX + 0.5) * g.cellSize, g.yWuMax - g.cellSize / 2) }

    // What one seed's camp is, as the checks below read it
    property var results: []
    property var current: null
    function survey(seed) {
        let g = game, c = Balance.camp
        let floor = 0, spans = {}, rows = 0
        for (let y = 0; y < g.gridHeight; y++) {
            let row = g.grid[y], first = -1, last = -1
            for (let x = 0; x < g.gridWidth; x++)
                // The old camp's 400 cells held its buildings too
                if (row[x] === g.cellRoom || building(g, x, y)) {
                    floor++
                    if (first < 0) first = x
                    last = x
                }
            if (first >= 0) { rows++; spans[first + "-" + last] = true }
        }
        let k = g.player, from = centre(k)
        let path = g.findPath(from.x, from.y, stairsPoint(g).x, stairsPoint(g).y)
        let len = pathLength(from, path)
        let fire = campfire(g), inn = npc(g, "Innkeeper"), smith = npc(g, "Blacksmith"), witch = npc(g, "Witch")
        let reach = o => o && g.findPath(from.x, from.y, o.xWu, o.yWu).length > 0 && floorAt(g, o.xWu, o.yWu)
        // The innkeeper stands between the tavern's walls, under its roof
        let ic = cellOf(g, inn.xWu, inn.yWu)
        let walled = dir => {
            for (let s = 1; s <= c.building.width; s++)
                if (building(g, ic[0] + dir[0] * s, ic[1] + dir[1] * s)) return true
            return false
        }
        let anvil = g.dungeonObjects.find(o => o && o.widthWu === 0.6 && o.heightWu === 0.4)
        let tree = g.dungeonObjects.find(o => o && o.radius > 0 && o.categories !== undefined)
        let layer = lightLayer(g)
        let bcells = Object.keys(g._buildingCells).map(Number)
        let shading = layer && bcells.length > 0 && bcells.every(i => layer.isOccluded(
                          (i % g.gridWidth + 0.5) * g.cellSize, (Math.floor(i / g.gridWidth) + 0.5) * g.cellSize))
        let fireLight = fire ? fire.data.find(o => o && o.castsShadows !== undefined) : null
        let fc = fire ? centre(fire) : Qt.point(0, 0)
        let nearestWall = Math.min.apply(null, bcells.map(i => Math.hypot(
                          (i % g.gridWidth + 0.5) * g.cellSize - fc.x, (Math.floor(i / g.gridWidth) + 0.5) * g.cellSize - fc.y)))
        return {
            seed: seed, signature: signature(g), floor: floor, shapes: Object.keys(spans).length, rows: rows,
            path: path, from: from, length: len, seconds: len / Balance.knight.moveSpeed,
            placed: reach(fire) && reach(inn) && reach(smith) && reach(witch)
                    && fc.y > from.y && fc.y < stairsPoint(g).y
                    && walled([-1, 0]) && walled([1, 0]) && walled([0, 1])
                    && anvil && Math.hypot(anvil.xWu - smith.routine[0].x, anvil.yWu - smith.routine[0].y) < 1.5
                    && tree && Math.hypot(tree.xWu - witch.xWu, tree.yWu - witch.yWu) < 2.5,
            tunnels: g.grid[0][g.entranceGridX] !== g.cellWall && g.grid[g.gridHeight - 1][g.exitGridX] !== g.cellWall,
            shading: shading,
            lit: fireLight && fireLight.castsShadows && fireLight.radius > nearestWall + g.cellSize,
            nearestWall: nearestWall, fireRadius: fireLight ? fireLight.radius : 0,
            walked: false, walkMs: 0
        }
    }

    // Walking the knight along the way: each frame towards the next point
    property var walk: null
    Timer {
        id: walker
        interval: 16
        repeat: true
        onTriggered: {
            let g = game, w = bench.walk
            if (!w) { stop(); return }
            if (g.levelType !== "village" || g.resetting) {
                w.done = true
                w.ms = Date.now() - w.start
                stop()
                return
            }
            let k = g.player, at = centre(k)
            while (w.i < w.path.length && Math.hypot(w.path[w.i].x - at.x, w.path[w.i].y - at.y) < 0.35) w.i++
            let to = w.i < w.path.length ? w.path[w.i] : Qt.point(at.x, at.y + 2)
            let dx = to.x - at.x, dy = to.y - at.y, d = Math.hypot(dx, dy) || 1
            k.moveX = dx / d
            k.moveY = -dy / d
        }
    }

    // --- Captures ---
    // The camera follows the knight only when it moves: a knight put
    // somewhere and standing still is nudged by a hair each frame until
    // the camera has caught up
    Timer {
        id: nudger
        interval: 16
        repeat: true
        property real sign: 1
        onTriggered: {
            if (!game || !game.player) return
            sign = -sign
            game.player.xWu += sign * 0.001
        }
    }

    Canvas {
        id: outlineCanvas
        visible: false
        width: 50 * 8
        height: 50 * 8
        property var g: null
        onPaint: {
            let ctx = getContext("2d"), s = 8
            ctx.fillStyle = "#111"
            ctx.fillRect(0, 0, width, height)
            if (!g) return
            for (let y = 0; y < g.gridHeight; y++)
                for (let x = 0; x < g.gridWidth; x++) {
                    let v = g.grid[y][x]
                    ctx.fillStyle = building(g, x, y) ? "#8a6a4a" : v === g.cellWall ? "#333" : "#999"
                    ctx.fillRect(x * s, (g.gridHeight - 1 - y) * s, s, s)
                }
        }
    }
    function saveOutline(seed, done) {
        outlineCanvas.g = game
        outlineCanvas.visible = true
        outlineCanvas.requestPaint()
        Qt.callLater(() => outlineCanvas.grabToImage(r => {
            let file = outDir + "/outline-" + seed + ".png"
            check(r.saveToFile(file), "saved " + file)
            outlineCanvas.visible = false
            done()
        }))
    }
    function saveGame(name) {
        game.grabToImage(r => {
            let file = outDir + "/" + name + ".png"
            check(r.saveToFile(file), "saved " + file)
        })
    }

    // --- The steps ---
    property int seedIndex: 0
    property var steps: []
    function seedSteps(seed) {
        let s = [
            [() => true, () => game.applyScenario("village", 0, seed)],
            [() => inCamp(game), () => {
                current = survey(seed)
                walk = { path: current.path, i: 0, start: Date.now(), done: false, ms: 0 }
                walker.start()
            }],
            [() => walk && walk.done, () => {
                current.walked = true
                current.walkMs = walk.ms
                results.push(current)
                walk = null
            }]
        ]
        if (outDir === "" || shotSeeds.indexOf(seed) < 0) return s
        // The camp whole, zoomed out, the knight in the middle
        return s.concat([
            [() => true, () => game.applyScenario("village", 0, seed)],
            [() => inCamp(game), () => { game.pixelPerUnit = 15 }],
            // Moved once the zoom is in place: the camera follows the
            // knight's pixels
            [500, () => {
                let c = campfire(game)
                game.player.xWu = c.xWu
                game.player.yWu = c.yWu + 2
                nudger.start()
            }],
            [2500, () => { nudger.stop(); saveGame("camp-" + seed) }],
            [300, () => { game.pixelPerUnit = 55; saveOutline(seed, () => {}) }],
            [500, () => {}]
        ])
    }
    function buildSteps() {
        let s = []
        for (let seed of seeds) s = s.concat(seedSteps(seed))
        // Another screen builds the same camps
        s.push([() => true, () => {
            other = gameComponent.createObject(bench.contentItem, {x: bench.width, width: 400, height: 300,
                                                                   muted: true, recordStoreName: storeName})
        }])
        for (let seed of seeds.slice(0, 3)) {
            s.push([() => true, () => other.applyScenario("village", 0, seed)])
            s.push([() => inCamp(other), () => {
                let mine = results.find(r => r.seed === seed)
                check(mine && signature(other) === mine.signature,
                      "seed " + seed + ": another screen builds the same cave")
            }])
        }
        if (outDir !== "") {
            // The buildings' shadows from the campfire
            s.push([() => true, () => game.applyScenario("village", 0, seeds[0])])
            s.push([() => inCamp(game), () => { game.pixelPerUnit = 28 }])
            s.push([500, () => {
                let c = campfire(game)
                game.player.xWu = c.xWu
                game.player.yWu = c.yWu + 8
                nudger.start()
            }])
            s.push([2500, () => { nudger.stop(); saveGame("shadows") }])
            // The same with the lanterns out: what is left is the campfire's
            s.push([300, () => {
                for (let t of game.torches)
                    for (let l of t.data) if (l && l.castsShadows !== undefined) l.enabled = false
            }])
            s.push([500, () => saveGame("shadows-fire-only")])
            s.push([300, () => { game.pixelPerUnit = 55 }])
        }
        s.push([() => true, () => judge()])
        s.push([300, () => {
            other.destroy()
            game.destroy()
        }])
        s.push([300, () => {
            console.log("[Cave] done,", failures, "failed")
            Qt.exit(failures)
        }])
        return s
    }

    function judge() {
        let c = Balance.camp, n = results.length
        let list = (f, show) => results.filter(f).map(r => r.seed + (show ? " (" + show(r) + ")" : "")).join(", ")
        let distinct = {}
        for (let r of results) distinct[r.signature] = true
        check(n === seeds.length, n + " of " + seeds.length + " seeds built a camp")
        check(Object.keys(distinct).length === n, n + " seeds build " + Object.keys(distinct).length + " different outlines")
        let floors = results.map(r => r.floor)
        check(results.every(r => r.floor >= 1.3 * 400 && r.floor <= 1.8 * 400),
              "the camp is about 1.5 times the old 400 cells: " + Math.min.apply(null, floors) + " to "
              + Math.max.apply(null, floors) + " cells of floor and buildings " + list(r => r.floor < 520 || r.floor > 720, r => r.floor))
        check(results.every(r => r.shapes >= 8),
              "no box: each camp's rows take at least 8 different spans (fewest "
              + Math.min.apply(null, results.map(r => r.shapes)) + ")")
        let secs = results.map(r => r.seconds)
        check(results.every(r => r.path.length > 0 && r.seconds <= c.maxWalk),
              "the walk from the entrance to the stairs takes " + Math.min.apply(null, secs).toFixed(2) + " to "
              + Math.max.apply(null, secs).toFixed(2) + " s at move speed " + Balance.knight.moveSpeed
              + ", at most maxWalk " + c.maxWalk + " s " + list(r => !(r.seconds <= c.maxWalk), r => r.seconds.toFixed(2)))
        let ms = results.map(r => r.walkMs)
        check(results.every(r => r.walked && r.walkMs > 0),
              "the knight walks that way to the stairs on every seed, in " + (Math.min.apply(null, ms) / 1000).toFixed(2)
              + " to " + (Math.max.apply(null, ms) / 1000).toFixed(2) + " s of the bench's clock")
        check(results.every(r => r.placed),
              "the campfire on the way, the innkeeper in the tavern, the smith at his anvil and the witch at her tree, "
              + "all reached from the entrance " + list(r => !r.placed))
        check(results.every(r => r.tunnels), "the entrance and the exit tunnel are open " + list(r => !r.tunnels))
        check(results.every(r => r.shading), "the tavern's and the smithy's walls block the light " + list(r => !r.shading))
        check(results.every(r => r.lit),
              "the campfire's light casts shadows and reaches the buildings (radius " + results[0].fireRadius
              + " wu, nearest building wall " + results[0].nearestWall.toFixed(1) + " wu) " + list(r => !r.lit))
    }

    Timer {
        id: script
        property int i: 0
        property real waitedMs: 0
        interval: 20
        repeat: true
        onTriggered: {
            if (i === 0 && bench.steps.length === 0) bench.steps = bench.buildSteps()
            let step = bench.steps[i]
            waitedMs += interval
            let ready = typeof step[0] === "number" ? waitedMs >= step[0] : step[0]()
            if (!ready) {
                if (waitedMs > 30000) {
                    console.log("[Cave] FAIL step", i, "timed out")
                    Qt.exit(failures + 100)
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
