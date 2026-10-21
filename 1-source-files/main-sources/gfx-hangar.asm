\ ******************************************************************************
\
\ gfx-hangar.asm - the ship hangar: one frame of the renderer (bank 6)
\
\ Master's hangar (HALL, HAS1, HANGER) draws the ships with LL9 and then the
\ hangar's lines directly, each line running in from the screen's edge until
\ it meets something already drawn. Here the hangar is a space-view frame
\ (docs/renderer.md, "The hangar"): HALL clears the screen with TT66 as
\ before and calls G_HANG0, which empties the frame's lists (a docking leaves
\ the last flight iteration's records in them) and sets the hangar's light;
\ HAS1 places each ship as before, and LL9 records it (record mode: QQ11 =
\ 0, GFORCE = 0); TT66's view name is in the text map. HALL then jumps to
\ G_HANGAR, which draws the frame with F_FRAME, its call of f_lines pointed
\ at f_hback for this frame only: the hangar's background goes in after the
\ (empty) disc layer and before the ships, so the ships hide it where the
\ original's lines stopped at them, and the flight's frames run exactly as
\ before (no test, no cost).
\
\ The background: the back wall a darker tan and the floor a light tan, each
\ a flat 2x2 dither (HPWL, HPWH in HAZEL, gfx-hangar-hz.asm), with HANGER's
\ lines over them in black: the floor's at y = #Y + 130 DIV Q for Q = 2 to
\ 12, from x = 2 to 253, and the wall's every 8 pixels, x = 8 to 248, from
\ the top to the floor's furthest line. The wall starts below the view's
\ name (TT66's, in yellow, which the wall's tan, half yellow, swallows): a
\ black band, rows 1 to 15, is left above it.
\
\ ******************************************************************************

HTOP = 16               \ the wall's top row: text row 1, the view's name, is on
                        \ black above it

\ F_HANGAR: the hangar's frame (G_HANGAR, from HALL)

.F_HANGAR
 LDX #LO(f_hback)
 LDY #HI(f_hback)
 JSR fhg_pat
 JSR F_FRAME
 LDX #LO(f_lines)
 LDY #HI(f_lines)
.fhg_pat
 STX ff_lin+1
 STY ff_lin+2
 RTS

\ F_HANG0: before the hangar's ships are recorded (G_HANG0): the hangar's
\ light (LLT, gfx-light.asm: towards the top right and the viewer, as the
\ title's), and the frame's lists emptied

.F_HANG0
 LDX #2
.fhg0
 LDA fhlt,X
 STA LLT,X
 DEX
 BPL fhg0
 JMP f_reset

.fhlt EQUB 24, 24, &E8

\ f_hback: the background, in place of f_lines's call (F_FRAME's ff_lin),
\ then the lines recorded (none: f_lines is the frame's own)

.f_hback
 LDX #3                 \ the rectangles' vertices' high bytes: 0
.fhb0
 STZ R_PXH,X
 STZ R_PYH,X
 DEX
 BPL fhb0
 LDA #LO(HPWL)          \ f_col's packed colours: the wall's and the floor's
 STA fcl+1
 LDA #HI(HPWL)
 STA fcl+2
 LDA #LO(HPWH)
 STA fch+1
 LDA #HI(HPWH)
 STA fch+2
 STZ fz_t               \ x = 0 to 254 (the clip window stops at 253)
 LDA #255
 STA fz_u
 LDX #0                 \ the wall: from row HTOP (rows 1 to HTOP-1 stay black,
 JSR fch                \ a band behind the view's name: its yellow is the
 LDA #HTOP              \ wall's own) to the floor's furthest line
 LDY HFY
 JSR fh_rect
 LDX #1                 \ the floor: from there to the bottom
 JSR fch
 LDA HFY
 LDY #192
 JSR fh_rect
 LDA #FC_BLACK          \ the lines: black, solid
 JSR f_setcol
 STA R_COL3
 STA R_COL2
 LDA #2                 \ the floor's lines, x = 2 to 253, near to far (rows
 STA fz_t               \ HFY[10] to HFY[0]), as one-row rectangles (R_POLY
 LDA #254               \ fills a row much faster than R_LINE steps along it)
 STA fz_u
 LDX #10
.fhb2
 STX fz_i
 LDA HFY,X
 TAY
 INY
 JSR fh_rect
 LDX fz_i
 DEX
 BPL fhb2
 LDA #HTOP              \ the wall's lines, x = 248 down to 8, from row HTOP to
 STA fz_u               \ the floor's furthest line (R_LINE: a thin R_POLY is
 LDA #248               \ slower)
.fhb3
 STA fz_t
 TAX
 LDY HFY
 JSR f_line8
 LDA fz_t
 SEC
 SBC #8
 BNE fhb3
 JMP f_lines

\ fh_rect: fill pixels fz_t to fz_u-1 of rows A to Y-1 (R_POLY's rule) in the
\ colour set

.fh_rect
 STA R_PYL
 STA R_PYL+1
 STY R_PYL+2
 STY R_PYL+3
 LDA fz_t
 STA R_PXL
 STA R_PXL+3
 LDA fz_u
 STA R_PXL+1
 STA R_PXL+2
 LDA #4
 STA R_PN
 JMP T_POLY
