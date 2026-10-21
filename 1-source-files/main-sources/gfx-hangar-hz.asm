\ ******************************************************************************
\
\ gfx-hangar-hz.asm - the hangar's tables (gfx-hangar.asm), in HAZEL after
\ the game data (elite-layout.asm): read by f_hback in bank 6, which has no
\ room
\
\ ******************************************************************************

\ HFY: the floor's lines far to near (#Y + 130 DIV Q, Q = 12 down to 2, as
\ HANGER's DVID4K computed them); the first is the wall's foot

.HFY
FOR q, 12, 2, -1
 EQUB Y + 130 DIV q
NEXT

\ HPWL, HPWH: the wall's and the floor's colours in f_col's packed form
\ (hangarcols.py, docs/renderer.md): the wall a darker tan, two yellow, a magenta
\ and a black pixel in each 2x2 cell (RGB about 191, 128, 64), the floor a
\ light tan, two yellow, a magenta and a cyan (about 191, 191, 128). Ink
\ counts in quarters make f_col's 4x4 Bayer tile a 2x2 one, yellow on a
\ diagonal: a regular pattern, no banding

.HPWL
 EQUB &08, &88
.HPWH
 EQUB &31, &41

