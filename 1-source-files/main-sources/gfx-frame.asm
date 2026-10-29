\ ******************************************************************************
\
\ frame.asm - the double-buffered filled renderer's frame layer
\
\ Lives in sideways RAM bank GFXBANK (paged in only for the duration of a call,
\ via GCALL in main RAM). Elite's drawing primitives, when QQ11 = 0 (the space
\ view, the title screen and the death screen: the only screens that draw
\ ships), record what they would have drawn into the display list here; FRAME
\ (called once per main-loop iteration) renders the list into the back buffer
\ and asks the IRQ to show it at the next vertical sync.
\
\ Entry points are reached through the jump table at the start of the bank,
\ GT_* indices below, by LDX #GT_xxx : JSR GCALL.
\
\ ******************************************************************************

\ Entry points are called from main RAM through the G_* stubs (see
\ gstubs.asm), which page this bank in and Elite's bank back afterwards,
\ preserving A, X, Y and C on entry.

FZ = &D2                \ &D2-&E1
fz_p    = FZ            \ general pointer (2)
fz_q    = FZ+2          \ second pointer (2)
fz_dl   = FZ+4          \ ship's XX2 copy (2)
fz_v3   = FZ+6          \ ship's XX3 copy (2)
fz_ft   = FZ+8          \ face list pointer (2)
fz_nm   = FZ+10         \ general pointer (2), used by the text overlay
fz_dt   = FZ+10         \ ship's fin / detail list pointer (2)
fz_i    = FZ+12
fz_n    = FZ+13
fz_t    = FZ+14
fz_u    = FZ+15

\ ------------------------------------------------------------------------------
\ State
\ ------------------------------------------------------------------------------

\ Shared with the IRQ handler and Elite (in the glue area, gfx-gvars.asm):
\ GMODE (bit 7 set = space mode, double buffered), GFRONT (0/1 buffer
\ displayed), GFLIP (non-zero = flip pending to GPEND), GPEND, GDRAWON
\ (0 = primitives are erasing, so ignore them), GFORCE (non-zero = draw
\ directly even though QQ11 = 0), GSIGHT, GLASV.

.F_BACK     EQUB 1      \ the buffer being drawn (the one not displayed)

.F_NSHIP    EQUB 0      \ ships recorded this frame
.F_SZH      SKIP MAXSH  \ ship z (hi, lo) for sorting
.F_SZL      SKIP MAXSH
.F_STYP     SKIP MAXSH  \ ship type
.F_SNF      SKIP MAXSH  \ number of faces
.F_SPL      SKIP MAXSH  \ pointer into F_DL: XX2 copy (nf bytes) then XX3 copy
.F_SPH      SKIP MAXSH
.F_ORD      SKIP MAXSH  \ draw order (indices, far to near)
.F_SX4      SKIP MAXSH  \ LL9's XX4 (vertex visibility cut-off)
.F_DLP      EQUW 0      \ next free byte in F_DL

.F_NLINE    EQUB 0      \ enemy laser beams recorded this frame
.F_LX0      SKIP MAXLN
.F_LY0      SKIP MAXLN
.F_LX1      SKIP MAXLN
.F_LY1      SKIP MAXLN
.F_BX       SKIP 10     \ the energy bomb's bolt (f_bomb), BOMBTBX and BOMBTBY
.F_BY       SKIP 10     \ as F_BOMB found them

.F_NDOT     EQUB 0      \ dots recorded this frame (particles, distant ships)
.F_DX       SKIP MAXDT
.F_DY       SKIP MAXDT
.F_DS       SKIP MAXDT  \ size 1..3
.F_DC       SKIP MAXDT  \ colour index


.F_PLON     EQUB 0      \ planet disc recorded this frame
.F_PLX      EQUW 0      \ centre x (16-bit signed screen)
.F_PLY      EQUW 0      \ centre y
.F_PLR      EQUB 0      \ radius
.F_PLT      EQUB 0      \ planet type

.F_DCOL     EQUB 0, 0   \ disc colour index currently in each buffer's disc layer

\ ------------------------------------------------------------------------------
\ Fixed colours (even-row byte, odd-row byte), by index
\ ------------------------------------------------------------------------------

FC_BLACK = 0
FC_LASER = 1            \ our laser beams
FC_ELASER = 2           \ enemy laser beams
FC_PLINE = 3            \ planet meridians / craters
FC_PART = 4             \ explosion particles
FC_SIGHT = 5            \ laser sights
FC_STAR = 6             \ stardust (logical colour; stars use a solid ink)

.F_CPE
 EQUB &00, &FF, &F0, &0F, &FF, &0F, &FF
F_CPO = F_CPE           \ (the odd rows' bytes are the even rows')

\ F_INIT: one-off initialisation (called by the loader / startup) is in F_DL
\ (elite-gfx.asm), which it leaves to the ship records.

\ ------------------------------------------------------------------------------
\ Text map: 24 rows x 32 columns of desired characters (F_TM). A cell holds
\ its character (&20-&7F), or 0, or, once cleared, &80 + the character it
\ had (empty, remembering it), or &80 (empty: f_drule's mark for a cell a
\ buffer may show anything in). F_TMR counts each row's non-empty cells.
\ F_TCH holds, per row, bit b (P) for buffer b: the row has changed since
\ buffer b's text steps last ran on it. Nothing else records what a buffer
\ shows; between frames, for each buffer b and row:
\
\   * P clear: b shows exactly the row's characters (nothing in an empty
\     cell);
\   * P set: a cell holding c or &80 + c shows c or nothing, one holding 0
\     nothing, one holding &80 anything.
\
\ A cell given a different character (not into an empty, never-shown cell,
\ not its remembered one: f_char1) is erased at once in both buffers' next
\ frames, through their dirty extents (f_mark). A buffer's text steps, in a
\ row with P set, erase each cell with bit 7 set (f_text1), draw every
\ character (f_text2) and clear P; elsewhere they redraw only the
\ characters something was drawn over this frame. So a cell cleared and
\ given its character back (TT66 and a view's title) is left alone in both
\ buffers, as with the original's shown maps. Once both buffers have erased
\ a cleared cell it holds 0 (f_text1). A buffer's screen cleared (TTX66,
\ f_b0new) shows nothing: right for any P, as everything in the map since
\ (the screen's text) set P.
\
\ Outside record and space mode CHPR draws into shadow RAM (buffer 1) and
\ the map changes only so that buffer 0 (main RAM, the last space-mode
\ frame: f_enter) knows what of its text the screen's text has overprinted
\ (f_drule), with one exception: the first DLMAX characters after a screen
\ clear are noted (f_dlx/f_dly/f_dlk, f_dlog) and given to the map at the
\ first change in record or space mode (f_sync), as the screens that carry
\ on in record mode without a TT66 (DEATH's and TITLE's TT66 13, then QQ11
\ = 0; the briefing's LL9B) have drawn at most TTX66K's hyperspace
\ countdown (ee3: three characters) directly, which then stays on the
\ screen (docs/renderer.md, "The text map").
\ ------------------------------------------------------------------------------

DLMAX = 3               \ (TTX66K's ee3: TT11, three digits)

\ f_cell: X = column, Y = row -> the map accessors f_tmld/f_tmst patched to
\ its cell (row*32 + column)

.f_cell
 TYA
 LSR A
 LSR A
 LSR A
 STA f_tmld+2           \ row DIV 8 = high byte of row*32
 TYA
 ASL A
 ASL A
 ASL A
 ASL A
 ASL A                  \ (row MOD 8) * 32
 STX f_tmld+1
 ORA f_tmld+1
 CLC
 ADC #LO(F_TM)
 STA f_tmld+1
 STA f_tmst+1
 LDA f_tmld+2
 ADC #HI(F_TM)
 STA f_tmld+2
 STA f_tmst+2
 RTS

.f_row  EQUB 0
.f_tcol  EQUB 0
.F_TCH  SKIP 24         \ per text row: bit b set (P) = the row changed since
                        \ buffer b's text steps last ran on it
.f_tbit EQUB 0          \ this frame's buffer's bit in F_TCH (1 or 2)
.f_obit EQUB 0          \ and the other buffer's

\ f_char1 (F_CHAR, frame_cold.asm; f_sync): character A into the cell at
\ column X, row Y. EOR semantics like the original: printing the same
\ character again removes it.

.f_char1
 CPY #24
 BCS fch9
 CPX #32
 BCS fch9
 STY f_row
 STX f_tcol
 STA f_tmp
 JSR f_cell
 JSR f_tmget            \ X = the cell
 BEQ fch1               \ empty, never shown: store the character
 TXA
 BMI fch3
 CMP f_tmp
 BEQ fch2               \ the same character: remove it
 JSR f_eor              \ the one this cell's character replaced since the
 BCS fch8               \ frame: EOR takes it out again, the cell is unchanged
 JSR f_mark             \ another: replace it (erased in both buffers)
 BRA fch4
.fch3
 AND #&7F               \ cleared: the character it remembers is shown as it
 CMP f_tmp              \ was; another is drawn over an erased cell
 BEQ fch1
 JSR f_mark
.fch1
 LDX f_row
 INC F_TMR,X
.fch4
 LDA f_tmp
 JSR f_tmst
 BRA fch8
.fch2
 JSR f_tmclr
 LDX f_row
 DEC F_TMR,X
.fch8
 LDX f_row
 LDA #3
 STA F_TCH,X
.fch9
 RTS

\ f_eor: character f_tmp printed over the cell at f_tcol, f_row, which holds
\ another, A. CHPR draws by EOR, and TT107 prints the countdown's next
\ number over the current one and then the current one again, to take it
\ out: so when a cell was given its character over f_tmp since the last
\ frame, printing f_tmp again leaves the cell as it is (C set). Otherwise
\ (C clear) the replacement of A is noted in a ring of RPN cells (the
\ countdown replaces at most three at a time; f_text1 forgets them).

RPN = 4

.f_eor
 STA f_eok
 LDX f_rpn
 CPX #RPN+1
 BCC P%+4
 LDX #RPN
.feo1
 DEX
 BMI feo4
 LDA f_rpr,X
 CMP f_row
 BNE feo1
 LDA f_rpc,X
 CMP f_tcol
 BNE feo1
 LDA f_rpk,X
 CMP f_tmp
 BNE feo1
 LDA #&FF               \ (taken out: forgotten)
 STA f_rpr,X
 SEC
 RTS
.feo4
 LDA f_rpn
 INC f_rpn
 BNE P%+5
 DEC f_rpn              \ (saturates at 255)
 AND #RPN-1
 TAX
 LDA f_row
 STA f_rpr,X
 LDA f_tcol
 STA f_rpc,X
 LDA f_eok
 STA f_rpk,X
 CLC
 RTS

.f_rpn  EQUB 0          \ cells noted since the last frame (to 255)
.f_rpr  SKIP RPN        \ their rows (&FF: none), columns and replaced
.f_rpc  SKIP RPN        \ characters
.f_rpk  SKIP RPN
.f_eok  EQUB 0

.f_tmclr                \ the cell (not empty) cleared: it remembers its
 JSR f_tmget            \ character, which each buffer shows or not as before
 TXA
 ORA #&80
.f_tmst
 STA F_TM               \ patched
 RTS

.f_tmget
.f_tmld
 LDX F_TM               \ patched; sets Z and N on the content
 RTS

.f_ysav EQUB 0
.f_tmp  EQUB 0

\ f_mark: the cell at column f_tcol, row f_row is given a character where a
\ buffer may show another: erase it in both buffers' next frames (buffer 0's
\ only while f_mk0 is set, f_sync), as f_text1's erases do there: its
\ pixels, clipped to the space views' clip window (x 2..253,
\ y 1..191, F_FRAME), into the buffer's dirty extents (R_DIRTYLb/R_DIRTYRb,
\ main RAM), its pixel rows no longer kept in it (KF bit b,
\ gfx-raster_kept.asm), and the rows noted (f_mrt/f_mrb) for f_text1 to
\ give to the rasteriser's dirty row range (R_PRDYT/R_PRDYB, bank 5)

.f_mark
 LDA f_tcol
 ASL A
 ASL A
 ASL A
 PHA
 CMP #2
 BCS P%+4
 LDA #2
 STA fmk_l+1
 PLA
 ORA #7
 CMP #254
 BCC P%+4
 LDA #253
 STA fmk_r+1
 LDA f_row
 ASL A
 ASL A
 ASL A
 STA fmk_y+1            \ the cell's pixel rows 8r .. 8r + 7 (8r + 8: fmk_e)
 ADC #8                 \ (C = 0: r <= 23)
 STA fmk_e+1
 LDX #0                 \ buffer 0, then 1
.fmk0
 LDA fbp_dl,X
 STA fmk_d1+2
 STA fmk_d2+2
 LDA fbp_dr,X
 STA fmk_d3+2
 STA fmk_d4+2
 LDA fmk_kb,X
 STA fmk_k+1
.fmk_y
 LDY #0                 \ patched: 8r
 BNE P%+3               \ (row 0: from y = 1)
 INY
 TYA
 CMP f_mrt,X
 BCS P%+5
 STA f_mrt,X
.fmk1
.fmk_l
 LDA #0                 \ patched: the cell's left end
.fmk_d1
 CMP R_DIRTYL0,Y        \ patched
 BCS P%+5
.fmk_d2
 STA R_DIRTYL0,Y        \ patched
.fmk_r
 LDA #0                 \ patched: its right end
.fmk_d3
 CMP R_DIRTYR0,Y        \ patched
 BCC P%+5
.fmk_d4
 STA R_DIRTYR0,Y        \ patched
 LDA KF,Y
.fmk_k
 AND #0                 \ patched: not buffer X's bit
 STA KF,Y
 INY
.fmk_e
 CPY #0                 \ patched: 8r + 8
 BCC fmk1
 DEY
 TYA
 CMP f_mrb,X
 BCC P%+5
 STA f_mrb,X
 INX
 CPX #2
 BCS fmk9
 LDA f_mk0
 BEQ fmk0
.fmk9
 RTS

.fmk_kb EQUB &FE, &FD   \ (KF: bit b for buffer b, gfx-tramp.asm's tkbit)
.f_mrt  EQUB 255, 255   \ per buffer: the pixel rows f_mark has marked since
.f_mrb  EQUB 0, 0       \ its last frame (top 255: none)
.f_mk0  EQUB 0          \ non-zero: f_mark leaves buffer 1 alone

\ f_delchar0 (F_DELCHAR, frame_cold.asm): clear the text map cell at X =
\ column, Y = row

.f_delchar0
 STY f_ysav
 CPY #24
 BCS fdc9
 CPX #32
 BCS fdc9
 STY f_row
 JSR f_cell
 JSR f_tmget
 BEQ fdc9
 BMI fdc9
 JSR f_tmclr
 LDX f_row
 DEC F_TMR,X
 LDA #3
 STA F_TCH,X
.fdc9
 LDY f_ysav
 RTS

\ f_clrtext0 (F_CLRTEXT, frame_cold.asm; f_direct0): clear text map rows X
\ to Y inclusive (each cell remembers its character; a row with no
\ character is left as it is). Y is kept

.f_clrtext0
 STY f_ysav
 STY f_tmp
.fct1
 STX f_row
 LDA F_TMR,X            \ (an empty row is clear already)
 BEQ fct6
 LDY f_row
 LDX #0
 JSR f_cell             \ f_tmst -> start of row
 LDA f_tmst+1
 STA fct3+1
 STA fct4+1
 LDA f_tmst+2
 STA fct3+2
 STA fct4+2
 LDY #31
.fct3
 LDA F_TM,Y             \ patched
 BEQ fct5
 ORA #&80
.fct4
 STA F_TM,Y             \ patched
.fct5
 DEY
 BPL fct3
 LDX f_row
 STZ F_TMR,X
 LDA #3
 STA F_TCH,X
.fct6
 INX
 CPX #24
 BCS fct9
 CPX f_tmp
 BCC fct1
 BEQ fct1
.fct9
 LDY f_ysav
 RTS

\ ------------------------------------------------------------------------------
\ f_direct0 (F_DIRECT, frame_cold.asm): the screen is about to be cleared and
\ drawn directly (TT66): cancel double buffering, show and access main RAM.
\ ------------------------------------------------------------------------------

.f_direct0              \ (Master port: direct mode shows shadow RAM, where
 SEI                    \ Master's own drawing goes, buffer 1)
 LDA #0
 STA GMODE
 STA GFLIP
 STA GSIGHT
 STA GLASV
 LDA #1
 STA GFRONT
 TSB &FE34              \ ACCCON D = 1: show shadow RAM (X as it is)
 CLI
 LDX #0                 \ the text map cleared (Y is kept)
 LDY #23
 JSR f_clrtext0
 LDA #0
 LDX #NDSTAR-1          \ the stars will be re-recorded too (and no
.fdi1                   \ direct-mode stars noted: F_DSS)
 STA R_SS,X
 STA F_DSS,X
 DEX
 BPL fdi1
 RTS

\ ------------------------------------------------------------------------------
\ Recorders (called during the main loop; must only touch Elite variables they
\ are documented to read, and preserve Y)
\ ------------------------------------------------------------------------------

\ F_SHIP: record the ship being drawn by LL9. Inputs: TYPE, GNF (faces),
\ GNV (vertices), XX2 (face visibility), XX3 (projected vertices), INWK+6/7 (z),
\ and the orientation vectors' high bytes (L_REC: the record's XX2 copy holds
\ each face's lighting level, see gfx-light.asm).

.F_SHIP
 STY f_ysav
 LDX F_NSHIP
 CPX #MAXSH
 BCC P%+5
 JMP fsh9
 LDA GNV
 ASL A
 ASL A
 STA f_nv4
 CLC
 ADC GNF
 ADC F_DLP              \ room for nf + 4 * nv bytes?
 LDA F_DLP+1
 ADC #0
 CMP #HI(F_DLEND)
 BCC P%+5
 JMP fsh9
 LDA F_DLP
 STA F_SPL,X
 STA fsh2+1
 LDA F_DLP+1
 STA F_SPH,X
 STA fsh2+2
 LDA INWK+7
 STA F_SZH,X
 LDA INWK+6
 STA F_SZL,X
 LDA GTYPE              \ (Master port: TYPE, or DOD for the Dodo station)
 STA F_STYP,X
 LDA GNF
 STA F_SNF,X
 LDA XX4
 STA F_SX4,X
 LDY #0
 LDX GNF
 BEQ fsh3
.fsh1
 LDA XX2,Y
.fsh2
 STA &FFFF,Y            \ patched
 INY
 DEX
 BNE fsh1
 LDA GTYPE              \ Master port: the alloy plate's one face has no
 CMP #PLT               \ normal, so LL9 never marks it visible: fill it from
 BNE fsh3               \ both sides (no winding cull)
 LDA fsh2+1
 STA fsh8+1
 LDA fsh2+2
 STA fsh8+2
 LDA #1
.fsh8
 STA &FFFF              \ patched: the XX2 copy's first byte
.fsh3
 JSR L_REC              \ the faces' levels into the XX2 copy (gfx-light.asm,
                        \ main RAM: game context; Y is kept)
 TYA                    \ advance the destination past the XX2 copy
 CLC
 ADC fsh2+1             \ d = lo0 (C = carry into hi)
 STA fsh5+1             \ patch d+0, d+1, d+2, d+3 into the unrolled loop
 INC A                  \ (INC A leaves C alone)
 STA fsh5a+1
 INC A
 STA fsh5b+1
 INC A
 STA fsh5c+1
 LDA fsh2+2
 ADC #0
 STA fsh5+2
 STA fsh5a+2
 STA fsh5b+2
 STA fsh5c+2
 LDA fsh5+1             \ rare: d+k wrapped into the next page
 CMP #&FD
 BCC fsh7
 INC fsh5c+2
 CMP #&FE
 BCC fsh7
 INC fsh5b+2
 CMP #&FF
 BCC fsh7
 INC fsh5a+2
.fsh7
 LDA f_nv4              \ 4 * nv bytes, a multiple of 4
 BEQ fsh6
 SEC
 SBC #4
 TAY                    \ Y = f_nv4-4 .. 0 step -4, C = 1 in the loop
.fsh4
 LDA XX3+3,Y
.fsh5c
 STA &FFFF,Y            \ patched: d+3
 LDA XX3+2,Y
.fsh5b
 STA &FFFF,Y            \ patched: d+2
 LDA XX3+1,Y
.fsh5a
 STA &FFFF,Y            \ patched: d+1
 LDA XX3,Y
.fsh5
 STA &FFFF,Y            \ patched: d
 TYA
 SBC #4
 TAY
 BCS fsh4
.fsh6
 LDA f_nv4
 CLC
 ADC fsh5+1
 STA F_DLP
 LDA fsh5+2
 ADC #0
 STA F_DLP+1
 INC F_NSHIP
.fsh9
 LDY f_ysav
 RTS

.f_nv4 EQUB 0

\ F_BOMB: BOMBOFF is about to draw the energy bomb's bolt (H_BOMB): its
\ nine lines join the ten points BOMBTBX/BOMBTBY, which BOMBON set; copy
\ them, so the frame draws the last bolt drawn (its LOIN calls, H_LLINE,
\ record nothing)

.F_BOMB
 LDX #9
.fbo1
 LDA BOMBTBX,X          \ (main RAM: G_BOMB runs in game context; bankcheck: ok)
 STA F_BX,X
 LDA BOMBTBY,X          \ (bankcheck: ok)
 STA F_BY,X
 DEX
 BPL fbo1
 STX f_bomb             \ (&FF)
 RTS
.f_bomb  EQUB 0         \ bit 7: a bolt this frame

\ F_LINE: record an enemy laser beam X1,Y1 -> X2,Y2 (8-bit screen coords;
\ at most one per ship recorded: MAXLN)

.F_LINE
 LDX F_NLINE
 CPX #MAXLN
 BCS fli9
 LDA X1
 STA F_LX0,X
 LDA Y1
 STA F_LY0,X
 LDA X2
 STA F_LX1,X
 LDA Y2
 STA F_LY1,X
 INC F_NLINE
.fli9
 RTS

\ F_DOT: record a dot at X = x, A = y, size from ZZ as PIXEL does, colour GDCOL

.F_DOT
 STY f_ysav
 LDY F_NDOT
 CPY #MAXDT
 BCS fdo9
 STA F_DY,Y
 TXA
 STA F_DX,Y
 LDA GDCOL
 STA F_DC,Y
 LDX #2                 \ (Master port: a dash for ZZ >= 80, a double-
 LDA ZZ                 \ height dash below, as Master's PIXEL)
 CMP #80
 BCS fdo1
 INX
.fdo1
 TXA
 STA F_DS,Y
 INC F_NDOT
.fdo9
 LDY f_ysav
 RTS

\ F_PLANET: record the planet: centre (K3, K4) 16-bit, radius K, TYPE

.F_PLANET
 LDA TYPE
 LSR A
 BCS fpl1
 LDA K3
 STA F_PLX
 LDA K3+1
 STA F_PLX+1
 LDA K4
 STA F_PLY
 LDA K4+1
 STA F_PLY+1
 LDA K
 STA F_PLR
 LDA TYPE
 STA F_PLT
 LDA INWK+8             \ the planet's z is 24-bit, and a ship drawn with
 BEQ P%+4               \ faces is nearer than 4096: a planet 65536 or more
 LDA #&FF               \ away is held as z_hi = &FF, further than any such
 ORA INWK+7             \ ship (with INWK+7 alone, a planet 65536-69631 away
                        \ hid the station in front of it on a docking run)
 STA F_PLZH
 LDA INWK+6
 STA F_PLZL
 LDA #&FF
 STA F_PLON
 RTS

.F_PLZH EQUB 0          \ the planet's z (hi, lo), for hiding ships behind it
.F_PLZL EQUB 0
.fpl1                   \ the sun
 LDA K3
 STA F_SUX
 LDA K3+1
 STA F_SUX+1
 LDA K4
 STA F_SUY
 LDA K4+1
 STA F_SUY+1
 LDA K
 STA GSUNR
 LDA #&FF
 STA GSUNON
 RTS

\ F_SHPPT: record a distant ship as a 2x2 dot at (K3, K4), in its hue

.F_SHPPT
 STY f_ysav
 LDY F_NDOT
 CPY #MAXDT
 BCS fsp9
 LDA K3
 STA F_DX,Y
 LDA K4
 STA F_DY,Y
 LDA #3
 STA F_DS,Y
 LDA TYPE
 ORA #&80               \ bit 7: ship type (bits 0-6), drawn in its dot colour
 STA F_DC,Y
 INC F_NDOT
.fsp9
 LDY f_ysav
 RTS

\ ------------------------------------------------------------------------------
\ F_FRAME: render this frame's display list into the back buffer and queue a
\ flip. Called once per main-loop iteration (after M%), and per title-screen
\ iteration.
\ ------------------------------------------------------------------------------

.F_FRAME
 STY f_ysav
 LDA QQ11
 BEQ ff1
 JSR T_KOFF             \ (no kept rows: docs/renderer.md)
 JMP f_reset            \ not a space view: just forget what was recorded

.ff1                    \ (G_FRAME has run L_SUN, the light for the next
                        \ iteration's ships, in game context)

 \ save the zero page the rasteriser uses (&06-&27) and the frame layer's
 \ (&D2-&E1), unrolled
 FOR z, &06, &27        \ (on the stack: LDA zp/PHA is a cycle cheaper than
  LDA z                 \ LDA zp/STA abs; PLA/STA zp costs what LDA abs/STA zp
  PHA                   \ did)
 NEXT
 FOR z, 0, 15
  LDA FZ + z
  PHA
 NEXT

 BIT GMODE
 BMI ff5
 JSR f_enter2           \ first space-mode frame since the screen was cleared
                        \ (f_enter, with frame_cold.asm's direct-mode fix-ups)

.ff5                    \ (what touches no screen memory goes before the wait)
 JSR f_bufpatch
 LDA #2                 \ the clip window inside the border (the zero page
 STA R_CL               \ copy is Elite's between frames)
 LDA #253
 STA R_CR
 LDA #1
 STA R_CT
 LDA #191
 STA R_CB
 LDA F_BACK              \ K mode: kept solid rows (gfx-raster_kept.asm)
 JSR T_KFRAME
 LDA F_BACK
 JSR T_SETBUF
 JSR f_text1            \ text cells to be erased: background them (old dirty)
 JSR f_sight1           \ and the sights, if they have gone

.ff2
 LDA GFLIP              \ wait for the previous flip, so the back buffer is
 BNE ff2                \ no longer on screen

 LDA F_BACK             \ let the CPU see the back buffer at &4000-&6FFF
 BEQ ffb0               \ (Master port: ACCCON X only, D is the IRQ's: the
 LDA #4                 \ front buffer, and shadow RAM for the dashboard)
 TSB &FE34
.ffb0

 JSR T_STARERASE        \ undo last time's stars in this buffer
 JSR f_moon0            \ the moon: what this buffer shows of it (before
                        \ the layer's repair)
 JSR f_discs            \ the disc layer (sun or planet), incremental
 JSR f_disc2            \ the other disc, if both are on screen (incremental)
 JSR f_moon             \ the moon, if any (incremental)
 IF _PLANET_RINGS
 JSR f_ring             \ the ring, if any (dots; rings=on)
 ENDIF
.ff_lin                 \ (F_HANGAR points this call at f_hback for its frame)
 JSR f_lines            \ planet meridians, craters, enemy lasers
 JSR f_ships            \ filled ships, far to near
 JSR T_KCOMMIT          \ (K mode: the kept rows still pending blacked)
 JSR f_dots             \ particles, distant ships
 JSR f_lasers           \ our laser beams and the sights
 JSR f_flt              \ the lens flare (gfx-flare6.asm), then the text on top
 JSR f_sight2           \ and the sights
.ff_stars
 LDA #NOST+1            \ stardust, on black only (last: erasing it next
 STA R_SN               \ time restores black, so it needs no WL/WR): stars
 LDA F_SLV+16           \ 1..NOST (NOSTM is only ever NOST = 20), recorded by
 CMP #&80               \ the hooks straight into R_SX/R_SY/R_SS (R_SS = 0:
 BEQ ffs1               \ none); with a docking slot filled this frame,
 JSR f_slot             \ f_slot (gfx-frame_cold.asm) plots them
 BRA ff_stars9
.ffs1
 JSR T_STARPLOT
.ff_stars9              \ (the frame's drawing done: the harness's frame end)

 FOR z, 15, 0, -1        \ restore the zero page (pushed at ff1)
  PLA
  STA FZ + z
 NEXT
 FOR z, &27, &06, -1
  PLA
  STA z
 NEXT

 LDA #4                 \ CPU back to main RAM, and flip at the next vsync
 TRB &FE34
 LDA #%00000010         \ (Master port: with only the vsync interrupt masked
 STA &FE4E              \ in IER, as H_VSYNC reads GPEND and GFLIP; the timer 1
 LDA F_BACK             \ interrupt at the dashboard split must not be held
 STA GPEND              \ off)
 EOR #1
 STA F_BACK
 LDA #&FF
 STA GFLIP
 LDA #%10000010
 STA &FE4E

.f_reset
 LDA #&80               \ no docking slot (f_poly2 records one, f_slot uses it)
 STA F_SLV+16
 LDA #0                 \ empty the per-frame lists
 STA GLASV              \ (Master port: the beams show for one frame per LASLI)
 STA f_bomb             \ (and no bomb bolt yet)
 STA F_NSHIP
 STA F_NLINE
 STA F_NDOT
 STA F_PLON
 STA GSUNON
 STA MN_ON
 IF _PLANET_RINGS
 STA RG_N
 ENDIF
 LDA #LO(F_DL)
 STA F_DLP
 LDA #HI(F_DL)
 STA F_DLP+1
 LDY f_ysav
 RTS


\ f_enter: switch from direct drawing to double buffering. Main RAM (buffer
\ 0) has just been cleared by TT66 and holds the border; shadow RAM (buffer 1)
\ still holds the last frame of the previous space-mode session, which its
\ rasteriser state, disc colour and shown-text map still describe exactly
\ (direct mode only ever writes main RAM), so it is left alone and repaired
\ incrementally by its next frame. Only the border is copied across.

.f_enter
                        \ Master port: direct mode draws into shadow RAM (buffer
                        \ 1), which TTX66 has just cleared and given its border:
                        \ forget buffer 1's state. Main RAM (buffer 0) still
                        \ holds the last frame of the previous space-mode
                        \ session, which its rasteriser state, disc colour and
                        \ shown-text map still describe (direct mode never
                        \ writes main RAM), so it is left alone and repaired
                        \ incrementally by its next frame; only the border is
                        \ copied across (main RAM has none after F_INIT)
 LDA #HI(&4000)         \ copy byte columns 0 and 63 of every line, and the
 STA fen1+2             \ whole of line 0, from shadow RAM to main RAM
 STA fen2+2
 LDA #HI(&41F8)
 STA fen5+2
 STA fen6+2
.fen0
 LDA #4
 TSB &FE34              \ X = 1: shadow RAM
 LDX #7
.fen1
 LDA &4000,X            \ column 0, lines 0-7 of this character row
 STA F_HW,X
.fen5
 LDA &41F8,X            \ column 63
 STA F_HW+8,X
 DEX
 BPL fen1
 LDA #4
 TRB &FE34              \ X = 0: main RAM
 LDX #7
.fen3
 LDA F_HW,X
.fen2
 STA &4000,X
 LDA F_HW+8,X
.fen6
 STA &41F8,X
 DEX
 BPL fen3
 LDA fen1+2
 CLC
 ADC #2
 STA fen1+2
 STA fen2+2
 ADC #1
 STA fen5+2
 STA fen6+2
 CMP #&71
 BNE fen0
 LDA #4
 TSB &FE34
 LDX #0                 \ line 0: bytes 0, 8, 16, ... (every 8th byte of
.fen7                   \ pages &40 and &41)
 LDA &4000,X
 STA F_HW,X
 LDA &4100,X
 STA F_HW2,X            \ (F_HW, F_HW2: 512 bytes; rebuilt after)
 TXA
 CLC
 ADC #8
 TAX
 BNE fen7
 LDA #4
 TRB &FE34
.fen8
 LDA F_HW,X
 STA &4000,X
 LDA F_HW2,X
 STA &4100,X
 TXA
 CLC
 ADC #8
 TAX
 BNE fen8

 LDA #1                 \ buffer 1's state: empty (TTX66 blacked it)
 STA F_BACK
 STZ F_SGS+1
 STZ MO_ON+1            \ (no moon in it)
 JSR T_SETBUF
 JSR T_RESETBUF
 LDA #&FF
 STA F_DCOL+1
 STA f_mrt+1            \ (and no cells f_mark erased: its text shows nothing,
 STZ f_mrb+1            \ right for any F_TCH: the text map, frame.asm)
 STZ F_BACK             \ buffer 1 is on show: draw into buffer 0 first
 STZ GFLIP
 LDA #&80
 STA GMODE
 RTS


\ ------------------------------------------------------------------------------
\ Zero page used by the frame layer during F_FRAME (saved and restored along
\ with the rasteriser's &06-&27): Elite's XX2/K3/K4 workspace, dead between
\ main-loop iterations.
\ ------------------------------------------------------------------------------


\ ------------------------------------------------------------------------------
\ Buffer-dependent operands: f_bufpatch points this layer's accesses to the
\ current buffer's rasteriser arrays (R_DIRTYLb etc.).
\ ------------------------------------------------------------------------------

MACRO FPATCH lab, a0, a1
 LDA F_BACK
 BNE P%+14
 LDA #LO(a0)
 STA lab+1
 LDA #HI(a0)
 STA lab+2
 BNE P%+12
 LDA #LO(a1)
 STA lab+1
 LDA #HI(a1)
 STA lab+2
ENDMACRO

.f_bufpatch             \ (each array's two copies differ only in the high byte)
 LDX F_BACK
 LDA fbp_dl,X
 STA fdc_dl1+2
 STA fdc_dl2+2
 STA ft_wd1+2
 STA fsw_d1+2
 LDA fbp_dr,X
 STA fdc_dr1+2
 STA fdc_dr2+2
 STA ft_wd2+2
 STA fsw_d2+2
 LDA fbp_ol,X
 STA fdc_ol+2
 LDA fbp_or,X
 STA fdc_or+2
 RTS
.fbp_dl EQUB HI(R_DIRTYL0), HI(R_DIRTYL1)
.fbp_dr EQUB HI(R_DIRTYR0), HI(R_DIRTYR1)
.fbp_ol EQUB HI(R_DISCL0), HI(R_DISCL1)
.fbp_or EQUB HI(R_DISCR0), HI(R_DISCR1)
ASSERT LO(R_DIRTYL0) = LO(R_DIRTYL1) AND LO(R_DIRTYR0) = LO(R_DIRTYR1)
ASSERT LO(R_DISCL0) = LO(R_DISCL1) AND LO(R_DISCR0) = LO(R_DISCR1)

\ ------------------------------------------------------------------------------
\ The disc layer
\ ------------------------------------------------------------------------------

\ f_discs: choose which of the sun and planet is the incremental disc layer
\ (the bigger one), fill R_NDISCL/R and run R_DISCROWS. f_disc2 then draws the
\ other, if any, behind it (R_DISC2).

.f_discs
 LDA #0
 STA f_lay
 STA f_sec
 LDA GSUNON             \ sun drawn by SUN this frame?
 BEQ fds2
 LDA F_PLON
 BEQ fds1               \ sun only
 LDA GSUNR
 CMP F_PLR
 BCC fds3               \ planet bigger: planet layer, sun secondary
 LDA #2
 STA f_sec              \ sun layer, planet secondary
.fds1
 LDA #1
 STA f_lay
 BNE fds4
.fds2
 LDA F_PLON
 BEQ fds4               \ neither
 LDA #2
 STA f_lay
 BNE fds4
.fds3
 LDA #2
 STA f_lay
 LDA #1
 STA f_sec
.fds4
 LDA f_lay              \ if the layer's colour differs from what this buffer
 LDX F_BACK             \ holds, nothing of the old disc is intact: fold the
 CMP F_DCOL,X           \ old disc spans into the old dirty extents
 BEQ fds5
 STA F_DCOL,X
 JSR f_discdirty
.fds5
 LDA f_lay
 BEQ fds9
 CMP #1
 BEQ fds6
 LDA #FC_PLANE          \ (the planet's colour A: the beach ball's sea)
 STA R_DCE
 LDA #FC_PLANO
 STA R_DCO
 JSR f_plrows           \ planet spans into R_NDISCL/R, R_NDT/R_NDB
 JSR f_bounds           \ and its surface detail as colour boundaries
 CLC                    \ (C clear: the disc layer, R_DISCROWS)
 JMP T_DISCROWS
.fds6
 LDA #FC_SUNE
 STA R_DCE
 LDA #FC_SUNO
 STA R_DCO
 JSR f_sunrows
 JSR f_nobounds
 CLC                    \ (C clear: the disc layer, R_DISCROWS)
 JMP T_DISCROWS
.fds9
 LDA #1                 \ no disc
 STA R_NDT
 LDA #0
 STA R_NDB
 CLC                    \ (C clear: the disc layer, R_DISCROWS)
 JMP T_DISCROWS

.f_lay EQUB 0           \ disc layer: 0 none, 1 sun, 2 planet
.f_sec EQUB 0           \ secondary disc

.f_discdirty            \ DIRTY[b][y] |= DISC[b][y] for all rows
 LDY #191
.fdd1
.fdc_ol
 LDA R_DISCL0,Y         \ patched
.fdc_dl1
 CMP R_DIRTYL0,Y        \ patched
 BCS fdd2
.fdc_dl2
 STA R_DIRTYL0,Y        \ patched
.fdd2
.fdc_or
 LDA R_DISCR0,Y         \ patched
.fdc_dr1
 CMP R_DIRTYR0,Y        \ patched
 BCC fdd3
.fdc_dr2
 STA R_DIRTYR0,Y        \ patched
.fdd3
 DEY
 CPY #&FF
 BNE fdd1
 RTS

\ f_sunrows / f_plrows: a disc's spans into R_NDISCL/R and R_NDT/R_NDB, from
\ its centre (16-bit screen coordinates) and radius (8-bit), using a cached
\ half-width table per disc (rebuilt only when the radius changes)

.f_sunrows
 LDA F_SUX
 STA f_cx
 LDA F_SUX+1
 STA f_cxh
 LDA F_SUY
 STA f_cy
 LDA F_SUY+1
 STA f_cy+1
 LDA GSUNR
 STA f_r
 CMP f_hw2r
 BEQ fsu1
 STA f_hw2r
 LDA #LO(F_HW2)
 STA fhw_st+1
 LDA #HI(F_HW2)
 STA fhw_st+2
 JSR f_hwbuild
.fsu1
 LDA #LO(F_HW2)
 STA fpr_ld+1
 STA fpr_ld2+1
 LDA #HI(F_HW2)
 STA fpr_ld+2
 STA fpr_ld2+2
 JMP f_discspans

.f_plrows
 LDA F_PLX
 STA f_cx
 LDA F_PLX+1
 STA f_cxh
 LDA F_PLY
 STA f_cy
 LDA F_PLY+1
 STA f_cy+1
 LDA F_PLR
 STA f_r
 CMP f_hwr
 BEQ fpr1
 STA f_hwr
 LDA #LO(F_HW)
 STA fhw_st+1
 LDA #HI(F_HW)
 STA fhw_st+2
 JSR f_hwbuild
.fpr1
 LDA #LO(F_HW)
 STA fpr_ld+1
 STA fpr_ld2+1
 LDA #HI(F_HW)
 STA fpr_ld+2
 STA fpr_ld2+2
 JMP f_discspans

.fds_none
 LDA #1
 STA R_NDT
 STZ R_NDB
 RTS

.f_discspans            \ rows of the disc (f_cx, f_cy, f_r) within the window
                        \ (every exit sets R_NDT and R_NDB)
 LDA f_cy               \ fz_p = top row = cy - r, fz_q = bottom row = cy + r
 SEC
 SBC f_r
 STA fz_p
 LDA f_cy+1
 SBC #0
 STA fz_p+1
 LDA f_cy
 CLC
 ADC f_r
 STA fz_q
 LDA f_cy+1
 ADC #0
 STA fz_q+1
 BMI fds_none           \ bottom above the screen
 BNE fdx1               \ bottom below row 255: clamp
 LDA fz_q
 CMP R_CB
 BCC fdx2
.fdx1
 LDA R_CB
 STA fz_q
.fdx2
 LDA fz_p+1             \ top
 BMI fdx3               \ above row 0: clamp
 BNE fds_none           \ below row 255
 LDA fz_p
 CMP R_CT
 BCS fdx4
.fdx3
 LDA R_CT
 STA fz_p
.fdx4
 LDA fz_q               \ empty if top > bottom
 CMP fz_p
 BCC fds_none
 STA R_NDB
 LDA fz_p
 STA R_NDT
 SEC                    \ d = top - cy (16-bit signed, |d| <= r)
 SBC f_cy
 STA fz_t
 LDA #0
 SBC f_cy+1
 STA fz_u
 LDA f_cxh             \ fast path if the whole disc is inside the window
 BEQ fds_z              \ horizontally: cx - r >= CL and cx + r <= CR
 LDA #&80               \ high byte of cx nonzero: fpr_b1 and fpr_b2 become
 BRA fds_pat            \ BRA
.fds_z
 LDA f_cx
 SEC
 SBC f_r
 BCC fds_slow
 CMP R_CL
 BCC fds_slow
 LDA f_cx
 CLC
 ADC f_r
 BCS fds_slow
 SBC R_CR               \ (C = 0) borrow iff cx + r <= CR
 BCS fds_slow
 JMP fds_fast           \ (the fast path follows the slow one, out of
                        \ branch range)
.fds_slow               \ (the disc crosses the window's side, or the screen's)
 LDA #&89               \ high byte of cx zero: fpr_b1 and fpr_b2 become
.fds_pat                \ BIT #imm (no-ops: they keep X and C)
 STA fpr_b1
 STA fpr_b2
 LDY R_NDT
 LDX #&E8               \ X = |d| through the loop, stepped by fpr_id: INX
 LDA fz_u               \ (&E8) if d >= 0, else DEX (&CA) until d reaches 0
 BPL fpr4
 EOR fz_t               \ (d < 0: fz_u = &FF as |d| <= r <= 255, so A = NOT d)
 INC A
 STA fz_t
 LDX #&CA
.fpr4
 STX fpr_id
 LDX fz_t               \ |d|
.fpr2
.fpr_ld2
 LDA F_HW,X             \ patched: half-width
 STA fz_n
 CLC                    \ right = cx + n, clamped: < CL (or
.fpr_cx
 ADC #0                 \ patched: f_cx (the low byte of cx lives in this
                        \ operand); negative): empty; > CR (or > 255): CR
.fpr_b1
 BRA fpr10              \ patched: BRA if the high byte of cx is nonzero (out
                        \ of line), else BIT #imm (a no-op)
 BCS fpr5               \ high byte of cx + n = 1
.fpr11
 CMP R_CL
 BCC fpr8
 CMP R_CR
 BCC fpr6
.fpr5
 LDA R_CR
.fpr6
 STA R_NDISCR,Y
 LDA f_cx               \ left = cx - n: negative: CL; > 255 or > CR: empty;
 SEC                    \ < CL: CL
 SBC fz_n
.fpr_b2
 BRA fpr13              \ patched as fpr_b1
 BCC fpr3               \ high byte of cx - n = -1
.fpr14
 CMP R_CR
 BEQ fpr7
 BCS fpr8
 CMP R_CL
 BCS fpr7
.fpr3
 LDA R_CL
 BRA fpr7
.fpr10                  \ right, A = low byte, C = carry, high byte of cx
 STA fz_t               \ nonzero (X = |d| kept; fz_t is free in the loop)
 LDA f_cxh
 ADC #0                 \ high byte of cx + n
 BMI fpr8               \ minus: empty
 BNE fpr5               \ plus: CR
 LDA fz_t               \ zero
 BRA fpr11
.fpr17
 LDA fz_t               \ (fpr13: high byte zero)
 BRA fpr14
.fpr13                  \ left, A = low byte, C = no borrow, high byte of cx
 STA fz_t               \ nonzero
 LDA f_cxh
 SBC #0                 \ high byte of cx - n
 BEQ fpr17
 BMI fpr3               \ (plus: empty)
.fpr8
 LDA #0                 \ empty row: R = 0, L = 255
 STA R_NDISCR,Y
 DEC A
.fpr7
 STA R_NDISCL,Y
.fpr9
.fpr_id
 INX                    \ patched: DEX while d < 0; when |d| reaches 0
 BNE fpr16              \ step up from then on (fz_u is not kept)
 LDA #&E8
 STA fpr_id
.fpr16
 CPY fz_q               \ (= R_NDB: stored from fz_q at fdx4, unchanged here)
 INY
 BCC fpr2
 RTS

.fds_fast               \ here r <= 127 and |d| <= r, so d fits a signed byte
 LDA f_cx
 STA fsy_cr+1           \ patch cx and 2cx + 1 (mod 256) into both loops
 STA fdf_cr+1
 SEC
 ROL A
 STA fsy_cl+1
 STA fdf_cl+1
 LDA fz_q               \ A = B - T (B = R_NDB = fz_q, T = R_NDT = fz_p)
 SEC
 SBC fz_p               \ (C = 1 after: B >= T)
 LDY fz_t               \ Y = d = T - cy (|d| <= 127, so N = sign of d)
 BPL fdd                \ d >= 0: all rows at or below cy
 CLC
 ADC fz_t               \ A = b = B - cy, C = 1 iff b >= 0
 BCS fdsym              \ b >= 0: cy is in T..B
                        \ b < 0 (C = 0): rows T..B are cy - k for k = -b..a
 EOR #&FF               \ (a = -d), walked up from B
 TAY
 INY                    \ Y = -b
 LDX fz_q               \ X = B
 LDA #2
 SBC fz_t               \ (C = 0) A = a + 1 (C = 0 after)
 STA fdf_cp+1
 LDA #&CA               \ DEX
 BNE fdxs
.fdd                    \ d >= 0 (A = B - T, C = 1, Y = d): rows T..B are cy + k
 ADC fz_t               \ for k = d..b; A = B - T + d + 1 = b + 1 <= 128 (C = 0)
 STA fdf_cp+1
 LDX fz_p               \ X = T
 LDA #&E8               \ INX
.fdxs
 STA fdf_st
.fdf1                   \ X = row, Y = k = |row - cy|, C = 0 here
.fpr_ld
 LDA F_HW,Y             \ patched: half-width table
.fdf_cr
 ADC #0                 \ patched: cx (A = cx + n <= cx + r <= 255, so C = 0)
 STA R_NDISCR,X
 EOR #&FF
.fdf_cl
 ADC #0                 \ patched: 2cx + 1 (A = 2cx + 1 + ~(cx + n) = cx - n)
 STA R_NDISCL,X
.fdf_st
 INX                    \ patched: INX (rows below cy) or DEX (rows above cy)
 INY
.fdf_cp
 CPY #0                 \ patched: last k, plus 1 (C = 0 until then)
 BNE fdf1
 RTS

.fdsym                  \ (A = b, C = 1; a = cy - T = -d > 0)
 TAY                    \ Y = b
 CLC
 ADC fz_t               \ A = b - a, C = 1 iff b >= a
 BEQ fdse
 BCC fdsu
 INY                    \ b > a: rows cy - k and cy + k together for k = 0..a,
 STY fdf_cp+1           \ then rows cy + k for k = a + 1..b
 LDA #&E8               \ INX
 STA fdf_st
 LDA #1
 SBC fz_t               \ (C = 1) A = a + 1 (C = 0 after)
 STA fsy_cp+1
 ADC f_cy               \ A = cy + a + 1 <= B + 1 (C = 0 after)
 STA fsx_x+1
 LDA #&A2               \ LDX #
 BRA fds_c
.fdsu                   \ b < a (C = 0): rows cy - k and cy + k together for
 INY                    \ k = 0..b, then rows cy - k for k = b + 1..a
 STY fsy_cp+1           \ (C = 0 still)
 LDA #2
 SBC fz_t               \ (C = 0) A = a + 1
 STA fdf_cp+1
 LDA #&CA               \ DEX
 STA fdf_st
 LDA #&89               \ BIT # (X is already row cy - b - 1)
 BRA fds_c
.fdse                   \ b = a (C = 1, Y = a): rows cy - k and cy + k for k = 0..a
 INY
 STY fsy_cp+1           \ a + 1
 LDA #&60               \ RTS
.fds_c
 STA fsx_x              \ what follows the symmetric loop
 LDA fpr_ld+2           \ the symmetric loop reads n(k) at table + k (page
 STA fsy_ld+2           \ aligned: no page crossing)
 LDA f_cy               \ X = row cy - k, Y = k, from k = 0; rows cy + k are
 TAX                    \ written at (table + cy) + k
 CLC
 ADC #LO(R_NDISCR)      \ (cy <= R_CB = 191: no carry, see the ASSERT)
 STA fsy_sr+1
 TXA
 ADC #LO(R_NDISCL)
 STA fsy_sl+1
 LDA #HI(R_NDISCL)
 ADC #0                 \ (C = 0 after)
 STA fsy_sl+2
 LDY #0
.fsyl                   \ C = 0 here
.fsy_ld
 LDA F_HW,Y             \ patched: half-width table (high byte)
.fsy_cr
 ADC #0                 \ patched: cx
 STA R_NDISCR,X
.fsy_sr
 STA R_NDISCR,Y         \ patched: R_NDISCR + cy (low byte)
 EOR #&FF
.fsy_cl
 ADC #0                 \ patched: 2cx + 1
 STA R_NDISCL,X
.fsy_sl
 STA R_NDISCL,Y         \ patched: R_NDISCL + cy
 DEX
 INY
.fsy_cp
 CPY #0                 \ patched: last k, plus 1 (C = 0 until then)
 BNE fsyl
.fsx_x
 LDX #0                 \ patched: LDX #first tail row, BIT # (no-op) or RTS
 CLC                    \ (Y = k of the first tail row already)
 JMP fdf1
 ASSERT LO(R_NDISCR) + 191 < 256 AND LO(F_HW) = LO(F_HW2)

f_cx = fpr_cx + 1       \ (the operand of ADC # in the slow disc loop)
.f_cxh EQUB 0           \ high byte of cx
 EQUB 0, 0              \ (spare: keeps the layout after this unchanged)
.f_cy EQUW 0
.f_r  EQUB 0
.f_hwr EQUB 0           \ radius F_HW was built for (0 = none)
.f_hw2r EQUB 0          \ radius F_HW2 was built for

\ f_hwbuild: table[d] = floor(sqrt(r*r - d*d)) for d = 0..r (r = f_r, table
\ patched into fhw_st), by walking x down from r while x*x + d*d > r*r
\ (error e = r*r - d*d - x*x, 16-bit signed)

.f_hwbuild
 LDX f_r                \ x = r
 LDA #0
 STA fz_p               \ e = 0 (d = 0, x = r)
 STA fz_p+1
 LDY #0                 \ d
.fhw1
 TXA
.fhw_st
 STA F_HW,Y             \ patched
 CPY f_r
 BEQ fhw9
 TYA                    \ e -= 2d + 1 ; d++
 ASL A
 STA fz_t
 LDA #0
 ROL A
 STA fz_u
 LDA fz_p
 CLC                    \ (C = 0: SBC takes the + 1 too)
 SBC fz_t
 STA fz_p
 LDA fz_p+1
 SBC fz_u
 STA fz_p+1
 INY
.fhw2
 LDA fz_p+1             \ while e < 0: e += 2x - 1 ; x--
 BPL fhw1
 TXA
 ASL A
 STA fz_t
 LDA #0
 ROL A
 STA fz_u
 LDA fz_t
 SEC
 SBC #1
 STA fz_t
 BCS P%+4
 DEC fz_u
 LDA fz_p
 CLC
 ADC fz_t
 STA fz_p
 LDA fz_p+1
 ADC fz_u
 STA fz_p+1
 DEX
 JMP fhw2
.fhw9
 RTS

\ f_disc2: the secondary disc (both the sun and the planet on screen: more
\ often since the sun near the planet is drawn too, gfx-ssun.asm). It is the
\ smaller disc, and the sun and the planet are the same size (PLANET's radius
\ 24576 / z for both), so it is the further: R_DISC2 (gfx-raster_disc2.asm)
\ draws what the layer's span (this buffer's R_DISCL/R, as T_DISCROWS has
\ just left them) leaves of each of its rows, incrementally, as the layer is
\ drawn. With no secondary disc it is called only to erase what this buffer
\ still holds of one (R_S2T: its rows). It fills the rows R_DISC2 reads
\ beyond the new ones (the old rows) with empty spans.

.f_disc2
 LDA f_sec
 BEQ fd29
 CMP #1
 BEQ fd21
 LDA #FC_PLANE          \ (the planet's colour A: the beach ball's sea)
 STA R_COLE
 LDA #FC_PLANO
 STA R_COLO
 JSR f_plrows
 BRA fd22
.fd21
 LDA #FC_SUNE
 STA R_COLE
 LDA #FC_SUNO
 STA R_COLO
 JSR f_sunrows
.fd22                   \ R_DISC2 reads the new spans over this buffer's old
 LDX F_BACK             \ rows too (R_S2T..R_S2B): empty there, outside
 LDA R_S2B,X            \ NDT..NDB (rows lo .. hi: old + new)
 CMP R_NDB
 BCS fd23
 LDA R_NDB
.fd23
 STA fz_t               \ hi
 LDY R_S2T,X
 CPY R_NDT
 BCC fd24
 LDY R_NDT              \ lo
.fd24
 CPY R_NDT              \ lo .. NDT-1
 BCS fd26
 CPY fz_t
 BEQ fd25
 BCS fd27
.fd25
 LDA #&FF
 STA R_NDISCL,Y
 LDA #0
 STA R_NDISCR,Y
 INY
 BNE fd24
.fd26
 LDY R_NDB              \ NDB+1 .. hi
.fd2a
 CPY fz_t
 BCS fd27
 INY
 LDA #&FF
 STA R_NDISCL,Y
 LDA #0
 STA R_NDISCR,Y
 BRA fd2a
.fd27
 SEC                    \ (C set: R_DISC2)
 JMP T_DISCROWS
.fd29
 LDX F_BACK
 LDA R_S2T,X
 INC A
 BEQ fd28               \ (none in this buffer either)
 LDA #&FF               \ no rows (as R_DISC2 keeps them: 255, 0)
 STA R_NDT
 STZ R_NDB
 BRA fd22
.fd28
 RTS

\ ------------------------------------------------------------------------------
\ Lines, ships, dots, lasers, stars
\ ------------------------------------------------------------------------------

.f_setcol               \ A = fixed colour index -> R_COLE/R_COLO
 TAX
 LDA F_CPE,X
 STA R_COLE
 LDA F_CPO,X
 STA R_COLO
 RTS

.f_line8                \ line from (fz_t, fz_u) to (X, Y), 8-bit coordinates
 STX R_X1
 STY R_Y1
 LDA fz_t
 STA R_X0
 LDA fz_u
 STA R_Y0
 LDA #0
 STA R_X0+1
 STA R_Y0+1
 STA R_X1+1
 STA R_Y1+1
 JMP T_LINE

.f_lines
 BIT f_bomb             \ the bomb's bolt, if any, first (as recorded before
 BPL fln3               \ the beams, in the main loop's part 3)
 LDA #FC_PLINE
 JSR f_setcol
 LDA #0
 STA fz_i
.fln2
 LDX fz_i
 LDA F_BX,X
 STA fz_t
 LDA F_BY,X
 STA fz_u
 LDY F_BY+1,X
 LDA F_BX+1,X
 TAX
 JSR f_line8
 INC fz_i
 LDA fz_i
 CMP #9
 BCC fln2
.fln3
 LDA F_NLINE            \ then the enemy beams
 BEQ fln9
 LDA #FC_ELASER
 JSR f_setcol
 LDA #0
 STA fz_i
.fln1
 LDX fz_i
 LDA F_LX0,X
 STA fz_t
 LDA F_LY0,X
 STA fz_u
 LDA F_LY1,X
 TAY
 LDA F_LX1,X
 TAX
 JSR f_line8
 INC fz_i
 LDX fz_i
 CPX F_NLINE
 BCC fln1
.fln9
 RTS

\ f_ships: insertion-sort the ships far to near, then draw each one (f_ship).

.f_ships
 LDX F_NSHIP
 BNE P%+3
 RTS
 LDX #0                 \ F_ORD = 0, 1, 2, ... sorted by z descending
.fss1
 TXA
 STA F_ORD,X
 INX
 CPX F_NSHIP
 BCC fss1
 LDX #1
.fss2
 CPX F_NSHIP
 BCS fss6
 LDA F_ORD,X            \ insert element X
 STA fz_t
 TXA
 TAY
.fss3
 DEY
 BMI fss5
 LDA F_ORD,Y            \ compare z(fz_t) > z(F_ORD,Y)? then shift
 STA fz_u
 STX fz_n
 LDX fz_t
 LDA F_SZL,X
 STA fz_i
 LDA F_SZH,X
 LDX fz_u
 CMP F_SZH,X
 BCC fss4               \ new is nearer: stop
 BNE fss7               \ new is further: shift
 LDA fz_i
 CMP F_SZL,X
 BCC fss4
 BEQ fss4
.fss7
 LDX fz_n
 LDA fz_u
 STA F_ORD+1,Y
 JMP fss3
.fss4
 LDX fz_n
.fss5
 INY                    \ the place after Y (Y = -1, &FF, when it goes first:
 LDA fz_t               \ F_ORD+1,Y is then a page on, not F_ORD)
 STA F_ORD,Y
 INX
 BNE fss2
.fss6

 LDA #0
 STA fz_i
.fss8
 LDX fz_i
 CPX F_NSHIP
 BCS fss9
 LDA F_ORD,X
 JSR f_ship
 INC fz_i
 BNE fss8
.fss9
 RTS

.f_si   EQUB 0          \ ship index being drawn
.f_nf   EQUB 0
.f_f    EQUB 0          \ face number
.f_x4   EQUB 0
.f_cnt  EQUB 0          \ item counter (details, fins)
.f_k    EQUB 0          \ fin pass: number of its two faces visible

\ f_ship: draw one ship. Every face is flat-shaded (FC_FACETAB: n + 16 * hue
\ ramp, unit normal, n XX3 offsets; the record's XX2 copy holds the face's
\ level, gfx-light.asm, and f_col its ramp entry). The visible faces are drawn,
\ then the surface details over them and the fins (see faces.asm for the
\ order); not a fin with neither of its faces visible, behind the body, as LL9
\ has not projected its vertex on the body edge (the missile's list only those
\ two faces), and XX3 holds whatever was there before.

.f_ship                 \ A = ship index
 TAX
 STX f_si
 LDY F_STYP,X
 LDA F_SX4,X            \ skip ships whose polygon vertices may be stale
 STA f_x4
 CMP FC_MINVIS,Y
 BEQ P%+5
 BCC P%+3
 RTS
 TYA
 ASL A
 TAY
 LDA FC_FACETAB,Y
 STA fz_ft
 LDA FC_FACETAB+1,Y
 STA fz_ft+1
 LDA FC_DETTAB,Y        \ fins, then details
 STA fz_dt
 LDA FC_DETTAB+1,Y
 STA fz_dt+1
 LDA F_SPL,X            \ XX2 copy, then XX3 copy
 STA fz_dl
 LDA F_SPH,X
 STA fz_dl+1
 LDA F_SNF,X
 STA f_nf
 CLC
 ADC fz_dl
 STA fz_v3
 LDA fz_dl+1
 ADC #0
 STA fz_v3+1
 LDA fz_v3              \ the vertex gather's operands: XX3 copy + 0..3
 STA fsh_x0+1
 LDA fz_v3+1
 STA fsh_x0+2
 FOR k, 1, 3
  CLC
  LDA fz_v3
  ADC #k
  STA fsh_x0+1+6*k
  LDA fz_v3+1
  ADC #0
  STA fsh_x0+2+6*k
 NEXT

 JSR f_behind           \ hidden behind the planet?
 BCC P%+3
 RTS
.fsh_nf0                \ (past f_behind: harness/mstation.mjs)

 LDA #0
 STA f_f
 BEQ fsh_face
.fsh_skip               \ hidden face: just step over its entry
 LDY #0
 LDA (fz_ft),Y
 AND #15
 STA fz_n
 JMP fsh_next
.fsh_face
 LDY f_f
 CPY f_nf
 BCC P%+5
 JMP fsh_done
 LDA (fz_dl),Y          \ visibility
 BEQ fsh_skip
 STA fz_t
 LDY #0
 LDA (fz_ft),Y          \ n + 16 * ramp
 AND #15
 STA fz_n
 CMP #3
 BCC fsh_next
 STA R_PN
 LDA fz_t               \ the face's level
 AND #31
 TAX
 LDA (fz_ft),Y          \ its hue ramp
 LSR A
 LSR A
 LSR A
 LSR A
 JSR f_col              \ lit: R_COLE, R_COLO, R_COL2, R_COL3
 CLC                    \ the face's vertex offsets at fz_ft + 4
 LDA fz_ft
 ADC #4
 STA fsh_o+1
 LDA fz_ft+1
 ADC #0
 STA fsh_o+2
 LDX #0                 \ gather the vertices
.fsh_v
.fsh_o
 LDY &FFFF,X            \ XX3 offset (patched)
.fsh_x0
 LDA &FFFF,Y            \ (patched: the XX3 copy + 0..3)
 STA R_PXL,X
.fsh_x1
 LDA &FFFF,Y
 STA R_PXH,X
.fsh_x2
 LDA &FFFF,Y
 STA R_PYL,X
.fsh_x3
 LDA &FFFF,Y
 STA R_PYH,X
 ASSERT fsh_x1 = fsh_x0 + 6 AND fsh_x2 = fsh_x0 + 12 AND fsh_x3 = fsh_x0 + 18
 INX
 CPX fz_n
 BCC fsh_v
 BIT fz_t               \ far faces (XX2 = 255, bit 6 of the copy: Elite skipped
 BVC fsh_draw           \ the normal test) are culled by their winding on
                        \ screen, in the ship's handedness (bit 5)
 JSR f_winding
 BCC fsh_next
.fsh_draw
 JSR T_POLY
.fsh_next
 LDA fz_n               \ next face list entry: n + 4 bytes on
 CLC
 ADC #4
 ADC fz_ft
 STA fz_ft
 BCC P%+4
 INC fz_ft+1
 INC f_f
 JMP fsh_face

.fsh_done               \ details: skip the fins (7 bytes each) to the count
 LDY #0
 LDA (fz_dt),Y
 STA f_cnt
 ASL A
 ASL A
 ASL A
 SEC
 SBC f_cnt              \ 7 * count (C = 1: no borrow)
 SEC
 ADC fz_dt
 STA fz_q
 LDA fz_dt+1
 ADC #0
 STA fz_q+1
 LDA (fz_q),Y
 BEQ fdt8
 STA f_cnt
 INC fz_q
 BNE fdt1
 INC fz_q+1
.fdt1
 JSR f_item
 DEC f_cnt
 BNE fdt1
.fdt8
 LDY #0                 \ the other fins: one face visible, then both (the
 LDA (fz_dt),Y          \ fin nearest the viewer)
 BEQ fdt9
 LDA #1
 JSR f_fins
 LDA #2
 JMP f_fins
.fdt9
 RTS

\ f_item: draw the detail at (fz_q) if it is within its visibility distance
\ and face1 or face2 is visible: n = 2 a line, else a polygon (culled by its
\ winding if XX2 = 255). Then fz_q -> the next item.

.f_item
 LDY #0
 LDA (fz_q),Y           \ visibility distance
 CMP f_x4
 BCC fit8
 INY
 LDA (fz_q),Y           \ face1 + 16 * face2
 AND #15
 TAY
 LDA (fz_dl),Y
 BNE fit1
 LDY #1
 LDA (fz_q),Y
 LSR A
 LSR A
 LSR A
 LSR A
 TAY
 LDA (fz_dl),Y
 BEQ fit8
.fit1
 STA fz_t
 JSR f_itemv            \ colour and vertices
 LDA fz_n
 CMP #3
 BCC fit3
 STA R_PN
 BIT fz_t               \ (XX2 = 255: cull by winding)
 BVC fit2
 JSR f_winding
 BCC fit8
.fit2
 JSR f_poly2            \ (T_POLY, and the docking slot's outline)
 JMP fit8
.fit3
 LDA R_PXL              \ a line
 STA R_X0
 LDA R_PXH
 STA R_X0+1
 LDA R_PYL
 STA R_Y0
 LDA R_PYH
 STA R_Y0+1
 LDA R_PXL+1
 STA R_X1
 LDA R_PXH+1
 STA R_X1+1
 LDA R_PYL+1
 STA R_Y1
 LDA R_PYH+1
 STA R_Y1+1
 JSR T_LINE
.fit8
 LDY #3                 \ next item: 4 + n bytes on
 LDA (fz_q),Y
 CLC
 ADC #4
 ADC fz_q
 STA fz_q
 BCC P%+4
 INC fz_q+1
 RTS

\ f_itemv: the item at (fz_q): its colour (lit at the brighter of its two
\ faces' levels, or unlit), fz_n = n, R_PX/R_PY[0..n-1]

.f_itemv
 LDY #1                 \ face1 + 16 * face2: the brighter level (a hidden
 LDA (fz_q),Y           \ face's is 0)
 AND #15
 TAY
 LDA (fz_dl),Y
 AND #31
 STA fz_u
 LDY #1
 LDA (fz_q),Y
 LSR A
 LSR A
 LSR A
 LSR A
 TAY
 LDA (fz_dl),Y
 AND #31
 CMP fz_u
 BCS P%+4
 LDA fz_u
 TAX
 LDY #2
 LDA (fz_q),Y           \ colour byte: a hue ramp, or &80 + an unlit colour
 JSR f_col              \ R_COLE, R_COLO, R_COL2, R_COL3
 LDY #3
 LDA (fz_q),Y
 STA fz_n
 INY
 LDX #0
.fiv1
 STY fz_u
 LDA (fz_q),Y           \ XX3 offset
 TAY
 LDA (fz_v3),Y
 STA R_PXL,X
 INY
 LDA (fz_v3),Y
 STA R_PXH,X
 INY
 LDA (fz_v3),Y
 STA R_PYL,X
 INY
 LDA (fz_v3),Y
 STA R_PYH,X
 LDY fz_u
 INY
 INX
 CPX fz_n
 BCC fiv1
 RTS

\ f_fins: A = k (1 or 2): draw the fins (two-sided triangles standing on the
\ body edge between face1 and face2) with exactly k of those two faces
\ visible. A fin with one or both visible is in front of the body, and only
\ the fin on the corner facing the viewer (both visible) can hide another fin.
\ (One with neither visible is behind the body and is not drawn: f_ship.)

.f_fins
 STA f_k
 LDY #0
 LDA (fz_dt),Y
 STA f_cnt
 LDA fz_dt
 CLC
 ADC #1
 STA fz_q
 LDA fz_dt+1
 ADC #0
 STA fz_q+1
.ffi1
 LDY #0
 LDA (fz_q),Y           \ visibility distance
 CMP f_x4
 BCC ffi8
 LDX #0                 \ X = number of the two faces visible
 INY
 LDA (fz_q),Y
 AND #15
 TAY
 LDA (fz_dl),Y
 BEQ P%+3
 INX
 LDY #1
 LDA (fz_q),Y
 LSR A
 LSR A
 LSR A
 LSR A
 TAY
 LDA (fz_dl),Y
 BEQ P%+3
 INX
 CPX f_k
 BNE ffi8
 JSR f_itemv
 LDA #3
 STA R_PN
 JSR T_POLY
.ffi8
 LDA fz_q               \ next fin: 7 bytes on
 CLC
 ADC #7
 STA fz_q
 BCC P%+4
 INC fz_q+1
 DEC f_cnt
 BNE ffi1
 RTS

\ f_col: A = a face's or item's colour byte, X = the level (0..31): the
\ colour R_COLE, R_COLO, R_COL2, R_COL3 (rows y AND 3 = 0..3). A = 0..8: entry
\ X of that hue ramp (gfx-light6.asm), a 4x4 dither packed as w = a + 32 b +
\ 1024 c, whose rows are H[a] EOR H[c] EOR HL[b] (H = HL AND &F0); A = &80 +
\ k: the unlit colour k (black, cyan, magenta, yellow).

.fc_fix
 AND #3
 TAY
 LDA LT_FIX,Y
 STA R_COLE
 STA R_COLO
 STA R_COL2
 STA R_COL3
 RTS
.f_col
 TAY
 BMI fc_fix
 LDA LT_RL,Y
 STA fcl+1
 CLC
 ADC #32
 STA fch+1
 LDA LT_RH,Y
 STA fcl+2
 ADC #0
 STA fch+2
.fch
 LDA &FFFF,X            \ (patched) w's high byte: c = hi >> 2
 STA fc_hi
 LSR A
 LSR A
 TAY
.fcl
 LDA &FFFF,X            \ (patched) w's low byte: a = lo AND 31
 STA fc_lo
 AND #31
 TAX
 FOR r, 0, 3            \ H[a] EOR H[c]
  LDA LT_HL0+17*r,X
  EOR LT_HL0+17*r,Y
  AND #&F0
  STA fc_row+r
 NEXT
 LDA fc_hi              \ b = (hi AND 3) * 8 + lo DIV 32
 AND #3
 ASL fc_lo
 ROL A
 ASL fc_lo
 ROL A
 ASL fc_lo
 ROL A
 TAY
 LDA LT_HL0,Y           \ EOR HL[b]
 EOR fc_row
 STA R_COLE
 LDA LT_HL0+17,Y
 EOR fc_row+1
 STA R_COLO
 LDA LT_HL0+34,Y
 EOR fc_row+2
 STA R_COL2
 LDA LT_HL0+51,Y
 EOR fc_row+3
 STA R_COL3
 RTS
ASSERT LT_HL1 = LT_HL0 + 17 AND LT_HL2 = LT_HL0 + 34 AND LT_HL3 = LT_HL0 + 51

.fc_lo  EQUB 0
.fc_hi  EQUB 0
.fc_row SKIP 4

.f_dots
 LDA #0
 STA fz_i
.fdo2
 LDX fz_i
 CPX F_NDOT
 BCS fdo8
 LDA F_DC,X
 BPL fdo3
 AND #&7F               \ a ship type: its dot colour
 TAY
 LDA FC_DOTE,Y
 STA R_COLE
 LDA FC_DOTO,Y
 STA R_COLO
 JMP fdo4
.fdo3
 JSR f_setcol
.fdo4
 LDX fz_i
 LDA F_DS,X
 PHA
 LDA F_DY,X
 TAY
 LDA F_DX,X
 TAX
 PLA
 JSR T_DOT
 INC fz_i
 BNE fdo2
.fdo8
 RTS

\ f_lasers: our laser beams (LASLI's four lines from LASX,LASY to the bottom
\ of the view) and the sights

.f_lasers
 LDA GLASV
 BEQ fla2
 LDA #FC_LASER
 JSR f_setcol
 LDA LASX
 STA fz_t
 LDA LASY
 STA fz_u
 LDX #32
 LDY #2*Y-1
 JSR f_line8
 LDX #224
 LDY #2*Y-1
 JSR f_line8
 LDX #48
 LDY #2*Y-1
 JSR f_line8
 LDX #208
 LDY #2*Y-1
 JSR f_line8
.fla2
.fla9
 RTS

\ ------------------------------------------------------------------------------
\ Text overlay
\ ------------------------------------------------------------------------------

F_TCOL = &FF            \ text ink: yellow (logical colour 3)

\ f_rowptr: X = text row -> fz_p = F_TM + 32*row (X kept)

.f_rowptr
 TXA
 LSR A
 LSR A
 LSR A
 STA fz_p+1
 TXA
 ASL A
 ASL A
 ASL A
 ASL A
 ASL A
 CLC
 ADC #LO(F_TM)
 STA fz_p
 LDA fz_p+1
 ADC #HI(F_TM)
 STA fz_p+1
 RTS

\ f_text1: this buffer's text before the repair. The rows f_mark marked since
\ its last frame go into the rasteriser's dirty row range (R_MARKDIRTY with an
\ empty extent: only the rows). Then in each row that changed since its last
\ text steps (F_TCH), the cleared cells are erased, given back their
\ background by marking them dirty; one the other buffer has erased already
\ is forgotten (0). A row with no character is then done.

.f_text1
 LDX F_BACK
 LDY f_mrt,X
 CPY #192
 BCS ft10
 LDA #255
 STA R_XL
 STZ R_XR
 JSR T_MARKDIRTY        \ (keeps R_XL, R_XR)
 LDX F_BACK
 LDY f_mrb,X
 JSR T_MARKDIRTY
 LDX F_BACK
 LDA #255
 STA f_mrt,X
 STZ f_mrb,X
.ft10
 STZ f_rpn              \ (f_eor's replacements: a frame apart, not EOR's)
 LDA F_BACK             \ this buffer's bit in F_TCH, and the other's
 INC A
 STA f_tbit
 EOR #3
 STA f_obit
 LDX #23                \ rows 23..0 (each row is independent)
.ft11
 LDA F_TCH,X
 AND f_tbit
 BEQ ft18x
 STX fz_i
 JSR f_rowptr
 LDY #31
.ft12
 LDA (fz_p),Y           \ cleared (bit 7): erase it
 BPL ft17
 STY fz_u
 TYA
 ASL A
 ASL A
 ASL A
 STA R_XL
 ORA #7
 STA R_XR
 JSR f_clipx
 BCC ft16
 LDA fz_i               \ lines 8r..8r+7 within the clip window
 ASL A
 ASL A
 ASL A
 STA fz_t
 CLC
 ADC #8
 STA fz_n
 LDY fz_t
.ft13                   \ Y = row (T_MARKDIRTY preserves Y, R_XL, R_XR)
 CPY R_CT
 BCC ft14
 CPY R_CB
 BEQ P%+4
 BCS ft16
 JSR T_MARKDIRTY
.ft14
 INY
 CPY fz_n
 BCC ft13
.ft16
 LDY fz_u
 LDX fz_i
 LDA F_TCH,X            \ the other buffer erased it at its last frame: no
 AND f_obit             \ buffer shows it now
 BNE ft17
 LDA #0
 STA (fz_p),Y
.ft17
 DEY
 BPL ft12
 LDX fz_i
 LDA F_TMR,X            \ no character to draw: the row is done (else
 BNE ft18x              \ f_text2 finishes it)
 LDA F_TCH,X
 EOR f_tbit
 STA F_TCH,X
.ft18x
 DEX
 BPL ft11
 RTS

.f_clipx                \ clamp R_XL..R_XR to the clip window; C set if empty
 LDA R_XL
 CMP R_CL
 BCS P%+6
 LDA R_CL
 STA R_XL
 LDA R_XR
 CMP R_CR
 BCC P%+6
 LDA R_CR
 STA R_XR
 LDA R_XR
 CMP R_XL
 RTS                    \ C clear if XR < XL... invert below

\ f_text2: draw the characters of each row that changed since this buffer's
\ last text steps (F_TCH, whose bit is then cleared), and elsewhere those
\ whose pixels something overwrote this frame

.f_text2
 LDX #23                \ rows 23..0 (each row is independent)
.ft21
 LDA F_TMR,X            \ skip empty rows in a tight loop
 BNE ft2r
.ft29
 DEX
 BPL ft21
 RTS
.ft2r
 STX fz_i
 JSR f_rowptr
 LDA F_TCH,X            \ changed for this buffer: the whole row (then it is
 AND f_tbit             \ unchanged)
 BEQ ft2w
 EOR F_TCH,X
 STA F_TCH,X
 STZ f_wl
 LDY #31
 BRA ft27
.ft2w
 LDA #255               \ W = union of R_WL/R_WR and DIRTY over the 8 lines
 STA f_wl
 LDA #0
 STA f_wr
 TXA                    \ X = fz_i (f_rowptr preserves X)
 ASL A
 ASL A
 ASL A
 TAY
 ADC #8                 \ C = 0: row <= 23, so 8*row < 256
 STA fz_n
.ft22
 LDA R_WR,Y
 BEQ ft23
 CMP f_wr
 BCC P%+5
 STA f_wr
 LDA R_WL,Y
 CMP f_wl
 BCS ft23
 STA f_wl
.ft23
.ft_wd2
 LDA R_DIRTYR0,Y        \ patched
 BEQ ft24
 CMP f_wr
 BCC P%+5
 STA f_wr
.ft_wd1
 LDA R_DIRTYL0,Y        \ patched
 CMP f_wl
 BCS ft24
 STA f_wl
.ft24
 INY
 CPY fz_n
 BCC ft22
 LDA f_wr               \ as cell columns: wl DIV 8 .. wr DIV 8 (nothing
 BEQ ft2x               \ written in this row: WR = 0)
 LSR A
 LSR A
 LSR A
 TAY
 LDA f_wl
 LSR A
 LSR A
 LSR A
 STA f_wl
.ft27                   \ columns Y down to f_wl
 LDA (fz_p),Y
 BEQ ft28
 BMI ft28
 STY fz_u
 JSR f_glyph
 LDY fz_u
.ft28
 CPY f_wl
 BEQ ft2x
 DEY
 BRA ft27
.ft2x
 LDX fz_i
 JMP ft29

.f_wl EQUB 0
.f_wr EQUB 0

\ f_glyph: draw character A at column Y, text row fz_i, ink F_TCOL, only on
\ the glyph's pixels and only inside the clip window

.f_glyph
 BIT KMODE              \ K mode: the cell's rows are not kept
 BPL fgk
 PHA
 PHY
 LDA fz_i               \ (rows 8 * row .. + 7)
 ASL A
 ASL A
 ASL A
 PHA
 ADC #7                 \ (C = 0)
 TAX
 PLA
 JSR T_KROWS
 PLY
 PLA
.fgk
 SEC
 SBC #32                 \ glyph address = F_FONT + 8 * (char - 32)
 PHA
 ASL A
 ASL A
 ASL A
 ASSERT LO(F_FONT) = 0
 STA fgl1+1
 STA fglr+1             \ (the second load of the same row, for the low nibble)
 PLA
 LSR A
 LSR A
 LSR A
 LSR A
 LSR A
 CLC
 ADC #HI(F_FONT)
 STA fgl1+2
 STA fglr+2
 TYA                    \ screen: &4000 + row*&200 + 16*col
 ASL A
 ASL A
 ASL A
 ASL A
 STA fz_nm               \ low byte (16*col, may carry)
 ORA #8                  \ fz_v3 = fz_nm + 8, the right byte of the cell (low
 STA fz_v3               \ nibble 0: no carry; ORA keeps C for the ROL)
 LDA fz_i                \ high byte = 2*row + carry + &40 (row <= 23, so
 ROL A                   \ ROL leaves C = 0 and the ADC cannot carry)
 ADC #&40
 STA fz_nm+1
 STA fz_v3+1
 LDA #&FF               \ masks for the border columns (patched into the loop)
 STA fglm+1
 STA fgrm+1
 CPY #0
 BNE P%+7
 LDA #&33               \ pixels 0-1 of column 0 are the border
 STA fglm+1
 CPY #31
 BNE P%+7
 LDA #&CC               \ pixels 254-255 are the border
 STA fgrm+1
 ASSERT F_TCOL = &FF    \ ink is all-ones: (m AND ink) OR (NOT m AND s) = m OR s
 LDA fz_i               \ first line y = 8*row
 ASL A
 ASL A
 ASL A
 STA f_gy               \ (C = 0: row <= 23)
 LDA R_CT               \ the lines inside the clip window vertically:
 SBC f_gy               \ Y from max(0, R_CT - 8*row) (minus 1 here: the
 BCS P%+4               \ loop is entered at its INY)
 LDA #&FF
 TAY
 LDA R_CB               \ to min(7, R_CB - 8*row), none if R_CB < 8*row
 SEC
 SBC f_gy
 CLV                    \ V = 0 on exit, as before
 BCC fgl9
 CMP #7
 BCC P%+4
 LDA #7
 INC A
 STA fgl4+1
 BRA fgl3
.fgl0
.fgl1
 LDA F_FONT,Y           \ patched
 BEQ fgl3
 LSR A
 LSR A
 LSR A
 LSR A
 TAX
 LDA f_nib,X
.fglm
 AND #&FF               \ patched (left border mask)
 ORA (fz_nm),Y
 STA (fz_nm),Y
.fglr
 LDA F_FONT,Y           \ patched (the same address as fgl1)
 AND #15
 TAX
 LDA f_nib,X
.fgrm
 AND #&FF               \ patched (right border mask)
 ORA (fz_v3),Y
 STA (fz_v3),Y
.fgl3
 INY
.fgl4
 CPY #8                 \ patched (last line + 1)
 BCC fgl0
.fgl9
 RTS

.f_gy EQUB 0

.f_nib                  \ 4 font bits (bit 3 = leftmost) -> MODE 1 pixel mask
FOR n, 0, 15
 EQUB n * &11
NEXT

F_FONT = FONT% * 256      \ Master port: Elite's own font in main RAM (the same
ASSERT F_FONT + 768 <= &3000 \ 768 bytes), visible while ACCCON X is set


\ ------------------------------------------------------------------------------
\ Laser sights: four short arms about (128, 96), drawn after everything else
\ and only redrawn when something was written over them (like the text)
\ ------------------------------------------------------------------------------

SGX = 128
SGY = 96
SGIN = 11               \ arms run from SGIN to SGOUT pixels from the centre
SGOUT = 20

.F_SGS EQUB 0, 0        \ per buffer: the sights are drawn in it

\ f_sight1: sights shown in this buffer but no longer wanted: mark them dirty

.f_sight1
 LDX F_BACK
 LDA F_SGS,X
 BEQ fsg9
 LDA GSIGHT
 BNE fsg9
 LDA #0
 STA F_SGS,X
 LDA #SGX-SGOUT
 STA R_XL
 LDA #SGX+SGOUT
 STA R_XR
 LDY #SGY
 JSR T_MARKDIRTY
 LDA #SGX
 STA R_XL
 STA R_XR
 LDY #SGY-SGOUT
.fsg1
 STY fz_i
 JSR T_MARKDIRTY
 LDY fz_i
 INY
 CPY #SGY+SGOUT+1
 BCC fsg1
.fsg9
 RTS

\ f_wcov: does anything written this frame in row Y cover x = A .. X?
\ (R_WL/R_WR, or this buffer's new dirty extent). C set if so. Keeps Y.

.f_wcov
 STA fz_t
 STX fz_u
 LDA R_WR,Y             \ written: WL..WR (WR = 0: none)
 BEQ fwc2
 CMP fz_t
 BCC fwc2
 LDA fz_u
 CMP R_WL,Y
 BCS fwc9
.fwc2
.fsw_d2
 LDA R_DIRTYR0,Y        \ patched
 BEQ fwc8
 CMP fz_t
 BCC fwc8
 LDA fz_u
.fsw_d1
 CMP R_DIRTYL0,Y        \ patched
 BCS fwc9
.fwc8
 CLC
.fwc9
 RTS

.f_sight2
 LDA GSIGHT
 BEQ fsg9
 LDX F_BACK
 LDA F_SGS,X
 BEQ fsg3               \ not drawn yet
 LDY #SGY               \ overwritten anywhere?
 LDA #SGX-SGOUT
 LDX #SGX+SGOUT
 JSR f_wcov
 BCS fsg3
 LDA fsw_d2+2           \ this buffer's R_DIRTYR (f_bufpatch), high byte, +1
 INC A                  \ for the +SGY-SGOUT(-1) bases below
 STA fsg_or+2           \ (the low bytes are equal)
 STA fsg_or2+2
 ASSERT LO(R_DIRTYR0) = LO(R_DIRTYR1)
 ASSERT HI(R_DIRTYR0+SGY-SGOUT-1) = HI(R_DIRTYR0)+1 AND HI(R_DIRTYR1+SGY-SGOUT-1) = HI(R_DIRTYR1)+1
 ASSERT HI(R_DIRTYR0+SGY-SGOUT-1) = HI(R_DIRTYR0+SGY+SGOUT+1)   \ no page crossings in the loop
 LDY #2*SGOUT+1         \ two rows a pass: SGY-SGOUT+Y and SGY-SGOUT-1+Y, Y = 41,
.fsg2                   \ 39 .. 1 (row SGY+SGOUT+1 is read too; f_sgs ignores it).
 LDA R_WR+SGY-SGOUT,Y   \ f_wcov with A = X = SGX: WR, DIRTYR >= SGX (= &80,
.fsg_or                 \ so <> 0) <=> bit 7 set; usually neither is
 ORA R_DIRTYR0+SGY-SGOUT,Y \ patched (high byte, above)
 ORA R_WR+SGY-SGOUT-1,Y
.fsg_or2
 ORA R_DIRTYR0+SGY-SGOUT-1,Y \ patched (high byte, above)
 BMI fsgs
.fsg8
 DEY
 DEY
 BPL fsg2
 RTS
.fsgs
 JMP f_sgs              \ (frame_cold.asm: rare, and nothing after here moves)
.fsg3
 LDX F_BACK
 LDA #&FF
 STA F_SGS,X
 LDA F_CPE+FC_SIGHT     \ horizontal arms (row SGY is even)
 STA R_COLE
 STA R_COLO
 LDA #SGX-SGOUT
 STA R_XL
 LDA #SGX-SGIN
 STA R_XR
 LDY #SGY
 JSR T_SPAN
 LDA #SGX+SGIN
 STA R_XL
 LDA #SGX+SGOUT
 STA R_XR
 LDY #SGY
 JSR T_SPAN
 LDA F_CPE+FC_SIGHT     \ vertical arms: pixel 0 of byte column 32
 AND #&88               \ (loop-invariant colour bits)
 STA fz_t
 ASSERT SGY-SGOUT = 76 AND SGY-SGIN = 85   \ byte = &4000 + (y DIV 8)*&200 + &100 + (y MOD 8)
 ASSERT SGY+SGIN = 107 AND SGY+SGOUT = 116
 LDY #3                 \ rows 76..79: &5304..&5307
.fsg4
 LDA &5304,Y
 AND #&77
 ORA fz_t
 STA &5304,Y
 DEY
 BPL fsg4
 LDY #5                 \ rows 80..85: &5500..&5505
.fsg5
 LDA &5500,Y
 AND #&77
 ORA fz_t
 STA &5500,Y
 DEY
 BPL fsg5
 LDY #4                 \ rows 107..111: &5B03..&5B07, rows 112..116: &5D00..&5D04
.fsg6
 LDA &5B03,Y
 AND #&77
 ORA fz_t
 STA &5B03,Y
 LDA &5D00,Y
 AND #&77
 ORA fz_t
 STA &5D00,Y
 DEY
 BPL fsg6
 SEC                    \ C = 1 on exit, as before
 RTS

\ ------------------------------------------------------------------------------
\ Planet surface detail, filled: per-row colour boundaries for the disc layer
\ (R_NDN, R_NDX0-3: the disc alternates between colour A and colour B
\ at each boundary): circles on the planet's sphere, the beach ball's, the
\ craters' or the bands' (PF_HOOK, gfx-planet7.asm, makes them in game
\ context; PC_ROWS, gfx-merid.asm's circle engine, the rows), both in the
\ meridian window (bank 7).
\ ------------------------------------------------------------------------------

\ f_nobounds: rows R_NDT..R_NDB have no boundaries (plain disc)

.f_nobounds
 STZ R_NDF
 RTS

\ f_bounds: the planet's detail -> R_NDN/R_NDX0-3 for rows R_NDT..R_NDB
\ (which f_plrows has just set), and colour B (f_bcol)

.f_bounds
 JSR f_nobounds
 LDA R_NDT
 CMP R_NDB
 BEQ P%+4
 BCS fnb9
 BIT PF_CLS             \ the detail PF_HOOK made this frame (the beach
 BPL fnb9               \ ball, craters or bands): from the circle engine's
 JSR f_bcol             \ PC_ROWS
 JMP T_CAPS
.fnb9
 RTS

\ The planet's colours, every style's the beach ball's (pairs of bytes, even
\ rows and odd rows): colour A, the disc, its sea (FC_PLANE, FC_PLANO), and
\ colour B, its detail (the beach ball's land, the craters, the belt), green

FC_PLLE = &5F : FC_PLLO = &AF

\ f_bcol: R_NDF on and colour B

.f_bcol
 LDA #1
 STA R_NDF
 LDA #FC_PLLE
 STA R_DBE
 LDA #FC_PLLO
 STA R_DBO
 RTS

IF _PLANET_RINGS        \ (make rings=on)

\ ------------------------------------------------------------------------------
\ The ring (gfx-planet7.asm's pf_ring makes its dots in game context: RG_X,
\ RG_Y, RG_F, RG_N of them): each dot drawn in yellow (marked dirty, for the
\ next frame on this buffer to repair), but a dot behind the planet's centre
\ and inside its disc, which the planet hides
\ ------------------------------------------------------------------------------

.f_ring
 LDA RG_N
 BNE frg0
 RTS
.frg0
 LDA #&FF
 STA R_COLE
 STA R_COLO
 LDX #0
.frg1
 STX fm_i
 LDA RG_F,X
 BPL frg3
 LDA F_PLON             \ behind: inside the planet's disc?
 BEQ frg3
 LDA RG_Y,X
 SEC
 SBC F_PLY
 STA fz_t
 LDA #0
 SBC F_PLY+1
 JSR f_abs16
 BCS frg3
 CMP F_PLR
 BEQ frg2
 BCS frg3
.frg2
 TAY
 LDX fm_i
 LDA RG_X,X
 SEC
 SBC F_PLX
 STA fz_t
 LDA #0
 SBC F_PLX+1
 JSR f_abs16
 BCS frg3
 CMP F_HW,Y
 BCC frg4
 BEQ frg4
.frg3
 LDX fm_i
 LDA RG_X,X
 LDY RG_Y,X
 TAX
 LDA #1
 JSR T_DOT
.frg4
 LDX fm_i
 INX
 CPX RG_N
 BCC frg1
 RTS

ENDIF                   \ (_PLANET_RINGS)

\ ------------------------------------------------------------------------------
\ The moon (gfx-planet7.asm's pf_moon makes it in game context: MN_ON, MN_X,
\ MN_Y, MN_R, MN_Z, its crater in the caps' slot PCMAX): a third disc after
\ the sun and the planet (f_discs, f_disc2), light grey with a dark grey
\ crater, its rows hidden where the planet or the sun is in front of it
\ (MN_ON bits 6 and 5: the moon further than they). Ships further than the
\ moon and inside its disc are hidden (f_behind).
\
\ It is drawn incrementally: each buffer keeps where it drew the moon (MO_ON
\ ..., in the shared workspace: its centre, radius and depth bits, its rows
\ and its crater's rows), and only the rows that have changed since that
\ buffer's last frame are drawn again:
\
\   * the same place, size and depth (fm_md 1): a row with no crater, old or
\     new, only where this frame wrote over it (R_WL..R_WR, read before the
\     moon's own writes: the layer's repair of shapes drawn over the moon,
\     the layer's and the second disc's own changes); the crater's rows, old
\     or new, whole (the crater turns with the planet);
\   * moved, resized, its depth changed or gone (every row changed): f_moon0,
\     before the disc layer, puts the old moon's spans into DIRTY (its box's
\     rows, if F_HW3 no longer has its radius's half-widths) for the layer's
\     repair to restore in this frame, and the moon is drawn whole
\     (fm_md 0, as with nothing of it in this buffer).
\
\ Its writes go through T_WSPAN, into R_WL/R_WR (for the text and the
\ sights, and for the moon itself next time), never into DIRTY.
\ ------------------------------------------------------------------------------

.f_moon0
 STZ fm_md
 LDX F_BACK
 BIT MO_ON,X
 BPL fm09               \ (none in this buffer)
 BIT MN_ON
 BPL fm0d               \ gone
 LDA MN_ON
 EOR MO_ON,X
 AND #&60
 BNE fm0d               \ its depth changed
 LDA MN_R
 CMP MO_R,X
 BNE fm0d               \ resized
 LDY #0                 \ (MN_X, MN_Y against MO_XL ... MO_YH)
.fm0c
 LDA MN_X,Y
 CMP MO_XL,X
 BNE fm0n
 INX
 INX
 INY
 CPY #4
 BNE fm0c
 INC fm_md              \ the same (1)
.fm09
 RTS
.fm0n
 LDX F_BACK             \ (moved)
.fm0d                   \ the old box, x +/- r on rows MO_T .. MO_B, into DIRTY
 LDA MO_XL,X
 SEC
 SBC MO_R,X
 STA fz_t
 LDA MO_XH,X
 SBC #0
 JSR fm_clamp
 STA fm_l
 LDA MO_XL,X
 CLC
 ADC MO_R,X
 STA fz_t
 LDA MO_XH,X
 ADC #0
 JSR fm_clamp
 STA fm_r
 LDA MO_T,X
 STA fm_y
.fm0l
 LDX F_BACK
 LDY fm_y
 TYA
 CMP MO_B,X
 BEQ fm0k
 BCS fm0z
.fm0k
 LDA fm_l               \ the box's row, or the old span's when F_HW3 holds
 STA R_XL               \ the old radius's half-widths
 LDA fm_r
 STA R_XR
 LDA MO_R,X
 CMP f_hw3r
 BNE fm0w
 TYA                    \ |y - old y|, and the half-width there (none: the row
 SEC                    \ is skipped)
 SBC MO_YL,X
 STA fz_t
 LDA #0
 SBC MO_YH,X
 JSR f_abs16
 BCS fm0j
 CMP MO_R,X
 BEQ P%+4
 BCS fm0j
 TAY
 LDA F_HW3,Y
 STA fz_n
 LDA MO_XL,X            \ x - n .. x + n, clamped
 SEC
 SBC fz_n
 STA fz_t
 LDA MO_XH,X
 SBC #0
 JSR fm_clamp
 STA R_XL
 LDA MO_XL,X
 CLC
 ADC fz_n
 STA fz_t
 LDA MO_XH,X
 ADC #0
 JSR fm_clamp
 STA R_XR
 LDY fm_y
.fm0w
 JSR T_MARKDIRTY
.fm0j
 INC fm_y
 BNE fm0l
.fm0z
 LDX F_BACK             \ (and forget it)
 STZ MO_ON,X
 RTS

\ fm_clamp: the 16-bit x (A high, fz_t low) clamped to R_CL .. R_CR

.fm_clamp
 TAY
 BMI fmc_l
 BNE fmc_r
 LDA fz_t
 CMP R_CL
 BCC fmc_l
 CMP R_CR
 BCC fmc9
.fmc_r
 LDA R_CR
 RTS
.fmc_l
 LDA R_CL
.fmc9
 RTS

.f_moon
 BIT MN_ON
 BMI fmn0
 LDX F_BACK             \ none (f_moon0 has put any old one into DIRTY)
 STZ MO_ON,X
 RTS
.fmn0
 LDA MN_X
 STA f_cx
 LDA MN_X+1
 STA f_cxh
 LDA MN_Y
 STA f_cy
 LDA MN_Y+1
 STA f_cy+1
 LDA MN_R
 STA f_r
 CMP f_hw3r
 BEQ fmn1
 STA f_hw3r
 LDA #LO(F_HW3)
 STA fhw_st+1
 LDA #HI(F_HW3)
 STA fhw_st+2
 JSR f_hwbuild
.fmn1
 LDA #LO(F_HW3)
 STA fpr_ld+1
 STA fpr_ld2+1
 LDA #HI(F_HW3)
 STA fpr_ld+2
 STA fpr_ld2+2
 JSR f_discspans
 LDA #255               \ its crater's rows: fm_ct .. fm_cb (none: 255, 0)
 STA fm_ct
 STZ fm_cb
 LDY R_NDT
 CPY R_NDB
 BEQ fmn2
 BCS fmn4               \ (no rows on the screen)
.fmn2
 JSR T_MCAPS            \ (its crater's boundaries, as the planet's)
 LDY R_NDT
.fmn3
 LDA R_NDN,Y            \ (boundaries, or colour B at the left end)
 BEQ fmn3b
 CPY fm_ct
 BCS P%+5
 STY fm_ct
 STY fm_cb
.fmn3b
 CPY R_NDB
 INY
 BCC fmn3
.fmn4
 LDX F_BACK             \ the rows: the new ones, and the old ones when
 LDA R_NDT              \ fm_md is 1 or 2
 STA fm_y
 LDA R_NDB
 STA fm_hi
 LDA fm_md
 BEQ fmn5
 LDA MO_T,X
 CMP fm_y
 BCS P%+5
 STA fm_y
 LDA MO_B,X
 CMP fm_hi
 BCC fmn5
 STA fm_hi
.fmn5
 LDA fm_y
 CMP fm_hi
 BEQ fmn6
 BCS fmn7
.fmn6
 JSR fm_row
 INC fm_y
 BNE fmn5
.fmn7
 LDX F_BACK             \ what this buffer now shows
 LDA MN_ON
 AND #&60
 ORA #&80
 STA MO_ON,X
 LDY #0                 \ (MN_X, MN_Y, MN_R to MO_XL ... MO_R)
.fmn8
 LDA MN_X,Y
 STA MO_XL,X
 INX
 INX
 INY
 CPY #5
 BNE fmn8
 LDX F_BACK
 LDA R_NDT
 STA MO_T,X
 LDA R_NDB
 STA MO_B,X
 LDA fm_ct
 STA MO_CT,X
 LDA fm_cb
 STA MO_CB,X
 RTS

\ fm_row: row fm_y. fm_sp: its old span a0, b0, its new one a1, b1, and the
\ old one again (empty: 255, 0); fm_wl .. fm_wr: what this frame wrote over
\ it before the moon (R_WR = 0: nothing)

.fm_row
 LDY fm_y
 LDA R_WL,Y
 STA fm_wl
 LDA R_WR,Y
 STA fm_wr
 LDA #255
 STA fm_sp
 STA fm_sp+2
 STZ fm_sp+1
 STZ fm_sp+3
 CPY R_NDT              \ the new span
 BCC fr1
 LDA R_NDB
 CMP fm_y
 BCC fr1
 LDA R_NDISCL,Y
 STA fm_sp+2
 LDA R_NDISCR,Y
 STA fm_sp+3
.fr1
 LDA fm_md              \ the old (0: none: the row whole)
 BEQ frw
 LDX F_BACK
 TYA
 CMP MO_T,X
 BCC fr3
 CMP MO_B,X
 BEQ fr1a
 BCS fr3
.fr1a
 LDA fm_sp+2            \ (the same)
 STA fm_sp
 LDA fm_sp+3
 STA fm_sp+1
.fr3
 CPY fm_ct              \ a crater row, new or old: the row whole
 BCC fr4
 TYA
 CMP fm_cb
 BEQ frw
 BCC frw
.fr4
 LDX F_BACK
 TYA
 CMP MO_CT,X
 BCC fr5
 CMP MO_CB,X
 BEQ frw
 BCC frw
.fr5                    \ a plain row, the same: what was written over it,
 LDA fm_wr              \ light grey
 BEQ fr9
 LDA fm_wl
 CMP fm_sp+2
 BCS P%+5
 LDA fm_sp+2
 PHA
 LDA fm_wr
 CMP fm_sp+3
 BCC P%+5
 LDA fm_sp+3
 TAX
 PLA
 LDY #0
 JMP fm_iv
.fr9
 RTS
.frw                    \ the row whole: the new span's pieces in the moon's
 LDA fm_sp+3            \ colours
 CMP fm_sp+2
 BCC fr9
 STA fm_pb
 LDA fm_sp+2
 STA fm_pa
 LDA #1
 STA fm_n
 JSR fm_occs
 LDX #0
.frw1
 CPX fm_n
 BCS fr9
 STX fm_i
 JSR fm_paint
 LDX fm_i
 INX
 BRA frw1

\ fm_iv: pixels A .. X of row fm_y in colour Y (0 light grey), less the
\ discs in front

.fm_iv
 STY fm_c
 STA fm_pa
 STX fm_pb
 CPX fm_pa
 BCC fmd9
 LDA #1
 STA fm_n
 JSR fm_occs
 LDX #0
.fmv1
 CPX fm_n
 BCS fmd9
 STX fm_i
 LDA fm_pa,X
 STA fm_a
 LDA fm_pb,X
 STA R_XR
 JSR fm_span
 LDX fm_i
 INX
 BRA fmv1
.fmd9
 RTS

\ fm_occs: the pieces (fm_pa, fm_pb, fm_n of them) less the planet's and the
\ sun's discs where they are in front of the moon

.fm_occs
 BIT MN_ON
 BVC fos1
 LDA F_PLON
 BEQ fos1
 LDX #4
.fos0
 LDA F_PLX,X            \ (F_PLX, F_PLY, F_PLR to fm_ox, fm_oy, fm_or)
 STA fm_ox,X
 DEX
 BPL fos0
 LDA #HI(F_HW)
 LDX #LO(F_HW)
 JSR fm_occ
.fos1
 LDA MN_ON
 AND #&20
 BEQ fmd9
 LDA GSUNON
 BEQ fmd9
 LDX #3
.fos2
 LDA F_SUX,X            \ (F_SUX, F_SUY)
 STA fm_ox,X
 DEX
 BPL fos2
 LDA GSUNR
 STA fm_or
 LDA #HI(F_HW2)
 LDX #LO(F_HW2)
 JMP fm_occ

\ fm_occ: the pieces less the disc (fm_ox, fm_oy, fm_or) with half-width
\ table (X, A) (low, high), on row fm_y

.fmo0
 RTS
.fm_occ
 STX fmo_ld+1
 STA fmo_ld+2
 LDA fm_y               \ dy = y - oy, |dy| <= r
 SEC
 SBC fm_oy
 STA fz_t
 LDA #0
 SBC fm_oy+1
 JSR f_abs16
 BCS fmo0
 CMP fm_or
 BEQ fmo1
 BCS fmo0
.fmo1
 TAX
.fmo_ld
 LDA F_HW,X             \ (patched: the half-width table)
 STA fz_n
 LDA fm_ox              \ ol = ox - n, or = ox + n (16-bit), to 0..255
 SEC
 SBC fz_n
 STA fm_l
 LDA fm_ox+1
 SBC #0
 BMI fmo2
 BNE fmo0               \ (ol > 255: none)
 BEQ fmo3
.fmo2
 STZ fm_l
.fmo3
 LDA fm_ox
 CLC
 ADC fz_n
 STA fm_r
 LDA fm_ox+1
 ADC #0
 BMI fmo0               \ (or < 0: none)
 BEQ fmo4
 LDA #255
 STA fm_r
.fmo4
 LDX fm_n               \ each piece less [fm_l, fm_r]: from the last
.fmo5
 DEX
 BMI fmo9
 LDA fm_pb,X
 CMP fm_l
 BCC fmo5               \ (b < l: kept)
 LDA fm_pa,X
 CMP fm_r
 BEQ fmo6
 BCS fmo5               \ (a > r: kept)
.fmo6
 LDA fm_pa,X            \ [a, l - 1] in its place if a < l, and [r + 1, b]
 CMP fm_l               \ at the end if r < b
 BCS fmo7
 LDA fm_pb,X
 PHA
 LDA fm_l
 DEC A
 STA fm_pb,X
 PLA
 CMP fm_r
 BEQ fmo5
 BCC fmo5
 LDY fm_n
 STA fm_pb,Y
 LDA fm_r
 INC A
 STA fm_pa,Y
 INC fm_n
 BRA fmo5
.fmo7
 LDA fm_pb,X            \ (a >= l: only [r + 1, b], if any)
 CMP fm_r
 BEQ fmo8
 BCC fmo8
 LDA fm_r
 INC A
 STA fm_pa,X
 BRA fmo5
.fmo8
 LDY fm_n               \ (wholly hidden: the last piece into its place)
 DEY
 STY fm_n
 LDA fm_pa,Y
 STA fm_pa,X
 LDA fm_pb,Y
 STA fm_pb,X
 BRA fmo5
.fmo9
 RTS

\ fm_paint: piece X on row fm_y in the moon's colours: light grey from the
\ row's start colour, flipping to dark grey and back at its boundaries

.fm_paint
 LDA fm_pa,X
 STA fm_a
 LDA fm_pb,X
 STA fm_b
 LDY fm_y
 LDA R_NDN,Y            \ the count and, in bit 7, the start colour
 AND #&7F
 STA fm_k
 EOR R_NDN,Y
 ASL A
 ROL A
 STA fm_c
 LDA R_NDX0,Y
 STA fm_x
 LDA R_NDX1,Y
 STA fm_x+1
 LDA R_NDX2,Y
 STA fm_x+2
 LDA R_NDX3,Y
 STA fm_x+3
 LDX #0
.fmp1
 CPX fm_k
 BCS fmp4
 LDA fm_x,X
 CMP fm_a
 BEQ fmp2
 BCS fmp3
.fmp2
 LDA fm_c               \ (at or left of the piece's start: a flip)
 EOR #1
 STA fm_c
 BRA fmp3a
.fmp3
 CMP fm_b               \ inside: paint up to it, then flip
 BEQ fmp3b
 BCS fmp4
.fmp3b
 DEC A
 STA R_XR
 PHX
 JSR fm_span
 PLX
 LDA fm_x,X
 STA fm_a
 LDA fm_c
 EOR #1
 STA fm_c
.fmp3a
 INX
 BRA fmp1
.fmp4
 LDA fm_b
 STA R_XR
.fm_span                \ R_XL = fm_a .. R_XR in colour fm_c, on row fm_y
 LDA fm_a
 STA R_XL
 LDX fm_c
 LDA mn_ce,X
 STA R_COLE
 LDA mn_co,X
 STA R_COLO
 LDY fm_y
 JMP T_WSPAN            \ (into R_WL/R_WR, not DIRTY)

\ The moon's colours: light grey (C, M, Y and black in equal measure) and dark
\ grey (one of C, M, Y in four pixels): even rows, odd rows (MODE 1 bytes:
\ pixel i in bits 7 - i and 3 - i)
.mn_ce EQUB &6A, &28    \ light C M Y K, dark C K M K
.mn_co EQUB &9A, &44    \ light Y K C M, dark K Y K K

.f_hw3r EQUB 0          \ the radius F_HW3 was built for
.fm_y  EQUB 0
.fm_i  EQUB 0
.fm_n  EQUB 0
.fm_pa SKIP 3
.fm_pb SKIP 3
.fm_ox EQUW 0
.fm_oy EQUW 0
.fm_or EQUB 0
.fm_l  EQUB 0
.fm_r  EQUB 0
.fm_a  EQUB 0
.fm_b  EQUB 0
.fm_c  EQUB 0
.fm_k  EQUB 0
.fm_x  SKIP 4
.fm_md EQUB 0           \ f_moon0's case: 0 whole, 1 the same, 2 moved
.fm_hi EQUB 0           \ the last row
.fm_ct EQUB 0           \ the new crater rows
.fm_cb EQUB 0
.fm_wl EQUB 0           \ the row's R_WL, R_WR before the moon's writes
.fm_wr EQUB 0
.fm_sp SKIP 4           \ the row's old span, new span

\ ------------------------------------------------------------------------------
\ f_behind: is ship f_si behind the planet or the moon, with the first vertex
\ of its first visible face inside its disc? C set if so (don't draw it)
\ ------------------------------------------------------------------------------

.f_behind
 LDA F_PLON             \ the planet's disc, if any
 BEQ fbh0
 LDX #4
.fbhp
 LDA F_PLX,X            \ (F_PLX, F_PLY, F_PLR)
 STA fb_x,X
 DEX
 BPL fbhp
 LDA F_PLZH
 STA fb_zh
 LDA F_PLZL
 STA fb_zl
 LDA #LO(F_HW)
 LDX #HI(F_HW)
 JSR f_bdisc
 BCC fbh0
 RTS
.fbh0
 BIT MN_ON              \ the moon's, if any
 BMI fbh0a
 CLC
 RTS
.fbh0a
 LDX #3
.fbhm
 LDA MN_X,X             \ (MN_X, MN_Y, MN_R, MN_Z)
 STA fb_x,X
 DEX
 BPL fbhm
 LDA MN_R
 STA fb_r
 LDA MN_Z+1
 STA fb_zh
 LDA MN_Z
 STA fb_zl
 LDA #LO(F_HW3)
 LDX #HI(F_HW3)

\ f_bdisc: is ship f_si behind the disc fb_x, fb_y, fb_r (half-widths at
\ (A, X)), z fb_zh/fb_zl, with the first vertex of its first visible face
\ inside it? C set if so

.f_bdisc
 STA fbh_hw+1
 STX fbh_hw+2
 LDX f_si               \ further away than the disc?
 LDA fb_zl
 CMP F_SZL,X
 LDA fb_zh
 SBC F_SZH,X
 BCS fbh8               \ disc z >= ship z: in front
 LDY #0                 \ first visible face: its first vertex
 STY f_f
 LDA fz_ft
 STA fz_p
 LDA fz_ft+1
 STA fz_p+1
.fbh1
 LDY f_f
 CPY f_nf
 BCS fbh8
 LDA (fz_dl),Y
 BNE fbh2
 LDY #0                 \ skip this face's list entry (n + 16 * its hue ramp,
 LDA (fz_p),Y           \ its normal, n offsets: n + 4 bytes)
 AND #15
 CLC
 ADC #4
 ADC fz_p
 STA fz_p
 BCC P%+4
 INC fz_p+1
 INC f_f
 JMP fbh1
.fbh2
 LDY #4                 \ XX3 offset of the vertex
 LDA (fz_p),Y
 TAY
 LDA (fz_v3),Y          \ dx = x - the disc's x (16-bit)
 SEC
 SBC fb_x
 STA fz_t
 INY
 LDA (fz_v3),Y
 SBC fb_x+1
 JSR f_abs16            \ -> A = |dx| if < 256, else C set
 BCS fbh8
 STA f_bdx
 INY
 LDA (fz_v3),Y          \ dy = y - the disc's y
 SEC
 SBC fb_y
 STA fz_t
 INY
 LDA (fz_v3),Y
 SBC fb_y+1
 JSR f_abs16
 BCS fbh8
 CMP fb_r               \ |dy| <= r and |dx| <= half-width(|dy|)?
 BEQ fbh3
 BCS fbh8
.fbh3
 TAX
.fbh_hw
 LDA F_HW,X             \ (patched: the half-width table)
 CMP f_bdx
 BCC fbh8
 SEC
 RTS
.fbh8
 CLC
 RTS

.fb_x  EQUW 0           \ the disc: centre, radius (as F_PLX, F_PLY, F_PLR)
.fb_y  EQUW 0
.fb_r  EQUB 0
.fb_zh EQUB 0
.fb_zl EQUB 0
.f_bdx EQUB 0

\ f_abs16: (A fz_t) 16-bit signed -> A = |value| and C clear if < 256, else
\ C set

.f_abs16
 BPL fab1
 EOR #&FF
 STA fz_u
 LDA fz_t
 EOR #&FF
 CLC
 ADC #1
 STA fz_t
 LDA fz_u
 ADC #0
.fab1
 BNE fab9
 LDA fz_t
 CLC
 RTS
.fab9
 SEC
 RTS

\ f_winding: the face just gathered into R_PXL/R_PYL (low bytes; a far ship is
\ small, so differences fit in 8 bits), whose byte in the record's XX2 copy
\ is fz_t: C set if it is front-facing, i.e. clockwise on screen, (x1 - x0) *
\ (y2 - y0) - (y1 - y0) * (x2 - x0) > 0, as the face lists' windings are for
\ a ship with ZINF's handedness; anticlockwise if bit 5 of fz_t is set (the
\ ship has TIDY's handedness, mirrored: GHAND, S_SHIP)

.f_winding
 LDA R_PXL+1
 SEC
 SBC R_PXL
 STA fw_a
 LDA R_PYL+2
 SEC
 SBC R_PYL
 JSR f_smul             \ (x1 - x0) * (y2 - y0)
 STA fw_h
 STX fw_l
 LDA R_PYL+1
 SEC
 SBC R_PYL
 STA fw_a
 LDA R_PXL+2
 SEC
 SBC R_PXL
 JSR f_smul             \ (y1 - y0) * (x2 - x0)
 STA fw_t
 STX fw_t+1
 LDA fw_l               \ first - second, 16-bit signed
 SEC
 SBC fw_t+1
 STA fw_l
 LDA fw_h
 SBC fw_t
 BVC P%+4
 EOR #&80
 STA fw_h               \ (bit 7: the sign)
 ORA fw_l
 BEQ fwn9               \ zero: edge-on
 LDA fz_t               \ bit 5 of the face's byte (bit 7 here): the ship is
 ASL A                  \ mirrored from the face lists' handedness (L_REC)
 ASL A
 EOR fw_h
 BMI fwn9               \ negative (positive if mirrored): back face
 SEC
 RTS
.fwn9
 CLC
 RTS

\ f_smul: A * fw_a, both signed 8-bit -> A (high), X (low), signed 16-bit

.f_smul
 STA fw_b
 STA fw_bo
 LDA #0
 STA fw_t2
 LDX #8
.fsm1                   \ unsigned (fw_a * fw_b), then correct for signs
 LSR fw_b
 BCC fsm2
 CLC
 ADC fw_a
.fsm2
 ROR A
 ROR fw_t2
 DEX
 BNE fsm1
 TAX                    \ A = high byte of the unsigned product
 LDA fw_a               \ if fw_a < 0, high -= original b; if b < 0, high -= a
 BPL fsm3
 TXA
 SEC
 SBC fw_bo
 TAX
.fsm3
 LDA fw_bo
 BPL fsm4
 TXA
 SEC
 SBC fw_a
 TAX
.fsm4
 TXA
 LDX fw_t2
 RTS

.fw_a  EQUB 0
.fw_b  EQUB 0
.fw_bo EQUB 0
.fw_t  EQUW 0
.fw_t2 EQUB 0
.fw_h  EQUB 0
.fw_l  EQUB 0
