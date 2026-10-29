// probe.mjs: what the frame layer records per frame, and what recording and
// projecting a ship cost.
//
//   node 6-harness/records/probe.mjs --cand DISC --csyms SYMS [--log run1.jsonl --to 3600]
//                                       [--iters 10000] [--out FILE.json]
//
// With --log: replays that input log (as solidspan/fbhash.mjs); without, the
// gate's pilot run (6-harness/mpilot.mjs, the boot leftovers seeded as mcompare
// --seed boot), --iters MLOOP iterations, split by the pilot's phase.
// Per frame (at F_FRAME): ships recorded, F_DL bytes used, lines, dots.
// Per recorder call: cycles (F_SHIP without and with L_REC), drops (a call
// that recorded nothing for want of room, and the most in one frame).
// Per LL9: cycles by part (1-2, 3-7, 8, the
// rest), vertices projected (LL49) against the blueprint's.
import { writeFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import { parseArgs } from "../args.mjs";
const HERE = dirname(fileURLToPath(import.meta.url)), TREE = resolve(`${HERE}/../..`);
const a = parseArgs({ cand: "value", csyms: "value", log: "value", to: "value", iters: "value", out: "value" });
const { loadSyms, mapAt, mapOfLabel, physRead, runElite } = await import(`${TREE}/6-harness/mlib.mjs`);

function probe(cpu, sy, phaseOf) {
    const FORCE = { L_REC: 6 };   // (global labels from the light pass are not in banks.txt)
    const at = n => { const m = FORCE[n] ?? mapOfLabel(sy, n); if (sy[n] === undefined) throw new Error("no " + n); return [sy[n], m]; };
    const is = (pc, [ad, m]) => pc === ad && (m === "m" || mapAt(cpu.romsel, pc) === m);
    const L = Object.fromEntries(["F_SHIP", "L_REC", "F_LINE", "F_DOT", "F_SHPPT", "F_BOMB", "F_FRAME", "LL9", "LL17", "LL42", "LL49", "H_EE31", "DOEXP", "SHPPT", "f_ships", "PLANET", "f_ship", "fsh_nf0"].map(n => [n, at(n)]));
    console.log(Object.entries(L).map(([k, [ad, m]]) => `${k}=${m}:${ad.toString(16)}`).join(" "));
    const B6 = n => physRead(cpu, 6, sy[n]);
    const cyc = () => cpu.cycleSeconds * 2e6 + cpu.currentCycles;
    const R = { frames: {}, calls: {}, ll9: {}, types: {}, maxima: {} };
    const ph = () => (R.frames[phaseOf()] ||= { n: 0, ships: [], dl: [], lines: [], dots: [], shipsMax: 0, dlMax: 0, linesMax: 0, dotsMax: 0, frameCyc: 0, shipsCyc: 0 });
    const calls = n => (R.calls[n] ||= { n: 0, cyc: 0, drops: 0 });
    // active routines: [name, S at entry, t0, extra]
    const fdrop = {}; R.dropMax = {}; R.fship = { calls: 0, drawn: 0 };
    let act = [], last = cyc(), ll9 = null, frame = null;
    const hist = (arr, v) => { arr[v] = (arr[v] || 0) + 1; };
    cpu.debugInstruction.add(pc => {
        const now = cyc(), d = now - last; last = now;
        // close the routines that have returned
        for (let i = act.length - 1; i >= 0; i--) {
            const r = act[i];
            if (cpu.s >= r.s + 2 && pc !== r.pc) {
                act.splice(i, 1);
                const c = calls(r.n); c.n++; c.cyc += now - r.t;
                if (r.cnt !== undefined && r.cnt() === r.before) { c.drops++; fdrop[r.n] = (fdrop[r.n] || 0) + 1; }
                if (r.n === "LL9" && ll9) {
                    const k = phaseOf(), z = (R.ll9[k] ||= { n: 0, rec: 0, planet: 0, p12: 0, p37: 0, p8: 0, rest: 0, exp: 0, dot: 0, vproj: 0, vall: 0 });
                    z.n++; for (const q of ["planet", "p12", "p37", "p8", "rest", "exp", "dot"]) z[q] += ll9[q];
                    if (ll9.rec) { z.rec++; z.vproj += ll9.vp; z.vall += ll9.nv; }
                    ll9 = null;
                }
                if (r.n === "F_FRAME" && frame) { const f = ph(); f.frameCyc += now - r.t; frame = null; }
                if (r.n === "f_ships") { const f = ph(); f.shipsCyc += now - r.t; }
            }
        }
        if (ll9) ll9[ll9.part] += d;
        const push = (n, cnt) => act.push({ n, pc, s: cpu.s, t: now, cnt, before: cnt ? cnt() : undefined });
        if (is(pc, L.F_SHIP)) {
            push("F_SHIP", () => B6("F_NSHIP"));
            const t = physRead(cpu, "m", sy.GTYPE); (R.types[t] ||= { n: 0 }).n++;
            if (ll9) ll9.nv = physRead(cpu, "m", sy.GNV);
        } else if (is(pc, L.L_REC)) push("L_REC");
        else if (is(pc, L.F_LINE)) push("F_LINE", () => B6("F_NLINE"));
        else if (is(pc, L.F_DOT)) push("F_DOT", () => B6("F_NDOT"));
        else if (is(pc, L.F_SHPPT)) push("F_SHPPT", () => B6("F_NDOT"));
        else if (is(pc, L.F_BOMB)) push("F_BOMB");
        else if (is(pc, L.f_ships)) push("f_ships");
        else if (is(pc, L.F_FRAME) && physRead(cpu, "m", sy.QQ11) === 0) {
            push("F_FRAME"); frame = true;
            const f = ph(); f.n++;
            for (const [k, v] of Object.entries(fdrop)) { R.dropMax[k] = Math.max(R.dropMax[k] || 0, v); fdrop[k] = 0; }
            const ns = B6("F_NSHIP"), dl = B6("F_DLP") + 256 * physRead(cpu, 6, sy.F_DLP + 1) - sy.F_DL, nl = B6("F_NLINE"), nd = B6("F_NDOT");
            hist(f.ships, ns); hist(f.dl, dl >> 6 << 6); hist(f.lines, nl); hist(f.dots, nd);
            f.shipsMax = Math.max(f.shipsMax, ns); f.dlMax = Math.max(f.dlMax, dl); f.linesMax = Math.max(f.linesMax, nl); f.dotsMax = Math.max(f.dotsMax, nd);
        } else if (is(pc, L.LL9) && !ll9) {
            push("LL9"); ll9 = { part: "p12", planet: 0, p12: 0, p37: 0, p8: 0, rest: 0, exp: 0, dot: 0, vp: 0, nv: 0, rec: 0 };
        } else if (ll9) {
            if (is(pc, L.LL17)) ll9.part = "p37";
            else if (is(pc, L.LL42)) ll9.part = "p8";
            else if (is(pc, L.LL49)) ll9.vp++;
            else if (is(pc, L.H_EE31)) { ll9.part = "rest"; ll9.rec = 1; }
            else if (is(pc, L.DOEXP)) ll9.part = "exp";
            else if (is(pc, L.SHPPT)) ll9.part = "dot";
            else if (is(pc, L.PLANET)) ll9.part = "planet";
        }
        return false;
    });
    return R;
}

let R;
if (a.log) {
    const { replayMachine, CYCLES_PER_FRAME } = await import(`${TREE}/6-harness/solidspan/common.mjs`);
    const m = await replayMachine(a.log, a.cand, a.csyms);
    R = probe(m.cpu, m.sy, () => "run1");
    const TO = +(a.to || 3600);
    while (m.iter <= TO) { m.run(CYCLES_PER_FRAME); m.snaps.length = 0; }
} else {
    const { makePilot, patchCommander } = await import(`${TREE}/6-harness/mpilot.mjs`);
    const sy = loadSyms(a.csyms), rsy = loadSyms(`${TREE}/4-reference-binaries/sng47/symbols.txt`);
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
    const pilot = makePilot(), ITERS = +(a.iters || 10000);
    let installed = false;
    await runElite({ disc: a.cand, syms: sy, pilot, iters: ITERS, maxSecs: 4 * ITERS, patch: patchCommander, seedBoot,
        onIter: (i, s) => { if (!installed) { installed = true; R = probe(s._machine.processor, sy, () => pilot.P.phase); } } });
}
for (const c of Object.values(R.calls)) c.avg = c.n ? Math.round(c.cyc / c.n) : 0;
const out = resolve(a.out || `${TREE}/scratch/records/probe.json`);
writeFileSync(out, JSON.stringify(R, null, 1));
console.log(JSON.stringify({ dropMax: R.dropMax, fship: R.fship, types: R.types, calls: R.calls, ll9: R.ll9,
    frames: Object.fromEntries(Object.entries(R.frames).map(([k, f]) => [k, { n: f.n, shipsMax: f.shipsMax, dlMax: f.dlMax, linesMax: f.linesMax, dotsMax: f.dotsMax, frameCyc: Math.round(f.frameCyc / f.n), shipsCyc: Math.round(f.shipsCyc / f.n) }])) }, null, 1));
process.exit(0);
