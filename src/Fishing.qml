import QtQuick
import Clayground.Sound

// Fishing at a camp's pond (Balance.fishing): something to come down with
// between the dungeons, calm enough to talk over and with a little timing
// in it. The left button at the water casts, a click on the bite hooks,
// the button held reels and is let go while the fish thrashes. Game.qml
// steps it with the physics (step) and hands it the left button (press,
// release); it draws the rod, the line, the bobber and the fish itself,
// over the room, on this node's screen only. A fish landed goes into the
// knight's creel (Player.creel).
Canvas {
    id: fishing
    objectName: "fishing"

    property var game: null
    readonly property var cfg: Balance.fishing
    readonly property var knight: game ? game.player : null
    readonly property real ppu: game ? game.pixelPerUnit : 1

    // "" (not fishing), "cast", "wait", "bite", "reel", "landed"
    property string phase: ""
    readonly property bool active: phase !== ""
    // The pond fished, {x, y, rx, ry} in wu, the water's ellipse
    property var pond: null
    // The bobber, in wu, and where the knight stood when it cast
    property real bx: 0
    property real by: 0
    property real _fromX: 0
    property real _fromY: 0
    property real _t: 0
    property real _phaseT: 0
    property real _waitFor: 0
    property var _nibbleAt: []
    property real _sinceNibble: 9
    // The fish hooked: its kind (index into cfg.kinds) and size in cm;
    // where it is on its way in, 0 at the bobber to 1 at the bank
    property var fish: null
    property real progress: 0
    property real _len: 1
    property real _bankX: 0
    property real _bankY: 0
    property real tension: 0
    property bool reeling: false
    property real _thrashIn: 0
    property real _thrashLeft: 0
    readonly property bool thrashing: _thrashLeft > 0 && _thrashIn <= 0
    readonly property bool telling: phase === "reel" && _thrashLeft > 0 && _thrashIn > 0 && _thrashIn <= cfg.tell
    property real _click: 0
    // Bites left in this camp's pond; a new level fills it again
    property int bitesLeft: cfg.bites
    // Where the mouse aims, on water the knight can cast to, or null
    property var aim: null

    z: 5

    function _rand(pair) { return pair[0] + Math.random() * (pair[1] - pair[0]) }
    function _centre() { return { x: knight.xWu + knight.widthWu / 2, y: knight.yWu - knight.heightWu / 2 } }

    // The camp's ponds as water ellipses
    function _ponds() {
        if (!game || !game.campStyled || !game.campProps) return []
        return game.campProps.filter(p => p.kind === "pond")
            .map(p => ({ x: p.x, y: p.y, rx: p.w * 0.42, ry: p.h * 0.4 }))
    }
    function _inside(p, x, y, k) {
        let dx = (x - p.x) / (p.rx * k), dy = (y - p.y) / (p.ry * k)
        return dx * dx + dy * dy <= 1
    }
    // The same for the game: a pad's aim stops at the water (Game.padAimWu)
    function ponds() { return _ponds() }
    function inside(p, x, y, k) { return _inside(p, x, y, k) }
    // The point of p's water edge nearest (x, y), close enough for a walk
    // round its ellipse
    function _edge(p, x, y) {
        let a = Math.atan2((y - p.y) / p.ry, (x - p.x) / p.rx)
        return { x: p.x + Math.cos(a) * p.rx, y: p.y + Math.sin(a) * p.ry }
    }
    function _free() {
        return knight && !knight.fallen && !game.fallen && !game.talking && !knight.isBlocking
            && !knight.shieldWanted && !knight.isAttacking && !knight.isCharging && !knight.isDashing
    }
    // The water the mouse aims at, the knight close enough to its edge
    function _aimed() {
        if (!knight || !_free()) return null
        let a = game.aimWu(), c = _centre()
        for (let p of _ponds()) {
            if (!_inside(p, a.x, a.y, 0.92)) continue
            let e = _edge(p, c.x, c.y)
            if (Math.hypot(e.x - c.x, e.y - c.y) > cfg.reach) continue
            let d = Math.hypot(a.x - c.x, a.y - c.y)
            let k = Math.min(1, cfg.castMax / Math.max(0.01, d))
            let tx = c.x + (a.x - c.x) * k, ty = c.y + (a.y - c.y) * k
            if (!_inside(p, tx, ty, 0.92)) continue
            return { pond: p, x: tx, y: ty }
        }
        return null
    }

    // The left button went down: true when fishing took it (no swing)
    function press() {
        if (!knight) return false
        switch (phase) {
        case "":
            let a = _aimed()
            if (!a || bitesLeft <= 0) {
                if (a && bitesLeft <= 0) _say("The water has gone still", "#9FB8B0")
                return a !== null
            }
            _cast(a)
            return true
        case "wait":
            _say("Too soon", "#C8C2A0")
            _end()
            return true
        case "bite":
            _hook()
            return true
        case "reel":
            reeling = true
            return true
        }
        return true
    }
    function release() { reeling = false }

    function _cast(a) {
        let c = _centre()
        pond = a.pond
        bx = a.x
        by = a.y
        _fromX = c.x
        _fromY = c.y
        phase = "cast"
        _phaseT = 0
        castSound.play()
    }
    function _startWait() {
        phase = "wait"
        _phaseT = 0
        _waitFor = _rand(cfg.wait)
        let n = Math.round(_rand(cfg.nibbles))
        let at = [], t = _waitFor
        for (let i = 0; i < n; i++) {
            t -= _rand(cfg.nibbleGap)
            if (t > 0.4) at.push(t)
        }
        _nibbleAt = at.sort((x, y) => x - y)
        plopSound.play()
    }
    function _hook() {
        let total = cfg.kinds.reduce((s, k) => s + k.weight, 0)
        let r = Math.random() * total, kind = 0
        for (; kind < cfg.kinds.length - 1 && r >= cfg.kinds[kind].weight; kind++) r -= cfg.kinds[kind].weight
        let k = cfg.kinds[kind]
        fish = { kind: kind, size: Math.round(_rand(k.size)) }
        let c = _centre()
        let e = _edge(pond, c.x, c.y)
        _bankX = e.x
        _bankY = e.y
        _len = Math.max(0.5, Math.hypot(bx - e.x, by - e.y))
        progress = 0
        tension = 0
        reeling = true
        _nextThrash()
        phase = "reel"
        _phaseT = 0
        biteSound.play()
    }
    function _nextThrash() {
        let f = cfg.kinds[fish.kind].fight
        _thrashIn = _rand(cfg.thrashEvery) / f + cfg.tell
        _thrashLeft = _rand(cfg.thrash) * f
    }
    function _say(text, color) {
        let c = _centre()
        game.spawnDamageNumber(c.x, c.y + 0.6, text, color)
    }
    // The line comes in, empty or not; quietly when lost is undefined
    function _end() {
        phase = ""
        fish = null
        reeling = false
        tension = 0
        requestPaint()
    }
    // A new level: the pond's bites are back, nothing on the line
    function reset() {
        _end()
        bitesLeft = cfg.bites
    }

    // A physics step of dt seconds
    function step(dt) {
        if (!game || !knight) return
        _t += dt
        _sinceNibble += dt
        if (phase === "") {
            let a = _aimed()
            let had = aim !== null
            aim = a
            if (a || had) _frame()
            return
        }
        aim = null
        let c = _centre()
        if (!_free() || Math.hypot(c.x - _fromX, c.y - _fromY) > cfg.leave) {
            if (phase === "reel") _say("It got away", "#C8C2A0")
            _end()
            return
        }
        _phaseT += dt
        switch (phase) {
        case "cast":
            if (_phaseT >= 0.35) _startWait()
            break
        case "wait":
            if (_nibbleAt.length > 0 && _phaseT >= _nibbleAt[0]) {
                _nibbleAt.shift()
                _sinceNibble = 0
                plipSound.play()
            }
            if (_phaseT >= _waitFor) {
                phase = "bite"
                _phaseT = 0
                bitesLeft--
                biteSound.play()
            }
            break
        case "bite":
            if (_phaseT >= cfg.biteWindow) {
                _say("It got away", "#C8C2A0")
                _end()
            }
            break
        case "reel":
            _stepReel(dt)
            break
        case "landed":
            if (_phaseT >= 0.7) _end()
            break
        }
        _frame()
    }
    function _stepReel(dt) {
        let wasThrashing = thrashing
        if (_thrashIn > 0) {
            let before = _thrashIn
            _thrashIn -= dt
            // The tell: a plip just before it thrashes, time to let go
            if (before > cfg.tell && _thrashIn <= cfg.tell) plipSound.play()
            if (_thrashIn <= 0) splashSound.play()
        } else {
            _thrashLeft -= dt
            if (_thrashLeft <= 0) _nextThrash()
        }
        if (thrashing) {
            if (reeling) tension = Math.min(1, tension + cfg.tensionRise * dt)
            else progress = Math.max(0, progress - cfg.slack * dt / _len)
        } else {
            tension = Math.max(0, tension - cfg.tensionFall * dt)
            if (reeling) {
                progress = Math.min(1, progress + cfg.reelSpeed * dt / _len)
                _click += dt
                if (_click >= 0.11) {
                    _click = 0
                    clickSound.play()
                }
            }
        }
        if (tension >= 1) {
            snapSound.play()
            _say("The line snapped", "#E08060")
            _end()
            return
        }
        if (progress >= 1) {
            let k = cfg.kinds[fish.kind]
            knight.creel = knight.creel.concat([{ kind: fish.kind, size: fish.size }])
            landSound.play()
            _say(k.name + ", " + fish.size + " cm", k.color)
            phase = "landed"
            _phaseT = 0
        }
    }

    // Where the fish is now, in wu
    function _fishAt() {
        return { x: bx + (_bankX - bx) * progress, y: by + (_bankY - by) * progress }
    }

    // Place the canvas round the knight and the water it fishes, and paint
    property real _ox: 0
    property real _oy: 0
    function _frame() {
        if (!knight) return
        let c = _centre()
        let px = phase === "" ? (aim ? aim.x : c.x) : bx, py = phase === "" ? (aim ? aim.y : c.y) : by
        let m = 2.5
        let x0 = Math.min(c.x, px) - m, x1 = Math.max(c.x, px) + m
        let y0 = Math.min(c.y, py) - m, y1 = Math.max(c.y, py) + m
        _ox = x0
        _oy = y1
        x = x0 * ppu
        y = (parent ? parent.height : 0) - y1 * ppu
        width = (x1 - x0) * ppu
        height = (y1 - y0) * ppu
        requestPaint()
    }
    function _px(xw) { return (xw - _ox) * ppu }
    function _py(yw) { return (_oy - yw) * ppu }

    onPaint: {
        let ctx = getContext("2d")
        ctx.reset()
        if (!knight) return
        let u = ppu
        // The cast it would make: a faint ring where the bobber would land
        if (phase === "" && aim) {
            ctx.beginPath()
            ctx.ellipse(_px(aim.x) - 0.22 * u, _py(aim.y) - 0.12 * u, 0.44 * u, 0.24 * u)
            ctx.strokeStyle = bitesLeft > 0 ? "rgba(230, 240, 235, 0.45)" : "rgba(160, 170, 165, 0.25)"
            ctx.lineWidth = 1.5
            ctx.stroke()
            // What the button does here, small beside it
            ctx.font = Math.round(Math.max(10, 0.32 * u)) + "px sans-serif"
            ctx.fillStyle = bitesLeft > 0 ? "rgba(230, 240, 235, 0.6)" : "rgba(160, 170, 165, 0.45)"
            ctx.fillText(bitesLeft > 0 ? (game.padInUse ? "R1 cast" : "LMB cast") : "still water", _px(aim.x) + 0.32 * u, _py(aim.y) + 0.1 * u)
            return
        }
        if (phase === "") return
        let c = _centre()
        let cast = phase === "cast" ? Math.min(1, _phaseT / 0.35) : 1
        // The bobber's place: flying out while it casts, then on the water
        let ex = _fromX + (bx - _fromX) * cast, ey = _fromY + (by - _fromY) * cast
        let f = phase === "reel" || phase === "landed" ? _fishAt() : { x: ex, y: ey }
        let ang = Math.atan2(f.y - c.y, f.x - c.x)
        // The rod: out from the knight towards the water, bent by the pull
        let bend = (phase === "reel" ? 0.15 + 0.5 * tension + (thrashing ? 0.15 : 0) : 0.05)
            * (phase === "reel" && thrashing ? 1 + 0.3 * Math.sin(_t * 40) : 1)
        let r0 = 0.35, r1 = 1.7
        let baseX = c.x + Math.cos(ang) * r0, baseY = c.y + Math.sin(ang) * r0
        let tipA = ang + bend * 0.3
        let tipX = c.x + Math.cos(tipA) * r1, tipY = c.y + Math.sin(tipA) * r1
        let midX = c.x + Math.cos(ang + bend * 0.15) * (r0 + r1) / 2
        let midY = c.y + Math.sin(ang + bend * 0.15) * (r0 + r1) / 2
        ctx.beginPath()
        ctx.moveTo(_px(baseX), _py(baseY))
        ctx.quadraticCurveTo(_px(midX), _py(midY), _px(tipX), _py(tipY))
        ctx.strokeStyle = "#6B4A2E"
        ctx.lineWidth = Math.max(2, 0.07 * u)
        ctx.lineCap = "round"
        ctx.stroke()
        // The line: sagging slack, straight and reddening under tension
        let sag = phase === "reel" ? 0.4 * (1 - tension) * (reeling ? 0.4 : 1) : 0.5
        let lx = (tipX + f.x) / 2, ly = (tipY + f.y) / 2 - sag
        ctx.beginPath()
        ctx.moveTo(_px(tipX), _py(tipY))
        ctx.quadraticCurveTo(_px(lx), _py(ly), _px(f.x), _py(f.y))
        let red = phase === "reel" ? tension : 0
        ctx.strokeStyle = "rgba(" + Math.round(220 + 30 * red) + ", " + Math.round(225 - 150 * red) + ", "
                + Math.round(215 - 160 * red) + ", " + (0.55 + 0.4 * red).toFixed(2) + ")"
        ctx.lineWidth = 1 + 1.2 * red
        ctx.stroke()

        if (phase === "cast") return
        if (phase === "wait" || phase === "bite") {
            // Rings spreading slowly from the bobber, and a quick one at a
            // nibble; the bite throws a wide one
            for (let k = 0; k < 2; k++) {
                let rt = ((_t * 0.5 + k * 0.5) % 1)
                _ring(ctx, bx, by, 0.2 + 0.7 * rt, 0.35 * (1 - rt))
            }
            if (_sinceNibble < 0.4) _ring(ctx, bx, by, 0.2 + _sinceNibble * 1.2, 0.6 * (1 - _sinceNibble / 0.4))
            if (phase === "bite") _ring(ctx, bx, by, 0.3 + _phaseT * 2.2, 0.8 * (1 - _phaseT / cfg.biteWindow))
            // The bobber: red over white, bobbing; twitched by a nibble,
            // under the water on the bite
            let under = phase === "bite"
            let bob = Math.sin(_t * 2.2) * 0.03 - (_sinceNibble < 0.25 ? 0.06 * Math.sin(_sinceNibble * 25) : 0)
            let cx = _px(bx), cy = _py(by + bob)
            let r = 0.12 * u * (under ? 0.6 : 1)
            ctx.globalAlpha = under ? 0.45 : 1
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.fillStyle = "#F0EDE4"
            ctx.fill()
            ctx.beginPath()
            ctx.arc(cx, cy, r, Math.PI, 0)
            ctx.fillStyle = "#C83A2A"
            ctx.fill()
            ctx.globalAlpha = 1
            return
        }
        // The fish: a shadow under the water coming in, splashing as it
        // thrashes; landed, it leaps to the bank in its own colours
        let k = cfg.kinds[fish.kind]
        if (phase === "landed") {
            let t = Math.min(1, _phaseT / 0.5)
            let hx = f.x + (c.x - f.x) * t * 0.6, hy = f.y + (c.y - f.y) * t * 0.6 + Math.sin(t * Math.PI) * 0.9
            _fish(ctx, hx, hy, ang + Math.PI + Math.sin(_t * 30) * 0.5, k, 1, fish.size)
            if (t < 1) _ring(ctx, f.x, f.y, 0.3 + t * 1.2, 0.6 * (1 - t))
            return
        }
        let wig = Math.sin(_t * (thrashing ? 26 : 9)) * (thrashing ? 0.6 : 0.25)
        _fish(ctx, f.x, f.y, ang + Math.PI + wig, k, thrashing ? 0.9 : 0.5, fish.size)
        if (telling) _ring(ctx, f.x, f.y, 0.3 + (cfg.tell - _thrashIn) * 1.5, 0.5)
        if (thrashing) {
            ctx.fillStyle = "rgba(235, 245, 245, 0.8)"
            for (let i = 0; i < 6; i++) {
                let a = _t * 11 + i * 1.05, d = 0.25 + 0.2 * Math.abs(Math.sin(_t * 17 + i))
                ctx.beginPath()
                ctx.arc(_px(f.x + Math.cos(a) * d), _py(f.y + Math.sin(a) * d * 0.6 + 0.1), 0.04 * u, 0, Math.PI * 2)
                ctx.fill()
            }
            _ring(ctx, f.x, f.y, 0.35 + 0.15 * Math.sin(_t * 20), 0.6)
        }
    }
    function _ring(ctx, x, y, r, a) {
        if (a <= 0) return
        let u = ppu
        ctx.beginPath()
        ctx.ellipse(_px(x) - r * u, _py(y) - r * 0.55 * u, 2 * r * u, 1.1 * r * u)
        ctx.strokeStyle = "rgba(220, 235, 230, " + a.toFixed(3) + ")"
        ctx.lineWidth = 1.2
        ctx.stroke()
    }
    // A fish at (x, y) heading a (radians, its head that way), its body
    // long by its size, alpha 1 out of the water
    function _fish(ctx, x, y, a, k, alpha, size) {
        let u = ppu
        let len = (0.35 + Math.min(1, size / 60) * 0.5) * (k.eel ? 1.5 : 1)
        let wid = len * (k.eel ? 0.18 : 0.38)
        ctx.save()
        ctx.translate(_px(x), _py(y))
        ctx.rotate(-a)
        ctx.globalAlpha = alpha
        if (k.glows && alpha > 0.5) {
            ctx.shadowColor = k.color
            ctx.shadowBlur = 12
        }
        ctx.beginPath()
        ctx.ellipse(-len * 0.5 * u, -wid * 0.5 * u, len * u, wid * u)
        ctx.fillStyle = k.color
        ctx.fill()
        ctx.beginPath()
        ctx.moveTo(-len * 0.45 * u, 0)
        ctx.lineTo(-len * 0.8 * u, -wid * 0.55 * u)
        ctx.lineTo(-len * 0.8 * u, wid * 0.55 * u)
        ctx.closePath()
        ctx.fill()
        ctx.restore()
    }

    Sound { id: castSound; source: "assets/fish_cast.wav"; volume: game && !game.muted ? 0.6 * game.soundVolume : 0 }
    Sound { id: plopSound; source: "assets/fish_plop.wav"; volume: game && !game.muted ? 0.6 * game.soundVolume : 0 }
    Sound { id: plipSound; source: "assets/fish_plip.wav"; volume: game && !game.muted ? 0.5 * game.soundVolume : 0 }
    Sound { id: biteSound; source: "assets/fish_bite.wav"; volume: game && !game.muted ? 0.8 * game.soundVolume : 0 }
    Sound { id: clickSound; source: "assets/fish_click.wav"; volume: game && !game.muted ? 0.35 * game.soundVolume : 0 }
    Sound { id: splashSound; source: "assets/fish_splash.wav"; volume: game && !game.muted ? 0.6 * game.soundVolume : 0 }
    Sound { id: landSound; source: "assets/fish_land.wav"; volume: game && !game.muted ? 0.7 * game.soundVolume : 0 }
    Sound { id: snapSound; source: "assets/fish_snap.wav"; volume: game && !game.muted ? 0.6 * game.soundVolume : 0 }
}
