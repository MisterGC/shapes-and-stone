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
the wall clock at 7.5 Wu/s, sends snapshots exactly like `Game.qml`, and
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
cmake -S ../clayground -B build-claytools -G Ninja \
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
