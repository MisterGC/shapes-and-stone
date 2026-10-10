// Danger bench - each depth a difficulty range, the knights' last dungeon
// picks the spot (issue #96).
//
// Feeds made-up fight records to Game.settleDanger from a fresh game's
// position: little HP lost puts the next dungeon high in its depth's
// range, much lost low, a fall lower still, toward the bottom; a party's
// losses count averaged and one knight's fall as the party's. Then it
// plays a descent the game's own way, a record made up before each exit:
// each next dungeon's danger is above the last and its position the one
// the record earned, a potion's heal does not take a loss back, and a
// fall carries the position into the next run. Last it builds the dungeon
// at the same seed and the same danger twice - the same rooms, enemies and
// everything laid on the floor - and once at another danger of the same
// depth, which differs. Prints one PASS or FAIL line per check and exits
// with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/danger/danger.qml

import QtQuick
import QtQuick.Window
import "../../src"

Window {
    id: bench
    width: 800
    height: 600
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0

    function check(ok, what) {
        console.log("[Danger]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Danger] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true,
                                                  recordStoreName: "ShapesAndStoneDangerBench"})
        script.start()
    }

    function near(a, b) { return Math.abs(a - b) < 0.0005 }
    function f3(v) { return Number(v).toFixed(3) }
    function band(p) { return ["low", "middle", "high"][game.dangerBand(p)] }

    // What the dungeon is made of, in the order it was made: its rooms,
    // every object laid in it (walls, floor, faces, torches and what lies
    // on the floor) and every enemy, each by what it is and where
    function fingerprint() {
        let out = [JSON.stringify(game.rooms)]
        for (let o of game.dungeonObjects) {
            if (!o) continue
            let parts = [String(o).split("(")[0]]
            for (let k of ["xWu", "yWu", "widthWu", "heightWu", "sizeWu", "seed", "color",
                           "flameColor", "style", "crackShare", "moss", "density", "kind"])
                if (o[k] !== undefined) parts.push(k + "=" + (typeof o[k] === "number" ? f3(o[k]) : String(o[k])))
            out.push(parts.join(" "))
        }
        for (let e of game.enemies)
            if (e && !e.destroyed)
                out.push([e.enemyType, e.tier, f3(e.xWu), f3(e.yWu), e.atk, e.maxHp].join(":"))
        return out
    }

    // The made-up records of the descent: the share of max HP lost in
    // each dungeon before its exit
    readonly property var descent: [0.05, 0.9, 0.0, 0.4, 0.95, 0.1]
    property int leg: 0
    property var dangers: []     // the danger of each dungeon of the descent
    property var expected: []    // the position each exit should give
    property var first: []

    property var steps: [
        [() => game.screen === "title", () => {
            let s = Balance.danger.start
            check(near(game.dangerPosition, s) && near(game.nextPosition, s),
                  "a fresh game starts at position " + f3(s) + " (" + f3(game.dangerPosition) + ")")
            let little = game.settleDanger(s, [{lost: 0.05, fell: false}])
            let none = game.settleDanger(s, [{lost: 0, fell: false}])
            let much = game.settleDanger(s, [{lost: 0.9, fell: false}])
            let fall = game.settleDanger(s, [{lost: 0.2, fell: true}])
            check(band(little) === "high" && band(none) === "high",
                  "little HP lost puts the next dungeon high in its depth's range (5% lost: "
                  + f3(little) + ", none: " + f3(none) + ")")
            check(band(much) === "low",
                  "much HP lost puts it low (90% lost: " + f3(much) + ")")
            check(band(fall) === "low" && fall < much && near(fall, s * (1 - Balance.danger.pull)),
                  "a fall earns the bottom: halfway down from " + f3(s) + " to " + f3(fall)
                  + ", below 90% lost")
            let p = s, falls = []
            for (let i = 0; i < 4; i++) { p = game.settleDanger(p, [{lost: 0, fell: true}]); falls.push(f3(p)) }
            check(p < 0.05, "falls in a row run down to the bottom (" + falls.join(", ") + ")")
            let top = s
            for (let i = 0; i < 60; i++) top = game.settleDanger(top, [{lost: 0, fell: false}])
            check(top < 1 && near(top, Balance.danger.top),
                  "a flawless descent never leaves the depth's range (" + top + ")")
            let party = game.settleDanger(s, [{lost: 0, fell: false}, {lost: 0.9, fell: false}])
            check(near(party, game.settleDanger(s, [{lost: 0.45, fell: false}])) && band(party) === "middle",
                  "a party's losses count averaged: 0% and 90% lost stand where 45% does ("
                  + f3(party) + ")")
            let partyFall = game.settleDanger(s, [{lost: 0, fell: false}, {lost: 0.1, fell: true}])
            check(near(partyFall, fall), "one knight's fall is the party's (" + f3(partyFall) + ")")
            game.applyScenario("dungeon", s)
        }],
        [() => game.player && game.levelType === "dungeon", () => {
            check(game.depth === 0 && near(game.danger, Balance.danger.start),
                  "the first dungeon's danger is depth 0 at " + f3(game.danger))
            dangers.push(game.danger)
            // A potion's heal does not take a loss back
            let p = game.player
            p.graceLeft = 0
            p.takeDamage(60 + p.def, p.xWu + 1, p.yWu)
            p.potions = 1
            let healed = game.drinkPotion()
            check(healed > 0 && p.hp === p.maxHp - 60 + healed && near(game.levelRecord().lost, 60 / p.maxHp),
                  "a knight hit for 60 that drinks a potion has lost " + f3(game.levelRecord().lost)
                  + " of its HP all the same (HP " + p.hp + ", healed " + healed + ")")
            leg = 0
        }],
        // Down the descent: a made-up record, the exit, the village, the
        // next dungeon
        ...[0, 1, 2, 3, 4, 5].map(i => [() => game.player && game.levelType === "dungeon", () => {
            let lost = descent[i]
            let from = game.dangerPosition
            game.fightRecord.damageTaken = Math.round(lost * game.player.maxHp)
            game.fightRecord.deaths = 0
            let want = game.settleDanger(from, [{lost: lost, fell: false}])
            game.resetDungeon()
            let inVillage = game.levelType === "village" && near(game.nextPosition, want)
                && near(game.dangerPosition, from)
            game.resetDungeon()
            let d = game.danger
            check(inVillage && game.levelType === "dungeon" && game.depth === i + 1
                  && near(game.dangerPosition, want),
                  "depth " + (i + 1) + " after " + Math.round(lost * 100) + "% lost stands at "
                  + f3(game.dangerPosition) + " in its range (" + band(want) + "), " + f3(from) + " before")
            check(d > dangers[dangers.length - 1],
                  "its danger " + f3(d) + " is above the last dungeon's " + f3(dangers[dangers.length - 1]))
            dangers.push(d)
        }]),
        // The knight falls: the next run starts lower, from where this one was
        [() => game.player && game.levelType === "dungeon", () => {
            let from = game.dangerPosition
            let p = game.player
            p.graceLeft = 0
            p.isBlocking = false
            p.takeDamage(10 * p.maxHp, p.xWu + 1, p.yWu)
            check(game.fallen && near(game.nextPosition, game.settleDanger(from, [{lost: 1, fell: true}])),
                  "a fall at depth " + game.depth + " (" + f3(from) + ") puts the next run at "
                  + f3(game.nextPosition))
            expected = [game.nextPosition]
            game.newRun()
        }],
        [() => game.player && !game.fallen && game.levelType === "dungeon", () => {
            check(game.depth === 0 && near(game.dangerPosition, expected[0]),
                  "the next run's first dungeon stands there: depth 0 at " + f3(game.danger)
                  + " - the position lives across runs")
            // The same seed and the same danger build the same dungeon
            game.applyScenario("dungeon", 2.8)
            first = fingerprint()
            game.applyScenario("dungeon", 2.8)
            let again = fingerprint()
            check(first.length > 20 && JSON.stringify(first) === JSON.stringify(again),
                  "seed " + game.scenarioSeed + " at danger 2.8 builds the same dungeon twice ("
                  + first.length + " rooms, objects and enemies)")
            let n = game.enemies.length, sb = game.spawnRolls(2.8)
            check(n >= sb.enemiesMin && n <= sb.enemiesMax && game.enemies.every(e =>
                      e.atk === game.enemyAtk(e.enemyType, 2.8)),
                  "danger 2.8 drives the spawn table and the blows (" + n + " enemies, "
                  + sb.enemiesMin + " to " + sb.enemiesMax + ")")
            game.applyScenario("dungeon", 2.2)
            let low = fingerprint()
            check(JSON.stringify(low) !== JSON.stringify(first) && game.depth === 2,
                  "the same seed at danger 2.2, the same depth, builds another dungeon ("
                  + game.enemies.length + " enemies)")
            console.log("[Danger] descent:", dangers.map(f3).join(" < "))
            console.log("[Danger] done,", failures, "failed")
        }],
        // Torn down before quitting, as the other benches do
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
                    console.log("[Danger] FAIL step", i, "timed out")
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
