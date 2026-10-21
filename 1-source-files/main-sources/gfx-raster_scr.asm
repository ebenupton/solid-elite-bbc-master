\ ============================================================================
\ raster_scr.asm -- the rasteriser's scratch variables: inputs of one call
\ (polygon vertices, line end points) and the polygon edge tables and rows,
\ which no call reads from an earlier one. They can therefore live in
\ HAZEL's &C000-&C2FF, which DFS overwrites during disc access
\ (docs/master-memory.md): nothing needs rebuilding afterwards.
\ ============================================================================

.R_NDISCL   SKIP 192        \ new disc spans, left ends (rows NDT..NDB only, written
                            \ for each frame before R_DISCROWS reads them); first,
                            \ page aligned: R_NDISCL,X never crosses a page
.R_PXL      SKIP 16         \ vertex x, low bytes  (signed 16-bit)
.R_PXH      SKIP 16         \ vertex x, high bytes
.R_PYL      SKIP 16         \ vertex y, low bytes
.R_PYH      SKIP 16         \ vertex y, high bytes
.R_X0       SKIP 2          \ line end points: signed 16-bit words (lo, hi)
.R_Y0       SKIP 2
.R_X1       SKIP 2
.R_Y1       SKIP 2
.R_PN       SKIP 1          \ polygon vertex count 1..16
.R_COL2     SKIP 1          \ R_POLY colour bytes for rows y AND 3 = 2, 3
.R_COL3     SKIP 1
\ private to raster.asm / raster7.asm: polygon edge tables, rows (bank 7's
\ phase A for 16-bit polygons hands them to bank 5's phase B)
.R_PTA      SKIP 192
.R_PTB      SKIP 192
.R_PYS      SKIP 1          \ first row
.R_PYL1     SKIP 1          \ last row
.R_PYE      SKIP 1          \ last row + 1
.R_PXC      SKIP 1          \ non-zero: some x outside CL..CR (8-bit polygons)
.R_PCR1     SKIP 1          \ CR + 1
ASSERT R_Y1 = R_Y0 + 4
ASSERT HI(R_PXL) = HI(R_PYH + 15)
