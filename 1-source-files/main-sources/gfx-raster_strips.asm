\ ============================================================================
\ raster_strips.asm -- the strip encoder's core: a changed two-colour disc
\ row written as the difference of its old and new edge lists (each list:
\ the span's left end, the boundaries, the end after the right end; a pixel
\ takes the colour after the last edge at or before it, black after the
\ last).  The two lists are made alike, three boundaries each and the same
\ colour at the left end, with virtual boundaries (segments of no width):
\ one at the left end of the list with fewer if the colours there differ,
\ then at the end after the right end as many as each lacks.  Then each
\ edge's strip, old .. new, is written in the colour on the side it moved
\ from, cut short where the edge before's new place (moving right) or the
\ edge after's (moving left) has passed into it: exactly the pixels whose
\ colour changed, as both lists are in order.
\
\ gfx-raster_disc.asm's r_dpe INCLUDEs it between its entry and its store
\ (r_dpst), giving it:
\   the edges: old r_ol, rs_t0 .. rs_t2, r_oe; new r_nl, rs_t3 .. rs_t5, r_ne
\     (boundaries past a list's count are anything) and the counts r_ok and
\     r_nk (0 .. 3);
\   rs_cols: from A's bit 7 (colour B at the left end), r_c0 and r_c1, the
\     colours of the segment at the left end and of the next (keeps X);
\   rs_put: pixels X .. Y (X <= Y) in colour A (0: black, else r_c0 or r_c1);
\   rs_ov: where to go with more than three boundaries (nothing written).
\ Entered at rs_df with A's bit 7 the new left end's colour and C set if
\ the old one's differs (or at rs_cs, the colours the same, A's bit 7 their
\ colour), it falls through, the strips written, to the code after its
\ INCLUDE.
\ ============================================================================
{
.^rs_df
  BCC rs_cs               \ the colours at the left end differ: a virtual
  LDY r_ok                \ boundary there in the list with fewer (the new
  CPY r_nk                \ if as many), which then takes the other's colour
  BCC il
  LDY r_nk
  CPY #3
  BNE in
  JMP rs_ov               \ (three new already)
.in
  INC r_nk
  LDY rs_t4
  STY rs_t5
  LDY rs_t3
  STY rs_t4
  LDY r_nl
  STY rs_t3
  EOR #&80                \ (the old left end's colour)
  BRA rs_cs
.il
  INC r_ok
  LDY rs_t1
  STY rs_t2
  LDY rs_t0
  STY rs_t1
  LDY r_ol
  STY rs_t0
.^rs_cs
  JSR rs_cols
.pd
  LDA r_oe                \ virtual boundaries at each list's end after its
  LDX r_ok                \ right end, to three
  BEQ o0
  DEX
  BEQ o1
  DEX
  BEQ o2
  BRA o3
.o0
  STA rs_t0
.o1
  STA rs_t1
.o2
  STA rs_t2
.o3
  LDA r_ne
  LDX r_nk
  BEQ q0
  DEX
  BEQ q1
  DEX
  BEQ q2
  BRA go
.q0
  STA rs_t3
.q1
  STA rs_t4
.q2
  STA rs_t5
.go
  LDA r_nl                \ the left end: moved right, old .. new-1 black;
  CMP r_ol                \ left, new .. old-1 in segment 0's colour, up to
  BEQ e0                  \ the first boundary's new place
  BCC l0
  DEC A
  TAY
  LDX r_ol
  LDA #0
  JSR rs_put
  BRA e0
.l0
  LDA r_ol
  CMP rs_t3
  BCC k1
  LDA rs_t3
.k1
  CMP r_nl
  BEQ e0
  TAY
  DEY
  LDX r_nl
  LDA r_c0
  JSR rs_put
.e0
  LDA rs_t3               \ the first boundary: right, from the left end's
  CMP rs_t0               \ new place on, in segment 0's colour; left, up to
  BEQ e1                  \ the second's, in 1's
  BCC l1
  LDX rs_t0
  CPX r_nl
  BCS k2
  LDX r_nl
.k2
  CPX rs_t3
  BCS e1
  DEC A
  TAY
  LDA r_c0
  JSR rs_put
  BRA e1
.l1
  LDA rs_t0
  CMP rs_t4
  BCC k3
  LDA rs_t4
.k3
  CMP rs_t3
  BEQ e1
  TAY
  DEY
  LDX rs_t3
  LDA r_c1
  JSR rs_put
.e1
  LDA rs_t4               \ the second: right, from the first's new place on,
  CMP rs_t1               \ in 1's; left, up to the third's, in 2's (0's)
  BEQ e2
  BCC l2
  LDX rs_t1
  CPX rs_t3
  BCS k4
  LDX rs_t3
.k4
  CPX rs_t4
  BCS e2
  DEC A
  TAY
  LDA r_c1
  JSR rs_put
  BRA e2
.l2
  LDA rs_t1
  CMP rs_t5
  BCC k5
  LDA rs_t5
.k5
  CMP rs_t4
  BEQ e2
  TAY
  DEY
  LDX rs_t4
  LDA r_c0
  JSR rs_put
.e2
  LDA rs_t5               \ the third: right, from the second's new place
  CMP rs_t2               \ on, in 2's (0's); left, up to the end's, in 3's
  BEQ e3                  \ (1's)
  BCC l3
  LDX rs_t2
  CPX rs_t4
  BCS k6
  LDX rs_t4
.k6
  CPX rs_t5
  BCS e3
  DEC A
  TAY
  LDA r_c0
  JSR rs_put
  BRA e3
.l3
  LDA rs_t2
  CMP r_ne
  BCC k7
  LDA r_ne
.k7
  CMP rs_t5
  BEQ e3
  TAY
  DEY
  LDX rs_t5
  LDA r_c1
  JSR rs_put
.e3
  LDA r_ne                \ the end after the right end: right, from the
  CMP r_oe                \ third's new place on, in 3's (1's); left, black
  BEQ x
  BCC l4
  LDX r_oe
  CPX rs_t5
  BCS k8
  LDX rs_t5
.k8
  CPX r_ne
  BCS x
  DEC A
  TAY
  LDA r_c1
  JSR rs_put
  BRA x
.l4
  LDY r_oe
  DEY
  TAX
  LDA #0
  JSR rs_put
.x
}
