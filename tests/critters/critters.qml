// Critter bench - spiders, mice and rats scurry through the dungeon and a
// knight walking over one squashes it (issue #324, Balance.critters).
//
// On 4 seeds at two depths the dungeon's rooms and corridors hold critters
// as Balance.critters lays them out: each room at most perRoom rounded up,
// corridors one per about perCorridorCells cells, every one on a floor
// cell and none near where the knights come in; all three kinds turn up.
// Another screen lays out the same critters from the same seed. A
// critter is drawn only: no body, no enemy. A resting one scurries now
// and then. A knight standing near one startles it and it runs until it
// is out of reach. A knight walking at one squashes it: it is gone, the
// squash is heard as sfx/critter_squash, a mark of its kind's colour lies
// where it was, and the knight walked on over the spot. Neither hurts the
// knight, adds a kill or a chain link, or is a lock-on target. Prints one
// PASS or FAIL line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/critters/critters.qml
//
// With "fps" it measures instead, with a window: on one seed, the
// dungeon with no critters, with the game's, and full of critters
// (perRoom 12, one per 2 corridor cells), each for 10 s while the knight
// walks from room to room, it counts the frames the window draws and the
// physics steps, and times 600 steps of the critters' own work. Prints
// one line per run and a JSON line, and exits 0.
//
//   qml -I <build>/bin/qml tests/critters/critters.qml -- fps

import QtQuick
import QtQuick.Window
import "../../src"

Window {
    id: bench
    width: 1100
    height: 800
    visible: true
    color: "#1a1a2e"

    property var game: null
    property var other: null
    property int failures: 0
    readonly property string storeName: "ShapesAndStoneCrittersBench"
    readonly property var seeds: [424242, 1000, 8919, 16838]
    readonly property bool fpsMode: Qt.application.arguments.indexOf("fps") >= 0

    function check(ok, what) {
        console.log("[Critters]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    property var gameComponent: null
    Component.onCompleted: {
        gameComponent = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComponent.status !== Component.Ready) {
            console.log("[Critters] FAIL", gameComponent.errorString())
            Qt.exit(1)
            return
        }
        game = gameComponent.createObject(bench.contentItem, {width: bench.width, height: bench.height,
                                                              muted: true, recordStoreName: storeName})
        game.descentIntro = false
        script.start()
    }

    function inDungeon(g) { return g && g.player && g.levelType === "dungeon" && !g.resetting }
    function cellOf(g, x, y) { return [Math.floor(x / g.cellSize), Math.floor(y / g.cellSize)] }
    function roomOf(g, x, y) {
        let c = cellOf(g, x, y)
        return g.rooms.findIndex(r => c[0] >= r.x && c[0] < r.x + r.w && c[1] >= r.y && c[1] < r.y + r.h)
    }
    function knightAt(g) {
        return { x: g.player.xWu + g.player.widthWu / 2, y: g.player.yWu - g.player.heightWu / 2 }
    }
    // Put this knight's centre at (x, y)
    function placeKnight(g, x, y) {
        g.player.xWu = x - g.player.widthWu / 2
        g.player.yWu = y + g.player.heightWu / 2
    }
    function enemyNear(g, x, y, r) {
        return g.enemies.some(e => e && e.destroyed === false && Math.hypot(e.centreXWu - x, e.centreYWu - y) < r)
    }
    function critterKey(cs) {
        return cs.map(c => c.kind + "@" + c.xWu.toFixed(3) + "," + c.yWu.toFixed(3)).join(" ")
    }

    // What one dungeon's critters are, as the checks read them
    function survey(g, seed, depth) {
        let t = Balance.critters, cs = g.critters
        let spawn = g.rooms[0]
        let sx = (spawn.x + spawn.w / 2) * g.cellSize + 0.5, sy = (spawn.y + spawn.h / 2) * g.cellSize - 0.5
        let perRoom = g.rooms.map(() => 0), halls = 0, kinds = {}
        for (let c of cs) {
            let cell = cellOf(g, c.xWu, c.yWu)
            if (g.grid[cell[1]][cell[0]] === g.cellHallway) halls++
            let r = roomOf(g, c.xWu, c.yWu)
            if (r >= 0) perRoom[r]++
            kinds[c.kind] = (kinds[c.kind] || 0) + 1
        }
        let hallCells = 0
        for (let row of g.grid) for (let v of row) if (v === g.cellHallway) hallCells++
        return {
            seed: seed, depth: depth, count: cs.length, rooms: g.rooms.length, halls: halls, hallCells: hallCells,
            maxPerRoom: Math.max(...perRoom), inRooms: perRoom.filter(n => n > 0).length, kinds: kinds,
            onFloor: cs.every(c => g.critterFree(c.xWu, c.yWu)),
            clearOfSpawn: cs.every(c => Math.hypot(c.xWu - sx, c.yWu - sy) >= t.clearOfSpawn - 0.6),
            drawnOnly: cs.every(c => c.objectName === "critter" && c.categories === undefined
                                && c.world === undefined && g.enemies.indexOf(c) < 0),
            sizes: cs.every(c => c.sizeWu === t.kinds[c.kind].size),
            key: critterKey(cs)
        }
    }

    // A critter set up for the knight to stand by or walk at, the same
    // on every run however far the critters have scurried: the floor cell
    // nearest this knight whose centre has floor on side `dir` of it, d wu
    // off, room for the knight's box on the way to it and on past it, no
    // enemy within 12 wu and no other critter within d + 3 wu. The resting
    // or wandering critter nearest that cell, not `skip`, is put on its
    // centre to rest there. [critter, x, y, dir], x and y where the knight
    // goes, or null
    function setUpCritter(g, d, dirs, skip) {
        let k = knightAt(g)
        let cells = []
        for (let gy = 0; gy < g.gridHeight; gy++)
            for (let gx = 0; gx < g.gridWidth; gx++)
                if (g.grid[gy][gx] !== g.cellWall)
                    cells.push([(gx + 0.5) * g.cellSize, (gy + 0.5) * g.cellSize])
        cells.sort((a, b) => Math.hypot(a[0] - k.x, a[1] - k.y) - Math.hypot(b[0] - k.x, b[1] - k.y))
        let free = (x, y, dir) => {
            // The knight's box, and the way to the critter and on past it
            for (let s = -0.6; s <= d + 1.6; s += 0.25)
                for (let o of [-0.55, 0, 0.55])
                    if (!g.critterFree(x + dir[0] * s - dir[1] * o, y + dir[1] * s + dir[0] * o)) return false
            return true
        }
        for (let p of cells) {
            if (!g.critterFree(p[0], p[1]) || enemyNear(g, p[0], p[1], 12)) continue
            if (g.critters.some(c => Math.hypot(c.xWu - p[0], c.yWu - p[1]) < d + 3)) continue
            for (let dir of dirs) {
                let x = p[0] - dir[0] * d, y = p[1] - dir[1] * d
                if (!free(x, y, dir)) continue
                let list = g.critters.filter(c => c !== skip && (c.mood === "rest" || c.mood === "wander"))
                list.sort((a, b) => Math.hypot(a.xWu - p[0], a.yWu - p[1]) - Math.hypot(b.xWu - p[0], b.yWu - p[1]))
                if (list.length === 0) return null
                let c = list[0]
                c.xWu = p[0]
                c.yWu = p[1]
                c.mood = "rest"
                c.moodLeft = 60
                c.from = null
                return [c, x, y, dir]
            }
        }
        return null
    }

    property var results: []
    property var fled: null
    property var stomp: null
    property var before: null
    property var wanderers: []

    // --- The checks ---
    function buildSteps() {
        let s = []
        // Laid out from the seed
        for (let depth of [0, 3])
            for (let seed of seeds) {
                s.push([() => true, () => game.applyScenario("dungeon", depth, seed)])
                s.push([() => inDungeon(game) && game.critters.length > 0, () => results.push(survey(game, seed, depth))])
            }
        s.push([() => true, () => judge()])
        // Another screen lays out the same ones
        s.push([() => true, () => {
            other = gameComponent.createObject(bench.contentItem, {x: bench.width, width: 400, height: 300,
                                                                   muted: true, recordStoreName: storeName})
            other.descentIntro = false
            other.applyScenario("dungeon", 0, seeds[1])
        }])
        s.push([() => inDungeon(other) && other.critters.length > 0, () => {
            let mine = results.find(r => r.seed === seeds[1] && r.depth === 0)
            let theirs = survey(other, seeds[1], 0)
            check(mine && theirs.key === mine.key && theirs.count === mine.count,
                  "seed " + seeds[1] + ": another screen lays out the same " + theirs.count + " critters")
            other.destroy()
            other = null
        }])
        // A resting critter scurries now and then; a knight far off
        // does not startle it
        s.push([() => true, () => game.applyScenario("dungeon", 0, seeds[0])])
        s.push([() => inDungeon(game) && game.critters.length > 0, () => {
            let k = knightAt(game)
            wanderers = game.critters.filter(c => {
                let d = Math.hypot(c.xWu - k.x, c.yWu - k.y)
                return d > Balance.critters.kinds[c.kind].notice + 1 && d < Balance.critters.awake
            }).map(c => ({ c: c, x: c.xWu, y: c.yWu, moods: {} }))
        }])
        for (let i = 0; i < 40; i++)
            s.push([250, () => { for (let w of wanderers) w.moods[w.c.mood] = true }])
        s.push([() => true, () => {
            let moved = wanderers.filter(w => Math.hypot(w.c.xWu - w.x, w.c.yWu - w.y) > 0.05)
            check(wanderers.length > 0 && moved.length > 0 && wanderers.every(w => !w.moods.flee && !w.moods.startled)
                  && wanderers.every(w => game.critterFree(w.c.xWu, w.c.yWu)),
                  "over 10 s " + moved.length + " of the " + wanderers.length
                  + " critters awake but out of the knight's notice scurried, none fled, all on the floor")
        }])
        // A knight standing near one: it startles and runs
        s.push([() => true, () => {
            before = { hp: game.player.hp, kills: game.runKills, chain: game.chainLinks }
            let p = setUpCritter(game, 1.6, [[1, 0], [-1, 0], [0, 1], [0, -1]], null)
            if (!p) { check(false, "a critter with room round it to stand by"); return }
            fled = { c: p[0], kind: p[0].kind, x: p[0].xWu, y: p[0].yWu, moods: {} }
            placeKnight(game, p[1], p[2])
            game.player.moveX = 0
            game.player.moveY = 0
        }])
        for (let i = 0; i < 12; i++)
            s.push([100, () => { if (fled && fled.c) fled.moods[fled.c.mood] = true }])
        s.push([() => true, () => {
            if (!fled) return
            let k = knightAt(game), c = fled.c
            let d = c ? Math.hypot(c.xWu - k.x, c.yWu - k.y) : -1
            check(c && fled.moods.startled !== undefined && fled.moods.flee && d > Balance.critters.kinds[fled.kind].notice,
                  "a " + fled.kind + " 1.6 wu from a standing knight startled and ran: " + d.toFixed(2)
                  + " wu off after 1.2 s, its moods " + Object.keys(fled.moods).join(", "))
            check(c && c.from === game.player, "it runs from this screen's knight")
            check(game.critterFree(c.xWu, c.yWu), "it stays on the floor while it runs")
        }])
        // A knight walking at one squashes it
        s.push([() => true, () => {
            game.logSounds = true
            game.clearSoundLog()
            let p = setUpCritter(game, 1.3, [[1, 0], [-1, 0]], fled ? fled.c : null)
            if (!p) { check(false, "a critter with room to walk at it"); return }
            stomp = { c: p[0], kind: p[0].kind, x: p[0].xWu, y: p[0].yWu, dir: p[3], squashed: 0,
                      count: game.critters.length, marks: game.critterMarks.length }
            placeKnight(game, p[1], p[2])
            let lockBefore = game._pickLockTarget()
            stomp.lock = lockBefore && lockBefore.objectName === "critter"
            game.critterSquashed.connect(bench.onSquashed)
            game.player.moveX = p[3][0]
        }])
        s.push([400, () => {
            if (!stomp) return
            game.player.moveX = 0
            game.critterSquashed.disconnect(bench.onSquashed)
            let k = knightAt(game)
            let heard = game.soundLog.filter(x => x.cue === "sfx/critter_squash")
            let mark = game.critterMarks[game.critterMarks.length - 1]
            check(stomp.squashed === 1 && game.critters.indexOf(stomp.c) < 0
                  && game.critters.length === stomp.count - 1 && game.crittersSquashed === 1,
                  "a knight walking at a " + stomp.kind + " squashed it: " + game.critters.length
                  + " critters left of " + stomp.count)
            check(heard.length === 1 && heard[0].what === stomp.kind
                  && heard[0].pitch === Balance.critters.kinds[stomp.kind].pitch,
                  "its squash is heard once as sfx/critter_squash, " + (heard.length ? heard[0].pitch : "-")
                  + " semitones (" + heard.length + " heard)")
            check(game.critterMarks.length === stomp.marks + 1 && mark
                  && Math.hypot(mark.xWu - stomp.at.x, mark.yWu - stomp.at.y) < 1e-6
                  && Qt.colorEqual(mark.color, Balance.critters.kinds[stomp.kind].mark)
                  && Math.abs(mark.sizeWu - stomp.size * Balance.critters.markSize) < 1e-6,
                  "a mark in its kind's colour lies where it was squashed")
            check((k.x - stomp.x) * stomp.dir[0] > 0.6,
                  "the knight walked on over the spot: " + ((k.x - stomp.x) * stomp.dir[0]).toFixed(2) + " wu past it")
            check(!stomp.lock && game._pickLockTarget() === null,
                  "no critter is a lock-on target: the lock-on finds nothing beside it")
        }])
        s.push([() => true, () => {
            check(game.player.hp === before.hp, "the critters did not hurt the knight: " + game.player.hp + " HP")
            check(game.runKills === before.kills && game.chainLinks === before.chain && game.chainLinks === 0
                  && game.fightRecord.kills === 0,
                  "a squashed critter is no kill and no chain link: " + game.runKills + " kills, "
                  + game.chainLinks + " links")
        }])
        s.push([300, () => {
            game.destroy()
        }])
        s.push([300, () => {
            console.log("[Critters] done,", failures, "failed")
            Qt.exit(failures)
        }])
        return s
    }
    function onSquashed(kind, x, y, knight) {
        if (!stomp) return
        stomp.squashed++
        stomp.at = { x: x, y: y }
        stomp.size = Balance.critters.kinds[kind].size
        stomp.by = knight
    }

    function judge() {
        let t = Balance.critters
        let list = (rs, f) => rs.filter(f).map(r => "depth " + r.depth + " seed " + r.seed).join(", ")
        check(results.length === 2 * seeds.length, results.length + " dungeons surveyed")
        for (let r of results)
            check(r.count >= r.rooms && r.inRooms >= r.rooms / 2 && r.halls >= 1 && r.maxPerRoom <= Math.ceil(t.perRoom),
                  "depth " + r.depth + " seed " + r.seed + ": " + r.count + " critters, " + r.inRooms + " of "
                  + r.rooms + " rooms hold some (at most " + r.maxPerRoom + "), " + r.halls + " in corridors of "
                  + r.hallCells + " cells")
        check(results.every(r => r.onFloor), "every critter stands on a floor cell " + list(results, r => !r.onFloor))
        check(results.every(r => r.clearOfSpawn), "none within " + t.clearOfSpawn + " wu of where the knights come in "
              + list(results, r => !r.clearOfSpawn))
        check(results.every(r => r.drawnOnly), "a critter is drawn only: no body, no enemy "
              + list(results, r => !r.drawnOnly))
        check(results.every(r => r.sizes), "each is its kind's size " + list(results, r => !r.sizes))
        let kinds = {}
        for (let r of results) for (let k in r.kinds) kinds[k] = (kinds[k] || 0) + r.kinds[k]
        check(Object.keys(t.kinds).every(k => kinds[k] > 0), "all kinds turn up: " + JSON.stringify(kinds))
        let keys = {}
        for (let r of results) keys[r.key] = true
        check(Object.keys(keys).length === results.length, "the " + results.length + " dungeons hold "
              + Object.keys(keys).length + " different layouts")
    }

    // --- The frame-rate runs ---
    property int frames: 0
    property int physicsSteps: 0
    Connections {
        target: bench
        function onFrameSwapped() { bench.frames++ }
    }
    Connections {
        target: game ? game.physics : null
        function onStepped() { bench.physicsSteps++ }
    }
    property var runs: []
    property int roomAt: 0
    function fpsSteps() {
        let s = []
        let cases = [
            { name: "none", perRoom: 0, perCorridorCells: 1e9 },
            { name: "game", perRoom: Balance.critters.perRoom, perCorridorCells: Balance.critters.perCorridorCells },
            { name: "full", perRoom: 12, perCorridorCells: 2 }
        ]
        for (let cs of cases) {
            s.push([() => true, () => {
                Balance.critters.perRoom = cs.perRoom
                Balance.critters.perCorridorCells = cs.perCorridorCells
                game.applyScenario("dungeon", 0, seeds[0])
            }])
            s.push([() => inDungeon(game), () => { roomAt = 0 }])
            s.push([1500, () => { frames = 0; physicsSteps = 0; walker.start() }])
            s.push([10000, () => {
                walker.stop()
                let run = { critters: cs.name, count: game.critters.length + game.crittersSquashed,
                            squashed: game.crittersSquashed, fps: frames / 10, physicsPerSecond: physicsSteps / 10 }
                // The critters' own work, 600 steps with the knight in
                // the middle of the dungeon
                let mid = game.rooms[Math.floor(game.rooms.length / 2)]
                placeKnight(game, (mid.x + mid.w / 2) * game.cellSize, (mid.y + mid.h / 2) * game.cellSize)
                let t0 = Date.now()
                for (let i = 0; i < 600; i++) game._stepCritters(1 / 60)
                run.critterMsPerStep = (Date.now() - t0) / 600
                runs.push(run)
                console.log("[Critters] fps", JSON.stringify(run))
            }])
        }
        s.push([() => true, () => {
            console.log("[Critters] FPS " + JSON.stringify({ platform: Qt.platform.pluginName, runs: runs }))
            game.destroy()
        }])
        s.push([300, () => Qt.exit(0)])
        return s
    }
    // The knight walks from room to room: to the next room's middle
    // every 1.2 s, then on east, so the critters there flee and some are
    // squashed
    Timer {
        id: walker
        interval: 1200
        repeat: true
        onTriggered: {
            let r = game.rooms[bench.roomAt % game.rooms.length]
            bench.roomAt++
            placeKnight(game, (r.x + 1) * game.cellSize, (r.y + r.h / 2) * game.cellSize)
            game.player.moveX = 1
        }
    }

    property var steps: []
    Timer {
        id: script
        property int i: 0
        property real waitedMs: 0
        interval: 20
        repeat: true
        onTriggered: {
            if (i === 0 && bench.steps.length === 0) bench.steps = bench.fpsMode ? bench.fpsSteps() : bench.buildSteps()
            let step = bench.steps[i]
            waitedMs += interval
            let ready = typeof step[0] === "number" ? waitedMs >= step[0] : step[0]()
            if (!ready) {
                if (waitedMs > 30000) {
                    console.log("[Critters] FAIL step", i, "timed out")
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
