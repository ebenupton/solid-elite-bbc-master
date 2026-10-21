\ ============================================================================
\ raster_line.asm -- R_LINE, the rasteriser's line drawing, in the polygon
\ window (ANDY, ROMSEL RASTPOLY: docs/memory-map.md), after R_POLY
\ (gfx-raster_poly.asm).  The frame layer's T_LINE pages the polygon window in
\ and calls R_LINE.  Besides its own code and variables here it uses phase
\ A's 32-bit maths (rp_mul16, rp_div32, in the polygon window) and, in the
\ shared region (gfx-raster.asm), r_pset, the per-x masks r_lm and r_rm and
\ R_SETBUF's high bytes of the DIRTY arrays (r_sbh_dl, r_sbh_dr).  INCLUDE it
\ after them (it uses their symbols).
\
\ The line from P0 to P1 is Bresenham's along its major axis (x when |dx| >=
\ |dy|) from its left or top end: with d = |d major|, a = |d minor| and h = d
\ DIV 2, pixel i = 0..d is at major m0 + i, minor n0 +- (i * a + h) DIV d.
\ Its pixels inside the clip window are one run (x and y are monotonic).  A
\ line with both ends inside (8-bit) goes straight to the line loops (rl_line);
\ any other is clipped exactly (rl_gen: the first and last pixels inside, from
\ the window's four sides), then drawn by the same loops from the first pixel
\ when d <= 255, or pixel by pixel with a 16-bit error term when d > 255.
\ ============================================================================

.rl_start
\ rl_lstart: A = steps: l_n = A, l_e = (A DIV 2) - l_b, l_x = x0, the buffer's
\ dirty rows += y0..y1 (both inside the window)
.rl_lstart
{
  STA l_n
  LSR A
  SEC
  SBC l_b
  STA l_e
  LDA l_x0
  STA l_x
  LDX R_PRBUF
  LDA l_y0
  LDY l_y1
  CMP l_y1
  BCC t0
  TAY
  LDA l_y1
.t0
  CMP R_PRDYT,X           \ A = top, Y = bottom
  BCS t2
  STA R_PRDYT,X
.t2
  TYA
  CMP R_PRDYB,X
  BCC t4
  STA R_PRDYB,X
.t4
  RTS
}
\ rl_lswap: R_LINE's 8-bit ends exchanged
.rl_lswap
  LDX l_x1
  LDY l_x0
  STX l_x0
  STY l_x1
  LDX l_y1
  LDY l_y0
  STX l_y0
  STY l_y1
  RTS
\ ============================================================================
\ R_LINE (the frame layer's T_LINE pages the polygon window in and calls it)
\ ============================================================================
.R_LINE
{
  LDA R_X0+1              \ both ends in the window: the line loops
  ORA R_X1+1
  ORA R_Y0+1
  ORA R_Y1+1
  BNE gen
  LDA R_X0
  CMP R_CL
  BCC gen
  CMP R_CR
  BEQ f1
  BCS gen
.f1
  LDA R_X1
  CMP R_CL
  BCC gen
  CMP R_CR
  BEQ f2
  BCS gen
.f2
  LDA R_Y0
  CMP R_CT
  BCC gen
  CMP R_CB
  BEQ f3
  BCS gen
.f3
  LDA R_Y1
  CMP R_CT
  BCC gen
  CMP R_CB
  BEQ f4
  BCS gen
.f4
  JMP rl_line
.gen
}
\ ----------------------------------------------------------------------------
\ rl_gen: R_LINE clipped: the rows min(y0, y1)..max(y0, y1) inside the
\ window join the buffer's row range; then the first pixel inside the window
\ (i = rl_i) and the last (rl_j) are found exactly, and the pixels between them
\ drawn.  From the left / top end (major m0, minor n0, s the minor's sign):
\   rl_i = max(0, lo - m0, ceil((k * d - h) / a)) with k = nl - n0 (s > 0) or
\         n0 - nh (s < 0), the last term only if k > 0 (none inside if k > a)
\   rl_j = min(d, hi - m0, ((K + 1) * d - h - 1) DIV a) with K = nh - n0 (s >
\         0) or n0 - nl (s < 0), the last term only if K < a (none if K < 0)
\ ----------------------------------------------------------------------------
.rl_gen
{
  LDA R_Y0                \ rows touched -> this buffer's row range
  CMP R_Y1
  LDA R_Y0+1
  SBC R_Y1+1
  BVC yc0
  EOR #&80
.yc0
  BMI y0top
  LDX #4
  LDY #0
  BRA yc1
.y0top
  LDX #0
  LDY #4
.yc1
  LDA R_Y0+1,X            \ top
  BMI yt_ct
  BNE yno
  LDA R_Y0,X
  CMP R_CT
  BCS yt1
.yt_ct
  LDA R_CT
.yt1
  STA RZ_T0
  LDA R_Y0+1,Y            \ bottom
  BMI yno
  BNE yb_cb
  LDA R_Y0,Y
  CMP R_CB
  BCC yb1
.yb_cb
  LDA R_CB
.yb1
  CMP RZ_T0
  BCC yno
  LDX R_PRBUF
  CMP R_PRDYB,X
  BCC yb2
  STA R_PRDYB,X
.yb2
  LDA RZ_T0
  CMP R_PRDYT,X
  BCS yno
  STA R_PRDYT,X
.yno
  LDX R_PRBUF             \ the DIRTY operands for this buffer
  CPX rl_lbuf
  BEQ pd
  JSR rl_lpat
.pd
  LDX #2                  \ d = P1 - P0 -> rl_dx (x), rl_dy (y); |d| -> rl_ax, rl_ay
.dl
  SEC
  LDA R_X1,X
  SBC R_X0,X
  STA rl_dx,X
  STA rl_ax,X
  LDA R_X1+1,X
  SBC R_X0+1,X
  STA rl_dx+1,X
  STA rl_ax+1,X
  BPL dp
  SEC
  LDA #0
  SBC rl_dx,X
  STA rl_ax,X
  LDA #0
  SBC rl_dx+1,X
  STA rl_ax+1,X
.dp
  DEX
  DEX
  BPL dl
  LDX #0                  \ X = major axis offset (0 = x, 2 = y), Y = minor
  LDY #2
  LDA rl_ax
  CMP rl_ay
  LDA rl_ax+1
  SBC rl_ay+1
  BCS mx
  LDX #2
  LDY #0
.mx
  STX rl_mo
  LDA rl_dx+1,Y            \ minor sign: d minor's, negated when the ends swap
  EOR rl_dx+1,X
  STA rl_s
  LDA rl_ax,X
  STA rl_d
  LDA rl_ax+1,X
  STA rl_d+1
  LSR A
  STA rl_h+1
  LDA rl_d
  ROR A
  STA rl_h
  LDA rl_ax,Y
  STA rl_a
  LDA rl_ax+1,Y
  STA rl_a+1
  LDA R_CL,X
  STA rl_lo
  LDA R_CR,X
  STA rl_hi
  LDA R_CL,Y
  STA rl_nl
  LDA R_CR,Y
  STA rl_nh
  LDA #0                  \ from P1 when d major < 0
  BIT rl_dx+1,X
  BPL p0
  LDA #4
.p0
  ORA rl_mo
  TAX
  LDA R_X0,X
  STA rl_m0
  LDA R_X0+1,X
  STA rl_m0+1
  TXA
  EOR #2
  TAX
  LDA R_X0,X
  STA rl_n0
  LDA R_X0+1,X
  STA rl_n0+1
  LDA rl_mo                \ kind: 2 + (y increases) for x major, 0 + (x
  EOR #2                  \ increases) for y major
  BIT rl_s
  BMI kd
  ORA #1
.kd
  STA l_k
  SEC                     \ rl_i = max(0, lo - m0)
  LDA rl_lo
  SBC rl_m0
  STA rl_i
  LDA #0
  SBC rl_m0+1
  STA rl_i+1
  BPL i1
  STZ rl_i
  STZ rl_i+1
.i1
  BIT rl_s                 \ k -> rp_ma
  BMI ed
  SEC
  LDA rl_nl
  SBC rl_n0
  STA rp_ma
  LDA #0
  SBC rl_n0+1
  BRA ek
.ed
  SEC
  LDA rl_n0
  SBC rl_nh
  STA rp_ma
  LDA rl_n0+1
  SBC #0
.ek
  STA rp_ma+1
  BMI e0                  \ k <= 0: inside from the start on the minor axis
  ORA rp_ma
  BEQ e0
  LDA rl_a                 \ k > a: never inside
  CMP rp_ma
  LDA rl_a+1
  SBC rp_ma+1
  BCS P%+5
.none1
  JMP none
  CLC                     \ rl_t = a - h - 1 = a + NOT h
  LDA rl_h
  EOR #&FF
  ADC rl_a
  STA rl_t
  LDA rl_h+1
  EOR #&FF
  ADC rl_a+1
  STA rl_t+1
  JSR rl_mdqa             \ (k * d + a - h - 1) DIV a
  LDA rp_m0               \ rl_i = max(rl_i, that)
  CMP rl_i
  LDA rp_m1
  SBC rl_i+1
  BCC e0
  LDA rp_m0
  STA rl_i
  LDA rp_m1
  STA rl_i+1
.e0
  SEC                     \ rl_j = hi - m0 (none if < 0) ...
  LDA rl_hi
  SBC rl_m0
  STA rl_j
  LDA #0
  SBC rl_m0+1
  STA rl_j+1
  BMI none1
  LDA rl_d                 \ ... at most d
  CMP rl_j
  LDA rl_d+1
  SBC rl_j+1
  BCS j1
  LDA rl_d
  STA rl_j
  LDA rl_d+1
  STA rl_j+1
.j1
  BIT rl_s                 \ K -> rp_ma
  BMI xd
  SEC
  LDA rl_nh
  SBC rl_n0
  STA rp_ma
  LDA #0
  SBC rl_n0+1
  BRA xk
.xd
  SEC
  LDA rl_n0
  SBC rl_nl
  STA rp_ma
  LDA rl_n0+1
  SBC #0
.xk
  STA rp_ma+1
  BPL P%+5                \ K < 0: never inside
  JMP none
  LDA rp_ma               \ K >= a: inside to the end on the minor axis
  CMP rl_a
  LDA rp_ma+1
  SBC rl_a+1
  BCS x0
  INC rp_ma               \ K + 1
  BNE P%+5
  INC rp_ma+1
  LDA rl_h                 \ rl_t = -h - 1 = NOT h
  EOR #&FF
  STA rl_t
  LDA rl_h+1
  EOR #&FF
  STA rl_t+1
  JSR rl_mdqa             \ ((K + 1) * d - h - 1) DIV a
  LDA rp_m0               \ rl_j = min(rl_j, that)
  CMP rl_j
  LDA rp_m1
  SBC rl_j+1
  BCS x0
  LDA rp_m0
  STA rl_j
  LDA rp_m1
  STA rl_j+1
.x0
  LDA rl_j                 \ rl_i > rl_j: none inside
  CMP rl_i
  LDA rl_j+1
  SBC rl_i+1
  BCC none
  LDA rl_i                 \ q, r = (rl_i * a + h) DIV / MOD d
  ORA rl_i+1
  BNE fq
  STZ rp_m0
  STZ rp_m1
  LDA rl_h
  STA rp_m2
  LDA rl_h+1
  STA rp_m3
  BRA qd
.none
  RTS
.fq
  LDA rl_i
  STA rp_ma
  LDA rl_i+1
  STA rp_ma+1
  LDA rl_a
  STA rp_mb
  LDA rl_a+1
  STA rp_mb+1
  LDA rl_h
  STA rl_t
  LDA rl_h+1
  STA rl_t+1
  LDA rl_d
  STA rp_v0
  LDA rl_d+1
  STA rp_v1
  JSR rl_mdq
.qd
  SEC                     \ pixels: rl_j - rl_i + 1
  LDA rl_j
  SBC rl_i
  INC A
  STA l_n
  CLC                     \ the first pixel: major m0 + rl_i ...
  LDA rl_m0
  ADC rl_i
  TAY
  BIT rl_s                 \ ... minor n0 +- q
  BMI qn
  CLC
  LDA rl_n0
  ADC rp_m0
  BRA qs
.qn
  SEC
  LDA rl_n0
  SBC rp_m0
.qs
  LDX rl_mo                \ A = minor, Y = major -> l_x0, l_y0
  BEQ qx
  STA l_x0
  STY l_y0
  BRA qe
.qx
  STA l_y0
  STY l_x0
.qe
  SEC                     \ e = r - d
  LDA rp_m2
  SBC rl_d
  STA l_e
  LDA rp_m3
  SBC rl_d+1
  LDX rl_d+1
  BEQ short
  JMP rl_long             \ d > 255
.short
  LDA l_x0                \ d <= 255: the line loops from there
  STA l_x
  LDA rl_a
  STA l_a
  LDA rl_d
  STA l_b
  JMP rl_lgo
}
\ ============================================================================
\ The line loops: Bresenham along the major axis from the left / top end, a
\ pixel per step.  Pointer RZ_PP (+ Y = row AND 7), pixel mask l_m, colour
\ by row AND 7 (rl_lct); X = row; DIRTY[b][row] extended per pixel (the
\ buffer's row range is the caller's).  l_n pixels (0: 256), all inside the
\ window.
\ ============================================================================

\ rl_lpat: X = buffer: patch R_LINE's DIRTY operands for it
.rl_lpat
  STX rl_lbuf
  LDA r_sbh_dl,X
  STA lyl_p0+2
  STA lyl_p1+2
  STA lyr_p0+2
  STA lyr_p1+2
  STA lxu_p0+2
  STA lxu_p1+2
  STA lxd_p0+2
  STA lxd_p1+2
  LDA r_sbh_dr,X
  STA lyl_p2+2
  STA lyl_p3+2
  STA lyr_p2+2
  STA lyr_p3+2
  STA lxu_p2+2
  STA lxu_p3+2
  STA lxd_p2+2
  STA lxd_p3+2
  RTS

\ rl_line: R_LINE with both ends inside the window (8-bit); rl_lgo: a line
\ prepared by rl_gen (l_x0 = l_x, l_y0, l_e, l_a, l_b, l_n, l_k; the DIRTY
\ operands patched)
.rl_line
{
  LDX R_PRBUF
  CPX rl_lbuf
  BEQ pd
  JSR rl_lpat
.pd
  LDA R_X0
  STA l_x0
  LDA R_Y0
  STA l_y0
  LDA R_X1
  STA l_x1
  LDA R_Y1
  STA l_y1
  SEC
  LDA l_x1
  SBC l_x0
  BCS a1
  EOR #&FF
  INC A
.a1
  STA l_a                 \ |dx|
  SEC
  LDA l_y1
  SBC l_y0
  BCS a2
  EOR #&FF
  INC A
.a2
  STA l_b                 \ |dy|
  CMP l_a
  BCC xm
  BEQ xm
  LDA l_y1                \ y major: from the top end
  CMP l_y0
  BCS y1
  JSR rl_lswap
.y1
  LDA l_b                 \ steps = dy, e = (dy DIV 2) - dy, a = |dx|, b = dy
  JSR rl_lstart
  LDA l_x1
  CMP l_x0
  LDA #0
  ROL A                   \ 0: x decreases, 1: increases
  BRA go
.xm
  LDA l_x1                \ x major: from the left end
  CMP l_x0
  BCS x1
  JSR rl_lswap
.x1
  LDX l_a                 \ a = |dy|, b = |dx|
  LDY l_b
  STX l_b
  STY l_a
  TXA
  JSR rl_lstart
  LDA l_y1
  CMP l_y0
  LDA #1
  ROL A                   \ 2: y decreases, 3: increases
.go
  STA l_k
  INC l_n                 \ pixels = steps + 1 (0: 256)
}
.rl_lgo
{
  LDY #6
.ct
  LDA R_COLE
  STA rl_lct,Y
  LDA R_COLO
  STA rl_lct+1,Y
  DEY
  DEY
  BPL ct
  LDX l_y0                \ X = row, l_x = x
  LDA l_y0                \ the byte of (l_x, row X): RZ_PP + Y
  LSR A
  LSR A
  AND #&FE
  ORA #&40
  STA RZ_PP+1
  LDA l_x
  AND #&FC
  ASL A
  STA RZ_PP
  BCC s1
  INC RZ_PP+1
.s1
  LDY l_x
  LDA r_lm,Y              \ pixels x..3 AND pixels 0..x of its byte = pixel x
  AND r_rm,Y
  STA l_m
  LDA l_k
  ASL A
  TAY
  LDA tab,Y
  STA jp+1
  LDA tab+1,Y
  STA jp+2
  TXA
  AND #7
  TAY
.jp
  JMP &FFFF
.tab
  EQUW lyl, lyr, lxu, lxd
.lyl
  LDA (RZ_PP),Y
  EOR rl_lct,Y
  AND l_m
  EOR (RZ_PP),Y
  STA (RZ_PP),Y
  LDA l_x
.^lyl_p0 CMP R_DIRTYL0,X
  BCS lyl_1
.^lyl_p1 STA R_DIRTYL0,X
.lyl_1
.^lyl_p2 CMP R_DIRTYR0,X
  BCC lyl_2
.^lyl_p3 STA R_DIRTYR0,X
.lyl_2
  DEC l_n
  BEQ lyl_d
  INX
  INY
  CPY #8
  BNE lyl_y
  LDY #0
  LDA RZ_PP+1
  ADC #1
  STA RZ_PP+1
.lyl_y
  LDA l_e
  CLC
  ADC l_a
  STA l_e
  BCC lyl
  SBC l_b
  STA l_e
  DEC l_x
  ASL l_m
  BCC lyl
  LDA #&11
  STA l_m
  LDA RZ_PP
  SEC
  SBC #8
  STA RZ_PP
  BCS lyl
  DEC RZ_PP+1
  BRA lyl
.lyl_d
  RTS
.lyr
  LDA (RZ_PP),Y
  EOR rl_lct,Y
  AND l_m
  EOR (RZ_PP),Y
  STA (RZ_PP),Y
  LDA l_x
.^lyr_p0 CMP R_DIRTYL0,X
  BCS lyr_1
.^lyr_p1 STA R_DIRTYL0,X
.lyr_1
.^lyr_p2 CMP R_DIRTYR0,X
  BCC lyr_2
.^lyr_p3 STA R_DIRTYR0,X
.lyr_2
  DEC l_n
  BEQ lyr_d
  INX
  INY
  CPY #8
  BNE lyr_y
  LDY #0
  LDA RZ_PP+1
  ADC #1
  STA RZ_PP+1
.lyr_y
  LDA l_e
  CLC
  ADC l_a
  STA l_e
  BCC lyr
  SBC l_b
  STA l_e
  INC l_x
  LSR l_m
  BCC lyr
  LDA #&88
  STA l_m
  LDA RZ_PP
  ADC #7
  STA RZ_PP
  BCC lyr
  INC RZ_PP+1
  BRA lyr
.lyr_d
  RTS
.lxu
  LDA (RZ_PP),Y
  EOR rl_lct,Y
  AND l_m
  EOR (RZ_PP),Y
  STA (RZ_PP),Y
  LDA l_x
.^lxu_p0 CMP R_DIRTYL0,X
  BCS lxu_1
.^lxu_p1 STA R_DIRTYL0,X
.lxu_1
.^lxu_p2 CMP R_DIRTYR0,X
  BCC lxu_2
.^lxu_p3 STA R_DIRTYR0,X
.lxu_2
  DEC l_n
  BEQ lxu_d
  LDA l_e
  CLC
  ADC l_a
  STA l_e
  BCC lxu_x
  SBC l_b
  STA l_e
  DEX
  DEY
  BPL lxu_y
  LDY #7
  LDA RZ_PP+1
  SEC
  SBC #2
  STA RZ_PP+1
.lxu_y
.lxu_x
  INC l_x
  LSR l_m
  BCC lxu
  LDA #&88
  STA l_m
  LDA RZ_PP
  ADC #7
  STA RZ_PP
  BCC lxu
  INC RZ_PP+1
  BRA lxu
.lxu_d
  RTS
.lxd
  LDA (RZ_PP),Y
  EOR rl_lct,Y
  AND l_m
  EOR (RZ_PP),Y
  STA (RZ_PP),Y
  LDA l_x
.^lxd_p0 CMP R_DIRTYL0,X
  BCS lxd_1
.^lxd_p1 STA R_DIRTYL0,X
.lxd_1
.^lxd_p2 CMP R_DIRTYR0,X
  BCC lxd_2
.^lxd_p3 STA R_DIRTYR0,X
.lxd_2
  DEC l_n
  BEQ lxd_d
  LDA l_e
  CLC
  ADC l_a
  STA l_e
  BCC lxd_x
  SBC l_b
  STA l_e
  INX
  INY
  CPY #8
  BNE lxd_y
  LDY #0
  LDA RZ_PP+1
  ADC #1
  STA RZ_PP+1
.lxd_y
.lxd_x
  INC l_x
  LSR l_m
  BCC lxd
  LDA #&88
  STA l_m
  LDA RZ_PP
  ADC #7
  STA RZ_PP
  BCC lxd
  INC RZ_PP+1
  BRA lxd
.lxd_d
  RTS
}

.rl_end
PRINT "raster_line.asm: ", rl_end - rl_start, " bytes"
