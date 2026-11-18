#!/bin/sh
# 2-build-files/stills.sh [planets] [sunnear]: the stills in images/planets
# and images/sunnear from the build (3-assembled-output and
# 5-compiled-game-discs: run make first), with 6-harness/mplanet.mjs and
# 2-build-files/planetvis.py, and 6-harness/msunnear.mjs and
# 2-build-files/sunnear.py. Headless (jsbeeb). Each planet still is the last
# frame of a short posed scene; the seeds are the systems' QQ2 (s0 lo, hi,
# s1 lo, hi, s2 lo, hi): Leesti's for the craters. The
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
    pl beach --type 128 --x 128 --y 96 --r 70 --pose 20,30,0 &
    pl caps --type 130 --qq2 $LEESTI --x 128 --y 96 --r 70 --pose 20,30,0 &
    pl caps2 --type 130 --qq2 38,BA,7C,0D,5D,41 --x 120 --y 100 --r 50 --pose 0,60,20 --spin 5 &
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
