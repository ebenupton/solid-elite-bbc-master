#!/usr/bin/env python3
"""The lighting's L_REC, one build against another, on py65 (65C02).

    python3 6-harness/test_lrec.py REFDIR [--n 5000] [--seed 1] [--tree DIR]

REFDIR holds a reference build's 3-assembled-output (BCODE.unprot.bin,
HICODE.bin, BANK6.bin, HZDATA.bin and symbols.txt) whose L_REC is trusted;
the candidate is this tree's (or --tree's). Both are loaded as the game has
them (main RAM from CODE%, the quarter squares at &7000, the frame layer,
bank 6, at &8000, the blueprints in HAZEL at &C000) and L_REC is run on the
same random ships: every type with faces, a random orientation (INWK's
nosev, roofv and sidev, as test_ll9.py makes them), a random light (LLT,
a unit vector of 41.3, or random bytes of that size), handedness (GHAND)
and record slot (F_NSHIP), and a random visibility per face in the record's
XX2 copy (0 hidden, 255 cull by winding, or another non-zero value). The
faces' levels L_REC writes into the copy must be the same, byte for byte,
and Y must come back as it went in. Exit status 0 only if every ship gives
the same levels; prints the cycles each build took.
"""
import math, os, random, sys
from test_ll9 import load, sm16
from py65.devices.mpu65c02 import MPU

HERE = os.path.dirname(os.path.abspath(__file__))
RET = 0xFFF0
COPY = 0x0600           # (the record's XX2 copy, for F_SPL/F_SPH)


def load6(d, srcdir):
    sy, mem = load(d, srcdir)
    out = os.path.join(d, '3-assembled-output') if os.path.isdir(os.path.join(d, '3-assembled-output')) else d
    b = list(open(os.path.join(out, 'BANK6.bin'), 'rb').read())
    mem[0x8000:0x8000 + len(b)] = b
    return sy, mem


def run(sy, image, sets, y):
    """L_REC on the image with the given (address, bytes) written: (memory,
    Y returned, cycles)"""
    mpu = MPU()
    mem = image[:]
    for a, bs in sets:
        mem[a:a + len(bs)] = bs
    mpu.memory = mem
    mpu.a, mpu.x, mpu.y, mpu.p = 0, 0, y, 0x24
    mpu.sp = 0xFD
    mem[0x1FF], mem[0x1FE] = (RET - 1) >> 8, (RET - 1) & 255
    mpu.pc = sy['L_REC']
    c0 = mpu.processorCycles
    n = 0
    while mpu.pc != RET:
        mpu.step()
        n += 1
        if n > 200000:
            raise RuntimeError('runaway at &%04X' % mpu.pc)
    return mem, mpu.y, mpu.processorCycles - c0


def sb(v):
    return int(v) & 255


def main():
    args = sys.argv[1:]
    opt = lambda n, d: (args[args.index(n) + 1] if n in args else d)
    ref = args[0]
    tree = opt('--tree', os.path.dirname(HERE))
    n, seed = int(opt('--n', 5000)), int(opt('--seed', 1))
    (sa, ma), (sb_, mb) = load6(ref, tree), load6(tree, tree)
    rnd = random.Random(seed)
    xx21 = sa['XX21']
    bp = lambda t: ma[xx21 + 2 * (t - 1)] | (ma[xx21 + 2 * (t - 1) + 1] << 8)
    types = [(t, ma[bp(t) + 12] >> 2) for t in range(1, 34) if bp(t) >= 0xC000 and ma[bp(t) + 12] >> 2]
    cyc = [0, 0]
    faces = lit = 0
    for i in range(n):
        t, nf = rnd.choice(types)
        a, b, c = (rnd.uniform(0, 2 * math.pi) for _ in range(3))
        ca, sa_, cb, sb2, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
        R = [[cb * cc, -cb * sc, sb2], [sa_ * sb2 * cc + ca * sc, -sa_ * sb2 * sc + ca * cc, -sa_ * cb],
             [-ca * sb2 * cc + sa_ * sc, ca * sb2 * sc + sa_ * cc, ca * cb]]
        if rnd.random() < 0.2:
            R = rnd.choice(([[1, 0, 0], [0, 1, 0], [0, 0, 1]], [[0, 0, -1], [0, 1, 0], [-1, 0, 0]], [[0, 1, 0], [-1, 0, 0], [0, 0, 1]]))
        if rnd.random() < 0.5:  # (the other handedness, as the station has it)
            R[2] = [-v for v in R[2]]
        vecs = []
        for row in R:
            for v in row:
                vecs += sm16(v * 0x6000 + rnd.uniform(-300, 300))
        if rnd.random() < 0.8:
            u = [rnd.gauss(0, 1) for _ in range(3)]
            m = math.sqrt(sum(x * x for x in u)) or 1
            llt = [sb(round(x / m * 41.3)) for x in u]
        else:
            llt = [sb(rnd.randint(-41, 41)) for _ in range(3)]
        k = rnd.randrange(12)
        xx2 = [rnd.choice((0, 0, 255, 255, rnd.randrange(1, 255))) for _ in range(nf)]
        y = rnd.randrange(256)
        gh = rnd.choice((0x40, 0x60))
        res = []
        for s, mm in ((sa, ma), (sb_, mb)):
            sets = [(s['INWK'] + 9, vecs), (s['LLT'], llt), (s['GNF'], [nf]), (s['GTYPE'], [t]),
                    (s['GHAND'], [gh]),
                    (s['F_NSHIP'], [k]), (s['F_SPL'] + k, [COPY & 255]), (s['F_SPH'] + k, [COPY >> 8]),
                    (COPY, xx2 + [0x5A] * 4)]
            mem, yo, cy = run(s, mm, sets, y)
            res.append((mem[COPY:COPY + nf + 4], yo, cy))
        (oa, ya, ca_), (ob, yb, cb_) = res
        if oa != ob or ya != yb or ya != y:
            raise SystemExit('ship %d (type %d, %d faces, LLT %s, slot %d): levels differ\n  in    %s\n  ref   %s Y %d\n  build %s Y %d (Y in %d)' % (
                i, t, nf, llt, k, xx2, oa, ya, ob, yb, y))
        cyc[0] += ca_
        cyc[1] += cb_
        faces += nf
        lit += sum(1 for v in oa[:nf] if v & 0x1F)
    print('L_REC: %d ships, %d faces (%d lit above level 0): the levels equal' % (n, faces, lit))
    print('  %.0f -> %.0f cycles a ship' % (cyc[0] / n, cyc[1] / n))


if __name__ == '__main__':
    main()
