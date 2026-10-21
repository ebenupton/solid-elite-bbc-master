#!/usr/bin/env python3
"""Check the 6502's ship lighting against the model (lightramps.py).

    node 6-harness/mlight.mjs --out L.json [--iters N] ...
    python3 2-build-files/lightcheck.py L.json

For every recorded ship: recompute each visible face's level from the
orientation bytes L_REC saw (INWK+9..26), the light LL and the face's unit
normal, with lightramps' arithmetic (light_ship, level_fixed), and compare
with the level L_REC left in the record's XX2 copy (and its flags). Also
reports how far the light is from the sun's true direction (slot 1 the sun),
and the levels' error against the exact (floating-point) n.L.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import faces as F          # noqa: E402
import lightramps as LR    # noqa: E402


def sbyte(v):
    return v - 256 if v >= 128 else v


def main():
    J = json.load(open(sys.argv[1]))
    recs = J['ships']
    R = LR.ramps()
    cbad = 0
    for k, cnt in J['cols'].items():
        A, X, *got = map(int, k.split(','))
        want = [LR.FIXED_BYTE[A & 3]] * 4 if A & 0x80 else LR.tile_bytes(R[LR.HUE_ORDER[A]][X])
        if got != want:
            cbad += 1
            print('COLOUR MISMATCH ramp %d level %d: 6502 %s, model %s' % (A, X, got, want))
    print('%d distinct colours drawn (%d polygons): %d mismatches against the model'
          % (len(J['cols']), sum(J['cols'].values()), cbad))
    ships = dict(F.prepare(F.load_ships()))
    for t, s in ships.items():
        LR.annotate(t, s)
    bad = 0
    nface = 0
    errs = []
    sunang = []
    for r in recs:
        s = ships[r['type']]
        h = r['h']
        LL = [sbyte(v) for v in r['LL']]
        Ls = []
        for off in (12, 6, 0):                      # sidev, roofv, nosev: x hi at +1
            hv = []
            for c in range(3):
                hb = h[off + 2 * c + 1]
                m = (hb & 0x7F) >> 1
                hv.append(-m if hb & 0x80 else m)
            Ls.append(LR.dot32(hv, LL)[1])
        for f, (raw, enc) in enumerate(zip(r['raw'], r['enc'])):
            if raw == 0:
                want = 0
            else:
                want = 0x80 | (0x40 if raw == 255 else 0) | LR.level_fixed(s['n63'][f], Ls)
                nface += 1
                # exact level for the same orientation and light
                M = []
                for off in (12, 6, 0):
                    M.append([((h[off + 2 * c + 1] & 0x7F) * 256 + h[off + 2 * c]) / 0x6000 *
                              (-1 if h[off + 2 * c + 1] & 0x80 else 1) for c in range(3)])
                n = s['faces'][f]['n']
                nn = math.sqrt(sum(c * c for c in n)) or 1
                # view-space normal = n_x sidev + n_y roofv + n_z nosev
                v = [sum(n[k] / nn * M[k][c] for k in range(3)) for c in range(3)]
                L = [c / 41.3 for c in LL]
                exact = round(31 * max(0.0, sum(a * b for a, b in zip(v, L))))
                errs.append(abs(exact - (enc & 31)))
            if want != enc:
                bad += 1
                if bad <= 10:
                    print('MISMATCH iter %d type %d face %d: raw %d, 6502 &%02X, model &%02X (Ls %s)'
                          % (r['i'], r['type'], f, raw, enc, want, Ls))
        if r['frin1'] == 129:
            p = []
            for c in range(3):
                lo, hi, sg = r['sun'][3 * c:3 * c + 3]
                p.append((lo + 256 * hi + 65536 * (sg & 0x7F)) * (-1 if sg & 0x80 else 1))
            pl = math.sqrt(sum(c * c for c in p))
            ll = math.sqrt(sum(c * c for c in LL))
            if pl and ll:
                sunang.append(math.degrees(math.acos(max(-1, min(1, sum(a * b for a, b in zip(p, LL)) / pl / ll)))))
    print('%d ship records, %d visible faces: %d mismatches against the model' % (len(recs), nface, bad))
    if errs:
        print('level against the exact n.L: mean |error| %.2f, max %d (of 31)' % (sum(errs) / len(errs), max(errs)))
    if sunang:
        sunang.sort()
        print('light against the sun (%d records): median %.1f deg, max %.1f deg'
              % (len(sunang), sunang[len(sunang) // 2], sunang[-1]))
    sys.exit(1 if bad or cbad else 0)


if __name__ == '__main__':
    main()
