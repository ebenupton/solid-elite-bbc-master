// The planet's turn over the gate's run: its vectors at each PF_HOOK call
// (the game's, as drawn) and at each call that makes the records (pf_beach's
// or pf_craters' entry: the fresh frames, every iteration close up, MCNT even
// in deep space), and the player's own roll and pitch (ALP1, BET1). Prints the
// median turn from one iteration to the next with the player still (the
// planet's own pitch and roll, by half steps every iteration: H_MVS4), by
// MCNT's parity and its spread; and from one fresh frame to the next (the
// turn the drawing shows at once), overall and with the player still. Then
// the lengths of the planet's three vectors over the run (unit length 96 x
// 256), and the largest departure of a pair from right angles. Then the calls
// that make records and those that keep them, close up and in deep space (z
// at least 512 x 256), by MCNT's parity, and the kept frames' radius; and,
// with the player still, the turn a kept frame lacks: from the records it
// keeps to the game's vectors.
//
// node 6-harness/mspin.mjs [--disc d] [--syms s] [--iters N] [--seedfile f]
import { runElite, loadSyms, CAND_SYMS, CAND_DISC } from "./mlib.mjs";
import { makePilot, patchCommander } from "./mpilot.mjs";
import { readFileSync } from "fs";
import { parseArgs } from "./args.mjs";
const a = parseArgs({ disc: "value", syms: "value", iters: "value", seedfile: "value" });
const sy = loadSyms(a.syms || CAND_SYMS);
const seed = a.seedfile ? JSON.parse(readFileSync(a.seedfile, "utf8")) : null;
let cur = -1, inst = false;
const calls = [], fresh = [];
const vec = (m, o) => [0, 1, 2].map(j => { const lo = m[sy.INWK + o + 2 * j], hi = m[sy.INWK + o + 2 * j + 1]; const v = lo | (hi & 127) << 8; return hi & 128 ? -v : v; });
await runElite({ disc: a.disc || CAND_DISC, syms: sy, pilot: makePilot(), iters: +(a.iters || 10000), patch: patchCommander, seed, maxSecs: 40000,
    onIter: (i, s, r) => { cur = i; const cpu = r.cpu, m = cpu.ramRomOs; if (inst) return; inst = true;
        cpu.debugInstruction.add(pc => {
            if ((cpu.romsel & 15) !== 7) return false;
            if (pc === sy.PF_HOOK) calls.push({ i: cur, rad: m[sy.K + 1] ? 255 : m[sy.K], on: !m[sy.K + 1] && m[sy.K] >= 6, deep: (m[sy.INWK + 8] & 127) >= 2, made: false, n: vec(m, 9), r: vec(m, 15), s: vec(m, 21), still: !(m[sy.ALP1] & 127) && !(m[sy.BET1] & 127), mcnt: m[sy.MCNT], pl: Math.hypot(m[sy.ALP1] & 127, m[sy.BET1] & 127) / 256 * 180 / Math.PI });
            else if (pc === sy.pf_beach || pc === sy.pf_craters) calls[calls.length - 1].made = true, fresh.push({ i: cur, r: vec(m, 15), s: vec(m, 21), still: !(m[sy.ALP1] & 127) && !(m[sy.BET1] & 127) });
            else if (pc === sy.pf_note && calls.length) calls[calls.length - 1].made = true;   // (as well: a hook can miss an entry)
            return false;
        }); } });
const ang = (u, v) => { const d = u[0] * v[0] + u[1] * v[1] + u[2] * v[2], nu = Math.hypot(...u), nv = Math.hypot(...v); return Math.acos(Math.max(-1, Math.min(1, d / (nu * nv)))) * 180 / Math.PI; };
const med = x => { x.sort((p, q) => p - q); return x.length ? `${x[x.length >> 1].toFixed(2)} deg (n ${x.length})` : "none"; };
const turn = (p, q) => Math.max(ang(q.r, p.r), ang(q.s, p.s));
const it = { even: [], odd: [] }, fr = { all: [], still: [] }, gap = {};
const spread = x => { const y = [...x].sort((p, q) => p - q); return y.length ? `${y[0].toFixed(2)}..${y[y.length - 1].toFixed(2)}` : "none"; };
for (let k = 1; k < calls.length; k++) {
    const p = calls[k - 1], q = calls[k];
    if (q.i !== p.i + 1 || !q.still) continue;
    it[q.mcnt & 1 ? "odd" : "even"].push(turn(p, q));
}
for (let k = 1; k < fresh.length; k++) {
    const p = fresh[k - 1], q = fresh[k], d = q.i - p.i;
    if (d < 1 || d > 4) continue;
    gap[d] = (gap[d] || 0) + 1;
    fr.all.push(turn(p, q));
    if (q.still) fr.still.push(turn(p, q));
}
const pl = calls.map(c => c.pl), mv = pl.filter(x => x > 0);
console.log(`the game's vectors, player still: MCNT even ${med(it.even)}, MCNT odd ${med(it.odd)}; all ${spread([...it.even, ...it.odd])} deg`);
console.log(`the player's own turn: zero in ${pl.length - mv.length} of ${pl.length} calls; when turning, median ${med(mv)}`);
console.log(`from one fresh frame to the next (iterations apart: ${Object.entries(gap).map(([d, n]) => `${d}: ${n}`).join(", ")}): ${med(fr.all)}; player still ${med(fr.still)}`);
const len = { n: [], r: [], s: [] };
let orth = 0;
const dot = (u, v) => (u[0] * v[0] + u[1] * v[1] + u[2] * v[2]) / (Math.hypot(...u) * Math.hypot(...v));
for (const c of calls) {
    for (const k of ["n", "r", "s"]) len[k].push(Math.hypot(...c[k]) / 24576);
    orth = Math.max(orth, ...[[c.n, c.r], [c.n, c.s], [c.r, c.s]].map(([u, v]) => Math.abs(90 - Math.acos(Math.max(-1, Math.min(1, dot(u, v)))) * 180 / Math.PI)));
}
const lr = x => { let lo = Infinity, hi = -Infinity, t = 0; for (const v of x) { lo = Math.min(lo, v); hi = Math.max(hi, v); t += v; } return `${lo.toFixed(4)}..${hi.toFixed(4)} (mean ${(t / x.length).toFixed(4)})`; };
console.log(`vector lengths over ${calls.length} calls (iterations ${calls.length ? calls[0].i : 0}-${calls.length ? calls[calls.length - 1].i : 0}): nosev ${lr(len.n)}, roofv ${lr(len.r)}, sidev ${lr(len.s)}; off right angles at most ${orth.toFixed(2)} deg`);
const keptRad = [];
const n = { close: { even: [0, 0], odd: [0, 0] }, deep: { even: [0, 0], odd: [0, 0] } }, lack = [];
let rec = null;
for (const c of calls) {
    if (!c.on) { rec = null; continue; }
    n[c.deep ? "deep" : "close"][c.mcnt & 1 ? "odd" : "even"][c.made ? 0 : 1]++;
    if (!c.made) keptRad.push(c.rad);
    if (c.made) rec = c; else if (rec && c.still) lack.push(turn(rec, c));
}
for (const k of ["close", "deep"]) console.log(`${k}: MCNT even ${n[k].even[0]} made, ${n[k].even[1]} kept; MCNT odd ${n[k].odd[0]} made, ${n[k].odd[1]} kept`);
console.log(`kept frames' radius: median ${[...keptRad].sort((p, q) => p - q)[keptRad.length >> 1] ?? 0}, at most ${keptRad.length ? Math.max(...keptRad) : 0} pixels`);
console.log(`the turn a kept frame lacks, player still: ${med(lack)}, at most ${lack.length ? lack[lack.length - 1].toFixed(2) : 0} deg`);
process.exit(0);
