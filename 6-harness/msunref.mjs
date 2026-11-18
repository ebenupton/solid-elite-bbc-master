// The proofs that the reference's patch (2-build-files/sunref/sunref.py:
// 3-assembled-output/sunref.json, the sun's parking assembled for the released SNG47)
// changes the original only as it should (docs/renderer.md, "The sun's
// parking"):
//
//   1. the bytes: SNG47 booted to TT170, its main RAM (&0000-&7FFF) before and
//      after the patch is written; every byte that differs must be in the
//      patch's code (&0B80-, SNG47's unused &0B00-&0CFF) or at one of its
//      sites, and each site's bytes before must be the patch's orig
//      (applyRefPatch checks them, and finds the unlabelled ones);
//   2. the passive variant (3-assembled-output/sunref-passive.json: part 14 and TT110 call
//      the original's WPLS and NWSPS, so the sun is never parked): SNG47
//      against SNG47 with it, mcompare.mjs --loose over the gate's 10000
//      iterations and over the views run (1500, --views), game state
//      identical, and the parked sun's region unchanged throughout. So
//      SUNSC, SUNBK's test, the moved station heap and the anchors change
//      nothing unless a sun is parked.
//
// node 6-harness/msunref.mjs [--csyms 3-assembled-output/symbols.txt] [--out dir] [--skip passive]
// Prints each proof's result and "SUNREF PASS" or "SUNREF FAIL"; exit status 0 only on PASS.
import { bootMaster, loadSyms, loadRefPatch, applyRefPatch, ROOT } from "./mlib.mjs";
import { parseArgs } from "./args.mjs";
import { spawnSync } from "child_process";
import { mkdirSync } from "fs";

const a = parseArgs({ csyms: "value", out: "value", skip: "value" });
const CSYMS = a.csyms || `${ROOT}3-assembled-output/symbols.txt`;
const OUT = a.out || `${ROOT}6-harness/work/sunref`; mkdirSync(OUT, { recursive: true });
const REF = `${ROOT}4-reference-binaries/sng47/elite-master-sng47.ssd`, RSYMS = `${ROOT}4-reference-binaries/sng47/symbols.txt`;
const P = loadRefPatch(CSYMS.replace(/[^/]*$/, "sunref.json")), PP = CSYMS.replace(/[^/]*$/, "sunref-passive.json");
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

// ---- 2. the passive variant
if (a.skip !== "passive") for (const [name, extra] of [["passive", ["--iters", "10000"]], ["passive-views", ["--iters", "1500", "--views", "--maxsecs", "400"]]]) {
    const r = spawnSync(process.execPath, [`${ROOT}6-harness/mcompare.mjs`, ...extra, "--loose", "--ref", REF, "--rsyms", RSYMS, "--cand", REF, "--csyms", RSYMS,
        "--refpatch", "none", "--candpatch", PP, "--out", `${OUT}/${name}`], { encoding: "utf8", maxBuffer: 1 << 28 });
    const out = (r.stdout || "") + (r.stderr || "");
    const pass = r.status === 0 && /^MCOMPARE PASS/m.test(out) && /unchanged at every iteration/.test(out);
    const line = l => (out.match(new RegExp(`^${l}.*$`, "m")) || [""])[0];
    console.log(`${name}: ${line("Game state identical") || line("FIRST DIVERGENCE") || line("MCOMPARE")}; ${line("region SUNPK").trim()}`);
    if (!pass) { console.log(out.split("\n").filter(l => /FIRST DIVERGENCE|^  \S|MCOMPARE|Error/.test(l)).slice(0, 20).join("\n")); ok = false; }
    console.log(`${name}: ${pass ? "PASS" : "FAIL"}`);
}
console.log(ok ? "SUNREF PASS" : "SUNREF FAIL");
process.exit(ok ? 0 : 1);
