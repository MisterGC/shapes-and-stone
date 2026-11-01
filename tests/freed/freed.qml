// Freed bench - the travellers sent off in a run sit by the next camp's
// fire only, and a special one joins the camps for good and sits by every
// camp's fire (issue #159, #176, #177).
//
// The game keeps its specials in a store of the bench's own, emptied at
// the start. A level's special comes from its seed alone: the same seed
// holds the same travellers of the same kinds with an empty and a full
// record, the special an ordinary traveller once it is with the camps.
// On the first seed whose dungeon at depth 2 holds a lost
// traveller, the knight talks to every traveller in it, and each leaves:
// they sit round the fire of the camp after depth 2, seated, on the camp's
// floor and clear of its travellers, and not by the fire of the camp after
// depth 3 of that run; a new run's first camp has none of them. Then in the dojo's
// deep scenario the knight talks to the special: it says its own line,
// leaves, and joins the camps for good, kept in the store. Every camp of
// the next run has it by the fire, with its gold edge and its line to a
// knight near it, and the fire heals by its comfort, Balance.deep.specials'
// heal times faster. In that run the knight sends the travellers of the
// same dungeon at depth 2 off again: the camp after depth 2 has them and
// the special, the camp after depth 3 the special alone. The fall screen and the title show the freed of
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
    readonly property var tc: Balance.deep.traveller
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
    // The knight stands just below traveller t of the deep and talks to
    // it, as E there does: whether it leaves
    function talkTo(t) {
        let p = game.player
        game.endDig()
        p.xWu = t.midXWu - p.widthWu / 2
        p.yWu = t.footYWu - 0.3 + p.heightWu / 2
        step(1)
        return game.talkToDeepTraveller() && t.outcome === "leaving"
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
    // What is wrong with the figures of this camp: each seated, on the
    // floor, on the ring round the fire, clear of the travellers
    function sittingBroken() {
        let out = [], fc = fireCentre(), cfg = Balance.deep.camp
        for (let f of camp().figures) {
            if (!f.seated || f.gone) out.push(f.cell + " not seated")
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
            // A level's special comes from its seed alone: the same seed
            // holds the same traveller of the same kind with an empty and
            // a full record, a special only while it is not with the camps
            let line = () => game.deepTravellers.map(s => s.cell + ":" + s.kind).sort().join()
            let found = null
            for (let i = 0; i < 120 && !found; i++) {
                let seed = 9000 + i * 7919
                game.applyScenario("dungeon", 2, seed)
                let sp = game.deepTravellers.find(s => s.special !== "")
                if (sp) found = { seed: seed, cell: sp.cell, kind: sp.kind, special: sp.special, all: line() }
            }
            check(found !== null, "seed " + (found ? found.seed : "none") + " holds a special at depth 2: "
                  + (found ? found.special + " (" + found.kind + ") on " + found.cell : "none"))
            if (!found) return
            camp().joined = Balance.deep.specials.map(sp => sp.id)
            game.applyScenario("dungeon", 2, found.seed)
            let again = game.deepTravellers.find(s => s.cell === found.cell)
            check(line() === found.all && again && again.kind === found.kind && again.special === "",
                  "with every special in the record the same seed holds the same travellers ("
                  + line() + "), " + found.cell + " an ordinary " + (again ? again.kind : "none"))
            camp().joined = []
            game.applyScenario("dungeon", 2, found.seed)
            again = game.deepTravellers.find(s => s.cell === found.cell)
            check(again && again.special === found.special, "with the record empty again it is " + found.special
                  + " again (" + (again ? again.special : "none") + ")")
        }],
        [50, () => {
            // A dungeon at depth 2 with a lost traveller
            Clayground.paused = true
            for (let i = 0; i < 60 && seed2 < 0; i++) {
                let seed = 5000 + i * 7919
                game.applyScenario("dungeon", 2, seed)
                if (game.deepTravellers.some(s => s.kind === "lost" && s.special === "")) seed2 = seed
            }
            check(seed2 >= 0 && game.depth === 2, "seed " + seed2 + " has a lost traveller at depth 2 ("
                  + game.deepTravellers.map(s => s.kind + (s.special ? ":" + s.special : "")).join(", ") + ")")
            game.player.hp = 100000
        }],
        [100, () => {
            // The levels built on the way to it gone, a turn later
            step(1)
            let all = game.deepTravellers.slice(), ok = true
            for (let s of all) ok = talkTo(s) && ok
            freedAt2 = all.filter(s => s.outcome === "leaving" || s.outcome === "fleeing")
                          .map(s => s.kind + (s.special ? ":" + s.special : "")).sort()
            check(ok && all.every(s => s.outcome === "leaving"),
                  "the knight talks to all " + all.length + " travellers of the dungeon: "
                  + all.map(s => s.kind + " " + s.outcome).join(", "))
            check(camp().run.length === all.length && freedAt2.length === all.length,
                  "the run keeps them (" + camp().run.length + "), " + freedAt2.length + " left toward the exit")
            seconds(tc.say + tc.fadeAfter + tc.fade + 1)
            Clayground.paused = false
            goTo(game.levelIndexOf(2, "village"))
        }],
        [() => game.levelType === "village" && game.campfire !== null && game.player !== null, () => {
            let want = freedAt2.filter(k => k.indexOf(":") < 0)
            check(game.depth === 2 && JSON.stringify(sitting()) === JSON.stringify(want),
                  "the camp after depth 2: the " + want.length + " that left sit by the fire (" + sitting().join(", ")
                  + ")")
            let broken = sittingBroken()
            check(broken.length === 0, "each seated on the ring round the fire, on the floor, clear of the "
                  + game.campTravellers.length + " travellers" + (broken.length ? ": " + broken.join("; ") : ""))
            nearFire()
        }],
        [800, () => { capture("camp") }],
        [() => saved, () => { goTo(game.levelIndexOf(3, "dungeon")) }],
        [() => game.levelType === "dungeon" && game.player !== null, () => {
            goTo(game.levelIndexOf(3, "village"))
        }],
        [() => game.levelType === "village" && game.campfire !== null && game.player !== null, () => {
            check(game.depth === 3 && sitting().length === 0 && camp().run.length === freedAt2.length,
                  "the camp after depth 3 of the same run: none of the " + freedAt2.length
                  + " sent off at depth 2 by its fire (" + sitting().join(", ") + "), the run still keeps them")
            game.newRun()
        }],
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
            let sp = game.deepTravellers.find(s => s.special !== "")
            let table = sp ? camp().specialOf(sp.special) : null
            check(sp && table && sp.special === Balance.deep.specials[0].id && sp.kind === table.kind
                  && sp.edgeColor.toString() === Qt.color(Balance.deep.specialEdge).toString(),
                  "the deep room holds the first special not yet with the camps, " + (table ? table.name : "none")
                  + ", its edge gold")
            check(talkTo(sp), "the knight talks to it")
            check(sp.outcome === "leaving" && sp.saying === table.line,
                  "it says its own line and leaves: " + sp.outcome + ", \"" + sp.saying + "\"")
            let kept = []
            try { kept = JSON.parse(store.get("specials", "[]")) } catch (err) {}
            check(camp().joined.join() === table.id && kept.join() === table.id,
                  "it joins the camps for good, kept with the record: " + kept.join())
            seconds(tc.say + tc.fadeAfter + tc.fade + 1)
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
            // The same dungeon at depth 2 in this run, its travellers sent off again
            Clayground.paused = true
            game.applyScenario("dungeon", 2, seed2)
            game.player.hp = 100000
            step(1)
            let all = game.deepTravellers.slice(), ok = true
            for (let s of all) ok = talkTo(s) && ok
            check(ok && all.every(s => s.special === "") && all.length === freedAt2.length,
                  "this run the knight sends the " + all.length + " travellers of depth 2 off again")
            seconds(tc.say + tc.fadeAfter + tc.fade + 1)
            Clayground.paused = false
            goTo(game.levelIndexOf(2, "village"))
        }],
        [() => game.levelType === "village" && game.campfire !== null && game.player !== null, () => {
            let sp = Balance.deep.specials[0]
            let want = freedAt2.concat([sp.kind + ":" + sp.id]).sort()
            check(game.depth === 2 && JSON.stringify(sitting()) === JSON.stringify(want) && sittingBroken().length === 0
                  && Math.abs(game.campfire.healRate - Balance.campfire.healPerSecond * sp.heal) < 1e-6,
                  "the camp after depth 2: " + sp.name + " and the " + freedAt2.length + " sent off there ("
                  + sitting().join(", ") + ")")
            goTo(game.levelIndexOf(3, "dungeon"))
        }],
        [() => game.levelType === "dungeon" && game.player !== null, () => {
            goTo(game.levelIndexOf(3, "village"))
        }],
        [() => game.levelType === "village" && game.campfire !== null && game.player !== null, () => {
            let sp = Balance.deep.specials[0]
            check(game.depth === 3 && sitting().join() === sp.kind + ":" + sp.id && sittingBroken().length === 0
                  && Math.abs(game.campfire.healRate - Balance.campfire.healPerSecond * sp.heal) < 1e-6,
                  "the camp after depth 3: " + sp.name + " alone, those of depth 2 not (" + sitting().join(", ") + ")")
            game.player.hp = game.player.maxHp
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
