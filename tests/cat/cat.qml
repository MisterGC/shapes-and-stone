// Cat bench - a cave cat sleeps by the camp's fire and looks up when a
// knight comes near (issue #150).
//
// In every look (grotto at depth 0, hall at 4, ember camp at 7) on 20
// seeds most camps have a cat and not all: one at most, on its ring round
// the campfire, out of the warmth where the knights sit, whole on the
// floor and clear of the way to the stairs, the people's spots and the
// props, and nothing the benches look for (no body, no npc, no campfire,
// no prop, no moths). Another screen places the same cat, or none, from
// the same seed. Then on a camp with a cat: the knight far off, it
// sleeps; the knight near, it looks up at it within a tick and its rise,
// its eyes on the knight, and follows the knight to its other side; the
// knight gone, it keeps looking until settle has passed, then sleeps; a
// knight that sits down by the fire beside it lets it sleep. A cat on its
// own, given two knights, looks up at whichever comes near and watches
// the nearer; asleep it stretches, and a knight coming ends the stretch at
// once. Prints one PASS or FAIL line per check and exits with the
// number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/cat/cat.qml

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
    readonly property string storeName: "ShapesAndStoneCatBench"
    readonly property var seeds: [424242, 1000, 8919, 16838, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    readonly property var depths: ({ grotto: 0, hall: 4, ember: 7 })
    readonly property var n: Balance.camp.cat

    function check(ok, what) {
        console.log("[Cat]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    property var gameComponent: null
    Component.onCompleted: {
        gameComponent = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComponent.status !== Component.Ready) {
            console.log("[Cat] FAIL", gameComponent.errorString())
            Qt.exit(1)
            return
        }
        game = gameComponent.createObject(bench.contentItem, {width: bench.width, height: bench.height,
                                                              muted: true, recordStoreName: storeName})
        script.start()
    }

    function inCamp(g) { return g && g.player && g.levelType === "village" && !g.resetting }
    function cats(g) { return g.dungeonObjects.filter(o => o && o.creature === "cat") }
    function r3(v) { return Math.round(v * 1000) / 1000 }

    // What one seed's camp's cat is, as the checks read it
    function survey(g, seed) {
        let c = Balance.camp, cs = cats(g), cat = cs[0], fire = g.campfire
        let out = { seed: seed, look: g.campLook.name, cats: cs.length, key: "none" }
        if (!cat) return out
        let half = cat.sizeWu / 2
        let fx = fire.xWu + fire.widthWu / 2, fy = fire.yWu - fire.heightWu / 2
        let ring = Math.hypot(cat.xWu - fx, cat.yWu - fy)
        // The warmth: a knight's centre within healRadius of the fire's
        // corner plus a knight's half (0.5, 0.5); how far the cat lies
        // past it, less a knight's half width
        let wx = fire.xWu + 0.5, wy = fire.yWu - 0.5
        let warmth = Math.hypot(cat.xWu - wx, cat.yWu - wy) - half - 0.5
        let cx = g.entranceGridX * g.cellSize
        let spots = [Qt.point(cx - 6, fire.yWu - 2)]
        for (let o of g.dungeonObjects)
            if (o && o.objectName === "npc") {
                spots.push(Qt.point(o.xWu, o.yWu))
                for (let r of o.routine) spots.push(Qt.point(r.x, r.y))
            }
        let floor = true
        for (let gy = Math.floor((cat.yWu - half) / g.cellSize); gy <= Math.floor((cat.yWu + half) / g.cellSize); gy++)
            for (let gx = Math.floor((cat.xWu - half) / g.cellSize); gx <= Math.floor((cat.xWu + half) / g.cellSize); gx++)
                if (g.grid[gy][gx] !== g.cellRoom || g._buildingCells[gy * g.gridWidth + gx]) floor = false
        return Object.assign(out, {
            ring: ring >= n.ring[0] - 1e-6 && ring <= n.ring[1] + 1e-6,
            ringWu: r3(ring),
            warm: warmth,
            floor: floor,
            path: cat.xWu + half <= cx - c.clearOfPath || cat.xWu - half >= cx + c.clearOfPath,
            people: spots.every(s => Math.hypot(s.x - cat.xWu, s.y - cat.yWu) >= c.clearOfPeople),
            props: g.campProps.every(p => Math.hypot(Math.max(0, Math.abs(p.x - cat.xWu) - p.w / 2),
                                                     Math.max(0, Math.abs(p.y - cat.yWu) - p.h / 2))
                                          >= half + n.clearOfProps),
            nobody: cat.categories === undefined && cat.objectName !== "npc" && cat.healRadius === undefined
                    && cat.propKind === undefined && cat.mothLights === undefined && cat.routine === undefined
                    && cat.dialogueLines === undefined && g.campCat === cat,
            asleep: cat.mood === "idle",
            key: r3(cat.xWu) + "," + r3(cat.yWu) + " " + r3(cat.seed)
        })
    }

    // The knight's centre to (x, y) wu, the camera on it
    function placeKnight(g, x, y) {
        g.player.xWu = x - 0.5
        g.player.yWu = y + 0.5
        g.camera.target = null
        g.camera.target = g.player
    }
    function knightAt(g) { return Qt.point(g.player.xWu + 0.5, g.player.yWu - 0.5) }
    // The cat looks at (x, y): its look within a few degrees of the way
    function looksAt(cat, p) {
        let d = Math.hypot(p.x - cat.xWu, p.y - cat.yWu)
        return (cat.lookX * (p.x - cat.xWu) + cat.lookY * (p.y - cat.yWu)) / d > 0.99
    }

    // --- The steps ---
    property var results: []
    property var steps: []
    property var cat: null
    property var fireAt: null
    property var near: null
    property real t0: 0
    property var catSeed: 0
    function buildSteps() {
        let s = []
        let names = Balance.camp.looks.map(l => l.name)
        for (let name of names)
            for (let seed of seeds) {
                s.push([() => true, () => game.applyScenario("village", depths[name], seed)])
                s.push([() => inCamp(game), () => results.push(survey(game, seed))])
            }
        s.push([() => true, () => judge()])
        // Another screen places the same cat, or none
        s.push([() => true, () => {
            other = gameComponent.createObject(bench.contentItem, {x: bench.width, width: 400, height: 300,
                                                                   muted: true, recordStoreName: storeName})
        }])
        for (let name of names)
            for (let seed of seeds.slice(0, 6)) {
                s.push([() => true, () => other.applyScenario("village", depths[name], seed)])
                s.push([() => inCamp(other), () => {
                    let mine = results.find(r => r.seed === seed && r.look === name)
                    let theirs = survey(other, seed)
                    check(mine && theirs.key === mine.key, name + ", seed " + seed
                          + ": another screen places the same cat (" + theirs.key + ")")
                }])
            }
        s.push([300, () => { other.destroy(); other = null }])

        // The cat by a knight: far off it sleeps
        s.push([() => true, () => {
            catSeed = (results.find(r => r.look === "grotto" && r.cats === 1) || {}).seed
            game.applyScenario("village", 0, catSeed)
        }])
        s.push([() => inCamp(game), () => {
            cat = game.campCat
            let f = game.campfire
            fireAt = Qt.point(f.xWu + f.widthWu / 2, f.yWu - f.heightWu / 2)
            // Near: between the cat and the fire, 2.5 wu from the fire's
            // centre, in its warmth
            let d = Math.hypot(cat.xWu - fireAt.x, cat.yWu - fireAt.y)
            near = Qt.point(fireAt.x + 2.5 * (cat.xWu - fireAt.x) / d, fireAt.y + 2.5 * (cat.yWu - fireAt.y) / d)
        }])
        s.push([1000, () => {
            let k = knightAt(game), d = Math.hypot(k.x - cat.xWu, k.y - cat.yWu)
            check(cat.mood === "idle" && cat.lift === 0 && d > n.forget,
                  "grotto, seed " + catSeed + ": the knight " + r3(d) + " wu off at the entrance, the cat sleeps ("
                  + cat.mood + ", lift " + r3(cat.lift) + ")")
            placeKnight(game, near.x, near.y)
            t0 = Date.now()
        }])
        // Near, it looks up at the knight
        s.push([() => cat.mood === "alert" || Date.now() - t0 > 1000, () => {
            let k = knightAt(game), d = Math.hypot(k.x - cat.xWu, k.y - cat.yWu)
            check(cat.mood === "alert" && cat.watching === game.player,
                  "the knight comes " + r3(d) + " wu near: the cat looks up within "
                  + (Date.now() - t0) + " ms (" + cat.mood + ")")
            t0 = Date.now()
        }])
        s.push([(n.rise + 0.2) * 1000, () => {
            check(cat.lift === 1 && looksAt(cat, knightAt(game)),
                  "its head is up after " + n.rise + " s (lift " + r3(cat.lift) + ") and its eyes on the knight (look "
                  + r3(cat.lookX) + ", " + r3(cat.lookY) + ")")
            // To its other side, still near: the look follows
            let away = Qt.point(2 * cat.xWu - near.x, 2 * cat.yWu - near.y)
            let back = Qt.point(cat.xWu + (near.x - cat.xWu) * 0.5 - (near.y - cat.yWu),
                                cat.yWu + (near.y - cat.yWu) * 0.5 + (near.x - cat.xWu))
            let floorAt = p => game.grid[Math.floor(p.y / game.cellSize)][Math.floor(p.x / game.cellSize)] === game.cellRoom
            let to = floorAt(away) ? away : back
            placeKnight(game, to.x, to.y)
        }])
        s.push([500, () => {
            let k = knightAt(game)
            check(cat.mood === "alert" && looksAt(cat, k) && Math.hypot(k.x - cat.xWu, k.y - cat.yWu) < n.forget,
                  "the knight moves round it: its eyes follow (look " + r3(cat.lookX) + ", " + r3(cat.lookY) + ")")
            // Away: back to the entrance
            placeKnight(game, game.entranceGridX * game.cellSize + 1, cat.yWu - 12)
            t0 = Date.now()
        }])
        s.push([(n.settle - 0.6) * 1000, () => {
            check(cat.mood === "alert", "the knight gone, it keeps looking up " + (n.settle - 0.6) + " s ("
                  + cat.mood + ")")
        }])
        s.push([() => cat.mood === "idle" || Date.now() - t0 > (n.settle + 1) * 1000, () => {
            let ms = Date.now() - t0
            check(cat.mood === "idle" && ms >= (n.settle - n.tick) * 1000 && ms <= (n.settle + 0.5) * 1000,
                  "and settles back to sleep " + ms + " ms after it left (settle " + n.settle + " s)")
            t0 = Date.now()
        }])
        s.push([(n.fall + 0.3) * 1000, () => {
            check(cat.lift === 0, "its head is down again after " + n.fall + " s (lift " + r3(cat.lift) + ")")
            // A knight that sits by the fire beside it
            placeKnight(game, near.x, near.y)
            t0 = Date.now()
        }])
        s.push([1000, () => {
            check(cat.mood === "alert" && !game.player.seated && game.campfire.warms(game.player.xWu, game.player.yWu),
                  "a knight in the fire's warmth beside it wakes it (" + cat.mood + ")")
        }])
        s.push([() => game.player.seated && cat.mood === "idle"
                      || Date.now() - t0 > (Balance.camp.sitAfter + n.settle + 2) * 1000, () => {
            check(game.player.seated && cat.mood === "idle",
                  "it sits down, and the cat sleeps again " + (Date.now() - t0) + " ms after it came ("
                  + cat.mood + ", seated " + game.player.seated + ")")
        }])

        // A cat on its own with two knights: it looks up at whichever comes
        // near and watches the nearer
        s.push([() => true, () => {
            loneCat = loneComponent.createObject(bench.contentItem, { gameWorld: fakeWorld, xWu: 10, yWu: 10, seed: 0.3 })
            knightA.x = 30; knightB.x = 30
        }])
        s.push([500, () => {
            check(loneCat.mood === "idle", "a cat with both knights off sleeps (" + loneCat.mood + ")")
            knightB.x = 12; knightB.y = 10
        }])
        s.push([500, () => {
            check(loneCat.mood === "alert" && loneCat.watching === knightB && loneCat.lookX > 0.99,
                  "the second knight comes near: it looks up at it")
            knightA.x = 9; knightA.y = 10
        }])
        s.push([500, () => {
            check(loneCat.watching === knightA && loneCat.lookX < -0.99,
                  "the first comes nearer: it watches the first (look " + r3(loneCat.lookX) + ")")
            knightA.x = 30; knightB.x = 30
        }])
        s.push([(n.settle + 0.5) * 1000, () => {
            check(loneCat.mood === "idle" && loneCat.watching === null, "both gone, it sleeps (" + loneCat.mood + ")")
            loneCat.destroy()
            // Its stretch, made to come every 0.3 s
            loneCat = loneComponent.createObject(bench.contentItem, {
                gameWorld: fakeWorld, xWu: 10, yWu: 10, seed: 0.3,
                numbers: Object.assign({}, n, { act: { every: [0.3, 0.3], seconds: 1 } }) })
            t0 = Date.now()
        }])
        s.push([() => loneCat.act > 0.99 || Date.now() - t0 > 2000, () => {
            check(loneCat.act > 0.99 && loneCat.mood === "idle",
                  "asleep it stretches: act " + r3(loneCat.act) + " " + (Date.now() - t0) + " ms in")
            knightA.x = 11; knightA.y = 10
        }])
        s.push([() => loneCat.mood === "alert" || Date.now() - t0 > 3000, () => {
            check(loneCat.mood === "alert" && loneCat.act === 0, "a knight near, it leaves the stretch at once "
                  + "(act " + r3(loneCat.act) + ")")
            knightA.x = 30
            loneCat.destroy()
        }])

        s.push([300, () => game.destroy()])
        s.push([300, () => {
            console.log("[Cat] done,", failures, "failed")
            Qt.exit(failures)
        }])
        return s
    }

    property var loneCat: null
    Component { id: loneComponent; CaveCat {} }
    QtObject { id: knightA; property real x: 30; property real y: 10 }
    QtObject { id: knightB; property real x: 30; property real y: 10 }
    QtObject {
        id: fakeWorld
        function knightsHere() {
            return [knightA, knightB].map(k => ({ knight: k, x: k.x, y: k.y, seated: false }))
        }
    }

    function judge() {
        let list = (rs, f) => rs.filter(f).map(r => r.look + " " + r.seed).join(", ")
        let withCat = results.filter(r => r.cats === 1)
        check(results.every(r => r.cats <= 1), "no camp has more than one cat " + list(results, r => r.cats > 1))
        check(withCat.length >= results.length * 0.6 && withCat.length < results.length,
              "most camps have a cat, not all: " + withCat.length + " of " + results.length
              + " (share " + n.share + ")")
        for (let look of Balance.camp.looks) {
            let rs = results.filter(r => r.look === look.name)
            check(rs.some(r => r.cats === 1), look.name + ": " + rs.filter(r => r.cats === 1).length + " of "
                  + rs.length + " camps have a cat")
        }
        check(withCat.every(r => r.ring), "it lies " + n.ring[0] + " to " + n.ring[1] + " wu from the fire's centre "
              + list(withCat, r => !r.ring))
        check(withCat.every(r => r.warm >= Balance.campfire.healRadius),
              "out of the warmth where the knights sit, a knight's width clear (closest "
              + r3(Math.min(...withCat.map(r => r.warm))) + " wu to the edge, want " + Balance.campfire.healRadius + ")")
        check(withCat.every(r => r.floor), "whole on the cave's floor " + list(withCat, r => !r.floor))
        check(withCat.every(r => r.path && r.people && r.props),
              "clear of the way to the stairs, the people's spots and the props "
              + list(withCat, r => !(r.path && r.people && r.props)))
        check(withCat.every(r => r.nobody), "drawn only: no body, no npc, no campfire, no prop, no moths, no "
              + "dialogue " + list(withCat, r => !r.nobody))
        check(withCat.every(r => r.asleep), "it starts asleep " + list(withCat, r => !r.asleep))
        let keys = {}
        for (let r of withCat.filter(r => r.look === "grotto")) keys[r.key] = true
        let grottos = withCat.filter(r => r.look === "grotto").length
        check(Object.keys(keys).length === grottos, "the grotto's " + grottos + " cats lie in "
              + Object.keys(keys).length + " different places")
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
                    console.log("[Cat] FAIL step", i, "timed out")
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
