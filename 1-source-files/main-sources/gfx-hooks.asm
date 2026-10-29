\ ******************************************************************************
\
\ gfx-hooks.asm - the glue between Master Elite's drawing code and the frame
\ layer (after the Demonstration Disc port's src/hooks.asm)
\
\ Master port: these run in game context only, with ACCCON X clear; they are
\ in the glue area (elite-glue.asm), with the renderer's other glue (below
\ &3000, as the hooks that run with X set or from the IRQ, gfx-gluehooks.asm,
\ must be). Elite's drawing routines call
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

\ H_CIRC: CIRCLE in record mode records the planet's disc instead (PL9 is
\ about to draw the planet's circle) and its surface detail (G_PFHOOK), and
\ returns from PL9 itself, whose meridians and crater the renderer draws
\ (their maths, PL9 parts 2 and 3, PLS2, PLS22 ..., are "Area: none"),
\ leaving what the game reads of them: K2 (MV40 adds it into the next
\ object's y without setting it first) as PLS1 leaves it for nosev_x (a
\ meridian planet of radius 6 or more; halved, a crater planet whose crater
\ faces us), TGT (31 or 64) and FLAG (0); and LSX2 = 0, STP and CNT as
\ CIRCLE2 would. If the circle isn't on screen (CHKON), it returns from
\ CIRCLE with C set, as CIRCLE does

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
 JSR G_PLANET
 JSR G_PFHOOK           \ the planet's class and surface detail (gfx-planet7.asm)
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
 PLA                    \ (return from PL9: CIRCLE's return into it)
 PLA
 LDA K+1                \ (PL9: only below a radius of 256)
 BNE hci9
 LDA TYPE
 CMP #128
 BNE hci2
 LDA K                  \ a meridian planet (part 2): radius 6 up
 CMP #6
 BCC hci9
 LDA #31
 BNE hci3
.hci2
 LDA INWK+20            \ a crater planet (part 3): its crater facing us
 BMI hci9
 LDA #64
.hci3
 STA TGT
 LDX #9
 JSR PLS1
 LDY TYPE               \ (halved for a crater planet)
 CPY #128
 BEQ P%+3
 LSR A
 STA K2
.hci9
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
 JSR S_SHIP             \ record it (G_SHIP), with its handedness

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
 JSR G_LINE
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
\ H_BOMB (at BOMBOFF, in the space view) has the frame layer copy the bolt's
\ points (F_BOMB: the frame draws the last bolt drawn), and H_LLINE draws
\ nothing (Y kept, as LOIN keeps it; A and X are dead after BOMBOFF)

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
 RTS
