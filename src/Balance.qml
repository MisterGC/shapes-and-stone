pragma Singleton
import QtQuick

// Every fight number in one place: tuning the fight is an edit of this file.
// Distances in world units (wu), speeds in wu per second, times in seconds,
// angles in degrees from the facing direction. In the inspector,
// `eval JSON.stringify(Balance)` returns the whole table.
QtObject {

    // Damage taken is (attack - defense), never below this
    readonly property int minDamage: 1

    readonly property var knight: ({
        hp: 120,
        atk: 15,
        def: 5,
        mana: 40,
        moveSpeed: 7.5,
        // Melee: a swing hits in range and within the arc, each enemy once
        attackRange: 2.0,
        attackArc: 60,
        // Radius of the circle that finds melee candidates, in knight widths
        attackSensor: 1.5,
        swingDuration: 0.25,
        // The arc fades this long after the swing; the swing hits until
        // the fade is over
        swingFade: 0.1,
        attackCooldown: 0.5,
        // Damage of a swing, as a multiple of atk
        blockingSwing: 0.85,
        dashingSwing: 1.5,
        parrySwing: 2,
        // Shield: blocks hits from within the arc, lets this share through
        shieldArc: 60,
        blockedShare: 0.3,
        blockSpeed: 0.4,    // share of move and dash speed while blocking
        // Mana pays for what the knight does: a raised shield drains
        // blockDrain per second, a blow it stops costs blockMana, a dash
        // dashMana and a whirlwind whirlMana, its dash included. At 0 the
        // shield drops and does not rise again until a parry or the rest
        // below gives some back. Without the mana a dash does not start and
        // a whirlwind is a heavy swing; the knight shows noManaWord in
        // noManaColor, clicks empty and flashes the mana bar
        blockDrain: 1,
        blockMana: 6,
        dashMana: 8,
        whirlMana: 20,
        noManaWord: "NO MANA",
        noManaColor: "#C080FF",
        parryMana: 10,
        // With the shield down and no mana spent for manaRegenDelay
        // seconds, mana comes back at manaRegen per second: resting gives
        // the block back
        manaRegen: 4,
        manaRegenDelay: 1.5,
        // Perfect block: a shield raised at most this many physics steps
        // before a blow takes it whole - no damage, this much mana back,
        // and a lunging attacker staggers for this many seconds. Only a
        // shield that was down at least perfectBlockRearm steps before it
        // rose counts: one flicked up and down does not keep the window open
        perfectBlockFrames: 8,
        perfectBlockRearm: 12,
        perfectBlockMana: 5,
        perfectBlockStagger: 0.6,
        // Charged heavy swing: the left button released before chargeStart
        // swings at once. Held longer, the knight charges, moving at
        // chargeSpeed of its move speed; at chargeTime the charge is full
        // and a release swings a heavy blow: heavySwing times atk, within
        // heavyArc and heavyRange times attackRange, through a guardian's
        // shield (it staggers), knocking back heavyKnockback times as far.
        // Released before full, a normal swing. Held chargeHold past full,
        // the knight lets it go at normal strength. A hit cancels it
        chargeStart: 0.2,
        chargeTime: 0.6,
        chargeHold: 1.0,
        chargeSpeed: 0.7,
        heavySwing: 2.5,
        heavyArc: 90,
        heavyRange: 1.25,
        heavyKnockback: 2,
        // Whirlwind: Q with full momentum (Balance.momentum) spins the
        // knight forward, whirlSpeed for whirlDuration seconds along its
        // way or facing, no damage taken, and hits every standing enemy
        // within whirlReach of it, centre to centre, once, for whirlSwing
        // times atk, through a guardian's shield. A dash cancels a charge
        whirlDuration: 0.35,
        whirlSpeed: 22.0,
        whirlReach: 1.6,
        whirlSwing: 2,
        // After a hit the shield did not stop, no damage taken for this long
        hurtGrace: 0.5,
        // A landed hit, or a crushing blow through the held shield, throws
        // the knight knockback wu back along the blow, fading out over
        // knockbackDuration seconds; a wall stops it
        knockback: 1.3,
        knockbackDuration: 0.15,
        // Dash: no damage taken while it lasts
        dashSpeed: 40.0,
        dashDuration: 0.15,
        dashCooldown: 0.8,
        // A blocking dash pushes enemies away at this speed
        pushSpeed: 20.0
    })

    // A blow the knight's shield stops reads as a success, not a smaller
    // hit. The shield arc flashes white for flash seconds and swells to
    // bump times its size; the knight's own screen freezes for freeze
    // seconds, takes this much trauma and a kick of kick wu; sparks fly;
    // the shield's clang plays pitch semitones up; the attacker recoils
    // recoil wu off the shield
    readonly property var block: ({
        flash: 0.14,
        bump: 1.25,
        freeze: 0.045,
        trauma: 0.2,
        kick: 0.1,
        sparks: 12,
        pitch: 0,
        recoil: 0.3
    })

    // A perfect block (knight.perfectBlockFrames) reads as more than a
    // block: the shield flashes for flash seconds and swells to bump times
    // its size, the knight glows pale blue for glow seconds; sparks fly
    // around a ring; the knight's own screen freezes for freeze seconds at
    // freezeScale of its speed, takes this much trauma, flashes
    // flashColor for screenFlash seconds at screenFlashOpacity and pulses
    // by pulse over pulseTime seconds; the shield's clang plays pitch
    // semitones up, brighter
    readonly property var perfectBlock: ({
        flash: 0.26,
        bump: 1.5,
        glow: 0.22,
        sparks: 18,
        freeze: 0.09,
        freezeScale: 0.1,
        trauma: 0.28,
        flashColor: "#DDF4FF",
        screenFlash: 0.07,
        screenFlashOpacity: 0.22,
        pulse: 0.5,
        pulseTime: 0.22,
        pitch: 5
    })

    // The charged heavy swing (knight.charge...) reads as a commitment: the
    // blade glows from the knight's blade colour to glow as it charges;
    // when full a ring of ringColor flashes out to ringScale times the
    // knight's size over ring seconds with a tick pitch semitones up. The
    // heavy swing plays the swing sample swingPitch semitones; its hit
    // throws sparks and a ring, and the knight's own screen freezes for
    // freeze seconds with this much trauma and a kick of kick wu
    readonly property var heavy: ({
        glow: "#FFF2C0",
        ringColor: "#FFFFFF",
        ring: 0.2,
        ringScale: 2.2,
        tickPitch: 12,
        swingPitch: -5,
        sparks: 16,
        freeze: 0.09,
        trauma: 0.35,
        kick: 0.2
    })

    // The whirlwind (knight.whirl...) reads as a blade tornado: the blade
    // spins turns times round the knight in glow over the whirl, its
    // smear covering up to smear degrees; as it starts a ring of glow
    // flashes and sparks fly along the dash, and the knight's own screen
    // takes this much trauma and a kick of kick wu. It plays the swing
    // sample swingPitch semitones, and the knight shouts, shoutPitch
    // semitones, at shoutVolume;
    // each enemy it hits takes a heavy hit's impact
    readonly property var whirl: ({
        glow: "#FFF2C0",
        turns: 2,
        smear: 270,
        sparks: 14,
        trauma: 0.3,
        kick: 0.25,
        swingPitch: -8,
        shoutPitch: -3,
        shoutVolume: 0.9
    })

    // A hit that lands reads as a hurt, not as the grace after it: the
    // knight turns color for flash seconds before the white flicker, and
    // the HP it lost stays on the HP bar as a pale chunk that drains away
    // over chunkDrain seconds
    readonly property var hurt: ({
        color: "#FF5040",
        flash: 0.06,
        chunkDrain: 0.4
    })

    // The shield shows how much mana is left. Below lowShare of the
    // knight's mana its arc thins and blinks blink times a second; at 0 it
    // breaks into shards grey pieces that fly apart for shardTime seconds,
    // and the mana bar flashes barColor barFlashes times, each barFlash
    // seconds long - as it does for a right-click with no mana
    readonly property var shieldBreak: ({
        lowShare: 0.25,
        blink: 4,
        shards: 3,
        shardTime: 0.3,
        barColor: "#FF3030",
        barFlashes: 2,
        barFlash: 0.12
    })

    // While an enemy winds up, a ring in its telegraph colour closes from
    // from times its size onto its outline, on the physics steps, and
    // reaches it on the step the lunge's parry window opens. It is
    // thickness of the enemy's width thick, drawn at this opacity, and
    // flashColor while the window is open. A spitter's shot gets the same
    // ring, closing as the shot leaves, without the flash
    readonly property var parryRing: ({
        from: 2,
        thickness: 0.06,
        opacity: 0.9,
        flashColor: "#FFFFFF"
    })

    // Momentum, the whirlwind's price: max pips, earned by blows that land
    // - a swing or a heavy blow that hits swing or heavy (once a swing,
    // however many it hits), a parry parry, a bash that shoves bash, a
    // perfect block perfectBlock. Q with all of them whirls and spends
    // them; short of max it flashes the pips for flash seconds. A fall
    // loses them, a new level keeps them
    readonly property var momentum: ({
        max: 4,
        swing: 1,
        heavy: 1,
        parry: 2,
        bash: 1,
        perfectBlock: 2,
        flash: 0.4,
        color: "#FFC85A"
    })

    // The sword-and-shield combo: the right button within window seconds of
    // a normal swing's start bashes with the shield. Every standing enemy
    // within reach times the knight's attackRange and in the swing's arc
    // is shoved back at speed wu/s, as the dash push does, and a guardian's
    // guard breaks. It costs mana; without it the shield only rises
    readonly property var bash: ({
        window: 0.35,
        mana: 6,
        reach: 1.2,
        speed: 20.0,
        // A shoved enemy breaks off its attack, staggered this long (a
        // guardian the full enemy.stagger, its guard broken)
        stagger: 0.4,
        // The knight lunges behind its shield: lungeSpeed wu/s along its
        // facing, fading out over lungeTime seconds, the shield up and
        // flashing, sparks sparks off its front
        lungeSpeed: 8.0,
        lungeTime: 0.12,
        sparks: 6,
        word: "BASH",
        wordColor: "#9FD4E8"
    })

    // The knight's footsteps: perSecond of them while it walks, the same
    // beat as the view's step bob; a knight that does not really move, held
    // by a wall, makes none. At volume, the sample pitched by the next of
    // pitches semitones in turn, left and right foot
    readonly property var steps: ({
        perSecond: 2.6,
        volume: 0.15,
        pitches: [0, -2]
    })

    // A grunt or a guardian winding up its lunge screams like a goblin,
    // fading with the distance as the crushing blow's growl does: the
    // sample pitched by tierPitch semitones (weak, normal, tough) at volume
    readonly property var scream: ({
        tierPitch: [0, -3, -6],
        volume: 0.7
    })

    // A crushing blow (enemy.crush...) reads as its own: while it winds up
    // the enemy glows glow, white-hot, a halo of halo times its size at
    // haloOpacity around it; its ring is ringColor, thickness times the
    // parry ring's, with a second one gap times its size, and it growls:
    // the spitter's sample growlPitch semitones down. Its blow on a held
    // shield throws sparks sparks and the shield's shards, and the
    // knight's own screen freezes for freeze seconds with this much
    // trauma and a kick of kick wu
    readonly property var crush: ({
        glow: "#FFF4E0",
        halo: 1.4,
        haloOpacity: 0.45,
        ringColor: "#FF4A1C",
        thickness: 1.6,
        gap: 1.5,
        growlPitch: -12,
        sparks: 14,
        freeze: 0.11,
        trauma: 0.6,
        kick: 0.3
    })

    readonly property var enemy: ({
        // Base HP by tier: weak, normal, tough
        tierHp: [22, 36, 50],
        // Per type: HP on top of the tier, attack, defense, speeds
        grunt: { hpBonus: 0, atk: 12, def: 2, chaseSpeed: 4.0, patrolSpeed: 1.5 },
        guardian: { hpBonus: 10, atk: 12, def: 2, chaseSpeed: 4.0, patrolSpeed: 1.5 },
        spitter: { hpBonus: -6, atk: 10, def: 0, chaseSpeed: 2.4, patrolSpeed: 0.9 },
        // How often an enemy decides, and how often a chase re-plans its path
        thinkInterval: 0.1,
        repathInterval: 1.0,
        // Patrol waypoints lie this far from the spawn point
        patrolRadius: 2,
        // A patrolling enemy notices a knight it sees within sightRange wu.
        // Chasing, one it cannot see it hunts where it saw it last, and
        // gives up after giveUpAfter seconds unseen or there, back to its
        // patrol: a room does not follow the knight through the dungeon
        sightRange: 7.0,
        giveUpAfter: 4.0,
        // Lunge: wind up backwards, then dash at the knight
        lungeRange: 2.0,
        windUpSpeed: 4.0,
        windUp: 0.3,
        lungeDuration: 0.35,
        // A lunge hits when it ends this close to the knight
        lungeHitRange: 1.2,
        // The last physics steps (1/60 s each) of a lunge in which a swing
        // parries it
        parryFrames: 9,
        // No attack is telegraphed for less than this: a wind-up, a
        // counter or a shot that would be shorter is drawn out to it
        minTelegraph: 0.25,
        recovery: 0.8,
        stagger: 1.0,
        // Pushed back by a hit, not steering against it
        knockbackSpeed: 7,
        knockbackDuration: 0.12,
        // Guardian: a frontal shield that turns toward the knight
        shieldArc: 60,
        shieldTurnSpeed: 120,
        blockedShare: 0.3,
        // After a blocked hit it counters, winding up this share of windUp
        counterWindUp: 0.5,
        // Crushing blow: a tough grunt or guardian winds one up instead of
        // a lunge at crushChance of its attacks, for crushWindUp seconds
        // (aiState "crush"). A held shield breaks against it: crushMana
        // mana gone, the shield down for crushLockout seconds, crushShare
        // of the damage through. A perfect block stops it whole and
        // staggers the enemy for stagger; a dash dodges it; it opens no
        // parry window
        crushChance: 0.3,
        crushWindUp: 0.5,
        crushMana: 15,
        crushLockout: 0.5,
        crushShare: 0.6,
        // Spitter: keeps its distance and shoots
        preferredDist: 5.0,
        // Backs off below this share of preferredDist, closes in above the other
        tooClose: 0.7,
        tooFar: 1.3,
        kiteSpeed: 3.0,
        shootRange: 8.0,
        shootCooldown: 1.2,
        shootWindUp: 0.3
    })

    readonly property var projectile: ({
        speed: 5.0,
        lifetime: 3.0
    })

    readonly property var spawn: ({
        // Rooms per dungeon, rolled evenly from roomsMin to roomsMax, each
        // roomSizeMin to roomSizeMax cells a side; the build and the witch's
        // reading both take these
        roomsMin: 9,
        roomsMax: 12,
        roomSizeMin: 5,
        roomSizeMax: 8,
        // Enemies per dungeon at depth 0, rolled evenly from min to max
        enemiesMin: 10,
        enemiesMax: 15,
        // Tier mix of a dungeon, dealt not rolled: weakChance of its enemies
        // (rounded) are weak, those above normalChance tough, the rest normal
        weakChance: 0.2,
        normalChance: 0.8,
        // Type rolls: guardian first, then spitter, else grunt
        guardianChance: 0.15,
        guardianChanceTough: 0.4,
        spitterChance: 0.2,
        // The village fight room: who stands where, offset in wu from its
        // centre, and how long after it is cleared it fills up again
        fightRoom: [
            { dx: 4, dy: 2, tier: 1, type: "grunt" },
            { dx: -4, dy: 2, tier: 1, type: "grunt" },
            { dx: 0, dy: 4, tier: 2, type: "guardian" },
            { dx: -3, dy: -3, tier: 1, type: "spitter" }
        ],
        fightRoomRespawn: 2.0
    })

    // Deeper is harder: each step of a dungeon's danger (its depth, counted
    // in dungeons from 0, plus its position in the depth's range, see
    // danger) adds these to the spawn rolls and the enemies' attack, up to
    // the caps. A danger between two whole steps adds its share
    readonly property var depth: ({
        // More enemies: added to enemiesMin and enemiesMax, never above the
        // cap; at 2 a dungeon two depths down holds more than the one above
        enemies: 2,
        enemiesCap: 26,
        // Fewer weak: weakChance falls by this, not below 0
        weakChance: -0.05,
        // More tough: the tough share (above normalChance) grows by this
        toughChance: 0.08,
        toughCap: 0.6,
        // More guardians and spitters: added to their chances (a tough
        // guardian's too), each up to the cap
        guardianChance: 0.03,
        spitterChance: 0.03,
        typeCap: 0.45,
        // Harder blows: added to every enemy's atk, rounded to whole points
        atk: 0.5
    })

    // A dungeon's danger is its depth plus a position in [0, 1) in that
    // depth's range. Leaving a dungeon moves the position pull of the way
    // toward what it earned: 1 less the share of max HP the knights lost
    // in it, averaged (a potion's heal does not take a loss back), or 0 if
    // a knight fell there. The position goes on into the next run, not
    // past a restart: a fresh game starts at start. It never reaches top
    readonly property var danger: ({
        start: 0.5,
        pull: 0.5,
        top: 0.999,
        // A position below low is low danger, from high on high, between
        // them middle
        low: 0.33,
        high: 0.67,
        // What a dungeon looks like at low, middle and high danger:
        // torches in torch, torchShare of the torch spots lit, the
        // darkness's ambient and the screen's temperature; crackShare of
        // the floor stones cracked and moss over that share of the floor;
        // stains old stains, bones heaps of bones and embers glowing coals
        // per room on the floor; dust and embers in the air at that
        // density (0 for none). The exit stairs glow in the next
        // dungeon's torch colour
        looks: [
            { torch: "#FFB65C", torchShare: 1.0, ambient: "#100D0C", temperature: 0.12,
              crackShare: 0.02, moss: 0, stains: 0, bones: 0, embers: 0,
              dust: 0.5, emberAir: 0 },
            { torch: "#BFD0E8", torchShare: 0.6, ambient: "#090B12", temperature: -0.08,
              crackShare: 0.14, moss: 0.35, stains: 2, bones: 0, embers: 0,
              dust: 0.2, emberAir: 0 },
            { torch: "#FF3A14", torchShare: 0.85, ambient: "#140707", temperature: 0.3,
              crackShare: 0.4, moss: 0, stains: 3, bones: 2, embers: 0,
              dust: 0, emberAir: 0 }
        ]
    })

    // A dungeon's features - what the knights read, use, find or break -
    // laid out once its rooms and corridors are carved, each kind from its
    // own stream of the level's seed. Every feature keeps the same rules:
    // it stands on a room's cell, never in the start room, never on a
    // doorway (a room cell beside a corridor) nor on a corridor's cell, at
    // least clearOfEntrance wu from the entrance and clearOfExit wu from
    // the exit, centre to centre, one feature to a cell. kinds, in the
    // order they are laid out: perRoom how many of the kind each room but
    // the start room holds at low, middle and high danger (as
    // danger.looks), a whole number, its fraction a chance of one more;
    // showcase how many per room in the dojo's features scenario. The
    // breakables: a clay "urn", a wooden "crate" (or barrel) and a
    // "crystal" cluster, rarer the shallower; then the traps: a "spike"
    // plate, more often the higher the danger, and an arrow "slit" in a
    // room's wall, the more and the faster the higher the danger
    readonly property var dungeon: ({
        // Loops: the rooms are joined in a chain, and extraCorridors more
        // corridors at low, middle and high danger (as danger.looks) join
        // two rooms close but not neighbours in it, so a dungeon has ways
        // around. Each is drawn from the loopChoice closest pairs left; one
        // that would cut through or open into a third room, or run into
        // the entrance's or the exit's shaft, is passed over
        extraCorridors: [1, 2, 3],
        loopChoice: 3,
        // Doors: a room entrance - a corridor's cell beside a room, with
        // rock on its two other sides - gets one with doorShare's chance at
        // low, middle and high danger, every one in the features scenario.
        // Two jambs doorJamb wu thick narrow the doorway to a leaf
        // doorWidth wu wide, one knight, and doorThickness thick. A door
        // starts closed. Closed it blocks the knights, the enemies, their
        // shots and their sight; E within doorReach wu of its centre opens
        // or closes it, unless someone stands in it. An enemy chasing
        // through a closed door stops within doorBashReach wu of it, winds
        // up doorBash seconds (the wind-up ring) and bursts it open; a
        // bashed door stays open. The enemies' paths take a closed door
        // as doorPathCost cells more than an open one
        doorShare: [0.3, 0.4, 0.5],
        doorWidth: 1.2,
        doorThickness: 0.3,
        doorJamb: 0.5,
        doorReach: 1.8,
        doorBash: 1.5,
        doorBashReach: 1.6,
        doorPathCost: 6,
        clearOfEntrance: 8,
        clearOfExit: 8,
        kinds: {
            urn: { perRoom: [0.8, 0.6, 0.5], showcase: 1 },
            crate: { perRoom: [0.6, 0.7, 0.6], showcase: 1 },
            crystal: { perRoom: [0.1, 0.25, 0.45], showcase: 1 },
            spike: { perRoom: [0.3, 0.5, 0.8], showcase: 1 },
            slit: { perRoom: [0.25, 0.5, 0.6], showcase: 1 }
        },
        // A breakable blocks like a small wall: a square of sizeWu on its
        // cell's centre. A swing breaks the nearest one in its arc, a
        // charged swing and the whirlwind every one they reach; a crystal
        // only a charged swing breaks
        breakableSize: 1.2,
        // An urn and a barrel stand upright and are drawn from the side:
        // they block a square of foot wu instead (a knight is 1 wu, a
        // flagstone 0.5) and rise tall wu from its near edge
        standing: {
            urn: { foot: 0.6, tall: 0.85 },
            barrel: { foot: 0.75, tall: 1.0 }
        },
        // What a breakable holds: gold with chance, an amount from
        // gold[0] to gold[1], and perDepth more of both ends a depth.
        // Rolled by the host from the level's seed and the thing's cell,
        // dropped where it stood
        loot: {
            urn: { chance: 0.35, gold: [1, 3], perDepth: 0 },
            crate: { chance: 0.3, gold: [2, 4], perDepth: 0 },
            crystal: { chance: 0.85, gold: [6, 10], perDepth: 2 }
        },
        // A spike plate: a square of spikePlateSize wu on its cell's
        // centre with small holes in it. A knight whose centre steps on it
        // makes it click, and spikeDelay seconds later its spikes rise: a
        // knight still on it then, and not dashing, takes spikeDamage and
        // spikeDamagePerDepth more a depth, never more than spikeCap of
        // its max HP; no defence, shield or grace takes any of it. A plate
        // fires once and stays sprung. Only knights trigger it.
        // spikeClickPitch and spikeRisePitch are the click's and the
        // spikes' notes, in semitones off their samples
        spikePlateSize: 1.6,
        spikeDelay: 0.25,
        spikeDamage: 14,
        spikeDamagePerDepth: 3,
        spikeCap: 0.25,
        spikeClickPitch: -9,
        spikeRisePitch: 9,
        // An arrow slit sits in the wall beside its feature's cell, a room
        // cell on the room's edge, and fires across the room along its
        // row or column to the wall facing it. It fires on the beats of
        // its rhythm, slitBeat seconds each, counted on the session clock
        // (alone on the physics clock), so every screen fires the same
        // arrow at the same moment. Before each shot it glows: a ring in
        // slitGlowColor closes on it over slitWarn seconds, as an enemy's
        // parry ring does, and flashes as the arrow leaves.
        // slitRhythms: beats, 1 a shot and 0 a rest, and the danger bands
        // a rhythm is drawn at. A room's second slit takes the first's
        // rhythm half a turn later: the two take turns. Every slit leaves
        // a safe way past: a lane, the room's doorways joined by cells no
        // arrow crosses, or a gap, a rest in its rhythm long enough for a
        // knight to walk over its line, slitGapMargin times what that
        // takes (Game.slitCrossTime); a room with neither takes the band's
        // first rhythm with one. An arrow is arrowLength wu long and flies
        // at arrowSpeed; it hurts only knights: arrowDamage and
        // arrowDamagePerDepth more a depth, never more than arrowCap of
        // the knight's max HP, less its defence. A held shield facing it
        // stops it whole, at the shield's mana cost; a perfect block sends
        // it back to its slit; a dash passes through it. slitShotPitch is
        // the shot's note, in semitones off the swing's sample
        slitBeat: 0.3,
        slitWarn: 0.45,
        slitGlowColor: "#FF8C00",
        slitRhythms: [
            { name: "single", beats: [1, 0, 0, 0, 0], bands: [0, 1, 2] },
            { name: "double", beats: [1, 0, 1, 0, 0, 0, 0], bands: [0, 1, 2] },
            { name: "volley", beats: [1, 1, 1, 0, 0, 0, 0, 0], bands: [1, 2] },
            { name: "stream", beats: [1, 0], bands: [2] },
            { name: "hail", beats: [1], bands: [2] }
        ],
        slitGapMargin: 1.5,
        arrowLength: 0.8,
        arrowSpeed: 12,
        arrowDamage: 12,
        arrowDamagePerDepth: 2,
        arrowCap: 0.2,
        slitShotPitch: 7,
        // Secret rooms: secrets how many a dungeon hides at low, middle and
        // high danger, a whole number, its fraction a chance of one more;
        // secretShowcase in the features scenario. Each is a chamber of
        // secretSize by secretSize cells off a room but the start room,
        // behind one cell of its wall, with rock all round. The wall cell
        // shows a hairline crack with dust breathing out of it. A dash
        // that reaches its face - the knight's body within secretDashReach
        // wu of it, its centre in front of the cell - bursts it open when
        // it heads into the wall no more than secretDashAngle degrees off
        // straight; at a flatter angle it glances off with a puff of dust
        // and a knock. E does nothing at it. It lies on no way to the
        // exit, and stays rock on the minimap until it is open. It holds a
        // cache: cacheThings urns
        // and crates and, with cacheCrystal's chance at the band, a
        // crystal cluster, each with the gold of its cacheLoot row (as
        // loot), always more than the same thing elsewhere
        secrets: [0.3, 0.6, 1.3],
        secretShowcase: 1,
        secretSize: 3,
        secretDashReach: 0.25,
        secretDashAngle: 45,
        cacheThings: 3,
        cacheCrystal: [0.25, 0.4, 0.6],
        cacheLoot: {
            urn: { chance: 1, gold: [4, 7], perDepth: 1 },
            crate: { chance: 1, gold: [5, 8], perDepth: 1 },
            crystal: { chance: 1, gold: [14, 20], perDepth: 3 }
        }
    })

    // Greed in the deep (issue #154): a vein of gems in a wall's face, cut
    // with the pickaxe the sword turns into while digging (issue #155).
    // E with the knight's centre within reach wu of the vein's face starts
    // the dig, the sword folding into the pickaxe in morph seconds; walking
    // further than leave wu off, raising the shield, swinging or dashing
    // ends it, and the pickaxe folds back. While it digs a ring closes on
    // the vein from ringFrom times ringSize wu to ringSize, once every
    // ringTime seconds, counted on the physics steps: E within window
    // seconds of a close, before or after it, is a clean strike, once a
    // close; any other E chips. A vein takes strikes[0] to strikes[1]
    // strikes, clean or chipped, by its seed; the last one splits the
    // stone and the gem pops out, its size in wu from gemSize[0] with no
    // clean strike to gemSize[1] with all of them clean, by their share.
    // A clean strike throws sparks in the gem's colour and plays the tink
    // a step of phrase higher (semitones above the sample) for each clean
    // strike before it; a chip throws chips grey chips and plays the
    // chink alone, chipPitch semitones down. The gem coming free plays the
    // tink at each of chime, chimeGap seconds apart, and the crumble.
    // Within glintReach wu of the knight a vein glints, brighter the
    // nearer; coming within shimmerReach it shimmers once, the tink at
    // shimmerPitch and shimmerVolume times its volume. shapes: the gem by depth, the last
    // whose from is at most the depth: the five Platonic solids
    readonly property var deep: ({
        reach: 1.6,
        leave: 2.4,
        morph: 0.16,
        ringTime: 0.75,
        ringSize: 1.1,
        ringFrom: 2.4,
        window: 0.12,
        strikes: [3, 5],
        gemSize: [0.34, 0.74],
        sparks: 8,
        chips: 7,
        chipColor: "#8C8A86",
        chinkVolume: 0.8,
        chipPitch: -3,
        tinkVolume: 0.5,
        phrase: [0, 2, 4, 7, 9, 12],
        chime: [12, 19, 24],
        chimeGap: 0.12,
        crumbleVolume: 0.5,
        glintReach: 5.5,
        shimmerReach: 3.5,
        shimmerPitch: 19,
        shimmerVolume: 0.12,
        shapes: [
            { from: 0, shape: "tetrahedron", color: "#F2B33D" },
            { from: 2, shape: "cube", color: "#4FC48A" },
            { from: 4, shape: "octahedron", color: "#4A86F0" },
            { from: 6, shape: "dodecahedron", color: "#B072E8" },
            { from: 8, shape: "icosahedron", color: "#FF4A2A" }
        ]
    })

    // Gold: what a killed enemy drops where it fell, for a knight to pick up
    readonly property var loot: ({
        // By tier: weak, normal, tough. The fight room drops none
        goldByTier: [3, 5, 8],
        // A knight this close to a drop picks it up
        pickupRange: 0.8
    })

    // The village's wares, in gold: the innkeeper's potions, drunk with
    // key 1, and mana draughts, drunk with key 2, and the smith's upgrades
    readonly property var shop: ({
        potionPrice: 15,
        potionHeal: 50,
        // A mana draught gives back this much mana, up to the knight's max:
        // at knight.mana it refills the bar
        draughtPrice: 20,
        draughtMana: 40,
        // The smith's upgrades last the run and have levels: the sword,
        // the shield, the harness and the blade. At each camp he sells one
        // level of one of them, the next above the knight's; the camp
        // after depth d offers level L only once d reaches levelDepth[L - 1].
        // Level L costs upgradePrice[L - 1] and gives the L-th entry of
        // its effect below
        levelDepth: [0, 2, 4],
        upgradePrice: [30, 45, 60],
        // Sharpened sword: added to the knight's atk
        swordAtk: [5, 9, 12],
        // Reinforced shield: a held block lets this share through instead
        // of knight.blockedShare, and a blow it stops costs this much mana
        // instead of knight.blockMana. The perfect block's window stays
        // the same
        shieldBlockedShare: [0.15, 0.1, 0.05],
        shieldBlockMana: [4, 3, 2],
        // Lighter harness: a dash costs this much mana instead of
        // knight.dashMana, the whirlwind's dash too
        harnessDashMana: [6, 4, 3],
        // Balanced blade: a whirlwind costs this much mana, its dash
        // included, instead of knight.whirlMana
        bladeWhirlMana: [15, 12, 9]
    })

    // The dungeon master's panel (issue #142): with Dungeon Master ticked
    // on the title, the host or a solo player sees these settings before
    // each dungeon, with the values the game would use, and sets any of
    // them for that dungeon and the ones after. A row: its key, its
    // label, the step its arrows turn it by, its range and the decimals
    // shown; kinds the feature kinds (dungeon.kinds) it sets per room
    // together, its whole number split between them as the dungeon's
    // band shares them out. A feature knob more is a row more
    readonly property var dungeonMaster: ({
        settings: [
            { key: "enemies", label: "Enemies per room", step: 0.1, min: 0, max: 8, decimals: 2 },
            { key: "spikes", label: "Spike plates per room", step: 0.1, min: 0, max: 4, decimals: 2,
              kinds: ["spike"] },
            { key: "slits", label: "Arrow slits per room", step: 0.1, min: 0, max: 4, decimals: 2,
              kinds: ["slit"] },
            { key: "rooms", label: "Rooms", step: 1, min: 3, max: 16, decimals: 0 },
            { key: "depth", label: "Base depth", step: 1, min: 0, max: 30, decimals: 0 },
            { key: "position", label: "Relative difficulty", step: 0.05, min: 0, max: 0.999, decimals: 2 },
            { key: "breakables", label: "Breakables per room", step: 0.1, min: 0, max: 6, decimals: 2,
              kinds: ["urn", "crate", "crystal"] }
        ]
    })

    // A session's party: an ally lifts a fallen knight up, and a knight
    // still down when the party reaches the camp rises there. Solo play
    // has neither. A dungeon is built for the knights the party had when
    // it was entered: each knight beyond the first adds enemiesPerKnight
    // to the spawn table's enemiesMin and enemiesMax, on top of what its
    // danger adds and never above depth.enemiesCap, and hpPerKnight of
    // each enemy's HP, rounded to whole points. One knight's dungeon has
    // neither, nor has the village's fight room
    readonly property var party: ({
        enemiesPerKnight: 2,
        hpPerKnight: 0.25,
        // An ally this close to a fallen knight (centre to centre, wu)
        // lifts it up once it has stood there reviveTime seconds, on the
        // physics clock, without a hit landing on it; a hit, or a step out
        // of range, starts the lift over
        reviveRange: 1.5,
        reviveTime: 3.0,
        // The knight rises with this share of its max HP, lifted or at camp
        reviveHp: 0.3,
        // The ring that fills around the fallen knight while it is lifted:
        // its radius as a share of the knight's size, its width in pixels
        // and its colour
        ringRadius: 0.9,
        ringWidth: 3,
        ringColor: "#F2E2A0"
    })

    // The HUD's descent gauge: a shaft of layers in view, one per depth,
    // the knight's marker in the middle one once it is that deep. A
    // layer's rock goes from top at depth 0 to deep at hotDepth and on,
    // drawn glow of the way toward the seam colour there, and the seam
    // under it glows from none at depth 0 to full at hotDepth; every other
    // layer is alternate as bright. Small in a dungeon, large at the camp
    // (shaft width and layer height in pixels), where the marker waits
    // sinkDelay seconds and then sinks in sink seconds into the next layer
    readonly property var gauge: ({
        layers: 5,
        top: "#9C8B6A",
        deep: "#2A1612",
        seam: "#FF5A1C",
        glow: 0.4,
        hotDepth: 20,
        alternate: 0.88,
        marker: "#F2E2A0",
        small: { width: 18, layer: 14 },
        large: { width: 56, layer: 52 },
        sinkDelay: 0.6,
        sink: 1.6
    })

    // The record of the deepest descent: a run that goes deeper raises a
    // banner over the dungeon for banner seconds, fading in and out in
    // fade seconds, and plays a chime at volume: the menu's confirm sound
    // once per note of chime (semitones over its own), step seconds apart
    readonly property var record: ({
        banner: 2.5,
        fade: 0.3,
        volume: 0.7,
        chime: [0, 4, 7, 12],
        step: 0.12
    })

    readonly property var campfire: ({
        healPerSecond: 5.0,
        // Mana comes back here, on top of the rest's knight.manaRegen
        manaPerSecond: 5.0,
        healRadius: 3.0,
        healTick: 0.2
    })

    // The camp (issue #145): a cave, not a box. Sizes in grid cells (2 wu)
    // unless named in wu. The cave fills a box of width x height cells
    // whose top sits exitTunnel rows below the top of the map, where the
    // stairs are. Its edge runs bay cells inside the box, and along each
    // side it moves out by up to bay cells (a bay) or in by up to outcrop
    // cells (an outcrop), stepping by one or two cells every stretch[0] to
    // stretch[1] cells;
    // each corner of the box is cut off diagonally by corner[0] to
    // corner[1] cells. The entrance and the exit open in a bay. The
    // outline draws from its own stream, the level's seed ^ seedSalt, so
    // every screen of a session builds the same cave
    readonly property var camp: ({
        width: 32,
        height: 26,
        exitTunnel: 3,
        bay: 2,
        outcrop: 2,
        stretch: [3, 6],
        corner: [4, 7],
        seedSalt: 0x63617665,
        // The walk from where the knights come in to the stairs, at
        // knight.moveSpeed, takes at most this many seconds
        maxWalk: 8,
        // The tavern and the smithy: walls of whole cells, open to the
        // south, width x height cells each, building cells to either side
        // of the camp's middle column and raised cells above its middle row
        building: { width: 5, height: 4, side: 4, raised: 2 },
        // The campfire's light, in wu: it reaches the buildings, which
        // cast shadows from it
        fireLight: 16,
        // The rock overhangs the cave's north-facing edges: a lip of lip wu
        // hangs over the top of the face, stalactites of up to stalactite
        // wu below it, one in about every tooth wu along the edge, and
        // their shadows fall up to shadow wu onto the floor
        overhang: { lip: 0.3, stalactite: 0.55, tooth: 0.7, shadow: 1.6 },
        // The camp's look follows the depth (issue #146): a camp takes the
        // last of looks whose from is at most its depth, the depth of the
        // dungeon before it. Each look has its rock (the walls' tops and
        // the overhang), its faces in faceStyle ("bricks", "moss",
        // "strata" or "basalt") with their rims, the tavern's and the
        // smithy's walls and faces, the lanterns at their fronts, the
        // witch's tree (or what stands in its place); its floor in style
        // ("stone", "earth" or "basalt") with grass over that share of
        // earth, moss over that share of stone and that share of the
        // stones cracked; its air (motes of that colour, density and
        // size, drifting that far, blinking like fireflies or not, glowing
        // on their own or seen in the light); its moths (see moths below);
        // and its screen grade: the darkness's ambient, the temperature,
        // the saturation and the vignette. Its props are one of layouts,
        // picked from the level's seed ^ propSalt, each a list of props:
        // a kind of shaders/prop.frag centred x, y wu from the camp's
        // centre (east, north), w x h wu.
        // A prop that would not lie whole on the cave's floor, clear of
        // the paths, the fire and the people, is left out. Props are drawn
        // only: the knights walk over them, nothing blocks or hurts
        propSalt: 0x70726f70,
        // Props stay this far, in wu, off the middle column (the way from
        // the entrance to the stairs), off the campfire's centre, off the
        // fronts of the buildings, and off the innkeeper, the smith, the
        // witch, her tree and every spot of their routines
        clearOfPath: 3,
        clearOfFire: 5,
        clearOfFront: 3,
        clearOfPeople: 2.5,
        // A prop whose place the cave's edge cuts moves up to propShift wu
        // toward the middle, on its side and then on the other
        propShift: 4,
        // A knight that stands still sitAfter seconds within the
        // campfire's healRadius sits down facing the fire (issue #148):
        // no key, no button, no knockback. Any of them stands it up at
        // once. It is the look only: the fire heals and refills the same.
        // The pose sinks in down seconds and rises in up seconds, squash
        // of the knight's height lower; seated it breathes breath radians
        // a second, breathDepth of its height deep, and its shield lies
        // on the floor beside it
        sitAfter: 3,
        sit: { down: 0.45, up: 0.12, squash: 0.2, breath: 1.3, breathDepth: 0.05 },
        // The camp rests (issue #147) once every knight in it has stood
        // still restQuiet seconds: every knight seated, the last of them
        // standing still since restQuiet - sitAfter before it sat
        restQuiet: 10,
        // The camp's near sounds (issue #147), each played at its source:
        // the listening knight hears it at volume times (1 - d / reach)
        // squared, d its distance in wu, and not at all from reach on. It
        // plays again every every[0] to every[1] seconds, pitched by
        // pitch[0] to pitch[1] semitones. The campfire crackles in every
        // camp, the anvil rings while the smith stands at it hammering,
        // and each look has its own at the props of its kinds: drips at
        // the grotto's pond, the cart creaking in the miners' hall, the
        // embers hissing at the ember camp's coals and cracks. While the
        // camp rests the music falls to restMusic of its level in
        // fadeDown seconds and the near sounds rise to restNear times
        // their volume; a knight that moves brings both back in fadeUp
        sounds: {
            fire: { sample: "camp_crackle.wav", volume: 0.55, reach: 16, every: [0.12, 0.45], pitch: [-3, 2] },
            anvil: { sample: "camp_anvil.wav", volume: 0.45, reach: 18, every: [0.8, 1.1], pitch: [-1, 0] },
            looks: {
                grotto: { sample: "camp_drip.wav", props: ["pond"], volume: 0.5, reach: 14, every: [0.9, 3.0], pitch: [-4, 5] },
                hall: { sample: "camp_creak.wav", props: ["cart"], volume: 0.45, reach: 14, every: [3.0, 7.0], pitch: [-2, 2] },
                ember: { sample: "camp_hiss.wav", props: ["coals", "cracks"], volume: 0.35, reach: 12, every: [1.5, 4.5], pitch: [-3, 1] }
            },
            restMusic: 0.3,
            restNear: 1.5,
            fadeDown: 3,
            fadeUp: 0.8
        },
        // The camp's lights breathe (issue #149): on top of its flicker the
        // campfire's and each lantern's intensity swells and sinks by up
        // to depth of itself, one breath every seconds[0] to seconds[1]
        // seconds, each light on its own breath. Only the intensity
        // breathes, never the radius; the fire stays the brightest light.
        // The breaths and the moths draw from the level's seed ^
        // lightSalt, so every screen of a session sees the same
        lightSalt: 0x6d6f7468,
        breath: { seconds: [5, 8], depth: 0.1 },
        // Moths circle the campfire and every lantern in slow, uneven
        // loops (issue #149), as many as the look's moths says (fire,
        // lantern: moths at each, at most 8), in its colour, drawn in one
        // pass by shaders/moths.frag for up to 6 lights. A moth's loop is
        // orbit wu around its light (fire or lantern), flattened to
        // squash of that north to south, swelling and shrinking by swell
        // of itself; it goes round at speed[0] to speed[1] radians a
        // second, either way, wavering by waver, and darts aside up to
        // dart wu. Its wings, size wu across, beat flutter times a second
        moths: {
            lantern: { orbit: 0.8 },
            fire: { orbit: 1.6 },
            squash: 0.6,
            swell: 0.35,
            speed: [0.5, 1.1],
            waver: 0.6,
            dart: 0.12,
            size: 0.24,
            flutter: 9
        },
        // A cave cat sleeps curled by the campfire (issue #150) in share
        // of the camps, drawn from the level's seed ^ catSalt, so every
        // screen of a session sees the same cat or none. It lies ring[0]
        // to ring[1] wu from the fire's centre, out of the warmth where
        // the knights sit, at one of angles spots round it that lies
        // whole on the floor, clearOfPath, clearOfPeople and clearOfProps
        // wu off the way to the stairs, the people's spots and the props;
        // with none it is not there. It is size wu across and breathes
        // once every breath seconds. Every tick seconds it looks for a
        // standing knight: one within notice wu lifts its head in rise
        // seconds, and once none is within forget wu for settle seconds it
        // tucks it back in fall seconds. Asleep it stretches every
        // act.every[0] to [1] seconds, for act.seconds
        catSalt: 0x63617421,
        cat: {
            share: 0.8,
            ring: [4.5, 5],
            angles: 24,
            clearOfProps: 0.5,
            size: 1.1,
            breath: 4,
            tick: 0.1,
            notice: 3,
            forget: 4,
            settle: 1.5,
            rise: 0.4,
            fall: 1.2,
            act: { every: [20, 45], seconds: 2.5 },
            fur: "#6E5E52",
            light: "#A89380",
            eyes: "#E8D27A"
        },
        // Travellers rest at the camp (issue #151): count[0] to count[1]
        // of kinds, other adventurers on their way, each its own name,
        // shape, colour and icon, drawn from the level's seed ^
        // travellerSalt, so every screen of a session sees the same. Each
        // sits at one of angles spots ring[0] to ring[1] wu from the
        // fire's centre, on the floor, for rest[0] to rest[1] seconds,
        // then wanders to one of the look's wander props - off wu off its
        // edge toward the camp's middle, apart wu aside of the traveller
        // before it, doing its text - for wander[0]
        // to wander[1] seconds, and back; without such a prop it moves to
        // another seat. They walk at walk wu a second and the knights walk
        // through them. Talked to (E) one gives hearsayLines of hearsay,
        // and sells nothing. Two of them standing within reach wu of each
        // other exchange one of exchanges, the first after first[0] to
        // first[1] seconds in the camp, then every every[0] to every[1]
        // seconds: one says the first line, the other answers after answer
        // seconds, each bubble up for show seconds. A dog follows one of
        // them (dog below). The lines are tables: more are written here
        travellerSalt: 0x74726176,
        travellers: {
            count: [1, 3],
            kinds: [
                { name: "Wanderer", shape: "square", color: "#5E8CB8", icon: "pack" },
                { name: "Pilgrim", shape: "diamond", color: "#9AB85E", icon: "staff" },
                { name: "Minstrel", shape: "circle", color: "#C8607A", icon: "lute" },
                { name: "Prospector", shape: "square", color: "#B89A5E", icon: "pack" },
                { name: "Hermit", shape: "diamond", color: "#8A7AA8", icon: "staff" }
            ],
            ring: [2.2, 2.8],
            angles: 16,
            rest: [16, 26],
            wander: [7, 11],
            walk: 1.2,
            off: 1.2,
            apart: 1.4,
            props: {
                grotto: [ { kind: "pond", text: "*watching the water*" } ],
                hall: [ { kind: "cart", text: "*peering into the cart*" } ],
                ember: [ { kind: "coals", text: "*warming hands*" }, { kind: "cracks", text: "*staring into the glow*" } ]
            },
            seatText: "*resting*",
            hearsayLines: 2,
            reach: 9,
            first: [4, 8],
            every: [10, 18],
            answer: 2.5,
            show: 4,
            // A dog follows one traveller: it trots after it, stays follow
            // wu beside it, runs at speed wu a second, and is a Creature
            // like the cat: it looks up at a standing knight within notice
            // wu and settles once none is within forget wu for settle
            // seconds; at rest it scratches every act.every[0] to [1]
            // seconds, for act.seconds
            dog: {
                size: 0.75,
                follow: 0.9,
                speed: 2.4,
                breath: 1.6,
                tick: 0.1,
                notice: 3,
                forget: 4,
                settle: 1.5,
                rise: 0.3,
                fall: 0.8,
                act: { every: [12, 25], seconds: 1.4 },
                fur: "#8A6A44",
                light: "#C9A878",
                eyes: "#2A1E14"
            },
            exchanges: [
                [ "Heard the slits on four fire in threes.", "Then dash on the third." ],
                [ "The big ones swing slow.", "Slow, but you only get to be wrong once." ],
                [ "Lost my lantern two floors down.", "Lost my brother three floors down. Keep the lantern." ],
                [ "Some walls down there sound hollow.", "Hit them. Gold likes to hide." ],
                [ "This fire's the best thing I've seen all week.", "Week's not over." ],
                [ "Spitters keep their distance.", "So close it for them." ],
                [ "Any of you been past the embers?", "Once. Came back with less eyebrow." ],
                [ "Smith says the blade gets better deeper down.", "So does the trouble." ],
                [ "Hold the shield too long and it runs dry.", "Like my purse." ],
                [ "The plates on the floor click before they bite.", "Then listen for the click." ]
            ],
            hearsay: [
                "They say the deeper camps keep warmer fires. Something down there keeps them lit.",
                "A guardian shoves you back when you stand in its way. Step aside, then strike.",
                "Folk say the witch reads the next dungeon true. I've never caught her wrong.",
                "Heard of a knight who parried a crushing blow. Heard it from him, mind.",
                "The arrow slits fire in rhythm. Count, then walk.",
                "Down past the miners' hall the rock gets hot enough to cook on.",
                "Some hollow walls hide a whole chamber. Look for the cracked ones.",
                "Rest a while by the fire. It mends more than skin.",
                "Tough ones carry more gold. Weak ones carry their friends.",
                "A dash takes you through a blow if you time it. Most don't."
            ]
        },
        looks: [
            { name: "grotto", from: 0,
              rock: "#1E2826", face: "#3E5446", faceStyle: "moss", rim: "#6A8A6A",
              buildingWall: "#4A4232", buildingFace: "#5E5440", lantern: "#E8F0A0", tree: "#2A4A2A",
              floor: { style: "earth", color: "#34402E", grass: 0.8, moss: 0, crackShare: 0 },
              air: { color: "#BFFF73", alpha: 0.9, density: 0.06, size: 0.06, drift: 0.9, blink: true, glows: true },
              moths: { color: "#F0F6E0", alpha: 0.95, fire: 4, lantern: 4 },
              grade: { ambient: "#3E5248", temperature: -0.1, saturation: 1.2, vignette: 0.35 },
              layouts: [
                  [ { kind: "pond", x: -20, y: -3, w: 7, h: 5 },
                    { kind: "stones", x: -13, y: -14, w: 4, h: 3 },
                    { kind: "mushrooms", x: -21, y: 6, w: 3, h: 2 },
                    { kind: "ferns", x: 13, y: -14, w: 4, h: 3 },
                    { kind: "stones", x: 20, y: -2, w: 4, h: 3 },
                    { kind: "mushrooms", x: 12, y: 15, w: 3, h: 2 },
                    { kind: "ferns", x: -12, y: 15, w: 4, h: 2 } ],
                  [ { kind: "pond", x: 20, y: -3, w: 7, h: 5 },
                    { kind: "ferns", x: -20, y: 0, w: 4, h: 3 },
                    { kind: "stones", x: 13, y: -14, w: 5, h: 3 },
                    { kind: "mushrooms", x: -14, y: -13, w: 3, h: 2 },
                    { kind: "stones", x: -12, y: 15, w: 4, h: 2 },
                    { kind: "ferns", x: 13, y: 15, w: 4, h: 2 },
                    { kind: "mushrooms", x: 21, y: 6, w: 3, h: 2 } ],
                  [ { kind: "pond", x: -13, y: -13, w: 8, h: 5 },
                    { kind: "stones", x: 13, y: -13, w: 4, h: 3 },
                    { kind: "ferns", x: -20, y: 1, w: 4, h: 3 },
                    { kind: "mushrooms", x: 20, y: 0, w: 3, h: 2 },
                    { kind: "ferns", x: 12, y: 15, w: 4, h: 2 },
                    { kind: "stones", x: -12, y: 15, w: 4, h: 2 },
                    { kind: "mushrooms", x: 8, y: -9, w: 2, h: 2 } ]
              ] },
            { name: "hall", from: 3,
              rock: "#2A221C", face: "#7A6040", faceStyle: "strata", rim: "#A08860",
              buildingWall: "#5A3E22", buildingFace: "#8A6232", lantern: "#FFC870", tree: "#5A4128",
              floor: { style: "earth", color: "#4A3D2C", grass: 0, moss: 0, crackShare: 0 },
              air: { color: "#FFD99A", alpha: 0.35, density: 0.35, size: 0.045, drift: 0.35, blink: false, glows: false },
              moths: { color: "#F2E2C4", alpha: 0.9, fire: 5, lantern: 3 },
              grade: { ambient: "#5A4E3E", temperature: 0.12, saturation: 1.1, vignette: 0.4 },
              layouts: [
                  [ { kind: "rails", x: -14, y: -15, w: 14, h: 1.4 },
                    { kind: "cart", x: -10, y: -15, w: 2.4, h: 1.8 },
                    { kind: "timber", x: -20, y: 0, w: 3, h: 4 },
                    { kind: "ore", x: 13, y: -13, w: 4, h: 3 },
                    { kind: "crates", x: 20, y: -2, w: 3, h: 3 },
                    { kind: "crates", x: 12, y: 15, w: 3, h: 2 },
                    { kind: "ore", x: -12, y: 15, w: 4, h: 2 } ],
                  [ { kind: "rails", x: 20, y: -3, w: 1.4, h: 12 },
                    { kind: "cart", x: 20, y: 1, w: 1.8, h: 2.4 },
                    { kind: "crates", x: -20, y: -1, w: 3, h: 3 },
                    { kind: "ore", x: -13, y: -13, w: 4, h: 3 },
                    { kind: "timber", x: 13, y: -14, w: 4, h: 3 },
                    { kind: "ore", x: 12, y: 15, w: 4, h: 2 },
                    { kind: "crates", x: -12, y: 15, w: 3, h: 2 } ],
                  [ { kind: "rails", x: 12, y: 15, w: 12, h: 1.4 },
                    { kind: "cart", x: 15, y: 15, w: 2.4, h: 1.8 },
                    { kind: "ore", x: -20, y: 0, w: 4, h: 4 },
                    { kind: "crates", x: 13, y: -13, w: 3, h: 3 },
                    { kind: "timber", x: -13, y: -14, w: 4, h: 3 },
                    { kind: "crates", x: 20, y: -1, w: 3, h: 2 },
                    { kind: "ore", x: -12, y: 15, w: 4, h: 2 } ]
              ] },
            { name: "ember", from: 6,
              rock: "#181414", face: "#3A302E", faceStyle: "basalt", rim: "#8A4A30",
              buildingWall: "#3A2A24", buildingFace: "#4E3A30", lantern: "#FF7A3A", tree: "#262022",
              floor: { style: "basalt", color: "#363030", grass: 0, moss: 0, crackShare: 0 },
              air: { color: "#FF5414", alpha: 0.9, density: 0.05, size: 0.05, drift: 0.8, blink: false, glows: true },
              moths: { color: "#E8C4B0", alpha: 0.85, fire: 2, lantern: 2 },
              grade: { ambient: "#3C2622", temperature: 0.3, saturation: 1.15, vignette: 0.45 },
              layouts: [
                  [ { kind: "cracks", x: -20, y: -1, w: 7, h: 5 },
                    { kind: "basalt", x: -13, y: -14, w: 5, h: 3 },
                    { kind: "coals", x: 13, y: -13, w: 3, h: 2 },
                    { kind: "slag", x: 20, y: -2, w: 4, h: 3 },
                    { kind: "cracks", x: 12, y: 15, w: 8, h: 2 },
                    { kind: "basalt", x: -12, y: 15, w: 5, h: 2 } ],
                  [ { kind: "cracks", x: 20, y: -1, w: 7, h: 5 },
                    { kind: "basalt", x: -20, y: 0, w: 4, h: 4 },
                    { kind: "slag", x: -13, y: -13, w: 4, h: 3 },
                    { kind: "coals", x: 8, y: -9, w: 2, h: 2 },
                    { kind: "basalt", x: 13, y: -14, w: 5, h: 3 },
                    { kind: "cracks", x: -12, y: 15, w: 8, h: 2 },
                    { kind: "coals", x: 12, y: 15, w: 3, h: 2 } ],
                  [ { kind: "cracks", x: -13, y: -13, w: 8, h: 4 },
                    { kind: "basalt", x: 20, y: 0, w: 4, h: 4 },
                    { kind: "slag", x: -20, y: 1, w: 4, h: 3 },
                    { kind: "coals", x: 13, y: -13, w: 3, h: 2 },
                    { kind: "basalt", x: 12, y: 15, w: 5, h: 2 },
                    { kind: "slag", x: -12, y: 15, w: 4, h: 2 } ]
              ] }
        ]
    })
}
