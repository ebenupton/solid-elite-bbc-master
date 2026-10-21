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
(`gfx-hooks.asm`, `gfx-lowhooks.asm`). Each hook records what the routine
would have drawn, then returns from the routine itself:

* `LL9` records each ship. `EE31` jumps to `H_EE31`, which records the
  ship's projected vertices, its face visibility and its laser beam if it
  is firing at us. `SHPPT` records a distant ship's dot.
* `CIRCLE` records the planet's disc. Each meridian and crater curve starts
  a new curve (`H_PCURVE`), and `BLINE` records its points. `SUN` records
  the sun's half-widths.
* `PIXEL2` records a star and `PIXEL` an explosion particle. `PIX1` no longer
  erases a star's old position, a choice that `pxpat` patches once per star
  pass.
* `LASLI` (our lasers), `BOMBOFF` (the energy bomb's lightning) and `SIGHT`
  (the laser sights) record their lines.
* `CHPR` and `CLYNS` keep a 32x24 **text map** of the characters on screen,
  in record mode and outside it.

The launch and hyperspace rings are drawn directly, even in record mode
(`HFS2` sets `GFORCE`). Outside record mode every hook returns at once, so the
docked screens are drawn as before, into shadow RAM, which is then on show
all frame (direct mode).

At the end of each flight iteration, `H_MFRAME` (after `M%`, in `TT100` and
`DEATH`) runs the frame layer's `F_FRAME`. It renders the records into the
back buffer, two frames old:

1. Wait until the previous flip has happened.
2. Erase this buffer's old stars, which were plotted only on black pixels.
3. Per row, update the disc layer (the planet or the sun). From this
   buffer's old disc span, its old dirty extent and the new span, write the
   disc's colour where it is not already right, and black where something
   old is no longer covered.
4. Fill the ships far to near, each face a dithered polygon in its lit
   colour, with their details and fins. Then draw the lines and the
   particles. All of these extend this buffer's dirty extent for each row.
5. Draw the lens flare, if the sun is on screen (below).
6. Draw the text, in the cells whose character changed or whose pixels were
   drawn over, then the laser sights.
7. Plot the stars last, on black pixels only.
8. Request a flip at the next vsync. `H_VSYNC`, from `IRQ1`, shows the
   front buffer.

Because each buffer repairs only its own dirty rows, a frame costs what
changed, not the whole screen.

`TTX66`, which clears the screen for a new view, enters direct mode
(`G_DIRECT`). The first frame afterwards goes back to double buffering
(`f_enter`). An in-system jump (`WARP`) keeps the space view on show
(`GWARP`). A disc command stashes HAZEL in buffer 0, so it sets `GSTASH`,
and the next frame in space mode starts buffer 0 afresh (`f_b0new`). The
title screen's ship and the escape pod are one frame each (`LL9F`).

## Where the renderer lives

| Part | Where | What |
|---|---|---|
| The shared workspace | main `&0E40-&1EDB`, below the main code | the state that the rasteriser's banks, the frame layer, the game's hooks and the IRQ handler share: the per-call scratch, the dirty extents, the disc rows' boundaries and the stars. Below `&3000`, so every bank sees it whatever ACCCON X is. `DFSST`, `DOSCLI`'s stash, is here too |
| The glue | the low area, main RAM below `&3000` | the shared variables with initial values (`gfx-gvars.asm`), the `T_` trampolines from the frame layer into the rasteriser (`gfx-tramp.asm`), the text and IRQ hooks (`gfx-lowhooks.asm`), the `G_` stubs that page the frame layer in from game code (`gfx-gstubs.asm`) and the hooks in Elite's drawing code (`gfx-hooks.asm`) |
| The rasteriser's shared region | bank 5 `&9000-&BFFF`, paged with either window | the boundary arrays, `R_SETBUF`, the per-x tables, the 24 row-run pages at `&A000` (variables and small routines sit in their 65-byte tails), the stars, the lens flare, and the arithmetic and cold parts of both windows that use nothing of either window |
| The rasteriser's polygon window | ANDY `&8000-&8FFF`, ROMSEL `&85` | `R_POLY` (8-bit and 16-bit polygons) and `R_LINE` (lines, clipped exactly) |
| The rasteriser's disc window | bank 5 `&8000-&8FFF`, ROMSEL 5 | the disc rows, the dirty repair, `R_INIT`, `R_RESETBUF` |
| The frame layer | bank 6 | `gfx-frame.asm`, the ships' faces and colours (`gfx-faces.asm`), the lighting (`gfx-light6.asm`, `gfx-light.asm`), `frame_cold`, the flare's step and the hangar's frame. Then its state: the planet's and the sun's half-widths, the display list (`F_DL`, which holds `F_INIT` until the first frame), the text map and each cell's shown state |
| The hangar's tables | HAZEL, after the game data | the floor's rows and the tans |

The two windows of bank 5 never call each other. The shared region refers to
neither, except where a line is marked. `bankcheck.py` checks this at every
build. ANDY is paged in only by the trampolines: `T_POLY` and `T_LINE` page
ROMSEL `&85`, and the rest page bank 5. `&F4` always matches ROMSEL.

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
* Stars are plotted on black pixels only and erased the next time.
* Every span extends its row's dirty extent for this buffer. The repair
  blacks the old extents that nothing new covers.

`6-harness/test_raster.py` runs every primitive on py65 against a
pixel-exact model, with this port's memory layout. It also checks that
nothing outside the screen, the rasteriser's memory and its zero page is
written. The gate runs it with `--quick`.

## Lighting

The sun is the light source in flight. `L_SUN`, once per frame, keeps the
light's direction. It is reseeded from the sun's position every 32
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

When the sun is on screen in the front view, and not behind the planet, the
frame draws eight ghosts along the line from the screen's centre through
the sun: six dithered discs and two dotted rings. They are ORed in their
inks, so the light adds up. Three levels of brightness depend on how far the
sun is from the centre. The flare extends each row's dirty extent, so the
next frame on the buffer repairs it like any other shape. It never touches
game state. `f_flt` (bank 6) makes the tests and `R_FLARE` (bank 5) draws.

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
  tables). It parses the 33 blueprints, rebuilds each face's polygon, turns
  detail edges into filled details, fins and lines, finds each ship's
  symmetries, and gives the faces colours so that adjacent faces never
  match. It prints a report per ship.
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
  frame against it).

`2-build-files/dashboard.py` (with `swatch35.py`, the dither cells) does run
in the build. It draws the dashboard's image and writes its routines'
tables.

## Speed

The gate's run gives 17.24 flight iterations per emulated second, against
SNG47's 13.97 (1.234 times). With the speed-ups of the port's second part
and the original's wireframe drawing it is 17.86. So the renderer, net of
the wireframe drawing it replaces, costs about 4,022 cycles a flight iteration
(115,992 against 111,970). The big planet and the space station close up are the
slowest views, as their discs and faces cover most of the screen.
