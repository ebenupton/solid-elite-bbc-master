#!/bin/sh
# 6-harness/discmem/bench.sh TREE OUT [what...]: the disc layer's scenes on
# the build in TREE (its 5-compiled-game-discs and 3-assembled-output),
# headless, one at a time; results in OUT
# (compare two with 6-harness/discmem/cmp.py OUT_A OUT_B).
#   run1     the pixel oracle (frame hashes of both buffers after every frame,
#            6-harness/solidspan/fbhash.mjs) and the speed windows
#            (mspeed.mjs) over run1 (launch, flight, docking: an agentplay
#            session's input log, RUN1=<inputs.jsonl>)
#   gatefb   6-harness/mfbcmp.mjs --frames over the gate's piloted run (3000
#            iterations: Lave's beach ball, the crater system)
#   planets  posed planet scenes (6-harness/mplanet.mjs): back buffer at every
#            frame's end and the planet routines' cycles
#   sunnear  the sun near the planet (6-harness/msunnear.mjs): back buffer and
#            the disc layer's, the second disc's and the frame's cycles; also
#            the sun across the window's edge, growing, and growing past the
#            planet (the two swap: the planet is then the second disc)
# Default: all of them.
set -u
TREE=$1; OUT=$2; shift 2
what=${*:-run1 gatefb planets sunnear}
R=$(cd "$(dirname "$0")/../.." && pwd)
DISC=$TREE/5-compiled-game-discs/elite-master-sng47.ssd
SYMS=$TREE/3-assembled-output/symbols.txt
mkdir -p "$OUT"
LEESTI=38,BA,7C,0D,5D,41
pl() {
    n=$1; shift
    node "$R/6-harness/mplanet.mjs" --tree "$TREE" --out "$OUT/pl-$n" --from 300 "$@" > "$OUT/pl-$n.log" 2>&1 || echo "planet $n: FAILED"
}
for w in $what; do case $w in
run1)
    : "${RUN1:?run1 needs RUN1, an agentplay session's inputs.jsonl}"
    node "$R/6-harness/solidspan/fbhash.mjs" --log "$RUN1" --cand "$DISC" --csyms "$SYMS" \
        --from 0 --to 3600 --out "$OUT/run1-fb.json" > "$OUT/run1-fb.log" 2>&1
    node "$R/6-harness/solidspan/mspeed.mjs" --log "$RUN1" --cand "$DISC" --csyms "$SYMS" \
        --windows 0-3550,1000-1400,2000-2400,3000-3400,3420-3550,3484-3530 > "$OUT/run1-speed.txt" 2>&1 ;;
gatefb)
    node "$R/6-harness/mfbcmp.mjs" --frames --disc "$DISC" --syms "$SYMS" --iters 3000 \
        --out "$OUT/gate-fb.json" > "$OUT/gate-fb.log" 2>&1 ;;
planets)
    pl beach90 --type 128 --x 128 --y 96 --r 90 --pose 20,30,0 --spin 22.5 --n 16
    pl beach200 --type 128 --x 128 --y 96 --r 200 --pose 20,30,0 --spin 5 --n 16
    pl beachpath --type 128 --x0 60 --y0 60 --x1 180 --y1 130 --r0 40 --r1 160 --pose 20,30,0 --spin 3 --n 24
    pl caps90 --type 130 --qq2 $LEESTI --x 128 --y 96 --r 90 --pose 20,30,0 --spin 22.5 --n 16
    pl caps200 --type 130 --qq2 $LEESTI --x 128 --y 96 --r 200 --pose 0,60,20 --spin 5 --n 16
    pl capspath --type 130 --qq2 $LEESTI --x0 200 --y0 40 --x1 100 --y1 120 --r0 30 --r1 120 --pose 0,60,20 --spin 5 --n 24
    pl beachtop --type 128 --x0 128 --y0 -60 --x1 140 --y1 20 --r0 120 --r1 125 --pose 20,30,0 --spin 5 --n 16     # (its centre above the screen)
    pl beachleft --type 128 --x0 8 --y0 100 --x1 40 --y1 90 --r0 100 --r1 110 --pose 20,30,0 --spin 5 --n 16      # (by the window's left side)
    pl moon1 --type 128 --qq2 76,70,EB,94,0B,D5 --x 93 --y 97 --r 33 --pose 59,28,24 --spin 2 --n 16
    pl moon2 --type 130 --qq2 DA,1C,F6,BA,66,D3 --x 110 --y 90 --r 31 --pose 40,76,2 --spin 11 --n 16
    pl moon3 --type 130 --qq2 38,AD,9C,15,1D,A9 --x 70 --y 100 --r 30 --pose 0,150,30 --n 16
    pl moonpath --type 128 --qq2 76,70,EB,94,0B,D5 --x0 60 --y0 80 --x1 160 --y1 110 --r0 20 --r1 60 --pose 59,28,24 --spin 2 --n 24 ;;
sunnear)
    sn() {
        n=$1; shift
        node "$R/6-harness/msunnear.mjs" --disc "$DISC" --syms "$SYMS" --out "$OUT/$n" --pose 20,30,0 --spin 3 "$@" > "$OUT/$n.log" 2>&1 || echo "$n: FAILED"
    }
    sn sunnear
    sn sunedge --sx 236 --sx1 290                       # (the second disc across the window's edge)
    sn sungrow --sz 393216 --sz1 131072                 # (its radius 16 to 48)
    sn sunswap --pz 262144 --psx 120 --psy 120 --sz 393216 --sz1 131072     # (the planet, radius 24, becomes the second disc)
    sn sunsmall --pz 125829 --psx 110 --psy 110 --sx 180 --sy0 150 --sy1 40 ;;   # (a planet of radius 50 wholly on the screen)
esac; done
