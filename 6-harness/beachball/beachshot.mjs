#!/usr/bin/env node
// beachshot.mjs: find the beach ball (meridian) planets in a session's replay, and
// screenshot them. The candidate replays an agentplay session's input log read for
// read (as the agentplay tools' fbreplay.mjs and film.mjs do; 6-harness/README.md), headless.
//
//   node 6-harness/beachball/beachshot.mjs --log RUN/inputs.jsonl --cand DISC --csyms SYMS
//        --out DIR [--from I] [--to I] [--shots I1,I2,...] [--every N]
//
// After each frame (hframe's return from G_FRAME) it records, while PM_OK is set (the
// meridian window computed this frame's beach ball), the iteration, the radius PM_R,
// the centre (PM_CX, PM_CY in bank 7) and the planet's vectors (INWK at PM_HOOK time
// is gone by then: the window's own copy of the constants is not needed here), into
// DIR/scan.jsonl. With --shots, the picture shown a frame and a half after each listed
// iteration's frame is saved as DIR/beach-<iteration>.png (the frame that iteration
// drew, once its flip has happened). Stops at --to or the log's end.
import { EliteMachine, loadSyms, CYCLES_PER_FRAME } from "../agentplay/lib.mjs";
import { physRead } from "../mlib.mjs";
import { DEFAULTS, seedBytes } from "../agentplay/session.mjs";
import { COMMANDERS } from "../agentplay/styles.mjs";
import { parseArgs } from "../args.mjs";
import { readFileSync, writeFileSync, mkdirSync, appendFileSync } from "fs";

const a = parseArgs({ log: "value", out: "value", cand: "value", csyms: "value", from: "value", to: "value", shots: "value" });
if (!a.log || !a.out || !a.cand || !a.csyms) { console.error("--log, --out, --cand and --csyms are required"); process.exit(2); }
const OUT = a.out;
mkdirSync(OUT, { recursive: true });
const FROM = +(a.from || 0), TO = +(a.to || 1e9);
const SHOTS = new Set((a.shots || "").split(",").filter(Boolean).map(Number));

// ---- the log (all of it)
const L = { rlog: new Map(), rjoy: [[], []], ptr: [0, 0], pokes: new Map(), header: null };
for (const l of readFileSync(a.log, "utf8").split("\n")) {
    if (!l) continue;
    const e = JSON.parse(l);
    if (e.header) L.header = e;
    else if (e.p !== undefined) L.rlog.set(e.p, e);
    else if (e.j !== undefined) L.rjoy[e.w].push([e.j, e.v]);
    else if (e.poke !== undefined) L.pokes.set(e.poke, e.v);
}
const H = L.header;
const rsy = loadSyms(H.rsyms || DEFAULTS.rsyms), csy = loadSyms(a.csyms);
const rand = H.seed !== undefined && H.seed !== null ? seedBytes(H.seed) : null;
const cmdr = COMMANDERS[H.commander || "jameson"];
const patch = cmdr.patch ? m => cmdr.patch(m) : null;
const ref = new EliteMachine({ name: "ref", disc: H.ref || DEFAULTS.ref, syms: rsy, input: { rdkey: () => [], dks5: () => false, joy: () => 0x80 }, rand, patch });
await ref.boot();
for (let k = 0; k < 10000 && !ref.started; k++) ref.run(CYCLES_PER_FRAME);
if (!ref.started) { console.error("the reference never reached TT170"); process.exit(2); }
let mismatches = 0;
const cand = new EliteMachine({ name: "cand", disc: a.cand, syms: csy, rand, patch, seedFrom: ref, workarounds: H.workarounds || [],
    input: {
        rdkey(ctx) { const e = L.rlog.get(ctx.poll); if (e && (e.t !== "r" || e.s !== ctx.site)) mismatches++; return e?.k || []; },
        dks5(ctx) { const e = L.rlog.get(ctx.poll); if (e && (e.t !== "d" || e.key !== ctx.key)) mismatches++; return !!(e && e.t === "d"); },
        joy(ctx) {
            const l = L.rjoy[ctx.which];
            while (L.ptr[ctx.which] + 1 < l.length && l[L.ptr[ctx.which] + 1][0] <= ctx.joy) L.ptr[ctx.which]++;
            const e = l[L.ptr[ctx.which]];
            return e && e[0] <= ctx.joy ? e[1] : 0x80;
        },
    } });
await cand.boot();
cand.pokes = L.pokes;
const cpu = cand.cpu, sy = cand.sy, ram = cand.ram;
const b7 = (n, o = 0) => physRead(cpu, 7, sy[n] + o);
const s16 = (lo, hi) => { const v = lo | hi << 8; return v >= 32768 ? v - 65536 : v; };
const HF = sy.hframe + 7;
writeFileSync(`${OUT}/scan.jsonl`, "");
let shootAt = null, nrec = 0;
cpu.debugInstruction.add(pc => {
    if (pc === HF && cand.iter >= FROM && ram[sy.QQ11] === 0 && ram[sy.PM_OK] & 0x80) {
        const r = { it: cand.iter, r: ram[sy.PM_R], cx: s16(b7("PM_CX"), b7("PM_CX", 1)), cy: s16(b7("PM_CY"), b7("PM_CY", 1)) };
        appendFileSync(`${OUT}/scan.jsonl`, JSON.stringify(r) + "\n");
        nrec++;
        if (SHOTS.has(cand.iter)) shootAt = cand.iter;
    }
    return false;
});
let last = Date.now();
for (;;) {
    if (shootAt !== null) {
        const it = shootAt; shootAt = null;
        cand.renderAll();
        cand.run(CYCLES_PER_FRAME * 1.5);
        writeFileSync(`${OUT}/beach-${it}.png`, await cand.screenshot());
        cand.s._video.frameSkipCount = 25;
        SHOTS.delete(it);
        console.log(`shot ${it}`);
        if (!SHOTS.size && a.shots) break;
    }
    const r = cand.run(CYCLES_PER_FRAME);
    cand.snaps.length = 0;
    if (cand.iter >= TO || r === "blocked") break;
    if (Date.now() - last > 30000) { last = Date.now(); console.log(`it ${cand.iter}, ${nrec} beach ball frames`); }
}
console.log(`stopped at iteration ${cand.iter}; ${nrec} beach ball frames; ${mismatches} read mismatches`);
process.exit(0);
