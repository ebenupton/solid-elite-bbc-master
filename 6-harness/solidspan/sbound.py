#!/usr/bin/env python3
"""sbound.py DUMP [--from I --to J]: the upper bound of keeping single-value spans.

DUMP is sdump.mjs's output: per frame a 4-byte header (iteration lo, hi, frame
count, buffer) and the buffer just drawn (&4000-&6FFF). Each frame is compared
with the previous frame drawn into the same buffer. Per pixel row (1..191), with
the row's 64 bytes (columns 0 and 63 masked to their non-border pixels):

  all:      bytes in uniform runs (>= 1 whole byte, value non-zero) of the old
            frame that hold the same value in the new one (any scheme's bound);
  largest:  the old row's largest uniform non-zero run K (>= T bytes), and the
            bytes of K that the new frame has the same value in;
  fullrow:  rows whose old content is one value from its first non-zero byte to
            its last (the edge bytes may be partial), K = the whole bytes
            between, and the bytes of K the new frame repeats.

Cycles: each kept byte saves its erase (STA abs,Y, 5) and its fill (5).
"""
import sys
def rows(buf):
    out = []
    for y in range(192):
        base = (y >> 3) * 0x200 + (y & 7)
        out.append(bytes(buf[base + 8 * c] for c in range(64)))
    return out
def runs(r):
    i = 0
    while i < 64:
        v = r[i]
        if v == 0: i += 1; continue
        j = i
        while j + 1 < 64 and r[j + 1] == v: j += 1
        yield i, j, v
        i = j + 1
args = sys.argv[1:]
FROM = int(args[args.index('--from') + 1]) if '--from' in args else 0
TO = int(args[args.index('--to') + 1]) if '--to' in args else 1 << 30
data = open(args[0], 'rb').read()
F = 4 + 0x3000
last = {}
TH = [1, 2, 4, 8, 16, 32]
tot = {'all': 0, 'full': 0, 'fullrows': 0, 'rows': 0}
lg = {t: [0, 0] for t in TH}
frames = 0
for o in range(0, len(data) - F + 1, F):
    it = data[o] | data[o + 1] << 8; b = data[o + 3]
    cur = rows(data[o + 4:o + F])
    if b in last and FROM <= it <= TO:
        frames += 1
        old = last[b]
        for y in range(1, 191):
            ro, rn = bytearray(old[y]), cur[y]
            ro[0] = 0; ro[63] = 0          # border columns: never kept
            if not any(ro): continue
            tot['rows'] += 1
            best = (0, 0, 0, 0)
            for i, j, v in runs(ro):
                tot['all'] += sum(1 for x in range(i, j + 1) if rn[x] == v)
                if j - i + 1 > best[0]: best = (j - i + 1, i, j, v)
            L, i, j, v = best
            sv = sum(1 for x in range(i, j + 1) if rn[x] == v)
            for t in TH:
                if L >= t: lg[t][0] += 1; lg[t][1] += sv
            nz = [x for x in range(64) if ro[x]]
            f, l = nz[0], nz[-1]
            if l - f >= 2 and len(set(ro[f + 1:l])) == 1:
                tot['fullrows'] += 1
                v = ro[f + 1]
                tot['full'] += sum(1 for x in range(f + 1, l) if rn[x] == v)
    last[b] = cur
print(f'frames compared {frames}; rows with content {tot["rows"] / frames:.1f} a frame')
print(f'all uniform runs: {tot["all"] / frames:.0f} bytes kept a frame (~{10 * tot["all"] / frames:.0f} cycles)')
for t in TH:
    print(f'largest run >= {t:2d} bytes: {lg[t][0] / frames:.1f} rows, {lg[t][1] / frames:.0f} bytes kept a frame (~{10 * lg[t][1] / frames:.0f} cycles)')
print(f'full-row solid: {tot["fullrows"] / frames:.1f} rows, {tot["full"] / frames:.0f} bytes kept a frame (~{10 * tot["full"] / frames:.0f} cycles)')
