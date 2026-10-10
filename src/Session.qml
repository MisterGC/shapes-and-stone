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
    property real soundVolume: 1     // and its sounds at this share
    // This node's knight's name, edited in the lobby (nameEdited)
    property string playerName: "Knight"
    // The record the lobby shows, Game.recordLine
    property string recordLine: ""

    readonly property bool connected: net.connected
    readonly property bool isHost: net.isHost
    readonly property string nodeId: net.nodeId
    // The Network itself, only for the ReplicatedObject in each enemy
    readonly property var network: net

    // The run is on: the host started it, or this node joined one under
    // way (also emitted on the host itself). levelIndex is the level the
    // host plays, 0 at the start; position and next are the danger's
    // positions it plays it at (Game.dangerPosition, Game.nextPosition),
    // knights the knights the host built the level for (Game.partyKnights)
    signal started(int seed, int levelIndex, real position, real next, int knights)
    // Every client applies this level at the host's danger, built for the
    // host's knights; the host is the level authority
    signal levelChanged(int levelIndex, real position, real next, int knights)
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
    // (amount, x, y), "stagger" (seconds) or "push" (dx, dy, speed)
    signal enemyBlowReceived(string fromId, var blow)
    // An enemy of the host's lunged at this node's knight (atk, x, y, size)
    signal knightBlowReceived(var blow)
    // This node's knight dealt the blow that killed an enemy of the host's
    // (id, x, y, dx, dy, color)
    signal enemyKillReceived(var kill)
    // A spitter of the host's fired (id, x, y, dx, dy, damage)
    signal shotReceived(var shot)
    // The host owns every gold drop as a replicated object of type "gold",
    // as it owns the enemies; it came to life or went on this node
    signal goldSpawned(string objectId, var props)
    signal goldDespawned(string objectId)
    // Host: a node's knight reached a drop and asks for it
    signal goldClaimed(string fromId, string objectId)
    // The host gave this node's knight a drop (id, amount)
    signal goldGranted(var grant)
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
    // The run is over for everyone, the session stays: on a joiner when
    // the host ends it, on the host at once
    signal runEnded()
    // The host started the next run after the party had fallen: this
    // joiner goes again from depth 0 on this seed, at this position in
    // its range, its first dungeon built for knights
    signal wentAgain(int seed, real position, int knights)
    // Another node's knight stood beside this node's fallen knight long
    // enough: it rises (Balance.party)
    signal liftReceived(string fromId)
    // The name was edited in the lobby
    signal nameEdited(string name)
    // Joiner: the host's party went deeper than the host's record, with
    // the banner in the dungeon or, at the run's end, without it
    signal recordBroken(bool banner)

    // Every knight's name by its node, the session property "names": each
    // node sends its own to the host, which sets it
    readonly property var names: net.connected && net.sessionProperties.names
                                 ? net.sessionProperties.names : ({})
    // The host's record, the party's ({depth, names, date}), the session
    // property "record"; null before the host has set it
    readonly property var hostRecord: net.connected && net.sessionProperties.record
                                      ? net.sessionProperties.record : null
    // The session's runs the host counted, newest first ({depth, seconds}),
    // the session property "runs"
    readonly property var hostRuns: net.connected && net.sessionProperties.runs
                                    ? net.sessionProperties.runs : []
    // Host: the names it has been sent
    property var _names: ({})

    property var remotePlayers: ({})
    // The last state each other node sent, also while its knight is not
    // made (a level being built, a run not yet joined): a knight made
    // starts from it, a downed one downed
    property var lastStates: ({})
    // This node is leaving on its own: its session ending is no lost host
    property bool _leaving: false
    // The knights in the session, this node's among them: what the host
    // builds the next level for
    readonly property int knights: net.connected ? net.nodeCount : 1
    // The seed of the run this node plays: a new one from the host is the
    // next run, the same one a level of this run
    property int runSeed: -1

    Network {
        id: net
        maxNodes: 4
        topology: Network.Topology.Star
        signalingMode: Network.SignalingMode.Cloud
        autoRelay: true

        // The run is the session property "run", its seed, the level
        // played, the danger's positions (pos, next) and the knights it
        // was built for (knights): the host sets it
        // when the run starts and at each level, and a node that joins
        // late gets it with its welcome (clayground#306)
        onSessionPropertyChanged: (name, value) => {
            if (net.isHost || name !== "run") return
            let again = session.inGame && value.seed !== session.runSeed
            let knights = value.knights || 1
            session.runSeed = value.seed
            if (!session.inGame) session.started(value.seed, value.level, value.pos, value.next, knights)
            else if (again) {
                session.lastStates = ({})
                session.wentAgain(value.seed, value.pos, knights)
            }
            else session.levelChanged(value.level, value.pos, value.next, knights)
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
            } else if (data.type === "goldClaim") {
                if (net.isHost) session.goldClaimed(fromId, data.id)
            } else if (data.type === "goldGrant") {
                session.goldGranted(data)
            } else if (data.type === "shot") {
                session.shotReceived(data)
            } else if (data.type === "struck") {
                session.struckReported(fromId, data)
            } else if (data.type === "lift") {
                session.liftReceived(fromId)
            } else if (data.type === "name") {
                if (net.isHost) session._setName(fromId, data.name)
            } else if (data.type === "newRecord") {
                if (!net.isHost) session.recordBroken(data.banner === true)
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
            else if (type === "gold") session.goldSpawned(id, props)
        }
        onObjectDespawned: (id, type) => {
            if (type === "enemy") session.enemyDespawned(id)
            else if (type === "gold") session.goldDespawned(id)
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
            if (net.isHost && _names[nodeId] !== undefined) {
                delete _names[nodeId]
                net.setSessionProperty("names", _names)
            }
            session.playerLeft(nodeId)
            session.partyChanged()
        }

        onConnectedChanged: {
            if (net.connected) {
                session._leaving = false
                // Later: a host can set no session property before its
                // connectedChanged is over
                Qt.callLater(session._sendName)
            } else {
                session.lastStates = ({})
                session.runSeed = -1
                session._names = ({})
            }
        }
        // reason is "host-left" when the host left on its own, else it
        // crashed or the connection was lost (clayground#376)
        onHostLost: (reason, message) => {
            if (!session.inGame || session._leaving) return
            session.hostLost(reason === "host-left"
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
            let state = {
                x: player.xWu,
                y: player.yWu,
                a: player.facingAngle,
                // 4 while the knight charges a heavy swing, 5 once it is full
                s: player.isAttacking ? 1 : player.isBlocking ? 2 : player.isDashing ? 3
                   : player.chargeFull ? 5 : player.isCharging ? 4 : 0,
                // The block on its own: s shows only one action, and a
                // swing while blocking would hide the shield
                b: player.isBlocking ? 1 : 0,
                h: player.hp
            }
            // This knight's record of the level (lv), for the host to set
            // the next dungeon's danger from: the share of its max HP lost
            // (l) and, once it fell, f
            let rec = world.levelRecord()
            state.lv = world.levelIndex
            state.l = Math.round(rec.lost * 1000) / 1000
            if (rec.fell) state.f = 1
            // Lifting a fallen ally up: whose knight and how far, for the
            // ring every screen draws around it
            if (player.reviveTarget !== "") {
                state.v = player.reviveTarget
                state.p = Math.round(player.reviveProgress * 1000) / 1000
            }
            net.broadcastState(state)
        }
    }

    // Host: start the game for everyone with this seed, its first dungeon
    // at this position in its range, built for knights
    function start(seed, position, knights) {
        runSeed = seed
        net.setSessionProperty("run", {seed: seed, level: 0, pos: position, next: position,
                                       knights: knights})
        started(seed, 0, position, position, knights)
    }

    // Host: the party has fallen, the next run starts for everyone on this
    // seed. The last states are of the run before, whose knights were down:
    // each knight of the next run is drawn from its first state in it (on
    // a joiner too, when wentAgain comes)
    function goAgain(seed, position, knights) {
        if (!net.isHost) return
        runSeed = seed
        lastStates = ({})
        net.setSessionProperty("run", {seed: seed, level: 0, pos: position, next: position,
                                       knights: knights})
    }

    // The name goes to the host, which sets it for every node; the host's
    // own straight into the session property
    onPlayerNameChanged: _sendName()
    function _sendName() {
        if (!net.connected) return
        if (net.isHost) _setName(net.nodeId, playerName)
        else net.sendTo(net.hostId, {type: "name", name: playerName})
    }
    function _setName(nodeId, name) {
        _names[nodeId] = String(name).slice(0, 16)
        net.setSessionProperty("names", _names)
    }
    // A node's knight's name; "Knight" before it has sent one
    function nameOf(nodeId) {
        let n = names[nodeId]
        return n ? n : "Knight"
    }
    // The names of every knight in the session, from the host's list: the
    // host's first, the others by their node, so each screen has them in
    // the same order
    function partyNames() {
        let others = Object.keys(names).filter(id => id !== net.hostId).sort()
        return [nameOf(net.hostId)].concat(others.map(id => names[id]))
    }
    // Host: its record is the party's, for every screen
    function publishRecord(record) {
        if (net.isHost) net.setSessionProperty("record", record)
    }
    // Host: the session's runs, newest first, for every fallen screen
    function publishRuns(runs) {
        if (net.isHost) net.setSessionProperty("runs", runs)
    }
    // Host: the party went deeper than the record, every screen tells it
    function announceRecord(banner) {
        if (net.isHost) net.broadcast({type: "newRecord", banner: banner})
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
    // Host: gold where an enemy died, for every node
    function spawnGold(props) {
        return net.spawn("gold", props)
    }
    // Host: the drop is gone, on every node
    function despawnGold(objectId) {
        net.despawn(objectId)
    }
    // This node's knight reached a drop: the host gives it to the first
    // node that claims it. The host's own claim is answered at once
    function claimGold(objectId) {
        if (net.isHost) goldClaimed(net.nodeId, objectId)
        else net.sendTo(net.hostId, {type: "goldClaim", id: objectId})
    }
    // Host: the drop goes to that node's knight
    function grantGold(nodeId, grant) {
        net.sendTo(nodeId, Object.assign({type: "goldGrant"}, grant))
    }
    // Host: a spitter fired, every node flies the shot
    function sendShot(shot) {
        net.broadcast(Object.assign({type: "shot"}, shot))
    }
    // This node judged an attack on its own knight, for every other node
    function reportStruck(report) {
        net.broadcast(Object.assign({type: "struck"}, report))
    }

    // This node's knight lifted that node's fallen knight up. A knight
    // made without a session (fakeDownedAlly) rises here
    function liftKnight(nodeId) {
        if (net.connected) {
            net.sendTo(nodeId, {type: "lift"})
            return
        }
        let rp = remotePlayers[nodeId]
        if (rp) rp.remoteHp = Math.round(Balance.party.reviveHp * Balance.knight.hp)
    }
    // How far the other nodes' knights have lifted that node's knight up,
    // 0..1, from their last states: the furthest of them
    function liftOf(nodeId) {
        let best = 0
        for (let id in lastStates) {
            let st = lastStates[id]
            if (st && st.v === nodeId && st.p > best) best = st.p
        }
        return best
    }

    // Host: every knight is down, the run ends for everyone; nobody leaves
    // the session, so the host can start the next run (goAgain)
    function endRun() {
        if (!net.isHost) return
        net.broadcast({type: "runEnd"})
        runEnded()
    }

    // Host: tell the joiners which level comes next, at which danger and
    // for how many knights, and every node that joins later which one is
    // played
    function announceLevel(levelIndex, position, next, knights) {
        net.setSessionProperty("run", {seed: net.sessionProperties.run.seed,
                                       level: levelIndex, pos: position, next: next,
                                       knights: knights})
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

    // The dojo, without a session: a fallen ally beside the knight, to be
    // lifted up as one of a session would (Balance.party). It goes with
    // the level, as every other node's knight does
    function fakeDownedAlly(px, py) {
        let id = "dojo-ally"
        if (remotePlayers[id]) remotePlayers[id].destroy()
        let rp = remotePlayerComponent.createObject(world.room, {
            nodeId: id,
            playerColor: _colorOf(id),
            xWu: px,
            yWu: py,
            remoteHp: 0,
            known: true,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            gameWorld: world
        })
        remotePlayers[id] = rp
        return rp
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
                soundVolume: session.soundVolume
                playerName: session.playerName
                onPlayerNameChanged: session.nameEdited(playerName)
                names: session.names
                recordLine: session.recordLine
                onStartGame: session.lobbyStartRequested()
                onBack: { net.leave(); session.lobbyLeft() }
            }
        }
    }
}
