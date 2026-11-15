// Boss bench - every third dungeon ends in a boss room: the Hollow Warden
// (issue #274, Balance.boss).
//
// Builds the dungeons of depths 0 to 8 on one seed and checks that exactly
// those at 2, 5 and 8 end in a boss room: the room the exit stairs' shaft
// leaves from, with a gate in the shaft and one in every way in, no other
// enemy, feature or wooden door in it, and the Warden asleep in it, its HP
// and tempo rising per appearance as the table has them. Then, in the
// dungeon at depth 2, the bench steps the world one physics step at a time:
// the knight walks into the room, which shuts - the ways in and the shaft -,
// the Warden wakes, its banner and HP bar show and its song plays part one.
// At Balance.boss.phaseAt of its HP its phase 2 begins: its adds come, it
// plays phase2Tempo times faster, the light turns and the song plays part
// two; a zone opens under the knight, warns, and hurts it through a raised
// shield, and one it steps out of does not; at waveAt the second wave comes.
// Beaten, it drops its gold, the gates open, the victory banner shows and
// the knight is whole again.
//
// It speaks (issue #323): as the room shuts the Warden says its
// appearance's line, played and shown on that same step, with the Warden
// awake on it - the line holds up nothing -, and as it falls another. Its
// lines differ per appearance, the last pair is said at every one past
// them, their words are the voice script's and short enough to read
// under the banner, and its stone shows a crack per defeat before. Prints
// one PASS or FAIL line per check and exits with the number of failures.
//
//   QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/boss/boss.qml

import QtQuick
import QtQuick.Window
import Clayground.Common
import "../../src"

Window {
    id: bench
    width: 900
    height: 600
    visible: true
    color: "#1a1a2e"

    property var game: null
    property int failures: 0
    readonly property int seed: 424242

    function check(ok, what) {
        console.log("[Boss]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Boss] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 900, height: 600, muted: true})
        script.start()
    }

    Timer {
        id: script
        interval: 50
        repeat: true
        onTriggered: {
            if (!game || game.screen !== "title") return
            stop()
            try {
                run()
            } catch (err) {
                check(false, "the bench ran to its end: " + err + "\n" + err.stack)
            }
            game.destroy()
            Qt.exit(failures)
        }
    }

    function alive(e) { return !!e && e.destroyed === false }
    function warden() { return game.enemies.find(e => alive(e) && e.boss) || null }
    function fight() { return game.bossFight }
    function r1(v) { return Math.round(v * 10) / 10 }
    function centre(e) { return {x: e.xWu + e.widthWu / 2, y: e.yWu - e.heightWu / 2} }
    function inRoom(r, x, y) {
        let cs = game.cellSize
        return x >= r.x * cs && x <= (r.x + r.w) * cs && y >= r.y * cs && y <= (r.y + r.h) * cs
    }
    function cellIn(r, gx, gy) { return gx >= r.x && gx < r.x + r.w && gy >= r.y && gy < r.y + r.h }

    // The fight first: a game that has built many dungeons steps slower
    // with each, and the depths are only built, not stepped
    function run() {
        Clayground.paused = true
        checkFight()
        checkDepths()
        checkLines()
    }

    // ---- its lines (issue #323) ----
    function readSound(path) {
        let xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../sound/" + path), false)
        xhr.send()
        try { return JSON.parse(xhr.responseText) } catch (e) { return null }
    }
    function checkLines() {
        let b = Balance.boss, pairs = b.lines
        let script = readSound("voice/warden.voice.json")
        let sheet = readSound("cues.json")
        if (!script || !sheet) {
            check(false, "the Warden's voice script and the cue sheet read (QML_XHR_ALLOW_FILE_READ=1?)")
            return
        }
        let byId = {}
        for (let l of script.lines) byId[l.id] = l
        let all = []
        for (let pr of pairs) all.push(pr.gates, pr.fall)
        let texts = all.map(l => l.text)
        check(pairs.length >= 4 && new Set(texts).size === texts.length,
              pairs.length + " pairs of lines, " + texts.length + " lines, no two the same")
        let wrong = all.filter(l => !byId[l.id] || byId[l.id].text !== l.text || byId[l.id].voice !== "warden_hollow")
        check(wrong.length === 0 && script.lines.length === all.length,
              "every line's words are its line's in sound/voice/warden.voice.json, in the Warden's voice"
              + (wrong.length ? " - not " + wrong.map(l => l.id).join(", ") : ""))
        let open = all.filter(l => {
            let c = sheet.cues["voice/warden/" + l.id]
            return c && c.category === "voice" && c.mode === "rendered" && c.verdict === null
                && c.source === "voice/warden.voice.json" && c.render === "voice/warden/" + l.id + ".wav"
        })
        check(open.length === all.length, open.length + " of " + all.length
              + " lines are voice cues of the sound factory with an open verdict")
        let longest = 0, words = 0
        for (let l of all) {
            let c = sheet.cues["voice/warden/" + l.id], r = c ? readSound(c.report) : null
            longest = Math.max(longest, r ? r.duration_s : 99)
            words = Math.max(words, l.text.split(/\s+/).length)
        }
        check(words <= 8 && longest <= b.lineShow,
              "each is short: at most " + words + " words, its render at most " + longest
              + " s, shown for " + b.lineShow + " s")
        let n1 = game.wardenLine(0, "gates").id, n2 = game.wardenLine(1, "gates").id
        let n3 = game.wardenLine(2, "gates").id, n4 = game.wardenLine(3, "gates").id
        let later = [3, 4, 7, 20].every(n => game.wardenLine(n, "gates") === pairs[pairs.length - 1].gates
                                         && game.wardenLine(n, "fall") === pairs[pairs.length - 1].fall)
        check(new Set([n1, n2, n3, n4]).size === 4 && later,
              "its first, second and third appearance say their own lines (" + [n1, n2, n3].join(", ")
              + "), every later one " + n4 + " and " + game.wardenLine(3, "fall").id)
        console.log("[Boss] its story:", pairs.map(pr => pr.gates.text + " / " + pr.fall.text).join(" // "))
    }

    // ---- the boss rooms of depths 0 to 8 ----
    function checkDepths() {
        let found = [], rows = []
        for (let d = 0; d <= 8; d++) {
            game.applyScenario("dungeon", d, seed)
            let f = fight(), w = warden(), r = game.bossRoom
            let boss = f.stage === "waiting" && r !== null && w !== null
            if (boss) found.push(d)
            if (game.isBossDepth(d) !== boss) {
                check(false, "depth " + d + ": a boss room " + (game.isBossDepth(d) ? "wanted" : "not wanted")
                      + " (stage \"" + f.stage + "\", room " + JSON.stringify(r) + ", Warden " + (w !== null) + ")")
                continue
            }
            if (!boss) continue
            let n = game.bossAppearance(d)
            let last = game.rooms[game.rooms.length - 1]
            let shaft = game.grid[r.y + r.h] && game.grid[r.y + r.h][game.exitGridX] === game.cellHallway
            let exitGate = f.gates.find(g => g.exit)
            let ways = f.gates.filter(g => !g.exit)
            check(r === last && game.exitGridX >= r.x && game.exitGridX < r.x + r.w && shaft
                  && exitGate && exitGate.cell === game.exitGridX + "," + (r.y + r.h) && exitGate.shut
                  && ways.length > 0 && ways.every(g => !g.shut),
                  "depth " + d + ": the boss room is the last room, the exit stairs' shaft leaves from it at x "
                  + game.exitGridX + " and its gate is shut; " + ways.length + " ways in stand open")
            let c = centre(w)
            let others = game.enemies.filter(e => alive(e) && !e.boss && inRoom(r, centre(e).x, centre(e).y))
            let things = game.features ? game.features.filter(x => cellIn(r, x.gx, x.gy)) : []
            let doors = game.doors.filter(x => [[1, 0], [-1, 0], [0, 1], [0, -1]].some(
                q => cellIn(r, parseInt(x.cell.split(",")[0]) + q[0], parseInt(x.cell.split(",")[1]) + q[1])))
            check(inRoom(r, c.x, c.y) && w.dormant && others.length === 0 && doors.length === 0,
                  "depth " + d + ": the Warden sleeps in it alone (" + others.length + " other enemies, "
                  + doors.length + " wooden doors at it)")
            let hp = game.wardenHp(n, 1, game.danger), tempo = game.wardenTempo(n)
            let b = Balance.boss
            check(w.maxHp === hp && w.hp === hp && Math.abs(w.tempo - tempo) < 1e-9
                  && Math.abs(w.beatLen - b.beat / tempo) < 1e-9
                  && Math.abs(hp - Math.round(b.hp * (1 + n * b.hpGrow) * (1 + Math.min(game.danger, b.depthUpTo) * Balance.depth.hp))) <= 0,
                  "depth " + d + ": appearance " + n + ", HP " + w.maxHp + " (table " + hp + "), tempo "
                  + r1(w.tempo * 100) / 100 + " (table " + tempo + "), a beat of " + r1(w.beatLen * 100) / 100 + " s")
            check(w.cracks === n && f.appearance === n,
                  "depth " + d + ": its stone shows " + w.cracks + " cracks, one per defeat before")
            rows.push({d: d, hp: w.maxHp, tempo: w.tempo})
        }
        check(JSON.stringify(found) === JSON.stringify([2, 5, 8]),
              "boss rooms at exactly depths " + found.join(", ") + " of 0-8")
        check(rows.length === 3 && rows[1].hp > rows[0].hp && rows[2].hp > rows[1].hp
              && rows[1].tempo > rows[0].tempo && rows[2].tempo > rows[1].tempo,
              "its HP and tempo rise: " + rows.map(x => "depth " + x.d + " " + x.hp + " HP at "
                                                     + r1(x.tempo * 100) / 100).join(", "))
    }

    // ---- the fight at depth 2 ----
    function stepN(n) { for (let i = 0; i < n; i++) Clayground.physicsStep(1) }
    function steps(seconds) { return Math.round(seconds * 60) }
    // The knight walks to (x, y), its centre, at most maxSteps steps
    function walkTo(x, y, maxSteps) {
        let p = game.player
        for (let i = 0; i < maxSteps; i++) {
            let dx = x - (p.xWu + 0.5), dy = y - (p.yWu - 0.5)
            let len = Math.sqrt(dx * dx + dy * dy)
            if (len < 0.2) break
            p.moveX = dx / len
            p.moveY = -dy / len
            Clayground.physicsStep(1)
        }
        p.moveX = 0
        p.moveY = 0
    }
    function keep(p) {
        p.hp = p.maxHp
        p.graceLeft = 0
    }

    function checkFight() {
        game.applyScenario("bossroom", 2, seed)
        let f = fight(), w = warden(), p = game.player, r = game.bossRoom
        if (!w || !p || !r || f.stage !== "waiting") {
            check(false, "the boss room at depth 2 stands with the knight at its door (stage \""
                  + f.stage + "\")")
            return
        }
        // No other enemy in the way: the dungeon's stand where they are
        for (let e of game.enemies.filter(alive)) if (!e.boss) e.halt()
        let cs = game.cellSize
        let mid = {x: (r.x + r.w / 2) * cs, y: (r.y + r.h / 2) * cs}
        let g = f.gates.find(x => !x.exit)
        let start = {x: p.xWu + 0.5, y: p.yWu - 0.5}
        check(!f.inside(start.x, start.y) && !g.shut,
              "the knight stands outside the room, its way in open (" + g.cell + ")")
        // Asleep it takes no blow: not one, not a killing one, and the
        // room stays open, its exit shut
        let hpAsleep = w.hp
        w.takeDamage(2100, p.xWu, p.yWu, false)
        stepN(2)
        let hpStruck = w.hp
        w.takeDamage(1000000, p.xWu, p.yWu, true)
        stepN(2)
        check(hpStruck === hpAsleep && w.hp === hpAsleep && alive(w) && w.dormant && f.stage === "waiting"
              && !g.shut && f.gates.find(x => x.exit).shut && f.addsCalled === 0,
              "asleep, the Warden takes neither a blow nor a killing one (HP " + hpAsleep + " to " + hpStruck
              + " to " + w.hp + "), the room stays open (stage \"" + f.stage + "\"), its exit shut")
        // On the gate's line the Warden still sleeps; two cells on, in the
        // room, it wakes
        let nx = Math.sign(g.cxWu - start.x), ny = Math.sign(g.cyWu - start.y)
        if (g.across) ny = 0; else nx = 0
        let into = {x: g.cxWu + nx * 1.5 * cs, y: g.cyWu + ny * 1.5 * cs}
        walkTo(g.cxWu, g.cyWu, 600)
        stepN(2)
        check(f.stage === "waiting" && w.dormant, "in the doorway the room is still open, the Warden asleep")
        game.logSounds = true
        game.soundLog = []
        let shut = null
        let onBegan = () => { shut = {t: Math.round(game.physicsSeconds * 1000) / 1000, awake: !w.dormant,
                                      said: f.said.slice()} }
        f.began.connect(onBegan)
        walkTo(into.x, into.y, 600)
        stepN(2)
        f.began.disconnect(onBegan)
        let gatesLine = game.wardenLine(0, "gates")
        let heard = game.soundLog.filter(x => x.cue.indexOf("voice/warden/") === 0)
        check(shut !== null && shut.awake && JSON.stringify(shut.said) === JSON.stringify([gatesLine.id])
              && heard.length === 1 && heard[0].cue === "voice/warden/" + gatesLine.id && heard[0].t === shut.t,
              "as the room shuts the Warden says \"" + gatesLine.text + "\" (" + (heard.length ? heard[0].cue : "none")
              + " at " + (heard.length ? heard[0].t : "-") + " s), awake on that same step ("
              + (shut ? shut.t : "-") + " s): the line holds up nothing")
        let shutAll = f.gates.every(x => x.shut)
        check(f.stage === "fight" && shutAll && !w.dormant,
              "a few steps in the room shuts: " + f.gates.filter(x => x.shut).length + " of "
              + f.gates.length + " gates shut, the Warden awake (stage \"" + f.stage + "\")")
        stepN(steps(0.6))
        let banner = f.children.find(x => x.objectName === "bossBanner")
        let barItem = f.children.find(x => x.objectName === "bossBar")
        check(banner && banner.opacity > 0.5 && banner.text === Balance.boss.name.toUpperCase()
              && barItem && barItem.visible,
              "its name shows as a banner (\"" + (banner ? banner.text : "") + "\") and its HP as a bar")
        let caption = f.children.find(x => x.objectName === "bossLine")
        check(caption && caption.opacity > 0.5 && caption.text.indexOf(gatesLine.text) >= 0
              && caption.y > barItem.y - caption.height - 20 && caption.y + caption.height <= barItem.y,
              "its words show as a subtitle above its HP bar: " + (caption ? caption.text : ""))
        check(game.bossSong && game.bossSongPlayer().state === "one" && game.bossSongPlayer().wanted
              && !game.dungeonMusicWanted(),
              "its song plays part one in place of the dungeon's (" + game.bossSongPlayer().state + ")")
        // Walking back out: the gate holds
        let before = {x: p.xWu, y: p.yWu}
        walkTo(g.cxWu, g.cyWu, steps(1.5))
        check(f.inside(p.xWu + 0.5, p.yWu - 0.5, 0), "the shut gate holds the knight in the room")

        // ---- phase 2 ----
        w.halt()
        w.halted = false
        let foesBefore = game.enemies.filter(alive).length
        let b = Balance.boss
        w.hp = Math.floor(w.maxHp * b.phaseAt) + 5
        w.takeDamage(1000, p.xWu, p.yWu, false)
        stepN(2)
        let adds = game.enemies.filter(e => alive(e) && !e.boss && e.tier === 0
                                       && f.inside(centre(e).x, centre(e).y, 0))
        check(w.phase === 2 && f.phase === 2 && adds.length === b.adds,
              "at " + b.phaseAt * 100 + " % HP its phase 2 begins: " + adds.length + " weak grunts come ("
              + b.adds + " by the table)")
        check(Math.abs(w.beatLen - b.beat / (w.tempo * b.phase2Tempo)) < 1e-9 && game.bossLit
              && game.bossSongPlayer().state === "two",
              "it plays " + b.phase2Tempo + " times faster (a beat of " + r1(w.beatLen * 100) / 100
              + " s), the light turns and the song plays part two")
        let core = null
        for (let it of [w].concat(game.glowParent().children))
            if (it.objectName === "wardenCore") core = it
        for (let i = 0; i < w.children.length && !core; i++)
            if (w.children[i].objectName === "wardenCore") core = w.children[i]
        check(core !== null, "its core shows")
        for (let e of adds) e.halt()
        w.halt()

        // A zone under the knight, its shield up: it hurts
        p.isBlocking = true
        let opened = f.zonesOpened, n = 0
        while (f.zonesOpened === opened && n < steps(b.zone.every * 2)) { keep(p); stepN(1); n++ }
        let z = f.zones.length > 0 ? f.zones[f.zones.length - 1] : null
        check(z !== null && Math.hypot(z.x - (p.xWu + 0.5), z.y - (p.yWu - 0.5)) < 0.1,
              "a zone opens under the knight " + r1(n / 60) + " s into phase 2")
        let warned = 0, hp0 = p.maxHp, hits = f.zoneHits
        p.hp = hp0
        p.graceLeft = 0
        let item = null
        // Up to the step before it hurts
        while (z && f.now() + 1.5 / 60 < z.at) {
            stepN(1)
            p.graceLeft = 0
            for (let it of game.room.children) if (it.zoneId === z.id) item = it
            if (item && item.warn > warned) warned = item.warn
        }
        let hpWarned = p.hp
        stepN(3)
        check(warned > 0.9 && hpWarned === hp0 && f.zoneHits === hits + 1 && p.hp === hp0 - f.zoneDamage(),
              "its ring closes over " + b.zone.warn + " s (" + Math.round(warned * 100) + " % a step before, HP "
              + hpWarned + "), then it hurts "
              + f.zoneDamage() + " through the raised shield (HP " + hp0 + " to " + p.hp + ")")
        p.isBlocking = false
        // The next one: the knight steps out of it while it warns
        opened = f.zonesOpened
        n = 0
        while (f.zonesOpened === opened && n < steps(b.zone.every * 2)) { keep(p); stepN(1); n++ }
        z = f.zones.length > 0 ? f.zones[f.zones.length - 1] : null
        hits = f.zoneHits
        p.hp = p.maxHp
        let away = {x: (z ? z.x : 0) + (z && z.x < mid.x ? 1 : -1) * (b.zone.radius + 1.2), y: z ? z.y : 0}
        walkTo(away.x, away.y, steps(b.zone.warn * 0.9))
        stepN(steps(b.zone.warn) + 2)
        check(z !== null && f.zoneHits === hits && p.hp === p.maxHp,
              "a zone the knight stepped out of while it warned does not hurt it")

        // The second wave
        foesBefore = game.enemies.filter(e => alive(e) && !e.boss).length
        w.hp = Math.floor(w.maxHp * b.waveAt) + 5
        w.takeDamage(1000, p.xWu, p.yWu, false)
        stepN(2)
        let more = game.enemies.filter(e => alive(e) && !e.boss).length - foesBefore
        check(more === b.adds && f.addsCalled === 2 * b.adds,
              "at " + b.waveAt * 100 + " % HP the second wave: " + more + " more grunts")

        // ---- beaten ----
        p.hp = 10
        p.mana = 0
        let goldBefore = game.goldDrops.length
        let fellAt = Math.round(game.physicsSeconds * 1000) / 1000
        game.soundLog = []
        w.takeDamage(100000, p.xWu, p.yWu, false)
        stepN(2)
        let fallLine = game.wardenLine(0, "fall")
        let fallHeard = game.soundLog.filter(x => x.cue.indexOf("voice/warden/") === 0)
        check(JSON.stringify(f.said) === JSON.stringify([gatesLine.id, fallLine.id]) && fallHeard.length === 1
              && fallHeard[0].cue === "voice/warden/" + fallLine.id && fallHeard[0].t - fellAt <= 2 / 60 + 1e-6,
              "as it falls it says \"" + fallLine.text + "\" (" + (fallHeard.length ? fallHeard[0].cue : "none") + ")")
        let drops = game.goldDrops.length - goldBefore
        let total = game.goldDrops.slice(goldBefore).reduce((t, x) => t + x.amount, 0)
        let want = b.gold + b.goldGrow * game.bossAppearance(2)
        check(!alive(warden()) && f.stage === "beaten" && f.gates.every(x => !x.shut),
              "it falls: every gate opens, the exit's too")
        check(drops === b.drops && Math.abs(total - want) <= b.drops,
              "it drops a large pile of gold: " + drops + " piles, " + total + " gold (" + want + " by the table)")
        stepN(steps(0.6))
        let victory = f.children.find(x => x.objectName === "victoryBanner")
        check(victory && victory.opacity > 0.5 && !barItem.visible,
              "the victory banner shows (\"" + (victory ? victory.text : "") + "\"), the HP bar is gone")
        check(caption.opacity > 0.5 && caption.text.indexOf(fallLine.text) >= 0,
              "its last words show under it: " + caption.text)
        game.logSounds = false
        check(p.hp === p.maxHp && p.mana === p.maxMana,
              "the knight is healed to full HP and mana (" + p.hp + "/" + p.maxHp + ", " + Math.round(p.mana)
              + "/" + p.maxMana + ")")
        check(!game.bossSong && game.dungeonMusicWanted(), "the dungeon's song plays again")
    }
}
