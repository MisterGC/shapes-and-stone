import QtQuick
import Box2D
import Clayground.Network
import Clayground.Physics

// Another player's knight: a body that follows the received state. How it
// looks is KnightView, the same as the local Player's.
PhysicsItem {
    id: rp

    property string nodeId: ""
    property var gameWorld: null
    property color playerColor: "#A44A90"
    property real facingAngle: 0
    property int actionState: 0   // 0=idle, 1=atk, 2=block, 3=dash
    property int remoteHp: Balance.knight.hp
    property bool remoteBlocking: false
    property int rttMs: -1        // best round trip the network measured, -1 unknown
    // Its node's state has come: until then where the knight is and
    // whether it is down are not known, and it is not drawn
    property bool known: false
    visible: known

    widthWu: 1.0
    heightWu: 1.0

    bodyType: Body.Kinematic
    fixedRotation: true
    gravityScale: 0

    fixtures: Circle {
        radius: rp.width * 0.35
        x: rp.width / 2
        y: rp.height / 2
        sensor: true
    }

    // Snapshot-buffer interpolation: the avatar renders a small constant
    // delay in the past so it always blends between two received states.
    // (A Behavior on xWu/yWu is the wrong tool here - see clayground #139.)
    // sentAt is the sender's clock from Network.stateReceived (clayground
    // #290); older plugins pass nothing and the interpolator falls back to
    // the arrival time.
    function pushState(data, sentAt) {
        known = true
        sync.push(data, sentAt)
        actionState = data.s !== undefined ? data.s : 0
        // A sender without b only has the block in s
        remoteBlocking = data.b !== undefined ? data.b === 1 : actionState === 2
        if (data.h !== undefined) remoteHp = data.h
    }

    // The delay is the visible lag: at full speed (7.5 Wu/s) every 10 ms
    // puts the avatar 0.075 Wu behind where the player really is. Game.qml
    // sends a snapshot per physics step (~16 ms), so 50 ms covers three
    // missed steps on a LAN. Over the internet the buffer has to absorb
    // jitter: with a plugin that has clayground #291 the interpolator sizes
    // the delay from the observed jitter itself; older plugins get the
    // round trip added as a stand-in.
    StateInterpolator {
        id: sync
        delayMs: 50 + Math.min(100, Math.max(0, rp.rttMs))
        angleKeys: ["a"]
        Component.onCompleted: if ("autoDelay" in sync) sync.autoDelay = true
        onUpdated: {
            rp._trackMotion(value.x, value.y)
            rp.xWu = value.x
            rp.yWu = value.y
            if (value.a !== undefined) rp.facingAngle = value.a
        }
    }

    // The walk the view animates (step bob, lean, lantern swing) comes from
    // how fast the interpolated body moves, relative to the knight's full
    // speed; the state carries no input
    readonly property real _maxSpeed: 7.5
    property real _moveX: 0
    property real _moveAmount: 0
    property real _lastMotionMs: 0
    function _trackMotion(x, y) {
        let now = Date.now()
        let dt = (now - _lastMotionMs) / 1000
        _lastMotionMs = now
        if (dt <= 0 || dt > 0.25) return
        let vx = (x - xWu) / dt / _maxSpeed
        let vy = (y - yWu) / dt / _maxSpeed
        // Smoothed: frame times jitter, the walk should not
        _moveX += (Math.max(-1, Math.min(1, vx)) - _moveX) * 0.3
        _moveAmount += (Math.min(1, Math.sqrt(vx * vx + vy * vy)) - _moveAmount) * 0.3
        _still.restart()
    }
    // No new positions: the knight stands
    Timer { id: _still; interval: 150; onTriggered: { rp._moveX = 0; rp._moveAmount = 0 } }

    // Reliable action events (broadcast) trigger crisp effects even when
    // the sampled action state misses the moment.
    // Its sounds are the local knight's, quieter and fading with distance.
    function triggerAction(name) {
        let gain = gameWorld ? gameWorld.remoteGain(xWu, yWu) : 0
        if (name === "attack") {
            view.swing()
            if (gameWorld && gain > 0 && actionState !== 3) gameWorld.playSwordSwing(gain)
        } else if (name === "dash") {
            view.dash(150)
            if (gameWorld && gain > 0) gameWorld.playDash(gain)
        } else if (name === "parry") {
            view.parry()
            if (gameWorld && gain > 0) gameWorld.playImpact(gain)
        } else if (name === "block") {
            view.block()
            if (gameWorld && gain > 0) gameWorld.playBlock(gain)
        } else if (name === "perfectBlock") {
            view.perfectBlock()
            if (gameWorld && gain > 0) gameWorld.playBlock(gain, true)
        } else if (name === "hurt") {
            view.hurt()
            _grace.restart()
        }
    }
    // The grace after a hit, on this screen's clock: the other knight
    // counts it on its own physics steps
    NumberAnimation {
        id: _grace
        target: view
        property: "graceLeft"
        from: Balance.knight.hurtGrace
        to: 0
        duration: Balance.knight.hurtGrace * 1000
    }

    // A swing the event has not shown yet
    onActionStateChanged: if (actionState === 1 && !view.swinging) view.swing()

    KnightView {
        id: view
        host: rp
        gameWorld: rp.gameWorld
        bodyColor: rp.playerColor
        trimColor: Qt.darker(rp.playerColor, 1.4)
        accentColor: Qt.lighter(rp.playerColor, 1.3)
        bladeColor: Qt.lighter(rp.playerColor, 1.1)
        ridgeColor: Qt.darker(rp.playerColor, 1.15)
        facingAngle: rp.facingAngle
        moveX: rp._moveX
        moveAmount: rp._moveAmount
        blocking: rp.remoteBlocking
        dashing: rp.actionState === 3
        downed: rp.remoteHp <= 0
    }
}
