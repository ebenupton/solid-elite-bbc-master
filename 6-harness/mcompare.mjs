// Determinism and speed comparison for BBC Master Elite: a reference build
// against a candidate build, both on the emulated BBC Master, both driven by the
// same deterministic pilot (mpilot.mjs) through mlib.mjs's input
// injection.
//
// node 6-harness/mcompare.mjs [--iters 5000] [--ref disc] [--rsyms file]
//                           [--cand disc] [--csyms file] [--seed boot|rand|none]
//                           [--loose] [--window 200] [--out dir] [--shots N]
//                           [--maxsecs S] [--nopatch] [--norefcache] [--views]
//                           [--trace FROM,TO,LABEL+LABEL,VAR+VAR~OFFSET]
//
// Defaults: reference = 4-reference-binaries/sng47/elite-master-sng47.ssd (the
// released SNG47 disc) with 4-reference-binaries/sng47/symbols.txt (the symbols
// of the original source's build, which is bit-identical to it); candidate =
// 5-compiled-game-discs/elite-master-sng47.ssd with
// 3-assembled-output/symbols.txt.
//
// An iteration is one pass of the main loop, counted at MLOOP (so docked
// iterations count too; the flight loop proper, TT100 to MLOOP, runs only in
// space). At every MLOOP the game state (mlib.regionsFor: zero page, K% ship
// slots and line heap, WP: FRIN, flight variables, stardust, the commander
// NAME..SVC, JOPOS; UP: configuration; NA%: the last saved commander; the sound
// buffers) is recorded and the two runs are compared iteration by iteration.
// Addresses that depend on real time are excluded (mlib.TIMING_EXCLUDE: DL, the
// IRQ's vsync flag; JOPOS, the IRQ's ADC values; the sound buffers, counted down
// by the IRQ), and so are temporaries that hold addresses of relocated code or
// data (mlib.RELOC_EXCLUDE). --loose also excludes drawing temporaries and line heaps
// (mlib.DRAW_EXCLUDE), for candidates whose drawing differs. The first
// divergence is reported with symbol names, then per-address counts.
//
// --seed boot (the default): at TT170, every byte of the compared state that the
// candidate has not written since its entry point S% (by its own code or by
// the MOS on its behalf) and that differs from the reference's is set to the
// reference's value. Such bytes were left by the boot and the loader (the
// loader's code in WP, MOS and DFS workspace bytes in zero page such as JSTX
// that depend on the files loaded, RAND as the loader's Saturn leaves it), not
// by the game, and a changed loader or disc changes them. The bytes seeded are
// reported. --seed rand copies only RAND; --seed none nothing.
//
// Speed: flight-loop iterations (TT100 to TT100, only those with no docked
// iteration in between) per emulated second, per window of --window
// iterations, for both runs, with the pilot's phase mix for the window.
//
// Exit status 0 if the game state is identical at every compared iteration
// (and both runs completed); prints "MCOMPARE PASS <ref it/s> <cand it/s>" or
// "MCOMPARE FAIL <reason>".
import { runElite, loadSyms, regionsFor, excludeSet, TIMING_EXCLUDE, RELOC_EXCLUDE, DRAW_EXCLUDE, ROOT, CAND_DISC, CAND_SYMS, REF_DISC, REF_SYMS, WORK } from "./mlib.mjs";
import { makePilot, patchCommander } from "./mpilot.mjs";
import { writeFileSync, mkdirSync } from "fs";
import { makeTracer } from "./mtrace.mjs";
import { parseArgs } from "./args.mjs";

const args = parseArgs({ iters: "value", ref: "value", rsyms: "value", cand: "value", csyms: "value", seed: "value", loose: "flag", window: "value",
    out: "value", shots: "value", maxsecs: "value", nopatch: "flag", norefcache: "flag", views: "flag", trace: "value", screen: "flag" });
for (const [d, s] of [["ref", "rsyms"], ["cand", "csyms"]])       // (a disc with another build's symbols hooks the wrong addresses)
    if (!args[d] !== !args[s]) { console.error(`--${d} and --${s} go together`); process.exit(2); }
const ITERS = +(args.iters || 5000);
const REF = args.ref || REF_DISC;
const RSYMS = args.rsyms || REF_SYMS;
const CAND = args.cand || CAND_DISC;
const CSYMS = args.csyms || CAND_SYMS;
const SEED = args.seed || "boot";
const WINDOW = +(args.window || 200);
const OUT = args.out || `${WORK}compare`;
const SHOTS = +(args.shots || 0);
mkdirSync(OUT, { recursive: true });

const rsy = loadSyms(RSYMS), csy = loadSyms(CSYMS);

async function run(label, disc, sy, seed, seedBoot) {
    const pilot = makePilot({ views: !!args.views });   // --views: the pilot changes view in flight
    const phases = [];
    // --trace FROM,TO,LABEL+LABEL,EXTRA+EXTRA (mtrace.mjs): <out>/trace-<label>.txt
    const traceOut = [];
    const tracer = args.trace ? makeTracer(args.trace, sy, traceOut) : null;
    const t0 = Date.now();
    const r = await runElite({
        disc, syms: sy, pilot, iters: ITERS, maxSecs: +(args.maxsecs || 4 * ITERS),
        patch: args.nopatch ? null : patchCommander, seed, seedBoot, screen: !!args.screen,
        onIter: (i, s, res) => { phases.push(pilot.P.phase); if (tracer) tracer(i, s, res); },
        shots: SHOTS, onShot: async (s, i) => writeFileSync(`${OUT}/${label}-${String(i).padStart(6, "0")}.png`, await s.screenshotActive({ scale: 1 })),
    });
    r.phases = phases; r.stats = pilot.P.stats; r.wall = (Date.now() - t0) / 1000;
    if (tracer) writeFileSync(`${OUT}/trace-${label}.txt`, traceOut.join("\n") + "\n");
    console.log(`${label}: ${r.iters} iterations (${r.tt100} in flight), emulated ${r.emuSecs.toFixed(1)} s, wall ${r.wall.toFixed(1)} s${r.error ? ", STOPPED: " + r.error : ""}`);
    return r;
}

// The reference run depends only on the reference disc and symbols, the
// harness (mlib, mpilot) and the options that shape the run, so it is cached
// (6-harness/work/refcache, keyed by a hash of all of those; --norefcache to
// rerun it).
async function cachedRef() {
    const { createHash } = await import("crypto");
    const { readFileSync, existsSync } = await import("fs");
    const { gzipSync, gunzipSync } = await import("zlib");
    const h = createHash("sha1");
    for (const f of [REF, RSYMS, new URL("mlib.mjs", import.meta.url), new URL("mpilot.mjs", import.meta.url)]) h.update(readFileSync(f));
    h.update(JSON.stringify([ITERS, args.maxsecs || 0, !!args.nopatch, !!args.views, !!args.screen]));
    const dir = `${WORK}refcache`, file = `${dir}/${h.digest("hex")}.json.gz`;
    if (!args.norefcache && !args.trace && existsSync(file)) {
        const o = JSON.parse(gunzipSync(readFileSync(file)).toString());
        o.snaps = o.snaps.map(b => Uint8Array.from(Buffer.from(b, "base64")));
        o.init = Uint8Array.from(Buffer.from(o.init, "base64"));
        o.stats.systems = new Set(o.stats.systems);
        console.log(`ref: ${o.iters} iterations (${o.tt100} in flight), emulated ${o.emuSecs.toFixed(1)} s (cached)`);
        return o;
    }
    const r = await run("ref", REF, rsy, null);
    const o = { snaps: r.snaps.map(b => Buffer.from(b).toString("base64")), screens: r.screens, init: Buffer.from(r.init).toString("base64"),
        initRand: [...r.initRand], iterTimes: r.iterTimes, tt100Times: r.tt100Times, regions: r.regions, keyLog: r.keyLog,
        iters: r.iters, tt100: r.tt100, emuSecs: r.emuSecs, error: r.error, phases: r.phases,
        stats: { ...r.stats, systems: [...r.stats.systems] } };
    mkdirSync(dir, { recursive: true });
    // (written whole, then renamed into place: a gate running at the same time in this
    // worktree never reads a part-written file)
    const tmp = `${file}.${process.pid}.tmp`;
    writeFileSync(tmp, gzipSync(JSON.stringify(o)));
    (await import("fs")).renameSync(tmp, file);
    return r;
}
const ref = await cachedRef();
const seeds = SEED === "rand" ? [[csy.RAND, [...ref.initRand]]] : null;
const seedBoot = SEED !== "boot" ? null : (cregions, written, rb) => {
    // region by region (the regions match by name and length; their addresses
    // may differ between builds)
    const out = [];
    let o = 0;
    for (const [ra, n, name] of ref.regions) {
        const c = cregions.find(r => r[2] === name);
        if (c && c[1] === n) for (let i = 0; i < n; i++) if (!written.has(c[0] + i) && rb(c[0] + i) !== ref.init[o + i]) out.push([c[0] + i, [ref.init[o + i]]]);
        o += n;
    }
    return out;
};
const cand = await run("cand", CAND, csy, seeds, seedBoot);
// the boot leftovers seeded into the candidate (for mprof.mjs --seedfile)
if (cand.seeded) writeFileSync(`${OUT}/seeded.json`, JSON.stringify(cand.seeded));

const report = [];
const log = (...x) => { const l = x.join(" "); console.log(l); report.push(l); };

// ---- Pilot coverage
function statLine(st) {
    return `launches ${st.launches}, dockings ${st.dockings}, hyperspace jumps ${st.jumps} (galactic ${st.galactic}), systems ${st.systems.size} [${[...st.systems].join(" ")}], ` +
        `engagements ${st.engagements}, ships destroyed ${st.kills} ${JSON.stringify(st.killTypes)}, missiles fired ${st.missiles}, ECM ${st.ecm}, deaths ${st.deaths}, ` +
        `trades: buy ${st.buys} sell ${st.sells} equip ${st.equips}, key waits ${st.waits}`;
}
log(`Iterations: ref ${ref.iters} (flight ${ref.tt100}), cand ${cand.iters} (flight ${cand.tt100}); seed=${SEED}${args.loose ? " loose" : ""}`);
log(`Pilot (ref):  ${statLine(ref.stats)}`);
log(`Pilot (cand): ${statLine(cand.stats)}`);

// ---- Compare
const rreg = ref.regions, creg = cand.regions;
let ok = true;
for (let k = 0; k < rreg.length; k++) if (rreg[k][1] !== creg[k][1] || rreg[k][2] !== creg[k][2]) { log(`region ${rreg[k][2]} differs in size: ref ${rreg[k][1]}, cand ${creg[k][1]}`); ok = false; }
const ex = excludeSet(rsy, args.loose ? [TIMING_EXCLUDE, RELOC_EXCLUDE, DRAW_EXCLUDE] : [TIMING_EXCLUDE, RELOC_EXCLUDE]);
// offset -> ref address
const offAddr = [];
for (const [a, n] of rreg) for (let i = 0; i < n; i++) offAddr.push(a + i);
const byAddr = {};
for (const [k, v] of Object.entries(rsy)) if (v < 0x8000 && !(v in byAddr)) byAddr[v] = k;
function symName(a) {
    for (let b = a; b >= Math.max(0, a - 64); b--) if (byAddr[b] !== undefined) return b === a ? byAddr[b] : `${byAddr[b]}+${a - b}`;
    return `&${a.toString(16)}`;
}
const n = Math.min(ref.snaps.length, cand.snaps.length);
let firstDiv = -1, firstAny = -1, printed = false;
const perAddr = {};
if (ok) {
    const ri = ref.init, ci = cand.init;
    const d0 = [];
    for (let o = 0; o < ri.length; o++) if (ri[o] !== ci[o] && !ex.has(offAddr[o])) d0.push(symName(offAddr[o]));
    if (cand.seeded) log(`Seeded at TT170 (boot leftovers): ${cand.seeded.length} bytes${cand.seeded.length ? ": " + cand.seeded.slice(0, 40).map(([a]) => symName(a)).join(" ") : ""}`);
    log(`State at TT170 (after seeding): ${d0.length} differing bytes${d0.length ? ": " + d0.slice(0, 40).join(" ") : ""}`);
    // --loose: the ship line heap grows down from &0800 and can reach into
    // the K% slots that are empty; an empty slot (FRIN = 0, compared) is
    // never read before NWSHP fills all of it, so its bytes are excluded
    const NI = 37, kOff = offAddr.indexOf(rsy["K%"]), fOff = offAddr.indexOf(rsy.FRIN);
    const emptySlot = (snap, o) => {
        if (!args.loose || o < kOff || o >= kOff + 12 * NI) return false;
        return snap[fOff + Math.floor((o - kOff) / NI)] === 0;
    };
    for (let i = 0; i < n; i++) {
        const a = ref.snaps[i], b = cand.snaps[i];
        for (let o = 0; o < a.length; o++) if (a[o] !== b[o]) {
            const ad = offAddr[o];
            perAddr[ad] = (perAddr[ad] || 0) + 1;
            if (firstAny < 0) firstAny = i;
            if (!ex.has(ad) && !emptySlot(a, o) && firstDiv !== i && firstDiv < 0) firstDiv = i;
        }
        if (firstDiv === i && !printed) {
            printed = true;
            log(`FIRST DIVERGENCE of game state at iteration ${i} (phase ${ref.phases[i]}, ref t=${ref.iterTimes[i].toFixed(2)} s, cand t=${cand.iterTimes[i].toFixed(2)} s):`);
            let shown = 0;
            for (let o = 0; o < a.length && shown < 100; o++) if (a[o] !== b[o] && !ex.has(offAddr[o]) && !emptySlot(a, o)) { log(`  ${symName(offAddr[o])} (&${offAddr[o].toString(16)}): ref &${a[o].toString(16)} cand &${b[o].toString(16)}`); shown++; }
            const kr = ref.keyLog.filter(k => k[0] >= i - 3 && k[0] <= i), kc = cand.keyLog.filter(k => k[0] >= i - 3 && k[0] <= i);
            log(`  keys (ref) ${JSON.stringify(kr)}`);
            log(`  keys (cand) ${JSON.stringify(kc)}`);
        }
    }
}
if (cand.page0d && cand.page0d.length) {
    log(`PAGE &0D WRITTEN by the game (off limits, docs/MASTER-MEMORY.md): ${cand.page0d.map(([i, pc, a]) => `iteration ${i} PC &${pc.toString(16)} -> &${a.toString(16)}`).join(", ")}`);
    ok = false;
}
// --screen: the screen (shadow RAM) at each iteration, for candidates that
// draw exactly as the original does
if (args.screen) {
    const sd = [];
    for (let i = 0; i < n; i++) if (ref.screens[i] !== cand.screens[i]) sd.push(i);
    if (sd.length) { log(`SCREEN DIFFERS at ${sd.length} iterations, the first ${sd.slice(0, 10).join(" ")}`); ok = false; }
    else log(`Screen identical at all ${n} iterations`);
}
const complete = ref.iters === ITERS && cand.iters === ITERS && !ref.error && !cand.error;
if (ok && firstDiv < 0) log(`Game state identical at all ${n} iterations${complete ? "" : " (INCOMPLETE run)"}`);
log(`First iteration with any difference (including excluded addresses): ${firstAny}`);
const pa = Object.entries(perAddr).sort((x, y) => y[1] - x[1]).slice(0, 40);
if (pa.length) {
    log("Per-address count of differing iterations (* = excluded):");
    for (const [ad, c] of pa) log(`  ${ex.has(+ad) ? "*" : " "} ${symName(+ad)} (&${(+ad).toString(16)}): ${c}${ex.has(+ad) ? "  [" + ex.get(+ad) + "]" : ""}`);
}

// ---- Speed
// flight iterations: consecutive TT100 entries one MLOOP iteration apart
function flightRates(r) {
    const dts = [];   // [iteration, dt]
    const t = r.tt100Times;
    for (let k = 1; k < t.length; k++) if (t[k][1] === t[k - 1][1] + 1) dts.push([t[k][1], t[k][0] - t[k - 1][0]]);
    return dts;
}
function windows(r) {
    const out = [];
    const dts = flightRates(r);
    for (let w = 0; w < ITERS; w += WINDOW) {
        const ds = dts.filter(([i]) => i >= w && i < w + WINDOW);
        const sum = ds.reduce((a, [, d]) => a + d, 0);
        out.push({ w, n: ds.length, rate: ds.length ? ds.length / sum : NaN });
    }
    const all = dts.reduce((a, [, d]) => a + d, 0);
    return { win: out, all: dts.length / all, n: dts.length };
}
const rs = windows(ref), cs = windows(cand);
function phaseMix(w) {
    const c = {};
    for (let i = w; i < Math.min(w + WINDOW, ref.phases.length); i++) c[ref.phases[i]] = (c[ref.phases[i]] || 0) + 1;
    return Object.entries(c).sort((a, b) => b[1] - a[1]).map(([p, k]) => `${p} ${k}`).join(", ");
}
log(`Speed: flight iterations per emulated second, per window of ${WINDOW} iterations`);
log(`  window          flight    ref     cand   cand/ref  phases (ref)`);
for (let k = 0; k < rs.win.length; k++) {
    const a = rs.win[k], b = cs.win[k] || { rate: NaN };
    log(`  ${String(a.w).padStart(5)}-${String(Math.min(a.w + WINDOW, ITERS) - 1).padStart(5)}   ${String(a.n).padStart(5)}  ${a.rate.toFixed(2).padStart(6)}  ${b.rate.toFixed(2).padStart(6)}   ${(b.rate / a.rate).toFixed(3).padStart(6)}   ${phaseMix(a.w)}`);
}
log(`  all              ${String(rs.n).padStart(5)}  ${rs.all.toFixed(2).padStart(6)}  ${cs.all.toFixed(2).padStart(6)}   ${(cs.all / rs.all).toFixed(3).padStart(6)}`);
// (the emulated machine runs at 2 MHz, so this is exact: the same flight
// iterations in both runs, when the game state is identical)
log(`Cycles per flight iteration: ref ${(2e6 / rs.all).toFixed(1)}, cand ${(2e6 / cs.all).toFixed(1)}`);
// by the pilot's phase at the iteration
{
    const byPhase = r => { const o = {}; for (const [i, d] of flightRates(r)) { const p = ref.phases[i] || "?"; (o[p] ||= [0, 0]); o[p][0]++; o[p][1] += d; } return o; };
    const pr = byPhase(ref), pc = byPhase(cand);
    log(`Speed by pilot phase (flight it/s): phase, iterations, ref, cand, cand/ref`);
    for (const [p, [k, d]] of Object.entries(pr)) { const c = pc[p] || [0, 1]; log(`  ${p.padEnd(9)} ${String(k).padStart(6)}  ${(k / d).toFixed(2).padStart(6)}  ${(c[0] / c[1]).toFixed(2).padStart(6)}   ${((c[0] / c[1]) / (k / d)).toFixed(3)}`); }
}
log(`  emulated time to iteration ${n - 1}: ref ${ref.iterTimes[n - 1]?.toFixed(1)} s, cand ${cand.iterTimes[n - 1]?.toFixed(1)} s`);
writeFileSync(`${OUT}/report.txt`, report.join("\n") + "\n");
writeFileSync(`${OUT}/keys-ref.txt`, ref.keyLog.map(k => k.join(" ")).join("\n") + "\n");
writeFileSync(`${OUT}/keys-cand.txt`, cand.keyLog.map(k => k.join(" ")).join("\n") + "\n");
if (ok && firstDiv < 0 && complete) { log(`MCOMPARE PASS ${rs.all.toFixed(2)} ${cs.all.toFixed(2)}`); process.exit(0); }
log(`MCOMPARE FAIL ${cand.page0d?.length ? "page &0D written" : !ok ? "regions or screen" : firstDiv >= 0 ? "divergence at " + firstDiv : "incomplete"}`);
process.exit(1);
