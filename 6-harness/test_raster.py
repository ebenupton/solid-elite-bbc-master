#!/usr/bin/env python3
"""Soak test for the full Master port's rasteriser (1-source-files/main-sources/gfx-raster*.asm).

A thin adapter over the demo port's tools/test_raster.py (its pixel-exact Python
reference, py65 65C02, the write guard and every test), pointed at the Master files:

  * the wrapper assembles the renderer's shared workspace as elite-gfx.asm lays it
    out in main RAM (one block, from its first ORG to WS_END: gfx-raster_scr.asm, the
    per-call inputs, with R_NDISCL page aligned, which the polygon edge tables share with
    R_NDISCR; gfx-raster_vars.asm at its fixed base, as the laser-sight rows must not cross
    a page; R_WL, R_WR, R_NDN, KF, the stars), and the
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
tr.NSTARS = int(re.search(r'^\s*NOST\s*=\s*(\d+)', open(os.path.join(MS, 'elite-source.asm')).read(), re.M).group(1)) + 1   # (NDSTAR: the star arrays' size)


def gfx_constants():
    """elite-gfx.asm's constants (MCB, banks, sizes), defined before its first ORG or CLEAR"""
    out = ['HOMEBANK = 4']
    # the shared workspace's star arrays are NDSTAR (elite-gfx.asm) long, from Elite's
    # NOST (elite-source.asm), and it ends at the main code's start, CODE% (WS_END)
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
    return [p for p in (os.path.join(MS, f) for f in ('gfx-raster.asm', 'gfx-raster_lcold.asm', 'gfx-raster_disc2.asm',
                                                      'gfx-raster_disc.asm', 'gfx-raster_poly.asm', 'gfx-raster_line.asm'))
            if os.path.exists(p)]


LINEA = os.path.join(MS, 'gfx-raster_line.asm')    # R_LINE in the polygon window (ANDY) ...
LINE5 = os.path.join(MS, 'gfx-raster_lcold.asm')   # ... and its cold part in the shared region
LINE7 = not os.path.exists(LINEA)                  # (before: R_LINE in bank 7, gfx-raster7.asm)
DISC2 = os.path.join(MS, 'gfx-raster_disc2.asm')   # the second disc (R_DISC2): after the shared
HASD2 = os.path.exists(DISC2)                      # region, with R_LINE's cold part in the room
                                                   # below the per-x tables, as elite-gfx.asm
                                                   # places them (its spans in bank 5 too, R_S2L0
                                                   # ..., and its rows in the shared workspace)


SRCH = os.path.join(MS, 'gfx-raster_hz.asm')       # (the bank 5 <-> 7 stubs, while they exist)
# the meridian window (gfx-merid.asm, the circle engine, and gfx-planet7.asm,
# the styles: bank 7 after the cold area; here at MTEST), with the game's
# symbols they read: INWK, K3, K4, TYPE and K at their places in Master Elite's
# zero page (K3 and K4 are in &10-&28, which PF_HOOK saves and uses: it must
# read them first), PF_CLS and QQ2 below the workspace (at &0C00: the workspace
# starts at &0E00), FRIN and K% as the game has them, the quarter squares at
# &7000 (after the test's screen)
MERID = os.path.join(MS, 'gfx-merid.asm')
MTEST = 0xA000
MG = dict(INWK=0x9C, K3=0x14, K4=0x22, QSL=0x7000, QSH=0x7200,
          TYPE=0x85, K=0x56, PF_CLS=0x0C03, VIEW=0x0C08, QQ2=0x0C10, FRIN=0x0841)
MG['K%'] = 0x0400
MERID_GAME = ''.join('%s = &%04X\n' % kv for kv in MG.items())
# banded planets (gfx-planet7.asm's _PLANET_BANDS, the Makefile's bands=on):
# tested on (they are off in the default build), or as BANDS=off has it
BANDS = os.environ.get('BANDS', 'on') == 'on'
MERID_GAME += '_PLANET_BANDS = %s\n' % ('TRUE' if BANDS else 'FALSE')
# planet rings (_PLANET_RINGS, the Makefile's rings=on): likewise tested on
# (off in the default build), or as RINGS=off has it; defined before the
# shared workspace (gfx-planetv.asm's RG_ variables)
RINGS = os.environ.get('RINGS', 'on') == 'on'
# the planet's styles (gfx-planet7.asm in the meridian window after
# gfx-kept7.asm) and the variables the frame reads (gfx-planetv.asm: in the
# shared workspace, ws_block, where elite-gfx.asm includes it; else here at
# ZTEST)
CAPS7 = os.path.join(MS, 'gfx-planet7.asm')
CAPSV = os.path.join(MS, 'gfx-planetv.asm')
CAPS = os.path.exists(CAPS7)
CAPSV_WS = 'gfx-planetv.asm' in open(GFX).read()   # (elite-gfx.asm includes it:
                                                    # the shared workspace, ws_block)
ZTEST = 0xC000
DATAZ = b''
# the kept solid rows (gfx-raster_kept.asm in the disc window, gfx-kept7.asm in
# bank 7 after the meridian window): their variables (in the glue area in the
# game; KF is in the shared workspace, as in the game) and the glue area's
# thunk from the polygon window to bank 7 and k_setbuf7 (gfx-tramp.asm's),
# here at HZ
KEPT7 = os.path.join(MS, 'gfx-kept7.asm')
KEPT = os.path.exists(KEPT7)
MERIDBANK = 7
KEPT_HZ = '''SGY = 96
SGOUT = 20
.KMODE EQUB 0
.KBIT EQUB 1
.KBITN EQUB &FE
.KPLO EQUB &FF
.KPHI EQUB 0
.KREC EQUB 0
.T_KPRE
 LDX #MERIDBANK
 STX &F4
 STX &FE30
 JSR k_pre
 LDX #RASTPOLY
 STX &F4
 STX &FE30
 RTS
.k_setbuf7
 TAX
 LDA k_dlh,X
 STA k_pd1+2
 STA k_pd3+2
 STA k_pd5+2
 LDA k_drh,X
 STA k_pd2+2
 STA k_pd4+2
 STA k_pd6+2
 STA k_pd7+2
 RTS
.k_dlh EQUB HI(R_DIRTYL0), HI(R_DIRTYL1)
.k_drh EQUB HI(R_DIRTYR0), HI(R_DIRTYR1)
'''
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
        f.write('_PLANET_RINGS = %s\n' % ('TRUE' if RINGS else 'FALSE'))
        f.write(ws_block() + '\n')
        if WINDOWS:
            f.write('ORG &%X\n' % tr.HZ)
            if KEPT:            # the kept rows' state and the glue area's thunks
                f.write(KEPT_HZ)
            f.write('.r_hz_end\n')
            if KEPT:
                f.write('SAVE "h.bin", &%X, r_hz_end\n' % tr.HZ)
            f.write('CLEAR &8000, &C000\nORG &9000\nINCLUDE "%s"\n' % tr.SRC)
            if HASD2:
                f.write('INCLUDE "%s"\n' % DISC2)
                f.write('.t_b5end\n')
                if not LINE7:
                    f.write('CLEAR r_tfree, r_tables\nORG r_tfree\nINCLUDE "%s"\n' % LINE5)
            else:
                if not LINE7:
                    f.write('INCLUDE "%s"\n' % LINE5)
                f.write('.t_b5end\n')
            f.write('ORG &8000\nINCLUDE "%s"\n' % os.path.join(MS, 'gfx-raster_disc.asm'))
            if KEPT:
                f.write('INCLUDE "%s"\n' % os.path.join(MS, 'gfx-raster_kept.asm'))
            f.write('SAVE "r.bin", &8000, t_b5end\n')
            f.write('CLEAR &8000, &9000\nORG &8000\nINCLUDE "%s"\n' % os.path.join(MS, 'gfx-raster_poly.asm'))
            if not LINE7:
                f.write('INCLUDE "%s"\n' % LINEA)
            f.write('SAVE "ra.bin", &8000, P%\n')
            if os.path.exists(MERID):       # the meridian window (bank 7), with the game's
                f.write(MERID_GAME)
                if CAPS and not CAPSV_WS:   # (the variables at ZTEST first, if not in
                    f.write('CLEAR &%X, &DF00\nORG &%X\nINCLUDE "%s"\nSAVE "z.bin", &%X, P%%\n'
                            % (ZTEST, ZTEST, CAPSV, ZTEST))   # the shared workspace)
                f.write('CLEAR &8000, &C000\nORG &%X\nINCLUDE "%s"\n' % (MTEST, MERID)
                        + ('INCLUDE "%s"\n' % KEPT7 if KEPT else '')
                        + ('INCLUDE "%s"\n' % CAPS7 if CAPS else '') + 'SAVE "m.bin", &%X, P%%\n' % MTEST)
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
    datah = open(os.path.join(d, 'h.bin'), 'rb').read() if os.path.exists(os.path.join(d, 'h.bin')) else b''
    global DATAM, DATAZ
    DATAM = open(os.path.join(d, 'm.bin'), 'rb').read() if os.path.exists(os.path.join(d, 'm.bin')) else b''
    DATAZ = open(os.path.join(d, 'z.bin'), 'rb').read() if os.path.exists(os.path.join(d, 'z.bin')) else b''
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
        self.mem[ZTEST:ZTEST + len(DATAZ)] = list(DATAZ)
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
        if 'KMODE' in self.syms:             # (the game's glue area and HAZEL: K mode off)
            s = self.syms
            for k, v in (('KMODE', 0), ('KBIT', 1), ('KBITN', 0xFE), ('KPLO', 0xFF), ('KPHI', 0)):
                self.mem[s[k]] = v
            self.mem[s['KF']:s['KF'] + 192] = [0] * 192

    # the demo's tests write a row's start colour as R_NDP (bit 0; its other
    # bits random): here it is R_NDN's bit 7 (the count in bits 0-6)
    def wr(self, name, val, off=0):
        if name == 'R_NDP' and 'R_NDP' not in self.syms:
            a = self.syms['R_NDN'] + off
            self.mem[a] = (self.mem[a] & 0x7F) | ((val & 1) << 7)
            return
        super().wr(name, val, off)

    def rd(self, name, off=0):
        if name == 'R_NDP' and 'R_NDP' not in self.syms:
            return self.mem[self.syms['R_NDN'] + off] >> 7
        if name == 'R_NDN' and 'R_NDP' not in self.syms:
            return self.mem[self.syms['R_NDN'] + off] & 0x7F
        return super().rd(name, off)

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
                raise RuntimeError('runaway in %s at &%04X ROMSEL &%02X' % (name, mpu.pc, self.romsel))
        if self.romsel != bank:
            raise AssertionError('%s returned with ROMSEL &%02X' % (name, self.romsel))
        self.cycles = mpu.processorCycles - c0
        if self.guard:
            self.check_writes(snap, name)
        self.page(5)
        return self.cycles


def star_ref(ref, x, y, s, scol):
    """A star (R_STARPLOT): per row, per byte, its in-window pixels are set to
    scol only if the whole byte is black. (The docking slot's box is the frame
    layer's: f_slot takes those stars out of R_SS before the plot.)"""
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
            if all(ref.getpix(4 * c + p, py) == 0 for p in range(4)):
                for px in pxs:
                    ref.setpix(px, py, scol, scol)


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


# ------------------------------------------------------------ the circle engine
import math as _m
import planet_caps as PCM                       # noqa: E402  (the model, beside this file)
PCM.BANDS = BANDS
PCM.RINGS = RINGS


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


def _game_spans(cx, cy, r, clip=(1, 254, 1, 191)):
    """the disc's rows as the frame layer has them (integer half-widths), clipped"""
    out = {}
    for y in range(max(cy - r, clip[2]), min(cy + r, clip[3]) + 1):
        h = _m.isqrt(r * r - (y - cy) ** 2)
        l, rr = max(cx - h, clip[0]), min(cx + h, clip[1])
        if l <= rr:
            out[y] = (l, rr)
    return out


def _b7(m, name, vals=None):
    """bank 7's bytes at a label (read, or written if vals)"""
    m.page(7)
    a = m.syms[name]
    if vals is None:
        out = m.mem[a]
    else:
        for i, v in enumerate(vals):
            m.mem[a + i] = v & 255
        out = None
    m.page(5)
    return out


def _sm(v):
    m_ = min(abs(v), 32767)
    return [m_ & 255, (m_ >> 8) | (0x80 if v < 0 else 0)]


def _spans_in(m, spans):
    """the disc's rows into the disc layer's arrays: (ndt, ndb, ndl, ndr)"""
    ndt, ndb = (min(spans), max(spans)) if spans else (255, 0)
    ndl, ndr = [255] * 192, [0] * 192
    m.wr('R_NDT', ndt)
    m.wr('R_NDB', ndb)
    for y in range(ndt, ndb + 1) if spans else []:
        ndl[y], ndr[y] = spans.get(y, (255, 0))
        m.wr('R_NDISCL', ndl[y], y)
        m.wr('R_NDISCR', ndr[y], y)
    return ndt, ndb, ndl, ndr


def _check_rows(m, want, ndt, ndb, what):
    out = {}
    for y in range(ndt, ndb + 1):
        n = m.rd('R_NDN', y)
        xs = [m.rd('R_NDX%d' % k, y) for k in range(n)]
        got = (m.rd('R_NDP', y) & 1, xs)
        if got != (want[y][0] & 1, want[y][1]):
            raise AssertionError('%s row %d: %s, the model %s' % (what, y, got, want[y]))
        out[y] = (xs, got[0])
    return out


def _body(cx, cy, r, base, circs):
    """the model's records and base colour for circles [(vec, c8, cneg, kn)]"""
    recs = [PCM.circ_consts(cx, cy, r, v, c8, cn, kn) for v, c8, cn, kn in circs]
    for c in recs:
        if c is not None:
            base ^= PCM.rec_parity(c)
    return base, recs


def circ_rows(self, circs, spans, body, base=0):
    """pc_circ for each circle (vec, c8, cneg, kn) of the body (cx, cy, r),
    then PC_ROWS over the disc rows spans {y: (l, r)}; checked against
    6-harness/planet_caps.py. Returns {y: (xs, p)} and the cycles"""
    m = self.m
    cx, cy, r = body
    _b7(m, 'PC_N', [0])
    _b7(m, 'pc_inv', [base])
    m.guard = False
    c1 = 0
    for vec, c8, cneg, kn in circs:
        _b7(m, 'pcv', [b for lo_hi in vec for b in lo_hi])
        _b7(m, 'pcbx', [cx & 255, (cx >> 8) & 255, cy & 255, (cy >> 8) & 255, r])
        _b7(m, 'pcc', [c8, 0x80 if cneg else 0, kn & 255, kn >> 8])
        c1 += m.call(m.syms['pc_circ'], bank=7)
    m.guard = True
    base, recs = _body(cx, cy, r, base, circs)
    if _b7(m, 'pc_inv') != base or _b7(m, 'PC_N') != sum(1 for c in recs if c is not None and not c['none']):
        raise AssertionError('pc_circ: base %d PC_N %d, the model %d %d' % (_b7(m, 'pc_inv'), _b7(m, 'PC_N'), base, len(recs)))
    ndt, ndb, ndl, ndr = _spans_in(m, spans)
    c2 = m.call(m.syms['PC_ROWS'], bank=7) if spans else 0      # (T_CAPS)
    want = PCM.body_rows(base, recs, ndt, ndb, ndl, ndr) if spans else {}
    out = _check_rows(m, want, ndt, ndb, 'PC_ROWS (centre %d,%d r %d, circles %s)' % (cx, cy, r, circs)) if spans else {}
    return out, c1, c2


def _rand_cap(rnd):
    v = [rnd.gauss(0, 1) for _ in range(3)]
    n = _m.sqrt(sum(x * x for x in v)) or 1
    sc = 12288 * rnd.uniform(0.98, 1.02)  # (a vector halved, as pf_tilt has it)
    v = [int(round(x / n * sc)) for x in v]
    if rnd.random() < 0.1:              # (an axis near the screen's plane, or along y)
        v[rnd.randrange(3)] = rnd.randrange(-20, 21)
    c8 = 0 if rnd.random() < 0.2 else rnd.randrange(256)     # (great circles too)
    return [tuple(_sm(x)) for x in v], c8, rnd.random() < 0.3, 10923


def test_caps(self, n):
    """the engine alone: n random planets (radius 6..250, centre on and off
    the screen) with one to three random circles, pc_circ then PC_ROWS, bit
    for bit against 6-harness/planet_caps.py"""
    rnd = self.rnd
    self.set_clip((1, 254, 1, 191))
    for i in range(n):
        r = rnd.choice((rnd.randrange(6, 40), rnd.randrange(6, 251)))
        cx = rnd.randrange(-r // 2, 256 + r // 2)
        cy = rnd.randrange(-r // 2, 192 + r // 2)
        caps = [_rand_cap(rnd) for _ in range(rnd.randrange(1, 4))]
        rows, c1, c2 = self.circ_rows(caps, _game_spans(cx, cy, r), (cx, cy, r), rnd.randrange(2))
        self.stat('caps_cap', c1 // len(caps))
        self.stat('caps_rows', (len(rows), c2))
    h = self.stats['caps_cap']
    rr = self.stats['caps_rows']
    return 'pc_circ %d..%d cycles a circle, PC_ROWS %.0f cycles a row' % (min(h), max(h), sum(c for _, c in rr) / max(1, sum(k for k, _ in rr)))


def _pfhook(self, vecs, typ, r, cx, cy, qq2, pos=None):
    """PF_HOOK on the machine for the planet (orientation vecs: nosev, roofv,
    sidev; TYPE typ; radius r; centre cx, cy; seed qq2), checked: A, X, Y,
    the flags and zero page &10-&28 kept, and PF_CLS. Returns (inwk, the
    model's base and circles, the hook's cycles)"""
    rnd, m, mem = self.rnd, self.m, self.m.mem
    inwk = [0] * 36
    for k, v in enumerate(pos or []):       # (the position: x, y, z, sign-magnitude)
        m_ = abs(v)
        inwk[3 * k:3 * k + 3] = [m_ & 255, (m_ >> 8) & 255, ((m_ >> 16) & 0x7F) | (0x80 if v < 0 else 0)]
    for k, v in enumerate(vecs[0] + vecs[1] + vecs[2]):
        inwk[9 + 2 * k], inwk[10 + 2 * k] = _smag(v)
    for k, v in enumerate(inwk):
        mem[MG['INWK'] + k] = v
    for nm, v in (('K3', cx), ('K4', cy), ('K', r)):
        mem[MG[nm]] = v & 255
        mem[MG[nm] + 1] = (v >> 8) & 255
    mem[MG['TYPE']] = typ
    mem[MG['QQ2']:MG['QQ2'] + 6] = qq2
    zp = mem[0x10:0x29]
    a0, x0, y0 = rnd.randrange(256), rnd.randrange(256), rnd.randrange(256)
    m.guard = False
    cyc = m.call(m.syms['PF_HOOK'], a=a0, x=x0, y=y0, bank=7)
    m.guard = True
    mpu = m.mpu
    if (mpu.a, mpu.x, mpu.y, mpu.p & 0xC3) != (a0, x0, y0, 0x24 & 0xC3) or mem[0x10:0x29] != zp:
        raise AssertionError('PF_HOOK did not keep A, X, Y, the flags and zero page &10-&28: %s %s %s'
                             % ((mpu.a, mpu.x, mpu.y, mpu.p), (a0, x0, y0), [(0x10 + k, a_, b_) for k, (a_, b_) in enumerate(zip(mem[0x10:0x29], zp)) if a_ != b_]))
    on = 6 <= r < 256
    base, circs = PCM.pf_records(inwk, qq2, typ) if on else (0, [])
    base, recs = _body(cx, cy, r, base, circs)
    n = sum(1 for c in recs if c is not None and not c['none'])
    k = 0 if typ == 128 else 2 if PCM.pf_banded(qq2) else 1
    if mem[MG['PF_CLS']] != k | (0x80 if (n or base) else 0):
        raise AssertionError('PF_HOOK: PF_CLS %02X (type %d r %d)' % (mem[MG['PF_CLS']], typ, r))
    return inwk, base, recs, n or base, cyc


def _pfrows(self, base, recs, cx, cy, r, what):
    """PC_ROWS after PF_HOOK, against the model"""
    spans = _game_spans(cx, cy, r)
    if not spans:
        return {}, 0
    ndt, ndb, ndl, ndr = _spans_in(self.m, spans)
    c = self.m.call(self.m.syms['PC_ROWS'], bank=7)
    return _check_rows(self.m, PCM.body_rows(base, recs, ndt, ndb, ndl, ndr), ndt, ndb, what), c


def test_merid(self, n):
    """the beach ball: n random meridian planets (radius 6..250, centre on and
    off the screen, any orientation), PF_HOOK then PC_ROWS, bit for bit
    against 6-harness/planet_caps.py; and the rows the same as
    6-harness/planet_analytic.py's (the beach ball's own model before the circle
    engine) pixel for pixel: its boundaries but for equal pairs (where both
    of a row's crossings meet, s = 0, it gave two, and the engine none)"""
    rnd = self.rnd
    self.set_clip((1, 254, 1, 191))
    for i in range(n):
        vecs = _rand_frame(rnd)
        r = rnd.choice((rnd.randrange(6, 40), rnd.randrange(6, 251)))
        cx = rnd.randrange(-r // 2, 256 + r // 2)
        cy = rnd.randrange(-r // 2, 192 + r // 2)
        inwk, base, recs, on, c1 = self._pfhook(vecs, 128, r, cx, cy, [rnd.randrange(256) for _ in range(6)])
        rows, c2 = self._pfrows(base, recs, cx, cy, r, 'beach ball (centre %d,%d r %d)' % (cx, cy, r))
        self.stat('merid_hook', c1)
        self.stat('merid_rows', (len(rows), c2))
        if rows and not any(abs(c) == 1 for c in vecs[1] + vecs[2]):
            # (a component of 1 halves to 0 in pf_tilt, losing its sign: then
            # the circle is edge-on through the centre row, which may differ)
            ndt, ndb, ndl, ndr = _spans_in(self.m, _game_spans(cx, cy, r))
            old = PA.analytic_rows_fixed(cx, cy, r, PA.frame_normals(inwk), ndt, ndb, ndl, ndr)
            odd = lambda v: sorted(set(x for x in v if v.count(x) % 2))
            for y, (xs, p) in rows.items():
                if (p, odd(xs)) != (old[y][0] & 1, odd(old[y][1])):
                    raise AssertionError('beach ball row %d: %s, planet_analytic %s (centre %d,%d r %d, vectors %s)'
                                         % (y, (p, xs), old[y], cx, cy, r, vecs))
    h = self.stats['merid_hook']
    rr = self.stats['merid_rows']
    return 'PF_HOOK %d..%d cycles, PC_ROWS %.0f cycles a row' % (min(h), max(h), sum(c for _, c in rr) / max(1, sum(k for k, _ in rr)))


import planet_analytic as PA                    # noqa: E402  (the beach ball's model, beside this file)


def beach_rows(self, f, spans, cx, cy, rad):
    """test_frames' 'beachball' scenario: this frame's boundaries from
    PF_HOOK and PC_ROWS, for a meridian planet spinning about a random axis,
    written to the disc layer's arrays"""
    st = getattr(self, '_beach', None)
    if st is None or f == 0:
        st = self._beach = dict(vecs=_rand_frame(self.rnd)[:], ax=self.rnd.randrange(3),
                                w=self.rnd.choice((-1, 1)) * self.rnd.uniform(0.01, 0.12))
    st['vecs'] = _rotate(st['vecs'], st['ax'], st['w'])
    r = max(6, min(250, int(rad)))
    inwk, base, recs, on, c1 = self._pfhook(st['vecs'], 128, r, int(cx), int(cy), [0] * 6)
    _spans_in(self.m, spans)
    rows = {}
    if spans:
        ndt, ndb = min(spans), max(spans)
        ndl, ndr = [255] * 192, [0] * 192
        for y, (l, r_) in spans.items():
            ndl[y], ndr[y] = l, r_
        self.m.call(self.m.syms['PC_ROWS'], bank=7)
        rows = _check_rows(self.m, PCM.body_rows(base, recs, ndt, ndb, ndl, ndr), ndt, ndb, 'beachball')
    self.m.wr('R_NDF', 1)
    return rows, 1


def test_pfhook(self, n):
    """PF_HOOK on random crater and meridian planets: the class, the moon, the
    ring, and the rows (PC_ROWS) against the model of its style's circles"""
    rnd, m, mem = self.rnd, self.m, self.m.mem
    self.set_clip((1, 254, 1, 191))
    for i in range(n):
        vecs = _rand_frame(rnd)
        typ = rnd.choice((128, 130, 130))
        r = rnd.choice((rnd.randrange(1, 40), rnd.randrange(6, 251), 300))
        cx = rnd.randrange(-60, 316)
        cy = rnd.randrange(-60, 252)
        qq2 = [rnd.randrange(256) for _ in range(6)]
        if rnd.random() < 0.5:          # (a moon: h bits 0-1 = 1)
            qq2[5] = (qq2[5] & 0xFC) | ((1 ^ qq2[1] ^ qq2[3]) & 3)
        if rnd.random() < 0.4:          # (a ring: h bits 4-6 = 4)
            qq2[5] = (qq2[5] & 0x8F) | ((0x40 ^ qq2[1] ^ qq2[3]) & 0x70)
        pz = rnd.randrange(24576 * 256 // max(r, 1) // 2, 24576 * 256 // max(r, 1) * 2 + 1)
        pz = min(pz, (1 << 23) - 1)
        pos = [max(-(1 << 23) + 1, min((1 << 23) - 1, c)) for c in
               ((cx - 128) * pz // 256 + rnd.randrange(-300, 301), (96 - cy) * pz // 256 + rnd.randrange(-300, 301), pz)]
        mem[MG['FRIN'] + 1] = rnd.choice((129, 2))
        k1 = MG['K%'] + 37
        sz = rnd.randrange(1 << 23)
        mem[k1 + 6], mem[k1 + 7], mem[k1 + 8] = sz & 255, (sz >> 8) & 255, (sz >> 16) | rnd.choice((0, 0, 0x80))
        # the moon's place (MN_E, MN_TURN's: the coordinates, up to 5.25 radii
        # out on each axis; or unknown, MN_OK clear) and the view
        E = None if rnd.random() < 0.1 else [rnd.randrange(-129024, 129025) for _ in range(3)]
        view = rnd.randrange(4)
        mem[MG['VIEW']] = view
        mem[self.m.syms['MN_OK']] = 0 if E is None else 0xFF
        for j, v in enumerate(E or [0, 0, 0]):
            v &= 0xFFFFFF
            mem[self.m.syms['MN_E'] + 3 * j:self.m.syms['MN_E'] + 3 * j + 3] = [v & 255, (v >> 8) & 255, v >> 16]
        inwk, base, recs, on, c1 = self._pfhook(vecs, typ, r, cx, cy, qq2, pos)
        self._check_moon(inwk, qq2, typ, cx, cy, r, E, view)
        if on:
            self._pfrows(base, recs, cx, cy, r, 'PF_HOOK (type %d centre %d,%d r %d)' % (typ, cx, cy, r))
    return '%d moons, %d rings' % (len(self.stats.get('moons', [])), len(self.stats.get('rings', [])))


def _check_moon(self, inwk, qq2, typ, cx, cy, r, E=None, view=0):
    """PF_HOOK's moon (MN_ON ...) against the model's, and its crater's rows
    (PC_MROWS) on its disc"""
    m, mem = self.m, self.m.mem
    pz = mem[MG['INWK'] + 6] | (mem[MG['INWK'] + 7] << 8) | ((mem[MG['INWK'] + 8] & 0x7F) << 16)
    sunz = None
    if mem[MG['FRIN'] + 1] == 129 and not mem[MG['K%'] + 37 + 8] & 0x80:
        k = MG['K%'] + 37
        sunz = mem[k + 6] | (mem[k + 7] << 8) | (mem[k + 8] << 16)
    want = PCM.pf_moon(inwk, qq2, cx, cy, r, pz, sunz, E, view) if 6 <= r < 256 else None
    s = m.syms
    ring = (PCM.pf_ring(inwk, qq2, cx, cy, r) if 6 <= r < 256 else None) or []
    n = mem[s['RG_N']] if RINGS else 0
    got = [(mem[s['RG_X'] + i], mem[s['RG_Y'] + i], bool(mem[s['RG_F'] + i] & 0x80)) for i in range(n)]
    if sorted(got) != sorted(ring):
        raise AssertionError('PF_HOOK ring: %s, the model %s (r %d)' % (got[:6], ring[:6], r))
    if ring:
        self.stat('rings', 1)
    on = mem[s['MN_ON']]
    if want is None:
        if on & 0x80:
            raise AssertionError('PF_HOOK: a moon the model has not (r %d)' % r)
        return
    w16 = lambda a: (mem[a] | (mem[a + 1] << 8)) - (0x10000 if mem[a + 1] & 0x80 else 0)
    got = dict(on=on, x=w16(s['MN_X']), y=w16(s['MN_Y']), r=mem[s['MN_R']], z16=mem[s['MN_Z']] | (mem[s['MN_Z'] + 1] << 8))
    exp = dict(on=0x80 | (0x40 if want['behind'] else 0) | (0x20 if want['behindsun'] else 0), x=want['x'], y=want['y'], r=want['r'], z16=want['z16'])
    if got != exp:
        raise AssertionError('PF_HOOK moon: %s, the model %s' % (got, exp))
    self.stat('moons', 1)
    if want['cap'] is None:
        return
    mx, my, mr = want['x'], want['y'], want['r']
    spans = _game_spans(mx, my, mr)
    if not spans:
        return
    ndt, ndb, ndl, ndr = _spans_in(m, spans)
    m.call(s['PC_MROWS'], bank=7)
    base, recs = _body(mx, my, mr, 0, [want['cap']])
    _check_rows(m, PCM.body_rows(base, recs, ndt, ndb, ndl, ndr), ndt, ndb, 'PC_MROWS')


def cap_rows(self, f, spans, cx, cy, rad):
    """test_frames' 'capball' scenario: this frame's boundaries from the caps of a
    planet spinning about a random axis, written to the disc layer's arrays"""
    st = getattr(self, '_capst', None)
    if st is None or f == 0:
        st = self._capst = dict(vecs=_rand_frame(self.rnd)[:], ax=self.rnd.randrange(3),
                                w=self.rnd.choice((-1, 1)) * self.rnd.uniform(0.01, 0.12),
                                cs=[(self.rnd.randrange(3), self.rnd.randrange(150, 256), self.rnd.random() < 0.2)
                                    for _ in range(self.rnd.randrange(1, 4))])
    st['vecs'] = _rotate(st['vecs'], st['ax'], st['w'])
    r = max(6, min(250, int(rad)))
    caps = [([tuple(_smag(x // 2)) for x in st['vecs'][k]], c8, cn, 10923) for k, c8, cn in st['cs']]
    rows, c1, c2 = self.circ_rows(caps, spans, (int(cx), int(cy), r))
    self.m.wr('R_NDF', 1)
    return rows, 1


def test_kept(self, nframes, scenario='station'):
    """K mode (the kept solid rows: gfx-raster_kept.asm, gfx-kept7.asm) over
    multi-frame sequences on two buffers, as the frame layer drives it: each
    frame T_KFRAME's set-up (KMODE, KBIT, KBITN, KPLO/KPHI, k_setbuf7), the
    disc layer (with its repair), a "station" (two big faces sharing an edge,
    filling whole rows, and a slot polygon over one, drifting a pixel or two a
    frame, their colours mostly kept), small ships, lines and dots (each with
    its trampoline's k_kill first), R_MARKDIRTY (k_kill), then k_commit after
    the ships; sometimes K mode off (k_clear) or a reset buffer.  After each
    frame the buffer must equal the reference: [disc over black, polys, lines,
    dots], exactly as without K mode."""
    m, rnd = self.m, self.rnd
    import math
    Ref, poly_spans, random_poly = tr.Ref, tr.poly_spans, tr.random_poly
    self.set_clip((2, 253, 1, 191))
    bufs = [None, None]
    for b in range(2):
        m.call('R_SETBUF', a=b)
        m.clearall()
        bufs[b] = m.screen()
    m.call('k_clear')
    outside = list(bufs)
    kon = True
    cx, cy = rnd.uniform(80, 176), rnd.uniform(60, 130)
    w, h, ang = rnd.uniform(150, 600), rnd.uniform(120, 500), rnd.uniform(-0.3, 0.3)
    cols = [(rnd.randrange(1, 256), rnd.randrange(1, 256)) for _ in range(3)]
    disc = scenario == 'sun'
    kept = 0
    for f in range(nframes):
        b = f & 1
        m.set_screen(bufs[b])
        m.call('R_SETBUF', a=b)
        if rnd.random() < 0.05:                       # K mode off for a while (T_KOFF)
            kon = not kon
            if not kon:
                m.wr('KMODE', 0)
                m.call('k_clear')
        if kon:                                       # T_KFRAME
            m.wr('KMODE', 0x80)
            m.wr('KBIT', 1 << b)
            m.wr('KBITN', 0xFF ^ (1 << b))
            m.wr('KPLO', 0xFF)
            m.wr('KPHI', 0)
            m.call('k_setbuf7', a=b, bank=7)
        if rnd.random() < 0.02:                       # a reset buffer (T_RESETBUF)
            r = Ref(bufs[b], self.clip)
            r.blackwin()
            m.set_screen(bytes(r.b))
            m.call('R_RESETBUF')
            m.call('k_clear')
            outside[b] = m.screen()
        def kill(y0, y1):
            y0, y1 = max(0, y0), min(191, y1)
            if kon and y0 <= y1:
                m.call('k_kill', a=y0, x=y1)
        if rnd.random() < 0.3:                        # a text cell's mark (f_text1's)
            y = rnd.randrange(1, 192)
            kill(y, y)
            m.wzp('R_XL', rnd.randrange(2, 200))
            m.wzp('R_XR', min(253, m.mem[tr.ZP['R_XL']] + rnd.randrange(0, 50)))
            m.call('R_MARKDIRTY', y=y)
        spans = {}
        if disc and (f // 6) % 2 == 0:
            dcx, dcy, rad = 128 + 60 * math.sin(f / 5), 96 + 40 * math.cos(f / 7), 30
            for y in range(1, 192):
                dy = y + 0.5 - dcy
                if abs(dy) < rad:
                    hh = math.sqrt(rad * rad - dy * dy)
                    l, r = max(2, int(cx - hh)), min(253, int(cx + hh))
                    if l <= r:
                        spans[y] = (l, r)
        m.wr('R_NDT', min(spans) if spans else 255)
        m.wr('R_NDB', max(spans) if spans else 0)
        for y, (l, r) in spans.items():
            m.wr('R_NDISCL', l, y)
            m.wr('R_NDISCR', r, y)
        m.wr('R_NDF', 0)
        m.wzp('R_DCE', 0x5A)
        m.wzp('R_DCO', 0xA5)
        m.call('R_DISCROWS')
        ref = Ref(outside[b], self.clip)
        ref.blackwin()
        for y, (l, r) in spans.items():
            ref.span(y, l, r, 0x5A, 0xA5)
        # the station: two faces sharing an edge, a slot over the first
        if (f // 8) % 4 != 1:                         # (and stretches holding still)
            cx += rnd.uniform(-2, 2)
            cy += rnd.uniform(-2, 2)
            w *= rnd.uniform(0.98, 1.04)
            h *= rnd.uniform(0.98, 1.04)
            ang += rnd.uniform(-0.02, 0.02)
        if rnd.random() < 0.05:
            cols[rnd.randrange(3)] = (rnd.randrange(0, 256), rnd.randrange(0, 256))
        ca, sa = math.cos(ang), math.sin(ang)
        def pt(u, v):
            return (int(round(cx + u * ca - v * sa)), int(round(cy + u * sa + v * ca)))
        mid = rnd.uniform(-0.1, 0.1)
        faces = [[pt(-w, -h), pt(mid * w, -h), pt(mid * w, h), pt(-w, h)],
                 [pt(mid * w, -h), pt(w, -h), pt(w, h), pt(mid * w, h)]]
        order = [0, 1] if f % 3 else [1, 0]
        items = [(faces[i], cols[i]) for i in order]
        if (f // 10) % 3 != 2:              # (mostly one face filling whole rows)
            items = [([pt(-w, -h), pt(w, -h), pt(w, h), pt(-w, h)], cols[0])]
        if rnd.random() < 0.7:
            sw, sh = rnd.uniform(10, 40), rnd.uniform(5, 30)
            items.append(([pt(-sw, -sh), pt(sw, -sh), pt(sw, sh), pt(-sw, sh)], cols[2]))
        for _ in range(rnd.randrange(0, 3)):
            vs = random_poly(rnd, rnd.choice(['small', 'tiny', 'edge', 'screen']))
            items.insert(rnd.randrange(len(items) + 1), (vs, (rnd.randrange(256), rnd.randrange(256))))
        for vs, (ce, co) in items:
            if rnd.random() < 0.15:                   # a line among the ships (f_item's)
                pts = [rnd.randrange(-20, 276), rnd.randrange(-20, 212), rnd.randrange(-20, 276), rnd.randrange(-20, 212)]
                lc = rnd.randrange(256)
                kill(min(pts[1], pts[3]), max(pts[1], pts[3]))
                self.draw_line(*pts, lc, lc)
                for x, y in tr.line_pixels(*pts):
                    if ref.inwin(x, y):
                        ref.setpix(x, y, lc, lc)
            self.draw_poly(vs, ce, co)
            for y, (l, r) in poly_spans(vs, self.clip).items():
                ref.span(y, l, r, ce, co)
        if kon:
            m.call('k_commit')
            kept += sum(1 for y in range(192) if m.rd('KF', y) & (1 << b))
        for _ in range(rnd.randrange(0, 3)):          # dots, after the ships
            x, y, sz = rnd.randrange(256), rnd.randrange(256), rnd.randrange(1, 4)
            ce, co = rnd.randrange(256), rnd.randrange(256)
            if kon and y < 192:
                kill(y, min(191, y + 1))
            self.set_col(ce, co)
            m.call('R_DOT', a=sz, x=x, y=y)
            for px, py in tr.dot_pixels(x, y, sz):
                if ref.inwin(px, py):
                    ref.setpix(px, py, ce, co)
        got = m.screen()
        if got != bytes(ref.b):
            diff = [i for i in range(0x3000) if got[i] != ref.b[i]]
            a = diff[0]
            y = (a // 0x200) * 8 + (a & 7)
            rows = sorted(set((d // 0x200) * 8 + (d & 7) for d in diff))
            raise AssertionError('kept frame %d (buf %d): %d bytes differ, first row %d col %d; rows %s'
                                 % (f, b, len(diff), y, (a % 0x200) // 8, rows[:12]))
        bufs[b] = got
    m.wr('KMODE', 0)
    m.call('k_clear')
    self.set_clip((1, 254, 1, 191))     # (as the other tests expect)
    return '%.1f rows kept a frame' % (kept / max(1, nframes))


tr.Tester.test_kept = test_kept

tr.Tester.circ_rows = circ_rows
tr.Tester._pfhook = _pfhook
tr.Tester._pfrows = _pfrows

def test_disc2(self, nframes, scenario='both'):
    """The second disc (R_DISC2, gfx-raster_disc2.asm) over multi-frame
    sequences on two buffers, as the frame layer drives it: each frame the
    disc layer (the bigger disc, R_DISCROWS; a colour change folds the old
    layer into DIRTY first, as f_discdirty does), then the smaller one behind
    it (R_DISC2, its spans in R_NDISCL/R; with none, called while the buffer
    still holds one), then ships, lines and dots (each with its trampoline's
    k_kill in K mode, and k_commit after the ships), and the stars.  The two
    discs drift, grow and shrink, cross so that the bigger one changes (the
    colours swap), come and go, and jump; sometimes a buffer is reset.  After
    each frame the buffer must equal the reference [the layer over black, the
    second disc's spans less the layer's on each row, ships, lines, dots,
    stars], and every changed pixel must lie in R_WL/R_WR or DIRTY (or be a
    star's).  scenario: 'both' (K mode off) or 'kept' (K mode on, mostly)."""
    m, rnd = self.m, self.rnd
    import math
    Ref, poly_spans, random_poly = tr.Ref, tr.poly_spans, tr.random_poly
    self.set_clip((2, 253, 1, 191))
    clip = self.clip
    bufs = [None, None]
    for b in range(2):
        m.call('R_SETBUF', a=b)
        m.clearall()
        bufs[b] = m.screen()
    outside = list(bufs)
    kept = scenario == 'kept'
    kon = kept
    if 'KMODE' in m.syms:
        m.wr('KMODE', 0)
        m.call('k_clear')
    SUN, PLA = (0xFF, 0xFA), (0x05, 0x5A)
    # two discs: (cx, cy, r, vx, vy, vr, colours)
    def newdisc(big):
        r = rnd.uniform(40, 130) if big else rnd.uniform(3, 40)
        return [rnd.uniform(-20, 276), rnd.uniform(-20, 212), r,
                rnd.uniform(-3, 3), rnd.uniform(-3, 3), rnd.uniform(-1.5, 1.5)]
    pl, su = newdisc(True), newdisc(False)
    if rnd.random() < 0.5:          # the sun near the planet's limb
        a = rnd.uniform(0, 2 * math.pi)
        su[0], su[1] = pl[0] + pl[2] * math.cos(a), pl[1] + pl[2] * math.sin(a)
    ships = [(rnd.uniform(0, 256), rnd.uniform(0, 192), rnd.uniform(-3, 3), rnd.uniform(-3, 3)) for _ in range(rnd.randrange(0, 4))]
    stars = [(rnd.randrange(256), rnd.randrange(192), rnd.randrange(1, 4)) for _ in range(rnd.randrange(0, tr.NSTARS + 1))]
    lcol = [None, None]
    oldstars = [set(), set()]
    m.wr('R_NDF', 0)
    m.wr('R_SCOL', 0xFF)

    def spans_of(d):
        cx, cy, r = d[0], d[1], d[2]
        sp = {}
        for y in range(clip[2], clip[3] + 1):
            dy = y + 0.5 - cy
            if abs(dy) < r:
                h = math.sqrt(r * r - dy * dy)
                l, rr = max(int(math.floor(cx - h)), clip[0]), min(int(math.floor(cx + h)), clip[1])
                if l <= rr:
                    sp[y] = (l, rr)
        return sp

    def put_spans(sp):
        ndt, ndb = (min(sp), max(sp)) if sp else (rnd.choice((1, 255)), 0)
        m.wr('R_NDT', ndt)
        m.wr('R_NDB', ndb)
        for y in range(ndt, ndb + 1) if sp else []:
            l, r = sp.get(y, (255, 0))
            m.wr('R_NDISCL', l, y)
            m.wr('R_NDISCR', r, y)

    def kill(y0, y1):
        y0, y1 = max(0, y0), min(191, y1)
        if kon and y0 <= y1:
            m.call('k_kill', a=y0, x=y1)
    cyc = []
    for f in range(nframes):
        b = f & 1
        m.set_screen(bufs[b])
        m.call('R_SETBUF', a=b)
        if kept and rnd.random() < 0.05:
            kon = not kon
            if not kon:
                m.wr('KMODE', 0)
                m.call('k_clear')
        if kon:                                       # T_KFRAME
            m.wr('KMODE', 0x80)
            m.wr('KBIT', 1 << b)
            m.wr('KBITN', 0xFF ^ (1 << b))
            m.wr('KPLO', 0xFF)
            m.wr('KPHI', 0)
            m.call('k_setbuf7', a=b, bank=7)
        if rnd.random() < 0.03:                       # a reset buffer (T_RESETBUF)
            r = Ref(bufs[b], clip)
            r.blackwin()
            m.set_screen(bytes(r.b))
            m.call('R_RESETBUF')
            if 'k_clear' in m.syms:
                m.call('k_clear')
            outside[b] = bufs[b] = m.screen()
            lcol[b] = None
            oldstars[b] = set()
        if rnd.random() < 0.2:                        # a text cell's mark (f_text1's)
            y = rnd.randrange(1, 192)
            kill(y, y)
            m.wzp('R_XL', rnd.randrange(2, 200))
            m.wzp('R_XR', min(253, m.mem[tr.ZP['R_XL']] + rnd.randrange(0, 50)))
            m.call('R_MARKDIRTY', y=y)
        m.call('R_STARERASE')
        # the discs: which is on, which is bigger
        on_p = (f // 9) % 5 != 3
        on_s = (f // 7) % 6 != 4
        if rnd.random() < 0.03:
            pl = newdisc(rnd.random() < 0.8)
        if rnd.random() < 0.03:
            su = newdisc(rnd.random() < 0.2)
        discs = []                                    # the bigger one is the layer
        if on_p:                                      # (f_discs: the sun's on a tie)
            discs.append((spans_of(pl), PLA, pl[2]))
        if on_s:
            discs.append((spans_of(su), SUN, su[2] + 1e-9))
        discs.sort(key=lambda d: -d[2])
        lay = discs[0] if discs else None
        sec = discs[1] if len(discs) > 1 else None
        # the layer (with the caller's colour change: the old disc into DIRTY)
        put_spans(lay[0] if lay else {})
        lc = lay[1] if lay else None
        if lcol[b] is not None and lcol[b] != lc:
            for y in range(192):
                l = m.rd('R_DISCL0', y + 0x300 * b)
                r = m.rd('R_DISCR0', y + 0x300 * b)
                if l <= r:
                    m.wzp('R_XL', l)
                    m.wzp('R_XR', r)
                    m.call('R_MARKDIRTY', y=y)
        lcol[b] = lc
        m.wzp('R_DCE', lc[0] if lc else 0)
        m.wzp('R_DCO', lc[1] if lc else 0)
        m.call('R_DISCROWS')
        # the second disc
        if sec or m.rd('R_S2T', b) != 255:
            put_spans(sec[0] if sec else {})
            ndt, ndb = m.rd('R_NDT'), m.rd('R_NDB')      # (f_disc2's: the old rows too,
            t0, b0 = m.rd('R_S2T', b), m.rd('R_S2B', b)   # empty outside the new)
            for y in range(min(t0, ndt), max(b0, ndb) + 1):
                if not ndt <= y <= ndb:
                    m.wr('R_NDISCL', 255, y)
                    m.wr('R_NDISCR', 0, y)
            if sec:
                self.set_col(*sec[1])
            if os.environ.get('RDEBUG'):
                _y = int(os.environ.get('RROW', '0'))
                _pre = (m.rd('R_S2L1' if b else 'R_S2L0', _y), m.rd('R_S2R1' if b else 'R_S2R0', _y), m.rd('R_WL', _y), m.rd('R_WR', _y),
                        m.rd('R_DISCL0', _y + 0x300 * b), m.rd('R_DISCR0', _y + 0x300 * b), m.rd('R_NDISCL', _y), m.rd('R_NDISCR', _y))
                print('frame', f, 'row', _y, 'old a,b W layer new', _pre)
            cyc.append(m.call('R_DISC2'))
        ref = Ref(outside[b], clip)
        ref.blackwin()
        lsp = lay[0] if lay else {}
        for y, (l, r) in lsp.items():
            ref.span(y, l, r, *lay[1])
        if sec:
            for y, (l, r) in sec[0].items():
                L, R = lsp.get(y, (255, 0))
                for x in range(l, r + 1):
                    if not L <= x <= R:
                        ref.setpix(x, y, *sec[1])
        wt, wb = m.rd('R_PRWT'), m.rd('R_PRWB')
        for y in range(192):
            if m.rd('R_WR', y) and not wt <= y <= wb:
                raise AssertionError('disc2 frame %d: R_WR[%d] set outside the WL rows %d..%d' % (f, y, wt, wb))
        # ships, a line, dots
        newships = []
        for (sx, sy, svx, svy) in ships:
            sx, sy = sx + svx, sy + svy
            if not (-40 < sx < 296 and -40 < sy < 232):
                sx, sy = rnd.uniform(0, 256), rnd.uniform(0, 192)
            newships.append((sx, sy, svx, svy))
            for t in range(rnd.randrange(1, 3)):
                vs = random_poly(rnd, 'small')
                vs = [(x - vs[0][0] + int(sx), y - vs[0][1] + int(sy)) for x, y in vs]
                ce, co = rnd.randrange(256), rnd.randrange(256)
                self.draw_poly(vs, ce, co)
                for y, (l, r) in poly_spans(vs, clip).items():
                    ref.span(y, l, r, ce, co)
        ships = newships
        if rnd.random() < 0.3:
            pts = [rnd.randrange(-20, 276), rnd.randrange(-20, 212), rnd.randrange(-20, 276), rnd.randrange(-20, 212)]
            lc_ = rnd.randrange(256)
            kill(min(pts[1], pts[3]), max(pts[1], pts[3]))
            self.draw_line(*pts, lc_, lc_)
            for x, y in tr.line_pixels(*pts):
                if ref.inwin(x, y):
                    ref.setpix(x, y, lc_, lc_)
        if kon:
            m.call('k_commit')
        for _ in range(rnd.randrange(0, 3)):
            x, y, sz = rnd.randrange(256), rnd.randrange(256), rnd.randrange(1, 4)
            ce, co = rnd.randrange(256), rnd.randrange(256)
            if kon and y < 192:
                kill(y, min(191, y + 1))
            self.set_col(ce, co)
            m.call('R_DOT', a=sz, x=x, y=y)
            for px, py in tr.dot_pixels(x, y, sz):
                if ref.inwin(px, py):
                    ref.setpix(px, py, ce, co)
        # the stars, last
        stars = [((x + rnd.randrange(-2, 3)) & 255, min(255, max(0, y + rnd.randrange(-2, 3))), s_) for x, y, s_ in stars]
        m.wr('R_SN', len(stars))
        for i, (x, y, s_) in enumerate(stars):
            m.wr('R_SX', x, i)
            m.wr('R_SY', y, i)
            m.wr('R_SS', s_, i)
        m.call('R_STARPLOT')
        pre = bytes(ref.b)
        for x, y, s_ in stars:
            tr.star_ref(ref, x, y, s_, 0xFF)
        starpix = set()
        for a in range(0x3000):
            if pre[a] != ref.b[a]:
                for p_ in range(4):
                    if (pre[a] ^ ref.b[a]) & (0x88 >> p_):
                        starpix.add((4 * ((a % 0x200) // 8) + p_, (a // 0x200) * 8 + (a & 7)))
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
            raise AssertionError('disc2 frame %d (%s, buf %d): %d bytes differ, first row %d col %d; rows %s'
                                 % (f, scenario, b, len(diff), y, (a % 0x200) // 8, rows[:12]))
        old = bufs[b]
        dirt = self.dirty(b)
        wl2 = [(m.rd('R_WL', y), m.rd('R_WR', y)) for y in range(192)]
        for a in range(0x3000):
            if got[a] != old[a]:
                y = (a // 0x200) * 8 + (a & 7)
                c = (a % 0x200) // 8
                for p_ in range(4):
                    x = 4 * c + p_
                    if (got[a] ^ old[a]) & (0x88 >> p_):
                        ok = (wl2[y][1] and wl2[y][0] <= x <= wl2[y][1]) or (dirt[y][0] <= x <= dirt[y][1]) \
                            or (x, y) in starpix or (x, y) in oldstars[b]
                        if not ok:
                            raise AssertionError('disc2 frame %d: pixel %d,%d changed outside WL/DIRTY' % (f, x, y))
        bufs[b] = got
        oldstars[b] = starpix
        for d in (pl, su):                            # move the discs
            d[0] += d[3]
            d[1] += d[4]
            d[2] = min(200, max(0.5, d[2] + d[5]))
            if rnd.random() < 0.05:
                d[3], d[4], d[5] = rnd.uniform(-3, 3), rnd.uniform(-3, 3), rnd.uniform(-1.5, 1.5)
            if rnd.random() < 0.02:                   # a jump (the view turned)
                d[0], d[1] = d[0] + rnd.uniform(-80, 80), d[1] + rnd.uniform(-60, 60)
    if 'KMODE' in m.syms:
        m.wr('KMODE', 0)
        m.call('k_clear')
    self.set_clip((1, 254, 1, 191))     # (as the other tests expect)
    return 'R_DISC2 mean %d cycles' % (sum(cyc) // max(1, len(cyc)))


tr.Tester.test_disc2 = test_disc2

tr.Tester.test_merid = test_merid
tr.Tester.beach_rows = beach_rows
tr.Tester.test_caps = test_caps
tr.Tester.test_pfhook = test_pfhook
tr.Tester._check_moon = _check_moon
tr.Tester.cap_rows = cap_rows
if os.path.exists(MERID):
    tr.EXTRA += [('merid', 'test_merid', 400, ()), ('beachball', 'test_frames', 44, ('beachball',)),
                 ('beachball', 'test_frames', 44, ('beachball',))]

if KEPT:     # (after the meridian tests, which keep the random numbers they had)
    tr.EXTRA += [('kept', 'test_kept', 120, ('station',)), ('kept', 'test_kept', 120, ('sun',))] * 3

if CAPS:     # (after the rest, which keep the random numbers they had)
    tr.EXTRA += [('caps', 'test_caps', 400, ()), ('pfhook', 'test_pfhook', 200, ()),
                 ('capball', 'test_frames', 44, ('capball',)), ('capball', 'test_frames', 44, ('capball',))]

if HASD2:    # (after the others, which keep the random numbers they had)
    tr.EXTRA += [('disc2', 'test_disc2', 80, ('both',)), ('disc2', 'test_disc2', 80, ('kept',))] * 3

tr.assemble = assemble
tr.Tester.test_lines = test_lines
_demo_check_patch_sites = tr.check_patch_sites
tr.check_patch_sites = check_patch_sites
tr.Machine = Machine
tr.Tester.set_col = set_col
tr.Tester.draw_line = draw_line
tr.star_ref = star_ref

if __name__ == '__main__':
    tr.main()
