# Multiplayer sync: what lags, why, and how to measure it

Investigation for issue #8 (two instances on one laptop: the other player
trails behind and looks out of place). Verified against clayground
`visual-atmosphere` @ d5de079, whose `plugins/clay_network` is identical
to `origin/release/v2026.8`.

## Root cause

The lag is the remote avatar's render delay, not the transport. The game
sent snapshots at 20 Hz and `RemotePlayer` rendered them 120 ms in the
past (`StateInterpolator.delayMs`). At the knight's full speed of 7.5 Wu/s
that is 0.9 Wu behind the real position, almost a full body length, and
that is what "positions drifting out of sync" looks like side by side:
the avatar trails while you move and catches up 120 ms after you stop.

The signaling mode is not the cause. Cloud (PeerJS) and LAN (embedded
server) only differ in how peers find each other; after ICE the state
travels peer to peer on a WebRTC data channel in both modes (STUN only,
host candidates allowed, so two instances on one machine connect
directly). Measured on this machine the two modes are indistinguishable
once connected: same delay, same 0 to 1 ms round trip, same jitter, zero
drops. Cloud only changes the connection setup (713 ms here versus
1048 ms for LAN, whose ICE phase was slower).

The transport itself is sound for this job: `broadcastState` goes over a
dedicated unordered channel without retransmissions, every update carries
a sequence number so stale ones are dropped, and receives reach QML as
queued events with no polling. Two things in the plugin do contribute and
are filed as clayground issues (listed at the end): snapshots are timestamped with
their arrival time (a burst after a stall compresses the motion and the
avatar jumps), and the interpolation delay is a fixed number the game has
to guess.

## What changed in the game

- `Game.qml` broadcasts one snapshot per physics step (60 Hz) instead of
  a free-running 50 ms timer. The stream now carries exactly the motion
  the simulation produced; at about 90 bytes per update that is 5 to
  6 kB/s per stream on the lossy channel.
- `RemotePlayer.qml` renders 50 ms in the past plus the measured round
  trip (capped at 100 ms), so a LAN session gets 50 ms and an internet
  session gets a buffer that survives its jitter. With a plugin that has
  clayground #291 it switches on `autoDelay` instead and passes the
  sender's timestamp (#290) into the interpolator; the round-trip rule
  stays as the fallback for older plugins.
- `MultiplayerLobby.qml` lets the host pick LAN or Internet signaling.
  Joiners need no switch, the plugin recognises LAN codes (`L…-…`) by
  their shape. The browser build hides the LAN option (the plugin does
  not support it there) and refuses a LAN code with a message.

## Measurements

`tests/netbench` reproduces the game's sync path between two headless
instances on one machine: the host moves on a path that is a function of
the wall clock at 7.5 Wu/s, sends snapshots exactly like `Session.qml`, and
the joiner records interpolated versus true position every frame. The
effective delay is the time shift that best explains the interpolated
motion; the residual is what remains after that shift.

| signaling | send period | delayMs | effective delay ms | mean error Wu | max error Wu | residual Wu | arrival gap ms | drops | rtt ms |
|---|---|---|---|---|---|---|---|---|---|
| local | 50 ms | 120 | 120 | 0.90 | 0.92 | 0.053 | 50 ± 5.3 (max 65) | 0 | 1 |
| cloud | 50 ms | 120 | 120 | 0.90 | 0.91 | 0.053 | 50 ± 5.3 (max 65) | 0 | 1 |
| local | 50 ms | 100 | 100 | 0.75 | 0.77 | 0.040 | 50 ± 5.4 (max 65) | 0 | 0 |
| local | 33 ms | 80 | 80 | 0.60 | 0.61 | 0.028 | 33 ± 4.1 (max 50) | 0 | 0 |
| local | 33 ms | 66 | 65 | 0.50 | 0.51 | 0.023 | 33 ± 4.1 (max 50) | 0 | 1 |
| local | 16 ms | 50 | 50 | 0.38 | 0.64 | 0.020 | 16 ± 1.9 (max 52) | 0 | 1 |
| local | 16 ms | 40 | 40 | 0.31 | 0.32 | 0.011 | 16 ± 0.7 (max 18) | 0 | 1 |
| local | per frame | 50 | 50 | 0.38 | 0.42 | 0.013 | 16 ± 0.8 (max 23) | 0 | 0 |
| cloud | per frame | 50 | 50 | 0.38 | 0.39 | 0.013 | 16 ± 0.8 (max 18) | 0 | 0 |

Reading it: error is speed times delay in every row, so the delay is the
whole story on a loopback. The one outlier (send 16 ms, delay 50, max
error 0.64) is a single 52 ms arrival gap: the late snapshots were
stamped on arrival and the interpolator played 50 ms of motion in a few
milliseconds. That is clayground #290. The last two rows are the game's shipped
setting: 50 ms behind, 0.38 Wu mean error, identical over LAN and Cloud
signaling.

## Running the bench

It needs the Clayground live loader, which the game's own build does not
produce (tools are off there). Build clayground out of tree with tools:

```
cmake -S clayground -B build-claytools -G Ninja \
  -DCMAKE_PREFIX_PATH=$HOME/Qt/6.11.2/gcc_64 -DCMAKE_BUILD_TYPE=Release \
  -DCLAYGROUND_WITH_TOOLS=ON -DCLAYGROUND_WITH_EXAMPLES=OFF -DBUILD_TESTING=ON
cmake --build build-claytools -j8
python3 tests/netbench/run_netbench.py --loader build-claytools/bin/clayliveloader --mode local
python3 tests/netbench/run_netbench.py --loader build-claytools/bin/clayliveloader --mode cloud
```

Options: `--interval <ms>` (0 = per frame, the game's setting),
`--delay <ms>`, `--seconds <n>`, `--json <file>` to append one result
line per run. Exit code 0 means a measurement was taken; the numbers are
the result. Both instances must run on one machine, the truth comes from
the shared clock.

## Checking a real LAN or internet session

The bench cannot leave one machine. For the two remaining checks of #8
run the game itself and read the `NetworkMonitor` overlay (bottom right
while connected):

1. LAN, two native instances on two machines: host picks LAN, shares the
   code, joiner enters it. Expect rtt in the low milliseconds, `in`
   around 60/s, `age` under 100 ms, `drop` 0 and no `[fallback]` marker.
   Walk into a wall next to each other: the other avatar should stop
   within one body width of where the other screen shows it.
2. Internet, one browser and one native instance: host picks Internet,
   the browser joins via the cloud code. Expect the same rates; the
   remote delay is 50 ms plus the shown rtt. A `[fallback]` marker means
   the lossy channel did not negotiate and state rides the reliable
   channel, which lags under loss. In the browser the plugin uses PeerJS
   data connections, so the lossy channel is PeerJS's `reliable: false`.

## Enemies (issue #13)

The host runs every enemy; the others show it. An enemy is a replicated
object of type `"enemy"` that the host spawns (clayground #306): its
`ReplicatedObject` sends `xWu`, `yWu`, `aiState`, `facingAngle`, `hp`,
`parryWindow` and `targetId` whenever one changes, and a joiner makes a
remote enemy per object - a kinematic body without AI - also for objects
spawned before it joined. A knight's blow on a remote enemy goes to the
host as a message (`enemyBlow`); the host's enemy hits another node's
knight with one (`knightBlow`), which that node checks against where the
knight really is; a spitter's shot is broadcast and flown on every node.

The remote enemy renders on `autoDelay`, like `RemotePlayer.qml`. Until
issue #64 it had a fixed delay of 50 ms plus the round trip (capped at
100 ms) instead, and until issue #19 a second setting, `settleMs: 30`: an enemy
that stops dead (a lunge lands) sent nothing until the settle, and the
interpolator carried the lunge on, up to 1.2 Wu past the stop. Both were
behaviour of clayground any object that rests or stops would meet, filed
as [clayground #366](https://github.com/MisterGC/clayground/issues/366)
(`autoDelay` after a rest) and
[clayground #367](https://github.com/MisterGC/clayground/issues/367)
(the overshoot until the settle).

Against clayground `issue-366` @ e003cf9, which carries both fixes, the
same-world bench (below) ran three ways, each five times with Local and
five times with Cloud signaling; the setting kept ran ten times more on
the branch's head:

| enemy settings | runs | exit 0 | worst position error, Wu | position misses | render delay, ms | AI state misses |
|---|---|---|---|---|---|---|
| fixed delay, `settleMs: 30` (before #19) | 10 | 6 | 0.103 - 0.306 | 3 | 50 - 52 | 0 |
| fixed delay, default `settleMs` (now) | 20 | 14 | 0.045 - 0.262 | 2 | 50 - 52 | 0 |
| `autoDelay`, default `settleMs` | 10 | 6 | 0.047 - 0.213 | 0 | 35 - 359 | 3 (Cloud) |

- `settleMs` is the default again: #367 sends a stopped object's state
  once more right after the stop. The miss issue #19 was asked about, a
  remote enemy in `recovery` just over 0.25 Wu off, got rarer but did not
  go: 2 of 20 runs (0.256 and 0.262 Wu) against 3 of 10 with
  `settleMs: 30` (0.252, 0.270 and 0.306 Wu), every one in `recovery`.
  The tolerance stays 0.25 Wu.
- The fixed delay stayed then. With `autoDelay` each enemy gets the delay its
  own send intervals ask for, and some enemies were rendered up to 359 ms
  behind: three Cloud runs failed the AI state check with a joiner state
  the host had left more than 300 ms before (e.g. `patrol` on the joiner
  where the host had `idle`). Widening the check's 300 ms is not the
  answer; an enemy shown 360 ms late also lunges 360 ms late on that
  screen. It stayed a workaround until
  [clayground #374](https://github.com/MisterGC/clayground/issues/374),
  which issue #64 builds on.
- The other failures are not the position or the state check, and come
  with every setting: the block phase, where the first lunge was judged
  `ignored` (the knight was in the grace after another hit, so every blow
  of that enemy counted `ignored`) or once `hit`, in 1 run with
  `settleMs: 30`, 3 with the default and 2 with `autoDelay`; and once a
  shield push that moved the enemy 0.93 Wu, under the 1.0 Wu asked.

### Every same-world miss named (issue #64)

Against clayground `issue-374` @ af6f806 (PR #394, the submodule), with
the enemy on `autoDelay`, each miss of the table above has its cause:

- the position just over 0.25 Wu in `recovery`: gone with the fixed
  delay. Over 52 runs on `autoDelay` (12 Cloud on 8b6c263, 20 Local and
  20 Cloud on af6f806) the worst position error was 0.138 Wu, in
  `recovery`, every enemy rendered 33 to 81 ms behind, no AI state miss.
  That the fixed 50 ms ran out of buffered states when Cloud's arrival
  jitter outlasted it, while a lunge stopped, is inferred from the table
  (2 misses in 20 runs with it, none with `autoDelay`), not reproduced.
- the block judged `ignored`: the bench's question. The host's other
  enemies kept thinking while the joiner's knight held its shield toward
  one; one that hit the knight from behind put it into its grace, and
  the knight ignored the lunge, as it should. The other enemies now stop
  thinking for the lunge answers, as for the shots, and a lunge met in
  the grace is tried again; no run needed a second try.
- the shield push of 0.00 Wu (and 0.93): the bench's question. The bench
  measured the push along the knight's approach before its dash; the push
  goes along the direction the knight sends, from where it is at the step
  it pushes. A blocking dash covers 0.27 Wu a step: an enemy within a step
  of the knight when it dashes (0.011 to 0.083 Wu in these runs) is behind
  it by the step it pushes, and is pushed back the way the knight came,
  173 to 180 degrees off the approach. 14 of 52 runs pushed so; measured
  along the approach each read 0.00 Wu, measured along the push the host
  received, 1.17 to 1.37 Wu. On the host's own screen every push went
  away from the joiner's knight as the host showed it. One of those
  pushes stopped after 0.42 Wu at a wall: the knight had stood a step
  from it, and a push turned back toward that spot met it. The knight now
  stands in the open for the push.

The last 10 Local and 10 Cloud runs, on this branch with every fix, all
exited 0 with 37 checks passed: 11149 to 12154 enemy records judged per
run, the worst position error 0.043 to 0.050 Wu, the render delay 33 to
77 ms, no id, HP or AI state miss; every push moved its enemy 1.33 to
1.36 Wu, seven of them turned back.

None was a disagreement between the screens, so none went back to
Clayground. Why pushes turned back came more often with the auto delay
(10 of 40 runs on #374's branch against 1 of 16 before, clayground#374)
is not determined; the measure no longer depends on it.

`tests/enemies` measures it: host and joiner in one process over LAN,
five seconds of two knights fighting, every enemy compared every 16 ms.
Five runs against clayground `issue-306` @ 6eefb29: max error 0.375 to
0.397 Wu (during a lunge), mean 0.070 Wu, no AI state or target on the
joiner that the host had not had in the 300 ms before.

## The same world on both screens (issue #14)

`tests/sameworld/run_sameworld.py` runs a session as it is played: two
processes of Clayground's live loader (`clayliveloader --instance host`
and `--instance joiner`), each with the whole game, connected over Local
or Cloud signaling and driven through the inspector protocol. The host
starts the game on seed 424242. The host's knight goes to one enemy and
the joiner's in sight of the enemy farthest from it. The joiner's knight
answers that enemy (issue #17, below), and the bench checks that the host
takes each answer and that the joiner then shows the host's HP. After
that both knights fight the nearest enemy for eight seconds. Every frame each process
records every enemy it shows, with the wall-clock time: object id,
position, HP and AI state.

The joiner renders the host's enemies in the past by the delay their
interpolator sizes itself (`autoDelay`, 33 to 81 ms in the runs of issue
#64).
Each joiner record carries the delay each enemy was rendered with (its
interpolator's `effectiveDelayMs`, so an enemy on `autoDelay` is judged
by its own), and is judged against the host's records:

- position: within 0.25 Wu (`--tolerance`) of the host's position at that
  delay, give or take 20 ms (`--slack`), the host's position taken between
  its two frames around that moment
- id: an enemy on the joiner is one the host had in the 300 ms before
  (`--lag`), and an enemy on the host shows up on the joiner within 300 ms
- AI state: one the host had in the 300 ms before. A host record also
  holds the states an enemy passed through since the record before: a
  lunge that lands and a blow that staggers in one frame make a
  `recovery` that no frame shows, but that is sent and shown
- HP: one the host had in the 300 ms before, or one between two of them.
  Clayground blends every number of a replicated object, HP too
  (clayground#368), so between two of the host's states the joiner shows
  an HP that neither had (`hpBlended` counts these). Until the clayground
  pin carries the fix this is a named tolerance; right after the scripted
  hit and once the fight is over the HPs have to agree exactly.

It exits with the number of failed checks. `--fault stale` makes the
joiner apply none of the host's enemy states, which proves the checks
can fail. `--dump` writes both processes' raw records to a file, and
`--judge <file> --late-ms 200` judges them again with the joiner made
200 ms later than it was. Whatever ends a run - its end, an exception,
Ctrl-C - both loaders are stopped and the temp dir is removed; it stays,
with the loaders' logs, only after a run that failed a check.

Six runs against clayground `issue-306` @ 6eefb29 (the submodule), three
with Local and three with Cloud signaling, all exited 0. Each judged 5110
to 6280 enemy records of the joiner, all rendered 50 ms behind (the round
trip on one machine is under 1 ms). The worst position error against the
host 50 +- 20 ms before was 0.041 to 0.048 Wu, the mean 0.0007 to
0.0009 Wu. No run had an id, AI state or HP the host had not had in the
300 ms before; 2 to 10 HPs per run were blended. The scripted hit landed
with the first swing in every run. The same six records judged with the
joiner 200 ms late all failed the position check, with a worst error of
1.21 to 1.29 Wu. With `--fault stale` the run exited 4: position (max
8.0 Wu), AI state (1760 misses), HP during the fight (617 misses) and HP
after the hit (joiner 52, host 39) failed.

On the joiner a knight that stood still did not see a host's enemy walk
into its reach: Box2D lets a body at rest fall asleep, a host's enemy on
the joiner is moved only by setting its position, and that woke nothing
(clayground#369). The clayground pin carries the fix since issue #17, and
the bench's knight stands.

## A hit counts once, whoever lands it (issue #17)

A knight's answer to a host's enemy is judged on the knight's own screen
and applied by the host, once:

- a swing: the attacker's screen draws the hit, counts the damage it dealt
  and sends the blow (`enemyBlow`, kind `damage`); the host lowers the HP,
  and every screen shows the host's HP
- a parry: the same, plus `stagger`; the host's enemy staggers
- a shield push: `push`, and `stagger` on a guardian; the host shoves its
  enemy. A shove runs as a knockback (`Enemy.shove`): a velocity set once
  lasted only until the AI's next think, which stops an enemy in
  `recovery` or `stagger`, so the same push went anywhere from 0 to 2 Wu,
  for the host's knight as for a joiner's. Now it goes about 1.3 Wu
  (`knight.pushSpeed` over `enemy.knockbackDuration`).
  An enemy that died in the knight's reach could stay in its reach
  (`Player.enemiesInRange`): its body's end of contact can come without its
  item, so the sensor cannot tell whom to drop. First in the reach, it made
  the push throw before it reached the enemy being pushed, and no `push`
  was sent. The knight now drops dead enemies from its reach before a
  swing or a push.
- a kill: the host's enemy dies and is despawned on every screen; the
  killer's screen counts the kill and draws the death, stain included, and
  the others draw it from its `impact`

The other way round, a host's enemy that lunges at a joiner's knight sends
the blow (`knightBlow`) with the enemy's id. The joiner holds it until its
screen shows the lunge land, the enemy's render delay after it arrived. Without the hold, a parry in the last 50 ms
of the parry window as the joiner shows it came after the blow of the
very lunge it parried: the knight was hurt and parried at once. A parry of
that enemy from its last parry window (`enemy.parryFrames` steps) before
the blow arrived until the hold ends answers the lunge, and the blow is
dropped. `Game.knightStruck` says what became of each blow: `hit`,
`blocked`, `ignored`, `out of reach` or `parried`.

`tests/sameworld/run_sameworld.py` checks each of these between a host and
a joiner process. The joiner's knight stands in sight of an enemy until it
sleeps, the enemy walks into its reach, and one swing lowers the enemy's HP
by the same amount on both screens; the host's enemies lose what the
joiner's screen dealt. It parries that enemy from the sixth frame of the
window it shows, when the host's lunge has landed and its blow is on its
way: the host's enemy staggers and no blow of that lunge lands on the
knight. The knight goes to a third enemy, which the host kills there, then
stands 4 to 8 Wu from the first, on a spot whose grid cell and the eight
around it are floor, and shield-pushes it once it comes: the host receives
the push and its enemy moves at least 1 Wu along the direction the push
carries (issue #64, below). Then it
kills that enemy while the host's knight kills another: both are gone on
both screens, the host's and the joiner's kill records grow by their own
kills, and every death leaves one stain on each screen, in the same place.

Eight runs against clayground `issue-369` @ acffb2d (the submodule), five
with Local and three with Cloud signaling, all exited 0 with 23 checks
passed. In every run the joiner's knight slept before its swing and the
swing landed with the first try: HP 52 to 49 on both screens, and the 16
its screen dealt (the swing also caught a second enemy) was what the host's
enemies lost. Every late parry staggered the host's enemy, and the one
blow of that lunge was dropped as parried. Every push reached the host
(`push` and `stagger`) and moved its enemy 1.30 to 1.36 Wu; in seven of
the eight a dead enemy was first in the knight's reach at the push. Both
kills went on both screens with matching stains (two or three deaths per
run: a swing also kills what else is in its arc). The worst position error
was 0.045 to 0.245 Wu, mostly on an enemy in a lunge at the knight.

Each fix is proven by switching it off. Without the parry's drop the parry
check fails: the blow lands. With the knight's old loops and a dead enemy
first in its reach, the push throws, the host receives nothing and its
enemy moves 0.00 Wu. Before the shove ran as a knockback, a push the host
received moved its enemy 0.30 to 0.32 Wu in some runs, 1.2 to 2.2 in
others. With `--fault stale` the run exits 7.

The position check fails now and then on an enemy the scripted steps do
not touch, in `recovery` or a lunge: 0.253 to 0.286 Wu against the 0.25
tolerance, in about one run of five while these steps were built. That
check and its tolerance are #14's.

## An attack on a knight is judged by its own screen (issue #18)

A block, a parry and a dash depend on the knight's facing and state, which
only its own screen has exactly. So the host announces an enemy's attack,
and the screen of the knight it goes for decides, applies that knight's HP
and tells the others (`struck`, broadcast):

- a lunge: the host sends the blow (`knightBlow`, issue #17); the knight's
  screen holds it for the enemy's render delay and judges it `parried`,
  `blocked`, `dodged`, `hit`, `ignored` (fallen, or in the grace after a
  hit) or `out of reach`. A dash that carried the knight past the enemy
  counts as `dodged`. The result goes to every node as
  `{source: "lunge", id: <enemy>, result}`; `Game.struckReported` says it
  on the others. The knight's HP reaches them with its state as before.
- a shot: the host gives it an id (`shot1`, `shot2`, ... per game) and sends
  it with the shot. Every node flies it under that id; it hurts only that
  node's knight. The node whose knight it meets judges it - `blocked` by
  the shield, `dodged` in a dash, `hit` or `ignored` - and sends
  `{source: "shot", id, result}`. Every other node removes the shot of that
  id without an impact of its own (the knight's screen sends the hit or
  the deflection as before). A shot that meets no knight bursts on each
  screen on its own, at its wall or the end of its life.
  `Game.shotEnded` says what became of each shot on this screen.
  A known trade-off: no host decides who a shot hits, so one shot that
  meets two knights on their two screens within the network delay hits both.

The parry window of a held blow is counted in physics steps (the blow's
arrival step minus `enemy.parryFrames`), as the enemy's attack runs, not in
wall-clock milliseconds; the hold itself stays wall clock, since the screen
renders the enemy by it.

Building the bench showed a game bug: the shield check for a shot measured
from the knight's top-left corner to the shot's. The knight is 1.0 Wu, the
shot 0.3 Wu, so the shot's corner sits 0.35 Wu off its centre at that size,
and a shot from the left or from above came in at the edge of the 60 degree
arc or beyond it: with the shield up and facing the spitter the knight took
the hit. The shield is now measured in one place: `Player.isShieldFacing`
takes the attacker's corner and its size and compares the two centres.
A shot passes its 0.3 Wu, a lunge the enemy's 0.8 Wu (the host sends it in
`knightBlow` as `size`); the reach of a lunge stays corner to corner, as
the host's own check. The benches' scripted knights face a thing centre to
centre too. The fight bench (seed 424242) before and after: `mix` and
`parry` unchanged (175 dealt, 4 taken, 4 blocks, 116 HP; 170 dealt, 0
taken, 4 parries, 120 HP), `block` still falls with 10 blocks and 120
taken, now dealing 61 instead of 68 and killing 1 enemy instead of 0.

`tests/sameworld/run_sameworld.py` checks it between a host and a joiner
process, after the parry of issue #17:

- the joiner's knight holds its shield toward the enemy, which lunges,
  while the host's other enemies stop thinking (one that hit the knight
  from behind put it into its grace, and the lunge counted `ignored`,
  issue #64); a lunge that meets the knight in its grace all the same is
  tried again, as a shot is. The
  joiner's screen judges the blow `blocked`, the knight loses HP for it, the
  host receives `blocked` and shows an HP the joiner's knight had in the
  300 ms before
- it dashes at the enemy from the fifth frame of the parry window it shows:
  `dodged`, no HP lost, the host receives `dodged`
- it stands 2.5 to 4 Wu from a spitter while the host's enemies stop
  thinking (so the spitter spits only when told, and no other blow puts the
  knight into its grace), and the host makes the spitter spit at it three
  times: with the shield up, dashing into the shot, standing. The joiner's
  screen judges `blocked`, `dodged`, `hit`, each with the knight's state at
  that moment in the log; the host receives each result, and its shot of
  that id was shown until the result came and is gone after
- the other way round, the joiner's knight waits beside another enemy, and
  the host's knight holds its shield toward the spitter, which spits at it:
  the host's screen judges `blocked`, the joiner receives it, and its shot
  of that id goes then. (On the spot the joiner's knight had just stood
  on, the joiner's screen met the shot with its own knight first: the
  known trade-off above.)

Six runs against clayground `issue-369` @ acffb2d (the submodule), three
with Local and three with Cloud signaling, all exited 0 with 37 checks
passed. In all six every new check passed on its first try: each lunge
blocked and dodged, each shot on the joiner blocked, dodged and hit, the
shot on the host blocked. Each result reached the other screen 0 to 2 ms
after the judging screen decided, and its shot of that id was last drawn 0
to 6 ms before the result arrived. The worst position error was 0.089 to
0.223 Wu. With no node sending `struck` the run exits 6: the six checks
that the other screen receives the result fail, and the shots fly on. With
the joiner ignoring the host's results only (`_endShot` returning on a
joiner) it exits 1, on the joiner's check alone. With `--fault stale` it
exited 9 (run before the host's shot was added).

## A downed knight, and the end of a co-op run (issue #19)

A knight at 0 HP is down, on every screen: `KnightView.downed` flattens
and darkens it, hides its aim and dims its lantern. The local knight is
down when its HP is 0 (`Player.fallen`); another player's knight when the
HP its state carries is 0 (`RemotePlayer.remoteHp`, sent with every state,
60 per second). A down knight takes no blow (`ignored`), the campfire does
not heal it, and it stays down through a level change, for the rest of the
run.

In a session the fall does not end the run while another knight stands.
The downed player's screen says "You are down", keeps the dungeon in sight
under a light shade and offers only Esc, which leaves the session; the
enemies go for the knights still standing (issue #13).

The host ends the run: whenever its own knight falls, another knight's
HP changes (`Session.partyChanged`) or a node leaves, it checks whether
its knight and every other one are at 0 HP. If so it broadcasts
`runEnd`; each joiner leaves the session on it, and the host follows once
every joiner has left, or after `Session.endRunWaitMs` (2 s), so its
leaving cannot cut the message off. Then every screen stops its enemies
and shows the run's summary, as the fall screen does for one knight:
"Your party has fallen", the depth, the kills, the time and the best
depth, which is kept as on any fall. Enter or Esc goes to the title; a
co-op run is not started again from there.

`tests/downed/downed.qml` checks it with a host and a joiner in one
process, over LAN, in two sessions. In the first the joiner's knight
falls first: both screens draw it down, its screen says "You are down"
and offers only Esc, the host's knight stands, the run goes on and no
enemy stops. Then the host's knight falls: within 3 s both screens must
be out of the session and show "Your party has fallen" with the depth,
kills, time and best depth, and only the title offered; Enter on the
host's and Esc on the joiner's must take each to the title. In the second the host's knight
falls first and the joiner's last, so the host learns of the last fall
through the joiner's state.

Six runs against clayground `issue-366` @ e003cf9 (the submodule) all
exited 0 with 42 checks passed. Both screens showed the summary 57 to
95 ms after the last knight fell. With the host's `runEnd` broadcast taken
out the bench exits 100, waiting for the end; with `RemotePlayer` drawing
no knight down it exits 100, waiting for the fall on the other screen;
with Enter doing nothing on the summary it exits 100, waiting for the
title.

## Joining late, leaving and losing the host (issue #20)

The run is two Clayground session properties, `seed` and `level`, which the
host sets when it starts the run and `level` again at each level
(clayground#306). A node that joins gets both with its welcome, after every
live enemy: it builds the host's level on the host's seed, a village or a
dungeon, and makes a remote enemy for each of the host's. The `gameStart`
and `levelChange` messages are gone; the lobby's start and a level change
reach the joiners in the game the same way. Two things in Clayground
shaped this:

- a session property whose value is an object (`{seed, level}`) reached
  the joiners as `null`; numbers arrive. `setSessionProperty` takes a
  `QVariant`, and a JS object in it is a `QJSValue`, which
  `QJsonObject::fromVariantMap` turns into null when the host sends it
  (read in the source, not traced)
- `sessionPropertyChanged` comes before `sessionProperties` has the new
  value, so `Session.qml` keeps the two values from the signal itself

Every node that is in the run when a node joins makes a knight for it.
Another player's knight is made with the HP of the last state its node
sent, also when the level is built again, so a downed knight is never drawn
standing until its next state. Without a state yet - a node that just
joined, or every other knight on the screen of the node that did - the
knight is not drawn (`RemotePlayer.known`), and no enemy goes for it.

A node that leaves says goodbye (clayground#299): every screen removes its
knight, and the host's enemies that went for it drop it
(`Enemy.dropTarget`): an attack wound up against it does not go on, and
the next think picks the nearest knight still there. A joiner whose session
ends without its leaving - the host left, crashed or lost its connection -
goes to the title, which says "The host left the game" or "Lost the
connection to the host".

`tests/joinleave/joinleave.qml` checks it with a host, a joiner and a late
joiner in one process, over LAN. The joiner's knight goes down and the
host goes down two levels, to the dungeon at depth 1; then the late joiner
joins. It must play the host's seed and level, have the host's rooms and
live enemies (each within 1 Wu of the host's), never draw the joiner's
downed knight standing, and its knight must show on the host's and the
joiner's screens where it stands. Its knight then stands at the host's
enemy farthest from the host's knight until an enemy chases it, and it
leaves: within 1.5 s no enemy of the host's goes for it, both other
screens have dropped it, and a second later still none does. Last the host
leaves: within 2 s the joiner is on the title, saying "The host left the
game", out of the session with its run cleared. `tests/downed` adds the
level change: while one knight is down the host goes down two levels, and
the other screen must make that knight downed in the village and in the
dungeon.

Against clayground e003cf9, five runs of the join and
leave bench exited 0 with 18 checks passed: the late joiner was in the run
176 to 1093 ms after it joined, the host's enemies dropped the knight 36 to
50 ms after its player left and the joiner's screen 39 to 66 ms after, and
the joiner was on the title 93 to 111 ms after the host left. Three runs of
the downed bench exited 0 with 50 checks passed. Each part fails when
switched off: with `nodeLeft` ignored the join and leave bench times out
waiting for the enemies to drop the knight, without the host lost signal
it times out waiting for the title, and without the HP from the last state
the downed bench exits 4, on the four level change checks. The same-world
bench, whose session now starts through the session properties, ran four
times with Local signaling, all exited 0 with 37 checks passed, and four
times with Cloud: two exited 0, one failed the block phase (the first
lunge judged `ignored`) and one the position check (0.278 Wu, an enemy in
`recovery`, shapes-and-stone #64), the two misses issue #19 recorded.
With the host's explicit drop switched off the enemies still dropped the
knight, 115 ms after: once the knight is gone from the session the next
think picks another. The drop only makes it immediate, and cancels an
attack wound up against that knight.

## Gold drops, picked up once (issue #38)

The host owns the gold as it owns the enemies. A host's enemy that dies
drops its gold (`Game.dropGold`): the host spawns it as a replicated
object of type `"gold"` with its place and amount, and every node makes a
`GoldDrop` of it, a node that joins late too. Whose blow killed the enemy
does not matter: issue #17's rules credit the kill to the killer's screen
(its fight record and run kills), and the gold goes to whichever knight
reaches the drop first. Each node checks every physics step whether its
own knight stands on a drop and claims it (`goldClaim`, sent to the host;
the host's own claim is answered at once). The host takes the first claim
it gets for a drop, despawns the drop on every node and tells the
claimer's node the amount (`goldGrant`); a later claim finds no drop and
gets nothing. The gold, the potions and the smith's upgrade are each
knight's own and live on its own node, as its HP does; the others never
see them. A drop the host leaves behind at a level change is despawned
with the level, as its enemies are.

The gold bench joins a host and a joiner over LAN and puts both knights on
the same drop in the same frame: one of them got it, once. It also checks
that a drop of the joiner's kill goes to the host's knight that picks it
up, and the other way round, and that a claim the joiner sends after the
drop was taken gives no gold.

## Security note

clayground #293 is the concrete gap behind the "secure/robust foundation"
question: a LAN code is the host's private IP and port in base36, the
embedded signaling server accepts every offer over plain `ws://`, so
anyone on the network who finds the port can join. The data channels are
DTLS-encrypted either way. The public PeerJS server is a dependency, not
a security hole: room ids are random and `Network.signalingUrl` points
the cloud mode at a self-hosted relay (`clay-dev-server` ships one).

## Clayground issues

Filed in `MisterGC/clayground` and fixed together in
[clayground PR #295](https://github.com/MisterGC/clayground/pull/295)
(branch `net-sync-fixes` off `release/v2026.8`). With that plugin the game
passes the sender's timestamp into the interpolator and switches on
`autoDelay`; against an older plugin it keeps the round-trip rule. Bench
against that build, per-frame sends, both signaling modes: 35 to 40 ms
effective delay and 0.28 Wu mean error (fixed 50 ms: 0.38 Wu; the original
120 ms: 0.90 Wu). Run it with `--auto` and the loader from that build.

- [#290](https://github.com/MisterGC/clayground/issues/290) `StateInterpolator` stamps snapshots with arrival time, so a late burst makes the remote avatar jump (the spike in the table above)
- [#291](https://github.com/MisterGC/clayground/issues/291) `StateInterpolator` should size its delay from observed jitter instead of a fixed `delayMs` (replaces the round-trip rule in `RemotePlayer.qml`)
- [#292](https://github.com/MisterGC/clayground/issues/292) host writes `peers_` from the libdatachannel thread in `onDataChannel`
- [#293](https://github.com/MisterGC/clayground/issues/293) LAN join has no secret: the code is the host's IP and port, anyone on the network can join
- [#294](https://github.com/MisterGC/clayground/issues/294) network docs disagree with the code: `peerStats` "when verbose", Cloud "requires internet", `LAN`/`Internet` names
