// A deterministic pilot for BBC Master Elite (used by harness/mcompare.mjs via
// harness/mlib.mjs).
//
// The pilot decides which keys are down at each keyboard read from the game
// state at that moment, plus its own memory (phase, step counters), which is
// updated only from game state it observes at the start of each main-loop
// iteration (MLOOP) and at key reads. So two runs that have had identical game
// state up to a read get identical keys, whatever their speed. It reads only
// game variables (never screen memory, nor drawing temporaries, apart from R and
// QQ29 inside gnum, which gnum itself sets).
//
// The cycle it flies, forever:
//  * title screens: "N" (no commander load) after 25 polls, SPACE after 25 more
//    (the commander is then patched: see patchCommander);
//  * docked: Status (f8), Sell Cargo (f2, "Y" = sell all of each item), Market
//    Prices (f7), Buy Cargo (f1, 3t of one item, by gnum digits and RETURN),
//    Equip Ship (f3: fuel, then missiles up to 4, then an escape pod), then the
//    Short-range Chart (f5): move the crosshairs with the cursor keys towards a
//    candidate offset, snap with Data on System (f6), and accept the system if
//    it is in fuel range, else try the next offset; then Launch (f0);
//  * in flight, for COMBAT_ITERS iterations: engage the nearest hostile (or
//    asteroid / boulder): set roll and pitch rates to bring it onto the
//    vertical axis and into the sights, fire (A) when it is in them; on every
//    second engagement with a hostile, arm a missile (T) and fire it (M) once
//    locked; E.C.M. (E) when a missile comes close; energy bomb (TAB) against
//    four or more hostiles close by; escape pod (ESCAPE) when the energy is low;
//    meanwhile cruise towards the planet;
//  * then hyperspace (H) to the chosen system (every fourth launch: CTRL+H, a
//    galactic hyperspace, if the drive is fitted);
//  * after the jump: steer round the planet to the station's side (planet + 4
//    and then + 2 nosev), in-system jumps (J) while far enough, until the
//    station spawns; engage hostiles on the way (and, outside the safe zone, any
//    non-police ship) for at most 150 iterations each; fly at the station and
//    engage the docking computer (C) within 12000 units; it docks;
//  * on death, the title screens again.
// Internal key numbers (Advanced User Guide p142)
export const K = {
    Q: 0x10, F4: 0x14, F7: 0x16, LEFT: 0x19, F0: 0x20, E: 0x22, T: 0x23, DOWN: 0x29,
    N1: 0x30, N2: 0x31, N3: 0x11, N4: 0x12, N5: 0x13, UP: 0x39, A: 0x41, X: 0x42, Y: 0x44, J: 0x45,
    RETURN: 0x49, TAB: 0x60, ESC: 0x70, S: 0x51, C: 0x52, H: 0x54, N: 0x55, SPACE: 0x62, M: 0x65, LT: 0x66, GT: 0x67,
    SLASH: 0x68, F1: 0x71, F2: 0x72, F3: 0x73, F5: 0x74, F6: 0x75, F8: 0x76, F9: 0x77, RIGHT: 0x79,
};
const DIGIT = [0x27, K.N1, K.N2, K.N3, K.N4, K.N5, 0x34, 0x24, 0x15, 0x26];

// Ship types (elite-source.asm)
const MSL = 1, COPS = 16, SST = 2, ESC = 3, PLT = 4, OIL = 5, BOULDER = 6, AST = 7, SPL = 8, THG = 29, TGL = 30, DOD = 33;
const NI = 37, NOSH = 12;
const COMBAT_ITERS = 500;

// Hyperspace candidate offsets for the crosshairs (galactic x, y units)
const OFFSETS = [[10, 0], [0, 12], [-10, 0], [0, -12], [8, 8], [-8, -8], [8, -8], [-8, 8], [16, 0], [-16, 0], [0, 24], [0, -24], [4, 4], [-4, 4]];

export function makePilot(opts = {}) {
    const P = {
        phase: "start", step: 0, stepIter: 0, titlePolls: 0,
        chartTry: 0, chartTarget: null, chartWait: 0, chosen: false,
        flightIter: 0, hyperAt: -1, ignore: new Set(), engageType: -1, engageStart: 0, jumps: 0, lastSys: null, engageSlot: -1, engagements: 0,
        missileArmedAt: -1, exploding: [], lastNomsl: 0, lastMissile: -1000, lastIter: -1,
        stats: { launches: 0, dockings: 0, jumps: 0, galactic: 0, systems: new Set(), engagements: 0, kills: 0, missiles: 0, ecm: 0, escapes: 0, bombs: 0, deaths: 0, titles: 0, buys: 0, sells: 0, equips: 0, waits: 0, killTypes: {} },
    };

    const sv = (c, a) => c.rb(a);
    function coord(c, base, off) {
        const lo = c.rb(base + off), hi = c.rb(base + off + 1), sg = c.rb(base + off + 2);
        const m = ((sg & 0x7f) << 16) | (hi << 8) | lo;
        return sg & 0x80 ? -m : m;
    }
    function vec(c, a) {
        const lo = c.rb(a), hi = c.rb(a + 1);
        const m = ((hi & 0x7f) << 8) | lo;
        return hi & 0x80 ? -m : m;
    }
    function ship(c, i) {
        const base = c.sy["K%"] + NI * i;
        return {
            i, type: c.rb(c.sy.FRIN + i), base,
            x: coord(c, base, 0), y: coord(c, base, 3), z: coord(c, base, 6),
            newb: c.rb(base + 36), b31: c.rb(base + 31),
            nose: [vec(c, base + 9), vec(c, base + 11), vec(c, base + 13)],
        };
    }
    const docked = c => sv(c, c.sy.QQ12) !== 0;

    // Steering towards (x, y, z) in our frame. The keys change the roll and
    // pitch rates (JSTX, JSTY: 128 = none; ">" lowers JSTX and turns the view
    // anticlockwise, so a target on the right moves up; "X" lowers JSTY and
    // pulls the nose up, so a target above moves down), so the pilot sets
    // desired rates proportional to the angles and presses a key when the rate
    // is more than a key's step away from it. Roll brings the target onto the
    // vertical axis (above us, or below if it is already within 45 degrees of
    // straight below), pitch brings it to the centre.
    function steer(c, t, tight) {
        const keys = [];
        const ax = Math.abs(t.x), ay = Math.abs(t.y);
        const ahead = t.z > 0;
        const off = Math.atan2(Math.hypot(t.x, t.y), t.z);            // angle off the nose
        const below = t.y < 0 && ay > ax;
        let r = below ? -Math.atan2(t.x, -t.y) : Math.atan2(t.x, t.y); // roll error, ">" reduces r > 0
        r *= Math.min(1, off / 0.12);                                 // no rolling hard at a target near the nose
        const pe = Math.abs(r) < 0.5 || !ahead ? (ahead ? Math.atan2(t.y, t.z) : (below ? -Math.PI / 2 : Math.PI / 2)) : 0;
        const clamp = v => Math.max(-124, Math.min(124, v));
        const wantX = 128 - clamp(r * 160), wantY = 128 - clamp(pe * 360);
        const jx = c.rb(c.sy.JSTX), jy = c.rb(c.sy.JSTY);
        if (jx > wantX + 8) keys.push(K.GT); else if (jx < wantX - 8) keys.push(K.LT);
        if (jy > wantY + 15) keys.push(K.X); else if (jy < wantY - 15) keys.push(K.S);
        const inSights = ahead && (ax < tight && ay < tight || off < 0.15);
        return { keys, inSights, off };
    }

    function speedKeys(c, want) {
        const d = c.rb(c.sy.DELTA);
        if (d < want - 2) return [K.SPACE];
        if (d > want + 2) return [K.SLASH];
        return [];
    }

    function nearestTarget(c, range) {
        let best = null;
        for (let i = 1; i < NOSH; i++) {
            const t = c.rb(c.sy.FRIN + i);
            if (!t || t & 0x80) continue;
            if ([SST, DOD, ESC, PLT, OIL, SPL].includes(t)) continue;
            const s = ship(c, i);
            if (s.b31 & 0xa0) continue;              // exploding or killed
            const hostile = (s.newb & 4) || t === THG || t === TGL;
            // outside the station's safe zone in the approach, any non-police ship
            const fair = P.phase === "approach" && !c.rb(c.sy.SSPR) && t !== COPS && t !== MSL;
            if (!hostile && !fair && t !== AST && t !== BOULDER) continue;
            const d = Math.max(Math.abs(s.x), Math.abs(s.y), Math.abs(s.z));
            if (d > (hostile ? 0x2800 : range) || P.ignore.has(i)) continue;
            const score = d * (2 + Math.atan2(Math.hypot(s.x, s.y), s.z));
            if (!best || score < best.score) best = { ...s, d, hostile, score };
        }
        return best;
    }

    function flightKeys(c) {
        const sy = c.sy, keys = [];
        // opts.views (mcompare --views, the view-change regression): every 50
        // flight iterations look rear, left and right, then front again (f1, f2,
        // f3, f0, two iterations apart), whatever else the pilot is doing
        if (opts.views) {
            const v = { 20: K.F1, 22: K.F2, 24: K.F3, 26: K.F0 }[P.flightIter % 50];
            if (v) { P.stats.views = (P.stats.views || 0) + 1; return [v]; }
        }
        if (c.rb(sy.auto)) return keys;              // docking computer flying
        // E.C.M. against a close missile we did not fire recently
        if (c.rb(sy.ECM) && !c.rb(sy.ECMA) && P.flightIter - P.lastMissile > 60) {
            for (let i = 1; i < NOSH; i++) if (c.rb(sy.FRIN + i) === MSL) {
                const s = ship(c, i);
                if (Math.max(Math.abs(s.x), Math.abs(s.y), Math.abs(s.z)) < 0x800) { keys.push(K.E); P.stats.ecm++; break; }
            }
        }
        // escape pod when the energy banks are nearly empty
        if (c.rb(sy.ESCP) && c.rb(sy.ENERGY) < 64 && (c.rb(sy.FSH) < 32 || c.rb(sy.ASH) < 32)) { P.stats.escapes++; P.phase = "escape"; return [K.ESC]; }
        // energy bomb against a pack of four or more hostiles close by
        if (c.rb(sy.BOMB) === 0x7f) {
            let n = 0;
            for (let i = 1; i < NOSH; i++) {
                const t = c.rb(sy.FRIN + i);
                if (!t || t & 0x80) continue;
                const s = ship(c, i);
                if ((s.newb & 4) && Math.max(Math.abs(s.x), Math.abs(s.y), Math.abs(s.z)) < 0x1000) n++;
            }
            if (n >= 4) { P.stats.bombs++; keys.push(K.TAB); }
        }
        const tgt = P.phase === "combat" ? nearestTarget(c, 0x2000) : P.phase === "approach" ? nearestTarget(c, 0x1800) : null;
        if (tgt) {
            if (tgt.i !== P.engageSlot || tgt.type !== P.engageType) { P.engageSlot = tgt.i; P.engageType = tgt.type; P.engageStart = P.flightIter; P.engagements++; P.stats.engagements++; }
            if (P.flightIter - P.engageStart > (P.phase === "combat" ? 400 : 150)) P.ignore.add(tgt.i);   // give up on this one
            const { keys: k, inSights } = steer(c, tgt, 160);
            keys.push(...k, ...speedKeys(c, tgt.d < 0x1000 ? 4 : 30));
            if (inSights) keys.push(K.A);
            if (opts.debug) opts.debug(`${P.flightIter} slot ${tgt.i} type ${tgt.type} newb ${tgt.newb.toString(16)} xyz ${tgt.x},${tgt.y},${tgt.z} off ${steer(c, tgt, 160).off.toFixed(3)} J ${c.rb(sy.JSTX)},${c.rb(sy.JSTY)} D ${c.rb(sy.DELTA)} keys ${keys.map(k => k.toString(16))}`);
            // missiles: every second engagement with a hostile; T arms the missile and
            // it locks (MSTG = slot, bit 7 clear) when the target is in the sights
            const msar = c.rb(sy.MSAR), mstg = c.rb(sy.MSTG), nomsl = c.rb(sy.NOMSL);
            if (tgt.hostile && nomsl && P.engagements % 2 === 0) {
                if (mstg < 0x80) { keys.push(K.M); P.lastMissile = P.flightIter; }
                else if (!msar && inSights) keys.push(K.T);
            }
            return keys;
        }
        P.engageSlot = -1;
        if (P.phase === "combat") {
            // cruise towards the planet meanwhile
            const pl = ship(c, 0);
            keys.push(...steer(c, pl, 2000).keys, ...speedKeys(c, 20));
            return keys;
        }
        if (P.phase === "hyper") {
            const pl = ship(c, 0);
            keys.push(...steer(c, pl, 2000).keys);
            if (P.hyperAt < 0 && c.rb(sy.QQ22 + 1) === 0) { keys.push(K.H); P.hyperAt = P.flightIter; }
            return keys;
        }
        if (P.phase === "approach") {
            if (c.rb(sy.SSPR)) {
                // fly towards the station, then let the docking computer dock
                const st = ship(c, 1), d = Math.max(Math.abs(st.x), Math.abs(st.y), Math.abs(st.z));
                if (d < 12000 && c.rb(sy.DKCMP)) { keys.push(K.C); return keys; }
                keys.push(...steer(c, st, 0).keys, ...speedKeys(c, d < 12000 ? 8 : 40));
                return keys;
            }
            // The station spawns when the planet is within 65536 and the point
            // planet + 2 * nosev (where the station sits) is within 49152 on each
            // axis: fly to planet + 4 * nosev first (to come round the planet on
            // the station's side), then to planet + 2 * nosev
            const pl = ship(c, 0);
            const wp = k => ({ x: pl.x + k * pl.nose[0], y: pl.y + k * pl.nose[1], z: pl.z + k * pl.nose[2] });
            const w4 = wp(4), w2 = wp(2);
            if (Math.max(Math.abs(w4.x), Math.abs(w4.y), Math.abs(w4.z)) < 40000) P.approachStage = 1;
            const t = P.approachStage ? w2 : w4;
            const { keys: k } = steer(c, t, 0);
            keys.push(...k, ...speedKeys(c, 40));
            const off = Math.atan2(Math.hypot(t.x, t.y), t.z);
            if (off < 0.1 && (c.rb(c.sy["K%"] + 8) & 0x7f) >= 2) keys.push(K.J);
            return keys;
        }
        return keys;
    }

    // Docked: a sequence of screens, one step per main-loop iteration or more
    function dockedKeys(c) {
        const sy = c.sy;
        const st = P.step, it = P.stepIter;
        switch (st) {
            case 0: return it === 2 ? [K.F8] : [];                    // status
            case 1: return it === 2 ? [K.F2] : [];                    // sell cargo
            case 2: return it === 2 ? [K.F7] : [];                    // market prices
            case 3: return it === 2 ? [K.F1] : [];                    // buy cargo
            case 4: return it === 2 ? [K.F3] : [];                    // equip
            case 5: {                                                 // chart: choose the next system
                if (it === 2) return [K.F5];
                if (it < 3) return [];
                if (P.chosen) return [];
                if (!P.chartTarget) {
                    const [dx, dy] = OFFSETS[P.chartTry % OFFSETS.length];
                    P.chartTarget = [(c.rb(sy.QQ0) + dx) & 255, (c.rb(sy.QQ1) + dy) & 255];
                    P.chartWait = 0;
                }
                const qx = c.rb(sy.QQ9), qy = c.rb(sy.QQ10), [tx, ty] = P.chartTarget;
                if (P.chartWait === 1) {
                    // after f6: accept if a different system in fuel range
                    P.chartWait = 0;
                    const d = c.rb(sy.QQ8) | (c.rb(sy.QQ8 + 1) << 8);
                    if (d > 0 && d <= c.rb(sy.QQ14)) { P.chosen = true; return [K.F5]; }
                    P.chartTry++; P.chartTarget = null;
                    if (P.chartTry > 40) { P.chosen = true; return []; }
                    return [K.F5];
                }
                if (qx !== tx && Math.abs(qx - tx) < 128) return [qx < tx ? K.RIGHT : K.LEFT];
                if (qy !== ty && Math.abs(qy - ty) < 128) return [qy > ty ? K.UP : K.DOWN];
                P.chartWait = 1;
                return [K.F6];
            }
            default: return it === 3 ? [K.F0] : [];                    // launch
        }
    }
    const STEP_LEN = [6, 6, 5, 6, 6, Infinity, 99];

    // Key waits (TT217 / t / PAUSE2 / YESNO / title loops)
    function waitKeys(c) {
        const sy = c.sy, site = c.site;
        P.stats.waits++;
        if (site === "TLL2" || site === "TL1") {                     // title screens
            if (P.phase !== "title") { if (P.phase !== "start") P.stats.deaths++; P.phase = "title"; P.stats.titles++; P.titlePolls = 0; }
            P.titlePolls++;
            const n = P.titlePolls;
            if (n === 25) return [K.N];
            if (n === 50) { P.titlePolls = 0; return [K.SPACE]; }
            return [];
        }
        if (site === "t" || site === "PAUSE2" && c.callSite === (sy.PAUSE2_C ?? sy.PAUSE2)) return []; // first loop: keys released (PAUSE2_C: PAUSE2 in the cold area)
        const qq11 = c.rb(sy.QQ11);
        if (c.waitFor === "TT223" || c.waitFor === "gnum") {
            const r = c.rb(sy.R);
            const item = c.rb(sy.QQ29);
            if (qq11 === 4) { if (r === 0) { P.stats.sells++; return [K.Y]; } return [K.RETURN]; }   // sell all
            if (qq11 === 2) {                                         // buy a few of one item
                const want = item === (P.stats.dockings % 3) ? 3 : 0;
                if (!want) return [K.N];
                if (r === 0) { P.stats.buys++; return [DIGIT[want]]; }
                return [K.RETURN];
            }
            if (qq11 === 32) {                                        // equip: fuel, then missiles
                let want = 0;
                if (c.rb(sy.QQ14) < 70) want = 1;
                else if (c.rb(sy.NOMSL) < 4) want = 2;
                else if (!c.rb(sy.ESCP) && P.equipTry !== P.stats.dockings) { want = 8; P.equipTry = P.stats.dockings; }
                if (!want) return [K.N];
                if (r === 0) { P.stats.equips++; return [DIGIT[want]]; }
                return [K.RETURN];
            }
            return [K.N];
        }
        if (c.waitFor === "YESNO") return [K.N];
        return [K.SPACE];
    }

    return {
        P,
        keys(c) {
            if (c.site === "DOKEY") return docked(c) ? dockedKeys(c) : flightKeys(c);
            if (c.site === "FREEZE") return [];
            return waitKeys(c);
        },
        dks(c) {
            // CTRL in hyp: galactic hyperspace on every fourth jump if fitted
            if (c.key === 1 && c.site === "hyp" || c.key === 1 && c.site === "TTX111") return P.galactic;
            return false;
        },
        observe(c) {
            const sy = c.sy;
            const isDocked = docked(c);
            const sys = `${c.rb(sy.GCNT)}:${c.rb(sy.QQ0)},${c.rb(sy.QQ1)}`;
            // missiles fired: NOMSL going down in flight
            const nomsl = c.rb(sy.NOMSL);
            if (!isDocked && P.phase !== "title" && nomsl < P.lastNomsl) P.stats.missiles += P.lastNomsl - nomsl;
            P.lastNomsl = nomsl;
            // ships destroyed: byte #31 bit 5 (exploding) newly set in a slot
            for (let i = 1; i < NOSH; i++) {
                const t = c.rb(sy.FRIN + i), ex = t && (c.rb(sy["K%"] + NI * i + 31) & 0x20) ? t : 0;
                if (ex && P.exploding[i] !== ex) { P.stats.kills++; P.stats.killTypes[ex] = (P.stats.killTypes[ex] || 0) + 1; }
                P.exploding[i] = ex;
            }
            if (P.lastSys !== sys) {
                if (P.lastSys !== null && P.phase !== "docked" && P.phase !== "title") { P.stats.jumps++; if (P.galactic) P.stats.galactic++; P.phase = "approach"; P.approachStage = 0; P.galactic = false; }
                P.stats.systems.add(sys); P.lastSys = sys;
            }
            if (isDocked) {
                if (P.phase !== "docked") {
                    if (P.phase !== "title" && P.phase !== "escape") P.stats.dockings++;
                    P.phase = "docked"; P.step = 0; P.stepIter = 0; P.chosen = false; P.chartTarget = null;
                } else {
                    P.stepIter++;
                    if (P.step === 5 ? P.chosen : P.stepIter >= STEP_LEN[P.step]) { P.step++; P.stepIter = 0; P.chartWait = 0; }
                }
            } else {
                if (P.phase === "docked" || P.phase === "title") {
                    P.phase = "combat"; P.flightIter = 0; P.stats.launches++; P.ignore.clear(); P.hyperAt = -1; P.engagements = 0;
                    P.jumps++; P.galactic = P.jumps % 4 === 0 && c.rb(sy.GHYP) !== 0;
                }
                P.flightIter++;
                if (P.phase === "combat" && P.flightIter > COMBAT_ITERS) P.phase = "hyper";
                if (P.phase === "hyper" && P.hyperAt >= 0 && P.flightIter - P.hyperAt > 400) { P.phase = "approach"; P.approachStage = 0; }   // jump failed
            }
        },
    };
}

// The commander patch applied identically in both runs at BAY (after the title
// screens' DFAULT): front beam laser, cash, docking computer, galactic
// hyperdrive, 4 missiles, E.C.M., energy unit, escape pod, energy bomb, full fuel.
export function patchCommander({ wr, sy }) {
    wr(sy.LASER, [143]);                     // front beam laser (POW + 128)
    wr(sy.CASH, [0x00, 0x01, 0x86, 0xa0]);   // 10000.0 Cr (cash is big-endian, tenths)
    wr(sy.DKCMP, [0xff]);
    wr(sy.GHYP, [0xff]);
    wr(sy.NOMSL, [4]);
    wr(sy.ECM, [0xff]);
    wr(sy.ENGY, [1]);
    wr(sy.ESCP, [0xff]);
    wr(sy.BOMB, [0x7f]);
    wr(sy.QQ14, [70]);
}
