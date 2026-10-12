// Master party bench - one of two game instances, a host or a joiner,
// that run_masterparty.py starts as two processes (clayliveloader
// --instance), connects over Local or Cloud signaling and drives through
// the inspector protocol (issue #142).
//
// The instance runs the real game. The host ticks Dungeon Master, sets
// the panel's settings, generates and goes; the driver reads the dungeon
// the host's panel showed and the one each screen built.

import QtQuick
import Clayground.Network
import "../../src"

Item {
    id: bench
    anchors.fill: parent

    Game {
        id: game
        anchors.fill: parent
        muted: true
        // A store of its own: the bench keeps neither a record nor the
        // player's dungeon master settings
        recordStoreName: "ShapesAndStoneMasterPartyBench"
    }

    // ---- the game's Session and its Network, found by what they offer ----
    readonly property var session: {
        for (let i = 0; i < game.data.length; i++)
            if (typeof game.data[i].sendImpact === "function") return game.data[i]
        return null
    }
    readonly property var net: session ? session.network : null

    // ---- driver API ----
    property bool useLocalSignaling: true
    readonly property string netId: net ? net.networkId : ""
    readonly property string nodeId: net ? net.nodeId : ""
    readonly property bool connected: net ? net.connected : false
    readonly property int nodeCount: net ? net.nodeCount : 0

    function configure(local) {
        useLocalSignaling = local
        return net !== null
    }
    function _mode() {
        return useLocalSignaling ? Network.SignalingMode.Local : Network.SignalingMode.Cloud
    }
    function hostUp() { net.signalingMode = _mode(); net.host() }
    function joinNet(code) { net.signalingMode = _mode(); net.join(code) }
    function leave() { if (net) net.leave() }

    // The dungeon master on this node, with these settings (JSON) and
    // nothing else set
    function master(on, settings) {
        game.setDungeonMaster(on)
        game.masterPinned = ({})
        return settings ? game.masterPaste(settings) : true
    }
    // Host: start the session's game on this seed; with the mode on the
    // panel comes up first
    function startGame(s) {
        game.masterSeed = s
        game._startMultiplayerGame()
        return game.masterOpen
    }
    // Host: the next level for every node, as when a knight reaches the
    // exit; into a dungeon the panel comes up first
    function advance() {
        game._hostAdvanceLevel()
        return game.masterOpen
    }
    function panelUp() { return game.masterOpen }
    function turn(key, steps) { game.masterTurn(key, steps); return game.masterSettingsJson() }
    function generate() { game.masterGenerate(); return game.masterPreview ? game.masterPreview.seed : null }
    function go() { game.masterGo(); return true }

    // In a dungeon with the other player's knight and the host's enemies
    function inRun() {
        return game.screen === "game" && game.player !== null && game.levelType === "dungeon"
               && session !== null && Object.keys(session.remotePlayers).length > 0
               && game.enemies.length > 0
    }
    function where() {
        return { screen: game.screen, level: game.levelIndex, type: game.levelType,
                 knight: game.player !== null }
    }
    // Every enemy stands where it is
    function halt() {
        for (let e of game.enemies) if (e && e.halt) e.halt()
        return game.enemies.length
    }
    function standUp() { if (game.player) game.player.hp = 100000 }

    // The dungeon this screen built and the overrides it was built with
    function built() {
        return { master: game.master, seed: game.levelSeedNow(), danger: game.danger,
                 grid: JSON.stringify(game.grid), rooms: game.rooms,
                 features: game.features.map(f => [f.kind, f.gx, f.gy]),
                 enemies: game.enemies.filter(e => e && !e.destroyed && e._spawnXWu !== undefined)
                          .map(e => [Number(e._spawnXWu).toFixed(3), Number(e._spawnYWu).toFixed(3), e.tier, e.enemyType]) }
    }
    // Host: the dungeon the panel showed
    function shown() {
        let p = game.masterPreview
        if (!p) return null
        return { seed: p.seed, danger: p.depth + p.position, grid: JSON.stringify(p.grid), rooms: p.rooms,
                 features: p.features.map(f => [f.kind, f.gx, f.gy]),
                 enemies: p.enemies.map(e => [e.x.toFixed(3), e.y.toFixed(3), e.tier, e.type]) }
    }
}
