// Camps bench - the camp's look follows the depth: a mossy grotto at depth
// 0 to 2, a miners' hall at 3 to 5, an ember camp from 6 on (issue #146).
//
// applyScenario("village", d) lands in the grotto at d = 0, the hall at
// 4 and the ember camp at 7, and every depth from 0 to 12 in the look
// Balance.camp.looks gives it. Each look shows as its own: the floor, the
// rock, the faces, the light and the screen grade differ from the other
// looks', and the camp takes them. On 12 seeds per look the props lie
// whole on the cave's floor, off the way to the stairs, the campfire and
// the people, at least minProps of them, the layout's landmark among
// them, from at least two of the look's layouts; nothing of them blocks or is anyone the benches look for. The
// campfire stays the brightest light and the innkeeper, the smith and the
// witch keep their places at every depth. Another game, another screen,
// builds the same camp - look, layout and props - from the same seed and
// depth. Prints one PASS or FAIL line per check and exits with the number
// of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/camps/camps.qml
//
// With a window, the copied shaders and an output directory it also saves
// each look at two seeds, zoomed out to show the camp whole, and close up
// at the campfire (camp-<look>-<seed>.png, fire-<look>-<seed>.png):
//
//   qml -I <build>/bin/qml tests/camps/camps.qml -- <out dir>

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
    readonly property string storeName: "ShapesAndStoneCampsBench"

    readonly property var args: Qt.application.arguments
    readonly property string outDir: args.length > 1 && !String(args[args.length - 1]).endsWith(".qml")
                                     ? args[args.length - 1] : ""
    readonly property var seeds: Array.from({ length: 12 }, (v, i) => 1000 + 7919 * i)
    readonly property var shotSeeds: [424242, 1000]
    // A depth of each look: as the issue names them
    readonly property var depths: ({ grotto: 0, hall: 4, ember: 7 })
    readonly property int minProps: 4

    function check(ok, what) {
        console.log("[Camps]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    property var gameComponent: null
    Component.onCompleted: {
        gameComponent = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComponent.status !== Component.Ready) {
            console.log("[Camps] FAIL", gameComponent.errorString())
            Qt.exit(1)
            return
        }
        game = gameComponent.createObject(bench.contentItem, {width: bench.width, height: bench.height,
                                                              muted: true, recordStoreName: storeName})
        script.start()
    }

    function inCamp(g) { return g && g.player && g.levelType === "village" && !g.resetting }
    function npc(g, name) {
        let kids = g.room.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i].objectName === "npc" && kids[i].npcName === name) return kids[i]
        return null
    }
    function campfire(g) { return g.dungeonObjects.find(o => o && o.healRadius !== undefined) }
    function find(root, test) {
        if (root && test(root)) return root
        let kids = (root && (root.data || root.children)) || []
        for (let i = 0; i < kids.length; i++) {
            let f = find(kids[i], test)
            if (f) return f
        }
        return null
    }
    function lightLayer(g) { return find(g, o => typeof o.setOccluderGrid === "function") }
    function screenFx(g) { return find(g, o => o.vignette !== undefined && o.lowHealth !== undefined) }
    function lights(o) {
        let found = []
        for (let k of (o.data || [])) if (k && k.castsShadows !== undefined) found.push(k)
        return found
    }
    function props(g) { return g.dungeonObjects.filter(o => o && o.propKind !== undefined) }
    function floorItem(g) { return g.dungeonObjects.find(o => o && o.grass !== undefined) }
    function faces(g) { return g.dungeonObjects.filter(o => o && o.faceStyle !== undefined && o.shadowWu !== undefined) }

    // What one seed's camp at one depth is, as the checks below read it
    property var results: []
    function survey(g, seed, d) {
        let look = g.campLook, c = Balance.camp
        let fire = campfire(g), ff = fire ? lights(fire) : []
        let cx = (Math.floor((g.gridWidth - c.width) / 2) + Math.floor(c.width / 2)) * g.cellSize
        let others = []
        for (let t of g.torches) others = others.concat(lights(t))
        let laid = props(g)
        let cellsFloor = p => {
            for (let gy = Math.floor((p.y - p.h / 2) / g.cellSize); gy <= Math.floor((p.y + p.h / 2 - 0.001) / g.cellSize); gy++)
                for (let gx = Math.floor((p.x - p.w / 2) / g.cellSize); gx <= Math.floor((p.x + p.w / 2 - 0.001) / g.cellSize); gx++)
                    if (g.grid[gy][gx] !== g.cellRoom || g._buildingCells[gy * g.gridWidth + gx]) return false
            return true
        }
        let inn = npc(g, "Innkeeper"), smith = npc(g, "Blacksmith"), witch = npc(g, "Witch")
        let off = (p, x, y) => Math.hypot(x - Math.max(p.x - p.w / 2, Math.min(x, p.x + p.w / 2)),
                                          y - Math.max(p.y - p.h / 2, Math.min(y, p.y + p.h / 2)))
        let fl = floorItem(g), fs = faces(g), layer = lightLayer(g), sfx = screenFx(g)
        return {
            seed: seed, depth: d, look: look.name, layout: g.campLayout,
            props: JSON.stringify(g.campProps), count: g.campProps.length,
            landmark: g.campProps.some(p => p.kind === look.layouts[g.campLayout][0].kind),
            onFloor: g.campProps.every(cellsFloor),
            clear: g.campProps.every(p => Math.abs(p.x - cx) >= p.w / 2 + c.clearOfPath
                                     && off(p, fire.xWu, fire.yWu) >= c.clearOfFire
                                     && [inn, smith, witch].every(n => off(p, n.xWu, n.yWu) >= c.clearOfPeople)),
            drawnOnly: laid.length === g.campProps.length
                       && laid.every(o => o.categories === undefined && o.objectName !== "npc" && o.healRadius === undefined),
            brightest: ff.length > 0 && others.every(l => l.intensity < ff[0].intensity && l.radius < ff[0].radius),
            people: [inn, smith, witch].map(n => n.xWu.toFixed(2) + "," + n.yWu.toFixed(2)).join(" ")
                    + " fire " + fire.xWu.toFixed(2) + "," + fire.yWu.toFixed(2),
            taken: fl.style === look.floor.style && Qt.colorEqual(fl.color, look.floor.color)
                   && fs.every(f => f.faceStyle === look.faceStyle) && fs.some(f => Qt.colorEqual(f.color, look.face))
                   && Qt.colorEqual(layer.ambient, look.grade.ambient)
                   && Math.abs(sfx.temperature - look.grade.temperature) < 1e-6
                   && Math.abs(sfx.vignette - look.grade.vignette) < 1e-6
        }
    }

    // --- Captures ---
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
    // A capture's step waits until it is saved; one never saved times the
    // bench out
    property bool saving: false
    function saveGame(name) {
        saving = true
        game.grabToImage(r => {
            let file = outDir + "/" + name + ".png"
            check(r.saveToFile(file), "saved " + file)
            saving = false
        })
    }
    function shotSteps(name, d, seed) {
        return [
            [() => true, () => game.applyScenario("village", d, seed)],
            [() => inCamp(game), () => { bench.raise(); bench.requestActivate(); game.pixelPerUnit = 15 }],
            [500, () => {
                let c = campfire(game)
                game.player.xWu = c.xWu
                game.player.yWu = c.yWu + 2
                nudger.start()
            }],
            [2500, () => { nudger.stop(); saveGame("camp-" + name + "-" + seed) }],
            [() => !saving, () => { game.pixelPerUnit = 40 }],
            [500, () => {
                let c = campfire(game)
                game.player.xWu = c.xWu - 4
                game.player.yWu = c.yWu + 1
                nudger.start()
            }],
            [2500, () => { nudger.stop(); saveGame("fire-" + name + "-" + seed) }],
            [() => !saving, () => { game.pixelPerUnit = 55 }]
        ]
    }

    // --- The steps ---
    property var steps: []
    function buildSteps() {
        let s = []
        let names = Balance.camp.looks.map(l => l.name)
        // Every depth from 0 to 12 in its look
        for (let d = 0; d <= 12; d++) {
            let want = d >= 6 ? "ember" : d >= 3 ? "hall" : "grotto"
            s.push([() => true, () => game.applyScenario("village", d, seeds[0])])
            s.push([() => inCamp(game), () => results.push(survey(game, seeds[0], d))])
        }
        s.push([() => true, () => {
            for (let name of names) {
                let r = results.find(x => x.depth === depths[name])
                check(r && r.look === name, "applyScenario(\"village\", " + depths[name] + ") lands in the "
                      + name + " (" + (r ? r.look : "no camp") + ")")
            }
            let wrong = results.filter(r => r.look !== (r.depth >= 6 ? "ember" : r.depth >= 3 ? "hall" : "grotto"))
            check(wrong.length === 0, "depths 0-2 build the grotto, 3-5 the hall, 6-12 the ember camp"
                  + wrong.map(r => " depth " + r.depth + ": " + r.look).join(""))
            let people = {}
            for (let r of results) people[r.people] = true
            check(Object.keys(people).length === 1, "the campfire, the innkeeper, the smith and the witch stand "
                  + "in the same places at every depth: " + Object.keys(people).join(" | "))
            results = []
        }])
        // Each look its own
        s.push([() => true, () => {
            let looks = Balance.camp.looks, same = []
            for (let i = 0; i < looks.length; i++)
                for (let j = i + 1; j < looks.length; j++) {
                    let a = looks[i], b = looks[j]
                    let parts = [["floor", a.floor.color !== b.floor.color || a.floor.style !== b.floor.style],
                                 ["rock", a.rock !== b.rock], ["faces", a.faceStyle !== b.faceStyle],
                                 ["ambient", a.grade.ambient !== b.grade.ambient],
                                 ["temperature", a.grade.temperature !== b.grade.temperature],
                                 ["air", a.air.color !== b.air.color],
                                 ["props", a.layouts[0].map(p => p.kind).join() !== b.layouts[0].map(p => p.kind).join()]]
                    for (let p of parts) if (!p[1]) same.push(a.name + "/" + b.name + " " + p[0])
                }
            check(same.length === 0, "each look has its own floor, rock, faces, ambient, temperature, air and props"
                  + (same.length ? ": the same " + same.join(", ") : ""))
        }])
        // Every look on every seed
        for (let name of names)
            for (let seed of seeds) {
                let d = depths[name]
                s.push([() => true, () => game.applyScenario("village", d, seed)])
                s.push([() => inCamp(game), () => results.push(survey(game, seed, d))])
            }
        s.push([() => true, () => judge()])
        // Another screen builds the same camps
        s.push([() => true, () => {
            other = gameComponent.createObject(bench.contentItem, {x: bench.width, width: 400, height: 300,
                                                                   muted: true, recordStoreName: storeName})
        }])
        for (let name of names)
            for (let seed of seeds.slice(0, 3)) {
                let d = depths[name]
                s.push([() => true, () => other.applyScenario("village", d, seed)])
                s.push([() => inCamp(other), () => {
                    let mine = results.find(r => r.seed === seed && r.depth === d)
                    let theirs = survey(other, seed, d)
                    check(mine && theirs.look === mine.look && theirs.layout === mine.layout && theirs.props === mine.props,
                          name + ", seed " + seed + ": another screen builds the same camp (layout " + theirs.layout
                          + ", " + theirs.count + " props)")
                }])
            }
        if (outDir !== "")
            for (let name of names)
                for (let seed of shotSeeds) s = s.concat(shotSteps(name, depths[name], seed))
        s.push([300, () => {
            other.destroy()
            game.destroy()
        }])
        s.push([300, () => {
            console.log("[Camps] done,", failures, "failed")
            Qt.exit(failures)
        }])
        return s
    }

    function judge() {
        let list = (rs, f) => rs.filter(f).map(r => r.look + " " + r.seed).join(", ")
        check(results.every(r => r.taken), "each camp takes its look's floor, faces, ambient, temperature and vignette "
              + list(results, r => !r.taken))
        for (let look of Balance.camp.looks) {
            let rs = results.filter(r => r.look === look.name)
            let layouts = {}
            for (let r of rs) layouts[r.layout] = true
            let counts = rs.map(r => r.count)
            check(rs.length === seeds.length && rs.every(r => r.count >= minProps),
                  look.name + ": " + rs.length + " seeds lay " + Math.min.apply(null, counts) + " to "
                  + Math.max.apply(null, counts) + " props, at least " + minProps + " " + list(rs, r => r.count < minProps))
            check(Object.keys(layouts).length >= 2, look.name + ": the seeds pick layouts "
                  + Object.keys(layouts).sort().join(", ") + " of " + look.layouts.length)
        }
        check(results.every(r => r.landmark), "every camp lays its layout's first prop, the look's landmark "
              + "(the pond, the rail track, the cracks) " + list(results, r => !r.landmark))
        check(results.every(r => r.onFloor), "every prop lies whole on the cave's floor " + list(results, r => !r.onFloor))
        check(results.every(r => r.clear), "every prop keeps off the way to the stairs, the campfire and the people "
              + list(results, r => !r.clear))
        check(results.every(r => r.drawnOnly), "the props are drawn only: no body, no npc, no campfire "
              + list(results, r => !r.drawnOnly))
        check(results.every(r => r.brightest), "the campfire is the brightest light of every camp "
              + list(results, r => !r.brightest))
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
                    console.log("[Camps] FAIL step", i, "timed out")
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
