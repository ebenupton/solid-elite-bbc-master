"""Reference model of the planet's surface detail (1-source-files/main-sources/gfx-merid.asm,
the circle engine, and gfx-planet7.asm, its styles): the rows of a disc
coloured by circles on the sphere, bit for bit as the 6502 code makes them.

Every feature is a circle on the planet's sphere (radius r, centre (bx, by)
on the screen): the boundary of the region {p : m^.p >= d}, d = r c (c the
cosine of its angular radius, 0..255/256, and its sign). A meridian or the
equator is a great circle (c = 0); a crater a small cap; a band the region
between two latitude circles about the spin axis. A style is a short list
of such circles, each a record (circ_consts), and a base colour; a pixel's
colour is the base EOR the parity of the regions it is in. The axes are
Elite's orientation vectors (or sums of them, halved), in Elite's axes (y
up); the visible hemisphere is the one where a vector's z is positive. If
m's z is negative, m and d are negated and the region is the complement of
the one that gives (inv).

The circle projects to the ellipse
    X = X0 + a (y - yc) -/+ sqrt(D),  D = K0 - K2 (y - yc)^2,
about (xc, yc) = (bx, by) + d (m^x, m^y'), with a = -mx my' / rho2, K2 =
t (1 + my'^2 / rho2), K0 = t (r^2 - d^2), t = mz^2 / rho2, rho2 = mx^2 + mz^2.
Along a row the side function f = m^.p - d is concave on the visible
hemisphere, so the row's X- crossing is a boundary iff f <= 0 at the row's
left limb point, X+ iff at its right one, and the row starts in the region
iff f > 0 at its left limb point. Along the limb f changes sign only at the
nodes, where the circle meets the limb: Ys = A -/+ sqrt(B), A = m^y' d / q2,
B = v (r^2 - d^2 / q2), q2 = m^x^2 + m^y'^2, v = mx^2 / (mx^2 + my^2), each
on the left limb or the right; so the two crossings' validity and the start
colour are comparisons of the row with two threshold rows. Rows Yc +/- k
from the ellipse's (rounded) centre row share D(k) and s = round(sqrt(D)),
stepped as the beach ball's row loop stepped them; past the ellipse only
rows between the nodes (one crossing) have a boundary, at the centre line.

body_rows(...) returns {y: (p, [x...])}: p the colour at the span's left
end (0 = A, 1 = B), the boundaries inside (L, R] ascending, at most four (a
fifth drops the two rightmost).
"""
import math

M32 = 0xFFFFFFFF


def fdiv(u, v):
    """the 6502 division (gfx-merid.asm pm_fdiv), u/v as 16.16 with a 12-bit
    mantissa (planet_analytic.fdiv), and saturated if v loses all its bits
    while both are shifted right (u >= 2^24 > v)"""
    if u == 0:
        return 0
    if v == 0:
        return M32
    while u >= 1 << 24 or v >= 1 << 24:
        u >>= 8
        v >>= 8
        if u == 0:
            return 0
        if v == 0:
            return M32
    eu = 24 - u.bit_length()
    ev = 24 - v.bit_length()
    U = (u << eu) >> 8
    V = (v << ev) >> 8
    q = (U << 11) // V
    sh = 5 + ev - eu
    r = q << sh if sh >= 0 else q >> -sh
    return min(r, M32)


def smag(lo, hi):
    """sign-magnitude 16-bit (as INWK) -> (magnitude, negative)"""
    return lo | ((hi & 0x7F) << 8), bool(hi & 0x80)


def setup_core(vec):
    """pms_core's per-axis terms (gfx-merid.asm), exactly: vec = [(lo, hi)] *
    3 sign-magnitude (pf_tilt's halved vectors; magnitudes >> 2, the
    beach ball's |v| >> 3). Returns the magnitudes, their squares, the signs,
    inv, t, |a| and its sign, K2 and v"""
    am, sg, nz = [], [], []
    for lo, hi in vec:
        m, neg = smag(lo, hi)
        nz.append(m != 0)
        sg.append(neg and m != 0)
        am.append(m >> 2)
    sx = sg[0]
    sy = sg[1] != nz[1]             # my' = -my
    inv = 0
    if sg[2]:
        inv = 1
        sx = sx != nz[0]
        sy = sy != nz[1]
    ax, ay, az = am
    X2, Y2, Z2, XY = ax * ax, ay * ay, az * az, ax * ay
    R2 = X2 + Z2 or 1
    Q2 = X2 + Y2 or 1
    t = min(fdiv(Z2, R2), 0xFFFF)
    v = min(fdiv(X2, Q2), 0xFFFF)
    aa = fdiv(XY, R2)
    if aa > 0xFFFFFF:
        aa = 0xFFFFFF
    aneg = (sx == sy)               # a = -mx my' / rho2
    u = fdiv(Y2, R2)
    p = (u >> 16) * t
    K2 = (p + t) & M32
    q = (u & 0xFFFF) * t
    K2 = (K2 + (q >> 16)) & M32
    return dict(am=am, nz=nz, sx=sx, sy=sy, inv=inv, t=t, v=v, aa=aa, aneg=aneg, K2=K2)


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def s32(v):
    v &= M32
    return v - 0x100000000 if v & 0x80000000 else v


def clamp_row(t):
    return max(0, min(192, t))


def circ_consts(bx, by, r, vec, c8, cneg, kn=10923):
    """pc_circ: one circle's record (None if the axis is zero): the
    constants of its row loop, its threshold rows and inv"""
    k = setup_core(vec)
    am = k['am']
    if not any(am):
        return None
    hu = []
    for m, nz in zip(am, k['nz']):          # the unit axis, 0.8 (at least 1 if not zero)
        h = min(255, (m * (kn >> 1)) >> 16)
        hu.append(1 if h == 0 and nz else h)
    hx, hy = hu[0], hu[1]
    sx, sy, t = k['sx'], k['sy'], k['t']
    d = r * c8                               # (8.8)
    dneg = bool(cneg) != bool(k['inv']) and d != 0
    # the centre (16.8) and its row
    X0 = (d * hx) >> 8
    Y0 = (d * hy) >> 8
    xc = bx * 256 + (-X0 if dneg != sx else X0)
    yc = by * 256 + (-Y0 if dneg != sy else Y0)
    Yc = (yc + 128) >> 8
    C0 = (xc + 128) >> 8                     # (the centre line at row Yc to the nearest
    aa = k['aa']                             # pixel: rows Yc +/- k are symmetric about it)
    a = -aa if k['aneg'] else aa
    C0 = s32(C0 << 16)
    # K0, s0
    rc2 = r * r - ((d * d) >> 16)
    K0 = rc2 * t
    s0 = (math.isqrt(K0) + 128) >> 8
    L0 = s0 * s0 - s0
    # the nodes, in 1/512 pixels from by
    q2 = hx * hx + hy * hy
    A = min(fdiv(Y0 << 8, q2), 0xFFFFFF)
    A9 = A >> 7
    if dneg != sy:
        A9 = -A9
    e2 = fdiv((d * d) >> 16, q2)
    B = (r * r - e2) * k['v'] if e2 < r * r else 0
    S = math.isqrt(B >> 16) << 8            # (8.8: the integer part)
    S9 = 2 * S + (1 if S * S != B else 0)
    hyr = hy * r
    hyr = -hyr if sy else hyr
    ds = -d if dneg else d
    top = -hyr - ds > 0
    bot = hyr - ds > 0
    if top != bot or not d:                  # (d = 0: the nodes' rows are -/+ w)
        mu = 2 if sx == sy else 1
        md = 3 - mu
    else:
        mu = md = 2 if sx == dneg else 1
    F = 3 if top else 0
    st = F
    th = []
    for n, M in ((A9 - S9, mu), (A9 + S9, md)):
        if st & M:
            T = by - ((-n) >> 9)             # ceil: inside -> outside
        else:
            T = by + (n >> 9) + 1            # floor + 1
        th.append((clamp_row(T), M))
        st ^= M
    none = S9 == 0 and mu == md and F == 3    # (no node, both limbs in the region:
                                             # every row is, and pc_circ keeps no record)
    return dict(inv=k['inv'], a=s32(a), K0=K0, K2=k['K2'], s0=s0, L0=L0, C0=C0, Yc=s16(Yc), F=F,
                T1=th[0][0], M1=th[0][1], T2=th[1][0], M2=th[1][1], none=none)


def rec_parity(c):
    """a record's part of the body's base colour: inv EOR its region at the
    top's left limb"""
    return c['inv'] ^ (c['F'] & 1)


def put(row, x, L, R):
    """a crossing at x (16-bit signed) on a row with span L..R"""
    if x < 0 or (x < 256 and x <= L):
        row[0] ^= 1
    elif x >= 256 or x > R:
        return
    else:
        xs = row[1]
        xs.append(x)
        xs.sort()
        if len(xs) == 5:                     # (the two rightmost dropped)
            del xs[3:]


def flags(c, y):
    f = c['F']
    if y >= c['T1']:
        f ^= c['M1']
    if y >= c['T2']:
        f ^= c['M2']
    return f


def body_rows(base, recs, ndt, ndb, ndl, ndr):
    """pc_rows: the rows NDT..NDB (spans ndl, ndr [192]) of a body whose
    records are recs (circ_consts; base: the style's colour EOR the records'
    rec_parity)"""
    rows = {y: [base, []] for y in range(ndt, ndb + 1)}
    recs = [c for c in recs if c is not None and not c['none']]
    for c in recs:                            # the start colour: each left-limb toggle
        for T, M in ((c['T1'], c['M1']), (c['T2'], c['M2'])):
            if M & 1:
                for y in range(max(T, ndt), ndb + 1):
                    rows[y][0] ^= 1
    for c in recs:
        tlo, thi = min(c['T1'], c['T2']), max(c['T1'], c['T2'])
        D = c['K0'] >> 9
        dl = c['K2'] >> 1
        s = c['s0']
        H = c['L0'] >> 1
        past = False
        Cd = Cu = c['C0']
        yd = yu = c['Yc']
        k = 0
        while k < 255:                        # (k is 8-bit: rows within 254 of Yc)
            LD = min(ndb + 1, thi) if past else ndb + 1
            LU = max(ndt, tlo) if past else ndt
            if yd >= LD and yu < LU:
                break
            if not past:
                while s and D < H * 256 + 0x20:
                    s -= 1
                    H -= s
            ss = 0 if past else s
            for y, C, act in ((yd, Cd, ndt <= yd < LD), (yu, Cu, k and LU <= yu <= ndb)):
                if not act:
                    continue
                f = flags(c, y)
                vm, vp = not f & 1, not f & 2
                if ss == 0 and vm == vp:
                    continue
                cc = s16((C >> 16) + (1 if C & 0xFFFF else 0))
                if vm:
                    put(rows[y], s16(cc - ss), ndl[y], ndr[y])
                if vp:
                    put(rows[y], s16(cc + ss), ndl[y], ndr[y])
            if not past:
                if (dl >> 8) > D:
                    past = True
                else:
                    D -= dl >> 8
                    dl = min(dl + c['K2'], M32)
            Cd = s32(Cd + c['a'])
            Cu = s32(Cu - c['a'])
            yd += 1
            yu -= 1
            k += 1
    return {y: (v[0], v[1]) for y, v in rows.items()}


def truth(bx, by, r, axes, x, y):
    """the float colour of pixel (x, y) (centre at integer x, y): the parity of
    the caps (axis vectors as integers, c) containing its point on the sphere,
    or None outside the disc"""
    X, Ys = x - bx, y - by
    q = r * r - X * X - Ys * Ys
    if q < 0:
        return None
    Z = math.sqrt(q)
    p = 0
    for (vx, vy, vz), c in axes:
        n = math.sqrt(vx * vx + vy * vy + vz * vz)
        if (vx * X - vy * Ys + vz * Z) / n >= r * c:
            p ^= 1
    return p


# ------------------------------------------------------------ the game's caps

PFS_C = (247, 241, 232, 222)
PFN = (10923, 9770, 10596, 7723)      # 2^24 / the nominal length (>> 3) of pf_tilt's sums


def pf_kn(y, f):
    return PFN[0 if not y else 3 if f & 8 else 2 if f & 4 else 1]


def _tc(inwk, o):
    lo, hi = inwk[o], inwk[o + 1]
    m = lo | ((hi & 0x7F) << 8)
    return -m if hi & 0x80 else m


def pf_tilt(inwk, x, y, f):
    """pf_tilt: (+/- vector x) / 2 + (+/- vector y) / 2^(k+1), sign-magnitude
    words (x, y: INWK offsets; y = 0 none; f bit 0, 1 the signs, bit 2 k = 2,
    else k = 1, bit 3 k = 0); each magnitude shifted before its sign is
    applied (rounded towards zero)"""
    out = []
    for j in range(3):
        m, neg = smag(inwk[x + 2 * j], inwk[x + 2 * j + 1])
        r = -(m >> 1) if neg != bool(f & 1) else m >> 1
        if y:
            m, neg = smag(inwk[y + 2 * j], inwk[y + 2 * j + 1])
            m >>= 1 if f & 8 else 3 if f & 4 else 2
            r += -m if neg != bool(f & 2) else m
        m = -r if r < 0 else r
        out.append((m & 255, ((m >> 8) & 0x7F) | (0x80 if r < 0 else 0)))
    return out


PFB_N = (64, 96, 128, 150)
PFB_S = (32, 64, 96, 128)


BANDS = True                          # banded planets in the build (make bands=on)
RINGS = True                          # planet rings in the build (make rings=on)


def pf_banded(qq2):
    """a crater planet (TYPE 130) whose seed makes it banded (in a build with
    banded planets)"""
    return BANDS and qq2[3] & 3 == 0


def pf_records(inwk, qq2, typ):
    """PF_HOOK's style: (base, [(vec, c8, cneg, kn)]): a meridian planet's
    beach ball (its two great circles, normal to roofv and sidev: colour B
    where the surface is on the same side of both), or pf_caps'"""
    if typ == 128:
        return 1, [(pf_tilt(inwk, 15, 0, 0), 0, 0, PFN[0]), (pf_tilt(inwk, 21, 0, 0), 0, 0, PFN[0])]
    return 0, pf_caps(inwk, qq2)


def pf_caps(inwk, qq2):
    """pf_craters or pf_bands: the crater planet's caps [(vec, c8, cneg, kn)]
    from its orientation (INWK) and the system's seed (QQ2)"""
    if pf_banded(qq2):
        v = pf_tilt(inwk, 9, 21, 0b1010)
        return [(v, PFB_N[(qq2[5] >> 4) & 3], 0, PFN[3]), (v, PFB_S[qq2[5] >> 6], 1, PFN[3])]
    caps = [(pf_tilt(inwk, 15, 0, 0), 222, 0, PFN[0])]
    n = qq2[4] & 3
    if n:
        f = (qq2[4] >> 2) & 7
        caps.append((pf_tilt(inwk, 9, 21, f), PFS_C[qq2[5] & 3], 0, pf_kn(21, f)))
        if n == 2:
            f = qq2[4] >> 5
            caps.append((pf_tilt(inwk, 21, 15, f), PFS_C[(qq2[5] >> 2) & 3], 0, pf_kn(15, f)))
    return caps


# ------------------------------------------------------------ the moon

PFM_RHO = (48, 56, 64, 72)            # its radius over the planet's (0.8)
MOON_C8 = 196                         # its crater: 40 degrees across


def moon_hash(qq2):
    return qq2[1] ^ qq2[3] ^ qq2[5]


PFM_VS = (0, 1, 2, 0, 1, 2, 2, 1, 0, 2, 1, 0)     # the view's axes (PLUT's): E's axis
PFM_VN = (0, 0, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0)     # and its sign, by 3 VIEW + i


def moon_e0(qq2):
    """MN_TURN's E as it makes it (the coordinates: x, y, z), or None"""
    h = moon_hash(qq2)
    if h & 3 != 1:
        return None
    c = round((3, 3.75, 4.5, 5.25)[(h >> 2) & 3] / math.sqrt(2) * 24576)
    c = c if h & 0x10 else -c
    return [c, 0, c]


def pf_moon(inwk, qq2, cx, cy, r, pz, sunz=None, E=None, view=0):
    """pf_moon: the moon of a planet (centre cx, cy, radius r < 256; its
    position, in the view's axes, INWK's bytes 0-8) at E from it (MN_E: the
    coordinates, the front view's axes; None: MN_OK clear) in the view VIEW,
    or None: dict(on, x, y, r, z16, z24, behind, behindsun, cap) with cap
    (vec, c8, cneg, kn) for its crater (None if it is too small for one).
    Its centre M = P + E (E in the view's axes) is projected as Elite does
    (x = 128 + 256 M_x / M_z, y = 96 - 256 M_y / M_z, the radius rho 24576 /
    256 M_z: M shifted right until M_z fits 15 bits). sunz: the sun's z
    (24-bit, positive), if the sun is in slot 1"""
    h = moon_hash(qq2)
    if h & 3 != 1 or r < 16 or E is None:
        return None

    def sm24(k):
        m = inwk[k] | (inwk[k + 1] << 8) | ((inwk[k + 2] & 0x7F) << 16)
        return -m if inwk[k + 2] & 0x80 else m
    M, ez = [], 0
    for i in range(3):
        v = E[PFM_VS[3 * view + i]]
        v = -v if PFM_VN[3 * view + i] else v
        if i == 2:
            ez = v
        M.append(sm24(3 * i) + v)
    if M[2] <= 0:
        return None
    z24 = M[2]
    s = 0
    while M[2] >= 32768:
        M = [c >> 1 for c in M]
        s += 1
    zq = M[2]

    def xy(v, neg, centre):
        a = abs(v)
        if a >= 65536:
            return None
        q = (a << 8) // zq
        if q >= 16384:
            return None
        return centre + (-q if (v < 0) != neg else q)
    mx = xy(M[0], False, 128)
    if mx is None:
        return None
    my = xy(M[1], True, 96)
    if my is None:
        return None
    mr = (((PFM_RHO[(h >> 5) & 3] * 96) << 8) >> s) // zq
    if mr < 64 and mr < 2:
        return None
    mr = min(mr, 63)
    behind = ez > 0
    behindsun = sunz is not None and sunz < z24
    cap = (pf_tilt(inwk, 15, 0, 0), MOON_C8, 0, PFN[0]) if mr >= 10 else None
    return dict(x=mx, y=my, r=mr, z16=min(z24, 0xFFFF), z24=z24, behind=behind, behindsun=behindsun, cap=cap)


# ------------------------------------------------------------ the rings

PFR_R = (102, 115, 128, 141)          # the ring's radius over the planet's (x 64)


def _sm16(lo, hi):
    m = lo | ((hi & 0x7F) << 8)
    return -m if hi & 0x80 else m


def pf_ring(inwk, qq2, cx, cy, r):
    """pf_ring: the ring's dots [(x, y, back)] (on the screen only), or None.
    The ring lies in the plane of the planet's equator, normal to the axis it
    spins about (nosev - sidev): two conjugate radii, roofv and (nosev +
    sidev) / sqrt(2), scaled to the ring's radius on the screen, give its
    points P(t) = cos t A1 + sin t A2 (t = k pi / N, k = 0 .. N - 1) and -P(t);
    a point is behind the planet's centre if its z is negative"""
    h = moon_hash(qq2)
    if not RINGS or (h >> 4) & 7 != 4 or r < 8:
        return None
    S = PFR_R[(h >> 2) & 3] * r
    S3 = (S * 21845) >> 16                     # the radius in pixels x 64 / 3
    S3r2 = S3 + ((S3 * 27146) >> 16)            # and times sqrt(2)
    u1 = [_sm16(inwk[15 + 2 * i], inwk[16 + 2 * i]) for i in range(3)]
    u2 = [_sm16(lo, hi) for lo, hi in pf_tilt(inwk, 9, 21, 0b1000)]   # (nosev + sidev) / 2

    def sc(k, v):
        m = (k * abs(v)) >> 15
        return -m if v < 0 else m
    A1 = [sc(S3, v) for v in u1]                # 12.4 pixels
    A2 = [sc(S3r2, v) for v in u2]
    N = 32 if S >= 120 * 64 else 16
    dots = []
    for k in range(N):
        i = k * (32 // N)
        s8 = SIN16[i] if i <= 16 else SIN16[32 - i]
        c8 = SIN16[16 - i] if i <= 16 else -SIN16[i - 16]

        def prod(c, a):
            p = abs(c) * abs(a)
            return -p if (c < 0) != (a < 0) else p
        P = [(prod(c8, a) + prod(s8, b)) >> 8 for a, b in zip(A1[:2], A2[:2])]
        hz = lambda a: -(abs(a) >> 8) if a < 0 else abs(a) >> 8     # (z: A's high bytes)
        Pz = prod(c8, hz(A1[2])) + prod(s8, hz(A2[2]))
        for sg in (1, -1):
            x = cx + ((sg * P[0]) >> 4)
            y = cy - ((sg * P[1]) >> 4)
            if 0 <= x <= 255 and 0 <= y <= 191:
                dots.append((x, y, sg * Pz < 0))
    return dots


SIN16 = [min(255, int(256 * math.sin(i * math.pi / 32) + 0.5)) for i in range(17)]   # (pf_ring's pfr_sin)
