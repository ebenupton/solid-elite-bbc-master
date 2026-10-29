\ ******************************************************************************
\
\ gfx-ssun.asm - the sun near the planet, drawn as scenery: at bank 4's end
\ (Elite's home bank, after the hot pass and the hot data: elite-layout.asm),
\ one of the renderer's routines that run in game context, with bank 4 paged;
\ S_SUN from G_FRAME (the glue area), from hframe after each main-loop
\ iteration
\
\ Elite has one slot for the sun and the space station (FRIN+1). When we
\ come near the planet, part 15 of the main flight loop removes the sun (WPLS)
\ and puts the station in its slot (NWSPS); once the station is out of
\ range, KS4 puts a new sun back in the slot, overhead (y_sign 6). The game
\ is left exactly so. Meanwhile this draws the sun where it would have been,
\ for the frame only:
\
\   * slot 1 the sun, with the planet within one sign unit on every axis
\     (part 15 spawns the station when they are all zero, in an iteration
\     with MCNT AND 31 = 0): D = sun - planet, 24-bit two's complement, in
\     the frames before such an iteration; further away, D is forgotten
\   * slot 1 the station: D turned by our roll and pitch by MV40 itself
\     (ss_turn; our own movement moves the planet and the sun alike, so D only
\     turns); then, in record mode, the sun is recorded at planet + D as
\     PLANET would draw it: the view's axes as PLUT, then PLANET's tests
\     (0 < z_sign < 48, z_sign or z_hi non-zero), PROJ (x / z and y / z,
\     under 1024), the radius 24576 / z (248 if 256 or more) and CHKON
\   * slot 1 the station and D unknown (we launched: this system's sun was
\     never in the slot): D from the system's seeds, by SOLAR's own code
\     placing the planet and the sun as on arrival (ss_seed: its second
\     emission, with FIST's bit 0 taken as clear)
\   * docked (G_DIRECT with QQ12 non-zero), witchspace, no planet: none
\
\ The sun and the planet are the same size (PLANET's 24576 / z for both),
\ so the frame layer puts the bigger disc in front (f_discs, f_disc2).
\
\ Only its own variables (bank 4, here, and the shared workspace's) and the
\ frame's (F_SUX, F_SUY, SS_OK in the shared workspace, GSUNR, GSUNON in the
\ glue area) are written: the zero page and the game's variables that MV40
\ and SOLAR use are kept and put back, so the game sees nothing of it.
\
\ ******************************************************************************

.S_SUN
 IF _PLANET_MOON        \ (the moon: make moon=on)
 JSR MN_TURN            \ the moon's place, turned (once an iteration)
 ENDIF
 LDA MJ                 \ witchspace: no planet, no sun
 BNE ss_off
 LDA FRIN               \ slot 0 the planet (128 or 130)
 BPL ss_off
 LDA FRIN+1
 CMP #129
 BEQ ss_near
 CMP #SST
 BNE ss_ret
 BIT SS_OK              \ the station: turn D (or derive it), then draw
 BMI ss_rot
 JSR ss_seed
 BRA ss_drw
.ss_rot
 JSR ss_turn
.ss_drw
 LDA QQ11
 ORA GFORCE
 BNE ss_ret
 JMP ss_draw

.ss_near                \ the sun: keep D while the station may appear
 LDA K%+2
 ORA K%+5
 ORA K%+8
 AND #%01111110         \ every |sign| <= 1
 BNE ss_off
 LDA MCNT               \ part 15 may put the station in the slot only
 AND #%00011110         \ when MCNT AND 31 = 0, and TT100 decrements MCNT
 BEQ ss_cap             \ after this: D is needed only from the frames with
 RTS                    \ MCNT AND 31 = 1 (and 0)
.ss_off
 STZ SS_OK
.ss_ret
 RTS

.ss_cap                 \ D = sun - planet, from the slots
 LDX #8
.ssc0
 LDA K%,X
 STA ss_pl,X
 LDA K%+NI%,X
 STA ss_su,X
 DEX
 BPL ssc0

\ ss_dif: D = ss_su - ss_pl (sign-magnitude, as INWK has them), and SS_OK set

.ss_dif
 LDX #0
.ssc1
 LDA ss_su,X
 STA ss_w
 LDA ss_su+1,X
 STA ss_w+1
 LDA ss_su+2,X
 JSR ss_tc
 LDA ss_w
 STA ss_d,X
 LDA ss_w+1
 STA ss_d+1,X
 LDA ss_w+2
 STA ss_d+2,X
 LDA ss_pl,X
 STA ss_w
 LDA ss_pl+1,X
 STA ss_w+1
 LDA ss_pl+2,X
 JSR ss_tc
 SEC
 LDA ss_d,X
 SBC ss_w
 STA ss_d,X
 LDA ss_d+1,X
 SBC ss_w+1
 STA ss_d+1,X
 LDA ss_d+2,X
 SBC ss_w+2
 STA ss_d+2,X
 INX
 INX
 INX
 CPX #9
 BNE ssc1
 LDA #&FF
 STA SS_OK
 RTS

\ ss_tc: (A ss_w+1 ss_w) sign-magnitude -> ss_w(2 1 0) two's complement (X kept)

.ss_tc
 STA ss_w+2
 ASL A
 BCC sst9
 LSR A
 STA ss_w+2
.ss_neg                 \ ss_w(2 1 0) = -ss_w(2 1 0)
 SEC
 LDA #0
 SBC ss_w
 STA ss_w
 LDA #0
 SBC ss_w+1
 STA ss_w+1
 LDA #0
 SBC ss_w+2
 STA ss_w+2
.sst9
 RTS

\ ss_seed: D from the seeds, by SOLAR's own code: its second copy (the
\ SOLAR block's ", again": streams.py's 3-assembled-output/elite-source-again.asm, its
\ labels and calls named A_<name>), entered at nobirths (past the
\ Trumbles, which the Master never has), calling ZINF itself and, for SOS1
\ and NWSHP, stand-ins that note INWK's coordinates (ss_pl, the planet;
\ ss_su, the sun) instead of making ships. SOLAR halves FIST, its bit 0
\ going into the planet's z_sign, and ZINF zeroes INWK: both are put back.
\ FIST's bit 0 is taken as clear (what it was on the arrival is not known).

.ss_seed
 LDX #NI%-1             \ keep INWK and FIST
.sss1
 LDA INWK,X
 STA ss_zs,X
 DEX
 BPL sss1
 LDA FIST
 PHA
 AND #%11111110
 STA FIST
 JSR A_nobirths         \ SOLAR: the planet (SOS1), then the sun (NWSHP)
 PLA
 STA FIST
 LDX #NI%-1
.sss2
 LDA ss_zs,X
 STA INWK,X
 DEX
 BPL sss2
 JMP ss_dif             \ D = the sun - the planet

 INCLUDE "3-assembled-output/elite-source-again.asm"
 RTS                    \ (SOLAR falls through into NWSTARS: here, back)

A_ZINF = ZINF
A_DORND = DORND         \ (the Trumbles' part, not run)

.A_SOS1                 \ SOLAR's planet: noted
 LDX #8
.sss3
 LDA INWK,X
 STA ss_pl,X
 DEX
 BPL sss3
 RTS

.A_NWSHP                \ SOLAR's sun: noted
 LDX #8
.sss4
 LDA INWK,X
 STA ss_su,X
 DEX
 BPL sss4
 RTS

\ ss_turn: D turned by our roll (ALPHA) and pitch (BETA) by MV40 itself, as
\ it turns the planet and the sun (ss_turnx: the vector at ss_d + X, X = 0
\ D, 9 the moon's MN_E with moon=on):
\   1. K2 = y - alpha * x / 256    2. z = z + beta * K2 / 256
\   3. y = K2 - beta * z / 256     4. x = x + alpha * y / 256
\ The vector goes into INWK's coordinates, sign-magnitude, and MV40 runs
\ with TYPE the sun's (129) and DELTA 0, so that MV45, which it jumps to,
\ moves z by nothing and returns; K2's low byte, which MV40 reads without
\ setting (step 3's carry), is 0. The zero page it uses (ss_zpa: INWK's
\ coordinates, P, Q, R, S, T, K, K2, TYPE and DELTA) is kept and put back,
\ so the game sees none of it.

.ss_turn
 LDX #0
.ss_turnx
 LDA ALPHA
 ORA BETA
 AND #%01111111
 BNE sst0
 RTS                    \ neither: nothing turns
.sst0
 STX ss_o
 LDY #SS_NZP-1          \ keep the zero page MV40 uses
.sst1
 LDX ss_zpa,Y
 LDA 0,X
 STA ss_zs,Y
 DEY
 BPL sst1
 LDX ss_o               \ INWK's coordinates = the vector, sign-magnitude
 LDY #0
.sst2
 LDA ss_d,X
 STA ss_w
 LDA ss_d+1,X
 STA ss_w+1
 LDA ss_d+2,X
 STA ss_w+2
 BPL sst3
 JSR ss_neg
 LDA ss_w+2
 ORA #%10000000
 STA ss_w+2
.sst3
 LDA ss_w
 STA INWK,Y
 LDA ss_w+1
 STA INWK+1,Y
 LDA ss_w+2
 STA INWK+2,Y
 INX
 INX
 INX
 INY
 INY
 INY
 CPY #9
 BNE sst2
 LDA #129               \ the sun (MV45 returns), not moved (DELTA 0)
 STA TYPE
 STZ DELTA
 STZ K2
 JSR MV40
 LDX ss_o               \ the vector = INWK's coordinates, two's complement
 LDY #0
.sst4
 LDA INWK,Y
 STA ss_w
 LDA INWK+1,Y
 STA ss_w+1
 LDA INWK+2,Y
 JSR ss_tc               \ (X and Y kept)
 LDA ss_w
 STA ss_d,X
 LDA ss_w+1
 STA ss_d+1,X
 LDA ss_w+2
 STA ss_d+2,X
 INX
 INX
 INX
 INY
 INY
 INY
 CPY #9
 BNE sst4
 LDY #SS_NZP-1          \ the zero page back
.sst5
 LDX ss_zpa,Y
 LDA ss_zs,Y
 STA 0,X
 DEY
 BPL sst5
 RTS

.ss_zpa                 \ the zero page MV40 (with MULT3, MVT3, MV45 and MVT1)
 EQUB INWK, INWK+1, INWK+2, INWK+3, INWK+4, INWK+5, INWK+6, INWK+7, INWK+8
 EQUB P, P+1, P+2, Q, R, S, T, K, K+1, K+2, K+3, K2, K2+1, K2+2, K2+3
 EQUB TYPE, DELTA
SS_NZP = P% - ss_zpa

\ ss_draw: record the sun at planet + D, as PLANET would draw it

.ssd0
 RTS
.ss_draw
 STZ GSUNON             \ (what SUN drew this iteration, before the station
 LDX #0                 \ took the slot, is this same sun)
.ssd1
 LDA K%,X               \ S = the planet + D
 STA ss_w
 LDA K%+1,X
 STA ss_w+1
 LDA K%+2,X
 JSR ss_tc
 CLC
 LDA ss_w
 ADC ss_d,X
 STA ss_s,X
 LDA ss_w+1
 ADC ss_d+1,X
 STA ss_s+1,X
 LDA ss_w+2
 ADC ss_d+2,X
 STA ss_s+2,X
 INX
 INX
 INX
 CPX #9
 BNE ssd1

 LDA VIEW               \ the view's axes, as PLUT: rear (x, z) = (-x, -z),
 BEQ ssv9               \ left (z, -x), right (-z, x)
 CMP #2
 BCS ssv2
 LDX #0
 JSR ss_negs
 BRA ssv8
.ssv2
 LDX #2
.ssv3
 LDA ss_s,X
 LDY ss_s+6,X
 STA ss_s+6,X
 TYA
 STA ss_s,X
 DEX
 BPL ssv3
 LDX #0
 LDA VIEW
 CMP #3
 BEQ ssv7
.ssv8
 LDX #6
.ssv7
 JSR ss_negs
.ssv9

 LDA ss_s+8             \ PLANET: z_sign >= 48 (or negative): too far, or
 CMP #48                \ behind; z_sign = z_hi = 0: too close
 BCS ssd0
 ORA ss_s+7
 BEQ ssd0
 LDX #0                 \ |x| and |y| in place, their signs in ss_sx, ss_sy
 JSR ss_absn
 STA ss_sx
 LDX #3
 JSR ss_absn
 STA ss_sy
 LDY #0                 \ z, |x| and |y| shifted right together until z
 LDA ss_s+8             \ fits 16 bits (ss_sh shifts)
 BEQ ssn9
.ssn1
 LSR ss_s+8
 ROR ss_s+7
 ROR ss_s+6
 LSR ss_s+2
 ROR ss_s+1
 ROR ss_s
 LSR ss_s+5
 ROR ss_s+4
 ROR ss_s+3
 INY
 LDA ss_s+8
 BNE ssn1
.ssn9
 STY ss_sh

 LDX #0                 \ PROJ: K3 = 128 + x / z * 256
 JSR ss_div
 BCS ssd8
 LDA ss_sx
 STA ss_sg
 LDA #X
 JSR ss_cen
 STA F_SUX
 STX F_SUX+1
 LDX #3                 \ K4 = 96 - y / z * 256
 JSR ss_div
 BCS ssd8
 LDA ss_sy
 EOR #%10000000
 STA ss_sg
 LDA #Y
 JSR ss_cen
 STA F_SUY
 STX F_SUY+1
 JMP ss_rad
.ssd8
 RTS

.ss_rad
 LDA #&60               \ the radius: 24576 / z * 256, from &6000 >> ss_sh
 STA ss_s+1
 LDA #0
 STA ss_s
 STA ss_s+2
 LDY ss_sh
 BEQ ssr2
.ssr1
 LSR ss_s+1
 ROR ss_s
 DEY
 BNE ssr1
.ssr2
 LDX #0
 JSR ss_div
 LDA ss_q
 BCS ssr3
 LDY ss_q+1
 BEQ ssr4
.ssr3
 LDA #248
.ssr4
 STA GSUNR

 \ CHKON: the circle's box must meet the screen (x 0..255, y 0..Yx2M1-1)
 CLC                    \ right edge K3 + K >= 0
 ADC F_SUX
 LDA F_SUX+1
 ADC #0
 BMI ssd9
 LDA F_SUX              \ left edge K3 - K <= 255
 SEC
 SBC GSUNR
 LDA F_SUX+1
 SBC #0
 BMI ssk1
 BNE ssd9
.ssk1
 LDA F_SUY              \ bottom edge K4 + K >= 0
 CLC
 ADC GSUNR
 LDA F_SUY+1
 ADC #0
 BMI ssd9
 LDA F_SUY              \ top edge K4 - K < Yx2M1
 SEC
 SBC GSUNR
 TAX
 LDA F_SUY+1
 SBC #0
 BMI ssk2
 BNE ssd9
 CPX Yx2M1
 BCS ssd9
.ssk2
 LDA #&FF
 STA GSUNON
.ssd9
 RTS

\ ss_cen: (X A) = A + ss_q, or A - ss_q if ss_sg bit 7 is set (a screen
\ coordinate from the centre A and the projection ss_q)

.ss_cen
 BIT ss_sg
 BMI ssc5
 CLC
 ADC ss_q
 PHA
 LDA #0
 ADC ss_q+1
 TAX
 PLA
 RTS
.ssc5
 SEC
 SBC ss_q
 PHA
 LDA #0
 SBC ss_q+1
 TAX
 PLA
 RTS

\ ss_negs: ss_s(X+2 X+1 X) negated

.ss_negs
 SEC
 LDA #0
 SBC ss_s,X
 STA ss_s,X
 LDA #0
 SBC ss_s+1,X
 STA ss_s+1,X
 LDA #0
 SBC ss_s+2,X
 STA ss_s+2,X
 RTS

\ ss_absn: A = the sign of ss_s(X+2 X+1 X) (bit 7), which is made positive

.ss_absn
 LDA ss_s+2,X
 AND #%10000000
 BEQ ssa9
 PHA
 JSR ss_negs
 PLA
.ssa9
 RTS

\ ss_div: ss_q = n * 256 / z for n = ss_s(X+2 X+1 X) and z = ss_s(7 6),
\ C set (and ss_q undefined) if it is 1024 or more: n / 4 is below z, then
\ ten steps of shift and subtract

.ss_div
 LDA ss_s+2,X
 CMP #4
 BCS ssq9               \ n / 4 >= 65536 > z
 STA ss_r+2
 LDA ss_s+1,X
 STA ss_r+1
 LDA ss_s,X
 STA ss_r
 LDA #0
 STA ss_b
 LDY #2                 \ (ss_r+1 ss_r) = n / 4, its two low bits in ss_b's
.ssq1                   \ top two
 LSR ss_r+2
 ROR ss_r+1
 ROR ss_r
 ROR ss_b
 DEY
 BNE ssq1
 LDA ss_r               \ n / 4 >= z: 1024 or more
 CMP ss_s+6
 LDA ss_r+1
 SBC ss_s+7
 BCS ssq9
 STZ ss_q
 STZ ss_q+1
 LDY #10
.ssq2
 ASL ss_b
 ROL ss_r
 ROL ss_r+1
 BCS ssq3               \ (17 bits: above z)
 LDA ss_r
 CMP ss_s+6
 LDA ss_r+1
 SBC ss_s+7
 BCC ssq4
.ssq3
 LDA ss_r
 SBC ss_s+6             \ (C = 1)
 STA ss_r
 LDA ss_r+1
 SBC ss_s+7
 STA ss_r+1
 SEC
.ssq4
 ROL ss_q
 ROL ss_q+1
 DEY
 BNE ssq2
 CLC
.ssq9
 RTS

IF _PLANET_MOON         \ (the moon: make moon=on)

\ ******************************************************************************
\
\ MN_TURN: the moon's place, E = moon - planet (MN_E), kept as S_SUN keeps
\ D: a vector fixed in space, so turned by our roll and pitch as MV40 turns
\ the planet's position (our own movement moves the planet and the moon
\ alike), once an iteration (the first call with this MCNT: from G_PFHOOK
\ before the planet's detail, from MOONHIT, or from S_SUN after the
\ iteration). The planet's own orientation is not followed: Elite's TIDY
\ renormalises it with one-byte precision every 16 iterations, which turns
\ its spin axis (nosev - sidev) by up to 3 degrees at a time, so a moon 3
\ to 5.25 radii out on that axis would jump with it.
\
\ In a system with a moon (h = s0_hi EOR s1_hi EOR s2_hi, bits 0-1 = 1), E
\ is made in the first iteration after we arrive (SOLAR) or launch (SOS1),
\ which make the planet with ZINF's orientation: on its spin axis then, w =
\ (nosev - sidev) / sqrt(2) = (-1, 0, -1) / sqrt(2), on the side h bit 4
\ gives (set: -w), D = 3, 3.75, 4.5 or 5.25 radii out (h bits 2-3): E =
\ +/- (c, 0, c), c = D 24576 / sqrt(2) (the planet's radius is 24576 in the
\ coordinates, which E is in, as D); then turned by that iteration's roll
\ and pitch, as the planet's position was. It is forgotten (MN_OK clear) in
\ witchspace, with no planet, while we are docked (also F_DIRECT) and when
\ the system changes (QQ2). Only E, MN_OK and its own variables are
\ written (A, X, Y and the flags are not kept).
\
\ ******************************************************************************

.mt_off
 STZ MN_OK
.mnt9
 RTS
.MN_TURN
 LDA MCNT               \ once an iteration
 CMP mt_it
 BEQ mnt9
 STA mt_it
 LDA MJ                 \ witchspace, docked, or no planet: none
 ORA QQ12
 BNE mt_off
 LDA FRIN
 BPL mt_off
 LDX #5                 \ another system: forget it
.mnt1
 LDA QQ2,X
 CMP mt_sys,X
 BEQ mnt2
 STA mt_sys,X
 STZ MN_OK
.mnt2
 DEX
 BPL mnt1
 LDA QQ2+1              \ h: a moon?
 EOR QQ2+3
 EOR QQ2+5
 TAY
 AND #3
 CMP #1
 BNE mt_off
 BIT MN_OK
 BMI mnt4
 TYA                    \ made: E = +/- (c, 0, c)
 PHA
 LSR A
 LSR A
 AND #3
 TAY
 LDA mt_cl,Y
 STA ss_w
 LDA mt_cm,Y
 STA ss_w+1
 LDA mt_ch,Y
 STA ss_w+2
 PLA
 AND #16
 BNE P%+5
 JSR ss_neg             \ (h bit 4 clear: w, whose x and z are negative)
 LDX #2
.mnt3
 LDA ss_w,X
 STA MN_E,X
 STA MN_E+6,X
 STZ MN_E+3,X
 DEX
 BPL mnt3
 DEC MN_OK              \ (&FF)
.mnt4
 LDX #9                 \ turned
 JMP ss_turnx

.mt_cl  EQUB 166, 143, 120, 98
.mt_cm  EQUB 203, 254, 49, 100
.mt_ch  EQUB 0, 0, 1, 1

ENDIF                   \ (_PLANET_MOON)

\ Its variables (bank 4)

.ss_o   SKIP 1          \ ss_turnx's vector
IF _PLANET_MOON
.mt_it  SKIP 1          \ MN_TURN: the MCNT of E's last turn
.mt_sys SKIP 6          \ the system E is of (QQ2)
ENDIF
.ss_s   SKIP 9          \ the sun: planet + D, in the view's axes
ASSERT SS_NZP <= NI% AND NI% <= 37   \ (ss_zs, ss_pl and ss_su: the shared
                                     \ workspace, elite-gfx.asm)
.ss_w   SKIP 3
.ss_r   SKIP 3
.ss_q   SKIP 2
.ss_sg  SKIP 1
.ss_sx  SKIP 1
.ss_sy  SKIP 1
.ss_sh  SKIP 1
.ss_b   SKIP 1
