// Vein party bench - one of two game instances, a host or a joiner, that
// run_veinparty.py starts as two processes (clayliveloader --instance),
// connects over Local or Cloud signaling and drives through the inspector
// protocol (issue #156).
//
// The instance runs the real game. The driver has a knight cut one of the
// dungeon's veins and reads what each screen shows: the veins, which of
// them are split, and each knight's pouch.

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
        // A record of its own: the bench keeps no best depth of the player's
        recordStoreName: "ShapesAndStoneVeinPartyBench"
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
    // Host: start the session's game on this seed
    function startGame(s) {
        game.masterSeed = s
        game._startMultiplayerGame()
    }
    function leave() { if (net) net.leave() }

    // In a dungeon with the other player's knight and the host's enemies
    function inRun() {
        return game.screen === "game" && game.player !== null
               && session !== null && Object.keys(session.remotePlayers).length > 0
               && game.enemies.length > 0
    }
    // Host: every enemy stands where it is
    function halt() {
        for (let e of game.enemies) if (e && e.halt) e.halt()
        return game.enemies.length
    }
    // The knight out of reach of a stray blow
    function standUp() { game.player.hp = 100000 }

    // The veins on this screen: cell, gem, strikes and whether split
    function veins() {
        return game.veins.map(v => ({ cell: v.cell, shape: v.shape, strikes: v.strikes, split: v.split }))
    }
    function pouch() { return game.player ? game.player.pouch : [] }

    // This knight cuts the vein on cell, every strike clean on its close:
    // it stands in front of its face, aims at it and the left button
    // starts the dig, and its strikes are judged at once on the dig's clock
    function cut(cell) {
        let v = game.veinAt(cell), p = game.player
        if (!v || v.split) return false
        game.endDig()
        p.xWu = v.faceXWu - p.widthWu / 2
        p.yWu = v.cyWu - v.sizeWu / 2 - 0.6 + p.heightWu / 2
        game.aimOverride = { x: v.faceXWu, y: v.faceYWu }
        if (!game.pressPick() || !game.dig || game.dig.vein !== v) return false
        for (let i = 0; i < v.strikes; i++) {
            game.dig.t = (i + 1) * Balance.deep.ringTime
            game.pressPick()
        }
        game.aimOverride = null
        return v.split
    }
}
