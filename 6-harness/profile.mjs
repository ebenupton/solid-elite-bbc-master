// Cycle profile of full Master Elite per (mapping, PC), for weighting the grind's
// windows, over exactly the run the gate (6-harness/verify.sh) times.
//
// node 6-harness/profile.mjs [--disc d] [--syms s]
//                                     [--iters 10000] [--seed boot|none]
//                            [--out 6-harness/work/profile.json] [--pagex]
//
// The run: mlib.mjs runElite with mpilot.mjs's pilot and its commander
// patch, the candidate's boot leftovers seeded from the reference disc at TT170 exactly
// as mcompare.mjs --seed boot does (the reference is booted to its first MLOOP
// for that), --iters MLOOP iterations (the gate's 10000) -- so the same pilot, seeds and
// trajectory as 6-harness/verify.sh 10000.  (Defaults: the build's disc and
// symbols, 5-compiled-game-discs and 3-assembled-output.)
//
// Attribution: the cycles between
// two consecutive instruction hooks go to the earlier PC (its own cycles, plus an
// interrupt entry that followed it), keyed by what was mapped there:
//   M:<pc>  main RAM (&0000-&7FFF)       A:<pc>   ANDY (&8000-&8FFF, ROMSEL bit 7)
//   B<n>:<pc> sideways RAM bank n (4-7)  HZ:<pc>  HAZEL (&C000-&DFFF, ACCCON Y)
//   MOS:<pc>  the MOS (&C000- without Y, &E000-) and any other paged ROM (DFS ...)
//
// --pagex: also count the page-crossing cycles, per PC and per scenario (a taken
// branch whose target is in another page than the next instruction; an
// abs,X / abs,Y / (zp),Y read whose indexed address is in another page than its
// base), into each scenario's "pagex" (total) and "pagex_pcs": the cycles that
// page alignment would save.
//
// Scenarios, as the gate's speed figure (mcompare.mjs flightRates) counts:
//   "flight"   the flight iterations: TT100 to the next TT100 when exactly one MLOOP
//              iteration lies between them; iterations = their number, so
//              cycles_per_iteration = 2e6 / (the gate's "all" it/s for this build)
//   "phase:<p>" the same split by the pilot's phase at the closing TT100 (approach:
//              the station approach with the big planet, combat, hyper: the hyperspace
//              countdown and the jump, escape, ...)
//   "other"    every other cycle from the first MLOOP on (docked screens, title,
//              launch, death); iterations = MLOOP iterations that are not flight ones
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { dirname, resolve } from "path";
import { fileURLToPath } from "url";

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, arr) => {
    if (v.startsWith("--")) acc.push([v.slice(2), arr[i + 1] && !arr[i + 1].startsWith("--") ? arr[i + 1] : true]);
    return acc;
}, []));
const { runElite, loadSyms, mapAt, mapOfLabel, CAND_DISC, CAND_SYMS, REF_DISC, REF_SYMS, WORK } = await import("./mlib.mjs");
const { makePilot, patchCommander } = await import("./mpilot.mjs");
const DISC = resolve(args.disc || CAND_DISC);
const SYMS = resolve(args.syms || CAND_SYMS);
const REF = REF_DISC, RSYMS = REF_SYMS;
const OUT = resolve(args.out || `${WORK}profile.json`);
const ITERS = +(args.iters || 10000);
const SEED = args.seed || "boot";
for (const f of [DISC, SYMS]) if (!existsSync(f)) throw new Error(`${f} missing (build first)`);

const sy = loadSyms(SYMS);
const t0 = Date.now();

// ---- the boot leftovers (mcompare.mjs --seed boot): the reference's state at TT170
let seedBoot = null;
if (SEED === "boot") {
    const rsy = loadSyms(RSYMS);
    const ref = await runElite({ disc: REF, syms: rsy, pilot: makePilot(), iters: 1, maxSecs: 200, patch: patchCommander });
    if (!ref.init) throw new Error("reference run did not reach TT170");
    seedBoot = (cregions, written, rb) => {
        const out = [];
        let o = 0;
        for (const [ra, n, name] of ref.regions) {
            const c = cregions.find(r => r[2] === name);
            if (c && c[1] === n) for (let i = 0; i < n; i++) if (!written.has(c[0] + i) && rb(c[0] + i) !== ref.init[o + i]) out.push([c[0] + i, [ref.init[o + i]]]);
            o += n;
        }
        return out;
    };
    console.log(`reference booted to TT170 for the seed (${((Date.now() - t0) / 1000).toFixed(1)} s)`);
}

// ---- the profile
const MAPS = ["M", "A", "B4", "B5", "B6", "B7", "HZ", "MOS"];
const NM = MAPS.length, SZ = NM * 65536;
const PAGEX = !!args.pagex;
const mk = () => ({ iterations: 0, total_cycles: 0, c: new Float64Array(SZ), px: PAGEX ? new Float64Array(SZ) : null, pxt: 0 });
// the 65C12's reads that take a cycle more when the indexed address crosses a page
const IDXX = new Set([0x1D, 0x3D, 0x5D, 0x7D, 0xBD, 0xBC, 0xDD, 0xFD, 0x3C, 0x1E, 0x3E, 0x5E, 0x7E]);
const IDXY = new Set([0x19, 0x39, 0x59, 0x79, 0xB9, 0xBE, 0xD9, 0xF9]);
const ZPY = new Set([0x11, 0x31, 0x51, 0x71, 0xB1, 0xD1, 0xF1]);
const BRANCH = new Set([0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0, 0x80]);
const curPX = PAGEX ? new Float64Array(SZ) : null;
let curPXT = 0, prevBranch = -1, prevBranchIdx = -1, prevTarget = -1;
const scen = { flight: mk(), other: mk() };
const cur = new Float64Array(SZ), stamp = new Uint32Array(SZ);
let touched = [], gen = 1, curTotal = 0;
const pilot = makePilot();
let cpu = null, installed = false, on = false, last = 0, lastIdx = -1;
let myIter = 0, prevTT = -1, sw = null, swm = "m";
const cyc = () => cpu.cycleSeconds * 2e6 + cpu.currentCycles;
const idxOf = pc => {
    if (pc < 0x8000) return pc;
    if (pc < 0xc000) {
        const r = cpu.romsel;
        if (pc < 0x9000 && (r & 0x80)) return 65536 + pc;
        const b = r & 15;
        return b >= 4 && b <= 7 ? (2 + b - 4) * 65536 + pc : 7 * 65536 + pc;
    }
    if (pc < 0xe000 && (cpu.acccon & 8)) return 6 * 65536 + pc;
    return 7 * 65536 + pc;
};
const close = dest => {
    const ds = [dest];
    for (const sc of ds) { sc.total_cycles += curTotal; sc.pxt += curPXT; }
    for (const k of touched) {
        const v = cur[k]; for (const sc of ds) sc.c[k] += v; cur[k] = 0;
        if (PAGEX) { for (const sc of ds) sc.px[k] += curPX[k]; curPX[k] = 0; }
    }
    touched = []; gen++; curTotal = 0; curPXT = 0;
};
const closeFlight = phase => {
    const ph = (scen["phase:" + phase] ||= mk());
    ph.iterations++; scen.flight.iterations++;
    ph.total_cycles += curTotal; scen.flight.total_cycles += curTotal;
    ph.pxt += curPXT; scen.flight.pxt += curPXT;
    for (const k of touched) {
        const v = cur[k]; ph.c[k] += v; scen.flight.c[k] += v; cur[k] = 0;
        if (PAGEX) { ph.px[k] += curPX[k]; scen.flight.px[k] += curPX[k]; curPX[k] = 0; }
    }
    touched = []; gen++; curTotal = 0; curPXT = 0;
};
const r = await runElite({
    disc: DISC, syms: sy, pilot, iters: ITERS, maxSecs: 4 * ITERS, patch: patchCommander, seedBoot,
    onIter: (i, s) => {
        myIter = i + 1;          // (mlib counts the MLOOP after this call)
        if (installed) return;
        installed = true; on = true;
        cpu = s._machine.processor;
        last = cyc();
        sw = sy.TT100; swm = mapOfLabel(sy, "TT100");     // (TT100 may be in bank 4)
        cpu.debugInstruction.add(pc => {
            const now = cyc();
            if (lastIdx >= 0) {
                const d = now - last;
                if (stamp[lastIdx] !== gen) { stamp[lastIdx] = gen; touched.push(lastIdx); }
                cur[lastIdx] += d; curTotal += d;
            }
            last = now;
            if (PAGEX) {
                // the branch just executed: taken into another page?
                if (prevBranch >= 0 && pc === prevTarget && ((prevBranch + 2) >> 8 & 255) !== (pc >> 8)) {
                    if (stamp[prevBranchIdx] !== gen) { stamp[prevBranchIdx] = gen; touched.push(prevBranchIdx); }
                    curPX[prevBranchIdx]++; curPXT++;
                }
                prevBranch = -1;
                const op = cpu.readmem(pc);
                let base = -1, ix = 0;
                if (IDXX.has(op)) { base = cpu.readmem((pc + 1) & 0xffff); ix = cpu.x; }
                else if (IDXY.has(op)) { base = cpu.readmem((pc + 1) & 0xffff); ix = cpu.y; }
                else if (ZPY.has(op)) { const z = cpu.readmem((pc + 1) & 0xffff); base = cpu.readmem(z); ix = cpu.y; }
                if (base >= 0 && base + ix > 255) {
                    const k = idxOf(pc);
                    if (stamp[k] !== gen) { stamp[k] = gen; touched.push(k); }
                    curPX[k]++; curPXT++;
                }
                if (BRANCH.has(op)) {
                    const o = cpu.readmem((pc + 1) & 0xffff);
                    prevBranch = pc; prevBranchIdx = idxOf(pc); prevTarget = (pc + 2 + (o < 128 ? o : o - 256)) & 0xffff;
                }
            }
            if (pc === sw && (swm === "m" || mapAt(cpu.romsel, pc) === swm)) {
                // a TT100 entry: close the interval since the previous one
                if (prevTT >= 0 && myIter === prevTT + 1) closeFlight(pilot.P.phase);
                else close(scen.other);
                prevTT = myIter;
            }
            lastIdx = idxOf(pc);
            return false;
        });
    },
});
close(scen.other);
scen.other.iterations = r.iters - scen.flight.iterations;
const out = { disc: DISC, syms: SYMS, iters: r.iters, tt100: r.tt100, seeded: r.seeded ? r.seeded.length : 0,
    error: r.error || null, emulated_secs: r.emuSecs, wall_secs: (Date.now() - t0) / 1000,
    pilot: { ...pilot.P.stats, systems: [...pilot.P.stats.systems] }, scenarios: {} };
for (const [n, sc] of Object.entries(scen)) {
    const pcs = [];
    for (let k = 0; k < SZ; k++) if (sc.c[k]) pcs.push([`${MAPS[k >> 16]}:${(k & 0xffff).toString(16)}`, Math.round(sc.c[k])]);
    pcs.sort((x, y) => y[1] - x[1]);
    out.scenarios[n] = { iterations: sc.iterations, total_cycles: sc.total_cycles,
        cycles_per_iteration: sc.iterations ? sc.total_cycles / sc.iterations : null,
        pcs: Object.fromEntries(pcs) };
    if (PAGEX) {
        const px = [];
        for (let k = 0; k < SZ; k++) if (sc.px[k]) px.push([`${MAPS[k >> 16]}:${(k & 0xffff).toString(16)}`, sc.px[k]]);
        px.sort((x, y) => y[1] - x[1]);
        out.scenarios[n].pagex = sc.pxt;
        out.scenarios[n].pagex_per_iteration = sc.iterations ? sc.pxt / sc.iterations : null;
        out.scenarios[n].pagex_pcs = Object.fromEntries(px);
    }
    console.log(`${n}: ${sc.iterations} iterations, ${sc.total_cycles.toFixed(0)} cycles` +
        (sc.iterations ? `, ${(sc.total_cycles / sc.iterations).toFixed(0)} cycles/iteration` +
            (n === "other" ? "" : `, ${(2e6 * sc.iterations / sc.total_cycles).toFixed(2)} it/s`) : "") +
        (PAGEX && sc.iterations ? `, page crossings ${(sc.pxt / sc.iterations).toFixed(0)} cycles/iteration` : ""));
}
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(out));
console.log(`-> ${OUT} (${r.iters} MLOOP iterations, ${r.tt100} TT100, emulated ${out.emulated_secs.toFixed(1)} s, wall ${out.wall_secs.toFixed(1)} s${r.error ? ", STOPPED: " + r.error : ""})`);
process.exit(r.error || r.iters !== ITERS ? 1 : 0);
