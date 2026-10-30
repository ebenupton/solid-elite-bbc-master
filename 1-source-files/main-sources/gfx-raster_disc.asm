\ ============================================================================
\ raster_disc.asm -- the rasteriser's disc window: R_DISCROWS and the dirty
\ repair outside the disc rows (r7_crep, from bank 7), in bank 5's
\ &8000-&8FFF (ROMSEL 5; bank 5's &9000-&BFFF, the shared region
\ gfx-raster.asm, is the rest of the bank).  The frame layer's T_DISCROWS
\ pages it in.  INCLUDE it at &8000 in bank 5's assembly, after
\ gfx-raster.asm.
\ ============================================================================

\ ============================================================================
\ R_DISCROWS
\ ============================================================================
.R_DISCROWS
{
  BCC t0                  \ C set: the second disc instead (f_disc2's T_DISCROWS:
  JMP R_DISC2             \ gfx-raster_disc2.asm)
.t0
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
  STA r_pt91+2
  STA r_pt102+2
  STA r_pt98+2
  STA r_pt110+2
  STA r_pt131+2
  STA r_pt154+2
  STA r_pt155+2
  STA r_pt156+2
  STA r_pt158+2
  LDA r_sbh_bdx0,X          \ group r_bdx0
  STA r_pt93+2
  STA r_pt100+2
  STA r_pt134+2
  STA r_pt138+2
  STA r_pt401+2
  STA r_pt402+2
  STA r_pt403+2
  STA r_pt407+2
  LDA r_sbh_bdx1,X          \ group r_bdx1
  STA r_pt94+2
  STA r_pt101+2
  STA r_pt135+2
  STA r_pt139+2
  STA r_pt404+2
  STA r_pt405+2
  STA r_pt406+2
  STA r_pt419+2
  LDA r_sbh_bdx2,X          \ group r_bdx2
  STA r_pt95+2
  STA r_pt103+2
  STA r_pt136+2
  STA r_pt137+2
  STA r_pt420+2
  STA r_pt421+2
  STA r_pt422+2
  STA r_pt423+2
.pt
  LDX R_PRBUF
  LDA R_PRBMODE,X           \ plain last time: its rows had no boundaries
  BNE m1
  LDX #191                \ (every row: a row with no old span has no
.m0                       \ boundaries, which r_dpe relies on)
.^r_pt110 STZ r_bdn,X
  DEX
  CPX #&FF
  BNE m0
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
  LDA R_NDN,X             \ the count and the colour, new and old
.^r_pt91 CMP r_bdn,X
  BNE ch
  ASL A                   \ (A = 2 count; no boundaries, the usual case: on)
  BNE nz
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
.nz                       \ 1 to 3 boundaries, as stored (A = 2 count; 4
  TAY                     \ are never stored: r_bstore)
  LDA R_NDX0,X
.^r_pt93 CMP r_bdx0,X
  BNE chb
  CPY #4
  BCC sm
  LDA R_NDX1,X
.^r_pt94 CMP r_bdx1,X
  BNE chb
  CPY #6
  BCC sm
  LDA R_NDX2,X
.^r_pt95 CMP r_bdx2,X
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
\ (Y = 2 count: one to three) are unchanged, no dirty, a boundary moved
\ (r_dmb): each moved boundary's strip (old .. new) in the colour on the
\ side it moved from, cut short where its neighbour's new place has passed
\ into it (as r_dpe: the span's ends stay put).  Ends at r_dmbx.
.r_dq
{
  STX RZ_Y
  STY r_cn
  TXA                     \ row pointers, the segments' colours, no writes
  AND #7
  STA RZ_PA
  STA RZ_PB
  LDA r_ypg,X
  STA RZ_PA+1
  INC A
  STA RZ_PB+1
  LDA #&FF
  STA r_wmin
  STZ r_wmax
  TXA
  AND #1
  TAY
  LDA R_NDN,X
  BMI cb
  LDA R_DCE,Y
  STA r_c0
  LDA R_DBE,Y
  STA r_c1
  BRA go
.cb
  LDA R_DBE,Y
  STA r_c0
  LDA R_DCE,Y
  STA r_c1
.go
  LDA R_NDX0,X            \ the first: moved right, old .. new-1 in segment
.^r_pt401 CMP r_bdx0,X    \ 0's colour; left, new .. old-1 (or up to the
  BEQ n0                  \ second's new place) in 1's
  BCC l0
  DEC A
  TAY
.^r_pt402 LDA r_bdx0,X
  TAX
  LDA r_c0
  JSR rs_put
  LDX RZ_Y
  BRA n0
.l0
.^r_pt403 LDA r_bdx0,X
  LDY r_cn
  CPY #4
  BCC l0b
  CMP R_NDX1,X
  BCC l0b
  LDA R_NDX1,X
.l0b
  CMP R_NDX0,X
  BEQ n0
  TAY
  DEY
  LDA R_NDX0,X
  TAX
  LDA r_c1
  JSR rs_put
  LDX RZ_Y
.n0
  LDA r_cn
  CMP #4
  BCS b1
  JMP fin
.b1
  LDA R_NDX1,X            \ the second: right, from the first's new place on,
.^r_pt404 CMP r_bdx1,X    \ in 1's; left, up to the third's, in 2's (0's)
  BEQ n1
  BCC l1
  DEC A
  TAY
.^r_pt405 LDA r_bdx1,X
  CMP R_NDX0,X
  BCS P%+5
  LDA R_NDX0,X
  CMP R_NDX1,X
  BCS n1
  TAX
  LDA r_c1
  JSR rs_put
  LDX RZ_Y
  BRA n1
.l1
.^r_pt406 LDA r_bdx1,X
  LDY r_cn
  CPY #6
  BCC l1b
  CMP R_NDX2,X
  BCC l1b
  LDA R_NDX2,X
.l1b
  CMP R_NDX1,X
  BEQ n1
  TAY
  DEY
  LDA R_NDX1,X
  TAX
  LDA r_c0
  JSR rs_put
  LDX RZ_Y
.n1
  LDA r_cn
  CMP #6
  BCC fin
  LDA R_NDX2,X            \ the third: right, from the second's new place
.^r_pt420 CMP r_bdx2,X    \ on, in 2's (0's); left, in 3's (1's)
  BEQ fin
  BCC l2
  DEC A
  TAY
.^r_pt421 LDA r_bdx2,X
  CMP R_NDX1,X
  BCS P%+5
  LDA R_NDX1,X
  CMP R_NDX2,X
  BCS fin
  TAX
  LDA r_c0
  JSR rs_put
  LDX RZ_Y
  BRA fin
.l2
.^r_pt422 LDY r_bdx2,X
  DEY
  TAX
  LDA r_c1
  JSR rs_put
  LDX RZ_Y
.fin
  LDA R_NDX0,X            \ the new boundaries; what was written
.^r_pt407 STA r_bdx0,X
  LDA R_NDX1,X
.^r_pt419 STA r_bdx1,X
  LDA R_NDX2,X
.^r_pt423 STA r_bdx2,X
  LDA r_wmax
  BEQ fx
  STA R_WR,X
  LDA r_wmin
  STA R_WL,X
.fx
  JMP r_dmbx
}

\ rs_cols (raster_strips.asm's): X = row, A's bit 7: colour B at the left
\ end: r_c0 and r_c1, the colours of the segment at the left end and of the
\ next, by the row's parity (keeps X)
.rs_cols
{
  ASL A                   \ (C: colour B at the left end)
  TXA
  AND #1
  TAY                     \ (Y: an odd row)
  BCS b
  LDA R_DCE,Y
  STA r_c0
  LDA R_DBE,Y
  STA r_c1
  RTS
.b
  LDA R_DBE,Y
  STA r_c0
  LDA R_DCE,Y
  STA r_c1
  RTS
}

\ rs_put (raster_strips.asm's, and r_dq's): r_sw, noting the strip in r_wmin ..
\ r_wmax (strips come left to right: the first sets r_wmin, the last r_wmax)
.rs_put
  CPX r_wmin
  BCS P%+5
  STX r_wmin
  STY r_wmax
  JMP r_sw

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
\ r_dpe: X = row of a two-colour disc, no dirty, its span, count or colour
\ changed (r_dmb).  A row is a list of edges: its span's left end, its
\ boundaries, the end after its right end; a pixel takes the colour after
\ the last edge at or before it (black after the last).  The old list and
\ the new are made alike, three boundaries each and the same colour at the
\ left end, with virtual boundaries (segments of no width): one at the left
\ end of the list with fewer if the colours there differ, then at the end
\ after the right end of each list as many as it lacks.  Then each edge's
\ strip, old .. new, is written in the colour on the side it moved from,
\ cut short where the edge before's new place (moving right) or the edge
\ after's (moving left) has passed into it: exactly the pixels whose
\ colour changed (each such pixel lies in one strip, as the edges are in
\ order, old and new).  More than three boundaries after that, or an
\ unknown old count: r_drg, a repaint.  No old span: the new one segment by
\ segment (r_segw, whole bytes through the row runs); a row with no old
\ span has a count of none (R_RESETBUF, r_dbm's switch from plain rows and
\ every write of an empty span keep it so), so the same count means both
\ spans there.  No new span: r_dp2 blacks the old.  No boundaries, old or
\ new, and the same colour: r_dp2's one-colour row.
\ ============================================================================
\ r_dpb: r_dp2 for a one-colour row in colour B (X = RZ_Y = row): R_DCE /
\ R_DCO and R_DBE / R_DBO swapped round it.  Returns X = RZ_Y.
.r_dpb
  JSR r_dsw
  JSR r_dp2+2
.r_dsw                    \ swap the colour pairs (X kept)
  LDA R_DCE
  LDY R_DBE
  STA R_DBE
  STY R_DCE
  LDA R_DCO
  LDY R_DBO
  STA R_DBO
  STY R_DCO
  RTS
.r_dpe
{
  STX RZ_Y
  LDA R_NDN,X             \ the count and the colour (bit 7), new and old
.^r_pt154 CMP r_bdn,X
  BEQ sm
  JMP df
.sm
  ASL A                   \ the same (A = 2 count, C = the colour): no
  BNE sc                  \ boundaries: a one-colour row, which r_dp2 does
  BCS r_dpb               \ in less time, in colour A (R_DCE / R_DCO) or,
  JMP r_dp2+2             \ with the pairs swapped round it, B (RZ_Y = X
                          \ already: skip STX)
.sc
  LSR A                   \ (both spans there: a count of one to three)
  STA r_ok
  STA r_nk
  JSR ld
  LDA R_NDN,X
  JMP rs_cs
.df                       \ another count or colour
.^r_pt155 LDA r_bdn,X
  CMP #&40
  BEQ rp                  \ (the old count unknown)
  LDA R_NDISCL,X
  CMP #&FF
  BEQ ne
  LDA R_NDN,X             \ the counts (the new at most three)
  AND #7
  CMP #4
  BCS rp
  STA r_nk
.^r_pt156 LDA r_bdn,X
  AND #3
  STA r_ok
.^r_pt157 LDA r_sl,X
  CMP #&FF
  BEQ oe
  JSR ld
  LDA R_NDN,X             \ (C: the colours at the left end differ)
.^r_pt158 EOR r_bdn,X
  ASL A
  LDA R_NDN,X
  JMP rs_df
.rp
  TXA                     \ a repaint
  TAY
  JMP r_drg
.ne
  JSR r_dp2+2             \ no new span: the old one black (RZ_Y = X: skip
  LDY RZ_Y                \ STX), then the row's count and colour
  JMP r_bstore
.oe
  TXA                     \ no old span: the new one segment by segment
  TAY                     \ (r_segw: whole bytes through the row runs)
  JSR r_rowset
  JSR r_bcols
  LDA R_NDISCL,Y
  STA r_nL
  LDA R_NDISCR,Y
  STA r_nR
  LDA #&FF
  STA r_wmin
  STZ r_wmax
  JSR r_segw
  JMP r_dpst
\ ld: row X's edges as raster_strips.asm wants them, the row pointers and
\ nothing written yet (r_wmin, r_wmax); keeps X
.ld
.^r_pt132 LDA r_sl,X
  STA r_ol
.^r_pt138 LDA r_bdx0,X
  STA rs_t0
.^r_pt139 LDA r_bdx1,X
  STA rs_t1
.^r_pt137 LDA r_bdx2,X
  STA rs_t2
.^r_pt133 LDA r_sr,X
  INC A
  STA r_oe
  LDA R_NDISCL,X
  STA r_nl
  LDA R_NDX0,X
  STA rs_t3
  LDA R_NDX1,X
  STA rs_t4
  LDA R_NDX2,X
  STA rs_t5
  LDA R_NDISCR,X
  INC A
  STA r_ne
  TXA
  AND #7
  STA RZ_PA
  STA RZ_PB
  LDA r_ypg,X
  STA RZ_PA+1
  INC A
  STA RZ_PB+1
  LDA #&FF
  STA r_wmin
  STZ r_wmax
  RTS
}
.rs_ov                    \ (raster_strips.asm: more than three boundaries,
  LDY RZ_Y                \ nothing written: a repaint)
  JMP r_drg
 INCLUDE "1-source-files/main-sources/gfx-raster_strips.asm"
\ r_dpst: (falling from raster_strips.asm's strips, or from r_dpe) the row's
\ new span, count, colour and boundaries; what was written
.r_dpst
{
  LDY RZ_Y                \ the row's new span, count, colour and boundaries;
  LDA R_NDISCL,Y          \ what was written
.^r_pt149 STA r_sl,Y
  LDA R_NDISCR,Y
.^r_pt130 STA r_sr,Y
  LDA R_NDN,Y
.^r_pt131 CMP r_bdn,Y
  BNE e5
  LDA R_NDX0,Y            \ (the same count and colour)
.^r_pt134 STA r_bdx0,Y
  LDA R_NDX1,Y
.^r_pt135 STA r_bdx1,Y
  LDA R_NDX2,Y
.^r_pt136 STA r_bdx2,Y
  BRA e6
.e5
  JSR r_bstore
.e6
  LDA r_wmax
  BEQ e7
  STA R_WR,Y
  LDA r_wmin
  STA R_WL,Y
.e7
  RTS
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
  LDA R_NDN,Y             \ the count (at most 4) and the colour (bit 7)
  AND #&7F
  STA r_cn
  LDA R_NDX0,Y
  STA r_bv
  LDA R_NDX1,Y
  STA r_bv+1
  LDA R_NDX2,Y
  STA r_bv+2
  LDA R_NDX3,Y
  STA r_bv+3
  LDA R_NDN,Y
  ROL A
  ROL A
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
.^r_pt86 CMP r_bdn,Y
  BNE sg
  ASL A                   \ (A = 2 count, C = the colour)
  BNE sg
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


\ r_bcols: Y = row: r_cA, r_cB = colour A, B bytes of the row (keeps X, Y; r_drg,
\ r_dpe)
.r_bcols
  TYA
  LSR A                   \ (C: an odd row)
  LDA R_DCE
  BCC P%+4
  LDA R_DCO
  STA r_cA
  LDA R_DBE
  BCC P%+5
  LDA R_DBO
  STA r_cB
  RTS

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











