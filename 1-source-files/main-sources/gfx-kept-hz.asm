\ ******************************************************************************
\
\ gfx-kept-hz.asm - the kept solid rows' state (gfx-raster_kept.asm), in HAZEL
\ after the saved data, where every bank and both of ACCCON X's mappings see
\ it: per row, bit b set if the row is kept in buffer b, bit 7 if it is
\ pending this frame. Not saved: R_INIT clears it.
\
\ ******************************************************************************

.KF SKIP 192
