// live.mjs: what a stretch of the game's code leaves that the game reads
// later. For each span (a start label and an end: the return from the
// routine the start label is in, or another label), the zero page and
// workspace bytes the span writes are watched from its end: the next access
// by game code (anything but the renderer's banks, the frame layer and the
// MOS) is either a read (the value the span left is live) or a write (dead).
// Per address it counts both and names the routines that read.
//
//   node 6-harness/records/live.mjs --cand DISC --csyms SYMS [--iters 10000]
//        --span PTCLS:ret [--span LL42:H_EE31,DOEXP ...] [--views] [--xx3]
//        [--touch 2-5,28-3b,...]
//
// A span "A:ret" starts when the PC reaches label A and ends when the stack
// rises above where it was then (A's routine returns; "ret" for a routine
// fallen into from its caller's tail, as PTCLS is from DOEXP, also works);
// "A:B,C" ends when the PC reaches B or C. Only spans started in a space view
// (QQ11 = 0) are watched. PTCLS spans are split into the erase pass (called
// from H_PTCLSE) and the draw pass. Flies the gate's pilot (6-harness/mpilot.mjs)
// for --iters main-loop iterations (with --views, changing view as
// mcompare's --views does). --xx3: page 1 (XX3 and the stack) is watched too.
// --touch: these zero page addresses (hex, ranges a-b) count as written by
// every span (to ask whether the values the game had at a span's start, if
// the span had changed them, would be read).
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
const HERE = dirname(fileURLToPath(import.meta.url)), TREE = resolve(`${HERE}/../..`);
const argv = process.argv.slice(2), arg = n => { const i = argv.indexOf("--" + n); return i >= 0 ? argv[i + 1] : undefined; };
const spansArg = argv.flatMap((v, i) => v === "--span" ? [argv[i + 1]] : []);
const { loadSyms, mapAt, mapOfLabel, runElite } = await import(`${TREE}/6-harness/mlib.mjs`);
const { makePilot, patchCommander } = await import(`${TREE}/6-harness/mpilot.mjs`);
const sy = loadSyms(arg("csyms"));
const at = n => { if (sy[n] === undefined) throw new Error("no label " + n); return [sy[n], mapOfLabel(sy, n)]; };
const is = (cpu, pc, [ad, m]) => pc === ad && (m === "m" || mapAt(cpu.romsel, pc) === m);
const SPANS = spansArg.map(s => { const [f, t] = s.split(":"); return { name: s, from: at(f), fromName: f, ret: t === "ret", to: t === "ret" ? [] : t.split(",").map(at) }; });
// labels by mapping, for naming readers
const labs = {};
for (const [k, v] of Object.entries(sy)) { if (v < 0x0800) continue; const m = mapOfLabel(sy, k); if (m === "m" && v >= 0x8000) continue; (labs[m] ||= []).push([k, v]); }
for (const l of Object.values(labs)) l.sort((x, y) => x[1] - y[1]);
const labelOf = (cpu, pc) => { const l = labs[mapAt(cpu.romsel, pc)] || []; let r = "?"; for (const [k, v] of l) { if (v <= pc) r = k; else break; } return r; };
const zpName = {}; for (const [k, v] of Object.entries(sy)) if (v < 0x100 && !(v in zpName)) zpName[v] = k;
const nameOf = ad => ad < 0x100 ? (zpName[ad] !== undefined ? `${zpName[ad]}` : "") + `(&${ad.toString(16)})` : ad < 0x200 ? `stack+${ad - 0x100}` : "&" + ad.toString(16);
// renderer and MOS code: its accesses are not the game's
const isRenderer = (cpu, pc) => {
    if (pc >= 0xe000) return true;
    if (pc >= 0xc000) return !(cpu.acccon & 8);
    if (pc >= 0x8000) {
        const b = cpu.romsel & 0x8f;
        if (b & 0x80 && pc < 0x9000) return true;
        if ((b & 15) === 5 || (b & 15) === 6) return true;
        if ((b & 15) === 7 && sy.MERID_START !== undefined && pc >= sy.MERID_START) return true;
    }
    return false;
};
const watched = ad => ad < 0x100 || (ad >= 0x0400 && ad < 0x0d00) || (argv.includes("--xx3") && ad >= 0x100 && ad < 0x200);
const R = {}, count = {};
const pend = new Map();   // addr -> span key whose value is pending
const open = [];          // active spans: { key, s, sp, wrote }
const pilot = makePilot(), ITERS = +(arg("iters") || 10000);
let installed = false;
const resolveAcc = (cpu, ad, kind) => {
    const p = pend.get(ad);
    if (p === undefined) return;
    pend.delete(ad);
    const e = ((R[ad] ||= {})[p] ||= { live: 0, dead: 0, readers: {} });
    if (kind === "r") { e.live++; const l = labelOf(cpu, cpu.pc); e.readers[l] = (e.readers[l] || 0) + 1; } else e.dead++;
};
const TOUCH = (arg("touch") || "").split(",").filter(Boolean).flatMap(r => { const [a, b = a] = r.split("-").map(h => parseInt(h, 16)); return Array.from({ length: b - a + 1 }, (_, i) => a + i); });
const close = i => { const o = open[i]; for (const ad of o.wrote) pend.set(ad, o.key); for (const ad of TOUCH) pend.set(ad, o.key); open.splice(i, 1); };
const install = cpu => {
    cpu.debugInstruction.add(pc => {
        for (let i = open.length - 1; i >= 0; i--) {
            const o = open[i];
            if (o.sp.ret ? cpu.s >= o.s + 2 : o.sp.to.some(t => is(cpu, pc, t))) close(i);
        }
        for (const sp of SPANS) if (is(cpu, pc, sp.from) && cpu.ramRomOs[sy.QQ11] === 0 && !open.some(o => o.sp === sp)) {
            let key = sp.name;
            if (sp.fromName === "PTCLS") {
                const ret = (cpu.ramRomOs[0x101 + cpu.s] | cpu.ramRomOs[0x102 + cpu.s] << 8) + 1;
                key += ret > sy.H_PTCLSE && ret < sy.H_PTCLSE + 8 ? " erase" : " draw";
            }
            count[key] = (count[key] || 0) + 1;
            open.push({ key, s: cpu.s, sp, wrote: new Set() });
        }
        return false;
    });
    cpu.debugRead.add(ad => {
        if (!watched(ad) || isRenderer(cpu, cpu.pc)) return false;
        resolveAcc(cpu, ad, "r");
        return false;
    });
    cpu.debugWrite.add(ad => {
        if (!watched(ad) || isRenderer(cpu, cpu.pc)) return false;
        resolveAcc(cpu, ad, "w");
        for (const o of open) o.wrote.add(ad);
        return false;
    });
};
const rsy = loadSyms(`${TREE}/4-reference-binaries/sng47/symbols.txt`);
const ref = await runElite({ disc: `${TREE}/4-reference-binaries/sng47/elite-master-sng47.ssd`, syms: rsy, pilot: makePilot(), iters: 1, maxSecs: 200, patch: patchCommander });
const seedBoot = (cregions, written, rb) => {
    const out = []; let o = 0;
    for (const [, n, name] of ref.regions) {
        const c = cregions.find(r => r[2] === name);
        if (c && c[1] === n) for (let i = 0; i < n; i++) if (!written.has(c[0] + i) && rb(c[0] + i) !== ref.init[o + i]) out.push([c[0] + i, [ref.init[o + i]]]);
        o += n;
    }
    return out;
};
const views = argv.includes("--views");
await runElite({ disc: arg("cand"), syms: sy, pilot: views ? makePilot({ views: true }) : pilot, iters: ITERS, maxSecs: 4 * ITERS, patch: patchCommander, seedBoot,
    onIter: (i, s) => { if (!installed) { installed = true; install(s._machine.processor); } } });
console.log("spans in a space view: " + Object.entries(count).map(([k, v]) => `${k} ${v}`).join(", "));
for (const ad of Object.keys(R).map(Number).sort((x, y) => x - y))
    for (const [p, e] of Object.entries(R[ad]))
        console.log(`${nameOf(ad).padEnd(16)} ${p.padEnd(22)} live ${String(e.live).padStart(7)} dead ${String(e.dead).padStart(7)}  ${Object.entries(e.readers).sort((x, y) => y[1] - x[1]).slice(0, 6).map(([k, v]) => `${k} ${v}`).join(", ")}`);
process.exit(0);
