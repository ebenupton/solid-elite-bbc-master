#!/usr/bin/env python3
"""The dashboard: a 256 x 56 MODE 1 image in the space view's CMYK palette.

    python3 2-build-files/dashboard.py [outdir]     (default master/build/)

(The Master port's version of the demo port's tools/dashboard.py: scanner
colours for Master Elite's 33 ship types, by colour class, and the missile
colours by Master's MSBAR arguments.)

writes
    DIALS1.bin      the 3584-byte image, loaded to &7000 (7 character rows of
                    64 bytes x 8 lines: &7000 + row * &200 + column * 8 + line)
    dashtab-*.asm   tables for the dashboard routines in elite-source.asm
                    (dials, scan, dot, spbt, ecbt, msbar: each at its routine)
                    (colour byte pairs, bulb bitmaps, missile shape), INCLUDEd
                    by the bank 4 part of the source
    dashboard.png   a preview of the static image (x4)
    dashmock.png    the same with the dynamic elements drawn at sample values
                    (bars, roll / pitch markers, scanner dots and sticks,
                    compass dot, missiles, bulbs), as the routines draw them

The colour, dot, bulb and missile tables are all generated here, so the look
of every dynamic element can be changed by editing the constants below.

Geometry (dashboard coordinates: x 0..255, line 0..55 = screen line 192..247):

    left panel   labels x 2..14, bars x 16..47 (bytes 4..11), rows 0..5
    scanner      x 49..206, centre (126, 28) (dot x = X1..X1+2, stick at X1+1)
    compass      centre (196, 11.5), dot 3 x 2 at COMX..COMX+2, COMY-1..COMY
                 (3 x 1 at COMY when the planet / station is behind)
    right panel  bars x 208..239 (bytes 52..59), labels x 241..254, rows 0..6
    bars         lines 2..4 of their character row, scale on lines 6..7
    roll/pitch   a 2-pixel marker at P, P+1 (P = 0..30, 15 = centre),
                 lines 1..5
    missiles     row 6, bytes 4+2k, 5+2k (k = 0..3, missile 4-k), lines 1..5
    bulbs        E.C.M. bytes 14-15, space station bytes 48-49 of row 5

Colours: inks K, C, M, Y = logical 0..3. A colour is a 2x2 cell (pixel (x, y)
takes the ink at (x AND 1, y AND 1), in screen coordinates; the dashboard
starts at an even line, so line parity is the same) and is stored for the
routines as a pair of bytes: the four-pixel byte for even lines and for odd.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from swatch35 import cell as dither_cell, PHYS   # noqa: E402

K, C, M, Y = 0, 1, 2, 3
W, H = 256, 56


def solid(i):
    return {(0, 0): i, (1, 0): i, (0, 1): i, (1, 1): i}


def dith(k, c, m, y):
    return dither_cell(k, c, m, y)


def checker(a, b):
    """a at (0, 0) and (1, 1), b at (1, 0) and (0, 1)"""
    return {(0, 0): a, (1, 1): a, (1, 0): b, (0, 1): b}


# The palette of the dashboard
COLS = {
    'K': solid(K), 'C': solid(C), 'M': solid(M), 'Y': solid(Y),
    'RED': checker(M, Y),          # magenta + yellow: red / orange
    'GRN': checker(C, Y),          # cyan + yellow: green
    'BLU': checker(C, M),          # cyan + magenta: blue / violet
    'dC': checker(C, K),           # half-bright inks
    'dM': checker(M, K),
    'dY': checker(Y, K),
    'dB': dith(2, 1, 1, 0),        # dark blue
}

# Indicator colours (as used by the routines; see dashtab.asm)
FRAME = 'C'
SCALE = 'M'          # bar scale baseline
TICK = 'M'            # bar scale ticks
LAB1 = 'C'            # FS AS FU / SP RL DC labels
LAB2 = 'M'            # CT LT AL / 1 2 3 4 labels
ELL = 'M'             # scanner ellipse
GRID = 'M'           # scanner grid
RING = 'C'            # compass ring
CROSS = 'M'           # compass cross-hair

BAR_SAFE = 'Y'        # shields, energy (PZW safe colour)
BAR_SAFE2 = 'C'       # speed, temperatures (PZW2 safe colour)
BAR_FUEL = 'Y'
BAR_ALT = 'C'
BAR_DANGER = 'RED'
BAR_FLASH = 'GRN'     # the alternate danger colour when flashing is on
MARKER = 'Y'          # roll / pitch marker

# Scanner colour classes (each has a dot / stick table entry), and the class of
# each ship type 0..33, from Master Elite's scacol (mode 2 colours): YELLOW2
# missile, GREEN2 station, BLUE2 pods, plates, canisters and the Worm, RED2
# rocks, MAG2 the Python, Boa and Anaconda, WHITE2 the Thargoid (yellow
# here), 0 the Cougar (cloaked: black, so EOR drawing leaves the scanner as
# it is), CYAN2 the rest
CLASSES = ['K', 'C', 'M', 'Y', 'GRN', 'BLU', 'RED']
MASTER_SCACOL = ['K', 'Y', 'GRN', 'BLU', 'BLU', 'BLU', 'RED', 'RED', 'RED', 'C', 'C', 'C', 'M',
                 'M', 'M', 'RED', 'C', 'C', 'C', 'C', 'C', 'C', 'C', 'BLU', 'C', 'C', 'M', 'C',
                 'C', 'Y', 'C', 'C', 'K', 'C']
SCACLASS = [CLASSES.index(c) for c in MASTER_SCACOL]
SCACOL = CLASSES
COMPASS_FRONT = 'Y'
COMPASS_BEHIND = 'GRN'
MISSILE = {0x00: 'K', 0x0C: 'C', 0x0F: 'Y', 0x03: 'RED'}   # MSBAR's Y argument (0, GREEN2, YELLOW2, RED2)
ECM_BULB = 'Y'
SST_BULB = 'C'

# 5 x 5 font
FONT = {
    'A': ['.###.', '#...#', '#####', '#...#', '#...#'],
    'C': ['.####', '#....', '#....', '#....', '.####'],
    'D': ['####.', '#...#', '#...#', '#...#', '####.'],
    'E': ['#####', '#....', '####.', '#....', '#####'],
    'F': ['#####', '#....', '####.', '#....', '#....'],
    'I': ['#####', '..#..', '..#..', '..#..', '#####'],
    'L': ['#....', '#....', '#....', '#....', '#####'],
    'P': ['####.', '#...#', '####.', '#....', '#....'],
    'R': ['####.', '#...#', '####.', '#..#.', '#...#'],
    'S': ['.####', '#....', '.###.', '....#', '####.'],
    'T': ['#####', '..#..', '..#..', '..#..', '..#..'],
    'U': ['#...#', '#...#', '#...#', '#...#', '.###.'],
    '1': ['.##..', '..#..', '..#..', '..#..', '.###.'],
    '2': ['####.', '....#', '.###.', '#....', '#####'],
    '3': ['####.', '....#', '.###.', '....#', '####.'],
    '4': ['#..#.', '#..#.', '#####', '...#.', '...#.'],
}
# 4 x 5 font for the labels (two letters in 9 pixels)
FONT4 = {
    'A': ['.##.', '#..#', '####', '#..#', '#..#'],
    'C': ['.###', '#...', '#...', '#...', '.###'],
    'D': ['###.', '#..#', '#..#', '#..#', '###.'],
    'F': ['####', '#...', '###.', '#...', '#...'],
    'L': ['#...', '#...', '#...', '#...', '####'],
    'P': ['###.', '#..#', '###.', '#...', '#...'],
    'R': ['###.', '#..#', '###.', '#.#.', '#..#'],
    'S': ['.###', '#...', '.##.', '...#', '###.'],
    'T': ['####', '.#..', '.#..', '.#..', '.#..'],
    'U': ['#..#', '#..#', '#..#', '#..#', '.##.'],
    '1': ['.#.', '##.', '.#.', '.#.', '###'],
    '2': ['###.', '...#', '.##.', '#...', '####'],
    '3': ['###.', '...#', '.##.', '...#', '###.'],
    '4': ['#.#.', '#.#.', '####', '..#.', '..#.'],
}

ECM_BITMAP = [      # 8 x 8, '#' = bulb colour (EOR'd onto black)
    '.######.',
    '##....##',
    '##.#####',
    '##...###',
    '##.#####',
    '##....##',
    '.######.',
    '........',
]
SST_BITMAP = [
    '.######.',
    '##....##',
    '##.#####',
    '###..###',
    '#####.##',
    '##....##',
    '.######.',
    '........',
]
MISSILE_SHAPE = [   # 8 x 5 (lines 1..5 of row 6), pointing right
    '#.......',
    '.####...',
    '#######.',
    '.####...',
    '#.......',
]


class Canvas:
    def __init__(self):
        self.p = [[K] * W for _ in range(H)]

    def put(self, x, y, col):
        if 0 <= x < W and 0 <= y < H:
            c = COLS[col] if isinstance(col, str) else col
            self.p[y][x] = c[(x & 1, y & 1)]

    def xor(self, x, y, col):
        if 0 <= x < W and 0 <= y < H:
            c = COLS[col] if isinstance(col, str) else col
            self.p[y][x] ^= c[(x & 1, y & 1)]

    def hline(self, x0, x1, y, col, step=1):
        for x in range(x0, x1 + 1, step):
            self.put(x, y, col)

    def vline(self, x, y0, y1, col, step=1):
        for y in range(y0, y1 + 1, step):
            self.put(x, y, col)

    def rect(self, x0, y0, x1, y1, col):
        for y in range(y0, y1 + 1):
            self.hline(x0, x1, y, col)

    def text(self, s, x, y, col, font=FONT, gap=1):
        for ch in s:
            g = font.get(ch)
            if g is None:
                x += 4
                continue
            for j, row in enumerate(g):
                for i, b in enumerate(row):
                    if b == '#':
                        self.put(x + i, y + j, col)
            x += len(g[0]) + gap

    def line(self, x0, y0, x1, y1, col, dotted=0):
        n = max(abs(x1 - x0), abs(y1 - y0))
        for i in range(n + 1):
            if dotted and i % dotted:
                continue
            x = x0 + (x1 - x0) * i / n if n else x0
            y = y0 + (y1 - y0) * i / n if n else y0
            self.put(int(round(x)), int(round(y)), col)

    def ellipse(self, cx, cy, a, b, col, dotted=0):
        """thin 1-pixel outline of the ellipse ((x-cx)/a)^2 + ((y-cy)/b)^2 = 1
        (cx, cy may be .5): a sweep in x where the outline is flatter than 45
        degrees and in y where it is steeper"""
        pts = set()
        # the 45-degree point: x offset where slope = 1
        xs = a * a / math.sqrt(a * a + b * b)
        for x in range(int(math.floor(cx - a)) - 1, int(math.ceil(cx + a)) + 2):
            dx = x - cx
            if abs(dx) <= xs:
                h = b * math.sqrt(max(0.0, 1 - (dx / a) ** 2))
                for sg in (-1, 1):
                    pts.add((x, int(math.floor(cy + sg * h + 0.5))))
        ys = b * b / math.sqrt(a * a + b * b)
        for y in range(int(math.floor(cy - b)) - 1, int(math.ceil(cy + b)) + 2):
            dy = y - cy
            if abs(dy) <= ys + 0.5:
                if abs(dy) > b:
                    continue
                w = a * math.sqrt(max(0.0, 1 - (dy / b) ** 2))
                for sg in (-1, 1):
                    pts.add((int(math.floor(cx + sg * w + 0.5)), y))
        for (x, y) in sorted(pts):
            if dotted and (x + y) % dotted:
                continue
            self.put(x, y, col)

    def tobytes(self):
        out = bytearray(3584)
        for y in range(H):
            r, l = divmod(y, 8)
            for c in range(64):
                b = 0
                for p in range(4):
                    v = self.p[y][4 * c + p]
                    b |= ((v >> 1) & 1) << (7 - p) | (v & 1) << (3 - p)
                out[r * 512 + c * 8 + l] = b
        return bytes(out)

    def png(self, path, scale=4):
        from PIL import Image
        img = Image.new('RGB', (W, H))
        img.putdata([PHYS[v] for row in self.p for v in row])
        img = img.resize((W * scale, H * scale), Image.NEAREST)
        img.save(path)


def pair(col):
    """(even-line byte, odd-line byte) of four pixels in colour col"""
    c = COLS[col]
    out = []
    for ly in (0, 1):
        b = 0
        for p in range(4):
            v = c[(p & 1, ly)]
            b |= ((v >> 1) & 1) << (7 - p) | (v & 1) << (3 - p)
        out.append(b)
    return tuple(out)


# ----------------------------------------------------------------------------
# The static image

SCX, SCY = 126, 28          # scanner centre (dot stick x = X1 + 1, Y1 = 220)
ELA, ELB = 67.5, 16.5       # ellipse semi-axes
CMX, CMY, CMR = 196, 11.5, 10.5   # compass ring

LROWS = ['FS', 'AS', 'FU', 'CT', 'LT', 'AL']
RROWS = ['SP', 'RL', 'DC', '1', '2', '3', '4']
LX0, RX0 = 16, 208          # bar left edges (32 pixels each)


def bar_scale(cv, x0, row, kind):
    """The scale under a bar: a baseline on line 7 and ticks on line 6 (in the
    bottom row, whose line 7 is the frame, the baseline on line 6 and no
    ticks, so nothing touches the frame)"""
    y = row * 8
    if row == 6:
        cv.hline(x0, x0 + 31, y + 6, SCALE)
        return
    cv.hline(x0, x0 + 31, y + 7, SCALE)
    if kind == 'centre':                    # roll / pitch: centre and ends
        for x in (x0, x0 + 31):
            cv.put(x, y + 6, TICK)
        cv.put(x0 + 15, y + 6, TICK)
        cv.put(x0 + 16, y + 6, TICK)
        cv.put(x0 + 15, y + 7, TICK)
        cv.put(x0 + 16, y + 7, TICK)
        for x in (x0 + 7, x0 + 8, x0 + 23, x0 + 24):
            cv.put(x, y + 7, TICK)
        return
    for i in range(0, 33, 8):
        x = min(x0 + i, x0 + 31)
        cv.put(x, y + 6, TICK)


def draw_static():
    cv = Canvas()
    # outer frame
    cv.hline(0, 255, 0, FRAME)
    cv.hline(0, 255, 55, FRAME)
    cv.vline(0, 0, 55, FRAME)
    cv.vline(255, 0, 55, FRAME)
    # panel dividers
    for x in (48, 207):
        cv.vline(x, 0, 55, FRAME)
    # left panel
    for r, lab in enumerate(LROWS):
        cv.text(lab, 2, r * 8 + 2, LAB1 if r < 3 else LAB2, FONT4)
        bar_scale(cv, LX0, r, 'bar')
    # danger thresholds (temperatures at 22 of 32 pixels)
    for r in (3, 4):
        cv.put(LX0 + 22, r * 8 + 6, 'Y')
        cv.put(LX0 + 22, r * 8 + 7, 'Y')
    # right panel
    for r, lab in enumerate(RROWS):
        x = 243 if len(lab) == 2 else 247
        cv.text(lab, x, r * 8 + 2, LAB1 if r < 3 else LAB2, FONT4)
        bar_scale(cv, RX0, r, 'centre' if r in (1, 2) else 'bar')
    cv.put(RX0 + 28, 6, 'Y')            # speed danger threshold
    cv.put(RX0 + 28, 7, 'Y')
    # missile icon, bottom left (row 6, lines 1..5)
    y = 49
    cv.hline(3, 11, y + 2, 'C')
    cv.hline(4, 10, y + 1, 'dC')
    cv.hline(4, 10, y + 3, 'dC')
    cv.put(12, y + 2, 'Y')
    cv.put(2, y, 'M'); cv.put(2, y + 4, 'M'); cv.put(3, y + 1, 'M'); cv.put(3, y + 3, 'M')

    # scanner: grid then ellipse
    # horizontal lines (perspective: closer together towards the back)
    for yy, half in ((SCY - 9, 0.83), (SCY, 1.0), (SCY + 9, 0.83)):
        # extent of the ellipse at this line
        dy = (yy - SCY) / ELB
        w = ELA * math.sqrt(max(0.0, 1 - dy * dy))
        for x in range(int(SCX - w) + 2, int(SCX + w) - 1):
            if (x - SCX) % 2 == 0:
                cv.put(x, yy, GRID)
    # vertical centre line
    for yy in range(int(SCY - ELB) + 2, int(SCY + ELB) - 1):
        if (yy - SCY) % 2 == 0:
            cv.put(SCX, yy, GRID)
    # perspective lines: from the back of the ellipse towards the viewer
    for s in (-1, 1):
        x0, y0 = SCX + s * 20, SCY - ELB + 1
        x1, y1 = SCX + s * 46, SCY + ELB - 4
        n = int(abs(y1 - y0))
        for i in range(0, n + 1, 2):
            t = i / n
            cv.put(int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t)), GRID)
    cv.ellipse(SCX + 0.0, SCY + 0.0, ELA, ELB, ELL)
    # range ticks on the centre line
    for dx in (-44, -22, 22, 44):
        cv.put(SCX + dx, SCY - 1, 'C')
        cv.put(SCX + dx, SCY + 1, 'C')
    cv.put(SCX, SCY, 'C')

    # compass ring and cross-hair: dashed, as Master's (P.DIALS2P), clear of the
    # centred dot (x 195..197, lines 10..12), so the dot (EOR) sits in the gap
    # when the planet or station is dead ahead
    cv.ellipse(CMX, CMY, CMR, CMR, RING)
    for d in (2, 3, 6, 7):
        cv.put(CMX - d, 11, CROSS)
        cv.put(CMX + d, 11, CROSS)
    for d in (3, 5, 7, 9):
        cv.put(CMX, 11 - d, CROSS)
        cv.put(CMX, 11 + d, CROSS)
    # corner ornaments of the scanner
    for (x, y, sx, sy) in ((49, 1, 1, 1), (206, 54, -1, -1), (49, 54, 1, -1)):
        for i in range(4):
            for j in range(4 - i):
                cv.put(x + sx * j, y + sy * i, 'BLU')
    # ELITE
    cv.text('ELITE', 126 - 14, 49, 'C', FONT, gap=1)
    return cv


# ----------------------------------------------------------------------------
# Dynamic elements, drawn as the routines do (for the mock-up)

def mock(cv):
    import copy
    m = copy.deepcopy(cv)

    def bar(x0, row, L, col):
        for y in range(row * 8 + 2, row * 8 + 5):
            for x in range(x0, x0 + min(L, 32)):
                m.put(x, y, col)

    def marker(x0, row, P, col):
        for y in range(row * 8 + 1, row * 8 + 6):
            m.put(x0 + P, y, col)
            m.put(x0 + P + 1, y, col)

    bar(LX0, 0, 30, BAR_SAFE)
    bar(LX0, 1, 4, BAR_DANGER)
    bar(LX0, 2, 17, BAR_FUEL)
    bar(LX0, 3, 9, BAR_SAFE2)
    bar(LX0, 4, 25, BAR_DANGER)
    bar(LX0, 5, 14, BAR_ALT)
    bar(RX0, 0, 21, BAR_SAFE2)
    marker(RX0, 1, 9, MARKER)
    marker(RX0, 2, 15, MARKER)
    for i, L in enumerate((32, 32, 19, 0)):
        bar(RX0, 3 + i, L, BAR_SAFE)

    def dot(X1, Y1, col, h=2):
        for yy in range(Y1 - h + 1, Y1 + 1):
            for x in range(X1, X1 + 3):
                m.xor(x, yy - 192, col)

    def ship(X1, Y1, SCv, col):
        dot(X1, Y1, col)
        x = X1 + 1
        if Y1 > SCv:      # stick upwards
            for yy in range(SCv, Y1 - 1):
                m.xor(x, yy - 192, col)
        else:
            for yy in range(Y1 + 1, SCv + 1):
                m.xor(x, yy - 192, col)

    ship(100, 230, 215, 'C')
    ship(150, 205, 222, 'C')
    ship(170, 226, 230, 'GRN')
    ship(80, 212, 228, 'RED')
    ship(126, 221, 221, 'M')
    dot(193, 206, COMPASS_FRONT)
    for k, colkey in enumerate((0x0C, 0x0C, 0x0F, 0x03)):   # missiles 4..1
        col = MISSILE[colkey]
        x0 = (4 + 2 * k) * 4
        for j, row in enumerate(MISSILE_SHAPE):
            for i, b in enumerate(row):
                if b == '#':
                    m.put(x0 + i, 49 + j, col)
    for (bm, x0, col) in ((ECM_BITMAP, 56, ECM_BULB), (SST_BITMAP, 192, SST_BULB)):
        for j, row in enumerate(bm):
            for i, b in enumerate(row):
                if b == '#':
                    m.xor(x0 + i, 40 + j, col)
    return m


# ----------------------------------------------------------------------------
# Tables for the routines

def bitmap_bytes(bm, col, x0, y0):
    """16 bytes: byte column x0/4 lines 0..7, then the next column (EOR data)"""
    out = []
    for cb in range(2):
        for j in range(8):
            b = 0
            for p in range(4):
                x = x0 + cb * 4 + p
                if bm[j][cb * 4 + p] == '#':
                    v = COLS[col][(x & 1, (y0 + j) & 1)]
                    b |= ((v >> 1) & 1) << (7 - p) | (v & 1) << (3 - p)
            out.append(b)
    return out


def shape_masks(shape):
    """per line, the masks of the two bytes (both colour bits per pixel)"""
    out = []
    for row in shape:
        for cb in range(2):
            b = 0
            for p in range(4):
                if row[cb * 4 + p] == '#':
                    b |= 0x88 >> p
            out.append(b)
    return out


def tables():
    """the tables, one file each for the routine that uses them, at its place
    in elite-source.asm: {name: text} for build/dashtab-<name>.asm"""
    out = {}
    L = []

    def pairdef(name, col):
        e, o = pair(col)
        L.append(' %s_E = &%02X : %s_O = &%02X    \\ %s' % (name, e, name, o, col))

    for n, c in (('DC_SAFE', BAR_SAFE), ('DC_SAFE2', BAR_SAFE2), ('DC_FUEL', BAR_FUEL),
                 ('DC_ALT', BAR_ALT), ('DC_DANGER', BAR_DANGER), ('DC_FLASH', BAR_FLASH),
                 ('DC_MARK', MARKER)):
        pairdef(n, c)
    out['dials'], L = L, []
    # Dot and stick bytes for each scanner colour class (CLASSES, then the
    # compass in front and behind) and pixel phase p = x AND 3 of the dot's
    # left pixel (3 pixels wide, stick at its middle pixel): index 4 * c + p
    cols = SCACOL + [COMPASS_FRONT, COMPASS_BEHIND]
    tabs = {k: [] for k in ('dt0E', 'dt0O', 'dt1E', 'dt1O', 'dtsE', 'dtsO')}
    for col in cols:
        e, o = pair(col)
        for ph in range(4):
            m0 = m1 = 0
            for i in range(3):
                q = ph + i
                if q < 4:
                    m0 |= 0x88 >> q
                else:
                    m1 |= 0x88 >> (q - 4)
            q = ph + 1
            sm = 0x88 >> (q % 4)
            tabs['dt0E'].append(e & m0); tabs['dt0O'].append(o & m0)
            tabs['dt1E'].append(e & m1); tabs['dt1O'].append(o & m1)
            tabs['dtsE'].append(e & sm); tabs['dtsO'].append(o & sm)
    L.append('\\ dot (byte 0, byte 1) and stick bytes for even and odd lines, by')
    L.append('\\ 4 * colour + (x AND 3) (the stick is in byte 1 iff x AND 3 = 3)')
    for k, v in tabs.items():
        L.append('.' + k)
        for i in range(0, len(v), 16):
            L.append(' EQUB ' + ', '.join('&%02X' % b for b in v[i:i + 16]))
    out['dot'], L = L, []
    L.append(' DT_FRONT = %d : DT_BEHIND = %d   \\ the compass dot\'s classes' % (len(CLASSES), len(CLASSES) + 1))
    L.append('.dtcls                  \\ scanner colour class * 4 by ship type 0..33')
    L.append(' EQUB ' + ', '.join('%d' % (4 * c) for c in SCACLASS))
    out['scan'], L = L, []
    L.append('.dmscolE                \\ missiles: none, unarmed, armed, locked')
    L.append(' EQUB ' + ', '.join('&%02X' % pair(MISSILE[k])[0] for k in (0, 0x0C, 0x0F, 0x03)))
    L.append('.dmscolO')
    L.append(' EQUB ' + ', '.join('&%02X' % pair(MISSILE[k])[1] for k in (0, 0x0C, 0x0F, 0x03)))
    L.append('.dmsmask                \\ missile shape: lines 1..5, (left, right) byte masks')
    L.append(' EQUB ' + ', '.join('&%02X' % b for b in shape_masks(MISSILE_SHAPE)))
    out['msbar'] = L
    out['ecbt'] = ['.ECBT                   \\ E.C.M. bulb (EOR), bytes 14-15 of row 5',
                   ' EQUB ' + ', '.join('&%02X' % b for b in bitmap_bytes(ECM_BITMAP, ECM_BULB, 56, 40))]
    out['spbt'] = ['.SPBT                   \\ space station bulb (EOR), bytes 48-49 of row 5',
                   ' EQUB ' + ', '.join('&%02X' % b for b in bitmap_bytes(SST_BITMAP, SST_BULB, 192, 40))]
    return {k: '\n'.join(['\\ Generated by tools/dashboard.py - do not edit', ''] + v) + '\n' for k, v in out.items()}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build')   # master/build
    os.makedirs(out, exist_ok=True)
    cv = draw_static()
    open(os.path.join(out, 'DIALS1.bin'), 'wb').write(cv.tobytes())
    for k, v in tables().items():
        open(os.path.join(out, 'dashtab-%s.asm' % k), 'w').write(v)
    try:
        cv.png(os.path.join(out, 'dashboard.png'))
        mock(cv).png(os.path.join(out, 'dashmock.png'))
    except ImportError:
        pass


if __name__ == '__main__':
    main()
