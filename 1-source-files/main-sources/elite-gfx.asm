\ ******************************************************************************
\
\ elite-gfx.asm - the filled renderer's memory: its shared workspace in main
\ RAM (its glue is in the main code's glue area, elite-glue.asm), banks 5 and 6
\ and ANDY, and the meridian window in bank 7
\ (docs/memory-map.md)
\
\ INCLUDEd at the end of elite-layout.asm (after the game's code, so that the
\ layer can use Elite's symbols). From the Demonstration Disc port (tag
\ demo-final, src/gfx-build.asm), with the memory laid out for the full
\ game. The state that more than one bank, the IRQ handler or code running
\ with ACCCON X set reads is in main RAM below &3000 (the shared workspace,
\ below the main code), which every bank sees whatever ACCCON X is; so is
\ the glue (the cross-bank trampolines and hooks, the shared variables with
\ initial values), in the main code's glue area (elite-glue.asm), as the IRQ
\ and text hooks run during disc commands too. HAZEL holds the game data
\ (the ship blueprints, elite-data.asm: elite-layout.asm). Produces:
\
\   BANK5.bin  sideways RAM bank 5: the rasteriser's shared region and
\              disc window (gfx-raster.asm, gfx-raster_lcold.asm;
\              gfx-raster_disc.asm, gfx-raster_kept.asm)
\   RASTA.bin  ANDY: the rasteriser's polygon window (gfx-raster_poly.asm,
\              gfx-raster_line.asm)
\   BANK6.bin  sideways RAM bank 6: the frame layer (gfx-frame.asm),
\              the ship faces and colours (gfx-faces.asm), the lighting,
\              the flare's step and the hangar, its state, then the
\              hangar's tables (gfx-hangar6.asm)
\   MERID.bin  sideways RAM bank 7 after the cold pass: the meridian
\              window: the beach ball planet's boundaries (gfx-merid.asm),
\              the kept solid rows' polygon part (gfx-kept7.asm) and the
\              lens flare (gfx-flare.asm)
\
\ (all in 3-assembled-output)
\
\ ******************************************************************************

ACCY = 8                \ ACCCON bit Y: HAZEL at &C000-&DFFF
MAXSH = NOSH            \ ships per frame: LL9 records a ship at most once an
                        \ iteration, and only the ships in the NOSH slots
                        \ (the planet and the sun are not recorded)
MAXLN = MAXSH           \ lines per frame: the enemy beams, one per ship
                        \ recorded (H_EE31; the bomb's bolt is F_BX/F_BY)
MAXDT = 64              \ dots per frame
RASTBANK = 5            \ the rasteriser: bank 5, its disc window (&8000-&8FFF) and
RASTPOLY = &85          \ the shared region (&9000-&BFFF); ANDY over bank 5, its
                        \ polygon window
GFXBANK = 6
MERIDBANK = 7           \ the meridian window (gfx-merid.asm): bank 7, after the
                        \ cold area
ELITEBANK = HOMEBANK
R_S2L0 = &9A00          \ the second disc's spans as each buffer last drew them
R_S2L1 = &9B00          \ (gfx-raster_disc2.asm), in bank 5, where R_DISC2 runs:
R_S2R0 = &8F40          \ left ends in the room below the per-x tables, right
R_S2R1 = &BF40          \ ends after the disc window and after R_DISC2 (empty:
                        \ 255, 0); each array whole in a page, a buffer's and
                        \ the other's at the same low byte (R_SETBUF patches
                        \ the high bytes)

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
.R_S2T      SKIP 2          \ the second disc's rows in each buffer as drawn
.R_S2B      SKIP 2          \ (none: 255, 0) and its colour (R_COLE): R_DISC2,
.R_S2C      SKIP 2          \ gfx-raster_disc2.asm (f_disc2 reads the rows)
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
.ss_pl      SKIP 9          \ S_SUN's ss_dif: the planet's and the sun's
.ss_su      SKIP 9          \ coordinates (INWK's, sign-magnitude; gfx-ssun.asm)
.ss_zs      SKIP 37         \ S_SUN's: the zero page kept round MV40 and SOLAR
.WS_KGAP                    \ (gfx-ssun.asm: NI% <= 37)
ALIGN &100
.KF         SKIP 192        \ the kept solid rows (gfx-raster_kept.asm), per row:
                            \ bit b set if the row is kept in buffer b, bit 7 if
                            \ it is pending this frame (R_INIT clears it)
.DFSST2 SKIP 64         \ (DFSST's second half: &DFC0-&DFFF)
.R_WR       SKIP 192        \ (raster_vars.asm; whole in a page)
.F_DSS      SKIP NDSTAR     \ the directly drawn stars' sizes (bank 6's: 0 = none,
                            \ cleared with R_SS by F_INIT and f_direct0)
ASSERT HI(F_DSS) = HI(F_DSS + NDSTAR - 1)
.GFAR       SKIP 1          \ non-zero: LL9 has shown a face of the ship it is
                            \ drawing without testing its normal (S_SHIP)
.GHAND      SKIP 1          \ the ship's handedness (SHAND): %01000000 as ZINF's,
                            \ %01100000 as TIDY's (L_REC, f_winding)
.GSPLV      SKIP 4          \ part 5's XX2 for the splinter's faces (SPLV)
.GSHT       SKIP 4          \ SHAND's workspace
INCLUDE "1-source-files/main-sources/gfx-planetv.asm"   \ the moon's and the ring's (bank 7 writes them in
                            \ game context, the frame layer reads them)
.F_SUX      SKIP 2          \ the sun's centre this frame (F_PLANET from SUN, or
.F_SUY      SKIP 2          \ S_SUN: gfx-ssun.asm), with GSUNR and GSUNON
.FL_BEH     SKIP 1          \ bit 7: the sun is behind the planet (f_flt, for
                            \ R_FLARE's probes)
.SS_OK      SKIP 1          \ bit 7: S_SUN knows where the sun is from the planet
                            \ (F_DIRECT clears it while we are docked)
.ss_d       SKIP 9          \ S_SUN's D = sun - planet (x, y, z: lo, hi, top, two's
                            \ complement), then, as ss_turn (MV40) turns both alike,
.MN_E       SKIP 9          \ the moon's place, E = moon - planet, the same way, in
                            \ the coordinates (MN_TURN, gfx-ssun.asm; pf_moon
                            \ and MOONHIT read it)
.MN_OK      SKIP 1          \ bit 7: MN_E is this system's (F_DIRECT clears it
                            \ while we are docked)
.WS_GAP                    \ (free to the main code)
SKIP CODE% - P%
.WS_END
PRINT "Shared workspace: ", ~WS_START, "-", ~WS_GAP-1, " (free ", &1000-DFSIN-1, ", ", RVBASE-R_S2C-2, ", ", KF-WS_KGAP, " and ", CODE%-WS_GAP, " to the main code at ", ~CODE%, ")"
ASSERT WS_END = CODE%   \ (one block, ending where the main code starts)
ASSERT HI(KF) = HI(KF + 191)    \ (KF,Y: no page crossing)
ASSERT HI(R_WR) = HI(R_WR + 191)

CLEAR &8000, &C000      \ bank 5: the shared region from &9000 (the per-x tables,
ORG &9000               \ the row runs, the boundary arrays, the stars, the lens
INCLUDE "1-source-files/main-sources/gfx-raster.asm"   \ ...), then the disc window at &8000
INCLUDE "1-source-files/main-sources/gfx-raster_disc2.asm"   \ the second disc (R_DISC2: run with the disc
                               \ window paged in, from R_DISCROWS)
ASSERT P% <= R_S2R1            \ (buffer 1's spans' right ends follow it)
.B5_END
ASSERT B5_END <= &C000
CLEAR r_tfree, r_tables \ (gfx-raster.asm skips it)
ORG r_tfree             \ R_LINE's cold part, in the room below the per-x
INCLUDE "1-source-files/main-sources/gfx-raster_lcold.asm"   \ tables (gfx-raster.asm's r_tfree)
.B5_GAP
ASSERT B5_GAP <= R_S2L0       \ (the second disc's spans' left ends follow it)
ASSERT R_S2L1 + 192 <= r_tables AND R_S2R1 + 192 <= &C000 AND R_S2L0 + 192 <= R_S2L1
ASSERT LO(R_S2L0) = LO(R_S2L1) AND LO(R_S2R0) = LO(R_S2R1) AND LO(R_S2L0) <= &40 AND LO(R_S2R0) <= &40
ORG &8000
INCLUDE "1-source-files/main-sources/gfx-raster_disc.asm"
INCLUDE "1-source-files/main-sources/gfx-raster_kept.asm"   \ kept solid rows: bank 5's part

.B5LO_END
ASSERT B5LO_END <= R_S2R0 AND R_S2R0 + 192 <= &9000   \ (buffer 0's spans' right
                                \ ends after the disc window's code)
PRINT "Bank 5: rasteriser: disc window &8000-", ~B5LO_END-1, " (free ", R_S2R0-B5LO_END, " before R_S2R0), shared &9000-", ~B5_END-1,  " free ", R_S2R1-B5_END, " before R_S2R1 (+ ", R_S2L0-B5_GAP, " at ", ~B5_GAP, ", ", R_S2L1-R_S2L0-192, " and ", r_tables-R_S2L1-192, " after R_S2L0 and R_S2L1)"
SAVE "3-assembled-output/BANK5.bin", &8000, B5_END, &8000

CLEAR COLD_END%, &C000  \ bank 7 after the cold area (ROMSEL MERIDBANK): the
ORG COLD_END%           \ meridian window, the beach ball planet's boundaries
.MERID_START
INCLUDE "1-source-files/main-sources/gfx-merid.asm"
INCLUDE "1-source-files/main-sources/gfx-kept7.asm"    \ kept solid rows: the polygons' part (docs/renderer.md)
INCLUDE "1-source-files/main-sources/gfx-planet7.asm"  \ the planet's caps: craters (PF_HOOK, PC_ROWS)
INCLUDE "1-source-files/main-sources/gfx-flare.asm"    \ the lens flare (T_FLARE; its step in bank 6:
                               \ gfx-flare6.asm)
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
INCLUDE "3-assembled-output/gfx-light-6.asm"   \ the lighting's L_REC (gfx-light.asm's second
                               \ pass; L_SUN, its first, is at bank 4's end)
INCLUDE "1-source-files/main-sources/gfx-frame_cold.asm"
INCLUDE "1-source-files/main-sources/gfx-flare6.asm"   \ the lens flare's step (the flare: gfx-flare.asm, bank 7)
INCLUDE "1-source-files/main-sources/gfx-hangar.asm"   \ the hangar's frame (HALL; its tables are at bank 6's end)
.B6_CODE_END
.F_HW   SKIP 256        \ planet half-widths
.F_HW2  SKIP 256        \ sun half-widths
.F_HW3  SKIP 64         \ moon half-widths (its radius is at most 63)
.F_DL                   \ ship records: XX2 then XX3 copies (1536 bytes)
 SKIP &22
 INCLUDE "1-source-files/main-sources/gfx-finit.asm"   \ F_INIT, run once before the first frame
 SKIP F_DL + 1536 - P%
.F_DLEND
.F_TM   SKIP 768        \ text map: desired characters, 24 rows of 32
.F_TMR  SKIP 24         \ non-empty cells per row
.F_DSX  SKIP NDSTAR     \ the stars drawn directly (gfx-frame_cold.asm's F_DSTAR,
.F_DSY  SKIP NDSTAR     \ f_unstar): x and y (their sizes, F_DSS, in the shared
                        \ workspace)
 INCLUDE "1-source-files/main-sources/gfx-hangar6.asm"   \ the hangar's tables (f_hback; data
                        \ before them stays at its place)
.F_SLV  SKIP 52         \ the docking slot's vertices, as R_PXL .. R_PYH + 3
                        \ (f_poly2, f_slot: gfx-frame_cold.asm; x high of
                        \ vertex 0, F_SLV+16, &80: none)
.B6_END
PRINT "Bank 6: frame layer &8000-", ~B6_CODE_END-1, ", data ", ~F_HW, "-", ~B6_END-1, " free ", &C000-B6_END
ASSERT B6_END <= &C000
SAVE "3-assembled-output/BANK6.bin", &8000, B6_END, &8000

