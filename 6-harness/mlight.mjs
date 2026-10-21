// Ship lighting check: what L_REC (gfx-light.asm) was given and
// what it wrote, for every ship recorded, so 2-build-files/lightcheck.py can
// recompute the levels with the model (2-build-files/lightramps.py) and
// compare; plus the light against the sun's true direction.
//
// node 6-harness/mlight.mjs --out file.json [--disc d] [--syms s] [--iters N]
//                         [--seedfile f] [--every K]
//
// Per recorded ship (in iterations i with i % K == 0, K = --every, default 1):
// { i, type, LL: [x, y, z], h: INWK+9..26 (the orientation vectors), pos:
// INWK+0..8 (the position), raw: XX2
// as copied, enc: the copy after L_REC, sun: K%+37..45 (slot 1), frin1 };
// and every colour f_col made for a polygon: "A,X,COLE,COLO,COL2,COL3": count.
import { runElite, loadSyms, CAND_DISC, CAND_SYMS, physRead } from "./mlib.mjs";
import { makePilot, patchCommander } from "./mpilot.mjs";
import { readFileSync, writeFileSync } from "fs";
const a = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, arr) => { if (v.startsWith("--")) acc.push([v.slice(2), arr[i + 1] && !arr[i + 1].startsWith("--") ? arr[i + 1] : true]); return acc; }, []));
const sy = loadSyms(a.syms || CAND_SYMS);
const seed = a.seedfile ? JSON.parse(readFileSync(a.seedfile, "utf8")) : null;
const EVERY = +(a.every || 1), ITERS = +(a.iters || 3000);
const out = []; let cur = -1, inst = false, pend = [], colq = null;
const cols = {};
await runElite({ disc: a.disc || CAND_DISC, syms: sy, pilot: makePilot(), iters: ITERS, patch: patchCommander, seed,
    onIter: (i, s, r) => { cur = i; const cpu = r.cpu; if (inst) return; inst = true;
        const m = ad => cpu.ramRomOs[ad >= 0xc000 && ad < 0xe000 ? ad - 0xc000 + 0x9000 : ad];   // (HAZEL's physical place)
        const b6 = ad => physRead(cpu, 6, ad);
        cpu.debugInstruction.add(pc => {
            if (pc === sy.L_REC && cur % EVERY === 0 && m(sy.GNF)) {
                const k = b6(sy.F_NSHIP), at = b6(sy.F_SPL + k) | b6(sy.F_SPH + k) << 8, nf = m(sy.GNF);
                pend.push({ i: cur, type: m(sy.GTYPE), LL: [0, 1, 2].map(j => b6(sy.LLT + j)),
                    h: Array.from({ length: 18 }, (_, j) => m(sy.INWK + 9 + j)), pos: Array.from({ length: 9 }, (_, j) => m(sy.INWK + j)),
                    raw: Array.from({ length: nf }, (_, j) => b6(at + j)), at, nf,
                    sun: Array.from({ length: 9 }, (_, j) => m(sy["K%"] + 37 + j)), frin1: m(sy.FRIN + 1) });
            } else if (pc === sy.f_col && cpu.romsel === 6) {
                colq = [cpu.a, cpu.x];
            } else if (pc === sy.T_POLY && colq) {
                const c = [m(0x06), m(0x07), m(sy.R_COL2), m(sy.R_COL3)];   // R_COLE, R_COLO (zero page)
                cols[colq.concat(c).join(",")] = (cols[colq.concat(c).join(",")] || 0) + 1;
                colq = null;
            } else if (pc === sy.F_FRAME && cpu.romsel === 6 && pend.length) {
                for (const p of pend) { p.enc = Array.from({ length: p.nf }, (_, j) => b6(p.at + j)); out.push(p); }
                pend = [];
            }
            return false;
        });
    } });
writeFileSync(a.out, JSON.stringify({ ships: out, cols }));
console.log(`${out.length} ship records written to ${a.out}`);
