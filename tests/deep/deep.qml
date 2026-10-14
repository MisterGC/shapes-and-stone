// Deep bench - a vein in the dojo: the sword turns into a pickaxe and
// strikes in rhythm cut a gem out of the stone (issue #155).
//
// applyScenario("deep") lands the knight in reach of a vein, its gem a
// tetrahedron at depth 0 and each shape of Balance.deep.shapes at its
// depth. The mouse aiming at the vein starts the dig (issue #169): the
// pickaxe shows once the sword has folded into it. Then, the game paused
// (Clayground.paused) and single-stepped (Clayground.physicsStep): the
// left button aimed at the vein on a close of the ring, and up to window
// seconds before or after it, strikes clean, with the chink and a tink a
// pentatonic step higher each; a click a step outside the window, or a
// second one on the same close, chips, with the chink alone. The window counts the
// physics steps: a strike held a while on the wall clock between two
// steps is judged by the steps alone. The vein's last strike splits it,
// and the gem's size follows its clean strikes, 0 to all of them. Raising
// the shield or walking off ends the dig, and the pickaxe folds back into
// the sword; a swing or a dash ends it too, and aimed at the vein
// mid-swing none begins. E at the vein starts no dig and strikes nothing,
// the mouse moving off the vein ends the dig, and the left button aimed
// away from it swings the sword. A gem cut with every strike clean is won
// as a clean cut, one cut with none notched: it holds wonAbove above the
// knight, grown, and drops into the pouch, where the HUD counts it and
// its count bumps. The vein sits in a rough rock face rockCells cells to
// each side of it.
// Prints one PASS or FAIL line per check and exits with the
// number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/deep/deep.qml

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Common
import "../../src"

Window {
    id: bench
    width: 1000
    height: 760
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0
    readonly property var cfg: Balance.deep
    // The ring's beat and its window in physics steps
    readonly property real dt: 1 / 60
    readonly property int beat: Math.round(cfg.ringTime / dt)
    readonly property int win: Math.floor(cfg.window / dt + 1e-6)

    function check(ok, what) {
        console.log("[Deep]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function pressE() { keys.keyClick(Qt.Key_E, Qt.NoModifier, -1) }
    // The vein's face on the game's screen, where the mouse aims at it
    function veinPoint() {
        let v = vein()
        return v.mapToItem(game, v.width / 2, v.height * (1 - v.faceWu / v.sizeWu / 2))
    }
    // The mouse moves onto the vein, and the left button clicks there
    function aimVein() {
        let p = veinPoint()
        keys.mouseMove(game, p.x, p.y, -1, Qt.NoButton, Qt.NoModifier)
    }
    function strike() {
        let p = veinPoint()
        keys.mouseClick(game, p.x, p.y, Qt.LeftButton, Qt.NoModifier, -1)
    }
    // A point on the floor three knights south of the knight
    function awayPoint() {
        let p = game.player
        return p.mapToItem(game, p.width / 2, p.height * 3.5)
    }
    function aimAway() {
        let p = awayPoint()
        keys.mouseMove(game, p.x, p.y, -1, Qt.NoButton, Qt.NoModifier)
    }
    function clickAway() {
        let p = awayPoint()
        keys.mouseClick(game, p.x, p.y, Qt.LeftButton, Qt.NoModifier, -1)
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
    property int bumpsBefore: 0

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Deep] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true})
        script.start()
    }

    function knight() { return game._knightCentre() }
    function vein() { return game.veins[0] }
    function faceDistance() {
        let k = knight(), v = vein()
        return Math.hypot(v.faceXWu - k.x, v.faceYWu - k.y)
    }
    function pickaxeItem() {
        let kids = game.player.parent.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i].objectName === "pickaxe") return kids[i]
        return null
    }
    function step(n) { for (let i = 0; i < n; i++) Clayground.physicsStep(1) }
    // Steps until the dig has run n steps since its E
    function stepTo(n) {
        let k = 0
        while (game.dig && game.dig.t < n * dt - 1e-6 && k++ < 2000) Clayground.physicsStep(1)
    }
    // A fresh deep room, the mouse on the vein and the dig begun on a
    // step, paused
    function freshDig() {
        Clayground.paused = true
        game.applyScenario("deep")
        game.forceActiveFocus()
        aimVein()
        step(1)
    }
    // Cuts the vein with clean strikes on the first closes, then chips
    // half way through the next beats; the gem it gives
    function cut(clean) {
        freshDig()
        let v = vein(), at = 0
        for (let i = 0; i < v.strikes; i++) {
            at += beat
            stepTo(i < clean ? at : at - Math.round(beat / 2))
            strike()
        }
        return game.lastGem
    }
    // The vein sounds heard since n of them had played
    function heardSince(n) {
        let k = game.veinSoundCount - n
        return k > 0 ? game.veinSounds.slice(-k) : []
    }

    property var steps: [
        [() => game.screen === "title", () => {
            game.applyScenario("deep")
            game.forceActiveFocus()
        }],
        [300, () => {
            let v = vein()
            check(game.veins.length === 1 && game.player && faceDistance() <= cfg.reach,
                  "applyScenario(\"deep\") lands the knight " + faceDistance().toFixed(2)
                  + " wu from the vein's face, within reach " + cfg.reach)
            check(v.shape === "tetrahedron" && Qt.colorEqual(v.gemColor, cfg.shapes[0].color),
                  "at depth 0 the vein holds a " + v.shape)
            check(v.strikes >= cfg.strikes[0] && v.strikes <= cfg.strikes[1],
                  "the vein takes " + v.strikes + " strikes, " + cfg.strikes[0] + " to " + cfg.strikes[1])
            check(!game.player.digging && pickaxeItem() && !pickaxeItem().visible,
                  "before the mouse aims at the vein the knight holds no pickaxe")
            Clayground.paused = true
            aimVein()
            step(1)
            check(game.player.digging && game.dig && game.dig.vein === v,
                  "the mouse aiming at the vein starts the dig")
            step(Math.ceil(cfg.morph / dt) + 1)
            check(game.player.pickMorph === 1 && pickaxeItem().visible && v.ringShows,
                  "after " + cfg.morph + " s of steps the sword has turned into the pickaxe ("
                  + game.player.pickMorph + ") and the ring closes on the vein")
            let shown = []
            for (let i = 0; i < cfg.shapes.length; i++) {
                game.applyScenario("deep", cfg.shapes[i].from)
                shown.push(vein().shape)
            }
            check(shown.join() === cfg.shapes.map(s => s.shape).join(),
                  "the scenario shows each shape at its depth: " + shown.join(", "))
        }],
        // Clean on the close, early and late within the window; a chip a
        // step outside it and on a close already taken
        [100, () => {
            freshDig()
            let v = vein()
            stepTo(beat)
            let n = game.veinSoundCount
            strike()
            let s1 = game.lastStrike
            check(s1.clean && v.clean === 1 && Math.abs(s1.off) < 1e-6,
                  "a click on the close strikes clean (" + s1.off.toFixed(3) + " s off)")
            check(heardSince(n).join() === "chink,tink+" + cfg.phrase[0],
                  "a clean strike plays the chink and the tink: " + heardSince(n).join())
            stepTo(beat + 2)
            n = game.veinSoundCount
            strike()
            check(!game.lastStrike.clean && v.chips === 1,
                  "a second click on the same close chips")
            check(heardSince(n).join() === "chink" + cfg.chipPitch,
                  "a chip plays the chink alone: " + heardSince(n).join())
            stepTo(2 * beat - win)
            n = game.veinSoundCount
            strike()
            check(game.lastStrike.clean && v.clean === 2,
                  "a click " + win + " steps (" + (win * dt).toFixed(3) + " s) before a close strikes clean")
            check(heardSince(n).slice(0, 2).join() === "chink,tink+" + cfg.phrase[1],
                  "the second clean strike's tink is a pentatonic step higher: " + heardSince(n).join())
        }],
        [100, () => {
            freshDig()
            let v = vein()
            stepTo(beat + win)
            strike()
            check(game.lastStrike.clean, "a click " + win + " steps after a close strikes clean")
            stepTo(2 * beat + win + 1)
            strike()
            check(!game.lastStrike.clean,
                  "a click " + (win + 1) + " steps after a close chips")
            freshDig()
            stepTo(beat - win - 1)
            strike()
            check(!game.lastStrike.clean,
                  "a click " + (win + 1) + " steps before a close chips")
        }],
        // The window counts physics time: held between two steps on the
        // wall clock longer than a beat, a strike is judged by the steps
        [100, () => {
            freshDig()
            stepTo(beat - 2)
        }],
        [Math.round(cfg.ringTime * 1500), () => {
            strike()
            check(game.lastStrike.clean && Math.abs(game.dig.t - (beat - 2) * dt) < 1e-6,
                  "2 steps before the close and " + Math.round(cfg.ringTime * 1500)
                  + " ms of wall clock later, still 2 steps before it: clean")
            stepTo(2 * beat - Math.round(beat / 2))
        }],
        [Math.round(cfg.ringTime * 500), () => {
            strike()
            check(!game.lastStrike.clean,
                  "half a beat before a close and half a beat of wall clock later: a chip")
        }],
        // The gem's size follows the clean strikes
        [100, () => {
            freshDig()
            let sizes = [], strikes = vein().strikes
            for (let c = 0; c <= strikes; c++) {
                let g = cut(c)
                check(g && g.clean === c && g.strikes === strikes && vein().split
                      && Math.abs(g.sizeWu - game.gemSize(c, strikes)) < 1e-9,
                      "cut with " + c + " of " + strikes + " strikes clean: the stone splits and a "
                      + (g ? g.shape + " of " + g.sizeWu.toFixed(3) + " wu" : "no gem") + " pops out")
                sizes.push(g ? g.sizeWu : 0)
            }
            check(sizes.length === strikes + 1 && sizes.every((s, i) => i === 0 || s > sizes[i - 1])
                  && Math.abs(sizes[0] - cfg.gemSize[0]) < 1e-9
                  && Math.abs(sizes[sizes.length - 1] - cfg.gemSize[1]) < 1e-9,
                  "the gem's size grows with each clean strike: " + sizes.map(s => s.toFixed(3)).join(" < "))
            let heard = game.veinSounds.slice(-3)
            check(heard[0] === "tink+" + cfg.phrase[strikes - 1] && heard[1] === "crumble"
                  && heard[2] === "tink+" + cfg.chime[0],
                  "the split crumbles and the chime begins: " + heard.join())
        }],
        // The dig ends with the shield, walking off, a swing or a dash
        [1500, () => {
            check(game.veinSounds.slice(-cfg.chime.length).join()
                  === cfg.chime.map(p => "tink+" + p).join(),
                  "the chime plays its " + cfg.chime.length + " notes: " + game.veinSounds.slice(-3).join())
            freshDig()
            step(Math.ceil(cfg.morph / dt) + 1)
            game.player.raiseShield()
            step(1)
            check(!game.player.digging && !game.dig, "raising the shield ends the dig")
            step(Math.ceil(cfg.morph / dt) + 1)
            game.player.lowerShield()
            check(game.player.pickMorph === 0 && !pickaxeItem().visible,
                  "and the pickaxe has folded back into the sword")
            freshDig()
            step(2)
            game.player.xWu -= cfg.leave + 0.5
            step(1)
            check(!game.player.digging && !game.dig, "walking off ends the dig")
            freshDig()
            step(2)
            game.player.attack()
            step(1)
            check(game.player.isAttacking && !game.player.digging && !game.dig, "a swing ends the dig")
            step(1)
            check(!game.player.digging && !game.dig, "aimed at the vein mid-swing, no dig begins")
            freshDig()
            step(2)
            game.player.dash()
            step(1)
            check(game.player.isDashing && !game.player.digging && !game.dig, "a dash ends the dig")
        }],
        // E at a vein starts nothing and strikes nothing; the left button
        // aimed away from it swings the sword (issue #169)
        [100, () => {
            Clayground.paused = true
            game.applyScenario("deep")
            game.forceActiveFocus()
            aimAway()
            step(1)
            pressE()
            step(1)
            check(!game.dig && !game.player.digging && vein().struck === 0,
                  "E at the vein, the mouse aimed away from it, starts no dig")
            aimVein()
            step(1)
            stepTo(beat)
            pressE()
            check(game.dig && vein().struck === 0, "E while the dig runs strikes nothing (struck " + vein().struck + ")")
            strike()
            check(game.lastStrike.clean && vein().struck === 1 && !game.player.isAttacking,
                  "the left button aimed at the vein on the close strikes clean with the pickaxe, the sword does not swing")
            aimAway()
            step(1)
            check(!game.dig && !game.player.digging, "the mouse moving off the vein ends the dig")
            clickAway()
            step(1)
            check(game.player.isAttacking && !game.dig && vein().struck === 1,
                  "the left button aimed away from the vein swings the sword")
        }],
        // The gem won: clean, held above the knight, then into the pouch
        [100, () => {
            bumpsBefore = game.pouchBumps
            let g = cut(99)
            let w = game.wonGems[0], h = find(game, "hudPouch")
            check(game.wonGems.length === 1 && w.clean && w.notches === 0 && g.chips === 0
                  && game.player.pouch.length === 1 && h.summary === "",
                  "a gem cut with every strike clean is won as a clean cut, in the pouch but not yet on the HUD ("
                  + (h.summary || "nothing") + ")")
        }],
        [() => game.wonGems.length > 0 && game.wonGems[0].phase === "hold", () => {
            let w = game.wonGems[0], k = knight()
            let across = w.width * w.scale / game.pixelPerUnit
            check(Math.abs(w.atX - k.x) < 1e-6 && Math.abs(w.atY - (k.y + cfg.wonAbove)) < 1e-6
                  && Math.abs(w.grow - 1) < 1e-6 && across >= Math.max(cfg.wonMin, w.sizeWu * cfg.wonScale) - 1e-6,
                  "it holds " + cfg.wonAbove + " wu above the knight, " + across.toFixed(2) + " wu across, "
                  + cfg.wonScale + " times its " + w.sizeWu.toFixed(2) + " wu")
        }],
        [() => game.wonGems.length === 0, () => {
            let h = find(game, "hudPouch")
            check(game.pouchBumps === bumpsBefore + 1 && game._bumpShape === "tetrahedron"
                  && h.summary === "tetrahedron 1",
                  "it drops into the pouch: the HUD counts it (" + h.summary + ") and its count bumps")
            let g = cut(0)
            let w = game.wonGems[0]
            check(w && !w.clean && w.notches === Math.min(3, g.chips) && w.notches > 0,
                  "a gem cut with no strike clean is won chipped, " + (w ? w.notches : 0) + " notches broken out of it")
        }],
        // The vein's rough rock face
        [() => game.wonGems.length === 0, () => {
            game.applyScenario("deep")
            let v = vein(), f = game.rockFaces, cs = game.cellSize
            let c = v.cell.split(",").map(Number)
            check(f.length === 1 && f[0].faceStyle === "rock"
                  && f[0].xWu <= (c[0] - cfg.rockCells) * cs + 1e-6
                  && f[0].xWu + f[0].widthWu >= (c[0] + 1 + cfg.rockCells) * cs - 1e-6
                  && Math.abs(f[0].yWu - (c[1] * cs + game.wallFaceWu)) < 1e-6,
                  "the deep room's vein sits in a rough rock face, " + cfg.rockCells + " cell(s) to each side of it ("
                  + (f[0] ? f[0].xWu.toFixed(2) + " to " + (f[0].xWu + f[0].widthWu).toFixed(2) + " wu" : "none") + ")")
            Clayground.paused = false
            console.log("[Deep] done,", failures, "failed")
            game.destroy()
        }],
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
                    console.log("[Deep] FAIL step", i, "timed out")
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
