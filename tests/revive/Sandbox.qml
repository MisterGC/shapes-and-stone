// Revive bench - one of two game instances, a host or a joiner, that
// run_revive.py starts as two processes (clayliveloader --instance),
// connects over Local or Cloud signaling and drives through the inspector
// protocol (issue #100).
//
// The instance runs the real game. The driver strikes the joiner's knight
// down, stands the host's knight beside it, hits the host's knight half
// way, and reads what each screen shows: its knight, the other knight, the
// ring around the fallen one and the fight record.

import QtQuick
import QtTest
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
        recordStoreName: "ShapesAndStoneReviveBench"
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

    // The party's numbers, from the table (null before issue #100)
    function party() { return Balance.party === undefined ? null : Balance.party }

    // In a dungeon with the other player's knight and the host's enemies
    function inRun() {
        return game.screen === "game" && game.player !== null
               && session !== null && Object.keys(session.remotePlayers).length > 0
               && game.enemies.length > 0
    }
    // Host: down to the next level
    function advance() { game._hostAdvanceLevel() }
    // Host: every enemy stands where it is, so nothing but the bench hits
    // a knight
    function halt() {
        for (let e of game.enemies) if (e && e.halt) e.halt()
        return game.enemies.length
    }
    // The knight out of reach of a stray blow while the bench sets up
    function standUp() { game.player.hp = 100000 }
    // A blow no knight survives, from the side, not dashing or blocking
    function strikeDown() {
        let p = game.player
        p.isBlocking = false
        p.graceLeft = 0
        p.takeDamage(10 * Math.max(p.hp, p.maxHp), p.xWu + 1, p.yWu)
    }
    // A blow that lands as a hurt and leaves the knight standing. It throws
    // the knight nowhere: the lift must start over from the hit, not from
    // a step out of range
    function hurt() {
        let p = game.player
        p.isBlocking = false
        p.graceLeft = 0
        p.knockback = 0
        return p.takeDamage(5, p.xWu + 1, p.yWu)
    }
    // This node's knight dx wu right of another node's knight
    function moveBeside(id, dx) {
        let rp = session.remotePlayers[id]
        if (!rp) return false
        game.player.xWu = rp.xWu + dx
        game.player.yWu = rp.yWu
        return true
    }

    // What this screen shows of the knights
    function run() {
        let p = game.player
        let others = []
        for (let id in session.remotePlayers) {
            let rp = session.remotePlayers[id]
            let v = _viewOf(rp)
            others.push({id: id, hp: rp.remoteHp, downed: v ? v.downed : null,
                         ring: _ring(rp), x: rp.xWu, y: rp.yWu})
        }
        let r = game.fightRecord
        return {
            screen: game.screen, level: game.levelIndex, type: game.levelType,
            fallen: game.fallen, partyFallen: game.partyFallen,
            knight: p ? {hp: p.hp, maxHp: p.maxHp, x: p.xWu, y: p.yWu,
                         downed: _viewOf(p) ? _viewOf(p).downed : null, ring: _ring(p),
                         lifting: p.reviveTarget === undefined ? "" : p.reviveTarget,
                         progress: p.reviveProgress === undefined ? 0 : p.reviveProgress} : null,
            others: others,
            fallenScreen: _fallenScreen() ? _find(_fallenScreen(), "fallenTitle").text : null,
            record: {lifts: r.lifts === undefined ? null : r.lifts,
                     lifted: r.lifted === undefined ? null : r.lifted}
        }
    }

    // How full the ring around a knight is drawn on this screen, 0 when
    // none is (no ring before issue #100)
    function _ring(knight) {
        let v = _viewOf(knight)
        if (!v || v.reviveProgress === undefined) return 0
        return v.downed && v.reviveProgress > 0 ? v.reviveProgress : 0
    }
    function _find(root, name) {
        if (root.objectName === name) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = _find(kids[i], name)
            if (f) return f
        }
        return null
    }
    function _fallenScreen() {
        let f = _find(game, "fallenScreen")
        return f && f.visible ? f : null
    }
    // The KnightView that draws a knight, local or remote
    function _viewOf(knight) {
        if (!knight) return null
        for (let i = 0; i < knight.data.length; i++)
            if (knight.data[i].downed !== undefined && typeof knight.data[i].swing === "function")
                return knight.data[i]
        return null
    }
}
