// Screenshots of the ship hangar in chosen configurations, from one boot:
// node 6-harness/mhangar.mjs OUTDIR CONFIG...   (DISC, SYMS override the build)
// New game, launch; then for each CONFIG, at a TT100 (flight) the PC is set to
// GOIN (dock: the docking tunnel, then HALL's hangar), with RAND (&02-&05) set
// first so that HALL's choice is repeatable, and any pokes; a screenshot is
// taken once HALL has drawn the hangar (at DELAY), then F0 launches again.
// CONFIG: name:r0,r1,r2,r3[:sym+off=val,...] (RAND's four bytes, decimal or 0x).
// Prints the cycles from HALL to its DELAY (the hangar's whole drawing) and,
// for the filled build, inside G_HANGAR (the frame).
import { MachineSession, BBC } from "./jsbeeb.mjs";
import { loadSyms, CAND_DISC, CAND_SYMS } from "./mlib.mjs";
import { writeFileSync, mkdirSync } from "fs";
const [OUT, ...CONFIGS] = process.argv.slice(2); mkdirSync(OUT, { recursive: true });
const sy = loadSyms(process.env.SYMS || CAND_SYMS);
const s = new MachineSession("Master"); await s.initialise(); await s.boot(30);
s.loadDisc(process.env.DISC || CAND_DISC); s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
const cpu = s._machine.processor; const secs = n => s.runFor(2000000 * n);
const cyc = () => cpu.cycleSeconds * 2e6 + cpu.currentCycles;
const key = async (k, hold = 0.15, after = 1.5) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
await secs(28); await key("N"); await secs(3); await key("SPACE"); await secs(4);
const addr = a => isNaN(+a) ? sy[a.split("+")[0]] + (+(a.split("+")[1] || 0)) : +a;
const prof = {}; let lastK = "", lastC = 0;
let cfg = null, state = 0, tHall = 0, tG = 0, gCyc = 0, hallCyc = 0;
const GH = sy.G_HANGAR, DEL = sy.DELAY;
cpu.debugInstruction.add(pc => {
  if (state === 1 && pc === sy.TT100 && (process.env.ANYBANK || (cpu.romsel & 15) === 4)) {
    const r = cfg.rand; for (let i = 0; i < 4; i++) cpu.ramRomOs[2 + i] = r[i];
    for (const [a, v] of cfg.pokes) cpu.ramRomOs[a >= 0xc000 && a < 0xe000 ? a - 0x3000 : a] = v;   // (HAZEL is at 9000-AFFF in jsbeeb's array)
    state = 2; cpu.pc = sy.GOIN;
  } else if (state === 2 && pc === sy.HALL) { tHall = cyc(); state = 3; }
  else if (state === 3 && GH !== undefined && pc === GH) { tG = cyc(); }
  if (state === 3 && tG && process.env.PROF) { const k = (pc >= 0x8000 && pc < 0xc000 ? (cpu.romsel & 0x8f).toString(16) + ":" : "") + pc.toString(16); const c = cyc(); prof[lastK] = (prof[lastK] || 0) + c - lastC; lastK = k; lastC = c; }
  if (state === 3 && process.env.PEEK && pc === sy.F_HANGAR && (cpu.romsel & 15) === 6) console.log("F_NSHIP", cpu.readmem(sy.F_NSHIP), "types", [0,1,2].map(i => cpu.readmem(sy.F_STYP + i)), "zh", [0,1,2].map(i => cpu.readmem(sy.F_SZH + i)), "nf", [0,1,2].map(i => cpu.readmem(sy.F_SNF + i)));
  if (state === 3 && pc === DEL) { hallCyc = cyc() - tHall; gCyc = tG ? cyc() - tG : 0; state = 4; }
  return false;
});
for (const c of CONFIGS) {
  const [name, rs, ps] = c.split(":");
  cfg = { rand: rs.split(",").map(Number), pokes: (ps || "").split(",").filter(x => x).map(p => { const [a, v] = p.split("="); return [addr(a), +v]; }) };
  await key("F0", 0.2, 6); tG = 0; state = 1;
  let t = 0; while (state < 4 && t < 400) { await secs(0.05); t++; }
  await secs(0.3);
  writeFileSync(`${OUT}/${name}.png`, await s.screenshotActive({ scale: 1 }));
  console.log(name, state === 4 ? "ok" : "TIMEOUT", "HALL to DELAY", hallCyc, "cycles", (hallCyc / 2e6).toFixed(3), "s; G_HANGAR..DELAY", gCyc);
  if (process.env.PROF) { writeFileSync(`${OUT}/${name}.prof.json`, JSON.stringify(prof)); for (const k in prof) delete prof[k]; }
  await secs(1.5); await key("SPACE", 0.15, 1);   // past any briefing
}
process.exit(0);
