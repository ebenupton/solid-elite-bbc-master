#!/usr/bin/env node
// itcyc.mjs: cycles of every iteration FROM..TO of a replayed run (one line each:
// iteration, cycles), and how many of them ran in K mode (KMODE bit 7 at MLOOP)
//   node 6-harness/solidspan/itcyc.mjs --log L --cand D --csyms S --from I --to J --out FILE
import { replayMachine, CYCLES_PER_FRAME } from "./common.mjs";
import { parseArgs } from "../args.mjs";
import { writeFileSync } from "fs";
const a = parseArgs({ log: "value", cand: "value", csyms: "value", from: "value", to: "value", out: "value" });
const m = await replayMachine(a.log, a.cand, a.csyms);
const at = [], km = [];
m.onIter = mm => { at[mm.iter] = mm.cyclesNow(); km[mm.iter] = mm.sy.KMODE !== undefined ? mm.ram[mm.sy.KMODE] >> 7 : 0; };
while (m.iter <= +a.to) { m.run(CYCLES_PER_FRAME); m.snaps.length = 0; }
const out = [];
for (let i = +a.from; i < +a.to; i++) if (at[i + 1] !== undefined && at[i] !== undefined) out.push(`${i} ${at[i + 1] - at[i]} ${km[i + 1]}`);
writeFileSync(a.out, out.join("\n") + "\n");
process.exit(0);
