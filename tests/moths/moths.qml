// Moths bench - moths circle the camp's lanterns and its campfire, and the
// camp's light breathes (issue #149).
//
// In every look (grotto at depth 0, hall at 4, ember camp at 7) on 4
// seeds the camp has one moth layer and no item per moth: it circles the
// campfire and each lantern with the look's number of moths, at the spot
// each light shines from, and is nothing the benches look for (no body,
// no npc, no campfire, no prop). Raising every light to the most moths it
// takes adds no item to the scene. The campfire and every lantern breathe
// by Balance.camp.breath, each a whole number of breaths in its 1000 s
// round, the intensity swelling and sinking over a few seconds while the
// radius and the heal radius stay put, and the fire at its dimmest
// outshines a lantern at its brightest. A dungeon's torches do not
// breathe. Another screen builds the same moths and breaths from the
// same seed. Prints one PASS or FAIL line per check and exits with the
// number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/moths/moths.qml

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
    readonly property string storeName: "ShapesAndStoneMothsBench"
    readonly property var seeds: [424242, 1000, 8919, 16838]
    readonly property var depths: ({ grotto: 0, hall: 4, ember: 7 })

    function check(ok, what) {
        console.log("[Moths]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    property var gameComponent: null
    Component.onCompleted: {
        gameComponent = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComponent.status !== Component.Ready) {
            console.log("[Moths] FAIL", gameComponent.errorString())
            Qt.exit(1)
            return
        }
        game = gameComponent.createObject(bench.contentItem, {width: bench.width, height: bench.height,
                                                              muted: true, recordStoreName: storeName})
        script.start()
    }

    function inCamp(g) { return g && g.player && g.levelType === "village" && !g.resetting }
    function inDungeon(g) { return g && g.player && g.levelType === "dungeon" && !g.resetting }
    function campfire(g) { return g.dungeonObjects.find(o => o && o.healRadius !== undefined) }
    function mothLayers(g) { return g.dungeonObjects.filter(o => o && o.mothLights !== undefined) }
    function light(o) {
        for (let k of (o.data || [])) if (k && k.castsShadows !== undefined) return k
        return null
    }
    function itemCount(root) {
        let n = 1
        for (let k of (root.children || [])) n += itemCount(k)
        return n
    }
    function near(a, b) { return Math.abs(a - b) < 1e-6 }

    // What one seed's camp's moths and breaths are, as the checks read them
    function survey(g, seed) {
        let look = g.campLook, m = Balance.camp.moths, b = Balance.camp.breath
        let layers = mothLayers(g), fire = campfire(g), lanterns = g.torches
        let layer = layers[0]
        let ls = layer ? layer.mothLights : []
        let fx = fire.xWu + fire.widthWu / 2, fy = fire.yWu - fire.heightWu / 2
        let breathers = [fire].concat(lanterns)
        return {
            seed: seed, look: look.name, layers: layers.length,
            lights: ls.length, lanterns: lanterns.length,
            atFire: ls.length > 0 && near(ls[0].x, fx) && near(ls[0].y, fy)
                    && ls[0].orbit === m.fire.orbit && ls[0].count === look.moths.fire,
            atLanterns: ls.length === lanterns.length + 1
                        && lanterns.every((t, i) => near(ls[i + 1].x, t.xWu) && near(ls[i + 1].y, t.yWu - 0.5)
                                          && ls[i + 1].orbit === m.lantern.orbit
                                          && ls[i + 1].count === look.moths.lantern),
            count: layer ? layer.mothCount : 0,
            colour: layer ? Qt.colorEqual(Qt.rgba(layer.color.r, layer.color.g, layer.color.b, 1), look.moths.color)
                            && Math.abs(layer.color.a - look.moths.alpha) < 0.01 : false,
            nobody: layers.every(o => o.categories === undefined && o.objectName !== "npc"
                                 && o.healRadius === undefined && o.propKind === undefined),
            breathe: breathers.every(l => l.breath === b.depth && l.breathSeconds >= b.seconds[0]
                                     && l.breathSeconds <= b.seconds[1]
                                     && near(1000 / l.breathSeconds, Math.round(1000 / l.breathSeconds))),
            byLight: breathers.every(l => near(light(l).intensity, (l === fire ? 1.1 : 0.75) * l.breathing)),
            key: (layer ? layer.seed : -1) + " " + JSON.stringify(ls) + " "
                 + breathers.map(l => l.breathSeconds.toFixed(4) + "/" + l.breathPhase.toFixed(4)).join(" ")
        }
    }

    // A few seconds of the fire's and a lantern's light, sampled
    property var samples: []
    Timer {
        id: sampler
        interval: 50
        repeat: true
        onTriggered: {
            let f = campfire(game), t = game.torches[0]
            let fl = light(f), tl = light(t)
            bench.samples.push({ fire: fl.intensity, fireRadius: fl.radius, lantern: tl.intensity,
                                 lanternRadius: tl.radius, heal: f.healRadius })
        }
    }

    // --- The steps ---
    property var results: []
    property var steps: []
    function buildSteps() {
        let s = []
        let names = Balance.camp.looks.map(l => l.name)
        for (let name of names)
            for (let seed of seeds) {
                s.push([() => true, () => game.applyScenario("village", depths[name], seed)])
                s.push([() => inCamp(game), () => results.push(survey(game, seed))])
            }
        s.push([() => true, () => judge()])
        // No item per moth: every light at the most moths it takes
        s.push([() => true, () => game.applyScenario("village", 0, seeds[0])])
        s.push([() => inCamp(game), () => {
            let layer = mothLayers(game)[0]
            let before = itemCount(game), was = layer.mothCount
            layer.mothLights = layer.mothLights.map(l => Object.assign({}, l, { count: layer.maxPerLight }))
            let after = itemCount(game)
            check(layer.mothCount === layer.maxPerLight * layer.mothLights.length && after === before,
                  "from " + was + " to " + layer.mothCount + " moths the scene keeps its " + before
                  + " items (" + after + ")")
        }])
        // The light breathes, the radius and the heal stay put
        s.push([() => true, () => game.applyScenario("village", 0, seeds[1])])
        s.push([() => inCamp(game), () => { samples = []; sampler.start() }])
        s.push([6000, () => {
            sampler.stop()
            let b = Balance.camp.breath
            let span = k => Math.max(...samples.map(x => x[k])) - Math.min(...samples.map(x => x[k]))
            check(samples.length > 50 && span("fire") > 0.01 && span("lantern") > 0.005,
                  "over 6 s the fire's light swings by " + span("fire").toFixed(3) + " and a lantern's by "
                  + span("lantern").toFixed(3) + " (" + samples.length + " samples)")
            check(span("fireRadius") === 0 && span("lanternRadius") === 0 && span("heal") === 0
                  && samples[0].fireRadius === Balance.camp.fireLight && samples[0].heal === Balance.campfire.healRadius,
                  "the radii stay put while they breathe: fire " + samples[0].fireRadius + " wu, lantern "
                  + samples[0].lanternRadius + " wu, heal " + samples[0].heal + " wu")
            check(Math.min(...samples.map(x => x.fire)) > Math.max(...samples.map(x => x.lantern))
                  && 1.1 * (1 - b.depth) > 0.75 * (1 + b.depth),
                  "the fire at its dimmest (" + (1.1 * (1 - b.depth)).toFixed(3) + ") outshines a lantern at its "
                  + "brightest (" + (0.75 * (1 + b.depth)).toFixed(3) + ")")
        }])
        // A dungeon's torches do not breathe
        s.push([() => true, () => game.applyScenario("dungeon", 0, seeds[0])])
        s.push([() => inDungeon(game), () => {
            check(game.torches.length > 0 && game.torches.every(t => t.breath === 0 && t.breathing === 1)
                  && mothLayers(game).length === 0,
                  "a dungeon's " + game.torches.length + " torches do not breathe and it has no moths")
        }])
        // Another screen builds the same moths and breaths
        s.push([() => true, () => {
            other = gameComponent.createObject(bench.contentItem, {x: bench.width, width: 400, height: 300,
                                                                   muted: true, recordStoreName: storeName})
        }])
        for (let name of names) {
            let seed = seeds[2]
            s.push([() => true, () => other.applyScenario("village", depths[name], seed)])
            s.push([() => inCamp(other), () => {
                let mine = results.find(r => r.seed === seed && r.look === name)
                let theirs = survey(other, seed)
                check(mine && theirs.key === mine.key, name + ", seed " + seed
                      + ": another screen builds the same moths and breaths")
            }])
        }
        s.push([300, () => {
            other.destroy()
            game.destroy()
        }])
        s.push([300, () => {
            console.log("[Moths] done,", failures, "failed")
            Qt.exit(failures)
        }])
        return s
    }

    function judge() {
        let list = (rs, f) => rs.filter(f).map(r => r.look + " " + r.seed).join(", ")
        check(results.every(r => r.layers === 1), "every camp has one moth layer "
              + list(results, r => r.layers !== 1))
        check(results.every(r => r.lanterns === 4 && r.lights === 5), "it circles the campfire and the 4 lanterns "
              + list(results, r => r.lights !== 5))
        check(results.every(r => r.atFire && r.atLanterns), "at the spot each light shines from, with the look's "
              + "moths and loop " + list(results, r => !(r.atFire && r.atLanterns)))
        for (let look of Balance.camp.looks) {
            let rs = results.filter(r => r.look === look.name)
            let want = look.moths.fire + 4 * look.moths.lantern
            check(rs.length === seeds.length && rs.every(r => r.count === want && r.colour),
                  look.name + ": " + want + " moths (" + look.moths.fire + " at the fire, " + look.moths.lantern
                  + " at each lantern) in " + look.moths.color + " " + list(rs, r => r.count !== want || !r.colour))
        }
        let keys = {}
        for (let r of results.filter(r => r.look === "grotto")) keys[r.key] = true
        check(Object.keys(keys).length === seeds.length, "the grotto's " + seeds.length + " seeds fly "
              + Object.keys(keys).length + " different moths and breaths")
        check(results.every(r => r.nobody), "the moths are drawn only: no body, no npc, no campfire, no prop "
              + list(results, r => !r.nobody))
        check(results.every(r => r.breathe), "the campfire and every lantern breathe by Balance.camp.breath, a whole "
              + "number of breaths in 1000 s " + list(results, r => !r.breathe))
        check(results.every(r => r.byLight), "the light's intensity is its own times its breath "
              + list(results, r => !r.byLight))
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
                    console.log("[Moths] FAIL step", i, "timed out")
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
