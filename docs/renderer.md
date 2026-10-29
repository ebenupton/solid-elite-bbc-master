# The filled renderer

The port's third part replaces Master Elite's wireframe drawing in flight
with a filled, dithered, lit and double-buffered renderer. The renderer
descends from the one written for the Elite Demonstration Disc. The game
logic is untouched: it runs exactly as the original does, and records what
it would have drawn. The renderer then draws a frame from those records at
the end of each main-loop iteration. The docked screens (status, market,
charts, the title's text, the disc menu) stay Master's own drawing.

[memory-map.md](memory-map.md) shows where each part lives.
[master-memory.md](master-memory.md) covers the hardware it relies on.

## The screen

The whole screen is one custom MODE 1 screen, 256 pixels wide, with one
fixed palette: logical colours 0 to 3 are black, cyan, magenta and yellow.
The loader sets this palette once, and the interrupt handler never changes
mode or palette. A filled colour is a 4x4 Bayer dither of the four inks.
This gives a ramp of shades for each hue, which the lighting steps
through.

* **The space view** is 192 lines at `&4000-&6FFF`. It is double buffered.
  Buffer 0 is main RAM `&4000-&6FFF` and buffer 1 is shadow RAM
  `&4000-&6FFF`. ACCCON X selects the buffer the CPU writes, and ACCCON D the
  one on show.
* **The dashboard** is 56 lines at shadow `&7000-&7DFF`, in the same MODE 1
  format and palette. Its image is BDATA, which
  `2-build-files/dashboard.py` draws. Master's dashboard routines (`SCAN`,
  `DOT`, the bulbs, `MSBAR`, `DIALS` and their helpers) are redrawn for it,
  at their places in bank 4. They redraw only the bytes that change, and
  they leave every temporary, register and flag that a caller can see
  exactly as Master's routines did. The game logic reads some of them: `Y1`
  and the carry after `SCAN`.

### Dashboard split timing

With buffer 0 on show, the dashboard must still come from shadow RAM. So the
interrupt handler sets ACCCON D at the boundary. The write must land in line
191's horizontal blanking: after the last fetch of the space view (cycle
24511 of the frame) and before the first fetch of the dashboard (24576).
That leaves a 64-cycle window.

The original restarted timer 1 at each vsync, so the split moved with the
interrupt latency. A section with interrupts off delayed it: `FILLKL`'s scan
held the interrupt off for up to 540 cycles. Measured over the gate's run,
the write landed 2 to 6 cycles early in about 1% of frames and up to four
lines late in about 0.9%.

Option D fixes this:

* `T1SYNC`, called once by `BEGIN`, waits for vsync with interrupts off. It
  starts timer 1 at `VSCAN(0 1)` and latches 19966, so the timer fires at the
  same raster position every frame, one frame of 312 64-microsecond lines
  apart, from the same crystal.
* `IRQ1` tests timer 1's flag first.
* Code that must not be interrupted by the vsync handler masks only CA1 in
  the System VIA's IER, never all interrupts with SEI. That covers
  `FILLKL`'s scan, `NOISE`, `SOFLUSH` and the frame flip.
* `VSCAN+1` is 72, which centres the write's 26-cycle spread in the window.

Measured over 62,000 frames (the gate, and agentplay sessions with keys
held), the timer's latency was 45 to 55 cycles, and the write was never
early or late. The margins are about 30 cycles early and 24 late. The
phase is set once, so anything that rewrote timer 1 or the CRTC's frame
registers would need `T1SYNC` again. Nothing does.

## The frame model

"Record mode" is `QQ11 = 0` (a view that draws ships) with `GFORCE = 0`. In
record mode, Elite's drawing routines call hooks at their start
(`gfx-hooks.asm`, `gfx-gluehooks.asm`). Each hook records what the routine
would have drawn, then returns from the routine itself:

* `LL9` records each ship that is not exploding as its part 6 starts
  (`H_LL42`): what part 6 on reads, and the faces' levels; the frame
  projects it as it draws it (see "The frame's records"). `H_EE31` records
  its laser beam if it is firing at us. `SHPPT` records a distant ship's
  dot.
* `CIRCLE` records the planet's disc, and `H_CIRC` hands the planet's
  orientation to the meridian window, which makes its surface detail (see
  "Planet surfaces"). A meridian planet's equator and meridian and a crater
  planet's crater are not worked out at all: in record mode `H_CIRC`
  returns from `PL9` itself, leaving what the game reads of that path as
  the original leaves it (`K2`, which `MV40` adds into the next object's
  y; `TGT`; `FLAG`). That path (`PL9` parts 2 and 3, `PLS2`, `PLS22` and its
  curve loop, `PLS3`, `PLS4`, `PLS5`) is `Area: none` in the source
  ([memory-map.md](memory-map.md)): planets are never drawn outside record
  mode, as `GFORCE` is set only for the hyperspace rings, which use
  `CIRCLE2`. `SUN` records the sun's half-widths.
* `PIXEL2` records a star. `PIX1` no longer erases a star's old position, a
  choice that `pxpat` patches once per star pass. `DOEXP` notes an
  explosion's cloud, which the frame draws from the ship line heap (see
  "The frame's records").
* `LASLI` (our lasers) and `SIGHT` (the laser sights) note theirs for the
  frame. `BOMBOFF` (the energy bomb's lightning) has the frame layer copy
  the bolt's ten points (`F_BOMB`: `BOMBTBX` and `BOMBTBY`, the last bolt
  drawn), and its nine lines record nothing. The frame's line list holds
  only the enemy beams, one per ship recorded (`MAXLN = MAXSH = NOSH`).
* `CHPR` and `CLYNS` keep a 32x24 **text map** of the characters the
  frames draw (see "The text map").

The launch and hyperspace rings are drawn directly, even in record mode
(`HFS2` sets `GFORCE`). Outside record mode every hook returns at once, so the
docked screens are drawn as before, into shadow RAM, which is then on show
all frame (direct mode).

At the end of each flight iteration, `H_MFRAME` (after `M%`, in `TT100` and
`DEATH`) runs the frame layer's `F_FRAME`. It renders the records into the
back buffer, two frames old:

1. Wait until the previous flip has happened.
2. Erase this buffer's old stars, which were plotted only into black bytes.
3. Per row, update the disc layer (the bigger of the planet and the sun,
   which is the nearer). From this buffer's old disc span, its old dirty
   extent and the new span, write the disc's colour where it is not
   already right, and black where something old is no longer covered. Then
   the second disc, the smaller and further one, where the layer leaves
   room (see "The sun near the planet"), and the moon, if the system has
   one (see "The moon").
4. Fill the ships far to near, each projected as it is drawn, each face a
   dithered polygon in its lit colour, with their details and fins. Then draw the lines and the
   particles. All of these extend this buffer's dirty extent for each row.
   A ship further away than the planet (or the moon), with the first vertex
   of its first visible face inside its disc, is not drawn (`f_behind`).
   `F_PLANET` records the planet's z for this as 16 bits; a planet 65536 or
   more away (z's third byte non-zero) is recorded as `&FFxx`, further than
   any ship drawn with faces (always nearer than 4096). Before that fix,
   only z's low 16 bits were kept, so a planet 65536-69631 away hid a
   station in front of it on a docking run (`6-harness/mstation.mjs`).
5. Draw the lens flare, if the sun is on screen (below).
6. Draw the text: in the rows that changed, erase the cleared cells and
   draw the row; elsewhere draw the cells whose pixels were drawn over. Then
   the laser sights.
7. Plot the stars last, only into screen bytes that are wholly black (see
   "Stars behind fills").
8. Request a flip at the next vsync. `H_VSYNC`, from `IRQ1`, shows the
   front buffer.

The frame rate is capped at 25 frames a second: each frame is on show for at
least two fields. `H_VSYNC` holds a pending flip for one field when the vsync
before it flipped (`GVLAST`), so a frame quicker than two fields waits at its
flip, while the next iteration's game code runs. A slower frame flips at the
first vsync after it is queued, as before. Every flip goes this way: flight,
the escape pod's drift, the title screens and the briefing's Constrictor.
The docked screens never flip. Before the cap, 10.7% of the gate's frames
were shown for a single field, so motion juddered between one field and two;
with it, none are. The cost is 4 cycles a vsync, 15 at a flip, and 13 bytes.
On the title screen the ship's approach, quicker than 25 frames a second
while the ship is small, now takes about 3.5 seconds rather than 2.3.

Because each buffer repairs only its own dirty rows, a frame costs what
changed, not the whole screen. Close to the space station, rows that hold
one solid span are kept from one frame to the next instead (see "Kept solid
rows").

`TTX66`, which clears the screen for a new view, enters direct mode
(`G_DIRECT`) and empties the frame's lists: `DEATH`'s and `ESCAPE`'s
`TT66` come in the middle of an iteration, so what it had recorded is gone
from the screen, and a frame's lists hold one record a ship slot at most. The first frame afterwards goes back to double buffering
(`f_enter`). An in-system jump (`WARP`) keeps the space view on show
(`GWARP`). A disc command stashes HAZEL in buffer 0, so it sets `GSTASH`,
and the next frame in space mode starts buffer 0 afresh (`f_b0new`). The
title screen's ship and the escape pod are one frame each (`LL9F`).

## Where the renderer lives

| Part | Where | What |
|---|---|---|
| The shared workspace | main `&0E00-&1E15`, below the main code | the state that the rasteriser's banks, the frame layer, the game's hooks and the IRQ handler share: the per-call inputs, the dirty extents, the disc rows' boundaries, the stars, the kept solid rows' `KF`, and what the frame reads of the moon (`gfx-planetv.asm`). Below `&3000`, so every bank sees it whatever ACCCON X is. `DFSST` and `DFSST2`, `DOSCLI`'s stash, are here too |
| Bank 4's end | after the hot pass and the hot data, bank 4 paged | the renderer's routines that run in game context, from `G_FRAME`: `S_SUN`, the sun near the planet (`gfx-ssun.asm`), and `L_SUN`, the light for the next iteration's ships (`gfx-light.asm`'s first pass); then the moon's collision test, `MOONHIT` (`elite-moon.asm`), from the main flight loop |
| The glue | the glue area, main RAM below `&3000` | the shared variables with initial values (`gfx-gvars.asm`), the `T_` trampolines from the frame layer into the rasteriser (`gfx-tramp.asm`), the text and IRQ hooks (`gfx-gluehooks.asm`), the `G_` stubs that page the frame layer in from game code (`gfx-gstubs.asm`) and the hooks in Elite's drawing code (`gfx-hooks.asm`) |
| The rasteriser's shared region | bank 5 `&9000-&BFFF`, paged with either window | the boundary arrays, `R_SETBUF`, the per-x tables, the 24 row-run pages at `&A000` (variables and small routines sit in their 65-byte tails), the stars, the second disc (`R_DISC2`), and the arithmetic and cold parts of both windows that use nothing of either window |
| The rasteriser's polygon window | ANDY `&8000-&8FFF`, ROMSEL `&85` | `R_POLY` (8-bit and 16-bit polygons) and `R_LINE` (lines, clipped exactly) |
| The rasteriser's disc window | bank 5 `&8000-&8FFF`, ROMSEL 5 | the disc rows, the dirty repair, `R_INIT`, `R_RESETBUF` |
| The frame layer | bank 6 | `gfx-frame.asm`, the ships' faces and colours (`gfx-faces.asm`), the lighting (`gfx-light6.asm`, and `L_REC` from `gfx-light.asm`; `L_SUN` is at bank 4's end), `frame_cold`, the flare's step and the hangar's frame. Then its state: the planet's and the sun's half-widths, the ship records (`F_RP`, `F_SR`, whose room holds `F_INIT` until the first frame), the zero page `F_FRAME` keeps (`f_zsv`), the text map (`F_TM`, `F_TMR`, `F_TCH`) |
| The hangar's tables | bank 6, at the end of its image | the floor's rows and the tans (`gfx-hangar6.asm`) |
| The meridian window | bank 7 after the cold pass, ROMSEL 7 (`MERID.bin`) | the planet's surface: the circle engine, `pc_circ` and `PC_ROWS` (`gfx-merid.asm`), and the styles and the moon, `PF_HOOK` and `pf_moon` (`gfx-planet7.asm`); then the kept solid rows' polygon part, `k_pre` and `k_settle` (`gfx-kept7.asm`); then the lens flare, `R_FLARE` and its tables (`gfx-flare.asm`) |

The two windows of bank 5 never call each other. The shared region refers to
neither, except where a line is marked. `bankcheck.py` checks this at every
build. ANDY is paged in only by the trampolines: `T_POLY` and `T_LINE` page
ROMSEL `&85`, and the rest page bank 5. The meridian window is paged in
only by its stubs, `G_PFHOOK`, `T_CAPS`, `T_MCAPS`, `T_KPRE` and `T_FLARE`. `&F4` always matches
ROMSEL.

## The rasteriser

The rasteriser draws spans into the back buffer. Each row of the space view
has an unrolled run of `STA abs,Y` stores (the row-run pages), entered at the
offset of a span's first byte and left after its last, with the row in Y.
`R_SETBUF` patches the runs' high bytes for the back buffer.

* `R_POLY` fills a convex polygon in a dithered colour. Phase A walks its
  edges into per-row left and right boundaries, with 8-bit or 16-bit DDAs.
  Phase B fills the rows.
* `R_LINE` draws a line. Both ends on screen take the fast loops. Any other
  line is clipped exactly to the window's sides first, with the original's
  rounding, and then takes the same loops.
* `R_DISCROWS` draws the disc layer row by row, from the old and new spans
  and the dirty extents.
* Stars are plotted only into wholly black screen bytes, and erased the
  next time.
* Every span extends its row's dirty extent for this buffer. The repair
  blacks the old extents that nothing new covers.

`6-harness/test_raster.py` runs every primitive on py65 against a
pixel-exact model, with this port's memory layout. It also checks that
nothing outside the screen, the rasteriser's memory and its zero page is
written. The gate runs it with `--quick`.

## Stars behind fills

`R_STARPLOT` plots a star's pixels in a screen byte only when the whole
byte is black, not just the star's own pixels. Every fill the frame layer
draws other than pure black (the ships' lit ramps and unlit colours, the
planet's and the sun's discs and colour B, the second disc, the moon, the
hangar's panels, the distant dots) has a coloured pixel in every byte of
every row of its dither, so no star shows through a fill's black pixels;
at a fill's edge a star lands only on black, within three pixels of the
edge. The test is also cheaper than testing the star's own pixels, by
about 6 cycles a star.

The one pure black fill, a station's docking slot, is handled apart:
`f_poly2` copies the slot's four vertices to `F_SLV` (bank 6) when it fills
it, and `F_FRAME` then plots the stars through `f_slot`
(`gfx-frame_cold.asm`), which takes the stars in the vertices' bounding box
out of `R_SS` for the plot and puts them back; `f_reset` (and `F_INIT`) mark
`F_SLV` empty. Without a slot the cost is one test a frame. The hangar's
black lines are the other black fill, and its frames plot no stars.

`2-build-files/starocc.py` proves the premise at every build (the Makefile
fails if it does not pass): from the bank 6 image, the symbols and the
sources, it checks every colour the build can give a fill (each writer of
the colour bytes must be of a source it knows), and that the docking slots
are the only black polygon details, each with four vertices.
`test_raster.py` models the rule, and `6-harness/mstarocc.mjs` puts a grid
of stars over the planet's sea, a dark ship, the docking slot and the sun
beside the planet, and screenshots them.

## The text map

The frames draw the text from one structure, the text map `F_TM` in bank 6
(768 bytes: the characters wanted in the 24 rows of 32 cells), with `F_TMR`
(24: the characters per row) and `F_TCH` (24: per row, bit b for buffer b).
Nothing records which characters each buffer shows.

**Why a whole map.** Besides the space views' few strings, the frames draw
the mission 1 briefing, which prints whole pages in space mode while
`LL9B`'s frames run: token 10's pages are 317 and 369 cells counting spaces
(420 at most). The title screen has about 90 cells, a flight view at most
about 61, `DEATH` about 39. A list of characters at two bytes an entry would
be larger than the map and would need an overflow path; the map has
neither a bound to keep nor an overflow.

**A cell** holds its character, 0, &80 + the character it had (cleared,
remembering it), or &80 (a buffer may show anything there). `F_TCH`'s bit b
(P) says the row has changed since buffer b's text steps last ran on it.
Between frames, for each buffer and row: if P is clear, the buffer shows
exactly the row's characters; if P is set, a cell holding c or &80 + c
shows c or nothing, one holding 0 nothing, one holding &80 anything. Every
change keeps that true (`f_char1`, `f_delchar0`, `f_clrtext0`):

* a character into an empty cell, or into a cleared cell remembering it
  (`TT66`, then the view's title): P set for both buffers, nothing erased,
  so a title cleared and printed again is left alone in both buffers;
* the same character printed again: the cell is cleared (`CHPR`'s EOR);
* a character into a cell holding, or remembering, another: the cell is
  erased at once in both buffers' next frames (`f_mark`): its pixels go into
  the buffer's dirty extents, its pixel rows are no longer kept in it (`KF`),
  and the rows go into the rasteriser's dirty row range;
* a character printed over the one that replaced it since the last frame
  leaves the cell as it is (`f_eor`: a ring of the last four replacements,
  forgotten at each frame's text steps). That is EOR's undo: `TT107` prints
  the hyperspace countdown's next number over the current one, then the
  current one again to take it out, so the space views show 15, 14, 13 ...
  as the original does (`images/countdown/sheet.png`: SNG47, the map
  without `f_eor` and with it, at a countdown's first ticks, made by
  `6-harness/mcountsheet.mjs`).

A buffer's text steps, in a row with P set: `f_text1` erases the cells with
bit 7 set, and `f_text2` draws every character of the row and clears P. In
the other rows `f_text2` draws only the characters something was drawn over
this frame. A cleared screen shows nothing, which is right for any P.

**Outside record and space mode** `CHPR` draws into shadow RAM (buffer 1)
and the map does not follow the screen. Main RAM (buffer 0) still holds the
last space-mode frame, and only what the screen's text does to the cells
buffer 0 may show is recorded (`f_drule`): a character drawn over a cell
holding or remembering the same character toggles it; over another it
becomes &80, which is then erased; a cell holding 0 is left alone.

**The direct text a frame can inherit.** After `DEATH`'s and `TITLE`'s `TT66
13`, which carry on in record mode, the only text printed directly before
the next space-mode frame is `TTX66K`'s hyperspace countdown (`ee3`: three
cells at (1..3, 1)), when a countdown is running. So `F_CHAR` notes the
first three characters drawn directly after a screen clear, and the first
change in record or space mode (or the first frame) puts them into the map
(`f_sync`). A fourth character, a delete or `CLYNS` on a direct screen, or a
`TT66` first gives the noted characters to `f_drule` instead: the screens
that print more than three characters directly always end with a `TT66`
before any frame.

**Cost and checks.** In bank 6, `F_TM` 768 bytes, `F_TMR` and `F_TCH` 24
each, the direct notes 11, `f_eor`'s ring 14, and `f_mark` 136 with its
tables. The gate's flight runs at 194,178 cycles an iteration (10.30
iterations per emulated second), and the docked screens draw text with no
upkeep of what each buffer shows (about 5% fewer busy cycles,
`mdocktime.mjs`). `6-harness/mfbcmp.mjs --frames` hashes both buffers at
every frame of the gate's run (and the development tree's replays do the
same over sessions with deaths, escape pods, the briefings, hyperspace,
dockings and view changes); with `--mask 1,1,3` it shows which frames
differ only in the countdown's cells. Against the per-cell shown state
this map replaced, 305,743 frames are identical but for 8,688 that differ
only in those three cells, where the space views now show the original's
number.

## The frame's records

What the frame layer keeps between the game's drawing calls and the frame
is what the frame cannot find in the game's own memory when it draws.

**Explosion clouds.** A cloud's record is the exploding ship's line heap,
which the game already keeps: its size, counter and vertex count, its seeds
and the vertices' screen coordinates. `DOEXP`'s draw pass notes the ship's
slot and data block (`H_PTCLS`, `F_CLOUD`) in the dot list, and the frame,
in its order, runs `PTCLS` on the heap again (`T_CLOUD`: bank 4, ACCCON X
clear, entering at `PTCLR`), its `PIXEL` calls plotting each particle
(`H_DOT`, `F_PDOT`). So the frame draws every particle the original draws,
from the same `DORND2` sequence and arithmetic, where a 64-entry dot list
dropped some (247 of the gate's 5,533). A slot that no longer holds an
exploding ship has nothing drawn, and the heap is not written between the
record and the frame: `MA15` removes no ship whose cloud was drawn, `KILLSHP`
moves only the heaps above the slot it removes, and `NWSHP` takes room
below them. In record mode both of `DOEXP`'s passes do only what the game
keeps of `PTCLS` (`F_CLOUD`): `DORND2` three times a particle, the seeds,
`RAND+1` and `RAND+3`, `Q`, `U`, `TGT`, `CNT` and `CNT2`;
`6-harness/records/live.mjs` (every byte `PTCLS` writes, watched to the
game's next access over the gate's run) finds nothing else read. The dot
list holds a distant ship's dot or a cloud, one per slot (`MAXDT =
MAXSH`). `6-harness/records/particles.mjs` checks every particle of the
gate's run against SNG47's `PTCLS` draw passes.

**Ships.** A ship's record is what `LL9`'s part 6 on (`LL42`: each vertex's
visibility, then the visible vertices' screen coordinates in `XX3`) reads,
taken as part 6 starts (`H_LL42`, `F_SHIP`): `INWK` 0-8, `XX16` as part 3
scaled it and `XX0` (`F_RP`, 29 bytes a ship, a field to an array of
`MAXSH`), the faces' levels (`F_SR`, which the frame's part 6 reads as
`XX2`), and the type, faces and `XX4`. The frame runs part 6 on itself for
each ship as it draws it, far to near (`f_proj`, `T_GAME` at `LL42P`: bank
4 with ACCCON X clear; `H_EE31` returns at once while `GPRJ` is set), into
`XX3`, which `f_ship` reads in place; the first ship in the order is
projected before the frame waits for the flip. The records take 528 bytes
where a buffer of `XX2` and `XX3` copies took 1,536.

In the game, `LL9` stops at part 6 for a ship that is not exploding:
`6-harness/records/live.mjs` finds nothing part 6 on leaves read but
`XX3`, by `DOEXP` (an exploding ship still projects all its vertices) and
`H_EE31` (a ship firing at us has its gun vertex alone projected, `F_GUN`
setting part 6's loop on it). The frame keeps the 20 zero page bytes its
game code changes that the game reads afterwards (`f_gkeep`, `f_gback`).
`XX3` is page 1, under the stack, so `F_FRAME` keeps the zero page it uses
(`&06-&27` and `&D2-&E1`) in bank 6 (`f_zsv`), not on the stack. The lowest
S while the frame projects, interrupts included, against the end of the
largest ship's `XX3` (37 vertices, `&193`): flight and docking `&D4` (65
bytes to spare), the escape pod `&DD`, the title screen, the docking
tunnel, the hangar and the briefings `&C0` (44; the briefing's Constrictor
ends at `&143`). `6-harness/records/stack.mjs` measures it over the gate by
the pilot's phase, and `STACKWATCH=1` in `mshipshow.mjs` and `mbrief.mjs`
on the title and docked screens. `6-harness/records/combat.mjs` flies a
scene of up to seven hostile ships, one set exploding every 12 iterations,
and compares two builds' game state and pixels frame by frame.

## Kept solid rows

In the last seconds of docking the station fills the screen, and most rows
are one face from edge to edge. Each frame would erase those rows and fill
them again with the same byte. Instead, a row is **kept** in a buffer when
the last thing drawn on it there was one polygon span covering the row's
whole dirty extent, at least 8 whole bytes, not black. `KF`, one byte a
row, holds bit 0 or 1 for a row kept in buffer 0
or 1, and bit 7 for a row pending this frame.

* **K mode.** All of this runs only while the space station is recorded
  close (z below `&200`) inside the safe zone, and, once K mode has run
  three frames, only while the repair keeps finding at least 16 kept rows
  (otherwise it sits out four frames). `T_KFRAME` decides before each
  frame. Outside K mode `KF` is all zero, and the cost is a few tests of
  `KMODE`, about 90 cycles a flight iteration.
* **The repair** (`r7_rowrep`) leaves a kept row as it is and makes it
  pending, with its old extent still in the dirty extents.
* **Record and settle.** `R_POLY` calls `k_pre` (bank 7, through `T_KPRE`)
  between its phases, once per polygon. A span on a pending row settles it
  (`k_settle`): if the span and colour are unchanged, nothing is written at
  all; otherwise only the bytes between the old and new ends are written,
  and if the colour is the same, phase B skips the row. A span that covers
  a row's dirty extent so far keeps the row.
* **Everything else** drawn on a pending row (lines, dots, spans, text, the
  lens flare) first blacks it and forgets it (`k_kill`, from the
  trampolines). After the ships, `k_commit` blacks the rows still pending.

The pixels are the same as without it: frame hashes of both buffers match
over replayed elite-agent sessions with three dockings. Dockings run 7.6%
to 10.6% faster over their last seconds, and up to 27% faster in single
frames with the station filling the screen. Flight elsewhere is unchanged.
`test_raster.py`'s `kept` test drives multi-frame sequences through K mode
against the model.

## Lighting

The sun is the light source in flight. `L_SUN`, once per frame, keeps the
light's direction (`LLT`, in the glue area). It runs in game context, so it
is at bank 4's end: `G_FRAME` calls it in a space view before it pages bank
6 for `F_FRAME`, and `G_HANGAR` for the hangar. `gfx-light.asm` holds it and
`L_REC` as two passes, which `2-build-files/lightpass.py` writes out for
bank 4 and bank 6. It is reseeded from the sun's position every 32
iterations and rotated by the roll and pitch in between. On the title screen
and in the hangar the light is fixed, from the top right and the viewer.
`L_REC`, as each ship is recorded, writes each visible face's level,
`round(31 * max(0, n.L))`, into the record. The products are exact, using
the quarter squares.

Each ship has two hues out of nine 32-entry ramps that all ships share. Each
ramp runs from 50% to 100% of its hue's brightness. A face takes one hue and
its level picks the shade. Details take their face's level in the other hue,
and fins the brighter of their two faces. Lines, the stations' docking slots
and distant dots are unlit. The docking slot is filled, then outlined in
yellow, so it shows from as far away as the original's wireframe slot does.

## Lens flare

When the sun is on screen in the front view, the frame draws eight ghosts along the line from the screen's centre through
the sun: six dithered discs and two dotted rings. They are ORed in their
inks, so the light adds up. Three levels of brightness depend on how far the
sun is from the centre. The flare extends each row's dirty extent, so the
next frame on the buffer repairs it like any other shape. It never touches
game state. `f_flt` (bank 6) makes the tests and `R_FLARE` (in the
meridian window, bank 7) draws. `T_FLARE` pages bank 7 for it, then makes
the flare's two bank 5 calls: `R_MARKDIRTY` for the rows written, which
`R_FLARE` returns (C set if the sun was in sight, the rows in Y to X), and
in K mode `k_clear`.

The flare is turned down, or off, as the sun is hidden. Before drawing any
ghost, `R_FLARE` probes the back buffer as drawn so far (the planet, ships,
dots and lasers; the text, sights and stars come after the flare) at nine
points of the sun's disc: the centre, and eight round it at about 0.62 R
(left, right, up, down and the diagonals; offsets R/2 + R/8 and R/2 - R/16,
with R capped at 127).

* A probe outside the clip window (x 2 to 253, y 1 to 191) is out of sight.
* A probe inside is in sight if its pixel is still the sun's colour for its
  row: `FC_SUNE` on even rows and `FC_SUNO` on odd ones, so a dithered row is
  compared pixel by pixel with its own colour byte (`fl_pxm`). ACCCON X is
  the frame layer's, so the reads see this buffer.
* When the sun is the second disc, behind a bigger planet, a probe inside
  the planet's span on its row is out of sight (`FL_BEH`, which `f_flt` sets),
  as the planet's colours could pass the colour test; `R_FLARE` reads this
  buffer's disc spans for it. So a sun rising over the limb turns the flare
  up in steps.
* With no probe in sight there is no flare, and nothing is marked dirty. In
  K mode the kept rows are forgotten only when the flare draws.
* Otherwise every ghost's density steps down 0 (all nine in sight), 1 (seven
  or eight), 2 (four to six) or 3 (one to three) more rungs of its ladder
  (`fl_vred`).

`f_flt`'s tests are still made first: the front view and the sun's centre
on the screen. The probes take
1,200-1,280 cycles a flared frame, so a hidden sun's flare costs about 1,440
cycles where a drawn flare costs 14,000-28,000. `6-harness/mflarevis.mjs`
puts the sun, and optionally a ship, on paths in front of the gate's pilot
and dumps each frame's back buffer with the probes' count and cycles;
`2-build-files/flarevis.py` renders the dumps.

## Planet surfaces

Every feature of a planet's surface is drawn as a circle on its sphere: the
boundary of the region {p : m.p >= d}, for a unit axis m and a cosine d. A
meridian or the equator is a great circle (d = 0), a crater a small cap,
and a band the region between two latitude circles about the spin axis. A
**style** is a few such circles and a base colour, and a pixel's colour is
the base EOR the parity of the regions it is in. Each circle is projected
exactly, so the boundaries meet the limb and each other without tears.

A meridian planet (type 128, Lave's among them) is drawn as the
Demonstration Disc port's beach ball rather than with Elite's equator and
meridian: the great circles normal to its `roofv` and `sidev` vectors, with
base colour 1, so that where a point is on the same side of both it is
colour B (green land), and elsewhere colour A (the sea, `FC_PLANE` and
`FC_PLANO`).

A crater planet's craters are true spherical caps, {p : m.p >= r c}, each
drawn where it is seen and cut by the limb where it is not, on a blue body
(base colour 0) in the land's green (`FC_PLLE`, `FC_PLLO`). There are up to
three, from the system's seed (`QQ2`): the first on `roofv`, 30 degrees
across, as Elite's crater; then, as the seed's bits have it, one on `nosev`
tilted towards `sidev` and one on `sidev` tilted towards `roofv`, 15 to 30
degrees across. No two axes are within 63 degrees, so they never overlap.

**Banded planets** are an option, `make bands=on` (`_PLANET_BANDS`), off by
default, when their code is assembled out. With it, a quarter of the
crater planets (by the seed; Lave is a meridian planet and keeps its beach
ball) are drawn with two latitude circles about the axis the planet spins
about, `nosev - sidev` (`MVEIT` pitches `roofv` and `nosev` and rolls `roofv`
and `sidev` alike, so that axis stays where it is): north of one latitude
(14 to 36 degrees) and south of another (-7 to -30 degrees), EOR'd, so the
polar zones are colour A and the belt between them colour B. As the axis
does not turn, the belt stands still while the planet spins. Two
parallels can put four crossings in a row, which the disc layer holds.
`test_raster.py` tests the planet code with bands on (`BANDS=off` in its
environment for the default), and `planet_caps.py`'s `BANDS` follows it.

The disc layer already draws up to four boundaries a row. It keeps two of
them a row for each buffer (`R_BDN`, `R_BDX0`, `R_BDX1`), so that the
row's next change can be drawn as strips; a row with three or four is
stored as unknown (count `&40`), and its next change is repainted segment
by segment. Over the gate's run 2.5% of the beach ball's rows have three
boundaries and almost none four, and keeping only two is quicker (the rows'
cycles fall 1.8%) and frees 1,039 bytes of bank 5. What the surface needs
is the geometry, which has its own window: the meridian window, in bank 7
after the cold pass, with the circle engine (`gfx-merid.asm`) and the
styles (`gfx-planet7.asm`). It has two entry points, each behind one stub
in the glue area:

* `PF_HOOK` runs in game context, for every planet. `H_CIRC` calls it
  through `G_PFHOOK` (from `K`, `K3` and `K4`), in place of the equator and
  meridian (`PLS4`, `PLS1`, `PLS5` and `BLINE` no longer run for meridian
  planets) and the crater (`PL26`'s ellipse is neither worked out nor
  recorded). It makes the planet's class
  (`PF_CLS`: 0 a meridian planet, 1 craters, 2 bands; bit 7 when it made the
  detail this frame, which `H_CIRC` clears) and its circles' records.
  `pc_circ` makes one circle's record (24 bytes) from its axis, its cosine
  and the body: the projected ellipse's constants (`a`, `K0`, `K2` and `s0`,
  multiplied with the quarter squares), its centre line at its centre row,
  and two threshold rows, where the circle meets the limb. Along a row
  m.p - d is concave on the visible hemisphere, so whether each of a row's
  two crossings is a boundary, and the colour the row starts in, are
  comparisons of the row with the two thresholds. A circle wholly hidden
  keeps no record.
* `PC_ROWS` runs during the frame. `f_bounds` calls it through `T_CAPS`
  before the disc rows, when `PF_HOOK` made the detail this frame. It fills
  the rows with the base colour EOR the left limb's toggles, then for each
  record walks the rows out from its centre row, stepping the ellipse's
  terms as the beach ball's row loop did, and writes each row's boundaries
  into the disc layer's arrays, which `R_DISCROWS` then draws like any
  other disc.

Each frame the planet spins as in the original, by 1/16 radian in roll and
pitch, so the records are made every frame. Keeping rows between frames
would pay only for a circle that is hidden or edge-on, and is not done.

The 6502 code matches two reference models row for row:
`6-harness/planet_caps.py` models the engine and the styles bit for bit,
and the beach ball's rows are those of `6-harness/planet_analytic.py`
pixel for pixel (but for a pair of equal boundaries where both of a row's
crossings meet, which the engine leaves out). `test_raster.py`'s `merid`
test runs `PF_HOOK` and `PC_ROWS` against both models on random planets
(with Master Elite's own zero-page addresses for `K3` and `K4`), `pfhook`
runs `PF_HOOK` on random crater and meridian planets, `caps` runs the
engine alone on random circles, and its `beachball` and `capball` frames
feed a spinning planet's rows through `R_DISCROWS`. `6-harness/mplanet.mjs`
poses planet scenes and dumps each frame with the planet routines' cycles,
for `2-build-files/planetvis.py` to render.

What each style costs, in cycles a frame (`6-harness/mplanet.mjs`, the
planet at the screen's centre, 16 frames of spin at 22.5 degrees each, the
mean): the set-up is `G_PFHOOK` (`PF_HOOK` and its `pc_circ` calls), the
rows `T_CAPS` (`PC_ROWS`), and the disc `T_DISCROWS` (the disc layer,
incremental between frames). A crater planet's caps are as the seed gives
them, and a cap on the far side costs its set-up only; the plain disc is
the frames with no detail (a crater planet whose only crater is hidden).
The bands are a `make bands=on` build's.

| Style | Radius | Set-up | Rows | Disc | Total |
|---|---|---|---|---|---|
| Plain disc | 30 / 60 / 90 | 18.0K | 0 | 27.5K / 34.8K / 43.0K | 45.5K / 52.8K / 60.9K |
| Beach ball | 30 / 60 / 90 | 25.6K | 29.4K / 53.4K / 77.7K | 69.2K / 132.9K / 200.6K | 124.2K / 211.9K / 303.9K |
| Craters, 1 cap | 30 / 60 / 90 | 18.2K | 6.8K / 11.4K / 16.3K | 33.6K / 56.3K / 80.6K | 58.7K / 85.9K / 115.0K |
| Craters, 2 caps | 30 / 60 / 90 | 36.1K | 11.7K / 19.6K / 27.5K | 46.6K / 83.8K / 125.2K | 94.5K / 139.5K / 188.8K |
| Craters, 3 caps | 30 / 60 / 90 | 53.8K | 18.0K / 29.8K / 41.6K | 56.6K / 104.4K / 156.7K | 128.5K / 187.9K / 252.0K |
| Bands | 30 / 60 / 90 | 38.7K | 33.8K / 60.3K / 87.1K | 26.7K / 43.5K / 59.4K | 99.3K / 142.5K / 185.1K |

The beach ball is the dearest: its two great circles cross every row, and
as the planet spins every boundary moves, so the disc layer repaints most
of the disc each frame. The bands cost about as much in rows but stand
still under the spin, so the disc layer has little to repair. A cap's rows
scale with its size, not the disc's.

`images/planets` holds a still of each style, made by
`2-build-files/stills.sh` from posed scenes: `beach.png`, `caps.png` and
`caps2.png` (Leesti's craters), `nobands.png` (a banded seed as the default
build draws it), `bands.png` and `bands2.png`, `moon1.png` to `moon3.png`,
and `ring.png`, `ring2.png`, `ringmoon.png` and `ringmoon2.png` (the bands
and rings from a build with `make bands=on rings=on`).

## The moon

A quarter of the systems (by the seed: `h` = `s0_hi EOR s1_hi EOR s2_hi`,
bits 0-1 = 1) have a moon. It is scenery only: no ship slot, no random
number, no saved state. It is 0.19 to 0.28 of the planet's radius, drawn
for planets of radius 16 or more, light grey (equal parts of the four
inks) with a dark grey crater on `roofv`, 40 degrees across, from a moon
radius of 10 (a circle record of the engine in slot `PCMAX`, its rows made
by `PC_MROWS` through `T_MCAPS`).

**Its place** is a point fixed in space, as `S_SUN` keeps the sun: `MN_TURN`
(`gfx-ssun.asm`, bank 4, game context) keeps E = moon - planet (`MN_E`,
24-bit two's complement, in the shared workspace beside `S_SUN`'s D) and
turns it with our roll and pitch once an iteration by `MV40` itself
(`ss_turnx`), at the first call with a new `MCNT`: `G_PFHOOK`, before the
planet's detail, or `S_SUN` after the iteration. E is made in the first
iteration after we arrive or launch, when the planet still has `ZINF`'s
orientation: on its spin axis, (-1, 0, -1) / sqrt(2), on the side the seed
gives, 3 to 5.25 radii out. The planet's own spin axis would not do, as
`TIDY` renormalises its orientation every 16 iterations with one-byte
precision, turning the axis by up to 3 degrees at a time. `MN_OK` is
cleared in witchspace, with no planet, while docked and when `QQ2` changes.

**Drawn.** `pf_moon` (`gfx-planet7.asm`, bank 7, from `PF_HOOK`) projects
planet + E in the view's axes as `PLUT` has them; the moon is behind the
planet if E's z is positive, and behind the sun if further than it. What
the frame reads (`MN_ON`, `MN_X`, `MN_Y`, `MN_R`, `MN_Z` ...,
`gfx-planetv.asm`) is in the shared workspace. The frame layer's `f_moon`
draws it as a third disc after the sun and the planet, less their spans
where they are in front, and `f_behind` hides a ship further than the moon
whose first vertex is inside its disc. It is drawn incrementally: each
buffer keeps the moon as it drew it (`MO_ON` ... `MO_CB`), and only the rows
that changed since that buffer's last frame are drawn:

* the same place, size and depth: a plain row only where this frame wrote
  over it (the written extents), a crater row whole, as the crater turns
  with the planet;
* moved, resized, its depth changed, or gone: `f_moon0`, before the disc
  layer, puts the old moon into the dirty extents, so the layer's repair
  restores what was under it, and the moon is drawn whole.

Its writes go through `T_WSPAN` (`R_WSPAN`, bank 5: a span noted in the
written extents, as `R_DISC2`'s are, never in the dirty ones). A still
moon costs 29% less than one drawn whole each frame.

**The moon is solid**: flying into it kills us, as the planet does. The
main flight loop's part 15 (`MA22`) calls `MOONHIT` (`elite-moon.asm`, at
bank 4's end) before the planet's altitude test, and on C set jumps to
`MA28`, the planet's crash (`DEATH`: the same sound, the same death
screen). `MOONHIT` tests on the planet's altitude iteration (`MCNT` mod 32 =
10), in systems with a moon: with the moon's centre M = P + (E >> 8), we
have crashed if |M|^2 < (rho 96)^2. It writes no zero page and nothing of
the game's but by crashing, and in a system without a moon it returns at
once. This is the port's one change to the game: SNG47 has no moons, so in
a system with one a run that flies into the moon diverges from SNG47
there. The gate's systems have none. For a lockstep comparison in a moon
system, build with `make moon=scenery` (`_MOON_SOLID` FALSE: no call of
`MOONHIT`). `6-harness/mmoonhit.mjs` puts the moon at a chosen distance
dead ahead: inside its radius we crash, outside we do not, and a system
without a moon never does.

`test_raster.py`'s `pfhook` test checks the moon (`MN_ON`, `MN_X`, `MN_Y`,
`MN_R`, `MN_Z` against `planet_caps.py`'s `pf_moon`, with random E, views
and positions) and its crater's rows. `6-harness/mmoonpath.mjs` records a
long turning flight in a moon system, and `2-build-files/moonpath.py`
checks it: over 1,600 iterations |E| stays within 0.8%, its angle to the
station less the planet within about 0.3 degrees, and the drawn centre
within 1.4 pixels of planet + E projected.

[elite-agent](https://github.com/8bitkick/elite-agent)'s moon mode places
the moon as the port does and steers clear of it; the development tree's
agentplay runs it, and films an arrival in a moon system to the docking
(the system (155, 60), reached from (156, 57), with the moon beside the
planet in the front view at the arrival), with the moon and then the sun
near the planet, with its flare, each on the screen for most of a minute.
`images/moon/approach-sheet.png` is a sheet of the film's frames, and
`images/moon/approach.json` its record.

## Planet rings

Planet rings are an option, `make rings=on` (`_PLANET_RINGS`), off by
default, as the bands are: then `pf_ring`, its helpers, tables and
variables (bank 7), `f_ring` (bank 6) and the dots' arrays (the shared
workspace) are assembled out. With it, an eighth of the systems (by the
seed) have a ring: a dotted ellipse in the plane of the planet's equator,
normal to the spin axis `nosev - sidev`, so its shape on the screen stays
put while the planet turns. `pf_ring` uses conjugate diameters: two radii,
`roofv` and (`nosev` + `sidev`) / sqrt(2), scaled to the ring's radius on
the screen (1.6 to 2.2 planet radii), give its points P(t) = cos t A1 + sin
t A2 and -P(t), t = i pi / 32 (32 or 64 dots); a point is behind the
planet's centre if its z is negative. The dots go to `RG_X`, `RG_Y` and
`RG_F` (`gfx-planetv.asm`, in the shared workspace), and the frame layer's
`f_ring` draws them in yellow after the moon (`T_DOT`, marked dirty), but
not a dot behind the planet's centre and inside its disc. `test_raster.py`
assembles the planet code with rings on (`RINGS=off` in its environment for
the default), checking the dots against `planet_caps.py`'s `pf_ring`.

## The sun near the planet

Elite has one slot, `FRIN+1`, for the sun and the space station. Every 32
iterations, part 15 of the main flight loop checks whether we are near the
planet; if so, `WPLS` removes the sun from the screen and `NWSPS` puts the
station in its slot. When the station is out of range, `KS4` makes a new sun
overhead, and after a launch there is no sun at all. The game state must
stay SNG47's, so none of that changes: the renderer draws the sun as
scenery instead, where it would have been, for the frame only.

`S_SUN` (`gfx-ssun.asm`, at bank 4's end with `L_SUN`) runs after every
main-loop iteration, from `G_FRAME` with bank 4 paged, before `F_FRAME`. It
writes only its own variables and the frame's (`F_SUX`, `F_SUY`, `GSUNR`,
`GSUNON`, `SS_OK`); the zero page and the game's variables that it borrows
are kept and put back.

* **The sun in its slot**, and the planet within one sign unit on every
  axis: in the frames with `MCNT AND 31` = 1 or 0 (the last before part 15
  can swap the slot) it takes D = sun - planet (24-bit two's complement,
  `ss_d`, in the shared workspace). Further out, D is forgotten.
* **The station in the slot**: our own movement moves the planet and the
  sun alike, so D only turns, and it is turned by our roll and pitch by
  `MV40` itself (`ss_turn`: D into `INWK`'s coordinates, `MV40` with `TYPE`
  129 and `DELTA` 0, so that `MV45` moves z by nothing and returns). In
  record mode the sun is recorded at planet + D, as `PLANET` would draw it
  (the view's axes as `PLUT`, `PLANET`'s tests on z, `PROJ`, the radius
  24576 / z, `CHKON`).
* **The station in the slot and D unknown** (we launched, so this system's
  sun was never in the slot): D comes from the system's seeds by `SOLAR`'s
  own code. The `SOLAR` block is tagged `Area: cold, again`, so `streams.py`
  emits it a second time (`elite-source-again.asm`, with no stubs and its
  labels and call targets named `A_<name>`), which `ss_seed` includes and
  enters at `A_nobirths`, with stand-ins for `SOS1` and `NWSHP` that note
  `INWK`'s coordinates instead of making ships ([memory-map.md](memory-map.md)).
* Docked (`F_DIRECT` clears `SS_OK`), in witchspace or with no planet: no
  sun.

When `KS4` brings the game's own sun back, it is overhead, as in the
original, and the drawn sun jumps there. The lighting keeps turning its
light while the station has the slot.

**Two discs.** `PLANET` gives the sun and the planet the same radius at the
same z, so the bigger disc is the nearer. `f_discs` makes the bigger one
the disc layer, and `f_disc2` draws the smaller one only where the layer's
span on each row leaves room, up to two pieces a row: a sun behind a bigger
planet is cut by its limb, a planet behind a bigger sun by the sun, and
ships are drawn after both. A planet that is the second disc is a plain
disc, without its surface detail.

The second disc is incremental, as the original's sun is (its `SUNX` and
line heap): `R_DISC2` (`gfx-raster_disc2.asm`, at the end of bank 5's
shared region) keeps, for each buffer, the second disc's span on every row
(`R_S2L0` and `R_S2L1` in the room below the per-x tables, `R_S2R0` after
the disc window, `R_S2R1` after `R_DISC2`), its rows and its colour
(`R_S2T`, `R_S2B`, `R_S2C`, in the shared workspace). After `R_DISCROWS`,
everything that can have happened to the old pieces since the buffer's
last frame is in the rows' written extents (`R_WL`, `R_WR`), so per row
only the ends that moved, and what was written over the span, are drawn
again; the old span is blacked and the new one drawn whole only when they
are apart, one is empty or the colour changed. Its writes are masked to
their pixels and go into the written extents, not the dirty ones, so the
next frame does not repair them. `f_disc2` calls `T_DISCROWS` with C set,
which `R_DISCROWS` sends to `R_DISC2`. `r_lput2` hands spans of 16 pixels or
more to the row run.

A frame with the sun in view costs `S_SUN` about 3,200 cycles and the
second disc 2,500 (held still) to 17,600 (rising); in the front view the
lens flare costs most, as anywhere. On the gate's docking approach, with a
small sun in the front view, the windows run 3.1% and 7.0% slower than
without it; elsewhere the cost is within 0.1%. `test_raster.py`'s `disc2`
test drives two discs drifting, crossing, coming and going on two buffers,
with ships, lines, dots, text, stars, resets and K mode, against the model
every frame. `6-harness/msunnear.mjs` poses the scene (a big planet, the sun
rising from behind its limb, the station crossing), `msunprof.mjs` profiles
a stretch of the gate's run, and `2-build-files/sunnear.py` renders the
frames, a sheet and a movie: `images/sunnear/sunnear.gif` (the sun rising
from behind the planet's limb with the flare's probes going 0 to 9, then
the station crossing it), `sheet.png`, and `spawn.png`, the frame after the
station appears in the game's own way (`msunnear.mjs --spawn`), with the
sun drawn where the game's own sun was.

## Every disc, incremental

Like the original's sun, every disc keeps what it drew and redraws only
what changed:

* the planet or the sun as the disc layer (`R_DISCROWS`: each buffer's
  spans and boundaries);
* the smaller of them, the second disc (`R_DISC2`);
* the moon, by rows (`f_moon`).

A row's boundary count and its colour at the span's left end are one
byte: `R_NDN` holds the count in bits 0-6 and the colour in bit 7
(`PC_ROWS` and `PC_MROWS` write it so, `f_moon` reads it), and each
buffer's stored boundaries likewise (`R_BDN`). An unchanged row is then one
compare of the two bytes, and `r_dpe` finds a changed row's count
difference with the colours shifted out. The disc memory, in bytes:

| Structure | Where | Bytes |
|---|---|---:|
| `R_DISCL0/R0/L1/R1`, the layer's spans by buffer | shared workspace | 768 |
| `R_BDN`, `R_BDX0`, `R_BDX1` by buffer, its boundaries | bank 5 | 1,152 |
| `R_S2L0/L1/R0/R1`, the second disc's spans by buffer | bank 5 | 768 |
| `R_NDN` (count and colour), `R_NDX0-3`, this frame's boundaries | shared workspace | 960 |
| `R_NDISCL/R`, this frame's spans (the polygons' edge tables between the frames' discs) | shared workspace | 384 |
| `F_HW`, `F_HW2`, `F_HW3`, the half-widths by radius | bank 6 | 576 |

Measured and not taken (`6-harness/discmem`: `bench.sh` runs the disc
layer's scenes on a build, `cmp.py` and `perframe.py` compare two builds'
pixels byte for byte and their cycles frame by frame; a candidate had to
leave every frame of every scene no slower):

* The second disc's spans made again from its place and radius as each
  buffer drew it, instead of kept: 768 bytes of bank 5 for about 330 of
  bank 6's code, but frames where the second disc moves were 1,100 to 2,500
  cycles slower.
* The layer's spans made again the same way: 768 bytes, at about 25 cycles
  a row whenever the planet moves and a half-width table whenever its
  radius changes.
* One heap for all the discs' kept state: a close planet alone needs 1,920
  bytes in both buffers, and only the second disc could share it.
* Rows made as `R_DISCROWS` reads them: `PC_ROWS` walks each circle out from
  its centre row, so rows in order would need a rewrite of the circle
  engine, to save `R_NDN` and `R_NDX0-3` (960 bytes).
* The third and fourth boundaries only for the rows that have them: two
  craters side by side give such rows over a cap's height.

The ring is dots, explosions are particles, the hangar is rectangles and
lines, and the hyperspace and launch rings and the charts' circles are
lines. The one exception is the lens flare: its ghosts are dithered discs
and dotted rings ORed over the frame, marked dirty and repaired by the
layer the next frame on the buffer. An OR over whatever is under it has to
be redrawn wherever that changes, and it keeps nothing on the screen by
design.

## The hangar

The hangar, shown on docking, is one frame of the renderer:

* `HALL` stays in record mode and calls `G_HANG0`, which empties the frame's
  lists.
* `HAS1` places each ship as before and records it through `G_HLL9`.
* `G_HANGAR`, in place of `HANGER`, draws the frame with the hangar's
  background under the ships. The wall and the floor are flat tans (two
  yellow pixels, a magenta and a black or a cyan in each 2x2 cell), with
  `HANGER`'s grid lines in black, so the ships hide the grid where the
  original's lines stopped at them.

Two of the ships `HALL` can choose, the Sidewinder and the Mamba, are
dithered from the wall's own inks and blend into it. They are drawn as the
nearest ships of their size that stand out, an Asp Mk II and a Viper. Only
the blueprint drawn changes: `HALL` and `HAS1` run as before, with the same
random numbers. `HANGER`, `HAS2`, `HAL3`, `HAS3` and `DVID4K` are gone.

## The briefings

Mission 1's briefing shows the Constrictor turning, in view types 13 and 1.
The original draws it directly and erases it through its line heap.
`BRIEF`, `PAUSE` and `PAS1` call `LL9B` instead. `LL9B` sets `QQ11` to 0 while
`LL9` records the ship and `F_FRAME` draws it, then puts `QQ11` back, so
`QQ11` is the original's whenever game code reads it. The briefing's text,
printed outside record mode while the frames run, goes into the text map
(`H_CHAR`, `f_sync`), and the frames draw it.

With that, nothing draws a ship directly any more. `LL9`'s line drawing
(parts 9 to 11 and its line heap set-up), `LSPUT`, `LSCLR`'s erase and
`Shpt` are removed. Each original routine keeps its header with a
"Port: removed" note. The ship line heap's allocation stays, as it is game
state: a full heap stops `NWSHP`.

## Generated tables

Some of the renderer's sources are tables that tools in `2-build-files`
generate. They are checked in, and the build does not regenerate them; run
the tool again after changing it:

* `gfx-faces.asm` and `gfx-light6.asm` come from
  `python3 2-build-files/faces.py`, run after a build (it reads the build's
  `HZDATA.bin` and `symbols.txt`, the blueprints, which do not depend on the
  tables). It parses the 33 blueprints, rebuilds each face's polygon (faces
  that share a plane are merged when one of them has no closed outline of
  its own, as the Adder's back has; boundary vertices well off a face's
  plane that close a boundary of their own, the Cougar's wings, are left
  out of it and become fins), turns detail edges into filled details,
  fins and lines, finds each ship's symmetries, and gives the faces colours
  so that adjacent faces never match. It prints a report per ship. The
  game no longer assembles the blueprints' edge lists (the `EDGE` macro,
  `elite-data.asm`), so it takes each blueprint's edges from the released
  SNG47's data (`4-reference-binaries/sng47/BDATA.unprot.bin`), and asserts
  that the vertices, faces and normal scale there are the build's.
* `lightramps.py` is the lighting model that chooses the nine ramps and
  writes `gfx-light6.asm` (through `faces.py`); run alone, it renders the
  ramps (and, with `anim`, a tumbling preview of each ship) into
  `3-assembled-output/lighting`. `lightcheck.py` checks the 6502's lighting
  against the model over a run of `6-harness/mlight.mjs`.
* The hangar's inks come from `hangarcols.py`, which packs the panels'
  dithers into `HPWL`/`HPWH`, and `hangarinks.py`, which measured (with
  `6-harness/mhangar.mjs`'s screenshots) which ships blend into the
  hangar's tans.
* The lens flare's tables (`gfx-flare.asm`) come from `flare.py`, the model
  the 6502 code matches pixel for pixel (`--check` compares an emulator
  frame against it). `--tables` prints them (`fl_rad`, `fl_ink`, `fl_ni`,
  `fl_mt`, `fl_dk`, `fl_ring` and `fl_htab`, from its `GHOSTS`, `LADDER`,
  `BAYER`, `RING` and `hw_table`), and `--verify` checks the source's tables,
  and `fl_htab` as assembled into `MERID.bin`, byte for byte; the gate runs
  it after the build.

`2-build-files/dashboard.py` (with `swatch35.py`, the dither cells) does run
in the build. It draws the dashboard's image and writes its routines'
tables.

## Speed

The gate's run gives 10.29 flight iterations per emulated second, against
SNG47's 13.97 (0.736 times), with the frame rate capped at 25 frames a
second. Before the planets' circle engine it gave 11.82 (0.846 times, at
169,148 cycles a flight iteration); most of the difference is the crater
system's stretch of the run (iterations 800 to 2799), where two true caps
cost more than the polygon crater did. With the cap it first gave 11.73
(170,540 cycles); the disc layer's two boundaries a row and its short paths
for one-colour and emptied rows brought it to 11.82. Without the cap it gave
11.99 (0.858 times, 166,791 cycles), with a tenth of its frames shown for a
single field. With the speed-ups of the port's second part and the original's
wireframe drawing it is 17.86, and with plain disc planets in place of the
beach ball the renderer ran at 17.24 (115,992 cycles). So most of the cost
is the beach ball: its geometry and its two-colour disc rows, every frame
that a meridian planet is on screen, which is about half the gate's run, as
the pilot starts at Lave. Flight with no beach ball on screen runs as fast
as before. The big planet and the space station close up are the slowest
views, as their discs and faces cover most of the screen; the kept solid
rows speed up the station's last seconds.
