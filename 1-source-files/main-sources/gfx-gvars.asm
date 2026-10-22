\ ******************************************************************************
\
\ gfx-gvars.asm - the variables shared between Elite, the IRQ handler and the
\ graphics bank, with their initial values (in the low area, main RAM below
\ &3000: elite-low.asm)
\
\ ******************************************************************************

\ Variables shared between Elite, the IRQ handler and the graphics bank

.GMODE   EQUB 0         \ bit 7 set: space mode (double buffered)
.GFRONT  EQUB 1         \ buffer displayed: 0 = main RAM (A), 1 = shadow (B, and
                        \ Master's direct-mode screen)
.GFLIP   EQUB 0         \ non-zero: show buffer GPEND at the next vsync
.GPEND   EQUB 0
.GDRAWON EQUB &FF       \ 0: drawing primitives are erasing, ignore them
.GFORCE  EQUB 0         \ non-zero: draw directly even though QQ11 = 0
.GSIGHT  EQUB 0         \ non-zero: draw the laser sights
.GLASV   EQUB 0         \ non-zero: our laser beams are showing
.GLCOL   EQUB 3         \ colour index for recorded lines
.GDCOL   EQUB 4         \ colour index for recorded dots
.GNF     EQUB 0         \ faces / vertices of the ship being recorded
.GNV     EQUB 0
.GTYPE   EQUB 0         \ the type whose faces the ship being recorded uses
.GSUNON  EQUB 0         \ non-zero: SUN drew the sun this frame (LSO, SUNX valid)
.GSUNR   EQUB 0         \ the sun's radius this frame
.GSTASH  EQUB 0         \ bit 7: a disc command has stashed HAZEL in buffer 0
                        \ (DOSCLI), which the next space-mode frame clears
.PM_OK   EQUB 0         \ bit 7: PM_HOOK has computed this frame's beach ball
                        \ constants (H_CIRC clears it)
.PM_R    EQUB 0         \ the planet's radius this frame (H_CIRC; PM_HOOK)
.PS_VALID EQUB 0        \ bit 7: the disc layer's arrays hold the beach ball's
                        \ rows for PM_HOOK's last constants (T_MERID sets it,
                        \ H_CIRC clears it for a crater planet)
.GWARP   EQUB 0         \ bit 7: TT66 is an in-system jump's (WARP sets it,
                        \ F_DIRECT clears it)

\ Kept solid rows (gfx-raster_kept.asm), shared by the frame layer, the
\ rasteriser's windows and the trampolines
.KMODE   EQUB 0         \ bit 7: K mode this frame (the station close by)
.KBIT    EQUB 1         \ this frame's buffer's bit in KF (1 or 2)
.KBITN   EQUB &FE       \ and its complement
.KPLO    EQUB &FF       \ the pending rows: KPLO..KPHI
.KPHI    EQUB 0
.KREC    EQUB 0         \ kept rows found pending this frame (r7_rowrep)
.KON     EQUB 0         \ K mode frames in a row (to 3)
.KSKIP   EQUB 0         \ frames K mode sits out (T_KFRAME)
                        \ (KF, per row: bit b, kept in buffer b; bit 7,
                        \ pending: in HAZEL, elite-layout.asm)
