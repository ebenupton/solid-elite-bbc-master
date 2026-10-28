#!/usr/bin/env python3
#
# ******************************************************************************
#
# BBC MASTER ELITE: THE LIGHTING'S TWO PASSES
#
# Run by the Makefile from the repository's root, before the game is
# assembled. gfx-light.asm (1-source-files/main-sources) is one file with two
# halves, its IF LIGHTPASS = 4 and IF LIGHTPASS = 6 blocks: L_SUN, which runs
# in game context at bank 4's end (elite-layout.asm and elite-measure.asm
# assemble it), and L_REC, in the frame layer in bank 6 (elite-gfx.asm). This
# writes a copy for each pass, 3-assembled-output/gfx-light-4.asm and
# gfx-light-6.asm, with the other half assembled out (IF FALSE) and the
# source's line numbers
#
# ******************************************************************************

import re

SRC = "1-source-files/main-sources/gfx-light.asm"
OUT = "3-assembled-output/gfx-light-%d.asm"

text = open(SRC, encoding="latin-1").read()
for p in (4, 6):
    t = re.sub(r"^IF LIGHTPASS = %d " % p, "IF TRUE  ", text, flags=re.M)
    t = re.sub(r"^IF LIGHTPASS = [0-9] ", "IF FALSE  ", t, flags=re.M)
    with open(OUT % p, "w", encoding="latin-1", newline="") as f:
        f.write(t)
