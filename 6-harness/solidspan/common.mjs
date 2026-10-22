// common.mjs: replay an agentplay input log (run1) on a Master build, headless,
// as the agentplay tools' fbreplay.mjs does; 6-harness/README.md (shared by mspeed.mjs, sdump.mjs).
import { EliteMachine, loadSyms, CYCLES_PER_FRAME } from "../agentplay/lib.mjs";
import { DEFAULTS, seedBytes } from "../agentplay/session.mjs";
import { COMMANDERS } from "../agentplay/styles.mjs";
import { readFileSync, existsSync } from "fs";
import { dirname } from "path";
export { CYCLES_PER_FRAME };
export async function replayMachine(log, cand, csyms) {
    // (loadSyms reads banks.txt beside the symbols: without it the banked hooks, RDKEY's
    // among them, are dropped and the game never gets past its loading)
    if (!existsSync(dirname(csyms) + "/banks.txt")) throw new Error(`no banks.txt beside ${csyms}`);
    const L = { rlog: new Map(), rjoy: [[], []], ptr: [0, 0], pokes: new Map(), header: null };
    for (const l of readFileSync(log, "utf8").split("\n")) {
        if (!l) continue;
        const e = JSON.parse(l);
        if (e.header) L.header = e; else if (e.p !== undefined) L.rlog.set(e.p, e);
        else if (e.j !== undefined) L.rjoy[e.w].push([e.j, e.v]); else if (e.poke !== undefined) L.pokes.set(e.poke, e.v);
    }
    const H = L.header, rand = seedBytes(H.seed), cmdr = COMMANDERS[H.commander || "jameson"], patch = cmdr.patch ? m => cmdr.patch(m) : null;
    const ref = new EliteMachine({ name: "ref", disc: DEFAULTS.ref, syms: loadSyms(DEFAULTS.rsyms), input: { rdkey: () => [], dks5: () => false, joy: () => 0x80 }, rand, patch });
    await ref.boot(); for (let k = 0; k < 10000 && !ref.started; k++) ref.run(CYCLES_PER_FRAME);
    const m = new EliteMachine({ name: "cand", disc: cand, syms: loadSyms(csyms), rand, patch, seedFrom: ref, workarounds: H.workarounds || [], input: {
        rdkey: ctx => L.rlog.get(ctx.poll)?.k || [], dks5: ctx => { const e = L.rlog.get(ctx.poll); return !!(e && e.t === "d"); },
        joy(ctx) { const l = L.rjoy[ctx.which]; while (L.ptr[ctx.which] + 1 < l.length && l[L.ptr[ctx.which] + 1][0] <= ctx.joy) L.ptr[ctx.which]++; const e = l[L.ptr[ctx.which]]; return e && e[0] <= ctx.joy ? e[1] : 0x80; } } });
    await m.boot(); m.pokes = L.pokes;
    return m;
}
