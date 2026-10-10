// Gold bench - kills drop gold, a knight picks it up and the HUD shows it;
// in a session the host owns the drops and each is picked up once, by one
// knight (issue #38).
//
// First one knight alone: the HUD shows "Gold 0", a kill drops the gold of
// the enemy's tier, the knight picks it up and the HUD shows it, and the
// village keeps it. There, with E at the innkeeper and 1 in the dialogue
// panel, it buys a potion: the gold drops by its price, and 1 outside the
// panel heals. The smith sells one level per camp, among them the
// sharpened sword (more atk) and the reinforced shield (a held block lets
// less through and costs less mana), and refuses a second there; the next
// level keeps gold, potions and the level. Then a host and a joiner in one process, joined over
// LAN: a drop the joiner's knight killed goes to the host's knight that
// picks it up, one the host killed to the joiner's, one both knights stand
// on to exactly one of them, and a late claim for a drop already taken
// gives nothing. Prints one PASS or FAIL line per check and exits with the
// number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/gold/gold.qml

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Network
import "../../src"

Window {
    id: bench
    width: 1000
    height: 500
    visible: true
    color: "#1a1a2e"

    property var solo: null
    property var host: null
    property var joiner: null
    property var hostNet: null
    property var joinNet: null
    property int failures: 0

    readonly property int seed: 424242
    // A record of its own: the bench keeps no best depth of the player's
    readonly property string storeName: "ShapesAndStoneGoldBench"

    function check(ok, what) {
        console.log("[Gold]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    property var gameComponent: null
    Component.onCompleted: {
        gameComponent = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComponent.status !== Component.Ready) {
            console.log("[Gold] FAIL", gameComponent.errorString())
            Qt.exit(1)
            return
        }
        solo = gameComponent.createObject(bench.contentItem, {width: 1000, height: 500, muted: true,
                                                              recordStoreName: storeName})
        script.start()
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
    function hudGold(game) { return find(game, "hudGold") }
    function panel(game) {
        for (let i = 0; i < game.data.length; i++)
            if (game.data[i] && typeof game.data[i].advance === "function"
                && game.data[i].wares !== undefined) return game.data[i]
        return null
    }
    function panelText(game) { return find(panel(game), "dialogueText").text }
    function npc(game, name) {
        let kids = game.room.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i].objectName === "npc" && kids[i].npcName === name) return kids[i]
        return null
    }

    // The game's Session and its Network, found by what they offer
    function session(game) {
        for (let i = 0; i < game.data.length; i++)
            if (typeof game.data[i].sendImpact === "function") return game.data[i]
        return null
    }
    function network(game) {
        let s = session(game)
        if (!s) return null
        for (let i = 0; i < s.data.length; i++)
            if (typeof s.data[i].join === "function" && s.data[i].signalingMode !== undefined)
                return s.data[i]
        return null
    }

    function liveEnemies(game) { return game.enemies.filter(e => e && !e.destroyed) }
    function enemyById(game, id) { return liveEnemies(game).find(e => e.objectId === id) }
    function dropById(game, id) { return game.goldDrops.find(d => d && d.objectId === id) }
    // Stand the knight on (x, y), or well away from it
    function standAt(knight, x, y) { knight.xWu = x; knight.yWu = y }
    function standAway(knight, x, y) { knight.xWu = x + 6; knight.yWu = y }
    function haltAll(game) { for (let e of liveEnemies(game)) e.halt() }

    // --- One knight alone ---
    property int soloTier: -1
    property int soloAmount: 0
    property var soloSteps: [
        [() => solo.width > 0, () => solo.applyScenario("dungeon", 0)],
        [() => solo.player && liveEnemies(solo).length > 0, () => {
            haltAll(solo)
            let h = hudGold(solo)
            check(h && h.visible && h.text === "Gold 0",
                  "the HUD shows \"Gold 0\" at the start of a run (" + (h ? h.text : "none") + ")")
            let e = liveEnemies(solo)[0]
            soloTier = e.tier
            soloAmount = Balance.loot.goldByTier[e.tier]
            standAway(solo.player, e.xWu, e.yWu)
            e.takeDamage(100000, e.xWu + 1, e.yWu)
        }],
        [() => solo.goldDrops.length === 1, () => {
            let d = solo.goldDrops[0]
            check(d.amount === soloAmount && d.amount > 0,
                  "the kill drops the gold of the enemy's tier " + soloTier + " (" + d.amount
                  + ", the table says " + soloAmount + ")")
            check(solo.player.gold === 0, "the gold lies on the floor until the knight picks it up")
            standAt(solo.player, d.xWu, d.yWu)
        }],
        [() => solo.goldDrops.length === 0, () => {
            check(solo.player.gold === soloAmount,
                  "the knight picked the drop up (" + solo.player.gold + " gold)")
            check(hudGold(solo).text === "Gold " + soloAmount,
                  "the kill raised the HUD's gold (" + hudGold(solo).text + ")")
            solo._enterLevel(solo.levelIndex + 1)
        }],
        [() => solo.player && solo.levelType === "village", () => {
            check(solo.player.gold === soloAmount && hudGold(solo).text === "Gold " + soloAmount,
                  "the village keeps the knight's gold (" + hudGold(solo).text + ")")
            // More gold for the shopping, as if from more kills
            solo.player.gold = Balance.shop.potionPrice + Balance.shop.upgradePrice[0] + 2
            let inn = npc(solo, "Innkeeper")
            standAt(solo.player, inn.xWu, inn.yWu - 1)
        }],
        [() => npc(solo, "Innkeeper").nearbyPlayer !== null, () => {
            solo.forceActiveFocus()
            press(Qt.Key_E)
        }],
        [() => panel(solo).visible, () => {
            let p = panel(solo)
            check(p.speakerName === "Innkeeper" && p.wares.length === 2 && p.wares[0].id === "potion"
                  && p.wares[0].price === Balance.shop.potionPrice && p.wares[1].id === "draught",
                  "E at the innkeeper opens the dialogue panel, which offers a potion for "
                  + Balance.shop.potionPrice + " gold, and a mana draught")
            gold0 = solo.player.gold
            press(Qt.Key_1)
            check(solo.player.gold === gold0 - Balance.shop.potionPrice && solo.player.potions === 1,
                  "1 in the panel buys a potion: the gold drops by its price (" + gold0 + " -> "
                  + solo.player.gold + "), one potion")
            check(hudGold(solo).text === "Gold " + solo.player.gold,
                  "the HUD shows the gold left (" + hudGold(solo).text + ")")
            check(find(solo, "hudPotions").visible && find(solo, "hudPotions").text === "Potions 1  [1]",
                  "the HUD shows the potion (" + find(solo, "hudPotions").text + ")")
            // Not enough gold for a second one plus the smith's upgrade:
            // spend down to just below the price
            let keep = solo.player.gold
            solo.player.gold = Balance.shop.potionPrice - 1
            press(Qt.Key_1)
            check(solo.player.gold === Balance.shop.potionPrice - 1 && solo.player.potions === 1,
                  "without enough gold 1 buys nothing (\"" + panelText(solo) + "\")")
            solo.player.gold = keep
            // E through the lines closes the panel
            for (let i = 0; i < 6 && p.visible; i++) press(Qt.Key_E)
            check(!p.visible, "E through the innkeeper's lines closes the panel")
            solo.player.hp = 20
            press(Qt.Key_1)
        }],
        [() => true, () => {
            let heal = Balance.shop.potionHeal
            check(solo.player.hp === 20 + heal && solo.player.potions === 0,
                  "1 outside the panel drinks the potion: HP 20 -> " + solo.player.hp + " (+" + heal + ")")
            press(Qt.Key_1)
            check(solo.player.hp === 20 + heal, "with no potion left 1 heals nothing")
            let smith = npc(solo, "Blacksmith")
            standAt(solo.player, smith.xWu, smith.yWu - 1)
        }],
        [() => npc(solo, "Blacksmith").nearbyPlayer !== null, () => press(Qt.Key_E)],
        [() => panel(solo).visible, () => {
            let p = panel(solo)
            check(p.speakerName === "Blacksmith" && p.wares.length === 4
                  && p.wares[0].id === "sword" && p.wares[1].id === "shield"
                  && p.wares[0].label.indexOf("+" + Balance.shop.swordAtk[0] + " damage") >= 0
                  && p.wares[1].label.indexOf(Math.round(Balance.shop.shieldBlockedShare[0] * 100) + " %") >= 0
                  && p.wares[1].label.indexOf("costs " + Balance.shop.shieldBlockMana[0] + " mana") >= 0,
                  "the smith offers the sword and the shield, each with its effect (\""
                  + p.wares.map(w => w.label).join("\", \"") + "\")")
            gold0 = solo.player.gold
            press(Qt.Key_1)
            let k = solo.player
            check(k.swordLevel === 1 && k.atk === 20 && k.atk === Balance.knight.atk + Balance.shop.swordAtk[0]
                  && k.maxHp === Balance.knight.hp && k.gold === gold0 - Balance.shop.upgradePrice[0],
                  "1 buys the sharpened sword (level " + k.swordLevel + ", atk " + k.atk
                  + ", gold " + gold0 + " -> " + k.gold + ")")
            check(p.wares.length === 0, "after one level the smith offers none more at this camp")
            gold0 = k.gold
            press(Qt.Key_2)
            let again = solo.buyWare({ id: "shield", price: Balance.shop.upgradePrice[0] })
            check(!again && k.swordLevel === 1 && k.shieldLevel === 0 && k.gold === gold0,
                  "a second purchase is refused (sword " + k.swordLevel + ", shield " + k.shieldLevel
                  + ", gold " + k.gold + ", \"" + panelText(solo) + "\")")
            for (let i = 0; i < 6 && p.visible; i++) press(Qt.Key_E)
            k.potions = 2
            solo._enterLevel(solo.levelIndex + 1)
        }],
        [() => solo.player && solo.levelType === "dungeon", () => {
            let k = solo.player
            check(k.gold === gold0 && k.potions === 2 && k.swordLevel === 1 && k.atk === 20,
                  "the next level keeps gold, potions and the sword (" + k.gold + " gold, " + k.potions
                  + " potions, atk " + k.atk + ")")
            solo.newRun()
        }],
        [() => solo.player && solo.levelIndex === 0, () => {
            let k = solo.player
            check(k.gold === 0 && k.potions === 0 && k.swordLevel === 0 && k.atk === Balance.knight.atk
                  && k.blockedShare === Balance.knight.blockedShare && k.blockMana === Balance.knight.blockMana,
                  "a new run starts without gold, potions or the smith's levels")
            solo._enterLevel(1)
        }],
        [() => solo.player && solo.levelType === "village", () => {
            solo.player.gold = Balance.shop.upgradePrice[0]
            let smith = npc(solo, "Blacksmith")
            standAt(solo.player, smith.xWu, smith.yWu - 1)
        }],
        [() => npc(solo, "Blacksmith").nearbyPlayer !== null, () => press(Qt.Key_E)],
        [() => panel(solo).visible, () => {
            let p = panel(solo)
            press(Qt.Key_2)
            let k = solo.player
            check(k.shieldLevel === 1 && k.atk === Balance.knight.atk && k.gold === 0,
                  "2 buys the reinforced shield (level " + k.shieldLevel + ", atk " + k.atk + ")")
            k.gold = Balance.shop.upgradePrice[0]
            press(Qt.Key_1)
            check(k.shieldLevel === 1 && k.swordLevel === 0 && k.gold === Balance.shop.upgradePrice[0],
                  "1 at the smith then buys no sword")
            for (let i = 0; i < 6 && p.visible; i++) press(Qt.Key_E)
            // A 20-atk blow on the held shield, from the front, past the
            // perfect block's window
            k.graceLeft = 0
            k.facingAngle = 0
            k.raiseShield()
            k._raisedAt = k._steps - Balance.knight.perfectBlockFrames - 1
            let hp = k.hp
            let manaBefore = k.mana
            let res = k.takeDamage(20, k.xWu + 1, k.yWu)
            let share = Math.floor((20 - k.def) * 0.15)
            check(res === "blocked" && hp - k.hp === share
                  && share === Math.floor((20 - k.def) * Balance.shop.shieldBlockedShare[0]),
                  "a held block of a 20-atk blow lets " + (hp - k.hp) + " of " + (20 - k.def)
                  + " through (15 %: " + share + ")")
            check(Math.abs(manaBefore - k.mana - 4) < 1e-6
                  && Math.abs(manaBefore - k.mana - Balance.shop.shieldBlockMana[0]) < 1e-6,
                  "the blocked blow costs the reinforced shield " + (manaBefore - k.mana).toFixed(2) + " mana")
            steps0 = k._steps
        }],
        // The drain, measured once the blow's hit stop is over
        [() => solo.player._steps - steps0 >= 30, () => {
            let k = solo.player
            k.mana = k.maxMana
            mana0 = k.mana
            steps0 = k._steps
            drainSecs = 0
            measuring = true
        }],
        [() => solo.player._steps - steps0 >= 60, () => {
            let k = solo.player
            measuring = false
            let secs = drainSecs
            let drain = (mana0 - k.mana) / secs
            check(k.isBlocking && Math.abs(drain - Balance.knight.blockDrain) < 0.05,
                  "the held reinforced shield drains " + drain.toFixed(2) + " mana/s over " + secs.toFixed(2)
                  + " s, as any shield does")
            k.lowerShield()
            // The levels are read live: set one, and its effects follow at once
            k.shieldLevel = 0
            k.swordLevel = 1
            let sword = k.atk === 20 && k.blockedShare === Balance.knight.blockedShare
                && k.blockMana === Balance.knight.blockMana
            k.swordLevel = 0
            k.shieldLevel = 1
            let shield = k.atk === Balance.knight.atk && k.blockedShare === Balance.shop.shieldBlockedShare[0]
                && k.blockMana === Balance.shop.shieldBlockMana[0]
            check(sword && shield, "setting swordLevel or shieldLevel applies the sword or the shield at once")
        }],
        [100, () => solo.destroy()]
    ]
    property int gold0: 0
    property real mana0: 0
    property int steps0: 0
    // The simulated seconds the drain is measured over, step by step: a
    // step's length is the world's timeStep at that step
    property bool measuring: false
    property real drainSecs: 0
    Connections {
        target: solo && solo.player ? solo.player.world : null
        function onStepped() { if (bench.measuring) bench.drainSecs += target.timeStep }
    }

    // --- A host and a joiner ---
    property string dropId: ""
    property int dropAmount: 0
    property int hostGold0: 0
    property int joinGold0: 0
    // Kill a live enemy of the host's from the given screen
    function killOne(game) {
        let e = liveEnemies(game)[0]
        console.log("[Gold] killing", e.objectId, "tier", e.tier, "from the",
                    game === host ? "host" : "joiner")
        e.takeDamage(100000, e.xWu + 1, e.yWu)
        hostGold0 = host.player.gold
        joinGold0 = joiner.player.gold
    }
    // The one drop, the same on both screens
    function oneDrop() {
        return host.goldDrops.length === 1 && joiner.goldDrops.length === 1
            && host.goldDrops[0].objectId === joiner.goldDrops[0].objectId
    }
    function noteDrop() {
        let d = host.goldDrops[0]
        dropId = d.objectId
        dropAmount = d.amount
        return d
    }
    function dropGone() { return !dropById(host, dropId) && !dropById(joiner, dropId) }

    property var coopSteps: [
        [() => true, () => {
            host = gameComponent.createObject(bench.contentItem, {width: 500, height: 500, muted: true,
                                                                  recordStoreName: storeName})
            joiner = gameComponent.createObject(bench.contentItem, {x: 500, width: 500, height: 500,
                                                                    muted: true, recordStoreName: storeName})
            hostNet = network(host)
            joinNet = network(joiner)
            hostNet.signalingMode = Network.SignalingMode.Local
            hostNet.host()
        }],
        [() => hostNet.networkId !== "", () => joinNet.join(hostNet.networkId)],
        [() => hostNet.connected && joinNet.connected && hostNet.nodeCount >= 2, () => {
            host.masterSeed = seed
            host._startMultiplayerGame()
        }],
        [() => host.player && joiner.player && host.screen === "game" && joiner.screen === "game"
               && liveEnemies(host).length > 2 && liveEnemies(joiner).length === liveEnemies(host).length,
         () => {
            haltAll(host)
            host.player.hp = 100000
            joiner.player.hp = 100000
            check(host.player.gold === 0 && joiner.player.gold === 0, "both knights start with no gold")
            // The joiner's knight kills; the host's picks the gold up
            let e = liveEnemies(joiner)[0]
            standAway(host.player, e.xWu, e.yWu)
            standAway(joiner.player, e.xWu, e.yWu - 3)
            killOne(joiner)
        }],
        [() => oneDrop(), () => {
            let d = noteDrop()
            check(dropId.indexOf(hostNet.nodeId + ":") === 0,
                  "the drop of the joiner's kill is an object the host spawned (" + dropId + ")")
            check(dropById(joiner, dropId).amount === dropAmount,
                  "both screens have the drop with the same " + dropAmount + " gold")
            standAt(host.player, d.xWu, d.yWu)
        }],
        [() => dropGone(), () => {}],
        [300, () => {
            check(host.player.gold === hostGold0 + dropAmount && joiner.player.gold === joinGold0,
                  "the gold of the joiner's kill went to the host's knight that picked it up (host "
                  + host.player.gold + ", joiner " + joiner.player.gold + ")")
            // The host's knight kills; the joiner's picks the gold up
            let e = liveEnemies(host)[0]
            standAway(host.player, e.xWu, e.yWu)
            standAway(joiner.player, e.xWu, e.yWu - 3)
            killOne(host)
        }],
        [() => oneDrop(), () => {
            let d = noteDrop()
            standAt(joiner.player, d.xWu, d.yWu)
        }],
        [() => dropGone(), () => {}],
        [300, () => {
            check(joiner.player.gold === joinGold0 + dropAmount && host.player.gold === hostGold0,
                  "the gold of the host's kill went to the joiner's knight that picked it up (host "
                  + host.player.gold + ", joiner " + joiner.player.gold + ")")
            check(hudGold(joiner).text === "Gold " + joiner.player.gold,
                  "the joiner's HUD shows its own gold (" + hudGold(joiner).text + ")")
            let e = liveEnemies(host)[0]
            standAway(host.player, e.xWu, e.yWu)
            standAway(joiner.player, e.xWu, e.yWu - 3)
            killOne(host)
        }],
        // Both knights on the same drop in the same frame
        [() => oneDrop(), () => {
            let d = noteDrop()
            standAt(joiner.player, d.xWu, d.yWu)
            standAt(host.player, d.xWu, d.yWu)
        }],
        [() => dropGone(), () => {}],
        [300, () => {
            let hostGot = host.player.gold - hostGold0, joinGot = joiner.player.gold - joinGold0
            check(hostGot + joinGot === dropAmount && (hostGot === 0 || joinGot === 0),
                  "a drop both knights stand on is picked up once, by one knight (host +" + hostGot
                  + ", joiner +" + joinGot + " of " + dropAmount + ")")
            hostGold0 = host.player.gold
            joinGold0 = joiner.player.gold
            // A claim that comes after the drop was taken
            session(joiner).claimGold(dropId)
        }],
        [300, () => {
            check(host.player.gold === hostGold0 && joiner.player.gold === joinGold0,
                  "a claim for a drop already taken gives no gold (host " + host.player.gold
                  + ", joiner " + joiner.player.gold + ")")
            hostNet.leave()
            joinNet.leave()
        }],
        // Torn down before quitting: the game crashes when Qt quits with it
        // still up, and the crash's exit code would hide the result
        [300, () => { host.destroy(); joiner.destroy() }]
    ]

    property var steps: soloSteps.concat(coopSteps).concat([
        [300, () => {
            console.log("[Gold] done,", failures, "failed")
            Qt.exit(failures)
        }]
    ])

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
                    console.log("[Gold] FAIL step", i, "timed out")
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
