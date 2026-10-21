#!/usr/bin/env python3
# bankcheck.py: check the banking rules of the relocated Master Elite
# (docs/memory-map.md, elite-far.asm). Run by the Makefile from the repository's root.
#
# Areas: "main" (elite-source.asm's run, build/elite-source-run.asm, its low
# area, build/elite-source-low.asm, and the files they INCLUDE in main RAM:
# elite-far.asm; their labels
# assembled at &8000-&BFFF, where the main code continues, are in bank 4),
# "bank4" (elite-source.asm's blocks in bank 4, build/elite-source-bank4.asm),
# "cold" (elite-source.asm's cold blocks,
# build/elite-source-cold.asm and build/elite-data-cold.asm: ROMSEL COLDBANK,
# bank 7). Each side's far-call stubs are in its own copy, at their targets'
# places (2-build-files/streams.py). Main RAM and bank 4 see each other (bank 4 is paged
# whenever game code runs). The cold area is only paged during far calls.
#
# Rules, for every reference from code or data in one area to a label in
# another:
#  * branches never cross areas;
#  * cold code reaches main or bank 4 code only through stubs (x4_name,
#    j4_name: JSR far4 / far4j : EQUW name), and never reads bank 4 data
#    (it may take an address: #LO/#HI);
#  * main and bank 4 code reach cold code only through stubs (JSR far7 /
#    far7j : EQUW name_C), and never read cold data;
#  * a line with the comment "bankcheck: ok" is exempt (reviewed by hand).
#  * "hazel" is visible to every area: HAZEL (the game data,
#    build/elite-data-hot.asm).
# Exit status 1 if any rule is broken.
import re, sys

SRC = "1-source-files/main-sources/"
FILES = {"../../3-assembled-output/elite-source-run.asm": "main", "../../3-assembled-output/elite-source-low.asm": "main",
         "../../3-assembled-output/elite-source-bank4.asm": "bank4", "../../3-assembled-output/elite-source-cold.asm": "cold", "elite-layout.asm": "main", "elite-far.asm": "main", "elite-hi.asm": "main",
         # elite-data.asm's hot data (in HAZEL) and cold data (in the cold area)
         "../../3-assembled-output/elite-data-hot.asm": "hazel", "../../3-assembled-output/elite-data-cold.asm": "cold",
         "elite-low.asm": "main"}
# the copies of elite-source.asm that 2-build-files/streams.py writes, one per area
# (their line numbers are elite-source.asm's)
SHOW = {"../../3-assembled-output/elite-source-%s.asm" % a: "elite-source.asm" for a in ("run", "low", "bank4", "cold")}
SHOW.update({"../../3-assembled-output/elite-data-%s.asm" % a: "elite-data.asm" for a in ("hot", "cold")})
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
addr = {}                                  # the labels' addresses (build/symbols.txt)
try:
    for m in re.finditer(r"'([^']+)':(\d+)", open("3-assembled-output/symbols.txt").read()):
        addr.setdefault(m.group(1), int(m.group(2)))
except FileNotFoundError:
    pass
for l, a in list(area.items()):           # the main code continues into bank 4:
    if a == "main" and 0x8000 <= addr.get(l, 0) < 0xC000:   # the main files' labels
        area[l] = "bank4"                  # assembled there are in bank 4

errors = []
for f, a in FILES.items():
    prev, prevop = None, None
    for n, line, labels, mn, op, ok in statements(SRC + f):
        if ok:
            prev, prevop = mn, op.strip()
            continue
        if mn is None and re.match(r"^[A-Za-z_][\w%]*\s*=", op.strip()):
            continue                       # (an assignment defines a constant)
        if mn is None and re.match(r"^(PRINT|SAVE|ASSERT|IF|ELIF|SKIP|ORG|CLEAR|ALIGN|GUARD|INCLUDE|INCBIN|R_TO7)\b", op.strip(), re.I):
            continue                       # (assembler directives; R_TO7: the call to bank 7)
        if mn is None and re.match(r"^EQUW\b", op.strip(), re.I) and prev in ("JSR",) and prevop in ("far4", "far4j", "far7", "far7j"):
            prev, prevop = None, None
            continue                       # the EQUW of a far-call stub
        for x in idents(op):
            b = "self" if x in own[f] else area.get(x)
            if b is None or b == a or b == "self" or x in ("far4", "far4j", "far7", "far7j"):
                continue                   # (the far-call code is callable from anywhere)
            where = "%s:%d" % (SHOW.get(f, f), n)
            if mn in BRANCH:
                errors.append("%s: branch from %s to %s %s" % (where, a, b, x))
            elif a == "cold":
                if op.strip().startswith("#"):
                    continue               # (an address, not a read)
                if b in ("bank4", "cold"):
                    errors.append("%s: %s code refers to %s label %s" % (where, a, b, x))
                elif mn in ("JSR", "JMP"):
                    errors.append("%s: %s code calls %s in %s directly (use a stub)" % (where, a, x, b))
            else:
                if b == "cold":
                    errors.append("%s: %s refers to cold label %s (use a stub)" % (where, a, x))
        prev = mn
        prevop = op.strip()

for e in errors:
    print("bankcheck:", e)
print("bankcheck: %d labels, %s" % (len(area), "%d rule(s) broken" % len(errors) if errors else "all rules hold"))
sys.exit(1 if errors else 0)
