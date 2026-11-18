#!/usr/bin/env python3
"""sunref.py: the patch to the reference, the released SNG47, that the
harness writes at TT170 so that the original runs the same game logic as
this build. Run by the Makefile; writes 3-assembled-output/sunref.json, which
6-harness/mlib.mjs's loadRefPatch reads (mcompare.mjs and agentplay give it to
the reference when it is beside the candidate's symbols). A patch is:

  code    [[address, [bytes]]]: assembled code, in SNG47's unused memory FREE
  sites   [{name, addr, orig, new}]: SNG47's bytes at each changed site and
          what they become, each the same length (the harness checks orig
          at TT170 before it writes anything); a site with no label of its
          own has no addr but search: [from, to], a routine's extent, in
          which the harness finds orig exactly once
  lso     the space station's line heap, if the patch moves it (the harness
          maps it to LSO's address in the compared state), else null
  region  [address, length, name]: more game state of the patched original,
          compared as such, or null

The site table is empty: SNG47 runs as released.

The build prints the patch (into 3-assembled-output/compile.txt) and fails unless every
byte it writes is in FREE or at one of its sites, no two sites overlap, no
site is in FREE, and every site keeps its length."""
import json, sys

FREE = (0x0B00, 0x0D00)                    # SNG47's unused &0B00-&0CFF
OUT = "3-assembled-output/sunref.json"


def audit(p):
    bad = []
    for a, b in p["code"]:
        if a < FREE[0] or a + len(b) > FREE[1]:
            bad.append("code at &%04X-&%04X is outside &%04X-&%04X" % (a, a + len(b) - 1, FREE[0], FREE[1] - 1))
    spans = sorted((s["addr"], s["addr"] + len(s["new"]), s["name"]) for s in p["sites"] if s["addr"] is not None)
    for (a0, e0, n0), (a1, e1, n1) in zip(spans, spans[1:]):
        if a1 < e0:
            bad.append("sites %s and %s overlap" % (n0, n1))
    spans += [(s["search"][0], s["search"][1], s["name"]) for s in p["sites"] if s["addr"] is None]
    for a, e, n in spans:
        if e > FREE[0] and a < FREE[1]:
            bad.append("site %s is in the free area" % n)
    for s in p["sites"]:
        if len(s["orig"]) != len(s["new"]):
            bad.append("site %s changes its length" % s["name"])
    n = sum(len(b) for a, b in p["code"])
    print("sunref: %s: %d bytes of code, %d sites" % (p["name"], n, len(p["sites"])))
    for b in bad:
        print("sunref: AUDIT FAIL: " + b)
    return not bad


def main():
    p = {"name": "none", "code": [], "sites": [], "lso": None, "region": None}
    if not audit(p):
        sys.exit(1)
    with open(OUT, "w") as f:
        json.dump(p, f)


main()
