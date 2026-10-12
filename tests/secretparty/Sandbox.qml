// Secret party bench - one of two game instances, a host or a joiner,
// that run_secretparty.py starts as two processes (clayliveloader
// --instance), connects over Local or Cloud signaling and drives through
// the inspector protocol (issue #128).
//
// The instance runs the real game. The driver stands a knight in front of
// a secret door, or one tile off, has it dash into the wall there and
// reads the secret rooms each screen shows.

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
        recordStoreName: "ShapesAndStoneSecretPartyBench"
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

    // The first seed from s on whose first dungeon hides a secret room
    function seedWithSecret(s) {
        for (let k = s; k < s + 200; k++) {
            game.masterSeed = k
            if (game.secretsOf(0, Balance.danger.start) > 0) return k
        }
        return -1
    }

    // The secret rooms on this screen: the cracked cell, whether it is
    // open, whether its door and room are floor in the grid, and its cache
    // things standing
    function secrets() {
        if (!game.secretRooms) return []
        return game.secretRooms.map(s => {
            let floor = game.grid[s.gy][s.gx] !== game.cellWall
            for (let y = s.room.y; y < s.room.y + s.room.h; y++)
                for (let x = s.room.x; x < s.room.x + s.room.w; x++)
                    floor = floor && game.grid[y][x] !== game.cellWall
            let rock = game.grid[s.gy][s.gx] === game.cellWall
            for (let y = s.room.y; y < s.room.y + s.room.h; y++)
                for (let x = s.room.x; x < s.room.x + s.room.w; x++)
                    rock = rock && game.grid[y][x] === game.cellWall
            return { cell: s.cell, open: s.open, floor: floor, rock: rock,
                     cache: s.cache.filter(f => game.breakableAt(f.gx + "," + f.gy) !== null).length }
        })
    }
    function secretOf(cell) {
        return secrets().find(s => s.cell === cell) || null
    }
    // This knight's centre in front of the secret on cell, moved k cells
    // along the wall, 0.3 wu off its face
    function standBefore(cell, k) {
        let s = game.secretAt(cell)
        if (!s) return false
        let p = game.player
        let d = game.cellSize / 2 + p.widthWu / 2 + 0.3
        let x = (s.gx + s.ny * k + 0.5) * game.cellSize + s.nx * d
        let y = (s.gy + s.nx * k + 0.5) * game.cellSize + s.ny * d
        p.xWu = x - p.widthWu / 2
        p.yWu = y + p.heightWu / 2
        p.moveX = 0
        p.moveY = 0
        return true
    }
    // This knight dashes straight into the wall of the secret on cell; its
    // moves are on screen, y down. False when it could not dash
    function dashInto(cell) {
        let s = game.secretAt(cell)
        if (!s) return false
        let p = game.player
        p.dashCooldown = 0
        p.mana = 1000
        p.moveX = -s.nx
        p.moveY = s.ny
        p.dash()
        p.moveX = 0
        p.moveY = 0
        return p.isDashing
    }
    function found() { return game.runSecrets }
    function level() { return game.levelIndex }
}
