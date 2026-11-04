#!/usr/bin/env python3
"""scenes.py A.json [B.json]: flight speed by scene, and the planet's detail
by radius, from mscenes.mjs runs of the gate's run (two builds whose game
state is identical fly the same iterations).

An iteration counts when it is a flight iteration in the front view (one
TT100 to the next) and both runs put it in the same scene:
  station close: the station (slot 1) ahead, z below 16 x 256
  sun close:     the sun (slot 1) ahead, z below 1024 x 256
  planet close:  the planet ahead, z below 128 x 256 (mostly off the
                 screen or not drawn: few disc rows)
  big planet:    the planet ahead, z 128 x 256 to 512 x 256 (the big
                 discs)
  open space:    the planet at 512 x 256 or more, no station within
                 64 x 256, no other ships
  ships about:   other ships in the bubble
and the window "Lave": the first system's front-view flight iterations
(combat just after launch at Lave, a meridian planet: the beach ball's).

Then, per build, the planet's detail (PF_HOOK, the circle engine's calls in
game context): its calls and cycles per call by radius band and by scene,
split into the divides, the multiplies, the square roots, the rest and the
interrupts; and how often a call's inputs, or its records, are bitwise
those of the previous call (in the previous flight iteration): what exact
memoisation could save.
"""
import json, sys, collections

SCENES = ['open space', 'ships about', 'planet close', 'big planet', 'sun close', 'station close', 'other']
BANDS = [(6, 15), (16, 31), (32, 63), (64, 127), (128, 256)]


def scene(a):
    pz = a['p']['z']; st = a['f1'] == 2
    sz = a['s1']['z'] if st else 1 << 20
    sun = a['f1'] == 129
    if st and sz < 16 and a['s1']['zs'] == 0: return 'station close'
    if sun and a['s1']['z'] < 1024 and a['s1']['zs'] == 0: return 'sun close'
    if pz < 128 and a['p']['zs'] == 0: return 'planet close'
    if pz < 512 and a['p']['zs'] == 0: return 'big planet'
    if pz >= 512 and not (st and sz < 64) and a['ships'] == 0: return 'open space'
    if a['ships'] > 0: return 'ships about'
    return 'other'


def flight(rows):
    """{iteration: (scene, cycles, row)} for the front-view flight iterations"""
    out = {}
    for a, b in zip(rows, rows[1:]):
        if b['tt'] - a['tt'] != 1 or a['qq11'] != 0 or a['view'] != 0:
            continue
        out[a['i']] = (scene(a), (b['t'] - a['t']) * 2e6, a)
    return out


def lave(rows):
    out = {}
    for a, b in zip(rows, rows[1:]):
        if b['tt'] - a['tt'] == 1 and a['qq11'] == 0 and a['view'] == 0 and tuple(a.get('sys', ())) == (20, 173):
            out[a['i']] = (b['t'] - a['t']) * 2e6
    return out


def band(r):
    for lo, hi in BANDS:
        if lo <= r <= hi:
            return f"r {lo}-{hi}"
    return f"r {r}"


def detail(name, rows, fl):
    print(f"\n{name}: the planet's detail (PF_HOOK), cycles per call")
    hdr = f"{'':18s} {'calls':>6s} {'recs':>5s} {'all':>7s} {'div':>6s} {'mul':>6s} {'sqrt':>6s} {'rest':>6s} {'irq':>5s}"
    by = collections.defaultdict(list)
    allc = []
    for x in rows:
        for p in x['pf']:
            by[band(p['r'])].append(p); allc.append(p)
            if x['i'] in fl:
                by['scene: ' + fl[x['i']][0]].append(p)
    print(hdr)
    keys = [band(lo) for lo, _ in BANDS] + ['scene: ' + s for s in SCENES]
    for k in keys + ['all']:
        ps = allc if k == 'all' else by.get(k, [])
        if not ps: continue
        n = len(ps)
        f = lambda key: sum(p[key] for p in ps) / n
        rest = f('c') - f('div') - f('mul') - f('sqrt') - f('irq')
        print(f"{k:18s} {n:6d} {f('n'):5.2f} {f('c'):7.0f} {f('div'):6.0f} {f('mul'):6.0f} {f('sqrt'):6.0f} {rest:6.0f} {f('irq'):5.0f}")
    # memoisation: a call whose inputs (or records) are the previous call's
    prev = None; hi = ho = n = 0; savable = 0
    for x in rows:
        for p in x['pf']:
            if prev is not None:
                n += 1
                if p['h'] == prev['h']: hi += 1; savable += p['c']
                if p['o'] == prev['o']: ho += 1
            prev = p
    tot = sum(p['c'] for p in allc)
    if n:
        print(f"memoisation: of {n} calls after the first, inputs unchanged in {hi} ({100*hi/n:.2f}%), "
              f"records unchanged in {ho} ({100*ho/n:.2f}%); exact input memoisation could save at most "
              f"{savable:.0f} of {tot:.0f} cycles ({100*savable/max(tot,1):.2f}%)")
    nfl = len(fl)
    if nfl:
        print(f"per front-view flight iteration, by scene: PF_HOOK's calls and cycles, and its share of the iteration")
        per = collections.defaultdict(lambda: [0, 0, 0.0, 0.0])
        for x in rows:
            if x['i'] in fl:
                k, c, _ = fl[x['i']]
                for key in (k, 'all scenes'):
                    e = per[key]; e[0] += 1; e[1] += len(x['pf']); e[2] += sum(p['c'] for p in x['pf']); e[3] += c
        for k in SCENES + ['all scenes']:
            it, calls, c, tot = per[k]
            if it:
                print(f"{k:18s} {it:5d} it  {calls/it:4.2f} calls/it  {c/it:7.0f} cycles/it  {100*c/tot:5.1f}% of {tot/it:7.0f}")


def main():
    ra = json.load(open(sys.argv[1]))
    rb = json.load(open(sys.argv[2])) if len(sys.argv) > 2 else None
    fa = flight(ra)
    fb = flight(rb) if rb else None
    agg = collections.defaultdict(lambda: [0, 0.0, 0.0])
    for i, (k, c, _) in fa.items():
        if fb is None or (i in fb and fb[i][0] == k):
            agg[k][0] += 1; agg[k][1] += c; agg[k][2] += fb[i][1] if fb else 0
    print("flight speed by scene (front view):" + (" A against B" if rb else ""))
    tot = [0, 0.0, 0.0]
    for k in SCENES:
        n, ca, cb = agg[k]
        if not n: continue
        tot = [tot[0] + n, tot[1] + ca, tot[2] + cb]
        s = f"{k:14s} {n:5d} it  A {ca/n:8.0f} cycles/it {2e6*n/ca:6.2f} it/s"
        if rb: s += f"  B {cb/n:8.0f} cycles/it {2e6*n/cb:6.2f} it/s  B-A {(cb-ca)/n:+7.0f}  A/B {ca/cb:5.3f}"
        print(s)
    n, ca, cb = tot
    s = f"{'all scenes':14s} {n:5d} it  A {ca/n:8.0f} cycles/it {2e6*n/ca:6.2f} it/s"
    if rb: s += f"  B {cb/n:8.0f} cycles/it {2e6*n/cb:6.2f} it/s  B-A {(cb-ca)/n:+7.0f}  A/B {ca/cb:5.3f}"
    print(s)
    la = lave(ra); lb = lave(rb) if rb else None
    ks = [i for i in la if lb is None or i in lb]
    if ks:
        ca = sum(la[i] for i in ks); s = f"{'window: Lave':14s} {len(ks):5d} it  A {ca/len(ks):8.0f} cycles/it {2e6*len(ks)/ca:6.2f} it/s"
        if lb:
            cb = sum(lb[i] for i in ks); s += f"  B {cb/len(ks):8.0f} cycles/it {2e6*len(ks)/cb:6.2f} it/s  B-A {(cb-ca)/len(ks):+7.0f}  A/B {ca/cb:5.3f}"
        print(s)
    detail("A", ra, fa)
    if rb: detail("B", rb, fb)


if __name__ == '__main__':
    main()
