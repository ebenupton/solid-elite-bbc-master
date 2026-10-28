\ ******************************************************************************
\
\ gfx-merid.asm - the circle engine: the planet's surface detail as circles on
\ its sphere (sideways RAM bank 7, after the cold area, paged as ROMSEL
\ MERIDBANK: the meridian window; docs/memory-map.md)
\
\ Every feature of a planet's surface is a circle on its sphere, the boundary
\ of the region {p : m^.p >= d}, d = r c (m^ a unit axis, c the cosine of the
\ circle's angular radius): a meridian or the equator is a great circle
\ (c = 0), a crater a small cap, a band the region between two latitude
\ circles about the spin axis. A style (gfx-planet7.asm's PF_HOOK) is a few
\ such circles and a base colour; a point's colour is the base EOR the
\ parity of the regions it is in. The beach ball is two great circles, normal
\ to roofv and sidev, with base 1 (colour B where the surface is on the same
\ side of both planes).
\
\ Each circle projects to the ellipse x = xc + a (y - yc) -/+ sqrt(D),
\ D = K0 - K2 (y - yc)^2, about (xc, yc) = (cx, cy) + d (m^x, m^y'), with
\ a = -mx my' / rho2, K2 = t (1 + my'^2 / rho2), K0 = t (r^2 - d^2),
\ t = mz^2 / rho2, rho2 = mx^2 + mz^2 (Elite's axes, y up, my' = -my; if
\ mz < 0, m and d are negated and the region is the complement: inv).
\ Along a row the side function f = m^.p - d is concave on the visible
\ hemisphere, so a row's X- crossing is a boundary iff f <= 0 at the row's
\ left limb point, X+ iff at its right one, and the row starts in the region
\ iff f > 0 at its left limb point. Along the limb f changes sign only at
\ the circle's two nodes, Ys = A -/+ sqrt(B), A = m^y' d / q2,
\ B = v (r^2 - d^2 / q2), q2 = m^x^2 + m^y'^2, v = mx^2 / (mx^2 + my^2),
\ each on the left limb or the right, so both tests and the start colour are
\ comparisons of the row with two threshold rows (T1, T2: from f's sign at
\ the top of the disc each toggles the left or the right limb's). Rows
\ Yc +/- k from the ellipse's (rounded) centre row share D(k) and
\ s = round(sqrt(D)), stepped incrementally (no multiplies per row); past the
\ ellipse (D < 0) only rows between the nodes, with one crossing, have a
\ boundary, at the centre line. A circle's crossings are inserted in order
\ into the disc layer's boundaries (R_NDN, R_NDX0-3, R_NDP; gfx-raster.asm's
\ header); with a fifth in a row the two rightmost are dropped.
\ 6-harness/planet_caps.py models this code bit for bit; for a great circle it
\ gives the beach ball's rows exactly as 6-harness/planet_analytic.py has them
\ (the demo port's src/planet4.asm).
\
\ Two entry points, each behind one stub:
\
\   * pc_circ, in game context (PF_HOOK, through G_PFHOOK, from H_CIRC): one
\     circle's record into the next slot of PCB, from the axis pcv (pf_tilt's
\     sign-magnitude words), its scale pcn, the cosine pcc and its sign
\     pcneg and the body pcbx, pcby, pcr; its part of the base colour into
\     pc_inv. It uses Elite's zero page &10-&28, which PF_HOOK saves, and
\     reads main RAM only for the quarter squares (QSL, QSH);
\
\   * PC_ROWS (the planet's records) and PC_MROWS (the moon's), in the frame
\     (bank 6's f_bounds and f_moon, through T_CAPS and T_MCAPS): the disc
\     layer's boundaries for rows R_NDT..R_NDB (spans R_NDISCL..R_NDISCR).
\     They use the rasteriser's scratch zero page &10-&27 (F_FRAME has saved
\     it).
\
\ ******************************************************************************

pm_a  = &10             \ zero page workspace (Elite's, saved and restored):
pm_b  = &14             \ multiplicand, dividend; multiplier, divisor;
pm_p  = &18             \ product, quotient; temporary
pm_tt = &20
pmi_res = &23           \ pm_isqrt's
pmi_one = &25
pmi_s = &27             \ (&27-&28)

\ A circle's record (RSZ bytes, in its slot of PCB)
R_A   = 0               \ a, 16.16 signed
R_K2  = 4               \ K2 = D(0) - D(1), 16.16
R_K0  = 8               \ K0 = D(0), 16.16
R_S0  = 12              \ s0 = round(sqrt(K0))
R_L0  = 13              \ s0^2 - s0
R_C0  = 15              \ the centre line at row Yc, to the nearest pixel
                        \ (16-bit signed: rows Yc +/- k are symmetric about it)
R_YC  = 17              \ Yc (16-bit signed)
R_F   = 19              \ the region at the top of the disc: 3 (both limbs
                        \ in it: no crossing a boundary) or 0
R_T1  = 20              \ from row T1 on the limbs in M1 (1 left, 2 right)
R_T2  = 21              \ are toggled, and from T2 those in M2 (0..192)
R_M1  = 22
R_M2  = 23              \ (M1 and M2 last: pr_c + RSZ follows them)
RSZ   = 24
PCMAX = 3               \ the planet's records (slots 0-2; the moon's in slot 3)

\ ******************************************************************************
\
\ pc_circ: one circle's record into the next slot (PC_N), from the axis pcv,
\ pcn (2^24 / the axis' nominal length >> 3: pf_tilt), the cosine pcc (0.8)
\ and its sign pcneg (bit 7), and the body (pcbx, pcby, pcr); pc_inv EOR'd
\ with its inv and its region at the top's left limb
\
\ ******************************************************************************

.pcc9
 RTS
.pc_circ
 LDA PC_N
 CMP #PCMAX+1
 BCS pcc9
 STZ pc_t
 LDX #0                 \ the magnitudes >> 2 (pf_tilt's halved vectors: the
 LDY #0                 \ beach ball's |v| >> 3), signs, non-zero flags
.pcl1
 LDA pcv+1,X
 AND #&7F
 STA pm_tt+1
 LDA pcv,X
 STA pm_tt
 ORA pm_tt+1
 BEQ pcl1a
 LDA #&80
.pcl1a
 STA pm_nz,Y
 AND pcv+1,X
 STA pm_sg,Y
 LDA pm_tt+1
 LSR A
 ROR pm_tt
 LSR A
 ROR pm_tt
 STA pv_m+1,Y
 ORA pm_tt
 TSB pc_t
 LDA pm_tt
 STA pv_m,Y
 INX
 INX
 INY
 INY
 CPY #6
 BNE pcl1
 LDA pc_t               \ (no axis: no circle)
 BEQ pcc9
 JSR pms_core           \ sx, sy, inv, t, v, a, K2
 LDX #7                 \ (a, K2 into the record)
.pcl2
 LDA pm_a32,X
 STA wr+R_A,X
 DEX
 BPL pcl2
 LDA pcn+1              \ (pcn / 2: the unit axis from the magnitudes >> 2)
 LSR A
 STA pv_cn+1
 LDA pcn
 ROR A
 STA pv_cn
 STZ pm_p+2             \ (d = 0: d^2 = 0, A9 = 0)
 STZ pm_p+3
 LDX #2
.pcl3
 STZ pc_a9,X
 DEX
 BPL pcl3
 LDA pcr                \ d = r c (8.8), and its sign once m is negated (0 if
 STA pv_r               \ d is: then only mx's sign tells the nodes' side)
 LDX pcc
 JSR pm_mul8
 STA pv_d+1
 LDA pm_m8
 STA pv_d
 ORA pv_d+1
 CMP #1
 ROR pc_dnz             \ (bit 7: d is not 0; with d = 0 the terms in d are
 STA pc_dn              \ not computed: a great circle)
 LDA pm_nz+2            \ (d = 0: hy only needs to be non-zero if my is, for
 ASL A                  \ the top and bottom)
 ROL A
 STA pv_hy
 BIT pc_dnz
 BPL pcl4z
 LDA pm_inv
 LSR A
 ROR A
 EOR pcneg
 AND #&80
 STA pc_dn
 LDX #O_M               \ the unit axis' x and y, 0.8
 JSR pc_unit
 STA pv_hx
 LDX #O_M+2
 JSR pc_unit
 STA pv_hy
.pcl4
 LDX #0                 \ the centre (xc, yc) = (cx, cy) + d (hx, hy) (16.8),
.pcl4a                  \ rounded: C0, the centre line at row Yc, and Yc (rows
 PHX                    \ Yc +/- k from the ellipse's centre row)
 TXA
 LSR A
 TAY
 LDA pm_sx,Y
 PHA
 TXA
 CLC
 ADC #O_HX
 TAY
 PLA
 JSR pc_off
 PLX
 LDA pc_o
 CMP #&80
 LDA pc_o+1
 ADC pcbx,X
 STA wr+R_C0,X
 LDA pc_o+2
 ADC pcbx+1,X
 STA wr+R_C0+1,X
 INX
 INX
 CPX #4
 BNE pcl4a
 BRA pcl4y
.pcl4z
 LDX #3                 \ (d = 0: C0 = cx, Yc = cy)
.pcl4w
 LDA pcbx,X
 STA wr+R_C0,X
 DEX
 BPL pcl4w
 BRA pcl5
.pcl4y
 LDA pm_p+1             \ (Y0 = |d hy| >> 8, for A)
 STA pm_Y2+1
 LDA pm_p+2
 STA pm_Y2+2
 BIT pc_dnz
 BPL pcl5
 LDX #O_D               \ d^2 >> 16
 TXA
 TAY
 JSR pc_mul
.pcl5
 LDA pm_p+2             \ (d^2 >> 16, or 0)
 STA pv_dd
 LDA pm_p+3
 STA pv_dd+1
 LDA pcr                \ r^2
 TAX
 JSR pm_mul8
 STA pv_r2+1
 LDA pm_m8
 STA pv_r2
 SEC                    \ K0 = (r^2 - (d^2 >> 16)) t
 SBC pv_dd
 STA pv_rc
 LDA pv_r2+1
 SBC pv_dd+1
 STA pv_rc+1
 LDX #O_RC
 LDY #O_T
 JSR pc_mul
 LDX #3
.pcl6
 LDA pm_p,X
 STA wr+R_K0,X
 DEX
 BPL pcl6
 LDA wr+R_K0+2          \ s0 = round(sqrt(K0)): f = isqrt(K0's integer part),
 STA pm_tt              \ s0 = f + 1 iff the remainder > f, or = f and K0's
 LDA wr+R_K0+3          \ fraction >= 1/4
 STA pm_tt+1
 JSR pm_isqrt
 TAX
 LDA pm_tt+1
 BNE pcs1
 CPX pm_tt
 BCC pcs1
 BNE pcs2
 LDA wr+R_K0+1
 CMP #&40
 BCC pcs2
.pcs1
 INX
.pcs2
 STX wr+R_S0            \ L0 = s0^2 - s0
 TXA
 JSR pm_mul8
 STA wr+R_L0+1
 LDA pm_m8
 SEC
 SBC wr+R_S0
 STA wr+R_L0
 BCS P%+5
 DEC wr+R_L0+1
 BIT pc_dnz             \ the nodes: q2 = hx^2 + hy^2 (0.16; 0 saturates),
 BMI pcq                \ A = Y0 / q2, e2 = d^2 / q2 (d = 0: A9 = 0, e2 = 0,
 LDA pv_r2              \ so B = r^2 v)
 STA pv_rc
 LDA pv_r2+1
 STA pv_rc+1
 JMP pcnm
.pcq
 LDA pv_hx
 TAX
 JSR pm_mul8
 STA pm_X2+1
 LDA pm_m8
 STA pm_X2
 LDA pv_hy
 TAX
 JSR pm_mul8
 TAY
 LDA pm_m8
 CLC
 ADC pm_X2
 STA pm_X2
 TYA
 ADC pm_X2+1
 STA pm_X2+1
 LDA #0
 STA pm_X2+3
 STA pm_Y2
 STA pm_Y2+3
 ROL A
 STA pm_X2+2
 LDX #pm_Y2-pm_P
 LDY #pm_X2-pm_P
 JSR pm_fdiv
 LDA pm_p+3             \ A9 = min(A, &FFFFFF) >> 7 (1/512 pixels, 24-bit
 BEQ pcn1               \ signed: dn EOR sy)
 LDA #&FF
 STA pm_p
 STA pm_p+1
 STA pm_p+2
.pcn1
 ASL pm_p
 ROL pm_p+1
 ROL pm_p+2
 LDA #0
 ROL A
 STA pc_a9+2
 LDA pm_p+1
 STA pc_a9
 LDA pm_p+2
 STA pc_a9+1
 LDX #pc_a9-pc_o
 LDA pc_dn
 EOR pm_sy
 JSR pc_sgn
 LDA pv_dd
 STA pm_Y2
 LDA pv_dd+1
 STA pm_Y2+1
 STZ pm_Y2+2
 LDX #pm_Y2-pm_P
 LDY #pm_X2-pm_P
 JSR pm_fdiv
.pcn3
 LDA pm_p+2             \ B = (r^2 - e2) v (16.16), 0 if e2 >= r^2
 ORA pm_p+3
 BNE pcn2
 SEC
 LDA pv_r2
 SBC pm_p
 STA pv_rc
 LDA pv_r2+1
 SBC pm_p+1
 STA pv_rc+1
 BCS pcnm
.pcn2
 STZ pv_rc
 STZ pv_rc+1
.pcnm
 LDX #O_RC
 LDY #O_V
 JSR pc_mul
 LDA pm_p+2             \ S = 256 f, f = isqrt(B's integer part);
 STA pm_tt              \ S9 = 2 S + (B > S^2: the remainder or B's
 LDA pm_p+3             \ fraction not 0)
 STA pm_tt+1
 JSR pm_isqrt
 STA pc_s9+1
 STZ pc_s9
 LDA pm_tt
 ORA pm_tt+1
 ORA pm_p
 ORA pm_p+1
 CMP #1
 ROL pc_s9
 ROL pc_s9+1
 LDA #0
 ROL A
 STA pc_s9+2
 \ f at the top (Ys = -r: -my' r - d) and the bottom (my' r - d): each
 \ limb's region there (F: both or neither); if they differ, the upper node
 \ toggles the right limb when mx and my' have the same sign, else the left,
 \ and the lower one the other; if not, both the same limb, the right if
 \ mx d > 0. From the top down, a limb leaving the region at a node's row Yn
 \ does so from row floor(Yn) + 1, one entering it from ceil(Yn) (f = 0 is
 \ outside): T = cy + (n + 512 or 511) >> 9, 0..192, the nodes n = A9 -/+ S9
 \ (1/512 pixels from cy). With h = |my'| r: -h > D iff d < 0 and h < |d|;
 \ h > D iff d < 0, or h > d; the top is the first if my' >= 0, the bottom
 \ the second, and the other way round if my' < 0
 LDX #O_HY
 LDY #O_R
 JSR pc_mul
 LDY #0
 BIT pc_dn
 BMI pcm0
 LDA pv_d               \ d >= 0: h > D iff d < h; -h > D no
 CMP pm_p
 LDA pv_d+1
 SBC pm_p+1
 LDA #0
 ROL A
 EOR #1
 BRA pcm4
.pcm0
 LDA pm_p               \ d < 0: h > D, and -h > D iff h < d
 CMP pv_d
 LDA pm_p+1
 SBC pv_d+1
 LDA #1
 BCS pcm4
 INY
.pcm4                   \ A = h > D, Y = -h > D
 BIT pm_sy
 BMI pcm5
 STY pc_t               \ my' >= 0: top = (-h > D), bottom = (h > D)
 BRA pcm6
.pcm5
 STA pc_t               \ my' < 0: top = (h > D), bottom = (-h > D)
 TYA
.pcm6                   \ pc_t = top, A = bottom
 EOR pc_t
 STA pc_tb              \ (bit 0: they differ)
 LDA pc_t
 BEQ P%+4
 LDA #3
 STA wr+R_F
 STA pc_st
 BIT pc_dnz             \ (d = 0: the nodes' rows are -/+ w, as the upper
 BPL pcm1               \ node toggles the right limb when mx and my' have
 LDA pc_tb              \ the same sign)
 LSR A
 BCS pcm1
 LDA pm_sx
 EOR pc_dn
 JSR pc_rl
 STA wr+R_M1
 BRA pcm2
.pcm1
 LDA pm_sx
 EOR pm_sy
 JSR pc_rl
 STA wr+R_M1
 EOR #3
.pcm2
 STA wr+R_M2
 LDY #0                 \ the nodes n1 = A9 - S9 (the upper), n2 = A9 + S9
 SEC
.pct0
 LDA pc_a9,Y
 SBC pc_s9,Y
 STA pc_n,Y
 INY
 TYA
 EOR #3
 BNE pct0
 LDY #0
 CLC
.pct0a
 LDA pc_a9,Y
 ADC pc_s9,Y
 STA pc_n+3,Y
 INY
 TYA
 EOR #3
 BNE pct0a
 LDX #0
 LDY #0
.pct1
 LDA wr+R_M1,Y          \ (C: the limb outside the region, adding 512)
 AND pc_st
 EOR wr+R_M1,Y
 CMP #1
 LDA pc_n,X
 ADC #&FF
 LDA pc_n+1,X
 ADC #1
 STA pc_v
 LDA pc_n+2,X
 ADC #0
 CMP #&80
 ROR A
 ROR pc_v
 STA pc_v+1
 CLC
 LDA pc_v
 ADC pcby
 STA pc_v
 LDA pc_v+1
 ADC pcby+1
 BMI pct2
 BNE pct3
 LDA pc_v
 CMP #193
 BCC pct4
.pct3
 LDA #192
 BRA pct4
.pct2
 LDA #0
.pct4
 STA wr+R_T1,Y
 LDA wr+R_M1,Y
 EOR pc_st
 STA pc_st
 LDX #3
 INY
 CPY #2
 BNE pct1
 LDA wr+R_F             \ the base colour: inv EOR the top's left limb's region
 AND #1
 EOR pm_inv
 EOR pc_inv
 STA pc_inv
 LDA pc_s9              \ no node (S9 = 0), one limb toggled twice and both in
 ORA pc_s9+1            \ the region at the top: every row is in the region,
 ORA pc_s9+2            \ and there is no record
 BNE pcy2
 LDA wr+R_M1
 EOR wr+R_M2
 BNE pcy2
 LDA wr+R_F
 CMP #3
 BEQ pcy9
.pcy2
 LDX PC_N               \ the record into its slot
 INC PC_N
 LDY pcb_o+1,X
 LDX #RSZ-1
.pcy0
 DEY
 LDA wr,X
 STA PCB,Y
 DEX
 BPL pcy0
.pcy9
 RTS

\ pc_rl: A = 2 (the right limb) if A bit 7 is clear, else 1 (the left)

.pc_rl
 ASL A
 LDA #2
 BCC P%+4
 LDA #1
 RTS

\ pc_unit: A = min(255, pv+X (the magnitude >> 2) pcn / 2 >> 16) (|m| times
\ 2^24 over its nominal length: Elite's vectors are of length &6000), 0.8;
\ at least 1 if the component is not zero

.pc_unit
 LDA pm_nz-O_M,X
 STA pc_t
 LDY #O_CN
 JSR pc_mul
 LDA pm_p+3
 BEQ pcu1
 LDA #255
 RTS
.pcu1
 LDA pm_p+2
 BNE pcu2
 LDA pc_t
 ASL A
 ROL A
.pcu2
 RTS

\ pc_off: pc_o = (d h) >> 8 (16.8, 24-bit; h = pv+Y), negated if A EOR dn is
\ negative

.pc_off
 STA pc_t
 STZ pm_p+1
 STZ pm_p+2
 BIT pc_dnz
 BPL pco1
 LDX #O_D
 JSR pc_mul
.pco1
 LDA pm_p+1
 STA pc_o
 LDA pm_p+2
 STA pc_o+1
 STZ pc_o+2
 LDX #0
 LDA pc_t
 EOR pc_dn

\ pc_sgn: the 24-bit pc_o + X negated if A bit 7 is set (Y kept)

.pc_sgn
 ASL A
 BCC pcg9
 PHY
 LDY #3
 SEC
.pcg1
 LDA #0
 SBC pc_o,X
 STA pc_o,X
 INX
 DEY
 BNE pcg1
 PLY
.pcg9
 RTS

\ pp_neg: pm_p (4 bytes) negated

.pp_neg
 LDX #0
 LDY #4
 SEC
.ppn1
 LDA #0
 SBC pm_p,X
 STA pm_p,X
 INX
 DEY
 BNE ppn1
 RTS

\ pc_mul: pm_p (4) = pv+X (2) * pv+Y (2), unsigned

.pc_mul
 LDA pv,X
 STA pm_a
 LDA pv+1,X
 STA pm_a+1
 LDA pv,Y
 STA pm_b
 LDA pv+1,Y
 STA pm_b+1
 JMP pm_mul16

\ pms_core: from the magnitudes and signs in pv_m, pm_sg and pm_nz, the
\ circle's orientation terms: pm_sx, pm_sy, pm_inv, t (pm_tq), v (pm_v), a
\ (pm_a32) and K2 (pm_K2)

.pms_core
 LDA pm_sg              \ sx = sign(mx), sy = sign(my') = -sign(my)
 STA pm_sx
 LDA pm_sg+2
 EOR pm_nz+2
 STA pm_sy
 LDA #0
 STA pm_inv
 LDA pm_sg+4            \ mz < 0: negate m (inverting this circle's colour)
 BPL pms3
 INC pm_inv
 LDA pm_sx
 EOR pm_nz
 STA pm_sx
 LDA pm_sy
 EOR pm_nz+2
 STA pm_sy
.pms3
 LDX #0                 \ X2 = mx^2, Y2 = my^2, Z2 = mz^2, XY = mx my
 LDY #0
 JSR pc_mul
 LDX #pm_X2-pm_P
 JSR pms_stp
 LDX #2
 LDY #2
 JSR pc_mul
 LDX #pm_Y2-pm_P
 JSR pms_stp
 LDX #4
 LDY #4
 JSR pc_mul
 LDX #pm_Z2-pm_P
 JSR pms_stp
 LDX #0
 LDY #2
 JSR pc_mul
 LDX #pm_XY-pm_P
 JSR pms_stp
 CLC                    \ R2 = X2 + Z2, Q2 = X2 + Y2 (0 only when the
                        \ dividend is too: pm_fdiv gives 0, or saturates)
 LDX #0
 LDY #3
.pms4
 LDA pm_X2,X
 ADC pm_Z2,X
 STA pm_R2,X
 INX
 DEY
 BPL pms4
 CLC
 LDX #0
 LDY #3
.pms5
 LDA pm_X2,X
 ADC pm_Y2,X
 STA pm_Q2,X
 INX
 DEY
 BPL pms5
 LDX #pm_Z2-pm_P        \ t = Z2 / R2 (0.16)
 LDY #pm_R2-pm_P
 JSR pm_fdiv16
 STA pm_tq
 STX pm_tq+1
 LDX #pm_X2-pm_P        \ v = X2 / Q2 (0.16)
 LDY #pm_Q2-pm_P
 JSR pm_fdiv16
 STA pm_v
 STX pm_v+1
 LDX #pm_XY-pm_P        \ |a| = XY / R2 (8.16)
 LDY #pm_R2-pm_P
 JSR pm_fdiv
 LDA pm_p+3             \ (at most &FF.FFFF)
 BEQ pms5a
 LDA #&FF
 STA pm_p
 STA pm_p+1
 STA pm_p+2
 LDA #0
 STA pm_p+3
.pms5a
 LDA pm_sx              \ a = -mx my' / rho2: negative iff mx, my' have the
 EOR pm_sy              \ same sign
 BMI pms6
 JSR pp_neg
.pms6
 LDX #3
.pms7
 LDA pm_p,X
 STA pm_a32,X
 DEX
 BPL pms7
 LDX #pm_Y2-pm_P        \ u = Y2 / R2 (16.16)
 LDY #pm_R2-pm_P
 JSR pm_fdiv
 LDA pm_p               \ K2 = t (1 + u) = t u_hi + t + (t u_lo) / 65536
 STA pm_ulo
 LDA pm_p+1
 STA pm_ulo+1
 LDA pm_p+2
 STA pm_a
 LDA pm_p+3
 STA pm_a+1
 JSR pms_bt
 JSR pm_mul16
 CLC
 LDA pm_p
 ADC pm_tq
 STA pm_K2
 LDA pm_p+1
 ADC pm_tq+1
 STA pm_K2+1
 LDA pm_p+2
 ADC #0
 STA pm_K2+2
 LDA pm_p+3
 ADC #0
 STA pm_K2+3
 LDA pm_ulo
 STA pm_a
 LDA pm_ulo+1
 STA pm_a+1
 JSR pms_bt
 JSR pm_mul16
 CLC
 LDA pm_K2
 ADC pm_p+2
 STA pm_K2
 LDA pm_K2+1
 ADC pm_p+3
 STA pm_K2+1
 BCC pms8
 INC pm_K2+2
 BNE pms8
 INC pm_K2+3
.pms8
 RTS
.pms_bt                  \ pm_b = t
 LDA pm_tq
 STA pm_b
 LDA pm_tq+1
 STA pm_b+1
 RTS

.pms_stp                 \ pm_P+X (4 bytes) = pm_p
 LDY #0
.pmst1
 LDA pm_p,Y
 STA pm_P,X
 INX
 INY
 CPY #4
 BNE pmst1
 RTS

\ pm_fdiv: pm_p = U / V as 16.16 with a 12-bit mantissa (U = pm_P+X, V =
\ pm_P+Y, 4 bytes each, V > 0): while either is >= 2^24 both lose their low
\ byte; each is normalised (shifted left until bit 23 is set, eu and ev
\ times) and its top 16 bits taken, U' and V'; q = floor(U' 2^11 / V')
\ (12 steps: 2^10 <= q < 2^12) is shifted left by 5 + ev - eu (right if
\ negative), saturating at 2^32 - 1 (as when V loses all its bits). U = 0
\ gives 0. (planet_caps.fdiv)
\ pm_fdiv16: the same clamped to 16 bits, in X (high) and A (low).

.pm_fdiv16
 JSR pm_fdiv
 LDA pm_p+2
 ORA pm_p+3
 BEQ pfd16
 LDA #&FF
 TAX
 RTS
.pfd16
 LDA pm_p
 LDX pm_p+1
 RTS

.pm_fdiv
 LDA pm_P,X             \ U -> pm_a, V -> pm_b
 STA pm_a
 LDA pm_P+1,X
 STA pm_a+1
 LDA pm_P+2,X
 STA pm_a+2
 LDA pm_P+3,X
 STA pm_a+3
 LDA pm_P,Y
 STA pm_b
 LDA pm_P+1,Y
 STA pm_b+1
 LDA pm_P+2,Y
 STA pm_b+2
 LDA pm_P+3,Y
 STA pm_b+3
 LDA #0
 STA pm_p
 STA pm_p+1
 STA pm_p+2
 STA pm_p+3
.pfd1
 LDA pm_a               \ U = 0: 0
 ORA pm_a+1
 ORA pm_a+2
 ORA pm_a+3
 BNE P%+3
 RTS
 LDA pm_b               \ V = 0 (or gone): saturated
 ORA pm_b+1
 ORA pm_b+2
 ORA pm_b+3
 BNE P%+5
 JMP pfd_sat
 LDA pm_a+3             \ either >= 2^24: both lose a byte
 ORA pm_b+3
 BEQ pfd2
 LDX #0
.pfd1a
 LDA pm_a+1,X
 STA pm_a,X
 LDA pm_b+1,X
 STA pm_b,X
 INX
 CPX #3
 BNE pfd1a
 LDA #0
 STA pm_a+3
 STA pm_b+3
 BEQ pfd1
.pfd2
 LDX #pm_a              \ normalise U, V: X = their zero page address
 JSR pfd_norm
 STY pm_eu
 LDX #pm_b
 JSR pfd_norm
 TYA                    \ the shift 5 + ev - eu
 CLC
 ADC #5
 SEC
 SBC pm_eu
 STA pm_eu
 LDY #12                \ q = floor(U' 2^11 / V'), U' and V' in bytes 1-2
 CLC                    \ (R = U', its bit 16 in C)
.pfd5
 BCS pfd6               \ R >= 2^16 > V': subtract
 LDA pm_a+1
 CMP pm_b+1
 LDA pm_a+2
 SBC pm_b+2
 BCC pfd7
.pfd6
 LDA pm_a+1
 SBC pm_b+1
 STA pm_a+1
 LDA pm_a+2
 SBC pm_b+2
 STA pm_a+2
 SEC
.pfd7
 ROL pm_p               \ the quotient bit (C)
 ROL pm_p+1
 ASL pm_a+1             \ R <<= 1
 ROL pm_a+2
 DEY
 BNE pfd5
 LDY pm_eu              \ shift q
 BPL pfd8
.pfd7r
 LSR pm_p+1
 ROR pm_p
 INY
 BNE pfd7r
 RTS
.pfd8
 CPY #8
 BCC pfd9
 LDA pm_p+3             \ a byte at a time
 BNE pfd_sat
 LDA pm_p+2
 STA pm_p+3
 LDA pm_p+1
 STA pm_p+2
 LDA pm_p
 STA pm_p+1
 LDA #0
 STA pm_p
 TYA
 SBC #8                 \ (C set)
 TAY
 JMP pfd8
.pfd9
 DEY
 BMI pfd10
 ASL pm_p
 ROL pm_p+1
 ROL pm_p+2
 ROL pm_p+3
 BCC pfd9
.pfd_sat
 LDA #&FF
 STA pm_p
 STA pm_p+1
 STA pm_p+2
 STA pm_p+3
.pfd10
 RTS

.pfd_norm               \ the 24-bit value at zero page X (non-zero): shift
 LDY #0                 \ left until bit 23 is set; Y = the shifts
.pfn1
 LDA 2,X
 BNE pfn2
 LDA 1,X                \ a byte at a time
 STA 2,X
 LDA 0,X
 STA 1,X
 LDA #0
 STA 0,X
 TYA
 CLC
 ADC #8
 TAY
 BNE pfn1
.pfn2
 BMI pfn3
 ASL 0,X
 ROL 1,X
 ROL 2,X
 INY
 LDA 2,X
 BPL pfn2
.pfn3
 RTS

\ pm_mul16: pm_p (4) = pm_a (2) * pm_b (2), unsigned, from four 8 x 8
\ products (Elite's quarter-square tables)

.pm_mul16
 LDA pm_a
 LDX pm_b
 JSR pm_mul8
 STA pm_p+1
 LDA pm_m8
 STA pm_p
 LDA pm_a+1
 LDX pm_b+1
 JSR pm_mul8
 STA pm_p+3
 LDA pm_m8
 STA pm_p+2
 LDA pm_a
 LDX pm_b+1
 JSR pm_mul8
 JSR pmm_add
 LDA pm_a+1
 LDX pm_b
 JSR pm_mul8
.pmm_add                \ pm_p += (A pm_m8) << 8
 TAY
 LDA pm_m8
 CLC
 ADC pm_p+1
 STA pm_p+1
 TYA
 ADC pm_p+2
 STA pm_p+2
 BCC P%+4
 INC pm_p+3
 RTS

.pm_mul8                \ (A pm_m8) = A * X by quarter squares: QS(A + X) -
 STA pm_m8              \ QS(|A - X|), QS(n) = n^2 DIV 4 (QSL, QSH)
 TXA
 SEC
 SBC pm_m8
 BCS pmq1
 EOR #&FF
 ADC #1
.pmq1
 TAY                    \ Y = |A - X|
 TXA
 CLC
 ADC pm_m8
 TAX                    \ X = A + X, C = its bit 8
 BCS pmq2
 LDA QSL,X              \ (bankcheck: ok: game context)
 SEC
 SBC QSL,Y              \ (bankcheck: ok)
 STA pm_m8
 LDA QSH,X              \ (bankcheck: ok)
 SBC QSH,Y              \ (bankcheck: ok)
 RTS
.pmq2
 LDA QSL+256,X          \ (bankcheck: ok)
 SEC
 SBC QSL,Y              \ (bankcheck: ok)
 STA pm_m8
 LDA QSH+256,X          \ (bankcheck: ok)
 SBC QSH,Y              \ (bankcheck: ok)
 RTS

\ pm_isqrt: A = floor(sqrt(pm_tt)) (16-bit), pm_tt = the remainder pm_tt - A^2:
\ a bit at a time, the candidates' squares from the quarter-square table
\ (c^2 = 4 f(c) + (c AND 1))

.pm_isqrt
 LDA #0
 STA pmi_res
 LDA #&80
 STA pmi_one
.pis1
 LDA pmi_res
 ORA pmi_one
 TAX
 JSR pis_sq
 LDA pm_tt
 CMP pmi_s
 LDA pm_tt+1
 SBC pmi_s+1
 BCC pis2
 STX pmi_res
.pis2
 LSR pmi_one
 BNE pis1
 LDX pmi_res
 JSR pis_sq
 LDA pm_tt
 SEC
 SBC pmi_s
 STA pm_tt
 LDA pm_tt+1
 SBC pmi_s+1
 STA pm_tt+1
 LDA pmi_res
 RTS

.pis_sq                 \ pmi_s = X^2
 LDA QSL,X              \ (bankcheck: ok: game context)
 ASL A
 STA pmi_s
 LDA QSH,X              \ (bankcheck: ok)
 ROL A
 ASL pmi_s
 ROL A
 STA pmi_s+1
 TXA
 AND #1
 ORA pmi_s
 STA pmi_s
 RTS
\ ******************************************************************************
\
\ PC_ROWS (the planet: slots 0 .. PC_N - 1, base colour pc_inv), PC_MROWS
\ (the moon: slots PCMAX .. MN_N - 1, MN_INV): the disc layer's boundaries
\ for rows R_NDT..R_NDB (spans R_NDISCL..R_NDISCR). Every row starts with
\ no boundary and the base colour; then each record in turn: its left limb's
\ toggles flip the start colour of the rows from T1 or T2 down, and, unless
\ every row is wholly outside its region, its rows from Yc out, down and up.
\ Called by f_bounds and f_moon (bank 6) through T_CAPS and T_MCAPS, during
\ the frame, with this bank paged; it uses the rasteriser's scratch zero page
\ &10-&27 (F_FRAME has saved it).
\
\ ******************************************************************************

ZD  = &10               \ D(k) / 2, 16.16 (its low byte is not used)
ZT0 = &10               \ (pr_nx's, before the records: the colour, the row,
ZT1 = &11               \ the next toggle)
ZT2 = &12
ZDL = &14               \ (D(k) - D(k+1)) / 2, 16.16, saturated
ZCD = &18               \ the centre line, 16.16 signed: row Yc + k
ZC2 = &1C               \ 2 C0 (16-bit)
pr_H = &10              \ (s^2 - s) / 2: its low byte (ZD's, not used once
pr_Hh = &1E             \ halved) and its high byte
pr_t = &1F              \ a row's flags (pr_row, pr_side)
mt_x = &23              \ (mpi)
ZK  = &20               \ k
ZYD = &21               \ Yc + k, Yc - k (their low bytes)
ZYU = &22
ZC  = &24               \ the row's centre, ceil(C)
ZS  = &26               \ s = round(sqrt(D(k)))
ZSS = &27               \ the half-chord used: s, or 0 once past

.PC_MROWS
 LDX #PCMAX
 LDY MN_N
 LDA MN_INV
 BRA pcr0
.PC_ROWS
 LDX #0
 LDY PC_N
 LDA pc_inv
.pcr0
 STX pr_n
 STY pr_end
 PHA
 LDY #0                 \ the records' left limb toggles: the start colour of
.pcr1                   \ the rows from T on flipped (pr_lt, pr_lc of them)
 CPX pr_end
 BCS pcr4
 PHX
 LDA pcb_o,X
 TAX
 JSR pcr1a
 INX
 JSR pcr1a
 PLX
 INX
 BRA pcr1
.pcr1a
 LDA PCB+R_M1,X
 LSR A
 BCC pcr1b
 LDA PCB+R_T1,X
 STA pr_lt,Y
 INY
.pcr1b
 RTS
.pcr4
 STY pr_lc
 PLA                    \ every row: no boundary, the base colour EOR the
 LDX R_NDT              \ toggles so far
 JSR pr_nx
.pcr5
 STA R_NDP,X
 STZ R_NDN,X
 CPX R_NDB
 BCS pcr2
 INX
 CPX ZT2
 BCC pcr5
 JSR pr_nx
 BRA pcr5

\ pr_nx: A = the colour A EOR a toggle for each of pr_lt <= X (each then
\ taken out); ZT2 = the least left, or 255

.pr_nx
 STA ZT0
 STX ZT1
 LDA #255
 STA ZT2
 LDY pr_lc
.pnx1
 DEY
 BMI pnx9
 LDA pr_lt,Y
 CMP ZT1
 BEQ pnx2
 BCS pnx3
.pnx2
 LDA #255
 STA pr_lt,Y
 LDA ZT0
 EOR #1
 STA ZT0
 BRA pnx1
.pnx3
 CMP ZT2
 BCS pnx1
 STA ZT2
 BRA pnx1
.pnx9
 LDA ZT0
 RTS

.pcr2
 LDX pr_n
 CPX pr_end
 BCC pcr3
 RTS
.pcr3
 INC pr_n
 LDY pcb_o+1,X          \ the record
 LDX #RSZ-1
.prc1
 DEY
 LDA PCB,Y
 STA pr_c,X
 DEX
 BPL prc1
 LDA pr_c+R_T1          \ the rows with one crossing at most: tlo..thi - 1
 LDX pr_c+R_T2
 CMP pr_c+R_T2
 BCC pcr7
 STX pr_lo
 STA pr_hi
 BCS pcr8
.pcr7
 STA pr_lo
 STX pr_hi
.pcr8
.pcr9
 LDX #3                 \ D/2 = K0/2, dl = K2/2, C = C0, 2 C0
.pcr10
 LDA pr_c+R_K0,X
 STA ZD,X
 LDA pr_c+R_K2,X
 STA ZDL,X
 DEX
 BPL pcr10
 STZ ZCD
 STZ ZCD+1
 LDA pr_c+R_C0
 STA ZCD+2
 ASL A
 STA ZC2
 LDA pr_c+R_C0+1
 STA ZCD+3
 ROL A
 STA ZC2+1
 LSR ZD+3
 ROR ZD+2
 ROR ZD+1
 ROR ZD
 LSR ZDL+3
 ROR ZDL+2
 ROR ZDL+1
 ROR ZDL
 LDX #0                 \ K2 and a into the row loop's ADC #s
 LDY #0                 \ (six bytes apart)
.pcr11
 LDA pr_c+R_K2,Y
 STA prk0+1,X
 LDA pr_c+R_A,Y
 STA pra0+1,X
 TXA
 CLC
 ADC #6
 TAX
 INY
 CPY #4
 BNE pcr11
 LDA pr_c+R_YC          \ the rows Yc + k and Yc - k (their low bytes: the
 STA ZYD                \ rows, when they are on the screen)
 STA ZYU
 STZ ZK
 LDA pr_c+R_S0
 STA ZS
 LDA pr_c+R_L0+1        \ H = L0 / 2
 LSR A
 STA pr_Hh
 LDA pr_c+R_L0
 ROR A
 STA pr_H
 STZ ZSS
 LDA pr_c+R_F           \ the limbs' regions on row Yc + k: F, toggled by M1
 STA pr_bd              \ from k = T1 - Yc, by M2 from T2 - Yc; on row Yc - k:
 EOR pr_c+R_M1          \ F EOR M1 EOR M2, toggled by M1 from k = Yc + 1 - T1,
 EOR pr_c+R_M2          \ by M2 from Yc + 1 - T2 (pr_tk, clamped to 0..255)
 STA pr_bu
 LDX #1                 \ (T1, T2, then NDT and NDB + 1: the rows on the
.pcr12                  \ screen from k = NDT - Yc down, Yc - NDB up)
 LDA pr_c+R_T1,X
 STA pr_tk,X
 STA pr_tk+4,X
 DEX
 BPL pcr12
 LDA R_NDT
 STA pr_tk+2
 LDA R_NDB
 INC A
 STA pr_tk+6
 LDX #2
.pcr13
 LDA pr_tk,X
 JSR pr_kd
 STA pr_tk,X
 LDA pr_tk+4,X
 JSR pr_ku
 STA pr_tk+4,X
 DEX
 BPL pcr13
 LDA pr_tk+6            \ (up: k >= 1)
 BNE P%+5
 INC pr_tk+6
 STZ pr_past
 JSR pr_lim

.pr_loop
 LDA ZK                 \ a segment's end: the flags, or done
 CMP pr_ke
 BCC prl1
 JSR pr_seg
 BCC prl1
 JMP pcr2
.prl1
 BIT pr_past            \ s = round(sqrt(D)): s drops while D/2 < H + 1/8
 BMI prl3               \ (D < s^2 - s + 1/4)
.prs1
 LDA ZS
 BEQ prs9
 LDA ZD+1
 CMP #&20
 LDA ZD+2
 SBC pr_H
 LDA ZD+3
 SBC pr_Hh
 BCS prs9
 DEC ZS                 \ H -= s (the new s)
 LDA pr_H
 SEC
 SBC ZS
 STA pr_H
 BCS prs1
 DEC pr_Hh
 BCC prs1
.prs9
 LDA ZS
 STA ZSS
.prl3
 BIT pr_fd              \ row Yc + k: centre ceil(C)
 BPL prl4
 LDA ZCD
 ORA ZCD+1
 CMP #1
 LDA ZCD+2
 ADC #0
 STA ZC
 LDA ZCD+3
 ADC #0
 STA ZC+1
 LDX ZYD
 LDA pr_fd
 JSR pr_row
.prl4
 BIT pr_fu              \ row Yc - k: centre ceil(2 C0 - C) = 2 C0 - floor(C)
 BPL prl5
 SEC
 LDA ZC2
 SBC ZCD+2
 STA ZC
 LDA ZC2+1
 SBC ZCD+3
 STA ZC+1
 LDX ZYU
 LDA pr_fu
 JSR pr_row
.prl5
 BIT pr_past            \ D -= dl, dl += K2 (past the ellipse once D < 0)
 BMI prl7
 SEC                    \ (D is kept to 1/256: its low byte is not used)
 LDA ZD+1
 SBC ZDL+1
 STA ZD+1
 LDA ZD+2
 SBC ZDL+2
 STA ZD+2
 LDA ZD+3
 SBC ZDL+3
 STA ZD+3
 BCS prl6
 JSR pr_pst
 BRA prl7
.prl6
 CLC                    \ (the ADC #s: K2, patched)
 LDA ZDL
.prk0
 ADC #0
 STA ZDL
 LDA ZDL+1
.prk1
 ADC #0
 STA ZDL+1
 LDA ZDL+2
.prk2
 ADC #0
 STA ZDL+2
 LDA ZDL+3
.prk3
 ADC #0
 STA ZDL+3
 BCC prl7
 LDA #&FF
 STA ZDL
 STA ZDL+1
 STA ZDL+2
 STA ZDL+3
.prl7
 CLC                    \ C += a (the ADC #s: a, patched)
 LDA ZCD
.pra0
 ADC #0
 STA ZCD
 LDA ZCD+1
.pra1
 ADC #0
 STA ZCD+1
 LDA ZCD+2
.pra2
 ADC #0
 STA ZCD+2
 LDA ZCD+3
.pra3
 ADC #0
 STA ZCD+3
 INC ZYD
 DEC ZYU
 INC ZK
 JMP pr_loop
ASSERT prk1 = prk0 + 6 AND prk3 = prk0 + 18 AND pra3 = pra0 + 18

\ pr_pst: past the ellipse: s = 0 from now on, and only the rows with one
\ crossing at most (a new segment next). pr_lim: the last rows the loop may
\ reach (pr_tk + 3, pr_tk + 7): down, NDB (past, thi - 1); up, NDT (past,
\ tlo)

.pr_pst
 LDA #&80
 STA pr_past
 STZ ZSS
.pr_lim
 STZ pr_ke
 LDA R_NDB
 INC A
 BIT pr_past
 BPL prm1
 CMP pr_hi
 BCC prm1
 LDA pr_hi
.prm1
 JSR pr_kd
 CMP pr_tk+2            \ (not below the first)
 BCS P%+5
 LDA pr_tk+2
 STA pr_tk+3
 LDA R_NDT
 BIT pr_past
 BPL prm2
 CMP pr_lo
 BCS prm2
 LDA pr_lo
.prm2
 JSR pr_ku
 CMP pr_tk+6
 BCS P%+5
 LDA pr_tk+6
 STA pr_tk+7
 RTS

\ pr_seg: at k (ZK): done (C set) once both sides are past their last rows;
\ else (C clear) each side's flags (pr_fd, pr_fu: bit 7 the row is on the
\ screen with a limb outside the region, bits 0-1 the limbs in it) and the
\ next k at which any changes (pr_ke)

.pr_seg
 LDA ZK
 CMP pr_tk+3
 BCC pre1
 CMP pr_tk+7
 BCS pre9
.pre1
 LDA pr_bd
 LDX #0
 JSR pr_side
 STA pr_fd
 LDA pr_bu
 LDX #4
 JSR pr_side
 STA pr_fu
 LDA #255
 STA pr_ke
 LDX #7
.pre2
 LDA pr_tk,X
 CMP ZK
 BCC pre3
 BEQ pre3
 CMP pr_ke
 BCS pre3
 STA pr_ke
.pre3
 DEX
 BPL pre2
 CLC
.pre9
 RTS

.pr_side                \ A = the side's flags at k (X = 0 down, 4 up): the
 STA pr_t               \ base EOR M1, M2 from its first two thresholds, and
 LDY #0                 \ bit 7 between the last two (pr_tm: M1, M2, &80, &80)
.prd1
 LDA ZK
 CMP pr_tk,X
 BCC prd2
 LDA pr_t
 EOR pr_tm,Y
 STA pr_t
.prd2
 INX
 INY
 CPY #4
 BNE prd1
 LDA pr_t               \ (both limbs in the region: inactive)
 AND #3
 CMP #3
 BEQ prd9
 LDA pr_t
.prd9
 RTS

\ pr_kd: A = clamp(A - Yc) (0..255); pr_ku: A = clamp(Yc + 1 - A)

.pr_kd
 SEC
 SBC pr_c+R_YC
 TAY
 LDA #0
 SBC pr_c+R_YC+1
 BRA pr_cl
.pr_ku
 STA pr_t
 SEC
 LDA pr_c+R_YC
 SBC pr_t
 TAY
 LDA pr_c+R_YC+1
 SBC #0
 INY
 BNE pr_cl
 INC A
.pr_cl
 CMP #0
 BMI pck0
 BNE pck1
 TYA
 RTS
.pck0
 LDA #0
 RTS
.pck1
 LDA #255
 RTS

\ pr_row: row X's crossings about its centre ZC, A = the limbs in the region:
\ X- if the left limb is outside it, X+ if the right one is; with s = 0 (past
\ the ellipse, or at its ends) only if one is

.pr_row
 AND #3
 STA pr_t
 LDA ZSS
 BNE prw1
 LDA pr_t
 BEQ prw9
.prw1
 LSR pr_t
 BCS prw2
 SEC                    \ X-: c - s
 LDA ZC
 SBC ZSS
 TAY
 LDA ZC+1
 SBC #0
 JSR pr_put
.prw2
 LSR pr_t
 BCS prw9
 CLC                    \ X+: c + s
 LDA ZC
 ADC ZSS
 TAY
 LDA ZC+1
 ADC #0

\ pr_put: a crossing at (A Y) (16-bit signed) on row X: at or left of the
\ span's left end it flips the row's colour, right of the span it is
\ dropped, inside it is inserted in order, and with a fifth the two
\ rightmost are dropped. X kept

.pr_put
 BMI pr_flipx
 BNE prw9
 TYA
 CMP R_NDISCL,X
 BCC pr_flipx
 BEQ pr_flipx
 CMP R_NDISCR,X
 BEQ P%+4
 BCS prw9
 LDY R_NDN,X
 BEQ prp0
 CPY #4
 BCS pr_over
 INC R_NDN,X
 BRA mpi
.prp0                   \ (the row's first)
 STA R_NDX0,X
 INC R_NDN,X
 RTS
.pr_flipx               \ row X's starting colour flipped
 LDA R_NDP,X
 EOR #1
 STA R_NDP,X
.prw9
 RTS

\ mpi: insert x (A) into row X's sorted R_NDX0 .. R_NDX(Y-1) (Y = 1..3)

.mpi
 STA mt_x
 CPY #2
 BEQ mpi2
 BCC mpi1
.mpi3
 LDA R_NDX2,X
 CMP mt_x
 BEQ mpi3s
 BCS mpi3m
.mpi3s
 LDA mt_x
 STA R_NDX3,X
 RTS
.mpi3m
 STA R_NDX3,X
.mpi2
 LDA R_NDX1,X
 CMP mt_x
 BEQ mpi2s
 BCS mpi2m
.mpi2s
 LDA mt_x
 STA R_NDX2,X
 RTS
.mpi2m
 STA R_NDX2,X
.mpi1
 LDA R_NDX0,X
 CMP mt_x
 BEQ mpi1s
 BCS mpi1m
.mpi1s
 LDA mt_x
 STA R_NDX1,X
 RTS
.mpi1m
 STA R_NDX1,X
 LDA mt_x
 STA R_NDX0,X
 RTS

.pr_over                \ (A = the fifth: the two rightmost dropped)
 DEC R_NDN,X
 CMP R_NDX3,X
 BCS prw9
 DEY
 BRA mpi

\ The engine's variables (bank 7: pc_circ writes the records in game
\ context, PC_ROWS reads them in the frame, both with this bank paged)

.pm_eu  EQUB 0
.pv                     \ pc_circ's 16-bit operands (pc_mul: offsets O_ from pv)
.pv_m   SKIP 6          \ |mx|, |my|, |mz| >> 2
.pv_hx  EQUW 0          \ the unit axis' x and y (0.8)
.pv_hy  EQUW 0
.pv_d   EQUW 0          \ d = r c (8.8)
.pv_r   EQUW 0          \ r
.pm_tq  EQUW 0          \ t = mz^2 / rho2, 0.16
.pm_v   EQUW 0          \ v = mx^2 / (mx^2 + my^2), 0.16
.pv_cn  EQUW 0          \ pcn / 2
.pv_rc  EQUW 0          \ r^2 - (d^2 >> 16), r^2 - e2
.pv_r2  EQUW 0          \ r^2
.pv_dd  EQUW 0          \ d^2 >> 16
O_M = pv_m - pv
O_HX = pv_hx - pv
O_HY = pv_hy - pv
O_D = pv_d - pv
O_R = pv_r - pv
O_T = pm_tq - pv
O_V = pm_v - pv
O_CN = pv_cn - pv
O_RC = pv_rc - pv
.pm_sg  SKIP 6          \ their signs (by 2)
.pm_nz  SKIP 6          \ &80 if non-zero (by 2)
.pm_sx  EQUB 0          \ bit 7: mx < 0 (after negating m if mz < 0)
.pm_sy  EQUB 0          \ bit 7: my' < 0
.pm_inv EQUB 0          \ 1 if m was negated
.pm_ulo EQUW 0
.pm_a32 SKIP 4          \ a, 16.16 signed } (in this order: the record's
.pm_K2  SKIP 4          \ K2, 16.16       } first eight bytes)
.pm_P                   \ 4-byte operands
.pm_X2  SKIP 4
.pm_Y2  SKIP 4
.pm_Z2  SKIP 4
.pm_XY  SKIP 4
.pm_R2  SKIP 4
.pm_Q2  SKIP 4
.pm_m8  EQUB 0
.pm_zsave SKIP 25       \ Elite's &10-&28 while PF_HOOK uses them

.pc_t   EQUB 0
.pc_dnz EQUB 0          \ bit 7: d is not 0
.pc_dn  EQUB 0          \ bit 7: d < 0 once m is negated (0 if d is 0)
.pc_tb  EQUB 0          \ bit 7: the bottom in the region, bit 6: the top
.pc_st  EQUB 0
.pc_v   EQUW 0
.pc_o   SKIP 3          \ } 24-bit signed, at pc_o + X for pc_sgn: an offset
.pc_a9  SKIP 3          \ } (16.8); A, sqrt(B) and the two nodes, in 1/512
.pc_s9  SKIP 3          \ } pixels
.pc_n   SKIP 6
.wr     SKIP RSZ        \ the record being made
 EQUB &80, &80          \ (pr_tm's last two)

\ The frame's (PC_ROWS'), over the game context's (pc_circ's) work variables
pr_c   = wr             \ the record whose rows are being made (its slot's copy)
pr_tm  = pr_c + R_M1    \ M1, M2, &80, &80
pr_n   = pm_P           \ the next record
pr_end = pm_P + 1       \ the slot after the last
pr_lo  = pm_P + 2       \ the rows with one crossing at most: pr_lo .. pr_hi - 1
pr_hi  = pm_P + 3
pr_past = pm_P + 4      \ bit 7: past the ellipse (D < 0)
pr_tk  = pm_P + 5       \ k thresholds: down T1, T2, first, end; up the same (8)
pr_bd  = pm_P + 13      \ the limbs' regions at k = 0, down and up
pr_bu  = pm_P + 14
pr_fd  = pm_P + 15      \ the flags (pr_seg)
pr_fu  = pm_P + 16
pr_ke  = pm_P + 17      \ the next k at which they change
pr_lc  = pm_P + 18      \ the left limb's toggles (pr_nx): how many, their rows
pr_lt  = pm_P + 19      \ (2 a record: at most 6; over pm_m8 and pm_zsave)

.pcb_o  EQUB 0, RSZ, 2*RSZ, 3*RSZ, 4*RSZ \ the slots' offsets in PCB (and the end)
.PC_N   EQUB 0          \ the planet's records this frame
.pc_inv EQUB 0          \ its base colour (the style's EOR its records')
.pcbx   EQUW 0          \ the body: its centre and radius
.pcby   EQUW 0
.pcr    EQUB 0
.pcv    SKIP 6          \ the axis (three sign-magnitude words: pf_tilt)
.pcc    EQUB 0          \ the circle's cosine (0.8) and its sign (bit 7)
.pcneg  EQUB 0
.pcn    EQUW 0          \ 2^24 / the axis' nominal length (>> 3)
.PCB    SKIP RSZ * (PCMAX + 1)  \ the records: the planet's, and the moon's crater
