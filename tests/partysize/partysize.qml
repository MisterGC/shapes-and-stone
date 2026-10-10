// Party size bench - more knights meet more resistance: a dungeon's
// enemies grow with the party (issue #102).
//
// Builds the dungeon of the same seed at the same danger for 1, 2 and 4
// knights, as the dojo does (game.knightsOverride, then applyScenario),
// and checks it against Balance.party: per knight beyond the first
// enemiesPerKnight more enemies, within depth.enemiesCap, each with
// hpPerKnight more of its HP. The rooms and everything laid on the floor
// stay the same. For 1 knight the dungeon is today's: its fingerprint is
// the one recorded below, from the game with 9 to 12 rooms. A knight
// count changed in a dungeon changes the next dungeon, not this one, and
// the village's fight room is not scaled. Prints one PASS or FAIL line
// per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/partysize/partysize.qml

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
        console.log("[PartySize]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[PartySize] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true,
                                                  recordStoreName: "ShapesAndStonePartySizeBench"})
        script.start()
    }

    function f3(v) { return Number(v).toFixed(3) }

    // The dungeons the bench builds: dangers on the scenario seed; with
    // the cap at 26 neither reaches it, four knights at 1.5 come to 24
    readonly property var dangers: [0.5, 1.5]
    readonly property var parties: [1, 2, 4]
    // Today's dungeon for one knight (9 to 12 rooms, 10 to 15 enemies at
    // depth 0): the fingerprint hash and enemy count at each danger, on
    // the scenario seed
    readonly property var today: ({
        "0.5": { hash: "c87fe15c", enemies: 15 },
        "1.5": { hash: "886b113c", enemies: 18 }
    })

    // What the dungeon is made of, as the danger bench reads it: its
    // rooms and every object laid in it
    function layout() {
        let out = [JSON.stringify(game.rooms)]
        for (let o of game.dungeonObjects) {
            if (!o) continue
            // The type without the number QML gives it, or an inline
            // type of Game.qml, in load order: a new type shifts it
            let parts = [String(o).split("(")[0].replace(/_QML(TYPE)?_\d+$/, "")]
            for (let k of ["xWu", "yWu", "widthWu", "heightWu", "sizeWu", "seed", "color",
                           "flameColor", "style", "crackShare", "moss", "density", "kind"])
                if (o[k] !== undefined) parts.push(k + "=" + (typeof o[k] === "number" ? f3(o[k]) : String(o[k])))
            out.push(parts.join(" "))
        }
        return out
    }
    function foes() {
        return game.enemies.filter(e => e && !e.destroyed)
                   .map(e => [e.enemyType, e.tier, f3(e.xWu), f3(e.yWu), e.atk, e.maxHp, e.hp].join(":"))
    }
    function hash(lines) {
        let s = lines.join("\n"), h = 5381
        for (let i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0
        return h.toString(16)
    }
    // The fingerprint of today's dungeon: layout and enemies, without the
    // HP an enemy has left (all of it)
    function todayLines() {
        return layout().concat(foes().map(f => f.split(":").slice(0, 6).join(":")))
    }

    // The table, read here from Balance and not from the game's spawnRolls
    // per knight beyond the first: one knight's dungeon reads none of it
    function extra(k) { return Math.max(0, k - 1) }
    function perKnight(k, what) { return extra(k) === 0 ? 0 : extra(k) * Balance.party[what] }
    function range(d, k) {
        let more = Math.floor(d * Balance.depth.enemies) + perKnight(k, "enemiesPerKnight")
        let cap = Balance.depth.enemiesCap
        return [Math.min(cap, Balance.spawn.enemiesMin + more), Math.min(cap, Balance.spawn.enemiesMax + more)]
    }
    function hpOf(type, tier, k) {
        let base = Balance.enemy.tierHp[tier] + Balance.enemy[type].hpBonus
        return Math.round(base * (1 + perKnight(k, "hpPerKnight")))
    }

    // The dojo's knight count; a game without it (before issue #102)
    // builds for one knight whatever is asked
    function knights(k) { if ("knightsOverride" in game) game.knightsOverride = k }
    function builtFor() { return game.partyKnights === undefined ? 1 : game.partyKnights }
    function build(d, k) {
        knights(k)
        game.applyScenario("dungeon", d)
        return { knights: builtFor(), layout: layout(), foes: foes(), n: game.enemies.length,
                 enemies: game.enemies.slice() }
    }

    property var solo: ({})

    property var steps: [
        [() => game.screen === "title", () => {
            check(Balance.party.enemiesPerKnight > 0 && Balance.party.hpPerKnight > 0,
                  "Balance.party has enemiesPerKnight " + Balance.party.enemiesPerKnight
                  + " and hpPerKnight " + Balance.party.hpPerKnight)
            for (let d of dangers) {
                let s = null
                for (let k of parties) {
                    let b = build(d, k)
                    let tag = "danger " + d + ", " + k + (k === 1 ? " knight: " : " knights: ")
                    let r = range(d, k)
                    check(b.knights === k, tag + "the dungeon is built for " + b.knights)
                    if (k === 1) {
                        s = b
                        let h = hash(todayLines()), t = today[String(d)]
                        console.log("[PartySize] today's", "danger " + d + ":", h, b.n, "enemies")
                        check(h === t.hash && b.n === t.enemies,
                              tag + "today's dungeon, " + b.n + " enemies (fingerprint " + h
                              + ", recorded " + t.hash + ", " + t.enemies + " enemies)")
                    } else {
                        check(JSON.stringify(b.layout) === JSON.stringify(s.layout),
                              tag + "the same rooms and floor as for 1 knight (" + b.layout.length + " objects)")
                        let uncapped = r[1] < Balance.depth.enemiesCap
                        let want = s.n + perKnight(k, "enemiesPerKnight")
                        check(b.n >= r[0] && b.n <= r[1] && (!uncapped || b.n === want),
                              tag + b.n + " enemies, the table's " + r[0] + " to " + r[1]
                              + (uncapped ? ", the solo roll's " + s.n + " plus " + (want - s.n)
                                          : ", at the cap " + Balance.depth.enemiesCap)
                              + " (1 knight: " + s.n + ")")
                    }
                    let wrong = b.enemies.filter(e => e.maxHp !== hpOf(e.enemyType, e.tier, k) || e.hp !== e.maxHp)
                    let shown = []
                    for (let t of ["grunt", "guardian", "spitter"])
                        for (let tier of [0, 1, 2])
                            if (b.enemies.some(e => e.enemyType === t && e.tier === tier))
                                shown.push(t + tier + " " + hpOf(t, tier, k))
                    check(b.n > 0 && wrong.length === 0,
                          tag + "every enemy has the table's HP (" + shown.join(", ") + ")"
                          + (wrong.length ? "; " + wrong.length + " do not, e.g. " + wrong[0].enemyType
                                            + wrong[0].tier + " " + wrong[0].maxHp : ""))
                }
            }
            // The same seed, danger and knights build the same dungeon
            let a = build(1.5, 4), b = build(1.5, 4)
            check(JSON.stringify(a.layout.concat(a.foes)) === JSON.stringify(b.layout.concat(b.foes)),
                  "seed " + game.scenarioSeed + " at danger 1.5 for 4 knights builds the same dungeon twice")
            // A knight count changed in a dungeon changes the next one only
            let c = build(0.5, 2)
            knights(4)
            check(builtFor() === 2 && JSON.stringify(foes()) === JSON.stringify(c.foes),
                  "a third and fourth knight in a 2 knights' dungeon leave its " + c.n + " enemies as they are")
            game.resetDungeon()
        }],
        [() => game.player && game.levelType === "village", () => {
            check(builtFor() === 4, "the village after it is entered for " + builtFor() + " knights")
            game.resetDungeon()
        }],
        [() => game.player && game.levelType === "dungeon", () => {
            let r = range(game.danger, 4)
            let wrong = game.enemies.filter(e => e.maxHp !== hpOf(e.enemyType, e.tier, 4))
            check(builtFor() === 4 && game.enemies.length >= r[0] && game.enemies.length <= r[1]
                  && wrong.length === 0,
                  "the next dungeon, depth " + game.depth + " at " + f3(game.danger) + ", is built for 4: "
                  + game.enemies.length + " enemies, the table's " + r[0] + " to " + r[1] + ", their HP the table's")
            // The village's fight room is the same for any party
            knights(4)
            game.applyScenario("fight", 0)
            let wrongRoom = game.enemies.filter(e => e.maxHp !== hpOf(e.enemyType, e.tier, 1))
            check(game.enemies.length === Balance.spawn.fightRoom.length && wrongRoom.length === 0,
                  "the fight room for 4 knights holds its " + game.enemies.length + " enemies at solo HP")
            knights(0)
            console.log("[PartySize] done,", failures, "failed")
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
                    console.log("[PartySize] FAIL step", i, "timed out")
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
                console.log("[PartySize] FAIL step", i - 1, "threw:", err)
                Qt.exit(failures + 1)
                stop()
            }
        }
    }
}
