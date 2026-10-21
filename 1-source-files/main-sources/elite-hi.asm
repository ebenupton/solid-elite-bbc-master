\ ******************************************************************************
\
\ elite-hi.asm - the high code: the quarter squares, at the start of the
\ run's second part, main RAM from &7000 (docs/memory-map.md)
\
\ Port: no counterpart in the original. Main RAM &7000-&7DFF would be the
\ dashboard's, but the dashboard is in shadow RAM: the IRQ shows shadow RAM
\ from the dashboard's first line on (timer 1 sets ACCCON D in line 191's
\ horizontal blanking, never late), so main RAM from &7000 is never on show.
\ The main code's run continues there (elite-source.asm, at its split before
\ TACTICS), through &8000 into bank 4, after the quarter squares QSL and QSH,
\ which the port's multiplications (MU11, MULT1, MULTS, MLTU2, MULT3, the
\ stardust's) and the lighting (gfx-light.asm, in bank 6) use with bank 4,
\ 6 or 7 paged, so they must be outside the banks, and are too big for the
\ low area below &3000. Page aligned, as their users patch the operands' low
\ bytes. Like the run there, they are never used with ACCCON X set (which
\ hides main RAM at &3000-&7FFF).
\
\ Saved with the run's part in main RAM from &7000 as HICODE, which the
\ loader copies into place.
\
\ ******************************************************************************

\ ******************************************************************************
\
\       Name: QSL, QSH
\       Type: Variable
\   Category: Maths (Arithmetic)
\    Summary: Port: quarter squares for MULTS, MU11 and MULT1
\
\ ------------------------------------------------------------------------------
\
\ QSL and QSH are the low and high bytes of n^2 / 4 (rounded down) for n =
\ 0..511, so a * b = QS(a + b) - QS(|a - b|) for 8-bit a and b. The
\ multiplications that use them run in game context only (never with ACCCON
\ X set, which would hide these tables).
\
\ ******************************************************************************

 ASSERT LO(P%) = 0       \ (page aligned: the multiplications patch their
                        \ operands' low bytes, QSL+b and QSL-b, and index them)

.QSL

FOR n, 0, 511
 EQUB LO(n * n DIV 4)
NEXT

.QSH

FOR n, 0, 511
 EQUB HI(n * n DIV 4)
NEXT


