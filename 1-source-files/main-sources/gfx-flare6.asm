\ ******************************************************************************
\
\ gfx-flare6.asm - the lens flare's part in bank 6 (see gfx-flare.asm, in
\ bank 5): its step in F_FRAME and the tests that read bank 6's state
\
\ ******************************************************************************

\ (Its zero page is defined in gfx-flare.asm, assembled first.)

\ f_flt: F_FRAME's text step, after the flare (in place of JSR f_text2).
\ Without the sun (GSUNON = 0) it costs a test. With it: when the view is
\ the front one and the sun's centre is on the screen (x 1..255, y 0..191)
\ and not inside the planet's disc (F_HW has the planet's half-widths, built
\ this frame), the flare (R_FLARE, bank 5, through T_FLARE) with fl_dx and
\ fl_dy (the centre less (128, 96)) and this buffer's dirty extents' pages.

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
 LDA F_PLON             \ behind the planet? (inside its disc)
 BEQ flt1
 LDX #2
 JSR fl_pd              \ |sy - py|
 BNE flt1
 CPY F_PLR
 BEQ P%+4
 BCS flt1
 LDA F_HW,Y
 STA fl_t
 LDX #0
 JSR fl_pd              \ |sx - px|
 BNE flt1
 CPY fl_t
 BCC flt9
 BEQ flt9
.flt1
 LDX fsw_d1+2           \ this buffer's dirty extents (f_bufpatch)
 LDY fsw_d2+2
 JSR T_FLARE
.flt9
 JMP f_text2

\ fl_pd: X = 0: |F_SUX - F_PLX|, X = 2: |F_SUY - F_PLY| in Y, with Z = 1 if
\ it is below 256 (Z = 0: further apart)

.fl_pd
 LDA F_SUX,X
 SEC
 SBC F_PLX,X
 TAY
 LDA F_SUX+1,X
 SBC F_PLX+1,X
 BEQ fl_ret             \ 0..255
 INC A
 BNE fl_ret             \ (not -256..-1: Z = 0)
 TYA                    \ -255..-1: Y = - low byte (-256: Z = 0)
 BEQ fpq8
 EOR #&FF
 TAY
 INY
 LDA #0
.fl_ret
 RTS
.fpq8
 DEC A
 RTS
