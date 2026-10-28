// The lens flare's occlusion probes: fly the gate's pilot to iteration FROM,
// then hold the keys off and put the sun (slot 1) on a path in front of the
// ship each iteration (as the flare's scratch scene.mjs before it); optionally a
// ship (--ship slot) in front of the sun, on its own path. At each frame's
// end (F_FRAME after f_stars, bank 6) the back buffer is dumped with the
// probes in sight (fl_vn at fl_seen, bank 5), the probes' cycles (R_FLARE to
// fl_seen) and f_flt's cycles (the flare, to f_text2).
//
// node 6-harness/mflarevis.mjs [--tree T] --out D [--from 1000] [--n 100] [--path line|fixed]
//      [--x0 --y0 --x1 --y1 --z] [--ship slot --sx0 --sy0 --sx1 --sy1 --sz]
//      [--hideplanet] [--seedfile 6-harness/work/verify/compare/seeded.json]
// (--tree: the repository whose build to run, by default this one)
// Renders: python3 2-build-files/flarevis.py <out> <png> <iter> [<iter> ...]
import { runElite, loadSyms, physRead, mapOfLabel, ROOT } from "./mlib.mjs";
import { makePilot, patchCommander } from "./mpilot.mjs";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
const a = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, arr) => { if (v.startsWith("--")) acc.push([v.slice(2), arr[i + 1] && !arr[i + 1].startsWith("--") ? arr[i + 1] : true]); return acc; }, []));
const TREE = a.tree || ROOT.replace(/\/$/, ""), OUT = a.out;
mkdirSync(OUT, { recursive: true });
const sy = loadSyms(`${TREE}/3-assembled-output/symbols.txt`);
const FROM = +(a.from || 1000), N = +(a.n || 100);
const lst = readFileSync(`${TREE}/3-assembled-output/compile.txt`, "utf8").split("\n");
function jsrIn(target) {
    const t = target.toString(16).toUpperCase().padStart(4, "0");
    for (const l of lst) {
        const m = l.match(/^\s+([0-9A-F]{4})\s+20 ([0-9A-F]{2}) ([0-9A-F]{2})\s+JSR &([0-9A-F]{4})/);
        if (m && m[4] === t && parseInt(m[1], 16) > sy.F_FRAME && parseInt(m[1], 16) < sy.F_FRAME + 0x200) return parseInt(m[1], 16);
    }
    throw new Error("JSR not found");
}
const FEND = jsrIn(sy.f_stars) + 3;
const FLT = sy.f_flt, FTX = sy.f_text2, RFL = sy.R_FLARE, SEEN = sy.fl_seen ?? -1;
const lerp = (p, q, t) => +p + (q - p) * t;
function target(k) {
    const t = N > 1 ? k / (N - 1) : 0;
    if (a.path === "fixed") return [+(a.x || 160), +(a.y || 80), +(a.z || 303104)];
    return [lerp(a.x0, a.x1, t), lerp(a.y0, a.y1, t), +(a.z || 303104)];
}
function shipTarget(k) {
    const t = N > 1 ? k / (N - 1) : 0;
    return [lerp(a.sx0, a.sx1, t), lerp(a.sy0, a.sy1, t), +(a.sz || 1500)];
}
const pilot0 = makePilot();
const pilot = { ...pilot0, keys: c => (c.iterOf() >= FROM ? [] : pilot0.keys(c)), dks: c => (c.iterOf() >= FROM ? false : pilot0.dks ? pilot0.dks(c) : false), observe: pilot0.observe, P: pilot0.P };
const M6 = mapOfLabel(sy, "F_SUX");
const b6 = (cpu, x) => physRead(cpu, M6, x);
const frames = [], log = [];
let cur = -1, armed = false;
const seed = a.seedfile ? JSON.parse(readFileSync(a.seedfile, "utf8")) : null;
const res = await runElite({ disc: `${TREE}/5-compiled-game-discs/elite-master-sng47.ssd`, syms: sy, pilot, iters: FROM + N + 2, patch: patchCommander, seed,
    onIter: (i, s, r) => {
        const cpu = r.cpu;
        if (!armed) {
            armed = true;
            let tf = 0, tflare = 0, tr = 0, tprobe = -1, seen = -1, kpc = 0;
            const cyc = () => (cpu.cycleSeconds + cpu.currentCycles / 2e6) * 2e6;
            cpu.debugInstruction.add(pc => {
                const bank = cpu.romsel & 15;
                if (bank === 6) {
                    if (pc === FLT) { tf = cyc(); tprobe = -1; seen = -1; }
                    else if (pc === FTX && tf) { tflare = cyc() - tf; tf = 0; }
                    else if (pc === FEND && cur >= FROM) {
                        const back = b6(cpu, sy.F_BACK);
                        const base = back ? 0x8000 : 0;
                        const buf = Buffer.alloc(0x3000);
                        for (let k = 0; k < 0x3000; k++) buf[k] = cpu.ramRomOs[base + 0x4000 + k];
                        const w16 = x => { const v = b6(cpu, x) | b6(cpu, x + 1) << 8; return v > 32767 ? v - 65536 : v; };
                        const pal = Array.from(s._machine.processor.video.ulaPal.slice(0, 16));
                        frames.push({ iter: cur, back, sun: [w16(sy.F_SUX), w16(sy.F_SUY), cpu.ramRomOs[sy.GSUNR], cpu.ramRomOs[sy.GSUNON]],
                            planet: [w16(sy.F_PLX), w16(sy.F_PLY), b6(cpu, sy.F_PLR), b6(cpu, sy.F_PLON)], seen, probe: tprobe, flare: Math.round(tflare), pal });
                        writeFileSync(`${OUT}/frame-${String(cur).padStart(6, "0")}.bin`, buf);
                        tflare = 0;
                    }
                } else if (bank === 5) {
                    if (pc === RFL) tr = cyc();
                    else if (pc === SEEN) { tprobe = Math.round(cyc() - tr); seen = cpu.ramRomOs[0x17]; }
                }
                return false;
            });
        }
        cur = i;
        if (i >= FROM && i < FROM + N) {
            const k1 = sy["K%"] + 37;
            if (cpu.ramRomOs[sy.FRIN + 1] !== 129) { log.push(`iter ${i}: slot 1 is ${cpu.ramRomOs[sy.FRIN + 1]}`); return; }
            const put = (base, o, v) => { const m = Math.abs(v); cpu.ramRomOs[base + o] = m & 255; cpu.ramRomOs[base + o + 1] = (m >> 8) & 255; cpu.ramRomOs[base + o + 2] = ((m >> 16) & 127) | (v < 0 ? 128 : 0); };
            const [tx, ty, z] = target(i - FROM);
            put(k1, 0, Math.round((tx - 128) * z / 256)); put(k1, 3, Math.round((96 - ty) * z / 256)); put(k1, 6, z);
            if (a.hideplanet) cpu.ramRomOs[sy["K%"] + 8] |= 0x80;
            if (a.ship) {
                const sl = +a.ship, ks = sy["K%"] + 37 * sl;
                if (i === FROM) log.push(`slot ${sl} type ${cpu.ramRomOs[sy.FRIN + sl]}`);
                const [sx, syy, sz] = shipTarget(i - FROM);
                put(ks, 0, Math.round((sx - 128) * sz / 256)); put(ks, 3, Math.round((96 - syy) * sz / 256)); put(ks, 6, sz);
                // facing us, upright: nosev (0, 0, -1), roofv (0, 1, 0), sidev (1, 0, 0) (&6000 = 1)
                const vec = (o, x, y, zz) => { [x, y, zz].forEach((c, j) => { cpu.ramRomOs[ks + o + 2 * j] = 0; cpu.ramRomOs[ks + o + 2 * j + 1] = c; }); };
                vec(9, 0, 0, 0xe0); vec(15, 0, 0x60, 0); vec(21, 0x60, 0, 0);
                cpu.ramRomOs[ks + 27] = 0; cpu.ramRomOs[ks + 29] = 0; cpu.ramRomOs[ks + 30] = 0;
            }
        }
        if (i === FROM) { const fr = []; for (let k = 0; k < 12; k++) fr.push(cpu.ramRomOs[sy.FRIN + k]); log.push(`FRIN ${fr.join(" ")}`); }
    } });
writeFileSync(`${OUT}/frames.json`, JSON.stringify({ frames, iterTimes: res.iterTimes, log, FROM, N }));
console.log(`${frames.length} frames`); for (const l of log) console.log(l);
for (const f of frames) console.log(f.iter, "seen", f.seen, "probe", f.probe, "flare", f.flare, "sun", f.sun.join(" "), "planet", f.planet.join(" "));
