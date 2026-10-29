#!/usr/bin/env python3
"""6-harness/discmem/perframe.py A B [scene...]: per-frame cycles of the sun
scenes (bench.sh's sunnear, sunedge, ...) of two builds, frame by frame (by k):
the frames where B's whole frame is slower than A's, and by how much."""
import json, os, sys
A, B = sys.argv[1], sys.argv[2]
scenes = sys.argv[3:] or ['sunnear', 'sunedge', 'sungrow', 'sunswap', 'sunsmall']
for n in scenes:
    try:
        fa = {f['k']: f for f in json.load(open(os.path.join(A, n, 'frames.json')))['frames'] if 'discs' in f and 'disc2' in f}
        fb = {f['k']: f for f in json.load(open(os.path.join(B, n, 'frames.json')))['frames'] if 'discs' in f and 'disc2' in f}
    except FileNotFoundError:
        continue
    ks = sorted(set(fa) & set(fb))
    d = [(fb[k]['frame'] - fa[k]['frame'], k) for k in ks]
    dd = [(fb[k]['discs'] + fb[k]['disc2'] - fa[k]['discs'] - fa[k]['disc2'], k) for k in ks]
    slow = [x for x in d if x[0] > 0]
    slowd = [x for x in dd if x[0] > 0]
    print('%-9s %3d frames: whole frame slower in %d (worst %+d at k=%s), discs+disc2 slower in %d (worst %+d), mean %+.0f' % (
        n, len(ks), len(slow), max(d)[0], max(d)[1], len(slowd), max(dd)[0], sum(x for x, _ in d) / len(d)))
