// Lip-sync bench - a voiced greeting moves its speaker's mouth from the
// line's viseme cues (issue #191).
//
// One knight in the camp talks to the innkeeper, the blacksmith and the
// witch in turn with E. Each greeting must be its cue's render in
// sound/voice/npc_greetings/, and the dialogue panel must hold the mouth
// cues of the visemes file beside it, as many as the file has. While the
// line plays the speaker's mouth must show, take the shape of the cue at
// that time and take more than one shape; once the cues are over it rests
// on X, and the panel closed it shows no mouth. Prints one PASS or FAIL
// line per check and exits with the number of failures. Reading the
// visemes needs QML_XHR_ALLOW_FILE_READ=1.
//
//   QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen qml -I <build>/bin/qml tests/lipsync/lipsync.qml

import QtQuick
import QtQuick.Window
import QtTest

Window {
    id: bench
    width: 1000
    height: 500
    visible: true
    color: "#1a1a2e"

    property var solo: null
    property int failures: 0

    function check(ok, what) {
        console.log("[LipSync]", ok ? "PASS" : "FAIL", what)
        if (!ok) failures++
    }

    TestEvent { id: keys }
    function press(key) { keys.keyClick(key, Qt.NoModifier, -1) }

    Component.onCompleted: {
        let comp = Qt.createComponent(Qt.resolvedUrl("../../src/Game.qml"))
        if (comp.status !== Component.Ready) {
            console.log("[LipSync] FAIL", comp.errorString())
            Qt.exit(1)
            return
        }
        solo = comp.createObject(bench.contentItem, {width: 1000, height: 500, muted: true,
                                                     recordStoreName: "ShapesAndStoneLipSyncBench"})
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
    function panel() {
        for (let i = 0; i < solo.data.length; i++)
            if (solo.data[i] && typeof solo.data[i].lipSync === "function") return solo.data[i]
        return null
    }
    function npc(name) {
        let kids = solo.room.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i].objectName === "npc" && kids[i].npcName === name) return kids[i]
        return null
    }
    function readCues(line) {
        let xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../sound/voice/npc_greetings/" + line + ".visemes.json"), false)
        xhr.send()
        try { return JSON.parse(xhr.responseText).mouthCues } catch (e) { return [] }
    }
    function cueAt(cues, t) {
        let c = cues.find(c => t >= c.start && t < c.end)
        return c ? c.value : "X"
    }

    // The speaker talked to now, its line and what was seen of its mouth
    readonly property var speakers: [["Innkeeper", "innkeeper_greeting"], ["Blacksmith", "blacksmith_greeting"],
                                     ["Witch", "witch_greeting"]]
    property int who: 0
    property var fileCues: []
    property var seen: []
    property int matched: 0
    property int sampled: 0
    function speaker() { return npc(speakers[who][0]) }
    function standBy() {
        let n = speaker()
        n.routine = []
        solo.player.xWu = n.xWu
        solo.player.yWu = n.yWu - 1
    }
    // Every 50 ms while the line plays: the mouth shape against the cue at
    // that time, a frame either side
    Timer {
        id: watch
        interval: 50
        repeat: true
        onTriggered: {
            let p = bench.panel(), n = bench.speaker()
            let t = (Date.now() - p._voiceStart) / 1000
            let near = [bench.cueAt(p.mouthCues, t - 0.04), bench.cueAt(p.mouthCues, t),
                        bench.cueAt(p.mouthCues, t + 0.04)]
            bench.sampled++
            if (near.indexOf(n.mouth) >= 0) bench.matched++
            if (bench.seen.indexOf(n.mouth) < 0) bench.seen = bench.seen.concat([n.mouth])
        }
    }

    function talk() {
        standBy()
        seen = []
        matched = 0
        sampled = 0
        fileCues = readCues(speakers[who][1])
    }
    function talkSteps() {
        return [
            [() => speaker() !== null && speaker().nearbyPlayer !== null, () => {
                solo.forceActiveFocus()
                press(Qt.Key_E)
                watch.restart()
            }],
            [() => panel().visible, () => {
                let n = speaker(), line = speakers[who][1]
                let g = solo._greetings["voice/npc_greetings/" + line]
                check(n.greetingSound === "voice/npc_greetings/" + line && g
                      && String(g.source).endsWith("sound/voice/npc_greetings/" + line + ".wav"),
                      speakers[who][0] + " greets with its cue's render, " + line + ".wav")
                check(fileCues.length > 2 && panel().mouthCues.length === fileCues.length,
                      "the panel holds the line's " + panel().mouthCues.length + " mouth cues, "
                      + fileCues.length + " in its visemes file")
                check(find(n, "mouth").visible, "the speaker's mouth shows while it speaks")
            }],
            [() => fileCues.length > 0 && (Date.now() - panel()._voiceStart) / 1000
                   > fileCues[fileCues.length - 1].end + 0.2, () => {
                watch.stop()
                let n = speaker(), talking = seen.filter(s => s !== "X")
                check(talking.length >= 2, "its mouth takes " + talking.length + " shapes while it speaks ("
                      + seen.join("") + ")")
                check(sampled > 10 && matched >= sampled * 0.9,
                      "its mouth shows the cue of the moment " + matched + " of " + sampled + " times")
                check(n.mouth === "X", "once the line is over its mouth rests on X (" + n.mouth + ")")
                press(Qt.Key_Escape)
            }],
            [() => !panel().visible, () => {
                check(speaker().mouth === "" && !find(speaker(), "mouth").visible,
                      "the panel closed, the speaker shows no mouth")
                who++
                if (who < speakers.length) talk()
            }]
        ]
    }

    property var steps: [
        [() => solo.width > 0, () => solo.applyScenario("dungeon", 0)],
        [() => solo.player !== null, () => solo._enterLevel(solo.levelIndex + 1)],
        [() => solo.player && solo.levelType === "village" && npc("Witch") !== null, () => {
            solo.player.hp = 100000
            talk()
        }]
    ].concat(talkSteps(), talkSteps(), talkSteps(), [
        [100, () => console.log("[LipSync] done,", failures, "failed")],
        [300, () => solo.destroy()],
        [300, () => Qt.exit(failures)]
    ])

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
                    console.log("[LipSync] FAIL step", i, "timed out")
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
