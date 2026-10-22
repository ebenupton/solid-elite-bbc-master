#!/usr/bin/env node
// sdump.mjs: replay a run on a Master build and, at each frame's end (hframe's return
// from G_FRAME), append the buffer just drawn to OUT: per frame a 4-byte header
// (iteration lo, hi, frame count lo, buffer) then the 12K of &4000-&6FFF.
//   node 6-harness/solidspan/sdump.mjs --log run1.jsonl --cand DISC --csyms SYMS --from I --to J --out FILE
import { replayMachine, CYCLES_PER_FRAME } from "./common.mjs";
import { parseArgs } from "../args.mjs";
import { openSync, writeSync, closeSync } from "fs";
const a = parseArgs({ log: "value", cand: "value", csyms: "value", from: "value", to: "value", out: "value" });
const FROM = +a.from, TO = +a.to;
const m = await replayMachine(a.log, a.cand, a.csyms);
const cpu = m.cpu, HF = m.sy.hframe + 7, GP = m.sy.GPEND, fd = openSync(a.out, "w"); let n = 0;
cpu.debugInstruction.add(pc => {
    if (pc === HF && m.iter >= FROM && m.iter <= TO) {
        const b = cpu.ramRomOs[GP];
        const h = Buffer.from([m.iter & 255, m.iter >> 8, n & 255, b]);
        writeSync(fd, h); writeSync(fd, cpu.ramRomOs.subarray(b ? 0xc000 : 0x4000, b ? 0xf000 : 0x7000)); n++;
    }
    return false;
});
while (m.iter <= TO) { m.run(CYCLES_PER_FRAME); m.snaps.length = 0; }
closeSync(fd);
console.log(`${n} frames written, iterations ${FROM}..${TO}`);
process.exit(0);
