// Leads bench - at most one tough enemy per room, the room's lead
// (issue #269).
//
// Plans 50 seeds at each of depths 0, 2, 4 and 8 the way the game builds
// a dungeon (Game.planDungeon, the seed and the depth set as the dungeon
// master sets them, at position 0): no room holds two tough enemies, the
// start room none, and the rooms with a lead are as many as the table
// gives at that depth (spawnRolls' leadShare of the rooms but the start
// room, rounded, no more than hold an enemy). Each seed planned twice
// gives the same grid, rooms and enemies. Then it builds the dungeon at
// each depth on the scenario seed and checks that the enemies spawned are
// the planned ones and again no room holds two tough. Prints the share of
// rooms with a lead per depth against the table's, one PASS or FAIL line
// per check, and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/leads/leads.qml

import QtQuick
import QtQuick.Window
import "../../src"

Window {
    id: bench
    width: 800
    height: 600
    visible: true
    color: "#1a1a2e"

    readonly property var depths: [0, 2, 4, 8]
    readonly property int seeds: 50
    property var game: null
    property int failures: 0
    property int built: 0

    function check(ok, what) {
        console.log("[Leads]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Leads] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true})
        script.start()
    }

    // Which room an enemy at x, y (wu) stands in, its index, -1 for none
    function roomOf(rooms, x, y) {
        let gx = Math.floor(x / game.cellSize), gy = Math.floor(y / game.cellSize)
        return rooms.findIndex(r => gx >= r.x && gx < r.x + r.w && gy >= r.y && gy < r.y + r.h)
    }
    // A dungeon's enemies by room: {tough: [per room], any: [per room]}
    function byRoom(rooms, enemies) {
        let out = { tough: rooms.map(() => 0), any: rooms.map(() => 0) }
        for (let e of enemies) {
            let i = roomOf(rooms, e.x, e.y)
            if (i < 0) continue
            out.any[i]++
            if (e.tier === 2) out.tough[i]++
        }
        return out
    }
    // The rooms with a lead the table gives a dungeon at danger d
    function leadsWanted(rooms, enemies, d) {
        let spawnRooms = rooms.length - 1
        return Math.min(enemies.length, spawnRooms, Math.round(spawnRooms * game.spawnRolls(d, 1).leadShare))
    }
    function planOf(p) {
        return JSON.stringify([p.grid, p.rooms, p.enemies.map(e => [e.x, e.y, e.tier, e.type])])
    }

    function planned(d) {
        let crowded = [], inStart = [], off = [], differs = []
        let leads = 0, rooms = 0
        for (let s = 1; s <= seeds; s++) {
            let m = { depth: d, seed: s }
            let p = game.planDungeon(0, 0, 1, m)
            let r = byRoom(p.rooms, p.enemies)
            let two = r.tough.filter(n => n > 1).length
            if (two > 0) crowded.push("seed " + s + ": " + two + " rooms")
            if (r.any[0] > 0) inStart.push("seed " + s)
            let have = r.tough.filter(n => n === 1).length
            let want = leadsWanted(p.rooms, p.enemies, d)
            if (have !== want) off.push("seed " + s + ": " + have + " of " + want)
            leads += have
            rooms += p.rooms.length - 1
            if (planOf(game.planDungeon(0, 0, 1, m)) !== planOf(p)) differs.push("seed " + s)
        }
        let share = game.spawnRolls(d, 1).leadShare
        console.log("[Leads] depth " + d + ": " + leads + " leads in " + rooms + " rooms, "
                    + (leads / rooms).toFixed(3) + " of them; the table's share " + share.toFixed(3))
        check(crowded.length === 0, "at depth " + d + " no room of " + seeds + " seeds holds two tough enemies"
              + (crowded.length ? " - " + crowded.join(", ") : ""))
        check(inStart.length === 0, "at depth " + d + " the start room holds no enemy"
              + (inStart.length ? " - " + inStart.join(", ") : ""))
        check(off.length === 0, "at depth " + d + " every seed has the table's count of rooms with a lead ("
              + Math.round(share * 100) + " % of its rooms)" + (off.length ? " - " + off.join(", ") : ""))
        check(differs.length === 0, "at depth " + d + " each seed planned twice is the same dungeon"
              + (differs.length ? " - " + differs.join(", ") : ""))
    }

    // The dungeon built at depth d on the scenario seed is the planned one
    function checkBuilt(d) {
        let live = game.enemies.filter(e => e && !e.destroyed)
            .map(e => ({ x: e._spawnXWu, y: e._spawnYWu, tier: e.tier, type: e.enemyType }))
        let p = game.planDungeon(game.levelIndex, game.dangerPosition, game.partyKnights, null, game.masterSeed)
        let a = JSON.stringify(live.map(e => [e.x.toFixed(3), e.y.toFixed(3), e.tier, e.type]))
        let b = JSON.stringify(p.enemies.map(e => [e.x.toFixed(3), e.y.toFixed(3), e.tier, e.type]))
        check(a === b && JSON.stringify(game.rooms) === JSON.stringify(p.rooms),
              "at depth " + d + " the dungeon built holds the planned " + p.enemies.length + " enemies")
        let r = byRoom(game.rooms, live)
        let want = leadsWanted(game.rooms, live, game.danger)
        check(r.tough.every(n => n <= 1) && r.tough.filter(n => n === 1).length === want,
              "at depth " + d + " the dungeon built has " + r.tough.filter(n => n === 1).length
              + " rooms with a lead, the table's " + want + ", none with two")
    }

    property var steps: {
        let out = [[() => game.screen === "title", () => {
            for (let d of depths) planned(d)
            game.applyScenario("dungeon", depths[0])
        }]]
        for (let i = 0; i < depths.length; i++) {
            let d = depths[i], next = depths[i + 1]
            out.push([() => game.player && game.enemies.length > 0 && game.depth === d, () => {
                checkBuilt(d)
                if (next !== undefined) game.applyScenario("dungeon", next)
            }])
        }
        out.push([300, () => {
            console.log("[Leads] done,", failures, "failed")
            game.destroy()
        }])
        out.push([300, () => Qt.exit(failures)])
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
                if (waitedMs > 30000) {
                    console.log("[Leads] FAIL step", i, "timed out")
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
