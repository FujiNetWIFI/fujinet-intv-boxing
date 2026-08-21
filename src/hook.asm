; Netcode hook segment for Boxing (Mattel 1980).
;
; STATUS: M0 recon complete (spikes/NOTES.md).  Header relocation, both RNG
; wrapper flavours (8 sites: 1x X_RAND1, 7x X_RAND2), and all four timer-API
; shim sites are the declared patch map (tools/patches.py).
;
; The cart header's timer-table pointer ($5002) is patched to NEW_TIMER_TBL:
;
;   slot 0  X_MUSIC_TICK, stopped  -> countdown $0125/$0126.  Defensive
;           placeholder every port in the family uses -- CONFIRMED
;           load-bearing on this cart specifically (exec_equ.asm): the
;           custom ISR calls X_PLAY_NOTE, which reaches an EXEC routine
;           that reprograms table SLOT 0's countdown via the header
;           pointer whenever a note plays, regardless of what the cart put
;           there.  Without this placeholder, MASTER_TICK (which WOULD
;           otherwise be the natural choice for slot 0 -- Boxing's original
;           table has no music entry) would have its own dispatcher
;           countdown silently stomped every time a punch/bell sound plays.
;   slot 1  MASTER_TICK, interval 1, always armed -> countdown $0127/$0128.
;           Our master dispatcher, every pass.  Calls BX_TICK1 ($51F0, the
;           ORIGINAL slot-0 target) directly -- nothing else in the
;           relocated table reaches it (PORTING.md §7.31).
;   slot 2  BX_TICK2 ($52F2), NATIVE -- unchanged target+interval.
;   slot 3  BX_TICK3 ($5297), NATIVE -- unchanged target+interval.
;   slot 4  BX_TICK4 ($5A0F), NATIVE -- unchanged target+interval.
;   slot 5  BX_TICK5 ($57AB), NATIVE -- unchanged target+interval.
;
; §7.31's native-dispatch shortcut applies to FOUR of five entries (Sea
; Battle's precedent was two of three): $17D5 cannot reach slot 2's
; dispatch check until MASTER_TICK (slot 1) fully returns, so a stall
; spinning inside MASTER_TICK freezes every later native slot exactly as
; atomically as a virtualized one would, with zero hand-rolled countdown
; code.  The cost this port pays that Sea Battle didn't: THREE native
; entries (slots 2/3/4) are armed/stopped by cart code via the timer API
; (Sea Battle had only one), so all three need a real-countdown mirror in
; the CRC/resync image, not just one (ram.asm/exec_equ.asm).  Slots 1 and
; 5 are never armed/stopped by any cart code (M0: zero timer-API
; references to the original $501C/$502C slot addresses) and need no
; tracking at all.
;
; No X_SCAN self-call hazard: zero references to $14F1 anywhere in the ROM
; (M0), so $035D only needs nulling AFTER the tick, not before as well
; (unlike NASL Soccer, PORTING.md §7.26).
;
; Cart ISR: Boxing installs its OWN ISR body at $58E1 (.START saves the
; live vector to $01A8/$01A9 first).  RS_CLAMP_ISR (resync.asm) forces both
; the saved pair and the live $0100/$0101 back to the EXEC default after
; every state apply -- PORTING.md §7.27's code-pointer clamp, load-bearing
; here (the pair sits inside image section 1 and gets transported whether
; wanted or not).  The wall tick rate must be MEASURED at MASTER_TICK
; (§7.28), never taken from the header, because this ISR decrements $0102
; itself -- confirm at M2.
;
; Boxing is STRICTLY 2 SEATS, simultaneous, DISPATCH-ONLY input (M0: zero
; polled $011F/$0120/$0121/$0122 reads anywhere in the ROM), NO turn
; arbiter: the EXEC scan hands each handler R1 = the seat index via
; `SUBI #$011F,R1` before the dispatch jump, and Boxing's shared per-seat
; handler body indexes state directly off R1 -- so VD_CTRL must track
; VD_SIDE (unlike Golf, where every handler ignores it and VD_CTRL stays a
; hardcoded 0).  Both seats replay every tick, Sea Battle's shape; there is
; no SHADOW_CTRL/UPDATE_SHADOW surface at all, because there is nothing to
; poll.

        ORG     $6000

NEW_TIMER_TBL:
        DECLE   X_MUSIC_TICK AND $FF, X_MUSIC_TICK SHR 8
        DECLE   $01, $80                ; interval $8001: stopped, one-shot
        DECLE   MASTER_TICK AND $FF, MASTER_TICK SHR 8
        DECLE   $01, $00                ; every pass, always armed
        DECLE   BX_TICK2 AND $FF, BX_TICK2 SHR 8
        DECLE   $10, $00                ; original interval word, UNCHANGED
        DECLE   BX_TICK3 AND $FF, BX_TICK3 SHR 8
        DECLE   $10, $00                ; original interval word, UNCHANGED
        DECLE   BX_TICK4 AND $FF, BX_TICK4 SHR 8
        DECLE   $01, $00                ; original interval word, UNCHANGED
        DECLE   BX_TICK5 AND $FF, BX_TICK5 SHR 8
        DECLE   $01, $00                ; original interval word, UNCHANGED
        DECLE   $00, $00                ; terminator

; Symbolic slot addresses (exec_equ.asm) -- must follow NEW_TIMER_TBL since
; as1600 requires a computable EQU expression at the point of definition.
BX_SLOT2        EQU     NEW_TIMER_TBL+8
BX_SLOT3        EQU     NEW_TIMER_TBL+12
BX_SLOT4        EQU     NEW_TIMER_TBL+16

; ---------------------------------------------------------------------------
; NET_START -- patched start-of-game vector ($5004, original target
; BX_START = $5053).  Runs after the title screen, before the EXEC main
; loop starts (the EXEC jumps here with R5 = $108F), so netcode RAM is
; initialized before the first MASTER_TICK.  Falls through to the original
; .START, which sets up the "CHOOSE MEN" prompt.
;
; BX_TICK2/3/4's real countdowns need NO seeding here: the EXEC's own
; boot-time X_TIMER_INIT (run before .START, from the relocated header
; pointer) already copies NEW_TIMER_TBL's interval words into $0125-$0130,
; using the SAME words the original cart shipped with -- this is the whole
; benefit of leaving those entries native instead of virtualizing them.
; SC_CNT2-SC_CNT7's netcode-RAM mirror starts at NET_START's zero fill,
; which is harmless: MASTER_TICK's first tick refreshes it from the real
; cells before anything reads it.
; ---------------------------------------------------------------------------
NET_START:
        PSHR    R5                      ; EXEC main-loop return
        MVII    #NET_RAM, R4
        MVII    #NET_RAM_SIZE, R1
        CLRR    R0
@@zero: MVO@    R0,     R4
        DECR    R1
        BNEQ    @@zero
        MVII    #SPIKE_DELAY, R0        ; virt-dispatch delay depth (spike knob)
        MVO     R0,     DELAY_EN
        ; Seat defaults for local builds: seat 0 of a 2-player game.  The
        ; netplay path overwrites both from the START payload.
        MVII    #2,     R0
        MVO     R0,     NET_COUNT
    IF SPIKE_VIRT <> 0
        JSR     R5,     LS_RING_INIT    ; idle-fill the dispatch rings
    ENDI
    IF SPIKE_ECHO <> 0
        JSR     R5,     ECHO_TEST       ; parks with results; never returns
    ENDI
    IF NET_SESSION <> 0
        JSR     R5,     SES_MAIN        ; login/lobby; arms NET_ACTIVE or not
    ENDI
        PULR    R5
        J       BX_START

; NET_NULL_TBL: handed to the EXEC scan (via $035D) while dispatch is
; virtualized so its event dispatch resolves null pointers and never calls
; game code from real local input.  Zeros on both sides of the base cover
; negative slot indexes.
NET_NULL_TBL:
        DECLE   0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        DECLE   0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; ---------------------------------------------------------------------------
; MASTER_TICK -- timer entry 1 of NEW_TIMER_TBL, dispatched by the EXEC
; every main-loop pass.  May clobber R0-R3.  Returns via the dispatcher's
; R5.
; ---------------------------------------------------------------------------
MASTER_TICK:
        PSHR    R5
    IF STALL_N <> 0
        ; Stall injector (spike c): every 64th pass, busy-spin ~STALL_N
        ; frames INSIDE the dispatch.  The ISR keeps firing but $0102 sits
        ; at 0 mid-pass, so it takes its skip path: display continues,
        ; game logic freezes.
        MVI     FRM_CTR, R0
        INCR    R0
        ANDI    #$3F,   R0
        MVO     R0,     FRM_CTR
        BNEQ    @@no_stall
        DIS
        MVI     $102,   R2
        CLRR    R0
        MVO     R0,     $102
        EIS
        MVII    #STALL_N * 3000, R1     ; ~15 cycles/iter, ~1 frame per 1000
@@spin: DECR    R1
        BNEQ    @@spin
        DIS
        MVO     R2,     $102
        EIS
@@no_stall:
    ENDI
    IF NET_SESSION <> 0
        MVI     NET_ACTIVE, R0
        TSTR    R0
        BEQ     @@mt_local
        JSR     R5,     LS_PASS         ; lockstep netplay path
        PULR    R7
@@mt_local:
    ENDI
    IF SPIKE_RECORD <> 0
        JSR     R5,     REC_CAPTURE     ; log the live cells for this tick
    ENDI
    IF SPIKE_VIRT <> 0
        ; Virtualized local dispatch.  BOTH seats replay, every tick: there
        ; is no turn arbiter on this cart -- both boxers act simultaneously.
        JSR     R5,     VIRT_CAPTURE
        JSR     R5,     LS_TBL_ADOPT
        MVI     GAME_TBL_HI, R1
        SWAP    R1,     1
        ADD     GAME_TBL_LO, R1
        BEQ     @@mt_no_tbl
        MVO     R1,     $35D
@@mt_no_tbl:
        CLRR    R0
        MVO     R0,     VD_SIDE         ; seat 0
        MVO     R0,     VD_CTRL
        JSR     R5,     LS_VDISPATCH
        MVII    #1,     R0
        MVO     R0,     VD_SIDE         ; seat 1
        MVO     R0,     VD_CTRL
        JSR     R5,     LS_VDISPATCH
    ENDI
        JSR     R5,     BX_GAME_TICK
    IF SPIKE_VIRT <> 0
        JSR     R5,     LS_TBL_ADOPT
        MVII    #NET_NULL_TBL+4, R0
        MVO     R0,     $35D
    ENDI
    IF SPIKE_TRACE <> 0
        JSR     R5,     TRACE_TICK
    ELSE
        ; sim tick counter (16-bit across two 8-bit cells)
        MVI     TICK_LO, R0
        INCR    R0
        MVO     R0,     TICK_LO
        CMPI    #$100,  R0
        BNEQ    @@mt_out
        MVI     TICK_HI, R0
        INCR    R0
        MVO     R0,     TICK_HI
    ENDI
@@mt_out:
        PULR    R7

; ---------------------------------------------------------------------------
; BX_GAME_TICK -- dispatches BX_TICK1 (the ORIGINAL slot-0 body, which
; nothing else in the relocated table reaches -- PORTING.md §7.31) and
; mirrors the three native, timer-API-stoppable countdowns (slots 2/3/4)
; into netcode RAM for LS_CKSUM.  Shared by MASTER_TICK's local path and
; lockstep.asm's LS_PASS (both paths need it -- Sea Battle's hard-won
; rule, PORTING.md: NET_ACTIVE returns via LS_PASS before MASTER_TICK's
; local-only section is ever reached, so anything computed only there goes
; stale under real netplay).  Slots 2/3/4 themselves fire NATIVELY, called
; by $17D5 immediately after MASTER_TICK returns -- nothing to do for them
; here beyond the mirror copy.
; Clobbers R0/R1.  Returns via the caller's R5.
; ---------------------------------------------------------------------------
BX_GAME_TICK:
        PSHR    R5
        JSR     R5,     BX_TICK1
        ; Mirror the three native countdowns into netcode RAM.
        MVI     BX_CNT2_LO, R0
        MVO     R0,     SC_CNT2
        MVI     BX_CNT2_HI, R0
        MVO     R0,     SC_CNT3
        MVI     BX_CNT3_LO, R0
        MVO     R0,     SC_CNT4
        MVI     BX_CNT3_HI, R0
        MVO     R0,     SC_CNT5
        MVI     BX_CNT4_LO, R0
        MVO     R0,     SC_CNT6
        MVI     BX_CNT4_HI, R0
        MVO     R0,     SC_CNT7
        ; BX_QUIESCENT (exec_equ.asm's BX_MATCHOVER candidate -- CONFIRM
        ; at M4).  Purely derived from a cell already inside the standard
        ; CRC range.
        MVI     BX_MATCHOVER, R0
        TSTR    R0
        BEQ     @@gt_not_q
        MVII    #1,     R0
        MVO     R0,     BX_QUIESCENT
        B       @@gt_qout
@@gt_not_q:
        CLRR    R0
        MVO     R0,     BX_QUIESCENT
@@gt_qout:
        PULR    R7

; BX_POSSESSION -- lockstep.asm (generic, unchanged) calls this by name
; from LS_PASS, right after BX_GAME_TICK.  Boxing has no possession
; concept -- ARB_SEAT (ram.asm) stays declared and always zero.  Stub.
BX_POSSESSION:
        MOVR    R5,     R7

; ---------------------------------------------------------------------------
; BX_RAND1 / BX_RAND2 -- canonical-RNG wrappers for the game's eight RAND
; call sites (1x X_RAND1, 7x X_RAND2; M0, all confirmed genuine JSR
; instructions via the linear scan AND cross-checked in dis1600).  The EXEC
; sound engine advances the shared LFSR at $035E from ISR context whenever
; noise SFX play (§5.2) -- and Boxing plays plenty of them (punches, bell,
; crowd cheer) -- so game logic must not read $035E directly: swap the
; canonical (sim-space) value in, call the EXEC routine with interrupts
; off, swap the advanced value back out.
; Preserves R1/R2 like the underlying EXEC routines; result in R0.
; ---------------------------------------------------------------------------
BX_RAND1:
        PSHR    R5
        DIS
        JSR     R5,     @@swap_in
        JSR     R5,     X_RAND1
        B       @@swap_out

BX_RAND2:
        PSHR    R5
        DIS
        JSR     R5,     @@swap_in
        JSR     R5,     X_RAND2
@@swap_out:
        PSHR    R1
        MVI     EXEC_RNG, R1
        MVO     R1,     RNG_LO
        SWAP    R1,     1
        MVO     R1,     RNG_HI
        PULR    R1
        EIS
        PULR    R7

@@swap_in:
        PSHR    R1
        PSHR    R2
        MVI     RNG_HI, R1
        SWAP    R1,     1
        MVI     RNG_LO, R2
        ADDR    R2,     R1
        MVO     R1,     EXEC_RNG
        PULR    R2
        PULR    R1
        MOVR    R5,     R7

; ---------------------------------------------------------------------------
; BX_ARM_SHIM / BX_STOP_SHIM -- wired into tools/patches.py at all four
; original timer-API call sites.  Each site passes R1 = the address of the
; entry's slot WITHIN THE RELOCATED TABLE (already repatched by
; tools/patches.py from the original header-table address); the shims
; dispatch on R1 to flip the matching real countdown's stop bit directly,
; rather than calling through the real X_TIMER_START/X_TIMER_STOP --
; following Sea Battle's SB_START_SHIM precedent (the one real-hardware-
; verified example of a native, non-virtualized entry's arm/stop path in
; this family): real ARM semantics only clear bit 15 of the CURRENT
; countdown value (no magnitude reset -- if a stopped entry's countdown was
; left mid-count, re-arming resumes from THAT value, not a fresh reload),
; and STOP sets it.  Bit 15 is the top bit of the HIGH byte, so only the
; _HI cell needs touching.  The CP-1610 has no OR/ORI instruction (AND/XOR
; only) -- "set bit 7 unconditionally" is the standard idiom, clear it then
; XOR it back on: ANDI #$7F,R0 guarantees bit 7 is 0, so XORI #$80,R0
; against that guaranteed-0 bit is equivalent to OR.
; MUST preserve R1 and R2: $52D9's stop-all loop walks R1 across all three
; native slots with R2 as its loop counter, through BX_STOP_SHIM once per
; slot (PORTING.md §7.24's R1/R2 preservation rule).
; ---------------------------------------------------------------------------
BX_STOP_SHIM:
        CMPI    #BX_SLOT2, R1
        BNEQ    @@sp_2
        MVI     BX_CNT2_HI, R0
        ANDI    #$7F,   R0
        XORI    #$80,   R0
        MVO     R0,     BX_CNT2_HI
        MOVR    R5,     R7
@@sp_2: CMPI    #BX_SLOT3, R1
        BNEQ    @@sp_3
        MVI     BX_CNT3_HI, R0
        ANDI    #$7F,   R0
        XORI    #$80,   R0
        MVO     R0,     BX_CNT3_HI
        MOVR    R5,     R7
@@sp_3: MVI     BX_CNT4_HI, R0          ; BX_SLOT4 (only remaining case)
        ANDI    #$7F,   R0
        XORI    #$80,   R0
        MVO     R0,     BX_CNT4_HI
        MOVR    R5,     R7

BX_ARM_SHIM:
        CMPI    #BX_SLOT2, R1
        BNEQ    @@sa_2
        MVI     BX_CNT2_HI, R0
        ANDI    #$7F,   R0
        MVO     R0,     BX_CNT2_HI
        MOVR    R5,     R7
@@sa_2: CMPI    #BX_SLOT3, R1
        BNEQ    @@sa_3
        MVI     BX_CNT3_HI, R0
        ANDI    #$7F,   R0
        MVO     R0,     BX_CNT3_HI
        MOVR    R5,     R7
@@sa_3: MVI     BX_CNT4_HI, R0          ; BX_SLOT4 (only remaining case)
        ANDI    #$7F,   R0
        MVO     R0,     BX_CNT4_HI
        MOVR    R5,     R7

; ---------------------------------------------------------------------------
; BX_REBASE_HOOK -- called from resync.asm's RS_REBASE (one added line;
; resync.asm is otherwise unchanged) after a state image has been applied.
; Restores the three native countdowns from their just-applied SC_CNT*
; mirrors -- without this, a resync would silently desync the timer state
; this cart tracks outside the standard $015D-$01EF image range: the
; pushed image would look right in the mirror but the real dispatcher
; would keep running on its own unsynchronized countdown.
; Clobbers R0.
; ---------------------------------------------------------------------------
BX_REBASE_HOOK:
        MVI     SC_CNT2, R0
        MVO     R0,     BX_CNT2_LO
        MVI     SC_CNT3, R0
        MVO     R0,     BX_CNT2_HI
        MVI     SC_CNT4, R0
        MVO     R0,     BX_CNT3_LO
        MVI     SC_CNT5, R0
        MVO     R0,     BX_CNT3_HI
        MVI     SC_CNT6, R0
        MVO     R0,     BX_CNT4_LO
        MVI     SC_CNT7, R0
        MVO     R0,     BX_CNT4_HI
        MOVR    R5,     R7
