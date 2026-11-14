// Specials bench - the knight picks one of three specials at the start of
// a dungeon (issue #317).
//
// Alone, with the whirlwind the one special in the game: the first
// dungeon shows no choice, the knight has the whirlwind, the descent
// intro counts at once, the HUD shows "Whirlwind 20" and the controls hint
// "Q whirlwind", and Q whirls. Then the bench offers the specials not in
// the game yet too (Game.specialsAll) and the knight buys the balanced
// blade I at the camp. The next dungeon's intro shows the choice with the
// depth and the name: three cards with a name, a line and the mana each
// costs with the blade (Balance.shop.bladeShare), the whirlwind's card
// under the keys; it waits for the pick, no count and no "Waiting for the
// party", the world held. The arrows and the move keys move along the
// cards, one card a press also with the moves bound to the arrows, and 2
// takes the stun: the choice goes, the count starts and lets go.
// The HUD shows the stun and its mana, the hint "Q stun"; neither Q nor
// the pad's R2 whirls, nothing is spent, and the smith says what the
// blade gives the stun. In the dungeon after the camp the choice opens on
// the stun; the synthetic pad's stick moves along the cards and A takes
// the whirlwind, which Q lets loose as today for the blade's mana. In the
// next one a click takes the bolt, which holds through its dungeon and
// the camp after it.
// In a session, a host and a joiner joined over LAN in one process: each
// picks its own. The host picks first and waits, told so, past
// Balance.intro.waitMax for the joiner still choosing; the count starts on
// both once the joiner has picked, at the same moment of the session
// clock. Prints one PASS or FAIL line per check and exits with the number
// of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/specials/specials.qml

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.GameController
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

    readonly property int seed: 317317

    function check(ok, what) {
        console.log("[Specials]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function key(game, k) {
        game.forceActiveFocus()
        keys.keyClick(k, Qt.NoModifier, -1)
    }

    // The pad: its state by input name, as the inspector's input action
    // sends it (ClayInputCtrl)
    QtObject {
        id: agent
        property bool active: false
        property var gamepad: ({})
        signal stateChanged()
        function set(state) {
            gamepad = state
            active = true
            stateChanged()
        }
    }
    SyntheticGamepad {
        gameController: bench.solo ? bench.solo.gameController : null
        source: agent
    }
    function pad(state) { agent.set(state) }
    function tap(state) { return [[80, () => pad(state)], [80, () => pad({})]] }

    Component.onCompleted: {
        gameComp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComp.status !== Component.Ready) {
            console.log("[Specials] FAIL", gameComp.errorString())
            Qt.exit(1)
            return
        }
        solo = makeGame({})
        script.start()
    }
    function makeGame(props) {
        let g = gameComp.createObject(bench.contentItem, Object.assign({
            width: 1000, height: 500, muted: true, descentIntro: true,
            recordStoreName: "ShapesAndStoneSpecialsBench"}, props))
        g.setDungeonMaster(false)
        g.introBeatChanged.connect(() => { if (g.introBeat > 0) beatsOf(g).push(g.introBeat) })
        return g
    }
    property var beats: ({})
    function beatsOf(g) {
        let id = String(g)
        if (!beats[id]) beats[id] = []
        return beats[id]
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
    function text(game, name) {
        let f = shown(game, name)
        return f ? f.text : ""
    }
    function hint(game) { return find(game, "controlsHint").text.replace(/\u00a0/g, " ") }
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
    // A card's name, line and mana as it shows them
    function card(game, id) {
        let c = shown(game, "specialCard_" + id)
        if (!c) return null
        return { name: find(c, "specialName").text, line: find(c, "specialLine").text,
                 mana: find(c, "specialMana").text, item: c }
    }
    function blade(id, level) {
        return Math.round(Balance.specials[id].mana * Balance.shop.bladeShare[level - 1])
    }
    // The knight ready for its special: full momentum and mana
    function ready(p) {
        p.momentum = Balance.momentum.max
        p.mana = p.maxMana
    }
    function nextDungeon(g) {
        g._enterLevel(g.levelIndex + 1)
    }

    property real pickedAt: 0
    property var spent: null

    property var soloSteps: [].concat(
        [[() => solo.screen === "title", () => {
            solo.screen = "game"
            solo.forceActiveFocus()
        }],
        [() => solo.player && solo.introOn, () => {
            check(Balance.specials.order.join(",") === "whirlwind,stun,bolt"
                  && solo.specialsOffered.join(",") === "whirlwind",
                  "the specials are the whirlwind, the stun and the bolt, the whirlwind the one in the game ("
                  + solo.specialsOffered.join(",") + ")")
            check(!solo.specialChoosing && shown(solo, "specialChoice") === null && solo.introStartsAt === 0,
                  "with one special no choice shows and the count starts at once")
            check(solo.player.special === "whirlwind", "the knight has the whirlwind")
        }],
        [() => !solo.introHeld, () => {
            let p = solo.player
            check(text(solo, "specialHud") === "Whirlwind " + Balance.knight.whirlMana,
                  "the HUD shows the whirlwind and its mana (" + text(solo, "specialHud") + ")")
            check(hint(solo).indexOf("Q whirlwind") >= 0, "the controls hint says Q whirlwind")
            ready(p)
            key(solo, Qt.Key_Q)
            check(p.isWhirling && p.momentum === 0 && Math.abs(p.maxMana - p.mana - Balance.knight.whirlMana) < 1e-6,
                  "Q whirls for " + (p.maxMana - p.mana) + " mana and the momentum")
            solo.specialsAll = true
            nextDungeon(solo)
        }],
        [() => solo.levelType === "village" && solo.player, () => {
            check(!solo.specialChoosing, "the camp has no choice")
            solo.player.bladeLevel = 1
            check(solo.smithGives("blade", 1) === "a whirlwind costs " + blade("whirlwind", 1) + " mana",
                  "the smith's balanced blade I lowers the whirlwind (" + solo.smithGives("blade", 1) + ")")
            nextDungeon(solo)
        }],
        [() => solo.levelType === "dungeon" && solo.player && solo.introOn, () => {
            check(solo.specialChoosing && shown(solo, "specialChoice") !== null,
                  "with three offered the next dungeon's intro shows the choice")
            check(shown(solo, "introDepth") !== null && shown(solo, "introName") !== null,
                  "with the depth and the dungeon's name")
            let all = Balance.specials.order.map(id => card(solo, id))
            check(all.every(c => c !== null), "a card for each of the three")
            let ok = Balance.specials.order.every((id, i) => all[i]
                && all[i].name.indexOf(Balance.specials[id].name) >= 0
                && all[i].line === Balance.specials[id].line
                && all[i].mana === blade(id, 1) + " mana")
            check(ok, "each with its name, its line and its mana with the blade ("
                  + all.map(c => c ? c.name + ": " + c.mana : "none").join(", ") + ")")
            check(solo.specialSelected === 0, "the keys are on the knight's whirlwind")
        }],
        [900, () => {
            check(solo.introWaiting && solo.introBeat === 0 && !solo.physics.running,
                  "the intro waits for the pick: no count, the world held")
            check(shown(solo, "introWait") === null, "it does not say it waits for the party")
            let p = solo.player
            ready(p)
            key(solo, Qt.Key_Q)
            check(!p.isWhirling && p.mana === p.maxMana, "Q does nothing while the choice is open")
            key(solo, Qt.Key_Right)
            let a = solo.specialSelected
            key(solo, Qt.Key_D)
            let b = solo.specialSelected
            key(solo, Qt.Key_D)
            let c = solo.specialSelected
            key(solo, Qt.Key_Left)
            let d = solo.specialSelected
            key(solo, Qt.Key_A)
            let e = solo.specialSelected
            check([a, b, c, d, e].join(",") === "1,2,2,1,0",
                  "Right, D, D, Left and A move along the cards (" + [a, b, c, d, e].join(",") + ")")
            let under = card(solo, "whirlwind").item
            check(Qt.colorEqual(under.border.color, Balance.specials.pickColor),
                  "the card under the keys is drawn in pickColor (" + under.border.color + ", chosen "
                  + under.chosen + ", selected " + find(solo, "specialChoice").selected + ")")
            // With the moves on the arrows an arrow moves the choice once,
            // not by its key and again as the keyboard's stick
            let bound = solo.controls.bind("moveLeft", "key", Qt.Key_Left)
                && solo.controls.bind("moveRight", "key", Qt.Key_Right)
            let from = solo.specialSelected
            key(solo, Qt.Key_Right)
            let right = solo.specialSelected - from
            key(solo, Qt.Key_Left)
            let left = solo.specialSelected - from - right
            solo.controls.reset()
            check(bound && right === 1 && left === -1, "with the moves bound to the arrows Right moves "
                  + right + " card and Left " + left + " (1 and -1)")
            beatsOf(solo).length = 0
            key(solo, Qt.Key_2)
            pickedAt = solo.introClock
            check(solo.player.special === "stun" && !solo.specialChoosing,
                  "2 takes the stun and the choice goes")
            check(solo.introStartsAt >= 0 && solo.introHeld, "the count starts on the pick")
        }],
        [() => !solo.introHeld, () => {
            check(beatsOf(solo).join(",") === "3,2,1" && solo.introStartsAt === pickedAt,
                  "it counts 3, 2, 1 from the pick (" + beatsOf(solo).join(",") + ") and lets go")
            let p = solo.player
            check(text(solo, "specialHud") === "Stun " + blade("stun", 1) && p.specialMana === blade("stun", 1),
                  "the HUD shows the stun and its mana with the blade (" + text(solo, "specialHud") + ")")
            check(hint(solo).indexOf("Q stun") >= 0 && hint(solo).indexOf("whirlwind") < 0,
                  "the controls hint says Q stun")
            ready(p)
            key(solo, Qt.Key_Q)
            check(!p.isWhirling && !p.isDashing && p.mana === p.maxMana && p.momentum === Balance.momentum.max,
                  "with the stun chosen Q fires no whirlwind and spends nothing")
            pad({triggerR2: 1})
        }],
        [100, () => {
            let p = solo.player
            check(!p.isWhirling && !p.isDashing && p.mana === p.maxMana && p.momentum === Balance.momentum.max,
                  "nor does the pad's R2")
            pad({})
            check(solo.smithGives("blade", 2) === "a stun costs " + blade("stun", 2) + " mana",
                  "the smith's blade II lowers the stun (" + solo.smithGives("blade", 2) + ")")
            nextDungeon(solo)
        }],
        [() => solo.levelType === "village" && solo.player, () => {
            check(solo.player.special === "stun", "the stun holds through the camp")
            nextDungeon(solo)
        }],
        [() => solo.levelType === "dungeon" && solo.specialChoosing, () => {
            check(solo.specialSelected === 1, "the next choice opens on the stun (" + solo.specialSelected + ")")
        }]],
        tap({axisX: 1}),
        [[0, () => check(solo.specialSelected === 2, "the pad's stick right moves to the bolt ("
                         + solo.specialSelected + ")")]],
        tap({axisX: -1}),
        tap({axisX: -1}),
        [[0, () => check(solo.specialSelected === 0, "left twice to the whirlwind (" + solo.specialSelected + ")")]],
        tap({buttonA: true}),
        [[() => !solo.specialChoosing, () => {
            check(solo.player.special === "whirlwind", "the pad's A takes the whirlwind")
        }]],
        [[() => !solo.introHeld, () => {
            let p = solo.player
            ready(p)
            key(solo, Qt.Key_Q)
            check(p.isWhirling && p.momentum === 0 && Math.abs(p.maxMana - p.mana - blade("whirlwind", 1)) < 1e-6,
                  "Q whirls as today, for the blade's " + (p.maxMana - p.mana) + " mana")
            nextDungeon(solo)
        }],
        [() => solo.levelType === "village" && solo.player, () => nextDungeon(solo)],
        [() => solo.levelType === "dungeon" && solo.specialChoosing && card(solo, "bolt") !== null, () => {
            let c = card(solo, "bolt").item
            keys.mouseClick(c, c.width / 2, c.height / 2, Qt.LeftButton, Qt.NoModifier, -1)
            check(solo.player.special === "bolt" && !solo.specialChoosing, "a click takes the bolt")
        }],
        [() => !solo.introHeld, () => {
            check(solo.player.special === "bolt" && text(solo, "specialHud").indexOf("Bolt") === 0,
                  "the bolt holds in its dungeon (" + text(solo, "specialHud") + ")")
            nextDungeon(solo)
        }],
        [() => solo.levelType === "village" && solo.player, () => {
            check(solo.player.special === "bolt", "and in the camp after it")
            solo.destroy()
            solo = null
            startSession()
        }]]
    )

    function startSession() {
        host = makeGame({width: 500, specialsAll: true})
        joiner = makeGame({x: 500, width: 500, specialsAll: true})
        hostNet = network(host)
        joinNet = network(joiner)
        if (!hostNet || !joinNet) {
            console.log("[Specials] FAIL no Network in the game's session")
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
    property real hostPickedAt: 0
    property real joinerPickedAt: 0

    property var sessionSteps: [
        [() => hostNet && !hostNet.connected && !joinNet.connected, () => hostNet.host()],
        [() => hostNet.networkId !== "", () => joinNet.join(hostNet.networkId)],
        [() => hostNet.connected && joinNet.connected && hostNet.nodeCount >= 2, () => {
            host.masterSeed = seed
            host._startMultiplayerGame()
        }],
        [() => bothIn() && host.specialChoosing && joiner.specialChoosing, () => {
            check(true, "in a session both knights get the choice")
            key(host, Qt.Key_2)
            hostPickedAt = session(host).now()
            check(host.player.special === "stun" && !host.specialChoosing && host.introWaiting,
                  "the host takes the stun and waits")
        }],
        [(Balance.intro.waitMax + 0.8) * 1000, () => {
            check(host.introWaiting && joiner.introWaiting && joiner.specialChoosing && !host.physics.running,
                  "past waitMax (" + Balance.intro.waitMax + " s) the host still waits for the joiner choosing")
            check(shown(host, "introWait") !== null, "and says it waits for the party")
            key(joiner, Qt.Key_3)
            joinerPickedAt = session(joiner).now()
            check(joiner.player.special === "bolt" && !joiner.specialChoosing, "the joiner takes the bolt")
        }],
        [() => !host.introWaiting && !joiner.introWaiting, () => {
            check(host.introStartsAt > 0 && host.introStartsAt === joiner.introStartsAt,
                  "both count from the same moment (" + host.introStartsAt + " / " + joiner.introStartsAt + ")")
            check(host.introStartsAt >= joinerPickedAt, "the count starts once both have picked (joiner "
                  + joinerPickedAt.toFixed(0) + ", count " + host.introStartsAt.toFixed(0) + ")")
            check(host.player.special === "stun" && joiner.player.special === "bolt",
                  "each knight keeps its own: the host the stun, the joiner the bolt")
        }],
        [() => !host.introHeld && !joiner.introHeld, () => {
            check(host.physics.running && joiner.physics.running, "then both let go")
            console.log("[Specials] done,", failures, "failed")
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
                    console.log("[Specials] FAIL step", i, "timed out")
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
