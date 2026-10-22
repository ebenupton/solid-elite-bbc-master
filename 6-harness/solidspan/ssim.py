#!/usr/bin/env python3
"""ssim.py PREFIX [--kt N]: replay srec.mjs's record (PREFIX.jsonl, PREFIX.bin) through
the kept-solid-row rules (gfx-raster_kept.asm) and count what they save.

Per frame, for the buffer drawn (each compared with that buffer's previous frame):
  * the repair leaves rows kept last time pending (their old extent, value v);
  * the first polygon span on a pending row settles it: the old bytes outside
    its interior are blacked, and (same colour) the interior bytes the old row
    held are not written again: erase saved = old bytes inside the new interior,
    fill saved = those of them in the old interior when the colour is v;
  * a span that covers the row's dirty extent so far (from the empty extent)
    keeps the row (interior >= KT whole bytes, colour non-zero, away from the
    border); any other span on it, or anything else drawn on it, forgets it;
  * pending rows nothing touched are blacked at the commit (no saving).
Each kept row is checked against the frame's buffer: its interior must hold v.
"""
import sys, json
args = sys.argv[1:]
KT = int(args[args.index('--kt') + 1]) if '--kt' in args else 8
pre = args[0]
F = 4 + 0x3000
bufs = open(pre + '.bin', 'rb').read()
frames = [json.loads(l) for l in open(pre + '.jsonl')]
def rowbytes(buf, y):
    base = (y >> 3) * 0x200 + (y & 7)
    return [buf[base + 8 * c] for c in range(64)]
kept = {0: {}, 1: {}}          # buffer -> {row: (xl, xr, v)} at its last frame
tot = dict(frames=0, spanrows=0, settles=0, erase=0, fill=0, commits=0, commitbytes=0, kept=0, bad=0, blackpieces=0, blackbytes=0)
for i, fr in enumerate(frames):
    b = fr['b']; buf = bufs[i * F + 4:(i + 1) * F]
    pend = dict(kept[b])        # rows pending this frame
    ext = {}                    # this frame's dirty extent per row (pixels)
    new = {}                    # rows kept this frame
    for (y, xl, xr, col) in fr['P']:
        tot['spanrows'] += 1
        if y in pend:
            oxl, oxr, v = pend.pop(y)
            ol, orr = oxl >> 2, oxr >> 2
            nl, ne = (xl >> 2) + 1, xr >> 2      # new interior nl .. ne-1
            ni = set(range(nl, ne))
            old = set(range(ol, orr + 1))
            tot['settles'] += 1
            tot['erase'] += len(old & ni)
            bl = old - ni
            tot['blackbytes'] += len(bl)
            if col == v:
                tot['fill'] += len(set(range(ol + 1, orr)) & ni)
        dl, dr = ext.get(y, (255, 0))
        covers = xl <= dl and xr >= dr
        ext[y] = (min(dl, xl), max(dr, xr))
        if covers and xr - xl >= 4 * KT + 7 and col != 0:
            new[y] = (xl, xr, col)
        else:
            new.pop(y, None)
    for (y0, y1, k) in fr['O']:
        if k == 'G': continue
        for y in range(max(0, y0), min(191, y1) + 1):
            new.pop(y, None)
            if y in pend:
                oxl, oxr, v = pend.pop(y); tot['commits'] += 1; tot['commitbytes'] += (oxr >> 2) - (oxl >> 2) + 1
    for y, (oxl, oxr, v) in pend.items():
        tot['commits'] += 1; tot['commitbytes'] += (oxr >> 2) - (oxl >> 2) + 1
    for y, (xl, xr, v) in list(new.items()):
        r = rowbytes(buf, y)
        if any(r[c] != v for c in range((xl >> 2) + 1, xr >> 2) if not (c == 32 and 76 <= y <= 116)):
            tot['bad'] += 1; del new[y]
    tot['kept'] += len(new)
    if '--per' in args: print(fr['it'], b, len(fr['P']), len(new), tot['erase'] + tot['fill'] - getattr(sys, '_last', 0)); sys._last = tot['erase'] + tot['fill']
    kept[b] = new
    tot['frames'] += 1
n = tot['frames']
print(f"KT {KT}: {n} frames; a frame: {tot['spanrows']/n:.0f} span rows, {tot['kept']/n:.1f} rows kept, {tot['settles']/n:.1f} settled, "
      f"{tot['erase']/n:.0f} erase bytes saved, {tot['fill']/n:.0f} fill bytes saved, {tot['blackbytes']/n:.0f} bytes blacked in settles, "
      f"{tot['commits']/n:.1f} rows committed ({tot['commitbytes']/n:.0f} bytes); kept rows failing the buffer check {tot['bad']}")
print(f"  ~ saved {5*(tot['erase']+tot['fill'])/n:.0f} cycles a frame (5 a byte) before bookkeeping")
