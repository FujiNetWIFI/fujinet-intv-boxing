# Claude guidance for fujinet-intv-boxing

Eleventh FujiNet netplay port (Boxing, Mattel 1980), the fifth strictly
2-player port. **Read `PORTING.md` before touching anything** — it is the
accumulated methodology of all eleven ports; `spikes/NOTES.md` has this
cart's evidence trail (M0 the `X_MUSIC_TICK` placeholder proven
load-bearing rather than precautionary, M1 the native-dispatch table +
`as1600`-vs-bare-invocation memattr trap, M2 the clean 20 Hz measurement,
M3 the CHOOSE MEN handshake fully root-caused by live single-instruction
stepping, M4 the determinism investigation).

**Mostly working, one open item.** `verify-org` → `verify-patch` (39
words) → `check-7000` → every build variant assembles clean →
live boot-dump matches the recon-predicted state → wall tick rate
measured at exactly 20.0 Hz → `lagcheck` PASS (peak 199/209 at shift=20
vs. a 0-20/209 baseline) → `echo-test` (100 clean rounds) →
`server-diff` (6/6 clean, 2 seats) → `rig PLAYERS=2` (0 CRC mismatches)
→ `peerleft PLAYERS=2` (both leave modes) → hardware images built
(`build/boxing_net.rom`, `build/boxing_nethud.rom`). **`make det`
FAILS** (2/256 checksum ticks differ, narrow and self-correcting,
isolated to the native timer-countdown mirrors) and **`make m4`
demonstrates the repair mechanism works** (the deliberately injected
fault IS fixed, the quiescent branch of `RS_PENDING` IS confirmed
firing) **but doesn't end cleanly** because the `det` residual keeps
triggering further resyncs across a long run. Not yet run on real
hardware — that needs the user. Port 9112 / Lobby appkey 20 need
provisioning on `fujinet.online` before a production launch.

Hard rules, most of them learned the expensive way elsewhere:

- Never let any segment map `$7000`: the EXEC boot EXECUTES the word
  there. `make check-7000` guards it; the `NET_SESSION` block ORGs at
  `$D000`.
- Never put netcode RAM below `$8080` (STIC alias).
- **Always build with `make <target>`, never a bare `as1600`
  invocation**, when testing a fresh build variant. A hand-assembled
  `.cfg` is missing the `[memattr] $8000-$9BFF = RAM 8` line `make`'s
  recipes append as a separate step — without it, cart RAM reads as
  unmapped, and the symptom is a CONTENT-INDEPENDENT crash at a fixed
  cycle count that looks exactly like a real code bug (cost a genuine
  side-investigation this session before the pattern gave it away).
- Native dispatch, 4 of 5 entries (`BX_TICK2/3/4/5`, PORTING.md §7.31),
  the widest application yet. `MASTER_TICK` occupies slot 1, not slot 0
  — a stopped `X_MUSIC_TICK` placeholder MUST stay at slot 0, and it is
  provably load-bearing here (not just precautionary): the cart's own
  ISR calls `X_PLAY_NOTE`, and the EXEC's note engine reprograms
  whatever sits at table slot 0's countdown unconditionally whenever a
  note is playing.
- Boxing is **dispatch-only for input** (zero `$011F`-`$0124` reads
  anywhere in the ROM) and has **no turn arbiter** — both seats' events
  replay every tick via the EXEC's own controller-index handoff (`R1`
  into the handler), which Boxing's shared per-seat handler body relies
  on directly.
- The "CHOOSE MEN" prompt is a real, sequential 2-seat handshake:
  digit-select then ENTER, per seat, and picking the SAME digit as the
  other seat is silently rejected by the game's own duplicate-pick
  guard — `SCRIPT_TBL` (`src/vdispatch.asm`) sends different digits per
  seat. This was found by live single-instruction stepping (jzIntv's
  `s` command, **not** `n`, which unsets a breakpoint), not by static
  disassembly alone — see `spikes/NOTES.md` M3 for the full trace.
- Boxing owns its own frame ISR (unlike every 2-player predecessor):
  `RS_CLAMP_ISR` is load-bearing (Soccer's shape), and a game-logic
  busy-wait at `$56C9` reads `$0102` directly with its own `EIS` —
  canonicalized via `tools/patches.py`'s 39th site.
- `r N` in jzIntv scripts counts INSTRUCTIONS (~200k/emulated second);
  breakpoint-forced injection is exploration-only; exact-tick gates use
  the in-ROM `SCRIPT_TBL` or `TRACE_DONE` parks, never a breakpoint
  count.
- Rig scripts pkill `fujinet -u 127.0.0.1:1808` — never type that
  pattern in an interactive shell command line (`pkill -f` matches your
  own shell and kills it).
- The default FujiNet-workspace BOIP port (9995) may already be held by
  an unrelated project's long-running `fujinet-pc-rs232` instance on a
  shared workstation — point `FN_BOIP=` at a free port with a matching
  `fnconfig.ini` edit if so; this is not a Boxing-specific defect.

Gate ladder (each must pass before the next is worth trusting): verify-org
→ verify-patch → check-7000 → every build variant assembles → live
boot-dump → wall tick rate → lagcheck → det (currently failing, see
above) → echo-test → server-diff → rig PLAYERS=2 → m4 PLAYERS=2 (+
QUIESCE=1, repair mechanism confirmed, overall cleanliness blocked by
the det residual) → peerleft PLAYERS=2 (both leave modes) → hardware.

Assignments: production port 9112, FujiNet Lobby appkey 20, maxplayers 2.
The server (`server/intv_relay_server.py`) is protocol v2 (seat-tagged,
rooms), `MAX_SEATS=2`; `server/c/` is the generic C relay, held to
byte-for-byte equality by `tools/server_diff.py --seats 2` (copied from
Sea Battle's 2-seat-pinned version — Golf's own `server_diff.py` is
pinned at 4 and is NOT the right template for a 2-seat port; caught
before running the diff, not after).

Known open item (the one that matters most for continued work): `make
det`'s residual. One class (a real-frame `$0102` busy-wait in the
punch-connect timing check) was fully root-caused by live
single-instruction stepping and fixed. A second, narrowed to
`BX_TICK2`'s native countdown mirror (`SC_CNT2/3`), was found but not
yet reconciled — the working hypothesis is a second, distinct real-frame
interaction between the stall injector's `$0102` save/restore and the
EXEC main loop's own pass-retrigger logic at `$108F`, untested before
time ran out on the investigation this session. Next step: a live
`$0102`/`$108F` trace across a stall boundary, the same methodology that
found the first leak. See `spikes/NOTES.md` M4 for the complete,
reproducible investigation (exact ticks, exact checksums, exact
diagnostic narrowing steps) — this is a well-scoped problem, not a
mystery to re-derive from scratch.
