# In-place patch map for Boxing.bin (word address -> as1600 expression).
# Symbols are defined in src/hook.asm / src/ram.asm / src/exec_equ.asm.
# Building with tools/dump_rom.py and NO patch file must stay byte-identical
# to the original (make verify-org -- verified).
#
# STATUS (see spikes/NOTES.md M0 for the evidence trail): header relocation,
# both RNG wrapper flavours (8 sites), and all four timer-API shim sites are
# decoded and confirmed in the dis1600 listing.  `make verify-patch` proves
# exactly the words below differ from the original ROM.  Boxing is
# DISPATCH-ONLY for input (M0: zero $011F/$0120/$0121/$0122 references
# anywhere in the ROM), so unlike every prior 2-seat port there is no
# polled-input patch site at all.
{
    # --- Cart header ---
    # $5002/$5003: EXEC timer table pointer -> relocated table in $6000 seg.
    0x5002: "NEW_TIMER_TBL AND $FF",
    0x5003: "NEW_TIMER_TBL SHR 8",
    # $5004/$5005: start-of-game vector -> netcode init shim (falls through
    # to the original .START at $5053).
    0x5004: "NET_START AND $FF",
    0x5005: "NET_START SHR 8",

    # --- RNG call sites -> canonical-RNG wrappers ---
    # X_RAND1 ($167D), 1 site.  Each JSR R5,target is the 3-word form
    # (opcode word unpatched; the following two words encode the target as
    # ((target SHR 10) SHL 2) OR $0100, target AND $3FF).
    0x50E9: "((BX_RAND1 SHR 10) SHL 2) OR $0100",
    0x50EA: "BX_RAND1 AND $3FF",
    # X_RAND2 ($169E), 7 sites.
    0x5301: "((BX_RAND2 SHR 10) SHL 2) OR $0100",
    0x5302: "BX_RAND2 AND $3FF",
    0x5319: "((BX_RAND2 SHR 10) SHL 2) OR $0100",
    0x531A: "BX_RAND2 AND $3FF",
    0x5490: "((BX_RAND2 SHR 10) SHL 2) OR $0100",
    0x5491: "BX_RAND2 AND $3FF",
    0x549F: "((BX_RAND2 SHR 10) SHL 2) OR $0100",
    0x54A0: "BX_RAND2 AND $3FF",
    0x54D6: "((BX_RAND2 SHR 10) SHL 2) OR $0100",
    0x54D7: "BX_RAND2 AND $3FF",
    0x5557: "((BX_RAND2 SHR 10) SHL 2) OR $0100",
    0x5558: "BX_RAND2 AND $3FF",
    0x5840: "((BX_RAND2 SHR 10) SHL 2) OR $0100",
    0x5841: "BX_RAND2 AND $3FF",

    # --- Timer-arm/stop sites -> real-countdown shims ---
    # All four sites call the REAL EXEC entry point (X_TIMER_STOP=$1838 or
    # X_TIMER_START=$1844) with R1 = the ORIGINAL header table's slot
    # address, loaded by an SDBD-prefixed `MVII #addr,R1` immediately
    # before the JSR (3-word form: opcode, imm-lo, imm-hi -- the SAME
    # lo-byte/hi-byte split as the header patches above, just at a
    # different address).  The address goes stale after relocation --
    # both X_TIMER_START/STOP resolve R1 against the header table pointer,
    # which now points at NEW_TIMER_TBL, so calling through computes
    # garbage post-relocation regardless of table layout.  Retargeted to
    # BX_ARM_SHIM/BX_STOP_SHIM, which reimplement the real bit-15 stop-flag
    # semantics directly against the known real countdown cell (src/
    # hook.asm; Sea Battle's SB_START_SHIM precedent).  Each site's MVII
    # operand is ALSO repatched, to the entry's new address WITHIN
    # NEW_TIMER_TBL (BX_SLOT2/3/4, exec_equ.asm) -- the shims dispatch on
    # R1 to pick the right cell.
    #
    # STOP site $521B/$521E (stop slot 3 = BX_TICK3=$5297, orig addr
    # $5024): SDBD MVII #$5024,R1 ($521B-$521D) / JSR X_TIMER_STOP
    # ($521E-$5220).
    0x521C: "BX_SLOT3 AND $FF",
    0x521D: "BX_SLOT3 SHR 8",
    0x521F: "((BX_STOP_SHIM SHR 10) SHL 2) OR $0100",
    0x5220: "BX_STOP_SHIM AND $3FF",
    # STOP site $52D4/$52D9 (stop-ALL loop, orig base $5020, walks 3 slots
    # via ADDI #$0004,R1 for 3 iterations -- BX_TICK2/3/4 = orig slots
    # 1/2/3): SDBD MVII #$5020,R1 ($52D4-$52D6) / MVII #$0003,R2 / JSR
    # X_TIMER_STOP ($52D9-$52DB).  The +4-word stride is UNCHANGED --
    # NEW_TIMER_TBL keeps the same 4-word-per-slot layout, so walking
    # BX_SLOT2 -> BX_SLOT3 -> BX_SLOT4 by +4 each needs no separate patch.
    0x52D5: "BX_SLOT2 AND $FF",
    0x52D6: "BX_SLOT2 SHR 8",
    0x52DA: "((BX_STOP_SHIM SHR 10) SHL 2) OR $0100",
    0x52DB: "BX_STOP_SHIM AND $3FF",
    # START sites $53A7/$53AA (start slot 2=BX_TICK2, orig $5020) and
    # $53AF (start slot 4=BX_TICK4, orig $5028, reached via the SAME base
    # + $0008 -- BX_SLOT2+8 == BX_SLOT4 exactly, since both the original
    # and new tables keep identical relative slot spacing, so the ADDI
    # #$0008,R1 at $53AD needs no patch of its own).
    0x53A8: "BX_SLOT2 AND $FF",
    0x53A9: "BX_SLOT2 SHR 8",
    0x53AB: "((BX_ARM_SHIM SHR 10) SHL 2) OR $0100",
    0x53AC: "BX_ARM_SHIM AND $3FF",
    0x53B0: "((BX_ARM_SHIM SHR 10) SHL 2) OR $0100",
    0x53B1: "BX_ARM_SHIM AND $3FF",
    # START site $558E/$5591 (start slot 3=BX_TICK3, orig $5024).
    0x558F: "BX_SLOT3 AND $FF",
    0x5590: "BX_SLOT3 SHR 8",
    0x5592: "((BX_ARM_SHIM SHR 10) SHL 2) OR $0100",
    0x5593: "BX_ARM_SHIM AND $3FF",

    # --- $0102 real-frame busy-wait -> canonical (M4 determinism finding) ---
    # $56C9: `MVI $0102,R1 / EIS / CMPI #$0001,R1 / BGT L_56C9` -- game
    # logic (the punch-connect timing check, reached only when the
    # proximity test just above it finds the boxers in range) busy-waits
    # for the EXEC's OWN ISR phase counter to count down past 1, with its
    # OWN EIS to let the ISR keep advancing it -- entirely outside the
    # documented X_TIMER/pass-gate API, invisible to a JSR-based recon
    # scan.  This reads REAL, sub-tick frame timing: a netcode stall
    # (either the test injector or the real lockstep freeze, both of
    # which save/force-0/restore $0102 identically) does not preserve
    # the real-time relationship this specific poll depends on, and it
    # produced a genuine, reproducible `make det` divergence (M4: 1/256
    # ticks, isolated to the SC_CNT2-7 timer-tail sub-range by narrowing
    # TRACE_RANGES as a diagnostic, then root-caused by single-instruction
    # stepping to this exact loop).
    # Fix: redirect the operand from $0102 to RS_SPARE0 ($8102, netcode
    # RAM, always zero -- zeroed once at NET_START and never written
    # again by anything).  0 satisfies "<=1" on the very first check, so
    # the loop always exits immediately and deterministically, on every
    # console, stalled or not -- matching the RNG wrapper's own
    # philosophy of canonicalizing a real-time-dependent read rather than
    # trying to preserve its exact timing.  The sim-logic OUTCOME (does
    # the punch land) is unaffected; only the sub-frame real-time delay
    # before that outcome is decided is removed.
    0x56CA: "RS_SPARE0",
}
