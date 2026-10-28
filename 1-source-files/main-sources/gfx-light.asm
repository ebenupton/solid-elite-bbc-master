\ ******************************************************************************
\
\ gfx-light.asm - flat-shaded lighting of the ships: the game-context half
\
\ From the Demonstration Disc port's shade7.asm (branch lighting). The model
\ is lightramps.py (docs/renderer.md): a face's light is I = 0.5 + 0.5 max(0, n.L)
\ for its unit normal n and L the unit vector towards the light, entry
\ round(31 max(0, n.L)) of its hue's 32-entry ramp of 4x4 dithers (one pool
\ of nine hue ramps shared by every ship, each from 50% to 100% of the hue's
\ own full brightness: gfx-light6.asm).
\
\ Master port: in bank 6, with the frame layer, which calls it (F_FRAME, F_SHIP)
\ in game context only (never with ACCCON X set, which would hide the
\ quarter squares QSL/QSH, main RAM at &7000, that it multiplies with).
\ Its reads of QSL/QSH are marked "bankcheck: ok": the frame layer reads main
\ RAM above &3000 nowhere else, as it may run with X set, but these run before
\ F_FRAME sets X (L_SUN) or from F_SHIP, in game context (L_REC).
\ The frame layer's f_col (gfx-frame.asm) turns a level into the four row
\ bytes at drawing time.
\
\ L_SUN (F_FRAME, once per main-loop iteration in a space view) keeps LV,
\ the unit vector towards the sun in view space (x right, y up, z in; 16-bit
\ signed, 1 = &4000), and LLT = LV * 41.3 (signed bytes) for the next
\ iteration's ships:
\   * slot 1 (FRIN+1) is the sun (type 129): LV = the sun's position,
\     normalised, when it has just appeared and every 32nd iteration; on the
\     others LV is rotated by our roll and pitch as MV40 rotates the planet
\     and sun (the sun is so far away that our own movement does not turn it);
\   * slot 1 is the space station (the safe zone: the station has replaced
\     the sun): LV keeps being rotated, so the light stays continuous, and is
\     re-seeded from the sun when it is back;
\   * slot 1 is empty (the title screen, no local universe): the fixed light
\     (1, 1, -1) / sqrt 3, from the top right into the screen.
\
\ L_REC (F_SHIP, once the ship's face visibility XX2 is copied into its
\ record): the light in the ship's own coordinates, Ls[a] = (a . LLT + 16)
\ >> 5 for the orientation vectors a = sidev, roofv, nosev (their high bytes
\ halved: 48 = 1), |Ls| <= 64, 62 for a unit vector; then for each visible
\ face, d = (n . Ls + 16) >> 5 for its unit normal n in blueprint coordinates
\ (magnitude 61, from the face list FC_FACETAB) is about 118 (n . L), and
\ its level is min(31, (d + d / 16 + 2) / 4), or 0 if n . Ls < 0 (a ship
\ vertex v is v_x sidev + v_y roofv + v_z nosev in view space, and so is a
\ normal, whether the orientation is a rotation or, as the station's until
\ its first TIDY, a reflection). The level replaces the face's byte in the
\ record's XX2 copy:
\   0                    hidden (as before)
\   &80 + level          visible
\   &C0 + level          visible, XX2 was 255 (Elite skipped the normal
\                        test: the frame layer culls it by its winding),
\                        plus &20 if the ship is mirrored from the face
\                        lists' handedness (GHAND: TIDY's, not ZINF's)
\ so the frame layer reads a face's level from the copy, and a hidden face's
\ level is 0 (ambient), which the fins standing on it take.
\
\ Products are exact: a * b = QS(|a + b|) - QS(|a - b|) for the quarter
\ squares QS(n) = n^2 / 4 (QSL/QSH, rounded down: the roundings cancel, as
\ a + b and a - b have the same parity), summed in 16 bits and rounded once.
\
\ Only the lighting's own variables (below) and the ship record are written:
\ none of it is game state.
\
\ ******************************************************************************


{
\ ------------------------------------------------------------------------------
\ L_SUN
\ ------------------------------------------------------------------------------

.^L_SUN
 LDA FRIN+1
 BEQ ls_fix             \ no slot 1 (title screen): the fixed light
 CMP #129
 BNE ls_rot             \ the station: keep rotating LV
 BIT lv_ok              \ the sun: seed LV from it when it has just appeared
 BVC ls_seed            \ (bit 6 clear) and every 32nd iteration
 INC lv_cnt
 LDA lv_cnt
 AND #31
 BEQ ls_seed
.ls_rot
 BIT lv_ok
 BMI ls_r1
 LDX #2                 \ LV not set up yet (the safe zone from the start):
.ls_r0                  \ start from the fixed light, (1, 1, -1) / sqrt 3
 LDA lv_defl,X
 STA LVL,X
 LDA lv_defh,X
 STA LVH,X
 DEX
 BPL ls_r0
 LDA #&80
 STA lv_ok
.ls_r1
 JSR lv_rot
 JMP lv_ll
.ls_fix
 STZ lv_ok
 LDA #24
 STA LLT
 STA LLT+1
 LDA #&E8               \ -24
 STA LLT+2
 RTS

.lv_defl EQUB LO(&24F3), LO(&24F3), LO(-&24F3)    \ &4000 / sqrt 3
.lv_defh EQUB HI(&24F3), HI(&24F3), HI(-&24F3)

.ls_seed                \ LV = the sun's position (K% + NI%), normalised
 STZ lv_cnt
 LDX #8                 \ |x|, |y|, |z| as 24-bit (lo, hi, top) in lv_w,
.lse1                   \ their signs in lv_sg
 LDA K%+NI%,X
 STA lv_w,X
 DEX
 BPL lse1
 LDX #2
 LDY #8
.lsa
 LDA lv_w,Y
 STA lv_sg,X
 AND #&7F
 STA lv_w,Y
 DEY
 DEY
 DEY
 DEX
 BPL lsa
 LDA #0                 \ all zero (the sun here)? keep LV
 LDX #8
.lsz
 ORA lv_w,X
 DEX
 BPL lsz
 TAX
 BEQ ls_rot
.lse2
 LDA lv_w+2             \ shift all three left until one has bit 22 set
 ORA lv_w+5
 ORA lv_w+8
 AND #&40
 BNE lse3
 LDX #6
.lse4
 ASL lv_w,X
 ROL lv_w+1,X
 ROL lv_w+2,X
 DEX
 DEX
 DEX
 BPL lse4
 BRA lse2
.lse3
 STZ l7_s               \ S = QS(x) + QS(y) + QS(z) for the top bytes t
 STZ l7_t               \ (0..127; one of them 64 or more)
 LDX #6
.lsq
 LDY lv_w+2,X
 LDA QSL,Y              \ bankcheck: ok
 CLC
 ADC l7_t
 STA l7_t
 LDA QSH,Y              \ bankcheck: ok
 ADC l7_s
 STA l7_s
 DEX
 DEX
 DEX
 BPL lsq
 STZ lv_l               \ the length, sqrt(x^2 + y^2 + z^2) in units of t
 LDA #&80               \ (64..220): the smallest n with QS(n) >= S, by a
 STA lv_m               \ binary search for the largest with QS(n) < S
.lsb
 LDA lv_l
 ORA lv_m
 TAX
 LDA QSL,X              \ QS(n) - S (bankcheck: ok)
 CMP l7_t
 LDA QSH,X              \ bankcheck: ok
 SBC l7_s
 BCS P%+5
 STX lv_l
 LSR lv_m
 BNE lsb
 INC lv_l               \ (>= the largest t, so 128 t / length <= 128)
 LDX #2                 \ LV = +/- (128 t / length) * 128
.lse9
 TXA
 STA l7_t
 ASL A
 ADC l7_t
 TAY
 LDA lv_w+2,Y           \ t: the dividend 128 t is (t >> 1, (t AND 1) << 7)
 LSR A
 STZ lv_a
 ROR lv_a
 LDY #8
.lsd
 ASL lv_a
 ROL A
 BCS lsd1
 CMP lv_l
 BCC lsd2
.lsd1
 SBC lv_l
 INC lv_a
.lsd2
 DEY
 BNE lsd
 LDA #0                 \ (lv_a+1 A) = quotient * 128
 LSR lv_a
 ROR A
 STA lv_a+1
 LDY lv_a
 LDA lv_sg,X            \ the sign
 BPL lse10
 SEC
 LDA #0
 SBC lv_a+1
 STA lv_a+1
 LDA #0
 SBC lv_a
 TAY
.lse10
 LDA lv_a+1
 STA LVL,X
 TYA
 STA LVH,X
 DEX
 BPL lse9
 LDA #&C0
 STA lv_ok

.lv_ll                  \ LLT = LV * 41 / &4000 = (h >> 1) + (h >> 3) + (h >> 6)
 LDX #2                 \ for h = LV's high byte (arithmetic shifts)
.lvl1
 LDA LVH,X
 CMP #&80
 ROR A                  \ h >> 1
 STA l7_t
 CMP #&80
 ROR A
 CMP #&80
 ROR A                  \ h >> 3
 STA l7_s
 CMP #&80
 ROR A
 CMP #&80
 ROR A
 CMP #&80
 ROR A                  \ h >> 6
 CLC
 ADC l7_s
 CLC
 ADC l7_t
 STA LLT,X
 DEX
 BPL lvl1
 RTS

\ lv_rot: rotate LV by our roll and pitch, as MV40 rotates the planet:
\   K2 = y - alpha x / 256, z = z + beta K2 / 256,
\   y = K2 - beta z / 256, x = x + alpha y / 256

.lv_rot
 LDA ALPHA
 ORA BETA
 AND #&7F
 BEQ lvr9               \ no rotation
 LDX #0                 \ K2 = y + x * (-alpha) / 256
 LDA ALPHA
 EOR #&80
 JSR lv_mul
 CLC
 ADC LVL+1
 STA lv_k2
 TXA
 ADC LVH+1
 STA lv_k2+1
 LDX #&FF               \ z = z + K2 * beta / 256  (X = &FF: v = K2)
 LDA BETA
 JSR lv_mul
 CLC
 ADC LVL+2
 STA LVL+2
 TXA
 ADC LVH+2
 STA LVH+2
 LDX #2                 \ y = K2 + z * (-beta) / 256
 LDA BETA
 EOR #&80
 JSR lv_mul
 CLC
 ADC lv_k2
 STA LVL+1
 TXA
 ADC lv_k2+1
 STA LVH+1
 LDX #1                 \ x = x + y * alpha / 256
 LDA ALPHA
 JSR lv_mul
 CLC
 ADC LVL
 STA LVL
 TXA
 ADC LVH
 STA LVH
.lvr9
 RTS

\ lv_mul: (X A) = v * a / 256 (16-bit signed; v = LV component X, or K2 if
\ X = &FF; A = a, sign-magnitude), truncated towards zero

.lv_mul
 STA l7_s               \ sign of the product in bit 7, then of v
 AND #&7F
 STA lv_m
 CPX #&FF
 BNE lvm1
 LDA lv_k2
 LDY lv_k2+1
 BRA lvm2
.lvm1
 LDA LVL,X
 LDY LVH,X
.lvm2
 STA lv_u
 STY lv_u+1
 STZ lv_u+2
 TYA
 EOR l7_s
 STA l7_s
 TYA
 BPL lvm3
 SEC                    \ |v|
 LDA #0
 SBC lv_u
 STA lv_u
 LDA #0
 SBC lv_u+1
 STA lv_u+1
.lvm3
 STZ lv_a
 STZ lv_a+1
 STZ lv_a+2
.lvm4
 LSR lv_m
 BCC lvm5
 CLC
 LDA lv_a
 ADC lv_u
 STA lv_a
 LDA lv_a+1
 ADC lv_u+1
 STA lv_a+1
 LDA lv_a+2
 ADC lv_u+2
 STA lv_a+2
.lvm5
 LDA lv_m
 BEQ lvm6
 ASL lv_u
 ROL lv_u+1
 ROL lv_u+2
 BRA lvm4
.lvm6
 LDA lv_a+1             \ (X A) = acc / 256, signed
 LDX lv_a+2
 BIT l7_s
 BPL lvm7
 EOR #&FF
 CLC
 ADC #1
 PHA
 TXA
 EOR #&FF
 ADC #0
 TAX
 PLA
.lvm7
 RTS


\ ------------------------------------------------------------------------------
\ L_REC (F_SHIP, with ship record F_NSHIP's XX2 copy written; Y is kept)
\ ------------------------------------------------------------------------------

.l7_off EQUB 22, 16, 10 \ INWK offset of the x high byte: sidev, roofv, nosev

.^L_REC
 LDA GNF
 BNE P%+3
 RTS
 STY lr_y
 LDX #2                 \ lr_b = LLT
.lr0
 LDA LLT,X
 STA lr_b,X
 DEX
 BPL lr0
 LDY #2                 \ axis: 2 nosev, 1 roofv, 0 sidev
.lr1
 STY l7_s
 LDX l7_off,Y
 LDY #0
.lr2
 LDA INWK,X             \ high byte (sign-magnitude, 96 = 1) / 2, signed
 PHP
 AND #&7F
 LSR A
 PLP
 BPL P%+5
 EOR #&FF
 INC A
 STA lr_a,Y
 INX
 INX
 INY
 CPY #3
 BCC lr2
 JSR l_dot              \ Ls = (h . LLT + 16) >> 5
 JSR l_r32
 LDY l7_s
 STA lr_c,Y
 DEY
 BPL lr1
 LDX #2                 \ lr_b = Ls
.lr3
 LDA lr_c,X
 STA lr_b,X
 DEX
 BPL lr3

 LDX F_NSHIP            \ the record's XX2 copy (bankcheck: ok: L_REC runs
 LDA F_SPL,X            \ from F_SHIP, with bank 6 paged; bankcheck: ok)
 STA lrv+1
 STA lrw+1
 LDA F_SPH,X            \ (bankcheck: ok)
 STA lrv+2
 STA lrw+2
 LDA GTYPE              \ the face list (in bank 6)
 ASL A
 TAX
 LDA FC_FACETAB,X       \ (bankcheck: ok)
 STA lrn+1
 STA lrf+1
 LDA FC_FACETAB+1,X     \ (bankcheck: ok)
 STA lrn+2
 STA lrf+2
 LDX #0
.lf1
 STX lr_f
.lrv
 LDA &FFFF,X            \ (patched) XX2: 0 hidden
 BEQ lf9
 STA lr_r
 LDY #3                 \ the face's unit normal (bytes 1..3 of its entry)
.lf2
.lrf
 LDA &FFFF,Y            \ (patched)
 STA lr_a-1,Y
 DEY
 BNE lf2
 JSR l_dot
 LDA #0
 BIT lr_sh
 BMI lf4                \ n . Ls < 0: level 0
 JSR l_r32              \ d
 STA lr_c
 LSR A                  \ d + d / 16 + 2 (<= 136)
 LSR A
 LSR A
 LSR A
 SEC
 ADC lr_c
 INC A
 LSR A
 LSR A
 CMP #32
 BCC lf4
 LDA #31
.lf4
 ORA #&80               \ visible
 LDY lr_r
 INY
 BNE P%+5
 ORA GHAND              \ XX2 = 255: cull by winding (bit 6), and bit 5 if
                        \ the ship is mirrored (GHAND, set by S_SHIP)
 LDX lr_f
.lrw
 STA &FFFF,X            \ (patched)
.lf9
.lrn
 LDA &FFFF              \ (patched) the next face entry: n + 4 bytes on
 AND #15
 SEC
 ADC #3
 CLC
 ADC lrn+1
 STA lrn+1
 STA lrf+1
 BCC P%+8
 INC lrn+2
 INC lrf+2
 LDX lr_f
 INX
 CPX GNF
 BCC lf1
 LDY lr_y
 RTS

\ l_dot: (lr_sh lr_sl) = lr_a . lr_b (signed bytes, |a +/- b| < 128)

.l_dot
 STZ lr_sl
 STZ lr_sh
 LDX #2
.ld1
 LDA lr_a,X
 CLC
 ADC lr_b,X
 BPL P%+5
 EOR #&FF
 INC A
 TAY
 LDA lr_sl
 CLC
 ADC QSL,Y              \ bankcheck: ok
 STA lr_sl
 LDA lr_sh
 ADC QSH,Y              \ bankcheck: ok
 STA lr_sh
 LDA lr_a,X
 SEC
 SBC lr_b,X
 BPL P%+5
 EOR #&FF
 INC A
 TAY
 LDA lr_sl
 SEC
 SBC QSL,Y              \ bankcheck: ok
 STA lr_sl
 LDA lr_sh
 SBC QSH,Y              \ bankcheck: ok
 STA lr_sh
 DEX
 BPL ld1
 RTS

\ l_r32: A = (lr_sh lr_sl + 16) >> 5 (the low byte of it; it fits a signed byte)

.l_r32
 LDA lr_sl
 CLC
 ADC #16
 STA lr_sl
 LDA lr_sh
 ADC #0
 ASL lr_sl
 ROL A
 ASL lr_sl
 ROL A
 ASL lr_sl
 ROL A
 RTS


\ ------------------------------------------------------------------------------
\ Variables (renderer state, not game state)
\ ------------------------------------------------------------------------------

.^LLT      EQUB 24, 24, &E8 \ the light towards the sun, x, y, z (* 41.3; L_SUN):
                        \ the fixed light until L_SUN first runs
.LVL     SKIP 3         \ LV: the unit vector towards the sun (16-bit, 1 = &4000)
.LVH     SKIP 3
.lv_ok   EQUB 0         \ bit 7: LV is set up; bit 6: from the sun
.lv_cnt  SKIP 1         \ iterations since LV was last seeded from the sun
.l7_t    SKIP 1
.l7_s    SKIP 1
.lv_w    SKIP 9         \ L_SUN: the sun's |x|, |y|, |z| (24-bit each)
.lv_sg   SKIP 3         \ and their signs (bit 7)
.lv_l    SKIP 1         \ the length, in units of the top byte
.lv_m    SKIP 1         \ lv_mul: multiplier magnitude (and the search's bit)
.lv_u    SKIP 3         \ lv_mul: |v|, shifted
.lv_a    SKIP 3         \ lv_mul: accumulator
.lv_k2   SKIP 2         \ MV40's K2
.lr_a    SKIP 3         \ l_dot's operands
.lr_b    SKIP 3
.lr_c    SKIP 3         \ L_REC: Ls, then d
.lr_sl   SKIP 1         \ l_dot's result
.lr_sh   SKIP 1
.lr_f    SKIP 1         \ L_REC: the face
.lr_r    SKIP 1         \ L_REC: its XX2
.lr_y    SKIP 1
}
