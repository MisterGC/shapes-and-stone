// Slit party bench - one of two game instances, a host or a joiner, that
// run_slitparty.py starts as two processes (clayliveloader --instance),
// connects over Local or Cloud signaling and drives through the inspector
// protocol (issue #125).
//
// The instance runs the real game. It logs every arrow its slits fire,
// with the session time it was due at and the session time it left on
// this screen, what each arrow did to its knight and where each went.
// The driver stands a knight in a slit's line, its back to it or its
// shield raised just before an arrow, and reads what each screen shows.

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
        recordStoreName: "ShapesAndStoneSlitPartyBench"
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
    readonly property bool synced: net ? net.sessionTimeSynced : false

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
    // The knight at full HP, its mana and dash ready, its shield down
    function fresh() {
        let p = game.player
        p.hp = p.maxHp
        p.graceLeft = 0
        p.mana = p.maxMana
        p.dashCooldown = 0
        p.lowerShield()
        return true
    }

    // The slits on this screen, by cell, with their rhythms
    function slits() {
        if (!game.slits) return []
        return game.slits.map(s => ({ cell: s.cell, rhythm: s.rhythm, offset: s.offset,
                                      beats: s.beats, dx: s.dirX, dy: s.dirY, line: s.lineWu }))
    }
    // The session clock here, ms
    function now() { return session.now() }

    // Every arrow fired, met and ended on this screen since startLog():
    // {id, at: when it was due (ms), now: when it left here (ms)}, {id,
    // result}, {id, where}
    property var fired: []
    property var met: []
    property var ended: []
    function startLog() {
        fired = []
        met = []
        ended = []
        return now()
    }
    Connections {
        target: game
        function onArrowFired(id, cell, at) {
            bench.fired.push({ id: id, at: at * 1000, now: bench.now() })
        }
        function onArrowMet(id, result) { bench.met.push({ id: id, result: result }) }
        function onArrowEnded(id, where) { bench.ended.push({ id: id, where: where }) }
    }

    function hp() { return game.player ? game.player.hp : -1 }
    function maxHp() { return game.player ? game.player.maxHp : -1 }
    function mana() { return game.player ? game.player.mana : -1 }
    // What an arrow takes from this knight here, its defence off
    function damage() {
        let p = game.player
        return Math.max(Balance.minDamage, game.arrowDamageAt(game.depth, p.maxHp) - p.def)
    }
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
    // This knight back in the start room, off every line
    function moveHome() {
        let r = game.rooms[0]
        return moveTo((r.x + r.w / 2) * game.cellSize, (r.y + r.h / 2) * game.cellSize)
    }

    // The cells of slit feature f's line
    function lineOf(f) {
        let g = game.grid, out = [], x = f.gx, y = f.gy
        while (g[y] && g[y][x] !== undefined && g[y][x] !== game.cellWall) {
            out.push(x + "," + y)
            x += f.dx
            y += f.dy
        }
        return out
    }
    // A slit whose line's third cell nothing stands on and no other
    // slit's line crosses: its cell, or ""
    function pickSlit() {
        let feats = game.features.filter(f => f.kind === "slit")
        for (let f of feats) {
            let line = lineOf(f)
            if (line.length < 5) continue
            let c = line[2]
            if (game.features.some(o => o.gx + "," + o.gy === c)) continue
            if (feats.some(o => o !== f && lineOf(o).indexOf(c) >= 0)) continue
            return f.gx + "," + f.gy
        }
        return ""
    }
    // This knight on the third cell of slit cell's line, its back to it
    property string slitCell: ""
    function standInLine(cell) {
        let f = game.features.find(o => o.kind === "slit" && o.gx + "," + o.gy === cell)
        let c = lineOf(f)[2].split(",").map(Number)
        slitCell = cell
        moveTo((c[0] + 0.5) * game.cellSize, (c[1] + 0.5) * game.cellSize)
        game.player.facingAngle = Math.atan2(f.dy, f.dx) * 180 / Math.PI
        return true
    }
    // Facing the slit, the shield raised just before its next arrow
    property bool perfect: false
    function perfectNext() {
        let f = game.features.find(o => o.kind === "slit" && o.gx + "," + o.gy === slitCell)
        game.player.facingAngle = Math.atan2(-f.dy, -f.dx) * 180 / Math.PI
        perfect = true
        return true
    }
    Connections {
        target: game.physics
        function onStepped() {
            if (!bench.perfect || !game.player) return
            let p = game.player
            let cx = p.xWu + p.widthWu / 2, cy = p.yWu - p.heightWu / 2
            for (let a of game.arrows) {
                if (a.arrowId.indexOf(bench.slitCell + "#") !== 0 || a.judged || a.back) continue
                let d = (cx - a.xWu) * a.dirX + (cy - a.yWu) * a.dirY
                if (d <= 1.3 && d > 0.5) {
                    bench.perfect = false
                    p.raiseShield()
                }
            }
        }
    }
}
