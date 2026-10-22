#!/usr/bin/env node
// szprobe.mjs: the station's recorded z (F_SZH, F_SZL) at each F_FRAME, iterations FROM..TO
import { replayMachine, CYCLES_PER_FRAME } from "./common.mjs";
import { mapAt } from "../mlib.mjs";
import { parseArgs } from "../args.mjs";
const a = parseArgs({ log: "value", cand: "value", csyms: "value", from: "value", to: "value" });
const m = await replayMachine(a.log, a.cand, a.csyms);
const cpu = m.cpu, sy = m.sy;
const rd = ad => cpu.readmem(ad);
cpu.debugInstruction.add(pc => {
    if (pc === sy.F_FRAME && mapAt(cpu.romsel, pc) === 6 && m.iter >= +a.from) {
        const n = rd(sy.F_NSHIP), out = [];
        for (let i = 0; i < n; i++) out.push(`${rd(sy.F_STYP + i)}:${rd(sy.F_SZH + i)}.${rd(sy.F_SZL + i)}`);
        console.log(m.iter, out.join(" "));
    }
    return false;
});
while (m.iter <= +a.to) { m.run(CYCLES_PER_FRAME); m.snaps.length = 0; }
process.exit(0);
