// Go-again bench - one of two game instances, a host or a joiner, that
// run_goagain.py starts as two processes (clayliveloader --instance),
// connects over Local or Cloud signaling and drives through the inspector
// protocol (issue #99).
//
// The instance runs the real game. The driver lets the party fall, presses
// Enter on the joiner's fallen screen and then on the host's, and reads
// what each screen shows: its run, its knights, its enemies and the shots
// flying on it.

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
        recordStoreName: "ShapesAndStoneGoAgainBench"
    }

    // ---- the game's Session and its Network, found by what they offer ----
    readonly property var session: {
        for (let i = 0; i < game.data.length; i++)
            if (typeof game.data[i].sendImpact === "function") return game.data[i]
        return null
    }
    readonly property var net: session ? session.network : null

    // Sends a key the way a keyboard does, to whatever has the focus
    TestEvent { id: keys }

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
    // Host: down to the level after the next one
    function advance() { game._hostAdvanceLevel() }
    // The knight out of the enemies' reach while the bench sets things up
    function standUp() { game.player.hp = 100000 }
    // Gold, a potion, a draught and a smith's level to carry, so a new run
    // has something to drop
    function enrich() {
        game.player.gold = 25
        game.player.potions = 1
        game.player.draughts = 1
        game.player.swordLevel = 1
    }
    // A blow no knight survives, from the side, not dashing or blocking
    function strikeDown() {
        let p = game.player
        p.isBlocking = false
        p.graceLeft = 0
        p.takeDamage(10 * Math.max(p.hp, p.maxHp), p.xWu + 1, p.yWu)
    }

    // What this screen shows of the run
    function run() {
        let p = game.player
        let others = []
        for (let id in session.remotePlayers) {
            let rp = session.remotePlayers[id]
            others.push({id: id, hp: rp.remoteHp, downed: _viewOf(rp) ? _viewOf(rp).downed : null,
                         color: String(rp.playerColor)})
        }
        return {
            screen: game.screen, seed: game.masterSeed, level: game.levelIndex,
            depth: game.depth, type: game.levelType,
            fallen: game.fallen, partyFallen: game.partyFallen,
            connected: connected, nodes: nodeCount,
            knight: p ? {hp: p.hp, maxHp: p.maxHp, mana: p.mana, maxMana: p.maxMana, gold: p.gold,
                         potions: p.potions, draughts: p.draughts,
                         levels: p.swordLevel + p.shieldLevel + p.harnessLevel + p.bladeLevel,
                         downed: _viewOf(p) ? _viewOf(p).downed : null} : null,
            others: others,
            fallenScreen: _fallenScreen() ? {title: _find(_fallenScreen(), "fallenTitle").text,
                                             hint: _find(_fallenScreen(), "fallenHint").text} : null,
            goldDrops: game.goldDrops.length
        }
    }
    // Every enemy this screen holds, as {id: [type, tier, x, y, destroyed,
    // halted, remote]}
    function enemies() {
        let out = {}
        for (let e of game.enemies) {
            if (!e) continue
            out[e.objectId] = [e.enemyType, e.tier, r3(e.xWu), r3(e.yWu), e.destroyed === true,
                               e.halted === true, e.remote === true]
        }
        return out
    }
    // Every shot flying on this screen, by its id: also one the game no
    // longer tracks, so a shot left over from a run shows
    function shots() {
        let out = []
        let kids = game.room ? game.room.children : []
        for (let i = 0; i < kids.length; i++) {
            let k = kids[i]
            if (k && k.objectName === "projectile" && !k.destroyed) out.push(k.shotId)
        }
        return out
    }
    // Host: a shot from beside its knight; it stands where it was fired
    // until the run is over or its lifetime is
    function shoot() {
        let p = game.player
        game.spawnProjectile(p.xWu + 2.5, p.yWu, 1, 0, 0)
        let id = "shot" + game._shotCount
        hold(id)
        return id
    }
    // The shot stands where it is on this screen and meets nothing - no
    // wall of the next dungeon, no knight - nor bursts when its lifetime is
    // over: only the game can take it away; false without it
    function hold(id) {
        let s = game._shotById[id]
        if (!s) return false
        s.speed = 0
        s.collidesWith = 0
        s.sensorCollidesWith = 0
        for (let i = 0; i < s.data.length; i++)
            if (s.data[i].interval !== undefined && s.data[i].running !== undefined)
                s.data[i].running = false
        return true
    }
    // Enter or Esc on this screen's fallen screen
    function press(key) {
        let fs = _fallenScreen()
        if (!fs) return false
        fs.forceActiveFocus()
        keys.keyClick(key, Qt.NoModifier, -1)
        return true
    }
    function enter() { return press(Qt.Key_Return) }

    function r3(v) { return Math.round(v * 1000) / 1000 }
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
