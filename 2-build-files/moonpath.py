"""moonpath.py RUN.json [--max-err 3] [--max-turn 0.5]: check a moon path that
6-harness/mmoonpath.mjs recorded (a long flight in a moon system, iteration by
iteration). The moon must stay at a fixed place in space relative to the
planet, moving on the screen only as our flight moves it, as the planet and
the sun do:

  * fixed in space: E = moon - planet (MN_E) keeps its length, and its angle
    to a vector the game itself keeps fixed in space, slot 1's object (the
    sun or the station) less the planet, turned by the game's own MVEIT,
    stays the same (to --max-turn degrees);
  * drawn there: where pf_moon placed the moon (MN_X, MN_Y), it is where
    planet + E projects (x = 128 + 256 x / z, y = 96 - 256 y / z), to
    --max-err pixels;
  * smooth: the moon's step on the screen from one iteration to the next is
    the projected point's step, to --max-err pixels.

A run without MN_E (a build without MN_TURN) is measured against the
planet's spin axis instead (nosev - sidev, D radii out), and the same
numbers are printed, for comparison. Exit status 1 if a check fails (with
MN_E)."""
import sys, json, math

args = sys.argv[1:]
opt = {'--max-err': 3.0, '--max-turn': 0.5}
for k in list(opt):
    if k in args:
        i = args.index(k)
        opt[k] = float(args[i + 1])
        del args[i:i + 2]
d = json.load(open(args[0]))
R = d['rec']
q = d['qq2']
h = q[1] ^ q[3] ^ q[5]
D = (3, 3.75, 4.5, 5.25)[(h >> 2) & 3]


def E_of(r):
    if r.get('E') is not None:
        return r['E'] if r['eok'] & 0x80 else None
    w = [a - b for a, b in zip(r['nose'], r['side'])]
    n = math.sqrt(sum(x * x for x in w))
    k = D * 24576 / n * (-1 if h & 16 else 1)
    return [x * k for x in w]


def ang(a, b):
    c = sum(x * y for x, y in zip(a, b)) / math.sqrt(sum(x * x for x in a) * sum(y * y for y in b))
    return math.degrees(math.acos(max(-1, min(1, c))))


def proj(M):
    if M[2] <= 0:
        return None
    return (128 + 256 * M[0] / M[2], 96 - 256 * M[1] / M[2])


new = R[0].get('E') is not None
lens, angs, errs, steps, msteps, psteps = [], {}, [], [], [], []
prev = None
for r in R:
    E = E_of(r)
    if E is None or r.get('view', 0) != 0:
        prev = None
        continue
    lens.append(math.sqrt(sum(x * x for x in E)))
    if r['sunType'] in (2, 129):
        V = [s - p for s, p in zip(r['S'], r['P'])]
        angs.setdefault(r['sunType'], []).append(ang(E, V))
    M = [p + e for p, e in zip(r['P'], E)]
    pr = proj(M)
    placed = r['mn'][1] != 32767
    if pr and placed:
        errs.append(math.hypot(r['mn'][1] - pr[0], r['mn'][2] - pr[1]))
    cur = (pr, (r['mn'][1], r['mn'][2]) if placed else None, (r['pl'][0], r['pl'][1]))
    if prev and prev[0] and cur[0] and prev[1] and cur[1]:
        dpx, dpy = cur[0][0] - prev[0][0], cur[0][1] - prev[0][1]
        dmx, dmy = cur[1][0] - prev[1][0], cur[1][1] - prev[1][1]
        steps.append(math.hypot(dmx - dpx, dmy - dpy))
        msteps.append(math.hypot(dmx, dmy))
        psteps.append(math.hypot(cur[2][0] - prev[2][0], cur[2][1] - prev[2][1]))
    prev = cur
fail = []
print('%s: %d iterations (%s), D %.2f' % (args[0], len(R), 'MN_E' if new else 'the old model: nosev - sidev', D))
if lens:
    lv = (max(lens) - min(lens)) / (sum(lens) / len(lens))
    print('  |E|: %.0f .. %.0f (%.3f%%)' % (min(lens), max(lens), 100 * lv))
    if new and lv > 0.01:
        fail.append('|E| varies')
for t, a in angs.items():
    rng = max(a) - min(a)
    print('  angle to slot 1 (%s) - planet: %.2f .. %.2f degrees (range %.2f, %d iterations)' % ('sun' if t == 129 else 'station', min(a), max(a), rng, len(a)))
    if new and rng > opt['--max-turn']:
        fail.append('E turns against slot 1')
if errs:
    print('  drawn vs planet + E projected: mean %.2f, max %.2f pixels (%d iterations)' % (sum(errs) / len(errs), max(errs), len(errs)))
    if new and max(errs) > opt['--max-err']:
        fail.append('drawn away from planet + E')
if steps:
    print('  step on the screen: moon max %.1f, planet max %.1f; moon less projected point: mean %.2f, max %.2f pixels (%d steps)'
          % (max(msteps), max(psteps), sum(steps) / len(steps), max(steps), len(steps)))
    if new and max(steps) > opt['--max-err']:
        fail.append('a step not the projected point\'s')
if new:
    print('MOONPATH %s%s' % ('PASS' if not fail else 'FAIL: ', ', '.join(fail)))
    sys.exit(1 if fail else 0)
