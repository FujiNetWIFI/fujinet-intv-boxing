# Boxing (Mattel 1980) — eleventh port, evidence trail

Read `PORTING.md` first. This file is the cart-specific investigation log:
what was measured, what was found live, and the reasoning behind each
design decision that isn't already captured in source comments.

## M0 — Recon and scaffold

`tools/recon.py rom/Boxing.bin` output matched PORTING.md §3's own
prediction table for Boxing exactly: timer table `$501C`, start-of-game
`$5053`, 5 timer entries (no music slot), 8 RNG sites (1× X_RAND1, 7×
X_RAND2), 4 timer-API sites, dispatch-only input (zero `$011F`-`$0124`
references anywhere in the ROM — confirmed twice, once by recon's own
linear scan and once by grepping the full `dis1600` listing for the two
false-positive hits it did find, both inside a DECLE data table at
`$5787-$5796`, not reachable code).

`make verify-org` passed immediately (byte-identical rebuild). Full
`make dis` confirmed: no JSR to `$108F/$11FA/$17D5/$1AAD` (no cart
main-loop clone, §7.15 N/A), no reference to `$14F1` (§7.26 N/A), no
`MVII/MVO` of R6 (no SP reset).

**A finding not in the original plan**: the disassembly showed a real,
reachable call from the cart's own custom ISR (`$58E1`) to
`X_PLAY_NOTE` ($1ABD) at `$592A`. Tracing the EXEC's own sound-engine
internals ($1A61 "sfx entry" → `.EXEC.831`/`$1831`, the "set countdown :=
R0, music" entry) showed it computes the target countdown address as
`$0125 + (table_base - table_base)/2 = $0125` — i.e. **table slot 0,
unconditionally**, regardless of what the cart's own table puts there,
whenever a note is actively playing. Every prior port's `hook.asm` already
carries a comment about this exact hazard and defends against it with a
stopped `X_MUSIC_TICK` placeholder at slot 0 even when the CART's OWN
table has no music entry — but this is the first port where that
defense is *provably* load-bearing rather than precautionary, since
Boxing's ISR genuinely calls into the note engine. Without the
placeholder, `MASTER_TICK` (the natural choice for slot 0, since
Boxing's original table has no music entry either) would have had its
own dispatcher countdown silently stomped by the EXEC every time a
punch/bell sound plays. This became `exec_equ.asm`'s `X_MUSIC_TICK`
comment and the reason `NEW_TIMER_TBL` has 6 slots, not 5.

## M1 — Hook, patch map, native dispatch

**Native dispatch, 4 of 5 entries** (PORTING.md §7.31), the widest
application yet (Sea Battle did 2 of 3). Table layout:
slot 0 `X_MUSIC_TICK` (placeholder) → slot 1 `MASTER_TICK` → slots 2-5
`BX_TICK2/3/4/5`, all four native, unchanged target+interval.
`MASTER_TICK` calls `BX_TICK1` ($51F0, the ORIGINAL slot-0 body) directly
every tick — nothing else in the relocated table reaches it.

Timer-API arm/stop sites (4, all `SDBD MVII #addr,R1` immediately before
the JSR): decoded and confirmed the exact word offsets by hand
(the MVII's *immediate operand words* are two positions after the
opcode, not the opcode itself — an easy off-by-one made and caught during
this session's first patches.py draft, before any build was attempted).
Followed Sea Battle's `SB_START_SHIM` precedent — shims that flip the
real countdown's bit-15 stop flag directly — rather than repatching the
operand and calling through the real `X_TIMER_START`/`STOP`, since that
approach's safety for a *native* (non-virtualized) entry was never
actually proven in this family and Sea Battle's one real example chose
not to risk it.

`make verify-patch`: 38 declared sites (later 39, see M4), all confirmed
changed and nothing else. `make check-7000`: clean. Live boot-dump
(§7.31's own required verification, not just a green `make det`):
$035D reached $5932 (`BX_HTBL_PROMPT`) after boot, proving `BX_TICK1` is
genuinely being called and `.START`'s own logic ran to completion.

**A real toolchain trap, costly in wall-clock time before being found**:
every `main_*.asm` variant built directly with `as1600` (bypassing
`make`) produces a `.cfg` missing the `[memattr] $8000-$9BFF = RAM 8`
line — `make`'s own recipes append it as a separate step after
assembly. Without it, cart RAM reads as unmapped/floating, and the
symptom is a CONTENT-INDEPENDENT crash ("CPU off in the weeds", PC lands
on $0001) at a FIXED cycle count regardless of what the ROM actually
does — deterministic and reproducible, which makes it look exactly like
a real code bug. Cost a long side-investigation (chasing a "crash" that
was actually just missing RAM) before the pattern (`b?` set fine, `r N`
runs fine, then garbage) gave it away. **Always use `make <target>`,
never a bare `as1600` invocation, when testing a fresh build variant.**

## M2 — Wall tick rate

Measured at `MASTER_TICK` ($6044 in the hook build), 10 consecutive
samples after settling past boot: **44,802 cycles between consecutive
hits, exactly 3.000 NTSC frames, 20.0 Hz** — matching the header-implied
rate exactly, matching Armor Battle's own "cleanest cadence" reference
point in PORTING.md §2.2. Despite owning its own ISR (unlike every prior
"clean" example), Boxing's ISR does not skip counting real frames the
way Soccer's scroll dance does — no §7.28 surprise here.

## M3 — Interception proof (lagcheck) and the CHOOSE MEN handshake

Boxing opens on a keypad-driven "CHOOSE MEN" prompt
(`GAME_TBL == BX_HTBL_PROMPT == $5932`) that masked ($3F) disc-only fuzz
can never answer (§7.25) — this needed a real demo script, and getting
it right took most of this milestone's session.

**Root-caused by live single-instruction stepping** (jzIntv's `s`
command — **not** `n`, which unsets a breakpoint; a real trap the first
time through) with breakpoints at every conditional branch in the
prompt's keypad handler ($597E, table offset +2):

- The disc slot (table+0, `$5347`) is a preview cursor only.
- The keypad slot (`$597E`) accepts digits 1-6 (`CMPI #$0006,R0 / BGT
  ...reject`) and ENTER (`R0 == $0B`, matching the `$0B` convention every
  sibling port's `ARB_INJECT` already uses for this key).
- On ENTER, it cross-checks the OTHER seat's confirmed-flag
  (`$01AC`+seat — `$01AD` for seat 0's check of seat 1, `$01AC` for seat
  1's check of seat 0, computed via `$01AD - seat`). If the other seat
  hasn't confirmed, this is a no-op "mark myself confirmed" and returns.
- **If the other seat HAS confirmed, a second check compares the two
  seats' STORED DIGITS** (`$01AE`/`$01AF`) and treats an EQUAL pick as
  "duplicate, ignore" — silently returning without transitioning.
  Sending digit #1 to both seats (the natural first attempt) hits this
  branch every single time: **two boxers can't be the same pick**, and
  the guard eats the second ENTER, parking the whole run at
  `BX_HTBL_PROMPT` forever with every checksum agreeing trivially —
  PORTING.md §5.5's exact trap, a new concrete instance of it.
- Only reached with DIFFERENT digits: `$59BA` pushes `$50A2` as a
  computed tail-call return address; the handler's own shared
  `$59A2-$59AA` cleanup path's final `PULR R7` pops that instead of the
  real caller, jumping into `$50A2`'s install-the-live-table sequence.

`SCRIPT_TBL` (`src/vdispatch.asm`) sends seat 0 → boxer #1, seat 1 →
boxer #2, confirmed live to reach `BX_HTBL_LIVE` ($593C).

**Lagcheck design note**: an early attempt using long (15-tick) sustained
disc holds scored the correct top peak (shift=20, 199/209) but not
clearly enough above the shift=0 baseline (178/209) to pass the gate —
because the prompt's disc/preview handler only reacts to FRESH `$011F`
events, not the held level, so long holds are mostly flat, repeated
ticks that dilute the cross-correlation. Switching to single-tick
alternating disc pulses (a fresh edge nearly every tick) sharpened the
signal to shift=20 (199) vs. a **0-20/209** baseline — an enormous
margin. `make lagcheck`: **PASS**.

## M4 — Determinism

RNG wrappers (`BX_RAND1`/`BX_RAND2`, `src/hook.asm`) follow the
family's canonical swap-in/DIS/call/swap-out/EIS pattern exactly; all 8
call sites confirmed patched (`make verify-patch`).

`make det` (script + destination-phase assertion: `GAME_TBL == $593C`,
seats picked different boxers) reaches real round play cleanly, but
**does not currently show a clean checksum PASS**. Two real,
root-caused, narrow divergences were found, both isolated to the
timer-tail (`SC_CNT2-7`, the native countdown mirrors) by temporarily
narrowing `debug.asm`'s `TRACE_RANGES` as a diagnostic (excluding the
whole tail made both disappear; re-including it and excluding only
`SC_CNT6/7` isolated the first to `BX_TICK4`'s mirror, then further
narrowing to `SC_CNT2/3` isolated the second to `BX_TICK2`'s):

1. **Found and fixed**: `$56C9` is a real-gameplay busy-wait (the
   punch-connect timing check, gated behind a proximity test) that reads
   the EXEC's own ISR phase counter `$0102` **directly**, with its own
   `EIS` to let the ISR keep advancing it while it polls —
   `MVI $0102,R1 / EIS / CMPI #$0001,R1 / BGT $56C9`. This is entirely
   outside the documented `X_TIMER`/pass-gate API and invisible to any
   JSR-based recon scan (there is no JSR at all — it's a direct memory
   read). It watches real, sub-tick frame timing; a netcode stall (the
   test injector and the real lockstep freeze both save/force-0/restore
   `$0102` identically) does not preserve the real-time relationship
   this specific poll depends on. **Fix**: redirect the operand from
   `$0102` to `RS_SPARE0` (always-zero netcode RAM) — `0 <= 1` satisfies
   the loop on the very first check, deterministically, on every
   console, stalled or not. This is `tools/patches.py`'s 39th site.
   Confirmed via a live breakpoint that the patched build correctly
   reads `$8102` at that address. This eliminated the tick-917
   divergence (in `BX_TICK4`'s mirror) *when tested in isolation with the
   timer tail narrowed to exclude it* — but did NOT eliminate it when
   re-tested against the full range; see below.
2. **Found, not yet resolved**: a second, separate divergence appears at
   tick 768 in `BX_TICK2`'s countdown mirror (`SC_CNT2/3`) — present both
   before and after the `$56C9` fix, and (with the fix applied) the
   original tick-917 divergence *also reappeared* when tested against
   the unmodified full range, contradicting the isolated result. This is
   not yet reconciled: the working hypothesis is a second, distinct
   real-frame-timing interaction between the stall injector's `$0102`
   save/restore and the EXEC main loop's own pass-retrigger logic at
   `$108F` (untested: whether a sufficiently long stall can leave `$0102`
   restored to a value that causes `$108F` to detect more than one pass
   as due in immediate succession, effectively letting `$17D5` walk the
   table more than once for what the sim accounts as a single tick) —
   but this was not confirmed by live tracing before time ran out on
   this investigation for the current session.

**Current status, stated plainly**: `make det` FAILS (2/256 checksum
ticks differ; both builds park at the same tick with an *identical*
settled state — the divergence is narrow and self-correcting, not
runaway). This is a real, open item, not a shrug — the `$56C9` class was
fully root-caused and fixed, and the remaining divergence is narrowed to
a specific 6-cell sub-range with a documented next hypothesis. Following
Sea Battle's own precedent (`CLAUDE.md`: "a real, narrow desync in the
map-phase idle bookkeeping that the resync safety net successfully
recovers from every time... accept this as-is and continue"), this
session's decision is to **proceed to M5-M7 rather than block
indefinitely on full elimination**, since the CRC+resync mechanism
(built at M6) is specifically the safety net for exactly this class of
residual, and confirming the rest of the pipeline is more valuable than
perfecting one narrow determinism gap in isolation. Revisit with a live
`$0102`/`$108F` trace across a stall boundary before shipping to
production if this needs to be fully closed.

## Assignments

Production port **9112**, FujiNet Lobby appkey **20**, `MAX_SEATS = 2`
(next free after Soccer 9109/17, Sea Battle 9110/18, Golf 9111/19).
`server/intv_relay_server.py` is protocol v2, pinned at `MAX_SEATS = 2`;
`tools/server_diff.py` is Sea Battle's 2-seat-pinned version (Golf's is
pinned at 4 and was NOT the right template to copy verbatim — caught
before running the diff, not after).
