\ ******************************************************************************
\
\ gfx-planet7.asm - the planet's styles and its moon (sideways RAM
\ bank 7, in the meridian window after gfx-merid.asm and gfx-kept7.asm, paged
\ as ROMSEL MERIDBANK; docs/memory-map.md)
\
\ PF_HOOK, in game context (G_PFHOOK, from H_CIRC): the planet's class
\ (PF_CLS) and its style as a few circles on its sphere, each a record made
\ by gfx-merid.asm's pc_circ (which describes the method), and a base colour
\ (pc_inv):
\
\   * class 0, a meridian planet (TYPE 128): the beach ball, the great
\     circles normal to roofv and sidev, base 1 (colour B where the surface
\     is on the same side of both planes, as Elite's equator and meridian
\     divide it);
\
\   * class 1, a crater planet (TYPE 130): one to three craters, small caps
\     from the system's seed (pf_craters), base 0;
\
\   * class 2, a banded crater planet (a quarter of them, by the seed: only
\     in a build with make bands=on, _PLANET_BANDS): two
\     latitude circles about the spin axis, EOR'd (pf_bands), base 0.
\
\ Then the moon (pf_moon, with its crater's record in slot PCMAX), when the
\ seed has one. Elite's state is not
\ touched: Elite's zero page &10-&28 (the engine's workspace) is saved and
\ restored, and A, X, Y and the flags are preserved. The frame layer makes
\ the rows through T_CAPS and T_MCAPS (gfx-merid.asm's PC_ROWS, PC_MROWS).
\ 6-harness/planet_caps.py models it all bit for bit.
\
\ ******************************************************************************

.PF_HOOK
 PHP
 PHA
 PHX
 PHY
 STZ PC_N
 STZ MN_ON
 LDA TYPE               \ the class: a crater planet (TYPE 130) 1, a meridian
 LSR A                  \ planet (128) 0
 AND #1
 STA PF_CLS
 IF _PLANET_BANDS       \ (banded planets: make bands=on)
 BEQ pfh4
 LDA QQ2+3              \ s1_hi bits 0-1 both clear (a quarter of the crater
 AND #3                 \ planets): banded, class 2 (Lave is a meridian
 BNE pfh4               \ planet, so it keeps its beach ball)
 LDA #2
 STA PF_CLS
.pfh4
 ENDIF
 LDA K+1                \ the detail only below a radius of 256, as PL9 has
 BNE pfh9               \ it, and from 6 up, as its meridians
 LDA K
 CMP #6
 BCC pfh9
 STA pcr
 STA pf_r
 LDX #24                \ (Elite's &10-&28: the engine's workspace)
.pfh0
 LDA &10,X
 STA pm_zsave,X
 DEX
 BPL pfh0
 LDA K3                 \ the centre (K3 and K4 are in &10-&28: read before
 STA pcbx               \ the workspace is used)
 LDA K3+1
 STA pcbx+1
 LDA K4
 STA pcby
 LDA K4+1
 STA pcby+1
 LDX #4                 \ (the planet's centre and radius, kept for pf_moon)
.pfh5
 LDA pcbx,X
 STA pf_cx,X
 DEX
 BPL pfh5
 STZ pc_inv
 LDA PF_CLS
 BNE pfh2
 INC pc_inv             \ (the beach ball: base 1)
 JSR pf_beach
 BRA pfh3
.pfh2
 IF _PLANET_BANDS
 CMP #2
 BNE pfh6
 JSR pf_bands
 BRA pfh3
.pfh6
 ENDIF
 JSR pf_craters
.pfh3
 LDA PC_N               \ (records, or a base colour)
 ORA pc_inv
 BEQ pfh7
 LDA #&80
 TSB PF_CLS
.pfh7
 JSR pf_moon            \ (pf_moon first: it sets mn_h)
 LDX #24
.pfh1
 LDA pm_zsave,X
 STA &10,X
 DEX
 BPL pfh1
.pfh9
 PLY
 PLX
 PLA
 PLP
 RTS

\ pf_beach: a meridian planet's two great circles, normal to roofv and sidev
\ pf_one: a circle of cosine A (positive) about vector X (INWK offset) alone

.pf_beach
 LDX #15
 JSR pf_gc
 LDX #21
.pf_gc
 LDA #0
.pf_one
 PHA
 LDY #0
 TYA
 JSR pf_tilt
 PLA
 STA pcc
 STZ pcneg
 JMP pc_circ

\ pf_craters: a crater planet's caps, from the system's seed (QQ2): the
\ first on roofv, 30 degrees across (Elite's crater: at 222/256 of the radius
\ from the centre, half the radius across); then, as the seed has it, one on
\ nosev (either way) tilted towards sidev, and one on sidev tilted towards
\ roofv, each 15 to 30 degrees. No two axes are closer than 63 degrees, so
\ the craters never overlap.

.pf_craters
 LDX #15                \ roofv
 LDA #222
 JSR pf_one
 LDA QQ2+4              \ s2_lo bits 0-1: more caps (0, 1, 2, 1)
 AND #3
 BEQ pfc9
 PHA
 LDA QQ2+4              \ bits 2-4: the second's signs and tilt
 LSR A
 LSR A
 AND #7
 LDX #9                 \ nosev, tilted towards sidev
 LDY #21
 JSR pf_tilt
 LDA QQ2+5              \ s2_hi bits 0-1: its size
 JSR pf_size
 PLA
 CMP #2
 BNE pfc9
 LDA QQ2+4              \ bits 5-7: the third's
 LSR A
 LSR A
 LSR A
 LSR A
 LSR A
 LDX #21                \ sidev, tilted towards roofv
 LDY #15
 JSR pf_tilt
 LDA QQ2+5              \ s2_hi bits 2-3
 LSR A
 LSR A
.pf_size                \ a crater of A bits 0-1's size (15, 20, 25 or 30
 AND #3                 \ degrees) on pcv
 TAX
 LDA pfs_c,X
 STA pcc
 STZ pcneg
 JMP pc_circ
.pfc9
 RTS
.pfs_c EQUB 247, 241, 232, 222

IF _PLANET_BANDS        \ (make bands=on)

\ pf_bands: a banded planet's two latitude circles, the edges of its belt,
\ about the axis the planet spins about. Its pitch and roll (MVEIT part 8:
\ pitch turns roofv and nosev, roll roofv and sidev, alike) turn it about
\ nosev - sidev, which stays put. North of the one edge (cosine c1) and
\ south of the other (-c2), EOR'd: the belt between them is colour B, the
\ two polar zones colour A. c1 and c2 from the seed (s2_hi bits 4-7)

.pf_bands
 LDX #9                 \ (nosev - sidev) / 2
 LDY #21
 LDA #%1010
 JSR pf_tilt
 LDA QQ2+5
 LSR A
 LSR A
 LSR A
 LSR A
 PHA
 AND #3
 TAX
 LDA pfb_n,X
 STA pcc
 STZ pcneg
 JSR pc_circ
 PLA
 LSR A
 LSR A
 TAX
 LDA pfb_s,X
 STA pcc
 LDA #&80
 STA pcneg
 JMP pc_circ
.pfb_n EQUB 64, 96, 128, 150    \ the north edge's latitude: 14 to 36 degrees
.pfb_s EQUB 32, 64, 96, 128     \ the south edge's: -7 to -30 degrees

ENDIF

\ pf_tilt: pcv = (+/- vector X) / 2 + (+/- vector Y) / 2^(k+1), as
\ sign-magnitude words (X, Y = 9 nosev, 15 roofv, 21 sidev; Y = 0: none), A
\ bits 0-3: bit 0 the first's sign, bit 1 the second's, bit 2 k = 2, else
\ k = 1 (a tilt of 14 or 27 degrees), bit 3 k = 0 (an equal weight); each
\ magnitude shifted before its sign is applied (so a vector alone is exactly
\ halved). Halved, as the sums must fit 15 bits (a circle depends on its
\ axis' direction only); pcn = 2^24 / the sum's nominal length (>> 3)

.pf_tilt
 STA pft_f
 STX pft_x
 STY pft_y
 LDX #0                 \ pcn: 1536 (a vector halved), 1536 sqrt(1 + 1/4) or
 CPY #0                 \ sqrt(1 + 1/16) (k = 1, 2), 1536 sqrt(2) (k = 0)
 BEQ pft0
 INX
 AND #12
 BEQ pft0
 INX
 CMP #4
 BEQ pft0
 INX
.pft0
 LDA pfn_lo,X
 STA pcn
 LDA pfn_hi,X
 STA pcn+1
 LDA pfn_k,X            \ (the second's shift)
 STA pft_k2
 LDY #4                 \ each component, Y = 4, 2, 0
.pft1
 STZ pft_r
 STZ pft_r+1
 LDX pft_y              \ a vector alone (a crater on roofv, the beach ball's
 BNE pft2               \ circles): its magnitude halved, its sign kept
 TYA
 CLC
 ADC pft_x
 TAX
 LDA INWK+1,X
 PHA
 AND #&7F
 LSR A
 STA pft_r+1
 LDA INWK,X
 ROR A
 STA pcv,Y
 PLA
 AND #&80
 ORA pft_r+1
 BRA pft5
.pft2
 LDX pft_x              \ the first, halved and signed
 LDA pft_f
 STA pft_n
 LDA #1
 JSR pft_add
 LDX pft_y              \ the second, shifted k + 1 times and signed
 LDA pft_f
 LSR A
 STA pft_n
 LDA pft_k2
 JSR pft_add
.pft4
 LDA pft_r+1            \ to sign-magnitude
 BPL pft4a
 LDA #0
 SEC
 SBC pft_r
 STA pft_r
 LDA #0
 SBC pft_r+1
 ORA #&80
.pft4a
 TAX
 LDA pft_r
 STA pcv,Y
 TXA
.pft5
 STA pcv+1,Y
 DEY
 DEY
 BPL pft1
 RTS

.pfn_lo EQUB LO(10923), LO(9770), LO(10596), LO(7723)
.pfn_hi EQUB HI(10923), HI(9770), HI(10596), HI(7723)
.pfn_k  EQUB 0, 2, 3, 1

\ pft_add: pft_r += the INWK word at X + Y, its magnitude shifted right A
\ times, negated if its sign EOR pft_n bit 0 is set (Y kept)

.pft_add
 STA pft_k
 STX pft_s
 TYA
 CLC
 ADC pft_s
 TAX
 LDA pft_n
 LSR A
 LDA INWK+1,X
 BCC P%+4
 EOR #&80
 STA pft_n
 AND #&7F
 STA pft_s+1
 LDA INWK,X
 STA pft_s
 LDX pft_k
.pfa1
 LSR pft_s+1
 ROR pft_s
 DEX
 BNE pfa1
 BIT pft_n
 BMI pfa2
 CLC
 LDA pft_r
 ADC pft_s
 STA pft_r
 LDA pft_r+1
 ADC pft_s+1
 STA pft_r+1
 RTS
.pfa2
 SEC
 LDA pft_r
 SBC pft_s
 STA pft_r
 LDA pft_r+1
 SBC pft_s+1
 STA pft_r+1
 RTS

\ ******************************************************************************
\
\ The moon (game context, as PF_HOOK)
\
\ ******************************************************************************

\ pf_moon: a moon, for the systems whose seed has one (h = s0_hi EOR s1_hi
\ EOR s2_hi, bits 0-1 = 1: a quarter of them), and planets of radius 16 up.
\ It is scenery: no ship slot, no random number, no saved state. It sits at
\ E = MN_E from the planet's centre, a vector fixed in space (gfx-ssun.asm's
\ MN_TURN puts it on the planet's spin axis, on the side h bit 4 gives and
\ 3 to 5.25 planet radii out by h bits 2-3, when we arrive or launch, and
\ MN_TURN turns it with our roll and pitch, as the game turns the planet's
\ position), with a radius rho (0.19 to 0.28 of the planet's, h bits 5-6).
\ Its centre M = P + E (P the planet's position, INWK, and E, both in the
\ view's axes as PLUT turns them) is projected as Elite projects:
\
\   x = 128 + 256 M_x / M_z,  y = 96 - 256 M_y / M_z,
\   radius = rho 96 256 / M_z (at most 63),
\
\ M shifted right until M_z fits 15 bits. It is behind the planet if
\ e_z > 0 (E's z in the view's axes), behind the sun (slot 1) if further
\ than it. Its crater (on roofv, 40 degrees across: radius 10 up) is a
\ record of pc_circ's, in slot PCMAX. MN_ON (bit 7 on, 6 behind the planet,
\ 5 behind the sun), MN_X, MN_Y, MN_R, MN_Z (16 bits, &FFFF if further),
\ MN_INV and MN_N (its crater) are what the frame reads.
\ 6-harness/planet_caps.py's pf_moon models it.

.pfm9
 RTS
.pf_moon
 LDA QQ2+1              \ h
 EOR QQ2+3
 EOR QQ2+5
 STA mn_h
 AND #3
 CMP #1
 BNE pfm9
 LDA pcr                \ (r: 16 up)
 CMP #16
 BCC pfm9
 BIT MN_OK              \ (its place known: MN_TURN)
 BPL pfm9
 LDA VIEW               \ M = P + E in the view's axes (PLUT's): P from INWK,
 STA mn_v               \ E_j from MN_E by pfm_vs and pfm_vn (3 VIEW + i), as
 ASL A                  \ 24-bit two's complement, x, y, z (by 3)
 ADC mn_v
 STA mn_v
 LDX #0
.pfm1
 LDA INWK,X             \ P_i
 STA mn_m,X
 LDA INWK+1,X
 STA mn_m+1,X
 LDA INWK+2,X
 AND #&7F
 STA mn_m+2,X
 LDA INWK+2,X
 BPL pfm2
 SEC
 LDA #0
 SBC mn_m,X
 STA mn_m,X
 LDA #0
 SBC mn_m+1,X
 STA mn_m+1,X
 LDA #0
 SBC mn_m+2,X
 STA mn_m+2,X
.pfm2
 TXA                    \ (i = X / 3)
 LDY #&FF
 SEC
.pfm3
 INY
 SBC #3
 BCS pfm3
 TYA
 CLC
 ADC mn_v
 TAY
 LDA pfm_vn,Y
 STA mn_sg
 LDA pfm_vs,Y
 TAY
 LDA MN_E,Y             \ E_j, negated if pfm_vn says
 STA mn_n
 LDA MN_E+1,Y
 STA mn_n+1
 LDA MN_E+2,Y
 STA mn_n+2
 BIT mn_sg
 BPL pfm4
 SEC
 LDA #0
 SBC mn_n
 STA mn_n
 LDA #0
 SBC mn_n+1
 STA mn_n+1
 LDA #0
 SBC mn_n+2
 STA mn_n+2
.pfm4
 CPX #6                 \ (e_z for the behind test)
 BNE pfm5
 LDA mn_n
 ORA mn_n+1
 ORA mn_n+2
 BEQ pfm5a
 LDA mn_n+2
 EOR #&80
.pfm5a
 STA mn_t               \ (bit 7: e_z > 0)
.pfm5
 CLC
 LDA mn_m,X
 ADC mn_n
 STA mn_m,X
 LDA mn_m+1,X
 ADC mn_n+1
 STA mn_m+1,X
 LDA mn_m+2,X
 ADC mn_n+2
 STA mn_m+2,X
 INX
 INX
 INX
 CPX #9
 BEQ P%+5
 JMP pfm1
 LDA mn_m+8             \ M_z > 0, or none
 BMI pfm9a
 ORA mn_m+7
 ORA mn_m+6
 BNE pfm6
.pfm9a
 RTS
.pfm6
 LDX #2                 \ (M_z, 24-bit, for the sun's test) and MN_Z: 16
.pfm6a                  \ bits, &FFFF if further
 LDA mn_m+6,X
 STA mn_z,X
 DEX
 BPL pfm6a
 LDA mn_z
 STA MN_Z
 LDA mn_z+1
 STA MN_Z+1
 LDA mn_z+2
 BEQ pfm6b
 LDA #&FF
 STA MN_Z
 STA MN_Z+1
.pfm6b
 LDY #0                 \ M shifted right together until M_z fits 15 bits
.pfm7                   \ (Y shifts; pfm_div's divisor)
 LDA mn_m+8
 BNE pfm7b
 LDA mn_m+7
 BPL pfm8
.pfm7b
 LDX #6
.pfm7a
 LDA mn_m+2,X
 CMP #&80
 ROR mn_m+2,X
 ROR mn_m+1,X
 ROR mn_m,X
 DEX
 DEX
 DEX
 BPL pfm7a
 INY
 BRA pfm7
.pfm8
 STY mn_s
 LDA mn_m+6
 STA mn_q
 LDA mn_m+7
 STA mn_q+1
 LDX #0                 \ x = 128 + 256 M_x / M_z
 JSR pfm_xy
 BCS pfm9c
 STA MN_X+1
 STY MN_X
 LDX #3                 \ y = 96 - 256 M_y / M_z
 JSR pfm_xy
 BCC pfm9d
.pfm9c
 RTS
.pfm9d
 STA MN_Y+1
 STY MN_Y
 LDA mn_h               \ radius = rho 96 256 / M_z (rho / 256 of the
 LSR A                  \ planet's radius, 24576)
 LSR A
 LSR A
 LSR A
 LSR A
 AND #3
 TAX
 LDA pfm_rho,X
 LDX #96
 JSR pm_mul8
 STA mn_n+2
 LDA pm_m8
 STA mn_n+1
 STZ mn_n
 LDY mn_s
 BEQ pfm8b
.pfm8a
 LSR mn_n+2
 ROR mn_n+1
 ROR mn_n
 DEY
 BNE pfm8a
.pfm8b
 JSR pfm_div
 LDA mn_n+1
 ORA mn_n+2
 BNE pfm10a
 LDA mn_n
 CMP #2
 BCC pfm9c
 CMP #64
 BCC pfm10b
.pfm10a
 LDA #63
.pfm10b
 STA MN_R
 LDA #&80               \ on; behind the planet if e_z > 0
 BIT mn_t
 BPL pfm10
 ORA #&40
.pfm10
 STA MN_ON
 LDA FRIN+1             \ behind the sun: the sun in slot 1, in front of us,
 CMP #129               \ nearer than the moon
 BNE pfm11
 LDA K%+37+8
 BMI pfm11
 LDA K%+37+6
 CMP mn_z
 LDA K%+37+7
 SBC mn_z+1
 LDA K%+37+8
 SBC mn_z+2
 BCS pfm11
 LDA #&20
 TSB MN_ON
.pfm11
 LDA MN_R               \ its crater (radius 10 up)
 CMP #10
 BCC pfm12
 LDA PC_N
 PHA
 LDA pc_inv
 PHA
 LDA #PCMAX
 STA PC_N
 STZ pc_inv
 LDA MN_X
 STA pcbx
 LDA MN_X+1
 STA pcbx+1
 LDA MN_Y
 STA pcby
 LDA MN_Y+1
 STA pcby+1
 LDA MN_R
 STA pcr
 LDX #15
 LDA #MOON_C8
 JSR pf_one
 LDA PC_N
 STA MN_N
 LDA pc_inv
 STA MN_INV
 PLA
 STA pc_inv
 PLA
 STA PC_N
 RTS
.pfm12
 LDA #PCMAX
 STA MN_N
 STZ MN_INV
 RTS

\ pfm_xy: the moon's x (X = 0) or y (X = 3) on the screen, 128 + 256 M_x / M_z
\ or 96 - 256 M_y / M_z (mn_m, M_z in mn_q), in (A Y), C set if it is out of
\ range (X kept)

.pfm_xy
 LDA mn_m+2,X           \ |M_i| (16 bits, else out of range), its sign (y's
 STA mn_sg              \ turned) in mn_sg
 CPX #0
 BEQ pfx0
 EOR #&80
 STA mn_sg
.pfx0
 LDA mn_m,X
 STA mn_n+1
 LDA mn_m+1,X
 STA mn_n+2
 LDA mn_m+2,X
 BPL pfx1
 SEC
 LDA #0
 SBC mn_n+1
 STA mn_n+1
 LDA #0
 SBC mn_n+2
 STA mn_n+2
 LDA #0
 SBC mn_m+2,X
.pfx1
 BNE pfx9
 STZ mn_n               \ (times 256)
 PHX
 JSR pfm_div
 PLX
 LDA mn_n+2             \ (at most 16383)
 BNE pfx9
 LDA mn_n+1
 CMP #&40
 BCS pfx9
 BIT mn_sg
 BPL pfx4
 SEC
 LDA #0
 SBC mn_n
 STA mn_n
 LDA #0
 SBC mn_n+1
 STA mn_n+1
.pfx4
 CLC                    \ + the screen's centre (128 or 96)
 LDA mn_n
 ADC pfm_ctr,X
 TAY
 LDA mn_n+1
 ADC #0
 CLC
 RTS
.pfx9
 SEC
 RTS

\ pfm_div: mn_n (24-bit) = mn_n / mn_q (15-bit), unsigned

.pfm_div
 STZ mn_r
 STZ mn_r+1
 LDX #24
.pmd1
 ASL mn_n
 ROL mn_n+1
 ROL mn_n+2
 ROL mn_r
 ROL mn_r+1
 LDA mn_r
 SEC
 SBC mn_q
 TAY
 LDA mn_r+1
 SBC mn_q+1
 BCC pmd2
 STA mn_r+1
 STY mn_r
 INC mn_n
.pmd2
 DEX
 BNE pmd1
 RTS

MOON_C8 = 196           \ the moon's crater: cos 40 degrees
\ the view's axes (PLUT's): by 3 VIEW + i, E's axis (0, 3, 6) and a sign;
\ front (x, y, z), rear (-x, y, -z), left (z, y, -x), right (-z, y, x)
.pfm_vs EQUB 0, 3, 6, 0, 3, 6, 6, 3, 0, 6, 3, 0
.pfm_vn EQUB 0, 0, 0, &80, 0, &80, 0, 0, &80, &80, 0, 0
.pfm_rho EQUB 48, 56, 64, 72
.pfm_ctr EQUB 128, 0, 0, 96
.mn_h  EQUB 0
.mn_v  EQUB 0
.mn_t  EQUB 0
.mn_s  EQUB 0
.mn_m  SKIP 9           \ M = P + E in the view's axes (x, y, z, two's complement)
.mn_q  EQUW 0
.mn_n  SKIP 3
.mn_r  EQUW 0
.mn_sg EQUB 0
.mn_z  SKIP 3

.pf_cx EQUW 0           \ the planet's centre and radius (PF_HOOK)
.pf_cy EQUW 0
.pf_r  EQUB 0
.pft_f EQUB 0           \ pf_tilt's
.pft_x EQUB 0
.pft_y EQUB 0
.pft_k EQUB 0
.pft_k2 EQUB 0
.pft_n EQUB 0
.pft_r EQUW 0
.pft_s EQUW 0
