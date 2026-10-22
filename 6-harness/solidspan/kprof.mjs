#!/usr/bin/env node
// kprof.mjs: cycles by label (the nearest label at or below each instruction, in its
// mapping) over iterations FROM..TO of a replayed run on a Master build.
//   node 6-harness/solidspan/kprof.mjs --log run1.jsonl --cand DISC --csyms SYMS --from I --to J [--top N]
import { replayMachine, CYCLES_PER_FRAME } from "./common.mjs";
import { parseArgs } from "../args.mjs";
const a = parseArgs({ log: "value", cand: "value", csyms: "value", from: "value", to: "value", top: "value" });
const FROM = +a.from, TO = +a.to;
const m = await replayMachine(a.log, a.cand, a.csyms);
const cpu = m.cpu, acc = new Map();
let last = null, lastc = 0, on = false, t0 = 0, t1 = 0;
// (on exactly from iteration FROM's start to TO's: onIter is called at MLOOP)
m.onIter = mm => { if (mm.iter === FROM) { on = true; t0 = mm.cyclesNow(); last = null; } if (mm.iter === TO) { on = false; t1 = mm.cyclesNow(); } };
while (m.iter < FROM - 1) { m.run(CYCLES_PER_FRAME); m.snaps.length = 0; }
cpu.debugInstruction.add(pc => {
    if (!on) return false;
    const c = m.cyclesNow();
    if (last !== null) acc.set(last, (acc.get(last) || 0) + c - lastc);
    last = m.labelOf(pc) || "?" + pc.toString(16); lastc = c;
    return false;
});
while (m.iter <= TO) { m.run(CYCLES_PER_FRAME); m.snaps.length = 0; }
const tot = t1 - t0, n = TO - FROM;
console.log(`iterations ${FROM}..${TO}: ${(tot / n).toFixed(0)} cycles an iteration`);
for (const [k, v] of [...acc].sort((x, y) => y[1] - x[1]).slice(0, +(a.top || 40))) console.log(`${(v / n).toFixed(0).padStart(8)} ${k}`);
process.exit(0);
