#!/usr/bin/env python3
"""fbdiff.py A.bin B.bin [--png DIR] [--scenes SCENES.json]: two builds'
frames (6-harness/mfbdump.mjs dumps of the gate's run) compared pixel by
pixel: how many frames differ, the rows and pixels per differing frame
(mean, and by the planet's radius), the worst frame, and with --png the
worst frames' crops before and after (and the differing pixels in white),
4x. With --scenes (an mscenes.mjs run of the same build) the differing
frames are also counted by scene (scenes.py's)."""
import sys, json, os, collections
import numpy as np

PAL = np.array([(0, 0, 0), (0, 255, 255), (255, 0, 255), (255, 255, 0)], np.uint8)     # K, C, M, Y


def load(path):
    meta = json.load(open(path + '.json'))
    raw = np.fromfile(path, np.uint8).reshape(len(meta), 24, 64, 8)    # char row, column, line
    return meta, raw


def pixels(buf):
    """a buffer (24, 64, 8) as 192 x 256 colours 0..3 (MODE 1)"""
    b = buf.transpose(0, 2, 1).reshape(192, 64)                     # y, byte
    out = np.empty((192, 256), np.uint8)
    for p in range(4):                                              # pixel 3 - p of each byte
        out[:, (3 - p)::4] = (((b >> (p + 4)) & 1) << 1) | ((b >> p) & 1)
    return out


def band(r):
    if r is None: return 'no planet'
    for lo, hi in ((6, 15), (16, 31), (32, 63), (64, 127), (128, 255)):
        if lo <= r <= hi: return f"r {lo}-{hi}"
    return f"r {r}"


def crop_png(pa, pb, box, path):
    from PIL import Image
    y0, y1, x0, x1 = box
    a = PAL[pa[y0:y1, x0:x1]]
    b = PAL[pb[y0:y1, x0:x1]]
    d = np.where((pa[y0:y1, x0:x1] != pb[y0:y1, x0:x1])[..., None], 255, 40).astype(np.uint8).repeat(3, axis=2)
    gap = np.full((y1 - y0, 2, 3), 80, np.uint8)
    im = np.concatenate([a, gap, b, gap, d], axis=1)
    Image.fromarray(im).resize((im.shape[1] * 4, im.shape[0] * 4), Image.NEAREST).save(path)


def main():
    args = sys.argv[1:]
    png = scenes = None
    if '--png' in args:
        k = args.index('--png'); png = args[k + 1]; del args[k:k + 2]
    if '--scenes' in args:
        k = args.index('--scenes'); scenes = args[k + 1]; del args[k:k + 2]
    ma, ra = load(args[0])
    mb, rb = load(args[1])
    ib = {m['f']: k for k, m in enumerate(mb)}
    sc = {}
    if scenes:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import scenes as S
        for i, (k, c, row) in S.flight(json.load(open(scenes))).items():
            sc[i] = k
    n = 0
    diffs = []
    for k, m in enumerate(ma):
        j = ib.get(m['f'])
        if j is None:
            continue
        n += 1
        if np.array_equal(ra[k], rb[j]):
            continue
        pa, pb = pixels(ra[k]), pixels(rb[j])
        d = pa != pb
        npx = int(d.sum())
        if not npx:
            continue
        ys = np.nonzero(d.any(axis=1))[0]
        xs = np.nonzero(d.any(axis=0))[0]
        r = m['planet'][2] if m.get('planet') else None
        diffs.append(dict(f=m['f'], k=k, j=j, px=npx, rows=len(ys), box=(int(ys[0]), int(ys[-1]) + 1, int(xs[0]), int(xs[-1]) + 1),
                          r=r, planet=m.get('planet'), scene=sc.get(int(m['f'].split('.')[0]), 'not front-view flight')))
    print(f"{n} frames compared, {len(diffs)} differ ({100 * len(diffs) / max(n, 1):.2f}%)")
    if not diffs:
        return
    px = [x['px'] for x in diffs]; rw = [x['rows'] for x in diffs]
    print(f"per differing frame: {np.mean(rw):.1f} rows, {np.mean(px):.1f} pixels (median {int(np.median(px))}, 90th percentile {int(np.percentile(px, 90))})")
    by = collections.defaultdict(list)
    for x in diffs:
        by[band(x['r'])].append(x)
    for k in sorted(by, key=lambda s: (len(s), s)):
        v = by[k]
        print(f"  {k:10s} {len(v):5d} frames, {np.mean([x['rows'] for x in v]):5.1f} rows, {np.mean([x['px'] for x in v]):6.1f} pixels per frame, worst {max(x['px'] for x in v)}")
    if sc:
        bys = collections.Counter(x['scene'] for x in diffs)
        print('  by scene: ' + ', '.join(f"{k} {v}" for k, v in bys.most_common()))
    worst = sorted(diffs, key=lambda x: -x['px'])
    w = worst[0]
    print(f"worst: frame {w['f']}, {w['px']} pixels in {w['rows']} rows, box y {w['box'][0]}-{w['box'][1] - 1} x {w['box'][2]}-{w['box'][3] - 1}, planet {w['planet']}")
    if png:
        os.makedirs(png, exist_ok=True)
        for x in worst[:3]:
            pa, pb = pixels(ra[x['k']]), pixels(rb[x['j']])
            if x['planet']:
                cx, cy, r = x['planet']
                box = (max(0, cy - r - 4), min(192, cy + r + 5), max(0, cx - r - 4), min(256, cx + r + 5))
                if box[0] >= box[1] or box[2] >= box[3]:
                    box = x['box']
            else:
                box = x['box']
            box = (max(0, min(box[0], x['box'][0]) - 2), min(192, max(box[1], x['box'][1]) + 2),
                   max(0, min(box[2], x['box'][2]) - 2), min(256, max(box[3], x['box'][3]) + 2))
            p = os.path.join(png, f"frame-{x['f']}.png")
            crop_png(pa, pb, box, p)
            print(f"  {p}: before | after | differing pixels ({x['px']} pixels, planet {x['planet']})")


if __name__ == '__main__':
    main()
