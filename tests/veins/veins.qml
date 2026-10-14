// Veins bench - veins glint in the dungeon's walls, their gems go into a
// pouch, and the smith buys them (issue #156).
//
// First one knight alone. The dungeon on 20 seeds, each at a low, a
// middle and a high danger, built twice: the same veins on the same
// cells with the same gems and strikes, each in the face of a wall cell
// north of a room's cell, not in the start room, its gem the depth's,
// and no torch on a vein's cell or on another torch's (also on the two
// seeds where a torch stepped aside onto the other one), each vein's cell
// in a rough rock face (issue #169); none in the camp
// nor in the fight room. A vein far from the knight's
// lantern is dark, one in it glints; the deepest gem glows on its own.
// Then in the dojo's deep scenario two veins are cut, one with every
// strike clean and one with none: each gem goes into the pouch worth the
// table's value, the HUD shows a count per shape, the camp keeps the
// pouch, and the smith, with E and 1, buys the gems for their worth.
// A knight that falls alone drops its pouch where it fell. Then a host
// and a joiner in one process, joined over LAN: both build the same
// veins; a vein the joiner cuts is split on the host's screen too and
// its gem is the joiner's, one the host cuts is split on the joiner's; a
// second claim for a vein split gives nothing and shows the joiner LOST;
// both knights cut the same vein, the host's claim first: the joiner's
// split shows no gem until the host answers, and then LOST, the gem the
// host's (#168 review); a pouch dropped on another level than the host's
// is refused and stays with the knight (#168 review); the host's knight falls
// and its pouch lies on both screens where it fell, the joiner lifts it
// up and takes the pouch; the joiner's knight falls and the host walks
// over its pouch and takes it, the joiner's pouch leaving it only once the
// host laid it down. Prints one PASS or FAIL line per check and
// exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/veins/veins.qml

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
    property int failures: 0

    readonly property var cfg: Balance.deep
    readonly property int seeds: 20
    readonly property var dangers: [0.3, 1.6, 2.8]
    // The session's seed: its first dungeon holds veins
    readonly property int coopSeed: 424242
    readonly property string storeName: "ShapesAndStoneVeinsBench"

    function check(ok, what) {
        console.log("[Veins]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    property var gameComponent: null
    Component.onCompleted: {
        gameComponent = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComponent.status !== Component.Ready) {
            console.log("[Veins] FAIL", gameComponent.errorString())
            Qt.exit(1)
            return
        }
        solo = gameComponent.createObject(bench.contentItem, {width: 1000, height: 500, muted: true,
                                                              recordStoreName: storeName})
        script.steps = soloSteps.concat(placementSteps()).concat(afterPlacement).concat(coopSteps)
        script.start()
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
    function panel(game) {
        for (let i = 0; i < game.data.length; i++)
            if (game.data[i] && typeof game.data[i].advance === "function"
                && game.data[i].wares !== undefined) return game.data[i]
        return null
    }
    function npc(game, name) {
        let kids = game.room.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i].objectName === "npc" && kids[i].npcName === name) return kids[i]
        return null
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
    function haltAll(game) { for (let e of game.enemies) if (e && !e.destroyed && e.halt) e.halt() }

    // The veins of a game as lines, "gx,gy:shape:strikes"
    function veinLines(game) {
        return game.veins.map(v => v.cell + ":" + v.shape + ":" + v.strikes).sort()
    }
    // What rule vein v breaks on the grid, "" for none
    function veinBroken(game, v) {
        let c = v.cell.split(",").map(Number), g = game.grid, start = game.rooms[0]
        if (g[c[1]][c[0]] !== game.cellWall) return "not on a wall cell"
        let fy = c[1] - 1
        if (g[fy][c[0]] !== game.cellRoom) return "no room's cell south of it"
        if (c[0] >= start.x && c[0] < start.x + start.w && fy >= start.y && fy < start.y + start.h)
            return "in the start room"
        if (v.shape !== game.gemOf(game.dangerDepth).shape) return "not the depth's gem"
        return ""
    }
    // The torches of a game that stand on a vein's cell or on another
    // torch's spot: ["x,y ..."]
    function torchesClashing(game) {
        let seen = {}, out = []
        let veinAt = {}
        for (let v of game.veins) veinAt[v.cell] = true
        for (let t of game.torches) {
            if (!t) continue
            let key = t.xWu.toFixed(3) + "," + t.yWu.toFixed(3)
            let cell = Math.floor(t.xWu / game.cellSize) + "," + Math.floor(t.yWu / game.cellSize)
            if (seen[key]) out.push(key + " on another torch")
            if (veinAt[cell]) out.push(key + " on the vein of " + cell)
            seen[key] = true
        }
        return out
    }
    // The veins of a game whose cell no rough rock face covers: ["x,y"]
    function veinsBare(game) {
        let cs = game.cellSize
        return game.veins.filter(v => {
            let c = v.cell.split(",").map(Number)
            return !game.rockFaces.some(f => f.faceStyle === "rock"
                                         && Math.abs(f.yWu - (c[1] * cs + game.wallFaceWu)) < 1e-6
                                         && f.xWu <= c[0] * cs + 1e-6 && f.xWu + f.widthWu >= (c[0] + 1) * cs - 1e-6)
        }).map(v => v.cell)
    }
    // The knight's centre in front of vein v's face, off by dx
    function standAtVein(game, v, dx) {
        let p = game.player
        p.xWu = v.faceXWu + (dx || 0) - p.widthWu / 2
        p.yWu = v.cyWu - v.sizeWu / 2 - 0.6 + p.heightWu / 2
    }
    // Cuts vein v with its knight: aimed at it, clean strikes of the left
    // button on the closes, or each half a beat off them; the dig started
    // and judged at once
    function cutVein(game, v, clean) {
        game.endDig()
        standAtVein(game, v)
        game.aimOverride = { x: v.faceXWu, y: v.faceYWu }
        if (!game.pressPick() || !game.dig || game.dig.vein !== v) return false
        for (let i = 0; i < v.strikes; i++) {
            game.dig.t = (i + (clean ? 1 : 0.5)) * cfg.ringTime
            game.pressPick()
        }
        game.aimOverride = null
        return v.split
    }
    function centreOf(game) { return game._knightCentre() }

    // --- One knight alone ---
    property var soloSteps: [
        [() => solo.width > 0, () => {
            check(Balance.dungeon.kinds.vein && Balance.dungeon.kinds.vein.perRoom.length === 3,
                  "Balance.dungeon.kinds.vein has a per room for each danger band: "
                  + JSON.stringify(Balance.dungeon.kinds.vein.perRoom))
            check(cfg.shapes.every(g => g.value && g.value[0] > 0 && g.value[1] > g.value[0])
                  && cfg.shapes.every((g, i) => i === 0 || g.value[0] > cfg.shapes[i - 1].value[0]),
                  "Balance.deep gives each shape a value, deeper ones worth more: "
                  + cfg.shapes.map(g => g.shape + " " + g.value.join("-")).join(", "))
        }]
    ]
    // The same seed and danger twice: the same veins, by the rules
    property var placed: ({ lines: 0, same: 0, builds: 0, broken: [], least: 1e9, empty: 0, perBand: [0, 0, 0],
                            clashes: [], bare: [] })
    function placementSteps() {
        let out = []
        for (let i = 0; i < seeds; i++) {
            for (let dg of dangers) {
                out.push([40, () => {
                    let seed = 2000 + i * 7919
                    solo.applyScenario("dungeon", dg, seed)
                    let a = veinLines(solo)
                    for (let v of solo.veins) {
                        let why = veinBroken(solo, v)
                        if (why !== "") placed.broken.push("seed " + seed + " danger " + dg + " " + v.cell + " " + why)
                    }
                    for (let c of torchesClashing(solo)) placed.clashes.push("seed " + seed + " danger " + dg + " " + c)
                    for (let c of veinsBare(solo)) placed.bare.push("seed " + seed + " danger " + dg + " " + c)
                    solo.applyScenario("dungeon", dg, seed)
                    let b = veinLines(solo)
                    placed.builds++
                    if (JSON.stringify(a) === JSON.stringify(b)) placed.same++
                    placed.lines += a.length
                    placed.least = Math.min(placed.least, a.length)
                    if (a.length === 0) placed.empty++
                    placed.perBand[solo.dangerBand(solo.dangerPosition)] += a.length
                }])
            }
        }
        // The two seeds where a torch stepped aside onto the other one
        for (let sd of [[81190, 2.8], [492978, 0.3]]) {
            out.push([40, () => {
                solo.applyScenario("dungeon", sd[1], sd[0])
                for (let c of torchesClashing(solo)) placed.clashes.push("seed " + sd[0] + " danger " + sd[1] + " " + c)
                bench.torchSeeds++
            }])
        }
        return out
    }
    property var afterPlacement: [
        [100, () => {
            check(placed.builds === seeds * dangers.length && placed.same === placed.builds,
                  "the same seed and danger place the same veins, gems and strikes on " + placed.same + " of "
                  + placed.builds + " dungeons (" + seeds + " seeds at danger " + dangers.join(", ") + ")")
            check(placed.lines > 0 && placed.empty < placed.builds / 2,
                  "they place " + placed.lines + " veins, " + placed.empty + " dungeons without one; by band "
                  + placed.perBand.join(", "))
            check(placed.broken.length === 0, "every vein sits in the face of a wall cell north of a room's "
                  + "cell, not in the start room, its gem the depth's"
                  + (placed.broken.length ? ": " + placed.broken.length + " not, e.g. " + placed.broken.slice(0, 3).join("; ") : ""))
            check(placed.clashes.length === 0 && bench.torchSeeds === 2,
                  "no torch stands on a vein or on another torch, on these dungeons and seeds 81190 and 492978"
                  + (placed.clashes.length ? ": " + placed.clashes.length + ", e.g. " + placed.clashes.slice(0, 3).join("; ") : ""))
            check(placed.bare.length === 0, "every vein sits in a rough rock face"
                  + (placed.bare.length ? ": " + placed.bare.length + " not, e.g. " + placed.bare.slice(0, 3).join("; ") : ""))
            let camps = 0
            for (let i = 0; i < 5; i++) {
                solo.applyScenario("village", i * 2, 2000 + i * 7919)
                camps += solo.veins.length + solo.features.filter(f => f.kind === "vein").length
            }
            solo.applyScenario("fight")
            let fight = solo.veins.length
            check(camps === 0 && fight === 0, "no vein in the camp (5 camps: " + camps + ") nor in the fight room ("
                  + fight + ")")
            // A dungeon with a vein: the knight far from it, then in front
            for (let i = 0; i < seeds; i++) {
                solo.applyScenario("dungeon", 2.8, 2000 + i * 7919)
                if (solo.veins.length > 0) break
            }
            let v = solo.veins[0]
            solo.player.xWu = v.faceXWu + cfg.glintReach + 3
            solo.player.yWu = v.faceYWu - 6
        }],
        [200, () => {
            let v = solo.veins[0]
            check(v.lit === 0 && !v.knightNear, "a vein out of every lantern's reach is dark (lit " + v.lit + ")")
            standAtVein(solo, v)
        }],
        [200, () => {
            let v = solo.veins[0]
            check(v.lit === 1 && v.knightNear, "in the knight's lantern it glints at full (lit " + v.lit
                  + ") and shimmers")
            solo.applyScenario("deep", 8)
            check(solo.veins[0].selfLit && !solo.veins[0].split,
                  "the deepest gem, the " + solo.veins[0].shape + ", glows on its own")
            // Depth 2's cube: one vein cut clean, a second one beside it
            // cut with no clean strike
            solo.applyScenario("deep", 2)
        }],
        [200, () => {
            let v = solo.veins[0]
            let c = v.cell.split(",").map(Number)
            let w = solo.placeVein(c[0] + 2, c[1])
            check(solo.player.pouch.length === 0 && !find(solo, "hudPouch").visible,
                  "the knight starts with an empty pouch, the HUD shows none")
            let ok1 = cutVein(solo, v, true)
            let ok2 = cutVein(solo, w, false)
            let want = [cfg.shapes[1].value[1], cfg.shapes[1].value[0]]
            check(ok1 && ok2 && solo.player.pouch.length === 2
                  && solo.player.pouch.every(g => g.shape === "cube")
                  && solo.player.pouch.map(g => g.value).join() === want.join(),
                  "two cubes cut, one clean and one chipped all through, go into the pouch worth the table's "
                  + want.join(" and ") + " gold: " + JSON.stringify(solo.player.pouch))
        }],
        // The gems won land in the pouch and the HUD counts them
        [() => solo.wonGems.length === 0, () => {
            let h = find(solo, "hudPouch")
            check(h.visible && h.summary === "cube 2", "the HUD shows the pouch's count per shape (" + h.summary + ")")
            pouchWorth = solo.pouchWorth(solo.player.pouch)
            solo._enterLevel(solo.levelIndex + 1)
        }],
        [() => solo.player && solo.levelType === "village", () => {
            check(solo.player.pouch.length === 2 && find(solo, "hudPouch").summary === "cube 2",
                  "the camp keeps the pouch (" + find(solo, "hudPouch").summary + ")")
            solo.player.gold = 7
            let smith = npc(solo, "Blacksmith")
            solo.player.xWu = smith.xWu
            solo.player.yWu = smith.yWu - 1
        }],
        [() => npc(solo, "Blacksmith").nearbyPlayer !== null, () => {
            solo.forceActiveFocus()
            press(Qt.Key_E)
        }],
        [() => panel(solo).visible, () => {
            let p = panel(solo)
            check(p.wares.length > 0 && p.wares[0].id === "gems" && p.wares[0].sell
                  && p.wares[0].price === pouchWorth,
                  "the smith offers first to buy the gems, for their worth " + pouchWorth + " ("
                  + (p.wares[0] ? p.wares[0].label + " + " + p.wares[0].price : "nothing") + ")")
            press(Qt.Key_1)
            check(solo.player.gold === 7 + pouchWorth && solo.player.pouch.length === 0,
                  "1 sells them: the gold goes from 7 to " + solo.player.gold + " (+" + pouchWorth
                  + "), the pouch is empty")
            check(!find(solo, "hudPouch").visible && p.wares.every(w => w.id !== "gems"),
                  "the HUD shows no pouch, the smith offers none more")
            for (let i = 0; i < 8 && p.visible; i++) press(Qt.Key_E)
            // A knight that falls alone drops its pouch where it fell
            solo.applyScenario("deep", 4)
        }],
        [200, () => {
            cutVein(solo, solo.veins[0], true)
            let c = centreOf(solo)
            fallAt = c
            solo.player.hp = 0
        }],
        [() => solo.fallen, () => {
            let d = solo.pouchDrops[0]
            check(solo.player.pouch.length === 0 && solo.pouchDrops.length === 1
                  && Math.abs(d.xWu - fallAt.x) < 1e-6 && Math.abs(d.yWu - fallAt.y) < 1e-6
                  && solo.pouchOf(d.gems).length === 1 && solo.pouchOf(d.gems)[0].shape === "octahedron",
                  "a knight that falls alone drops its pouch where it fell, its octahedron in it ("
                  + (d ? d.gems : "none") + ")")
            solo.destroy()
        }]
    ]
    property int pouchWorth: 0
    property int torchSeeds: 0
    property var fallAt: null

    // --- A host and a joiner ---
    function veinsBoth() {
        return host.veins.length > 0 && JSON.stringify(veinLines(host)) === JSON.stringify(veinLines(joiner))
    }
    function splitOn(game, cell) {
        let v = game.veinAt(cell)
        return v !== null && v.split
    }
    function dropsOf(game, owner) {
        return game.pouchDrops.filter(d => d && d.owner === owner)
    }
    property string cutJ: ""
    property string cutH: ""
    property string cutR: ""
    property var hostFall: null
    property var joinFall: null
    property var coopSteps: [
        [300, () => {
            host = gameComponent.createObject(bench.contentItem, {width: 500, height: 500, muted: true,
                                                                  recordStoreName: storeName})
            joiner = gameComponent.createObject(bench.contentItem, {x: 500, width: 500, height: 500,
                                                                    muted: true, recordStoreName: storeName})
            hostNet = network(host)
            joinNet = network(joiner)
            hostNet.signalingMode = Network.SignalingMode.Local
            hostNet.host()
        }],
        [() => hostNet.networkId !== "", () => joinNet.join(hostNet.networkId)],
        [() => hostNet.connected && joinNet.connected && hostNet.nodeCount >= 2, () => {
            host.masterSeed = coopSeed
            host._startMultiplayerGame()
        }],
        [() => host.player && joiner.player && host.screen === "game" && joiner.screen === "game"
               && Object.keys(session(host).remotePlayers).length > 0
               && Object.keys(session(joiner).remotePlayers).length > 0, () => {
            haltAll(host)
            host.player.hp = 100000
            joiner.player.hp = 100000
            check(veinsBoth() && host.veins.length >= 2,
                  "both screens build the same " + host.veins.length + " veins on seed " + coopSeed
                  + " (host " + veinLines(host).join(" ") + "; joiner " + veinLines(joiner).join(" ") + ")")
            cutJ = joiner.veins[0].cell
            cutH = host.veins[1].cell
            check(cutVein(joiner, joiner.veinAt(cutJ), true), "the joiner's knight cuts the vein on " + cutJ)
        }],
        [() => splitOn(host, cutJ) && joiner.player.pouch.length === 1, () => {
            let v = host.veinAt(cutJ)
            check(joiner.player.pouch[0].shape === v.shape
                  && joiner.player.pouch[0].value === host.gemValue(v.shape, v.strikes, v.strikes)
                  && host.player.pouch.length === 0,
                  "it is split on the host's screen too, and its " + v.shape + " worth "
                  + joiner.player.pouch[0].value + " is the joiner's, not the host's")
            check(cutVein(host, host.veinAt(cutH), false), "the host's knight cuts the vein on " + cutH)
        }],
        [() => splitOn(joiner, cutH) && host.player.pouch.length === 1, () => {
            check(true, "the vein the host cut is split on the joiner's screen too")
            // A second claim for the vein already split
            session(joiner).reportCut(joiner.levelIndex, cutJ, 3)
        }],
        [() => joiner.gemsLost === 1, () => {
            check(joiner.player.pouch.length === 1 && host.player.pouch.length === 1,
                  "a second claim for a vein split gives no gem, the joiner is shown LOST (joiner "
                  + joiner.player.pouch.length + ", host " + host.player.pouch.length + ")")
            // Both knights at the same vein, the host's claim first
            cutR = host.veins.find(v => !v.split).cell
            let won = joiner.gemsWon
            check(cutVein(joiner, joiner.veinAt(cutR), true) && joiner.gemsWon === won
                  && joiner._cutsAsked[cutR] !== undefined,
                  "the joiner's knight splits the vein on " + cutR + ": no gem shows until the host answers")
            check(cutVein(host, host.veinAt(cutR), true) && host.player.pouch.length === 2,
                  "the host's knight splits it too, its claim first: the gem is the host's")
        }],
        [() => joiner.gemsLost === 2, () => {
            check(joiner.player.pouch.length === 1 && joiner.gemsWon === 1 && joiner._cutsAsked[cutR] === undefined
                  && host.player.pouch.length === 2,
                  "the joiner's claim is refused: it is shown LOST, no gem won and its pouch still holds 1")
            // A pouch dropped on another level than the host's
            host._hostDropPouch(joinNet.nodeId, { xWu: 1, yWu: 1, gems: "cube:9", level: host.levelIndex + 1 })
        }],
        [() => joiner.pouchDropsRefused === 1, () => {
            check(host.pouchDrops.length === 0 && joiner.pouchDrops.length === 0 && joiner.player.pouch.length === 1,
                  "a pouch dropped on another level than the host's is refused: none lies on either screen, "
                  + "the joiner's stays with it")
            // The host's knight falls; the joiner stands beside it, out of
            // the pouch's reach, and lifts it up
            hostFall = centreOf(host)
            joiner.player.xWu = host.player.xWu + 1.2
            joiner.player.yWu = host.player.yWu
            host.player.hp = 0
        }],
        [() => host.fallen && dropsOf(host, hostNet.nodeId).length === 1
               && dropsOf(joiner, hostNet.nodeId).length === 1, () => {
            let a = dropsOf(host, hostNet.nodeId)[0], b = dropsOf(joiner, hostNet.nodeId)[0]
            check(host.player.pouch.length === 0 && a.objectId !== "" && a.objectId === b.objectId
                  && Math.abs(b.xWu - hostFall.x) < 1e-3 && Math.abs(b.yWu - hostFall.y) < 1e-3
                  && host.pouchOf(b.gems).length === 2,
                  "the host's knight fell: its pouch lies on both screens where it fell (" + b.gems + ")")
        }],
        [() => !host.fallen, () => {
            check(true, "the joiner lifted the host's knight up")
        }],
        [() => dropsOf(host, hostNet.nodeId).length === 0 && dropsOf(joiner, hostNet.nodeId).length === 0
               && joiner.player.pouch.length === 3, () => {
            check(host.player.pouch.length === 0,
                  "lifting it up the joiner took its pouch: 3 gems now, the host none, the pouch gone on both screens")
            joinFall = centreOf(joiner)
            host.player.xWu = joiner.player.xWu + 6
            host.player.yWu = joiner.player.yWu
            joiner.player.hp = 0
            check(joiner.fallen && joiner.player.pouch.length === 3 && joiner._pouchDropAsked === 3,
                  "the joiner's knight fell: its pouch stays with it until the host answers")
        }],
        [() => joiner.fallen && dropsOf(host, joinNet.nodeId).length === 1 && joiner.player.pouch.length === 0, () => {
            let d = dropsOf(host, joinNet.nodeId)[0]
            check(host.pouchOf(d.gems).length === 3,
                  "the host laid it down: its pouch of 3 gems lies on the host's screen, the joiner's is empty ("
                  + d.gems + ")")
            host.player.xWu = d.xWu - host.player.widthWu / 2
            host.player.yWu = d.yWu + host.player.heightWu / 2
        }],
        [() => dropsOf(host, joinNet.nodeId).length === 0 && dropsOf(joiner, joinNet.nodeId).length === 0
               && host.player.pouch.length === 3, () => {
            check(joiner.player.pouch.length === 0,
                  "the host's knight walked over it and took it: 3 gems, the pouch gone on both screens")
            console.log("[Veins] done,", failures, "failed")
            joinNet.leave()
            hostNet.leave()
        }],
        [500, () => { host.destroy(); joiner.destroy() }],
        [300, () => Qt.exit(failures)]
    ]

    Timer {
        id: script
        property var steps: []
        property int i: 0
        property real waitedMs: 0
        interval: 20
        repeat: true
        onTriggered: {
            let step = steps[i]
            waitedMs += interval
            let ready = typeof step[0] === "number" ? waitedMs >= step[0] : step[0]()
            if (!ready) {
                if (waitedMs > 20000) {
                    console.log("[Veins] FAIL step", i, "timed out")
                    Qt.exit(failures + 1)
                    stop()
                }
                return
            }
            waitedMs = 0
            i++
            if (i >= steps.length) stop()
            try {
                step[1]()
            } catch (err) {
                console.log("[Veins] FAIL step", i - 1, "threw:", err)
                Qt.exit(failures + 1)
                stop()
            }
        }
    }
}
