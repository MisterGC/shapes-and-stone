// Boots bench - the smith's swift boots make the knight walk faster
// (issue #325).
//
// At the first camp the smith offers the swift boots I next to his other
// four upgrades, for shop.upgradePrice[0], with what they give; with a gem
// in the pouch his offer for it comes first and 6 buys the boots. Then the
// knight walks at shop.bootsSpeed[0] and the smith sells nothing more; the
// knight panel shows "Swift boots I" and what it gives. The camp after
// depth 0 offers no boots II, the one after depth 2 does, the one after
// depth 4 boots III. In the fight room, at every level from none to III:
// walking it goes the level's speed, charging a swing and behind a raised
// shield the same share of it as without boots
// (knight.chargeSpeed, knight.blockSpeed), and a dash goes as far and costs
// as much mana as without. Prints one PASS or FAIL line per check and exits
// with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/boots/boots.qml

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Common
import "../../src"

Window {
    id: bench
    width: 1000
    height: 500
    visible: true
    color: "#1a1a2e"

    property var solo: null
    property int failures: 0
    readonly property string storeName: "ShapesAndStoneBootsBench"

    function check(ok, what) {
        console.log("[Boots]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(key) {
        solo.forceActiveFocus()
        keys.keyClick(key, Qt.NoModifier, -1)
    }

    property var gameComponent: null
    Component.onCompleted: {
        gameComponent = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComponent.status !== Component.Ready) {
            console.log("[Boots] FAIL", gameComponent.errorString())
            Qt.exit(1)
            return
        }
        solo = gameComponent.createObject(bench.contentItem, {width: 1000, height: 500, muted: true,
                                                              recordStoreName: storeName})
        solo.controls.reset()
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
    function textsUnder(item, out) {
        out = out || []
        if (item.text !== undefined && item.visible) out.push(String(item.text))
        let kids = item.data || []
        for (let i = 0; i < kids.length; i++) textsUnder(kids[i], out)
        return out
    }
    function panel(game) {
        for (let i = 0; i < game.data.length; i++)
            if (game.data[i] && typeof game.data[i].advance === "function"
                && game.data[i].wares !== undefined) return game.data[i]
        return null
    }
    function talk(game, name) {
        panel(game).close()
        let kids = game.room.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i].objectName === "npc" && kids[i].npcName === name) kids[i].interact()
        return panel(game)
    }
    function inLevel(type) { return solo && solo.player && solo.levelType === type && !solo.resetting }
    function alive(e) { return e && e.destroyed === false }
    function near(a, b) { return Math.abs(a - b) < 1e-3 }

    // ---- in the fight room, on the paused physics clock ----
    function steps(n) {
        for (let i = 0; i < n; i++) Clayground.physicsStep(1)
    }
    function speed(p) {
        let v = p.body.linearVelocity
        return Math.sqrt(v.x * v.x + v.y * v.y)
    }
    // The knight at the room's centre, standing, every enemy far off and halted
    function centre(p) {
        let g = solo
        p.moveX = 0
        p.moveY = 0
        p.xWu = g._fightRoomCx - p.widthWu / 2
        p.yWu = g._fightRoomCy + p.heightWu / 2
        p.body.linearVelocity = Qt.point(0, 0)
        for (let e of g.enemies.filter(alive)) {
            e.xWu = g._fightRoomCx - 30
            e.yWu = g._fightRoomCy + 30
            e.body.linearVelocity = Qt.point(0, 0)
            if (!e.halted) e.halt()
        }
        steps(2)
    }
    // At level: the speed walking, charging and behind the shield, and a
    // dash's length and mana
    function measure(p, level) {
        p.bootsLevel = level
        let out = { level: level, maxSpeed: p.maxSpeed }
        centre(p)
        p.moveX = 1
        steps(4)
        out.walk = speed(p)
        p.pressSwing()
        steps(Math.ceil(Balance.knight.chargeStart * 60) + 4)
        out.charging = p.isCharging
        out.charge = speed(p)
        p.dropSwing()
        steps(1)
        p.raiseShield()
        steps(3)
        out.block = speed(p)
        p.lowerShield()
        centre(p)
        p.moveX = 1
        p.dashCooldown = 0
        p.mana = p.maxMana
        let x0 = p.xWu, mana0 = p.mana
        p.dash()
        out.dashed = p.isDashing
        out.dashMana = mana0 - p.mana
        steps(Math.round(Balance.knight.dashDuration * 60))
        // The dash's own way, less the walk of any step it had over
        out.dash = p.xWu - x0
        p.moveX = 0
        return out
    }

    property var measured: []
    property var steps_: [
        // The first camp of a run, depth 0
        [() => solo.screen === "title", () => solo.applyScenario("village", 0.5)],
        [() => inLevel("village"), () => {
            let k = solo.player
            k.gold = 1000
            let gold0 = k.gold
            let p = talk(solo, "Blacksmith")
            let ids = p.wares.map(x => x.id).join(", ")
            let boots = p.wares.find(x => x.id === "boots")
            let gives = solo.smithGives("boots", 1)
            check(ids === "sword, shield, harness, blade, boots" && boots.level === 1
                  && boots.price === Balance.shop.upgradePrice[0]
                  && boots.label === "Swift boots I (" + gives + ")",
                  "the first camp's smith offers the swift boots I next to his other four for "
                  + "upgradePrice[0] (" + p.wares.map(x => x.label + " " + x.price).join("; ") + ")")
            check(gives === "walk " + Math.round((Balance.shop.bootsSpeed[0] / Balance.knight.moveSpeed - 1) * 100)
                  + " % faster", "the boots say what they give (\"" + gives + "\")")
            // A gem in the pouch: his offer for it comes first, the boots
            // are the sixth ware
            k.pouch = [{ shape: "triangle", value: 5 }]
            p = talk(solo, "Blacksmith")
            ids = p.wares.map(x => x.id).join(", ")
            check(ids === "gems, sword, shield, harness, blade, boots",
                  "with a gem in the pouch his offer for it comes first (" + ids + ")")
            press(Qt.Key_6)
            check(k.bootsLevel === 1 && k.gold === gold0 - Balance.shop.upgradePrice[0]
                  && near(k.maxSpeed, Balance.shop.bootsSpeed[0]) && k.swordLevel === 0 && k.pouch.length === 1,
                  "6 buys the swift boots I: the knight walks " + k.maxSpeed + " wu/s (gold " + gold0 + " -> "
                  + k.gold + ")")
            check(p.wares.every(x => x.id === "gems"), "and the smith sells nothing more there ("
                  + p.wares.map(x => x.id).join(", ") + ")")
            p.close()
            solo.forceActiveFocus()
            solo.knightPanelOpen = true
        }],
        [100, () => {
            let kp = find(solo, "knightPanel")
            let texts = kp && kp.visible ? textsUnder(kp).join("|") : ""
            check(texts.indexOf("Swift boots I") >= 0 && texts.indexOf(solo.smithGives("boots", 1)) >= 0,
                  "the knight panel shows the swift boots I and what they give")
            solo.knightPanelOpen = false
            solo.player.smithDone = false
            check(solo.smithWare("boots") === null, "the camp after depth " + solo.depth + " offers no boots II")
            solo.applyScenario("village", 2.5)
        }],
        [() => inLevel("village") && solo.depth === 2, () => {
            solo.player.bootsLevel = 1
            let w = solo.smithWare("boots")
            check(w && w.level === 2 && w.price === Balance.shop.upgradePrice[1],
                  "the camp after depth 2 offers the boots II for upgradePrice[1] (" + (w ? w.label : "none") + ")")
            solo.applyScenario("village", 4.5)
        }],
        [() => inLevel("village") && solo.depth === 4, () => {
            solo.player.bootsLevel = 2
            let w = solo.smithWare("boots")
            check(w && w.level === 3 && w.price === Balance.shop.upgradePrice[2],
                  "the camp after depth 4 offers the boots III for upgradePrice[2] (" + (w ? w.label : "none") + ")")
            solo.applyScenario("flow", 0)
        }],
        [() => solo.player && solo.levelType === "dungeon" && !solo.resetting && solo.enemies.filter(alive).length > 0, () => {
            Clayground.paused = true
            let p = solo.player
            p.maxHp = 100000
            p.hp = 100000
            p.maxMana = 1000
            let m = [0, 1, 2, 3].map(l => measure(p, l))
            p.bootsLevel = 0
            let k = Balance.knight
            for (let x of m) {
                let want = x.level > 0 ? Balance.shop.bootsSpeed[x.level - 1] : k.moveSpeed
                check(near(x.maxSpeed, want) && Math.abs(x.walk - want) < 0.01,
                      "boots " + x.level + ": the knight walks " + x.walk.toFixed(3) + " wu/s (" + want + ")")
                check(x.charging && Math.abs(x.charge / x.walk - k.chargeSpeed) < 0.005
                      && Math.abs(x.block / x.walk - k.blockSpeed) < 0.005,
                      "boots " + x.level + ": charging it goes " + (x.charge / x.walk).toFixed(3)
                      + " of that (chargeSpeed " + k.chargeSpeed + "), behind the shield "
                      + (x.block / x.walk).toFixed(3) + " (blockSpeed " + k.blockSpeed + ")")
                check(x.dashed && near(x.dashMana, m[0].dashMana) && near(x.dashMana, k.dashMana)
                      && Math.abs(x.dash - m[0].dash) < 0.01,
                      "boots " + x.level + ": a dash goes " + x.dash.toFixed(3) + " wu for " + x.dashMana
                      + " mana, as without boots (" + m[0].dash.toFixed(3) + " wu, " + m[0].dashMana + ")")
            }
            check(m[3].walk > m[2].walk && m[2].walk > m[1].walk && m[1].walk > m[0].walk,
                  "each level walks faster than the one below")
            Clayground.paused = false
        }],
        // The game gone before the exit, as the other benches end
        [100, () => solo.destroy()],
        [300, () => {
            console.log("[Boots]", failures === 0 ? "all checks pass" : failures + " checks fail")
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
            let step = bench.steps_[i]
            waitedMs += interval
            let ready = typeof step[0] === "number" ? waitedMs >= step[0] : step[0]()
            if (!ready) {
                if (waitedMs > 20000) {
                    console.log("[Boots] FAIL step", i, "timed out")
                    Qt.exit(failures + 100)
                    stop()
                }
                return
            }
            waitedMs = 0
            i++
            if (i >= bench.steps_.length) stop()
            step[1]()
        }
    }
}
