// The dot-to-polygons hand-over: a ship coming in from far away must be drawn
// in every frame, as the original's distant dot (SHPPT) or as its filled
// faces, never as nothing (the gap there once was between the two).
//
// node 6-harness/mdotgap.mjs --title [--type 11] [--polls 400] [--sheet f.png]
// node 6-harness/mdotgap.mjs --pose [--types 1,5,8,11,...] [--zfrom 112]
//                          [--zto 2] [--zstep 1]
//                          [--disc d] [--syms s]
//
// --title: the title screen's ship (TITLE's X replaced by --type) as it comes
// in from z_hi = 96; at each key poll of the title loop (one per frame) the
// space view's lit pixels (between the title and the text below) on the screen
// shown, the ship's z and what the frame layer drew for it (a dot: F_SHPPT;
// faces: fsh_draw). --sheet f.png: a contact sheet of the frames.
// --pose: each type posed in flight (as mshippose.mjs does: planet and
// station behind us, speed 0) in front of us at x = z / 4, y = 0 (64 pixels
// right of the centre, clear of the sights), z_hi from --zfrom
// down to --zto, each z held for three iterations, then the lit pixels the
// ship adds to the screen shown (against the screen with it behind us).
// Prints a line per frame or z, and "DOTGAP PASS" or "DOTGAP FAIL" (some frame
// with the ship in front of us and on screen drew no pixel); exit status 0
// only on PASS.
import { MachineSession, BBC, sharp } from "./jsbeeb.mjs";
import { loadSyms, CAND_DISC, CAND_SYMS, mapOfLabel, mapAt, physRead } from "./mlib.mjs";
import { parseArgs } from "./args.mjs";
const a = parseArgs({ title: "flag", pose: "flag", type: "value", polls: "value", sheet: "value", types: "value",
    zfrom: "value", zto: "value", zstep: "value", disc: "value", syms: "value", quiet: "flag" });
const sy = loadSyms(a.syms || CAND_SYMS);
const DISC = a.disc || CAND_DISC;
const s = new MachineSession("Master"); await s.initialise(); await s.boot(30);
s.loadDisc(DISC); s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
const cpu = s._machine.processor, ram = cpu.ramRomOs, secs = n => s.runFor(2000000 * n);
const at = (pc, name) => { if (pc !== sy[name]) return false; const b = sy.__bank[name]; return b === undefined || (cpu.romsel & 15) === (b & 15); };
const M6 = mapOfLabel(sy, "F_STYP");
// the screen shown: Elite's (x, y) is two frame pixels wide, two lines high
const FW = 1024, VX = 184, VY = 68, v = s._video;
function screen() {
    const fb = new Uint8Array(s._completeFb8.buffer.slice(0)), L = v.leftBorder, T = v.topBorder;
    return { fb, lit: (x, y) => { const o = 4 * ((T + VY + 2 * y) * FW + L + VX + 2 * x); return fb[o] + fb[o + 1] + fb[o + 2] > 60; } };
}
async function png(fb, file) {
    const L = v.leftBorder, T = v.topBorder;
    return sharp(Buffer.from(fb.buffer), { raw: { width: FW, height: 625, channels: 4 } })
        .extract({ left: L + VX, top: T + VY, width: 512, height: 384 }).png().toFile(file);
}
let bad = 0;
const say = t => { if (!a.quiet) console.log(t); };

if (a.title) {
    const T = +(a.type || 11), POLLS = +(a.polls || 400);
    const tName = sy.TITLE_C !== undefined ? "TITLE_C" : "TITLE", tAddr = sy[tName], tMap = mapOfLabel(sy, tName);
    let inT = false, polls = 0, dot = 0, faces = 0, z = 0;
    const rows = [], frames = [];
    cpu.debugInstruction.add(pc => {
        if (pc === tAddr && (tMap === "m" || tMap === mapAt(cpu.romsel, pc))) { if (!inT) cpu.x = T; inT = true; }
        if (!inT) return false;
        if (at(pc, "F_SHPPT")) dot++;
        if (at(pc, "fsh_draw")) faces++;
        if (pc === sy.RDKEY) {
            const sc = screen(); let n = 0;
            for (let y = 16; y < 150; y++) for (let x = 2; x < 254; x++) if (sc.lit(x, y)) n++;
            rows.push({ p: polls, z: ram[sy.INWK + 6] | ram[sy.INWK + 7] << 8, dot, faces, n });
            if (a.sheet) frames.push(sc.fb);
            dot = 0; faces = 0;
            if (++polls >= POLLS) return true;
        }
        return false;
    });
    while (polls < POLLS) await s.runFor(200000);
    // the screen shown lags the frame drawn; a ship is in front and on screen
    // throughout (it comes in along the line of sight)
    const gap = rows.filter((r, i) => i > 2 && r.n === 0);
    for (const r of rows) say(`poll ${String(r.p).padStart(3)} z &${r.z.toString(16).padStart(4, "0")}  ${r.dot ? "dot" : "   "} ${r.faces ? `faces ${String(r.faces).padStart(2)}` : "        "}  lit ${r.n}${r.p > 2 && r.n === 0 ? "  GAP" : ""}`);
    if (gap.length) { bad = gap.length; console.log(`title type ${T}: ${gap.length} frames with no pixel, z &${gap[0].z.toString(16)} to &${gap[gap.length - 1].z.toString(16)}`); }
    if (a.sheet) {
        // the frames from the first with faces drawn less 10, 80 of them, 10 across
        const f0 = Math.max(0, rows.findIndex(r => r.faces) - 10), sel = frames.slice(f0, f0 + 80);
        const W = 256, H = 192, cols = 10, tiles = [];
        for (let k = 0; k < sel.length; k++) {
            const f = `${a.sheet}.${k}.png`; await png(sel[k], f);
            // (the middle 64 x 48 of the view, magnified 4 times)
            tiles.push({ input: await sharp(f).extract({ left: 192, top: 144, width: 128, height: 96 }).resize(W, H, { kernel: "nearest" }).toBuffer(), left: (k % cols) * (W + 4), top: Math.floor(k / cols) * (H + 4) });
        }
        await sharp({ create: { width: (W + 4) * cols, height: (H + 4) * Math.ceil(sel.length / cols), channels: 3, background: "#202020" } })
            .composite(tiles).png().toFile(a.sheet);
        const { unlinkSync } = await import("fs"); for (let k = 0; k < sel.length; k++) unlinkSync(`${a.sheet}.${k}.png`);
        console.log(`${a.sheet}: polls ${f0} to ${f0 + sel.length - 1}`);
    }
}

if (a.pose) {
    const key = async (k, hold = 0.2, after = 1) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
    await secs(28); await key("N"); await secs(3); await key("SPACE"); await secs(4);
    await key("F0", 0.2, 12);
    // two poses: front-left-low (the ship audit's o6: no face edge-on) and
    // nose on (as the title's ship comes in: the flattest outline)
    const POSES = { o6: [[-0.5997301821134201, 0.34984260623282837, -0.7196762185361041], [0.22396377884822027, 0.9368084920965556, 0.2687565346178643]],
        front: [[0, 0, -1], [0, 1, 0]] };
    let n, r, sd;
    const enc = q => { const m = Math.min(0x7fff, Math.round(Math.abs(q) * 0x6000)); return [m & 255, (m >> 8) | (q < 0 ? 0x80 : 0)]; };
    let cur = null, iters = 0;
    cpu.debugInstruction.add(pc => {
        if (!at(pc, "MLOOP")) return false;
        iters++;
        if (!cur) return false;
        const K = sy["K%"];
        ram.fill(0, K, K + 3 * 37);
        ram[K + 7] = 0x80; ram[K + 8] = 0x80;
        ram[K + 37 + 7] = 0x60; ram[K + 37 + 8] = 0x80;
        ram[K + 37 + 9 + 4] = 0x60; ram[K + 37 + 15 + 2] = 0x60; ram[K + 37 + 21] = 0x60;
        const S = K + 74;
        ram[S + 6] = cur.z & 255; ram[S + 7] = cur.z >> 8; ram[S + 8] = cur.behind ? 0x80 : 0;
        ram[S + 0] = (cur.z >> 2) & 255; ram[S + 1] = cur.z >> 10;   // x = z / 4: 64 pixels right, clear of the sights
        [...n, ...r, ...sd].forEach((q, i) => { const [lo, hi] = enc(q); ram[S + 9 + 2 * i] = lo; ram[S + 10 + 2 * i] = hi; });
        [0x80, 2, cur.t, 0].forEach((b, i) => { ram[sy.FRIN + i] = b; });
        ram[sy.DELTA] = 0; ram[sy.QQ11] = 0; ram[sy.VIEW] = 0; ram[sy.LASER] = 0;
        return false;
    });
    for (let k = 0; k < 200 && !iters; k++) await s.runFor(20000);
    const hold = async () => { const i0 = iters; for (let k = 0; k < 4000 && iters < i0 + 3; k++) await s.runFor(20000); await s.runFor(100000); };
    const TYPES = (a.types || "1,3,4,5,6,8,9,10,11,16,17,19,21,32").split(",").map(Number);
    const Z0 = +(a.zfrom || 112), Z1 = +(a.zto || 2), ZS = +(a.zstep || 1);
    for (const t of TYPES) for (const [pn, [pv, pr]] of Object.entries(POSES)) {
        n = pv; r = pr; sd = [n[1] * r[2] - n[2] * r[1], n[2] * r[0] - n[0] * r[2], n[0] * r[1] - n[1] * r[0]];
        cur = { t, z: 0x2000, behind: true }; await hold();
        const base = screen();
        const gaps = [];
        let line = [];
        for (let zh = Z0; zh >= Z1; zh -= ZS) {
            cur = { t, z: zh << 8 }; await hold();
            const sc = screen(); let m = 0;
            // round the ship's centre, as far as the ship reaches (130 units
            // or so: the Cobra's half-span), plus four pixels
            const h = Math.min(120, 4 + Math.ceil(130 * 256 / (zh << 8)));
            for (let y = Math.max(18, 96 - h); y <= Math.min(189, 96 + h); y++) for (let x = Math.max(2, 192 - h); x <= Math.min(253, 192 + h); x++) if (sc.lit(x, y) && !base.lit(x, y)) m++;
            if (m === 0) gaps.push(zh);
            line.push(`${zh.toString(16)}:${m}`);
        }
        say(`type ${String(t).padStart(2)} ${pn.padEnd(5)}: ${line.join(" ")}`);
        console.log(`type ${String(t).padStart(2)} ${pn.padEnd(5)}: ${gaps.length ? `GAP at z_hi ${gaps.map(g => "&" + g.toString(16)).join(" ")}` : "drawn at every z"}`);
        bad += gaps.length;
    }
}
console.log(bad ? `DOTGAP FAIL (${bad} frames drew nothing)` : "DOTGAP PASS");
process.exit(bad ? 1 : 0);
