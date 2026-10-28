\ ******************************************************************************
\
\ frame_cold.asm - the frame layer's bookkeeping for screens drawn directly
\ (outside record mode, i.e. QQ11 or GFORCE non-zero), and for those that
\ then carry on in record mode without a TT66: DEATH and TITLE (TT66 13,
\ whose TTX66K may print the hyperspace countdown directly, then QQ11 = 0)
\ and the briefing's LL9B. FRAME must know what text main RAM (buffer 0)
\ already shows, and the directly drawn stars must go (in record mode STARS1
\ only records new positions, so nothing else would ever remove them from
\ buffer 0).
\
\ INCLUDEd at the end of bank 6 (after its data), wrapping the text-map entry points of
\ frame.asm (f_char1, f_delchar0, f_clrtext0, f_direct0, f_enter), so that
\ none of the per-frame code moves.
\
\ ******************************************************************************

\ F_CHAR: TT26's character K3 at (XC-1, YC): in record or space mode into
\ the text map (f_char1); otherwise CHPR draws it directly, and it is noted
\ (the first DLMAX after a screen clear) or given to the map's cells that
\ buffer 0 may show (f_drule). A, X and Y are not kept

.F_CHAR
 BIT GMODE
 BMI fch_r
 LDA QQ11
 ORA GFORCE
 BNE fch_d
.fch_r
 JSR fsy1               \ (the direct text noted first, if any)
 LDA K3
 LDX XC
 DEX
 LDY YC
 JMP f_char1
.fch_d
 LDX f_dlog
 CPX #DLMAX
 BCS fchd2
 LDA XC
 DEC A
 STA f_dlx,X
 LDA YC
 STA f_dly,X
 LDA K3
 STA f_dlk,X
 INC f_dlog
 RTS
.fchd2
 JSR f_dflush
 LDA K3
 LDX XC
 DEX
 LDY YC
 JMP f_drule

\ F_DELCHAR: clear the text map cell at (XC, YC) (TT26's delete)

.F_DELCHAR
 LDX XC
 LDY YC
 JSR f_sync
 JMP f_delchar0

\ F_CLRTEXT: clear text map rows 21-23 (CLYNS). Preserves X and Y (CLYNS
\ leaves X alone).

.F_CLRTEXT
 PHX
 PHY
 JSR f_sync
 LDX #21
 LDY #23
 JSR f_clrtext0
 PLY
 PLX
 RTS

\ F_DIRECT: TT66 is about to blank shadow RAM and draw directly (f_direct0
\ clears the text map): no direct text or stars

.F_DIRECT
 LDA QQ12               \ docked: S_SUN forgets where the sun is (after a
 BEQ P%+8               \ launch it takes it from the system's seeds), and
 STZ SS_OK              \ MN_TURN the moon's place (MN_TURN makes it again)
 STZ MN_OK
 ASL GWARP              \ LOOK1's TT66 for an in-system jump (WARP) in space
 BCC fdr1               \ mode: keep double buffering and the view on show (the
 BIT GMODE              \ blank screen was all a held J ever showed). As
 BPL fdr1               \ TTX66 would have cleared it, the text goes (the jump's
 STZ GSIGHT             \ LOOK1 reprints the title and redraws the sights), and
 JSR f_sync             \ G_DIRECT returns to TTX66's caller with its results,
 LDX #0                 \ the cursor at (1, 1)
 LDY #23
 JSR f_clrtext0
 LDX #0
 LDY #0
 LDA #1
 STA XC
 STA YC
 RTS
.fdr1
 JSR f_dflush           \ (the last screen's noted text given to the map)
 JSR f_direct0          \ (which clears F_DSS with R_SS: no stars noted)
 STZ f_dlog             \ nothing noted on the new screen
 RTS

\ f_poly2: f_item's polygon detail (T_POLY), and a station's docking slot
\ (the only unlit polygon detail: black, colour byte &80 + 4 * its fill
\ visibility, gfx-faces.asm) filled and outlined in yellow over that. A fill
\ only a pixel or two across can come out empty, so the slot vanished long
\ before Elite stopped drawing its edges; lines always show, so the slot is
\ seen as early as in the original (its item's visibility is the furthest
\ Elite draws any of its edges: beyond its fill visibility, where some of its
\ vertices are not projected, just its side from vertex 0 to 1, as Elite),
\ and stands out from the dithered face. f_itemv has left the vertices in
\ R_PXL/R_PXH/R_PYL/R_PYH, which T_POLY and T_LINE do not change, and n in
\ fz_n.

.f_poly2
 LDY #2
 LDA (fz_q),Y           \ the colour byte: a hue ramp (bit 7 clear), or the
 BPL fpo8               \ slot's
 LSR A
 LSR A
 AND #31                \ its fill visibility
 CMP f_x4
 LDA #1                 \ (beyond it, A = 1: the edge from vertex 0 to 1 only)
 BCC fpo2
 JSR T_POLY
 LDX #51                \ its vertices for R_STARPLOT, which plots no star
.fpo3                   \ over it (F_SLV: black, the screen cannot tell)
 LDA R_PXL,X
 STA F_SLV,X
 DEX
 BPL fpo3
 LDA fz_n
.fpo2
 PHA
 LDA #1                 \ yellow (F_CPE/F_CPO entry 1)
 JSR f_setcol
 PLA
.fpo1                   \ A = i + 1 (i = n-1 down to 0): the edge from vertex i
 STA fz_u               \ to vertex (i + 1) MOD n
 DEC A
 LDX #3
 JSR fpo_ld             \ R_X0, R_Y0 = vertex i
 LDA fz_u
 CMP fz_n
 BCC P%+4
 LDA #0
 LDX #7
 JSR fpo_ld             \ R_X1, R_Y1 = vertex (i + 1) MOD n
 JSR T_LINE
 DEC fz_u
 LDA fz_u
 BNE fpo1
 RTS
.fpo8
 JMP T_POLY

\ fpo_ld: A = vertex number, X = 3 (to R_X0, R_Y0) or 7 (to R_X1, R_Y1): the
\ vertex's R_PYH, R_PYL, R_PXH, R_PXL (16 bytes apart) to R_X0 + X, X-1,
\ X-2, X-3

.fpo_ld
 ORA #48
 TAY
 SEC
.fpol1
 LDA R_PXL,Y
 STA R_X0,X
 TYA
 SBC #16
 TAY
 DEX
 BCS fpol1
 RTS
 ASSERT R_PXH = R_PXL + 16 AND R_PYL = R_PXL + 32 AND R_PYH = R_PXL + 48
 ASSERT R_Y0 = R_X0 + 2 AND R_X1 = R_X0 + 4 AND R_Y1 = R_X0 + 6

\ f_enter2: the first record-mode frame since F_DIRECT. Main RAM is visible
\ (X = 0): remove the directly drawn stars before f_enter copies the border
\ to shadow RAM, then give the text map the text drawn directly, if any.

.f_enter2
 JSR f_unstar
 BIT GSTASH             \ after a disc command buffer 0 holds no frame: start it
 BPL fen2a              \ afresh (f_b0new)
 JSR f_b0new
.fen2a
 JSR f_enter
 STZ f_hwr              \ f_enter used the half-width tables as its buffer
 STZ f_hw2r
                        \ fall through into f_sync (QQ11 = 0 here)

\ f_sync: called before each change to the text map. Outside record and space
\ mode (GMODE bit 7: the frames are running, as in the mission briefing,
\ whose text is printed outside record mode while LL9B draws the ship as a
\ frame) CHPR draws the text directly, into shadow RAM (buffer 1): the
\ characters F_CHAR noted are given to the map's cells by f_drule before the
\ map changes otherwise (f_dflush). At the first change in record or space
\ mode (or the first frame), they go into the map as characters (f_char1),
\ erasing nothing in buffer 1, which shows them: so the screens that carry
\ on in record mode keep the hyperspace countdown TTX66K drew. Preserves X
\ and Y.

.f_sync
 BIT GMODE
 BMI fsy1
 LDA QQ11
 ORA GFORCE
 BNE f_dflush
.fsy1
 LDA f_dlog
 BEQ fsy9
 CMP #DLMAX+1
 BCS fsy8               \ (given to the map already: f_dflush)
 DEC f_mk0              \ (non-zero: f_mark leaves buffer 1 alone)
 CLC
 JSR fdl0
 STZ f_mk0
.fsy8
 STZ f_dlog
.fsy9
 RTS

\ f_dflush: the noted direct text, if not yet given to the map, given to its
\ cells by f_drule; then nothing more is noted until the next screen clear
\ (F_DIRECT) or record-mode change (f_sync). Preserves X and Y.

.f_dflush
 LDA f_dlog
 CMP #DLMAX+1
 BCS fdl9
 SEC
 JSR fdl0
 LDA #DLMAX+1
 STA f_dlog
.fdl9
 RTS

.fdl0                   \ the noted characters, in order, to f_drule (C set)
 PHX                    \ or f_char1 (C clear); X and Y kept
 PHY
 ROR f_dmode
 LDX #0
.fdl1
 CPX f_dlog
 BCS fdl8
 PHX
 LDA f_dly,X
 TAY
 LDA f_dlk,X
 PHA
 LDA f_dlx,X
 TAX
 PLA
 BIT f_dmode
 BPL fdl2
 JSR f_drule
 BRA fdl3
.fdl2
 JSR f_char1
.fdl3
 PLX
 INX
 BRA fdl1
.fdl8
 PLY
 PLX
 RTS

.f_dlog EQUB 0          \ characters noted since the screen's clear (DLMAX + 1:
                        \ given to the map already)
.f_dmode EQUB 0         \ bit 7: fdl0 to f_drule
.f_dlx  SKIP DLMAX      \ their columns, rows and characters
.f_dly  SKIP DLMAX
.f_dlk  SKIP DLMAX

\ f_drule: character A drawn directly into the cell at column X, row Y. A
\ cell holding 0 or &80 is left alone (buffer 0 shows nothing there, or is
\ to erase it anyway); one holding A or &80 + A is toggled, as CHPR's EOR
\ and f_char1 do it; one holding another character, or remembering one,
\ becomes &80: buffer 0 may show that character, which is to go

.f_drule
 CPY #24
 BCS frl9
 CPX #32
 BCS frl9
 STA f_tmp
 STY f_row
 JSR f_cell
 JSR f_tmget
 STX f_ysav             \ (the cell)
 TXA
 AND #&7F
 BEQ frl9
 LDX f_row
 CMP f_tmp
 BNE frl2
 LDA f_ysav             \ the same character: drawn again or removed
 EOR #&80
 BMI frl1
 INC F_TMR,X
 BRA frl4
.frl1
 DEC F_TMR,X
 BRA frl4
.frl2
 LDA #&80               \ another: forgotten
 BIT f_ysav
 BMI frl4
 DEC F_TMR,X
.frl4
 JSR f_tmst
 LDA #3
 STA F_TCH,X
.frl9
 RTS

\ f_b0new: a disc command has used buffer 0 (main RAM &4000-&5FFF) to stash
\ HAZEL (DOSCLI, elite-source.asm), so it no longer holds the last frame of
\ the previous space-mode session that its rasteriser state and disc colour
\ describe: clear it and forget that state, as F_INIT leaves
\ it, for f_enter to carry on from (it then copies the border across)

.f_b0new
 STZ GSTASH
 LDA #4                 \ X = 0: main RAM
 TRB &FE34
 LDA #&40
 STA fbn1+2
 LDA #0
 TAX
.fbn1
 STA &4000,X            \ (patched) clear &4000-&6FFF
 INX
 BNE fbn1
 INC fbn1+2
 LDY fbn1+2
 CPY #&70
 BNE fbn1
 STZ F_SGS              \ no sights drawn in it
 STZ MO_ON              \ no moon
 LDA #&FF               \ no disc colour
 STA F_DCOL
 LDA #0                 \ its rasteriser state: empty
 JSR T_SETBUF
 JSR T_RESETBUF
 LDA #&FF               \ and no cells f_mark erased: its text shows nothing,
 STA f_mrt              \ right for any F_TCH (the text map, frame.asm)
 STZ f_mrb
 RTS

\ f_unstar: EOR away the stars PIXEL drew directly into main RAM since
\ F_DIRECT (F_DSTAR noted them), exactly as PIXEL drew
\ them, so any text drawn over them stays intact. Main RAM must be visible.

.f_unstar
 LDA #4                 \ (Master port: the stars were drawn into shadow RAM)
 TSB &FE34
 LDY #NDSTAR-1
.fus1
 LDA F_DSS,Y
 BEQ fus9
 STA f_tmp              \ size 1-3
 LDA #0
 STA F_DSS,Y
 STY f_ysav2
 LDA F_DSY,Y            \ fz_nm = &4000 + (y DIV 8) * &200 + (x DIV 4) * 8
 LSR A
 LSR A
 AND #%11111110
 ORA #&40
 STA fz_nm+1
 LDA F_DSX,Y
 AND #%11111100
 ASL A
 STA fz_nm
 BCC P%+4
 INC fz_nm+1
 LDA F_DSX,Y
 AND #3
 TAX
 LDA F_DSY,Y
 AND #7
 TAY
 LDA f_tmp
 CMP #2
 BCS fus2
 LDA f_twos,X           \ size 1: one pixel
 BCC fus4
.fus2
 LDA f_twos2,X          \ size 2: a dash
 EOR (fz_nm),Y
 STA (fz_nm),Y
 LDA f_tmp
 CMP #3
 BCC fus8
 DEY                    \ size 3: and the row above (below on a cell's top row)
 BPL P%+4
 LDY #1
 LDA f_twos2,X
.fus4
 EOR (fz_nm),Y
 STA (fz_nm),Y
.fus8
 LDY f_ysav2
.fus9
 DEY
 BPL fus1
 LDA #4
 TRB &FE34
 RTS

.f_ysav2 EQUB 0
.f_twos  EQUB %10001000 AND DUST, %01000100 AND DUST, %00100010 AND DUST, %00010001 AND DUST
.f_twos2 EQUB %11001100 AND DUST, %01100110 AND DUST, %00110011 AND DUST, %00110011 AND DUST
                        \ (Master port: TWOS2 AND DUST, as PIXEL draws stardust)

\ F_DSTAR: outside record mode PIXEL2 draws star Y straight into main RAM;
\ H_STAR (C set: hA = y, X = x, ZZ = distance) and H_STAROFF (C clear: off
\ screen) come here (via G_DSTAR) to note it, so that f_unstar can remove it.
\ Preserves X and Y; returns C set if it was clear.

.F_DSTAR
 BCC fdzo
 CPY #NDSTAR
 BCS fdz9
 LDA hA
 STA F_DSY,Y
 TXA
 STA F_DSX,Y
 LDA ZZ                 \ size 2-3 as Master's PIXEL draws it (non-zero:
 CMP #80                \ noted)
 LDA #2
 BCS fdz1
 LDA #3
.fdz1
 STA F_DSS,Y
.fdz9
 RTS
.fdzo
 CPY #NDSTAR
 BCS fdzo9
 LDA #0
 STA F_DSS,Y
.fdzo9
 SEC
 RTS

\ (F_DSS, F_DSX, F_DSY: the noted stars' sizes (0 = none), x and y, in bank
\ 6's state, elite-gfx.asm)

\ f_sgs: f_sight2's rare case, out of line (frame.asm's fsg2 loop found bit 7
\ set in rows SGY-SGOUT+Y or SGY-SGOUT-1+Y, Y = 1-41 odd): f_wcov with A = X =
\ SGX for each of the two rows (ignoring row SGY+SGOUT+1, outside the sight);
\ either covered -> fsg3 (redraw), else carry on at fsg8

.f_sgs
 PHY
 TYA
 CLC
 ADC #SGY-SGOUT         \ Y = the upper row of the pair, SGY-SGOUT+Y
 TAY
 CPY #SGY+SGOUT+1
 BCS fsgs1              \ row SGY+SGOUT+1: not part of the sight
 LDA #SGX
 TAX
 JSR f_wcov             \ A = X = SGX (fz_t = fz_u = SGX, as before)
 BCS fsgs3
.fsgs1
 DEY                    \ the lower row, SGY-SGOUT-1+Y
 LDA #SGX
 TAX
 JSR f_wcov
 BCS fsgs3
 PLY
 JMP fsg8
.fsgs3
 PLY
 JMP fsg3

\ ------------------------------------------------------------------------------
\ f_slot: the stars (T_STARPLOT) when a station's docking slot was filled this
\ frame. The slot is the frame's only pure black fill (2-build-files/
\ starocc.py), so the screen cannot tell a star there from one on the
\ background: f_poly2 copies the slot's four vertices, as T_POLY filled them,
\ to F_SLV (R_PXL .. R_PYH + 3's layout: x low at +0, x high at +16, y low at
\ +32, y high at +48). The stars with a pixel in the vertices' bounding box
\ (clamped to 0..255) are taken out of R_SS for this plot and put back after
\ it (the hooks write R_SS only when a star moves); f_reset then marks F_SLV
\ empty (x high of vertex 0 &80, which no projected vertex is).
\ ------------------------------------------------------------------------------

.f_slot
{
  LDA #&FF                \ r_sbb: x min, x max, y min, y max
  STA r_sbb
  STA r_sbb+2
  STZ r_sbb+1
  STZ r_sbb+3
  LDX #35                 \ the y of vertices 3..0 (F_SLV+32..35), then the x
.v                        \ (F_SLV+3..0)
  LDY #2
  CPX #32
  BCS v1
  LDY #0
.v1
  LDA F_SLV+16,X          \ the coordinate clamped to 0..255
  BEQ v3
  ASL A                   \ (C = its sign: off the screen's top or left, 0;
  LDA #&FF                \ else 255)
  ADC #0
  BRA v4
.v3
  LDA F_SLV,X
.v4
  CMP r_sbb,Y
  BCS v5
  STA r_sbb,Y
.v5
  CMP r_sbb+1,Y
  BCC v6
  STA r_sbb+1,Y
.v6
  DEX
  BMI v7
  CPX #31
  BNE v
  LDX #3
  BRA v
.v7
  LDA r_sbb               \ a star's pixels are x..x+1, y..y+1: it meets
  BEQ v8                  \ the box if x >= x min - 1 (and y likewise)
  DEC r_sbb
.v8
  LDA r_sbb+2
  BEQ v9
  DEC r_sbb+2
.v9
  LDX R_SN                \ the stars in the box out of R_SS (R_SN >= 1:
.s                        \ the frame layer's NOST + 1)
  DEX
  BMI s3
  LDA R_SS,X
  STA r_ssv,X
  BEQ s
  LDA R_SX,X
  CMP r_sbb
  BCC s
  CMP r_sbb+1
  BEQ s1
  BCS s
.s1
  LDA R_SY,X
  CMP r_sbb+2
  BCC s
  CMP r_sbb+3
  BEQ s2
  BCS s
.s2
  STZ R_SS,X
  BRA s
.s3
  JSR T_STARPLOT          \ plot the rest
  LDX R_SN                \ and put R_SS back
.r
  DEX
  BMI r1
  LDA r_ssv,X
  STA R_SS,X
  BRA r
.r1
  RTS
.r_sbb  SKIP 4
.r_ssv  SKIP NDSTAR
}
