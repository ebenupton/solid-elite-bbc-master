#!/usr/bin/env node
// mdprof.mjs: the Master port's disc layer profiled over windows of a replayed run:
// per iteration, the cycles of every routine on the call stack (inc) and on its
// top (cx), their calls, and each call of the two-colour rows' strip encoders
// (r_dpe, r_dq): what it was given (no old span, the same count, one more or one
// fewer boundary, the colour flipped, the old count unknown), how it ended (its
// strips written; one-colour; painted segment by segment; repainted) and its
// cycles before its first write, in r_sw (the strips' pixels) and in the
// repaints (r_dp2, r_dpb, r_ddw, r_drg). One JSON array of iterations (--out);
// a summary per window on stdout.
//   node 6-harness/discmem/mdprof.mjs --log run1/inputs.jsonl --cand 5-compiled-game-discs/elite-master-sng47.ssd
//        --csyms 3-assembled-output/symbols.txt --windows 300-403,5355-5457 [--out x.json]
import { replayMachine, CYCLES_PER_FRAME } from "../solidspan/common.mjs";
import { loadSyms, mapOfLabel } from "../mlib.mjs";
import { mapAt } from "../mlib.mjs";
import { parseArgs } from "../args.mjs";
import { writeFileSync } from "fs";
const a = parseArgs({ log: "value", cand: "value", csyms: "value", windows: "value", out: "value", routines: "value" });
if (!a.log || !a.cand || !a.csyms || !a.windows) { console.error("--log, --cand, --csyms and --windows are required"); process.exit(2); }
const sy = loadSyms(a.csyms);
// a label's mapping; one exported from a scope (.^name) has no bank in banks.txt:
// it is in the disc layer's files, R_DISCROWS' bank
function mapOf(n) {
    const v = sy[n], m = mapOfLabel(sy, n);
    if (m !== "m" || v < 0x8000 || v >= 0xc000) return m;
    return mapOfLabel(sy, "R_DISCROWS");
}
const ROUT = ["F_FRAME", "T_DISCROWS", "R_DISCROWS", "r_dbm", "r_dmb", "r_dpe", "r_dq", "r_drg", "r_dp2", "r_dp2+2", "r_dp1",
    "r_dpb", "r_ddw", "r_segw", "r_sw", "r_bstore", "r_dla", "r_dlb", "R_DISC2", "r_rowset", "r_bcols", ...(a.routines ? a.routines.split(",") : [])];
const ENT = new Map(), at = {};
for (const r of ROUT) {
    const [n, off] = r.split("+"), v = sy[n];
    if (v === undefined) continue;
    const ad = v + (+off || 0);
    ENT.set(mapOf(n) + ":" + ad, r);
}
for (const n of ["r_dmbx"]) at[n] = sy[n] !== undefined ? mapOf(n) + ":" + sy[n] : null;
// r_dpe's row X as given: the old span empty; else the old and new counts and
// colours (R_NDN, r_bdn: count + &80 for colour B, &40 unknown) the same, one
// more or fewer boundary, the colour flipped, or more apart; "/span" if the
// span is the same (only the count or colour changed). The per-buffer arrays'
// addresses are read from r_dpe's own patched operands
const opnd = n => { const p = sy[n] + 1; return cpu.readmem(p) | cpu.readmem(p + 1) << 8; };
function kindOf(x) {
    const rd = n => cpu.readmem(opnd(n) + x);
    if (rd("r_pt132") === 0xff) return "oempty";
    const nn = cpu.readmem(sy.R_NDN + x), on = rd("r_pt154");
    const d = (nn & 0x7f) - (on & 0x7f), flip = ((nn ^ on) & 0x80) !== 0;
    let k = on === 0x40 ? "unknown" : d === 0 ? (flip ? "flip" : "same") : d === 1 ? "more" : d === -1 ? "fewer" : "apart";
    if (cpu.readmem(sy.R_NDISCL + x) === rd("r_pt132") && cpu.readmem(sy.R_NDISCR + x) === rd("r_pt133")) k += "/span";
    return k + (nn & 0x7f);
}
const rowOf = x => { const rd = n => cpu.readmem(opnd(n) + x), r = sy.R_NDX0 !== undefined ? sy.R_NDX0 : 0;
    return `o ${rd("r_pt132")}|${rd("r_pt134")},${rd("r_pt135")}|${rd("r_pt133")} n${(rd("r_pt154") & 0x7f)} -> ${cpu.readmem(sy.R_NDISCL + x)}|${[0, 1, 2, 3].map(i => cpu.readmem(sy["R_NDX" + i] + x)).join(",")}|${cpu.readmem(sy.R_NDISCR + x)} n${cpu.readmem(sy.R_NDN + x) & 0x7f}`; };
const W = a.windows.split(",").map(s => s.split("-").map(Number));
const END = Math.max(...W.map(w => w[1]));
const m = await replayMachine(a.log, a.cand, a.csyms);
const cpu = m.cpu;
const iters = [];
let cur = null, on = false, fr = [], lastc = 0, rec = null, qrec = null, wrec = null;
const pop = c => {
    const f = fr.pop();
    cur.inc[f.n] = (cur.inc[f.n] || 0) + c - f.c0;
    if (f.n === "r_sw" && wrec) { wrec.sw += c - f.c0; wrec.nsw++; }
    if (f.n === "r_sw") { if (rec) { rec.sw += c - f.c0; rec.nsw++; } if (qrec) { qrec.sw += c - f.c0; qrec.nsw++; } }
    if (rec && f.n !== "r_dpe" && /^r_(dp(2|b)|ddw|drg)/.test(f.n) && !fr.some(g => /^r_(dp(2|b)|ddw|drg)/.test(g.n))) rec.fb += c - f.c0;
    if (f.n === "r_ddw" && wrec) { wrec.t = c - wrec.c0; cur.ddw.push(wrec); wrec = null; }
    if (rec && f.n === "r_dpe") { if (rec.out === "?") rec.out = "ok"; rec.t = c - rec.c0; cur.dpe.push(rec); rec = null; }
    if (qrec && (f.n === "r_drg" || f.n === "r_ddw")) qrec.fb += c - f.c0, qrec.out = f.n === "r_drg" ? "gen" : "ddw";
    if (qrec && f.n === "r_dq") { qrec.t = c - qrec.c0; cur.dq.push(qrec); qrec = null; }
};
m.onIter = mm => {
    if (cur) { const c = mm.cyclesNow(); while (fr.length) pop(c); cur.wall = c - cur.a0; iters.push(cur); cur = null; }
    const w = W.find(([x, y]) => mm.iter >= x && mm.iter < y);
    on = !!w; fr = []; rec = qrec = wrec = null;
    if (on) { cur = { it: mm.iter, w: w.join("-"), cx: {}, inc: {}, calls: {}, dpe: [], dq: [], ddw: [], a0: mm.cyclesNow(), dr: [1, 1], ch: [true, true] }; lastc = cur.a0; }
};
cpu.debugInstruction.add(pc => {
    if (!on) return false;
    const c = m.cyclesNow(), s = cpu.s;
    if (fr.length) { const t = fr[fr.length - 1].n; cur.cx[t] = (cur.cx[t] || 0) + c - lastc; }
    lastc = c;
    while (fr.length && s > fr[fr.length - 1].sp) pop(c);
    const key = mapAt(cpu.romsel, pc) + ":" + pc;
    if (key === at.r_dmbx) while (fr.length && fr.some(f => f.n === "r_dq")) pop(c);   // (r_dq, JMPed to, ends there)
    const n = ENT.get(key);
    if (n) {
        fr.push({ n, sp: s, c0: c });
        cur.calls[n] = (cur.calls[n] || 0) + 1;
        if (n === "r_dpe") rec = { c0: c, k: kindOf(cpu.x), out: "?", pre: null, sw: 0, nsw: 0, fb: 0, row: rowOf(cpu.x) };
        if (n === "r_dq") qrec = { c0: c, out: "ok", pre: null, sw: 0, nsw: 0, fb: 0 };
        if (n === "r_sw") { if (rec && rec.pre === null) rec.pre = c - rec.c0; if (qrec && qrec.pre === null) qrec.pre = c - qrec.c0; }
        if (n === "r_ddw") wrec = { c0: c, k: "", out: rec ? "dpe" : qrec ? "dq" : "?", pre: null, sw: 0, nsw: 0, fb: 0 };
        if (rec && rec.out === "?") {
            if (n === "r_ddw" || n === "r_drg") { rec.out = n.slice(2); if (rec.pre === null) rec.pre = c - rec.c0; }
            if (n === "r_segw") { rec.out = "segw"; if (rec.pre === null) rec.pre = c - rec.c0; }
            if (n === "r_dp2+2" || n === "r_dpb") { rec.out = "1col"; if (rec.pre === null) rec.pre = c - rec.c0; }
        }
    }
    return false;
});
while (m.iter <= END) { m.run(CYCLES_PER_FRAME); m.snaps.length = 0; }
if (process.env.ROWS) for (const i of iters) for (const r of i.dpe) if (r.k.startsWith(process.env.ROWS) && (!process.env.OUT || r.out === process.env.OUT)) console.log(i.it, r.k, r.out, r.row);
if (a.out) writeFileSync(a.out, JSON.stringify(iters));
for (const [x, y] of W) {
    const I = iters.filter(i => i.it >= x && i.it < y), n = I.length;
    const wall = I.reduce((s, i) => s + i.wall, 0) / n;
    const inc = k => I.reduce((s, i) => s + (i.inc[k] || 0), 0) / n;
    const calls = k => I.reduce((s, i) => s + (i.calls[k] || 0), 0) / n;
    console.log(`== ${x}-${y}: ${n} iterations, ${wall.toFixed(0)} cycles an iteration (${(2e6 / wall).toFixed(2)} it/s)`);
    for (const k of ["R_DISCROWS", "r_dmb", "r_dpe", "r_dq", "r_segw", "r_ddw", "r_drg", "r_dp2+2", "r_sw", "R_DISC2"])
        console.log(`  ${k.padEnd(11)} ${inc(k).toFixed(0).padStart(7)} cycles (${(100 * inc(k) / wall).toFixed(2)}%), ${calls(k).toFixed(1)} calls`);
    for (const [nm, f] of [["r_dpe", "dpe"], ["r_dq", "dq"], ["r_ddw", "ddw"]]) {
        const R = I.flatMap(i => i[f]);
        if (!R.length) continue;
        const grp = {};
        for (const r of R) { const g = (grp[(r.k ? r.k + "/" : "") + r.out] ||= { n: 0, t: 0, pre: 0, sw: 0, nsw: 0, fb: 0 }); g.n++; g.t += r.t; g.pre += r.pre ?? (r.t - r.sw - r.fb); g.sw += r.sw; g.nsw += r.nsw; g.fb += r.fb; }
        const tot = R.reduce((s, r) => s + r.t, 0), own = R.reduce((s, r) => s + r.t - r.sw - r.fb, 0);
        console.log(`  ${nm}: ${(R.length / n).toFixed(1)} calls an iteration, ${(tot / R.length).toFixed(0)} cycles a call (${(own / R.length).toFixed(0)} its own, less r_sw and the repaints), ${(100 * tot / n / wall).toFixed(2)}% of the iteration (${(100 * own / n / wall).toFixed(2)}% its own)`);
        for (const [k, g] of Object.entries(grp).sort((p, q) => q[1].n - p[1].n))
            console.log(`    ${k.padEnd(12)} ${(g.n / n).toFixed(2).padStart(6)}/it (${(100 * g.n / R.length).toFixed(0).padStart(3)}%)  ${(g.t / g.n).toFixed(0).padStart(5)} a call: before its first write ${(g.pre / g.n).toFixed(0).padStart(4)}, r_sw ${(g.sw / g.n).toFixed(0).padStart(4)} (${(g.nsw / g.n).toFixed(1)} strips), repaints ${(g.fb / g.n).toFixed(0)}`);
    }
}
process.exit(0);
