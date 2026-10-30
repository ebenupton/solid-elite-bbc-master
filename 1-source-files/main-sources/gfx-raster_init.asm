\ ============================================================================
\ raster_init.asm -- R_INIT, the rasteriser's set-up, run once (T_INIT, from
\ F_INIT), in the shared region for room (after gfx-raster_disc2.asm:
\ elite-gfx.asm).
\ ============================================================================
.R_INIT
{
  LDA #1
  STA R_CL
  STA R_CT
  LDA #254
  STA R_CR
  LDA #191
  STA R_CB
  LDA #&FF
  STA R_SCOL
  STA R_NDT
  STA R_PRWT
  STZ R_NDB
  STZ R_NDF
  STZ R_SN
  STZ R_PN
  STZ R_PRWB
  LDA #1                  \ buffer 1's state, then buffer 0's (each R_SETBUF
.ib                       \ patching, as R_PRBUF starts as 0), ending with 0
  PHA
  JSR R_SETBUF
  JSR R_RESETBUF
  PLA
  DEC A
  BPL ib
  JSR k_clear             \ no kept rows (T_INIT pages the disc window: bankcheck: ok)
  LDX #192
.il
  LDA #&FF
  STA R_WL-1,X
  STZ R_WR-1,X
  DEX
  BNE il
  RTS
}
