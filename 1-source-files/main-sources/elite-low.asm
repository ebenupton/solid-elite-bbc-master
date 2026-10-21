\ ******************************************************************************
\
\ elite-low.asm - the low area, at the end of the main code's head, in main
\ RAM below &3000 (docs/memory-map.md)
\
\ Port: INCLUDEd by elite-source.asm after UP, before HEAD_END%. What is here
\ is visible whatever is paged at &8000-&BFFF and whatever ACCCON X is, so
\ the IRQ handler, the MOS vectors (entered with any ROM paged) and code that
\ runs with ACCCON X set can use it:
\
\   * the blocks of elite-source.asm tagged low (build/elite-source-low.asm,
\     which 2-build-files/streams.py writes): stackpt and NEWBRK, which the MOS enters
\     through BRKV with the ROM that raised the error paged in, and whose
\     original place is later in the run (in bank 4);
\
\   * the far calls between Elite's home bank and the cold area
\     (elite-far.asm), which page the banks;
\
\   * the renderer's shared variables with their initial values
\     (gfx-gvars.asm), which the game, the IRQ handler and the renderer's
\     banks share.
\
\ ******************************************************************************

 INCLUDE "3-assembled-output/elite-source-low.asm"   \ the blocks tagged low

 INCLUDE "1-source-files/main-sources/elite-far.asm"            \ far calls to and from the cold area

 INCLUDE "1-source-files/main-sources/gfx-gvars.asm"            \ the renderer's shared variables
