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
        attackCooldown: 0.5,
        // Damage of a swing, as a multiple of atk
        blockingSwing: 0.85,
        dashingSwing: 1.5,
        parrySwing: 2,
        // Shield: blocks hits from within the arc, lets this share through
        shieldArc: 60,
        blockedShare: 0.3,
        blockSpeed: 0.4,    // share of move and dash speed while blocking
        // Dash: no damage taken while it lasts
        dashSpeed: 40.0,
        dashDuration: 0.15,
        dashCooldown: 0.8,
        // A blocking dash pushes enemies away at this speed
        pushSpeed: 20.0
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
        // The last part of a lunge in which a swing parries it
        parryWindow: 0.15,
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
        // Enemies per dungeon, rolled evenly from min to max
        enemiesMin: 5,
        enemiesMax: 8,
        // Tier rolls: below weak is weak, below normal is normal, else tough
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

    readonly property var campfire: ({
        healPerSecond: 5.0,
        healRadius: 3.0,
        healTick: 0.2
    })
}
