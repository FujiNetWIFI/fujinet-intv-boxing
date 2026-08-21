# Boxing (Mattel, 1980) — FujiNet netplay, 2 players

The eleventh FujiNet netplay port of an EXEC-era Intellivision cart.
Boxing is a simultaneous 2-player game (no turns): both consoles run the
whole original cart, lightly patched, exchanging one controller byte per
seat per sim tick, staying in delay-based lockstep. There is no turn
arbiter — the game's own shared per-seat handler indexes state directly
off the controller index the EXEC hands it, so both seats' events replay
every tick.

The pre-game "CHOOSE MEN" screen is a real keypad-driven prompt: each
seat picks a boxer (digits 1-6) and presses ENTER. Picking the SAME
digit as the other seat is silently rejected by the game's own
duplicate-pick guard — the demo/fuzz script sends seat 0 → boxer #1,
seat 1 → boxer #2.

## Status

Most emulated gates PASS (2026-08-20); one is a documented, root-caused
open item:

| gate | result |
|---|---|
| `make verify-org` | byte-identical rebuild |
| `make verify-patch` | exactly the 39 declared words differ |
| `make check-7000` | no build maps `$7000` |
| live boot-dump (§7.31) | `MASTER_TICK` confirmed calling the original slot-0 body; `$035D` reaches the CHOOSE MEN prompt table |
| wall tick rate (§7.28) | measured 44,802 cycles = exactly 3.000 frames = 20.0 Hz, matching the header |
| `make lagcheck` | TRACE_RING cross-correlation peaks at shift=20 (199/209 agree vs a 0-20/209 baseline) |
| `make det` | **FAILS** — 2/256 tick checksums differ under stall injection, both narrowed to the native timer-countdown mirrors; one root cause found and fixed (a real-frame `$0102` busy-wait in the punch-timing logic, canonicalized), a second not yet reconciled. See `spikes/NOTES.md` M4. Destination-phase assertion (`GAME_TBL == $593C`, both seats picked different boxers) passes. |
| `make echo-test` | 100 clean transport rounds |
| `make server-diff` | 6/6 scenarios, 2 seats |
| `make rig PLAYERS=2` | live lockstep, 0 CRC mismatches, all DIAG counters zero |
| `make m4 PLAYERS=2` (+ `QUIESCE=1`) | the deliberately injected fault IS repaired (confirmed by direct cell inspection) and the quiescent branch of `RS_PENDING` IS confirmed firing — but the overall run does not end cleanly, because the `make det` residual keeps triggering further (self-correcting) resyncs throughout a long run |
| `make peerleft PLAYERS=2` | both leave modes (`clean` and `timeout`), correct terminal screen decoded, DIAG counters clean |

Not yet done: real-hardware bring-up (`make rom SRV_HOST=...`, PiRTO II,
HUD on, tune `d` from the L/S/T/R/H row) and a human `make run-hook` feel
playtest. Hardware images are built (`build/boxing_net.rom`,
`build/boxing_nethud.rom`).

**Known open item**: `make det` does not show a clean PASS. The residual
is narrow (self-correcting within the same run, isolated to the native
timer-countdown mirror cells) and the CRC+resync safety net demonstrably
repairs deliberately injected faults in `make m4` — but it recurs often
enough that a long `make m4` run never settles into a fully clean tail.
Full root-cause and fix is future work; see `spikes/NOTES.md` M4 for the
complete investigation (one class fully diagnosed and fixed live via
single-instruction stepping, a second narrowed to `BX_TICK2`'s mirror
but not yet reconciled). This mirrors Sea Battle's own shipped precedent
(`fujinet-intv-sea-battle/CLAUDE.md`): a real, narrow, resync-recovered
desync, accepted and documented rather than blocking indefinitely.

## Build & run

Prereqs: as1600/dis1600/bin2rom (jzIntv SDK), jzIntv with `--fujinet`,
fujinet-pc-rs232 dist, Python 3.

```sh
make verify-org           # gate 0: the dump reassembles byte-identical
make run-hook              # play the patched-but-local build (feel test)
make rig                   # full 2-console local netplay rig, headless
make rom SRV_HOST=fujinet.online   # hardware image -> build/boxing_net.rom
make rom-hud               # same with the live HUD row (bring-up)
server/run_production.sh   # relay on :9112, registered on the FujiNet Lobby
```

Port 9112 / Lobby appkey 20 are Boxing's assignments on the shared host
(next free after Soccer 9109/17, Sea Battle 9110/18, Golf 9111/19) —
**these need provisioning on `fujinet.online` before a production
launch.** The lobby username comes from the FujiNet Lobby appkey
(creator 1/app 1/key 0), falling back to `GUESTnn`.

## What is different from the sibling ports

- **Native dispatch, 4 of 5 entries** (PORTING.md §7.31) — the widest
  application yet (Sea Battle did 2 of 3). `MASTER_TICK` occupies table
  slot 1 (a defensive `X_MUSIC_TICK` placeholder still owns slot 0 —
  load-bearing here, unlike every prior port that carried it only as
  precaution: Boxing's own ISR calls into the EXEC note engine, which
  reprograms slot 0's countdown whenever a note plays). Slots 2-5 are
  the four native entries, unchanged target and interval.
- **Dispatch-only input, no turn arbiter**: zero polled `$011F`-`$0124`
  reads anywhere in the ROM. The EXEC hands each handler the controller
  index directly (`R1`), and Boxing's own handlers are seat-aware, so
  both seats' events replay every tick with no arbitration needed —
  Sea Battle's shape, not Golf/Bowling's.
- **A real cart-owned ISR**: Boxing installs its own frame interrupt
  body, unlike every 2-player predecessor. `RS_CLAMP_ISR` is load-bearing
  here (Soccer's shape, not Sea Battle's harmless-spare one) — the saved
  vector at `$01A8/$01A9` is a genuine code pointer inside the transported
  image, and a corrupted wire byte there would install an arbitrary
  interrupt handler.
- **A game-logic busy-wait on `$0102` directly**: unrelated to the
  documented timer API, unrelated to the sound engine — the punch-connect
  timing check at `$56C9` polls the EXEC's own ISR phase counter with its
  own `EIS`, entirely outside any JSR a recon scan could find. Canonicalized
  by redirecting the read to an always-zero netcode-RAM cell (`tools/
  patches.py`'s 39th patch site) — see `spikes/NOTES.md` M4 for the full
  investigation.

## Layout

Same tree as the sibling ports (see `PORTING.md`, the canonical
methodology). `spikes/NOTES.md` holds the full per-milestone evidence
trail, including the M3 investigation into the CHOOSE MEN handshake and
the M4 determinism investigation.
