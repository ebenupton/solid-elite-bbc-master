\ ******************************************************************************
\
\ elite-gfx.asm - the filled renderer's memory: its shared workspace in main
\ RAM, its glue in HAZEL, banks 5 and 6 and ANDY, and the meridian window in
\ bank 7
\ (docs/memory-map.md)
\
\ INCLUDEd at the end of elite-source.asm (after the game's code, so that the
\ layer can use Elite's symbols). From the Demonstration Disc port (tag
\ demo-final, src/gfx-build.asm), with the memory laid out for the full
\ game. The state that more than one bank, the IRQ handler or code running
\ with ACCCON X set reads is in main RAM below &3000 (the shared workspace,
\ below the main code), which every bank sees whatever ACCCON X is; so is
\ the glue (the cross-bank trampolines and hooks, the shared variables with
\ initial values), in the main code's low area (elite-low.asm), as the IRQ
\ and text hooks run during disc commands too. HAZEL holds the game data
\ (the ship blueprints, elite-data.asm: elite-layout.asm). Produces:
\
\   build/BANK5.bin  sideways RAM bank 5: the rasteriser's shared region and
\                    disc window (gfx-raster.asm, gfx-flare.asm,
\                    gfx-raster_lcold.asm; gfx-raster_disc.asm)
\   build/RASTA.bin  ANDY: the rasteriser's polygon window (gfx-raster_poly.asm,
\                    gfx-raster_line.asm)
\   build/BANK6.bin  sideways RAM bank 6: the frame layer (gfx-frame.asm),
\                    the ship faces and colours (gfx-faces.asm) and its state
\   build/MERID.bin  sideways RAM bank 7 after the cold area: the meridian
\                    window, the beach ball planet's boundaries (gfx-merid.asm)
\
\ ******************************************************************************

ACCY = 8                \ ACCCON bit Y: HAZEL at &C000-&DFFF
MAXSH = 13              \ ships per frame
MAXLN = 48              \ lines per frame
MAXDT = 64              \ dots per frame
RASTBANK = 5            \ the rasteriser: bank 5, its disc window (&8000-&8FFF) and
RASTPOLY = &85          \ the shared region (&9000-&BFFF); ANDY over bank 5, its
                        \ polygon window
GFXBANK = 6
MERIDBANK = 7           \ the meridian window (gfx-merid.asm): bank 7, after the
                        \ cold area
MERIDHOLD = 0           \ a beach ball's orientation is taken one frame in
                        \ MERIDHOLD + 1 (gfx-merid.asm, PM_HOOK): its spin (1/16
                        \ radian an iteration) shows in steps; its position and
                        \ size follow every frame (0: as the demo port)
ELITEBANK = HOMEBANK

NDSTAR = NOST+1         \ stars 1..NOSTM (Master port: NOSTM <= NOST = 20)

\ The shared workspace: the state that the rasteriser's two banks, the frame
\ layer, the game's hooks and the IRQ handler share, in one block in main
\ RAM from &0E00 (above page &0D, off limits, docs/master-memory.md) to the
\ main code (CODE%), below &3000, where all of them see it. Variables only
\ (the renderer initialises them: R_INIT, F_INIT), except DFSST and DFSST2,
\ which the loader fills (from &0400, as the loader itself is here). Each
\ array's page crossings are as they were measured, or fewer: raster_vars
\ at a fixed place, moved only by whole pages (the rows of the laser sights'
\ scan in R_DIRTYR0/1 must not cross a page, gfx-frame.asm's f_sight2),
\ R_NDISCL page aligned (gfx-raster_scr.asm), the other row arrays from a
\ low byte of &40 or less or whole in a page (KF, R_WR), the star arrays
\ whole in a page. The polygon edge tables share the new disc spans' places
\ (R_PTA = R_NDISCR, R_PTB = R_NDISCL: gfx-raster_scr.asm)

ORG &0E00               \ (from here to WS_END: test_raster.py assembles it too)
.WS_START
.R_NDN      SKIP 192        \ (raster_vars.asm: boundaries per disc row, 0..4)
INCLUDE "1-source-files/main-sources/gfx-raster_scr.asm"   \ the vertices (&0EC0), R_NDISCL (&0F00) ...
.R_SS       SKIP NDSTAR     \ star size 1..3 (raster_vars.asm: the stars)
.R_SX       SKIP NDSTAR
.DFSIN      SKIP 1          \ bit 7: a disc command is under way (DOSCLI, DOSNMI)
ASSERT HI(R_SS) = HI(R_SX + NDSTAR - 1)
ASSERT P% <= &1000
ORG &1000
.R_WL       SKIP 192        \ this frame's written extents (empty: R=0)
.DFSST  SKIP 64         \ DFS's and the MOS's lasting bytes in HAZEL, &C2C0-&C2FF
                        \ (here) and &DFC0-&DFFF (DFSST2: the MOS's FSCV copy
                        \ at &DFDA-&DFDB, the ACCCON its error path puts back at
                        \ &DFDC-&DFDD), while the game uses those places: put
                        \ back for each disc command (DOSCLI; the loader takes
                        \ them first)
.R_SY       SKIP NDSTAR
RVOFF = &182            \ R_DIRTYR0's offset in raster_vars (asserted below)
RVBASE = &12B5 - RVOFF  \ (&14B5 when it was measured: two pages lower)
ASSERT P% <= RVBASE
SKIP RVBASE - P%
INCLUDE "1-source-files/main-sources/gfx-raster_vars.asm"
ASSERT R_DIRTYR0 = RVBASE + RVOFF
R_PTA = R_NDISCR        \ the polygon edge tables (gfx-raster_scr.asm)
R_PTB = R_NDISCL
ASSERT LO(R_PTA) <> LO(R_PTB) AND LO(R_PTA) + 191 < 256   \ (k_pre tells them apart)
.R_SN       SKIP 1          \ star count 0..NDSTAR
.R_SCOL     SKIP 1          \ star colour byte (R_INIT: &FF)
ALIGN &100
.KF         SKIP 192        \ the kept solid rows (gfx-raster_kept.asm), per row:
                            \ bit b set if the row is kept in buffer b, bit 7 if
                            \ it is pending this frame (R_INIT clears it)
.DFSST2 SKIP 64         \ (DFSST's second half: &DFC0-&DFFF)
.R_WR       SKIP 192        \ (raster_vars.asm; whole in a page)
.F_DSS      SKIP NDSTAR     \ the directly drawn stars' sizes (bank 6's: 0 = none,
                            \ cleared with R_SS by F_INIT and f_direct0)
ASSERT HI(F_DSS) = HI(F_DSS + NDSTAR - 1)
.WS_GAP                     \ (free to the main code)
SKIP CODE% - P%
.WS_END
PRINT "Shared workspace: ", ~WS_START, "-", ~WS_GAP-1, " (free ", &1000-DFSIN-1, ", ", RVBASE-R_SY-NDSTAR, ", ", KF-R_SCOL-1, " and ", CODE%-WS_GAP, " to the main code at ", ~CODE%, ")"
ASSERT WS_END = CODE%   \ (one block, ending where the main code starts)
ASSERT HI(KF) = HI(KF + 191)    \ (KF,Y: no page crossing)
ASSERT HI(R_WR) = HI(R_WR + 191)

CLEAR &8000, &C000      \ bank 5: the shared region from &9000 (the per-x tables,
ORG &9000               \ the row runs, the boundary arrays, the stars, the lens
INCLUDE "1-source-files/main-sources/gfx-raster.asm"   \ flare ...), then the disc window at &8000
INCLUDE "1-source-files/main-sources/gfx-flare.asm"    \ the lens flare (its step in bank 6: gfx-flare6.asm)
INCLUDE "1-source-files/main-sources/gfx-raster_lcold.asm"   \ R_LINE's cold part
.B5_END
ASSERT B5_END <= &C000
ORG &8000
INCLUDE "1-source-files/main-sources/gfx-raster_disc.asm"
INCLUDE "1-source-files/main-sources/gfx-raster_kept.asm"   \ kept solid rows: bank 5's part

.B5LO_END
ASSERT B5LO_END <= &9000
PRINT "Bank 5: rasteriser: disc window &8000-", ~B5LO_END-1, " (free ", &9000-B5LO_END, "), shared &9000-", ~B5_END-1, " free ", &C000-B5_END, " (+ ", r_tables-r_tfree, " at ", ~r_tfree, ")"
SAVE "3-assembled-output/BANK5.bin", &8000, B5_END, &8000

CLEAR COLD_END%, &C000  \ bank 7 after the cold area (ROMSEL MERIDBANK): the
ORG COLD_END%           \ meridian window, the beach ball planet's boundaries
.MERID_START
INCLUDE "1-source-files/main-sources/gfx-merid.asm"
INCLUDE "1-source-files/main-sources/gfx-kept7.asm"    \ kept solid rows: the polygons' part (docs/renderer.md)
.MERID_END
ASSERT MERID_END <= &C000
PRINT "Bank 7: meridian window ", ~MERID_START, "-", ~MERID_END-1, ", bank 7 free ", &C000-MERID_END
SAVE "3-assembled-output/MERID.bin", MERID_START, MERID_END, MERID_START

CLEAR &8000, &9000      \ ANDY (ROMSEL &85): the rasteriser's polygon window
ORG &8000
INCLUDE "1-source-files/main-sources/gfx-raster_poly.asm"
INCLUDE "1-source-files/main-sources/gfx-raster_line.asm"   \ R_LINE
.RA_END
ASSERT RA_END <= &9000
PRINT "ANDY: rasteriser polygon window &8000-", ~RA_END-1, " free ", &9000-RA_END
SAVE "3-assembled-output/RASTA.bin", &8000, RA_END, &8000

CLEAR &8000, &C000
ORG &8000
INCLUDE "1-source-files/main-sources/gfx-frame.asm"
INCLUDE "1-source-files/main-sources/gfx-faces.asm"
INCLUDE "1-source-files/main-sources/gfx-light6.asm"   \ the lighting tables (and the first ramps)
INCLUDE "1-source-files/main-sources/gfx-light.asm"    \ the lighting's L_SUN and L_REC
INCLUDE "1-source-files/main-sources/gfx-frame_cold.asm"
INCLUDE "1-source-files/main-sources/gfx-flare6.asm"   \ the lens flare's step (the flare: gfx-flare.asm, bank 5)
INCLUDE "1-source-files/main-sources/gfx-hangar.asm"   \ the hangar's frame (HALL; its tables are in HAZEL)
.B6_CODE_END
.F_HW   SKIP 256        \ planet half-widths
.F_HW2  SKIP 256        \ sun half-widths
.F_DL                   \ ship records: XX2 then XX3 copies (1536 bytes)
 SKIP &22
 INCLUDE "1-source-files/main-sources/gfx-finit.asm"   \ F_INIT, run once before the first frame
 SKIP F_DL + 1536 - P%
.F_DLEND
.F_TM   SKIP 768        \ text map: desired characters, 24 rows of 32
.F_ST   SKIP 768        \ what each buffer shows in each cell (gfx-frame.asm)
ASSERT F_ST = F_TM + &300
.F_TMR  SKIP 24         \ non-empty cells per row
.F_SHR0 SKIP 24
.F_SHR1 SKIP 24
.F_DSX  SKIP NDSTAR     \ the stars drawn directly (gfx-frame_cold.asm's F_DSTAR,
.F_DSY  SKIP NDSTAR     \ f_unstar): x and y (their sizes, F_DSS, in the shared
                        \ workspace)
 INCLUDE "1-source-files/main-sources/gfx-hangar6.asm"   \ the hangar's tables (f_hback; data
                        \ before them stays at its place)
.B6_END
PRINT "Bank 6: frame layer &8000-", ~B6_CODE_END-1, ", data ", ~F_HW, "-", ~B6_END-1, " free ", &C000-B6_END
ASSERT B6_END <= &C000
SAVE "3-assembled-output/BANK6.bin", &8000, B6_END, &8000
