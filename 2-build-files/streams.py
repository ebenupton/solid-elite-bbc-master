#!/usr/bin/env python3
# streams.py: split the main source into its emissions (docs/memory-map.md,
# "The source and its emissions"). Run by the Makefile from the repository's root.
#
# src/elite-source.asm is the original's main source in the original's order.
# Each of its routines and tables sits once, at its original place, and the
# area it lives in is a field of its header:
#
#   \       Name: TT219
#   ...
#   \       Area: cold
#
# No Area field: the main code's run (main RAM from the head, after the low
# area at CODE%, then bank 4 where main RAM ends). "Area: low": main RAM below
# &3000, first in the low area, before the head (what the MOS enters with any
# ROM paged, but whose original place is later in the run). "Area: bank 4": bank 4, after the run (code that runs
# with ACCCON X set, which hides main RAM at &3000-&7FFF, and the tables it
# reads). "Area: cold": the cold area, sideways RAM bank 7. A block runs from its
# header to the next header (or to a separator line of stars, which starts an
# untagged block: the original's PRINT and SAVE sections).
#
# BeebAsm assembles a file once and has one location counter, and banks 4
# and 7 share the addresses &8000-&BFFF, so each area's blocks are assembled
# from a copy of the source of their own: build/elite-source-<area>.asm is
# elite-source.asm with every line outside that area's blocks blanked (so
# that line numbers stay the source's). src/elite-layout.asm INCLUDEs the
# copies one after the other (run, bank4, cold), each at its own address, and
# the run INCLUDEs the low copy at the end of its head, so every label is
# defined exactly once and every block is assembled once.
#
# Each emission is the original in its order, with a stub wherever a routine
# lives on the other side. The hot side is the run, the low area and bank 4;
# the cold side the cold area. In a hot copy, the line that defines a cold
# label X that the hot side refers to holds X's stub, under X's own name:
#
#   .TT22 JSR far7 : EQUW TT22_C        (TT22_C: the body, in the cold copy)
#
# and in the cold copy, the line that defines a hot label H that cold code
# calls or jumps to holds H's stub, under the name the cold copy's calls are
# renamed to:
#
#   .x4_TT26 JSR far4 : EQUW TT26
#
# (far7j and j4_ / far4j for the targets that never return, NORETURN below).
# A cold block's stubs go in the copy of the hot area of the nearest block
# before it that is not cold (the run's for the low area), so the stubs sit
# where the routine was carved out of that emission, and a block that falls
# through into a routine of the other side falls into its stub: the stub
# calls the body and returns to the falling routine's caller with the
# caller's bank back, which is what the fall-through did in the original (a
# jump stub, for a target that never returns, just jumps).
#
# The data source, src/elite-data.asm, is the original's too, and is emitted
# the same way (build/elite-data-<area>.asm): its blocks are hot data (no
# Area field: HAZEL, which elite-layout.asm fills from &C000 in the source's
# order), "Area: cold" (the cold area, after the cold code) or "Area: BDATA"
# (the dashboard image, which the Makefile assembles on its own as the BDATA
# file). A block without a name (the configuration, the file banners, the
# closing SAVE) goes with the next named block, and those after the last one
# with BDATA. The hot and cold copies are assembled in elite-layout.asm's
# pass, so the configuration they use is elite-source.asm's.
#
# Checks (exit status 1 on failure):
#   * every block's IF ... ENDIF nesting is balanced (a blanked block must not
#     take half of a conditional with it);
#   * a block whose code can fall through its end is followed, in the source,
#     by a block of the same area (each area is assembled in the source's
#     order, so a block falls into the next block of its own area), or by a
#     block of the other side whose first statement is its entry label, so
#     that the falling block falls into that label's stub (run or bank 4 into
#     cold, cold into run, low or bank 4); any other fall-through across areas
#     (between the run, the low area and bank 4, or from the low area into
#     the cold area) is an error;
#   * every stub's line is blank in its copy, and every target is defined in
#     elite-source.asm (a stub has a place only there).
import os, re, sys

SRC = "1-source-files/main-sources/elite-source.asm"
OUT = "3-assembled-output/elite-source-%s.asm"
AREAS = ("run", "low", "bank4", "cold")
DATA = "1-source-files/main-sources/elite-data.asm"
DOUT = "3-assembled-output/elite-data-%s.asm"
DAREAS = ("bdata", "hot", "cold")
DTAGS = {"cold": "cold", "BDATA": "bdata"}
STAR = re.compile(r"^\\ \*{70,}\s*$")
AREA = re.compile(r"^\\       Area: (.*)$")
TAGS = {"cold": "cold", "bank 4": "bank4", "low": "low"}
NOFALL = set("RTS RTI JMP BRA BRK".split())


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


# the build options' flags (build/elite-build-options.asm, as the Makefile writes
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
# cold copy), and with each JSR or JMP from cold code to a label of the run,
# the low area or bank 4 (H) going through a stub, x4_H (JSR far4: call H with
# bank 4 paged in, then page the cold area back) or, for the targets in
# NORETURN, j4_H (JSR far4j: jump to H). Every other file keeps the names as
# they are, so a reference from outside the cold area to a cold label X
# reaches its stub, .X (JSR far7 : EQUW X_C, or far7j for the targets in
# NORETURN). Each stub is at its target's place in the other side's copy
# (above); there is one for each cold label that a file outside the cold area
# refers to and for each hot label that cold code calls or jumps to, and one
# for each routine that a block of the other side falls into. Labels that are
# one place (defined one after another, with nothing assembled between them)
# share a stub: the earlier ones are bare labels at their lines. Labels ending
# in % keep their names (the cold area's S% is the loader's entry point, by
# address). Cold code that needs a stub's address (a jump table: JMTB) names
# the stub itself, x4_H.
#
# NORETURN: the targets that never return to their caller, so that their
# stubs jump (far7j, far4j) and leave no far-call frame on the stack.

NORETURN = {"BAY", "DEATH2", "TT170", "FRCE", "GOIN", "BEGIN"}
# the files outside elite-source.asm whose references to cold labels need
# stubs (everything else that elite-layout.asm assembles)
OTHERS = ("1-source-files/main-sources/elite-layout.asm", "1-source-files/main-sources/elite-low.asm",
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


def glue(copies, errors, lines, bl, falls):
    macros = set()
    for l in copies["run"]:
        m = re.match(r"^\s*MACRO\s+(\w+)", l)
        if m:
            macros.add(m.group(1))
    cold = {n for n, i in defined(copies["cold"]) if not n.endswith("%")}
    # the labels of the run, the low area and bank 4, with the files the hot
    # blocks INCLUDE
    hotfiles = [("run", copies["run"]), ("low", copies["low"]), ("bank4", copies["bank4"])]
    for a in ("run", "low", "bank4"):
        for l in copies[a]:
            m = re.match(r'^\s*INCLUDE\s+"(1-source-files/main-sources/[^"]+)"', split_code(l)[0])
            if m:
                hotfiles += read_file(m.group(1))
    hot = {}
    for f, ls in hotfiles:
        for n, i in defined(ls):
            hot.setdefault(n, f)
    for n in cold & set(hot):
        errors.append("%s: %s is defined in the cold area and outside it" % (SRC, n))
    alias = {}
    for f, ls in hotfiles + [("cold", copies["cold"])]:
        alias.update(aliases(ls, macros))
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
            if m and m.group(2) in hot and m.group(2) not in cold:
                code = m.group(1) + ("j4_" if m.group(2) in NORETURN else "x4_") + m.group(2) + m.group(3)
            cc[i] = code + comment
            continue
        new = ""
        pos = 0
        for off, st in statements(code):
            m = re.match(r"^(\s*)(JSR|JMP)(\s+)([A-Za-z_][A-Za-z0-9_]*%?)(.*)$", st, re.I)
            if m and m.group(4) in hot and m.group(4) not in cold:
                h = m.group(4)
                if m.group(5).strip():
                    errors.append("%s:%d: %s %s%s from the cold area: a stub can only call a label"
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
    # references to cold labels from outside the cold area
    others = []
    for f in OTHERS:
        if os.path.exists(f):
            others += read_file(f)
    out7, seen7 = [], set()
    elsewhere = {n for f, ls in others for n, i in defined(ls)}
    for f, ls in [("run", copies["run"]), ("low", copies["low"]), ("bank4", copies["bank4"])] + others:
        own = {n for n, i in defined(ls)}
        for l in ls:                       # (loop variables and macro parameters)
            m = re.match(r"^\s*(FOR|MACRO)\s+(.*)$", split_code(l)[0], re.I)
            if m:
                own.update(IDENT.findall(m.group(2).split(",")[0] if m.group(1).upper() == "FOR"
                                         else m.group(2)))
        for i, l in enumerate(ls):
            for a, b, name in tokens(split_code(l)[0]):
                if name not in cold or name in own:
                    continue
                if name in elsewhere:      # (another file's label of the same name)
                    if f in ("run", "low", "bank4"):
                        errors.append("%s:%d: %s is a cold label and a label of another file"
                                      % (SRC, i + 1, name))
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
    # build's flags assemble), and the area of that line's block
    barea = [None] * len(lines)
    for k, (s0, e0, name, area) in enumerate(bl):
        for i in range(s0, e0):
            barea[i] = k
    where = {}
    for n, i in defined(lines):
        if ACTIVE[i]:
            where.setdefault(n, i)
    macros_ = macros

    def host(i):
        """the hot area whose emission holds the stubs at line i of a cold
        block: that of the nearest block before it, in the source, that is not
        cold and holds code (the low area's blocks: the run's), so that a block
        that falls through into the cold block falls into its stubs"""
        for k in range(barea[i] - 1, -1, -1):
            s0, e0, name, area = bl[k]
            if area == "cold":
                continue
            if any(ACTIVE[j] and assembles(code_part(lines[j]), macros_) for j in range(s0, e0)):
                return "run" if area == "low" else area
        return "run"

    def place_stubs(groups, ok_area, side):
        """groups: [(far helper, [(stub label, target label)])], each group one
        place; each stub goes at the line of its target's definition, in the
        copy of the area that hosts it, and the labels of a place share the
        stub at the last of them"""
        n = 0
        for far, members in groups:
            at = []
            for stub, target in members:
                i = where.get(target)
                if i is None or bl[barea[i]][3] not in ok_area:
                    errors.append("%s: no place in the source for the stub %s (%s is not defined "
                                  "in elite-source.asm's %s blocks)" % (SRC, stub, target, side))
                    continue
                at.append((i, stub, target))
            at.sort()
            for k, (i, stub, target) in enumerate(at):
                a = host(i) if side == "cold" else "cold"
                text = ".%s" % stub
                # (a label shares the next one's stub only if nothing is
                # assembled between them in this copy)
                if k == len(at) - 1 or any(assembles(code_part(copies[a][j]), macros_)
                                           for j in range(i + 1, at[k + 1][0])):
                    text += " JSR %s : EQUW %s" % (far, target + "_C" if side == "cold" else target)
                    n += 1
                cur = copies[a][i]
                if (a, i) in placed:
                    copies[a][i] = cur + " : " + text      # (two stubs at one line)
                elif code_part(cur):
                    errors.append("%s:%d: the stub %s's line is not blank in the %s copy"
                                  % (SRC, i + 1, stub, a))
                else:
                    copies[a][i] = text
                    placed.add((a, i))
        return n

    placed = set()

    # the stubs into the cold area, in the hot copies at the cold labels' places
    groups, done = [], {}
    for name in out7:
        place = alias.get(name, name)
        far = "far7j" if place in NORETURN or name in NORETURN else "far7"
        if place not in done:
            done[place] = len(groups)
            groups.append((far, []))
        elif groups[done[place]][0] != far:
            errors.append("%s: %s and %s are one place but not both NORETURN" % (SRC, name, place))
        groups[done[place]][1].append((name, name))
    n7 = place_stubs(groups, ("cold",), "cold")
    # the stubs out of the cold area, in the cold copy at the hot labels' places
    groups, done = [], {}
    for stub, h, place, kind in out4:
        key = (kind, place)
        if key not in done:
            done[key] = len(groups)
            groups.append(("far4j" if kind == "j4_" else "far4", []))
        groups[done[key]][1].append((stub, h))
    n4 = place_stubs(groups, ("run", "low", "bank4"), "hot")
    return n7, n4


def data(errors):
    """the data source's copies, one per area (DAREAS)"""
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
    for a in DAREAS:
        out = []
        for s, e, name, area in bl:
            out += [lines[i] if area == a else "" for i in range(s, e)]
        with open(DOUT % a, "w", encoding="latin-1") as f:
            f.write("\n".join(out))
    return {a: sum(1 for b in bl if b[3] == a and b[2]) for a in DAREAS}


def main():
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
        if depth and area != "run":
            errors.append("%s:%d: %s: IF ... ENDIF not balanced in an area's block" % (SRC, s + 1, name))
    # fall-through: each block that can fall through its end must be followed,
    # in the source, by a block of its own area that holds code, or by a block
    # of the other side (hot: the run or bank 4; cold) whose first statement is
    # its entry label, as that label's stub is then the next thing in the
    # falling block's emission
    falls = []
    for k, (s, e, name, area) in enumerate(bl):
        st = last_statement(lines, s, e)
        if not falls_through(st, macros):
            continue
        for s2, e2, name2, area2 in bl[k + 1:]:
            if not any(ACTIVE[i] and assembles(code_part(lines[i]), macros) for i in range(s2, e2)):
                continue               # (comments, PRINTs and constants only)
            if any(re.match(r"^(ORG|CLEAR|SKIPTO)\b", code_part(lines[i]), re.I) for i in range(s2, e2)):
                errors.append("%s:%d: %s (%s) can fall through its end (%s) into %s, which moves the address"
                              % (SRC, e, name, area, st, name2))
            elif area2 != area:
                entry = entry_label(lines, s2, e2, macros)
                side = "hot" if area in ("run", "bank4") and area2 == "cold" else \
                       "cold" if area == "cold" else None
                if side and entry:
                    falls.append((side, entry))
                else:
                    errors.append("%s:%d: %s (%s) can fall through its end (%s) into %s (%s)%s"
                                  % (SRC, e, name, area, st, name2, area2,
                                     "" if side else ", and no stub of %s is in %s's emission" % (name2, area)))
            break
    copies = {}
    for a in AREAS:
        copies[a] = []
        for s, e, name, area in bl:
            copies[a] += [lines[i] if area == a else "" for i in range(s, e)]
    nstubs = glue(copies, errors, lines, bl, falls)
    nd = data(errors)
    for a in AREAS:
        with open(OUT % a, "w", encoding="latin-1") as f:
            f.write("\n".join(copies[a]))
    n = {a: sum(1 for b in bl if b[3] == a) for a in AREAS}
    for e in errors:
        print("streams:", e)
    print("streams: %d blocks (%s), stubs %d into the cold area, %d out of it; data %s%s"
          % (len(bl), ", ".join("%s %d" % (a, n[a]) for a in AREAS), nstubs[0], nstubs[1],
             ", ".join("%s %d" % (a, nd[a]) for a in DAREAS),
             ", %d error(s)" % len(errors) if errors else ""))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
