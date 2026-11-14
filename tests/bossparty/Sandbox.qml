// Boss party bench - one of two game instances, a host or a joiner, that
// run_bossparty.py starts as two processes (clayliveloader --instance),
// connects over Local or Cloud signaling and drives through the inspector
// protocol (issue #274).
//
// The instance runs the real game. The host takes the session down to the
// dungeon at depth 2, whose last room is the Hollow Warden's; the driver
// stands each knight outside or inside that room and reads what each
// screen shows of the Warden's fight.

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
        recordStoreName: "ShapesAndStoneBossPartyBench"
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
    // Host: the session goes down to the dungeon at depth d, as the stairs
    // take it there
    function goToDepth(d) {
        let index = game.levelIndexOf(d, "dungeon")
        let dd = game._dangerFor(index)
        session.announceLevel(index, dd.pos, dd.next, dd.knights, null)
        game._applyLevelChange(index, dd)
        return index
    }
    function level() { return game.levelIndex }
    // Host: every enemy but the Warden stands where it is
    function halt() {
        let n = 0
        for (let e of game.enemies) if (e && e.halt && !e.destroyed && !e.boss) { e.halt(); n++ }
        return n
    }
    // The knight out of reach of a stray blow
    function standUp() { game.player.hp = 100000; game.player.maxHp = 100000 }

    function alive(e) { return !!e && e.destroyed === false }
    function warden() { return game.enemies.find(e => alive(e) && e.boss) || null }

    // What this screen shows of the Warden's fight
    function boss() {
        let f = game.bossFight, w = warden()
        let banner = f.children.find(x => x.objectName === "bossBanner")
        let victory = f.children.find(x => x.objectName === "victoryBanner")
        let bar = f.children.find(x => x.objectName === "bossBar")
        let r = game.bossRoom
        let cs = game.cellSize
        let adds = game.enemies.filter(e => alive(e) && !e.boss && r
                                       && f.inside(e.xWu + e.widthWu / 2, e.yWu - e.heightWu / 2, 0))
        return {
            level: game.levelIndex, stage: f.stage, phase: f.phase, room: r,
            gates: f.gates.map(g => ({ cell: g.cell, exit: g.exit, shut: g.shut })),
            warden: w ? { id: w.objectId, hp: w.hp, maxHp: w.maxHp, phase: w.phase, dormant: w.dormant,
                          remote: w.remote } : null,
            adds: adds.map(e => e.objectId).sort(),
            zones: f.zones.map(z => z.id).sort(),
            banner: banner ? banner.opacity : 0, victory: victory ? victory.opacity : 0,
            bar: bar ? bar.visible : false, lit: game.bossLit,
            hp: game.player ? game.player.hp : 0, maxHp: game.player ? game.player.maxHp : 0,
            mana: game.player ? game.player.mana : 0, maxMana: game.player ? game.player.maxMana : 0
        }
    }
    // This knight in the room, k wu right of its middle
    function enterRoom(k) {
        let r = game.bossRoom, p = game.player
        if (!r || !p) return false
        let cs = game.cellSize
        let x = (r.x + r.w / 2) * cs + k, y = (r.y + 1.2) * cs
        p.xWu = x - p.widthWu / 2
        p.yWu = y + p.heightWu / 2
        return game.bossFight.inside(x, y)
    }
    // This knight in the corridor outside the room's first way in
    function leaveRoom() {
        let g = game.bossFight.gates.find(x => !x.exit), p = game.player
        if (!g || !p) return false
        let gx = parseInt(g.cell.split(",")[0]), gy = parseInt(g.cell.split(",")[1])
        p.xWu = (gx + 0.5) * game.cellSize - p.widthWu / 2
        p.yWu = (gy + 0.5) * game.cellSize + p.heightWu / 2
        return true
    }
    // This knight a little hurt and short of mana, so the victory's heal shows
    function hurt() {
        game.player.maxHp = Balance.knight.hp
        game.player.hp = Math.round(Balance.knight.hp / 2)
        game.player.mana = 0
        return game.player.hp
    }
    // Host: the Warden's HP just above share of its max, then a blow
    function strikeWarden(share) {
        let w = warden(), p = game.player
        if (!w) return false
        w.halt()
        w.halted = false
        w.hp = Math.floor(w.maxHp * share) + 5
        w.takeDamage(1000, p.xWu, p.yWu, false)
        return w.phase
    }
    // Host: the Warden falls to this knight's blow
    function killWarden() {
        let w = warden(), p = game.player
        if (!w) return false
        w.takeDamage(1000000, p.xWu, p.yWu, false)
        return true
    }
    // Host: the adds stand
    function haltAdds() {
        for (let e of game.enemies) if (alive(e) && !e.boss) e.halt()
        return true
    }
}
