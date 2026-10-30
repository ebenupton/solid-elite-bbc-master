\ ============================================================================
\ raster_reset.asm -- R_RESETBUF (T_RESETBUF, R_INIT) and r7_reset1, in the
\ shared region for room (in the room below the per-x tables, after
\ gfx-raster_lcold.asm: elite-gfx.asm); they use nothing of either window.
\ ============================================================================
\ ============================================================================
\ R_RESETBUF: the current buffer's state, not the screen
\ ============================================================================
.R_RESETBUF
{
  LDY #191
  LDX R_PRBUF
  BNE b1
.c0
  LDA #&FF
  STA R_DIRTYL0,Y
  STA R_DISCL0,Y
  LDA #0
  STA R_DIRTYR0,Y
  STA R_DISCR0,Y
  STA R_BDN0,Y            \ (no span, no boundaries: r_dpe)
  DEY
  CPY #&FF
  BNE c0
  BRA done
.b1
  LDA #&FF
  STA R_DIRTYL1,Y
  STA R_DISCL1,Y
  LDA #0
  STA R_DIRTYR1,Y
  STA R_DISCR1,Y
  STA R_BDN1,Y
  DEY
  CPY #&FF
  BNE b1
.done
  JMP r7_reset1
}
\ r7_reset1: buffer X's scalars (keeps X)
.r7_reset1
  LDA #&FF
  STA R_PRDYT,X
  STA R_PRDST,X
  STA R_S2T,X             \ (the second disc's rows: none, and no colour, so
  STZ R_S2B,X             \ that R_DISC2 draws its next rows whole and never
  STZ R_S2C,X             \ reads its spans as they were: gfx-raster_disc2.asm)
  STZ R_PRDYB,X
  STZ R_PRDSB,X
  STZ R_PRSCNT,X
  STZ R_PRECNT,X
  STZ R_PRBMODE,X
  RTS
