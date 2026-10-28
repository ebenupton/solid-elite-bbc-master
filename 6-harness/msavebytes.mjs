// Saves byte-identical: save the same commander on the released SNG47 disc
// and on our build, through the game's own disc menu with real key presses,
// and compare the saved files byte for byte (and their catalogue entries:
// load and execution addresses, length).
//
// node 6-harness/msavebytes.mjs [--ref d] [--rsyms s] [--cand d] [--csyms s] [--out dir]
//
// Defaults: --ref 4-reference-binaries/sng47/elite-master-sng47.ssd with its
// symbols.txt, --cand 5-compiled-game-discs/elite-master-sng47.ssd with
// 3-assembled-output/symbols.txt. On each disc: the RTC
// pinned, new game (title: N, then SPACE), docked at Lave; the commander made
// the same on both, by the symbols of each: CASH 12345.6 Cr, fuel 5.5, 7 t of
// food and 3 t of computers in the hold, legal status 10; "@" -> 2 (save) as
// TESTB on drive 0. The file E.TESTB is read from the disc image as the
// emulated drive wrote it. Prints "SAVEBYTES PASS <n> bytes" or "SAVEBYTES
// FAIL" with the differing offsets; exit status 0 only on PASS.
import { MachineSession, BBC, toSsdOrDsd } from "./jsbeeb.mjs";
import { loadSyms, pinRtc, REF_DISC, REF_SYMS, CAND_DISC, CAND_SYMS, WORK } from "./mlib.mjs";
import { writeFileSync, mkdirSync } from "fs";
import { parseArgs } from "./args.mjs";
const a = parseArgs({ ref: "value", rsyms: "value", cand: "value", csyms: "value", out: "value" });
const REF = a.ref || REF_DISC;
const RSYMS = a.rsyms || REF_SYMS;
const CAND = a.cand || CAND_DISC;
const CSYMS = a.csyms || CAND_SYMS;
const OUT = a.out || `${WORK}savebytes`;
mkdirSync(OUT, { recursive: true });
const NAME = "TESTB";

async function saveOn(tag, disc, symsPath) {
    const sy = loadSyms(symsPath);
    const s = new MachineSession("Master"); await s.initialise(); pinRtc(s); await s.boot(30);
    s.loadDisc(disc); s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
    const cpu = s._machine.processor;
    const secs = n => s.runFor(2000000 * n);
    const key = async (k, hold = 0.15, after = 0.6) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
    const poke = (label, off, bytes) => bytes.forEach((b, i) => { cpu.ramRomOs[sy[label] + off + i] = b; });
    await secs(28);
    await key("N");                         // N: no commander to load
    await secs(3);
    await key("SPACE");
    await secs(4);
    poke("CASH", 0, [0x00, 0x01, 0xe2, 0x40]);  // 12345.6 Cr
    poke("QQ14", 0, [55]);                  // fuel 5.5
    poke("QQ20", 0, [7]);                   // food
    poke("QQ20", 7, [3]);                   // computers
    poke("FIST", 0, [10]);                  // legal status
    await key("AT", 0.15, 1.5);             // @: the disc menu
    await key("K2", 0.15, 1.5);             // 2: save
    await s.type(NAME); await key("RETURN", 0.1, 1.5);
    await s.type("0"); await secs(6);       // drive 0
    writeFileSync(`${OUT}/${tag}-saved.png`, await s.screenshotActive({ scale: 1 }));
    const img = toSsdOrDsd(cpu.fdc._drives[0].disc);
    writeFileSync(`${OUT}/${tag}-disc.ssd`, img);
    // DFS catalogue: names in sector 0 (8 bytes each from 8), addresses in
    // sector 1 (8 bytes each from &108: load, exec, length, extra bits, start)
    const nf = img[0x105] / 8;
    for (let i = 0; i < nf; i++) {
        const o = 8 + 8 * i;
        const nm = String.fromCharCode(img[o + 7] & 0x7f) + "." + String.fromCharCode(...img.slice(o, o + 7)).trim();
        if (nm !== "E." + NAME) continue;
        const c = 0x108 + 8 * i, x = img[c + 6];
        const load = img[c] | img[c + 1] << 8 | (x >> 2 & 3) << 16;
        const exec = img[c + 2] | img[c + 3] << 8 | (x >> 6 & 3) << 16;
        const len = img[c + 4] | img[c + 5] << 8 | (x >> 4 & 3) << 16;
        const start = img[c + 7] | (x & 3) << 8;
        const data = img.slice(start * 256, start * 256 + len);
        writeFileSync(`${OUT}/${tag}-E.${NAME}.bin`, data);
        return { load, exec, len, data };
    }
    return null;
}

const r = await saveOn("ref", REF, RSYMS);
const c = await saveOn("cand", CAND, CSYMS);
const hex = v => "&" + v.toString(16).toUpperCase();
let ok = !!(r && c);
if (!r) console.log(`savebytes: E.${NAME} is not on the reference's disc`);
if (!c) console.log(`savebytes: E.${NAME} is not on the candidate's disc`);
if (ok) {
    console.log(`savebytes: ref load ${hex(r.load)} exec ${hex(r.exec)} length ${r.len}; cand load ${hex(c.load)} exec ${hex(c.exec)} length ${c.len}`);
    if (r.load !== c.load || r.exec !== c.exec || r.len !== c.len) { ok = false; console.log("savebytes: the catalogue entries differ"); }
    const diff = [];
    for (let i = 0; i < Math.max(r.data.length, c.data.length); i++) if (r.data[i] !== c.data[i]) diff.push(i);
    if (diff.length) {
        ok = false;
        console.log(`savebytes: ${diff.length} bytes differ: ` + diff.slice(0, 32).map(i => `+${hex(i)} ${r.data[i]?.toString(16)}/${c.data[i]?.toString(16)}`).join(" "));
    }
}
console.log(ok ? `SAVEBYTES PASS ${r.len} bytes identical` : "SAVEBYTES FAIL");
process.exit(ok ? 0 : 1);
