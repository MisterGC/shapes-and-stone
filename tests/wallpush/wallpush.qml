// Wall push bench - an enemy shoved against the wall above it, its top-left
// corner inside the wall, still sees and walks from where it stands
// (issue #184).
//
// Starts single player on a fixed seed and stops the level's enemies. It
// finds a floor cell under a wall one cell thick, a patrol point beyond
// it no farther than one below, spawns a grunt there and shoves it into
// the wall until its corner is inside, as a hole's creatures crawl out. With the knight
// out of sight the grunt must patrol again, not stand still; a second
// grunt shoved the same way, with the knight 4 wu below it in plain sight,
// must spot the knight and go for it. Prints one PASS or FAIL line per
// check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/wallpush/wallpush.qml

import QtQuick
import QtQuick.Window
import "../../src"

Window {
    id: bench
    width: 800
    height: 600
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0

    function check(ok, what) {
        console.log("[WallPush]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[WallPush] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true})
        script.start()
    }

    function wall(gx, gy) {
        return gx < 0 || gy < 0 || gx >= game.gridWidth || gy >= game.gridHeight
            || game.grid[gy][gx] === game.cellWall
    }
    // A floor cell (gx, gy) under a wall that runs on left and right of it,
    // with floor left and right of it and two cells of floor below it. A
    // wall one cell thick, with floor beyond it, comes first: a patrol
    // point beyond it is no farther than one below
    function findSpot() {
        let found = null
        for (let gy = 1; gy < game.gridHeight - 1; gy++)
            for (let gx = 1; gx < game.gridWidth - 1; gx++)
                if (wall(gx - 1, gy + 1) && wall(gx, gy + 1) && wall(gx + 1, gy + 1) && !wall(gx, gy)
                        && !wall(gx - 1, gy) && !wall(gx + 1, gy)
                        && !wall(gx, gy - 1) && !wall(gx, gy - 2)
                        && !game.doors.some(d => d.cell === gx + "," + gy || d.cell === gx + "," + (gy - 1))) {
                    if (!wall(gx, gy + 2)) return {gx: gx, gy: gy}
                    found = found || {gx: gx, gy: gy}
                }
        return found
    }
    property var spot: null
    readonly property real cs: game ? game.cellSize : 2

    function centre(o) { return Qt.point(o.xWu + o.widthWu / 2, o.yWu - o.heightWu / 2) }
    function dist(a, b) { return Math.hypot(a.x - b.x, a.y - b.y) }
    // Puts the knight's centre at (x, y)
    function placeKnight(x, y) {
        let p = game.player
        p.xWu = x - p.widthWu / 2
        p.yWu = y + p.heightWu / 2
    }
    // A grunt spawned with its corner in the wall above the spot, as a
    // hole's creatures crawl out, and shoved up into it
    function shovedGrunt() {
        let n = game.enemies.length
        game.spawnEnemy(spot.gx * cs + 0.6, (spot.gy + 1) * cs + 0.1, 1, "grunt", 1)
        let e = game.enemies[n]
        e.knockback(0, 1, 4)
        return e
    }
    function cornerInWall(e) {
        return wall(Math.floor(e.xWu / cs), Math.floor(e.yWu / cs))
    }

    property var grunt: null
    property var pushedAt: null
    property real farthest: 0
    property var seenStates: []
    property real startDist: 0
    property real nearest: 1e9

    property var steps: [
        [() => game.screen === "title", () => {
            // A seed whose first dungeon has a wall one cell thick
            game.masterSeed = 424242
            game.screen = "game"
            game.forceActiveFocus()
        }],
        [() => game.player && game.enemies.length > 0, () => {
            for (let e of game.enemies) e.halt()
            spot = findSpot()
            check(spot !== null && !wall(spot.gx, spot.gy + 2),
                  "the level has a floor cell under a wall one cell thick"
                  + (spot ? " (" + spot.gx + "," + spot.gy + ")" : ""))
            if (!spot) { Qt.exit(failures); return }
            // The knight far off, out of the grunt's sight
            let far = null
            for (let gy = 0; gy < game.gridHeight && !far; gy++)
                for (let gx = 0; gx < game.gridWidth && !far; gx++)
                    if (!wall(gx, gy) && Math.hypot(gx - spot.gx, gy - spot.gy) * cs > 20)
                        far = Qt.point(gx * cs + cs / 2, gy * cs + cs / 2)
            placeKnight(far.x, far.y)
            grunt = shovedGrunt()
        }],
        // The shove has died down
        [() => grunt._knockT <= 0, () => {
            check(cornerInWall(grunt), "the shoved grunt's top-left corner is inside the wall ("
                  + grunt.xWu.toFixed(2) + ", " + grunt.yWu.toFixed(2) + ")")
            check(!wall(Math.floor(centre(grunt).x / cs), Math.floor(centre(grunt).y / cs)),
                  "its centre stands on the floor")
            pushedAt = centre(grunt)
            watch.restart()
        }],
        [4000, () => {
            watch.stop()
            check(grunt.aiState === "patrol", "with no knight in sight it is on patrol ("
                  + grunt.aiState + ")")
            check(farthest >= 1.0, "it patrols away from the wall instead of standing still (farthest "
                  + farthest.toFixed(2) + " wu from where it was shoved)")
            grunt.halt()
            // The knight 4 wu below the spot, in plain sight of a grunt there
            placeKnight(spot.gx * cs + cs / 2, (spot.gy - 2) * cs + cs / 2)
            grunt = shovedGrunt()
        }],
        [() => grunt._knockT <= 0, () => {
            check(cornerInWall(grunt), "the second shoved grunt's top-left corner is inside the wall ("
                  + grunt.xWu.toFixed(2) + ", " + grunt.yWu.toFixed(2) + ")")
            startDist = dist(centre(grunt), centre(game.player))
            nearest = startDist
            seenStates = []
            check(startDist <= Balance.enemy.sightRange, "the knight stands within sight range ("
                  + startDist.toFixed(2) + " wu)")
            watch.restart()
        }],
        [3000, () => {
            watch.stop()
            check(seenStates.indexOf("chase") >= 0, "it spots the knight and gives chase (states "
                  + seenStates.join(", ") + ")")
            check(nearest <= startDist - 1.0, "it goes for the knight (from "
                  + startDist.toFixed(2) + " to " + nearest.toFixed(2) + " wu)")
            console.log("[WallPush] done,", failures, "failed")
        }],
        // Torn down before quitting, as the impact bench does
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ]

    // What the grunt does while it is watched
    Timer {
        id: watch
        interval: 50
        repeat: true
        onTriggered: {
            if (!grunt) return
            let c = centre(grunt)
            if (pushedAt) farthest = Math.max(farthest, dist(c, pushedAt))
            nearest = Math.min(nearest, dist(c, centre(game.player)))
            if (seenStates.indexOf(grunt.aiState) < 0) seenStates = seenStates.concat([grunt.aiState])
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
                if (waitedMs > 20000) {
                    console.log("[WallPush] FAIL step", i, "timed out")
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
