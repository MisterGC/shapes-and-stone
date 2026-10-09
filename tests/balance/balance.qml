// Balance bench - every fight number comes from the Balance table (issue #32).
//
// Reads the whole table the way the inspector does, then builds a dungeon,
// the fight room and the village and checks that the knight, every enemy,
// the fight room lineup and the campfire carry the table's values; at
// depth 0, 2 and 4 the dungeon holds more enemies, a higher tier mix and
// harder blows, as the table's depth group says; tough grunts and
// guardians, and no other enemy, wind up a crushing blow at
// enemy.crushChance, for enemy.crushWindUp, and one on a held shield
// takes enemy.crushMana, enemy.crushShare of the damage and drops the
// shield for enemy.crushLockout; the smith sells the sword and the shield
// for shop.upgradePrice, which take the shop's values; the
// campfire refills a dry knight's mana on top of the rest's knight.manaRegen,
// away from it only the rest does, and the
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
            && near(e.crushChance, crushChanceOf(e))
    }
    // Tough grunts and guardians wind up crushing blows, no other enemy
    function crushChanceOf(e) {
        return e.tier === 2 && e.enemyType !== "spitter" ? Balance.enemy.crushChance : 0
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
            let groups = ["knight", "enemy", "projectile", "spawn", "depth", "campfire", "shop"]
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

            // The tough guardian winds up crushing blows at the table's
            // chance, the others none; a crushing wind-up lasts crushWindUp
            let be = Balance.enemy
            let gd = es.find(e => e.enemyType === "guardian")
            check(near(gd.crushChance, be.crushChance) && es.filter(e => e !== gd).every(e => e.crushChance === 0),
                  "the tough guardian winds up crushing blows at crushChance " + gd.crushChance
                  + ", the table says " + be.crushChance + "; the normal grunts and the spitter at "
                  + es.filter(e => e !== gd).map(e => e.crushChance).join(", "))
            gd.target = null
            gd.crushChance = 1
            gd.windUp(be.windUp)
            let crushWindUp = gd._attackTimer, crushState = gd.aiState
            gd.crushChance = 0
            gd.windUp(be.windUp)
            check(crushState === "crush" && near(crushWindUp, be.crushWindUp)
                  && gd.aiState === "telegraph" && near(gd._attackTimer, be.windUp),
                  "a crushing blow winds up for " + crushWindUp + " s (" + crushState + "), the table says "
                  + be.crushWindUp + "; a lunge for " + gd._attackTimer + " s")
            gd.aiState = "patrol"
            gd.crushChance = be.crushChance
            // A crushing blow on the held shield, from the front
            let p = game.player
            p.graceLeft = 0
            p.mana = p.maxMana
            p.facingAngle = 0
            p.raiseShield()
            p._raisedAt = p._steps - Balance.knight.perfectBlockFrames - 1
            let hp = p.hp
            let res = p.takeDamage(20, p.xWu + 1, p.yWu, undefined, true)
            let share = Math.floor((20 - p.def) * be.crushShare)
            check(res === "crushed" && near(p.maxMana - p.mana, be.crushMana) && hp - p.hp === share
                  && near(p.shieldLock, be.crushLockout) && !p.isBlocking,
                  "on a held shield it takes " + (p.maxMana - p.mana) + " mana (crushMana " + be.crushMana
                  + "), " + (hp - p.hp) + " of " + (20 - p.def) + " HP (crushShare " + be.crushShare
                  + ") and drops the shield for " + p.shieldLock + " s (crushLockout " + be.crushLockout + ")")
            p.lowerShield()
            game.applyScenario("village")
        }],
        [() => game.player && game.levelType === "village", () => {
            campfire = game.dungeonObjects.find(o => o && o.healRadius !== undefined)
            check(campfire && near(campfire.healRate, Balance.campfire.healPerSecond)
                  && near(campfire.manaRate, Balance.campfire.manaPerSecond)
                  && near(campfire.healRadius, Balance.campfire.healRadius),
                  "the campfire's heal rate, mana rate and radius come from the table")
            // The smith's wares and what they do: the table's shop group
            let shop = Balance.shop, p = game.player
            check(shop.upgradePrice === 30 && shop.swordAtk === 5 && near(shop.shieldBlockedShare, 0.15)
                  && shop.shieldBlockMana === 4,
                  "the shop's upgradePrice " + shop.upgradePrice + ", swordAtk " + shop.swordAtk
                  + ", shieldBlockedShare " + shop.shieldBlockedShare + ", shieldBlockMana " + shop.shieldBlockMana)
            let smith = game.room.children.find(c => c.objectName === "npc" && c.npcName === "Blacksmith")
            let wares = smith ? smith.wares : []
            check(wares.length === 2 && wares[0].id === "sword" && wares[1].id === "shield"
                  && wares.every(w => w.price === shop.upgradePrice),
                  "the smith sells the sword and the shield for upgradePrice ("
                  + wares.map(w => w.id + " " + w.price).join(", ") + ")")
            p.upgrade = "sword"
            let sword = p.atk === Balance.knight.atk + shop.swordAtk
                && near(p.blockedShare, Balance.knight.blockedShare) && near(p.blockMana, Balance.knight.blockMana)
            p.upgrade = "shield"
            let shield = p.atk === Balance.knight.atk && near(p.blockedShare, shop.shieldBlockedShare)
                && near(p.blockMana, shop.shieldBlockMana) && near(p.blockDrain, Balance.knight.blockDrain)
            p.upgrade = ""
            check(sword && shield && p.atk === Balance.knight.atk
                  && near(p.blockedShare, Balance.knight.blockedShare) && near(p.blockMana, Balance.knight.blockMana),
                  "the sharpened sword adds swordAtk, the reinforced shield takes shieldBlockedShare and shieldBlockMana")
            // Hurt and dry, away from the fire
            game.player.xWu = campfire.xWu + Balance.campfire.healRadius + 4
            game.player.yWu = campfire.yWu
            game.player.mana = 0
        }],
        [1000, () => {
            // A second of wall clock: the rest's mana, no more
            let rest = game.player.mana
            check(rest >= 0.5 * Balance.knight.manaRegen && rest <= 1.3 * Balance.knight.manaRegen,
                  "a dry knight away from the fire gets only the rest's mana back (" + rest.toFixed(2)
                  + " in a second, the table says " + Balance.knight.manaRegen + ")")
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
            let wantMana = 2 * (Balance.campfire.manaPerSecond + Balance.knight.manaRegen)
            let tick = Balance.campfire.manaPerSecond * Balance.campfire.healTick
            check(refilled >= wantMana - 2 * tick - Balance.knight.manaRegen * 0.2
                  && refilled <= wantMana + tick + Balance.knight.manaRegen * 0.2,
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
            // The new level's knight rests from its first step: a few
            // steps of manaRegen on top
            let m = game.player.mana
            check(game.levelType === "dungeon" && game.player.hp === 70
                  && m >= 7 && m < 7 + Balance.knight.manaRegen * 0.25,
                  "the next level keeps the knight's HP and mana (" + game.player.hp
                  + " HP, " + m.toFixed(2) + " mana, 7 and the rest's few steps)")
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
