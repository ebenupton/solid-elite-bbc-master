\ ******************************************************************************
\
\ gfx-gstubs.asm - main-RAM stubs that page the graphics bank in around a call
\
\ Each G_xxx preserves A, X, Y and C into F_xxx, which lives in sideways RAM bank
\ GFXBANK; Elite's own bank (ELITEBANK) is paged back in afterwards. Master
\ port: in the glue area (elite-glue.asm), with the renderer's other glue, as
\ code that pages a bank in must be outside the banks; they are only ever
\ called from game code, with ACCCON X clear (the frame sets X itself, inside
\ F_FRAME), but sit in the one glue area with the rest (below &3000).
\
\ ******************************************************************************


.gback
 LDA #ELITEBANK
 STA &F4
 STA &FE30
 RTS

.gA EQUB 0

.G_FRAME
 STA gA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 LDA gA
 JSR F_FRAME
 JMP gback

.G_SHIP
 STA gA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 LDA gA
 JSR F_SHIP
 JMP gback

.G_LINE
 STA gA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 LDA gA
 JSR F_LINE
 JMP gback

.G_DOT
 STA gA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 LDA gA
 JSR F_DOT
 JMP gback



.G_DIRECT
 STA gA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 LDA gA
 JSR F_DIRECT

\ If F_DIRECT kept space mode (an in-system jump), return to TTX66's caller
\ instead, with TTX66's results but no screen clear and border (F_DIRECT set
\ XC = YC = 1 and X = Y = 0; COL is as it was): A = %00001001, C = 0 and
\ V = 0 (from the BIT: GMODE = &80), as TTX66 returns

 BIT GMODE
 BPL gdir9
 PLA
 PLA
 JSR gback
 LDA #%00001001
 CLC
 RTS
.gdir9
 JMP gback

.G_PLANET
 STA gA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 LDA gA
 JSR F_PLANET
 JMP gback

.G_SHPPT
 STA gA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 LDA gA
 JSR F_SHPPT
 JMP gback

.G_INIT
 STA gA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 LDA gA
 JSR F_INIT
 JMP gback


.G_BOMB
 LDA #GFXBANK
 STA &F4
 STA &FE30
 JSR F_BOMB
 JMP gback

.G_PCURVE               \ (F_PCURVE and F_PPOINT do not read A, and both
 LDA #GFXBANK           \ callers, H_PCURVE and BLINE, enter with A = 0 and
 STA &F4                \ reload A afterwards, so A need not be kept in gA)
 STA &FE30
 JSR F_PCURVE
 JMP gback

.G_MERHOOK              \ (the meridian window's PM_HOOK, gfx-merid.asm: it
 LDA #MERIDBANK         \ keeps A, X, Y and the flags)
 STA &F4
 STA &FE30
 JSR PM_HOOK
 JMP gback

.G_PPOINT
 LDA #GFXBANK
 STA &F4
 STA &FE30
 JMP F_PPOINT           \ (it returns through gback)


.G_DSTAR                \ (C preserved both ways)
 LDA #GFXBANK
 STA &F4
 STA &FE30
 JSR F_DSTAR
 JMP gback



\ The hangar (gfx-hangar.asm), from HALL and HAS1. G_HANG0, before the ships are
\ recorded: the hangar's light and the frame's lists emptied (F_HANG0).
\ G_HANGAR: the frame, with the hangar's background under the ships

.G_HANG0
 LDA #GFXBANK
 STA &F4
 STA &FE30
 JSR F_HANG0
 JMP gback

\ G_HLL9: HAS1's LL9, with TYPE set while LL9 records the ship (H_EE31
\ takes the ship's faces from TYPE; HAS1 sets only XX0): the type whose XX21
\ entry is XX0 (XX15+2, the type HAS1 was given, is gone: TIDY uses XX15),
\ or the one HSUB draws in its place, with XX0 its blueprint. TYPE and XX0
\ are put back afterwards, as the original leaves them

.G_HLL9
 LDA TYPE
 PHA
 LDA XX0
 PHA
 LDA XX0+1
 PHA
 LDX #0
.ghl1
 INX
 INX
 LDA XX21-2,X
 CMP XX0
 BNE ghl1
 LDA XX21-1,X
 CMP XX0+1
 BNE ghl1
 TXA
 LSR A
 TAY
 LDA HSUB-1,Y           \ the type drawn
 STA TYPE
 ASL A
 TAX
 LDA XX21-2,X           \ and its blueprint
 STA XX0
 LDA XX21-1,X
 STA XX0+1
 JSR LL9
 PLA
 STA XX0+1
 PLA
 STA XX0
 PLA
 STA TYPE
 RTS

\ HSUB: the type whose blueprint the hangar draws, for each type HALL can
\ choose (1 to 21: HATB's, and the solo ships, SH3 to SH3+4): the type
\ itself, but for the two that blend into the tan (HATB's Port note,
\ elite-source.asm): the Sidewinder (17) is drawn as an Asp Mk II (25), the
\ Mamba (18) as a Viper (COPS)

.HSUB
FOR hst, 1, 21
 IF hst = 17
  EQUB 25
 ELIF hst = 18
  EQUB COPS
 ELSE
  EQUB hst
 ENDIF
NEXT

.G_HANGAR
 LDA #GFXBANK
 STA &F4
 STA &FE30
 JSR F_HANGAR
 JMP gback
