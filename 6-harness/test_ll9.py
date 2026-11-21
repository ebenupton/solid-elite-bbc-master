#!/usr/bin/env python3
"""LL9's arithmetic, one build against another, on py65 (65C02).

    python3 6-harness/test_ll9.py REFDIR [--n 2000] [--seed 1] [--tree DIR]

REFDIR holds a reference build's BCODE.unprot.bin, HICODE.bin, BANK4.bin,
HZDATA.bin and symbols.txt (3-assembled-output of a build whose LL9 is
trusted); the candidate is this tree's 3-assembled-output (or --tree's).
Both are loaded as the game has them (main RAM from CODE%, the quarter
squares and the hot pass at &7000, bank 4 at &8000, the blueprints in HAZEL
at &C000; a build with LL21I runs it first, as BEGIN does) and run on the
same random ships, of every type with faces:

  * parts 3 to 5, from LL10 (the ship is in the view cone) to LL42: the
    orientation vectors scaled (XX16), the distance (XX4) and each face's
    visibility (XX2), which must be equal, or to SHPPT (the ship is a dot),
    with the same ships;
  * parts 6 to 8, from LL42P to LL72, on the reference's state at LL42
    (so the two builds' parts are compared separately): the vertices'
    screen coordinates on the heap (XX3) and their count (CNT).

The temporaries the parts leave (P, Q, R, S, T, U, XX12, XX15 ...) are not
compared: the gate's run compares the game state. Exit status 0 only if
every ship gives the same results; prints the cycles each build took.
"""
import math, os, random, re, sys
from py65.devices.mpu65c02 import MPU

HERE = os.path.dirname(os.path.abspath(__file__))
RET = 0xFFF0


def load(d, srcdir):
    out = os.path.join(d, '3-assembled-output') if os.path.isdir(os.path.join(d, '3-assembled-output')) else d
    sy = {k: int(v) for k, v in re.findall(r"'([^']+)':(-?\d+)L?", open(os.path.join(out, 'symbols.txt')).read())}
    src = os.path.join(srcdir, '1-source-files', 'main-sources', 'elite-source.asm')
    code = int(re.search(r'^\s*CODE%\s*=\s*&([0-9A-Fa-f]+)', open(src).read(), re.M).group(1), 16)
    mem = [0] * 0x10000
    rd = lambda n: list(open(os.path.join(out, n), 'rb').read())
    b = rd('BCODE.unprot.bin')
    mem[code:code + len(b)] = b
    for n, a in (('HICODE.bin', 0x7000), ('BANK4.bin', 0x8000), ('HZDATA.bin', 0xC000)):
        b = rd(n)
        mem[a:a + len(b)] = b
    return sy, mem


class Run:
    def __init__(self, sy, mem):
        self.sy, self.image = sy, mem
        self.mpu = MPU()
        if 'LL21I' in sy:       # (BEGIN's: the table of part 3's scaling)
            self.image = self.go([0] * 256, [0] * 256, 'LL21I', ())[1]
            self.image[0:0x200] = [0] * 0x200

    def go(self, zp, page1, start, stops, extra=()):
        """the image with zero page zp (and page 1), run from start to one of
        stops (labels) or the return: (stop, memory, cycles)"""
        sy, mpu = self.sy, self.mpu
        mem = self.image[:]
        mem[0:0x100] = zp
        mem[0x100:0x200] = page1
        for a, v in extra:
            mem[a] = v
        mpu.memory = mem
        mpu.a = mpu.x = mpu.y = 0
        mpu.p = 0x24
        mpu.sp = 0xFD
        mem[0x1FF], mem[0x1FE] = (RET - 1) >> 8, (RET - 1) & 255
        mpu.pc = sy[start]
        st = {sy[s]: s for s in stops}
        st[RET] = 'return'
        c0 = mpu.processorCycles
        n = 0
        while mpu.pc not in st:
            mpu.step()
            n += 1
            if n > 400000:
                raise RuntimeError('runaway from %s at &%04X' % (start, mpu.pc))
        return st[mpu.pc], mem, mpu.processorCycles - c0


def sm16(v):
    m = min(abs(int(v)), 0x7FFF)
    return [m & 255, (m >> 8) | (0x80 if v < 0 else 0)]


def sm24(v):
    m = abs(int(v))
    return [m & 255, (m >> 8) & 255, ((m >> 16) & 0x7F) | (0x80 if v < 0 else 0)]


def rand_ship(rnd, sy, mem, types):
    """a ship in front of us: zero page (XX0, INWK, NEWB ...) as LL9 has it at LL10"""
    zp = [rnd.randrange(256) for _ in range(256)]
    t = rnd.choice(types)
    bp = mem[sy['XX21'] + 2 * (t - 1)] | (mem[sy['XX21'] + 2 * (t - 1) + 1] << 8)
    zp[sy['XX0']], zp[sy['XX0'] + 1] = bp & 255, bp >> 8
    zp[sy['TYPE']] = t
    z = int(rnd.choice((rnd.uniform(200, 3000), rnd.uniform(200, 0xBF00), rnd.uniform(200, 800))))
    f = rnd.choice((0.2, 0.9, 1.0))
    x, y = int(rnd.uniform(-z, z) * f), int(rnd.uniform(-z, z) * f)
    # a random rotation, its rows the ship's nosev, roofv and sidev at 96 a unit
    a, b, c = (rnd.uniform(0, 2 * math.pi) for _ in range(3))
    ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    R = [[cb * cc, -cb * sc, sb], [sa * sb * cc + ca * sc, -sa * sb * sc + ca * cc, -sa * cb],
         [-ca * sb * cc + sa * sc, ca * sb * sc + sa * cc, ca * cb]]
    if rnd.random() < 0.3:      # (the game's vectors are axis-aligned at spawn)
        R = rnd.choice(([[1, 0, 0], [0, 1, 0], [0, 0, 1]], [[0, 0, -1], [0, 1, 0], [-1, 0, 0]], [[0, 1, 0], [-1, 0, 0], [0, 0, 1]]))
    inwk = sm24(x) + sm24(y) + sm24(z)
    for row in R:
        for v in row:
            inwk += sm16(v * 0x6000 + rnd.uniform(-200, 200))
    inwk += [rnd.randrange(32), rnd.randrange(256), rnd.randrange(256), rnd.randrange(256), rnd.randrange(256)]
    inwk += [rnd.choice((0, 0x08, 0x40, 0x48, 0x10))]      # byte #31: not exploding, not killed
    inwk += [rnd.randrange(256)] * 4
    for k in range(36):
        zp[sy['INWK'] + k] = inwk[k]
    zp[sy['NEWB']] = rnd.randrange(128)
    zp[sy['XX19']], zp[sy['XX19'] + 1] = 0x00, 0x05         # (the ship line heap: not used here)
    zp[sy['INF']], zp[sy['INF'] + 1] = 0x00, 0x06
    return zp


def main():
    args = sys.argv[1:]
    opt = lambda n, d: (args[args.index(n) + 1] if n in args else d)
    ref = args[0]
    tree = opt('--tree', os.path.dirname(HERE))
    n, seed = int(opt('--n', 2000)), int(opt('--seed', 1))
    A, B = Run(*load(ref, tree)), Run(*load(tree, tree))      # (CODE% from this tree's source for both)
    rnd = random.Random(seed)
    sy = A.sy
    # the ship types with a blueprint (not the planet's or the sun's slots)
    types = [t for t in range(1, 34) if (A.image[sy['XX21'] + 2 * (t - 1)] | (A.image[sy['XX21'] + 2 * (t - 1) + 1] << 8)) >= 0xC000]
    cyc = {'A35': 0, 'B35': 0, 'A68': 0, 'B68': 0}
    drawn = dots = verts = 0
    for i in range(n):
        zp = rand_ship(rnd, sy, A.image, types)
        p1 = [rnd.randrange(256) for _ in range(256)]
        ra = A.go(zp, p1, 'LL10', ('LL42', 'SHPPT', 'LL14'))
        rb = B.go(zp, p1, 'LL10', ('LL42', 'SHPPT', 'LL14'))
        if ra[0] != rb[0]:
            raise SystemExit('ship %d: the reference stops at %s, the build at %s' % (i, ra[0], rb[0]))
        if ra[0] != 'LL42':
            dots += 1
            continue
        drawn += 1
        cyc['A35'] += ra[2]
        cyc['B35'] += rb[2]
        for nm, ln in (('XX2', 16), ('XX16', 18), ('XX4', 1), ('XX0', 2), ('INWK', 36)):
            va = ra[1][A.sy[nm]:A.sy[nm] + ln]
            vb = rb[1][B.sy[nm]:B.sy[nm] + ln]
            if va != vb:
                raise SystemExit('ship %d (type %d) parts 3-5: %s differs\n  ref   %s\n  build %s' % (i, zp[sy['TYPE']], nm, va, vb))
        if ra[1][A.sy['GFAR']] != rb[1][B.sy['GFAR']]:
            raise SystemExit('ship %d parts 3-5: GFAR differs' % i)
        # parts 6 to 8, both from the reference's state at LL42
        zp2, p2 = ra[1][0:0x100], ra[1][0x100:0x200]
        sa = A.go(zp2, p2, 'LL42P', ('LL72',))
        sb = B.go(zp2, p2, 'LL42P', ('LL72',))
        cyc['A68'] += sa[2]
        cyc['B68'] += sb[2]
        if sa[0] != 'LL72' or sb[0] != 'LL72':
            raise SystemExit('ship %d parts 6-8: stopped at %s, %s' % (i, sa[0], sb[0]))
        # (page 1 below the stack's top few bytes: the heap)
        if sa[1][0x100:0x1F0] != sb[1][0x100:0x1F0]:
            d = [k for k in range(0xF0) if sa[1][0x100 + k] != sb[1][0x100 + k]]
            raise SystemExit('ship %d (type %d) parts 6-8: XX3 differs at %s\n  ref   %s\n  build %s' % (
                i, zp[sy['TYPE']], d[:12], [sa[1][0x100 + k] for k in d[:12]], [sb[1][0x100 + k] for k in d[:12]]))
        if sa[1][A.sy['CNT']] != sb[1][B.sy['CNT']]:
            raise SystemExit('ship %d parts 6-8: CNT differs' % i)
        verts += sum(1 for k in range(0, 0xF0, 4) if sa[1][0x100 + k:0x104 + k] != p2[k:k + 4])
    print('LL9: %d ships, %d drawn (%d dots or out of view): parts 3-5 and 6-8 equal' % (n, drawn, dots))
    if drawn:
        print('  parts 3-5: %d -> %d cycles a ship; parts 6-8: %d -> %d (about %.0f vertices a ship)' % (
            cyc['A35'] / drawn, cyc['B35'] / drawn, cyc['A68'] / drawn, cyc['B68'] / drawn, verts / drawn))


if __name__ == '__main__':
    main()
