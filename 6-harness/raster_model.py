#!/usr/bin/env python3
"""Soak test for src/raster.asm against a pixel-exact Python reference.

(The Demonstration Disc port's test of its rasteriser, which this port's
rasteriser descends from: its pixel-exact model, machine and tests.
6-harness/test_raster.py runs them on the port's rasteriser, with the port's
memory layout.)

Assembles a wrapper that INCLUDEs raster.asm (at a deliberately odd ORG), runs it
in py65's 65C02 with a flat 64K memory and compares every routine with the model
below.  Also checks that nothing outside the screen window, the module, the
renderer's zero page (&06-&27) and the stack page is ever written, and reports
cycle counts.

    python3 tools/test_raster.py [--seed N] [--quick] [--org HEX] [--cycles]
"""
import argparse
import math
import os
import random
import re
import subprocess
import sys
import tempfile

from py65.devices.mpu65c02 import MPU

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BEEBASM = os.environ.get('BEEBASM', 'beebasm')
SRC = os.path.join(ROOT, 'src', 'raster.asm')
SCR0, SCR1 = 0x4000, 0x7000
RET = 0xFFF0                       # sentinel return address

ZP = dict(R_COLE=0x06, R_COLO=0x07, R_XL=0x08, R_XR=0x09, R_CL=0x0A, R_CR=0x0B,
          R_CT=0x0C, R_CB=0x0D, R_DCE=0x0E, R_DCO=0x0F)


# ----------------------------------------------------------------------------- build
VARS = 0xC000                      # raster_vars.asm (HAZEL in the real build)
SRCV = os.path.join(ROOT, 'src', 'raster_vars.asm')
SRCH = os.path.join(ROOT, 'src', 'raster_hz.asm')
SRC7 = os.path.join(ROOT, 'src', 'raster7.asm')
HZ = 0xDC00                        # raster_hz.asm (HAZEL code in the real build)
ROMSEL, ROMSELCOPY = 0xFE30, 0xF4
EXTRA = []                         # (name, Tester method, count, (args)): run after the rest


def assemble(org):
    base = os.path.join(ROOT, 'scratch', 'raster')
    d = tempfile.mkdtemp(prefix='raster_', dir=base if os.path.isdir(base) else None)
    w = os.path.join(d, 'w.asm')
    with open(w, 'w') as f:
        f.write('ORG &%X\nINCLUDE "%s"\n.r_vars_end\n' % (VARS, SRCV))
        f.write('ORG &%X\nINCLUDE "%s"\n.r_hz_end\n' % (HZ, SRCH))
        f.write('ORG &%X\nINCLUDE "%s"\n' % (org, SRC))
        f.write('SAVE "r.bin", &%X, P%%\n' % org)
        f.write('CLEAR &8000, &C000\nORG &8000\nINCLUDE "%s"\nSAVE "r7.bin", &8000, P%%\n' % SRC7)
        f.write('SAVE "h.bin", &%X, r_hz_end\n' % HZ)
    r = subprocess.run([BEEBASM, '-i', w, '-d', '-labels', os.path.join(d, 'w.lab')],
                       cwd=d, capture_output=True, text=True)
    if r.returncode != 0 or 'error' in r.stdout.lower():
        print(r.stdout, r.stderr)
        raise SystemExit('assembly failed')
    txt = open(os.path.join(d, 'w.lab')).read()
    syms = {k: int(v) for k, v in re.findall(r"'([^']+)':(-?\d+)L?", txt)}
    data = open(os.path.join(d, 'r.bin'), 'rb').read()
    data7 = open(os.path.join(d, 'r7.bin'), 'rb').read()
    datah = open(os.path.join(d, 'h.bin'), 'rb').read()
    msg = [l for l in r.stdout.splitlines() if l.startswith('raster')]
    import shutil
    shutil.rmtree(d, ignore_errors=True)
    return syms, (data, data7, datah), ('; '.join(msg))


def check_patch_sites():
    """Every instruction naming buffer-0 state must be a listed patch site."""
    src = open(SRC).read().splitlines()
    names = ('r_dl', 'r_dr', 'r_sl', 'r_sr', 'r_s0y', 'r_s0x', 'r_s0a', 'r_s0b')
    sites, listed = set(), set(re.findall(r'(r_pt\d+)\+2', open(SRC).read()))
    bad = []
    for ln in src:
        code = ln.split('\\')[0]
        m = re.match(r'\s*(\.\^?(r_pt\d+))?\s*([A-Z]{3})\s+([^ ;]+)', code)
        if not m:
            continue
        opnd = m.group(4)
        base = re.split(r'[,+\-]', opnd)[0]
        if base in names:
            if 'nopatch' in ln:
                continue
            if not m.group(2):
                bad.append(ln.strip())
            else:
                sites.add(m.group(2))
    missing = sites - listed
    assert not bad, 'unpatched buffer references: %s' % bad
    assert not missing, 'patch sites not in R_SETBUF: %s' % missing
    # each site must be patched with its own array's high byte
    txt = open(SRC).read()
    use = dict(re.findall(r'\.\^?(r_pt\d+)\s+[A-Z]{3}\s+(r_\w+)', txt))
    grp = None
    for ln in txt[txt.index('.R_SETBUF'):].splitlines():
        m = re.search(r'group (r_\w+)', ln)
        if m:
            grp = m.group(1)
        m = re.match(r'\s*STA (r_pt\d+)\+2', ln)
        if m:
            assert use[m.group(1)] == grp, 'site %s patched as %s' % (m.group(1), grp)
        if ln.startswith('}'):
            break
    return len(sites)


# ----------------------------------------------------------------------------- machine
class Machine:
    def __init__(self, org, seed=1):
        self.syms, (data, data7, datah), self.sizemsg = assemble(org)
        self.org = org
        self.mem = [0] * 65536
        rnd = random.Random(seed)
        for a in range(65536):
            self.mem[a] = rnd.randrange(256)
        self.mem[self.org:self.org + len(data)] = list(data)
        self.mem[HZ:HZ + len(datah)] = list(datah)
        b7 = [rnd.randrange(256) for _ in range(0x4000)]
        b7[0:len(data7)] = list(data7)
        self.banks = {5: None, 7: b7}
        self.bank = 5
        self.mem[ROMSEL] = 5
        self.mem[ROMSELCOPY] = 5
        self.lo, self.hi = self.syms['r_start'], self.syms['r_end']
        self.image = list(data)
        self.mpu = MPU(memory=self.mem)
        self.cycles = 0
        self.guard = True

    def s(self, name):
        return self.syms[name]

    def call(self, name, a=0, x=0, y=0, maxcyc=20_000_000):
        mpu, mem = self.mpu, self.mem
        if self.guard:
            snap = mem[:]
        mpu.a, mpu.x, mpu.y = a, x, y
        mpu.p = 0x24
        mpu.sp = 0xFF
        ret = RET - 1
        mem[0x1FF] = ret >> 8
        mem[0x1FE] = ret & 0xFF
        mpu.sp = 0xFD
        mpu.pc = self.syms[name] if isinstance(name, str) else name
        c0 = mpu.processorCycles
        step = mpu.step
        banks = self.banks
        while mpu.pc != RET:
            step()
            nb = mem[ROMSEL]
            if nb != self.bank:             # sideways bank switch
                banks[self.bank] = mem[0x8000:0xC000]
                mem[0x8000:0xC000] = banks[nb]
                self.bank = nb
            if mpu.processorCycles - c0 > maxcyc:
                raise RuntimeError('runaway in %s' % name)
        if self.bank != 5:
            raise AssertionError('%s returned with bank %d paged' % (name, self.bank))
        self.cycles = mpu.processorCycles - c0
        if self.guard:
            self.check_writes(snap, name)
        return self.cycles

    def check_writes(self, snap, name):
        mem = self.mem
        v0, v1 = VARS, self.syms['r_vars_end']
        h0, h1 = HZ, self.syms['r_hz_end']
        for lo, hi in ((0, 0x06), (0x28, ROMSELCOPY), (ROMSELCOPY + 1, 0x100), (0x200, 0x4000),
                       (0x7000, self.lo), (self.hi, v0), (v1, h0), (h1, ROMSEL), (ROMSEL + 1, 0x10000)):
            if mem[lo:hi] != snap[lo:hi]:
                for a in range(lo, hi):
                    if mem[a] != snap[a]:
                        raise AssertionError('%s wrote &%04X' % (name, a))
        # module code outside the variable/table areas must be restored (the runs)
        w0 = self.syms.get('r_wcrun')
        if w0 is not None and mem[w0:w0 + 3 * 193 + 1] != snap[w0:w0 + 3 * 193 + 1]:
            raise AssertionError('%s left r_wcrun modified' % name)
        r0 = self.syms['r_run0']
        for r in range(24):
            base = r0 + 256 * r
            if mem[base:base + 190] != snap[base:base + 190]:
                raise AssertionError('%s left run %d modified' % (name, r))

    # memory helpers
    def wr(self, name, val, off=0):
        a = (self.syms[name] if isinstance(name, str) else name) + off
        self.mem[a] = val & 0xFF

    def rd(self, name, off=0):
        a = (self.syms[name] if isinstance(name, str) else name) + off
        return self.mem[a]

    def wzp(self, name, val):
        self.mem[ZP[name]] = val & 0xFF

    def screen(self):
        return bytes(self.mem[SCR0:SCR1])

    def clearall(self):
        """Black the clip window of the current buffer and reset its state: the
        rasteriser's R_CLEARALL where it has one (the demo's), else its effect done
        here (the Master port dropped R_CLEARALL, which nothing in the game called):
        the window blacked, R_RESETBUF, R_WL/R_WR = the window on its rows, R_PRWT /
        R_PRWB widened to it.  Returns R_RESETBUF's (or R_CLEARALL's) cycles."""
        if 'R_CLEARALL' in self.syms:
            return self.call('R_CLEARALL')
        mem = self.mem
        cl, cr, ct, cb = (mem[ZP[k]] for k in ('R_CL', 'R_CR', 'R_CT', 'R_CB'))
        r = Ref(self.screen(), (cl, cr, ct, cb))
        r.blackwin()
        self.set_screen(bytes(r.b))
        c = self.call('R_RESETBUF')
        for y in range(ct, cb + 1):
            self.wr('R_WL', cl, y)
            self.wr('R_WR', cr, y)
        if ct < self.rd('R_PRWT'):
            self.wr('R_PRWT', ct)
        if cb >= self.rd('R_PRWB'):
            self.wr('R_PRWB', cb)
        return c

    def set_screen(self, b):
        self.mem[SCR0:SCR1] = list(b)


# ----------------------------------------------------------------------------- reference
def addr(x, y):
    return (y >> 3) * 0x200 + (y & 7) + 8 * (x >> 2)


class Ref:
    """A screen (bytes &4000-&6FFF) and the reference drawing operations."""

    def __init__(self, scr, clip):
        self.b = bytearray(scr)
        self.cl, self.cr, self.ct, self.cb = clip

    def inwin(self, x, y):
        return self.cl <= x <= self.cr and self.ct <= y <= self.cb

    def setpix(self, x, y, ce, co):
        c = co if y & 1 else ce
        m = 0x88 >> (x & 3)
        a = addr(x, y)
        self.b[a] = (self.b[a] & ~m & 0xFF) | (c & m)

    def getpix(self, x, y):
        v = self.b[addr(x, y)]
        p = x & 3
        return (((v >> (7 - p)) & 1) << 1) | ((v >> (3 - p)) & 1)

    def span(self, y, xl, xr, ce, co):
        for x in range(xl, xr + 1):
            self.setpix(x, y, ce, co)

    def blackwin(self):
        for y in range(self.ct, self.cb + 1):
            self.span(y, self.cl, self.cr, 0, 0)


def cdiv(a, b):
    return -((-a) // b)


def poly_spans(verts, clip):
    """{y: (xl, xr)} of a convex polygon under the top-left / pixel-centre rule."""
    cl, cr, ct, cb = clip
    out = {}
    n = len(verts)
    ys = [v[1] for v in verts]
    for y in range(max(ct, min(ys)), min(cb, max(ys) - 1) + 1):
        xs = []
        for i in range(n):
            (x0, y0), (x1, y1) = verts[i], verts[(i + 1) % n]
            if y0 == y1:
                continue
            if y0 > y1:
                x0, y0, x1, y1 = x1, y1, x0, y0
            if y0 <= y < y1:
                xs.append(x0 + cdiv((x1 - x0) * (y - y0), y1 - y0))
        if len(xs) < 2:
            continue
        l, r = max(min(xs), cl), min(max(xs), cr + 1) - 1
        if l <= r:
            out[y] = (l, r)
    return out


def line_pixels(x0, y0, x1, y1):
    dx, dy = x1 - x0, y1 - y0
    if dx == 0 and dy == 0:
        return [(x0, y0)]
    pts = []
    if abs(dx) >= abs(dy):
        if dx < 0:
            x0, y0, x1, y1 = x1, y1, x0, y0
            dx, dy = -dx, -dy
        s = 1 if dy > 0 else -1 if dy < 0 else 0
        a = abs(dy)
        for i in range(dx + 1):
            pts.append((x0 + i, y0 + s * ((2 * i * a + dx) // (2 * dx))))
    else:
        if dy < 0:
            x0, y0, x1, y1 = x1, y1, x0, y0
            dx, dy = -dx, -dy
        s = 1 if dx > 0 else -1 if dx < 0 else 0
        a = abs(dx)
        for i in range(dy + 1):
            pts.append((x0 + s * ((2 * i * a + dy) // (2 * dy)), y0 + i))
    return pts


def dot_pixels(x, y, s):
    pts = [(x, y)]
    if s >= 2:
        pts.append((x + 1, y))
    if s == 3:
        pts += [(x, y + 1), (x + 1, y + 1)]
    return [(px, py) for px, py in pts if px <= 255 and py <= 255]


def star_ref(ref, x, y, s, scol):
    """A star: per row, per byte, its in-window pixels are set to scol only
    if all of them are black."""
    rows = [y] + ([y + 1] if s == 3 and y < 255 else [])
    xs = [x] + ([x + 1] if s >= 2 and x < 255 else [])
    for py in rows:
        if not (ref.ct <= py <= ref.cb):
            continue
        byts = {}
        for px in xs:
            if ref.cl <= px <= ref.cr:
                byts.setdefault(px >> 2, []).append(px)
        for c, pxs in byts.items():
            if all(ref.getpix(px, py) == 0 for px in pxs):
                for px in pxs:
                    ref.setpix(px, py, scol, scol)


# ----------------------------------------------------------------------------- shapes
def convex_hull(pts):
    pts = sorted(set(pts))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def random_poly(rnd, kind=None):
    kind = kind or rnd.choice(['small', 'small', 'screen', 'big', 'huge', 'edge', 'tiny', 'degen'])
    if kind == 'degen':
        t = rnd.randrange(4)
        if t == 0:      # collinear
            x0, y0 = rnd.randrange(-50, 300), rnd.randrange(-50, 250)
            dx, dy = rnd.randrange(-5, 6), rnd.randrange(-5, 6)
            vs = [(x0 + k * dx, y0 + k * dy) for k in rnd.sample(range(-20, 20), rnd.randrange(2, 8))]
        elif t == 1:    # single row
            y = rnd.randrange(-2, 194)
            vs = [(rnd.randrange(-100, 400), y) for _ in range(rnd.randrange(2, 6))]
        elif t == 2:    # all one point
            p = (rnd.randrange(0, 256), rnd.randrange(0, 192))
            vs = [p] * rnd.randrange(1, 5)
        else:           # thin sliver
            x0, y0 = rnd.randrange(0, 256), rnd.randrange(0, 192)
            vs = [(x0, y0), (x0 + rnd.randrange(-300, 300), y0 + rnd.randrange(-300, 300)),
                  (x0 + rnd.randrange(-1, 2), y0 + rnd.randrange(-1, 2))]
        return vs
    if kind == 'tiny':
        cx, cy, r = rnd.randrange(0, 256), rnd.randrange(0, 192), 3
    elif kind == 'small':
        cx, cy, r = rnd.randrange(0, 256), rnd.randrange(0, 192), rnd.randrange(3, 30)
    elif kind == 'screen':
        cx, cy, r = rnd.randrange(30, 220), rnd.randrange(30, 160), rnd.randrange(20, 120)
    elif kind == 'edge':
        cx, cy, r = rnd.choice([0, 255, rnd.randrange(256)]), rnd.choice([0, 191, rnd.randrange(192)]), rnd.randrange(5, 80)
    elif kind == 'big':
        cx, cy, r = rnd.randrange(-300, 550), rnd.randrange(-300, 500), rnd.randrange(100, 800)
    else:
        cx, cy, r = rnd.randrange(-3000, 3000), rnd.randrange(-3000, 3000), rnd.randrange(500, 6000)
    pts = []
    for _ in range(rnd.randrange(3, 24)):
        a = rnd.random() * 2 * math.pi
        rr = r * (0.3 + 0.7 * rnd.random())
        pts.append((int(round(cx + rr * math.cos(a))), int(round(cy + rr * math.sin(a)))))
    hull = convex_hull(pts)[:16]
    hull = convex_hull(hull)
    if len(hull) < 3:
        return random_poly(rnd, kind)
    if rnd.random() < 0.5:
        hull = hull[::-1]
    k = rnd.randrange(len(hull))
    hull = hull[k:] + hull[:k]
    return [(max(-16384, min(16383, x)), max(-16384, min(16383, y))) for x, y in hull]


def fan_mesh(rnd):
    """Triangles tiling a convex polygon exactly (a fan from an interior point,
    each triangle possibly split again at an interior point)."""
    big = rnd.random() < 0.3
    while True:
        P = random_poly(rnd, 'huge' if big else 'screen')
        if len(P) >= 3:
            break
    def inside(q):
        sg = [(b[0] - a[0]) * (q[1] - a[1]) - (b[1] - a[1]) * (q[0] - a[0])
              for a, b in zip(P, P[1:] + P[:1])]
        return all(v > 0 for v in sg) or all(v < 0 for v in sg)
    cx = sum(p[0] for p in P) // len(P)
    cy = sum(p[1] for p in P) // len(P)
    if not inside((cx, cy)):            # thin polygon: the rounded centroid
        return fan_mesh(rnd)            # may fall outside; take another
    tris = []
    for i in range(len(P)):
        t = [(cx, cy), P[i], P[(i + 1) % len(P)]]
        tris.append(t)
    out = []
    for t in tris:
        a, b, c = t
        if rnd.random() < 0.5:
            # split at an interior lattice point if one exists near the centroid
            m = ((a[0] + b[0] + c[0]) // 3, (a[1] + b[1] + c[1]) // 3)

            def side(p, q, r):
                return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
            s1, s2, s3 = side(a, b, m), side(b, c, m), side(c, a, m)
            if (s1 > 0 and s2 > 0 and s3 > 0) or (s1 < 0 and s2 < 0 and s3 < 0):
                out += [[a, b, m], [b, c, m], [c, a, m]]
                continue
        out.append(t)
    res = []
    for t in out:
        if rnd.random() < 0.5:
            t = t[::-1]
        k = rnd.randrange(3)
        res.append(t[k:] + t[:k])
    return P, res


def polyhedron_mesh(rnd):
    """Front faces of a random convex polyhedron, perspective-projected to
    integer screen points; returns (silhouette points, faces)."""
    import numpy as np
    n = rnd.randrange(5, 14)
    pts = []
    for _ in range(n):
        v = np.array([rnd.gauss(0, 1) for _ in range(3)])
        pts.append(v / np.linalg.norm(v))
    pts = np.array(pts)
    # faces of the hull: brute force over triples
    faces = []
    for i in range(n):
        for j in range(i + 1, n):
            for k in range(j + 1, n):
                nrm = np.cross(pts[j] - pts[i], pts[k] - pts[i])
                if np.linalg.norm(nrm) < 1e-9:
                    continue
                d = np.dot(pts) if False else (pts - pts[i]) @ nrm
                if np.all(d <= 1e-9):
                    faces.append((i, j, k))
                elif np.all(d >= -1e-9):
                    faces.append((i, k, j))
    # random rotation, push away from camera
    q = np.linalg.qr(np.array([[rnd.gauss(0, 1) for _ in range(3)] for _ in range(3)]))[0]
    pw = pts @ q.T
    dist = rnd.uniform(2.0, 6.0)
    scale = rnd.uniform(100, 900)
    cx, cy = rnd.uniform(-100, 356), rnd.uniform(-100, 292)
    proj = []
    for p in pw:
        z = p[2] + dist
        proj.append((int(round(cx + scale * p[0] / z)), int(round(cy + scale * p[1] / z))))
    front = []
    for (i, j, k) in faces:
        a, b, c = proj[i], proj[j], proj[k]
        area = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        if area > 0:
            front.append([a, b, c])
    return proj, front


# ----------------------------------------------------------------------------- driver
class Tester:
    def __init__(self, m, rnd):
        self.m, self.rnd = m, rnd
        self.clip = (1, 254, 1, 191)
        self.stats = {}

    def set_clip(self, clip):
        self.clip = clip
        for n, v in zip(('R_CL', 'R_CR', 'R_CT', 'R_CB'), clip):
            self.m.wzp(n, v)

    def set_col(self, ce, co):
        self.m.wzp('R_COLE', ce)
        self.m.wzp('R_COLO', co)

    def stat(self, k, v):
        self.stats.setdefault(k, []).append(v)

    def dirty(self, b):
        m = self.m
        dl = m.s('R_DIRTYL0') + 0x300 * b
        dr = m.s('R_DIRTYR0') + 0x300 * b
        return [(m.mem[dl + y], m.mem[dr + y]) for y in range(192)]

    def draw_poly(self, verts, ce, co):
        m = self.m
        n = len(verts)
        m.wr('R_PN', n)
        for i, (x, y) in enumerate(verts[:16]):
            m.wr('R_PXL', x & 0xFF, i)
            m.wr('R_PXH', (x >> 8) & 0xFF, i)
            m.wr('R_PYL', y & 0xFF, i)
            m.wr('R_PYH', (y >> 8) & 0xFF, i)
        self.set_col(ce, co)
        return m.call('R_POLY')

    def draw_line(self, x0, y0, x1, y1, ce, co, entry='R_LINE'):
        m = self.m
        for nm, v in (('R_X0', x0), ('R_Y0', y0), ('R_X1', x1), ('R_Y1', y1)):
            m.wr(nm, v & 0xFF)
            m.wr(nm, (v >> 8) & 0xFF, 1)
        self.set_col(ce, co)
        return m.call(entry)

    # --------------------------------------------------------------- span test
    def test_spans(self, n):
        m, rnd = self.m, self.rnd
        self.set_clip((1, 254, 1, 191))
        for it in range(n):
            scr = bytes(rnd.randrange(256) for _ in range(0x3000)) if it % 50 == 0 else m.screen()
            m.set_screen(scr)
            ref = Ref(scr, self.clip)
            y = rnd.randrange(0, 192)
            xl = rnd.randrange(1, 255)
            xr = rnd.randrange(xl, 255) if rnd.random() < 0.7 else min(254, xl + rnd.randrange(0, 9))
            ce, co = rnd.randrange(256), rnd.randrange(256)
            self.set_col(ce, co)
            m.wzp('R_XL', xl)
            m.wzp('R_XR', xr)
            cyc = m.call('R_SPAN', y=y)
            self.stat('span', (xr - xl + 1, cyc))
            ref.span(y, xl, xr, ce, co)
            if m.screen() != bytes(ref.b):
                raise AssertionError('span y=%d %d..%d' % (y, xl, xr))

    # --------------------------------------------------------------- polygons
    def poly_case(self, verts, ref, b, dirt):
        ce, co = self.rnd.randrange(256), self.rnd.randrange(256)
        cyc = self.draw_poly(verts, ce, co)
        sp = poly_spans(verts, self.clip)
        for y, (l, r) in sp.items():
            ref.span(y, l, r, ce, co)
            dl, dr = dirt[y]
            dirt[y] = (min(dl, l), max(dr, r))
        if self.m.screen() != bytes(ref.b):
            diff = [i for i in range(0x3000) if self.m.screen()[i] != ref.b[i]]
            raise AssertionError('poly %s: %d bytes differ, first %04X' % (verts, len(diff), diff[0]))
        if self.dirty(b) != dirt:
            ys = [y for y in range(192) if self.dirty(b)[y] != dirt[y]]
            raise AssertionError('poly %s dirty differs rows %s' % (verts, ys[:5]))
        return cyc, sp

    def reset_state(self, b):
        """clear all (R_CLEARALL or its effect) on buffer b; returns the reference."""
        m = self.m
        m.call('R_SETBUF', a=b)
        m.clearall()
        ref = Ref(m.screen(), self.clip)
        dirt = [(255, 0)] * 192
        return ref, dirt

    def test_polys(self, n):
        m, rnd = self.m, self.rnd
        for it in range(n):
            if it % 40 == 0:
                if rnd.random() < 0.3:
                    cl = rnd.randrange(1, 100)
                    ct = rnd.randrange(0, 100)
                    self.set_clip((cl, rnd.randrange(cl, 255), ct, rnd.randrange(ct, 192)))
                else:
                    self.set_clip((1, 254, 1, 191))
                b = rnd.randrange(2)
                m.set_screen(bytes(rnd.randrange(256) for _ in range(0x3000)))
                ref, dirt = self.reset_state(b)
            verts = random_poly(rnd)
            cyc, sp = self.poly_case(verts, ref, b, dirt)
            if all(0 <= x <= 255 and 0 <= y <= 255 for x, y in verts):
                self.stat('poly8', (len(sp), sum(r - l + 1 for l, r in sp.values()), cyc))
            else:
                self.stat('poly16', (len(sp), sum(r - l + 1 for l, r in sp.values()), cyc))

    def test_meshes(self, n):
        m, rnd = self.m, self.rnd
        self.set_clip((1, 254, 1, 191))
        gaps = 0
        for it in range(n):
            ref, dirt = self.reset_state(rnd.randrange(2))
            if it % 2 == 0:
                outline, tris = fan_mesh(rnd)
            else:
                outline, tris = polyhedron_mesh(rnd)
                if not tris:
                    continue
                outline = convex_hull(outline)
            cover = {}
            for t in tris:
                _, sp = self.poly_case(t, ref, self.m.rd('R_PRBUF'), dirt)
                for y, (l, r) in sp.items():
                    for x in range(l, r + 1):
                        cover[(x, y)] = cover.get((x, y), 0) + 1
            over = sum(1 for v in cover.values() if v > 1)
            if it % 2 == 0:
                assert over == 0, 'fan mesh overlap %d pixels' % over
            else:
                # projected polyhedra: rounding the vertices can fold a face
                self.folds = getattr(self, 'folds', 0) + over
            if it % 2 == 0 and len(outline) >= 3:
                want = poly_spans(outline, self.clip)
                need = set((x, y) for y, (l, r) in want.items() for x in range(l, r + 1))
                missing = need - set(cover)
                extra = set(cover) - need
                assert not missing and not extra, 'fan mesh: %d gaps %d extra' % (len(missing), len(extra))
            else:
                # polyhedron: every pixel strictly inside the silhouette hull but
                # not on a projected edge must be covered
                want = poly_spans(outline, self.clip)
                need = set((x, y) for y, (l, r) in want.items() for x in range(l, r + 1))
                missing = need - set(cover)
                gaps += len(missing)
        return 'polyhedra: %d gap px, %d fold-overlap px' % (gaps, getattr(self, 'folds', 0))


    # --------------------------------------------------------------- lines, dots
    def test_lines(self, n):
        m, rnd = self.m, self.rnd
        b = 0
        for it in range(n):
            if it % 50 == 0:
                if rnd.random() < 0.3:
                    cl = rnd.randrange(1, 100)
                    ct = rnd.randrange(0, 100)
                    self.set_clip((cl, rnd.randrange(cl, 255), ct, rnd.randrange(ct, 192)))
                else:
                    self.set_clip((1, 254, 1, 191))
                b = rnd.randrange(2)
                m.set_screen(bytes(rnd.randrange(256) for _ in range(0x3000)))
                ref, dirt = self.reset_state(b)
            kind = rnd.random()
            if kind < 0.5:
                pts = [rnd.randrange(-20, 276), rnd.randrange(-20, 212), rnd.randrange(-20, 276), rnd.randrange(-20, 212)]
            elif kind < 0.8:
                x0, y0 = rnd.randrange(0, 256), rnd.randrange(0, 192)
                pts = [x0, y0, x0 + rnd.randrange(-12, 13), y0 + rnd.randrange(-12, 13)]
            else:
                pts = [rnd.randrange(-16000, 16000) for _ in range(4)]
            ce, co = rnd.randrange(256), rnd.randrange(256)
            cyc = self.draw_line(*pts, ce, co)
            npx = 0
            for x, y in line_pixels(*pts):
                if ref.inwin(x, y):
                    ref.setpix(x, y, ce, co)
                    dl, dr = dirt[y]
                    dirt[y] = (min(dl, x), max(dr, x))
                    npx += 1
            if kind >= 0.5 and kind < 0.8:
                self.stat('line', (max(abs(pts[2] - pts[0]), abs(pts[3] - pts[1])) + 1, npx, cyc))
            if m.screen() != bytes(ref.b):
                raise AssertionError('line %s' % pts)
            if self.dirty(b) != dirt:
                raise AssertionError('line dirty %s' % pts)
            # a dot now and then
            if rnd.random() < 0.3:
                x, y, s = rnd.randrange(256), rnd.randrange(256), rnd.randrange(1, 4)
                self.set_col(ce, co)
                cyc = m.call('R_DOT', a=s, x=x, y=y)
                self.stat('dot', (s, cyc))
                for px, py in dot_pixels(x, y, s):
                    if ref.inwin(px, py):
                        ref.setpix(px, py, ce, co)
                        dl, dr = dirt[py]
                        dirt[py] = (min(dl, px), max(dr, px))
                if m.screen() != bytes(ref.b):
                    raise AssertionError('dot %d,%d,%d' % (x, y, s))
                if self.dirty(b) != dirt:
                    raise AssertionError('dot dirty')

    # --------------------------------------------------------------- frames
    def test_frames(self, nframes, scenario=None):
        """Multi-frame sequences on two buffers: after each frame the buffer
        must equal [disc over black, polys, lines, dots, stars]."""
        m, rnd = self.m, self.rnd
        sc0 = scenario or ''
        # the game's window is 2..253 while discs may reach 1..254
        self.set_clip((2, 253, 1, 191) if sc0.startswith('band') and rnd.random() < 0.6 else (1, 254, 1, 191))
        bufs = [bytes(rnd.randrange(256) for _ in range(0x3000)) for _ in range(2)]
        outside = [None, None]
        use_reset = rnd.random() < 0.5
        reset_at = rnd.randrange(3, max(4, nframes)) if rnd.random() < 0.5 else -1

        def blackreset(b):
            r = Ref(bufs[b], self.clip)
            r.blackwin()
            m.set_screen(bytes(r.b))
            m.call('R_SETBUF', a=b)
            m.call('R_RESETBUF')
            return m.screen()
        for b in range(2):
            m.set_screen(bufs[b])
            m.call('R_SETBUF', a=b)
            if use_reset:
                bufs[b] = blackreset(b)
            else:
                m.clearall()
                bufs[b] = m.screen()
            outside[b] = bufs[b]
        sc = scenario or rnd.choice(['none', 'sun', 'planet', 'mixed', 'jumpy'])
        cx, cy, rad = rnd.uniform(0, 256), rnd.uniform(0, 192), rnd.uniform(5, 60)
        if sc == 'planet':
            rad = rnd.uniform(150, 250)
            cx, cy = rnd.uniform(60, 200), rnd.uniform(150, 300)
        vx, vy, vr = rnd.uniform(-2, 2), rnd.uniform(-2, 2), rnd.uniform(-0.5, 0.5)
        stars = [(rnd.randrange(256), rnd.randrange(192), rnd.randrange(1, 4)) for _ in range(rnd.randrange(0, 25))]
        ships = [(rnd.uniform(0, 256), rnd.uniform(0, 192), rnd.uniform(-3, 3), rnd.uniform(-3, 3)) for _ in range(rnd.randrange(0, 4))]
        dce, dco = rnd.randrange(256), rnd.randrange(256)
        dbe, dbo = rnd.randrange(256), rnd.randrange(256)
        bands = sc in ('bands', 'bandmix', 'bandjump')
        beach = sc == 'beachball'       # (the adapter's beach_rows: a rotating meridian planet)
        if beach:
            cx, cy, rad = rnd.uniform(20, 236), rnd.uniform(10, 180), rnd.uniform(6, 140)
            vx, vy, vr = rnd.uniform(-1.5, 1.5), rnd.uniform(-1.5, 1.5), rnd.uniform(-0.6, 0.6)
        if bands:
            cx, cy, rad = rnd.uniform(40, 216), rnd.uniform(30, 160), rnd.uniform(20, 110)
            vx, vy, vr = rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.3, 0.3)
        if sc == 'bandjump':    # a small two-colour disc moving fast (a crater planet
            rad = rnd.uniform(8, 40)        # as the view turns): narrow rows whose old
            vx, vy = rnd.uniform(-30, 30), rnd.uniform(-20, 20)    # and new spans are apart
            vr = rnd.uniform(-1, 1)
        def newcurve():
            return [rnd.uniform(-rad, rad), rnd.uniform(-1.5, 1.5), rnd.uniform(-rad, rad), rnd.uniform(-rad, rad)]
        curves = [newcurve() for _ in range(rnd.randrange(0, 5))]
        eq = rnd.uniform(-rad, rad)
        drawn_cols = [None, None]
        oldstars = [set(), set()]
        m.wr('R_NDF', 0)
        for f in range(nframes):
            b = f & 1
            if f == reset_at:       # e.g. leaving direct drawing: both black, state reset
                for bb in range(2):
                    bufs[bb] = blackreset(bb)
            m.set_screen(bufs[b])
            m.call('R_SETBUF', a=b)
            m.wr('R_SCOL', rnd.choice([0xFF, 0xFF, 0x0F, 0xF0]))
            scol = m.rd('R_SCOL')
            cyc_e = m.call('R_STARERASE')
            # disc
            if sc == 'jumpy':
                cx, cy, rad = rnd.uniform(-50, 300), rnd.uniform(-50, 250), rnd.uniform(0, 120)
            has_disc = sc != 'none' and (sc != 'mixed' or (f // 7) % 2 == 0)
            spans = {}
            if has_disc and beach:      # the game's disc: the integer circle the
                ir = max(6, min(250, int(rad)))     # meridian window is given (the
                for y in range(max(int(cy) - ir, 1), min(int(cy) + ir, 191) + 1):   # frame
                    h = math.isqrt(ir * ir - (y - int(cy)) ** 2)   # layer's half-widths)
                    l, r = max(int(cx) - h, 1), min(int(cx) + h, 254)
                    if l <= r:
                        spans[y] = (l, r)
            elif has_disc:
                for y in range(0, 192):
                    dy = y + 0.5 - cy
                    if abs(dy) < rad:
                        h = math.sqrt(rad * rad - dy * dy)
                        l, r = int(math.floor(cx - h)), int(math.floor(cx + h))
                        l, r = max(l, 1), min(r, 254)
                        if l <= r and 1 <= y <= 191:
                            spans[y] = (l, r)
            if spans:
                ndt, ndb = min(spans), max(spans)
            else:
                ndt, ndb = 255, 0
            m.wr('R_NDT', ndt)
            m.wr('R_NDB', ndb)
            for y in range(ndt, ndb + 1) if spans else []:
                l, r = spans.get(y, (255, 0))
                m.wr('R_NDISCL', l, y)
                m.wr('R_NDISCR', r, y)
            bnd = {}
            ndf = 0
            if beach:
                if rnd.random() < 0.1:
                    dce, dco, dbe, dbo = (rnd.randrange(256) for _ in range(4))
                bnd, ndf = self.beach_rows(f, spans, cx, cy, rad)
            if bands:
                for c in curves:                    # drift, sometimes jump
                    c[0] += rnd.uniform(-2.5, 2.5)
                    if rnd.random() < 0.03:
                        c[:] = newcurve()
                if rnd.random() < 0.05 and curves:
                    curves.pop(rnd.randrange(len(curves)))
                if rnd.random() < 0.05 and len(curves) < 4:
                    curves.append(newcurve())
                eq += rnd.uniform(-1, 1)
                if rnd.random() < 0.1:
                    dce, dco, dbe, dbo = (rnd.randrange(256) for _ in range(4))
                ndf = 0 if (sc == 'bandmix' and (f // 5) % 3 == 2) else 1
                for y in range(ndt, ndb + 1) if spans else []:
                    xs = sorted(int(cx + c[0] + c[1] * (y - cy)) for c in curves
                                if min(c[2], c[3]) <= y - cy <= max(c[2], c[3]))
                    p_ = (1 if y > cy + eq else 0) ^ (1 if rnd.random() < 0.02 else 0)
                    l_, r_ = spans.get(y, (255, 0))
                    if l_ <= r_:            # the frame layer's guarantee: boundaries
                        p_ ^= sum(1 for v in xs if v <= l_) & 1     # inside (L, R],
                        xs = [v for v in xs if l_ < v <= r_]        # left crossings
                    else:                                           # folded into P
                        xs = []
                    bnd[y] = (xs, p_)
                    m.wr('R_NDN', len(xs), y)
                    m.wr('R_NDP', p_ | (rnd.randrange(128) << 1), y)
                    for i in range(4):
                        m.wr('R_NDX%d' % i, xs[i] if i < len(xs) else rnd.randrange(256), y)
                if not ndf:
                    bnd = {}
            m.wr('R_NDF', ndf)
            m.wr('R_DBE', dbe)
            m.wr('R_DBO', dbo)
            cols = (dce, dco, dbe, dbo)
            if drawn_cols[b] is not None and drawn_cols[b] != cols:
                # the caller's colour change: fold this buffer's old disc into dirty
                for y in range(192):
                    l = m.rd('R_DISCL0', y + 0x300 * b)
                    r = m.rd('R_DISCR0', y + 0x300 * b)
                    if l <= r:
                        m.wzp('R_XL', l)
                        m.wzp('R_XR', r)
                        m.call('R_MARKDIRTY', y=y)
            drawn_cols[b] = cols
            m.wzp('R_DCE', dce)
            m.wzp('R_DCO', dco)
            cyc_d = m.call('R_DISCROWS')
            self.stat('disc_' + sc, cyc_d)
            ref = Ref(outside[b], self.clip)
            ref.blackwin()
            for y, (l, r) in spans.items():
                l, r = max(l, self.clip[0]), min(r, self.clip[1])
                if y in bnd:
                    xs, p_ = bnd[y]
                    for x in range(l, r + 1):
                        c = p_ ^ (sum(1 for v in xs if v <= x) & 1)
                        ref.setpix(x, y, dbe if c else dce, dbo if c else dco)
                else:
                    ref.span(y, l, r, dce, dco)
            # WL/WR must cover every changed pixel so far
            wl = [(m.rd('R_WL', y), m.rd('R_WR', y)) for y in range(192)]
            wt, wb = m.rd('R_PRWT'), m.rd('R_PRWB')
            for y in range(192):
                if wl[y][1] and not wt <= y <= wb:
                    raise AssertionError('frame %d: R_WR[%d] set outside the WL rows %d..%d' % (f, y, wt, wb))
            # shapes
            newships = []
            for (sx, sy, svx, svy) in ships:
                sx, sy = sx + svx, sy + svy
                newships.append((sx, sy, svx, svy))
                for t in range(rnd.randrange(1, 4)):
                    vs = random_poly(rnd, 'small')
                    vs = [(x - vs[0][0] + int(sx), y - vs[0][1] + int(sy)) for x, y in vs]
                    ce, co = rnd.randrange(256), rnd.randrange(256)
                    self.draw_poly(vs, ce, co)
                    for y, (l, r) in poly_spans(vs, self.clip).items():
                        ref.span(y, l, r, ce, co)
            ships = newships
            if rnd.random() < 0.5:
                pts = [rnd.randrange(-20, 276), rnd.randrange(-20, 212), rnd.randrange(-20, 276), rnd.randrange(-20, 212)]
                ce, co = rnd.randrange(256), rnd.randrange(256)
                self.draw_line(*pts, ce, co)
                for x, y in line_pixels(*pts):
                    if ref.inwin(x, y):
                        ref.setpix(x, y, ce, co)
            lxpix = set()
            for _ in range(rnd.randrange(0, 4)):
                x, y, s = rnd.randrange(256), rnd.randrange(256), rnd.randrange(1, 4)
                ce, co = rnd.randrange(256), rnd.randrange(256)
                self.set_col(ce, co)
                m.call('R_DOT', a=s, x=x, y=y)
                for px, py in dot_pixels(x, y, s):
                    if ref.inwin(px, py):
                        ref.setpix(px, py, ce, co)
            # stars
            stars = [((x + rnd.randrange(-2, 3)) & 255, min(255, max(0, y + rnd.randrange(-2, 3))), s) for x, y, s in stars]
            m.wr('R_SN', len(stars))
            for i, (x, y, s) in enumerate(stars):
                m.wr('R_SX', x, i)
                m.wr('R_SY', y, i)
                m.wr('R_SS', s, i)
            cyc_p = m.call('R_STARPLOT')
            pre = bytes(ref.b)
            for x, y, s in stars:
                star_ref(ref, x, y, s, scol)
            starpix = set()
            for a in range(0x3000):
                if pre[a] != ref.b[a]:
                    for p in range(4):
                        if (pre[a] ^ ref.b[a]) & (0x88 >> p):
                            starpix.add((4 * ((a % 0x200) // 8) + p, (a // 0x200) * 8 + (a & 7)))
            got = m.screen()
            if got != bytes(ref.b):
                diff = [i for i in range(0x3000) if got[i] != ref.b[i]]
                a = diff[0]
                y = (a // 0x200) * 8 + (a & 7)
                rows = sorted(set((d // 0x200) * 8 + (d & 7) for d in diff))
                if os.environ.get('RDEBUG'):
                    ra = (y >> 3) * 0x200 + (y & 7)
                    print('got', ''.join('%02x' % got[ra + 8 * c] for c in range(64)))
                    print('exp', ''.join('%02x' % ref.b[ra + 8 * c] for c in range(64)))
                raise AssertionError('frame %d (%s, buf %d): %d bytes differ, first row %d col %d; rows %s'
                                     % (f, sc, b, len(diff), y, (a % 0x200) // 8, rows[:12]))
            # written-extent check: every byte that changed vs this buffer's last
            # frame lies in WL/WR (disc, star erase/plot) or DIRTY (shapes)
            old = bufs[b]
            dirt = self.dirty(b)
            wl2 = [(m.rd('R_WL', y), m.rd('R_WR', y)) for y in range(192)]
            for a in range(0x3000):
                if got[a] != old[a]:
                    y = (a // 0x200) * 8 + (a & 7)
                    c = (a % 0x200) // 8
                    for p in range(4):
                        x = 4 * c + p
                        mm = 0x88 >> p
                        if (got[a] ^ old[a]) & mm:
                            ok = (wl2[y][1] and wl2[y][0] <= x <= wl2[y][1]) or (dirt[y][0] <= x <= dirt[y][1]) \
                                or (x, y) in starpix or (x, y) in lxpix or (x, y) in oldstars[b]
                            if not ok:
                                raise AssertionError('frame %d: pixel %d,%d changed outside WL/DIRTY' % (f, x, y))
            bufs[b] = got
            oldstars[b] = starpix       # erased next time on this buffer (no WL/WR needed)
            self.stat('starerase', cyc_e)
            self.stat('starplot', (len(stars), cyc_p))
            # move the disc
            cx, cy, rad = cx + vx, cy + vy, max(0, rad + vr)
            if sc == 'bandjump' and not (-40 < cx < 296 and -40 < cy < 232):
                cx, cy = rnd.uniform(40, 216), rnd.uniform(30, 160)


def summarize(stats):
    out = []
    if 'span' in stats:
        bins = {}
        for w, c in stats['span']:
            k = (w // 32) * 32
            bins.setdefault(k, []).append(c - 12)
        out.append('R_SPAN (excl. JSR/RTS of the test call) cycles by width:')
        for k in sorted(bins):
            v = bins[k]
            out.append('  width %3d-%3d: mean %6.0f  min %4d  max %4d  (n=%d)' % (k, k + 31, sum(v) / len(v), min(v), max(v), len(v)))
        # least squares fit cyc = a + b*w for w >= 9
        pts = [(w, c - 12) for w, c in stats['span'] if w >= 9]
        if pts:
            n = len(pts)
            sx = sum(p[0] for p in pts); sy = sum(p[1] for p in pts)
            sxx = sum(p[0] ** 2 for p in pts); sxy = sum(p[0] * p[1] for p in pts)
            b = (n * sxy - sx * sy) / (n * sxx - sx * sx)
            a = (sy - b * sx) / n
            out.append('  fit (width >= 9): %.0f + %.2f * width pixels  (= %.2f per byte)' % (a, b, 4 * b))
        nar = [c - 12 for w, c in stats['span'] if w <= 4]
        if nar:
            out.append('  width <= 4: mean %.0f' % (sum(nar) / len(nar)))
    for k in ('poly8', 'poly16'):
        if k in stats:
            v = [s for s in stats[k] if s[0] > 0]
            if not v:
                continue
            out.append('R_POLY %s path: %d drawn polys' % ('8-bit' if k == 'poly8' else '16-bit', len(v)))
            for lo, hi in ((1, 8), (9, 24), (25, 64), (65, 192)):
                w = [s for s in v if lo <= s[0] <= hi]
                if w:
                    rows = sum(s[0] for s in w) / len(w)
                    px = sum(s[1] for s in w) / len(w)
                    cyc = sum(s[2] for s in w) / len(w)
                    out.append('  %3d-%3d rows: mean %5.1f rows %7.0f px  %7.0f cycles (%.0f/row)' % (lo, hi, rows, px, cyc, cyc / rows))
    if 'line' in stats:
        v = stats['line']
        tot = sum(s[2] for s in v); n = sum(s[0] for s in v)
        out.append('R_LINE short lines: mean %.0f cycles for mean %.1f pixels (%.0f/pixel incl. setup)'
                   % (tot / len(v), n / len(v), tot / max(1, n)))
    if 'dot' in stats:
        for s in (1, 2, 3):
            v = [c for z, c in stats['dot'] if z == s]
            if v:
                out.append('R_DOT size %d: mean %.0f cycles' % (s, sum(v) / len(v)))
    for k in sorted(stats):
        if k.startswith('disc_'):
            v = stats[k]
            out.append('R_DISCROWS %-7s: mean %6.0f  max %6d cycles (n=%d)' % (k[5:], sum(v) / len(v), max(v), len(v)))
    if 'starplot' in stats:
        v = stats['starplot']
        out.append('R_STARPLOT: mean %.0f cycles for mean %.1f stars' % (sum(c for _, c in v) / len(v), sum(n for n, _ in v) / len(v)))
        v = stats['starerase']
        out.append('R_STARERASE: mean %.0f cycles' % (sum(v) / len(v)))
    if 'linex' in stats:
        v = stats['linex']
        out.append('R_LINEX: mean %.0f cycles for mean %.1f pixels' % (sum(c for _, c in v) / len(v), sum(n for n, _ in v) / len(v)))
    return '\n'.join(out)


# ----------------------------------------------------------------------------- bench
def bench(m, rnd):
    """Cycle counts for representative cases (no checking; run the soak first)."""
    t = Tester(m, rnd)
    t.set_clip((1, 254, 1, 191))
    m.guard = False
    out = []
    m.call('R_SETBUF', a=0)
    m.clearall()
    # spans
    t.set_col(0x5A, 0xA5)
    for w in (1, 4, 8, 16, 32, 64, 128, 254):
        cs = []
        for xl in range(1, 255 - w + 1, 7):
            m.wzp('R_XL', xl)
            m.wzp('R_XR', xl + w - 1)
            cs.append(m.call('R_SPAN', y=rnd.randrange(192)) - 12)
        out.append('R_SPAN width %3d: %4.0f cycles (incl. row set-up; core r_spc is ~72 less)' % (w, sum(cs) / len(cs)))
    # polygons: triangles and quads of given height, 8-bit
    for h in (4, 8, 16, 32, 64, 128):
        for nv in (3, 4):
            cs, rows = [], []
            for k in range(40):
                cx, cy = rnd.randrange(h * 6 // 10 + 2, 254 - h * 6 // 10), rnd.randrange(h // 2 + 2, 190 - h // 2)
                ang = rnd.random() * 6.283
                vs = [(int(cx + h * 0.6 * math.cos(ang + 6.283 * i / nv)), int(cy + h * 0.5 * math.sin(ang + 6.283 * i / nv) * 1.0)) for i in range(nv)]
                vs = convex_hull(vs)
                if len(vs) < 3:
                    continue
                cs.append(t.draw_poly(vs, 0x5A, 0xA5))
                sp = poly_spans(vs, t.clip)
                rows.append((len(sp), sum(r - l + 1 for l, r in sp.values())))
            n = len(cs)
            out.append('R_POLY %d-gon ~%3d rows: %6.0f cycles  (mean %5.1f rows, %6.0f px; %4.0f/row)'
                       % (nv, h, sum(cs) / n, sum(r for r, _ in rows) / n, sum(p for _, p in rows) / n,
                          sum(cs) / max(1, sum(r for r, _ in rows))))
    # 16-bit polygon: a big one through the screen
    cs = []
    for k in range(20):
        vs = random_poly(rnd, 'huge')
        cs.append((t.draw_poly(vs, 0x5A, 0xA5), len(poly_spans(vs, t.clip))))
    cs = [c for c in cs if c[1]]
    out.append('R_POLY huge (16-bit, clipped): %6.0f cycles mean for %5.1f rows' % (sum(c for c, _ in cs) / len(cs), sum(r for _, r in cs) / len(cs)))
    # lines
    for L in (2, 10, 50, 150):
        cs = []
        for k in range(30):
            x0, y0 = rnd.randrange(20, 236), rnd.randrange(20, 172)
            a = rnd.random() * 6.283
            x1, y1 = int(x0 + L * math.cos(a)), int(y0 + L * math.sin(a))
            cs.append(t.draw_line(x0, y0, x1, y1, 0xFF, 0xFF))
        out.append('R_LINE length ~%3d (start on screen): %6.0f cycles' % (L, sum(cs) / len(cs)))
    for name, d in (('horizontal', (50, 0)), ('shallow 5:1', (50, 10)), ('diagonal', (50, 50)), ('vertical', (0, 50))):
        c0 = t.draw_line(100, 60, 100, 60, 0xFF, 0xFF)
        c = t.draw_line(100, 60, 100 + d[0], 60 + d[1], 0xFF, 0xFF)
        out.append('R_LINE %-11s 51 px: %5d cycles (%.0f per extra pixel; 1 px: %d)' % (name, c, (c - c0) / 50, c0))
    cs = []
    for k in range(30):
        cs.append(t.draw_line(rnd.randrange(-3000, -100), rnd.randrange(-3000, 3000), rnd.randrange(100, 200), rnd.randrange(50, 150), 0xFF, 0xFF))
    out.append('R_LINE from far off screen: %6.0f cycles' % (sum(cs) / len(cs)))
    # disc layer steady state
    def disc_frames(cx, cy, r, vx, vy, n=8, ships=0, bands=None, vr=0):
        res = []
        m.wr('R_NDF', 1 if bands else 0)
        m.wr('R_DBE', 0x33)
        m.wr('R_DBO', 0xCC)
        for b in range(2):
            m.call('R_SETBUF', a=b)
            m.clearall()
        for f in range(n):
            b = f & 1
            m.call('R_SETBUF', a=b)
            m.call('R_STARERASE')
            spans = {}
            if r > 0:
                for y in range(1, 192):
                    dy = y + 0.5 - cy
                    if abs(dy) < r:
                        h = math.sqrt(r * r - dy * dy)
                        l, rr = max(1, int(cx - h)), min(254, int(cx + h))
                        if l <= rr:
                            spans[y] = (l, rr)
            if spans:
                m.wr('R_NDT', min(spans)); m.wr('R_NDB', max(spans))
                for y in range(min(spans), max(spans) + 1):
                    l, rr = spans.get(y, (255, 0))
                    m.wr('R_NDISCL', l, y); m.wr('R_NDISCR', rr, y)
                    if bands:
                        xs = sorted(int(cx + o + f * bands) for o in (-r * 0.4, r * 0.3))
                        p_ = (1 if y > cy else 0) ^ (sum(1 for v in xs if v <= l) & 1)
                        xs = [v for v in xs if l < v <= rr]
                        m.wr('R_NDN', len(xs), y)
                        m.wr('R_NDP', p_, y)
                        for i, v in enumerate(xs):
                            m.wr('R_NDX%d' % i, v, y)
            else:
                m.wr('R_NDT', 255); m.wr('R_NDB', 0)
            m.wzp('R_DCE', 0x5A); m.wzp('R_DCO', 0xA5)
            res.append(m.call('R_DISCROWS'))
            for s in range(ships):
                x, y = 60 + 40 * s + f, 60 + 20 * s
                t.draw_poly([(x, y), (x + 30, y + 10), (x + 10, y + 25)], 0xFF, 0x0F)
            cx += vx
            cy += vy
            r += vr
        return res[4:]
    for name, args in (('no disc, nothing dirty', (0, 0, 0, 0, 0)),
                       ('no disc, 3 small ships moving', (0, 0, 0, 0, 0, 8, 3)),
                       ('sun r=40 moving 1px/frame', (128, 96, 40, 1, 0)),
                       ('sun r=40 static', (128, 96, 40, 0, 0)),
                       ('planet r=200 moving 1px/frame', (128, 260, 200, 1, -1)),
                       ('planet r=200 static', (128, 260, 200, 0, 0)),
                       ('planet r=200 + 3 ships', (128, 260, 200, 1, -1, 8, 3)),
                       ('planet r=80, 2 boundaries static', (128, 96, 80, 0, 0, 8, 0, 0)),
                       ('planet r=80, 2 bounds move 1px/fr', (128, 96, 80, 0, 0, 8, 0, 1)),
                       ('planet r=80, bounds+disc 1px/fr', (128, 96, 80, 1, 0, 8, 0, 1)),
                       ('planet r=80, bounds 1px, disc grows', (128, 96, 80, 0, 0, 8, 0, 1, 0.7))):
        v = disc_frames(*args)
        out.append('R_DISCROWS %-36s %6.0f cycles/frame' % (name + ':', sum(v) / len(v)))
    m.wr('R_NDF', 0)
    # stars
    m.call('R_SETBUF', a=0)
    m.clearall()
    m.wr('R_SN', 24)
    for i in range(24):
        m.wr('R_SX', rnd.randrange(256), i); m.wr('R_SY', rnd.randrange(192), i); m.wr('R_SS', rnd.randrange(1, 4), i)
    out.append('R_STARPLOT 24 stars (mixed sizes): %d cycles' % m.call('R_STARPLOT'))
    out.append('R_STARERASE 24 stars (mixed sizes): %d cycles' % m.call('R_STARERASE'))
    for sz in (1, 2, 3):
        for i in range(24):
            m.wr('R_SS', sz, i)
        m.call('R_DISCROWS')
        c = m.call('R_STARPLOT')
        e = m.call('R_STARERASE')
        out.append('  stars of size %d: plot %4.0f, erase %3.0f cycles per star' % (sz, c / 24, e / 24))
    out.append('R_RESETBUF: %d cycles' % m.call('R_RESETBUF'))
    out.append('R_SETBUF switch: %d cycles' % m.call('R_SETBUF', a=1))
    if 'R_CLEARALL' in m.syms:
        out.append('R_CLEARALL: %d cycles' % m.clearall())
    m.guard = True
    return '\n'.join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--quick', action='store_true')
    ap.add_argument('--org', default='8000')
    ap.add_argument('--only', default='')
    ap.add_argument('--bench', action='store_true')
    a = ap.parse_args()
    scale = 0.2 if a.quick else 1.0
    nsites = check_patch_sites()
    m = Machine(int(a.org, 16), a.seed)
    print(m.sizemsg.strip(), '; %d R_SETBUF patch sites' % nsites)
    rnd = random.Random(a.seed)
    m.call('R_INIT')
    t = Tester(m, rnd)
    only = a.only.split(',') if a.only else None
    if a.bench:
        print(bench(m, rnd))
        return

    def run(name, fn, *args):
        if only and name not in only:
            return
        r = fn(*args)
        print('%-8s ok%s' % (name, '' if r is None else ' (%s)' % r))
        sys.stdout.flush()
    run('spans', t.test_spans, int(3000 * scale))
    run('polys', t.test_polys, int(3000 * scale))
    run('meshes', t.test_meshes, int(60 * scale))
    run('lines', t.test_lines, int(2000 * scale))
    for sc in ('none', 'sun', 'planet', 'mixed', 'jumpy', 'bands', 'bandmix', 'bands'):
        run('frames', t.test_frames, int(40 * scale) + 4, sc)
    for k in range(6):          # regression: r_dpe's strips into the gap between
        run('bandjump', t.test_frames, int(40 * scale) + 4, 'bandjump')   # spans apart
    for name, fn, n, args in EXTRA:     # (tests an adapter adds: name, Tester method,
        run(name, getattr(t, fn), max(1, int(n * scale)), *args)   # count, more arguments)
    print(summarize(t.stats))


if __name__ == '__main__':
    main()
