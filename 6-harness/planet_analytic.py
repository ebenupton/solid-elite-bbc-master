"""Reference model of the analytic meridian boundaries (frame.asm f_merid):
per row, where each great circle's projected ellipse crosses the row, from
the planet's orientation vectors.

Great circle with normal m (Elite axes, y up; visible hemisphere z > 0),
screen offsets X = x - cx, Ys = y - cy (down), m' = (mx, -my, mz) with mz >= 0
(m negated if not, which inverts that circle's colour). On the visible
hemisphere f = mx X + my' Ys + mz Z, Z = sqrt(r^2 - X^2 - Ys^2), is concave
along a row, so {f > 0} is an interval; the crossings are the roots of
(mx X + my' Ys)^2 = mz^2 (r^2 - X^2 - Ys^2):
    X = a Ys -/+ sqrt(D),  a = -mx my' / rho2,  rho2 = mx^2 + mz^2,
    D = K0 - K2 Ys^2,  K0 = r^2 mz^2 / rho2,  K2 = mz^2 N / rho2^2
(N = |m|^2); the X- root is a boundary iff f(-h) <= 0 and X+ iff f(h) <= 0
(h = the row's half-width), and the row starts (left limb) in {f > 0} iff
f(-h) > 0. Along the limb f changes sign only at the nodes (Z = 0, f = 0):
Ys = +/-w, w = r mx / sqrt(mx^2 + my^2), so the validity of X+/X- is a
comparison of the row with a threshold row.

analytic_rows(..., fixed=False) evaluates this in floating point;
fixed=True emulates the 6502 implementation's integer arithmetic exactly.
"""
import math


def sm16(lo, hi):
    v = lo | ((hi & 127) << 8)
    return -v if hi & 128 else v


def circle_consts(m, r):
    mx, my, mz = m
    myp = -my
    inv = 0
    if mz < 0:
        mx, myp, mz = -mx, -myp, -mz
        inv = 1
    N = mx * mx + myp * myp + mz * mz
    rho2 = mx * mx + mz * mz
    rho2 = max(rho2, N * 1e-5)
    a = -mx * myp / rho2
    K0 = r * r * mz * mz / rho2
    K2 = mz * mz * N / (rho2 * rho2)
    q = math.sqrt(mx * mx + myp * myp)
    w = r * mx / q if q > 0 else 0.0
    return dict(inv=inv, a=a, K0=K0, K2=K2, w=w, pos=(myp >= 0))


def analytic_rows_float(cx, cy, r, normals, ndt, ndb, ndl, ndr, pol=1):
    rows = {}
    for y in range(ndt, ndb + 1):
        rows[y] = [pol, []]
    for m in normals:
        c = circle_consts(m, r)
        w = c["w"]
        for y in range(ndt, ndb + 1):
            Ys = y - cy
            if c["pos"]:
                vp = Ys <= -w; vm = Ys <= w
            else:
                vp = Ys >= w; vm = Ys >= -w
            st = rows[y]
            st[0] ^= c["inv"] ^ (0 if vm else 1)
            D = c["K0"] - c["K2"] * Ys * Ys
            if D < 0:
                if vm != vp:
                    D = 0.0
                else:
                    continue
            s = math.floor(math.sqrt(D) + 0.5)
            cc = math.ceil(cx + c["a"] * Ys)
            for valid, b in ((vm, cc - s), (vp, cc + s)):
                if not valid:
                    continue
                if b <= ndl[y]:
                    st[0] ^= 1
                elif b <= ndr[y]:
                    st[1].append(b)
    return {y: (v[0], sorted(v[1])) for y, v in rows.items()}


# ---------------------------------------------------------------- fixed point

def isqrt(n):
    return math.isqrt(n)


def fdiv(u, v):
    """the 6502 division (planet4.asm pm_fdiv), u/v as 16.16 with a 12-bit
    mantissa: while either is >= 2^24 both are shifted right a byte; each is
    normalised (shifted left until bit 23 is set) and its top 16 bits taken,
    U' and V'; q = floor(U' 2^11 / V') (12 steps, 2^10 <= q < 2^12), and the
    result q shifted by 5 + ev - eu (ev, eu: the left shifts), saturated to
    32 bits. u = 0 gives 0 (v > 0)."""
    if u == 0:
        return 0
    while u >= 1 << 24 or v >= 1 << 24:
        u >>= 8
        v >>= 8
        if u == 0:
            return 0
    eu = 24 - u.bit_length()
    ev = 24 - v.bit_length()
    U = (u << eu) >> 8
    V = (v << ev) >> 8
    q = (U << 11) // V
    sh = 5 + ev - eu
    r = q << sh if sh >= 0 else q >> -sh
    return min(r, 0xFFFFFFFF)


def udiv16(u, v, ibits):
    """floor(u * 2^16 / v), saturated to ibits integer bits (+16 fraction):
    restoring division, 16 + ibits quotient bits (as the 6502 code)"""
    q = (u << 16) // v
    mx = (1 << (16 + ibits)) - 1
    return min(q, mx)


def fixed_consts(m, r):
    """the 6502 code's per-circle constants. m = sign-magnitude 16-bit
    components (as INWK), magnitudes reduced to 12 bits"""
    mx, my, mz = m
    myp = -my
    inv = 0
    if mz < 0:
        mx, myp, mz = -mx, -myp, -mz
        inv = 1
    ax, ay, az = abs(mx) >> 3, abs(myp) >> 3, abs(mz) >> 3
    X2, Y2, Z2, XY = ax * ax, ay * ay, az * az, ax * ay
    R2 = X2 + Z2
    if R2 == 0:
        R2 = 1
    Q2 = X2 + Y2
    if Q2 == 0:
        Q2 = 1
    t = min(fdiv(Z2, R2), 0xFFFF)    # mz^2 / rho2, 0.16
    u = fdiv(Y2, R2)                 # my^2 / rho2, 16.16
    am = min(fdiv(XY, R2), 0xFFFFFF) # |a|, 8.16
    v = min(fdiv(X2, Q2), 0xFFFF)    # mx^2 / (mx^2 + my^2), 0.16
    r2 = r * r
    K0 = (r2 * t) >> 0               # 16.16 (r2 * 0.16)
    K2 = (t * (u + 65536)) >> 16     # 16.16, = t (1 + u)
    K2 = min(K2, 0xFFFFFFFF)
    W2 = r2 * v                      # 16.16
    a = am if (mx < 0) != (myp < 0) else -am   # a = -mx my' / rho2
    return dict(inv=inv, a=a, K0=K0, K2=K2, W2=W2, wneg=(mx < 0), pos=(myp >= 0))


def thresholds(c, cy):
    """per circle: uP, uM (8-bit screen rows, 0..192) and neg: X+ valid iff
    (y < uP) xor neg, X- valid iff (y < uM) xor neg"""
    W2 = c["W2"]
    f = isqrt(W2 >> 16)
    cl = f + (1 if f * f * 65536 < W2 else 0)      # ceil(|w|)
    if not c["wneg"]:
        fl_w, ce_w = f, cl
    else:
        fl_w, ce_w = -cl, -f
    if c["pos"]:   # X+ iff Ys <= -w = floor(-w) = -ce_w; X- iff Ys <= floor(w)
        tP = cy - ce_w; tM = cy + fl_w
        neg = False
    else:          # X+ iff Ys >= ceil(w) <=> !(Ys <= ceil(w)-1); X- iff Ys >= ceil(-w) = -fl_w
        tP = cy + ce_w - 1; tM = cy - fl_w - 1
        neg = True
    clamp = lambda t: max(0, min(192, t + 1))
    return clamp(tP), clamp(tM), neg, cl


def analytic_rows_fixed(cx, cy, r, normals, ndt, ndb, ndl, ndr, pol=1):
    rows = {}
    cs = [fixed_consts(m, r) for m in normals]
    th = [thresholds(c, cy) for c in cs]
    for y in range(ndt, ndb + 1):
        p = pol
        for c, (uP, uM, neg, cl) in zip(cs, th):
            vm = (y < uM) != neg
            p ^= c["inv"] ^ (0 if vm else 1)
        rows[y] = [p, []]
    kvis = max(cy - ndt, ndb - cy)
    for c, (uP, uM, neg, kw) in zip(cs, th):
        K0, K2 = c["K0"], c["K2"]
        s = isqrt(K0 >> 16)         # s0 = round(sqrt(K0)) (planet4.asm, PM_HOOK)
        if K0 >= (s * s + s) * 65536 + 16384:
            s += 1
        # the row loop tracks D/2 (16.16): D(k)/2 - D(k+1)/2 = K2 (2k + 1) / 2
        D = K0 >> 9                 # (kept to 1/256)
        dl = K2 >> 1
        inc = K2
        H = (s * s - s) >> 1        # s drops when D/2 < H + 1/8 (D < s^2 - s + 1/4)
        Cd = cx * 65536
        past = False
        k = 0
        while k <= kvis:
            if past and k > kw:
                break
            # s = round(sqrt(D))
            if not past:
                while s > 0 and D < H * 256 + 0x20:
                    s -= 1
                    H -= s
            ss = 0 if past else s
            cdn = (Cd >> 16) + (1 if Cd & 0xFFFF else 0)
            cup = 2 * cx - (Cd >> 16)
            for y, cc in ((cy + k, cdn), (cy - k, cup)) if k else ((cy, cdn),):
                if not (ndt <= y <= ndb):
                    continue
                vp = (y < uP) != neg
                vm = (y < uM) != neg
                if past and vp == vm:
                    continue
                st = rows[y]
                for valid, b in ((vm, cc - ss), (vp, cc + ss)):
                    if not valid:
                        continue
                    if b <= ndl[y]:
                        st[0] ^= 1
                    elif b <= ndr[y]:
                        st[1].append(b)
            # next k
            if not past:
                if dl >> 8 > D:
                    past = True
                else:
                    D -= dl >> 8
                    dl = min(dl + inc, 0xFFFFFFFF)
            Cd += c["a"]
            k += 1
    return {y: (v[0], sorted(v[1])) for y, v in rows.items()}


def analytic_rows(cx, cy, r, normals, ndt, ndb, ndl, ndr, pol=1, fixed=True):
    f = analytic_rows_fixed if fixed else analytic_rows_float
    return f(cx, cy, r, normals, ndt, ndb, ndl, ndr, pol)


def frame_normals(inwk):
    roof = [sm16(inwk[15], inwk[16]), sm16(inwk[17], inwk[18]), sm16(inwk[19], inwk[20])]
    side = [sm16(inwk[21], inwk[22]), sm16(inwk[23], inwk[24]), sm16(inwk[25], inwk[26])]
    return [side, roof]
