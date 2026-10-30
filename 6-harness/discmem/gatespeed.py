#!/usr/bin/env python3
"""6-harness/discmem/gatespeed.py A/compare.log B/compare.log: the gate's
speed table (6-harness/mcompare.mjs's windows of 200 flight iterations) of two
builds side by side: the candidate's it/s in each, the change, and the
windows that got slower."""
import re, sys
def load(f):
    w = {}
    for l in open(f):
        m = re.match(r'\s+(\d+)-\s*(\d+)\s+(\d+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)', l)
        if m:
            w[(int(m.group(1)), int(m.group(2)))] = float(m.group(5))
        m = re.match(r'\s+all\s+(\d+)\s+([\d.]+)\s+([\d.]+)', l)
        if m:
            w['all'] = float(m.group(3))
    return w
a, b = load(sys.argv[1]), load(sys.argv[2])
slower = 0
for k in [k for k in a if k != 'all'] + ['all']:
    if k not in b:
        continue
    d = b[k] - a[k]
    slower += d < 0
    print('%-12s %6.2f -> %6.2f  %+6.2f%%%s' % ('%d-%d' % k if k != 'all' else 'all', a[k], b[k], 100 * d / a[k], '  SLOWER' if d < 0 else ''))
print('windows slower:', slower)
