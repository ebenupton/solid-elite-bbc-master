// The sun's parking (elite-source.asm: SUNUP, SUNSC, SUNBK,
// SUNLAU): scenes that the gate's run never reaches, each flown on the
// patched reference (the released SNG47 with the build's sunref.json, as
// mcompare.mjs runs it) and on the build, with the game state compared at
// every MLOOP (mcompare.mjs's comparison, --loose), and checked on both
// machines, every iteration and at each routine's entry and exit:
//
//   * at every MLOOP in flight in a system with a planet, with the station
//     present (SSPR), bit 7 of SUNPF is set (the sun is parked), bit 6 is
//     clear (SUNSC's two visits per pass) and slot 1 holds the station;
//   * MVEIT runs exactly once with TYPE = 129 in each flight iteration in
//     which a sun exists (slot 1, or parked), and not at all in one without;
//   * in the reference, nothing writes the patch's code, or the free bytes
//     after the station's line heap, but the patch's own code;
//   * (apart from what the comparison excludes, the drawing temporaries ...)
//     SUNUP changes only SUNPK and SUNPF, and leaves SUNPK equal to slot 1's
//     block; SUNBK (with the sun parked) changes only slot 1's block, FRIN+1,
//     SUNPF and SSPR, and leaves slot 1's block equal to SUNPK; SUNLAU, from
//     after its JSR NWSPS, changes only INWK, SUNPK, SUNPF and T, and leaves
//     SUNPK equal to INWK;
//   * the sun SUNLAU makes is the one SOLAR made on arrival in that system
//     (its position relative to the planet, with bit 0 of FIST then taken as
//     clear, and the rest of its block), whenever the scene arrived there
//     first (the arrival is noted where SOLAR falls into NWSTARS).
//
// The scenes (all from the gate's pilot, 6-harness/mpilot.mjs, and its
// commander; pokes at MLOOP, in both machines alike):
//   zone      the pilot's cycle (launch, fights, hyperspace, approach, docking)
//             with the station's safe zone left and entered again and again:
//             in flight with the station present, every 250 iterations, the
//             station is put 61440 ahead (FAROF removes it: SUNBK);
//             without it, the planet is put where part 14 spawns the station
//             (SUNUP), which the pilot then docks with (and launches: SUNLAU)
//   full      the sun parked and every other slot filled (three asteroids and
//             seven canisters, the heap just fitting), which the pilot shoots:
//             the slots shuffle below the parked sun, spawns fail, and the
//             explosion clouds are drawn (their seed: DOEXP, PTCLS)
//   handback  flying at the sun as the station goes: the sun ahead in the
//             front view, parked, then the station put far away; the sun's
//             centre on the screen (the build's F_SUX, F_SUY: the frame's
//             record) must move by no more than 2 pixels a frame across it
//   events    in the safe zone: the escape pod; a mis-jump (CTRL held at
//             TT18's test, PATG set); a crash into the station (death, the
//             title, a new game, a launch); a hyperspace jump; the energy bomb
//             and the E.C.M.; the galactic hyperdrive; each followed by the
//             pilot's own flying
//
// node 6-harness/msunslot.mjs [--scene zone,full,handback,events] [--iters N]
//      [--cand disc --csyms syms] [--out dir]
// Prints per scene the routines' entry counts in each machine, the checks'
// failures and "SUNSLOT PASS" or "SUNSLOT FAIL"; exit status 0 only on PASS.
import { runElite, loadSyms, loadRefPatch, refPatchPath, excludeSet, TIMING_EXCLUDE, RELOC_EXCLUDE, DRAW_EXCLUDE, ROOT, mapAt } from "./mlib.mjs";
import { makePilot, patchCommander, K } from "./mpilot.mjs";
import { writeFileSync, mkdirSync } from "fs";
import { parseArgs } from "./args.mjs";

const a = parseArgs({ scene: "value", iters: "value", cand: "value", csyms: "value", out: "value" });
const CAND = a.cand || `${ROOT}5-compiled-game-discs/elite-master-sng47.ssd`, CSYMS = a.csyms || `${ROOT}3-assembled-output/symbols.txt`;
const REF = `${ROOT}4-reference-binaries/sng47/elite-master-sng47.ssd`, RSYMS = `${ROOT}4-reference-binaries/sng47/symbols.txt`;
const OUT = a.out || `${ROOT}6-harness/work/sunslot`; mkdirSync(OUT, { recursive: true });
const RP = loadRefPatch(refPatchPath(CSYMS));
if (!RP || !RP.hooks) { console.log("SUNSLOT FAIL: the build has no reference patch with hooks (sunref.json)"); process.exit(1); }
const rsy = loadSyms(RSYMS), csy = loadSyms(CSYMS);
const NI = 37, SST = 2;
const SCENES = (a.scene || "zone,full,handback,events").split(",");
const DBG = process.env.SUNSLOT_DEBUG ? process.env.SUNSLOT_DEBUG.split("-").map(Number) : null;
const ITERS = { zone: 16000, full: 2500, handback: 400, events: 14000 };

// each machine's view of the routines: label -> { a, b } (address, ROMSEL bank or null)
function labels(sy, ref) {
    const L = n => {
        if (ref) return RP.hooks["A_" + n] !== undefined ? { a: RP.hooks["A_" + n], b: null } : null;
        const nm = sy[n + "_C"] !== undefined ? n + "_C" : n;
        if (sy[nm] === undefined) return null;
        const b = sy.__bank[nm];
        return { a: sy[nm], b: b === undefined || sy[nm] < 0x8000 || sy[nm] >= 0xc000 ? null : b & 15 };
    };
    const G = n => { const nm = !ref && sy[n + "_C"] !== undefined ? n + "_C" : n, b = sy.__bank[nm];
        return { a: sy[nm], b: b === undefined || sy[nm] < 0x8000 || sy[nm] >= 0xc000 ? null : b & 15 }; };
    return { SUNUP: L("SUNUP"), SUNBK: L("SUNBK"), SUNSC: L("SUNSC"), SUNLAU: L("SUNLAU"), MVEIT: G("MVEIT"), NWSTARS: G("NWSTARS"), SOLAR: G("SOLAR"), TT100: G("TT100"), KILLSHP: G("KILLSHP"),
        EV: ["DEATH", "DOENTRY", "ESCAPE", "TT18", "MJP", "TITLE", "Ghy", "BOMBON", "ECBLB2", "DOEXP"].map(n => [n, G(n)]),
        FEND: ref ? null : G("ff_stars9") };         // (the build's frame's end, after the stars: the frame's sun as recorded)
}

// a sign-magnitude coordinate (lo, hi, sign) as a number
const coord = (rb, a) => { const m = ((rb(a + 2) & 0x7f) << 16) | (rb(a + 1) << 8) | rb(a); return rb(a + 2) & 0x80 ? -m : m; };
const putc = (ram, a, v) => { const m = Math.abs(v); ram[a] = m & 255; ram[a + 1] = (m >> 8) & 255; ram[a + 2] = ((m >> 16) & 127) | (v < 0 ? 128 : 0); };

async function fly(scene, who, disc, sy, ref, seedBoot) {
    const L = labels(sy, ref);
    const pk = ref ? RP.region[0] : sy.SUNPK, pf = pk + NI;
    const pilot = makePilot();
    const P = pilot.P;
    const strays = [];
    const fail = [], count = { SUNUP: 0, SUNBK: 0, SUNSC: 0, SUNLAU: 0, parkedIters: 0, handbacks: 0 };
    const arrivals = {}, sunPos = [];
    let solarArm = false, mvArm = false, cpu = null, ram = null, regions = null, iter = 0, lastAct = 0, mv = 0, mvIter = -1, tt = 0, ttIter = -1;
    const rb = x => ram[x & 0xffff];
    const at = (h, pc) => h && pc === h.a && (h.b === null || (cpu.romsel & 15) === h.b);
    const snap = () => { const o = []; for (const [s, n] of regions) for (let i = 0; i < n; i++) o.push(ram[s + i]); return o; };
    const addrs = []; const setAddrs = () => { for (const [s, n] of regions) for (let i = 0; i < n; i++) addrs.push(s + i); };
    const block = base => Array.from({ length: NI }, (_, i) => rb(base + i));
    const sunExists = () => !rb(sy.QQ12) && !rb(sy.MJ) && rb(sy.FRIN) & 0x80 && (rb(sy.FRIN + 1) === 129 || (rb(sy.SSPR) && rb(pf) & 0x80));
    const K1 = sy["K%"] + NI;
    const open = [];                         // entries being watched: { name, sp, before }
    const exm = excludeSet(sy, [TIMING_EXCLUDE, RELOC_EXCLUDE, DRAW_EXCLUDE]);   // (drawing temporaries: SPBLB's SC ...)
    const allowed = {
        SUNUP: x => x >= pk && x <= pf,
        SUNBK: x => (x >= K1 && x < K1 + NI) || x === sy.FRIN + 1 || x === pf || x === sy.SSPR,
        SUNLAU: x => (x >= sy.INWK && x < sy.INWK + NI) || (x >= pk && x <= pf) || x === sy.T,
    };
    // the sun SOLAR made, noted at NWSTARS (SOLAR falls into it) after a jump
    const sysId = () => `${rb(sy.GCNT)}:${rb(sy.QQ0)},${rb(sy.QQ1)}`;
    function noteArrival() {
        if (rb(sy.FRIN + 1) !== 129 || !(rb(sy.FRIN) & 0x80) || rb(sy.QQ12)) return;
        const K0 = sy["K%"];
        const a3 = (rb(sy.QQ15 + 1) & 3) + 3, C = (rb(K0 + 8) & 0x7f) - a3;      // FIST's bit 0, from the planet's z_sign
        if (C !== 0 && C !== 1) { fail.push(`${who} ${iter}: SOLAR's planet at z_sign ${rb(K0 + 8)}, not ${a3} or ${a3 + 1}`); return; }
        const d = [0, 3, 6].map(o => coord(rb, K1 + o) - coord(rb, K0 + o));
        // (with bit 0 of FIST clear the planet is at (h, h, a), h = a / 2, not at
        // ((a + 1) / 2, (a + 1) / 2, a + 1); the sun is where it is)
        d[0] += (((a3 + C) >> 1) - (a3 >> 1)) * 65536; d[2] += C * 65536;
        arrivals[sysId()] = { d, rest: block(K1).slice(9) };
    }
    function checkLaunch() {
        const want = arrivals[sysId()];
        if (!want) return;
        count.launchChecked = (count.launchChecked || 0) + 1;
        const got = [0, 3, 6].map(o => coord(rb, pk + o) - [0, 0, 65536][o / 3]);   // (the planet at (0, 0, 1) sign units)
        const rest = block(pk).slice(9);
        if (got.join() !== want.d.join()) fail.push(`${who} ${iter}: SUNLAU's sun at ${got} from the planet, SOLAR's at ${want.d}`);
        if (rest.join() !== want.rest.join()) fail.push(`${who} ${iter}: SUNLAU's sun's bytes 9-36 ${rest.map(v => v.toString(16))}, SOLAR's ${want.rest.map(v => v.toString(16))}`);
    }
    function hook(pc) {
        for (let q = open.length - 1; q >= 0; q--) {
            const o = open[q];
            if (cpu.s <= o.sp) continue;
            open.splice(q, 1);
            const after = snap(), changed = [];
            for (let i = 0; i < after.length; i++) if (after[i] !== o.before[i]) changed.push(addrs[i]);
            const bad = changed.filter(x => !allowed[o.name](x) && !exm.has(x));
            if (bad.length) fail.push(`${who} ${iter}: ${o.name} changed ${bad.slice(0, 8).map(x => "&" + x.toString(16)).join(" ")}`);
            if (o.name === "SUNUP" && block(pk).join() !== block(K1).join()) fail.push(`${who} ${iter}: SUNUP: SUNPK is not slot 1's block`);
            if (o.name === "SUNBK" && o.parked && block(pk).join() !== block(K1).join()) fail.push(`${who} ${iter}: SUNBK: slot 1's block is not SUNPK`);
            if (o.name === "SUNBK" && !o.parked) fail.push(`${who} ${iter}: SUNBK with no parked sun (KS4's own sun)`);
            if (o.name === "SUNLAU") { if (block(pk).join() !== block(sy.INWK).join()) fail.push(`${who} ${iter}: SUNLAU: SUNPK is not INWK`); checkLaunch(); }
        }
        if (DBG && at(L.MVEIT, pc) && iter >= DBG[0] && iter <= DBG[1]) console.log(`${who} ${iter} MVEIT TYPE=${rb(sy.TYPE)} XSAV=${rb(sy.XSAV)} INF=${(rb(sy.INF) | rb(sy.INF + 1) << 8).toString(16)}`);
        // (MVEIT's entry, or its second instruction if the first was missed: jsbeeb
        // calls no hook for the instruction an interrupt returns to)
        const mvAt = at(L.MVEIT, pc), mv2 = L.MVEIT && pc === L.MVEIT.a + 2 && (L.MVEIT.b === null || (cpu.romsel & 15) === L.MVEIT.b);
        if (mvAt) mvArm = true;
        if ((mvAt || (mv2 && !mvArm)) && rb(sy.TYPE) === 129) { if (mvIter === iter) mv++; else { mvIter = iter; mv = 1; } }
        if (mv2) mvArm = false;
        else if (at(L.TT100, pc)) { if (ttIter === iter) tt++; else { ttIter = iter; tt = 1; } }
        else if (at(L.SUNSC, pc)) { count.SUNSC++; if (DBG && iter >= DBG[0] && iter <= DBG[1]) console.log(`${who} ${iter} SUNSC X=${cpu.x} SSPR=${rb(sy.SSPR)} SUNPF=${rb(pf).toString(16)} FRIN=${Array.from({ length: 13 }, (_, k) => rb(sy.FRIN + k)).join(",")}`); }
        else if (at(L.SUNUP, pc)) { count.SUNUP++; open.push({ name: "SUNUP", sp: cpu.s, before: snap() }); }
        else if (at(L.SUNBK, pc)) { count.SUNBK++; open.push({ name: "SUNBK", sp: cpu.s, before: snap(), parked: !!(rb(pf) & 0x80) && !!rb(sy.SSPR) }); }
        else if (L.SUNLAU && pc === L.SUNLAU.a + 3 && (L.SUNLAU.b === null || (cpu.romsel & 15) === L.SUNLAU.b)) { count.SUNLAU++; open.push({ name: "SUNLAU", sp: cpu.s, before: snap() }); }
        else if (at(L.SOLAR, pc)) solarArm = true;
        else if (at(L.NWSTARS, pc) && solarArm) { solarArm = false; noteArrival(); }   // (SOLAR falls into NWSTARS)
        else if (at(L.KILLSHP, pc) && rb(sy.SSPR) && rb(pf) & 0x80) count.killsParked = (count.killsParked || 0) + 1;
        else for (const [n, h] of L.EV) if (at(h, pc)) { count[n] = (count[n] || 0) + 1; if (rb(sy.SSPR) && rb(pf) & 0x80) count[n + "Parked"] = (count[n + "Parked"] || 0) + 1; break; }
        else if (at(L.FEND, pc) && scene === "handback" && ev && iter >= ev + 30 && iter <= ev + 50)
            sunPos.push([iter, rb(sy.FRIN + 1), wordAt(sy.F_SUX), wordAt(sy.F_SUY), rb(sy.GSUNR), rb(sy.GSUNON)]);
        return false;
    }
    // the scenes' pokes, at MLOOP (after the snapshot), in both machines alike
    const flying = () => !rb(sy.QQ12) && !rb(sy.MJ) && (rb(sy.FRIN) & 0x80) && P.phase !== "title" && P.phase !== "start";
    function leave() {                       // the station 61440 ahead: FAROF (z_hi > 224) removes it
        putc(ram, K1 + 6, 0xf000); lastAct = iter; count.leaves = (count.leaves || 0) + 1;
    }
    function approach() {                    // the planet where part 15 spawns the station 10848 ahead
        const K0 = sy["K%"];
        putc(ram, K0, 0); putc(ram, K0 + 3, -20000); putc(ram, K0 + 6, 60000);
        const vec = (o, x, y, z) => [x, y, z].forEach((c, j) => { ram[K0 + o + 2 * j] = 0; ram[K0 + o + 2 * j + 1] = c; });
        vec(9, 0, 0, 0xe0); vec(15, 0, 0x60, 0); vec(21, 0x60, 0, 0);
        lastAct = iter; count.approaches = (count.approaches || 0) + 1;
    }
    function fill() {                        // every other slot: 3 asteroids, 7 canisters, just ahead
        let heap = 0x800;
        for (let s = 2; s < 12; s++) {
            const t = s < 5 ? 7 : 5, size = t === 7 ? 69 : 53, b = sy["K%"] + NI * s;
            for (let i = 0; i < NI; i++) ram[b + i] = 0;
            putc(ram, b, (s - 7) * 600); putc(ram, b + 3, (s & 1 ? 1 : -1) * 400); putc(ram, b + 6, 3000 + 500 * s);
            ram[b + 14] = 0xe0; ram[b + 18] = 0x60; ram[b + 22] = 0x60;
            heap -= size; ram[b + 33] = heap & 255; ram[b + 34] = heap >> 8;
            ram[b + 35] = t === 7 ? 60 : 17; ram[b + 27] = 2;
            ram[sy.FRIN + s] = t; ram[sy.MANY + t]++; ram[sy.JUNK]++;
        }
        ram[sy.SLSP] = heap & 255; ram[sy.SLSP + 1] = heap >> 8;
        count.filled = heap.toString(16);
    }
    function sunAhead() {                    // the parked sun ahead, 3 sign units, a little up and right,
        putc(ram, pk, 30000); putc(ram, pk + 3, 20000); putc(ram, pk + 6, 3 * 65536);   // and the station
        putc(ram, K1, 0); putc(ram, K1 + 3, -6000); putc(ram, K1 + 6, -6000);           // behind us, below
        ram[sy.DELTA] = 1;
    }
    let ev = 0;
    function onIter(i, s, res) {
        iter = i;
        if (DBG && i >= DBG[0] && i <= DBG[1] && ram) console.log(`${who} ${i} MLOOP INWK33=${(rb(sy.INWK + 33) | rb(sy.INWK + 34) << 8).toString(16)} SLSP=${(rb(sy.SLSP) | rb(sy.SLSP + 1) << 8).toString(16)} FRIN=${Array.from({ length: 12 }, (_, k) => rb(sy.FRIN + k)).join(",")} SSPR=${rb(sy.SSPR)} TYPE=${rb(sy.TYPE)} QQ12=${rb(sy.QQ12)} phase=${P.phase}`);
        if (!cpu) {
            cpu = s._machine.processor; ram = cpu.ramRomOs; regions = res.regions; setAddrs(); cpu.debugInstruction.add(hook);
            // the reference: nothing but the patch's own code writes the patch's free
            // memory, apart from the station's line heap there (SNG47's LL9)
            if (ref) {
                const c0 = RP.code[0][0], c1 = RP.region[0], f0 = c0, heap = RP.lso;
                cpu.debugWrite.add(x => {
                    if (x < f0 || x >= 0x0d00 || (x >= c1 && x < heap + 101)) return false;   // (the parked sun, which MAL1 copies back, and the heap)
                    const p = cpu.oldPcArray[cpu.oldPcIndex];
                    if (!(p >= c0 && p < c1) && strays.length < 10) strays.push(`&${x.toString(16)} by &${p.toString(16)}`);
                    return false;
                });
            }
        }
        // the per-iteration checks, for the iteration that has just ended
        if (flying() && rb(sy.SSPR) && rb(pf) & 0x40) fail.push(`${who} ${i}: SUNPF bit 6 set at MLOOP`);
        if (flying() && rb(sy.SSPR) && !(rb(pf) & 0x80)) fail.push(`${who} ${i}: the station is here and the sun is not parked`);
        if (flying() && rb(sy.SSPR) && rb(sy.FRIN + 1) !== SST) fail.push(`${who} ${i}: SSPR set, slot 1 is ${rb(sy.FRIN + 1)}`);
        // (the flight iterations: one TT100 since the last MLOOP, in flight before and after)
        const flight = ttIter === i - 1 && tt === 1 && wasFlight && flying(), moved = mvIter === i - 1 ? mv : 0;
        if (flight && lastSun && moved !== 1) fail.push(`${who} ${i - 1}: a sun existed and MVEIT moved it ${moved} times`);
        if (flight && !lastSun && moved) fail.push(`${who} ${i - 1}: no sun, and MVEIT moved one ${moved} times`);
        if (flying() && rb(sy.SSPR) && rb(pf) & 0x80) count.parkedIters++;
        // the scene
        if (scene === "zone" && flying() && i - lastAct > 250) {
            if (rb(sy.SSPR) && (P.phase === "combat" || P.phase === "hyper")) leave();
            else if (!rb(sy.SSPR) && rb(sy.FRIN + 1) === 129 && (P.phase === "combat" || P.phase === "approach")) approach();
        }
        if (scene === "full" && flying() && rb(sy.SSPR) && !count.filled && i > 30) fill();
        if (scene === "handback" && flying() && rb(sy.SSPR)) {
            if (!ev && i > 20) { ev = i; sunAhead(); }
            else if (ev && i < ev + 40) sunAhead();
            else if (ev && i === ev + 40) { leave(); count.handbacks++; }
        }
        if (scene === "events" && flying() && !rb(sy.SSPR) && rb(sy.FRIN + 1) === 129 && i - lastAct > 300 && P.phase === "approach") approach();
        else if (scene === "events" && flying() && rb(sy.SSPR) && i - lastAct > 300) {
            const k = ev++ % 6;
            lastAct = i;
            if (k === 0) { ram[sy.ESCP] = 0xff; scripted = { until: i + 3, keys: [K.ESC] }; count.escapes = (count.escapes || 0) + 1; }
            // (the mis-jump straight after the escape pod's docking and relaunch, and the
            // jump after the crash's new game: each with a target chosen while docked, not
            // the system just reached, which the pilot would not jump to)
            else if (k === 1) { ram[sy.PATG] = 0xff; P.phase = "hyper"; P.hyperAt = -1; misjump = i + 400; count.misjumps = (count.misjumps || 0) + 1; }
            else if (k === 2) { putc(ram, K1, 0); putc(ram, K1 + 3, 0); putc(ram, K1 + 6, 200); ram[sy.DELTA] = 30; count.crashes = (count.crashes || 0) + 1; }
            else if (k === 3) { P.phase = "hyper"; P.hyperAt = -1; count.jumps = (count.jumps || 0) + 1; }
            // the energy bomb and the E.C.M. with the sun parked (MA24 and the slots'
            // effects skip negative types), then the galactic hyperdrive (CTRL held at
            // hyp's test, then H)
            else if (k === 4) { ram[sy.BOMB] = 0x7f; ram[sy.ECM] = 0xff; scripted = { until: i + 8, keys: [K.TAB], alt: [K.E] }; count.bombs = (count.bombs || 0) + 1; }
            else { ram[sy.GHYP] = 0xff; ghyp = i + 6; scripted = { until: i + 4, keys: [K.H] }; count.ghyps = (count.ghyps || 0) + 1; }
        }
        lastSun = sunExists(); wasFlight = flying();
    }
    const wordAt = x => { if (x === undefined) return null; const v = rb(x) | rb(x + 1) << 8; return v > 32767 ? v - 65536 : v; };
    let lastSun = false, wasFlight = false, scripted = null, misjump = -1, ghyp = -1;
    const keys = c => {
        if (scripted && iter <= scripted.until) return scripted.alt && iter > scripted.until - 4 ? scripted.alt : scripted.keys;
        return pilot.keys(c);
    };
    // (CTRL, DKS5's key 1, held at TT18's mis-jump test only: not at the H key, which would
    // make it a galactic jump)
    const dks = c => (misjump >= iter && c.key === 0x01 && c.site === "ee5") || (ghyp >= iter && c.key === 0x01 && c.site !== "ee5") ? true
        : pilot.dks ? pilot.dks(c) : false;
    const r = await runElite({ disc, syms: sy, pilot: { keys, dks, observe: pilot.observe, P }, iters: ITERS[scene] * (+(a.iters || 1)), maxSecs: 6 * ITERS[scene],
        patch: patchCommander, refPatch: ref ? RP : null, onIter, seedBoot });
    if (strays.length) fail.push(`${who}: the patch's memory written by other code: ${strays.join(", ")}`);
    return { r, fail, count, sunPos, arrivals: Object.keys(arrivals).length };
}

// the comparison, as mcompare.mjs --loose
function compare(ref, cand) {
    const ex = excludeSet(rsy, [TIMING_EXCLUDE, RELOC_EXCLUDE, DRAW_EXCLUDE]);
    const offAddr = []; for (const [s, n] of ref.regions) for (let i = 0; i < n; i++) offAddr.push(s + i);
    const kOff = offAddr.indexOf(rsy["K%"]), fOff = offAddr.indexOf(rsy.FRIN);
    const empty = (sn, o) => o >= kOff && o < kOff + 12 * NI && sn[fOff + Math.floor((o - kOff) / NI)] === 0;
    if (ref.regions.map(r => r[1] + r[2]).join() !== cand.regions.map(r => r[1] + r[2]).join()) return "the regions differ";
    const n = Math.min(ref.snaps.length, cand.snaps.length);
    for (let i = 0; i < n; i++) for (let o = 0; o < offAddr.length; o++)
        if (ref.snaps[i][o] !== cand.snaps[i][o] && !ex.has(offAddr[o]) && !empty(ref.snaps[i], o))
            return `iteration ${i}: &${offAddr[o].toString(16)} ref &${ref.snaps[i][o].toString(16)} cand &${cand.snaps[i][o].toString(16)}`;
    if (ref.iters !== cand.iters || ref.error || cand.error) return `incomplete (ref ${ref.iters}, cand ${cand.iters} ${ref.error || ""} ${cand.error || ""})`;
    return null;
}

let ok = true;
const report = {};
for (const scene of SCENES) {
    const t0 = Date.now();
    const R = await fly(scene, "ref", REF, rsy, true);
    // the candidate's boot leftovers from the reference's state at TT170 (as mcompare.mjs --seed boot)
    const seedBoot = (cregions, written, rb) => {
        const out = []; let o = 0;
        for (const [ra, n, name] of R.r.regions) {
            const c = cregions.find(q => q[2] === name);
            if (c && c[1] === n) for (let i = 0; i < n; i++) if (!written.has(c[0] + i) && rb(c[0] + i) !== R.r.init[o + i]) out.push([c[0] + i, [R.r.init[o + i]]]);
            o += n;
        }
        return out;
    };
    const C = await fly(scene, "cand", CAND, csy, false, seedBoot);
    const div = compare(R.r, C.r);
    const fails = [...R.fail, ...C.fail];
    if (div) fails.unshift(`game state: ${div}`);
    if ((scene === "zone" || scene === "handback") && !(R.count.SUNUP && R.count.SUNBK)) fails.push("the sun was not parked (SUNUP) and restored (SUNBK)");
    if (scene === "handback") {
        if (!C.count.handbacks) fails.push("no hand-back");
        for (let k = 1; k < C.sunPos.length; k++) {
            const [i0, , x0, y0, , on0] = C.sunPos[k - 1], [i1, s1, x1, y1, , on1] = C.sunPos[k];
            if (!on0 || !on1) fails.push(`iteration ${i1}: the sun not drawn (slot 1 ${s1})`);
            else if (Math.abs(x1 - x0) > 2 || Math.abs(y1 - y0) > 2) fails.push(`iteration ${i1}: the sun jumped from (${x0}, ${y0}) to (${x1}, ${y1})`);
        }
    }
    if (scene === "full" && !(R.count.killsParked > 0)) fails.push("no ship removed below the parked sun");
    if (scene === "full" && !(R.count.DOEXP > 0)) fails.push("no explosion cloud (DOEXP): the clouds' seed is not exercised");
    if (scene === "events") for (const n of ["ESCAPEParked", "MJPParked", "DEATHParked", "TITLE", "TT18Parked", "DOENTRY", "GhyParked", "BOMBONParked", "ECBLB2Parked"])
        if (!R.count[n]) fails.push(`no ${n}`);
    if (scene === "zone" && !(R.count.launchChecked > 0)) fails.push("no launch from a system the scene arrived at (SUNLAU against SOLAR)");
    console.log(`${scene}: ${R.r.iters} iterations, ${((Date.now() - t0) / 1000).toFixed(0)} s; ref ${JSON.stringify(R.count)}; cand ${JSON.stringify(C.count)}; arrivals ${R.arrivals}`);
    if (scene === "handback") console.log(`  the sun on the screen (iteration, slot 1, x, y, r, on): ${C.sunPos.map(p => p.join(",")).join(" ")}`);
    for (const f of fails.slice(0, 20)) console.log(`  FAIL ${f}`);
    if (fails.length) ok = false;
    report[scene] = { ref: R.count, cand: C.count, fails, sunPos: C.sunPos };
}
writeFileSync(`${OUT}/sunslot.json`, JSON.stringify(report, null, 1));
console.log(ok ? "SUNSLOT PASS" : "SUNSLOT FAIL");
process.exit(ok ? 0 : 1);
