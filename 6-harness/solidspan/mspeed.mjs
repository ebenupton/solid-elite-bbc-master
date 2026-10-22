#!/usr/bin/env node
// mspeed.mjs: iterations per emulated second over windows of a replayed run on a
// Master build (tube/tools/tspeed.mjs's --kind m, on its own).
//   node 6-harness/solidspan/mspeed.mjs --log run1.jsonl --cand DISC --csyms SYMS [--windows 1000-1400,3420-3550,0-3550]
import { replayMachine, CYCLES_PER_FRAME } from "./common.mjs";
import { parseArgs } from "../args.mjs";
const a = parseArgs({ log: "value", cand: "value", csyms: "value", windows: "value" });
if (!a.log || !a.cand || !a.csyms) { console.error("--log, --cand and --csyms are required"); process.exit(2); }
const W = (a.windows || "1000-1400,3420-3550,0-3550").split(",").map(s => s.split("-").map(Number));
const last = Math.max(...W.map(w => w[1]));
const m = await replayMachine(a.log, a.cand, a.csyms);
const at = [];
m.onIter = mm => { at[mm.iter] = mm.cyclesNow(); };
while (m.iter <= last) { m.run(CYCLES_PER_FRAME); m.snaps.length = 0; }
for (const [x, y] of W) {
    const cyc = at[y] - at[x];
    console.log(`iterations ${x}-${y}: ${(cyc / (y - x)).toFixed(0)} cycles an iteration, ${((y - x) * 2e6 / cyc).toFixed(2)} it/s`);
}
process.exit(0);
