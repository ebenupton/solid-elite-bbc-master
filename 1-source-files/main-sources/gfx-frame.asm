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

.F_NLINE    EQUB 0      \ lines recorded this frame (planet features, enemy lasers)
.F_LX0      SKIP MAXLN
.F_LY0      SKIP MAXLN
.F_LX1      SKIP MAXLN
.F_LY1      SKIP MAXLN
.F_LC       SKIP MAXLN  \ colour index

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
\ Text map: 24 rows x 32 columns of desired characters (F_TM), and for each
\ cell what each buffer shows (F_ST, at F_TM + &300). A cell of F_TM is its
\ character (&20-&7F), or 0, or, once cleared, &80 + the character it had
\ (empty, remembering the character). For buffer b, bit b+2 of F_ST (F_STN)
\ says it shows a character in the cell, and bit b (F_STM) that this is the
\ cell's character, or the one it remembers: so a cell cleared and given
\ its character back (TT66 and a view's title) is shown as it was, as with
\ the original's shown maps. The text steps erase a cell where a buffer shows
\ a character that is not the cell's (N, and not M or the cell empty), and
\ draw a non-empty cell where it shows none (not N). F_TMR counts the
\ non-empty cells of each text map row, F_SHR0/F_SHR1 those each buffer
\ shows, so empty rows cost nothing.
\ ------------------------------------------------------------------------------

F_STM = 1               \ F_ST: buffer 0 shows the cell's character
F_STN = 4               \ F_ST: buffer 0 shows a character (buffer 1: x 2)

.f_tmclear              \ clear the text map and buffer 1's shown cells (Master
 LDX #0                 \ port: buffer 1, shadow RAM, is the direct-mode screen,
.ftc1                   \ which TTX66 blanks; buffer 0 keeps its own: it still
 LDA F_TM,X             \ holds that picture)
 BEQ P%+7
 ORA #&80
 STA F_TM,X
 LDA F_TM+256,X
 BEQ P%+7
 ORA #&80
 STA F_TM+256,X
 LDA F_TM+512,X
 BEQ P%+7
 ORA #&80
 STA F_TM+512,X
 INX
 BNE ftc1
 LDA #5*F_STM           \ buffer 1 shows nothing
 JSR f_stand
 LDX #23
.ftc2
 STA F_TMR,X
 STA F_SHR1,X
 DEX
 BPL ftc2
 JMP f_tchall

\ f_stand: every cell's F_ST AND A: a buffer's shown cells cleared (f_tmclear,
\ f_enter, f_b0new). Returns A = 0

.f_stand
 STA fsa1+1
 STA fsa2+1
 STA fsa3+1
 LDX #0
.fsa0
 LDA F_ST,X
.fsa1
 AND #0                 \ patched
 STA F_ST,X
 LDA F_ST+256,X
.fsa2
 AND #0                 \ patched
 STA F_ST+256,X
 LDA F_ST+512,X
.fsa3
 AND #0                 \ patched
 STA F_ST+512,X
 INX
 BNE fsa0
 TXA
 RTS

\ f_stset: every cell's F_ST = (F_ST AND A) OR (X if the text map's cell is
\ empty, Y if not): buffer 1's shown cells set from the text map (f_sync)

.f_stset
 STA fss_k+1
 STX fss_z+1
 STY fss_n+1
 LDA #HI(F_TM)
 STA fss_t+2
 LDA #HI(F_ST)
 STA fss_s+2
 STA fss_d+2
 LDX #0
.fss_t
 LDA F_TM,X             \ patched
 BEQ fss_z
 BMI fss_z
.fss_n
 LDA #0                 \ patched
 BRA fst2
.fss_z
 LDA #0                 \ patched
.fst2
 STA fss_o+1
.fss_s
 LDA F_ST,X             \ patched
.fss_k
 AND #0                 \ patched
.fss_o
 ORA #0                 \ patched
.fss_d
 STA F_ST,X             \ patched
 INX
 BNE fss_t
 INC fss_t+2
 INC fss_s+2
 INC fss_d+2
 LDA fss_t+2
 CMP #HI(F_TM)+3
 BNE fss_t
 RTS

\ f_cell: X = column, Y = row -> f_ptr = row*32 + column (offset into a map)
\ Returns the offset in f_off (2 bytes) and also patches the map accessors
\ f_tmld/f_tmst and f_stld/f_stst.

.f_cell
 TYA
 LSR A
 LSR A
 LSR A
 STA f_off+1            \ row DIV 8 = high byte of row*32
 TYA
 ASL A
 ASL A
 ASL A
 ASL A
 ASL A                  \ (row MOD 8) * 32
 STA f_off
 TXA
 ORA f_off
 STA f_off
 CLC
 ADC #LO(F_TM)
 STA f_tmld+1
 STA f_tmst+1
 STA f_stld+1
 STA f_stst+1
 LDA f_off+1
 ADC #HI(F_TM)
 STA f_tmld+2
 STA f_tmst+2
 ADC #3                 \ (C = 0) F_ST = F_TM + &300
 STA f_stld+2
 STA f_stst+2
 RTS

.f_off  EQUW 0
.f_row  EQUB 0
.F_TCH  SKIP 24         \ per text row: bit b set = buffer b's shown row may
                        \ differ from the text map (f_text1/f_text2 scan it whole)
.f_tbit EQUB 0          \ this frame's buffer bit (1 or 2): its M bit in F_ST

.f_tchall               \ every row changed, for both buffers (keeps X; A = 0)
 PHX
 LDX #23
 LDA #3
.fta1
 STA F_TCH,X
 DEX
 BPL fta1
 PLX
 LDA #0
 RTS

\ f_char0 (F_CHAR, frame_cold.asm): A = character, (XC-1, YC) = cell. EOR
\ semantics like the original: printing the same character again removes it.

.f_char0
 STY f_ysav
 PHA
 LDX XC
 DEX
 LDY YC
 CPY #24
 BCS fch9
 CPX #32
 BCS fch9
 STY f_row
 JSR f_cell
 PLA
 JSR f_tmget            \ X = current content
 BEQ fch1               \ empty: store the character
 BMI fch1
 STA f_tmp
 CPX f_tmp
 BEQ fch2               \ same character: remove it
 JSR f_tmstore          \ different: replace
 JMP fch8
.fch1
 JSR f_tmstore
 LDX f_row
 INC F_TMR,X
 JMP fch8
.fch2
 JSR f_tmclr
 LDX f_row
 DEC F_TMR,X
.fch8
 LDX f_row
 LDA #3
 STA F_TCH,X
 LDY f_ysav
 RTS
.fch9
 PLA
 LDY f_ysav
 RTS

.f_tmstore              \ A = the new character, X = the cell's content (not
 STA f_tmp              \ A): if it is not A's, or A's remembered, neither
 TXA                    \ buffer shows the cell's character now (M = 0)
 AND #&7F
 CMP f_tmp
 BEQ fts1
.f_stld
 LDA F_ST               \ patched
 AND #3*F_STN
.f_stst
 STA F_ST               \ patched
.fts1
 LDA f_tmp
.f_tmst
 STA F_TM               \ patched
 RTS

.f_tmclr                \ the cell (not empty) cleared: it remembers its
 JSR f_tmget            \ character, which each buffer shows or not as before
 TXA
 ORA #&80
 BNE f_tmst             \ (always)

.f_tmget
.f_tmld
 LDX F_TM               \ patched; sets Z and N on the content
 RTS

.f_ysav EQUB 0
.f_tmp  EQUB 0

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

\ f_clrtext0 (F_CLRTEXT, frame_cold.asm): clear text map rows X to Y inclusive
\ (each cell remembers its character; F_ST is unchanged)

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
 LDA #0
 LDX f_row
 STA F_TMR,X
.fct6
 LDA #3
 STA F_TCH,X
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
 JSR f_tmclear          \ (A = 0; X only, so Y is kept)
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

\ F_LINE: record a line X1,Y1 -> X2,Y2 in colour GLCOL (8-bit screen coords)

.F_BOMB                 \ Master port: a new energy bomb bolt: drop the lines of
 BIT f_bomb             \ the bolt recorded earlier in this frame, if any
 BPL fbo1
 LDA f_bmark
 STA F_NLINE
 RTS
.fbo1
 LDA F_NLINE
 STA f_bmark
 LDA #&FF
 STA f_bomb
 RTS
.f_bomb  EQUB 0
.f_bmark EQUB 0

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
 LDA GLCOL
 STA F_LC,X
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

.F_SUX EQUW 0
.F_SUY EQUW 0

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

.ff1
 JSR L_SUN              \ the light for the next iteration's ships (gfx-light.asm,
                        \ main RAM: game context, before ACCCON X is set below)

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
 JSR f_discs            \ the disc layer (sun or planet), incremental
 JSR f_disc2            \ the other disc, if both are on screen (full spans)
.ff_lin                 \ (F_HANGAR points this call at f_hback for its frame)
 JSR f_lines            \ planet meridians, craters, enemy lasers
 JSR f_ships            \ filled ships, far to near
 JSR T_KCOMMIT          \ (K mode: the kept rows still pending blacked)
 JSR f_dots             \ particles, distant ships
 JSR f_lasers           \ our laser beams and the sights
 JSR f_flt              \ the lens flare (gfx-flare6.asm), then the text on top
 JSR f_sight2           \ and the sights
 JSR f_stars            \ stardust, on black only (last: erasing it next
                        \ time restores black, so it needs no WL/WR)

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
 LDA #0                 \ empty the per-frame lists
 STA GLASV              \ (Master port: the beams show for one frame per LASLI)
 STA f_bomb             \ (and no bomb bolt yet)
 STA F_NSHIP
 STA F_NLINE
 STA F_NDOT
 STA F_PLON
 STA GSUNON
 STA F_NCV
 STA F_NPT
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
 JSR T_SETBUF
 JSR T_RESETBUF
 LDA #&FF
 STA F_DCOL+1
 LDA #5*F_STM           \ buffer 1 shows nothing
 JSR f_stand
 LDX #23
.fen9
 STA F_SHR1,X
 DEX
 BPL fen9
 JSR f_tchall
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
\ current buffer's rasteriser arrays (R_DIRTYLb etc.) and shown-text map.
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
 LDA fbp_sr,X
 STA ft_sr1+2
 STA ft_sr2+2
 STA ft_sr3+2
 LDA fbp_srl,X
 STA ft_sr1+1
 STA ft_sr2+1
 STA ft_sr3+1
 RTS
.fbp_dl EQUB HI(R_DIRTYL0), HI(R_DIRTYL1)
.fbp_dr EQUB HI(R_DIRTYR0), HI(R_DIRTYR1)
.fbp_ol EQUB HI(R_DISCL0), HI(R_DISCL1)
.fbp_or EQUB HI(R_DISCR0), HI(R_DISCR1)
.fbp_sr EQUB HI(F_SHR0), HI(F_SHR1)
.fbp_srl EQUB LO(F_SHR0), LO(F_SHR1)
ASSERT LO(R_DIRTYL0) = LO(R_DIRTYL1) AND LO(R_DIRTYR0) = LO(R_DIRTYR1)
ASSERT LO(R_DISCL0) = LO(R_DISCL1) AND LO(R_DISCR0) = LO(R_DISCR1)

\ ------------------------------------------------------------------------------
\ The disc layer
\ ------------------------------------------------------------------------------

\ f_discs: choose which of the sun and planet is the incremental disc layer
\ (the bigger one), fill R_NDISCL/R and run R_DISCROWS. f_disc2 then draws the
\ other, if any, as plain spans.

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
 LDA #FC_PLANE
 STA R_DCE
 LDA #FC_PLANO
 STA R_DCO
 JSR f_plrows           \ planet spans into R_NDISCL/R, R_NDT/R_NDB
 JSR f_bounds           \ and its surface detail as colour boundaries
 JMP T_DISCROWS
.fds6
 LDA #FC_SUNE
 STA R_DCE
 LDA #FC_SUNO
 STA R_DCO
 JSR f_sunrows
 JSR f_nobounds
 JMP T_DISCROWS
.fds9
 LDA #1                 \ no disc
 STA R_NDT
 LDA #0
 STA R_NDB
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

\ f_disc2: the secondary disc, drawn in full every frame as spans (rare: both
\ the sun and the planet on screen).

.f_disc2
 LDA f_sec
 BEQ fd29
 CMP #1
 BEQ fd21
 LDA #FC_PLANE
 STA R_COLE
 LDA #FC_PLANO
 STA R_COLO
 JSR f_plrows
 JMP fd22
.fd21
 LDA #FC_SUNE
 STA R_COLE
 LDA #FC_SUNO
 STA R_COLO
 JSR f_sunrows
.fd22
 LDY R_NDT
.fd23
 CPY R_NDB
 BEQ P%+4
 BCS fd29
 LDA R_NDISCL,Y
 CMP R_NDISCR,Y
 BEQ P%+4
 BCS fd28
 STA R_XL
 LDA R_NDISCR,Y
 STA R_XR
 STY fz_i
 JSR T_SPAN
 LDY fz_i
 JSR T_MARKDIRTY
 LDY fz_i
.fd28
 INY
 BNE fd23
.fd29
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
 LDA #0
 STA fz_i
.fln1
 LDX fz_i
 CPX F_NLINE
 BCS fln9
 LDA F_LC,X
 JSR f_setcol
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
 BNE fln1
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
 LDA fz_t
 STA F_ORD+1,Y
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
\ level, gfx-light.asm, and f_col its ramp entry). Fins standing behind the body are drawn
\ first, then the visible faces, the surface details over them and the other
\ fins (see faces.asm for the order).

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

 LDY #0                 \ fins behind the body (neither of their faces visible)
 LDA (fz_dt),Y
 BEQ fsh_nf0
 TYA
 JSR f_fins
.fsh_nf0

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
 BIT fz_t               \ far ships (XX2 = 255, bit 6 of the copy: Elite skipped
 BVC fsh_draw           \ the normal test) cull back faces by their winding on
                        \ screen, except the station (mirrored until its first TIDY)
 LDX f_si
 LDA F_STYP,X
 CMP #SST
 BEQ fsh_draw
 CMP #DOD               \ (Master port: the Dodo station too)
 BEQ fsh_draw
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

\ f_fins: A = k: draw the fins (two-sided triangles standing on the body edge
\ between face1 and face2) with exactly k of those two faces visible. A fin
\ with neither visible is behind the body, one with one or both in front of
\ it, and only the fin on the corner facing the viewer (both visible) can hide
\ another fin.

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

.f_stars                \ stars 1..NOSTM (NOSTM is only ever NOST = 18), recorded
 LDA #NOST+1            \ by the hooks straight into R_SX/R_SY/R_SS (R_SS = 0: none)
 STA R_SN               \ (Master port: NOST = 20)
 JMP T_STARPLOT

\ ------------------------------------------------------------------------------
\ Text overlay
\ ------------------------------------------------------------------------------

F_TCOL = &FF            \ text ink: yellow (logical colour 3)

\ f_rowptr: X = text row -> fz_p = F_TM + 32*row, fz_q = F_ST + 32*row

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
 STA fz_q
 LDA fz_p+1
 ADC #HI(F_TM)
 STA fz_p+1
 ADC #3                 \ (C = 0) F_ST = F_TM + &300
 STA fz_q+1
 RTS

\ f_text1: cells shown in this buffer that must change: give them back their
\ background by marking them dirty before R_DISCROWS repaints

.f_text1
 LDA F_BACK             \ this buffer's bit in F_TCH, and its M bit in F_ST
 INC A                  \ (into the text steps' masks)
 STA f_tbit
 STA ft_e1+1
 ASL A                  \ its N bit
 ASL A
 STA ft_n2+1
 ORA f_tbit             \ both
 STA ft_n1+1
 STA ft_m1+1
 STA ft_b2+1
 EOR #&FF               \ neither
 STA ft_c1+1
 LDX #23                \ rows 23..0 (each row is independent)
.ft11
.ft_sr1
 LDA F_SHR0,X           \ patched
 BEQ ft18x              \ X = row still
 LDA F_TCH,X            \ shown row = text map row: nothing to remove
 AND f_tbit
 BEQ ft18x
 STX fz_i
 JSR f_rowptr
 LDY #31
.ft12
 LDA (fz_q),Y           \ a character shown (N) that is not the cell's (not
.ft_n1                  \ M), or the cell is empty (M is never set without N)
 AND #0                 \ patched: N and M
 BEQ ft17a
.ft_m1
 CMP #0                 \ patched: N and M
 BNE ft15
 LDA (fz_p),Y
 BEQ ft15
 BMI ft15
.ft17a
 DEY
 BPL ft12
 BMI ft18
.ft15
 LDA (fz_q),Y           \ this cell goes: it shows nothing, and is marked
.ft_c1                  \ dirty
 AND #0                 \ patched: neither N nor M
 STA (fz_q),Y
 LDX fz_i
.ft_sr2
 DEC F_SHR0,X           \ patched
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
.ft17
 DEY
 BPL ft12
.ft18
 LDX fz_i
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

\ f_text2: draw the text map's cells that this buffer doesn't show yet, or
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
 LDA f_wl               \ as cell columns: wl DIV 8 .. wr DIV 8
 LSR A
 LSR A
 LSR A
 STA f_wl
 LDA f_wr
 BEQ ft25
 LSR A
 LSR A
 LSR A
 STA f_wr
 JMP ft26
.ft25
 LDA #255               \ nothing written in this row
 STA f_wl
 LDA #0
 STA f_wr
.ft26
 LDX fz_i               \ row unchanged for this buffer: only the cells
 LDA F_TCH,X            \ written over (columns f_wl..f_wr)
 AND f_tbit
 BNE ft2f
 LDY f_wr
 CPY f_wl
 BCC ft2x
 LDA f_wl
 STA ft_end
 BRA ft27
.ft2x
 JMP ft29
.ft2f
 EOR F_TCH,X            \ whole row (then it is unchanged)
 STA F_TCH,X
 STZ ft_end
 LDY #31
.ft27
 LDA (fz_p),Y
 BEQ ft28
 BMI ft28
 LDA (fz_q),Y
.ft_e1
 AND #0                 \ patched: M (f_text1 has erased the other characters,
 BEQ ft2d               \ so M = N here): not shown yet
 CPY f_wl
 BCC ft28
 CPY f_wr
 BEQ ft2d
 BCS ft28
.ft2d
 LDA (fz_q),Y
.ft_n2
 AND #0                 \ patched: N
 BNE ft2e
 LDX fz_i
.ft_sr3
 INC F_SHR0,X           \ patched
.ft2e
 LDA (fz_q),Y           \ shown now
.ft_b2
 ORA #0                 \ patched: E and N
 STA (fz_q),Y
 LDA (fz_p),Y
 STY fz_u
 JSR f_glyph
 LDY fz_u
.ft28
 CPY ft_end
 BEQ ft2e9
 DEY
 JMP ft27
.ft2e9
 LDX fz_i
 JMP ft29

.f_wl EQUB 0
.f_wr EQUB 0
.ft_end EQUB 0

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
\ Planet surface detail, filled: Elite's PLS22 computes each ellipse (half
\ ellipses for the equator and meridian, a full one for a crater) as points
\ passed to BLINE; we record them (F_PCURVE, F_PPOINT) and turn the curves
\ into per-row colour boundaries for the disc layer: the disc alternates
\ between colour A and colour B at each boundary, so the meridian and equator
\ give a two-colour "beach ball" and a crater a filled ellipse.
\ ------------------------------------------------------------------------------

MAXCV = 3               \ curves per frame
MAXPT = 40              \ points per frame: PLS22's step STP is at least 2
                        \ (CIRCLE's PL89), so a crater's full ellipse has at
                        \ most 33 points and the meridian and equator's half
                        \ ellipses 17 each; a point past the end is dropped

                        \ F_NCV (curves recorded this frame) and F_NPT
                        \ (points recorded this frame) live in F_PPOINT's
                        \ LDA #/LDY # operands
.F_CVS SKIP MAXCV       \ first point of each curve
.F_CVE SKIP MAXCV       \ one past its last point
.F_CVT SKIP MAXCV       \ TGT: 31 (half ellipse) or 64 (full)
.F_PXL SKIP MAXPT
.F_PXH SKIP MAXPT
.F_PYL SKIP MAXPT
.F_PYH SKIP MAXPT

.F_PCURVE
 PHX
 LDX F_NCV
 CPX #MAXCV
 BCS fpc9
 LDA F_NPT
 STA F_CVS,X
 STA F_CVE-1,X          \ ends the previous curve (X = 0: writes F_CVS+2, unused or overwritten later)
 LDA TGT
 STA F_CVT,X
 INC F_NCV
.fpc9
 PLX
 RTS

.F_PPOINT               \ (the current curve's F_CVE is set from F_NPT at fbd2)
 LDA #0                 \ operand = F_NCV
F_NCV = P%-1
 BEQ fpp9
 LDY #0                 \ operand = F_NPT (Y is not preserved: BLINE, the
F_NPT = P%-1            \ only caller, reloads Y on every path
 CPY #MAXPT             \ before reading it; CLIP2 only saves/restores it)
 BCS fpp9
 LDA K6
 STA F_PXL,Y
 LDA K6+1
 STA F_PXH,Y
 LDA K5+2               \ (Master port: BLINE has the new point's y in K5(3 2))
 STA F_PYL,Y
 LDA K5+3
 STA F_PYH,Y
 INY
 STY F_NPT
.fpp9
 JMP gback              \ (G_PPOINT tail-jumps here: page Elite's bank back in
                        \ and return to BLINE)

\ f_nobounds: rows R_NDT..R_NDB have no boundaries (plain disc)

.f_nobounds             \ (STZ: no caller reads A, which left room for
 STZ R_NDF              \ F_PPOINT's JMP gback)
 RTS

.f_zerobounds           \ rows R_NDT..R_NDB: no boundaries yet (only caller
                        \ fbd1, where f_bounds has checked R_NDT <= R_NDB)
 LDA R_NDB
 INC A
 STA fnb_e+1
 STA fsg_cb+1           \ (and f_segment's row range: rows NDT..NDB)
 EOR R_NDT              \ C = bit 0 of (R_NDB+1) EOR R_NDT: an odd row count
 LDY R_NDT
 STY fsg_ct+1
 LSR A
 LDA #0
 BCS fnb2               \ odd: one row first, then pairs
.fnb1                   \ two rows per pass
 STA R_NDN,Y
 STA R_NDP,Y
 INY
.fnb2
 STA R_NDN,Y
 STA R_NDP,Y
 INY
.fnb_e
 CPY #0                 \ patched: R_NDB+1
 BNE fnb1
.fnb9
 RTS

\ f_bounds: the planet's curves -> R_NDN/R_NDX0-3/R_NDP for rows
\ R_NDT..R_NDB (which f_plrows has just set), and colour B

.f_bounds
 JSR f_nobounds
 LDA R_NDT
 CMP R_NDB
 BEQ P%+4
 BCS fnb9
 LDA #1
 BIT PM_OK              \ a beach ball (PM_HOOK ran this frame): the
 BPL fbd1               \ boundaries from the meridian window
 STA R_NDF              \ (gfx-merid.asm), colour B green land
 LDA #&5F
 STA R_DBE
 LDA #&AF
 STA R_DBO
 JMP T_MERID
.fbd1
 LDX F_NCV              \ else a crater's curves (only a crater planet's are
 BEQ fnb9               \ recorded), colour B a dark crater
 STA R_NDF
 JSR f_zerobounds
 LDA #&50
 STA R_DBE
 LDA #&A0
 STA R_DBO
.fbd2
 LDX F_NCV              \ the last curve ends at F_NPT (F_NCV >= 1 here)
 LDA F_NPT
 STA F_CVE-1,X
 LDA #0
 STA f_ci
.fbd3                   \ for each curve
 LDX f_ci
 CPX F_NCV
 BCC P%+5
 JMP f_parity
 LDA F_CVE,X            \ its segments: points F_CVS .. F_CVE-1
 STA fbd_e+1
 LDA F_CVS,X
 TAX
 BRA fbd5               \ loop test at the bottom
.fbd4
 LDA F_PXL-1,X          \ segment start = point X-1
 STA sg_ax
 LDA F_PXH-1,X
 STA sg_ax+1
 LDA F_PYL-1,X
 STA sg_ay
 LDA F_PYH-1,X
 STA sg_ay+1
 LDA F_PXL,X            \ segment end = point X
 STA sg_bx
 LDA F_PXH,X
 STA sg_bx+1
 LDA F_PYL,X
 STA sg_by
 LDA F_PYH,X
 STA sg_by+1
 PHX
 JSR f_seg16
 PLX
.fbd5
 INX                    \ segment X-1 -> X
.fbd_e
 CPX #0                 \ patched: F_CVE of this curve
 BCC fbd4
.fbd6
                        \ (a crater's full ellipse is closed)
.fbd7
 INC f_ci
 JMP fbd3

.f_ci EQUB 0

\ f_seg16: boundary crossings of the segment (sg_ax, sg_ay) - (sg_bx, sg_by)
\ (16-bit) for rows y with min(y) <= y < max(y) within R_NDT..R_NDB. A crossing
\ left of the row's disc span flips the row's starting colour (R_NDP), one
\ right of it is ignored, one inside is added to the row's boundaries. Long
\ segments (|dx| or |dy| > 255) are halved, recursively.

.f_seg16
 LDA sg_bx              \ |dx| > 255 or |dy| > 255?
 SEC
 SBC sg_ax
 LDA sg_bx+1
 SBC sg_ax+1
 BEQ fs16a
 CMP #&FF
 BNE fs16s
 LDA sg_bx
 CMP sg_ax
 BEQ fs16s              \ dx = -256
.fs16a
 LDA sg_by
 SEC
 SBC sg_ay
 LDA sg_by+1
 SBC sg_ay+1
 BEQ fs16b
 CMP #&FF
 BNE fs16s
 LDA sg_by
 CMP sg_ay
 BEQ fs16s
.fs16b
 JMP f_segment
.fs16s                  \ split at the midpoint: push the second half
 LDA sg_bx+1
 PHA
 LDA sg_bx
 PHA
 LDA sg_by+1
 PHA
 LDA sg_by
 PHA
 LDA sg_ax              \ mid = (a + b) / 2 (arithmetic: the true sign of the
 CLC                    \ 17-bit sum is N EOR V)
 ADC sg_bx
 STA fz_t
 LDA sg_ax+1
 ADC sg_bx+1
 STA fz_u
 BVC P%+4
 EOR #&80
 ASL A
 ROR fz_u
 ROR fz_t
 LDA fz_u
 STA sg_bx+1
 LDA fz_t
 STA sg_bx
 LDA sg_ay
 CLC
 ADC sg_by
 STA fz_t
 LDA sg_ay+1
 ADC sg_by+1
 STA fz_u
 BVC P%+4
 EOR #&80
 ASL A
 ROR fz_u
 ROR fz_t
 LDA fz_u
 STA sg_by+1
 LDA fz_t
 STA sg_by
 JSR f_seg16            \ first half: a -> mid
 LDA sg_bx              \ second half: mid -> b
 STA sg_ax
 LDA sg_bx+1
 STA sg_ax+1
 LDA sg_by
 STA sg_ay
 LDA sg_by+1
 STA sg_ay+1
 PLA
 STA sg_by
 PLA
 STA sg_by+1
 PLA
 STA sg_bx
 PLA
 STA sg_bx+1
 JMP f_seg16

\ f_segment: as f_seg16 for |dx|, |dy| <= 255

.f_segment
 LDA sg_ay              \ order the end points by y: (sg_x, sg_y) is the top
 CMP sg_by
 LDA sg_ay+1
 SBC sg_by+1
 BVC P%+4
 EOR #&80
 BMI fsg_ok             \ a above b
 LDA sg_ay              \ equal rows: nothing
 CMP sg_by
 BNE fsg_sw
 LDA sg_ay+1
 CMP sg_by+1
 BNE fsg_sw
.fsg_x                  \ (also f_segment's other early exits)
 RTS
.fsg_sw
 LDX #3                 \ swap a and b
.fsg_w
 LDA sg_ax,X
 LDY sg_bx,X
 STA sg_bx,X
 TYA
 STA sg_ax,X
 DEX
 BPL fsg_w
.fsg_ok
 LDA sg_ax              \ start at a; dy = by - ay, dx = bx - ax
 STA sg_x
 LDA sg_ax+1
 STA sg_x+1
 LDA sg_ay
 STA sg_y
 LDA sg_ay+1
 STA sg_y+1
 LDA sg_by
 SEC
 SBC sg_ay
 STA sg_dy
 LDA sg_by+1
 STA sg_y1+1
 LDA sg_bx
 SEC
 SBC sg_ax
 STA sg_dx
 LDA sg_bx+1
 SBC sg_ax+1
 STA sg_sx              \ sign of dx (bit 7)
 BPL fsg_p
 LDA sg_dx              \ |dx|
 EOR #&FF
 CLC
 ADC #1
 STA sg_dx
.fsg_p
 LDA sg_y+1             \ the segment must reach rows NDT..NDB:
 BMI fsg_a              \ y1 > NDT and y0 <= NDB
 BNE fsg_x
 LDA R_NDB
 CMP sg_y
 BCC fsg_x              \ NDB < y0: misses
.fsg_a
 LDA sg_y1+1
 BMI fsg_x
 BNE fsg_bh             \ y1 > 255: the loop ends at NDB+1
 LDA sg_by
 CMP R_NDT
 BEQ fsg_x
 BCC fsg_x              \ y1 > NDT: reaches the span
.fsg_cb
 CMP #0                 \ patched: R_NDB+1 <= 192 (f_zerobounds)
 BCC fsg_bs
.fsg_bh
 LDA fsg_cb+1
.fsg_bs                 \ the loop's end row E = min(y1, NDB+1) lives in the
 STA fsg_ya+1           \ operands of the two hot exit tests (and fsg_c): rows
 STA fsg_yb+1           \ run from y0 (<= NDB) up, so Y reaches E before
                        \ passing NDB, and above the screen Y >= LO(y0) > E
                        \ (|dy| <= 255), so no other row there matches it
.fsg_b
 LDA sg_dx              \ q = |dx| DIV dy, r = |dx| MOD dy
 LDX #0
.fsg_d
 CMP sg_dy
 BCC fsg_e
 SBC sg_dy
 INX
 BNE fsg_d
.fsg_e
 STA sg_r
 STX sg_q
 STZ sg_err
.fsg_row                \ row sg_y: record the crossing if it's in range
 LDY sg_y               \ Y = sg_y (low byte) for the whole loop: sg_y itself
 LDA sg_y+1             \ is not updated after this (only read before here)
 BMI fsg_hi             \ y < 0 (0 or negative here: fsg_p): rows above
.fsg_ry                 \ the screen. From here on sg_y+1 = 0, and Y <= NDB
.fsg_ct                 \ <= 191 at fsg_n, so Y never wraps in this loop
 CPY #0                 \ patched: R_NDT (f_zerobounds)
 BCC fsg_n
 LDA sg_x+1             \ left of the span? (x <= NDISCL, x 16-bit)
 BMI fsg_l
 BNE fsg_n              \ x > 255: right of it
 LDA sg_x               \ x <= NDISCL: left of the span
 CMP R_NDISCL,Y
 BCC fsg_l
 BEQ fsg_l
 CMP R_NDISCR,Y         \ x > NDISCR: right of the span
 BCC P%+4              \ x < NDISCR: inside (x = NDISCR falls through BNE)
 BNE fsg_n
 LDX R_NDN,Y            \ inside: append (up to four)
 BNE fsg_k1
 STA R_NDX0,Y           \ n = 0
 LDA #1
 STA R_NDN,Y
 INY                    \ (fsg_n inlined)
.fsg_ya
 CPY #0                 \ patched: E = min(y1, NDB+1) (fsg_bs)
 BNE fsg_m
 RTS
.fsg_k1
 CPX #2
 BCS fsg_k2
 STA R_NDX1,Y           \ n = 1
 LDA #2
 STA R_NDN,Y
 INY                    \ (fsg_n inlined)
.fsg_yb
 CPY #0                 \ patched: E = min(y1, NDB+1) (fsg_bs)
 BNE fsg_m
 RTS
.fsg_k2
 BNE fsg_k3
 STA R_NDX2,Y           \ n = 2
 LDA #3
 STA R_NDN,Y
 BRA fsg_n
.fsg_k3
 CPX #4
 BCS fsg_n              \ n >= 4: full
 STA R_NDX3,Y           \ n = 3
 LDA #4
 STA R_NDN,Y
 BRA fsg_n
.fsg_l
 LDA R_NDP,Y            \ left of the span: flip the starting colour
 EOR #1
 STA R_NDP,Y
.fsg_n
 INY                    \ next row: y++, x += sx * (q + carry of the error)
.fsg_c
 CPY fsg_ya+1           \ done at y1
 BNE fsg_m
 RTS
.fsg_hi                 \ rows above the screen: the step returns to fsg_up
 LDX #LO(fsg_up)        \ (not fsg_ry) until y reaches 0 (y >= -254 here as
 STX fsg_jj+1           \ |dy| <= 255 and y1 > 0, so sg_y+1 = &FF, and Y
 LDX #HI(fsg_up)        \ never equals E above the screen: see fsg_bs)
 STX fsg_jj+2
.fsg_up
 INY
 BNE fsg_m
 INC sg_y+1             \ y = 0: back to fsg_ry from the next row
 LDX #LO(fsg_ry)        \ (and Y = 0 < E: no exit here)
 STX fsg_jj+1
 LDX #HI(fsg_ry)
 STX fsg_jj+2
 BRA fsg_m
.fsg_m
 LDA sg_err
 CLC
 ADC sg_r
 STA sg_err
 LDX sg_q
 BCS fsg_m1             \ (err + r can exceed 255 only if dy > 128)
 CMP sg_dy
 BCC fsg_m2
.fsg_m1
 SBC sg_dy
 STA sg_err
 INX
.fsg_m2
 BIT sg_sx              \ N = sign of dx
 BMI fsg_m3
 TXA
 CLC
 ADC sg_x
 STA sg_x
 BCC fsg_jj
 INC sg_x+1
.fsg_jj
 JMP fsg_ry             \ patched: fsg_up while y < 0
.fsg_m3
 TXA                    \ x - step = x + ~step + 1 (same A, C, V as SBC)
 EOR #&FF
 SEC
 ADC sg_x
 STA sg_x
 BCS fsg_jj
 DEC sg_x+1
 BRA fsg_jj

.sg_ax  EQUW 0          \ segment end points: ax, ay, bx, by would be
.sg_ay  EQUW 0          \ contiguous with this order for the swap: ax, ay
.sg_bx  EQUW 0
.sg_by  EQUW 0
.sg_x   EQUW 0
.sg_y   EQUW 0
.sg_y1  EQUW 0
.sg_dx  EQUB 0
.sg_dy  EQUB 0
.sg_sx  EQUB 0
.sg_q   EQUB 0
.sg_r   EQUB 0
.sg_err EQUB 0

\ f_parity: per row, sort the boundaries and set the colour at the left end

.f_parity
 LDY R_NDT
.fpa1
 LDA R_NDN,Y            \ sort up to four (insertion sort by hand)
 CMP #2
 BCC fpa5
 LDA R_NDX0,Y
 CMP R_NDX1,Y
 BCC fpa2
 LDX R_NDX1,Y
 STA R_NDX1,Y
 TXA
 STA R_NDX0,Y
.fpa2
 LDA R_NDN,Y
 CMP #3
 BCC fpa5
 LDA R_NDX1,Y           \ insert X2
 CMP R_NDX2,Y
 BCC fpa3
 LDX R_NDX2,Y
 STA R_NDX2,Y
 TXA
 STA R_NDX1,Y
 LDA R_NDX0,Y
 CMP R_NDX1,Y
 BCC fpa3
 LDX R_NDX1,Y
 STA R_NDX1,Y
 TXA
 STA R_NDX0,Y
.fpa3
 LDA R_NDN,Y
 CMP #4
 BCC fpa5
 LDA R_NDX2,Y           \ insert X3
 CMP R_NDX3,Y
 BCC fpa5
 LDX R_NDX3,Y
 STA R_NDX3,Y
 TXA
 STA R_NDX2,Y
 LDA R_NDX1,Y
 CMP R_NDX2,Y
 BCC fpa5
 LDX R_NDX2,Y
 STA R_NDX2,Y
 TXA
 STA R_NDX1,Y
 LDA R_NDX0,Y
 CMP R_NDX1,Y
 BCC fpa5
 LDX R_NDX1,Y
 STA R_NDX1,Y
 TXA
 STA R_NDX0,Y
.fpa5
.fpa8
 CPY R_NDB
 INY
 BCC P%+3
 RTS
 JMP fpa1

\ ------------------------------------------------------------------------------
\ f_behind: is ship f_si behind the planet, with the first vertex of its first
\ visible face inside the planet's disc? C set if so (don't draw it)
\ ------------------------------------------------------------------------------

.f_behind
 LDA F_PLON
 CMP #1                 \ C clear (not behind) if there is no planet
 BCS P%+3
 RTS
 LDX f_si               \ further away than the planet?
 LDA F_PLZL
 CMP F_SZL,X
 LDA F_PLZH
 SBC F_SZH,X
 BCS fbh8               \ planet z >= ship z: in front
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
 LDA (fz_v3),Y          \ dx = x - planet x (16-bit)
 SEC
 SBC F_PLX
 STA fz_t
 INY
 LDA (fz_v3),Y
 SBC F_PLX+1
 JSR f_abs16            \ -> A = |dx| if < 256, else C set
 BCS fbh8
 STA f_bdx
 INY
 LDA (fz_v3),Y          \ dy = y - planet y
 SEC
 SBC F_PLY
 STA fz_t
 INY
 LDA (fz_v3),Y
 SBC F_PLY+1
 JSR f_abs16
 BCS fbh8
 CMP F_PLR              \ |dy| <= r and |dx| <= half-width(|dy|)?
 BEQ fbh3
 BCS fbh8
.fbh3
 TAX
 LDA F_HW,X
 CMP f_bdx
 BCC fbh8
 SEC
 RTS
.fbh8
 CLC
 RTS

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
\ small, so differences fit in 8 bits): C set if it is clockwise on screen
\ (front-facing), i.e. (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0) > 0

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
 BMI fwn9               \ negative: back face
 ORA fw_l
 BEQ fwn9               \ zero: edge-on
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
