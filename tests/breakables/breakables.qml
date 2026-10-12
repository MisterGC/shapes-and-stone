// Breakables bench - urns, crates and crystal clusters break under a
// swing and may hold gold (issue #123).
//
// Lands in the dojo's features scenario, where every room but the first
// holds one of each kind, and stills the enemies. With an out dir and a
// window it first lines up an urn, a crate, a barrel and a crystal in
// front of the knight and saves them whole (breakables.png) and breaking
// under a charged swing (breaking.png). Then it walks the knight into a
// crate, which stops it; swings at an urn and a crate, which break, and
// at a crystal, which a swing glances off and a charged swing breaks.
// Three urns in front of the knight: a swing breaks the nearest alone, a
// charged swing the other two at once; the whirlwind breaks three crates
// around the knight and passes a crystal. Then it breaks every thing of
// the dungeon with a swing, a crystal with a charged one, and checks that
// each dropped the gold the table gives it on the scenario seed, where it
// stood, against the fingerprint recorded below. Last it rolls the gold
// of every breakable of 40 seeds: each kind holds gold about as often as
// its chance says and always an amount in its range, a crystal more often
// and more than an urn, and a crystal deeper down more. Prints one PASS or
// FAIL line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/breakables/breakables.qml
//   qml -I <build>/bin/qml tests/breakables/breakables.qml -- <out dir>

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
        console.log("[Breakables]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Breakables] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                  recordStoreName: "ShapesAndStoneBreakablesBench"})
        script.start()
    }

    // The gold every breakable of the features scenario on its seed drops,
    // in the order of its features, recorded from this build
    readonly property string recorded: "c1fd59c2"
    readonly property int seeds: 40
    readonly property var kinds: ["urn", "crate", "crystal"]

    function hash(ls) {
        let s = ls.join("\n"), h = 5381
        for (let i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0
        return h.toString(16)
    }
    function p() { return game.player }
    function centre() { return { x: p().xWu + p().widthWu / 2, y: p().yWu - p().heightWu / 2 } }
    // The knight's centre on (x, y), standing, its swing ready
    function standAt(x, y) {
        p().xWu = x - p().widthWu / 2
        p().yWu = y + p().heightWu / 2
        p().moveX = 0
        p().moveY = 0
        p().attackCooldown = 0
        p().isAttacking = false
        p().isHeavy = false
    }
    function face(x, y) {
        let c = centre()
        p().facingAngle = Math.atan2(y - c.y, x - c.x) * 180 / Math.PI
    }
    // What the bench keeps of a thing: a thing broken is destroyed, and
    // null wherever it was held
    function snap(b) { return b ? { kind: b.kind, cell: b.cell, cxWu: b.cxWu, cyWu: b.cyWu, sizeWu: b.sizeWu } : null }
    // A thing made for the bench by itself, one of the dungeon's by its cell
    function whole(t) {
        if (!t) return false
        return t.objectName !== undefined ? game.breakables.indexOf(t) >= 0
                                          : game.breakables.some(b => b.cell === t.cell && b.kind === t.kind)
    }
    // The gold drops lying where b stood
    function dropsAt(b) {
        return game.goldDrops.filter(d => d && Math.abs(d.xWu - b.cxWu) < 1e-6 && Math.abs(d.yWu - b.cyWu) < 1e-6)
    }
    function goldText(b) { let d = dropsAt(b); return d.length ? String(d[0].amount) : "none" }
    // A thing made for the bench in front of the knight: kind at
    // (x, y), not one of the dungeon's features
    function put(kind, x, y) {
        return game._placeBreakable({ kind: kind, gx: Math.floor(x / game.cellSize),
                                      gy: Math.floor(y / game.cellSize), xWu: x, yWu: y }, 0)
    }
    // Where the knight stands to swing at b: 1.4 wu off its centre on the
    // side a walkable cell with no other thing lies
    function besideOf(b) {
        let g = game.grid
        for (let d of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
            let gx = Math.floor(b.cxWu / game.cellSize) + d[0], gy = Math.floor(b.cyWu / game.cellSize) + d[1]
            if (!g[gy] || g[gy][gx] === game.cellWall) continue
            if (game.breakables.some(o => o.cell !== b.cell && Math.floor(o.cxWu / game.cellSize) === gx
                                     && Math.floor(o.cyWu / game.cellSize) === gy)) continue
            return { x: b.cxWu + d[0] * 1.4, y: b.cyWu + d[1] * 1.4 }
        }
        return null
    }
    function swingAt(b, heavy) {
        let at = besideOf(b)
        if (!at) return false
        standAt(at.x, at.y)
        face(b.cxWu, b.cyWu)
        return heavy ? p().heavyAttack() : (p().attack(), true)
    }
    function firstOf(kind) { return snap(game.breakables.find(b => b.kind === kind && besideOf(b))) }

    property var target: null
    property var row: []
    property var tally: ({ broken: 0, missed: [], rolls: [] })

    property var steps: [
        [() => game.screen === "title", () => {
            let t = Balance.dungeon.loot
            check(t && kinds.every(k => t[k] && t[k].chance > 0 && t[k].gold[1] >= t[k].gold[0]
                                   && Balance.dungeon.kinds[k]),
                  "Balance.dungeon has a loot row and a density for " + kinds.join(", "))
            check(t.crystal.chance > t.urn.chance && t.crystal.gold[0] > t.urn.gold[1],
                  "a crystal holds gold more often (" + t.crystal.chance + ") and more ("
                  + t.crystal.gold.join("-") + ") than an urn (" + t.urn.chance + ", " + t.urn.gold.join("-") + ")")
            game.applyScenario("features")
        }],
        [500, () => {
            for (let e of game.enemies) if (e && e.halt) e.halt()
            p().hp = 100000
            let n = kinds.map(k => game.breakables.filter(b => b.kind === k).length)
            check(game.levelType === "dungeon" && n.every(c => c > 0),
                  "the features scenario stands " + kinds.map((k, i) => n[i] + " " + k).join(", ")
                  + " on its cells")
            check(game.breakables.every(b => game.features.some(f => f.kind === b.kind && f.xWu === b.cxWu
                                                                 && f.yWu === b.cyWu)),
                  "each stands on a feature of its kind")
            if (outDir === "") return
            // In the start room, in front of the knight: urn, crate,
            // barrel, crystal in an arc
            game.fx = true
            let c = centre()
            row = [["urn", -60], ["crate", -20], ["crate", 20], ["crystal", 60]].map((k, i) => {
                let a = k[1] * Math.PI / 180
                let b = put(k[0], c.x + Math.cos(a) * 2.1, c.y + Math.sin(a) * 2.1)
                if (i === 1) b.seed = 0.9
                if (i === 2) b.seed = 0.1
                return b
            })
            face(c.x + 1, c.y)
            game.camera.target = null
            game.camera.target = p()
        }],
        [700, () => {
            if (outDir === "") return
            bench.contentItem.grabToImage(r => {
                let ok = r.saveToFile(outDir + "/breakables.png")
                console.log("[Breakables]", ok ? "saved" : "could not save", outDir + "/breakables.png")
            })
        }],
        [300, () => {
            if (outDir === "") return
            p().attackCooldown = 0
            p().heavyAttack()
        }],
        [90, () => {
            if (outDir === "") return
            bench.contentItem.grabToImage(r => {
                let ok = r.saveToFile(outDir + "/breaking.png")
                console.log("[Breakables]", ok ? "saved" : "could not save", outDir + "/breaking.png")
            })
        }],
        [400, () => {
            if (outDir !== "")
                check(row.every(b => !whole(b)), "the charged swing broke the urn, the crate, the barrel and the crystal in its arc")
            // A crate stops the knight like a wall
            target = firstOf("crate")
            let at = besideOf(target)
            standAt(at.x, at.y)
            p().moveX = Math.sign(target.cxWu - at.x)
            p().moveY = -Math.sign(target.cyWu - at.y)
        }],
        [600, () => {
            let c = centre(), gap = Math.max(Math.abs(c.x - target.cxWu), Math.abs(c.y - target.cyWu))
            let edge = target.sizeWu / 2 + p().widthWu / 2
            check(whole(target) && gap >= edge - 0.05,
                  "walking into a crate for 0.6 s the knight stops at its side: " + gap.toFixed(2)
                  + " wu centre to centre, the two touch at " + edge.toFixed(2))
            p().moveX = 0
            p().moveY = 0
            // A swing at an urn
            target = firstOf("urn")
            swingAt(target, false)
        }],
        [300, () => {
            let gold = game.breakableGold("urn", target.cell)
            check(!whole(target), "a swing breaks an urn (" + target.cell + ")")
            check(goldText(target) === (gold > 0 ? String(gold) : "none"),
                  "it drops the gold the table gives it where it stood: " + goldText(target) + ", rolled " + gold)
            target = firstOf("crate")
            swingAt(target, false)
        }],
        [300, () => {
            let gold = game.breakableGold("crate", target.cell)
            check(!whole(target), "a swing breaks a crate (" + target.cell + ")")
            check(goldText(target) === (gold > 0 ? String(gold) : "none"),
                  "it drops the gold the table gives it where it stood: " + goldText(target) + ", rolled " + gold)
            target = firstOf("crystal")
            swingAt(target, false)
        }],
        [300, () => {
            check(whole(target) && dropsAt(target).length === 0,
                  "a swing glances off a crystal (" + target.cell + "): it stands, nothing dropped")
            swingAt(target, true)
        }],
        [300, () => {
            let gold = game.breakableGold("crystal", target.cell)
            check(!whole(target), "a charged swing breaks it")
            check(goldText(target) === (gold > 0 ? String(gold) : "none"),
                  "it drops the gold the table gives it where it stood: " + goldText(target) + ", rolled " + gold)
            // Three urns in front of the knight, in the start room
            let r = game.rooms[0]
            standAt((r.x + 1) * game.cellSize, (r.y + r.h / 2) * game.cellSize)
            let c = centre()
            row = [[0, 1.5], [25, 1.8], [-25, 2.0]].map(u => {
                let a = u[0] * Math.PI / 180
                return put("urn", c.x + Math.cos(a) * u[1], c.y + Math.sin(a) * u[1])
            })
            face(c.x + 1, c.y)
            p().attack()
        }],
        [300, () => {
            check(!whole(row[0]) && whole(row[1]) && whole(row[2]),
                  "of three urns in its arc a swing breaks the nearest alone")
            p().attackCooldown = 0
            p().isAttacking = false
            p().heavyAttack()
        }],
        [300, () => {
            check(!whole(row[1]) && !whole(row[2]), "a charged swing breaks the other two at once")
            // Three crates around the knight and a crystal: the whirlwind
            let r = game.rooms[0]
            standAt((r.x + r.w / 2) * game.cellSize, (r.y + r.h / 2) * game.cellSize)
            let c = centre()
            row = [[0, "crate"], [120, "crate"], [240, "crate"], [180, "crystal"]].map(u => {
                let a = u[0] * Math.PI / 180
                return put(u[1], c.x + Math.cos(a) * 1.5, c.y + Math.sin(a) * 1.5)
            })
            p().momentum = Balance.momentum.max
            p().mana = p().maxMana
            face(c.x, c.y + 1)
            check(p().unleash(), "the knight whirls")
        }],
        [Balance.knight.whirlDuration * 1000 + 300, () => {
            check(row.slice(0, 3).every(b => !whole(b)), "the whirlwind breaks the three crates around the knight")
            check(whole(row[3]), "and passes the crystal")
            game._wreck(row[3], 0, 1)
            p().isDashing = false
            p().isWhirling = false
        }],
    ].concat(breakAllSteps()).concat([
        [100, () => {
            check(tally.missed.length === 0, "every thing of the dungeon broke under its swing and dropped "
                  + "its gold where it stood (" + tally.broken + " broken)"
                  + (tally.missed.length ? ": " + tally.missed.length + " did not, e.g. "
                     + tally.missed.slice(0, 3).join("; ") : ""))
            let h = hash(tally.rolls)
            console.log("[Breakables] gold fingerprint:", h, tally.rolls.length, "things")
            check(h === recorded, "seed " + game.scenarioSeed + " drops the gold recorded (" + h
                  + ", recorded " + recorded + ")")
        }]
    ]).concat(seedSteps()).concat([
        [100, () => {
            let t = Balance.dungeon.loot
            for (let k of kinds) {
                let s = rolled[k], share = s.gold / s.n
                check(s.n >= 30 && Math.abs(share - t[k].chance) < 0.12,
                      seeds + " seeds: " + s.n + " " + k + "s hold gold " + (100 * share).toFixed(0)
                      + "% of the time, the table's chance " + (100 * t[k].chance).toFixed(0) + "%")
                check(s.outside.length === 0, "every " + k + "'s gold lies in its range at its depth"
                      + (s.outside.length ? ": " + s.outside.slice(0, 3).join("; ") : ""))
            }
            let mean = k => rolled[k].sum / Math.max(1, rolled[k].gold)
            check(mean("crystal") > mean("urn") && mean("crystal") > mean("crate"),
                  "a crystal holds more than an urn or a crate: " + kinds.map(k => k + " "
                  + mean(k).toFixed(1)).join(", ") + " on average")
            check(rolled.deepCrystal > mean("crystal"),
                  "at depth 4 a crystal holds more: " + rolled.deepCrystal.toFixed(1) + " on average")
            console.log("[Breakables] done,", failures, "failed")
        }],
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ])

    // Every thing left of the scenario's dungeon, one a step: a swing, a
    // charged one at a crystal, and its drop read the next step
    function breakAllSteps() {
        let out = [[100, () => {
            game.applyScenario("features")
            for (let e of game.enemies) if (e && e.halt) e.halt()
            p().hp = 100000
            tally.queue = game.features.filter(f => kinds.indexOf(f.kind) >= 0)
            target = null
        }]]
        // As many steps as the scenario has things, and some to spare
        for (let i = 0; i < 80; i++) {
            out.push([() => !p().isAttacking, () => {
                if (target) {
                    let gold = game.breakableGold(target.kind, target.cell)
                    tally.rolls.push(target.cell + ":" + gold)
                    if (whole(target) || goldText(target) !== (gold > 0 ? String(gold) : "none"))
                        tally.missed.push(target.kind + " at " + target.cell + (whole(target) ? " stands"
                                          : " dropped " + goldText(target) + ", rolled " + gold))
                    else tally.broken++
                    target = null
                }
                let f = tally.queue.shift()
                if (!f) return
                target = snap(game.breakableAt(f.gx + "," + f.gy))
                if (!target || !swingAt(target, f.kind === "crystal")) {
                    tally.missed.push(f.kind + " at " + f.gx + "," + f.gy + (target ? " has no side to swing from"
                                                                              : " is not there"))
                    target = null
                }
            }])
        }
        return out
    }

    // The gold of every breakable on 40 seeds, rolled without breaking
    // them, across the bands; and the crystals once more at depth 4
    property var rolled: ({ urn: { n: 0, gold: 0, sum: 0, outside: [] },
                            crate: { n: 0, gold: 0, sum: 0, outside: [] },
                            crystal: { n: 0, gold: 0, sum: 0, outside: [] }, deepCrystal: 0 })
    function seedSteps() {
        let out = []
        for (let i = 0; i < seeds; i++) {
            out.push([60, () => {
                let seed = 5000 + i * 7919
                game.applyScenario("features", (i % 10) * 0.55, seed)
                for (let f of game.features) {
                    let s = rolled[f.kind]
                    if (!s) continue
                    let t = Balance.dungeon.loot[f.kind], g = game.breakableGold(f.kind, f.gx + "," + f.gy)
                    let lo = t.gold[0] + t.perDepth * game.depth, hi = t.gold[1] + t.perDepth * game.depth
                    s.n++
                    if (g > 0) { s.gold++; s.sum += g }
                    if (g !== 0 && (g < lo || g > hi || g !== Math.floor(g)))
                        s.outside.push("seed " + seed + " " + f.gx + "," + f.gy + ": " + g + " not in " + lo + "-" + hi)
                }
            }])
        }
        out.push([60, () => {
            game.applyScenario("features", 4.5)
            let g = game.features.filter(f => f.kind === "crystal")
                        .map(f => game.breakableGold("crystal", f.gx + "," + f.gy)).filter(v => v > 0)
            rolled.deepCrystal = g.reduce((a, v) => a + v, 0) / Math.max(1, g.length)
        }])
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
                    console.log("[Breakables] FAIL step", i, "timed out")
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
                console.log("[Breakables] FAIL step", i - 1, "threw:", err)
                Qt.exit(failures + 1)
                stop()
            }
        }
    }
}
