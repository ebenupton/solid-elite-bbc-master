// The frames a build draws over the gate's run, whole, for fbdiff.py to
// compare pixel by pixel with another build's (a change that is meant to
// alter the picture: how many frames, rows and pixels, and where).
//
// node 6-harness/mfbdump.mjs --out FILE [--disc d] [--syms s] [--iters N]
//                           [--seedfile f]
//
// At every entry to F_FRAME's f_reset in bank 6 (as mfbcmp.mjs --frames:
// the end of every rendered frame, keyed iteration.n), the buffer the frame
// drew (main RAM's &4000-&6FFF or shadow RAM's: the one that differs from
// its last record; main RAM's if neither does) is appended to FILE, 12,288
// bytes, and FILE.json lists the frames in order with their buffer (0 main,
// 1 shadow) and the planet's place and radius (K3, K4, K: as the last
// PF_HOOK call of the iteration had them, or null).
import { runElite, loadSyms, CAND_SYMS, CAND_DISC } from "./mlib.mjs";
import { makePilot, patchCommander } from "./mpilot.mjs";
import { readFileSync, writeFileSync, openSync, writeSync, closeSync } from "fs";
import { parseArgs } from "./args.mjs";
const a = parseArgs({ disc: "value", syms: "value", iters: "value", out: "value", seedfile: "value" });
if (!a.out) { console.error("--out FILE needed"); process.exit(2); }
const sy = loadSyms(a.syms || CAND_SYMS);
const seed = a.seedfile ? JSON.parse(readFileSync(a.seedfile, "utf8")) : null;
const FR = sy.f_reset;
const fd = openSync(a.out, "w");
const meta = [];
let cur = -1, nIn = 0, inst = false, seen = false, planet = null, pIter = -1;
const last = [null, null];
const eq = (x, y) => { if (!y) return false; for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return false; return true; };
await runElite({ disc: a.disc || CAND_DISC, syms: sy, pilot: makePilot(), iters: +(a.iters || 10000), patch: patchCommander, seed, maxSecs: 40000,
    onIter: (i, s, r) => { if (i !== cur) nIn = 0; cur = i; const cpu = r.cpu, m = cpu.ramRomOs; if (inst) return; inst = true;
        cpu.debugInstruction.add(pc => {
            if (pc === sy.PF_HOOK && (cpu.romsel & 15) === 7) {
                planet = m[sy.K + 1] ? null : [m[sy.K3] | m[sy.K3 + 1] << 8, m[sy.K4] | m[sy.K4 + 1] << 8, m[sy.K]];
                pIter = cur;
            }
            // (jsbeeb calls no hook for a slice's first instruction: f_reset's
            // second, after its LDA #0, stands in for a missed first)
            if ((pc === FR || pc === FR + 2) && (cpu.romsel & 0x8f) === 6) {
                if (pc === FR + 2 && seen) { seen = false; return false; }
                seen = pc === FR;
                const b0 = m.subarray(0x4000, 0x7000), b1 = m.subarray(0xc000, 0xf000);
                const k = !eq(b0, last[0]) ? 0 : !eq(b1, last[1]) ? 1 : 0;
                const buf = k ? b1 : b0;
                last[k] = Uint8Array.from(buf);
                writeSync(fd, buf);
                meta.push({ f: `${cur}.${nIn++}`, b: k, planet: pIter === cur ? planet : null });
            }
            return false;
        }); } });
closeSync(fd);
writeFileSync(a.out + ".json", JSON.stringify(meta));
console.log(`${meta.length} frames -> ${a.out}`);
process.exit(0);
