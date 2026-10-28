// Where the sun near the planet costs time: fly the gate's pilot (as
// 6-harness/verify.sh's mcompare.mjs run) and, from iteration FROM to TO, record
// per frame: S_SUN's cycles (gfx-ssun.asm, from its entry to F_FRAME's), the
// disc layer (f_discs), the secondary disc (f_disc2), the lens flare's step
// (f_flt to f_text2) and the whole frame (F_FRAME to the flip's queue), with
// GSUNON, GSUNR, the planet's radius, which disc is secondary (f_sec) and
// VIEW. A build without S_SUN (the baseline) is measured the same way.
//
// node 6-harness/msunprof.mjs [--tree T] [--from 4700] [--to 5300] [--out file.json]
//      [--seedfile 6-harness/work/verify/compare/seeded.json] (the gate's boot leftovers)
import { runElite, loadSyms, physRead, mapOfLabel, ROOT } from "./mlib.mjs";
import { makePilot, patchCommander } from "./mpilot.mjs";
import { readFileSync, writeFileSync } from "fs";
const a = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, arr) => { if (v.startsWith("--")) acc.push([v.slice(2), arr[i + 1] && !arr[i + 1].startsWith("--") ? arr[i + 1] : true]); return acc; }, []));
const TREE = a.tree || ROOT.replace(/\/$/, ""), FROM = +(a.from || 4700), TO = +(a.to || 5300);
const sy = loadSyms(`${TREE}/3-assembled-output/symbols.txt`);
const lst = readFileSync(`${TREE}/3-assembled-output/compile.txt`, "utf8").split("\n");
function jsrIn(target, after) {
    const t = target.toString(16).toUpperCase().padStart(4, "0");
    for (const l of lst) {
        const m = l.match(/^\s+([0-9A-F]{4})\s+20 ([0-9A-F]{2}) ([0-9A-F]{2})\s+JSR &([0-9A-F]{4})/);
        if (m && m[4] === t && parseInt(m[1], 16) > sy.F_FRAME && parseInt(m[1], 16) < sy.F_FRAME + 0x200) return parseInt(m[1], 16) + 3;
    }
    throw new Error("JSR not found");
}
const AFT = { discs: jsrIn(sy.f_discs), disc2: jsrIn(sy.f_disc2), flt: jsrIn(sy.f_flt), stars: sy.ff_stars9 };
const M6 = mapOfLabel(sy, "F_PLR");
const pilot = makePilot();
const seed = a.seedfile ? JSON.parse(readFileSync(a.seedfile, "utf8")) : null;
const frames = [];
let cur = -1, armed = false;
const res = await runElite({ disc: `${TREE}/5-compiled-game-discs/elite-master-sng47.ssd`, syms: sy, pilot, iters: TO + 1, patch: patchCommander, seed,
    onIter: (i, s, r) => {
        cur = i;
        if (armed) return;
        armed = true;
        const cpu = r.cpu;
        const cyc = () => (cpu.cycleSeconds + cpu.currentCycles / 2e6) * 2e6;
        const b6 = x => physRead(cpu, M6, x);
        let t = {}, f = null;
        cpu.debugInstruction.add(pc => {
            if (cur < FROM || cur > TO) return false;
            const bank = cpu.romsel & 15;
            if (bank === ((sy.__bank.S_SUN ?? 7) & 15) && sy.S_SUN !== undefined && pc === sy.S_SUN) t.ss = cyc();
            else if (bank === 6) {
                if (pc === sy.F_FRAME) { f = { i: cur, ss: t.ss ? Math.round(cyc() - t.ss) : 0 }; t = { ff: cyc() }; }
                else if (!f) return false;
                else if (pc === sy.f_discs) t.d1 = cyc();
                else if (pc === AFT.discs) { f.discs = Math.round(cyc() - t.d1); t.d2 = cyc(); }
                else if (pc === AFT.disc2) f.disc2 = Math.round(cyc() - t.d2);
                else if (pc === sy.f_flt) t.fl = cyc();
                else if (pc === AFT.flt) f.flt = Math.round(cyc() - t.fl);
                else if (pc === AFT.stars) {
                    f.frame = Math.round(cyc() - t.ff);
                    f.sun = cpu.ramRomOs[sy.GSUNON] ? cpu.ramRomOs[sy.GSUNR] : -1;
                    f.pr = b6(sy.F_PLON) ? b6(sy.F_PLR) : -1;
                    f.sec = b6(sy.f_sec); f.view = cpu.ramRomOs[sy.VIEW]; f.slot1 = cpu.ramRomOs[sy.FRIN + 1];
                    if (f.sun >= 0) { const w = x => { const v = cpu.ramRomOs[x] | cpu.ramRomOs[x + 1] << 8; return v > 32767 ? v - 65536 : v; }; f.sx = w(sy.F_SUX); f.sy = w(sy.F_SUY); }
                    frames.push(f); f = null;
                }
            }
            return false;
        });
    } });
const it = res.iterTimes;
const rate = (p, q) => (q - p) / (it[q] - it[p]);
const out = { FROM, TO, rate: rate(FROM, TO), frames };
if (a.out) writeFileSync(a.out, JSON.stringify(out));
const sum = k => frames.reduce((s, f) => s + (f[k] || 0), 0);
const withSun = frames.filter(f => f.sun >= 0), both = frames.filter(f => f.sun >= 0 && f.pr >= 0);
console.log(`iterations ${FROM}-${TO}: ${rate(FROM, TO).toFixed(3)} it/s; ${frames.length} frames, ${withSun.length} with the sun, ${both.length} with the sun and the planet, ${frames.filter(f => f.sun >= 0 && f.view === 0).length} in the front view`);
console.log(`cycles per frame: S_SUN ${(sum("ss") / frames.length).toFixed(0)}, discs ${(sum("discs") / frames.length).toFixed(0)}, disc2 ${(sum("disc2") / frames.length).toFixed(0)}, flt ${(sum("flt") / frames.length).toFixed(0)}, frame ${(sum("frame") / frames.length).toFixed(0)}`);
for (const f of frames) if (f.i % 10 === 0 || f.sun >= 0) console.log(JSON.stringify(f));
process.exit(0);
