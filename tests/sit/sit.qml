// Sit bench - a knight that stands still by the fire sits down, and any
// key or button stands it up again (issue #148).
//
// In the camp after depth 0, the world paused and stepped one physics step
// at a time: a knight standing still in the campfire's warmth is not
// seated one step before Balance.camp.sitAfter and is on the step that
// reaches it, facing the fire, its shield set down; one press of D stands
// it up and it moves in that same step. Seated again, Space (a dash), the
// right button (the shield) and a click (a swing) each stand it up in the
// step they come. A knight standing still out of the fire's warmth for
// twice sitAfter does not sit. Every sit and stand is one action the knight
// sends ("sit", "stand"). Then, the world running: five seconds at the fire
// heal and refill as much seated as for a knight that never sits.
// Prints one PASS or FAIL line per check and exits with the number of
// failures; with a window and an output directory it saves sit.png, the
// knight seated at the fire.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/sit/sit.qml
//   qml -I <build>/bin/qml tests/sit/sit.qml -- <out dir>

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Common
import "../../src"

Window {
    id: bench
    width: 1000
    height: 600
    visible: true
    color: "#1a1a2e"

    property var game: null
    property var fire: null
    property int failures: 0
    // What the knight sent, in order
    property var sent: []
    // The heal and refill of the knight that sits, then of the one that never does
    property var rested: []
    property int hpBefore: 0
    readonly property string outDir: Qt.application.arguments.length > 0
        && Qt.application.arguments[Qt.application.arguments.length - 1].indexOf(".qml") < 0
        ? Qt.application.arguments[Qt.application.arguments.length - 1] : ""

    function check(ok, what) {
        console.log("[Sit]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Sit] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 1000, height: 600, muted: true,
                                                  recordStoreName: "ShapesAndStoneSitBench"})
        script.start()
    }

    readonly property real stepS: game ? game.physics.timeStep : 1 / 60
    // The steps standing still that reach sitAfter
    readonly property int sitSteps: Math.ceil(Balance.camp.sitAfter / stepS - 1e-6)

    function find(root, name) {
        if (root.objectName === name) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = find(kids[i], name)
            if (f) return f
        }
        return null
    }
    // The knight stands with its body's corner dx wu east of the fire's
    function standBy(dx) {
        let p = game.player
        p.xWu = fire.xWu + dx
        p.yWu = fire.yWu
        p.body.linearVelocity = Qt.point(0, 0)
        Clayground.physicsStep(1)
    }
    // Steps until the knight sits, standBy's step the first of sitSteps;
    // whether it sat on the last and not before
    function sitDown() {
        Clayground.physicsStep(sitSteps - 2)
        let early = game.player.seated
        Clayground.physicsStep(1)
        return !early && game.player.seated
    }
    function lastSent() { return sent.length > 0 ? sent[sent.length - 1] : "" }
    function angleOff(a, b) {
        let d = Math.abs(a - b) % 360
        return Math.min(d, 360 - d)
    }

    property var steps: [
        [() => game.width > 0, () => game.applyScenario("village", 0)],
        [() => game.player && game.levelType === "village" && game.campfire && !game.resetting, () => {
            fire = game.campfire
            check(fire.healRadius !== undefined && game.dungeonObjects.indexOf(fire) >= 0,
                  "the camp's campfire is the game's campfire")
            game.forceActiveFocus()
            game.player.acted.connect(a => { if (a === "sit" || a === "stand") bench.sent.push(a) })
            Clayground.paused = true
            // West of the fire, inside its warmth
            standBy(-1.5)
            let p = game.player
            check(fire.warms(p.xWu, p.yWu) && !p.seated,
                  "a knight in the fire's warmth stands at first (" + p.xWu.toFixed(2) + ", "
                  + p.yWu.toFixed(2) + ")")
            check(sitDown(),
                  "standing still it is not seated one step before sitAfter (" + Balance.camp.sitAfter
                  + " s, " + sitSteps + " steps) and is on the step that reaches it")
            let want = fire.angleFrom(p.xWu, p.yWu)
            check(angleOff(p.sitAngle, want) < 0.5 && Math.abs(want) < 45,
                  "seated it faces the fire (" + p.sitAngle.toFixed(1) + " deg, the fire lies at "
                  + want.toFixed(1) + " deg)")
            check(lastSent() === "sit" && sent.length === 1, "sitting down sends one \"sit\" (" + sent + ")")
            // The pose sinks in over sit.down: by now on the wall clock
        }],
        [Balance.camp.sit.down * 1000 + 200, () => {
            let shield = find(game.player, "shieldDown")
            check(shield && shield.visible && shield.opacity > 0.9,
                  "its shield lies on the floor beside it (opacity " + (shield ? shield.opacity.toFixed(2) : "-") + ")")
            if (outDir !== "") {
                game.camera.target = null
                game.camera.target = game.player
            }
        }],
        [() => true, () => {
            if (outDir === "") return
            bench.contentItem.grabToImage(r => {
                let ok = r.saveToFile(outDir + "/sit.png")
                check(ok, "saved " + outDir + "/sit.png")
            })
        }],
        [500, () => {
            let p = game.player
            let x0 = p.xWu
            keys.keyPress(Qt.Key_D, Qt.NoModifier, -1)
            check(p.moveX === 1, "D sets the knight's move (moveX " + p.moveX + ")")
            Clayground.physicsStep(1)
            check(!p.seated && p.body.linearVelocity.x > 0,
                  "one step after D the knight stands and moves (velocity "
                  + p.body.linearVelocity.x.toFixed(2) + " wu/s)")
            Clayground.physicsStep(1)
            check(p.xWu > x0, "it walks east (" + x0.toFixed(3) + " -> " + p.xWu.toFixed(3) + ")")
            check(lastSent() === "stand" && sent.length === 2, "standing up sends one \"stand\" (" + sent + ")")
            keys.keyRelease(Qt.Key_D, Qt.NoModifier, -1)
            // Space: a dash
            standBy(-1.5)
            check(sitDown(), "back by the fire it sits down again")
            keys.keyClick(Qt.Key_Space, Qt.NoModifier, -1)
            Clayground.physicsStep(1)
            check(!p.seated && p.isDashing, "Space stands it up in the step it comes, dashing")
            Clayground.physicsStep(Math.ceil(Balance.knight.dashDuration / stepS) + 2)
            // The right button: the shield
            standBy(-1.5)
            check(sitDown(), "and sits down after the dash")
            p.raiseShield()
            Clayground.physicsStep(1)
            check(!p.seated && p.isBlocking, "the right button stands it up, the shield raised")
            p.lowerShield()
            // A click: a swing
            standBy(-1.5)
            check(sitDown(), "and sits down after the shield")
            p.pressSwing()
            Clayground.physicsStep(1)
            let up = !p.seated
            p.releaseSwing()
            Clayground.physicsStep(1)
            check(up && p.isAttacking, "a click stands it up as the button goes down, and it swings")
            Clayground.physicsStep(Math.ceil((Balance.knight.swingDuration + Balance.knight.attackCooldown) / stepS) + 2)
            // Out of the fire's warmth
            standBy(Balance.campfire.healRadius + 3)
            let n = sent.length
            Clayground.physicsStep(2 * sitSteps)
            check(!fire.warms(p.xWu, p.yWu) && !p.seated && sent.length === n,
                  "a knight standing still away from the fire for twice sitAfter does not sit")
            check(sent.join(" ") === "sit stand sit stand sit stand sit stand",
                  "each sit and each stand was one action sent (" + sent.join(" ") + ")")
            // The world runs: five seconds at the fire, hurt and dry
            standBy(-1.5)
            p.hp = 40
            p.mana = 0
            hpBefore = p.hp
            Clayground.paused = false
        }],
        [5000, () => {
            let p = game.player
            rested.push({hp: p.hp - hpBefore, mana: p.mana, seated: p.seated})
            // The same with a knight that never sits
            Clayground.paused = true
            p.sitAfter = 1e9
            // Out of the warmth it stands up, and back by the fire
            standBy(Balance.campfire.healRadius + 3)
            standBy(-1.5)
            p.hp = 40
            p.mana = 0
            hpBefore = p.hp
            Clayground.paused = false
        }],
        [5000, () => {
            let p = game.player
            rested.push({hp: p.hp - hpBefore, mana: p.mana, seated: p.seated})
            let a = rested[0], b = rested[1]
            let tickHp = Math.round(Balance.campfire.healPerSecond * Balance.campfire.healTick)
            let tickMana = (Balance.campfire.manaPerSecond + Balance.knight.manaRegen) * Balance.campfire.healTick
            check(a.seated && !b.seated, "the first knight sat, the second never did")
            check(Math.abs(a.hp - b.hp) <= tickHp && a.hp >= 4 * Balance.campfire.healPerSecond,
                  "five seconds at the fire heal the same seated or standing (" + a.hp + " HP and "
                  + b.hp + " HP, one tick " + tickHp + ")")
            check(Math.abs(a.mana - b.mana) <= tickMana + 0.01,
                  "and refill the same mana (" + a.mana.toFixed(1) + " and " + b.mana.toFixed(1)
                  + ", one tick " + tickMana.toFixed(1) + ")")
            // Gone before the window: torn down with it, the camp crashes
            // the exit (on the base too)
            game.destroy()
        }],
        [300, () => {
            console.log("[Sit] done,", failures, "failed")
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
                    console.log("[Sit] FAIL step", i, "timed out")
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
