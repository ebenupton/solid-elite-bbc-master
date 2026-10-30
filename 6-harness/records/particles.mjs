// particles.mjs: the explosion particles each main-loop iteration draws, on
// the released SNG47 and on a build, flown by the gate's pilot (as mcompare,
// the boot leftovers seeded from the reference), compared iteration by
// iteration.
//
//   node 6-harness/records/particles.mjs --cand DISC --csyms SYMS [--iters 10000]
//        [--old] [--out FILE.json]
//
// SNG47: the PIXEL calls of PTCLS's draw pass (DOEXP falling into PTCLS; its
// erase pass, a JSR from DOEXP, draws the last iteration's particles again to
// remove them). The build: the particles its frame plots (F_PDOT, the frame's
// PTCLS), or with --old a build that records particles in the dot list (F_DOT:
// those it recorded, the rest dropped). Each particle is (x, y, ZZ >= 80);
// prints the iterations whose particles differ, and the totals.
import { writeFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
const HERE = dirname(fileURLToPath(import.meta.url)), TREE = resolve(`${HERE}/../..`);
const argv = process.argv.slice(2), arg = (n, d) => { const i = argv.indexOf("--" + n); return i >= 0 ? argv[i + 1] : d; };
const { loadSyms, mapAt, mapOfLabel, physRead, runElite } = await import(`${TREE}/6-harness/mlib.mjs`);
const { makePilot, patchCommander } = await import(`${TREE}/6-harness/mpilot.mjs`);
const ITERS = +arg("iters", 10000), OLD = argv.includes("--old");
const rsy = loadSyms(`${TREE}/4-reference-binaries/sng47/symbols.txt`), csy = loadSyms(arg("csyms"));
const lab = (sy, n) => { if (sy[n] === undefined) throw new Error("no " + n); return [sy[n], mapOfLabel(sy, n)]; };

async function run(disc, sy, kind, seedBoot) {
    const per = [];
    let cur = null, installed = false, drawPass = false;
    const install = cpu => {
        const is = (pc, [ad, m]) => pc === ad && (m === "m" || mapAt(cpu.romsel, pc) === m);
        const add = (x, y) => cur.push([x, y, cpu.ramRomOs[sy.ZZ] >= 80 ? 1 : 0]);
        if (kind === "ref") {
            const PT = lab(sy, "PTCLS"), PX = lab(sy, "PIXEL"), DX = sy.DOEXP;
            let s0 = -1;
            cpu.debugInstruction.add(pc => {
                if (s0 >= 0 && cpu.s >= s0 + 2) { s0 = -1; drawPass = false; }
                if (is(pc, PT)) { const ret = (cpu.ramRomOs[0x101 + cpu.s] | cpu.ramRomOs[0x102 + cpu.s] << 8) + 1; drawPass = !(ret > DX && ret < sy.PTCLS); s0 = cpu.s; }
                else if (is(pc, PX) && drawPass && cur && cpu.ramRomOs[sy.QQ11] === 0) add(cpu.x, cpu.a);
                return false;
            });
        } else if (kind === "old") {
            const FD = [sy.F_DOT, 6];
            cpu.debugInstruction.add(pc => {
                if (pc === FD[0] && (cpu.romsel & 0x8f) === 6 && cur && physRead(cpu, 6, sy.F_NDOT) < 64) add(cpu.x, cpu.a);
                return false;
            });
        } else {
            const TP = [sy.F_PDOT, 6];
            // (jsbeeb calls no hook for an execute slice's first instruction:
            // F_PDOT's second, TAY's next, stands in for a missed first; an
            // interrupt between the two is not a second particle)
            let seen = false;
            cpu.debugInstruction.add(pc => {
                if ((cpu.romsel & 0x8f) !== 6 || !cur) return false;
                if (pc === TP[0]) { add(cpu.x, cpu.a); seen = true; }
                else if (pc === TP[0] + 1) { if (!seen) add(cpu.x, cpu.a); seen = false; }
                return false;
            });
        }
    };
    const res = await runElite({ disc, syms: sy, pilot: makePilot(), iters: ITERS, maxSecs: 4 * ITERS, patch: patchCommander, seedBoot,
        onIter: (i, s) => { if (!installed) { installed = true; install(s._machine.processor); } if (cur) per[i - 1] = cur; cur = []; } });
    return { per, res };
}
const ref = await run(`${TREE}/4-reference-binaries/sng47/elite-master-sng47.ssd`, rsy, "ref");
const seedBoot = (cregions, written, rb) => {
    const out = []; let o = 0;
    for (const [, n, name] of ref.res.regions) {
        const c = cregions.find(r => r[2] === name);
        if (c && c[1] === n) for (let i = 0; i < n; i++) if (!written.has(c[0] + i) && rb(c[0] + i) !== ref.res.init[o + i]) out.push([c[0] + i, [ref.res.init[o + i]]]);
        o += n;
    }
    return out;
};
const cand = await run(arg("cand"), csy, OLD ? "old" : "new", seedBoot);
let iters = 0, same = 0, differ = [], nRef = 0, nCand = 0, maxRef = 0;
for (let i = 0; i < Math.max(ref.per.length, cand.per.length); i++) {
    const a = ref.per[i] || [], b = cand.per[i] || [];
    if (!a.length && !b.length) continue;
    iters++; nRef += a.length; nCand += b.length; maxRef = Math.max(maxRef, a.length);
    if (JSON.stringify(a) === JSON.stringify(b)) same++; else differ.push(`${i}:${a.length}/${b.length}`);
}
console.log(`iterations with particles: ${iters}; identical ${same}; differ ${differ.length}${differ.length ? " (iteration:ref/cand) " + differ.slice(0, 40).join(" ") : ""}`);
console.log(`particles: SNG47 ${nRef}, build ${nCand}; most in one iteration (SNG47) ${maxRef}`);
if (arg("out")) writeFileSync(arg("out"), JSON.stringify({ ref: ref.per, cand: cand.per }));
console.log(differ.length ? "PARTICLES DIFFER" : "PARTICLES MATCH");
process.exit(0);
