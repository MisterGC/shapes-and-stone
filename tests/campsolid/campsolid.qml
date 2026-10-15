// Solid camp bench - what stands up from the camp's floor is solid, the
// dog follows its traveller smoothly, and a villager talked to stops and
// faces the knight (issue #178).
//
// In every look (grotto at depth 0, hall at 4, ember camp at 7) on 10
// seeds each prop of a solid kind (Balance.camp.solid) and the campfire
// have their solid body, the flat props none. A knight's middle is walked
// over the camp's floor on a lattice from the entrance, once without the
// solid bodies and once with them: every point reached before is reached
// after unless the knight would stand in a solid one, and the stairs, the
// fire's warmth, the innkeeper, the smith and the witch at every spot of
// their routines stay reachable. Then in the grotto a knight walks into
// the campfire, the pond and the ferns and stops at their edge. The dog's
// traveller walks to its other spot and back: the dog sets out once and
// rests once each way, its velocity never changes sign, it turns only as
// it sets out and as it rests (to face its traveller), and once the
// traveller stands its distance to its place shrinks every step until it
// rests within numbers.rest; a knight walking through the resting
// traveller and its dog pushes neither. Last the smith, talked to while
// it walks and while it hammers, stops, faces the knight and does nothing
// until the talk ends, then goes on where it left off.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/campsolid/campsolid.qml

import QtQuick
import QtQuick.Window
import QtTest
import "../../src"

Window {
    id: bench
    width: 1100
    height: 950
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0
    readonly property string storeName: "ShapesAndStoneCampSolidBench"
    readonly property var seeds: [424242, 1000, 8919, 16838, 1, 2, 3, 4, 5, 6]
    readonly property var depths: ({ grotto: 0, hall: 4, ember: 7 })
    readonly property var solid: Balance.camp.solid
    // The lattice the knight's middle walks on, and its collider's radius
    readonly property real lattice: 0.25
    readonly property real knightRadius: 0.45

    function check(ok, what) {
        console.log("[CampSolid]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    property var gameComponent: null
    Component.onCompleted: {
        gameComponent = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComponent.status !== Component.Ready) {
            console.log("[CampSolid] FAIL", gameComponent.errorString())
            Qt.exit(1)
            return
        }
        game = gameComponent.createObject(bench.contentItem, {width: bench.width, height: bench.height,
                                                              muted: true, recordStoreName: storeName})
        script.start()
    }

    function inCamp(g) { return g && g.player && g.levelType === "village" && !g.resetting }
    function r2(v) { return Math.round(v * 100) / 100 }
    function person(name) {
        let kids = game.room.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i].objectName === "npc" && kids[i].npcName === name) return kids[i]
        return null
    }
    function solids() { return game.dungeonObjects.filter(o => o && o.objectName === "campSolid") }
    function knightAt() { return Qt.point(game.player.xWu + 0.5, game.player.yWu - 0.5) }
    function fireAt() {
        let f = game.campfire
        return Qt.point(f.xWu + f.widthWu / 2, f.yWu - f.heightWu / 2)
    }

    // Whether a knight's middle at (x, y) fits: its circle off the walls
    // and the buildings and, with bodies, out of every one of them
    function fits(x, y, bodies) {
        let r = knightRadius
        for (let gy = Math.floor((y - r) / game.cellSize); gy <= Math.floor((y + r) / game.cellSize); gy++)
            for (let gx = Math.floor((x - r) / game.cellSize); gx <= Math.floor((x + r) / game.cellSize); gx++) {
                let open = game.grid[gy] && (game.grid[gy][gx] === game.cellRoom || game.grid[gy][gx] === game.cellHallway)
                           && !game._buildingCells[gy * game.gridWidth + gx]
                if (open) continue
                // The circle against the cell's square
                let nx = Math.max(gx * game.cellSize, Math.min(x, (gx + 1) * game.cellSize))
                let ny = Math.max(gy * game.cellSize, Math.min(y, (gy + 1) * game.cellSize))
                if (Math.hypot(nx - x, ny - y) < r) return false
            }
        for (let b of bodies) {
            if (b.holds(x, y)) return false
            for (let i = 0; i < 12; i++) {
                let a = i * Math.PI / 6
                if (b.holds(x + r * Math.cos(a), y + r * Math.sin(a))) return false
            }
        }
        return true
    }
    // The lattice points a knight's middle reaches from (x0, y0) without
    // crossing what does not fit, as {key: point}
    function reach(x0, y0, bodies) {
        let k = (i, j) => i + "," + j
        let i0 = Math.round(x0 / lattice), j0 = Math.round(y0 / lattice)
        let seen = {}, open = [[i0, j0]]
        seen[k(i0, j0)] = Qt.point(i0 * lattice, j0 * lattice)
        let maxX = game.gridWidth * game.cellSize, maxY = game.gridHeight * game.cellSize
        while (open.length > 0) {
            let at = open.pop()
            for (let d of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
                let i = at[0] + d[0], j = at[1] + d[1]
                if (seen[k(i, j)] !== undefined) continue
                let x = i * lattice, y = j * lattice
                if (x < 0 || y < 0 || x > maxX || y > maxY || !fits(x, y, bodies)) continue
                seen[k(i, j)] = Qt.point(x, y)
                open.push([i, j])
            }
        }
        return seen
    }

    // One seed's camp: its solid bodies and what a knight reaches
    function survey(seed, look) {
        let bodies = solids()
        let props = game.campProps
        let kinds = Object.keys(solid.kinds)
        let propBodies = bodies.filter(b => b.kind !== "fire")
        let fireBodies = bodies.filter(b => b.kind === "fire")
        let f = fireAt()
        let matched = props.filter(p => kinds.indexOf(p.kind) >= 0).every(p => propBodies.some(b =>
            b.kind === p.kind && Math.abs(b.xWu + b.widthWu / 2 - p.x) < 1e-6
            && Math.abs(b.yWu - b.heightWu / 2 - p.y) < 1e-6 && b.widthWu === p.w && b.heightWu === p.h))
        let solidCount = props.filter(p => kinds.indexOf(p.kind) >= 0).length
        check(matched && propBodies.length === solidCount && fireBodies.length === 1
              && fireBodies[0].holds(f.x, f.y) && fireBodies[0].widthWu === 2 * solid.fire,
              look + " seed " + seed + ": " + solidCount + " of " + props.length + " props are solid ("
              + props.map(p => p.kind + (kinds.indexOf(p.kind) >= 0 ? "*" : "")).join(" ")
              + "), and the campfire within " + solid.fire + " wu")
        // The knight's middle as it enters
        let start = Qt.point(game.entranceGridX * game.cellSize + game.cellSize / 2, knightAt().y)
        let before = reach(start.x, start.y, [])
        let after = reach(start.x, start.y, bodies)
        let lost = []
        for (let key in before)
            if (after[key] === undefined && fits(before[key].x, before[key].y, bodies)) lost.push(before[key])
        check(lost.length === 0, look + " seed " + seed + ": of " + Object.keys(before).length
              + " points a knight reached, " + Object.keys(after).length + " are reached with the solids, "
              + "none lost but those inside them" + (lost.length > 0 ? " - lost " + lost.length + ", first at "
              + r2(lost[0].x) + "," + r2(lost[0].y) : ""))
        // What must stay reachable: the stairs, the fire's warmth and the
        // people at every spot of their routines, a knight within 1.5 wu
        let near = (set, x, y, d) => {
            for (let key in set)
                if (Math.hypot(set[key].x - x, set[key].y - y) <= d) return true
            return false
        }
        let goals = [{ what: "stairs", x: game.exitGridX * game.cellSize + game.cellSize / 2, y: 2, d: 1.5 },
                     { what: "warmth", x: f.x, y: f.y, d: Balance.campfire.healRadius - 0.5 }]
        for (let name of ["Innkeeper", "Blacksmith", "Witch"]) {
            let npc = person(name)
            for (let r of npc.routine) goals.push({ what: name, x: r.x + 0.4, y: r.y - 0.4, d: 1.5 })
        }
        // The stairs lie in the north tunnel: its top cell's middle
        let top = 0
        while (top < game.gridHeight && game.grid[top][game.exitGridX] !== game.cellHallway) top++
        goals[0].y = top * game.cellSize + game.cellSize / 2
        let missed = goals.filter(gl => near(before, gl.x, gl.y, gl.d) && !near(after, gl.x, gl.y, gl.d))
        let never = goals.filter(gl => !near(before, gl.x, gl.y, gl.d))
        check(missed.length === 0 && never.length === 0, look + " seed " + seed
              + ": the stairs, the fire's warmth, the innkeeper, the smith and the witch at "
              + (goals.length - 2) + " spots stay reachable"
              + (missed.length > 0 ? " - lost: " + missed.map(gl => gl.what).join(", ") : "")
              + (never.length > 0 ? " - never reached: " + never.map(gl => gl.what).join(", ") : ""))
        return { seed: seed, look: look, props: props.map(p => p.kind) }
    }

    // The knight's middle to (x, y) wu, standing, the camera on it
    function placeKnight(x, y) {
        game.player.xWu = x - 0.5
        game.player.yWu = y + 0.5
        game.player.linearVelocity = Qt.point(0, 0)
        game.camera.target = null
        game.camera.target = game.player
    }

    // --- Walking into the solids ---
    // From dist wu east (or west) of body b's edge on its middle row, the
    // knight walks toward its middle for 1.5 s
    property var into: null
    property var path: []
    function walkInto(b) {
        let cx = b.xWu + b.widthWu / 2, cy = b.yWu - b.heightWu / 2
        let half = b.widthWu / 2 * (b.shape === "box" ? b.fill : Math.cos(Math.PI / 8) * b.fill)
        let side = [1, -1].find(s => fits(cx + s * (half + 1.5), cy, solids())
                                     && fits(cx + s * (half + 0.6), cy, solids())) || 1
        placeKnight(cx + side * (half + 1.5), cy)
        into = { body: b, side: side, cx: cx, cy: cy, half: half }
        path = []
        game.player.moveY = 0
        game.player.moveX = -side
    }
    function judgeInto() {
        game.player.moveX = 0
        let b = into.body, k = knightAt()
        let inside = path.some(p => b.holds(p.x, p.y))
        let gap = into.side * (k.x - into.cx) - into.half
        check(!inside && gap < knightRadius + 0.15 && gap > 0, "the knight walking into the " + b.kind
              + " stops at its edge: its middle " + r2(gap) + " wu off it, never on it, from "
              + r2(path[0] ? path[0].x : 0) + " to " + r2(k.x))
    }

    // --- The dog ---
    property var trace: []
    property var leader: null
    property int goal: 0
    property real t0: 0
    function sendLeader(i) {
        leader._routineIndex = i
        leader._atDestination = false
        leader._activityText = ""
        goal = i
        trace = []
        t0 = Date.now()
    }
    function sample() {
        let d = game.campDog, s = d.spot()
        trace.push({ vx: d.velocityX, vy: d.velocityY, moving: d.moving, facing: d.facing,
                     off: Math.hypot(s.x - d.xWu, s.y - d.yWu), walking: leader.doing === null })
    }
    function judgeDog(way) {
        let sets = 0, rests = 0, turns = 0, flips = 0
        let lastX = 0, lastY = 0
        for (let i = 1; i < trace.length; i++) {
            let a = trace[i - 1], b = trace[i]
            if (b.moving && !a.moving) sets++
            if (!b.moving && a.moving) rests++
            if (b.facing !== a.facing) turns++
            if (b.vx !== 0) { if (lastX * b.vx < 0) flips++; lastX = b.vx }
            if (b.vy !== 0) { if (lastY * b.vy < 0) flips++; lastY = b.vy }
        }
        // From when the traveller stands: the distance shrinks to rest
        let stood = trace.findIndex(p => !p.walking)
        let after = stood < 0 ? [] : trace.slice(stood)
        let shrinks = true
        for (let i = 1; i < after.length; i++)
            if (after[i - 1].moving && after[i].off > after[i - 1].off + 1e-6) shrinks = false
        let restAt = after.findIndex(p => !p.moving)
        let last = trace[trace.length - 1]
        check(sets === 1 && rests === 1 && flips === 0 && turns <= sets + rests, "the dog follows its "
              + leader.npcName + " " + way + " in " + trace.length + " samples: sets out " + sets
              + "x, rests " + rests + "x, velocity sign changes " + flips + ", turns " + turns)
        check(stood >= 0 && shrinks && restAt >= 0 && last.off <= Balance.camp.travellers.dog.rest + 1e-6,
              "once the " + leader.npcName + " stands its dog's distance to its place shrinks every sample"
              + " and settles in " + restAt + " samples at " + r2(last ? last.off : -1) + " wu")
    }

    // --- The talk ---
    property var smith: null
    property var held: null
    function panel() {
        for (let i = 0; i < game.data.length; i++)
            if (game.data[i] && typeof game.data[i].advance === "function"
                && game.data[i].wares !== undefined) return game.data[i]
        return null
    }
    function smithAt() { return Qt.point(smith.xWu + smith.widthWu / 2, smith.yWu - smith.heightWu / 2) }
    // The knight 1.2 wu west or east of the smith, as side says, then E
    function talkToSmith(side) {
        let s = smithAt()
        placeKnight(s.x + side * 1.2, s.y)
    }
    function snapshot() {
        let s = smithAt()
        return { x: s.x, y: s.y, timer: smith._activityTimer, index: smith._routineIndex,
                 at: smith._atDestination, doing: smith.doing }
    }
    function closeTalk() {
        let p = panel()
        for (let i = 0; i < 8 && p && p.visible; i++) press(Qt.Key_E)
    }

    property var steps: []
    function buildSteps() {
        let s = []
        for (let name of Object.keys(depths))
            for (let seed of seeds) {
                s.push([() => true, () => game.applyScenario("village", depths[name], seed)])
                s.push([() => inCamp(game), () => survey(seed, name)])
            }

        // Into the campfire, the pond and the ferns of a grotto with both
        s.push([() => true, () => {
            game.applyScenario("village", 0, seeds[0])
        }])
        s.push([() => inCamp(game), () => {}])
        for (let kind of ["fire", "pond", "ferns"]) {
            s.push([200, () => {
                let b = solids().find(o => o.kind === kind)
                if (!b) {
                    check(false, "the grotto of seed " + seeds[0] + " has a solid " + kind)
                    into = null
                    return
                }
                walkInto(b)
            }])
            for (let i = 0; i < 75; i++)
                s.push([20, () => { if (into) path.push(knightAt()) }])
            s.push([() => true, () => { if (into) judgeInto() }])
        }

        // The dog, its traveller to the farther of its spots and back
        s.push([() => true, () => {
            leader = game.campDog.leader
            let f = fireAt()
            placeKnight(game.entranceGridX * game.cellSize + 1, f.y - 12)
            let c = Qt.point(leader.xWu + 0.4, leader.yWu - 0.4)
            let far = leader.routine.map(r => Math.hypot(r.x + 0.4 - c.x, r.y - 0.4 - c.y))
            sendLeader(far[1] > far[0] ? 1 : 0)
        }])
        for (let way of ["there", "back"]) {
            s.push([() => { sample(); return leader.doing !== null && !game.campDog.moving || Date.now() - t0 > 25000 },
                    () => judgeDog(way)])
            if (way === "there") s.push([() => true, () => sendLeader(1 - goal)])
        }
        // The knight walks through the resting traveller and its dog:
        // neither has a body that takes a push, so neither moves
        let still = null, crossing = []
        s.push([() => true, () => {
            let c = Qt.point(leader.xWu + 0.4, leader.yWu - 0.4), d = game.campDog
            still = { lx: leader.xWu, ly: leader.yWu, dx: d.xWu, dy: d.yWu }
            let y = (c.y + d.yWu) / 2
            placeKnight(Math.min(c.x, d.xWu) - 2, y)
            game.player.moveY = 0
            game.player.moveX = 1
            crossing = []
        }])
        for (let i = 0; i < 90; i++)
            s.push([20, () => crossing.push({ k: knightAt().x, moving: game.campDog.moving,
                                              vx: game.campDog.velocityX, vy: game.campDog.velocityY })])
        s.push([() => true, () => {
            game.player.moveX = 0
            let d = game.campDog
            let off = Math.hypot(leader.xWu - still.lx, leader.yWu - still.ly)
                      + Math.hypot(d.xWu - still.dx, d.yWu - still.dy)
            let crossed = crossing[crossing.length - 1].k > Math.max(still.lx + 0.8, still.dx) + 0.5
            check(crossed && off < 1e-6 && crossing.every(c => !c.moving && c.vx === 0 && c.vy === 0),
                  "the knight walks through the resting " + leader.npcName + " and its dog from "
                  + r2(crossing[0].k) + " to " + r2(crossing[crossing.length - 1].k)
                  + ": neither is pushed (" + off.toExponential(1) + " wu) and the dog never sets out")
        }])

        // The smith, talked to on its way and at its anvil
        s.push([() => true, () => {
            smith = person("Blacksmith")
            // On its way: to the spot after the anvil
            smith._routineIndex = 1
            smith._atDestination = false
            smith._activityText = ""
        }])
        for (let phase of ["on its way", "hammering"]) {
            s.push([() => phase === "hammering" ? smith.doing !== null && smith.doing.sound === "anvil"
                                                 : smith.linearVelocity.x !== 0 || smith.linearVelocity.y !== 0,
                    () => talkToSmith(phase === "hammering" ? -1 : 1)])
            s.push([() => smith.nearbyPlayer !== null, () => {
                game.forceActiveFocus()
                press(Qt.Key_E)
                held = snapshot()
            }])
            s.push([300, () => {
                let k = knightAt(), sm = smithAt()
                let p = panel()
                check(p && p.visible && p.speakerName === "Blacksmith" && smith.listening
                      && smith.listener === game.player,
                      "talked to " + phase + ", the smith listens to the knight")
                check(smith.facing === (k.x > sm.x ? 1 : -1), "it faces the knight " + (k.x > sm.x ? "east" : "west")
                      + " (facing " + smith.facing + ")")
                held = snapshot()
            }])
            s.push([2000, () => {
                let now = snapshot()
                let moved = Math.hypot(now.x - held.x, now.y - held.y)
                check(moved < 0.01 && now.timer === held.timer && now.index === held.index && now.doing === null
                      && smith.linearVelocity.x === 0 && smith.linearVelocity.y === 0,
                      "for 2 s of the talk it stands (" + r2(moved) + " wu) and does nothing: its step "
                      + now.index + ", " + r2(now.timer) + " s of it left")
                closeTalk()
            }])
            s.push([400, () => {
                let p = panel()
                check(p && !p.visible && !smith.listening, "the talk ends and the smith stops listening")
                held = snapshot()
            }])
            s.push([1200, () => {
                let now = snapshot()
                let moved = Math.hypot(now.x - held.x, now.y - held.y)
                let goesOn = phase === "hammering"
                    ? (now.timer < held.timer - 0.5 && now.doing !== null || now.index !== held.index)
                    : (moved > 0.5 || now.at)
                check(goesOn, "after the talk it goes on " + (phase === "hammering"
                      ? "hammering: " + r2(held.timer) + " s left, then " + r2(now.timer)
                      : "on its way: " + r2(moved) + " wu"))
            }])
        }

        s.push([300, () => game.destroy()])
        s.push([300, () => {
            console.log("[CampSolid] done,", failures, "failed")
            Qt.exit(failures)
        }])
        return s
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
                if (waitedMs > 70000) {
                    console.log("[CampSolid] FAIL step", i, "timed out")
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
