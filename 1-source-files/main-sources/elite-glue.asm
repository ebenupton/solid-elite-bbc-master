\ ******************************************************************************
\
\ elite-glue.asm - the glue area, first in the main code, in main RAM below
\ the low pass (docs/memory-map.md)
\
\ Port: INCLUDEd by elite-layout.asm at CODE%, before the low pass (Elite's
\ code that must be below &3000: WSCAN, the sound, IRQ1, CHPR and its font,
\ UP, stackpt and NEWBRK). All of it is below &3000 (asserted after the low pass), so it is
\ visible whatever is paged at &8000-&BFFF and whatever ACCCON X is (the IRQ
\ handler, the MOS vectors, entered with any ROM paged, and code that runs
\ with ACCCON X set use much of it). It holds the port's own code only:
\
\   * the stubs between the hot side and the cold pass (elite-stubs.asm,
\     with 3-assembled-output/elite-stubs.asm, which 2-build-files/streams.py writes), one per
\     target, which page the banks;
\
\   * the renderer's glue: the variables that the game, the IRQ handler and
\     the renderer's banks share, with their initial values (gfx-gvars.asm),
\     the trampolines from the frame layer into the rasteriser
\     (gfx-tramp.asm), the hooks that CHPR (WRCHV: any ROM paged, ACCCON X
\     set) and IRQ1 call (gfx-gluehooks.asm), the G_ stubs that page the
\     frame layer in (gfx-gstubs.asm) and the hooks in Elite's drawing code
\     (gfx-hooks.asm).
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-stubs.asm"          \ the stubs to and from the cold pass

 INCLUDE "1-source-files/main-sources/gfx-gvars.asm"            \ the renderer's glue: shared variables,
 INCLUDE "1-source-files/main-sources/gfx-tramp.asm"            \ the trampolines into the rasteriser,
 INCLUDE "1-source-files/main-sources/gfx-gluehooks.asm"         \ the text map's and the IRQ's hooks


 INCLUDE "1-source-files/main-sources/gfx-gstubs.asm"           \ the stubs that page the frame layer in
 INCLUDE "1-source-files/main-sources/gfx-hooks.asm"            \ the hooks in Elite's drawing code
