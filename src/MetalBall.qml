import QtQuick
import Box2D
import Clayground.Physics
import Clayground.World

// A slinger's metal ball (Balance.ball, issue #322). It flies straight and
// bounces off the walls and a shut door, mirrored off the cell its edge
// reached, so its path is the same on every screen whatever the frame
// rate; after Balance.ball.bounces bounces it falls at the next wall it
// meets. A ball no shield has touched passes the enemies and hurts the
// knight it meets; any raised shield facing it bounces it (turn), and from
// then on it passes the knights and hurts the first enemy it meets. A
// fallen ball lies a moment, harmless, and is gone.
PhysicsItem {
    id: ball
    objectName: "ball"

    property var gameWorld: null
    // The host's id for this ball, the same on every node
    property string ballId: ""
    // The way it flies, y up, and how fast
    property real dirX: 0
    property real dirY: 0
    property real speed: Balance.ball.speed
    property int damage: Balance.enemy.slinger.atk
    // Its slinger's perfect-block window in physics steps (Enemy.
    // perfectFrames, wider for a lead at a slow duel pace); 0 for the
    // knight's own
    property int perfectFrames: 0
    // The walls it bounced off so far
    property int bounces: 0
    // A shield bounced it: back, as a spitter's shot sent back is (so
    // what looks for a shot on its way passes it), by "blocked" or
    // "perfect"; own when this screen's knight's shield did, which deals
    // backDamage to the enemy it meets
    property bool back: false
    property bool ownBack: false
    property int backDamage: 0
    property string turnedBy: ""
    // It fell: it lies where it fell, harmless, until it is gone
    property bool fallen: false
    property bool destroyed: false
    // It bounced off a wall, its n-th, its centre touching the wall at
    // (x, y)
    signal bounced(int n, real x, real y)
    // It fell: how - "wall" (past its bounces), "knight" (it hurt one),
    // "enemy" (a shield's ball hit one), "life" (its time was over) or
    // "report" (another node's knight or enemy met it)
    signal fell(string how)
    // It is gone, on this screen
    signal gone()

    widthWu: Balance.ball.size
    heightWu: Balance.ball.size
    readonly property real centreX: xWu + widthWu / 2
    readonly property real centreY: yWu - heightWu / 2

    bodyType: Body.Dynamic
    fixedRotation: true
    gravityScale: 0

    // Its one fixture is a sensor: it meets the knights and the enemies,
    // and the walls are the grid's (Game.ballSolid), not the physics'
    property alias sensorCategories: sensor.categories
    property alias sensorCollidesWith: sensor.collidesWith

    fixtures: [
        Circle {
            id: sensor
            radius: ball.width / 2
            x: ball.width / 2
            y: ball.height / 2
            sensor: true
            onBeginContact: (other) => ball.met(other)
        }
    ]

    // A cold glint of its own in the dark
    Light2d {
        offsetXWu: ball.widthWu / 2
        offsetYWu: -ball.heightWu / 2
        radius: ball.back ? 2.2 : 1.6
        color: ball.back ? Balance.ball.turnedColor : "#B8C4D0"
        intensity: ball.fallen ? 0.2 : 0.7
        castsShadows: false
    }

    // Visual: a dark iron sphere, a highlight up left; a shield's ball
    // glows pale. Fallen it settles, smaller and dull, and fades
    Item {
        id: look
        objectName: "ballLook"
        anchors.fill: parent
        scale: ball.fallen ? 0.8 : 1
        opacity: 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        Rectangle {
            visible: ball.back && !ball.fallen
            anchors.centerIn: parent
            width: parent.width * 1.8
            height: width
            radius: width / 2
            color: Balance.ball.turnedColor
            opacity: 0.3
        }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: ball.fallen ? Qt.darker(Balance.ball.color, 1.5) : Balance.ball.color
            border.color: ball.back && !ball.fallen ? Balance.ball.turnedColor : "#2A2F35"
            border.width: Math.max(1, width * 0.1)
        }
        Rectangle {
            x: parent.width * 0.22
            y: parent.height * 0.18
            width: parent.width * 0.3
            height: width
            radius: width / 2
            color: "#F2F6FA"
            opacity: ball.fallen ? 0.25 : 0.85
        }
        NumberAnimation on opacity {
            id: fadeOut
            running: false
            to: 0
            duration: Balance.ball.restTime * 1000
        }
    }

    // It flies on the physics steps: the step moved it, a wall it reached
    // turns it back from where it would have been
    Connections {
        target: ball.world
        function onStepped() { ball._step() }
    }
    function _step() {
        if (destroyed) return
        if (fallen) {
            body.linearVelocity = Qt.point(0, 0)
            return
        }
        if (gameWorld && gameWorld.ballSolid) _bounce()
        _lastX = centreX
        _lastY = centreY
        if (fallen) return
        body.linearVelocity = Qt.point(dirX * speed, -dirY * speed)
    }

    // Where its centre was after the step before, for the axes' tests
    property real _lastX: centreX
    property real _lastY: centreY
    Component.onCompleted: { _lastX = centreX; _lastY = centreY }

    // Each axis on its own, x first: when the edge it flies towards is in
    // a solid cell - along x in the rows it came from, along y in the
    // columns it is in now -, its centre is mirrored at that cell's side
    // and the axis turns; past its bounces it falls at that side instead
    function _bounce() {
        let cs = gameWorld.cellSize, r = widthWu / 2
        let cx = centreX, cy = centreY, hit = false
        // Where its centre was as it touched the wall
        let tx = cx, ty = cy
        let solidAt = (x, y) => gameWorld.ballSolid(Math.floor(x / cs), Math.floor(y / cs))
        if (dirX !== 0) {
            let sx = dirX > 0 ? 1 : -1, edge = cx + sx * r
            if (solidAt(edge, _lastY - r * 0.7) || solidAt(edge, _lastY + r * 0.7)) {
                let side = (sx > 0 ? Math.floor(edge / cs) : Math.floor(edge / cs) + 1) * cs
                if (bounces >= Balance.ball.bounces) return _fallAt(side - sx * r, cy, "wall")
                tx = side - sx * r
                cx = 2 * tx - cx
                dirX = -dirX
                hit = true
            }
        }
        if (dirY !== 0) {
            let sy = dirY > 0 ? 1 : -1, edge = cy + sy * r
            if (solidAt(cx - r * 0.7, edge) || solidAt(cx + r * 0.7, edge)) {
                let side = (sy > 0 ? Math.floor(edge / cs) : Math.floor(edge / cs) + 1) * cs
                if (bounces >= Balance.ball.bounces) return _fallAt(cx, side - sy * r, "wall")
                ty = side - sy * r
                cy = 2 * ty - cy
                dirY = -dirY
                hit = true
            }
        }
        if (!hit) return
        _put(cx, cy)
        bounces++
        bounced(bounces, tx, ty)
    }
    function _put(cx, cy) {
        xWu = cx - widthWu / 2
        yWu = cy + heightWu / 2
        _lastX = cx
        _lastY = cy
    }

    // Its time is over: it falls where it is. It starts again when a
    // shield sends it
    PhysicsTimer {
        id: life
        world: ball.world
        running: !ball.fallen && !ball.destroyed
        interval: Balance.ball.lifetime * 1000
        onTriggered: ball._fallAt(ball.centreX, ball.centreY, "life")
    }
    // A fallen ball lies restTime seconds, then is gone
    PhysicsTimer {
        id: rest
        world: ball.world
        running: false
        interval: Balance.ball.restTime * 1000
        onTriggered: ball.vanish()
    }

    // The sensor met a knight or an enemy: a ball on its way judges this
    // screen's knight, a shield's ball the first enemy
    function met(other) {
        if (destroyed || fallen) return
        let entity = other.getBody().target
        if (!entity) return
        if (back) {
            if (entity.objectName === "enemy") hitEnemy(entity)
            return
        }
        if (!entity.takeDamage || entity.objectName === "enemy") return

        // Any raised shield facing it bounces it: perfect along the way
        // the knight faces, plain off the shield
        let shield = entity.shieldShot ? entity.shieldShot(xWu, yWu, widthWu, dirX, dirY, perfectFrames) : ""
        if (shield === "perfect" || shield === "blocked") {
            let rad = entity.facingAngle * Math.PI / 180
            let d = shield === "perfect" ? Qt.point(Math.cos(rad), Math.sin(rad))
                                         : glanceOff(dirX, dirY, Math.cos(rad), Math.sin(rad))
            let dealt = Math.round(entity.atk * Balance.ball.backDamage)
            turn(shield, true, dealt, centreX, centreY, d.x, d.y)
            if (gameWorld && gameWorld.ballLanded)
                gameWorld.ballLanded(ballId, shield, centreX, centreY, d.x, d.y)
            return
        }
        // Dodged in a dash, or met in the grace after a hit: it flies on
        let result = entity.takeDamage(damage, xWu, yWu, widthWu, false, dirX, dirY, perfectFrames)
        if (result !== "hit" && result !== "blocked") return
        if (gameWorld) {
            gameWorld.impact("projectileHit", entity.xWu, entity.yWu, dirX, dirY)
            gameWorld.spawnHurtNumber(entity.xWu, entity.yWu, damage, Balance.ball.color)
            if (gameWorld.ballLanded) gameWorld.ballLanded(ballId, "hit", centreX, centreY)
        }
        _fallAt(centreX, centreY, "knight")
    }

    // The way a plain shield bounces it, (dx, dy) coming in, the shield
    // facing (nx, ny): mirrored off the shield, at least Balance.ball.glance
    // degrees off the line it came along, turned to the side the mirror
    // leans to (left when it comes straight on)
    function glanceOff(dx, dy, nx, ny) {
        let dot = dx * nx + dy * ny
        let ox = dot < -0.05 ? dx - 2 * dot * nx : nx
        let oy = dot < -0.05 ? dy - 2 * dot * ny : ny
        let len = Math.max(1e-6, Math.hypot(ox, oy))
        ox /= len
        oy /= len
        // The line it came along, back: (-dx, -dy)
        let bx = -dx, by = -dy
        let off = Math.atan2(bx * oy - by * ox, bx * ox + by * oy)
        let least = Balance.ball.glance * Math.PI / 180
        if (Math.abs(off) >= least) return Qt.point(ox, oy)
        let a = Math.atan2(by, bx) + (off < 0 ? -least : least)
        return Qt.point(Math.cos(a), Math.sin(a))
    }

    // A shield sent it from its centre (x, y) along (dx, dy): by
    // "blocked" or "perfect", own when this screen's knight's did, dealing
    // damage to the enemy it meets. A perfect block's flies at backSpeed;
    // its time starts again
    function turn(by, own, damage, x, y, dx, dy) {
        if (destroyed) return
        // One that fell here before another screen's shield turned it
        // there gets up again: no fade, no rest, seen whole
        rest.stop()
        fadeOut.stop()
        look.opacity = 1
        fallen = false
        back = true
        ownBack = own
        backDamage = damage
        turnedBy = by
        _put(x, y)
        let len = Math.max(1e-6, Math.hypot(dx, dy))
        dirX = dx / len
        dirY = dy / len
        if (by === "perfect") speed = Balance.ball.backSpeed
        body.linearVelocity = Qt.point(dirX * speed, -dirY * speed)
        life.restart()
    }

    // A shield's ball met enemy: it falls there, and the screen whose
    // knight's shield sent it deals the blow - a lead's stance breaks
    // under it (Enemy.takeShot, cause "ball") - and tells the others
    function hitEnemy(enemy) {
        if (destroyed || !enemy || enemy.destroyed) return
        if (ownBack && enemy.takeShot) {
            let dealt = enemy.takeShot(backDamage, centreX - dirX, centreY - dirY, "ball")
            if (gameWorld) {
                // The knight's own hit sound: its blow came back
                if (gameWorld.playImpact) gameWorld.playImpact()
                gameWorld.spawnDamageNumber(enemy.xWu, enemy.yWu, dealt, Balance.ball.turnedColor)
                if (gameWorld.countFight) gameWorld.countFight("ballBackHit")
                if (gameWorld.ballLanded) gameWorld.ballLanded(ballId, "enemy", centreX, centreY)
            }
        }
        _fallAt(centreX, centreY, "enemy")
    }

    // It falls with its centre at (x, y): it stops, lies restTime seconds
    // and is gone
    function fallAt(x, y, how) { _fallAt(x, y, how) }
    function _fallAt(x, y, how) {
        if (destroyed || fallen) return
        fallen = true
        _put(x, y)
        body.linearVelocity = Qt.point(0, 0)
        fadeOut.start()
        rest.start()
        fell(how)
    }

    // Gone at once, without falling
    function vanish() {
        if (destroyed) return
        destroyed = true
        gone()
        destroy()
    }
}
