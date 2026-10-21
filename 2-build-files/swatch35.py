#!/usr/bin/env python3
"""The 35 colours: every 2x2 dither of MODE 1's four inks, black, cyan, magenta and
yellow (K + C + M + Y = 4 pixels), numbered 0..34 (ALL: by black count rising, then
cyan, yellow and magenta counts falling), and each one's cell, the ink at each of
the four positions (cell).

A tile is filled with its entry's cell repeated: pixel (x, y) of the screen takes
the ink at (x & 1, y & 1), so tools/landgen.py turns an entry into two bytes, one
for even lines and one for odd (dither_bytes), and land.s fills whole bytes with
them.  Pixels from different cells therefore meet without a seam only if the inks
they share are in phase, which cell arranges: black at the same positions in
every colour that has it (one in four at (0, 0); two the checkerboard (0, 0) and
(1, 1); three those and (1, 0)), and magenta likewise where the black leaves room.
PHYS is each ink's RGB.

The landscape uses entries land.LAND, land.SEAC, land.PADC (19, K1C1M1Y1) and
frame.BLACK (34, K4); shipgen picks the ship's shades from the same list.

    python3 proto/swatch35.py   writes proto/swatch35.png: every entry's cell tiled
                                12 x 8 pixels beside its average colour and number
"""
import os
from itertools import product, combinations

K, C, M, Y = 0, 1, 2, 3
PHYS = {K: (0, 0, 0), C: (0, 255, 255), M: (255, 0, 255), Y: (255, 255, 0)}
ORDER = [(0, 0), (1, 1), (1, 0), (0, 1)]       # positions, the diagonal first: two
                                                # of an ink are checkered
KPHASE = [(0, 0), (1, 1), (1, 0), (0, 1)]      # where the black goes, in every colour
MPHASE = [(1, 1), (0, 0), (1, 0), (0, 1)]      # and the magenta, where the black is not


def cell(k, c, m, y):
    """The cell of the colour with k black, c cyan, m magenta and y yellow pixels (k
    + c + m + y = 4): {(x, y): ink} over the four positions.  Cyan takes ORDER from
    the front, yellow then magenta from the back, black the rest; a SHEARED cell has
    its odd line's two pixels swapped (the ink filling a column is set on a diagonal
    before the phasing); then the cell is scrolled (shifted a pixel
    across, down or both, which does not change the dither) until its black is at
    KPHASE[:k], and mphase puts its magenta in phase."""
    out, back = {}, ORDER[::-1]
    for pos in ORDER[:c]:
        out[pos] = C
    for pos in back[:y]:
        out[pos] = Y
    for pos in back[y:y + m]:
        out[pos] = M
    for pos in ORDER:
        out.setdefault(pos, K)
    if (k, c, m, y) in SHEARED:
        out[(0, 1)], out[(1, 1)] = out[(1, 1)], out[(0, 1)]
    if 0 < k < 4:
        want = set(KPHASE[:k])
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            moved = {((x + dx) & 1, (y + dy) & 1): v for (x, y), v in out.items()}
            if {p for p, v in moved.items() if v == K} == want:
                out = moved
                break
        else:
            raise ValueError(f'no scroll puts K{k}C{c}M{m}Y{y}\'s black in phase')
    return mphase(out, k, c, m, y)


def mphase(out, k, c, m, y):
    """out with its magenta in phase and its black kept where it is: the magenta at
    the first m positions of MPHASE (KPHASE for an MBLACK colour) the black leaves
    free.  By a scroll if one keeps the black in place, else by rebuilding the cell
    with the cyan and yellow placed round black and magenta in the arrangement with
    the fewest stripes (an ink filling a row or column of the cell).  A cell with
    no magenta, or nothing else, is returned as it is."""
    if m in (0, 4):
        return out
    blk = {p for p, v in out.items() if v == K}
    order = KPHASE if (k, c, m, y) in MBLACK else MPHASE
    want = set([p for p in order if p not in blk][:m])
    for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        moved = {((x + dx) & 1, (y_ + dy) & 1): v for (x, y_), v in out.items()}
        if ({p for p, v in moved.items() if v == K} == blk
                and {p for p, v in moved.items() if v == M} == want):
            return moved
    rest = [p for p in ORDER if p not in blk and p not in want]
    best = None
    for cyan in combinations(rest, c):
        cell = {p: K for p in blk}
        cell.update({p: M for p in want})
        cell.update({p: (C if p in cyan else Y) for p in rest})
        n = (sum(cell[(x, 0)] == cell[(x, 1)] for x in (0, 1))
             + sum(cell[(0, r)] == cell[(1, r)] for r in (0, 1)))
        if best is None or n < best[0]:
            best = (n, cell)
    return best[1]


ALL = [(k, c, m, y) for k, c, m, y in product(range(5), repeat=4) if k + c + m + y == 4]
ALL.sort(key=lambda t: (t[0], -t[1], -t[3], -t[2]))      # black ascending, then cyan, yellow,
                                                          # magenta descending
SHEARED = {ALL[i] for i in (23, 26, 27)}                  # K1M2Y1, K2C1Y1, K2C1M1: an ink
                                                          # fills a column unsheared
MBLACK = {ALL[2]}                                         # C3M1: magenta on the black's grid


def main():
    from PIL import Image, ImageDraw
    S, cols = 6, 5
    w, h = 220, 70
    img = Image.new('RGB', (cols * w + 10, ((len(ALL) + cols - 1) // cols) * h + 10), (60, 60, 60))
    d = ImageDraw.Draw(img)
    for n, t in enumerate(ALL):
        x0, y0 = 10 + (n % cols) * w, 10 + (n // cols) * h
        cl = cell(*t)
        for yy in range(8):
            for xx in range(12):
                c = PHYS[cl[(xx & 1, yy & 1)]]
                d.rectangle([x0 + xx * S, y0 + yy * S, x0 + xx * S + S - 1, y0 + yy * S + S - 1], c)
        avg = tuple(sum(PHYS[v][ch] for v in cl.values()) // 4 for ch in range(3))
        d.rectangle([x0 + 12 * S + 4, y0, x0 + 12 * S + 44, y0 + 8 * S - 1], avg)
        d.text((x0 + 12 * S + 50, y0 + 8), f'{n:2d}', fill=(255, 255, 255))
        d.text((x0 + 12 * S + 50, y0 + 26), 'K%dC%dM%dY%d' % t, fill=(220, 220, 220))
    img.save(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'swatch35.png'))


if __name__ == '__main__':
    main()
