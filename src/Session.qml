import QtQuick
import Clayground.Network

// The co-op session: owns the Network, the lobby-to-game flow, the
// registry of remote players and the host's enemies as replicated objects.
// Game.qml calls into it and reacts to its signals; it never touches the
// Network itself (only an enemy's ReplicatedObject is given it).
Item {
    id: session
    anchors.fill: parent

    // Set by the game
    property var world: null
    property var player: null
    property bool inGame: false      // the game screen is up
    property bool showLobby: false   // the lobby screen is up
    property bool muted: false       // the lobby plays no sound

    readonly property bool connected: net.connected
    readonly property bool isHost: net.isHost
    readonly property string nodeId: net.nodeId
    // The Network itself, only for the ReplicatedObject in each enemy
    readonly property var network: net

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
    // The host runs every enemy as a replicated object of type "enemy"; it
    // came to life or went on this node - a joiner's too, also one that
    // joins late (issue #13)
    signal enemySpawned(string objectId, var props)
    signal enemyDespawned(string objectId)
    // Host: another player's knight struck an enemy; blow.kind is "damage"
    // (amount, x, y), "stagger" or "push" (dx, dy, speed)
    signal enemyBlowReceived(string fromId, var blow)
    // An enemy of the host's lunged at this node's knight (atk, x, y)
    signal knightBlowReceived(var blow)
    // This node's knight dealt the blow that killed an enemy of the host's
    // (id, x, y, dx, dy, color)
    signal enemyKillReceived(var kill)
    // A spitter of the host's fired (x, y, dx, dy, damage)
    signal shotReceived(var shot)
    // Another node judged an attack on its own knight: report.source is
    // "lunge" (id: the enemy's), report.result what became of it
    // (Game.knightStruck)
    signal struckReported(string fromId, var report)

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
            } else if (data.type === "enemyBlow") {
                if (net.isHost) session.enemyBlowReceived(fromId, data)
            } else if (data.type === "knightBlow") {
                session.knightBlowReceived(data)
            } else if (data.type === "enemyKill") {
                session.enemyKillReceived(data)
            } else if (data.type === "shot") {
                session.shotReceived(data)
            } else if (data.type === "struck") {
                session.struckReported(fromId, data)
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

        onObjectSpawned: (id, type, owner, props) => {
            if (type === "enemy") session.enemySpawned(id, props)
        }
        onObjectDespawned: (id, type) => {
            if (type === "enemy") session.enemyDespawned(id)
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

    // Leave the session, e.g. for the title after the knight has fallen
    function leave() {
        net.leave()
    }

    // Host: an enemy for every node; the host owns it and runs its AI
    function spawnEnemy(props) {
        return net.spawn("enemy", props)
    }
    // Host: the enemy is gone, on every node
    function despawnEnemy(objectId) {
        net.despawn(objectId)
    }
    // Joiner: this node's knight struck an enemy, for the host to apply
    function strikeEnemy(objectId, blow) {
        net.sendTo(net.hostId, Object.assign({type: "enemyBlow", id: objectId}, blow))
    }
    // Host: an enemy lunged at another node's knight
    function strikeKnight(nodeId, blow) {
        net.sendTo(nodeId, Object.assign({type: "knightBlow"}, blow))
    }
    // Host: the blow of another node's knight killed an enemy
    function reportKill(nodeId, kill) {
        net.sendTo(nodeId, Object.assign({type: "enemyKill"}, kill))
    }
    // Host: a spitter fired, every node flies the shot
    function sendShot(shot) {
        net.broadcast(Object.assign({type: "shot"}, shot))
    }
    // This node judged an attack on its own knight, for every other node
    function reportStruck(report) {
        net.broadcast(Object.assign({type: "struck"}, report))
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
                muted: session.muted
                onStartGame: session.lobbyStartRequested()
                onBack: { net.leave(); session.lobbyLeft() }
            }
        }
    }
}
