#!/usr/bin/env python3
"""The filled hangar's panel colours (gfx-hangar.asm's HPWL/HPWH): each a 4x4
ordered dither given as ink counts out of 16 (yellow, cyan, magenta; the rest
black), packed as f_col's w = a + 32 b + 1024 c with cumulative counts a = Y,
b = Y + C, c = Y + C + M (gfx-light6.asm). Prints the two EQUB lines.

    python3 2-build-files/hangarcols.py "Y C M" ...   (one panel each: the
                                                     wall, then the floor's
                                                     bands, far to near)
"""
import sys
lo, hi = [], []
for arg in sys.argv[1:]:
    y, c, m = (int(v) for v in arg.split())
    assert y + c + m <= 16
    w = y + 32 * (y + c) + 1024 * (y + c + m)
    lo.append("&%02X" % (w & 255)); hi.append("&%02X" % (w >> 8))
print(".HPWL\n EQUB " + ", ".join(lo))
print(".HPWH\n EQUB " + ", ".join(hi))
