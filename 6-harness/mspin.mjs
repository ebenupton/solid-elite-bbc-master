// The planet's turn per iteration, as the game has it and as the drawing has
// it (pf_spin), over the gate's run: at PF_HOOK's entry (the game's vectors)
// and at pf_beach's or pf_craters' entry (the drawing's), roofv and sidev,
// and the player's roll and pitch (ALP1, BET1); prints the median angle
// between consecutive iterations' vectors, overall and with the player not
// turning (ALP1 = BET1 = 0: the planet's spin alone), and the player's own
// turn (ALP1 and BET1, the roll and pitch, over 256 radians).
//
// node 6-harness/mspin.mjs [--disc d] [--syms s] [--iters N] [--seedfile f]
import { runElite, loadSyms, CAND_SYMS, CAND_DISC } from "./mlib.mjs";
import { makePilot, patchCommander } from "./mpilot.mjs";
import { readFileSync } from "fs";
import { parseArgs } from "./args.mjs";
const a = parseArgs({ disc: "value", syms: "value", iters: "value", seedfile: "value" });
const sy = loadSyms(a.syms || CAND_SYMS);
const seed = a.seedfile ? JSON.parse(readFileSync(a.seedfile, "utf8")) : null;
let cur = -1, inst = false;
const game = [], draw = [];
const vec = (m, o) => [0, 1, 2].map(j => { const lo = m[sy.INWK + o + 2 * j], hi = m[sy.INWK + o + 2 * j + 1]; const v = lo | (hi & 127) << 8; return hi & 128 ? -v : v; });
await runElite({ disc: a.disc || CAND_DISC, syms: sy, pilot: makePilot(), iters: +(a.iters || 10000), patch: patchCommander, seed, maxSecs: 40000,
    onIter: (i, s, r) => { cur = i; const cpu = r.cpu, m = cpu.ramRomOs; if (inst) return; inst = true;
        const b7 = n => sy[n] !== undefined;
        cpu.debugInstruction.add(pc => {
            if ((cpu.romsel & 15) !== 7) return false;
            if (pc === sy.PF_HOOK) game.push([cur, vec(m, 15), vec(m, 21), m[sy.ALP1], m[sy.BET1], m[sy.VIEW]]);
            else if ((b7("pf_beach") && pc === sy.pf_beach) || (b7("pf_craters") && pc === sy.pf_craters)) draw.push([cur, vec(m, 15), vec(m, 21)]);
            return false;
        }); } });
const ang = (u, v) => { const d = u[0] * v[0] + u[1] * v[1] + u[2] * v[2], nu = Math.hypot(...u), nv = Math.hypot(...v); return Math.acos(Math.max(-1, Math.min(1, d / (nu * nv)))) * 180 / Math.PI; };
function rate(rows, still) {
    const out = [];
    for (let k = 1; k < rows.length; k++) {
        const [i, r, s, al, be, vw] = rows[k], p = rows[k - 1];
        if (p[0] !== i - 1) continue;
        if (still && (game.find(g => g[0] === i) || [0, 0, 0, 1, 1])[3] | (game.find(g => g[0] === i) || [0, 0, 0, 1, 1])[4]) continue;
        out.push(Math.max(ang(r, p[1]), ang(s, p[2])));
    }
    out.sort((x, y) => x - y);
    return out.length ? `${out[out.length >> 1].toFixed(2)} deg (n ${out.length})` : "none";
}
console.log(`game's vectors: median turn ${rate(game, false)}; player still: ${rate(game, true)}`);
const pl = game.map(g => Math.hypot(g[3] & 127, g[4] & 127) / 256 * 180 / Math.PI).sort((x, y) => x - y);
const moving = pl.filter(x => x > 0);
console.log(`the player's own turn (ALP1, BET1 over 256 radians): zero in ${pl.length - moving.length} of ${pl.length} calls; when turning, median ${moving.length ? moving[moving.length >> 1].toFixed(2) : 0} deg, largest ${pl[pl.length - 1].toFixed(2)} deg`);
console.log(`drawing's vectors: median turn ${rate(draw, false)}; player still: ${rate(draw, true)}`);
process.exit(0);
