// Save and load a commander on the emulated Master, through the game's own
// disc menu, with real key presses (not the deterministic pilot).
//
// node 6-harness/msavetest.mjs [--disc d] [--syms s] [--out dir]
//
// New game (title: N, then SPACE), docked: CASH is set to a marker, "@" ->
// 2 (save) as TESTA; CASH is changed; "@" -> 1 (load) TESTA; CASH must be
// the marker again. Then a load of a file that isn't there (the error path),
// "@" -> 3 (catalogue, drive 0), and a launch (f0) to check that the
// renderer is intact after the disc access. DFS and the MOS overwrite parts
// of HAZEL during a disc command (docs/master-memory.md): at each OSCLI the
// game makes, the places they may write are filled with junk (&C000-&C27F,
// &D900-&DAFF, &DC00-&DFBF; not DFS's drive state and lasting bytes at
// &C280-&C2FF, nor the MOS's at &DFC0-&DFFF, which DOSCLI puts back for the
// command). Checks that NEWBRK, the BRKV handler, is entered once, for the
// failed load, with ACCCON X clear, the minimal NMI handler is back at &0D00, that the disc's
// catalogue holds E.TESTA and every file, that the game data (the
// blueprints and their tables, from XX21) is intact after the disc commands,
// and that the space view after the launch holds nothing of what a disc
// command left in screen buffer 0 (DOSCLI may stash HAZEL there): no more
// than a few of its bytes may equal HAZEL's at the same offset; and that no
// disc command changes ANDY (the rasteriser's polygon window: a CRC of
// &8000-&8FFF at each OSCLI DOSCLI makes, against one when DOSNMI ends the
// command, also on the error path). Screenshots
// of each step go to <out>. Exit status 0 on success.
import { MachineSession } from "./jsbeeb.mjs";
import { BBC } from "./jsbeeb.mjs";
import { toSsdOrDsd } from "./jsbeeb.mjs";
import { loadSyms, mapAt, mapOfLabel, CAND_DISC, CAND_SYMS, WORK } from "./mlib.mjs";
import { writeFileSync, mkdirSync, readFileSync, existsSync } from "fs";
import { dirname } from "path";
import { parseArgs } from "./args.mjs";
const a = parseArgs({ disc: "value", syms: "value", out: "value" });
const DISC = a.disc || CAND_DISC;
const sy = loadSyms(a.syms || CAND_SYMS);
const OUT = a.out || `${WORK}save`;
mkdirSync(OUT, { recursive: true });
const s = new MachineSession("Master"); await s.initialise(); await s.boot(30);
s.loadDisc(DISC); s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
const cpu = s._machine.processor;
const secs = n => s.runFor(2000000 * n);
const hits = { NEWBRK: 0, DOSNMI_C: 0, DOSCLI_C: 0 };
const hm = Object.fromEntries(Object.keys(hits).map(k => [k, mapOfLabel(sy, k)]));
let brkX = 0;
// ANDY (jsbeeb keeps it at &8000-&8FFF in its RAM array) around each disc command
const crc = (lo, hi) => { let c = 0xffffffff; for (let a = lo; a < hi; a++) { c ^= cpu.ramRomOs[a]; for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1)); } return (c ^ 0xffffffff) >>> 0; };
let andyAt = null, andyChecks = 0, andyBad = 0;
cpu.debugInstruction.add(pc => { for (const k in hits) if (pc === sy[k] && (hm[k] === "m" || mapAt(cpu.romsel, pc) === hm[k])) { hits[k]++; if (k === "NEWBRK" && (cpu.acccon & 4)) brkX++;
    if (k === "DOSNMI_C" && andyAt !== null) { andyChecks++; if (crc(0x8000, 0x9000) !== andyAt) andyBad++; andyAt = null; } } return false; });
let shot = 0;
const snap = async name => writeFileSync(`${OUT}/${String(shot++).padStart(2, "0")}-${name}.png`, await s.screenshotActive({ scale: 1 }));
// keys by their place in the BBC keyboard matrix (jsbeeb's BBC table)
const key = async (k, hold = 0.15, after = 0.6) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
const slowType = async t => { for (const c of t) { await s.type(c); await secs(0.3); } };
const cash = () => [0, 1, 2, 3].map(i => cpu.ramRomOs[sy.CASH + i]);
const setCash = v => v.forEach((b, i) => { cpu.ramRomOs[sy.CASH + i] = b; });
// DFS and the MOS may write these parts of HAZEL during a disc command: fill
// them with junk at each OSCLI the game makes (inside DOSCLI, after it has set
// up DFS's own bytes). (jsbeeb keeps HAZEL at &9000 in its RAM array.)
const HZ = a => 0x9000 + a - 0xc000;
let seed = 12345, junks = 0;
const JUNK = [[0xc000, 0xc280], [0xd900, 0xdb00], [0xdc00, 0xdfc0]];
const junk = () => {
    junks++;
    for (const [lo, hi] of JUNK) for (let a = lo; a < hi; a++) { seed = (seed * 1103515245 + 12345) >>> 0; cpu.ramRomOs[HZ(a)] = seed >>> 24; } };
cpu.debugInstruction.add(pc => {
    if (pc !== 0xfff7 || (cpu.romsel & 15) !== 7) return false;
    const site = (cpu.ramRomOs[0x100 + ((cpu.s + 1) & 0xff)] | cpu.ramRomOs[0x100 + ((cpu.s + 2) & 0xff)] << 8) - 2;
    if (site >= sy.DOSCLI_C && site < sy.DOSNMI_C) { junk(); andyAt = crc(0x8000, 0x9000); }   // (DOSCLI's JSR OSCLI, not the loader's)
    return false; });
// the game data from XX21 (the blueprints and their tables) as the build has
// it, in HAZEL from &C000 (3-assembled-output/HZDATA.bin, next to the symbols)
const BD = dirname(a.syms || CAND_SYMS);
const XX21 = sy.XX21;
const PARTS = [[XX21, readFileSync(`${BD}/HZDATA.bin`)]];
const dataPhys = HZ;
await secs(28);
await snap("title");
await key("N");                       // N: no commander to load
await secs(3);
await key("SPACE");                       // SPACE
await secs(4);
await snap("docked");
const MARK = [0x00, 0x01, 0xe2, 0x40];   // 12345.6 Cr
setCash(MARK);
await key("AT", 0.15, 1.5);           // @: the disc menu
await snap("menu");
console.log("QQ11 after @:", cpu.ramRomOs[sy.QQ11]);
await key("K2", 0.15, 1.5);            // 2: save
await s.type("TESTA"); await key("RETURN", 0.1, 1.5);
await s.type("0"); await secs(6);       // drive 0
await snap("saved");
setCash([0, 0, 0, 7]);
await key("AT", 0.15, 1.5);
await key("K1", 0.15, 1.5);            // 1: load
await s.type("TESTA"); await key("RETURN", 0.1, 1.5);
await s.type("0"); await secs(6);       // drive 0
await snap("loaded");
const got = cash();
const ok = got.every((b, i) => b === MARK[i]);
console.log("CASH after load:", got.map(b => b.toString(16)).join(" "), ok ? "matches" : "DOES NOT MATCH");
await key("F8", 0.15, 2);             // (another key first: the game ignores a
                                       // key pressed again straight away)
await key("AT", 0.15, 1.5);           // the error path: load a file that
await snap("e-menu");
await key("K1", 0.15, 1.5);            // isn't there ("File not found",
await s.type("QQ"); await key("RETURN", 0.1, 1.5); // through BRKV, NEWBRK)
await snap("e-name");
await s.type("0"); await secs(1);
await snap("e-err");
await secs(5);
await snap("error");
await key("SPACE", 0.15, 2);
await key("F8", 0.15, 2);
await key("AT", 0.15, 1.5);
await key("K3", 0.15, 1.5);            // 3: catalogue
await s.type("0"); await key("RETURN", 0.1, 5);
await snap("catalogue");
await key("SPACE", 0.15, 2);
await key("ESCAPE", 0.15, 2);              // ESCAPE out of the menu if needed
await key("F0", 0.2, 12);             // f0: launch
await snap("launched");
await secs(4);
await snap("flight");
console.log("disc commands (DOSCLI):", hits.DOSCLI_C, " errors (NEWBRK):", hits.NEWBRK, brkX ? `(${brkX} with ACCCON X SET)` : "(ACCCON X clear)", " NMI handler reinstalls (DOSNMI):", hits.DOSNMI_C);
const nmi = [0, 1, 2, 3, 4, 5].map(i => cpu.ramRomOs[0x0d00 + i].toString(16)).join(" ");
console.log("&0D00 after the disc accesses:", nmi, nmi === "48 ad 28 fe 68 40" ? "(the minimal NMI handler)" : "(NOT the minimal handler)");
// the disc's catalogue, as written (DFS: names at sector 0, 8 bytes each)
const img = toSsdOrDsd(cpu.fdc._drives[0].disc);
writeFileSync(`${OUT}/disc-after.ssd`, img);
const nf = img[0x105] / 8, names = [];
for (let i = 0; i < nf; i++) { const o = 8 + 8 * i; names.push(String.fromCharCode(img[o + 7] & 0x7f) + "." + String.fromCharCode(...img.slice(o, o + 7)).trim()); }
console.log("disc catalogue:", names.join(" "));
const saved = names.includes("E.TESTA");
// the game data after the disc commands (XX21+2/3, the station's blueprint, is
// written by the game)
let bad = 0, nd = 0;
for (const [base, img] of PARTS) for (let i = 0; i < img.length; i++, nd++) {
    const ad = base + i;
    if (ad === XX21 + 2 || ad === XX21 + 3) continue;
    if (cpu.ramRomOs[dataPhys(ad)] !== img[i]) bad++;
}
console.log(`game data (HAZEL, ${nd} bytes) after ${junks} junk fills: ${bad ? bad + " bytes DIFFER" : "intact"}`);
// once the game draws its space view through the filled renderer (LL9F, the
// title's frame, exists), the space view after the launch: screen buffer 0
// (main &4000-&5FFF) must not still hold HAZEL's stash: count the non-zero
// bytes equal to HAZEL's at the same offset (a stale stash matches nearly all
// of them); before that, main &4000-&5FFF is never on show
let same = 0, nz = 0, viewOk = true;
if (sy.LL9F !== undefined) {
    for (let i = 0; i < 0x2000; i++) { const h = cpu.ramRomOs[HZ(0xc000 + i)]; if (h) { nz++; if (cpu.ramRomOs[0x4000 + i] === h) same++; } }
    viewOk = same * 20 < nz;
    console.log(`space view after the disc commands: ${same} of HAZEL's ${nz} non-zero bytes in buffer 0 at the same offset (${viewOk ? "no stale stash" : "STALE STASH"})`);
}
console.log(`ANDY over the disc commands: ${andyChecks} checked, ${andyBad ? andyBad + " CHANGED" : "unchanged"}`);
console.log(saved ? "E.TESTA is on the disc" : "E.TESTA is NOT on the disc");
process.exit(ok && saved && !bad && viewOk && junks >= 4 && hits.NEWBRK === 1 && !brkX && andyChecks >= 4 && !andyBad ? 0 : 1);
