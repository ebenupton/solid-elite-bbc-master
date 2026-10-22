\ ******************************************************************************
\
\ elite-low.asm - the low area, first in the main code, in main RAM below
\ the head (docs/memory-map.md)
\
\ Port: INCLUDEd by elite-source.asm at CODE%, before the head (VEC to UP),
\ which the run follows. All of it is below &3000 (asserted after UP), so it
\ is visible whatever is paged at &8000-&BFFF and whatever ACCCON X is; what
\ is here up to LOW_END% must be, as the IRQ handler, the MOS vectors
\ (entered with any ROM paged) and code that runs with ACCCON X set use it:
\
\   * the blocks of elite-source.asm tagged low (build/elite-source-low.asm,
\     which 2-build-files/streams.py writes): stackpt and NEWBRK, which the MOS enters
\     through BRKV with the ROM that raised the error paged in, and whose
\     original place is later in the run (in bank 4);
\
\   * the far calls between Elite's home bank and the cold area
\     (elite-far.asm), which page the banks;
\
\   * the renderer's glue: the variables that the game, the IRQ handler and
\     the renderer's banks share, with their initial values (gfx-gvars.asm),
\     the trampolines from the frame layer into the rasteriser
\     (gfx-tramp.asm), the hooks that CHPR (WRCHV: any ROM paged, ACCCON X
\     set) and IRQ1 call (gfx-lowhooks.asm); then, after LOW_END%, needing
\     only game context (ACCCON X clear) but outside the banks they page,
\     the G_ stubs that page the frame layer in (gfx-gstubs.asm) and the
\     hooks in Elite's drawing code (gfx-hooks.asm).
\
\ ******************************************************************************

 INCLUDE "3-assembled-output/elite-source-low.asm"   \ the blocks tagged low

 INCLUDE "1-source-files/main-sources/elite-far.asm"            \ far calls to and from the cold area

 INCLUDE "1-source-files/main-sources/gfx-gvars.asm"            \ the renderer's glue: shared variables,
 INCLUDE "1-source-files/main-sources/gfx-tramp.asm"            \ the trampolines into the rasteriser,
 INCLUDE "1-source-files/main-sources/gfx-lowhooks.asm"         \ the text map's and the IRQ's hooks

.LOW_END%                               \ (the part used with ACCCON X set ends)

 INCLUDE "1-source-files/main-sources/gfx-gstubs.asm"           \ the stubs that page the frame layer in
 INCLUDE "1-source-files/main-sources/gfx-hooks.asm"            \ the hooks in Elite's drawing code
