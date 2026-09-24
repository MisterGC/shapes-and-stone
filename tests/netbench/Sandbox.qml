// Net bench - measures the game's player-sync path end to end.
//
// Mirrors Game.qml/RemotePlayer.qml exactly: the same Network settings,
// a 50 ms Timer sampling a frame-updated position into broadcastState,
// and a StateInterpolator (120 ms) on the receiving side. The sender moves
// on a path that is a pure function of the wall clock, so a receiver on
// the same machine can compute the sender's true position for any instant
// and compare it with what the interpolator shows.
//
// Driven by run_netbench.py through the inspector protocol
// (clayliveloader --sbx Sandbox.qml --instance <name>).

import QtQuick
import Clayground.Network

Item {
    id: bench
    anchors.fill: parent

    // ---- knobs (set by the driver before host()/join()) ----
    // sendIntervalMs <= 0 sends one snapshot per rendered frame, which is
    // what Game.qml does since it broadcasts on every physics step.
    property int sendIntervalMs: 0
    property alias delayMs: sync.delayMs   // RemotePlayer.qml: 120
    property bool useLocalSignaling: true

    // ---- sender: clock-driven path, peak speed = Player.maxSpeed (7.5 Wu/s) ----
    // x = 10 + 8 sin(w t), y = 10 + 8 cos(w t), w = 7.5 / 8  -> |v| = 7.5 Wu/s
    readonly property real pathW: 7.5 / 8
    property real t0: 0                    // shared origin (Date.now() on the sender)
    function truthAt(t) {
        let s = (t - t0) / 1000
        return {x: 10 + 8 * Math.sin(pathW * s),
                y: 10 + 8 * Math.cos(pathW * s),
                a: ((s * 90) % 360 + 360) % 360}
    }
    // Like Player.xWu: updated once per rendered frame by the physics step
    property real senderX: 0
    property real senderY: 0
    property real senderA: 0
    function sendSnapshot() {
        net.broadcastState({x: bench.senderX, y: bench.senderY,
                            a: bench.senderA, s: 0, h: 120})
    }
    FrameAnimation {
        running: bench.t0 > 0 && net.connected
        onTriggered: {
            let p = bench.truthAt(Date.now())
            bench.senderX = p.x; bench.senderY = p.y; bench.senderA = p.a
            if (bench.sendIntervalMs <= 0 && net.isHost) bench.sendSnapshot()
        }
    }
    Timer {
        interval: Math.max(1, bench.sendIntervalMs)
        repeat: true
        running: bench.sendIntervalMs > 0 && bench.t0 > 0 && net.connected && net.isHost
        onTriggered: bench.sendSnapshot()
    }

    // ---- receiver: interpolate the host's stream, log error per frame ----
    property string trackedSender: ""
    property var samples: []               // {t, ix, iy, tx, ty}
    property var arrivalDt: []             // ms between consecutive state arrivals
    property real lastArrival: 0
    property int stateCount: 0

    StateInterpolator {
        id: sync
        delayMs: 120
        angleKeys: ["a"]
        onUpdated: {
            if (bench.t0 <= 0) return
            let now = Date.now()
            let p = bench.truthAt(now)
            let s = bench.samples
            s.push({t: now, ix: value.x, iy: value.y, tx: p.x, ty: p.y})
            if (s.length > 4000) s.splice(0, s.length - 4000)
        }
    }

    Network {
        id: net
        maxNodes: 4
        topology: Network.Topology.Star
        autoRelay: true
        onMessageReceived: (from, data) => {
            if (data.type === "t0") { bench.t0 = data.t0; sync.reset(); bench.samples = [] }
        }
        onStateReceived: (from, data) => {
            if (from !== bench.trackedSender) return
            let now = Date.now()
            if (bench.lastArrival > 0) {
                let d = bench.arrivalDt
                d.push(now - bench.lastArrival)
                if (d.length > 4000) d.splice(0, d.length - 4000)
            }
            bench.lastArrival = now
            bench.stateCount++
            sync.push(data)
        }
    }

    // ---- driver API ----
    readonly property string netId: net.networkId
    readonly property bool connected: net.connected
    readonly property var nodeList: net.nodes
    readonly property var netRef: net

    function configure(local, intervalMs, delay) {
        useLocalSignaling = local; sendIntervalMs = intervalMs; delayMs = delay
    }
    function hostUp() {
        net.signalingMode = useLocalSignaling ? Network.SignalingMode.Local
                                              : Network.SignalingMode.Cloud
        net.host()
    }
    function joinNet(code) {
        net.signalingMode = useLocalSignaling ? Network.SignalingMode.Local
                                              : Network.SignalingMode.Cloud
        net.join(code)
    }
    // Host: start the clock-driven path and tell everyone the origin.
    function startPath() {
        t0 = Date.now()
        net.broadcast({type: "t0", t0: t0})
    }
    function trackSender(id) {
        trackedSender = id; sync.reset(); samples = []; arrivalDt = []
        lastArrival = 0; stateCount = 0
    }

    // Error statistics of the interpolated view against the truth, and the
    // effective end-to-end delay: the time shift that best explains the
    // interpolated position (interp(t) ~ truth(t - shift)).
    function report() {
        let s = samples
        let n = s.length
        if (n < 10) return {n: n}
        let errs = []
        for (let i = 0; i < n; ++i) {
            let dx = s[i].ix - s[i].tx, dy = s[i].iy - s[i].ty
            errs.push(Math.sqrt(dx * dx + dy * dy))
        }
        let sorted = errs.slice().sort((a, b) => a - b)
        let mean = errs.reduce((a, b) => a + b, 0) / n
        let bestShift = -1, bestRms = 1e9
        for (let shift = 0; shift <= 600; shift += 5) {
            let acc = 0
            for (let i = 0; i < n; ++i) {
                let p = truthAt(s[i].t - shift)
                let dx = s[i].ix - p.x, dy = s[i].iy - p.y
                acc += dx * dx + dy * dy
            }
            let rms = Math.sqrt(acc / n)
            if (rms < bestRms) { bestRms = rms; bestShift = shift }
        }
        let dt = arrivalDt
        let dtMean = dt.length ? dt.reduce((a, b) => a + b, 0) / dt.length : -1
        let dtVar = 0
        for (let i = 0; i < dt.length; ++i) dtVar += (dt[i] - dtMean) * (dt[i] - dtMean)
        let dtStd = dt.length ? Math.sqrt(dtVar / dt.length) : -1
        let dtMax = dt.length ? Math.max.apply(null, dt) : -1
        let stats = net.syncStats[trackedSender] || {}
        let peer = net.peerStats[trackedSender] || {}
        return {
            n: n,
            durationMs: s[n - 1].t - s[0].t,
            errMeanWu: mean,
            errP95Wu: sorted[Math.floor(n * 0.95)],
            errMaxWu: sorted[n - 1],
            effectiveDelayMs: bestShift,
            residualRmsWu: bestRms,
            arrivals: stateCount,
            arrivalDtMeanMs: dtMean,
            arrivalDtStdMs: dtStd,
            arrivalDtMaxMs: dtMax,
            dropped: stats.dropped !== undefined ? stats.dropped : -1,
            rttMs: peer.latency !== undefined ? peer.latency : net.latency,
            stateChannel: peer.stateChannel || "",
            phaseTiming: net.phaseTiming
        }
    }
}
