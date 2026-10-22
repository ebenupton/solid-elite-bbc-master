#!/usr/bin/env node
// fbhash.mjs: the pixel oracle (as the Tube branch's fbreplay.mjs): replay a run on a
// Master build and hash both screen buffers (main RAM's &4000-&6FFF, then shadow
// RAM's) at each frame's end (hframe's return from G_FRAME), keyed "iteration.n" (n a
// running frame count); compare two builds' files with fbcmp.mjs.
//   node 6-harness/solidspan/fbhash.mjs --log run1.jsonl --cand DISC --csyms SYMS --from I --to J --out FILE.json
import { replayMachine, CYCLES_PER_FRAME } from "./common.mjs";
import { parseArgs } from "../args.mjs";
import { writeFileSync } from "fs";
import { createHash } from "crypto";
const a = parseArgs({ log: "value", cand: "value", csyms: "value", from: "value", to: "value", out: "value" });
const FROM = +a.from, TO = +a.to;
const m = await replayMachine(a.log, a.cand, a.csyms);
const cpu = m.cpu, HF = m.sy.hframe + 7, res = {};
let n = 0;
cpu.debugInstruction.add(pc => {
    if (pc === HF && m.iter >= FROM) {
        const h = createHash("sha1");
        h.update(cpu.ramRomOs.subarray(0x4000, 0x7000)); h.update(cpu.ramRomOs.subarray(0xc000, 0xf000));
        res[`${m.iter}.${n++}`] = h.digest("hex").slice(0, 16);
    }
    return false;
});
while (m.iter <= TO) { m.run(CYCLES_PER_FRAME); m.snaps.length = 0; }
writeFileSync(a.out, JSON.stringify(res));
console.log(`${Object.keys(res).length} frames hashed, iterations ${FROM}..${m.iter}`);
process.exit(0);
