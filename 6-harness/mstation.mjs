// Regression test: the station in front of a planet just over 65536 away must
// be drawn (a docking run with the planet behind the station). The scene is
// the user's save state's (2026-10-23, the 25 fps disc), as the Tube's
// tstation.mjs (the Tube version's) puts it: the planet at z = &10636 (67126), the
// Coriolis station dead ahead at z = 3619, a transporter. F_PLANET recorded
// 16 bits of the planet's z (INWK+7, INWK+6), so f_behind read the planet as
// 1590 away, nearer than the station, and the station, inside the planet's
// disc on screen, was hidden.
//
// node 6-harness/mstation.mjs [--disc d] [--syms s] [--out dir]
//
// Boots the build as mredock.mjs does (SHIFT+BREAK, a new commander,
// launch with f0); at the next MLOOP the scene's ship slots (K%'s first three,
// FRIN to JUNK) are put in and the speed set to 0. Over the next 8 main-loop
// iterations every frame that records the station (F_STYP 2) must draw it
// (f_ship gets past f_behind to fsh_nf0). Prints the counts and
// "STATION PASS" or "STATION FAIL"; exit status 0 only on PASS; a screenshot
// of the scene in <out>/station.png.
import { MachineSession } from "./jsbeeb.mjs";
import { BBC } from "./jsbeeb.mjs";
import { loadSyms, CAND_DISC, CAND_SYMS, WORK, mapOfLabel, physRead } from "./mlib.mjs";
import { writeFileSync, mkdirSync } from "fs";
import { parseArgs } from "./args.mjs";
const a = parseArgs({ disc: "value", syms: "value", out: "value" });
const sy = loadSyms(a.syms || CAND_SYMS);
const OUT = a.out || `${WORK}station`; mkdirSync(OUT, { recursive: true });
// the scene: K% (three slots: planet, station, transporter), FRIN .. JUNK
const KS = "000000a546003606014bca1db806198eba454ab8835d12c4102d5c00007f7f100000000024000000010000230e0000000020005a9cd0852e4590b52fc14b839b0000ff001e817e0af000000000fc06001d2f0000000018005c009100dc001800dd00108d820a00008018f16b072061";
const WS = "80020a0000000000000000000000000100000000000000010000000000000000000000000000000000000000000000";
const s = new MachineSession("Master"); await s.initialise(); await s.boot(30);
s.loadDisc(a.disc || CAND_DISC); s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
const cpu = s._machine.processor; const secs = n => s.runFor(2000000 * n);
const key = async (k, hold = 0.2, after = 1) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
// a label's hook: its address with its bank paged in (ROMSEL's bits 0-3)
const at = (pc, name) => { if (pc !== sy[name]) return false; const b = sy.__bank[name]; return b === undefined || (cpu.romsel & 15) === (b & 15); };
const M6 = mapOfLabel(sy, "F_STYP");
await secs(28); await key("N"); await secs(3); await key("SPACE"); await secs(4);
await key("F0", 0.2, 12);
// at MLOOP: the scene in
let atLoop = false, phase = 0, iters = 0, recorded = 0, drawn = 0, frames = 0;
cpu.debugInstruction.add(pc => {
    if (phase === 0) { if (at(pc, "MLOOP")) atLoop = true; return false; }
    if (at(pc, "MLOOP")) iters++;
    if (at(pc, "f_ships")) frames++;
    if (at(pc, "f_ship") && physRead(cpu, M6, sy.F_STYP + cpu.a) === 2) recorded++;
    if (at(pc, "fsh_nf0") && physRead(cpu, M6, sy.F_STYP + physRead(cpu, M6, sy.f_si)) === 2) drawn++;
    return false;
});
for (let k = 0; k < 200 && !atLoop; k++) await s.runFor(20000);
if (!atLoop) { console.log("STATION FAIL: never reached MLOOP"); process.exit(1); }
const ram = cpu.ramRomOs;
Buffer.from(KS, "hex").forEach((b, i) => { ram[sy["K%"] + i] = b; });
Buffer.from(WS, "hex").forEach((b, i) => { ram[sy.FRIN + i] = b; });
ram[sy.DELTA] = 0; ram[sy.QQ11] = 0; ram[sy.VIEW] = 0;
phase = 1;
// over 8 iterations: the station recorded, and drawn
for (let k = 0; k < 2000 && iters < 8; k++) await s.runFor(20000);
writeFileSync(`${OUT}/station.png`, await s.screenshotActive({ scale: 1 }));
const ok = recorded > 0 && drawn === recorded;
console.log(`${iters} iterations, ${frames} frames with ships: the station recorded in ${recorded}, drawn in ${drawn}`);
console.log(ok ? "STATION PASS" : "STATION FAIL (hidden behind the planet)");
process.exit(ok ? 0 : 1);
