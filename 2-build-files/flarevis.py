"""flarevis.py frames_dir out.png iter [iter ...] [--label]: the dumped back
buffers (6-harness/mflarevis.mjs) as PNG, 256x192 doubled, with the probes drawn and the
probes-in-sight count; several iterations side by side."""
import sys, json, os
from PIL import Image, ImageDraw
d, out = sys.argv[1], sys.argv[2]
iters = [int(x) for x in sys.argv[3:] if not x.startswith('--')]
meta = {f['iter']: f for f in json.load(open(os.path.join(d, 'frames.json')))['frames']}
def pal_of(f):
    # MODE 1 logical colours 0..3 are ULA entries 0, 2, 8, 10 (ABGR words)
    p = []
    for idx in (0, 2, 8, 10):
        v = f['pal'][idx] & 0xffffffff
        p.append((v & 255, (v >> 8) & 255, (v >> 16) & 255))
    return p
def img(it):
    f = meta[it]
    buf = open(os.path.join(d, 'frame-%06d.bin' % it), 'rb').read()
    pal = pal_of(f)
    if len(set(pal)) < 3:
        pal = [(0, 0, 0), (255, 0, 0), (0, 255, 255), (255, 255, 0)]
    im = Image.new('RGB', (256, 192))
    px = im.load()
    for y in range(192):
        for x in range(256):
            b = buf[(y >> 3) * 0x200 + (x >> 2) * 8 + (y & 7)]
            p = 3 - (x & 3)
            c = ((b >> (p + 4)) & 1) << 1 | ((b >> p) & 1)
            px[x, y] = pal[c]
    im = im.resize((512, 384), Image.NEAREST)
    dr = ImageDraw.Draw(im)
    dr.rectangle([0, 0, 511, 15], fill=(0, 0, 0))
    sx, sy_, r = f['sun'][0], f['sun'][1], f['sun'][2]
    dr.text((4, 2), 'iter %d  sun (%d,%d) r%d  probes in sight %s/9  probe %s cyc  flare %d cyc' % (
        it, sx, sy_, r, f['seen'] if f['seen'] >= 0 else '-', f['probe'] if f['probe'] >= 0 else '-', f['flare']), fill=(255, 255, 255))
    return im
ims = [img(i) for i in iters]
W = sum(i.width for i in ims) + 8 * (len(ims) - 1)
out_im = Image.new('RGB', (W, ims[0].height), (40, 40, 40))
x = 0
for i in ims:
    out_im.paste(i, (x, 0)); x += i.width + 8
out_im.save(out)
print(out)
