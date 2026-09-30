// Clock bench - enemy AI and the knight's cooldowns run on the game clock,
// the physics steps, not on wall clock (issue #33).
//
// Starts single player, pauses the world the way the dojo does
// (Clayground.paused) and puts an enemy into its telegraph and the knight
// into its attack and dash cooldowns. Paused for a second of wall clock,
// nothing may move on; single steps (Clayground.physicsStep) must carry the
// telegraph into the lunge after the steps its wind-up takes and count the
// cooldowns down by 1/60 s each. A full hit stop must hold them the same
// way. Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/clock/clock.qml

import QtQuick
import QtQuick.Window
import Clayground.Common
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
        console.log("[Clock]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Clock] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true})
        script.start()
    }

    // The enemy under test: a melee one, which telegraphs before its lunge
    property var enemy: null
    readonly property real stepS: 1 / 60

    // Puts the enemy into a fresh telegraph towards the knight
    function telegraph() {
        let p = game.player
        enemy.target = p
        enemy._knockT = 0
        enemy._dirToTargetX = 1
        enemy._dirToTargetY = 0
        enemy._attackTimer = enemy.windUpDuration
        enemy.aiState = "telegraph"
    }
    function near(a, b) { return Math.abs(a - b) < 1e-6 }

    property real attackCd: 0
    property real dashCd: 0
    property real attackTimer: 0
    property int stepsToLunge: 0

    property var steps: [
        [() => game.screen === "title", () => {
            game.screen = "game"
            game.forceActiveFocus()
        }],
        [() => game.player && game.enemies.some(e => e.enemyType !== "spitter"), () => {
            enemy = game.enemies.find(e => e.enemyType !== "spitter")
            Clayground.paused = true
            check(!game.physics.running, "Clayground.paused stops the world")
            telegraph()
            game.player.attackCooldown = Balance.knight.attackCooldown
            game.player.dashCooldown = Balance.knight.dashCooldown
            attackCd = game.player.attackCooldown
            dashCd = game.player.dashCooldown
            attackTimer = enemy._attackTimer
        }],
        // Three wind-ups of wall clock and more than any cooldown
        [1000, () => {
            check(enemy.aiState === "telegraph" && near(enemy._attackTimer, attackTimer),
                  "paused, the enemy stays in its telegraph ("
                  + enemy.aiState + ", " + enemy._attackTimer.toFixed(3) + " s left)")
            check(near(game.player.attackCooldown, attackCd) && near(game.player.dashCooldown, dashCd),
                  "paused, the knight's cooldowns stand still (attack "
                  + game.player.attackCooldown.toFixed(3) + " s, dash "
                  + game.player.dashCooldown.toFixed(3) + " s)")
            // Six steps are 100 ms: the cooldowns count down by that much
            Clayground.physicsStep(6)
            check(Math.abs(attackCd - game.player.attackCooldown - 6 * stepS) < 1e-3
                  && Math.abs(dashCd - game.player.dashCooldown - 6 * stepS) < 1e-3,
                  "six single steps count the knight's cooldowns down by 100 ms (attack "
                  + attackCd.toFixed(3) + " -> " + game.player.attackCooldown.toFixed(3) + " s)")
            // The AI thinks every thinkInterval of simulated time, so the
            // telegraph ends between one think before and two after the
            // wind-up, counted in steps
            telegraph()
            stepsToLunge = 0
            while (enemy.aiState === "telegraph" && stepsToLunge < 600) {
                Clayground.physicsStep(1)
                stepsToLunge++
            }
            let windUp = enemy.windUpDuration / stepS
            let think = Balance.enemy.thinkInterval / stepS
            check(enemy.aiState === "lunge"
                  && stepsToLunge >= windUp - think && stepsToLunge <= windUp + 2 * think,
                  "single steps carry the telegraph into the lunge after "
                  + stepsToLunge + " steps (wind-up " + Math.round(windUp) + " steps)")
            // A cooldown runs out on the step that reaches it
            game.player.dashCooldown = 3 * stepS
            Clayground.physicsStep(2)
            let left = game.player.dashCooldown
            Clayground.physicsStep(1)
            check(left > 0 && game.player.dashCooldown === 0,
                  "a dash cooldown of three steps is over on the third step")
            // A full hit stop holds the game clock as a pause does
            Clayground.paused = false
            telegraph()
            game.player.attackCooldown = Balance.knight.attackCooldown
            attackCd = game.player.attackCooldown
            game.hitStop(1500, 0)
            attackTimer = enemy._attackTimer
        }],
        [700, () => {
            check(game.hitStopActive, "the measurement ran inside the hit stop")
            check(enemy.aiState === "telegraph" && Math.abs(enemy._attackTimer - attackTimer) < 1e-3,
                  "a full hit stop holds the enemy in its telegraph ("
                  + enemy.aiState + ", " + enemy._attackTimer.toFixed(3) + " s left)")
            check(Math.abs(game.player.attackCooldown - attackCd) < 1e-3,
                  "a full hit stop holds the knight's attack cooldown ("
                  + game.player.attackCooldown.toFixed(3) + " s)")
        }],
        [() => !game.hitStopActive, () => {}],
        // Once the stop is over the clock runs on
        [600, () => {
            check(enemy.aiState !== "telegraph", "after the hit stop the telegraph goes on ("
                  + enemy.aiState + ")")
            check(game.player.attackCooldown === 0, "after the hit stop the attack cooldown runs out")
            console.log("[Clock] done,", failures, "failed")
        }],
        // Torn down before quitting, as the impact bench does
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
                    console.log("[Clock] FAIL step", i, "timed out")
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
