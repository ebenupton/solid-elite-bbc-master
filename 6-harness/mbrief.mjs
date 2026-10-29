// The mission briefings and debriefings, forced with pokes, recorded frame by frame:
// node 6-harness/mbrief.mjs --out DIR [--disc D --syms S] [--configs brief1,debrief1,...]
// (default: the build's disc and symbols; for the original, --disc
// 4-reference-binaries/sng47/elite-master-sng47.ssd --syms 4-reference-binaries/sng47/symbols.txt)
//
// New game, launch; then for each config, at a TT100 (flight) RAND (&02-&05) is set (so
// that HALL's hangar is the same in both machines), the mission state is poked and the PC
// is set to GOIN (dock: the docking tunnel, HALL, then DOENTRY's mission checks). Every
// key wait of the briefing (PAUSE's PAL1 loop with the rotating ship, PAUSE2) is answered
// by SPACE 2.5 s after it starts (PAUSE2's just before its second RDKEY), the same in
// both machines; a config ends at STATUS (the
// briefing's BAY), 1 s later. The configs:
//   brief1    TP = 0, TALLY+1 = 5, galaxy 1: BRIEF, the Constrictor (the only ship)
//   debrief1  TP = 3: DEBRIEF
//   brief2    TP = 2, galaxy 3: BRIEF2 (the Thargoid plans mission's first message)
//   brief3    TP = 6, galaxy 3 at Ceerdi (215, 84): BRIEF3 (the plans)
//   debrief2  TP = 10, galaxy 3 at Birera (63, 72): DEBRIEF2
// Writes DIR/NAME.raw (every frame the video chip painted from GOIN to the end, the active
// area at half its size (448 x 300: a mode 1 pixel each), RGB, 50 a second), DIR/NAME-waitN.png (each key wait, just before its key press) and
// DIR/NAME.json: the frames' times and what was running, the emulated times of the
// briefing's stages, and BRIEF's ship at each LL9 call (INWK bytes 0-35 and the time),
// for comparing the two machines' briefings.
import { MachineSession, BBC } from "./jsbeeb.mjs";
import { loadSyms, mapAt, mapOfLabel, pinRtc, CAND_DISC, CAND_SYMS } from "./mlib.mjs";
import { parseArgs } from "./args.mjs";
import { writeFileSync, mkdirSync, openSync, writeSync, closeSync } from "fs";

const a = parseArgs({ out: "value", disc: "value", syms: "value", configs: "value" });
if (!a.out) { console.error("--out DIR is required"); process.exit(2); }
const OUT = a.out; mkdirSync(OUT, { recursive: true });
const sy = loadSyms(a.syms || CAND_SYMS);
const DISC = a.disc || CAND_DISC;
const CONFIGS = {
    brief1: { TP: 0, "TALLY+1": 5, GCNT: 0 },
    debrief1: { TP: 3, "TALLY+1": 5, GCNT: 0 },
    brief2: { TP: 2, "TALLY+1": 5, GCNT: 2 },
    brief3: { TP: 6, "TALLY+1": 5, GCNT: 2, QQ0: 215, QQ1: 84 },
    debrief2: { TP: 10, "TALLY+1": 5, GCNT: 2, QQ0: 63, QQ1: 72 },
};
const names = (a.configs || Object.keys(CONFIGS).join(",")).split(",");

// a routine by name: the port's cold routines are X_C in bank 7, the original's are X
const where = n => {
    const nm = sy[n + "_C"] !== undefined ? n + "_C" : n;
    if (sy[nm] === undefined) throw new Error(`no symbol ${n}`);
    return { addr: sy[nm], map: mapOfLabel(sy, nm) };
};
const R = Object.fromEntries(["TT100", "GOIN", "BRIEF", "PAL1", "PAUSE2", "STATUS", "LL9", "PAS1", "BR2", "DOENTRY", "BRIS", "DELAY"].map(n => [n, where(n)]));

const s = new MachineSession("Master"); await s.initialise(); pinRtc(s); await s.boot(30);
s.loadDisc(DISC); s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
const cpu = s._machine.processor;
// STACKWATCH=1: the lowest S while the frame runs game code (GPRJ set: the
// frame's ship projection, whose XX3 is under the stack), printed at the end
// (6-harness/records/stack.mjs)
const SW = { minS: 0xff };
if (process.env.STACKWATCH && sy.GPRJ !== undefined) cpu.debugInstruction.add(() => { if ((cpu.ramRomOs[sy.GPRJ] & 0x80) && cpu.s < SW.minS) SW.minS = cpu.s; return false; });
const cyc = () => cpu.cycleSeconds * 2e6 + cpu.currentCycles;
const now = () => cyc() / 2e6;
const secs = n => s.runFor(Math.round(2000000 * n));
const key = async (k, hold = 0.15, after = 1.5) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
await secs(28); await key("N"); await secs(3); await key("SPACE"); await secs(4);

const at = (pc, r) => pc === r.addr && (r.map === "m" || r.map === mapAt(cpu.romsel, pc));
const poke = (adr, v) => { cpu.ramRomOs[adr >= 0xc000 && adr < 0xe000 ? adr - 0x3000 : adr] = v; };
const sym = n => { const [b, o] = n.split("+"); return sy[b] + (+(o || 0)); };

// every frame painted, a mode 1 pixel to a pixel
let rec = null;
const v = s._video, orig = v.paint_ext;
v.paint_ext = (...args) => {
    orig.apply(v, args);
    if (!rec) return;
    const l = v.leftBorder, t = v.topBorder, src = s._completeFb8;
    const W = (1024 - l - v.rightBorder) >> 1, H = (625 - t - v.bottomBorder) >> 1, buf = Buffer.alloc(W * H * 3);
    rec.size ||= [W, H];
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const p = ((t + 2 * y) * 1024 + l + 2 * x) * 4, d = (y * W + x) * 3;
        buf[d] = src[p]; buf[d + 1] = src[p + 1]; buf[d + 2] = src[p + 2];
    }
    writeSync(rec.fd, buf);
    rec.frames.push(+(now() - rec.t0).toFixed(4));
};

let st = null;
cpu.debugInstruction.add(pc => {
    if (!st) return false;
    if (st.phase === "fly" && at(pc, R.TT100)) {
        for (let i = 0; i < 4; i++) cpu.ramRomOs[2 + i] = [0x31, 0x5c, 0x12, 0xa7][i];
        for (const [k, val] of Object.entries(st.pokes)) poke(sym(k), val);
        st.phase = "dock"; cpu.pc = R.GOIN.addr; st.t.goin = now();
        return false;
    }
    if (st.phase === "fly") return false;
    const t = now() - st.t.goin;
    for (const n of ["DOENTRY", "BRIEF", "BRIS", "BR2"]) if (st.t[n] === undefined && at(pc, R[n])) st.t[n] = +t.toFixed(4);
    if (at(pc, R.LL9) && st.t.BRIEF !== undefined) {
        st.ll9.push({ t: +t.toFixed(4), inwk: Array.from({ length: 36 }, (_, i) => cpu.ramRomOs[sy.INWK + i]) });
    }
    if (at(pc, R.PAS1) && st.t.BRIEF !== undefined) st.pas1.push(+t.toFixed(4));
    if ((at(pc, R.PAL1) || at(pc, R.PAUSE2)) && !st.keyHeld && t > st.quietUntil) {
        st.waits.push({ t: +t.toFixed(4), kind: at(pc, R.PAL1) ? "PAL1" : "PAUSE2" });
        st.keyHeld = true;
    }
    // PAUSE2 returns only if its first RDKEY finds no key and its second one a key, so
    // its key goes down just before the second (PAUSE2+5), as a person's might
    if (st.arm && at(pc, { addr: R.PAUSE2.addr + 5, map: R.PAUSE2.map })) { cpu.sysvia.keyDownRaw(BBC.SPACE); st.arm = false; st.down = now(); }
    if (st.phase === "dock" && at(pc, R.STATUS) && st.t.DOENTRY !== undefined) { st.t.STATUS = +t.toFixed(4); st.phase = "status"; }
    return false;
});

for (const nm of names) {
    await key("F0", 0.2, 6);
    const fd = openSync(`${OUT}/${nm}.raw`, "w");
    st = { phase: "fly", pokes: CONFIGS[nm], t: {}, ll9: [], pas1: [], waits: [], keyHeld: false, quietUntil: 0 };
    let waited = 0;
    while (st.phase === "fly" && waited++ < 400) await secs(0.05);
    rec = { fd, frames: [], t0: st.t.goin };
    let n = 0, guard = 0;
    while (st.phase !== "status" && guard++ < 4000) {
        if (st.keyHeld && st.waits.length > n) {
            n = st.waits.length;
            await secs(2.4);
            writeFileSync(`${OUT}/${nm}-wait${n}.png`, await s.screenshotActive({ scale: 1 }));
            await secs(0.1);
            if (st.waits[n - 1].kind === "PAUSE2") { st.arm = true; while (st.arm) await secs(0.001); }
            else cpu.sysvia.keyDownRaw(BBC.SPACE);
            await secs(0.15); cpu.sysvia.keyUpRaw(BBC.SPACE);
            st.quietUntil = now() - st.t.goin + 0.5; st.keyHeld = false;
            continue;
        }
        await secs(0.02);
    }
    await secs(1);
    writeFileSync(`${OUT}/${nm}-end.png`, await s.screenshotActive({ scale: 1 }));
    const frames = rec.frames, size = rec.size; rec = null; closeSync(fd);
    const info = { config: nm, disc: DISC, pokes: CONFIGS[nm], ok: st.phase === "status", size, times: st.t, waits: st.waits, pas1: st.pas1, ll9: st.ll9, frames };
    writeFileSync(`${OUT}/${nm}.json`, JSON.stringify(info));
    console.log(nm, st.phase === "status" ? "ok" : "TIMEOUT", JSON.stringify(st.t), "waits", st.waits.length, "LL9", st.ll9.length, "PAS1", st.pas1.length);
    st = null;
}
if (process.env.STACKWATCH) console.log(`lowest S while the frame projects: &${SW.minS.toString(16)}`);
process.exit(0);
