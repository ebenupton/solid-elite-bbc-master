\ ============================================================================
\ raster.asm -- filled-polygon / disc-layer / line / dot / star rasteriser for
\ the double-buffered CMYK MODE 1 Elite (BBC Master, 65C02).  See
\ docs/renderer.md for the screen layout and the frame model.
\
\ Files: raster_vars.asm and raster_scr.asm hold every variable and array the
\ caller reads or writes, and the state the rasteriser's parts share (the
\ shared workspace in main RAM, which every bank sees).  The code, tables and
\ private state are in three windows of sideways RAM (docs/memory-map.md):
\   this file, the shared region: bank 5 &9000-&BFFF (the per-x tables, the
\     boundary arrays, R_SETBUF, r_spc, the 24 row runs and their tails, the
\     stars), seen with either window below;
\   raster_disc.asm, the disc window: bank 5 &8000-&8FFF, paged with ROMSEL 5
\     (RASTBANK): R_DISCROWS, the dirty repair, R_INIT and R_RESETBUF;
\   raster_poly.asm and raster_line.asm, the polygon window: ANDY, paged with
\     ROMSEL &85 (RASTPOLY, ANDY over bank 5): R_POLY and R_LINE (R_LINE's
\     cold part, raster_lcold.asm, and R_POLY's arithmetic are here, for room).
\ The caller (the frame layer's T_ trampolines) pages ROMSEL &85 for R_POLY
\ and R_LINE and 5 for the rest; each returns with what it was entered with.
\ R_SETBUF pages the polygon window in for its operands there and 5 back.
\ Nothing calls between the two windows.  INCLUDE this file at &9000 (its
\ runs must start at a page whose number is a multiple of 32: asserted).  It
\ references no Elite symbol; all labels start with r_ / R_ / RZ_ (and r7_
\ for code that came from bank 7).  CPU 1 is selected.  The store runs are
\ self-modified (an RTS is planted and removed again), so it must run from
\ RAM.
\
\ ---------------------------------------------------------------- zero page
\ &06-&27 are used (the caller saves/restores them around rendering).
\   R_COLE, R_COLO  fill colour pair: byte for even rows, byte for odd rows
\   R_XL, R_XR      span ends for R_SPAN / R_MARKDIRTY (inclusive pixels)
\   R_CL, R_CR      clip window x min/max (inclusive). 1 <= CL <= CR <= 254
\   R_CT, R_CB      clip window y min/max (inclusive). 0 <= CT <= CB <= 191
\   R_DCE, R_DCO    disc colour pair (R_DISCROWS)
\   everything else in &10-&27 is internal scratch (RZ_*), clobbered by calls.
\ The clip window should stay constant from frame to frame; black the window
\ and R_RESETBUF both buffers after changing it.
\
\ ---------------------------------------------------------------- variables
\ (raster_vars.asm; empty span: L = 255, R = 0; for R_WL/R_WR, R = 0)
\   R_PN               polygon vertex count (1..16; more are ignored)
\   R_COL2, R_COL3     R_POLY's colour bytes for rows y AND 3 = 2, 3 (with
\                      R_COLE, R_COLO for rows 0, 1)
\   R_PXL/R_PXH/R_PYL/R_PYH  16-entry vertex arrays (signed 16-bit, y down)
\   R_X0,R_Y0,R_X1,R_Y1      line end points, signed 16-bit words (lo, hi)
\   R_SN               star count (0..24)
\   R_SX,R_SY,R_SS     24-entry star arrays: x, y (8-bit), size 1..3 (0: none)
\   R_SCOL             star colour byte (R_INIT sets &FF = logical colour 3)
\   R_NDT, R_NDB       new disc rows for R_DISCROWS (NDT > NDB: no disc)
\   R_NDISCL/R_NDISCR  new disc spans (rows NDT..NDB only) [192 each]
\   R_DIRTYL0/R0, R_DIRTYL1/R1  per-buffer dirty extents  [192 each]
\   R_DISCL0/R0,  R_DISCL1/R1   per-buffer disc spans     [192 each]
\   R_WL, R_WR         this frame's written extents (see R_DISCROWS) [192]
\   R_NDF              0: this frame's disc is plain colour A (the arrays
\                      below are ignored); else each disc row has:
\   R_NDN              boundaries in the row, 0..4                 [192]
\   R_NDX0..R_NDX3     their x, ascending, inside (NDISCL, NDISCR]: pixels
\                      >= x take the other colour (flips at or left of
\                      NDISCL are folded into R_NDP by the caller)   [192]
\   R_NDP              bit 0: colour at the span's left end before any
\                      flip (0 = A = R_DCE/R_DCO, 1 = B = R_DBE/R_DBO) [192]
\   R_DBE, R_DBO       colour B pair
\   (R_PTA/R_PTB, R_PYS..R_PCR1, R_BD*: private to the rasteriser.)
\ Coordinates passed to R_POLY / R_LINE must lie in -16384..16383.
\
\ ---------------------------------------------------------------- routines
\ Registers A, X, Y are not preserved unless stated.  Decimal mode must be off.
\
\ R_INIT       once at startup: clip window = 1..254 x 1..191, R_SCOL = &FF,
\              all per-buffer state empty, R_SETBUF 0.  Does not touch the
\              screen: follow with R_RESETBUF on a black window for each
\              buffer.
\ R_SETBUF     A = buffer 0/1 whose state arrays (dirty, disc, stars) the
\              following calls use.  Call it before drawing each frame.  It
\              self-modifies the code: ~85 operand high bytes are stored
\              (~400 cycles) when the buffer changes.
\ R_RESETBUF   forget the current buffer's state (no dirty, no disc, no
\              stars) without touching the screen; the caller guarantees the
\              buffer's clip window is black.  ~5000 cycles.  No R_INIT needed.
\ R_SPAN       Y = row, fill pixels R_XL..R_XR (within the clip window, XL<=XR)
\              with the colour pair.  Pure drawing: no state is updated.
\              Pass R_COLE = R_COLO = 0 for black.
\ R_POLY       filled convex polygon (R_PN, R_PXL..R_PYH), either winding, in
\              a 4-row colour: row y takes R_COLE, R_COLO, R_COL2, R_COL3 for
\              y AND 3 = 0, 1, 2, 3 (a 4x4 dither tile; set R_COL2 = R_COLE and
\              R_COL3 = R_COLO for a 2-row colour pair).  Pixel (x,y)
\              (centre at integer x,y) is filled when it
\              is inside, using a top-left rule: rows y0 <= y < y1 of each
\              edge, pixels ceil(xleft) <= x < ceil(xright), exact integer
\              edge stepping from the upper end point, so polygons sharing an
\              edge tile with no gaps or overlaps.  Clipped to the window.
\              Extends DIRTY of the current buffer.  Fast path when every
\              coordinate is 0..255.
\ R_LINE       1-pixel line R_X0,R_Y0 - R_X1,R_Y1 (inclusive), clipped; pixel
\              colour = the dither at its position.  Bresenham along the major
\              axis stepped in the increasing direction; minor coordinate =
\              round-half-up.  Extends DIRTY.  Fast path when both ends are
\              inside the window.
\ R_DOT        X = x, Y = y, A = size: 1 = 1x1, 2 = 2x1, 3 = 2x2 (right/down).
\              Clipped.  Extends DIRTY.
\ R_STARERASE  black every star pixel R_STARPLOT set last time in this buffer.
\ R_STARPLOT   plot stars R_SX/SY/SS (R_SN of them) in R_SCOL.  A star row's
\              pixels within one screen byte are set only if all of them are
\              black there (else that byte is left alone); remembered for
\              R_STARERASE.  It must be the frame's last drawing (after the
\              text overlay): stars then only ever replace black that stays
\              black, so neither plotting nor erasing them touches R_WL/R_WR.
\ R_DISCROWS   the incremental disc layer for the current buffer (see below).
\ R_MARKDIRTY  Y = row, extend this buffer's DIRTY[y] by R_XL..R_XR (use it
\              for anything else drawn into the buffer, e.g. text, so the next
\              R_DISCROWS on this buffer repairs it).
\
\ Frame order for buffer b:  R_SETBUF b; R_STARERASE; (fill R_NDISC*, R_NDT,
\ R_NDB, R_DCE/R_DCO) R_DISCROWS; R_POLY/R_LINE/R_DOT ...; text; R_STARPLOT.
\
\ R_DISCROWS first hands the dirty rows that are neither old nor new disc rows
\ to bank 7 (r7_crep): those rows hold only shapes over black there (text
\ cells under them are redrawn through R_WL/R_WR), so
\ the extent is widened to whole bytes and blacked by one row run, R_WL/R_WR
\ set to it; the row loop below then only visits the disc rows.
\ R_DISCROWS, per row y of the clip window: writes the disc colour on the new
\ span minus the intact part of the old one (old span minus old dirty) and
\ black on (old span + old dirty) minus the new span; then DISC[b][y] = new,
\ DIRTY[b][y] = empty.  Where the old disc is intact and an end moves, the
\ bytes between the old and new end are rewritten whole (black / disc / disc
\ from the new end on): pixels outside the disc there are black anyway.  It
\ also starts the frame's R_WL/R_WR (clearing last frame's rows): afterwards
\ they hold, per row, the extent of the disc-layer writes (and of the
\ dirty repair).  Shapes are NOT added to R_WL/R_WR: what was written this
\ frame is R_WL/R_WR[y] union DIRTY[b][y].
\ Rows of R_NDISCL/R in NDT..NDB with NDISCL = 255 (or L > R) are empty;
\ spans are clamped to the clip window.
\ Two-colour discs (R_NDF <> 0): pixel x of a disc row has colour R_NDP
\ EOR (the number of its boundaries <= x).  Each buffer remembers its rows'
\ boundaries.  A changed row with no dirty extent is a list of edges (span
\ start, flips, span end + 1), each with an old and a new position; a flip
\ that crossed an end is matched by a virtual one there.  When the strips
\ between each edge's positions are in order, only they are written (r_dq
\ if only boundaries moved, else r_dpe); otherwise, and for rows with a
\ dirty extent, the row is repainted whole (r_drg).  New spans are clamped to the clip window; pass
\ them already clamped (with flips at or left of NDISCL folded into R_NDP)
\ so unchanged rows are recognised by the cheap comparison.  A change of
\ the colours A/B must be handled by the caller as now: fold the old disc
\ into DIRTY (R_MARKDIRTY) first.
\ ============================================================================

CPU 1

R_COLE  = &06
R_COLO  = &07
R_XL    = &08
R_XR    = &09
R_CL    = &0A
R_CR    = &0B
R_CT    = &0C
R_CB    = &0D
R_DCE   = &0E
R_DCO   = &0F
RZ_PA   = &10           \ (lo = y AND 7, hi = row page)  bytes of columns 0..31
RZ_PB   = &12           \ (lo = y AND 7, hi = row page+1) columns 32..63
RZ_PP   = &14           \ RTS plant pointer / pixel pointer
RZ_COL  = &16           \ this row's colour byte
RZ_Y    = &17           \ current row
RZ_SA   = &18           \ edge A: x (16)            } side 0 (offset 0)
RZ_CE   = &18           \ (phase B: this row pair's colours, even and odd rows)
RZ_CO   = &19
RZ_TA   = &1A           \ edge A: error term (16)   }
RZ_XE   = &1A           \ (phase B: COLE EOR COL2, COLO EOR COL3)
RZ_XO   = &1B
RZ_SB   = &1C           \ edge B: x (16)            } side 1 (offset 4)
RZ_TB   = &1E           \ edge B: error term (16)   }
RZ_T0   = &20
RZ_T1   = &21
RZ_T2   = &22
RZ_T3   = &23
RZ_T4   = &24
RZ_T5   = &25
RZ_T6   = &26
RZ_T7   = &27
\ R_LINE's (gfx-raster_line.asm; here, as gfx-raster_lcold.asm uses them too)
l_x0 = &18              \ (rl_gen's pixel-by-pixel loop: x, y, as l_x0,X)
l_y0 = &19
l_x1 = &1A
l_y1 = &1B
l_e  = &1C
l_m  = &1D
l_n  = &1E
l_a  = &1F
l_b  = &20
l_x  = &21
l_k  = &22              \ kind (0..3)

r_opSTA = &99           \ STA abs,Y (the row runs are indexed by the row, as bank 7's)
r_opRTS = &60


\ (bank 5 from &9000: the rasteriser's shared region, seen with either window)
.r_start

\ ============================================================================
\ The boundary arrays of two-colour discs (R_DISCROWS, r_dbm): each buffer's
\ last boundaries per row, up to two (a row with more is stored as count
\ &80, unknown: its next change is a full repaint; the gate's beach balls
\ have three in 3-5% of their rows, four in none).  Each buffer's four
\ arrays are contiguous, buffer 1's &300 after buffer 0's, so that the two
\ arrays of a pair share their low byte (r_dbm patches only operands' high
\ bytes, from r_sbh_bd*).  The most read, R_BDN and R_BDX0, are at low
\ bytes &00 and &40: reading them ,X never crosses a page (R_BDP, at &80,
\ does for rows 128 on).
\ ============================================================================
.R_BDN0  SKIP 192       \ boundaries per row, 0..2, or &80: more (unknown)
.R_BDX10 SKIP 192       \ their x (raw), the second ...
.R_BDP0  SKIP 192       \ bit 0: the colour at the span's left end
.R_BDX00 SKIP 192       \ ... and the first
.R_BDN1  SKIP 192       \ buffer 1's (= buffer 0's + &300)
.R_BDX11 SKIP 192
.R_BDP1  SKIP 192
.R_BDX01 SKIP 192
ASSERT R_BDN1 = R_BDN0 + &300 AND R_BDX01 = R_BDX00 + &300
\ Row set-up.  Y = row (0..191; kept).  Sets RZ_Y, RZ_PA, RZ_PB, the run page
\ (RZ_PP+1 and r_jsr+2).  Clobbers A.
.r_rowset
  STY RZ_Y
  TYA
  AND #7
  STA RZ_PA
  STA RZ_PB
  TYA
  LSR A
  LSR A
  AND #&FE
  ORA #&40
  STA RZ_PA+1
  INC A
  STA RZ_PB+1
  TYA
  LSR A
  LSR A
  LSR A
  CLC
  ADC #HI(r_run0)
  STA RZ_PP+1
  STA r_jsr+2
  RTS
\ r_dw: span A..X (A <= X) in RZ_COL on the row set up; tracks wmin/wmax
.r_dw
{
  STA R_XL
  STX R_XR
  CMP r_wmin
  BCS w1
  STA r_wmin
.w1
  CPX r_wmax
  BCC w2
  STX r_wmax
.w2
  LDX R_XL
  JMP r_spc
}
\ r_bstore: Y = row: remember the row's new boundaries (raw) in this buffer;
\ a row with more than two is stored as unknown (count &80)
.r_bstore
  LDA R_NDN,Y
  CMP #3
  BCS bsu
.^r_pt98 STA r_bdn,Y
  LDA R_NDP,Y
  AND #1
.^r_pt99 STA r_bdp,Y
  LDA R_NDX0,Y
.^r_pt100 STA r_bdx0,Y
  LDA R_NDX1,Y
.^r_pt101 STA r_bdx1,Y
  RTS
.bsu
  LDA #&80
.^r_pt102 STA r_bdn,Y
  RTS

ASSERT r_s1y = r_s0y + &300 AND r_s1x = r_s0x + &300
ASSERT r_s1a = r_s0a + &300 AND r_s1b = r_s0b + &300

\ ============================================================================
\ Per-buffer row arrays: buffer 1's are buffer 0's + &300 (R_SETBUF adds 3 to
\ the high byte of every patched operand).
\ ============================================================================
r_ta = R_PTA            \ polygon edge tables (raster_scr)
r_ystart = R_PYS        \ polygon rows ystart..ylast, yend = ylast + 1, any x
r_ylast = R_PYL1        \ outside CL..CR (raster_scr: bank 7's phase A sets
r_yend = R_PYE          \ them for 16-bit polygons), CR + 1
r_xclip = R_PXC
r_cr1 = R_PCR1
r_tb = R_PTB

\ the API arrays live in raster_vars.asm; the rasteriser's private state,
\ R_PRBUF (the current buffer), R_PRDYT/R_PRDYB (per buffer: rows that may
\ have a dirty extent), R_PRDST/R_PRDSB (per buffer: rows of its disc),
\ R_PRSCNT (per buffer: star records), R_PRECNT (per buffer: star records
\ erased, not yet in WL), R_PRWT/R_PRWB (rows of WL/WR that may be non-empty)
\ and R_PRBMODE (per buffer: its rows may hold boundaries), is at the end of
\ the shared region (gfx-raster_lcold.asm)
r_dl = R_DIRTYL0
r_dr = R_DIRTYR0
r_sl = R_DISCL0
r_sr = R_DISCR0
r_dl1 = R_DIRTYL1
r_dr1 = R_DIRTYR1
r_sl1 = R_DISCL1
r_sr1 = R_DISCR1
r_bdn = R_BDN0          \ per-buffer boundary rows (patched like r_dl)
r_bdp = R_BDP0
r_bdx0 = R_BDX00
r_bdx1 = R_BDX10

\ ============================================================================
\ R_SETBUF: A = buffer.  Patches every buffer-dependent operand (high byte).
\ ============================================================================
.R_SETBUF
{
  AND #1
  CMP R_PRBUF
  BNE go
  RTS
.go
  STA R_PRBUF
  TAX
  LDA r_sbh_dl,X          \ group r_dl
  STA r_pt408+2
  STA r_pt409+2
  STA r_pt01+2
  STA r_pt02+2
  STA r_pt05+2
  STA r_pt06+2
  STA r_pt19+2
  STA r_pt23+2
  STA r_pt25+2
  STA r_pt46+2
  STA r_pt48+2
  STA r_pt88+2
  LDA r_sbh_dr,X          \ group r_dr
  STA r_pt03+2
  STA r_pt04+2
  STA r_pt07+2
  STA r_pt08+2
  STA r_pt20+2
  STA r_pt24+2
  STA r_pt47+2
  STA r_pt49+2
  LDA r_sbh_s0a,X          \ group r_s0a
  STA r_pt32+2
  STA r_pt36+2
  STA r_pt416+2
  STA r_pt418+2
  LDA r_sbh_s0b,X          \ group r_s0b
  STA r_pt33+2
  STA r_pt37+2
  LDA r_sbh_s0x,X          \ group r_s0x
  STA r_pt31+2
  STA r_pt35+2
  STA r_pt415+2
  LDA r_sbh_s0y,X          \ group r_s0y
  STA r_pt30+2
  STA r_pt34+2
  STA r_pt414+2
  LDA r_sbh_sl,X          \ group r_sl
  STA r_pt17+2
  STA r_pt21+2
  STA r_pt26+2
  STA r_pt45+2
  STA r_pt50+2
  STA r_pt53+2
  STA r_pt54+2
  STA r_pt89+2
  STA r_pt97+2
  STA r_pt131+2
  STA r_pt132+2
  STA r_pt144+2
  STA r_pt150+2
  STA r_pt152+2
  STA r_pt399+2
  LDA r_sbh_sr,X          \ group r_sr
  STA r_pt18+2
  STA r_pt22+2
  STA r_pt27+2
  STA r_pt51+2
  STA r_pt52+2
  STA r_pt55+2
  STA r_pt90+2
  STA r_pt133+2
  STA r_pt140+2
  STA r_pt145+2
  STA r_pt151+2
  STA r_pt153+2
  JMP r_sbpoly             \ (phase B's operands, in the polygon window)
}
\ ============================================================================
\ r_spc: the span core.  Row set up (r_rowset), RZ_COL = colour byte,
\ X = R_XL = left pixel, R_XR = right pixel, R_XL <= R_XR.  Clobbers A, X, Y,
\ RZ_T7, RZ_PP.
\ ============================================================================
.r_spc
{
  TXA                     \ N = xl >= &80 (from TXA)
  BMI lb
  EOR R_XR
  CMP #4
  BCC one                 \ both ends in one byte
  LDY r_xo,X
  LDA (RZ_PA),Y           \ left edge, columns 0..31
  EOR RZ_COL
  AND r_lm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
.run
  LDY R_XR
  LDA r_j-4,Y             \ plant: column xr DIV 4
  STA RZ_PP
  LDA r_j,X               \ entry: column xl DIV 4 + 1 (= the plant when no
  STA r_jsr+1             \ whole byte lies between: the JSR hits the RTS)
  LDA #r_opRTS
  STA (RZ_PP)
  LDY RZ_Y                \ (the run is indexed by the row)
  LDA RZ_COL
.^r_jsr
  JSR &FFFF
  LDX R_XR                \ right edge (A = RZ_COL still; N = XR >= &80)
  BMI rb
  LDY r_xo,X
  EOR (RZ_PA),Y
  AND r_rm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  LDA #r_opSTA
  STA (RZ_PP)
  RTS
.rb
  LDY r_xo,X
  EOR (RZ_PB),Y
  AND r_rm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  LDA #r_opSTA
  STA (RZ_PP)
  RTS
.lb                       \ xl >= &80 (A = xl)
  EOR R_XR
  CMP #4
  BCC one                 \ both ends in one byte
  LDY r_xo,X
  LDA (RZ_PB),Y           \ left edge, columns 32..63
  EOR RZ_COL
  AND r_lm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  BRA run
.one
  LDY r_xo,X
  CPX #&80                \ XL, XR differ only in bits 0-1 (XL EOR XR < 4)
  BCS ob
  LDA (RZ_PA),Y
  EOR RZ_COL
  AND r_lm,X
  LDX R_XR
  AND r_rm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  RTS
.ob
  LDA (RZ_PB),Y
  EOR RZ_COL
  AND r_lm,X
  LDX R_XR
  AND r_rm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  RTS
}

\ ============================================================================
\ R_SPAN: Y = row, R_XL..R_XR, colour pair R_COLE/R_COLO.
\ ============================================================================

\ ============================================================================
\ Pixel address: X = x, Y = y -> RZ_PP = address of the byte.  Keeps X, Y.
\ ============================================================================

\ ============================================================================
\ r_pset: X = x, Y = y (inside the clip window): pixel in the colour pair's
\ dither, extends DIRTY[y] and the buffer's row range.  Clobbers A; keeps X, Y.
\ ============================================================================

\ r_pclip: X = x, Y = y: r_pset (and row range) if inside the clip window

\ ============================================================================
\ R_DOT: X = x, Y = y, A = size (1 = 1x1, 2 = 2x1, 3 = 2x2)
\ ============================================================================

\ ============================================================================
\ R_MARKDIRTY: Y = row, extend DIRTY[b][y] by R_XL..R_XR.
\ ============================================================================


\ R_SETBUF's last part: phase B's DIRTY operands, in the polygon window (ANDY:
\ entered and left with ROMSEL RASTBANK, X = buffer)
.r_sbpoly
  LDA #RASTPOLY
  STA &F4
  STA &FE30
  LDA r_sbh_dl,X          \ group r_dl
  STA r_pt60+2            \ bankcheck: ok (paged in above)
  STA r_pt410+2           \ bankcheck: ok (paged in above)
  STA r_pt61+2            \ bankcheck: ok (paged in above)
  STA r_pt411+2           \ bankcheck: ok (paged in above)
  LDA r_sbh_dr,X          \ group r_dr
  STA r_pt62+2            \ bankcheck: ok (paged in above)
  STA r_pt412+2           \ bankcheck: ok (paged in above)
  STA r_pt63+2            \ bankcheck: ok (paged in above)
  STA r_pt413+2           \ bankcheck: ok (paged in above)
  LDA #RASTBANK
  STA &F4
  STA &FE30
  RTS


\ ----------------------------------------------------------------------------
\ The polygon window's arithmetic (R_POLY's phase A, gfx-raster_poly.asm),
\ here for room: r_div8, r_dvq and the 32-bit multiply and divide with their
\ variables (none uses anything of the polygon window's)
\ ----------------------------------------------------------------------------
\ r_div8: A / r_v0 -> r_m0 quotient, A remainder (clobbers X).
.r_div8
{
  STA RZ_T6               \ dividend, becoming the quotient
  LDA r_v0
  STA RZ_T7
  LDA #0
  LDX #8
.lp
  ASL RZ_T6
  ROL A
  BCS sb
  CMP RZ_T7
  BCC ns
.sb
  SBC RZ_T7
  INC RZ_T6
.ns
  DEX
  BNE lp
  LDX RZ_T6
  STX r_m0
  RTS
}

\ r_dvq: A / RZ_T1 (A >= RZ_T1 >= 1) -> r_m0 quotient, A remainder.
\ Repeated subtraction when the quotient is small (divisor >= 16).
.r_dvq
{
  LDX RZ_T1
  CPX #16
  BCC small
  LDX #&FF                \ divisor >= 16: quotient < 16
  SEC
.lp
  INX
  SBC RZ_T1
  BCS lp
  ADC RZ_T1
  STX r_m0
  RTS
.small
  STA RZ_T6               \ divisor < 16: quotient < 16 unless A >= 16 * d
  TXA
  ASL A
  ASL A
  STA RZ_T7               \ 4d
  ASL A
  ASL A                   \ 16d (< 256)
  CMP RZ_T6
  BEQ long
  BCC long
  LDA RZ_T6
  LDX #&FC
  SEC
.l4
  INX
  INX
  INX
  INX
  SBC RZ_T7
  BCS l4
  ADC RZ_T7
  DEX
.l1
  INX
  SBC RZ_T1
  BCS l1
  ADC RZ_T1
  STX r_m0
  RTS
.long
  LDA RZ_T6
  LDX RZ_T1
  STX r_v0
  JMP r_div8
}
\ the 32-bit multiply and divide
.rp_m0 EQUB 0           \ 32-bit dividend / product; quotient m0,m1
.rp_m1 EQUB 0
.rp_m2 EQUB 0           \ remainder m2,m3
.rp_m3 EQUB 0
.rp_v0 EQUB 0           \ divisor
.rp_v1 EQUB 0
.rp_ma EQUW 0           \ multiplicand
.rp_mb EQUW 0           \ multiplier
.rp_mul16
{
  LDA #0
  STA rp_m2
  STA rp_m3
  LDX #16
.lp
  LSR rp_mb+1
  ROR rp_mb
  BCC ns
  CLC
  LDA rp_m2
  ADC rp_ma
  STA rp_m2
  LDA rp_m3
  ADC rp_ma+1
  STA rp_m3
.ns
  ROR rp_m3
  ROR rp_m2
  ROR rp_m1
  ROR rp_m0
  DEX
  BNE lp
  RTS
}
.rp_div32
{
  LDX #16
.lp
  ASL rp_m0
  ROL rp_m1
  ROL rp_m2
  ROL rp_m3
  BCS sb
  LDA rp_m2
  CMP rp_v0
  LDA rp_m3
  SBC rp_v1
  BCC ns
.sb
  LDA rp_m2
  SBC rp_v0
  STA rp_m2
  LDA rp_m3
  SBC rp_v1
  STA rp_m3
  INC rp_m0
.ns
  DEX
  BNE lp
  RTS
}

\ (free to the per-x tables)
.r_tfree

\ ============================================================================
\ Page-aligned per-x tables, at &9C00: the row runs after them start at &A000
\ (a page whose number is a multiple of 32: asserted below)
\ ============================================================================
ASSERT P% <= r_start + &C00
SKIP r_start + &C00 - P%
.r_tables
.r_xo                   \ (8 * (x DIV 4)) AND &FF : edge byte offset
FOR x, 0, 255
  EQUB (x * 2) AND &F8
NEXT
.r_jm                   \ 3 * (x DIV 4) - 3 = r_j[x - 4]: run plant offset (column x DIV 4)
FOR x, 0, 255           \ (read as r_j-4,Y with Y = xr >= 4: page-aligned, no crossing)
  IF x < 4
    EQUB &F8              \ (what r_j-4,Y read here before: r_xo[252..255])
  ELSE
    EQUB 3 * (x DIV 4) - 3
  ENDIF
NEXT
r_j = r_jm + 4          \ r_j,X = 3 * (x DIV 4) for X = xl <= 251 (never crosses the page)
.r_lm                   \ pixels (x AND 3)..3 of a byte
FOR x, 0, 255
  EQUB ((&F0 >> (x AND 3)) AND &F0) OR (&0F >> (x AND 3))
NEXT
.r_rm                   \ pixels 0..(x AND 3) of a byte
FOR x, 0, 255
  EQUB ((&F0 << (3 - (x AND 3))) AND &F0) OR ((&0F << (3 - (x AND 3))) AND &0F)
NEXT

\ ============================================================================
\ The store runs: one page per character row r (24), STA &4000+&200r+8c-8r,Y (Y =
\ the row: the same form as bank 7's r7_rrun) for
\ c = 1..63 then RTS (190 bytes).  The 66 bytes after each run hold variables.
\ ============================================================================
MACRO R_RUN r
  FOR c, 1, 63
    STA &4000 + r * &200 + c * 8 - r * 8, Y
  NEXT
  RTS
  EQUB 0                  \ spare: the 'nothing planted' target (offset 190)
ENDMACRO

MACRO R_ENDPAGE r
  ASSERT P% <= r_run0 + (r + 1) * &100
  ALIGN &100
ENDMACRO

.r_run0 R_RUN 0
.r_s0y SKIP 48          \ star records, buffer 0: row
.r_dsz EQUB 0           \ R_DOT
.r_dx EQUB 0
.r_dy EQUB 0
.r_k EQUB 0             \ stars
.r_si EQUB 0
R_ENDPAGE 0
.r_run1 R_RUN 1
.r_s0x SKIP 48          \ buffer 0: x of first pixel
R_ENDPAGE 1
.r_run2 R_RUN 2
.r_s0a SKIP 48          \ buffer 0: mask set in column x DIV 4
R_ENDPAGE 2
.r_run3 R_RUN 3
.r_s1y SKIP 48          \ buffer 1 (= buffer 0 + &300)
R_ENDPAGE 3
.r_run4 R_RUN 4
.r_s1x SKIP 48
R_ENDPAGE 4
.r_run5 R_RUN 5
.r_s1a SKIP 48
R_ENDPAGE 5
.r_run6 R_RUN 6
.r_s0b SKIP 48          \ buffer 0: mask set in column x DIV 4 + 1
R_ENDPAGE 6
.r_run7 R_RUN 7
.r_s0r SKIP 48          \ star records, buffer 0: row
R_ENDPAGE 7
.r_run8 R_RUN 8
.r_s1r SKIP 48          \ buffer 1: row
.r_m0 EQUB 0            \ r_div8, r_dvq: quotient
.r_v0 EQUB 0            \ r_div8: divisor
.r_sbd EQUB 0           \ R_SETBUF delta
R_ENDPAGE 8
.r_run9 R_RUN 9
.r_s1b SKIP 48
R_ENDPAGE 9
.r_run10 R_RUN 10
.r_cx EQUB 0            \ COLE EOR COLO
.r_cb1 EQUB 0           \ CB + 1
.r_n EQUB 0
.r_sbbdb EQUB &FF       \ buffer r_dbm's operands are patched for
.r_dsub EQUB 0          \ r_dmb -> r_drg: repaint only the dirty part
.r_i0 EQUB 0
.r_i1 EQUB 0
.r_yminL EQUB 0
.r_yminH EQUB 0
.r_ymaxL EQUB 0
.r_ymaxH EQUB 0
.r_top EQUB 0
.r_bon EQUB 0           \ R_DISCROWS: this frame uses boundaries
.r_cc EQUB 0
.r_cidx EQUB 0, 0
.r_ccnt EQUB 0, 0
.r_cend EQUB 0, 0
.r_smx                    \ r_dmb, an unchanged dirty row (X; A = dL + 1): a
  DEC A                   \ dirty extent clear of the span only needs blacking
  CMP R_NDISCR,X          \ (r_dp1, as r_drg would)
  BEQ sms
  BCS smf                 \ dL > sR
  LDA r_pt409+2           \ dR (this buffer's R_DIRTYR: R_DIRTYL's page + 1)
  INC A
  STA smo+2
.smo
  LDA R_DIRTYR0,X
  CMP R_NDISCL,X
  BCC smf                 \ dR < sL
.sms
  INC r_dsub
  JMP r_dmgd
.smf
  TXA
  TAY
  JMP r_gd1
ASSERT HI(R_DIRTYR0) = HI(R_DIRTYL0) + 1 AND HI(R_DIRTYR1) = HI(R_DIRTYL1) + 1
ASSERT LO(R_DIRTYR0) = LO(R_DIRTYR1)
R_ENDPAGE 10
.r_run11 R_RUN 11
.r_ov SKIP 59           \ variables of routines never active together
R_ENDPAGE 11
.r_run12 R_RUN 12
.r_s1k SKIP 48          \ buffer 1: star's first pixel
R_ENDPAGE 12
\ overlay: R_DISCROWS rows
r_oL = r_ov + 4
r_oR = r_ov + 5
r_dL = r_ov + 6
r_dR = r_ov + 7
r_nL = r_ov + 8
r_nR = r_ov + 9
r_iL = r_ov + 10
r_iR = r_ov + 11
r_wmin = r_ov + 12
r_wmax = r_ov + 13
r_dcol = r_ov + 14
r_ba = r_ov + 15
r_bb = r_ov + 16
r_tl = r_ov + 17
r_fe = r_ov + 20
r_fo = r_ov + 21
r_bv = r_ov + 22        \ r_segw: the new boundaries (4)
r_ev = r_ov + 45        \ r_dpe: edges new (7), then old (7) at r_ev+7
r_nn = r_ov + 30        \ new count / colour; old count / colour
r_np = r_ov + 31
r_on = r_ov + 32
r_op = r_ov + 33
r_ns = r_ov + 34        \ strips to write (r_dp2)
r_cA = r_ov + 35        \ this row's colour A, B bytes
r_cB = r_ov + 36
r_dcr = r_ov + 37       \ r_dp2: right end colour
r_segs = r_ov + 38      \ r_drg: repaint the new span segment by segment
r_cl = r_ov + 39        \ r_canon: span, count in
r_cr = r_ov + 40
r_cn = r_ov + 41
.r_run13 R_RUN 13
.r_s0k SKIP 48          \ buffer 0: star's first pixel
R_ENDPAGE 13
.r_run14 R_RUN 14
.r_pclip
{
  CPX R_CL
  BCC out
  CPX R_CR
  BEQ ok1
  BCS out
.ok1
  CPY R_CT
  BCC out
  CPY R_CB
  BEQ ok2
  BCS out
.ok2
  TYA                     \ extend the buffer's row range by row Y
  LDY R_PRBUF
  CMP R_PRDYT,Y
  BCS n3
  STA R_PRDYT,Y
.n3
  CMP R_PRDYB,Y
  BCC n4
  STA R_PRDYB,Y
.n4
  TAY                     \ Y = row again
  JMP r_pset              \ tail call
.out
  RTS
}
\ R_SETBUF's and r_dbm's high bytes of each buffer's arrays
.r_sbh_dl EQUB HI(R_DIRTYL0), HI(R_DIRTYL1)
ASSERT LO(R_DIRTYL0) = LO(R_DIRTYL1)
.r_sbh_dr EQUB HI(R_DIRTYR0), HI(R_DIRTYR1)
ASSERT LO(R_DIRTYR0) = LO(R_DIRTYR1)
.r_sbh_s0a EQUB HI(r_s0a), HI(r_s1a)
ASSERT LO(r_s0a) = LO(r_s1a)
.r_sbh_s0x EQUB HI(r_s0x), HI(r_s1x)
ASSERT LO(r_s0x) = LO(r_s1x)
.r_sbh_s0y EQUB HI(r_s0y), HI(r_s1y)
ASSERT LO(r_s0y) = LO(r_s1y)
.r_sbh_sl EQUB HI(R_DISCL0), HI(R_DISCL1)
.r_sbh_s0k EQUB HI(r_s0k), HI(r_s1k)
ASSERT LO(r_s0k) = LO(r_s1k)
.r_sbh_s0r EQUB HI(r_s0r), HI(r_s1r)
ASSERT LO(r_s0r) = LO(r_s1r)
.r_sbh_s0b EQUB HI(r_s0b), HI(r_s1b)
ASSERT LO(r_s0b) = LO(r_s1b)
R_ENDPAGE 14
.r_run15 R_RUN 15
.r_pset
{
  TYA                     \ RZ_PP = screen address of (X, Y)
  AND #7
  ORA r_xo,X
  STA RZ_PP
  TYA
  LSR A
  LSR A
  AND #&FE
  ORA #&40
  CPX #&80
  ADC #0
  STA RZ_PP+1
  LDA r_lm,X
  AND r_rm,X
  STA RZ_T6
  TYA
  LSR A
  LDA R_COLE
  BCC ev
  LDA R_COLO
.ev
  EOR (RZ_PP)
  AND RZ_T6
  EOR (RZ_PP)
  STA (RZ_PP)
  TXA
.^r_pt01 CMP r_dl,Y
  BCS n1
.^r_pt02 STA r_dl,Y
.n1
.^r_pt03 CMP r_dr,Y
  BCC n2
.^r_pt04 STA r_dr,Y
.n2
  RTS
}
R_ENDPAGE 15
.r_run16 R_RUN 16
.R_SPAN
{
  LDA R_XR
  CMP R_XL
  BCC out
  JSR r_rowset
  TYA
  LSR A
  LDA R_COLE
  BCC ev
  LDA R_COLO
.ev
  STA RZ_COL
  LDX R_XL
  JMP r_spc
.out
  RTS
}
\ R_LINE's variables (gfx-raster_line.asm, gfx-raster_lcold.asm)
.rl_lct SKIP 8          \ R_LINE: colour byte by row AND 7
.rl_lbuf EQUB &FF       \ buffer R_LINE's DIRTY operands are patched for
\ rl_gen's variables (16-bit: lo, hi)
.rl_dx SKIP 2            \ P1 - P0: x, y (rl_dx + 2)
.rl_dy SKIP 2
.rl_ax SKIP 2            \ |dx|, |dy| (rl_ax + 2)
.rl_ay SKIP 2
.rl_d  SKIP 2            \ |d major|
.rl_a  SKIP 2            \ |d minor|
.rl_h  SKIP 2            \ d DIV 2
.rl_m0 SKIP 2            \ the left / top end: major, minor
.rl_n0 SKIP 2
.rl_i  SKIP 2            \ the first pixel inside, the last (i)
.rl_j  SKIP 2
.rl_t  SKIP 2            \ rl_mdq's signed addend
.rl_mo SKIP 1            \ major axis: 0 = x, 2 = y (an offset into R_X0.., R_CL..)
.rl_s  SKIP 1            \ bit 7: the minor coordinate decreases
.rl_lo SKIP 1            \ major window lo, hi; minor window lo, hi
.rl_hi SKIP 1
.rl_nl SKIP 1
.rl_nh SKIP 1
R_ENDPAGE 16
.r_run17 R_RUN 17
.R_DOT
{
  STA r_dsz
  STX r_dx
  STY r_dy
  JSR r_pclip
  LDA r_dsz
  CMP #2
  BCC done
  LDX r_dx
  INX
  BEQ row2
  LDY r_dy
  JSR r_pclip
.row2
  LDA r_dsz
  CMP #3
  BCC done
  LDY r_dy
  INY
  BEQ done
  LDX r_dx
  JSR r_pclip
  LDX r_dx
  INX
  BEQ done
  JSR r_pclip
.done
  RTS
}
R_ENDPAGE 17
.r_run18 R_RUN 18
.R_MARKDIRTY
{
  LDA R_XL
.^r_pt05 CMP r_dl,Y
  BCS n1
.^r_pt06 STA r_dl,Y
.n1
  LDA R_XR
.^r_pt07 CMP r_dr,Y
  BCC n2
.^r_pt08 STA r_dr,Y
.n2
  LDX R_PRBUF
  TYA
  CMP R_PRDYT,X
  BCS n3
  STA R_PRDYT,X
.n3
  CMP R_PRDYB,X
  BCC n4
  STA R_PRDYB,X
.n4
  RTS
}
.r_sbh_bdx1 EQUB HI(R_BDX10), HI(R_BDX11)
ASSERT LO(R_BDX10) = LO(R_BDX11)
.r_sbh_bdx0 EQUB HI(R_BDX00), HI(R_BDX01)
ASSERT LO(R_BDX00) = LO(R_BDX01)
.r_sbh_bdp EQUB HI(R_BDP0), HI(R_BDP1)
ASSERT LO(R_BDP0) = LO(R_BDP1)
.r_sbh_bdn EQUB HI(R_BDN0), HI(R_BDN1)
ASSERT LO(R_BDN0) = LO(R_BDN1)
ASSERT LO(R_DISCL0) = LO(R_DISCL1)
.r_sbh_sr EQUB HI(R_DISCR0), HI(R_DISCR1)
ASSERT LO(R_DISCR0) = LO(R_DISCR1)
R_ENDPAGE 18
.r_run19 R_RUN 19
.fl_htab                \ the lens flare's half-widths (gfx-flare.asm): the
MACRO FLHW r            \ widest x with x^2 + d^2 <= r^2 + r, d = 0..r (one
 FOR d, 0, r            \ page: fl_hw's high byte is fixed)
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
R_ENDPAGE 19
.r_run20 R_RUN 20
.fl_ml  SKIP 2          \ the lens flare (gfx-flare.asm): 32 D (x, y), low
.fl_mh  SKIP 2          \ and high bytes
.fl_sl  SKIP 2          \ the centres' sums S (x, y)
.fl_sh  SKIP 2
.fl_lev SKIP 1          \ the level less 3, turned down by the probes (-5..0)
R_ENDPAGE 20
.r_run21 R_RUN 21
.r_dp1
{
  JSR r_rowset
  STZ RZ_COL
.^r_pt46 LDA r_dl,Y
  STA R_XL
  STA R_WL,Y
.^r_pt47 LDA r_dr,Y
  STA R_XR
  STA R_WR,Y
  LDA #&FF
.^r_pt48 STA r_dl,Y
  LDA #0
.^r_pt49 STA r_dr,Y
  CPY R_PRWT
  BCS w1
  STY R_PRWT
.w1
  CPY R_PRWB
  BCC w2
  STY R_PRWB
.w2
  LDX R_XL
  JMP r_spc
}
R_ENDPAGE 21
.r_run22 R_RUN 22
\ r_bmn: black on [r_ba, r_bb] minus [r_nL, r_nR]
.r_bmn
{
  LDA r_nR
  CMP r_nL
  BCC whole
  LDA r_nR
  CMP r_ba
  BCC whole
  LDA r_bb
  CMP r_nL
  BCC whole
  LDA r_ba
  CMP r_nL
  BCS b2
  LDX r_nL
  DEX
  JSR r_dw
.b2
  LDA r_nR
  CMP r_bb
  BCS done
  INC A
  LDX r_bb
  JMP r_dw
.whole
  LDA r_ba
  LDX r_bb
  JMP r_dw
.done
  RTS
}
R_ENDPAGE 22
.r_run23 R_RUN 23
.r_crep5                  \ R_DISCROWS: r7_crep (returns X = R_PRBUF)
  STZ R_PRCWB
  LDA R_PRDYZ
  CMP R_PRDYA
  BCC c4                  \ (no dirty rows)
  JSR r7_crep             \ bankcheck: ok (only R_DISCROWS calls r_crep5)
.c4
  LDX R_PRBUF
  RTS
.r_cwb5                   \ R_DISCROWS: the repair's rows into R_PRWT..R_PRWB
  LDA R_PRCWB             \ (the disc rows' code assumes rows go upwards)
  CMP R_PRWB
  BCC c5
  STA R_PRWB
.c5
  RTS
\ r_bcols: Y = row: r_cA, r_cB = colour A, B bytes of the row (keeps X, Y)
.r_bcols
  TYA
  LSR A
  BCS bc1
  LDA R_DCE
  STA r_cA
  LDA R_DBE
  STA r_cB
  RTS
.bc1
  LDA R_DCO
  STA r_cA
  LDA R_DBO
  STA r_cB
  RTS
R_ENDPAGE 23
ASSERT (HI(r_run0) AND 31) = 0   \ (the repair: the row's run page is Y DIV 8 OR HI(r_run0))


\ ============================================================================
\ R_STARERASE: black the pixels R_STARPLOT set last time in this buffer.
\ Records: row (+&80: also the next byte), x, mask set in x's byte.
\ ============================================================================
.R_STARERASE
{
  LDX R_PRBUF
  LDA R_PRSCNT,X
  STA r_k
  STZ R_PRSCNT,X
  LDX #0
  CPX r_k
  BCS edone
.el
.^r_pt30 LDA r_s0y,X      \ byte address (bit 7 of the high byte: one byte)
  STA RZ_PP
.^r_pt31 LDA r_s0x,X
  BMI e1
  STA RZ_PP+1
  LDA (RZ_PP)
.^r_pt32 AND r_s0a,X      \ inverse mask
  STA (RZ_PP)
.^r_pt33 LDA r_s0b,X
  CMP #&FF
  BEQ en
  LDY #8
  AND (RZ_PP),Y
  STA (RZ_PP),Y
  BRA en
.e1
  AND #&7F
  STA RZ_PP+1
  LDA (RZ_PP)
.^r_pt418 AND r_s0a,X
  STA (RZ_PP)
.en
  INX
  CPX r_k
  BCC el
.edone
  RTS
}

\ ============================================================================
\ Stars
\ ============================================================================

{
.sdone
  LDX R_PRBUF
  LDA r_k
  STA R_PRSCNT,X
  RTS
.slow
  STX RZ_SA               \ (X = x, Y = y on every branch here)
  STY RZ_SA+1
  JSR r_strow
  LDA RZ_TA
  CMP #3
  BCC sd1
  INC RZ_SA+1
  BEQ sd1
  JSR r_strow
.sd1
  LDX RZ_TA+1
  BRA snext
.^R_STARPLOT
  STZ r_k
  LDA R_CB
  INC A
  STA cb1+1
  LDA R_SN                \ star count (only ever 0 or 19, so <= 24)
  STA sl+1                \ (patched: the loop limit)
  STA nl+1                \ (and its copy at .nl)
  LDX #&FF
.snext
  INX
.sl
  CPX #0                  \ (R_SN)
  BCS sdone
.sl2
  LDA R_SS,X
  BEQ snext
.some
  STX RZ_TA+1
  STA RZ_TA
  LDY R_SY,X
  LDA R_SX,X
  TAX                     \ fast path: x .. x+1 inside the window, in one byte,
  CPX R_CL                \ the row(s) inside
  BCC slow
  CPX R_CR
  BCS slow
  CPY R_CT                \ (two pixels split across bytes, x AND 3 = 3 with
  BCC slow                \ size >= 2: caught by the mask being 0 at .two)
.cb1
  CPY #0                  \ (CB + 1)
  BCS slow
  LDA RZ_TA
  LSR A                   \ size 1..3: C = 0 for 2; else A = 0 for 1, 1 for 3
  BCC two2                \ (size 2)
  BEQ one                 \ size 1: one pixel; 2, 3: two
  STX RZ_SA               \ (x for the second row at nx)
  CPY R_CB                \ size 3: the second row inside too? (y + 1 <= CB)
  BCS slow
.two2
  LDA r_lm,X
  AND r_rm+1,X            \ two pixels: 0 only when split across bytes
  BEQ slow                \ (x AND 3 = 3: r_lm = &11, r_rm(x+1) = &88)
.msk
  STA RZ_SB               \ the mask
.row
  TYA                     \ RZ_PP = byte of (x, y)
  AND #7
  ORA r_xo,X
  STA RZ_PP
  LDA r_ypg,Y
  CPX #&80
  ADC #0
  STA RZ_PP+1
  LDA (RZ_PP)             \ all black there?
  AND RZ_SB
  BNE nx
  LDX r_k                 \ (< 48 always: R_SN <= 24, <= 2 records a star)
  LDA R_SCOL
  AND RZ_SB
  ORA (RZ_PP)
  STA (RZ_PP)
  LDA RZ_PP
.^r_pt414 STA r_s0y,X
  LDA RZ_PP+1
  ORA #&80                \ (bit 7: no second byte)
.^r_pt415 STA r_s0x,X
  LDA RZ_SB
  EOR #&FF
.^r_pt416 STA r_s0a,X
  INC r_k
.nx
  LDA RZ_TA               \ size 3: the next row
  CMP #3
  BEQ third
  LDX RZ_TA+1             \ (snext inlined: INX, then the loop test)
  INX
.nl
  CPX #0                  \ (R_SN)
  BCC sl2
  JMP sdone
.third
  STZ RZ_TA
  LDX RZ_SA
  INY
  BRA row
.one
  LDA r_lm,X
  AND r_rm,X
  BRA msk
}

\ one row of a star: row RZ_SA+1, pixel RZ_SA (and RZ_SA+1 if size >= 2).
\ Each of the (one or two) bytes it touches is set only if all its star
\ pixels there are black; the byte address and inverse masks are recorded.
.r_strow
{
  LDY RZ_SA+1
  CPY R_CT
  BCC o1
  CPY R_CB
  BEQ r1
  BCC r1
.o1
  RTS
.r1
  LDX RZ_SA
  STZ RZ_SB+1
  LDA RZ_TA
  CMP #2
  BCS two
  CPX R_CL                \ one pixel
  BCC o1
  CPX R_CR
  BEQ one
  BCS o1
.one
  LDA r_lm,X
  AND r_rm,X
  BRA mset
.two
  CPX R_CL                \ two pixels, both inside: the fast case
  BCC clip
  CPX R_CR
  BCS clip
  TXA
  AND #3
  CMP #3
  BEQ split
  LDA r_lm,X
  AND r_rm+1,X
  BRA mset
.split
  LDA #&88
  STA RZ_SB+1
  LDA #&11
  BRA mset
.clip
  STZ RZ_SB               \ general: pixel by pixel
  CPX R_CL
  BCC c2
  CPX R_CR
  BEQ c1
  BCS c2
.c1
  LDA r_lm,X
  AND r_rm,X
  STA RZ_SB
.c2
  INX
  BEQ c4
  CPX R_CL
  BCC c4
  CPX R_CR
  BEQ c3
  BCS c4
.c3
  LDA r_lm,X
  AND r_rm,X
  PHA
  TXA
  AND #3
  BEQ c5
  PLA
  ORA RZ_SB
  STA RZ_SB
  BRA c4
.c5
  PLA
  STA RZ_SB+1
.c4
  LDX RZ_SA
  LDA RZ_SB
  ORA RZ_SB+1
  BNE ms2
  RTS
.ms2
  LDA RZ_SB
.mset
  STA RZ_SB
  TYA                     \ RZ_PP = byte of (X, Y)
  AND #7
  ORA r_xo,X
  STA RZ_PP
  TYA
  LSR A
  LSR A
  AND #&FE
  ORA #&40
  CPX #&80
  ADC #0
  STA RZ_PP+1
  LDX r_k                 \ (record slot; X = x is in RZ_SA)
  CPX #48
  BCS o2
  LDA #&FF                \ byte A
  STA RZ_T0
  LDA RZ_SB
  BEQ ba
  AND (RZ_PP)
  BNE ba
  LDA R_SCOL
  AND RZ_SB
  ORA (RZ_PP)
  STA (RZ_PP)
  LDA RZ_SB
  EOR #&FF
  STA RZ_T0
.ba
  LDA #&FF                \ byte B (next column)
  LDY RZ_SB+1
  BEQ bb
  TYA
  LDY #8
  AND (RZ_PP),Y
  BNE bf
  LDA R_SCOL
  AND RZ_SB+1
  ORA (RZ_PP),Y
  STA (RZ_PP),Y
  LDA RZ_SB+1
  EOR #&FF
  BRA bb
.bf
  LDA #&FF
.bb
.^r_pt37 STA r_s0b,X
  AND RZ_T0
  CMP #&FF
  BEQ o2                  \ nothing set
  LDA RZ_PP
.^r_pt34 STA r_s0y,X
  LDA RZ_PP+1
.^r_pt35 STA r_s0x,X
  LDA RZ_T0
.^r_pt36 STA r_s0a,X
  INC r_k
.o2
  RTS
}

\ r_lput2: pixels RZ_SB .. RZ_TA+1 of row RZ_Y in RZ_COL (row pointers set).
\ Clobbers A, X, Y.
.r_lput2
{
  LDA RZ_TA+1
  TAY                     \ Y = last pixel
  LDX RZ_SB               \ X = first
  EOR RZ_SB
  CMP #4
  BCS two
  LDA r_lm,X              \ one byte
  AND r_rm,Y
  STA RZ_T7
  LDY r_xo,X
  CPX #&80
  BCS h1
  LDA RZ_COL
  EOR (RZ_PA),Y
  AND RZ_T7
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  RTS
.h1
  LDA RZ_COL
  EOR (RZ_PB),Y
  AND RZ_T7
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  RTS
.two
  STY R_XR
  TYA                     \ adjacent bytes?
  AND #&FC
  STA RZ_T7
  TXA
  AND #&FC
  ADC #3                  \ (C = 1 from the CMP)
  CMP RZ_T7
  BEQ adj
  JMP long                \ (r_ypg sits between here and .long)
.adj
  LDY r_xo,X              \ first byte: from X on
  CPX #&80
  BCS h2
  LDA RZ_COL
  EOR (RZ_PA),Y
  AND r_lm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  BRA s2
.h2
  LDA RZ_COL
  EOR (RZ_PB),Y
  AND r_lm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
.s2
  LDX R_XR                \ second byte: up to the last
  LDY r_xo,X
  CPX #&80
  BCS h3
  LDA RZ_COL
  EOR (RZ_PA),Y
  AND r_rm,X
  EOR (RZ_PA),Y
  STA (RZ_PA),Y
  RTS
.h3
  LDA RZ_COL
  EOR (RZ_PB),Y
  AND r_rm,X
  EOR (RZ_PB),Y
  STA (RZ_PB),Y
  RTS
.^r_ypg                   \ high byte of row y's byte 0
FOR y, 0, 191
  EQUB &40 + 2 * (y DIV 8)
NEXT
.long
  STX R_XL                \ up to 12 bytes: masked ends, whole bytes stored
  TYA                     \ through a byte pointer
  SEC
  SBC R_XL
  CMP #48
  BCS span
  LDA RZ_PP               \ (RZ_PP holds a planted RTS's address: keep it)
  PHA
  LDA RZ_PP+1
  PHA
  LDA r_xo,X
  ORA RZ_PA
  STA RZ_PP
  LDA RZ_PA+1
  CPX #&80
  ADC #0
  STA RZ_PP+1
  LDA RZ_COL              \ first byte: from X on
  EOR (RZ_PP)
  AND r_lm,X
  EOR (RZ_PP)
  STA (RZ_PP)
  LDA R_XR                \ whole bytes: last/4 - first/4 - 1
  LSR A
  LSR A
  STA RZ_T7
  TXA
  LSR A
  LSR A
  SEC
  SBC RZ_T7
  EOR #&FF
  TAY
  BEQ lb
.wl
  LDA RZ_PP
  CLC
  ADC #8
  STA RZ_PP
  BCC wl1
  INC RZ_PP+1
.wl1
  LDA RZ_COL
  STA (RZ_PP)
  DEY
  BNE wl
.lb
  LDA RZ_PP               \ last byte: up to the last pixel
  CLC
  ADC #8
  STA RZ_PP
  BCC lb1
  INC RZ_PP+1
.lb1
  LDX R_XR
  LDA RZ_COL
  EOR (RZ_PP)
  AND r_rm,X
  EOR (RZ_PP)
  STA (RZ_PP)
  PLA
  STA RZ_PP+1
  PLA
  STA RZ_PP
  RTS
.span
  LDY RZ_Y                \ a span (r_rowset for the run page)
  JSR r_rowset
  LDX R_XL
  JMP r_spc
}

.r_end
PRINT "raster.asm: ", r_end - r_start, " bytes from ", ~r_start, " to ", ~r_end
