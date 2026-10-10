// Camp bench - the camp prepares the next dungeon: the witch reads it, the
// innkeeper sells a mana draught, the smith's upgrades last the run and
// have levels (issue #98).
//
// On the dojo's seed one knight alone leaves a dungeon three times, having
// lost little, half or most of its HP, and talks to the witch at each camp:
// her reading names the next dungeon's depth and where it sits in its
// range, high, in the middle or low, and its enemies - how many, how many
// tough and weak, how many guardians and spitters - and the dungeon the
// knight walks down into has exactly those. At a camp it buys a mana
// draught with 2 in the innkeeper's panel and drinks it with 2 in the next
// dungeon: the mana comes back. At the first camp the smith offers level I
// of the sword, the shield, the harness and the blade; the knight buys the
// harness and the smith sells nothing more there. Two dungeons later the
// harness still holds - a dash costs its mana - the next camp's smith has
// no harness II (the depth's limit) and the one after sells it. A new run
// starts without. Then a host and a joiner in one process, joined over
// LAN: at the camp both knights hear the same reading, which the next
// dungeon both screens show bears out, and each buys on its own gold.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/camp/camp.qml

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
    readonly property string storeName: "ShapesAndStoneCampBench"

    function check(ok, what) {
        console.log("[Camp]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    property var gameComponent: null
    Component.onCompleted: {
        gameComponent = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComponent.status !== Component.Ready) {
            console.log("[Camp] FAIL", gameComponent.errorString())
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
    function panel(game) {
        for (let i = 0; i < game.data.length; i++)
            if (game.data[i] && typeof game.data[i].advance === "function"
                && game.data[i].wares !== undefined) return game.data[i]
        return null
    }
    function npc(game, name) {
        let kids = game.room.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i].objectName === "npc" && kids[i].npcName === name) return kids[i]
        return null
    }
    function talk(game, name) {
        panel(game).close()
        npc(game, name).interact()
        return panel(game)
    }
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
    function inLevel(game, type) { return game && game.player && game.levelType === type && !game.resetting }

    // The dungeon a screen shows, counted the way the witch counts it
    function census(game) {
        let out = { enemies: 0, weak: 0, normal: 0, tough: 0, grunt: 0, guardian: 0, spitter: 0 }
        for (let e of liveEnemies(game)) {
            out.enemies++
            out[["weak", "normal", "tough"][e.tier]]++
            out[e.enemyType]++
        }
        return out
    }
    function sameCount(a, b) {
        return ["enemies", "weak", "normal", "tough", "grunt", "guardian", "spitter"].every(k => a[k] === b[k])
    }
    function countText(c) {
        return c.enemies + " enemies: " + c.weak + " weak, " + c.normal + " normal, " + c.tough + " tough; "
            + c.grunt + " grunts, " + c.guardian + " guardians, " + c.spitter + " spitters"
    }
    // Whether the reading's lines say what the dungeon holds
    function linesTell(lines, depth, band, c) {
        let says = (i, text, yes) => (lines[i].indexOf(text) >= 0) === yes
        return lines.length >= 3
            && says(0, "Depth " + depth + " waits below", true)
            && says(0, ["low in its range", "in the middle of its range", "high in its range"][band], true)
            && says(1, "I see " + c.enemies + " shapes", true)
            && says(1, c.tough + " of them hulking", c.tough > 0) && says(1, "hulking", c.tough > 0)
            && says(1, c.weak + " feeble", c.weak > 0) && says(1, "feeble", c.weak > 0)
            // Neither guardians nor spitters: "No shields, nothing that spits"
            && says(2, c.guardian + " behind shields", c.guardian > 0)
            && says(2, "shields", c.guardian > 0 || c.spitter === 0)
            && says(2, c.spitter + " that spit", c.spitter > 0)
            && says(2, "spit", c.spitter > 0 || c.guardian === 0)
    }

    // --- The witch, at three camps ---
    // Each case: the danger the dungeon before the camp is entered at, the
    // share of HP lost in it, and the band the next dungeon should get
    readonly property var cases: [
        { at: 0.9, lost: 0.0, band: 2 },
        { at: 1.5, lost: 0.5, band: 1 },
        { at: 3.1, lost: 0.95, band: 0 }
    ]
    property var reading: null
    property var heard: []
    function witchSteps(c) {
        let name = ["low", "middle", "high"][c.band]
        return [
            [() => true, () => solo.applyScenario("dungeon", c.at)],
            [() => inLevel(solo, "dungeon"), () => {
                solo.fightRecord.damageTaken = Math.round(c.lost * solo.player.maxHp)
                solo.fightRecord.deaths = 0
                solo.resetDungeon()
            }],
            [() => inLevel(solo, "village"), () => {
                let p = talk(solo, "Witch")
                heard = p.lines.slice()
                reading = solo.foretell()
                check(p.visible && p.speakerName === "Witch" && heard.length >= 3,
                      "after " + Math.round(c.lost * 100) + "% lost the witch reads the next dungeon (\""
                      + heard.join(" / ") + "\")")
                check(reading.depth === solo.depth + 1 && reading.band === c.band
                      && solo.dangerBand(solo.nextPosition) === c.band,
                      "she reads depth " + reading.depth + " " + name + " in its range (next position "
                      + solo.nextPosition.toFixed(3) + ")")
                p.close()
                solo.resetDungeon()
            }],
            [() => inLevel(solo, "dungeon") && liveEnemies(solo).length > 0, () => {
                let got = census(solo)
                check(solo.depth === reading.depth && solo.dangerBand(solo.dangerPosition) === c.band,
                      "the next dungeon is depth " + solo.depth + ", " + name + " in its range ("
                      + solo.danger.toFixed(3) + ")")
                check(sameCount(got, reading),
                      "it holds what she read: " + countText(got) + " (read: " + countText(reading) + ")")
                check(linesTell(heard, solo.depth, c.band, got),
                      "her words say so: \"" + heard.slice(0, 3).join(" / ") + "\"")
            }]
        ]
    }

    // --- The innkeeper's draught and the smith's levels ---
    property int gold0: 0
    property real mana0: 0
    property var soloSteps: [].concat(witchSteps(cases[0]), witchSteps(cases[1]), witchSteps(cases[2]), [
        // The first camp of a run: depth 0
        [() => true, () => solo.applyScenario("village", 0.5)],
        [() => inLevel(solo, "village"), () => {
            solo.forceActiveFocus()
            solo.player.gold = Balance.shop.draughtPrice
            let p = talk(solo, "Innkeeper")
            let w = p.wares.find(x => x.id === "draught")
            check(p.wares.length === 2 && p.wares[1] === w && w.price === Balance.shop.draughtPrice
                  && w.label.indexOf("+" + Balance.shop.draughtMana + " mana") >= 0,
                  "the innkeeper offers a mana draught next to the potion (\"" + (w ? w.label : "none")
                  + "\" for " + (w ? w.price : "-") + " gold)")
            press(Qt.Key_2)
            let k = solo.player
            let hud = find(solo, "hudDraughts")
            check(k.draughts === 1 && k.gold === 0 && k.potions === 0,
                  "2 in the panel buys the draught with the knight's gold (" + k.draughts + " draught, "
                  + k.gold + " gold left)")
            check(hud.visible && hud.text === "Draughts 1  [2]", "the HUD shows it (" + hud.text + ")")
            p.close()
            // The smith of the first camp: level I of each, nothing higher
            k.gold = 1000
            gold0 = k.gold
            p = talk(solo, "Blacksmith")
            let ids = p.wares.map(x => x.id).join(", ")
            check(ids === "sword, shield, harness, blade" && p.wares.every(x => x.level === 1
                      && x.price === Balance.shop.upgradePrice[0]),
                  "the first camp's smith offers level I of the sword, the shield, the harness and the blade ("
                  + p.wares.map(x => x.label + " " + x.price).join("; ") + ")")
            let harness = p.wares[2]
            check(harness.label.indexOf("a dash costs " + Balance.shop.harnessDashMana[0] + " mana") >= 0
                  && p.wares[3].label.indexOf("a whirlwind costs " + Balance.shop.bladeWhirlMana[0] + " mana") >= 0,
                  "the harness and the blade say what they make cheaper (\"" + harness.label + "\", \""
                  + p.wares[3].label + "\")")
            press(Qt.Key_3)
            check(k.harnessLevel === 1 && k.gold === gold0 - Balance.shop.upgradePrice[0]
                  && k.dashMana === Balance.shop.harnessDashMana[0],
                  "3 buys the lighter harness I (dash " + k.dashMana + " mana, gold " + gold0 + " -> " + k.gold + ")")
            gold0 = k.gold
            let more = solo.buyWare({ id: "sword", price: Balance.shop.upgradePrice[0] })
            check(p.wares.length === 0 && !more && k.swordLevel === 0 && k.gold === gold0,
                  "one level per camp: then the smith offers nothing and sells no sword")
            p.close()
            solo.resetDungeon()
        }],
        // The draught, in the dungeon
        [() => inLevel(solo, "dungeon"), () => {
            let k = solo.player
            check(k.draughts === 1 && k.harnessLevel === 1, "the next dungeon keeps the draught and the harness")
            k.mana = 5
            press(Qt.Key_2)
            check(k.draughts === 0 && k.mana === Math.min(k.maxMana, 5 + Balance.shop.draughtMana),
                  "2 in the dungeon drinks it: mana 5 -> " + k.mana + " of " + k.maxMana)
            k.draughts = 1
            press(Qt.Key_2)
            check(k.draughts === 1, "with the mana full a draught is not wasted")
            solo.resetDungeon()
        }],
        // The camp after depth 1: no level II yet
        [() => inLevel(solo, "village"), () => {
            let p = talk(solo, "Blacksmith")
            let ids = p.wares.map(x => x.id + " " + x.level).join(", ")
            check(solo.depth < Balance.shop.levelDepth[1] && ids === "sword 1, shield 1, blade 1",
                  "the camp after depth " + solo.depth + " offers no harness II, above its limit (" + ids + ")")
            check(!solo.buyWare({ id: "harness" }) && solo.player.harnessLevel === 1,
                  "nor sells it when asked")
            press(Qt.Key_3)
            check(solo.player.bladeLevel === 1 && solo.player.whirlMana === Balance.shop.bladeWhirlMana[0],
                  "3 buys the balanced blade I (whirlwind " + solo.player.whirlMana + " mana)")
            p.close()
            solo.resetDungeon()
        }],
        // Two dungeons after the harness
        [() => inLevel(solo, "dungeon"), () => {
            let k = solo.player
            k.mana = k.maxMana
            mana0 = k.mana
            k.dash()
            check(k.harnessLevel === 1 && k.isDashing && Math.abs(mana0 - k.mana - Balance.shop.harnessDashMana[0]) < 1e-6,
                  "two dungeons later the harness still holds: a dash at depth " + solo.depth + " costs "
                  + (mana0 - k.mana).toFixed(2) + " mana, not " + Balance.knight.dashMana)
            solo.resetDungeon()
        }],
        // The camp after depth 2: level II
        [() => inLevel(solo, "village"), () => {
            let p = talk(solo, "Blacksmith")
            let harness = p.wares.find(x => x.id === "harness")
            check(harness && harness.level === 2 && harness.price === Balance.shop.upgradePrice[1]
                  && p.wares.every(x => x.level <= 2),
                  "the camp after depth " + solo.depth + " offers the harness II (\""
                  + (harness ? harness.label : "none") + "\"), nothing above II")
            gold0 = solo.player.gold
            solo.buyWare(harness)
            check(solo.player.harnessLevel === 2 && solo.player.dashMana === Balance.shop.harnessDashMana[1]
                  && solo.player.gold === gold0 - Balance.shop.upgradePrice[1],
                  "the knight buys it: a dash costs " + solo.player.dashMana + " mana")
            p.close()
            let k = solo.player
            k.graceLeft = 0
            k.isBlocking = false
            k.takeDamage(10 * k.maxHp, k.xWu + 1, k.yWu)
        }],
        [() => solo.fallen, () => solo.newRun()],
        [() => inLevel(solo, "dungeon") && solo.levelIndex === 0, () => {
            let k = solo.player
            check(k.harnessLevel === 0 && k.bladeLevel === 0 && k.draughts === 0
                  && k.dashMana === Balance.knight.dashMana && k.whirlMana === Balance.knight.whirlMana,
                  "a new run starts without the smith's levels or draughts")
        }],
        [100, () => solo.destroy()]
    ])

    // --- A host and a joiner ---
    property var hostReading: null
    property var hostHeard: []
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
        [() => inLevel(host, "dungeon") && inLevel(joiner, "dungeon") && liveEnemies(host).length > 0,
         () => host._hostAdvanceLevel()],
        [() => inLevel(host, "village") && inLevel(joiner, "village") && host.levelIndex === joiner.levelIndex,
         () => {
            hostHeard = talk(host, "Witch").lines.slice()
            let joinHeard = talk(joiner, "Witch").lines.slice()
            hostReading = host.foretell()
            check(hostHeard.length >= 3 && JSON.stringify(hostHeard) === JSON.stringify(joinHeard),
                  "both knights hear the same reading (\"" + hostHeard.slice(0, 3).join(" / ") + "\")")
            check(JSON.stringify(hostReading) === JSON.stringify(joiner.foretell()) && hostReading.depth === 1,
                  "for depth " + hostReading.depth + ", for " + host.knightsNow() + " knights: "
                  + countText(hostReading))
            // Each knight's own gold: the host's pays for a draught and the
            // sword, the joiner's for a draught and then not for the sword
            host.player.gold = 100
            joiner.player.gold = Balance.shop.draughtPrice + 5
            let hd = host.buyWare({ id: "draught", price: Balance.shop.draughtPrice })
            let hs = host.buyWare(host.smithWare("sword"))
            let jd = joiner.buyWare({ id: "draught", price: Balance.shop.draughtPrice })
            let js = joiner.buyWare(joiner.smithWare("sword"))
            check(hd && hs && host.player.gold === 100 - Balance.shop.draughtPrice - Balance.shop.upgradePrice[0]
                  && host.player.draughts === 1 && host.player.swordLevel === 1,
                  "the host's knight buys a draught and the sword I on its own gold (" + host.player.gold + " left)")
            check(jd && !js && joiner.player.gold === 5 && joiner.player.draughts === 1
                  && joiner.player.swordLevel === 0,
                  "the joiner's knight buys a draught on its own and cannot pay the sword ("
                  + joiner.player.gold + " left)")
            panel(host).close()
            panel(joiner).close()
            host._hostAdvanceLevel()
        }],
        [() => inLevel(host, "dungeon") && inLevel(joiner, "dungeon") && host.levelIndex === 2
               && liveEnemies(host).length > 0 && liveEnemies(joiner).length === liveEnemies(host).length,
         () => {
            let h = census(host), j = census(joiner)
            check(sameCount(h, hostReading) && sameCount(j, hostReading)
                  && linesTell(hostHeard, host.depth, host.dangerBand(host.dangerPosition), h),
                  "the next dungeon on both screens holds what she read: " + countText(h))
            check(host.player.swordLevel === 1 && joiner.player.swordLevel === 0
                  && host.player.draughts === 1 && joiner.player.draughts === 1,
                  "each knight keeps what it bought")
            hostNet.leave()
            joinNet.leave()
        }],
        // Torn down before quitting: the game crashes when Qt quits with it
        // still up, and the crash's exit code would hide the result
        [300, () => { host.destroy(); joiner.destroy() }]
    ]

    property var steps: soloSteps.concat(coopSteps).concat([
        [300, () => {
            console.log("[Camp] done,", failures, "failed")
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
                    console.log("[Camp] FAIL step", i, "timed out")
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
