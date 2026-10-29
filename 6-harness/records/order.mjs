// order.mjs: does every frame draw each ship it recorded exactly once? And of
// the ships handed to f_ship, how many it projects (fpj0, past FC_MINVIS's
// test) and how many it draws (fsh_nf0, past f_behind's: not hidden behind the
// planet or the moon). Flies
// the gate's pilot (as mcompare, the boot leftovers seeded from the
// reference) for --iters iterations and, per frame, compares the ships
// f_ships hands to f_ship (its A) with 0 .. F_NSHIP - 1.
//
//   node 6-harness/records/order.mjs --cand DISC --csyms SYMS [--iters 10000] [--noseed]
//
// (--noseed: no seeding, as 6-harness/mfbcmp.mjs flies the pilot)
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
const HERE = dirname(fileURLToPath(import.meta.url)), TREE = resolve(`${HERE}/../..`);
const argv = process.argv.slice(2), arg = (n, d) => { const i = argv.indexOf("--" + n); return i >= 0 ? argv[i + 1] : d; };
const { loadSyms, physRead, runElite } = await import(`${TREE}/6-harness/mlib.mjs`);
const { makePilot, patchCommander } = await import(`${TREE}/6-harness/mpilot.mjs`);
const sy = loadSyms(arg("csyms")), rsy = loadSyms(`${TREE}/4-reference-binaries/sng47/symbols.txt`);
const ref = await runElite({ disc: `${TREE}/4-reference-binaries/sng47/elite-master-sng47.ssd`, syms: rsy, pilot: makePilot(), iters: 1, maxSecs: 200, patch: patchCommander });
const seedBoot = (cregions, written, rb) => { const out = []; let o = 0; for (const [, n, name] of ref.regions) { const c = cregions.find(r => r[2] === name); if (c && c[1] === n) for (let i = 0; i < n; i++) if (!written.has(c[0] + i) && rb(c[0] + i) !== ref.init[o + i]) out.push([c[0] + i, [ref.init[o + i]]]); o += n; } return out; };
let inst = false, it = 0, cur = null, frames = 0, multi = 0, bad = 0, nShip = 0, nProj = 0, nDrawn = 0;
const ex = [], badIt = [];
const at6 = (cpu, pc, n) => pc === sy[n] && (cpu.romsel & 0x8f) === 6;
const ITERS = +arg("iters", 10000);
await runElite({ disc: arg("cand"), syms: sy, pilot: makePilot(), iters: ITERS, maxSecs: 4 * ITERS, patch: patchCommander, seedBoot: argv.includes("--noseed") ? undefined : seedBoot,
    onIter: (i, s) => { it = i; if (inst) return; inst = true; const cpu = s._machine.processor;
        let last = -1;
        cpu.debugInstruction.add(pc => {
            const was = last; last = pc;
            if (at6(cpu, pc, "fpj0")) nProj++;
            else if (at6(cpu, pc, "fsh_nf0")) nDrawn++;
            if (at6(cpu, pc, "f_ships")) cur = { n: physRead(cpu, 6, sy.F_NSHIP), got: [] };
            // (jsbeeb calls no hook for an execute slice's first instruction:
            // f_ship's second, after its TAX, stands in for a missed first)
            else if (cur && (at6(cpu, pc, "f_ship") || (pc === sy.f_ship + 1 && (cpu.romsel & 0x8f) === 6 && was !== sy.f_ship))) cur.got.push(cpu.a);
            else if (cur && at6(cpu, pc, "f_reset")) {
                frames++; if (cur.n > 1) multi++;
                nShip += cur.got.length;
                const want = Array.from({ length: cur.n }, (_, k) => k).join(), got = [...cur.got].sort((x, y) => x - y).join();
                if (want !== got) { bad++; badIt.push(it); if (ex.length < 10) ex.push(`${it}: ${cur.n} recorded, drawn ${cur.got.join(",")}`); }
                cur = null;
            }
            return false;
        }); } });
console.log(`frames ${frames}, with more than one ship ${multi}, not drawing each ship once ${bad}${ex.length ? ": " + ex.join("; ") : ""}`);
if (sy.fpj0 !== undefined) console.log(`ships handed to f_ship ${nShip}, projected ${nProj}, drawn ${nDrawn}`);
if (argv.includes("--list")) console.log("iterations: " + badIt.join(" "));
process.exit(0);
