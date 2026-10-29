\ ******************************************************************************
\
\ gfx-finit.asm - the frame layer's one-off initialisation, F_INIT
\
\ Master port: INCLUDEd by elite-gfx.asm in bank 6's F_SR (the ship records),
\ after the 34 bytes where F_INIT keeps Elite's &06-&27 while the rasteriser's
\ R_INIT uses them: the loader calls it once (G_INIT) before the first frame,
\ and from the first frame on F_SR holds the ship records.
\
\ ******************************************************************************

.F_INIT
 LDX #&21               \ R_INIT uses &06-&27: keep Elite's values (in F_SR,
.fin0                   \ before this code)
 LDA &06,X
 STA F_SR,X
 DEX
 BPL fin0
 JSR T_INIT
 LDX #&21
.fin4
 LDA F_SR,X
 STA &06,X
 DEX
 BPL fin4
 LDA #4                 \ Master port: clear main RAM's screen (buffer 0);
 TRB &FE34              \ shadow RAM's (buffer 1, Master's direct-mode screen,
 LDA #&40               \ on show) is cleared by TTX66
 STA fin3+2
 LDA #0
 TAX
.fin3
 STA &4000,X
 INX
 BNE fin3
 INC fin3+2
 LDY fin3+2
 CPY #&70
 BNE fin3
 LDA #&80               \ no docking slot (F_SLV: f_poly2, f_slot)
 STA F_SLV+16
 LDA #0
 STA F_NSHIP
 STA F_NLINE
 STA F_NDOT
 STA F_PLON
 STA MN_ON              \ (no moon, no ring: gfx-planetv.asm is not loaded)
 IF _PLANET_RINGS
 STA RG_N
 ENDIF
 STA MO_ON              \ (and no moon drawn in either buffer)
 STA MO_ON+1
 LDX #NDSTAR-1          \ no stars recorded, no direct-mode stars noted
.fin1
 STA R_SS,X
 STA F_DSS,X
 DEX
 BPL fin1
 RTS                    \ (the text map, F_TCH and f_dlog are all zero, as
                        \ loaded: no text, none shown, none noted)
