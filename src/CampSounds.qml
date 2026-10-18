import QtQuick
import Clayground.Sound

// The camp's near sounds and its rest (issue #147, Balance.camp.sounds).
// Each sound sits at its source - the campfire's crackle, the anvil while
// the smith hammers, the look's own at its props - and this screen's
// knight hears it fading with its distance; there is no left or right.
// When every knight in the camp has stood still restQuiet seconds the
// camp rests: the music steps down (musicShare) and the near sounds come
// forward (nearShare), both back once a knight moves. Everything counts
// physics steps, so a pause holds it and a bench can step it. M mutes it
// with the game.
Item {
    id: campSounds

    property var game: null
    // The game's Session: its remotePlayers are the other knights
    property var party: null
    readonly property var cfg: Balance.camp.sounds

    // The sounds placed by build(): { name, sound, x, y, volume, reach,
    // every, pitch, when, next }; when, if set, says whether it plays now
    property var sources: []
    readonly property bool active: !!game && game.campStyled && sources.length > 0

    // How long the camp has rested, in seconds of the last knight to sit
    // standing still; 0 while a knight is up
    property real restFor: 0
    readonly property bool quiet: restFor >= Balance.camp.restQuiet - 1e-6
    // The music's share of its level and the near sounds' share of their
    // volume, gliding toward the rest's or back
    property real musicShare: 1
    property real nearShare: 1
    // Per sound name: how often it played and its last gain, for benches
    property var played: ({})
    property var lastGain: ({})

    Sound {
        id: crackle
        source: "../sound/sfx/" + cfg.fire.sample
        volume: game && !game.muted ? game.soundVolume : 0
    }
    Sound {
        id: anvil
        source: "../sound/sfx/" + cfg.anvil.sample
        volume: game && !game.muted ? game.soundVolume : 0
    }
    Sound {
        id: drip
        source: "../sound/sfx/" + cfg.looks.grotto.sample
        volume: game && !game.muted ? game.soundVolume : 0
    }
    Sound {
        id: creak
        source: "../sound/sfx/" + cfg.looks.hall.sample
        volume: game && !game.muted ? game.soundVolume : 0
    }
    Sound {
        id: hiss
        source: "../sound/sfx/" + cfg.looks.ember.sample
        volume: game && !game.muted ? game.soundVolume : 0
    }
    readonly property var _byLook: ({ grotto: drip, hall: creak, ember: hiss })

    // The camp's sounds, after generateVillage laid it out: the fire, the
    // anvil while the smith stands at it doing "anvil", and the look's
    // own at each of its props
    function build(fire, smith, anvilAt, look, props) {
        let list = []
        let add = (name, sound, c, x, y, when) => list.push({
            name: name, sound: sound, x: x, y: y, volume: c.volume, reach: c.reach,
            every: c.every, pitch: c.pitch, when: when || null, next: _wait(c.every) })
        if (fire) add("crackle", crackle, cfg.fire, fire.xWu, fire.yWu)
        if (smith && anvilAt)
            add("anvil", anvil, cfg.anvil, anvilAt.x, anvilAt.y,
                () => !!smith.doing && smith.doing.sound === "anvil")
        let own = cfg.looks[look.name]
        if (own)
            for (let p of props)
                if (own.props.indexOf(p.kind) >= 0) add(look.name, _byLook[look.name], own, p.x, p.y)
        sources = list
        played = ({})
        lastGain = ({})
    }
    function clear() { sources = [] }

    // How loud a sound with reach is at x, y for this screen's knight, before
    // its volume and the rest
    function falloff(reach, x, y) {
        let p = game ? game.player : null
        if (!p) return 0
        let k = Math.max(0, 1 - Math.hypot(x - p.xWu, y - p.yWu) / reach)
        return k * k
    }
    // The gain the loudest source of name plays at now, 0 if none is heard
    function gainOf(name) {
        let g = 0
        for (let s of sources)
            if (s.name === name) g = Math.max(g, _gain(s))
        return g
    }
    function _gain(s) { return Math.min(1, s.volume * nearShare * falloff(s.reach, s.x, s.y)) }
    function _wait(every) { return every[0] + Math.random() * (every[1] - every[0]) }

    // Every knight in the camp is seated: this screen's and every other
    // player's
    function allSeated() {
        if (!game || !game.player || !game.player.seated) return false
        let others = party ? party.remotePlayers : {}
        for (let id in others)
            if (others[id] && !others[id].seated) return false
        return true
    }

    function step(dt) {
        let resting = active && allSeated()
        // The last knight sat after sitAfter seconds standing still
        restFor = resting ? Math.max(restFor + dt, Balance.camp.sitAfter) : 0
        // A share moves the whole way between 1 and the rest's in fadeDown
        // seconds, or back in fadeUp
        let seconds = quiet ? cfg.fadeDown : cfg.fadeUp
        let toward = (v, rest) => {
            let to = quiet ? rest : 1, by = dt * Math.abs(rest - 1) / seconds
            return to > v ? Math.min(to, v + by) : Math.max(to, v - by)
        }
        musicShare = toward(musicShare, cfg.restMusic)
        nearShare = toward(nearShare, cfg.restNear)
        if (!active) return
        for (let s of sources) {
            s.next -= dt
            if (s.next > 0) continue
            s.next = _wait(s.every)
            if (s.when && !s.when()) continue
            let g = _gain(s)
            if (g <= 0) continue
            let pitch = s.pitch[0] + Math.floor(Math.random() * (s.pitch[1] - s.pitch[0] + 1))
            s.sound.triggerNote(s.sound.rootNote + pitch, g)
            played[s.name] = (played[s.name] || 0) + 1
            lastGain[s.name] = g
        }
    }

    Connections {
        target: game ? game.physics : null
        function onStepped() { campSounds.step(game.physics.timeStep) }
    }
    // This screen's knight standing up ends the rest in the step it stands,
    // whichever of the two steps first
    Connections {
        target: game ? game.player : null
        function onSeatedChanged() { if (!game.player.seated) campSounds.restFor = 0 }
    }
}
