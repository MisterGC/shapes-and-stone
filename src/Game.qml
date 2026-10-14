import QtQuick
import Box2D
import Clayground.Common
import Clayground.Algorithm
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
    // The player's Music and Sound settings from the Esc menu, 0..1 in
    // steps of a tenth: every track and sound plays at its own volume
    // times one of them. Kept with the record (keys "musicVolume" and
    // "soundVolume"); M still mutes both
    property real musicVolume: 1
    property real soundVolume: 1
    function setVolume(which, value) {
        let v = Math.round(Math.max(0, Math.min(1, value)) * 10) / 10
        if (which === "music") {
            musicVolume = v
            records.set("musicVolume", String(v))
        } else {
            soundVolume = v
            records.set("soundVolume", String(v))
            // Heard at the new share, so the setting can be judged by ear
            volumeTick.play()
        }
    }
    function _loadVolumes() {
        let read = key => {
            let v = parseFloat(records.get(key, "1"))
            return isNaN(v) ? 1 : Math.max(0, Math.min(1, v))
        }
        musicVolume = read("musicVolume")
        soundVolume = read("soundVolume")
    }

    // Atmosphere layer (lighting, procedural ground, screen effects).
    // V toggles it for a before/after comparison.
    property bool fx: true

    // Audio — switches based on levelType
    LoopMusic {
        id: dungeonAmbience
        source: "assets/dungeon_ambience.mp3"
        level: muted ? 0 : 0.4 * musicVolume
        loop: true
    }

    LoopMusic {
        id: dungeonMusic
        source: "assets/dungeon_music.mp3"
        level: muted ? 0 : 0.3 * musicVolume
        loop: true
    }

    LoopMusic {
        id: villageAmbience
        source: "assets/village_ambience.mp3"
        level: muted ? 0 : 0.4 * musicVolume
        loop: true
    }

    LoopMusic {
        id: villageMusic
        source: "assets/village_music.mp3"
        level: muted ? 0 : 0.35 * musicVolume * campSounds.musicShare
        loop: true
    }

    // The camp's near sounds, each at its source, and the music stepping
    // back while every knight rests (issue #147)
    CampSounds { id: campAudio; game: world; party: session }
    readonly property alias campSounds: campAudio

    onLevelTypeChanged: {
        if (levelType === "village") {
            dungeonAmbience.halt()
            dungeonMusic.halt()
            villageAmbience.start()
            villageMusic.start()
        } else {
            villageAmbience.halt()
            villageMusic.halt()
            dungeonAmbience.start()
            dungeonMusic.start()
        }
    }



    Sound {
        id: impactSound
        source: "assets/punch_hitting.wav"
        volume: muted ? 0 : 0.7 * soundVolume
    }

    Sound {
        id: dashSound
        source: "assets/dash.wav"
        volume: muted ? 0 : 0.6 * soundVolume
    }

    // gain (0..1) is for sounds of another player's knight, see remoteGain()
    function playImpact(gain) {
        impactSound.triggerOneShot(gain === undefined ? 1 : gain)
    }

    Sound {
        id: deathBurstSound
        source: "assets/burst.wav"
        volume: muted ? 0 : 0.7 * soundVolume
    }

    Sound {
        id: swordSwingSound
        source: "assets/sword_swing.wav"
        volume: muted ? 0 : 0.5 * soundVolume
    }

    function playDash(gain) {
        dashSound.triggerOneShot(gain === undefined ? 1 : gain)
    }

    // The shield's own sound: a metal clang, so a block never sounds like
    // a hit, and a perfect block brighter
    Sound {
        id: shieldClangSound
        source: "assets/shield_clang.wav"
        volume: muted ? 0 : 0.7 * soundVolume
    }
    function playBlock(gain, perfect) {
        shieldClangSound.triggerNote(shieldClangSound.rootNote
                                     + (perfect ? Balance.perfectBlock.pitch : Balance.block.pitch),
                                     gain === undefined ? 1 : gain)
    }

    function playSwordSwing(gain) {
        swordSwingSound.triggerOneShot(gain === undefined ? 1 : gain)
    }
    // The charged swing: the swing sample pitched down, heavier
    function playHeavySwing(gain) {
        swordSwingSound.triggerNote(swordSwingSound.rootNote + Balance.heavy.swingPitch,
                                    gain === undefined ? 1 : gain)
    }
    // The whirlwind: the swing sample pitched further down, a long spin,
    // The knight's footsteps (Balance.steps), only this node's own
    Sound {
        id: footstepSound
        source: "assets/footstep.wav"
        volume: muted ? 0 : Balance.steps.volume * soundVolume
    }
    property int _foot: 0
    function playStep() {
        let p = Balance.steps.pitches
        footstepSound.triggerNote(footstepSound.rootNote + p[_foot++ % p.length], 1)
    }
    // and the knight's shout of a special move
    Sound {
        id: whirlShoutSound
        source: "assets/knight_whirl_shout.wav"
        volume: muted ? 0 : Balance.whirl.shoutVolume * soundVolume
    }
    function playWhirlwind(gain) {
        swordSwingSound.triggerNote(swordSwingSound.rootNote + Balance.whirl.swingPitch,
                                    gain === undefined ? 1 : gain)
        whirlShoutSound.triggerNote(whirlShoutSound.rootNote + Balance.whirl.shoutPitch,
                                    gain === undefined ? 1 : gain)
    }
    // The charge is full: a high tick
    Sound {
        id: chargeTickSound
        source: "assets/menu_change.wav"
        volume: muted ? 0 : 0.6 * soundVolume
    }
    function playChargeFull(gain) {
        chargeTickSound.triggerNote(chargeTickSound.rootNote + Balance.heavy.tickPitch,
                                    gain === undefined ? 1 : gain)
    }

    // A Sound step in the Esc menu: the menu's tick at the new share
    Sound {
        id: volumeTick
        source: "assets/menu_change.wav"
        volume: muted ? 0 : 0.6 * soundVolume
    }
    // Gold picked up: a coin's clink, once however many drops it was
    Sound {
        id: coinSound
        source: "assets/coin_pickup.wav"
        volume: muted ? 0 : 0.5 * soundVolume
    }
    function _clink() { coinSound.play() }

    // The knight's own hurt: a low thud, never the punch of a sword
    Sound {
        id: hurtSound
        source: "assets/knight_hurt.wav"
        volume: muted ? 0 : 0.8 * soundVolume
    }
    function playHurt(gain) {
        hurtSound.triggerOneShot(gain === undefined ? 1 : gain)
    }

    // The shield breaking at 0 mana, and the right button with no mana
    Sound {
        id: shieldBreakSound
        source: "assets/shield_break.wav"
        volume: muted ? 0 : 0.7 * soundVolume
    }
    function playShieldBreak(gain) {
        shieldBreakSound.triggerOneShot(gain === undefined ? 1 : gain)
    }
    Sound {
        id: shieldEmptySound
        source: "assets/shield_empty.wav"
        volume: muted ? 0 : 0.6 * soundVolume
    }
    function playShieldEmpty() {
        shieldEmptySound.triggerOneShot(1)
    }
    // A spike plate: its click is the menu's tick pitched down, its
    // spikes the swing pitched up (Balance.dungeon.spike...Pitch)
    function playPlateClick() {
        chargeTickSound.triggerNote(chargeTickSound.rootNote + Balance.dungeon.spikeClickPitch, 1)
    }
    function playSpikesRise() {
        swordSwingSound.triggerNote(swordSwingSound.rootNote + Balance.dungeon.spikeRisePitch, 1)
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
        volume: muted ? 0 : 0.6 * soundVolume
    }

    function playSpitShot() {
        spitterSound.play()
    }

    // A tough enemy winds up a crushing blow: a low growl, the spitter's
    // sample pitched down, fading with the distance from this knight
    Sound {
        id: growlSound
        source: "assets/spitter.wav"
        volume: muted ? 0 : 0.8 * soundVolume
    }
    function playCrushGrowl(xWu, yWu) {
        let gain = 1
        if (player) {
            let dx = xWu - player.xWu, dy = yWu - player.yWu
            gain = Math.max(0, 1 - Math.sqrt(dx * dx + dy * dy) / remoteHearingWu)
        }
        if (gain > 0) growlSound.triggerNote(growlSound.rootNote + Balance.crush.growlPitch, gain)
    }

    // A grunt or a guardian winds up its lunge: a goblin's scream, pitched
    // by its tier (Balance.scream), fading as the growl does
    Sound {
        id: screamSound
        source: "assets/goblin_scream.wav"
        volume: muted ? 0 : Balance.scream.volume * soundVolume
    }
    function playScream(xWu, yWu, tier) {
        let gain = 1
        if (player) {
            let dx = xWu - player.xWu, dy = yWu - player.yWu
            gain = Math.max(0, 1 - Math.sqrt(dx * dx + dy * dy) / remoteHearingWu)
        }
        let pitch = Balance.scream.tierPitch[Math.max(0, Math.min(2, tier))] || 0
        if (gain > 0) screamSound.triggerNote(screamSound.rootNote + pitch, gain)
    }

    Sound {
        id: innkeeperGreeting
        source: "assets/innkeeper_greeting.wav"
        volume: muted ? 0 : 0.8 * soundVolume
    }
    Sound {
        id: blacksmithGreeting
        source: "assets/blacksmith_greeting.wav"
        volume: muted ? 0 : 0.8 * soundVolume
    }
    Sound {
        id: witchGreeting
        source: "assets/witch_greeting.wav"
        volume: muted ? 0 : 0.8 * soundVolume
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
    //   kind: enemyHit, heavyHit, enemyBlocked, enemyDeath, playerHit, playerBlocked,
    //         perfectBlock, crushBlow, parry, whirlwind, projectileHit,
    //         projectileDeflected, projectileBurst
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
        case "heavyHit":
            spawnSparks(x - nx * 0.3, y - ny * 0.3, nx, ny, Balance.heavy.sparks, Balance.heavy.glow)
            spawnShards(x, y, nx, ny, 6, color, 0.24)
            spawnRing(x, y, Balance.heavy.glow)
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
            spawnSparks(x, y, -nx, -ny, Balance.block.sparks, "#CFEFFF")
            break
        case "perfectBlock":
            spawnSparks(x, y, -nx, -ny, Balance.perfectBlock.sparks, "#FFFFFF")
            spawnRing(x, y, "#BFE6FF")
            break
        case "crushBlow":
            // The held shield broken: sparks and its shards along the blow
            spawnSparks(x, y, nx, ny, Balance.crush.sparks, Balance.crush.glow)
            spawnShards(x, y, nx, ny, 6, "#9AA4AC", 0.2)
            break
        case "parry":
            spawnSparks(x, y, nx, ny, 14, "#FFE066")
            spawnRing(x, y, "#FFD700")
            break
        case "whirlwind":
            // The spin starts: a ring round the knight, sparks along the dash
            spawnSparks(x, y, nx, ny, Balance.whirl.sparks, Balance.whirl.glow)
            spawnRing(x, y, Balance.whirl.glow)
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
            let legacyShake = {enemyHit: 1.5, heavyHit: 2, enemyBlocked: 0.5, playerHit: 3,
                               playerBlocked: 1, perfectBlock: 1, crushBlow: 3, whirlwind: 1.5,
                               projectileHit: 1, projectileDeflected: 0.5}[kind] || 0
            if (legacyShake > 0) shake(legacyShake)
            return
        }
        switch (kind) {
        case "enemyHit":
            _trauma(0.22); _kick(nx * 0.12, ny * 0.12); _freeze(55)
            break
        case "heavyHit":
            _trauma(Balance.heavy.trauma)
            _kick(nx * Balance.heavy.kick, ny * Balance.heavy.kick)
            _freeze(Balance.heavy.freeze * 1000)
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
            // A block is a success: a short freeze and a kick sell that the
            // shield took it, still well below a hit's
            _trauma(Balance.block.trauma)
            _kick(nx * Balance.block.kick, ny * Balance.block.kick)
            _freeze(Balance.block.freeze * 1000)
            break
        case "perfectBlock":
            _trauma(Balance.perfectBlock.trauma)
            _freeze(Balance.perfectBlock.freeze * 1000, Balance.perfectBlock.freezeScale)
            if (screenFx) screenFx.perfectBlock()
            break
        case "crushBlow":
            // Worse than a hit: the shield is gone with it
            _trauma(Balance.crush.trauma)
            _kick(nx * Balance.crush.kick, ny * Balance.crush.kick)
            _freeze(Balance.crush.freeze * 1000)
            if (screenFx) screenFx.hurt()
            break
        case "parry":
            _trauma(0.3); _freeze(140, 0.12)
            if (screenFx) screenFx.parry()
            break
        case "whirlwind":
            _trauma(Balance.whirl.trauma)
            _kick(nx * Balance.whirl.kick, ny * Balance.whirl.kick)
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
    // Why the title is up, when it was not the player's choice (the host
    // was lost); gone once the title is left
    property string titleMessage: ""

    // Co-op: the connection, the lobby and the remote players
    Session {
        id: session
        z: 5000
        world: world
        player: world.player
        inGame: screen === "game"
        showLobby: screen === "lobby"
        muted: world.muted
        soundVolume: world.soundVolume
        playerName: world.playerName
        recordLine: world.recordLine
        // The host's run, from its start or, on a node that joins late,
        // at the level the host plays
        onStarted: (seed, level, position, next, knights, dm) => {
            masterSeed = seed
            world.levelIndex = level
            world.levelType = levelTypeOf(level)
            master = world.levelType === "dungeon" ? dm || null : null
            _setDanger(position, next)
            _setKnights(knights)
            screen = "game"
        }
        onLevelChanged: (newIndex, position, next, knights, dm) =>
            _applyLevelChange(newIndex, {pos: position, next: next, knights: knights, master: dm || null})
        onWentAgain: (seed, position, knights, dm) => _startRun(seed, position, knights, dm)
        onLiftReceived: (fromId) => _rise("lift")
        onRecordBroken: (banner) => _hostRecordBroken(banner)
        onNameEdited: (name) => world.playerName = name
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
            if (blow.kind === "damage") e.takeRemoteBlow(blow.amount, blow.x, blow.y, fromId, blow.heavy === true)
            else if (blow.kind === "stagger") e.stagger(blow.seconds)
            else if (blow.kind === "push") e.shove(blow.dx, blow.dy, blow.speed)
        }
        onKnightBlowReceived: (blow) => _holdKnightBlow(blow)
        onPartyChanged: _checkPartyDown()
        onRunEnded: _endPartyRun()
        onPlayerLeft: (nodeId) => _dropKnight(nodeId)
        onHostLost: (message) => {
            console.log("[Game]", message, "- back to the title")
            backToTitle()
            titleMessage = message
        }
        onEnemyKillReceived: (kill) => {
            let e = _enemyById[kill.id]
            if (e) e.destroyed = true
            impact("enemyDeath", kill.x, kill.y, kill.dx, kill.dy, kill.color)
            playDeathBurst()
            countFight("kill")
        }
        onGoldSpawned: (objectId, props) => _makeGoldDrop(props, objectId)
        onGoldDespawned: (objectId) => _removeGoldDrop(objectId)
        onGoldClaimed: (fromId, objectId) => _giveGold(fromId, objectId)
        onGoldGranted: (grant) => _collectGold(grant.amount, grant.x, grant.y)
        onBreakReported: (level, cell) => _hostBreak(level, cell)
        onSpringReported: (level, cell, riseAt) => _hostSpring(level, cell, riseAt)
        onDoorReported: (level, cell, open) => _hostDoor(level, cell, open)
        onSecretReported: (level, cell) => _hostSecret(level, cell)
        onShotReceived: (shot) => {
            if (screen !== "game") return
            _flyShot(shot.id, shot.x, shot.y, shot.dx, shot.dy, shot.damage)
            playSpitShot()
        }
        onStruckReported: (fromId, report) => {
            if (report.source === "shot") _endShot(report.id, report.result)
            else if (report.source === "arrow") _arrowReported(report)
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
            if (!k || (k === player ? player.fallen : !k.known || k.remoteHp <= 0)) continue
            let dx = k.xWu - x, dy = k.yWu - y
            let d = dx * dx + dy * dy
            if (d < bestD) { bestD = d; best = k }
        }
        return best
    }
    // The knights on this screen, this node's and the other players',
    // that have not fallen: { knight, x, y, seated }, x and y its centre
    // in wu. The camp's creatures watch them
    function knightsHere() {
        let knights = [player]
        for (let id in session.remotePlayers) knights.push(session.remotePlayers[id])
        let here = []
        for (let k of knights) {
            if (!k || (k === player ? player.fallen : !k.known || k.remoteHp <= 0)) continue
            here.push({ knight: k, x: k.xWu + 0.5, y: k.yWu - 0.5, seated: !!k.seated })
        }
        return here
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
                                                 size: enemy.widthWu, crush: enemy.crushing,
                                                 dx: enemy._dirToTargetX, dy: enemy._dirToTargetY})
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
    // "perfect", "crushed", "dodged", "ignored", "out of reach" or
    // "parried"; a crushing blow is never parried. This
    // screen judges it by its knight's own state, and reports it to the
    // others (issue #18).
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
        let crush = blow.crush === true
        let at = _parriedAt[blow.id]
        if (!crush && at !== undefined && at >= blow.arrived - Balance.enemy.parryFrames) {
            _struck(blow.id, "parried")
            return
        }
        // A dash that carried the knight past the enemy dodged it all the same
        let dx = player.xWu - blow.x, dy = player.yWu - blow.y
        if (Math.sqrt(dx * dx + dy * dy) >= Balance.enemy.lungeHitRange) {
            _struck(blow.id, player.isDashing ? "dodged" : "out of reach")
            return
        }
        // A blow sounds the shield's own block or the knight's hurt, in
        // takeDamage
        let result = player.takeDamage(blow.atk, blow.x, blow.y, blow.size, crush, blow.dx, blow.dy)
        // A blocked one throws the host's enemy back off the shield; a
        // perfect block staggers it, as it does an enemy of this node's,
        // a crushing blow's for the full stagger
        let e = _enemyById[blow.id]
        if (result === "blocked" && e && !e.destroyed) e.recoil(player)
        if (result === "perfect" && e && !e.destroyed)
            e.stagger(crush ? Balance.enemy.stagger : Balance.knight.perfectBlockStagger)
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
    // Host: a player left, its knight is gone; no enemy goes for it any more
    function _dropKnight(nodeId) {
        if (!session.isHost) return
        for (let e of enemies) {
            if (e && !e.destroyed && !e.remote && e.targetId === nodeId) e.dropTarget()
        }
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

    // --- Gold (issue #38) ---
    // A killed enemy drops gold where it fell; the first knight to reach it
    // picks it up, whoever dealt the killing blow. In a session the host
    // owns every drop as it owns the enemies: it spawns them as replicated
    // objects, each node claims the drops its own knight reaches, and the
    // host gives a drop to the first claim it gets and despawns it, so a
    // drop is picked up once, by one knight. Each knight's gold is its own
    // node's.
    property var goldDrops: []
    property var _goldById: ({})
    // Where an enemy died: gold for its tier, none in the fight room
    function dropGold(x, y, tier) {
        if (fightRoomActive) return
        _spawnGold(x, y, Balance.loot.goldByTier[tier] || 0)
    }
    // amount gold at (x, y): this node's own alone, the host's in a session
    function _spawnGold(x, y, amount) {
        if (amount <= 0) return
        let props = {xWu: x, yWu: y, amount: amount}
        if (!session.connected)
            _makeGoldDrop(props)
        else if (session.isHost)
            session.spawnGold(props)
    }
    function _makeGoldDrop(props, objectId) {
        objectId = objectId || ""
        if (objectId !== "" && _goldById[objectId]) return _goldById[objectId]
        let drop = goldDropComponent.createObject(world.room, Object.assign({}, props, {
            objectId: objectId,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
        }))
        if (!drop) return null
        goldDrops.push(drop)
        if (objectId !== "") _goldById[objectId] = drop
        return drop
    }
    function _removeGoldDrop(objectId) {
        let drop = _goldById[objectId]
        if (!drop) return
        delete _goldById[objectId]
        _forgetGoldDrop(drop)
    }
    function _forgetGoldDrop(drop) {
        goldDrops = goldDrops.filter(d => d !== drop)
        try { drop.destroy() } catch (err) {}
    }
    // Each step: the drops this node's knight stands on are its, or
    // claimed from the host in a session
    function _pickUpGold() {
        if (!player || player.fallen || goldDrops.length === 0) return
        let range = Balance.loot.pickupRange
        for (let drop of goldDrops.slice()) {
            if (!drop || drop.claimed) continue
            let dx = drop.xWu - player.xWu, dy = drop.yWu - player.yWu
            if (dx * dx + dy * dy > range * range) continue
            if (drop.objectId === "") {
                _collectGold(drop.amount, drop.xWu, drop.yWu)
                _forgetGoldDrop(drop)
            } else if (session.connected) {
                drop.claimed = true
                session.claimGold(drop.objectId)
            }
        }
    }
    // Host: a node's knight reached a drop; the first claim takes it, a
    // later one finds it gone
    function _giveGold(nodeId, objectId) {
        let drop = _goldById[objectId]
        if (!drop || !session.isHost) return
        let grant = {id: objectId, amount: drop.amount, x: drop.xWu, y: drop.yWu}
        session.despawnGold(objectId)
        if (nodeId === session.nodeId) _collectGold(grant.amount, grant.x, grant.y)
        else session.grantGold(nodeId, grant)
    }
    function _collectGold(amount, x, y) {
        if (!player) return
        player.gold += amount
        spawnDamageNumber(x, y, "+" + amount, "#E8B83A")
        Qt.callLater(_clink)
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

    // --- Danger (issue #96) ---
    // A dungeon's danger is its depth plus a position in [0, 1) in that
    // depth's range, and drives what Balance.depth adds: the more the
    // knights kept of their HP in the last dungeon, the higher the next
    // one stands in its range (Balance.danger). In a village
    // dangerPosition is still the dungeon's just left and nextPosition
    // the next one's, fixed at the exit; in a dungeon nextPosition is what
    // the next one would get were the party to leave now. After the run
    // has ended in a fall, nextPosition is where the next run starts
    property real dangerPosition: Balance.danger.start
    property real nextPosition: Balance.danger.start
    // The overrides the dungeon played now is built with (issue #142):
    // {seed, rooms, enemies, depth, and per feature row its key}, each
    // left out for the game's own, null for a dungeon wholly the game's
    // and for a village. dangerDepth is the depth its danger counts from:
    // the base depth set there, else depth
    property var master: null
    readonly property int dangerDepth: master && master.depth !== undefined ? master.depth : depth
    readonly property real danger: dangerDepth + dangerPosition
    // 0 low, 1 middle, 2 high
    function dangerBand(position) {
        return position < Balance.danger.low ? 0 : position < Balance.danger.high ? 1 : 2
    }
    // The position of the next dungeon: pull of the way from position
    // toward what the last one earned, 1 less the knights' average share
    // of max HP lost, or 0 if any knight fell. records: [{lost, fell}]
    function settleDanger(position, records) {
        if (records.length === 0) return position
        let fell = false, lost = 0
        for (let r of records) {
            fell = fell || r.fell === true
            lost += Math.min(1, Math.max(0, r.lost)) / records.length
        }
        let earned = fell ? 0 : 1 - lost
        let next = position + (earned - position) * Balance.danger.pull
        return Math.max(0, Math.min(Balance.danger.top, next))
    }
    // This knight's record of the level: the share of its max HP it lost -
    // a potion's heal does not take it back - and whether it fell
    function levelRecord() {
        let maxHp = player ? player.maxHp : Balance.knight.hp
        return { lost: Math.min(1, fightRecord.damageTaken / maxHp), fell: fightRecord.deaths > 0 }
    }
    // Every knight's record of the level: this node's and, in a session,
    // each other node's from the last state it sent in this level
    function partyRecords() {
        let out = [levelRecord()]
        for (let id in session.remotePlayers) {
            let st = session.lastStates[id]
            if (st && st.lv === levelIndex && st.l !== undefined)
                out.push({ lost: st.l, fell: st.f === 1 })
        }
        return out
    }
    // The positions the level newIndex is entered at and the knights it is
    // built for: out of a dungeon the next one's position is settled from
    // the party's records, out of a village the next dungeon stands where
    // the exit fixed it
    function _dangerFor(newIndex) {
        if (levelTypeOf(newIndex) === "village")
            return { pos: dangerPosition, next: settleDanger(dangerPosition, partyRecords()),
                     knights: knightsNow() }
        return { pos: nextPosition, next: nextPosition, knights: knightsNow() }
    }
    // Where the next run starts after this one ended in a fall: a fall
    // earns the bottom of the range
    function _dangerAfterFall() {
        let from = levelType === "village" ? nextPosition : dangerPosition
        return settleDanger(from, [{ lost: 1, fell: true }])
    }
    // What a dungeon looks like at its danger: Balance.danger.looks of
    // its band. The village and the fight room keep their own look
    readonly property bool dangerLook: levelType === "dungeon" && !fightRoomActive
    readonly property var look: Balance.danger.looks[dangerBand(dangerPosition)]
    // What the camp looks like at its depth (issue #146): the last of
    // Balance.camp.looks it is deep enough for - a mossy grotto, a miners'
    // hall, an ember camp. The fight room keeps its own look
    readonly property bool campStyled: levelType === "village" && !fightRoomActive
    readonly property var campLook: campLookAt(depth)
    function campLookAt(d) {
        let looks = Balance.camp.looks
        for (let i = looks.length - 1; i > 0; i--)
            if (d >= looks[i].from) return looks[i]
        return looks[0]
    }
    function _setDanger(position, next) {
        if (position === undefined || isNaN(position)) return
        dangerPosition = position
        nextPosition = next === undefined || isNaN(next) ? position : next
        console.log("[Game] Danger", danger.toFixed(3), "next position", nextPosition.toFixed(3))
    }
    // --- The party's size (issue #102) ---
    // The knights the level was built for: a dungeon's enemies grow with
    // them (Balance.party). It is fixed as the level is entered - in a
    // session by the host, sent with the level - so a knight joining or
    // leaving changes the next dungeon, not this one
    property int partyKnights: 1
    // The dojo's knights for the next level, 0 to count the session's:
    // eval knightsOverride = 4, then eval applyScenario("dungeon", 2.5),
    // builds that dungeon for four knights
    property int knightsOverride: 0
    function knightsNow() { return knightsOverride > 0 ? knightsOverride : session.knights }
    function _setKnights(knights) {
        partyKnights = Math.max(1, knights || 1)
        console.log("[Game] Built for", partyKnights, partyKnights === 1 ? "knight" : "knights")
    }
    // --- The witch reads the next dungeon (issue #98) ---
    // What the dungeon at level index holds, read off its seed the way
    // generateDungeon builds it: its depth, its position's band in the
    // depth's range, its enemies counted by tier and type and its secret
    // rooms (secretsOf). Left out,
    // the dungeon is the next one, at nextPosition, for the knights the
    // party has now. In a session every node reads the same: the seed,
    // the position and the knights are the host's
    function foretell(index, position, knights) {
        if (index === undefined) index = levelTypeOf(levelIndex) === "village" ? levelIndex + 1
                                                                                : levelIndex + 2
        if (position === undefined) position = nextPosition
        if (knights === undefined) knights = knightsNow()
        let rand = createRng(deriveSeed(masterSeed, index))
        let rms = planRooms(Balance.spawn.roomsMin, Balance.spawn.roomsMax, Balance.spawn.roomSizeMin, Balance.spawn.roomSizeMax, rand)
        let enemies = rollEnemies(rms, spawnRolls(depthOf(index) + position, knights), rand)
        let out = { depth: depthOf(index), band: dangerBand(position), enemies: enemies.length,
                    weak: 0, normal: 0, tough: 0, grunt: 0, guardian: 0, spitter: 0,
                    secrets: secretsOf(index, position) }
        for (let e of enemies) {
            out[["weak", "normal", "tough"][e.tier]]++
            out[e.type]++
        }
        return out
    }
    // How many secret rooms the dungeon at level index and position holds:
    // carved off its seed by carveDungeon, as generateDungeon carves it,
    // and the level played now put back as it was
    function secretsOf(index, position) {
        let kept = _keepCarved()
        let levelSeed = deriveSeed(masterSeed, index)
        let band = dangerBand(position)
        let n = 0
        try {
            n = carveDungeon(levelSeed, band, false, createRng(levelSeed)).secrets.length
        } finally {
            _putCarved(kept)
        }
        return n
    }
    // What carveDungeon carves on the live grid, kept to put back after a
    // dungeon is carved only to be read
    function _keepCarved() {
        return { grid: grid, rooms: rooms, entranceGridX: entranceGridX, exitGridX: exitGridX,
                 loopCorridors: loopCorridors }
    }
    function _putCarved(kept) {
        grid = kept.grid
        rooms = kept.rooms
        entranceGridX = kept.entranceGridX
        exitGridX = kept.exitGridX
        loopCorridors = kept.loopCorridors
    }
    // The witch's reading of the next dungeon, one line per press of E:
    // where it sits in its depth's range, what lives there and, when it
    // hides one, that a chamber lies behind its stones and how to find it
    function witchReading() {
        let f = foretell()
        let lines = ["Depth " + f.depth + " waits below. It sits "
                     + ["low in its range - the last one cost you dearly",
                        "in the middle of its range",
                        "high in its range - you came through whole, it will not be kind"][f.band]
                     + "."]
        let tiers = [f.tough > 0 ? f.tough + " of them hulking" : "",
                     f.weak > 0 ? f.weak + " feeble" : ""].filter(t => t !== "")
        lines.push("I see " + f.enemies + " shapes in the dark"
                   + (tiers.length > 0 ? ", " + tiers.join(", ") : "") + ".")
        let kinds = [f.guardian > 0 ? f.guardian + " behind shields" : "",
                     f.spitter > 0 ? f.spitter + (f.spitter === 1 ? " that spits" : " that spit")
                                     + " from afar" : ""].filter(t => t !== "")
        lines.push(kinds.length > 0 ? "Among them " + kinds.join(" and ") + "."
                                    : "No shields, nothing that spits - only teeth.")
        if (f.secrets > 0)
            lines.push("And a hidden chamber lies below, behind the stones. Where a wall is cracked "
                       + "and breathes dust, throw yourself at it.")
        lines.push("Return to me... if you survive.")
        return lines
    }

    // --- Dungeon master (issue #142) ---
    // Ticked on the title (kept, key "dungeonMaster"): before each
    // dungeon the host, or a solo player, sees the panel with
    // Balance.dungeonMaster's settings at the values the game would use.
    // A setting turned is set (masterPinned, kept as JSON under
    // "dungeonMasterSettings") for that dungeon and the ones after, until
    // Backspace gives it back to the game. Generate shows the dungeon Go
    // enters, again a new one; Go builds it with the settings as its
    // master. In a session only the host has the panel, and the master
    // goes with the level, so every knight plays the host's dungeon
    property bool dungeonMaster: false
    property var masterPinned: ({})
    // The dungeon the panel is up for: {index, pos, knights, seed (the
    // run's), go(m, pos)}; null while it is not up
    property var masterAsk: null
    // The level seed Generate rolled for it, -1 for the run's own
    property int masterSeedRoll: -1
    // What the panel shows: planDungeon's, null before Generate
    property var masterPreview: null
    property string masterNote: ""
    readonly property bool masterOpen: masterAsk !== null

    function setDungeonMaster(on) {
        dungeonMaster = on
        records.set("dungeonMaster", on ? "1" : "0")
    }
    function _loadMaster() {
        dungeonMaster = records.get("dungeonMaster", "0") === "1"
        let pinned = {}
        try { pinned = JSON.parse(records.get("dungeonMasterSettings", "{}")) } catch (err) {}
        masterPinned = _masterRead(pinned) || {}
    }
    function _keepMaster() { records.set("dungeonMasterSettings", JSON.stringify(masterPinned)) }
    // The settings in o that the table has, each in its range; null when
    // o is no object
    function _masterRead(o) {
        if (!o || typeof o !== "object" || Array.isArray(o)) return null
        let out = {}
        for (let row of Balance.dungeonMaster.settings) {
            let v = Number(o[row.key])
            if (o[row.key] === undefined || o[row.key] === null || isNaN(v)) continue
            out[row.key] = _masterClamp(row, v)
        }
        return out
    }
    function _masterClamp(row, v) {
        let f = Math.pow(10, row.decimals)
        return Math.max(row.min, Math.min(row.max, Math.round(v * f) / f))
    }
    // Whether this node asks the dungeon master before a dungeon
    function _masterAsks() { return dungeonMaster && (!session.connected || session.isHost) }

    // The panel up for ask; the knight lets go of what it holds, as
    // under the Esc menu
    function openMaster(ask) {
        if (player) {
            player.lowerShield()
            player.dropSwing()
        }
        masterSeedRoll = -1
        masterPreview = null
        masterNote = ""
        masterAsk = ask
        session.setMastering(true)
        console.log("[Game] Dungeon master: the panel is up for level", ask.index)
    }
    // The level seed of the panel's dungeon
    function _masterSeed() {
        return masterSeedRoll >= 0 ? masterSeedRoll : deriveSeed(masterAsk.seed, masterAsk.index)
    }
    // The overrides the panel's dungeon is built with: the settings set,
    // the seed Generate rolled; null when it is the game's own
    function masterOverrides() {
        let m = {}
        for (let k in masterPinned) if (k !== "position") m[k] = masterPinned[k]
        if (masterSeedRoll >= 0) m.seed = masterSeedRoll
        return Object.keys(m).length > 0 ? m : null
    }
    function _masterPosition() {
        return masterPinned.position !== undefined ? masterPinned.position : masterAsk.pos
    }
    // What the game would use for each setting of the panel's dungeon,
    // with its seed and the depth, position and rooms set: {key: value}
    function masterGameValues() {
        let a = masterAsk
        let pos = _masterPosition()
        let d = masterPinned.depth !== undefined ? masterPinned.depth : depthOf(a.index)
        let rand = createRng(_masterSeed())
        let sb = Balance.spawn
        let rmin = masterPinned.rooms !== undefined ? masterPinned.rooms : sb.roomsMin
        let rmax = masterPinned.rooms !== undefined ? masterPinned.rooms : sb.roomsMax
        let rms = planRooms(rmin, rmax, sb.roomSizeMin, sb.roomSizeMax, rand)
        let foes = rollEnemies(rms, spawnRolls(d + pos, a.knights), rand)
        let band = dangerBand(pos)
        let out = { enemies: rms.length > 1 ? foes.length / (rms.length - 1) : 0,
                    rooms: rms.length, depth: depthOf(a.index), position: a.pos }
        for (let row of Balance.dungeonMaster.settings)
            if (row.kinds)
                out[row.key] = row.kinds.reduce((t, k) => t + Balance.dungeon.kinds[k].perRoom[band], 0)
        return out
    }
    // The panel's rows: [{key, label, value, set, text}]
    function masterRows() {
        if (!masterAsk) return []
        let game = masterGameValues()
        return Balance.dungeonMaster.settings.map(row => {
            let set = masterPinned[row.key] !== undefined
            let v = set ? masterPinned[row.key] : game[row.key]
            let text = Number(v).toFixed(row.decimals)
            if (row.key === "position") text += " " + ["low", "middle", "high"][dangerBand(v)]
            return { key: row.key, label: row.label, value: v, set: set, text: text }
        })
    }
    // A setting turned by steps of its row: set from what it shows
    function masterTurn(key, steps) {
        let row = Balance.dungeonMaster.settings.find(r => r.key === key)
        if (!row || !masterAsk) return
        let shown = masterRows().find(r => r.key === key).value
        let p = Object.assign({}, masterPinned)
        p[key] = _masterClamp(row, shown + steps * row.step)
        masterPinned = p
        _keepMaster()
        if (masterPreview) _masterShow()
    }
    // A setting given back to the game
    function masterUnset(key) {
        if (masterPinned[key] === undefined) return
        let p = Object.assign({}, masterPinned)
        delete p[key]
        masterPinned = p
        _keepMaster()
        if (masterPreview) _masterShow()
    }
    // Generate: the dungeon Go enters; once one is shown, a new one on a
    // new seed
    function masterGenerate() {
        if (!masterAsk) return
        if (masterPreview) {
            let seed
            do { seed = Math.floor(Math.random() * 2147483647) } while (seed === _masterSeed())
            masterSeedRoll = seed
        }
        _masterShow()
    }
    function _masterShow() {
        masterPreview = planDungeon(masterAsk.index, _masterPosition(), masterAsk.knights,
                                    masterOverrides(), masterAsk.seed)
    }
    // Go: the panel's dungeon is entered, built with its overrides
    function masterGo() {
        if (!masterAsk) return
        let a = masterAsk, m = masterOverrides(), pos = _masterPosition()
        masterAsk = null
        masterPreview = null
        session.setMastering(false)
        console.log("[Game] Dungeon master: go,", JSON.stringify(m), "at position", pos.toFixed(3))
        a.go(m, pos)
    }
    // Copy settings: the settings set, as JSON; Paste settings sets
    // exactly those of a copied text, false when it holds none
    function masterSettingsJson() { return JSON.stringify(masterPinned) }
    function masterPaste(text) {
        let o = null
        try { o = _masterRead(JSON.parse(text)) } catch (err) {}
        if (!o) {
            masterNote = "The clipboard holds no settings"
            return false
        }
        masterPinned = o
        _keepMaster()
        masterNote = "Settings pasted"
        if (masterPreview) _masterShow()
        return true
    }
    // The dungeon at level index and position, for knights, with the
    // overrides m (null for the game's own) on the run's seed: carved and
    // its enemies rolled as generateDungeon does, without touching the
    // world, the level played now put back as it was. {seed, band, depth,
    // grid, rooms, features, doors, secrets, enemies, entranceGridX,
    // exitGridX}
    function planDungeon(index, position, knights, m, runSeed) {
        let kept = _keepCarved()
        try {
            let levelSeed = m && m.seed !== undefined ? m.seed
                                                       : deriveSeed(runSeed === undefined ? masterSeed : runSeed, index)
            let spec = dungeonSpec(position, m)
            let rand = createRng(levelSeed)
            let plan = carveDungeon(levelSeed, spec.band, false, rand, spec)
            let d = m && m.depth !== undefined ? m.depth : depthOf(index)
            let foes = rollEnemies(rooms, spec.rolls(d + position, knights), rand)
            return { seed: levelSeed, band: spec.band, depth: d, position: position, grid: grid,
                     rooms: rooms, features: plan.features, doors: plan.doors, secrets: plan.secrets,
                     enemies: foes, entranceGridX: entranceGridX, exitGridX: exitGridX }
        } finally {
            _putCarved(kept)
        }
    }
    // The knight is at 0 HP: the enemies stand still and the fallen screen
    // offers a new run or the title
    property bool fallen: false
    // A session's run ended with every knight down: the session stays, the
    // fallen screen shows the run's summary, and the host's Enter starts
    // the next run for everyone
    property bool partyFallen: false
    // Esc opened the menu (Resume, Title). Alone the world is paused under
    // it; in a session it runs on, since a pause would stop every other
    // player's enemies, and only this knight stops taking input.
    property bool menuOpen: false
    // C opened the knight panel: stats, pack and the smith's upgrades. It
    // only shows, nothing pauses and the knight keeps the keys
    property bool knightPanelOpen: false
    readonly property bool gamePaused: menuOpen && !session.connected
    // The title, the lobby, the pause menu and the fallen screen each take
    // the keys while they are up; when the last of them closes the game
    // takes them back, so the knight answers the keys without a click
    readonly property bool overlayUp: screen !== "game" || menuOpen || fallen
    onOverlayUpChanged: if (!overlayUp) world.forceActiveFocus()
    // Paused by stopping the world: the first step after resuming is one
    // frame long, not the whole pause (clayground#338), so no cooldown or
    // AI timer runs out on it.
    Binding {
        target: world.physics
        property: "running"
        value: false
        when: world.gamePaused
        restoreMode: Binding.RestoreBindingOrValue
    }
    components: []

    // The run so far, for the fallen screen: the enemies killed and the
    // simulated seconds since it started (a pause holds them)
    property int runKills: 0
    property real runSeconds: 0
    // The secret rooms the party opened this run
    property int runSecrets: 0
    // The record of the deepest descent on this machine: the depth (-1
    // before the first), the knights' names and the date, kept with
    // Clayground.Storage as soon as a run gets deeper (key "record", and
    // its depth alone under "bestDepth"). A joiner keeps the party's
    // descent in its own record too
    property var ownRecord: ({depth: -1, names: [], date: ""})
    readonly property int bestDepth: ownRecord.depth
    // The record every screen shows: alone this machine's, in a session
    // the host's, the party's
    readonly property var record: session.connected && !session.isHost
                                  ? (session.hostRecord || {depth: -1, names: [], date: ""})
                                  : ownRecord
    readonly property string recordLine: record.depth < 0 ? ""
        : "Record " + record.depth + (record.names && record.names.length > 0
                                      ? "  •  " + record.names.join(", ") : "")
          + (record.date ? "  •  " + record.date : "")
    // This machine's record's depth when this run started, and whether
    // the run went deeper: alone and on the host the first dungeon deeper
    // than it raises the banner, on a joiner the host's word does
    property int runStartRecord: -1
    property bool recordPassed: false
    // The banner was raised: once per run, on the step the depth passes
    // the record, on every screen of a session
    signal recordBanner(int depth)
    // This session's runs, newest first ({depth, seconds}): alone since
    // the game started, in a session the host's since it was hosted
    property var ownRuns: []
    readonly property var sessionRuns: session.connected && !session.isHost ? session.hostRuns : ownRuns
    // The lobby's name of this machine's knight, kept with the record
    property string playerName: "Knight"
    // A bench keeps its record apart from the player's with its own name
    property string recordStoreName: "ShapesAndStone"
    KeyValueStore { id: records; name: world.recordStoreName }
    function _startRunRecord() {
        runKills = 0
        runSeconds = 0
        runSecrets = 0
        runStartRecord = ownRecord.depth
        recordPassed = false
    }
    function _today() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }
    // The knights of this run: alone this one, in a session every node's
    function _partyNames() { return session.connected ? session.partyNames() : [playerName] }
    // The run is at a new depth or has ended: deeper than this machine's
    // record, it is kept at once with the knights' names. Alone and on the
    // host, the run went deeper than the record it started with: in the
    // dungeon the banner goes up, once, on every screen; at the run's end
    // (atEnd) the fallen screen says so without it
    function _keepRecord(atEnd) {
        if (screen !== "game" && !atEnd) return
        if (depth > ownRecord.depth) {
            ownRecord = {depth: depth, names: _partyNames(), date: _today()}
            records.set("record", JSON.stringify(ownRecord))
            records.set("bestDepth", String(depth))
            if (session.connected && session.isHost) session.publishRecord(ownRecord)
        }
        if (session.connected && !session.isHost) return
        if (recordPassed || depth <= runStartRecord) return
        recordPassed = true
        console.log("[Game] New record: depth", depth)
        if (session.connected) session.announceRecord(!atEnd)
        if (!atEnd) _raiseRecordBanner()
    }
    onDepthChanged: _keepRecord(false)
    // Joiner: the host's party went deeper than the host's record
    function _hostRecordBroken(banner) {
        if (recordPassed) return
        recordPassed = true
        if (banner && screen === "game") _raiseRecordBanner()
    }
    function _raiseRecordBanner() {
        recordBannerShow.restart()
        recordChime.step = 0
        recordChime.restart()
        recordBanner(depth)
    }
    // A run is over: the first of this session's runs on the fallen screen
    function _countRun() {
        ownRuns = [{depth: depth, seconds: Math.round(runSeconds * 10) / 10}].concat(ownRuns)
        if (session.connected && session.isHost) session.publishRuns(ownRuns)
    }
    function _loadRecord() {
        let r = null
        try { r = JSON.parse(records.get("record", "null")) } catch (err) { r = null }
        if (!r || typeof r.depth !== "number")
            r = {depth: parseInt(records.get("bestDepth", "-1")), names: [], date: ""}
        if (isNaN(r.depth)) r.depth = -1
        ownRecord = {depth: r.depth, names: Array.isArray(r.names) ? r.names : [],
                     date: r.date ? String(r.date) : ""}
        playerName = records.get("playerName", "Knight")
    }
    onPlayerNameChanged: records.set("playerName", playerName)
    // A session hosted, joined or left starts its own list of runs; the
    // host's record is the party's from the start
    Connections {
        target: session
        function onConnectedChanged() {
            world.ownRuns = []
            // Later: a host can set no session property before its
            // connectedChanged is over
            if (session.connected) Qt.callLater(() => {
                if (session.connected && session.isHost) session.publishRecord(world.ownRecord)
            })
        }
    }

    // Collision categories
    readonly property int catWall: Box.Category1
    readonly property int catPlayer: Box.Category2
    readonly property int catEnemy: Box.Category3
    readonly property int catProjectile: Box.Category4
    // The breakables: they stop the knights and the enemies, not the shots
    readonly property int catProp: Box.Category5

    Component.onCompleted: {
        console.log("[Game] Component.onCompleted - width:", width, "height:", height)
        _loadRecord()
        _loadVolumes()
        _loadMaster()
        runStartRecord = ownRecord.depth
        console.log("[Game] Record so far:", recordLine === "" ? "none" : recordLine)
        forceActiveFocus()
    }

    // Wait for valid size + game screen before generating dungeon
    onWidthChanged: _tryStartGame()
    onScreenChanged: {
        if (screen !== "title") titleMessage = ""
        _tryStartGame()
    }
    function _tryStartGame() {
        if (screen === "game" && width > 0 && height > 0 && !player && !masterOpen) {
            console.log("[Game] Starting game - width:", width, "height:", height)
            console.log("[Game] pixelPerUnit:", pixelPerUnit)
            if (!session.connected) _setKnights(knightsNow())
            // A node that joins a session late may start in a village
            if (levelType === "village") {
                generateVillage()
                return
            }
            let go = () => {
                dungeonAmbience.start()
                dungeonMusic.start()
                generateDungeon()
            }
            // Alone the dungeon master sets the first dungeon here, in a
            // session the host did before the start
            if (session.connected || !_masterAsks()) {
                go()
                return
            }
            if (masterSeed < 0)
                masterSeed = Math.floor(Math.random() * 2147483647)
            openMaster({ index: levelIndex, pos: dangerPosition, knights: partyKnights, seed: masterSeed,
                         go: (m, pos) => {
                             master = m
                             _setDanger(pos, pos)
                             go()
                         } })
        }
    }

    function _startMultiplayerGame() {
        if (masterOpen) return
        if (masterSeed < 0)
            masterSeed = Math.floor(Math.random() * 2147483647)
        let knights = knightsNow()
        let go = (m, pos) => session.start(masterSeed, pos, knights, m)
        if (!_masterAsks()) go(null, dangerPosition)
        else openMaster({ index: 0, pos: dangerPosition, knights: knights, seed: masterSeed, go: go })
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
            // The left button swings on release, or charges while held
            if (mouse.button === Qt.LeftButton) player.pressSwing(mouse)
            if (mouse.button === Qt.RightButton) player.raiseShield()
        }

        onReleased: (mouse) => {
            if (!player) return
            if (mouse.button === Qt.LeftButton) player.releaseSwing(mouse)
            if (mouse.button === Qt.RightButton) player.lowerShield()
        }
        onCanceled: if (player) {
            player.dropSwing()
            player.lowerShield()
        }
    }

    // Player center in screen coords (for aiming) - map from player's parent to mouseInput coords
    property var playerScreenPos: player ? player.parent.mapToItem(mouseInput, player.x + player.width * 0.5, player.y + player.height * 0.5) : Qt.point(width/2, height/2)
    property real playerScreenX: playerScreenPos.x
    property real playerScreenY: playerScreenPos.y


    // Input handling
    Keys.onPressed: (event) => {
        // Esc closes an open dialogue or the knight panel; only without
        // either it opens the menu
        if (event.key === Qt.Key_Escape) {
            if (talking) dialoguePanel.close()
            else if (knightPanelOpen) knightPanelOpen = false
            else if (screen === "game" && player && !fallen) openMenu()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_M) {
            muted = !muted
            event.accepted = true
            return
        }
        // Q: the whirlwind, with full momentum
        if (event.key === Qt.Key_Q) {
            if (!event.isAutoRepeat && screen === "game" && player && !fallen && !talking) player.unleash()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_C) {
            if (screen === "game" && player && !fallen) knightPanelOpen = !knightPanelOpen
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_V) {
            fx = !fx
            event.accepted = true
            return
        }
        // 1 to 4 buy what the dialogue panel offers; without wares 1
        // drinks a potion and 2 a mana draught
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
            let i = event.key - Qt.Key_1
            if (dialoguePanel.visible && dialoguePanel.wares.length > 0) {
                if (i < dialoguePanel.wares.length) buyWare(dialoguePanel.wares[i])
                event.accepted = true
            } else if (event.key === Qt.Key_1) {
                drinkPotion()
                event.accepted = true
            } else if (event.key === Qt.Key_2) {
                drinkDraught()
                event.accepted = true
            }
            return
        }
        if (event.key === Qt.Key_E) {
            if (dialoguePanel.visible) {
                dialoguePanel.advance()
            } else if (player) {
                // Find nearby NPC to interact with, else a door
                let items = world.room.children
                let talked = false
                for (let i = 0; i < items.length; i++) {
                    let npc = items[i]
                    if ((npc.objectName === "npc" || npc.objectName === "traveller") && npc.nearbyPlayer) {
                        npc.interact()
                        talked = true
                        break
                    }
                }
                if (!talked && !fallen)
                    useDoor(nearestDoor(player.xWu + player.widthWu / 2, player.yWu - player.heightWu / 2,
                                        Balance.dungeon.doorReach))
            }
            event.accepted = true
            return
        }
    }
    Keys.forwardTo: gameCtrl
    function openMenu() {
        // The menu takes the keys, and the keyboard gamepad lets go of what
        // is held when the focus moves (clayground#413); the shield and the
        // swing are the mouse's, whose release the menu would swallow
        if (player) {
            player.lowerShield()
            player.dropSwing()
        }
        menuOpen = true
    }
    function closeMenu() {
        menuOpen = false
    }
    // Where the keys or the touch pad steer the knight, -1..1 on each axis;
    // every level binds its knight to these. While a dialogue is open the
    // knight stands, so it cannot walk off and leave the panel up, and a
    // key still held moves it again once the panel closes
    readonly property bool talking: dialoguePanel.visible
    readonly property real knightMoveX: talking ? 0 : gameCtrl.axisX
    readonly property real knightMoveY: talking ? 0 : -gameCtrl.axisY
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

        onButtonBPressedChanged: {
            if (buttonBPressed && player && !world.talking) {
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

        // The HP the last hit took: a pale chunk past the fill that drains
        // away; only the hurt knight's own screen has it
        Rectangle {
            id: hpChunk
            objectName: "hpChunk"
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 2
            // The HP the chunk reaches to, never below the knight's. It
            // drains on the physics steps from `from` to the knight's HP
            // over Balance.hurt.chunkDrain seconds, easing in: a pause or
            // the hit stop of the blow holds it
            property real hp: 0
            property real from: 0
            property real age: 0
            function reset() {
                hp = player ? player.hp : 0
                from = hp
                age = Balance.hurt.chunkDrain
            }
            width: player ? (parent.width - 4) * Math.max(0, Math.min(hp, player.maxHp)) / player.maxHp : 0
            radius: 2
            color: "#F4E4D4"
            opacity: 0.85
            Connections {
                target: player
                function onHpChanged() {
                    if (player.hp < hpChunk.hp) {
                        hpChunk.from = hpChunk.hp
                        hpChunk.age = 0
                    } else {
                        hpChunk.reset()
                    }
                }
            }
            Connections {
                target: world.physics
                function onStepped() {
                    let d = Balance.hurt.chunkDrain
                    if (!player || hpChunk.age >= d) return
                    hpChunk.age = Math.min(d, hpChunk.age + world.physics.timeStep)
                    let k = hpChunk.age / d
                    hpChunk.hp = hpChunk.from + (player.hp - hpChunk.from) * k * k
                }
            }
        }
        // A new knight (a level, a run) starts without a chunk, also once
        // it is given the HP it carries from the level before
        Connections {
            target: world
            function onPlayerChanged() { Qt.callLater(hpChunk.reset) }
        }

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

        // The shield ran dry or a right-click found no mana: the bar
        // flashes red
        Rectangle {
            id: manaFlash
            objectName: "manaFlash"
            anchors.fill: parent
            radius: parent.radius
            color: Balance.shieldBreak.barColor
            // Seconds since the flash began, on the physics steps: on for
            // the first half of each of its barFlashes
            property real age: Balance.shieldBreak.barFlashes * Balance.shieldBreak.barFlash
            readonly property bool running: age < Balance.shieldBreak.barFlashes * Balance.shieldBreak.barFlash
            opacity: running && (age % Balance.shieldBreak.barFlash) < Balance.shieldBreak.barFlash / 2 ? 0.85 : 0
            Connections {
                target: world.physics
                function onStepped() {
                    if (manaFlash.running) manaFlash.age += world.physics.timeStep
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: player ? Math.ceil(player.mana) + " / " + player.maxMana : ""
            color: "white"
            font.pixelSize: 10
            font.bold: true
        }
    }

    // Momentum (Balance.momentum): a pip for each one earned, right of the
    // mana bar; full, they glow and Q is named. Q short of them flashes
    // them for momentum.flash seconds
    Row {
        id: momentumHud
        objectName: "momentumHud"
        anchors.left: manaHud.right
        anchors.leftMargin: 8
        anchors.verticalCenter: manaHud.verticalCenter
        spacing: 4
        z: 1000
        visible: player !== null
        readonly property int have: player ? player.momentum : 0
        readonly property bool full: have >= Balance.momentum.max
        property bool flashing: false
        Timer {
            id: momentumFlash
            interval: Balance.momentum.flash * 1000
            onTriggered: momentumHud.flashing = false
        }
        Connections {
            target: player
            function onMomentumShort() {
                momentumHud.flashing = true
                momentumFlash.restart()
            }
        }
        Repeater {
            model: Balance.momentum.max
            Rectangle {
                required property int index
                width: 10; height: 10
                rotation: 45
                color: index >= momentumHud.have ? "#2A2A2A"
                    : momentumHud.full ? Qt.lighter(Balance.momentum.color, 1.15 + 0.15 * Math.sin(world._momentumT * 8))
                    : Balance.momentum.color
                border.color: momentumHud.flashing ? Balance.shieldBreak.barColor
                    : index < momentumHud.have ? "#FFF2C0" : "#666666"
                border.width: momentumHud.flashing ? 2 : 1
            }
        }
        Text {
            visible: momentumHud.full
            text: "Q"
            color: Balance.momentum.color
            style: Text.Outline
            styleColor: "#000000"
            font.pixelSize: 12
            font.bold: true
        }
    }
    property real _momentumT: 0
    NumberAnimation on _momentumT {
        running: momentumHud.full
        from: 0; to: 1000; duration: 1000000
        loops: Animation.Infinite
    }

    // The mana bar's red flash, on this screen only
    function flashManaBar() { manaFlash.age = 0 }
    readonly property bool manaBarFlashing: manaFlash.running

    // The knight's gold, under the bars
    Text {
        id: hudGold
        objectName: "hudGold"
        anchors.top: manaHud.bottom
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.topMargin: 6
        z: 1000
        visible: player !== null
        text: "Gold " + (player ? player.gold : 0)
        color: "#E8B83A"
        style: Text.Outline
        styleColor: "#000000"
        font.pixelSize: 14
        font.bold: true
        font.letterSpacing: 1
    }

    // The knight's potions, and the key that drinks one
    Text {
        objectName: "hudPotions"
        anchors.top: hudGold.bottom
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.topMargin: 2
        z: 1000
        visible: player !== null && player.potions > 0
        text: "Potions " + (player ? player.potions : 0) + "  [1]"
        color: "#66CC66"
        style: Text.Outline
        styleColor: "#000000"
        font.pixelSize: 14
        font.bold: true
        font.letterSpacing: 1
    }

    // The knight's mana draughts, and the key that drinks one; under the
    // potions, or in their place when it has none
    Text {
        objectName: "hudDraughts"
        anchors.top: hudGold.bottom
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.topMargin: player && player.potions > 0 ? 20 : 2
        z: 1000
        visible: player !== null && player.draughts > 0
        text: "Draughts " + (player ? player.draughts : 0) + "  [2]"
        color: "#B080E0"
        style: Text.Outline
        styleColor: "#000000"
        font.pixelSize: 14
        font.bold: true
        font.letterSpacing: 1
    }

    // The controls, for a first-time player: shown at depth 0 on a keyboard
    // and mouse, out of the way of the dialogue panel and the fallen screen
    readonly property bool touchControls: Qt.platform.os === "ios" || Qt.platform.os === "android"
    Text {
        id: controlsHint
        objectName: "controlsHint"
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 12
        z: 1000
        visible: player !== null && depth === 0 && !touchControls && !fallen && !menuOpen
                 && !dialoguePanel.visible
        text: "WASD move  •  LMB strike, hold to charge  •  RMB shield  •  Space dash  •  "
              + "Q whirlwind  •  E talk  •  1 potion  •  2 draught  •  C knight  •  M mute  •  Esc menu"
        color: "#BBBBBB"
        opacity: 0.85
        style: Text.Outline
        styleColor: "#000000"
        font.pixelSize: 13
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
        id: muteIcon
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

    // How deep the knight is, under the minimap; large at the camp
    DepthGauge {
        id: depthGauge
        objectName: "depthGauge"
        anchors.top: muteIcon.bottom
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.rightMargin: 10
        z: 1000
        visible: player !== null
        depth: world.depth
        camp: levelType === "village" && !fightRoomActive
        record: world.record.depth
    }

    // The party went deeper than the record: a short banner over the
    // dungeon on every screen, and a chime (Balance.record)
    Text {
        id: recordBannerText
        objectName: "recordBanner"
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.22
        z: 1000
        visible: opacity > 0
        opacity: 0
        text: "New record"
        color: "#E8C35A"
        style: Text.Outline
        styleColor: "#000000"
        font.pixelSize: 40
        font.bold: true
        font.letterSpacing: 3

        Text {
            anchors.top: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Depth " + world.depth
            color: "#DDDDDD"
            style: Text.Outline
            styleColor: "#000000"
            font.pixelSize: 18
            font.bold: true
        }
    }
    SequentialAnimation {
        id: recordBannerShow
        NumberAnimation { target: recordBannerText; property: "opacity"; to: 1; duration: Balance.record.fade * 1000 }
        PauseAnimation { duration: Math.max(0, Balance.record.banner - 2 * Balance.record.fade) * 1000 }
        NumberAnimation { target: recordBannerText; property: "opacity"; to: 0; duration: Balance.record.fade * 1000 }
    }
    Sound {
        id: recordChimeSound
        source: "assets/menu_confirm.wav"
        volume: muted ? 0 : Balance.record.volume * soundVolume
    }
    Timer {
        id: recordChime
        property int step: 0
        interval: Balance.record.step * 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            recordChimeSound.triggerNote(recordChimeSound.rootNote + Balance.record.chime[step], 1)
            if (++step >= Balance.record.chime.length) stop()
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
        function onActed(action) {
            session.sendAction(action)
            // A hit on a knight lifting an ally up starts the lift over
            if (action === "hurt") player.reviveProgress = 0
        }
    }

    Connections {
        target: player
        function onHpChanged() { if (player.hp <= 0) _fall() }
    }

    function _fall() {
        if (fallen || screen !== "game") return
        console.log("[Game] The knight has fallen at depth", depth)
        menuOpen = false
        knightPanelOpen = false
        fallen = true
        _keepRecord(true)
        if (!session.connected) _countRun()
        countFight("fall")
        if (!session.connected) nextPosition = _dangerAfterFall()
        // In a session the enemies go for the knights still standing
        if (session.connected) {
            _checkPartyDown()
            return
        }
        for (let e of enemies) {
            try { if (e && e.halt) e.halt() } catch(err) {}
        }
    }

    // Host: when its own knight and every other knight of the session are
    // down, the run ends for everyone and each screen shows its summary
    function _checkPartyDown() {
        if (!session.connected || !session.isHost || screen !== "game" || !player || !player.fallen)
            return
        for (let id in session.remotePlayers) {
            let rp = session.remotePlayers[id]
            if (rp && rp.remoteHp > 0) return
        }
        console.log("[Game] Every knight is down at depth", depth, "- the run ends")
        session.endRun()
    }

    // The host ended the run: the enemies stop and the fallen screen shows
    // how far the party got; the session stays for the next run
    function _endPartyRun() {
        if (screen !== "game" || partyFallen) return
        console.log("[Game] The party has fallen at depth", depth)
        for (let e of enemies) {
            try { if (e && e.halt) e.halt() } catch(err) {}
        }
        _keepRecord(true)
        if (session.isHost) _countRun()
        nextPosition = _dangerAfterFall()
        partyFallen = true
        fallen = true
    }

    // --- Lifting a fallen knight up (issue #100) ---
    // In a session a knight standing within Balance.party.reviveRange of a
    // fallen ally lifts it up: after reviveTime seconds on the physics
    // clock its node raises it with reviveHp of its max HP. A hit on the
    // lifting knight, a step out of range or a nearer fallen ally starts it
    // over. Each node counts its own knight's lift and sends it with its
    // state, so every screen draws the ring around the fallen knight.
    // Alone there is nobody to lift, except the dojo's fakeDownedAlly()
    function _stepRevive() {
        if (!player) return
        let target = player.fallen || partyFallen ? null : _fallenAllyNear()
        let id = target ? target.nodeId : ""
        if (id !== player.reviveTarget) {
            player.reviveTarget = id
            player.reviveProgress = 0
        }
        if (target) {
            let before = player.reviveProgress
            player.reviveProgress = Math.min(1, before + world.physics.timeStep / Balance.party.reviveTime)
            // Full, the ring stays full until the ally's state says it rose
            if (before < 1 && player.reviveProgress >= 1) {
                console.log("[Game] Lifted up the knight of", id)
                session.liftKnight(id)
                countFight("lift")
            }
        }
        player.reviveRing = player.fallen ? session.liftOf(session.nodeId) : 0
        for (let rid in session.remotePlayers) {
            let rp = session.remotePlayers[rid]
            if (!rp) continue
            let own = player.reviveTarget === rid ? player.reviveProgress : 0
            rp.reviveRing = rp.remoteHp <= 0 ? Math.max(own, session.liftOf(rid)) : 0
        }
    }
    // The nearest fallen knight of another node within reviveRange, or null
    function _fallenAllyNear() {
        let r = Balance.party.reviveRange
        let best = null, bestD = r * r
        for (let id in session.remotePlayers) {
            let rp = session.remotePlayers[id]
            if (!rp || !rp.known || rp.remoteHp > 0) continue
            let dx = rp.xWu - player.xWu, dy = rp.yWu - player.yWu
            let d = dx * dx + dy * dy
            if (d <= bestD) { bestD = d; best = rp }
        }
        return best
    }
    // This node's fallen knight rises with Balance.party.reviveHp of its
    // max HP: an ally lifted it up ("lift"), or the party reached the camp
    // ("camp"). Once the party has fallen nobody rises
    function _rise(how) {
        if (!player || !player.fallen || partyFallen || screen !== "game") return
        player.hp = Math.max(1, Math.round(Balance.party.reviveHp * player.maxHp))
        fallen = false
        if (how === "lift") countFight("lifted")
        console.log("[Game] The knight rises (" + how + ") with HP", player.hp)
    }
    // The dojo, alone: a fallen ally beside the knight to try the lift on,
    // eval fakeDownedAlly(); it is gone with the level
    function fakeDownedAlly() {
        if (!player) return null
        return session.fakeDownedAlly(player.xWu + 1, player.yWu)
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
        property int perfectBlocks: 0
        // Crushing blows that broke the held shield
        property int crushed: 0
        // Whirlwinds that hit an enemy, and the enemies they hit
        property int whirlwinds: 0
        property int whirlHits: 0
        property int kills: 0
        property int deaths: 0
        // Fallen allies this knight lifted up, and the times an ally lifted
        // it up (a rise at camp is neither)
        property int lifts: 0
        property int lifted: 0
        property real seconds: 0
        property real clearSeconds: -1
    }
    function resetFightRecord() {
        let r = fightRecord
        r.damageDealt = 0; r.damageTaken = 0; r.parries = 0; r.blocks = 0
        r.perfectBlocks = 0; r.crushed = 0; r.whirlwinds = 0; r.whirlHits = 0
        r.kills = 0; r.deaths = 0; r.lifts = 0; r.lifted = 0
        r.seconds = 0; r.clearSeconds = -1
    }
    // what: dealt, taken (with the damage), parry, block, perfectBlock
    // (counted as a block too), crushed (a crushing blow broke the held
    // shield), whirlwind (a whirlwind hit its first enemy), whirlHit (an
    // enemy it hit), kill, fall, lift (this knight lifted an ally up) or
    // lifted (an ally lifted it up)
    function countFight(what, amount) {
        let r = fightRecord
        switch (what) {
        case "dealt": r.damageDealt += amount; break
        case "taken": r.damageTaken += amount; break
        case "parry": r.parries++; break
        case "block": r.blocks++; break
        case "perfectBlock": r.perfectBlocks++; break
        case "crushed": r.crushed++; break
        case "whirlwind": r.whirlwinds++; break
        case "whirlHit": r.whirlHits++; break
        case "fall": r.deaths++; break
        case "lift": r.lifts++; break
        case "lifted": r.lifted++; break
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
            world._pickUpGold()
            world._stepRevive()
            world._stepPlates()
            world._stepSlits()
            world._stepDoors()
            world._stepSecrets()
            world._forecastDanger()
            if (world.player && !world.fallen) {
                world.fightRecord.seconds += world.physics.timeStep
                world.runSeconds += world.physics.timeStep
            }
        }
    }

    // In a dungeon, a few times a second, where the next one would stand
    // were the party to leave now: the exit stairs show it. Once the run
    // has ended nextPosition is the next run's
    function _forecastDanger() {
        if (levelType !== "dungeon" || fightRoomActive || !player || _physicsSteps % 10 !== 0) return
        if (session.connected ? partyFallen : fallen) return
        nextPosition = settleDanger(dangerPosition, partyRecords())
    }

    // Enter on the fallen screen: a new run from depth 0 on a new seed. In
    // a session only the host starts it, for every knight
    function newRun() {
        if (session.connected && !session.isHost) return
        if (masterOpen) return
        let seed
        do {
            seed = Math.floor(Math.random() * 2147483647)
        } while (seed === masterSeed)
        let knights = knightsNow()
        let go = (m, pos) => _startRun(seed, pos, knights, m)
        if (!_masterAsks()) go(null, nextPosition)
        else openMaster({ index: 0, pos: nextPosition, knights: knights, seed: seed, go: go })
    }
    // The next run on seed, from depth 0 with a fresh knight, its first
    // dungeon at position in its range and built with the overrides m
    // (null for the game's own). The host clears its enemies on every
    // node before it tells the others the seed and spawns the next run's;
    // its first dungeon is built for knights
    function _startRun(seed, position, knights, m) {
        console.log("[Game] New run, seed:", seed)
        clearDungeon()
        masterSeed = seed
        master = m || null
        _setDanger(position, position)
        _setKnights(knights)
        if (session.connected && session.isHost) session.goAgain(seed, dangerPosition, partyKnights, master)
        menuOpen = false
        knightPanelOpen = false
        fallen = false
        partyFallen = false
        resetting = false
        fightRoomActive = false
        levelIndex = 0
        levelType = "dungeon"
        _startRunRecord()
        generateDungeon()
        minimap.requestPaint()
    }

    // Esc on the fallen screen: leave the run (and a session) for the title,
    // where the next start rolls a new seed
    function backToTitle() {
        console.log("[Game] Back to the title")
        // The next game from the title starts where this run left the
        // danger: after a fall or out of a village at the next position
        let position = fallen || levelType === "village" ? nextPosition : dangerPosition
        clearDungeon()
        if (session.connected) session.leave()
        _setDanger(position, position)
        menuOpen = false
        knightPanelOpen = false
        fallen = false
        partyFallen = false
        resetting = false
        fightRoomActive = false
        masterSeed = -1
        master = null
        masterAsk = null
        masterPreview = null
        levelIndex = 0
        levelType = "dungeon"
        _startRunRecord()
        dungeonAmbience.halt()
        dungeonMusic.halt()
        villageAmbience.halt()
        villageMusic.halt()
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
    // ambient is how much of an unlit spot still shows: in the dungeon next
    // to nothing, so what lies beyond the lantern and the torches stays
    // unseen but for the enemies' glowing eyes; a moonlit dusk in the village.
    LightLayer2d {
        id: lighting
        world: world
        active: world.fx && screen === "game"
        ambient: fightRoomActive ? "#1a1824" : levelType === "village" ? campLook.grade.ambient : look.ambient
        // Little additive glow: it washes colours towards white-grey; the
        // light should reveal the shapes' own colours, not tint them
        glow: 0.1
        falloff: 1.6
        shadowHardness: 2.5
    }

    ScreenFx2d {
        id: screenFxItem
        world: world
        vignette: world.fx ? (campStyled ? campLook.grade.vignette : 0.55) : 0
        vignetteColor: "#000000"
        // Danger rooms run warm, the camps as their look (README: Atmosphere Toolkit)
        temperature: !world.fx ? 0 : campStyled ? campLook.grade.temperature
                     : dangerLook ? look.temperature : 0.12
        // A touch more colour than flat: darkness already mutes everything
        // outside the light, the lit shapes should stay vivid
        saturation: !world.fx ? 1 : campStyled ? campLook.grade.saturation : 1.15
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
        function perfectBlock() {
            let b = Balance.perfectBlock
            screenFxItem.flash(b.flashColor, b.screenFlash * 1000, b.screenFlashOpacity)
            screenFxItem.pulse(b.pulse, b.pulseTime * 1000)
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
        objectName: "minimap"
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
                    var shown = mapCell(gx, gy)
                    if (shown !== "") {
                        ctx.fillStyle = shown === "rock" ? "#333" : "#666"
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

            // The other knights of a session, in their colours, wherever
            // they are - explored or not. Enemies are not shown: the map
            // tells where you have been, not what waits there
            var others = session.remotePlayers || {}
            for (var id in others) {
                var rp = others[id]
                if (!rp) continue
                ctx.fillStyle = String(rp.playerColor)
                ctx.beginPath()
                ctx.arc(rp.xWu / cellSize * scale, (gridHeight - rp.yWu / cellSize) * scale, 3, 0, Math.PI * 2)
                ctx.fill()
            }
        }
        // Own moves repaint it (revealAroundPlayer); the others' moves this
        Timer {
            interval: 250
            repeat: true
            running: session.connected && screen === "game"
            onTriggered: minimap.requestPaint()
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
    // The host settles the next danger from every knight's record and
    // sends it with the level
    function _hostAdvanceLevel() {
        if (resetting || masterOpen) return
        let next = levelIndex + 1
        let d = _dangerFor(next)
        let go = (m, pos) => {
            let dd = m || pos !== d.pos ? { pos: pos, next: pos, knights: d.knights, master: m } : d
            session.announceLevel(next, dd.pos, dd.next, dd.knights, m)
            _applyLevelChange(next, dd)
        }
        if (levelTypeOf(next) !== "dungeon" || !_masterAsks()) go(null, d.pos)
        else openMaster({ index: next, pos: d.pos, knights: d.knights, seed: masterSeed, go: go })
    }

    // d: the danger's positions the level is entered at and the knights it
    // is built for ({pos, next, knights})
    function _applyLevelChange(newIndex, d) {
        if (resetting || newIndex === levelIndex) return
        resetting = true
        Qt.callLater(() => {
            _enterLevel(newIndex, d)
            resetting = false
        })
    }

    // The one way to the next level: what the knight carries (its HP, mana,
    // gold, potions, draughts and the smith's upgrades) goes with it, a village follows each dungeon.
    // In a session a knight down rises at the village's camp. d is the
    // danger's positions it is entered at and the knights it is built
    // for, the host's in a session; alone they are settled here, before
    // the knight and its record are gone. d.master is the dungeon's
    // overrides, the dungeon master's
    function _enterLevel(newIndex, d) {
        d = d || _dangerFor(newIndex)
        let carried = player ? { hp: player.hp, mana: player.mana, gold: player.gold,
                                 potions: player.potions, draughts: player.draughts,
                                 momentum: player.momentum, levels: smithLevels(player) }
                             : { hp: Balance.knight.hp, mana: Balance.knight.mana, gold: 0,
                                 potions: 0, draughts: 0, momentum: 0, levels: smithLevels(null) }
        console.log("[Game] Level", newIndex, "carrying HP:", carried.hp, "mana:", carried.mana,
                    "gold:", carried.gold, "potions:", carried.potions, "draughts:", carried.draughts,
                    "smith:", JSON.stringify(carried.levels))
        clearDungeon()
        levelIndex = newIndex
        levelType = levelTypeOf(newIndex)
        master = levelType === "dungeon" ? d.master || null : null
        _setDanger(d.pos, d.next)
        _setKnights(d.knights)
        if (levelType === "village")
            generateVillage()
        else
            generateDungeon()
        if (player) {
            for (let line of smithLines) player[line + "Level"] = carried.levels[line]
            player.hp = carried.hp
            player.mana = carried.mana
            player.gold = carried.gold
            player.potions = carried.potions
            player.draughts = carried.draughts
            player.momentum = carried.momentum
        }
        // A knight still down when the party reaches the camp rises there
        if (session.connected && levelType === "village") _rise("camp")
    }

    // Component factories
    Component { id: playerComponent; Player {} }
    Component { id: enemyComponent; Enemy {} }
    Component { id: wallComponent; Wall {} }
    Component { id: wallFaceComponent; WallFace {} }
    Component { id: torchComponent; Torch {} }
    Component { id: motesComponent; Motes {} }

    function spawnMotes() {
        // Fireflies and embers glow on their own; dust only shows where
        // light falls. A camp's air is its look's
        if (campStyled) {
            let a = campLook.air
            let col = Qt.color(a.color)
            dungeonObjects.push(motesComponent.createObject(a.glows ? glowParent() : world.room, {
                widthWu: xWuMax, heightWu: yWuMax,
                fireflies: a.blink, density: a.density, moteSize: a.size, drift: a.drift,
                color: Qt.rgba(col.r, col.g, col.b, a.alpha),
                pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
                visible: Qt.binding(() => world.fx)
            }))
            return
        }
        let m = motesComponent.createObject(world.room, {
            widthWu: xWuMax, heightWu: yWuMax,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            visible: Qt.binding(() => world.fx)
        })
        dungeonObjects.push(m)
        if (!dangerLook) return
        // The dungeon's air at its danger: dust, and embers glowing on
        // their own
        m.density = look.dust
        m.visible = Qt.binding(() => world.fx && look.dust > 0)
        if (look.emberAir <= 0) return
        let e = motesComponent.createObject(glowParent(), {
            widthWu: xWuMax, heightWu: yWuMax,
            density: look.emberAir, moteSize: 0.05, drift: 0.8,
            color: Qt.rgba(1.0, 0.33, 0.08, 0.9),
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            visible: Qt.binding(() => world.fx)
        })
        dungeonObjects.push(e)
    }
    Component { id: floorComponent; Floor {} }
    Component { id: campfireComponent; Campfire {} }
    Component { id: projectileComponent; Projectile {} }
    Component { id: npcComponent; Npc {} }
    Component { id: goldDropComponent; GoldDrop {} }

    // Dialogue panel (bottom-center, hidden by default)
    DialoguePanel { id: dialoguePanel; parent: world; gold: player ? player.gold : 0 }

    // The knight panel (C), on the left under the gold and the potions
    KnightPanel {
        parent: world
        anchors.top: hudGold.bottom
        anchors.left: parent.left
        anchors.topMargin: 48
        anchors.leftMargin: 12
        z: 1500
        visible: knightPanelOpen && player !== null && screen === "game" && !fallen && !menuOpen
        knight: player
        game: world
    }

    function openDialogue(name, color, lines, wares) {
        dialoguePanel.open(name, color, lines, _offered(wares || []))
    }
    // The innkeeper's wares are always offered; the smith's are made as he
    // is talked to (smithWare), the next level of each upgrade he may sell
    function _offered(wares) {
        let out = []
        for (let w of wares) {
            let offer = w.id === "potion" || w.id === "draught" ? w : smithWare(w.id)
            if (offer) out.push(offer)
        }
        return out
    }

    // --- The smith's upgrades (issues #38, #81, #98) ---
    // Each lasts the run and has levels (Balance.shop): one level per
    // camp, the next above the knight's, and higher levels only deeper
    readonly property var smithLines: ["sword", "shield", "harness", "blade"]
    // The knight's levels, {sword, shield, harness, blade}; all 0 for none
    function smithLevels(knight) {
        let out = {}
        for (let line of smithLines) out[line] = knight ? knight[line + "Level"] : 0
        return out
    }
    // The highest level the smith of this camp sells: the camp after depth
    // d reaches level L once d is levelDepth[L - 1]
    function smithLimit() {
        return Balance.shop.levelDepth.filter(d => d <= depth).length
    }
    // The ware of the next level of line, or null where the smith sells
    // none: the knight has the last level, the next one is above this
    // camp's limit, or it bought a level here already
    function smithWare(line) {
        if (!player || player.smithDone || smithLines.indexOf(line) < 0) return null
        let level = player[line + "Level"] + 1
        if (level > smithLimit() || level > Balance.shop.upgradePrice.length) return null
        return { id: line, level: level, price: Balance.shop.upgradePrice[level - 1],
                 label: smithName(line, level) + " (" + smithGives(line, level) + ")" }
    }
    // A level's name, "Lighter harness II" ("Lighter harness" for level
    // 0), and what it gives, "a dash costs 4 mana": the smith's offer and
    // the knight panel say the same
    function smithName(line, level) {
        let name = line === "sword" ? "Sharpened sword" : line === "shield" ? "Reinforced shield"
            : line === "harness" ? "Lighter harness" : "Balanced blade"
        return level < 1 ? name : name + " " + (["I", "II", "III", "IV", "V"][level - 1] || String(level))
    }
    function smithGives(line, level) {
        let sh = Balance.shop, i = level - 1
        return line === "sword" ? "+" + sh.swordAtk[i] + " damage"
            : line === "shield" ? "a block lets " + Math.round(sh.shieldBlockedShare[i] * 100)
                                  + " % through, costs " + sh.shieldBlockMana[i] + " mana"
            : line === "harness" ? "a dash costs " + sh.harnessDashMana[i] + " mana"
            : "a whirlwind costs " + sh.bladeWhirlMana[i] + " mana"
    }

    // --- The village's wares (issue #38) ---
    // Bought with this node's knight's own gold. A potion is kept for key 1,
    // a draught for key 2; a smith's level lasts the run
    function buyWare(ware) {
        if (!player || player.fallen) return false
        let inn = ware.id === "potion" || ware.id === "draught"
        // The smith sells only what he offers now: a ware from before the
        // knight bought here, or above the camp's limit, is refused
        let offer = inn ? ware : smithWare(ware.id)
        if (!offer) return false
        if (player.gold < offer.price) {
            dialoguePanel.note = "You'll need " + offer.price + " gold for that."
            return false
        }
        player.gold -= offer.price
        if (ware.id === "potion") {
            player.potions++
            dialoguePanel.note = "One potion. Drink it when it counts."
        } else if (ware.id === "draught") {
            player.draughts++
            dialoguePanel.note = "A mana draught. It'll fill you up when the shield runs dry."
        } else {
            player[ware.id + "Level"] = offer.level
            player.smithDone = true
            dialoguePanel.note = {
                sword: "There. That edge will bite deeper.",
                shield: "There. That shield will let less through.",
                harness: "There. Lighter on your feet now.",
                blade: "There. It'll spin true in your hand."
            }[ware.id]
        }
        dialoguePanel.wares = _offered(dialoguePanel.wares)
        console.log("[Game] Bought", ware.id + (inn ? "" : " level " + offer.level), "for",
                    offer.price, "gold,", player.gold, "left")
        return true
    }
    function drinkPotion() {
        if (!player) return 0
        let healed = player.drinkPotion()
        if (healed > 0) spawnDamageNumber(player.xWu, player.yWu, "+" + healed, "#44CC44")
        return healed
    }
    function drinkDraught() {
        if (!player) return 0
        let gained = player.drinkDraught()
        if (gained > 0) spawnDamageNumber(player.xWu, player.yWu, "+" + Math.round(gained), "#B080E0")
        return gained
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
        let levelSeed = levelSeedNow()
        rng = createRng(levelSeed)
        console.log("[Game] Seed:", masterSeed, "Level:", levelIndex, "LevelSeed:", levelSeed)
        // Nothing lost here yet: were the party to leave at once, the next
        // dungeon would stand there, and the stairs show it from the start
        nextPosition = settleDanger(dangerPosition, [{ lost: 0, fell: false }])
        console.log("[Game] Grid size:", gridWidth, "x", gridHeight, "cells")

        // Steps 1 to 4c: the grid carved and its features, doors and
        // secret rooms laid out (carveDungeon); a secret room's cells stay
        // rock until opened
        initExploredCells()
        let spec = dungeonSpec(dangerPosition, master)
        let plan = carveDungeon(levelSeed, spec.band, featureShowcase, rng, spec)
        let featureList = plan.features
        let doorList = plan.doors
        _takeSecrets(plan.secrets)

        // Step 5: Convert grid to actual game objects
        buildDungeonFromGrid()
        placeRoomTorches(createRng(levelSeed ^ 0x5bd1e995), look)
        placeDebris(createRng(levelSeed ^ 0x2c1b3c6d), look)
        placeFeatures(featureList)
        placeDoors(doorList)
        placeSecrets()

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
        for (let e of rollEnemies(rooms, spec.rolls(danger, partyKnights), rng))
            spawnEnemy(e.x, e.y, e.tier, e.type, partyKnights)

        // Bind player controls
        if (player) {
            player.moveX = Qt.binding(() => knightMoveX)
            player.moveY = Qt.binding(() => knightMoveY)
            // Mouse aiming: bind screen coords for facing calculation
            player.mouseScreenX = Qt.binding(() => mouseInput.mouseX)
            player.mouseScreenY = Qt.binding(() => mouseInput.mouseY)
            player.playerScreenX = Qt.binding(() => playerScreenX)
            player.playerScreenY = Qt.binding(() => playerScreenY)
            gameCamera.target = player
            revealAroundPlayer()  // Initial reveal
        }

        // The secret rooms the host's party opened here already, the
        // things it broke, and the plates it set off, for a node that
        // joins late
        _applySecrets(_sessionSecrets)
        _applyBroken(_sessionBroken)
        _applySprung(_sessionSprung)
        _applyDoors(_sessionDoors)

        // Spawn remote players for multiplayer
        if (rooms.length > 0) {
            let startRoom = rooms[0]
            session.spawnRemotePlayers((startRoom.x + startRoom.w / 2) * cellSize,
                                (startRoom.y + startRoom.h / 2) * cellSize)
        }

        console.log("[Game] generateDungeon() complete")
    }

    // The level seed the level played now is built on: the master's when
    // it set one, else the run's seed's for the level
    function levelSeedNow() {
        return master && master.seed !== undefined ? master.seed : deriveSeed(masterSeed, levelIndex)
    }
    // What a dungeon at position is built from, with the master's
    // overrides m (null for the game's own): its band, its rooms' count
    // range, the feature kinds' table and its spawn rolls at a danger for
    // knights (spawnRolls, with the enemies per room m sets). position
    // left out is the middle of the range
    function dungeonSpec(position, m) {
        let sb = Balance.spawn
        let spec = { band: position === undefined ? 1 : dangerBand(position),
                     roomsMin: sb.roomsMin, roomsMax: sb.roomsMax, kinds: Balance.dungeon.kinds,
                     enemiesPerRoom: undefined }
        spec.rolls = (d, knights) => Object.assign(spawnRolls(d, knights), { perRoom: spec.enemiesPerRoom })
        if (!m) return spec
        if (m.rooms !== undefined) spec.roomsMin = spec.roomsMax = m.rooms
        if (m.enemies !== undefined) spec.enemiesPerRoom = m.enemies
        // A feature row's per room, split between its kinds, at every band
        let kinds = {}
        for (let k in Balance.dungeon.kinds) kinds[k] = Object.assign({}, Balance.dungeon.kinds[k])
        for (let row of Balance.dungeonMaster.settings) {
            if (!row.kinds || m[row.key] === undefined) continue
            let shares = splitShare(m[row.key], row.kinds.map(k => kinds[k].perRoom[spec.band]))
            row.kinds.forEach((k, i) => kinds[k].perRoom = [shares[i], shares[i], shares[i]])
        }
        spec.kinds = kinds
        return spec
    }
    // total split by weights: its whole number in whole shares, the
    // largest remainders first, and its fraction in proportion, so a
    // whole total gives that many to a room
    function splitShare(total, weights) {
        let sum = weights.reduce((a, b) => a + b, 0)
        let w = weights.map(x => sum > 0 ? x / sum : 1 / weights.length)
        let whole = Math.floor(total + 1e-9), frac = Math.max(0, total - whole)
        let out = w.map(x => Math.floor(x * whole))
        let left = whole - out.reduce((a, b) => a + b, 0)
        let order = w.map((x, i) => i).sort((a, b) => (w[b] * whole - out[b]) - (w[a] * whole - out[a]) || w[b] - w[a])
        for (let i = 0; i < left; i++) out[order[i % order.length]]++
        return out.map((n, i) => n + frac * w[i])
    }

    // Steps 1 to 4c of a dungeon, the same for the one built
    // (generateDungeon) and the one the witch reads (secretsOf), on the
    // live grid: the grid filled with walls, the rooms drawn from rand and
    // carved, the chain of corridors, the entrance and the exit, the loops;
    // then its features, doors and secret rooms laid out on it, without
    // touching the world: {features, doors, secrets}
    function carveDungeon(levelSeed, band, showcase, rand, spec) {
        spec = spec || dungeonSpec(undefined, null)
        // Step 1: Initialize grid with walls
        initializeGrid()

        // Step 2: Place rooms
        placeRooms(spec.roomsMin, spec.roomsMax, Balance.spawn.roomSizeMin,
                   Balance.spawn.roomSizeMax, rand)

        // Step 3: Connect rooms with spanning tree
        connectRooms()

        // Step 4: Add entrance (south) and exit (north)
        addEntranceAndExit()

        // Step 4b: Close loops with corridors off the chain
        addLoops(createRng(levelSeed ^ 0x4c6f6f70), Balance.dungeon.extraCorridors[band])

        // Step 4c: Lay out the features, the doors and the secret rooms
        let features = planFeatures(levelSeed, band, showcase, spec.kinds)
        let doors = planDoors(levelSeed, band, showcase)
        return { features: features, doors: doors,
                 secrets: planSecrets(levelSeed, band, showcase, features, doors) }
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

    function placeRooms(minRooms, maxRooms, minSize, maxSize, rand) {
        rooms = planRooms(minRooms, maxRooms, minSize, maxSize, rand || rng)
        // Carve the rooms into the grid
        for (let room of rooms)
            for (let y = room.y; y < room.y + room.h; y++)
                for (let x = room.x; x < room.x + room.w; x++)
                    grid[y][x] = cellRoom
        console.log("[Game] Placed", rooms.length, "rooms")
    }

    // The rooms of a dungeon, drawn from rand without touching the grid,
    // sorted by Y position (bottom to top) for the spanning tree. Only
    // they and rollEnemies draw from the level's rng, so the witch can
    // read the next dungeon's enemies off its seed (foretell)
    function planRooms(minRooms, maxRooms, minSize, maxSize, rand) {
        let out = []
        let numRooms = minRooms + Math.floor(rand() * (maxRooms - minRooms + 1))
        let attempts = 0
        let maxAttempts = 100

        while (out.length < numRooms && attempts < maxAttempts) {
            attempts++

            // Random room size (in cells)
            let rw = minSize + Math.floor(rand() * (maxSize - minSize + 1))
            let rh = minSize + Math.floor(rand() * (maxSize - minSize + 1))

            // Random position (leave 1 cell border for walls)
            let rx = 1 + Math.floor(rand() * (gridWidth - rw - 2))
            let ry = 1 + Math.floor(rand() * (gridHeight - rh - 2))

            // Check if room overlaps with existing rooms (with 1 cell padding)
            let overlaps = false
            for (let room of out) {
                if (rx < room.x + room.w + 1 &&
                    rx + rw + 1 > room.x &&
                    ry < room.y + room.h + 1 &&
                    ry + rh + 1 > room.y) {
                    overlaps = true
                    break
                }
            }
            if (!overlaps) out.push({x: rx, y: ry, w: rw, h: rh})
        }

        out.sort((a, b) => a.y - b.y)
        return out
    }

    // The enemies of a dungeon with these rooms and spawn rolls (spawnRolls,
    // or a dungeonSpec's rolls),
    // drawn from rand: [{x, y, tier, type}] in wu, across the rooms but the
    // first, the knights' start, with the table's tier mix
    function rollEnemies(rms, sb, rand) {
        let out = []
        if (rms.length < 2) return out
        let spawnRooms = rms.slice(1)
        // perRoom, when the rolls have it, sets the count: that many to a
        // room, rounded over all of them; the roll is drawn all the same
        let roll = rand()
        let numEnemies = sb.perRoom !== undefined ? Math.round(sb.perRoom * spawnRooms.length)
                                                  : sb.enemiesMin + Math.floor(roll * (sb.enemiesMax - sb.enemiesMin + 1))
        let tiers = dealTiers(numEnemies, sb, rand)
        for (let i = 0; i < numEnemies; i++) {
            let room = spawnRooms[i % spawnRooms.length]
            let ex = (room.x + 1 + rand() * (room.w - 2)) * cellSize
            let ey = (room.y + 1 + rand() * (room.h - 2)) * cellSize
            let tier = tiers[i]
            // Enemy type: guardian, spitter, else grunt
            let typeRoll = rand()
            let guardianChance = tier === 2 ? sb.guardianChanceTough : sb.guardianChance
            let type = typeRoll < guardianChance ? "guardian"
                : typeRoll < guardianChance + sb.spitterChance ? "spitter" : "grunt"
            out.push({x: ex, y: ey, tier: tier, type: type})
        }
        return out
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

    // The corridors off the chain (addLoops): [{a, b, cells}], a and b the
    // rooms' indices, cells the [gx, gy] it carved out of the rock
    property var loopCorridors: []

    // count more corridors, each between two rooms close but not
    // neighbours in the chain, so the dungeon has loops. rand is their own
    // stream of the level's seed, so the rooms, the enemies and the
    // witch's reading stay as the seed has them. Each pick is one of the
    // dungeon.loopChoice closest pairs left (the gap between the rooms, in
    // cells), carved L-shaped centre to centre as the chain's are, the
    // stream choosing which leg comes first. A corridor is taken only if
    // each of its cells outside its two rooms lies in no third room nor
    // beside one, beside its own two only where it steps into them, not on
    // or beside the entrance's or the exit's shaft, and it carves at least
    // one new cell; else its other leg is tried, then the next pair. Fewer
    // than count only when no pair is left
    function addLoops(rand, count) {
        loopCorridors = []
        let n = rooms.length
        let inRoom = (r, gx, gy) => gx >= r.x && gx < r.x + r.w && gy >= r.y && gy < r.y + r.h
        let centre = r => [Math.floor(r.x + r.w / 2), Math.floor(r.y + r.h / 2)]
        let start = rooms[0], end = rooms[n - 1]
        let shaft = (gx, gy) => (Math.abs(gx - entranceGridX) <= 1 && gy < start.y)
                                || (Math.abs(gx - exitGridX) <= 1 && gy >= end.y + end.h)
        let pairs = []
        for (let i = 0; i < n; i++)
            for (let j = i + 2; j < n; j++) {
                let a = rooms[i], b = rooms[j]
                let gap = Math.max(0, b.x - (a.x + a.w), a.x - (b.x + b.w))
                        + Math.max(0, b.y - (a.y + a.h), a.y - (b.y + b.h))
                pairs.push({ a: i, b: j, gap: gap })
            }
        pairs.sort((p, q) => p.gap - q.gap || p.a - q.a || p.b - q.b)

        let beside = (r, c) => {
            let inX = c[0] >= r.x && c[0] < r.x + r.w, inY = c[1] >= r.y && c[1] < r.y + r.h
            let nearX = c[0] >= r.x - 1 && c[0] <= r.x + r.w, nearY = c[1] >= r.y - 1 && c[1] <= r.y + r.h
            return nearX && nearY && (inX || inY)
        }
        let clear = (path, p) => {
            let fresh = 0
            for (let i = 0; i < path.length; i++) {
                let c = path[i]
                if (inRoom(rooms[p.a], c[0], c[1]) || inRoom(rooms[p.b], c[0], c[1])) continue
                if (shaft(c[0], c[1])) return -1
                for (let k = 0; k < n; k++) {
                    if (!beside(rooms[k], c)) continue
                    // Its own two rooms only where it steps in or out,
                    // never along their walls
                    let step = (k === p.a || k === p.b)
                        && [path[i - 1], path[i + 1]].some(q => q && inRoom(rooms[k], q[0], q[1]))
                    if (!step) return -1
                }
                if (grid[c[1]][c[0]] === cellWall) fresh++
            }
            return fresh
        }

        while (loopCorridors.length < count && pairs.length > 0) {
            let pick = Math.floor(rand() * Math.min(Balance.dungeon.loopChoice, pairs.length))
            let p = pairs.splice(pick, 1)[0]
            let ca = centre(rooms[p.a]), cb = centre(rooms[p.b])
            let flip = rand() < 0.5
            for (let first of [flip, !flip]) {
                let path = lPath(ca[0], ca[1], cb[0], cb[1], first)
                if (clear(path, p) <= 0) continue
                let cells = path.filter(c => grid[c[1]][c[0]] === cellWall)
                for (let c of cells) grid[c[1]][c[0]] = cellHallway
                loopCorridors.push({ a: p.a, b: p.b, cells: cells })
                break
            }
        }
        console.log("[Game] Closed", loopCorridors.length, "loops of", count)
    }

    // The cells of an L from (x1, y1) to (x2, y2), both ends in: along x
    // first when acrossFirst, else along y first
    function lPath(x1, y1, x2, y2, acrossFirst) {
        let out = []
        let mx = acrossFirst ? x2 : x1, my = acrossFirst ? y1 : y2
        let walk = (fx, fy, tx, ty) => {
            let dx = Math.sign(tx - fx), dy = Math.sign(ty - fy)
            for (let x = fx, y = fy; ; x += dx, y += dy) {
                out.push([x, y])
                if (x === tx && y === ty) break
            }
        }
        walk(x1, y1, mx, my)
        out.pop()
        walk(mx, my, x2, y2)
        return out
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
        if (dangerLook) {
            floorObj.crackShare = look.crackShare
            floorObj.moss = look.moss
        }
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
                    // Found start of wall run, find its length; a secret
                    // room's cells run apart, so opening it takes them away
                    let startX = gx, secret = _secretOf(gx, gy)
                    while (gx < gridWidth && grid[gy][gx] === cellWall && _secretOf(gx, gy) === secret) {
                        gx++
                    }
                    let runLength = gx - startX

                    // Create single wall for entire run
                    let wx = startX * cellSize
                    let wy = gy * cellSize
                    let ww = runLength * cellSize
                    _keepSecretBuilt(secret, createWallAt(wx, wy + cellSize, ww, cellSize))
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
        if (campStyled) wall.color = campLook.rock
        dungeonObjects.push(wall)
        return wall
    }

    // Torches on the north wall of each room. Decoration draws from its own
    // generator so the layout and enemies stay identical to a seed without it.
    // With a look (Balance.danger.looks) only its torchShare of them burn,
    // in its torch colour
    property var torches: []
    function placeRoomTorches(decoRng, look) {
        torches = []
        for (let room of rooms) {
            let gy = room.y + room.h
            if (gy >= gridHeight) continue
            let spots = []
            for (let gx = room.x; gx < room.x + room.w; gx++)
                if (grid[gy][gx] === cellWall && grid[gy - 1][gx] !== cellWall && _secretOf(gx, gy) < 0)
                    spots.push(gx)
            if (spots.length === 0) continue
            let count = room.w >= 7 && spots.length >= 4 ? 2 : 1
            for (let i = 0; i < count; i++) {
                // Spread two torches across the wall, one sits near the middle
                let t = count === 1 ? 0.5 : (i === 0 ? 0.25 : 0.75)
                t += (decoRng() - 0.5) * 0.15
                let gx = spots[Math.max(0, Math.min(spots.length - 1, Math.round(t * (spots.length - 1))))]
                if (look && decoRng() >= look.torchShare) continue
                placeTorch(gx * cellSize + cellSize / 2, gy * cellSize + wallFaceWu * 0.75,
                           look ? look.torch : undefined)
            }
        }
    }

    // What lies on the floor of each room but the first at the look's
    // danger: old stains, bones and embers, each kind look.<kind> per room
    // on average, laid out from the level's seed
    Component { id: debrisComponent; Debris {} }
    function placeDebris(decoRng, look) {
        for (let room of rooms.slice(1)) {
            for (let kind of ["stains", "bones", "embers"]) {
                // A whole number per room, its fraction a chance of one more
                let n = Math.floor(look[kind] + decoRng())
                for (let i = 0; i < n; i++) {
                    let x = (room.x + 1 + decoRng() * (room.w - 2)) * cellSize
                    let y = (room.y + 1 + decoRng() * (room.h - 2)) * cellSize
                    let seed = decoRng()
                    let props = {
                        xWu: x, yWu: y, seed: seed,
                        pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
                        visible: Qt.binding(() => world.fx)
                    }
                    let o = kind === "stains"
                        ? stainComp.createObject(world.room, Object.assign(props, {
                              color: "#2E1A14", sizeWu: 1.0 + 0.6 * seed }))
                        : debrisComponent.createObject(kind === "embers" ? glowParent() : world.room,
                              Object.assign(props, { kind: kind, sizeWu: 0.8 + 0.3 * seed }))
                    if (o) dungeonObjects.push(o)
                    if (o && kind === "bones") bonePiles.push(o)
                }
            }
        }
    }
    // The heaps of bones still lying on the floor: a swing or a whirlwind
    // that reaches one breaks it (Player._breakBones), only on this screen
    property var bonePiles: []
    // A heap breaks: bone splinters thrown along the blow (nx, ny), a dull
    // crack, and it is gone
    function breakBones(pile, nx, ny) {
        let i = bonePiles.indexOf(pile)
        if (i < 0) return
        bonePiles.splice(i, 1)
        spawnShards(pile.xWu, pile.yWu, nx, ny, 9, "#D8D0BC", 0.14)
        spawnShards(pile.xWu, pile.yWu, nx, ny, 3, "#DDD5C2", 0.22)
        impactSound.triggerOneShot(0.35)
        pile.destroy()
    }

    // The dungeon's features (Balance.dungeon): [{kind, gx, gy, xWu, yWu}],
    // a cell and its centre in wu. The dojo's features scenario sets
    // featureShowcase, and each kind is laid out at its showcase count
    // instead of its danger's; a new level is built without it
    property var features: []
    property bool featureShowcase: false

    // Whether a feature may stand on cell (gx, gy) of the carved grid: a
    // room's cell, not in the start room, not beside a corridor, and the
    // table's distance clear of the entrance and the exit
    function featureCellOk(gx, gy) {
        if (grid[gy][gx] !== cellRoom) return false
        let start = rooms[0]
        if (gx >= start.x && gx < start.x + start.w && gy >= start.y && gy < start.y + start.h)
            return false
        for (let n of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            let nx = gx + n[0], ny = gy + n[1]
            if (nx >= 0 && nx < gridWidth && ny >= 0 && ny < gridHeight && grid[ny][nx] === cellHallway)
                return false
        }
        let far = (ex, ey, d) => Math.hypot((gx - ex) * cellSize, (gy - ey) * cellSize) >= d
        return far(entranceGridX, 0, Balance.dungeon.clearOfEntrance)
            && far(exitGridX, gridHeight - 1, Balance.dungeon.clearOfExit)
    }

    // The features of the carved dungeon, at the look's band (dangerBand)
    // or at the showcase counts, without touching the world. Each kind
    // draws from its own stream, the level's seed and the kind's name, and
    // ranks a room's cells by it whatever the other kinds took: it takes
    // the first of them still free (a slit one on the room's edge,
    // _slitAim). So a kind added or retuned moves another only off a cell
    // it takes first. kinds is Balance.dungeon's when left out. The slits
    // get their rhythms last (_rhythmSlits)
    function planFeatures(levelSeed, band, showcase, kinds) {
        kinds = kinds || Balance.dungeon.kinds
        let out = []
        if (rooms.length < 2) return out
        let taken = {}
        for (let kind in kinds) {
            let table = kinds[kind]
            let rand = createRng(levelSeed ^ 0x7a3d9e21 ^ _nameHash(kind))
            let perRoom = showcase ? table.showcase : table.perRoom[band]
            for (let room of rooms.slice(1)) {
                // A whole number per room, its fraction a chance of one more
                let n = Math.floor(perRoom + rand())
                if (n <= 0) continue
                let cells = []
                for (let gy = room.y; gy < room.y + room.h; gy++)
                    for (let gx = room.x; gx < room.x + room.w; gx++)
                        if (featureCellOk(gx, gy)) cells.push([gx, gy])
                // Shuffled (Fisher-Yates) by this kind's stream alone
                for (let i = cells.length - 1; i > 0; i--) {
                    let j = Math.floor(rand() * (i + 1))
                    let c = cells[i]; cells[i] = cells[j]; cells[j] = c
                }
                let picked = []
                for (let c of cells) {
                    if (n <= 0) break
                    if (taken[c[1] * gridWidth + c[0]]) continue
                    let aim = kind === "slit" ? _slitAim(c[0], c[1], room, picked) : {}
                    if (!aim) continue
                    taken[c[1] * gridWidth + c[0]] = true
                    let f = Object.assign({ kind: kind, gx: c[0], gy: c[1],
                                            xWu: (c[0] + 0.5) * cellSize, yWu: (c[1] + 0.5) * cellSize }, aim)
                    out.push(f)
                    picked.push(f)
                    n--
                }
            }
        }
        return _rhythmSlits(out, levelSeed, band)
    }
    function _nameHash(name) {
        let h = 5381
        for (let i = 0; i < name.length; i++) h = (Math.imul(h, 33) ^ name.charCodeAt(i)) | 0
        return h
    }

    function placeFeatures(list) {
        features = list
        breakables = []
        _propCells = ({})
        _buildingCells = ({})
        _brokenCells = []
        plates = []
        _sprungCells = ({})
        slits = []
        _clearArrows()
        let band = dangerBand(dangerPosition)
        for (let f of list) {
            let o = null
            if (Balance.dungeon.loot[f.kind])
                o = _placeBreakable(f, band)
            else if (f.kind === "spike")
                o = _placePlate(f, band)
            else if (f.kind === "slit")
                o = _placeSlit(f, band)
            if (o) dungeonObjects.push(o)
        }
    }

    // --- Breakables (issue #123) ---
    // Urns, crates and crystals stand on their features' cells, the same
    // on every screen, as the seed lays them out. A blow on this screen
    // breaks one at once (Player._breakThings); alone the game rolls its
    // gold, in a session the host does, publishes the cells broken in the
    // level (session property "broken") and every screen breaks them too,
    // a node that joins later as well. The gold is a drop as an enemy's
    Component { id: breakableComponent; Breakable {} }
    Component {
        id: crystalGlowComponent
        Rectangle {
            property real pixelPerUnit: 1
            property real xWu: 0
            property real yWu: 0
            x: xWu * pixelPerUnit - width / 2
            y: (parent ? parent.height : 0) - yWu * pixelPerUnit - height / 2
            width: 1.6 * pixelPerUnit
            height: width
            radius: width / 2
            color: "#307FE6FF"
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { from: 0.6; to: 1; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1; to: 0.6; duration: 1100; easing.type: Easing.InOutSine }
            }
        }
    }
    // The whole ones still standing, and their cells by grid key, which
    // the enemies' paths go around
    property var breakables: []
    // The camp's campfire, null in a dungeon: a knight that stands still
    // in its warmth sits down (Player, issue #148)
    property var campfire: null
    property var _propCells: ({})
    // Host, and alone: the cells broken in this level, "gx,gy"
    property var _brokenCells: []
    function _placeBreakable(f, band) {
        let cell = f.gx + "," + f.gy
        let b = breakableComponent.createObject(world.room, {
            kind: f.kind, cell: cell, cxWu: f.xWu, cyWu: f.yWu, band: band,
            seed: createRng(f.gx * 7349 + f.gy * 3571)(),
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            categories: catProp,
            collidesWith: catPlayer | catEnemy
        })
        if (!b) return null
        if (f.kind === "crystal") {
            b.glow = crystalGlowComponent.createObject(glowParent(), {
                xWu: f.xWu, yWu: f.yWu, pixelPerUnit: Qt.binding(() => world.pixelPerUnit) })
            if (b.glow) dungeonObjects.push(b.glow)
        }
        breakables.push(b)
        _propCells[f.gy * gridWidth + f.gx] = true
        _setPathCell(f.gx, f.gy, false)
        return b
    }
    function breakableAt(cell) {
        return breakables.find(b => b.cell === cell) || null
    }
    // The gold a breakable holds, from the level's seed and its cell
    // alone, whoever breaks it and when: 0 for none
    function breakableGold(kind, cell) {
        let t = (_cacheCells[cell] ? Balance.dungeon.cacheLoot : Balance.dungeon.loot)[kind]
        if (!t) return 0
        let c = cell.split(",").map(Number)
        let rand = createRng(levelSeedNow() ^ 0x3c6ef372 ^ (c[1] * gridWidth + c[0]))
        if (rand() >= t.chance) return 0
        let lo = t.gold[0] + t.perDepth * dangerDepth, hi = t.gold[1] + t.perDepth * dangerDepth
        return lo + Math.floor(rand() * (hi - lo + 1))
    }
    // This node's knight broke b with a blow along (nx, ny)
    function breakThing(b, nx, ny) {
        if (!_wreck(b, nx, ny)) return
        if (session.connected) session.reportBreak(levelIndex, b.cell)
        else _broken(b.kind, b.cell, b.cxWu, b.cyWu)
    }
    // A blow too weak for it: a crystal glances a swing off with sparks
    function glanceThing(b, nx, ny) {
        spawnSparks(b.cxWu, b.cyWu, -nx, -ny, 6, "#BFF4FF")
        impactSound.triggerOneShot(0.25)
    }
    // Alone, or the host: b broke for good, its gold drops where it stood
    // and, in a session, every screen is told
    function _broken(kind, cell, x, y) {
        if (_brokenCells.indexOf(cell) >= 0) return
        _brokenCells.push(cell)
        _spawnGold(x, y, breakableGold(kind, cell))
        if (session.connected)
            session.publishBroken({ seed: session.runSeed, level: levelIndex, cells: _brokenCells.slice() })
    }
    // Host: a node broke the thing on that cell of that level
    function _hostBreak(level, cell) {
        if (level !== levelIndex || levelType !== "dungeon") return
        let cache = [].concat(...secretRooms.filter(s => s.open).map(s => s.cache))
        let f = features.concat(cache).find(f => f.gx + "," + f.gy === cell && Balance.dungeon.loot[f.kind])
        if (!f) return
        let b = breakableAt(cell)
        if (b) _wreck(b, 0, -1)
        _broken(f.kind, cell, f.xWu, f.yWu)
    }
    // The host's cells broken in the level: those still whole here break
    function _applyBroken(v) {
        if (!v || !session.connected || session.isHost || levelType !== "dungeon") return
        if (v.seed !== session.runSeed || v.level !== levelIndex) return
        for (let cell of v.cells) {
            let b = breakableAt(cell)
            if (b) _wreck(b, 0, -1)
        }
    }
    readonly property var _sessionBroken: session.broken
    on_SessionBrokenChanged: _applyBroken(_sessionBroken)
    // Off the floor with its look's pieces thrown along (nx, ny) and a
    // crack; false when it was broken already
    function _wreck(b, nx, ny) {
        let i = breakables.indexOf(b)
        if (i < 0) return false
        breakables.splice(i, 1)
        let c = b.cell.split(",").map(Number)
        delete _propCells[c[1] * gridWidth + c[0]]
        _setPathCell(c[0], c[1], true)
        let x = b.cxWu, y = b.cyWu
        if (b.kind === "urn") {
            spawnShards(x, y, nx, ny, 10, b._clay, 0.2)
            spawnShards(x, y, nx, ny, 4, Qt.lighter(b._clay, 1.3), 0.28)
            impactSound.triggerOneShot(0.5)
        } else if (b.kind === "crate") {
            spawnShards(x, y, nx, ny, 9, b._wood, 0.24)
            spawnShards(x, y, nx, ny, 5, Qt.lighter(b._wood, 1.3), 0.14)
            impactSound.triggerOneShot(0.6)
        } else {
            spawnShards(x, y, nx, ny, 12, "#7FE6FF", 0.18)
            spawnSparks(x, y, nx, ny, 10, "#E8FBFF")
            impactSound.triggerOneShot(0.7)
        }
        if (b.glow) b.glow.destroy()
        b.destroy()
        return true
    }

    // --- Spike plates (issue #124) ---
    // A plate stands on its feature's cell, the same on every screen. This
    // node's knight stepping on it, its centre on the plate, makes it
    // click; spikeDelay later its spikes rise and judge this node's knight
    // alone: on the plate and not dashing, it takes the spikes' damage
    // (spikeDamageAt). Then it stays sprung. Alone the delay runs on the
    // physics clock, held by a pause. In a session the rise is a moment on
    // the session clock: the node that set it off reports it to the host,
    // which publishes the plates set off in the level (session property
    // "sprung"), and every other screen clicks and raises the plate at that
    // moment, judging its own knight, a node that joins later too
    Component { id: plateComponent; SpikePlate {} }
    property var plates: []
    // Host: the plates set off in this level, "gx,gy" to their riseAt
    property var _sprungCells: ({})
    // A plate clicked or rose on this screen; result is what its spikes
    // did to this node's knight (SpikePlate.result)
    signal plateClicked(string cell)
    signal plateRose(string cell, string result)
    function _placePlate(f, band) {
        let p = plateComponent.createObject(world.room, {
            cell: f.gx + "," + f.gy, xWu: f.xWu, yWu: f.yWu, band: band,
            sizeWu: Balance.dungeon.spikePlateSize,
            seed: createRng(f.gx * 7349 + f.gy * 3571)(),
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
        })
        if (p) plates.push(p)
        return p
    }
    function plateAt(cell) {
        return plates.find(p => p.cell === cell) || null
    }
    // What a plate's spikes deal at depth d to a knight of maxHp: never
    // more than spikeCap of its max HP
    function spikeDamageAt(d, maxHp) {
        let t = Balance.dungeon
        return Math.min(Math.round(t.spikeDamage + t.spikeDamagePerDepth * Math.max(0, d)),
                        Math.floor(t.spikeCap * maxHp))
    }
    // Whether this node's knight stands on plate p: its centre on the slab
    function onPlate(p) {
        if (!player) return false
        let h = p.sizeWu / 2
        return Math.abs(player.xWu + player.widthWu / 2 - p.xWu) <= h
            && Math.abs(player.yWu - player.heightWu / 2 - p.yWu) <= h
    }
    // Each physics step: a plate this knight steps on clicks, a clicked
    // one whose moment came rises
    function _stepPlates() {
        if (plates.length === 0 || levelType !== "dungeon") return
        let dt = world.physics.timeStep
        for (let p of plates.slice()) {
            if (p.phase === "armed") {
                if (player && !player.fallen && onPlate(p)) _clickPlate(p, -1)
            } else if (p.phase === "clicked") {
                let due = p.riseAt >= 0 ? session.now() >= p.riseAt
                                        : (p.riseIn = p.riseIn - dt) <= 1e-6
                if (due) _risePlate(p)
            }
        }
    }
    // p clicks: set off by this node's knight (riseAt -1), or by another's,
    // its spikes due at riseAt on the session clock
    function _clickPlate(p, riseAt) {
        p.phase = "clicked"
        playPlateClick()
        if (riseAt >= 0) {
            p.riseAt = riseAt
        } else if (session.connected) {
            p.riseAt = session.now() + Balance.dungeon.spikeDelay * 1000
            session.reportSpring(levelIndex, p.cell, p.riseAt)
        } else {
            p.riseIn = Balance.dungeon.spikeDelay
        }
        plateClicked(p.cell)
    }
    // p's spikes rise: this node's knight on it is hit, unless it dashes
    function _risePlate(p) {
        p.phase = "sprung"
        playSpikesRise()
        spawnSparks(p.xWu, p.yWu, 0, 1, 6, "#E6E2D6")
        let result = "clear"
        if (player && onPlate(p)) {
            result = player.takeTrapDamage(spikeDamageAt(dangerDepth, player.maxHp))
            console.log("[Game] Spikes rose under the knight at", p.cell, "-", result)
        }
        p.result = result
        plateRose(p.cell, result)
    }
    // Host: a node set off the plate on that cell of that level, its
    // spikes due at riseAt; the first word on a plate holds
    function _hostSpring(level, cell, riseAt) {
        if (level !== levelIndex || levelType !== "dungeon") return
        if (_sprungCells[cell] !== undefined || !plateAt(cell)) return
        _sprungCells[cell] = riseAt
        let p = plateAt(cell)
        if (p.phase === "armed") _clickPlate(p, riseAt)
        session.publishSprung({ seed: session.runSeed, level: levelIndex,
                                plates: Object.assign({}, _sprungCells) })
    }
    // The host's plates set off in the level: those still armed here click
    // and rise at their moment; long past, they are simply sprung
    function _applySprung(v) {
        if (!v || !session.connected || session.isHost || levelType !== "dungeon") return
        if (v.seed !== session.runSeed || v.level !== levelIndex) return
        for (let cell in v.plates) {
            let p = plateAt(cell)
            if (!p || p.phase !== "armed") continue
            if (session.now() - v.plates[cell] > 1000) p.phase = "sprung"
            else _clickPlate(p, v.plates[cell])
        }
    }
    readonly property var _sessionSprung: session.sprung
    on_SessionSprungChanged: _applySprung(_sessionSprung)

    // --- Arrow slits (issue #125) ---
    // A slit sits in the wall beside its feature's cell, on a room's edge,
    // and fires across the room on the beats of its rhythm
    // (Balance.dungeon.slit...). The beats are counted on the trap clock:
    // the session clock in a session, so every screen fires the same arrow
    // at the same moment, alone the physics clock, held by a pause. An
    // arrow's flight is a function of that clock, the same on every screen
    // too. Each game judges the arrows on its own knight alone
    // (Player.meetArrow) and tells the others what became of one that hit,
    // was blocked or sent back, which then goes on their screens as well
    Component { id: slitComponent; ArrowSlit {} }
    Component { id: arrowComponent; Arrow {} }
    property var slits: []
    property var arrows: []
    // The knight's square and an arrow's thickness, wu, for the hits and
    // the gaps
    readonly property real knightSizeWu: 1.0
    readonly property real arrowWidthWu: 0.2
    // Seconds on the physics clock, the trap clock alone
    property real _trapClock: 0
    // The last beat the slits fired on, -1 before the first step
    property int _slitBeat: -1
    // What another node's knight did to an arrow not fired here yet, by id
    property var _arrowFates: ({})
    // An arrow left its slit on this screen, at the trap clock's moment at
    // (s); this node's knight met one: result as Player.meetArrow's; one
    // went: on the wall facing its slit ("wall"), on its slit, sent back
    // ("slit"), or on a knight or a shield ("knight")
    signal arrowFired(string id, string cell, real at)
    signal arrowMet(string id, string result)
    signal arrowEnded(string id, string where)

    // Where a slit on cell (gx, gy) of room fires from, or null. The cell
    // lies on the room's edge with a wall beside it - north, south, west
    // or east, the first that fits - and the slit's line runs from it
    // across the room to a wall, not a doorway, on no line of a slit
    // picked in the room before. {dx, dy, cells}: the way it fires, y up,
    // and the cells its line crosses
    function _slitAim(gx, gy, room, picked) {
        for (let n of [[0, 1], [0, -1], [-1, 0], [1, 0]]) {
            if (!grid[gy + n[1]] || grid[gy + n[1]][gx + n[0]] !== cellWall) continue
            let dx = -n[0], dy = -n[1], x = gx, y = gy, cells = 0
            while (x >= room.x && x < room.x + room.w && y >= room.y && y < room.y + room.h) {
                cells++
                x += dx
                y += dy
            }
            if (!grid[y] || grid[y][x] !== cellWall) continue
            if (picked.some(p => dy === 0 ? p.dy === 0 && p.gy === gy : p.dx === 0 && p.gx === gx))
                continue
            return { dx: dx, dy: dy, cells: cells }
        }
        return null
    }
    // The cells of a slit's line, "gx,gy"
    function slitLine(f) {
        let out = []
        for (let i = 0, x = f.gx, y = f.gy; i < f.cells; i++, x += f.dx, y += f.dy) out.push(x + "," + y)
        return out
    }
    // The longest rest of a rhythm's beats a knight has to walk over a
    // slit's line, s: the time between two arrows less the time one takes
    // to pass a knight
    function slitGap(beats) {
        let t = Balance.dungeon, shots = []
        beats.forEach((b, i) => { if (b === 1) shots.push(i) })
        if (shots.length === 0) return Infinity
        let longest = 0
        for (let i = 0; i < shots.length; i++) {
            let next = i + 1 < shots.length ? shots[i + 1] : shots[0] + beats.length
            longest = Math.max(longest, next - shots[i])
        }
        return longest * t.slitBeat - (t.arrowLength + knightSizeWu) / t.arrowSpeed
    }
    // What a knight takes to walk over a line at its pace, s, and the gap
    // a rhythm must leave for it
    function slitCrossTime() { return (knightSizeWu + arrowWidthWu) / Balance.knight.moveSpeed }
    function slitGapNeed() { return Balance.dungeon.slitGapMargin * slitCrossTime() }
    // Whether room leaves a lane past its slits (group): its doorways - its
    // cells beside a corridor - on none of their lines and under no
    // breakable of list, and all of them joined by such cells
    function slitLane(room, group, list) {
        let blocked = {}
        for (let f of group) for (let c of slitLine(f)) blocked[c] = true
        for (let f of list) if (Balance.dungeon.loot[f.kind]) blocked[f.gx + "," + f.gy] = true
        let inRoom = (x, y) => x >= room.x && x < room.x + room.w && y >= room.y && y < room.y + room.h
        let doors = []
        for (let gy = room.y; gy < room.y + room.h; gy++)
            for (let gx = room.x; gx < room.x + room.w; gx++)
                for (let n of [[1, 0], [-1, 0], [0, 1], [0, -1]])
                    if (grid[gy + n[1]] && grid[gy + n[1]][gx + n[0]] === cellHallway) {
                        doors.push(gx + "," + gy)
                        break
                    }
        if (doors.some(d => blocked[d])) return false
        if (doors.length < 2) return true
        let seen = {}, todo = [doors[0]]
        seen[doors[0]] = true
        while (todo.length > 0) {
            let c = todo.pop().split(",").map(Number)
            for (let n of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
                let x = c[0] + n[0], y = c[1] + n[1], k = x + "," + y
                if (!inRoom(x, y) || seen[k] || blocked[k]) continue
                seen[k] = true
                todo.push(k)
            }
        }
        return doors.every(d => seen[d])
    }
    // The rhythms of the planned slits: a room's slits share one, drawn
    // from the band's rhythms by the level's seed and the room's first
    // slit, each started its share of a turn after the one before, so two
    // take turns. A room that leaves no lane takes the band's first
    // rhythm with a gap if the one drawn has none. Each slit gets rhythm,
    // beats, offset and safe ("lane" or "gap")
    function _rhythmSlits(list, levelSeed, band) {
        let rhythms = Balance.dungeon.slitRhythms.filter(r => r.bands.indexOf(band) >= 0)
        let byRoom = {}
        for (let f of list) {
            if (f.kind !== "slit") continue
            let r = rooms.findIndex(m => f.gx >= m.x && f.gx < m.x + m.w && f.gy >= m.y && f.gy < m.y + m.h)
            byRoom[r] = (byRoom[r] || []).concat([f])
        }
        for (let r in byRoom) {
            let group = byRoom[r]
            let rand = createRng(levelSeed ^ 0x1f83d9ab ^ (group[0].gy * gridWidth + group[0].gx))
            let rhythm = rhythms[Math.floor(rand() * rhythms.length)]
            let lane = slitLane(rooms[r], group, list)
            if (!lane && slitGap(rhythm.beats) < slitGapNeed())
                rhythm = rhythms.find(x => slitGap(x.beats) >= slitGapNeed()) || rhythm
            let start = Math.floor(rand() * rhythm.beats.length)
            group.forEach((f, i) => Object.assign(f, {
                rhythm: rhythm.name, beats: rhythm.beats, safe: lane ? "lane" : "gap",
                offset: start + Math.round(i * rhythm.beats.length / group.length) }))
        }
        return list
    }

    function _placeSlit(f, band) {
        let s = slitComponent.createObject(world.room, {
            cell: f.gx + "," + f.gy,
            xWu: f.xWu - f.dx * cellSize / 2, yWu: f.yWu - f.dy * cellSize / 2,
            dirX: f.dx, dirY: f.dy, lineWu: f.cells * cellSize,
            rhythm: f.rhythm, beats: f.beats, offset: f.offset, band: band,
            ringParent: glowParent(),
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
        })
        if (s) slits.push(s)
        return s
    }
    function slitAt(cell) {
        return slits.find(s => s.cell === cell) || null
    }
    // The trap clock, s
    function trapTime() { return session.connected ? session.now() / 1000 : _trapClock }
    // Whether slit s fires on beat k of the trap clock
    function slitFiresOn(s, k) {
        let n = s.beats.length
        return s.beats[((k + s.offset) % n + n) % n] === 1
    }
    // What an arrow deals at depth d to a knight of maxHp, before its
    // defence: never more than arrowCap of its max HP
    function arrowDamageAt(d, maxHp) {
        let t = Balance.dungeon
        return Math.min(Math.round(t.arrowDamage + t.arrowDamagePerDepth * Math.max(0, d)),
                        Math.floor(t.arrowCap * maxHp))
    }
    // The shot's twang, fading with the distance from this knight
    function _playArrow(xWu, yWu) {
        let gain = remoteGain(xWu, yWu) / remoteMaxGain
        if (gain > 0)
            swordSwingSound.triggerNote(swordSwingSound.rootNote + Balance.dungeon.slitShotPitch, 0.6 * gain)
    }

    // Each physics step: the slits fire on the beats passed since the step
    // before, wind up for the next, and the arrows fly
    function _stepSlits() {
        if (levelType !== "dungeon" || slits.length === 0) return
        _trapClock += world.physics.timeStep
        let t = trapTime(), beat = Balance.dungeon.slitBeat
        let k = Math.floor(t / beat)
        // The first step, or the clock set back or far ahead (a session's
        // clock syncing): no beats caught up
        if (_slitBeat < 0 || k < _slitBeat || k - _slitBeat > 4) _slitBeat = k
        for (let b = _slitBeat + 1; b <= k; b++)
            for (let s of slits) if (slitFiresOn(s, b)) _fireArrow(s, b, b * beat)
        _slitBeat = k
        let warn = Balance.dungeon.slitWarn
        for (let s of slits) {
            let next = k + 1
            while (!slitFiresOn(s, next) && next <= k + s.beats.length) next++
            let left = next * beat - t
            s.warn = left <= warn ? 1 - left / warn : 0
            s.flash = t - s.shotAt >= 0 && t - s.shotAt < 0.08
        }
        for (let a of arrows.slice()) _flyArrow(a, t)
    }
    // Slit s fires: the arrow of beat b, leaving at the clock's moment at
    function _fireArrow(s, b, at) {
        let id = s.cell + "#" + b
        let a = arrowComponent.createObject(glowParent(), {
            arrowId: id, slit: s, dirX: s.dirX, dirY: s.dirY,
            lengthWu: Balance.dungeon.arrowLength,
            fromX: s.xWu, fromY: s.yWu, fromT: at, flightWu: s.lineWu,
            xWu: s.xWu, yWu: s.yWu, lastX: s.xWu, lastY: s.yWu,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
        })
        if (!a) return
        arrows.push(a)
        s.shotAt = at
        _playArrow(s.xWu, s.yWu)
        arrowFired(id, s.cell, at)
        let fate = _arrowFates[id]
        if (fate) {
            delete _arrowFates[id]
            _arrowFate(a, fate)
        }
    }
    // Arrow a at the clock's moment t: on its way from its start, until it
    // reaches the wall facing its slit, or its slit when sent back
    function _flyArrow(a, t) {
        let d = Math.max(0, Math.min(a.flightWu, Balance.dungeon.arrowSpeed * (t - a.fromT)))
        a.lastX = a.xWu
        a.lastY = a.yWu
        a.xWu = a.fromX + a.dirX * d
        a.yWu = a.fromY + a.dirY * d
        let back = a.back
        if (!a.judged) _judgeArrow(a, t)
        if (a.back !== back) return
        if (arrows.indexOf(a) >= 0 && d >= a.flightWu - 1e-6) _endArrow(a, a.back ? "slit" : "wall")
    }
    // Whether arrow a's shaft, swept since the step before, meets this
    // node's knight; if so the knight's game judges it
    function _judgeArrow(a, t) {
        if (!player) return
        let cx = player.xWu + player.widthWu / 2, cy = player.yWu - player.heightWu / 2
        let hw = player.widthWu / 2 + arrowWidthWu / 2, hh = player.heightWu / 2 + arrowWidthWu / 2
        let tx = a.lastX - a.dirX * a.lengthWu, ty = a.lastY - a.dirY * a.lengthWu
        if (Math.max(tx, a.xWu) < cx - hw || Math.min(tx, a.xWu) > cx + hw
                || Math.max(ty, a.yWu) < cy - hh || Math.min(ty, a.yWu) > cy + hh)
            return
        a.judged = true
        // Where it comes from: on its line, two wu towards its slit
        let fx = a.dirX !== 0 ? cx - a.dirX * 2 : a.xWu
        let fy = a.dirY !== 0 ? cy - a.dirY * 2 : a.yWu
        let result = player.meetArrow(arrowDamageAt(dangerDepth, player.maxHp), fx, fy, a.dirX, a.dirY)
        console.log("[Game] Arrow", a.arrowId, "met the knight -", result)
        arrowMet(a.arrowId, result)
        if (result !== "hit" && result !== "blocked" && result !== "perfect") return
        if (session.connected)
            session.reportStruck({source: "arrow", id: a.arrowId, result: result,
                                  x: a.xWu, y: a.yWu, at: t * 1000})
        if (result === "perfect") _sendBack(a, a.xWu, a.yWu, t)
        else _endArrow(a, "")
    }
    // A perfect block sends arrow a back to its slit from (x, y) at the
    // clock's moment t; it hurts nobody on its way
    function _sendBack(a, x, y, t) {
        if (a.back) return
        a.back = true
        a.judged = true
        a.fromX = x
        a.fromY = y
        a.fromT = t
        a.flightWu = Math.abs(x - a.slit.xWu) + Math.abs(y - a.slit.yWu)
        a.dirX = -a.dirX
        a.dirY = -a.dirY
    }
    // Arrow a is gone: it broke on the wall facing its slit ("wall"), on
    // its slit ("slit"), or on a knight or a shield ("")
    function _endArrow(a, where) {
        let i = arrows.indexOf(a)
        if (i < 0) return
        arrows.splice(i, 1)
        if (where === "wall") spawnSparks(a.xWu, a.yWu, -a.dirX, -a.dirY, 3, "#C8B898")
        else if (where === "slit") spawnSparks(a.xWu, a.yWu, -a.dirX, -a.dirY, 8, "#FFFFFF")
        arrowEnded(a.arrowId, where === "" ? "knight" : where)
        a.destroy()
    }
    // Another node's knight met an arrow: hit or blocked it is gone here
    // too, sent back it flies back here too
    function _arrowReported(r) {
        if (levelType !== "dungeon") return
        let a = arrows.find(x => x.arrowId === r.id)
        if (a) _arrowFate(a, r)
        else _arrowFates[r.id] = r
    }
    function _arrowFate(a, r) {
        if (r.result === "perfect") _sendBack(a, r.x, r.y, r.at / 1000)
        else _endArrow(a, "")
    }
    function _clearArrows() {
        for (let a of arrows) {
            try { a.destroy() } catch (err) {}
        }
        arrows = []
        _arrowFates = {}
        _slitBeat = -1
    }

    // --- Doors (issue #127) ---
    // Some room entrances get a door (Balance.dungeon.doorShare): a
    // doorway, a corridor's cell beside a room with rock on its two other
    // sides, narrowed by two jambs to a leaf one knight wide. The doors
    // come from their own stream of the level's seed, so nothing else of
    // the dungeon moves, and start closed. A closed door blocks the
    // knights, the enemies, their shots and their sight; E beside it opens
    // or closes it (useDoor). An enemy chasing through a closed one winds
    // up doorBash seconds and bursts it open (Enemy "bash", bashDoor), and
    // a bashed door stays open. Alone the game owns the doors; in a
    // session the host does: a node's E asks it, and it publishes the
    // doors not closed in the level (session property "doors") for every
    // screen, a node that joins later too
    Component { id: doorComponent; Door {} }
    property var doors: []
    // Host, and alone: the doors not closed in this level, "gx,gy" to
    // "open" or "bashed"
    property var _doorStates: ({})

    // Whether cell (gx, gy) of the carved grid is a doorway: a corridor's
    // cell beside a room, rock on its two other sides, not in the
    // entrance's or the exit's shaft. Its axis then: across when the
    // corridor runs along x, and the side of the room along it
    function doorway(gx, gy) {
        if (grid[gy][gx] !== cellHallway || rooms.length < 2) return null
        let start = rooms[0], end = rooms[rooms.length - 1]
        if ((gx === entranceGridX && gy < start.y) || (gx === exitGridX && gy >= end.y + end.h))
            return null
        let at = (x, y) => x >= 0 && x < gridWidth && y >= 0 && y < gridHeight ? grid[y][x] : cellWall
        for (let d of [[1, 0], [0, 1]]) {
            if (at(gx + d[1], gy + d[0]) !== cellWall || at(gx - d[1], gy - d[0]) !== cellWall) continue
            let a = at(gx + d[0], gy + d[1]), b = at(gx - d[0], gy - d[1])
            if (a === cellWall || b === cellWall) continue
            if (a !== cellRoom && b !== cellRoom) continue
            return { across: d[0] === 1, roomSide: a === cellRoom ? 1 : -1 }
        }
        return null
    }
    // The doors of the carved dungeon, without touching the world:
    // [{gx, gy, xWu, yWu, across, roomSide}], each doorway in grid order
    // with doorShare's chance at the band, every one in the showcase
    function planDoors(levelSeed, band, showcase) {
        let out = []
        let rand = createRng(levelSeed ^ 0x446f6f72)
        let share = showcase ? 1 : Balance.dungeon.doorShare[band]
        for (let gy = 0; gy < gridHeight; gy++)
            for (let gx = 0; gx < gridWidth; gx++) {
                let d = doorway(gx, gy)
                if (!d || rand() >= share) continue
                out.push(Object.assign({ gx: gx, gy: gy, xWu: (gx + 0.5) * cellSize,
                                         yWu: (gy + 0.5) * cellSize }, d))
            }
        return out
    }
    function placeDoors(list) {
        doors = []
        _doorStates = ({})
        let t = Balance.dungeon, band = dangerBand(dangerPosition)
        let jamb = (cellSize - t.doorWidth) / 2
        for (let f of list) {
            // The jambs, walls at both ends of the leaf
            let x0 = f.gx * cellSize, y0 = f.gy * cellSize
            if (f.across) {
                createWallAt(f.xWu - t.doorJamb / 2, y0 + jamb, t.doorJamb, jamb)
                createWallAt(f.xWu - t.doorJamb / 2, y0 + cellSize, t.doorJamb, jamb)
            } else {
                createWallAt(x0, f.yWu + t.doorJamb / 2, jamb, t.doorJamb)
                createWallAt(x0 + cellSize - jamb, f.yWu + t.doorJamb / 2, jamb, t.doorJamb)
            }
            let d = doorComponent.createObject(world.room, {
                cell: f.gx + "," + f.gy, cxWu: f.xWu, cyWu: f.yWu,
                across: f.across, roomSide: f.roomSide,
                leafWu: t.doorWidth, thickWu: t.doorThickness, band: band,
                seed: createRng(f.gx * 7349 + f.gy * 3571)(),
                pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
                world: world.physics,
                categories: catWall,
                collidesWith: catPlayer | catEnemy | catProjectile
            })
            if (!d) continue
            doors.push(d)
            dungeonObjects.push(d)
        }
    }
    function doorAt(cell) {
        return doors.find(d => d.cell === cell) || null
    }
    function doorShut(cell) {
        let d = doorAt(cell)
        return d !== null && d.shut
    }
    // The door nearest (x, y) within reach wu of its centre, bashed ones
    // left out; null for none
    function nearestDoor(x, y, reach) {
        let best = null, bestD = reach
        for (let d of doors) {
            if (d.doorState === "bashed") continue
            let dist = Math.hypot(d.cxWu - x, d.cyWu - y)
            if (dist <= bestD) { best = d; bestD = dist }
        }
        return best
    }
    // Whether a knight or an enemy stands where door d's leaf closes
    function _doorTaken(d) {
        let bodies = enemies.filter(e => e && !e.destroyed)
        if (player) bodies.push(player)
        for (let id in session.remotePlayers) bodies.push(session.remotePlayers[id])
        let half = Balance.dungeon.doorWidth / 2
        for (let b of bodies) {
            let bx = b.xWu + b.widthWu / 2 - d.cxWu, by = b.yWu - b.heightWu / 2 - d.cyWu
            let along = d.across ? bx : by, side = d.across ? by : bx
            if (Math.abs(along) < d.thickWu / 2 + b.widthWu / 2 && Math.abs(side) < half + b.widthWu / 2)
                return true
        }
        return false
    }
    // This node's knight pressed E at door d: it opens a closed door and
    // closes an open one, unless someone stands in it; alone at once, in a
    // session by the host. False when it does nothing
    function useDoor(d) {
        if (!d || d.doorState === "bashed") return false
        let open = d.shut
        if (!open && _doorTaken(d)) return false
        if (session.connected && !session.isHost) session.reportDoor(levelIndex, d.cell, open)
        else _setDoor(d.cell, open ? "open" : "closed")
        return true
    }
    // Host: a node's knight opened or closed the door on that cell
    function _hostDoor(level, cell, open) {
        if (level !== levelIndex || levelType !== "dungeon") return
        let d = doorAt(cell)
        if (!d || d.doorState === "bashed") return
        if (!open && _doorTaken(d)) return
        _setDoor(cell, open ? "open" : "closed")
    }
    // Alone, or the host: an enemy here burst the door on cell open
    function bashDoor(cell) { _setDoor(cell, "bashed") }
    // Alone, or the host: the door on cell is now state, and in a session
    // every screen is told. A bashed door stays as it is
    function _setDoor(cell, state) {
        let d = doorAt(cell)
        if (!d || d.doorState === state || d.doorState === "bashed") return
        _showDoor(d, state)
        let v = Object.assign({}, _doorStates)
        if (state === "closed") delete v[cell]
        else v[cell] = state
        _doorStates = v
        // A path holds the waypoints already passed: the enemies on the
        // chase plan anew from where they stand, so a door shut behind
        // one is no door ahead of it (closedDoorAhead)
        if (state === "closed")
            for (let e of enemies)
                if (e && !e.destroyed && !e.remote && e.aiState === "chase") e._recalcChasePath()
        if (session.connected)
            session.publishDoors({ seed: session.runSeed, level: levelIndex, doors: v })
    }
    function _showDoor(d, state) {
        if (d.doorState === state) return
        d.doorState = state
        if (state === "bashed") {
            let nx = d.across ? -d.roomSide : 0, ny = d.across ? 0 : -d.roomSide
            spawnShards(d.cxWu, d.cyWu, nx, ny, 10, d._wood, 0.26)
            spawnShards(d.cxWu, d.cyWu, nx, ny, 6, Qt.lighter(d._wood, 1.35), 0.16)
            impactSound.triggerOneShot(0.8)
        } else {
            impactSound.triggerOneShot(0.2)
        }
    }
    // The host's doors not closed in the level: every door here as they say
    function _applyDoors(v) {
        if (!v || !session.connected || session.isHost || levelType !== "dungeon") return
        if (v.seed !== session.runSeed || v.level !== levelIndex) return
        for (let d of doors) {
            if (d.doorState === "bashed") continue
            _showDoor(d, v.doors[d.cell] || "closed")
        }
    }
    readonly property var _sessionDoors: session.doors
    on_SessionDoorsChanged: _applyDoors(_sessionDoors)
    // Each physics step: the E over the door this node's knight may use
    function _stepDoors() {
        if (doors.length === 0) return
        let near = player && !fallen ? nearestDoor(player.xWu + player.widthWu / 2,
                                                   player.yWu - player.heightWu / 2,
                                                   Balance.dungeon.doorReach) : null
        for (let d of doors) d.prompt = d === near
    }
    // Whether the line from (x1, y1) to (x2, y2) runs through a closed
    // door's doorway
    function _shutBetween(x1, y1, x2, y2) {
        for (let d of doors) {
            if (!d.shut) continue
            let a1 = d.across ? x1 : y1, a2 = d.across ? x2 : y2
            let s1 = d.across ? y1 : x1, s2 = d.across ? y2 : x2
            let at = d.across ? d.cxWu : d.cyWu, side = d.across ? d.cyWu : d.cxWu
            if ((a1 - at) * (a2 - at) > 0 || a1 === a2) continue
            let s = s1 + (s2 - s1) * (at - a1) / (a2 - a1)
            if (Math.abs(s - side) <= cellSize / 2) return true
        }
        return false
    }
    // The closed door on enemy e's path within doorBashReach wu of it, its
    // cell; "" for none
    function closedDoorAhead(e) {
        let wps = e.pathAhead()
        if (doors.length === 0 || wps.length === 0) return ""
        let x = e.xWu + e.widthWu / 2, y = e.yWu - e.heightWu / 2
        for (let d of doors) {
            if (!d.shut || Math.hypot(d.cxWu - x, d.cyWu - y) > Balance.dungeon.doorBashReach) continue
            if (wps.some(w => Math.abs(w.x - d.cxWu) < 0.01 && Math.abs(w.y - d.cyWu) < 0.01))
                return d.cell
        }
        return ""
    }

    // --- Secret rooms (issue #128) ---
    // Some dungeons hide a chamber off a room behind a secret door
    // (Balance.dungeon.secrets): one cell of the room's wall, with a
    // hairline crack and dust breathing out of it (SecretWall). The
    // secrets come from their own stream of the level's seed, laid out
    // after the features and the doors, so nothing else of the dungeon
    // moves. Until it is opened a secret room is rock in the grid: the
    // walls, their faces, the shadows, the enemies' sight and paths and
    // the minimap take it as stone, and it lies on no way to the exit. A
    // dash of this node's knight into the cracked face bursts it open
    // (_stepSecrets, burstSecret), one that glances off it shows a puff of
    // dust; E does nothing at it. Opened, the walls on its cells go, the grid opens
    // and the cache inside - urns, crates, maybe a crystal - stands on its
    // floor, richer than elsewhere (cacheLoot). Alone the game owns the
    // secrets; in a session the host does: a node's E asks it, and it
    // keeps the secrets opened in the level as the session property
    // "secrets", so every screen opens them, a player who joins later too
    Component { id: secretWallComponent; SecretWall {} }
    // [{cell, gx, gy, fx, fy, nx, ny, room: {x, y, w, h}, cache: [feature],
    // open, built: [the walls, faces and rims on its cells], trims: [the
    // faces and rims its opening bared], clue}]: gx, gy
    // the cracked wall cell ("gx,gy" its cell), fx, fy the floor cell in
    // front of it, (nx, ny) the step from the one to the other
    property var secretRooms: []
    // The secret rooms' cells by grid key (gy * gridWidth + gx), the
    // cracked one with them, to their index in secretRooms
    property var _secretCells: ({})
    // The cache things' cells, "gx,gy", which roll their gold by cacheLoot
    property var _cacheCells: ({})
    // Host, and alone: the cells of the secrets opened in this level
    property var _openedSecrets: []

    function _secretOf(gx, gy) {
        let i = _secretCells[gy * gridWidth + gx]
        return i === undefined ? -1 : i
    }
    function _keepSecretBuilt(i, o) {
        if (i >= 0 && o) secretRooms[i].built.push(o)
    }
    // The secret rooms of the carved dungeon with these features and
    // doors, at the band or the showcase count, without touching the
    // world or the grid. Each hides behind one cell of a room's wall, not
    // at its corners and not of the start room: the floor cell in front of
    // it a feature's cell would be (featureCellOk) with no feature on it,
    // the cell rock with rock beside it along the wall, and the chamber,
    // secretSize cells square, beyond it with rock all round, out of every
    // other room, corridor, shaft and secret. The candidates are taken in
    // an order drawn from the secrets' own stream, one to a room, and the
    // same stream lays out each one's cache
    function planSecrets(levelSeed, band, showcase, featureList, doorList) {
        let t = Balance.dungeon
        let rand = createRng(levelSeed ^ 0x53656372)
        let want = showcase ? t.secretShowcase : Math.floor(t.secrets[band] + rand())
        let out = []
        if (want <= 0 || rooms.length < 2) return out
        let n = t.secretSize
        let used = {}
        for (let f of featureList || []) used[f.gx + "," + f.gy] = true
        for (let d of doorList || []) used[d.gx + "," + d.gy] = true
        let cands = []
        for (let ri = 1; ri < rooms.length; ri++) {
            let r = rooms[ri]
            for (let d of [[0, 1], [0, -1], [1, 0], [-1, 0]]) {
                let len = d[0] === 0 ? r.w : r.h
                for (let i = 1; i < len - 1; i++) {
                    let fx = d[0] === 0 ? r.x + i : (d[0] > 0 ? r.x + r.w - 1 : r.x)
                    let fy = d[0] !== 0 ? r.y + i : (d[1] > 0 ? r.y + r.h - 1 : r.y)
                    let gx = fx + d[0], gy = fy + d[1]
                    for (let off of [0, -1, 1]) {
                        let x0 = d[0] === 0 ? gx - Math.floor(n / 2) + off : (d[0] > 0 ? gx + 1 : gx - n)
                        let y0 = d[1] === 0 ? gy - Math.floor(n / 2) + off : (d[1] > 0 ? gy + 1 : gy - n)
                        cands.push({ ri: ri, gx: gx, gy: gy, fx: fx, fy: fy, nx: -d[0], ny: -d[1],
                                     room: { x: x0, y: y0, w: n, h: n } })
                    }
                }
            }
        }
        for (let i = cands.length - 1; i > 0; i--) {
            let j = Math.floor(rand() * (i + 1))
            let c = cands[i]; cands[i] = cands[j]; cands[j] = c
        }
        let rock = (x, y) => x >= 0 && x < gridWidth && y >= 0 && y < gridHeight && grid[y][x] === cellWall
        let taken = {}, hosts = {}
        for (let c of cands) {
            if (out.length >= want) break
            if (hosts[c.ri] || used[c.fx + "," + c.fy] || !featureCellOk(c.fx, c.fy)) continue
            if (!rock(c.gx, c.gy) || !rock(c.gx + c.ny, c.gy + c.nx) || !rock(c.gx - c.ny, c.gy - c.nx))
                continue
            let m = c.room
            if (m.x < 1 || m.y < 1 || m.x + m.w > gridWidth - 1 || m.y + m.h > gridHeight - 1) continue
            let ok = true
            for (let y = m.y - 1; ok && y <= m.y + m.h; y++)
                for (let x = m.x - 1; ok && x <= m.x + m.w; x++)
                    ok = rock(x, y) && !taken[y * gridWidth + x]
            if (!ok) continue
            for (let y = m.y - 1; y <= m.y + m.h; y++)
                for (let x = m.x - 1; x <= m.x + m.w; x++) taken[y * gridWidth + x] = true
            hosts[c.ri] = true
            // The cache on the chamber's cells but the one inside the door
            let inside = [c.gx - c.nx, c.gy - c.ny]
            let cells = []
            for (let y = m.y; y < m.y + m.h; y++)
                for (let x = m.x; x < m.x + m.w; x++)
                    if (x !== inside[0] || y !== inside[1]) cells.push([x, y])
            for (let i = cells.length - 1; i > 0; i--) {
                let j = Math.floor(rand() * (i + 1))
                let q = cells[i]; cells[i] = cells[j]; cells[j] = q
            }
            let kinds = []
            for (let i = 0; i < t.cacheThings; i++) kinds.push(rand() < 0.5 ? "urn" : "crate")
            if (showcase || rand() < t.cacheCrystal[band]) kinds.push("crystal")
            let cache = kinds.slice(0, cells.length).map((k, i) => ({
                kind: k, gx: cells[i][0], gy: cells[i][1],
                xWu: (cells[i][0] + 0.5) * cellSize, yWu: (cells[i][1] + 0.5) * cellSize }))
            out.push({ cell: c.gx + "," + c.gy, gx: c.gx, gy: c.gy, fx: c.fx, fy: c.fy,
                       nx: c.nx, ny: c.ny, room: m, cache: cache })
        }
        return out
    }
    // The planned secrets are this level's: their cells known before the
    // walls are built, so the walls on them run apart
    function _takeSecrets(list) {
        secretRooms = list.map(s => Object.assign({ open: false, built: [], trims: [], clue: null }, s))
        let cells = {}, cache = {}
        secretRooms.forEach((s, i) => {
            cells[s.gy * gridWidth + s.gx] = i
            for (let y = s.room.y; y < s.room.y + s.room.h; y++)
                for (let x = s.room.x; x < s.room.x + s.room.w; x++) cells[y * gridWidth + x] = i
            for (let f of s.cache) cache[f.gx + "," + f.gy] = true
        })
        _secretCells = cells
        _cacheCells = cache
        _openedSecrets = []
    }
    // The clue over each cracked cell, and the faces and rims its opening
    // will bare, hidden till then: built with the level, before the
    // knights and the enemies, they lie under them
    function placeSecrets() {
        for (let s of secretRooms) {
            s.trims = _secretTrims(s)
            s.clue = secretWallComponent.createObject(world.room, {
                cxWu: (s.gx + 0.5) * cellSize, cyWu: (s.gy + 0.5) * cellSize, sizeWu: cellSize,
                nx: s.nx, ny: s.ny, seed: createRng(s.gx * 7349 + s.gy * 3571)(),
                pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
            })
            if (s.clue) dungeonObjects.push(s.clue)
        }
    }
    // The faces and rims secret s's opening bares, hidden: a face on a
    // wall cell over one of its cells, a rim under one, each run of them
    // along a row one piece
    function _secretTrims(s) {
        let out = []
        let opened = (x, y) => (x === s.gx && y === s.gy)
            || (x >= s.room.x && x < s.room.x + s.room.w && y >= s.room.y && y < s.room.y + s.room.h)
        let x0 = Math.min(s.gx, s.room.x) - 1, x1 = Math.max(s.gx, s.room.x + s.room.w - 1) + 1
        let y0 = Math.min(s.gy, s.room.y) - 1, y1 = Math.max(s.gy, s.room.y + s.room.h - 1) + 1
        for (let gy = y0; gy <= y1; gy++) {
            for (let which of [-1, 1]) {
                let trim = x => grid[gy][x] === cellWall && !opened(x, gy) && opened(x, gy + which)
                let gx = x0
                while (gx <= x1) {
                    if (!trim(gx)) { gx++; continue }
                    let startX = gx
                    while (gx <= x1 && trim(gx)) gx++
                    let o = which < 0 ? _createWallFace(startX, gx, gy) : _createWallRim(startX, gx, gy)
                    if (!o) continue
                    o.visible = false
                    out.push(o)
                }
            }
        }
        return out
    }
    function secretAt(cell) {
        return secretRooms.find(s => s.cell === cell) || null
    }
    // The closed secret whose cracked face a knight's body, its centre at
    // (x, y) and half wu wide, reaches: within secretDashReach wu of the
    // face, the centre in front of the cracked cell. null for none
    function secretTouched(x, y, half) {
        for (let s of secretRooms) {
            if (s.open) continue
            let dx = x - (s.gx + 0.5) * cellSize, dy = y - (s.gy + 0.5) * cellSize
            let off = dx * s.nx + dy * s.ny - cellSize / 2 - half
            let side = Math.abs(dx * s.ny - dy * s.nx)
            if (off > -0.05 && off <= Balance.dungeon.secretDashReach && side < cellSize / 2) return s
        }
        return null
    }
    // How straight a dash along (dirX, dirY), y up, heads into secret s's
    // wall: the cosine of the angle off straight, 1 head on, 0 along it
    function secretDashInto(s, dirX, dirY) {
        return -(dirX * s.nx + dirY * s.ny)
    }
    // A dash of this node's knight reached a cracked face and glanced off
    // it (Balance.dungeon.secretDashAngle), once a dash
    signal secretGlanced(string cell)
    // The secret the dash under way glanced off already
    property var _glancedBy: null
    // This node's knight's dash burst secret s: alone it opens at once,
    // in a session by the host. False when it does nothing
    function burstSecret(s) {
        if (!s || s.open) return false
        if (session.connected && !session.isHost) session.reportSecret(levelIndex, s.cell)
        else _openSecret(s.cell)
        return true
    }
    // Host: a node's knight opened the secret on that cell
    function _hostSecret(level, cell) {
        if (level !== levelIndex || levelType !== "dungeon") return
        _openSecret(cell)
    }
    // Alone, or the host: the secret on cell opens, and in a session every
    // screen is told
    function _openSecret(cell) {
        let s = secretAt(cell)
        if (!s || s.open) return
        _showSecret(s)
        _openedSecrets = _openedSecrets.concat([cell])
        if (session.connected)
            session.publishSecrets({ seed: session.runSeed, level: levelIndex, cells: _openedSecrets.slice() })
    }
    // Secret s opens on this screen: the walls on its cells go, the grid,
    // the shadows and the paths open, the faces and rims its opening bares
    // show, and its cache stands on its floor
    function _showSecret(s) {
        if (s.open) return
        s.open = true
        for (let o of s.built) { try { if (o) o.destroy() } catch(err) {} }
        dungeonObjects = dungeonObjects.filter(o => s.built.indexOf(o) < 0)
        s.built = []
        let carve = (x, y, type) => {
            grid[y][x] = type
            _setPathCell(x, y, true)
        }
        carve(s.gx, s.gy, cellHallway)
        for (let y = s.room.y; y < s.room.y + s.room.h; y++)
            for (let x = s.room.x; x < s.room.x + s.room.w; x++) carve(x, y, cellRoom)
        for (let o of s.trims) o.visible = Qt.binding(() => world.fx)
        updateOccluders()
        let band = dangerBand(dangerPosition)
        for (let f of s.cache) {
            let o = _placeBreakable(f, band)
            if (o) dungeonObjects.push(o)
        }
        if (s.clue) s.clue.open = true
        let cx = (s.gx + 0.5) * cellSize, cy = (s.gy + 0.5) * cellSize
        spawnShards(cx, cy, s.nx, s.ny, 12, "#5A6272", 0.28)
        spawnShards(cx, cy, s.nx, s.ny, 8, "#D8CDB6", 0.12)
        impactSound.triggerOneShot(0.7)
        shake(0.4)
        runSecrets++
        minimap.requestPaint()
        // A thing of its cache the host broke before this screen opened it
        _applyBroken(_sessionBroken)
    }
    // The host's secrets opened in the level: every one here opens
    function _applySecrets(v) {
        if (!v || !session.connected || session.isHost || levelType !== "dungeon") return
        if (v.seed !== session.runSeed || v.level !== levelIndex) return
        for (let cell of v.cells) {
            let s = secretAt(cell)
            if (s) _showSecret(s)
        }
    }
    readonly property var _sessionSecrets: session.secrets
    on_SessionSecretsChanged: _applySecrets(_sessionSecrets)
    // Each physics step: this node's knight dashing into a cracked face
    // bursts it open, heading in within secretDashAngle of straight; at a
    // flatter angle, still into the wall, the dash glances off with a puff
    // of dust from the crack and a dull knock, once a dash
    function _stepSecrets() {
        if (secretRooms.length === 0) return
        if (!player || fallen || !player.isDashing) { _glancedBy = null; return }
        let s = secretTouched(player.xWu + player.widthWu / 2, player.yWu - player.heightWu / 2,
                              player.widthWu / 2)
        if (!s) return
        let into = secretDashInto(s, player.dashDirX, -player.dashDirY)
        if (into >= Math.cos(Balance.dungeon.secretDashAngle * Math.PI / 180) - 1e-6) {
            burstSecret(s)
        } else if (into > 0 && _glancedBy !== s) {
            _glancedBy = s
            let cx = (s.gx + 0.5 + s.nx * 0.5) * cellSize, cy = (s.gy + 0.5 + s.ny * 0.5) * cellSize
            spawnShards(cx, cy, s.nx, s.ny, 6, "#D8CDB6", 0.1)
            impactSound.triggerOneShot(0.25)
            secretGlanced(s.cell)
        }
    }
    // What the minimap shows of cell (gx, gy): "" unexplored, "rock" or
    // "floor". A secret room is rock until it is opened
    function mapCell(gx, gy) {
        if (!exploredCells[gy] || !exploredCells[gy][gx]) return ""
        return grid[gy][gx] === cellWall ? "rock" : "floor"
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
                let startX = gx, secret = _secretOf(gx, gy)
                while (gx < gridWidth && grid[gy][gx] === cellWall && grid[gy + 1][gx] !== cellWall
                       && _secretOf(gx, gy) === secret)
                    gx++
                _keepSecretBuilt(secret, _createWallRim(startX, gx, gy))
            }
        }
    }
    function _createWallRim(fromGx, toGx, gy) {
        let r = wallRimComponent.createObject(world.room, {
            xWu: fromGx * cellSize, yWu: (gy + 1) * cellSize,
            widthWu: (toGx - fromGx) * cellSize,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            visible: Qt.binding(() => world.fx)
        })
        if (campStyled) r.color = campLook.rim
        dungeonObjects.push(r)
        return r
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
                let startX = gx, secret = _secretOf(gx, gy)
                while (gx < gridWidth && grid[gy][gx] === cellWall && grid[gy - 1][gx] !== cellWall
                       && _secretOf(gx, gy) === secret)
                    gx++
                _keepSecretBuilt(secret, _createWallFace(startX, gx, gy))
            }
        }
    }
    function _createWallFace(fromGx, toGx, gy) {
        let f = wallFaceComponent.createObject(world.room, {
            xWu: fromGx * cellSize,
            yWu: gy * cellSize + wallFaceWu,
            widthWu: (toGx - fromGx) * cellSize,
            heightWu: wallFaceWu,
            color: campStyled ? campLook.face : "#3A4658",
            faceStyle: campStyled ? campLook.faceStyle : "bricks",
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            visible: Qt.binding(() => world.fx)
        })
        dungeonObjects.push(f)
        return f
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
            collidesWith: catWall | catProjectile | catProp,
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

    // The spawn table at a danger: Balance.spawn with Balance.depth added
    // once per step of it (a share of it between two), each number within
    // its cap, and Balance.party.enemiesPerKnight for each of knights
    // (1 when left out) beyond the first
    function spawnRolls(d, knights) {
        let sb = Balance.spawn, bd = Balance.depth
        let tough = Math.min(bd.toughCap, 1 - sb.normalChance + d * bd.toughChance)
        let more = Math.floor(d * bd.enemies) + _extraKnights(knights) * Balance.party.enemiesPerKnight
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

    // An enemy's attack at a danger
    function enemyAtk(type, d) {
        return Balance.enemy[type].atk + Math.round(d * Balance.depth.atk)
    }
    // An enemy's HP in a dungeon built for knights (1 when left out):
    // Balance.party.hpPerKnight of it more for each beyond the first
    function enemyHp(type, tier, knights) {
        let hp = Balance.enemy.tierHp[tier] + Balance.enemy[type].hpBonus
        return Math.round(hp * (1 + _extraKnights(knights) * Balance.party.hpPerKnight))
    }
    function _extraKnights(knights) { return Math.max(0, (knights || 1) - 1) }

    // knights: the knights the dungeon is built for, 1 when left out
    function spawnEnemy(ex, ey, tier, type, knights) {
        // A rolled tier 0 is the weak tier, not a missing one
        tier = tier === undefined ? 1 : tier
        type = type || "grunt"
        let stats = Balance.enemy[type]
        let ehp = enemyHp(type, tier, knights)
        let eatk = enemyAtk(type, danger)
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
            collidesWith: catWall | catPlayer | catProp
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

    // A number over what was hit, healed or picked up: how hard a strike
    // landed shows in normal play. Above the darkness, readable where the
    // light does not reach
    function spawnDamageNumber(wx, wy, amount, color) {
        damageNumberComp.createObject(glowParent(), {
            objectName: "damageNumber",
            xWu: wx, yWu: wy + 0.5,
            startYWu: wy + 0.5,
            text: "" + amount,
            color: color,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
        })
    }

    // The knight's own hurt is told by its flash and the HP bar's chunk:
    // a number over it is for tuning, in debug mode only
    function spawnHurtNumber(wx, wy, amount, color) {
        if (debugMechanics) spawnDamageNumber(wx, wy, amount, color)
    }

    // A word over the struck enemy - PARRY, PERFECT - shows in normal play
    function spawnWord(wx, wy, word, color) {
        damageNumberComp.createObject(world.room, {
            objectName: "fightWord",
            xWu: wx, yWu: wy + 0.5,
            startYWu: wy + 0.5,
            text: word,
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
        // The stairs glow in the next dungeon's torch colour: in a dungeon
        // where it would stand were the party to leave now, in the village
        // where it stands
        exitStairs = exitStairsComponent.createObject(world.room, {
            xWu: wx, yWu: wy, widthWu: cellSize, heightWu: cellSize,
            glow: Qt.binding(() => Balance.danger.looks[dangerBand(world.nextPosition)].torch),
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            visible: Qt.binding(() => world.fx)
        })
        dungeonObjects.push(exitStairs)
        console.log("[Game] Exit sensor placed at grid x=", exitGridX)
    }

    function clearDungeon() {
        _attackRng = null
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
        let kept = {}
        for (let e of enemies) kept[e.objectId] = e
        _enemyById = kept

        // Gold drops go as the enemies do: the host's on every node with
        // their despawn, a joiner's when that arrives
        for (let d of goldDrops.slice()) {
            if (!d) continue
            if (d.objectId !== "" && session.connected) {
                if (session.isHost) session.despawnGold(d.objectId)
                continue
            }
            try { d.destroy() } catch(err) {}
        }
        goldDrops = goldDrops.filter(d => d && d.objectId !== "" && session.connected
                                     && _goldById[d.objectId] === d)

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
        campfire = null
        campCat = null
        campTravellers = []
        campDog = null
        campTalk = null
        campSounds.clear()
        features = []
        featureShowcase = false
        breakables = []
        _propCells = ({})
        _buildingCells = ({})
        _brokenCells = []
        plates = []
        _sprungCells = ({})
        slits = []
        _clearArrows()
        doors = []
        _doorStates = ({})
        secretRooms = []
        _secretCells = ({})
        _cacheCells = ({})
        _openedSecrets = []
        bonePiles = []
        torches = []
        stains = []
        // A blow held for the last level's enemy does not land in the next,
        // nor does a shot still flying
        _heldBlows = []
        _parriedAt = {}
        for (let id in _shotById) {
            try { if (_shotById[id] && !_shotById[id].destroyed) _shotById[id].vanish() } catch(err) {}
        }
        _shotById = {}

        grid = []
        rooms = []
        campProps = []
        campLayout = -1
        // The minimap paints what is explored of the grid, and the grid is gone
        exploredCells = []
    }

    // Alone out of a level into the next; into a dungeon the dungeon
    // master sets it first, and the exit stays taken while the panel is up
    function resetDungeon() {
        let next = levelIndex + 1
        if (levelTypeOf(next) !== "dungeon" || !_masterAsks()) {
            _enterLevel(next)
            resetting = false
            return
        }
        let d = _dangerFor(next)
        openMaster({ index: next, pos: d.pos, knights: d.knights, seed: masterSeed,
                     go: (m, pos) => {
                         _enterLevel(next, { pos: pos, next: pos, knights: d.knights, master: m })
                         resetting = false
                     } })
    }

    // --- Village/Camp generation ---
    function generateVillage() {
        if (masterSeed < 0)
            masterSeed = Math.floor(Math.random() * 2147483647)
        let levelSeed = deriveSeed(masterSeed, levelIndex)
        rng = createRng(levelSeed)
        console.log("[Game] Village - Seed:", masterSeed, "Level:", levelIndex)

        // The cave, the tavern and the smithy are cells of the grid: they
        // block the way, the light and the paths like a dungeon's rock
        initializeGrid()
        initExploredCells()
        let camp = carveCamp(levelSeed)
        let b = Balance.camp.building
        let tavern = { gx: camp.mid - b.side - b.width, gy: camp.midRow + b.raised, w: b.width, h: b.height }
        let smithy = { gx: camp.mid + b.side, gy: tavern.gy, w: b.width, h: b.height }
        _buildingCells = ({})
        _carveBuilding(tavern)
        _carveBuilding(smithy)
        for (let y = 0; y < gridHeight; y++)
            for (let x = 0; x < gridWidth; x++)
                if (grid[y][x] === cellRoom || _buildingCells[y * gridWidth + x])
                    exploredCells[y][x] = true

        // Entrance at the bottom, exit at the top: a tunnel each from the
        // edge of the map to the cave's bay
        let entranceX = camp.mid
        let exitX = entranceX
        for (let y = 0; y < gridHeight && grid[y][entranceX] === cellWall; y++) grid[y][entranceX] = cellHallway
        for (let y = gridHeight - 1; y >= 0 && grid[y][exitX] === cellWall; y--) grid[y][exitX] = cellHallway
        entranceGridX = entranceX
        exitGridX = exitX

        // Build walls and floor (cool blue palette)
        let floorObj = floorComponent.createObject(world.room, {
            xWu: 0, yWu: yWuMax, widthWu: xWuMax, heightWu: yWuMax,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            fx: Qt.binding(() => world.fx),
            style: campLook.floor.style,
            grass: campLook.floor.grass,
            moss: campLook.floor.moss,
            crackShare: campLook.floor.crackShare,
            seed: (levelIndex * 0.137) % 1
        })
        floorObj.color = campLook.floor.color
        dungeonObjects.push(floorObj)
        let built = dungeonObjects.length
        createMergedWalls()
        createBoundaryWalls()
        createWallFaces()
        createWallRims()
        _tintBuildings(built)
        _placeOverhangs(camp.seed)
        updateOccluders()
        spawnMotes()

        // The camp's centre in world units: the middle column's west edge,
        // the middle row's south edge
        let cx = camp.mid * cellSize
        let cy = camp.midRow * cellSize

        // Campfire (bottom-center of village)
        let cf = campfireComponent.createObject(world.room, {
            xWu: cx, yWu: cy - 3,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            gameWorld: world
        })
        dungeonObjects.push(cf)
        campfire = cf

        // Tavern (west of the middle), open to the south: x the middle of
        // its floor, y0 its south edge
        let tx = (tavern.gx + tavern.w / 2) * cellSize
        let ty0 = tavern.gy * cellSize
        _lightBuilding(tavern)
        // Innkeeper NPC with routine
        _spawnVillageNpc(tx, ty0 + 5, "#C9A227", "mug", "Innkeeper", [
            { x: tx, y: ty0 + 5, duration: 4, text: "*polishing mugs*" },
            { x: tx, y: ty0 + 3, duration: 3, text: "*sweeping floor*" },
            { x: tx - 1, y: ty0 + 2, duration: 2, text: "*checking supplies*" }
        ], [
            "Welcome, traveler! You look like you've seen better days.",
            "Rest by the campfire — it'll patch you right up.",
            "For the road, a potion or a mana draught. Coin first, mind.",
            "The deeper floors have nastier creatures. Be careful."
        ], "assets/innkeeper_greeting.wav", [
            { id: "potion", label: "Health potion", price: Balance.shop.potionPrice },
            { id: "draught", label: "Mana draught (+" + Balance.shop.draughtMana + " mana)",
              price: Balance.shop.draughtPrice }
        ])

        // Smithy (east of the middle), open to the south
        let sx = (smithy.gx + smithy.w / 2) * cellSize
        let sy0 = smithy.gy * cellSize
        _lightBuilding(smithy)
        // Anvil in front of the smithy
        _spawnAnvil(sx, sy0 - 1)
        let anvilAt = Qt.point(sx, sy0 - 1)
        // Blacksmith NPC with routine
        _spawnVillageNpc(sx, sy0 + 3, "#B87333", "hammer", "Blacksmith", [
            { x: sx, y: sy0 - 1, duration: 5, text: "*hammering*", sound: "anvil" },
            { x: sx, y: sy0 + 5, duration: 3, text: "*sorting tools*" },
            { x: sx - 1, y: sy0 + 3, duration: 2, text: "*inspecting blade*" }
        ], [
            "Ah, another one from the depths. Your blade's seen some work.",
            "Sword, shield, harness or blade - one piece of work per visit, and it lasts the descent.",
            "The deeper you've been, the finer I can make it. Bring gold from below."
        ], "assets/blacksmith_greeting.wav", smithLines.map(line => ({ id: line })))

        // Tree at village edge (dark green static object)
        let tree = wallComponent.createObject(world.room, {
            xWu: cx - 6, yWu: cy - 5,
            widthWu: 1.0, heightWu: 1.0,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            world: world.physics,
            categories: catWall,
            collidesWith: catPlayer,
            color: campLook.tree
        })
        tree.radius = tree.width * 0.5
        dungeonObjects.push(tree)

        // Witch — fortune teller near the tree: she reads the next dungeon
        _spawnVillageNpc(cx - 5, cy - 5, "#7B2D8E", "crystal", "Witch", [
            { x: cx - 6, y: cy - 4.5, duration: 4, text: "*gazing into crystal*" },
            { x: cx - 4, y: cy - 5, duration: 3, text: "*muttering softly*" },
            { x: cx - 5, y: cy - 5.5, duration: 2, text: "*reading the stars*" }
        ], witchReading, "assets/witch_greeting.wav")
        let spots = [Qt.point(tree.xWu, tree.yWu)]
        _placeCampProps(camp, levelSeed, spots)
        _spawnMoths(_breatheLights(levelSeed, [cf].concat(torches)), cf, torches)
        _placeCat(camp, levelSeed, cf, spots)
        _placeTravellers(camp, levelSeed, cf)
        campSounds.build(cf, dungeonObjects.find(o => o && o.objectName === "npc" && o.npcName === "Blacksmith"),
                         anvilAt, campLook, campProps)

        // Spawn player at entrance
        spawnPlayer(cx, (camp.oy + 2) * cellSize)
        session.spawnRemotePlayers(cx, (camp.oy + 2) * cellSize)

        // Block entrance + exit sensor
        blockEntrance()
        placeExitSensor()

        // Bind controls
        if (player) {
            player.moveX = Qt.binding(() => knightMoveX)
            player.moveY = Qt.binding(() => knightMoveY)
            player.mouseScreenX = Qt.binding(() => mouseInput.mouseX)
            player.mouseScreenY = Qt.binding(() => mouseInput.mouseY)
            player.playerScreenX = Qt.binding(() => playerScreenX)
            player.playerScreenY = Qt.binding(() => playerScreenY)
            gameCamera.target = player
            revealAroundPlayer()
        }

        console.log("[Game] Village generated")
    }

    // The camp's cave in the grid (issue #145): the floor of a box of
    // Balance.camp cells, its edge moved out into bays and in as outcrops
    // and its corners cut off, all from the level's own stream. Returns
    // the box (ox, oy), its middle column and row, and a seed for what is
    // drawn along the edge
    function carveCamp(levelSeed) {
        let c = Balance.camp
        let rand = createRng(levelSeed ^ c.seedSalt)
        let ox = Math.floor((gridWidth - c.width) / 2)
        let oy = gridHeight - c.exitTunnel - c.height
        let mid = Math.floor(ox + c.width / 2)
        let midRow = Math.floor(oy + c.height / 2)
        let pick = (range) => range[0] + Math.floor(rand() * (range[1] - range[0] + 1))
        // A side's edge, per cell along it: how many cells it moves in
        // from its base line (an outcrop) or, below 0, out (a bay). It
        // steps by one or two cells at a time, so it terraces rather than
        // growing fingers of rock or floor one cell wide, and leans back
        // to the base line, so no side stays in or out all along
        let side = (n) => {
            let edge = []
            let inset = pick([-c.bay, c.outcrop])
            while (edge.length < n) {
                let run = pick(c.stretch)
                for (let i = 0; i < run && edge.length < n; i++) edge.push(inset)
                let back = 0.5 + 0.2 * inset
                let step = pick([1, 2]) * (rand() < back ? -1 : 1)
                inset = Math.max(-c.bay, Math.min(c.outcrop, inset + step))
            }
            return edge
        }
        let south = side(c.width), north = side(c.width)
        let west = side(c.height), east = side(c.height)
        // The entrance and the exit open in a bay
        for (let i = -1; i <= 1; i++) {
            south[mid - ox + i] = -c.bay
            north[mid - ox + i] = -c.bay
        }
        // Cut off: south-west, south-east, north-west, north-east
        let corners = [pick(c.corner), pick(c.corner), pick(c.corner), pick(c.corner)]
        for (let y = 0; y < c.height; y++)
            for (let x = 0; x < c.width; x++) {
                let xe = c.width - 1 - x, yn = c.height - 1 - y
                if (y < c.bay + south[x] || yn < c.bay + north[x]
                    || x < c.bay + west[y] || xe < c.bay + east[y])
                    continue
                if (x + y < corners[0] || xe + y < corners[1] || x + yn < corners[2] || xe + yn < corners[3])
                    continue
                grid[oy + y][ox + x] = cellRoom
            }
        // Only what the knights can walk to from the entrance stays floor
        let reached = ({})
        let open = [[mid, oy + 2]]
        reached[(oy + 2) * gridWidth + mid] = true
        while (open.length > 0) {
            let at = open.pop()
            for (let d of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
                let nx = at[0] + d[0], ny = at[1] + d[1], k = ny * gridWidth + nx
                if (nx < 0 || ny < 0 || nx >= gridWidth || ny >= gridHeight || reached[k]
                    || grid[ny][nx] !== cellRoom) continue
                reached[k] = true
                open.push([nx, ny])
            }
        }
        for (let y = oy; y < oy + c.height; y++)
            for (let x = ox; x < ox + c.width; x++)
                if (grid[y][x] === cellRoom && !reached[y * gridWidth + x]) grid[y][x] = cellWall
        return { ox: ox, oy: oy, mid: mid, midRow: midRow, seed: rand() }
    }

    // The cells of the tavern's and the smithy's walls, (gy * gridWidth + gx)
    property var _buildingCells: ({})
    // A building of whole cells at (gx, gy), its south-west cell: walls
    // west, north and east, open to the south
    function _carveBuilding(r) {
        for (let y = r.gy; y < r.gy + r.h; y++)
            for (let x = r.gx; x < r.gx + r.w; x++) {
                if (x !== r.gx && x !== r.gx + r.w - 1 && y !== r.gy + r.h - 1) continue
                grid[y][x] = cellWall
                _buildingCells[y * gridWidth + x] = true
            }
    }
    // The walls and faces made since dungeonObjects held `from` that stand
    // on a building's cells take its timber colours
    function _tintBuildings(from) {
        let c = campLook
        for (let i = from; i < dungeonObjects.length; i++) {
            let o = dungeonObjects[i]
            let face = o.shadowWu !== undefined
            if (!face && o.categories === undefined) continue
            // A wall's yWu is its top edge, a face's the top of the face
            let gy = face ? Math.floor(o.yWu / cellSize) : Math.round(o.yWu / cellSize) - 1
            let gx = Math.round(o.xWu / cellSize)
            if (!_buildingCells[gy * gridWidth + gx]) continue
            o.color = face ? c.buildingFace : c.buildingWall
        }
    }
    // The camp's lights breathe, the campfire and the lanterns, each on its
    // own breath from the level's seed ^ Balance.camp.lightSalt (issue
    // #149). A breath is a whole share of the lights' 1000 s round of
    // time, so it never jumps when the round starts over. Returns the
    // stream, for what else hangs on the lights
    function _breatheLights(levelSeed, lights) {
        let b = Balance.camp.breath
        let rand = createRng(levelSeed ^ Balance.camp.lightSalt)
        for (let l of lights) {
            let seconds = b.seconds[0] + rand() * (b.seconds[1] - b.seconds[0])
            l.breath = b.depth
            l.breathSeconds = 1000 / Math.round(1000 / seconds)
            l.breathPhase = rand() * 2 * Math.PI
        }
        return rand
    }
    // Moths circle the campfire and the lanterns (issue #149), all of them
    // in one item; how many at each light and their colour are the look's
    Component { id: mothsComponent; Moths {} }
    function _spawnMoths(rand, fire, lanterns) {
        let m = Balance.camp.moths, look = campLook.moths
        let col = Qt.color(look.color)
        // Where the lights shine from (their Light2d offsets): the middle
        // of the fire's body, half a wu in front of a lantern's wall
        let lights = [{ x: fire.xWu + fire.widthWu / 2, y: fire.yWu - fire.heightWu / 2,
                        orbit: m.fire.orbit, count: look.fire }]
        for (let t of lanterns)
            lights.push({ x: t.xWu, y: t.yWu - 0.5, orbit: m.lantern.orbit, count: look.lantern })
        dungeonObjects.push(mothsComponent.createObject(glowParent(), {
            mothLights: lights,
            seed: Math.floor(rand() * 1000),
            color: Qt.rgba(col.r, col.g, col.b, look.alpha),
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
            visible: Qt.binding(() => world.fx)
        }))
    }
    // The cave cat (issue #150): in Balance.camp.cat.share of the camps,
    // curled on a ring round the campfire, out of the warmth where the
    // knights sit, on the floor and clear of the way to the stairs, the
    // people's spots (the routines' and the tree, as _placeCampProps
    // leaves them) and the props. Its own stream, the level's seed ^
    // Balance.camp.catSalt, so every screen of a session sees the same cat
    // or none. campCat is it, or null
    Component { id: caveCatComponent; CaveCat {} }
    property var campCat: null
    function _placeCat(camp, levelSeed, fire, spots) {
        let c = Balance.camp, n = c.cat
        let rand = createRng(levelSeed ^ c.catSalt)
        campCat = null
        if (rand() >= n.share) return
        let r = n.ring[0] + rand() * (n.ring[1] - n.ring[0])
        let start = rand() * 2 * Math.PI
        let fx = fire.xWu + fire.widthWu / 2, fy = fire.yWu - fire.heightWu / 2
        let cx = camp.mid * cellSize, half = n.size / 2
        let fits = []
        for (let i = 0; i < n.angles; i++) {
            let a = start + i * 2 * Math.PI / n.angles
            let x = fx + r * Math.cos(a), y = fy + r * Math.sin(a)
            if (x + half > cx - c.clearOfPath && x - half < cx + c.clearOfPath) continue
            if (spots.some(s => Math.hypot(s.x - x, s.y - y) < c.clearOfPeople)) continue
            if (campProps.some(p => Math.hypot(Math.max(0, Math.abs(p.x - x) - p.w / 2),
                                               Math.max(0, Math.abs(p.y - y) - p.h / 2)) < half + n.clearOfProps)) continue
            let floor = true
            for (let gy = Math.floor((y - half) / cellSize); gy <= Math.floor((y + half) / cellSize); gy++)
                for (let gx = Math.floor((x - half) / cellSize); gx <= Math.floor((x + half) / cellSize); gx++)
                    if (!grid[gy] || grid[gy][gx] !== cellRoom || _buildingCells[gy * gridWidth + gx]) floor = false
            if (floor) fits.push(Qt.point(x, y))
        }
        let at = fits[Math.floor(rand() * fits.length)]
        let seed = rand()
        if (!at) return
        campCat = caveCatComponent.createObject(world.room, {
            xWu: at.x, yWu: at.y, seed: seed,
            gameWorld: world,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
        })
        dungeonObjects.push(campCat)
    }
    // Travellers rest at the camp (issue #151): Balance.camp.travellers
    // other adventurers, each sitting at the fire and wandering to one of
    // the look's props and back, two now and then exchanging a pair of
    // lines, one of them followed by a dog. All of it - who comes, where
    // each sits and wanders, what each says - draws from its own stream,
    // the level's seed ^ Balance.camp.travellerSalt, so every screen of a
    // session sees the same. A traveller is an Npc named "traveller", not
    // "npc": the benches that look for the innkeeper, the smith and the
    // witch never find one. It sells nothing, and the knights walk
    // through it
    Component { id: travellerComponent; Npc { objectName: "traveller"; solid: false } }
    Component { id: campDogComponent; CampDog {} }
    Component { id: campTalkComponent; CampTalk {} }
    property var campTravellers: []
    property var campDog: null
    property var campTalk: null
    function _placeTravellers(camp, levelSeed, fire) {
        let c = Balance.camp, n = c.travellers
        let rand = createRng(levelSeed ^ c.travellerSalt)
        campTravellers = []
        campDog = null
        campTalk = null
        let pick = (range) => range[0] + rand() * (range[1] - range[0])
        let half = 0.4
        let onFloor = (x, y) => {
            for (let gy = Math.floor((y - half) / cellSize); gy <= Math.floor((y + half) / cellSize); gy++)
                for (let gx = Math.floor((x - half) / cellSize); gx <= Math.floor((x + half) / cellSize); gx++)
                    if (!grid[gy] || grid[gy][gx] !== cellRoom || _buildingCells[gy * gridWidth + gx]) return false
            return true
        }
        let count = n.count[0] + Math.floor(rand() * (n.count[1] - n.count[0] + 1))
        // The seats: on a ring round the fire, on the floor, off the cat
        let fx = fire.xWu + fire.widthWu / 2, fy = fire.yWu - fire.heightWu / 2
        let r = pick(n.ring), start = rand() * 2 * Math.PI
        let seats = []
        for (let i = 0; i < n.angles; i++) {
            let a = start + i * 2 * Math.PI / n.angles
            let x = fx + r * Math.cos(a), y = fy + r * Math.sin(a)
            if (!onFloor(x, y)) continue
            if (campCat && Math.hypot(campCat.xWu - x, campCat.yWu - y) < campCat.sizeWu / 2 + half + 0.3) continue
            seats.push(Qt.point(x, y))
        }
        // The props they wander to, by the look
        let goals = n.props[campLook.name] || []
        let wanders = campProps.filter(p => goals.some(g => g.kind === p.kind))
        let cx = camp.mid * cellSize, cy = camp.midRow * cellSize
        let kinds = n.kinds.slice()
        let spread = Math.max(1, Math.floor(seats.length / count))
        for (let i = 0; i < count && i < seats.length; i++) {
            let kind = kinds.splice(Math.floor(rand() * kinds.length), 1)[0]
            let seat = seats[i * spread]
            // Its walk: off the prop's edge toward the camp's middle, a
            // little aside so two do not stand in one place
            let spot = null, text = n.seatText
            let p = wanders.length > 0 ? wanders[Math.floor(rand() * wanders.length)] : null
            let aside = (rand() - 0.5) * 2
            if (p) {
                let dx = cx - p.x, dy = cy - p.y, d = Math.hypot(dx, dy) || 1
                let ux = dx / d, uy = dy / d
                let t = Math.min(Math.abs(ux) > 1e-6 ? (p.w / 2 + n.off) / Math.abs(ux) : Infinity,
                                 Math.abs(uy) > 1e-6 ? (p.h / 2 + n.off) / Math.abs(uy) : Infinity)
                let x = p.x + ux * t - uy * aside, y = p.y + uy * t + ux * aside
                if (onFloor(x, y)) {
                    spot = Qt.point(x, y)
                    text = goals.find(g => g.kind === p.kind).text
                }
            }
            if (!spot) spot = seats[(i * spread + Math.floor(seats.length / 2)) % seats.length]
            let rest = pick(n.rest), wander = pick(n.wander)
            let heard = n.hearsay.slice(), lines = []
            for (let k = 0; k < n.hearsayLines && heard.length > 0; k++)
                lines.push(heard.splice(Math.floor(rand() * heard.length), 1)[0])
            // An Npc's xWu, yWu is its top-left corner; seats are centres
            let at = (q) => ({ x: q.x - half, y: q.y + half })
            let t = travellerComponent.createObject(world.room, {
                xWu: at(seat).x, yWu: at(seat).y,
                pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
                world: world.physics,
                gameWorld: world,
                interactionCategories: catWall,
                interactionCollidesWith: catPlayer,
                npcColor: kind.color,
                iconType: kind.icon,
                shape: kind.shape,
                npcName: kind.name,
                walkSpeed: n.walk,
                routine: [ Object.assign(at(seat), { duration: rest, text: n.seatText }),
                           Object.assign(at(spot), { duration: wander, text: text }) ],
                dialogueLines: lines
            })
            dungeonObjects.push(t)
            campTravellers.push(t)
        }
        if (campTravellers.length === 0) return
        // The dog, beside the traveller it follows
        let leader = campTravellers[Math.floor(rand() * campTravellers.length)]
        let dogSeed = rand()
        campDog = campDogComponent.createObject(world.room, {
            leader: leader, seed: dogSeed,
            xWu: leader.xWu + half + (dogSeed < 0.5 ? 1 : -1) * n.dog.follow, yWu: leader.yWu - half - 0.25,
            gameWorld: world,
            pixelPerUnit: Qt.binding(() => world.pixelPerUnit)
        })
        dungeonObjects.push(campDog)
        // The talk: every exchange once in an order of the stream, each
        // between two of them
        let order = n.exchanges.map((e, i) => i)
        let plan = [], waits = []
        while (order.length > 0) {
            let e = n.exchanges[order.splice(Math.floor(rand() * order.length), 1)[0]]
            let a = Math.floor(rand() * campTravellers.length)
            let b = campTravellers.length > 1
                ? (a + 1 + Math.floor(rand() * (campTravellers.length - 1))) % campTravellers.length : a
            plan.push({ a: a, b: b, lines: e })
            waits.push(pick(n.every))
        }
        campTalk = campTalkComponent.createObject(world.room, {
            travellers: campTravellers, plan: plan, first: pick(n.first), waits: waits
        })
        dungeonObjects.push(campTalk)
    }
    // Lanterns flanking a building's open front
    function _lightBuilding(r) {
        let y0 = r.gy * cellSize + 0.35
        placeTorch((r.gx + 0.5) * cellSize, y0, campLook.lantern)
        placeTorch((r.gx + r.w - 0.5) * cellSize, y0, campLook.lantern)
    }
    // The rock overhanging the cave's north-facing edges, one piece per
    // run of face, as the faces are; the buildings have none
    Component { id: overhangComponent; CaveOverhang {} }
    function _placeOverhangs(seed) {
        let o = Balance.camp.overhang
        let isEdge = (gx, gy) => grid[gy][gx] === cellWall && grid[gy - 1][gx] !== cellWall
                                 && !_buildingCells[gy * gridWidth + gx]
        for (let gy = 1; gy < gridHeight; gy++) {
            let gx = 0
            while (gx < gridWidth) {
                if (!isEdge(gx, gy)) { gx++; continue }
                let startX = gx
                while (gx < gridWidth && isEdge(gx, gy)) gx++
                dungeonObjects.push(overhangComponent.createObject(world.room, {
                    xWu: startX * cellSize, yWu: gy * cellSize + wallFaceWu,
                    widthWu: (gx - startX) * cellSize, faceWu: wallFaceWu,
                    lipWu: o.lip, stalactiteWu: o.stalactite, toothWu: o.tooth, shadowWu: o.shadow,
                    seed: seed * 1000,
                    baseColor: campLook.rock,
                    pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
                    visible: Qt.binding(() => world.fx)
                }))
            }
        }
    }

    // The camp's props (issue #146): one of its look's layouts, picked
    // from the level's own stream (seed ^ Balance.camp.propSalt), so every
    // screen of a session lays out the same. A prop is left out unless it
    // lies whole on the cave's floor - in its place, else moved in or to
    // the camp's other side onto no other prop - clear of the way to the stairs, the
    // campfire, the buildings' fronts, and the people and where they walk
    // and the spots (points in wu) given. campProps holds what was laid:
    // { kind, x, y, w, h } in world units, the prop's centre
    Component { id: campPropComponent; CampProp {} }
    property var campProps: []
    property var campLayout: -1
    property real campClock: 0
    NumberAnimation on campClock {
        from: 0; to: 3600; duration: 3600000
        loops: Animation.Infinite
        running: campStyled && world.fx
    }
    function _placeCampProps(camp, levelSeed, spots) {
        let c = Balance.camp, look = campLook
        // The innkeeper, the smith and the witch, and every spot of their
        // routines
        for (let o of dungeonObjects)
            if (o && o.objectName === "npc") {
                spots.push(Qt.point(o.xWu, o.yWu))
                for (let r of o.routine) spots.push(Qt.point(r.x, r.y))
            }
        let rand = createRng(levelSeed ^ c.propSalt)
        campLayout = Math.floor(rand() * look.layouts.length)
        campProps = []
        let cx = camp.mid * cellSize, cy = camp.midRow * cellSize
        let fire = dungeonObjects.find(o => o && o.healRadius !== undefined)
        let b = c.building
        let fronts = [camp.mid - b.side - b.width, camp.mid + b.side].map(gx => ({
            x0: gx * cellSize, x1: (gx + b.width) * cellSize,
            y: (camp.midRow + b.raised) * cellSize }))
        for (let p of look.layouts[campLayout]) {
            let seed = rand()
            // Where the cave's edge cuts its place, the prop steps in
            // toward the middle, wu by wu up to c.propShift, then tries the
            // same on the other side of the camp; moved, it lands on no
            // other prop
            let tries = []
            for (let side of [1, -1])
                for (let k = 0; k <= c.propShift; k++) tries.push(side * (p.x - Math.sign(p.x) * k))
            let px = tries.find(x => _propFits(cx + x - p.w / 2, cy + p.y - p.h / 2, cx + x + p.w / 2,
                                               cy + p.y + p.h / 2, cx, fire, fronts, spots)
                                     && (x === p.x || !campProps.some(q => Math.abs(q.x - cx - x) < (q.w + p.w) / 2
                                                                      && Math.abs(q.y - cy - p.y) < (q.h + p.h) / 2)))
            if (px === undefined) continue
            let x0 = cx + px - p.w / 2, y1 = cy + p.y + p.h / 2
            let glows = ["mushrooms", "cracks", "coals"].indexOf(p.kind) >= 0
            let o = campPropComponent.createObject(glows ? glowParent() : world.room, {
                xWu: x0, yWu: y1, widthWu: p.w, heightWu: p.h,
                propKind: p.kind, seed: seed,
                time: Qt.binding(() => campClock),
                pixelPerUnit: Qt.binding(() => world.pixelPerUnit),
                visible: Qt.binding(() => world.fx)
            })
            dungeonObjects.push(o)
            campProps.push({ kind: p.kind, x: cx + px, y: cy + p.y, w: p.w, h: p.h })
        }
    }
    function _propFits(x0, y0, x1, y1, cx, fire, fronts, spots) {
        let c = Balance.camp
        // How far the rectangle is from a point
        let off = (px, py) => Math.hypot(px - Math.max(x0, Math.min(px, x1)), py - Math.max(y0, Math.min(py, y1)))
        if (x1 > cx - c.clearOfPath && x0 < cx + c.clearOfPath) return false
        if (off(fire.xWu, fire.yWu) < c.clearOfFire) return false
        for (let f of fronts)
            if (x1 > f.x0 && x0 < f.x1 && y1 > f.y - c.clearOfFront && y0 < f.y) return false
        for (let s of spots)
            if (off(s.x, s.y) < c.clearOfPeople) return false
        for (let gy = Math.floor(y0 / cellSize); gy <= Math.floor((y1 - 0.001) / cellSize); gy++)
            for (let gx = Math.floor(x0 / cellSize); gx <= Math.floor((x1 - 0.001) / cellSize); gx++)
                if (!grid[gy] || grid[gy][gx] !== cellRoom || _buildingCells[gy * gridWidth + gx]) return false
        return true
    }

    // dialogue: its lines, or a function making them when it is talked to
    function _spawnVillageNpc(wx, wy, color, iconType, name, routine, dialogue, greeting, wares) {
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
            dialogueLines: typeof dialogue === "function" ? [] : dialogue || [],
            speak: typeof dialogue === "function" ? dialogue : null,
            greetingSound: greeting || "",
            wares: wares || []
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
            player.moveX = Qt.binding(() => knightMoveX)
            player.moveY = Qt.binding(() => knightMoveY)
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
    // "features" is the dungeon with every feature kind at its showcase
    // count (Balance.dungeon), to try a kind right after a reload
    function scenarios() { return ["dungeon", "village", "fight", "features"] }
    // atDanger (0 when left out) is the danger the dungeon, the village or
    // the fight room is at: its depth and, after the point, its position
    // in the depth's range, e.g. applyScenario("dungeon", 4.8) through eval
    // for a dungeon high in depth 4's range. A whole number is the bottom.
    // seed (scenarioSeed when left out) is the run's seed it is built on
    function applyScenario(name, atDanger, seed) {
        let dg = Math.max(0, Number(atDanger) || 0)
        let d = Math.floor(dg)
        _setDanger(Math.min(Balance.danger.top, dg - d), dg - d)
        _setKnights(knightsNow())
        muted = true
        masterSeed = seed === undefined ? scenarioSeed : seed
        if (player) clearDungeon()
        master = null
        featureShowcase = name === "features"
        fallen = false
        fightRoomActive = false
        // Generate before leaving the title: with a player in place,
        // _tryStartGame() does not build a second level on top.
        let type = name === "village" ? "village" : "dungeon"
        // Landing at a depth is no descent past the record: no banner
        recordPassed = true
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

    // The level's attack rolls - whether a tough enemy winds up a crushing
    // blow - from the run's seed and the level, so a seed plays the same
    // fight; only where the AI runs. Seeded anew with each level
    property var _attackRng: null
    function rollAttack() {
        if (!_attackRng) _attackRng = createRng(levelSeedNow() ^ 0x6372)
        return _attackRng()
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
        if (doors.length > 0 && _shutBetween(x1Wu, y1Wu, x2Wu, y2Wu)) return false
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

    // --- Paths on the grid: Clayground's GridPathfinder (issue #127) ---
    // The pathfinder holds the grid's walls and the breakables still
    // standing as blocked. It is fed the grid turned half a turn: its
    // neighbour order is then the one of the game's own A* it replaced, so
    // a seed takes the same paths and the fight bench the same numbers
    GridPathfinder { id: pathfinder }
    // The grid the pathfinder was filled from; another one fills it anew
    property var _pathGrid: null
    function _pathCell(gx, gy) {
        return { x: gridWidth - 1 - gx, y: gridHeight - 1 - gy }
    }
    function _syncPathfinder() {
        if (_pathGrid === grid) return
        let data = new Array(gridWidth * gridHeight)
        for (let gy = 0; gy < gridHeight; gy++)
            for (let gx = 0; gx < gridWidth; gx++) {
                let c = _pathCell(gx, gy)
                data[c.y * gridWidth + c.x] = grid[gy][gx] === cellWall
                    || _propCells[gy * gridWidth + gx] ? 1 : 0
            }
        pathfinder.columns = gridWidth
        pathfinder.rows = gridHeight
        pathfinder.walkableData = data
        _pathGrid = grid
    }
    // Whether the pathfinder takes cell (gx, gy) as walkable, once filled
    function _setPathCell(gx, gy, walkable) {
        if (_pathGrid !== grid) return
        let c = _pathCell(gx, gy)
        pathfinder.setWalkable(c.x, c.y, walkable)
    }
    function _blockedCell(gx, gy) {
        return grid[gy][gx] === cellWall || _propCells[gy * gridWidth + gx] === true
    }
    // The cells from (sx, sy) to (ex, ey), [{x, y}] in grid cells; a
    // breakable on either end is no obstacle. shut: the closed doors
    // between are, as rock
    function _cellPath(sx, sy, ex, ey, shut) {
        _syncPathfinder()
        let ends = [[sx, sy], [ex, ey]].filter(c => _blockedCell(c[0], c[1]))
        for (let c of ends) _setPathCell(c[0], c[1], true)
        let closed = (shut ? doors.filter(d => d.shut) : []).map(d => d.cell.split(",").map(Number))
                         .filter(c => !(c[0] === sx && c[1] === sy) && !(c[0] === ex && c[1] === ey))
        for (let c of closed) _setPathCell(c[0], c[1], false)
        let a = _pathCell(sx, sy), b = _pathCell(ex, ey)
        let path = pathfinder.findPath(a.x, a.y, b.x, b.y)
        for (let c of ends) _setPathCell(c[0], c[1], false)
        for (let c of closed) _setPathCell(c[0], c[1], true)
        return path.map(c => ({ x: gridWidth - 1 - c.x, y: gridHeight - 1 - c.y }))
    }
    // The cells from (sx, sy) to (ex, ey) with a closed door as
    // doorPathCost cells more. GridPathfinder knows walkable or not, no
    // cost (clayground#423): the way through the closed doors is taken
    // unless the way around them is no longer than it and their cost
    function _costPath(sx, sy, ex, ey) {
        let path = _cellPath(sx, sy, ex, ey, false)
        let shut = path.filter(c => doorShut(c.x + "," + c.y)).length
        if (shut === 0) return path
        let around = _cellPath(sx, sy, ex, ey, true)
        return around.length > 0 && around.length <= path.length + shut * Balance.dungeon.doorPathCost
            ? around : path
    }
    // The way from one point to another in wu, cell centres as waypoints;
    // [] when there is none
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
        return _costPath(s.x, s.y, e.x, e.y).map(c => Qt.point(c.x * cellSize + cellSize / 2,
                                                             c.y * cellSize + cellSize / 2))
    }

    // --- Screen Overlays ---

    // Esc menu (over the dungeon, under the fallen screen)
    Loader {
        anchors.fill: parent
        z: 4400
        active: menuOpen && screen === "game" && !fallen
        sourceComponent: Component {
            PauseMenu {
                inSession: session.connected
                musicVolume: world.musicVolume
                soundVolume: world.soundVolume
                onVolumeSet: (which, value) => world.setVolume(which, value)
                onResume: world.closeMenu()
                onToTitle: world.backToTitle()
            }
        }
    }

    // Fallen screen (over the dungeon, under the title)
    Loader {
        anchors.fill: parent
        z: 4500
        active: fallen && screen === "game"
        sourceComponent: Component {
            FallenScreen {
                depth: world.depth
                kills: world.runKills
                secrets: world.runSecrets
                seconds: world.runSeconds
                recordLine: world.recordLine
                newRecord: world.recordPassed
                runs: world.sessionRuns
                canGoAgain: !session.connected || (world.partyFallen && session.isHost)
                waitsForHost: session.connected && world.partyFallen && !session.isHost
                partyFights: session.connected && !world.partyFallen
                partyFallen: world.partyFallen
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
                musicVolume: world.musicVolume
                soundVolume: world.soundVolume
                message: world.titleMessage
                recordLine: world.recordLine
                dungeonMaster: world.dungeonMaster
                onDungeonMasterToggled: world.setDungeonMaster(!world.dungeonMaster)
                onSinglePlayerSelected: screen = "game"
                onMultiplayerSelected: screen = "lobby"
            }
        }
    }

    // A joiner while the host's dungeon master panel is up, in the lobby,
    // the village or on the fallen screen: the next dungeon is coming
    Rectangle {
        objectName: "masterWaitNote"
        z: 5650
        visible: session.mastering && !session.isHost
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 24
        width: waitText.implicitWidth + 32
        height: waitText.implicitHeight + 16
        radius: 6
        color: "#CC08070C"
        border.color: "#E0B060"
        border.width: 1
        Text {
            id: waitText
            anchors.centerIn: parent
            text: "The dungeon master prepares the next dungeon\u2026"
            color: "#E0B060"
            font.pixelSize: 16
            font.italic: true
        }
    }

    // The dungeon master's panel (over the lobby and the fallen screen)
    Loader {
        anchors.fill: parent
        z: 5600
        active: world.masterOpen
        sourceComponent: Component {
            DungeonMasterPanel {
                depth: world.masterAsk ? world.depthOf(world.masterAsk.index) : 0
                rows: world.masterAsk ? world.masterRows() : []
                preview: world.masterPreview
                note: world.masterNote
                settingsJson: world.masterSettingsJson()
                cellWall: world.cellWall
                cellSize: world.cellSize
                onTurned: (key, steps) => world.masterTurn(key, steps)
                onUnset: (key) => world.masterUnset(key)
                onGenerate: world.masterGenerate()
                onGo: world.masterGo()
                onCopied: world.masterNote = "Settings copied"
                onPasted: (text) => world.masterPaste(text)
            }
        }
    }
}
