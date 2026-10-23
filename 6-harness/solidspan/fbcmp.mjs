#!/usr/bin/env node
// fbcmp.mjs: compare two frame-hash files (fbhash.mjs's: keys
// "iteration.n", values the hash of both screen buffers) as ordered sequences of
// distinct frames per iteration. jsbeeb skips its instruction hook on the first
// instruction of an execute slice, so either side can miss a frame: a lone frame
// inserted or deleted (its neighbours matching) is a sampling gap; a frame whose
// hash differs from the other side's at the same place is a mismatch.
// node 6-harness/solidspan/fbcmp.mjs ref.json cand.json [--from I] [--to J]
import { readFileSync } from "fs";
const [fa, fb] = process.argv.slice(2).filter(x => !x.startsWith("--"));
const arg = k => { const i = process.argv.indexOf(k); return i > 0 ? +process.argv[i + 1] : undefined; };
const FROM = arg("--from") ?? 0, TO = arg("--to") ?? Infinity;
function seq(f) {
    const m = JSON.parse(readFileSync(f, "utf8")), out = [];
    const keys = Object.keys(m).map(k => [k, ...k.split(".").map(Number)]).filter(([, i]) => i >= FROM && i <= TO).sort((x, y) => x[1] - y[1] || x[2] - y[2]);
    for (const [k, i] of keys) { const h = m[k]; if (!out.length || out.at(-1).h !== h) out.push({ i, h }); }
    return out;
}
const A = seq(fa), B = seq(fb);
// align: greedy with one-frame lookahead on either side
let i = 0, j = 0, gaps = 0, bad = [], matched = 0;
while (i < A.length && j < B.length) {
    if (A[i].h === B[j].h) { matched++; i++; j++; continue; }
    if (i + 1 < A.length && A[i + 1].h === B[j].h) { gaps++; i++; continue; }
    if (j + 1 < B.length && A[i].h === B[j + 1].h) { gaps++; j++; continue; }
    bad.push([A[i].i, B[j].i]); i++; j++;
    if (bad.length > 50) break;
}
console.log(`${A.length} and ${B.length} distinct frames; ${matched} matched, ${gaps} sampling gaps, ${bad.length} mismatched${bad.length ? ": first at iterations " + bad.slice(0, 10).map(([x, y]) => `${x}/${y}`).join(" ") : ""}; ${A.length - i} and ${B.length - j} left over`);
process.exit(bad.length ? 1 : 0);
