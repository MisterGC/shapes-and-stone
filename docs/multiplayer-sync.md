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

Two settings of the remote enemy's interpolation are not the defaults:

- A fixed delay of 50 ms plus the round trip (capped at 100 ms) instead
  of `autoDelay`. An enemy at rest sends nothing, and `autoDelay` counts
  that gap into the sender's update period: after a rest it rendered the
  enemy about 80 ms behind and glided back to 40 ms over seconds. At a
  lunge's 5.6 to 8 Wu/s that is up to 0.65 Wu.
- `settleMs: 30` instead of 200. An enemy stops dead when a lunge lands;
  its position stops changing, so nothing is sent until the settle, and
  meanwhile the interpolator extrapolates the lunge (up to
  `maxExtrapolationMs`, 200). With 200 the remote enemy overshot by up to
  1.2 Wu and snapped back.

Both are behaviour of clayground's `StateInterpolator` and
`ReplicatedObject` that any object which rests or stops would meet, filed
as [clayground #366](https://github.com/MisterGC/clayground/issues/366)
(`autoDelay` after a rest) and
[clayground #367](https://github.com/MisterGC/clayground/issues/367)
(the overshoot until the settle); the two settings are workarounds until
those are fixed.

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

The joiner renders the host's enemies 50 ms plus the round trip (capped
at 100 ms) in the past, the delay `Enemy.qml` gives their interpolator.
Each joiner record carries the delay it was rendered with, and is judged
against the host's records:

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
screen shows the lunge land, the enemy's render delay (50 ms plus the
round trip) after it arrived. Without the hold, a parry in the last 50 ms
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
stands 4 to 8 Wu from the first and shield-pushes it once it comes: the
host receives the push and its enemy moves at least 1 Wu away from the
knight. Then it
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
