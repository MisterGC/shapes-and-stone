// Strings capture - one frame of a lead's string (issue #272), for
// clayrender: the duel room's lead strikes string `string` of its type
// at the knight, which stands with its shield up, and the world is
// stepped `step` physics steps into the string; `ready` holds the capture
// until then, and `info` says what the frame shows. The same step gives
// the same frame on every run.
//
//   clayrender tests/strings/Capture.qml --out f.png --size 900x600 \
//       --set 'string=1' --set 'step=40' --wait-for 'ready' --result -  \
//       --eval 'JSON.stringify(info)'

import QtQuick
import Clayground.Common
import "../../src"

Item {
    id: capture
    width: 900
    height: 600

    property int string: 0
    property int step: 0
    property bool ready: false
    property var info: ({})

    Game {
        id: game
        anchors.fill: parent
        muted: true
    }

    function hold(p, e, x, y) {
        p.xWu = x
        p.yWu = y
        p.hp = p.maxHp
        p.mana = p.maxMana
        p.graceLeft = 0
        p.facingAngle = Math.atan2(e.yWu - e.heightWu / 2 - p.yWu + p.heightWu / 2,
                                   e.xWu + e.widthWu / 2 - p.xWu - p.widthWu / 2) * 180 / Math.PI
        p.isBlocking = true
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        property int stage: 0
        onTriggered: {
            if (stage === 0) {
                if (game.screen !== "title") return
                game.applyScenario("duel")
                stage = 1
                return
            }
            let lead = game.enemies.find(e => !e.destroyed && e.lead)
            if (!game.player || !game.fightRoomActive || !lead) return
            stop()
            Clayground.paused = true
            let p = game.player
            lead.halt()
            lead.halted = false
            lead.crushChance = 0
            lead.target = p
            lead.xWu = p.xWu + 1.6
            lead.yWu = p.yWu
            let x = p.xWu, y = p.yWu
            hold(p, lead, x, y)
            Clayground.physicsStep(2)
            lead.beginString(capture.string, false)
            for (let i = 0; i < capture.step && lead.stringName !== ""; i++) {
                hold(p, lead, x, y)
                Clayground.physicsStep(1)
            }
            hold(p, lead, x, y)
            let s = Balance.lead.strings[lead.enemyType][capture.string]
            capture.info = {type: lead.enemyType, name: s.name, beats: s.beats, step: capture.step,
                            beat: lead._beat, state: lead.aiState, ring: Math.round(lead.ringProgress * 100) / 100,
                            window: lead.parryWindow, feinting: lead.feinting}
            capture.ready = true
        }
    }
}
