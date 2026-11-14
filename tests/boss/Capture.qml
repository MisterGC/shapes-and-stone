// Boss capture - one frame of the Hollow Warden's fight (issue #274), for
// clayrender: the dungeon at depth 2 on the scenario's seed, the knight
// stepped into the Warden's room, and the world stepped to the moment
// `shot` names - "banner" its name banner as the room shuts, "phase1" a
// wind-up of its phase 1, "phase2" its phase 2 with its adds, its core
// and a zone warning under the knight, "victory" the victory banner over
// its gold with the gates open. `ready` holds the capture until then, and
// `info` says what the frame shows. The same shot gives the same frame on
// every run.
//
//   clayrender tests/boss/Capture.qml --out f.png --size 1100x700 \
//       --set 'shot="phase2"' --wait-for 'ready' --settle --result - \
//       --eval 'JSON.stringify(info)'

import QtQuick
import Clayground.Common
import "../../src"

Item {
    id: capture
    width: 1100
    height: 700

    property string shot: "phase1"
    property bool ready: false
    property var info: ({})

    Game {
        id: game
        anchors.fill: parent
        muted: true
    }

    function alive(e) { return !!e && e.destroyed === false }
    function step(n, keep) {
        for (let i = 0; i < n; i++) {
            Clayground.physicsStep(1)
            if (keep) keep()
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        property int stage: 0
        onTriggered: {
            if (stage === 0) {
                if (game.screen !== "title") return
                game.applyScenario("bossroom", 2)
                stage = 1
                return
            }
            let f = game.bossFight
            let w = game.enemies.find(e => alive(e) && e.boss)
            if (!game.player || !w || f.stage !== "waiting") return
            stop()
            Clayground.paused = true
            for (let e of game.enemies) if (alive(e) && !e.boss) e.halt()
            let p = game.player, r = game.bossRoom, cs = game.cellSize
            // The knight in the room, a few steps from the Warden, its
            // shield towards it
            let wc = { x: w.xWu + w.widthWu / 2, y: w.yWu - w.heightWu / 2 }
            let at = { x: wc.x - 3.2, y: wc.y - 1.2 }
            let hold = () => {
                p.xWu = at.x - p.widthWu / 2
                p.yWu = at.y + p.heightWu / 2
                p.hp = p.maxHp
                p.graceLeft = 0
                p.facingAngle = Math.atan2(w.yWu - w.heightWu / 2 - at.y, w.xWu + w.widthWu / 2 - at.x)
                                * 180 / Math.PI
                p.isBlocking = true
            }
            hold()
            step(2, hold)
            game.revealAroundPlayer()
            game.snapCamera()
            if (shot === "banner") {
                step(50, hold)
            } else if (shot === "phase1") {
                step(200, hold)
                let n = 0
                while (n < 600 && !(w.aiState === "telegraph" && w.ringProgress > 0.5)) { step(1, hold); n++ }
            } else {
                // Past the name banner
                step(200, hold)
                w.hp = Math.floor(w.maxHp * Balance.boss.phaseAt) + 5
                w.takeDamage(1000, p.xWu, p.yWu, false)
                step(2, hold)
                for (let e of game.enemies) if (alive(e) && !e.boss) e.halt()
                if (shot === "phase2") {
                    let n = 0
                    while (n < 600 && !(f.zones.length > 0 && f.now() > f.zones[0].at - 0.45)) { step(1, hold); n++ }
                } else {
                    // Hurt, a few steps off where it falls: the heal and
                    // the whole pile show
                    p.hp = Math.round(p.maxHp / 2)
                    p.mana = 0
                    p.xWu = w.xWu + w.widthWu / 2 - 3.5 - p.widthWu / 2
                    p.yWu = w.yWu - w.heightWu / 2 - 1 + p.heightWu / 2
                    p.isBlocking = false
                    w.takeDamage(1000000, p.xWu, p.yWu, false)
                    step(60)
                }
            }
            game.snapCamera()
            let banner = f.children.find(x => x.objectName === "bossBanner")
            let victory = f.children.find(x => x.objectName === "victoryBanner")
            capture.info = {
                shot: shot, stage: f.stage, phase: f.phase,
                warden: alive(w) ? { hp: w.hp, maxHp: w.maxHp, state: w.aiState,
                                     ring: Math.round(w.ringProgress * 100) / 100 } : null,
                adds: game.enemies.filter(e => alive(e) && !e.boss && f.inside(e.xWu + 0.4, e.yWu - 0.4, 0)).length,
                zones: f.zones.length, gatesShut: f.gates.filter(g => g.shut).length, gates: f.gates.length,
                banner: banner ? Math.round(banner.opacity * 100) / 100 : 0,
                victory: victory ? Math.round(victory.opacity * 100) / 100 : 0,
                gold: game.goldDrops.length, knightHp: p.hp
            }
            capture.ready = true
        }
    }
}
