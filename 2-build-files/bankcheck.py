#!/usr/bin/env python3
# bankcheck.py: check the banking rules of the relocated Master Elite
# (docs/memory-map.md, elite-stubs.asm). Run by the Makefile from the repository's root.
#
# Areas: "main" (elite-source.asm's configuration, its low pass and the hot
# pass's containers in main RAM, 3-assembled-output/elite-source-config.asm, -low.asm,
# -hot1.asm and -hot2.asm, and the files in main RAM: the glue area ...), "bank4" (the hot pass's container in bank 4,
# 3-assembled-output/elite-source-hot3.asm, with the CMYK dashboard, and the hot data that
# follows it, 3-assembled-output/elite-data-hot4.asm), "cold" (elite-source.asm's cold blocks,
# 3-assembled-output/elite-source-cold.asm and 3-assembled-output/elite-data-cold.asm: ROMSEL COLDBANK,
# bank 7). The stubs between the passes are in the glue area
# (2-build-files/streams.py). Main RAM and bank 4 see each other (bank 4 is paged
# whenever game code runs). The cold area is only paged through the stubs.
#
# Rules, for every reference from code or data in one area to a label in
# another:
#  * branches never cross areas;
#  * cold code reaches main or bank 4 code only through stubs (x4_name,
#    j4_name, in 3-assembled-output/elite-stubs.asm: "stubs"), or, for the low pass's
#    routines that need nothing of the hot side, directly (streams.py's
#    3-assembled-output/direct.txt), and never reads bank 4 data (it may take an
#    address: #LO/#HI);
#  * main and bank 4 code reach cold code only through stubs (name, in
#    3-assembled-output/elite-stubs.asm, whose body is name_C), and never read cold data;
#  * the stubs (elite-stubs.asm and 3-assembled-output/elite-stubs.asm) may refer to
#    anything, and every area may call them;
#  * a line with the comment "bankcheck: ok" is exempt (reviewed by hand).
#  * the renderer's banks (bank5: gfx-raster.asm, the rasteriser's shared region,
#    with its disc window bank5d, gfx-raster_disc.asm, and its polygon window
#    bank5a, gfx-raster_poly.asm and gfx-raster_line.asm, in ANDY, which never
#    refer to each other; the shared region, which runs with either window
#    paged in, refers to neither (but for lines marked bankcheck: ok);
#    bank6: the frame layer, the
#    faces, the lighting tables, frame_cold and the flare's bank 6 part,
#    bank5 also the lens flare and R_LINE's cold part, gfx-raster_lcold.asm;
#    bank7m: the meridian window, gfx-merid.asm, in bank 7 after the cold
#    area, which only the stubs page in) are reached
#    from other areas only through the stubs in GLUE files (G_ stubs, T_
#    trampolines, the glue area's hooks) or as addresses (#LO/#HI); their
#    code calls main RAM and HAZEL code directly but nothing in another bank,
#    reads no other bank's data, and reads main RAM data only below &3000 (the frame layer may run with ACCCON
#    X set, which hides main RAM above);
#  * no label or constant of the renderer's is in HAZEL (&C000-&DFFF), and
#    nothing labelled is in &DF00-&DFFF (the MOS's);
#  * "hazel" is visible to every area: HAZEL (the game data,
#    3-assembled-output/elite-data-hot.asm) and the renderer's shared
#    workspace in main RAM below &3000 (elite-gfx.asm, gfx-raster_scr.asm,
#    gfx-raster_vars.asm); the renderer's glue is main RAM below &3000 (the
#    glue area), which every area sees too.
# Exit status 1 if any rule is broken.
import re, sys

SRC = "1-source-files/main-sources/"
FILES = {"../../3-assembled-output/elite-source-config.asm": "main", "../../3-assembled-output/elite-source-low.asm": "main",
         "../../3-assembled-output/elite-source-hot1.asm": "main", "../../3-assembled-output/elite-source-hot2.asm": "main",
         "../../3-assembled-output/elite-source-hot3.asm": "bank4", "../../3-assembled-output/elite-source-cold.asm": "cold", "elite-layout.asm": "main", "elite-stubs.asm": "stubs", "../../3-assembled-output/elite-stubs.asm": "stubs", "gfx-gstubs.asm": "main", "elite-qs.asm": "main", "gfx-hooks.asm": "main",
         # elite-data.asm's hot data (in HAZEL, and in bank 4 what HAZEL has no
         # room for) and cold data (in the cold pass)
         "../../3-assembled-output/elite-data-hot.asm": "hazel", "../../3-assembled-output/elite-data-hot4.asm": "bank4", "../../3-assembled-output/elite-data-cold.asm": "cold",
         # the renderer: its glue in the glue area (stubs, trampolines, hooks,
         # shared variables), its shared workspace and its banks
         "elite-glue.asm": "main",
         "gfx-gvars.asm": "main", "gfx-tramp.asm": "main", "gfx-gluehooks.asm": "main",
         "gfx-raster_scr.asm": "hazel",
         "gfx-raster_vars.asm": "hazel", "elite-gfx.asm": "hazel",
         "gfx-raster.asm": "bank5", "gfx-raster_disc.asm": "bank5d", "gfx-raster_poly.asm": "bank5a",
         "gfx-raster_line.asm": "bank5a", "gfx-raster_lcold.asm": "bank5",
         "gfx-frame.asm": "bank6", "gfx-faces.asm": "bank6", "gfx-light6.asm": "bank6", "gfx-light.asm": "bank6", "gfx-finit.asm": "bank6",
         "gfx-frame_cold.asm": "bank6", "gfx-flare6.asm": "bank6", "gfx-hangar.asm": "bank6", "gfx-hangar6.asm": "bank6", "gfx-flare.asm": "bank7m",
         "gfx-merid.asm": "bank7m", "gfx-planet7.asm": "bank7m", "gfx-planetv.asm": "hazel",  # (the shared workspace)
         "gfx-raster_kept.asm": "bank5d", "gfx-raster_disc2.asm": "bank5", "gfx-ssun.asm": "bank4", "gfx-kept7.asm": "bank7m"}
# the copies of elite-source.asm that 2-build-files/streams.py writes, one per area
# (their line numbers are elite-source.asm's)
SHOW = {"../../3-assembled-output/elite-source-%s.asm" % a: "elite-source.asm" for a in ("config", "low", "hot1", "hot2", "hot3", "cold")}
SHOW.update({"../../3-assembled-output/elite-data-%s.asm" % a: "elite-data.asm" for a in ("hot", "hot4", "cold")})
RENDER = ("bank5", "bank5d", "bank5a", "bank6", "bank7m")
# the rasteriser's bank 5: its shared region (bank5, &9000-&BFFF) is seen with
# either window, the disc window (bank5d, ROMSEL 5) or the polygon window
# (bank5a, ANDY, ROMSEL &85), which are never paged in together
RAST5 = ("bank5", "bank5d", "bank5a")
# the files that hold the cross-bank stubs into the renderer's banks (the G_
# stubs page bank 6 in from game code, the T_ trampolines bank 5 (ANDY over it
# for R_POLY and R_LINE) from bank 6, the glue area's hooks bank 6 from any bank)
GLUE = ("gfx-gstubs.asm", "gfx-tramp.asm", "gfx-gluehooks.asm")
MNEM = set(("ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRA BRK BVC BVS CLC CLD CLI CLV CMP CPX CPY "
            "DEC DEX DEY EOR INC INX INY JMP JSR LDA LDX LDY LSR NOP ORA PHA PHP PHX PHY PLA PLP PLX "
            "PLY ROL ROR RTI RTS SBC SEC SED SEI STA STX STY STZ TAX TAY TRB TSB TSX TXA TXS TYA").split())
BRANCH = set("BCC BCS BEQ BMI BNE BPL BRA BVC BVS".split())
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_%]*")


def code_part(line):
    out, q = "", False
    for ch in line:
        if ch == '"':
            q = not q
        if ch == "\\" and not q:
            break
        out += ch
    return out


def statements(path):
    try:
        lines = open(path).read().split("\n")
    except FileNotFoundError:
        return
    for n, line in enumerate(lines, 1):
        c = code_part(line)
        ok = "bankcheck: ok" in line
        for st in re.split(r"\s:\s", c):
            t = st.strip()
            labels = []
            while True:
                m = re.match(r"^\.([A-Za-z_][\w%]*)\s*(.*)$", t)
                if not m:
                    break
                labels.append(m.group(1))
                t = m.group(2).strip()
            mn, op = None, ""
            m = re.match(r"^([A-Za-z]{3})\b\s*(.*)$", t)
            if m and m.group(1).upper() in MNEM:
                mn, op = m.group(1).upper(), m.group(2)
            else:
                op = t
            yield n, line, labels, mn, op, ok


def idents(op):
    s = re.sub(r"'.'", "", re.sub(r'"[^"]*"', "", op))   # (strings and character literals)
    s = re.sub(r"&[0-9A-Fa-f]+", "", s)
    return IDENT.findall(s)


area = {}
own = {}                                   # each file's own labels (local names win)
for f, a in FILES.items():
    own[f] = set()
    for n, line, labels, mn, op, ok in statements(SRC + f):
        for l in labels:
            area.setdefault(l, a)
            own[f].add(l)
        m = re.match(r"^([A-Za-z_]\w*)\s*=", op.strip())
        if m and mn is None:               # (constants and macro locals the file assigns)
            own[f].add(m.group(1))
        m = re.match(r"^(MACRO\s+\w+|FOR)\s+(.*)$", op.strip(), re.I)
        if m:                              # (macro parameters and loop variables)
            own[f].update(IDENT.findall(m.group(2).split(",")[0] if m.group(1).upper() == "FOR" else m.group(2)))
direct = set()                             # the low pass's labels the cold pass calls
try:                                       # directly (2-build-files/streams.py)
    direct = set(open("3-assembled-output/direct.txt").read().split())
except FileNotFoundError:
    pass
addr = {}                                  # the labels' addresses (3-assembled-output/symbols.txt)
try:
    for m in re.finditer(r"'([^']+)':(\d+)", open("3-assembled-output/symbols.txt").read()):
        addr.setdefault(m.group(1), int(m.group(2)))
except FileNotFoundError:
    pass
errors = []
# HAZEL (&C000-&DFFF) holds the game data only: no label or constant of the
# renderer's (elite-gfx.asm and the gfx- files: code, tables, variables,
# stubs) may be there, and &DF00-&DFFF is the MOS's (docs/memory-map.md, rule 5)
for f in FILES:
    if f == "elite-gfx.asm" or f.startswith("gfx-"):
        for l in sorted(own[f]):
            if 0xC000 <= addr.get(l, 0) < 0xE000:
                errors.append("%s: the renderer's %s is in HAZEL (&%04X)" % (f, l, addr[l]))
for l, v in addr.items():
    if 0xDF00 <= v < 0xE000 and area.get(l) is not None:
        errors.append("%s is at &%04X, the MOS's page of HAZEL" % (l, v))
for f, a in FILES.items():
    prev, prevop = None, None
    for n, line, labels, mn, op, ok in statements(SRC + f):
        if ok:
            prev, prevop = mn, op.strip()
            continue
        if mn is None and re.match(r"^[A-Za-z_][\w%]*\s*=", op.strip()):
            continue                       # (an assignment defines a constant)
        if mn is None and re.match(r"^(PRINT|SAVE|ASSERT|IF|ELIF|SKIP|ORG|CLEAR|ALIGN|GUARD|INCLUDE|INCBIN)\b", op.strip(), re.I):
            continue                       # (assembler directives)
        for x in idents(op):
            b = "self" if x in own[f] else area.get(x)
            if b is None or b == a or b == "self" or a == "stubs" or b == "stubs":
                continue                   # (the stubs are callable from anywhere, and
                                           # reach both sides)
            where = "%s:%d" % (SHOW.get(f, f), n)
            if a in RAST5 and b in RAST5:
                if {a, b} == {"bank5d", "bank5a"} and not op.strip().startswith("#"):
                    errors.append("%s: %s refers to %s label %s (the disc and polygon windows are never paged in together)" % (where, a, b, x))
                elif a == "bank5" and not op.strip().startswith("#"):
                    errors.append("%s: the shared region refers to %s label %s (it runs with either window paged in)" % (where, b, x))
                continue
            if mn in BRANCH:
                errors.append("%s: branch from %s to %s %s" % (where, a, b, x))
            elif b in RENDER or a in RENDER:
                if op.strip().startswith("#") or f in GLUE:
                    continue               # (an address, or a stub that pages the bank in)
                if a in RENDER and b in ("main", "hazel") and mn in ("JSR", "JMP"):
                    continue               # (main RAM and HAZEL code is visible from the banks)
                if a in RENDER and b == "main" and addr.get(x, 0x10000) < 0x3000:
                    continue               # (main RAM below &3000 is visible whatever ACCCON X)
                if b == "hazel":
                    continue
                errors.append("%s: %s refers to %s label %s (use a stub)" % (where, a, b, x))
            elif a == "cold":
                if op.strip().startswith("#"):
                    continue               # (an address, not a read)
                if b in ("bank4", "cold"):
                    errors.append("%s: %s code refers to %s label %s" % (where, a, b, x))
                elif mn in ("JSR", "JMP") and x not in direct:
                    errors.append("%s: %s code calls %s in %s directly (use a stub)" % (where, a, x, b))
                elif mn in ("JSR", "JMP") and addr.get(x, 0x10000) >= 0x3000:
                    errors.append("%s: %s code calls %s directly, which is not below &3000" % (where, a, x))
            else:
                if b == "cold":
                    errors.append("%s: %s refers to cold label %s (use a stub)" % (where, a, x))
        prev = mn
        prevop = op.strip()

for e in errors:
    print("bankcheck:", e)
print("bankcheck: %d labels, %s" % (len(area), "%d rule(s) broken" % len(errors) if errors else "all rules hold"))
sys.exit(1 if errors else 0)
