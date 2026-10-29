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

.G_FRAME                \ (from hframe only, with bank 4 paged, which keeps A;
 JSR S_SUN              \ F_FRAME does not read it) the sun near the planet
 LDA QQ11               \ first (S_SUN, gfx-ssun.asm), then in a space view the
 BNE P%+5               \ light for the next iteration's ships (L_SUN,
 JSR L_SUN              \ gfx-light.asm): both at bank 4's end
 LDA #GFXBANK
 STA &F4
 STA &FE30
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

.G_GUN                  \ (A passed, Y returned: F_GUN's)
 STA gA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 LDA gA
 JSR F_GUN
 JMP gback

.G_PDOT                 \ (A, X passed: F_PDOT's)
 STA gA
 LDA #GFXBANK
 STA &F4
 STA &FE30
 LDA gA
 JSR F_PDOT
 JMP gback

.G_CLOUD                \ (C passed: F_CLOUD's)
 LDA #GFXBANK
 STA &F4
 STA &FE30
 JSR F_CLOUD
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

.G_PFHOOK               \ (the planet's detail, gfx-planet7.asm, after the
 IF _PLANET_MOON        \ moon's place for this iteration with moon=on,
 JSR MN_TURN            \ gfx-ssun.asm, in bank 4: H_CIRC keeps nothing in
 ENDIF                  \ A, X, Y or the flags)
 LDA #MERIDBANK
 STA &F4
 STA &FE30
 JSR PF_HOOK
 JMP gback


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

.G_HANGAR                \ (from HALL, with bank 4 paged: the light for the
 LDA QQ11               \ hangar's ships too, L_SUN, gfx-light.asm, at bank
 BNE P%+5               \ 4's end, as G_FRAME does)
 JSR L_SUN
 LDA #GFXBANK
 STA &F4
 STA &FE30
 JSR F_HANGAR
 JMP gback
