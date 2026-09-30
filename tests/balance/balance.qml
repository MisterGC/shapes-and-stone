// Balance bench - every fight number comes from the Balance table (issue #32).
//
// Reads the whole table the way the inspector does, then builds a dungeon,
// the fight room and the village and checks that the knight, every enemy,
// the fight room lineup and the campfire carry the table's values. Last it
// changes a value in the table and checks the next knight has it. Prints
// one PASS or FAIL line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/balance/balance.qml

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
        console.log("[Balance]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Balance] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true})
        script.start()
    }

    function near(a, b) { return Math.abs(a - b) < 0.001 }

    // The numbers of the table, each with its path
    function leaves(o, path, out) {
        for (let k in o) {
            let v = o[k], p = path ? path + "." + k : k
            if (v !== null && typeof v === "object") leaves(v, p, out)
            else out.push(p)
        }
        return out
    }

    function checkEnemy(e) {
        let t = Balance.enemy[e.enemyType]
        let hp = Balance.enemy.tierHp[e.tier] + t.hpBonus
        return e.maxHp === hp && e.atk === t.atk && e.def === t.def
            && near(e.chaseSpeed, t.chaseSpeed) && near(e.patrolSpeed, t.patrolSpeed)
            && near(e.lungeRange, Balance.enemy.lungeRange)
            && near(e.windUpDuration, Balance.enemy.windUp)
            && near(e.shootCooldown, Balance.enemy.shootCooldown)
            && near(e.shieldArc, Balance.enemy.shieldArc)
    }

    property var campfire: null
    property int hpBefore: 0

    property var steps: [
        [() => game.screen === "title", () => {
            let json = JSON.parse(JSON.stringify(Balance))
            let groups = ["knight", "enemy", "projectile", "spawn", "campfire"]
            check(groups.every(g => json[g] !== undefined) && json.minDamage === 1,
                  "JSON.stringify(Balance) returns the whole table ("
                  + leaves(json, "", []).length + " values)")
            game.applyScenario("dungeon")
        }],
        [() => game.player && game.enemies.length > 0, () => {
            let p = game.player, k = Balance.knight
            check(p.hp === k.hp && p.maxHp === k.hp && p.atk === k.atk && p.def === k.def,
                  "the knight's HP, attack and defense come from the table")
            check(near(p.maxSpeed, k.moveSpeed) && near(p.attackRange, k.attackRange)
                  && near(p.attackArcAngle, k.attackArc) && near(p.attackCooldownTime, k.attackCooldown)
                  && near(p.dashSpeed, k.dashSpeed) && near(p.dashDuration, k.dashDuration)
                  && near(p.dashCooldownTime, k.dashCooldown) && near(p.shieldArcAngle, k.shieldArc),
                  "the knight's speed, reach, cooldowns and dash come from the table")
            let n = game.enemies.length
            check(n >= Balance.spawn.enemiesMin && n <= Balance.spawn.enemiesMax,
                  "the dungeon spawns " + n + " enemies, within the table's "
                  + Balance.spawn.enemiesMin + " to " + Balance.spawn.enemiesMax)
            let wrong = game.enemies.filter(e => !checkEnemy(e))
            check(wrong.length === 0, "every enemy's HP, attack, defense and timings come from the table ("
                  + wrong.map(e => e.enemyType + "/" + e.tier + " hp " + e.maxHp).join(", ") + ")")
            game.applyScenario("fight")
        }],
        [() => game.fightRoomActive && game.enemies.length > 0, () => {
            let lineup = Balance.spawn.fightRoom
            let es = game.enemies
            let same = es.length === lineup.length && lineup.every((l, i) =>
                es[i].enemyType === l.type && es[i].tier === l.tier
                && near(es[i]._spawnXWu, game._fightRoomCx + l.dx)
                && near(es[i]._spawnYWu, game._fightRoomCy + l.dy))
            check(same, "the fight room holds the table's lineup ("
                  + es.map(e => e.enemyType + "/" + e.tier).join(", ") + ")")
            check(es.every(checkEnemy), "the fight room's enemies carry the table's stats")
            game.applyScenario("village")
        }],
        [() => game.player && game.levelType === "village", () => {
            campfire = game.dungeonObjects.find(o => o && o.healRadius !== undefined)
            check(campfire && near(campfire.healRate, Balance.campfire.healPerSecond)
                  && near(campfire.healRadius, Balance.campfire.healRadius),
                  "the campfire's heal rate and radius come from the table")
            // Hurt, at the fire
            game.player.xWu = campfire.xWu
            game.player.yWu = campfire.yWu
            game.player.hp = 60
            hpBefore = 60
        }],
        [2000, () => {
            let healed = game.player.hp - hpBefore
            let want = 2 * Balance.campfire.healPerSecond
            check(healed >= want - 2 && healed <= want + 1,
                  "two seconds at the fire heal " + healed + " HP, the table says " + want)
            // A tuned table reaches the next knight
            Balance.knight.hp = 150
            game.applyScenario("dungeon")
        }],
        [() => game.player && game.levelType === "dungeon", () => {
            check(game.player.maxHp === 150 && game.player.hp === 150,
                  "a changed knight.hp reaches the next knight (" + game.player.maxHp + ")")
            Balance.knight.hp = 120
            console.log("[Balance] done,", failures, "failed")
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
                    console.log("[Balance] FAIL step", i, "timed out")
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
