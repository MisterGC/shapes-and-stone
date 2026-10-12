// Dungeon master bench - before each dungeon the host sets its numbers,
// previews the map, generates again or goes (issue #142).
//
// Ticks Dungeon Master and starts a solo game on the scenario seed: the
// panel is up before the first dungeon, no knight yet, its rows at the
// values the game would use (the rooms and enemies of the seed's first
// dungeon, the band's features per room). A and Backspace on a row set
// it and give it back. Copy settings puts the settings set on the
// clipboard as JSON, Paste settings reads it back. The bench sets every
// row - 2 enemies, 1 spike plate, 1 arrow slit and 2 breakables per room,
// 8 rooms, base depth 1, relative difficulty 0.2 - presses G twice (the
// second time a new seed) and checks the preview: the asked rooms and,
// in every room but the start room, the asked counts. Enter goes: the
// dungeon built is the one the preview showed, the same grid, rooms,
// features and enemies, at depth 1 + 0.2. A second game started on the
// same store finds the settings and the mode kept. The village after it
// asks no master; the next dungeon does, and with every setting given
// back to the game Go builds the dungeon the game builds without the
// mode. With the mode off the next dungeon comes without the panel.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/dungeonmaster/dungeonmaster.qml

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Storage
import "../../src"

Window {
    id: bench
    width: 1100
    height: 720
    visible: true
    color: "#1a1a2e"

    readonly property string storeName: "ShapesAndStoneDungeonMasterBench"
    property var game: null
    property int failures: 0
    property var shown: null
    property var asked: ({ enemies: 2, spikes: 1, slits: 1, rooms: 8, depth: 1, position: 0.2, breakables: 2 })

    function check(ok, what) {
        console.log("[DungeonMaster]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    // What the game kept, read back the way the next start reads it, and
    // the clipboard as another program would read it
    KeyValueStore { id: kept; name: bench.storeName }
    TextEdit { id: clip; visible: false }
    function clipboard() {
        clip.text = ""
        clip.paste()
        return clip.text
    }

    function newGame() {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[DungeonMaster] FAIL", c.errorString())
            Qt.exit(1)
            return null
        }
        return c.createObject(bench.contentItem, { width: 1100, height: 720, muted: true,
                                                   recordStoreName: bench.storeName })
    }

    Component.onCompleted: {
        kept.remove("dungeonMaster")
        kept.remove("dungeonMasterSettings")
        game = newGame()
        if (game) script.start()
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
    function panel() {
        let f = find(game, "dungeonMasterPanel")
        return f && f.visible ? f : null
    }
    function row(key) { return game.masterRows().find(r => r.key === key) }
    function near(a, b) { return Math.abs(a - b) < 1e-6 }

    // Which room a cell lies in, its index, -1 for none
    function roomOf(rooms, gx, gy) {
        return rooms.findIndex(r => gx >= r.x && gx < r.x + r.w && gy >= r.y && gy < r.y + r.h)
    }
    // Per room but the start room: [{enemies, spikes, slits, breakables}]
    function perRoom(rooms, enemies, features) {
        let out = rooms.map(() => ({ enemies: 0, spikes: 0, slits: 0, breakables: 0 }))
        for (let e of enemies) {
            let i = roomOf(rooms, Math.floor(e.x / game.cellSize), Math.floor(e.y / game.cellSize))
            if (i >= 0) out[i].enemies++
        }
        for (let f of features) {
            let i = roomOf(rooms, f.gx, f.gy)
            if (i < 0) continue
            if (f.kind === "spike") out[i].spikes++
            else if (f.kind === "slit") out[i].slits++
            else out[i].breakables++
        }
        return out.slice(1)
    }
    function cellOf(kind, cell) {
        let c = cell.split(",").map(Number)
        return { kind: kind, gx: c[0], gy: c[1] }
    }
    function shortOf(rooms, want) {
        let out = []
        rooms.forEach((r, i) => {
            for (let k in want) if (r[k] !== want[k]) out.push("room " + (i + 1) + " " + k + " " + r[k])
        })
        return out
    }
    // The dungeon built, in the preview's terms
    function built() {
        return {
            grid: JSON.stringify(game.grid),
            rooms: JSON.stringify(game.rooms),
            features: JSON.stringify(game.features.map(f => [f.kind, f.gx, f.gy])),
            enemies: JSON.stringify(game.enemies.filter(e => e && !e.destroyed)
                                    .map(e => [e._spawnXWu.toFixed(3), e._spawnYWu.toFixed(3), e.tier, e.enemyType]))
        }
    }
    function planned(p) {
        return {
            grid: JSON.stringify(p.grid),
            rooms: JSON.stringify(p.rooms),
            features: JSON.stringify(p.features.map(f => [f.kind, f.gx, f.gy])),
            enemies: JSON.stringify(p.enemies.map(e => [e.x.toFixed(3), e.y.toFixed(3), e.tier, e.type]))
        }
    }
    function same(a, b, what) {
        for (let k of ["grid", "rooms", "features", "enemies"])
            check(a[k] === b[k], what + ": the same " + k + (a[k] === b[k] ? "" : " (" + a[k].length + " vs " + b[k].length + " chars)"))
    }

    property var steps: [
        // The mode ticked, a solo start: the panel before the first dungeon
        [0, () => {
            game.setDungeonMaster(true)
            game.masterSeed = game.scenarioSeed
            game.screen = "game"
        }],
        [() => panel() !== null && panel().activeFocus, () => {
            check(game.player === null && game.masterAsk.index === 0,
                  "with Dungeon Master ticked the panel is up before the first dungeon, no knight yet")
            let p = game.planDungeon(0, game.dangerPosition, 1, null, game.scenarioSeed)
            let rooms = row("rooms"), enemies = row("enemies")
            check(!rooms.set && rooms.value === p.rooms.length,
                  "the rooms row shows the game's " + p.rooms.length + " (" + rooms.text + ")")
            check(!enemies.set && near(enemies.value, p.enemies.length / (p.rooms.length - 1)),
                  "the enemies row shows the game's " + p.enemies.length + " over " + (p.rooms.length - 1)
                  + " rooms (" + enemies.text + ")")
            let band = game.dangerBand(game.dangerPosition)
            let kinds = Balance.dungeon.kinds
            check(near(row("spikes").value, kinds.spike.perRoom[band])
                  && near(row("slits").value, kinds.slit.perRoom[band])
                  && near(row("breakables").value, kinds.urn.perRoom[band] + kinds.crate.perRoom[band]
                          + kinds.crystal.perRoom[band]),
                  "the feature rows show the band's per room (" + row("spikes").text + ", "
                  + row("slits").text + ", " + row("breakables").text + ")")
            check(row("depth").value === 0 && near(row("position").value, game.dangerPosition),
                  "base depth 0 and the relative difficulty " + row("position").text)
            // A on the first row turns it down a step and sets it
            bench.shown = enemies.value
            press(Qt.Key_A)
        }],
        [100, () => {
            let e = row("enemies")
            check(e.set && near(e.value, Math.round((bench.shown - 0.1) * 100) / 100),
                  "A sets the enemies row a step down (" + Number(bench.shown).toFixed(2) + " -> " + e.text + ")")
            check(JSON.parse(kept.get("dungeonMasterSettings", "{}")).enemies === e.value,
                  "the setting is kept as it is set")
            press(Qt.Key_Backspace)
        }],
        [100, () => {
            check(!row("enemies").set && Object.keys(game.masterPinned).length === 0,
                  "Backspace gives it back to the game")
            game.masterPaste(JSON.stringify(asked))
            check(JSON.stringify(game.masterPinned) === JSON.stringify(asked),
                  "every row set: " + game.masterSettingsJson())
            press(Qt.Key_C)
        }],
        [100, () => {
            let text = clipboard()
            check(text === JSON.stringify(asked), "Copy settings puts them on the clipboard as JSON (" + text + ")")
            game.masterPaste("{}")
            check(Object.keys(game.masterPinned).length === 0, "pasting {} sets none")
            press(Qt.Key_V)
        }],
        [100, () => {
            check(JSON.stringify(game.masterPinned) === JSON.stringify(asked),
                  "Paste settings reads the copied JSON back (" + game.masterSettingsJson() + ")")
            clip.text = "no settings here"
            clip.selectAll()
            clip.copy()
            press(Qt.Key_V)
        }],
        [100, () => {
            check(JSON.stringify(game.masterPinned) === JSON.stringify(asked) && game.masterNote !== "",
                  "a clipboard without settings leaves them as they are (" + game.masterNote + ")")
            press(Qt.Key_G)
        }],
        [100, () => {
            let p = game.masterPreview
            check(p !== null && p.seed === game.deriveSeed(game.scenarioSeed, 0),
                  "G shows the dungeon on the run's own seed (" + (p ? p.seed : "none") + ")")
            bench.shown = p
            press(Qt.Key_G)
        }],
        [100, () => {
            let p = game.masterPreview
            check(p !== null && p.seed !== bench.shown.seed && p.seed === game.masterSeedRoll,
                  "G again rolls a new seed (" + bench.shown.seed + " -> " + (p ? p.seed : "none") + ")")
            bench.shown = p
            check(p.rooms.length === asked.rooms, "the preview has the asked " + asked.rooms + " rooms ("
                  + p.rooms.length + ")")
            let short = shortOf(perRoom(p.rooms, p.enemies, p.features),
                                { enemies: asked.enemies, spikes: asked.spikes, slits: asked.slits,
                                  breakables: asked.breakables })
            check(short.length === 0, "every room but the start room holds the asked counts in the preview"
                  + (short.length ? " - short: " + short.join(", ") : ""))
            check(p.depth === asked.depth && near(p.position, asked.position),
                  "the preview is at base depth " + p.depth + " and position " + p.position)
            press(Qt.Key_Return)
        }],
        [() => game.player !== null && panel() === null, () => {
            check(game.masterAsk === null, "Enter goes: the panel is gone, the knight in the dungeon")
            same(built(), planned(bench.shown), "the dungeon entered is the one the preview showed")
            let p = bench.shown
            let objs = perRoom(game.rooms, game.enemies.filter(e => e && !e.destroyed).map(e => ({ x: e._spawnXWu, y: e._spawnYWu })),
                               game.breakables.map(b => cellOf("urn", b.cell))
                               .concat(game.plates.map(o => cellOf("spike", o.cell)))
                               .concat(game.slits.map(o => cellOf("slit", o.cell))))
            let short = shortOf(objs, { enemies: asked.enemies, spikes: asked.spikes, slits: asked.slits,
                                        breakables: asked.breakables })
            check(short.length === 0, "the built dungeon's enemies, breakables, plates and slits: the asked counts per room"
                  + (short.length ? " - short: " + short.join(", ") : ""))
            check(game.levelIndex === 0 && game.depth === 0 && game.dangerDepth === 1 && near(game.danger, 1.2),
                  "the run stays at depth 0, its danger counts from base depth 1: " + game.danger.toFixed(3))
            check(game.masterSeed === game.scenarioSeed && game.levelSeedNow() === p.seed,
                  "the run's seed stays, the level is built on the rolled one")
            check(kept.get("dungeonMaster", "") === "1"
                  && kept.get("dungeonMasterSettings", "") === JSON.stringify(asked),
                  "the mode and the settings are kept")
            // A second game on the same store: as after a reload
            let again = newGame()
            check(again && again.dungeonMaster && JSON.stringify(again.masterPinned) === JSON.stringify(asked),
                  "a game started again finds the mode on and the settings ("
                  + (again ? again.masterSettingsJson() : "none") + ")")
            if (again) again.destroy()
            // Out to the village: no master there
            game.resetting = true
            game.resetDungeon()
        }],
        [() => game.levelType === "village" && game.player !== null, () => {
            check(game.masterAsk === null && game.master === null && game.dangerDepth === game.depth,
                  "the village asks no master and has none")
            for (let k in asked) game.masterUnset(k)
            game.resetting = true
            game.resetDungeon()
        }],
        [() => panel() !== null && panel().activeFocus, () => {
            check(game.masterAsk.index === 2 && game.levelType === "village",
                  "out of the village the panel is up for the next dungeon")
            bench.shown = game.planDungeon(2, game.masterAsk.pos, 1, null)
            press(Qt.Key_Return)
        }],
        [() => game.levelType === "dungeon" && game.player !== null && panel() === null, () => {
            check(game.master === null, "with every setting the game's, Go builds with no overrides")
            same(built(), planned(bench.shown), "Go with the game's values builds the game's dungeon")
            game.setDungeonMaster(false)
            game.resetting = true
            game.resetDungeon()
        }],
        [() => game.levelType === "village" && game.player !== null, () => {
            game.resetting = true
            game.resetDungeon()
        }],
        [() => game.levelIndex === 4 && game.player !== null, () => {
            check(game.masterAsk === null && game.master === null && kept.get("dungeonMaster", "") === "0",
                  "with the mode off the next dungeon comes without the panel")
            console.log("[DungeonMaster] done,", failures, "failed")
            Qt.exit(failures)
        }]
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
                    console.log("[DungeonMaster] FAIL step", i, "timed out")
                    Qt.exit(failures + 100)
                    stop()
                }
                return
            }
            waitedMs = 0
            // Advance first: a key click spins the event loop, and this
            // timer must not run the same step again inside it
            i++
            if (i >= bench.steps.length) stop()
            step[1]()
        }
    }
}
