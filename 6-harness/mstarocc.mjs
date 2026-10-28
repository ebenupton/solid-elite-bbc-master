// Screenshots of stardust behind solid objects: a grid of stars is given to
// the renderer over a scene, to see that none shows through a fill (the
// planet's dithered sea, dark ship faces, a station's black docking slot,
// the sun beside the planet), as 2-build-files/starocc.py proves.
//
// node 6-harness/mstarocc.mjs --disc d --syms s --out dir [--scene name] [--tag t]
//                            [--grid x0,y0,dx,dy,size]
//
// Boots the build as mstation.mjs does (SHIFT+BREAK, a new commander,
// launch with f0); at the next MLOOP the scene's ship slots (K%'s first three,
// FRIN to JUNK) are put in and the speed set to 0. From then on, at every
// frame's star step, R_SX/R_SY/R_SS are overwritten with a grid of stars: by default
// 7 x 3 of all three sizes over the view, stepping a few pixels each frame;
// with --grid, 7 x 3 stars of one size (1..3) at x0 + i dx, y0 + j dy (screen
// pixels), the same every frame (to put them on one object). (The grid goes in
// at F_FRAME's ff_stars, before f_slot takes a docking slot's stars out.) Scenes:
//   planet   the planet filling the middle of the view (its sea dithered with
//            black), a transporter in front of it
//   station  the Coriolis station dead ahead, its docking slot filled black,
//            the planet behind it
//   both     the sun and the planet on screen together (the second disc)
//   ship     a transporter close ahead (its darker faces dithered with black)
// After 12 main-loop iterations <out>/<tag>-<scene>.png is taken.
import { MachineSession, BBC } from "./jsbeeb.mjs";
import { loadSyms, WORK } from "./mlib.mjs";
import { writeFileSync, mkdirSync } from "fs";
import { parseArgs } from "./args.mjs";
const a = parseArgs({ disc: "value", syms: "value", out: "value", scene: "value", tag: "value", grid: "value" });
if (!a.disc || !a.syms) { console.error("--disc and --syms are required"); process.exit(2); }
const sy = loadSyms(a.syms);
const OUT = a.out || `${WORK}starocc`; mkdirSync(OUT, { recursive: true });
const SCENE = a.scene || "station", TAG = a.tag || "stars";
// mstation.mjs's scene: K% (planet, station, transporter), FRIN .. JUNK
const KS = "000000a546003606014bca1db806198eba454ab8835d12c4102d5c00007f7f100000000024000000010000230e0000000020005a9cd0852e4590b52fc14b839b0000ff001e817e0af000000000fc06001d2f0000000018005c009100dc001800dd00108d820a00008018f16b072061";
const WS = "80020a0000000000000000000000000100000000000000010000000000000000000000000000000000000000000000";
const ks = Buffer.from(KS, "hex");
const put24 = (slot, off, v) => {           // a signed 24-bit coordinate (sign-magnitude)
    const m = Math.abs(v), b = 37 * slot + off;
    ks[b] = m & 255; ks[b + 1] = (m >> 8) & 255; ks[b + 2] = ((m >> 16) & 127) | (v < 0 ? 128 : 0);
};
const ws = Buffer.from(WS, "hex");
if (SCENE === "planet") {
    put24(0, 0, 0); put24(0, 3, 0); put24(0, 6, 90000);       // the planet ahead
    put24(1, 0, 0); put24(1, 3, 0); put24(1, 6, -60000);      // the station behind us
    put24(2, 0, -60); put24(2, 3, 30); put24(2, 6, 420);     // the transporter in front of it
} else if (SCENE === "both") {
    put24(0, 0, 9000); put24(0, 3, 0); put24(0, 6, 50000);    // the planet ahead, to the right
    put24(1, 0, 0); put24(1, 3, 0); put24(1, 6, -60000);
    put24(2, 0, 0); put24(2, 3, 0); put24(2, 6, -60000);
} else if (SCENE === "station") {
    put24(1, 6, 650);                                         // the station closer, its slot towards
    const o = 37 + 9;                                         // us (nosev -z, roofv y, sidev x):
    ks.fill(0, o, o + 18);                                    // its slot filled
    ks[o + 5] = 0xE0; ks[o + 6 + 3] = 0x60; ks[o + 12 + 1] = 0x60;
} else if (SCENE === "ship") {
    put24(0, 6, -90000);                                      // the planet behind us
    put24(1, 0, 0); put24(1, 3, 0); put24(1, 6, -60000);      // the station too
    put24(2, 0, 0); put24(2, 3, 0); put24(2, 6, 110);         // the transporter close, ahead
} else { console.error(`unknown scene ${SCENE}`); process.exit(2); }

const s = new MachineSession("Master"); await s.initialise(); await s.boot(30);
s.loadDisc(a.disc); s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
const cpu = s._machine.processor; const secs = n => s.runFor(2000000 * n);
const key = async (k, hold = 0.2, after = 1) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
const at = (pc, name) => { if (pc !== sy[name]) return false; const b = sy.__bank[name]; return b === undefined || (cpu.romsel & 15) === (b & 15); };
await secs(28); await key("N"); await secs(3); await key("SPACE"); await secs(4);
await key("F0", 0.2, 12);
const ram = cpu.ramRomOs;
const NDSTAR = sy.R_SX - sy.R_SS;
let atLoop = false, phase = 0, iters = 0, frame = 0;
cpu.debugInstruction.add(pc => {
    if (phase === 0) { if (at(pc, "MLOOP")) atLoop = true; return false; }
    if (at(pc, "MLOOP")) {
        iters++;
        if (SCENE === "both") {                // the sun: the planet's slot sun-like (SUN draws slot 1 as the sun)
            ram[sy.FRIN + 1] = 129;
            const b = sy["K%"] + 37;
            for (const [off, val] of [[0, -30000], [3, -6000], [6, 70000]]) {
                const m = Math.abs(val); ram[b + off] = m & 255; ram[b + off + 1] = (m >> 8) & 255; ram[b + off + 2] = ((m >> 16) & 127) | (val < 0 ? 128 : 0);
            }
        }
    }
    if (at(pc, "ff_stars")) {                  // the grid: 7 x 3 stars, sizes 1, 2, 3 (before f_slot)
        frame++;
        const g = a.grid ? a.grid.split(",").map(Number) : null;
        const ox = (frame * 5) % 24, oy = (frame * 7) % 40;
        for (let i = 0; i < NDSTAR; i++) {
            const gx = i % 7, gy = Math.floor(i / 7);
            ram[sy.R_SX + i] = (g ? g[0] + gx * g[2] : 8 + ox + gx * 36) & 255;
            ram[sy.R_SY + i] = g ? g[1] + gy * g[3] : 20 + oy + gy * 50;
            ram[sy.R_SS + i] = g ? g[4] : 1 + (i % 3);
        }
    }
    return false;
});
for (let k = 0; k < 200 && !atLoop; k++) await s.runFor(20000);
if (!atLoop) { console.log("STAROCC FAIL: never reached MLOOP"); process.exit(1); }
ks.forEach((b, i) => { ram[sy["K%"] + i] = b; });
ws.forEach((b, i) => { ram[sy.FRIN + i] = b; });
if (SCENE === "both") ram[sy.FRIN + 1] = 129;
ram[sy.DELTA] = 0; ram[sy.QQ11] = 0; ram[sy.VIEW] = 0;
phase = 1;
for (let k = 0; k < 4000 && iters < 12; k++) await s.runFor(20000);
const f = `${OUT}/${TAG}-${SCENE}.png`;
writeFileSync(f, await s.screenshotActive({ scale: 1 }));
console.log(`${SCENE}: ${iters} iterations, ${frame} frames with the grid; ${f}`);
process.exit(0);
