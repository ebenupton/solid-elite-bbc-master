#!/usr/bin/env python3
# streams.py: emit the main source in three passes, low, hot and cold, and
# flow the hot pass through its containers (docs/memory-map.md, "The source
# and its passes"). Run by the Makefile from the repository's root, twice:
#
#   python3 2-build-files/streams.py measure    the copies for elite-measure.asm
#   python3 2-build-files/streams.py place      the copies for elite-layout.asm, placed
#                                              by the sizes the measure gave
#
# elite-source.asm is the original's main source in the original's order.
# Each of its routines and tables sits once, at its original place, and the
# pass it is emitted in is a field of its header:
#
#   \       Name: TT219
#   ...
#   \       Area: cold
#
#   * "Area: low": the low pass, Elite's code that must be in main RAM below
#     &3000, where it is seen whatever bank is paged and whatever ACCCON X is
#     (the head, VEC to UP: the IRQ and the sound, CHPR and its font, the
#     log tables, UP ...; stackpt and NEWBRK, which the MOS enters through
#     BRKV with any ROM paged). elite-layout.asm puts it after the glue area,
#     all of it below &3000.
#   * no Area field: the hot pass, the rest of the game code, which runs with
#     Elite's home bank (bank 4) paged. It flows through its containers in
#     order: main RAM from the low pass's end to &4000 (screen buffer 0 is
#     above), main RAM from the quarter-square tables' end (&7400) to &8000,
#     then bank 4 from &8000 (after which the hot data that HAZEL has no room
#     for follows).
#   * "Area: hot, ACCCON X": the hot pass, but code that runs with ACCCON X
#     set (Master's drawing for the docked screens' text and lines, the CMYK
#     dashboard) and the tables it reads, which shadow RAM would hide in main
#     &3000-&7FFF: the flow puts it in bank 4 (in the source's order, before
#     the hot code that follows it in the source).
#   * "Area: cold": the cold pass, sideways RAM bank 7 from &8000.
#
# A block runs from its header to the next header (or to a separator line of
# stars, which starts an untagged block: the original's PRINT and SAVE
# sections). The blocks before the head (the configuration and the
# workspaces: ZP, XX3, K%, WP) are the configuration, assembled first. A
# block that assembles nothing (a banner, constants, PRINTs) goes with the
# block before it.
#
# BeebAsm assembles a file once and has one location counter, and the
# containers share addresses (banks 4 and 7 both at &8000-&BFFF), so each
# container's blocks are assembled from a copy of the source of their own:
# 3-assembled-output/elite-source-<copy>.asm is elite-source.asm with every line outside
# that copy's blocks blanked (so that line numbers stay the source's): config,
# low, hot1 (main RAM to &4000), hot2 (main RAM from &7400), hot3 (bank 4) and
# cold; and for the measure, measure (the whole hot pass in one, with a label
# FLOW_<n> at the start of each block). elite-layout.asm INCLUDEs the copies
# each at its own address, so every label is defined exactly once and every
# block is assembled once.
#
# The flow. The hot pass is cut into units: blocks that must stay together,
# because one falls through into the next (its last statement can continue,
# or is a BIT skip, EQUB &2C or &24) or branches into another (the blocks
# from the one to the other, as a branch's reach is short). In the source's
# order, each unit goes into the container the flow has reached if it fits
# there, and the flow moves on to the next container when it does not (so
# each container holds its units in the source's order, and the containers
# follow each other in it); a unit with an ACCCON X block goes into bank 4
# whatever the flow has reached. The hot data (elite-data.asm's untagged
# blocks) flows the same way, through HAZEL from &C000 (to &DF00) and then
# bank 4, after the hot code. The sizes are measured, not estimated: the
# measure copies are assembled once (elite-measure.asm, whose symbols give
# each FLOW_<n> and DFLOW_<n>), and a block's size does not depend on where
# it goes (no block aligns itself; a stub at its place is the same size in
# every container). 3-assembled-output/flow.txt lists the containers and their units.
#
# Each pass is the original in its order, and every call from one side to
# the other goes through a stub of its own, in the glue area (main RAM below
# &3000), which this script writes (3-assembled-output/elite-stubs.asm, INCLUDEd by
# elite-stubs.asm). The hot side is the low and hot passes, the cold side
# the cold pass. The hot side calls a cold label X by its own name, which is
# X's stub; its body is X_C in the cold pass:
#
#   .TT22 JSR to7 : JSR TT22_C : JMP to4
#
# and the cold pass's calls and jumps to a hot label H are renamed to H's
# stub, x4_H (j4_H for a jump):
#
#   .x4_LL5 JSR to4 : JSR LL5 : JMP to7
#
# (for the targets that never return, NORETURN below, the stub jumps:
# .TT170 JSR to7 : JMP TT170_C). The cold pass calls the low pass's routines
# that need nothing of the hot side directly (direct_calls). A block that
# falls through into a routine of the other side falls into a JMP to that
# routine's stub, written at the routine's place in the falling block's pass
# (the copy of the nearest block before it that is not of the other side):
# the stub calls the routine, which returns to the falling routine's caller
# with the caller's bank back, which is what the fall-through did in the
# original.
#
# The data source, elite-data.asm, is the original's too, and is emitted
# the same way (3-assembled-output/elite-data-<copy>.asm): its blocks are hot data (no
# Area field: HAZEL, then bank 4, flowed as above: hot (HAZEL) and hot4
# (bank 4), and measure for the measure), "Area: cold" (the cold pass, after
# the cold code) or "Area: BDATA" (the dashboard image, which the Makefile
# assembles on its own as the BDATA file). A block without a name (the
# configuration, the file banners, the closing SAVE) goes with the next named
# block, and those after the last one with BDATA.
#
# Checks (exit status 1 on failure):
#   * every block's IF ... ENDIF nesting is balanced (a blanked block must not
#     take half of a conditional with it);
#   * a block whose code can fall through its end is followed, in the source,
#     by a block of the same pass (each pass is assembled in the source's
#     order, and a hot block's unit holds the block it falls into), or by a
#     block of the other side whose first statement is its entry label, so
#     that the falling block falls into that label's stub; any other
#     fall-through across passes (between the low and hot passes) is an
#     error;
#   * every stub's line is blank in its copy, and every target is defined in
#     elite-source.asm (a stub has a place only there);
#   * every unit fits a container, and the flow fits.
import json, re, sys

SRC = "1-source-files/main-sources/elite-source.asm"
OUT = "3-assembled-output/elite-source-%s.asm"
DATA = "1-source-files/main-sources/elite-data.asm"
DOUT = "3-assembled-output/elite-data-%s.asm"
MEASURE = "3-assembled-output/measure-symbols.txt"
STUBS = "3-assembled-output/elite-stubs.asm"
DIRECT = "3-assembled-output/direct.txt"
FLOWTXT = "3-assembled-output/flow.txt"
DTAGS = {"cold": "cold", "BDATA": "bdata"}
STAR = re.compile(r"^\\ \*{70,}\s*$")
AREA = re.compile(r"^\\       Area: (.*)$")
TAGS = {"cold": "cold", "low": "low", "hot, ACCCON X": "hotx"}
NOFALL = set("RTS RTI JMP BRA BRK".split())
BRANCH = set("BCC BCS BEQ BMI BNE BPL BRA BVC BVS".split())

# the hot pass's containers, in the flow's order: (copy, start, end); the
# starts of the first two come from the measure (the low pass's end, the
# quarter-square tables' end)
HOTX = "hot3"                              # (where an ACCCON X unit goes: bank 4)
HAZEL_START, HAZEL_END = 0xC000, 0xDF00    # (&DF00-&DFFF is the MOS's)


def code_part(line):
    out, q = "", False
    for ch in line:
        if ch == '"':
            q = not q
        if ch == "\\" and not q:
            break
        out += ch
    return out.strip()


def blocks(lines, tags=TAGS):
    """[(start, end, name, area)]: a block starts at a header (a line of
    stars followed by a lone backslash) or at a separator line of stars"""
    out = [[0, None, None, "run"]]
    inh = False
    for i, l in enumerate(lines):
        if STAR.match(l):
            if inh:
                inh = False
                if (i + 2 < len(lines) and lines[i + 1].rstrip() == "\\"
                        and lines[i + 2].startswith("\\       Name:")):
                    out.append([i, None, None, "run"])     # (a banner's closing line
                    inh = True                             # opens the next header)
            elif i + 1 < len(lines) and lines[i + 1].rstrip() == "\\":
                out.append([i, None, None, "run"])
                inh = True
            else:
                out.append([i, None, None, "run"])
        elif inh:
            if not l.startswith("\\"):
                sys.exit("%s:%d: a header that is not closed" % (SRC, i + 1))
            m = re.match(r"^\\       Name: (.*)$", l)
            if m:
                out[-1][2] = m.group(1).strip()
            m = AREA.match(l)
            if m:
                t = m.group(1).strip()
                if t not in tags:
                    sys.exit("%d: unknown area %r" % (i + 1, t))
                out[-1][3] = tags[t]
    for k, b in enumerate(out):
        b[1] = out[k + 1][0] if k + 1 < len(out) else len(lines)
    return [tuple(b) for b in out]


# the build options' flags (3-assembled-output/elite-build-options.asm, as the Makefile writes
# them for the game), for the checks' view of conditional assembly
FLAGS = {"_SNG47": True, "_COMPACT": False, "_MATCH_ORIGINAL_BINARIES": True,
         "_REMOVE_CHECKSUMS": True, "_MAX_COMMANDER": False, "Q%": False}


def active_lines(lines):
    """for each line, False if it is in a branch of IF ... ENDIF that the
    flags rule out (a condition on anything else counts as either way)"""
    out, stack = [], []          # stack: [this branch on, a branch taken, known]
    for l in lines:
        c = code_part(l)
        m = re.match(r"^(IF|ELIF|ELSE|ENDIF)\b\s*(.*)$", c, re.I)
        on = all(st[0] for st in stack)
        if not m:
            out.append(on)
            continue
        kw, cond = m.group(1).upper(), m.group(2).strip()
        v = FLAGS.get(cond.replace("NOT(", "").rstrip(")")) if cond else None
        if v is not None and cond.startswith("NOT("):
            v = not v
        if kw == "IF":
            stack.append([True if v is None else v, bool(v), v is not None])
        elif kw in ("ELIF", "ELSE") and stack:
            st = stack[-1]
            if not st[2]:
                st[0] = True
            elif kw == "ELSE":
                st[0] = not st[1]
            else:
                st[0] = (not st[1]) and (True if v is None else v)
                st[1] = st[1] or st[0]
                st[2] = st[2] and v is not None
        elif kw == "ENDIF" and stack:
            stack.pop()
        out.append(False)
    return out


ACTIVE = []


def last_statement(lines, s, e):
    """the last statement of lines[s:e] that is assembled (None if none),
    passing over the lines of conditional assembly (IF, ELIF, ELSE, ENDIF)
    and the branches the build's flags rule out"""
    for i in range(e - 1, s - 1, -1):
        if ACTIVE and not ACTIVE[i]:
            continue
        c = code_part(lines[i])
        if c and not re.match(r"^(IF|ELIF|ELSE|ENDIF)\b", c, re.I):
            return c if c.upper().startswith("EQU") else c.split(" : ")[-1].strip()
    return None


def entry_label(lines, s, e, macros):
    """the label at the start of lines[s:e] (its first statement that is
    assembled), or None if the block starts with anything else"""
    for i in range(s, e):
        if ACTIVE and not ACTIVE[i]:
            continue
        c = code_part(lines[i])
        if not c or re.match(r"^(IF|ELIF|ELSE|ENDIF)\b", c, re.I) or not assembles(c, macros):
            continue
        m = re.match(r"^\.([A-Za-z_][A-Za-z0-9_]*)", c)
        return m.group(1) if m else None
    return None


def assembles(c, macros):
    """whether the statement c assembles bytes or moves the address (an
    instruction, data, a label, ORG ...), not just comments, PRINTs, SAVEs,
    ASSERTs or constants"""
    if not c or re.match(r"^(PRINT|SAVE|ASSERT|IF|ELIF|ELSE|ENDIF|MACRO|ENDMACRO|GUARD|CPU)\b", c, re.I):
        return False
    return not re.match(r"^[A-Za-z_][\w%]*\s*=", c)


def falls_through(stmt, macros):
    if stmt is None:
        return False
    w = stmt.split()
    if not w:
        return False
    op = w[0].upper()
    if w[0] in macros:
        return False                   # (a macro: the original's data macros)
    if re.match(r"^EQUB\s+&(2C|24)$", stmt.strip(), re.I):
        return True                    # (a BIT skip: the next instruction's
                                       # bytes are its operand, so it runs on)
    if op in NOFALL:
        return False
    if re.match(r"^(EQU[BWDS]|SKIP|INCBIN|FOR|NEXT|PRINT|SAVE|ASSERT|ORG|CLEAR|GUARD|MACRO|ENDMACRO|INCLUDE|CPU|COPYBLOCK|ALIGN)\b", op):
        return False                   # (data and directives: nothing to fall from)
    if re.match(r"^[A-Za-z_][\w%]*\s*=", stmt) or stmt.startswith("."):
        return False                   # (a constant, or a label alone)
    return True


# ---------------------------------------------------------------- the glue
#
# The source uses the original's names throughout. The cold copy is assembled
# with each cold label X renamed X_C (its definition and every reference in the
# cold copy), and with each JSR or JMP from cold code to a label of the low
# or hot pass (H) going through a stub, x4_H (call H with bank 4 paged in, then
# page the cold pass back) or, for the targets in NORETURN, j4_H (jump to H),
# but for the low routines it calls directly. Every other file keeps the names
# as they are, so a reference from outside the cold pass to a cold label X
# reaches its stub, .X. There is one stub for each cold label that a file
# outside the cold pass refers to, for each hot label that cold code calls or
# jumps to, and for each routine that a block of the other side falls into.
# Labels that are one place (defined one after another, with nothing
# assembled between them) share a stub. Labels ending in % keep their names
# (the cold pass's S% is the loader's entry point, by address). Cold code that
# needs a stub's address (a jump table: JMTB) names the stub itself, x4_H.
#
# NORETURN: the targets that never return to their caller, so that their
# stubs jump and leave no return into the stub on the stack.

NORETURN = {"BAY", "DEATH2", "TT170", "FRCE", "GOIN", "BEGIN"}
# the files outside elite-source.asm whose references to cold labels need
# stubs (everything else that elite-layout.asm assembles)
OTHERS = ("1-source-files/main-sources/elite-layout.asm", "1-source-files/main-sources/elite-measure.asm", "1-source-files/main-sources/elite-glue.asm",
          "1-source-files/main-sources/elite-qs.asm", "1-source-files/main-sources/elite-gfx.asm")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*%?")


def split_code(line):
    """(code, comment): the line up to its comment, and the comment"""
    q = False
    for k, ch in enumerate(line):
        if ch == '"':
            q = not q
        elif ch == "\\" and not q:
            return line[:k], line[k:]
    return line, ""


def tokens(code):
    """(start, end, name) of the identifiers in code, outside strings and
    character literals, and not hex (&), binary (%) or decimal digits"""
    out, k, n = [], 0, len(code)
    while k < n:
        ch = code[k]
        if ch == '"':
            k = code.find('"', k + 1)
            k = n if k < 0 else k + 1
        elif ch == "'" and k + 2 < n and code[k + 2] == "'":
            k += 3
        elif ch in "&%" or ch.isdigit():
            k += 1
            while k < n and (code[k].isalnum() or code[k] == "_"):
                k += 1
        else:
            m = IDENT.match(code, k)
            if m:
                out.append((m.start(), m.end(), m.group(0)))
                k = m.end()
            else:
                k += 1
    return out


def defined(lines):
    """[(name, line)] of the labels the lines define (.name)"""
    out = []
    for i, l in enumerate(lines):
        code = split_code(l)[0]
        for st in code.split(":"):
            m = re.match(r"^\s*\.([A-Za-z_][A-Za-z0-9_]*%?)", st)
            if m:
                out.append((m.group(1), i))
    return out


def aliases(lines, macros):
    """{label: first label of its place}: labels defined one after another
    with nothing assembled between them are one place"""
    out, cur = {}, None
    for i, l in enumerate(lines):
        code = split_code(l)[0].strip()
        if not code:
            continue
        m = re.match(r"^\.([A-Za-z_][A-Za-z0-9_]*%?)\s*(.*)$", code)
        if m:
            cur = cur or m.group(1)
            out[m.group(1)] = cur
            if m.group(2).strip():
                cur = None
        elif assembles(code, macros):
            cur = None
    return out


def statements(code):
    """the statements of a line's code (split at colons outside strings)"""
    out, q, last = [], False, 0
    for k, ch in enumerate(code):
        if ch == '"':
            q = not q
        elif ch == ":" and not q:
            out.append((last, code[last:k]))
            last = k + 1
    out.append((last, code[last:]))
    return out


def read_file(path, seen=None):
    """a source file's lines, with the files it INCLUDEs from 1-source-files/main-sources/"""
    seen = seen if seen is not None else set()
    if path in seen:
        return []
    seen.add(path)
    lines = open(path, encoding="latin-1").read().split("\n")
    out = [(path, lines)]
    for l in lines:
        m = re.match(r'^\s*INCLUDE\s+"(1-source-files/main-sources/[^"]+)"', split_code(l)[0])
        if m:
            out += read_file(m.group(1), seen)
    return out


def glue(copies, errors, lines, bl, eff, copy_of, falls, hotcopies):
    """the stubs between the passes (above), written into the copies; returns
    (stubs into the cold pass, stubs out of it)"""
    macros = set()
    for l in lines:
        m = re.match(r"^\s*MACRO\s+(\w+)", l)
        if m:
            macros.add(m.group(1))
    cold = {n for n, i in defined(copies["cold"]) if not n.endswith("%")}
    # the labels of the hot side (the low and hot passes), with the files
    # their blocks INCLUDE
    hotfiles = [(c, copies[c]) for c in hotcopies]
    for c in hotcopies:
        for l in copies[c]:
            m = re.match(r'^\s*INCLUDE\s+"(1-source-files/main-sources/[^"]+)"', split_code(l)[0])
            if m:
                hotfiles += read_file(m.group(1))
    hot = {}
    for f, ls in hotfiles:
        for n, i in defined(ls):
            hot.setdefault(n, f)
    for n in cold & set(hot):
        errors.append("%s: %s is defined in the cold pass and outside it" % (SRC, n))
    alias = {}
    for f, ls in hotfiles + [("cold", copies["cold"])]:
        alias.update(aliases(ls, macros))
    direct = direct_calls(lines, bl, eff, cold, hot)
    # the cold copy: X -> X_C, JSR/JMP H -> x4_H / j4_H
    out4 = []                               # (stub name, target) in order
    seen4 = {}
    cc = copies["cold"]
    act = active_lines(cc)
    for i, l in enumerate(cc):
        code, comment = split_code(l)
        if not code.strip():
            continue
        if not act[i]:                     # (a branch the build leaves out: the
            for a, b, name in reversed(tokens(code)):   # names, but no stubs)
                if name in cold:
                    code = code[:a] + name + "_C" + code[b:]
            m = re.match(r"^(\s*(?:JSR|JMP)\s+)([A-Za-z_]\w*)(.*)$", code, re.I)
            if m and m.group(2) in hot and m.group(2) not in cold and m.group(2) not in direct:
                code = m.group(1) + ("j4_" if m.group(2) in NORETURN else "x4_") + m.group(2) + m.group(3)
            cc[i] = code + comment
            continue
        new = ""
        pos = 0
        for off, st in statements(code):
            m = re.match(r"^(\s*)(JSR|JMP)(\s+)([A-Za-z_][A-Za-z0-9_]*%?)(.*)$", st, re.I)
            if m and m.group(4) in hot and m.group(4) not in cold and m.group(4) not in direct:
                h = m.group(4)
                if m.group(5).strip():
                    errors.append("%s:%d: %s %s%s from the cold pass: a stub can only call a label"
                                  % (SRC, i + 1, m.group(2), h, m.group(5)))
                place = alias.get(h, h)
                kind = "j4_" if place in NORETURN or h in NORETURN else "x4_"
                stub = kind + h
                if stub not in seen4:
                    seen4[stub] = place
                    out4.append((stub, h, place, kind))
                new += code[pos:off] + m.group(1) + m.group(2) + m.group(3) + stub + m.group(5)
                pos = off + len(st)
                continue
            for a, b, name in tokens(st):
                if name in cold:
                    new += code[pos:off + a] + name + "_C"
                    pos = off + b
                m2 = re.match(r"^(x4_|j4_)(.+)$", name)
                if m2 and m2.group(2) in hot and name not in seen4:
                    seen4[name] = alias.get(m2.group(2), m2.group(2))   # (a stub named in the
                    out4.append((name, m2.group(2), seen4[name], m2.group(1)))   # source: its address)
            new += code[pos:off + len(st)]
            pos = off + len(st)
        cc[i] = new + code[pos:] + comment
    # references to cold labels from outside the cold pass
    others = []
    for f in OTHERS:
        others += read_file(f)
    out7, seen7 = [], set()
    elsewhere = {n for f, ls in others for n, i in defined(ls)}
    for f, ls in [(c, copies[c]) for c in hotcopies + ["config"]] + others:
        own = {n for n, i in defined(ls)}
        for l in ls:                       # (loop variables and macro parameters)
            m = re.match(r"^\s*(FOR|MACRO)\s+(.*)$", split_code(l)[0], re.I)
            if m:
                own.update(IDENT.findall(m.group(2).split(",")[0] if m.group(1).upper() == "FOR"
                                         else m.group(2)))
        for i, l in enumerate(ls):
            for off, st in statements(split_code(l)[0]):
                for a, b, name in tokens(st):
                    if name not in cold or name in own:
                        continue
                    if name in elsewhere:  # (another file's label of the same name)
                        if f in hotcopies:
                            errors.append("%s:%d: %s is a cold label and a label of another file"
                                          % (SRC, i + 1, name))
                        continue
                    # a stub reaches the routine: a call or a jump to it, or its
                    # address (#LO/#HI, EQUW, a constant); anything else would
                    # read or write the stub's bytes, not the cold pass's
                    t = re.sub(r"^\s*(\.[A-Za-z_]\w*\s*)+", "", st).strip()
                    if not (re.match(r"^(JSR|JMP)\s+%s$" % re.escape(name), t, re.I)
                            or re.match(r"^[A-Z]{3}\s+#", t, re.I)
                            or re.match(r"^(EQU[BWD]|[A-Za-z_][\w%]*\s*=)", t, re.I)):
                        errors.append("%s:%d: %s refers to the cold label %s other than by a call, a "
                                      "jump or its address (%s): a stub has no data"
                                      % (f if not f in hotcopies + ["config"] else SRC, i + 1, f, name, t))
                        continue
                    if name not in seen7:
                        seen7.add(name)
                        out7.append(name)
    # the stubs that the fall-through seams land on: a block that falls
    # through its end into a block of the other side falls into the stub at
    # that block's entry label
    for side, entry in falls:
        if side == "hot":                  # (hot code falls into a cold routine)
            if entry not in seen7:
                seen7.add(entry)
                out7.append(entry)
        else:                              # (cold code falls into a hot routine)
            place = alias.get(entry, entry)
            kind = "j4_" if place in NORETURN or entry in NORETURN else "x4_"
            if kind + entry not in seen4:
                seen4[kind + entry] = place
                out4.append((kind + entry, entry, place, kind))
    # where each label is defined in the source (its first line that the
    # build's flags assemble), and its block
    barea = [None] * len(lines)
    for k, (s0, e0, name, area) in enumerate(bl):
        for i in range(s0, e0):
            barea[i] = k
    where = {}
    for n, i in defined(lines):
        if ACTIVE[i]:
            where.setdefault(n, i)

    def host(i):
        """the copy that holds the stubs at line i of a cold block: that of
        the nearest block before it, in the source, that is not cold and
        holds code, so that a block that falls through into the cold block
        falls into its stubs"""
        for k in range(barea[i] - 1, -1, -1):
            if eff[k] == "cold" or not ASM[k]:
                continue
            return copy_of[k]
        return "low"

    # the stubs (3-assembled-output/elite-stubs.asm, INCLUDEd in the glue area by
    # elite-stubs.asm): one per target, the labels of one place sharing it
    def grouped(items, side):
        """items: [(stub label, target label, jumps)] -> [(jumps, [stub
        labels], target)], one per place"""
        out, done = [], {}
        for stub, target, jumps in items:
            i = where.get(target)
            ok = ("cold",) if side == "cold" else ("low", "hot", "hotx")
            if i is None or eff[barea[i]] not in ok:
                errors.append("%s: no place in the source for the stub %s (%s is not defined "
                              "in elite-source.asm's %s blocks)" % (SRC, stub, target, side))
                continue
            key = (alias.get(target, target), jumps)
            if key not in done:
                done[key] = len(out)
                out.append((jumps, [], target))
            if stub not in out[done[key]][1]:
                out[done[key]][1].append(stub)
        return out

    s7 = grouped([(n, n, alias.get(n, n) in NORETURN or n in NORETURN) for n in out7], "cold")
    s4 = grouped([(stub, h, kind == "j4_") for stub, h, place, kind in out4], "hot")
    for kind in (s7, s4):
        seen = {}
        for jumps, labels, target in kind:
            for l in labels:
                if l in seen and seen[l] != jumps:
                    errors.append("%s: %s is called and jumped to through one stub" % (SRC, l))
                seen[l] = jumps
    text = ["\\ 3-assembled-output/elite-stubs.asm: the stubs between the passes, written by",
            "\\ 2-build-files/streams.py (elite-stubs.asm INCLUDEs it in the glue area)", "",
            "\\ into the cold pass (the hot side's calls of cold routines)", "", ".STUBS7"]
    for jumps, labels, target in s7:
        text += [".%s" % l for l in labels[:-1]]
        text.append(stub_text(labels[-1], target + "_C", "to7", "to4", jumps))
    text += [".STUBS7_END", "", "\\ out of the cold pass (the cold pass's calls of hot routines)", "", ".STUBS4"]
    for jumps, labels, target in s4:
        text += [".%s" % l for l in labels[:-1]]
        text.append(stub_text(labels[-1], target, "to4", "to7", jumps))
    text += [".STUBS4_END", ""]
    with open(STUBS, "w") as f:
        f.write("\n".join(text))
    # the fall-through seams: a block that falls through its end into a
    # routine of the other side falls into a jump to that routine's stub (or,
    # for a low routine the cold pass calls directly, to the routine)
    for side_, entry in falls:
        i = where.get(entry)
        if side_ == "hot":
            a, to = host(i), entry
        else:
            a, to = "cold", entry if entry in direct else \
                ("j4_" if alias.get(entry, entry) in NORETURN or entry in NORETURN else "x4_") + entry
        if code_part(copies[a][i]):
            errors.append("%s:%d: the seam into %s: its line is not blank in the %s copy" % (SRC, i + 1, entry, a))
        else:
            copies[a][i] = " JMP %s                \\ (the fall-through into %s, on the other side)" % (to, entry)
    return len(s7), len(s4), direct


# INLINE: the stubs that are written out in full rather than through the
# shared to7 and to4 (the busiest; each costs 17 bytes more and saves 15
# cycles a call)
INLINE = set()


def stub_text(label, target, enter, leave, jumps):
    """a stub, one statement a line (so that the tools that read the source
    a line at a time see each instruction's own operand): page the target's
    bank in (A and the flags kept), call the target, page the caller's bank
    back (A and the flags kept), return; or, for a target that never
    returns, page its bank in and jump"""
    bank = {"to7": "COLDBANK", "to4": "HOMEBANK"}
    page = lambda b: [" PHP", " PHA", " LDA #%s" % b, " STA &F4", " STA VIA+&30", " PLA", " PLP"]
    if jumps:
        body = page(bank[enter]) if label in INLINE else [" JSR %s" % enter]
        return "\n".join([".%s" % label] + body + [" JMP %s" % target])
    if label in INLINE:
        body = page(bank[enter]) + [" JSR %s" % target] + page(bank[leave]) + [" RTS"]
    else:
        body = [" JSR %s" % enter, " JSR %s" % target, " JMP %s" % leave]
    return "\n".join([".%s" % label] + body)


GLUEOK = ("1-source-files/main-sources/gfx-gluehooks.asm", "1-source-files/main-sources/gfx-gvars.asm")
KEEPBANK = {"TTX66M"}                      # (elite-stubs.asm's stub that keeps
                                           # the caller's bank, for CHPR)


def direct_calls(lines, bl, eff, cold, hot):
    """the low pass's labels that the cold pass may call or jump to directly,
    with no stub: those of the low blocks that, with every low block they
    call, jump or branch to or fall into, refer to nothing of the hot or cold
    pass and to no glue code but the text hooks and the shared variables
    (GLUEOK, which keep whatever bank is paged), so that they run the same
    with the cold pass paged in"""
    lab = {}
    for k, (s, e, name, area) in enumerate(bl):
        for n, i in defined(lines[s:e]):
            if ACTIVE[s + i]:
                lab.setdefault(n, k)
    glue = {}
    for f, ls in read_file("1-source-files/main-sources/elite-glue.asm"):
        for n, i in defined(ls):
            glue.setdefault(n, f)
    low = [k for k in range(len(bl)) if eff[k] == "low" and ASM[k]]
    bad, edges = set(), {k: set() for k in low}
    for k in low:
        s, e, name, area = bl[k]
        own = {n for n, i in defined(lines[s:e])}
        for i in range(s, e):
            if not ACTIVE[i]:
                continue
            for off, st in statements(split_code(lines[i])[0]):
                st = re.sub(r"^\s*(\.[A-Za-z_]\w*\s*)+", "", st)
                m = re.match(r"^([A-Za-z]{3})\b", st.strip())
                op = m.group(1).upper() if m else ""
                for a, b, t in tokens(st):
                    if t in own or (m and t.upper() == op):
                        continue
                    k2 = lab.get(t)
                    if k2 is not None and eff[k2] == "low":
                        if op in ("JSR", "JMP") or op in BRANCH:
                            edges[k].add(k2)
                    elif k2 is not None and eff[k2] in ("hot", "hotx", "cold"):
                        bad.add(k)
                    elif t in cold:
                        bad.add(k)
                    elif t in glue and glue[t] not in GLUEOK and t not in KEEPBANK:
                        bad.add(k)
        st = last_statement(lines, s, e)
        if falls_through(st, set()):
            nxt = [k2 for k2 in range(k + 1, len(bl)) if ASM[k2]]
            if nxt and eff[nxt[0]] == "low":
                edges[k].add(nxt[0])
    changed = True
    while changed:
        changed = False
        for k in low:
            if k not in bad and edges[k] & bad:
                bad.add(k)
                changed = True
    out = set()
    for k in low:
        if k not in bad:
            s, e, name, area = bl[k]
            out.update(n for n, i in defined(lines[s:e]) if ACTIVE[s + i])
    return out


def measured():
    """the measure's symbols (3-assembled-output/measure-symbols.txt, beebasm -d of
    elite-measure.asm)"""
    sy = {}
    for m in re.finditer(r"'([^']+)':(\d+)", open(MEASURE).read()):
        sy.setdefault(m.group(1), int(m.group(2)))
    return sy


def data(errors, phase, sy=None):
    """the data source's copies: bdata, cold, and the hot data, measure (with a
    label DFLOW_<n> at each named block) or flowed (hot: HAZEL, hot4: bank 4);
    returns (the copies, the bytes the hot data puts in bank 4, the flow's
    report lines)"""
    lines = open(DATA, encoding="latin-1").read().split("\n")
    bl = []
    for s, e, name, area in blocks(lines, DTAGS):
        bl.append([s, e, name, ("hot" if area == "run" else area) if name else None])
    nxt = "bdata"
    for b in reversed(bl):                 # (unnamed blocks: the next named one's)
        if b[3] is None:
            b[3] = nxt
        else:
            nxt = b[3]
    for s, e, name, area in bl:
        depth = 0
        for i in range(s, e):
            c = code_part(lines[i]).upper()
            depth += bool(re.match(r"^IF\b", c)) - bool(re.match(r"^ENDIF\b", c))
        if depth:
            errors.append("%s:%d: %s: IF ... ENDIF not balanced in an area's block" % (DATA, s + 1, name))
    hot = [k for k, b in enumerate(bl) if b[3] == "hot" and b[2]]
    copy = {}
    report, b4 = [], 0
    if phase == "measure":
        for k, b in enumerate(bl):
            copy[k] = "measure" if b[3] == "hot" else b[3]
    else:
        # the flow: HAZEL from &C000 while each block fits, then bank 4
        at, cur = HAZEL_START, "hot"
        for n, k in enumerate(hot):
            nk = sy["DFLOW_%d" % hot[n + 1]] if n + 1 < len(hot) else sy["DFLOW_END"]
            size = nk - sy["DFLOW_%d" % k]
            if cur == "hot" and at + size > HAZEL_END:
                report.append("  HAZEL &%04X-&%04X, %d free; bank 4 after the hot code from %s"
                              % (HAZEL_START, at - 1, HAZEL_END - at, bl[k][2]))
                cur = "hot4"
            if cur == "hot":
                at += size
            else:
                b4 += size
            copy[k] = cur
        if cur == "hot":
            report.append("  HAZEL &%04X-&%04X, %d free; nothing in bank 4" % (HAZEL_START, at - 1, HAZEL_END - at))
        last = "hot"
        for k in range(len(bl) - 1, -1, -1):   # (unnamed blocks: the next named one's copy)
            if bl[k][3] == "hot":
                if bl[k][2]:
                    last = copy[k]
                else:
                    copy[k] = last
            else:
                copy[k] = bl[k][3]
    names = ("bdata", "cold") + (("measure",) if phase == "measure" else ("hot", "hot4"))
    out = {a: [] for a in names}
    for k, (s, e, name, area) in enumerate(bl):
        for a in names:
            out[a] += [lines[i] if copy[k] == a else "" for i in range(s, e)]
        if phase == "measure" and area == "hot" and name:
            out["measure"][s] = ".DFLOW_%d" % k
    for a in names:
        with open(DOUT % a, "w", encoding="latin-1") as f:
            f.write("\n".join(out[a]))
    return {a: sum(1 for k, b in enumerate(bl) if copy[k] == a and b[2]) for a in names}, b4, report


ASM = []


def main():
    phase = sys.argv[1] if len(sys.argv) > 1 else "place"
    if phase not in ("measure", "place"):
        sys.exit("usage: streams.py measure|place")
    lines = open(SRC, encoding="latin-1").read().split("\n")
    bl = blocks(lines)
    ACTIVE[:] = active_lines(lines)
    macros = set(m.group(1) for m in (re.match(r"^\s*MACRO\s+(\w+)", l) for l in lines) if m)
    errors = []
    for s, e, name, area in bl:
        depth = 0
        for i in range(s, e):
            c = code_part(lines[i]).upper()
            if re.match(r"^IF\b", c):
                depth += 1
            elif re.match(r"^ENDIF\b", c):
                depth -= 1
        if depth:
            errors.append("%s:%d: %s: IF ... ENDIF not balanced in a block" % (SRC, s + 1, name))
    # each block's pass: the configuration before the head, then its tag; a
    # block that assembles nothing goes with the block before it
    ASM[:] = [any(ACTIVE[i] and assembles(code_part(lines[i]), macros) for i in range(s, e))
              for s, e, name, area in bl]
    first = min(k for k, b in enumerate(bl) if b[3] == "low")
    eff = []
    for k, (s, e, name, area) in enumerate(bl):
        if k < first:
            eff.append("config")
        elif not ASM[k]:
            eff.append(eff[-1])
        else:
            eff.append({"run": "hot", "hotx": "hotx", "low": "low", "cold": "cold"}[area])
    side = lambda p: "cold" if p == "cold" else "hot"
    pas = lambda p: "hot" if p == "hotx" else p
    # the hot pass's blocks that assemble, in the source's order, and its units
    hot = [k for k in range(len(bl)) if eff[k] in ("hot", "hotx") and ASM[k]]
    pos = {k: n for n, k in enumerate(hot)}
    parent = list(range(len(hot)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def join(a, b):
        for x in range(min(a, b), max(a, b)):      # (a unit is a run of blocks)
            ra, rb = find(x), find(x + 1)
            if ra != rb:
                parent[max(ra, rb)] = min(ra, rb)
    # fall-through: each block that can fall through its end must be followed,
    # in the source, by a block of its own pass that holds code (in the hot
    # pass, the same unit), or by a block of the other side whose first
    # statement is its entry label, as that label's stub is then the next
    # thing in the falling block's pass
    falls = []
    for k, (s, e, name, area) in enumerate(bl):
        if eff[k] == "config" or not ASM[k]:
            continue
        st = last_statement(lines, s, e)
        if not falls_through(st, macros):
            continue
        for k2 in range(k + 1, len(bl)):
            s2, e2, name2, area2 = bl[k2]
            if not ASM[k2]:
                continue               # (comments, PRINTs and constants only)
            if any(re.match(r"^(ORG|CLEAR|SKIPTO)\b", code_part(lines[i]), re.I) for i in range(s2, e2)):
                errors.append("%s:%d: %s (%s) can fall through its end (%s) into %s, which moves the address"
                              % (SRC, e, name, eff[k], st, name2))
            elif pas(eff[k2]) == pas(eff[k]):
                if pas(eff[k]) == "hot":
                    join(pos[k], pos[k2])
            elif side(eff[k2]) != side(eff[k]):
                entry = entry_label(lines, s2, e2, macros)
                if entry:
                    falls.append((side(eff[k]), entry))
                else:
                    errors.append("%s:%d: %s (%s) can fall through its end (%s) into %s (%s), whose "
                                  "first statement is not its entry label" % (SRC, e, name, eff[k], st, name2, eff[k2]))
            else:
                errors.append("%s:%d: %s (%s) can fall through its end (%s) into %s (%s), another pass"
                              % (SRC, e, name, eff[k], st, name2, eff[k2]))
            break
    # branches: a hot block that branches into another keeps the blocks from
    # the one to the other in one unit (a branch reaches only 128 bytes)
    blockof = {}
    for k, (s, e, name, area) in enumerate(bl):
        for n, i in defined(lines[s:e]):
            if ACTIVE[s + i]:
                blockof.setdefault(n, k)
    for k in hot:
        s, e, name, area = bl[k]
        for i in range(s, e):
            if not ACTIVE[i]:
                continue
            for off, st in statements(split_code(lines[i])[0]):
                m = re.match(r"^\s*(?:\.[A-Za-z_]\w*\s+)*([A-Za-z]{3})\s+([A-Za-z_]\w*)(?![\w%])", st)
                if not m or m.group(1).upper() not in BRANCH:
                    continue
                k3 = blockof.get(m.group(2))
                if k3 is None or k3 == k:
                    continue
                if k3 in pos:
                    join(pos[k], pos[k3])
                else:
                    errors.append("%s:%d: %s branches to %s in another pass (%s)"
                                  % (SRC, i + 1, name, m.group(2), eff[k3]))
    # a block that starts by aligning itself (ALIGN n: the log tables) is
    # measured without the measure's padding and placed at the next multiple
    # of n, the padding counted in its container
    align = {}
    for k in hot:
        s, e, name, area = bl[k]
        for i in range(s, e):
            c = code_part(lines[i])
            if ACTIVE[i] and assembles(c, macros):
                m = re.match(r"^ALIGN\s+&([0-9A-F]+)$", c, re.I)
                if m:
                    align[k] = int(m.group(1), 16)
                break
    units = []                             # [first, last] positions in hot
    for n in range(len(hot)):
        if n and find(n) == find(n - 1):
            units[-1][1] = n
        else:
            units.append([n, n])
    # each block's copy
    copy_of = {}
    report = []
    if phase == "measure":
        for k in range(len(bl)):
            copy_of[k] = "measure" if eff[k] in ("hot", "hotx") else eff[k]
        dn, b4, drep = data(errors, phase)
    else:
        sy = measured()
        dn, b4, drep = data(errors, phase, sy)
        addr = [sy["FLOW_%d" % k] for k in hot] + [sy["FLOW_END"]]
        bsize = []                         # each block's size, less any measure padding
        for n, k in enumerate(hot):
            pad = (-addr[n]) % align[k] if k in align else 0
            bsize.append(addr[n + 1] - addr[n] - pad)

        def fit(at, u0, u1):
            """where the unit u0..u1 ends if it starts at at"""
            for n in range(u0, u1 + 1):
                if hot[n] in align:
                    at += (-at) % align[hot[n]]
                at += bsize[n]
            return at
        conts = [["hot1", sy["LOW_END%"], 0x4000, []], ["hot2", sy["QS_RUN%"], 0x8000, []],
                 ["hot3", 0x8000, 0xC000 - b4, []]]
        used = {c[0]: 0 for c in conts}
        cur = 0
        for u0, u1 in units:
            xu = any(eff[hot[n]] == "hotx" for n in range(u0, u1 + 1))
            names = "%s..%s" % (bl[hot[u0]][2], bl[hot[u1]][2]) if u1 > u0 else bl[hot[u0]][2]
            if xu:
                c = [c for c in conts if c[0] == HOTX][0]
                if fit(c[1] + used[c[0]], u0, u1) > c[2]:
                    errors.append("the ACCCON X unit %s does not fit in %s" % (names, c[0]))
            else:
                while cur < len(conts) and fit(conts[cur][1] + used[conts[cur][0]], u0, u1) > conts[cur][2]:
                    cur += 1
                if cur == len(conts):
                    errors.append("the hot pass does not fit: %s has no room" % names)
                    break
                c = conts[cur]
            size = fit(c[1] + used[c[0]], u0, u1) - (c[1] + used[c[0]])
            c[3].append((used[c[0]], size, names, xu))
            used[c[0]] += size
            for n in range(u0, u1 + 1):
                copy_of[hot[n]] = c[0]
        for k in range(len(bl)):
            if k not in copy_of:
                if eff[k] in ("hot", "hotx"):  # (a block that assembles nothing:
                    copy_of[k] = copy_of.get(k - 1, "hot1")   # the one before it's)
                else:
                    copy_of[k] = eff[k]
        for name, a, b, us in conts:
            report.append("%s &%04X-&%04X: %d units, %d bytes, %d free" % (name, a, b - 1, len(us), used[name],
                                                                          b - a - used[name]))
            for off, size, names, xu in us:
                report.append("  &%04X %5d %s%s" % (a + off, size, names, " (ACCCON X)" if xu else ""))
        report.append("hot data:")
        report += drep
    copies = {}
    allc = ["config", "low", "cold"] + (["measure"] if phase == "measure" else ["hot1", "hot2", "hot3"])
    for a in allc:
        copies[a] = []
        for k, (s, e, name, area) in enumerate(bl):
            copies[a] += [lines[i] if copy_of[k] == a else "" for i in range(s, e)]
    if phase == "measure":
        for k in hot:
            copies["measure"][bl[k][0]] = ".FLOW_%d" % k
    nstubs = glue(copies, errors, lines, bl, eff, copy_of, falls,
                  ["low"] + (["measure"] if phase == "measure" else ["hot1", "hot2", "hot3"]))
    with open(DIRECT, "w") as f:           # (for bankcheck.py: what the cold pass calls directly)
        f.write("".join("%s\n" % n for n in sorted(nstubs[2])))
    for a in allc:
        with open(OUT % a, "w", encoding="latin-1") as f:
            f.write("\n".join(copies[a]))
    if phase == "place":
        with open(FLOWTXT, "w") as f:
            f.write("\n".join(report) + "\n")
    for e in errors:
        print("streams:", e)
    n = {p: sum(1 for k in range(len(bl)) if eff[k] == p and ASM[k]) for p in ("low", "hot", "hotx", "cold")}
    print("streams (%s): %d blocks (low %d, hot %d with %d ACCCON X, cold %d), %d hot units, stubs %d into "
          "the cold pass, %d out of it; data %s%s"
          % (phase, len(bl), n["low"], n["hot"] + n["hotx"], n["hotx"], n["cold"], len(units),
             nstubs[0], nstubs[1], ", ".join("%s %d" % kv for kv in dn.items()),
             ", %d error(s)" % len(errors) if errors else ""))
    if phase == "place":
        for l in report:
            if not l.startswith("  &"):
                print("streams:", l.strip())
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
