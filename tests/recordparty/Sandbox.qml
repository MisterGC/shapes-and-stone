// Record party bench - one of two game instances, a host or a joiner, that
// run_recordparty.py starts as two processes (clayliveloader --instance),
// connects over Local or Cloud signaling and drives through the inspector
// protocol (issue #101).
//
// prepare() gives the instance a record store of its own with a record and
// a knight's name in it, and only then makes the game, which loads them.
// The driver takes the party down past the host's record, lets it fall and
// go again, and reads what each screen shows of the record: the lobby, the
// HUD, the banner and the fall screen.

import QtQuick
import QtTest
import Clayground.Network
import Clayground.Storage
import "../../src"

Item {
    id: bench
    anchors.fill: parent

    property var game: null
    property string storeName: "ShapesAndStoneRecordPartyBench"
    KeyValueStore { id: store; name: bench.storeName }
    Component { id: gameComponent; Game {} }

    // ---- the game's Session and its Network, found by what they offer ----
    readonly property var session: {
        if (!game) return null
        for (let i = 0; i < game.data.length; i++)
            if (typeof game.data[i].sendImpact === "function") return game.data[i]
        return null
    }
    readonly property var net: session ? session.network : null

    // Every banner this screen raised, by the depth it was at
    property var banners: []

    // Sends a key the way a keyboard does, to whatever has the focus
    TestEvent { id: keys }

    // ---- driver API ----
    property bool useLocalSignaling: true
    readonly property string netId: net ? net.networkId : ""
    readonly property string nodeId: net ? net.nodeId : ""
    readonly property bool connected: net ? net.connected : false
    readonly property int nodeCount: net ? net.nodeCount : 0

    // A store of this instance's own (role), holding record (JSON) and the
    // knight's name; then the game, in the lobby
    function prepare(local, role, record, name) {
        useLocalSignaling = local
        storeName = "ShapesAndStoneRecordPartyBench-" + role
        store.remove("bestDepth")
        store.set("record", record)
        store.set("playerName", name)
        game = gameComponent.createObject(bench, {width: bench.width, height: bench.height,
                                                  muted: true, recordStoreName: storeName})
        game.anchors.fill = bench
        game.recordBanner.connect(d => banners.push(d))
        game.screen = "lobby"
        return net !== null
    }
    function _mode() {
        return useLocalSignaling ? Network.SignalingMode.Local : Network.SignalingMode.Cloud
    }
    function hostUp() { net.signalingMode = _mode(); net.host() }
    function joinNet(code) { net.signalingMode = _mode(); net.join(code) }
    // Host: start the session's game on this seed
    function startGame(s) {
        game.masterSeed = s
        game._startMultiplayerGame()
    }
    function leave() { if (net) net.leave() }

    function inRun() {
        return game.screen === "game" && game.player !== null && !game.fallen
               && session !== null && Object.keys(session.remotePlayers).length > 0
    }
    // Host: one level down
    function advance() { game._hostAdvanceLevel() }
    // The knight out of the enemies' reach while the bench leads it down
    function standUp() { game.player.hp = 100000 }
    function strikeDown() {
        let p = game.player
        p.isBlocking = false
        p.graceLeft = 0
        p.takeDamage(10 * Math.max(p.hp, p.maxHp), p.xWu + 1, p.yWu)
    }
    function enter() {
        let fs = _visible("fallenScreen")
        if (!fs) return false
        fs.forceActiveFocus()
        keys.keyClick(Qt.Key_Return, Qt.NoModifier, -1)
        return true
    }

    // What this screen shows of the record
    function show() {
        let fs = _visible("fallenScreen")
        let stored = null
        try { stored = JSON.parse(store.get("record", "null")) } catch (err) {}
        return {
            screen: game.screen, level: game.levelIndex, depth: game.depth, seed: game.masterSeed,
            fallen: game.fallen, partyFallen: game.partyFallen, connected: connected,
            lobby: _text(_visible("lobbyRecord")),
            names: session ? session.partyNames() : [],
            hud: _text(_visible("gaugeRecord")),
            banners: banners,
            bannerUp: _find(game, "recordBanner").opacity > 0,
            fallenRecord: fs ? _text(_find(fs, "fallenRecord")) : null,
            runs: fs ? _findAll(fs, "fallenRun").map(t => t.text) : null,
            stored: stored
        }
    }

    function _text(t) { return t ? t.text : null }
    function _find(root, name) {
        if (!root) return null
        if (root.objectName === name) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = _find(kids[i], name)
            if (f) return f
        }
        return null
    }
    function _findAll(root, name, out) {
        out = out || []
        if (!root) return out
        if (root.objectName === name) out.push(root)
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) _findAll(kids[i], name, out)
        return out
    }
    function _visible(name) {
        let f = _find(game, name)
        return f && f.visible ? f : null
    }
}
