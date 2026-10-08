// Ring bench - the parry ring of a grunt's wind-up, captured to PNGs
// (issue #78).
//
// Starts the fight room paused and single-steps one grunt from the start of
// its telegraph, a step and a half from the knight. Saves <out>/ring-0.png
// as the telegraph begins, ring-50.png once the ring is half closed and
// ring-100.png on the step the parry window opens, where the ring lies on
// the grunt's outline and is white. Then the tough guardian winds up a
// crushing blow: crush-50.png once its ring is half closed, the guardian
// white-hot and its ring doubled in the crushing blow's colour. Checks the
// ring's drawn size at each, prints one PASS or FAIL line per check and
// exits with the number of failures. It needs a window: offscreen it saves the HUD but not the world.
//
//   qml -I <build>/bin/qml tests/ring/ring.qml -- <out dir>

import QtQuick
import QtQuick.Window
import Clayground.Common
import "../../src"

Window {
    id: bench
    width: 1000
    height: 700
    visible: true
    color: "#1a1a2e"

    readonly property string outDir: Qt.application.arguments[Qt.application.arguments.length - 1]
    property var game: null
    property var grunt: null
    property var guardian: null
    property int failures: 0

    function check(ok, what) {
        console.log("[Ring]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Ring] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true})
        script.start()
    }

    function capture(name) {
        bench.contentItem.grabToImage(r => {
            let ok = r.saveToFile(outDir + "/" + name + ".png")
            console.log("[Ring] capture", name, ok ? "saved" : "FAILED")
        })
    }

    // The ring's drawn size against the one its progress gives
    function ringItem() {
        let candidates = [grunt].concat(game.glowParent())
        for (let p of candidates)
            for (let i = 0; i < p.children.length; i++)
                if (p.children[i].objectName === "parryRing"
                    && (p === grunt || Math.abs(p.children[i].x + p.children[i].width / 2
                                                - grunt.x - grunt.width / 2) < 1))
                    return p.children[i]
        return null
    }
    // The ring is drawn from times the grunt's size down to its outline;
    // the outline crouches and stretches with the grunt's pose, so the
    // drawn size is the progress's times the pose's, within its range
    function checkSize(what) {
        let r = ringItem()
        let from = Balance.parryRing.from
        let want = from - (from - 1) * grunt.ringProgress
        let drawn = r ? r.width / grunt.width : 0
        check(r && r.visible && drawn / want > 0.7 && drawn / want < 1.3,
              what + ": progress " + grunt.ringProgress.toFixed(3) + ", the ring is drawn "
              + drawn.toFixed(3) + "x the grunt's width, " + want.toFixed(3) + "x before its pose")
    }

    property var steps: [
        [() => game.screen === "title", () => game.applyScenario("fight")],
        [() => game.player && game.fightRoomActive
              && game.enemies.some(e => e.enemyType === "grunt"), () => {
            Clayground.paused = true
            let p = game.player
            grunt = game.enemies.find(e => e.enemyType === "grunt" && !e.destroyed)
            for (let o of game.enemies) {
                o.target = o === grunt ? p : null
                if (o !== grunt) { o.aiState = "patrol"; o.parryWindow = false }
            }
            grunt._knockT = 0
            grunt.attackCooldown = 0
            grunt.xWu = p.xWu + 1.5
            grunt.yWu = p.yWu
            grunt.aiState = "chase"
            let n = 0
            while (grunt.aiState !== "telegraph" && n++ < 600) Clayground.physicsStep(1)
            check(grunt.aiState === "telegraph", "the grunt winds up (" + grunt.aiState + ")")
        }],
        [600, () => { checkSize("the telegraph begins"); capture("ring-0") }],
        [400, () => {
            let n = 0
            while (grunt.ringProgress < 0.5 && n++ < 600) Clayground.physicsStep(1)
        }],
        [600, () => { checkSize("half way"); capture("ring-50") }],
        [400, () => {
            let n = 0
            while (!grunt.parryWindow && n++ < 600) Clayground.physicsStep(1)
            check(grunt.parryWindow && grunt.ringProgress === 1
                  && Qt.colorEqual(grunt.ringColor, Balance.parryRing.flashColor),
                  "the parry window opens with the ring closed and white ("
                  + grunt.ringProgress + ", " + grunt.ringColor + ")")
        }],
        [600, () => { checkSize("the parry window opens"); capture("ring-100") }],
        // A crushing blow: the tough guardian at the knight, the grunt gone
        [400, () => {
            let p = game.player
            grunt.target = null
            grunt.xWu = p.xWu - 6
            grunt.aiState = "patrol"
            guardian = game.enemies.find(e => e.enemyType === "guardian" && !e.destroyed)
            guardian.target = p
            guardian.crushChance = 1
            guardian._knockT = 0
            guardian.attackCooldown = 0
            guardian._attackTimer = 0
            guardian.xWu = p.xWu + 1.5
            guardian.yWu = p.yWu
            guardian.aiState = "chase"
            let n = 0
            while (guardian.aiState !== "crush" && n++ < 600) Clayground.physicsStep(1)
            while (guardian.ringProgress < 0.5 && n++ < 600) Clayground.physicsStep(1)
            let near = item => item.visible && Math.abs(item.x + item.width / 2
                                                        - guardian.x - guardian.width / 2) < 1
            let drawn = name => [guardian].concat(game.glowParent()).some(
                par => Array.from(par.children).some(c => c.objectName === name && near(c)))
            check(guardian.aiState === "crush" && drawn("crushRing") && drawn("crushGlow")
                  && Qt.colorEqual(guardian.ringColor, Balance.crush.ringColor),
                  "the guardian winds up a crushing blow (" + guardian.aiState + ", progress "
                  + guardian.ringProgress.toFixed(3) + "): white-hot, its ring doubled and "
                  + guardian.ringColor)
        }],
        [600, () => capture("crush-50")],
        [500, () => {
            Clayground.paused = false
            console.log("[Ring] done,", failures, "failed")
            game.destroy()
        }],
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
                    console.log("[Ring] FAIL step", i, "timed out")
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
