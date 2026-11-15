// Descent bench - entering a dungeon opens with its depth, its name and a
// 3-2-1 count while the world is held (issue #316).
//
// Alone: the first dungeon shows "Depth 0" and its name, counts 3, 2, 1
// (Balance.intro) and lets go after introSeconds. While it holds, the world
// is stopped, no enemy and not the knight moves, with D held; the knight's
// swing, charged swing, shield, dash and whirlwind are refused, and no blow
// lands on the knight, from an enemy or a trap, nor on an enemy. Each beat
// and Go play the count's cue (sfx/descent_count), Go an octave up. Once
// it lets go, Go shows and D moves the knight. The camp has no intro; the
// dungeon after it has its own, "Depth 1", and the solo pause holds its
// count, as it holds through a stall of the frames: the clock moves at
// most Balance.intro.maxStep a frame. It passes the record of depth 0 the
// bench puts into its store: the record's banner waits while the intro
// holds and goes up only after it lets go.
// Every length is timed on the intro's own clock, never the wall clock,
// which a slow machine stretches: each beat and the release land at their
// time, late by no more than the largest step that clock took.
// In a session, a host and a joiner joined over LAN in one process: the
// count starts once both knights are in the dungeon, both screens show the
// same name, hold the same count and let go at the same moment of the
// session clock. A knight whose intro never reports holds the host no
// longer than Balance.intro.waitMax, and the host is told it waits.
// With two specials or more in the game the knight takes the first at once
// (the specials bench tries the choice). Prints one PASS or FAIL line per
// check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/descent/descent.qml

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Network
import Clayground.Storage
import "../../src"

Window {
    id: bench
    width: 1000
    height: 500
    visible: true
    color: "#1a1a2e"

    property var solo: null
    property var host: null
    property var joiner: null
    property var hostNet: null
    property var joinNet: null
    property var gameComp: null
    property int failures: 0

    readonly property int seed: 316316
    readonly property real beatMs: Balance.intro.beat * 1000
    readonly property real leadMs: Balance.intro.lead * 1000
    readonly property real holdMs: (Balance.intro.lead + Balance.intro.beats * Balance.intro.beat) * 1000
    // How long the bench stalls the frames in the dungeon after the camp
    readonly property real stallMs: 300

    function check(ok, what) {
        console.log("[Descent]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function hold(item, key) {
        item.forceActiveFocus()
        keys.keyPress(key, Qt.NoModifier, -1)
    }

    // The bench's record, depth 0 on every run, so the dungeon at depth 1
    // passes it
    KeyValueStore { id: store; name: "ShapesAndStoneDescentBench" }
    // Every record banner the solo game raised: its depth and whether the
    // intro held then
    property var banners: []

    Component.onCompleted: {
        store.remove("bestDepth")
        store.set("record", JSON.stringify({depth: 0, names: ["Ana"], date: "2026-11-01"}))
        gameComp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComp.status !== Component.Ready) {
            console.log("[Descent] FAIL", gameComp.errorString())
            Qt.exit(1)
            return
        }
        solo = makeGame({})
        solo.recordBanner.connect(d => banners.push({ depth: d, held: solo.introHeld }))
        script.start()
    }
    function makeGame(props) {
        let g = gameComp.createObject(bench.contentItem, Object.assign({
            width: 1000, height: 500, muted: true, logSounds: true, descentIntro: true,
            recordStoreName: "ShapesAndStoneDescentBench"}, props))
        // The intro, not the choice of a special, is this bench's: with two
        // specials or more in the game (issue #318) the knight takes the
        // first card as soon as the choice opens, the whirlwind
        g.specialChoosingChanged.connect(() => Qt.callLater(() => {
            if (g.specialChoosing) g.chooseSpecial(g.specialOffer[0])
        }))
        watch(g)
        return g
    }

    function find(root, name) {
        if (root.objectName === name) return root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) {
            let f = find(kids[i], name)
            if (f) return f
        }
        return null
    }
    function shown(game, name) {
        let f = find(game, name)
        return f && f.visible ? f : null
    }
    function session(game) {
        for (let i = 0; i < game.data.length; i++)
            if (typeof game.data[i].sendImpact === "function") return game.data[i]
        return null
    }
    function network(game) {
        let s = session(game)
        if (!s) return null
        for (let i = 0; i < s.data.length; i++)
            if (typeof s.data[i].join === "function" && s.data[i].signalingMode !== undefined)
                return s.data[i]
        return null
    }

    // What each game's intro did, timed on its own clock (introClock: alone
    // the intro's, in a session the session clock), which a stall of the
    // frames moves by at most Balance.intro.maxStep alone: each beat and
    // when it let go, the largest step the clock took in the count
    // (maxStep) and while it waited for the party before it (waitStep), and
    // where the knight and the enemies stood as it let go. The wall clock
    // only for the record (heldAt, freedAt): a slow machine stretches it
    property var seen: ({})
    function watch(g) {
        let id = String(g)
        seen[id] = { beats: [], freed: false, freedClock: -1, freedPos: null, lastClock: 0, maxStep: 0,
                     waitStep: 0, heldAt: -1, freedAt: -1 }
        // A step of the clock ending in the count, or before it began
        let took = (s, clock) => {
            let step = clock - s.lastClock
            if (g.introStartsAt >= 0 && clock > g.introStartsAt) s.maxStep = Math.max(s.maxStep, step)
            else s.waitStep = Math.max(s.waitStep, step)
            s.lastClock = clock
        }
        g.introHeldChanged.connect(() => {
            let s = seen[id]
            if (g.introHeld) {
                Object.assign(s, { beats: [], freed: false, lastClock: g.introClock, maxStep: 0,
                                   waitStep: 0, heldAt: Date.now(), freedAt: -1 })
                return
            }
            took(s, g.introClock)
            Object.assign(s, { freed: true, freedClock: g.introClock, freedPos: where(g), freedAt: Date.now() })
        })
        g.introClockChanged.connect(() => {
            let s = seen[id]
            if (g.introHeld) took(s, g.introClock)
        })
        g.introBeatChanged.connect(() => {
            if (g.introBeat > 0) seen[id].beats.push({ beat: g.introBeat, clock: g.introClock })
        })
    }
    function seenOf(g) { return seen[String(g)] }
    function where(g) {
        return { knight: g.player ? Qt.point(g.player.xWu, g.player.yWu) : null,
                 enemies: g.enemies.filter(e => e && !e.destroyed).map(e => Qt.point(e.xWu, e.yWu)) }
    }
    function movedSince(a, b) {
        let sum = Math.abs(a.knight.x - b.knight.x) + Math.abs(a.knight.y - b.knight.y)
        for (let i = 0; i < Math.min(a.enemies.length, b.enemies.length); i++)
            sum += Math.abs(a.enemies[i].x - b.enemies[i].x) + Math.abs(a.enemies[i].y - b.enemies[i].y)
        return sum
    }
    function countCues(g) {
        return g.soundLog.filter(r => r.cue === "sfx/descent_count").map(r => r.what + (r.pitch ? "@" + r.pitch : ""))
    }
    // On the intro's clock each beat and the release land at their time
    // after the count's start (introStartsAt) - the 3 leadMs after it, the
    // others beatMs apart, the release holdMs after it - never early and
    // no later than the largest step the clock took, as the clock moves a
    // step a tick
    function late(at, due, step) { return at - due >= 0 && at - due <= step }
    function checkCount(g, who) {
        let s = seenOf(g)
        let order = s.beats.map(b => b.beat).join(",")
        check(order === "3,2,1", who + " counts 3, 2, 1 (" + order + ")")
        if (s.beats.length !== 3) return
        let from = g.introStartsAt, step = s.maxStep
        let r = v => Math.round(v * 10) / 10
        let at = s.beats.map(b => r(b.clock - from)).concat([r(s.freedClock - from)])
        let due = [0, 1, 2, 3].map(i => leadMs + i * beatMs)
        check(at.every((a, i) => late(a, due[i], step)), who + ": the 3, the 2, the 1 and the release land at "
              + at.join(", ") + " ms of its clock (" + due.join(", ") + ", each within a step of "
              + r(step) + " ms)")
    }

    property var before: null
    property real clockAtPause: 0
    property var hpBefore: ({})

    property var soloSteps: [
        [() => solo.screen === "title", () => {
            check(!solo.introOn, "the title has no intro")
            solo.screen = "game"
            solo.forceActiveFocus()
        }],
        [() => solo.player && solo.enemies.length > 0, () => {
            let s = seenOf(solo)
            check(solo.introOn && solo.introHeld && s.heldAt > 0 && !s.freed,
                  "entering the first dungeon opens its intro")
            check(!solo.physics.running, "the intro holds the world: the physics stands")
            let depth = shown(solo, "introDepth"), name = shown(solo, "introName")
            let want = solo.dungeonNameOf(solo.levelSeedNow(), solo.dangerBand(solo.dangerPosition))
            check(shown(solo, "descentIntro") !== null && depth && depth.text === "Depth 0",
                  "it shows the depth (" + (depth ? depth.text : "none") + ")")
            check(name && name.text === want && /^The \w+ \w+$/.test(want),
                  "it shows the dungeon's name (" + (name ? name.text : "none") + ")")
            check(shown(solo, "introCount") === null && solo.introBeat === 0,
                  "the count waits through the lead")
            // Every action the knight has, and a blow on either side
            let p = solo.player
            let mana = p.mana
            p.momentum = Balance.momentum.max
            p.mana = p.maxMana
            mana = p.mana
            p.attack()
            check(!p.isAttacking, "a swing is refused")
            check(p.heavyAttack() === false && !p.isAttacking, "a charged swing is refused")
            check(p.pressSwing(null) === false, "the strike button takes nothing")
            p.raiseShield()
            check(!p.isBlocking, "the shield stays down")
            p.dash()
            check(!p.isDashing, "a dash is refused")
            check(p.unleash() === false && !p.isWhirling && p.momentum === Balance.momentum.max,
                  "the whirlwind is refused and keeps its momentum")
            check(p.mana === mana, "no mana is spent (" + mana + " -> " + p.mana + ")")
            let hp = p.hp
            let e = solo.enemies.filter(x => x && !x.destroyed)[0]
            check(p.takeDamage(10, p.xWu + 1, p.yWu) === "ignored" && p.takeTrapDamage(10) === "ignored"
                  && p.hp === hp, "no blow lands on the knight, from an enemy or a trap")
            let ehp = e.hp
            check(e.takeDamage(10, p.xWu, p.yWu, false, false) === 0 && e.hp === ehp,
                  "no blow lands on an enemy")
            before = where(solo)
            hold(solo, Qt.Key_D)
        }],
        [() => !solo.introHeld, () => {
            let s = seenOf(solo)
            let held = s.freedClock - solo.introStartsAt
            check(solo.introSeconds * 1000 === holdMs && late(held, holdMs, s.maxStep), "the intro holds "
                  + held + " ms of its clock (" + holdMs + " ms, within a step of " + s.maxStep + " ms; "
                  + (s.freedAt - s.heldAt) + " ms on the wall clock)")
            checkCount(solo, "alone it")
            check(movedSince(before, s.freedPos) < 1e-6, "through the hold neither the knight, with D held,"
                  + " nor any of " + before.enemies.length + " enemies moved ("
                  + movedSince(before, s.freedPos).toFixed(4) + " wu)")
            let cues = countCues(solo).join(", ")
            check(cues === "beat3, beat2, beat1, go@" + Balance.intro.goPitch,
                  "each beat and Go play the count's cue, Go " + Balance.intro.goPitch + " semitones up (" + cues + ")")
            check(solo.physics.running, "it lets go of the world")
            check(shown(solo, "introGo") !== null && shown(solo, "introCount") === null, "Go shows")
            before = where(solo)
        }],
        [300, () => {
            check(movedSince(before, where(solo)) > 0.3, "then D moves the knight ("
                  + movedSince(before, where(solo)).toFixed(2) + " wu in 300 ms)")
            keys.keyRelease(Qt.Key_D, Qt.NoModifier, -1)
            solo.clearSoundLog()
            solo._enterLevel(solo.levelIndex + 1)
        }],
        [() => solo.levelType === "village" && solo.player, () => {
            check(!solo.introOn && !solo.introHeld && solo.physics.running,
                  "the camp has no intro")
        }],
        [300, () => {
            check(shown(solo, "descentIntro") === null && countCues(solo).length === 0,
                  "nothing of it shows or sounds in the camp")
            solo._enterLevel(solo.levelIndex + 1)
        }],
        [() => solo.levelType === "dungeon" && solo.player, () => {
            let depth = shown(solo, "introDepth")
            check(solo.introHeld && depth && depth.text === "Depth 1",
                  "the dungeon after the camp has its own intro (" + (depth ? depth.text : "none") + ")")
            check(solo.recordPassed && solo._recordWaits && banners.length === 0,
                  "it passes the record of depth 0, and the record's banner waits while the intro holds ("
                  + banners.length + " raised)")
            // A slow machine's frame: the count must not skip for it
            let until = Date.now() + stallMs
            while (Date.now() < until) {}
        }],
        [300, () => {
            solo.openMenu()
            clockAtPause = solo.introClock
        }],
        [600, () => {
            check(solo.introHeld && solo.introClock === clockAtPause,
                  "under the solo pause the count stands (" + clockAtPause + " -> " + solo.introClock + " ms)")
            solo.closeMenu()
        }],
        [() => !solo.introHeld, () => {
            let s = seenOf(solo)
            let held = s.freedClock - solo.introStartsAt
            let maxStep = Balance.intro.maxStep * 1000
            check(s.maxStep === maxStep, "a stall of " + stallMs + " ms moves the count's clock by "
                  + s.maxStep + " ms at most (" + maxStep + " ms)")
            check(late(held, holdMs, s.maxStep), "with the stall and the pause in it the intro holds " + held
                  + " ms of its clock (" + holdMs + " ms; " + (s.freedAt - s.heldAt) + " ms on the wall clock)")
            checkCount(solo, "after the camp it")
            // None went up while it held (checked as it began), and this
            // one went up with the intro no longer held
            let b = banners[0]
            check(banners.length === 1 && b.depth === 1 && !b.held && !solo._recordWaits,
                  "the record's banner goes up once, after the intro lets go ("
                  + (b ? "depth " + b.depth + ", intro held " + b.held : "none") + ")")
            solo.destroy()
            solo = null
            startSession()
        }]
    ]

    function startSession() {
        host = makeGame({width: 500})
        joiner = makeGame({x: 500, width: 500})
        hostNet = network(host)
        joinNet = network(joiner)
        if (!hostNet || !joinNet) {
            console.log("[Descent] FAIL no Network in the game's session")
            Qt.exit(1)
            return
        }
        hostNet.signalingMode = Network.SignalingMode.Local
    }
    function bothIn() {
        return host && joiner && host.player && joiner.player
               && host.screen === "game" && joiner.screen === "game"
               && host.levelIndex === joiner.levelIndex && host.levelType === joiner.levelType
    }

    property var sessionSteps: [
        [() => hostNet && !hostNet.connected && !joinNet.connected, () => hostNet.host()],
        [() => hostNet.networkId !== "", () => joinNet.join(hostNet.networkId)],
        [() => hostNet.connected && joinNet.connected && hostNet.nodeCount >= 2, () => {
            host.masterSeed = seed
            host._startMultiplayerGame()
        }],
        [() => bothIn() && host.introOn && joiner.introOn, () => {
            check(host.introHeld && joiner.introHeld && !host.physics.running && !joiner.physics.running,
                  "in a session both screens hold the first dungeon")
            let a = shown(host, "introName"), b = shown(joiner, "introName")
            check(a && b && a.text === b.text, "both show the same name (" + (a ? a.text : "none")
                  + " / " + (b ? b.text : "none") + ")")
            let j = joiner.player
            check(j.takeDamage(10, j.xWu + 1, j.yWu) === "ignored", "no blow lands on the joiner's knight")
        }],
        [() => seenOf(host).freed && seenOf(joiner).freed, () => {
            check(host.introStartsAt > 0 && host.introStartsAt === joiner.introStartsAt,
                  "both count from the same moment of the session clock (" + host.introStartsAt
                  + " / " + joiner.introStartsAt + ")")
            check(host.introStartsAt >= joiner.introArrivedAt && host.introStartsAt >= host.introArrivedAt,
                  "the count starts once both knights have arrived (host " + host.introArrivedAt
                  + ", joiner " + joiner.introArrivedAt + ", count " + host.introStartsAt + ")")
            let hs = seenOf(host), js = seenOf(joiner)
            let end = host.introStartsAt + holdMs
            check(late(hs.freedClock, end, hs.maxStep) && late(js.freedClock, end, js.maxStep),
                  "both let go at the count's end " + end.toFixed(0) + " on the session clock, each on its"
                  + " next tick: host " + hs.freedClock.toFixed(0) + ", joiner " + js.freedClock.toFixed(0)
                  + " (steps of " + hs.maxStep.toFixed(0) + " and " + js.maxStep.toFixed(0) + " ms)")
            checkCount(host, "the host")
            checkCount(joiner, "the joiner")
            check(countCues(host).length === 4 && countCues(joiner).length === 4,
                  "each screen plays the count's cue four times (" + countCues(host).join(", ")
                  + " / " + countCues(joiner).join(", ") + ")")
            // A knight whose intro never reports: the joiner shows none
            joiner.descentIntro = false
            host._hostAdvanceLevel()
        }],
        [() => bothIn() && host.levelType === "village", () => {
            check(!host.introOn && !joiner.introOn, "the party's camp has no intro")
            host._hostAdvanceLevel()
        }],
        [() => bothIn() && host.levelType === "dungeon" && host.introOn, () => {
            check(host.introWaiting, "the host waits for a knight not arrived")
        }],
        [1500, () => {
            check(host.introWaiting && shown(host, "introWait") !== null && !host.physics.running,
                  "after " + Balance.intro.waitNote + " s it says it waits for the party, the world held")
        }],
        [() => !host.introWaiting, () => {
            // The host gives up on the tick its clock passes waitMax; the
            // count's start is read just after that tick's clock
            let waited = host.introStartsAt - Balance.intro.lag * 1000 - host.introArrivedAt
            check(late(waited, Balance.intro.waitMax * 1000, seenOf(host).waitStep + 1),
                  "it holds no longer than " + Balance.intro.waitMax + " s for it (" + waited.toFixed(0)
                  + " ms, within a step of " + seenOf(host).waitStep.toFixed(0) + " ms)")
        }],
        [() => !host.introHeld, () => {
            check(host.physics.running, "then counts and lets go")
            console.log("[Descent] done,", failures, "failed")
        }],
        [300, () => { host.destroy(); joiner.destroy() }],
        [300, () => Qt.exit(failures)]
    ]

    property var steps: soloSteps.concat(sessionSteps)

    Timer {
        id: script
        property int i: 0
        property real waitedMs: 0
        interval: 20
        repeat: true
        onTriggered: {
            let step = bench.steps[i]
            waitedMs += interval
            let ready = typeof step[0] === "number" ? waitedMs >= step[0] : step[0]()
            if (!ready) {
                if (waitedMs > 20000) {
                    console.log("[Descent] FAIL step", i, "timed out")
                    Qt.exit(failures + 100)
                    stop()
                }
                return
            }
            waitedMs = 0
            // Advance first: a key click spins the event loop, and this
            // timer must not run the same step again inside it
            i++
            if (i >= bench.steps.length) stop()
            step[1]()
        }
    }
}
