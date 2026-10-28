"""sunnear.py frames_dir out_dir [--sheet k,k,...] [--mp4 file] [--gif file]:
the back buffers dumped by 6-harness/msunnear.mjs as PNG frames (256x192
doubled, pixel aspect as the screen), out_dir/frame-NNNN.png; optionally a
contact sheet of some frames with their numbers, an MP4 (ffmpeg) and a GIF."""
import sys, json, os, subprocess
from PIL import Image, ImageDraw
d, out = sys.argv[1], sys.argv[2]
opts = dict(zip(sys.argv[3::2], sys.argv[4::2]))
os.makedirs(out, exist_ok=True)
meta = json.load(open(os.path.join(d, 'frames.json')))
frames = meta['frames']
def pal_of(f):
    p = []
    for idx in (0, 2, 8, 10):   # MODE 1 logical colours 0..3: ULA entries 0, 2, 8, 10 (ABGR)
        v = f['pal'][idx] & 0xffffffff
        p.append((v & 255, (v >> 8) & 255, (v >> 16) & 255))
    if len(set(p)) < 3:
        p = [(0, 0, 0), (255, 0, 0), (0, 255, 255), (255, 255, 0)]
    return p
def img(f):
    buf = open(os.path.join(d, 'frame-%06d.bin' % f['k']), 'rb').read()
    pal = pal_of(f)
    im = Image.new('RGB', (256, 192))
    px = im.load()
    for y in range(192):
        for x in range(256):
            b = buf[(y >> 3) * 0x200 + (x >> 2) * 8 + (y & 7)]
            p = 3 - (x & 3)
            px[x, y] = pal[((b >> (p + 4)) & 1) << 1 | ((b >> p) & 1)]
    return im.resize((640, 384), Image.NEAREST)
ims = {}
for f in frames:
    im = img(f)
    ims[f['k']] = im
    im.save(os.path.join(out, 'frame-%04d.png' % f['k']))
if '--sheet' in opts:
    ks = [int(x) for x in opts['--sheet'].split(',')]
    W, H = 640 // 2, 384 // 2
    cols = min(4, len(ks))
    rows = (len(ks) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * (W + 6), rows * (H + 20)), (40, 40, 40))
    for i, k in enumerate(ks):
        f = next(f for f in frames if f['k'] == k)
        t = ims[k].resize((W, H), Image.LANCZOS)
        x, y = (i % cols) * (W + 6), (i // cols) * (H + 20)
        sheet.paste(t, (x, y + 18))
        ImageDraw.Draw(sheet).text((x + 4, y + 3), 'frame %d  probes %s/9' % (k, f['seen'] if f['seen'] >= 0 else '-'), fill=(255, 255, 255))
    sheet.save(os.path.join(out, 'sheet.png'))
if '--mp4' in opts:
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', '12.5', '-i', os.path.join(out, 'frame-%04d.png'),
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', opts['--mp4']], check=True)
if '--gif' in opts:
    seq = [ims[k] for k in sorted(ims)]
    seq[0].save(opts['--gif'], save_all=True, append_images=seq[1:], duration=80, loop=0)
print(len(ims), 'frames')
