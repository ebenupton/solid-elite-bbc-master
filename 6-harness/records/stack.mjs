// stack.mjs: how close the stack comes to the projected vertices. The frame
// runs LL9's part 6 on (T_GAME, GPRJ set), which puts each visible vertex's
// screen coordinates in XX3, page 1 from &0100 up, under the stack; this
// watches, while GPRJ is set, the lowest S (interrupts included) and the
// highest byte of page 1 written below the stack (XX3), and prints both, the
// margin between them and the ship type whose vertices came closest.
//
//   node 6-harness/records/stack.mjs --cand DISC --csyms SYMS [--iters 10000] [--title N]
//
// Flies the gate's pilot (boot leftovers seeded as mcompare does) for
// --iters iterations; --title N instead waits on the title screen (its
// rotating ship) for N main-loop polls of the title's loop.
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
const HERE = dirname(fileURLToPath(import.meta.url)), TREE = resolve(`${HERE}/../..`);
const argv = process.argv.slice(2), arg = (n, d) => { const i = argv.indexOf("--" + n); return i >= 0 ? argv[i + 1] : d; };
const { loadSyms, physRead, runElite } = await import(`${TREE}/6-harness/mlib.mjs`);
const { makePilot, patchCommander } = await import(`${TREE}/6-harness/mpilot.mjs`);
const sy = loadSyms(arg("csyms")), rsy = loadSyms(`${TREE}/4-reference-binaries/sng47/symbols.txt`);
const ref = await runElite({ disc: `${TREE}/4-reference-binaries/sng47/elite-master-sng47.ssd`, syms: rsy, pilot: makePilot(), iters: 1, maxSecs: 200, patch: patchCommander });
const seedBoot = (cregions, written, rb) => { const out = []; let o = 0; for (const [, n, name] of ref.regions) { const c = cregions.find(r => r[2] === name); if (c && c[1] === n) for (let i = 0; i < n; i++) if (!written.has(c[0] + i) && rb(c[0] + i) !== ref.init[o + i]) out.push([c[0] + i, [ref.init[o + i]]]); o += n; } return out; };
export function watch(cpu, sy, R) {
    cpu.debugInstruction.add(() => { if (cpu.ramRomOs[sy.GPRJ] & 0x80) { if (cpu.s < R.minS) R.minS = cpu.s; const p = R.phaseOf ? R.phaseOf() : "all"; if (!(p in R.phase) || cpu.s < R.phase[p]) R.phase[p] = cpu.s; } return false; });
    cpu.debugWrite.add(a => {
        if (!(cpu.ramRomOs[sy.GPRJ] & 0x80) || a < 0x100 || a > 0x1ff) return false;
        if (a - 0x100 < cpu.s && a > R.maxX) { R.maxX = a; R.type = physRead(cpu, 6, sy.F_STYP + physRead(cpu, 6, sy.f_si)); }
        return false;
    });
}
const R = { minS: 0xff, maxX: 0x100, type: 0, phase: {} };
const ITERS = +arg("iters", 10000);
let inst = false;
const pilot = makePilot();
await runElite({ disc: arg("cand"), syms: sy, pilot, iters: ITERS, maxSecs: 4 * ITERS, patch: patchCommander, seedBoot,
    onIter: (i, s) => { if (!inst) { inst = true; R.phaseOf = () => pilot.P.phase; watch(s._machine.processor, sy, R); } } });
console.log(`lowest S while the frame projects: &${R.minS.toString(16)} (stack from &${(0x101 + R.minS).toString(16)}); highest XX3 byte written: &${R.maxX.toString(16)} (type ${R.type}); margin ${0x101 + R.minS - R.maxX - 1} bytes`);
console.log("lowest S by the pilot's phase: " + Object.entries(R.phase).map(([k, v]) => `${k} &${v.toString(16)}`).join(", "));
process.exit(0);
