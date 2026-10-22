\ ******************************************************************************
\
\ gfx-merid.asm - the meridian window: the beach ball planet's colour
\ boundaries (sideways RAM bank 7, after the cold area, paged as ROMSEL
\ MERIDBANK; docs/memory-map.md)
\
\ A planet of type 128 has an equator and a meridian: Elite draws the visible
\ halves of the two great circles in the planes normal to roofv and sidev.
\ The filled renderer colours the disc instead: colour B where the surface is
\ on the same side of both planes, colour A elsewhere (a "beach ball"), as a
\ list of colour boundaries per disc row for the disc layer (R_NDN, R_NDX0-3,
\ R_NDP; gfx-raster.asm's header). Each circle is projected exactly, so the
\ boundaries meet the limb and each other with no tears. The method is
\ described at PM_MERID below; 6-harness/planet_analytic.py (analytic_rows_fixed)
\ models this code bit for bit. From the demo port (demo-final's
\ src/planet4.asm) with Master's quarter squares and a window of its own.
\
\ The window has two entry points, and nothing else in it is called from
\ outside:
\
\   * PM_HOOK, in game context: the per-frame constants of both circles,
\     from the planet's orientation vectors (INWK), its centre (K3, K4) and
\     radius (PM_R, which H_CIRC records); PM_OK is set (&80). The
\     orientation is taken one frame in MERIDHOLD + 1 (the spin shows in
\     steps); in between only what depends on the radius and centre is
\     computed, or nothing, when they are as they were and the disc layer's
\     arrays still hold the rows (PS_VALID): then PM_OK = &C0, and T_MERID
\     skips PM_MERID. Called by G_MERHOOK
\     (gfx-gstubs.asm) from H_MERID, in place of PL9's equator and meridian.
\     Elite's state is not touched: the workspace is here, Elite's
\     zero page &10-&28 is saved and restored, and A, X, Y and the flags are
\     preserved;
\
\   * PM_MERID, in the frame (bank 6's f_bounds, through the trampoline
\     T_MERID, gfx-tramp.asm): the row loop, which writes the disc layer's
\     boundaries for rows R_NDT..R_NDB.
\
\ It reads main RAM only below &3000 (the shared workspace), but for the
\ quarter squares (QSL, QSH) in PM_HOOK, which runs in game context.
\
\ ******************************************************************************

pm_a  = &10             \ zero page workspace (Elite's, saved and restored):
pm_b  = &14             \ multiplicand, dividend; multiplier, divisor;
pm_p  = &18             \ product, quotient; remainder; temporary
pm_rr = &1C
pm_tt = &20
pmi_res = &23           \ pm_isqrt's
pmi_one = &25
pmi_s = &27             \ (&27-&28)

.PM_HOOK
 PHP
 PHA
 PHX
 PHY
 LDA PM_SPIN            \ the planet spins by 1/16 radian an iteration (in
 BEQ phk8               \ roll and pitch): its orientation is taken one frame
 LDA pm_mc              \ in MERIDHOLD + 1 (PM_SPIN counts the frames held),
 DEC A                  \ while each frame draws this beach ball (MCNT, the
 CMP MCNT               \ main loop's counter, one less than last time)
 BNE phk8
 DEC PM_SPIN            \ the orientation is held
 LDA MCNT
 STA pm_mc
 BIT PS_VALID           \ and when the centre and radius are as they were too,
 BPL phk6               \ the rows in the disc layer's arrays are kept
 LDA K3
 CMP PM_CX
 BNE phk6
 LDA K3+1
 CMP PM_CX+1
 BNE phk6
 LDA K4
 CMP PM_CY
 BNE phk6
 LDA K4+1
 CMP PM_CY+1
 BNE phk6
 LDA PM_R
 CMP pm_rs
 BNE phk6
 LDA #&C0               \ (T_MERID skips PM_MERID)
 STA PM_OK
 JMP phk7
.phk8
 LDA #MERIDHOLD         \ a new orientation
 STA PM_SPIN
 INC pm_og
 LDA MCNT
 STA pm_mc
 SEC                    \ (C: the orientation's constants are computed)
 BCS phk11
.phk6
 CLC                    \ (C clear: the held orientation's constants are used)
.phk11
 ROR pm_new             \ (bit 7)
 LDA PM_R
 EOR pm_rs              \ (C clear if the radius is as it was)
 CMP #1
 ROR pm_rch             \ (bit 7: the radius has changed)
 LDA PM_R
 STA pm_rs
 LDX #24
.phk0
 LDA &10,X
 STA pm_zsave,X
 DEX
 BPL phk0
 LDA K3                 \ the centre, for PM_MERID (K3, K4: as H_CIRC recorded
 STA PM_CX              \ it in F_PLX, F_PLY)
 LDA K3+1
 STA PM_CX+1
 LDA K4
 STA PM_CY
 LDA K4+1
 STA PM_CY+1
 LDA PM_R               \ r^2
 STA pm_a
 STA pm_b
 STZ pm_a+1
 STZ pm_b+1
 JSR pm_mul16
 LDA pm_p
 STA pm_r2
 LDA pm_p+1
 STA pm_r2+1
 LDX #MCB-1             \ roofv's circle: PM_BLK1 and its orientation's terms
 LDY #pm_oc1-pm_oc      \ (pm_oc1)
 JSR phk_c
 LDX #MCB-1
.phk1
 LDA pm_blk,X
 STA PM_BLK1,X
 DEX
 BPL phk1
 LDX #MCB-1             \ sidev's: PM_BLK2, pm_oc2
 LDY #pm_oc2-pm_oc
 JSR phk_c2
 LDX #MCB-1
.phk2
 LDA pm_blk,X
 STA PM_BLK2,X
 DEX
 BPL phk2
 LDA #&80               \ the constants are ready (bit 6 clear: T_MERID runs
 STA PM_OK              \ PM_MERID)
 LDX #24
.phk3
 LDA pm_zsave,X
 STA &10,X
 DEX
 BPL phk3
.phk7
 PLY
 PLX
 PLA
 PLP
 RTS

\ phk_c (roofv, PM_BLK1), phk_c2 (sidev, PM_BLK2): one circle's constants into
\ pm_blk. A new orientation: all of them (pm_setup), and its terms t, v and
\ the signs (pm_tq, pm_v, pm_sx, pm_sy) are kept at pm_oc + Y. A held one:
\ the circle's last block and terms, then only what depends on the radius
\ and the centre (pm_radius), or, with the radius as it was, on the centre
\ (pm_centre). X = MCB - 1, Y = the terms' offset.

.phk_c2
 BIT pm_new
 BPL phc2
 LDX #6
 BNE phc5               \ (always)
.phc2
 LDA PM_BLK2,X
 STA pm_blk,X
 DEX
 BPL phc2
 BMI phc3               \ (always)
.phk_c
 BIT pm_new
 BPL phc1
 LDX #0
.phc5
 STY pm_ocy
 JSR pm_setup
 LDY pm_ocy
 LDX #0
.phc6
 LDA pm_tq,X
 STA pm_oc,Y
 INY
 INX
 CPX #7
 BNE phc6
 RTS
.phc1
 LDA PM_BLK1,X
 STA pm_blk,X
 DEX
 BPL phc1
.phc3
 STY pm_ocy
 LDX #0
.phc4
 LDA pm_oc,Y
 STA pm_tq,X
 INY
 INX
 CPX #7
 BNE phc4
 BIT pm_rch             \ the same radius: only the node rows, which depend
 BPL phc7               \ on the centre (pm_f kept)
 JSR pm_radius
 LDY pm_ocy             \ (and floor(|w|), for next time)
 LDA pm_f
 STA pm_oc+6,Y
 RTS
.phc7
 JMP pm_centre

\ pm_setup: the constants of the circle with normal INWK+15+X (roofv 0, sidev 6)
\ into pm_blk

.pm_setup
 STX pm_o
 LDY #0                 \ |m| >> 3 (12 bits) and signs (zero: positive)
 JSR pms_comp
 LDX pm_o
 INX
 INX
 LDY #2
 JSR pms_comp
 LDX pm_o
 INX
 INX
 INX
 INX
 LDY #4
 JSR pms_comp
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
 JSR pms_mul
 LDX #pm_X2-pm_P
 JSR pms_stp
 LDX #2
 LDY #2
 JSR pms_mul
 LDX #pm_Y2-pm_P
 JSR pms_stp
 LDX #4
 LDY #4
 JSR pms_mul
 LDX #pm_Z2-pm_P
 JSR pms_stp
 LDX #0
 LDY #2
 JSR pms_mul
 LDX #pm_XY-pm_P
 JSR pms_stp
 CLC                    \ R2 = X2 + Z2, Q2 = X2 + Y2 (at least 1)
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
 LDA pm_R2
 ORA pm_R2+1
 ORA pm_R2+2
 ORA pm_R2+3
 BNE P%+5
 INC pm_R2
 LDA pm_Q2
 ORA pm_Q2+1
 ORA pm_Q2+2
 ORA pm_Q2+3
 BNE P%+5
 INC pm_Q2
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
 SEC
 LDA #0
 SBC pm_p
 STA pm_p
 LDA #0
 SBC pm_p+1
 STA pm_p+1
 LDA #0
 SBC pm_p+2
 STA pm_p+2
 LDA #0
 SBC pm_p+3
 STA pm_p+3
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
.pms9
.pm_radius             \ (phk_c: the constants that depend on the radius and centre)
 JSR pms_r2              \ K0 = r^2 t
 JSR pms_bt
 JSR pm_mul16
 LDX #3
.pms10
 LDA pm_p,X
 STA pm_K0,X
 DEX
 BPL pms10
 LDA pm_K0+2            \ s0 = round(sqrt(K0)), L0 = s0^2 - s0: with
 STA pm_tt               \ f = pm_isqrt(K0 hi), rem = K0 hi - f^2, s0 = f + 1
 LDA pm_K0+3            \ iff K0 >= (f^2 + f + 1/4), i.e. iff rem > f, or
 STA pm_tt+1             \ rem = f and K0 lo >= &4000
 JSR pm_isqrt
 STA pm_s0
 LDA pm_tt+1
 BNE pms11               \ rem > f
 LDA pm_tt
 CMP pm_s0
 BCC pms12               \ rem < f
 BNE pms11
 LDA pm_K0+1
 CMP #&40
 BCC pms12
.pms11
 INC pm_s0              \ L0 = f^2 + f = K0 hi - rem + f
 LDA pm_K0+2
 SEC
 SBC pm_tt
 STA pm_L0
 LDA pm_K0+3
 SBC pm_tt+1
 STA pm_L0+1
 LDA pm_L0
 CLC
 ADC pm_s0
 STA pm_L0
 BCC P%+5
 INC pm_L0+1
 LDA pm_L0              \ (s0 was incremented: subtract the 1)
 BNE P%+5
 DEC pm_L0+1
 DEC pm_L0
 JMP pms13
.pms12
 LDA pm_K0+2            \ L0 = f^2 - f = K0 hi - rem - f
 SEC
 SBC pm_tt
 STA pm_L0
 LDA pm_K0+3
 SBC pm_tt+1
 STA pm_L0+1
 LDA pm_L0
 SEC
 SBC pm_s0
 STA pm_L0
 BCS P%+5
 DEC pm_L0+1
.pms13
 JSR pms_r2              \ W2 = r^2 v (w^2, 16.16)
 LDA pm_v
 STA pm_b
 LDA pm_v+1
 STA pm_b+1
 JSR pm_mul16
 LDA pm_p+2             \ f = floor(|w|), cl = ceil(|w|)
 STA pm_tt
 LDA pm_p+3
 STA pm_tt+1
 JSR pm_isqrt
 STA pm_f
 STA pm_kw
 LDA pm_tt
 ORA pm_tt+1
 ORA pm_p
 ORA pm_p+1
 BEQ P%+5
 INC pm_kw
 \ thresholds: P1 = cy - cl + 1, P2 = cy + f + 1, N1 = cy + cl, N2 = cy - f
 \ pos (my' >= 0): (uP, uM) = (P1, P2) if mx >= 0, else (P2, P1)
 \ neg: (uP, uM) = (N1, N2) if mx >= 0, else (N2, N1); each clamped to 0..192
.pm_centre              \ (phk_c: the constants that depend on the centre)
 LDA pm_sy
 BMI pms20
 LDA #0
 STA pm_neg
 LDA K4              \ P1
 SEC
 SBC pm_kw
 STA pm_tt
 LDA K4+1
 SBC #0
 STA pm_tt+1
 LDA #1
 JSR pms_clamp
 STA pm_tt+2
 LDA K4              \ P2
 CLC
 ADC pm_f
 STA pm_tt
 LDA K4+1
 ADC #0
 STA pm_tt+1
 LDA #1
 JMP pms21
.pms20
 LDA #1
 STA pm_neg
 LDA K4              \ N1
 CLC
 ADC pm_kw
 STA pm_tt
 LDA K4+1
 ADC #0
 STA pm_tt+1
 LDA #0
 JSR pms_clamp
 STA pm_tt+2
 LDA K4              \ N2
 SEC
 SBC pm_f
 STA pm_tt
 LDA K4+1
 SBC #0
 STA pm_tt+1
 LDA #0
.pms21
 JSR pms_clamp           \ A = second value, pm_tt+2 = first
 LDX pm_tt+2
 BIT pm_sx
 BMI pms22
 STX pm_uP
 STA pm_uM
 RTS
.pms22
 STA pm_uP
 STX pm_uM
 RTS

.pms_clamp               \ (pm_tt) + A, 16-bit signed, clamped to 0..192
 CLC
 ADC pm_tt
 STA pm_tt
 BCC P%+4
 INC pm_tt+1
 LDA pm_tt+1
 BMI pmsc8
 BNE pmsc9
 LDA pm_tt
 CMP #193
 BCS pmsc9
 RTS
.pmsc8
 LDA #0
 RTS
.pmsc9
 LDA #192
 RTS

.pms_r2                  \ pm_a = r^2
 LDA pm_r2
 STA pm_a
 LDA pm_r2+1
 STA pm_a+1
 RTS

.pms_bt                  \ pm_b = t
 LDA pm_tq
 STA pm_b
 LDA pm_tq+1
 STA pm_b+1
 RTS

.pms_comp                \ component INWK+15+X -> pm_m+Y = |v| >> 3, pm_sg+Y =
 LDA INWK+15+1,X          \ its sign (0 if zero), pm_nz+Y = &80 if non-zero
 AND #&7F
 STA pm_tt+1
 LDA INWK+15,X
 STA pm_tt
 ORA pm_tt+1
 BEQ pmsp1
 LDA #&80
.pmsp1
 STA pm_nz,Y
 AND INWK+15+1,X
 STA pm_sg,Y
 LDA pm_tt+1
 LSR A
 ROR pm_tt
 LSR A
 ROR pm_tt
 LSR A
 ROR pm_tt
 STA pm_m+1,Y
 LDA pm_tt
 STA pm_m,Y
 RTS

.pms_mul                 \ pm_p = pm_m+X * pm_m+Y
 LDA pm_m,X
 STA pm_a
 LDA pm_m+1,X
 STA pm_a+1
 LDA pm_m,Y
 STA pm_b
 LDA pm_m+1,Y
 STA pm_b+1
 JMP pm_mul16

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
\ negative), saturating at 2^32 - 1. U = 0 gives 0. (planet_analytic.fdiv)
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

.pm_r2  EQUW 0          \ r^2
.pm_rs  EQUB 0          \ the radius of the last constants (PM_CX, PM_CY: their
                        \ centre)
.pm_eu  EQUB 0
.pm_o   EQUB 0
.pm_m   SKIP 6          \ |mx|, |my|, |mz| >> 3
.pm_sg  SKIP 6          \ their signs (by 2)
.pm_nz  SKIP 6          \ &80 if non-zero (by 2)
.pm_tq  EQUW 0          \ mz^2 / rho2, 0.16        } a circle's orientation's
.pm_v   EQUW 0          \ mx^2 / (mx^2 + my^2), 0.16 } terms, and pm_f (7 bytes, in this
.pm_sx  EQUB 0          \ bit 7: mx < 0 (after negating m if mz < 0)
.pm_sy  EQUB 0          \ bit 7: my' < 0           } order: phk_c)
.pm_f   EQUB 0          \ floor(|w|) (the radius's, kept with them)
.pm_oc
.pm_oc1 SKIP 7          \ roofv's, kept while the orientation is held
.pm_oc2 SKIP 7          \ sidev's
.pm_rch EQUB 0          \ bit 7: the radius has changed since the last constants
.pm_ocy EQUB 0
.pm_new EQUB 0          \ bit 7: a new orientation this frame
.pm_mc  EQUB 0          \ MCNT when the constants were last made or kept
.PM_SPIN EQUB 0         \ frames the orientation may still be held
.pm_og  EQUB 0          \ the orientation's generation (one more for each new one)
.pm_rog EQUB 0          \ the rows in the disc layer's arrays: its generation,
.pm_rrd EQUB 0          \ radius,
.pm_rcx EQUW 0          \ centre
.pm_rcy EQUW 0
.pm_ndt EQUB 0          \ and rows (pm_save)
.pm_ndb EQUB 0
.pm_ulo EQUW 0
.pm_P                   \ 4-byte operands
.pm_X2  SKIP 4
.pm_Y2  SKIP 4
.pm_Z2  SKIP 4
.pm_XY  SKIP 4
.pm_R2  SKIP 4
.pm_Q2  SKIP 4

.pm_zsave SKIP 25       \ Elite's &10-&28 while PM_HOOK uses them
.pm_m8  SKIP 1

MCB = 20                \ bytes of a circle's constants (pm_blk, mc_blk)
.PM_BLK1 SKIP MCB       \ roofv's circle (PM_HOOK -> PM_MERID)
.PM_BLK2 SKIP MCB       \ sidev's
.PM_CX  SKIP 2          \ the planet's centre (K3, K4 at PM_HOOK)
.PM_CY  SKIP 2

.pm_blk                 \ a circle's constants (as PM_MERID's mc_blk)
.pm_a32 SKIP 4          \ a, 16.16 signed
.pm_K0  SKIP 4          \ K0 = D(0), 16.16
.pm_K2  SKIP 4          \ K2 = D(0) - D(1)
.pm_L0  SKIP 2          \ s0^2 - s0
.pm_s0  SKIP 1          \ round(sqrt(K0))
.pm_uP  SKIP 1          \ X+ valid on row y iff (y < uP) EOR neg
.pm_uM  SKIP 1          \ X- valid iff (y < uM) EOR neg
.pm_neg SKIP 1          \ 0 or 1
.pm_inv SKIP 1          \ 1 if m was negated
.pm_kw  SKIP 1          \ ceil(|w|): beyond it rows have no single crossing
ASSERT P% - pm_blk = MCB

\ ******************************************************************************
\
\ PM_MERID: the disc layer's boundaries R_NDN, R_NDX0-3 (ascending) and R_NDP
\ for rows R_NDT..R_NDB (spans R_NDISCL..R_NDISCR) from PM_BLK1/2 and the
\ centre PM_CX, PM_CY. Called by f_bounds (bank 6) through T_MERID, during
\ the frame, with this bank paged; it uses the rasteriser's scratch zero
\ page &10-&27 (F_FRAME has saved it).
\
\ For a great circle with normal m (Elite axes, y up, negated if need be so
\ that mz >= 0) and row Ys = y - cy (down), the projected ellipse crosses
\ the row at x = cx + a Ys -/+ sqrt(D), D = K0 - K2 Ys^2, with
\ a = -mx my' / rho2, K0 = r^2 mz^2 / rho2, K2 = mz^2 |m|^2 / rho2^2,
\ my' = -my, rho2 = mx^2 + mz^2. The X- crossing is on the visible hemisphere
\ iff the side function f = m.p is <= 0 at the row's left limb point, X+ iff
\ it is at the right one; along the limb f changes sign only at the circle's
\ nodes (rows cy -/+ w, w = r mx / sqrt(mx^2 + my^2)), so both tests are row
\ comparisons, and the row starts (left limb) on the f > 0 side iff X- is not
\ valid. Colour B where the surface point is on the same side of both planes
\ (as Elite's polyline construction had it). Boundary pixel = ceil(x), with
\ sqrt(D) rounded to the nearest integer. Rows go in pairs cy + k, cy - k
\ from the centre out, with D(k), s(k) = round(sqrt(D(k))) and cx + a k
\ stepped incrementally (no multiplies per row); the first circle's
\ crossings are stored in order, the second's inserted in order.
\
\ ******************************************************************************

CPU 1

MZ = &10                \ the rasteriser's scratch zero page: free until
mz_D  = MZ              \ T_DISCROWS. D(k) / 2, 16.16
mz_dl = MZ+4            \ (D(k) - D(k+1)) / 2, 16.16, saturating
mz_C  = MZ+8            \ cx + a k, 16.16 signed
mz_H  = MZ+12           \ (s * s - s) / 2
mz_yd = MZ+14           \ cy + k (low byte: the row, when visible)
mz_yu = MZ+15           \ cy - k
mz_c  = MZ+16           \ the row's centre, ceil(cx + a Ys)
mz_k  = MZ+18
mz_s  = MZ+19           \ round(sqrt(D(k)))
mp_ss = MZ+20           \ the half-chord used: s, or 0 once past
mp_F  = MZ+21           \ row cy + k: bit 7 visible, 6 X- valid, 5 X+ valid
mp_G  = MZ+22           \ row cy - k: the same
mp_ke = MZ+23           \ the flags hold for k < mp_ke

.PM_MERID
 JSR pm_shift           \ the last rows moved, if they can be (C clear)
 BCS P%+3
 RTS
 LDA #1                 \ every row: no crossings yet, and the colour at
 EOR PM_BLK1+mc_inv-mc_blk  \ the left limb, 1 EOR inv1 EOR inv2 EOR neg1
 EOR PM_BLK1+mc_neg-mc_blk  \ EOR neg2 EOR (y < uM1) EOR (y < uM2): constant
 EOR PM_BLK2+mc_inv-mc_blk  \ on [NDT, min uM), [min uM, max uM), [max uM,
 EOR PM_BLK2+mc_neg-mc_blk  \ NDB]
 STA mf_v
 LDY R_NDB
 INY
 STY mf_nb1
 LDA PM_BLK1+mc_uM-mc_blk
 LDY PM_BLK2+mc_uM-mc_blk
 CMP PM_BLK2+mc_uM-mc_blk
 BCC mfm1
 TAX
 TYA
 STX ar_hi
 BCS mfm1a
.mfm1
 STY ar_hi
.mfm1a
 TAY                    \ Y = min
 LDX R_NDT
 LDA mf_v
 JSR mf_fill
 EOR #1
 LDY ar_hi
 JSR mf_fill
 EOR #1
 LDY mf_nb1
 JSR mf_fill

 LDA PM_CX              \ 2 cx
 ASL A
 STA mp_cx2
 LDA PM_CX+1
 ROL A
 STA mp_cx2+1
 LDA R_NDT              \ rows cy + k visible for vd0 <= k < vd1, rows cy - k
 JSR mt_ucy             \ for vu0 <= k < vu1 (thresholds clamped to 0..255)
 STA mt_vd0
 LDA mf_nb1
 JSR mt_ucy
 STA mt_vd1
 LDA R_NDB
 JSR mt_cyu
 STA mt_vu0
 LDA R_NDT
 JSR mt_cyu1
 STA mt_vu1
 LDA mt_vd1             \ kvis + 1 = max(vd1, vu1)
 CMP mt_vu1
 BCS P%+5
 LDA mt_vu1
 STA mt_kv1
 LDA #1
 STA mt_one
 LDX #MCB-1             \ roofv's circle
.mfm7
 LDA PM_BLK1,X
 STA mc_blk,X
 DEX
 BPL mfm7
 STZ mp_p2
 JSR mc_pass
 LDX #MCB-1             \ sidev's: inserted in order
.mfm8
 LDA PM_BLK2,X
 STA mc_blk,X
 DEX
 BPL mfm8
 LDA #&80
 STA mp_p2
 JSR mc_pass
 STZ mp_p2
                        \ (falls into pm_save)

\ pm_save: what the rows in the disc layer's arrays are for: the centre,
\ radius, orientation and rows

.pm_save
 LDA PM_CX
 STA pm_rcx
 LDA PM_CX+1
 STA pm_rcx+1
 LDA PM_CY
 STA pm_rcy
 LDA PM_CY+1
 STA pm_rcy+1
 LDA pm_rs
 STA pm_rrd
 LDA pm_og
 STA pm_rog
 LDA R_NDT
 STA pm_ndt
 LDA R_NDB
 STA pm_ndb
 RTS

\ pm_shift: when the planet has only moved since the rows in the disc
\ layer's arrays were made (the same orientation and radius: PS_VALID,
\ pm_rog, pm_rrd), by -128..127 pixels each way, with its disc whole between
\ R_CL and R_CR in both places (no span is clipped, so no crossing is folded
\ but at the limb, which moves with it) and every new row among the old
\ ones, the new rows are the old ones moved: row y is row y - dy with dx
\ added to its boundaries, as PM_MERID would compute them (c - cx and the
\ node rows' y - cy do not depend on the centre). C clear if so; else C set
\ and nothing is changed

.pmsh9
 SEC
 RTS
.pm_shift
 BIT PS_VALID
 BPL pmsh9
 LDA pm_og
 CMP pm_rog
 BNE pmsh9
 LDA pm_rs
 CMP pm_rrd
 BNE pmsh9
 SEC                    \ dx = cx - its old value, -128..127 (mt_x: its
 LDA PM_CX              \ high byte, 0 or &FF)
 SBC pm_rcx
 STA pmsh_dx+1
 LDA PM_CX+1
 SBC pm_rcx+1
 JSR pmsh_s8
 BCS pmsh9
 SEC                    \ dy likewise (mt_t+1: its high byte)
 LDA PM_CY
 SBC pm_rcy
 STA mt_t
 LDA PM_CY+1
 SBC pm_rcy+1
 STA mt_t+1
 JSR pmsh_s8b
 BCS pmsh9
 LDA PM_CX              \ both discs between R_CL and R_CR
 LDX PM_CX+1
 JSR pmsh_in
 BCS pmsh9
 LDA pm_rcx
 LDX pm_rcx+1
 JSR pmsh_in
 BCS pmsh9
 LDA R_NDT              \ NDT - dy >= the old NDT, NDB - dy <= the old NDB
 SEC
 SBC mt_t
 TAY
 LDA #0
 SBC mt_t+1
 BNE pmsh9
 CPY pm_ndt
 BCC pmsh9
 LDA R_NDB
 SEC
 SBC mt_t
 TAY
 LDA #0
 SBC mt_t+1
 BNE pmsh9c
 CPY pm_ndb
 BEQ P%+4
 BCS pmsh9c
 BIT mt_t+1             \ moved up (dy < 0): rows from the top down
 BMI pmsh5
 LDY R_NDB              \ else from the bottom up: row Y from row X = Y - dy
.pmsh1
 TYA
 SEC
 SBC mt_t
 TAX
 JSR pmsh_row
 CPY R_NDT
 BEQ pmsh8
 DEY
 BRA pmsh1
.pmsh5
 LDY R_NDT
.pmsh6
 TYA
 SEC
 SBC mt_t
 TAX
 JSR pmsh_row
 CPY R_NDB
 BEQ pmsh8
 INY
 BRA pmsh6
.pmsh8
 JSR pm_save
 CLC
 RTS
.pmsh9c
 SEC
 RTS

.pmsh_row               \ row Y = row X moved by dx
 LDA R_NDN,X
 STA R_NDN,Y
 LDA R_NDP,X
 STA R_NDP,Y
 LDA R_NDX0,X
 CLC
.pmsh_dx
 ADC #0                 \ (patched: dx)
 STA R_NDX0,Y
 LDA R_NDX1,X
 CLC
 ADC pmsh_dx+1
 STA R_NDX1,Y
 LDA R_NDX2,X
 CLC
 ADC pmsh_dx+1
 STA R_NDX2,Y
 LDA R_NDX3,X
 CLC
 ADC pmsh_dx+1
 STA R_NDX3,Y
 RTS

.pmsh_s8b               \ (A, mt_t) a 16-bit difference: C clear if -128..127
 TAX
 LDA mt_t
 BRA pmsh_s8c
.pmsh_s8                \ (A, pmsh_dx+1) likewise
 TAX
 LDA pmsh_dx+1
.pmsh_s8c
 CPX #0
 BEQ pmss1
 CPX #&FF
 BNE pmss9
 CMP #&80               \ (high byte &FF: C clear if the low byte < &80, no)
 BCC pmss9
 CLC
 RTS
.pmss1
 CMP #&80               \ (high byte 0: C clear if the low byte < &80)
 RTS
.pmss9
 SEC
 RTS

.pmsh_in                \ (X A) = cx: C clear if cx - r >= R_CL and
 TAY                    \ cx + r <= R_CR (pm_rs = r)
 SEC
 SBC pm_rs
 PHA
 TXA
 SBC #0
 BNE pmsi8
 PLA
 CMP R_CL
 BCC pmsi9
 TYA
 CLC
 ADC pm_rs
 TAY
 TXA
 ADC #0
 BNE pmsi9
 CPY R_CR
 BEQ pmsi7
 BCS pmsi9
.pmsi7
 CLC
 RTS
.pmsi8
 PLA
.pmsi9
 SEC
 RTS

.mf_fill                \ rows X .. min(Y, NDB + 1) - 1: NDP = A, NDN = 0
 CPY mf_nb1
 BCC P%+5
 LDY mf_nb1
 STY mf_e
 CPX mf_e
 BCS mff9
.mff1
 STA R_NDP,X
 STZ R_NDN,X
 INX
 CPX mf_e
 BCC mff1
.mff9
 RTS

.mt_ucy                 \ A = clamp(A - cy) to 0..255
 SEC
 SBC PM_CY
 TAY
 LDA #0
 SBC PM_CY+1
 JMP mt_cl
.mt_cyu1                \ A = clamp(cy + 1 - A)
 SEC
 SBC #1
 BCS mt_cyu
 LDA PM_CY              \ (A was 0)
 CLC
 ADC #1
 TAY
 LDA PM_CY+1
 ADC #0
 JMP mt_cl
.mt_cyu                 \ A = clamp(cy - A)
 STA ar_hi
 LDA PM_CY
 SEC
 SBC ar_hi
 TAY
 LDA PM_CY+1
 SBC #0
.mt_cl                  \ (A Y) 16-bit signed -> 0..255
 BMI mtc0
 BNE mtc1
 TYA
 RTS
.mtc0
 LDA #0
 RTS
.mtc1
 LDA #255
 RTS

\ mc_pass: one circle's crossings (constants in mc_blk), rows cy +/- k

.mc_pass
 LDA mc_uM              \ validity thresholds in k: X- valid on row cy + k iff
 JSR mt_ucy             \ (k < md) EOR neg, on row cy - k iff (k >= mu) EOR
 STA mt_md              \ neg; X+ likewise with pd, pu
 LDA mc_uP
 JSR mt_ucy
 STA mt_pd
 LDA mc_uM
 JSR mt_cyu1
 STA mt_mu
 LDA mc_uP
 JSR mt_cyu1
 STA mt_pu
 LDX mc_kw
 INX
 STX mt_kw1
 LDA #0
 LDY mc_neg
 BEQ P%+4
 LDA #&60
 STA mt_neg
 LDX #3                 \ D/2 = K0/2, dl = K2/2 (D(0) - D(1) = K2)
.mp0
 LDA mc_K0,X
 STA mz_D,X
 LDA mc_K2,X
 STA mz_dl,X
 DEX
 BPL mp0
 LDA mc_K2              \ K2 and a into the row loop's ADC #s
 STA mpk0+1
 LDA mc_K2+1
 STA mpk1+1
 LDA mc_K2+2
 STA mpk2+1
 LDA mc_K2+3
 STA mpk3+1
 LDA mc_a
 STA mpa0+1
 LDA mc_a+1
 STA mpa1+1
 LDA mc_a+2
 STA mpa2+1
 LDA mc_a+3
 STA mpa3+1
 LSR mz_D+3
 ROR mz_D+2
 ROR mz_D+1
 ROR mz_D
 LSR mz_dl+3
 ROR mz_dl+2
 ROR mz_dl+1
 ROR mz_dl
 LDX #LO(mp_two)        \ the row routine for this circle
 LDY #HI(mp_two)
 BIT mp_p2
 BMI P%+6
 LDX #LO(mp_two1)
 LDY #HI(mp_two1)
 STX mpj1+1
 STY mpj1+2
 STX mpj2+1
 STY mpj2+2
 STZ mz_C
 STZ mz_C+1
 STZ mz_k
 STZ mp_past
 STZ mp_ke
 LDA PM_CX
 STA mz_C+2
 LDA PM_CX+1
 STA mz_C+3
 LDA PM_CY
 STA mz_yd
 STA mz_yu
 LDA mc_s0
 STA mz_s
 LDA mc_L0+1            \ H = L0 / 2
 LSR A
 STA mz_H+1
 LDA mc_L0
 ROR A
 STA mz_H

.mp_loop
 LDA mz_k
 CMP mp_ke
 BCC mp_body
 JSR mp_seg             \ new flags (C set: done)
 BCC mp_body
 RTS

.mp_body
 BIT mp_past
 BMI mp_c
.mp_s                   \ s = round(sqrt(D)): s drops while D/2 < H + 1/8
 LDA mz_s               \ (D < s^2 - s + 1/4)
 BEQ mp_s9
 LDA mz_D+1
 CMP #&20
 LDA mz_D+2
 SBC mz_H
 LDA mz_D+3
 SBC mz_H+1
 BCS mp_s9
 DEC mz_s               \ H -= s (the new s)
 LDA mz_H
 SEC
 SBC mz_s
 STA mz_H
 BCS mp_s
 DEC mz_H+1
 BCC mp_s
.mp_s9
 LDA mz_s
 STA mp_ss
.mp_c
 BIT mp_F               \ row cy + k: centre ceil(C)
 BPL mp_up
 LDA mz_C
 ORA mz_C+1
 CMP #1
 LDA mz_C+2
 ADC #0
 STA mz_c
 LDA mz_C+3
 ADC #0
 STA mz_c+1
 LDX mz_yd
 LDA mp_F
.mpj1
 JSR mp_two             \ (patched: mp_two1 for the first circle)
.mp_up
 BIT mp_G               \ row cy - k: centre ceil(2 cx - C) = 2 cx - floor(C)
 BPL mp_adv
 LDA mp_cx2
 SEC
 SBC mz_C+2
 STA mz_c
 LDA mp_cx2+1
 SBC mz_C+3
 STA mz_c+1
 LDX mz_yu
 LDA mp_G
.mpj2
 JSR mp_two
.mp_adv
 BIT mp_past            \ D -= dl, dl += K2 (past the ellipse once D < 0)
 BMI mp_a2
 SEC                    \ (D is kept to 1/256: its low byte is not used)
 LDA mz_D+1
 SBC mz_dl+1
 STA mz_D+1
 LDA mz_D+2
 SBC mz_dl+2
 STA mz_D+2
 LDA mz_D+3
 SBC mz_dl+3
 STA mz_D+3
 BCS mp_a1
 LDA #&80               \ past: s = 0 from now on, and new flags next time
 STA mp_past
 STZ mp_ss
 LDX mz_k
 INX
 STX mp_ke
 BRA mp_a2
.mp_a1
 CLC                    \ (the ADC #s: K2, patched by mc_pass)
 LDA mz_dl
.mpk0
 ADC #0
 STA mz_dl
 LDA mz_dl+1
.mpk1
 ADC #0
 STA mz_dl+1
 LDA mz_dl+2
.mpk2
 ADC #0
 STA mz_dl+2
 LDA mz_dl+3
.mpk3
 ADC #0
 STA mz_dl+3
 BCC mp_a2
 LDA #&FF
 STA mz_dl
 STA mz_dl+1
 STA mz_dl+2
 STA mz_dl+3
.mp_a2
 CLC                    \ C += a (the ADC #s: a, patched by mc_pass)
 LDA mz_C
.mpa0
 ADC #0
 STA mz_C
 LDA mz_C+1
.mpa1
 ADC #0
 STA mz_C+1
 LDA mz_C+2
.mpa2
 ADC #0
 STA mz_C+2
 LDA mz_C+3
.mpa3
 ADC #0
 STA mz_C+3
 INC mz_yd
 DEC mz_yu
 INC mz_k
 JMP mp_loop

\ mp_seg: the flags for rows cy +/- k, and the next k at which any changes
\ (C set if the pass is done: k > kvis, or past the ellipse and k > kw)

.mps9
 SEC
 RTS
.mp_seg
 LDA mz_k
 CMP mt_kv1
 BCS mps9
 BIT mp_past
 BPL mps1
 CMP mt_kw1
 BCS mps9
.mps1                   \ F: k in [vd0, vd1), (k < md, k < pd) EOR neg
 LDX #0
 LDA mz_k
 CMP mt_pd
 BCS P%+4
 LDX #&20
 CMP mt_md
 BCS mps2
 TXA
 ORA #&40
 TAX
 LDA mz_k
.mps2
 CMP mt_vd0
 BCC mps3
 CMP mt_vd1
 BCS mps3
 TXA
 ORA #&80
 TAX
.mps3
 TXA
 EOR mt_neg
 JSR mps_past
 STA mp_F
 LDX #0                 \ G: k >= 1, k in [vu0, vu1), (k >= mu, k >= pu) EOR
 LDA mz_k               \ neg
 CMP mt_pu
 BCC P%+4
 LDX #&20
 CMP mt_mu
 BCC mps4
 TXA
 ORA #&40
 TAX
 LDA mz_k
.mps4
 CMP #1
 BCC mps5
 CMP mt_vu0
 BCC mps5
 CMP mt_vu1
 BCS mps5
 TXA
 ORA #&80
 TAX
.mps5
 TXA
 EOR mt_neg
 JSR mps_past
 STA mp_G
 LDA #255               \ next boundary: the least threshold above k
 STA mp_ke
 LDX #mt_n-1
.mpn1
 LDA mt_tab,X
 CMP mz_k
 BCC mpn2
 BEQ mpn2
 CMP mp_ke
 BCS mpn2
 STA mp_ke
.mpn2
 DEX
 BPL mpn1
 CLC
 RTS

.mps_past               \ past the ellipse: no crossings unless exactly one
 BIT mp_past            \ of X-, X+ is valid
 BPL mpp9
 STA mt_t
 ASL A
 EOR mt_t
 AND #&40
 BNE mpp8
 LDA mt_t
 AND #&80
 RTS
.mpp8
 LDA mt_t
.mpp9
 RTS

\ mp_two: row X, flags A (bit 6 X- valid, bit 5 X+ valid), centre mz_c,
\ half-chord mp_ss. A crossing at or left of the span's left end flips the
\ row's start colour, one right of the span is dropped, one inside is added.

\ mp_two1: the same for the first circle, whose rows are still empty
\ (R_NDN = 0): crossings are stored in order, the count written once

.mp_two1
 ASL A
 ASL A                  \ C = X- valid, N = X+ valid
 STA mt_t
 LDY #0
 BCC m1p
 LDA mz_c               \ X-: c - s (C set)
 SBC mp_ss
 STA mt_x
 LDA mz_c+1
 SBC #0
 BMI m1f
 BNE m1p
 LDA mt_x
 CMP R_NDISCL,X
 BCC m1f
 BEQ m1f
 CMP R_NDISCR,X
 BEQ P%+4
 BCS m1p
 STA R_NDX0,X
 INY
 BNE m1p
.m1f
 LDA R_NDP,X
 EOR #1
 STA R_NDP,X
.m1p
 BIT mt_t
 BPL m1e
 LDA mz_c               \ X+: c + s
 CLC
 ADC mp_ss
 STA mt_x
 LDA mz_c+1
 ADC #0
 BMI m1g
 BNE m1e
 LDA mt_x
 CMP R_NDISCL,X
 BCC m1g
 BEQ m1g
 CMP R_NDISCR,X
 BEQ P%+4
 BCS m1e
 CPY #0
 BNE m1q
 STA R_NDX0,X
 INY
 TYA
 STA R_NDN,X
 RTS
.m1q
 STA R_NDX1,X
 INY
.m1e
 TYA
 STA R_NDN,X
 RTS
.m1g
 LDA R_NDP,X
 EOR #1
 STA R_NDP,X
 TYA
 STA R_NDN,X
 RTS

.mpt_l                  \ X- left of the span: flip, then X+
 JSR mpt_f
 JMP mpt2
.mp_two
 ASL A
 ASL A                  \ C = X- valid, N = X+ valid
 STA mt_t
 BCC mpt2
 LDA mz_c               \ X-: c - s (C set)
 SBC mp_ss
 TAY
 LDA mz_c+1
 SBC #0
 BMI mpt_l
 BNE mpt2
 TYA
 JSR mp_put
.mpt2
 BIT mt_t
 BPL mpt9
 LDA mz_c               \ X+: c + s
 CLC
 ADC mp_ss
 TAY
 LDA mz_c+1
 ADC #0
 BMI mpt_f
 BNE mpt9
 TYA
.mp_put                 \ A = x (0..255) on row X
 CMP R_NDISCL,X
 BCC mpt_f
 BEQ mpt_f
 CMP R_NDISCR,X
 BEQ P%+4
 BCS mpt9
 LDY R_NDN,X             \ (the second circle: insert in order)
 INC R_NDN,X
 JMP mpi
.mpt_f
 LDA R_NDP,X
 EOR #1
 STA R_NDP,X
.mpt9
 RTS
.mpi                    \ the second: insert x into the sorted R_NDX0..
 STA mt_x               \ R_NDX(Y-1)
 CPY #2
 BEQ mpi2
 BCS mpi3
 CPY #1
 BEQ mpi1
 STA R_NDX0,X
 RTS
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

.mp_cx2 EQUW 0          \ 2 cx
.mp_past EQUB 0         \ bit 7: past the ellipse's last row (D < 0)
.mf_v   EQUB 0
.mf_nb1 EQUB 0          \ NDB + 1
.mf_e   EQUB 0
.ar_hi  EQUB 0
.mt_t   EQUW 0
.mt_x   EQUB 0
.mp_p2  EQUB 0          \ bit 7: the second circle (insert in order)
.mt_neg EQUB 0          \ &60 if neg
.mt_tab                 \ thresholds in k (0..255)
.mt_vd0 EQUB 0
.mt_vd1 EQUB 0
.mt_vu0 EQUB 0
.mt_vu1 EQUB 0
.mt_md  EQUB 0
.mt_pd  EQUB 0
.mt_mu  EQUB 0
.mt_pu  EQUB 0
.mt_one EQUB 1
.mt_kv1 EQUB 0          \ kvis + 1
.mt_kw1 EQUB 0          \ kw + 1
mt_n = P% - mt_tab

                        \ a circle's constants (MCB bytes)
.mc_blk
.mc_a   SKIP 4          \ a, 16.16 signed
.mc_K0  SKIP 4          \ K0 = D(0), 16.16
.mc_K2  SKIP 4          \ K2 = D(0) - D(1)
.mc_L0  SKIP 2          \ s0^2 - s0
.mc_s0  SKIP 1          \ round(sqrt(K0))
.mc_uP  SKIP 1          \ X+ valid on row y iff (y < uP) EOR neg
.mc_uM  SKIP 1          \ X- valid iff (y < uM) EOR neg
.mc_neg SKIP 1          \ 0 or 1
.mc_inv SKIP 1          \ 1 if m was negated
.mc_kw  SKIP 1          \ ceil(|w|): beyond it rows have no single crossing

