#!/usr/bin/env python3
"""sourcediff.py: classify every line of
1-source-files/main-sources/elite-source.asm that differs from the original's
source, as it is in this repository's history at b892ec6 (Mark Moxon's
elite-source-code-bbc-master, the commit the port starts from), into the
kinds of change the house rules allow and the real edits
(docs/source-diff.md).

Usage, from the repository's root:

    python3 2-build-files/sourcediff.py [--base REV] [--rev REV] [--worktree DIR]
                                        [--routines] [--themes] [--lines FILE]

    --base REV      the pristine commit (default b892ec6)
    --rev REV       compare that commit's file instead of the working tree's
    --worktree DIR  the repo to read (default: the one this script is in)
    --routines      the real edits' line counts by routine (the enclosing
                    block's Name:)
    --themes        the same, by the groups of docs/source-diff.md
    --lines FILE    write every changed line with its kind and routine

Method: git diff --diff-algorithm=histogram -U0 BASE [REV] -- the file. Each
hunk (with no context) is a change group, classified line by line. A line's
statement is its text before any comment (a backslash outside quotes),
whitespace-normalised:

  * a statement on both sides of a group is kept, only its comment changed;
  * a group that removes no statement and adds at most four (calls, jumps,
    immediate or absolute loads, stores, a compare, a skip), one of them
    naming port code or a port variable, is a hook;
  * a group that swaps one JSR or JMP for another (and maybe a NOP) is a
    redirected call;
  * a block whose header Name: the original lacks is a port routine written
    into the file;
  * an added comment in a run of comment that mentions Port is a Port: note;
  * blank and other comment lines go with their group: real when it changes
    statements, allowed when it does not.

Kinds starting "A" are allowed by the house rules, "B" are real edits.
"""
import os, re, sys, subprocess, collections

def opt(name, default=None):
    if name in sys.argv:
        return sys.argv[sys.argv.index(name) + 1]
    return default
WT = opt('--worktree', os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))
BASE = opt('--base', 'b892ec6')
REV = opt('--rev')
F = '1-source-files/main-sources/elite-source.asm'
def git(*a):
    return subprocess.run(['git', '-C', WT] + list(a), capture_output=True,
                          text=True, check=True).stdout
orig = git('show', BASE + ':' + F).split('\n')
if REV:
    cur = git('show', REV + ':' + F).split('\n')
else:
    with open(os.path.join(WT, F), encoding='latin-1') as f:
        cur = f.read().split('\n')
diff = git('diff', '--diff-algorithm=histogram', '-U0', BASE,
           *([REV] if REV else []), '--', F).split('\n')

def names(lines):
    out, c = [], '(configuration)'
    for l in lines:
        m = re.match(r'\\\s+Name: (.*)', l)
        if m: c = m.group(1).strip()
        out.append(c)
    return out
oname, cname = names(orig), names(cur)
orig_names = set(oname)

def stmt(l):
    s, q = [], False
    for ch in l:
        if ch == '"': q = not q
        if ch == '\\' and not q: break
        s.append(ch)
    return ' '.join(''.join(s).split())

# symbols the original defines (labels and assignments)
orig_syms = set()
for l in orig:
    s = stmt(l)
    m = re.match(r'^\.(\w+)', s) or re.match(r'^(\w+%?)\s*=', s)
    if m: orig_syms.add(m.group(1))
# labels the port defines inside the original's own blocks (local edits)
local_syms = set()
for i, l in enumerate(cur):
    m = re.match(r'^\.(\w+)', stmt(l))
    if m and m.group(1) not in orig_syms and cname[i] in orig_names:
        local_syms.add(m.group(1))
def port_ref(s):
    """True if the statement names a symbol that is port code or data: not
    defined by the original, nor a label the port added inside an original
    routine."""
    s = re.sub(r'^\.\w+\s*', '', s)
    m = re.match(r'^[A-Z]{3}\s+(.*)$', s)
    if not m: return False
    ops = re.sub(r'&[0-9A-Fa-f]+|%[01]+|\b\d+\b', ' ', m.group(1))
    for w in re.findall(r'[A-Za-z_][\w%]*', ops):
        if w in ('A', 'X', 'Y', 'LO', 'HI'): continue
        if w not in orig_syms and w not in local_syms: return True
    return False

# A block written into the file by the port: its header Name is not one of
# the original's (DIALS replaces DIALS (Part 1 of 4) .. (Part 4 of 4))
REWRITE_OF = {'DIALS': 'DIALS (Parts 1-4)'}
new_block = [n not in orig_names for n in cname]

groups = []
for l in diff:
    m = re.match(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', l)
    if m:
        a, b, c, d = int(m[1]), int(m[2] or 1), int(m[3]), int(m[4] or 1)
        g = {'rem': [], 'add': []}; groups.append(g)
        oi, ci = (a - 1 if b else a), (c - 1 if d else c); continue
    if not groups: continue
    if l.startswith('-') and not l.startswith('---'):
        groups[-1]['rem'].append(oi); oi += 1
    elif l.startswith('+') and not l.startswith('+++'):
        groups[-1]['add'].append(ci); ci += 1

COND = re.compile(r'^(IF|ELIF|ELSE|ENDIF)\b')
cats = collections.Counter()
by_routine = collections.defaultdict(collections.Counter)
lines_out = []

kinds = collections.Counter()
def put(side, cat, name, text):
    cats[(side, cat)] += 1
    kinds[(side, cat[0], 'statement' if stmt(text) else
           'blank' if text.strip() == '' else 'comment')] += 1
    if cat[0] == 'B': by_routine[name][side] += 1
    lines_out.append('%s %-34s %-30s %s' % (side, cat, name, text))

def port_comment_runs(idx):
    """For added comment-only lines: does the run of comment text it is in
    (consecutive lines with a comment) mention Port?"""
    res, run = {}, []
    def flush():
        hit = any('Port' in cur[j] for j in run)
        for j in run: res[j] = hit
    prev = None
    for i in idx:
        has_c = '\\' in cur[i] and cur[i].strip() != '\\'
        if run and (i != prev + 1 or not has_c):
            flush(); run = []
        if has_c: run.append(i)
        prev = i
    if run: flush()
    return res

for g in groups:
    rs = [stmt(orig[i]) for i in g['rem']]
    as_ = [stmt(cur[i]) for i in g['add']]
    common = collections.Counter(s for s in rs if s) & collections.Counter(s for s in as_ if s)
    r_changed = collections.Counter(s for s in rs if s) - common
    a_changed = collections.Counter(s for s in as_ if s and not COND.match(s)) - common
    n_r, n_a = sum(r_changed.values()), sum(a_changed.values())
    a_list = list(a_changed.elements())
    # kinds of group
    pure_insert = n_r == 0 and n_a > 0
    # a hook: a pure insertion of at most four statements that calls or
    # jumps to port code (or sets a port variable or bank), with only
    # minimal glue (immediate loads, stores, a compare and a skip)
    GLUE = re.compile(r'^(\.\w+|(LDA|LDX) #\S+|(STA|STX|STZ) \S+|CMP #\S+|'
                      r'BNE P%\+\d|BCS \w+|(JSR|JMP) \w+)$')
    hook = (pure_insert and n_a <= 4 and all(GLUE.match(s) for s in a_list)
            and any(port_ref(s) for s in a_list if not s.startswith('.'))
            and not any(new_block[i] for i in g['add']))
    redirect = (n_r == 1 and 1 <= n_a <= 2 and
                re.match(r'^(JSR|JMP) ', list(r_changed)[0]) and
                re.match(r'^(JSR|JMP) ', a_list[0]) and
                list(r_changed)[0].split()[0] == a_list[0].split()[0] and
                all(s == 'NOP' for s in a_list[1:]))
    edited = (n_r > 0 or n_a > 0) and not hook and not redirect
    pc = port_comment_runs(g['add'])
    keep_r, keep_a = dict(common), dict(common)
    for i in g['rem']:
        l, s, n = orig[i], stmt(orig[i]), oname[i]
        if l.strip() == '':
            put('-', 'B blank, in an edited group' if edited else 'A blank', n, l)
        elif s == '':
            if l.lstrip().startswith('\\SAVE') or l.lstrip().startswith('\\ORG'):
                put('-', 'A comment reworded', n, l)
            elif n_r: put('-', 'B comment removed with code', n, l)
            else: put('-', 'A comment reworded', n, l)
        elif keep_r.get(s, 0) > 0:
            keep_r[s] -= 1; put('-', 'A statement kept, comment changed', n, l)
        elif redirect: put('-', 'B call redirected', n, l)
        elif COND.match(s): put('-', 'B conditional removed', n, l)
        else: put('-', 'B statement removed or changed', n, l)
    for i in g['add']:
        l, s, n = cur[i], stmt(cur[i]), cname[i]
        if new_block[i]:
            put('+', 'B port routine in the file', REWRITE_OF.get(n, n), l)
        elif l.strip() == '':
            put('+', 'B blank, in an edited group' if edited else 'A blank', n, l)
        elif re.match(r'\\\s+Area: ', l): put('+', 'A Area: tag', n, l)
        elif s == '':
            put('+', 'A Port: note' if pc.get(i) else
                'B comment on new code' if edited else 'A comment reworded', n, l)
        elif keep_a.get(s, 0) > 0:
            keep_a[s] -= 1; put('+', 'A statement kept, comment changed', n, l)
        elif COND.match(s): put('+', 'A conditional (IF/ENDIF)', n, l)
        elif hook: put('+', 'A hook', n, l)
        elif redirect: put('+', 'B call redirected', n, l)
        elif pure_insert: put('+', 'B statement inserted', n, l)
        else: put('+', 'B statement added or changed', n, l)

tot = collections.Counter()
for side in '-+':
    print('removed/changed original lines' if side == '-' else 'added lines')
    for (s, c), v in sorted(cats.items()):
        if s == side: print(f'  {c:36s} {v:6d}'); tot[s] += v
    a = sum(v for (s, c), v in cats.items() if s == side and c[0] == 'A')
    b = sum(v for (s, c), v in cats.items() if s == side and c[0] == 'B')
    print(f'  {"total":36s} {tot[side]:6d}   allowed {a}, real {b}')
print('\nby kind of line (side, allowed/real, kind):')
for k, v in sorted(kinds.items()): print(' ', k, v)
if '--routines' in sys.argv:
    print('\nreal edits by routine: removed/changed, added')
    for n, c in sorted(by_routine.items(), key=lambda kv: -(kv[1]['-'] + kv[1]['+'])):
        print(f'{c["-"]:5d} {c["+"]:5d}  {n}')
if '--lines' in sys.argv:
    open(opt('--lines'), 'w').write('\n'.join(lines_out) + '\n')

# Themes for the report's table (by the enclosing routine's Name:)
THEMES = [
 ('1 Memory map and build', ['(configuration)', 'K%', 'WP', 'FONT%', 'log', 'F%', 'COLD']),
 ('2 One screen, split timer, interrupts', ['IRQ1', 'VSCAN', 'T1SYNC', 'TVT1', 'TVT3',
   'DOVDU19', 'SOFLUSH', 'NOISE', 'SETINTS']),
 ('3 ACCCON by TSB/TRB', ['setzp', 'getzp', 'LOIN']),
 ('4 CMYK dashboard', ['SCAN', 'DOT', 'ddot', 'CPIXK', 'CTWOS', 'TWOS2', 'ECBLB2', 'ECBLB',
   'SPBLB', 'SPBT', 'ECBT', 'MSBAR', 'DIALS (Parts 1-4)', 'DIALS (Part 1 of 4)',
   'DIALS (Part 2 of 4)', 'DIALS (Part 3 of 4)', 'DIALS (Part 4 of 4)', 'PZW', 'PZW2',
   'DILX', 'DIL2', 'DILI', 'DSEG', 'ADDK']),
 ('5 Renderer: record instead of draw', ['HLOIN', 'PIXEL2', 'PIXEL', 'pxpat', 'pxpatd',
   'CHPR', 'TTX66', 'CLYNS', 'BOMBOFF', 'LASLI', 'SUN (Part 1 of 4)', 'CIRCLE', 'WPLS2',
   'SIGHT', 'DOEXP', 'HFS2', 'FLIP', 'nWq', 'STARS2', 'STARS6',
   'Main game loop (Part 2 of 6)', 'DEATH', 'WARP', 'HALL', 'HAS1', 'HANGER', 'HAS2',
   'HAL3', 'HAS3', 'DVID4K', 'HANGFLAG', 'ESCAPE', 'TITLE', 'BRIEF', 'PAUSE', 'PAS1',
   'LL9F', 'LL9B', 'SHPPT', 'LL9 (Part 1 of 12)', 'LL9 (Part 5 of 12)',
   'LL9 (Part 9 of 12)', 'LL9 (Part 10 of 12)', 'LL9 (Part 11 of 12)',
   'LL9 (Part 12 of 12)', 'LSPUT', 'SPLV', 'S_SHIP', 'SHAND', 'ZP', 'cls']),
 ('6 Speed rewrites', ['MULT3', 'MU5', 'MLS1', 'SQUA2', 'MLU1', 'MULTU', 'MU11', 'FMLTU',
   'MLTU2', 'MULT1', 'MAD', 'ADD', 'TAS3', 'TIS1', 'TIS2', 'DVID4', 'DVL9a', 'DVID3B2',
   'LL5', 'LL38', 'LL51', 'LL51L', 'LL62', 'LL145 (Part 1 of 4)', 'LL9 (Part 6 of 12)',
   'LL9 (Part 7 of 12)', 'LL9 (Part 8 of 12)', 'MVS4', 'MVS5', 'MVT3', 'STARS1', 'BLINE',
   'PLS22', 'PLL4F', 'pl4pat', 'Main flight loop (Part 4 of 16)',
   'Main flight loop (Part 6 of 16)', 'Main flight loop (Part 7 of 16)', 'SPIN', 'MALC',
   'MALW', 'ex', 'QQ18IX', 'TT43', 'PIX1', 'FILLKL', 'orange']),
 ('7 Passes and banks', ['JMTB', 'NEWBRK', 'YESNO', 'ANGRY', 'QQ23']),
 ('8 Disc commands', ['DOSCLI', 'GTDIR', 'CATS', 'DELT', 'wfile', 'rfile', 'savosc',
   'lodosc']),
 ('9 Unused code and tables removed', ['LOINQ (Part 1 of 7)', 'S%', 'DEEOR', 'DEEORS',
   'NUMBOR', 'THERE', 'TT214', 'DVLOIN', 'INCYC', 'SWAPPZERO', 'backtonormal', 'CLDELAY',
   'OTHERFILEPR', 'yetanotherrts', 'NMIpissoff', 'MUT2', 'MUT3', 'LL28', 'beamcol',
   'sightcol', 'SCTBX1', 'SCTBX2', 'wtable', 'alogh', 'ECMOF', 'SFRMIS', 'hyp1', 'TT18']),
]
if '--themes' in sys.argv:
    seen = set()
    for t, rs in THEMES:
        r = sum(by_routine[n]['-'] for n in rs); a = sum(by_routine[n]['+'] for n in rs)
        print(f'\n{t}: {r} removed/changed, {a} added')
        for n in sorted(rs, key=lambda n: -(by_routine[n]['-'] + by_routine[n]['+'])):
            seen.add(n)
            if by_routine[n]['-'] + by_routine[n]['+']:
                print(f'   {by_routine[n]["-"]:5d} {by_routine[n]["+"]:5d}  {n}')
    left = [n for n in by_routine if n not in seen]
    print('\nunassigned:', left)
