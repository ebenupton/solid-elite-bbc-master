"""planetvis.py frames_dir out.png iter [iter ...] [--cols N]: the back
buffers that 6-harness/mplanet.mjs dumped, as PNG (256x192 doubled), labelled
with the iteration, the planet's radius and class and the frame's cycles in
the planet's routines; several frames in a grid."""
import sys, json, os
from PIL import Image, ImageDraw
argv = sys.argv[1:]
cols = 0
if '--cols' in argv:
    k = argv.index('--cols')
    cols = int(argv[k + 1])
    del argv[k:k + 2]
args = argv
d, out = args[0], args[1]
iters = [int(x) for x in args[2:] if x.isdigit()]
meta = {f['iter']: f for f in json.load(open(os.path.join(d, 'frames.json')))['frames']}
if not iters:
    iters = sorted(meta)
PAL = [(0, 0, 0), (0, 255, 255), (255, 0, 255), (255, 255, 0)]     # K, C, M, Y


def img(it):
    f = meta[it]
    buf = open(os.path.join(d, 'frame-%06d.bin' % it), 'rb').read()
    im = Image.new('RGB', (256, 192))
    px = im.load()
    for y in range(192):
        for x in range(256):
            b = buf[(y >> 3) * 0x200 + (x >> 2) * 8 + (y & 7)]
            p = 3 - (x & 3)
            c = ((b >> (p + 4)) & 1) << 1 | ((b >> p) & 1)
            px[x, y] = PAL[c]
    im = im.resize((512, 384), Image.NEAREST)
    dr = ImageDraw.Draw(im)
    dr.rectangle([0, 0, 511, 27], fill=(0, 0, 0))
    cy = f.get('cyc', {})
    dr.text((4, 2), 'iter %d  planet (%d,%d) r%d  class %02X' % (it, f['planet'][0], f['planet'][1], f['planet'][2], f.get('pfcls', 0)), fill=(255, 255, 255))
    dr.text((4, 14), '  '.join('%s %d' % (k, v) for k, v in sorted(cy.items()) if k != 'F_FRAME'), fill=(200, 200, 200))
    return im


ims = [img(i) for i in iters]
cols = cols or len(ims)
rows = (len(ims) + cols - 1) // cols
W, H = ims[0].width, ims[0].height
out_im = Image.new('RGB', (cols * W + 8 * (cols - 1), rows * H + 8 * (rows - 1)), (40, 40, 40))
for k, i in enumerate(ims):
    out_im.paste(i, ((k % cols) * (W + 8), (k // cols) * (H + 8)))
out_im.save(out)
print(out)
