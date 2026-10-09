// Danger party bench - one of two game instances, a host or a joiner,
// that run_dangerparty.py starts as two processes (clayliveloader
// --instance), connects over Local or Cloud signaling and drives through
// the inspector protocol (issue #96).
//
// The instance runs the real game. The driver makes up each knight's
// record of a dungeon, lets the host lead the party down and reads what
// each screen shows: the danger of the level and the dungeon's look.

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
        recordStoreName: "ShapesAndStoneDangerPartyBench"
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

    // In a dungeon with the other player's knight and the host's enemies,
    // this node's knight standing (a function: remotePlayers changes in
    // place, a binding misses it)
    function inRun() {
        return game.screen === "game" && game.player !== null && !game.fallen
               && session !== null && Object.keys(session.remotePlayers).length > 0
               && game.enemies.length > 0
    }
    // Host: down to the next level, the party's danger settled on the way
    function advance() { game._hostAdvanceLevel() }
    // Host: every enemy stands still, so no blow adds to a made-up record
    function calm() {
        for (let e of game.enemies) if (e && e.halt) e.halt()
        return true
    }
    // This knight's record of the dungeon, made up: the share of its max
    // HP lost and whether it fell
    function setRecord(lost, fell) {
        game.fightRecord.damageTaken = Math.round(lost * game.player.maxHp)
        game.fightRecord.deaths = fell ? 1 : 0
        return true
    }
    // What the host would settle the next dungeon from: every knight's
    // record it holds
    function records() { return game.partyRecords() }
    // Where the host would put the next dungeon were the party to leave
    // now; the same function a level change calls
    function settled() { return game.settleDanger(game.dangerPosition, game.partyRecords()) }

    // The level this screen shows and its danger
    function danger() {
        return {
            screen: game.screen, level: game.levelIndex, depth: game.depth, type: game.levelType,
            danger: r3(game.danger), pos: r3(game.dangerPosition), next: r3(game.nextPosition),
            band: game.dangerBand(game.dangerPosition), connected: connected, nodes: nodeCount,
            standing: game.player !== null
        }
    }
    // What the dungeon on this screen looks like: the band, its light,
    // every torch, the floor, what lies on it and what drifts in the air
    function look() {
        let out = {band: game.dangerBand(game.dangerPosition), ambient: String(game.look.ambient),
                   temperature: game.look.temperature,
                   torches: game.torches.map(t => [r3(t.xWu), r3(t.yWu), String(t.flameColor)]),
                   floor: null, onFloor: [], air: [],
                   stairs: game.exitStairs ? String(game.exitStairs.glow) : null}
        for (let o of game.dungeonObjects) {
            if (!o) continue
            if (o.style === "stone") out.floor = [r3(o.crackShare), r3(o.moss)]
            else if (o.kind !== undefined) out.onFloor.push([o.kind, r3(o.xWu), r3(o.yWu)])
            else if (String(o).startsWith("Stain")) out.onFloor.push(["stain", r3(o.xWu), r3(o.yWu)])
            else if (o.moteSize !== undefined) out.air.push(r3(o.density))
        }
        return out
    }
    // The knight in the room after the first, where the floor carries the
    // look, and the camera on it - it follows only a knight that moves
    function showRoom() {
        let r = game.rooms[1]
        game.player.xWu = (r.x + r.w / 2) * game.cellSize
        game.player.yWu = (r.y + r.h / 2) * game.cellSize
        game.camera.target = null
        game.camera.target = game.player
        return true
    }

    function r3(v) { return Math.round(v * 1000) / 1000 }
}
