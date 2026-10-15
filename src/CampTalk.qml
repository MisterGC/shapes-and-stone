import QtQuick

// The travellers' talk at the camp (issue #151): every so often two of
// them exchange a pair of lines in speech bubbles, one says the first
// line and the other answers. What comes in which order, and who says
// it, is the plan the camp drew from the level's seed, so every screen
// of a session hears the same exchanges in the same order; only when
// each comes is each screen's own. Nothing hangs on it. Numbers in
// Balance.camp.travellers.
Item {
    id: talk

    property var numbers: Balance.camp.travellers
    // The travellers, Npcs
    property var travellers: []
    // The exchanges in the order they come, round and round:
    // { a, b, lines: [first, answer] }, a and b indexes into travellers
    property var plan: []
    // Seconds before the first exchange, and between the exchanges,
    // round and round
    property real first: Infinity
    property var waits: []
    // What has been said: { who, line, t }, t seconds in the camp
    property var said: []
    // How many exchanges have been opened
    property int exchanged: 0

    property real _t: 0
    property real _in: first
    property var _answer: null

    // Two can talk while each stands at its spot and they are near
    function _canTalk(a, b) {
        return a.doing !== null && b.doing !== null
            && Math.hypot(a.xWu - b.xWu, a.yWu - b.yWu) <= numbers.reach
    }
    function _say(who, line) {
        who.say(line, numbers.show)
        said.push({ who: who.npcName, line: line, t: _t })
    }
    function tick(dt) {
        _t += dt
        if (_answer) {
            // One talked to by a knight leaves its answer unsaid (issue #178)
            if (_answer.who.listening) _answer = null
            else if (_t >= _answer.at) {
                _say(_answer.who, _answer.line)
                _answer = null
            }
            return
        }
        _in -= dt
        if (_in > 0 || plan.length === 0) return
        let e = plan[exchanged % plan.length]
        let a = travellers[e.a], b = travellers[e.b]
        // Not now: tried again next tick
        if (!a || !b || !_canTalk(a, b)) return
        _say(a, e.lines[0])
        _answer = { who: b, line: e.lines[1], at: _t + numbers.answer }
        exchanged++
        _in = waits.length > 0 ? waits[(exchanged - 1) % waits.length] : numbers.every[0]
    }
    Timer {
        interval: 100
        running: talk.travellers.length >= 2
        repeat: true
        onTriggered: talk.tick(interval / 1000)
    }
}
