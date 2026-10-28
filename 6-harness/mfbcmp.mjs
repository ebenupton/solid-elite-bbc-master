// Renderer regression check: the screen buffers a build's frames leave, as
// hashes, for comparison between two builds whose game state is identical
// (a renderer optimisation must draw exactly the same pixels).
//
// node 6-harness/mfbcmp.mjs --out file.json [--disc d] [--syms s] [--iters N]
//                         [--every K] [--seedfile f] [--frames] [--mask r,c0,c1]
// node 6-harness/mfbcmp.mjs --cmp a.json b.json
//
// At the end of each K-th iteration's frame (hframe's return from G_FRAME),
// hashes main RAM's and shadow RAM's &4000-&6FFF (both buffers) and records
// them by iteration. --cmp lists the iterations whose buffers differ.
// --frames: instead, at every entry to F_FRAME's f_reset in bank 6 (the end
// of every rendered frame, and every non-space-view F_FRAME call: each
// main-loop iteration, the title, the briefing, the hangar, the death
// screen), keyed "iteration.n" (n: the call within the iteration); --every
// is then ignored.
// --dump N also writes iteration N's two buffers (main RAM's, then shadow RAM's
// &4000-&6FFF) to <out>.N.raw, and bank 6 to <out>.N.b6, to see where two
// builds differ.
import { runElite, loadSyms, physRead, CAND_SYMS, CAND_DISC } from "./mlib.mjs";
import { makePilot, patchCommander } from "./mpilot.mjs";
import { readFileSync, writeFileSync } from "fs";
import { createHash } from "crypto";
const a = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, arr) => { if (v.startsWith("--")) acc.push([v.slice(2), arr[i + 1] && !arr[i + 1].startsWith("--") ? arr[i + 1] : true]); return acc; }, []));
if (a.cmp) {
    const A = JSON.parse(readFileSync(a.cmp, "utf8")), B = JSON.parse(readFileSync(process.argv[process.argv.indexOf(a.cmp) + 1], "utf8"));
    const diff = Object.keys(A).filter(k => B[k] !== undefined && A[k] !== B[k]);
    const outside = diff.filter(k => A[k].includes("/") && B[k].includes("/") && A[k].split("/")[1] !== B[k].split("/")[1]);
    const masked = A[Object.keys(A)[0]]?.includes("/");
    console.log(`${Object.keys(A).length} frames compared, ${diff.length} differ${diff.length ? ": " + diff.slice(0, 30).join(" ") : ""}` +
        (masked ? `; ${outside.length} differ outside the masked cells${outside.length ? ": " + outside.slice(0, 30).join(" ") : ""}` : ""));
    process.exit((masked ? outside.length : diff.length) ? 1 : 0);
}
const sy = loadSyms(a.syms || CAND_SYMS);
const seed = a.seedfile ? JSON.parse(readFileSync(a.seedfile, "utf8")) : null;
const EVERY = +(a.every || 5), ITERS = +(a.iters || 3000);
const H = sy.hframe + 7;   // hframe: PHP PHA PHX PHY JSR G_FRAME | PLY
const FR = sy.f_reset;     // (bank 6: tested with ROMSEL)
const res = {}; let cur = -1, inst = false, nIn = 0, seen = false;
// --mask row,col0,col1: each frame's hash is followed by "/" and a second one
// with those text cells (both buffers) blanked, to show that two builds differ
// only there (--cmp then also counts the frames equal outside the cells)
const MASK = a.mask ? String(a.mask).split(",").map(Number) : null;
const maskCells = (buf, [r, c0, c1]) => { const b = Buffer.from(buf); for (const base of [0, 0x3000]) for (let c = c0; c <= c1; c++) b.fill(0, base + r * 512 + c * 16, base + r * 512 + c * 16 + 16); return b; };
const hashBufs = cpu => {
    const both = Buffer.concat([cpu.ramRomOs.subarray(0x4000, 0x7000), cpu.ramRomOs.subarray(0xc000, 0xf000)]);
    const h = b => createHash("sha1").update(b).digest("hex").slice(0, 16);
    return MASK ? h(both) + "/" + h(maskCells(both, MASK)) : h(both);
};
await runElite({ disc: a.disc || CAND_DISC, syms: sy, pilot: makePilot(), iters: ITERS, patch: patchCommander, seed,
    onIter: (i, s, r) => { if (i !== cur) nIn = 0; cur = i; const cpu = r.cpu; if (inst) return; inst = true;
        cpu.debugInstruction.add(pc => {
            if (a.frames) {
                // (jsbeeb calls no hook for a slice's first instruction: f_reset's
                // second, after its LDA #0, stands in for a missed first)
                if ((pc === FR || pc === FR + 2) && (cpu.romsel & 0x8f) === 6) {
                    if (pc === FR + 2 && seen) seen = false;
                    else { seen = pc === FR; res[`${cur}.${nIn++}`] = hashBufs(cpu); }
                }
                return false;
            }
            if (pc === H && cur % EVERY === 0 && res[cur] === undefined) {
                const h = createHash("sha1");
                h.update(cpu.ramRomOs.subarray(0x4000, 0x7000)); h.update(cpu.ramRomOs.subarray(0xc000, 0xf000));
                res[cur] = h.digest("hex").slice(0, 16);
                if (+a.dump === cur) {
                    writeFileSync(`${a.out}.${cur}.raw`, Buffer.concat([cpu.ramRomOs.subarray(0x4000, 0x7000), cpu.ramRomOs.subarray(0xc000, 0xf000)]));
                    writeFileSync(`${a.out}.${cur}.b6`, Buffer.from(Array.from({ length: 0x4000 }, (_, j) => physRead(cpu, 6, 0x8000 + j))));
                }
            }
            return false;
        }); } });
writeFileSync(a.out, JSON.stringify(res));
console.log(`${Object.keys(res).length} frames hashed`);
