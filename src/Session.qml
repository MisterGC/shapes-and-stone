import QtQuick
import Clayground.Network

// The co-op session: owns the Network, the lobby-to-game flow and the
// registry of remote players. Game.qml calls into it and reacts to its
// signals; it never touches the Network itself.
Item {
    id: session
    anchors.fill: parent

    // Set by the game
    property var world: null
    property var player: null
    property bool inGame: false      // the game screen is up
    property bool showLobby: false   // the lobby screen is up

    readonly property bool connected: net.connected
    readonly property bool isHost: net.isHost

    // The host started the game (also emitted on the host itself)
    signal started(int seed)
    // Every client applies this level; the host is the level authority
    signal levelChanged(int levelIndex)
    // Host only: a player reached the exit, the host decides to advance
    signal advanceRequested()
    // The host pressed start in the lobby; the game picks the seed and
    // calls start()
    signal lobbyStartRequested()
    // The lobby was left without starting
    signal lobbyLeft()
    // Another player hit or was hit; this screen draws the hit, no more
    signal impactReceived(string kind, real x, real y, real dx, real dy, var color)

    property var remotePlayers: ({})

    Network {
        id: net
        maxNodes: 4
        topology: Network.Topology.Star
        signalingMode: Network.SignalingMode.Cloud
        autoRelay: true

        onMessageReceived: (fromId, data) => {
            if (data.type === "gameStart") {
                session.started(data.seed)
            } else if (data.type === "action") {
                let rp = remotePlayers[fromId]
                if (rp) rp.triggerAction(data.action)
            } else if (data.type === "impact") {
                session.impactReceived(data.kind, data.x, data.y, data.dx, data.dy, data.color)
            } else if (data.type === "levelChange") {
                session.levelChanged(data.levelIndex)
            } else if (data.type === "exitReached") {
                // Host is level authority: any player reaching the exit
                // advances the whole session
                if (net.isHost) session.advanceRequested()
            }
        }

        onStateReceived: (fromId, data, sentAt) => {
            let rp = remotePlayers[fromId]
            if (rp) rp.pushState(data, sentAt)
        }

        onNodeLeft: (nodeId) => {
            if (remotePlayers[nodeId]) {
                remotePlayers[nodeId].destroy()
                delete remotePlayers[nodeId]
            }
        }
    }

    // Sync health overlay (multiplayer only)
    NetworkMonitor {
        network: net
        visible: net.connected && session.inGame
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 10
    }

    // Player state broadcast: one snapshot per physics step (60 Hz), so the
    // stream carries exactly the motion the simulation produced instead of a
    // free-running timer sampling it. The lossy state channel makes the rate
    // cheap; the payoff is that RemotePlayer can render only ~50 ms behind
    // (see docs/multiplayer-sync.md for the measurements behind this).
    Connections {
        target: world ? world.physics : null
        enabled: session.inGame && net.connected && player !== null
        function onStepped() {
            net.broadcastState({
                x: player.xWu,
                y: player.yWu,
                a: player.facingAngle,
                s: player.isAttacking ? 1 : player.isBlocking ? 2 : player.isDashing ? 3 : 0,
                // The block on its own: s shows only one action, and a
                // swing while blocking would hide the shield
                b: player.isBlocking ? 1 : 0,
                h: player.hp
            })
        }
    }

    // Host: start the game for everyone with this seed
    function start(seed) {
        net.broadcast({type: "gameStart", seed: seed})
        started(seed)
    }

    // Reliable event so remote clients show an action crisply
    function sendAction(action) {
        if (net.connected)
            net.broadcast({type: "action", action: action})
    }

    // A hit the local player landed or took, for the others to draw
    function sendImpact(kind, x, y, dx, dy, color) {
        if (net.connected && inGame)
            net.broadcast({type: "impact", kind: kind, x: x, y: y, dx: dx, dy: dy,
                           color: color === undefined ? undefined : String(color)})
    }

    // The local player reached the exit: the host advances, a joiner asks
    // the host, which answers with levelChange
    function reachExit() {
        if (net.isHost)
            advanceRequested()
        else
            net.broadcast({type: "exitReached"})
    }

    // Host: tell the joiners which level comes next
    function announceLevel(levelIndex) {
        net.broadcast({type: "levelChange", levelIndex: levelIndex})
    }

    Component { id: remotePlayerComponent; RemotePlayer {} }

    function spawnRemotePlayers(px, py) {
        if (!net.connected) return
        let colors = ["#A44A90", "#90A44A", "#A4904A"]
        for (let i = 0; i < net.nodes.length; i++)
            _spawnRemotePlayer(net.nodes[i], colors[i % colors.length], px, py)
    }

    function _spawnRemotePlayer(nodeId, color, px, py) {
        let rp = remotePlayerComponent.createObject(world.room, {
            nodeId: nodeId,
            playerColor: color,
            xWu: px,
            yWu: py,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            rttMs: Qt.binding(() => net.latency),
            gameWorld: world
        })
        if (rp) {
            remotePlayers[nodeId] = rp
            console.log("[Session] Remote player created for", nodeId, "color:", color)
        }
    }

    function clearRemotePlayers() {
        for (let id in remotePlayers) {
            try { if (remotePlayers[id]) remotePlayers[id].destroy() } catch(err) {}
        }
        remotePlayers = ({})
    }

    // Multiplayer lobby
    Loader {
        anchors.fill: parent
        active: session.showLobby
        sourceComponent: Component {
            MultiplayerLobby {
                network: net
                onStartGame: session.lobbyStartRequested()
                onBack: { net.leave(); session.lobbyLeft() }
            }
        }
    }
}
