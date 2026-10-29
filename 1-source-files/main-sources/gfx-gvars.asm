\ ******************************************************************************
\
\ gfx-gvars.asm - the variables shared between Elite, the IRQ handler and the
\ graphics bank, with their initial values (in the glue area, main RAM below
\ &3000: elite-glue.asm)
\
\ ******************************************************************************

\ Variables shared between Elite, the IRQ handler and the graphics bank

.GMODE   EQUB 0         \ bit 7 set: space mode (double buffered)
.GFRONT  EQUB 1         \ buffer displayed: 0 = main RAM (A), 1 = shadow (B, and
                        \ Master's direct-mode screen)
.GFLIP   EQUB 0         \ non-zero: show buffer GPEND at the next vsync
.GPEND   EQUB 0
.GVLAST  EQUB 0         \ non-zero: the last vsync flipped (H_VSYNC: 25 fps cap)
.GPX     EQUB 0         \ ACCCON X (4) as the frame had it before running game
                        \ code with X clear (T_GAME; F_PDOT)
.GPCT    EQUB 0         \ the clip window's top, R_CT, while the frame runs
                        \ game code (T_GAME; FMLTU writes P: F_PDOT)
.GPRJ    EQUB 0         \ bit 7: the frame is running game code (T_GAME)
.GFORCE  EQUB 0         \ non-zero: draw directly even though QQ11 = 0
.GSIGHT  EQUB 0         \ non-zero: draw the laser sights
.GLASV   EQUB 0         \ non-zero: our laser beams are showing
.GNF     EQUB 0         \ faces of the ship being recorded
.GTYPE   EQUB 0         \ the type whose faces the ship being recorded uses
.GSUNON  EQUB 0         \ non-zero: SUN drew the sun this frame (LSO, SUNX valid)
.GSUNR   EQUB 0         \ the sun's radius this frame
.LLT     EQUB 24, 24, &E8 \ the light towards the sun, x, y, z (* 41.3): L_SUN
                        \ (bank 4) writes it, L_REC (bank 6) reads it
                        \ (gfx-light.asm); the fixed light until L_SUN first
                        \ runs
.GSTASH  EQUB 0         \ bit 7: a disc command has stashed HAZEL in buffer 0
                        \ (DOSCLI), which the next space-mode frame clears
.PF_CLS  EQUB 0         \ the planet's class (bits 0-1: 0 meridian, the beach
                        \ ball, 1 craters, 2 bands), bit 7: its surface detail
                        \ this frame (PF_HOOK, gfx-planet7.asm; T_CAPS runs
                        \ gfx-merid.asm's PC_ROWS)
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
                        \ pending: in the shared workspace, elite-gfx.asm)
