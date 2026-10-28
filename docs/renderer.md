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

* `LL9` records each ship. `EE31` jumps to `H_EE31`, which records the
  ship's projected vertices, its face visibility and its laser beam if it
  is firing at us. `SHPPT` records a distant ship's dot.
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
3. Per row, update the disc layer (the bigger of the planet and the sun,
   which is the nearer). From this buffer's old disc span, its old dirty
   extent and the new span, write the disc's colour where it is not
   already right, and black where something old is no longer covered. Then
   the second disc, the smaller and further one, where the layer leaves
   room (see "The sun near the planet").
4. Fill the ships far to near, each face a dithered polygon in its lit
   colour, with their details and fins. Then draw the lines and the
   particles. All of these extend this buffer's dirty extent for each row.
   A ship further away than the planet, with the first vertex of its first
   visible face inside the planet's disc, is not drawn (`f_behind`).
   `F_PLANET` records the planet's z for this as 16 bits; a planet 65536 or
   more away (z's third byte non-zero) is recorded as `&FFxx`, further than
   any ship drawn with faces (always nearer than 4096). Before that fix,
   only z's low 16 bits were kept, so a planet 65536-69631 away hid a
   station in front of it on a docking run (`6-harness/mstation.mjs`).
5. Draw the lens flare, if the sun is on screen (below).
6. Draw the text, in the cells whose character changed or whose pixels were
   drawn over, then the laser sights.
7. Plot the stars last, on black pixels only.
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
(`G_DIRECT`). The first frame afterwards goes back to double buffering
(`f_enter`). An in-system jump (`WARP`) keeps the space view on show
(`GWARP`). A disc command stashes HAZEL in buffer 0, so it sets `GSTASH`,
and the next frame in space mode starts buffer 0 afresh (`f_b0new`). The
title screen's ship and the escape pod are one frame each (`LL9F`).

## Where the renderer lives

| Part | Where | What |
|---|---|---|
| The shared workspace | main `&0E00-&1DED`, below the main code | the state that the rasteriser's banks, the frame layer, the game's hooks and the IRQ handler share: the per-call inputs, the dirty extents, the disc rows' boundaries, the stars and the kept solid rows' `KF`. Below `&3000`, so every bank sees it whatever ACCCON X is. `DFSST` and `DFSST2`, `DOSCLI`'s stash, are here too |
| Bank 4's end | after the hot pass and the hot data, bank 4 paged | the renderer's routines that run in game context, from `G_FRAME`: `S_SUN`, the sun near the planet (`gfx-ssun.asm`), and `L_SUN`, the light for the next iteration's ships (`gfx-light.asm`'s first pass) |
| The glue | the glue area, main RAM below `&3000` | the shared variables with initial values (`gfx-gvars.asm`), the `T_` trampolines from the frame layer into the rasteriser (`gfx-tramp.asm`), the text and IRQ hooks (`gfx-gluehooks.asm`), the `G_` stubs that page the frame layer in from game code (`gfx-gstubs.asm`) and the hooks in Elite's drawing code (`gfx-hooks.asm`) |
| The rasteriser's shared region | bank 5 `&9000-&BFFF`, paged with either window | the boundary arrays, `R_SETBUF`, the per-x tables, the 24 row-run pages at `&A000` (variables and small routines sit in their 65-byte tails), the stars, the second disc (`R_DISC2`), and the arithmetic and cold parts of both windows that use nothing of either window |
| The rasteriser's polygon window | ANDY `&8000-&8FFF`, ROMSEL `&85` | `R_POLY` (8-bit and 16-bit polygons) and `R_LINE` (lines, clipped exactly) |
| The rasteriser's disc window | bank 5 `&8000-&8FFF`, ROMSEL 5 | the disc rows, the dirty repair, `R_INIT`, `R_RESETBUF` |
| The frame layer | bank 6 | `gfx-frame.asm`, the ships' faces and colours (`gfx-faces.asm`), the lighting (`gfx-light6.asm`, and `L_REC` from `gfx-light.asm`; `L_SUN` is at bank 4's end), `frame_cold`, the flare's step and the hangar's frame. Then its state: the planet's and the sun's half-widths, the display list (`F_DL`, which holds `F_INIT` until the first frame), the text map and each cell's shown state |
| The hangar's tables | bank 6, at the end of its image | the floor's rows and the tans (`gfx-hangar6.asm`) |
| The meridian window | bank 7 after the cold pass, ROMSEL 7 (`MERID.bin`) | the planet's surface: the circle engine, `pc_circ` and `PC_ROWS` (`gfx-merid.asm`), and the styles, `PF_HOOK` (`gfx-planet7.asm`); then the kept solid rows' polygon part, `k_pre` and `k_settle` (`gfx-kept7.asm`); then the lens flare, `R_FLARE` and its tables (`gfx-flare.asm`) |

The two windows of bank 5 never call each other. The shared region refers to
neither, except where a line is marked. `bankcheck.py` checks this at every
build. ANDY is paged in only by the trampolines: `T_POLY` and `T_LINE` page
ROMSEL `&85`, and the rest page bank 5. The meridian window is paged in
only by its stubs, `G_PFHOOK`, `T_CAPS`, `T_KPRE` and `T_FLARE`. `&F4` always matches
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
* Stars are plotted on black pixels only and erased the next time.
* Every span extends its row's dirty extent for this buffer. The repair
  blacks the old extents that nothing new covers.

`6-harness/test_raster.py` runs every primitive on py65 against a
pixel-exact model, with this port's memory layout. It also checks that
nothing outside the screen, the rasteriser's memory and its zero page is
written. The gate runs it with `--quick`.

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

The disc layer already draws up to four boundaries a row. It keeps two of
them a row for each buffer (`R_BDN`, `R_BDP`, `R_BDX0`, `R_BDX1`), so that
the row's next change can be drawn as strips; a row with three or four is
stored as unknown (count `&80`), and its next change is repainted segment
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
frames, a sheet and a movie.

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

The gate's run gives 11.82 flight iterations per emulated second, against
SNG47's 13.97 (0.846 times), at 169,148 cycles a flight iteration, with the
frame rate capped at 25 frames a second. With the cap it first gave 11.73
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
