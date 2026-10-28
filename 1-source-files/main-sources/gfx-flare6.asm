\ ******************************************************************************
\
\ gfx-flare6.asm - the lens flare's part in bank 6 (see gfx-flare.asm, in
\ bank 7): its step in F_FRAME and the tests that read bank 6's state
\
\ ******************************************************************************

\ (Its zero page is defined in gfx-flare.asm, assembled first.)

\ f_flt: F_FRAME's text step, after the flare (in place of JSR f_text2).
\ Without the sun (GSUNON = 0) it costs a test. With it: when the view is
\ the front one and the sun's centre is on the screen (x 1..255, y 0..191),
\ the flare (R_FLARE, bank 7, through T_FLARE) with fl_dx and fl_dy (the
\ centre less (128, 96)) and this buffer's dirty extents' pages. R_FLARE's
\ probes see what hides the sun: ships, and the planet, which f_disc2 keeps
\ in front of a smaller (further) sun, so there is no test that the centre
\ is outside the planet's disc.

.f_flt
 LDA GSUNON
 BEQ flt9
 LDA VIEW               \ the front view, and the sun's centre on the
 ORA F_SUX+1            \ screen: x 1..255, y 0..191
 ORA F_SUY+1
 BNE flt9
 LDA F_SUX
 BEQ flt9
 EOR #&80
 STA fl_dx
 LDA F_SUY
 CMP #192
 BCS flt9
 SBC #95                \ (C = 0: - 96)
 STA fl_dy
 LDA f_sec              \ FL_BEH bit 7: the sun is the secondary disc, behind
 LSR A                  \ the planet (f_sec = 1)
 ROR A
 STA FL_BEH
 LDX fsw_d1+2           \ this buffer's dirty extents (f_bufpatch)
 LDY fsw_d2+2
 JSR T_FLARE
.flt9
 JMP f_text2
