// Regression test: ships posed in flight at the orientations the ship audit
// flagged (2026-10-26: the Missile's poses o1-o4, the Splinter's o0, o5-o9 and
// close; 2026-10-27: the Cargo canister's o9 and close, the Boulder's o1, the
// Cobra Mk III's o8, the Cougar's o0 and o4), drawn by the renderer and
// checked.
//
// node 6-harness/mshippose.mjs [--disc d] [--syms s] [--out dir] [--only 1,8]
//
// Boots the build as mstation.mjs does (SHIFT+BREAK, a new commander,
// launch with f0). From then on, at every MLOOP, the scene is put back: the
// planet behind us (K% slot 0), the station far behind us (slot 1), and the
// posed ship in slot 2 at (x, y, z) with the pose's nosev and roofv, no speed,
// no rotation, no AI; our speed 0. Every pose is flown in both of the
// game's handednesses: "Z", sidev = nosev x roofv, as ZINF spawns a ship, and
// "T", sidev = roofv x nosev, as TIDY leaves it (a ship's first TIDY, within
// 16 iterations of its spawn, mirrors it). The pose is held until the ship
// has been drawn three iterations running with that matrix (TIDY, run on it
// every 16th iteration, changes it for one), then the screen is taken
// (<out>/sNN_<pose><Z|T>.png) and checked:
//   * outside: no blob of lit pixels outside the convex hull of the ship's
//     projected vertices (grown by 4 pixels; the laser sights are left out)
//     bigger than a speck of stardust (or two side by side: over 6 pixels or
//     5 across). LL9's XX3 is poisoned as LL9 starts on
//     the posed ship (vertex i on an ellipse round the view's centre), so a
//     vertex that is used but not projected draws far outside: the Missile's
//     fins once did (in flight, XX3 holds whatever the ship drawn before left);
//   * cover: inside the hull of the solid body's vertices (shrunk by 4 pixels,
//     or 1.5 when LL9 projected them all and the hull is made from its XX3)
//     every 2x2 cell of pixels has a lit pixel (the Splinter's faces were
//     culled by wrong normals: holes in the body);
//   * faces: the faces f_ship filled (fsh_draw) in the ship's last frame are
//     its front faces, worked out from the pose (a face more than 5 degrees
//     from edge-on to the line of sight must be drawn if it faces us and not
//     drawn if it faces away). A pose's "lax" faces are exempt, and so is
//     their area from the cover test: faces LL9 hides although they face us,
//     as the released game does (the Boulder's face 4: its blueprint normal,
//     (-5, -4, -1), is too short for LL9's test, which uses the normal's tip);
//   * wings: each of the pose's "wings" (the Cougar's: zero-thickness, on the
//     body's edge, seen face on) is covered as the body is (2x2 cells inside
//     it, shrunk by 1.5 pixels, lit);
//   * empty: no lit pixel 1.5 pixels inside each of the pose's "empty"
//     triangles (the Cougar's notches between its nose and a wing's leading
//     edge, once filled as part of a face polygon taken round the wing).
// The projection used for the hulls is LL9's arithmetic (within 3 pixels of
// it); the largest difference from the vertices LL9 projected is printed.
// Prints a line per pose and "SHIPPOSE PASS" or "SHIPPOSE FAIL"; exit status 0
// only on PASS.
import { MachineSession, BBC, sharp } from "./jsbeeb.mjs";
import { loadSyms, CAND_DISC, CAND_SYMS, WORK, mapOfLabel, physRead } from "./mlib.mjs";
import { mkdirSync } from "fs";
import { parseArgs } from "./args.mjs";
const a = parseArgs({ disc: "value", syms: "value", out: "value", only: "value" });
const sy = loadSyms(a.syms || CAND_SYMS);
const OUT = a.out || `${WORK}shippose`; mkdirSync(OUT, { recursive: true });

// The ships: vertices and face polygons (gfx-faces.asm) from the blueprints;
// solid = the vertices of the convex body that must be covered
const SHIPS = {
    1: { name: "Missile", solid: [0, 1, 2, 3, 4, 5, 6, 7, 8],
         f: [[3, 0, 4], [1, 4, 0], [2, 1, 0], [2, 0, 3], [2, 5, 6, 1], [1, 6, 7, 4], [8, 3, 4, 7], [5, 2, 3, 8], [6, 5, 8, 7]],
         v: [[0, 0, 68], [8, -8, 36], [8, 8, 36], [-8, 8, 36], [-8, -8, 36], [8, 8, -44], [8, -8, -44], [-8, -8, -44], [-8, 8, -44],
             [12, 12, -44], [12, -12, -44], [-12, -12, -44], [-12, 12, -44], [-8, 8, -12], [-8, -8, -12], [8, 8, -12], [8, -8, -12]] },
    8: { name: "Splinter", solid: [0, 1, 2, 3], f: [[3, 1, 2], [2, 0, 3], [3, 0, 1], [2, 1, 0]],
         v: [[-24, -25, 16], [0, 12, -10], [11, -6, 2], [12, 42, 7]] },
    5: { name: "Cargo", solid: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
         f: [[0, 4, 3, 2, 1], [0, 1, 6, 5], [1, 2, 7, 6], [2, 3, 8, 7], [3, 4, 9, 8], [4, 0, 5, 9], [5, 6, 7, 8, 9]],
         v: [[24, 16, 0], [24, 5, 15], [24, -13, 9], [24, -13, -9], [24, 5, -15], [-24, 16, 0], [-24, 5, 15], [-24, -13, 9],
             [-24, -13, -9], [-24, 5, -15]] },
    6: { name: "Boulder", solid: [0, 1, 2, 3, 4, 5, 6],
         f: [[5, 4, 0], [1, 5, 0], [2, 5, 1], [2, 3, 5], [3, 4, 5], [1, 0, 6], [6, 2, 1], [6, 3, 2], [6, 4, 3], [0, 4, 6]],
         v: [[-18, 37, -11], [30, 7, 12], [28, -7, -12], [2, 0, -39], [-28, 34, -30], [5, -10, 13], [20, 17, -30]] },
    11: { name: "Cobra Mk3", solid: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
         f: [[0, 1, 2], [2, 1, 5], [0, 2, 6], [1, 3, 5], [4, 0, 6], [9, 2, 5], [6, 2, 9], [5, 3, 8], [7, 4, 6],
             [11, 7, 6, 9, 5, 8, 10], [10, 8, 3, 1], [0, 11, 10, 1], [4, 7, 11, 0]],
         v: [[32, 0, 76], [-32, 0, 76], [0, 26, 24], [-120, -3, -8], [120, -3, -8], [-88, 16, -40], [88, 16, -40],
             [128, -8, -40], [-128, -8, -40], [0, 26, -40], [-32, -24, -40], [32, -24, -40], [-36, 8, -40], [-8, 12, -40],
             [8, 12, -40], [36, 8, -40], [36, -12, -40], [8, -16, -40], [-8, -16, -40], [-36, -12, -40], [0, 0, 76],
             [0, 0, 90], [-80, -6, -40], [-80, 6, -40], [-88, 0, -40], [80, 6, -40], [88, 0, -40], [80, -6, -40]] },
    32: { name: "Cougar", solid: [0, 1, 2, 3, 4, 5, 6],
         f: [[0, 1, 2, 3], [4, 2, 1], [5, 4, 1, 0], [6, 4, 5], [6, 5, 0, 3], [6, 3, 2, 4]],
         v: [[0, 5, 67], [-20, 0, 40], [-40, 0, -40], [0, 14, -40], [0, -14, -40], [20, 0, 40], [40, 0, -40], [-36, 0, 56],
             [-60, 0, -20], [36, 0, 56], [60, 0, -20], [0, 7, 35], [0, 8, 25], [-12, 2, 45], [12, 2, 45], [-10, 6, -40],
             [-10, -6, -40], [10, -6, -40], [10, 6, -40]] },
};
// The audit's poses (nosev n, roofv r)
const O6 = { n: [-0.5997301821134201, 0.34984260623282837, -0.7196762185361041], r: [0.22396377884822027, 0.9368084920965556, 0.2687565346178643] };
const POSES = {
    o0: { name: "front", n: [0, 0, -1], r: [0, 1, 0] },
    o1: { name: "rear", n: [0, 0, 1], r: [0, 1, 0] },
    o2: { name: "left", n: [-1, 0, 0], r: [0, 1, 0] },
    o3: { name: "right", n: [1, 0, 0], r: [0, 1, 0] },
    o4: { name: "top", n: [0, 1, 0], r: [0, 0, -1] },
    o5: { name: "bottom", n: [0, 1, 0], r: [0, 0, 1] },
    o6: { name: "front-left-low", ...O6 },
    o7: { name: "front-right-high", n: [0.5997301821134201, -0.34984260623282837, -0.7196762185361041], r: [0.22396377884822027, 0.9368084920965556, -0.2687565346178643] },
    o8: { name: "rear-left-low", n: [-0.5997301821134201, -0.34984260623282837, 0.7196762185361041], r: [-0.22396377884822027, 0.9368084920965556, 0.2687565346178643] },
    o9: { name: "rear-right-high +25deg roll", n: [0.5997301821134201, 0.34984260623282837, 0.7196762185361041], r: [-0.527644458599955, 0.8490368313491703, 0.026977478038560345] },
    close: { name: "close-up front-left-low", ...O6 },
};
// [type, pose, z, x, y, checks], at the z the audit's capture drew them at.
// The Missile's side and top views are off centre (as the title screen's ship
// is a little), so that the side faces seen edge-on are hidden, as there
const CASES = [
    [1, "o1", 155], [1, "o2", 236, 0, 16], [1, "o3", 236, 0, -16], [1, "o4", 480, 24, 0],
    [8, "o0", 308], [8, "o5", 153], [8, "o6", 297], [8, "o7", 274], [8, "o8", 247], [8, "o9", 212], [8, "close", 186],
    [5, "o9", 189], [5, "close", 80], [6, "o1", 288, 0, 0, { lax: [4] }], [11, "o8", 434],
    [32, "o0", 215], [32, "o4", 481, 0, 0, { wings: [[1, 7, 8, 2], [5, 9, 10, 6]], empty: [[0, 1, 7], [0, 5, 9]] }],
].filter(([t]) => !a.only || a.only.split(",").map(Number).includes(t)).flatMap(c => [[...c.slice(0, 2), "Z", ...c.slice(2)], [...c.slice(0, 2), "T", ...c.slice(2)]]);

const cross = (p, q) => [p[1] * q[2] - p[2] * q[1], p[2] * q[0] - p[0] * q[2], p[0] * q[1] - p[1] * q[0]];
const dot = (p, q) => p[0] * q[0] + p[1] * q[1] + p[2] * q[2];
const sub = (p, q) => [p[0] - q[0], p[1] - q[1], p[2] - q[2]];
const enc = v => { const m = Math.min(0x7fff, Math.round(Math.abs(v) * 0x6000)); return [m & 255, (m >> 8) | (v < 0 ? 0x80 : 0)]; };
const sidev = (p, h) => h === "Z" ? cross(p.n, p.r) : cross(p.r, p.n);
// a vertex in view space: v_x sidev + v_y roofv + v_z nosev, as LL9 does it
// (part 3 scales each vector byte to R = 256 * (2 * |hi| + lo bit 7) / 197,
// part 6 sums |v| * R / 256 per term, rounded down), then part 7's projection
// (X = 128 +/- 256 |x| / z, Y = 96 -/+ 256 |y| / z, rounded down)
function project(c) {
    const sc = v => { const [lo, hi] = enc(v); return Math.sign(v) * Math.floor(256 * (2 * (hi & 0x7f) + (lo >> 7)) / 197); };
    const n = c.p.n.map(sc), r = c.p.r.map(sc), sd = sidev(c.p, c.h).map(sc);
    const term = (u, m) => Math.sign(u) * Math.sign(m) * Math.floor(Math.abs(u) * Math.abs(m) / 256);
    return SHIPS[c.t].v.map(v => {
        const P = [0, 1, 2].map(i => term(v[0], sd[i]) + term(v[1], r[i]) + term(v[2], n[i]));
        const X = c.x + P[0], Y = c.y + P[1], Z = Math.max(4, c.z + P[2]);
        return [128 + Math.sign(X) * Math.floor(256 * Math.abs(X) / Z), 96 - Math.sign(Y) * Math.floor(256 * Math.abs(Y) / Z)];
    });
}
// the faces that face us (exactly), and those that face away, each more than
// 5 degrees from edge-on to the line of sight to the face's centre
function frontFaces(c) {
    const sd = sidev(c.p, c.h), sh = SHIPS[c.t];
    const V = sh.v.map(v => [0, 1, 2].map(i => v[0] * sd[i] + v[1] * c.p.r[i] + v[2] * c.p.n[i] + [c.x, c.y, c.z][i]));
    const m = [0, 1, 2].map(i => sh.solid.reduce((s, k) => s + V[k][i], 0) / sh.solid.length);
    const front = new Set(), back = new Set();
    sh.f.forEach((poly, f) => {
        let nv = cross(sub(V[poly[1]], V[poly[0]]), sub(V[poly[2]], V[poly[0]]));
        const ctr = [0, 1, 2].map(i => poly.reduce((s, k) => s + V[k][i], 0) / poly.length);
        if (dot(nv, sub(ctr, m)) < 0) nv = nv.map(u => -u);        // outward
        const cs = dot(nv, ctr) / Math.sqrt(dot(nv, nv) * dot(ctr, ctr));
        if (cs < -0.087) front.add(f); else if (cs > 0.087) back.add(f);
    });
    return { front, back };
}
function hull(pts) {
    const p = [...pts].sort((u, w) => u[0] - w[0] || u[1] - w[1]);
    const cr = (o, u, w) => (u[0] - o[0]) * (w[1] - o[1]) - (u[1] - o[1]) * (w[0] - o[0]);
    const lo = [], hi = [];
    for (const q of p) { while (lo.length >= 2 && cr(lo[lo.length - 2], lo[lo.length - 1], q) <= 0) lo.pop(); lo.push(q); }
    for (const q of p.reverse()) { while (hi.length >= 2 && cr(hi[hi.length - 2], hi[hi.length - 1], q) <= 0) hi.pop(); hi.push(q); }
    return lo.slice(0, -1).concat(hi.slice(0, -1));       // anticlockwise in (x, y)
}
// signed distance of (x, y) inside the hull (positive inside)
function inside(h, x, y) {
    let d = Infinity;
    for (let i = 0; i < h.length; i++) {
        const [x0, y0] = h[i], [x1, y1] = h[(i + 1) % h.length];
        const L = Math.hypot(x1 - x0, y1 - y0) || 1;
        d = Math.min(d, ((x1 - x0) * (y - y0) - (y1 - y0) * (x - x0)) / L);
    }
    return d;
}

const s = new MachineSession("Master"); await s.initialise(); await s.boot(30);
s.loadDisc(a.disc || CAND_DISC); s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
const cpu = s._machine.processor; const secs = n => s.runFor(2000000 * n);
const key = async (k, hold = 0.2, after = 1) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
const at = (pc, name) => { if (pc !== sy[name]) return false; const b = sy.__bank[name]; return b === undefined || (cpu.romsel & 15) === (b & 15); };
const M6 = mapOfLabel(sy, "F_STYP"), rd6 = name => physRead(cpu, M6, sy[name]);
await secs(28); await key("N"); await secs(3); await key("SPACE"); await secs(4);
await key("F0", 0.2, 12);

const ram = cpu.ramRomOs;
let atLoop = false, iters = 0, cur = null, xx3 = null, run = 0, faces = null, drawn = null;
function pose() {
    const K = sy["K%"], { t, p, h, z, x, y } = cur, sd = sidev(p, h);
    ram.fill(0, K, K + 3 * 37);
    ram[K + 7] = 0x80; ram[K + 8] = 0x80;                           // the planet: z = -&8000
    ram[K + 37 + 7] = 0x60; ram[K + 37 + 8] = 0x80;                 // the station: z = -&6000
    ram[K + 37 + 9 + 4] = 0x60; ram[K + 37 + 15 + 2] = 0x60; ram[K + 37 + 21] = 0x60;
    const S = K + 74;
    ram[S + 6] = z & 255; ram[S + 7] = z >> 8;
    ram[S + 0] = Math.abs(x); ram[S + 2] = x < 0 ? 0x80 : 0;
    ram[S + 3] = Math.abs(y); ram[S + 5] = y < 0 ? 0x80 : 0;
    [...p.n, ...p.r, ...sd].forEach((v, i) => { const [lo, hi] = enc(v); ram[S + 9 + 2 * i] = lo; ram[S + 10 + 2 * i] = hi; });
    [0x80, 2, t, 0].forEach((b, i) => { ram[sy.FRIN + i] = b; });
    ram[sy.DELTA] = 0; ram[sy.QQ11] = 0; ram[sy.VIEW] = 0; ram[sy.LASER] = 0;
}
cpu.debugInstruction.add(pc => {
    if (at(pc, "MLOOP")) { atLoop = true; iters++; if (cur) pose(); }
    if (!cur) return false;
    // LL9 for the posed ship: XX3 poisoned, vertex i on an ellipse round the
    // view's centre at i golden angles (any three make a triangle)
    if (at(pc, "LL9") && ram[sy.TYPE] === cur.t) SHIPS[cur.t].v.forEach((_, i) => {
        const g = i * 2.39996;
        ram.set([Math.round(128 + 100 * Math.cos(g)), 0, Math.round(96 + 75 * Math.sin(g)), 0], sy.XX3 + 4 * i);
    });
    // LL9 records the posed ship: the vertices it projected (XX3), and whether
    // it was drawn with the pose's matrix (sidev's high bytes)
    if (at(pc, "H_EE31") && ram[sy.TYPE] === cur.t) {
        xx3 = Array.from(ram.subarray(sy.XX3, sy.XX3 + 4 * SHIPS[cur.t].v.length));
        const sd = sidev(cur.p, cur.h).map(u => enc(u)[1]);
        run = [0, 1, 2].every(i => Math.abs((ram[sy.INWK + 22 + 2 * i] & 0x7f) - (sd[i] & 0x7f)) <= 2 &&
            ((ram[sy.INWK + 22 + 2 * i] ^ sd[i]) & 0x80) === 0 || (sd[i] & 0x7f) < 3) ? run + 1 : 0;
    }
    // the frame layer draws the posed ship: the faces it fills
    if (at(pc, "f_ship") && physRead(cpu, M6, sy.F_STYP + cpu.a) === cur.t) faces = new Set();
    if (at(pc, "fsh_draw") && faces && physRead(cpu, M6, sy.F_STYP + rd6("f_si")) === cur.t) faces.add(rd6("f_f"));
    if (at(pc, "fsh_done") && faces && physRead(cpu, M6, sy.F_STYP + rd6("f_si")) === cur.t) { drawn = faces; faces = null; }
    return false;
});
for (let k = 0; k < 200 && !atLoop; k++) await s.runFor(20000);
if (!atLoop) { console.log("SHIPPOSE FAIL: never reached MLOOP"); process.exit(1); }

const v = s._video, FW = 1024;
// the space view's top left (Elite's (0, 0), the border) in the active area:
// an Elite pixel is two frame pixels wide and two lines high
const VX = 184, VY = 68;
// the hull's margin: this projection is within 3 pixels of LL9's (the ship's
// position goes through LL9's sign-magnitude sums and the frame's clipping)
const GROW = 4;
// the laser sights (lines through the view's centre, drawn in every frame)
const sight = (x, y) => (y >= 95 && y <= 97 && Math.abs(x - 128) < 26) || (x >= 127 && x <= 129 && Math.abs(y - 96) < 26);
const XY = (b, i) => [(b[4 * i] | b[4 * i + 1] << 8) << 16 >> 16, (b[4 * i + 2] | b[4 * i + 3] << 8) << 16 >> 16];
let bad = 0;
const fj = l => l.sort((p, q) => p - q).join(l.some(f => f > 9) ? "," : "");
for (const [t, pid, h, z, x = 0, y = 0, chk = {}] of CASES) {
    cur = { t, p: POSES[pid], h, z, x, y }; xx3 = null; run = 0; drawn = null;
    const i0 = iters;
    for (let k = 0; k < 4000 && (iters < i0 + 6 || run < 3); k++) await s.runFor(20000);
    await s.runFor(100000);
    const fb = s._completeFb8, L = v.leftBorder, T = v.topBorder, W = FW - L - v.rightBorder, H = 625 - T - v.bottomBorder;
    const tag = `s${String(t).padStart(2, "0")}_${pid}${h}`;
    await sharp(Buffer.from(fb.buffer), { raw: { width: FW, height: 625, channels: 4 } })
        .extract({ left: L, top: T, width: W, height: H }).png().toFile(`${OUT}/${tag}.png`);
    const lit = (x, y) => {
        const o = 4 * ((T + VY + 2 * y) * FW + L + VX + 2 * x);
        return fb[o] + fb[o + 1] + fb[o + 2] > 60;
    };
    // our projection, and where LL9 projected a vertex (its XX3 entry within
    // GROW of ours) LL9's; the body's hull is shrunk by GROW unless all of its
    // vertices are LL9's, then by 1.5
    const P = project(cur);
    let perr = 0, exact = !!xx3;
    const Q = P.map(([px, py], i) => {
        if (!xx3) return [px, py];
        const [X, Y] = XY(xx3, i), e = Math.hypot(X - px, Y - py);
        if (e <= GROW) { perr = Math.max(perr, e); return [X, Y]; }
        if (SHIPS[t].solid.includes(i)) exact = false;
        return [px, py];
    });
    const hAll = hull(Q), hSolid = hull(SHIPS[t].solid.map(i => Q[i])), SHRINK = exact ? 1.5 : GROW;
    // outside: blobs of lit pixels outside the grown hull (below the view's
    // title, inside its border)
    const seen = new Set(); let worst = 0, wpos = null;
    const out = (px, py) => lit(px, py) && inside(hAll, px + 0.5, py + 0.5) <= -GROW && !sight(px, py);
    for (let py = 18; py < 190; py++) for (let px = 2; px < 254; px++) {
        if (seen.has(py * 256 + px) || !out(px, py)) continue;
        const st = [[px, py]]; seen.add(py * 256 + px); let n = 0, x0 = px, x1 = px, y0 = py, y1 = py;
        while (st.length) {
            const [cx, cy] = st.pop(); n++;
            x0 = Math.min(x0, cx); x1 = Math.max(x1, cx); y0 = Math.min(y0, cy); y1 = Math.max(y1, cy);
            for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]) {
                const nx = cx + dx, ny = cy + dy;
                if (nx < 2 || nx > 253 || ny < 18 || ny > 189 || seen.has(ny * 256 + nx) || !out(nx, ny)) continue;
                seen.add(ny * 256 + nx); st.push([nx, ny]);
            }
        }
        if ((n > 6 || Math.max(x1 - x0, y1 - y0) >= 5) && n > worst) { worst = n; wpos = [x0, y0, x1, y1]; }
    }
    // cover: 2x2 cells inside the shrunk solid hull (but not in a lax face)
    // with no lit pixel, then in each wing
    const lax = (chk.lax || []).map(f => hull(SHIPS[t].f[f].map(i => Q[i])));
    let cells = 0, holes = 0;
    for (const [hh, sk] of [[hSolid, SHRINK], ...(chk.wings || []).map(w => [hull(w.map(i => Q[i])), 1.5])])
        for (let py = 0; py < 190; py += 2) for (let px = 0; px < 256; px += 2) {
            if (inside(hh, px + 1, py + 1) < sk + 0.5 || lax.some(lh => inside(lh, px + 1, py + 1) > -1.5)) continue;
            cells++;
            if (!(lit(px, py) || lit(px + 1, py) || lit(px, py + 1) || lit(px + 1, py + 1))) holes++;
        }
    // empty: lit pixels inside the empty triangles
    let filled = 0;
    for (const e of chk.empty || []) {
        const eh = hull(e.map(i => Q[i]));
        for (let py = 18; py < 190; py++) for (let px = 2; px < 254; px++)
            if (inside(eh, px + 0.5, py + 0.5) > 1.5 && lit(px, py) && !sight(px, py)) filled++;
    }
    // faces: the front faces drawn, no back face (lax faces either way)
    const { front, back } = frontFaces(cur), d = drawn || new Set(), lx = new Set(chk.lax || []);
    const missing = [...front].filter(f => !d.has(f) && !lx.has(f)), extra = [...back].filter(f => d.has(f) && !lx.has(f));
    const ok = worst === 0 && holes === 0 && filled === 0 && drawn && !missing.length && !extra.length;
    if (!ok) bad++;
    console.log(`${SHIPS[t].name.padEnd(9)} ${(pid + h).padEnd(6)} z ${String(z).padStart(4)}: outside ${worst ? `${worst} px at ${wpos}` : "none"}, ` +
        `cover ${cells - holes}/${cells}${chk.empty ? `, empty ${filled ? `${filled} px lit` : "ok"}` : ""}, faces ${drawn ? fj([...d]) || "-" : "?"}` +
        `${missing.length ? ` (front ${fj(missing)} not drawn)` : ""}${extra.length ? ` (back ${fj(extra)} drawn)` : ""}` +
        `, projection ${perr.toFixed(1)}  ${ok ? "ok" : "BAD"}`);
}
console.log(bad ? `SHIPPOSE FAIL (${bad} of ${CASES.length} poses)` : `SHIPPOSE PASS (${CASES.length} poses)`);
process.exit(bad ? 1 : 0);
