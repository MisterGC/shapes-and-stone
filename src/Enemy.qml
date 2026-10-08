import QtQuick
import Box2D
import Clayground.Physics
import Clayground.Behavior
import Clayground.Network

PhysicsItem {
    id: enemy
    objectName: "enemy"

    property var gameWorld: null

    Component.onCompleted: {
        console.log("[Enemy] Created - xWu:", xWu, "yWu:", yWu)
        _spawnXWu = xWu
        _spawnYWu = yWu
    }

    property bool destroyed: false

    // In a session the host runs every enemy and the other nodes show it
    // (issue #13): objectId is its replicated object, network the session's
    // Network, and remote is true where another node runs its AI. A remote
    // enemy is moved by the host's states and passes this node's knight's
    // blows on to the host.
    property string objectId: ""
    property var network: null
    property bool remote: false
    // How far in the past a remote enemy is shown, in ms
    readonly property real renderDelayMs: replica.interpolator.effectiveDelayMs
    // The AI thinks here: only where the enemy is not remote
    readonly property bool thinks: aiTimer.running

    // The host sends a state when one of these changes; a remote enemy
    // renders them in the past by the delay the interpolator sizes from
    // the jitter it sees (autoDelay), as RemotePlayer does; the stop and
    // settle copies of an enemy that stands and is hit no longer stretch
    // it (clayground#374). An enemy that stops dead (a lunge lands, a
    // stagger) stops in place on the other screens: clayground sends its
    // last state once more right after the stop.
    ReplicatedObject {
        id: replica
        network: enemy.network
        objectId: enemy.objectId
        properties: ["xWu", "yWu", "aiState", "facingAngle", "hp", "parryWindow", "targetId",
                     "windUpLength"]
        interpolate: true
        interpolator.autoDelay: true
        // HP switches with its state, never blended between two of the
        // host's (clayground#368); so does a wind-up's length
        steppedProperties: ["hp", "windUpLength"]
        interpolator.angleKeys: ["facingAngle"]
    }

    widthWu: 0.8
    heightWu: 0.8

    bodyType: remote ? Body.Kinematic : Body.Dynamic
    fixedRotation: true
    gravityScale: 0

    property alias categories: collider.categories
    property alias collidesWith: collider.collidesWith
    property alias sensor: collider.sensor

    // AI target
    property var target: null
    // The node whose knight the target is, the same on every screen; ""
    // without a session or a target
    property string targetId: ""

    // Set by halt() when the knight has fallen: the AI stays idle for good
    property bool halted: false

    // Tier: 0=weak, 1=normal, 2=tough
    property int tier: 1
    property string enemyType: "grunt"  // "grunt", "guardian", or "spitter"
    property real facingAngle: 0          // Guardian tracks player direction
    readonly property real shieldArc: Balance.enemy.shieldArc
    readonly property real shieldRotSpeed: Balance.enemy.shieldTurnSpeed

    // Stats, from the balance table; hp, atk and def are set on spawn
    readonly property var _typeStats: Balance.enemy[enemyType] || Balance.enemy.grunt
    readonly property real chaseSpeed: _typeStats.chaseSpeed
    readonly property real patrolSpeed: _typeStats.patrolSpeed
    property real _lungeSpeed: 0  // Calculated per attack
    readonly property real windUpSpeed: Balance.enemy.windUpSpeed
    readonly property real windUpDuration: Balance.enemy.windUp
    readonly property real lungeDuration: Balance.enemy.lungeDuration
    readonly property real lungeRange: Balance.enemy.lungeRange
    property int hp: Balance.enemy.tierHp[1]
    property int maxHp: Balance.enemy.tierHp[1]
    property int atk: Balance.enemy.grunt.atk
    property int def: Balance.enemy.grunt.def

    // Spitter-specific
    readonly property real preferredDist: Balance.enemy.preferredDist
    readonly property real shootRange: Balance.enemy.shootRange
    readonly property real kiteSpeed: Balance.enemy.kiteSpeed
    readonly property real shootCooldown: Balance.enemy.shootCooldown
    property real _shootTimer: 0

    // Combat state
    property real attackCooldown: 0
    property real _attackTimer: 0
    property real _dirToTargetX: 0
    property real _dirToTargetY: 0
    property bool parryWindow: false
    property int _lungeSteps: 0     // physics steps until the lunge lands

    // AI state: patrol, chase, telegraph, lunge, stagger, recovery, kite, shoot
    property string aiState: "patrol"

    // The parry ring (issue #78): while it winds up, a ring closes on it
    // and reaches its outline on the step the lunge's parry window opens,
    // or as a shot leaves. ringProgress runs from 0 to 1 on the physics
    // steps, so a pause or a hit stop holds it. windUpLength is the
    // telegraph or shot wind-up under way, in seconds, sent to the other
    // screens: there the ring counts its own steps from the host's
    // telegraph and closes when the host's parryWindow opens
    property real windUpLength: 0
    property real _ringT: 0
    // The step length the ring counts a lunge's steps in: the world's at
    // the start of the wind-up, never 0 as it is in a full hit stop
    property real _ringStep: 1 / 60
    readonly property bool ringShows: aiState === "telegraph" || aiState === "shoot"
                                      || aiState === "lunge"
    readonly property color ringColor: parryWindow ? Balance.parryRing.flashColor
        : enemyType === "spitter" ? "#F2D13A" : "#FF8C00"
    // Seconds of a lunge after its first step until the parry window opens
    readonly property real _ringLunge: aiState === "shoot" ? 0
        : Math.max(0, lungeStepCount(_ringStep) - 1 - Balance.enemy.parryFrames) * _ringStep
    readonly property real ringProgress: {
        if (!ringShows) return 0
        if (parryWindow) return 1
        let total = windUpLength + _ringLunge
        if (total <= 0) return 1
        let left = remote ? total - _ringT
            : aiState === "lunge" ? Math.max(0, _lungeSteps - Balance.enemy.parryFrames) * _ringStep
            : _attackTimer + _ringLunge
        return Math.max(0, Math.min(1, 1 - left / total))
    }
    Connections {
        target: enemy.world
        enabled: enemy.remote && enemy.ringShows
        function onStepped() { enemy._ringT += enemy.world.timeStep }
    }

    // Internal state
    property real _spawnXWu: 0
    property real _spawnYWu: 0
    property var _lastKnownTargetPos: null
    property real _pathRecalcTimer: 0

    // Contact shadow: grounds the shape on the floor
    Rectangle {
        z: -1
        visible: enemy._fx
        width: parent.width * 0.92
        // Kept inside the body's bounds: a child reaching outside inflates
        // childrenRect and skews the physics debug draw
        height: parent.height * 0.32
        radius: height / 2
        x: (parent.width - width) / 2
        y: parent.height * 0.68
        color: "#000000"
        opacity: 0.38
    }

    // Tough enemy glow ring
    Rectangle {
        visible: tier === 2
        anchors.centerIn: parent
        width: parent.width * 1.4
        height: parent.height * 1.4
        radius: width * 0.5
        color: "transparent"
        border.color: "#CC6644"
        border.width: 2
        opacity: 0.6
    }

    // Life: breathing at rest, a bob while moving (visual only)
    property real _lifeT: Math.random() * 10
    NumberAnimation on _lifeT {
        running: enemy._fx
        from: enemy._lifeT; to: enemy._lifeT + 1000; duration: 1000000
        loops: Animation.Infinite
    }
    readonly property real _speed: enemy.linearVelocity
        ? Math.min(1, Math.sqrt(enemy.linearVelocity.x * enemy.linearVelocity.x
                                + enemy.linearVelocity.y * enemy.linearVelocity.y) / 3) : 0
    readonly property real _breath: Math.sin(_lifeT * 2.1) * (1 - _speed)
    readonly property real _bob: Math.abs(Math.sin(_lifeT * 12)) * _speed

    // Visual
    Rectangle {
        id: visual
        transform: [
            Scale {
                origin.x: visual.width / 2; origin.y: visual.height
                xScale: enemy._fx ? 1 - 0.025 * enemy._breath + 0.03 * enemy._bob : 1
                yScale: enemy._fx ? 1 + 0.035 * enemy._breath - 0.05 * enemy._bob : 1
            },
            Translate { y: enemy._fx ? -enemy._bob * visual.height * 0.06 : 0 }
        ]
        anchors.centerIn: parent
        anchors.fill: parent
        radius: width * .5
        opacity: tier === 0 ? 0.6 : 1.0
        color: {
            let isSpitter = enemyType === "spitter"
            let base
            switch (enemy.aiState) {
            case "patrol": base = isSpitter ? "#6B8E4A" : "#8B3A3A"; break
            case "chase": base = isSpitter ? "#7BA854" : "#CC4444"; break
            case "kite": base = "#8EBB5A"; break
            // A spitter winding up its shot turns warm yellow: an attack
            // coming, like the melee telegraph, and far from its kiting green
            case "shoot": base = "#F2D13A"; break
            case "telegraph": base = "#FF8C00"; break
            case "lunge": base = "#FF4444"; break
            case "stagger": base = "#666666"; break
            default: base = isSpitter ? "#6B8E4A" : "#8B3A3A"
            }
            return tier === 0 ? Qt.darker(base, 1.4) : tier === 2 ? Qt.lighter(base, 1.2) : base
        }
        Behavior on color { ColorAnimation { duration: 100 } }

        BodyShade {
            visible: enemy._fx
            baseColor: visual.color
        }

        Canvas {
            id: goblinIcon
            anchors.centerIn: parent
            width: parent.width * 0.7
            height: parent.height * 0.7
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width, h = height
                var dark = Qt.darker(visual.color, 1.8)
                ctx.fillStyle = dark
                ctx.strokeStyle = dark
                ctx.lineWidth = w * 0.06

                if (enemyType === "spitter") {
                    // Big central eye
                    ctx.beginPath()
                    ctx.arc(w * 0.5, h * 0.4, w * 0.22, 0, Math.PI * 2)
                    ctx.fill()
                    // Pupil (lighter)
                    ctx.fillStyle = visual.color
                    ctx.beginPath()
                    ctx.arc(w * 0.5, h * 0.4, w * 0.1, 0, Math.PI * 2)
                    ctx.fill()
                    // Open mouth (spitting)
                    ctx.fillStyle = dark
                    ctx.beginPath()
                    ctx.arc(w * 0.5, h * 0.72, w * 0.14, 0, Math.PI * 2)
                    ctx.fill()
                } else {
                    // Pointy ears
                    ctx.beginPath()
                    ctx.moveTo(w * 0.05, h * 0.45)
                    ctx.lineTo(w * -0.05, h * 0.05)
                    ctx.lineTo(w * 0.25, h * 0.35)
                    ctx.closePath()
                    ctx.fill()

                    ctx.beginPath()
                    ctx.moveTo(w * 0.95, h * 0.45)
                    ctx.lineTo(w * 1.05, h * 0.05)
                    ctx.lineTo(w * 0.75, h * 0.35)
                    ctx.closePath()
                    ctx.fill()

                    // Eyes
                    ctx.beginPath()
                    ctx.arc(w * 0.33, h * 0.42, w * 0.09, 0, Math.PI * 2)
                    ctx.fill()
                    ctx.beginPath()
                    ctx.arc(w * 0.67, h * 0.42, w * 0.09, 0, Math.PI * 2)
                    ctx.fill()

                    // Jagged mouth
                    ctx.beginPath()
                    ctx.moveTo(w * 0.25, h * 0.7)
                    ctx.lineTo(w * 0.35, h * 0.62)
                    ctx.lineTo(w * 0.45, h * 0.72)
                    ctx.lineTo(w * 0.55, h * 0.62)
                    ctx.lineTo(w * 0.65, h * 0.72)
                    ctx.lineTo(w * 0.75, h * 0.62)
                    ctx.stroke()
                }
            }

            Connections {
                target: visual
                function onColorChanged() { goblinIcon.requestPaint() }
            }
        }
    }

    // Squash on a hit, crouch while winding up, stretch into the lunge
    property real _poseScale: !_fx ? 1
        : aiState === "telegraph" || aiState === "shoot" ? 0.8
        : aiState === "lunge" ? 1.15 : 1
    Behavior on _poseScale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
    property real _squash: 1
    SequentialAnimation {
        id: hitSquash
        NumberAnimation { target: enemy; property: "_squash"; to: 0.7; duration: 40 }
        NumberAnimation { target: enemy; property: "_squash"; to: 1; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 3 }
    }
    Binding { target: visual; property: "scale"; value: enemy._poseScale * enemy._squash }

    // Eyes that glow in the dark: drawn above the darkness, so an enemy
    // beyond the light is a pair of eyes coming closer. They sit on the
    // icon's eyes and blink now and then.
    Item {
        id: glowEyes
        parent: enemy._fx && gameWorld && gameWorld.glowParent ? gameWorld.glowParent() : enemy
        visible: enemy._fx && enemy.aiState !== "stagger"
        x: parent === enemy ? 0 : enemy.x
        y: parent === enemy ? 0 : enemy.y
        width: enemy.width
        height: enemy.height
        scale: visual.scale
        readonly property bool spitter: enemy.enemyType === "spitter"
        readonly property color eyeColor: spitter ? "#D8FF80"
            : enemy.aiState === "telegraph" || enemy.aiState === "lunge" ? "#FFF2C0" : "#FFB040"
        property real open: 1
        SequentialAnimation on open {
            loops: Animation.Infinite
            PauseAnimation { duration: 2200 + Math.random() * 2600 }
            NumberAnimation { to: 0.1; duration: 60 }
            NumberAnimation { to: 1; duration: 90 }
        }
        Repeater {
            model: glowEyes.spitter ? [0.5] : [0.381, 0.619]
            Item {
                required property var modelData
                x: enemy.width * modelData
                y: enemy.height * 0.44
                // Halo, then the eye itself
                Rectangle {
                    width: enemy.width * (glowEyes.spitter ? 0.5 : 0.36)
                    height: width * (0.4 + 0.6 * glowEyes.open)
                    radius: width / 2
                    x: -width / 2; y: -height / 2
                    color: glowEyes.eyeColor
                    opacity: 0.18
                }
                Rectangle {
                    width: enemy.width * (glowEyes.spitter ? 0.18 : 0.13)
                    height: width * glowEyes.open
                    radius: width / 2
                    x: -width / 2; y: -height / 2
                    color: glowEyes.eyeColor
                }
            }
        }
    }

    Rectangle {
        id: hitFlash
        anchors.fill: visual
        radius: visual.radius
        scale: visual.scale
        color: "white"
        opacity: 0
        SequentialAnimation {
            id: hitFlashAnimation
            PropertyAnimation {
                target: hitFlash; property: "opacity"
                from: 0.8; to: 0; duration: 150
                easing.type: Easing.OutQuad
            }
        }
    }

    // Parry window flash
    Rectangle {
        id: parryFlash
        anchors.fill: visual
        radius: visual.radius
        color: "white"
        opacity: parryWindow ? 0.4 : 0
        Behavior on opacity { NumberAnimation { duration: 50 } }
    }

    // The parry ring: above the darkness with fx on, as the eyes are, in
    // the telegraph colour, white while the parry window is open
    Rectangle {
        id: parryRing
        objectName: "parryRing"
        parent: enemy._fx && gameWorld && gameWorld.glowParent ? gameWorld.glowParent() : enemy
        visible: enemy.ringShows
        readonly property real size: enemy.width * visual.scale
            * (Balance.parryRing.from - (Balance.parryRing.from - 1) * enemy.ringProgress)
        width: size
        height: size
        radius: size / 2
        x: (parent === enemy ? 0 : enemy.x) + (enemy.width - size) / 2
        y: (parent === enemy ? 0 : enemy.y) + (enemy.height - size) / 2
        color: "transparent"
        border.width: Math.max(1.5, enemy.width * Balance.parryRing.thickness)
        border.color: enemy.ringColor
        opacity: Balance.parryRing.opacity
    }

    // Stagger wobble animation
    SequentialAnimation {
        id: staggerWobble
        loops: Animation.Infinite
        PropertyAnimation { target: enemy; property: "rotation"; to: 10; duration: 80 }
        PropertyAnimation { target: enemy; property: "rotation"; to: -10; duration: 80 }
    }

    // Health bar
    Rectangle {
        id: healthBarBg
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 4
        width: parent.width * 1.2
        height: 4
        color: "#333333"
        visible: hp < maxHp

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * (hp / maxHp)
            color: hp > maxHp * 0.5 ? "#22CC22" : (hp > maxHp * 0.25 ? "#CCCC22" : "#CC2222")
            Behavior on width { NumberAnimation { duration: 100 } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    // Guardian shield arc
    Canvas {
        id: guardianShield
        visible: enemyType === "guardian" && aiState !== "stagger"
        readonly property real shieldSize: enemy.width * 0.8
        readonly property real orbitRadius: enemy.width * 0.5
        readonly property real angleRad: facingAngle * Math.PI / 180
        width: shieldSize
        height: shieldSize
        x: enemy.width / 2 - width / 2 + Math.cos(angleRad) * orbitRadius
        y: enemy.height / 2 - height / 2 - Math.sin(angleRad) * orbitRadius
        rotation: -facingAngle
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height
            ctx.beginPath()
            ctx.arc(w / 2, h / 2, w * 0.4, -Math.PI * 0.4, Math.PI * 0.4)
            ctx.strokeStyle = "#CC6644"
            ctx.lineWidth = w * 0.25
            ctx.stroke()
        }

        Connections {
            target: enemy
            function onFacingAngleChanged() { guardianShield.requestPaint() }
        }
        Component.onCompleted: requestPaint()
    }

    // Mechanics debug hint
    Text {
        visible: gameWorld ? gameWorld.debugMechanics : false
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: hp < maxHp ? 14 : 6
        text: enemyType === "guardian" ? "Flank/Push" : (enemyType === "spitter" ? "Close/Shield" : "Block/Counter")
        color: enemyType === "guardian" ? "#CC6644" : (enemyType === "spitter" ? "#6B8E4A" : "#AAAAAA")
        font.pixelSize: 9
        font.bold: true
        style: Text.Outline
        styleColor: "#000000"
    }

    fixtures: [
        Circle {
            id: collider
            radius: enemy.width * 0.35
            x: enemy.width / 2
            y: enemy.height / 2
            density: 1.0
            friction: 0.0
            restitution: 0.0
            onBeginContact: (other) => enemy.onCollision(other)
        }
    ]

    // FollowPath for both patrol and chase navigation
    // Manage FollowPath.running imperatively — a declarative binding gets
    // broken by FollowPath's internal "running = false" on path completion.
    onAiStateChanged: {
        followPath.running = !remote && (aiState === "patrol" || aiState === "chase")
        // A wind-up starts the parry ring: its length where the AI runs, a
        // count of steps where it is shown
        if (aiState === "telegraph" || aiState === "shoot") {
            if (world && world.timeStep > 0) _ringStep = world.timeStep
            if (remote) _ringT = 0
            else windUpLength = _attackTimer
        }
        // A remote enemy wobbles while the host's staggers
        if (remote) {
            if (aiState === "stagger") staggerWobble.restart()
            else if (staggerWobble.running) { staggerWobble.stop(); rotation = 0 }
        }
    }
    // A remote enemy flashes when the host's loses HP, unless this node's
    // knight struck it a moment ago and it flashes already
    property int _shownHp: hp
    onHpChanged: {
        if (remote && hp < _shownHp && !hitFlashAnimation.running) {
            hitFlashAnimation.restart()
            if (_fx) hitSquash.restart()
        }
        _shownHp = hp
    }
    onEnemyTypeChanged: goblinIcon.requestPaint()

    FollowPath {
        id: followPath
        world: enemy.gameWorld
        actor: enemy
        debug: gameWorld ? gameWorld.debugBehavior : false
        desiredSpeed: enemy.aiState === "chase" ? enemy.chaseSpeed : enemy.patrolSpeed
        repeat: enemy.aiState === "patrol"
        onArrived: {
            if (enemy.aiState === "chase") {
                if (target && gameWorld && gameWorld.hasLineOfSight(xWu, yWu, target.xWu, target.yWu)) {
                    _recalcChasePath()
                    followPath.running = true
                } else {
                    console.log("[Enemy] Lost target, returning to patrol")
                    aiState = "patrol"
                    _setupPatrol()
                }
            }
        }
    }

    // The AI thinks on the game clock: a pause, a single step or a hit stop
    // holds a telegraph, a lunge or a cooldown with the world (issue #33)
    PhysicsTimer {
        id: aiTimer
        world: enemy.world
        interval: Balance.enemy.thinkInterval * 1000
        running: !enemy.remote
        repeat: true
        onTriggered: updateAI(interval / 1000.0)
    }

    // Knockback: a shove along the blow that the AI does not steer against
    // until it has died down (README: "push 0.25 tiles in hit direction").
    readonly property bool _fx: gameWorld ? gameWorld.fx === true : false
    property real _lastHitDx: 0
    property real _lastHitDy: 0
    property real _knockT: 0
    property real _knockVx: 0
    property real _knockVy: 0
    readonly property real knockDuration: Balance.enemy.knockbackDuration
    function knockback(dx, dy, speed) {
        let len = Math.sqrt(dx * dx + dy * dy)
        if (len < 0.001) return
        _knockVx = dx / len * speed
        _knockVy = dy / len * speed
        _knockT = knockDuration
        followPath.running = false
        hitSquash.restart()
    }
    Connections {
        target: enemy.world
        enabled: enemy._knockT > 0
        function onStepped() {
            let k = enemy._knockT / enemy.knockDuration
            enemy.body.linearVelocity = Qt.point(enemy._knockVx * k, -enemy._knockVy * k)
            enemy._knockT -= enemy.world.timeStep
            if (enemy._knockT <= 0) {
                enemy._knockT = 0
                enemy.body.linearVelocity = Qt.point(0, 0)
                followPath.running = (enemy.aiState === "patrol" || enemy.aiState === "chase")
            }
        }
    }

    // A shove along (dx, dy) at speed, from the knight's shield push. It
    // runs as a knockback: a velocity set once lasted only until the AI's
    // next think, which stops an enemy in recovery or stagger, so the
    // shove went anywhere from 0 to 2 Wu
    function shove(dx, dy, speed) {
        if (remote) {
            if (gameWorld) gameWorld.strikeEnemy(enemy, {kind: "push", dx: dx, dy: dy, speed: speed})
            return
        }
        knockback(dx, dy, speed)
    }

    // An attack runs on the physics steps, not on the AI's think ticks: a
    // telegraph lasts its wind-up to the step, and the parry window is open
    // for exactly Balance.enemy.parryFrames steps (issue #35)
    Connections {
        target: enemy.world
        enabled: !enemy.halted && !enemy.remote
        function onStepped() { enemy._stepAttack(enemy.world.timeStep) }
    }

    // Seconds a telegraph of this length is drawn out to
    function telegraphTime(seconds) {
        return Math.max(Balance.enemy.minTelegraph, seconds)
    }

    function _stepAttack(dt) {
        if (_knockT > 0) return
        // Counted down per step; what is left of a step's rounding is none
        if (_attackTimer > 0)
            _attackTimer = _attackTimer - dt < 1e-6 ? 0 : _attackTimer - dt
        switch (aiState) {
        case "telegraph":
            if (_attackTimer <= 0) _startLunge()
            break
        case "shoot":
            if (_attackTimer <= 0) {
                fireProjectile()
                aiState = "kite"
            }
            break
        case "lunge":
            _stepLunge()
            break
        }
    }

    function _startLunge() {
        if (!target) {
            aiState = "chase"
            return
        }
        // Lunge speed to reach the knight where it stands now
        let lungeDx = target.xWu - xWu
        let lungeDy = target.yWu - yWu
        let lungeDist = Math.sqrt(lungeDx * lungeDx + lungeDy * lungeDy)
        let len = Math.max(0.01, lungeDist)
        _dirToTargetX = lungeDx / len
        _dirToTargetY = lungeDy / len
        _lungeSpeed = lungeDist / lungeDuration
        _lungeSteps = lungeStepCount(world.timeStep)
        aiState = "lunge"
        _stepLunge()
    }

    // Physics steps a lunge takes at steps of this length, the first one
    // included
    function lungeStepCount(step) {
        return Math.max(1, Math.round(lungeDuration / step))
    }

    // Dash forward, the last parryFrames steps open to a parry, then land
    function _stepLunge() {
        // Negate Y for world-to-screen
        body.linearVelocity = Qt.point(
            _dirToTargetX * _lungeSpeed,
            -_dirToTargetY * _lungeSpeed)
        _lungeSteps--
        if (_lungeSteps > 0) {
            parryWindow = _lungeSteps <= Balance.enemy.parryFrames
            return
        }
        parryWindow = false
        body.linearVelocity = Qt.point(0, 0)
        performAttack()
        // A blow blocked perfectly staggered it: no recovery over that
        if (aiState !== "lunge") return
        aiState = "recovery"
        attackCooldown = Balance.enemy.recovery
    }

    // The knight has fallen: drop the target, stand still and stop thinking.
    // A lunge or shot still winding up never lands.
    function halt() {
        halted = true
        target = null
        aiState = "idle"
        staggerWobble.stop()
        rotation = 0
        body.linearVelocity = Qt.point(0, 0)
    }

    // Its knight's player left the session: the knight is gone, and so is
    // an attack wound up against it. The next think picks the nearest
    // knight still there
    function dropTarget() {
        target = null
        targetId = ""
        parryWindow = false
        _attackTimer = 0
        if (["telegraph", "lunge", "shoot", "chase", "kite"].indexOf(aiState) >= 0) {
            aiState = "patrol"
            followPath.running = false
            followPath.wpsWu = []
            if (_knockT <= 0) body.linearVelocity = Qt.point(0, 0)
        }
    }

    function updateAI(dt) {
        if (halted) return
        if (_knockT > 0) return
        // In a session it goes for the nearest knight still standing; an
        // attack under way stays on the knight it wound up against
        if (gameWorld && gameWorld.enemiesChooseTarget
            && aiState !== "telegraph" && aiState !== "lunge" && aiState !== "shoot") {
            target = gameWorld.nearestKnight(xWu, yWu)
            targetId = gameWorld.knightIdOf(target)
        }
        if (!target || !gameWorld) {
            aiState = "patrol"
            return
        }

        if (attackCooldown > 0) attackCooldown -= dt
        if (_shootTimer > 0) _shootTimer -= dt
        _pathRecalcTimer -= dt

        let dx = target.xWu - xWu
        let dy = target.yWu - yWu
        let dist = Math.sqrt(dx * dx + dy * dy)
        let canSee = gameWorld.hasLineOfSight(xWu, yWu, target.xWu, target.yWu)

        switch (aiState) {
        case "patrol":
            if (canSee) {
                console.log("[Enemy] Spotted player!")
                aiState = "chase"
                _recalcChasePath()
            } else if (followPath.wpsWu.length === 0) {
                _setupPatrol()
            } else if (!followPath.running) {
                followPath.running = true
            }
            break

        case "chase":
            if (enemyType === "spitter") {
                // Spitter transitions to kite when in range with LOS
                if (canSee && dist < shootRange) {
                    aiState = "kite"
                } else if (_pathRecalcTimer <= 0) {
                    _recalcChasePath()
                    _pathRecalcTimer = Balance.enemy.repathInterval
                }
            } else {
                if (enemyType === "guardian") _lerpFacing(dy, dx, dt)
                if (dist < lungeRange && canSee) {
                    // Capture direction to target for wind-up/lunge
                    let len = Math.max(0.01, dist)
                    _dirToTargetX = dx / len
                    _dirToTargetY = dy / len
                    _attackTimer = telegraphTime(windUpDuration)
                    aiState = "telegraph"
                } else if (_pathRecalcTimer <= 0) {
                    _lastKnownTargetPos = Qt.point(target.xWu, target.yWu)
                    _recalcChasePath()
                    _pathRecalcTimer = Balance.enemy.repathInterval
                }
            }
            break

        case "kite":
            // Spitter: maintain distance, retreat if too close, advance if too far
            if (!canSee) {
                aiState = "chase"
                _recalcChasePath()
                break
            }
            {
                let len = Math.max(0.01, dist)
                let ndx = dx / len
                let ndy = dy / len
                if (dist < preferredDist * Balance.enemy.tooClose) {
                    // Too close — retreat
                    body.linearVelocity = Qt.point(
                        -ndx * kiteSpeed, ndy * kiteSpeed)
                } else if (dist > preferredDist * Balance.enemy.tooFar) {
                    // Too far — approach
                    body.linearVelocity = Qt.point(
                        ndx * chaseSpeed, -ndy * chaseSpeed)
                } else {
                    // Good range — strafe slightly
                    body.linearVelocity = Qt.point(
                        -ndy * patrolSpeed, -ndx * patrolSpeed)
                }
            }
            // Shoot when cooldown ready
            if (_shootTimer <= 0 && dist <= shootRange) {
                _shootTimer = shootCooldown
                _attackTimer = telegraphTime(Balance.enemy.shootWindUp)
                let len = Math.max(0.01, dist)
                _dirToTargetX = dx / len
                _dirToTargetY = dy / len
                aiState = "shoot"
            }
            break

        case "shoot":
            // Holds still while the shot winds up; _stepAttack fires it
            body.linearVelocity = Qt.point(0, 0)
            break

        case "telegraph":
            // Pull backward (wind-up) — negate Y for world-to-screen;
            // _stepAttack starts the lunge, which it also runs
            body.linearVelocity = Qt.point(
                -_dirToTargetX * windUpSpeed,
                _dirToTargetY * windUpSpeed)
            break

        case "stagger":
            body.linearVelocity = Qt.point(0, 0)
            if (_attackTimer <= 0) {
                staggerWobble.stop()
                enemy.rotation = 0
                aiState = "chase"
            }
            break

        case "recovery":
            body.linearVelocity = Qt.point(0, 0)
            if (enemyType === "guardian") _lerpFacing(dy, dx, dt)
            if (attackCooldown <= 0)
                aiState = "chase"
            break
        }
    }

    function _lerpFacing(dy, dx, dt) {
        let targetAngle = Math.atan2(dy, dx) * 180 / Math.PI
        let diff = targetAngle - facingAngle
        while (diff > 180) diff -= 360
        while (diff < -180) diff += 360
        let maxRot = shieldRotSpeed * dt
        facingAngle += Math.max(-maxRot, Math.min(maxRot, diff))
    }

    function _recalcChasePath() {
        if (!target || !gameWorld) return
        let path = gameWorld.findPath(xWu, yWu, target.xWu, target.yWu)
        if (path.length > 1) {
            // Skip first waypoint (our current cell)
            followPath.wpsWu = path.slice(1)
        } else if (path.length === 1) {
            followPath.wpsWu = path
        }
        // If no path found, keep current path (or stop)
    }

    function _setupPatrol() {
        // Patrol near spawn point: 2-3 waypoints in a small area
        let r = Balance.enemy.patrolRadius
        let offsets = [
            Qt.point(_spawnXWu - r, _spawnYWu),
            Qt.point(_spawnXWu + r, _spawnYWu),
            Qt.point(_spawnXWu, _spawnYWu + r),
            Qt.point(_spawnXWu, _spawnYWu - r)
        ]
        // Pick 2 random reachable offsets
        let wps = []
        for (let p of offsets) {
            if (gameWorld) {
                let gx = Math.floor(p.x / gameWorld.cellSize)
                let gy = Math.floor(p.y / gameWorld.cellSize)
                if (gx >= 0 && gx < gameWorld.gridWidth &&
                    gy >= 0 && gy < gameWorld.gridHeight &&
                    gameWorld.grid[gy][gx] !== gameWorld.cellWall) {
                    wps.push(p)
                }
            }
            if (wps.length >= 2) break
        }
        if (wps.length >= 2)
            followPath.wpsWu = wps
    }

    function performAttack() {
        // Another node's knight: that node checks the reach and takes the hit
        if (target && !target.takeDamage && target.nodeId !== undefined) {
            if (gameWorld) gameWorld.strikeKnight(target, enemy, atk, xWu, yWu)
            return
        }
        if (target && target.takeDamage) {
            let dx = target.xWu - xWu
            let dy = target.yWu - yWu
            let dist = Math.sqrt(dx * dx + dy * dy)
            if (dist < Balance.enemy.lungeHitRange) {
                let result = target.takeDamage(atk, xWu, yWu, widthWu)
                // A blocked blow throws it back, a perfect block staggers
                // it; the knight sounds its own block or hurt, so the
                // lunge plays nothing here
                if (result === "blocked") recoil(target)
                if (result === "perfect") stagger(Balance.knight.perfectBlockStagger)
                if (result !== "hit") return
                console.log("[Enemy] Lunge hit! Dealt", atk, "damage")
            }
        }
    }

    // Thrown back off a knight's shield that stopped its blow, by
    // Balance.block.recoil wu. A knockback fades out step by step, so it
    // covers speed times the sum of its steps' shares of the speed
    function recoil(knight) {
        if (Balance.block.recoil <= 0) return
        let dt = world.timeStep, per = 0
        for (let t = knockDuration; t > 1e-9; t -= dt) per += t / knockDuration * dt
        shove(xWu - knight.xWu, yWu - knight.yWu, Balance.block.recoil / per)
    }

    function fireProjectile() {
        if (gameWorld && gameWorld.spawnProjectile) {
            gameWorld.spawnProjectile(xWu, yWu, _dirToTargetX, _dirToTargetY, atk)
            if (gameWorld.playSpitShot) gameWorld.playSpitShot()
            console.log("[Enemy] Spitter fired projectile!")
        }
    }

    // Staggered for seconds, for the table's enemy.stagger without them
    function stagger(seconds) {
        let t = seconds === undefined ? Balance.enemy.stagger : seconds
        if (remote) {
            if (gameWorld) gameWorld.strikeEnemy(enemy, {kind: "stagger", seconds: t})
            return
        }
        parryWindow = false
        _attackTimer = t
        aiState = "stagger"
        staggerWobble.restart()
    }

    function onCollision(other) {}

    function _isShieldFacing(attackerX, attackerY) {
        let dx = attackerX - xWu
        let dy = attackerY - yWu
        let angleToAttacker = Math.atan2(dy, dx) * 180 / Math.PI
        let angleDiff = angleToAttacker - facingAngle
        while (angleDiff > 180) angleDiff -= 360
        while (angleDiff < -180) angleDiff += 360
        return Math.abs(angleDiff) <= shieldArc
    }

    // What a blow of amount from (attackerX, attackerY) does: the damage
    // and whether a guardian's shield took it. A heavy blow (the knight's
    // charged swing) goes through the shield
    function _blow(amount, attackerX, attackerY, heavy) {
        let finalDamage = Math.max(Balance.minDamage, amount - def)
        // Guardian frontal shield
        let blocked = false
        if (enemyType === "guardian" && aiState !== "stagger" && heavy !== true
            && attackerX !== undefined && _isShieldFacing(attackerX, attackerY)) {
            finalDamage = Math.floor(finalDamage * Balance.enemy.blockedShare)
            blocked = true
        }
        return {damage: finalDamage, blocked: blocked}
    }

    // The impact a blow makes: a heavy one its own
    function _hitKind(blocked, heavy) {
        return blocked ? "enemyBlocked" : heavy === true ? "heavyHit" : "enemyHit"
    }

    // This node's knight struck the enemy; heavy for its charged swing
    function takeDamage(amount, attackerX, attackerY, heavy) {
        if (!remote) {
            _takeBlow(amount, attackerX, attackerY, "", heavy)
            return
        }
        // Remote: the hit looks and counts here, the host applies it
        let b = _blow(amount, attackerX, attackerY, heavy)
        let hdx = attackerX !== undefined ? xWu - attackerX : 0
        let hdy = attackerY !== undefined ? yWu - attackerY : 0
        if (gameWorld) {
            gameWorld.countFight("dealt", b.damage)
            gameWorld.impact(_hitKind(b.blocked, heavy), xWu, yWu, hdx, hdy, visual.color)
            gameWorld.strikeEnemy(enemy, {kind: "damage", amount: amount, x: attackerX, y: attackerY,
                                          heavy: heavy === true})
        }
        hitFlashAnimation.restart()
        if (_fx) hitSquash.restart()
    }

    // Host: the knight of node byId struck the enemy; that node drew the
    // hit and counted it
    function takeRemoteBlow(amount, attackerX, attackerY, byId, heavy) {
        _takeBlow(amount, attackerX, attackerY, byId, heavy)
    }

    // A blow from this node's knight (byId "") or another node's
    function _takeBlow(amount, attackerX, attackerY, byId, heavy) {
        let b = _blow(amount, attackerX, attackerY, heavy)
        let finalDamage = b.damage
        let blocked = b.blocked
        let own = byId === ""

        hp = Math.max(0, hp - finalDamage)
        if (gameWorld && own) gameWorld.countFight("dealt", finalDamage)
        console.log("[Enemy] Took", finalDamage, "damage, HP:", hp, blocked ? "(blocked)" : "")
        hitFlashAnimation.restart()
        let hdx = attackerX !== undefined ? xWu - attackerX : 0
        let hdy = attackerY !== undefined ? yWu - attackerY : 0
        _lastHitDx = hdx
        _lastHitDy = hdy
        if (gameWorld && own) {
            if (gameWorld.impact)
                gameWorld.impact(_hitKind(blocked, heavy), xWu, yWu, hdx, hdy, visual.color)
            else
                gameWorld.shake(blocked ? 0.5 : 1.5)
        }
        if (!blocked && hp > 0 && _fx)
            knockback(hdx, hdy, Balance.enemy.knockbackSpeed
                                * (heavy === true ? Balance.knight.heavyKnockback : 1))

        // Guardian counter-attacks after blocking
        if (blocked && aiState !== "telegraph" && aiState !== "lunge") {
            if (target) {
                let dx = target.xWu - xWu
                let dy = target.yWu - yWu
                let len = Math.max(0.01, Math.sqrt(dx * dx + dy * dy))
                _dirToTargetX = dx / len
                _dirToTargetY = dy / len
                // Faster counter, but no shorter than any telegraph
                _attackTimer = telegraphTime(windUpDuration * Balance.enemy.counterWindUp)
                aiState = "telegraph"
            }
        }

        // Getting hit while patrolling triggers chase
        if (aiState === "patrol" && target) {
            console.log("[Enemy] Hit while patrolling — chasing attacker!")
            aiState = "chase"
            _recalcChasePath()
        }

        if (hp <= 0) die(byId)
    }

    // byId: the node whose knight killed it, "" for this node's
    function die(byId) {
        console.log("[Enemy] Died!")
        let own = !byId
        if (gameWorld && own) {
            if (gameWorld.impact)
                gameWorld.impact("enemyDeath", xWu, yWu, _lastHitDx, _lastHitDy, visual.color)
            else
                gameWorld.spawnDeathParticles(xWu, yWu)
            gameWorld.playDeathBurst()
        }
        destroyed = true
        // Gold where it fell; in a session only the host's enemies die here
        if (gameWorld && gameWorld.dropGold && !remote) gameWorld.dropGold(xWu, yWu, tier)
        if (gameWorld) {
            // The killer's node draws the death and counts the kill
            if (own) gameWorld.countFight("kill")
            else gameWorld.reportKill(byId, enemy, _lastHitDx, _lastHitDy, String(visual.color))
        }
        // A replicated enemy goes on every node; Game destroys this item
        if (objectId !== "" && gameWorld && gameWorld.despawnEnemy(enemy)) return
        destroy()
    }
}
