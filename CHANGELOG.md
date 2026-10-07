# Changelog

All notable changes to Shapes & Stone are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the game
uses [Semantic Versioning](https://semver.org/).

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

[0.1.0]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.1.0
