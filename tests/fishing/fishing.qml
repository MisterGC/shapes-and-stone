// Fishing bench - the camp's pond can be fished, the fish sold to the
// innkeeper or one given to the cave cat (Balance.fishing).
//
// On the scenario seed's grotto camp, the game paused so only the bench
// steps the fishing: the knight at the pond's edge aiming at the water
// may cast, aiming off it or standing far off it may not; a cast flies
// for a moment and lands within castMax on the water; a click before the
// bite reels in empty and spends no bite; a bite not clicked gets away and
// spends one; a bite clicked hooks the fish, and the button held reels it
// in to the creel; held through a thrash the line snaps, let go the fish
// pulls back out and the line slackens; walking off ends it; with no bites
// left the water is still. The innkeeper buys the creel for the kinds'
// gold, the cat takes the smallest fish from a knight beside it and eats
// it, and a new level fills the pond's bites again. Prints one PASS or
// FAIL line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/fishing/fishing.qml

import QtQuick
import QtQuick.Window
import Clayground.Common
import "../../src"

Window {
    id: bench
    width: 1000
    height: 700
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0
    readonly property var cfg: Balance.fishing
    readonly property real stepS: 1 / 60

    function check(ok, what) {
        console.log("[Fishing]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Fishing] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                  recordStoreName: "ShapesAndStoneFishingBench"})
        script.start()
    }

    property var f: null
    property var pond: null
    function run(seconds) {
        let n = Math.round(seconds / stepS)
        for (let i = 0; i < n; i++) f.step(stepS)
    }
    // The knight's centre to (x, y)
    function place(x, y) {
        let p = game.player
        p.xWu = x - p.widthWu / 2
        p.yWu = y + p.heightWu / 2
    }
    function cast() {
        f._end()
        run(stepS)
        let ok = f.press()
        run(0.4)
        return ok
    }
    // A bite on the line now
    function bite() {
        cast()
        f._waitFor = f._phaseT + 0.05
        f._nibbleAt = []
        run(0.1)
    }

    readonly property var steps: [
        [() => true, () => game.applyScenario("village")],
        [() => game.player && game.levelType === "village", () => {
            Clayground.paused = true
            f = fishingOf(game)
            let ponds = game.campProps.filter(p => p.kind === "pond")
            check(f !== null && ponds.length === 1, "the camp has its fishing and one pond (" + ponds.length + ")")
            pond = ponds[0]
            // On the pond's south bank, a step off the water's edge
            let ry = pond.h * 0.4
            place(pond.x, pond.y - ry - 0.8)
            game.aimOverride = { x: pond.x + 0.5, y: pond.y + 0.3 }
            run(stepS)
            check(f.aim !== null && f.bitesLeft === cfg.bites,
                  "at the bank, aiming at the water, it may cast (" + (f.aim !== null) + ", "
                  + f.bitesLeft + " bites)")
            game.aimOverride = { x: pond.x, y: pond.y - ry - 2.5 }
            run(stepS)
            check(f.aim === null, "aiming at the ground it may not")
            place(pond.x, pond.y - ry - 4)
            game.aimOverride = { x: pond.x, y: pond.y }
            run(stepS)
            check(f.aim === null, "standing " + 4 + " wu off the water it may not")
            place(pond.x, pond.y - ry - 0.8)
            game.aimOverride = { x: pond.x + 0.5, y: pond.y + 0.3 }

            // The cast
            run(stepS)
            let took = f.press()
            let flying = f.phase === "cast"
            run(0.4)
            let c = { x: game.player.xWu + game.player.widthWu / 2, y: game.player.yWu - game.player.heightWu / 2 }
            let d = Math.hypot(f.bx - c.x, f.by - c.y)
            check(took && flying && f.phase === "wait" && d <= cfg.castMax + 1e-6
                  && f._inside(f.pond, f.bx, f.by, 1),
                  "the button casts: it flies, then waits on the water " + d.toFixed(2) + " wu off ("
                  + f.phase + ")")

            // Too soon
            f.press()
            check(f.phase === "" && f.bitesLeft === cfg.bites,
                  "a click before the bite reels in empty and spends no bite (" + f.bitesLeft + ")")

            // A bite missed
            bite()
            let biting = f.phase === "bite"
            run(cfg.biteWindow + 0.05)
            check(biting && f.phase === "" && f.bitesLeft === cfg.bites - 1,
                  "a bite not clicked within " + cfg.biteWindow + " s gets away and spends a bite ("
                  + f.bitesLeft + " left)")

            // A bite hooked and reeled in
            bite()
            f.press()
            let hooked = f.phase === "reel" && f.fish !== null
            f.fish = { kind: 1, size: 20 }
            f._thrashIn = 99
            let before = game.player.creel.length
            run(f._len / cfg.reelSpeed + 0.2)
            check(hooked && (f.phase === "landed" || f.phase === "") && game.player.creel.length === before + 1
                  && game.player.creel[before].kind === 1,
                  "clicked on the bite it hooks, and held it reels the fish into the creel ("
                  + JSON.stringify(game.player.creel) + ")")
            run(1)

            // Held through a thrash, the line snaps
            bite()
            f.press()
            f._thrashIn = 0
            f._thrashLeft = 5
            before = game.player.creel.length
            run(1 / cfg.tensionRise + 0.1)
            check(f.phase === "" && game.player.creel.length === before,
                  "held through a thrash the line snaps in " + (1 / cfg.tensionRise).toFixed(2) + " s")

            // Let go, the fish pulls back and the tension falls
            bite()
            f.press()
            f.progress = 0.5
            f.tension = 0.5
            f._thrashIn = 0
            f._thrashLeft = 5
            f.release()
            run(0.5)
            check(f.phase === "reel" && f.progress < 0.5 && f.tension === 0.5,
                  "let go through a thrash the fish pulls back (" + f.progress.toFixed(3)
                  + ") and the line holds (" + f.tension.toFixed(2) + ")")
            f._thrashLeft = 0.01
            f._thrashIn = 0
            run(0.5)
            check(f.tension < 0.5, "the thrash over, the tension falls (" + f.tension.toFixed(2) + ")")

            // Walking off ends it
            place(pond.x + cfg.leave + 0.5, pond.y - ry - 0.8)
            run(stepS)
            check(f.phase === "", "walking off the line comes in")
            place(pond.x, pond.y - ry - 0.8)

            // No bites left
            f.bitesLeft = 0
            run(stepS)
            let took2 = f.press()
            check(took2 && f.phase === "", "with no bites left the button casts nothing")

            // The innkeeper buys the creel
            game.player.creel = [{ kind: 0, size: 8 }, { kind: 2, size: 30 }, { kind: 4, size: 20 }]
            let price = cfg.kinds[0].gold + cfg.kinds[2].gold + cfg.kinds[4].gold
            let gold = game.player.gold
            let offer = game.fishWare()
            let sold = game.buyWare({ id: "fish" })
            check(offer && offer.price === price && sold && game.player.gold === gold + price
                  && game.player.creel.length === 0,
                  "the innkeeper buys the creel for " + price + " gold (offered "
                  + (offer ? offer.price : "none") + ", gold " + gold + " -> " + game.player.gold + ")")
            check(game.fishWare() === null, "with the creel empty he offers nothing for it")

            // The cat
            let cat = game.campCat
            if (cat) {
                game.player.creel = [{ kind: 2, size: 40 }, { kind: 0, size: 7 }]
                place(cat.xWu + 8, cat.yWu)
                let far = game.feedCat()
                place(cat.xWu, cat.yWu - 1.2)
                let fed = game.feedCat()
                check(!far && fed && game.player.creel.length === 1 && game.player.creel[0].size === 40,
                      "the cat takes the smallest fish from a knight beside it, none from afar ("
                      + JSON.stringify(game.player.creel) + ")")
                eatenCat = cat
            } else {
                check(false, "the scenario camp has a cat")
            }
        }],
        [400, () => {
            check(eatenCat && eatenCat.eat > 0, "the cat eats it (" + (eatenCat ? eatenCat.eat.toFixed(2) : "-") + ")")
            Clayground.paused = false
            game.aimOverride = null
            f.bitesLeft = 0
            game.applyScenario("village")
        }],
        [() => game.player && game.levelType === "village", () => {
            check(fishingOf(game).bitesLeft === cfg.bites && fishingOf(game).phase === "",
                  "a new level fills the pond's bites again (" + fishingOf(game).bitesLeft + ")")
        }],
        [300, () => game.destroy()],
        [300, () => {
            console.log("[Fishing] done,", failures, "failed")
            Qt.exit(failures)
        }]
    ]
    property var eatenCat: null
    function fishingOf(g) {
        let items = g.room ? g.room.children : []
        for (let i = 0; i < items.length; i++) if (items[i].objectName === "fishing") return items[i]
        return null
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
                if (waitedMs > 30000) {
                    console.log("[Fishing] FAIL step", i, "timed out")
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
