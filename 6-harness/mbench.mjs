// A speed benchmark that does not move when the game's random numbers do:
// frozen scenes. Boots the build (SHIFT+BREAK, a new commander, launch with
// f0, as 6-harness/msunnear.mjs), then for each scene puts the scene's state in
// at an MLOOP (the ship slots, the planet, the sun, the view, our speed and
// rotation), lets it run WARM iterations and snapshots the game state
// (mlib.regionsFor). Then it runs N iterations in windows of M: the snapshot
// is put back at the start of each window, so the scene starts the same in
// any build and moves for M iterations (the renderer does real work, and
// its memos hit as in play); within a window, at every MLOOP, RAND is put
// back and every slot after the scene's ships emptied (with MANY and SLSP
// as in the snapshot), so that no ship spawns and no random number taken
// before (the original's sun's edge, explosion clouds ...) changes what
// follows. The figure is the emulated cycles from one MLOOP to the next,
// averaged over the N iterations, and the iterations a second; and the work:
// those cycles less the frame layer's wait for the flip (7 cycles a turn of
// ff2's LDA GFLIP : BNE ff2), as the 25 a second cap makes the first figure
// move with the vsync's phase, by about 1% either way for a small change.
//
// The scenes (the front view unless said; positions in the game's units):
//   flight     cruising: the planet far off (radius about 20), three ships
//              ahead at 3000-6000, rolling a little
//   combat     five ships close round us (800-2000), turning, our rolling and
//              pitching; the planet small
//   beachball  the approach: the planet's beach ball filling the view
//              (radius about 110), one ship
//   sun        a visible sun (radius 32) beside the planet (radius 60)
//   docking    the station ahead at 1500, the planet behind it
//   zone       the safe zone: the station near and ahead, the sun parked
//              behind us (in a build without SUNPK the sun is S_SUN's or
//              none), two ships
//   rear       the beach ball in the rear view, with ships
//
// node 6-harness/mbench.mjs [--disc d] [--syms s] [--scene a,b] [--n 128] [--warm 8] [--out file.json] [--pin]
// --pin also puts in, at the pose, the stardust (a fixed pseudo-random field)
// and RAND, and poses only at an MLOOP with buffer 1 on show (GFRONT), so that
// nothing the boot and launch left behind, which moves with the build's speed,
// is carried into the scenes; run one scene a process (--scene) for figures
// that do not depend on the scenes before it either.
// Prints "scene: cycles/iteration it/s work" per scene.
import { MachineSession } from "/Users/ebenupton/.npm/_npx/e76f2a7d329553db/node_modules/jsbeeb/src/machine-session.js";
import { BBC } from "/Users/ebenupton/.npm/_npx/e76f2a7d329553db/node_modules/jsbeeb/src/utils.js";
import { loadSyms, ROOT, regionsFor, pinRtc } from "./mlib.mjs";
import { writeFileSync } from "fs";
import { parseArgs } from "./args.mjs";

const a = parseArgs({ disc: "value", syms: "value", scene: "value", n: "value", warm: "value", out: "value", pin: "flag" });
const SYMS = a.syms || `${ROOT}3-assembled-output/symbols.txt`, DISC = a.disc || `${ROOT}5-compiled-game-discs/elite-master-sng47.ssd`;
const sy = loadSyms(SYMS);
const N = +(a.n || 128), WARM = +(a.warm || 8), M = 32;
const NI = 37;
// ship types (elite-source.asm)
const SST = 2, CYL = 11, ADA = 21, MAM = 18, KRA = 19, SIDE = 17, VIPER = 16, PYTHON = 12, ASP = 26;

// a block: position, orientation (nosev, roofv, sidev as unit vectors), and the rest
const unit = 0x6000;
function blockBytes({ x, y, z, nose = [0, 0, -1], roof = [0, 1, 0], side = [1, 0, 0], speed = 0, roll = 0, pitch = 0, ai = 0, newb = 0, energy = 100, heap = 0x0800 }) {
    const b = new Array(NI).fill(0);
    const c = (o, v) => { const m = Math.abs(Math.round(v)); b[o] = m & 255; b[o + 1] = (m >> 8) & 255; b[o + 2] = ((m >> 16) & 127) | (v < 0 ? 128 : 0); };
    c(0, x); c(3, y); c(6, z);
    const v = (o, w) => w.forEach((q, j) => { const m = Math.min(32767, Math.round(Math.abs(q) * unit)); b[o + 2 * j] = m & 255; b[o + 2 * j + 1] = (m >> 8) | (q < 0 ? 128 : 0); });
    v(9, nose); v(15, roof); v(21, side);
    b[27] = speed; b[29] = roll; b[30] = pitch; b[32] = ai; b[33] = heap & 255; b[34] = heap >> 8; b[35] = energy; b[36] = newb;
    return b;
}
const HEAP = { [CYL]: 157, [ADA]: 93, [MAM]: 97, [KRA]: 89, [SIDE]: 65, [VIPER]: 81, [PYTHON]: 89, [ASP]: 105, [SST]: 0 };
// the scenes: planet (type 128, its block), slot 1 (the sun 129 or the station SST), ships
const R = r => 24576 * 256 / r;                    // the z for a disc of radius r (PLANET: 24576 / z)
const SCENES = {
    flight: { planet: { x: -R(20) * 0.3, y: R(20) * 0.2, z: R(20) }, slot1: { type: 129, x: R(8), y: R(8) * 0.4, z: -R(8) },
        ships: [[CYL, { x: 900, y: 300, z: 3000, speed: 10, roll: 2 }], [ADA, { x: -1200, y: -400, z: 4500, speed: 12 }], [VIPER, { x: 300, y: 900, z: 6000, speed: 14 }]], view: 0, delta: 15, alpha: 2, beta: 0 },
    combat: { planet: { x: R(15), y: R(15) * 0.5, z: R(15) }, slot1: { type: 129, x: -R(6), y: 0, z: -R(6) },
        ships: [[CYL, { x: 300, y: 200, z: 900, speed: 20, roll: 3, pitch: 2 }], [MAM, { x: -500, y: 100, z: 1200, speed: 25, roll: 130 }], [KRA, { x: 200, y: -600, z: 1500, speed: 22, pitch: 3 }],
            [SIDE, { x: -900, y: -200, z: 800, speed: 30, roll: 4 }], [ASP, { x: 700, y: 500, z: 2000, speed: 18, pitch: 130 }]], view: 0, delta: 20, alpha: 3, beta: 2 },
    beachball: { planet: { x: 0, y: -R(110) * 0.3, z: R(110) }, slot1: { type: 129, x: R(10), y: R(10), z: -R(10) },
        ships: [[PYTHON, { x: 800, y: 600, z: 2500, speed: 10 }]], view: 0, delta: 12, alpha: 1, beta: 0 },
    sun: { planet: { x: -R(60) * 0.4, y: -R(60) * 0.3, z: R(60) }, slot1: { type: 129, x: R(32) * 0.25, y: R(32) * 0.15, z: R(32) },
        ships: [], view: 0, delta: 1, alpha: 0, beta: 0 },
    docking: { planet: { x: 0, y: 0, z: 80000 }, slot1: { type: SST, x: 0, y: 0, z: 1500, roll: 255 }, park: { x: R(8), y: R(8), z: -R(8) },
        ships: [], view: 0, delta: 10, alpha: 0, beta: 0 },
    zone: { planet: { x: 0, y: -30000, z: 60000 }, slot1: { type: SST, x: 400, y: -500, z: 4000, roll: 255 }, park: { x: -R(7), y: R(7) * 0.2, z: -R(7) },
        ships: [[VIPER, { x: 500, y: 300, z: 2000, speed: 15, roll: 2 }], [CYL, { x: -800, y: 200, z: 3500, speed: 12 }]], view: 0, delta: 15, alpha: 2, beta: 1 },
    rear: { planet: { x: 0, y: R(100) * 0.3, z: -R(100) }, slot1: { type: 129, x: R(10), y: 0, z: R(10) },
        ships: [[CYL, { x: 500, y: 300, z: -2500, speed: 10, roll: 2 }], [ADA, { x: -700, y: -300, z: -3500, speed: 12 }]], view: 1, delta: 10, alpha: 2, beta: 0 },
};
const which = (a.scene || Object.keys(SCENES).join(",")).split(",");

const s = new MachineSession("Master"); await s.initialise(); pinRtc(s); await s.boot(30);
s.loadDisc(DISC); s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
const cpu = s._machine.processor, ram = cpu.ramRomOs, secs = n => s.runFor(2000000 * n);
const key = async (k, hold = 0.2, after = 1) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
await secs(28); await key("N"); await secs(3); await key("SPACE"); await secs(4); await key("F0", 0.2, 12);
const regions = regionsFor(sy);
const at = (pc, n) => pc === sy[n] && (sy.__bank[n] === undefined || sy[n] < 0x8000 || (cpu.romsel & 15) === (sy.__bank[n] & 15));
const cyc = () => cpu.cycleSeconds * 2e6 + cpu.currentCycles;
const FF2 = sy.ff2;                                 // the frame layer's wait for the flip: LDA GFLIP : BNE ff2

function pose(sc) {
    const K = sy["K%"];
    const put = (slot, type, b) => { for (let i = 0; i < NI; i++) ram[K + NI * slot + i] = b[i]; ram[sy.FRIN + slot] = type; };
    for (let i = 0; i <= 12; i++) ram[sy.FRIN + i] = 0;
    for (let i = 0; i < 40; i++) if (sy.MANY + i < sy.MANY + 34) ram[sy.MANY + i] = 0;
    ram[sy.JUNK] = 0;
    put(0, 128, blockBytes({ ...sc.planet, roll: 1, pitch: 1 }));
    put(1, sc.slot1.type, blockBytes({ ...sc.slot1, heap: sy.LSO }));
    if (sc.slot1.type === SST) ram[sy.SSPR] = 1;
    if (sc.park && sy.SUNPK !== undefined) { const b = blockBytes(sc.park); for (let i = 0; i < NI; i++) ram[sy.SUNPK + i] = b[i]; ram[sy.SUNPF] = 0x80; }
    let heap = 0x0800, n = 2;
    for (const [t, d] of sc.ships) { heap -= HEAP[t]; put(n++, t, blockBytes({ ...d, heap })); ram[sy.MANY + t]++; }
    ram[sy.SLSP] = heap & 255; ram[sy.SLSP + 1] = heap >> 8;
    ram[sy.VIEW] = sc.view; ram[sy.DELTA] = sc.delta; ram[sy.ALPHA] = sc.alpha; ram[sy.BETA] = sc.beta;
    if (a.pin) {                                    // --pin: the stardust and RAND put in too
        let q = 12345; const r8 = () => (q = (q * 1103515245 + 12345) & 0x7fffffff, (q >> 16) & 255);
        for (let i = 0; i < sy.SXL - sy.SX; i++) { ram[sy.SX + i] = r8(); ram[sy.SXL + i] = r8(); ram[sy.SY + i] = r8();
            ram[sy.SYL + i] = r8(); ram[sy.SZ + i] = r8() | 17; ram[sy.SZL + i] = r8(); }
        [0x49, 0x53, 0x7A, 0x2E].forEach((v, i) => { ram[sy.RAND + i] = v; });
    }
    ram[sy.ENERGY] = 255; ram[sy.FSH] = 255; ram[sy.ASH] = 255; ram[sy.MCNT] = 1;
}

const results = {};
for (const name of which) {
    const sc = SCENES[name];
    let k = -1, snap = null, times = [], posed = false, done = false, rand, many, slsp, spins = 0, lastPc = -1, spinAt = [];
    const h = cpu.debugInstruction.add(pc => {
        if (FF2 !== undefined && pc === FF2 && lastPc === FF2 + 3 && at(pc, "ff2")) spins++;
        lastPc = pc;
        if (!at(pc, "MLOOP") || done) return false;
        k++;
        if (!posed) { if (a.pin && ram[sy.GFRONT] !== 1) return false; pose(sc); posed = true; k = 0; return false; }
        if (k === WARM) { snap = regions.map(([b, n]) => Array.from(ram.subarray(b, b + n))); rand = Array.from(ram.subarray(sy.RAND, sy.RAND + 4));
            many = Array.from(ram.subarray(sy.MANY, sy.MANY + 34)); slsp = [ram[sy.SLSP], ram[sy.SLSP + 1]]; }
        if (snap) {
            if (times.length % M === 0) regions.forEach(([b], j) => snap[j].forEach((v, i) => { ram[b + i] = v; }));
            else {
                rand.forEach((v, i) => { ram[sy.RAND + i] = v; }); many.forEach((v, i) => { ram[sy.MANY + i] = v; });
                ram[sy.SLSP] = slsp[0]; ram[sy.SLSP + 1] = slsp[1];
                for (let i = 2 + sc.ships.length; i <= 12; i++) ram[sy.FRIN + i] = 0;
            }
            times.push(cyc()); spinAt.push(spins);
        }
        if (times.length > N) done = true;
        return false;
    });
    for (let q = 0; q < 200000 && !done; q++) await s.runFor(20000);
    h.remove();
    const per = (times[times.length - 1] - times[0]) / (times.length - 1);
    const work = per - 7 * (spinAt[spinAt.length - 1] - spinAt[0]) / (times.length - 1);
    results[name] = { cycles: Math.round(per), its: +(2e6 / per).toFixed(3), work: Math.round(work), n: times.length - 1 };
    console.log(`${name.padEnd(10)} ${String(Math.round(per)).padStart(7)} cycles/iteration  ${(2e6 / per).toFixed(2).padStart(6)} it/s  ${String(Math.round(work)).padStart(7)} work`);
}
if (a.out) writeFileSync(a.out, JSON.stringify({ disc: DISC, N, WARM, results }, null, 1));
process.exit(0);
