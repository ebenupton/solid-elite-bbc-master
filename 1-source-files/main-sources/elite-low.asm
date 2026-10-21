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
\   * DOSCLI's stash of the filing system's lasting bytes in HAZEL (DFSST),
\     which the loader fills and DOSCLI, in the cold area, uses around each
\     disc command (docs/master-memory.md).
\
\ ******************************************************************************

 INCLUDE "3-assembled-output/elite-source-low.asm"   \ the blocks tagged low

 INCLUDE "1-source-files/main-sources/elite-far.asm"            \ far calls to and from the cold area

.DFSST  SKIP 128        \ DFS's and the MOS's lasting bytes in HAZEL, &C2C0-&C2FF
                        \ and &DFC0-&DFFF (the MOS's FSCV copy at &DFDA-&DFDB, the
                        \ ACCCON its error path puts back at &DFDC-&DFDD), while
                        \ the game uses those places: put back for each disc
                        \ command (DOSCLI; the loader takes them first)

.DFSIN  SKIP 1          \ bit 7: a disc command is under way (DOSCLI, DOSNMI)

 ASSERT DFSIN = DFSST + 128      \ (the loader clears it)
