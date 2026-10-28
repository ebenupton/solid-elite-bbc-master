#!/usr/bin/env python3
"""Filled ships for the Master port (from the demo port's tools/faces.py):
parse Master Elite's 33 ship blueprints (3-assembled-output/HZDATA.bin), rebuild each
face's polygon, turn the blueprint's detail edges into filled surface details,
fins and lines, find each ship's symmetries and give every face a fixed colour
from two hue ramps (adjacent faces never alike, symmetric where the geometry
allows), and write gfx-faces.asm and gfx-light6.asm in
1-source-files/main-sources (after a build: it reads the build's HZDATA.bin and
symbols.txt; the blueprints do not depend on the tables it writes).

See docs/renderer.md.

    python3 2-build-files/faces.py  -> 1-source-files/main-sources/gfx-faces.asm
                                       and gfx-light6.asm, and a report on stdout
"""
import os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # the repository
BUILD = os.path.join(ROOT, '3-assembled-output')
SRC = os.path.join(ROOT, '1-source-files', 'main-sources')
NAMES = {1: 'Missile', 2: 'Coriolis station', 3: 'Escape pod', 4: 'Alloy plate', 5: 'Cargo canister',
         6: 'Boulder', 7: 'Asteroid', 8: 'Splinter', 9: 'Shuttle', 10: 'Transporter',
         11: 'Cobra Mk III', 12: 'Python', 13: 'Boa', 14: 'Anaconda', 15: 'Rock hermit',
         16: 'Viper', 17: 'Sidewinder', 18: 'Mamba', 19: 'Krait', 20: 'Adder', 21: 'Gecko',
         22: 'Cobra Mk I', 23: 'Worm', 24: 'Cobra Mk III (pirate)', 25: 'Asp Mk II',
         26: 'Python (pirate)', 27: 'Fer-de-lance', 28: 'Moray', 29: 'Thargoid', 30: 'Thargon',
         31: 'Constrictor', 32: 'Cougar', 33: 'Dodecahedron station'}
NTYPES = 33
# Vertex face lists as the build's blueprints have them, where they differ
# from the data (none: Master Elite's blueprints are used unchanged)
PATCH = {}


def _mem():
    """The game data in HAZEL (3-assembled-output/HZDATA.bin, from XX21 at &C000) and XX21's
    address."""
    mem = bytearray(0x10000)
    sy = {}
    for m in re.finditer(r"'([^']+)':(\d+)", open(os.path.join(BUILD, 'symbols.txt')).read()):
        sy.setdefault(m.group(1), int(m.group(2)))
    d = open(os.path.join(BUILD, 'HZDATA.bin'), 'rb').read()
    mem[sy['XX21']:sy['XX21'] + len(d)] = d
    return mem, sy['XX21']


def _sgn(b, mask, v):
    return -v if b & mask else v


def parse(mem, a):
    h = mem[a:a + 20]
    eoff = h[3] | h[16] << 8
    foff = h[4] | h[17] << 8
    nv, ne, nf = h[8] // 6, h[9], h[12] // 4
    verts = []
    for i in range(nv):
        b = mem[a + 20 + 6 * i:a + 26 + 6 * i]
        verts.append(dict(x=_sgn(b[3], 0x80, b[0]), y=_sgn(b[3], 0x40, b[1]), z=_sgn(b[3], 0x20, b[2]),
                          vis=b[3] & 31, faces=(b[4] & 15, b[4] >> 4, b[5] & 15, b[5] >> 4)))
    edges = []
    ea = (a + eoff) & 0xFFFF
    for i in range(ne):
        b = mem[ea + 4 * i:ea + 4 * i + 4]
        edges.append(dict(vis=b[0] & 31, f1=b[1] & 15, f2=b[1] >> 4, v1=b[2] >> 2, v2=b[3] >> 2))
    faces = []
    fa = (a + foff) & 0xFFFF
    for i in range(nf):
        b = mem[fa + 4 * i:fa + 4 * i + 4]
        faces.append(dict(vis=b[0] & 31, n=(_sgn(b[0], 0x80, b[1]), _sgn(b[0], 0x40, b[2]),
                                            _sgn(b[0], 0x20, b[3]))))
    return dict(addr=a, scale=h[18], gun=h[6], visdist=h[13], verts=verts, edges=edges, faces=faces)


def _ref_mem():
    """The released SNG47's data (4-reference-binaries/sng47/BDATA.unprot.bin, at
    &7000, XX21 at &8000): the blueprints with their edge lists, which the
    build no longer assembles (elite-data.asm's EDGE macro)."""
    mem = bytearray(0x10000)
    d = open(os.path.join(ROOT, '4-reference-binaries', 'sng47', 'BDATA.unprot.bin'), 'rb').read()
    mem[0x7000:0x7000 + len(d)] = d
    return mem, 0x8000


def load_ships():
    mem, xx21 = _mem()
    rmem, rxx21 = _ref_mem()
    out = []
    for t in range(1, NTYPES + 1):
        a = mem[xx21 + 2 * (t - 1)] | mem[xx21 + 2 * (t - 1) + 1] << 8
        s = parse(mem, a)
        # the edges from the reference's copy of the blueprint (the build's
        # edge offset now points at its faces); its vertices and faces must
        # be the build's
        ra = rmem[rxx21 + 2 * (t - 1)] | rmem[rxx21 + 2 * (t - 1) + 1] << 8
        r = parse(rmem, ra)
        assert (r['verts'], r['faces'], r['scale']) == (s['verts'], s['faces'], s['scale']), t
        s['edges'] = r['edges']
        s['name'] = NAMES[t]
        if len(s['faces']) == 1 and all(e['f1'] == e['f2'] == 15 for e in s['edges']):
            # the alloy plate: one face, its edges all on "face 15" (always
            # drawn); for the reconstruction they are the sides of face 0
            for e in s['edges']:
                e['f1'], e['f2'] = 0, 15
        for v, fl in PATCH.get(t, {}).items():
            s['verts'][v]['faces'] = fl
        out.append((t, s))
    return out


# ---------------------------------------------------------------------------
# Face reconstruction

import math
from collections import defaultdict


def _vec(v):
    return (v['x'], v['y'], v['z'])


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _unit(a):
    m = math.sqrt(_dot(a, a))
    return (a[0] / m, a[1] / m, a[2] / m)


def _basis(n):
    """Two unit vectors u, w spanning the plane normal to n, with u x w = n-hat
    (so angles measured from u towards w go anticlockwise about n)."""
    nh = _unit(n)
    a = (1, 0, 0) if abs(nh[0]) < 0.9 else (0, 1, 0)
    u = _unit(_cross(a, nh))
    w = _cross(nh, u)
    return nh, u, w


def _hull(pts):
    """Andrew's monotone chain on [(x, y, id)]; anticlockwise, collinear points dropped."""
    pts = sorted(set(pts))
    if len(pts) < 3:
        return [p[2] for p in pts]

    def cr(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cr(lo[-2], lo[-1], p) <= 1e-9:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cr(hi[-2], hi[-1], p) <= 1e-9:
            hi.pop()
        hi.append(p)
    return [p[2] for p in lo[:-1] + hi[:-1]]


def reconstruct(s):
    """Fill s['polys'][f] (list of vertex indices, clockwise about the face
    normal in blueprint coordinates = clockwise on screen when front-facing,
    or [] if unfillable), s['detail'] (edge
    indices that are not polygon sides) and s['notes'] (diagnostics)."""
    V = [_vec(v) for v in s['verts']]
    notes = []
    polys = []
    # Faces that share a plane (an identical blueprint normal) and of which some
    # face has no closed boundary of its own (the Adder's back: faces 6, 7 and 8,
    # each with two of the hexagon's sides) are one polygon, on the lowest of
    # them; the others are left empty. They share a normal, so Elite gives them
    # the same visibility and the lighting the same level.
    def _closes(f):
        adj = defaultdict(set)
        for e in s['edges']:
            if f in (e['f1'], e['f2']) and e['f1'] != e['f2']:
                adj[e['v1']].add(e['v2'])
                adj[e['v2']].add(e['v1'])
        changed = True
        while changed:
            changed = False
            for v in list(adj):
                if len(adj[v]) <= 1:
                    for o in adj[v]:
                        adj[o].discard(v)
                    del adj[v]
                    changed = True
        return len(adj) >= 3
    byn = defaultdict(set)
    for f, face in enumerate(s['faces']):
        if face['n'] != (0, 0, 0):
            byn[tuple(face['n'])].add(f)
    merged = {}
    for G in byn.values():
        if len(G) > 1 and not all(_closes(f) for f in G):
            for f in G:
                merged[f] = G
    for f, face in enumerate(s['faces']):
        n = face['n']
        if n == (0, 0, 0):
            # Master's alloy plate: a single face with no normal (LL9 shows it
            # from both sides); take the plane of its vertices (Newell)
            es = [e for e in s['edges'] if f in (e['f1'], e['f2'])] or s['edges']
            vs = sorted({e['v1'] for e in es} | {e['v2'] for e in es})
            c = [sum(V[v][i] for v in vs) / len(vs) for i in range(3)]
            vs.sort(key=lambda v: math.atan2(V[v][1] - c[1], V[v][0] - c[0]))
            n = tuple(_newell(V, vs))
            face['n'] = n
            notes.append(f'face {f}: zero normal in the blueprint, plane of its vertices used')
        nh, u, w = _basis(n)
        G = merged.get(f, {f})
        if f in merged and f != min(G):
            polys.append([])
            notes.append(f'face {f}: drawn as part of face {min(G)} (same plane) -> n=0')
            continue
        B = [e for e in s['edges'] if (e['f1'] in G) != (e['f2'] in G)] if len(G) > 1 else \
            [e for e in s['edges'] if f in (e['f1'], e['f2']) and e['f1'] != e['f2']]
        if len(G) > 1:
            notes.append(f'face {f}: faces {sorted(G)} share a plane and no face of them closes alone: one polygon, face {f}')
        adj = defaultdict(set)
        for e in B:
            adj[e['v1']].add(e['v2'])
            adj[e['v2']].add(e['v1'])
        # prune dangling chains (guns, fins): degree-1 vertices, repeatedly
        changed = True
        while changed:
            changed = False
            for v in list(adj):
                if len(adj[v]) <= 1:
                    for o in adj[v]:
                        adj[o].discard(v)
                    del adj[v]
                    changed = True
        cand = sorted(adj)
        if len(cand) < 3:
            polys.append([])
            notes.append(f'face {f}: no closed boundary ({len(B)} edges) -> n=0')
            continue
        ext = max(math.dist(V[a], V[b]) for a in cand for b in cand)
        keep = cand
        pts = [(round(_dot(u, V[v]), 6), round(_dot(w, V[v]), 6), v) for v in keep]
        poly = _hull(pts)
        inside = [v for v in keep if v not in poly]
        # an interior (non-collinear) candidate means the boundary is non-convex
        for v in inside:
            # collinear with a hull side?
            p = (_dot(u, V[v]), _dot(w, V[v]))
            on = False
            for i in range(len(poly)):
                a, b = poly[i], poly[(i + 1) % len(poly)]
                pa = (_dot(u, V[a]), _dot(w, V[a]))
                pb = (_dot(u, V[b]), _dot(w, V[b]))
                cr = (pb[0] - pa[0]) * (p[1] - pa[1]) - (pb[1] - pa[1]) * (p[0] - pa[0])
                if abs(cr) < 1e-6 * ext * ext:
                    on = True
            if not on:
                notes.append(f'face {f}: boundary vertex {v} inside hull -> face non-convex')
        if len(poly) < 3:
            polys.append([])
            notes.append(f'face {f}: degenerate hull -> n=0')
            continue
        # true normal of the polygon (Newell) vs blueprint normal
        nw = [0.0, 0.0, 0.0]
        for i in range(len(poly)):
            a, b = V[poly[i]], V[poly[(i + 1) % len(poly)]]
            nw[0] += (a[1] - b[1]) * (a[2] + b[2])
            nw[1] += (a[2] - b[2]) * (a[0] + b[0])
            nw[2] += (a[0] - b[0]) * (a[1] + b[1])
        ang = math.degrees(math.acos(max(-1, min(1, _dot(_unit(nw), nh)))))
        nwh = _unit(nw)
        hs = [_dot(nwh, V[v]) for v in keep]
        dev = (max(hs) - min(hs)) / 2
        if dev > 0.02 * ext:
            notes.append(f'face {f}: non-planar: vertices +-{dev:.1f} off their best plane '
                         f'over extent {ext:.0f}')
        if ang > 5:
            notes.append(f'face {f}: blueprint normal is {ang:.0f} deg off the polygon\'s true normal')
        # hull sides should be blueprint edges of this face
        eset = {frozenset((e['v1'], e['v2'])) for e in s['edges'] if e['f1'] in G or e['f2'] in G}
        for i in range(len(poly)):
            a, b = poly[i], poly[(i + 1) % len(poly)]
            if frozenset((a, b)) not in eset:
                notes.append(f'face {f}: hull side {a}-{b} is not an edge of this face')
        # The hull runs anticlockwise about the blueprint normal (right-hand rule
        # in blueprint coordinates).  Every ship orientation in the game has det
        # -1 (ZINF: sidev (1,0,0), roofv (0,1,0), nosev (0,0,-1); TIDY keeps
        # sidev = nosev x roofv), a reflection, so that order shows anticlockwise
        # on screen; reverse it to get CLOCKWISE ON SCREEN (x right, y down) for a
        # front-facing face.
        polys.append(poly[::-1])
    # detail edges: not a side of the polygon of either of its faces
    detail = []
    for i, e in enumerate(s['edges']):
        side = False
        for f in {e['f1'], e['f2']}:
            p = polys[f] if f < len(polys) else []
            for j in range(len(p)):
                if {p[j], p[(j + 1) % len(p)]} == {e['v1'], e['v2']}:
                    side = True
        if not side:
            detail.append(i)
    s['polys'], s['detail'], s['notes'] = polys, detail, notes
    return s


def check_projection(s, samples=20000, seed=1):
    """Each polygon vertex must be projected by LL9 whenever its face is filled:
    LL9 projects vertex v only if one of v's four faces (or face 15) has XX2 != 0
    and v's visibility distance >= XX4.  Static test + Monte Carlo over viewpoints
    using Elite's own test (face f visible iff n.(p + n/2^scale) < 0 where p is
    the ship's position in its own frame; the normal tip is the face's foot)."""
    import random
    rnd = random.Random(seed)
    out = []
    sc = 2 ** s['scale']
    nf = len(s['faces'])
    static = []
    for f, p in enumerate(s['polys']):
        for v in p:
            vf = set(s['verts'][v]['faces'])
            if s['verts'][v]['vis'] < 31:
                out.append(f'face {f}: vertex {v} has visibility distance {s["verts"][v]["vis"]} '
                           f'< 31 (not projected when XX4 > {s["verts"][v]["vis"]}, i.e. z >= '
                           f'{(s["verts"][v]["vis"] + 1) * 128})')
            if f in vf or 15 in vf:
                continue
            static.append((f, v, vf))
    for f, v, vf in static:
        bad = 0
        for _ in range(samples):
            # random direction, distance 1.5..20 x ship radius
            while True:
                d = (rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))
                if 0.01 < _dot(d, d) <= 1:
                    break
            r = rnd.uniform(1.5, 20) * 200
            pos = tuple(c * r / math.sqrt(_dot(d, d)) for c in d)

            def vis(g):
                n = s['faces'][g]['n']
                return _dot(n, tuple(pos[i] + n[i] / sc for i in range(3))) < 0
            if vis(f) and not any(g < nf and vis(g) for g in vf):
                bad += 1
        out.append(f'face {f}: vertex {v} lists faces {sorted(vf)} not {f}: '
                   f'{"STALE in %.1f%% of views where face %d is visible" % (100.0 * bad / samples, f) if bad else "never stale in sampling (a listed face is always visible with it)"}')
    return out


# ---------------------------------------------------------------------------
# A model of LL9 part 5's arithmetic, to find what XX2 holds

def _fm(a, q):
    return (a * q) >> 8


def _add(s1, m1, s2, m2):
    """LL38 on sign-magnitude bytes: returns (sign, mag, overflow)."""
    if s1 == s2:
        r = m1 + m2
        return s1, r & 255, r > 255
    if m1 >= m2:
        return s1, m1 - m2, False
    return s2, m2 - m1, False


def elite_xx2(s, pos, M):
    """XX2 values LL9 computes for ship s at view-space position pos (integers)
    with orientation rows M = (sidev, roofv, nosev) as unit vectors in view
    space.  Returns list of XX2 bytes (0 = hidden) and zn (z after the shifts)."""
    x, y, z = (abs(int(c)) for c in pos)
    sx, sy, sz = (c < 0 for c in pos)
    xx17 = s['scale']
    while z >> 8:
        xx17 += 1
        x >>= 1
        y >>= 1
        z >>= 1
    zn = z
    o = [[min(255, int(abs(M[r][c]) * 96 * 2 * 256 / 197 / 1)) for c in range(3)] for r in range(3)]
    p = []
    for r in range(3):
        acc_s, acc = False, 0
        for c, (m, sg) in enumerate(((x, sx), (y, sy), (z, sz))):
            t = _fm(m, o[r][c])
            acc_s, acc, _ = _add(acc_s, acc, sg ^ (M[r][c] < 0), t)
        p.append((acc_s, acc))
    out = []
    for face in s['faces']:
        n = face['n']
        ns = [c < 0 for c in n]
        nm = [abs(c) for c in n]
        pp = list(p)
        if xx17 >= 4:
            X = pp
        else:
            sh = xx17
            while True:
                nn = [m >> sh for m in nm]
                X, ovf = [], False
                for i in range(3):
                    sg, m, o_ = _add(ns[i], nn[i], pp[i][0], pp[i][1])
                    ovf |= o_
                    X.append((sg, m))
                if not ovf:
                    break
                pp = [(sg, m >> 1) for sg, m in pp]
                sh = 1
        acc_s, acc = False, 0
        for i in range(3):
            t = _fm(X[i][1], nm[i])
            acc_s, acc, _ = _add(acc_s, acc, X[i][0] ^ ns[i], t)
        out.append(acc if acc_s else 0)
    return out, zn


# ---------------------------------------------------------------------------
# Colours

import sys as _sys
import random as _random
from itertools import permutations as _perms, product as _product, combinations as _combs
_sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import swatch35 as SW                                   # noqa: E402

# Ships are not lit: every face has a fixed colour, drawn from two contrasting
# hue ramps per ship (swatch35 numbers, dark to light).
RAMPS = {
    'red':    [29, 23, 12],
    'gold':   [28, 21, 10, 11],
    'cyan':   [25, 15, 0, 1],
    'blue':   [27, 17, 5, 2],
    'green':  [26, 16, 18, 3, 6],
    'purple': [30, 20, 9, 5],
    'pink':   [24, 14, 13, 23, 8],
    'tan':    [29, 22, 7, 11],
    'grey':   [27, 19, 4, 7],
}
# per type: (primary hue A, secondary hue B)
SHIP_HUES = {
    1: ('pink', 'gold'),         # Missile
    2: ('grey', 'gold'),         # Coriolis station
    3: ('grey', 'red'),          # Escape pod
    4: ('grey', 'tan'),          # Alloy plate
    5: ('gold', 'cyan'),         # Cargo canister
    6: ('tan', 'grey'),          # Boulder
    7: ('tan', 'grey'),          # Asteroid
    8: ('tan', 'grey'),          # Splinter
    9: ('blue', 'gold'),         # Shuttle
    10: ('cyan', 'tan'),         # Transporter
    11: ('tan', 'blue'),         # Cobra Mk III
    12: ('purple', 'tan'),       # Python
    13: ('green', 'grey'),       # Boa
    14: ('blue', 'green'),       # Anaconda
    15: ('tan', 'grey'),         # Rock hermit
    16: ('cyan', 'blue'),        # Viper (police)
    17: ('red', 'gold'),         # Sidewinder
    18: ('green', 'gold'),       # Mamba
    19: ('red', 'purple'),       # Krait
    20: ('gold', 'blue'),        # Adder
    21: ('green', 'red'),        # Gecko
    22: ('blue', 'pink'),        # Cobra Mk I
    23: ('pink', 'green'),       # Worm
    24: ('pink', 'grey'),        # Cobra Mk III (pirate)
    25: ('purple', 'cyan'),      # Asp Mk II
    26: ('red', 'tan'),          # Python (pirate)
    27: ('gold', 'purple'),      # Fer-de-lance
    28: ('cyan', 'pink'),        # Moray
    29: ('green', 'purple'),     # Thargoid
    30: ('green', 'purple'),     # Thargon
    31: ('red', 'grey'),         # Constrictor
    32: ('purple', 'grey'),      # Cougar
    33: ('grey', 'blue'),        # Dodecahedron station
}
SUN_SWATCH, PLANET_SWATCH = 11, 17     # the old (sun ramp level 6), (planet level 4)
BLACK = 34
INK_BYTE = {SW.K: 0x00, SW.C: 0x0F, SW.M: 0xF0, SW.Y: 0xFF}
INK_SWATCH = {SW.K: 34, SW.C: 0, SW.M: 14, SW.Y: 10}


def dither_bytes(n):
    """(even-row byte, odd-row byte) of swatch35.ALL[n]: MODE 1 pixel p of a byte
    (x = 4c + p, so x AND 1 = p AND 1) takes the ink at (p AND 1, row AND 1);
    colour v sets bit 7-p to v bit 1 and bit 3-p to v bit 0."""
    cl = SW.cell(*SW.ALL[n])
    out = []
    for row in (0, 1):
        b = 0
        for p in range(4):
            v = cl[(p & 1, row)]
            b |= ((v >> 1) & 1) << (7 - p) | (v & 1) << (3 - p)
        out.append(b)
    return tuple(out)


def _lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _lab(li):
    r, g, b = li
    X = 0.4124 * r + 0.3576 * g + 0.1805 * b
    Y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    Z = 0.0193 * r + 0.1192 * g + 0.9505 * b

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(X / 0.9505), f(Y), f(Z / 1.089)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def swatch_lab(n):
    cl = SW.cell(*SW.ALL[n])
    li = [sum(_lin(SW.PHYS[v][ch]) for v in cl.values()) / 4 for ch in range(3)]
    return _lab(li)


def dE(a, b):
    return math.dist(swatch_lab(a), swatch_lab(b))


# ---------------------------------------------------------------------------
# Structure: polygon parts, surface details, fins, lines

def _newell(V, loop):
    nw = [0.0, 0.0, 0.0]
    for i in range(len(loop)):
        a, b = V[loop[i]], V[loop[(i + 1) % len(loop)]]
        nw[0] += (a[1] - b[1]) * (a[2] + b[2])
        nw[1] += (a[2] - b[2]) * (a[0] + b[0])
        nw[2] += (a[0] - b[0]) * (a[1] + b[1])
    return tuple(nw)


def _on_segment(P, A, B):
    d = _sub(B, A)
    w = _sub(P, A)
    c = _cross(d, w)
    if _dot(c, c) > 1e-6:
        return False
    t = _dot(w, d) / _dot(d, d)
    return -1e-9 <= t <= 1 + 1e-9


def _sides(poly):
    return [frozenset((poly[i], poly[(i + 1) % len(poly)])) for i in range(len(poly))]


def structure(s):
    """From s['polys'] and s['detail'] build:
      s['nodes']: the coloured polygon parts, node f = face f's polygon;
      s['dets']: surface items drawn over a face after the faces:
        {'kind': 'poly'|'line', 'faces': (f1, f2), 'vis', 'verts'};
      s['fins']: zero-thickness fins {'faces': (A, B), 'vis', 'verts'};
      s['adj']: set of frozenset node pairs sharing a polygon side;
      s['notes2']: what was done with each detail."""
    V = [_vec(v) for v in s['verts']]
    E = s['edges']
    nf = len(s['faces'])
    polys = [list(p) for p in s['polys']]
    nodes = [{'poly': polys[f], 'face': f} for f in range(nf)]
    dets, fins, notes = [], [], []
    # the rest: connected components of detail edges
    rest = list(s['detail'])
    comp = {}
    for i in rest:
        comp[i] = i

    def find(i):
        while comp[i] != i:
            i = comp[i]
        return i
    for i in rest:
        for j in rest:
            if i < j and {E[i]['v1'], E[i]['v2']} & {E[j]['v1'], E[j]['v2']}:
                comp[find(j)] = find(i)
    groups = defaultdict(list)
    for i in rest:
        groups[find(i)].append(i)
    for g in sorted(groups.values()):
        adj = defaultdict(list)
        for i in g:
            adj[E[i]['v1']].append(E[i]['v2'])
            adj[E[i]['v2']].append(E[i]['v1'])
        deg = {v: len(a) for v, a in adj.items()}
        evis = min(E[i]['vis'] for i in g)
        fs = {E[i]['f1'] for i in g} | {E[i]['f2'] for i in g}
        if all(d == 2 for d in deg.values()) and len(fs) == 1:
            # closed loop on one face
            f = fs.pop()
            loop = [E[g[0]]['v1']]
            prev = None
            while True:
                nxt = [w for w in adj[loop[-1]] if w != prev and (len(loop) < 2 or w != loop[-2])]
                prev = loop[-1]
                w = nxt[0]
                if w == loop[0]:
                    break
                loop.append(w)
            # clockwise about the face normal (as the face polygons)
            if _dot(_newell(V, loop), s['faces'][f]['n']) > 0:
                loop = loop[::-1]
            vis = min([evis] + [s['verts'][v]['vis'] for v in loop])
            stale = [v for v in loop if not (f in s['verts'][v]['faces'] or 15 in s['verts'][v]['faces'])]
            if stale:
                # LL9 may not project these vertices when face f is visible:
                # drop the detail rather than fill from stale coordinates
                notes.append(
                    f'detail loop {loop} on face {f}: vertices {stale} do not list face {f}: dropped')
                continue
            dets.append({'kind': 'poly', 'faces': (f, f), 'vis': vis, 'verts': loop})
            notes.append('edges %s: closed loop %s on face %d -> filled polygon (drawn when XX4 <= %d)'
                         % (g, loop, f, vis))
            continue
        ends = [v for v, d in deg.items() if d == 1]
        # chain: a fin if both ends are on one body edge (polygon side)
        fin = None
        if len(ends) != 2 or any(d > 2 for d in deg.values()):
            ends = []
        for f, p in enumerate(polys):
            for i in range(len(p)):
                a, b = V[p[i]], V[p[(i + 1) % len(p)]]
                if ends and all(_on_segment(V[v], a, b) for v in ends):
                    other = [h for h, q in enumerate(polys) if h != f and
                             all(any(_on_segment(V[v], V[q[k]], V[q[(k + 1) % len(q)]])
                                     for k in range(len(q))) for v in ends)]
                    fin = (f, other[0] if other else f)
        if fin:
            chain = [ends[0]]
            while chain[-1] != ends[1]:
                chain.append([w for w in adj[chain[-1]] if w not in chain][0])
            vis = min([evis] + [s['verts'][v]['vis'] for v in chain])
            A, B = sorted(fin)
            # LL9 projects a fin vertex when one of the faces it lists is
            # visible: every one must list A or B (the fin is drawn when one
            # of them is). The frame layer draws no fin with neither visible
            # (behind the body): a vertex that lists no other face is then
            # not projected (the missile's, on the body's edge)
            assert all({A, B} & set(s['verts'][v]['faces']) for v in chain), (chain, A, B)
            alone = [v for v in chain if set(s['verts'][v]['faces']) <= {A, B}]
            fins.append({'faces': (A, B), 'vis': vis, 'verts': chain})
            notes.append('edges %s: fin %s standing on the edge between faces %d and %d -> '
                         'two-sided filled triangle, drawn when face %d or %d is visible%s'
                         % (g, chain, A, B, A, B, ' (vertex %s lists only those faces)' % alone if alone else ''))
            continue
        for i in g:
            e = E[i]
            dets.append({'kind': 'line', 'faces': (e['f1'], e['f2']), 'vis': e['vis'],
                         'verts': [e['v1'], e['v2']]})
        notes.append('edges %s: %s -> kept as line%s'
                     % (g, 'not a closed loop on one face, not a fin' if ends or len(fs) == 1 else
                        'a loop across faces %s (fold lines of non-planar quads)' % sorted(fs),
                        's' if len(g) > 1 else ''))
    # adjacency between polygon parts
    side = defaultdict(set)
    for k, nd in enumerate(nodes):
        if nd['poly']:
            for sd in _sides(nd['poly']):
                side[sd].add(k)
    adjs = set()
    for sd, ks in side.items():
        for a, b in _combs(sorted(ks), 2):
            adjs.add(frozenset((a, b)))
    s['nodes'], s['dets'], s['fins'], s['adj'], s['notes2'] = nodes, dets, fins, adjs, notes
    return s


# ---------------------------------------------------------------------------
# Symmetry

AXN = 'xyz'


def _symname(perm, sg):
    out = []
    for k in range(3):
        out.append(('-' if sg[k] < 0 else '') + AXN[perm[k]])
    return '(x,y,z)->(%s)' % ','.join(out)


def symmetries(s):
    """Every signed axis permutation mapping the ship onto itself: all vertices,
    and the polygon parts, details and fins onto ones of the same kind.
    Returns [(name, vertex map, node map)], the identity first."""
    V = [_vec(v) for v in s['verts']]
    idx = {}
    for i, v in enumerate(V):
        idx.setdefault(v, i)
    nkey = {frozenset(nd['poly']): k for k, nd in enumerate(s['nodes']) if nd['poly']}
    dets = s['dets']
    dkey = {(d['kind'], frozenset(d['verts'])) for d in dets}
    fkey = {frozenset(d['verts']) for d in s['fins']}
    out = []
    for perm in _perms(range(3)):
        for sg in _product((1, -1), repeat=3):
            vm = []
            for v in V:
                w = tuple(sg[k] * v[perm[k]] for k in range(3))
                if w not in idx:
                    break
                vm.append(idx[w])
            else:
                nm = {}
                ok = True
                for k, nd in enumerate(s['nodes']):
                    if nd['poly']:
                        img = frozenset(vm[v] for v in nd['poly'])
                        if img not in nkey:
                            ok = False
                            break
                        nm[k] = nkey[img]
                    else:
                        nm[k] = k
                ok = ok and all((d['kind'], frozenset(vm[v] for v in d['verts'])) in dkey for d in dets)
                ok = ok and all(frozenset(vm[v] for v in d['verts']) in fkey for d in s['fins'])
                if ok:
                    out.append((_symname(perm, sg), vm, nm))
    out.sort(key=lambda g: g[0] != '(x,y,z)->(x,y,z)')
    return out


def _compose(a, b):
    return tuple(a[x] for x in b)


def subgroups(G):
    """All subgroups of G (a list of node maps as tuples), as sets of indices."""
    maps = [tuple(g[1]) for g in G]
    index = {m: i for i, m in enumerate(maps)}
    seen = set()
    out = []
    n = len(G)
    for r in range(0, min(n, 4) + 1):
        for gens in _combs(range(1, n), r):
            H = {0}
            frontier = list(gens)
            H |= set(gens)
            changed = True
            while changed:
                changed = False
                for a in list(H):
                    for b in list(H):
                        c = index.get(_compose(maps[a], maps[b]))
                        if c is None:
                            continue
                        if c not in H:
                            H.add(c)
                            changed = True
            key = frozenset(H)
            if key not in seen:
                seen.add(key)
                out.append(key)
    return out


def orbits(nodes_n, G, H):
    par = list(range(nodes_n))

    def find(i):
        while par[i] != i:
            i = par[i]
        return i
    for h in H:
        for k, im in G[h][2].items():
            par[find(im)] = find(k)
    out = defaultdict(list)
    for k in range(nodes_n):
        out[find(k)].append(k)
    return sorted(out.values())


def choose_symmetry(s):
    """H: the largest subgroup of the symmetry group G under which no polygon part
    maps to one it shares a side with (so an H-invariant colouring can give
    adjacent parts different colours); among equals, prefer one containing the
    x -> -x mirror, then y -> -y.  The rest of G is honoured softly."""
    G = symmetries(s)
    nn = len(s['nodes'])
    best = None
    for H in subgroups(G):
        orb = orbits(nn, G, H)
        bad = any(frozenset((a, b)) in s['adj'] for o in orb for a, b in _combs(o, 2))
        if bad:
            continue
        names = {G[h][0] for h in H}
        key = (len(H), '(x,y,z)->(-x,y,z)' in names, '(x,y,z)->(x,-y,z)' in names)
        if best is None or key > best[0]:
            best = (key, H)
    return G, best[1]


# ---------------------------------------------------------------------------
# Colouring

LIGHT = _unit((0.0, 1.0, 0.7))
DE_MIN = 14.0


def _area(V, poly):
    return math.sqrt(_dot(_newell(V, poly), _newell(V, poly))) / 2 if len(poly) >= 3 else 0.0


def colour_ship(t, s, seed=1, iters=40000):
    """Fixed colour (swatch number) per polygon part: s['col'][node]."""
    V = [_vec(v) for v in s['verts']]
    G, H = choose_symmetry(s)
    nn = len(s['nodes'])
    orb = orbits(nn, G, H)
    of = {}
    for i, o in enumerate(orb):
        for k in o:
            of[k] = i
    hA, hB = SHIP_HUES[t]
    pal = [(0, c) for c in RAMPS[hA]] + [(1, c) for c in RAMPS[hB]]
    # soft symmetry pairs (node pairs that G \ H would like coloured alike)
    soft_same, soft_adj = set(), set()
    for gi, (name, vm, nm) in enumerate(G):
        if gi in H:
            continue
        for k, im in nm.items():
            if of[k] == of[im]:
                continue
            pr = frozenset((of[k], of[im]))
            if frozenset((k, im)) in s['adj']:
                soft_adj.add(pr)
            else:
                soft_same.add(pr)
    soft_same -= soft_adj
    oadj = defaultdict(int)
    for pr in s['adj']:
        a, b = tuple(pr)
        oadj[frozenset((of[a], of[b]))] += 1
    area = [sum(_area(V, s['nodes'][k]['poly']) for k in o) for o in orb]
    tot = sum(area) or 1
    nrm = []
    for o in orb:
        nd = s['nodes'][o[0]]
        nrm.append(_unit(s['faces'][nd['face']]['n']))
    ncol = len(pal)
    lab = [swatch_lab(c) for _, c in pal]
    D = [[math.dist(lab[i], lab[j]) for j in range(ncol)] for i in range(ncol)]
    no = len(orb)

    def score(x):
        sc = 0.0
        for pr, cnt in oadj.items():
            a, b = tuple(pr)
            ca, cb = x[a], x[b]
            d = D[ca][cb]
            if d < DE_MIN:
                sc += 1000 + 50 * (DE_MIN - d)
            samehue = pal[ca][0] == pal[cb][0]
            if pr in soft_adj:
                sc += (0 if samehue else 14) + 0.25 * max(0, d - DE_MIN)
            else:
                sc += cnt * ((9 if samehue else 0) - 0.12 * min(d, 50))
        for pr in soft_same:
            a, b = tuple(pr)
            if x[a] != x[b]:
                sc += 30
        sc -= 3.0 * len(set(x))
        bshare = 0.0
        for i in range(no):
            L = lab[x[i]][0]
            Lt = 70 + 22 * _dot(nrm[i], LIGHT)
            sc += 0.004 * (L - Lt) ** 2 * area[i] / tot * no
            if pal[x[i]][0] == 1:
                bshare += area[i] / tot
        if bshare > 0.5:
            sc += 40 * (bshare - 0.5)
        return sc
    rnd = _random.Random(seed * 1000 + t)
    best = None
    for restart in range(6):
        x = [rnd.randrange(ncol) for _ in range(no)]
        cur = score(x)
        T = 30.0
        for it in range(iters // 6):
            i = rnd.randrange(no)
            old = x[i]
            x[i] = rnd.randrange(ncol)
            new = score(x)
            if new <= cur or rnd.random() < math.exp((cur - new) / T):
                cur = new
            else:
                x[i] = old
            T = max(0.05, T * 0.9993)
        if best is None or cur < best[0]:
            best = (cur, list(x))
    x = best[1]
    col = [None] * nn
    fam = [None] * nn
    for i, o in enumerate(orb):
        for k in o:
            col[k] = pal[x[i]][1]
            fam[k] = (hA, hB)[pal[x[i]][0]]
    s['col'] = col
    s['fam'] = fam                     # each part's hue family (its lighting ramp)
    s['pal'] = pal
    s['G'], s['H'] = G, H
    s['soft_adj'] = [(orb[a], orb[b]) for a, b in (tuple(p) for p in soft_adj)]
    # details: polygons in the colour (of the ship's two ramps or black) that
    # contrasts most with their face
    cands = sorted(set(RAMPS[hA] + RAMPS[hB] + ([BLACK] if t in (2, 33) else [])))   # black: the docking slot (the only
    # polygon detail with colour byte &80, which gfx-frame_cold.asm's f_poly2 outlines)
    for d in s['dets']:
        f = d['faces'][0]
        if d['kind'] == 'poly':
            d['col'] = max(cands, key=lambda c: (dE(c, col[f]), -c))
        else:
            fc = [col[g] for g in set(d['faces'])]
            d['col'] = max((INK_SWATCH[k] for k in (SW.C, SW.M, SW.Y)),
                           key=lambda c: (min(dE(c, q) for q in fc), -c))
    fcands = sorted(set(RAMPS[hA] + RAMPS[hB]))
    for d in s['fins']:
        fc = [col[g] for g in d['faces']]
        d['col'] = max(fcands, key=lambda c: (min(dE(c, q) for q in fc), -c))
    s['dot'] = RAMPS[hA][-2]
    return s


def check_colours(t, s):
    """Assertions + a report of the symmetry and adjacency decisions."""
    out = []
    G, H = s['G'], s['H']
    col = s['col']
    out.append('symmetry group: %s' % ', '.join(g[0] for g in G[1:]) if len(G) > 1 else
               'symmetry group: identity only')
    out.append('honoured exactly: %s' % (', '.join(G[h][0] for h in sorted(H) if h) or 'identity only'))
    for pr in s['adj']:
        a, b = tuple(pr)
        assert col[a] != col[b], (s['name'], a, b)
        assert dE(col[a], col[b]) >= DE_MIN - 1e-6, (s['name'], a, b)
    hue = {c: h for h, c in reversed(s['pal'])}
    samehue = sorted(tuple(sorted(p)) for p in s['adj'] if hue[col[tuple(p)[0]]] == hue[col[tuple(p)[1]]])
    softpairs = set()
    for gi, (name, vm, nm) in enumerate(G):
        if gi in H:
            continue
        for k, im in nm.items():
            if k < im and col[k] != col[im]:
                if frozenset((k, im)) in s['adj']:
                    softpairs.add((k, im, name, 'adjacent across the mirror/rotation: same hue, '
                                   'different shade' if hue[col[k]] == hue[col[im]] else
                                   'adjacent: different hues'))
                else:
                    softpairs.add((k, im, name, 'NOT adjacent but coloured differently'))
    for k, im, name, what in sorted(softpairs):
        out.append('  %s: parts %d/%d (%d, %d) %s' % (name, k, im, col[k], col[im], what))
    other = [p for p in samehue if not any({p[0], p[1]} == {k, im} for k, im, _, _ in softpairs)]
    if other:
        out.append('  adjacent parts in the same hue (other than the above): %s' % other)
    return out


# ---------------------------------------------------------------------------
# Output

def _equb(vals, per=16):
    out = []
    for i in range(0, len(vals), per):
        out.append(' EQUB ' + ', '.join('&%02X' % v for v in vals[i:i + per]))
    return out


def slot_vis(s):
    """The unlit (black) polygon details, the stations' docking slots, which
    gfx-frame_cold.asm's f_poly2 fills and outlines: drawn as long as Elite
    draws any of their edges. The loop is rotated so that its first side is
    the edge Elite draws furthest out (with both ends projected), and 'vis'
    becomes that distance; 'fillvis' is the least visibility of its vertices
    (all projected: fill and outline), and beyond it f_poly2 draws only the
    side from vertex 0 to vertex 1. (The Dodo's slot: vertices 22 and 23 go
    at XX4 > 23 and its edges 31 and 33 at XX4 > 20, but edge 30, 20-21,
    stays to XX4 = 30.)"""
    for d in s['dets']:
        if d['kind'] != 'poly' or d.get('fam') or d['col'] != BLACK:
            continue
        loop = d['verts']
        n = len(loop)
        vv = [s['verts'][v]['vis'] for v in loop]
        best, bk = -1, 0
        for k in range(n):
            a, b = loop[k], loop[(k + 1) % n]
            ev = [e['vis'] for e in s['edges'] if {e['v1'], e['v2']} == {a, b}]
            sc = min(ev + [vv[k], vv[(k + 1) % n]])
            if sc > best:
                best, bk = sc, k
        d['verts'] = loop[bk:] + loop[:bk]
        d['fillvis'] = min(vv)
        d['vis'] = max(best, d['fillvis'])


# The colouring's seed, by type, where 1 is not used: the Adder's back (faces 6
# to 8, one polygon since the back was filled) changed the search's outcome to
# the same colouring with its two hues swapped; seed 2 finds the colouring the
# Adder had before, with the back in gold.
COLOUR_SEED = {20: 2}


def prepare(ships):
    for t, s in ships:
        reconstruct(s)
        structure(s)
        colour_ship(t, s, seed=COLOUR_SEED.get(t, 1))
        slot_vis(s)
    return ships


def emit(ships, path):
    import lightramps as LR
    L = []
    nbytes = 0

    def eb(vals, per=16):
        nonlocal nbytes
        nbytes += len(vals)
        L.extend(_equb(vals, per))
    L += ['\\ gfx-faces.asm -- generated by faces.py (see docs/renderer.md); do not edit.',
          '\\',
          '\\ Filled faces, surface details, fins and colours for Master Elite\'s 33',
          '\\ ship types.  Faces are flat-shaded (lightramps.py).  Per-type',
          '\\ pointer tables have an entry for every type 0..33 (type 0 is a dummy).',
          '\\',
          '\\ FC_FACETAB -> per face f, in blueprint order: n + 16 * its hue ramp (0..8',
          '\\   in the shared pool, gfx-light6.asm), its unit normal (x, y, z: signed',
          '\\   bytes of magnitude 61; the lighting picks the ramp entry), then n XX3',
          '\\   offsets (4 * vertex).  Polygons are',
          '\\   convex and CLOCKWISE ON SCREEN (x right, y down) when the face is',
          '\\   front-facing, for every orientation with det -1, i.e. as set by ZINF',
          '\\   and kept by TIDY (sidev = nosev x roofv).  The station (NWSPS negates',
          '\\   the planet\'s nosev) is mirrored, det +1, until its first TIDY: so do',
          '\\   not rely on winding for it.  n < 3: do not fill.',
          '\\ FC_DETTAB -> nfins, nfins fins, then ndet, ndet details; each item is',
          '\\   visibility distance, face1 + 16 * face2, colour byte (a hue ramp, lit',
          '\\   at the brighter of face1\'s and face2\'s levels, or &80 + k, unlit',
          '\\   black, cyan, magenta or yellow), n, then n XX3 offsets.  Draw only',
          '\\   when XX4 <= visibility.',
          '\\   Details (n = 2: a line, n >= 3: a polygon on face1 = face2) are drawn',
          '\\   over the faces when XX2[face1] or XX2[face2] is non-zero (a polygon',
          '\\   with XX2 = 255: cull by its winding, as its face).',
          '\\   Fins (n = 3, two-sided, zero thickness, standing on the body edge',
          '\\   between face1 and face2): k = number of face1, face2 visible; draw',
          '\\   k = 1 after the details, then k = 2 (the fin nearest the viewer)',
          '\\   last; not k = 0 (behind the body: LL9 does not project a vertex on',
          '\\   the body edge that lists only face1 and face2).',
          '\\   An unlit polygon detail (the docking slots: black) has 4 * its fill',
          '\\   visibility added to its colour byte: if XX4 > that, some vertices',
          '\\   are unprojected, and f_poly2 draws only its side from vertex 0 to 1.',
          '\\ FC_MINVIS[type]: if XX4 > it, a polygon vertex may not have been',
          '\\   projected (vertex visibility distance < XX4): do not fill that ship.',
          '\\ FC_DOTE/FC_DOTO[type]: colour of the ship drawn as a distant dot.',
          '']
    L.append('FC_NTYPES = %d' % NTYPES)
    se, so = dither_bytes(SUN_SWATCH)
    pe, po = dither_bytes(PLANET_SWATCH)
    L.append('FC_SUNE = &%02X : FC_SUNO = &%02X' % (se, so))
    L.append('FC_PLANE = &%02X : FC_PLANO = &%02X' % (pe, po))
    L.append('')
    for name, tag in (('FACETAB', 'F'), ('DETTAB', 'D')):
        L.append('.FC_%s' % name)
        L.append('%-30s\\ type 0: unused' % ' EQUW 0')
        nbytes += 2
        for t, s in ships:
            L.append(('%-30s' % (' EQUW FC_S%d_%s' % (t, tag))) + '\\ type %d: %s' % (t, s['name']))
            nbytes += 2
        L.append('')
    for t, s in ships:
        L.append('\\ %s (type %d): hues %s + %s' % ((s['name'], t) + SHIP_HUES[t]))
        L.append('.FC_S%d_F' % t)
        for f in range(len(s['faces'])):
            p = s['nodes'][f]['poly']
            c = LR.hue_byte(s['fam'][f])
            nx, ny, nz = s['n63'][f]
            assert len(p) < 16
            vals = [len(p) + 16 * c, nx & 255, ny & 255, nz & 255] + [4 * v for v in p]
            nbytes += len(vals)
            L.append(' EQUB %d + 16 * %d, %d AND &FF, %d AND &FF, %d AND &FF%s    \\ face %d: %s' % (
                len(p), c, nx, ny, nz, ''.join(', %d' % (4 * v) for v in p), f, s['fam'][f]))
        L.append('.FC_S%d_D' % t)

        def item(d, what):
            nonlocal nbytes
            if d.get('kind') == 'line' or not d.get('fam'):
                c = LR.fixed_byte(d['col'])
                if 'fillvis' in d:
                    c |= d['fillvis'] << 2      # (f_col reads bits 0-1 only)
            else:
                c = LR.hue_byte(d['fam'])
            f1, f2 = d['faces']
            vals = [d['vis'], f1 | f2 << 4, c, len(d['verts'])] + [4 * v for v in d['verts']]
            nbytes += len(vals)
            L.append(' EQUB %d, &%02X, &%02X, %d%s    \\ %s %s, %s' % (
                d['vis'], f1 | f2 << 4, c, len(d['verts']),
                ''.join(', %d' % (4 * v) for v in d['verts']), what, d['verts'],
                d.get('fam') or ('unlit %d' % d['col'])))
        L.append(' EQUB %d                       \\ fins' % len(s['fins']))
        nbytes += 1
        for d in s['fins']:
            item(d, 'fin')
        L.append(' EQUB %d                       \\ details' % len(s['dets']))
        nbytes += 1
        for d in s['dets']:
            item(d, d['kind'])
        L.append('')
    L.append('.FC_MINVIS                     \\ by type: least visibility distance of any polygon vertex;')
    L.append('                              \\ if XX4 > this, some polygon vertex may be unprojected (stale)')
    mv = [31] + [min([s['verts'][v]['vis'] for p in s['polys'] for v in p] + [31]) for t, s in ships]
    eb(mv)
    dots = [dither_bytes(BLACK)] + [dither_bytes(s['dot']) for t, s in ships]
    L.append('.FC_DOTE                      \\ by type: distant-dot colour, even rows')
    eb([e for e, o in dots])
    L.append('.FC_DOTO                      \\ odd rows')
    eb([o for e, o in dots])
    L.append('')
    L.append('\\ %d bytes in all' % nbytes)
    open(path, 'w').write('\n'.join(L) + '\n')
    return nbytes


def report(ships):
    out = []
    for t, s in ships:
        out.append('%d %s: hues %s + %s' % ((t, s['name']) + SHIP_HUES[t]))
        for n in s['notes']:
            out.append('   ' + n)
        for n in s['notes2']:
            out.append('   ' + n)
        for n in check_colours(t, s):
            out.append('   ' + n)
        out.append('   parts: ' + ' '.join('%d:%d' % (k, c) for k, c in enumerate(s['col'])))
        for n in check_projection(s):
            if 'visibility distance' not in n:
                out.append('   ' + n)
    return out


def main():
    import lightramps as LR
    ships = prepare(load_ships())
    for t, s in ships:
        LR.annotate(t, s)
    n = emit(ships, os.path.join(SRC, 'gfx-faces.asm'))
    LR.emit_light(os.path.join(SRC, 'gfx-light6.asm'))
    print('\n'.join(report(ships)))
    print('gfx-faces.asm: %d bytes of tables' % n)


if __name__ == '__main__':
    main()
