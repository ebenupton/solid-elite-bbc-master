#!/bin/sh
# 6-harness/verify.sh [iterations] [mcompare options...]: the gate for a change
# to BBC Master Elite (6-harness/README.md).
#
#  1. build: make (from the repository's root); FAIL on a non-zero exit or an
#     error or failed ASSERT in the output. Reports how many of the five
#     original binaries still match 4-reference-binaries/sng47. Once the
#     build has the filled renderer's rasteriser, its soak test
#     (6-harness/test_raster.py --quick: every primitive against a
#     pixel-exact model, on py65) runs first.
#  2. determinism: 6-harness/mcompare.mjs --iters N (default 10000) of the
#     released SNG47 disc (4-reference-binaries/sng47) against the new build
#     (5-compiled-game-discs/elite-master-sng47.ssd, with its own symbols),
#     both flown by the same pilot; FAIL on a divergence of game state, a run
#     that stops early, or a write to page &0D. MODE (below) says how strict
#     the comparison is.
#  3. regressions, with real key presses: dock, launch, dock again
#     (mredock.mjs); save, load, a failed load and a catalogue through the
#     game's disc menu (msavetest.mjs, once the build has DOSCLI, its disc
#     glue); the same commander saved on SNG47 and on the build, the files
#     compared byte for byte (msavebytes.mjs); once the build has the filled renderer, the station drawn in
#     front of a planet just over 65536 away (mstation.mjs); and changes of
#     view in flight against the reference over 1500 iterations
#     (mcompare.mjs --views); once the build culls by the ship's handedness,
#     the ships the ship audit flagged, posed in flight (mshippose.mjs).
#  4. speed: flight-loop iterations per emulated second over the whole run,
#     reference and candidate, their ratio, and the candidate's cycles per
#     flight iteration (reported, not gated; the per-window table is in the
#     log).
#
# MODE: "strict" compares every byte of the game state that the harness
# records, drawing temporaries and line heaps included (mlib.mjs); "loose"
# leaves out the drawing temporaries and the line heaps (DRAW_EXCLUDE), for
# a build whose drawing code differs from the original's. "screen" also
# compares the screen (shadow RAM &4000-&7DFF) at every iteration, for a build
# that draws exactly as the original does. The default is the port's current
# state ("loose": the CMYK dashboard draws differently from Master's, so the
# drawing temporaries and the screen are no longer the original's);
# MODE="..." in the environment overrides it.
#
# Prints PASS/FAIL per step, then "VERIFY PASS <ref it/s> <cand it/s> <ratio>
# <cycles>" or "VERIFY FAIL <step>"; exit status 0 only on PASS. Logs go to
# 6-harness/work/verify/. 10000 iterations take about 5 minutes (the
# reference run is cached after the first).
MODE=${MODE:-loose}
set -u
cd "$(dirname "$0")/.." || exit 1
ITERS=${1:-10000}
[ $# -gt 0 ] && shift
LOG=6-harness/work/verify
mkdir -p "$LOG"
fail() { echo "VERIFY FAIL $1"; exit 1; }
CAND=5-compiled-game-discs/elite-master-sng47.ssd
CSYMS=3-assembled-output/symbols.txt
REF=4-reference-binaries/sng47/elite-master-sng47.ssd
RSYMS=4-reference-binaries/sng47/symbols.txt

# ---- 1. the rasteriser's soak test, and the build
if [ -f 1-source-files/main-sources/gfx-raster.asm ]; then
    if python3 6-harness/test_raster.py --quick > "$LOG/test_raster.log" 2>&1; then
        echo "test_raster: PASS"
    else
        tail -20 "$LOG/test_raster.log"; echo "test_raster: FAIL"; fail test_raster
    fi
fi
if ! make > "$LOG/build.log" 2>&1; then
    tail -20 "$LOG/build.log"; echo "build: FAIL (exit status)"; fail build
fi
if grep -iE "error|assertion failed" "$LOG/build.log" 3-assembled-output/compile.txt > "$LOG/build.errors" && [ -s "$LOG/build.errors" ]; then
    cat "$LOG/build.errors"; echo "build: FAIL (error/ASSERT in output)"; fail build
fi
SAME=$(python3 2-build-files/crc32.py 4-reference-binaries/sng47 3-assembled-output 2>/dev/null | grep -c " Yes ")
echo "build: PASS ($SAME of 5 binaries identical to the SNG47 reference)"

# ---- 2. determinism (and speed)
OPTS=
case "$MODE" in *strict*) ;; *) OPTS="--loose" ;; esac
case "$MODE" in *screen*) OPTS="$OPTS --screen" ;; esac
node 6-harness/mcompare.mjs --iters "$ITERS" $OPTS --cand "$CAND" --csyms "$CSYMS" \
    --out "$LOG/compare" "$@" > "$LOG/compare.log" 2>&1
CST=$?
grep -E "^Pilot \(ref\)" "$LOG/compare.log"
if grep -q "FIRST DIVERGENCE" "$LOG/compare.log"; then
    grep -A14 "FIRST DIVERGENCE" "$LOG/compare.log" | head -24; echo "compare: FAIL (divergence)"; fail compare
fi
if [ $CST -ne 0 ] || ! grep -q "^MCOMPARE PASS" "$LOG/compare.log"; then
    grep -E "SCREEN|PAGE" "$LOG/compare.log"; tail -5 "$LOG/compare.log"; echo "compare: FAIL (exit $CST)"; fail compare
fi
grep -E "Game state identical|Screen identical" "$LOG/compare.log"
echo "compare: PASS (mode: $MODE)"

# ---- 3. regressions
node 6-harness/mredock.mjs --disc "$CAND" --syms "$CSYMS" --out "$LOG/redock" > "$LOG/redock.log" 2>&1
grep -E "^docking|^REDOCK" "$LOG/redock.log"
grep -q "^REDOCK PASS" "$LOG/redock.log" || { echo "redock: FAIL"; fail redock; }
if grep -q "'DOSCLI_C'" "$CSYMS"; then
    node 6-harness/msavetest.mjs --disc "$CAND" --syms "$CSYMS" --out "$LOG/save" > "$LOG/save.log" 2>&1 || { tail -8 "$LOG/save.log"; echo "savetest: FAIL"; fail savetest; }
    SAVE=savetest
else
    SAVE="no savetest: the original's disc access"
fi
# saves byte-identical: the same commander saved on SNG47 and on this build,
# the files (and their catalogue entries) compared byte for byte
node 6-harness/msavebytes.mjs --ref "$REF" --rsyms "$RSYMS" --cand "$CAND" --csyms "$CSYMS" \
    --out "$LOG/savebytes" > "$LOG/savebytes.log" 2>&1
grep -E "^savebytes:|^SAVEBYTES" "$LOG/savebytes.log"
grep -q "^SAVEBYTES PASS" "$LOG/savebytes.log" || { tail -5 "$LOG/savebytes.log"; echo "savebytes: FAIL"; fail savebytes; }
SAVE="$SAVE, savebytes"
if grep -q "'F_PLANET'" "$CSYMS"; then
    # the station in front of a planet just over 65536 away (a docking run
    # with the planet behind it) must be drawn: F_PLANET once kept 16 bits of
    # the planet's z, and f_behind hid the station behind it
    node 6-harness/mstation.mjs --disc "$CAND" --syms "$CSYMS" --out "$LOG/station" > "$LOG/station.log" 2>&1
    grep -E "^[0-9]+ iterations" "$LOG/station.log"
    grep -q "^STATION PASS" "$LOG/station.log" || { echo "station: FAIL"; fail station; }
    SAVE="$SAVE, station"
fi
node 6-harness/mcompare.mjs --iters 1500 $OPTS --views --maxsecs 400 --cand "$CAND" --csyms "$CSYMS" \
    --out "$LOG/views" > "$LOG/views.log" 2>&1
grep -q "^MCOMPARE PASS" "$LOG/views.log" || { grep -A8 "FIRST DIVERGENCE" "$LOG/views.log" | head -10; grep SCREEN "$LOG/views.log"; echo "views: FAIL"; fail views; }
SAVE="$SAVE, views"
if grep -q "'GHAND'" "$CSYMS"; then
    # the ship audit's flagged poses (the missile's fins, the splinter's
    # faces), in flight, in both handednesses: nothing drawn outside the
    # ship, its body covered, its front faces and no others filled
    node 6-harness/mshippose.mjs --disc "$CAND" --syms "$CSYMS" --out "$LOG/shippose" > "$LOG/shippose.log" 2>&1
    grep -q "^SHIPPOSE PASS" "$LOG/shippose.log" || { grep "BAD" "$LOG/shippose.log" | head -10; echo "shippose: FAIL"; fail shippose; }
    SAVE="$SAVE, shippose"
fi
echo "regressions: PASS (redock, $SAVE)"

# ---- 4. speed
ALL=$(grep -E "^ +all " "$LOG/compare.log")
CYC=$(sed -n 's/^Cycles per flight iteration: ref [0-9.]*, cand \([0-9.]*\)$/\1/p' "$LOG/compare.log")
echo "speed (flight it/s, ref cand cand/ref): $ALL; cycles per flight iteration $CYC"
set -- $ALL
echo "VERIFY PASS $3 $4 $5 $CYC"
exit 0
