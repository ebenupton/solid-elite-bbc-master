// combat.mjs: a busy combat scene, the same on any build whose game logic is
// SNG47's, for comparing two builds frame by frame (speed and pixels).
//
//   node 6-harness/records/combat.mjs --disc DISC --syms SYMS --out FILE.json
//        [--iters 600] [--ships 8] [--prof LABEL,LABEL...]
//   node 6-harness/records/combat.mjs --cmp A.json B.json [--each]
//
// Boots the build as the gate does (6-harness/mlib.mjs runElite: the gate's
// pilot, 6-harness/mpilot.mjs, through the title and the docked screens to the
// first launch, the boot leftovers seeded from the reference as mcompare
// does), then presses no keys in flight and, from the 20th iteration in space,
// keeps the scene: up to --ships hostile ships, as many as the ship line heap
// takes (a fixed list of types and places, spawned by the game's own NWSHP,
// entered at MLOOP with MLOOP+2 as its return), one set exploding (byte #31
// bit 7) every 12 iterations from the 40th and replaced as its slot frees,
// and our energy and shields kept full. Nothing depends on the build's speed,
// so two builds whose game logic is the same fly the same scene. Per
// iteration it records the emulated cycles from MLOOP to MLOOP, the frame's
// cycles (F_FRAME to the end of its drawing, f_reset), the ships and dots the
// frame layer recorded, a hash of the game state (RAND, the ship slots and
// FRIN) and a hash of both screen buffers at the frame's end. Where the build
// has GPRJ (the frame projecting ships), it also prints how close the stack
// came to the vertices projected (as stack.mjs). --cmp prints both builds'
// speed over the run, and the iterations whose game state or pixels differ.
import { readFileSync, writeFileSync } from "fs";
import { createHash } from "crypto";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
const HERE = dirname(fileURLToPath(import.meta.url)), TREE = resolve(`${HERE}/../..`);
const { loadSyms, mapAt, mapOfLabel, physRead, runElite } = await import(`${TREE}/6-harness/mlib.mjs`);
const { makePilot, patchCommander } = await import(`${TREE}/6-harness/mpilot.mjs`);
const argv = process.argv.slice(2), arg = (n, d) => { const i = argv.indexOf("--" + n); return i >= 0 ? argv[i + 1] : d; };

if (argv.includes("--cmp")) {
    const [fa, fb] = argv.slice(argv.indexOf("--cmp") + 1);
    const A = JSON.parse(readFileSync(fa, "utf8")), B = JSON.parse(readFileSync(fb, "utf8"));
    const n = Math.min(A.iters.length, B.iters.length);
    let ca = 0, cb = 0, fa_ = 0, fb_ = 0, worse = 0, better = 0, worst = 1;
    const diff = [], sdiff = [];
    for (let i = 0; i < n; i++) {
        const a = A.iters[i], b = B.iters[i];
        ca += a.cyc; cb += b.cyc; fa_ += a.frame; fb_ += b.frame;
        if (a.state !== b.state) sdiff.push(i);
        if (a.fb !== b.fb) diff.push(i);
        if (b.cyc > a.cyc) worse++; else if (b.cyc < a.cyc) better++;
        worst = Math.max(worst, b.cyc / a.cyc);
        if (argv.includes("--each")) console.log(`${String(i).padStart(4)} ships ${a.ships}/${b.ships} dots ${a.dots}/${b.dots}  iter ${a.cyc} ${b.cyc} (${(b.cyc / a.cyc).toFixed(4)})  frame ${a.frame} ${b.frame}${a.fb !== b.fb ? "  PIXELS DIFFER" : ""}${a.prof || b.prof ? "  " + [...new Set([...Object.keys(a.prof || {}), ...Object.keys(b.prof || {})])].map(k => `${k} ${(a.prof || {})[k] || 0}/${(b.prof || {})[k] || 0}`).join(" ") : ""}`);
    }
    const ips = c => (2e6 * n / c).toFixed(3);
    console.log(`${n} iterations: A ${ips(ca)} it/s, B ${ips(cb)} it/s (B/A ${(ca / cb).toFixed(4)}); frame cycles A ${Math.round(fa_ / n)} B ${Math.round(fb_ / n)} an iteration`);
    console.log(`iterations slower in B ${worse} (the worst by ${((worst - 1) * 100).toFixed(2)}%), faster ${better}; game state differs in ${sdiff.length}${sdiff.length ? " from " + sdiff[0] : ""}; frames whose pixels differ: ${diff.length}${diff.length ? ": " + diff.slice(0, 40).join(" ") : ""}`);
    process.exit(diff.length || sdiff.length ? 1 : 0);
}

const sy = loadSyms(arg("syms")), rsy = loadSyms(`${TREE}/4-reference-binaries/sng47/symbols.txt`);
const ITERS = +arg("iters", 600), NSHIPS = +arg("ships", 8);
const ref = await runElite({ disc: `${TREE}/4-reference-binaries/sng47/elite-master-sng47.ssd`, syms: rsy, pilot: makePilot(), iters: 1, maxSecs: 200, patch: patchCommander });
const seedBoot = (cregions, written, rb) => { const out = []; let o = 0; for (const [, n, name] of ref.regions) { const c = cregions.find(r => r[2] === name); if (c && c[1] === n) for (let i = 0; i < n; i++) if (!written.has(c[0] + i) && rb(c[0] + i) !== ref.init[o + i]) out.push([c[0] + i, [ref.init[o + i]]]); o += n; } return out; };
const lab = n => { if (sy[n] === undefined) throw new Error("no " + n); return [sy[n], mapOfLabel(sy, n)]; };
const base = makePilot();
let flying = false;
const pilot = { ...base, keys: ctx => flying && ctx.site === "DOKEY" ? [] : base.keys(ctx) };
const TYPES = [11, 12, 17, 18, 19, 20, 21, 25, 27, 29, 24, 16];
const place = k => { const a = k * 2.4; return [Math.round(500 * Math.cos(a)), Math.round(300 * Math.sin(a)), 900 + (k * 377) % 1800]; };
const out = { iters: [] };
const ST = { minS: 0xff, maxX: 0x100, type: 0 };
class Done {}
let installed = false, inSpace = 0, spawnK = 0, rec = null, t0 = 0, f0 = 0, atLoop = null;
try {
    await runElite({ disc: arg("disc"), syms: sy, pilot, iters: 1e6, maxSecs: 20000, patch: patchCommander, seedBoot,
        onIter: (i, s) => {
            const cpu = s._machine.processor, ram = cpu.ramRomOs;
            if (!installed) { installed = true; atLoop = install(cpu, ram); }
            atLoop();
            if (out.iters.length >= ITERS) throw new Done();
        } });
} catch (e) { if (!(e instanceof Done)) throw e; }

function install(cpu, ram) {
    const cyc = () => cpu.cycleSeconds * 2e6 + cpu.currentCycles;
    const is = (pc, [ad, m]) => pc === ad && (m === "m" || mapAt(cpu.romsel, pc) === m);
    const MLOOP = lab("MLOOP"), NWSHP = lab("NWSHP"), FF = lab("F_FRAME"), FR = sy.f_reset, RET = [MLOOP[0] + 2, MLOOP[1]];
    const setCoord = (o, v) => { const m = Math.abs(v); ram[sy.INWK + o] = m & 255; ram[sy.INWK + o + 1] = m >> 8; ram[sy.INWK + o + 2] = v < 0 ? 0x80 : 0; };
    const ships = () => { let n = 0; for (let k = 0; k < 12; k++) { const t = ram[sy.FRIN + k]; if (t && t < 0x80 && t !== 2) n++; } return n; };
    let want = false, spawning = false, lastShips = -1, full = 99, saved = null;
    if (sy.GPRJ !== undefined) {
        cpu.debugInstruction.add(() => { if ((ram[sy.GPRJ] & 0x80) && cpu.s < ST.minS) ST.minS = cpu.s; return false; });
        cpu.debugWrite.add(a => { if ((ram[sy.GPRJ] & 0x80) && a >= 0x100 && a < 0x100 + cpu.s && a > ST.maxX) { ST.maxX = a; ST.type = physRead(cpu, 6, sy.F_STYP + physRead(cpu, 6, sy.f_si)); } return false; });
    }
    function spawnOne() {
        lastShips = ships();
        const k = spawnK++, t = TYPES[k % TYPES.length], [x, y, z] = place(k);
        ram.fill(0, sy.INWK, sy.INWK + 37);
        setCoord(0, x); setCoord(3, y); setCoord(6, z);
        ram[sy.INWK + 22] = 96; ram[sy.INWK + 18] = 96; ram[sy.INWK + 14] = 0x80 | 96;   // ZINF's: facing us
        ram[sy.INWK + 27] = 12; ram[sy.INWK + 32] = 0xBE; ram[sy.INWK + 36] = 4;          // speed, AI, hostile
        const ret = RET[0] - 1;
        ram[0x100 + cpu.s] = ret >> 8; cpu.s = (cpu.s - 1) & 255; ram[0x100 + cpu.s] = ret & 255; cpu.s = (cpu.s - 1) & 255;
        cpu.a = t; cpu.pc = NWSHP[0];
    }
    // --prof a,b,c: the cycles in each of these routines (from its label to
    // its return), per iteration (rec.prof)
    const PROF = (arg("prof") || "").split(",").filter(Boolean).map(n => ({ n, at: lab(n) }));
    const open = [];
    if (PROF.length) cpu.debugInstruction.add(pc => {
        for (let k = open.length - 1; k >= 0; k--) if (cpu.s >= open[k].s + 2) { const o = open[k]; open.splice(k, 1); if (rec) rec.prof[o.n] = (rec.prof[o.n] || 0) + cyc() - o.t; }
        for (const p of PROF) if (is(pc, p.at)) open.push({ n: p.n, s: cpu.s, t: cyc() });
        return false;
    });
    cpu.debugInstruction.add(pc => {
        // (this hook runs after runElite's, which calls onIter at MLOOP: stopping
        // the slice here, before MLOOP's first instruction runs, leaves the PC to
        // be set to NWSHP)
        if (want && is(pc, MLOOP)) { want = false; spawning = true; saved = Array.from(ram.subarray(sy.INWK, sy.INWK + 37)); spawnOne(); return true; }
        if (spawning && is(pc, RET)) {
            if (ships() >= Math.min(NSHIPS, full) || ships() === lastShips) {
                if (ships() === lastShips) full = ships();     // (NWSHP found no room: until a ship goes)
                for (let k = 0; k < 37; k++) ram[sy.INWK + k] = saved[k];
                cpu.x = 0xff;                                   // (MLOOP's LDX #&FF, before its TXS)
                spawning = false; t0 = cyc();
                return false;
            }
            spawnOne();
            return true;
        }
        if (rec) {
            if (is(pc, FF)) { f0 = cyc(); if (ram[sy.QQ11] === 0) { rec.ships = physRead(cpu, 6, sy.F_NSHIP); rec.dots = physRead(cpu, 6, sy.F_NDOT); } }
            else if (pc === FR && (cpu.romsel & 0x8f) === 6 && f0) {
                rec.frame += cyc() - f0; f0 = 0;
                rec.fb = createHash("sha1").update(ram.subarray(0x4000, 0x7000)).update(ram.subarray(0xc000, 0xf000)).digest("hex").slice(0, 16);
            }
        }
        return false;
    });
    return () => {
        const now = cyc();
        if (rec) { rec.cyc = now - t0; out.iters.push(rec); rec = null; }
        if (!flying && base.P.phase !== "docked" && base.P.phase !== "title" && ram[sy.QQ12] === 0 && ram[sy.QQ11] === 0) flying = true;
        if (flying && ram[sy.QQ11] === 0) inSpace++;
        if (inSpace < 20) return;
        ram[sy.ENERGY] = 255; ram[sy.FSH] = 255; ram[sy.ASH] = 255;
        if (inSpace >= 40 && (inSpace - 40) % 12 === 0)
            for (let k = 2; k < 12; k++) { const b = sy["K%"] + 37 * k; if (ram[sy.FRIN + k] && !(ram[b + 31] & 0xa0)) { ram[b + 31] |= 0x80; break; } }
        if (ships() < full) full = 99;
        if (out.iters.length < ITERS) rec = { cyc: 0, frame: 0, ships: 0, dots: 0, fb: "", prof: {},
            state: createHash("sha1").update(ram.subarray(sy.RAND, sy.RAND + 4)).update(ram.subarray(sy["K%"], sy["K%"] + 12 * 37)).update(ram.subarray(sy.FRIN, sy.FRIN + 12)).digest("hex").slice(0, 12) };
        t0 = now;
        if (ships() < Math.min(NSHIPS, full)) want = true;
    };
}
writeFileSync(arg("out"), JSON.stringify(out));
const tot = out.iters.reduce((a, r) => a + r.cyc, 0);
if (sy.GPRJ !== undefined) console.log(`stack: lowest S while the frame projects &${ST.minS.toString(16)}, highest XX3 byte &${ST.maxX.toString(16)} (type ${ST.type}), margin ${0x101 + ST.minS - ST.maxX - 1} bytes`);
console.log(`${out.iters.length} iterations, ${(2e6 * out.iters.length / tot).toFixed(2)} it/s, spawned ${spawnK}, ships per frame ${(out.iters.reduce((a, r) => a + r.ships, 0) / out.iters.length).toFixed(1)}, dots max ${Math.max(...out.iters.map(r => r.dots))}`);
process.exit(0);
