#!/usr/bin/env python3
"""Soak test for the full Master port's rasteriser (1-source-files/main-sources/gfx-raster*.asm).

A thin adapter over the demo port's tools/test_raster.py (its pixel-exact Python
reference, py65 65C02, the write guard and every test), pointed at the Master files:

  * the wrapper assembles the renderer's shared workspace as elite-gfx.asm lays it
    out in main RAM (one block, from its first ORG to WS_END: gfx-raster_scr.asm, the
    per-call scratch, with R_NDISCL page aligned; gfx-raster_vars.asm at its fixed base, as the
    laser-sight rows must not cross a page; R_WL, R_WR, R_NDN, the stars), and the
    rasteriser as elite-gfx.asm does: bank 5 (gfx-raster.asm, the shared region, at
    &9000, then R_LINE's cold part gfx-raster_lcold.asm; gfx-raster_disc.asm, the disc
    window, at &8000) and ANDY (gfx-raster_poly.asm and gfx-raster_line.asm, the
    polygon window); while R_LINE was in bank 7 (gfx-raster7.asm), also bank 7 at
    R7START, and while there were no windows, bank 5 from &8000, the stubs
    gfx-raster_hz.asm at &DF00 and bank 7 from &8000; the machine
    pages as the Master does (ROMSEL bits 0-3 the bank, bit 7 ANDY), each entry point
    is called with its T_ trampoline's ROMSEL, and &F4 must match each ROMSEL write;
  * the write guard allows exactly those areas (plus the renderer's zero page, the
    stack and the screen, as before);
  * R_POLY's 4-row colour: every polygon is drawn with R_COL2 = R_COLE and
    R_COL3 = R_COLO, the 2-row colour pair the reference models (gfx-raster.asm's
    header: "set R_COL2 = R_COLE and R_COL3 = R_COLO for a 2-row colour pair").  The
    4-row dither itself is not checked here.

    python3 6-harness/test_raster.py [--seed N] [--quick] [--only x,y]

Run from anywhere; needs py65 and BeebAsm ($BEEBASM, or beebasm on the path).  Exit status 0 only if every
test passes.
"""
import os, re, subprocess, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import raster_model as tr                        # noqa: E402  (the model and its tests)

TREE = os.path.abspath(os.environ.get('GRIND_TREE', REPO))     # the tree whose rasteriser is tested
MS = os.path.join(TREE, '1-source-files', 'main-sources')
tr.SRC = os.path.join(MS, 'gfx-raster.asm')
tr.SRCV = os.path.join(MS, 'gfx-raster_vars.asm')
tr.SRC7 = os.path.join(MS, 'gfx-raster7.asm')
GFX = os.path.join(MS, 'elite-gfx.asm')
tr.HZ = 0xDF00


def gfx_constants():
    """elite-gfx.asm's constants (MCB, banks, sizes), defined before its first ORG or CLEAR"""
    out = ['HOMEBANK = 4']
    # the shared workspace's F_DSS is NDSTAR (elite-gfx.asm) long, from Elite's NOST
    # (elite-source.asm), and it ends at the main code's start, CODE% (WS_TOP)
    src = open(os.path.join(MS, 'elite-source.asm')).read()
    out.append('NOST = %s' % re.search(r'^\s*NOST\s*=\s*(\d+)', src, re.M).group(1))
    out.append('CODE%% = %s' % re.search(r'^\s*CODE%\s*=\s*(&[0-9A-Fa-f]+)', src, re.M).group(1))
    for l in open(GFX).read().split('\n'):
        if re.match(r'\s*(CLEAR|ORG)\b', l):         # (the workspace, ws_block, follows)
            break
        if re.match(r'^[A-Z_][A-Z0-9_]*\s*=', l):
            out.append(l)
    if not any(re.match(r'^NDSTAR\s*=', l) for l in out):
        out += [l for l in open(GFX).read().split('\n') if re.match(r'^NDSTAR\s*=', l)]
    return '\n'.join(out)


def ws_block():
    """elite-gfx.asm's shared workspace (after `NDSTAR =`, from its first ORG to
    .WS_END: one block, WS_START..WS_END), as text, with its INCLUDEs made absolute"""
    t = open(GFX).read().split('\n')
    i = next(n for n, l in enumerate(t) if re.match(r'^NDSTAR\s*=', l)) + 1
    out = []
    for l in t[i:]:
        out.append(l.replace('"1-source-files/main-sources/', '"%s/' % MS))
        if l.startswith('.WS_END'):
            break
    return '\n'.join(out)


def raster_files():
    """the rasteriser's bank 5 / ANDY sources (those that exist): the shared region
    and its two windows"""
    return [p for p in (os.path.join(MS, f) for f in ('gfx-raster.asm', 'gfx-raster_lcold.asm', 'gfx-raster_disc.asm',
                                                      'gfx-raster_poly.asm', 'gfx-raster_line.asm'))
            if os.path.exists(p)]


LINEA = os.path.join(MS, 'gfx-raster_line.asm')    # R_LINE in the polygon window (ANDY) ...
LINE5 = os.path.join(MS, 'gfx-raster_lcold.asm')   # ... and its cold part in the shared region
LINE7 = not os.path.exists(LINEA)                  # (before: R_LINE in bank 7, gfx-raster7.asm)


SRCH = os.path.join(MS, 'gfx-raster_hz.asm')       # (the bank 5 <-> 7 stubs, while they exist)
# the meridian window (gfx-merid.asm: bank 7 after the cold area; here at MTEST),
# with the game's symbols it reads: INWK, K3, K4 and MCNT at their places in
# Master Elite's zero page (K3 and K4 are in &10-&28, which PM_HOOK saves and
# uses: it must read them first), PM_OK, PM_R, PS_VALID below the workspace, the
# quarter squares at &7000 (after the test's screen)
MERID = os.path.join(MS, 'gfx-merid.asm')
MTEST = 0xA000
MG = dict(INWK=0x9C, K3=0x14, K4=0x22, PM_OK=0x0E00, PM_R=0x0E01, PS_VALID=0x0E02, MCNT=0x84, QSL=0x7000, QSH=0x7200)
MERID_GAME = ''.join('%s = &%04X\n' % kv for kv in MG.items())
DATAM = b''
WINDOWS = os.path.exists(os.path.join(MS, 'gfx-raster_poly.asm'))


def check_patch_sites():
    """the demo's check, over all three bank 5 / ANDY files (the polygon window's
    phase B operands are patched by R_SETBUF's r_sbpoly)"""
    base = os.path.join(REPO, '6-harness', 'work', 'raster')
    os.makedirs(base, exist_ok=True)
    cat = os.path.join(base, 'raster-all.asm')
    with open(cat, 'w') as f:
        f.write('\n'.join(open(p).read() for p in raster_files()))
    old, tr.SRC = tr.SRC, cat
    try:
        return _demo_check_patch_sites()
    finally:
        tr.SRC = old


def assemble(org):
    """as elite-gfx.asm lays the rasteriser out: bank 5 (the shared region from
    &9000 with R_LINE's cold part, the disc window at &8000), ANDY (the polygon
    window at &8000: R_POLY, R_LINE), or, before, bank 7 for R_LINE (from
    R7START).  (org is ignored: the layout is fixed.)"""
    base = os.path.join(REPO, '6-harness', 'work', 'raster')
    os.makedirs(base, exist_ok=True)
    d = tempfile.mkdtemp(prefix='mraster_', dir=base)
    w = os.path.join(d, 'w.asm')
    with open(w, 'w') as f:
        f.write(gfx_constants() + '\n')
        f.write(ws_block() + '\n')
        if WINDOWS:
            f.write('ORG &%X\n.r_hz_end\n' % tr.HZ)
            f.write('CLEAR &8000, &C000\nORG &9000\nINCLUDE "%s"\n' % tr.SRC)
            if not LINE7:
                f.write('INCLUDE "%s"\n' % LINE5)
            f.write('.t_b5end\n')
            f.write('ORG &8000\nINCLUDE "%s"\nSAVE "r.bin", &8000, t_b5end\n' % os.path.join(MS, 'gfx-raster_disc.asm'))
            f.write('CLEAR &8000, &9000\nORG &8000\nINCLUDE "%s"\n' % os.path.join(MS, 'gfx-raster_poly.asm'))
            if not LINE7:
                f.write('INCLUDE "%s"\n' % LINEA)
            f.write('SAVE "ra.bin", &8000, P%\n')
            if os.path.exists(MERID):       # the meridian window (bank 7), with the game's
                f.write(MERID_GAME + 'CLEAR &8000, &C000\nORG &%X\nINCLUDE "%s"\nSAVE "m.bin", &%X, P%%\n'
                        % (MTEST, MERID, MTEST))
            if LINE7:
                f.write('CLEAR &8000, &C000\nORG R7START\nINCLUDE "%s"\nSAVE "r7.bin", R7START, P%%\n' % tr.SRC7)
        else:                               # (bank 5 from &8000, the stubs, bank 7 from &8000)
            f.write('ORG &%X\nINCLUDE "%s"\n.r_hz_end\n' % (tr.HZ, SRCH))
            f.write('ORG &8000\nINCLUDE "%s"\nSAVE "r.bin", &8000, P%%\n' % tr.SRC)
            f.write('CLEAR &8000, &C000\nORG &8000\nINCLUDE "%s"\nSAVE "r7.bin", &8000, P%%\n' % tr.SRC7)
            f.write('SAVE "h.bin", &%X, r_hz_end\n' % tr.HZ)
    r = subprocess.run([tr.BEEBASM, '-i', w, '-d', '-labels', os.path.join(d, 'w.lab')],
                       cwd=d, capture_output=True, text=True)
    if r.returncode != 0 or 'error' in r.stdout.lower():
        print(r.stdout, r.stderr)
        raise SystemExit('assembly failed')
    txt = open(os.path.join(d, 'w.lab')).read()
    syms = {k: int(v) for k, v in re.findall(r"'([^']+)':(-?\d+)L?", txt)}
    data = open(os.path.join(d, 'r.bin'), 'rb').read()
    dataa = open(os.path.join(d, 'ra.bin'), 'rb').read() if WINDOWS else b''
    data7 = open(os.path.join(d, 'r7.bin'), 'rb').read() if os.path.exists(os.path.join(d, 'r7.bin')) else b''
    datah = open(os.path.join(d, 'h.bin'), 'rb').read() if not WINDOWS else b''
    global DATAM
    DATAM = open(os.path.join(d, 'm.bin'), 'rb').read() if os.path.exists(os.path.join(d, 'm.bin')) else b''
    msg = [l for l in r.stdout.splitlines() if l.startswith('raster')]
    shutil.rmtree(d, ignore_errors=True)
    return syms, (data, dataa, data7, datah), ('; '.join(msg))


# the bank (ROMSEL) each entry point is called with: the frame layer's T_
# trampolines page bank 5 in (RASTBANK), ANDY over it for R_POLY and R_LINE
# (T_POLY, T_LINE: RASTPOLY; before, bank 7 for R_LINE)
_C = dict(re.findall(r'^(RASTPOLY|RASTBANK)\s*=\s*&?([0-9A-Fa-f]+)', open(GFX).read(), re.M))
ENTRY_BANK = {'R_POLY': int(_C.get('RASTPOLY', '5'), 16), 'R_LINE': 7 if LINE7 else int(_C.get('RASTPOLY', '5'), 16)}


class Machine(tr.Machine):
    """the demo's machine with the Master's sideways RAM: ROMSEL bits 0-3 page a
    bank in at &8000-&BFFF, bit 7 ANDY over its &8000-&8FFF"""
    def __init__(self, org, seed=1):
        import random
        from py65.devices.mpu65c02 import MPU
        self.syms, (data, dataa, data7, datah), self.sizemsg = assemble(org)
        rnd = random.Random(seed)
        self.mem = [rnd.randrange(256) for _ in range(65536)]
        self.mem[tr.HZ:tr.HZ + len(datah)] = list(datah)
        b5 = [rnd.randrange(256) for _ in range(0x4000)]
        b5[0:len(data)] = list(data)
        b7 = [rnd.randrange(256) for _ in range(0x4000)]
        r7 = self.syms.get('r7_start', 0x8000) - 0x8000
        b7[r7:r7 + len(data7)] = list(data7)
        b7[MTEST - 0x8000:MTEST - 0x8000 + len(DATAM)] = list(DATAM)
        for n in range(512):
            self.mem[MG['QSL'] + n] = (n * n // 4) & 255
            self.mem[MG['QSH'] + n] = (n * n // 4) >> 8
        self.andy = [rnd.randrange(256) for _ in range(0x1000)]
        self.andy[0:len(dataa)] = list(dataa)
        self.banks = {5: b5, 7: b7}
        self.romsel = None
        self.page(5)
        self.lo, self.hi = 0x8000, 0xC000
        self.image = list(data)
        self.mpu = MPU(memory=self.mem)
        self.cycles = 0
        self.guard = True

    def check_writes(self, snap, name):
        mem, s = self.mem, self.syms
        allowed = sorted([(0x06, 0x28), (tr.ROMSELCOPY, tr.ROMSELCOPY + 1), (0x100, 0x200),
                          (tr.SCR0, tr.SCR1), (self.lo, self.hi),
                          (s['WS_START'], s['WS_END']), (tr.HZ, s['r_hz_end']),
                          (tr.ROMSEL, tr.ROMSEL + 1)])
        a0 = 0
        for lo, hi in allowed + [(0x10000, 0x10000)]:
            if a0 < lo and mem[a0:lo] != snap[a0:lo]:
                for a in range(a0, lo):
                    if mem[a] != snap[a]:
                        raise AssertionError('%s wrote &%04X' % (name, a))
            a0 = max(a0, hi)
        if self.romsel & 15 != 5:              # (the meridian window: bank 7 paged)
            return
        r0 = s['r_run0']
        for r in range(24):
            b = r0 + 256 * r
            if mem[b:b + 190] != snap[b:b + 190]:
                raise AssertionError('%s left run %d modified' % (name, r))

    def page(self, rs):
        """ROMSEL = rs (as a write to ROMSEL would): bank rs AND 15, ANDY if bit 7"""
        mem = self.mem
        if rs != self.romsel:
            if self.romsel is not None:          # put the paged memory back
                b, andy = self.romsel & 15, self.romsel & 0x80
                if andy:
                    self.andy[:] = mem[0x8000:0x9000]
                    self.banks[b][0x1000:] = mem[0x9000:0xC000]
                else:
                    self.banks[b][:] = mem[0x8000:0xC000]
            b = rs & 15
            mem[0x8000:0xC000] = self.banks[b]
            if rs & 0x80:
                mem[0x8000:0x9000] = self.andy
            self.romsel = rs
        mem[tr.ROMSEL] = mem[tr.ROMSELCOPY] = rs

    def call(self, name, a=0, x=0, y=0, maxcyc=20_000_000, bank=None):
        """as the demo's, but entered (and returning) with the entry's ROMSEL (the
        T_ trampoline's); ROMSEL writes page as the hardware would, and &F4 must
        match ROMSEL whenever it is written"""
        if bank is None:
            bank = ENTRY_BANK.get(name, 5)
        self.page(bank)
        mpu, mem = self.mpu, self.mem
        if self.guard:
            snap = mem[:]
        mpu.a, mpu.x, mpu.y = a, x, y
        mpu.p = 0x24
        ret = tr.RET - 1
        mem[0x1FF] = ret >> 8
        mem[0x1FE] = ret & 0xFF
        mpu.sp = 0xFD
        mpu.pc = self.syms[name] if isinstance(name, str) else name
        c0 = mpu.processorCycles
        step = mpu.step
        while mpu.pc != tr.RET:
            step()
            rs = mem[tr.ROMSEL]
            if rs != self.romsel:
                if mem[tr.ROMSELCOPY] != rs:
                    raise AssertionError('%s: ROMSEL &%02X written with &F4 = &%02X' % (name, rs, mem[tr.ROMSELCOPY]))
                self.page(rs)                    # (the runs, which the guard checks, are in
                                                 # bank 5's &9000-&BFFF: paged either way)
            if mpu.processorCycles - c0 > maxcyc:
                raise RuntimeError('runaway in %s' % name)
        if self.romsel != bank:
            raise AssertionError('%s returned with ROMSEL &%02X' % (name, self.romsel))
        self.cycles = mpu.processorCycles - c0
        if self.guard:
            self.check_writes(snap, name)
        self.page(5)
        return self.cycles


def set_col(self, ce, co):
    self.m.wzp('R_COLE', ce)
    self.m.wzp('R_COLO', co)
    self.m.wr('R_COL2', ce)          # a 2-row colour pair in R_POLY's 4-row colour
    self.m.wr('R_COL3', co)


def draw_line(self, x0, y0, x1, y1, ce, co, entry='R_LINE'):
    m = self.m
    for nm, v in (('R_X0', x0), ('R_Y0', y0), ('R_X1', x1), ('R_Y1', y1)):
        m.wr(nm, v & 0xFF)
        m.wr(nm, (v >> 8) & 0xFF, 1)
    self.set_col(ce, co)
    return m.call(entry)                  # (with T_LINE's ROMSEL)


_demo_test_lines = tr.Tester.test_lines


def test_lines(self, n):
    """the demo's random lines, then as many again aimed at R_LINE's clipping:
    ends on and next to the window's sides, long lines (d > 255) across the
    window, points, horizontal, vertical and diagonal lines; each checked
    against the reference (pixels, DIRTY) and the buffer's row range
    (R_PRDYT..R_PRDYB must take in every row drawn)"""
    _demo_test_lines(self, n)
    m, rnd = self.m, self.rnd

    def end(kind):
        cl, cr, ct, cb = self.clip
        if kind == 0:                                     # on or next to a side
            return (rnd.choice((cl - 1, cl, cl + 1, cr - 1, cr, cr + 1, rnd.randrange(256))),
                    rnd.choice((ct - 1, ct, ct + 1, cb - 1, cb, cb + 1, rnd.randrange(192))))
        if kind == 1:                                     # around the window
            return rnd.randrange(-300, 556), rnd.randrange(-300, 492)
        if kind == 2:                                     # inside
            return rnd.randrange(cl, cr + 1), rnd.randrange(ct, cb + 1)
        return rnd.randrange(-3000, 3256), rnd.randrange(-3000, 3192)   # long
    b = 0
    for it in range(n):
        if it % 50 == 0:
            if rnd.random() < 0.5:
                cl = rnd.randrange(1, 120)
                ct = rnd.randrange(0, 120)
                self.set_clip((cl, rnd.randrange(cl, 255), ct, rnd.randrange(ct, 192)))
            else:
                self.set_clip((1, 254, 1, 191))
            b = rnd.randrange(2)
            m.set_screen(bytes(rnd.randrange(256) for _ in range(0x3000)))
            ref, dirt = self.reset_state(b)
        x0, y0 = end(rnd.randrange(4))
        x1, y1 = end(rnd.randrange(4))
        s = rnd.random()
        if s < 0.1:
            x1, y1 = x0, y0
        elif s < 0.2:
            y1 = y0
        elif s < 0.3:
            x1 = x0
        elif s < 0.4:
            d = rnd.randrange(-600, 600)
            x1, y1 = x0 + d, y0 + rnd.choice((d, -d))
        ce, co = rnd.randrange(256), rnd.randrange(256)
        pts = (x0, y0, x1, y1)
        self.draw_line(*pts, ce, co)
        rows = []
        for x, y in tr.line_pixels(*pts):
            if ref.inwin(x, y):
                ref.setpix(x, y, ce, co)
                dl, dr = dirt[y]
                dirt[y] = (min(dl, x), max(dr, x))
                rows.append(y)
        if m.screen() != bytes(ref.b):
            raise AssertionError('line %s' % (pts,))
        if self.dirty(b) != dirt:
            raise AssertionError('line dirty %s' % (pts,))
        if rows and not (m.rd('R_PRDYT', b) <= min(rows) and max(rows) <= m.rd('R_PRDYB', b)):
            raise AssertionError('line row range %s' % (pts,))


# ------------------------------------------------------------ meridian window
import math as _m
import planet_analytic as PA                    # noqa: E402  (the model, beside this file)


def _rand_frame(rnd):
    """a random orientation (orthonormal vectors scaled to &6000 with a few %
    noise, as Elite's), sometimes with a normal nearly along an axis
    (as planet_synth.py's rand_frame, in the development tree)"""
    q = [rnd.gauss(0, 1) for _ in range(4)]
    n = _m.sqrt(sum(x * x for x in q)); w, x, y, z = [v / n for v in q]
    R = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    vecs = []
    for i in range(3):
        sc = 24576 * (1 + rnd.uniform(-0.04, 0.04))
        vecs.append([int(round(R[j][i] * sc)) for j in range(3)])
    if rnd.random() < 0.15:
        k, ax = rnd.randrange(3), rnd.randrange(3)
        eps = rnd.uniform(-0.02, 0.02)
        v = [0, 0, 0]; v[ax] = 24576
        for j in range(3):
            if j != ax:
                v[j] = int(24576 * rnd.uniform(-1, 1) * abs(eps))
        vecs[k] = v
    return vecs


def _rotate(vecs, ax, ang):
    """the frame rotated about axis ax by ang (as the planet's spin)"""
    c, s_ = _m.cos(ang), _m.sin(ang)
    i, j = [(1, 2), (0, 2), (0, 1)][ax]
    out = []
    for v in vecs:
        v = list(v)
        v[i], v[j] = int(round(c * v[i] - s_ * v[j])), int(round(s_ * v[i] + c * v[j]))
        out.append(v)
    return out


def _smag(v):
    m = min(abs(v), 32767)
    return m & 255, (m >> 8) | (0x80 if v < 0 else 0)


def merid_rows(self, vecs, cx, cy, r, spans, held=False, valid=False):
    """PM_HOOK (game context) then PM_MERID (frame) on the machine, for the
    planet with orientation vecs (nosev, roofv, sidev), centre (cx, cy) and
    radius r over the disc rows spans {y: (l, r)}; checked against the model
    (6-harness/planet_analytic.py, analytic_rows_fixed) and the hook's contract.
    Returns {y: (xs, p)} and the two calls' cycles"""
    m = self.m
    mem = m.mem
    inwk = [0] * 36
    for k, v in enumerate(vecs[0] + vecs[1] + vecs[2]):
        inwk[9 + 2 * k], inwk[10 + 2 * k] = _smag(v)
    for k, v in enumerate(inwk):
        mem[MG['INWK'] + k] = v
    for nm, v in (('K3', cx), ('K4', cy)):
        mem[MG[nm]] = v & 255
        mem[MG[nm] + 1] = (v >> 8) & 255
    mem[MG['PM_R']] = r
    mem[MG['PM_OK']] = 0
    mem[MG['PS_VALID']] = 0x80 if valid else 0   # (the arrays hold the last rows: T_MERID's)
    if held:                           # the orientation held: the last frame drew it
        mem[MG['MCNT']] = (mem[MG['MCNT']] - 1) & 255
        _hold(m)
    else:                              # a new orientation (PM_SPIN = 0)
        m.page(7); mem[m.syms['PM_SPIN']] = 0; m.page(5)
    zp = mem[0x10:0x29]
    a0, x0, y0 = self.rnd.randrange(256), self.rnd.randrange(256), self.rnd.randrange(256)
    m.guard = False
    snap = mem[:]
    c1 = m.call(m.syms['PM_HOOK'], a=a0, x=x0, y=y0, bank=7)
    mpu = m.mpu
    if (mpu.a, mpu.x, mpu.y, mpu.p & 0xC3) != (a0, x0, y0, 0x24 & 0xC3):
        raise AssertionError('PM_HOOK did not keep A, X, Y and the flags')
    if mem[0x10:0x29] != zp:
        raise AssertionError('PM_HOOK did not restore zero page &10-&28')
    kept = mem[MG['PM_OK']] == 0xC0
    if mem[MG['PM_OK']] != 0x80 and not (valid and kept):
        raise AssertionError('PM_HOOK did not set PM_OK')
    for a in range(0x10000):           # (bank 7 is paged back out: main RAM only)
        if mem[a] != snap[a] and not (a == MG['PM_OK'] or 0x100 <= a < 0x200 or 0x8000 <= a < 0xC000):
            raise AssertionError('PM_HOOK wrote &%04X' % a)
    ndt, ndb = (min(spans), max(spans)) if spans else (255, 0)
    ndl, ndr = [255] * 192, [0] * 192
    m.wr('R_NDT', ndt)
    m.wr('R_NDB', ndb)
    for y in range(ndt, ndb + 1) if spans else []:
        ndl[y], ndr[y] = spans.get(y, (255, 0))
        m.wr('R_NDISCL', ndl[y], y)
        m.wr('R_NDISCR', ndr[y], y)
    m.guard = True
    c2 = m.call(m.syms['PM_MERID'], bank=7) if spans and not kept else 0   # (T_MERID)
    want = PA.analytic_rows_fixed(cx, cy, r, PA.frame_normals(inwk), ndt, ndb, ndl, ndr) if spans else {}
    out = {}
    for y in range(ndt, ndb + 1) if spans else []:
        n = m.rd('R_NDN', y)
        xs = [m.rd('R_NDX%d' % k, y) for k in range(n)]
        got = (m.rd('R_NDP', y) & 1, xs)
        if got != (want[y][0] & 1, want[y][1]):
            raise AssertionError('PM_MERID row %d: %s, the model %s (centre %d,%d r %d)' % (y, got, want[y], cx, cy, r))
        out[y] = (xs, got[0])
    return out, c1, c2


def _game_spans(cx, cy, r, clip=(1, 254, 1, 191)):
    """the disc's rows as the frame layer has them (integer half-widths), clipped"""
    out = {}
    for y in range(max(cy - r, clip[2]), min(cy + r, clip[3]) + 1):
        h = _m.isqrt(r * r - (y - cy) ** 2)
        l, rr = max(cx - h, clip[0]), min(cx + h, clip[1])
        if l <= rr:
            out[y] = (l, rr)
    return out


def _hold(m):
    """a frame left to hold the orientation (PM_SPIN), as MERIDHOLD >= 1 leaves
    it: the held paths are tested whatever MERIDHOLD the build has (with 0 the
    game never takes them)"""
    m.page(7)
    if m.mem[m.syms['PM_SPIN']] == 0:
        m.mem[m.syms['PM_SPIN']] = 1
    m.page(5)


def test_merid(self, n):
    """the meridian window alone: n random planets (radius 6..250, centre on
    and off the screen, any orientation), PM_HOOK then PM_MERID, bit for bit
    against 6-harness/planet_analytic.py"""
    rnd = self.rnd
    self.set_clip((1, 254, 1, 191))
    for i in range(n):
        vecs = _rand_frame(rnd)
        r = rnd.choice((rnd.randrange(6, 40), rnd.randrange(6, 251)))
        cx = rnd.randrange(-r // 2, 256 + r // 2)
        cy = rnd.randrange(-r // 2, 192 + r // 2)
        rows, c1, c2 = self.merid_rows(vecs, cx, cy, r, _game_spans(cx, cy, r))
        self.stat('merid_hook', c1)
        self.stat('merid_rows', (len(rows), c2))
        # the same planet next frame (orientation held): a new radius and
        # centre (the radius terms only, still exact), or the same (rows kept)
        m, mem = self.m, self.m.mem
        r0, cx0, cy0 = r, cx, cy
        if rnd.random() < 0.6:
            r = max(6, min(250, r + rnd.randrange(-3, 4)))
            cx += rnd.randrange(-3, 4)
            cy += rnd.randrange(-3, 4)
        same = (r, cx, cy) == (r0, cx0, cy0)
        mem[MG['PS_VALID']] = 0x80
        mem[MG['MCNT']] = (mem[MG['MCNT']] - 1) & 255
        for nm, v in (('K3', cx), ('K4', cy)):
            mem[MG[nm]] = v & 255
            mem[MG[nm] + 1] = (v >> 8) & 255
        mem[MG['PM_R']] = r
        mem[MG['PM_OK']] = 0
        _hold(m)
        zp = mem[0x10:0x29]
        m.guard = False
        m.call(m.syms['PM_HOOK'], a=1, x=2, y=3, bank=7)
        mpu = m.mpu
        if (mpu.a, mpu.x, mpu.y) != (1, 2, 3) or mem[0x10:0x29] != zp:
            raise AssertionError('PM_HOOK (held) did not keep A, X, Y and zero page')
        if mem[MG['PM_OK']] != (0xC0 if same else 0x80):
            raise AssertionError('PM_HOOK held: PM_OK = %02X (same %s)' % (mem[MG['PM_OK']], same))
        if not same:                     # the held orientation's rows (moved, if the
            self.merid_rows(vecs, cx, cy, r, _game_spans(cx, cy, r), held=True)   # radius is the same)
            if rnd.random() < 0.7:           # and once more, moved again: the last rows
                cx += rnd.randrange(-6, 7)   # moved (pm_shift), or made again
                cy += rnd.randrange(-6, 7)
                self.merid_rows(vecs, cx, cy, r, _game_spans(cx, cy, r), held=True, valid=True)
    h = self.stats['merid_hook']
    rr = self.stats['merid_rows']
    return 'PM_HOOK %d..%d cycles, PM_MERID %.0f cycles a row' % (min(h), max(h), sum(c for _, c in rr) / max(1, sum(k for k, _ in rr)))


def beach_rows(self, f, spans, cx, cy, rad):
    """test_frames' 'beachball' scenario: this frame's boundaries from the
    meridian window, for a planet spinning about a random axis (its
    orientation kept between frames and, as in the game, taken one frame in
    four: in between the window keeps or moves its last rows, or makes them
    again for the new centre and radius), written to the disc layer's arrays"""
    st = getattr(self, '_beach', None)
    if st is None or f == 0:
        st = self._beach = dict(vecs=_rand_frame(self.rnd)[:], ax=self.rnd.randrange(3),
                                w=self.rnd.choice((-1, 1)) * self.rnd.uniform(0.01, 0.12))
    held = f % 4 != 0
    if not held:
        st['vecs'] = _rotate(st['vecs'], st['ax'], 4 * st['w'])
    r = max(6, min(250, int(rad)))
    rows, c1, c2 = self.merid_rows(st['vecs'], int(cx), int(cy), r, spans, held=held, valid=held)
    self.m.wr('R_NDF', 1)
    return {y: v for y, v in rows.items()}, 1


tr.Tester.merid_rows = merid_rows
tr.Tester.test_merid = test_merid
tr.Tester.beach_rows = beach_rows
if os.path.exists(MERID):
    tr.EXTRA += [('merid', 'test_merid', 400, ()), ('beachball', 'test_frames', 44, ('beachball',)),
                 ('beachball', 'test_frames', 44, ('beachball',))]

tr.assemble = assemble
tr.Tester.test_lines = test_lines
_demo_check_patch_sites = tr.check_patch_sites
tr.check_patch_sites = check_patch_sites
tr.Machine = Machine
tr.Tester.set_col = set_col
tr.Tester.draw_line = draw_line

if __name__ == '__main__':
    tr.main()
