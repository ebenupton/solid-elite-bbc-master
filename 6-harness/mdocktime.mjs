// The docked screens' drawing times: node 6-harness/mdocktime.mjs [--disc d] [--syms s]
//
// Boots the build (SHIFT+BREAK, the RTC pinned, as the gate), answers the
// title's questions, and on the Status screen presses each docked-screen key
// in turn: f8 Status, f1 Buy Cargo, f2 Sell Cargo, f3 Equip Ship, f4 the
// Galactic Chart, f5 the Short-range Chart, f6 Data on System, f7 Market
// Prices, f9 Inventory (each back to Status after, so each screen is drawn
// from the same one; f1 and f3 then wait for a number, answered with RETURN).
// A screen's time is the cycles from the first entry to RDKEY after its key
// goes down (the scan that sees the key) to the next entry to RDKEY (the
// main loop's next scan, or the number prompt's first): the dispatch and the
// drawing. That is in whole frames when the screen waits for the vertical
// sync (WSCAN), so the busy cycles are given too: the same interval less the
// cycles spent in WSCAN's wait loop (DELL1K). The emulation is
// deterministic, so a build gives the same cycles to the cycle; compare two
// builds by running it on each. Prints one line per screen (cycles and ms at
// 2 MHz) and their total; --json writes them too.
import { loadSyms, mapAt, mapOfLabel, bootMaster, CAND_DISC, CAND_SYMS } from "./mlib.mjs";
import { BBC } from "./jsbeeb.mjs";
import { writeFileSync } from "fs";

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, v, i, arr) => {
    if (v.startsWith("--")) acc.push([v.slice(2), arr[i + 1] && !arr[i + 1].startsWith("--") ? arr[i + 1] : true]);
    return acc;
}, []));
const DISC = args.disc || CAND_DISC;
const sy = loadSyms(args.syms || CAND_SYMS);

const s = await bootMaster(DISC);
const cpu = s._machine.processor;
const cyc = () => cpu.cycleSeconds * 2e6 + cpu.currentCycles;
const secs = n => s.runFor(2000000 * n);
const rk = sy.RDKEY, rkm = mapOfLabel(sy, "RDKEY");
const wl = sy.DELL1K, wlm = mapOfLabel(sy, "DELL1K");
let armed = false, start = -1, took = -1, waited = 0, busy = -1, prev = -1, inWait = false;
cpu.debugInstruction.add(pc => {
    const now = cyc();
    if (start >= 0 && took < 0 && inWait) waited += now - prev;
    prev = now;
    inWait = (pc === wl || pc === wl + 2) && (wlm === "m" || mapAt(cpu.romsel, pc) === wlm);
    if (pc === rk && (rkm === "m" || mapAt(cpu.romsel, pc) === rkm)) {
        if (armed) { start = now; armed = false; waited = 0; }
        else if (start >= 0 && took < 0) { took = now - start; busy = took - waited; }
    }
    return false;
});
const key = async (k, hold = 0.15, after = 3) => {
    cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after);
};
const timed = async k => {
    start = -1; took = -1; armed = true;
    await key(k);
    return [took, busy];
};
await secs(28);
await key("N", 0.15, 1.5); await secs(3); await key("SPACE", 0.15, 1.5); await secs(4);
const out = {};
let total = 0, tbusy = 0;
for (const [k, n] of [["F8", "status"], ["F1", "buy"], ["F2", "sell"], ["F3", "equip"], ["F4", "galchart"],
                      ["F5", "shortchart"], ["F6", "data"], ["F7", "market"], ["F9", "inventory"]]) {
    await key("F8", 0.15, 2);
    const [t, b] = await timed(k);
    if (k === "F1" || k === "F3") await key("RETURN", 0.1, 2);
    out[n] = { cycles: t, busy: b }; total += t; tbusy += b;
    console.log(`${n.padEnd(11)} ${String(t).padStart(8)} cycles ${(t / 2000).toFixed(2).padStart(7)} ms, busy ${String(b).padStart(8)}`);
}
console.log(`${"total".padEnd(11)} ${String(total).padStart(8)} cycles ${(total / 2000).toFixed(2).padStart(7)} ms, busy ${String(tbusy).padStart(8)}`);
if (args.json) writeFileSync(args.json, JSON.stringify({ disc: DISC, screens: out, total, busy: tbusy }, null, 1));
process.exit(0);
