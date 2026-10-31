# Changelog

All notable changes to Shapes & Stone are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the game
uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **The dungeon's music follows the fight:** the more enemies near the knight are after it, up to three, the more the dungeon's song plays - a pulse of kick and snare with the first, a horn's counter-line and brushes with the second and third - and it settles slowly once they give up or fall (`Balance.music`). (#191)
- **The villagers speak and their mouths move:** the innkeeper's, the blacksmith's and the witch's greetings are voiced lines from the sound factory, and while one plays the speaker shows a mouth that follows the line's lip-sync cues, resting once the line is over. (#191)

### Changed

- **Fourteen sounds revised and approved:** the village's night ambience, the creature's burst, the camp's anvil, crackle, creak and hiss, the coin, the deep's crumble, freed chord and tink, the sword's hit, the shield's clang, the sword's swing and the knight's footstep, now a dry heel tap, revised in the sound factory's studio and delivered with their renders. Five of them use a layer's drive or an LFO's shape, which need Clayground `issue-452`. (#199)
- **The sword's swing, the shield's clang and the deep's crumble come from design files:** each is the sound factory's stock template - `swing`, `metal-hit`, `crumble` - with its macro knobs set and a few values overridden, compiled to the recipe the game plays and tuned with `sp tweak`. The crumble loses its harsh edge (the report's `harsh_2_5k` flag); the swing sits a little lower and darker. Built on Clayground `7e93c11` (issue-452), which has the curves, FM, bursts and coloured noise the templates use. (#195)
- **All of the game's sound comes from the sound factory** (#191): the title's, the camp's and the dungeon's music are songs in the factory's note notation that Clayground's `SongPlayer` plays live; the dungeon's and the camp's ambience, the fight's, the menus', the coin's and the fishing sounds and the cat's purr are recipes in `sound/`; the greetings and the knight's whirlwind shout are spoken by vocli and lip-synced. Every one is a cue in `sound/cues.json` with its sound report, waiting for a person's verdict. The hand-made wav and mp3 files and `tools/fishing_sounds.py` are gone. Built on Clayground `8574700` (issue-439, on release/v2026.11).

- **The deep's, the camp's and the knight's sounds** come from the sound factory: the chink, the tink, the crumble, the rumble, the groan, the freed chord, the camp's crackle, anvil, drip, creak and hiss, the potion and the heartbeat are recipes in `sound/`, listed with their sound reports in the cue sheet `sound/cues.json`. Ten play live through Clayground's `SfxPlayer`, a little different each time, the chink, the tink, the anvil and the drip transposed per play; the crackle, the creak and the hiss play their renders, pitched per play as before, since their pitch is in noise and filters a recipe's detune does not move. The Python scripts that synthesised them are gone. Built on Clayground `8574700` (issue-439, on release/v2026.11). (#190)

## [0.3.0] - 2026-10-12

Dungeons fight back and hide things: spike plates and arrow slits you learn to read, doors you shut and enemies bash, loops and secret rooms to find, urns, barrels, crates and crystals to break for gold, and a Dungeon Master panel to tune the next dungeon before you enter it. Built on Clayground v2026.9.

**Play:** open https://mistergc.dev/shapes-and-stone/ in a current browser.

### Added

- **Dungeon features:** after its rooms and corridors are carved, a dungeon lays out its features, each kind from its own stream of the seed, as many per room as its danger asks (`Balance.dungeon`), never in the start room, on a doorway or in a corridor, and clear of the entrance and the exit. The dojo's `features` scenario shows every kind, one arrow slit a room. (#122)
- **Breakables:** clay urns, wooden crates and barrels, and crystal clusters, glowing and rarer the shallower, stand in a dungeon's rooms and block the way like a small wall. Urns and barrels stand upright, drawn from the side and smaller than a knight (`Balance.dungeon.standing`). A swing breaks the nearest in its arc, a charged swing and the whirlwind every one they reach; only a charged swing breaks a crystal. Each may hold gold by its kind (`Balance.dungeon.loot`), a crystal more often and more, the deeper the more; it drops where the thing stood. In a session the host rolls it, and a thing broken on one screen is broken on every screen. (#123, #135)
- **Spike plates:** a floor stone with small holes stands in some rooms, more often the higher the danger. Stepped on, it clicks, and 0.25 s later spikes rise (`Balance.dungeon.spikeDelay`): a knight still on it takes `spikeDamage`, more the deeper, never more than a quarter of its max HP; a dash at the click saves it. A plate fires once and stays sprung, bent spikes over a stain. Only knights set it off and take its damage; in a session it is sprung on every screen and each knight's own game judges the spikes on it. (#124)
- **Arrow slits:** a narrow opening in a room's wall fires across the room in a rhythm you can learn (`Balance.dungeon.slitRhythms`) - a single shot, "1 - 1 - pause", a volley, and at a higher danger a stream or a hail - at most one a room, 0.6 a room at high danger. Before each shot a ring closes on it and it glows, as an enemy's wind-up does. Every slit leaves a lane or a gap in its rhythm long enough to walk past. An arrow hurts only knights; a held shield stops it, a perfect block sends it back to its slit and a dash passes through it. In a session every screen fires the same arrow at the same session time, and each knight's own game judges the arrows on it. (#125, #135)
- **Loops:** some rooms get a second entrance - one corridor off the chain of rooms at low danger, two at middle, three at high (`Balance.dungeon.extraCorridors`) - between rooms close but not next in the chain, so a dungeon has ways around to flank and to escape. A seed and danger carve the same on every screen; no such corridor cuts through or opens into another room. (#126)
- **Doors:** some room entrances get a door, more often the higher the danger (`Balance.dungeon.doorShare`), one knight wide, so a doorway becomes a chokepoint. E beside it opens or closes it; closed it blocks knights, enemies, their shots and their sight. An enemy chasing through a closed door stops, winds up with its ring for 1.5 s (`doorBash`) and bursts it open, and a bashed door stays open. In a session the host owns the doors, and a door opened on one screen is open on every screen. (#127)
- **Secret rooms:** some dungeons hide a chamber behind one cell of a room's wall, more of them the higher the danger (`Balance.dungeon.secrets`). The cell shows a hairline crack with dust breathing out of it; a dash straight into it bursts it open, one at a flat angle glances off with a puff of dust. Until then the chamber is rock, on the minimap too, and never on the way to the exit. Inside waits a cache of urns and crates, sometimes a crystal cluster, with more gold than anywhere else (`cacheLoot`). The witch tells when the next dungeon hides one, the fallen screen counts the secrets found, and in a session the host owns them: a secret opened on one screen is open on every screen. (#128)
- **Dungeon master mode:** with *Dungeon Master* ticked on the title, a solo player or the host sees a panel before each dungeon: enemies, spike plates, arrow slits and breakables per room, rooms, base depth and relative difficulty, at the values the game would use. Changed values hold for that dungeon and the next ones and are kept; *Generate* previews the dungeon with its enemies, breakables and traps, again on a new seed, and *Go* enters it. *Copy settings* puts them on the clipboard as JSON, *Paste settings* reads them back. In a session every knight plays the host's dungeon, and the joiners are told while the host prepares it (`Balance.dungeonMaster`). (#142)

### Changed

- **Enemy paths** come from Clayground's `GridPathfinder` instead of the game's own A*, the same paths as before; a closed door counts as a few cells more, so an enemy takes a short way around one when there is one. (#127)

### Fixed

- **A blow during a hit stop froze the game:** a knight hit or an enemy thrown off the shield while a hit stop held the physics hung the game at full CPU, since v0.2.0. The knockback now lands as far as on any other step and the game goes on. (#138)

## [0.2.2] - 2026-10-11

Fight for your whirlwind: blows that land earn the momentum Q spends, a shield bash follows a swing, and dungeons are darker, fuller and harder, their enemies staying in their rooms. Music and sound have their own volume, and the knight panel shows what you carry. Built on Clayground v2026.9.

**Play:** open https://mistergc.dev/shapes-and-stone/ in a current browser.

### Added

- **Music and Sound volume** in the Esc menu, in tenths with A/D, the arrows or a click, kept for the next visit; M still mutes everything. (c0b4b89)
- **The knight panel** on C: HP, mana, damage, depth, gold, potions, draughts and the smith's upgrades with what each level gives; the game runs on while it is open. (c0b4b89)
- **Potions and mana draughts at the belt:** a vial of each the knight carries hangs beside it with the count. (c0b4b89, f1a6c5d)
- **Gold clinks** when it is picked up. (c0b4b89)
- **Footsteps** while the knight walks; one held at a wall makes none. (3d67868)
- **Sword-and-shield bash:** a right-click within 0.35 s of a swing lands the sword, then lunges behind the shield and shoves the enemies in front back, breaking off their attack (a guardian's guard breaks), for 6 mana. (e3caad5, dcc864f)
- **Momentum:** blows that land fill 4 pips beside the mana bar - a swing, heavy blow or bash 1, a parry or perfect block 2. (dd2ff23)
- **Breakable bones:** a swing or a whirlwind that reaches a heap of bones breaks it into splinters. (e40a44b)
- **Strike numbers:** the damage of a hit shows over the enemy, and healing and gold picked up show over the knight, in normal play. (3d67868)

### Changed

- **Dark beyond the light again:** outside the lantern and the torches the dungeon is near black and an enemy is not seen until the light reaches it, its eyes no longer glow; a wall torch lights a smaller stretch. (4069bfd, 3d67868)
- **The whirlwind** is let loose with Q and needs full momentum, which it spends; a full charge held into a dash no longer whirls. A fall loses the momentum, a new level keeps it. (dd2ff23)
- **Harder from the start:** a dungeon at depth 0 holds 10 to 15 enemies (was 8 to 12), up to 26 deeper down; enemies have about a fifth more HP and hit 2 harder. Each depth still adds as much as before. (dcc864f)
- **Enemies stay in their rooms:** they notice a knight only within 7 wu, hunt where they last saw one, and go back to their patrol after 4 s out of sight, so a room no longer follows the knight through the dungeon. (a246a0e)
- **The minimap** shows no enemies; in a session it always shows the other knights in their colours, also in parts no one has explored. (8e698f9)

### Fixed

- In the browser the music of the camp, the dungeon and the title loops instead of falling silent after one pass. (3d67868)
- In the browser the music plays at the remembered Music volume from the start, not at full until the volume is changed once. (0e20fcc)

## [0.2.1] - 2026-10-10

Fights in the browser keep every key, and the dungeon is bigger and less pitch black. Built on Clayground v2026.9.

**Play:** open https://mistergc.dev/shapes-and-stone/ in a current browser, or download the package for your system from the [release page](https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.2.1) (macOS, Windows, Linux AppImage; nothing to install).

### Changed

- **Bigger dungeons:** a dungeon has 9 to 12 rooms and 8 to 12 enemies at depth 0, up to 22 deeper down. (#118)
- **Very dark, not pitch black:** the dungeon outside the lamps' light stays readable. (#117)
- **The highest danger** lies in bones and dried blood, without glowing embers on the floor or in the air. (#117)

### Fixed

- In the browser a key pressed or let go while a mouse button is down reaches the knight, so it no longer walks on by itself or ignores a direction during a swing. (#116)

## [0.2.0] - 2026-10-10

Fights that read and reward skill, and a descent that follows the party: the dungeon grows with how well you did and how many you are, a fallen friend can be lifted up, and the camp prepares the next dungeon. Built on Clayground v2026.9.

**Play:** open https://mistergc.dev/shapes-and-stone/ in a current browser, or download the package for your system from the [release page](https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.2.0) (macOS, Windows, Linux AppImage; nothing to install).

### Added

### The fight

- **A blocked blow feels like a success:** it looks, sounds and feels different from a smaller hit. (#75)
- **The perfect block:** raise the shield just before a blow lands and it does no damage and staggers the attacker. (#76)
- **A ring shows when to parry:** it closes on an enemy's wind-up as the parry window opens. (#78)
- **The heavy swing:** hold the left button to charge a swing that breaks a guardian's guard. (#79)
- **The crushing blow:** tough enemies wind up a blow that breaks a held shield, but not a perfect block. (#80)
- **The whirlwind:** a full charge let go right around a dash's start spins the knight forward. (#89)
- **The smith improves the sword or the shield** for gold. (#81)
- **You see at once** when the knight is hurt and when the shield has run dry. (#77)

### The descent

- **Danger that follows you:** each depth is a range of difficulty, and how much HP the last dungeon cost picks the spot; the dungeon's look tells low, middle and high danger apart. (#96)
- **A descent gauge** shows how deep the knight is. (#97)
- **The record:** the party's deepest descent shows on the title, the lobby, the HUD and the fall screen, and passing it raises a banner on every screen. (#101)
- **The camp prepares the next dungeon:** the witch reads it, the innkeeper sells a mana draught, and the smith's upgrades have levels that last the run. (#98)

### Co-op

- **Go again together:** when the whole party has fallen, the host starts the next run for everyone without leaving the session. (#99)
- **Lift a fallen ally:** stand beside a fallen knight to lift it up; a knight still down rises at the next camp. (#100)
- **More knights meet more resistance:** a dungeon's enemies and their HP grow with the party. (#102)

### Changed

- **Playtest refinements:** a landed hit throws the knight back, enemies scream as they wind up, the whirlwind gets a shout, the shield is steel with a clang, and mana pays for blocks, dashes and whirlwinds and comes back by resting. (#94)

### Fixed

- After an overlay closes, the keys move the knight again without a click. (#73)
- With a villager's dialogue open the knight stands, so the dialogue no longer stays open into the dungeon; Esc closes it. (#90)
- In the browser the title music starts on the first key press or click instead of staying silent. (#112)

## [0.1.0] - 2026-10-07

The first playable Shapes & Stone: a knight goes down a dungeon depth by depth, alone or with friends, natively over LAN or in the browser over the internet. Fighting is skill - read the attack, block, parry or dash - and every depth is harder than the last. Built on Clayground v2026.8.

**Play:** open https://mistergc.dev/shapes-and-stone/ in a current browser, or download the package for your system from the [release page](https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.1.0) (macOS, Windows, Linux AppImage; nothing to install).

### Added

### The game

- **A run with depth.** Each dungeon is a numbered depth and deeper is harder; you see how deep you are, and your best depth is kept between runs, in the browser too. (#2, #37)
- **The fall ends the run** with how deep you got, your kills and time, and you can go again. (#6)
- **Fights you answer.** Every enemy attack has a readable wind-up; block it, parry it in a short window, or dash out of it. Blocking costs mana, a parry refunds it, and the campfire refills it. (#35, #36)
- **Gold and shops.** Kills drop gold; the innkeeper sells a health potion, the smith a damage or max-HP upgrade for the run. (#38)
- **A screen a first-time player can read:** a controls hint, and Esc pauses - or, in a co-op session, opens a menu without stopping the world for the others. (#39)
- **Sound outside the dojo**, and M mutes it. (#31)
- **Atmosphere:** a dark dungeon lit in colour, procedural ground and walls, cel-shaded characters, hits you feel - and a hit shakes only the screen of the player it concerns. (#10, #16)
- The village with its campfire, NPCs and the witch; grunts, spitters and guardians; shield, dash push and the parry.

### Co-op

- **Friends play together**, natively over LAN or over the internet with a code, and in the browser over the internet - a native host takes browser players too. (#9, #40, #41)
- **One world for everyone:** the host runs the enemies and every player sees the same ones, in the same place and state. (#13, #14)
- **Fair hits:** a hit on an enemy counts once, whoever lands it; an attack on a player is judged by that player's own game, so a block or parry you see is the one that counts. (#17, #18)
- **Co-op death:** a downed knight shows on every screen, and when the whole party is down the run ends for everyone with the party's summary. (#19)
- **Joining late, leaving and losing the host** all end somewhere sensible: a late joiner starts in the host's level with the live enemies, enemies drop a player who left, and losing the host returns you to the title with the reason. (#20)
- The other player's knight looks and sounds like yours. (#15)

### Downloads and the web

- **Native packages** for macOS, Windows and Linux that start without Qt installed, attached to every release. (#41)
- **The browser game on GitHub Pages**, deployed from a release. (#40)

### Changed

- Every fight number sits in one balance table, and enemy and knight timing follows the game clock, so pause and hit stop hold it. (#32, #33)
- Clayground comes in as a git submodule; networking lives in one `Session.qml`. (#11, #12)
- The game takes Clayground's fixes instead of its own workarounds: no CMake 4 policy flag, Clayground's packaging, session properties and host-lost reasons. (#49)

### For developers

- Every PR gets a headless build check. (#23)
- A scripted fight bench reports the same numbers on every run of a seed. (#34)
- A same-world check runs two games, host and joiner, and compares every enemy's position, HP and AI state; it passes 10 Local and 10 Cloud runs in a row. (#14, #64)

[Unreleased]: https://github.com/MisterGC/shapes-and-stone/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.3.0
[0.2.2]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.2.2
[0.2.1]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.2.1
[0.2.0]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.2.0
[0.1.0]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.1.0
