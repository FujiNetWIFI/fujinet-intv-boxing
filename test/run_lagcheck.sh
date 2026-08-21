#!/bin/sh
# M2/§7.24 interception proof: the same in-ROM demo script, run at d=0
# (boxing_lag0) and d=20 (boxing_lag).  The delay ring is the ONLY difference
# between the two builds, so the whole per-tick game-state timeline must
# come out shifted by exactly d.
#
# Unlike the sibling ports, this does not watch a hand-picked game cell:
# Golf's exact swing/aim field offsets were not reverse-engineered this
# session (M2 TODO -- PORTING.md §5.5, measure before trusting further).
# Instead both builds carry SPIKE_TRACE (src/debug.asm's TRACE_TICK), so
# TRACE_RING holds a per-tick rotate-add checksum over the SAME game-state
# ranges `make det` already checksums.  That is a stronger, cart-agnostic
# signal: it does not require knowing WHAT changed, only that the whole
# state timeline in the d=20 build is a d-tick-later copy of the d=0
# build's timeline.  TRACE_STOP=250 is under 256 so the ring never wraps:
# ring index i IS tick i, directly, no lap ambiguity.
#
# Pure `r N` + one final breakpoint park: deterministic per build
# (PORTING.md §7.17 bans breakpoint-forced injection for exact-tick work,
# not instruction-count parks -- and this uses neither, just TRACE_DONE).
set -e
cd "$(dirname "$0")/.."
BUILD=build
JZINTV=${JZINTV:-$HOME/Workspace/jzintv-20200712-src/bin/jzintv}

make -s $BUILD/boxing_lag0.bin $BUILD/boxing_lag.bin >/dev/null

dump() {  # $1 = binary, $2 = sym file, $3 = output log
    DONE_ADDR=$(awk '/ TRACE_DONE$/ { sub(/^0+/, "", $1); print $1 }' "$2")
    if [ -z "$DONE_ADDR" ]; then
        echo "TRACE_DONE not found in $2" >&2
        exit 1
    fi
    {
        printf 'b 14D5\nr 10000000\ng 7 14D7\nn 14D5\n'
        printf 'b %s\nr 200000000\n' "$DONE_ADDR"
        printf 'm 9000 200\n'
        printf 'm 8108 2\n'          # TICK_LO/TICK_HI at park
        printf 'q\n'
    } > "$BUILD/lagprobe.scr"
    SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
        timeout 120 "$JZINTV" -d --script="$BUILD/lagprobe.scr" -r0 \
        -e rom/exec.bin -g rom/grom.bin "$1" > "$2.out" 2>&1 || true
    if ! grep -q "Hit breakpoint at .$DONE_ADDR" "$2.out"; then
        echo "$1 never reached TRACE_DONE (\$$DONE_ADDR); tail:" >&2
        tail -5 "$2.out" >&2
        exit 1
    fi
    cp "$2.out" "$3"
}

dump $BUILD/boxing_lag0.bin $BUILD/boxing_lag0.sym $BUILD/lag0.log
dump $BUILD/boxing_lag.bin  $BUILD/boxing_lag.sym  $BUILD/lag20.log

python3 - $BUILD/lag0.log $BUILD/lag20.log <<'EOF'
import re, sys

def ring(path):
    """Parse the `m 9000 200` dump: 256 entries x 2 bytes.  With
    TRACE_STOP < 256 the ring never wraps, so ring[i] is simply tick i's
    checksum (entries past the parked tick are stale zero-fill).  Returns
    the list of 256 ints and the parked TICK_LO/TICK_HI."""
    log = open(path).read()
    rows = re.findall(r'^([0-9A-F]{4}):((?:\s+[0-9A-F]{4}\*?){1,8})\s*#',
                       log, re.M)
    words = []
    tick_row = None
    for addr, body in rows:
        a = int(addr, 16)
        vals = [int(w.rstrip('*'), 16) for w in body.split()]
        if 0x9000 <= a < 0x9200:
            words.extend(vals)
        elif a == 0x8108:
            tick_row = vals
    if len(words) < 512:
        raise SystemExit(f"LAGCHECK FAIL: {path} ring dump too short "
                          f"({len(words)} words)")
    entries = [(words[2 * i] & 0xFF) | ((words[2 * i + 1] & 0xFF) << 8)
               for i in range(256)]
    tick = None
    if tick_row:
        tick = (tick_row[0] & 0xFF) | ((tick_row[1] & 0xFF) << 8)
    return entries, tick

r0, t0 = ring(sys.argv[1])
r20, t20 = ring(sys.argv[2])
print(f"parked ticks: d=0 -> {t0}, d=20 -> {t20}")
PARK = min(t for t in (t0, t20) if t is not None)

# Score each candidate shift: tick t in the d=0 run should equal tick
# (t + s) in the d=20 run when the state timeline is shifted s ticks
# later.  Only compare ticks strictly inside BOTH parked ranges (no
# wraparound, no stale zero-fill past the park point).
best = []
for s in range(0, 41):
    hit = tot = 0
    for t in range(PARK - 41):
        if t + s >= PARK:
            continue
        tot += 1
        if r0[t] == r20[t + s]:
            hit += 1
    if tot >= 50:
        best.append((hit, s))
if not best:
    print("LAGCHECK FAIL: not enough in-range samples to score any shift")
    sys.exit(1)
best.sort(reverse=True)
peak_hit, shift = best[0]
median_hit = sorted(h for h, s in best)[len(best) // 2]
zero_hit = dict((s, h) for h, s in best).get(0)

print(f"best alignment: shift = {shift} ticks ({peak_hit}/{tot} agree)")
print(f"baseline      : median shift agreement {median_hit}/{tot}"
      + (f", shift=0 {zero_hit}/{tot}" if zero_hit is not None else ""))
top = sorted(best, reverse=True)[:5]
print("top shifts    : " + ", ".join(f"{s}:{h}" for h, s in top))

if not (17 <= shift <= 23):
    print(f"LAGCHECK FAIL: agreement peaks at shift {shift}, expected ~20")
    sys.exit(1)
if peak_hit < 1.25 * median_hit:
    print(f"LAGCHECK FAIL: peak {peak_hit} is not clearly above the "
          f"{median_hit} baseline -- no timeline shift is discernible")
    sys.exit(1)
if zero_hit is not None and peak_hit < 1.25 * zero_hit:
    print(f"LAGCHECK FAIL: shift {shift} ({peak_hit}) is not clearly "
          f"better than shift 0 ({zero_hit}) -- the delay ring is inert")
    sys.exit(1)
print(f"LAGCHECK PASS: interception + delay ring proven -- the state "
      f"timeline shifts {shift} ticks later at d=20")
print(f"  (agreement peaks at {peak_hit} vs a {median_hit} baseline)")
EOF
