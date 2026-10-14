// Stone party bench - one of two game instances, a host or a joiner,
// that run_stoneparty.py starts as two processes (clayliveloader
// --instance), connects over Local or Cloud signaling and drives through
// the inspector protocol (issue #158).
//
// The instance runs the real game. The driver has a knight free a
// petrified traveller, every strike clean, and reads what each screen
// shows of the travellers: where they stand, whether freed, how each goes
// on and what they did.

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
        recordStoreName: "ShapesAndStoneStonePartyBench"
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
    // Host: every enemy stands where it is, also each one a hole sends
    property bool keepHalted: false
    function halt() {
        keepHalted = true
        _haltAll()
        return game.enemies.length
    }
    function _haltAll() {
        for (let e of game.enemies) if (e && !e.destroyed && !e.halted && e.halt) e.halt()
    }
    Timer {
        interval: 20
        repeat: true
        running: bench.keepHalted
        onTriggered: bench._haltAll()
    }
    // The knight out of reach of a stray blow
    function standUp() { game.player.hp = 100000 }

    // The spawn holes on this screen: cell, its veins, stage and waves
    function holes() {
        return game.holes.map(h => ({ cell: h.cell, veins: h.veinCells, stage: h.stage, wave: h.wave }))
    }

    // The petrified travellers on this screen: cell, kind, strikes,
    // whether freed, how it goes on, gone, where its feet stand, its
    // colour back and its fade
    function stones() {
        return game.stones.map(s => ({ cell: s.cell, kind: s.kind, strikes: s.strikes, freed: s.freed,
                                       outcome: s.outcome, gone: s.gone, x: s.footXWu, y: s.footYWu,
                                       colour: s.colour, fade: s.fade, saying: s.saying, hole: s.holeCell }))
    }
    // What they did on this screen: [{cell, what, t}]
    function stoneEvents() { return game.stoneEvents }
    function stoneSounds() { return game.stoneSounds }
    // Where the miner on cell works, {x, y}
    function workSpot(cell) {
        let s = game.stoneAt(cell)
        return s ? game._workSpot(s) : null
    }

    // This knight frees the traveller on cell, every strike clean on its
    // close: it stands in front of it, aims at it and the left button
    // starts the dig, and its strikes are judged at once on the dig's
    // clock
    function free(cell) {
        let s = game.stoneAt(cell), p = game.player
        if (!s || s.freed) return false
        game.endDig()
        p.xWu = s.faceXWu - p.widthWu / 2
        p.yWu = s.cyWu - s.sizeWu / 2 - 0.6 + p.heightWu / 2
        game.aimOverride = { x: s.faceXWu, y: s.faceYWu }
        if (!game.pressPick() || !game.dig || game.dig.stone !== s) return false
        for (let i = 0; i < s.strikes; i++) {
            game.dig.t = (i + 1) * Balance.deep.stone.ringTime
            game.pressPick()
        }
        game.aimOverride = null
        return s.freed
    }
}
