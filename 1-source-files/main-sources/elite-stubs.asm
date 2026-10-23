\ ******************************************************************************
\
\ elite-stubs.asm - the stubs between the hot side and the cold pass
\
\ Port (docs/memory-map.md, "Calls between the passes"): INCLUDEd in the glue
\ area, in main RAM below &3000, so that it is seen whatever is paged at
\ &8000-&BFFF.
\
\ Elite's game code runs with its home bank (HOMEBANK, sideways RAM bank 4)
\ paged in at &8000-&BFFF: the low pass, the hot pass (main RAM, then bank 4)
\ and the glue area call each other directly. The cold pass (the docked
\ screens, the charts, the title, save and load, the flight-rare routines)
\ is in sideways RAM bank 7 (COLDBANK). The source calls everything by the
\ original's names, and every call from one side to the other goes through
\ a stub of its own here, which 2-build-files/streams.py writes
\ (3-assembled-output/elite-stubs.asm), one per target:
\
\   .TT22 JSR to7 : JSR TT22_C : JMP to4        the hot side calls cold TT22
\   .x4_LL5 JSR to4 : JSR LL5 : JMP to7         the cold pass calls hot LL5
\   .TT170 JSR to7 : JMP TT170_C                a jump: the target never
\   .j4_BEGIN JSR to4 : JMP BEGIN               returns (TT170, BAY, ...)
\
\ A hot call of a cold routine X names X, which is its stub (its body is X_C
\ in the cold pass); the cold pass's calls of a hot routine H are renamed to
\ x4_H (j4_H for a jump). The cold pass calls the low pass's routines that
\ need nothing of the hot side (WSCAN, DELAY, CHPR, NOISE ...) directly, as
\ main RAM below &3000 is seen with bank 7 paged too (streams.py's
\ direct_calls, 3-assembled-output/direct.txt, which bankcheck.py reads). A routine that
\ falls through into a routine of the other side falls into a JMP to its
\ stub, at the routine's place: the stub calls the routine, which returns
\ to the falling routine's caller with the caller's bank back, as the
\ fall-through did (RES2 into ZINF, Ze into DORND2, SOLAR into NWSTARS;
\ BEGIN into TT170, a jump).
\
\ Each stub knows its caller's bank: every caller of a stub into the cold
\ pass runs with bank 4 paged (the game; NEWBRK, which the MOS enters with
\ any ROM paged, pages bank 4 first), and every caller of a stub out of it
\ runs with bank 7 paged. So a stub pages the target's bank in, calls it and
\ pages the caller's bank back, with no frame of its own: the target sees
\ only the stub's return address above its caller's (two bytes more than a
\ direct call; harness/mlib.mjs sees through it by the stubs' ranges,
\ STUBS7 to STUBS7_END and STUBS4 to STUBS4_END). A, X, Y and every flag
\ reach the target as they were at the stub, and come back unchanged.
\
\ to7 and to4 write &F4 before ROMSEL, so &F4 always matches ROMSEL or is
\ about to: an interrupt between the two writes that paged a bank and put
\ ROMSEL back from &F4 would page the bank the stub is about to page anyway,
\ and the stubs run in main RAM, which no paging hides. (No interrupt
\ handler pages a bank now: IRQ1, H_VSYNC and SOINT do not.)
\
\ A call through a stub costs 85 cycles more than a direct JSR (6 for the
\ JSR to the stub, 35 for to7's JSR and body, 6 and 6 for the JSR to the
\ target and its RTS, 3 for the JMP, 29 for to4's body and RTS); the far
\ calls this replaces (far7 and far4: the stub's address of the target read
\ through the stack and a self-modified operand) cost about 171. The
\ busiest stubs (streams.py's INLINE) are written out in full, 70 cycles.
\
\ ******************************************************************************

\ to7, to4: page bank 7 (the cold pass) or bank 4 (the hot pass) in, A and
\ the flags kept

.to7

 PHP
 PHA
 LDA #COLDBANK
 STA &F4
 STA VIA+&30
 PLA
 PLP
 RTS

.to4

 PHP
 PHA
 LDA #HOMEBANK
 STA &F4
 STA VIA+&30
 PLA
 PLP
 RTS

\ TTX66M: TTX66 (bank 4) for CHPR, which keeps the caller's bank, as CHPR is
\ also the WRCHV handler and the MOS may call it with a filing system ROM
\ paged in (a disc catalogue). A is not kept (TTX66 takes nothing in it, and
\ CHPR's three calls use neither A nor the flags it returns)

.TTX66M

 LDA &F4                \ the caller's bank
 PHA
 LDA #HOMEBANK
 STA &F4
 STA VIA+&30
 JSR TTX66
 PLA
 STA &F4
 STA VIA+&30
 RTS

 INCLUDE "3-assembled-output/elite-stubs.asm"        \ the stubs, one per target
