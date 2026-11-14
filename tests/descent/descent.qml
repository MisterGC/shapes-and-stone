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
// count.
// In a session, a host and a joiner joined over LAN in one process: the
// count starts once both knights are in the dungeon, both screens show the
// same name, hold the same count and let go at the same moment of the
// session clock. A knight whose intro never reports holds the host no
// longer than Balance.intro.waitMax, and the host is told it waits.
// Prints one PASS or FAIL line per check and exits with the number of
// failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/descent/descent.qml

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Network
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
    // A tick of the intro's clock and of this script, with room for an
    // offscreen frame that comes late
    readonly property real slackMs: 80

    function check(ok, what) {
        console.log("[Descent]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function hold(item, key) {
        item.forceActiveFocus()
        keys.keyPress(key, Qt.NoModifier, -1)
    }

    Component.onCompleted: {
        gameComp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComp.status !== Component.Ready) {
            console.log("[Descent] FAIL", gameComp.errorString())
            Qt.exit(1)
            return
        }
        solo = makeGame({})
        script.start()
    }
    function makeGame(props) {
        let g = gameComp.createObject(bench.contentItem, Object.assign({
            width: 1000, height: 500, muted: true, logSounds: true, descentIntro: true,
            recordStoreName: "ShapesAndStoneDescentBench"}, props))
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

    // What each game's intro did: when it began holding, each beat and
    // when it let go, in wall-clock ms and on its session clock, and where
    // the knight and the enemies stood as it let go
    property var seen: ({})
    function watch(g) {
        let id = String(g)
        seen[id] = { beats: [], heldAt: -1, freedAt: -1, freedSession: -1, freedPos: null }
        g.introHeldChanged.connect(() => {
            let s = seen[id]
            if (g.introHeld) {
                s.heldAt = Date.now()
                s.beats = []
                s.freedAt = -1
                return
            }
            s.freedAt = Date.now()
            s.freedSession = session(g).now()
            s.freedPos = where(g)
        })
        g.introBeatChanged.connect(() => {
            if (g.introBeat > 0) seen[id].beats.push({ beat: g.introBeat, at: Date.now(), session: session(g).now() })
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
    // The beats one after the other, beatMs apart, the first leadMs after
    // the count began: alone as the hold began, in a session at its moment
    // of the session clock, after the wait for the party
    function checkCount(g, who) {
        let s = seenOf(g)
        let order = s.beats.map(b => b.beat).join(",")
        check(order === "3,2,1", who + " counts 3, 2, 1 (" + order + ")")
        if (s.beats.length !== 3) return
        let lead = Math.round(session(g).connected ? s.beats[0].session - g.introStartsAt : s.beats[0].at - s.heldAt)
        let gaps = [s.beats[1].at - s.beats[0].at, s.beats[2].at - s.beats[1].at, s.freedAt - s.beats[2].at]
        check(Math.abs(lead - leadMs) <= slackMs, who + ": the depth and the name stand alone "
              + lead + " ms before the 3 (" + leadMs + " ms)")
        check(gaps.every(d => Math.abs(d - beatMs) <= slackMs), who + ": each beat lasts "
              + gaps.join(", ") + " ms (" + beatMs + " ms)")
    }

    property var before: null
    property real heldFrom: 0
    property real clockAtPause: 0
    property real pausedMs: 0
    property var hpBefore: ({})

    property var soloSteps: [
        [() => solo.screen === "title", () => {
            check(!solo.introOn, "the title has no intro")
            solo.screen = "game"
            solo.forceActiveFocus()
        }],
        [() => solo.player && solo.enemies.length > 0, () => {
            let s = seenOf(solo)
            check(solo.introOn && solo.introHeld && s.heldAt > 0,
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
            let held = s.freedAt - s.heldAt
            check(Math.abs(held - solo.introSeconds * 1000) <= slackMs, "the intro holds "
                  + held + " ms (" + solo.introSeconds * 1000 + " ms)")
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
        }],
        [300, () => {
            solo.openMenu()
            clockAtPause = solo.introClock
            heldFrom = Date.now()
        }],
        [600, () => {
            check(solo.introHeld && solo.introClock === clockAtPause,
                  "under the solo pause the count stands (" + clockAtPause + " -> " + solo.introClock + " ms)")
            solo.closeMenu()
            pausedMs = Date.now() - heldFrom
        }],
        [() => !solo.introHeld, () => {
            let s = seenOf(solo)
            let held = s.freedAt - s.heldAt - pausedMs
            check(Math.abs(held - solo.introSeconds * 1000) <= 2 * slackMs, "it holds "
                  + held + " ms besides the pause (" + solo.introSeconds * 1000 + " ms)")
            check(seenOf(solo).beats.map(b => b.beat).join(",") === "3,2,1",
                  "after the camp it counts 3, 2, 1 (" + seenOf(solo).beats.map(b => b.beat).join(",") + ")")
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
        [() => seenOf(host).freedAt > 0 && seenOf(joiner).freedAt > 0, () => {
            check(host.introStartsAt > 0 && host.introStartsAt === joiner.introStartsAt,
                  "both count from the same moment of the session clock (" + host.introStartsAt
                  + " / " + joiner.introStartsAt + ")")
            check(host.introStartsAt >= joiner.introArrivedAt && host.introStartsAt >= host.introArrivedAt,
                  "the count starts once both knights have arrived (host " + host.introArrivedAt
                  + ", joiner " + joiner.introArrivedAt + ", count " + host.introStartsAt + ")")
            let hf = seenOf(host).freedSession, jf = seenOf(joiner).freedSession
            let end = host.introStartsAt + host.introSeconds * 1000
            check(Math.abs(hf - jf) <= slackMs && hf >= end && jf >= end,
                  "both let go at the same moment: host " + hf.toFixed(0) + ", joiner " + jf.toFixed(0)
                  + " on the session clock, the count's end " + end.toFixed(0))
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
            let waited = host.introStartsAt - Balance.intro.lag * 1000 - host.introArrivedAt
            check(Math.abs(waited - Balance.intro.waitMax * 1000) <= 2 * slackMs,
                  "it holds no longer than " + Balance.intro.waitMax + " s for it (" + waited.toFixed(0) + " ms)")
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
