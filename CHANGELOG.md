# Changelog

All notable changes to Shapes & Stone are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the game
uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.7.0] - 2026-11-22

### Added

- **A room's lead ends each string with a retreat, and that is your turn:** after its last blow it steps back, dims, shuts its eyes, loses the ring round it and lets out a higher, softer growl, then stands with its guard down for one beat - 1.16 s at the Standard pace, long enough to charge a full heavy swing and land it. In that beat it strikes nobody, a guardian lead's shield stops nothing, and a charged swing that lands opens it. A lead also no longer cuts a rest short to strike at a knight that charges; outside its rests and its retreat it still strikes a charging knight first. The Hollow Warden keeps its fight for now. ([#363](https://github.com/MisterGC/shapes-and-stone/issues/363))

### Changed

- **A room's lead fights at a slower duel pace:** a lead now winds up, strikes, feints and recovers 1.65 times slower than before - in its strings a blow comes every 1.16 s where it came every 0.7 s - and walks at 2.4 instead of 4.0, slower than your knight with its shield up, so you can back away from it behind the shield. Your windows against it widen by as much: a shield raised up to 13 physics steps (0.22 s) before its blow is a perfect block, where it was 8, a parry has 15 steps where it had 9, and a guardian lead turns its shield at 73 degrees a second instead of 120, so you can walk round it. This is the Standard step of a duel pace that has two more, Swift (1.3 times slower) and Deliberate (twice as slow); the game plays at Standard, and the menu does not offer the choice yet. Your knight's swing, shield, charge and dash, the weak and normal enemies and the Hollow Warden keep their timing. ([#361](https://github.com/MisterGC/shapes-and-stone/issues/361))

## [0.6.0] - 2026-11-20

The knight gets a toolkit: before each dungeon it picks one of three specials - the whirlwind, a stun or a bolt - and a quick move away from its aim and back fires the special's stronger version, while kills in a chain make its blows stronger. A new lead, the slinger, slings metal balls that bounce off walls and off any raised shield, and the Hollow Warden tells, line by line, that it was a knight once. A dungeon opens with a descent intro, critters scurry over its floor, and the smith sells swift boots. Built on Clayground v2026.13.

**Play:** open https://mistergc.dev/shapes-and-stone/ in a current browser.

Not yet playtested by hand: everything new was played by the test pilots, among them one that reacts a quarter of a second late and misses one answer in five; it wins every fight, the Warden at depth 2, 5 and 8 included, with and without each special. Co-op was checked with two games in one process, not over the network. The 16 new sounds - the count of the descent intro, the stun's bash, the bolt's shot and hit, the combo's surge, the ball's shot and bounce, the critter's squash and the Warden's eight lines - still wait for a verdict by ear.

### Added

- **The smith sells swift boots:** a fifth upgrade, next to the sword, the shield, the harness and the blade, makes the knight walk faster - 7 % at level I, 13 % at II and 20 % at III - priced and unlocked by depth like the other four. Charging a swing or raising the shield still slows you by the same share, and the dash goes as far and costs as much as before. The knight panel shows the level, and with gems to sell the smith's sixth ware is bought with 6. The fight bench's pacing pilots pass their checks with the boots at level III. ([#325](https://github.com/MisterGC/shapes-and-stone/issues/325))
- **Critters scurry through the dungeon:** spiders, mice and rats now live on the floor of the rooms and corridors, one or two to a room and a few along the corridors. They run when you come near and get squashed when you walk over one, with a small crunch and a mark left on the floor for the rest of the level. They are there to make the dungeon feel alive and nothing more: a critter never hurts you, never blocks your way, counts for no kill chain and is never picked by the lock-on. In co-op every screen has the same critters in the same places, and each screen lets them run from the knights it shows. The squash waits for a verdict by ear. ([#324](https://github.com/MisterGC/shapes-and-stone/issues/324))
- **The Hollow Warden speaks - it was a knight once:** the Warden now says one short line as its gates shut and one as it falls, spoken and shown as a subtitle above its HP bar. Its lines differ at its first, second and third appearance, and read in order they tell its story: a knight who went down to bring the lost home, was turned to stone like the travellers your pickaxe frees, and never climbed back. From its fourth appearance on it has a last pair of its own. Its stone shows a crack for every time you beat it before, the core's ember glowing in each. The line never holds up the fight - the Warden wakes on the same step as before - and in co-op every screen hears the same line and sees the same cracks. The eight lines are spoken in a voice of their own and wait for a verdict by ear. ([#323](https://github.com/MisterGC/shapes-and-stone/issues/323))
- **The slinger, a lead that slings metal balls:** from the second dungeon on, about a quarter of the rooms' leads are slingers - a block of grey iron with square-ish corners and a visor's slit for an eye, unlike any round enemy. It keeps its distance and slings an iron ball that bounces off the walls and closed doors, four times, and drops at the next wall. A ball hurts you when it reaches you and passes the other enemies; a dash goes through it. Any raised shield bounces it away - a plain block glances it off to the side, a perfect block sends it faster the way you face - and a ball your shield bounced hurts the first enemy it meets as hard as your swing and opens a lead it hits, the slinger too. So a slinger's room plays a little like Pong, the shield your paddle. The slinger attacks in rhythms of its own, one ball then a rest while it bounces about, and has a lead's stance. The witch names the slingers in her reading. The shot and the bounce have sounds of their own, which wait for a verdict by ear. In co-op every screen sees the same ball bounce at the same places. ([#322](https://github.com/MisterGC/shapes-and-stone/issues/322))
- **A kill chain makes your blows stronger:** every third kill in a chain, which already adds a momentum pip, now also makes the knight's sword hit 15 % harder while the chain holds - +15 % after 3 kills, +30 % after 6, at most +45 % from 9 on. It counts for every swing, charged or not, and for the whirlwind's hits, not for the bolt. The HUD shows it right of your special, as *CHAIN +30%*, and it is gone as soon as you take a hit or 2.5 s pass without a kill; the momentum pips stay. A kill bursts with more shards, more sparks and a wider ring the longer the chain runs, up to its eighth kill, and in co-op every screen sees the bigger burst. A flow room clears faster this way; a duel with a room's lead or the Hollow Warden takes about as long as before. ([#321](https://github.com/MisterGC/shapes-and-stone/issues/321))
- **A combo fires a special's stronger version:** move away from your aim, then towards it, and press Q or R2 within a third of a second, and the special you picked goes off stronger for the same mana. The whirlwind becomes a *Tempest* that spins longer and wider and hits harder, the stun a *Quake* that freezes further and for 2.5 s instead of 1.5, the bolt a *Lance*, bigger, faster and twice as hard. It works with the keys, the stick and moves you have rebound, and you keep walking while you enter it; pressed too long after the combo, or after a combo the wrong way round, the button fires the normal special, so nobody who skips the combo loses anything. The stronger one shows its name over the knight with a gold ring and sparks and plays a rising swell over the special's own sound, which waits for a verdict by ear. The choice of specials shows the combo and what each stronger version does. A room's lead and the Hollow Warden are still never frozen or opened by a special. In co-op every screen sees and hears it. ([#320](https://github.com/MisterGC/shapes-and-stone/issues/320))
- **The bolt, a special that hurts from afar:** picked for a dungeon, Q or R2 lets a violet blast loose along your aim for 15 mana. It flies twelve knight-widths at most and hurts the first enemy it meets as hard as a sword swing; a wall or a closed door stops it, and it never hurts a knight. A guardian's shield still takes it from the front, and a room's lead or the Hollow Warden takes only a chip of it on its stance - it wears the stance but never breaks it, so a duel is still won with the sword. The shot and the hit have sounds of their own, which wait for a verdict by ear. In co-op the bolt flies on every screen. ([#319](https://github.com/MisterGC/shapes-and-stone/issues/319))
- **The stun, a special for a crowd:** picked for a dungeon, Q or R2 makes the knight bash with its shield for 15 mana, and every weak and normal enemy within two and a half knight-widths of it, all round, freezes for 1.5 s. A frozen enemy turns ice blue with a white rim and stops breathing; it neither moves nor strikes, an attack it had wound up is over, and your blows land on it without knocking it back or meeting a guardian's shield. A room's lead or the Hollow Warden is never frozen: a stun while it winds up ends that wind-up and it comes straight at you again, its stance as it was and not opened, so a duel is still won on its timing. The bash has a sound of its own, a deep thump with a short iron ring and frost over it, which waits for a verdict by ear. In co-op a stun freezes the enemies on every screen. ([#318](https://github.com/MisterGC/shapes-and-stone/issues/318))
- **The knight picks its special for each dungeon:** before the descent intro counts, a choice shows the specials - the whirlwind, a stun and a bolt - each with its name, a line of what it does and its mana cost, and the count starts once you have picked. The arrows, A and D or the stick move along the cards; 1 to 3, a click, Enter or the pad's A take one, and the choice opens on your last pick. Q or R2 then fire that special and nothing else, the HUD shows it right of the mana bar and the controls hint names it. The smith's balanced blade now lowers whichever special you picked, to 75, 60 and 45 % of its mana at its three levels; the whirlwind still costs 15, 12 and 9. In co-op every knight picks its own, and a knight still choosing holds the count. ([#317](https://github.com/MisterGC/shapes-and-stone/issues/317))
- **A dungeon opens with a descent intro:** entering a dungeon shows its depth and a name for it - *The Cold Galleries*, *The Scorched Crypts* - then counts 3, 2, 1 with a stone-drum knock on each beat and Go an octave up, two seconds in all. Until Go nothing moves and nothing strikes or takes damage, so a fight never starts before you can see the room. In co-op the count starts once every knight has arrived and ends at the same moment on every screen; a knight not there after 6 s holds the others no longer. The camp has no intro. The count's sound waits for a verdict by ear. ([#316](https://github.com/MisterGC/shapes-and-stone/issues/316))
- **A test pilot that plays like a person:** the fight bench has a pilot that answers an attack no sooner than a quarter of a second after it begins and mistimes one in five of its parries and perfect blocks. It plays a flow room, a duel with each kind of lead - a spitter lead's duel is new for it - and the Hollow Warden at depth 2, 5 and 8, and says whether it won and in how many seconds, so how hard a fight is can be judged before anyone plays it. The other test pilots and what they must pass stay as they were. ([#315](https://github.com/MisterGC/shapes-and-stone/issues/315))
- **The person-like test pilot uses a special:** given the whirlwind, the stun or the bolt, the fight bench's pilot that reacts a quarter of a second late and mistimes one answer in five fires it as a person would, just as late and missing as often, and pays it from the knight's own mana. The pacing run now plays it with each of the three in a flow room, a duel with each kind of lead, the slinger's included, and against the Warden at depth 2, and says whether it won, in how many seconds and how often it fired the special. Each fight it loses now says why: what hurt the knight and how much, its misses, and whether its mana ran dry. Without a special it plays exactly as before. ([#344](https://github.com/MisterGC/shapes-and-stone/issues/344))

### Changed

- **The Hollow Warden can be beaten without playing perfectly:** each of its strings now begins with a longer wind-up, a full second instead of half of one, so a parry timed to its ring counts even if you were still swinging as it began. A parry you miss costs 6 to 9 HP instead of 18 to 21, it has a fifth less HP, its floor zones open every 5 s instead of every 3.5 s, and it speeds up less from one appearance to the next. The fight bench's pilot that reacts a quarter of a second late and mistimes one parry in five now beats it at depth 2, 5 and 8 in 76 to 80 s, where it fell within 23 s before; mashing or holding a charge still loses to it. ([#330](https://github.com/MisterGC/shapes-and-stone/issues/330))
- **A duel's slow motion comes from Clayground:** an opening slows the fight as before, and in co-op only the picture. Under it is now Clayground's own slow motion, which counts the game's clock, not the wall clock. The game no longer sets the physics speed itself, and its fight music bench checks on CI that the dungeon song moves to its duel part where no audio device plays it. ([#314](https://github.com/MisterGC/shapes-and-stone/issues/314))

### Fixed

- **The campfire heals on the game's clock:** resting at a camp's fire gives the same HP and mana for the same time in the game on any machine. It used to count the wall clock, so on a slow computer or in a slow browser the fire could heal a knight more or less than the time that had passed in the game. ([#345](https://github.com/MisterGC/shapes-and-stone/issues/345))

## [0.5.0] - 2026-11-14

Fights have two rhythms: most rooms are a fast flow of weak enemies that fall to a stroke or two, kill after kill building a chain; a room's lead is a duel, won by reading its strings and striking while it is open, and the music and the view turn to it; and every third dungeon ends in the Hollow Warden's boss room. Built on Clayground v2026.11.1.

**Play:** open https://mistergc.dev/shapes-and-stone/ in a current browser.

Not yet playtested by hand: the Warden at depth 5 and 8, and a duel under the rule that mashing parries no lead; the test pilots played them. The four new sounds - the dungeon song's duel part, the lead's growl, the boss song and the Warden's toll - still wait for a verdict by ear.

### Added

- **Kill chains:** kills in quick succession build a chain. Each kill within 2.5 s of the last climbs the death sound a step of the dungeon song's scale and gets a short crunchy hit stop, and every third kill in a chain adds a momentum pip. A hit taken or a longer pause breaks the chain. ([#270](https://github.com/MisterGC/shapes-and-stone/issues/270))
- **A room's lead stands its ground:** the one tough enemy a room may hold no longer flinches - no blow knocks it back or staggers it, and it keeps winding up while you hit it. A blow does a tenth of its damage and wears down the stance bar under the lead. A parry, a perfect block, a charged swing landed while it recovers from its attack, or its stance worn down to nothing opens it: it shows OPEN and reels for 1.5 s, and every blow in that time does one and a half times its damage. Mashing and holding a charge parry no lead: a swing begun right after another, and a charged swing, do not count as a parry, so only a deliberate swing timed to its lunge does. A lead has many times the HP of the enemies around it, so it falls in its openings, not to a few swings; a grunt or guardian lead has a third less HP than a spitter lead, so a duel with one does not drag on. In co-op an opening shows on every screen. ([#271](https://github.com/MisterGC/shapes-and-stone/issues/271), [#288](https://github.com/MisterGC/shapes-and-stone/issues/288))
- **A room's lead strikes in strings:** each kind of lead - grunt, guardian, spitter - attacks in rhythms of its own, strikes and rests on a steady beat, and the parry ring closes on every beat. Some wind-ups are feints: the ring stops short, holds, then closes. A knight who stands in a lead's reach charging a swing gets struck first, and the hit cancels the charge; a charge built outside its reach and let go in a rest still opens it. ([#272](https://github.com/MisterGC/shapes-and-stone/issues/272))
- **A duel sounds and looks like one:** while a room's lead is after the knight, the dungeon song moves to a duel part - a heartbeat on the kick, a low drone, a harp ticking late in each bar - and back to its flow part once the lead falls, gives up or is out of reach. A lead growls as it spots the knight, and every parry, perfect block and opening in a duel plays a brass sting. A lock on a lead (F, the middle button or L2) closes the view in a little round the knight, and an opening plays a short slow motion; in co-op the slow motion slows only the picture, as the hit stop does. ([#273](https://github.com/MisterGC/shapes-and-stone/issues/273))
- **A perfect block sends a spitter's shot back:** raised just before the shot meets it, the shield sends it back along its line, faster. On its way back it hurts no knight; the first enemy it meets takes a blow as hard as the knight's swing, and a room's lead it hits is opened, so a perfect block answers a lead that shoots. A plain block still ends the shot. In co-op the shot flies back on every screen. ([#283](https://github.com/MisterGC/shapes-and-stone/issues/283))
- **The Hollow Warden:** every third dungeon - depth 2, 5, 8 and on - ends in a boss room in front of the exit stairs. Until every knight still standing is in, the Warden sleeps and a blow glances off it; then its gates shut, its name shows as a banner and its HP as a bar. The Warden, a large hollow stone hexagon, duels in three strings of its own, and its wind-up and its strike ring with a deep hollow stone toll in the dungeon song's key - the wind-up on a higher note, the strike on the low root - so you hear it apart from the small ones, which keep their scream. At half its HP its core glows, weak grunts come out of the floor, it plays a quarter faster, the light turns red, its own song moves to a second part, and zones open under the knights that warn with the slits' ring before they hurt. Beaten, it opens the way on, drops a large pile of gold, shows a victory banner and heals every knight to full HP and mana, a fallen one too. Each time it comes back it has 5 % more HP and plays 5 % faster; the depth adds to its HP only up to depth 4, since the smith's sword stops growing at depth 5, so it stays beatable at depth 2, 5 and 8 alike: the test pilot that parries every string beats it in a little over a minute each time, and mashing or holding a charge loses to it. In co-op every screen sees the same Warden, phase and adds. ([#274](https://github.com/MisterGC/shapes-and-stone/issues/274), [#287](https://github.com/MisterGC/shapes-and-stone/issues/287), [#289](https://github.com/MisterGC/shapes-and-stone/issues/289))

### Changed

- **Enemies keep pace with the smith's sword:** a weak or normal enemy falls to one charged swing or two to three swings at every depth, with the sword the smith has usually sold by then. Enemy HP used to stay the same all the way down while the sword added up to 12 attack, so every fight got shorter the deeper you went. Now weak and normal enemies start with less - a weak grunt has 22 HP at depth 0 instead of 46, a normal one 28 instead of 60 - and enemies gain a fifth more HP with each depth. ([#268](https://github.com/MisterGC/shapes-and-stone/issues/268))
- **A charged swing has its own recovery:** it cost no more than a click, the same 0.5 s before the next swing. Now, once its arc has faded, the knight recovers half a second before it swings again, and a charged swing that hits no enemy leaves the knight without shield, dash or whirlwind for that time. A charged swing that parries takes the recovery away. ([#268](https://github.com/MisterGC/shapes-and-stone/issues/268))
- **At most one tough enemy per room, its lead:** tough enemies used to grow to 60 % of a dungeon's enemies deep down; with leads now duels, that would make every room a slow one. Now a room holds at most one, its lead, and the rest are weak or normal. One room in three has a lead at depth 0, never the start room, more with each depth and every room from depth 8 on. A dungeon holds as many enemies as before, so the rooms without a lead fight in larger groups, and a creature out of a spawn hole is never tough. The dungeon master panel gets a row, *Rooms with a lead*, that sets the share for the next dungeon. ([#269](https://github.com/MisterGC/shapes-and-stone/issues/269))

### Fixed

- **A shield held toward a spitter stops its shot from a slant too:** the shot flew from the spitter's corner at the knight's corner, so it could pass a knight standing at a slant beside its middle, outside the shield. It now flies from the spitter's middle at the knight's. ([#272](https://github.com/MisterGC/shapes-and-stone/issues/272))

## [0.4.2] - 2026-11-06

Every control can be rebound, for mouse and keyboard and for a gamepad, on a new Control Input page; the game says when a gamepad connects or leaves; and in the browser a gamepad plays in Firefox too. Built on Clayground v2026.11.1.

**Play:** open https://mistergc.dev/shapes-and-stone/ in a current browser.

### Added

- **Control Input page:** under Sound in the pause menu and on the title, a page lists the devices there are - keyboard, mouse and each gamepad by name, the one in use marked - and every control side by side, for mouse and keyboard and for a gamepad. ([#220](https://github.com/MisterGC/shapes-and-stone/issues/220))
- **Rebind any control:** pick a control in either column and press the new key, mouse button or pad button. A binding another control already has swaps with it, Esc or B cancels, and *Reset* under each column brings its defaults back; opening the menu stays fixed so nobody locks themselves out. Every change is saved at once, so it survives a restart and a browser reload. ([#221](https://github.com/MisterGC/shapes-and-stone/issues/221), [#242](https://github.com/MisterGC/shapes-and-stone/issues/242))
- **Gamepad notices:** a short notice names a gamepad when it connects or leaves, on the title, in the lobby and in a game; when the pad that played leaves, it says the keyboard and mouse play now. In the browser the title asks you to press a button on your pad until the browser lists it. ([#219](https://github.com/MisterGC/shapes-and-stone/issues/219))

### Changed

- **One table for every control:** the keys, the mouse, the gamepad, the swing and every controls hint read the same table, so the hints now also name F, V and the middle mouse button. ([#218](https://github.com/MisterGC/shapes-and-stone/issues/218))
- **A gamepad plays in Firefox:** the browser version runs on Clayground v2026.11.1, which reads a pad in Firefox wherever Firefox reads it cleanly - every pad on Linux, SteamOS included, and every pad but Nintendo's Switch pads on macOS and Windows. Such a Switch pad is listed on the Control Input page with "no input in this browser" and plays in Chrome. ([#240](https://github.com/MisterGC/shapes-and-stone/issues/240))
- **A Nintendo pad shows its own letters in the browser:** the browser does not say what is printed on a pad's buttons, so a Switch pad read as an Xbox pad - its B showed A, and its A cancelled. Now the Control Input page, the menus and the hints name a Nintendo pad's buttons as printed. ([#237](https://github.com/MisterGC/shapes-and-stone/issues/237))

### Fixed

- **Control Input on the title takes a gamepad on its first press**, without a game started first; that press only takes the pad and chooses nothing. ([#236](https://github.com/MisterGC/shapes-and-stone/issues/236))
- **A resting mouse no longer takes the pick back from the gamepad** on the Control Input page when a note appears or clears. ([#243](https://github.com/MisterGC/shapes-and-stone/issues/243))

## [0.4.1] - 2026-11-01

The browser version has its sound again.

**Play:** open https://mistergc.dev/shapes-and-stone/ in a current browser.

### Fixed

- **No sound in the browser:** since the sound moved to the sound factory's `sound/` folder, the browser version left it out, so 0.4.0 played no music, ambience, effect or voice there. The web bundle now carries the cue sheet's sound files, and a sound file the game names that the bundle does not carry stops the build. (#216)

## [0.4.0] - 2026-11-01

The knight and every menu play with a gamepad, a Steam Deck's built-in controls too; the deep has veins to dig, spawn holes that answer greed and petrified travellers to free; the camp is a cave with a pond to fish; fights become duels; and every sound comes from the sound factory. Built on Clayground v2026.11.

**Play:** open https://mistergc.dev/shapes-and-stone/ in a current browser. A gamepad works in Chrome; Firefox lists it but it drives nothing yet.

### Added

- **Gamepad:** the knight plays with a gamepad, through Clayground's `GameController` in its `full` layout: the left stick moves, the right stick aims, R1 strikes and charges, L1 shields, B dashes, A talks, X and Y drink a potion and a draught, R2 whirls, L2 locks on and Select opens the knight panel; in a dialogue the stick picks a ware and X buys it. A pad takes over when it is used and the keyboard when a key goes down, the mouse takes the aim back when it moves, and while a pad is in use the controls hint, the talk prompts and the dialogue name its buttons. The pad bench plays it with the dojo's synthetic pad alone. (#200)
- **Menus with a gamepad:** the stick or the D-pad picks on the title, the pause menu, the fallen screen, the dungeon master panel and the lobby (held, it repeats), A confirms, B goes back and X generates on the panel; Start pauses and resumes. The pad cannot type a code, so Join takes the one typed or pasted. Under a menu the stick moves no knight and B makes no dash. (#201)
- **Steam Deck:** the README says how to add the Linux AppImage to Steam as a non-Steam game and play it in Game Mode on the Deck's built-in controls. While a pad is in use the hints of the title, the pause menu, the fallen screen, the dungeon master's panel and the knight panel, and the HUD's potions, name its buttons instead of keys. The Deck bench renders the HUD and every menu at 1280x800, with the keyboard and with a pad, and checks the size and fit of every text on screen. (#202)
- **The dungeon's music follows the fight:** the more enemies near the knight are after it, up to three, the more the dungeon's song plays - a pulse of kick and snare with the first, a horn's counter-line and brushes with the second and third - and it settles slowly once they give up or fall (`Balance.music`). (#191)
- **The villagers speak and their mouths move:** the innkeeper's, the blacksmith's and the witch's greetings are voiced lines from the sound factory, and while one plays the speaker shows a mouth that follows the line's lip-sync cues, resting once the line is over. (#191)
- **Veins and gems:** veins glint in the dungeon's walls, each in a stretch of rough rock face. Aimed at a vein in reach, the left button folds the sword into a pickaxe and strikes on a closing ring: a strike on the beat is clean, any other chips. The last strike splits the stone and the cut gem - amber tetrahedron near the top, up to an icosahedron deep down - rises over the knight under CLEAN CUT or CHIPPED and drops into a pouch; the smith buys the pouch, and a fallen knight drops it. In a session the host splits a vein on every screen and gives its gem to the first knight that split it (`Balance.deep`). (#155, #156, #169)
- **Spawn holes:** a room with a vein has a hole low in its north wall. Each gem cut there may wake it, the likelier the more the gem is worth and the more knights there are; woken, it puffs dust, opens its eyes, sends waves of the depth's creatures and crumbles shut for good (`Balance.deep.hole`). (#157, #175)
- **Petrified travellers:** a miner caught mid-swing or a lost traveller stands grey in a vein's rock face, and the same pickaxe frees them on a slower ring. A freed miner works beside the vein until the hole sends creatures; a lost one thanks the knight and walks off. Striking a traveller never wakes the hole. (#158)
- **Travellers by the camp's fire:** travellers freed in a run sit round the fire of every later camp of that run, and the rare specials - a healer, a cook, a lamplighter - join the camps for good, each with a comfort at the fire and none with fight power. The title and the fall screen say who was freed tonight and who is with the camps. (#159)
- **Fishing:** a camp's pond can be fished: cast with the left button, click on the bite, hold to reel and let go while the fish thrashes. Five kinds of fish from cave minnow to the rare glimmerfin, five bites a camp; the innkeeper buys the creel and the cave cat takes a fish and purrs. (#188)

### Changed

- **Duel fights:** a full charge is kept until release and spins all round, the knight moves slower while charging; F or the middle button locks on an enemy, so W/S close and open the distance and A/D circle it; a grunt circles before it strikes; below 35% health a blood-red edge beats with the heart, and a potion fills the bar over a second. (#186)
- **The camp is a cave:** a seeded cave about 1.5x the old box, with outcrops and bays, an overhanging lip with stalactites, and a tavern and a smithy whose walls cast the campfire's shadows. (#145)
- **Text size:** every text a player reads is at least 12 px, the size Valve recommends for the Steam Deck's 1280x800 - the mana, the depth gauge, the dialogue's and the menus' hints, the lobby's notes, the talk prompts and the speech bubbles were 9 to 11 px. (#202)
- **Fourteen sounds revised and approved:** the village's night ambience, the creature's burst, the camp's anvil, crackle, creak and hiss, the coin, the deep's crumble, freed chord and tink, the sword's hit, the shield's clang, the sword's swing and the knight's footstep, now a dry heel tap, revised in the sound factory's studio and delivered with their renders. Five of them use a layer's drive or an LFO's shape, new in Clayground v2026.11. (#199)
- **The sword's swing, the shield's clang and the deep's crumble come from design files:** each is the sound factory's stock template - `swing`, `metal-hit`, `crumble` - with its macro knobs set and a few values overridden, compiled to the recipe the game plays and tuned with `sp tweak`. The crumble loses its harsh edge (the report's `harsh_2_5k` flag); the swing sits a little lower and darker. Clayground v2026.11 has the curves, FM, bursts and coloured noise the templates use. (#195)
- **All of the game's sound comes from the sound factory** (#191): the title's, the camp's and the dungeon's music are songs in the factory's note notation that Clayground's `SongPlayer` plays live; the dungeon's and the camp's ambience, the fight's, the menus', the coin's and the fishing sounds and the cat's purr are recipes in `sound/`; the greetings and the knight's whirlwind shout are spoken by vocli and lip-synced. Every one is a cue in `sound/cues.json` with its sound report, waiting for a person's verdict. The hand-made wav and mp3 files and `tools/fishing_sounds.py` are gone.
- **The deep's, the camp's and the knight's sounds** come from the sound factory: the chink, the tink, the crumble, the rumble, the groan, the freed chord, the camp's crackle, anvil, drip, creak and hiss, the potion and the heartbeat are recipes in `sound/`, listed with their sound reports in the cue sheet `sound/cues.json`. Ten play live through Clayground's `SfxPlayer`, a little different each time, the chink, the tink, the anvil and the drip transposed per play; the crackle, the creak and the hiss play their renders, pitched per play as before, since their pitch is in noise and filters a recipe's detune does not move. The Python scripts that synthesised them are gone. (#190)

### Fixed

- **Enemies stuck in a wall:** an enemy flush under a wall never saw the knight and could patrol into the wall for good, since its sight and its path were measured from its top-left corner. It now sees and walks from its middle, and patrols between cells it can reach in a straight line. (#184)

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

[Unreleased]: https://github.com/MisterGC/shapes-and-stone/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.6.0
[0.5.0]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.5.0
[0.4.2]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.4.2
[0.4.1]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.4.1
[0.4.0]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.4.0
[0.3.0]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.3.0
[0.2.2]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.2.2
[0.2.1]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.2.1
[0.2.0]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.2.0
[0.1.0]: https://github.com/MisterGC/shapes-and-stone/releases/tag/v0.1.0
