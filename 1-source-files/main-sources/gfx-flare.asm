\ ******************************************************************************
\
\ gfx-flare.asm - the lens flare (docs/renderer.md, "Lens flare"): the
\ part in shadow RAM, run with ACCCON X = 1
\
\ From the demo port's lens flare (src/flare*.asm and docs/FLARE.md there),
\ with the same recipe, arithmetic and pixels; its model is
\ 2-build-files/flare.py, which also generates the tables below.
\ When SUN has drawn the sun this frame, in the front view, with its centre on
\ the screen (x 1..255, y 0..191) and not inside the planet's disc, eight
\ ghosts go over the frame after the lasers and before the text, sights and
\ stars: at C + k D / 8 (C = (128, 96), D = sun - C), six dithered discs and
\ two dotted rings, each pixel of a disc's 4x4 Bayer mask (its density, rows
\ shifted by the ghost's number) ORed in its ink. OR only lifts MODE 1's
\ two-bit inks (K = 00 < C = 01, M = 10 < Y = 11): additive light in this
\ palette. Three levels by |dx| + |dy| step every density down the ladder 0,
\ 1, 2, 4, 6, 8 / 16.
\
\ Occlusion: before any ghost, R_FLARE probes the back buffer at nine
\ points of the sun's disc (its centre, and eight round it at about 0.62 R:
\ left, right, up, down and the diagonals), as drawn so far (the planet,
\ ships, dots and lasers are on it; the text, sights and stars come after
\ the flare). A probe outside the clip window (x 2..253, y 1..191) is out of
\ sight; one inside is in sight if its pixel is still the sun's colour for
\ its row (FC_SUNE on even rows, FC_SUNO on odd: the dithered rows compare
\ with their own pair). None in sight: no flare (and nothing marked dirty).
\ Otherwise every ghost's density steps down 0 (all 9), 1 (7 or 8), 2 (4 to
\ 6) or 3 (1 to 3) more rungs of the ladder (fl_vred), on top of the level.
\ About 1,250 cycles a flared frame.
\
\ Every span extends this buffer's dirty extent for its row, and the rows'
\ range goes to R_MARKDIRTY, so the next frame on this buffer repairs it as
\ after any shape (the disc rows repainted, the rest blacked, the text and
\ sights redrawn over it): the flare keeps no state on the screen.
\
\ Memory: this file is in bank 7, in the meridian window (ROMSEL MERIDBANK,
\ as T_FLARE pages it), with its half-width table fl_htab and its variables
\ (it was in bank 5, after the rasteriser, until R_DISC2 needed the room).
\ It writes only the screen, the dirty extents (main RAM) and its own
\ state; T_FLARE does the rest in bank 5 when R_FLARE returns with C set
\ (the sun in sight): k_clear in K mode, and the rows written (Y .. X, if
\ any) into the repair's row range through R_MARKDIRTY.
\ The frame layer's f_flt (gfx-flare6.asm, bank 6) makes the tests that need
\ bank 6's state (the view, the sun's centre on the screen, not behind the
\ planet: F_HW) and enters R_FLARE through T_FLARE. ACCCON X is as the frame
\ layer has it, mapping the back buffer at &4000-&7FFF, so fl_or writes
\ either buffer with no switching. Everything this code reads is in bank 7,
\ the zero page or main RAM below &3000. (It was in shadow RAM, run
\ with ACCCON X set, until it moved here.)
\
\ ******************************************************************************

\ Zero page: the rasteriser's scratch &10-&27, which F_FRAME saves and
\ restores, and R_COLE, R_COLO and R_DCE (&06, &07, &0E: saved too, and set
\ again before any use after the flare)

fl_lq   = &06           \ a span's first byte's mask (before the row's)
fl_rq   = &07           \ its last byte's
fl_t    = &0E
fl_dx   = &10           \ the sun's x - 128 (signed)
fl_dy   = &11           \ the sun's y - 96 (signed; fl_dx + 1)
fl_u    = &12           \ the ghost's ink
fl_i    = &13           \ the next ghost's number
fl_ymin = &14           \ the rows written
fl_ymax = &15
fl_gx   = &16           \ the ghost's centre (on the screen when the sun's
fl_gy   = &17           \ centre is, as |k| <= 8: all 8-bit)
fl_r    = &18           \ a disc's radius (a ring: the step, 2 or 4)
fl_hw   = &19           \ a disc's half-width table (a ring: dx, dy)
fl_pat  = &1B           \ the ghost's ink masks for rows y AND 3 = 0..3
fl_d    = &1F           \ a disc's row offset d (a ring: the point's offset)
fl_m    = &20           \ the row's mask (fl_or: the middle bytes')
fl_sp   = &21           \ screen pointer (fl_or)
fl_n    = &23           \ 8 * (bytes - 1) (fl_or)
fl_ch   = &24           \ &40 + (a span's first byte's column >= 32)
fl_cl   = &27           \ 8 x a span's first byte's column, low byte
fl_vo   = &12           \ the probes (before the ghosts): offsets 0, a, b,
                        \ -b, -a (&12-&16)
fl_vn   = &17           \ the probes in sight
fl_vx   = &18           \ a probe's x
fl_vy   = &19           \ (scratch)
fl_vh   = &1B           \ R / 2

FLNG = 8                \ ghosts
FLHMAX = 26             \ the ring round the sun only for a sun this small


\ R_FLARE: the flare over this frame (from f_flt, bank 6, through T_FLARE,
\ when the sun's centre is on the screen in the front view and not behind the
\ planet; fl_dx, fl_dy set), X: this buffer's R_DIRTYL page, Y: its R_DIRTYR
\ page.

.R_FLARE
 STX fl_dl1+2           \ this buffer's dirty extents
 STX fl_dl2+2
 STY fl_dr1+2
 STY fl_dr2+2
                        \ how much of the sun is in sight: nine probes of
                        \ the back buffer as drawn so far (the ships, the
                        \ planet, the dots and the lasers on it; not the
                        \ text, sights and stars, drawn after the flare),
                        \ the centre and eight round it at about 0.62 R (R
                        \ capped at 127): offsets 0, a, b, -b, -a with a =
                        \ R/2 + R/8, b = R/2 - R/16 (the diagonals' b, b
                        \ about a / sqrt 2)
 LDA GSUNR
 BPL P%+4
 LDA #127
 LSR A
 STA fl_vh              \ R/2
 LSR A
 LSR A
 STA fl_vx              \ R/8
 LSR A
 STA fl_vy              \ R/16
 LDA fl_vh
 CLC
 ADC fl_vx
 STA fl_vo+1            \ a
 EOR #&FF
 INC A
 STA fl_vo+4            \ -a
 LDA fl_vh
 SEC
 SBC fl_vy
 STA fl_vo+2            \ b
 EOR #&FF
 INC A
 STA fl_vo+3            \ -b
 STZ fl_vo
 STZ fl_vn
 LDX #8                 \ probe X: (sx, sy) + (fl_vo[fl_pxi], fl_vo[fl_pyi])
.flv1
 LDY fl_pxi,X           \ x: (sx - 128) + offset, signed, in -126..125 (x
 LDA fl_dx              \ 2..253, the clip window), else out of sight
 CLC
 ADC fl_vo,Y
 BVS flv8
 EOR #&80
 CMP #2
 BCC flv8
 CMP #254
 BCS flv8
 STA fl_vx
 LDY fl_pyi,X           \ y: (sy - 96) + offset in -95..95 (y 1..191)
 LDA fl_dy
 CLC
 ADC fl_vo,Y
 BVS flv8
 CLC
 ADC #95                \ y - 1
 CMP #191
 BCS flv8
 INC A
 TAY                    \ the byte: &4000 + (y DIV 8) * &200 + 8 * (x DIV
 LSR A                  \ 4) + y MOD 8
 LSR A
 AND #&FE
 ORA #&40
 STA fl_sp+1
 LDA fl_vx
 AND #&FC
 ASL A
 STA fl_sp
 BCC P%+4
 INC fl_sp+1
 TYA
 LSR A                  \ C: y odd (the sun's odd rows' colour)
 TYA
 AND #7
 TAY
 LDA (fl_sp),Y          \ the probe's pixel still the sun's colour for the
 EOR #FC_SUNE           \ row (a dithered row compares with its own byte)?
 BCC P%+4
 EOR #FC_SUNE EOR FC_SUNO
 STA fl_vy
 LDA fl_vx
 AND #3
 TAY
 LDA fl_pxm,Y
 AND fl_vy
 BNE flv8
 INC fl_vn
.flv8
 DEX
 BPL flv1
.fl_seen
 LDY fl_vn              \ none in sight: no flare (C clear)
 BNE P%+4
 CLC
 RTS
 LDY fl_vn              \ (K mode: T_FLARE forgets the kept rows)
 LDX fl_vred,Y          \ the flare turned down by the probes in sight: 0
.flm1                   \ for all 9, else -1, -2 or -3
 LDA fl_dx              \ level 3 if |dx| + |dy| < 96, 2 if < 192, else 1:
 JSR fl_abs             \ fl_lev = level - 3 + that
 STA fl_t
 LDA fl_dy
 JSR fl_abs
 CLC
 ADC fl_t
 CMP #96
 BCC flm2
 DEX
 CMP #192
 BCC flm2
 DEX
.flm2
 STX fl_lev
 LDA #255
 STA fl_ymin
 STZ fl_ymax
 LDX #1                 \ the centres' sums (x, then y): S = 32 k D, k = 8
.flm0                   \ to start (S = 256 D), stepped down by 32 D (|S| <
 LDA fl_dx,X            \ 2^15: the centre's offset k D / 8, floored, is S's
 STA fl_sh,X            \ high byte)
 STZ fl_sl,X
 CMP #&80               \ 32 D: D >> 3 (arithmetic), (D AND 7) << 5
 ROR A
 CMP #&80
 ROR A
 CMP #&80
 ROR A
 STA fl_mh,X
 LDA fl_dx,X
 AND #7
 LSR A
 ROR A
 ROR A
 ROR A
 STA fl_ml,X
 DEX
 BPL flm0
 STZ fl_i
 BRA flm3

.flm9
 LDA #255               \ the sun in sight: C set, and the rows written, Y ..
 STA R_XL               \ X (none if Y > X), which T_FLARE puts into the
 STZ R_XR               \ repair's row range (an empty extent: only the range
 LDY fl_ymin            \ grows)
 LDX fl_ymax
 SEC
 RTS

.flm8                   \ the sums for the next ghost: S -= (k - k') 32 D
 LDY fl_dk,X
 PHX
.flc1
 LDX #1
.flc2
 SEC
 LDA fl_sl,X
 SBC fl_ml,X
 STA fl_sl,X
 LDA fl_sh,X
 SBC fl_mh,X
 STA fl_sh,X
 DEX
 BPL flc2
 DEY
 BNE flc1
 PLX
 BRA flm4

.flm3                   \ the next ghost
 LDX fl_i
 CPX #FLNG
 BCS flm9
 INC fl_i
 TXA                    \ k = 8: the ring round the sun, if the sun is small
 BNE flm8
 LDA GSUNR
 CMP #FLHMAX+1
 BCS flm3
.flm4
 LDA fl_ni,X            \ density index + fl_lev (none if 0 or less)
 AND #&7F
 CLC
 ADC fl_lev
 BEQ flm3
 BMI flm3
 STA fl_m
 LDA fl_sh              \ centre = (128, 96) + (k D) >> 3
 EOR #&80
 STA fl_gx
 LDA fl_sh+1
 CLC
 ADC #96
 STA fl_gy
 LDA fl_ink,X
 STA fl_u
 LDA fl_ni,X
 BPL flm5
 JSR fl_dots            \ a dotted ring
 BRA flm3
.flm5
 JSR fl_disc            \ a disc
 BRA flm3

\ fl_abs: A = |A| (A from a load: N its sign; A > -128)

.fl_abs
 BPL P%+5
 EOR #&FF
 INC A
 RTS

\ fl_disc: ghost X, a disc (centre fl_gx, fl_gy; ink fl_u; density index
\ fl_m): its radius, half-widths and four row masks, then rows max(gy - r,
\ 1)..min(gy + r, 191) whose mask is not zero, each the span gx - h..gx + h
\ (h = the half-width at |y - gy|) clipped to x = 2..253: by d = |y - gy|
\ from r down to 0, rows gy - d and gy + d sharing the span

.fl_disc
 LDA fl_rad,X           \ radius, half-widths
 STA fl_r
 LDA fl_hl,X
 STA fl_hw
 LDA #HI(fl_htab)
 STA fl_hw+1
 STX fl_d               \ masks[index][(j + number) AND 3] AND ink, j = 0..3
 LDA fl_m
 ASL A
 ASL A
 STA fl_t
 LDY #3
.flm6
 TYA
 CLC
 ADC fl_d
 AND #3
 ORA fl_t
 TAX
 LDA fl_mt,X
 AND fl_u
 STA fl_pat,Y
 DEY
 BPL flm6
 LDA fl_gy              \ the rows' range
 CLC
 ADC fl_r
 CMP #192
 BCC P%+4
 LDA #191
 CMP fl_ymax
 BCC P%+4
 STA fl_ymax
 LDA fl_gy
 SEC
 SBC fl_r
 BCC P%+4
 BNE P%+4
 LDA #1
 CMP fl_ymin
 BCS P%+4
 STA fl_ymin
 LDA fl_r
 STA fl_d
 JMP fsd0

\ fl_dots: ghost X, a dotted ring (centre fl_gx, fl_gy; ink fl_u; density
\ index fl_m): fl_ring's points (times 2 ^ its scale), every one at density
\ index 3 or more, else every other one, in all four quadrants (the points
\ on the axes once each), each ORed in its ink where it is inside the clip
\ window

.fl_dots
 LDY #2                 \ the step: every point (2 bytes on) at index 3 or
 LDA fl_m               \ more, else every other one (4)
 CMP #3
 BCS P%+4
 LDY #4
 STY fl_r
 LDA fl_rad,X           \ (its scale)
 STA fl_t
 LDA #&FF               \ every row's mask: all (fl_lq has the pixel's), one
 STA fl_m               \ byte
 STZ fl_n
 LDX #0
.fsr1
 STX fl_d
 LDA fl_ring,X          \ dx, dy
 LDY fl_t
 BEQ P%+3
 ASL A
 STA fl_hw
 LDA fl_ring+1,X
 CPY #0
 BEQ P%+3
 ASL A
 STA fl_hw+1
 LDA fl_gx              \ columns gx + dx and gx - dx
 CLC
 ADC fl_hw
 BCS P%+5
 JSR fl_dcol
 LDA fl_hw              \ (dx = 0: the same column)
 BEQ fsr2
 LDA fl_gx
 SEC
 SBC fl_hw
 BCC P%+5
 JSR fl_dcol
.fsr2
 LDA fl_d
 CLC
 ADC fl_r
 TAX
 CPX #18
 BCC fsr1
 RTS

\ The tables (2-build-files/flare.py --tables, from its GHOSTS, LADDER, BAYER,
\ RING and hw_table; --verify checks them byte for byte, 6-harness/verify.sh runs
\ it: fl_rad, fl_ink, fl_ni, fl_mt, fl_dk, fl_ring, and fl_htab below, as
\ assembled)

                        \ the ghosts, by number (k = 8, 5, 3, -1, -3, -4, -6,
                        \ -8: centre C + k D / 8; 8: the ring round the sun):
                        \ radius (a ring: its scale, 1 for 30, 0 for 15), ink,
                        \ density index (+ &80: a dotted ring), half-widths
.fl_rad EQUB 1, 4, 7, 3, 10, 5, 0, 18
.fl_ink EQUB &FF, &FF, &F0, &0F, &0F, &FF, &F0, &0F
.fl_ni  EQUB &83, 4, 3, 5, 3, 3, &83, 2
.fl_hl  EQUB 0, LO(fl_h4), LO(fl_h7), LO(fl_h3), LO(fl_h10), LO(fl_h5), 0, LO(fl_h18)

fl_mt = P% - 4          \ row masks of densities 1, 2, 4, 6, 8 / 16 (4x4
                        \ Bayer), by density index (1..5) and row
 EQUB &88, &00, &00, &00
 EQUB &88, &00, &22, &00
 EQUB &AA, &00, &AA, &00
 EQUB &AA, &44, &AA, &11
 EQUB &AA, &55, &AA, &55

.fsd0
.fsd1                   \ d (r down to 0): either row's mask not zero?
 LDA fl_gy
 SEC
 SBC fl_d
 AND #3
 TAX
 LDA fl_pat,X
 BNE fsd5
 LDA fl_gy
 CLC
 ADC fl_d
 AND #3
 TAX
 LDA fl_pat,X
 BEQ fsd8
.fsd5                   \ the span gx - h..gx + h, clipped
 LDY fl_d
 LDA (fl_hw),Y
 TAX
 EOR #&FF               \ XL = max(gx - h, 2)
 SEC
 ADC fl_gx
 BCS P%+4
 LDA #0
 CMP #2
 BCS P%+4
 LDA #2
 STA R_XL
 TXA                    \ XR = min(gx + h, 253)
 CLC
 ADC fl_gx
 BCS P%+6
 CMP #254
 BCC P%+4
 LDA #253
 STA R_XR
 CMP R_XL
 BCC fsd8
 AND #3                 \ the last byte's mask, the first's, the first's
 TAX                    \ column (x 8) and 8 x (bytes - 1), shared by the
 LDA fl_rmt,X           \ two rows
 STA fl_rq
 LDA R_XL
 AND #3
 TAX
 LDA fl_lmt,X
 STA fl_lq
 LDA R_XL
 AND #&FC
 STA fl_t
 ASL A
 STA fl_cl
 LDA #&20                \ (&40 + C)
 ROL A
 STA fl_ch
 LDA R_XR
 AND #&FC
 SEC
 SBC fl_t
 ASL A
 STA fl_n
 BNE fsd2
 LDA fl_lq              \ one byte: both masks
 AND fl_rq
 STA fl_lq
.fsd2
 LDA fl_gy              \ row gy - d, if >= 1
 SEC
 SBC fl_d
 BCC fsd3
 BEQ fsd3
 JSR fl_row
.fsd3
 LDA fl_d               \ row gy + d, if d > 0 and gy + d <= 191
 BEQ fsd8
 CLC
 ADC fl_gy
 CMP #192
 BCS fsd8
 JSR fl_row
.fsd8
 DEC fl_d
 BMI P%+5
 JMP fsd1
 RTS

\ fl_dcol: a dotted ring's column A: rows gy + dy and gy - dy

.fl_dcol
 CMP #2
 BCC fsc9
 CMP #254
 BCS fsc9
 STA R_XL
 STA R_XR
 TAY
 AND #&FC               \ its byte's column (fl_cl, fl_ch), pixel mask
 ASL A
 STA fl_cl
 LDA #&20                \ (&40 + C)
 ROL A
 STA fl_ch
 TYA
 AND #3
 TAX
 LDA fl_pxm,X
 AND fl_u
 STA fl_lq
 LDA fl_gy              \ (gy + dy <= 191 + 30: no carry)
 CLC
 ADC fl_hw+1
 JSR fl_drow
 LDA fl_hw+1            \ (dy = 0: the same row)
 BEQ fsc9
 LDA fl_gy
 SEC
 SBC fl_hw+1
 BCC fsc9
.fl_drow                \ row A, if inside the clip window
 CMP #1
 BCC fsc9
 CMP #192
 BCS fsc9
 CMP fl_ymax            \ the rows' range
 BCC P%+4
 STA fl_ymax
 CMP fl_ymin
 BCS P%+4
 STA fl_ymin
 TAY
 JMP fl_row1
.fsc9
 RTS

\ fl_row: row A (inside the clip window), if its mask (fl_pat) is not zero:
\ extend this buffer's dirty extent for the row by R_XL..R_XR, point fl_sp
\ at its first byte (column fl_cl / fl_ch) and OR the bytes (fl_or, with
\ the row's mask fl_m). Clobbers A, X, Y.

.fl_row
 TAY
 AND #3
 TAX
 LDA fl_pat,X
 BEQ fsc9
 STA fl_m
.fl_row1                \ (Y = row, fl_m = its mask)
 LDA R_XL
.fl_dl1
 CMP R_DIRTYL0,Y        \ patched (this buffer's)
 BCS P%+5
.fl_dl2
 STA R_DIRTYL0,Y
 LDA R_XR
.fl_dr1
 CMP R_DIRTYR0,Y
 BCC P%+5
.fl_dr2
 STA R_DIRTYR0,Y
 TYA                    \ &4000 + (y DIV 8) * &200 + (y MOD 8) + 8 * (XL DIV 4)
 AND #7
 ORA fl_cl
 STA fl_sp
 TYA
 LSR A
 LSR A
 AND #&FE
 ORA fl_ch
 STA fl_sp+1
                        \ (and on into fl_or)

\ fl_or: OR the span at fl_sp into the back buffer: its last byte (offset
\ fl_n) with fl_rq AND fl_m, then if fl_n > 0 the bytes between with fl_m and
\ its first with fl_lq AND fl_m (fl_n = 0: the one byte, with fl_lq AND
\ fl_m). Clobbers A, Y.

.fl_or
 LDY fl_n
 BEQ flo9
 LDA fl_rq
 AND fl_m
 ORA (fl_sp),Y
 STA (fl_sp),Y
 SEC
 BRA flo3
.flo2
 LDA (fl_sp),Y
 ORA fl_m
 STA (fl_sp),Y
.flo3
 TYA
 SBC #8
 TAY
 BNE flo2
.flo9
 LDA fl_lq
 AND fl_m
 ORA (fl_sp)
 STA (fl_sp)
 RTS

.fl_dk  EQUB 0, 3, 2, 4, 2, 1, 2, 2 \ the k steps 8 -> 5 -> 3 -> -1 -> -3 ->
                                    \ -4 -> -6 -> -8, by ghost
.fl_lmt EQUB &FF, &77, &33, &11     \ pixels x AND 3..3 of a byte
.fl_rmt EQUB &88, &CC, &EE, &FF     \ pixels 0..x AND 3
.fl_pxm EQUB &88, &44, &22, &11     \ pixel x AND 3
.fl_pxi EQUB 0, 1, 4, 0, 0, 2, 2, 3, 3 \ the probes' offsets (fl_vo): the
.fl_pyi EQUB 0, 0, 0, 1, 4, 2, 3, 2, 3 \ centre, right, left, down, up and
                                       \ the four diagonals
.fl_vred EQUB 0, -3, -3, -3, -2, -2, -2, -1, -1, 0 \ by the probes in sight
                                    \ (0: no flare)
.fl_ring                \ (dx, dy) of 9 points of a quarter circle of radius 15
 EQUB 15, 0, 15, 3, 14, 6, 12, 8, 11, 11, 8, 12, 6, 14, 3, 15, 0, 15

\ The flare's half-widths and variables
.fl_htab                \ the half-widths: the widest x with x^2 + d^2 <= r^2
MACRO FLHW r            \ + r, d = 0..r (one page: fl_hw's high byte is
 FOR d, 0, r            \ fixed)
  EQUB INT(SQR(r * r + r - d * d))
 NEXT
ENDMACRO
.fl_h3  FLHW 3
.fl_h4  FLHW 4
.fl_h5  FLHW 5
.fl_h7  FLHW 7
.fl_h10 FLHW 10
.fl_h18 FLHW 18
ASSERT HI(fl_htab) = HI(P% - 1)
.fl_ml  SKIP 2          \ 32 D (x, y), low and high bytes
.fl_mh  SKIP 2
.fl_sl  SKIP 2          \ the centres' sums S (x, y)
.fl_sh  SKIP 2
.fl_lev SKIP 1          \ the level less 3, turned down by the probes (-5..0)
