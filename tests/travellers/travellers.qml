// Travellers bench - travellers rest at the camp and talk among
// themselves (issue #151).
//
// In every look (grotto at depth 0, hall at 4, ember camp at 7) on 20
// seeds a camp has one to three travellers, each a kind of its own and
// none of them the innkeeper, the smith or the witch: the way the camp,
// dialogue and gold benches look for those (objectName "npc" and its
// name) finds the camp's own three and never a traveller. Each sits on
// its ring round the fire on the floor, wanders to a prop of the look or
// another seat, has its hearsay and sells nothing, and the knights walk
// through it; one dog follows one of them. The 20 seeds pick 20 sets of
// travellers, and another screen picks the same travellers, places,
// hearsay and exchanges from the same seed. Then in a camp of two or more
// a knight stands by the fire: two travellers exchange a pair of lines
// within a minute, and a third exchange follows its plan; E at a
// traveller gives its hearsay and no wares; sent to its wander spot, its
// dog trots after it and stays beside it. Prints one PASS or FAIL line
// per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/travellers/travellers.qml

import QtQuick
import QtQuick.Window
import QtTest
import "../../src"

Window {
    id: bench
    width: 1100
    height: 950
    visible: true
    color: "#1a1a2e"

    property var game: null
    property var other: null
    property int failures: 0
    readonly property string storeName: "ShapesAndStoneTravellersBench"
    readonly property var seeds: [424242, 1000, 8919, 16838, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    readonly property var depths: ({ grotto: 0, hall: 4, ember: 7 })
    readonly property var n: Balance.camp.travellers

    function check(ok, what) {
        console.log("[Travellers]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    property var gameComponent: null
    Component.onCompleted: {
        gameComponent = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (gameComponent.status !== Component.Ready) {
            console.log("[Travellers] FAIL", gameComponent.errorString())
            Qt.exit(1)
            return
        }
        game = gameComponent.createObject(bench.contentItem, {width: bench.width, height: bench.height,
                                                              muted: true, recordStoreName: storeName})
        script.start()
    }

    function inCamp(g) { return g && g.player && g.levelType === "village" && !g.resetting }
    function r3(v) { return Math.round(v * 1000) / 1000 }
    // As the camp, dialogue and gold benches look for the camp's people
    function person(g, name) {
        let kids = g.room.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i].objectName === "npc" && kids[i].npcName === name) return kids[i]
        return null
    }
    function travellersOf(g) { return g.room.children.filter(o => o && o.objectName === "traveller") }
    function centre(t) { return Qt.point(t.xWu + t.widthWu / 2, t.yWu - t.heightWu / 2) }
    function onFloor(g, p) {
        let gx = Math.floor(p.x / g.cellSize), gy = Math.floor(p.y / g.cellSize)
        return g.grid[gy] && g.grid[gy][gx] === g.cellRoom && !g._buildingCells[gy * g.gridWidth + gx]
    }

    // What one seed's camp's travellers are, as the checks read them
    function survey(g, seed) {
        let ts = travellersOf(g), fire = g.campfire
        let fx = fire.xWu + fire.widthWu / 2, fy = fire.yWu - fire.heightWu / 2
        let names = ts.map(t => t.npcName)
        let dogs = g.dungeonObjects.filter(o => o && o.creature === "dog")
        let seats = ts.map(t => Qt.point(t.routine[0].x + 0.4, t.routine[0].y - 0.4))
        let spots = ts.map(t => Qt.point(t.routine[1].x + 0.4, t.routine[1].y - 0.4))
        let talk = g.campTalk
        return {
            seed: seed, look: g.campLook.name, count: ts.length, names: names,
            kinds: names.every(nm => n.kinds.some(k => k.name === nm)) && new Set(names).size === names.length,
            notPeople: ["Innkeeper", "Blacksmith", "Witch"].every(nm => {
                let p = person(g, nm)
                return p !== null && ts.indexOf(p) < 0 && names.indexOf(nm) < 0
            }),
            seated: seats.every(s => {
                let r = Math.hypot(s.x - fx, s.y - fy)
                return r >= n.ring[0] - 1e-6 && r <= n.ring[1] + 1e-6 && onFloor(g, s)
            }) && ts.every((t, i) => Math.hypot(centre(t).x - seats[i].x, centre(t).y - seats[i].y) < 0.3),
            wander: spots.every(s => onFloor(g, s)) && ts.every(t => t.routine.length === 2),
            heard: ts.every(t => t.dialogueLines.length === n.hearsayLines
                                 && t.dialogueLines.every(l => n.hearsay.indexOf(l) >= 0)
                                 && t.wares.length === 0 && t.speak === null),
            through: ts.every(t => t.solid === false),
            dog: dogs.length === 1 && ts.indexOf(dogs[0].leader) >= 0 && g.campDog === dogs[0],
            planned: !!talk && talk.plan.length === n.exchanges.length
                     && talk.plan.every(e => e.a !== e.b || ts.length < 2),
            key: names.join("+") + " " + seats.map(s => r3(s.x) + "," + r3(s.y)).join(" ")
                 + " | " + spots.map(s => r3(s.x) + "," + r3(s.y)).join(" ")
                 + " | " + ts.map(t => t.dialogueLines.map(l => l.slice(0, 8)).join("/")).join(" ")
                 + " | " + (talk ? talk.plan.map(e => e.a + ">" + e.b + ":" + e.lines[0].slice(0, 8)).join(" ") : "")
                 + " | " + (dogs[0] ? dogs[0].leader.npcName + " " + r3(dogs[0].seed) : "")
        }
    }

    // The knight's centre to (x, y) wu, the camera on it
    function placeKnight(g, x, y) {
        g.player.xWu = x - 0.5
        g.player.yWu = y + 0.5
        g.camera.target = null
        g.camera.target = g.player
    }

    // --- The steps ---
    property var results: []
    property var steps: []
    property var talkSeed: 0
    property var traveller: null
    property int goal: 0
    property real t0: 0
    function panel() {
        for (let i = 0; i < game.data.length; i++)
            if (game.data[i] && typeof game.data[i].advance === "function"
                && game.data[i].wares !== undefined) return game.data[i]
        return null
    }
    function buildSteps() {
        let s = []
        let looks = Object.keys(depths)
        for (let name of looks)
            for (let seed of seeds) {
                s.push([() => true, () => game.applyScenario("village", depths[name], seed)])
                s.push([() => inCamp(game), () => results.push(survey(game, seed))])
            }
        s.push([() => true, () => judge()])
        // Another screen picks the same travellers
        s.push([() => true, () => {
            other = gameComponent.createObject(bench.contentItem, {x: bench.width, width: 400, height: 300,
                                                                   muted: true, recordStoreName: storeName})
        }])
        for (let name of looks)
            for (let seed of seeds.slice(0, 6)) {
                s.push([() => true, () => other.applyScenario("village", depths[name], seed)])
                s.push([() => inCamp(other), () => {
                    let mine = results.find(r => r.seed === seed && r.look === name)
                    let theirs = survey(other, seed)
                    check(mine && theirs.key === mine.key, name + ", seed " + seed
                          + ": another screen picks the same travellers, places, hearsay and exchanges ("
                          + theirs.names.join(", ") + ")")
                }])
            }
        s.push([300, () => { other.destroy(); other = null }])

        // In a camp of two or more, a knight by the fire hears them talk
        s.push([() => true, () => {
            talkSeed = (results.find(r => r.look === "grotto" && r.count >= 2) || {}).seed
            game.applyScenario("village", 0, talkSeed)
            t0 = Date.now()
        }])
        s.push([() => inCamp(game), () => {
            let f = game.campfire
            placeKnight(game, f.xWu + f.widthWu / 2, f.yWu + 4)
        }])
        s.push([() => game.campTalk.said.length >= 2 || Date.now() - t0 > 61000, () => {
            let said = game.campTalk.said, secs = (Date.now() - t0) / 1000
            let pair = said.length >= 2 && n.exchanges.some(e => e[0] === said[0].line && e[1] === said[1].line)
            check(said.length >= 2 && pair && said[0].who !== said[1].who && secs <= 60,
                  "seed " + talkSeed + ": two travellers exchange a pair of lines " + secs.toFixed(1)
                  + " s into the camp: " + said.slice(0, 2).map(x => x.who + ": \"" + x.line + "\"").join(" / "))
            let e = game.campTalk.plan[0], ts = game.campTravellers
            check(said.length >= 2 && said[0].who === ts[e.a].npcName && said[1].who === ts[e.b].npcName
                  && said[0].line === e.lines[0], "it is the first of the camp's plan, said by whom it names")
            check(said.length >= 2 && Math.abs(said[1].t - said[0].t - n.answer) < 0.15,
                  "the answer comes " + n.answer + " s after the line (" + (said.length >= 2
                  ? r3(said[1].t - said[0].t) : "-") + " s)")
            let speaker = ts.find(t => t.npcName === said[1].who)
            check(speaker && speaker.saying === said[1].line, "the answer shows in the speaker's bubble")
            t0 = Date.now()
        }])
        // The next exchange follows the plan
        s.push([() => game.campTalk.said.length >= 4 || Date.now() - t0 > 40000, () => {
            let said = game.campTalk.said, e = game.campTalk.plan[1]
            check(said.length >= 4 && said[2].line === e.lines[0] && said[3].line === e.lines[1],
                  "the next exchange is the plan's second (" + (said[2] ? said[2].who + ": \"" + said[2].line + "\"" : "none")
                  + ")")
        }])

        // E at a traveller: its hearsay, no wares
        s.push([() => true, () => {
            traveller = game.campTravellers[0]
            let c = centre(traveller)
            placeKnight(game, c.x, c.y + 1.2)
            t0 = Date.now()
        }])
        s.push([() => traveller.nearbyPlayer !== null || Date.now() - t0 > 3000, () => {
            game.forceActiveFocus()
            press(Qt.Key_E)
        }])
        s.push([300, () => {
            let p = panel()
            check(p && p.visible && p.speakerName === traveller.npcName && p.wares.length === 0
                  && p.lines.length === n.hearsayLines && p.lines.every(l => n.hearsay.indexOf(l) >= 0),
                  "E at the " + traveller.npcName + " gives " + n.hearsayLines + " lines of hearsay and no wares: "
                  + (p ? p.lines.join(" / ") : "no panel"))
            for (let i = 0; i < 4 && p && p.visible; i++) press(Qt.Key_E)
            check(p && !p.visible, "E through the lines closes it")
            // The dog's traveller goes to the farther of its seat and its
            // wander spot
            traveller = game.campDog.leader
            let c = centre(traveller)
            let far = traveller.routine.map(r => Math.hypot(r.x + 0.4 - c.x, r.y - 0.4 - c.y))
            goal = far[1] > far[0] ? 1 : 0
            traveller._routineIndex = goal
            traveller._atDestination = false
            traveller._activityText = ""
            placeKnight(game, game.entranceGridX * game.cellSize + 1, game.campfire.yWu - 12)
            t0 = Date.now()
        }])
        s.push([() => traveller._routineIndex === goal && traveller.doing !== null || Date.now() - t0 > 25000, () => {
            let c = centre(traveller), from = traveller.routine[1 - goal]
            check(traveller._routineIndex === goal && traveller.doing !== null, "the " + traveller.npcName
                  + " walks " + r3(Math.hypot(c.x - from.x - 0.4, c.y - from.y + 0.4)) + " wu to "
                  + (traveller.routine[goal].text || "its spot") + " in " + (Date.now() - t0) + " ms")
        }])
        s.push([1500, () => {
            let d = game.campDog, c = centre(traveller)
            let off = Math.hypot(d.xWu - c.x, d.yWu - c.y)
            check(!d.moving && off < n.dog.follow + 0.5, "its dog trotted after it and sits beside it ("
                  + r3(off) + " wu off, moving " + d.moving + ", dog " + r3(d.xWu) + "," + r3(d.yWu) + " spot "
                  + r3(d.spot().x) + "," + r3(d.spot().y) + ")")
        }])

        s.push([300, () => game.destroy()])
        s.push([300, () => {
            console.log("[Travellers] done,", failures, "failed")
            Qt.exit(failures)
        }])
        return s
    }

    function judge() {
        let list = (rs, f) => rs.filter(f).map(r => r.look + " " + r.seed).join(", ")
        check(results.every(r => r.count >= n.count[0] && r.count <= n.count[1]),
              "every camp has " + n.count[0] + " to " + n.count[1] + " travellers "
              + list(results, r => r.count < n.count[0] || r.count > n.count[1]))
        for (let k = n.count[0]; k <= n.count[1]; k++)
            check(results.some(r => r.count === k), results.filter(r => r.count === k).length + " camps have " + k)
        check(results.every(r => r.kinds), "each a kind of its own " + list(results, r => !r.kinds))
        check(results.every(r => r.notPeople), "looked for as the camp, dialogue and gold benches look, the "
              + "innkeeper, the smith and the witch are the camp's own, never a traveller "
              + list(results, r => !r.notPeople))
        check(results.every(r => r.seated), "each sits " + n.ring[0] + " to " + n.ring[1]
              + " wu from the fire's centre, on the floor " + list(results, r => !r.seated))
        check(results.every(r => r.wander), "each wanders to a spot on the floor " + list(results, r => !r.wander))
        check(results.every(r => r.heard), "each has " + n.hearsayLines + " lines of hearsay and sells nothing "
              + list(results, r => !r.heard))
        check(results.every(r => r.through), "the knights walk through them " + list(results, r => !r.through))
        check(results.every(r => r.dog), "one dog follows one of them " + list(results, r => !r.dog))
        check(results.every(r => r.planned), "each camp plans every exchange once, between two of them "
              + list(results, r => !r.planned))
        for (let look of Object.keys(depths)) {
            let rs = results.filter(r => r.look === look)
            let keys = new Set(rs.map(r => r.key))
            check(keys.size === rs.length, look + ": " + rs.length + " seeds pick " + keys.size + " sets of travellers")
        }
    }

    Timer {
        id: script
        property int i: 0
        property real waitedMs: 0
        interval: 20
        repeat: true
        onTriggered: {
            if (i === 0 && bench.steps.length === 0) bench.steps = bench.buildSteps()
            let step = bench.steps[i]
            waitedMs += interval
            let ready = typeof step[0] === "number" ? waitedMs >= step[0] : step[0]()
            if (!ready) {
                if (waitedMs > 70000) {
                    console.log("[Travellers] FAIL step", i, "timed out")
                    Qt.exit(failures + 100)
                    stop()
                }
                return
            }
            waitedMs = 0
            i++
            if (i >= bench.steps.length) stop()
            step[1]()
        }
    }
}
