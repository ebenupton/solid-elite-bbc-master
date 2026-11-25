// The last seconds of a docking run, posed: the space station dead ahead with
// its slot towards us, the sun (parked, as in the safe zone) straight ahead
// beyond it, and the stardust, flown in at a steady speed until we dock.
//
// node 6-harness/mdockview.mjs [--disc d] [--syms s] [--out dir] [--z z0]
//         [--speed s] [--sx x] [--sy y] [--every n] [--roll r] [--at k --out2 z] [--n iterations]
//
// Boots the build (SHIFT+BREAK, a new commander, launch with f0), puts the
// scene in at an MLOOP (as mbench.mjs poses its scenes) and flies on. At each
// MLOOP it notes the station's z, and every n iterations (and every one once
// the station is nearer than 400) writes a screenshot of the screen on show
// to <out>/dv-<iteration>-z<z>.png. With --at k --out2 z the station is put
// at z at iteration k (with --speed 0 and --z between 128 and the slot's
// face, 160, we sit inside the station until then, out of docking range).
import { MachineSession, BBC } from "./jsbeeb.mjs";
import { loadSyms, CAND_DISC, CAND_SYMS, WORK, pinRtc } from "./mlib.mjs";
import { writeFileSync, mkdirSync } from "fs";
import { parseArgs } from "./args.mjs";
const a = parseArgs({ disc: "value", syms: "value", out: "value", z: "value", speed: "value", sx: "value", sy: "value", every: "value", roll: "value", out2: "value", at: "value", n: "value" });
const sy = loadSyms(a.syms || CAND_SYMS);
const OUT = a.out || `${WORK}dockview`; mkdirSync(OUT, { recursive: true });
const NI = 37, SST = 2, unit = 0x6000;
const Z0 = +(a.z || 1400), SPEED = +(a.speed || 12), EVERY = +(a.every || 4);
function blockBytes({ x, y, z, nose = [0, 0, -1], roof = [0, 1, 0], side = [1, 0, 0], speed = 0, roll = 0, pitch = 0, heap = 0x0800 }) {
    const b = new Array(NI).fill(0);
    const c = (o, v) => { const m = Math.abs(Math.round(v)); b[o] = m & 255; b[o + 1] = (m >> 8) & 255; b[o + 2] = ((m >> 16) & 127) | (v < 0 ? 128 : 0); };
    c(0, x); c(3, y); c(6, z);
    const v = (o, w) => w.forEach((q, j) => { const m = Math.min(32767, Math.round(Math.abs(q) * unit)); b[o + 2 * j] = m & 255; b[o + 2 * j + 1] = (m >> 8) | (q < 0 ? 128 : 0); });
    v(9, nose); v(15, roof); v(21, side);
    b[27] = speed; b[29] = roll; b[30] = pitch; b[33] = heap & 255; b[34] = heap >> 8; b[35] = 100;
    return b;
}
const R = r => 24576 * 256 / r;
const s = new MachineSession("Master"); await s.initialise(); pinRtc(s); await s.boot(30);
s.loadDisc(a.disc || CAND_DISC); s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
const cpu = s._machine.processor, ram = cpu.ramRomOs, secs = n => s.runFor(2000000 * n);
const key = async (k, hold = 0.2, after = 1) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
await secs(28); await key("N"); await secs(3); await key("SPACE"); await secs(4); await key("F0", 0.2, 12);
const at = (pc, n) => sy[n] !== undefined && pc === sy[n] && (sy.__bank[n] === undefined || sy[n] < 0x8000 || (cpu.romsel & 15) === (sy.__bank[n] & 15));
function pose() {
    const K = sy["K%"];
    const put = (slot, type, b) => { for (let i = 0; i < NI; i++) ram[K + NI * slot + i] = b[i]; ram[sy.FRIN + slot] = type; };
    for (let i = 0; i <= 12; i++) ram[sy.FRIN + i] = 0;
    for (let i = 0; i < 34; i++) ram[sy.MANY + i] = 0;
    ram[sy.JUNK] = 0;
    put(0, 128, blockBytes({ x: 0, y: -20000, z: -80000 }));
    put(1, SST, blockBytes({ x: 0, y: 0, z: Z0, roof: [1, 0, 0], side: [0, -1, 0], roll: +(a.roll || 0), heap: sy.LSO }));   // the slot horizontal (ISDK: |roofv_x| large)
    ram[sy.SSPR] = 1;
    const sx = +(a.sx || 0.05), syy = +(a.sy || 0.03);
    if (sy.SUNPK !== undefined) { const b = blockBytes({ x: R(24) * sx, y: R(24) * syy, z: R(24) }); for (let i = 0; i < NI; i++) ram[sy.SUNPK + i] = b[i]; ram[sy.SUNPF] = 0x80; }
    ram[sy.SLSP] = 0x00; ram[sy.SLSP + 1] = 0x08;
    ram[sy.VIEW] = 0; ram[sy.DELTA] = SPEED; ram[sy.ALPHA] = 0; ram[sy.BETA] = 0; ram[sy.ALP1] = 0; ram[sy.ALP2] = 0; ram[sy.BET1] = 0; ram[sy.BET2] = 0;
    ram[sy.ENERGY] = 255; ram[sy.FSH] = 255; ram[sy.ASH] = 255; ram[sy.MCNT] = 1;
}
let posed = false, k = 0, docked = false, log = [], pending = null;
const z1 = () => { const b = sy["K%"] + NI; return (ram[b + 6] | ram[b + 7] << 8 | (ram[b + 8] & 127) << 16) * (ram[b + 8] & 128 ? -1 : 1); };
cpu.debugInstruction.add(pc => {
    if (!at(pc, "MLOOP")) return false;
    if (!posed) { pose(); posed = true; return false; }
    if (ram[sy.QQ11] !== 0) { docked = true; return false; }
    k++;
    if (a.at && k === +a.at) { const b = sy["K%"] + NI, v = +a.out2; ram[b + 6] = v & 255; ram[b + 7] = v >> 8; }   // --at k --out2 z: the station moved out to z at iteration k
    pending = { k, z: z1() };
    return false;
});
let shots = [];
for (let q = 0; q < 400000 && !docked && log.length < +(a.n || 400); q++) {
    await s.runFor(20000);
    if (pending) { const p = pending; pending = null; log.push(p);
        if (p.k % EVERY === 0 || p.z < 400) { const f = `${OUT}/dv-${String(p.k).padStart(3, "0")}-z${p.z}.png`; writeFileSync(f, await s.screenshotActive({ scale: 1 })); shots.push(f); } }
}
for (const p of log) console.log(`it ${p.k} z ${p.z}`);
console.log(docked ? "DOCKED" : "not docked"); console.log(shots.slice(-6).join("\n"));
process.exit(0);
