// Boot BBC Master Elite (master/build.sh's disc) on the emulated BBC Master and
// check that it reaches the title screen with its code and data in place.
//
// node harness/mboot.mjs [--disc master/build/elite-master-sng47.ssd]
//                        [--syms master/build/symbols.txt] [--out dir] [--polls N]
//
// Boots with SHIFT+BREAK, runs until the first title screen ("Load New
// Commander (Y/N)?") has drawn its rotating ship a few times (the 8th call of
// RDKEY after TITLE starts), then reports ROMSEL / ACCCON, compares the
// sideways, shadow and main RAM images the loader installs (build/images.txt)
// with what memory holds,
// and
// writes title.png.
// Exit status 0 if the title screen was reached and the banks match.
import { MachineSession } from "./jsbeeb.mjs";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { loadSyms, mapAt, mapOfLabel, CAND_DISC, CAND_SYMS, WORK } from "./mlib.mjs";

const ROOT = decodeURIComponent(new URL("..", import.meta.url).pathname);
const args = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, arr) => {
    if (v.startsWith("--")) acc.push([v.slice(2), arr[i + 1] && !arr[i + 1].startsWith("--") ? arr[i + 1] : true]);
    return acc;
}, []));
const DISC = args.disc || CAND_DISC;
const SYMS = args.syms || CAND_SYMS;
const OUT = args.out || `${WORK}boot`;
mkdirSync(OUT, { recursive: true });

const syms = loadSyms(SYMS);

const s = new MachineSession("Master");
await s.initialise();
await s.boot(30);
s.loadDisc(DISC);
s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
const cpu = s._machine.processor;

// Count RDKEY calls once TITLE (or its cold copy TITLE_C, in the cold area
// from Stage B) has been entered: TITLE's key loop calls RDKEY repeatedly
let titleCalls = 0, done = false, inTitle = false;
const tName = syms.TITLE_C !== undefined ? "TITLE_C" : "TITLE";
const tAddr = syms[tName], tMap = mapOfLabel(syms, tName), rMap = mapOfLabel(syms, "RDKEY");
const h = pc => {
    if (pc === tAddr && (tMap === "m" || tMap === mapAt(cpu.romsel, pc))) inTitle = true;
    if (pc === syms.RDKEY && (rMap === "m" || rMap === mapAt(cpu.romsel, pc)) && inTitle && ++titleCalls >= (+args.polls || 8)) done = true;
    return done;
};
cpu.debugInstruction.add(h);
const t0 = cpu.cycleSeconds;
while (!done && cpu.cycleSeconds - t0 < 60) { h(cpu.pc); cpu.execute(20000); }
const secs = cpu.cycleSeconds + cpu.currentCycles / 2e6;
if (!done) { console.log(`FAIL: title screen key loop not reached in 60 emulated seconds (PC &${cpu.pc.toString(16)})`); process.exit(1); }
console.log(`title screen key loop reached at emulated t=${secs.toFixed(2)} s`);
console.log(`ROMSEL &${cpu.romsel.toString(16)} (bank ${cpu.romsel & 15}${cpu.romsel & 0x80 ? ", ANDY paged" : ""}), ACCCON &${cpu.acccon.toString(16)}`);
console.log(`sideways RAM banks in this model: ${cpu.model.swram.map((v, i) => v ? i : -1).filter(i => i >= 0).join(" ")}`);

// The banked images against the build: [file, ROMSEL or "shadow", start]
// (ROMSEL bit 7: ANDY at &8000-&8FFF). The game writes XX21+2/3 (the station's
// blueprint, in HAZEL) and patches DETOK's JSR at DTM (DTM_C in the cold area).
// (build/images.txt, from build.sh: file, ROMSEL or main/shadow/hazel, start,
// "v" if it holds variables or self-modified code)
const images = readFileSync(SYMS.replace(/symbols\.txt$/, "images.txt"), "utf8").trim().split("\n").map(l => l.trim().split(/\s+/))
    .map(([f, rs, at, v]) => [f, /^[0-9a-f]+$/i.test(rs) ? parseInt(rs, 16) : rs, parseInt(at, 16), v === "v"]);
// (XX21: in the symbols since the data is assembled with the code; before
// that, in build/data-addresses.asm)
const xx21 = syms.XX21 ?? parseInt(readFileSync(SYMS.replace(/symbols\.txt$/, "data-addresses.asm"), "utf8").match(/XX21 = &([0-9A-F]+)/)[1], 16);
let diffs = [];
for (const [f, rs, start, vol] of images) {
    let img;
    try { img = readFileSync(`${ROOT}3-assembled-output/${f}`); } catch { continue; }
    const d = [];
    for (let i = 0; i < img.length; i++) {
        const a = start + i;
        const phys = rs === "main" ? a : rs === "shadow" ? a + 0x8000 : rs === "hazel" ? a - 0xc000 + 0x9000 : rs & 0x80 && a < 0x9000 ? a : cpu.romOffset + (rs & 15) * 16384 + a - 0x8000;
        if (a === xx21 + 2 || a === xx21 + 3) continue;
        if (syms.DTM_C !== undefined && (rs & 15) === 7 && (a === syms.DTM_C + 1 || a === syms.DTM_C + 2)) continue;
        if (cpu.ramRomOs[phys] !== img[i]) d.push(a);
    }
    console.log(`${f} (${rs === "shadow" ? "shadow RAM" : rs === "main" ? "main RAM" : rs === "hazel" ? "HAZEL" : "ROMSEL &" + rs.toString(16)}, &${start.toString(16)}-&${(start + img.length - 1).toString(16)}): ${d.length} differing bytes` +
        (d.length ? ` (first &${d[0].toString(16)}, last &${d.at(-1).toString(16)})` : ""));
    // the renderer's banks and code, and bank 4 (where the main code continues),
    // hold variables and self-modified code: their differences are reported but
    // not failures
    if (!vol) diffs = diffs.concat(d);
}
writeFileSync(`${OUT}/title.png`, await s.screenshotActive({ scale: 1 }));
console.log(`screenshot: ${OUT}/title.png`);
process.exit(diffs.length ? 1 : 0);
