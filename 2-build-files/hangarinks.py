#!/usr/bin/env python3
"""hangarinks -- which ships blend into the hangar's tan, from the rendered pixels.

    python3 2-build-files/hangarinks.py configs SEED... > cfg.txt
    node 6-harness/mhangar.mjs DIR $(cat cfg.txt)
    python3 2-build-files/hangarinks.py measure DIR

`configs` writes 6-harness/mhangar.mjs configurations: tNN_kk for each type NN
(1-31 but the Coriolis) and each RAND seed kk (seeds for which HALL chooses a
group of HATB, not a solo ship), with every group's first slot poked to type
NN and the other slots emptied, so the hangar holds that one ship at one of
the four groups' places; and t00_00, the empty hangar.

`measure` compares each screenshot with the empty hangar, in BBC pixels (one
sample in two each way of the 896x600 screenshot, inside the space view), and
prints per type, over all its placements:
  * the inks of the ship's pixels (those that differ from the empty hangar):
    the wall's tan is two yellow, a magenta and a black pixel in each 2x2
    cell, the floor's two yellow, a magenta and a cyan, so a ship dithered
    from yellow, magenta and black alone reads as the wall's texture;
  * dE: the CIELAB colour difference from the empty hangar at the same place,
    both blurred over 4x4 pixels (the dithers merged, as seen from a
    distance), median over the ship's silhouette (each row from its first to
    its last changed pixel, eroded by two pixels).
"""
import sys, os, glob, random, collections
import numpy as np
from PIL import Image

NAMES = {1: 'missile', 3: 'escape pod', 4: 'alloy plate', 5: 'cargo canister', 6: 'boulder',
         7: 'asteroid', 8: 'splinter', 9: 'shuttle', 10: 'transporter', 11: 'Cobra Mk III',
         12: 'Python', 13: 'Boa', 14: 'Anaconda', 15: 'rock hermit', 16: 'Viper', 17: 'Sidewinder',
         18: 'Mamba', 19: 'Krait', 20: 'Adder', 21: 'Gecko', 22: 'Cobra Mk I', 23: 'Worm',
         24: 'Cobra Mk III (pirate)', 25: 'Asp Mk II', 26: 'Python (pirate)', 27: 'Fer-de-Lance',
         28: 'Moray', 29: 'Thargoid', 30: 'Thargon', 31: 'Constrictor'}
INKS = np.array([[0, 0, 0], [0, 255, 255], [255, 0, 255], [255, 255, 0]])   # K C M Y


def configs(seeds):
    first, other = (0, 9, 18, 27), (3, 6, 12, 15, 21, 24, 30, 33)
    for t in [0] + sorted(NAMES):
        for k, sd in enumerate(seeds if t else seeds[:1]):
            p = ["HATB+%d=%d" % (s, t) for s in first] + ["HATB+%d=0" % s for s in other]
            print("t%02d_%02d:%s:%s" % (t, k, sd, ",".join(p)))


def lab(rgb):
    c = rgb / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.9505, 1.0, 1.089])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def load(path):
    return np.asarray(Image.open(path).convert('RGB').crop((185, 70, 695, 452))).astype(float)[::2, ::2]


def blur(a, k=2):
    p = np.pad(a, ((k, k), (k, k), (0, 0)), mode='edge')
    c = np.pad(p.cumsum(0).cumsum(1), ((1, 0), (1, 0), (0, 0)))
    h, w = a.shape[:2]
    return (c[2 * k:2 * k + h, 2 * k:2 * k + w] - c[:h, 2 * k:2 * k + w] - c[2 * k:2 * k + h, :w] + c[:h, :w]) / (4 * k * k)


def measure(d):
    bg = load(d + '/t00_00.png')
    bgl = lab(blur(bg))
    ink = collections.defaultdict(lambda: np.zeros(4))
    de = collections.defaultdict(list)
    for f in sorted(glob.glob(d + '/t*_*.png')):
        t = int(os.path.basename(f)[1:3])
        if t == 0:
            continue
        im = load(f)
        ch = np.abs(im - bg).sum(-1) > 0
        if ch.sum() < 20:
            continue
        idx = np.argmin(((im[..., None, :] - INKS) ** 2).sum(-1), -1)
        ink[t] += np.bincount(idx[ch], minlength=4)
        sil = np.zeros(ch.shape, bool)
        for y in range(ch.shape[0]):
            xs = np.nonzero(ch[y])[0]
            if len(xs):
                sil[y, xs.min():xs.max() + 1] = True
        e = sil.copy()
        for k in (1, 2):
            e[k:] &= sil[:-k]; e[:-k] &= sil[k:]; e[:, k:] &= sil[:, :-k]; e[:, :-k] &= sil[:, k:]
        if e.sum():
            de[t].append(np.sqrt(((lab(blur(im)) - bgl) ** 2).sum(-1))[e])
    print("%-24s %6s %6s %6s %6s %6s" % ("type", "K", "C", "M", "Y", "dE"))
    for t in sorted(ink, key=lambda t: -ink[t][3] / ink[t].sum()):
        s = ink[t] / ink[t].sum()
        m = np.median(np.concatenate(de[t])) if de[t] else float('nan')
        print("%-24s %5.0f%% %5.0f%% %5.0f%% %5.0f%% %6.1f" % ("%d %s" % (t, NAMES[t]), *(100 * s), m))


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == 'configs':
        configs(sys.argv[2:])
    elif len(sys.argv) == 3 and sys.argv[1] == 'measure':
        measure(sys.argv[2])
    else:
        sys.exit(__doc__)
