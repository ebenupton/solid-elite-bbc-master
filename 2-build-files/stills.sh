#!/bin/sh
# 2-build-files/stills.sh [planets] [sunnear]: the stills in images/planets
# and images/sunnear from the build (3-assembled-output and
# 5-compiled-game-discs: run make first), with 6-harness/mplanet.mjs and
# 2-build-files/planetvis.py, and 6-harness/msunnear.mjs and
# 2-build-files/sunnear.py. Headless (jsbeeb). Each planet still is the last
# frame of a short posed scene; the seeds are the systems' QQ2 (s0 lo, hi,
# s1 lo, hi, s2 lo, hi): Leesti's for the craters, and seeds with a moon
# (h = s0_hi ^ s1_hi ^ s2_hi, h & 3 = 1) and a ring (h bits 4-6 = 4). The
# banded planets (bands.png, bands2.png) and the rings (ring*.png) come from
# a copy of the repository built with "make bands=on rings=on"
# (6-harness/work/stills/bandstree), as the default build has neither. The
# sun near the planet's frames and movie (sunnear.mp4) stay in
# 6-harness/work/stills; its sheet, spawn frame and sunnear.gif go to
# images/sunnear.
set -u
cd "$(dirname "$0")/.." || exit 1
T=$(pwd)
W=$T/6-harness/work/stills; mkdir -p "$W"
what=${*:-planets sunnear}
LEESTI=38,BA,7C,0D,5D,41
pl() {      # pl name args...: a scene, its last frame as images/planets/name.png
    n=$1; shift
    node 6-harness/mplanet.mjs --tree "${TREE:-$T}" --out "$W/$n" --from 300 --n 6 "$@" > "$W/$n.log" 2>&1 &&
    python3 2-build-files/planetvis.py "$W/$n" "images/planets/$n.png" 305 > /dev/null
}
case "$what" in *planets*)
    B=$W/bandstree; rm -rf "$B"; mkdir -p "$B/3-assembled-output" "$B/5-compiled-game-discs"
    cp -R 1-source-files 2-build-files Makefile "$B"/ &&
        (cd "$B" && make bands=on rings=on verify=no) > "$W/bandstree.log" 2>&1 || { echo "stills: the bands=on rings=on build failed"; exit 1; }
    pl beach --type 128 --x 128 --y 96 --r 70 --pose 20,30,0 &
    pl caps --type 130 --qq2 $LEESTI --x 128 --y 96 --r 70 --pose 20,30,0 &
    TREE=$B pl bands --type 130 --qq2 38,AD,9C,14,1D,15 --x 128 --y 96 --r 80 --pose 20,30,0 &
    TREE=$B pl bands2 --type 130 --qq2 38,AD,9C,14,1D,15 --x 140 --y 100 --r 50 --pose 0,60,20 --spin 5 &
    wait
    pl caps2 --type 130 --qq2 38,BA,7C,0D,5D,41 --x 120 --y 100 --r 50 --pose 0,60,20 --spin 5 &
    pl nobands --type 130 --qq2 38,AD,9C,14,1D,15 --x 128 --y 96 --r 80 --pose 20,30,0 &
    wait
    pl moon1 --type 128 --qq2 76,70,EB,94,0B,D5 --x 93 --y 97 --r 33 --pose 59,28,24 --spin 2 &
    pl moon2 --type 130 --qq2 DA,1C,F6,BA,66,D3 --x 110 --y 90 --r 31 --pose 40,76,2 --spin 11 &
    pl moon3 --type 130 --qq2 38,AD,9C,15,1D,A9 --x 70 --y 100 --r 30 --pose 0,150,30 &
    TREE=$B pl ring --type 130 --qq2 38,AD,9C,15,1D,79 --x 128 --y 96 --r 40 --pose 20,30,0 &
    wait
    TREE=$B pl ring2 --type 128 --qq2 38,AD,9C,14,1D,78 --x 160 --y 96 --r 36 --pose 0,-60,0 &
    TREE=$B pl ringmoon --type 128 --qq2 38,AD,9C,15,1D,79 --x 170 --y 96 --r 34 --pose free &
    TREE=$B pl ringmoon2 --type 128 --qq2 38,AD,9C,15,1D,79 --x 120 --y 100 --r 30 --pose 0,90,0 &
    wait ;;
esac
case "$what" in *sunnear*)
    node 6-harness/msunnear.mjs --out "$W/sunnear" > "$W/sunnear.log" 2>&1
    python3 2-build-files/sunnear.py "$W/sunnear" "$W/sunnear-frames" --sheet 0,12,24,36,48,60,76,88,100,112,124,140 \
        --mp4 "$W/sunnear.mp4" --gif images/sunnear/sunnear.gif > /dev/null
    [ -f "$W/sunnear-frames/sheet.png" ] && mv "$W/sunnear-frames/sheet.png" images/sunnear/sheet.png
    node 6-harness/msunnear.mjs --spawn --out "$W/spawn" > "$W/spawn.log" 2>&1
    python3 2-build-files/sunnear.py "$W/spawn" "$W/spawnpng" > /dev/null
    last=$(ls "$W/spawnpng"/frame-*.png | tail -1); cp "$last" images/sunnear/spawn.png ;;
esac
