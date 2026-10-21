#!/usr/bin/env python3
"""Flat-shaded lighting for the ships: the light, the 32-entry hue ramps (one
shared pool for all ships), the 6502's fixed-point shading model, and preview
renders.

Lighting.  Each visible face gets I = 0.5 ambient + 0.5 * max(0, n.L), n the
face's unit normal and L the unit vector towards the light, (1, 1, -1) / sqrt 3
in Elite's frame (x right, y up, z into the screen): the light travels (1, 1, 1)
in screen terms (x left, y down, z in), from the top right into the screen.

Ramp mapping.  A face is never darker than the ambient 0.5, so the 32 entries
span the range in use: entry k is I_k = 0.5 + 0.5 k / 31 of the hue's full
colour (linear light), and a face's level is round(31 max(0, n.L)), the
diffuse term alone (entry 0 = ambient only, the faces turned away from the
light; entry 31 = full).

Hues.  Faces have hues, not colours: each face takes one of its ship's two
hue families (A or B, the family its old fixed colour came from), and one pool
of nine hue ramps (faces.RAMPS' names) is shared by every ship.  Adjacent
faces of the same hue are separated only by the lighting.  Each family's hue
(HUES) is the ink mix of its lightest, most saturated member that has no black
in it (grey: C2M1Y1, not K1C1M1Y1; its other black-free member, C1M1Y2, is
tan's mix); a single-ink member (Y4, C4, M4) is replaced by the family's two-ink one (M1Y3,
C3Y1, M3Y1), as one ink plus black has only 17 levels, too few for 32 distinct
entries.  Each ramp runs from 50% of the hue's own full brightness (entry 0)
to its full brightness (its mix with no black: entry 31).

Selection.  Each entry is a 4x4 ordered dither (16 pixels: a count of each ink,
laid out on a Bayer matrix, brightest inks at the lowest thresholds, so a pixel
lit at one level stays lit above it).  A dynamic programme over all ink counts
(only the hue's own inks plus black) picks the entries, each close in CIELAB
to its target (lightness weighted WL), with lightness strictly rising and as
few pixels as possible changing from one entry to the next (WS per pixel), so
the texture does not flicker as a face's level steps, and little hue drift
between neighbours (WH per squared degree of a*b* angle).

In MODE 1 a 4x4 tile is four bytes, one per row (pixel x of a byte is x AND 3),
so the fill takes row y's byte as tile row y AND 3.  The pool is 9 ramps x 32
entries (1152 bytes as tiles); the tables store each entry as its three
cumulative ink counts packed in two bytes (576 bytes), and the frame layer's
f_col expands it to the four row bytes with 68 bytes of row masks.

Master port (from the demo port's tools/lightramps.py): the tables are in
bank 6 (gfx-light6.asm: the ramp pointers, the row masks, the ramps and the
unlit colours), and the levels are computed in game context with exact products
(the quarter squares QSL/QSH, n^2 / 4) rather than rounded ones; see
light_ship and level_fixed for the arithmetic.

    python3 2-build-files/lightramps.py       report: per-hue L* table, ramps32.png
    python3 2-build-files/lightramps.py anim  + one tumble animation per ship type
"""
import os
import sys
import math
import itertools
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import faces as F          # noqa: E402
import swatch35 as SW      # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, '3-assembled-output', 'lighting')
NLEV = 32               # ramp entries: I = 0.5 .. 1
AMB, DIF = 0.5, 0.5
LTO = np.array([1.0, 1.0, -1.0]) / math.sqrt(3)       # towards the light (Elite frame)
WL = 12.0                                              # DP: lightness weight
WS = 12.0                                              # DP: weight per pixel changed between entries
WH = 0.3                                               # DP: weight per (degree of hue drift)^2 between entries

# each family's hue: (cyan, magenta, yellow) ink counts, black removed
HUES = {
    'red':    (0, 1, 1),
    'gold':   (0, 1, 3),
    'cyan':   (3, 0, 1),
    'blue':   (1, 1, 0),
    'green':  (1, 0, 1),
    'purple': (1, 3, 0),
    'pink':   (0, 3, 1),
    'tan':    (1, 1, 2),
    'grey':   (2, 1, 1),
}
HUE_ORDER = list(HUES)          # ramp index = position here

INK_RGB = np.array([SW.PHYS[i] for i in (SW.K, SW.C, SW.M, SW.Y)], float)
INK_LIN = np.array([[F._lin(float(c)) for c in rgb] for rgb in INK_RGB])
LUMA = INK_LIN @ np.array([0.2126, 0.7152, 0.0722])
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]])
COMPS = [c for c in itertools.product(range(17), repeat=4) if sum(c) == 16]   # (k, c, m, y)
COMP_LIN = np.array([sum(n * INK_LIN[i] for i, n in enumerate(c)) / 16 for c in COMPS])
COMP_LAB = np.array([F._lab(tuple(li)) for li in COMP_LIN])


def lab(li):
    return np.array(F._lab(tuple(li)))


def hue_lin(name):
    c, m, y = HUES[name]
    return (c * INK_LIN[1] + m * INK_LIN[2] + y * INK_LIN[3]) / (c + m + y)


def lum(li):
    return float(li @ np.array([0.2126, 0.7152, 0.0722]))


def levels_I():
    """Each entry's light: AMB .. 1 over entries 0..31."""
    return [AMB + DIF * k / (NLEV - 1) for k in range(NLEV)]


def targets(name):
    return np.array([lab(hue_lin(name) * I) for I in levels_I()])


def tile(comp):
    """4x4 ordered layout of a 16-pixel plan (ink index per pixel)."""
    plan = sorted([i for i, n in enumerate(comp) for _ in range(n)], key=lambda i: -LUMA[i])
    return np.array(plan)[BAYER]


def ramp(name):
    """NLEV ink counts (k, c, m, y) for the hue: a dynamic programme over the
    16-pixel plans of the hue's own inks plus black, minimising the sum of
    each entry's CIELAB error to its target (lightness weighted WL) and WS
    times the number of pixels that change between consecutive tiles (their
    Hamming distance: smooth texture as the level steps) and WH times their
    squared hue-angle difference (degrees), with lightness strictly rising."""
    tg = targets(name)
    c_, m_, y_ = HUES[name]
    idx = [i for i, cp in enumerate(COMPS)
           if all(cnt == 0 or have for cnt, have in zip(cp[1:], (c_, m_, y_)))]
    idx.sort(key=lambda i: COMP_LAB[i, 0])
    LAB = COMP_LAB[idx]
    Lv = LAB[:, 0]
    T = np.array([tile(COMPS[i]).reshape(-1) for i in idx])
    Ham = (T[:, None, :] != T[None, :, :]).sum(2)
    ang = np.degrees(np.arctan2(LAB[:, 2], LAB[:, 1]))
    dang = np.abs((ang[:, None] - ang[None, :] + 180) % 360 - 180)
    lower = Lv[:, None] < Lv[None, :] - 1e-9          # [i, j]: i may precede j
    INF = 1e18


    def cost(k):
        return WL * (Lv - tg[k, 0]) ** 2 + ((LAB[:, 1:] - tg[k, 1:]) ** 2).sum(1)
    best = cost(0)
    back = []
    for k in range(1, NLEV):
        tr = np.where(lower, best[:, None] + WS * Ham + WH * dang ** 2, INF)
        arg = tr.argmin(0)
        back.append(arg)
        best = tr[arg, np.arange(len(idx))] + cost(k)
    i = int(np.argmin(best))
    path = [i]
    for b in reversed(back):
        i = int(b[i])
        path.append(i)
    path.reverse()
    return [COMPS[idx[i]] for i in path]


def tile_bytes(t):
    """The four MODE 1 bytes (rows 0..3) of a 4x4 tile of ink indices."""
    out = []
    for row in range(4):
        b = 0
        for p in range(4):
            v = int(t[row, p])
            b |= ((v >> 1) & 1) << (7 - p) | (v & 1) << (3 - p)
        out.append(b)
    return out


_RAMPS = None


def ramps():
    """{family: [NLEV tiles]}."""
    global _RAMPS
    if _RAMPS is None:
        _RAMPS = {h: [tile(c) for c in ramp(h)] for h in HUE_ORDER}
    return _RAMPS


def tile_lab(t):
    li = INK_LIN[t.reshape(-1)].mean(0)
    return lab(li)


# ---------------------------------------------------------------- shading
# The 6502's arithmetic (gfx-light.asm).  Unit normals (magnitude
# 61) and the light in ship space (<= 64) are signed integers; a product is
# exact, a * b = QS[|a + b|] - QS[|a - b|] with the quarter squares QS[n] =
# floor(n^2 / 4) (QSL/QSH), summed over x, y, z in 16 bits, S, and rounded
# once: d = (S + 16) >> 5 (about 118 for n.L = 1, never above 125).  level =
# min(31, (d + d / 16 + 2) / 4) (d * 31 / 119 within 2%), or 0 if S < 0.

NSC = 61                # normal scale: keeps d within a signed byte with margin


def dot32(a, b):
    """(a . b + 16) >> 5 as the 6502 makes it (S fits 16 bits)."""
    S = sum(x * y for x, y in zip(a, b))
    assert -32768 <= S + 16 < 32768
    return S, (S + 16) >> 5


def unit63(n):
    m = math.sqrt(sum(c * c for c in n))
    return tuple(int(round(NSC * c / m)) for c in n)


LL_FIXED = (24, 24, -24)        # (1, 1, -1) / sqrt 3 * 41.3: the title screen's light


def light_ship(R, LL=LL_FIXED):
    """The light in ship space as the 6502 makes it (gfx-light.asm L_REC): for
    each axis a (sidev, roofv, nosev = columns of R), its high bytes
    (sign-magnitude, 96 = 1) halved, h, then Ls[a] = (h . LL + 16) >> 5, for
    LL = the light towards the sun * 41.3."""
    out = []
    for a in range(3):
        h = []
        for i in range(3):
            hb = int(round(96 * R[i, a]))
            h.append((abs(hb) >> 1) * (1 if hb >= 0 else -1))
        out.append(dot32(h, LL)[1])
        assert -128 <= out[-1] <= 127
    return out


def level_fixed(n63, Ls):
    S, d = dot32(n63, Ls)
    if S < 0:
        return 0
    assert d <= 127
    return min(NLEV - 1, (d + (d >> 4) + 2) >> 2)


def level_float(nv):
    return int(round((NLEV - 1) * max(0.0, float(nv @ LTO))))


# ---------------------------------------------------------------- tables
FIXED = {'black': 0, 'cyan': 1, 'magenta': 2, 'yellow': 3}   # unlit colours
FIXED_COMP = {'black': (16, 0, 0, 0), 'cyan': (0, 16, 0, 0), 'magenta': (0, 0, 16, 0),
              'yellow': (0, 0, 0, 16)}
SWATCH_FIXED = {F.BLACK: 'black', F.INK_SWATCH[SW.C]: 'cyan', F.INK_SWATCH[SW.M]: 'magenta',
                F.INK_SWATCH[SW.Y]: 'yellow'}
NRAMP = len(HUE_ORDER)
FIXED_BYTE = [0x00, 0x0F, 0xF0, 0xFF]   # the unlit colours' MODE 1 bytes (every row)


def hue_byte(fam):
    """A face's colour byte: its ramp (0..8); the lighting picks the entry."""
    return HUE_ORDER.index(fam)


def fixed_byte(swatch):
    """An unlit item's colour byte: &80 + k (black, cyan, magenta, yellow)."""
    return 0x80 + FIXED[SWATCH_FIXED[swatch]]


def comp_of(t):
    return tuple(int((t == i).sum()) for i in range(4))


def cum(comp):
    """(a, b, c): pixels with Bayer threshold t < a are yellow, a <= t < b cyan,
    b <= t < c magenta, the rest black (tile's luma order Y, C, M, K)."""
    k, c, m, y = comp
    return y, y + c, y + c + m


def rowmask(r, n):
    """4-bit mask of row r's pixels with threshold < n (pixel p = bit 3 - p)."""
    return sum(1 << (3 - p) for p in range(4) if BAYER[r][p] < n)


def expand(a, b, c):
    """The four row bytes as f_col makes them: H[a] EOR H[c] EOR HL[b] with
    H[n] = mask << 4 = HL[n] AND &F0, HL[n] = mask << 4 OR mask (yellow sets
    both bits of a pixel, cyan the low one, magenta the high one)."""
    out = []
    for r in range(4):
        H = lambda n: rowmask(r, n) << 4
        out.append(H(a) ^ H(c) ^ (H(b) | rowmask(r, b)))
    return out


def emit_light(path6):
    """gfx-light6.asm (bank 6): the lighting tables."""
    R = ramps()
    entries = [[comp_of(R[h][k]) for k in range(NLEV)] for h in HUE_ORDER]
    for blk in entries:
        for comp in blk:
            assert expand(*cum(comp)) == tile_bytes(tile(comp)), comp
    for k, comp in enumerate(FIXED_COMP[c] for c in sorted(FIXED, key=FIXED.get)):
        assert tile_bytes(tile(comp)) == [FIXED_BYTE[k]] * 4
    head = ['\\ %s -- generated by faces.py and lightramps.py (see docs/renderer.md); do not edit.',
            '\\',
            '\\ Lighting tables (lightramps.py has the model: docs/renderer.md), in bank 6',
            '\\ for the frame layer\'s f_col.',
            '\\ The shared ramp pool: ramps 0..%d (%s), 32 entries' % (NRAMP - 1, ', '.join(HUE_ORDER)),
            '\\   each (0 ambient only, 50% of the hue .. 31 full light).',
            '\\   LT_RL/LT_RH[ramp] -> 32 low bytes, then 32',
            '\\   high bytes, of w = a + 32 b + 1024 c for the entry\'s 4x4 dither: Bayer',
            '\\   thresholds t < a yellow, < b cyan, < c magenta, the rest black.',
            '\\ LT_HL0..3[n] (n = 0..16): row r\'s mask m of pixels with threshold < n as',
            '\\   m << 4 OR m: row byte = H[a] EOR H[c] EOR HL[b], H = HL AND &F0.',
            '\\ LT_FIX[k] (with the last ramp): the unlit colours (black, cyan, magenta, yellow) as',
            '\\   MODE 1 bytes.',
            '\\ (The unit face normals, magnitude %d, are in gfx-faces.asm\'s face lists.)' % NSC,
            '']

    def eb(L, vals, per=16):
        for i in range(0, len(vals), per):
            L.append(' EQUB ' + ', '.join('&%02X' % (v & 255) for v in vals[i:i + per]))

    def ramp(L, i):
        w = [a + 32 * b + 1024 * c for a, b, c in (cum(comp) for comp in entries[i])]
        L.append('.LT_P%d                         \\ %s' % (i, HUE_ORDER[i]))
        eb(L, [v & 255 for v in w])
        eb(L, [v >> 8 for v in w])
    L6 = [h % 'gfx-light6.asm' if '%s' in h else h for h in head]
    L6.append('.LT_RL')
    L6.append(' EQUB ' + ', '.join('LO(LT_P%d)' % i for i in range(NRAMP)))
    L6.append('.LT_RH')
    L6.append(' EQUB ' + ', '.join('HI(LT_P%d)' % i for i in range(NRAMP)))
    for r in range(4):
        L6.append('.LT_HL%d' % r)
        eb(L6, [rowmask(r, n) << 4 | rowmask(r, n) for n in range(17)], 17)
    for i in range(NRAMP):
        ramp(L6, i)
    L6.append('.LT_FIX')
    eb(L6, FIXED_BYTE)
    open(path6, 'w').write('\n'.join(L6) + '\n')


# ---------------------------------------------------------------- report
def report():
    R = ramps()
    tg = levels_I()
    print('ramp pool: %d hues x %d entries = %d tiles (%d bytes as 4-byte tiles, %d packed)'
          % (NRAMP, NLEV, NRAMP * NLEV, 4 * NRAMP * NLEV, 2 * NRAMP * NLEV))
    print('hues (C, M, Y ink mix) and full-brightness L*: ' +
          ', '.join('%s C%dM%dY%d %.1f' % ((h,) + HUES[h] + (lab(hue_lin(h))[0],)) for h in HUE_ORDER))
    print('\nL* of each entry (target in brackets)')
    print('entry  I     | ' + ' '.join('%13s' % h for h in HUE_ORDER))
    errs = []
    for k in range(NLEV):
        cells = []
        for h in HUE_ORDER:
            got, want = tile_lab(R[h][k])[0], targets(h)[k][0]
            errs.append(abs(got - want))
            cells.append('%5.1f (%5.1f)' % (got, want))
        print('%5d %5.3f | ' % (k, tg[k]) + ' '.join(cells))
    print('L* error: worst %.1f, mean %.2f' % (max(errs), np.mean(errs)))
    for h in HUE_ORDER:
        dE = [np.linalg.norm(tile_lab(R[h][k]) - targets(h)[k]) for k in range(NLEV)]
        cnt = [comp_of(R[h][k]) for k in range(NLEV)]
        Ls = [tile_lab(R[h][k])[0] for k in range(NLEV)]
        assert all(b > a for a, b in zip(Ls, Ls[1:])) and len(set(map(tuple, cnt))) == NLEV
        print('%-7s mean dE %.1f  %s' % (h, np.mean(dE), ' '.join('K%dC%dM%dY%d' % c for c in cnt)))


def ramps_png(path):
    from PIL import Image
    R = ramps()
    rows = []
    for h in HUE_ORDER:
        rows.append(np.concatenate([np.tile(t, (4, 4)) for t in R[h]], 1))
        rows.append(np.zeros((4, NLEV * 16), int))
    img = INK_RGB[np.concatenate(rows, 0)].astype(np.uint8)
    Image.fromarray(np.kron(img, np.ones((3, 3, 1), np.uint8))).save(path)


# ---------------------------------------------------------------- rendering
W, H = 256, 192


def prepared_ships():
    ships = F.load_ships()
    for t, s in ships:
        F.reconstruct(s)
        F.structure(s)
        F.colour_ship(t, s)
        annotate(t, s)
    return ships


def annotate(t, s):
    """Lighting attributes: each face's hue family (s['fam']) and unit normal;
    each detail polygon's family, the other one than its face's (the lighting
    gives a detail its face's level, so it must differ in hue), or None for a
    black one (the station's slot); a fin keeps its old colour's family
    and is drawn at the brighter of its two faces' levels (0, ambient, if hidden)."""
    hA, hB = F.SHIP_HUES[t]
    s['n63'] = [unit63(f['n']) for f in s['faces']]
    for d in s['dets']:
        if d['kind'] == 'poly':
            f = d['faces'][0]
            d['fam'] = None if d['col'] == F.BLACK else (hB if s['fam'][f] == hA else hA)
    for d in s['fins']:            # a fin keeps its old colour's family
        d['fam'] = hA if d['col'] in F.RAMPS[hA] else hB


def cell_tile(sw):
    cl = SW.cell(*SW.ALL[sw])
    return np.array([[cl[(x & 1, y & 1)] for x in range(4)] for y in range(4)])


def render(t, s, M, pos, lit, fixed=True):
    """One frame: ship s with orientation M (columns sidev, roofv, nosev in
    view space) at pos.  lit: shaded with the ramps (6502 arithmetic if
    fixed), else the fixed colours."""
    from PIL import Image, ImageDraw
    R = ramps()
    V = np.array([[v['x'], v['y'], v['z']] for v in s['verts']], float)
    P = V @ M.T + pos
    NR = np.array([f['n'] for f in s['faces']], float)
    N = NR @ M.T
    proj = np.c_[W / 2 + 256 * P[:, 0] / P[:, 2], H / 2 - 256 * P[:, 1] / P[:, 2]]
    fid = Image.new('I', (W, H), 0)
    d = ImageDraw.Draw(fid)
    tiles = {}
    Ls = light_ship(M)
    lev = {}
    vis = {}
    for f in range(len(s['faces'])):
        vis[f] = N[f] @ P[s['nodes'][f]['poly'][0] if s['nodes'][f]['poly'] else 0] < 0
        lev[f] = (level_fixed(s['n63'][f], Ls) if fixed else level_float(N[f] / np.linalg.norm(N[f]))) \
            if vis[f] else 0          # hidden: ambient (fins behind the body)
    key = [1]

    def put(poly, til, line=False):
        k = key[0]
        key[0] += 1
        tiles[k] = til
        pts = [tuple(proj[v]) for v in poly]
        if line:
            d.line(pts, fill=k)
        else:
            d.polygon(pts, fill=k)

    def fins(kk):
        for dt in s['fins']:
            f1, f2 = dt['faces']
            if vis[f1] + vis[f2] != kk:
                continue
            put(dt['verts'], R[dt['fam']][max(lev[f1], lev[f2])] if lit else cell_tile(dt['col']))
    fins(0)
    for f, nd in enumerate(s['nodes']):
        if vis[f] and len(nd['poly']) >= 3:
            put(nd['poly'], R[s['fam'][f]][lev[f]] if lit else cell_tile(s['col'][f]))
    for dt in s['dets']:
        f1, f2 = dt['faces']
        if not (vis[f1] or vis[f2]):
            continue
        if dt['kind'] == 'poly':
            if lit and dt['fam']:
                til = R[dt['fam']][lev[f1]]
            else:
                til = cell_tile(dt['col'])
            put(dt['verts'], til)
        else:
            put(dt['verts'], cell_tile(dt['col']), line=True)
    fins(1)
    fins(2)
    ids = np.array(fid)
    yy, xx = np.mgrid[0:H, 0:W]
    out = np.zeros((H, W), int)
    for k, til in tiles.items():
        m = ids == k
        out[m] = til[yy[m] & 3, xx[m] & 3]
    return INK_RGB[out].astype(np.uint8)


def rot(ax, a):
    c, s_ = math.cos(a), math.sin(a)
    i, j = [(1, 2), (2, 0), (0, 1)][ax]
    m = np.eye(3)
    m[i, i] = m[j, j] = c
    m[i, j] = -s_
    m[j, i] = s_
    return m


MIRROR = np.diag([1.0, 1.0, -1.0])      # ZINF: nose towards the viewer (det -1, as in the game)


def tumble_frames(n):
    """Orientations: three axes at rates 1, phi, sqrt 2 (incommensurate) plus a
    full turn each over the loop so it closes."""
    phi = (1 + math.sqrt(5)) / 2
    out = []
    for i in range(n):
        u = 2 * math.pi * i / n
        a = 2 * u + 0.9 * math.sin(phi * u) + 0.2
        b = 3 * u + 0.7 * math.sin(math.sqrt(2) * u + 1) + 0.5
        c = 1 * u + 0.8 * math.sin(math.sqrt(3) * u) + 0.1
        out.append(rot(0, a) @ rot(1, b) @ rot(2, c) @ MIRROR)
    return out


def ship_pos(s):
    rmax = max(math.sqrt(v['x'] ** 2 + v['y'] ** 2 + v['z'] ** 2) for v in s['verts'])
    return np.array([0.0, 0.0, 256 * rmax / 82])


def anim(outdir, secs=9.6, fps=25, scale=3):
    from PIL import Image
    import subprocess
    os.makedirs(outdir, exist_ok=True)
    ships = prepared_ships()
    n = int(secs * fps)
    Ms = tumble_frames(n)
    sheet = []
    for t, s in ships:
        pos = ship_pos(s)
        name = '%02d-%s' % (t, s['name'].split(' (')[0].lower().replace(' ', '-').replace('.', ''))
        if '(' in s['name']:
            name += '-' + s['name'].split('(')[1].rstrip(')').replace(' ', '-')
        frames = []
        gap = np.full((H, 4, 3), 60, np.uint8)
        for M in Ms:
            frames.append(np.concatenate([render(t, s, M, pos, True), gap, render(t, s, M, pos, False)], 1))
        big = [Image.fromarray(np.kron(f, np.ones((scale, scale, 1), np.uint8))) for f in frames]
        big[0].save(os.path.join(outdir, name + '.gif'), save_all=True, append_images=big[1:],
                    duration=1000 // fps, loop=0)
        tmp = os.path.join(outdir, '.frames')
        os.makedirs(tmp, exist_ok=True)
        for i, b in enumerate(big):
            b.save(os.path.join(tmp, '%04d.png' % i))
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', str(fps), '-i',
                        os.path.join(tmp, '%04d.png'), '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
                        '-crf', '16', os.path.join(outdir, name + '.mp4')], check=True)
        for f in os.listdir(tmp):
            os.remove(os.path.join(tmp, f))
        os.rmdir(tmp)
        sheet.append((name, [frames[i][:, :W] for i in (0, n // 3, 2 * n // 3)]))
        print('wrote', name)
    # contact sheet: three lit frames per type
    from PIL import ImageDraw
    rows = []
    for name, fr in sheet:
        row = np.concatenate([np.concatenate([f, np.full((H, 4, 3), 40, np.uint8)], 1) for f in fr], 1)
        rows.append(np.concatenate([row, np.full((4, row.shape[1], 3), 40, np.uint8)], 0))
    cols = 2
    while len(rows) % cols:
        rows.append(np.zeros_like(rows[0]))
    grid = np.concatenate([np.concatenate(rows[r * cols:(r + 1) * cols], 1)
                           for r in range(len(rows) // cols)], 0)
    img = Image.fromarray(np.kron(grid, np.ones((2, 2, 1), np.uint8)))
    dr = ImageDraw.Draw(img)
    for i, (name, _) in enumerate(sheet):
        r, c = divmod(i, cols)
        dr.text((c * rows[0].shape[1] * 2 + 6, r * rows[0].shape[0] * 2 + 4), name, fill=(255, 255, 255))
    img.save(os.path.join(outdir, 'contact-sheet-lit.png'))


def main():
    report()
    os.makedirs(OUT, exist_ok=True)
    ramps_png(os.path.join(OUT, 'ramps32.png'))
    if 'anim' in sys.argv[1:]:
        anim(os.path.join(OUT, 'anim'))


if __name__ == '__main__':
    main()
