// The moon's path: where the port draws the moon, iteration by iteration, in a
// long flight. Flies the gate's pilot to iteration FROM, then (once, at FROM)
// puts the planet (slot 0) ahead of us (--x --y --r: its screen position and
// radius) in a moon system (--qq2: the seed, six bytes hex), and from then on
// leaves the game to move it: the planet spins as the game spins it and moves
// as we move. Our own flight from FROM is --fly: "still" (keys off), or
// "turn" (a fixed cycle of roll and pitch keys and a little speed, so that our
// pitch and roll turn the view as well as the planet's own spin). Each
// iteration records the planet's position and orientation (slot 0), the sun's
// (slot 1) and the moon as PF_HOOK left it (MN_ON, MN_X, MN_Y, MN_R) and the
// planet's centre and radius on the screen as PF_HOOK saw them (pf_cx, pf_cy,
// pf_r, bank 7; MN_X 32767: no moon placed), and MN_E and MN_OK (MN_TURN's)
// where the build has them.
//
// node 6-harness/mmoonpath.mjs [--tree T] --out FILE.json [--from 300] [--n 1500]
//      [--qq2 76,70,EB,94,0B,D5] [--x 100 --y 90 --r 30] [--fly still|turn]
// Checked by 2-build-files/moonpath.py.
import { runElite, loadSyms, physRead, mapOfLabel, ROOT } from "./mlib.mjs";
import { makePilot, patchCommander, K } from "./mpilot.mjs";
import { writeFileSync } from "fs";
const a = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, arr) => { if (v.startsWith("--")) acc.push([v.slice(2), arr[i + 1] && !arr[i + 1].startsWith("--") ? arr[i + 1] : true]); return acc; }, []));
const TREE = a.tree || ROOT.replace(/\/$/, "");
const sy = loadSyms(`${TREE}/3-assembled-output/symbols.txt`);
const FROM = +(a.from || 300), N = +(a.n || 1500), FLY = a.fly || "still";
const QQ2 = String(a.qq2 || "76,70,EB,94,0B,D5").split(",").map(h => parseInt(h, 16));
// the turn cycle: 400 iterations, each a quarter of roll, pitch, both, none
function turnKeys(k, c) {
    const ph = Math.floor(k / 100) % 4, jx = c.rb(c.sy.JSTX), jy = c.rb(c.sy.JSTY), keys = [];
    const wx = ph === 0 || ph === 2 ? 96 : 128, wy = ph === 1 || ph === 2 ? 160 : 128;
    if (jx > wx + 4) keys.push(K.GT); else if (jx < wx - 4) keys.push(K.LT);
    if (jy > wy + 8) keys.push(K.X); else if (jy < wy - 8) keys.push(K.S);
    return keys;
}
const pilot0 = makePilot();
const mine = c => c.iterOf() >= FROM;
const pilot = { ...pilot0, keys: c => (mine(c) ? (FLY === "turn" ? turnKeys(c.iterOf() - FROM, c) : []) : pilot0.keys(c)),
    dks: c => (mine(c) ? (FLY === "turn" ? turnKeys(c.iterOf() - FROM, c).includes(c.key) : false) : pilot0.dks ? pilot0.dks(c) : false),
    observe: pilot0.observe, P: pilot0.P };
const M7 = mapOfLabel(sy, "pf_cx");
const rec = [];
await runElite({ disc: `${TREE}/5-compiled-game-discs/elite-master-sng47.ssd`, syms: sy, pilot, iters: FROM + N + 1, patch: patchCommander, maxSecs: +(a.maxsecs || 1800),
    onIter: (i, s, r) => {
        const cpu = r.cpu, ram = cpu.ramRomOs, k0 = sy["K%"];
        const c24 = o => { const m = ram[o] | ram[o + 1] << 8 | (ram[o + 2] & 127) << 16; return ram[o + 2] & 128 ? -m : m; };
        const v16 = o => { const m = ram[o] | (ram[o + 1] & 127) << 8; return ram[o + 1] & 128 ? -m : m; };
        const s16 = o => { const v = ram[o] | ram[o + 1] << 8; return v > 32767 ? v - 65536 : v; };
        const b7 = x => physRead(cpu, M7, x);
        const w7 = x => { const v = b7(x) | b7(x + 1) << 8; return v > 32767 ? v - 65536 : v; };
        if (i === FROM) {
            const put = (o, v) => { const m = Math.abs(v); ram[k0 + o] = m & 255; ram[k0 + o + 1] = (m >> 8) & 255; ram[k0 + o + 2] = ((m >> 16) & 127) | (v < 0 ? 128 : 0); };
            const rr = +(a.r || 30), z = Math.round(24576 * 256 / rr);
            put(0, Math.round((+(a.x || 100) - 128) * z / 256)); put(3, Math.round((96 - +(a.y || 90)) * z / 256)); put(6, z);
            ram[sy.FRIN] = a.type ? +a.type : 128;
            ram[sy.DELTA] = 0;
        }
        if (i >= FROM) QQ2.forEach((v, j) => { ram[sy.QQ2 + j] = v; });
        if (i <= FROM) return;
        rec.push({ i, mcnt: ram[sy.MCNT], type: ram[sy.FRIN], P: [0, 3, 6].map(o => c24(k0 + o)),
            nose: [9, 11, 13].map(o => v16(k0 + o)), roof: [15, 17, 19].map(o => v16(k0 + o)), side: [21, 23, 25].map(o => v16(k0 + o)),
            sunType: ram[sy.FRIN + 1], S: [0, 3, 6].map(o => c24(k0 + 37 + o)),
            mn: [ram[sy.MN_ON], s16(sy.MN_X), s16(sy.MN_Y), ram[sy.MN_R]], pl: [w7(sy.pf_cx), w7(sy.pf_cy), b7(sy.pf_r)],
            alpha: ram[sy.ALPHA], beta: ram[sy.BETA], delta: ram[sy.DELTA], view: ram[sy.VIEW],
            E: sy.MN_E === undefined ? null : [0, 3, 6].map(o => { const v = ram[sy.MN_E + o] | ram[sy.MN_E + o + 1] << 8 | ram[sy.MN_E + o + 2] << 16; return v & 0x800000 ? v - 0x1000000 : v; }),
            eok: sy.MN_OK === undefined ? null : ram[sy.MN_OK] });
        ram[sy.MN_X] = 0xFF; ram[sy.MN_X + 1] = 0x7F;  // (a sentinel: pf_moon placed no moon this iteration if it stays)
    } });
writeFileSync(a.out, JSON.stringify({ qq2: QQ2, from: FROM, fly: FLY, rec }));
console.log(`${rec.length} iterations -> ${a.out}`);
