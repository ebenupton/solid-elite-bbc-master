// Per-iteration times and scenes of a build over the gate's run, and the
// circle engine's cost in each, for the speed by scene (6-harness/scenes.py).
//
// node 6-harness/mscenes.mjs --out FILE.json [--disc d] [--syms s]
//                            [--iters 10000] [--seedfile f]
//
// The run is the gate's (verify.sh's mcompare.mjs): mpilot.mjs's pilot and
// commander patch, and the boot leftovers seeded from --seedfile (the gate's
// 6-harness/work/verify/compare/seeded.json), so the iterations line up with
// the gate's and with another build's run. At each MLOOP iteration, a row:
// the emulated time (t), the flight iteration count (tt: TT100s), QQ11, VIEW,
// the type in slot 1 (f1: FRIN+1, the station or the sun), the high parts of
// the planet's (slot 0, p) and slot 1's (s1) coordinates (bytes 1 and 2, 4
// and 5, 7 and 8 of the ship data block: x, y, z as hi + 256 * the sign
// byte's low 7 bits, and z's sign, zs), the number of other ships and the
// system (QQ0, QQ1).
//
// And each call of the planet's detail in the iteration (pf: PF_HOOK, bank
// 7, from G_PFHOOK, entry to return): the radius K (r), its class (PF_CLS
// after, bit 7: the detail made), the records made (n), its cycles (c: all,
// interrupts included; irq: those outside bank 7; div: pm_fdiv and
// pfd_norm; mul: pm_mul16, pm_mul8 and pc_mul; sqrt: pm_isqrt; the rest is
// c - irq - div - mul - sqrt), a hash of its inputs (h: TYPE, K, K3, K4,
// nosev, roofv and sidev, QQ2) and of its outputs (o: PF_CLS, PC_N, pc_inv
// and the records PCB[0 .. 24 PC_N)), from which scenes.py counts how often
// the inputs or the records are those of the previous call (memoisation).
import { writeFileSync, readFileSync } from "fs";
import { createHash } from "crypto";
import { runElite, loadSyms, mapOfLabel, physRead, CAND_DISC, CAND_SYMS } from "./mlib.mjs";
import { makePilot, patchCommander } from "./mpilot.mjs";
import { parseArgs } from "./args.mjs";
const args = parseArgs({ disc: "value", syms: "value", iters: "value", out: "value", seedfile: "value" });
if (!args.out) { console.error("--out FILE.json needed"); process.exit(2); }
const sy = loadSyms(args.syms || CAND_SYMS);
const seed = args.seedfile ? JSON.parse(readFileSync(args.seedfile, "utf8")) : null;
const rows = [];
// bank 7's labels, for grouping the detail's cycles by routine
const b7 = Object.keys(sy).filter(k => mapOfLabel(sy, k) === 7).map(k => [sy[k], k]).sort((a, b) => a[0] - b[0]);
const GROUP = { div: /^(pm_fdiv|pfd|pfn)/, mul: /^(pm_mul|pmm_add|pmq|pc_mul)/, sqrt: /^(pm_isqrt|pis)/ };
const grp = new Uint8Array(0x4000);         // 0 rest, 1 div, 2 mul, 3 sqrt
for (let i = 0; i < b7.length; i++) {
    const [a, n] = b7[i], e = i + 1 < b7.length ? b7[i + 1][0] : 0xc000;
    const g = GROUP.div.test(n) ? 1 : GROUP.mul.test(n) ? 2 : GROUP.sqrt.test(n) ? 3 : 0;
    if (a >= 0x8000 && a < 0xc000) grp.fill(g, a - 0x8000, Math.min(e, 0xc000) - 0x8000);
}
const GN = ["rest", "div", "mul", "sqrt"];
const hash = b => createHash("sha1").update(Buffer.from(b)).digest("hex").slice(0, 12);
let inst = false, call = null;
const r = await runElite({ disc: args.disc || CAND_DISC, syms: sy, pilot: makePilot(), iters: +(args.iters || 10000), maxSecs: 40000, patch: patchCommander, seed,
    onIter: (i, s, res) => {
        const cpu = res.cpu, m = cpu.ramRomOs, K = sy["K%"];
        const blk = n => { const a = K + 37 * n; return { x: m[a + 1] | ((m[a + 2] & 127) << 8), y: m[a + 4] | ((m[a + 5] & 127) << 8), z: m[a + 7] | ((m[a + 8] & 127) << 8), zs: m[a + 8] >> 7 }; };
        let ships = 0; for (let k = 2; k < 12; k++) if (m[sy.FRIN + k]) ships++;
        rows.push({ i, t: res.iterTimes[res.iterTimes.length - 1], tt: res.tt100AtIter[res.tt100AtIter.length - 1], qq11: m[sy.QQ11], view: m[sy.VIEW], f1: m[sy.FRIN + 1], p: blk(0), s1: blk(1), ships, sys: [m[sy.QQ0], m[sy.QQ1]], pf: [] });
        if (inst) return;
        inst = true;
        const cyc = () => cpu.cycleSeconds * 2e6 + cpu.currentCycles;
        let last = 0, lastG = -1;
        cpu.debugInstruction.add(pc => {
            if (call) {
                const now = cyc();
                if (lastG >= 0) call.g[lastG] += now - last;
                last = now;
                if (pc === call.ret && cpu.s === call.sp) {
                    const n = physRead(cpu, 7, sy.PC_N);
                    const out = [physRead(cpu, 7, sy.PF_CLS), n, physRead(cpu, 7, sy.pc_inv)];
                    for (let j = 0; j < 24 * n; j++) out.push(physRead(cpu, 7, sy.PCB + j));
                    const g = call.g, c = Math.round(now - call.t0);
                    rows[rows.length - 1].pf.push({ r: call.r, cls: out[0], n, c, irq: Math.round(g[4]), div: Math.round(g[1]), mul: Math.round(g[2]), sqrt: Math.round(g[3]), h: call.h, o: hash(out) });
                    call = null;
                } else lastG = pc >= 0x8000 && pc < 0xc000 && (cpu.romsel & 15) === 7 ? grp[pc - 0x8000] : 4;
            } else if (pc === sy.PF_HOOK && (cpu.romsel & 15) === 7) {
                const inp = [m[sy.TYPE], m[sy.K], m[sy.K + 1], m[sy.K3], m[sy.K3 + 1], m[sy.K4], m[sy.K4 + 1]];
                for (let j = 9; j < 27; j++) inp.push(m[sy.INWK + j]);
                for (let j = 0; j < 6; j++) inp.push(m[sy.QQ2 + j]);
                const ret = ((m[0x101 + cpu.s] | m[0x102 + cpu.s] << 8) + 1) & 0xffff;
                call = { t0: cyc(), r: m[sy.K + 1] ? 256 : m[sy.K], h: hash(inp), ret, sp: (cpu.s + 2) & 255, g: [0, 0, 0, 0, 0] };
                last = call.t0; lastG = 0;
            }
            return false;
        });
    } });
writeFileSync(args.out, JSON.stringify(rows));
console.log(`${r.iters} iterations${r.error ? ", stopped: " + r.error : ""} -> ${args.out}`);
process.exit(0);
