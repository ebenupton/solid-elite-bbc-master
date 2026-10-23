\ ============================================================================
\ raster_vars.asm -- the variables and arrays of raster.asm that its caller
\ reads or writes.  Assemble it (before INCLUDEing raster.asm) anywhere in
\ memory both the caller and the rasteriser can see (here the shared
\ workspace in main RAM below &3000, elite-gfx.asm).
\ No ORG and no alignment: it is placed at P%.
\ See raster.asm for what each one means.
\ ============================================================================

.R_NDT      SKIP 1          \ new disc rows NDT..NDB (NDT > NDB: none)
.R_NDB      SKIP 1
.R_NDISCR   SKIP 192
.R_DIRTYL0  SKIP 192        \ buffer 0: dirty extents (empty: L=255, R=0)
.R_DIRTYR0  SKIP 192
.R_DISCR0   SKIP 192        \ buffer 0: disc spans (empty: L=255, R=0); R before
.R_DISCL0   SKIP 192        \ L so that L (read more often) is at LO &35: no page crossing
.R_DIRTYL1  SKIP 192        \ buffer 1: the same, &300 on
.R_DIRTYR1  SKIP 192
.R_DISCR1   SKIP 192
.R_DISCL1   SKIP 192
\ two-colour discs (R_DISCROWS): rows NDT..NDB, used when R_NDF <> 0
.R_NDF      SKIP 1          \ 0: no boundaries this frame (disc all colour A)
.R_DBE      SKIP 1          \ colour B pair (even, odd rows)
.R_DBO      SKIP 1
.R_NDP      SKIP 192        \ bit 0: colour (0 = A, 1 = B) at the span's left end
.R_NDX0     SKIP 192        \ boundary x, ascending: pixels >= x take the other
.R_NDX1     SKIP 192        \ colour; values <= NDISCL or > NDISCR are allowed
.R_NDX2     SKIP 192
.R_NDX3     SKIP 192
\ (the rasteriser's private state, R_PRBUF..R_PRCWB, is in bank 5's shared
\ region: gfx-raster_lcold.asm's end)
ASSERT R_DIRTYL1 = R_DIRTYL0 + &300
