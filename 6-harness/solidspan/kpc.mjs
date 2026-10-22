#!/usr/bin/env node
// kpc.mjs: cycles by PC within an address range of one mapping (e.g. bank 7's kept
// rows' code), over iterations FROM..TO, with the symbols at or below each PC.
//   node 6-harness/solidspan/kpc.mjs --log L --cand D --csyms S --from I --to J --lo HEX --hi HEX --map 7
import { replayMachine, CYCLES_PER_FRAME } from "./common.mjs";
import { mapAt } from "../mlib.mjs";
import { parseArgs } from "../args.mjs";
const a = parseArgs({ log: "value", cand: "value", csyms: "value", from: "value", to: "value", lo: "value", hi: "value", map: "value" });
const FROM = +a.from, TO = +a.to, LO = parseInt(a.lo, 16), HI = parseInt(a.hi, 16), MAP = a.map;
const m = await replayMachine(a.log, a.cand, a.csyms);
const cpu = m.cpu, acc = new Map(), cnt = new Map();
let last = -1, lastc = 0;
while (m.iter < FROM) { m.run(CYCLES_PER_FRAME); m.snaps.length = 0; }
cpu.debugInstruction.add(pc => {
    const c = m.cyclesNow();
    if (last >= 0) { acc.set(last, (acc.get(last) || 0) + c - lastc); cnt.set(last, (cnt.get(last) || 0) + 1); }
    last = (pc >= LO && pc < HI && String(mapAt(cpu.romsel, pc)) === MAP) ? pc : -1; lastc = c;
    return false;
});
while (m.iter < TO) { m.run(CYCLES_PER_FRAME); m.snaps.length = 0; }
const n = TO - FROM, syms = Object.entries(m.sy).filter(([k, v]) => v >= LO && v < HI).sort((x, y) => x[1] - y[1]);
let tot = 0;
for (const pc of [...acc.keys()].sort((x, y) => x - y)) {
    const lab = syms.filter(([k, v]) => v <= pc).pop();
    tot += acc.get(pc);
    console.log(pc.toString(16), (acc.get(pc) / n).toFixed(0).padStart(7), (cnt.get(pc) / n).toFixed(1).padStart(7), lab ? `${lab[0]}+${pc - lab[1]}` : "");
}
console.log("total", (tot / n).toFixed(0));
process.exit(0);
