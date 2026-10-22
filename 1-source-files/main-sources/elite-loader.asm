\ ******************************************************************************
\
\ BBC MASTER ELITE GAME LOADER SOURCE
\
\ BBC Master Elite was written by Ian Bell and David Braben and is copyright
\ Acornsoft 1986
\
\ The code in this file has been reconstructed from a disassembly of the version
\ released on Ian Bell's personal website at http://www.elitehomepage.org/
\
\ The commentary is copyright Mark Moxon, and any misunderstandings or mistakes
\ in the documentation are entirely my fault
\
\ The terminology and notations used in this commentary are explained at
\ https://elite.bbcelite.com/terminology
\
\ The deep dive articles referred to in this commentary can be found at
\ https://elite.bbcelite.com/deep_dives
\
\ ------------------------------------------------------------------------------
\
\ This source file contains the loader for BBC Master Elite.
\
\ ------------------------------------------------------------------------------
\
\ This source file produces the following binary file:
\
\   * M128Elt.bin
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-build-options.asm"

 CPU 1                  \ Switch to 65SC12 assembly, as this code runs on the
                        \ BBC Master

 _SNG47                 = (_VARIANT = 1)
 _COMPACT               = (_VARIANT = 2)

 GUARD &C000            \ Guard against assembling over MOS memory

\ ******************************************************************************
\
\ Configuration variables
\
\ ******************************************************************************

 CODE% = &0E00          \ The address where the code will be run
 ASSERT CODE% >= &0E00  \ Port: page &0D is off limits (docs/master-memory.md),
                        \ except for the minimal NMI handler (see NMIH)

 FDC = &FE28            \ Port: the BBC Master's 1770 disc controller: status
                        \ (read) and command (write) register

 LOAD% = &0E00          \ The address where the code will be loaded

 N% = 67 + 18           \ N% is set to the number of bytes in the VDU table, so
                        \ we can loop through them below

 INCLUDE "3-assembled-output/game-addresses.asm"     \ Port: S%, the main entry point in
                                        \ the game code (was S% = &2C6C),
                                        \ and SBANK, the ROMSEL value to run
                                        \ it with, from the game's symbols

 HOMEBANK = 4           \ Port: Elite's home bank, the sideways RAM bank that is
                        \ paged in while the game runs (bank 6 in the original)

 VIA = &FE00            \ Memory-mapped space for accessing internal hardware,
                        \ such as the video ULA, 6845 CRTC and 6522 VIAs (also
                        \ known as SHEILA)

 OSWRCH = &FFEE         \ The address for the OSWRCH routine

 OSBYTE = &FFF4         \ The address for the OSBYTE routine

 OSCLI = &FFF7          \ The address for the OSCLI routine

\ ******************************************************************************
\
\       Name: ZP
\       Type: Workspace
\    Address: &0070 to &0075
\   Category: Workspaces
\    Summary: Important variables used by the loader
\
\ ******************************************************************************

 ORG &0002              \ Set the assembly address to &0002

IF _COMPACT

.MOS

 SKIP 1                 \ Determines whether we are running on a Master Compact
                        \
                        \   * 0 = This is a Master Compact
                        \
                        \   * &FF = This is not a Master Compact

ENDIF

 ORG &0070              \ Set the assembly address to &0070

.ZP

 SKIP 2                 \ Stores addresses used for moving content around

.P

 SKIP 1                 \ Temporary storage, used in a number of places

.Q

 SKIP 1                 \ Temporary storage, used in a number of places

.YY

 SKIP 1                 \ Temporary storage, used in a number of places

.T

 SKIP 1                 \ Temporary storage, used in a number of places

.LEN

 SKIP 2                 \ Port: the number of bytes left to copy (FTAB)

 ORG &00F4              \ Set the assembly address to &00F4

.LATCH

 SKIP 2                 \ The RAM copy of the currently selected paged ROM/RAM
                        \ in SHEILA &30

\ ******************************************************************************
\
\ ELITE LOADER
\
\ ******************************************************************************

 ORG CODE%              \ Set the assembly address to CODE%

\ ******************************************************************************
\
\       Name: B%
\       Type: Variable
\   Category: Drawing the screen
\    Summary: VDU commands for setting the square mode 1 screen
\  Deep dive: The split-screen mode in BBC Micro Elite
\             Drawing monochrome pixels on the BBC Micro
\
\ ------------------------------------------------------------------------------
\
\ This block contains the bytes that get written by OSWRCH to set up the screen
\ mode (this is equivalent to using the VDU statement in BASIC).
\
\ It defines the whole screen using a square, monochrome mode 1 configuration;
\ the mode 2 part for the dashboard is implemented in the IRQ1 routine.
\
\ The top part of Elite's screen mode is based on mode 1 but with the following
\ differences:
\
\   * 64 columns, 31 rows (256 x 248 pixels) rather than 80, 32
\
\   * The horizontal sync position is at character 90 rather than 98, which
\     pushes the screen to the right (which centres it as it's not as wide as
\     the normal screen modes)
\
\   * Screen memory goes from &4000 to &7EFF
\
\   * In the Master version of Elite, the screen mode is actually based on mode
\     129 rather than mode 1, so shadow RAM (known as LYNNE) is used to store
\     the screen memory, though in all other respects the screen mode is the
\     same as if it were based on mode 1
\
\   * The text window is 1 row high and 13 columns wide, and is at (2, 16)
\
\   * The cursor is disabled
\
\ This almost-square mode 1 variant makes life a lot easier when drawing to the
\ screen, as there are 256 pixels on each row (or, to put it in screen memory
\ terms, there are two pages of memory per row of pixels).
\
\ There is also an interrupt-driven routine that switches the bytes-per-pixel
\ setting from that of mode 1 to that of mode 2, when the raster reaches the
\ split between the space view and the dashboard.
\
\ ******************************************************************************

.B%

 EQUB 22, 129           \ Switch to screen mode 129

 EQUB 19, 1, 6, 0, 0, 0 \ Port: the CMYK palette, for the whole screen (the IRQ
 EQUB 19, 2, 5, 0, 0, 0 \ no longer changes the mode or the palette): logical
 EQUB 19, 3, 3, 0, 0, 0 \ colours 1, 2, 3 = cyan, magenta, yellow (0 = black)

 EQUB 28                \ Define a text window as follows:
 EQUB 2, 17, 15, 16     \
                        \   * Left = 2
                        \   * Right = 15
                        \   * Top = 16
                        \   * Bottom = 17
                        \
                        \ i.e. 1 row high, 13 columns wide at (2, 16)

 EQUB 23, 0, 6, 31      \ Set 6845 register R6 = 31
 EQUB 0, 0, 0           \
 EQUB 0, 0, 0           \ This is the "vertical displayed" register, and sets
                        \ the number of displayed character rows to 31. For
                        \ comparison, this value is 32 for standard modes 1 and
                        \ 2, but we claw back the last row for storing code just
                        \ above the end of screen memory

 EQUB 23, 0, 12, &08    \ Set 6845 register R12 = &08 and R13 = &00
 EQUB 0, 0, 0           \
 EQUB 0, 0, 0           \ This sets 6845 registers (R12 R13) = &0800 to point
 EQUB 23, 0, 13, &00    \ to the start of screen memory in terms of character
 EQUB 0, 0, 0           \ rows. There are 8 pixel lines in each character row,
 EQUB 0, 0, 0           \ so to get the actual address of the start of screen
                        \ memory, we multiply by 8:
                        \
                        \   &0800 * 8 = &4000
                        \
                        \ So this sets the start of screen memory to &4000

 EQUB 23, 0, 1, 64      \ Set 6845 register R1 = 64
 EQUB 0, 0, 0           \
 EQUB 0, 0, 0           \ This is the "horizontal displayed" register, which
                        \ defines the number of character blocks per horizontal
                        \ character row. For comparison, this value is 80 for
                        \ modes 1 and 2, but our custom screen is not as wide at
                        \ only 64 character blocks across

 EQUB 23, 0, 2, 90      \ Set 6845 register R2 = 90
 EQUB 0, 0, 0           \
 EQUB 0, 0, 0           \ This is the "horizontal sync position" register, which
                        \ defines the position of the horizontal sync pulse on
                        \ the horizontal line in terms of character widths from
                        \ the left-hand side of the screen. For comparison this
                        \ is 98 for modes 1 and 2, but needs to be adjusted for
                        \ our custom screen's width

 EQUB 23, 0, 10, 32     \ Set 6845 register R10 = %00100000 = 32
 EQUB 0, 0, 0           \
 EQUB 0, 0, 0           \ This is the "cursor start" register, and bits 5 and 6
                        \ define the "cursor display mode", as follows:
                        \
                        \   * %00 = steady, non-blinking cursor
                        \
                        \   * %01 = do not display a cursor
                        \
                        \   * %10 = fast blinking cursor (blink at 1/16 of the
                        \           field rate)
                        \
                        \   * %11 = slow blinking cursor (blink at 1/32 of the
                        \           field rate)
                        \
                        \ We can therefore turn off the cursor completely by
                        \ setting cursor display mode %01, with bit 6 of R10
                        \ clear and bit 5 of R10 set

\ ******************************************************************************
\
\       Name: Elite loader
\       Type: Subroutine
\   Category: Loader
\    Summary: Perform a number of OS calls, check for sideways RAM, load and
\             move the main game data, and load and run the main game code
\
\ ------------------------------------------------------------------------------
\
\ The loader loads and moves the following files. There is no decryption at this
\ stage - that is all done by the main game code.
\
\   * The BDATA game data file is loaded into main memory at &1300-&54FF, and is
\     then moved as follows:
\
\       * &1300-&21FF is moved to &7000-&7EFF in screen memory (i.e. shadow RAM)
\         for the dashboard
\
\       * &2200-&54FF is moved to &7F00-&B1FF in main memory, where the main
\         game code will decrypt it
\
\   * The main game code file is loaded into main memory at &1300 and the game
\     is started by jumping to &2C6C
\
\ The main game code file is called BCODE in the Master release and ELITE in the
\ Master Compact release. BCODE loads into &1300-&7F47, while ELITE loads into
\ &1300-&7FEC.
\
\ The main game code is then responsible for decrypting BDATA (from &8000 to
\ &B1FF) and BCODE/ELITE (from the end of the DEEOR routine to the end of the
\ file).
\
\ ******************************************************************************

.ENTRY

 ASSERT ENTRY = &0E55   \ Port: the execution address that elite-disc.asm gives
                        \ M128Elt (the CMYK palette made B% 18 bytes longer)

 JSR CHKRAM             \ Port: first of all, check that sideways RAM banks 4
                        \ to 7, which the game and the renderer use, are all
                        \ RAM (before the screen mode, palette or ACCCON are
                        \ changed, so that the message can be seen)

 LDA #16                \ Call OSBYTE with A = 16 and X = 0 to set the ADC to
 LDX #0                 \ sample no channels from the joystick/Bitstik
 JSR OSBYTE

IF _COMPACT

 LDA #129               \ Call OSBYTE with A = 129, X = 0 and Y = &FF to detect
 LDX #0                 \ the machine type, which returns the following:
 LDY #&FF               \
 JSR OSBYTE             \   * X = &F5 if this is a Master Compact with MOS 5

 LDA #&FF               \ Set A = &FF, the value we want to store in the MOS
                        \ flag if this is not a Master Compact

 CPX #&F5               \ If X <> &F5, skip the following instruction as this is
 BNE P%+4               \ a Master Compact

 LDA #0                 \ This is a Master Compact, so set A = 0

 STA MOS                \ Store the value of A in MOS, which will be 0 if this
                        \ is a Master Compact, or &FF if it isn't

ENDIF

 LDA #200               \ Call OSBYTE with A = 200, X = 1 and Y = 0 to disable
 LDX #1                 \ the ESCAPE key and disable memory clearing if the
 JSR OSB                \ BREAK key is pressed

 LDA #13                \ Call OSBYTE with A = 13, X = 0 and Y = 0 to disable
 LDX #0                 \ the "output buffer empty" event
 JSR OSB

 LDA #144               \ Call OSBYTE with A = 144, X = 255 and Y = 0 to move
 LDX #255               \ the screen down one line and turn screen interlace on
 LDY #0
 JSR OSBYTE

 LDA #144               \ Repeat the above command, which has the effect of
 LDX #255               \ setting the interlace to the original value, as the
 JSR OSBYTE             \ OSBYTE call above returns the original setting in Y

 LDA #225               \ Call OSBYTE with A = 225, X = 128 and Y = 0 to set
 LDX #128               \ the function keys to return ASCII codes for SHIFT-fn
 JSR OSB                \ keys (i.e. add 128)

 LDA #13                \ Call OSBYTE with A = 13, X = 2 and Y = 0 to disable
 LDX #2                 \ the "character entering buffer" event
 JSR OSB

 LDA #LO(B%)            \ Set ZP(1 0) to point to the VDU code table at B%
 STA ZP
 LDA #HI(B%)
 STA ZP+1

 LDY #0                 \ We are now going to send the N% VDU bytes in the table
                        \ at B% to OSWRCH to set up the special mode 1 screen
                        \ that forms the basis for the split-screen mode

.LOOP

 LDA (ZP),Y             \ Pass the Y-th byte of the B% table to OSWRCH
 JSR OSWRCH

 INY                    \ Increment the loop counter

 CPY #N%                \ Loop back for the next byte until we have done them
 BNE LOOP               \ all (the number of bytes was set in N% above)

 LDA #%00001111         \ Set the Access Control latch at SHEILA &34, as
 STA VIA+&34            \ follows:
                        \
                        \   * Bit 7 = IRR = 0: Do not IRQ the CPU with this
                        \   * Bit 6 = TST = 0: Must be set to 0
                        \   * Bit 5 = IFJ = 0: &FC00-&FDFF maps to the 1Mhz bus
                        \   * Bit 4 = ITU = 0: CPU can access external co-pro
                        \   * Bit 3 = Y = 1: &C000-&DFFF set to 8K private RAM
                        \   * Bit 2 = X = 1: &3000-&7FFF set to 20K shadow RAM
                        \   * Bit 1 = E = 1: All shadow RAM locations accessible
                        \   * Bit 0 = D = 1: Display shadow RAM as screen memory
                        \
                        \ In short, this switches the screen memory, which is in
                        \ shadow RAM, into the memory map at &3000-&7FFF, so now
                        \ we can poke directly to the screen memory, and it also
                        \ maps the filing system RAM space into &C000-&DFFF
                        \ (HAZEL), in place of the MOS VDU workspace

 JSR PLL1               \ Call PLL1 to draw Saturn

 LDA #%00001001         \ Clear bits 1 and 2 of the Access Control latch at
 STA VIA+&34            \ SHEILA &34, which changes the following:
                        \
                        \   * Bit 2 = X = 0: &3000-&7FFF set to main RAM
                        \   * Bit 1 = E = 0: VDU shadow RAM locations accessible
                        \
                        \ In short, this switches the screen memory, which is in
                        \ shadow RAM, out of the memory map, so &3000-&7FFF is
                        \ now mapped to main RAM and we can't update the screen

 LDA #4                 \ Call OSBYTE with A = 4, X = 1 and Y = 0 to disable
 LDX #1                 \ cursor editing, so the cursor keys return ASCII values
 JSR OSB                \ and can therefore be used in-game

 LDA #9                 \ Call OSBYTE with A = 9, X = 0 and Y = 0 to disable
 LDX #0                 \ flashing colours
 JSR OSB


                        \ Port: load the game's files other than BCODE, one at a
                        \ time, to &1300 (below &3000, so it is visible when
                        \ ACCCON X is set), then copy each one to where it
                        \ belongs, as listed in FTAB: shadow RAM, or a sideways
                        \ RAM bank (with ANDY when ROMSEL bit 7 is set)

 LDX #0                 \ X = offset of the FTAB entry

.LDF

 STX YY                 \ Save the entry's offset

 LDA FTAB+1,X           \ Fetch the high byte of the entry's OSCLI command,
 BEQ LDEND              \ which is zero at the end of the table

 TAY                    \ Run the command in (Y X), which loads the file at
 LDA FTAB,X             \ &1300
 TAX
 JSR OSCLI

 SEI                    \ No interrupts while ROMSEL and ACCCON are changed

 LDX YY                 \ Page in the file's destination: ROMSEL (and its RAM
 LDA FTAB+2,X           \ copy in &F4) and ACCCON
 STA LATCH
 STA VIA+&30
 LDA FTAB+3,X
 STA VIA+&34

 STZ ZP                 \ ZP(1 0) = &1300, the source
 LDA #&13
 STA ZP+1

 LDA FTAB+4,X           \ P(1 0) = the destination
 STA P
 LDA FTAB+5,X
 STA P+1

 LDA FTAB+6,X           \ LEN(1 0) = the number of bytes (non-zero)
 STA LEN
 LDA FTAB+7,X
 STA LEN+1

.LDC

 LDA (ZP)               \ Copy a byte
 STA (P)

 INC ZP                 \ Next source byte
 BNE P%+4
 INC ZP+1

 INC P                  \ Next destination byte
 BNE P%+4
 INC P+1

 LDA LEN                \ Count it off LEN(1 0)
 BNE P%+4
 DEC LEN+1
 DEC LEN
 LDA LEN
 ORA LEN+1
 BNE LDC

 LDA #%00001001         \ Main RAM back at &3000-&7FFF (ACCCON as the game has
 STA VIA+&34            \ it)

 CLI

 LDA YY                 \ Next entry
 CLC
 ADC #8
 TAX
 BNE LDF

.LDEND

 CLI                    \ Enable interrupts

 LDX #LO(MESS2)         \ Set (Y X) to point to MESS2 ("L.BCODE FFFF1300" in the
 LDY #HI(MESS2)         \ Master release, or "L.ELITE FFFF1300" in the Master
                        \ Compact release)

 JSR OSCLI              \ Call OSCLI to run the OS command in MESS2, which loads
                        \ the BCODE/ELITE file to address &1300, appending
                        \ &FFFF to the address to make sure it loads in the main
                        \ BBC Master rather than getting passed across the Tube
                        \ to the Second Processor, if one is fitted

 LDX #LO(MESS3)         \ Set (Y X) to point to MESS3 ("DIR E")
 LDY #HI(MESS3)

 JSR OSCLI              \ Call OSCLI to run the OS command in MESS3, which
                        \ changes the disc directory to E

                        \ Port: the rest of the loader runs from K% (&0400),
                        \ where its image at LTAIL is copied now: it writes
                        \ the renderer's shared workspace (DFSST here, G_INIT
                        \ the rest), which is in main RAM from &0E00 up to
                        \ the main code, where this loader is (elite-gfx.asm).
                        \ The game sets up K% itself, as it does WP, which was
                        \ the loader's place in the original

 LDX #0
.LTC
 LDA LTAIL,X
 STA LTRUN,X
 INX
 CPX #LTEND-LTRUN
 BNE LTC
 JMP LTRUN

.LTAIL

 ORG &0400              \ (assembled to run at &0400, its image here: COPYBLOCK
                        \ after LTEND)

.LTRUN

                        \ Port: that was the last disc access, so DFS is done
                        \ with HAZEL: stash DFS's and the MOS's lasting bytes,
                        \ as the game uses their places (DOSCLI puts them back
                        \ for each disc command): &C2C0-&C2FF and &DFC0-&DFFF
                        \ (ACCCON Y = 1 maps HAZEL at &C000-&DFFF), then copy
                        \ HAZEL's contents (the game data and the renderer's
                        \ glue) from their staging copy at &4000 into place

 SEI
 LDA #%00001001
 STA VIA+&34

 LDX #63
.DFST
 LDA &C2C0,X
 STA DFSST,X
 LDA &DFC0,X
 STA DFSST2,X
 DEX
 BPL DFST
 STZ DFSIN              \ (no disc command under way)

 LDX #0
 LDY #HI(HZLEN+255)     \ (whole pages)

.HZC

 LDA &4000,X
 STA HZ_START,X
 INX
 BNE HZC
 INC HZC+2
 INC HZC+5
 DEY
 BNE HZC

 ASSERT HZLEN <= &2000 AND LO(HZ_START) = 0  \ (HAZEL's staging copy at &4000)

                        \ Port: make the 1770 quiet and replace the DFS's NMI
                        \ handler at &0D00 with a minimal one (from the demo
                        \ port's loader, 3d25f90). The DFS's handler uses &A0-
                        \ &A7, which are the game's zero page (INWK) while the
                        \ game runs, so a stray NMI after loading (seen on a
                        \ real Master) would corrupt them, and could write the
                        \ game's value at &A7 to the 1770's command register,
                        \ which starts a command and raises more NMIs. The last
                        \ disc access has finished, so with interrupts off:
                        \ terminate whatever the 1770 is doing without an
                        \ interrupt (Force Interrupt with no conditions, &D0,
                        \ to its command register at &FE28), read its status
                        \ to clear INTRQ, and install PHA : LDA &FE28 : PLA :
                        \ RTI at &0D00, writing the RTI at &0D00 first, then
                        \ the body at &0D01, then the PHA, so the code at &0D00
                        \ is a complete handler at every step. These are the
                        \ only writes to page &0D before the game starts (page
                        \ &0D is otherwise off limits, docs/master-memory.md);
                        \ DFS copies its own handler back at the start of each
                        \ disc operation the game makes when docked

 LDA #&D0               \ 1770 Force Interrupt, no conditions: terminate any
 STA FDC                \ command and raise no interrupt

 LDX #8                 \ Give the 1770 time to take the command (it needs a
.NMIW                   \ few microseconds before its status is valid)
 DEX
 BNE NMIW

 LDA FDC                \ Read the status register, which clears INTRQ

 LDA #&40               \ &0D00 = RTI: a complete NMI handler on its own
 STA &0D00

 LDX #NMIHEND-NMIH-1    \ The rest of the handler at &0D01 (LDA &FE28 : PLA :
.NMIC                   \ RTI), behind the RTI
 LDA NMIH,X
 STA &0D01,X
 DEX
 BPL NMIC

 LDA #&48               \ And finally &0D00 = PHA, which completes the handler
 STA &0D00

                        \ Port: put the MOS's default back in the vectors at
                        \ &0200-&0235 (from the demo port's loader, 538f3de). A
                        \ ROM may have hooked one (the machine this was reported
                        \ on hooks BYTEV through an extended vector), and a
                        \ hook would then run on every call and could write its
                        \ private workspace, a page of HAZEL (the table at
                        \ &0DF0), which the renderer uses. Kept: BRKV and IRQ1V
                        \ (&0202-&0205) and WRCHV (&020E-&020F), which the game
                        \ sets itself, and the filing system vectors FILEV to
                        \ FSCV (&0212-&021F), which must stay the DFS's for the
                        \ disc access the game makes when docked. MOS 3.20 and
                        \ 3.50 hold the default table's length at &FFB6 and its
                        \ address at &FFB7

 LDA &FFB7              \ Point VRL's LDA at the default vector table
 STA VRL+1
 LDA &FFB8
 STA VRL+2
 LDY &FFB6              \ Y = the table's length

.VRL1

 DEY                    \ Next byte, from the top down
 BMI VRL4

 CPY #&02               \ Keep BRKV and IRQ1V (&0202-&0205)
 BCC VRL
 CPY #&06
 BCC VRL1
 CPY #&0E               \ Keep WRCHV (&020E-&020F)
 BEQ VRL1
 CPY #&0F
 BEQ VRL1
 CPY #&12               \ Keep the filing system vectors (&0212-&021F)
 BCC VRL
 CPY #&20
 BCC VRL1

.VRL

 LDA &FFFF,Y            \ Copy the default (the address is set above)
 STA &0200,Y
 BRA VRL1

.VRL4

 CLI

 JSR GINIT              \ Port: initialise the renderer (G_INIT: the rasteriser's
                        \ state, and shadow RAM's screen cleared)

 LDA #SBANK             \ Set the RAM copy of the currently selected paged ROM
 STA LATCH              \ to SBANK, the bank of the game's entry point S% (the
                        \ cold area, ROMSEL &87, from build/game-addresses.asm),
 STA VIA+&30            \ and page it in

 JMP S%                 \ Jump to the start of the main game code at S%, which
                        \ we just loaded in the BCODE/ELITE file

.NMIH                   \ Port: the minimal NMI handler's body at &0D01, after

 LDA FDC                \ the PHA at &0D00: acknowledge the 1770 (reading its
 PLA                    \ status clears INTRQ) and return
 RTI

.NMIHEND

.LTEND

 ASSERT LTEND - LTRUN <= 256 AND LTEND <= &05BB    \ (one copy loop; within K%)

 ORG LTAIL + LTEND - LTRUN      \ (back to the loader, after the image)

 COPYBLOCK LTRUN, LTEND, LTAIL

\ ******************************************************************************
\
\       Name: CHKRAM
\       Type: Subroutine
\   Category: Loader
\    Summary: Port: check that sideways banks 4 to 7 are RAM, or stop with an
\             error
\
\ ******************************************************************************

.CHKRAM

                        \ On a Master whose links LK18/LK19 select the ROM
                        \ sockets for banks 4/5 or 6/7 (to fit extra ROMs),
                        \ loading into those banks writes into ROM without an
                        \ error, so the game would start with banks missing.
                        \ For each bank, invert the byte at &8000, check that
                        \ it reads back inverted, then restore it and check it
                        \ again (two patterns, so a floating bus or an empty
                        \ socket can't pass). Interrupts are off, so the MOS
                        \ doesn't page another ROM in while we look (and &F4
                        \ is left alone)

 SEI
 LDX #7

.CHK1

 STX VIA+&30            \ Page in bank X
 LDA &8000
 EOR #&FF
 STA &8000
 CMP &8000
 BNE CHKF               \ Not RAM: report it
 EOR #&FF
 STA &8000
 CMP &8000
 BNE CHKF
 DEX
 CPX #3
 BNE CHK1

 LDA LATCH              \ All four banks are RAM: page the MOS's choice back in
 STA VIA+&30
 CLI
 RTS

.CHKF

 LDA LATCH              \ Bank X isn't RAM: page the MOS's choice back in, put
 STA VIA+&30            \ the bank's number into the message and stop with it
 CLI
 TXA
 ORA #'0'
 STA CHKB

 LDY #0                 \ Print the message in mode 7 with OSWRCH (not as a
.CHK2                   \ BRK error: the boot may have no language to print
 LDA CHKM,Y             \ it), then stop here for good
 BEQ CHK3
 JSR OSWRCH
 INY
 BNE CHK2
.CHK3
 JMP CHK3

.CHKM

 EQUB 22, 7             \ Switch to mode 7 and clear the screen

 EQUS "ELITE needs sideways RAM in banks 4-7,"
 EQUB 13, 10
 EQUS "but bank "

.CHKB

 EQUS "? is not RAM."
 EQUB 13, 10
 EQUS "Set links LK18 and LK19 to RAM."
 EQUB 13, 10

 EQUB 0                 \ End of message

\ ******************************************************************************
\
\       Name: FTAB
\       Type: Variable
\   Category: Loader
\    Summary: Port: the files the loader copies into place
\
\ ------------------------------------------------------------------------------
\
\ Eight bytes per file: the OSCLI command that loads it to &1300, the ROMSEL
\ and ACCCON values to copy it with, the destination, and the number of bytes
\ (a multiple of 256). The table ends with a zero command address.
\
\ ******************************************************************************

.FTAB

 EQUW MESS1             \ BDATA: the dashboard image (Port: the MODE 1 CMYK one),
                        \ to shadow RAM &7000-&7DFF
 EQUB HOMEBANK, %00001111
 EQUW &7000, &0E00

 EQUW MESS4             \ BANK4: Elite's home bank
 EQUB HOMEBANK, %00001001
 EQUW &8000, &4000

 EQUW MESS6             \ COLD7: the cold area, bank 7 from &8000 (the cold data,
 EQUB 7, %00001001      \ QQ18 and the extended tokens, then the cold code)
 EQUW &8000, C7LEN

 EQUW MESS7             \ MERID: the renderer's meridian window, bank 7 after
 EQUB 7, %00001001      \ the cold area
 EQUW M7AT, M7LEN

 EQUW MESS8             \ RASTA: the rasteriser's polygon window, ANDY
 EQUB &85, %00001001    \ (ROMSEL bit 7: ANDY over bank 5's &8000-&8FFF)
 EQUW &8000, RALEN

 EQUW MESS9             \ BANK5: the renderer's rasteriser, bank 5
 EQUB 5, %00001001
 EQUW &8000, B5LEN

 EQUW MESS10            \ BANK6: the renderer's frame layer, bank 6
 EQUB 6, %00001001
 EQUW &8000, B6LEN

 EQUW MESS12            \ HAZEL: the game data and the hangar's tables, staged
 EQUB HOMEBANK, %00001001 \ in main RAM at &4000 (screen buffer 0) and copied to
 EQUW &4000, HZLEN      \ HAZEL after the last disc access (see LDEND), as DFS
                        \ uses HAZEL

 EQUW MESS14            \ HICODE: the quarter-square tables, then the
 EQUB HOMEBANK, %00001001 \ run's second part, main RAM &7000-&7FFF
 EQUW &7000, HILEN

 EQUW 0

\ ******************************************************************************
\
\       Name: OSB
\       Type: Subroutine
\   Category: Utility routines
\    Summary: A convenience routine for calling OSBYTE with Y = 0
\
\ ******************************************************************************

.OSB

 LDY #0                 \ Call OSBYTE with Y = 0, returning from the subroutine
 JMP OSBYTE             \ using a tail call (so we can call OSB to call OSBYTE
                        \ for when we know we want Y set to 0)

\ ******************************************************************************
\
\       Name: MESS1
\       Type: Variable
\   Category: Loader
\    Summary: The OS command string for loading the BDATA binary
\
\ ******************************************************************************

.MESS1

 EQUS "L.BDATA FFFF1300"    \ This is short for "*LOAD BDATA FFFF1300"
 EQUB 13

\ ******************************************************************************
\
\       Name: MESS2
\       Type: Variable
\   Category: Loader
\    Summary: The OS command string for loading the main game code binary
\
\ ******************************************************************************

.MESS2

IF _SNG47

 EQUS "L.BCODE FFFF", STR$~(BCODEAT)   \ This is short for "*LOAD BCODE
 EQUB 13                \ FFFF1300" (Port: BCODE's address, from the build)

ELIF _COMPACT

 EQUS "L.ELITE FFFF1300"    \ This is short for "*LOAD ELITE FFFF1300"
 EQUB 13

ENDIF

\ ******************************************************************************
\
\       Name: MESS3
\       Type: Variable
\   Category: Loader
\    Summary: The OS command string for changing the disc directory to E
\
\ ******************************************************************************

.MESS3

 EQUS "DIR E"
 EQUB 13

.MESS4

 EQUS "L.BANK4 FFFF1300"    \ Port: *LOAD BANK4 FFFF1300
 EQUB 13

.MESS6

 EQUS "L.COLD7 FFFF1300"    \ Port: *LOAD COLD7 FFFF1300
 EQUB 13

.MESS7

 EQUS "L.MERID FFFF1300"    \ Port: *LOAD MERID FFFF1300
 EQUB 13

.MESS8

 EQUS "L.RASTA FFFF1300"    \ Port: *LOAD RASTA FFFF1300
 EQUB 13

.MESS9

 EQUS "L.BANK5 FFFF1300"    \ Port: *LOAD BANK5 FFFF1300
 EQUB 13

.MESS10

 EQUS "L.BANK6 FFFF1300"    \ Port: *LOAD BANK6 FFFF1300
 EQUB 13

.MESS12

 EQUS "L.HAZEL FFFF1300"    \ Port: *LOAD HAZEL FFFF1300
 EQUB 13

.MESS14

 EQUS "L.HICODE FFFF1300"   \ Port: *LOAD HICODE FFFF1300
 EQUB 13

.LOW_LOADER_END

\ Port: Saturn's drawing code and tables come last, above &1300 if need be:
\ they are used only before the first file is loaded to &1300, and everything
\ the loader runs after that (FTAB, the OS command strings, the copies, the
\ NMI handler and the vectors) is below &1300, asserted here

 ASSERT LOW_LOADER_END <= &1300

\ ******************************************************************************
\
\       Name: PLL1 (Part 1 of 3)
\       Type: Subroutine
\   Category: Drawing planets
\    Summary: Draw Saturn on the loading screen (draw the planet)
\  Deep dive: Drawing Saturn on the loading screen
\
\ ******************************************************************************

.PLL1

                        \ The following loop iterates CNT(1 0) times, i.e. &300
                        \ or 768 times, and draws the planet part of the
                        \ loading screen's Saturn

 STA RAND+1             \ Store A in RAND+1 among the hard-coded random seeds
                        \ in RAND. We set A to %00001111 before calling the PLL1
                        \ routine, so this sets the random number generator so
                        \ that it always generates the same numbers every time,
                        \ which is probably not what was intended (other
                        \ versions read the 6522 System VIA timer to use as a
                        \ seed, which is random). As a result, if you look at
                        \ the Saturn on the Master loading screen, it is always
                        \ exactly the same, every time you run the game

 JSR DORND              \ Set A and X to signed random numbers between -128 and
                        \ 127, so let's say A = r1

 JSR SQUA2              \ Set (A P) = A * A
                        \           = r1^2

 STA ZP+1               \ Set ZP(1 0) = (A P)
 LDA P                  \             = r1^2
 STA ZP

 JSR DORND              \ Set A and X to signed random numbers between -128 and
                        \ 127, so let's say A = r2

 STA YY                 \ Set YY = A
                        \        = r2

 JSR SQUA2              \ Set (A P) = A * A
                        \           = r2^2

 TAX                    \ Set (X P) = (A P)
                        \           = r2^2

 LDA P                  \ Set (A ZP) = (X P) + ZP(1 0)
 ADC ZP                 \
 STA ZP                 \ first adding the low bytes

 TXA                    \ And then adding the high bytes
 ADC ZP+1

 BCS PLC1               \ If the addition overflowed, jump down to PLC1 to skip
                        \ to the next pixel

 STA ZP+1               \ Set ZP(1 0) = (A ZP)
                        \             = r1^2 + r2^2

 LDA #1                 \ Set ZP(1 0) = &4001 - ZP(1 0) - (1 - C)
 SBC ZP                 \             = 128^2 - ZP(1 0)
 STA ZP                 \
                        \ (as the C flag is clear), first subtracting the low
                        \ bytes

 LDA #&40               \ And then subtracting the high bytes
 SBC ZP+1
 STA ZP+1

 BCC PLC1               \ If the subtraction underflowed, jump down to PLC1 to
                        \ skip to the next pixel

                        \ If we get here, then both calculations fitted into
                        \ 16 bits, and we have:
                        \
                        \   ZP(1 0) = 128^2 - (r1^2 + r2^2)
                        \
                        \ where ZP(1 0) >= 0

 JSR ROOT               \ Set ZP = SQRT(ZP(1 0))

 LDA ZP                 \ Set X = ZP >> 1
 LSR A                  \       = SQRT(128^2 - (a^2 + b^2)) / 2
 TAX

 LDA YY                 \ Set A = YY
                        \       = r2

 CMP #128               \ If YY >= 128, set the C flag (so the C flag is now set
                        \ to bit 7 of A)

 ROR A                  \ Rotate A and set the sign bit to the C flag, so A is
                        \ halved while retaining its sign
                        \
                        \ A is still a signed number from -128 to 127

 JSR PIX                \ Draw a pixel at screen coordinate (X + 128, A + 128),
                        \ where:
                        \
                        \   X = ZP / 2
                        \   A = r2 / 2
                        \   ZP = SQRT(128^2 - (r1^2 + r2^2))
                        \
                        \ So this is the same as plotting at (x, y) where:
                        \
                        \   r1 = random number from -128 to 127
                        \   r2 = random number from -128 to 127
                        \
                        \   (r1^2 + r2^2) < 128^2
                        \
                        \   x = (SQRT(128^2 - (r1^2 + r2^2)) / 2) + 128
                        \   y = (r2 / 2) + 128
                        \
                        \ which is what we want

.PLC1

 DEC CNT                \ Decrement the counter in CNT (the low byte)

 BNE PLL1               \ Loop back to PLL1 until CNT = 0

 DEC CNT+1              \ Decrement the counter in CNT+1 (the high byte)

 BNE PLL1               \ Loop back to PLL1 until CNT+1 = 0

\ ******************************************************************************
\
\       Name: PLL1 (Part 2 of 3)
\       Type: Subroutine
\   Category: Drawing planets
\    Summary: Draw Saturn on the loading screen (draw the stars)
\  Deep dive: Drawing Saturn on the loading screen
\
\ ******************************************************************************

                        \ The following loop iterates CNT2(1 0) times, i.e. &1DD
                        \ or 477 times, and draws the background stars on the
                        \ loading screen

.PLL2

 JSR DORND              \ Set A and X to signed random numbers between -128 and
                        \ 127, so let's say A = r3

 TAX                    \ Set X = A
                        \       = r3

 JSR SQUA2              \ Set (A P) = A * A
                        \           = r3^2

 STA ZP+1               \ Set ZP+1 = A
                        \          = r3^2 / 256

 JSR DORND              \ Set A and X to signed random numbers between -128 and
                        \ 127, so let's say A = r4

 STA YY                 \ Set YY = r4

 JSR SQUA2              \ Set (A P) = A * A
                        \           = r4^2

 ADC ZP+1               \ Set A = A + r3^2 / 256
                        \       = r4^2 / 256 + r3^2 / 256
                        \       = (r3^2 + r4^2) / 256

 CMP #&11               \ If A < 17, jump down to PLC2 to skip to the next pixel
 BCC PLC2

 LDA YY                 \ Set A = r4

 JSR PIX                \ Draw a pixel at screen coordinate (X + 128, A + 128),
                        \ where:
                        \
                        \   X = r3
                        \   A = r4
                        \
                        \ So this is the same as plotting at (x, y) where:
                        \
                        \   r3 = random number from -128 to 127
                        \   r4 = random number from -128 to 127
                        \
                        \   (r3^2 + r4^2) / 256 >= 17
                        \
                        \   x = r3
                        \   y = r4
                        \
                        \ which is what we want

.PLC2

 DEC CNT2               \ Decrement the counter in CNT2 (the low byte)

 BNE PLL2               \ Loop back to PLL2 until CNT2 = 0

 DEC CNT2+1             \ Decrement the counter in CNT2+1 (the high byte)

 BNE PLL2               \ Loop back to PLL2 until CNT2+1 = 0

\ ******************************************************************************
\
\       Name: PLL1 (Part 3 of 3)
\       Type: Subroutine
\   Category: Drawing planets
\    Summary: Draw Saturn on the loading screen (draw the rings)
\  Deep dive: Drawing Saturn on the loading screen
\
\ ******************************************************************************

                        \ The following loop iterates CNT3(1 0) times, i.e. &333
                        \ or 819 times, and draws the rings around the loading
                        \ screen's Saturn

.PLL3

 JSR DORND              \ Set A and X to signed random numbers between -128 and
                        \ 127, so let's say A = r5

 STA ZP                 \ Set ZP = r5

 JSR SQUA2              \ Set (A P) = A * A
                        \           = r5^2

 STA ZP+1               \ Set ZP+1 = A
                        \          = r5^2 / 256

 JSR DORND              \ Set A and X to signed random numbers between -128 and
                        \ 127, so let's say A = r6

 STA YY                 \ Set YY = r6

 JSR SQUA2              \ Set (A P) = A * A
                        \           = r6^2

 STA T                  \ Set T = A
                        \       = r6^2 / 256

 ADC ZP+1               \ Set ZP+1 = A + r5^2 / 256
 STA ZP+1               \          = r6^2 / 256 + r5^2 / 256
                        \          = (r5^2 + r6^2) / 256

 LDA ZP                 \ Set A = ZP
                        \       = r5

 CMP #128               \ If A >= 128, set the C flag (so the C flag is now set
                        \ to bit 7 of ZP, i.e. bit 7 of A)

 ROR A                  \ Rotate A and set the sign bit to the C flag, so bits
                        \ 6 and 7 are now the same

 CMP #128               \ If A >= 128, set the C flag (so again, the C flag is
                        \ set to bit 7 of A)

 ROR A                  \ Rotate A and set the sign bit to the C flag, so bits
                        \ 5-7 are now the same, i.e. A is a random number in one
                        \ of these ranges:
                        \
                        \   %00000000 - %00011111  = 0-31
                        \   %11100000 - %11111111  = 224-255
                        \
                        \ In terms of signed 8-bit integers, this is a random
                        \ number from -32 to 31. Let's call it r7

 ADC YY                 \ Set A = A + YY
                        \       = r7 + r6

 TAX                    \ Set X = A
                        \       = r6 + r7

 JSR SQUA2              \ Set (A P) = A * A
                        \           = (r6 + r7)^2

 TAY                    \ Set Y = A
                        \       = (r6 + r7)^2 / 256

 ADC ZP+1               \ Set A = A + ZP+1
                        \       = (r6 + r7)^2 / 256 + (r5^2 + r6^2) / 256
                        \       = ((r6 + r7)^2 + r5^2 + r6^2) / 256

 BCS PLC3               \ If the addition overflowed, jump down to PLC3 to skip
                        \ to the next pixel

 CMP #80                \ If A >= 80, jump down to PLC3 to skip to the next
 BCS PLC3               \ pixel

 CMP #32                \ If A < 32, jump down to PLC3 to skip to the next pixel
 BCC PLC3

 TYA                    \ Set A = Y + T
 ADC T                  \       = (r6 + r7)^2 / 256 + r6^2 / 256
                        \       = ((r6 + r7)^2 + r6^2) / 256

 CMP #16                \ If A >= 16, skip to PL1 to plot the pixel
 BCS PL1

 LDA ZP                 \ If ZP is positive (i.e. r5 < 128), jump down to PLC3
 BPL PLC3               \ to skip to the next pixel

.PL1

                        \ If we get here then the following is true:
                        \
                        \   32 <= ((r6 + r7)^2 + r5^2 + r6^2) / 256 < 80
                        \
                        \ and either this is true:
                        \
                        \   ((r6 + r7)^2 + r6^2) / 256 >= 16
                        \
                        \ or both these are true:
                        \
                        \   ((r6 + r7)^2 + r6^2) / 256 < 16
                        \   r5 >= 128

 LDA YY                 \ Set A = YY
                        \       = r6

 JSR PIX                \ Draw a pixel at screen coordinate (X + 128, A + 128),
                        \ where:
                        \
                        \   X = (random -32 to 31) + r6
                        \   A = r6
                        \
                        \ So this is the same as plotting at (x, y) where:
                        \
                        \   r5 = random number from -128 to 127
                        \   r6 = random number from -128 to 127
                        \   r7 = r5, squashed into -32 to 31
                        \
                        \   32 <= ((r6 + r7)^2 + r5^2 + r6^2) / 256 < 80
                        \
                        \   Either: ((r6 + r7)^2 + r6^2) / 256 >= 16
                        \
                        \   Or:     ((r6 + r7)^2 + r6^2) / 256 <  16
                        \           r5 >= 128
                        \
                        \   x = r6 + r7 + 128
                        \   y = r6 + 128
                        \
                        \ which is what we want

.PLC3

 DEC CNT3               \ Decrement the counter in CNT3 (the low byte)

 BNE PLL3               \ Loop back to PLL3 until CNT3 = 0

 DEC CNT3+1             \ Decrement the counter in CNT3+1 (the high byte)

 BNE PLL3               \ Loop back to PLL3 until CNT3+1 = 0

\ ******************************************************************************
\
\       Name: DORND
\       Type: Subroutine
\   Category: Maths (Arithmetic)
\    Summary: Generate random numbers
\  Deep dive: Generating random numbers
\             Fixing ship positions
\
\ ------------------------------------------------------------------------------
\
\ Set A and X to random numbers (though note that X is set to the random number
\ that was returned in A the last time DORND was called).
\
\ The C and V flags are also set randomly.
\
\ This is a simplified version of the DORND routine in the main game code. It
\ swaps the two calculations around and omits the ROL A instruction, but is
\ otherwise very similar. See the DORND routine in the main game code for more
\ details.
\
\ ******************************************************************************

.DORND

 LDA RAND+1             \ r1Â´ = r1 + r3 + C
 TAX                    \ r3Â´ = r1
 ADC RAND+3
 STA RAND+1
 STX RAND+3

 LDA RAND               \ X = r2Â´ = r0
 TAX                    \ A = r0Â´ = r0 + r2
 ADC RAND+2
 STA RAND
 STX RAND+2

 RTS                    \ Return from the subroutine

\ ******************************************************************************
\
\       Name: RAND
\       Type: Variable
\   Category: Drawing planets
\    Summary: The random number seed used for drawing Saturn
\
\ ******************************************************************************

.RAND

 EQUD &34785349

\ ******************************************************************************
\
\       Name: SQUA2
\       Type: Subroutine
\   Category: Maths (Arithmetic)
\    Summary: Calculate (A P) = A * A
\  Deep dive: Shift-and-add multiplication
\
\ ------------------------------------------------------------------------------
\
\ Do the following multiplication of signed 8-bit numbers:
\
\   (A P) = A * A
\
\ This uses a similar approach to routine SQUA2 in the main game code, which
\ itself uses the MU11 routine to do the multiplication. However, this version
\ first ensures that A is positive, so it can support signed numbers.
\
\ ******************************************************************************

.SQUA2

 BPL SQUA               \ If A > 0, jump to SQUA

 EOR #&FF               \ Otherwise we need to negate A for the SQUA algorithm
 CLC                    \ to work, so we do this using two's complement, by
 ADC #1                 \ setting A = ~A + 1

.SQUA

 STA Q                  \ Set Q = A and P = A

 STA P                  \ Set P = A

 LDA #0                 \ Set A = 0 so we can start building the answer in A

 LDY #8                 \ Set up a counter in Y to count the 8 bits in P

 LSR P                  \ Set P = P >> 1
                        \ and C flag = bit 0 of P

.SQL1

 BCC SQ1                \ If C (i.e. the next bit from P) is set, do the
 CLC                    \ addition for this bit of P:
 ADC Q                  \
                        \   A = A + Q

.SQ1

 ROR A                  \ Shift A right to catch the next digit of our result,
                        \ which the next ROR sticks into the left end of P while
                        \ also extracting the next bit of P

 ROR P                  \ Add the overspill from shifting A to the right onto
                        \ the start of P, and shift P right to fetch the next
                        \ bit for the calculation into the C flag

 DEY                    \ Decrement the loop counter

 BNE SQL1               \ Loop back for the next bit until P has been rotated
                        \ all the way

 RTS                    \ Return from the subroutine

\ ******************************************************************************
\
\       Name: PIX
\       Type: Subroutine
\   Category: Drawing pixels
\    Summary: Draw a single pixel at a specific coordinate
\
\ ------------------------------------------------------------------------------
\
\ Draw a pixel at screen coordinate (X + 128, A + 128). The routine uses the
\ same approach as the PIXEL routine in the main game code, except it plots a
\ single pixel from TWOS instead of a two pixel dash from TWOS2. This applies
\ to the top part of the screen (the four-colour mode 1 space view).
\
\ See the PIXEL routine in the main game code for more details.
\
\ ------------------------------------------------------------------------------
\
\ Arguments:
\
\   X                   The signed screen x-coordinate of the pixel to draw,
\                       from -128 to 127, to be plotted relative to the origin
\                       at (128, 128)
\
\   A                   The signed screen y-coordinate of the pixel to draw,
\                       from -128 to 127, to be plotted relative to the origin
\                       at (128, 128)
\
\ ******************************************************************************

.PIX

 TAY                    \ Copy A into Y, for use later

 EOR #%10000000         \ Add 128 to A and treat this as an unsigned number from
                        \ now on

 LSR A                  \ Set ZP+1 = &40 + 2 * (A >> 3)
 LSR A
 LSR A
 ASL A
 ORA #&40
 STA ZP+1

 TXA                    \ Set (C ZP) = (X >> 2) * 8
 EOR #%10000000         \
 AND #%11111100         \ i.e. the C flag contains bit 8 of the calculation
 ASL A
 STA ZP

 BCC P%+4               \ If the C flag is set, i.e. bit 8 of the above
 INC ZP+1               \ calculation was a 1, increment ZP+1 so that ZP(1 0)
                        \ points to the second page in this character row (i.e.
                        \ the right half of the row)

 TYA                    \ Set Y = Y mod 8, which is the pixel row within the
 AND #7                 \ character block at which we want to draw our pixel
 TAY                    \ (as each character block has 8 rows)

 TXA                    \ Set X = X mod 8, which is the horizontal pixel number
 AND #7                 \ within the character block where the pixel lies (as
 TAX                    \ each pixel line in the character block is 8 pixels
                        \ wide)

 LDA TWOS,X             \ Fetch a pixel from TWOS and poke it into ZP+Y
 STA (ZP),Y

 RTS                    \ Return from the subroutine

\ ******************************************************************************
\
\       Name: TWOS
\       Type: Variable
\   Category: Drawing pixels
\    Summary: Ready-made single-pixel character row bytes for mode 1
\
\ ------------------------------------------------------------------------------
\
\ Ready-made bytes for plotting one-pixel points in mode 1 (the top part of the
\ split screen). See the PIX routine for details.
\
\ ******************************************************************************

.TWOS

 EQUB %10000000
 EQUB %01000000
 EQUB %00100000
 EQUB %00010000
 EQUB %00001000
 EQUB %00000100
 EQUB %00000010
 EQUB %00000001

\ ******************************************************************************
\
\       Name: CNT
\       Type: Variable
\   Category: Drawing planets
\    Summary: A counter for use in drawing Saturn's planetary body
\
\ ------------------------------------------------------------------------------
\
\ Defines the number of iterations of the PLL1 loop, which draws the planet part
\ of the loading screen's Saturn.
\
\ ******************************************************************************

.CNT

 EQUW &0300             \ The number of iterations of the PLL1 loop (768)

\ ******************************************************************************
\
\       Name: CNT2
\       Type: Variable
\   Category: Drawing planets
\    Summary: A counter for use in drawing Saturn's background stars
\
\ ------------------------------------------------------------------------------
\
\ Defines the number of iterations of the PLL2 loop, which draws the background
\ stars on the loading screen.
\
\ ******************************************************************************

.CNT2

 EQUW &01DD             \ The number of iterations of the PLL2 loop (477)

\ ******************************************************************************
\
\       Name: CNT3
\       Type: Variable
\   Category: Drawing planets
\    Summary: A counter for use in drawing Saturn's rings
\
\ ------------------------------------------------------------------------------
\
\ Defines the number of iterations of the PLL3 loop, which draws the rings
\ around the loading screen's Saturn.
\
\ ******************************************************************************

.CNT3

 EQUW &0333             \ The number of iterations of the PLL3 loop (819)

\ ******************************************************************************
\
\       Name: ROOT
\       Type: Subroutine
\   Category: Maths (Arithmetic)
\    Summary: Calculate ZP = SQRT(ZP(1 0))
\
\ ------------------------------------------------------------------------------
\
\ Calculate the following square root:
\
\   ZP = SQRT(ZP(1 0))
\
\ This routine is identical to LL5 in the main game code - it even has the same
\ label names. The only difference is that LL5 calculates Q = SQRT(R Q), but
\ apart from the variables used, the instructions are identical, so see the LL5
\ routine in the main game code for more details on the algorithm used here.
\
\ ******************************************************************************

.ROOT

 LDY ZP+1               \ Set (Y Q) = ZP(1 0)
 LDA ZP
 STA Q

                        \ So now to calculate ZP = SQRT(Y Q)

 LDX #0                 \ Set X = 0, to hold the remainder

 STX ZP                 \ Set ZP = 0, to hold the result

 LDA #8                 \ Set P = 8, to use as a loop counter
 STA P

.LL6

 CPX ZP                 \ If X < ZP, jump to LL7
 BCC LL7

 BNE LL8                \ If X > ZP, jump to LL8

 CPY #64                \ If Y < 64, jump to LL7 with the C flag clear,
 BCC LL7                \ otherwise fall through into LL8 with the C flag set

.LL8

 TYA                    \ Set Y = Y - 64
 SBC #64                \
 TAY                    \ This subtraction will work as we know C is set from
                        \ the BCC above, and the result will not underflow as we
                        \ already checked that Y >= 64, so the C flag is also
                        \ set for the next subtraction

 TXA                    \ Set X = X - ZP
 SBC ZP
 TAX

.LL7

 ROL ZP                 \ Shift the result in Q to the left, shifting the C flag
                        \ into bit 0 and bit 7 into the C flag

 ASL Q                  \ Shift the dividend in (Y S) to the left, inserting
 TYA                    \ bit 7 from above into bit 0
 ROL A
 TAY

 TXA                    \ Shift the remainder in X to the left
 ROL A
 TAX

 ASL Q                  \ Shift the dividend in (Y S) to the left
 TYA
 ROL A
 TAY

 TXA                    \ Shift the remainder in X to the left
 ROL A
 TAX

 DEC P                  \ Decrement the loop counter

 BNE LL6                \ Loop back to LL6 until we have done 8 loops

 RTS                    \ Return from the subroutine

\ ******************************************************************************
\
\ Save M128Elt.bin
\
\ ******************************************************************************

 PRINT "S.M128Elt ", ~CODE%, " ", ~P%, " ", ~LOAD%, " ", ~LOAD%
 SAVE "3-assembled-output/M128Elt.bin", CODE%, P%, LOAD%

