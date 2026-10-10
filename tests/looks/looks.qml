// Looks bench - the dungeon's look shows its danger (issue #96).
//
// Builds the same dungeon, seed and depth, at a low, a middle and a high
// position in depth 3's range, stands the knight in the room after the
// first, where the floor carries the look, and saves each as
// <out>/low.png, middle.png and high.png. Each is checked against the
// table's look: its torches' colour and share, the floor's cracks and
// moss, what lies on the floor, the air and the light. Then, in the
// middle dungeon, it stands the knight at the exit stairs and makes up its
// record: none lost, and the stairs glow in the high look's torch colour
// (stairs-high.png); nearly all lost, in the low look's (stairs-low.png).
// Prints one PASS or FAIL line per check and exits with the number of
// failures. Offscreen only the HUD is saved: it needs a window, and the
// shaders copied beside the sources, as the knight bench does.
//
//   qml -I <build>/bin/qml tests/looks/looks.qml -- <out dir>

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
        console.log("[Looks]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Looks] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height,
                                                  muted: true,
                                                  recordStoreName: "ShapesAndStoneLooksBench"})
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

    function near(a, b) { return Math.abs(a - b) < 0.001 }
    function kindsOnFloor() {
        let n = {stains: 0, bones: 0, embers: 0}
        for (let o of game.dungeonObjects) {
            if (!o) continue
            if (o.kind === "bones") n.bones++
            else if (o.kind === "embers") n.embers++
            else if (String(o).startsWith("Stain")) n.stains++
        }
        return n
    }
    function floorOf() {
        for (let o of game.dungeonObjects)
            if (o && o.style === "stone") return o
        return null
    }
    function airOf() {
        let out = []
        for (let o of game.dungeonObjects)
            if (o && o.moteSize !== undefined) out.push(o)
        return out
    }

    // Down a dungeon at danger d: every enemy stands still, the knight in
    // the room after the first
    function enter(d) {
        game.applyScenario("dungeon", d)
        game.fx = true
        for (let e of game.enemies) if (e && e.halt) e.halt()
        let r = game.rooms[1]
        standAt((r.x + r.w / 2) * game.cellSize, (r.y + r.h / 2) * game.cellSize)
    }
    // The camera follows the knight's steps; one put somewhere it is
    // snapped to by setting it as its target anew
    function standAt(x, y) {
        game.player.xWu = x
        game.player.yWu = y
        game.camera.target = null
        game.camera.target = game.player
    }

    function checkLook(name, band) {
        let look = Balance.danger.looks[band]
        check(game.dangerBand(game.dangerPosition) === band,
              name + ": danger " + game.danger.toFixed(2) + " is in the " + name + " band")
        let colors = game.torches.map(t => String(t.flameColor))
        check(colors.length > 0 && colors.every(c => c.toUpperCase() === look.torch.toUpperCase()),
              name + ": " + colors.length + " torches burn " + look.torch)
        let f = floorOf()
        check(f && near(f.crackShare, look.crackShare) && near(f.moss, look.moss),
              name + ": the floor has " + look.crackShare + " of its stones cracked, moss " + look.moss)
        let n = kindsOnFloor(), rooms = game.rooms.length - 1
        check((look.stains > 0) === (n.stains > 0) && (look.bones > 0) === (n.bones > 0)
              && (look.embers > 0) === (n.embers > 0),
              name + ": on the floor of " + rooms + " rooms lie " + n.stains + " stains, "
              + n.bones + " bones, " + n.embers + " embers")
        let air = airOf()
        check(near(air[0].density, look.dust) && (air.length > 1) === (look.emberAir > 0),
              name + ": dust in the air at " + air[0].density + (air.length > 1 ? ", embers too" : ""))
        return colors.length
    }

    property var torchCounts: []

    property var steps: [
        [() => game.screen === "title", () => enter(3.1)],
        [1500, () => {
            torchCounts.push(checkLook("low", 0))
            capture("low")
        }],
        [() => saved, () => enter(3.5)],
        [1500, () => {
            torchCounts.push(checkLook("middle", 1))
            capture("middle")
        }],
        [() => saved, () => enter(3.9)],
        [1500, () => {
            torchCounts.push(checkLook("high", 2))
            check(torchCounts[1] < torchCounts[0],
                  "the middle dungeon burns fewer torches than the low one (" + torchCounts.join(", ") + ")")
            capture("high")
        }],
        // The exit stairs show where the next dungeon would stand
        [() => saved, () => {
            enter(3.5)
            let ex = game.exitStairs
            standAt(ex.xWu + ex.widthWu / 2, ex.yWu - ex.heightWu - 1.5)
            game.fightRecord.damageTaken = 0
        }],
        [1500, () => {
            let want = Balance.danger.looks[2].torch
            check(String(game.exitStairs.glow).toUpperCase() === want.toUpperCase(),
                  "with nothing lost the stairs glow " + game.exitStairs.glow + ", the high look's torch ("
                  + game.nextPosition.toFixed(2) + ")")
            capture("stairs-high")
        }],
        [() => saved, () => {
            game.fightRecord.damageTaken = Math.round(0.95 * Balance.knight.hp)
        }],
        [1500, () => {
            let want = Balance.danger.looks[0].torch
            check(String(game.exitStairs.glow).toUpperCase() === want.toUpperCase(),
                  "with 95% lost they glow " + game.exitStairs.glow + ", the low look's torch ("
                  + game.nextPosition.toFixed(2) + ")")
            capture("stairs-low")
        }],
        [() => saved, () => console.log("[Looks] done,", failures, "failed")],
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
                    console.log("[Looks] FAIL step", i, "timed out")
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
