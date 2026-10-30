\ ============================================================================
\ raster_wspan.asm -- R_WSPAN, the moon's span writes (make moon=on), in the
\ shared region, between the second disc's left ends R_S2L0 and R_S2L1
\ (elite-gfx.asm); it uses nothing of either window.
\ ============================================================================
\ R_WSPAN: R_SPAN (Y = row, R_XL .. R_XR, R_COLE/R_COLO), noting the span
\ in R_WL/R_WR and the rows R_PRWT .. R_PRWB as written this frame, as
\ R_DISC2 notes its own, not in DIRTY (the moon, gfx-frame.asm's f_moon:
\ make moon=on)
IF _PLANET_MOON
.R_WSPAN
{
  LDA R_XR
  CMP R_XL
  BCC w9
  LDA R_WR,Y
  BNE w1
  LDA #&FF                \ (none written yet: no left end)
  STA R_WL,Y
.w1
  LDA R_XR
  CMP R_WR,Y
  BCC w2
  STA R_WR,Y
.w2
  LDA R_XL
  CMP R_WL,Y
  BCS w3
  STA R_WL,Y
.w3
  CPY R_PRWT
  BCS w4
  STY R_PRWT
.w4
  CPY R_PRWB
  BCC w5
  STY R_PRWB
.w5
  JMP R_SPAN
.w9
  RTS
}
ENDIF
