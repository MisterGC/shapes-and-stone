// Gauge bench - a descent gauge shows how deep the knight is (issue #97).
//
// Lands the knight in the dungeon at depth 0, 5 and 15 and saves each
// screen as <out>/depth0.png, depth5.png and depth15.png: the gauge's
// marker sits in the knight's layer and the layers in view are darker and
// hotter the deeper. A dungeon high in depth 5's range shows the same
// gauge as one low in it - the gauge shows the depth, not the danger.
// Then the camp after depth 5: the gauge is large, its marker sinks into
// layer 6 before the next dungeon starts (camp.png). Prints one PASS or
// FAIL line per check and exits with the number of failures. The gauge
// is HUD, so it is saved offscreen too; the dungeon behind it needs a
// window and the shaders copied beside the sources, as the knight bench
// does.
//
//   qml -I <build>/bin/qml tests/gauge/gauge.qml -- <out dir>

import QtQuick
import QtQuick.Window
import "../../src"

Window {
    id: bench
    width: 1000
    height: 700
    visible: true
    color: "#1a1a2e"

    readonly property string outDir: Qt.application.arguments[Qt.application.arguments.length - 1]
    property var game: null
    property int failures: 0

    function check(ok, what) {
        console.log("[Gauge]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Gauge] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height,
                                                  muted: true,
                                                  recordStoreName: "ShapesAndStoneGaugeBench"})
        script.start()
    }

    property bool saved: false
    function capture(name) {
        saved = false
        bench.contentItem.grabToImage(r => {
            let ok = r.saveToFile(outDir + "/" + name + ".png")
            check(ok, "saved " + name + ".png")
            saved = true
        })
    }

    function find(root, name) {
        if (root.objectName === name) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = find(kids[i], name)
            if (f) return f
        }
        return null
    }
    function gauge() { return find(game, "depthGauge") }
    function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    // What the gauge shows: the depth its marker is at, the marker's
    // layer from the shaft's top, the layers in view and their colours
    function shows() {
        let g = gauge()
        let top = Math.floor(g.topDepth), colors = []
        for (let d = top; d < top + g.layers; d++) colors.push(String(g.layerColor(d)))
        return {depth: g.depth, shown: g.shown, layer: (g.markerY / g.layerHeight) - 0.5,
                top: top, colors: colors, camp: g.camp, label: find(game, "gaugeLabel").text}
    }

    // Down a dungeon at danger d, every enemy standing still
    function enter(d) {
        game.applyScenario("dungeon", d)
        game.fx = true
        for (let e of game.enemies) if (e && e.halt) e.halt()
    }

    property var seen: ({})
    function checkDungeon(depth) {
        let s = shows(), g = gauge()
        seen[depth] = s
        check(g.visible && !s.camp && g.layerHeight === Balance.gauge.small.layer,
              "depth " + depth + ": the small gauge shows in the dungeon")
        check(s.depth === depth && s.shown === depth && s.label === "Depth " + depth,
              "depth " + depth + ": its marker is at depth " + s.shown + ", \"" + s.label + "\"")
        let layer = Math.min(depth, Math.floor(g.layers / 2))
        check(Math.abs(s.layer - layer) < 0.001 && s.top === depth - layer,
              "depth " + depth + ": the marker is in layer " + s.layer + " of the view, layers "
              + s.top + " to " + (s.top + g.layers - 1) + " (" + s.colors.join(" ") + ")")
        check(Math.abs(g.heat(depth) - Math.min(1, depth / Balance.gauge.hotDepth)) < 0.001,
              "depth " + depth + ": the knight's layer is " + g.layerColor(depth)
              + ", its seam glowing " + g.heat(depth).toFixed(2))
    }

    property var steps: [
        [() => game.screen === "title", () => enter(0)],
        [1500, () => {
            checkDungeon(0)
            capture("depth0")
        }],
        [() => saved, () => enter(5)],
        [1500, () => {
            checkDungeon(5)
            capture("depth5")
        }],
        [() => saved, () => enter(15)],
        [1500, () => {
            checkDungeon(15)
            let g = gauge()
            let l0 = lum(g.layerColor(0)), l5 = lum(g.layerColor(5)), l15 = lum(g.layerColor(15))
            check(l0 > l5 && l5 > l15,
                  "the deeper the darker: the knight's layer at depth 0, 5 and 15 is "
                  + l0.toFixed(3) + ", " + l5.toFixed(3) + ", " + l15.toFixed(3) + " bright")
            let red = d => g.layerColor(d).r / Math.max(0.001, g.layerColor(d).b)
            check(red(15) > red(5) && red(5) > red(0) && g.heat(15) > g.heat(5) && g.heat(5) > g.heat(0),
                  "the deeper the hotter: red over blue " + red(0).toFixed(2) + ", " + red(5).toFixed(2)
                  + ", " + red(15).toFixed(2) + ", seams " + g.heat(0) + ", " + g.heat(5) + ", " + g.heat(15))
            check(seen[0].colors.join() !== seen[5].colors.join() && seen[5].colors.join() !== seen[15].colors.join(),
                  "the layers in view change with the depth")
            capture("depth15")
        }],
        // The danger's spot in the depth's range does not show
        [() => saved, () => enter(5.9)],
        [500, () => {
            let s = shows()
            check(game.dangerBand(game.dangerPosition) === 2 && JSON.stringify(s) === JSON.stringify(seen[5]),
                  "high in depth 5's range (danger " + game.danger.toFixed(2)
                  + ") the gauge shows what it showed low in it")
            game.applyScenario("village", 5)
        }],
        // The camp: large, the marker sinking into the next layer
        [300, () => {
            let g = gauge()
            check(g.visible && g.camp && g.layerHeight === Balance.gauge.large.layer
                  && g.shaftWidth === Balance.gauge.large.width,
                  "at the camp the gauge is large: layers " + g.layerHeight + " px high, "
                  + g.shaftWidth + " px wide")
            check(g.shown < 6, "the marker has not reached layer 6 yet (" + g.shown.toFixed(2) + ")")
        }],
        [() => gauge().sunk, () => {
            let s = shows()
            check(s.shown === 6 && s.depth === 5 && game.levelType === "village",
                  "before the next dungeon starts the marker has sunk into layer 6 ("
                  + s.shown + "), \"" + s.label + "\"")
            capture("camp")
        }],
        [() => saved, () => enter(6)],
        [500, () => {
            let s = shows()
            check(!s.camp && s.shown === 6, "the dungeon at depth 6 has the small gauge at 6 again")
        }],
        [100, () => console.log("[Gauge] done,", failures, "failed")],
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ]

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
                    console.log("[Gauge] FAIL step", i, "timed out")
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
