// Regression test: dock, launch, dock again (the docking computer), from a
// fresh boot, with real key presses. node 6-harness/mredock.mjs [--disc d]
// [--syms s] [--out dir]. Exit status 0 if both dockings happen (DOENTRY
// reached twice) within 90 emulated seconds each; screenshots of each stage.
import { MachineSession } from "./jsbeeb.mjs";
import { BBC } from "./jsbeeb.mjs";
import { loadSyms, CAND_DISC, CAND_SYMS, WORK } from "./mlib.mjs";
import { writeFileSync, mkdirSync } from "fs";
import { parseArgs } from "./args.mjs";
const a = parseArgs({ disc: "value", syms: "value", out: "value" });
const sy = loadSyms(a.syms || CAND_SYMS);
const OUT = a.out || `${WORK}redock`; mkdirSync(OUT, { recursive: true });
const s = new MachineSession("Master"); await s.initialise(); await s.boot(30);
s.loadDisc(a.disc || CAND_DISC); s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
const cpu = s._machine.processor; const secs = n => s.runFor(2000000 * n);
const key = async (k, hold = 0.2, after = 1) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
const snap = async n => writeFileSync(`${OUT}/${n}.png`, await s.screenshotActive({ scale: 1 }));
const DOE = sy.DOENTRY_C ?? sy.DOENTRY;
let docks = 0;
cpu.debugInstruction.add(pc => { if (pc === DOE && (sy.DOENTRY_C === undefined || (cpu.romsel & 15) === 7)) docks++; return false; });
await secs(28); await key("N"); await secs(3); await key("SPACE"); await secs(4);
cpu.ramRomOs[sy.DKCMP] = 0xff;
let ok = true;
for (let n = 1; n <= 2; n++) {
    await key("F0", 0.2, 10); await snap(`${n}-launched`);
    await key("C", 0.2, 1);
    let t = 0; while (docks < n && t < 90) { await secs(1); t++; if (t === 10) await snap(`${n}-docking`); }
    console.log(`docking ${n}: ${docks >= n ? `docked after ${t} s` : "NOT DOCKED after 90 s"}`);
    if (docks < n) { ok = false; await snap(`${n}-failed`); break; }
    await secs(8); await key("SPACE", 0.2, 3); await snap(`${n}-docked`);
}
console.log(ok ? "REDOCK PASS" : "REDOCK FAIL");
process.exit(ok ? 0 : 1);
