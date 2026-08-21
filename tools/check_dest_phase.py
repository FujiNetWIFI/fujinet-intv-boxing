#!/usr/bin/env python3
"""Destination-phase assertion (PORTING.md §5.5, §7.25).

A CRC gate PASS can be two consoles identically stuck in the same wrong
place -- the checksum compare cannot see that. Boxing's boot state is the
cart's own "CHOOSE MEN" keypad prompt (GAME_TBL == BX_HTBL_PROMPT ==
$5932), which masked ($3F, disc-only) fuzz can NEVER answer on its own --
only the scripted keypad digit+ENTER sequence (SCRIPT_TBL, src/
vdispatch.asm) gets past it. A run that somehow never drove that sequence
correctly would park on the prompt forever, with every checksum agreeing
trivially.

** ROOT-CAUSED LIVE (M3, single-instruction stepping, not guessed): ** the
handler's ENTER path ($597E/$59AB-$59C5) cross-checks BOTH seats'
confirmed-flags ($01AC/$01AD) AND, once both are confirmed, compares the
two seats' STORED DIGITS ($01AE/$01AF) -- picking the SAME digit for both
seats is treated as a "duplicate, ignore" and silently never transitions
(confirmed: sending digit #1 to both seats parked forever at
BX_HTBL_PROMPT with every gate green). SCRIPT_TBL sends seat 0 -> #1,
seat 1 -> #2 -- confirmed live to transition GAME_TBL to BX_HTBL_LIVE
($593C).

Usage: check_dest_phase.py build/det_a.out [...]
"""
import re
import sys

DUMP_RE = re.compile(r"^([0-9A-F]{4}):((?:\s+[0-9A-F]{4}\*?){1,8})\s*#", re.M)

BX_HTBL_PROMPT = 0x5932
BX_HTBL_LIVE = 0x593C


def check(path):
    text = open(path).read()
    mem = {}
    for m in DUMP_RE.finditer(text):
        addr = int(m.group(1), 16)
        for i, w in enumerate(m.group(2).split()):
            mem[addr + i] = int(w.rstrip("*"), 16)

    fail = []
    if not mem:
        return [f"{path}: no memory dumps found"]

    seat0_confirmed = mem.get(0x1AC)
    seat1_confirmed = mem.get(0x1AD)
    seat0_pick = mem.get(0x1AE)
    seat1_pick = mem.get(0x1AF)
    tbl_lo = mem.get(0x80C0)
    tbl_hi = mem.get(0x80C1)
    table = None
    if tbl_lo is not None and tbl_hi is not None:
        table = tbl_lo | (tbl_hi << 8)

    if table is None:
        fail.append("no GAME_TBL_LO/HI dump found (the run script must "
                    "dump $80C0-$80C1)")
    elif table == BX_HTBL_PROMPT:
        fail.append("GAME_TBL still points at BX_HTBL_PROMPT ($5932) -- "
                    "parked on the CHOOSE MEN prompt; every checksum "
                    "agrees trivially")
    elif table != BX_HTBL_LIVE:
        fail.append(f"GAME_TBL = ${table:04X}, expected BX_HTBL_LIVE "
                    f"($593C)")

    if seat0_confirmed is None or seat1_confirmed is None:
        fail.append("no $01AC-$01AD dump found (the run script must dump "
                    "$01A8-$01AF)")
    elif not (seat0_confirmed and seat1_confirmed):
        fail.append(f"seat confirm flags $01AC=${seat0_confirmed:04X} "
                    f"$01AD=${seat1_confirmed:04X} -- not both seats "
                    f"confirmed their pick")

    if seat0_pick is not None and seat1_pick is not None:
        if seat0_pick == seat1_pick:
            fail.append(f"both seats picked the same boxer (${seat0_pick:04X}) "
                        f"-- the handler's duplicate-pick guard silently "
                        f"rejects this and never transitions (M3 finding)")

    if not any(mem.get(a, 0) for a in range(0x31D, 0x35D)):
        fail.append("object table $031D-$035C all zero -- nothing was ever "
                    "populated")

    if fail:
        return [f"{path}: {f}" for f in fail]

    print(f"DEST-PHASE OK ({path}): GAME_TBL=${table:04X}, "
          f"seat picks = {seat0_pick:#04x}/{seat1_pick:#04x}")
    return []


problems = []
for arg in sys.argv[1:] or ["build/det_a.out"]:
    problems += check(arg)

if problems:
    print("DEST-PHASE FAIL:")
    for p in problems:
        print("  -", p)
    sys.exit(1)
