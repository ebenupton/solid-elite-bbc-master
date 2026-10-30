\ ============================================================================
\ raster_disc2.asm -- the second disc (R_DISC2): the smaller of the sun and
\ the planet when both are on the screen (the frame layer's f_disc2), drawn
\ behind the disc layer, incrementally.  In bank 5, at the end of the shared
\ region (where the lens flare was), with its per-buffer spans in bank 5
\ too (elite-gfx.asm: R_S2L0, R_S2L1 in the room below the per-x tables,
\ R_S2R0, R_S2R1 after this code) and its rows and colour in the shared
\ workspace (R_S2T, R_S2B, R_S2C).  Called with the rasteriser's disc
\ window paged (T_DISCROWS with C set, ROMSEL 5: R_DISCROWS' first
\ instruction sends it here): it writes through r_sw and settles kept rows
\ with k_kill (in the disc window).
\
\ R_DISC2: after R_DISCROWS, for the current buffer.  In: R_NDT..R_NDB and
\ R_NDISCL/R, the second disc's spans, clamped to the window as for
\ R_DISCROWS (NDT > NDB: none, best passed as 255, 0; an empty row is L =
\ 255, R = 0), and empty spans on the buffer's old rows (R_S2T..R_S2B)
\ outside NDT..NDB, and between the two (the frame layer's f_disc2 fills
\ them); R_COLE/R_COLO its colour pair.
\ The disc layer (this buffer's R_DISCL/R, as R_DISCROWS has just left them)
\ is in front of it: row y of the second disc shows its span a..b less the
\ layer's L..R, up to two pieces (the original's sun line heap keeps each
\ row's span the same way).
\
\ Each buffer remembers its rows' spans a..b (R_S2L/R) and their rows
\ (R_S2T..R_S2B) as drawn, and its colour (R_S2C, the even rows' byte).
\ What R_DISCROWS has just written this frame on a row (R_WL..R_WR: the
\ layer's writes and the dirty repair) is all that can have happened to the
\ old pieces there since: the shapes drawn over them were in the dirty
\ extents, the layer's old span L0 never held them, and wherever the layer
\ moved off (L0 less the new L) it wrote black.  So on each row, with the
\ old span a0..b0 and the new a1..b1, less the layer's span each time:
\
\   * the same span and nothing written over it: nothing to do (a few
\     compares);
\   * the same span, written over: max(a, WL) .. min(b, WR) drawn again;
\   * the spans overlap: the ends that shrank black, the ends that grew in
\     the disc's colour; if this frame also wrote over the new span, one span
\     over the grown ends and that part instead (pixels between them that
\     are still the disc's are written again, harmlessly);
\   * apart, or one of them empty, or the colour changed (the sun and the
\     planet swapped which is the bigger, so this disc is the other one now):
\     the old span black, then the new span whole.
\   * both spans empty or behind the layer: nothing.
\
\ The writes are masked to their pixels (r_sw), and added to R_WL/R_WR (and
\ R_PRWT..R_PRWB), so the text and the sights see them as written, as they
\ see the disc layer's; nothing goes into DIRTY, so the next frame on this
\ buffer does not repair them.  In K mode a row it writes is settled first
\ (k_kill), as T_SPAN would.  R_RESETBUF (on a buffer just blacked)
\ forgets the buffer's rows and sets its colour to none (0, which no disc
\ is): R_DISC2 empties its spans when it next draws there (so a reset
\ costs nothing until then) and draws its rows as recoloured.  R_SETBUF
\ patches the operands of this buffer's spans
\ (r_s2l, r_s2r) and of the layer's (r_sl, r_sr).
\ ============================================================================

d_a1 = &20              \ the row: new span a1..b1, old a0..b0, the layer's
d_b1 = &21              \ L..R (no layer: L = R = 255), in zero page that
d_a0 = &24              \ neither r_sw nor k_kill uses
d_b0 = &25
d_L  = &1D
d_R  = &1F
d_p  = &26              \ d2put's first pixel
d_q  = &1A              \ (these three: r_sw keeps them, k_kill does not)
d_mn = &23              \ this row's writes: pixels d_mn .. d_mx (none: d_mx = 0)
d_mx = &1E
d_c  = r_ov             \ the colour d2put writes in
d_cs = r_ov + 1         \ this row's disc colour (R_COLE / R_COLO)
d_y  = r_ov + 2         \ the row
d_hi = r_ov + 3         \ the last row
d_fl = r_ov + 18        \ &FF: the colour changed (every row old black, new whole)
d_t  = r_ov + 19

.R_DISC2
{
  LDX R_PRBUF
  STZ d_fl                \ the colour changed (and so the disc) since this
  LDA R_COLE              \ buffer's last frame?
  CMP R_S2C,X
  BEQ c1
  LDY R_S2C,X
  STA R_S2C,X
  DEC d_fl                \ (no colour before: the buffer was reset and
  TYA                     \ blacked since, so its spans become empty here)
  BNE c1
  LDY #191
.c0
  LDA #&FF
.^r_pt518 STA r_s2l,Y
  LDA #0
.^r_pt519 STA r_s2r,Y
  DEY
  CPY #&FF
  BNE c0
.c1
  LDA R_NDT               \ the rows: old + new (lo .. hi)
  LDY R_S2T,X
  STA R_S2T,X
  STY d_y                 \ (lo, for the moment)
  CMP d_y
  BCS c3
  STA d_y
.c3
  LDA R_NDB
  LDY R_S2B,X
  STA R_S2B,X
  STY d_hi
  CMP d_hi
  BCC c4
  STA d_hi
.c4
  LDA d_hi
  CMP d_y
  BCS c5
  RTS                     \ none, old or new
.c5
  LDA d_y                 \ any of the rows lo .. hi may get R_WL/R_WR
  CMP R_PRWT
  BCS c6
  STA R_PRWT
.c6
  LDA d_hi
  CMP R_PRWB
  BCC c7
  STA R_PRWB
.c7
  LDX d_y
.lp                       \ the rows lo .. hi: unchanged and not written over,
  LDA R_NDISCL,X          \ a few compares
.^r_pt500 CMP r_s2l,X
  BNE ch
  LDA R_NDISCR,X
.^r_pt503 CMP r_s2r,X
  BNE ch
  LDA R_WR,X
  ORA d_fl
  BNE wo
.nx
  CPX d_hi
  INX
  BCC lp
  RTS
.ch                       \ changed (or recoloured): nothing to draw if both
  LDA R_NDISCL,X          \ spans are empty or behind the layer (an empty
.^r_pt510 CMP r_sl,X      \ span, 255 .. 0, is); just remember the new one
  BCC cr
.^r_pt511 LDA r_sr,X
  CMP R_NDISCR,X
  BCC cr
.^r_pt512 LDA r_s2l,X
.^r_pt513 CMP r_sl,X
  BCC cr
.^r_pt514 LDA r_sr,X
.^r_pt515 CMP r_s2r,X
  BCC cr
  LDA R_NDISCL,X
.^r_pt516 STA r_s2l,X
  LDA R_NDISCR,X
.^r_pt517 STA r_s2r,X
  BRA nx
.cr
  STX d_y
  JSR row
  LDX d_y
  BRA nx
.wo                       \ recoloured: every row
  BIT d_fl
  BMI ch
  LDA R_NDISCL,X          \ unchanged, written over this frame: nothing if
.^r_pt508 CMP r_sl,X      \ the span is behind the layer (or empty), else
  BCC w0                  \ max(a, WL) .. min(b, WR), if any, drawn again
.^r_pt509 LDA r_sr,X
  CMP R_NDISCR,X
  BCS nx
.w0
  LDA R_WR,X
  CMP R_NDISCR,X
  BCC w1
  LDA R_NDISCR,X
.w1
  STA d_b1
  LDA R_WL,X
  CMP R_NDISCL,X
  BCS w2
  LDA R_NDISCL,X
.w2
  CMP d_b1
  BEQ w3
  BCS nx
.w3
  STA d_a1
  STX d_y
  JSR lay
  LDA d_a1                \ (all of it behind the layer: nothing)
  CMP d_L
  BCC w4
  LDA d_R
  CMP d_b1
  BCS w5
.w4
  JSR d2set
  LDA d_a1
  LDX d_b1
  JSR d2put
  JSR d2fin
.w5
  LDX d_y
  JMP nx

.all
  STZ d_c                 \ the old span black (none if empty) ...
  LDA d_a0
  LDX d_b0
  JSR d2put
  LDA d_cs                \ ... then the new span whole
  STA d_c
  LDA d_a1
  LDX d_b1
  JMP wn


.row                      \ row X (= d_y): changed or recoloured, and some of
                          \ it in front of the layer
.^r_pt501 LDY r_s2l,X     \ the old span
  STY d_a0
.^r_pt504 LDY r_s2r,X
  STY d_b0
  LDA R_NDISCL,X          \ the new one, remembered
  STA d_a1
.^r_pt502 STA r_s2l,X
  LDA R_NDISCR,X
  STA d_b1
.^r_pt505 STA r_s2r,X
  JSR lay
.go
  JSR d2set
  BIT d_fl                \ recoloured, an empty span or the spans apart: all
  BMI all
  LDA d_b1
  CMP d_a1
  BCC all                 \ the new span empty
  LDA d_b0
  CMP d_a0
  BCC all                 \ the old one empty
  CMP d_a1
  BCC all                 \ b0 < a1
  LDA d_b1
  CMP d_a0
  BCC all                 \ b1 < a0
  LDA d_L                 \ the spans overlap: with no layer on the row and
  INC A                   \ nothing written over it (the commonest case), the
  BNE gn                  \ ends' strips straight through r_sw
  LDX d_y
  LDA R_WR,X
  BNE gn
  LDA d_a1                \ the left end: a0 .. a1-1 black, or a1 .. a0-1 in
  CMP d_a0                \ the disc's colour
  BEQ q2
  BCC q1
  DEC A
  TAY
  LDX d_a0
  LDA #0
  BRA q3
.q1
  TAX
  LDY d_a0
  DEY
  LDA d_cs
.q3
  STX d_mn
  STY d_mx
  JSR r_sw
.q2
  LDA d_b1                \ the right end: b0+1 .. b1 in the disc's colour, or
  CMP d_b0                \ b1+1 .. b0 black
  BEQ q6
  BCC q4
  TAY
  LDX d_b0
  INX
  LDA d_cs
  BRA q5
.q4
  TAX
  INX
  LDY d_b0
  LDA #0
.q5
  STY d_mx
  CPX d_mn
  BCS q7
  STX d_mn
.q7
  JSR r_sw
.q6
  LDX d_y                 \ (R_WR was 0 on this row)
  LDA d_mn
  STA R_WL,X
  LDA d_mx
  STA R_WR,X
  RTS
.gn
  STZ d_c                 \ else the ends that shrank, black, through d2put
  LDA d_a1
  CMP d_a0
  BEQ b2
  BCC b2
  DEC A                   \ a0 .. a1-1
  TAX
  LDA d_a0
  JSR d2put
.b2
  LDA d_b0
  CMP d_b1
  BEQ b3
  BCC b3
  TAX                     \ b1+1 .. b0
  LDA d_b1
  INC A
  JSR d2put
.b3
  LDA d_cs                \ then the ends that grew, in the disc's colour
  STA d_c
  LDX d_y                 \ (written over too: max(a1, WL) .. min(b1, WR),
  LDA R_WR,X              \ if not empty, and they as one span)
  BEQ h0
  CMP d_b1
  BCC g4
  LDA d_b1
.g4
  STA d_t
  LDA R_WL,X
  CMP d_a1
  BCS g5
  LDA d_a1
.g5
  CMP d_t
  BEQ g6
  BCC g6
.h0
  LDA d_a1                \ the left end, a1 .. a0-1, if it grew
  CMP d_a0
  BCS h1
  LDX d_a0
  DEX
  JSR d2put
.h1
  LDA d_b0                \ the right, b0+1 .. b1
  CMP d_b1
  BCS h2
  INC A
  LDX d_b1
  JSR d2put
.h2
  JMP d2fin
.g6
  STA d_p                 \ max(a1, WL) .. min(b1, WR) (d_p .. d_t), widened
  LDA d_a1                \ over the ends that grew: the left, a1 .. a0-1 ...
  CMP d_a0
  BCS g7
  STA d_p
  LDX d_a0
  DEX
  CPX d_t
  BCC g7
  STX d_t
.g7
  LDA d_b0                \ ... and the right, b0+1 .. b1
  CMP d_b1
  BCS g9
  INC A
  CMP d_p
  BCS g8
  STA d_p
.g8
  LDA d_b1
  STA d_t
.g9
  LDA d_p
  LDX d_t
.wn
  JSR d2put
  JMP d2fin
}

\ lay: the layer's span on row X: d_L .. d_R (none: R = 255 too, so that a
\ piece is never right of it).  Keeps X.
.lay
{
.^r_pt507 LDY r_sr,X
.^r_pt506 LDA r_sl,X
  STA d_L
  INC A
  BNE l1
  LDY #&FF
.l1
  STY d_R
  RTS
}

\ d2set: row d_y about to be written: settled first in K mode (as T_SPAN's
\ k_kill); its pointers (RZ_PA, RZ_PB, RZ_Y), the disc's colour on it
\ (d_cs), no writes yet (d_mn .. d_mx)
.d2set
{
  BIT KMODE
  BPL s1
  LDA d_y
  TAX
  JSR k_kill              \ (rows A .. X; leaves R_WL/R_WR as the repair did) bankcheck: ok (R_DISC2 runs with the disc window paged in)
.s1
  LDX d_y
  STX RZ_Y
  TXA
  AND #7
  STA RZ_PA
  STA RZ_PB
  LDA r_ypg,X
  STA RZ_PA+1
  INC A
  STA RZ_PB+1
  TXA
  LSR A
  LDA R_COLE
  BCC s2
  LDA R_COLO
.s2
  STA d_cs
  STA d_c
  LDA #&FF
  STA d_mn
  STZ d_mx
  RTS
}

\ d2put: pixels A .. X (none if A > X) less the layer's span d_L .. d_R, in
\ colour d_c, on the row d2set set up; noted in d_mn .. d_mx.  Clobbers A,
\ X, Y and what r_sw does.
.d2put
{
  STA d_p
  STX d_q
  CPX d_p
  BCC x9                  \ X < A: none
  LDY d_L                 \ no layer on the row: all of it
  INY
  BEQ wr
  CMP d_L
  BCS rt                  \ A >= L: nothing left of the layer
  LDX d_L                 \ left of it: A .. min(X, L - 1)
  DEX
  CPX d_q
  BCC l1
  LDX d_q
.l1
  JSR wr
.rt
  LDA d_R                 \ right of it: max(A, R + 1) .. X, if X > R
  CMP d_q
  BCS x9
  INC A
  CMP d_p
  BCS r1
  LDA d_p
.r1
  LDX d_q
.wr                       \ pixels A .. X (A <= X)
  CMP d_mn
  BCS w1
  STA d_mn
.w1
  CPX d_mx
  BCC w2
  STX d_mx
.w2
  STA R_XL
  STX R_XR
  STX d_t
  TAX
  LDA d_t
  SEC
  SBC R_XL
  CMP #16
  BCC w3
  LDA d_c                 \ 17 pixels or more: through the run (as r_sw's
  STA RZ_COL              \ own long path would, from more)
  LDY RZ_Y
  JSR r_rowset
  LDX R_XL
  JMP r_spc
.w3
  LDY d_t
  LDA d_c
  JMP r_sw
.x9
  RTS
}

\ d2fin: row d_y's writes (d_mn .. d_mx) into R_WL/R_WR (R_DISC2 has put
\ its rows into R_PRWT..R_PRWB)
.d2fin
{
  LDA d_mx
  BEQ f9                  \ (none)
  LDX d_y
  LDY R_WR,X
  BNE f1
  DEY                     \ (none written yet: no left end)
  TYA
  STA R_WL,X
  LDA d_mx
.f1
  CMP R_WR,X
  BCC f2
  STA R_WR,X
.f2
  LDA d_mn
  CMP R_WL,X
  BCS f3
  STA R_WL,X
.f3
.f9
  RTS
}

\ R_SETBUF's high bytes for the spans' operands (r_s2l, r_s2r), by buffer
.r_sbh_s2l EQUB HI(R_S2L0), HI(R_S2L1)
.r_sbh_s2r EQUB HI(R_S2R0), HI(R_S2R1)
