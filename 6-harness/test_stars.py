#!/usr/bin/env python3
"""The front view's stardust (STARS with VIEW = 0), one build against another,
on py65 (65C02).

    python3 6-harness/test_stars.py REFDIR [--n 5000] [--seed 1] [--tree DIR]
                                           [--strict]

REFDIR holds a reference build's BCODE.unprot.bin, HICODE.bin, BANK4.bin,
HZDATA.bin and symbols.txt (3-assembled-output of a build whose stardust is
trusted); the candidate is this tree's 3-assembled-output (or --tree's). Both
are loaded as test_ll9.py loads them, each into its own memory, which then
persists from call to call as in the game (so the operands STARS1 patches,
and anything it keeps between calls, carry over).

Each call enters STARS (from a JMP in the main loop, so with a return address
on the stack) in record mode (QQ11 = 0, GFORCE = 0), the front view
(VIEW = 0), with the same random A, X, Y and flags on both (D clear, as
the game keeps it: S%'s CLD, and FILLKL's after RDKEY-1's SED). Between calls the
speed DELTA (0..40, DELT4 = 64 * DELTA as MA68 keeps it) and the roll and
pitch change as the main loop's key handling derives them from JSTX and JSTY
(ALP1, ALP2, ALP2+1, ALPHA, BET1, BET2, BET2+1, BETA, in M%), sometimes every
call and sometimes not for many calls, with zero roll or pitch (the patched
skips in MLSA and MLSB) and the changes to and from them. The particles start
as nWq makes them (NOSTM = NOST, or 3 as in witchspace), and RAND is
sometimes moved on between calls, as the rest of the main loop does.

After every call these must be equal: zero page except the temporaries P,
P+1, Q, R, S, T, T1, XX(1 0), YY(1 0) and widget (so RAND, X1, Y1, ZZ, COL
and the inputs), the particles SX, SY, SZ, SXL, SYL, SZL, the renderer's
records R_SX, R_SY, R_SS, and the A, X, Y and flags (N, V, Z, C) that STARS
returns with (its caller returns at once to the main loop, whose next DORND
takes C). The temporaries are set to different random values on the two
builds before each call, so a read of one before STARS writes it shows up.
With --strict the temporaries start equal and are compared as well. Exit status 0 only if every call gives the same results; prints the
cycles a call took on each build and how often the rare paths ran (counted on
the reference: KILL1, stl_dvs, mlqr, mlar, mlbr, MU8, mlsk and mlbk).
"""
import os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from test_ll9 import load, RET          # noqa: E402
from py65.devices.mpu65c02 import MPU   # noqa: E402

NOST = 20
TEMPS = ('P', 'P+1', 'Q', 'R', 'S', 'T', 'T1', 'XX', 'XX+1', 'YY', 'YY+1', 'widget')
RARE = ('KILL1', 'stl_dvs', 'mlqr', 'mlar', 'mlbr', 'MU8', 'mlsk', 'mlbk')


def addr(sy, n):
    if n.endswith('+1'):
        return sy[n[:-2]] + 1
    return sy[n]


class Build:
    def __init__(self, d, srcdir):
        # (CODE% is WS_END, the shared workspace's end, elite-gfx.asm, in
        # each build's own symbols: a REFDIR holds no source, and CODE% moves)
        self.sy, self.mem = load(d, srcdir)
        code = self.sy.get('WS_END')
        if code is not None:
            out = os.path.join(d, '3-assembled-output') if os.path.isdir(os.path.join(d, '3-assembled-output')) else d
            b = list(open(os.path.join(out, 'BCODE.unprot.bin'), 'rb').read())
            self.mem[0x0E00:0x4000] = [0] * (0x4000 - 0x0E00)
            self.mem[code:code + len(b)] = b
        self.mpu = MPU()
        self.mpu.memory = self.mem
        self.cycles = 0
        self.calls = 0
        self.watch = {}

    def stars(self, regs):
        mpu, mem = self.mpu, self.mem
        mpu.a, mpu.x, mpu.y, mpu.p = regs
        mpu.sp = 0xFD
        mem[0x1FF], mem[0x1FE] = (RET - 1) >> 8, (RET - 1) & 255
        mpu.pc = self.sy['STARS']
        c0 = mpu.processorCycles
        watch = self.watch
        n = 0
        while mpu.pc != RET:
            if mpu.pc in watch:
                watch[mpu.pc][1] += 1
            mpu.step()
            n += 1
            if n > 200000:
                raise RuntimeError('runaway at &%04X' % mpu.pc)
        self.cycles += mpu.processorCycles - c0
        self.calls += 1
        return mpu.a, mpu.x, mpu.y, mpu.p & 0xC3, mpu.sp


def roll(jstx):
    """ALP2, ALP2+1, ALP1, ALPHA from the damped roll rate JSTX, as M% does"""
    a = jstx ^ 0x80
    alp2 = a & 0x80
    m = (256 - a) & 255 if a & 0x80 else a
    m >>= 2
    if m < 8:
        m >>= 1
    return alp2, alp2 ^ 0x80, m, m | alp2


def pitch(jsty, c):
    """BET2, BET2+1, BET1, BETA from the damped pitch rate JSTY (c is the C
    that M%'s ADC #4 takes), as M% does"""
    a = jsty ^ 0x80
    bet21 = a & 0x80
    bet2 = bet21 ^ 0x80
    if a & 0x80:
        a ^= 0xFF
    m = (a + 4 + c) >> 4
    if m < 3:
        m >>= 1
    return bet2, bet21, m, m | bet2


def main():
    args = sys.argv[1:]
    opt = lambda n, d: (args[args.index(n) + 1] if n in args else d)
    ref = args[0]
    tree = opt('--tree', os.path.dirname(HERE))
    n, seed = int(opt('--n', 5000)), int(opt('--seed', 1))
    strict = '--strict' in args
    src = os.path.dirname(HERE)
    A, B = Build(ref, src), Build(tree, src)
    sa, sb = A.sy, B.sy
    names = ('SX', 'SY', 'SZ', 'SXL', 'SYL', 'SZL', 'R_SX', 'R_SY', 'R_SS', 'RAND', 'VIEW', 'GFORCE')
    for nm in names + ('QQ11', 'NOSTM', 'DELTA', 'DELT4', 'ALPHA', 'ALP1', 'ALP2', 'BETA', 'BET1', 'BET2') + TEMPS[::2]:
        k = nm[:-2] if nm.endswith('+1') else nm
        if sa[k] != sb[k]:
            raise SystemExit('%s is at &%04X in the reference, &%04X in the build' % (k, sa[k], sb[k]))
    for nm in RARE:
        if nm in sa:
            A.watch[sa[nm]] = [nm, 0]
    temps = {addr(sa, t) for t in TEMPS}
    zp = [k for k in range(256) if (strict or k not in temps) and k not in (0, 1)]
    arrays = [(nm, sa[nm], 4 if nm == 'RAND' else (1 if nm in ('VIEW', 'GFORCE') else NOST + 1)) for nm in names]
    rnd = random.Random(seed)

    def put(nm, v):
        for X in (A, B):
            X.mem[addr(sa, nm)] = v

    def dornd_seed():
        v = [rnd.randrange(256) for _ in range(4)]
        for X in (A, B):
            X.mem[sa['RAND']:sa['RAND'] + 4] = v

    def nwq(nost):
        # as nWq: z_hi = random OR 8, x_hi and y_hi random; the low bytes are
        # whatever was there (random here)
        for i in range(1, nost + 1):
            vals = [rnd.randrange(256) | 8, rnd.randrange(256), rnd.randrange(256)] + [rnd.randrange(256) for _ in range(3)]
            for X in (A, B):
                for nm, v in zip(('SZ', 'SX', 'SY', 'SZL', 'SXL', 'SYL'), vals):
                    X.mem[sa[nm] + i] = v

    # the zero page (and the rest) starts the same on both: random, then the
    # game's values
    for k in range(2, 256):
        put_v = rnd.randrange(256)
        A.mem[k] = B.mem[k] = put_v
    for nm in ('R_SX', 'R_SY', 'R_SS'):
        v = [rnd.randrange(256) for _ in range(NOST + 1)]
        for X in (A, B):
            X.mem[sa[nm]:sa[nm] + NOST + 1] = v
    put('VIEW', 0)
    put('QQ11', 0)
    put('GFORCE', 0)
    dornd_seed()
    nost = NOST
    put('NOSTM', nost)
    nwq(nost)

    jstx, jsty, c, delta = 128, 128, 0, 3
    hold = 0
    mode = 'steady'
    for call in range(n):
        if hold <= 0:
            mode = rnd.choice(('steady', 'steady', 'every', 'zero', 'toggle'))
            hold = rnd.choice((1, 5, 20, 60, 200))
            if rnd.random() < 0.03:     # a new cloud (a hyperspace or witchspace jump)
                nost = 3 if rnd.random() < 0.2 else NOST
                put('NOSTM', nost)
                nwq(nost)
        hold -= 1
        change = (mode == 'every') or (mode in ('zero', 'toggle') and rnd.random() < 0.3) or hold == 0
        if change or call == 0:
            if mode == 'zero':
                # zero roll or pitch or both (|JSTX - 128| < 8 gives ALP1 = 0,
                # |JSTY - 128| < 28 or so gives BET1 = 0)
                jstx = rnd.choice((128 + rnd.randrange(-7, 8), rnd.randrange(1, 256)))
                jsty = rnd.choice((128 + rnd.randrange(-20, 21), rnd.randrange(1, 256)))
            elif mode == 'toggle':
                jstx = 128 if rnd.random() < 0.5 else rnd.randrange(1, 256)
                jsty = 128 if rnd.random() < 0.5 else rnd.randrange(1, 256)
            else:
                jstx = rnd.randrange(1, 256)
                jsty = rnd.randrange(1, 256)
            c = rnd.randrange(2)
            if rnd.random() < 0.7:
                delta = rnd.choice((rnd.randrange(0, 41), 40, 0, 1, rnd.randrange(30, 41)))
        alp2, alp21, alp1, alpha = roll(jstx)
        bet2, bet21, bet1, beta = pitch(jsty, c)
        put('ALP2', alp2)
        put('ALP2+1', alp21)
        put('ALP1', alp1)
        put('ALPHA', alpha)
        put('BET2', bet2)
        put('BET2+1', bet21)
        put('BET1', bet1)
        put('BETA', beta)
        put('DELTA', delta)
        put('DELT4', (delta & 3) << 6)
        put('DELT4+1', delta >> 2)
        if rnd.random() < 0.5:          # the rest of the main loop's DORNDs
            dornd_seed()
        # the temporaries hold whatever the main loop left, different on the
        # two builds, so that a read of one before STARS writes it shows up
        for t in temps:
            A.mem[t] = rnd.randrange(256)
            B.mem[t] = A.mem[t] if strict else rnd.randrange(256)
        regs = (rnd.randrange(256), rnd.randrange(256), rnd.randrange(256), (rnd.randrange(256) & 0xC3) | 0x20)
        ra = A.stars(regs)
        rb = B.stars(regs)
        bad = []
        if ra != rb:
            bad.append('registers (A, X, Y, P & NVZC, SP): ref %s, build %s' % (
                tuple('%02X' % v for v in ra), tuple('%02X' % v for v in rb)))
        for nm, a0, ln in arrays:
            va, vb = A.mem[a0:a0 + ln], B.mem[a0:a0 + ln]
            if va != vb:
                d = [k for k in range(ln) if va[k] != vb[k]]
                bad.append('%s differs at %s: ref %s, build %s' % (nm, d[:8], [va[k] for k in d[:8]], [vb[k] for k in d[:8]]))
        dz = [k for k in zp if A.mem[k] != B.mem[k]]
        if dz:
            bad.append('zero page differs at %s: ref %s, build %s' % (
                ['&%02X' % k for k in dz[:8]], [A.mem[k] for k in dz[:8]], [B.mem[k] for k in dz[:8]]))
        if bad:
            raise SystemExit('call %d (seed %d; DELTA %d, ALP1 %d, BET1 %d, NOSTM %d):\n  %s' % (
                call, seed, delta, alp1, bet1, nost, '\n  '.join(bad)))
    cov = ', '.join('%s %d' % (w[0], w[1]) for w in sorted(A.watch.values()))
    print('STARS (front view): %d calls, seed %d: equal%s' % (n, seed, ' (strict: temporaries too)' if strict else ''))
    print('  cycles a call: reference %.1f, build %.1f' % (A.cycles / n, B.cycles / n))
    print('  rare paths on the reference: %s' % cov)
    miss = [w[0] for w in A.watch.values() if w[1] == 0]
    if miss:
        print('  (not reached: %s)' % ', '.join(miss))


if __name__ == '__main__':
    main()
