#!/usr/bin/env python3
"""6-harness/discmem/cmp.py A B: compare two 6-harness/discmem/bench.sh
outputs (A the reference build, B the candidate): pixels (every frame the
scenes dump, byte for byte; run1's and the gate's frame hashes through
fbcmp.mjs and mfbcmp.mjs --cmp) and cycles (each scene's mean per routine,
run1's windows)."""
import json, os, subprocess, sys, glob, re

A, B = sys.argv[1], sys.argv[2]
R = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
bad = 0


def frames_equal(da, db):
    fa = sorted(glob.glob(os.path.join(da, 'frame-*.bin')))
    same = diff = gap = 0
    first = None
    for f in fa:
        g = os.path.join(db, os.path.basename(f))
        if not os.path.exists(g):
            gap += 1                # (a frame one side did not dump: timing)
            continue
        if open(f, 'rb').read() == open(g, 'rb').read():
            same += 1
        else:
            diff += 1
            first = first or os.path.basename(f)
    return same, diff, first, gap


def mean(xs):
    return sum(xs) / len(xs) if xs else 0


if os.path.exists(os.path.join(A, 'run1-fb.json')) and os.path.exists(os.path.join(B, 'run1-fb.json')):
    r = subprocess.run(['node', os.path.join(R, '6-harness/solidspan/fbcmp.mjs'), os.path.join(A, 'run1-fb.json'),
                        os.path.join(B, 'run1-fb.json')], capture_output=True, text=True)
    print('run1 pixels:', r.stdout.strip())
    bad += r.returncode != 0
    sa = open(os.path.join(A, 'run1-speed.txt')).read()
    sb = open(os.path.join(B, 'run1-speed.txt')).read()
    for la, lb in zip(re.findall(r'iterations (\S+): (\d+) cycles', sa), re.findall(r'iterations (\S+): (\d+) cycles', sb)):
        ca, cb = int(la[1]), int(lb[1])
        print('run1 %-10s %7d -> %7d cycles an iteration (%+d, %+.2f%%)' % (la[0], ca, cb, cb - ca, 100.0 * (cb - ca) / ca))
if os.path.exists(os.path.join(A, 'gate-fb.json')) and os.path.exists(os.path.join(B, 'gate-fb.json')):
    r = subprocess.run(['node', os.path.join(R, '6-harness/mfbcmp.mjs'), '--cmp', os.path.join(A, 'gate-fb.json'),
                        os.path.join(B, 'gate-fb.json')], capture_output=True, text=True)
    print('gate pixels:', r.stdout.strip())
    bad += r.returncode != 0
for d in sorted(glob.glob(os.path.join(A, 'pl-*'))) + [os.path.join(A, n) for n in ('sunnear', 'sunedge', 'sungrow', 'sunswap', 'sunsmall')]:
    if not os.path.isdir(d):
        continue
    n = os.path.basename(d)
    e = os.path.join(B, n)
    if not os.path.isdir(e):
        continue
    same, diff, first, gap = frames_equal(d, e)
    bad += diff > 0
    ja = json.load(open(os.path.join(d, 'frames.json')))['frames']
    jb = json.load(open(os.path.join(e, 'frames.json')))['frames']
    if not n.startswith('sun'):     # (mplanet's first frame counts all before it)
        ja, jb = ja[1:], jb[1:]
    if n.startswith('sun'):
        keys = ['discs', 'disc2', 'frame']
        get = lambda f, k: f.get(k, 0)
    else:
        keys = [k for k in ['T_DISCROWS', 'T_CAPS', 'f_moon', 'T_MCAPS', 'F_FRAME'] if k in ja[0]['cyc']]
        get = lambda f, k: f['cyc'].get(k, 0)
    # frames by their key (k, or the iteration), both sides, every routine
    # timed on both (a hook the emulator skipped leaves one out: not compared)
    kf = 'k' if n.startswith('sun') else 'iter'
    has = lambda f: all((k in f) if n.startswith('sun') else (k in f['cyc']) for k in keys)
    fa = {f[kf]: f for f in ja if has(f)}
    fb = {f[kf]: f for f in jb if has(f)}
    both = sorted(set(fa) & set(fb))
    parts = []
    for k in keys:
        ma, mb = mean([get(fa[i], k) for i in both]), mean([get(fb[i], k) for i in both])
        parts.append('%s %.0f -> %.0f (%+.0f)' % (k, ma, mb, mb - ma))
    print('%-13s pixels %d same, %d differ%s%s; %s' % (n, same, diff, (' (first ' + first + ')') if first else '',
          (', %d not dumped by one side' % gap) if gap else '', '; '.join(parts)))
print('PIXELS', 'IDENTICAL' if not bad else 'DIFFER')
