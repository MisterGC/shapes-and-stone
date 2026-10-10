// Settings bench - the Music and Sound volumes of the Esc menu, the coin's
// clink, the knight panel on C and the vials at the knight's belt.
//
// In the Esc menu S steps to Music and A turns it down a tenth: every music
// track plays at its own volume times 0.9, and the value is kept with the
// record. S to Sound and A twice: every sound at its own times 0.8, kept
// too, and D gives a tenth back. Gold picked up plays the coin sound. C
// opens the knight panel: a harness bought from the smith shows with what
// its level gives, the potions with their count; C closes it, and Esc
// closes it before it would open the menu. Bought potions and draughts
// hang at the knight's belt with their counts. A knight that does not move
// makes no footstep; walking two beats of Balance.steps plays two. A strike's damage shows as a number in normal
// play, the knight's own hurt does not; an enemy's eyes are drawn with its
// body, under the darkness. A swing breaks a heap of bones in its arc, a
// whirlwind every heap within its reach. A right-click right after a swing
// bashes: the enemy in front is shoved back for Balance.bash.mana, once a
// swing, and not after the window. Prints one PASS or FAIL
// line per check and exits with the number of failures.
//
//   QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/settings/settings.qml

import QtQuick
import QtQuick.Window
import QtTest
import Clayground.Storage
import "../../src"

Window {
    id: bench
    width: 1000
    height: 600
    visible: true
    color: "#1a1a2e"

    readonly property string storeName: "ShapesAndStoneSettingsBench"
    property var game: null
    property int failures: 0
    property var bashFoe: null
    property real bashFrom: 0
    property real lungeFrom: 0
    property int bashSwing: 0

    function check(ok, what) {
        console.log("[Settings]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }
    function near(a, b) { return Math.abs(a - b) < 0.001 }

    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    // What the game kept, read back the way the next start reads it
    KeyValueStore { id: kept; name: bench.storeName }

    Component.onCompleted: {
        let c = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (c.status !== Component.Ready) {
            console.log("[Settings] FAIL", c.errorString())
            Qt.exit(1)
            return
        }
        game = c.createObject(bench.contentItem, {width: 1000, height: 600, recordStoreName: storeName})
        script.start()
    }

    // Every Music and Sound in the item tree under `root`, by file name
    function tracks(root, out) {
        out = out || {}
        let src = root.source !== undefined ? String(root.source) : ""
        if (src.endsWith(".mp3") || src.endsWith(".wav"))
            out[src.substring(src.lastIndexOf("/") + 1)] = root
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) tracks(kids[i], out)
        return out
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
    function shown(name) {
        let f = find(game, name)
        return f && f.visible ? f : null
    }
    function countNamed(root, name) {
        let n = root.objectName === name ? 1 : 0
        let kids = root.data || []
        for (let i = 0; i < kids.length; i++) n += countNamed(kids[i], name)
        return n
    }
    function textsUnder(item, out) {
        out = out || []
        if (item.text !== undefined && item.visible) out.push(String(item.text))
        let kids = item.data || []
        for (let i = 0; i < kids.length; i++) textsUnder(kids[i], out)
        return out
    }

    property var steps: [
        [() => game.screen === "title", () => {
            // A clean start, whatever an earlier run of the bench kept
            game.setVolume("music", 1)
            game.setVolume("sound", 1)
            game.muted = false
            game.screen = "game"
            game.forceActiveFocus()
        }],
        [() => game.player !== null && tracks(game)["dungeon_music.mp3"].playing, () => {
            press(Qt.Key_Escape)
        }],
        [() => shown("pauseMenu") !== null && shown("pauseMenu").activeFocus, () => {
            let m = shown("pauseMenu")
            check(m.choices.join(",") === "Resume,Music,Sound,Title", "the menu has Resume, Music, Sound, Title")
            check(find(m, "pauseVolumeMusic").text === "100%", "Music shows 100%")
            press(Qt.Key_S)
            press(Qt.Key_A)
        }],
        [100, () => {
            let t = tracks(game)
            check(near(game.musicVolume, 0.9), "S then A turns the music to 90%")
            check(find(shown("pauseMenu"), "pauseVolumeMusic").text === "90%", "the row shows 90%")
            check(near(t["village_music.mp3"].volume, 0.35 * 0.9) && near(t["dungeon_music.mp3"].volume, 0.3 * 0.9)
                  && near(t["village_ambience.mp3"].volume, 0.4 * 0.9),
                  "the music and the ambience play at their own volume times 0.9")
            check(near(t["punch_hitting.wav"].volume, 0.7), "the sounds keep their volume")
            check(kept.get("musicVolume", "") === "0.9", "the music volume is kept (" + kept.get("musicVolume", "") + ")")
            press(Qt.Key_S)
            press(Qt.Key_A)
            press(Qt.Key_A)
        }],
        [100, () => {
            let t = tracks(game)
            check(near(game.soundVolume, 0.8), "S then A twice turns the sound to 80%")
            check(near(t["punch_hitting.wav"].volume, 0.7 * 0.8) && near(t["coin_pickup.wav"].volume, 0.5 * 0.8),
                  "the sounds play at their own volume times 0.8")
            check(near(t["village_music.mp3"].volume, 0.35 * 0.9), "the music stays at 90%")
            check(kept.get("soundVolume", "") === "0.8", "the sound volume is kept")
            press(Qt.Key_D)
        }],
        [100, () => {
            check(near(game.soundVolume, 0.9), "D gives a tenth back")
            press(Qt.Key_W)
            press(Qt.Key_W)
            press(Qt.Key_Return)
        }],
        [() => shown("pauseMenu") === null && game.activeFocus, () => {
            check(true, "W twice and Enter resume")
            game._collectGold(5, game.player.xWu, game.player.yWu)
        }],
        [() => tracks(game)["coin_pickup.wav"].playing, () => {
            check(true, "gold picked up plays the coin sound")
            let p = game.player
            p.gold = 200
            check(game.buyWare({id: "harness"}), "the smith sells a harness")
            game.buyWare({id: "potion"})
            game.buyWare({id: "potion"})
            game.buyWare({id: "draught"})
            game.forceActiveFocus()
            press(Qt.Key_C)
        }],
        [100, () => {
            let panel = shown("knightPanel")
            check(panel !== null, "C opens the knight panel")
            let texts = panel ? textsUnder(panel).join("|") : ""
            check(texts.indexOf("Lighter harness I") >= 0 && texts.indexOf(game.smithGives("harness", 1)) >= 0,
                  "the panel shows the harness bought and what it gives")
            check(texts.indexOf("Sharpened sword - none yet") >= 0, "an upgrade not bought shows as none yet")
            check(find(panel, "knightPotions").value.indexOf("2") === 0, "the panel shows 2 potions")
            let belt = shown("knightBelt")
            check(belt !== null, "the knight has vials at its belt")
            let counts = belt ? textsUnder(belt) : []
            check(counts.join(",") === "2,1", "the belt shows 2 potions and 1 draught (" + counts.join(",") + ")")
            check(game.gamePaused === false, "the panel pauses nothing")
            press(Qt.Key_C)
        }],
        [100, () => {
            check(shown("knightPanel") === null, "C closes the knight panel")
            press(Qt.Key_C)
            press(Qt.Key_Escape)
        }],
        [100, () => {
            check(shown("knightPanel") === null && shown("pauseMenu") === null,
                  "Esc closes the panel and does not open the menu")
            game.player.potions = 0
            game.player.draughts = 0
        }],
        [100, () => {
            check(shown("knightBelt") === null, "an empty belt shows no vials")
            // Footsteps: held where it is, a knight makes none; walking, the
            // first comes half a beat in
            let p = game.player, dt = 1 / 60, beat = 1 / Balance.steps.perSecond
            let played = 0
            // A stand-in counts the steps; the knight's view reads only these
            p.gameWorld = {fx: game.fx, levelType: game.levelType, playStep: () => played++}
            p._countSteps(dt)
            for (let i = 0; i < 120; i++) p._countSteps(dt)
            check(played === 0, "a knight that does not move makes no step (" + played + ")")
            let n = Math.round(2 * beat / dt)
            for (let i = 0; i < n; i++) {
                p.xWu += p.maxSpeed * dt
                p._countSteps(dt)
            }
            check(played === 2, "walking two beats plays " + played + " steps, 2 wanted")
            p.gameWorld = game
            game.playStep()
        }],
        [() => tracks(game)["footstep.wav"].playing, () => {
            check(true, "a footstep is heard")
            // Strike numbers show in normal play, the knight's own hurt not
            game.debugMechanics = false
            let before = countNamed(game, "damageNumber")
            game.spawnHurtNumber(game.player.xWu, game.player.yWu, 7, "#FF4444")
            check(countNamed(game, "damageNumber") === before, "the knight's own hurt shows no number")
            let e = game.enemies.find(x => !x.destroyed)
            game.spawnDamageNumber(e.xWu, e.yWu, 12, "#FFD700")
            check(countNamed(game, "damageNumber") === before + 1, "a strike's damage shows over the enemy")
            // The eyes are drawn with the body, under the darkness
            let eyes = find(e, "enemyEyes")
            check(eyes !== null && eyes.parent === e, "an enemy's eyes stay with its body, under the darkness")
            // Bones: a swing breaks a heap in its arc, not one behind the
            // knight; a whirlwind breaks every heap within its reach
            let p = game.player
            p.facingAngle = 0
            let cx = p.xWu + p.widthWu / 2, cy = p.yWu - p.heightWu / 2
            let broke = []
            let pile = (name, dx) => ({name: name, xWu: cx + dx, yWu: cy, destroy: () => broke.push(name)})
            let ahead = pile("ahead", 0.8), behind = pile("behind", -0.8)
            game.bonePiles = [ahead, behind]
            p._breakBones(p.attackRange, true)
            check(broke.join(",") === "ahead" && game.bonePiles.length === 1 && game.bonePiles[0] === behind,
                  "a swing breaks the heap in its arc, not the one behind (" + broke.join(",") + ")")
            p._breakBones(Balance.knight.whirlReach, false)
            check(broke.join(",") === "ahead,behind" && game.bonePiles.length === 0,
                  "a whirlwind breaks the heap behind too")
            // The bash: a right-click soon after a swing shoves the enemy in
            // front back and costs Balance.bash.mana; a late one does not
            let foe = game.enemies.find(x => !x.destroyed)
            foe.xWu = p.xWu + 1.0
            foe.yWu = p.yWu
            p.mana = p.maxMana
            p.attackCooldown = 0
            p.isAttacking = false
            let words = countNamed(game, "fightWord")
            p.attack()
            let fromX = p.xWu
            p.raiseShield()
            p.lowerShield()
            check(p._lungeT > 0, "the bash starts the lunge ("
                  + p._lungeT.toFixed(2) + " s)")
            bench.lungeFrom = fromX
            check(p.mana === p.maxMana - Balance.bash.mana && countNamed(game, "fightWord") === words + 1,
                  "a right-click right after a swing bashes: " + (p.maxMana - p.mana) + " mana, "
                  + (countNamed(game, "fightWord") - words) + " BASH")
            p.raiseShield()
            p.lowerShield()
            check(countNamed(game, "fightWord") === words + 1, "a second right-click in the same swing bashes no more")
            bench.bashFoe = foe
            bench.bashFrom = foe.xWu
        }],
        [300, () => {
            check(game.player.xWu > bench.lungeFrom + 0.2 && game.player._lungeT === 0,
                  "the knight lunged forward " + (game.player.xWu - bench.lungeFrom).toFixed(2) + " wu")
            check(bench.bashFoe.xWu > bench.bashFrom + 0.3, "the bashed enemy is shoved back ("
                  + (bench.bashFoe.xWu - bench.bashFrom).toFixed(2) + " wu)")
            let p = game.player
            p.isAttacking = false
            p.attackCooldown = 0
            p.mana = p.maxMana
            p.attack()
            bench.bashSwing = p._steps
        }],
        [() => (game.player._steps - bench.bashSwing) * game.player.world.timeStep > Balance.bash.window + 0.05, () => {
            let p = game.player
            p.raiseShield()
            p.lowerShield()
            check(p.mana > p.maxMana - Balance.bash.mana, "a right-click after the window only raises the shield")
            console.log("[Settings] done,", failures, "failed")
        }],
        [300, () => game.destroy()],
        [300, () => Qt.exit(failures)]
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
                    console.log("[Settings] FAIL step", i, "timed out")
                    Qt.exit(failures + 1)
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
