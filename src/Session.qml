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

    // The run is on: the host started it, or this node joined one under
    // way (also emitted on the host itself). levelIndex is the level the
    // host plays, 0 at the start
    signal started(int seed, int levelIndex)
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
    // An enemy of the host's lunged at this node's knight (atk, x, y, size)
    signal knightBlowReceived(var blow)
    // This node's knight dealt the blow that killed an enemy of the host's
    // (id, x, y, dx, dy, color)
    signal enemyKillReceived(var kill)
    // A spitter of the host's fired (id, x, y, dx, dy, damage)
    signal shotReceived(var shot)
    // Another node judged an attack on its own knight: report.source is
    // "lunge" (id: the enemy's) or "shot" (id: the shot's), report.result
    // what became of it (Game.knightStruck)
    signal struckReported(string fromId, var report)
    // Another knight's HP changed or its node left: the party may be down
    // now
    signal partyChanged()
    // A node joined the run under way, or left it; its knight is already
    // made or gone on this screen
    signal playerJoined(string nodeId)
    signal playerLeft(string nodeId)
    // Another player's knight was made on this screen
    signal remotePlayerSpawned(string nodeId, var knight)
    // A joiner's session ended without its leaving: the host left, crashed
    // or lost its connection. message says which, for the title
    signal hostLost(string message)
    // The run is over for everyone: on a joiner when the host ends it, on
    // the host once the joiners have left or endRunWaitMs has passed
    signal runEnded()

    property var remotePlayers: ({})
    // The last state each other node sent, also while its knight is not
    // made (a level being built, a run not yet joined): a knight made
    // starts from it, a downed one downed
    property var lastStates: ({})
    // This node is leaving on its own: its session ending is no lost host
    property bool _leaving: false
    property string _lastError: ""
    // The host's run as far as its session properties have come
    property var _run: ({})

    Network {
        id: net
        maxNodes: 4
        topology: Network.Topology.Star
        signalingMode: Network.SignalingMode.Cloud
        autoRelay: true

        // The run is two session properties, its seed and the level played:
        // the host sets them when the run starts and the level at each
        // level, and a node that joins late gets both with its welcome
        // (clayground#306). Numbers each: an object as a session property
        // reaches the joiners as null at the clayground pin - a workaround
        // that waits on clayground#375
        onSessionPropertyChanged: (name, value) => {
            if (net.isHost || (name !== "seed" && name !== "level")) return
            // Kept from the signal: Network.sessionProperties follows only
            // after it (the same workaround, clayground#375)
            let run = session._run
            run[name] = value
            if (run.seed === undefined || run.level === undefined) return
            if (!session.inGame) session.started(run.seed, run.level)
            else if (name === "level") session.levelChanged(run.level)
        }

        onMessageReceived: (fromId, data) => {
            if (data.type === "action") {
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
            } else if (data.type === "runEnd") {
                if (!net.isHost) session.runEnded()
            } else if (data.type === "exitReached") {
                // Host is level authority: any player reaching the exit
                // advances the whole session
                if (net.isHost) session.advanceRequested()
            }
        }

        onStateReceived: (fromId, data, sentAt) => {
            lastStates[fromId] = data
            let rp = remotePlayers[fromId]
            if (rp) rp.pushState(data, sentAt)
        }

        onObjectSpawned: (id, type, owner, props) => {
            if (type === "enemy") session.enemySpawned(id, props)
        }
        onObjectDespawned: (id, type) => {
            if (type === "enemy") session.enemyDespawned(id)
        }

        // A node that joins a run under way gets its knight here; the
        // joiner makes the others' when it builds the level
        onNodeJoined: (nodeId) => {
            if (!session.inGame || !session._levelUp() || remotePlayers[nodeId]) return
            let p = session.player
            session._spawnRemotePlayer(nodeId, session._colorOf(nodeId), p.xWu, p.yWu)
            session.playerJoined(nodeId)
        }

        onNodeLeft: (nodeId) => {
            if (remotePlayers[nodeId]) {
                remotePlayers[nodeId].destroy()
                delete remotePlayers[nodeId]
            }
            delete lastStates[nodeId]
            session.playerLeft(nodeId)
            session.partyChanged()
        }

        onErrorOccurred: (message) => session._lastError = message
        onConnectedChanged: {
            if (net.connected) {
                session._leaving = false
                session._lastError = ""
            } else {
                session.lastStates = ({})
                session._run = ({})
                // The error that says why comes with the end or right after it
                if (session.inGame && !session._leaving) _hostLostCheck.restart()
            }
        }
    }
    // Why the host was lost is read from the error's text, and the error
    // comes after connected turned false, so it is waited for 50 ms: a
    // workaround that waits on clayground#376, a machine-readable reason
    Timer {
        id: _hostLostCheck
        interval: 50
        onTriggered: {
            if (net.connected || session._leaving || !session.inGame) return
            session.hostLost(session._lastError.indexOf("left") >= 0
                             ? "The host left the game"
                             : "Lost the connection to the host")
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
        net.setSessionProperty("seed", seed)
        net.setSessionProperty("level", 0)
        started(seed, 0)
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
        _leaving = true
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

    // Host: every knight is down, the run ends for everyone. The joiners
    // leave when the message arrives; the host leaves after them, so its
    // leaving cannot cut the message off.
    readonly property int endRunWaitMs: 2000
    function endRun() {
        if (!net.isHost || _endWait.running) return
        net.broadcast({type: "runEnd"})
        _endWait.waited = 0
        _endWait.start()
    }
    Timer {
        id: _endWait
        property int waited: 0
        interval: 50
        repeat: true
        onTriggered: {
            waited += interval
            if (Object.keys(session.remotePlayers).length > 0 && waited < session.endRunWaitMs)
                return
            stop()
            session.runEnded()
        }
    }

    // Host: tell the joiners which level comes next, and every node that
    // joins later which one is played
    function announceLevel(levelIndex) {
        net.setSessionProperty("level", levelIndex)
    }

    Component { id: remotePlayerComponent; RemotePlayer {} }

    function spawnRemotePlayers(px, py) {
        if (!net.connected) return
        for (let i = 0; i < net.nodes.length; i++)
            _spawnRemotePlayer(net.nodes[i], _colorOf(net.nodes[i]), px, py)
    }

    function _colorOf(nodeId) {
        let colors = ["#A44A90", "#90A44A", "#A4904A"]
        return colors[Math.max(0, net.nodes.indexOf(nodeId)) % colors.length]
    }
    // The level is built: this node's knight stands in it. While one is
    // built, the knights of every node are made with it
    function _levelUp() { return player !== null }

    function _spawnRemotePlayer(nodeId, color, px, py) {
        // Where the knight is comes with its next state; its HP is the
        // last one it sent, so a downed knight is never drawn standing.
        // Without one (a node that just joined, or this node did) it is
        // drawn from its first state on
        let last = lastStates[nodeId]
        let rp = remotePlayerComponent.createObject(world.room, {
            nodeId: nodeId,
            playerColor: color,
            xWu: px,
            yWu: py,
            remoteHp: last && last.h !== undefined ? last.h : Balance.knight.hp,
            known: last !== undefined,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            rttMs: Qt.binding(() => net.latency),
            gameWorld: world
        })
        if (rp) {
            rp.remoteHpChanged.connect(session.partyChanged)
            remotePlayers[nodeId] = rp
            console.log("[Session] Remote player created for", nodeId, "color:", color,
                        "HP:", rp.remoteHp)
            remotePlayerSpawned(nodeId, rp)
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
