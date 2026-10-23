\ ============================================================================
\ gfx-kept7.asm -- kept solid rows (docs/renderer.md), the polygons' part:
\ bank 7 (ROMSEL 7), after the meridian window.  R_POLY calls k_pre in K
\ mode, between its phases, through T_KPRE (the glue area); k_settle writes
\ the screen itself (piece).  Everything it reads
\ is in main RAM (the edge tables, DIRTY, KF) or the screen (ACCCON X as
\ the frame has it).  See gfx-raster_kept.asm for the scheme.
\ ============================================================================

KT = 8                  \ the least interior (whole bytes) a kept row must have

k_dl = &10              \ (the rasteriser's scratch, &10-&27: free between
k_ml = &11              \ R_POLY's phases) DL; the new span's end masks
k_mr = &12
k_nl = &13              \ and end bytes' columns
k_ne = &14
k_ce = &15              \ zone: its last byte's column
k_pa = &16              \ (2) the row's columns 0-31 on the screen
k_pb = &1A              \ (2) and 32-63
k_t  = &1C
k_v  = &1D
k_y  = &20
k_xl = &21
k_xr = &22
k_w  = &23
k_col = &24             \ (4) k_pre: the colour bytes of rows y AND 3 = 0..3

\ k_pre: R_POLY's rows r_ystart..r_yend-1 (its edge tables), before phase B.
\ A = the low byte of the left table (r_ta or r_tb).  For each row with a
\ span: a pending row is settled (k_settle); any other row is kept in this
\ buffer (KBIT) if the span covers its dirty extent (and is wide enough, in a
\ non-zero colour), else forgotten.
.k_pre
{
  LDX #0                  \ left, right: r_ta, r_tb (X = 0) or r_tb, r_ta
  CMP #LO(r_ta)
  BEQ p1
  LDX #2
.p1
  LDA k_tab,X
  STA kl1+1
  STA kl2+1
  STA kl3+1
  LDA k_tab+1,X
  STA kl1+2
  STA kl2+2
  STA kl3+2
  LDA k_tab+2,X
  STA kr1+1
  STA kr2+1
  STA kr2b+1
  STA kr3+1
  STA kr4+1
  LDA k_tab+3,X
  STA kr1+2
  STA kr2+2
  STA kr2b+2
  STA kr3+2
  STA kr4+2
  LDA R_COLE              \ the colour bytes of rows y AND 3 = 0..3
  STA k_col
  LDA R_COLO
  STA k_col+1
  LDA R_COL2
  STA k_col+2
  LDA R_COL3
  STA k_col+3
  LDA r_yend
  STA kye+1
  LDY r_ystart
.row
.kl1
  LDA r_ta,Y              \ (patched) XL
.kr1
  CMP r_tb,Y              \ (patched) XR + 1
  BCS next                \ no span
  LDX KF,Y
  BMI pend
.^k_pd1
  CMP R_DIRTYL0,Y         \ (patched by buffer) does it cover the extent?
  BEQ c1
  BCS kill0               \ XL > DL
.c1
  STA k_xl
.kr2
  LDA r_tb,Y              \ (patched) XR + 1
  DEC A
.^k_pd2
  CMP R_DIRTYR0,Y         \ (patched by buffer)
  BCC kill                \ XR < DR
  SBC k_xl                \ (C = 1) XR - XL >= 4 KT + 7: KT whole bytes inside
  CMP #4 * KT + 7
  BCC kill
  TYA
  AND #3
  TAX
  LDA k_col,X
  BEQ kill                \ (black is never kept)
  LDA KF,Y
  ORA KBIT
  STA KF,Y
.next
  INY
.kye
  CPY #0                  \ (patched: r_yend)
  BCC row
  RTS
.kill0
  TXA                     \ (X = KF,Y)
  BEQ next
  BNE k1
.kill
  LDA KF,Y
  BEQ next
.k1
  AND KBITN
  STA KF,Y
  BRA next
.pend
  JSR k_settle
  BRA next
}

\ k_settle: Y = a pending row (kept), A = its span's XL; XR + 1 in the right
\ table.  The row holds the old span DL..DR (DIRTY) in v and nothing else; it
\ is to hold the new span XL..XR in w and nothing else (for now: the rest of
\ the frame draws over it as it would over the new span alone).  Only the
\ pixels of the zones between DL and XL and between DR and XR differ, so only
\ the bytes in them are written, with their final value (w where the new span
\ covers the pixel, else black).  If w = v the row is then complete and phase
\ B leaves it; else phase B draws the span over it as usual.
.k_settle
{
  STA k_xl
  STY k_y
.^kr2b
  LDA r_tb,Y              \ (patched with kr1)
  DEC A
  STA k_xr
  TYA
  AND #3
  TAX
  LDA k_col,X
  STA k_w
  LDA k_y                 \ k_pa, k_pb: &4000 + (y DIV 8) * &200 + (y AND 7),
  AND #7                  \ + &100: the row's columns 0-31, 32-63
  STA k_pa
  STA k_pb
  TYA
  LSR A
  LSR A
  AND #&FE
  ORA #&40
  STA k_pa+1
  INC A
  STA k_pb+1
.^k_pd3
  LDA R_DIRTYL0,Y         \ (patched)
  STA k_dl
  \ v: the old row's byte at column DL DIV 4 + 1, or + 2 if that is column 32
  \ (where the sights' vertical arm ORs a pixel in)
  LSR A
  LSR A
  INC A
  CMP #32
  BNE v0
  INC A
.v0
  ASL A
  ASL A
  ASL A
  TAY
  BCS vb                  \ (C: column >= 32)
  LDA (k_pa),Y
  BRA vv
.vb
  LDA (k_pb),Y
.vv
  STA k_v
  LDY k_y
  \ the same span in the same colour (the station held still): nothing to
  \ write, phase B has nothing to do, and the row stays kept
  LDA k_dl
  CMP k_xl
  BNE full
.^k_pd7
  LDA R_DIRTYR0,Y         \ (patched)
  CMP k_xr
  BNE full
  LDA k_w
  CMP k_v
  BNE full
  LDA #0
.^kl3
  STA r_ta,Y              \ (patched with kl1)
.^kr4
  STA r_tb,Y              \ (patched with kr1)
  LDA KF,Y
  AND #&7F
  ORA KBIT
  STA KF,Y
  RTS
.full
  \ the new span's end bytes, and their masks
  LDA k_xl
  AND #3
  TAX
  LDA k_lm,X
  STA k_ml
  LDA k_xl
  LSR A
  LSR A
  STA k_nl
  LDA k_xr
  AND #3
  TAX
  LDA k_rm,X
  STA k_mr
  LDA k_xr
  LSR A
  LSR A
  STA k_ne
  \ the left zone: min(DL, XL) .. max(DL, XL) - 1
  LDA k_dl
  CMP k_xl
  BEQ z2
  LDX k_xl
  BCS z1                  \ DL > XL: XL .. DL - 1
  TAX                     \ DL < XL: DL .. XL - 1
  LDA k_xl
.z1
  DEC A
  JSR zone
.z2
.^k_pd4
  LDA R_DIRTYR0,Y         \ (patched) the right zone: min(DR, XR) + 1 .. max(DR, XR)
  CMP k_xr
  BEQ z3
  BCS z2a                 \ DR > XR: XR + 1 .. DR
  LDX k_xr                \ DR < XR: DR + 1 .. XR
  INC A
  STA k_t
  TXA
  LDX k_t
  BRA z2b
.z2a
  LDX k_xr
  INX
.z2b
  JSR zone
.z3
  LDY k_y
  LDA k_xl                \ the dirty extent is the span's
.^k_pd5
  STA R_DIRTYL0,Y         \ (patched)
  LDA k_xr
.^k_pd6
  STA R_DIRTYR0,Y         \ (patched)
  LDA k_w
  CMP k_v
  BNE rec                 \ another colour: phase B draws the span
  LDA #0                  \ the same: the row is done, phase B has nothing to
.^kl2                     \ do in it
  STA r_ta,Y              \ (patched with kl1)
.^kr3
  STA r_tb,Y              \ (patched with kr1)
.rec                      \ the span is all the row holds: kept if wide enough
  LDA KF,Y
  AND #&7F
  AND KBITN
  STA KF,Y
  LDA k_xr
  SEC
  SBC k_xl
  CMP #4 * KT + 7
  BCC rx
  LDA k_w
  BEQ rx
  LDA KF,Y
  ORA KBIT
  STA KF,Y
.rx
  RTS
\ zone: pixels X .. A (X <= A): their bytes to their final values (keeps Y)
.zone
  LSR A
  LSR A
  STA k_ce                \ the last byte's column
  TXA
  LSR A
  LSR A
  TAX                     \ X = the first's
.zl
  LDA #0                  \ the new span's pixels in column X, in w
  CPX k_nl
  BCC zw
  CPX k_ne
  BEQ ze
  BCS zw
  LDA #&FF
.zm
  CPX k_nl
  BNE zr
  AND k_ml
.zr
  AND k_w
.zw
  STA k_t
  TXA
  ASL A
  ASL A
  ASL A
  TAY
  LDA k_t
  CPX #32
  BCS zwb
  CPX #0                  \ (columns 0 and 63: the pixels outside the clip
  BNE zsa                 \ window, x 2..253, kept: the border's and its
  LDA (k_pa),Y            \ neighbour's)
  AND #&CC
  ORA k_t
.zsa
  STA (k_pa),Y
  BRA zn
.zwb
  CPX #63
  BNE zsb
  LDA (k_pb),Y
  AND #&33
  ORA k_t
.zsb
  STA (k_pb),Y
.zn
  CPX k_ce
  INX
  BCC zl
  LDY k_y
  RTS
.ze
  LDA k_mr
  BRA zm
.k_lm EQUB &FF, &77, &33, &11     \ pixels (x AND 3)..3 of a byte
.k_rm EQUB &88, &CC, &EE, &FF     \ pixels 0..(x AND 3)
}

.k_tab EQUW r_ta, r_tb, r_ta
