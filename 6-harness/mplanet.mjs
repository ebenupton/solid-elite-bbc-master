// Planet scenes: the planet's surface detail (caps, bands, moon, rings) posed
// on the screen. Flies the gate's pilot to iteration FROM, then holds the keys
// off and, each iteration from FROM, puts the planet (slot 0) at a screen
// position and radius (--x --y --r, or a path --x0 --y0 --x1 --y1 --r0 --r1
// over N iterations), with its type (--type 128 or 130) and the system's seed
// (--qq2 six bytes, hex, as "s0lo,s0hi,..."), and an orientation (--pose
// "ax,ay,az" in degrees: roofv, nosev and sidev rotated from facing us, then
// spun by --spin degrees an iteration about the game's spin axis), or lets
// the game spin it (--pose free); --keep leaves the planet where the game has
// it (with --pose free: the gate's own frames, measured). At each frame's
// end (F_FRAME's ff_stars9, after the stars, bank 6) the back buffer is dumped, with the
// frame's cycles in the planet's routines: G_PFHOOK (the game-context hook),
// T_CAPS (the detail's rows), T_DISCROWS (the disc layer), f_moon, T_MCAPS
// and f_ring when the build has them, and the whole F_FRAME.
//
// node 6-harness/mplanet.mjs [--tree T] --out D [--from 300] [--n 20] ...
//      [--hidesun] [--seedfile 6-harness/work/verify/compare/seeded.json]
// Renders: python3 2-build-files/flarevis.py <out> <png> <iter> [<iter> ...]
// (or 2-build-files/planetvis.py for a labelled sheet)
import { runElite, loadSyms, physRead, mapOfLabel, ROOT } from "./mlib.mjs";
import { makePilot, patchCommander } from "./mpilot.mjs";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
const a = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, arr) => { if (v.startsWith("--")) acc.push([v.slice(2), arr[i + 1] && !arr[i + 1].startsWith("--") ? arr[i + 1] : true]); return acc; }, []));
const TREE = a.tree || ROOT.replace(/\/$/, ""), OUT = a.out;
mkdirSync(OUT, { recursive: true });
const sy = loadSyms(`${TREE}/3-assembled-output/symbols.txt`);
const FROM = +(a.from || 300), N = +(a.n || 20);
const lst = readFileSync(`${TREE}/3-assembled-output/compile.txt`, "utf8").split("\n");
function jsrIn(target, from, span) {
    const t = target.toString(16).toUpperCase().padStart(4, "0");
    for (const l of lst) {
        const m = l.match(/^\s+([0-9A-F]{4})\s+20 ([0-9A-F]{2}) ([0-9A-F]{2})\s+JSR &([0-9A-F]{4})/);
        if (m && m[4] === t && parseInt(m[1], 16) > from && parseInt(m[1], 16) < from + span) return parseInt(m[1], 16);
    }
    throw new Error("JSR not found");
}
const FEND = sy.ff_stars9;
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
const M6 = mapOfLabel(sy, "F_PLX");
const b6 = (cpu, x) => physRead(cpu, M6, x);
const frames = [], log = [];
let cur = -1, armed = false;
const seed = a.seedfile ? JSON.parse(readFileSync(a.seedfile, "utf8")) : null;
// the routines whose cycles are counted: entry address (and bank, for the
// banked ones), until the stack pointer is back above its entry value
const WATCH = ["PL9", "f_bounds", "G_PFHOOK", "T_CAPS", "T_DISCROWS", "T_MOON", "T_RING", "f_moon", "f_ring", "T_MCAPS", "F_FRAME", "G_MERHOOK", "T_MERID"].filter(n => sy[n] !== undefined);
const res = await runElite({ disc: `${TREE}/5-compiled-game-discs/elite-master-sng47.ssd`, syms: sy, pilot, iters: FROM + N + 2, patch: patchCommander, seed,
    onIter: (i, s, r) => {
        const cpu = r.cpu;
        if (!armed) {
            armed = true;
            const cyc = () => (cpu.cycleSeconds + cpu.currentCycles / 2e6) * 2e6;
            const open = [], acc = {};
            cpu.debugInstruction.add(pc => {
                for (let k = open.length - 1; k >= 0; k--) {
                    if (cpu.s > open[k].sp) { acc[open[k].n] = (acc[open[k].n] || 0) + cyc() - open[k].t; open.splice(k, 1); }
                }
                for (const n of WATCH) if (pc === sy[n] && !open.some(o => o.n === n)) {
                    const bk = sy.__bank && sy.__bank[n];
                    if (bk === undefined || (cpu.romsel & 15) === (bk & 15)) open.push({ n, t: cyc(), sp: cpu.s });
                }
                const bank = cpu.romsel & 15;
                if (bank === 6 && pc === FEND && cur >= FROM) {
                    const back = b6(cpu, sy.F_BACK);
                    const base = back ? 0x8000 : 0;
                    const buf = Buffer.alloc(0x3000);
                    for (let k = 0; k < 0x3000; k++) buf[k] = cpu.ramRomOs[base + 0x4000 + k];
                    const w16 = x => { const v = b6(cpu, x) | b6(cpu, x + 1) << 8; return v > 32767 ? v - 65536 : v; };
                    const pal = Array.from(s._machine.processor.video.ulaPal.slice(0, 16));
                    frames.push({ iter: cur, back, sun: [0, 0, 0, 0], seen: -1, probe: -1, flare: 0,
                        planet: [w16(sy.F_PLX), w16(sy.F_PLY), b6(cpu, sy.F_PLR), b6(cpu, sy.F_PLON)], pfcls: cpu.ramRomOs[sy.PF_CLS], qq2: Array.from({ length: 6 }, (_, j) => cpu.ramRomOs[sy.QQ2 + j]), type: cpu.ramRomOs[sy.FRIN], pal, cyc: { ...acc } });
                    for (const k in acc) delete acc[k];
                    writeFileSync(`${OUT}/frame-${String(cur).padStart(6, "0")}.bin`, buf);
                }
                return false;
            });
        }
        cur = i;
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
        }
    } });
writeFileSync(`${OUT}/frames.json`, JSON.stringify({ frames, iterTimes: res.iterTimes, log, FROM, N }));
console.log(`${frames.length} frames`); for (const l of log) console.log(l);
for (const f of frames) console.log(f.iter, "planet", f.planet.join(" "), "cls", f.pfcls, "type", f.type, "qq2", f.qq2.map(x => x.toString(16)).join(","), Object.entries(f.cyc).map(([k, v]) => `${k} ${Math.round(v)}`).join("  "));
