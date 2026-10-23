// The flip-interval distribution: how many fields each frame of the
// double-buffered space view is shown for. H_VSYNC (gfx-gluehooks.asm) shows
// the pending back buffer at a vsync; a flip is a call of H_VSYNC at whose
// entry GFLIP was set and on whose return it is clear. The interval between
// two flips, in emulated time over 39936 cycles a field, is the number of
// fields the first frame was on show. (An interval with fewer H_VSYNC calls
// than fields, a vsync interrupt held off for over a field, is listed.)
//
// node 6-harness/mflips.mjs [--cand disc --csyms symbols] [--iters 10000] [--out file.json]
//      flown as the gate flies it (mpilot's pilot, commander patch, boot seed
//      against the SNG47 reference, as the gate)
// node 6-harness/mflips.mjs [--cand disc --csyms symbols] --title SECS
//      the title screen alone, no key pressed, for SECS emulated seconds
//
// Prints the histogram (interval in fields: count, share), per pilot phase in
// gate mode, and "MFLIPS min=<n>": the shortest interval seen.
import { runElite, loadSyms, bootMaster, CAND_DISC, CAND_SYMS, REF_DISC, REF_SYMS } from "./mlib.mjs";
import { makePilot, patchCommander } from "./mpilot.mjs";
import { writeFileSync } from "fs";
import { parseArgs } from "./args.mjs";

const args = parseArgs({ cand: "value", csyms: "value", iters: "value", out: "value", title: "value" });
if (!args.cand !== !args.csyms) { console.error("--cand and --csyms go together"); process.exit(2); }
const CAND = args.cand || CAND_DISC;
const sy = loadSyms(args.csyms || CAND_SYMS);
for (const n of ["H_VSYNC", "GFLIP", "QQ11"]) if (sy[n] === undefined) throw new Error(`${n} not in symbols`);
const HV = sy.H_VSYNC;
const HVEND = Math.min(...Object.values(sy).filter(v => v > HV + 8 && v < HV + 64 && v !== HV), HV + 64);   // (H_VSYNC's extent: the next routine)

const hist = {}, byTag = {}, odd = [];
let curIter = -1;
let tag = "title";
function attach(cpu) {
    let vs = 0, inHv = false, pend = 0, last = -1, lastT = 0;
    const now = () => cpu.cycleSeconds * 2e6 + cpu.currentCycles;
    cpu.debugInstruction.add(pc => {
        if (pc === HV) { vs++; inHv = true; pend = cpu.ramRomOs[sy.GFLIP]; return false; }
        if (inHv && (pc < HV || pc >= HVEND)) {
            inHv = false;
            if (pend && !cpu.ramRomOs[sy.GFLIP]) {
                const tNow = now();
                if (last >= 0) {
                    const d = Math.round((tNow - lastT) / 39936), calls = vs - last;
                    if (calls !== d) odd.push({ fields: d, handlerCalls: calls, iter: curIter, tag });
                    hist[d] = (hist[d] || 0) + 1;
                    const t = (byTag[tag] ||= {});
                    t[d] = (t[d] || 0) + 1;
                }
                last = vs; lastT = tNow;
            }
        }
        return false;
    });
}

if (args.title) {
    const s = await bootMaster(CAND);
    const cpu = s._machine.processor;
    attach(cpu);
    const end = cpu.cycleSeconds + +args.title;
    while (cpu.cycleSeconds < end) cpu.execute(50000);
} else {
    const REF = REF_DISC, RSYMS = REF_SYMS;
    const ITERS = +(args.iters || 10000);
    const ref = await runElite({ disc: REF, syms: loadSyms(RSYMS), pilot: makePilot(), iters: 1, maxSecs: 200, patch: patchCommander });
    const seedBoot = (cregions, written, rb) => {
        const out = []; let o = 0;
        for (const [, n, name] of ref.regions) {
            const c = cregions.find(r => r[2] === name);
            if (c && c[1] === n) for (let i = 0; i < n; i++) if (!written.has(c[0] + i) && rb(c[0] + i) !== ref.init[o + i]) out.push([c[0] + i, [ref.init[o + i]]]);
            o += n;
        }
        return out;
    };
    const pilot = makePilot();
    let hooked = false;
    const r = await runElite({
        disc: CAND, syms: sy, pilot, iters: ITERS, maxSecs: 4 * ITERS, patch: patchCommander, seedBoot,
        onIter: (i, s) => { if (!hooked) { hooked = true; attach(s._machine.processor); } tag = pilot.P.phase; curIter = i; },
    });
    console.log(`iterations ${r.iters}, emulated ${r.emuSecs.toFixed(1)} s${r.error ? ", error " + r.error : ""}`);
}

const show = (h, label) => {
    const n = Object.values(h).reduce((a, b) => a + b, 0);
    const keys = Object.keys(h).map(Number).sort((a, b) => a - b);
    const mean = keys.reduce((a, k) => a + k * h[k], 0) / (n || 1);
    console.log(`${label}: ${n} frames, mean ${mean.toFixed(2)} fields (${(50 / mean).toFixed(1)} fps); ` +
        keys.map(k => `${k}:${h[k]} (${(100 * h[k] / n).toFixed(1)}%)`).join("  "));
};
show(hist, "all");
for (const [t, h] of Object.entries(byTag)) if (t !== "all") show(h, "  " + t);
const min = Math.min(...Object.keys(hist).map(Number));
if (args.out) writeFileSync(args.out, JSON.stringify({ hist, byTag }, null, 1));
for (const o of odd.slice(0, 20)) console.log("vsync interrupt missed (fields, H_VSYNC calls):", JSON.stringify(o));
if (odd.length) console.log(`${odd.length} intervals with a vsync interrupt missed`);
console.log(`MFLIPS min=${min}`);
