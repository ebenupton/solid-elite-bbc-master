#!/usr/bin/env node
// srec.mjs: replay a run on a Master build and record, for iterations FROM..TO, what
// each frame draws, as JSON lines (one per frame):
//   {it, b, P: [[y, xl, xr, col], ...]   polygon spans in drawing order (phase B,
//                                         at pb_d2_e/pb_d2_o: X = XL, R_XR, the row
//                                         pair's colour RZ_CE / RZ_CO)
//    O: [[y0, y1], ...]                   rows touched by anything else (R_LINE's
//                                         end points' rows, R_DOT, R_SPAN, R_MARKDIRTY)
//    with the buffer drawn appended to OUT.bin as in sdump.mjs}
//   node 6-harness/solidspan/srec.mjs --log run1.jsonl --cand DISC --csyms SYMS --from I --to J --out PREFIX
import { replayMachine, CYCLES_PER_FRAME } from "./common.mjs";
import { mapAt } from "../mlib.mjs";
import { parseArgs } from "../args.mjs";
import { openSync, writeSync, closeSync } from "fs";
const a = parseArgs({ log: "value", cand: "value", csyms: "value", from: "value", to: "value", out: "value" });
const FROM = +a.from, TO = +a.to;
const m = await replayMachine(a.log, a.cand, a.csyms);
const cpu = m.cpu, sy = m.sy, ram = cpu.ramRomOs;
const HF = sy.hframe + 7, GP = sy.GPEND;
const fj = openSync(a.out + ".jsonl", "w"), fb = openSync(a.out + ".bin", "w");
let fr = null, n = 0;
const s16 = (lo, hi) => { const v = ram[lo] | ram[hi] << 8; return v & 0x8000 ? v - 0x10000 : v; };
cpu.debugInstruction.add(pc => {
    if (m.iter < FROM || m.iter > TO) return false;
    const map = mapAt(cpu.romsel, pc);
    if (pc === sy.F_FRAME && map === 6) { fr = { it: m.iter, b: null, P: [], O: [] }; return false; }
    if (!fr) return false;
    if ((pc === sy.pb_d2_e || pc === sy.pb_d2_o) && map === "A") {
        fr.P.push([cpu.y, cpu.x, ram[9], pc === sy.pb_d2_e ? ram[0x18] : ram[0x19]]);
    } else if (pc === sy.R_LINE && map === "A") {
        const y0 = s16(sy.R_Y0, sy.R_Y0 + 1), y1 = s16(sy.R_Y1, sy.R_Y1 + 1);
        fr.O.push([Math.min(y0, y1), Math.max(y0, y1), "L"]);
    } else if (pc === sy.R_DOT && map !== "A") { fr.O.push([cpu.y, cpu.y + 1, "D"]);
    } else if (pc === sy.R_SPAN && map !== "A") { fr.O.push([cpu.y, cpu.y, "S"]);
    } else if (pc === sy.R_MARKDIRTY && map !== "A") { fr.O.push([cpu.y, cpu.y, "M"]);
    } else if (pc === sy.f_glyph && map === 6) { fr.O.push([-1, -1, "G"]);
    } else if (pc === HF) {
        const b = ram[GP]; fr.b = b;
        writeSync(fj, JSON.stringify(fr) + "\n");
        writeSync(fb, Buffer.from([m.iter & 255, m.iter >> 8, n & 255, b]));
        writeSync(fb, ram.subarray(b ? 0xc000 : 0x4000, b ? 0xf000 : 0x7000)); n++; fr = null;
    }
    return false;
});
while (m.iter <= TO) { m.run(CYCLES_PER_FRAME); m.snaps.length = 0; }
closeSync(fj); closeSync(fb);
console.log(`${n} frames recorded, iterations ${FROM}..${TO}`);
process.exit(0);
