import QtQuick
import Box2D
import Clayground.Common
import Clayground.World
import Clayground.Physics
import Clayground.GameController
import Clayground.Sound
import Clayground.Storage

ClayWorld2d {
    id: world

    // World configuration (fit world to viewport)
    pixelPerUnit: 55
    gravity: Qt.point(0, 0)  // Top-down, no gravity
    timeStep: 1/60.0
    anchors.fill: parent
    focus: true

    camera: ClayWorld2dCamera {
        id: gameCamera
        mode: ClayWorld2dCamera.LookAhead
        lookAheadFactor: 0.2
        smoothing: 3.0
    }

    // Dark background behind the world
    Rectangle { parent: world; anchors.fill: parent; color: "#1a1a2e"; z: -1 }

    // Global mute, toggled with M. The dojo starts silent so reloads while
    // developing stay quiet; a native or browser start plays.
    property bool muted: Clayground.runsInSandbox

    // Atmosphere layer (lighting, procedural ground, screen effects).
    // V toggles it for a before/after comparison.
    property bool fx: true

    // Audio — switches based on levelType
    Music {
        id: dungeonAmbience
        source: "assets/dungeon_ambience.mp3"
        volume: muted ? 0 : 0.4
        loop: true
    }

    Music {
        id: dungeonMusic
        source: "assets/dungeon_music.mp3"
        volume: muted ? 0 : 0.3
        loop: true
    }

    Music {
        id: villageAmbience
        source: "assets/village_ambience.mp3"
        volume: muted ? 0 : 0.4
        loop: true
    }

    Music {
        id: villageMusic
        source: "assets/village_music.mp3"
        volume: muted ? 0 : 0.35
        loop: true
    }

    onLevelTypeChanged: {
        if (levelType === "village") {
            dungeonAmbience.stop()
            dungeonMusic.stop()
            villageAmbience.play()
            villageMusic.play()
        } else {
            villageAmbience.stop()
            villageMusic.stop()
            dungeonAmbience.play()
            dungeonMusic.play()
        }
    }



    Sound {
        id: impactSound
        source: "assets/punch_hitting.wav"
        volume: muted ? 0 : 0.7
    }

    Sound {
        id: dashSound
        source: "assets/dash.wav"
        volume: muted ? 0 : 0.6
    }

    // gain (0..1) is for sounds of another player's knight, see remoteGain()
    function playImpact(gain) {
        impactSound.triggerOneShot(gain === undefined ? 1 : gain)
    }

    Sound {
        id: deathBurstSound
        source: "assets/burst.wav"
        volume: muted ? 0 : 0.7
    }

    Sound {
        id: swordSwingSound
        source: "assets/sword_swing.wav"
        volume: muted ? 0 : 0.5
    }

    function playDash(gain) {
        dashSound.triggerOneShot(gain === undefined ? 1 : gain)
    }

    function playSwordSwing(gain) {
        swordSwingSound.triggerOneShot(gain === undefined ? 1 : gain)
    }

    // How loud another knight is at xWu/yWu: never as loud as your own
    // knight, and fading to silence about a screen away from you
    readonly property real remoteMaxGain: 0.5
    readonly property real remoteHearingWu: 14
    function remoteGain(xWu, yWu) {
        if (!player) return remoteMaxGain
        let dx = xWu - player.xWu, dy = yWu - player.yWu
        let d = Math.sqrt(dx * dx + dy * dy)
        return remoteMaxGain * Math.max(0, 1 - d / remoteHearingWu)
    }

    function playDeathBurst() {
        deathBurstSound.play()
    }

    Sound {
        id: spitterSound
        source: "assets/spitter.wav"
        volume: muted ? 0 : 0.6
    }

    function playSpitShot() {
        spitterSound.play()
    }

    Sound {
        id: innkeeperGreeting
        source: "assets/innkeeper_greeting.wav"
        volume: muted ? 0 : 0.8
    }
    Sound {
        id: blacksmithGreeting
        source: "assets/blacksmith_greeting.wav"
        volume: muted ? 0 : 0.8
    }
    Sound {
        id: witchGreeting
        source: "assets/witch_greeting.wav"
        volume: muted ? 0 : 0.8
    }

    function playNpcGreeting(soundFile) {
        if (soundFile.indexOf("innkeeper") >= 0) innkeeperGreeting.play()
        else if (soundFile.indexOf("blacksmith") >= 0) blacksmithGreeting.play()
        else if (soundFile.indexOf("witch") >= 0) witchGreeting.play()
    }

    // Apply screen shake via transform on room
    transform: Translate { x: _shakeOffsetX; y: _shakeOffsetY }

    // World bounds (in world units) - portrait orientation
    xWuMax: 100
    yWuMax: 100

    // Debug visualization
    debugPhysics: false
    property bool debugBehavior: false
    property bool debugMechanics: false
    property bool fightRoomActive: false
    property real _fightRoomCx: 0
    property real _fightRoomCy: 0

    canvas.showDebugInfo: false

    // Screen shake
    property real _shakeIntensity: 0
    property real _shakeOffsetX: 0
    property real _shakeOffsetY: 0

    Timer {
        id: shakeTimer
        interval: 30
        repeat: true
        running: _shakeIntensity > 0.5
        onTriggered: {
            _shakeOffsetX = (Math.random() * 2 - 1) * _shakeIntensity
            _shakeOffsetY = (Math.random() * 2 - 1) * _shakeIntensity
            _shakeIntensity *= 0.7
            if (_shakeIntensity <= 0.5) {
                _shakeOffsetX = 0
                _shakeOffsetY = 0
                _shakeIntensity = 0
            }
        }
    }

    function shake(intensity) {
        _shakeIntensity = Math.max(_shakeIntensity, intensity)
    }

    // --- Impact feedback --------------------------------------------------
    // Every hit in the game reports here, so how a fight feels is tuned in
    // one place. With fx off it falls back to the original shake only.
    //   kind: enemyHit, enemyBlocked, enemyDeath, playerHit, playerBlocked,
    //         parry, projectileHit, projectileDeflected, projectileBurst
    //   (x, y): where it happened; (dx, dy): direction the blow travelled
    //   color: the struck thing's colour (shards and stains)
    //   local: false for another player's hit (default true)
    // Its world part (sparks, shards, rings, stains) belongs to the place
    // of the hit and shows on every screen; its screen part (shake, kick,
    // hit-stop, flash) only on the screen of whoever hit or was hit. A local
    // hit goes out to the others, who draw its world part only.
    function impact(kind, x, y, dx, dy, color, local) {
        let len = Math.sqrt(dx * dx + dy * dy)
        let nx = len > 0.001 ? dx / len : 0
        let ny = len > 0.001 ? dy / len : 0
        _impactWorld(kind, x, y, nx, ny, color)
        if (local === false) return
        _impactScreen(kind, nx, ny)
        session.sendImpact(kind, x, y, dx, dy, color)
    }

    function _impactWorld(kind, x, y, nx, ny, color) {
        if (!fx) {
            if (kind === "enemyDeath") spawnDeathParticles(x, y)
            else if (kind === "parry") spawnParryEffect(x, y)
            else if (kind === "projectileDeflected") spawnDeflectParticles(x, y)
            else if (kind === "projectileBurst") spawnSpitParticles(x, y)
            return
        }
        switch (kind) {
        case "enemyHit":
            spawnSparks(x - nx * 0.3, y - ny * 0.3, nx, ny, 7, "#FFE6A0")
            spawnShards(x, y, nx, ny, 4, color, 0.2)
            break
        case "enemyBlocked":
            spawnSparks(x - nx * 0.45, y - ny * 0.45, -nx, -ny, 9, "#FFB060")
            break
        case "enemyDeath":
            spawnShards(x, y, nx, ny, 12, color, 0.3)
            spawnSparks(x, y, nx, ny, 10, Qt.lighter(color, 1.6))
            spawnRing(x, y, Qt.lighter(color, 1.4))
            spawnStain(x, y, color)
            break
        case "playerHit":
            spawnShards(x, y, nx, ny, 5, "#7AB8D4", 0.18)
            break
        case "playerBlocked":
            spawnSparks(x, y, -nx, -ny, 8, "#A0D8F0")
            break
        case "parry":
            spawnSparks(x, y, nx, ny, 14, "#FFE066")
            spawnRing(x, y, "#FFD700")
            break
        case "projectileHit":
        case "projectileBurst":
            spawnShards(x, y, nx, ny, 5, "#8EBB5A", 0.1)
            break
        case "projectileDeflected":
            spawnSparks(x, y, -nx, -ny, 8, "#A0D8F0")
            break
        }
    }

    function _impactScreen(kind, nx, ny) {
        if (!fx) {
            let legacyShake = {enemyHit: 1.5, enemyBlocked: 0.5, playerHit: 3,
                               playerBlocked: 1, projectileHit: 1,
                               projectileDeflected: 0.5}[kind] || 0
            if (legacyShake > 0) shake(legacyShake)
            return
        }
        switch (kind) {
        case "enemyHit":
            _trauma(0.22); _kick(nx * 0.12, ny * 0.12); _freeze(55)
            break
        case "enemyBlocked":
            _trauma(0.12); _freeze(30)
            break
        case "enemyDeath":
            _trauma(0.4); _kick(nx * 0.2, ny * 0.2); _freeze(90)
            break
        case "playerHit":
            _trauma(0.5); _kick(nx * 0.25, ny * 0.25); _freeze(75)
            if (screenFx) screenFx.hurt()
            break
        case "playerBlocked":
            _trauma(0.18); _kick(nx * 0.08, ny * 0.08)
            break
        case "parry":
            _trauma(0.3); _freeze(140, 0.12)
            if (screenFx) screenFx.parry()
            break
        case "projectileDeflected":
            _trauma(0.12)
            break
        // projectileHit: the player's own playerHit carries the shake
        }
    }


    function _trauma(t) {
        if (gameCamera.addTrauma) gameCamera.addTrauma(t)
        else shake(t * 6)
    }
    function _kick(dxWu, dyWu) {
        if (gameCamera.kick) gameCamera.kick(dxWu, dyWu)
    }
    function _freeze(ms, scale) {
        if (world.hitStop) world.hitStop(ms, scale === undefined ? 0 : scale)
    }

    Component { id: fxParticleComp; FxParticle {} }
    Component { id: stainComp; Stain {} }

    // Fragments of the struck shape, thrown along the blow
    function spawnShards(x, y, nx, ny, count, color, sizeWu) {
        for (let i = 0; i < count; i++) {
            let a = Math.atan2(ny, nx) + (Math.random() - 0.5) * 2.2
            let speed = 3 + Math.random() * 5
            fxParticleComp.createObject(world.room, {
                xWu: x, yWu: y,
                velX: Math.cos(a) * speed, velY: Math.sin(a) * speed,
                sizeWu: sizeWu * (0.6 + Math.random() * 0.8),
                color: Qt.darker(color, 0.9 + Math.random() * 0.5),
                lifetime: 420 + Math.random() * 300,
                spin: (Math.random() - 0.5) * 720,
                pixelPerUnit: world.pixelPerUnit
            })
        }
    }

    // Bright streaks flying off the point of contact
    function spawnSparks(x, y, nx, ny, count, color) {
        for (let i = 0; i < count; i++) {
            let a = Math.atan2(ny, nx) + (Math.random() - 0.5) * 2.6
            let speed = 6 + Math.random() * 7
            fxParticleComp.createObject(glowParent(), {
                xWu: x, yWu: y,
                velX: Math.cos(a) * speed, velY: Math.sin(a) * speed,
                sizeWu: 0.08, stretch: 4 + Math.random() * 4,
                color: color, lifetime: 180 + Math.random() * 160,
                shrinkTo: 0.1, z: 5,
                pixelPerUnit: world.pixelPerUnit
            })
        }
    }

    Component {
        id: ringComp
        Rectangle {
            id: _ring
            property real pixelPerUnit: 1
            property real xWu: 0
            property real yWu: 0
            property real rWu: 0.2
            width: rWu * 2 * pixelPerUnit
            height: width
            radius: width / 2
            x: xWu * pixelPerUnit - width / 2
            y: (parent ? parent.height : 0) - yWu * pixelPerUnit - height / 2
            color: "transparent"
            border.width: Math.max(1, 0.08 * pixelPerUnit * (1 - opacity * 0.3))
            z: 5
            ParallelAnimation {
                running: true
                NumberAnimation { target: _ring; property: "rWu"; to: 1.6; duration: 280; easing.type: Easing.OutCubic }
                NumberAnimation { target: _ring; property: "opacity"; from: 0.9; to: 0; duration: 280 }
                onFinished: _ring.destroy()
            }
        }
    }
    function spawnRing(x, y, color) {
        let r = ringComp.createObject(glowParent(), {
            xWu: x, yWu: y, pixelPerUnit: world.pixelPerUnit
        })
        if (r) r.border.color = color
    }

    // Stains persist for the level; the oldest go once there are many
    property var stains: []
    function spawnStain(x, y, color) {
        let s = stainComp.createObject(world.room, {
            xWu: x, yWu: y,
            color: Qt.darker(color, 1.7),
            sizeWu: 0.8 + Math.random() * 0.5,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            visible: Qt.binding(() => world.fx)
        })
        stains.push(s)
        dungeonObjects.push(s)
        while (stains.length > 60) {
            let old = stains.shift()
            try { if (old) old.destroy() } catch (err) {}
        }
    }

    // Screen state: "title", "lobby", "game"
    property string screen: "title"

    // Co-op: the connection, the lobby and the remote players
    Session {
        id: session
        z: 5000
        world: world
        player: world.player
        inGame: screen === "game"
        showLobby: screen === "lobby"
        muted: world.muted
        onStarted: (seed) => {
            masterSeed = seed
            screen = "game"
            world.forceActiveFocus()
        }
        onLevelChanged: (newIndex) => _applyLevelChange(newIndex)
        onAdvanceRequested: _hostAdvanceLevel()
        onLobbyStartRequested: _startMultiplayerGame()
        onLobbyLeft: screen = "title"
        onImpactReceived: (kind, x, y, dx, dy, color) => {
            if (screen === "game") impact(kind, x, y, dx, dy, color, false)
        }
        onEnemySpawned: (objectId, props) => _makeEnemy(props, objectId)
        onEnemyDespawned: (objectId) => _dropEnemy(objectId)
        onEnemyBlowReceived: (fromId, blow) => {
            let e = _enemyById[blow.id]
            if (!e || e.destroyed) return
            if (blow.kind === "damage") e.takeRemoteBlow(blow.amount, blow.x, blow.y, fromId)
            else if (blow.kind === "stagger") e.stagger()
            else if (blow.kind === "push") e.shove(blow.dx, blow.dy, blow.speed)
        }
        onKnightBlowReceived: (blow) => _holdKnightBlow(blow)
        onEnemyKillReceived: (kill) => {
            let e = _enemyById[kill.id]
            if (e) e.destroyed = true
            impact("enemyDeath", kill.x, kill.y, kill.dx, kill.dy, kill.color)
            playDeathBurst()
            countFight("kill")
        }
        onShotReceived: (shot) => {
            if (screen !== "game") return
            _flyShot(shot.id, shot.x, shot.y, shot.dx, shot.dy, shot.damage)
            playSpitShot()
        }
        onStruckReported: (fromId, report) => {
            if (report.source === "shot") _endShot(report.id, report.result)
            world.struckReported(fromId, report.source, report.id, report.result)
        }
    }

    // --- Enemies in a session (issue #13) ---
    // The host runs every enemy: it spawns them as replicated objects,
    // runs their AI and sends their state; every other node makes a
    // remote enemy per object that shows the host's and passes its own
    // knight's blows to the host. Without a session the game runs its
    // enemies itself, as it always did.
    property var _enemyById: ({})
    // In a session an enemy goes for the nearest knight still standing;
    // alone it keeps the target it was given
    readonly property bool enemiesChooseTarget: session.connected
    // The nearest knight at (x, y) that has not fallen, this node's or
    // another player's, or null
    function nearestKnight(x, y) {
        let knights = [player]
        for (let id in session.remotePlayers) knights.push(session.remotePlayers[id])
        let best = null, bestD = Infinity
        for (let k of knights) {
            if (!k || (k === player ? player.fallen : k.remoteHp <= 0)) continue
            let dx = k.xWu - x, dy = k.yWu - y
            let d = dx * dx + dy * dy
            if (d < bestD) { bestD = d; best = k }
        }
        return best
    }
    // The node a knight belongs to
    function knightIdOf(knight) {
        if (!knight) return ""
        return knight === player ? session.nodeId : knight.nodeId
    }
    // Joiner: this node's knight struck an enemy the host runs
    function strikeEnemy(enemy, blow) {
        if (session.connected && enemy.objectId !== "") session.strikeEnemy(enemy.objectId, blow)
    }
    // Host: an enemy lunged at another node's knight
    function strikeKnight(knight, enemy, atk, x, y) {
        if (session.connected)
            session.strikeKnight(knight.nodeId, {id: enemy.objectId, atk: atk, x: x, y: y,
                                                 size: enemy.widthWu})
    }
    // A host's enemy struck this knight: the blow lands when this screen
    // shows the lunge land, the enemy's render delay after it arrived. A
    // parry of that enemy from its last parry window before the blow arrived
    // until then answers that lunge, and the blow is dropped. Without the
    // hold, a parry in the window's last render delay on this screen came
    // after the blow of the lunge it parried. The window is counted in
    // physics steps, as the enemy's attack runs (issue #35); the hold is
    // wall clock, as this screen renders the enemy.
    // knightStruck says what became of each blow: "hit", "blocked",
    // "dodged", "ignored", "out of reach" or "parried". This screen judges
    // it by its knight's own state, and reports it to the others
    // (issue #18).
    signal knightStruck(string enemyId, string result)
    // Another node's knight met a host's enemy's attack and its node judged
    // it: source "lunge" (id: the enemy's) or "shot" (id: the shot's)
    signal struckReported(string nodeId, string source, string id, string result)
    function _struck(enemyId, result) {
        knightStruck(enemyId, result)
        if (session.connected) session.reportStruck({source: "lunge", id: enemyId, result: result})
    }
    // The physics steps since the game came up, the clock of the parry window
    property int _physicsSteps: 0
    property var _parriedAt: ({})
    property var _heldBlows: []
    // This node's knight parried a host's enemy
    function parried(enemy) {
        if (enemy.remote) _parriedAt[enemy.objectId] = _physicsSteps
    }
    function _holdKnightBlow(blow) {
        let e = _enemyById[blow.id]
        let hold = e ? e.renderDelayMs : 0
        _heldBlows.push(Object.assign({due: Date.now() + hold, arrived: _physicsSteps}, blow))
        _heldBlowTimer.start()
    }
    Timer {
        id: _heldBlowTimer
        interval: 5
        repeat: true
        onTriggered: {
            let now = Date.now()
            let due = world._heldBlows.filter(b => b.due <= now)
            world._heldBlows = world._heldBlows.filter(b => b.due > now)
            if (world._heldBlows.length === 0) stop()
            for (let b of due) world._landKnightBlow(b)
        }
    }
    function _landKnightBlow(blow) {
        // The reach is checked here, against where this knight really is
        if (!player) return
        let at = _parriedAt[blow.id]
        if (at !== undefined && at >= blow.arrived - Balance.enemy.parryFrames) {
            _struck(blow.id, "parried")
            return
        }
        // A dash that carried the knight past the enemy dodged it all the same
        let dx = player.xWu - blow.x, dy = player.yWu - blow.y
        if (Math.sqrt(dx * dx + dy * dy) >= Balance.enemy.lungeHitRange) {
            _struck(blow.id, player.isDashing ? "dodged" : "out of reach")
            return
        }
        let result = player.takeDamage(blow.atk, blow.x, blow.y, blow.size)
        if (result === "hit" || result === "blocked") playImpact()
        _struck(blow.id, result)
    }
    // Host: another node's knight killed an enemy
    function reportKill(nodeId, enemy, dx, dy, color) {
        if (session.connected)
            session.reportKill(nodeId, {id: enemy.objectId, x: enemy.xWu, y: enemy.yWu,
                                        dx: dx, dy: dy, color: color})
    }
    // Host: a replicated enemy goes on every node, its item with it; false
    // when it is not one
    function despawnEnemy(enemy) {
        if (!session.connected || !session.isHost || enemy.objectId === "") return false
        session.despawnEnemy(enemy.objectId)
        return true
    }
    function _dropEnemy(objectId) {
        let e = _enemyById[objectId]
        if (!e) return
        delete _enemyById[objectId]
        enemies = enemies.filter(x => x !== e)
        e.destroyed = true
        try { e.destroy() } catch (err) {}
        minimap.requestPaint()
    }

    // In a session every node simulates something the others see (the host
    // the world, each player its own knight): the hit stop holds the picture
    // and lets the simulation run on, so a hit never stalls the others
    hitStopMode: session.connected ? "view" : "physics"

    // Game state
    property var player: null
    property var enemies: []
    property var dungeonObjects: []
    property int entranceGridX: 0
    property int exitGridX: 0
    property int masterSeed: -1   // -1 = random on first run
    property int levelIndex: 0
    property string levelType: "dungeon"  // "dungeon" or "village"
    property var rng: null
    // How deep the run got: the dungeons behind the knight, 0 for the first
    readonly property int depth: depthOf(levelIndex)
    // Two levels make one depth: the dungeon at depth d is level 2d, the
    // village after it level 2d + 1. The rule lives only here, so the depth
    // shown and kept comes from the same rule as the level entered.
    function depthOf(index) { return Math.floor(index / 2) }
    function levelTypeOf(index) { return index % 2 === 1 ? "village" : "dungeon" }
    function levelIndexOf(d, type) { return 2 * d + (type === "village" ? 1 : 0) }
    // The knight is at 0 HP: the enemies stand still and the fallen screen
    // offers a new run or the title
    property bool fallen: false
    components: []

    // The run so far, for the fallen screen: the enemies killed and the
    // simulated seconds since it started (a pause holds them)
    property int runKills: 0
    property real runSeconds: 0
    // The deepest any run got on this machine (-1 before the first), kept
    // with Clayground.Storage; runStartBest is what it was when this run
    // started, so the fallen screen can tell a new best
    property int bestDepth: -1
    property int runStartBest: -1
    // A bench keeps its record apart from the player's with its own name
    property string recordStoreName: "ShapesAndStone"
    KeyValueStore { id: records; name: world.recordStoreName }
    function _startRunRecord() {
        runKills = 0
        runSeconds = 0
        runStartBest = bestDepth
    }
    function _keepBest() {
        if (depth <= bestDepth) return
        bestDepth = depth
        records.set("bestDepth", String(bestDepth))
    }
    onDepthChanged: _keepBest()

    // Collision categories
    readonly property int catWall: Box.Category1
    readonly property int catPlayer: Box.Category2
    readonly property int catEnemy: Box.Category3
    readonly property int catProjectile: Box.Category4

    Component.onCompleted: {
        console.log("[Game] Component.onCompleted - width:", width, "height:", height)
        bestDepth = parseInt(records.get("bestDepth", "-1"))
        runStartBest = bestDepth
        console.log("[Game] Best depth so far:", bestDepth)
        forceActiveFocus()
    }

    // Wait for valid size + game screen before generating dungeon
    onWidthChanged: _tryStartGame()
    onScreenChanged: _tryStartGame()
    function _tryStartGame() {
        if (screen === "game" && width > 0 && height > 0 && !player) {
            console.log("[Game] Starting game - width:", width, "height:", height)
            console.log("[Game] pixelPerUnit:", pixelPerUnit)
            dungeonAmbience.play()
            dungeonMusic.play()
            generateDungeon()
        }
    }

    function _startMultiplayerGame() {
        if (masterSeed < 0)
            masterSeed = Math.floor(Math.random() * 2147483647)
        session.start(masterSeed)
    }

    // Mouse input: aiming + attack + shield (also handles WASM focus)
    MouseArea {
        id: mouseInput
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: (mouse) => {
            world.forceActiveFocus()
            if (!player) return
            if (mouse.button === Qt.LeftButton) {
                player.attack()
            }
            if (mouse.button === Qt.RightButton) player.isBlocking = true
        }

        onReleased: (mouse) => {
            if (mouse.button === Qt.RightButton && player)
                player.isBlocking = false
        }
    }

    // Player center in screen coords (for aiming) - map from player's parent to mouseInput coords
    property var playerScreenPos: player ? player.parent.mapToItem(mouseInput, player.x + player.width * 0.5, player.y + player.height * 0.5) : Qt.point(width/2, height/2)
    property real playerScreenX: playerScreenPos.x
    property real playerScreenY: playerScreenPos.y


    // Input handling
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_M) {
            muted = !muted
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_V) {
            fx = !fx
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_E) {
            if (dialoguePanel.visible) {
                dialoguePanel.advance()
            } else if (player) {
                // Find nearby NPC to interact with
                let items = world.room.children
                for (let i = 0; i < items.length; i++) {
                    let npc = items[i]
                    if (npc.objectName === "npc" && npc.nearbyPlayer) {
                        npc.interact()
                        break
                    }
                }
            }
            event.accepted = true
            return
        }
    }
    Keys.forwardTo: gameCtrl
    GameController {
        id: gameCtrl
        anchors.fill: parent
        showDebugOverlay: false

        Component.onCompleted: {
            console.log("[Game] GameController.onCompleted - os:", Qt.platform.os)
            const os = Qt.platform.os
            if (os === "ios" || os === "android") {
                console.log("[Game] Selecting touchscreen gamepad")
                selectTouchscreenGamepad()
            } else {
                console.log("[Game] Selecting keyboard (WASD + Space/Shift)")
                selectKeyboard(Qt.Key_W, Qt.Key_S, Qt.Key_A, Qt.Key_D,
                               Qt.Key_Space, Qt.Key_Shift)
            }
        }

        onAxisXChanged: console.log("[Input] axisX:", axisX)
        onAxisYChanged: console.log("[Input] axisY:", axisY)
        onButtonBPressedChanged: {
            if (buttonBPressed && player) {
                player.dash()
            }
        }
    }

    // Player Health HUD (fixed position, not following camera)
    Rectangle {
        id: healthHud
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 10
        width: 200
        height: 24
        color: "#333333"
        radius: 4
        z: 1000  // Above everything

        Rectangle {
            id: healthFill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 2
            width: player ? (parent.width - 4) * (player.hp / player.maxHp) : parent.width - 4
            radius: 2
            color: {
                if (!player) return "#22CC22"
                let ratio = player.hp / player.maxHp
                if (ratio > 0.5) return "#22CC22"
                if (ratio > 0.25) return "#CCCC22"
                return "#CC2222"
            }

            Behavior on width { NumberAnimation { duration: 100 } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Text {
            anchors.centerIn: parent
            text: player ? player.hp + " / " + player.maxHp : ""
            color: "white"
            font.pixelSize: 12
            font.bold: true
        }
    }

    // Player Mana HUD
    Rectangle {
        id: manaHud
        anchors.top: healthHud.bottom
        anchors.left: parent.left
        anchors.margins: 10
        anchors.topMargin: 4
        width: 200
        height: 16
        color: "#333333"
        radius: 4
        z: 1000

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 2
            width: player ? (parent.width - 4) * (player.mana / player.maxMana) : parent.width - 4
            radius: 2
            color: "#8844AA"
            Behavior on width { NumberAnimation { duration: 100 } }
        }

        Text {
            anchors.centerIn: parent
            text: player ? Math.ceil(player.mana) + " / " + player.maxMana : ""
            color: "white"
            font.pixelSize: 10
            font.bold: true
        }
    }

    // How deep the knight is, under the bars
    Text {
        objectName: "hudDepth"
        anchors.top: manaHud.bottom
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.topMargin: 6
        z: 1000
        visible: player !== null
        text: "Depth " + depth
        color: "#DDDDDD"
        style: Text.Outline
        styleColor: "#000000"
        font.pixelSize: 14
        font.bold: true
        font.letterSpacing: 1
    }

    // Crosshair at mouse position
    Item {
        id: crosshair
        x: mouseInput.mouseX - 6
        y: mouseInput.mouseY - 6
        width: 12
        height: 12
        z: 1000

        // Horizontal line
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: 2
            color: "#7AB8D4"
        }
        // Vertical line
        Rectangle {
            anchors.centerIn: parent
            width: 2
            height: parent.height
            color: "#7AB8D4"
        }
    }

    // Mute indicator (always visible when muted)
    Rectangle {
        objectName: "muteIcon"
        anchors.top: minimap.bottom
        anchors.right: parent.right
        anchors.topMargin: 4
        anchors.rightMargin: 10
        width: 32; height: 32; radius: 6
        z: 1000
        visible: muted
        color: "#AA222222"

        Text {
            anchors.centerIn: parent
            text: "\u266A\u0338"
            color: "#CC6666"
            font.pixelSize: 28
            font.bold: true
        }
    }

    // DEV menu (sandbox only)
    Column {
        id: devMenu
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 10
        z: 1000
        visible: Clayground.runsInSandbox
        spacing: 4

        property bool expanded: false

        Rectangle {
            width: devMenu.expanded ? 160 : 36
            height: 24; radius: 4
            color: "#333333CC"

            Text {
                anchors.centerIn: parent
                text: devMenu.expanded ? "DEV [v]" : "DEV"
                color: "#AAAAAA"
                font.pixelSize: 12; font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: devMenu.expanded = !devMenu.expanded
            }
        }

        Rectangle {
            visible: devMenu.expanded
            width: 160; height: 24; radius: 4
            color: "#33333380"

            Text {
                anchors.centerIn: parent
                text: "Seed: " + masterSeed
                color: "#AAAAAA"; font.pixelSize: 11
            }
        }

        Rectangle {
            visible: devMenu.expanded
            width: 160; height: 24; radius: 4
            color: world.debugPhysics ? "#4A90A480" : "#33333380"

            Text {
                anchors.centerIn: parent
                text: "Physics: " + (world.debugPhysics ? "ON" : "OFF")
                color: "white"; font.pixelSize: 11
            }

            MouseArea {
                anchors.fill: parent
                onClicked: world.debugPhysics = !world.debugPhysics
            }
        }

        Rectangle {
            visible: devMenu.expanded
            width: 160; height: 24; radius: 4
            color: world.debugBehavior ? "#4A90A480" : "#33333380"

            Text {
                anchors.centerIn: parent
                text: "Behavior: " + (world.debugBehavior ? "ON" : "OFF")
                color: "white"; font.pixelSize: 11
            }

            MouseArea {
                anchors.fill: parent
                onClicked: world.debugBehavior = !world.debugBehavior
            }
        }

        Rectangle {
            visible: devMenu.expanded
            width: 160; height: 24; radius: 4
            color: world.debugMechanics ? "#4A90A480" : "#33333380"

            Text {
                anchors.centerIn: parent
                text: "Mechanics: " + (world.debugMechanics ? "ON" : "OFF")
                color: "white"; font.pixelSize: 11
            }

            MouseArea {
                anchors.fill: parent
                onClicked: world.debugMechanics = !world.debugMechanics
            }
        }

        Rectangle {
            visible: devMenu.expanded
            width: 160; height: 24; radius: 4
            color: fightRoomActive ? "#AA444480" : "#33333380"

            Text {
                anchors.centerIn: parent
                text: fightRoomActive ? "Fight Room: ON" : "Fight Room"
                color: fightRoomActive ? "#FF8888" : "white"
                font.pixelSize: 11
            }

            MouseArea {
                anchors.fill: parent
                onClicked: fightRoomActive ? exitFightRoom() : enterFightRoom()
            }
        }

        Rectangle {
            visible: devMenu.expanded
            width: 160; height: 24; radius: 4
            color: muted ? "#33333380" : "#4A90A480"

            Text {
                anchors.centerIn: parent
                text: muted ? "\u266A\u0338 Sound: OFF" : "\u266A Sound: ON"
                color: muted ? "#AA6666" : "white"
                font.pixelSize: 11
            }

            MouseArea {
                anchors.fill: parent
                onClicked: muted = !muted
            }
        }
    }

    // Reliable events so the other players see swings, dashes, parries and
    // hits crisply, not only when the sampled state catches them
    Connections {
        target: player
        function onActed(action) { session.sendAction(action) }
    }

    Connections {
        target: player
        function onHpChanged() { if (player.hp <= 0) _fall() }
    }

    function _fall() {
        if (fallen || screen !== "game") return
        console.log("[Game] The knight has fallen at depth", depth)
        fallen = true
        _keepBest()
        countFight("fall")
        // In a session the enemies go for the knights still standing
        if (session.connected) return
        for (let e of enemies) {
            try { if (e && e.halt) e.halt() } catch(err) {}
        }
    }

    // --- Fight record ---
    // How the fight went, counted where it happens: the damage the knight
    // dealt and took, its parries, the attacks its shield stopped, the
    // enemies killed, its falls, and the simulated seconds since the record
    // started and until no enemy stood (-1 while one does). Each new knight
    // starts a fresh record; the fight bench reads it (issue #34).
    readonly property QtObject fightRecord: QtObject {
        property int damageDealt: 0
        property int damageTaken: 0
        property int parries: 0
        property int blocks: 0
        property int kills: 0
        property int deaths: 0
        property real seconds: 0
        property real clearSeconds: -1
    }
    function resetFightRecord() {
        let r = fightRecord
        r.damageDealt = 0; r.damageTaken = 0; r.parries = 0; r.blocks = 0
        r.kills = 0; r.deaths = 0; r.seconds = 0; r.clearSeconds = -1
    }
    // what: dealt, taken (with the damage), parry, block, kill or fall
    function countFight(what, amount) {
        let r = fightRecord
        switch (what) {
        case "dealt": r.damageDealt += amount; break
        case "taken": r.damageTaken += amount; break
        case "parry": r.parries++; break
        case "block": r.blocks++; break
        case "fall": r.deaths++; break
        case "kill":
            r.kills++
            runKills++
            if (r.clearSeconds < 0 && !enemies.some(e => e && e.destroyed === false))
                r.clearSeconds = r.seconds
            break
        }
    }
    // The record's clock is the physics: a pause or a hit stop holds it
    Connections {
        target: world.physics
        function onStepped() {
            world._physicsSteps++
            if (world.player && !world.fallen) {
                world.fightRecord.seconds += world.physics.timeStep
                world.runSeconds += world.physics.timeStep
            }
        }
    }

    // Enter on the fallen screen: a new run from depth 0 on a new seed
    function newRun() {
        let oldSeed = masterSeed
        do {
            masterSeed = Math.floor(Math.random() * 2147483647)
        } while (masterSeed === oldSeed)
        console.log("[Game] New run, seed:", masterSeed)
        clearDungeon()
        fallen = false
        resetting = false
        fightRoomActive = false
        levelIndex = 0
        levelType = "dungeon"
        _startRunRecord()
        generateDungeon()
        minimap.requestPaint()
        world.forceActiveFocus()
    }

    // Esc on the fallen screen: leave the run (and a session) for the title,
    // where the next start rolls a new seed
    function backToTitle() {
        console.log("[Game] Back to the title")
        clearDungeon()
        if (session.connected) session.leave()
        fallen = false
        resetting = false
        fightRoomActive = false
        masterSeed = -1
        levelIndex = 0
        levelType = "dungeon"
        _startRunRecord()
        dungeonAmbience.stop()
        dungeonMusic.stop()
        villageAmbience.stop()
        villageMusic.stop()
        screen = "title"
    }

    // Track player movement for minimap exploration
    Connections {
        target: player
        function onXWuChanged() { revealAroundPlayer() }
        function onYWuChanged() { revealAroundPlayer() }
    }

    // Lantern lighting mask anchored to the player — only in the dungeon.
    // outerRadius is set larger than the viewport half-diagonal so the dark
    // edge fades off-screen rather than leaving visible pitch-black areas.
    AnchoredMask {
        world: world
        target: player
        enabled: levelType === "dungeon" && !world.fx
        innerRadius: 4
        outerRadius: 18
        color: "#ffb060"
        darkness: "#000000"
        flicker: 0.15
    }

    // --- Atmosphere: light and screen treatment (fx on) ---------------------
    // Coloured lights with wall shadows replace the single lantern mask. The
    // ambient is how much of an unlit spot still shows: next to nothing deep
    // in the dungeon, a moonlit dusk in the village.
    LightLayer2d {
        id: lighting
        world: world
        active: world.fx && screen === "game"
        ambient: fightRoomActive ? "#1a1824" : levelType === "village" ? "#4a5670" : "#0c0b12"
        // Little additive glow: it washes colours towards white-grey; the
        // light should reveal the shapes' own colours, not tint them
        glow: 0.1
        falloff: 1.6
        shadowHardness: 2.5
    }

    ScreenFx2d {
        id: screenFxItem
        world: world
        vignette: world.fx ? (levelType === "village" ? 0.35 : 0.55) : 0
        vignetteColor: "#000000"
        // Danger rooms run warm, the village cool (README: Atmosphere Toolkit)
        temperature: !world.fx ? 0 : levelType === "village" && !fightRoomActive ? -0.15 : 0.12
        // A touch more colour than flat: darkness already mutes everything
        // outside the light, the lit shapes should stay vivid
        saturation: world.fx ? 1.15 : 1
        contrast: world.fx ? 1.05 : 1
        // The heartbeat sets in below a quarter of the health and grows
        // gently - a warning, not an alarm
        lowHealth: world.fx && player && player.hp < player.maxHp * 0.25
                   ? 0.8 * (1 - player.hp / (player.maxHp * 0.25)) : 0
    }
    // Screen-space hit feedback used by impact(); null with fx off
    property var screenFx: world.fx ? screenFxApi : null
    QtObject {
        id: screenFxApi
        function hurt() {
            // A faint tint only: the knight's own white flash and the
            // fringe pulse carry the hit; a full red screen on every spit
            // wears the player out
            screenFxItem.flash("#FF3020", 90, 0.12)
            screenFxItem.pulse(0.4, 200)
        }
        function parry() {
            screenFxItem.flash("#FFF0B0", 80, 0.3)
            screenFxItem.pulse(1.0, 320)
        }
    }

    // Where things that give off light go: above the darkness with fx on
    function glowParent() {
        return fx && lighting.emissive ? lighting.emissive : world.room
    }

    // Walls cast shadows: the occluder map mirrors the level grid
    function updateOccluders() {
        lighting.setOccluderGrid(gridWidth, gridHeight, cellSize,
                                 (cx, cy) => grid[cy] && grid[cy][cx] === cellWall)
    }

    // Minimap with fog of war
    Canvas {
        id: minimap
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        width: 150
        height: 150
        z: 1000

        onPaint: {
            var ctx = getContext("2d")
            ctx.fillStyle = "#111"
            ctx.fillRect(0, 0, width, height)

            var scale = width / gridWidth

            // Draw explored cells
            for (var gy = 0; gy < gridHeight; gy++) {
                for (var gx = 0; gx < gridWidth; gx++) {
                    if (exploredCells[gy] && exploredCells[gy][gx]) {
                        var cellType = grid[gy][gx]
                        ctx.fillStyle = (cellType === cellWall) ? "#333" : "#666"
                        ctx.fillRect(gx * scale, (gridHeight - 1 - gy) * scale, scale, scale)
                    }
                }
            }

            // Draw player
            if (player) {
                var px = player.xWu / cellSize * scale
                var py = (gridHeight - player.yWu / cellSize) * scale
                ctx.fillStyle = "#4A90A4"
                ctx.beginPath()
                ctx.arc(px, py, 3, 0, Math.PI * 2)
                ctx.fill()
            }

            // Draw enemies (if in explored area)
            for (var e of enemies) {
                if (!e || e.destroyed) continue
                var ex = Math.floor(e.xWu / cellSize)
                var ey = Math.floor(e.yWu / cellSize)
                if (exploredCells[ey] && exploredCells[ey][ex]) {
                    ctx.fillStyle = "#CC4444"
                    ctx.beginPath()
                    ctx.arc(e.xWu / cellSize * scale, (gridHeight - e.yWu / cellSize) * scale, 2, 0, Math.PI * 2)
                    ctx.fill()
                }
            }
        }
    }

    // Exit trigger sensor
    property var exitSensor: null
    property var exitStairs: null
    Component { id: exitStairsComponent; ExitStairs {} }
    property bool resetting: false

    CollisionTracker {
        fixture: exitSensor ? exitSensor.fixture : null
        onBeginContact: (entity) => {
            if (entity === player && !resetting) {
                console.log("[Game] Player reached the exit!")
                if (!session.connected) {
                    resetting = true
                    Qt.callLater(resetDungeon)
                } else {
                    session.reachExit()
                }
            }
        }
    }

    // Host-authoritative level transitions: without this every client
    // regenerates on its own and the worlds silently diverge.
    function _hostAdvanceLevel() {
        if (resetting) return
        session.announceLevel(levelIndex + 1)
        _applyLevelChange(levelIndex + 1)
    }

    function _applyLevelChange(newIndex) {
        if (resetting || newIndex === levelIndex) return
        resetting = true
        Qt.callLater(() => {
            _enterLevel(newIndex)
            resetting = false
        })
    }

    // The one way to the next level: what the knight carries (its HP and
    // mana) goes with it, a village follows each dungeon
    function _enterLevel(newIndex) {
        let carried = player ? { hp: player.hp, mana: player.mana }
                             : { hp: Balance.knight.hp, mana: Balance.knight.mana }
        console.log("[Game] Level", newIndex, "carrying HP:", carried.hp, "and mana:", carried.mana)
        clearDungeon()
        levelIndex = newIndex
        levelType = levelTypeOf(newIndex)
        if (levelType === "village")
            generateVillage()
        else
            generateDungeon()
        if (player) { player.hp = carried.hp; player.mana = carried.mana }
    }

    // Component factories
    Component { id: playerComponent; Player {} }
    Component { id: enemyComponent; Enemy {} }
    Component { id: wallComponent; Wall {} }
    Component { id: wallFaceComponent; WallFace {} }
    Component { id: torchComponent; Torch {} }
    Component { id: motesComponent; Motes {} }

    function spawnMotes() {
        // Fireflies glow on their own; dust only shows where light falls
        let village = levelType === "village" && !fightRoomActive
        let m = motesComponent.createObject(village ? glowParent() : world.room, {
            widthWu: xWuMax, heightWu: yWuMax,
            fireflies: village,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            visible: Qt.binding(() => world.fx)
        })
        dungeonObjects.push(m)
    }
    Component { id: floorComponent; Floor {} }
    Component { id: campfireComponent; Campfire {} }
    Component { id: projectileComponent; Projectile {} }
    Component { id: npcComponent; Npc {} }

    // Dialogue panel (bottom-center, hidden by default)
    DialoguePanel { id: dialoguePanel; parent: world }

    function openDialogue(name, color, lines) {
        dialoguePanel.open(name, color, lines)
    }

    // Death particle
    Component {
        id: deathParticleComp
        Rectangle {
            id: _dp
            property real pixelPerUnit: 1
            property real xWu: 0
            property real yWu: 0
            property real widthWu: 0.2
            property real heightWu: 0.2
            property real velX: 0
            property real velY: 0
            x: xWu * pixelPerUnit
            y: parent ? parent.height - yWu * pixelPerUnit : 0
            width: widthWu * pixelPerUnit
            height: heightWu * pixelPerUnit
            radius: width * 0.3
            rotation: Math.random() * 360
            SequentialAnimation {
                running: true
                ParallelAnimation {
                    NumberAnimation { target: _dp; property: "xWu"; to: _dp.xWu + _dp.velX; duration: 500; easing.type: Easing.OutQuad }
                    NumberAnimation { target: _dp; property: "yWu"; to: _dp.yWu + _dp.velY; duration: 500; easing.type: Easing.OutQuad }
                    NumberAnimation { target: _dp; property: "opacity"; from: 1.0; to: 0; duration: 500 }
                    NumberAnimation { target: _dp; property: "widthWu"; to: 0.05; duration: 500 }
                    NumberAnimation { target: _dp; property: "heightWu"; to: 0.05; duration: 500 }
                }
                ScriptAction { script: _dp.destroy() }
            }
        }
    }

    // Dungeon generation constants
    readonly property int cellSize: 2      // Each grid cell = 2x2 world units (for 2-wide hallways)
    readonly property int wallThickness: 1

    // Cell types for the grid
    readonly property int cellWall: 0
    readonly property int cellFloor: 1
    readonly property int cellRoom: 2
    readonly property int cellHallway: 3

    // Grid dimensions (in cells, not world units)
    readonly property int gridWidth: Math.floor(xWuMax / cellSize)
    readonly property int gridHeight: Math.floor(yWuMax / cellSize)

    // Dungeon data
    property var grid: []
    property var rooms: []

    // Minimap exploration
    property var exploredCells: []
    property int revealRadius: 6

    function generateDungeon() {
        if (masterSeed < 0)
            masterSeed = Math.floor(Math.random() * 2147483647)
        let levelSeed = deriveSeed(masterSeed, levelIndex)
        rng = createRng(levelSeed)
        console.log("[Game] Seed:", masterSeed, "Level:", levelIndex, "LevelSeed:", levelSeed)
        console.log("[Game] Grid size:", gridWidth, "x", gridHeight, "cells")

        // Step 1: Initialize grid with walls
        initializeGrid()
        initExploredCells()

        // Step 2: Place rooms
        placeRooms(6, 8, 5, 8)  // minRooms, maxRooms, minSize, maxSize (in cells)

        // Step 3: Connect rooms with spanning tree
        connectRooms()

        // Step 4: Add entrance (south) and exit (north)
        addEntranceAndExit()

        // Step 5: Convert grid to actual game objects
        buildDungeonFromGrid()
        placeRoomTorches(createRng(levelSeed ^ 0x5bd1e995))

        // Step 6: Spawn player in first room
        if (rooms.length > 0) {
            let startRoom = rooms[0]
            let px = (startRoom.x + startRoom.w / 2) * cellSize
            let py = (startRoom.y + startRoom.h / 2) * cellSize
            console.log("[Game] Spawning player at:", px, py)
            spawnPlayer(px, py)
        }

        // Step 7: Block the entrance so player can't backtrack
        blockEntrance()

        // Step 8: Place exit trigger sensor at the north edge
        placeExitSensor()

        // Step 9: Spawn enemies across non-start rooms with tier variation
        if (rooms.length > 1) {
            let spawnRooms = rooms.slice(1)
            let sb = spawnRolls(depth)
            let numEnemies = sb.enemiesMin + Math.floor(rng() * (sb.enemiesMax - sb.enemiesMin + 1))
            let tiers = dealTiers(numEnemies, sb, rng)
            for (let i = 0; i < numEnemies; i++) {
                let room = spawnRooms[i % spawnRooms.length]
                let ex = (room.x + 1 + rng() * (room.w - 2)) * cellSize
                let ey = (room.y + 1 + rng() * (room.h - 2)) * cellSize
                let tier = tiers[i]
                // Enemy type: guardian, spitter, else grunt
                let typeRoll = rng()
                let guardianChance = tier === 2 ? sb.guardianChanceTough : sb.guardianChance
                let type = typeRoll < guardianChance ? "guardian"
                    : typeRoll < guardianChance + sb.spitterChance ? "spitter" : "grunt"
                spawnEnemy(ex, ey, tier, type)
            }
        }

        // Bind player controls
        if (player) {
            player.moveX = Qt.binding(() => gameCtrl.axisX)
            player.moveY = Qt.binding(() => -gameCtrl.axisY)
            // Mouse aiming: bind screen coords for facing calculation
            player.mouseScreenX = Qt.binding(() => mouseInput.mouseX)
            player.mouseScreenY = Qt.binding(() => mouseInput.mouseY)
            player.playerScreenX = Qt.binding(() => playerScreenX)
            player.playerScreenY = Qt.binding(() => playerScreenY)
            gameCamera.target = player
            revealAroundPlayer()  // Initial reveal
        }

        // Spawn remote players for multiplayer
        if (rooms.length > 0) {
            let startRoom = rooms[0]
            session.spawnRemotePlayers((startRoom.x + startRoom.w / 2) * cellSize,
                                (startRoom.y + startRoom.h / 2) * cellSize)
        }

        console.log("[Game] generateDungeon() complete")
    }

    function initializeGrid() {
        grid = []
        for (let y = 0; y < gridHeight; y++) {
            let row = []
            for (let x = 0; x < gridWidth; x++) {
                row.push(cellWall)
            }
            grid.push(row)
        }
        console.log("[Game] Grid initialized:", grid.length, "rows")
    }

    function initExploredCells() {
        exploredCells = []
        for (let y = 0; y < gridHeight; y++) {
            let row = []
            for (let x = 0; x < gridWidth; x++) {
                row.push(false)
            }
            exploredCells.push(row)
        }
    }

    function revealAroundPlayer() {
        if (!player) return
        let px = Math.floor(player.xWu / cellSize)
        let py = Math.floor(player.yWu / cellSize)

        for (let dy = -revealRadius; dy <= revealRadius; dy++) {
            for (let dx = -revealRadius; dx <= revealRadius; dx++) {
                let gx = px + dx
                let gy = py + dy
                if (gx >= 0 && gx < gridWidth && gy >= 0 && gy < gridHeight) {
                    if (dx*dx + dy*dy <= revealRadius*revealRadius) {
                        exploredCells[gy][gx] = true
                    }
                }
            }
        }
        minimap.requestPaint()
    }

    function placeRooms(minRooms, maxRooms, minSize, maxSize) {
        rooms = []
        let numRooms = minRooms + Math.floor(rng() * (maxRooms - minRooms + 1))
        let attempts = 0
        let maxAttempts = 100

        while (rooms.length < numRooms && attempts < maxAttempts) {
            attempts++

            // Random room size (in cells)
            let rw = minSize + Math.floor(rng() * (maxSize - minSize + 1))
            let rh = minSize + Math.floor(rng() * (maxSize - minSize + 1))

            // Random position (leave 1 cell border for walls)
            let rx = 1 + Math.floor(rng() * (gridWidth - rw - 2))
            let ry = 1 + Math.floor(rng() * (gridHeight - rh - 2))

            // Check if room overlaps with existing rooms (with 1 cell padding)
            let overlaps = false
            for (let room of rooms) {
                if (rx < room.x + room.w + 1 &&
                    rx + rw + 1 > room.x &&
                    ry < room.y + room.h + 1 &&
                    ry + rh + 1 > room.y) {
                    overlaps = true
                    break
                }
            }

            if (!overlaps) {
                rooms.push({x: rx, y: ry, w: rw, h: rh})
                // Carve room into grid
                for (let y = ry; y < ry + rh; y++) {
                    for (let x = rx; x < rx + rw; x++) {
                        grid[y][x] = cellRoom
                    }
                }
                console.log("[Game] Placed room", rooms.length, "at", rx, ry, "size", rw, "x", rh)
            }
        }

        // Sort rooms by Y position (bottom to top) for spanning tree
        rooms.sort((a, b) => a.y - b.y)
        console.log("[Game] Placed", rooms.length, "rooms")
    }

    function connectRooms() {
        if (rooms.length < 2) return

        // Simple spanning tree: connect each room to the next
        for (let i = 0; i < rooms.length - 1; i++) {
            let roomA = rooms[i]
            let roomB = rooms[i + 1]

            // Get center of each room
            let ax = Math.floor(roomA.x + roomA.w / 2)
            let ay = Math.floor(roomA.y + roomA.h / 2)
            let bx = Math.floor(roomB.x + roomB.w / 2)
            let by = Math.floor(roomB.y + roomB.h / 2)

            // Carve L-shaped hallway
            carveHallway(ax, ay, bx, by)
        }
    }

    function carveHallway(x1, y1, x2, y2) {
        // Carve horizontal first, then vertical (L-shape)
        let x = x1
        let y = y1

        // Horizontal segment
        let dx = x2 > x1 ? 1 : -1
        while (x !== x2) {
            if (grid[y][x] === cellWall) {
                grid[y][x] = cellHallway
            }
            x += dx
        }

        // Vertical segment
        let dy = y2 > y1 ? 1 : -1
        while (y !== y2) {
            if (grid[y][x] === cellWall) {
                grid[y][x] = cellHallway
            }
            y += dy
        }
    }

    function addEntranceAndExit() {
        if (rooms.length === 0) return

        // Entrance: carve path from bottom room to south edge
        let startRoom = rooms[0]
        let entranceX = Math.floor(startRoom.x + startRoom.w / 2)
        for (let y = 0; y < startRoom.y; y++) {
            grid[y][entranceX] = cellHallway
        }

        // Exit: carve path from top room to north edge
        let endRoom = rooms[rooms.length - 1]
        let exitX = Math.floor(endRoom.x + endRoom.w / 2)
        for (let y = endRoom.y + endRoom.h; y < gridHeight; y++) {
            grid[y][exitX] = cellHallway
        }

        entranceGridX = entranceX
        exitGridX = exitX
        console.log("[Game] Added entrance at x=", entranceX, "exit at x=", exitX)
    }

    function buildDungeonFromGrid() {
        // Create floor for entire dungeon area
        let floorObj = floorComponent.createObject(world.room, {
            xWu: 0, yWu: yWuMax, widthWu: xWuMax, heightWu: yWuMax,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            fx: Qt.binding(() => world.fx),
            style: levelType === "village" && !fightRoomActive ? "earth" : "stone",
            seed: (levelIndex * 0.137) % 1
        })
        dungeonObjects.push(floorObj)

        // Create merged walls using run-length encoding
        let wallCount = createMergedWalls()

        // Create boundary walls
        createBoundaryWalls()
        createWallFaces()
        createWallRims()
        updateOccluders()
        spawnMotes()

        console.log("[Game] Built dungeon with", wallCount, "merged walls")
    }

    function createMergedWalls() {
        // Run-length encoding: merge consecutive wall cells horizontally
        let wallCount = 0

        for (let gy = 0; gy < gridHeight; gy++) {
            let gx = 0
            while (gx < gridWidth) {
                if (grid[gy][gx] === cellWall) {
                    // Found start of wall run, find its length
                    let startX = gx
                    while (gx < gridWidth && grid[gy][gx] === cellWall) {
                        gx++
                    }
                    let runLength = gx - startX

                    // Create single wall for entire run
                    let wx = startX * cellSize
                    let wy = gy * cellSize
                    let ww = runLength * cellSize
                    createWallAt(wx, wy + cellSize, ww, cellSize)
                    wallCount++
                } else {
                    gx++
                }
            }
        }

        return wallCount
    }

    function createBoundaryWalls() {
        // South wall (with entrance gap handled by grid)
        // North wall (with exit gap handled by grid)
        // West wall
        createWallAt(0, yWuMax, wallThickness, yWuMax)
        // East wall
        createWallAt(xWuMax - wallThickness, yWuMax, wallThickness, yWuMax)
    }

    function createWallAt(wx, wy, ww, wh) {
        let wall = wallComponent.createObject(world.room, {
            xWu: wx, yWu: wy, widthWu: ww, heightWu: wh,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            categories: catWall,
            collidesWith: catPlayer | catEnemy | catProjectile,
            fx: Qt.binding(() => world.fx)
        })
        dungeonObjects.push(wall)
        return wall
    }

    // Torches on the north wall of each room. Decoration draws from its own
    // generator so the layout and enemies stay identical to a seed without it.
    property var torches: []
    function placeRoomTorches(decoRng) {
        torches = []
        for (let room of rooms) {
            let gy = room.y + room.h
            if (gy >= gridHeight) continue
            let spots = []
            for (let gx = room.x; gx < room.x + room.w; gx++)
                if (grid[gy][gx] === cellWall && grid[gy - 1][gx] !== cellWall)
                    spots.push(gx)
            if (spots.length === 0) continue
            let count = room.w >= 7 && spots.length >= 4 ? 2 : 1
            for (let i = 0; i < count; i++) {
                // Spread two torches across the wall, one sits near the middle
                let t = count === 1 ? 0.5 : (i === 0 ? 0.25 : 0.75)
                t += (decoRng() - 0.5) * 0.15
                let gx = spots[Math.max(0, Math.min(spots.length - 1, Math.round(t * (spots.length - 1))))]
                placeTorch(gx * cellSize + cellSize / 2, gy * cellSize + wallFaceWu * 0.75)
            }
        }
    }

    function placeTorch(wx, wy, color) {
        let t = torchComponent.createObject(glowParent(), {
            xWu: wx, yWu: wy,
            flameColor: color || "#FF9A3C",
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            visible: Qt.binding(() => world.fx)
        })
        dungeonObjects.push(t)
        torches.push(t)
        return t
    }

    // A light rim on wall tops that border walkable ground to their north:
    // the far edge of a wall, catching the same light as the faces.
    Component {
        id: wallRimComponent
        Rectangle {
            property real pixelPerUnit: 1
            property real xWu: 0
            property real yWu: 0
            property real widthWu: 1
            x: xWu * pixelPerUnit
            y: (parent ? parent.height : 0) - yWu * pixelPerUnit
            width: widthWu * pixelPerUnit
            height: Math.max(2, pixelPerUnit / 12)
            color: "#5A6A80"
            opacity: 0.8
        }
    }
    function createWallRims() {
        for (let gy = 0; gy < gridHeight - 1; gy++) {
            let gx = 0
            while (gx < gridWidth) {
                let isRim = grid[gy][gx] === cellWall && grid[gy + 1][gx] !== cellWall
                if (!isRim) { gx++; continue }
                let startX = gx
                while (gx < gridWidth && grid[gy][gx] === cellWall && grid[gy + 1][gx] !== cellWall)
                    gx++
                let r = wallRimComponent.createObject(world.room, {
                    xWu: startX * cellSize, yWu: (gy + 1) * cellSize,
                    widthWu: (gx - startX) * cellSize,
                    pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
                    visible: Qt.binding(() => world.fx)
                })
                dungeonObjects.push(r)
            }
        }
    }

    // Brick faces on every wall cell whose southern neighbour is walkable,
    // merged into runs like the walls themselves.
    readonly property real wallFaceWu: 0.7
    function createWallFaces() {
        for (let gy = 1; gy < gridHeight; gy++) {
            let gx = 0
            while (gx < gridWidth) {
                let isFace = grid[gy][gx] === cellWall && grid[gy - 1][gx] !== cellWall
                if (!isFace) { gx++; continue }
                let startX = gx
                while (gx < gridWidth && grid[gy][gx] === cellWall && grid[gy - 1][gx] !== cellWall)
                    gx++
                let f = wallFaceComponent.createObject(world.room, {
                    xWu: startX * cellSize,
                    yWu: gy * cellSize + wallFaceWu,
                    widthWu: (gx - startX) * cellSize,
                    heightWu: wallFaceWu,
                    color: levelType === "village" && !fightRoomActive ? "#34465A" : "#3A4658",
                    pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
                    visible: Qt.binding(() => world.fx)
                })
                dungeonObjects.push(f)
            }
        }
    }

    function spawnPlayer(px, py) {
        console.log("[Game] spawnPlayer at", px, py)
        resetFightRecord()
        player = playerComponent.createObject(world.room, {
            xWu: px, yWu: py,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            gameWorld: world,
            categories: catPlayer,
            collidesWith: catWall | catProjectile,
            // Attack sensor detects enemies
            attackSensorCategories: catPlayer,
            attackSensorCollidesWith: catEnemy
        })
        if (player) {
            console.log("[Game] Player created:", player, "xWu:", player.xWu, "yWu:", player.yWu,
                        "width:", player.width, "height:", player.height,
                        "physics world:", player.world)
        } else {
            console.log("[Game] ERROR: playerComponent.createObject returned null")
        }
    }

    // The spawn table at a depth: Balance.spawn with Balance.depth added
    // once per depth, each number within its cap
    function spawnRolls(d) {
        let sb = Balance.spawn, bd = Balance.depth
        let tough = Math.min(bd.toughCap, 1 - sb.normalChance + d * bd.toughChance)
        let more = Math.floor(d * bd.enemies)
        return {
            enemiesMin: Math.min(bd.enemiesCap, sb.enemiesMin + more),
            enemiesMax: Math.min(bd.enemiesCap, sb.enemiesMax + more),
            weakChance: Math.max(0, sb.weakChance + d * bd.weakChance),
            normalChance: 1 - tough,
            guardianChance: Math.min(bd.typeCap, sb.guardianChance + d * bd.guardianChance),
            guardianChanceTough: Math.min(bd.typeCap, sb.guardianChanceTough + d * bd.guardianChance),
            spitterChance: Math.min(bd.typeCap, sb.spitterChance + d * bd.spitterChance)
        }
    }

    // The tiers of n enemies (0=weak, 1=normal, 2=tough) in the table's
    // mix, shuffled: the mix of a dungeon is the table's, not a roll's luck
    function dealTiers(n, sb, rand) {
        let weak = Math.round(n * sb.weakChance)
        let tough = Math.min(n - weak, Math.round(n * (1 - sb.normalChance)))
        let tiers = []
        for (let i = 0; i < n; i++)
            tiers.push(i < weak ? 0 : i < n - tough ? 1 : 2)
        for (let i = n - 1; i > 0; i--) {
            let j = Math.floor(rand() * (i + 1))
            let t = tiers[i]; tiers[i] = tiers[j]; tiers[j] = t
        }
        return tiers
    }

    // An enemy's attack at a depth
    function enemyAtk(type, d) {
        return Balance.enemy[type].atk + Math.round(d * Balance.depth.atk)
    }

    function spawnEnemy(ex, ey, tier, type) {
        // A rolled tier 0 is the weak tier, not a missing one
        tier = tier === undefined ? 1 : tier
        type = type || "grunt"
        let stats = Balance.enemy[type]
        let ehp = Balance.enemy.tierHp[tier] + stats.hpBonus
        let eatk = enemyAtk(type, depth)
        let edef = stats.def
        let props = {
            xWu: ex, yWu: ey,
            hp: ehp, maxHp: ehp,
            atk: eatk, def: edef,
            tier: tier,
            enemyType: type
        }
        // In a session only the host spawns, for every node
        if (!session.connected)
            _makeEnemy(props)
        else if (session.isHost)
            session.spawnEnemy(props)
    }

    // An enemy item from what it is (props: where it stands, its stats,
    // tier and type); objectId is its replicated object in a session
    function _makeEnemy(props, objectId) {
        objectId = objectId || ""
        if (objectId !== "" && _enemyById[objectId]) return _enemyById[objectId]
        let remote = objectId !== "" && !session.isHost
        let enemy = enemyComponent.createObject(world.room, Object.assign({}, props, {
            objectId: objectId,
            network: objectId !== "" ? session.network : null,
            remote: remote,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            gameWorld: world,
            categories: catEnemy,
            collidesWith: catWall | catPlayer
        }))
        if (enemy) {
            console.log("[Game] Enemy created -", enemy.enemyType, "tier:", enemy.tier, "hp:", enemy.hp,
                        objectId !== "" ? (remote ? "shown for " : "run as ") + objectId : "")
            if (!remote) enemy.target = player
            enemies.push(enemy)
            if (objectId !== "") _enemyById[objectId] = enemy
        } else {
            console.log("[Game] ERROR: enemyComponent.createObject returned null")
        }
        return enemy
    }

    function spawnDeathParticles(wx, wy) {
        let colors = ["#CC4444", "#8B3A3A", "#FF6644", "#AA2222", "#FF8866"]
        for (let i = 0; i < 8; i++) {
            let angle = (i / 8) * Math.PI * 2 + (Math.random() - 0.5)
            let speed = 1.5 + Math.random() * 2.0
            deathParticleComp.createObject(world.room, {
                xWu: wx, yWu: wy,
                velX: Math.cos(angle) * speed,
                velY: Math.sin(angle) * speed,
                color: colors[Math.floor(Math.random() * colors.length)],
                pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
            })
        }
    }

    // In a session the host's spitter fires on every node: each node flies
    // the shot under the host's id for it, and it hurts only that node's
    // knight. That node judges it by its knight's own state - hit, blocked,
    // dodged - and reports it, and the shot goes on every screen
    // (issue #18). One that meets no knight bursts on each screen alone.
    property int _shotCount: 0
    property var _shotById: ({})
    // A shot met a knight: this node's (local) or another's, which reported
    // it; result as Player.takeDamage's, "blocked" for a deflected one
    signal shotEnded(string shotId, string result, bool local)
    function spawnProjectile(px, py, dirX, dirY, damage) {
        let id = "shot" + (++_shotCount)
        if (session.connected && session.isHost)
            session.sendShot({id: id, x: px, y: py, dx: dirX, dy: dirY, damage: damage})
        _flyShot(id, px, py, dirX, dirY, damage)
    }
    // This node's knight met shot id
    function shotLanded(id, result) {
        shotEnded(id, result, true)
        if (session.connected) session.reportStruck({source: "shot", id: id, result: result})
    }
    // Another node's knight met shot id: it goes here too, its impact is
    // the other node's
    function _endShot(id, result) {
        let proj = _shotById[id]
        if (proj && !proj.destroyed) proj.vanish()
        shotEnded(id, result, false)
    }
    function _flyShot(id, px, py, dirX, dirY, damage) {
        let proj = projectileComponent.createObject(world.room, {
            shotId: id,
            xWu: px, yWu: py,
            dirX: dirX, dirY: dirY,
            speed: Balance.projectile.speed,
            damage: damage,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            gameWorld: world,
            // Solid fixture: collides with walls
            categories: catProjectile,
            collidesWith: catWall,
            // Sensor fixture: detects player
            sensorCategories: catProjectile,
            sensorCollidesWith: catPlayer
        })
        if (proj) {
            _shotById[id] = proj
            proj.gone.connect(() => { if (world._shotById[id] === proj) delete world._shotById[id] })
            console.log("[Game] Projectile", id, "spawned at", px.toFixed(1), py.toFixed(1))
        }
    }

    function spawnSpitParticles(wx, wy) {
        let colors = ["#6B8E4A", "#8EBB5A", "#AADD66", "#4A6B2A"]
        for (let i = 0; i < 5; i++) {
            let angle = (i / 5) * Math.PI * 2 + (Math.random() - 0.5)
            let speed = 0.8 + Math.random() * 1.2
            deathParticleComp.createObject(world.room, {
                xWu: wx, yWu: wy,
                velX: Math.cos(angle) * speed,
                velY: Math.sin(angle) * speed,
                color: colors[Math.floor(Math.random() * colors.length)],
                pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
            })
        }
    }

    function spawnDeflectParticles(wx, wy) {
        let colors = ["#7AB8D4", "#A0D0E8", "#FFFFFF", "#4A90A4"]
        for (let i = 0; i < 6; i++) {
            let angle = (i / 6) * Math.PI * 2 + (Math.random() - 0.5)
            let speed = 1.0 + Math.random() * 1.5
            deathParticleComp.createObject(world.room, {
                xWu: wx, yWu: wy,
                velX: Math.cos(angle) * speed,
                velY: Math.sin(angle) * speed,
                color: colors[Math.floor(Math.random() * colors.length)],
                pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
            })
        }
    }

    // Floating damage number component
    Component {
        id: damageNumberComp
        Text {
            id: _dmgText
            property real pixelPerUnit: 1
            property real xWu: 0
            property real yWu: 0
            property real startYWu: 0
            x: xWu * pixelPerUnit - width / 2
            y: parent ? parent.height - yWu * pixelPerUnit - height : 0
            font.pixelSize: 14
            font.bold: true
            style: Text.Outline
            styleColor: "#000000"
            z: 999
            SequentialAnimation {
                running: true
                ParallelAnimation {
                    NumberAnimation { target: _dmgText; property: "yWu"; to: _dmgText.startYWu + 1.5; duration: 600; easing.type: Easing.OutQuad }
                    NumberAnimation { target: _dmgText; property: "opacity"; from: 1.0; to: 0; duration: 600 }
                }
                ScriptAction { script: _dmgText.destroy() }
            }
        }
    }

    function spawnDamageNumber(wx, wy, amount, color) {
        if (!debugMechanics) return
        damageNumberComp.createObject(world.room, {
            xWu: wx, yWu: wy + 0.5,
            startYWu: wy + 0.5,
            text: "" + amount,
            color: color,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
        })
    }

    function spawnParryEffect(wx, wy) {
        let colors = ["#FFD700", "#FFFFFF", "#FFE866", "#FFFFAA"]
        for (let i = 0; i < 5; i++) {
            let angle = (i / 5) * Math.PI * 2 + (Math.random() - 0.5)
            let speed = 2.0 + Math.random() * 1.5
            deathParticleComp.createObject(world.room, {
                xWu: wx, yWu: wy,
                velX: Math.cos(angle) * speed,
                velY: Math.sin(angle) * speed,
                color: colors[Math.floor(Math.random() * colors.length)],
                pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
            })
        }
    }

    function blockEntrance() {
        let wx = entranceGridX * cellSize
        let wy = cellSize  // Bottom edge of map
        let wall = createWallAt(wx, wy, cellSize, cellSize)
        wall.opacity = 0  // Invisible blocker
        console.log("[Game] Entrance blocked at grid x=", entranceGridX)
    }

    function placeExitSensor() {
        let wx = exitGridX * cellSize
        let wy = yWuMax  // Top edge of map
        exitSensor = wallComponent.createObject(world.room, {
            xWu: wx, yWu: wy, widthWu: cellSize, heightWu: cellSize,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            categories: catWall,
            collidesWith: catPlayer,
            sensor: true
        })
        exitSensor.opacity = 0
        dungeonObjects.push(exitSensor)
        exitStairs = exitStairsComponent.createObject(world.room, {
            xWu: wx, yWu: wy, widthWu: cellSize, heightWu: cellSize,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            visible: Qt.binding(() => world.fx)
        })
        dungeonObjects.push(exitStairs)
        console.log("[Game] Exit sensor placed at grid x=", exitGridX)
    }

    function clearDungeon() {
        exitSensor = null
        exitStairs = null

        // Destroy enemies. In a session the host despawns its enemies on
        // every node; a joiner's go when the host's do, which may already
        // be the next level's
        for (let e of enemies.slice()) {
            if (!e || e.destroyed) continue
            if (e.objectId !== "" && session.connected) {
                if (session.isHost) session.despawnEnemy(e.objectId)
                continue
            }
            try { e.destroy() } catch(err) {}
        }
        enemies = enemies.filter(e => e && !e.destroyed && e.remote && session.connected)

        // Destroy remote players
        session.clearRemotePlayers()

        // Destroy player
        if (player) {
            try { player.destroy() } catch(err) {}
            player = null
        }

        // Destroy all tracked dungeon objects (walls, floors)
        for (let obj of dungeonObjects) {
            try { if (obj) obj.destroy() } catch(err) {}
        }
        dungeonObjects = []
        torches = []
        stains = []
        // A blow held for the last level's enemy does not land in the next
        _heldBlows = []
        _parriedAt = {}
        _shotById = {}

        grid = []
        rooms = []
    }

    function resetDungeon() {
        _enterLevel(levelIndex + 1)
        resetting = false
    }

    // --- Village/Camp generation ---
    function generateVillage() {
        if (masterSeed < 0)
            masterSeed = Math.floor(Math.random() * 2147483647)
        let levelSeed = deriveSeed(masterSeed, levelIndex)
        rng = createRng(levelSeed)
        console.log("[Game] Village - Seed:", masterSeed, "Level:", levelIndex)

        let roomSize = 20
        let ox = Math.floor((gridWidth - roomSize) / 2)
        let oy = Math.floor((gridHeight - roomSize) / 2)

        // Initialize grid and carve village area
        initializeGrid()
        initExploredCells()
        for (let y = oy; y < oy + roomSize; y++)
            for (let x = ox; x < ox + roomSize; x++) {
                grid[y][x] = cellRoom
                exploredCells[y][x] = true
            }

        // Entrance at bottom, exit at top
        let entranceX = Math.floor(ox + roomSize / 2)
        let exitX = entranceX
        for (let y = 0; y < oy; y++) grid[y][entranceX] = cellHallway
        for (let y = oy + roomSize; y < gridHeight; y++) grid[y][exitX] = cellHallway
        entranceGridX = entranceX
        exitGridX = exitX

        // Build walls and floor (cool blue palette)
        let floorObj = floorComponent.createObject(world.room, {
            xWu: 0, yWu: yWuMax, widthWu: xWuMax, heightWu: yWuMax,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            fx: Qt.binding(() => world.fx),
            style: levelType === "village" && !fightRoomActive ? "earth" : "stone",
            seed: (levelIndex * 0.137) % 1
        })
        floorObj.color = "#2A3A4A"
        dungeonObjects.push(floorObj)
        createMergedWalls()
        createBoundaryWalls()
        createWallFaces()
        createWallRims()
        updateOccluders()
        spawnMotes()

        // Room center in world units
        let cx = (ox + roomSize / 2) * cellSize
        let cy = (oy + roomSize / 2) * cellSize

        // Campfire (bottom-center of village)
        let cf = campfireComponent.createObject(world.room, {
            xWu: cx, yWu: cy - 3,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            gameWorld: world
        })
        dungeonObjects.push(cf)

        // Tavern building (top-left) — entrance facing south
        _buildVillageBuilding(cx - 8, cy + 5, 6, 5, "south")
        // Innkeeper NPC with routine
        _spawnVillageNpc(cx - 8, cy + 4, "#C9A227", "mug", "Innkeeper", [
            { x: cx - 8, y: cy + 6, duration: 4, text: "*polishing mugs*" },
            { x: cx - 8, y: cy + 4, duration: 3, text: "*sweeping floor*" },
            { x: cx - 9, y: cy + 3, duration: 2, text: "*checking supplies*" }
        ], [
            "Welcome, traveler! You look like you've seen better days.",
            "Rest by the campfire — it'll patch you right up.",
            "The deeper floors have nastier creatures. Be careful."
        ], "assets/innkeeper_greeting.wav")

        // Blacksmith building (top-right) — entrance facing south
        _buildVillageBuilding(cx + 6, cy + 5, 6, 5, "south")
        // Anvil in front of blacksmith
        _spawnAnvil(cx + 6, cy + 2)
        // Blacksmith NPC with routine
        _spawnVillageNpc(cx + 6, cy + 4, "#B87333", "hammer", "Blacksmith", [
            { x: cx + 6, y: cy + 2, duration: 5, text: "*hammering*" },
            { x: cx + 6, y: cy + 6, duration: 3, text: "*sorting tools*" },
            { x: cx + 5, y: cy + 4, duration: 2, text: "*inspecting blade*" }
        ], [
            "Ah, another one from the depths. Your blade's seen some work.",
            "I could sharpen that for you... if I had the right stone.",
            "Bring me materials from below and I'll forge something proper."
        ], "assets/blacksmith_greeting.wav")

        // Tree at village edge (dark green static object)
        let tree = wallComponent.createObject(world.room, {
            xWu: cx - 6, yWu: cy - 5,
            widthWu: 1.0, heightWu: 1.0,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            categories: catWall,
            collidesWith: catPlayer,
            color: "#2A4A2A"
        })
        tree.radius = tree.width * 0.5
        dungeonObjects.push(tree)

        // Witch — fortune teller near the tree
        _spawnVillageNpc(cx - 5, cy - 5, "#7B2D8E", "crystal", "Witch", [
            { x: cx - 6, y: cy - 4.5, duration: 4, text: "*gazing into crystal*" },
            { x: cx - 4, y: cy - 5, duration: 3, text: "*muttering softly*" },
            { x: cx - 5, y: cy - 5.5, duration: 2, text: "*reading the stars*" }
        ], [
            "The stones whisper of what lies below...",
            "I see shapes in the dark — hungry ones.",
            "Beware the hollow chamber. Something ancient stirs.",
            "Return to me... if you survive."
        ], "assets/witch_greeting.wav")

        // Spawn player at entrance
        spawnPlayer(cx, (oy + 2) * cellSize)
        session.spawnRemotePlayers(cx, (oy + 2) * cellSize)

        // Block entrance + exit sensor
        blockEntrance()
        placeExitSensor()

        // Bind controls
        if (player) {
            player.moveX = Qt.binding(() => gameCtrl.axisX)
            player.moveY = Qt.binding(() => -gameCtrl.axisY)
            player.mouseScreenX = Qt.binding(() => mouseInput.mouseX)
            player.mouseScreenY = Qt.binding(() => mouseInput.mouseY)
            player.playerScreenX = Qt.binding(() => playerScreenX)
            player.playerScreenY = Qt.binding(() => playerScreenY)
            gameCamera.target = player
            revealAroundPlayer()
        }

        console.log("[Game] Village generated")
    }

    function _buildVillageBuilding(cx, cy, bw, bh, entrance) {
        // All params in world units. Builds 3 walls with one side open.
        let wallColor = "#1E2E3E"
        let t = 0.5  // Wall thickness in wu
        let x1 = cx - bw / 2
        let x2 = cx + bw / 2
        let y1 = cy - bh / 2
        let y2 = cy + bh / 2

        // Top wall (always present)
        createWallAt(x1, y2 + t, bw, t).color = wallColor
        // Left wall
        createWallAt(x1, y2 + t, t, bh + t).color = wallColor
        // Right wall
        createWallAt(x2 - t, y2 + t, t, bh + t).color = wallColor
        // Bottom wall (skip if entrance is south)
        if (entrance !== "south")
            createWallAt(x1, y1 + t, bw, t).color = wallColor
        // Lanterns flanking the open front
        if (entrance === "south") {
            placeTorch(x1 + t / 2, y1 + 0.35, "#FFC870")
            placeTorch(x2 - t / 2, y1 + 0.35, "#FFC870")
        }
    }

    function _spawnVillageNpc(wx, wy, color, iconType, name, routine, dialogue, greeting) {
        let npc = npcComponent.createObject(world.room, {
            xWu: wx, yWu: wy,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            gameWorld: world,
            categories: catWall,
            collidesWith: catPlayer,
            interactionCategories: catWall,
            interactionCollidesWith: catPlayer,
            npcColor: color,
            iconType: iconType,
            npcName: name || "",
            routine: routine || [],
            dialogueLines: dialogue || [],
            greetingSound: greeting || ""
        })
        dungeonObjects.push(npc)
    }

    function _spawnAnvil(wx, wy) {
        let anvil = wallComponent.createObject(world.room, {
            xWu: wx, yWu: wy,
            widthWu: 0.6, heightWu: 0.4,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            categories: catWall,
            collidesWith: catPlayer,
            color: "#333344"
        })
        dungeonObjects.push(anvil)
    }

    // --- Fight Room ---
    function enterFightRoom() {
        console.log("[Game] Entering fight room")
        clearDungeon()
        fightRoomActive = true

        // Simple walled room: 15x15 cells centered
        let roomSize = 15
        let ox = Math.floor((gridWidth - roomSize) / 2)
        let oy = Math.floor((gridHeight - roomSize) / 2)

        // Initialize grid and carve room
        initializeGrid()
        initExploredCells()
        for (let y = oy; y < oy + roomSize; y++)
            for (let x = ox; x < ox + roomSize; x++) {
                grid[y][x] = cellRoom
                exploredCells[y][x] = true
            }

        // Build walls and floor
        let floorObj = floorComponent.createObject(world.room, {
            xWu: 0, yWu: yWuMax, widthWu: xWuMax, heightWu: yWuMax,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            fx: Qt.binding(() => world.fx),
            style: levelType === "village" && !fightRoomActive ? "earth" : "stone",
            seed: (levelIndex * 0.137) % 1
        })
        dungeonObjects.push(floorObj)
        createMergedWalls()
        createBoundaryWalls()
        createWallFaces()
        createWallRims()
        updateOccluders()
        spawnMotes()
        rooms = [{x: ox, y: oy, w: roomSize, h: roomSize}]
        placeRoomTorches(createRng(7))

        // Spawn player at center
        let cx = (ox + roomSize / 2) * cellSize
        let cy = (oy + roomSize / 2) * cellSize
        _fightRoomCx = cx
        _fightRoomCy = cy
        spawnPlayer(cx, cy)

        // Bind controls
        if (player) {
            player.moveX = Qt.binding(() => gameCtrl.axisX)
            player.moveY = Qt.binding(() => -gameCtrl.axisY)
            player.mouseScreenX = Qt.binding(() => mouseInput.mouseX)
            player.mouseScreenY = Qt.binding(() => mouseInput.mouseY)
            player.playerScreenX = Qt.binding(() => playerScreenX)
            player.playerScreenY = Qt.binding(() => playerScreenY)
            gameCamera.target = player
        }

        // Spawn the fight room's enemies
        _spawnFightRoomEnemies()
    }

    // Auto-respawn enemies in fight room when all dead
    Timer {
        id: fightRoomRespawn
        interval: Balance.spawn.fightRoomRespawn * 1000
        repeat: true
        running: fightRoomActive
        onTriggered: {
            if (!player) return
            let alive = 0
            for (let e of enemies)
                if (e && e.destroyed === false) alive++
            if (alive > 0) return
            enemies = []
            _spawnFightRoomEnemies()
            console.log("[Game] Fight room: respawned enemies")
        }
    }

    function _spawnFightRoomEnemies() {
        for (let e of Balance.spawn.fightRoom)
            spawnEnemy(_fightRoomCx + e.dx, _fightRoomCy + e.dy, e.tier, e.type)
    }

    function exitFightRoom() {
        console.log("[Game] Exiting fight room")
        fightRoomActive = false
        clearDungeon()
        generateDungeon()
    }

    // --- Dojo scenarios: land a reload directly in the scene under test ---
    // A fixed seed keeps the layout identical across reloads, so before/after
    // captures compare the same room.
    readonly property int scenarioSeed: 424242
    function scenarios() { return ["dungeon", "village", "fight"] }
    // depth (0 when left out) is the depth the dungeon, the village or the
    // fight room is at, e.g. applyScenario("dungeon", 4) through eval
    function applyScenario(name, atDepth) {
        let d = Math.max(0, Math.floor(atDepth || 0))
        muted = true
        masterSeed = scenarioSeed
        if (player) clearDungeon()
        fallen = false
        fightRoomActive = false
        // Generate before leaving the title: with a player in place,
        // _tryStartGame() does not build a second level on top.
        let type = name === "village" ? "village" : "dungeon"
        levelIndex = levelIndexOf(d, type)
        levelType = type
        _startRunRecord()
        if (name === "fight")
            enterFightRoom()
        else if (name === "village")
            generateVillage()
        else
            generateDungeon()
        screen = "game"
        minimap.requestPaint()
        world.forceActiveFocus()
    }

    // --- Seeded PRNG (mulberry32) ---
    function createRng(seed) {
        let s = seed | 0
        return function() {
            s = (s + 0x6D2B79F5) | 0
            var t = Math.imul(s ^ (s >>> 15), 1 | s)
            t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296
        }
    }

    function deriveSeed(master, index) {
        return (master * 2654435761 + index * 2246822519) | 0
    }

    // --- Line-of-sight (Bresenham on grid) ---
    function hasLineOfSight(x1Wu, y1Wu, x2Wu, y2Wu) {
        let gx0 = Math.floor(x1Wu / cellSize)
        let gy0 = Math.floor(y1Wu / cellSize)
        let gx1 = Math.floor(x2Wu / cellSize)
        let gy1 = Math.floor(y2Wu / cellSize)

        let dx = Math.abs(gx1 - gx0)
        let dy = Math.abs(gy1 - gy0)
        let sx = gx0 < gx1 ? 1 : -1
        let sy = gy0 < gy1 ? 1 : -1
        let err = dx - dy

        while (true) {
            if (gx0 < 0 || gx0 >= gridWidth || gy0 < 0 || gy0 >= gridHeight)
                return false
            if (grid[gy0][gx0] === cellWall)
                return false
            if (gx0 === gx1 && gy0 === gy1)
                return true
            let e2 = 2 * err
            if (e2 > -dy) { err -= dy; gx0 += sx }
            if (e2 < dx)  { err += dx; gy0 += sy }
        }
    }

    // --- A* pathfinder on grid ---
    function findPath(x1Wu, y1Wu, x2Wu, y2Wu) {
        let sx = Math.floor(x1Wu / cellSize)
        let sy = Math.floor(y1Wu / cellSize)
        let ex = Math.floor(x2Wu / cellSize)
        let ey = Math.floor(y2Wu / cellSize)

        // Clamp to grid
        sx = Math.max(0, Math.min(gridWidth - 1, sx))
        sy = Math.max(0, Math.min(gridHeight - 1, sy))
        ex = Math.max(0, Math.min(gridWidth - 1, ex))
        ey = Math.max(0, Math.min(gridHeight - 1, ey))

        // Snap start/end to nearest walkable cell if on a wall
        function snapToWalkable(cx, cy) {
            if (grid[cy][cx] !== cellWall) return {x: cx, y: cy}
            let dirs = [[0,1],[0,-1],[1,0],[-1,0],[1,1],[1,-1],[-1,1],[-1,-1]]
            for (let d of dirs) {
                let nx = cx + d[0], ny = cy + d[1]
                if (nx >= 0 && nx < gridWidth && ny >= 0 && ny < gridHeight
                    && grid[ny][nx] !== cellWall)
                    return {x: nx, y: ny}
            }
            return null
        }
        let s = snapToWalkable(sx, sy)
        let e = snapToWalkable(ex, ey)
        if (!s || !e) return []
        sx = s.x; sy = s.y; ex = e.x; ey = e.y

        // Binary heap (min-heap by f score)
        let open = []
        let closed = new Set()
        let cameFrom = {}
        let gScore = {}

        function key(x, y) { return y * gridWidth + x }
        function heuristic(x, y) { return Math.abs(x - ex) + Math.abs(y - ey) }

        function heapPush(node) {
            open.push(node)
            let i = open.length - 1
            while (i > 0) {
                let p = (i - 1) >> 1
                if (open[p].f <= open[i].f) break
                let tmp = open[p]; open[p] = open[i]; open[i] = tmp
                i = p
            }
        }

        function heapPop() {
            let top = open[0]
            let last = open.pop()
            if (open.length > 0) {
                open[0] = last
                let i = 0
                while (true) {
                    let best = i
                    let l = 2 * i + 1, r = 2 * i + 2
                    if (l < open.length && open[l].f < open[best].f) best = l
                    if (r < open.length && open[r].f < open[best].f) best = r
                    if (best === i) break
                    let tmp = open[best]; open[best] = open[i]; open[i] = tmp
                    i = best
                }
            }
            return top
        }

        let startKey = key(sx, sy)
        gScore[startKey] = 0
        heapPush({x: sx, y: sy, f: heuristic(sx, sy)})

        let dirs = [[1,0],[-1,0],[0,1],[0,-1]]

        while (open.length > 0) {
            let cur = heapPop()
            let ck = key(cur.x, cur.y)

            if (cur.x === ex && cur.y === ey) {
                // Reconstruct path as world-unit waypoints
                let path = []
                let k = ck
                while (k !== undefined) {
                    let py = Math.floor(k / gridWidth)
                    let px = k % gridWidth
                    path.unshift(Qt.point(px * cellSize + cellSize / 2,
                                          py * cellSize + cellSize / 2))
                    k = cameFrom[k]
                }
                return path
            }

            if (closed.has(ck)) continue
            closed.add(ck)

            for (let d of dirs) {
                let nx = cur.x + d[0]
                let ny = cur.y + d[1]
                if (nx < 0 || nx >= gridWidth || ny < 0 || ny >= gridHeight) continue
                if (grid[ny][nx] === cellWall) continue
                let nk = key(nx, ny)
                if (closed.has(nk)) continue
                let ng = gScore[ck] + 1
                if (gScore[nk] === undefined || ng < gScore[nk]) {
                    gScore[nk] = ng
                    cameFrom[nk] = ck
                    heapPush({x: nx, y: ny, f: ng + heuristic(nx, ny)})
                }
            }
        }

        return [] // No path found
    }

    // --- Screen Overlays ---

    // Fallen screen (over the dungeon, under the title)
    Loader {
        anchors.fill: parent
        z: 4500
        active: fallen && screen === "game"
        sourceComponent: Component {
            FallenScreen {
                depth: world.depth
                kills: world.runKills
                seconds: world.runSeconds
                bestDepth: world.bestDepth
                newBest: world.depth > world.runStartBest
                canGoAgain: !session.connected
                partyFights: session.connected
                onGoAgain: world.newRun()
                onBackToTitle: world.backToTitle()
            }
        }
    }

    // Title screen (covers everything when active)
    Loader {
        anchors.fill: parent
        z: 5000
        active: screen === "title"
        sourceComponent: Component {
            TitleScreen {
                muted: world.muted
                onSinglePlayerSelected: { screen = "game"; world.forceActiveFocus() }
                onMultiplayerSelected: screen = "lobby"
            }
        }
    }
}
