// The moon is solid (1-source-files/main-sources/elite-moon.asm, MOONHIT): fly the gate's pilot
// to iteration FROM, then hold the keys off and, each iteration, put the
// planet (slot 0) where the system's moon (by --h: the seed's s0_hi, s1_hi =
// s2_hi = 0) has its centre at (0, 0, --m) from us, in the coordinates' high
// bytes, with the planet facing us (nosev (0, 0, -1), sidev (1, 0, 0)), our
// speed 0. Reports whether DEATH ran within --n iterations (MOONHIT tests on
// one iteration in 32).
//
// node 6-harness/mmoonhit.mjs [--tree T] --h H --m M [--from 300] [--n 40]
// prints "MOONHIT h=.. m=.. radius=.. death=yes|no (iteration ..)"
import { runElite, loadSyms, mapOfLabel, mapAt, ROOT } from "./mlib.mjs";
import { makePilot, patchCommander } from "./mpilot.mjs";
const a = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, arr) => { if (v.startsWith("--")) acc.push([v.slice(2), arr[i + 1] && !arr[i + 1].startsWith("--") ? arr[i + 1] : true]); return acc; }, []));
const TREE = a.tree || ROOT.replace(/\/$/, "");
const sy = loadSyms(`${TREE}/3-assembled-output/symbols.txt`);
const FROM = +(a.from || 300), N = +(a.n || 40), H = parseInt(a.h, 16), M = +a.m;
const D = [3, 3.75, 4.5, 5.25][(H >> 2) & 3], RHO = [48, 56, 64, 72][(H >> 5) & 3];
const side = (H & 16) ? -1 : 1;
const e = [-1, 0, -1].map(c => side * D * 96 * c / Math.SQRT2);  // the moon's offset (high bytes)
const P = [0, 0, M].map((c, i) => Math.round(c - e[i]));
const pilot0 = makePilot();
const pilot = { ...pilot0, keys: c => (c.iterOf() >= FROM ? [] : pilot0.keys(c)), dks: c => (c.iterOf() >= FROM ? false : pilot0.dks ? pilot0.dks(c) : false), observe: pilot0.observe, P: pilot0.P };
let cur = -1, armed = false, death = -1;
const dm = mapOfLabel(sy, sy.DEATH_C !== undefined ? "DEATH_C" : "DEATH"), da = sy.DEATH_C ?? sy.DEATH;
await runElite({ disc: `${TREE}/5-compiled-game-discs/elite-master-sng47.ssd`, syms: sy, pilot, iters: FROM + N, patch: patchCommander, maxSecs: +(a.maxsecs || 90),
    onIter: (i, s, r) => {
        const cpu = r.cpu;
        if (!armed) { armed = true; cpu.debugInstruction.add(pc => { if (pc === da && death < 0 && cur >= FROM && (dm === "m" || dm === mapAt(cpu.romsel, pc))) death = cur; return false; }); }
        cur = i;
        if (i < FROM || death >= 0) return;
        const ram = cpu.ramRomOs, k0 = sy["K%"];
        const put = (o, v) => { const m = Math.abs(v); ram[k0 + o] = 0; ram[k0 + o + 1] = m & 255; ram[k0 + o + 2] = ((m >> 8) & 127) | (v < 0 ? 128 : 0); };
        P.forEach((c, j) => put(3 * j, c));
        const vec = (o, x, y, z) => [x, y, z].forEach((c, j) => { const m = Math.abs(c); ram[k0 + o + 2 * j] = m & 255; ram[k0 + o + 2 * j + 1] = ((m >> 8) & 127) | (c < 0 ? 128 : 0); });
        vec(9, 0, 0, -0x6000); vec(15, 0, 0x6000, 0); vec(21, 0x6000, 0, 0);
        ram[sy.FRIN] = 128;
        [H & 0xff, H, 0, 0, 0, 0].forEach((v, j) => { ram[sy.QQ2 + j] = j === 1 ? H : (j % 2 ? 0 : 0x55); });
        ram[sy.DELTA] = 0;
    } });
console.log(`MOONHIT h=${H.toString(16)} m=${M} radius=${RHO * 96 / 256} D=${D} death=${death >= 0 ? "yes (iteration " + death + ")" : "no"}`);
