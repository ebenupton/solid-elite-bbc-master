\ ============================================================================
\ raster_poly.asm -- the rasteriser's polygon window: R_POLY (both phases;
\ phase A for 16-bit coordinates, r7_pf16, came from bank 7), in ANDY
\ (ROMSEL &85: ANDY over bank 5's &8000-&8FFF; bank 5's &9000-&BFFF, the
\ shared region gfx-raster.asm, stays visible: its arithmetic, r_div8,
\ r_pdiv, rp_mul16 and rp_div32, is there).  The frame layer's T_POLY
\ pages it in.  R_SETBUF (shared) pages it in to patch phase B's DIRTY
\ operands.  INCLUDE it at &8000 in an assembly of its own (ANDY), after
\ gfx-raster.asm: it starts with phase B's rows, whose pb_ret is r_xw, the
\ row runs' exit.
\ ============================================================================

\ ----------------------------------------------------------------------------
\ Phase B: rows RZ_Y.., to the end row (pb_ye); left table r_pbl1, right
\ (exclusive) r_pbr1/r_pbr2.  Row pointers, the run page (pb_j_e+2,
\ pb_j_o+2, RZ_PP+1; RZ_PP = 190), RZ_CE/RZ_CO (this row pair's colours) and
\ RZ_XE/RZ_XO set.  Even rows take RZ_CE, odd rows RZ_CO; at each even row
\ (a new pair) pb_tg toggles both to the other pair (a 4-row dither).  A
\ row's whole bytes are stored by its character row's run, entered by a JMP
\ (r_spc's header has the entries) and left by its fixed exit, r_xw, which
\ is pb_ret here: a row makes no call.  The even rows' code reaches pb_ret
\ with C = 1, the odd rows' with C = 0.  pb_ret is the window's first byte.
\ ----------------------------------------------------------------------------
.pb_ret                   \ (= r_xw) back from the run: A = the row's colour,
  BIT R_XR                \ X = R_XR; N = (XR >= &80)
  BMI pb_rbx
  LDY r_xo,X              \ right edge
  EOR (RZ_PA),Y
  AND r_rm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  BCC pb_skip_o
.pb_skip_e
  LDY RZ_Y
  INY
.pb_ye_e
  CPY #0                  \ (patched: the end row)
  BEQ pb_end_j
.pb_c_e
  STY RZ_Y
  INC RZ_PA
  INC RZ_PB
.r_pbx_o
.r_pbl1_o
  LDA &FFFF,Y
.r_pbr1_o
  CMP &FFFF,Y
  BCS pb_skip_o+2         \ empty row: Y = RZ_Y already, skip the LDY RZ_Y
  TAX
.r_pt410 CMP r_dl,Y
  BCS pb_d1_o
.r_pt411 STA r_dl,Y
.pb_d1_o
.r_pbr2_o
  LDA &FFFF,Y
  DEC A
  STA R_XR
.r_pt412 CMP r_dr,Y
  BCC pb_d2_o
.r_pt413 STA r_dr,Y
.pb_d2_o
  TXA
  EOR R_XR
  CMP #4
  BCC pb_one_o
  LDY r_xo,X
  CPX #&80
  BCS pb_lb_o
  LDA (RZ_PA),Y           \ left edge (C = 0 on)
  EOR RZ_CO
  AND r_lm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  TYA                     \ Y = 8 cl + line: the run's index
  ORA RZ_PA
  TAY
  LDA r_j,X               \ (C = 0) 255 - 3n, C = 0
  LDX R_XR
  SBC r_jm,X
  ADC #97                 \ L's store of column cl + n: 96 - 3n, C = 1 if n <= 32
  BCC pb_lng_o
.pb_go_o
  STA pb_j_o+1
  LDA RZ_CO
  CLC                     \ (pb_ret: an odd row)
.pb_j_o
  JMP &FF00               \ (the run's page) back at pb_ret
.pb_rbx                   \ right edge, columns 32..63 (C kept)
  LDY r_xo,X
  EOR (RZ_PB),Y
  AND r_rm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  BCS pb_skip_e
.pb_skip_o
  LDY RZ_Y
  INY
.pb_ye_o
  CPY #0                  \ (patched: the end row)
.pb_end_j                 \ (also BEQ pb_end_j from the even half: Z = 1)
  BEQ pb_end
.pb_c_o
  STY RZ_Y
  TYA                     \ RZ_PA/RZ_PB lo = row AND 7
  AND #7
  BEQ pb_cr               \ (pb_cr zeroes them itself)
  STA RZ_PA
  STA RZ_PB
  JMP pb_tg
.pb_end
  RTS
.pb_one_o
  LDY r_xo,X
  CPX #&80                \ XL, XR differ only in bits 0-1 (XL EOR XR < 4)
  BCS pb_ob_o
  LDA (RZ_PA),Y
  EOR RZ_CO
  AND r_lm,X
  LDX R_XR
  AND r_rm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  BRA pb_skip_o
.pb_ob_o
  LDA (RZ_PB),Y
  EOR RZ_CO
  AND r_lm,X
  LDX R_XR
  AND r_rm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  BRA pb_skip_o
.pb_lb_o                  \ left edge, columns 32..63 (C = 1)
  LDA (RZ_PB),Y
  EOR RZ_CO
  AND r_lm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  TYA                     \ Y = 8 (cl - 32) + line
  ORA RZ_PA
  TAY
  LDA r_jm,X              \ (C = 1) 253 - 3n, C = 0
  LDX R_XR
  SBC r_jm,X
  ADC #192                \ H's store of column cl + n: 189 - 3n (C = 1)
  BRA pb_go_o
.pb_lng_o                 \ (C = 0) A = 352 - 3n, n >= 33
  SBC #66                 \ H's store of column cl + n: 285 - 3n
  STA pb_j_o+1
  LDA #LO(pb_lx_o)        \ H's exit to pb_lx_o, which puts it back and enters L
  STA (RZ_PP)
  LDA RZ_CO
  CLC
  BRA pb_j_o
.pb_lx_o
  LDA #LO(r_xw)
  STA (RZ_PP)
  STZ pb_j_o+1
  LDA RZ_CO
  JMP pb_j_o
.pb_lx_e
  LDA #LO(r_xw)
  STA (RZ_PP)
  STZ pb_j_e+1
  LDA RZ_CE
  JMP pb_j_e
.pb_cr
  STZ RZ_PA               \ next character row: its run page
  STZ RZ_PB
  LDA RZ_PA+1
  CLC
  ADC #2
  STA RZ_PA+1
  INC A
  STA RZ_PB+1
  INC RZ_PP+1
  INC pb_j_e+2
  INC pb_j_o+2            \ (Y = RZ_Y still)
.pb_tg                    \ (Y = RZ_Y) the next row pair's colours
  LDA RZ_CE
  EOR RZ_XE
  STA RZ_CE
  LDA RZ_CO
  EOR RZ_XO
  STA RZ_CO
.r_pbx_e
.r_pbl1_e
  LDA &FFFF,Y
.r_pbr1_e
  CMP &FFFF,Y
  BCS pb_emp_e            \ empty row
  TAX
.r_pt60 CMP r_dl,Y
  BCS pb_d1_e
.r_pt61 STA r_dl,Y
.pb_d1_e
.r_pbr2_e
  LDA &FFFF,Y
  DEC A
  STA R_XR
.r_pt62 CMP r_dr,Y
  BCC pb_d2_e
.r_pt63 STA r_dr,Y
.pb_d2_e
  TXA
  EOR R_XR
  CMP #4
  BCC pb_one_e
  LDY r_xo,X
  CPX #&80
  BCS pb_lb_e
  LDA (RZ_PA),Y           \ left edge (C = 0 on)
  EOR RZ_CE
  AND r_lm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  TYA                     \ Y = 8 cl + line: the run's index
  ORA RZ_PA
  TAY
  LDA r_j,X               \ (C = 0) 255 - 3n, C = 0
  LDX R_XR
  SBC r_jm,X
  ADC #97                 \ L's store of column cl + n: 96 - 3n, C = 1 if n <= 32
  BCC pb_lng_e
.pb_go_e
  STA pb_j_e+1
  LDA RZ_CE
.pb_j_e
  JMP &FF00               \ (the run's page) back at pb_ret, C = 1: an even row
.pb_lng_e                 \ (C = 0) A = 352 - 3n, n >= 33
  SBC #66                 \ H's store of column cl + n: 285 - 3n (C = 1)
  STA pb_j_e+1
  LDA #LO(pb_lx_e)        \ H's exit to pb_lx_e, which puts it back and enters L
  STA (RZ_PP)
  LDA RZ_CE
  BRA pb_j_e
.pb_lb_e                  \ left edge, columns 32..63 (C = 1)
  LDA (RZ_PB),Y
  EOR RZ_CE
  AND r_lm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  TYA                     \ Y = 8 (cl - 32) + line
  ORA RZ_PA
  TAY
  LDA r_jm,X              \ (C = 1) 253 - 3n, C = 0
  LDX R_XR
  SBC r_jm,X
  ADC #192                \ H's store of column cl + n: 189 - 3n (C = 1)
  BRA pb_go_e
.pb_emp_e
  JMP pb_skip_e+2         \ (Y = RZ_Y already: past the LDY RZ_Y)
.pb_one_e
  LDY r_xo,X
  LDA r_lm,X
  LDX R_XR
  AND r_rm,X
  STA RZ_T7
  CPX #&80
  BCS pb_ob_e
  LDA (RZ_PA),Y
  EOR RZ_CE
  AND RZ_T7
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  JMP pb_skip_e
.pb_ob_e
  LDA (RZ_PB),Y
  EOR RZ_CE
  AND RZ_T7
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  JMP pb_skip_e
ASSERT pb_ret = r_xw
ASSERT HI(pb_lx_e) = HI(r_xw) AND HI(pb_lx_o) = HI(r_xw)   \ (a long row's H exit:
                          \ its low byte changed)

\ ============================================================================
\ R_POLY
\ ============================================================================
.R_POLY
{
  STZ F_DROK              \ (its edge tables are R_NDISCL/R: f_discspans' rows
  LDA R_PN                \ are not kept)
  BNE pn1
  RTS
.pn1
  CMP #17
  BCC n_ok
  LDA #16
.n_ok
  STA r_n
  \ fast path when every high byte is zero
  TAX
  DEX
  LDA #0
.hl
  ORA R_PXH,X
  ORA R_PYH,X
  DEX
  BPL hl
  TAX
  BNE p16
  JMP r_pf8
.p16                      \ some coordinate outside 0..255: phase A (r7_pf16)
  JSR r7_pf16
  CMP #0                  \ (A = 0: nothing to draw)
  BEQ r_pout
  JMP r_pcbd
.^r_pout                  \ (also r_pf8's: no rows)
  RTS
}

\ ============================================================================
\ R_POLY 8-bit path: every vertex x, y in 0..255.
\ Phase A walks both chains from the top vertex, running each edge's exact
\ DDA (x = x0 + ceil(dx*k/dy)) down a per-row table: chain A (forward) into
\ r_ta, chain B (backward) into r_tb.  Phase B fills each row from the left
\ table to the right one (exclusive), its whole bytes through the character
\ row's run.
\ ============================================================================
.r_pf8
{
  LDA R_CR
  INC A
  STA r_cr1
  LDX r_n
  DEX
  STX r_top
  LDA R_PYL,X
  STA r_yminL
  STA r_ymaxL
  STZ r_xclip
.sc
  LDA R_PYL,X
  CMP r_yminL
  BCS s1
  STA r_yminL
  STX r_top
.s1
  CMP r_ymaxL
  BCC s2
  STA r_ymaxL
.s2
  LDA R_PXL,X
  CMP R_CL
  BCC s3
  CMP r_cr1
  BCC s4
.s3
  INC r_xclip
.s4
  DEX
  BPL sc
  \ rows ystart..ylast
  LDA r_yminL
  CMP R_CT
  BCS y1
  LDA R_CT
.y1
  STA r_ystart
  CMP r_ymaxL
  BCS r_pout
  CMP R_CB
  BEQ y2
  BCS r_pout
.y2
  LDA r_ymaxL
  DEC A
  CMP R_CB
  BCC y3
  LDA R_CB
.y3
  STA r_ylast
  INC A
  STA r_yend
  \ chain A: forward into r_ta
  LDA #LO(r_ta)
  STA r_lsh_t+1
  STA r_lz_t+1
  LDA #HI(r_ta)
  STA r_lsh_t+2
  STA r_lz_t+2
  LDA #LO(ca)             \ (the edges' exit: ca, cb and r_exr share a page)
  STA r_exj+1
  LDX r_top
  BRA ca
.cad
  \ chain B: backward into r_tb
  LDA #LO(r_tb)
  STA r_lsh_t+1
  STA r_lz_t+1
  LDA #HI(r_tb)
  STA r_lsh_t+2
  STA r_lz_t+2
  LDA #LO(cb)
  STA r_exj+1
  LDX r_top
.cb
  LDA R_PYL,X
  CMP r_ymaxL
  BEQ cbd
  TXA
  TAY                     \ Y = i0
  DEX
  BPL cb1
  LDX r_n
  DEX
.cb1
  STX r_i1
  JMP r_e8
.cbd
  JMP r_pcbd
.^r_ex                    \ an edge is done: on along its chain (or, for the
  LDX r_i1                \ 16-bit path, back to r7_pf16b: r_exr)
.^r_exj
  JMP ca                  \ (its low byte patched: ca, cb or r_exr)
.^r_exr
  RTS
.cl                       \ y0 < ystart: out if the end row <= ystart, else
  LDA r_ystart            \ clipped
  CMP RZ_T2
  BCS r_ex
  JMP clipped
.ca                       \ (from the top vertex, a vertex at ymax, the
  LDA R_PYL,X             \ largest of the vertices' y, comes within n - 1
  CMP r_ymaxL             \ edges either way: no count is needed)
  BEQ cad
  TXA
  TAY                     \ Y = i0
  INX
  CPX r_n
  BCC ca1
  LDX #0
.ca1
  STX r_i1
  ASSERT HI(ca) = HI(r_exj) AND HI(cb) = HI(r_exj) AND HI(r_exr) = HI(r_exj)

\ r_e8: the edge from vertex Y (i0) to vertex X (i1 = r_i1) of an 8-bit
\ polygon into the chain's table, then r_ex.  Its set-up is in line in its
\ chain (chain A falls into it, chain B jumps), the division is reached and
\ left by jumps (r_pdiv, in the shared region; the sign of dx kept in Y's
\ bit 7), and the DDA loops end with a jump back to the chain: an edge
\ makes no call unless it starts above the window (r7_esgen) or has a
\ quotient of 16 or more with a divisor under 16 (r_div8b).  There are two loops: r_lz (no remainder: x += a a row) and
\ r_lsh (x += a, the error -= b, and on a borrow += dy, x += 1).
.r_e8
  LDA R_PYL,X
  CMP R_PYL,Y
  BCC r_ex
  BEQ r_ex                \ not going down
  CMP r_yend
  BCC e1
  LDA r_yend
.e1
  STA RZ_T2               \ end row (exclusive)
  LDA R_PYL,Y
  CMP RZ_T2
  BCS r_ex                \ y0 >= end row
  CMP r_ystart
  BCC cl                  \ y0 < ystart (if y0 >= ystart then RZ_T2 > y0 >= ystart)
  STA RZ_T3               \ start row (A = y0, C = 1)
  EOR #&FF
  ADC R_PYL,X             \ dy = y1 - y0; C stays 1 (y1 > y0)
  STA RZ_T1               \ dy
  LDA R_PXL,Y
  STA RZ_T0               \ S = x0
  EOR #&FF
  ADC R_PXL,X             \ dx = x1 - x0, C = (x1 >= x0)
  BCS pos
  EOR #&FF
  ADC #1                  \ |dx| (C = 0 here)
  LDY #&80                \ (Y's bit 7: dx < 0; i0 has it clear)
.pos
  CMP RZ_T1
  BCC steep
  JMP r_pdiv              \ (the division, in the shared region: gfx-raster.asm;
.steep                    \ it comes back at r_prnz or r_prz)
  TAX                     \ steep: q = 0, r = |dx| (vertical: r = 0)
  BEQ r_prz
  LDX #0
\ x = x0 + ceil(dx * k / dy) per row: x += a, the error -= b, and on a
\ borrow the error += dy, x += 1, with a = floor(dx / dy), b = dx - a * dy
.^r_prnz                  \ the remainder is not 0: X = q, A = r
  CPY #&80
  BCS nr
  TAY                     \ dx > 0: a = q, b = r (the loop's operands hold
  DEY                     \ a - 1 and b - 1)
  STY r_lsh_b+1
  DEX
  STX r_lsh_a+1
  BCC lsh0                \ (always: from the CPY)
.nr                       \ dx < 0: a = NOT q, b = dy - r (C = 1)
  SBC RZ_T1               \ r - dy = -b: NOT it is b - 1
  EOR #&FF
  STA r_lsh_b+1
  TXA
  EOR #&FF
  SBC #0                  \ (C = 0: - 1)
  STA r_lsh_a+1
.lsh0
  STZ RZ_TA               \ the error
  BRA r_lshgo
.^r_prz                   \ the remainder is 0: X = q; a = q, or -q for dx < 0
  CPY #&80
  BCC rzp
  TXA
  EOR #&FF
  ADC #0                  \ (C = 1: + 1)
  TAX
.rzp
  STX r_lz_a+1
  BRA r_lzgo
.clipped                  \ starts above the window: r7_esgen's general set-up
  STA RZ_Y                \ at ystart (A)
  STA RZ_T3
  STZ r7_side4
  JSR r7_esgen            \ (Y = i0, X = i1: S, t -> RZ_SA, RZ_TA; a, b, dy
  LDA RZ_SA               \ -> r7_ea, r7_eb, r7_edy)
  STA RZ_T0
  LDA r7_edy
  STA RZ_T1
  LDA r7_ea
  LDX r7_eb
  BNE r_psh1
\ b = 0: A = a  (falls into r_lz)
.^r_pzl1
  STA r_lz_a+1
.r_lzgo
  LDA RZ_T2
  STA r_lz_e+1
  LDY RZ_T3
  LDA RZ_T0
  CLC
\ The DDA loops (Y = row, run to the patched end row)
.^r_lz                    \ b = 0: A = x
.^r_lz_t
  STA &FFFF,Y
  INY
.^r_lz_a
  ADC #0                  \ a (C = 0)
.^r_lz_e
  CPY #0
  BCC r_lz
  ASSERT HI(P%) = HI(r_lz)   \ (the loops cross no page)
  JMP r_ex
\ shallow: X = b, A = a, RZ_TA = the error
.^r_psh1
  DEC A
  STA r_lsh_a+1
  DEX
  STX r_lsh_b+1
.r_lshgo
  LDA RZ_T1
  STA r_lsh_d+1
  LDA RZ_T2
  STA r_lsh_e+1
  LDY RZ_T3
  LDA RZ_T0
  CLC
.^r_lsh                   \ |dx| >= dy: A = x, RZ_TA = error
.^r_lsh_t
  STA &FFFF,Y
  INY
  TAX
  LDA RZ_TA
.^r_lsh_b
  SBC #0                  \ b - 1 (C = 0)
  BCS lsh1
.^r_lsh_d
  ADC #0                  \ dy
  INX
.lsh1
  STA RZ_TA
  TXA
.^r_lsh_a
  ADC #0                  \ a - 1 (C = 1)
.^r_lsh_e
  CPY #0
  BCC r_lsh
  ASSERT HI(P%) = HI(r_lsh)
  JMP r_ex
}

\ ----------------------------------------------------------------------------
\ r_pcbd: both chains' tables are made (phase A): the rows, then phase B
\ ----------------------------------------------------------------------------
{
.^r_pcbd
  \ which table is the left one?
  LDA r_ystart
  CLC
  ADC r_ylast
  ROR A
  TAY
  LDA r_ta,Y
  CMP r_tb,Y
  BCC aleft
  BNE bleft
  LDY r_ystart
.os
  LDA r_ta,Y
  CMP r_tb,Y
  BCC aleft
  BNE bleft
  INY
  CPY r_yend
  BCC os
  RTS                     \ no pixels
.aleft
  LDX #0
  BRA ori
.bleft
  LDX #2
.ori
  LDA otab,X
  STA r_pbl1_e+1
  STA r_pbl1_o+1
  LDA otab+1,X
  STA r_pbl1_e+2
  STA r_pbl1_o+2
  LDA otab+2,X
  STA r_pbr1_e+1
  STA r_pbr2_e+1
  STA r_pbr1_o+1
  STA r_pbr2_o+1
  LDA otab+3,X
  STA r_pbr1_e+2
  STA r_pbr2_e+2
  STA r_pbr1_o+2
  STA r_pbr2_o+2
  \ horizontal clip: clamp both tables into CL..CR+1
  LDA r_xclip
  BEQ nocl
  LDY r_ystart
.cl
  LDA r_ta,Y
  CMP R_CL
  BCS cl1
  LDA R_CL
.cl1
  CMP r_cr1
  BCC cl2
  LDA r_cr1
.cl2
  STA r_ta,Y
  LDA r_tb,Y
  CMP R_CL
  BCS cl3
  LDA R_CL
.cl3
  CMP r_cr1
  BCC cl4
  LDA r_cr1
.cl4
  STA r_tb,Y
  INY
  CPY r_yend
  BCC cl
.nocl
  \ rows clamped to nothing at the top / bottom (ta = tb): trim them
  LDY r_ystart
.tt
  LDA r_ta,Y
  CMP r_tb,Y
  BNE tt1
  INY
  CPY r_yend
  BCC tt
  RTS                     \ (no pixels at all)
.tt1
  STY r_ystart
  LDY r_ylast
.tb
  LDA r_ta,Y
  CMP r_tb,Y
  BNE tb1
  DEY
  BRA tb
.tb1
  STY r_ylast
  INY
  STY r_yend
  \ this buffer's dirty row range
  LDX R_PRBUF
  LDA r_ystart
  CMP R_PRDYT,X
  BCS d1
  STA R_PRDYT,X
.d1
  LDA r_ylast
  CMP R_PRDYB,X
  BCC d2
  STA R_PRDYB,X
.d2
  BIT KMODE               \ K mode: the kept rows' pass (gfx-raster_kept.asm)
  BPL d3
  LDA r_pbl1_e+1
  JSR T_KPRE              \ (the glue area: k_pre in bank 7)
.d3
  \ phase B set-up
  LDY r_ystart
  JSR r_rowset            \ (A = the run page)
  STA pb_j_e+2
  STA pb_j_o+2
  STA RZ_PP+1             \ RZ_PP: the run's H exit operand, for a long row
  LDA #190
  STA RZ_PP
  LDA r_yend
  STA pb_ye_e+1
  STA pb_ye_o+1
  LDA R_COLE              \ rows 4k, 4k+1 take COLE, COLO; rows 4k+2, 4k+3
  EOR R_COL2              \ COL2, COL3: RZ_CE/RZ_CO = this row pair's, toggled
  STA RZ_XE               \ by RZ_XE/RZ_XO at each pair
  LDA R_COLO
  EOR R_COL3
  STA RZ_XO
  TYA
  AND #2
  BEQ p01
  LDA R_COL2
  LDX R_COL3
  BRA pc
.p01
  LDA R_COLE
  LDX R_COLO
.pc
  STA RZ_CE
  STX RZ_CO
  TYA
  LSR A
  BCC ev
  JMP r_pbx_o             \ odd first row (Y = RZ_Y)
.ev
  JMP r_pbx_e             \ even first row
.otab
  EQUW r_ta, r_tb, r_ta
}


\ R_POLY's phase A for 16-bit coordinates: its variables (its 32-bit maths,
\ rp_mul16 and rp_div32, are in the shared region, gfx-raster.asm)
.rp_ov SKIP 17          \ phase A's edge set-up (r7_edy .. r7_eb)
.r7_n EQUB 0            \ R_POLY's phase A (16-bit): vertices, top vertex,
.r7_top EQUB 0          \ y range, chain count, edge, side
.r7_yminL EQUB 0
.r7_yminH EQUB 0
.r7_ymaxL EQUB 0
.r7_ymaxH EQUB 0
.r7_cc EQUB 0
.r7_i0 EQUB 0
.r7_i1 EQUB 0
.r7_side4 EQUB 0

\ ============================================================================
\ R_POLY's phase A for polygons with some coordinate outside 0..255: chain A
\ into r_ta, chain B into r_tb, rows r_ystart..r_ylast (the shared workspace); bank
\ R_POLY calls r7_pf16 and does phase B (r_pcbd)
\ ============================================================================
\ phase A's edge set-up (rp_ov)
r7_edy = rp_ov + 0
r7_ek0 = rp_ov + 2
r7_ex0 = rp_ov + 4
r7_eadx = rp_ov + 6
r7_eneg = rp_ov + 8
r7_eq = rp_ov + 9
r7_er = rp_ov + 11
r7_ea = rp_ov + 13
r7_eb = rp_ov + 15

.r7_pf16                  \ R_POLY, some coordinate outside 0..255: phase A (bank
{                         \ 5's r_pcbd does phase B); A = 0: nothing to draw
  LDA R_PN
  CMP #17
  BCC n_ok
  LDA #16
.n_ok
  STA r7_n
  \ reject when every x is left of CL or every x is right of CR
  STZ RZ_T0
  LDX r7_n
  DEX
.xl
  LDA R_PXH,X
  BMI xlt
  BNE xgt
  LDA R_PXL,X
  CMP R_CL
  BCC xlt
  CMP R_CR
  BEQ xin
  BCC xin
.xgt
  LDA #2
  BRA xor
.xin
  LDA #3
  BRA xor
.xlt
  LDA #1
.xor
  ORA RZ_T0
  STA RZ_T0
  DEX
  BPL xl
  CMP #3
  BEQ xok
  LDA #0
  RTS
.xok
  LDA R_PYL
  STA r7_yminL
  STA r7_ymaxL
  LDA R_PYH
  STA r7_yminH
  STA r7_ymaxH
  STZ r7_top
  LDX #1
  CPX r7_n
  BEQ rows
.vl
  LDA R_PYL,X             \ y < ymin ?
  CMP r7_yminL
  LDA R_PYH,X
  SBC r7_yminH
  BVC v1
  EOR #&80
.v1
  BPL notless
  LDA R_PYL,X
  STA r7_yminL
  LDA R_PYH,X
  STA r7_yminH
  STX r7_top
  BRA notmore
.notless
  LDA r7_ymaxL             \ ymax < y ?
  CMP R_PYL,X
  LDA r7_ymaxH
  SBC R_PYH,X
  BVC v2
  EOR #&80
.v2
  BPL notmore
  LDA R_PYL,X
  STA r7_ymaxL
  LDA R_PYH,X
  STA r7_ymaxH
.notmore
  INX
  CPX r7_n
  BNE vl
.rows
  \ row range
  LDA r7_yminH
  BMI ys_ct
  BNE out0                \ ymin > 255
  LDA r7_yminL
  CMP R_CB
  BEQ ys_ok
  BCS out0                \ ymin > CB
.ys_ok
  CMP R_CT
  BCS ys_set
.ys_ct
  LDA R_CT
.ys_set
  STA r_ystart
  LDX r7_ymaxH
  BMI out0
  BNE yl_cb
  CMP r7_ymaxL
  BCS out0                \ ystart >= ymax : no rows
  LDA r7_ymaxL
  DEC A
  CMP R_CB
  BCC yl_set
.yl_cb
  LDA R_CB
.yl_set
  STA r_ylast
  INC A
  STA r_yend
  BRA go
.out0
  LDA #0
  RTS
.go                       \ (into r7_pf16b)
}


\ ----------------------------------------------------------------------------
\ r7_pf16b: R_POLY with some coordinate outside 0..255 (rows r_ystart..r_ylast
\ already found).  Phase A as r_pf8 (chain A forward into r_ta, chain B
\ backward into r_tb) with 16-bit edges whose x is clamped into CL..CR+1 per
\ row; then bank 5's phase B (r_pcbd).
\ ----------------------------------------------------------------------------
.r7_pf16b
{
  LDA R_CR
  INC A
  STA r_cr1
  LDA #LO(r_exr)          \ (the edges' exit: back here, r_exr)
  STA r_exj+1
  LDA #LO(r_ta)
  STA r_lsh_t+1
  STA r_lz_t+1
  STA r7_x16_t+1
  STA r7_x16_f+1
  LDA #HI(r_ta)
  STA r_lsh_t+2
  STA r_lz_t+2
  STA r7_x16_t+2
  STA r7_x16_f+2
  LDA r7_n
  STA r7_cc
  LDX r7_top
.ca
  LDA R_PYL,X
  CMP r7_ymaxL
  BNE ca0
  LDA R_PYH,X
  CMP r7_ymaxH
  BEQ cad
.ca0
  DEC r7_cc
  BMI cad
  STX r7_i0
  INX
  CPX r7_n
  BCC ca1
  LDX #0
.ca1
  STX r7_i1
  JSR r7_e16
  LDX r7_i1
  BRA ca
.cad
  LDA #LO(r_tb)
  STA r_lsh_t+1
  STA r_lz_t+1
  STA r7_x16_t+1
  STA r7_x16_f+1
  LDA #HI(r_tb)
  STA r_lsh_t+2
  STA r_lz_t+2
  STA r7_x16_t+2
  STA r7_x16_f+2
  LDA r7_n
  STA r7_cc
  LDX r7_top
.cb
  LDA R_PYL,X
  CMP r7_ymaxL
  BNE cb0
  LDA R_PYH,X
  CMP r7_ymaxH
  BEQ cbd
.cb0
  DEC r7_cc
  BMI cbd
  STX r7_i0
  DEX
  BPL cb1
  LDX r7_n
  DEX
.cb1
  STX r7_i1
  JSR r7_e16
  LDX r7_i1
  BRA cb
.cbd
  STZ r_xclip
  LDA #1                  \ (bank 5: phase B)
  RTS
}

\ r7_e16: edge r7_i0 -> r7_i1 (16-bit) into the table (rows r_ystart..r_ylast)
.r7_e16
{
  LDY r7_i0
  LDX r7_i1
  LDA R_PYL,Y             \ going down? (y0 < y1)
  CMP R_PYL,X
  LDA R_PYH,Y
  SBC R_PYH,X
  BVC v1
  EOR #&80
.v1
  BPL out
  LDA R_PYH,X             \ end row = min(y1, yend)
  BMI out
  BNE e0
  LDA R_PYL,X
  CMP r_yend
  BCC e1
.e0
  LDA r_yend
.e1
  STA RZ_T2
  LDA R_PYH,Y             \ start row = max(y0, ystart)
  BMI s0
  BNE out
  LDA R_PYL,Y
  CMP r_ystart
  BCS s1
.s0
  LDA r_ystart
.s1
  STA RZ_T3
  CMP RZ_T2
  BCC go
.out
  RTS
.go
  STA RZ_Y
  STZ r7_side4
  JSR r7_esgen             \ S, t -> RZ_SA, RZ_TA; a, b, dy -> r7_ea, r7_eb, r7_edy
  LDY r7_i0                \ both ends' x inside CL..CR+1 and dy < 256:
  LDX r7_i1                \ the 8-bit DDA
  LDA r7_edy+1
  BNE gen
  LDA R_PXH,Y
  ORA R_PXH,X
  BNE gen
  LDA R_PXL,Y
  CMP R_CL
  BCC gen
  CMP r_cr1
  BEQ x1
  BCS gen
.x1
  LDA R_PXL,X
  CMP R_CL
  BCC gen
  CMP r_cr1
  BEQ x2
  BCS gen
.x2
  LDA RZ_SA
  STA RZ_T0
  LDA r7_edy
  STA RZ_T1
  LDX r7_eb
  LDA r7_ea
  CPX #0
  BNE sh
  JMP r_pzl1
.sh
  JMP r_psh1
.gen                      \ general: 16-bit S, t; x clamped into CL..CR+1
  LDA r7_eb
  STA bl+1
  LDA r7_eb+1
  STA bh+1
  LDA r7_edy
  STA dl+1
  LDA r7_edy+1
  STA dh+1
  LDA r7_ea
  STA al+1
  LDA r7_ea+1
  STA ah+1
  LDA RZ_T2
  STA ye+1
  STZ RZ_T4               \ bit 7: the far end is inside CL..CR+1 and dy < 256,
  LDX r7_i1                \ so once inside, x stays inside: the 8-bit DDA
  LDA r7_edy+1
  BNE g1
  LDA R_PXH,X
  BNE g1
  LDA R_PXL,X
  CMP R_CL
  BCC g1
  CMP r_cr1
  BEQ g0
  BCS g1
.g0
  DEC RZ_T4
.g1
  LDY RZ_T3
.lp
  LDA RZ_SA+1
  BMI lo
  BNE hi
  LDA RZ_SA
  CMP R_CL
  BCC lo
  CMP r_cr1
  BCC inw
.hi
  BIT r7_ea+1              \ right of the window, moving right: stays there
  BPL fh
  LDA r_cr1
  BRA st
.lo
  BIT r7_ea+1              \ left of it, moving left: stays there
  BMI fl
  LDA R_CL
.st
.^r7_x16_t
  STA &FFFF,Y
  INY
.ye
  CPY #0
  BCS done
  LDA RZ_TA               \ t -= b; borrow: t += dy, S += 1
  SEC
.bl
  SBC #0
  STA RZ_TA
  LDA RZ_TA+1
.bh
  SBC #0
  STA RZ_TA+1
  BCS nb
  LDA RZ_TA
.dl
  ADC #0
  STA RZ_TA
  LDA RZ_TA+1
.dh
  ADC #0
  STA RZ_TA+1
  BRA ad
.nb
  CLC
.ad
  LDA RZ_SA               \ S += a
.al
  ADC #0
  STA RZ_SA
  LDA RZ_SA+1
.ah
  ADC #0
  STA RZ_SA+1
  BRA lp
.done
  RTS
.fh
  LDA r_cr1
  BRA fi
.fl
  LDA R_CL
.fi
.^r7_x16_f
  STA &FFFF,Y
  INY
  CPY ye+1
  BCC fi
  RTS
.inw
  BIT RZ_T4
  BMI sw
  JMP st
.sw                       \ inside for good: the 8-bit DDA from row Y
  STA RZ_T0
  STY RZ_T3
  LDA r7_edy
  STA RZ_T1
  LDX r7_eb
  LDA r7_ea
  CPX #0
  BNE sw1
  JMP r_pzl1
.sw1
  JMP r_psh1
}

\ ----------------------------------------------------------------------------
\ r7_esgen: set up edge r7_i0 -> r7_i1 (y1 > row >= y0) for side r7_side4 at row
\ RZ_Y: x = x0 + ceil(dx*k/dy) with k = row - y0, kept as S and error t with
\ dx*k = dy*(S-x0) - t, 0 <= t < dy; per row S += a, t -= b (a = floor(dx/dy),
\ b = dx - a*dy), borrow: t += dy, S += 1.  Installs a, b, dy into the row loop.
\ ----------------------------------------------------------------------------
.r7_esgen                  \ Y = r7_i0, X = r7_i1
{
  SEC
  LDA R_PYL,X
  SBC R_PYL,Y
  STA r7_edy
  LDA R_PYH,X
  SBC R_PYH,Y
  STA r7_edy+1
  SEC
  LDA RZ_Y
  SBC R_PYL,Y
  STA r7_ek0
  LDA #0
  SBC R_PYH,Y
  STA r7_ek0+1
  LDA R_PXL,Y
  STA r7_ex0
  LDA R_PXH,Y
  STA r7_ex0+1
  STZ r7_eneg
  SEC
  LDA R_PXL,X
  SBC R_PXL,Y
  STA r7_eadx
  LDA R_PXH,X
  SBC R_PXH,Y
  STA r7_eadx+1
  BPL pos
  DEC r7_eneg
  SEC
  LDA #0
  SBC r7_eadx
  STA r7_eadx
  LDA #0
  SBC r7_eadx+1
  STA r7_eadx+1
.pos
  \ q, r = adx / dy
  LDA r7_eadx
  CMP r7_edy
  LDA r7_eadx+1
  SBC r7_edy+1
  BCS ndiv
  LDA r7_eadx
  STA r7_er
  LDA r7_eadx+1
  STA r7_er+1
  STZ r7_eq
  STZ r7_eq+1
  BRA ddone
.ndiv
  LDA r7_eadx+1
  ORA r7_edy+1
  BNE d16
  LDA r7_edy
  STA r_v0                \ (bank 5's r_div8, which uses r_v0 and r_m0)
  LDA r7_eadx
  JSR r_div8
  STA r7_er
  STZ r7_er+1
  LDA r_m0
  STA r7_eq
  STZ r7_eq+1
  BRA ddone
.d16
  LDA r7_eadx
  STA rp_m0
  LDA r7_eadx+1
  STA rp_m1
  STZ rp_m2
  STZ rp_m3
  LDA r7_edy
  STA rp_v0
  LDA r7_edy+1
  STA rp_v1
  JSR rp_div32
  LDA rp_m0
  STA r7_eq
  LDA rp_m1
  STA r7_eq+1
  LDA rp_m2
  STA r7_er
  LDA rp_m3
  STA r7_er+1
.ddone
  LDA r7_eneg
  BNE negab
  LDA r7_eq
  STA r7_ea
  LDA r7_eq+1
  STA r7_ea+1
  LDA r7_er
  STA r7_eb
  LDA r7_er+1
  STA r7_eb+1
  BRA abdone
.negab
  LDA r7_er
  ORA r7_er+1
  BNE rnz
  SEC                     \ a = -q, b = 0
  LDA #0
  SBC r7_eq
  STA r7_ea
  LDA #0
  SBC r7_eq+1
  STA r7_ea+1
  STZ r7_eb
  STZ r7_eb+1
  BRA abdone
.rnz
  LDA r7_eq                \ a = -q-1, b = dy - r
  EOR #&FF
  STA r7_ea
  LDA r7_eq+1
  EOR #&FF
  STA r7_ea+1
  SEC
  LDA r7_edy
  SBC r7_er
  STA r7_eb
  LDA r7_edy+1
  SBC r7_er+1
  STA r7_eb+1
.abdone
  LDX r7_side4
  LDA r7_ek0
  ORA r7_ek0+1
  BNE k0nz
  LDA r7_ex0
  STA RZ_SA,X
  LDA r7_ex0+1
  STA RZ_SA+1,X
  STZ RZ_TA,X
  STZ RZ_TA+1,X
  JMP install
.k0nz                     \ clipped start: q2, r2 = adx*k / dy
  LDA r7_eadx
  STA rp_ma
  LDA r7_eadx+1
  STA rp_ma+1
  LDA r7_ek0
  STA rp_mb
  LDA r7_ek0+1
  STA rp_mb+1
  JSR rp_mul16
  LDA r7_edy
  STA rp_v0
  LDA r7_edy+1
  STA rp_v1
  JSR rp_div32
  LDX r7_side4
  LDA r7_eneg
  BNE kneg
  LDA rp_m2
  ORA rp_m3
  BEQ kz
  SEC                     \ S = x0 + q2 + 1, t = dy - r2
  LDA r7_ex0
  ADC rp_m0
  STA RZ_SA,X
  LDA r7_ex0+1
  ADC rp_m1
  STA RZ_SA+1,X
  SEC
  LDA r7_edy
  SBC rp_m2
  STA RZ_TA,X
  LDA r7_edy+1
  SBC rp_m3
  STA RZ_TA+1,X
  JMP install
.kz
  CLC                     \ S = x0 + q2, t = 0
  LDA r7_ex0
  ADC rp_m0
  STA RZ_SA,X
  LDA r7_ex0+1
  ADC rp_m1
  STA RZ_SA+1,X
  STZ RZ_TA,X
  STZ RZ_TA+1,X
  JMP install
.kneg
  SEC                     \ S = x0 - q2, t = r2
  LDA r7_ex0
  SBC rp_m0
  STA RZ_SA,X
  LDA r7_ex0+1
  SBC rp_m1
  STA RZ_SA+1,X
  LDA rp_m2
  STA RZ_TA,X
  LDA rp_m3
  STA RZ_TA+1,X
.install
  RTS
}


