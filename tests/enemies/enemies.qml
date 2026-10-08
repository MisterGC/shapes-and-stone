// Enemy bench - two games in one process, a host and a joiner connected
// over LAN, check that the host runs every enemy and both screens show the
// same ones (issue #13).
//
// The host's knight stands at one enemy, the joiner's at the one farthest
// from it. For five seconds every frame compares each enemy on the two
// screens: its position, its AI state and the knight it goes for, and
// that the joiner shows the parry ring of a host's enemy winding up. A
// host's enemy winds up a crushing blow: the joiner shows its state
// "crush", white-hot with the doubled ring, and its lunge with no parry
// window, and the joiner's knight judges a crushing blow on its held
// shield as one. Then the
// joiner's knight kills an enemy, and falls: the enemies must go for the
// host's knight, the one still standing. Prints one PASS or FAIL line per
// check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/enemies/enemies.qml

import QtQuick
import QtQuick.Window
import Clayground.Network
import "../../src"

Window {
    id: bench
    width: 1000
    height: 500
    visible: true
    color: "#1a1a2e"

    property var host: null
    property var joiner: null
    property var hostNet: null
    property var joinNet: null
    property int failures: 0

    readonly property int seed: 424242
    // How far a joiner's enemy may be from the host's, and how far behind
    // the host's its state may be: the joiner shows the host's enemies a
    // few frames in the past
    readonly property real maxErrorWu: 0.5
    readonly property int stateLagMs: 300
    readonly property int sampleMs: 5000

    function check(ok, what) {
        console.log("[Enemies]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Enemies] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        // A record of its own: the bench keeps no best depth of the player's
        host = c.createObject(bench.contentItem, {width: 500, height: 500, muted: true,
                                                  recordStoreName: "ShapesAndStoneEnemyBench"})
        joiner = c.createObject(bench.contentItem, {x: 500, width: 500, height: 500, muted: true,
                                                    recordStoreName: "ShapesAndStoneEnemyBench"})
        hostNet = network(host)
        joinNet = network(joiner)
        if (!hostNet || !joinNet) {
            console.log("[Enemies] FAIL no Network in the game's session")
            Qt.exit(1)
            return
        }
        hostNet.signalingMode = Network.SignalingMode.Local
        hostNet.host()
        script.start()
    }

    // The game's Session and its Network, found by what they offer
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

    // The live enemies of a game, by object id
    function byId(game) {
        let m = {}
        for (let e of game.enemies)
            if (e && !e.destroyed) m[e.objectId] = e
        return m
    }
    function ids(game) { return Object.keys(byId(game)).sort() }
    function dist(a, b) {
        let dx = a.xWu - b.xWu, dy = a.yWu - b.yWu
        return Math.sqrt(dx * dx + dy * dy)
    }
    // The host's view of the two knights, by node
    function knights() {
        let k = {}
        k[hostNet.nodeId] = host.player
        k[joinNet.nodeId] = session(host).remotePlayers[joinNet.nodeId]
        return k
    }

    // Every frame for sampleMs: each enemy on both screens
    property var stats: null
    function startSampling() {
        stats = {n: 0, maxErr: 0, maxErrId: "", sumErr: 0, judged: 0, stateMiss: 0, targetMiss: 0,
                 missNote: "", history: {}, states: {}, startMs: Date.now(),
                 windUps: 0, ringShown: 0, ringMax: 0, windows: 0, windowsClosed: 0}
        sampler.start()
    }
    Timer {
        id: sampler
        interval: 16
        repeat: true
        onTriggered: {
            let st = bench.stats
            let now = Date.now()
            let h = bench.byId(bench.host), j = bench.byId(bench.joiner)
            for (let id in h) {
                let he = h[id]
                let hist = st.history[id] || (st.history[id] = [])
                hist.push({t: now, s: he.aiState, target: he.targetId})
                while (hist.length > 0 && hist[0].t < now - bench.stateLagMs) hist.shift()
                st.states[he.aiState] = true
                let je = j[id]
                if (!je) continue
                // The parry ring on the joiner's screen, from the host's
                // replicated state: shown on a wind-up, closed in the window
                if (je.aiState === "telegraph" || je.aiState === "shoot" || je.aiState === "lunge") {
                    st.windUps++
                    if (je.ringShows && je.ringProgress > 0) st.ringShown++
                    st.ringMax = Math.max(st.ringMax, je.ringProgress)
                }
                if (je.parryWindow) {
                    st.windows++
                    if (je.ringProgress === 1) st.windowsClosed++
                }
                let err = bench.dist(he, je)
                st.n++
                st.sumErr += err
                if (err > st.maxErr) { st.maxErr = err; st.maxErrId = id + " (" + he.aiState + ")" }
                // The window has to be full before the joiner's state can
                // be judged by it
                if (now - st.startMs < bench.stateLagMs) continue
                st.judged++
                if (!hist.some(x => x.s === je.aiState)) {
                    st.stateMiss++
                    st.missNote = id + ": joiner " + je.aiState + ", host " + he.aiState
                }
                if (!hist.some(x => x.target === je.targetId)) st.targetMiss++
            }
        }
    }

    property string idA: ""
    property string idB: ""
    // The host's enemy that winds up a crushing blow, and what the
    // joiner showed of it
    property string idC: ""
    property var crush: null
    Timer {
        id: crushSampler
        interval: 16
        repeat: true
        onTriggered: {
            let je = bench.byId(bench.joiner)[bench.idC]
            if (!je) return
            let c = bench.crush
            if (je.aiState === "crush") {
                c.crush++
                if (je.crushing && bench.shows(bench.joiner, "crushGlow") && bench.shows(bench.joiner, "crushRing")
                        && Qt.colorEqual(je.ringColor, Balance.crush.ringColor))
                    c.looks++
            }
            if (je.crushing && je.aiState === "lunge") c.lunge++
            if (je.crushing && je.parryWindow) c.windows++
        }
    }
    // Every item of this name anywhere under item is visible
    function shows(item, name) {
        if (!item) return false
        if (item.objectName === name && item.visible) return true
        let kids = item.children || []
        for (let i = 0; i < kids.length; i++)
            if (shows(kids[i], name)) return true
        return false
    }
    property int hostHp0: 0
    property int joinHp0: 0

    // Steps: [condition to wait for (or a delay in ms), action]
    property var steps: [
        [() => hostNet.networkId !== "", () => joinNet.join(hostNet.networkId)],
        [() => hostNet.connected && joinNet.connected && hostNet.nodeCount >= 2, () => {
            host.masterSeed = seed
            host._startMultiplayerGame()
        }],
        [() => host.player && joiner.player && host.screen === "game" && joiner.screen === "game"
               && session(host).remotePlayers[joinNet.nodeId] !== undefined
               && session(joiner).remotePlayers[hostNet.nodeId] !== undefined
               && host.enemies.length > 0 && joiner.enemies.length === host.enemies.length,
         () => {
            let h = byId(host), j = byId(joiner)
            console.log("[Enemies] both in game, host", hostNet.nodeId, "joiner", joinNet.nodeId,
                        "-", host.enemies.length, "enemies")
            check(ids(host).join() === ids(joiner).join() && ids(host).length === host.enemies.length,
                  "both screens have the same " + host.enemies.length + " enemies, by object id")
            check(Object.keys(h).every(id => h[id].enemyType === j[id].enemyType
                                       && h[id].tier === j[id].tier && h[id].maxHp === j[id].maxHp),
                  "every enemy has the same type, tier and HP on both screens")
            check(host.enemies.every(e => !e.remote && e.thinks),
                  "the host runs the AI of every enemy")
            check(joiner.enemies.every(e => e.remote && !e.thinks),
                  "the joiner runs the AI of none")
            check(joiner.enemies.every(e => e.objectId.indexOf(hostNet.nodeId + ":") === 0),
                  "every enemy is an object the host spawned")

            // The host's knight at one enemy, the joiner's at the farthest
            // from it, each a step beside it
            let es = host.enemies
            let best = -1
            for (let a of es)
                for (let b of es) {
                    let d = dist(a, b)
                    if (d > best) { best = d; idA = a.objectId; idB = b.objectId }
                }
            let a = h[idA], b = h[idB]
            host.player.hp = 100000
            joiner.player.hp = 100000
            hostHp0 = host.player.hp
            joinHp0 = joiner.player.hp
            host.player.xWu = a.xWu + 1; host.player.yWu = a.yWu
            joiner.player.xWu = b.xWu + 1; joiner.player.yWu = b.yWu
            console.log("[Enemies] host's knight at", idA, a.enemyType, "joiner's at", idB, b.enemyType,
                        best.toFixed(1), "Wu apart")
        }],
        // The joiner's knight reaches the host as a state; then watch
        [500, () => startSampling()],
        [sampleMs, () => {
            sampler.stop()
            let st = stats
            check(st.n > 0 && st.maxErr < maxErrorWu,
                  "every enemy's position agrees within " + maxErrorWu + " Wu (max "
                  + st.maxErr.toFixed(3) + " at " + st.maxErrId + ", mean "
                  + (st.sumErr / Math.max(1, st.n)).toFixed(3) + ", " + st.n + " samples)")
            check(st.judged > 0 && st.stateMiss === 0,
                  "every enemy's AI state on the joiner is the host's of the last " + stateLagMs
                  + " ms (" + st.stateMiss + " misses in " + st.judged + " samples"
                  + (st.missNote ? ", e.g. " + st.missNote : "") + ")")
            let seen = Object.keys(st.states).sort()
            check(st.states["chase"] && (st.states["telegraph"] || st.states["lunge"] || st.states["shoot"]),
                  "the enemies chased and attacked meanwhile (states seen: " + seen.join(", ") + ")")
            check(st.windUps > 0 && st.ringShown > st.windUps / 2 && st.ringMax > 0.9,
                  "the parry ring shows on the joiner's screen for the host's enemies ("
                  + st.ringShown + " of " + st.windUps + " wind-up samples, up to "
                  + st.ringMax.toFixed(3) + ")")
            check(st.windows > 0 && st.windowsClosed === st.windows,
                  "on the joiner's screen the ring is closed while the host's parry window is open ("
                  + st.windowsClosed + " of " + st.windows + " samples)")
            check(st.judged > 0 && st.targetMiss === 0,
                  "every enemy goes for the same knight on both screens, within " + stateLagMs
                  + " ms (" + st.targetMiss + " misses in " + st.judged + " samples)")

            let h = byId(host), j = byId(joiner)
            check(h[idA] && j[idA] && h[idA].targetId === hostNet.nodeId && j[idA].targetId === hostNet.nodeId,
                  "the enemy at the host's knight goes for the host's knight on both screens ("
                  + (h[idA] ? h[idA].targetId : "gone") + " / " + (j[idA] ? j[idA].targetId : "gone") + ")")
            check(h[idB] && j[idB] && h[idB].targetId === joinNet.nodeId && j[idB].targetId === joinNet.nodeId,
                  "the enemy at the joiner's knight goes for the joiner's knight on both screens ("
                  + (h[idB] ? h[idB].targetId : "gone") + " / " + (j[idB] ? j[idB].targetId : "gone") + ")")
            // Every enemy with a target goes for the nearer knight, where
            // the two are not about as near
            let k = knights(), wrong = [], checked = 0
            for (let id in h) {
                let e = h[id]
                if (e.targetId === "") continue
                let dh = dist(e, k[hostNet.nodeId]), dj = dist(e, k[joinNet.nodeId])
                if (Math.abs(dh - dj) < 1) continue
                checked++
                let nearest = dh < dj ? hostNet.nodeId : joinNet.nodeId
                if (e.targetId !== nearest || (j[id] && j[id].targetId !== nearest)) wrong.push(id)
            }
            check(checked > 0 && wrong.length === 0,
                  "every enemy with a target goes for the nearest knight on both screens ("
                  + checked + " checked" + (wrong.length ? ", wrong: " + wrong.join(" ") : "") + ")")
            check(joiner.player.hp < joinHp0,
                  "the host's enemies hurt the joiner's knight (HP " + joinHp0 + " -> " + joiner.player.hp + ")")
            check(host.player.hp < hostHp0,
                  "the host's enemies hurt the host's knight (HP " + hostHp0 + " -> " + host.player.hp + ")")

            // A melee enemy of the host's winds up a crushing blow
            let hc = Object.keys(h).map(id => h[id]).find(e => e.enemyType !== "spitter" && e.target)
            idC = hc ? hc.objectId : ""
            crush = {crush: 0, looks: 0, lunge: 0, windows: 0}
            if (hc) {
                hc.crushChance = 1
                hc.windUp(Balance.enemy.windUp)
                hc.crushChance = 0
            }
            crushSampler.start()
        }],
        [1500, () => {
            crushSampler.stop()
            let c = crush
            check(idC !== "" && c.crush > 0 && c.looks === c.crush,
                  "the joiner shows the host's crushing wind-up as \"crush\", white-hot with the doubled ring ("
                  + c.looks + " of " + c.crush + " samples, enemy " + idC + ")")
            check(c.lunge > 0 && c.windows === 0,
                  "its crushing lunge opens no parry window on the joiner's screen ("
                  + c.windows + " of " + c.lunge + " samples)")
            // The joiner's knight judges a crushing blow on its held shield
            let jp = joiner.player
            let results = []
            let record = (id, result) => results.push(result)
            joiner.knightStruck.connect(record)
            jp.graceLeft = 0
            jp.mana = jp.maxMana
            jp.facingAngle = 0
            jp.raiseShield()
            jp._raisedAt = jp._steps - Balance.knight.perfectBlockFrames - 1
            joiner._landKnightBlow({id: idC, atk: 20, x: jp.xWu + 0.5, y: jp.yWu, size: 0.8,
                                    crush: true, arrived: joiner._physicsSteps})
            joiner.knightStruck.disconnect(record)
            check(results[0] === "crushed" && Math.abs(jp.maxMana - jp.mana - Balance.enemy.crushMana) < 1e-3
                  && !jp.isBlocking && jp.shieldLock > 0,
                  "a crushing blow of the host's enemy breaks the held shield of the joiner's knight ("
                  + results.join(", ") + ", mana " + jp.maxMana + " -> " + jp.mana + ")")
            jp.lowerShield()
            // The joiner's knight strikes the enemy at it down
            let je = byId(joiner)[idB]
            if (je) je.takeDamage(100000, joiner.player.xWu, joiner.player.yWu)
        }],
        [() => !byId(host)[idB] && !byId(joiner)[idB], () => {
            check(true, "the enemy the joiner's knight killed is gone on both screens")
            check(joiner.fightRecord.kills === 1 && host.fightRecord.kills === 0,
                  "the kill counts for the joiner, not the host (joiner " + joiner.fightRecord.kills
                  + ", host " + host.fightRecord.kills + ")")
            check(ids(host).join() === ids(joiner).join(),
                  "both screens still have the same " + host.enemies.length + " enemies")
            // The joiner's knight falls
            joiner.player.hp = 0
        }],
        [1500, () => {
            let h = byId(host), j = byId(joiner)
            let targets = Object.keys(h).filter(id => h[id].targetId !== "")
            let onHost = targets.filter(id => h[id].targetId === hostNet.nodeId && j[id]
                                               && j[id].targetId === hostNet.nodeId)
            check(targets.length > 0 && onHost.length === targets.length,
                  "with the joiner's knight fallen every enemy goes for the host's knight on both screens ("
                  + onHost.length + " of " + targets.length + ")")
            check(joiner.enemies.length === host.enemies.length && joiner.enemies.every(e => !e.halted),
                  "the joiner's fall stops no enemy")
        }],
        [100, () => {
            hostNet.leave()
            joinNet.leave()
        }],
        [300, () => {
            check(joiner.enemies.length === 0, "leaving the session takes the host's enemies from the joiner ("
                  + joiner.enemies.length + " left)")
        }],
        // Torn down before quitting: the game crashes when Qt quits with it
        // still up, and the crash's exit code would hide the result
        [100, () => { host.destroy(); joiner.destroy() }],
        [300, () => {
            console.log("[Enemies] done,", failures, "failed")
            Qt.exit(failures)
        }]
    ]

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
                    console.log("[Enemies] FAIL timed out at step", i)
                    Qt.exit(100)
                }
                return
            }
            waitedMs = 0
            step[1]()
            i++
            if (i >= bench.steps.length) stop()
        }
    }
}
