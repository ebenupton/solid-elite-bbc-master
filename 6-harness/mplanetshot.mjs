// Planet stills for the README: a planet (and optionally its sun) posed on
// the screen, as mplanet.mjs poses it, and the whole screen (the space view
// and the dashboard) saved once the scene has settled.
//
// node 6-harness/mplanetshot.mjs [--tree T] --png FILE [--from 300] [--n 20]
//      [--x --y --r --type --qq2 --pose --spin as mplanet.mjs]
//      [--sun "x,y,z"] (the sun, slot 1, at these coordinates' high bytes,
//      signed; in front of the planet's distance it is drawn in front)
//      [--crop x0,y0,x1,y1] (save only that rectangle of the screenshot)
// (--tree: the repository whose build to run, by default this one)
//
// The README's images are these, each with --crop 184,68,696,564 (the
// screenshot cropped to (184, 68)-(696, 564): the space view and the
// dashboard, 512 x 496):
//   images/solid-elite-craters.png:
//     --type 130 --qq2 38,BA,7C,0D,5E,41 --x 150 --y 100 --r 80 --pose 30,-40,10
//   images/solid-elite-beach-ball-planet.png:
//     --type 128 --x 120 --y 100 --r 85 --pose 20,30,0
//   images/solid-elite-sun-near-planet.png:
//     --type 128 --x 110 --y 190 --r 120 --pose 20,30,0 --sun 70,120,1300
import { runElite, loadSyms, ROOT } from "./mlib.mjs";
import { makePilot, patchCommander } from "./mpilot.mjs";
import { sharp } from "./jsbeeb.mjs";
import { readFileSync, writeFileSync } from "fs";
const a = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, arr) => { if (v.startsWith("--")) acc.push([v.slice(2), arr[i + 1] && !arr[i + 1].startsWith("--") ? arr[i + 1] : true]); return acc; }, []));
const TREE = a.tree || ROOT.replace(/\/$/, "");
const sy = loadSyms(`${TREE}/3-assembled-output/symbols.txt`);
const FROM = +(a.from || 300), N = +(a.n || 20);
const lerp = (p, q, t) => +p + (q - p) * t;
function target(k) {
    const t = N > 1 ? k / (N - 1) : 0;
    if (a.x0 !== undefined) return [lerp(a.x0, a.x1, t), lerp(a.y0, a.y1, t), lerp(a.r0 ?? a.r ?? 60, a.r1 ?? a.r ?? 60, t)];
    return [+(a.x ?? 128), +(a.y ?? 96), +(a.r ?? 60)];
}
// the orientation: unit vectors (1 = &6000) rotated by ax about x, ay about y,
// az about z (degrees), in Elite's axes; then by k * spin about the game's
// spin axis (nosev - sidev: the planet pitches and rolls alike)
function rot(v, ax, ang) {
    const c = Math.cos(ang), s = Math.sin(ang), [x, y, z] = v;
    if (ax === 0) return [x, y * c - z * s, y * s + z * c];
    if (ax === 1) return [x * c + z * s, y, -x * s + z * c];
    return [x * c - y * s, x * s + y * c, z];
}
function rotAxis(v, u, ang) {               // Rodrigues
    const c = Math.cos(ang), s = Math.sin(ang), d = v[0] * u[0] + v[1] * u[1] + v[2] * u[2];
    const cr = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
    return [0, 1, 2].map(i => v[i] * c + cr[i] * s + u[i] * d * (1 - c));
}
function pose(k) {
    const [ax, ay, az] = String(a.pose || "0,0,0").split(",").map(x => (+x) * Math.PI / 180);
    let vs = [[0, 0, -1], [0, 1, 0], [1, 0, 0]];      // nosev, roofv, sidev: facing us
    vs = vs.map(v => rot(rot(rot(v, 0, ax), 1, ay), 2, az));
    const sp = (+(a.spin || 0)) * Math.PI / 180 * k;
    if (sp) {
        let u = [0, 1, 2].map(i => vs[0][i] - vs[2][i]); const n = Math.hypot(...u); u = u.map(x => x / n);
        vs = vs.map(v => rotAxis(v, u, sp));
    }
    return vs;
}
const pilot0 = makePilot();
const pilot = { ...pilot0, keys: c => (c.iterOf() >= FROM ? [] : pilot0.keys(c)), dks: c => (c.iterOf() >= FROM ? false : pilot0.dks ? pilot0.dks(c) : false), observe: pilot0.observe, P: pilot0.P };
const seed = a.seedfile ? JSON.parse(readFileSync(a.seedfile, "utf8")) : null;
const res = await runElite({ disc: `${TREE}/5-compiled-game-discs/elite-master-sng47.ssd`, syms: sy, pilot, iters: FROM + N + 2, patch: patchCommander, seed,
    onIter: (i, s, r) => {
        const cpu = r.cpu;
        if (i >= FROM && i < FROM + N) {
            const k0 = sy["K%"];
            const put = (base, o, v) => { const m = Math.abs(v); cpu.ramRomOs[base + o] = m & 255; cpu.ramRomOs[base + o + 1] = (m >> 8) & 255; cpu.ramRomOs[base + o + 2] = ((m >> 16) & 127) | (v < 0 ? 128 : 0); };
            const [tx, ty, rr] = target(i - FROM);
            const z = Math.round(24576 * 256 / rr);
            if (!a.keep) { put(k0, 0, Math.round((tx - 128) * z / 256)); put(k0, 3, Math.round((96 - ty) * z / 256)); put(k0, 6, z); }
            if (a.type) cpu.ramRomOs[sy.FRIN] = +a.type;
            if (a.qq2) String(a.qq2).split(",").forEach((h, j) => { cpu.ramRomOs[sy.QQ2 + j] = parseInt(h, 16); });
            if (a.pose !== "free" && (a.pose !== undefined || i === FROM)) {
                const vs = pose(i - FROM);
                const w = (o, v) => { const m = Math.min(32767, Math.round(Math.abs(v) * 24576)); cpu.ramRomOs[k0 + o] = m & 255; cpu.ramRomOs[k0 + o + 1] = (m >> 8) | (v < 0 ? 128 : 0); };
                [9, 15, 21].forEach((o, j) => { w(o, vs[j][0]); w(o + 2, vs[j][1]); w(o + 4, vs[j][2]); });
            }
            if (a.hidesun && cpu.ramRomOs[sy.FRIN + 1] === 129) cpu.ramRomOs[sy["K%"] + 37 + 8] |= 0x80;
            if (a.sun) {                        // the sun in slot 1, at (x, y, z) high bytes
                cpu.ramRomOs[sy.FRIN + 1] = 129;
                String(a.sun).split(",").forEach((c, j) => { const v = +c, m = Math.abs(v); cpu.ramRomOs[k0 + 37 + 3 * j] = 0; cpu.ramRomOs[k0 + 37 + 3 * j + 1] = m & 255; cpu.ramRomOs[k0 + 37 + 3 * j + 2] = ((m >> 8) & 127) | (v < 0 ? 128 : 0); });
            }
        }
    } });
await res.s.runFor(2000000 * 0.1);
let png = await res.s.screenshotActive({ scale: 1 });
if (a.crop) {
    const [x0, y0, x1, y1] = String(a.crop).split(",").map(Number);
    png = await sharp(png).extract({ left: x0, top: y0, width: x1 - x0, height: y1 - y0 }).png().toBuffer();
}
writeFileSync(a.png, png);
console.log(`${a.png}`);
