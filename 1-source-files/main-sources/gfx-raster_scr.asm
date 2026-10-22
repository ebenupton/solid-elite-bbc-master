\ ============================================================================
\ raster_scr.asm -- the rasteriser's per-call inputs (polygon vertices, line
\ end points, colours) and the new disc spans' left ends, in the shared
\ workspace (elite-gfx.asm, which places it: the vertices in one page, then
\ R_NDISCL page aligned).  The polygon edge tables R_PTA and R_PTB share
\ R_NDISCR's and R_NDISCL's places (elite-gfx.asm): the new disc spans are
\ only live from the frame's f_discs to R_DISCROWS (and f_disc2), before any
\ polygon, and are written afresh each frame; the tables only within one
\ R_POLY call.
\ ============================================================================

.R_PXL      SKIP 16         \ vertex x, low bytes  (signed 16-bit)
.R_PXH      SKIP 16         \ vertex x, high bytes
.R_PYL      SKIP 16         \ vertex y, low bytes
.R_PYH      SKIP 16         \ vertex y, high bytes
ASSERT HI(R_PXL) = HI(R_PYH + 15)
.R_NDISCL   SKIP 192        \ new disc spans, left ends (rows NDT..NDB only, written
                            \ for each frame before R_DISCROWS reads them); page
                            \ aligned: R_NDISCL,X never crosses a page
ASSERT LO(R_NDISCL) = 0
.R_X0       SKIP 2          \ line end points: signed 16-bit words (lo, hi)
.R_Y0       SKIP 2
.R_X1       SKIP 2
.R_Y1       SKIP 2
.R_PN       SKIP 1          \ polygon vertex count 1..16
.R_COL2     SKIP 1          \ R_POLY colour bytes for rows y AND 3 = 2, 3
.R_COL3     SKIP 1
\ private to the rasteriser: the polygon's rows (the polygon window's phase A
\ sets them for 16-bit polygons too; k_pre, bank 7, reads them)
.R_PYS      SKIP 1          \ first row
.R_PYL1     SKIP 1          \ last row
.R_PYE      SKIP 1          \ last row + 1
.R_PXC      SKIP 1          \ non-zero: some x outside CL..CR (8-bit polygons)
.R_PCR1     SKIP 1          \ CR + 1
ASSERT R_Y1 = R_Y0 + 4
