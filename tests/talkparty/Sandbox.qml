// Talk party bench - one of two game instances, a host or a joiner,
// that run_talkparty.py starts as two processes (clayliveloader
// --instance), connects over Local or Cloud signaling and drives through
// the inspector protocol (issue #176).
//
// The instance runs the real game. The driver has a knight stand by a
// miner and talk to the travellers of the deep, and reads what each
// screen shows of them: where they are, whether a miner digs, what each
// says, how each goes on and what they did.

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
        recordStoreName: "ShapesAndStoneTalkPartyBench"
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

    // The spawn holes on this screen: cell, its veins, stage, waves and
    // the strikes of its miners it counted
    function holes() {
        return game.holes.map(h => ({ cell: h.cell, veins: h.veinCells, stage: h.stage, wave: h.wave, dug: h.dug }))
    }

    // The travellers of the deep on this screen: cell, kind, special,
    // where its feet stand, how it goes on, gone, its line, whether a
    // miner digs and its strikes, its fade and its hole
    function travellers() {
        return game.deepTravellers.map(s => ({ cell: s.cell, kind: s.kind, special: s.special,
                                               x: s.footXWu, y: s.footYWu, outcome: s.outcome, gone: s.gone,
                                               saying: s.saying, digging: s.digging, digs: s.digs,
                                               fade: s.fade, hole: s.holeCell }))
    }
    // What they did on this screen: [{cell, what, t}]
    function events() { return game.deepTravellerEvents }
    function sounds() { return game.deepTravellerSounds }
    function soundCount() { return game.deepTravellerSoundCount }
    // The chords heard since the count of their sounds was n
    function chordsSince(n) {
        let k = game.deepTravellerSoundCount - n
        return k > 0 ? game.deepTravellerSounds.slice(-k).filter(x => x === "chord").length : 0
    }

    // The specials with this machine's camps, kept with its record, as if
    // it had talked to them (issue #159)
    function setSpecials(ids) {
        game.freedCamp.store.set("specials", JSON.stringify(ids))
        game.freedCamp.load()
        return game.freedCamp.joined
    }
    // Host: the party goes on to the next level, as at the exit
    function onward() { game._hostAdvanceLevel() }
    // This screen's camp: whether it is in one, the freed by its fire
    // ([kind or kind:special], sorted), the fire's rates and light, the
    // specials it shows and those kept with this machine's record
    function camp() {
        let cf = game.campfire, fc = game.freedCamp
        return { inCamp: game.levelType === "village" && cf !== null && game.player !== null,
                 sitting: fc.figures.map(f => f.kind + (f.special ? ":" + f.special : "")).sort(),
                 heal: cf ? cf.healRate : 0, mana: cf ? cf.manaRate : 0, light: cf ? cf.lightRadius : 0,
                 shown: fc.joinedShown, own: fc.joined }
    }

    // This knight talks to the traveller on cell, but the talk reaches
    // the host for another level than the host's, as one made just before
    // the party went on would: its line shows here at once, and the host
    // refuses it
    function talkStale(cell) {
        let s = game.deepTravellerAt(cell), run = s ? game._deepRuns[cell] : null
        if (!run || run.talked || s.outcome !== "") return ""
        run.talked = true
        game._deepSay(s, "leaving")
        game._deepEvent(s, "talked")
        session.reportTalk(game.levelIndex + 7, cell)
        return s.saying
    }
    function refused() { return game.talksRefused }
    // Whether this knight could talk to the traveller on cell again
    function talkableAgain(cell) {
        let s = game.deepTravellerAt(cell), run = s ? game._deepRuns[cell] : null
        return run !== null && !run.talked && s.outcome === ""
    }
    // This knight stands just below the traveller on cell, near enough to
    // talk to it, and a miner digs while it is there
    function standBy(cell) {
        let s = game.deepTravellerAt(cell), p = game.player
        if (!s) return false
        p.xWu = s.midXWu - p.widthWu / 2
        p.yWu = s.footYWu - 0.3 + p.heightWu / 2
        return true
    }
    // This knight goes back where the run started, out of every
    // traveller's reach
    property var _start: null
    function standAway() {
        let p = game.player
        if (!_start) return false
        p.xWu = _start.x
        p.yWu = _start.y
        return true
    }
    function noteStart() {
        _start = { x: game.player.xWu, y: game.player.yWu }
        return _start
    }
    // This knight talks to the traveller on cell, as E beside it does:
    // the line it says here at once ("" when it could not)
    function talk(cell) {
        if (!standBy(cell)) return ""
        let s = game.deepTravellerAt(cell)
        if (game.deepTravellerToTalk() !== s || !game.talkToDeepTraveller()) return ""
        return s.saying
    }
}
