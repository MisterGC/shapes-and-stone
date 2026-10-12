// Spike party bench - one of two game instances, a host or a joiner, that
// run_spikeparty.py starts as two processes (clayliveloader --instance),
// connects over Local or Cloud signaling and drives through the inspector
// protocol (issue #124).
//
// The instance runs the real game. The driver stands a knight on one of
// the dungeon's spike plates, or has it dash off at the click, and reads
// what each screen shows: each plate's phase, its knight's HP and the
// other knight's HP as this screen has it.

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
        recordStoreName: "ShapesAndStoneSpikePartyBench"
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
    // The knight at full HP, its mana and dash ready
    function fresh() {
        let p = game.player
        p.hp = p.maxHp
        p.graceLeft = 0
        p.mana = p.maxMana
        p.dashCooldown = 0
        return true
    }

    // The spike plates on this screen, by cell, with their phase and what
    // their spikes did to this knight (none before issue #124)
    function plates() {
        if (!game.plates) return []
        return game.plates.map(q => ({ cell: q.cell, x: q.xWu, y: q.yWu, phase: q.phase, result: q.result,
                                       out: wayOut(q) !== null }))
    }
    function hp() { return game.player ? game.player.hp : -1 }
    function maxHp() { return game.player ? game.player.maxHp : -1 }
    // What a plate's spikes take from this knight here
    function damage() { return game.spikeDamageAt(game.depth, game.player.maxHp) }
    // The other knight's HP as this screen has it
    function otherHp() {
        let ids = Object.keys(session.remotePlayers)
        return ids.length ? session.remotePlayers[ids[0]].remoteHp : -1
    }
    // This knight's centre on (x, y)
    function moveTo(x, y) {
        let p = game.player
        p.xWu = x - p.widthWu / 2
        p.yWu = y + p.heightWu / 2
        p.moveX = 0
        p.moveY = 0
        return true
    }
    // This knight back in the start room, off every plate
    function moveHome() {
        let r = game.rooms[0]
        return moveTo((r.x + r.w / 2) * game.cellSize, (r.y + r.h / 2) * game.cellSize)
    }

    // The plate on dashAt: this knight dashes off it at its click, the
    // way out three floor cells in a row with no breakable on them
    property string dashAt: ""
    function dashOff(cell) { dashAt = cell; return game.plateAt(cell) !== null }
    function wayOut(q) {
        let gx = Math.floor(q.xWu / game.cellSize), gy = Math.floor(q.yWu / game.cellSize)
        for (let d of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            let ok = true
            for (let i = 1; i <= 3; i++) {
                let x = gx + d[0] * i, y = gy + d[1] * i
                if (!game.grid[y] || game.grid[y][x] === undefined || game.grid[y][x] === game.cellWall
                        || game.breakableAt(x + "," + y)) ok = false
            }
            if (ok) return [d[0], -d[1]]
        }
        return null
    }
    Connections {
        target: game
        function onPlateClicked(cell) {
            if (cell !== bench.dashAt) return
            let q = game.plateAt(cell), d = bench.wayOut(q), p = game.player
            p.moveX = d[0]
            p.moveY = d[1]
            p.dash()
            p.moveX = 0
            p.moveY = 0
            bench.dashAt = ""
        }
    }
}
