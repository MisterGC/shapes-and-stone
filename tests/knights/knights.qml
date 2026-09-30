// Knight bench - the local and a remote knight side by side, doing the same
// thing at the same moment, captured to PNGs.
//
// Loads the real game in the dungeon scenario, spawns a RemotePlayer next
// to the player and drives it the way Session.qml does (pushState and
// triggerAction), without a network. Each pose is saved as <out>/<pose>.png.
//
//   qml -I <build>/bin/qml tests/knights/knights.qml -- <out dir>

import QtQuick
import QtQuick.Window

Window {
    id: bench
    width: 1000
    height: 700
    visible: true
    color: "#1a1a2e"

    readonly property string outDir: Qt.application.arguments[Qt.application.arguments.length - 1]
    property var game: null
    property var remote: null
    property real remoteX: 0
    property real remoteY: 0
    property int remoteState: 0

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Knights] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height})
        script.start()
    }

    // Feeds the remote the way the network does: one state per frame
    Timer {
        interval: 16
        repeat: true
        running: bench.remote !== null
        onTriggered: bench.remote.pushState({
            x: bench.remoteX, y: bench.remoteY,
            a: bench.game.player ? bench.game.player.facingAngle : 0,
            s: bench.remoteState, h: 120
        })
    }

    // The knight's KnightView; null on a build without one
    function view(knight) {
        for (let i = 0; i < knight.children.length; i++)
            if (typeof knight.children[i].parry === "function") return knight.children[i]
        return null
    }

    function capture(name) {
        bench.contentItem.grabToImage(r => {
            let ok = r.saveToFile(outDir + "/" + name + ".png")
            console.log("[Knights] capture", name, ok ? "saved" : "FAILED")
        })
    }

    // Poses: [delay before, action]
    property var steps: [
        [800, () => {
            game.applyScenario("dungeon")
        }],
        [600, () => {
            let p = game.player
            p.facingAngle = 90
            remoteX = p.xWu + 2.2
            remoteY = p.yWu
            let c = Qt.createComponent(Qt.resolvedUrl("../../src/RemotePlayer.qml"))
            remote = c.createObject(game.room, {
                nodeId: "bench", playerColor: "#A44A90",
                xWu: remoteX, yWu: remoteY,
                pixelPerUnit: Qt.binding(() => game.pixelPerUnit),
                world: game.physics, gameWorld: game
            })
            console.log("[Knights] remote", remote ? "spawned" : "FAILED")
        }],
        [800, () => {
            capture("1-idle")
            // Sounds: how loud the remote knight is, next to you and away
            let p = game.player
            for (let d of [0, 2.2, 7, 14])
                console.log("[Knights] remote gain at", d, "Wu:",
                            game.remoteGain(p.xWu + d, p.yWu).toFixed(3))
        }],
        [100, () => { game.player.attack(); remote.triggerAction("attack") }],
        [120, () => capture("2-swing")],
        [600, () => { game.player.isBlocking = true; remoteState = 2 }],
        [250, () => capture("3-block")],
        [100, () => { let v = view(game.player); if (v) v.parry(); remote.triggerAction("parry") }],
        [40, () => capture("4-parry")],
        [400, () => { game.player.isBlocking = false; remoteState = 0 }],
        [300, () => { let v = view(game.player); if (v) v.hurt(); remote.triggerAction("hurt") }],
        [30, () => capture("5-hurt")],
        [600, () => {
            game.player.dash(); remote.triggerAction("dash"); remoteState = 3
            dashMove.start()
        }],
        [70, () => capture("6-dash")],
        [800, () => {
            remoteState = 0
            // Out of the local lantern's reach: only its own light shows it
            remoteX = game.player.xWu + 7
            remoteY = game.player.yWu
        }],
        [900, () => capture("7-apart")],
        [500, () => { console.log("[Knights] done"); Qt.exit(0) }]
    ]

    // The remote dashes the same way as the local knight: up at dash speed
    Timer {
        id: dashMove
        interval: 16
        repeat: true
        property int n: 0
        onTriggered: { remoteY += 40 * 0.016; if (++n >= 9) { stop(); n = 0 } }
    }

    Timer {
        id: script
        property int i: 0
        interval: bench.steps[0][0]
        onTriggered: {
            bench.steps[i][1]()
            i++
            if (i < bench.steps.length) {
                interval = bench.steps[i][0]
                start()
            }
        }
    }
}
