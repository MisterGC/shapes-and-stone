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
        // Whirlwind: a full charge let go at most whirlWindow physics steps
        // before or after a dash starts spins the knight forward instead,
        // whirlSpeed for whirlDuration seconds along the dash, no damage
        // taken, and hits every standing enemy within whirlReach of it,
        // centre to centre, once, for whirlSwing times atk, through a
        // guardian's shield. Outside the window a full charge swings heavy
        // and a dash cancels the charge
        whirlWindow: 6,
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
        tierHp: [18, 30, 42],
        // Per type: HP on top of the tier, attack, defense, speeds
        grunt: { hpBonus: 0, atk: 10, def: 2, chaseSpeed: 4.0, patrolSpeed: 1.5 },
        guardian: { hpBonus: 10, atk: 10, def: 2, chaseSpeed: 4.0, patrolSpeed: 1.5 },
        spitter: { hpBonus: -6, atk: 8, def: 0, chaseSpeed: 2.4, patrolSpeed: 0.9 },
        // How often an enemy decides, and how often a chase re-plans its path
        thinkInterval: 0.1,
        repathInterval: 1.0,
        // Patrol waypoints lie this far from the spawn point
        patrolRadius: 2,
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
        enemiesMin: 8,
        enemiesMax: 12,
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
        enemiesCap: 22,
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
}
