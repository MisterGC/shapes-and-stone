// Balance bench - every fight number comes from the Balance table (issue #32).
//
// Reads the whole table the way the inspector does, then builds a dungeon,
// the fight room and the village and checks that the knight, every enemy,
// the fight room lineup and the campfire carry the table's values; at
// depth 0, 2 and 4 the dungeon holds more enemies, a higher tier mix and
// harder blows, as the table's depth group says; the
// campfire refills a dry knight's mana, away from it nothing does, and the
// next level, either way it is reached, keeps the knight's HP and mana. Last it
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
        let atk = t.atk + Math.round(game.depth * Balance.depth.atk)
        return e.maxHp === hp && e.atk === atk && e.def === t.def
            && near(e.chaseSpeed, t.chaseSpeed) && near(e.patrolSpeed, t.patrolSpeed)
            && near(e.lungeRange, Balance.enemy.lungeRange)
            && near(e.windUpDuration, Balance.enemy.windUp)
            && near(e.shootCooldown, Balance.enemy.shootCooldown)
            && near(e.shieldArc, Balance.enemy.shieldArc)
    }

    property var campfire: null
    property var _left: null    // the knight of the level just left
    property int hpBefore: 0
    property var byDepth: []    // [depth, enemies, average tier, grunt atk]

    // The dungeon at depth d holds the table's count and tier mix there
    function checkDepth(d) {
        let es = game.enemies, n = es.length, sb = game.spawnRolls(d)
        let weak = es.filter(e => e.tier === 0).length
        let tough = es.filter(e => e.tier === 2).length
        let avg = es.reduce((s, e) => s + e.tier, 0) / n
        byDepth.push([d, n, avg, game.enemyAtk("grunt", d)])
        check(game.depth === d && n >= sb.enemiesMin && n <= sb.enemiesMax,
              "at depth " + d + " the dungeon spawns " + n + " enemies, within "
              + sb.enemiesMin + " to " + sb.enemiesMax)
        check(weak === Math.round(n * sb.weakChance)
              && tough === Math.min(n - weak, Math.round(n * (1 - sb.normalChance))),
              "at depth " + d + " its tier mix is the table's (" + weak + " weak, "
              + tough + " tough, average tier " + avg.toFixed(2) + ")")
        let wrong = es.filter(e => !checkEnemy(e))
        check(wrong.length === 0, "at depth " + d + " every enemy carries the table's stats ("
              + wrong.map(e => e.enemyType + "/" + e.tier + " atk " + e.atk).join(", ") + ")")
    }

    property var steps: [
        [() => game.screen === "title", () => {
            let json = JSON.parse(JSON.stringify(Balance))
            let groups = ["knight", "enemy", "projectile", "spawn", "depth", "campfire"]
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
            let v = null
            for (let i = 0; i < p.children.length; i++)
                if (typeof p.children[i].parry === "function") v = p.children[i]
            check(v && near(v.swingDuration, k.swingDuration) && near(v.swingFade, k.swingFade),
                  "the swing and the fade of its arc, which it hits until, come from the table")
            let n = game.enemies.length
            check(n >= Balance.spawn.enemiesMin && n <= Balance.spawn.enemiesMax,
                  "the dungeon spawns " + n + " enemies, within the table's "
                  + Balance.spawn.enemiesMin + " to " + Balance.spawn.enemiesMax)
            let wrong = game.enemies.filter(e => !checkEnemy(e))
            check(wrong.length === 0, "every enemy's HP, attack, defense and timings come from the table ("
                  + wrong.map(e => e.enemyType + "/" + e.tier + " hp " + e.maxHp).join(", ") + ")")
            let weak = game.enemies.filter(e => e.tier === 0)
            check(weak.length > 0 && weak.every(e => e.maxHp === Balance.enemy.tierHp[0]
                                                    + Balance.enemy[e.enemyType].hpBonus),
                  "a weak enemy spawns weak (" + weak.length + " with the weak tier's HP)")
            checkDepth(0)
            game.applyScenario("dungeon", 2)
        }],
        [() => game.player && game.depth === 2 && game.enemies.length > 0, () => {
            checkDepth(2)
            game.applyScenario("dungeon", 4)
        }],
        [() => game.player && game.depth === 4 && game.enemies.length > 0, () => {
            checkDepth(4)
            let rising = byDepth.every((r, i) => i === 0
                || (r[1] > byDepth[i - 1][1] && r[2] > byDepth[i - 1][2] && r[3] > byDepth[i - 1][3]))
            check(rising, "deeper is harder: enemies, average tier and attack rise from depth 0 to 2 to 4 ("
                  + byDepth.map(r => "depth " + r[0] + ": " + r[1] + " enemies, tier "
                                + r[2].toFixed(2) + ", grunt atk " + r[3]).join("; ") + ")")
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
                  && near(campfire.manaRate, Balance.campfire.manaPerSecond)
                  && near(campfire.healRadius, Balance.campfire.healRadius),
                  "the campfire's heal rate, mana rate and radius come from the table")
            // Hurt and dry, away from the fire
            game.player.xWu = campfire.xWu + Balance.campfire.healRadius + 4
            game.player.yWu = campfire.yWu
            game.player.mana = 0
        }],
        [1000, () => {
            check(game.player.mana === 0,
                  "a dry knight away from the fire gets no mana back (" + game.player.mana + ")")
            // Hurt and dry, at the fire
            game.player.xWu = campfire.xWu
            game.player.yWu = campfire.yWu
            game.player.hp = 60
            hpBefore = 60
            game.player.mana = 0
        }],
        [2000, () => {
            let healed = game.player.hp - hpBefore
            let want = 2 * Balance.campfire.healPerSecond
            check(healed >= want - 2 && healed <= want + 1,
                  "two seconds at the fire heal " + healed + " HP, the table says " + want)
            let refilled = game.player.mana
            let wantMana = 2 * Balance.campfire.manaPerSecond
            let tick = Balance.campfire.manaPerSecond * Balance.campfire.healTick
            check(refilled >= wantMana - 2 * tick && refilled <= wantMana + tick,
                  "two seconds at the fire refill " + refilled.toFixed(1)
                  + " mana, the table says " + wantMana)
            // The next level keeps what the knight had; away from the fire,
            // whose next tick would heal it before the level changes
            game.player.xWu = campfire.xWu + Balance.campfire.healRadius + 4
            game.player.hp = 70
            game.player.mana = 7
            _left = game.player
            game._applyLevelChange(game.levelIndex + 1)
        }],
        [() => game.player && game.player !== _left && !game.resetting, () => {
            check(game.levelType === "dungeon" && game.player.hp === 70 && game.player.mana === 7,
                  "the next level keeps the knight's HP and mana (" + game.player.hp
                  + " HP, " + game.player.mana + " mana)")
            game.player.hp = 80
            game.player.mana = 3
            _left = game.player
            game.resetDungeon()
            check(game.player !== _left && game.player.hp === 80 && game.player.mana === 3,
                  "a reset to the next level keeps them too (" + game.player.hp
                  + " HP, " + game.player.mana + " mana)")
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
