\ ******************************************************************************
\
\ gfx-lowhooks.asm - the hooks that must live in main RAM below &3000 (the
\ low area, elite-low.asm): the text map's (CHPR runs as WRCHV with any ROM
\ paged and with ACCCON X set, which hides main RAM above &3000) and the
\ IRQ's (H_VSYNC); split from gfx-hooks.asm
\
\ ******************************************************************************

.hA EQUB 0                \ (also read by F_DSTAR in bank 6)

\ The text map: CHPR (WRCHV, so any ROM may be paged: the cold area, or DFS
\ printing a catalogue) and CLYNS keep the frame layer's text map up to date
\ in every mode (so a screen that carries on in record mode without a TT66
\ still has its text), and draw on the screen only outside record mode. These
\ stubs page bank 6 in and the caller's bank (&F4, ANDY included) back, and
\ live below &3000 as CHPR runs with ACCCON X set. A, X, Y are not kept (F_CHAR
\ and F_DELCHAR keep Y, F_CLRTEXT X and Y)

.G_CHAR
 LDA &F4
 PHA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 JSR F_CHAR
 BRA gtxt

.G_DELCHAR
 LDA &F4
 PHA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 JSR F_DELCHAR
 BRA gtxt

.G_CLRTEXT
 LDA &F4
 PHA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 JSR F_CLRTEXT
.gtxt
 PLA
 STA &F4
 STA &FE30
 RTS

\ H_CHAR: CHPR (RR3) is about to draw the character in K3 at (XC-1, YC), with
\ A = YC: record it in the text map, and in record mode, or in space mode
\ (GMODE bit 7: the frames are running, as in the mission briefing, whose
\ text is printed in view types 13 and 1 while LL9B draws the ship as a
\ frame), return through RR4 instead of drawing it (A = YC and C clear
\ otherwise, as RR3 is entered)

.H_CHAR
 STA hA
 JSR G_CHAR
 LDA QQ11
 ORA GFORCE
 BEQ hcr
 BIT GMODE
 BPL hcd
.hcr
 PLA
 PLA
 LDA hA                 \ leave SC(1 0), P(3 2) and W as RR3, RREN and RRL1 do
 ASL A
 ASL SC
 ADC #&40
 STA SC+1
 LDA SC
 CLC
 ADC #8
 STA P+2
 LDA SC+1
 STA P+3
 LDY #0
 LDA (P),Y
 AND #%00001111
 STA W
 JMP RR4
.hcd
 LDA hA
 CLC
 RTS

\ H_DEL: CHPR is deleting the character at (XC, YC) (after its DEC XC): the
\ text map too; in record mode return through RR4 instead of blanking it

.H_DEL
 PHA
 JSR G_DELCHAR
 LDA QQ11
 ORA GFORCE
 BNE hdl9
 PLA
 PLA
 PLA
 JMP RR4
.hdl9
 PLA
 RTS


\ H_VSYNC: called by IRQ1 at vertical sync (A only): a pending flip makes
\ GPEND the front buffer; in direct mode the front buffer is shadow RAM
\ (buffer 1); ACCCON D shows it (the timer 1 interrupt at the dashboard sets
\ D = 1 again, as the dashboard is in shadow RAM). Only D is touched, so the
\ main code's ACCCON X is kept

.H_VSYNC
 LDA GFLIP
 BEQ hv0
 LDA GPEND
 STA GFRONT
 STZ GFLIP
.hv0
 BIT GMODE
 BMI hv1
 LDA #1
 STA GFRONT
.hv1
 LDA #1
 BIT GFRONT
 BEQ hv2
 TSB &FE34
 RTS
.hv2
 TRB &FE34
 RTS

