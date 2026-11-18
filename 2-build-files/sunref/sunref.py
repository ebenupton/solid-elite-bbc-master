#!/usr/bin/env python3
"""sunref.py: the patch to the reference, the released SNG47, that the
harness writes at TT170 so that the original runs the same game logic as
this build: the sun parked while the space station holds its slot (SUNUP,
SUNSC, SUNBK, SUNLAU in src/elite-source.asm; docs/renderer.md, "The
sun's parking"), and the sun's edge drawing no random numbers (SUN's JSR
DORND as LDA #0 : NOP, the fringe 0: "The sun's edge"). Run by the Makefile
from master/; writes

  3-assembled-output/sunref.json          the patch (6-harness/mlib.mjs's loadRefPatch, which
                             mcompare.mjs and agentplay give the reference
                             when it is beside the candidate's symbols)
  3-assembled-output/sunref-passive.json  its passive variant (below)
  3-assembled-output/sunref-edge.json     the sun's edge's site alone, with randAt (the
                             harness advances RAND there as the DORND would:
                             6-harness/msunref.mjs's proof that it changes
                             nothing else)
  3-assembled-output/sunref-symbols.txt   the patch's labels at their SNG47 addresses
                             (beebasm -d), for the harness's hooks
  3-assembled-output/sunref-syms.asm      the bindings sunref.asm assembles with

A patch is:

  code    [[address, [bytes]]]: the routines, assembled at SR_ORG in SNG47's
          unused memory FREE (2-build-files/sunref/sunref.asm: streams.py's second
          emission of the blocks tagged ", again", followed by the parked
          sun, SUNPK and SUNPF, then the space station's line heap, SR_HEAP)
  sites   [{name, addr, orig, new}]: SNG47's bytes at each changed site and
          what they become, each the same length (the harness checks orig
          at TT170 before it writes anything); a site with no label of its
          own has no addr but search: [from, to], a routine's extent, in
          which the harness finds orig exactly once; a site whose new bytes
          are its orig is an anchor, only checked (MAL1g: SUNSC enters
          SNG47's MAL1 there, after its JSR GINF)
  lso     the space station's line heap, SR_HEAP, not LSO (which the sun's
          lines use, as the station and the parked sun are now both drawn);
          the harness maps it to LSO's address in the compared state
  region  [address, length, name]: the parked sun, compared as game state

Every name the routines use is bound to SNG47's address for it (its
symbols, 4-reference-binaries/sng47/symbols.txt and symbols-data.txt), each A_X (a call or a
jump out of the blocks) to SNG47's X, and each number constant
(NOSH = 12 ...) to elite-source.asm's value; a name that is none of these is
an error.

The passive variant's part 14 and TT110 sites call P_SUNUP and P_SUNLAU,
which jump to the original's WPLS and NWSPS, so the sun is never parked and
the other sites (MAL1's SUNSC, KS4's SUNBK, the station's heap) must change
nothing: the original against the original with the passive variant, game
state identical, is the proof (6-harness/msunref.mjs).

The build prints the patch (into 3-assembled-output/compile.txt) and fails unless every
byte it writes is in FREE or at one of its sites, no two sites overlap, no
site is in FREE, and every site keeps its length (sunref.asm asserts that
the station's heap ends below page &0D).

FREE: SNG47 never uses &0B9D-&0CFF. The hangar draws its ships with their
line heap at &0B00 (HAS1: INWK(34 33) = &0B00), at most 157 bytes (the
largest blueprint's, 4 * 39 + 1), and nothing else of SNG47's is in
&0B00-&0CFF (its loader's leftovers aside, which it never reads); the MOS
and DFS do not write there in the game (the port's WP is there, and the save
and load tests pass). 6-harness/msunslot.mjs watches the reference for any
write there that is not the patch's own."""
import json, os, re, subprocess, sys

FREE = (0x0B9D, 0x0D00)                    # SNG47's unused memory (above the hangar's heap)
SR_ORG = FREE[0]
REFSYMS = ("4-reference-binaries/sng47/symbols.txt", "4-reference-binaries/sng47/symbols-data.txt")
AGAIN = "3-assembled-output/elite-source-again.asm"
SRC = "1-source-files/main-sources/elite-source.asm"
ASM = "2-build-files/sunref/sunref.asm"
BEEBASM = os.environ.get("BEEBASM", "beebasm")
OWN = ("SUNPK", "SUNPF", "P_SUNUP", "P_SUNLAU", "SR_START", "SR_END", "SR_ORG", "SR_HEAP", "PASSIVE")
MNEMONICS = set("""ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRK BVC BVS CLC CLD CLI CLV CMP CPX CPY
DEC DEX DEY EOR INC INX INY JMP JSR LDA LDX LDY LSR NOP ORA PHA PHP PLA PLP ROL ROR RTI RTS SBC
SEC SED SEI STA STX STY TAX TAY TSX TXA TXS TYA X Y A LO HI EQUB EQUW""".split())
CMOS = set("BRA STZ PHX PHY PLX PLY TRB TSB".split())


def symbols(paths):
    sy = {}
    for p in paths:
        for m in re.finditer(r"'([^']+)':(\d+)", open(p).read()):
            sy.setdefault(m.group(1), int(m.group(2)))
    return sy


def constants():
    """elite-source.asm's number constants (NAME = 12, NAME = &1F)"""
    out = {}
    for l in open(SRC, encoding="latin-1"):
        m = re.match(r"^\s*([A-Za-z_][\w%]*)\s*=\s*(&[0-9A-Fa-f]+|\d+)\s*(\\.*)?$", l)
        if m:
            v = int(m.group(2)[1:], 16) if m.group(2).startswith("&") else int(m.group(2))
            out.setdefault(m.group(1), v)
    return out


def code_part(line):
    out, q = "", False
    for ch in line:
        if ch == '"':
            q = not q
        if ch == "\\" and not q:
            break
        out += ch
    return out


def bindings(ref):
    """3-assembled-output/sunref-syms.asm: each name the again blocks use, SNG47's"""
    lines = [code_part(l) for l in open(AGAIN, encoding="latin-1")]
    own = set(m.group(1) for l in lines for m in [re.match(r"^\.([A-Za-z_][\w%]*)", l.strip())] if m)
    consts = constants()
    out, bad, used = {}, [], set()
    for l in lines:
        st = l.strip()
        if not st:
            continue
        for op in re.findall(r"\b([A-Z]{3})\b", st):
            if op in CMOS:
                bad.append("%s: a 65C02 instruction (the blocks are NMOS 6502 code, for the Model B too)" % st)
        for n in re.findall(r"(?<![\w%&])([A-Za-z_][\w%]*)", st.lstrip(".")):
            if n in MNEMONICS or n in own or n in OWN:
                continue
            used.add(n)
    used |= {"A_WPLS", "A_NWSPS"}         # (the passive variant's P_SUNUP and P_SUNLAU)
    for n in sorted(used):
        x = n[2:] if n.startswith("A_") else n
        if x in ref:
            out[n] = ref[x]
        elif n == x and x in consts:
            out[n] = consts[x]
        elif n == "A_MAL1g":
            out[n] = ref["MAL1"] + 15     # (SNG47's MAL1 after its JSR GINF: an anchor site)
        else:
            bad.append("%s: not in SNG47's symbols, nor a constant" % n)
    with open("3-assembled-output/sunref-syms.asm", "w") as f:
        f.write("\\ Generated by 2-build-files/sunref/sunref.py: the names the routines use, SNG47's\n")
        f.write("SR_ORG = &%04X\n" % SR_ORG)
        for n, v in sorted(out.items()):
            f.write("%s = &%04X\n" % (n, v))
    return out, bad


def assemble(passive):
    r = subprocess.run([BEEBASM, "-i", ASM, "-D", "PASSIVE=%d" % passive, "-d"], capture_output=True, text=True)
    if r.returncode:
        sys.exit("sunref: beebasm failed:\n" + r.stdout[-2000:] + r.stderr[-2000:])
    sy = {}
    for m in re.finditer(r"'([^']+)':(\d+)", r.stdout):
        sy.setdefault(m.group(1), int(m.group(2)))
    return sy, open("3-assembled-output/sunref.bin", "rb").read(), r.stdout


def lo_hi(a):
    return [a & 255, a >> 8]


def edge(ref):
    """the sun's edge draws no random numbers: SUN's one JSR DORND (part 3,
    each row's fringe, ANDed with CNT and added to the row's half-width)
    becomes LDA #0 : NOP, so the fringe is 0 and RAND is not touched"""
    return {"name": "SUN: JSR DORND", "addr": None, "orig": [0x20] + lo_hi(ref["DORND"]), "new": [0xA9, 0x00, 0xEA],
            "search": [ref["SUN"], ref["CIRCLE"]]}


def patch(ref, sr, code, passive):
    def site(name, addr, orig, new):
        return {"name": name, "addr": addr, "orig": orig, "new": new}
    up = sr["P_SUNUP"] if passive else sr["A_SUNUP"]
    lau = sr["P_SUNLAU"] if passive else sr["A_SUNLAU"]
    lso = ref["LSO"]
    sites = [
        site("part 14: JSR WPLS", ref["MA23S"] - 6, [0x20] + lo_hi(ref["WPLS"]), [0x20] + lo_hi(up)),
        site("KS4: JSR ZINF", ref["KS4"], [0x20] + lo_hi(ref["ZINF"]), [0x4C] + lo_hi(sr["A_SUNBK"])),
        site("MAL1: JMP MA18", ref["MAL1"] + 7, [0x4C] + lo_hi(ref["MA18"]), [0x4C] + lo_hi(sr["A_SUNSC"])),
        site("MAL1g (anchor)", ref["MAL1"] + 10, [0x85, ref["TYPE"], 0x20] + lo_hi(ref["GINF"]) + [0xA0, 36],
             [0x85, ref["TYPE"], 0x20] + lo_hi(ref["GINF"]) + [0xA0, 36]),
        site("TT110: JSR NWSPS", None, [0x20] + lo_hi(ref["NWSPS"]), [0x20] + lo_hi(lau)),
        site("NWSPS: LDA #LO(LSO)", None, [0xA9, lso & 255, 0x85, ref["INWK"] + 33],
             [0xA9, sr["SR_HEAP"] & 255, 0x85, ref["INWK"] + 33]),
        site("NWSPS: LDA #HI(LSO)", None, [0xA9, lso >> 8, 0x85, ref["INWK"] + 34],
             [0xA9, sr["SR_HEAP"] >> 8, 0x85, ref["INWK"] + 34]),
    ]
    # the sites with no label of their own are found by their bytes, once,
    # within a routine (search: from, to), by the harness at TT170 (the build
    # has SNG47's symbols, not its code)
    for s_, rng in zip(sites[4:], (("TT110", "NLUNCH"), ("NWSPS", "NWSHP"), ("NWSPS", "NWSHP"))):
        s_["search"] = [ref[rng[0]], ref[rng[1]]]
    if not passive:
        sites.append(edge(ref))
    return {"name": "the sun's parking" + (" (passive)" if passive else ", the sun's edge"),
            "code": [[sr["SR_START"], list(code)]], "sites": sites, "lso": sr["SR_HEAP"],
            "region": [sr["SUNPK"], sr["SR_END"] - sr["SUNPK"], "SUNPK"],
            "hooks": {n: sr[n] for n in ("A_SUNUP", "A_SUNBK", "A_SUNSC", "A_SUNLAU", "A_SUNS1") if n in sr}}


def audit(p, sr):
    bad = []
    for a, b in p["code"]:
        if a < SR_ORG or a + len(b) > FREE[1]:
            bad.append("code at &%04X-&%04X is outside &%04X-&%04X" % (a, a + len(b) - 1, SR_ORG, FREE[1] - 1))
    # (the labelled sites against each other; a searched site is within its
    # routine, which no labelled site is in, and the harness finds it once)
    spans = sorted((s["addr"], s["addr"] + len(s["new"]), s["name"]) for s in p["sites"] if s["addr"] is not None)
    for (a0, e0, n0), (a1, e1, n1) in zip(spans, spans[1:]):
        if a1 < e0:
            bad.append("sites %s and %s overlap" % (n0, n1))
    for a0, e0, n0 in spans:
        for s in p["sites"]:
            if s["addr"] is None and a0 < s["search"][1] and e0 > s["search"][0]:
                bad.append("site %s is in %s's routine" % (n0, s["name"]))
    spans += [(s["search"][0], s["search"][1], s["name"]) for s in p["sites"] if s["addr"] is None]
    for a, e, n in spans:
        if e > FREE[0] and a < FREE[1]:
            bad.append("site %s is in the free area" % n)
    for s in p["sites"]:
        if len(s["orig"]) != len(s["new"]):
            bad.append("site %s changes its length" % s["name"])
    n = sum(len(b) for a, b in p["code"])
    print("sunref: %s: %d bytes at &%04X-&%04X (code to &%04X, SUNPK &%04X, SUNPF &%04X), station heap &%04X, %d sites"
          % (p["name"], n, p["code"][0][0], p["code"][0][0] + n - 1, sr["SUNPK"] - 1, sr["SUNPK"], sr["SUNPF"],
             p["lso"], len(p["sites"])))
    for s in p["sites"]:
        print("  %-15s %-22s %s -> %s" % ("&%04X" % s["addr"] if s["addr"] is not None else "&%04X-&%04X" % (s["search"][0], s["search"][1] - 1), s["name"], " ".join("%02X" % b for b in s["orig"]),
                                        " ".join("%02X" % b for b in s["new"])))
    for b in bad:
        print("sunref: AUDIT FAIL: " + b)
    return not bad


def main():
    ref = symbols(REFSYMS)
    out, bad = bindings(ref)
    if bad:
        for b in bad:
            print("sunref: " + b)
        sys.exit(1)
    ok = True
    for passive, name in ((1, "3-assembled-output/sunref-passive.json"), (0, "3-assembled-output/sunref.json")):
        sr, code, dump = assemble(passive)
        p = patch(ref, sr, code, passive)
        ok = audit(p, sr) and ok
        with open(name, "w") as f:
            json.dump(p, f)
    # the sun's edge alone, with the harness advancing RAND at the site as the
    # DORND it replaces would (randAt): the proof that the patch changes nothing
    # but the random numbers' use (6-harness/msunref.mjs)
    with open("3-assembled-output/sunref-edge.json", "w") as f:
        json.dump({"name": "the sun's edge (RAND kept)", "code": [], "sites": [edge(ref)], "lso": None, "region": None,
                   "randAt": "SUN: JSR DORND"}, f)
    with open("3-assembled-output/sunref-symbols.txt", "w") as f:
        f.write(dump)
    if not ok:
        sys.exit(1)


main()
