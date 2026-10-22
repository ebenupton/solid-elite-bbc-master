\ ******************************************************************************
\
\ gfx-tramp.asm - trampolines from the frame layer (bank GFXBANK) into the
\ rasteriser (bank RASTBANK, and ANDY over it, RASTPOLY, for R_POLY and
\ R_LINE). Lives in the low area (main RAM below &3000, elite-low.asm),
\ visible whichever bank is paged and whatever ACCCON X is. A, X, Y are
\ passed through; nothing is returned.
\
\ ******************************************************************************

.tA EQUB 0

.tback
 STA tA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 LDA tA
 RTS

.T_SETBUF
 STA tA
 LDA #RASTBANK
 STA &F4
 STA &FE30
 LDA tA
 JSR R_SETBUF
 JMP tback

.T_RESETBUF
 STA tA
 LDA #RASTBANK
 STA &F4
 STA &FE30
 LDA tA
 JSR R_RESETBUF
 JSR k_clear            \ (kept rows: forgotten)
 JMP tback

.T_STARERASE
 STA tA
 LDA #RASTBANK
 STA &F4
 STA &FE30
 LDA tA
 JSR R_STARERASE
 JMP tback

.T_DISCROWS
 STA tA
 LDA #RASTBANK
 STA &F4
 STA &FE30
 LDA tA
 JSR R_DISCROWS
 JMP tback

.T_SPAN
 STA tA
 LDA #RASTBANK
 STA &F4
 STA &FE30
 JSR tk_y               \ (K mode: row Y's kept state)
 LDA tA
 JSR R_SPAN
 JMP tback

.T_FLARE                \ (the lens flare, gfx-flare.asm; X and Y passed)
 LDA #RASTBANK
 STA &F4
 STA &FE30
 BIT KMODE              \ (K mode: the flare's rows are not kept)
 BPL P%+5
 JSR k_clear
 JSR R_FLARE
 JMP tback

.T_MARKDIRTY
 STA tA
 LDA #RASTBANK
 STA &F4
 STA &FE30
 JSR tk_y
 LDA tA
 JSR R_MARKDIRTY
 JMP tback

.T_MERID                \ (the meridian window's row loop, gfx-merid.asm: bank 7;
 BIT PM_OK              \ not when PM_HOOK has kept the last rows, PM_OK = &C0)
 BVS tmer9
 LDA #MERIDBANK
 STA &F4
 STA &FE30
 JSR PM_MERID
 LDA #&80               \ (the rows are for PM_HOOK's last constants)
 STA PS_VALID
 JMP tback
.tmer9
 RTS

.T_POLY                 \ (R_POLY is in the rasteriser's polygon window, ANDY)
 STA tA
 LDA #RASTPOLY
 STA &F4
 STA &FE30
 LDA tA
 JSR R_POLY
 JMP tback

.T_LINE                 \ (R_LINE is in the polygon window, ANDY, too)
 STA tA
 LDA #RASTPOLY
 STA &F4
 STA &FE30
 BIT KMODE
 BPL P%+5
 JSR tk_line
 LDA tA
 JSR R_LINE
 JMP tback

.T_DOT
 STA tA
 LDA #RASTBANK
 STA &F4
 STA &FE30
 BIT KMODE
 BPL tdt1
 CPY #192               \ (rows below the screen: nothing kept there)
 BCS tdt1
 STX tX
 STY tY
 TYA
 INY                    \ (rows Y and Y + 1, within 0..191)
 CPY #192
 BCC P%+3
 DEY
 TYA
 TAX
 LDA tY
 JSR k_kill
 LDX tX
 LDY tY
.tdt1
 LDA tA
 JSR R_DOT
 JMP tback

.T_STARPLOT
 STA tA
 LDA #RASTBANK
 STA &F4
 STA &FE30
 LDA tA
 JSR R_STARPLOT
 JMP tback

.T_INIT
 STA tA
 LDA #RASTBANK
 STA &F4
 STA &FE30
 LDA tA
 JSR R_INIT
 JMP tback

\ Kept solid rows (gfx-raster_kept.asm): the trampolines' side

.tX EQUB 0
.tY EQUB 0

\ tk_y: (ROMSEL 5) in K mode, row Y: settled if pending, and not kept; keeps
\ X and Y
.tk_y
 BIT KMODE
 BPL tky9
 STX tX
 STY tY
 TYA
 TAX
 JSR k_kill
 LDX tX
 LDY tY
.tky9
 RTS

\ tk_line: (ROMSEL &85: the disc window is paged in for k_kill) the rows of
\ the line R_X0,R_Y0 - R_X1,R_Y1, clipped to 0..191
.tk_line
 LDA #RASTBANK
 STA &F4
 STA &FE30
 LDX #0                 \ the top end: X = 0 (R_Y0) or 4 (R_Y1)
 LDA R_Y0
 CMP R_Y1
 LDA R_Y0+1
 SBC R_Y1+1
 BVC P%+4
 EOR #&80
 BMI tkl1               \ Y0 < Y1
 LDX #4
.tkl1
 LDA R_Y0+1,X           \ top < 0: 0; top > 191: no rows
 BMI tkl2
 BNE tkl8
 LDA R_Y0,X
 CMP #192
 BCS tkl8
 BCC tkl3
.tkl2
 LDA #0
.tkl3
 STA tY
 TXA                    \ the other end: bottom >= 192: 191; < 0: no rows
 EOR #4
 TAX
 LDA R_Y0+1,X
 BMI tkl8
 BNE tkl4
 LDA R_Y0,X
 CMP #192
 BCC tkl5
.tkl4
 LDA #191
.tkl5
 TAX
 LDA tY
 JSR k_kill
.tkl8
 LDA #RASTPOLY
 STA &F4
 STA &FE30
 RTS

\ T_KFRAME: (from F_FRAME, bank 6 paged, before T_SETBUF) A = the buffer:
\ K mode on if a space station is recorded close by (F_STYP, F_SZH in bank
\ 6), with this buffer's bits and operands (k_setbuf); off (and every kept
\ row forgotten) otherwise
KZ = &200               \ the station's z below KZ (its faces about to fill whole
                        \ rows), and the last K mode frame found at least KRMIN
KRMIN = 16              \ kept rows (else K mode sits out KSKIPN frames: the kept
KSKIPN = 4              \ rows' bookkeeping costs more than they save)
.T_KFRAME
 STA tA
 LDX F_NSHIP
.tkf1
 DEX
 BMI tkf3
 LDA F_STYP,X
 CMP #SST
 BEQ tkf2
 CMP #DOD
 BNE tkf1
.tkf2
 LDA F_SZL,X            \ z < KZ (16 bits)
 CMP #LO(KZ)
 LDA F_SZH,X
 SBC #HI(KZ)
 BCS tkf1
 LDA KSKIP              \ (sitting out after a frame that kept too few rows)
 BEQ tkf4
 DEC KSKIP
 BRA tkf3
.tkf4
 BIT KMODE              \ K mode the last two frames: did the last one find
 BPL tkf6               \ enough kept rows (KREC: krow's pending rows)?
 LDA KON                \ (the third frame's repair is the first to find rows
 CMP #3                 \ the first one kept)
 BCC tkf5
 LDA KREC
 CMP #KRMIN
 BCS tkf7
 LDA #KSKIPN            \ no: off for KSKIPN frames
 STA KSKIP
 BRA tkf3
.tkf6
 STZ KON
.tkf5
 INC KON
.tkf7
 STZ KREC
 LDA #MERIDBANK         \ K mode: this buffer's operands in bank 7
 STA &F4
 STA &FE30
 LDA tA
 JSR k_setbuf7
 LDX tA
 LDA tkbit,X
 STA KBIT
 EOR #&FF
 STA KBITN
 LDA #&FF
 STA KPLO
 STZ KPHI
 LDA #&80
 STA KMODE
 JMP tback
.tkbit EQUB 1, 2
.tkf3
.T_KOFF                 \ (and from f_reset: not a space view)
 BIT KMODE
 BPL tkf9
 STZ KMODE
 LDA #RASTBANK
 STA &F4
 STA &FE30
 JSR k_clear
 JMP tback
.tkf9
 RTS

\ T_KCOMMIT: after the ships, in K mode: the rows still pending blacked
.T_KCOMMIT
 BIT KMODE
 BPL tkf9
 LDA #RASTBANK
 STA &F4
 STA &FE30
 JSR k_commit
 JMP tback

\ T_KROWS: rows A .. X (in 0..191) are drawn on directly (the text, the
\ sights): not kept.  Keeps Y.
.T_KROWS
 BIT KMODE
 BPL tkf9
 STY tY
 PHA
 LDA #RASTBANK
 STA &F4
 STA &FE30
 PLA
 JSR k_kill
 LDY tY
 JMP tback

\ T_KPRE: (from R_POLY, ROMSEL &85) bank 7's k_pre, A passed
.T_KPRE
 LDX #MERIDBANK
 STX &F4
 STX &FE30
 JSR k_pre
 LDX #RASTPOLY
 STX &F4
 STX &FE30
 RTS

\ k_setbuf7: (bank 7 paged) buffer A: gfx-kept7.asm's DIRTY operands
.k_setbuf7
  TAX
  LDA k_dlh,X
  STA k_pd1+2
  STA k_pd3+2
  STA k_pd5+2
  LDA k_drh,X
  STA k_pd2+2
  STA k_pd4+2
  STA k_pd6+2
  STA k_pd7+2
  RTS
.k_dlh EQUB HI(R_DIRTYL0), HI(R_DIRTYL1)
.k_drh EQUB HI(R_DIRTYR0), HI(R_DIRTYR1)

