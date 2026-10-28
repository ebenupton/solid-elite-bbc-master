#!/usr/bin/env python3
"""Lens flare model for the filled CMYK MODE 1 Elite, and the generator of the
lens flare's tables in 1-source-files/main-sources/gfx-flare.asm
(docs/renderer.md, "Lens flare"; first written for the demo port, as its
tools/flare.py).

A cheap 1990s lens flare: when the sun's centre is on (or near) the screen,
a chain of dithered see-through circles ("ghosts") along the line from the
sun through the screen centre (128, 96) and beyond, plus a thin ring around
the sun.  Everything here is integer arithmetic in the form the 6502 code
(gfx-flare.asm) does it, so the emulator's frames can be checked against it
pixel for pixel.

Screens are 192 x 256 arrays of logical colours (0 K, 1 C, 2 M, 3 Y).

    python3 2-build-files/flare.py      renders the study sheets into
                                        3-assembled-output/flare/ (3x scale)
    python3 2-build-files/flare.py --tables
                                        prints gfx-flare.asm's tables (fl_rad,
                                        fl_ink, fl_ni, fl_mt, fl_dk, fl_ring,
                                        fl_htab) from GHOSTS, LADDER, BAYER,
                                        RING and hw_table
    python3 2-build-files/flare.py --verify [SRC] [BUILD]
                                        checks them byte for byte against
                                        gfx-flare.asm's literal tables and,
                                        if built, the assembled bytes
                                        (3-assembled-output: symbols.txt,
                                        MERID.bin); exit status 1 if not
    python3 2-build-files/flare.py --check A B SX SY SR [OUT]
                                        A: emulator screenshot without the
                                        flare, B: the same frame with it, SX SY
                                        SR the sun; compares B with the model
                                        applied to A (OUT: emulator | model |
                                        differences)
"""
import os
import re
import sys
import math
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, '3-assembled-output', 'flare')
SCRATCH = os.path.join(ROOT, '6-harness', 'work', 'flare')

K, C, M, Y = 0, 1, 2, 3
RGB = np.array([(0, 0, 0), (0, 255, 255), (255, 0, 255), (255, 255, 0)], np.uint8)
CX, CY = 128, 96                # the screen centre (Elite's X, Y)
CL, CR, CT, CB = 2, 253, 1, 191   # F_FRAME's clip window
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

# ---------------------------------------------------------------- the recipe
# Ghosts: (k, r, ink, n, kind).  Centre = C + k * D / 8, D = sun - C, so k = 8
# is the sun, 0 the screen centre, -8 the sun mirrored through the centre.
# r the radius in pixels, ink the logical colour, n the density in 16ths at
# full intensity (4x4 Bayer: n <= 4 touches only rows 0 and 2 of every 4),
# kind 'd' a disc, 'r' a ring 2 pixels thick.
GHOSTS = [
    (8, 30, Y, 4, 'o'),         # the ring round the sun (only if its radius <= HALOMAX)
    (5, 4, Y, 6, 'd'),
    (3, 7, M, 4, 'd'),
    (-1, 3, C, 8, 'd'),
    (-3, 10, C, 4, 'd'),
    (-4, 5, Y, 4, 'd'),
    (-6, 15, M, 4, 'o'),
    (-8, 18, C, 2, 'd'),
]
# Rings ('o') are dotted: RING's 32 points of radius 15 (doubled for radius 30),
# every one at density index >= 3 (n >= 4), every other one below.
RING = [(math.floor(15 * math.cos(2 * math.pi * i / 32) + 0.5),
         math.floor(15 * math.sin(2 * math.pi * i / 32) + 0.5)) for i in range(32)]
HALOMAX = 26


def hw_table(r):
    """Half-widths of a disc of radius r, row offset d = 0..r: the widest x with
    x*x + d*d <= r*r + r (a rounder circle than r*r at small radii)."""
    return [int(math.isqrt(r * r + r - d * d)) for d in range(r + 1)]


def row_mask(n, y, phase):
    """The pixel mask (4 bools) of density n/16 for screen row y, ghost phase
    (rows shifted by phase, so ghosts that overlap do not coincide)."""
    row = BAYER[(y + phase) & 3]
    return [row[p] < n for p in range(4)]


def hw_floor(r):
    """The frame layer's disc half-widths (f_hwbuild): floor(sqrt(r^2 - d^2))."""
    return [int(math.isqrt(r * r - d * d)) for d in range(r + 1)]


def intensity(sx, sy, planet=None):
    """Level 0..3 (0: no flare): none unless the sun's centre is on the screen
    (x 1..255, y 0..191) and not behind the planet; else 3 near the centre,
    falling with |dx| + |dy|."""
    if not (1 <= sx <= 255 and 0 <= sy <= 191):
        return 0
    if planet is not None:
        px, py, pr = planet
        d = abs(sy - py)
        if d <= pr and abs(sx - px) <= hw_floor(pr)[d]:
            return 0
    a = abs(sx - CX) + abs(sy - CY)
    return 3 if a < 96 else 2 if a < 192 else 1


LADDER = [0, 1, 2, 4, 6, 8, 8, 8]


def eff_n(n, lev):
    """Density at level lev (3 = full): step down the ladder 0 1 2 4 6 8."""
    i = LADDER.index(n) + lev - 3
    return LADDER[max(i, 0)]


def span(scr, y, xl, xr, ink, mask, mode):
    xl, xr = max(xl, CL), min(xr, CR)
    if y < CT or y > CB or xl > xr:
        return 0
    for x in range(xl, xr + 1):
        if mask[x & 3]:
            if mode == 'or':
                scr[y, x] |= ink
            else:
                scr[y, x] = ink
    return (xr >> 2) - (xl >> 2) + 1      # bytes touched


def disc(scr, gx, gy, r, ink, n, phase, mode, ring=0, stats=None):
    hw = hw_table(r)
    hwi = hw_table(r - ring) if ring else None
    for d in range(-r, r + 1):
        y = gy + d
        mask = row_mask(n, y, phase)
        if not any(mask) or y < CT or y > CB:
            continue
        h = hw[abs(d)]
        if hwi is not None and abs(d) <= r - ring:
            hi = hwi[abs(d)]
            b = span(scr, y, gx - h, gx - hi - 1, ink, mask, mode)
            b += span(scr, y, gx + hi + 1, gx + h, ink, mask, mode)
            nsp = 2
        else:
            b = span(scr, y, gx - h, gx + h, ink, mask, mode)
            nsp = 1
        if stats is not None and b:
            stats['bytes'] += b
            stats['spans'] += nsp


def flare(scr, sun, planet=None, mode='or', ghosts=GHOSTS, stats=None):
    """Draw the flare over scr (in place) for sun (sx, sy, sr); returns the level."""
    sx, sy, sr = sun
    lev = intensity(sx, sy, planet)
    if lev == 0:
        return 0
    dx, dy = sx - CX, sy - CY
    for i, (k, r, ink, n, kind) in enumerate(ghosts):
        if k == 8 and sr > HALOMAX:
            continue
        gx = CX + ((k * dx) >> 3)
        gy = CY + ((k * dy) >> 3)
        ne = eff_n(n, lev)
        if not ne:
            continue
        if kind == 'o':
            dots(scr, gx, gy, 1 if r == 30 else 0, 1 if ne >= 4 else 2, ink, stats)
        else:
            disc(scr, gx, gy, r, ink, ne, i & 3, mode, 2 if kind == 'r' else 0, stats)
    return lev


def dots(scr, gx, gy, shift, step, ink, stats=None):
    """A dotted ring: RING's points (scaled by 2^shift), every step-th, ORed."""
    for dx, dy in RING[::step]:
        x, y = gx + (dx << shift), gy + (dy << shift)
        if CL <= x <= CR and CT <= y <= CB:
            scr[y, x] |= ink
            if stats is not None:
                stats['dots'] = stats.get('dots', 0) + 1


# ---------------------------------------------------------------- scenes
SUNE, SUNO = 0xFF, 0xFA         # faces.asm FC_SUNE/FC_SUNO
PLANE, PLANO = 0x05, 0x5A       # FC_PLANE/FC_PLANO


def byte_ink(b, p):
    return ((b >> (7 - p)) & 1) << 1 | ((b >> (3 - p)) & 1)


def fill_disc(scr, cx, cy, r, ce, co):
    hw = hw_table(r)
    for d in range(-r, r + 1):
        y = cy + d
        if CT <= y <= CB:
            b = ce if y % 2 == 0 else co
            for x in range(max(cx - hw[abs(d)], CL), min(cx + hw[abs(d)], CR) + 1):
                scr[y, x] = byte_ink(b, x & 3)


def load_shot(path):
    """An emulator screenshot (jsbeeb's, 896 x 600) -> 192 x 256 inks."""
    a = np.array(Image.open(path).convert('RGB')).astype(int)
    a = a[68:68 + 384:2, 184:184 + 512:2]
    out = np.zeros(a.shape[:2], np.uint8)
    for i, c in enumerate(RGB):
        out[(a == c).all(2)] = i
    return out


def to_img(scr, scale=3):
    return Image.fromarray(RGB[scr]).resize((256 * scale, scr.shape[0] * scale), Image.NEAREST)


def base_scene(seed, sun, planet=None, ship=None):
    rng = np.random.default_rng(seed)
    scr = np.zeros((192, 256), np.uint8)
    scr[0, :] = C
    scr[:, 0] = C
    scr[:, 255] = C
    for _ in range(18):
        scr[rng.integers(2, 190), rng.integers(2, 252)] = Y
    sx, sy, sr = sun
    if planet:              # the planet in front of the sun
        px, py, pr = planet
        fill_disc(scr, sx, sy, sr, SUNE, SUNO)
        fill_disc(scr, px, py, pr, PLANE, PLANO)
    else:
        fill_disc(scr, sx, sy, sr, SUNE, SUNO)
    if ship is not None:
        ys, xs, img = ship
        h, w = img.shape
        sub = scr[ys:ys + h, xs:xs + w]
        sub[img != 0] = img[img != 0]
    for x in range(108, 118):
        scr[96, x] = C
        scr[96, x + 30] = C
    for y in range(76, 86):
        scr[y, 128] = C
        scr[y + 31, 128] = C
    return scr


def ship_sprite():
    """A lit ship cut from an emulator frame if one is to hand, else a
    two-tone triangle."""
    p = os.path.join(OUT, 'src-ship.png')
    if os.path.exists(p):
        return load_shot(p)[60:130, 90:170]
    img = np.zeros((40, 60), np.uint8)
    for y in range(40):
        for x in range(60):
            if x > y * 0.6 and x < 60 - y * 0.6:
                img[y, x] = Y if (x + y) % 2 else (C if x < 30 else M)
    return img


SCENES = [
    # name, sun, planet, ship
    ('top-left', (50, 58, 21), None, False),
    ('near-centre', (150, 80, 22), None, False),
    ('right-edge', (248, 124, 23), None, False),
    ('off-top', (136, -10, 23), None, False),
    ('planet', (60, 40, 18), (190, 150, 60), False),
    ('ship', (200, 40, 22), None, True),
    ('planet-ship', (40, 150, 20), (230, 30, 50), True),
    ('occluded', (150, 120, 18), (140, 120, 50), False),
]


def sheet(mode, name, ghosts=GHOSTS):
    ship = ship_sprite()
    tiles = []
    for i, (label, sun, planet, wship) in enumerate(SCENES):
        sh = (100, 60, ship) if wship else None
        if wship and label == 'planet-ship':
            sh = (70, 150, ship)
        scr = base_scene(i, sun, planet, sh)
        st = {'bytes': 0, 'spans': 0}
        lev = flare(scr, sun, planet, mode, ghosts, st)
        im = to_img(scr, 3)
        tiles.append((label, lev, st, im))
    W, H = 256 * 3, 192 * 3
    out = Image.new('RGB', (2 * W + 12, 4 * H + 36), (40, 40, 40))
    for j, (label, lev, st, im) in enumerate(tiles):
        out.paste(im, ((j % 2) * (W + 12), (j // 2) * (H + 12)))
    out.save(os.path.join(OUT, name))
    for label, lev, st, im in tiles:
        print(f'  {label:12s} level {lev}  {st["spans"]:3d} spans {st["bytes"]:4d} bytes')


def legend():
    """Each ghost of the recipe alone, at levels 3, 2 and 1 (columns), with its
    k, radius, ink and density: 3-assembled-output/flare/ghosts.png."""
    from PIL import ImageDraw
    S = 3
    cell = 72
    names = 'KCMY'
    out = Image.new('RGB', (160 + 3 * cell * S, len(GHOSTS) * cell * S), (40, 40, 40))
    dr = ImageDraw.Draw(out)
    for i, (k, r, ink, n, kind) in enumerate(GHOSTS):
        for j, lev in enumerate((3, 2, 1)):
            scr = np.zeros((cell, cell), np.uint8)
            ne = eff_n(n, lev)
            c = cell // 2
            if ne and kind == 'o':
                for dx, dy in RING[::1 if ne >= 4 else 2]:
                    sh = 1 if r == 30 else 0
                    x, y = c + (dx << sh) // 1, c + (dy << sh)
                    if 0 <= x < cell and 0 <= y < cell:
                        scr[y, x] |= ink
            elif ne:
                hw = hw_table(r)
                for d in range(-r, r + 1):
                    m = row_mask(ne, c + d, i & 3)
                    for x in range(c - hw[abs(d)], c + hw[abs(d)] + 1):
                        if m[x & 3]:
                            scr[c + d, x] |= ink
            img = Image.fromarray(RGB[scr]).resize((cell * S, cell * S), Image.NEAREST)
            out.paste(img, (160 + j * cell * S, i * cell * S))
        rr = 'r 30 (15 x 2)' if kind == 'o' and r == 30 else ('r 15' if kind == 'o' else f'r {r}')
        dr.text((6, i * cell * S + 8), f'k {k:+d}/8\n{rr}\nink {names[ink]}\n{n}/16\n'
                + ('dotted ring' if kind == 'o' else 'disc'), fill=(255, 255, 255))
    dr.text((170, 2), 'level 3', fill=(255, 255, 255))
    dr.text((170 + cell * S, 2), 'level 2', fill=(255, 255, 255))
    dr.text((170 + 2 * cell * S, 2), 'level 1', fill=(255, 255, 255))
    out.save(os.path.join(OUT, 'ghosts.png'))


def emu_sheet():
    """The model over real emulator frames (no flare), if any are in 6-harness/work/flare/bg."""
    import glob
    fs = sorted(glob.glob(os.path.join(SCRATCH, 'bg', 'scan-*.png')))
    logs = os.path.join(SCRATCH, 'bg', 'scan.json')
    if not fs or not os.path.exists(logs):
        return
    import json
    L = json.load(open(logs))
    tiles = []
    for f in fs:
        it = int(f[-9:-4])
        cand = [e for e in L if e[0] <= it and e[1] == 0]
        if not cand:
            continue
        e = cand[-1]
        scr = load_shot(f)
        flare(scr, (e[2], e[3], e[4]))
        tiles.append(to_img(scr, 3))
    W, H = 256 * 3, 192 * 3
    out = Image.new('RGB', (2 * W + 12, ((len(tiles) + 1) // 2) * (H + 12)), (40, 40, 40))
    for j, im in enumerate(tiles):
        out.paste(im, ((j % 2) * (W + 12), (j // 2) * (H + 12)))
    out.save(os.path.join(OUT, 'model-on-emu-frames.png'))


SIGHTS = [(96, x) for x in list(range(108, 118)) + list(range(139, 149))] + \
         [(y, 128) for y in list(range(76, 86)) + list(range(107, 117))]


def check(base_png, emu_png, sx, sy, sr, out_png=None):
    """Compare an emulator frame with the flare (emu_png) against the model
    applied to the same frame without it (base_png, the same TT100 iteration
    of the port without the flare). The laser sights are redrawn over the
    flare, so they are taken from the base frame; stars are only plotted on
    black bytes, so a star the flare covers is missing from the emulator's
    frame (reported apart). Returns (mismatches, star mismatches)."""
    base, emu = load_shot(base_png), load_shot(emu_png)
    model = base.copy()
    lev = flare(model, (sx, sy, sr))
    for y, x in SIGHTS:
        if base[y, x] == C:
            model[y, x] = C
    diff = model[1:192] != emu[1:192]
    ys, xs = np.nonzero(diff)
    star = sum(1 for y, x in zip(ys + 1, xs) if base[y, x] == Y and emu[y, x] != Y)
    if out_png:
        W = 256 * 3
        im = Image.new('RGB', (3 * W + 24, 192 * 3), (40, 40, 40))
        im.paste(to_img(emu), (0, 0))
        im.paste(to_img(model), (W + 12, 0))
        d = np.zeros((192, 256), np.uint8)
        d[1:192][diff] = M
        im.paste(to_img(d), (2 * W + 24, 0))
        im.save(out_png)
    return lev, len(ys), star


# ---------------------------------------------------------------- the tables
# gfx-flare.asm's tables, by ghost number (GHOSTS' order) where they are per
# ghost. A ring's radius byte is its scale (1 for 30, 0 for 15: RING is of
# radius 15); a ring's density index has &80 added.
HTAB_R = [3, 4, 5, 7, 10, 18]           # fl_h3 ... fl_h18, in fl_htab's order


def ink_byte(ink):
    """The ink in all four pixels of a MODE 1 byte (bit 4+p: 2, bit p: 1)."""
    return (0xF0 if ink & 2 else 0) | (0x0F if ink & 1 else 0)


def tables():
    """{label: [bytes]} for the tables gfx-flare.asm takes from the model."""
    t = {}
    t['fl_rad'] = [(1 if r == 30 else 0) if kind == 'o' else r for k, r, ink, n, kind in GHOSTS]
    t['fl_ink'] = [ink_byte(ink) for k, r, ink, n, kind in GHOSTS]
    t['fl_ni'] = [LADDER.index(n) + (0x80 if kind == 'o' else 0) for k, r, ink, n, kind in GHOSTS]
    mt = []                             # fl_mt: density index 1..5, rows 0..3
    for n in LADDER[1:6]:
        for y in range(4):
            mt.append(sum(0x88 >> p for p, on in enumerate(row_mask(n, y, 0)) if on))
    t['fl_mt'] = mt
    ks = [k for k, r, ink, n, kind in GHOSTS]
    t['fl_dk'] = [0] + [a - b for a, b in zip(ks, ks[1:])]
    t['fl_ring'] = [c for p in RING[:9] for c in p]
    t['fl_htab'] = [h for r in HTAB_R for h in hw_table(r)]
    return t


def print_tables():
    for name, b in tables().items():
        print('.%-7s EQUB %s' % (name, ', '.join('&%02X' % x for x in b)))


def asm_literals(src):
    """The literal tables in gfx-flare.asm: the EQUB lines from a table's label
    (or, for fl_mt, its 'fl_mt = P% - 4' line) to the next line that is not an
    EQUB; fl_hl's LO() entries and the FLHW macro are not literals."""
    out, cur = {}, None
    for line in open(src):
        code = line.split('\\')[0].rstrip()
        m = re.match(r'^\.(fl_\w+)\s*(.*)$', code) or re.match(r'^(fl_mt)\s*=', code)
        if m:
            cur = m.group(1)
            rest = m.group(2) if m.lastindex and m.lastindex >= 2 else ''
            out[cur] = []
            code = ' ' + rest
        if cur and re.match(r'^\s*EQUB\s', code):
            try:
                out[cur] += [int(v.strip().replace('&', '0x'), 0) & 0xFF
                             for v in code.split('EQUB', 1)[1].split(',')]
            except ValueError:          # (an expression: not a literal table)
                out[cur], cur = None, None
        elif cur and code.strip():
            cur = None
    return out


def verify(src, build):
    """Exit status 0 if every table matches: the literals in src, and fl_htab
    (FLHW, a BeebAsm macro) as assembled into build's MERID.bin."""
    want, bad = tables(), 0
    lit = asm_literals(src)
    for name, b in want.items():
        if name == 'fl_htab':
            continue
        got = lit.get(name)
        ok = got == b
        bad += not ok
        print('%-8s %s' % (name, 'identical' if ok else 'DIFFERS: source %s, model %s' % (got, b)))
    sym, merid = os.path.join(build, 'symbols.txt'), os.path.join(build, 'MERID.bin')
    if os.path.exists(sym) and os.path.exists(merid):
        sy = dict((k, int(v)) for k, v in re.findall(r"'([^']+)':(\d+)", open(sym).read()))
        at = sy['fl_htab'] - sy['MERID_START']
        got = list(open(merid, 'rb').read()[at:at + len(want['fl_htab'])])
        ok = got == want['fl_htab']
        bad += not ok
        print('%-8s %s (assembled, %s)' % ('fl_htab', 'identical' if ok else 'DIFFERS', merid))
    else:
        print('fl_htab  not checked (no build in %s)' % build)
    print('FLARE TABLES %s' % ('PASS' if not bad else 'FAIL'))
    return 0 if not bad else 1


def main():
    if '--tables' in sys.argv:
        print_tables()
        return
    if '--verify' in sys.argv:
        i = sys.argv.index('--verify')
        a = sys.argv[i + 1:]
        src = a[0] if a else os.path.join(ROOT, '1-source-files', 'main-sources', 'gfx-flare.asm')
        build = a[1] if len(a) > 1 else os.path.join(ROOT, '3-assembled-output')
        sys.exit(verify(src, build))
    os.makedirs(OUT, exist_ok=True)
    if '--check' in sys.argv:
        i = sys.argv.index('--check')
        b, e, sx, sy, sr = sys.argv[i + 1:i + 6]
        out = sys.argv[i + 6] if len(sys.argv) > i + 6 else None
        lev, n, star = check(b, e, int(sx), int(sy), int(sr), out)
        print(f'level {lev}: {n} pixels differ from the model ({star} of them stars the flare covers)')
        return
    for mode in ('or', 'over'):
        print(f'{mode}:')
        sheet(mode, f'model-{mode}.png')
    legend()
    emu_sheet()


if __name__ == '__main__':
    main()
