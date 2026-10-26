# The memory map

This is where the port puts each part of BBC Master Elite (SNG47) and of the
filled renderer, why it goes there, and how code in one region reaches
another. [master-memory.md](master-memory.md) covers the hardware: what the
MOS and DFS use, and which spare RAM the game may take.
[renderer.md](renderer.md) describes the renderer itself.

The original runs from main RAM `&1300-&7F48`, which includes the half of
main RAM that the shadow screen hides. It keeps its data (the ship
blueprints, the text tokens, the sine and arctan tables) in sideways RAM
bank 6. The port moves the code out of main RAM `&3000-&7FFF`, apart from
`&7000-&7FFF`, so that main `&4000-&6FFF` can be the second screen buffer.
It spreads the game over main RAM, sideways RAM banks 4 and 7, and HAZEL,
emitting the source in three passes: low (what must be below `&3000`), hot
(the rest of what runs with bank 4 paged) and cold (bank 7). The renderer
goes in banks 5 and 6 and ANDY, and in one window of bank 7 after the cold
pass, with its shared state and glue in main RAM below `&3000`. Every
routine of the game stays at its place in the original's source.

## The rules the layout follows

1. **ACCCON X.** With X = 1, shadow RAM appears at `&3000-&7FFF` and main
   RAM there is hidden. Code that runs with X = 1, and the data it reads,
   must not be in main `&3000-&7FFF`. That covers Master's drawing (the
   docked screens' text and lines, the dashboard, `PIX1`), `CHPR` and the
   frame layer. What they reach in main RAM is below `&3000`: the glue area
   (the text and IRQ hooks, `TTX66M`, the renderer's shared variables), the
   low pass (`CHPR` and its font, `cls`, `ZES1` and `ZES2`, `UP`), the
   dashboard's variables (`DASHV`, after `WP`) and the renderer's shared
   workspace. The hot code that runs with X = 1, and the tables it reads
   (Master's drawing, the CMYK dashboard, `ADDK` and the log tables), is
   tagged `Area: hot, ACCCON X`, and goes in bank 4, which X does not hide.
   The build asserts that the low pass ends below `&3000`. The game sets
   and clears X and E (bits 2 and 1) with `TSB` and `TRB`, as their
   comments always said, and the loader masks its writes, so ACCCON's
   bits 4 to 7 (ITU, the internal Tube, and IFJ) stay as the MOS set them.
2. **Interrupts and MOS vectors.** The IRQ arrives with any bank paged and
   with X either way. WRCHV (`CHPR`) and BRKV (`NEWBRK`) are entered with
   any ROM paged. Their handlers, and everything they touch, are in main RAM
   below `&3000`: the low pass (`IRQ1` and the sound code, `CHPR`, `NEWBRK`)
   and the glue area (the IRQ's `H_VSYNC`, the text hooks). They reach
   banked code only through stubs, which page the bank in and then page the
   caller's bank back. `NEWBRK` pages bank 4 itself first, and `CHPR`
   reaches `TTX66` through `TTX66M`, which keeps the caller's bank. No
   interrupt handler pages a bank.
3. **One sideways bank at a time.** Elite's home bank, bank 4, is paged
   whenever game code runs. So main RAM, HAZEL and bank 4 call each other
   and read each other's data directly: the low and hot passes, the glue
   area and the game data are one side, the hot side. The cold pass, in
   bank 7, is the other, and each routine that is called across the line
   has a stub of its own in the glue area ("Calls between the passes").
   Every other bank is reached through a stub that pages it in and pages
   the caller's bank back. `&F4` always matches ROMSEL.
4. **The renderer is in banks 5 and 6 and ANDY, and one window of bank 7.**
   ANDY (ROMSEL bit 7) overlays `&8000-&8FFF` of the paged bank:
   * ROMSEL `&85` is the rasteriser's polygon window: ANDY over bank 5,
     whose `&9000-&BFFF` is the rasteriser's shared region.
   * ROMSEL 5 is its disc window.
   * The frame layer is bank 6.
   * The meridian window is bank 7 after the cold pass: the beach ball
     planet's boundaries and the kept solid rows' polygon part, which need
     about 4K that none of the others has. Only their stubs page it in.
   Nothing calls between the two windows, and the shared region refers to
   neither. Each bank keeps its private tables. The state that more than one
   bank reads, or that the IRQ handler or code running with ACCCON X set
   reads, is the renderer's shared workspace, in main RAM below the main
   code.
5. **The game data is in HAZEL**, as far as it fits. HAZEL is visible
   whatever bank is paged. The data sits in the original's order from
   `XX21` at `&C000`. `NWSHP` reads past `E%`, to `E%-1,Y`, for the planet
   and the sun, into the missile's blueprint, as in the original, so the
   order matters. HAZEL holds nothing else. The hot data would flow on into
   bank 4, after the hot code; since the ships' edge lists went (nothing
   reads them, "Removed" below), all of it fits in HAZEL, `QQ18` (the
   recursive tokens, which the hot text printers read), `SNE` and `ACT`
   included.
6. **HAZEL and disc access.** DFS and the MOS overwrite parts of HAZEL
   during a disc command and keep lasting state there. `DOSCLI`, through
   which every OSCLI goes, stashes all of HAZEL in screen buffer 0 (main
   `&4000-&5FFF`). It puts the filing system's lasting bytes back,
   invalidates DFS's catalogue cache and copies the command to `&6000`. Then
   it makes the command and copies everything back
   ([master-memory.md](master-memory.md)). The next entry to space mode
   starts buffer 0 afresh. `&DF00-&DFFF` is the MOS's and holds no game
   data.
7. **The screen and the split.** Main `&4000-&6FFF` is screen buffer 0 and
   shadow `&4000-&6FFF` buffer 1. Shadow `&7000-&7DFF` is the dashboard.
   Main RAM under the dashboard (`&7000-&7FFF`) is never on show, as the
   split is never late ([renderer.md](renderer.md), "Dashboard split
   timing"). So it holds the quarter-square tables and the hot pass's
   second container. Code that
   must not be interrupted by the vsync handler masks only CA1 in the System
   VIA's IER. It never uses SEI, which would hold the split off.
8. **Page `&0D`** is never written, except by `DOSNMI`'s minimal NMI handler
   at `&0D00-&0D05`. The build asserts that nothing is assembled there.

## The source and its passes

`elite-source.asm` is Mark Moxon's main source in the original's order, and
`elite-data.asm` is his data source. The build emits the game source in
three passes, **low**, **hot** and **cold**, and each routine or table's
header names its pass:

    \       Name: TT219
    \       Type: Subroutine
    \   Category: Market
    \    Summary: Show the Buy Cargo screen (red key f1)
    \       Area: cold

* **`Area: low`** is the low pass: Elite's code that must be in main RAM
  below `&3000` (rules 1 and 2). A block is low if it runs with shadow RAM
  paged and is not in bank 4, if the IRQ or a MOS vector reaches it with
  any bank paged, if such code reads it, or if it falls or branches into a
  block that must be low. That is the IRQ and the sound code it calls,
  `CHPR` and what it uses (`cls`, `ZES1`, `ZES2`, `TT67K`, the font, `UP`),
  `stackpt` and `NEWBRK` (BRKV), and the small routines that the cold pass
  calls directly (`WSCAN`, `DELAY`, `BOOP`, `SOFLUSH`, `DOVDU19`): 29
  blocks.
* **No Area field** (or `Area: hot`) is the hot pass: the rest of the game
  code, which runs with bank 4 paged. It flows through main RAM and then
  bank 4 (below). **`Area: hot, ACCCON X`** is hot code that runs with
  ACCCON X set, and the tables it reads: Master's drawing for the docked
  screens' text and lines (`ylookup`, `LOIN`, `HLOIN`, `PIX1`, `PIXEL`,
  `TTX66`, `CLYNS`), the CMYK dashboard (`SCAN`, `DOT`, the bulbs, `MSBAR`,
  `DIALS` and its helpers), `ADDK` and the log tables. These go in bank 4.
  The hot pass has 347 blocks, 41 of them ACCCON X.
* **`Area: cold`** is the cold pass, sideways RAM bank 7 from `&8000`. This
  is code that runs on docked screens or a few times a flight: the docked
  screens, the extended tokens, the charts, the market, equipment, the title
  and start-up, save and load, launch, docking and hyperspace, the missions.
  161 blocks.
* **`, runs on`** after any of these marks a table that code reads past its
  end, so that the next block must follow it, as a fall-through would.
  `TKN2` is `Area: hot, runs on`: `DETOK2` reads the pairs of tokens
  228-255 in `QQ16`, which follows it.

In `elite-data.asm`, untagged blocks are the hot data, `Area: cold` is the
extended tokens (bank 7, after the cold code), and `Area: BDATA` is the
dashboard image (`2-build-files/dashboard.py` draws it).

**The containers.** Each pass goes into its containers in the source's
order. From the shared workspace up, memory is:

* main RAM from `CODE%`: the **glue area** (`elite-glue.asm`), the port's
  own code: the stubs between the passes (`elite-stubs.asm`), the
  renderer's shared variables, the `T_` trampolines, the text and IRQ
  hooks, the `G_` stubs and the drawing hooks. Then the **low pass**, which
  must end below `&3000` (`LOW_END%`). `CODE%` is chosen so that the font
  starts a page with no padding;
* the hot pass's first container, main RAM from `LOW_END%` to `&4000`;
* the quarter-square tables (`elite-qs.asm`, `&7000-&73FF`), then the hot
  pass's second container, main RAM from `&7400` to `&8000`;
* the hot pass's third container, bank 4 from `&8000`: the ACCCON X blocks
  first, as they come first in the source, then the rest; then the hot data
  that HAZEL has no room for;
* HAZEL from `&C000`: the hot data;
* the cold pass, bank 7 from `&8000`: the cold code, then the cold data.
  The meridian window follows it.

**The flow.** The hot pass is cut into units: runs of blocks that must stay
together, because one falls through into the next (its last statement can
continue, or is a BIT skip, `EQUB &2C` or `&24`), branches into another, or
runs on into the next. In the source's order, each unit goes into the
container the flow has reached if it fits, and otherwise into the next one.
So each container holds its units in the source's order, and no hand-placed
marker says where one container ends. An ACCCON X unit goes into bank 4
wherever the flow is. A block that aligns itself (the log tables' `ALIGN
&100`) is placed at the next boundary, and the padding is counted in its
container. The hot data flows the same way, through HAZEL and then bank 4.

The sizes are measured, not estimated. The Makefile runs
`2-build-files/streams.py` twice. `streams.py measure` writes the hot pass
as one copy, with a label `FLOW_<n>` at each block, and the hot data as
another, and `elite-measure.asm` assembles them past the containers' limits
for each block's size (`3-assembled-output/measure-symbols.txt`).
`streams.py place` then flows the units by those sizes. A block's size does
not depend on where it goes. `3-assembled-output/flow.txt` lists every
container and its units.

**The copies.** BeebAsm assembles with one location counter, and banks 4
and 7 share the addresses `&8000-&BFFF`. So `streams.py` writes one copy of
`elite-source.asm` per container into `3-assembled-output`, with the other
lines blanked so that line numbers stay the source's:
`elite-source-config.asm` (the configuration and the workspaces), `-low`,
`-hot1`, `-hot2`, `-hot3` and `-cold`. It does the same for
`elite-data.asm`: `elite-data-hot.asm` (HAZEL), `-hot4` (bank 4), `-cold`
and `-bdata`. `elite-layout.asm`, the file that the Makefile assembles,
INCLUDEs the copies in turn, each at its own address. Each label is defined
once and each block is assembled once.

**Checks at every build.** `streams.py` checks that each block's IF ...
ENDIF nesting is balanced and that every unit fits a container. A block
that can fall through its end must be followed by a block of its own pass,
or by a block of the other side whose first statement is its entry label (a
seam, below). No other fall-through or branch crosses the hot/cold line,
and the hot side refers to a cold label only to call it, jump to it or take
its address, as a stub has no data. Then `2-build-files/bankcheck.py`
checks every reference in the copies (below).

## Calls between the passes

The hot side calls and reads itself directly, as bank 4 is paged whenever
game code runs, and the cold pass calls and reads itself directly. Every
call from one side to the other goes through a stub of its own, one per
target, in the glue area (main RAM below `&3000`, seen with either bank
paged). `streams.py` writes the stubs (`3-assembled-output/elite-stubs.asm`,
which `elite-stubs.asm` includes). The source calls everything by the
original's names: in the cold copy, `streams.py` renames each cold label
`X` to `X_C`, and turns each call from cold code to hot code `H` into a
call of `x4_H`.

    .TT22                     the hot side calls cold TT22 by its name
     JSR to7                  page bank 7 in, A and the flags kept
     JSR TT22_C               the routine, in the cold pass
     JMP to4                  page bank 4 back, A and the flags kept, and return

    .x4_LL5                   the cold pass calls hot LL5 through x4_LL5
     JSR to4
     JSR LL5
     JMP to7

    .TT170                    a jump, for a routine that never returns
     JSR to7                  (TT170, BAY, DEATH2; j4_BEGIN, j4_GOIN, j4_FRCE)
     JMP TT170_C

A stub knows its caller's bank. Every caller of a stub into the cold pass
runs with bank 4 paged (`NEWBRK`, which the MOS enters with any ROM paged,
pages bank 4 first), and every caller of a stub out of it runs with bank 7
paged. So a stub keeps no frame: the routine sees only the stub's return
address above its caller's. A, X, Y and the flags pass both ways. `to7` and
`to4` write `&F4` before ROMSEL. The one stub that keeps the caller's bank
is `TTX66M`, for `CHPR`, written by hand in `elite-stubs.asm`. A call
through a stub costs 85 cycles more than a JSR; the generic far calls that
the stubs replaced, which read the target's address through the stack and
kept the caller's bank there, cost about 171.

The cold pass calls the low pass's routines that need nothing of the hot
side directly, with no stub: `BEEP`, `BOOP`, `CHPR`, `DELAY`, `DOVDU19`,
`NOISE`, `SOFLUSH`, `TT67K` and `WSCAN` (listed in
`3-assembled-output/direct.txt`).

A routine that falls through into a routine of the other side falls into a
seam: a JMP to that routine's stub, at the routine's place. The stub calls
the routine, which returns to the falling routine's caller with the
caller's bank back, just as the fall-through did. There are five: `RES2`
into `ZINF`, `SOLAR` into `NWSTARS`, `LAUN` into `HFS2` and `TTX69` into
`TT69` (cold into hot), and `BEGIN` into `TT170` (hot into cold, a jump).
The harness (`mlib.mjs`) sees through a stub to its caller by the stub's
address range.

| Kind | Where | Count | Pages |
|---|---|---:|---|
| stubs into the cold pass (`.TT22`; `STUBS7`) | the glue area | 38 | bank 7 in, then bank 4 back |
| stubs out of the cold pass (`.x4_LL5`, `.j4_BEGIN`; `STUBS4`) | the glue area | 57 | bank 4 in, then bank 7 back |
| `TTX66M` | the glue area (`elite-stubs.asm`) | 1 | bank 4 in, then the caller's bank back |
| `G_` stubs | the glue area (`gfx-gstubs.asm`; `G_CHAR`, `G_DELCHAR` and `G_CLRTEXT` in `gfx-gluehooks.asm`) | 16 | bank 6 in (bank 7 for `G_MERHOOK`, the meridian window), then bank 4 back (or the caller's bank, for the text stubs) |
| `T_` trampolines | the glue area (`gfx-tramp.asm`) | 13 | the rasteriser in (ROMSEL `&85` for `T_POLY` and `T_LINE`, bank 5 for most of the rest) or the meridian window (bank 7, for `T_MERID` and `T_KPRE`), then bank 6 back |

**Which side a routine is on** is measured: for each cold block, the calls
across the line that moving it hot would remove and the calls it would
create, counted over the gate's run. The text printers (`TT27`, `ex`,
`BPRNT`, `MESS` and their helpers) and the tables they read (`QQ18`,
`QQ16`) are hot, so they call `TT26` directly. The extended-token printer
`DETOK` stays cold, as its 3.5K of tables do not fit bank 4. What would
make more crossings than it removes stays cold too: `TT20` and `TT54`,
which the charts call 256 times a screen, and `TT111`, which calls them.
The gate's run makes 0.015 crossings per flight iteration and 3,738 off
flight, against 0.703 and 11,455 when every crossing was a far call (98% of
them `x4_TT26`, from the cold text printers).

The `G_` and `T_` stubs are the renderer's hot path by design.
`bankcheck.py` checks the rules for every reference: branches never cross
areas; each side reaches the other only through stubs (the cold pass may
also call the low labels in `direct.txt`, which must be below `&3000`), and
never reads the other's data; the renderer's banks are entered only through
their stubs or by address, call nothing in another bank, and read main RAM
only below `&3000`. A deliberate exception is marked `bankcheck: ok` on its
line.

## The map

| Region | Addresses | What |
|---|---|---|
| Zero page, stack, `K%` | `&0000-&00E3`, `&0100-&01FF`, `&0400-&07FF` | as in the original |
| `WP` | main `&0841-&0CCE` | Elite's workspace, the original's `&0E41-&12A9` moved down by `&600` (each byte keeps its place in its page), with the commander file buffer `commbuf` (`LSX2`) at `&087E`; then the CMYK dashboard's variables (`DASHV`), as the dashboard runs with ACCCON X set, and `VEC` (`&0CCF`), the configuration's last block |
| The shared workspace | main `&0E00-&1DD4` | the renderer's shared state, one block below the main code: the rasteriser's per-call inputs (the polygon edge tables share the disc spans' places), the stars, `DFSIN` and `DOSCLI`'s stash in two halves (`DFSST`, `DFSST2`), the dirty extents, the disc rows' boundaries, the kept solid rows' `KF` and the directly drawn stars' sizes `F_DSS` (`elite-gfx.asm`) |
| The glue area | main from `CODE%` (`&1E16`) to `&2868` | `elite-glue.asm`, the port's own code: `to7` and `to4`, `TTX66M` and the stubs between the passes (`elite-stubs.asm`: `STUBS7`, 38 into the cold pass, and `STUBS4`, 57 out of it), then the renderer's glue (`gfx-gvars.asm`, `gfx-tramp.asm`, `gfx-gluehooks.asm`, `gfx-gstubs.asm`, `gfx-hooks.asm`) |
| The low pass | main `&2869-&2E48`, below `&3000` (`LOW_END%`) | Elite's code that must be below `&3000`, in the source's order: `WSCAN`, `DELAY`, the sound (`BOOP`, `BEEP`, `SOFH` ... `SOINT`, the sound variables and tables), `IRQ1`, `VSCAN`, `DOVDU19`, `cls`, `TT67K`, `CHPR`, `ZES1`, `ZES2`, the font (page aligned at `&2B00`: `CODE%` is chosen so that this pads nothing), `UP`, `stackpt`, `NEWBRK` |
| The hot pass, in main RAM | main `&2E49-&3F92` (BCODE ends here) | the hot pass's first container: `T1SYNC`, `pxpatd`, `pxpat`, `HANGFLAG`, `G%`, the main flight loop, `MALW`, `MALC`, `MT14`, `MT15`, `TKN2` and `QQ16`, `NA%`, `UNIV`, `BLINE`, the stardust, `TENS`, `pr2`, `TT11`, `BPRNT`, `TT26`, `ESCAPE`, `HALL`, `HAS1` and more, in the source's order |
| Buffer 0 | main `&4000-&6FFF` | the screen; during a disc command, HAZEL's stash and the command |
| The quarter-square tables, then the hot pass | main `&7000-&7F3D` | `QSL` and `QSH` (`elite-qs.asm`, page aligned at `&7000`), then the hot pass's second container from `&7400`: `TACTICS`, `DOCKIT`, the tactics helpers, `HITCH`, `FRS1`, `FRMIS`, `ANGRY`, `FR1`, `SESCP`, `SFS1`, `SFS2`, `HFS2`, `STARS2`, and the maths from `MLS2` to `DVID3B2` |
| Bank 4 | `&8000-&B8C5` | the hot pass's third container. First the ACCCON X blocks (`&8000-&9089`): Master's drawing for the docked screens (`ylookup`, `LOIN`, `HLOIN`, `PIX1`, `PIXEL`, `TTX66`, `CLYNS` and their tables), the CMYK dashboard (`SCAN`, `DOT`, `ddot`, the bulbs, `MSBAR`, `DIALS` and its helpers, with the tables `dashboard.py` writes) and `ADDK`, then `log`, `logL` and `alogh`, page aligned at `&9100-&93FF`. Then the rest of the hot pass in the source's order, to `F%` (`&B8C6`): among it the text printers (`TT27` ... `ex`), the planet and the sun, the main game loop, `MESS`, the ships' drawing and moving. Then any hot data that HAZEL has no room for (none) |
| Bank 7, the cold pass | `&8000-&A660` | the cold blocks of `elite-source.asm` in its order (the start-up, the extended token printer `DETOK`, the docked screens, the charts and the market, hyperspace, the equipment, the title, save and load, `DOSCLI` ...), then the extended tokens |
| Bank 7, the meridian window | `&A661-&B577` (its own image, `MERID`) | the beach ball planet's boundaries (`gfx-merid.asm`: `PM_HOOK`, `PM_MERID` and their workspace), then the kept solid rows' polygon part (`gfx-kept7.asm`: `k_pre`, `k_settle`) |
| ANDY, the rasteriser's polygon window | `&8000-&8FDA` (ROMSEL `&85`) | `R_POLY` and `R_LINE` (`gfx-raster_poly.asm`, `gfx-raster_line.asm`) |
| Bank 5, the rasteriser | `&8000-&8F2F` (ROMSEL 5), `&9000-&BF94` | the disc window (`gfx-raster_disc.asm`, then the kept solid rows' part, `gfx-raster_kept.asm`); the shared region (`gfx-raster.asm`: the boundary arrays, `R_SETBUF`, the per-x tables, the 24 row-run pages at `&A000`, the stars; `gfx-flare.asm`; `gfx-raster_lcold.asm`; then the rasteriser's private state, `R_PRBUF` to `R_PRCWB`) |
| Bank 6, the frame layer | `&8000-&BFF9` | `gfx-frame.asm`, `gfx-faces.asm`, `gfx-light6.asm`, `gfx-light.asm`, `gfx-frame_cold.asm`, `gfx-flare6.asm`, `gfx-hangar.asm`; then its state: the half-widths, the display list (with `F_INIT`, `gfx-finit.asm`), the text map, the cells' shown states and the directly drawn stars; then the hangar's tables (`gfx-hangar6.asm`), which only `f_hback` reads |
| HAZEL | `&C000-&D780` | the hot data in the original's order: `XX21`, `E%`, `KWL%`, `KWH%`, the blueprints (without their edge lists), `QQ18`, `SNE`, `ACT`. `&DF00-&DFFF` is the MOS's |
| Shadow `&3000-&3FFF` | `&3090-&30FF` | the zero-page save (`setzp`, `getzp`), as in the original; nothing else |
| Buffer 1, the dashboard | shadow `&4000-&7DFF` | the screen |

Where each of the hot pass's containers ends is the flow's: the first unit
that does not fit goes on to the next container. `TACTICS`, whose seven
parts branch into one another and so move as a whole, leads the second.
`3-assembled-output/flow.txt` lists every unit.

Free space: 109 bytes below `&4000` and 194 below `&8000` (each the end of
one of the hot pass's containers in main RAM), 1,850 at the end of bank 4,
2,696 at the end of bank 7, 1,919 in HAZEL, 208 and 107 in bank 5 (and 808
below the per-x tables, freed when the disc layer went to two boundaries a
row, and 256 in the row runs' tails), 37 in ANDY, 6 in bank 6 (12 before the depth
test's fix to the planet's z), and 48 and 105 in `WP`'s
pages and the shared workspace, with 65 more between it and the main code
(79 before the 25 fps cap's 14 bytes in the glue area: `CODE%` moved down
from `&1E24` to `&1E16` to keep the font page aligned, so nothing after the
glue area moved).

The three passes cost 373 free bytes outside shadow RAM. The stubs between
the passes are 884 bytes, against the far calls' 184, all in the glue area
below `&3000`. The low pass gave the room: the original's code that the
earlier layout kept below `&3000` (`VEC` to `UP`, with `stackpt` and
`NEWBRK`: 2,413 bytes) became the low pass's 1,504, and the hot pass starts
after it. Aligning the log tables in bank 4 costs 140 bytes. The
text printers and the routines that crossed most moved from bank 7 into the
hot pass (bank 7's free space grew from 89 bytes to 2,700, and bank 4's
fell from 3,853 to 810), and `SNE` and `ACT` followed `QQ18` into bank 4
(HAZEL's free space grew from 283 to 363). Dropping the ships' edge lists
(2,596 bytes) brought `QQ18`, `SNE` and `ACT` back into HAZEL: HAZEL now
has 1,919 bytes free and bank 4 1,850.

The code moved, so the page crossings moved too. `6-harness/profile.mjs
--pagex` counts 1,108 cycles a flight iteration in page crossings, against
1,140 before the three passes, and 1,421 off flight, against 1,697. No
alignment pass has been made: nothing is padded to save a crossing.

## The loader

The loader (`M128Elt`, at `&0E00`, as in the original) first checks that
sideways banks 4 to 7 are RAM. It sets up the screen as the original does,
with the CMYK palette. It disables ESCAPE as the original does, but with
`*FX 200,3` rather than `*FX 200,1`, so that BREAK clears memory as a
power-on reset does: BREAK then reaches BASIC and SHIFT-BREAK boots the
game again. With memory kept, the MOS's reset hung with a garbled screen,
most likely on its own workspace in ANDY and HAZEL, which the rasteriser
and the game's data now hold. Then it loads each file to `&1300` and copies it into
place, using its table `FTAB`:

* BDATA, the dashboard image, goes to shadow `&7000-&7DFF`.
* BANK4 goes to bank 4, and COLD7 and MERID to bank 7.
* RASTA goes to ANDY (ROMSEL `&85`).
* BANK5 goes to bank 5 and BANK6 to bank 6.
* HAZEL is staged at main `&4000`.
* HICODE goes to main `&7000-&7FFF`.

Then it loads BCODE (the glue area, the low pass and the hot pass's first
container) to its address (`&1E16`) and changes directory to E. The
loader is in the shared workspace's place, so its last part runs from `K%`
(`&0400`), where it is copied first. That part takes DFS's and the MOS's
lasting bytes into `DFSST` and `DFSST2`, copies HAZEL into place, quietens the 1770 and
installs the minimal NMI handler, and resets the non-filing-system vectors
to the MOS's defaults. Then it calls `G_INIT`, which sets up the renderer's
state, and starts the game at `S%`. `S%` is in the cold pass, and the loader
takes its address and bank from the game's symbols
(`3-assembled-output/game-addresses.asm`, from `layout-info.py`).

## What is not in the original's order

* **The passes.** Memory follows the source's order within each pass and
  container, not across them. The low pass comes first. The hot pass's
  ACCCON X blocks lead bank 4, as they come early in the source but cannot
  be in main RAM. The cold pass is apart. The low pass holds the original's
  code from `WSCAN` to `UP`, less `T1SYNC`, `pxpatd`, `pxpat` and
  `HANGFLAG` (now hot) and `ADDK` and the log tables (hot, ACCCON X), with
  `stackpt` and `NEWBRK` at its end. `VEC`, the one variable before
  `WSCAN`, goes with the configuration, after `DASHV` in `WP`'s page
  (`&0CCF`).
* **Stubs and seams.** The stubs between the passes are in the glue area.
  `streams.py` generates them; they are not in the source. The original's
  fall-throughs that cross the hot/cold line fall into a JMP to the stub at
  the next routine's place (`RES2` into `ZINF`, `SOLAR` into `NWSTARS`,
  `LAUN` into `HFS2`, `TTX69` into `TT69`, `BEGIN` into `TT170`).
* **Port routines next to the routine they serve.** These are `ddot` (at
  `CPIXK`'s place), `DILI` and `DSEG` (after `DIL2`), `pxpatd` and `pxpat`
  (before `PIX1`), `MALW` and `MALC` (after part 6 of the main flight
  loop), `DVL9a` (after `DVID4`), `PLL4F` and `pl4pat` (after `PLS22`),
  `LL9F`, `LL9B` and `LL51L` (after `LL51`), `QQ18IX` (after `ex`) and
  `T1SYNC` (after `VSCAN`). `DOSCLI` and `DOSNMI` are at the end of the cold code.
* **Changed for the layout.** A few short branches into a routine that is
  now in another pass return through their own `RTS` instead (`DOEXP`,
  `YESNO`, `ANGRY`, `SIGHT`). `getzp` no longer pages bank 6 in. `NEWBRK`
  is the original with three lines that page bank 4 in, and a call of
  `DOSNMI`. `CHPR` reaches `TTX66` in bank 4 through `TTX66M`, as it runs
  as WRCHV with any ROM paged. The log tables align themselves (`ALIGN
  &100`), as they no longer follow the three-page font. `JMTB` names its
  hot targets' stubs (`x4_TT27`, `x4_MT14`, `x4_MT15`, `x4_DASC`, `x4_MT16`,
  `x4_CLYNS`). `TKN2` runs on into `QQ16`.
* **Removed.** The original's unreachable code and unused tables, and
  Master's direct drawing of ships, which nothing uses any more. Each
  original routine keeps its header with a "Port: removed" note. The ships'
  edge lists are not assembled either (the `EDGE` macro assembles nothing,
  with a "Port:" note): every ship is drawn from its faces, and a read
  watch over the gate's run, the title's ships, the briefings, docking with
  the hangar, the escape pod, death and redocking found no game code
  reading them. The blueprints' headers, their edge counts and offsets
  included, are as they were.
* **Port additions outside the source**, each in its own file with a header
  saying why: the glue area (`elite-glue.asm`, with the stubs,
  `elite-stubs.asm`), the quarter-square tables (`elite-qs.asm`), the layout
  (`elite-layout.asm`, and `elite-measure.asm`, which measures the hot
  pass) and the renderer (`elite-gfx.asm` and the `gfx-*.asm` files).
* **Placement by the build, not the source.** `CODE%` is chosen so that the
  font starts a page with no padding, and the containers are filled by the
  flow, not by markers.
