// Doors bench - doors open and close with E, are one knight wide, and
// enemies bash closed ones open (issue #127).
//
// Lands in the dojo's features scenario, where every room entrance has a
// door, and stills the enemies. At one door the knight walks into the
// closed leaf, which stops it; E opens it, and the knight walks through;
// E with the knight in the doorway leaves it open, E beside it closes it.
// A closed door hides the knight from an enemy and an open one does not,
// and the enemies' path goes through a closed door when the way around
// is longer than its cost. A grunt that spots the knight through the open
// door chases it; the door shut, the grunt stops at it, winds up with its
// ring for Balance.dungeon.doorBash seconds and bursts it open, and the
// bashed door stays open: E does nothing, it blocks no one, and the grunt
// goes on through. A door shut behind a grunt that came through it is no
// door it bashes. Then it lays out the doors of 50 seeds across the
// danger bands: each on a doorway, never in the entrance's or the exit's
// shaft, about doorShare of the doorways at its band, and the same twice
// on the same seed and danger. With an out dir and a window it saves
// closed.png, open.png, bashing.png and bashed.png. Prints one PASS or
// FAIL line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/doors/doors.qml
//   qml -I <build>/bin/qml tests/doors/doors.qml -- <out dir>

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
        console.log("[Doors]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Doors] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                  recordStoreName: "ShapesAndStoneDoorsBench"})
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
    // The door's axis, a unit step from the corridor into the room
    function into(d) { return d.across ? { x: d.roomSide, y: 0 } : { x: 0, y: d.roomSide } }
    // A point k wu from door d's centre along its axis, into the room
    function along(d, k) { let u = into(d); return { x: d.cxWu + u.x * k, y: d.cyWu + u.y * k } }
    // How far the knight's centre is past door d's leaf, into the room
    function past(d) { let c = centre(), u = into(d); return (c.x - d.cxWu) * u.x + (c.y - d.cyWu) * u.y }
    // The same for an enemy's centre
    function pastOf(d, e) {
        let u = into(d), x = e.xWu + e.widthWu / 2, y = e.yWu - e.heightWu / 2
        return (x - d.cxWu) * u.x + (y - d.cyWu) * u.y
    }
    function walkInto(d, sign) {
        let u = into(d)
        p().moveX = u.x * sign
        p().moveY = -u.y * sign
    }
    function cellOf(x, y) { return [Math.floor(x / game.cellSize), Math.floor(y / game.cellSize)] }
    function walkable(x, y) {
        let c = cellOf(x, y)
        return game.grid[c[1]] !== undefined && game.grid[c[1]][c[0]] !== undefined
            && game.grid[c[1]][c[0]] !== game.cellWall
    }
    // A door with two floor cells on each side along its axis, and a path
    // through it from its room's side when it is closed
    function pickDoor(not) {
        for (let d of game.doors) {
            if (d === not) continue
            let ok = [-4, -2, 2, 4, 5].every(k => { let q = along(d, k); return walkable(q.x, q.y) })
            if (!ok) continue
            let a = along(d, 4), b = along(d, -4)
            let path = game.findPath(a.x, a.y, b.x, b.y)
            if (path.some(w => Math.abs(w.x - d.cxWu) < 0.01 && Math.abs(w.y - d.cyWu) < 0.01)) return d
        }
        return null
    }
    function grab(name) {
        if (outDir === "") return
        bench.contentItem.grabToImage(r => {
            let ok = r.saveToFile(outDir + "/" + name)
            console.log("[Doors]", ok ? "saved" : "could not save", outDir + "/" + name)
        })
    }
    function snapCamera() {
        game.camera.target = null
        game.camera.target = p()
    }

    property var door: null
    property var grunt: null
    // A door shut behind a grunt that came through it, and what the grunt
    // did after
    property var behind: null
    property var after: ({ states: [], bashed: false })
    // The grunt's bash: the physics steps it began and the door broke on,
    // the simulated seconds between and its ring each step of it
    property var bash: ({ started: -1, ended: -1, seconds: 0, ring: 0, samples: 0 })

    property var steps: [
        [() => game.screen === "title", () => {
            let t = Balance.dungeon
            check(t.doorShare && t.doorShare.length === 3 && t.doorWidth > 0 && t.doorBash > 0
                  && t.doorReach > 0 && t.doorPathCost > 0,
                  "Balance.dungeon has the doors' share, width, reach, bash and path cost")
            game.applyScenario("features")
        }],
        [500, () => {
            for (let e of game.enemies) if (e && e.halt) e.halt()
            p().hp = 100000
            let doorways = 0
            for (let gy = 0; gy < game.gridHeight; gy++)
                for (let gx = 0; gx < game.gridWidth; gx++)
                    if (game.doorway(gx, gy)) doorways++
            check(game.doors.length > 0 && game.doors.length === doorways,
                  "the features scenario shows a door on every one of its " + doorways + " doorways ("
                  + game.doors.length + " doors)")
            check(game.doors.every(d => d.doorState === "closed" && d.active),
                  "every door starts closed")
            let w = Balance.dungeon.doorWidth
            check(p().widthWu <= w && w < 2 * p().widthWu && game.doors.every(d => d.leafWu === w),
                  "a door is one knight wide: its leaf " + w + " wu, the knight " + p().widthWu + " wu")
            door = pickDoor()
            check(door !== null, "a door with floor on both sides and the enemies' path through it: "
                  + (door ? door.cell : "none"))
            if (!door) return
            game.fx = true
            let q = along(door, -1.6)
            standAt(q.x, q.y)
            snapCamera()
        }],
        [400, () => grab("closed.png")],
        [100, () => {
            // A closed door stops the knight
            let q = along(door, -2.5)
            standAt(q.x, q.y)
            walkInto(door, 1)
        }],
        [800, () => {
            let edge = -(door.thickWu / 2 + p().widthWu / 2)
            check(past(door) <= edge + 0.05, "walking into the closed door for 0.8 s the knight stops at its leaf: "
                  + past(door).toFixed(2) + " wu past it, the leaf's side at " + edge.toFixed(2))
            p().moveX = 0
            p().moveY = 0
            press(Qt.Key_E)
        }],
        [200, () => {
            check(door.doorState === "open" && !door.active, "E beside it opens it")
            grab("open.png")
        }],
        [100, () => walkInto(door, 1)],
        [800, () => {
            check(past(door) > 1, "the knight walks through the open door (" + past(door).toFixed(2) + " wu past it)")
            // In the doorway E leaves it open
            standAt(door.cxWu, door.cyWu)
        }],
        [100, () => press(Qt.Key_E)],
        [200, () => {
            check(door.doorState === "open", "E with the knight in the doorway leaves it open")
            let q = along(door, -1.2)
            standAt(q.x, q.y)
        }],
        [100, () => press(Qt.Key_E)],
        [200, () => {
            check(door.doorState === "closed" && door.active, "E beside the open door closes it")
            let a = along(door, 3), b = along(door, -3)
            check(!game.hasLineOfSight(a.x, a.y, b.x, b.y), "a closed door hides the knight from an enemy beyond it")
            game.useDoor(door)
            check(game.hasLineOfSight(a.x, a.y, b.x, b.y), "an open one does not")
            game.useDoor(door)
            let path = game.findPath(a.x, a.y, b.x, b.y)
            check(door.shut && path.some(w => Math.abs(w.x - door.cxWu) < 0.01 && Math.abs(w.y - door.cyWu) < 0.01),
                  "the enemies' path goes through the closed door: no way around shorter than its cost "
                  + Balance.dungeon.doorPathCost)
            // A grunt in the room sees the knight through the open door
            game.useDoor(door)
            let k = along(door, -2.5), g = along(door, 3)
            standAt(k.x, k.y)
            game.spawnEnemy(g.x - 0.4, g.y + 0.4, 1, "grunt")
            grunt = game.enemies[game.enemies.length - 1]
        }],
        [() => grunt.aiState === "chase", () => {
            check(true, "the grunt spots the knight through the open door and chases it")
            check(game.useDoor(door) && door.shut, "the knight shuts the door in its face")
            sampler.start()
        }],
        [() => bash.ended >= 0 || (bash.started >= 0 && game._physicsSteps - bash.started > 600), () => {
            let t = Balance.dungeon.doorBash, took = bash.seconds
            check(bash.started >= 0, "the grunt stops at the closed door and winds up")
            check(bash.samples > 0 && bash.ring === bash.samples,
                  "with the wind-up ring (" + bash.ring + " of " + bash.samples + " samples)")
            check(bash.ended >= 0 && Math.abs(took - t) <= 0.05,
                  "and bursts it open " + took.toFixed(2) + " s later, doorBash " + t + " s")
            check(door.doorState === "bashed" && !door.active, "the door is bashed and blocks no one")
        }],
        [400, () => grab("bashed.png")],
        [100, () => {
            let q = along(door, -1.2)
            standAt(q.x, q.y)
            grunt.halt()
            press(Qt.Key_E)
        }],
        [300, () => {
            check(door.doorState === "bashed" && !door.active, "E beside a bashed door does nothing: it stays open")
            check(!game.useDoor(door) && door.doorState === "bashed", "nor can it be closed any other way")
            let a = along(door, 3), b = along(door, -3)
            check(game.hasLineOfSight(a.x, a.y, b.x, b.y), "the knight is seen through it")
            check(grunt.aiState !== "bash", "the grunt winds up at it no more (" + grunt.aiState + ")")
            // A grunt chases the knight into a room through an open door
            behind = pickDoor(door)
            check(behind !== null, "another door with floor on both sides: " + (behind ? behind.cell : "none"))
            game.useDoor(behind)
            let k = along(behind, 4), g = along(behind, -2)
            standAt(k.x, k.y)
            game.spawnEnemy(g.x - 0.4, g.y + 0.4, 1, "grunt")
            grunt = game.enemies[game.enemies.length - 1]
        }],
        // Through the doorway, past the leaf, the door shut behind it
        [() => grunt.aiState === "chase" && pastOf(behind, grunt) > 0.7, () => {
            check(game.useDoor(behind) && behind.shut, "the knight shuts the door behind the grunt, "
                  + pastOf(behind, grunt).toFixed(2) + " wu past it")
            followAfter.start()
        }],
        [2000, () => {
            followAfter.enabled = false
            check(after.states.indexOf("bash") < 0 && behind.doorState === "closed",
                  "the grunt does not bash the door behind it: the door stays closed, the grunt "
                  + after.states.join(" -> "))
            grunt.halt()
        }],
    ].concat(seedSteps()).concat([
        [100, () => {
            for (let b = 0; b < 3; b++) {
                let s = laid[b], share = s.doors / Math.max(1, s.doorways)
                check(s.doorways >= 30 && Math.abs(share - Balance.dungeon.doorShare[b]) < 0.12,
                      "band " + b + ": " + s.doors + " doors on " + s.doorways + " doorways, "
                      + (100 * share).toFixed(0) + "%, the table's " + (100 * Balance.dungeon.doorShare[b]).toFixed(0) + "%")
            }
            check(laid.wrong.length === 0, seeds + " seeds: every door on a doorway, none in a shaft"
                  + (laid.wrong.length ? ": " + laid.wrong.slice(0, 3).join("; ") : ""))
            check(laid.differ.length === 0, "the same seed and danger lay the same doors twice"
                  + (laid.differ.length ? ": " + laid.differ.slice(0, 3).join("; ") : ""))
            console.log("[Doors] done,", failures, "failed")
        }],
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ])

    // The grunt's wind-up at the door, each physics step
    Connections {
        id: sampler
        target: bench.game ? bench.game.physics : null
        enabled: false
        function start() { enabled = true }
        function onStepped() {
            let g = bench.grunt, b = bench.bash
            if (!g) return
            if (b.started >= 0 && b.ended < 0) b.seconds += bench.game.physics.timeStep
            if (g.aiState === "bash") {
                if (b.started < 0) b.started = bench.game._physicsSteps
                b.samples++
                if (g.ringShows && g.ringProgress >= 0) b.ring++
            }
            if (b.started >= 0 && b.ended < 0 && bench.door.doorState === "bashed")
                b.ended = bench.game._physicsSteps
            // Half way through the wind-up, its ring closing
            if (g.aiState === "bash" && !b.shot && g.ringProgress >= 0.5) {
                b.shot = true
                bench.grab("bashing.png")
            }
        }
    }

    // The grunt's states once the door is shut behind it, each step
    Connections {
        id: followAfter
        target: bench.game ? bench.game.physics : null
        enabled: false
        function start() { enabled = true }
        function onStepped() {
            let st = bench.after.states, s = bench.grunt ? bench.grunt.aiState : ""
            if (st[st.length - 1] !== s) st.push(s)
        }
    }

    // The doors of 50 seeds across the bands, each dungeon laid out twice
    property var laid: ({ wrong: [], differ: [], 0: { doors: 0, doorways: 0 },
                          1: { doors: 0, doorways: 0 }, 2: { doors: 0, doorways: 0 } })
    function seedSteps() {
        let out = []
        for (let i = 0; i < seeds; i++) {
            out.push([60, () => {
                let seed = 9000 + i * 7919, danger = (i % 10) * 0.33
                game.applyScenario("dungeon", danger, seed)
                let band = game.dangerBand(game.dangerPosition)
                let start = game.rooms[0], end = game.rooms[game.rooms.length - 1]
                let s = laid[band]
                for (let gy = 0; gy < game.gridHeight; gy++)
                    for (let gx = 0; gx < game.gridWidth; gx++)
                        if (game.doorway(gx, gy)) s.doorways++
                s.doors += game.doors.length
                for (let d of game.doors) {
                    let c = d.cell.split(",").map(Number)
                    let shaft = (c[0] === game.entranceGridX && c[1] < start.y)
                        || (c[0] === game.exitGridX && c[1] >= end.y + end.h)
                    if (!game.doorway(c[0], c[1]) || shaft)
                        laid.wrong.push("seed " + seed + " " + d.cell + (shaft ? " in a shaft" : " not a doorway"))
                }
                let first = game.doors.map(d => d.cell).join(" ")
                game.applyScenario("dungeon", danger, seed)
                let again = game.doors.map(d => d.cell).join(" ")
                if (first !== again) laid.differ.push("seed " + seed + ": " + first + " / " + again)
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
                    console.log("[Doors] FAIL step", i, "timed out")
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
                console.log("[Doors] FAIL step", i - 1, "threw:", err)
                Qt.exit(failures + 1)
                stop()
            }
        }
    }
}
