// Spikes bench - a spike plate clicks when a knight steps on it, its
// spikes rise Balance.dungeon.spikeDelay later and hurt a knight still on
// it, and a dash at the click saves it (issue #124).
//
// Lands in the dojo's features scenario, where every room but the first
// holds a plate, and stills the enemies. Checks that the scenario shows
// its plates, armed, each on a spike feature's cell, and that laying them
// out moved none of the other features. With an out dir and a window it
// saves plates.png, a plate armed and one sprung beside the knight. Then
// an enemy stands on a plate, which stays armed; the knight stands on
// another: it clicks, the knight's HP stays until spikeDelay later, when
// the spikes rise and take spikeDamageAt(depth) - rising.png is saved
// then - and the plate stays sprung through a second's standing, a step
// off and a step back on. The knight steps on a third and dashes at the
// click: the spikes rise behind it and it takes nothing. Last the damage
// against the cap: spikeDamageAt never more than spikeCap of the knight's
// max HP from depth 0 to 60, and the spikes of a plate at depth 0, 3, 8
// and 20 take that much and no more. Prints one PASS or FAIL line per
// check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/spikes/spikes.qml
//   qml -I <build>/bin/qml tests/spikes/spikes.qml -- <out dir>

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
        console.log("[Spikes]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Spikes] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                  recordStoreName: "ShapesAndStoneSpikesBench"})
        script.start()
    }

    // Every click and rise the game reports, by cell; the dash at the
    // click of the plate on dashAt
    property var clicks: ({})
    property var rises: ({})
    // The simulated seconds, summed over the physics steps, at each click
    // and rise
    property real simT: 0
    property var clickedAt: ({})
    property var roseAt: ({})
    Connections {
        target: game ? game.physics : null
        function onStepped() { bench.simT += game.physics.timeStep }
    }
    property string dashAt: ""
    property var dashDir: [0, 0]
    Connections {
        target: game
        function onPlateClicked(cell) {
            clicks[cell] = (clicks[cell] || 0) + 1
            clickedAt[cell] = simT
            if (cell !== bench.dashAt) return
            p().moveX = bench.dashDir[0]
            p().moveY = bench.dashDir[1]
            p().dash()
            p().moveX = 0
            p().moveY = 0
        }
        function onPlateRose(cell, result) {
            rises[cell] = (rises[cell] || []).concat([result])
            roseAt[cell] = simT
        }
    }

    function p() { return game.player }
    // The knight's centre on (x, y), standing
    function standAt(x, y) {
        p().xWu = x - p().widthWu / 2
        p().yWu = y + p().heightWu / 2
        p().moveX = 0
        p().moveY = 0
    }
    function fresh() {
        p().hp = p().maxHp
        p().graceLeft = 0
        p().mana = p().maxMana
        p().dashCooldown = 0
    }
    function halt() { for (let e of game.enemies) if (e && e.halt) e.halt() }
    function capOf() { return Math.floor(Balance.dungeon.spikeCap * p().maxHp) }
    // The way out of plate q a dash takes: three floor cells in a row
    // with no breakable on them, (moveX, moveY), y down
    function wayOut(q) {
        let gx = Math.floor(q.xWu / game.cellSize), gy = Math.floor(q.yWu / game.cellSize)
        for (let d of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            let ok = true
            for (let i = 1; i <= 3; i++) {
                let x = gx + d[0] * i, y = gy + d[1] * i
                if (!game.grid[y] || game.grid[y][x] === game.cellWall || game.grid[y][x] === undefined
                        || game.breakableAt(x + "," + y)) ok = false
            }
            if (ok) return [d[0], -d[1]]
        }
        return null
    }
    // The plates still armed
    function armed() { return game.plates.filter(q => q.phase === "armed") }
    function lines(list) { return list.map(f => [f.kind, f.gx, f.gy].join(":")) }

    property var plateA: null
    property var plateB: null
    property var plateE: null
    property var enemy: null
    property real hpAtClick: 0
    property var row: []
    property var capHits: []

    property var steps: [
        [() => game.screen === "title", () => {
            let t = Balance.dungeon
            check(t.spikeDelay >= 0.2 && t.spikeDelay <= 0.3 && t.spikeDamage > 0 && t.spikeCap > 0
                  && t.spikeCap < 1 && t.kinds.spike,
                  "Balance.dungeon has spikeDelay " + t.spikeDelay + " s, spikeDamage " + t.spikeDamage
                  + " (+" + t.spikeDamagePerDepth + " a depth), spikeCap " + t.spikeCap
                  + " and a density for spike plates")
            game.applyScenario("features")
        }],
        [500, () => {
            halt()
            let plates = game.plates, spikes = game.features.filter(f => f.kind === "spike")
            check(game.levelType === "dungeon" && plates.length > 0 && plates.length === spikes.length
                  && plates.every(q => q.visible && q.phase === "armed"),
                  "the features scenario shows " + plates.length + " spike plates, all armed, for "
                  + spikes.length + " spike features")
            check(plates.every(q => spikes.some(f => f.xWu === q.xWu && f.yWu === q.yWu
                                                && game.featureCellOk(f.gx, f.gy))),
                  "each stands on its feature's cell, a room's, off any doorway and corridor")
            // Laid out last, the plates moved no other feature
            let ls = game.deriveSeed(game.masterSeed, game.levelIndex)
            let kinds = Object.assign({}, Balance.dungeon.kinds)
            delete kinds.spike
            let without = lines(game.planFeatures(ls, 0, true, kinds))
            let others = lines(game.features.filter(f => f.kind !== "spike"))
            check(JSON.stringify(without) === JSON.stringify(others),
                  "laying out the plates moved none of the " + others.length + " other features")
            if (outDir === "") return
            // In the start room: an armed plate left of the knight, a
            // sprung one right of it
            game.fx = true
            let r = game.rooms[0]
            let cx = (r.x + r.w / 2) * game.cellSize, cy = (r.y + r.h / 2) * game.cellSize
            standAt(cx, cy + 1.6)
            row = [-1.3, 1.3].map(dx => game._placePlate({ gx: -1, gy: -1, xWu: cx + dx, yWu: cy }, 1))
            row[1].phase = "sprung"
            game.camera.target = null
            game.camera.target = p()
        }],
        [700, () => {
            if (outDir === "") return
            bench.contentItem.grabToImage(r => {
                let ok = r.saveToFile(outDir + "/plates.png")
                console.log("[Spikes]", ok ? "saved" : "could not save", outDir + "/plates.png")
            })
        }],
        [200, () => {
            for (let q of row) { game.plates.splice(game.plates.indexOf(q), 1); q.destroy() }
            row = []
            // Only knights: an enemy on a plate
            plateE = armed()[0]
            enemy = game.enemies.find(e => e && !e.destroyed)
            enemy.xWu = plateE.xWu - enemy.widthWu / 2
            enemy.yWu = plateE.yWu + enemy.heightWu / 2
        }],
        [500, () => {
            let c = { x: enemy.xWu + enemy.widthWu / 2, y: enemy.yWu - enemy.heightWu / 2 }
            check(Math.abs(c.x - plateE.xWu) < plateE.sizeWu / 2 && Math.abs(c.y - plateE.yWu) < plateE.sizeWu / 2
                  && plateE.phase === "armed" && !clicks[plateE.cell],
                  "an enemy standing on the plate at " + plateE.cell + " for 0.5 s leaves it armed")
            enemy.xWu = -50
            // The knight on another, standing still
            plateA = armed().find(q => q !== plateE)
            fresh()
            standAt(plateA.xWu, plateA.yWu)
        }],
        [() => plateA.phase !== "armed", () => {
            hpAtClick = p().hp
            check(plateA.phase === "clicked" && clicks[plateA.cell] === 1 && hpAtClick === p().maxHp,
                  "the knight on the plate at " + plateA.cell + " makes it click, its HP still "
                  + hpAtClick + " / " + p().maxHp)
        }],
        [() => plateA.phase === "sprung", () => {
            let dt = game.physics.timeStep, took = hpAtClick - p().hp
            let after = roseAt[plateA.cell] - clickedAt[plateA.cell]
            let want = game.spikeDamageAt(game.depth, p().maxHp)
            // On the first physics step the delay has run out: not before
            // it, and less than two 60 Hz steps after it
            check(after >= Balance.dungeon.spikeDelay - 1e-6 && after < Balance.dungeon.spikeDelay + 1 / 30,
                  "its spikes rise " + after.toFixed(3) + " s after the click on the physics clock, "
                  + "spikeDelay " + Balance.dungeon.spikeDelay + " s (the last step " + dt.toFixed(4) + " s)")
            check(took === want && plateA.result === "hit",
                  "the knight still on it takes " + took + ", spikeDamageAt(depth " + game.depth + ") "
                  + want + " (" + plateA.result + ")")
            if (outDir === "") return
            game.camera.target = null
            game.camera.target = p()
        }],
        [120, () => {
            if (outDir === "") return
            bench.contentItem.grabToImage(r => {
                let ok = r.saveToFile(outDir + "/rising.png")
                console.log("[Spikes]", ok ? "saved" : "could not save", outDir + "/rising.png")
            })
        }],
        // Fires once: standing on, a step off and a step back on
        [1000, () => {
            hpAtClick = p().hp
            standAt(plateA.xWu + game.cellSize, plateA.yWu)
        }],
        [300, () => standAt(plateA.xWu, plateA.yWu)],
        [1000, () => {
            check(p().hp === hpAtClick && plateA.phase === "sprung" && clicks[plateA.cell] === 1
                  && rises[plateA.cell].length === 1,
                  "the plate fires once: a second on it, a step off and back on and a second more take "
                  + (hpAtClick - p().hp) + ", " + clicks[plateA.cell] + " click and "
                  + rises[plateA.cell].length + " rise, still sprung")
            // A third plate with a way out, a dash at its click
            plateB = armed().find(q => q !== plateE && wayOut(q))
            dashDir = wayOut(plateB)
            dashAt = plateB.cell
            fresh()
            standAt(plateB.xWu, plateB.yWu)
        }],
        [() => plateB.phase === "sprung", () => {
            let off = !game.onPlate(plateB)
            check(p().hp === p().maxHp && (plateB.result === "clear" || plateB.result === "dodged") && off,
                  "a knight that dashes off the plate at " + plateB.cell + " at its click takes "
                  + (p().maxHp - p().hp) + " when the spikes rise (" + plateB.result + ", "
                  + (off ? "off the plate" : "still on it") + ")")
            dashAt = ""
            // The damage against the cap at every depth
            let cap = capOf(), over = []
            for (let d = 0; d <= 60; d++) {
                let v = game.spikeDamageAt(d, p().maxHp)
                if (v > cap || v <= 0) over.push("depth " + d + ": " + v)
            }
            check(over.length === 0 && game.spikeDamageAt(60, p().maxHp) === cap,
                  "spikeDamageAt from depth 0 to 60 lies in 1.." + cap + ", spikeCap " + Balance.dungeon.spikeCap
                  + " of " + p().maxHp + " HP, and reaches it" + (over.length ? ": " + over.join(", ") : ""))
        }],
    ].concat(capSteps()).concat([
        [100, () => {
            let cap = capOf()
            check(capHits.length === 4 && capHits.every(h => h.took === h.want && h.took <= cap),
                  "the spikes take spikeDamageAt and never more than " + cap + ": "
                  + capHits.map(h => "depth " + h.depth + " " + h.took + " (" + h.want + ")").join(", "))
            console.log("[Spikes] done,", failures, "failed")
        }],
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ])

    // A plate's spikes at depth 0, 3, 8 and 20, on the knight standing on it
    function capSteps() {
        let out = []
        for (let d of [0, 3, 8, 20]) {
            out.push([100, () => {
                game.applyScenario("features", d)
            }])
            out.push([300, () => {
                halt()
                plateA = armed()[0]
                fresh()
                standAt(plateA.xWu, plateA.yWu)
            }])
            out.push([() => plateA.phase === "sprung", () => {
                capHits.push({ depth: game.depth, took: p().maxHp - p().hp,
                               want: game.spikeDamageAt(game.depth, p().maxHp) })
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
                    console.log("[Spikes] FAIL step", i, "timed out")
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
                console.log("[Spikes] FAIL step", i - 1, "threw:", err)
                Qt.exit(failures + 1)
                stop()
            }
        }
    }
}
