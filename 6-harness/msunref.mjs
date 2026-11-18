// The proofs that the reference's patch (2-build-files/sunref/sunref.py:
// 3-assembled-output/sunref.json, the sun's parking assembled for the released SNG47, and
// the sun's edge drawing no random numbers)
// changes the original only as it should (docs/renderer.md, "The sun's
// parking"):
//
//   1. the bytes: SNG47 booted to TT170, its main RAM (&0000-&7FFF) before and
//      after the patch is written; every byte that differs must be in the
//      patch's code (&0B9D-, SNG47's unused &0B9D-&0CFF) or at one of its
//      sites, and each site's bytes before must be the patch's orig
//      (applyRefPatch checks them, and finds the unlabelled ones);
//   2. the passive variant (3-assembled-output/sunref-passive.json: part 14 and TT110 call
//      the original's WPLS and NWSPS, so the sun is never parked): SNG47
//      against SNG47 with it, mcompare.mjs --loose over the gate's 10000
//      iterations and over the views run (1500, --views), game state
//      identical, and the parked sun's region unchanged throughout. So
//      SUNSC, SUNBK's test, the moved station heap and the anchors change
//      nothing unless a sun is parked;
//   3. the sun's edge (3-assembled-output/sunref-edge.json: SUN's JSR DORND as LDA #0 :
//      NOP alone, with the harness advancing RAND there as the DORND would):
//      SNG47 against SNG47 with it, game state identical over the gate's run
//      and the views run, so the edge patch changes nothing but the random
//      numbers it no longer takes (the fringe it leaves is the line heap's).
//      The gate's pilot rarely faces a large sun, so this is shown again with
//      the sun posed ahead and large (mcompare --pose sunahead), where the
//      site runs tens of thousands of times (counted, and required):
//        edge-ahead          SNG47 against SNG47 with the edge site and randAt:
//                            identical;
//        edge-ahead-control  the same without randAt: must differ (where it
//                            first does is printed), so the run does test it;
//   4. the whole patch in the same posed scene: full-ahead, the build against
//      SNG47 with sunref.json (and --deadregs), identical, with the edge site
//      and both of MV40's sites run (counted, and required); and k2-control,
//      the same with MV40's two sites left out of the reference's patch: must
//      differ, so the sites are needed. (The clouds' keepRand has its control
//      in msunslot's full scene, where clouds are drawn.)
//
// node 6-harness/msunref.mjs [--csyms 3-assembled-output/symbols.txt] [--out dir] [--skip passive]
// Prints each proof's result and "SUNREF PASS" or "SUNREF FAIL"; exit status 0 only on PASS.
import { bootMaster, loadSyms, loadRefPatch, applyRefPatch, ROOT } from "./mlib.mjs";
import { parseArgs } from "./args.mjs";
import { spawnSync } from "child_process";
import { mkdirSync } from "fs";

const a = parseArgs({ cand: "value", csyms: "value", out: "value", skip: "value" });
const CSYMS = a.csyms || `${ROOT}3-assembled-output/symbols.txt`;
const CAND = a.cand || (a.csyms ? CSYMS.replace(/symbols\.txt$/, "elite-master-sng47.ssd") : `${ROOT}5-compiled-game-discs/elite-master-sng47.ssd`);
const OUT = a.out || `${ROOT}6-harness/work/sunref`; mkdirSync(OUT, { recursive: true });
const REF = `${ROOT}4-reference-binaries/sng47/elite-master-sng47.ssd`, RSYMS = `${ROOT}4-reference-binaries/sng47/symbols.txt`;
const P = loadRefPatch(CSYMS.replace(/[^/]*$/, "sunref.json")), PP = CSYMS.replace(/[^/]*$/, "sunref-passive.json"),
    PE = CSYMS.replace(/[^/]*$/, "sunref-edge.json");
let ok = true;

// ---- 1. the bytes
{
    const sy = loadSyms(RSYMS);
    const s = await bootMaster(REF);
    const cpu = s._machine.processor;
    let at = false;
    const h = cpu.debugInstruction.add(pc => { if (pc === sy.TT170) at = true; return at; });
    for (let k = 0; k < 4000 && !at; k++) cpu.execute(20000);
    h.remove();
    if (!at) { console.log("bytes: FAIL (never reached TT170)"); process.exit(1); }
    const before = Uint8Array.from(cpu.ramRomOs.subarray(0, 0x8000)), after = Uint8Array.from(before);
    applyRefPatch(after, P);
    const mine = new Set();
    for (const [c, bytes] of P.code) bytes.forEach((_, i) => mine.add(c + i));
    for (const st of P.sites) st.new.forEach((_, i) => mine.add(st.addr + i));
    const changed = [];
    for (let i = 0; i < 0x8000; i++) if (before[i] !== after[i]) changed.push(i);
    const stray = changed.filter(x => !mine.has(x));
    const code = changed.filter(x => x >= P.code[0][0] && x < P.code[0][0] + P.code[0][1].length).length;
    console.log(`bytes: ${changed.length} bytes changed: ${code} of the code, ${changed.length - code} at the sites; outside both: ${stray.length}`);
    for (const st of P.sites) console.log(`  &${st.addr.toString(16).toUpperCase()} ${st.name.padEnd(22)} ${st.orig.map(b => b.toString(16).padStart(2, "0")).join(" ")} -> ${st.new.map(b => b.toString(16).padStart(2, "0")).join(" ")}`);
    // the free area must be free: nothing of the original's there that it reads
    // (the patch's code over bytes the loader left: listed, for the record)
    const lo = 0x0b00, hi = 0x0d00, nz = []; for (let x = lo; x < hi; x++) if (before[x]) nz.push(x);
    console.log(`  &0B00-&0CFF before the patch: ${nz.length} non-zero bytes (the loader's leftovers; the game's code does not read them: see the passive run)`);
    if (stray.length) { console.log(`bytes: FAIL (${stray.slice(0, 8).map(x => "&" + x.toString(16)).join(" ")})`); ok = false; }
    else console.log("bytes: PASS");
}

// ---- 2 and 3. the passive variant, and the sun's edge
const runs = [["passive", PP, ["--iters", "10000"]], ["passive-views", PP, ["--iters", "1500", "--views", "--maxsecs", "400"]],
    ["edge", PE, ["--iters", "10000"]], ["edge-views", PE, ["--iters", "1500", "--views", "--maxsecs", "400"]],
    ["edge-ahead", PE, ["--iters", "1500", "--pose", "sunahead"]], ["edge-ahead-control", PE, ["--iters", "1500", "--pose", "sunahead", "--norandat"]]];
if (a.skip !== "passive") for (const [name, patch, extra] of runs) {
    const r = spawnSync(process.execPath, [`${ROOT}6-harness/mcompare.mjs`, ...extra, "--loose", "--ref", REF, "--rsyms", RSYMS, "--cand", REF, "--csyms", RSYMS,
        "--refpatch", "none", "--candpatch", patch, "--out", `${OUT}/${name}`], { encoding: "utf8", maxBuffer: 1 << 28 });
    report(name, (r.stdout || "") + (r.stderr || ""), r.status);
}

// ---- 4. the whole patch, the sun posed ahead: the build against SNG47 with
// sunref.json, and with MV40's sites left out (the control)
for (const [name, extra] of [["full-ahead", ["--deadregs"]], ["k2-control", ["--nosites", "^MV40"]]]) {
    const r = spawnSync(process.execPath, [`${ROOT}6-harness/mcompare.mjs`, "--iters", "1500", "--pose", "sunahead", "--loose", ...extra,
        "--cand", CAND, "--csyms", CSYMS, "--out", `${OUT}/${name}`], { encoding: "utf8", maxBuffer: 1 << 28 });
    report(name, (r.stdout || "") + (r.stderr || ""), r.status);
}

// a run's result: the proofs must be identical (the passive ones with the parked sun's
// region unchanged), the posed ones with their sites run; a control must differ
function report(name, out, status) {
    const line = l => (out.match(new RegExp(`^${l}.*$`, "m")) || [""])[0];
    const sites = {}; for (const m of out.matchAll(/^(ref|cand): patch sites run: (.*)$/gm)) for (const kv of m[2].split(", ")) { const q = /^(.*) (\d+)$/.exec(kv); if (q) sites[q[1]] = (sites[q[1]] || 0) + +q[2]; }
    const control = /control$/.test(name), diverged = /FIRST DIVERGENCE/.test(out);
    const need = name === "edge-ahead" || name === "edge-ahead-control" ? ["SUN: JSR DORND"] : name === "full-ahead" ? ["SUN: JSR DORND", "MV40: ADC K2", "MV40: SBC K2"] : [];
    const unrun = need.filter(n => !(sites[n] > 0));
    let pass = control ? diverged && !/Error/.test(out) : status === 0 && /^MCOMPARE PASS/m.test(out) && (!name.startsWith("passive") || /unchanged at every iteration/.test(out));
    if (unrun.length) pass = false;
    const sn = need.length ? `; sites run: ${need.map(n => `${n} ${sites[n] || 0}`).join(", ")}` : "";
    console.log(`${name}: ${line("Game state identical") || line("FIRST DIVERGENCE") || line("MCOMPARE")}${sn}${control ? (diverged ? " (a control: it must differ, and does)" : " (a control: it must differ, and does NOT)") : ""}; ${line("region SUNPK").trim()}`);
    if (control && diverged) console.log(out.split("\n").filter(l => /^  \S+ \(&/.test(l)).slice(0, 4).map(l => "  " + l.trim()).join("\n"));
    if (!pass) { console.log(out.split("\n").filter(l => /FIRST DIVERGENCE|^  \S|MCOMPARE|Error/.test(l)).slice(0, 20).join("\n")); ok = false; }
    console.log(`${name}: ${pass ? "PASS" : "FAIL"}`);
}
console.log(ok ? "SUNREF PASS" : "SUNREF FAIL");
process.exit(ok ? 0 : 1);
