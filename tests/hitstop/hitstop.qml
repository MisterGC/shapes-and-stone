// Hit stop bench - a blow that lands while a hit stop holds the physics
// throws the knight and an enemy back as far as on a normal step, and the
// game goes on (issue #138).
//
// A full hit stop steps the world by 0 s. The knockback's start speed is
// its distance over the sum of its steps' shares, which ran forever on a
// zero step and froze the game. Starts single player, measures the knight's
// knockback (takeDamage) and an enemy's recoil off the shield on a normal
// single step, then lands both inside a full hit stop: the bench has to get
// past them, their speeds have to match, the knockbacks have to hold
// through the stop and run out after it. Prints one PASS or FAIL line per
// check and exits with the number of failures; on a hang it never exits.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/hitstop/hitstop.qml

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
        console.log("[HitStop]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[HitStop] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 800, height: 600, muted: true})
        script.start()
    }

    property var enemy: null
    readonly property real stepS: 1 / 60

    // The speed a knockback of distance wu over duration s starts at on
    // steps of 1/60 s, as the knight's and the enemy's knockbacks sum it
    function startSpeed(distance, duration) {
        let per = 0
        for (let t = duration; t > 1e-9; t -= stepS) per += t / duration * stepS
        return distance / per
    }
    function speedOf(vx, vy) { return Math.sqrt(vx * vx + vy * vy) }
    function near(a, b) { return Math.abs(a - b) < 1e-6 }

    // A blow from the knight's left, travelling right
    function hitKnight() {
        let p = game.player
        p.graceLeft = 0
        return p.takeDamage(1, p.xWu - 2, p.yWu, 0, false, 1, 0)
    }
    function settle() {
        let p = game.player
        p._knockT = 0
        p.graceLeft = 0
        p.hp = p.maxHp
        enemy._knockT = 0
    }

    property real knightSpeed: 0
    property real enemySpeed: 0
    property int stepsAtHit: 0

    property var steps: [
        [() => game.screen === "title", () => {
            game.screen = "game"
            game.forceActiveFocus()
        }],
        [() => game.player && game.enemies.length > 0, () => {
            enemy = game.enemies[0]
            let p = game.player
            // A normal step: single steps run at 1/60 s
            Clayground.paused = true
            Clayground.physicsStep(1)
            check(near(game.timeStep, stepS), "a single step runs at 1/60 s ("
                  + game.timeStep.toFixed(4) + " s)")
            let r = hitKnight()
            knightSpeed = speedOf(p._knockVx, p._knockVy)
            let want = startSpeed(Balance.knight.knockback, Balance.knight.knockbackDuration)
            check(r === "hit" && Math.abs(knightSpeed - want) < 1e-6,
                  "on a normal step the knight is thrown back at " + knightSpeed.toFixed(3)
                  + " wu/s, " + Balance.knight.knockback + " wu over its knockback (" + r + ")")
            enemy.recoil(p)
            enemySpeed = speedOf(enemy._knockVx, enemy._knockVy)
            want = startSpeed(Balance.block.recoil, Balance.enemy.knockbackDuration)
            check(Math.abs(enemySpeed - want) < 1e-6,
                  "on a normal step an enemy recoils at " + enemySpeed.toFixed(3)
                  + " wu/s, " + Balance.block.recoil + " wu over its knockback")
            settle()
            Clayground.paused = false
            game.hitStop(1500, 0)
        }],
        // Well into the stop: the world steps by 0 s now
        [300, () => {
            let p = game.player
            check(game.hitStopActive && game.timeStep === 0,
                  "a full hit stop steps the world by 0 s (" + game.timeStep + " s)")
            stepsAtHit = p._steps
            let r = hitKnight()
            check(r === "hit" && Math.abs(speedOf(p._knockVx, p._knockVy) - knightSpeed) < 1e-6,
                  "a blow in the hit stop throws the knight back as on a normal step ("
                  + speedOf(p._knockVx, p._knockVy).toFixed(3) + " wu/s, " + r + ")")
            enemy.recoil(p)
            check(Math.abs(speedOf(enemy._knockVx, enemy._knockVy) - enemySpeed) < 1e-6,
                  "an enemy recoiling in the hit stop is thrown back as on a normal step ("
                  + speedOf(enemy._knockVx, enemy._knockVy).toFixed(3) + " wu/s)")
        }],
        [300, () => {
            let p = game.player
            check(game.hitStopActive, "the hit stop still holds")
            check(p._steps > stepsAtHit, "the world steps on in the hit stop ("
                  + (p._steps - stepsAtHit) + " steps)")
            check(near(p._knockT, Balance.knight.knockbackDuration)
                  && near(enemy._knockT, Balance.enemy.knockbackDuration),
                  "the hit stop holds both knockbacks (knight " + p._knockT.toFixed(3)
                  + " s, enemy " + enemy._knockT.toFixed(3) + " s left)")
        }],
        [() => !game.hitStopActive, () => {}],
        // Once the stop is over the knockbacks run out
        [600, () => {
            check(game.player._knockT === 0 && enemy._knockT === 0,
                  "after the hit stop both knockbacks have run out (knight "
                  + game.player._knockT.toFixed(3) + " s, enemy " + enemy._knockT.toFixed(3) + " s)")
            console.log("[HitStop] done,", failures, "failed")
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
                    console.log("[HitStop] FAIL step", i, "timed out")
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
