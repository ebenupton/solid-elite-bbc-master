\ ******************************************************************************
\
\ gfx-planet7.asm - the planet's styles (sideways RAM bank 7, in the meridian
\ window after gfx-merid.asm and gfx-kept7.asm, paged as ROMSEL MERIDBANK;
\ docs/memory-map.md)
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
\     from the system's seed (pf_craters), base 0.
\
\ Elite's state is not touched: Elite's zero page &10-&28 (the engine's
\ workspace) is saved and restored, and A, X, Y and the flags are preserved.
\ The frame layer makes the rows through T_CAPS (gfx-merid.asm's PC_ROWS).
\ 6-harness/planet_caps.py models it all bit for bit.
\
\ ******************************************************************************

.PF_HOOK
 PHP
 PHA
 PHX
 PHY
 STZ PC_N
 LDA TYPE               \ the class: a crater planet (TYPE 130) 1, a meridian
 LSR A                  \ planet (128) 0
 AND #1
 STA PF_CLS
 LDA K+1                \ the detail only below a radius of 256, as PL9 has
 BNE pfh9               \ it, and from 6 up, as its meridians
 LDA K
 CMP #6
 BCC pfh9
 STA pcr
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
 STZ pc_inv
 LDA PF_CLS
 BNE pfh2
 INC pc_inv             \ (the beach ball: base 1)
 JSR pf_beach
 BRA pfh3
.pfh2
 JSR pf_craters
.pfh3
 LDA PC_N               \ (records, or a base colour)
 ORA pc_inv
 BEQ pfh7
 LDA #&80
 TSB PF_CLS
.pfh7
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

.pft_f EQUB 0           \ pf_tilt's
.pft_x EQUB 0
.pft_y EQUB 0
.pft_k EQUB 0
.pft_k2 EQUB 0
.pft_n EQUB 0
.pft_r EQUW 0
.pft_s EQUW 0
