// Secrets bench - a secret door opens with E at the right wall, and a
// secret room holds a cache (issue #128).
//
// Lands in the dojo's features scenario, which hides a secret room, and
// stills the enemies. The secret room is rock: its cells and the cracked
// wall cell are walls, the clue shows over that cell, and the minimap
// shows the room as rock even with the knight right in front of it. E in
// front of it does nothing; a dash into the plain wall one tile off along
// it does nothing; a dash that reaches the cracked face at a flat angle
// glances off it; a dash straight into it bursts it open: the room and
// the door are floor, the minimap shows them, the knight walks in, the
// cache stands on its floor, each thing's gold above the most the same
// thing holds elsewhere, and the run counts one secret found. Then it lays out 50 seeds across the danger
// bands: each secret room rock while closed, the exit reachable from the
// start without it and the room not, its front cell reachable, the same
// twice on a seed and danger, more secrets the higher the band. On fixed
// seeds the witch's reading mentions a hidden chamber exactly when the
// next dungeon has one. With an out dir and a window it saves clue.png,
// the cracked wall cell between plain ones, and opened.png. Prints one
// PASS or FAIL line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/secrets/secrets.qml
//   qml -I <build>/bin/qml tests/secrets/secrets.qml -- <out dir>

import QtQuick
import QtQuick.Window
import QtTest
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
    readonly property int seeds: 50

    function check(ok, what) {
        console.log("[Secrets]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Secrets] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                  recordStoreName: "ShapesAndStoneSecretsBench"})
        script.start()
    }

    function p() { return game.player }
    function centre() { return { x: p().xWu + p().widthWu / 2, y: p().yWu - p().heightWu / 2 } }
    function standAt(x, y) {
        p().xWu = x - p().widthWu / 2
        p().yWu = y + p().heightWu / 2
        p().moveX = 0
        p().moveY = 0
    }
    function cellCentre(gx, gy) { return { x: (gx + 0.5) * game.cellSize, y: (gy + 0.5) * game.cellSize } }
    // The secret's room cells and its cracked one
    function cellsOf(s) {
        let out = [[s.gx, s.gy]]
        for (let y = s.room.y; y < s.room.y + s.room.h; y++)
            for (let x = s.room.x; x < s.room.x + s.room.w; x++) out.push([x, y])
        return out
    }
    // The cells reachable from (sx, sy) over cells not walls, 4-connected
    function reach(sx, sy) {
        let seen = {}, todo = [[sx, sy]]
        seen[sy * game.gridWidth + sx] = true
        while (todo.length > 0) {
            let c = todo.pop()
            for (let d of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
                let x = c[0] + d[0], y = c[1] + d[1]
                if (x < 0 || y < 0 || x >= game.gridWidth || y >= game.gridHeight) continue
                if (game.grid[y][x] === game.cellWall || seen[y * game.gridWidth + x]) continue
                seen[y * game.gridWidth + x] = true
                todo.push([x, y])
            }
        }
        return seen
    }
    function grab(name) {
        if (outDir === "") return
        bench.contentItem.grabToImage(r => {
            let ok = r.saveToFile(outDir + "/" + name)
            console.log("[Secrets]", ok ? "saved" : "could not save", outDir + "/" + name)
        })
    }
    function snapCamera() {
        game.camera.target = null
        game.camera.target = p()
    }
    // The knight's centre k cells along the wall from the floor cell in
    // front of secret s, gap wu off its face
    function standBefore(s, k, gap) {
        let c = cellCentre(s.gx + s.ny * k, s.gy + s.nx * k)
        let d = game.cellSize / 2 + p().widthWu / 2 + gap
        standAt(c.x + s.nx * d, c.y + s.ny * d)
    }
    // A dash at deg degrees off straight into secret s's wall, turned
    // along it towards +k; the knight's moves are on screen, y down
    function dashAt(s, deg) {
        let a = deg * Math.PI / 180
        let wx = -s.nx * Math.cos(a) + s.ny * Math.sin(a), wy = -s.ny * Math.cos(a) + s.nx * Math.sin(a)
        p().dashCooldown = 0
        p().mana = 1000
        p().moveX = wx
        p().moveY = -wy
        p().dash()
        p().moveX = 0
        p().moveY = 0
    }
    property int glances: 0
    Connections {
        target: bench.game
        function onSecretGlanced(cell) { bench.glances++ }
    }

    property var secret: null
    property int goldBefore: 0

    property var steps: [
        [() => game.screen === "title", () => {
            let t = Balance.dungeon
            check(t.secrets && t.secrets.length === 3 && t.secretShowcase >= 1 && t.secretSize >= 2
                  && t.cacheThings > 0 && t.cacheCrystal.length === 3 && t.cacheLoot.urn && t.cacheLoot.crystal,
                  "Balance.dungeon has the secrets' counts, size and cache")
            game.applyScenario("features")
        }],
        [500, () => {
            for (let e of game.enemies) if (e && e.halt) e.halt()
            p().hp = 100000
            check(game.secretRooms.length === Balance.dungeon.secretShowcase,
                  "the features scenario hides " + game.secretRooms.length + " secret room(s)")
            secret = game.secretRooms[0] || null
            if (!secret) return
            check(cellsOf(secret).every(c => game.grid[c[1]][c[0]] === game.cellWall),
                  "closed, its cracked cell " + secret.cell + " and its room are rock")
            check(secret.clue && secret.clue.visible, "the clue shows over the cracked cell")
            let front = cellCentre(secret.fx, secret.fy)
            check(game.grid[secret.fy][secret.fx] === game.cellRoom
                  && !game.features.some(f => f.gx === secret.fx && f.gy === secret.fy),
                  "the floor cell in front of it is a room's, free of features")
            game.fx = true
            standBefore(secret, 0, 0.3)
            snapCamera()
            game.revealAroundPlayer()
        }],
        [300, () => {
            let explored = cellsOf(secret).filter(c => game.mapCell(c[0], c[1]) !== "")
            check(explored.length > 0 && explored.every(c => game.mapCell(c[0], c[1]) === "rock"),
                  "in front of it the minimap shows its " + explored.length + " explored cells as rock")
            grab("clue.png")
            press(Qt.Key_E)
        }],
        [300, () => {
            check(!secret.open && cellsOf(secret).every(c => game.grid[c[1]][c[0]] === game.cellWall),
                  "E in front of it does nothing")
            // A dash into the plain wall one tile off along it
            standBefore(secret, 1, 0.3)
        }],
        [100, () => dashAt(secret, 0)],
        [600, () => {
            check(!secret.open && glances === 0, "a dash straight into the plain wall one tile off does nothing")
            // A flat dash that reaches the cracked face
            standBefore(secret, -0.4, 0.05)
        }],
        [100, () => dashAt(secret, 65)],
        [600, () => {
            check(!secret.open && glances === 1,
                  "a dash 65 degrees off straight glances off the cracked face, shut (" + glances + " glance)")
            standBefore(secret, 0, 0.3)
        }],
        [100, () => { goldBefore = game.breakables.length; dashAt(secret, 20) }],
        [300, () => {
            check(secret.open && !secret.clue.visible, "a dash 20 degrees off straight into the cracked face bursts it open")
            check(game.grid[secret.gy][secret.gx] === game.cellHallway
                  && cellsOf(secret).slice(1).every(c => game.grid[c[1]][c[0]] === game.cellRoom),
                  "its door and room are floor now")
            game.revealAroundPlayer()
            let explored = cellsOf(secret).filter(c => game.mapCell(c[0], c[1]) !== "")
            check(explored.length > 0 && explored.every(c => game.mapCell(c[0], c[1]) === "floor"),
                  "the minimap shows its " + explored.length + " explored cells as floor")
            check(game.runSecrets === 1, "the run counts 1 secret found (" + game.runSecrets + ")")
            let cache = secret.cache
            let standing = cache.filter(f => game.breakableAt(f.gx + "," + f.gy) !== null)
            check(cache.length >= Balance.dungeon.cacheThings && standing.length === cache.length,
                  "its cache stands on its floor: " + cache.map(f => f.kind).join(", "))
            let richer = cache.every(f => {
                let t = Balance.dungeon.loot[f.kind]
                return game.breakableGold(f.kind, f.gx + "," + f.gy) > t.gold[1] + t.perDepth * game.depth
            })
            check(richer, "each thing of the cache holds more gold than the same thing elsewhere: "
                  + cache.map(f => game.breakableGold(f.kind, f.gx + "," + f.gy)).join(", "))
            let inside = cellCentre(secret.gx - secret.nx, secret.gy - secret.ny)
            let path = game.findPath(centre().x, centre().y, inside.x, inside.y)
            check(path.length > 0, "the enemies' paths lead into it now (" + path.length + " waypoints)")
            // Walk through the door
            p().moveX = -secret.nx
            p().moveY = secret.ny
        }],
        [700, () => {
            p().moveX = 0
            p().moveY = 0
            let c = centre()
            let gx = Math.floor(c.x / game.cellSize), gy = Math.floor(c.y / game.cellSize)
            let s = secret.room
            check(gx >= s.x && gx < s.x + s.w && gy >= s.y && gy < s.y + s.h || (gx === secret.gx && gy === secret.gy),
                  "the knight walks through the opened door (cell " + gx + "," + gy + ")")
            let front = cellCentre(secret.fx, secret.fy)
            standAt(front.x, front.y)
            snapCamera()
        }],
        [400, () => grab("opened.png")]
    ].concat(seedSteps()).concat([[100, () => {
            check(laid.wrong.length === 0, "50 seeds: every secret room rock while closed, the exit reachable without it, "
                  + "the room not, its front cell yes" + (laid.wrong.length ? " - " + laid.wrong.slice(0, 4).join("; ") : ""))
            check(laid.differ.length === 0, "a seed and danger hide the same secrets twice"
                  + (laid.differ.length ? " - " + laid.differ.slice(0, 2).join("; ") : ""))
            let per = [0, 1, 2].map(b => laid[b].dungeons > 0 ? laid[b].secrets / laid[b].dungeons : 0)
            check(per[0] < per[1] && per[1] < per[2] && laid.total > 0,
                  "more secrets the higher the band: " + per.map(x => x.toFixed(2)).join(" / ")
                  + " a dungeon (" + laid.total + " in all)")
        }]]).concat(witchSteps()).concat([
        [100, () => console.log("[Secrets] done,", failures, "failed")],
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ])

    // The secrets of 50 seeds across the bands, each dungeon laid out twice
    property var laid: ({ wrong: [], differ: [], total: 0, 0: { dungeons: 0, secrets: 0 },
                          1: { dungeons: 0, secrets: 0 }, 2: { dungeons: 0, secrets: 0 } })
    function seedSteps() {
        let out = []
        for (let i = 0; i < seeds; i++) {
            out.push([60, () => {
                let seed = 5000 + i * 7919, danger = (i % 10) * 0.33
                game.applyScenario("dungeon", danger, seed)
                let band = game.dangerBand(game.dangerPosition)
                laid[band].dungeons++
                laid[band].secrets += game.secretRooms.length
                laid.total += game.secretRooms.length
                let start = game.rooms[0]
                let from = reach(Math.floor(start.x + start.w / 2), Math.floor(start.y + start.h / 2))
                if (!from[(game.gridHeight - 1) * game.gridWidth + game.exitGridX])
                    laid.wrong.push("seed " + seed + ": the exit is not reachable")
                for (let s of game.secretRooms) {
                    let cells = cellsOf(s)
                    if (!cells.every(c => game.grid[c[1]][c[0]] === game.cellWall))
                        laid.wrong.push("seed " + seed + " " + s.cell + ": not rock while closed")
                    if (cells.some(c => from[c[1] * game.gridWidth + c[0]]))
                        laid.wrong.push("seed " + seed + " " + s.cell + ": its room is reachable closed")
                    if (!from[s.fy * game.gridWidth + s.fx])
                        laid.wrong.push("seed " + seed + " " + s.cell + ": its front cell is not reachable")
                }
                let first = game.secretRooms.map(s => s.cell).join(" ")
                game.applyScenario("dungeon", danger, seed)
                let again = game.secretRooms.map(s => s.cell).join(" ")
                if (first !== again) laid.differ.push("seed " + seed + ": " + first + " / " + again)
            }])
        }
        return out
    }

    // The witch's reading at the camp of depth 0 against the next dungeon
    // built, on fixed seeds: the first with a secret room and the first
    // without from 7001 on
    property var witch: ({ with: -1, without: -1 })
    function witchSteps() {
        return [[60, () => {
            for (let seed = 7001; seed < 7101 && (witch.with < 0 || witch.without < 0); seed++) {
                game.masterSeed = seed
                if (game.secretsOf(2, 0.5) > 0) { if (witch.with < 0) witch.with = seed }
                else if (witch.without < 0) witch.without = seed
            }
            check(witch.with > 0 && witch.without > 0,
                  "seeds " + witch.with + " (a secret room at depth 1) and " + witch.without + " (none)")
        }]].concat([0, 1].map(k => [200, () => {
            let seed = k === 0 ? witch.with : witch.without
            if (seed < 0) return
            game.applyScenario("village", 0.5, seed)
            let reading = game.witchReading().join(" ")
            let says = reading.indexOf("hidden chamber") >= 0
            game.applyScenario("dungeon", 1.5, seed)
            let has = game.secretRooms.length > 0
            check(says === has && game.secretRooms.length === game.foretell(game.levelIndex, 0.5).secrets,
                  "seed " + seed + ": the witch " + (says ? "mentions" : "does not mention")
                  + " a hidden chamber, and the next dungeon has " + game.secretRooms.length)
        }]))
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
                    console.log("[Secrets] FAIL step", i, "timed out")
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
                console.log("[Secrets] FAIL step", i - 1, "threw:", err)
                Qt.exit(failures + 1)
                stop()
            }
        }
    }
}
