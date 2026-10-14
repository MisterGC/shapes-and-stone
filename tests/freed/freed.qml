// Freed bench - the travellers freed in a run sit by the next camps' fire,
// and a special one joins the camps for good (issue #159).
//
// The game keeps its specials in a store of the bench's own, emptied at
// the start. On the first seed whose dungeon at depth 2 holds a lost
// traveller, the knight frees every traveller in it, every strike clean:
// those that left toward the exit sit round the fire of the camp after
// depth 2 and of the camp after depth 3 of that run, in colour, seated, on
// the camp's floor and clear of its travellers, while a miner at work
// stays in its room; a new run's first camp has none of them. Then in the
// dojo's deep scenario the knight frees the special: it says its own line,
// leaves, and joins the camps for good, kept in the store. Every camp of
// the next run has it by the fire, with its gold edge and its line to a
// knight near it, and the fire heals by its comfort, Balance.deep.specials'
// heal times faster. The fall screen and the title show the freed of
// tonight and the specials with the camps; with an out dir and a window
// it saves camp.png (the run's freed by the fire), special.png (the
// special by it), fallen.png and title.png. Prints one PASS or FAIL line per check and
// exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/freed/freed.qml
//   qml -I <build>/bin/qml tests/freed/freed.qml -- <out dir>

import QtQuick
import QtQuick.Window
import Clayground.Common
import Clayground.Storage
import "../../src"

Window {
    id: bench
    width: 1000
    height: 760
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0
    readonly property var sc: Balance.deep.stone
    readonly property real dt: 1 / 60
    readonly property var args: Qt.application.arguments
    readonly property string outDir: args.indexOf("--") >= 0 && args.indexOf("--") < args.length - 1
                                     ? args[args.length - 1] : ""

    // The same store the game keeps its record and specials in, under the
    // bench's name, so the player's own are not touched
    readonly property string storeName: "ShapesAndStoneFreedBench"
    KeyValueStore { id: store; name: bench.storeName }

    function check(ok, what) {
        console.log("[Freed]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        store.set("specials", "[]")
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Freed] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                  recordStoreName: storeName})
        script.start()
    }

    function find(root, name) {
        if (!root) return null
        if (root.objectName === name) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = find(kids[i], name)
            if (f) return f
        }
        return null
    }
    function shown(name) {
        let t = find(game, name)
        return t && t.visible ? t.text : ""
    }

    function haltAll() { for (let e of game.enemies) if (e && !e.destroyed && !e.halted) e.halt() }
    function step(n) {
        for (let i = 0; i < n; i++) {
            Clayground.physicsStep(1)
            haltAll()
        }
    }
    function seconds(s) { step(Math.round(s / dt)) }
    function stepTo(n) {
        let k = 0
        while (game.dig && game.dig.t < n * dt - 1e-6 && k++ < 4000) step(1)
    }
    // The knight stands in front of t and frees it, every strike clean
    function free(t) {
        let p = game.player
        game.endDig()
        p.xWu = t.faceXWu - p.widthWu / 2
        p.yWu = t.cyWu - t.sizeWu / 2 - 0.6 + p.heightWu / 2
        game.aimOverride = { x: t.faceXWu, y: t.faceYWu }
        step(1)
        if (!game.dig || game.dig.target !== t) return false
        let beat = Math.round(sc.ringTime / dt), n = 0
        while (!t.freed && n++ < 10) {
            stepTo((Math.floor(game.dig.t / sc.ringTime + 1e-6) + 1) * beat)
            game.pressPick()
        }
        game.aimOverride = null
        game.endDig()
        return t.freed
    }
    // On to level index, as the exit takes the party there
    function goTo(index) {
        game._enterLevel(index)
    }
    function camp() { return game.freedCamp }
    // The figures by this camp's fire: [{kind, special}], sorted
    function sitting() {
        return camp().figures.map(f => f.kind + (f.special ? ":" + f.special : "")).sort()
    }
    function fireCentre() {
        let cf = game.campfire
        return { x: cf.xWu + cf.widthWu / 2, y: cf.yWu - cf.heightWu / 2 }
    }
    // What is wrong with the figures of this camp: each seated, in colour,
    // on the floor, on the ring round the fire, clear of the travellers
    function sittingBroken() {
        let out = [], fc = fireCentre(), cfg = Balance.deep.camp
        for (let f of camp().figures) {
            if (!f.seated || !f.freed || f.colour !== 1 || f.gone) out.push(f.cell + " not seated in colour")
            if (Math.abs(Math.hypot(f.footXWu - fc.x, f.footYWu + 0.35 - fc.y) - cfg.ring) > 1e-3)
                out.push(f.cell + " off the ring")
            if (!game._campFloorAt(f.footXWu, f.footYWu + 0.35, 0.4)) out.push(f.cell + " off the floor")
            for (let t of game.campTravellers)
                if (Math.hypot(t.xWu + 0.4 - f.footXWu, t.yWu - 0.4 - f.footYWu - 0.35) < cfg.clear - 1e-3)
                    out.push(f.cell + " on a traveller")
        }
        return out
    }

    // The knight stands by the fire, south of it
    function nearFire() {
        let fc = fireCentre(), p = game.player
        p.xWu = fc.x - 0.5
        p.yWu = fc.y - 1.6
    }

    property var freedAt2: []
    property int seed2: -1
    property real healedAtBase: 0
    property bool saved: true
    function capture(name) {
        saved = outDir === ""
        if (saved) return
        bench.contentItem.grabToImage(r => {
            check(r.saveToFile(outDir + "/" + name + ".png"), "saved " + name + ".png")
            saved = true
        })
    }

    property var steps: [
        [() => game.screen === "title", () => {
            check(camp().joined.length === 0 && shown("titleFreed") === "" && shown("titleJoined") === "",
                  "a fresh store: no specials with the camps, the title shows no freed and no specials")
        }],
        [50, () => {
            // A dungeon at depth 2 with a lost traveller
            Clayground.paused = true
            for (let i = 0; i < 60 && seed2 < 0; i++) {
                let seed = 5000 + i * 7919
                game.applyScenario("dungeon", 2, seed)
                if (game.stones.some(s => s.kind === "lost" && s.special === "")) seed2 = seed
            }
            check(seed2 >= 0 && game.depth === 2, "seed " + seed2 + " has a lost traveller at depth 2 ("
                  + game.stones.map(s => s.kind + (s.special ? ":" + s.special : "")).join(", ") + ")")
            game.player.hp = 100000
            step(1)
            let all = game.stones.slice(), ok = true
            for (let s of all) ok = free(s) && ok
            seconds(sc.colourTime + 0.2)
            freedAt2 = all.filter(s => s.outcome === "leaving" || s.outcome === "fleeing")
                          .map(s => s.kind + (s.special ? ":" + s.special : "")).sort()
            let working = all.filter(s => s.outcome === "working").length
            check(ok && all.every(s => s.freed && s.outcome !== ""),
                  "the knight frees all " + all.length + " travellers of the dungeon: "
                  + all.map(s => s.kind + " " + s.outcome).join(", "))
            check(camp().run.length === all.length && freedAt2.length > 0,
                  "the run keeps them (" + camp().run.length + "), " + freedAt2.length + " left toward the exit, "
                  + working + " at work in their rooms")
            seconds(sc.say + sc.fadeAfter + sc.fade + 1)
            Clayground.paused = false
            goTo(game.levelIndexOf(2, "village"))
        }],
        [() => game.levelType === "village" && game.campfire !== null && game.player !== null, () => {
            let want = freedAt2.filter(k => k.indexOf(":") < 0)
            check(game.depth === 2 && JSON.stringify(sitting()) === JSON.stringify(want),
                  "the camp after depth 2: the " + want.length + " that left sit by the fire (" + sitting().join(", ")
                  + "), no miner at work among them")
            let broken = sittingBroken()
            check(broken.length === 0, "each seated in colour on the ring round the fire, on the floor, clear of the "
                  + game.campTravellers.length + " travellers" + (broken.length ? ": " + broken.join("; ") : ""))
            goTo(game.levelIndexOf(3, "dungeon"))
        }],
        [() => game.levelType === "dungeon" && game.player !== null, () => {
            goTo(game.levelIndexOf(3, "village"))
        }],
        [() => game.levelType === "village" && game.campfire !== null && game.player !== null, () => {
            let want = freedAt2.filter(k => k.indexOf(":") < 0)
            check(game.depth === 3 && JSON.stringify(sitting()) === JSON.stringify(want) && sittingBroken().length === 0,
                  "the camp after depth 3 of the same run: the same " + want.length + " by its fire ("
                  + sitting().join(", ") + ")")
            nearFire()
        }],
        [800, () => { capture("camp") }],
        [() => saved, () => { game.newRun() }],
        [() => game.levelType === "dungeon" && game.player !== null && game.depth === 0, () => {
            check(camp().run.length === 0, "a new run has freed none yet (" + camp().run.length + ")")
            goTo(game.levelIndexOf(0, "village"))
        }],
        [() => game.levelType === "village" && game.campfire !== null && game.player !== null, () => {
            check(sitting().length === 0 && camp().figures.length === 0,
                  "the new run's first camp: the last run's freed are gone (" + sitting().length + " by the fire)")
            check(Math.abs(game.campfire.healRate - Balance.campfire.healPerSecond) < 1e-6,
                  "with no special the fire heals as it always did: " + game.campfire.healRate + " HP/s")
            // The fire's healing without a special, for a second
            let p = game.player
            p.xWu = game.campfire.xWu + 0.5
            p.yWu = game.campfire.yWu
            p.hp = 10
        }],
        [1000, () => {
            healedAtBase = game.player.hp - 10
            // The special in the deep room
            Clayground.paused = true
            game.applyScenario("deep", 3)
            game.player.hp = 100000
            step(1)
            let sp = game.stones.find(s => s.special !== "")
            let table = sp ? camp().specialOf(sp.special) : null
            check(sp && table && sp.special === Balance.deep.specials[0].id && sp.kind === table.kind
                  && sp.shimmerColor.toString() === Qt.color(Balance.deep.specialEdge).toString(),
                  "the deep room holds the first special not yet with the camps, " + (table ? table.name : "none")
                  + ", its edge gold")
            check(free(sp), "the knight frees it, every strike clean")
            seconds(sc.colourTime + 0.2)
            check(sp.outcome === "leaving" && sp.saying === table.line,
                  "it says its own line and leaves: " + sp.outcome + ", \"" + sp.saying + "\"")
            let kept = []
            try { kept = JSON.parse(store.get("specials", "[]")) } catch (err) {}
            check(camp().joined.join() === table.id && kept.join() === table.id,
                  "it joins the camps for good, kept with the record: " + kept.join())
            seconds(sc.say + sc.fadeAfter + sc.fade + 1)
            check(sp.gone, "it walks off toward the exit and is gone")
            Clayground.paused = false
            game.newRun()
        }],
        [() => game.levelType === "dungeon" && game.player !== null && game.depth === 0, () => {
            goTo(game.levelIndexOf(0, "village"))
        }],
        [() => game.levelType === "village" && game.campfire !== null && game.player !== null, () => {
            let sp = Balance.deep.specials[0]
            let f = camp().figures.find(x => x.special === sp.id)
            check(sitting().join() === sp.kind + ":" + sp.id && f && sittingBroken().length === 0,
                  "the next run's first camp: " + sp.name + " by the fire (" + sitting().join(", ") + ")")
            check(Math.abs(game.campfire.healRate - Balance.campfire.healPerSecond * sp.heal) < 1e-6,
                  "the fire heals " + sp.heal + " times faster with " + sp.name + ": " + game.campfire.healRate
                  + " HP/s (Balance.deep.specials)")
            let p = game.player
            p.xWu = f.footXWu - 0.5
            p.yWu = f.footYWu + 0.35 + 0.5
        }],
        [400, () => {
            let sp = Balance.deep.specials[0]
            let f = camp().figures.find(x => x.special === sp.id)
            check(f.saying === sp.campLine, "a knight near " + sp.name + " hears its line: \"" + f.saying + "\"")
            let p = game.player
            p.xWu = game.campfire.xWu + 0.5
            p.yWu = game.campfire.yWu
            p.hp = 10
        }],
        [1000, () => {
            let healed = game.player.hp - 10, sp = Balance.deep.specials[0]
            check(healedAtBase > 0 && healed >= healedAtBase * sp.heal * 0.75,
                  "by the fire a knight heals " + healed + " HP in a second, without a special " + healedAtBase)
            goTo(game.levelIndexOf(1, "dungeon"))
        }],
        [() => game.levelType === "dungeon" && game.player !== null, () => {
            goTo(game.levelIndexOf(1, "village"))
        }],
        [() => game.levelType === "village" && game.campfire !== null && game.player !== null, () => {
            let sp = Balance.deep.specials[0]
            check(sitting().join() === sp.kind + ":" + sp.id
                  && Math.abs(game.campfire.healRate - Balance.campfire.healPerSecond * sp.heal) < 1e-6,
                  "the next run's second camp has " + sp.name + " too (" + sitting().join(", ") + ")")
            nearFire()
        }],
        [800, () => { capture("special") }],
        [() => saved, () => {
            let p = game.player
            p.isBlocking = false
            p.takeDamage(10 * p.maxHp, p.xWu + 1, p.yWu)
        }],
        [() => find(game, "fallenScreen") && find(game, "fallenScreen").visible, () => {
            let sp = Balance.deep.specials[0]
            let freed = shown("fallenFreed"), joined = shown("fallenJoined")
            check(freed === camp().tonightLine && freed.indexOf("Freed tonight: ") === 0
                  && freed.indexOf(sp.name) > 0 && (freed.indexOf("lost traveller") > 0),
                  "the fall screen shows the freed of tonight: \"" + freed + "\"")
            check(joined === "With the camps: " + sp.name + " " + sp.title,
                  "and the specials with the camps: \"" + joined + "\"")
        }],
        [1200, () => { capture("fallen") }],
        [() => saved, () => { game.backToTitle() }],
        [() => game.screen === "title" && find(game, "titleFreed") !== null, () => {
            let sp = Balance.deep.specials[0]
            check(shown("titleFreed") === camp().tonightLine && shown("titleFreed") !== ""
                  && shown("titleJoined") === "With the camps: " + sp.name + " " + sp.title,
                  "the title shows them too: \"" + shown("titleFreed") + "\" / \"" + shown("titleJoined") + "\"")
        }],
        [1500, () => { capture("title") }],
        [() => saved, () => {
            console.log("[Freed] done,", failures, "failed")
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
            let s = bench.steps[i]
            waitedMs += interval
            let ready = typeof s[0] === "number" ? waitedMs >= s[0] : s[0]()
            if (!ready) {
                if (waitedMs > 30000) {
                    console.log("[Freed] FAIL step", i, "timed out")
                    Qt.exit(failures + 1)
                    stop()
                }
                return
            }
            waitedMs = 0
            i++
            if (i >= bench.steps.length) stop()
            s[1]()
        }
    }
}
