\ ******************************************************************************
\
\ gfx-hooks.asm - the glue between Master Elite's drawing code and the frame
\ layer (after the Demonstration Disc port's src/hooks.asm)
\
\ Master port: these run in game context only, with ACCCON X clear; they are
\ in the low area (elite-low.asm), with the renderer's other glue, after
\ LOW_END%, so they may lie above &3000 (the hooks that run with X set or
\ from the IRQ, gfx-lowhooks.asm, are below it). Elite's drawing routines call
\ these with a single JSR at their start. "Record mode" is QQ11 = 0 (a view that draws ships) and GFORCE = 0:
\ drawing is then recorded for FRAME instead of being done. A hook that takes
\ over pulls its return address (PLA : PLA) so its RTS returns from the hooked
\ routine itself.
\
\ ******************************************************************************


\ H_MFRAME: a main-loop iteration (M%), then the frame (TT100, and DEATH's
\ two M% calls)

.H_MFRAME
 JSR M%
                        \ fall through into hframe

\ hframe: the frame (bank 4 paged), preserving A, X, Y and the flags (the main
\ loop carries on with what M% left). LL9F (bank 4: LL9 then the frame, for
\ the title screen's rotating ship) jumps here.

.hframe
 PHP
 PHA
 PHX
 PHY
 JSR G_FRAME
 PLY
 PLX
 PLA
 PLP
 RTS

\ H_CIRC: CIRCLE in record mode records the planet disc instead (PL9 is about
\ to draw the planet's circle) and returns from CIRCLE as CIRCLE2 would:
\ C clear, LSX2 = 0 (the ball line heap in use), FLAG = 0, STP = 8, 4 or 2
\ by the radius and CNT = the first multiple of STP above 64. If the circle
\ isn't on screen (CHKON), C set as CIRCLE returns

.H_CIRC
 LDA QQ11
 ORA GFORCE
 BEQ P%+3
 RTS
 PLA
 PLA
 JSR CHKON
 BCC P%+3
 RTS
 STZ PM_OK              \ (no meridians yet: PM_HOOK sets it)
 LDA TYPE               \ (a crater planet's boundaries overwrite the beach
 CMP #128               \ ball's rows in the disc layer's arrays)
 BEQ P%+5
 STZ PS_VALID
 LDA K                  \ the radius, for PM_HOOK (PLS1 overwrites K)
 STA PM_R
 JSR G_PLANET
 LDA #0
 STA LSX2
 STA FLAG
 LDX K
 LDA #8
 LDY #72
 CPX #8
 BCC hci1
 LDA #4
 LDY #68
 CPX #60
 BCC hci1
 LDA #2
 LDY #66
.hci1
 STA STP
 STY CNT
 CLC
 RTS

\ H_WPLS2: in record mode the planet's lines are not on screen: just reset the
\ ball line heap (WP1)

.H_WPLS2
 LDA QQ11
 ORA GFORCE
 BEQ P%+3
 RTS
 PLA
 PLA
 JMP WP1

\ H_PCURVE: PLS22 is about to compute an ellipse (TGT segments): start a new
\ curve (BLINE records each point itself, through G_PPOINT). It preserves X,
\ Y and C (the caller sets A and the other flags straight after)

.H_PCURVE
 LDA QQ11
 ORA GFORCE
 BNE hpc9
 JMP G_PCURVE

\ H_MERID: PL9 has a meridian planet (TYPE 128) of radius 6 or more that
\ fits on the screen, and is about to draw its equator and meridian. In
\ record mode the renderer colours the disc as a beach ball instead: the
\ meridian window computes the frame's constants (G_MERHOOK, PM_HOOK), and
\ H_MERID returns from PL9 (Elite's half ellipses are neither computed nor
\ recorded) with TGT and K2 as PL9 would have left them: the game reads
\ both later. In direct mode it returns, and PL9 draws the lines

.H_MERID
 LDA QQ11
 ORA GFORCE
 BNE hpc9
 LDX #9                 \ K2 = nosev_x / z, as PL25 leaves it: MV40 adds
 JSR PLS1               \ K2 into the next object's y without setting it
 STA K2                 \ first (the sun's, when it follows the planet)
 LDA #31
 STA TGT
 PLA                    \ (return from PL9)
 PLA
 JMP G_MERHOOK

.hpc9
 RTS

\ H_STAR: PIXEL2 has star Y's screen position in X = x, A = y and is about to
\ fall into PIXEL (it JMPs here); in record mode it is recorded straight into the
\ rasteriser's arrays, by star index (R_SS: 2 = a dash, ZZ >= 80, 3 = a
\ double-height dash, as PIXEL draws them; 0 = none), and PIXEL2 returns as
\ PIXEL would, C = (ZZ >= 80) (not N and Z from Y: every caller reaches a
\ DEY or LDA first; nor T1 = Y: every reader of T1 writes it first). Outside
\ record mode A is restored and it jumps to PIXEL to draw it

.H_STAR                 \ (entered by JMP from PIXEL2, so RTS returns from it)
 STA R_SY,Y
.hstp                   \ (patched by pxpat: BIT #imm in record mode, BRA hst9
 BIT #hst9-hstp-2       \ outside it; was LDA QQ11 : ORA GFORCE : BNE hst9)
 TXA
 STA R_SX,Y
 LDA #2
 LDX ZZ
 CPX #80
 BCS P%+4
 LDA #3
 STA R_SS,Y
 RTS
.hst9
 LDA R_SY,Y             \ outside record mode PIXEL draws it: note where (in
 STA hA                 \ shadow RAM, the direct-mode screen), so that the first
 SEC                    \ frame in record mode can remove it (f_unstar)
 JSR G_DSTAR
 LDA hA
 JMP PIXEL

\ H_STAROFF: PIXEL2 found star Y off screen (entered by JMP, with C set and
\ A = |Y1| compared with #Y): in record mode it is not on screen. Returns as
\ PIXEL2's BCS PXR1 did as far as its callers read: C set, X and Y kept (A,
\ N and Z are dead: every caller of PIXEL2 and PIX1 reaches a DEY first, and
\ A is dead after it)

.H_STAROFF
.hsop                   \ (patched by pxpat, as hstp; was LDA QQ11 : ORA
 BIT #hso8-hsop-2       \ GFORCE : BNE hso8)
 LDA #0
 STA R_SS,Y
 RTS
.hso8
 CLC                    \ outside record mode: star Y is no longer drawn
 JMP G_DSTAR            \ (returns C set, X and Y kept)
\ H_EE31: LL9 has projected the ship (part 9, EE31, which jumps here: every
\ LL9 records, as nothing draws a ship directly, docs/renderer.md, "The
\ briefings"): record it (and its laser beam if it is firing at us) and
\ return from LL9. What LL9's parts 9 to 12 left that the game reads is set
\ as they would: bit 3 of byte #31 (on screen), bit 6 cleared if it fired,
\ XX20 (edges) and CNT (the blueprint's heap size, which LL170 leaves there);
\ and it returns as LSCLR does (A = 1, Y = 0, C set). The ship line heap is
\ not written (only the explosion clouds use it, DOEXP)

.H_EE31
 LDY #9                 \ XX20 = the number of edges (as EE31)
 LDA (XX0),Y
 STA XX20
 LDA #%00001000         \ the ship is now on screen (as EE31)
 ORA XX1+31
 STA XX1+31
 LDY #12                \ faces = byte #12 / 4
 LDA (XX0),Y
 LSR A
 LSR A
 STA GNF
 LDY #8                 \ vertices = byte #8 / 6
 LDA (XX0),Y
 LDX #0
.hee1
 CMP #6
 BCC hee2
 SBC #6
 INX
 BNE hee1
.hee2
 STX GNV
 LDX TYPE               \ the faces' type: the station's slot holds the
 CPX #SST               \ Coriolis or the Dodo (NWSPS), whose faces are
 BNE hee3               \ type DOD's
 LDA XX0
 CMP XX21+2*(DOD-1)
 BNE hee3
 LDA XX0+1
 CMP XX21+2*(DOD-1)+1
 BNE hee3
 LDX #DOD
.hee3
 STX GTYPE
 JSR G_SHIP

 BIT XX1+31             \ firing its lasers at us? (as EE31)
 BVC hee9
 LDA XX1+31
 AND #%10111111
 STA XX1+31
 LDY #6
 LDA (XX0),Y
 TAY
 LDX XX3,Y
 STX XX15
 INX
 BEQ hee9
 LDX XX3+1,Y
 STX XX15+1
 INX
 BEQ hee9
 LDX XX3+2,Y
 STX XX15+2
 LDX XX3+3,Y
 STX XX15+3
 LDA #0
 STA XX15+4
 STA XX15+5
 STA XX12+1
 LDA XX1+6
 STA XX12
 LDA XX1+2
 BPL P%+4
 DEC XX15+4
 JSR CLIP
 BCS hee9
 LDA #FC_ELASER
 STA GLCOL
 JSR G_LINE
 LDA #FC_PLINE
 STA GLCOL
.hee9
 LDY #5                 \ CNT = the blueprint's maximum heap size (as LL170)
 LDA (XX0),Y
 STA CNT
 LDA #1                 \ A = 1, Y = 0, C set, as LSCLR returns
 LDY #0
 SEC
 RTS

\ H_DOT: PIXEL with X = x, A = y (in record mode only DOEXP's explosion
\ particles reach it; stars are recorded by H_STAR): the dot is recorded
\ (unless GDRAWON is 0: PTCLS erasing the old cloud) and PIXEL returns as it
\ would: T1 = Y, C = (ZZ >= 80), N and Z from Y

.H_DOT
 STA hA
 LDA QQ11
 ORA GFORCE
 BNE hdd
 PLA
 PLA
 LDA GDRAWON
 BEQ hdz
 LDA hA
 JSR G_DOT
.hdz
 LDA ZZ
 CMP #80
 STY T1
 LDY T1
 RTS
.hdd
 LDA hA
 RTS

\ H_PTCLSE: DOEXP removing the old explosion cloud: run PTCLS (for its random
\ numbers) without recording anything

.H_PTCLSE
 STZ GDRAWON
 JSR PTCLS
 PHP
 PHA
 LDA #&FF
 STA GDRAWON
 PLA
 PLP
 RTS

\ Our laser beams: LASLI (falling into LASLI2) shows them, LASLI2 called
\ directly (main flight loop part 16, in the same iteration) removes them. In
\ record mode H_LAS1 (at LASLI's end) sets GLASV and returns from LASLI, so the
\ frame draws the beams from LASX/LASY (and clears GLASV), and H_LAS2 (at
\ LASLI2) returns from LASLI2 at once: nothing to remove

.H_LAS1
 LDA QQ11
 ORA GFORCE
 BEQ P%+3
 RTS
 PLA
 PLA
 LDA #&FF
 STA GLASV
 RTS

.H_LAS2
 LDA QQ11
 ORA GFORCE
 BEQ P%+3
 RTS
 PLA
 PLA
 RTS

\ H_CLYNS: CLYNS, after its newline, is about to clear text rows 21-23: the
\ text map's too; in record mode return from CLYNS instead of clearing the
\ screen, with A = X = Y = 0 as it does

.H_CLYNS
 JSR G_CLRTEXT
 LDA QQ11
 ORA GFORCE
 BEQ P%+3
 RTS
 PLA
 PLA
 LDA #0
 TAX
 TAY
 RTS

\ H_SIGHT: SIGHT is about to draw the laser sights (two crosshairs through
\ TT15, which leave QQ19+2 = 10 and QQ19+5 = GCYT); in record mode the frame
\ draws them while GSIGHT is non-zero (the laser power; TT66's G_DIRECT clears
\ it), so return from SIGHT with those as TT15 leaves them

.H_SIGHT
 LDA QQ11
 ORA GFORCE
 BEQ P%+3
 RTS
 PLA
 PLA
 LDY VIEW
 LDA LASER,Y
 STA GSIGHT
 LDA #10
 STA QQ19+2
 LDA #GCYT
 STA QQ19+5
 LDY #1                 \ and Y = 1, C clear, as the second TT15 returns (its
 CLC                    \ last LOIN keeps HLOIN3's Y; LOINQ ends with C clear)
 RTS

\ H_SUN: SUN has found the sun on screen (CHKON): record its centre and
\ radius (the frame fills a disc; SUN's fringe calculation carries on as
\ before, for its random numbers and the LSO heap). Keeps X, Y and C

.H_SUN
 LDA QQ11
 ORA GFORCE
 BNE hsu9
 PHP
 JSR G_PLANET
 PLP
.hsu9
 RTS

\ H_HLOIN: HLOIN (the sun's rows, through HLOIN2 too) draws nothing in
\ record mode: return from it at once (X and Y kept, as HLOIN keeps Y)

.H_HLOIN
 LDA QQ11
 ORA GFORCE
 BEQ P%+3
 RTS
 PLA
 PLA
 RTS

\ The energy bomb's lightning: BOMBOFF draws nine lines with LOIN (EOR), and
\ is called again with the same coordinates to remove them. In record mode
\ H_BOMB (at BOMBOFF, in the space view) tells the frame layer that a new bolt
\ starts, so only the last one recorded in a frame is drawn, and H_LLINE
\ records each line instead of drawing it (Y kept, as LOIN keeps it)

.H_BOMB
 LDA QQ11
 ORA GFORCE
 BNE hbm9
 JMP G_BOMB
.hbm9
 RTS

.H_LLINE
 LDA QQ11
 ORA GFORCE
 BEQ P%+5
 JMP LOIN
 LDA #FC_PLINE
 STA GLCOL
 JMP G_LINE
