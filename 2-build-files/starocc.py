#!/usr/bin/env python3
"""Prove that no star can show through a filled object (R_STARPLOT's rule).

    python3 2-build-files/starocc.py [build dir]      (default 3-assembled-output)

R_STARPLOT (gfx-raster.asm) sets a star's pixels in a screen byte only if the
whole byte is black there. Every fill the renderer draws (polygons, the disc
layer and its colour boundaries, the second disc's spans, dots) takes row y's
byte from a colour of at most four rows (row y AND 3 of a 4x4 tile, or a
2-row pair), and a MODE 1 byte is four pixels of one row: a byte wholly inside
a fill IS that tile row's byte. So a fill hides every star in its interior if
each row byte of its colour is non-zero. In a byte only partly covered by a
fill the star is plotted only if the covered pixels are black: the fill's
visible edge on that row is then in the next byte, and the star lies on
black, within three pixels of it.

This checks every colour the frame layer can give a fill, as the build has
them (the bank 6 image and the symbols, so the tables are what the 6502
reads):
  * every writer of the colour bytes (R_COLE, R_COLO, R_COL2, R_COL3, R_DCE,
    R_DCO, R_DBE, R_DBO) in 1-source-files/main-sources/gfx-*.asm must be one this tool knows
    (WRITERS: the source of its value), so a new one fails until it is added;
  * f_col's colours (gfx-frame.asm), computed as f_col computes them from
    bank 6's tables: every hue ramp entry (9 ramps x 32 levels), the unlit
    colours LT_FIX that the ships' polygon details use, and the hangar's
    wall and floor (HPWL/HPWH);
  * the colours loaded as immediates (the discs: FC_PLANE/O, FC_SUNE/O,
    colour B's land pair; the second disc), the moon's (mn_ce/mn_co, in a
    build with moons, make moon=on), the
    distant-dot colours (FC_DOTE/O) and F_CPE/F_CPO's fixed colours;
and requires every row byte of each to be non-zero, except the pure black
fills it names, each with how stars are kept off it:
  * the docking slots (unlit black polygon details, colour byte &80 + 4 *
    fill visibility): f_slot (gfx-frame_cold.asm) takes the stars in the
    slot's bounding box, which f_poly2 leaves in F_SLV, out of the plot; checked
    here: they are the only black polygon details, and have four vertices
    (F_SLV holds four);
  * FC_BLACK (F_CPE entry 0), the hangar's lines: HALL's TT66 runs F_DIRECT
    (gfx-frame_cold.asm), whose f_direct0 clears R_SS (only an in-system
    jump, GWARP, keeps it), and nothing records a star until the next
    launch, so the hangar's frames plot no stars.
Prints each colour family's count and "STAROCC PASS", or the failures and
"STAROCC FAIL"; exit status 0 only on PASS.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                # the repository
SRC = os.path.join(ROOT, '1-source-files', 'main-sources')
BUILD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, '3-assembled-output')

fails = []


def fail(msg):
    fails.append(msg)
    print('FAIL ' + msg)


# ---- the build: symbols and bank 6
txt = open(os.path.join(BUILD, 'symbols.txt')).read()
SY = {k: int(v) for k, v in re.findall(r"'([^']+)':(-?\d+)L?", txt)}
B6 = open(os.path.join(BUILD, 'BANK6.bin'), 'rb').read()
for fn in os.listdir(SRC):                  # (constants: the symbol dump has labels)
    if fn.startswith('gfx-') and fn.endswith('.asm'):
        for l in open(os.path.join(SRC, fn)):
            for k, v in re.findall(r'(?:^|:)\s*([A-Z][A-Z0-9_]*)\s*=\s*(&[0-9A-F]+|\d+)\s*(?=:|\\|$)', l.rstrip()):
                SY.setdefault(k, int(v[1:], 16) if v[0] == '&' else int(v))


def b6(label, n, off=0):
    a = SY[label] + off - 0x8000
    assert 0 <= a and a + n <= len(B6), label
    return list(B6[a:a + n])


# ---- every writer of the colour bytes, and where its value comes from
COLS = 'R_COLE|R_COLO|R_COL2|R_COL3|R_DCE|R_DCO|R_DBE|R_DBO'
# (file, the instruction loading the value) -> what it is. An immediate load
# (LDA #value: the discs' colours, colour B's) needs no entry: its value is
# read from the source and checked, the even row's with the odd row's that
# follows it.
WRITERS = {
    ('gfx-frame.asm', 'LDA F_CPE,X'): 'fixed', ('gfx-frame.asm', 'LDA F_CPO,X'): 'fixed',  # f_setcol
    ('gfx-frame.asm', 'LDA F_CPE+FC_SIGHT'): 'fixed',
    ('gfx-frame.asm', 'LDA LT_FIX,Y'): 'unlit',             # f_col's fc_fix
    ('gfx-frame.asm', 'EOR fc_row'): 'ramp', ('gfx-frame.asm', 'EOR fc_row+1'): 'ramp',  # f_col
    ('gfx-frame.asm', 'EOR fc_row+2'): 'ramp', ('gfx-frame.asm', 'EOR fc_row+3'): 'ramp',
    ('gfx-frame.asm', 'LDA FC_DOTE,Y'): 'dot', ('gfx-frame.asm', 'LDA FC_DOTO,Y'): 'dot',
    ('gfx-hangar.asm', 'LDA #FC_BLACK'): 'fixed',           # (f_setcol's A, black)
    ('gfx-frame.asm', 'LDA mn_ce,X'): 'moon', ('gfx-frame.asm', 'LDA mn_co,X'): 'moon',  # f_moon
    ('gfx-raster_disc.asm', 'LDY R_DBE'): 'swap', ('gfx-raster_disc.asm', 'LDY R_DBO'): 'swap',  # A <-> B
}
wpat = re.compile(r'^\s*(?:\.\S+\s+)?ST[AXYZ]\s+(%s)\b' % COLS)
lpat = re.compile(r'^\s*(?:\.\S+\s+)?(LD[AXY]|PLA|T[AXY][AXY]|AND|EOR|ORA)\b')
seen = set()
nw = 0
imm = []                                    # (colour byte, value) of the immediate loads, in order
for fn in sorted(os.listdir(SRC)):
    if not (fn.startswith('gfx-') and fn.endswith('.asm')):
        continue
    L = open(os.path.join(SRC, fn)).read().split('\n')
    for i, l in enumerate(L):
        if not wpat.match(l):
            continue
        j = i - 1
        while j >= 0 and not lpat.match(L[j]):
            j -= 1
        src = ' '.join(L[j].split('\\')[0].split()) if j >= 0 else '?'
        nw += 1
        m = re.match(r'LDA #(&[0-9A-F]+|\d+|[A-Z][A-Z0-9_]*)$', src)
        if m and (fn, src) not in WRITERS:
            v = m.group(1)
            imm.append((wpat.match(l).group(1), int(v[1:], 16) if v[0] == '&' else int(v) if v.isdigit() else SY[v]))
            continue
        if (fn, src) not in WRITERS:
            fail('%s:%d: %s from "%s": a colour source this tool does not know (add it to WRITERS)'
                 % (fn, i + 1, l.split('\\')[0].strip(), src))
        seen.add((fn, src))
for k in WRITERS:
    if k not in seen:
        fail('WRITERS lists %s "%s", which no longer writes a colour byte' % k)
print('%d colour byte writers' % nw)


def rows_ok(name, rows):
    """every row byte non-zero"""
    if any(r == 0 for r in rows):
        fail('%s: rows %s: a row with no pixel set (a star would show through)'
             % (name, ' '.join('&%02X' % r for r in rows)))
        return False
    return True


# ---- f_col's ramps, as the 6502 makes them
HL = [b6('LT_HL0', 17, 17 * r) for r in range(4)]
assert SY['LT_HL1'] == SY['LT_HL0'] + 17 and SY['LT_HL3'] == SY['LT_HL0'] + 51
NRAMP = SY['LT_RH'] - SY['LT_RL']
RL, RH = b6('LT_RL', NRAMP), b6('LT_RH', NRAMP)


def f_col(lo, hi):
    a, c, b = lo & 31, hi >> 2, (hi & 3) * 8 + (lo >> 5)
    return [((HL[r][a] ^ HL[r][c]) & 0xF0) ^ HL[r][b] for r in range(4)]


n = 0
for k in range(NRAMP):
    p = RL[k] + 256 * RH[k] - 0x8000
    for lev in range(32):
        rows_ok('ramp %d level %d' % (k, lev), f_col(B6[p + lev], B6[p + 32 + lev]))
        n += 1
print('ramps: %d ramps x 32 levels = %d colours' % (NRAMP, n))
HPW = list(zip(b6('HPWL', 2), b6('HPWH', 2)))
for i, (lo, hi) in enumerate(HPW):
    rows_ok('hangar panel %d' % i, f_col(lo, hi))
print('hangar: %d panels (wall, floor)' % len(HPW))

# ---- the ships' faces and details (gfx-faces.asm, which the build assembles)
FIX = b6('LT_FIX', 4)
faces = open(os.path.join(SRC, 'gfx-faces.asm')).read().split('\n')
blk = None
nf = nd = 0
slots = []
for l in faces:
    m = re.match(r'^\.FC_S(\d+)_([FD])\b', l)
    if m:
        blk = m.group(2)
        typ = int(m.group(1))
        continue
    if l.startswith('.') or not l.startswith(' EQUB') or blk is None:
        if l.startswith('.'):
            blk = None
        continue
    body = l.split('\\')[0][5:]
    if blk == 'F':
        m = re.match(r'\s*(\d+) \+ 16 \* (\d+),', body)
        nv, c = int(m.group(1)), int(m.group(2))
        if c >= NRAMP:
            fail('type %d: face ramp %d out of range' % (typ, c))
        nf += 1
        continue
    v = [x.strip() for x in body.split(',')]
    if len(v) < 4:
        continue                                        # (a count: fins, details)
    col, nv = int(v[2].replace('&', '0x'), 16), int(v[3])
    nd += 1
    if nv < 3:
        continue                                        # a line
    if col & 0x80:
        rows = [FIX[col & 3]] * 4
        if not any(rows):
            slots.append((typ, nv, col))
            if nv != 4:
                fail('type %d: a black polygon detail with %d vertices (F_SLV holds 4)' % (typ, nv))
            continue
        rows_ok('type %d unlit polygon detail &%02X' % (typ, col), rows)
    elif col >= NRAMP:
        fail('type %d: detail ramp %d out of range' % (typ, col))
print('ships: %d faces, %d details and fins; black polygons (docking slots, f_slot): %s'
      % (nf, nd, ', '.join('type %d &%02X' % (t, c) for t, _, c in slots)))
names = {int(t): nm for nm, t in re.findall(r'^\\ (.+?) \(type (\d+)\):', '\n'.join(faces), re.M)}
for t, _, _ in slots:
    if 'station' not in names.get(t, ''):
        fail('type %d (%s): a black polygon detail on a ship that is not a station' % (t, names.get(t)))

# ---- discs, dots, fixed colours
pairs = []
for (t0, e), (t1, o) in zip(imm[::2], imm[1::2]):  # (each set as even, then odd)
    if not (t0[-1] == 'E' and t1[-1] == 'O' and t0[:-1] == t1[:-1]):
        fail('immediate colours not set as even/odd pairs: %s then %s' % (t0, t1))
    rows_ok('colour %s/%s' % (t0, t1), [e, o])
    pairs.append('&%02X/&%02X' % (e, o))
if len(imm) % 2:
    fail('an unpaired immediate colour')
print('immediate colours (the discs: the planet, the sun, colour B; the second disc): %s' % ', '.join(sorted(set(pairs))))
NT = SY['FC_NTYPES']
de, do = b6('FC_DOTE', NT + 1), b6('FC_DOTO', NT + 1)
for t in range(1, NT + 1):
    rows_ok('type %d distant dot' % t, [de[t], do[t]])
print('distant dots: %d types' % NT)
if 'mn_ce' in SY:                                       # (a build with moons, make moon=on)
    mce, mco = b6('mn_ce', 2), b6('mn_co', 2)
    for i in range(2):
        rows_ok('moon colour %d' % i, [mce[i], mco[i]])
    print('the moon: light grey &%02X/&%02X, dark grey &%02X/&%02X' % (mce[0], mco[0], mce[1], mco[1]))
else:
    print('the moon: none (make moon=on builds it)')
NCP = SY['FC_STAR'] + 1
cpe = b6('F_CPE', NCP)
for i in range(NCP):
    if i == SY['FC_BLACK']:
        if cpe[i]:
            fail('FC_BLACK is not black')
        continue                                        # the hangar's lines (no stars there)
    rows_ok('fixed colour %d' % i, [cpe[i]])
print('fixed colours: %d (FC_BLACK: the hangar\'s lines only)' % NCP)

print('STAROCC FAIL (%d)' % len(fails) if fails else 'STAROCC PASS')
sys.exit(1 if fails else 0)
