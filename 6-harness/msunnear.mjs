// The sun near the planet (1-source-files/main-sources/gfx-ssun.asm): a posed scene, as
// mstation.mjs and mflarevis.mjs pose theirs. Boots the build
// (SHIFT+BREAK, a new commander, launch with f0: the station is in slot 1, so
// the game has no sun and S_SUN draws it), then at each MLOOP puts the planet,
// the station and the sun where the script says, with the speed 0 and no keys
// (so S_SUN does not turn D): the sun as S_SUN's D = sun - planet (ss_d, in
// the shared workspace) and SS_OK. At each frame's end (F_FRAME after f_stars,
// bank 6) the back buffer is dumped, with the sun and the planet as recorded
// and the lens flare's probes in sight (fl_vn at fl_seen, in the flare's
// bank).
//
// The script (--script sunrise, the default): the planet's limb across the
// lower screen; the sun rises from behind it (frames 0..RISE-1), holds, then
// the station crosses in front of it (FLY frames), and holds.
//
// node 6-harness/msunnear.mjs [--disc d] [--syms s] [--out dir] [--rise 64]
//      [--fly 56] [--hold 12] [--pz --psx --psy] [--sz --sx --sy0 --sy1]
// (the planet's z and centre on the screen; the sun's z, x and its rise)
// --spawn: no script. The game's own sun is put in slot 1, in view beside the
// planet, with the planet placed so that part 15 spawns the station 40000
// ahead within 32 iterations; then the game runs untouched (speed 0, no
// keys). Prints the sun as drawn each frame: the game's (SUN) until the
// station takes the slot, then S_SUN's, which must carry on from it.
// Writes <out>/frame-NNNNNN.bin (the back buffer, &4000-&6FFF) and
// <out>/frames.json; 2-build-files/sunnear.py renders them.
import { MachineSession, BBC } from "./jsbeeb.mjs";
import { loadSyms, mapOfLabel, physRead, CAND_SYMS, CAND_DISC, WORK } from "./mlib.mjs";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { parseArgs } from "./args.mjs";
const a = parseArgs({ disc: "value", syms: "value", out: "value", rise: "value", fly: "value", hold: "value",
    pz: "value", psx: "value", psy: "value", sz: "value", sx: "value", sy0: "value", sy1: "value", spawn: "flag" });
const SYMS = a.syms || CAND_SYMS;
const sy = loadSyms(SYMS);
const OUT = a.out || `${WORK}sunnear`; mkdirSync(OUT, { recursive: true });
const RISE = +(a.rise || 64), FLY = +(a.fly || 56), HOLD = +(a.hold || 12);
const N = a.spawn ? 40 : HOLD + RISE + HOLD + FLY + HOLD;

// FEND: the instruction after F_FRAME's JSR f_stars (as mflarevis.mjs finds it)
const lst = readFileSync(SYMS.replace(/symbols\.txt$/, "compile.txt"), "utf8").split("\n");
function jsrIn(target) {
    const t = target.toString(16).toUpperCase().padStart(4, "0");
    for (const l of lst) {
        const m = l.match(/^\s+([0-9A-F]{4})\s+20 ([0-9A-F]{2}) ([0-9A-F]{2})\s+JSR &([0-9A-F]{4})/);
        if (m && m[4] === t && parseInt(m[1], 16) > sy.F_FRAME && parseInt(m[1], 16) < sy.F_FRAME + 0x200) return parseInt(m[1], 16);
    }
    throw new Error("JSR not found");
}
const FEND = jsrIn(sy.f_stars) + 3;
const AFT = { discs: jsrIn(sy.f_discs) + 3, disc2: jsrIn(sy.f_disc2) + 3, flt: jsrIn(sy.f_flt) + 3 };

// the scene (front view; screen x = 128 + 256 x / z, y = 96 - 256 y / z, a
// disc's radius 24576 * 256 / z)
const PZ = +(a.pz || 52429), PSX = +(a.psx || 150), PSY = +(a.psy || 222);                 // the planet: radius 120, centre (150, 222)
const P = [Math.round((PSX - 128) * PZ / 256), Math.round((96 - PSY) * PZ / 256), PZ];
const SZ = +(a.sz || 6 * 65536);                                   // the sun: radius 16
const SX = +(a.sx || 132), SY0 = +(a.sy0 || 134), SY1 = +(a.sy1 || 58);                    // rises from (132, 134), behind the limb, to (132, 58)
const TZ = 1700, TY = 58, TX0 = -60, TX1 = 330;         // the station crosses at z 1700 along y = 58
const ease = t => t * t * (3 - 2 * t);
function pose(k) {
    let sy_ = SY0, st = null;
    if (k >= HOLD) sy_ = SY0 + (SY1 - SY0) * ease(Math.min(1, (k - HOLD) / (RISE - 1)));
    const f0 = HOLD + RISE + HOLD;
    if (k >= f0 && k < f0 + FLY) st = TX0 + (TX1 - TX0) * (k - f0) / (FLY - 1);
    return { sun: [SX, sy_], st };
}

const s = new MachineSession("Master"); await s.initialise(); await s.boot(30);
s.loadDisc(a.disc || CAND_DISC); s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
const cpu = s._machine.processor; const secs = n => s.runFor(2000000 * n);
const key = async (k, hold = 0.2, after = 1) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
const at = (pc, name) => { if (pc !== sy[name]) return false; const b = sy.__bank[name]; return b === undefined || (cpu.romsel & 15) === (b & 15); };
await secs(28); await key("N"); await secs(3); await key("SPACE"); await secs(4);
await key("F0", 0.2, 12);

const ram = cpu.ramRomOs;
const SSB = (sy.__bank.S_SUN ?? 7) & 15, FLB = (sy.__bank.fl_seen ?? 5) & 15;   // (S_SUN's bank, the flare's)
const b7 = addr => addr < 0x8000 ? addr : cpu.romOffset + SSB * 16384 + addr - 0x8000;   // S_SUN's variables (ss_d: main RAM)
const put = (base, o, v) => { const m = Math.abs(v); ram[base + o] = m & 255; ram[base + o + 1] = (m >> 8) & 255; ram[base + o + 2] = ((m >> 16) & 127) | (v < 0 ? 128 : 0); };
const putTc = (addr, v) => { const u = v & 0xffffff; ram[b7(addr)] = u & 255; ram[b7(addr) + 1] = (u >> 8) & 255; ram[b7(addr) + 2] = (u >> 16) & 255; };
const M6 = mapOfLabel(sy, "F_PLX");
const b6 = x => physRead(cpu, M6, x);
const w16m = x => { const v = ram[x] | ram[x + 1] << 8; return v > 32767 ? v - 65536 : v; };
const w16 = x => { const v = b6(x) | b6(x + 1) << 8; return v > 32767 ? v - 65536 : v; };
const cyc = () => (cpu.cycleSeconds + cpu.currentCycles / 2e6) * 2e6;

let phase = 0, k = -1, atLoop = false, seen = -1, tff = 0, tss = 0, tssd = 0, t = {}, cy = {};
const loopAt = [];
const frames = [], log = [];
const K1 = sy["K%"] + 37;
function doSpawn() {
    // the planet 60000 ahead and 20000 below (within part 15's range: every
    // sign byte 0), nosev (0, 0, -1), so the station's point (planet + 2
    // nosev) is 10848 ahead
    const vec = (b, o, x, y, z) => { [x, y, z].forEach((c, j) => { ram[b + o + 2 * j] = 0; ram[b + o + 2 * j + 1] = c; }); };
    const K0 = sy["K%"];
    put(K0, 0, 0); put(K0, 3, -20000); put(K0, 6, 60000);
    vec(K0, 9, 0, 0, 0xe0); vec(K0, 15, 0, 0x60, 0); vec(K0, 21, 0x60, 0, 0);
    // the sun: at (180, 50) on the screen, 5 sign units away (radius 19)
    put(K1, 0, 66560); put(K1, 3, 58880); put(K1, 6, 5 * 65536);
    ram[K1 + 27] = 0; ram[K1 + 29] = 0; ram[K1 + 30] = 0;
    ram[sy.FRIN + 1] = 129; ram[sy.SSPR] = 0;
    for (let j = 2; j < 12; j++) ram[sy.FRIN + j] = 0;
    ram[sy.DELTA] = 0; ram[sy.VIEW] = 0;
    log.push(`spawn scene in; MCNT ${ram[sy.MCNT]}`);
}
function doPose() {
    if (a.spawn) {                                      // (the planet spins: its
        if (k === 0) doSpawn();                         // orientation is put back
        else if (ram[sy.FRIN + 1] === 129) {            // until the station comes)
            const vec = (b, o, x, y, z) => { [x, y, z].forEach((c, j) => { ram[b + o + 2 * j] = 0; ram[b + o + 2 * j + 1] = c; }); };
            vec(sy["K%"], 9, 0, 0, 0xe0); vec(sy["K%"], 15, 0, 0x60, 0); vec(sy["K%"], 21, 0x60, 0, 0);
        }
        ram[sy.DELTA] = 0;
        return;
    }
    const { sun, st } = pose(k);
    put(sy["K%"], 0, P[0]); put(sy["K%"], 3, P[1]); put(sy["K%"], 6, P[2]);
    const S = [Math.round((sun[0] - 128) * SZ / 256), Math.round((96 - sun[1]) * SZ / 256), SZ];
    if (sy.ss_d !== undefined) {                        // (a build without S_SUN: no sun)
        for (let j = 0; j < 3; j++) putTc(sy.ss_d + 3 * j, S[j] - P[j]);
        ram[sy.SS_OK] = 0xff;
    }
    // the station: off to the side until it crosses, facing us, rolling
    const tx = st === null ? (k < HOLD + RISE + HOLD ? TX0 : TX1) : st;
    put(K1, 0, Math.round((tx - 128) * TZ / 256)); put(K1, 3, Math.round((96 - TY) * TZ / 256)); put(K1, 6, TZ);
    if (k === 0) {
        const vec = (o, x, y, z) => { [x, y, z].forEach((c, j) => { ram[K1 + o + 2 * j] = 0; ram[K1 + o + 2 * j + 1] = c; }); };
        vec(9, 0, 0, 0xe0); vec(15, 0, 0x60, 0); vec(21, 0x60, 0, 0);
        ram[K1 + 27] = 0;
    }
    ram[sy.DELTA] = 0; ram[sy.VIEW] = 0;
    for (let j = 2; j < 12; j++) if (ram[sy.FRIN + j]) { ram[sy.FRIN + j] = 0; log.push(`frame ${k}: slot ${j} emptied`); }
}
cpu.debugInstruction.add(pc => {
    if (phase === 0) { if (at(pc, "MLOOP")) atLoop = true; return false; }
    if (at(pc, "MLOOP")) { loopAt.push(cyc()); k++; if (k < N) doPose(); return false; }
    const bank = cpu.romsel & 15;
    if (bank === SSB && pc === sy.S_SUN) tss = cyc();
    else if (bank === 6 && pc === sy.F_FRAME) { tssd = sy.S_SUN !== undefined ? Math.round(cyc() - tss) : 0; tff = cyc(); seen = -1; cy = {}; }
    else if (bank === 6 && pc === sy.f_discs) t.d1 = cyc();
    else if (bank === 6 && pc === AFT.discs) { cy.discs = Math.round(cyc() - t.d1); t.d2 = cyc(); }
    else if (bank === 6 && pc === AFT.disc2) cy.disc2 = Math.round(cyc() - t.d2);
    else if (bank === 6 && pc === sy.f_flt) t.fl = cyc();
    else if (bank === 6 && pc === AFT.flt) cy.flt = Math.round(cyc() - t.fl);
    else if (bank === FLB && pc === sy.fl_seen) seen = ram[0x17];
    else if (bank === 6 && pc === FEND && k >= 0 && k < N) {
        const back = b6(sy.F_BACK);
        const base = back ? 0x8000 : 0;
        const buf = Buffer.alloc(0x3000);
        for (let q = 0; q < 0x3000; q++) buf[q] = ram[base + 0x4000 + q];
        const pal = Array.from(s._machine.processor.video.ulaPal.slice(0, 16));
        frames.push({ k, back, sun: [w16m(sy.F_SUX), w16m(sy.F_SUY), ram[sy.GSUNR], ram[sy.GSUNON]],
            planet: [w16(sy.F_PLX), w16(sy.F_PLY), b6(sy.F_PLR), b6(sy.F_PLON)], seen, ssun: tssd, frame: Math.round(cyc() - tff), ...cy,
            slot1: ram[sy.FRIN + 1], pal });
        writeFileSync(`${OUT}/frame-${String(k).padStart(6, "0")}.bin`, buf);
    }
    return false;
});
for (let q = 0; q < 200 && !atLoop; q++) await s.runFor(20000);
if (!atLoop) { console.log("SUNNEAR FAIL: never reached MLOOP"); process.exit(1); }
phase = 1;
for (let q = 0; q < 20000 && k < N + 1; q++) await s.runFor(20000);
writeFileSync(`${OUT}/frames.json`, JSON.stringify({ frames, log, N, RISE, FLY, HOLD, loopAt }));
// it/s over each part of the script (MLOOP to MLOOP, emulated)
const span = (p, q) => ((q - p) / ((loopAt[q] - loopAt[p]) / 2e6)).toFixed(3);
const parts = [["hidden", 0, HOLD + 30], ["rising", HOLD + 30, HOLD + RISE], ["clear", HOLD + RISE, HOLD + RISE + HOLD], ["flyby", HOLD + RISE + HOLD, HOLD + RISE + HOLD + FLY], ["all", 0, N]];
console.log("it/s: " + parts.map(([n, p, q]) => `${n} ${span(p, Math.min(q, loopAt.length - 1))}`).join(", "));
console.log(`${frames.length} frames of ${N}`); for (const l of log.slice(0, 20)) console.log(l);
for (const f of frames) console.log(f.k, "slot1", f.slot1, "sun", f.sun.join(" "), "planet", f.planet.join(" "), "seen", f.seen, "S_SUN", f.ssun, "discs", f.discs, "disc2", f.disc2, "flt", f.flt);
process.exit(0);
