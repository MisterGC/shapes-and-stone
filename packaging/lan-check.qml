// LAN check - one of two game processes that packaging/lan-check.sh starts
// on a package's runtime, a host and a joiner. Run as host (no code given)
// it hosts a LAN session and prints its code; run with SNS_LAN_CODE it joins
// that session. Each exits 0 once it is in the dungeon with the other
// player's knight, 1 after 60 s without.

import QtQuick
import QtQuick.Window
import Clayground.Network

Window {
    id: check
    width: 640
    height: 480
    visible: true

    readonly property string code: Qt.application.arguments.length > 0
        ? Qt.application.arguments[Qt.application.arguments.length - 1] : ""
    readonly property bool hosting: !code.startsWith("L")
    property var game: null
    property var session: null
    property var net: null

    function log(what) { console.log("[Lan]", hosting ? "host:" : "joiner:", what) }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../src/Game.qml"))
        if (c.status !== Component.Ready) {
            log("FAIL " + c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(contentItem, {width: 640, height: 480, muted: true,
                                            recordStoreName: "ShapesAndStoneLanCheck"})
        // The game's Session and its Network, found by what they offer
        for (let i = 0; i < game.data.length; i++)
            if (typeof game.data[i].sendImpact === "function") session = game.data[i]
        for (let i = 0; session && i < session.data.length; i++)
            if (typeof session.data[i].join === "function" && session.data[i].signalingMode !== undefined)
                net = session.data[i]
        if (!net) {
            log("FAIL no Network in the game's session")
            Qt.exit(1)
            return
        }
        if (hosting) {
            net.signalingMode = Network.SignalingMode.Local
            net.host()
        } else {
            net.join(code)
        }
    }

    property bool codeShown: false
    property bool started: false
    property bool done: false
    Timer {
        interval: 50
        repeat: true
        running: check.net !== null
        onTriggered: {
            if (hosting && !codeShown && net.networkId !== "") {
                codeShown = true
                console.log("[Lan] code", net.networkId)
            }
            if (hosting && !started && net.connected && net.nodeCount >= 2) {
                started = true
                log("the joiner is here, starting the game")
                game._startMultiplayerGame()
            }
            let others = Object.keys(session.remotePlayers).length
            if (!done && game.screen === "game" && game.player && others > 0) {
                done = true
                log("PASS in the dungeon with " + others + " other knight(s), "
                    + net.nodeCount + " nodes")
                Qt.exit(0)
            }
        }
    }
    Timer {
        interval: 60000
        running: true
        onTriggered: {
            log("FAIL after 60 s: connected " + (net && net.connected) + ", nodes "
                + (net ? net.nodeCount : 0) + ", screen " + (game ? game.screen : "-"))
            Qt.exit(1)
        }
    }
}
