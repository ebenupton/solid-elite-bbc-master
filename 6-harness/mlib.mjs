// Deterministic driver for BBC Master Elite on the emulated BBC Master (jsbeeb).
//
// Shared by harness/mcompare.mjs and the pilot (harness/mpilot.mjs).
//
// Input injection
// ---------------
// Master Elite reads the keyboard in three places only (SNG47, keyboard
// configuration; the joystick and Bitstik are never enabled):
//  * FILLKL, called only from RDKEY (and RDKEY-1, its BCD-only variant used by
//    DOKEY), scans the keyboard matrix directly through the System VIA, fills
//    the key logger (KY1-KY20 at &C4-&D3, via the IKNS table) and returns the
//    highest pressed key's internal number in KL and X. RDKEY then translates
//    it to ASCII through TRTB%.
//  * DKS5 (and CTRL, which falls into it) tests one key (SHIFT on the charts,
//    CTRL for the galactic hyperdrive and for a mis-jump on arrival).
//  * MT26 reads a line with OSWORD 0 (commander names: load/save only; the
//    pilot never goes there, and mlib stops with an error if it does).
// The hardware keyboard is never pressed after boot (all scans see no key), and
// keys are injected at fixed routine boundaries, before the code that consumes
// them:
//  * at RDKEY+5 (the PLA after JSR FILLKL returns) the key logger, KL and X are
//    overwritten with exactly what FILLKL would have produced for the pilot's
//    set of pressed keys (same ZEKTRAN clear, same IKNS walk, same KY19 ghost
//    rule);
//  * at DKS5+17 (the LDA #%00001011 after the LDX VIA+&4F that reads the key)
//    X is set to the key number with bit 7 set if the pilot says it is down.
// The pilot is asked at every such read, with the call site (the label of the
// JSR) and, for TT217/t waits, the routine that called the wait. So both runs
// see the same keys at the same main-loop iteration (DOKEY is called once per
// iteration), the same nth poll of a title loop, and the same nth key wait,
// whatever the wall or emulated timing.
//
// Timing-dependent state (found while building the harness: see 6-harness/README.md): the IRQ handler
// (IRQ1/LINSCN) writes only DL (the vsync flag WSCAN polls), JOPOS (ADC; the
// loader disables conversions and the game reads it only with the joystick
// configured), and the sound buffers (SOINT counts each sound down once per
// vsync, and frees its channel, SOPR = 0, when it ends). LASCT is counted down by
// MLOOP, not by the IRQ, in this version. The sound buffers do leak into game
// state, through NOISE: it picks a channel and accepts or drops the new sound
// by comparing its priority with SOPR, so its returned X, A and C flag depend on
// how many vsyncs have passed since the last sounds; and LASNO's NOISE call is
// followed directly by LASLI, whose first JSR DORND takes that C flag into the
// random number seed (DORND's ROL A). A build that runs at a different speed
// then gets different laser line positions and a different RAND (found with a
// build slowed by one WSCAN per iteration: divergence after 7334 iterations).
// So at every NOISE entry the three SOPR bytes are set to 0 (all channels free):
// NOISE then always takes a channel chosen only by the sound number and returns
// A = &80, X = that channel, C = 1 (or returns at once if sound is off), in both
// runs. The sound mix changes (no priority between sounds); game state does
// not otherwise depend on the sound buffers (only the sound routines and the
// IRQ read them), so they are excluded from the comparison.
import { MachineSession } from "./jsbeeb.mjs";
import { readFileSync, existsSync, appendFileSync } from "fs";
import { createHash } from "crypto";

export const ROOT = decodeURIComponent(new URL("..", import.meta.url).pathname);
// The build that the tools look at by default (the Makefile's outputs), the
// released SNG47 disc that it is compared with (with the symbols of the
// original source's build, which is byte for byte the released game), and the
// harness's working directory (logs, screenshots, the reference run's cache)
export const CAND_DISC = `${ROOT}5-compiled-game-discs/elite-master-sng47.ssd`;
export const CAND_SYMS = `${ROOT}3-assembled-output/symbols.txt`;
export const REF_DISC = `${ROOT}4-reference-binaries/sng47/elite-master-sng47.ssd`;
export const REF_SYMS = `${ROOT}4-reference-binaries/sng47/symbols.txt`;
export const WORK = `${ROOT}6-harness/work/`;

export function loadSyms(path) {
    const syms = {};
    for (const m of readFileSync(path, "utf8").matchAll(/'([^']+)':(\d+)L?/g)) if (!(m[1] in syms)) syms[m[1]] = +m[2];
    // Labels in sideways RAM: build/banks.txt next to the symbols, "label bank" per
    // line with the ROMSEL value of the code's bank in hex (4: Elite's home bank,
    // 7: the cold area, 85: the rasteriser's polygon window, ANDY over bank 5).
    // Kept non-enumerable so
    // that code iterating over the symbols sees only addresses.
    const bank = {};
    const bp = path.replace(/symbols\.txt$/, "banks.txt");
    if (bp !== path && existsSync(bp)) for (const l of readFileSync(bp, "utf8").split("\n")) {
        const [n, b] = l.trim().split(/\s+/);
        if (n && b) bank[n] = parseInt(b, 16);
    }
    Object.defineProperty(syms, "__bank", { value: bank, enumerable: false });
    return syms;
}

// What is mapped at addr for a given ROMSEL value: "m" (not sideways: main RAM,
// HAZEL, MOS), "A" (ANDY), or the sideways bank number
export function mapAt(romsel, addr) {
    if (addr < 0x8000 || addr >= 0xc000) return "m";
    if (addr < 0x9000 && romsel & 0x80) return "A";
    return romsel & 15;
}
// The mapping a label lives in ("m" for labels outside sideways RAM)
export function mapOfLabel(sy, name) {
    const a = sy[name], b = sy.__bank[name];
    return b === undefined ? "m" : mapAt(b, a);
}
// The bank of the caller of a stub between the passes (elite-stubs.asm)
// whose code holds address a, or null if a is in no stub: bank 4 for the stubs
// into the cold pass, bank 7 for those out of it
export function stubBank(sy, a) {
    if (sy.STUBS7 !== undefined && a >= sy.STUBS7 && a < sy.STUBS7_END) return 4;
    if (sy.STUBS4 !== undefined && a >= sy.STUBS4 && a < sy.STUBS4_END) return 7;
    return null;
}
// Read a byte of a given mapping regardless of what is paged
export function physRead(cpu, map, addr) {
    if (map === "m") return cpu.ramRomOs[addr & 0xffff];
    if (map === "A") return cpu.ramRomOs[addr];
    return cpu.ramRomOs[cpu.romOffset + map * 16384 + addr - 0x8000];
}

// Game state compared per iteration: [start, length, name]. All of these are at
// fixed addresses in the original; a relocated build supplies its own symbols
// and the regions are located by symbol (see regionsFor).
export function regionsFor(sy) {
    return [
        [0x0000, sy.NOSTM + 1 - 0x0000, "ZP"],                  // zero page game variables (&00-&E3)
        [sy["K%"], 0x0800 - sy["K%"], "K%"],                    // ship data blocks + ship line heap (down from &0800)
        [sy.WP, sy.JOPOS + 3 - sy.WP, "WP"],                    // FRIN, flight variables, sun/planet heaps, stardust, commander (NAME..SVC), JOPOS
        [sy.UP, sy.VOL + 1 - sy.UP, "UP"],                      // configuration (COMC..VOL; up to Stage B also the
                                                                // constant TGINT, which then moved away from S%)
        [sy["NA%"], sy["NAEND%"] - sy["NA%"], "NA%"],           // last saved commander (template) and checksums
        [sy.SOFLG, sy.SFXPR - sy.SOFLG, "SOUND"],               // sound buffers (written by the IRQ)
    ];
}

// Pointers in the compared state to data that a relocated build moves, put
// back to the original's addresses in each snapshot (the reference's are
// unchanged), so builds that move the data compare equal:
//  * the space station's ship line heap is LSO, in WP (NWSPS sets bytes
//    #33-#34 of its ship data block to LSO's address), so INWK(34 33) and
//    bytes #33-#34 of the K% slots may hold LSO's address: the original's
//    (&107E) goes in its place;
//  * XX0 points at the current ship's blueprint: the blueprints keep the
//    original's order from XX21 (&8000 in the original) to SNE, so a pointer
//    into them is moved by the difference.
// canonFor(sy, regions) returns the function that does it to a snapshot.
const LSO_ORIG = 0x107e, XX21_ORIG = 0x8000;
export function canonFor(sy, regions) {
    const offOf = a => { let o = 0; for (const [b, n] of regions) { if (a >= b && a + 1 < b + n) return o + a - b; o += n; } return -1; };
    const offs = [sy.INWK + 33, ...Array.from({ length: 12 }, (_, i) => sy["K%"] + 37 * i + 33)].map(offOf).filter(o => o >= 0);
    const xx0 = sy.XX0 === undefined ? -1 : offOf(sy.XX0);
    return buf => {
        if (sy.LSO !== LSO_ORIG) for (const o of offs) if ((buf[o] | buf[o + 1] << 8) === sy.LSO) { buf[o] = LSO_ORIG & 255; buf[o + 1] = LSO_ORIG >> 8; }
        if (sy.XX21 !== undefined && sy.XX21 !== XX21_ORIG && sy.SNE !== undefined && xx0 >= 0) {
            const v = buf[xx0] | buf[xx0 + 1] << 8;
            if (v >= sy.XX21 && v < sy.SNE) { const w = v - sy.XX21 + XX21_ORIG; buf[xx0] = w & 255; buf[xx0 + 1] = w >> 8; }
        }
        return buf;
    };
}

// Addresses excluded from the comparison, by symbol: name -> [length, reason]
export const TIMING_EXCLUDE = {
    DL: [1, "set to 30 by the vsync IRQ (LINSCN), cleared and polled by WSCAN: real time"],
    JOPOS: [3, "ADC values written by the IRQ (conversions disabled; only read with the joystick configured)"],
    SOFLG: [sy => sy.SFXPR - sy.SOFLG, "sound buffers SOFLG..SOFRQ, counted down by SOINT in the IRQ"],
};
// Temporaries that hold addresses of code or data that a relocated build moves
// (Stage B): they differ between builds without any difference in game state,
// and the game writes them before it reads them. Excluded by default.
export const RELOC_EXCLUDE = {
    P: [2, "temporary; CHPR leaves P(1 0) pointing at the font's glyph"],
    V: [2, "temporary; the token printers leave V(1 0) pointing into the token tables"],
};
// Drawing temporaries and heaps: excluded with --loose (for builds whose drawing
// differs; the pilot and the game logic never read them across iterations)
export const DRAW_EXCLUDE = {
    SC: [2, "screen address"], T1: [1, "temp"], T2: [1, "temp"], T3: [1, "temp"], T4: [1, "temp"],
    P: [3, "temp"], Q: [1, "temp"], R: [1, "temp"], S: [1, "temp"], T: [1, "temp"], U: [1, "temp"],
    XX15: [6, "line ends"], XX12: [6, "temp"], K: [4, "temp"], K2: [4, "temp"], K3: [14, "temp"], K4: [2, "temp"],
    K5: [4, "temp"], K6: [5, "temp"], XX16: [18, "temp"], XX0: [2, "blueprint ptr"], XX: [2, "temp"], YY: [2, "temp"],
    XSAV: [1, "temp"], YSAV: [1, "temp"], XX17: [1, "temp"], XX13: [1, "temp"], CNT: [1, "temp"], CNT2: [1, "temp"],
    STP: [1, "temp"], XX4: [1, "temp"], XX20: [1, "temp"], ZZ: [1, "temp"], V: [2, "temp"], LSP: [1, "ball heap ptr"],
    LSNUM: [1, "line heap"], LSNUM2: [1, "line heap"], XX14: [1, "temp"], SWAP: [1, "temp"], COL: [1, "colour"],
    XC: [1, "text cursor"], YC: [1, "text cursor"], LSX2: [256, "planet line heap"], LSY2: [256, "planet line heap"],
    LSO: [200, "sun line heap"], BUF: [90, "line buffer"], XSAV2: [1, "temp"], YSAV2: [1, "temp"],
    COMX: [1, "compass dot"], COMY: [1, "compass dot"], widget: [1, "temp"], dontclip: [1, "temp"], Yx2M1: [1, "temp"],
    newzp: [1, "temp"], XX18: [4, "temp"],
};

export function excludeSet(sy, lists) {
    const ex = new Map();
    for (const list of lists) for (const [n, [len0, why]] of Object.entries(list)) {
        if (sy[n] === undefined) continue;
        const len = typeof len0 === "function" ? len0(sy) : len0;
        for (let i = 0; i < len; i++) ex.set(sy[n] + i, `${n}: ${why}`);
    }
    // with the drawing exclusions, also the ship line heap below &0800 (the K%
    // blocks end at K% + NOSH * NI%)
    if (lists.includes(DRAW_EXCLUDE)) for (let a = sy["K%"] + 12 * 37; a < 0x0800; a++) ex.set(a, "ship line heap");
    return ex;
}

// The Master's CMOS RAM and real-time clock, made the machine's own and fixed. jsbeeb's
// clock reads the host's (local) time, and every machine in a process shares its CMOS
// bytes (one array, written through). Neither changes anything Elite does today: in a
// boot and an agentplay session the MOS and the game read CMOS bytes &13-&1E only, never
// the clock, and write only the clock's control registers A and B, at reset. Fixed all the
// same, so that no run can depend on when or beside what it runs: each machine gets its
// own copy of the CMOS bytes, and the clock always reads RTC_TIME, in UTC (writes to it
// are ignored).
export const RTC_TIME = Date.UTC(2000, 0, 1, 0, 0, 0);
export function pinRtc(s) {
    const c = s._machine.processor.cmos, read = c.read.bind(c), t = new Date(RTC_TIME);
    const bcd = v => parseInt(String(v % 100), 16);
    const clock = { 0: t.getUTCSeconds(), 2: t.getUTCMinutes(), 4: t.getUTCHours(), 6: t.getUTCDay() + 1, 7: t.getUTCDate(), 8: t.getUTCMonth() + 1, 9: t.getUTCFullYear() };
    c.store = c.store.slice();
    c.read = () => {
        const v = read();
        if (c.enabled && !c.addressSelect && c.dataSelect && c.isRead && c.cmosAddr in clock) return bcd(clock[c.cmosAddr]);
        return v;
    };
}

// Machine set-up: boot the Master, insert the disc, SHIFT+BREAK
export async function bootMaster(disc) {
    const s = new MachineSession("Master");
    await s.initialise();
    pinRtc(s);
    await s.boot(30);
    s.loadDisc(disc);
    s.keyDown(16); s.reset(true); await s.runFor(2000000); s.keyUp(16);
    if (process.env.XTRACE) xTrace(s, process.env.XTRACE, disc);
    return s;
}

// XTRACE=<file>: record each instruction address run with ACCCON X set (shadow
// RAM at &3000-&7FFF), with its mapping at &8000-&BFFF ("m", a bank or "A"),
// and write them, one "<disc> <mapping>:<address>" a line, to <file> at exit (appending, so several runs
// add up). Code that runs so must be below &3000 or in a sideways bank, never
// in main RAM at &3000-&7FFF (docs/memory-map.md).
function xTrace(s, file, disc) {
    const tag = String(disc) + " ";
    const cpu = s._machine.processor, seen = new Set();
    cpu.debugInstruction.add(pc => { if (cpu.acccon & 4) seen.add(mapAt(cpu.romsel, pc) + ":" + pc.toString(16)); return false; });
    process.on("exit", () => { if (seen.size) appendFileSync(file, [...seen].map(k => tag + k).join("\n") + "\n"); });
}

// Run one build under the pilot.
//   opts.disc, opts.syms (symbol table), opts.pilot (object with keys(ctx), dks(ctx)),
//   opts.iters (MLOOP iterations to record), opts.maxSecs (emulated), opts.seed (array of
//   [addr, bytes] to write at TT170), opts.seedBoot(regions, written, rb) (at TT170:
//   returns more [addr, bytes] to write, given the set of addresses written since
//   the game's entry S%), opts.patch({ wr, rb, sy }) (called at BAY after QU5,
//   i.e. after the title screens' DFAULT: the commander patch), opts.onIter(i, s, res),
//   opts.trace (log injected keys), opts.shots / opts.onShot(s, i) (screenshot every N)
// Returns { snaps (per iteration, regions concatenated), iterTimes, tt100Times
//   ([emulated s, iteration] per TT100), init (snapshot at TT170), initRand, keyLog,
//   events, iters, tt100, emuSecs, error }
export async function runElite(opts) {
    const sy = opts.syms;
    const s = await bootMaster(opts.disc);
    const cpu = s._machine.processor;
    const regions = regionsFor(sy);
    const canon = canonFor(sy, regions);
    const rd = (a, n = 1) => { const r = new Array(n); for (let i = 0; i < n; i++) r[i] = cpu.ramRomOs[(a + i) & 0xffff]; return r; };
    const rb = a => cpu.ramRomOs[a & 0xffff];
    const wr = (a, bytes) => { for (let i = 0; i < bytes.length; i++) cpu.ramRomOs[a + i] = bytes[i] & 255; };
    // label lookup for call sites, per mapping ("m" for main RAM, then ANDY and
    // the sideways banks, from build/banks.txt). A cold copy's label (name_C) is
// reported as name.
    const labs = {};
    for (const [k, v] of Object.entries(sy)) {
        if (v < 0x0800 || /^(CODE|LOAD)/.test(k)) continue;   // (section addresses, not routines)
        const m = mapOfLabel(sy, k);
        if (m === "m" && v >= 0x8000) continue;
        (labs[m] ||= []).push([k, v]);
    }
    for (const l of Object.values(labs)) l.sort((a, b) => a[1] - b[1]);
    const labelOf = (a, romsel = cpu.romsel) => {
        const lab = labs[mapAt(romsel, a)] || [];
        let lo = 0, hi = lab.length - 1, r = null;
        while (lo <= hi) { const m = (lo + hi) >> 1; if (lab[m][1] <= a) { r = lab[m][0]; lo = m + 1; } else hi = m - 1; }
        return r && r.endsWith("_C") ? r.slice(0, -2) : r;      // (cold copies keep their names, plus _C)
    };
    const stackWord = k => rb(0x100 + ((cpu.s + k) & 0xff)) | (rb(0x100 + ((cpu.s + k + 1) & 0xff)) << 8);
    // The JSR whose return address is at S+k: its address and the ROMSEL it ran
    // with, seeing through the stubs between the passes. A stub
    // (elite-stubs.asm) runs its target with the stack holding the
    // return into the stub, then the caller's own return address; the caller's
    // bank is the stub's: bank 4 for the stubs into the cold pass (STUBS7 to
    // STUBS7_END), bank 7 for those out of it (STUBS4 to STUBS4_END).
    // (romsel: what the code that owns S+k ran with, if not the current ROMSEL:
    // the ROMSEL of the frame below, when walking further up a chain)
    const callerAt = (k, romsel = cpu.romsel) => {
        let w = stackWord(k);
        for (;;) {
            const b = stubBank(sy, w + 1);
            if (b === null) break;
            romsel = b;
            k += 2;
            w = stackWord(k);
        }
        return { site: w + 1 - 3, romsel, k };
    };
    // hook points: address and mapping
    // (a routine moved to the cold area is hooked at its cold copy, name_C: code
    // outside reaches it through a stub of the old name, cold code directly)
    const hook = (name, off = 0) => { const n = sy[name + "_C"] !== undefined ? name + "_C" : name; return { a: sy[n] + off, m: mapOfLabel(sy, n) }; };
    const at = (h, pc) => pc === h.a && (h.m === "m" || h.m === mapAt(cpu.romsel, pc));
    const H_RDK = hook("RDKEY", 5), H_DKS5 = hook("DKS5", 17), H_NOISE = hook("NOISE"), H_MLOOP = hook("MLOOP"), H_LL5 = hook("LL5"),
        H_TT100 = hook("TT100"), H_QU5 = hook("QU5"), H_BAY = hook("BAY"), H_MT26 = hook("MT26"), H_TT170 = hook("TT170");

    const res = { snaps: [], screens: [], iterTimes: [], tt100Times: [], tt100AtIter: [], init: null, keyLog: [], events: [], s, cpu, sy, regions };
    let started = false, done = false, armPatch = false, iter = 0, tt100 = 0, checked = false;
    const ctxBase = { rb, rd, sy, iterOf: () => iter, tt100Of: () => tt100 };

    const ikm = mapOfLabel(sy, "IKNS");
    function fillkl(keys) {
        // as FILLKL: ZEKTRAN clears JSTY+1..JSTY+17, then each pressed key in increasing
        // internal number sets KL and, if it is in IKNS, decrements its logger byte
        for (let i = 1; i <= 17; i++) cpu.ramRomOs[sy.JSTY + i] = 0;
        let x = 0;
        for (const k of [...new Set(keys)].filter(k => k >= 16 && k < 128).sort((a, b) => a - b)) {
            cpu.ramRomOs[sy.KL] = k;
            for (;;) {
                const ik = physRead(cpu, ikm, sy.IKNS + x);     // (IKNS may be in bank 4)
                if (k < ik) break;
                if (k === ik) { cpu.ramRomOs[sy.KY17 + x] = (rb(sy.KY17 + x) - 1) & 255; x++; break; }
                x++;
            }
        }
        cpu.ramRomOs[sy.KY19] = rb(sy.KY19) & (rb(sy.KY6) ^ 0xff);
        cpu.x = rb(sy.KL);
    }

    const handler = pc => {
        if (at(H_RDK, pc) && started) {
            const c = callerAt(2);
            const callSite = c.site;
            const site = labelOf(callSite, c.romsel);
            // for waits (t, t2 in TT217), the routine that called the wait
            let waitFor = null;
            if (site === "t" || site === "t2") { const w = callerAt(c.k + 2, c.romsel); waitFor = labelOf(w.site, w.romsel); }
            const ctx = { ...ctxBase, kind: "rdkey", site, callSite, waitFor };
            const keys = opts.pilot.keys(ctx) || [];
            fillkl(keys);
            if (keys.length) res.keyLog.push([iter, site + (waitFor ? "<" + waitFor : ""), keys.map(k => k.toString(16)).join("+")]);
            if (opts.trace && keys.length) console.log(`iter ${iter} ${site}${waitFor ? "<" + waitFor : ""}: ${keys.map(k => "&" + k.toString(16)).join(" ")}`);
        } else if (at(H_DKS5, pc) && started) {
            const key = cpu.a;
            const c = callerAt(1);
            const site = labelOf(c.site, c.romsel);
            const down = opts.pilot.dks ? opts.pilot.dks({ ...ctxBase, kind: "dks5", key, site }) : false;
            cpu.x = down ? key | 0x80 : key;
            if (down) res.keyLog.push([iter, "DKS5:" + site, key.toString(16)]);
        } else if (at(H_NOISE, pc)) {
            for (let i = 0; i < 3; i++) cpu.ramRomOs[sy.SOPR + i] = 0;
        } else if (at(H_LL5, pc)) {
            // The altitude (main flight loop part 15) is SQRT(R Q) with R =
            // x_hi^2 + y_hi^2 + z_hi^2 - 37 and Q whatever the last routine to
            // use Q left there: game logic (MVS4, MVS5) or, when a line was
            // drawn last, LOINQ's slope arithmetic (LIlog6). A build whose
            // drawing differs leaves a different Q, so the altitude can differ
            // by one (and with R = 0, Q = 0 decides a crash). At that call
            // (LL5 returning to LDA Q : STA ALTIT) Q is set to 0 in both runs.
            const ret = (rb(0x101 + cpu.s) | rb(0x102 + cpu.s) << 8) + 1;
            const rc = a => cpu.readmem(a & 0xffff);     // (the caller's code, as paged: it may be in bank 4)
            if (rc(ret) === 0xa5 && rc(ret + 1) === sy.Q && rc(ret + 2) === 0x8d && (rc(ret + 3) | rc(ret + 4) << 8) === sy.ALTIT)
                cpu.ramRomOs[sy.Q] = 0;
        } else if (at(H_MLOOP, pc) && started) {
            res.snaps.push(snapshot());
            if (opts.screen) res.screens.push(screenHash());
            res.iterTimes.push(emuSecs());
            res.tt100AtIter.push(tt100);
            if (opts.pilot.observe) opts.pilot.observe({ ...ctxBase, kind: "iter" });
            if (opts.onIter) opts.onIter(iter, s, res);
            iter++;
            if (iter >= opts.iters) { done = true; return true; }
        } else if (at(H_TT100, pc) && started) {
            res.tt100Times.push([emuSecs(), iter]);
            tt100++;
        } else if (at(H_QU5, pc)) {
            armPatch = true;
        } else if (at(H_BAY, pc) && armPatch) {
            armPatch = false;
            if (opts.patch) opts.patch({ wr, rb, sy });
            res.events.push([iter, "commander patched at BAY"]);
        } else if (at(H_MT26, pc) && started) {
            res.events.push([iter, "MT26 (OSWORD line input) reached: not supported"]);
            res.error = "MT26";
            done = true; return true;
        } else if (at(H_TT170, pc) && !started) {
            started = true;
            if (!checked) {
                checked = true;
                const op = (h, i = 0) => physRead(cpu, h.m, h.a + i);
                if (op(H_RDK) !== 0x68) throw new Error(`RDKEY+5 is not PLA (&${op(H_RDK).toString(16)})`);
                if (op(H_DKS5) !== 0xa9 || op(H_DKS5, 1) !== 0x0b) throw new Error("DKS5+17 is not LDA #&0B");
            }
            if (opts.seed) for (const [a, bytes] of opts.seed) wr(a, bytes);
            if (opts.seedBoot) { res.seeded = opts.seedBoot(regions, written, rb); for (const [a, bytes] of res.seeded) wr(a, bytes); }
            bootWrites.remove();
            res.init = snapshot();
            res.initRand = rd(sy.RAND, 4);
        }
        return false;
    };
    function snapshot() {
        const out = [];
        for (const [a, n] of regions) out.push(...rd(a, n));
        return canon(Uint8Array.from(out));
    }
    // opts.screen: a hash of the screen in shadow RAM (&4000-&7DFF: the space
    // view and the dashboard) at each MLOOP, for builds that draw as the
    // original does (jsbeeb keeps shadow RAM at &3000-&7FFF at &B000-&FFFF)
    function screenHash() {
        return createHash("sha1").update(cpu.ramRomOs.subarray(0xc000, 0xfe00)).digest("hex").slice(0, 16);
    }
    function emuSecs() { return cpu.cycleSeconds + cpu.currentCycles / 2e6; }
    // the addresses written between the game's entry (S%) and TT170, by the game
    // or by the MOS on its behalf: anything else in the compared state at TT170
    // was left by the boot and the loader (opts.seedBoot)
    const H_S = hook("S%");
    const written = new Set();
    let inGame = false;
    const bootWrites = cpu.debugWrite.add(a => { if (inGame && a < 0x8000) written.add(a); return false; });
    // Page &0D is off limits (docs/master-memory.md): once the game has
    // started, only the MOS and the filing system ROM may write it (DFS
    // rewrites its NMI routine at &0D00 for every disc operation). Writes by
    // code in RAM (main RAM, sideways RAM banks 4-7, HAZEL) are recorded in
    // res.page0d, and mcompare fails the candidate on any.
    res.page0d = [];
    cpu.debugWrite.add(a => {
        if (!inGame || a < 0x0d00 || a > 0x0dff) return false;
        const pc = cpu.pc;
        const inRam = pc < 0x8000 || (pc < 0xc000 && (cpu.romsel & 15) >= 4 && (cpu.romsel & 15) <= 7) || (pc < 0x9000 && pc >= 0x8000 && (cpu.romsel & 0x80)) ||
            (pc >= 0xc000 && pc < 0xe000 && (cpu.acccon & 8));
        // the one exception: DOSNMI (cold area) puts the loader's minimal NMI
        // handler back at &0D00 after a disc command
        if (sy.DOSNMI_C !== undefined && pc >= sy.DOSNMI_C && pc < sy.DOSNMI_END_C && (cpu.romsel & 15) === 7) return false;
        if (inRam && res.page0d.length < 20) res.page0d.push([iter, pc, a]);
        return false;
    });
    const entry = cpu.debugInstruction.add(pc => { if (at(H_S, pc)) { inGame = true; entry.remove(); } return false; });
    cpu.debugInstruction.add(handler);
    const maxSecs = opts.maxSecs || 7200;
    let shotAt = 0;
    while (!done && emuSecs() < maxSecs) {
        for (let k = 0; k < 40 && !done; k++) { if (handler(cpu.pc)) break; cpu.execute(50000); }
        if (opts.shots && iter >= shotAt + opts.shots) { shotAt = iter; await opts.onShot(s, iter); }
    }
    res.emuSecs = emuSecs();
    res.iters = iter; res.tt100 = tt100;
    handler.remove();
    return res;
}

// Snapshot helpers
export function offsetToAddr(regions, o) {
    for (const [a, n] of regions) { if (o < n) return a + o; o -= n; }
    return -1;
}
export function valAt(regions, buf, ad) {
    let o = 0;
    for (const [a, n] of regions) { if (ad >= a && ad < a + n) return buf[o + ad - a]; o += n; }
    return -1;
}
