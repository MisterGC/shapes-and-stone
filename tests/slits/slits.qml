// Slits bench - an arrow slit fires across its room on the beats of its
// rhythm, glowing before each shot; an arrow hurts a knight in its line,
// a raised shield stops it, a perfect block sends it back and a dash
// passes through it; and every slit leaves a safe gap or lane (issue #125).
//
// Lands in the dojo's features scenario, where every room but the first
// holds two slits, and stills the enemies. Checks that the scenario shows
// its slits, each in the wall beside a slit feature's cell, firing across
// the room to a wall, with a rhythm of its band; that laying them out
// moved none of the other features; and that the two slits of a room take
// turns, never firing on the same beat. With an out dir and a window it
// saves glowing.png, a slit winding up beside the knight, and firing.png,
// its arrow just out. Then the knight stands in a slit's line, its back to
// it: the slit glows before the shot, its ring at least half closed on
// the last step before it, the arrow leaves on its beat and
// takes arrowDamageAt(depth) less the knight's defence. Facing it with
// the shield held, the next arrow is blocked: no damage, the shield's mana
// paid, the arrow gone. The shield raised just before the next one, a
// perfect block: no damage, the arrow flies back and breaks on its slit.
// Beside the line, the knight dashes across it as an arrow passes: the
// arrow passes through, no damage, and flies on to the wall. Last it
// builds the features scenario on 50 seeds across the danger bands and
// walks every slit itself: a lane - the room's doorways joined by cells
// on no slit's line and under no breakable - or a gap - a rest between
// two of its arrows longer than slitGapMargin times a knight takes to
// walk over the line. Prints one PASS or FAIL line per check and exits
// with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/slits/slits.qml
//   qml -I <build>/bin/qml tests/slits/slits.qml -- <out dir>

import QtQuick
import QtQuick.Window
import "../../src"

Window {
    id: bench
    width: 1280
    height: 800
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0
    property string outDir: {
        let args = Qt.application.arguments
        let i = args.indexOf("--")
        return i >= 0 && i + 1 < args.length ? args[i + 1] : ""
    }

    function check(ok, what) {
        console.log("[Slits]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Slits] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: bench.width, height: bench.height, muted: true,
                                                  recordStoreName: "ShapesAndStoneSlitsBench"})
        script.start()
    }

    readonly property int seeds: 50

    // The slit under test, the cell of its line the knight stands on, and
    // the way across its line the knight dashes from
    property var slit: null
    property var spot: null
    property var side: null
    // Every arrow of that slit: when it left (the trap clock), what it did
    // to the knight and where it went; and its slit's wind-up seen in the
    // slitWarn before each shot
    property var fired: ({})
    property var met: ({})
    property var ended: ({})
    property var lastMet: null
    property var lastEnded: null
    property real warnSeen: 0
    property bool flashSeen: false
    // Set to "perfect" or "dash": the knight raises its shield, or dashes
    // across the line, as the next arrow comes close
    property string answer: ""
    property var answered: null
    property var backTrail: null

    function mine(id) { return slit && id.indexOf(slit.cell + "#") === 0 }
    Connections {
        target: game
        function onArrowFired(id, cell, at) {
            if (!mine(id)) return
            fired[id] = { at: at, clock: game._trapClock, step: game.physics.timeStep, warn: warnSeen,
                          flash: false }
            warnSeen = 0
        }
        function onArrowMet(id, result) {
            if (!mine(id)) return
            met[id] = result
            lastMet = { id: id, result: result }
        }
        function onArrowEnded(id, where) {
            if (!mine(id)) return
            let a = game.arrows.find(x => x.arrowId === id)
            ended[id] = where
            lastEnded = { id: id, where: where }
        }
    }
    Connections {
        target: game ? game.physics : null
        function onStepped() {
            if (!slit) return
            warnSeen = Math.max(warnSeen, slit.warn)
            if (slit.flash) for (let id in fired) if (fired[id].clock > game._trapClock - 0.1) fired[id].flash = true
            for (let a of game.arrows) {
                if (!mine(a.arrowId)) continue
                if (a.back) backTrail = { id: a.arrowId, x: a.xWu, y: a.yWu }
                if (answer === "" || a.judged || a.back) continue
                // How far its head is from the knight's centre, along the line
                let c = centre(), d = (c.x - a.xWu) * a.dirX + (c.y - a.yWu) * a.dirY
                if (answer === "perfect" && d <= 1.3 && d > 0.5) {
                    answered = { id: a.arrowId, d: d }
                    answer = ""
                    p().raiseShield()
                } else if (answer === "dash" && d <= 0.9 && d > 0.5) {
                    // The knight is on the line two or three steps later,
                    // as the head reaches it
                    answered = { id: a.arrowId, d: d }
                    answer = ""
                    p().moveX = -side[0]
                    p().moveY = side[1]
                    p().dash()
                    p().moveX = 0
                    p().moveY = 0
                }
            }
        }
    }

    function p() { return game.player }
    function centre() { return { x: p().xWu + p().widthWu / 2, y: p().yWu - p().heightWu / 2 } }
    // The knight's centre on (x, y), standing
    function standAt(x, y) {
        p().xWu = x - p().widthWu / 2
        p().yWu = y + p().heightWu / 2
        p().moveX = 0
        p().moveY = 0
    }
    function fresh() {
        p().hp = p().maxHp
        p().graceLeft = 0
        p().mana = p().maxMana
        p().dashCooldown = 0
    }
    function halt() { for (let e of game.enemies) if (e && e.halt) e.halt() }
    function lines(list) { return list.map(f => [f.kind, f.gx, f.gy].join(":")) }
    function feature(s) { return game.features.find(f => f.kind === "slit" && f.gx + "," + f.gy === s.cell) }
    // The facing towards slit s from the knight, degrees, y up
    function towards(s) { return Math.atan2(-s.dirY, -s.dirX) * 180 / Math.PI }

    // The cells of a slit's line, walked here: from its cell away from
    // its wall until a wall
    function lineOf(f) {
        let g = game.grid, out = [], x = f.gx, y = f.gy
        while (g[y] && g[y][x] !== undefined && g[y][x] !== game.cellWall) {
            out.push(x + "," + y)
            x += f.dx
            y += f.dy
        }
        return out
    }
    function roomOf(gx, gy) {
        return game.rooms.findIndex(r => gx >= r.x && gx < r.x + r.w && gy >= r.y && gy < r.y + r.h)
    }
    // The beats slit f fires on in one turn of its rhythm
    function shots(f) {
        let n = f.beats.length, out = []
        for (let k = 0; k < n; k++) if (f.beats[((k + f.offset) % n + n) % n] === 1) out.push(k)
        return out
    }
    // The longest time between two of slit f's arrows passing a point of
    // its line with nothing in the way, s: its longest rest between two
    // shots less the time an arrow takes to pass a knight
    function gapOf(f) {
        let s = shots(f), n = f.beats.length, longest = 0, t = Balance.dungeon
        for (let i = 0; i < s.length; i++)
            longest = Math.max(longest, (i + 1 < s.length ? s[i + 1] : s[0] + n) - s[i])
        return longest * t.slitBeat - (t.arrowLength + p().heightWu) / t.arrowSpeed
    }
    // What a knight needs to walk over a line, with the table's margin
    function gapNeed() {
        return Balance.dungeon.slitGapMargin * (p().widthWu + game.arrowWidthWu) / Balance.knight.moveSpeed
    }
    // Whether room r's doorways are joined by cells on none of its slits'
    // lines and under no breakable
    function laneOf(r) {
        let room = game.rooms[r], g = game.grid, blocked = {}
        for (let f of game.features) {
            if (roomOf(f.gx, f.gy) !== r) continue
            if (f.kind === "slit") for (let c of lineOf(f)) blocked[c] = true
            if (Balance.dungeon.loot[f.kind]) blocked[f.gx + "," + f.gy] = true
        }
        let doors = []
        for (let gy = room.y; gy < room.y + room.h; gy++)
            for (let gx = room.x; gx < room.x + room.w; gx++)
                if ([[1, 0], [-1, 0], [0, 1], [0, -1]].some(n => g[gy + n[1]] && g[gy + n[1]][gx + n[0]] === game.cellHallway))
                    doors.push(gx + "," + gy)
        if (doors.length === 0 || doors.some(d => blocked[d])) return false
        let seen = {}, todo = [doors[0]]
        seen[doors[0]] = true
        while (todo.length) {
            let c = todo.pop().split(",").map(Number)
            for (let n of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
                let x = c[0] + n[0], y = c[1] + n[1], k = x + "," + y
                if (roomOf(x, y) !== r || seen[k] || blocked[k]) continue
                seen[k] = true
                todo.push(k)
            }
        }
        return doors.every(d => seen[d])
    }

    // A cell nothing stands on and no other slit's line crosses
    function clear(gx, gy, except) {
        let k = gx + "," + gy
        if (!game.grid[gy] || game.grid[gy][gx] !== game.cellRoom) return false
        if (game.features.some(f => f.gx + "," + f.gy === k)) return false
        return !game.features.some(f => f.kind === "slit" && f !== except && lineOf(f).indexOf(k) >= 0)
    }
    // A slit with room to answer it: the third cell of its line clear,
    // the cells either side of it clear, its line at least five cells
    function pickSlit() {
        for (let s of game.slits) {
            let f = feature(s), line = lineOf(f)
            if (line.length < 5) continue
            let c = line[2].split(",").map(Number)
            let perp = f.dx !== 0 ? [0, 1] : [1, 0]
            if (!clear(c[0], c[1], f) || !clear(c[0] + perp[0], c[1] + perp[1], f)
                    || !clear(c[0] - perp[0], c[1] - perp[1], f)) continue
            return { slit: s, spot: c, side: perp }
        }
        return null
    }
    function spotWu() {
        return { x: (spot[0] + 0.5) * game.cellSize, y: (spot[1] + 0.5) * game.cellSize }
    }
    function arrowsOf() { return game.arrows.filter(a => mine(a.arrowId)) }

    property real hpBefore: 0
    property real manaBefore: 0
    property string waitFor: ""

    property var steps: [
        [() => game.screen === "title", () => {
            let t = Balance.dungeon
            check(t.kinds.slit && t.slitRhythms.length > 0 && t.slitBeat > 0 && t.slitWarn > 0
                  && t.arrowSpeed > 0 && t.arrowDamage > 0 && t.arrowCap > 0 && t.arrowCap < 1,
                  "Balance.dungeon has slits at " + JSON.stringify(t.kinds.slit.perRoom) + " a room, "
                  + t.slitRhythms.length + " rhythms (" + t.slitRhythms.map(r => r.name).join(", ")
                  + ") on a " + t.slitBeat + " s beat, a " + t.slitWarn + " s wind-up, arrows at "
                  + t.arrowSpeed + " wu/s for " + t.arrowDamage + " (+" + t.arrowDamagePerDepth
                  + " a depth, cap " + t.arrowCap + ")")
            for (let b = 0; b < 3; b++) {
                let rs = t.slitRhythms.filter(r => r.bands.indexOf(b) >= 0)
                let gapped = rs.find(r => game.slitGap(r.beats) >= game.slitGapNeed())
                check(gapped !== undefined, "danger band " + b + " has " + rs.length + " rhythms, "
                      + (gapped ? "\"" + gapped.name + "\" with a gap of " + game.slitGap(gapped.beats).toFixed(2)
                                  + " s for a room without a lane" : "none with a gap"))
            }
            game.applyScenario("features")
        }],
        [500, () => {
            halt()
            let feats = game.features.filter(f => f.kind === "slit"), band = game.dangerBand(game.dangerPosition)
            check(game.slits.length > 0 && game.slits.length === feats.length && game.slits.every(s => s.visible),
                  "the features scenario shows " + game.slits.length + " slits for " + feats.length + " slit features")
            let bad = []
            for (let s of game.slits) {
                let f = feature(s), g = game.grid
                if (!f) { bad.push(s.cell + " has no feature"); continue }
                if (g[f.gy - f.dy][f.gx - f.dx] !== game.cellWall) bad.push(s.cell + " is not beside a wall")
                if (Math.abs(s.xWu - (f.xWu - f.dx * game.cellSize / 2)) > 1e-6
                        || Math.abs(s.yWu - (f.yWu - f.dy * game.cellSize / 2)) > 1e-6)
                    bad.push(s.cell + " is not on the wall's face")
                let line = lineOf(f)
                if (line.some(c => { let q = c.split(",").map(Number); return roomOf(q[0], q[1]) !== roomOf(f.gx, f.gy) }))
                    bad.push(s.cell + " fires out of its room")
                if (Math.abs(s.lineWu - line.length * game.cellSize) > 1e-6) bad.push(s.cell + " flies " + s.lineWu + " wu")
                let r = Balance.dungeon.slitRhythms.find(x => x.name === s.rhythm)
                if (!r || r.bands.indexOf(band) < 0) bad.push(s.cell + " has rhythm " + s.rhythm)
            }
            check(bad.length === 0, "each sits in the wall beside its cell, on its face, fires across its own room to "
                  + "a wall and has a rhythm of band " + band + (bad.length ? ": " + bad.join("; ") : ""))
            // Laid out last, the slits moved no other feature
            let ls = game.deriveSeed(game.masterSeed, game.levelIndex)
            let kinds = Object.assign({}, Balance.dungeon.kinds)
            delete kinds.slit
            let without = lines(game.planFeatures(ls, 0, true, kinds))
            let others = lines(game.features.filter(f => f.kind !== "slit"))
            check(JSON.stringify(without) === JSON.stringify(others),
                  "laying out the slits moved none of the " + others.length + " other features")
            // Two in a room take turns
            let pairs = 0, clash = []
            for (let r = 1; r < game.rooms.length; r++) {
                let two = feats.filter(f => roomOf(f.gx, f.gy) === r)
                if (two.length !== 2) continue
                pairs++
                let a = shots(two[0]), b = shots(two[1])
                if (two[0].rhythm !== two[1].rhythm || a.some(k => b.indexOf(k) >= 0))
                    clash.push("room " + r + ": " + two[0].rhythm + " " + a + " / " + two[1].rhythm + " " + b)
            }
            check(pairs > 0 && clash.length === 0, pairs + " rooms hold two slits, each pair on one rhythm, "
                  + "taking turns: never on the same beat" + (clash.length ? ": " + clash.join("; ") : ""))
            let pick = pickSlit()
            check(pick !== null, "a slit with a clear line to answer it" + (pick ? ": " + pick.slit.cell + ", "
                  + pick.slit.rhythm + ", firing " + [pick.slit.dirX, pick.slit.dirY] : ""))
            if (!pick) return
            slit = pick.slit
            spot = pick.spot
            side = pick.side
            if (outDir === "") return
            // Beside the slit, off its line, the camera on the knight
            game.fx = true
            let w = spotWu()
            standAt(w.x + side[0] * game.cellSize - slit.dirX * game.cellSize,
                    w.y + side[1] * game.cellSize - slit.dirY * game.cellSize)
            game.camera.target = null
            game.camera.target = p()
            waitFor = "glow"
        }],
        // The captures: the slit winding up, its arrow just out
        [() => outDir === "" || slit.warn > 0.75, () => {
            if (outDir === "") return
            bench.contentItem.grabToImage(r => {
                let ok = r.saveToFile(outDir + "/glowing.png")
                console.log("[Slits]", ok ? "saved" : "could not save", outDir + "/glowing.png")
            })
        }],
        [() => outDir === "" || arrowsOf().some(a => Math.abs(a.xWu - slit.xWu) + Math.abs(a.yWu - slit.yWu) > 1.6), () => {
            if (outDir === "") return
            bench.contentItem.grabToImage(r => {
                let ok = r.saveToFile(outDir + "/firing.png")
                console.log("[Slits]", ok ? "saved" : "could not save", outDir + "/firing.png")
            })
        }],
        // In its line, its back to it: hit
        [300, () => {
            fresh()
            let w = spotWu()
            standAt(w.x, w.y)
            p().facingAngle = towards(slit) + 180
            lastMet = null
            hpBefore = p().hp
        }],
        [() => lastMet !== null, () => {
            let f = fired[lastMet.id], took = hpBefore - p().hp
            let want = Math.max(Balance.minDamage, game.arrowDamageAt(game.depth, p().maxHp) - p().def)
            let beat = Balance.dungeon.slitBeat, k = Number(lastMet.id.split("#")[1])
            // On the first physics step at or after its beat; with a
            // window the steps follow its frames
            check(f && Math.abs(f.at - k * beat) < 1e-6 && f.clock - f.at >= 0 && f.clock - f.at <= f.step + 1e-6,
                  "the arrow " + lastMet.id + " leaves on its beat, " + (f ? f.at.toFixed(3) : "?") + " s, "
                  + (f ? ((f.clock - f.at) * 1000).toFixed(1) : "?") + " ms later on the physics clock, "
                  + "within its step of " + (f ? (f.step * 1000).toFixed(1) : "?") + " ms")
            // Seen on the steps before it: most of the way closed
            check(f && f.warn >= 0.5 && f.flash,
                  "the slit glows before it, its ring closing to " + (f ? f.warn.toFixed(2) : "?")
                  + " of the way, and flashes as it leaves (" + (f && f.flash) + ")")
            check(lastMet.result === "hit" && took === want,
                  "a knight standing in its line, its back to it, is hit: " + lastMet.result + ", " + took
                  + " taken, arrowDamageAt(depth " + game.depth + ") less its defence " + want)
        }],
        // Facing it, the shield held: blocked
        [700, () => {
            fresh()
            p().facingAngle = towards(slit)
            lastMet = null
            waitFor = "raise"
        }],
        [() => lastMet === null && Object.keys(fired).some(id => fired[id].clock > game._trapClock - 0.05), () => {
            // Just as an arrow leaves, long before it comes: no perfect block
            p().raiseShield()
            hpBefore = p().hp
            manaBefore = p().mana
        }],
        [() => lastMet !== null, () => {
            let gone = !arrowsOf().some(a => a.arrowId === lastMet.id)
            check(lastMet.result === "blocked" && p().hp === hpBefore && p().mana <= manaBefore - p().blockMana
                  && gone && ended[lastMet.id] === "knight",
                  "a raised shield facing it blocks it: " + lastMet.result + ", " + (hpBefore - p().hp)
                  + " taken, " + (manaBefore - p().mana).toFixed(1) + " mana spent (blockMana " + p().blockMana
                  + "), the arrow gone (" + ended[lastMet.id] + ")")
            p().lowerShield()
        }],
        // The shield raised just before it: a perfect block sends it back
        [500, () => {
            fresh()
            lastMet = null
            backTrail = null
            p().mana = p().maxMana / 2
            hpBefore = p().hp
            manaBefore = p().mana
            answer = "perfect"
        }],
        [() => lastMet !== null, () => {
            // The shield drains a little while it is up
            let back = Balance.knight.perfectBlockMana
            check(lastMet.result === "perfect" && p().hp === hpBefore && p().mana >= manaBefore + back - 0.5,
                  "raised " + (answered ? answered.d.toFixed(2) : "?") + " wu before the arrow, the shield blocks "
                  + "it perfectly: " + lastMet.result + ", " + (hpBefore - p().hp) + " taken, mana "
                  + manaBefore.toFixed(1) + " to " + p().mana.toFixed(1) + " (perfectBlockMana " + back + ")")
        }],
        [() => ended[lastMet.id] !== undefined, () => {
            let id = lastMet.id
            // Seen last on the step before it broke: within a step's flight
            let atSlit = backTrail && backTrail.id === id
                && Math.abs(backTrail.x - slit.xWu) + Math.abs(backTrail.y - slit.yWu)
                   <= Balance.dungeon.arrowSpeed * game.physics.timeStep + 1e-6
            check(ended[id] === "slit" && atSlit,
                  "it flies back along its line and breaks on its slit (" + ended[id] + ", last at "
                  + (backTrail ? backTrail.x.toFixed(2) + "," + backTrail.y.toFixed(2) : "?") + ", the slit at "
                  + slit.xWu.toFixed(2) + "," + slit.yWu.toFixed(2) + ")")
            p().lowerShield()
        }],
        // Beside the line, a dash across it as an arrow passes
        [600, () => {
            fresh()
            let w = spotWu()
            standAt(w.x + side[0] * 1.5, w.y + side[1] * 1.5)
            lastMet = null
            answered = null
            hpBefore = p().hp
            answer = "dash"
        }],
        [() => answered && ended[answered.id] !== undefined, () => {
            let c = centre(), w = spotWu()
            let across = (c.x - w.x) * side[0] + (c.y - w.y) * side[1] < -0.6
            let id = answered ? answered.id : "?"
            check(lastMet !== null && lastMet.id === id && lastMet.result === "dodged" && p().hp === hpBefore
                  && across,
                  "a dash across its line as the arrow " + id + " passes goes through it: "
                  + (lastMet ? lastMet.result : "not met") + ", " + (hpBefore - p().hp) + " taken, "
                  + (across ? "across the line" : "not across"))
            check(ended[answered.id] === "wall", "the arrow flies on to the wall facing its slit ("
                  + ended[answered.id] + ")")
            slit = null
        }],
    ].concat(seedSteps()).concat([
        [100, () => {
            check(walked.slits > 0 && walked.unsafe.length === 0,
                  seeds + " seeds lay " + walked.slits + " slits in " + walked.rooms + " rooms, each with a safe way "
                  + "past: " + walked.lanes + " in rooms with a lane, " + walked.gaps + " with a gap of "
                  + gapNeed().toFixed(2) + " s or more (" + Object.keys(walked.rhythms).map(k => k + " "
                  + walked.rhythms[k]).join(", ") + ")" + (walked.unsafe.length ? "; none: "
                  + walked.unsafe.length + ", e.g. " + walked.unsafe.slice(0, 3).join("; ") : ""))
            check(walked.forced > 0, walked.forced + " rooms without a lane would have drawn a rhythm "
                  + "with no gap: the generator gave them one with a gap")
            console.log("[Slits] done,", failures, "failed")
        }],
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
    ])

    // Every slit of the features scenario on 50 seeds, at dangers across
    // the bands, walked here: a lane in its room or a gap in its rhythm
    property var walked: ({ slits: 0, rooms: 0, lanes: 0, gaps: 0, forced: 0, unsafe: [], rhythms: {} })
    function seedSteps() {
        let out = []
        for (let i = 0; i < seeds; i++) {
            out.push([60, () => {
                let seed = 2000 + i * 6007, dg = (i % 10) * 0.55
                game.applyScenario("features", dg, seed)
                let band = game.dangerBand(game.dangerPosition)
                let byRoom = {}
                for (let f of game.features.filter(f => f.kind === "slit")) {
                    let r = roomOf(f.gx, f.gy)
                    byRoom[r] = (byRoom[r] || []).concat([f])
                }
                let rs = Balance.dungeon.slitRhythms.filter(x => x.bands.indexOf(band) >= 0)
                for (let r in byRoom) {
                    walked.rooms++
                    let lane = laneOf(Number(r))
                    for (let f of byRoom[r]) {
                        walked.slits++
                        walked.rhythms[f.rhythm] = (walked.rhythms[f.rhythm] || 0) + 1
                        let gap = gapOf(f)
                        if (lane) walked.lanes++
                        else if (gap >= gapNeed()) walked.gaps++
                        else walked.unsafe.push("seed " + seed + " " + f.gx + "," + f.gy + " " + f.rhythm
                                                + " gap " + gap.toFixed(2) + " s, no lane")
                    }
                    // The rhythm the room drew, before the generator's check
                    let rand = game.createRng(game.deriveSeed(seed, game.levelIndex) ^ 0x1f83d9ab
                                              ^ (byRoom[r][0].gy * game.gridWidth + byRoom[r][0].gx))
                    let drawn = rs[Math.floor(rand() * rs.length)]
                    if (!lane && game.slitGap(drawn.beats) < game.slitGapNeed()) walked.forced++
                }
            }])
        }
        return out
    }

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
                if (waitedMs > 60000) {
                    console.log("[Slits] FAIL step", i, "timed out")
                    Qt.exit(failures + 1)
                    stop()
                }
                return
            }
            waitedMs = 0
            i++
            if (i >= bench.steps.length) stop()
            try {
                step[1]()
            } catch (err) {
                console.log("[Slits] FAIL step", i - 1, "threw:", err)
                Qt.exit(failures + 1)
                stop()
            }
        }
    }
}
