\ ******************************************************************************
\
\ elite-moon.asm - the moon is solid: flying into it kills us, as flying into
\ the planet does
\
\ Port: at bank 4's end (elite-layout.asm, after the renderer's game-context
\ routines), called from the main flight loop's part 15 (MA22) with bank 4
\ paged. The moon (gfx-planet7.asm's pf_moon draws it) is in the systems
\ whose seed has one (h = s0_hi EOR s1_hi EOR s2_hi, bits 0-1 = 1): at
\ MN_E from the planet's centre (gfx-ssun.asm's MN_TURN places it in the
\ system, on the planet's spin axis, and MN_TURN keeps it fixed in space),
\ with a radius of rho planet radii (rho = 48, 56, 64 or 72 / 256 by h bits
\ 5-6), the planet's radius being 96 in the coordinates' high bytes, as in
\ MA22's own test.
\
\ MOONHIT makes the test on the planet's altitude iteration (MCNT mod 32 = 10,
\ as MA22's), in the coordinates' high bytes (units of 256): the moon's centre
\ is M = P + e, P the planet's position and e = MN_E >> 8; and we have flown
\ into the moon if |M|^2 < (rho 96)^2 (the radius 18, 21, 24 or 27). Between
\ two tests a ship moves 5 of these units at most (40 a step, 32 steps), and
\ the moon's radius is 18 or more. It reads game state only (and MN_E: no zero
\ page): with no moon it returns at once, so the game is as before in every
\ system without one. C set: we have crashed, and MA22 jumps to MA28 (DEATH),
\ the planet's crash.
\
\ ******************************************************************************

{
.mh_x
 CLC                    \ (no crash)
 RTS
.*MOONHIT
 LDA QQ2+1              \ a moon in this system?
 EOR QQ2+3
 EOR QQ2+5
 STA mh_h
 AND #3
 CMP #1
 BNE mh_x
 LDA MCNT               \ the planet's altitude iteration
 AND #31
 CMP #10
 BNE mh_x
 LDA FRIN               \ the planet in slot 0
 BPL mh_x
 JSR MN_TURN            \ the moon's place, this iteration's
 BIT MN_OK
 BPL mh_x
 LDA mh_h               \ the radius by h bits 5-6
 LSR A
 LSR A
 LSR A
 LSR A
 LSR A
 AND #3
 TAY
 LDA mh_rd,Y
 STA mh_r
 STZ mh_s               \ the sum of the squares
 STZ mh_s+1
 LDX #4                 \ each axis: X = 4, 2, 0 (z, y, x)
.mh1
 TXA                    \ Y = 3i = 3X / 2 (C clear)
 STA mh_g
 LSR A
 ADC mh_g
 TAY
 LDA MN_E+1,Y           \ e = MN_E >> 8
 STA mh_v
 LDA MN_E+2,Y
 STA mh_v+1
 TXA                    \ M = P + e: P's high and sign bytes, K% + 3i + 1
 STA mh_g               \ and + 2, 3i = 3X / 2
 LSR A
 ADC mh_g
 TAY
 INY
 JSR mh_tc
 LDA mh_w
 CLC
 ADC mh_v
 STA mh_w
 LDA mh_w+1
 ADC mh_v+1
 STA mh_w+1
 BPL mh6                \ |M|
 JSR mh_neg
.mh6
 BNE mh_n               \ (|M| >= 256: too far)
 LDA mh_w
 CMP mh_r
 BCS mh_n               \ (|M| >= the radius on this axis: no)
 ASL A                  \ |M|^2 = QS(2 |M|), summed
 TAY
 LDA QSL,Y
 CLC
 ADC mh_s
 STA mh_s
 LDA QSH,Y
 ADC mh_s+1
 STA mh_s+1
 DEX
 DEX
 BMI P%+5
 JMP mh1
 LDA mh_r               \ C set if the sum < the radius squared, QS(2 r)
 ASL A
 TAY
 LDA mh_s
 CMP QSL,Y
 LDA mh_s+1
 SBC QSH,Y              \ (C clear: the sum is less, a crash)
 BCC mh_y
.mh_n
 CLC
 RTS
.mh_y
 SEC
 RTS

\ mh_tc: the sign-magnitude word at K% + Y (low, high) in two's complement,
\ mh_w (A its high byte; keeps X)
.mh_tc
 LDA K%,Y
 STA mh_w
 LDA K%+1,Y
 STA mh_w+1
 BPL mt9
 AND #&7F
 STA mh_w+1

\ mh_neg: mh_w = - mh_w (A its high byte; keeps X)
.mh_neg
 SEC
 LDA #0
 SBC mh_w
 STA mh_w
 LDA #0
 SBC mh_w+1
 STA mh_w+1
.mt9
 RTS

.mh_rd  EQUB 18, 21, 24, 27     \ the radius: rho 96 / 256
.mh_h   SKIP 1
.mh_r   SKIP 1
.mh_g   SKIP 2
.mh_w   SKIP 2
.mh_v   SKIP 2
.mh_s   SKIP 2
}
