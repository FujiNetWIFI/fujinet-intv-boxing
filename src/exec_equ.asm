; EXEC ROM entry points and RAM locations used by the netcode patch.
; Addresses are the shared EXEC's (identical across all eleven ports).
;
; Boxing calls X_RAND1 once and X_RAND2 seven times (M0, recon.py + dis1600
; confirmed) -- every one needs a canonical-RNG wrapper (§5.2).

EXEC_RNG        EQU     $035E   ; 16-bit LFSR state (System RAM)
EXEC_ISR_DEF    EQU     $1126   ; the EXEC's default game-time ISR
X_RAND1         EQU     $167D
X_RAND2         EQU     $169E
X_MUSIC_TICK    EQU     $1A71   ; music note-timer routine.  Kept as
                                ;  NEW_TIMER_TBL slot 0, stopped -- the
                                ;  defensive placeholder every port in the
                                ;  family uses, REGARDLESS of whether the
                                ;  cart's own table has a music entry.
                                ;
                                ;  ** Confirmed load-bearing on THIS cart **
                                ;  (M0, a deeper pass than the "does the cart
                                ;  have a music slot" question the earlier
                                ;  ports asked): Boxing's custom ISR ($58E1)
                                ;  jumps to X_PLAY_NOTE ($1ABD) at $592A --
                                ;  a real, reachable call, not dead code.
                                ;  X_PLAY_NOTE's own per-pass duration
                                ;  countdown feeds a SEPARATE EXEC routine at
                                ;  $1A61 ("sfx entry") which, whenever a note
                                ;  is actively playing, calls $1831 (.EXEC.831,
                                ;  "set countdown := R0") with R1 = the
                                ;  header's timer-table BASE POINTER
                                ;  UNCHANGED -- i.e. offset ZERO from the
                                ;  table base, which .EXEC.811 (the shared
                                ;  countdown-address computer, traced in
                                ;  full: SUBR table_base,R1 / SAR R1,1 / ADDI
                                ;  #$0125,R1) resolves to exactly $0125,
                                ;  ALWAYS -- i.e. table SLOT 0's countdown,
                                ;  regardless of what the cart put there.
                                ;  Without the placeholder, MASTER_TICK would
                                ;  have occupied slot 0 directly (Boxing's
                                ;  original table has no music entry, unlike
                                ;  every other port that already carries this
                                ;  comment) and the EXEC's own note-duration
                                ;  engine would silently stomp the entire
                                ;  netcode dispatcher's countdown every time a
                                ;  punch/bell sound plays -- invisible to
                                ;  every CRC gate (both consoles reprogram it
                                ;  identically) but a real, periodic stall.
                                ;  Costs one dummy table row; keep it anyway.

; EXEC decoded per-controller input cells -- the canonical raw-decode names
; the shared vdispatch.asm engine reads directly for local single-console
; capture (VIRT_CAPTURE's live-pad path, REC_CAPTURE).  Boxing itself never
; reads these (see EXEC_HTBL below), so there is no shadow-pair PATCH site
; for them -- these equates exist purely so the generic engine assembles.
EXEC_IN_L       EQU     $011F   ; left/seat-0 decoded movement input
EXEC_IN_R       EQU     $0120   ; right/seat-1 decoded movement input
EXEC_KP_L       EQU     $0121   ; left/seat-0 keypad/action cell
EXEC_KP_R       EQU     $0122   ; right/seat-1 keypad/action cell

; EXEC decoded per-controller input cells.  Boxing is DISPATCH-ONLY (M0):
; zero references to $011F/$0120/$0121/$0122/$01FE/$01FF anywhere in the
; ROM -- no MVII base, no CMPI bound, no walking pointer (confirmed by a
; full linear word scan AND cross-checked against the assembled dis1600
; listing: the only two hits for $0121/$0123 sit inside a DECLE data table
; at $5787-$5796, not in any reachable instruction stream).  All input
; reaches game code through the $035D handler table; the EXEC's own scan
; hands each handler R1 = the controller/seat index (0 = left, 1 = right)
; via `SUBI #$011F,R1` immediately before the dispatch jump ($15F6/$15F8),
; and Boxing's handlers ARE seat-aware (the shared per-seat body at $5951
; indexes state with `ADDR R1,R3`) -- so, unlike Bowling/Golf, there is NO
; turn arbiter: both seats' events replay every tick (Sea Battle's shape).
EXEC_HTBL       EQU     $035D   ; input-handler table pointer (game-managed)

; Original game timer entries.  Original table at $501C, FIVE entries (4
; words each: addr lo/hi, interval lo/hi), NO music entry in slot 0 --
; recon.py's own table matches this file's header comment exactly.
;
; ** NATIVE DISPATCH (PORTING.md §7.31), not full virtualization -- Boxing
; is the SECOND port to use it (after Sea Battle's two-of-three) and the
; first to leave FOUR of five entries native.  $17D5 (the EXEC's own
; table-walk dispatcher) cannot reach a later slot's dispatch check until
; an earlier slot's JSR fully returns, so as long as MASTER_TICK is dispatched
; FIRST (immediately after the music placeholder), every entry after it --
; including any mid-tick stall, which spins INSIDE MASTER_TICK before it
; returns -- freezes exactly as atomically as a virtualized entry would,
; with zero hand-rolled countdown code for the four native slots. **
;
; NEW_TIMER_TBL layout (src/hook.asm), 6 slots:
;   slot 0  X_MUSIC_TICK, stopped        -> countdown $0125/$0126 (defensive
;           placeholder, see X_MUSIC_TICK above; EXCLUDED from the CRC --
;           real-frame sound-engine state, like $035E/$035F, not sim state)
;   slot 1  MASTER_TICK, interval 1      -> countdown $0127/$0128.  Our
;           dispatcher; always armed, never stopped by any cart code (M0:
;           zero timer-API references to the ORIGINAL slot-0 address
;           $501C) -- not tracked, trivially derived from tick parity.
;   slot 2  BX_TICK2 ($52F2), UNCHANGED target+interval ($0010, 20/16 Hz)
;           -> countdown $0129/$012A (BX_CNT2_LO/HI).  Armed/stopped by the
;           cart via the timer API (3 sites) -- MIRRORED (SC_CNT2/SC_CNT3).
;   slot 3  BX_TICK3 ($5297), UNCHANGED target+interval ($0010)
;           -> countdown $012B/$012C (BX_CNT3_LO/HI).  Armed/stopped (2
;           sites) -- MIRRORED (SC_CNT4/SC_CNT5).
;   slot 4  BX_TICK4 ($5A0F), UNCHANGED target+interval ($0001, 20 Hz)
;           -> countdown $012D/$012E (BX_CNT4_LO/HI).  Armed/stopped (2
;           sites, incl. the 3-slot stop-all loop) -- MIRRORED
;           (SC_CNT6/SC_CNT7).
;   slot 5  BX_TICK5 ($57AB), UNCHANGED target+interval ($0001)
;           -> countdown $012F/$0130.  NEVER armed/stopped by any cart code
;           (M0: zero timer-API references to the original slot-4 address
;           $502C, exactly like slot 1/MASTER_TICK) -- not tracked.
;
; Confirmed live (M0, dis1600 disassembly of every timer-API call site,
; cross-checked against .EXEC.811's exact address arithmetic at $1811-
; $181D): every ARM/STOP site passes R1 = the ORIGINAL header table's slot
; address as an immediate operand right before the JSR -- these go stale
; once the table relocates, and (following Sea Battle's SB_START_SHIM
; precedent -- the one real-hardware-verified example of a NATIVE, non-
; virtualized entry's arm/stop path in this family) each JSR TARGET is
; retargeted to BX_ARM_SHIM/BX_STOP_SHIM rather than calling through the
; real X_TIMER_START/X_TIMER_STOP with just the operand repatched: real ARM
; semantics only clear bit 15 of the CURRENT countdown value (no magnitude
; reset), and reimplementing that directly against the known real cell
; sidesteps ANY question about whether X_TIMER_START's own header-relative
; arithmetic is safe to call through post-relocation.
BX_TICK2        EQU     $52F2   ; interval $0010 (1.25 Hz @ 20Hz tick base)
BX_TICK3        EQU     $5297   ; interval $0010
BX_TICK4        EQU     $5A0F   ; interval $0001 (20 Hz)
BX_TICK5        EQU     $57AB   ; interval $0001 (20 Hz) -- native, unmirrored
BX_TICK1        EQU     $51F0   ; interval $0001 (20 Hz) -- MASTER_TICK calls
                                ;  this ORIGINAL slot-0 body directly every
                                ;  tick.  Nothing else in the relocated table
                                ;  reaches it (PORTING.md §7.31's own trap:
                                ;  a table-relocation that drops the ONLY
                                ;  caller of a replaced slot's target is
                                ;  invisible to `make det`, which only proves
                                ;  two builds agree with each other -- verify
                                ;  against a live boot dump, not just a green
                                ;  gate).
BX_START        EQU     $5053   ; original start-of-game vector target

BX_CNT2_LO      EQU     $0129   ; BX_TICK2's real countdown (slot 2)
BX_CNT2_HI      EQU     $012A
BX_CNT3_LO      EQU     $012B   ; BX_TICK3's real countdown (slot 3)
BX_CNT3_HI      EQU     $012C
BX_CNT4_LO      EQU     $012D   ; BX_TICK4's real countdown (slot 4)
BX_CNT4_HI      EQU     $012E

; Symbolic slot addresses within NEW_TIMER_TBL -- these are what the four
; timer-API patch sites' MVII operands are repatched to, and what
; BX_ARM_SHIM/BX_STOP_SHIM dispatch R1 against.  Defined in src/hook.asm,
; right after NEW_TIMER_TBL (as1600 EQU requires a computable expression at
; the point of definition, and NEW_TIMER_TBL isn't declared until hook.asm):
; BX_SLOT2 = NEW_TIMER_TBL+8, BX_SLOT3 = +12, BX_SLOT4 = +16, following
; directly from the 6-slot, 4-word-per-slot layout -- slot 0 at +0, slot 1
; (MASTER_TICK) at +4, slot 2 at +8, slot 3 at +12, slot 4 at +16, slot 5
; at +20.

; The dynamic $035D phase machine.  Three installs (M0):
;   $509F -> $5932  BX_HTBL_PROMPT  "CHOOSE MEN" pre-game keypad prompt
;   $53B6 -> $593C  BX_HTBL_LIVE    live in-round play (destination phase,
;                                    §5.5/PORTING.md's det/rig/m4 assertion)
;   $52CF -> $1906  EXEC null table, installed at match end, immediately
;                    before the 3-slot timer stop-all loop -- the strongest
;                    available "match is over" signal, and readable for
;                    free off the already-captured GAME_TBL_LO/HI cells.
BX_HTBL_PROMPT  EQU     $5932
BX_HTBL_LIVE    EQU     $593C

; §7.6 quiescent point candidate (to be CONFIRMED at M4 against a live
; scripted-round boot dump, not assumed from static analysis alone --
; PORTING.md's own repeated lesson).  $017C is set to 1 at $52C9, the
; instruction immediately before the match-end null-table install at
; $52CF -- readable without any extra CRC/image cell, since $017C already
; sits inside the standard $015D-$01EF range.  Whether this is a per-ROUND
; or per-MATCH transition (and therefore how OFTEN the resync gate actually
; gets to use it under real fuzzed play) is exactly what M4's scripted-round
; boot dump needs to establish; see PORTING.md §7.29 -- if masked disc-only
; fuzz can never knock a boxer down, the QUIESCE=1 forcing mode is what
; proves the branch at all.
BX_MATCHOVER    EQU     $017C

; --- Symbols resync.asm/lockstep.asm expect under canonical (SC_*) names ---
SC_PASSLEN      EQU     $0103   ; real EXEC pass-length cell; kept in the
                                ;  resync tail as free insurance and to keep
                                ;  the family's tail layout identical
; SC_ISR_SAVE: Boxing's own saved interrupt vector (its .START stashes the
; live $0100/$0101 into $01A8/$01A9 and its custom ISR body jumps through
; that pair unconditionally when $0102 falls out of range) -- a REAL,
; load-bearing code-pointer clamp target, unlike Sea Battle's harmless spare
; (PORTING.md §7.27, Soccer's RS_CLAMP_ISR shape).
SC_ISR_SAVE     EQU     $01A8

; DANCE_SETTLE (src/vdispatch.asm, copied unchanged) unconditionally checks
; $0101 against SC_ISR_BODY's page before repainting a terminal screen
; (PORTING.md §7.10).  Boxing's custom ISR body lives at $58E1, page $58.
SC_ISR_BODY     EQU     $5800
