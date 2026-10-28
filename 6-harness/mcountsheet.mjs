// The hyperspace countdown's cells, side by side: the original (SNG47), one
// build and another, from replay.mjs --shots 1 directories of the same
// session (each iteration's screenshots, it<n>-ref.png / it<n>-cand.png;
// replay.mjs is the development tree's agentplay replay, which this
// repository does not carry: see 6-harness/README.md). It made
// images/countdown/sheet.png.
// The candidates are taken one iteration later than the original, their
// frame's display latency.
//
// node 6-harness/mcountsheet.mjs SHOTS_A SHOTS_B OUT.png IT,IT,...
//   (the original's screenshots from SHOTS_A; the candidates' from SHOTS_A
//   and SHOTS_B, in that order: original | B | A)
import { sharp } from "./jsbeeb.mjs";
const [A, B, OUT, list] = process.argv.slice(2);
const its = list.split(",").map(Number);
const pad = i => `it${String(i).padStart(6, "0")}`;
const W = 260, H = 40;          // the top left of the space view: the countdown and the view's title
const tiles = [];
let y = 0;
for (const i of its) {
    let x = 0;
    for (const [d, w, o] of [[A, "ref", 0], [B, "cand", 1], [A, "cand", 1]]) {
        const b = await sharp(`${d}/${pad(i + o)}-${w}.png`).extract({ left: 180, top: 66, width: W, height: H }).png().toBuffer();
        tiles.push({ input: b, left: x, top: y });
        x += W + 8;
    }
    y += H + 6;
}
await sharp({ create: { width: 3 * (W + 8), height: y, channels: 3, background: { r: 60, g: 60, b: 60 } } }).composite(tiles).png().toFile(OUT);
