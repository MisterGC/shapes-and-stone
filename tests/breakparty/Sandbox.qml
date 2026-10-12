// Break party bench - one of two game instances, a host or a joiner, that
// run_breakparty.py starts as two processes (clayliveloader --instance),
// connects over Local or Cloud signaling and drives through the inspector
// protocol (issue #123).
//
// The instance runs the real game. The driver has a knight swing at one
// of the dungeon's breakables and reads what each screen shows: the
// things still standing, the gold lying on the floor and each knight's
// gold.

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
        recordStoreName: "ShapesAndStoneBreakPartyBench"
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

    // The breakables standing on this screen, by cell, with the gold the
    // table gives each (none before issue #123)
    function things() {
        if (!game.breakables) return []
        return game.breakables.map(b => ({ kind: b.kind, cell: b.cell, x: b.cxWu, y: b.cyWu,
                                           gold: game.breakableGold(b.kind, b.cell) }))
    }
    // The gold lying on this screen's floor
    function drops() {
        return game.goldDrops.filter(d => d).map(d => ({ x: d.xWu, y: d.yWu, amount: d.amount, id: d.objectId }))
    }
    function gold() { return game.player ? game.player.gold : -1 }
    function level() { return game.levelIndex }

    // This knight swings at the thing on cell, from the side a floor cell
    // lies, 1.4 wu off its centre; a charged swing when heavy
    function swingAt(cell, heavy) {
        let b = game.breakableAt(cell)
        if (!b) return false
        let p = game.player
        for (let d of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
            let gx = Math.floor(b.cxWu / game.cellSize) + d[0], gy = Math.floor(b.cyWu / game.cellSize) + d[1]
            if (!game.grid[gy] || game.grid[gy][gx] === game.cellWall) continue
            if (game.breakables.some(o => o !== b && Math.floor(o.cxWu / game.cellSize) === gx
                                     && Math.floor(o.cyWu / game.cellSize) === gy)) continue
            let x = b.cxWu + d[0] * 1.4, y = b.cyWu + d[1] * 1.4
            p.xWu = x - p.widthWu / 2
            p.yWu = y + p.heightWu / 2
            p.facingAngle = Math.atan2(b.cyWu - y, b.cxWu - x) * 180 / Math.PI
            p.attackCooldown = 0
            p.isAttacking = false
            return heavy ? p.heavyAttack() : (p.attack(), true)
        }
        return false
    }
    // This knight's centre on (x, y)
    function moveTo(x, y) {
        let p = game.player
        p.xWu = x - p.widthWu / 2
        p.yWu = y + p.heightWu / 2
        return true
    }
}
