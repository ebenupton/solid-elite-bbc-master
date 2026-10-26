\ ============================================================================
\ raster_disc.asm -- the rasteriser's disc window: R_DISCROWS and the dirty
\ repair outside the disc rows (r7_crep, from bank 7), then R_INIT and
\ R_RESETBUF, in bank 5's &8000-&8FFF (ROMSEL 5; bank 5's &9000-&BFFF, the
\ shared region gfx-raster.asm, is the rest of the bank).  The frame layer's
\ T_DISCROWS, T_INIT and T_RESETBUF page it in.  INCLUDE it at &8000 in bank 5's assembly, after
\ gfx-raster.asm.
\ ============================================================================

\ ============================================================================
\ R_DISCROWS
\ ============================================================================
.R_DISCROWS
{
  LDA R_NDT
  CMP R_CT
  BCS t1
  LDA R_CT
.t1
  STA R_PRNT
  LDA R_NDB
  CMP R_CB
  BCC t2
  LDA R_CB
.t2
  STA R_PRNB
  CMP R_PRNT
  BCS t3
  LDA #&FF
  STA R_PRNT
  STZ R_PRNB
.t3
  JSR r_wclear            \ clear last frame's WL/WR rows
  LDA #&FF
  STA R_PRWT
  STZ R_PRWB
  \ lo..hi = old disc rows + dirty rows + new disc rows
  LDX R_PRBUF
  LDA R_PRDST,X
  CMP R_PRDYT,X
  BCC t4
  LDA R_PRDYT,X
.t4
  CMP R_PRNT
  BCC t5
  LDA R_PRNT
.t5
  STA R_PRLO
  LDA R_PRDSB,X
  CMP R_PRDYB,X
  BCS t6
  LDA R_PRDYB,X
.t6
  CMP R_PRNB
  BCS t7
  LDA R_PRNB
.t7
  STA R_PRHI
  LDA R_PRDYT,X             \ dirty rows (for the loop split)
  STA R_PRDYA
  LDA R_PRDYB,X
  STA R_PRDYZ
  JSR r_crep5             \ dirty rows that are no disc rows: bank 7
  LDA R_PRNT
  STA R_PRDST,X
  LDA R_PRNB
  STA R_PRDSB,X
  LDA #&FF
  STA R_PRDYT,X
  STZ R_PRDYB,X
  LDA R_PRHI
  CMP R_PRLO
  BCS go
  JMP stars
.go
  \ rows of lo..hi outside nt..nb: new = empty
  LDX R_PRHI
  INX
  STX RZ_T0               \ hi + 1
  LDA R_PRNT                \ lo .. min(nt, hi+1) - 1
  CMP RZ_T0
  BCC pa
  LDA RZ_T0
.pa
  STA pe1+1
  LDX R_PRLO
  CPX pe1+1
  BCS pb
  LDA #&FF
.pf1
  STA R_NDISCL,X
  STZ R_NDISCR,X
  INX
.pe1
  CPX #0
  BNE pf1
.pb
  LDA R_PRNT                \ no new disc: done
  CMP #&FF
  BEQ pf5
  LDX R_PRNB                \ max(nb+1, lo) .. hi
  INX
  CPX R_PRLO
  BCS pc
  LDX R_PRLO
.pc
  CPX RZ_T0
  BCS pf5
  LDA RZ_T0
  STA pe2+1
  LDA #&FF
.pf4
  STA R_NDISCL,X
  STZ R_NDISCR,X
  INX
.pe2
  CPX #0
  BNE pf4
.pf5
  LDX R_PRBUF               \ boundaries this frame or last time: r_dbm
  LDA R_NDF
  ORA R_PRBMODE,X
  BEQ plain
  JMP r_dbm
.plain
  \ split lo..hi at the dirty rows: A-loop (no dirty) / B-loop
  LDA R_PRDYZ
  CMP R_PRDYA
  BCC alla                \ no dirty rows
  LDA R_PRDYA               \ clip the dirty rows to lo..hi
  CMP R_PRLO
  BCS s1
  LDA R_PRLO
  STA R_PRDYA
.s1
  LDA R_PRDYZ
  CMP R_PRHI
  BCC s2
  LDA R_PRHI
  STA R_PRDYZ
.s2
  LDX R_PRLO                \ lo .. dyt-1
  LDA R_PRDYA
  JSR r_dla
  LDX R_PRDYA               \ dyt .. dyb
  LDA R_PRDYZ
  INC A
  JSR r_dlb
  LDX R_PRDYZ               \ dyb+1 .. hi
  INX
  BRA tail
.alla
  LDX R_PRLO
.tail
  LDA R_PRHI
  INC A
  JSR r_dla
.stars
.^r_dstars
  JMP r_cwb5              \ (erased stars need no WL/WR: R_STARPLOT comes last)
}



\ ============================================================================
\ Two-colour discs.  r_dbm: R_DISCROWS' rows lo..hi when this frame or this
\ buffer's last one has boundaries.
\ ============================================================================
.r_dbm
{
  LDX R_PRBUF               \ the boundary arrays' operands: patched only here
  CPX r_sbbdb             \ (two-colour discs only)
  BNE pp
  JMP pt
.pp
  STX r_sbbdb
  LDA r_sbh_bdn,X          \ group r_bdn
  STA r_pt86+2
  STA r_pt92+2
  STA r_pt102+2
  STA r_pt420+2
  STA r_pt98+2
  STA r_pt110+2
  STA r_pt130+2
  STA r_pt139+2
  STA r_pt142+2
  STA r_pt154+2
  LDA r_sbh_bdp,X          \ group r_bdp
  STA r_pt87+2
  STA r_pt91+2
  STA r_pt99+2
  STA r_pt111+2
  STA r_pt138+2
  STA r_pt141+2
  STA r_pt143+2
  STA r_pt155+2
  LDA r_sbh_bdx0,X          \ group r_bdx0
  STA r_pt93+2
  STA r_pt100+2
  STA r_pt134+2
  STA r_pt400+2
  STA r_pt401+2
  LDA r_sbh_bdx1,X          \ group r_bdx1
  STA r_pt94+2
  STA r_pt101+2
  STA r_pt135+2
  STA r_pt402+2
  STA r_pt403+2
.pt
  LDX R_PRBUF
  LDA R_PRBMODE,X           \ plain last time: its rows had no boundaries
  BNE m1
  LDX R_PRLO
.m0
.^r_pt110 STZ r_bdn,X
.^r_pt111 STZ r_bdp,X
  CPX R_PRHI
  INX
  BCC m0
  LDX R_PRBUF
.m1
  LDA R_NDF
  STA R_PRBMODE,X
  LDA #1
  STA r_bon
  LDA R_NDF               \ rows without new boundaries: count 0, colour A
  BNE z0
  LDX R_PRLO                \ (no boundaries this frame: all of lo..hi)
  LDY R_PRHI
  JSR zr
  BRA z9
.z0
  LDX R_PRLO                \ lo .. nt-1
  LDY R_PRNT
  BEQ z5
  DEY
  CPY R_PRHI
  BCC z4
  LDY R_PRHI
.z4
  JSR zr
.z5
  LDX R_PRNB                \ nb+1 .. hi
  INX
  LDY R_PRHI
  JSR zr
  BRA z9
.zr                       \ rows X .. Y (none if X > Y)
  STY zre+1
  CPX zre+1
  BEQ zl
  BCS zx
.zl
  STZ R_NDN,X
  STZ R_NDP,X
  INX
.zre
  CPX #0
  BCC zl
  BEQ zl
.zx
  RTS
.z9
  LDX R_PRLO
  LDA R_PRHI
  INC A
  JSR r_dmb
  STZ r_bon
  JMP r_dstars
}

\ r_dmb: rows X .. A-1 with boundaries: unchanged rows cost a few compares
.r_dmb
{
  STA end+1
  STX st+1
.lp
  LDA R_NDISCL,X
.^r_pt89 CMP r_sl,X
  BNE ch
  LDA R_NDISCR,X
.^r_pt90 CMP r_sr,X
  BNE ch
  LDA R_NDP,X             \ (R_NDP and r_bdp only ever hold 0 or 1)
.^r_pt91 CMP r_bdp,X
  BNE ch
  LDA R_NDN,X             \ (no boundaries, the usual case: no TAY/BEQ)
  BNE nz
.^r_pt420 CMP r_bdn,X     \ (A = 0; patched with r_pt92)
  BNE ch
.sm
.^r_pt88 LDA r_dl,X       \ unchanged: dirty? then repaint only the dirty part
  INC A
  BNE smd
.nx
  INX
.end
  CPX #0
  BNE lp
  DEX                     \ rows st .. end-1 may have WL/WR (r_dq leaves
  CPX R_PRWB                \ R_PRWT/R_PRWB to this)
  BCC e1
  STX R_PRWB
.e1
.st
  LDX #0
  CPX R_PRWT
  BCS e2
  STX R_PRWT
.e2
  RTS
.smd
  JMP r_smx               \ (r_smx: in page &8E's spare bytes)
  EQUB 0, 0
.ch                       \ (here, in the loop's page: the BNE ch's and
.^r_pt409 LDA r_dl,X      \ BRA nx below take no page-crossing cycle)
  INC A
  BNE gd                  \ dirty
  JSR r_dpe
  LDX RZ_Y
  BRA nx
.nz                       \ 1..4 boundaries (the stored count: 1..2, or &80)
.^r_pt92 CMP r_bdn,X
  BNE ch
  TAY
  LDA R_NDX0,X
.^r_pt93 CMP r_bdx0,X
  BNE chb
  DEY
  BEQ sm
  LDA R_NDX1,X
.^r_pt94 CMP r_bdx1,X
  BEQ sm
.chb
.^r_pt408 LDA r_dl,X
  INC A
  BNE gd                  \ dirty
  JMP r_dq
.^r_dmbx
  LDX RZ_Y
  BRA nx
.gd
.^r_dmgd
  TXA
  TAY
  LDA R_NDISCL,Y
.^r_pt97 AND r_sl,Y
  INC A
  BNE gg
.^r_gd1
  STZ r_dsub
  JSR r_dp1               \ no disc, old or new: black the dirty extent
  LDX RZ_Y
  BRA nx
.gg
  JSR r_drg
  LDX RZ_Y
  JMP nx                  \ (out of BRA range; JMP is 3 cycles too)
}






\ r_dq: X = row of a two-colour disc whose span, colour and boundary count
\ are unchanged (no dirty): each moved boundary's strip (old .. new) is
\ written in the colour on the side it moved from.  Strips out of order:
\ r_drg (a full repaint; partial writes are harmless).
.r_dq
{
  STX RZ_Y
  TXA                     \ row pointers
  AND #7
  STA RZ_PA
  STA RZ_PB
  TXA
  LSR A
  LSR A
  AND #&FE
  ORA #&40
  STA RZ_PA+1
  INC A
  STA RZ_PB+1
  TXA                     \ colours: T2 even segments, T1 odd
  LSR A
  BCS od
  LDA R_DCE
  LDY R_DBE
  BRA ev
.od
  LDA R_DCO
  LDY R_DBO
.ev
  STA RZ_T2
  STY RZ_T1
  LDA R_NDP,X
  LSR A
  BCC np
  LDA RZ_T2
  STY RZ_T2
  STA RZ_T1
.np
  LDA R_NDN,X
  STA RZ_T5
.^r_pt399 LDA r_sl,X
  INC A
  STA RZ_T6               \ strips must start at or after this
  STZ RZ_T4               \ extent of the writes (none)
  STZ RZ_T3
  DEC RZ_T5               \ boundary 0
  BMI done0
.^r_pt400 LDY r_bdx0,X      \ Y = old, A = new
  STY RZ_T0
  LDA R_NDX0,X
  CMP RZ_T0
  BEQ s0
.^r_pt401 STA r_bdx0,X
  BCC l0
  CPY RZ_T6               \ moved right: old .. new-1 in the colour left of it
  BCC g0
  STA RZ_T6
  DEC A
  TAY
  LDX RZ_T0
  STY RZ_T3               \ (extent of the writes)
  LDA RZ_T4
  BNE r0
  STX RZ_T4
.r0
  LDA RZ_T2
  JSR r_sw
  LDX RZ_Y
  BRA n0
.l0
  CMP RZ_T6               \ moved left: new .. old-1 in the colour right of it
  BCC g0
  STY RZ_T6
  DEY
  TAX
  STY RZ_T3
  LDA RZ_T4
  BNE q0
  STX RZ_T4
.q0
  LDA RZ_T1
  JSR r_sw
  LDX RZ_Y
  BRA n0
.s0
  STA RZ_T6               \ unmoved: the next strip starts after it
  BRA n0
.done0
  JMP done
.g0
  JMP gen
.n0
  DEC RZ_T5               \ boundary 1
  BMI done1
.^r_pt402 LDY r_bdx1,X      \ Y = old, A = new
  STY RZ_T0
  LDA R_NDX1,X
  CMP RZ_T0
  BEQ s1
.^r_pt403 STA r_bdx1,X
  BCC l1
  CPY RZ_T6               \ moved right: old .. new-1 in the colour left of it
  BCC g1
  STA RZ_T6
  DEC A
  TAY
  LDX RZ_T0
  STY RZ_T3               \ (extent of the writes)
  LDA RZ_T4
  BNE r1
  STX RZ_T4
.r1
  LDA RZ_T1
  JSR r_sw
  LDX RZ_Y
  BRA n1
.l1
  CMP RZ_T6               \ moved left: new .. old-1 in the colour right of it
  BCC g1
  STY RZ_T6
  DEY
  TAX
  STY RZ_T3
  LDA RZ_T4
  BNE q1
  STX RZ_T4
.q1
  LDA RZ_T2
  JSR r_sw
  LDX RZ_Y
  BRA n1
.s1
  STA RZ_T6               \ unmoved: the next strip starts after it
  BRA n1
.done1
  JMP done
.g1
  JMP gen
.n1
.done
  LDY RZ_Y
  LDA RZ_T3
  BEQ none
  STA R_WR,Y
  LDA RZ_T4
  STA R_WL,Y
.none
  JMP r_dmbx
.gen
  LDY RZ_Y
  JSR r_drg
  JMP r_dmbx
}

\ r_sw: pixels X .. Y (X <= Y) of the row (RZ_PA/RZ_PB set) in colour A.
\ Clobbers A, X, Y, RZ_COL, RZ_SA, RZ_SA+1, RZ_T7.
\ (.cross sits before the entry so that BMI hx lies in the same page as hx.)
{
.cross
  STX RZ_SB
  STY RZ_TA+1
  JMP r_lput2
.^r_sw
  STA RZ_COL
  STY RZ_SA
  TXA
  BMI hx                  \ X >= &80, so Y >= &80 too (X <= Y)
  EOR RZ_SA
  BMI cross               \ X in columns 0..31, Y in 32..63
  CMP #4
  BCC oa                  \ one byte, columns 0..31 (the rarer case: the
                          \ commoner multi-byte case falls through)
.ma
  LDA r_xo,Y              \ both in columns 0..31
  STA RZ_SA+1
  LDY r_xo,X
  LDA RZ_COL
  EOR (RZ_PA),Y
  AND r_lm,X
  LDX RZ_COL              \ X = colour from here to .lsa (C kept)
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  TYA
  ADC #7                  \ (C = 1 from the CMP: + 8)
  TAY
  TXA                     \ A = colour (C kept)
  CPY RZ_SA+1
  BCS lsa
.la
  STA (RZ_PA),Y
  TYA
  ADC #8                  \ (C = 0 from the CPY)
  TAY
  TXA
  CPY RZ_SA+1
  BCC la
.lsa
  LDX RZ_SA
  EOR (RZ_PA),Y
  AND r_rm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  RTS
.hx
  EOR RZ_SA
  CMP #4
  BCC ob                  \ one byte, columns 32..63
.mb
  LDA r_xo,Y              \ both in columns 32..63
  STA RZ_SA+1
  LDY r_xo,X
  LDA RZ_COL
  EOR (RZ_PB),Y
  AND r_lm,X
  LDX RZ_COL              \ X = colour from here to .lsb (C kept)
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  TYA
  ADC #7                  \ (C = 1 from the CMP: + 8)
  TAY
  CPY RZ_SA+1
  BCS lsb
.lb                       \ (unrolled twice: saves a taken branch per pair; .la
                          \ is not unrolled, as BCC oa would go out of range)
  TXA
  STA (RZ_PB),Y
  TYA
  ADC #8                  \ (C = 0 from the CPY)
  TAY
  CPY RZ_SA+1
  BCS lsb
  TXA
  STA (RZ_PB),Y
  TYA
  ADC #8                  \ (C = 0 from the CPY)
  TAY
  CPY RZ_SA+1
  BCC lb
.lsb
  TXA
  LDX RZ_SA
  EOR (RZ_PB),Y
  AND r_rm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  RTS
.oa
  LDY r_xo,X              \ one byte, columns 0..31
  LDA RZ_COL
  EOR (RZ_PA),Y
  AND r_lm,X
  LDX RZ_SA
  AND r_rm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  RTS
.ob
  LDY r_xo,X              \ one byte, columns 32..63
  LDA RZ_COL
  EOR (RZ_PB),Y
  AND r_lm,X
  LDX RZ_SA
  AND r_rm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  RTS
}




\ ============================================================================
\ r_dpe: X = row of a two-colour disc, no dirty, changed.  The row is a list
\ of edges, each with an old and a new position: the span's left end, the
\ boundaries, the end after its right end.  When old and new have the same
\ boundary count and left colour and each edge's strip (old .. new) lies
\ before the next edge's, only the strips are written (masked): pixels
\ outside them keep their colour.  Relies on boundaries being inside their
\ span.  Otherwise r_drg (a full repaint).
\ ============================================================================
.r_dpeg
  JMP r_dpgl
.r_dpe
{
  STX RZ_Y
.^r_pt132 LDA r_sl,X
  CMP #&FF
  BEQ r_dpeg
  LDA R_NDN,X             \ (early out: counts differing by 2 or more, or
                          \ the same count with the colour flipped)
.^r_pt154 SBC r_bdn,X     \ C = 0 (r_sl < &FF): A = new - old - 1
  INC A                   \ A = new count - old count
  BNE ne
  LDA R_NDP,X             \ (R_NDP and r_bdp only ever hold 0 or 1)
.^r_pt155 CMP r_bdp,X     \ (CMP, not EOR: A keeps R_NDP; C is dead here)
  BNE r_dpeg
  ORA R_NDN,X             \ no boundaries, old or new, and colour A (R_DCE /
  BNE e9                  \ R_DCO) both times: a one-colour row, which r_dp2
  JMP r_dp2+2             \ does in less time (the stored boundaries, count 0,
                          \ are never read; RZ_Y = X already: skip STX)
.ne
  INC A                   \ A = difference + 1: 0 or 2 (counts differing by
  CMP #3                  \ 1 either way) go on, the rest to r_dpgl
  BCS r_dpeg
.e9
.^r_pt131 LDA r_sl,X
  STA r_ev+7              \ old left end
  LDA R_NDISCL,X          \ new left end (clamped to the window)
  CMP R_CL
  BCS e0
  LDA R_CL
.e0
  STA r_ev
  LDA R_NDX0,X            \ boundaries: new at r_ev+1, old at r_ev+8
  STA r_ev+1
  LDA R_NDX1,X
  STA r_ev+2
  LDA R_NDX2,X            \ (the third: one more than the two stored; a
  STA r_ev+3              \ fourth never gets here, see CMP #4 below)
.^r_pt134 LDA r_bdx0,X
  STA r_ev+8
.^r_pt135 LDA r_bdx1,X
  STA r_ev+9
  LDA R_NDP,X
  AND #1
  STA r_np                \ (the colour at the left end, both sides)
  LDA R_NDN,X             \ (four or more: the counts differ by two or more,
  CMP #4                  \ as at most two are stored, and the early out has
  BCS gen0                \ sent the row to r_dpgl already)
  STA r_cn
.^r_pt130 CMP r_bdn,X
  BEQ same
  BCC fewer
  SBC #1                  \ one more boundary than before
  LDA R_NDP,X
.^r_pt138 EOR r_bdp,X
  LSR A
  BCS moreL
.^r_pt139 LDA r_bdn,X     \ it came in at the right: old gets one at oR+1
  TAY
.^r_pt140 LDA r_sr,X
  INC A
  STA r_ev+8,Y
  BRA ends
.moreL
  LDY #3                  \ it came in at the left: old gets one at oL
.ml
  LDA r_ev+8,Y
  STA r_ev+9,Y
  DEY
  BPL ml
  LDA r_ev+7
  STA r_ev+8
  BRA ends
.same
  LDA R_NDP,X
.^r_pt141 EOR r_bdp,X
  LSR A
  BCC ends
.gen0
  JMP r_dpeg
.fewer
  INC A                   \ one fewer:
.^r_pt142 CMP r_bdn,X
  BNE gen0
  STA r_cn
  LDA R_NDP,X
.^r_pt143 EOR r_bdp,X
  LSR A
  BCS fewL
  LDY r_cn                \ it left at the right: new gets one at nR+1
  LDA R_NDISCR,X
  CMP R_CR
  BCC f1
  LDA R_CR
.f1
  INC A
  STA r_ev,Y
  BRA ends
.fewL
  LDA r_np                \ it left at the left: new gets one at nL, and
  EOR #1                  \ the left colour is the old one
  STA r_np
  LDY #3
.fl
  LDA r_ev+1,Y
  STA r_ev+2,Y
  DEY
  BPL fl
  LDA r_ev
  STA r_ev+1
.ends
  LDY r_cn
  INY                     \ Y = index of the right end (after them)
  LDA R_NDISCR,X          \ new right end (clamped)
  CMP R_CR
  BCC e1
  LDA R_CR
.e1
  CMP r_ev
  BCC gen
  INC A
  STA r_ev,Y
.^r_pt133 LDA r_sr,X
  INC A
  STA r_ev+7,Y
  STY r_ns                \ edges - 1
  LDA r_ev,Y              \ old and new spans apart (a gap between them): the
  CMP r_ev+7              \ strips would write into the gap, which r_drg (the
  BCC gen                 \ fallback after a partial write) doesn't cover
  LDA r_ev+7,Y
  CMP r_ev
  BCC gen
  TXA                     \ row pointers, colours
  AND #7
  STA RZ_PA
  STA RZ_PB
  TXA
  LSR A
  LSR A
  AND #&FE
  ORA #&40
  STA RZ_PA+1
  INC A
  STA RZ_PB+1
  TXA
  TAY
  JSR r_bcols
  LDA #&FF
  STA r_wmin
  STZ r_wmax
  STZ RZ_T6               \ strips must start at or after this (in order;
  LDY #0                  \ else r_dpeg: partial writes are harmless)
.st
  STY r_cl
  LDA r_ev+7,Y
  STA RZ_T0
  LDA r_ev,Y
  CMP RZ_T0
  BEQ eq
  BCC lt
  LDX RZ_T0               \ moved right: old .. new-1 take the colour left
  CPX RZ_T6               \ of the edge (X = the strip's left end)
  BCC gen
  STA RZ_T6
  DEY                     \ (colour index edge-1; the left end: black)
  TYA                     \ colour index Y: -1 black, else P EOR (Y AND 1)
  BPL cx                  \ (Y <= 6 otherwise: at most 7 edges)
.blk
  LDA #0                  \ black (the left end here; the right end from .lt)
  BRA c2
.eq
  CMP RZ_T6
  BCC gen
  STA RZ_T6
  BRA nx
.gen
  JMP r_dpeg
.lt
  CMP RZ_T6               \ moved left: new .. old-1 take the colour right
  BCC gen                 \ of the edge (the right end: black)
  TAX                     \ X = the strip's left end
  LDA RZ_T0
  STA RZ_T6
  TYA                     \ colour index Y (0..r_ns here)
  CPY r_ns
  BEQ blk
.cx
  EOR r_np
  LSR A
  LDA r_cA
  BCC c2
  LDA r_cB
.c2
  LDY RZ_T6               \ Y = right end (RZ_T6 - 1); X kept from above;
  DEY                     \ r_sw sets RZ_COL from A
  CPX r_wmin
  BCS c3
  STX r_wmin
.c3
  STY r_wmax              \ (strips run left to right: each right end is the max)
  JSR r_sw
.nx
  LDY r_cl
  CPY r_ns                \ (r_cl <= r_ns <= 7: no wrap at INY)
  INY
  BCC st
  LDX RZ_Y                \ remember the new row
  LDA r_ev
.^r_pt144 STA r_sl,X
  LDY r_ns
  LDA r_ev,Y
  DEC A
.^r_pt145 STA r_sr,X
  TXA
  TAY
  JSR r_bstore
  LDX RZ_Y
  TXA
  TAY
  LDA r_wmax
  BEQ none
  STA R_WR,Y
  LDA r_wmin
  STA R_WL,Y
  CPY R_PRWT
  BCS wz
  STY R_PRWT
.wz
  STY R_PRWB
.none
  RTS
}

\ r_dpgl: r_dpe's fallback (row RZ_Y, not dirty)
.r_dpgl
{
  LDY RZ_Y                \ not dirty: if the span did not shrink, repaint
.^r_pt150 LDA r_sl,Y        \ the new one segment by segment (no black)
  CMP #&FF
  BEQ none                \ (no old span: likewise, the row is black)
  STA r_oL
  LDA R_NDISCL,Y
  CMP R_CL
  BCS l1
  LDA R_CL
.l1
  CMP r_oL
  BEQ l2
  BCS full
.l2
  STA r_nL
  LDA R_NDISCR,Y
  CMP R_CR
  BCC r1
  LDA R_CR
.r1
  STA r_nR
.^r_pt151 CMP r_sr,Y
  BCC full
.paint
  LDA r_nR
  CMP r_nL
  BCC full
  JSR r_rowset
  JSR r_bcols
  LDA #&FF
  STA r_wmin
  STZ r_wmax
  JSR r_segw
  LDY RZ_Y
  LDA r_nL
.^r_pt152 STA r_sl,Y
  LDA r_nR
.^r_pt153 STA r_sr,Y
  JSR r_bstore
  LDA r_wmax
  BEQ x
  STA R_WR,Y
  LDA r_wmin
  STA R_WL,Y
.x
  RTS
.full
  JMP r_drg
.none
  LDA R_NDISCL,Y
  CMP R_CL
  BCS l3
  LDA R_CL
.l3
  STA r_nL
  LDA R_NDISCR,Y
  CMP R_CR
  BCC r3
  LDA R_CR
.r3
  STA r_nR
  BRA paint
}

\ r_segw: r_drg with boundaries: the whole new span r_nL..r_nR, segment by
\ segment in colours A / B (row RZ_Y, r_cA/r_cB set)
.r_segw
{
  LDA r_nR
  CMP r_nL
  BCS go
  RTS
.go
  LDY RZ_Y
  LDA R_NDN,Y
  CMP #5
  BCC s1
  LDA #4
.s1
  STA r_cn
  LDA R_NDX0,Y
  STA r_bv
  LDA R_NDX1,Y
  STA r_bv+1
  LDA R_NDX2,Y
  STA r_bv+2
  LDA R_NDX3,Y
  STA r_bv+3
  LDA R_NDP,Y
  AND #1
  STA r_np                \ colour now
  LDA r_nL
  STA r_ba                \ segment start
  LDX #0
.lp
  CPX r_cn
  BCS last
  LDA r_bv,X
  CMP r_nL
  BEQ flip
  BCC flip
  CMP r_nR
  BEQ s2
  BCS last
.s2
  CMP r_ba
  BEQ flip                \ empty segment
  STX r_nn
  DEC A
  TAX
  JSR seg
  LDX r_nn
  LDA r_bv,X
  STA r_ba
.flip
  LDA r_np
  EOR #1
  STA r_np
  INX
  BRA lp
.last
  LDX r_nR
.seg                      \ r_ba .. X in colour r_np
  LDA r_np
  LSR A
  LDA r_cA
  BCC c1
  LDA r_cB
.c1
  STA RZ_COL
  LDA r_ba
  JMP r_dw
}

\ r_dp1: Y = row with dirty extent and no disc (old or new)


\ ============================================================================
\ r_wclear: R_WR[R_PRWT .. R_PRWB] = 0, in blocks of 8 rows from (R_PRWB OR 7) down
\ to (R_PRWT AND &F8): the rows of those blocks outside R_PRWT..R_PRWB are 0
\ already.  Clobbers A, X.
\ ============================================================================
.r_wclear
{
  LDA R_PRWB
  CMP R_PRWT
  BCC none
  ORA #7
  TAX
  LDA R_PRWT
  AND #&F8
  STA lim+1
.lp
  STZ R_WR,X
  STZ R_WR-1,X
  STZ R_WR-2,X
  STZ R_WR-3,X
  STZ R_WR-4,X
  STZ R_WR-5,X
  STZ R_WR-6,X
  STZ R_WR-7,X
  TXA
  SEC
  SBC #8
  BCC none
  TAX
.lim
  CMP #0
  BCS lp
.none
  RTS
}

\ r_dla: rows X .. A-1 with no dirty extent.  r_dlb: rows X .. A-1, any.
.r_dla
{
  STA end+1
  STA end2+1              \ the changed-row tail's own copy of the end test
  CPX end+1
  BCS done
.lp
  LDA R_NDISCL,X
.^r_pt26 CMP r_sl,X
  BNE ch
  LDA R_NDISCR,X
.^r_pt27 CMP r_sr,X
  BNE ch
  INX
.end
  CPX #0
  BNE lp
.done
  RTS
.ch
  JSR r_dp2               \ (returns X = RZ_Y)
  INX
.end2
  CPX #0
  BNE lp
  RTS
}

.r_dlb
{
  STA end+1
  CPX end+1
  BCS done
.lp
.^r_pt25 LDA r_dl,X
  INC A
  BNE gd                  \ dirty
  LDA R_NDISCL,X
.^r_pt54 CMP r_sl,X
  BNE ch
  LDA R_NDISCR,X
.^r_pt55 CMP r_sr,X
  BNE ch
.nx
  INX
.end
  CPX #0
  BNE lp
.done
  RTS
.ch
  JSR r_dp2               \ (returns X = RZ_Y)
  BRA nx
.gd
  TXA
  TAY
  LDA R_NDISCL,Y
.^r_pt45 AND r_sl,Y
  INC A
  BNE gg
  JSR r_dp1               \ no disc, old or new: black the dirty extent
  LDX RZ_Y
  BRA nx
.gg
  JSR r_drg
  LDX RZ_Y
  BRA nx
}

\ r_dp2: X = row, dirty empty, disc changed (one colour, R_DCE / R_DCO by
\ row parity).  The old span is intact, so only the difference between it
\ and the new one is written: pixels in the new span but not the old take
\ the disc colour, pixels in the old but not the new go black, each piece by
\ r_sw (masked at its end bytes, so the pieces can share bytes, and the
\ window's border columns keep their pixels).  At most two pieces: the two
\ ends' strips when the spans overlap, else the old span and the new one.
\ R_WL/R_WR = the bytes written (none: left as they are).
.r_dp2
{
  STX RZ_Y
  TXA                     \ row pointers
  AND #7
  STA RZ_PA
  STA RZ_PB
  LDA r_ypg,X
  STA RZ_PA+1
  INC A
  STA RZ_PB+1
.^r_pt50 LDA r_sl,X
  STA RZ_T0               \ oL
.^r_pt51 LDY r_sr,X       \ (Y = oR kept until the TYA below; emp leaves Y alone)
  STY RZ_T1               \ oR
  LDA R_NDISCL,X          \ nL, nR: clamped to the window (empty: 255, 0)
  CMP R_CL
  BCS c0
  LDA R_CL
.c0
  STA RZ_T2
.^r_pt53 STA r_sl,X       \ (before r_sr: nothing reads either in between)
  LDA R_NDISCR,X
  CMP R_CR
  BCC c1
  LDA R_CR
.c1
  CMP RZ_T2
  BCC emp                 \ nR < nL: empty (out of line)
.c1b
  STA RZ_T3
.^r_pt52 STA r_sr,X
  TYA                     \ old empty: the new span (A = oR)
  BCC empd                \ (C clear: from emp, the new span empty)
  CMP RZ_T0
  BCC jonew
  CMP RZ_T2               \ (nR >= nL here: the new span is not empty)
  BCC jboth               \ apart (oR < nL or nR < oL): both
.ovl
  LDA RZ_T2               \ overlapping: the left end (R_WL/R_WR noted here,
  CMP RZ_T0               \ the left end's strip before the right end's)
  BEQ requal              \ (nL >= oL: nR >= nL >= oL, so not apart)
  BCS lshr
  LDY RZ_T0               \ nL < oL: apart if nR < oL, i.e. oL-1 >= nR
  DEY
  CPY RZ_T3
  BCS jboth
  AND #&FC                \ grown: nL .. oL-1 in the disc colour
  STA r_wmin
  TYA
  ORA #3
  STA R_WR,X              \ R_WR: the left end's bytes (the right end's strip, if
  TXA                     \ any, overwrites it) (X = RZ_Y; the row's disc colour:
                          \ R_DCE / R_DCO by parity)
  AND #1
  TAX
  LDA R_DCE,X
  LDX RZ_T2
  JSR r_sw
  BRA right
.jboth
  JMP both
.jonew
  JMP onew0
.empd                     \ new empty (A = oR): old empty too: onew0, else
  CMP RZ_T0               \ the old span black
  BCC jonew
  LDA RZ_T0               \ (as oblk: X = oL, r_wmin = oL AND &FC, then
  BRA rqs1                \ .rshr2: Y = oR, R_WR = oR OR 3, black)
.emp
  LDA r_pt53+2            \ (r_sl's current page, as R_SETBUF patched it)
  STA es+2
  LDA #&FF                \ empty new span: (255, 0)
  STA RZ_T2
.es
  STA r_sl,X              \ (nopatch: its page is copied from r_pt53+2 just above)
  INC A                   \ (A = 0, C clear: BCC emp)
  BRA c1b
.requal                   \ left ends equal: r_wmin from the right end's strip
  LDA RZ_T3
  CMP RZ_T1
  BEQ none                \ same span: nothing written (X = RZ_Y)
  BCC rqs
  LDA RZ_T1               \ grown: r_wmin = (oR + 1) AND &FC
  INC A
  AND #&FC
  STA r_wmin
  LDA RZ_T3
  BRA rgr
.rqs                      \ shrunk: r_wmin = (nR + 1) AND &FC, X = nR + 1
  INC A
.rqs1                     \ (entered here from .empd with A = oL)
  TAX
  AND #&FC
  STA r_wmin
  BRA rshr2
.lshr
  DEC A                   \ shrunk: oL .. nL-1 black
  TAY
  ORA #3
  STA R_WR,X              \ (X = RZ_Y: R_WR as above)
  LDA RZ_T0
  TAX
  AND #&FC
  STA r_wmin
  STZ RZ_COL              \ (black)
  JSR r_sw+2              \ past r_sw's STA RZ_COL
.right                    \ (r_wmin and R_WR already set by the left end's strip)
  LDA RZ_T3
  CMP RZ_T1
  BEQ fin
  BCS rgr
.rshr
  INC A                   \ shrunk: nR+1 .. oR black
  TAX
.rshr2                    \ (entered here from .rqs1 with X = nR+1 or oL)
  LDY RZ_T1
  STZ RZ_COL
  JSR r_sw+2              \ past r_sw's STA RZ_COL (black)
  LDX RZ_Y
  LDA RZ_T1               \ R_WR: the bytes written
  ORA #3
.wr
  STA R_WR,X
  BRA fin2
.rgr
  TAY                     \ (Y = nR for r_sw)
  ORA #3                  \ grown: oR+1 .. nR in the disc colour
  LDX RZ_Y
  STA R_WR,X              \ R_WR: the bytes written (the right end's strip is the max)
  TXA                     \ the row's disc colour
  AND #1
  TAX
  LDA R_DCE,X
  LDX RZ_T1
  INX
  JSR r_sw
.fin                      \ (R_WR set and a strip written on every path here)
  LDX RZ_Y                \ (X = RZ_Y on return: r_dla/r_dlb rely on it)
.fin2
  LDA r_wmin              \ R_WL: the bytes written
  STA R_WL,X
  CPX R_PRWT
  BCS w1
  STX R_PRWT
.w1
  STX R_PRWB                \ rows go upwards
.none
  RTS
.onew0                    \ old span empty: nothing noted yet
  LDA #&FF
  STA r_wmin
  STZ r_wmax
  BRA onew
.both
  JSR oblk
.onew
  LDA RZ_T3
  CMP RZ_T2
  BCC none                \ both spans empty (only from onew0, X = RZ_Y still)
  TAY
  LDA RZ_Y                \ the row's disc colour
  AND #1
  TAX
  LDA R_DCE,X
  STA RZ_COL
  LDX RZ_T2
  JSR put
  LDX RZ_Y
  LDA r_wmax              \ R_WR: the bytes written (r_wmax >= 3: a strip was written)
  BRA wr
.oblk                     \ the old span black (always the first strip)
  LDA #&FF
  STA r_wmin
  STZ r_wmax
  LDX RZ_T0
  LDY RZ_T1
  STZ RZ_COL
.put                      \ pixels X .. Y in colour RZ_COL (X <= Y), noted
  TXA
  AND #&FC
  CMP r_wmin
  BCS p1
  STA r_wmin
.p1
  TYA
  ORA #3
  CMP r_wmax
  BCC p2
  STA r_wmax
.p2
  JMP r_sw+2              \ past r_sw's STA RZ_COL (RZ_COL already set)
}

\ r_drg: general disc row, Y = row
.r_drg
{
  JSR r_rowset
  LDA #&FF
  STA r_wmin
  STZ r_wmax
  TYA
  LSR A
  LDA R_DCE
  BCC e
  LDA R_DCO
.e
  STA r_dcol
  STZ r_segs
  LDA r_bon
  BEQ dn
  JSR r_bcols             \ boundaries: plain only if none, old and new,
  LDA R_NDN,Y             \ and the same colour
.^r_pt86 ORA r_bdn,Y
  BNE sg
  LDA R_NDP,Y
.^r_pt87 EOR r_bdp,Y
  LSR A
  BCS sg
  LDA R_NDP,Y
  LSR A
  LDA r_cA
  BCC sg1
  LDA r_cB
.sg1
  STA r_dcol
  BRA dn
.sg
  INC r_segs
.dn
.^r_pt17 LDA r_sl,Y
  STA r_oL
.^r_pt18 LDA r_sr,Y
  STA r_oR
.^r_pt19 LDA r_dl,Y
  STA r_dL
.^r_pt20 LDA r_dr,Y
  STA r_dR
  LDA R_NDISCL,Y
  CMP R_CL
  BCS n1
  LDA R_CL
.n1
  STA r_nL
  LDA R_NDISCR,Y
  CMP R_CR
  BCC n2
  LDA R_CR
.n2
  STA r_nR
  CMP r_nL
  BCS n3
  LDA #&FF
  STA r_nL
  STZ r_nR
.n3
.gen1
  \ intact = old - dirty (the larger piece)
  LDA r_oR
  CMP r_oL
  BCC iempty
  LDA r_dR
  CMP r_dL
  BCC iwhole
  LDA r_dR
  CMP r_oL
  BCC iwhole
  LDA r_oR
  CMP r_dL
  BCC iwhole
  LDA r_dL
  SEC
  SBC r_oL
  BCS i1
  LDA #0
.i1
  STA r_tl
  LDA r_oR
  SEC
  SBC r_dR
  BCS i2
  LDA #0
.i2
  CMP r_tl
  BEQ usel
  BCC usel
  LDX r_dR
  INX
  STX r_iL
  LDA r_oR
  STA r_iR
  BRA idone
.usel
  LDA r_tl
  BEQ iempty
  LDA r_oL
  STA r_iL
  LDX r_dL
  DEX
  STX r_iR
  BRA idone
.iwhole
  LDA r_oL
  STA r_iL
  LDA r_oR
  STA r_iR
  BRA idone
.iempty
  LDA #&FF
  STA r_iL
  STZ r_iR
.idone
  LDX r_dsub
  STZ r_dsub
  LDA r_segs
  BEQ dc0
  TXA                     \ span and boundaries unchanged (r_dmb): only the
  BEQ whole               \ dirty part of the span
  LDA r_nL
  PHA
  LDA r_nR
  PHA
  LDA r_dL
  CMP r_nL
  BCC sb1
  STA r_nL
.sb1
  LDA r_dR
  CMP r_nR
  BCS sb2
  STA r_nR
.sb2
  JSR r_segw
  PLA
  STA r_nR
  PLA
  STA r_nL
  JMP nodisc
.whole
  JSR r_segw              \ boundaries: repaint the whole new span
  JMP nodisc
.dc0
  \ disc colour on new - intact
  LDA r_nR
  CMP r_nL
  BCC nodisc
  LDA r_dcol
  STA RZ_COL
  LDA r_iR
  CMP r_iL
  BCC full
  LDA r_iR
  CMP r_nL
  BCC full
  LDA r_nR
  CMP r_iL
  BCC full
  LDA r_nL
  CMP r_iL
  BCS d2
  LDX r_iL
  DEX
  JSR r_dw
.d2
  LDA r_iR
  CMP r_nR
  BCS nodisc
  INC A
  LDX r_nR
  JSR r_dw
  BRA nodisc
.full
  LDA r_nL
  LDX r_nR
  JSR r_dw
.nodisc
  \ black on (old + dirty) - new
  STZ RZ_COL
  LDA r_oR
  CMP r_oL
  BCC oe
  LDA r_dR
  CMP r_dL
  BCC de
  LDX r_oR
  INX
  CPX r_dL
  BCC sep
  LDX r_dR
  INX
  CPX r_oL
  BCC sep
  LDA r_oL
  CMP r_dL
  BCC h1
  LDA r_dL
.h1
  STA r_ba
  LDA r_oR
  CMP r_dR
  BCS h2
  LDA r_dR
.h2
  STA r_bb
  JSR r_bmn
  BRA fin
.sep
  LDA r_dL
  STA r_ba
  LDA r_dR
  STA r_bb
  JSR r_bmn
.de
  LDA r_oL
  STA r_ba
  LDA r_oR
  STA r_bb
  JSR r_bmn
  BRA fin
.oe
  LDA r_dR
  CMP r_dL
  BCC fin
  LDA r_dL
  STA r_ba
  LDA r_dR
  STA r_bb
  JSR r_bmn
.fin
  LDY RZ_Y
  LDA r_nL
.^r_pt21 STA r_sl,Y
  LDA r_nR
.^r_pt22 STA r_sr,Y
  LDA #&FF
.^r_pt23 STA r_dl,Y
  LDA #0
.^r_pt24 STA r_dr,Y
  LDA r_bon
  BEQ nb1
  JSR r_bstore            \ remember this row's boundaries
  LDY RZ_Y
.nb1
  LDA r_wmax
  STA R_WR,Y
  BEQ nw
  LDA r_wmin
  STA R_WL,Y
  CPY R_PRWT
  BCS w1
  STY R_PRWT
.w1
  CPY R_PRWB
  BCC nw
  STY R_PRWB
.nw
  RTS
}


\ ============================================================================
\ Dirty repair outside the disc rows (R_DISCROWS calls r7_crep before its row
\ loop).  The dirty rows that are in neither this buffer's old disc rows nor
\ the new ones hold nothing but black under their dirty extents, so each such
\ row's extent, widened to whole bytes, is blacked by one row run through
\ the row runs, its R_WL/R_WR set to that and its DIRTY emptied; R_DISCROWS' row
\ loop then only visits the disc rows (R_PRLO..R_PRHI and R_PRDYA..R_PRDYZ are
\ narrowed to them).  Byte columns 0 and 63 hold the border: their bytes are
\ masked.  (Byte-column runs were measured against these row runs on a
\ capture of the game, with the same row handling either side: rows won; see
\ the columns-experiments branch.)
\ ============================================================================
c_L   = &18
c_R   = &19
c_NL  = &1A
c_YE  = &1E
c_M   = &23
c_CO  = &22
c_BT  = &24
c_BB  = &25


.r7_crep
{
  STZ R_PRCWB
  LDA R_PRDYZ
  CMP R_PRDYA
  BCC none
  LDX R_PRBUF             \ band = old disc rows + new disc rows
  LDA R_PRDST,X
  CMP R_PRNT
  BCC b1
  LDA R_PRNT
.b1
  STA c_BT
  LDA R_PRDSB,X
  CMP R_PRNB
  BCS b2
  LDA R_PRNB
.b2
  STA c_BB
  LDY R_PRDYA
  CMP c_BT
  BCS band
  LDA R_PRDYZ             \ no disc rows: all the dirty rows
  JSR rep
  LDA #&FF                \ and no disc rows to loop over
  STA R_PRLO
  STZ R_PRHI
.none
  RTS
.band
  BIT KMODE               \ K mode: the band's rows are not kept (the row
  BPL k9                  \ loop below repaints them as before)
  LDX c_BT
.k1
  LDA KF,X
  AND KBITN
  STA KF,X
  CPX c_BB
  INX
  BCC k1
  LDY R_PRDYA
.k9
  CPY c_BT                \ dya .. min(dyz, bt - 1)
  BCS p2
  LDA c_BT
  DEC A
  CMP R_PRDYZ
  BCC p1
  LDA R_PRDYZ
.p1
  JSR rep
.p2
  LDA c_BB                \ max(dya, bb + 1) .. dyz
  INC A
  BEQ nar
  TAY
  CPY R_PRDYA
  BCS p3
  LDY R_PRDYA
.p3
  LDA R_PRDYZ
  STY c_NL
  CMP c_NL
  BCC nar
  JSR rep
.nar                      \ the row loop: disc rows only
  LDA R_PRLO
  CMP c_BT
  BCS n1
  LDA c_BT
  STA R_PRLO
.n1
  LDA R_PRHI
  CMP c_BB
  BCC n2
  LDA c_BB
  STA R_PRHI
.n2
  LDA R_PRDYA
  CMP R_PRLO
  BCS n3
  LDA R_PRLO
  STA R_PRDYA
.n3
  LDA R_PRDYZ
  CMP R_PRHI
  BCC n4
  LDA R_PRHI
  STA R_PRDYZ
.n4
  LDA R_PRDYZ
  CMP R_PRDYA
  BCS n5
  LDA #&FF
  STA R_PRDYA
  STZ R_PRDYZ
.n5
  RTS
\ rep: rows Y .. A
.rep
  STA R_PRCWB
  INC A
  STA c_YE
  CPY R_PRWT
  BCS r1
  STY R_PRWT
.r1
  JMP r7_rowrep
}

\ r7_rowrep: rows Y .. c_YE - 1 (see above)
.r7_rowrep
{
  LDX R_PRBUF
  LDA dlh,X
  STA ld1+2
  STA sd1+2
  STA fl1+2
  STA fs1+2
  STA r_kd1+2
  LDA drh,X
  STA ld2+2
  STA sd2+2
  STA fl2+2
  STA fs2+2
  STA r_kd3+2
  LDA #LO(frow-fnb-2)     \ the loop: frow, or in K mode krow (kept rows:
  BIT KMODE               \ raster_kept.asm), which hands the other rows to
  BPL k0                  \ frow's body
  LDA #LO(krow-fnb-2)
.k0
  STA fnb+1
  BIT KMODE
  BMI krow
.frow                     \ fast path: extent inside columns 1..62
.fl2
  LDA R_DIRTYR0,Y
  BEQ fnx
  CMP #252
  BCS slow
  TAX
  ORA #3
  STA R_WR,Y
  LDA r_j,X             \ plant the RTS after column R DIV 4
  STA RZ_PP
.fl1
  LDA R_DIRTYL0,Y
  AND #&FC                \ L AND &FC = 0 <=> L < 4
  BEQ slow
  STA R_WL,Y
  TAX
  LDA r_j-4,X           \ enter at column L DIV 4
  STA fj+1
  LDA #&FF
.fs1
  STA R_DIRTYL0,Y
  TYA                     \ the run page of row Y
  LSR A
  LSR A
  LSR A
  ORA #HI(r_run0)         \ (= ADC: Y DIV 8 < 32)
  STA fj+2
  STA RZ_PP+1
  LDA #&60
  STA (RZ_PP)
  LDA #0
.fs2
  STA R_DIRTYR0,Y
.fj
  JSR &FFFF               \ patched: straight into the row run (the run keeps Y)
  LDA #r_opSTA
  STA (RZ_PP)
.fnx
  INY
  CPY c_YE
.fnb
  BCC frow                \ (patched: frow or krow)
  RTS
.slow                     \ an end in column 0 or 63: the general row code
  JSR row1
  BRA fnx
\ K mode (raster_kept.asm): a row kept in this buffer is left as it is,
\ pending (KF bit 7), its old extent in DIRTY and its WL/WR as if blacked;
\ the other rows go through frow's body
.krow
  LDA KF,Y
  AND KBIT
  BEQ frow
.kp
  EOR KF,Y                \ (A = KBIT) KBIT off, pending on
  ORA #&80
  STA KF,Y
  INC KREC                \ (counted for T_KFRAME)
.^r_kd3
  LDA R_DIRTYR0,Y         \ (patched) WL, WR as row1 would set them
  ORA #3
  STA R_WR,Y
.^r_kd1
  LDA R_DIRTYL0,Y         \ (patched)
  AND #&FC
  STA R_WL,Y
  CPY KPLO
  BCS kp1
  STY KPLO
.kp1
  CPY KPHI
  BCC fnx
  STY KPHI
  BRA fnx
\ row1: row Y, general (the border columns' bytes masked)
.row1
.^r_row1                  \ (raster_kept.asm's k_rows: a pending row blacked)
.ld2
  LDA R_DIRTYR0,Y
  STA c_R
  ORA #3
  STA R_WR,Y
.ld1
  LDX R_DIRTYL0,Y
  STX c_L
  TXA
  AND #&FC
  STA R_WL,Y
  LDA #&FF
.sd1
  STA R_DIRTYL0,Y
  LDA #0
.sd2
  STA R_DIRTYR0,Y
  TXA                     \ first byte column (0: the border's)
  LSR A
  LSR A
  BEQ e0
.nl1
  STA c_NL
  LDA c_R                 \ last byte column (63: the border's)
  LSR A
  LSR A
  CMP #63
  BEQ e63
.nr1
  INC A
  CMP c_NL
  BEQ nx
  BCC nx
  ASL A                   \ plant the RTS at column NR (r_jm at 4 NR: 3 (NR - 1))
  ASL A
  TAX
  LDA r_jm,X
  STA RZ_PP
  TYA                     \ the run page of row Y
  LSR A
  LSR A
  LSR A
  ORA #HI(r_run0)         \ (= ADC: Y DIV 8 < 32)
  STA RZ_PP+1
  STA rj+2
  LDA c_NL
  ASL A
  ASL A
  TAX
  LDA r_jm,X
  STA rj+1
  LDA #&60
  STA (RZ_PP)
  STY RZ_Y
  LDA #0
  JSR rj
  LDA #r_opSTA
  STA (RZ_PP)
  LDY RZ_Y
.nx
  RTS
.rj
  JMP &FFFF
.e0
  STY RZ_Y
  JSR edge0
  LDY RZ_Y
  LDA #1
  BRA nl1
.e63
  STY RZ_Y
  JSR edge63
  LDY RZ_Y
  LDA #62
  BRA nr1
\ edge0 / edge63: black pixels c_L .. c_R of row RZ_Y within column 0 / 63
.edge0
  LDX c_R
  CPX #4
  BCC e0a
  LDX #3
.e0a
  LDA r_rm,X
  LDX c_L
  AND r_lm,X
  LDX #0
  BRA eg
.edge63
  LDA c_L
  CMP #252
  BCS e6a
  LDA #252
.e6a
  AND #3
  TAX
  LDA c_R                 \ (>= 252)
  AND #3
  TAY
  LDA r_lm,X
  AND r_rm,Y
  LDX #&F8
.eg
  EOR #&FF
  STA c_M
  STX c_CO
  LDA RZ_Y
  AND #7
  ORA c_CO
  STA RZ_PA
  LDA RZ_Y
  LSR A
  LSR A
  AND #&FE
  ORA #&40
  CPX #0
  BEQ eg1
  INC A
.eg1
  STA RZ_PA+1
  LDA (RZ_PA)
  AND c_M
  STA (RZ_PA)
  RTS
.dlh EQUB HI(R_DIRTYL0), HI(R_DIRTYL1)
.drh EQUB HI(R_DIRTYR0), HI(R_DIRTYR1)
}





\ ============================================================================
\ R_INIT
\ ============================================================================
\ ============================================================================
\ R_INIT
\ ============================================================================
.R_INIT
{
  LDA #1
  STA R_CL
  STA R_CT
  LDA #254
  STA R_CR
  LDA #191
  STA R_CB
  LDA #&FF
  STA R_SCOL
  STA R_NDT
  STA R_PRWT
  STZ R_NDB
  STZ R_NDF
  STZ R_SN
  STZ R_PN
  STZ R_PRWB
  STZ R_PRBUF             \ buffer 1's state, then buffer 0's (each R_SETBUF
  LDA #1                  \ patching), ending with buffer 0
.ib
  PHA
  JSR R_SETBUF
  JSR R_RESETBUF
  PLA
  DEC A
  BPL ib
  JSR k_clear             \ no kept rows
  LDY #191
.il
  LDA #&FF
  STA R_WL,Y
  LDA #0
  STA R_WR,Y
  DEY
  CPY #&FF
  BNE il
  RTS
}






\ ============================================================================
\ R_RESETBUF: the current buffer's state, not the screen
\ ============================================================================
.R_RESETBUF
{
  LDY #191
  LDX R_PRBUF
  BNE b1
.c0
  LDA #&FF
  STA R_DIRTYL0,Y
  STA R_DISCL0,Y
  LDA #0
  STA R_DIRTYR0,Y
  STA R_DISCR0,Y
  DEY
  CPY #&FF
  BNE c0
  BRA done
.b1
  LDA #&FF
  STA R_DIRTYL1,Y
  STA R_DISCL1,Y
  LDA #0
  STA R_DIRTYR1,Y
  STA R_DISCR1,Y
  DEY
  CPY #&FF
  BNE b1
.done
  JMP r7_reset1
}
\ r7_reset1: buffer X's scalars (keeps X)
.r7_reset1
  LDA #&FF
  STA R_PRDYT,X
  STA R_PRDST,X
  STZ R_PRDYB,X
  STZ R_PRDSB,X
  STZ R_PRSCNT,X
  STZ R_PRECNT,X
  STZ R_PRBMODE,X
  RTS
