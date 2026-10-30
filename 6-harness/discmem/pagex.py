#!/usr/bin/env python3
"""6-harness/discmem/pagex.py COMPILE.TXT [FROM_LABEL TO_LABEL]: the branches
whose taken path crosses a page (one cycle more) in a stretch of a build's
listing (default: bank 5's disc window, .R_DISCROWS to .B5LO_END), by the
label above each; compare two builds' outputs to see which loops a layout
change moved across a page."""
import re, sys
f = sys.argv[1]
a, b = (sys.argv[2], sys.argv[3]) if len(sys.argv) > 3 else ('R_DISCROWS', 'B5LO_END')
on, lab, out = False, None, []
br = re.compile(r'^\s+([0-9A-F]{4})\s+([0-9A-F]{2}) ([0-9A-F]{2})\s+(B(?:CC|CS|EQ|NE|MI|PL|VC|VS|RA)) &([0-9A-F]{4})')
for l in open(f, encoding='latin-1'):
    if l.startswith('.' + a) and not on:
        on = True
    if not on:
        continue
    if l.startswith('.' + b):
        break
    if l.startswith('.'):
        lab = l[1:].split()[0]
        continue
    m = br.match(l)
    if m:
        pc, tgt = int(m.group(1), 16), int(m.group(5), 16)
        if (pc + 2) >> 8 != tgt >> 8:
            out.append('%s %04X %s &%04X' % (lab, pc, m.group(4), tgt))
print('\n'.join(out))
