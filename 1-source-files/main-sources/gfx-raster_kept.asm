\ ============================================================================
\ raster_kept.asm -- kept solid rows (docs/renderer.md), bank 5's part:
\ in the disc window (ROMSEL 5), after raster_disc.asm.  The polygons' part,
\ k_pre and k_settle, is in bank 7 (gfx-kept7.asm); the repair's part is in
\ r7_crep and r7_rowrep (raster_disc.asm).
\
\ A row of a buffer is kept when the last thing drawn on it in that buffer's
\ frame was one polygon span covering the row's whole dirty extent, so that
\ the row holds that span and nothing else: whole bytes of one value v (not
\ zero) between its two edge bytes.  KF[y] bit b (KBIT) says so for buffer
\ b.  On that buffer's next frame the repair leaves the row as it is
\ (pending: KF bit 7, the old extent still in DIRTY), and the first thing to
\ touch the row settles it: a polygon span (k_settle) blacks the old pixels
\ outside its own interior and writes only the interior bytes the row does
\ not already hold in its colour; anything else (k_kill, from the
\ trampolines: lines, dots, spans, R_MARKDIRTY, the text) blacks the old
\ extent first; what is still pending after the ships is blacked then
\ (k_commit).
\
\ Only while KMODE bit 7 is set (T_KFRAME: a space station close by); KF is
\ all zero otherwise.
\ ============================================================================

\ k_rows: rows A .. X (A <= X, both in 0..191): a pending row's old extent is
\ blacked (row1, as the repair would have), then KF AND k_mask is kept
\ (k_mask: &7F, or &7F AND KBITN to forget the rows' kept state too)
.k_rows
{
  STA k_lo
  STX k_hi
  LDY k_lo
.lp
  LDA KF,Y
  BEQ nx
  BPL m1
  JSR r_row1              \ (keeps Y)
  LDA KF,Y
.m1
  AND k_mask
  STA KF,Y
.nx
  CPY k_hi
  INY
  BCC lp
  RTS
}

\ k_commit: after the ships, black every row still pending (KPLO..KPHI)
.k_commit
{
  LDY KPLO
  CPY KPHI
  BEQ lp
  BCS none
.lp
  LDA KF,Y
  BPL nx
  JSR r_row1              \ (keeps Y)
  LDA KF,Y
  AND #&7F
  STA KF,Y
.nx
  CPY KPHI
  INY
  BCC lp
.none
  LDA #&FF
  STA KPLO
  STZ KPHI
  RTS
}

\ k_kill and k_clear: from the trampolines (ROMSEL 5)
.k_kill                   \ rows A .. X: pending ones blacked first (k_rows),
  PHA                     \ then forgotten
  LDA KBITN
  AND #&7F
  STA k_mask
  PLA
  JMP k_rows
.k_clear                  \ forget every kept row (K mode off, a reset
  LDY #191                \ buffer, the flare, R_INIT); A = 0 on return
  LDA #0
.kcl1
  STA KF,Y
  DEY
  CPY #&FF
  BNE kcl1
  RTS

.k_lo EQUB 0
.k_hi EQUB 0
.k_mask EQUB 0
