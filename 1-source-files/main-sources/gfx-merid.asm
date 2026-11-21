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
\ into the disc layer's boundaries (R_NDN, R_NDX0-3; gfx-raster.asm's
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
\     pc_inv. It uses Elite's zero page &10-&26 (PF_HOOK keeps XC, COL, YC and
\     QQ17 in it), and reads main RAM only for the quarter squares (QSL,
\     QSH);
\
\   * PC_ROWS (the planet's records), in the frame (bank 6's f_bounds,
\     through T_CAPS): the disc
\     layer's boundaries for rows R_NDT..R_NDB (spans R_NDISCL..R_NDISCR).
\     They use the rasteriser's scratch zero page &10-&27 (F_FRAME has saved
\     it).
\
\ ******************************************************************************

pm_a  = &10             \ zero page workspace (Elite's, saved and restored):
pm_b  = &14             \ multiplicand, dividend; multiplier, divisor;
pm_p  = &18             \ product, quotient; temporary
pm_tt = &20
pm_ql = &1C             \ PMQ's pointers into QSL and QSH (&1C-&1F)
pm_qh = &1E
pm_t8 = &22             \ its product's low byte
pmi_n = &23             \ pm_isqrt's: n' (&23-&24) and a square (&25-&26)
pmi_c = &25

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
PCMAX = 3               \ the planet's records (slots 0-2)
PCSLOTS = PCMAX

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
 CMP #PCSLOTS
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
 JSR pc_sq
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
 PHA                    \ (unclamped, into pc_tw, for pf_hold)
 TYA
 ASL A
 TAX
 LDA pc_v
 STA pc_tw,X
 PLA
 STA pc_tw+1,X
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
 LDA PC_N               \ (its unclamped thresholds, for pf_hold)
 ASL A
 ASL A
 TAX
 LDA pc_tw
 STA pc_tu,X
 LDA pc_tw+1
 STA pc_tu+1,X
 LDA pc_tw+2
 STA pc_tu+2,X
 LDA pc_tw+3
 STA pc_tu+3,X
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

\ pc_sq: pm_p (4) = pv+X (2) squared

.pc_sq
 LDA pv,X
 STA pm_a
 LDA pv+1,X
 STA pm_a+1
 JMP pm_sq16

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
 JSR pc_sq
 LDX #pm_X2-pm_P
 JSR pms_stp
 LDX #2
 JSR pc_sq
 LDX #pm_Y2-pm_P
 JSR pms_stp
 LDX #4
 JSR pc_sq
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
 LDA pm_p
 STA pm_P,X
 LDA pm_p+1
 STA pm_P+1,X
 LDA pm_p+2
 STA pm_P+2,X
 LDA pm_p+3
 STA pm_P+3,X
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
.pfd_e0
 JMP pfd_0
.pfd_es
 JMP pfd_sat

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
 ORA pm_a+3             \ either >= 2^24: both lose their low byte (once:
 BEQ pfd1               \ both are then below 2^24)
 LDA pm_P+3,Y
 STA pm_b+3
 LDX #0
.pfd1a
 LDA pm_a+1,X
 STA pm_a,X
 LDA pm_b+1,X
 STA pm_b,X
 INX
 CPX #3
 BNE pfd1a
.pfd1
 LDA pm_a               \ U = 0: 0
 ORA pm_a+1
 ORA pm_a+2
 BEQ pfd_e0
 LDA pm_b               \ V = 0 (or gone): saturated
 ORA pm_b+1
 ORA pm_b+2
 BEQ pfd_es
 LDX #pm_b              \ normalise V: V' = (pm_b+2 pm_b+1), ev
 JSR pfd_norm
 STA pm_b+2
 TYA
 CLC
 ADC #5
 STA pm_eu
 LDX #pm_a              \ and U: U' = (A pm_a+1), eu; the shift 5 + ev - eu
 JSR pfd_norm
 PHA
 TYA
 EOR #&FF
 SEC
 ADC pm_eu
 STA pm_eu
 PLA
 STZ pm_p+1             \ q = floor(U' 2^11 / V'), its top 4 bits into
 LDX #4                 \ pm_p+1, then 8 into pm_p, R = U' (A pm_a+1, its
 CLC                    \ bit 16 in C)
.pfd5
 BCS pfd6               \ R >= 2^16 > V': subtract
 CMP pm_b+2
 BCC pfd7
 BNE pfd6
 LDY pm_a+1
 CPY pm_b+1
 BCC pfd7
.pfd6
 TAY
 LDA pm_a+1
 SBC pm_b+1
 STA pm_a+1
 TYA
 SBC pm_b+2
 SEC
.pfd7
 ROL pm_p+1             \ the quotient bit (C)
 ASL pm_a+1             \ R <<= 1
 ROL A
 DEX
 BNE pfd5
 LDX #8
.pfd5b
 BCS pfd6b
 CMP pm_b+2
 BCC pfd7b
 BNE pfd6b
 LDY pm_a+1
 CPY pm_b+1
 BCC pfd7b
.pfd6b
 TAY
 LDA pm_a+1
 SBC pm_b+1
 STA pm_a+1
 TYA
 SBC pm_b+2
 SEC
.pfd7b
 ROL pm_p
 ASL pm_a+1
 ROL A
 DEX
 BNE pfd5b
 STZ pm_p+2
 STZ pm_p+3
 LDY pm_eu              \ shift q
 BMI pfdr
 TYA                    \ left: by bits (into pm_p+2), then by bytes
 AND #7
 BEQ pfd9
 TAX
.pfd8
 ASL pm_p
 ROL pm_p+1
 ROL pm_p+2
 DEX
 BNE pfd8
.pfd9
 TYA
 LSR A
 LSR A
 LSR A
 BEQ pfd10
 CMP #2
 BCC pfdb1
 BEQ pfdb2
 CMP #3
 BNE pfd_sat
 LDA pm_p+1             \ by 3 bytes
 ORA pm_p+2
 BNE pfd_sat
 LDA pm_p
 STA pm_p+3
 STZ pm_p
 RTS
.pfdb2
 LDA pm_p+2             \ by 2 bytes
 BNE pfd_sat
 LDA pm_p+1
 STA pm_p+3
 LDA pm_p
 STA pm_p+2
 STZ pm_p+1
 STZ pm_p
 RTS
.pfdb1
 LDA pm_p+2             \ by 1 byte
 STA pm_p+3
 LDA pm_p+1
 STA pm_p+2
 LDA pm_p
 STA pm_p+1
 STZ pm_p
 RTS
.pfdr
 CPY #256-11            \ right: by 12 or more, 0
 BCC pfd_0
 CPY #256-7
 BCS pfdr1
 LDA pm_p+1             \ (by 8 to 11: a byte first)
 STA pm_p
 STZ pm_p+1
 TYA
 ADC #8                 \ (C = 0)
 TAY
 BEQ pfd10
.pfdr1
 LSR pm_p+1
 ROR pm_p
 INY
 BNE pfdr1
 RTS
.pfd_0
 STZ pm_p
 STZ pm_p+1
 STZ pm_p+2
 STZ pm_p+3
 RTS
.pfd_sat
 LDA #&FF
 STA pm_p
 STA pm_p+1
 STA pm_p+2
 STA pm_p+3
.pfd10
 RTS

.pfd_norm               \ the 24-bit value at zero page X (non-zero) shifted
 LDY #0                 \ left until bit 23 is set: A = its top byte, its
 LDA 2,X                \ next at 1,X; Y = the shifts
 BNE pfn2
 LDA 1,X                \ a byte at a time
 LDY 0,X
 STY 1,X
 STZ 0,X
 LDY #8
 CMP #0
 BNE pfn2
 LDY #16
 LDA 1,X
 STZ 1,X
.pfn2
 BMI pfn3
.pfn1
 INY
 ASL 0,X
 ROL 1,X
 ROL A
 BPL pfn1
.pfn3
 RTS

\ pm_mul16: pm_p (4) = pm_a (2) * pm_b (2), unsigned, from four 8 x 8
\ products (Elite's quarter-square tables), or two or one when a high byte is
\ zero; pm_sq16: pm_p (4) = pm_a (2)
\ squared, from two squares and one product. Each product is PMQ's: the
\ multiplier b's byte is the low byte of the pointers pm_ql and pm_qh (QSL + b
\ and QSH + b: the tables are page aligned), so that (pm_ql),Y is QS(Y + b)

MACRO PMQ               \ (pm_t8 A) = Y * b, Y kept: QS(Y + b) - QS(|Y - b|)
 TYA
 SEC
 SBC pm_ql
 BCS pq1
 EOR #&FF
 ADC #1
 SEC
.pq1
 TAX                    \ X = |Y - b|
 LDA (pm_ql),Y          \ (bankcheck: ok: game context)
 SBC QSL,X              \ (bankcheck: ok)
 STA pm_t8
 LDA (pm_qh),Y          \ (bankcheck: ok)
 SBC QSH,X              \ (bankcheck: ok)
ENDMACRO

MACRO PMQB b            \ b, a byte at zero page address b, as the multiplier
 LDA b
 STA pm_ql
 STA pm_qh
ENDMACRO

MACRO PMQH              \ the pointers' high bytes
 LDA #HI(QSL)
 STA pm_ql+1
 LDA #HI(QSH)
 STA pm_qh+1
ENDMACRO

.pmb0                   \ b < 256: al bl + ah bl << 8
 STZ pm_p+3
 LDY pm_a+1
 BEQ pmb1
 PMQ
 TAX
 LDA pm_t8
 CLC
 ADC pm_p+1
 STA pm_p+1
 TXA
 ADC #0
 STA pm_p+2
 RTS
.pmb1
 STZ pm_p+2
 RTS

.pm_mul16
 PMQH
 PMQB pm_b              \ al bl
 LDY pm_a
 PMQ
 STA pm_p+1
 LDA pm_t8
 STA pm_p
 LDA pm_b+1
 BEQ pmb0
 LDY pm_a+1             \ ah bl
 BEQ pma0
 PMQ
 TAX
 LDA pm_t8
 CLC
 ADC pm_p+1
 STA pm_p+1
 TXA
 ADC #0
 STA pm_p+2
 PMQB pm_b+1            \ ah bh
 PMQ
 TAX
 LDA pm_t8
 CLC
 ADC pm_p+2
 STA pm_p+2
 TXA
 ADC #0
 STA pm_p+3
 LDY pm_a               \ al bh
 PMQ
 TAX
 LDA pm_t8
 CLC
 ADC pm_p+1
 STA pm_p+1
 TXA
 ADC pm_p+2
 STA pm_p+2
 BCC P%+4
 INC pm_p+3
 RTS
.pma0                   \ a < 256: al bl + al bh << 8
 PMQB pm_b+1
 LDY pm_a
 PMQ
 TAX
 LDA pm_t8
 CLC
 ADC pm_p+1
 STA pm_p+1
 TXA
 ADC #0
 STA pm_p+2
 STZ pm_p+3
 RTS

.pm_sq16
 PMQH
 PMQB pm_a              \ al^2 = QS(2 al)
 LDY pm_a
 LDA (pm_ql),Y          \ (bankcheck: ok: game context)
 STA pm_p
 LDA (pm_qh),Y          \ (bankcheck: ok)
 STA pm_p+1
 PMQB pm_a+1            \ ah^2
 LDY pm_a+1
 LDA (pm_ql),Y          \ (bankcheck: ok)
 STA pm_p+2
 LDA (pm_qh),Y          \ (bankcheck: ok)
 STA pm_p+3
 LDY pm_a               \ 2 al ah
 PMQ
 ASL pm_t8
 ROL A
 TAX
 BCC P%+4
 INC pm_p+3
 LDA pm_t8
 CLC
 ADC pm_p+1
 STA pm_p+1
 TXA
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

\ pm_isqrt: A = f = floor(sqrt(pm_tt)) (16-bit), pm_tt = the remainder
\ pm_tt - f^2. n is normalised to n' = 4^k n >= 2^14 (k = 0..7), so that
\ f' = floor(sqrt(n')) is pis_t's floor(sqrt(256 h')) (h' = n' DIV 256) or
\ one more (as sqrt(256 h' + 255) - sqrt(256 h') < 1); then f = f' >> k.
\ The squares come from the quarter-square table (c^2 = 4 QS(c) + (c AND 1))

.pm_isqrt
 LDY #0                 \ k
 LDX pm_tt
 LDA pm_tt+1
 BNE pis1
 TXA                    \ n < 256: n' = 256 n, k = 4
 BEQ pis9               \ (n = 0: f = 0, the remainder 0)
 LDX #0
 LDY #4
.pis1
 STX pmi_n
 CMP #64
 BCS pis3
.pis2                   \ n' = 4 n' until n' >= 2^14
 ASL pmi_n
 ROL A
 ASL pmi_n
 ROL A
 INY
 CMP #64
 BCC pis2
.pis3                   \ A = h' (64..255), Y = k
 STA pmi_n+1
 TAX
 LDA pis_t-64,X         \ g = floor(sqrt(256 h'))
 CMP #255
 BEQ pis4               \ (g = 255: f' = 255, as n' < 256^2)
 TAX
 INX                    \ f' = g + 1 iff (g + 1)^2 <= n'
 JSR pis_sq
 LDA pmi_n
 CMP pmi_c
 LDA pmi_n+1
 SBC pmi_c+1
 TXA
 BCS pis4
 DEX
 TXA
.pis4
 CPY #0                 \ f = f' >> k
 BEQ pis6
.pis5
 LSR A
 DEY
 BNE pis5
.pis6
 TAX                    \ the remainder n - f^2
 JSR pis_sq
 LDA pm_tt
 SEC
 SBC pmi_c
 STA pm_tt
 LDA pm_tt+1
 SBC pmi_c+1
 STA pm_tt+1
 TXA
.pis9
 RTS

.pis_sq                 \ pmi_c = X^2 (X kept)
 LDA QSL,X              \ (bankcheck: ok: game context)
 ASL A
 STA pmi_c
 LDA QSH,X              \ (bankcheck: ok)
 ROL A
 ASL pmi_c
 ROL A
 STA pmi_c+1
 TXA
 AND #1
 ORA pmi_c
 STA pmi_c
 RTS

.pis_t                  \ floor(sqrt(256 h)), h = 64..255 (pm_isqrt)
 FOR h, 64, 255
  EQUB INT(SQR(256 * h))
 NEXT
\ ******************************************************************************
\
\ PC_ROWS (the planet: slots 0 .. PC_N - 1, base colour pc_inv): the disc
\ layer's boundaries for rows R_NDT..R_NDB (spans R_NDISCL..R_NDISCR). Every
\ row starts with no boundary and the base colour; then each record in turn:
\ its left limb's toggles flip the start colour of the rows from T1 or T2
\ down, and, unless every row is wholly outside its region, its rows from Yc
\ out, down and up.
\ Called by f_bounds (bank 6) through T_CAPS, during the frame, with this
\ bank paged; it uses the rasteriser's scratch zero page &10-&1C (F_FRAME
\ has saved it), and patches its own code (this bank is RAM).
\
\ ******************************************************************************

ZT0 = &10               \ (before the records: the colour, the row, the next
ZT1 = &11               \ toggle; pcr1's record)
ZT2 = &12
ZT3 = &13
pr_H = &10              \ H = (s^2 - s) / 2 (16-bit; a record's, after them)
pr_Hf = &12             \ and the 1/8 with it (&20; 0 with H, once s is 0)
pr_y1 = &14             \ Yc + 1 (16-bit signed)
ZC2 = &16               \ 2 C0 (16-bit)
pr_t = &18              \ (PR_KU's, pr_slow's)
ZK  = &19               \ k, at a segment's start (pr_seg)
mt_x = &1A              \ a crossing being inserted (pr_ins)
ZC  = &1B               \ the row's centre, ceil(C): its low byte
ZS  = &1C               \ s = round(sqrt(D(k))), the half-chord; 0 once past

\ The loop's own numbers are the operands of its instructions, in this bank:
\ C, the centre line of row Yc + k (16.16 signed), in pra0 to pra3's LDA #s
\ and a in their ADC #s; dl = (D(k) - D(k+1)) / 2 (16.16, saturated) in prk0
\ to prk3's LDA #s and K2 in their ADC #s; E = D(k) / 2 - H - 1/8 (16.8: s
\ drops while it is negative, that is, while D < s^2 - s + 1/4; it is not
\ negative when a step is taken from it, so a borrow is its sign) in pr_e0
\ to pr_e2's LDA #s; the rows Yc + k and Yc - k (their low bytes) in
\ pr_dx's and pr_ux's LDX #s; and the row at which the segment ends in
\ pr_cmp's CMP #.
\
\ A segment is a run of k over which neither side's flags change (pr_seg):
\ for it, each row's code and each of its two crossings' is switched on or
\ off at its head, an instruction that does nothing (on) or a branch (off)
\ to the next head (PR_HEADS), so that a row tests no flag. The whole of a row is in line: no call
\ is made and nothing is pushed for a row or a crossing.

\ PR_LT: the left limb toggle of the record's half at PCB + X, if it has one,
\ to pr_lt + Y (in line in PC_ROWS, twice)

MACRO PR_LT
 LDA PCB+R_M1,X
 LSR A
 BCC n
 LDA PCB+R_T1,X
 STA pr_lt,Y
 INY
.n
ENDMACRO

\ PR_KD: A = clamp(A - Yc) (0..255); PR_KU: A = clamp(Yc + 1 - A) (in line in
\ pr_lim's loop; Y used)

MACRO PR_CL
 BEQ n2                 \ (the high byte: 0, in range)
 BMI n1
 LDY #255
 BNE n2
.n1
 LDY #0
.n2
 TYA
ENDMACRO

MACRO PR_KD
 SEC
 SBC pr_c+R_YC
 TAY
 LDA #0
 SBC pr_c+R_YC+1
 PR_CL
ENDMACRO

MACRO PR_KU
 STA pr_t
 SEC
 LDA pr_y1
 SBC pr_t
 TAY
 LDA pr_y1+1
 SBC #0
 PR_CL
ENDMACRO

\ PR_DROP: s (X, not 0) drops, H -= s and E += s (the new s), until E >= 0
\ (then ok) or s = 0 (in line in the loop's pr_sd). PR_NORM: with s = 0,
\ E += H + 1/8 (E = D / 2) and H = 0, no 1/8: C clear if E < 0 still (D < 0)

MACRO PR_DROP ok
.d1
 DEX
 STX ZS
 SEC
 LDA pr_H
 SBC ZS
 STA pr_H
 BCS d2
 DEC pr_H+1
.d2
 CLC
 LDA pr_e1+1
 ADC ZS
 STA pr_e1+1
 BCC d3
 INC pr_e2+1
 BEQ ok
.d3
 TXA
 BNE d1
ENDMACRO

MACRO PR_NORM
 CLC
 LDA pr_e0+1
 ADC pr_Hf
 STA pr_e0+1
 LDA pr_e1+1
 ADC pr_H
 STA pr_e1+1
 LDA pr_e2+1
 ADC pr_H+1
 STA pr_e2+1
 LDA #0
 STA pr_Hf
 STA pr_H
 STA pr_H+1
ENDMACRO

\ PR_SIDE: f = a side's flags at k (Y): its base b EOR M1, M2 from its first
\ two thresholds (pr_tk + o), and bit 7 between the last two; 3 (off) with
\ both limbs in the region (in line in pr_seg, for each side)

MACRO PR_SIDE b, o, f
 LDA b
 CPY pr_tk+o
 BCC n0
 EOR pr_c+R_M1
.n0
 CPY pr_tk+o+1
 BCC n1
 EOR pr_c+R_M2
.n1
 CPY pr_tk+o+2
 BCC n2
 EOR #&80
.n2
 CPY pr_tk+o+3
 BCC n3
 EOR #&80
.n3
 STA f
 AND #3
 CMP #3
 BNE n4
 STA f
.n4
ENDMACRO

\ PR_HEADS: a row's heads for the segment, from its flags f: the row (hc) on
\ if bit 7 is set and, with s = 0, just one limb is outside the region; its
\ crossings X- (hm) and X+ (hp) on if bits 0 and 1 are clear (in line in
\ pr_seg, for each side). A head is two bytes: on, LDY # (which does
\ nothing: Y is free there), and off, a branch always taken to the next
\ head with the same operand, BNE at the row's and X+'s, which are come to
\ with Z clear (from the loop's end, a crossing's last store, PR_FLIP,
\ pr_ir or a head's own branch), BEQ at X-'s, come to with Z set (the
\ centre's high byte is 0). X+'s is come to with Z set from X-'s branch,
\ but then it is on: with both off, the row is.

PR_ON = &A0             \ LDY #
PR_OFFN = &D0           \ BNE
PR_OFFZ = &F0           \ BEQ
PR_SON = &2C            \ (E's step, pr_hs: BIT abs, JMP abs)
PR_SOFF = &4C

MACRO PR_HEADS f, hc, hm, hp
 LDX #PR_OFFN
 LDA f
 BPL h1
 AND #3
 ORA ZS
 BEQ h1
 LDX #PR_ON
.h1
 STX hc
 LDA f
 LSR A
 LDX #PR_ON
 BCC h2
 LDX #PR_OFFZ
.h2
 STX hm
 LSR A
 LDX #PR_ON
 BCC h3
 LDX #PR_OFFN
.h3
 STX hp
ENDMACRO

\ PR_FLIP: row X's starting colour flipped (a crossing at or left of the
\ span's left end); Z clear after it, for the head it goes on to

MACRO PR_FLIP
 LDA R_NDN,X
 EOR #&80
 STA R_NDN,X
 LDY #1
ENDMACRO

\ PR_PUT: a crossing at A (0..255) on row X: at or left of the span's left
\ end it flips the row's colour (fl), right of the span it is dropped,
\ inside it is the row's first (R_NDX0), or is inserted in order (pr_ins,
\ which the four share: it goes on at pr_ir's JMP, set to nx); then nx, or,
\ for the row's first, the code that follows. In line for each side's X-
\ and X+ (the loop's four crossings).

MACRO PR_PUT fl, nx
 CMP R_NDISCL,X
 BCC fl
 BEQ fl
 CMP R_NDISCR,X
 BEQ P%+4
 BCS j9
 LDY R_NDN,X            \ the count (bit 7: the colour)
 BEQ p0
 CPY #&80
 BEQ p0
 STA mt_x
 LDA #LO(nx)
 STA pr_ir+1
 LDA #HI(nx)
 STA pr_ir+2
 JMP pr_ins
.j9
 JMP nx
.p0
 INC R_NDN,X            \ (the row's first)
 STA R_NDX0,X
ENDMACRO

.PC_ROWS
 LDX #0
 LDY PC_N
 STX pr_n
 STY pr_end
 LDY #0                 \ the records' left limb toggles: the start colour of
.pcr1                   \ the rows from T on flipped (pr_lt, pr_lc of them)
 CPX pr_end
 BCS pcr4
 STX ZT3
 LDA pcb_o,X
 TAX
 PR_LT
 INX
 PR_LT
 LDX ZT3
 INX
 BNE pcr1
.pcr4
 STY pr_lc
 LDA pc_inv             \ every row: no boundary, the base colour (bit 0, to
 LSR A                  \ bit 7: R_NDN's) EOR the toggles so far
 LDA #0
 ROR A
 LDX R_NDT
.pcr6                   \ the colour A EOR a toggle (bit 7) for each of
 STA ZT0                \ pr_lt <= X (each then taken out); ZT2 = the least
 STX ZT1                \ left, or 255
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
 LDA ZT0
 EOR #&80
 STA ZT0
 LDA #255
 STA pr_lt,Y
 BNE pnx1
.pnx3
 CMP ZT2
 BCS pnx1
 STA ZT2
 BCC pnx1
.pnx9
 LDY R_NDB              \ the rows up to the next toggle's, or to the last
 INY                    \ (pcr5c's CPX #)
 CPY ZT2
 BCC P%+4
 LDY ZT2
 STY pcr5c+1
 LDA ZT0
.pcr5
 STA R_NDN,X
 INX
.pcr5c
 CPX #0
 BCC pcr5
 CPX R_NDB
 BCC pcr6
 BEQ pcr6

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
 LDY #0                 \ a and K2 into the loop's ADC #s (seven bytes
 LDX #0                 \ apart; C stays clear), and dl = K2 / 2
 CLC
.pcr11
 LDA pr_c+R_A,Y
 STA pra0+3,X
 LDA pr_c+R_K2,Y
 STA prk0+3,X
 STA prk0+1,X
 TXA
 ADC #7
 TAX
 INY
 CPY #4
 BNE pcr11
 LSR prk3+1
 ROR prk2+1
 ROR prk1+1
 ROR prk0+1
 LDA pr_c+R_L0+1        \ H = L0 / 2
 LSR A
 STA pr_H+1
 LDA pr_c+R_L0
 ROR A
 STA pr_H
 LDX #0                 \ C = C0 (and 2 C0), not past
 STX pra0+1
 STX pra1+1
 STX pr_past
 LDA pr_c+R_C0
 STA pra2+1
 ASL A
 STA ZC2
 LDA pr_c+R_C0+1
 STA pra3+1
 ROL A
 STA ZC2+1
 LDA #PR_SON            \ (E's step is on until past the ellipse)
 STA pr_hs
 LDA pr_c+R_YC          \ the rows Yc + k and Yc - k (their low bytes: the
 STA pr_dx+1            \ rows, when they are on the screen), and Yc + 1
 STA pr_ux+1
 CLC
 ADC #1
 STA pr_y1
 LDA pr_c+R_YC+1
 ADC #0
 STA pr_y1+1
 LDA #&20
 STA pr_Hf
 LDA pr_c+R_S0          \ s = s0
 STA ZS
 LDA pr_c+R_K0+3        \ E = D / 2 - H - 1/8, D = K0 (D / 2 is kept to
 LSR A                  \ 1/256)
 STA pr_e2+1
 LDA pr_c+R_K0+2
 ROR A
 STA pr_e1+1
 LDA pr_c+R_K0+1
 ROR A
 SEC
 SBC #&20               \ (pr_Hf)
 STA pr_e0+1
 LDA pr_e1+1
 SBC pr_H
 STA pr_e1+1
 LDA pr_e2+1
 SBC pr_H+1
 STA pr_e2+1
 BCS pcr9a             \ E < 0: s drops, by the loop's code (pr_sls), which
 LDA #LO(pcr9)          \ comes back at pcr9
 STA pr_dlj+1
 LDA #HI(pcr9)
 STA pr_dlj+2
 LDA pr_e2+1
 JMP pr_sls
.pcr9
 LDA #LO(pr_dls)
 STA pr_dlj+1
 LDA #HI(pr_dls)
 STA pr_dlj+2
.pcr9a
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
 LDX R_NDB
 INX
 STX pr_tk+6

\ pr_lim: the last rows the loop may reach (pr_tk + 3, pr_tk + 7): down, NDB
\ (past, thi - 1); up, NDT (past, tlo); they, and for a record's first row
\ the other thresholds, as k: down clamp(row - Yc), up clamp(Yc + 1 - row).
\ Then a new segment (pr_pst, past the ellipse, comes here too)

.pr_lim
 LDX R_NDB
 INX
 TXA
 BIT pr_past
 BPL prm1
 CMP pr_hi
 BCC prm1
 LDA pr_hi
.prm1
 STA pr_tk+3
 LDA R_NDT
 BIT pr_past
 BPL prm2
 CMP pr_lo
 BCS prm2
 LDA pr_lo
.prm2
 STA pr_tk+7
 LDX #3
.pcr13
 LDA pr_tk,X
 PR_KD
 STA pr_tk,X
 LDA pr_tk+4,X
 PR_KU
 STA pr_tk+4,X
 DEX
 BMI pcr14
 BIT pr_past            \ (past: the last rows only)
 BPL pcr13
.pcr14
 LDA pr_tk+6            \ (up: k >= 1)
 BNE P%+5
 INC pr_tk+6
 LDA pr_tk+3            \ (the last not below the first)
 CMP pr_tk+2
 BCS P%+8
 LDA pr_tk+2
 STA pr_tk+3
 LDA pr_tk+7
 CMP pr_tk+6
 BCS P%+8
 LDA pr_tk+6
 STA pr_tk+7

\ pr_seg: a segment starts at k (the down row less Yc): the record is done
\ once both sides are past their last rows; else each side's flags (pr_fd,
\ pr_fu: bit 7 the row is on the screen with a limb outside the region, bits
\ 0-1 the limbs in it) and its heads, and the next k at which any flag
\ changes (pr_ke: its down row into pr_cmp)

.pr_seg
 SEC
 LDA pr_dx+1
 SBC pr_c+R_YC
 STA ZK
 CMP pr_tk+3
 BCC pre1
 CMP pr_tk+7
 BCC pre1
 JMP pcr2
.pre1
 TAY
 PR_SIDE pr_bd, 0, pr_fd
 PR_SIDE pr_bu, 4, pr_fu
 PR_HEADS pr_fd, pr_hd, pr_hdm, pr_hdp
 PR_HEADS pr_fu, pr_hu, pr_hum, pr_hup
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
 LDA pr_ke
 ADC pr_c+R_YC
 STA pr_cmp+1
 LDY #1                 \ (Z clear, as pr_hd is come to)

\ The loop: for each k, row Yc + k, row Yc - k, then C += a, E -= dl and
\ dl += K2 (with s dropped, or past the ellipse, if E < 0: pr_sls)

.pr_k
.pr_hd
 EQUB PR_ON, pr_dj - pr_hd - 2  \ row Yc + k (off: BNE pr_dj, and on to pr_hu)
.pr_dx
 LDX #0                 \ (the row)
 LDA pra0+1             \ its centre, ceil(C)
 ORA pra1+1
 CMP #1
 LDA pra2+1
 ADC #0
 STA ZC
 BCS pr_ds
 LDY pra3+1
 BEQ pr_hdm
.pr_ds                  \ (not on the screen: pr_slow; C: the carry into
 LDA pra3+1             \ the centre's high byte)
 ADC #0
 TAY
 BEQ pr_ds0
 LDA pr_fd
 JSR pr_slow
 DEY
 BEQ pr_dpf
 BPL pr_ds2
.pr_dj
 JMP pr_hu
.pr_ds2
 DEY
 BEQ pr_dmp
 BNE pr_dpp
.pr_ds0
 LDA ZC
 LDY #0                 \ (Z set, as pr_hdm is come to)
.pr_hdm
 EQUB PR_ON, pr_hdp - pr_hdm - 2  \ X-: c - s (off: BEQ pr_hdp)
 SEC
 SBC ZS
 BCS pr_dmp
.pr_dmf
 PR_FLIP
 JMP pr_hdp
.pr_dmp
 PR_PUT pr_dmf, pr_hdp
.pr_hdp
 EQUB PR_ON, pr_hu - pr_hdp - 2  \ X+: c + s (off: BNE pr_hu)
 LDA ZC
 CLC
 ADC ZS
 BCC pr_dpp
 LDY #1                 \ (Z clear)
 JMP pr_hu
.pr_dpf
 PR_FLIP
 JMP pr_hu
.pr_dpp
 PR_PUT pr_dpf, pr_hu
.pr_hu
 EQUB PR_ON, pr_uj - pr_hu - 2  \ row Yc - k (off: BNE pr_uj, and on to pr_adv)
.pr_ux
 LDX #0                 \ (the row)
 SEC                    \ its centre, ceil(2 C0 - C) = 2 C0 - floor(C)
 LDA ZC2
 SBC pra2+1
 STA ZC
 LDA ZC2+1
 SBC pra3+1
 BEQ pr_hum
 TAY                    \ (not on the screen: pr_slow)
 LDA pr_fu
 JSR pr_slow
 DEY
 BEQ pr_upf
 BPL pr_us2
.pr_uj
 JMP pr_adv
.pr_us2
 DEY
 BEQ pr_ump
 BNE pr_upp
.pr_hum
 EQUB PR_ON, pr_hup - pr_hum - 2  \ X-: c - s (off: BEQ pr_hup)
 LDA ZC
 SEC
 SBC ZS
 BCS pr_ump
.pr_umf
 PR_FLIP
 JMP pr_hup
.pr_ump
 PR_PUT pr_umf, pr_hup
.pr_hup
 EQUB PR_ON, pr_adv - pr_hup - 2  \ X+: c + s (off: BNE pr_adv)
 LDA ZC
 CLC
 ADC ZS
 BCC pr_upp
 JMP pr_adv
.pr_upf
 PR_FLIP
 JMP pr_adv
.pr_upp
 PR_PUT pr_upf, pr_adv
ASSERT pr_dj - pr_hd < 129 AND pr_hdp - pr_hdm < 129 AND pr_hu - pr_hdp < 129
ASSERT pr_uj - pr_hu < 129 AND pr_hup - pr_hum < 129 AND pr_adv - pr_hup < 129
.pr_adv
 CLC                    \ C += a
.pra0
 LDA #0
 ADC #0
 STA pra0+1
.pra1
 LDA #0
 ADC #0
 STA pra1+1
.pra2
 LDA #0
 ADC #0
 STA pra2+1
.pra3
 LDA #0
 ADC #0
 STA pra3+1
 INC pr_dx+1
 DEC pr_ux+1
.pr_hs
 BIT pr_nk              \ E -= dl (off, past the ellipse: JMP pr_nk)
 SEC
.pr_e0
 LDA #0
 SBC prk1+1
 STA pr_e0+1
.pr_e1
 LDA #0
 SBC prk2+1
 STA pr_e1+1
.pr_e2
 LDA #0
 SBC prk3+1
 STA pr_e2+1
 BCC pr_sls
.pr_dls
 CLC                    \ dl += K2
.prk0
 LDA #0
 ADC #0
 STA prk0+1
.prk1
 LDA #0
 ADC #0
 STA prk1+1
.prk2
 LDA #0
 ADC #0
 STA prk2+1
.prk3
 LDA #0
 ADC #0
 STA prk3+1
 BCC pr_nk
 LDA #&FF
 STA prk0+1
 STA prk1+1
 STA prk2+1
 STA prk3+1
.pr_nk
 LDA pr_dx+1            \ the next k: a new segment at its end
.pr_cmp
 CMP #0
 BEQ pr_sgj
 JMP pr_k
.pr_sgj
 JMP pr_seg
ASSERT pra1 = pra0 + 7 AND pra3 = pra0 + 21 AND prk1 = prk0 + 7 AND prk3 = prk0 + 21

\ pr_sls: E < 0 after its step (A = its high byte). Past the ellipse if
\ D / 2 = E + H + 1/8 < 0: then s = 0 from now on, E's step is off, and only
\ the rows with one crossing at most are left (pr_lim, and a new segment).
\ Else s drops until E >= 0 (PR_DROP; the test of D is left out when
\ E > -256, as the drops then end soon, and made if they reach s = 0 with
\ E < 0: PR_NORM), with a new segment if it reaches 0 (the rows' heads
\ depend on it).

.pr_sls
 LDX ZS
 BEQ pr_s0
 CMP #&FF
 BEQ pr_sd
 CLC
 LDA pr_e0+1
 ADC pr_Hf
 LDA pr_e1+1
 ADC pr_H
 LDA pr_e2+1
 ADC pr_H+1
 BCC pr_pst
.pr_sd
 PR_DROP pr_sok
 LDA pr_dx+1            \ (s is 0 now: a new segment)
 STA pr_cmp+1
.pr_s0
 PR_NORM
 BCC pr_pst
 BCS pr_dlj
.pr_sok
 TXA
 BNE pr_dlj
 LDA pr_dx+1            \ (s is 0 now: a new segment)
 STA pr_cmp+1
.pr_dlj
 JMP pr_dls              \ (a record's first row: to pcr9)
.pr_pst
 LDA #PR_SOFF
 STA pr_hs
 LDA #&80
 STA pr_past
 ASL A
 STA ZS
 JMP pr_lim

\ pr_ins: mt_x inserted in order into row X's R_NDX0.. (Y = R_NDN: 1 to 4
\ there, and the colour); with a fifth the two rightmost are dropped. Then
\ on, through pr_ir (PR_PUT sets it)

.pr_ins
 INC R_NDN,X
 TYA                    \ 1, 2, 3 there: into R_NDX0, R_NDX0..1, R_NDX0..2
 AND #7
 LSR A
 BEQ pri1
 BCS pri3
 LSR A
 BCS pri2
 DEC R_NDN,X            \ 4 there: the count stays 3, and the fifth is put
 DEC R_NDN,X            \ only if it is left of the fourth
 LDA mt_x
 CMP R_NDX3,X
 BCS pr_irz
.pri3
 LDA R_NDX2,X
 CMP mt_x
 BEQ pri3s
 BCS pri3m
.pri3s
 LDA mt_x
 STA R_NDX3,X
 JMP pr_ir
.pri3m
 STA R_NDX3,X
.pri2
 LDA R_NDX1,X
 CMP mt_x
 BEQ pri2s
 BCS pri2m
.pri2s
 LDA mt_x
 STA R_NDX2,X
 JMP pr_ir
.pri2m
 STA R_NDX2,X
.pri1
 LDA R_NDX0,X
 CMP mt_x
 BEQ pri1s
 BCS pri1m
.pri1s
 LDA mt_x
 STA R_NDX1,X
 JMP pr_ir
.pri1m
 STA R_NDX1,X
 LDA mt_x
 STA R_NDX0,X
.pr_ir
 JMP pr_adv             \ (patched)
.pr_irz
 LDY #1                 \ (Z clear, for the head it goes on to)
 BNE pr_ir

\ pr_slow: a row (X) whose centre (Y ZC, 16-bit signed) is not on the screen
\ (Y is not 0), A = its flags: what is left of it for the row's own code
\ comes back in Y. Right of the screen by 256 or more, both crossings are
\ dropped (0); left of it by more than 256, each flips the row's colour (so
\ both do nothing, and one flips it: 1, the X+ crossing's flip), each as a
\ 16-bit signed sum that wraps would have it; in between only one crossing
\ can be on the screen: with the centre right of it X-, c - s (2, at A: ZC is
\ set so that X+, after it, is dropped), and with the centre left of it X+,
\ c + s (3, at A), X- having flipped the colour here. (The one call of a
\ row: such rows are few.)

.pr_slow
 STA pr_t
 CPY #1
 BEQ psl4
 CPY #&FF
 BEQ psl5
 TYA
 BMI psl2
 CPY #&7F               \ (c + s past 32767 wraps: X+ flips the colour)
 BNE psl0
 LDA ZC
 CLC
 ADC ZS
 BCC psl0
.psl1
 LDA pr_t
 AND #2
 BNE psl0
.psl1a
 LDY #1
 RTS
.psl2
 CPY #&80               \ (c - s below -32768 wraps: X- is dropped)
 BNE psl3
 LDA ZC
 CMP ZS
 BCC psl1
.psl3
 LDA pr_t
 AND #3
 BNE psl1a
.psl0
 LDY #0
 RTS
.psl4
 LDA pr_t
 LSR A
 BCS psl0
 LDA ZC                 \ (X-: on the screen if c - s < 256)
 CMP ZS
 BCS psl0
 SEC
 SBC ZS
 LDY #&FF               \ (s > 0 here: &FF + s carries, and X+ is dropped)
 STY ZC
 LDY #2
 RTS
.psl5
 LDA pr_t
 LSR A
 BCS psl6
 PR_FLIP
.psl6
 LDA pr_t
 AND #2
 BNE psl0
 LDA ZC                 \ (X+: on the screen if c + s >= 0)
 CLC
 ADC ZS
 BCC psl1a
 LDY #3
 RTS

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
.pm_zsave SKIP 4        \ Elite's XC, COL, YC and QQ17 while PF_HOOK uses &10-&26

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
pr_lt  = pm_P + 19      \ (2 a record: at most 6; over pm_m8)

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
.pc_tw  SKIP 4          \ the record's thresholds T1, T2 before clamping (16-bit)
.pc_tu  SKIP 4 * PCSLOTS \ and each slot's (pf_hold moves them to the disc)
.PCB    SKIP RSZ * PCSLOTS  \ the records: the planet's
